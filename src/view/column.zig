const mod = @import("../mod.zig");
const Flex = @import("flex.zig").Flex;

pub fn column(children: anytype) mod.Container(mod.Runtime(@TypeOf(children)), Flex(.vertical)) {
    return .{ .children = children, .config = .{} };
}
