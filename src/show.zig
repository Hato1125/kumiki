const types = @import("types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("layout.zig");
const mod = @import("mod.zig");

pub fn Show(comptime f: anytype) type {
    return struct {
        pub const func = f;

        pub const padding = mod.padding;
        pub const frame = mod.frame;
        pub const flex = mod.flex;
        pub const bg = mod.bg;
        pub const clip = mod.clip;
        pub const opacity = mod.opacity;
        pub const tap = mod.tap;
        pub const key = mod.key;
        pub const input = mod.input;
        pub const wheel = mod.wheel;
        pub const animation = mod.animation;
        pub const with = mod.with;
    };
}

// Shows the view that `f` returns. `f` runs whenever the view is built, and
// its parameters are filled in by type, as described at `invoke` in
// call.zig.
pub fn show(comptime f: anytype) Show(f) {
    return .{};
}

// The config of a `when`: shows the first child while `cond_fn` returns true
// and the second otherwise. Both are kept, so switching back and forth keeps
// their state.
pub fn When(comptime cond_fn: anytype) type {
    return struct {
        active: bool = true,

        const Self = @This();

        pub const cond = cond_fn;

        pub fn measureAll(w: Self, children: anytype, c: Constraint) Extent {
            return if (w.active) pass.measure(&children[0], c) else pass.measure(&children[1], c);
        }

        pub fn layoutAll(w: Self, children: anytype, at: Point, _: Extent) void {
            if (w.active) pass.layout(&children[0], at) else pass.layout(&children[1], at);
        }
    };
}
