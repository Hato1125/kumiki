// A function receives this by declaring a parameter of this type. It
// describes the nearest component around the place the function is given.

const std = @import("std");

const node_zig = @import("node.zig");
const contains = node_zig.contains;

const Context = @This();

id: node_zig.NodeId,
state: *const node_zig.State,
arena: *std.heap.ArenaAllocator.State,
// The allocator given to the Scene.
gpa: std.mem.Allocator,

// The focus, the pointer and the pressed tap count when they are on this
// component or inside it.
pub fn focused(cx: Context) bool {
    return contains(cx.state.focus.slice(), cx.id);
}

// A component shows its focus only after the keyboard was used, so that a
// click leaves no mark.
pub fn focusVisible(cx: Context) bool {
    return cx.state.keyboard and cx.focused();
}

pub fn hovered(cx: Context) bool {
    return contains(cx.state.hover.slice(), cx.id);
}

pub fn pressed(cx: Context) bool {
    return contains(cx.state.press.slice(), cx.id);
}

// The string stays valid until this component is built again. It is empty
// when memory runs out.
pub fn print(cx: Context, comptime fmt: []const u8, args: anytype) []const u8 {
    var arena = cx.arena.promote(cx.gpa);
    defer cx.arena.* = arena.state;
    return std.fmt.allocPrint(arena.allocator(), fmt, args) catch "";
}
