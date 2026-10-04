const std = @import("std");
const anim = @import("anim");

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;
const expectApproxEqAbs = std.testing.expectApproxEqAbs;

test "lerp interpolates numbers and switches the rest at once" {
    const Sample = struct { r: u8, g: u8, a: f32, label: []const u8, pair: [2]f32, maybe: ?f32 };
    const a: Sample = .{ .r = 0, .g = 200, .a = 0, .label = "a", .pair = .{ 0, 4 }, .maybe = 2 };
    const b: Sample = .{ .r = 100, .g = 0, .a = 1, .label = "b", .pair = .{ 2, 0 }, .maybe = 4 };
    const middle = anim.lerp(Sample, a, b, 0.5);
    try expectEqual(50, middle.r);
    try expectEqual(100, middle.g);
    try expectEqual(0.5, middle.a);
    try std.testing.expectEqualStrings("b", middle.label);
    try expectEqual([2]f32{ 1, 2 }, middle.pair);
    try expectEqual(3, middle.maybe.?);
}

test "lerp keeps integers in range when it overshoots" {
    try expectEqual(255, anim.lerp(u8, 0, 250, 1.2));
    try expectEqual(0, anim.lerp(u8, 250, 5, 1.2));
}

test "lerp leaves a struct that declares lerp to it" {
    const Stepped = struct {
        value: f32,

        pub fn lerp(a: @This(), b: @This(), t: f32) @This() {
            return if (t < 0.5) a else b;
        }
    };
    const outer = struct { step: Stepped, plain: f32 };
    const middle = anim.lerp(outer, .{ .step = .{ .value = 0 }, .plain = 0 }, .{ .step = .{ .value = 8 }, .plain = 8 }, 0.25);
    try expectEqual(0, middle.step.value);
    try expectEqual(2, middle.plain);
}

test "lerp keeps the largest integers in range" {
    const max = std.math.maxInt(u32);
    try expectEqual(max, anim.lerp(u32, max, max, 0.5));
    try expectEqual(max, anim.lerp(u32, 0, max, 1.2));
    try expectEqual(max - 1, anim.lerp(u32, max - 3, max - 1, 1));
    try expectEqual(std.math.minInt(i32), anim.lerp(i32, 0, std.math.minInt(i32), 1.5));
    try expectEqual(std.math.maxInt(u64), anim.lerp(u64, std.math.maxInt(u64), std.math.maxInt(u64), 0.5));
}

test "a bezier is the cubic-bezier() of CSS" {
    const linear: anim.Curve = .{ .bezier = .{ 0.25, 0.25, 0.75, 0.75 } };
    try expectApproxEqAbs(0.3, linear.apply(0.3), 0.001);

    const overshooting: anim.Curve = .{ .bezier = .{ 0.42, 1.67, 0.21, 0.90 } };
    try expectEqual(0, overshooting.apply(0));
    try expectEqual(1, overshooting.apply(1));
    try expect(overshooting.apply(0.5) > 1);
}

test "a spring lasts until it settles" {
    const bouncy: anim.Animation = .spring(0.6, 800);
    try expectEqual(0, bouncy.curve.apply(0));
    try expectEqual(1, bouncy.curve.apply(1));
    try expect(bouncy.curve.apply(0.4) > 1);
    try expectApproxEqAbs(0.407, bouncy.duration, 0.001);

    const critical: anim.Animation = .spring(1, 1600);
    var t: f32 = 0;
    while (t <= 1) : (t += 0.05) try expect(critical.curve.apply(t) <= 1);

    const heavy: anim.Spring = .{ .damping = 2, .stiffness = 100 };
    try expectEqual(0, heavy.position(0));
    try expectApproxEqAbs(1, heavy.position(heavy.settleTime()), 0.002);
}

test "same compares strings by content" {
    const Label = struct { text: []const u8, size: f32 };
    var buf: [2]u8 = "ab".*;
    try expect(anim.same(Label, .{ .text = "ab", .size = 1 }, .{ .text = &buf, .size = 1 }));
    try expect(!anim.same(Label, .{ .text = "ab", .size = 1 }, .{ .text = "ab", .size = 2 }));
}

test "same compares slices of structs by content" {
    const Stop = struct { at: f32, name: []const u8 };
    const stops = [_]Stop{ .{ .at = 0, .name = "a" }, .{ .at = 1, .name = "b" } };
    var copy = stops;
    try expect(anim.same([]const Stop, &stops, &copy));
    copy[1].at = 2;
    try expect(!anim.same([]const Stop, &stops, &copy));
    try expect(!anim.same([]const Stop, &stops, copy[0..1]));
}

test "a tween restarts from the value it shows" {
    const spec: anim.Animation = .{ .duration = 1, .curve = .linear };
    var tween: anim.Tween(f32) = .init(0);
    tween.retarget(spec, 10, 0);
    try expectEqual(5, tween.at(spec, 0.5));
    tween.retarget(spec, 0, 0.5);
    try expectEqual(5, tween.at(spec, 0.5));
    try expectEqual(2.5, tween.at(spec, 1.0));
    tween.finish(spec, 1.5);
    try expect(!tween.running);
    try expectEqual(0, tween.at(spec, 2));
}

test "a tween takes an equal target without restarting, since it may hold newer strings" {
    const spec: anim.Animation = .{ .duration = 1, .curve = .linear };
    var old: [2]u8 = "ab".*;
    var tween: anim.Tween([]const u8) = .init(&old);
    tween.retarget(spec, "ab", 0);
    try expect(!tween.running);
    old = "xx".*;
    try std.testing.expectEqualStrings("ab", tween.at(spec, 0));
}
