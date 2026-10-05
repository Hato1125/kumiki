const mod = @import("../mod.zig");

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
        pub const pointer = mod.pointer;
        pub const hover = mod.hover;
        pub const drop = mod.drop;
        pub const popup = mod.popup;
        pub const shortcut = mod.shortcut;
        pub const animation = mod.animation;
        pub const with = mod.with;
    };
}

/// Shows the view that `f` returns. `f` runs whenever the view is built, and
/// its parameters are filled in by type, as described at `invoke` in
/// call.zig.
pub fn show(comptime f: anytype) Show(f) {
    return .{};
}
