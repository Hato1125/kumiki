//! A function receives this by declaring a parameter of this type. It
//! describes the nearest component around the place the function is given.

const std = @import("std");

const node_zig = @import("node.zig");
const contains = node_zig.contains;
const keyOf = @import("task.zig").keyOf;
const types = @import("types.zig");

const Context = @This();

id: node_zig.NodeId,
state: *const node_zig.State,
arena: *std.heap.ArenaAllocator.State,
/// The allocator given to the Scene.
gpa: std.mem.Allocator,
/// The size of this component at the last layout: zero before the first.
size: types.Extent,

/// The focus, the pointer and the pressed tap count when they are on this
/// component or inside it. Nothing has the focus while the keyboard is with
/// another window.
pub fn focused(cx: Context) bool {
    return cx.state.active and contains(cx.state.focus.slice(), cx.id);
}

/// A component shows its focus only after the keyboard was used, so that a
/// click leaves no mark.
pub fn focusVisible(cx: Context) bool {
    return cx.state.keyboard and cx.focused();
}

/// Moves the focus to the first view in this component that can take it,
/// once the tree is built with what the function that runs changed, so that a
/// view it brings up can take it. Nothing happens when the component shows
/// none.
pub fn focus(cx: Context) void {
    cx.state.wanted.* = cx.id;
}

pub fn hovered(cx: Context) bool {
    return contains(cx.state.hover.slice(), cx.id);
}

pub fn pressed(cx: Context) bool {
    return contains(cx.state.press.slice(), cx.id);
}

/// Runs `work(args...)` on a thread of its own, where it must not touch the
/// components, and hands what it returns to `done` on the thread of the
/// scene. `done` is one of the functions that this component, or one around
/// it, lists in `pub const later = .{ ... }`: its parameters are filled in by
/// type, and the one that nothing fills in takes the result. The result is
/// dropped when this component is gone by then.
pub fn spawn(
    cx: Context,
    comptime work: anytype,
    args: std.meta.ArgsTuple(@TypeOf(work)),
    comptime done: anytype,
) void {
    comptime {
        const Result = node_zig.ReturnOf(work);
        const takes = for (@typeInfo(@TypeOf(done)).@"fn".params) |param| {
            if (param.type == Result) break true;
        } else false;
        if (Result != void and !takes) {
            @compileError("the function given to spawn takes no " ++ @typeName(Result));
        }
    }
    cx.state.tasks.spawn(cx.id, work, args, keyOf(done));
}

/// Calls `f` once `seconds` have passed. `f` is one of the functions that
/// this component, or one around it, lists in `pub const later = .{ ... }`,
/// and its parameters are filled in by type. A call of `f` that this
/// component still waits for gives way, so asking again puts the moment off.
/// `f` runs on a frame of its own, never within the function that asks for
/// it, and not at all when this component is gone by then.
pub fn after(cx: Context, seconds: f64, comptime f: anytype) void {
    cx.state.tasks.after(cx.id, cx.state.now + @max(0, seconds), keyOf(f));
}

/// The text in the clipboard, or null when it holds none. Like the strings of
/// `print`, it stays valid until this component is built again.
pub fn paste(cx: Context) ?[]const u8 {
    var arena = cx.arena.promote(cx.gpa);
    defer cx.arena.* = arena.state;
    return cx.state.host.paste(cx.state.host.impl, arena.allocator());
}

/// Returns whether the clipboard took the text.
pub fn copy(cx: Context, text: []const u8) bool {
    return cx.state.host.copy(cx.state.host.impl, text);
}

/// The time in seconds of the event being handled, or else of this build. It
/// only serves to compare with other times of this clock.
pub fn now(cx: Context) f64 {
    return cx.state.now;
}

/// The string stays valid until this component is built again. It is empty
/// when memory runs out.
pub fn print(cx: Context, comptime fmt: []const u8, args: anytype) []const u8 {
    var arena = cx.arena.promote(cx.gpa);
    defer cx.arena.* = arena.state;
    return std.fmt.allocPrint(arena.allocator(), fmt, args) catch "";
}
