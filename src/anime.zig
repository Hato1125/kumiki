const std = @import("std");

pub const Curve = union(enum) {
    linear,
    ease_in,
    ease_out,
    ease_in_out,
    bezier: [4]f32,
    spring: Spring,

    // Maps progress in [0, 1] onto the curve. Beziers and springs may overshoot.
    pub fn apply(curve: Curve, t: f32) f32 {
        return switch (curve) {
            .linear => t,
            .ease_in => t * t * t,
            .ease_out => 1 - std.math.pow(f32, 1 - t, 3),
            .ease_in_out => if (t < 0.5) 4 * t * t * t else 1 - std.math.pow(f32, 2 - 2 * t, 3) / 2,
            .bezier => |p| bezierAt(p, t),
            .spring => |s| if (t >= 1) 1 else s.position(t * s.settleTime()),
        };
    }
};

// One coordinate of a cubic bezier from 0 to 1 with inner control points a, b.
fn bezierCoordinate(a: f32, b: f32, s: f32) f32 {
    const r = 1 - s;
    return 3 * r * r * s * a + 3 * r * s * s * b + s * s * s;
}

// x grows with the curve parameter, so bisection finds where x equals t.
fn bezierAt(p: [4]f32, t: f32) f32 {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    var low: f32 = 0;
    var high: f32 = 1;
    for (0..24) |_| {
        const middle = (low + high) / 2;
        if (bezierCoordinate(p[0], p[2], middle) < t) low = middle else high = middle;
    }
    return bezierCoordinate(p[1], p[3], (low + high) / 2);
}

// A unit mass on a spring, released at rest one unit away from where it
// settles. `damping` is the damping ratio: below 1 the mass bounces.
pub const Spring = struct {
    damping: f32 = 1,
    stiffness: f32,

    const tolerance = 0.001;

    // How far the mass has come after `t` seconds: 0 at the start, 1 at rest.
    pub fn position(s: Spring, t: f32) f32 {
        const frequency = @sqrt(s.stiffness);
        const ratio = s.damping;
        const decay = ratio * frequency;
        if (ratio < 1) {
            const damped = frequency * @sqrt(1 - ratio * ratio);
            return 1 - @exp(-decay * t) * (@cos(damped * t) + decay / damped * @sin(damped * t));
        }
        if (ratio == 1) return 1 - @exp(-frequency * t) * (1 + frequency * t);
        const root = frequency * @sqrt(ratio * ratio - 1);
        const slow = root - decay;
        const fast = -root - decay;
        return 1 - (fast * @exp(slow * t) - slow * @exp(fast * t)) / (fast - slow);
    }

    // Seconds until the mass stays within `tolerance` of rest. At critical
    // damping, (1 + x) * exp(-x) falls below the tolerance at x = 9.2334.
    pub fn settleTime(s: Spring) f32 {
        const frequency = @sqrt(s.stiffness);
        const ratio = s.damping;
        const decades = -@log(@as(f32, tolerance));
        if (ratio < 1) return decades / (ratio * frequency);
        if (ratio == 1) return 9.2334 / frequency;
        return decades / (frequency * (ratio - @sqrt(ratio * ratio - 1)));
    }
};

pub const Animation = struct {
    duration: f32 = 0.25,
    curve: Curve = .ease_in_out,

    // Follows a spring for as long as it takes to settle.
    pub fn spring(damping: f32, stiffness: f32) Animation {
        const s: Spring = .{ .damping = damping, .stiffness = stiffness };
        return .{ .duration = s.settleTime(), .curve = .{ .spring = s } };
    }

    // `points` are the x1, y1, x2, y2 of a CSS cubic-bezier().
    pub fn bezier(duration: f32, points: [4]f32) Animation {
        return .{ .duration = duration, .curve = .{ .bezier = points } };
    }
};

pub fn Tween(comptime T: type) type {
    return struct {
        from: T,
        to: T,
        start: f64 = 0,
        running: bool = false,

        const Self = @This();

        pub fn init(value: T) Self {
            return .{ .from = value, .to = value };
        }

        // Starts moving from the currently shown value toward `next`. An
        // equal target is taken too, because it may hold newer strings.
        pub fn retarget(tween: *Self, spec: Animation, next: T, now: f64) void {
            if (!same(T, next, tween.to)) {
                tween.from = tween.at(spec, now);
                tween.start = now;
                tween.running = true;
            }
            tween.to = next;
        }

        pub fn at(tween: *const Self, spec: Animation, now: f64) T {
            if (!tween.running) return tween.to;
            const elapsed: f32 = @floatCast(now - tween.start);
            const t = if (spec.duration <= 0) 1 else std.math.clamp(elapsed / spec.duration, 0, 1);
            return lerp(T, tween.from, tween.to, spec.curve.apply(t));
        }

        pub fn finish(tween: *Self, spec: Animation, now: f64) void {
            const elapsed: f32 = @floatCast(now - tween.start);
            if (elapsed >= spec.duration) tween.running = false;
        }
    };
}

// Compares slices by content, so a string that was formatted again into a
// new buffer does not restart an animation.
pub fn same(comptime T: type, a: T, b: T) bool {
    switch (@typeInfo(T)) {
        .pointer => |p| {
            if (p.size != .slice) return std.meta.eql(a, b);
            if (a.len != b.len) return false;
            for (a, b) |va, vb| if (!same(p.child, va, vb)) return false;
            return true;
        },
        .@"struct" => |s| {
            inline for (s.fields) |f| {
                if (!f.is_comptime and !same(f.type, @field(a, f.name), @field(b, f.name))) return false;
            }
            return true;
        },
        .optional => |o| {
            if (a) |va| if (b) |vb| return same(o.child, va, vb);
            return a == null and b == null;
        },
        .array => |array| {
            for (a, b) |va, vb| if (!same(array.child, va, vb)) return false;
            return true;
        },
        else => return std.meta.eql(a, b),
    }
}

// Values that cannot be interpolated, such as slices and enums, switch to
// `b` at once. `t` may leave [0, 1]; integers then stop at the ends of their
// range. They go through f64, which holds every 32-bit integer exactly.
pub fn lerp(comptime T: type, a: T, b: T, t: f32) T {
    switch (@typeInfo(T)) {
        .float => return a + (b - a) * @as(T, @floatCast(t)),
        .int => {
            if (a == b) return a;
            const from: f64 = @floatFromInt(a);
            const to: f64 = @floatFromInt(b);
            return std.math.lossyCast(T, @round(from + (to - from) * t));
        },
        .@"struct" => |s| {
            var r: T = b;
            inline for (s.fields) |f| {
                if (!f.is_comptime) @field(r, f.name) = lerp(f.type, @field(a, f.name), @field(b, f.name), t);
            }
            return r;
        },
        .optional => |o| {
            if (a) |va| if (b) |vb| return lerp(o.child, va, vb, t);
            return b;
        },
        .array => |array| {
            var r: T = b;
            for (&r, a, b) |*x, va, vb| x.* = lerp(array.child, va, vb, t);
            return r;
        },
        else => return b,
    }
}
