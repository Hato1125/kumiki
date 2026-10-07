const mod = @import("../mod.zig");

/// The config of a `show`, which stands for the view that `f` returns and is
/// replaced by it when the tree is built.
pub fn Show(comptime f: anytype) type {
    return struct {
        pub const func = f;
    };
}

/// Shows the view that `f` returns. `f` runs whenever the view is built, and
/// its parameters are filled in by type, as described at `invoke` in
/// call.zig.
pub fn show(comptime f: anytype) mod.Container(void, Show(f)) {
    return mod.leaf(Show(f){});
}
