const types = @import("../types.zig");
const Alignment = types.Alignment;
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("../layout.zig");
const mod = @import("../mod.zig");

/// The config of a stack: children lie on top of each other, later ones in
/// front, and the stack is as large as its largest child.
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

pub fn stack(
    children: anytype,
) mod.Container(mod.Runtime(@TypeOf(children)), Stack) {
    return .{ .children = children, .config = .{} };
}
