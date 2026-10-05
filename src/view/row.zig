const mod = @import("../mod.zig");
const Flex = @import("flex.zig").Flex;

pub fn row(children: anytype) mod.Container(mod.Runtime(@TypeOf(children)), Flex(.horizontal)) {
    return .{ .children = children, .config = .{} };
}
