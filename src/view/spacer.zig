const mod = @import("../mod.zig");

/// The config of a spacer, which takes the free space of a row or column.
pub const Spacer = struct { flex: f32 = 1 };

pub fn spacer() mod.Container(void, Spacer) {
    return mod.leaf(Spacer{});
}
