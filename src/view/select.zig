const types = @import("../types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("../layout.zig");
const mod = @import("../mod.zig");
const ReturnOf = @import("../node.zig").ReturnOf;

/// The config of a `select`: shows the child that stands for the value of the
/// enum that `cond_fn` returns, in the order of its fields. All children are
/// kept, so switching back and forth keeps their state.
pub fn Select(comptime cond_fn: anytype) type {
    const Choice = ReturnOf(cond_fn);
    if (@typeInfo(Choice) != .@"enum" or @typeInfo(Choice).@"enum".mode != .exhaustive) {
        @compileError("select takes a function that returns an exhaustive enum, not " ++
            @typeName(Choice) ++ "; use `when` for a bool");
    }
    const values = @typeInfo(Choice).@"enum".field_values;

    return struct {
        active: Choice = @fromBackingInt(@intCast(values[0])),

        const Self = @This();

        pub const cond = cond_fn;
        pub const count = values.len;

        pub fn shows(s: Self, comptime child: usize) bool {
            return s.active == @as(Choice, @fromBackingInt(@intCast(values[child])));
        }

        pub fn measureAll(s: Self, children: anytype, c: Constraint) Extent {
            inline for (0..children.len) |i| {
                if (s.shows(i)) return pass.measure(&children[i], c);
            }
            unreachable;
        }

        pub fn layoutAll(s: Self, children: anytype, at: Point, _: Extent) void {
            inline for (0..children.len) |i| {
                if (s.shows(i)) return pass.layout(&children[i], at);
            }
            unreachable;
        }
    };
}

/// Shows the child that stands for the value of the enum that `cond` returns:
/// the first child for its first field, and so on. There must be as many
/// children as fields. The parameters of `cond` are filled in by type like
/// those of `ui.show`.
pub fn select(
    comptime cond: anytype,
    children: anytype,
) mod.Container(mod.Runtime(@TypeOf(children)), Select(cond)) {
    const Config = Select(cond);
    if (children.len != Config.count) {
        @compileError("select has a different number of children than the fields of the enum");
    }
    return .{ .children = children, .config = .{} };
}
