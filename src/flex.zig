const std = @import("std");

const types = @import("types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("layout.zig");

pub const Axis = enum { horizontal, vertical };
pub const MainAlign = enum { start, center, end, between };
pub const CrossAlign = enum { start, center, end, stretch };

// The config of a row or column. Children with a flex factor share the free
// space in proportion to it. The container spans the whole axis when it has
// such children or when `main` needs free space to distribute.
pub fn Flex(comptime axis: Axis) type {
    return struct {
        gap: f32 = 0,
        main: MainAlign = .start,
        cross: CrossAlign = .start,

        const Self = @This();

        fn mainOf(e: Extent) f32 {
            return if (axis == .horizontal) e.width else e.height;
        }

        fn crossOf(e: Extent) f32 {
            return if (axis == .horizontal) e.height else e.width;
        }

        fn extent(along: f32, across: f32) Extent {
            return if (axis == .horizontal)
                .{ .width = along, .height = across }
            else
                .{ .width = across, .height = along };
        }

        fn gaps(f: Self, count: usize) f32 {
            return f.gap * @as(f32, @floatFromInt(@max(count, 1) - 1));
        }

        fn measureChild(f: Self, child: anytype, c: Constraint, min: f32, max: f32) Extent {
            const across = crossOf(c.max);
            const stretched = f.cross == .stretch and !std.math.isInf(across);
            return pass.measure(child, .{
                .min = extent(min, if (stretched) across else 0),
                .max = extent(max, across),
            });
        }

        pub fn measureAll(f: Self, children: anytype, c: Constraint) Extent {
            const space = mainOf(c.max);
            var used = f.gaps(children.len);
            var across: f32 = 0;
            var factors: f32 = 0;
            inline for (0..children.len) |i| {
                const factor = pass.flexOf(&children[i]);
                if (factor > 0) {
                    factors += factor;
                } else {
                    const size = f.measureChild(&children[i], c, 0, types.inf);
                    used += mainOf(size);
                    across = @max(across, crossOf(size));
                }
            }

            const free = if (std.math.isInf(space)) 0 else @max(0, space - used);
            inline for (0..children.len) |i| {
                const factor = pass.flexOf(&children[i]);
                if (factor > 0) {
                    const share = free * factor / factors;
                    const size = f.measureChild(&children[i], c, share, share);
                    used += mainOf(size);
                    across = @max(across, crossOf(size));
                }
            }

            const fills = (factors > 0 or f.main != .start) and !std.math.isInf(space);
            if (f.cross == .stretch and !std.math.isInf(crossOf(c.max))) across = crossOf(c.max);
            return c.constrain(extent(if (fills) space else used, across));
        }

        pub fn layoutAll(f: Self, children: anytype, at: Point, size: Extent) void {
            var used = f.gaps(children.len);
            inline for (0..children.len) |i| used += mainOf(children[i].size);

            const extra = @max(0, mainOf(size) - used);
            var along: f32 = switch (f.main) {
                .start, .between => 0,
                .center => extra / 2,
                .end => extra,
            };
            const step = if (f.main == .between and children.len > 1)
                f.gap + extra / @as(f32, @floatFromInt(children.len - 1))
            else
                f.gap;

            inline for (0..children.len) |i| {
                const free = crossOf(size) - crossOf(children[i].size);
                const across: f32 = switch (f.cross) {
                    .start, .stretch => 0,
                    .center => free / 2,
                    .end => free,
                };
                const offset = extent(along, across);
                pass.layout(&children[i], .{ .x = at.x + offset.width, .y = at.y + offset.height });
                along += mainOf(children[i].size) + step;
            }
        }
    };
}
