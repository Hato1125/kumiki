const std = @import("std");

const Tasks = @import("task.zig").Tasks;
const types = @import("types.zig");

/// Counts up from 1. 0 stands for no node.
pub const NodeId = u32;

/// A node and its ancestors, the node itself first.
pub const Path = struct {
    ids: [128]NodeId = undefined,
    len: usize = 0,

    pub fn slice(path: *const Path) []const NodeId {
        return path.ids[0..path.len];
    }

    pub fn id(path: *const Path) NodeId {
        return if (path.len == 0) 0 else path.ids[0];
    }

    pub fn push(path: *Path, node: NodeId) void {
        if (path.len == path.ids.len) return;
        path.ids[path.len] = node;
        path.len += 1;
    }

    /// The part of the path from `node` up to the root.
    pub fn from(path: *const Path, node: NodeId) Path {
        var tail: Path = .{};
        const start = std.mem.indexOfScalar(NodeId, path.slice(), node) orelse return tail;
        for (path.ids[start..path.len]) |ancestor| tail.push(ancestor);
        return tail;
    }
};

pub fn contains(path: []const NodeId, id: NodeId) bool {
    return std.mem.indexOfScalar(NodeId, path, id) != null;
}

/// What a scene shares with every pass over its tree. `animating`, `built` and
/// `stale` tell what the last build did: an animation still runs, something
/// was built again, a path may have changed because a list matched its rows
/// again or a `when` switched. `keyboard` is whether the last input came from
/// the keyboard, and `active` whether the keyboard is with the window of the
/// scene at all. `tasks` lives on the heap, because functions in the
/// background point at it while the scene may still be moved. `inputs` counts
/// the nodes that take typed text, and `typing` is where the implementation
/// was asked for it.
pub const State = struct {
    gpa: std.mem.Allocator,
    tasks: *Tasks,
    host: Host,
    inputs: u32 = 0,
    typing: ?types.Bounds = null,
    active: bool = true,
    next_id: NodeId = 0,
    now: f64 = 0,
    animating: bool = false,
    built: bool = false,
    stale: bool = false,
    focus: Path = .{},
    hover: Path = .{},
    press: Path = .{},
    keyboard: bool = false,
};

/// The implementation as a Context reaches it, for its clipboard. The scene
/// points `impl` at where the implementation is before it runs functions.
pub const Host = struct {
    impl: *anyopaque,
    paste: *const fn (*anyopaque, std.mem.Allocator) ?[]const u8,
    copy: *const fn (*anyopaque, []const u8) bool,
};

pub fn isShow(comptime T: type) bool {
    return @hasDecl(T, "func");
}

pub fn isComponent(comptime T: type) bool {
    return @hasDecl(T, "view");
}

pub fn isList(comptime T: type) bool {
    return @hasDecl(T, "source");
}

/// A container is made of `children` and a `config` that measures, places and
/// paints them.
pub fn isContainer(comptime T: type) bool {
    return @hasField(T, "children");
}

pub const HandlerKind = enum { tap, key, input, wheel, pointer };

pub fn handles(comptime T: type, comptime kind: HandlerKind) bool {
    return @hasDecl(T, "handler_kind") and T.handler_kind == kind;
}

pub fn isFocusable(comptime T: type) bool {
    return handles(T, .tap) or handles(T, .key) or handles(T, .input);
}

/// Whether a widget takes part in a pass through its declaration `name`. A
/// component is walked as the container of its view, whatever it declares.
pub fn has(comptime T: type, comptime name: []const u8) bool {
    return !isComponent(T) and @hasDecl(T, name);
}

pub fn ReturnOf(comptime f: anytype) type {
    return @typeInfo(@TypeOf(f)).@"fn".return_type.?;
}

/// A component that declares `pub fn provide` hands what that returns to the
/// functions inside it, which receive it by its type as they would a field.
pub fn provides(comptime View: type) bool {
    return isComponent(View) and @hasDecl(View, "provide");
}

pub fn Provided(comptime View: type) type {
    return ReturnOf(View.provide);
}

pub fn Resolved(comptime View: type) type {
    return if (isShow(View)) ReturnOf(View.func) else View;
}

// Whether a node of `View` keeps its position. One that leaves its children
// where it is, as a component always does, is where its last child is and
// keeps none.
fn keepsOffset(comptime View: type) bool {
    if (isComponent(View)) return false;
    if (!isContainer(View)) return true;
    const Config = @FieldType(View, "config");
    return @hasDecl(Config, "layout") or @hasDecl(Config, "layoutAll");
}

/// The widget of a container is its config, because its children have nodes
/// of their own. The arena holds the strings made by Context.print until the
/// next build, and `given` what the component provided at its last build.
/// `offsetOf` reads the offset, which not every node keeps.
pub fn Node(comptime View: type) type {
    return struct {
        id: NodeId,
        offset: if (keepsOffset(View)) types.Point else void,
        size: types.Extent,
        widget: if (isContainer(View) and !isComponent(View)) @FieldType(View, "config") else View,
        children: Children(View),
        dirty: if (isComponent(View)) bool else void,
        arena: if (isComponent(View)) std.heap.ArenaAllocator.State else void,
        given: if (provides(View)) Provided(View) else void,
    };
}

pub fn NodeOf(comptime View: type) type {
    return Node(Resolved(View));
}

/// Where a node is: at its own offset, or where its last child is for a node
/// that keeps none.
pub fn offsetOf(node: anytype) types.Point {
    if (comptime @TypeOf(node.offset) != void) return node.offset;
    return offsetOf(&node.children[node.children.len - 1]);
}

fn Children(comptime View: type) type {
    if (isComponent(View)) return struct { NodeOf(@TypeOf(View.view)) };
    if (isList(View)) return std.ArrayList(Node(View.Row));
    if (!isContainer(View)) return void;
    const fields = @typeInfo(@FieldType(View, "children")).@"struct".fields;
    var element_types: [fields.len]type = undefined;
    for (fields, 0..) |field, i| element_types[i] = NodeOf(field.type);
    return @Tuple(&element_types);
}

pub const Order = enum { all, shown, front };

/// Calls `f(child, args...)` for the children of `node` until a call returns
/// true. `shown` leaves out the side of a `when` that is not on display, and
/// `front` also starts from the child in front.
pub fn each(
    node: anytype,
    comptime order: Order,
    comptime f: anytype,
    args: anytype,
) bool {
    const children = &node.children;
    if (comptime @TypeOf(children.*) == void) return false;
    if (comptime @hasField(@TypeOf(children.*), "items")) {
        for (0..children.items.len) |n| {
            const i = if (order == .front) children.items.len - 1 - n else n;
            if (stops(@call(.auto, f, .{&children.items[i]} ++ args))) {
                return true;
            }
        }
        return false;
    }
    const partly = comptime order != .all and has(@TypeOf(node.widget), "cond");
    inline for (0..children.len) |n| {
        const i = if (order == .front) children.len - 1 - n else n;
        if (!partly or (i == 0) == node.widget.active) {
            if (stops(@call(.auto, f, .{&children[i]} ++ args))) return true;
        }
    }
    return false;
}

fn stops(result: anytype) bool {
    return @TypeOf(result) == bool and result;
}
