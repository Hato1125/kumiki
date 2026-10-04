const std = @import("std");

pub const inf = std.math.inf(f32);

pub const Point = struct { x: f32 = 0, y: f32 = 0 };
pub const Extent = struct { width: f32 = 0, height: f32 = 0 };
pub const Bounds = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };

/// The bytes of a text from `start` up to `end`.
pub const Range = struct {
    start: usize = 0,
    end: usize = 0,

    pub fn len(range: Range) usize {
        return range.end - range.start;
    }
};

pub const Color = struct {
    r: u8 = 0,
    g: u8 = 0,
    b: u8 = 0,
    a: u8 = 255,

    pub const black: Color = .{};
    pub const white: Color = .{ .r = 255, .g = 255, .b = 255 };
    pub const transparent: Color = .{ .a = 0 };

    /// The color between `a` and `b` as it is seen. Each color counts by its
    /// alpha, so one that is transparent only lets the other fade and does
    /// not tint it on the way. A color does not go past `b` either: where a
    /// curve overshoots, the color waits at `b`.
    pub fn lerp(a: Color, b: Color, t: f32) Color {
        const progress = std.math.clamp(t, 0, 1);
        const weight_a = @as(f32, @floatFromInt(a.a)) * (1 - progress);
        const weight_b = @as(f32, @floatFromInt(b.a)) * progress;
        const alpha = weight_a + weight_b;
        if (alpha == 0) return .{
            .r = b.r,
            .g = b.g,
            .b = b.b,
            .a = 0,
        };
        return .{
            .r = weighted(a.r, b.r, weight_a, weight_b),
            .g = weighted(a.g, b.g, weight_a, weight_b),
            .b = weighted(a.b, b.b, weight_a, weight_b),
            .a = @intFromFloat(@round(alpha)),
        };
    }

    fn weighted(a: u8, b: u8, weight_a: f32, weight_b: f32) u8 {
        const sum = @as(f32, @floatFromInt(a)) * weight_a + @as(f32, @floatFromInt(b)) * weight_b;
        return @intFromFloat(@round(sum / (weight_a + weight_b)));
    }
};

pub const Constraint = struct {
    min: Extent = .{},
    max: Extent = .{ .width = inf, .height = inf },

    pub fn tight(e: Extent) Constraint {
        return .{ .min = e, .max = e };
    }

    pub fn loosen(c: Constraint) Constraint {
        return .{ .max = c.max };
    }

    pub fn constrain(c: Constraint, e: Extent) Extent {
        return .{
            .width = std.math.clamp(e.width, c.min.width, c.max.width),
            .height = std.math.clamp(e.height, c.min.height, c.max.height),
        };
    }

    /// The largest finite size: the maximum where it is bounded, else the minimum.
    pub fn biggest(c: Constraint) Extent {
        return .{
            .width = if (std.math.isInf(c.max.width)) c.min.width else c.max.width,
            .height = if (std.math.isInf(c.max.height)) c.min.height else c.max.height,
        };
    }

    pub fn deflate(c: Constraint, dx: f32, dy: f32) Constraint {
        return .{
            .min = .{
                .width = @max(0, c.min.width - dx),
                .height = @max(0, c.min.height - dy),
            },
            .max = .{
                .width = @max(0, c.max.width - dx),
                .height = @max(0, c.max.height - dy),
            },
        };
    }
};
