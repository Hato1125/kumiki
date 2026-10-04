const types = @import("types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("layout.zig");

// Where something smaller sits inside a larger area: 0 is the left or top
// edge and 1 is the right or bottom edge.
pub const Alignment = struct {
    x: f32 = 0.5,
    y: f32 = 0.5,

    pub const top_left: Alignment = .{ .x = 0, .y = 0 };
    pub const top: Alignment = .{ .x = 0.5, .y = 0 };
    pub const top_right: Alignment = .{ .x = 1, .y = 0 };
    pub const left: Alignment = .{ .x = 0, .y = 0.5 };
    pub const center: Alignment = .{ .x = 0.5, .y = 0.5 };
    pub const right: Alignment = .{ .x = 1, .y = 0.5 };
    pub const bottom_left: Alignment = .{ .x = 0, .y = 1 };
    pub const bottom: Alignment = .{ .x = 0.5, .y = 1 };
    pub const bottom_right: Alignment = .{ .x = 1, .y = 1 };

    pub fn place(a: Alignment, at: Point, outer: Extent, inner: Extent) Point {
        return .{
            .x = at.x + (outer.width - inner.width) * a.x,
            .y = at.y + (outer.height - inner.height) * a.y,
        };
    }
};

// The config of a stack: children lie on top of each other, later ones in
// front, and the stack is as large as its largest child.
pub const Stack = struct {
    alignment: Alignment = .center,

    pub fn measureAll(_: Stack, children: anytype, c: Constraint) Extent {
        var size: Extent = .{};
        inline for (0..children.len) |i| {
            const child = pass.measure(&children[i], c.loosen());
            size = .{
                .width = @max(size.width, child.width),
                .height = @max(size.height, child.height),
            };
        }
        return c.constrain(size);
    }

    pub fn layoutAll(
        s: Stack,
        children: anytype,
        at: Point,
        size: Extent,
    ) void {
        inline for (0..children.len) |i| {
            pass.layout(&children[i], s.alignment.place(at, size, children[i].size));
        }
    }
};
