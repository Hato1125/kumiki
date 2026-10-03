const types = @import("types.zig");
const Point = types.Point;
const call = @import("call.zig");
const invoke = call.invoke;
const node_zig = @import("node.zig");
const NodeId = node_zig.NodeId;
const Path = node_zig.Path;
const State = node_zig.State;
const each = node_zig.each;
const isFocusable = node_zig.isFocusable;
const isInput = node_zig.isInput;
const isKey = node_zig.isKey;
const isTap = node_zig.isTap;
const task_zig = @import("task.zig");
const markTargets = @import("tree.zig").markTargets;

// The buttons, keys and modifier bits have the values of SDL3.
pub const MouseButton = enum(u8) { left = 1, middle, right, x1, x2, _ };

pub const MouseButtonEvent = struct {
    button: MouseButton,
    down: bool,
    x: f32 = 0,
    y: f32 = 0,
};

pub const KeyPress = struct {
    key: u32 = 0,
    mod: u16 = 0,
    down: bool = false,
    repeat: bool = false,

    pub fn shift(press: KeyPress) bool {
        return press.mod & 0x0003 != 0;
    }

    // Whether the key is Ctrl, Shift, Alt or GUI on either side.
    pub fn isModifier(press: KeyPress) bool {
        return press.key >= 0x400000e0 and press.key <= 0x400000e7;
    }
};

pub const keys = struct {
    pub const enter: u32 = 0x0d;
    pub const space: u32 = 0x20;
    pub const tab: u32 = 0x09;
    pub const escape: u32 = 0x1b;
    pub const backspace: u32 = 0x08;
    pub const delete: u32 = 0x7f;
    pub const home: u32 = 0x4000004a;
    pub const end: u32 = 0x4000004d;
    pub const right: u32 = 0x4000004f;
    pub const left: u32 = 0x40000050;
    pub const down: u32 = 0x40000051;
    pub const up: u32 = 0x40000052;
};

// Text that was typed, or that an input method is still composing: each
// composition replaces the one before, and an empty one ends it. `text` is
// UTF-8 and only valid while the function it is given to runs.
pub const TextInput = struct {
    text: []const u8,
    composing: bool = false,
};

pub const Event = union(enum) {
    pointer_move: Point,
    pointer_leave,
    button: MouseButtonEvent,
    key: KeyPress,
    text: TextInput,
    close,
};

// Collects `target` and its ancestors. Like the other searches for input, it
// passes over what a `when` does not show.
pub fn findPath(node: anytype, target: NodeId, path: *Path) bool {
    if (node.id != target and !each(node, .shown, findPath, .{ target, path })) return false;
    path.push(node.id);
    return true;
}

// Collects the deepest node at `at` and its ancestors. Later children are in
// front of earlier ones.
pub fn hit(node: anytype, at: Point, path: *Path) bool {
    const x = at.x - node.offset.x;
    const y = at.y - node.offset.y;
    if (x < 0 or x >= node.size.width or y < 0 or y >= node.size.height) return false;
    _ = each(node, .front, hit, .{ at, path });
    path.push(node.id);
    return true;
}

pub const Nearest = struct {
    tap: NodeId = 0,
    focusable: NodeId = 0,
};

// Finds the nearest tap and the nearest focusable node among `target` and
// its ancestors.
pub fn nearest(node: anytype, target: NodeId, found: *Nearest) bool {
    if (node.id != target and !each(node, .shown, nearest, .{ target, found })) return false;
    const Widget = @TypeOf(node.widget);
    if (comptime isTap(Widget)) {
        if (found.tap == 0) found.tap = node.id;
    }
    if (comptime isFocusable(Widget)) {
        if (found.focusable == 0) found.focusable = node.id;
    }
    return true;
}

// Records the focusable nodes around `current` while walking the tree in
// order.
pub const FocusWalk = struct {
    current: NodeId,
    seen: bool = false,
    first: NodeId = 0,
    last: NodeId = 0,
    before: NodeId = 0,
    after: NodeId = 0,

    fn visit(walk: *FocusWalk, id: NodeId) void {
        if (walk.first == 0) walk.first = id;
        walk.last = id;
        if (id == walk.current) {
            walk.seen = true;
        } else if (!walk.seen) {
            walk.before = id;
        } else if (walk.after == 0) {
            walk.after = id;
        }
    }

    // Wraps around at both ends.
    pub fn result(walk: FocusWalk, backward: bool) NodeId {
        if (backward) return if (walk.before != 0) walk.before else walk.last;
        return if (walk.after != 0) walk.after else walk.first;
    }
};

// Whether a node wraps a focusable one through single children. It shares
// the stop of that one then: the inner node takes the focus, and keys and
// text reach the outer one from there.
fn wrapsStop(comptime N: type) bool {
    const Children = @FieldType(N, "children");
    if (Children == void or @hasField(Children, "items")) return false;
    const children = @typeInfo(Children).@"struct".fields;
    if (children.len != 1) return false;
    return isFocusable(@FieldType(children[0].type, "widget")) or wrapsStop(children[0].type);
}

pub fn walkFocus(node: anytype, walk: *FocusWalk) void {
    if (comptime isFocusable(@TypeOf(node.widget)) and !wrapsStop(@TypeOf(node.*))) walk.visit(node.id);
    _ = each(node, .shown, walkFocus, .{walk});
}

// The bounds of the nearest node that takes typed text among `target` and
// its ancestors.
pub fn typingArea(node: anytype, target: NodeId, area: *?types.Bounds) bool {
    if (node.id != target and !each(node, .shown, typingArea, .{ target, area })) return false;
    if (comptime isInput(@TypeOf(node.widget))) {
        if (area.* == null) area.* = .{
            .x = node.offset.x,
            .y = node.offset.y,
            .w = node.size.width,
            .h = node.size.height,
        };
    }
    return true;
}

// What is offered to a node and then to its ancestors.
pub const Offer = union(enum) { click, key: KeyPress, text: TextInput };

// Enter and Space activate a tap, except while text is typed: they belong to
// the text then.
fn handle(node: anytype, offer: Offer, owners: anytype, state: *const State) bool {
    const Widget = @TypeOf(node.widget);
    if (comptime isInput(Widget)) {
        if (offer == .text) {
            invoke(Widget.input_handler, owners, state, offer.text);
            markTargets(Widget.input_handler, owners);
            return true;
        }
    }
    if (comptime isKey(Widget)) {
        if (offer == .key and invoke(Widget.key_handler, owners, state, offer.key)) {
            markTargets(Widget.key_handler, owners);
            return true;
        }
    }
    if (comptime isTap(Widget)) {
        const activates = switch (offer) {
            .click => true,
            .key => |press| state.typing == null and press.down and
                (press.key == keys.enter or press.key == keys.space),
            .text => false,
        };
        if (activates) {
            _ = invoke(Widget.tap_action, owners, state, {});
            markTargets(Widget.tap_action, owners);
            return true;
        }
    }
    return false;
}

// Offers a click, a key press or text to `target` and then to its ancestors
// until one handles it. Returns whether `target` is inside `node`.
pub fn bubble(
    node: anytype,
    target: NodeId,
    offer: Offer,
    owners: anytype,
    state: *const State,
    handled: *bool,
) bool {
    const inner = if (comptime node_zig.isComponent(@TypeOf(node.widget))) owners ++ .{node} else owners;
    if (node.id != target and !each(node, .shown, bubble, .{ target, offer, inner, state, handled })) return false;
    if (!handled.*) handled.* = handle(node, offer, owners, state);
    return true;
}

// Hands the result of a background function to the `receive` of the
// component `target`, or of the nearest one around it that takes the
// result's type in the one parameter that its owners do not fill in. Returns
// whether `target` is inside `node`.
pub fn deliver(
    node: anytype,
    target: NodeId,
    task: *const task_zig.Task,
    owners: anytype,
    state: *const State,
    handled: *bool,
) bool {
    const Widget = @TypeOf(node.widget);
    const component = comptime node_zig.isComponent(Widget);
    const inner = if (component) owners ++ .{node} else owners;
    if (node.id != target and !each(node, .all, deliver, .{ target, task, inner, state, handled })) return false;
    if (comptime !component or !@hasDecl(Widget, "receive")) return true;

    inline for (@typeInfo(@TypeOf(Widget.receive)).@"fn".params) |param| {
        const P = param.type orelse continue;
        if (comptime call.fills(@TypeOf(inner), P)) continue;
        if (!handled.* and task.key == task_zig.keyOf(P)) {
            const result: *const P = @ptrCast(@alignCast(task.result));
            invoke(Widget.receive, inner, state, result.*);
            markTargets(Widget.receive, inner);
            handled.* = true;
        }
    }
    return true;
}
