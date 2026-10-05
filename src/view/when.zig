const types = @import("../types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("../layout.zig");
const mod = @import("../mod.zig");

/// The config of a `when`: shows the first child while `cond_fn` returns true
/// and the second otherwise. Both are kept, so switching back and forth keeps
/// their state.
pub fn When(comptime cond_fn: anytype) type {
    return struct {
        active: bool = true,

        const Self = @This();

        pub const cond = cond_fn;

        pub fn shows(w: Self, comptime child: usize) bool {
            return (child == 0) == w.active;
        }

        pub fn measureAll(w: Self, children: anytype, c: Constraint) Extent {
            return if (w.active) pass.measure(&children[0], c) else pass.measure(&children[1], c);
        }

        pub fn layoutAll(
            w: Self,
            children: anytype,
            at: Point,
            _: Extent,
        ) void {
            if (w.active) {
                pass.layout(&children[0], at);
            } else {
                pass.layout(&children[1], at);
            }
        }
    };
}

/// Shows `a` while `cond` returns true and `b` otherwise. The parameters of
/// `cond` are filled in by type like those of `ui.show`.
pub fn when(
    comptime cond: anytype,
    a: anytype,
    b: anytype,
) mod.Container(struct { @TypeOf(a), @TypeOf(b) }, When(cond)) {
    return .{ .children = .{ a, b }, .config = .{} };
}
