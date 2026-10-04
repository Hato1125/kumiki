const builtin = @import("builtin");

const types = @import("types.zig");
const Point = types.Point;
const call = @import("call.zig");
const invoke = call.invoke;
const node_zig = @import("node.zig");
const NodeId = node_zig.NodeId;
const Path = node_zig.Path;
const State = node_zig.State;
const contains = node_zig.contains;
const each = node_zig.each;
const isFocusable = node_zig.isFocusable;
const has = node_zig.has;
const handles = node_zig.handles;
const offsetOf = node_zig.offsetOf;
const task_zig = @import("task.zig");
const markTargets = @import("tree.zig").markTargets;

/// The buttons, keys and modifier bits have the values of SDL3.
pub const MouseButton = enum(u8) { left = 1, middle, right, x1, x2, _ };

/// `clicks` counts the presses that follow each other quickly at one place:
/// 2 for a double click. `mod` holds the modifier keys held meanwhile.
pub const MouseButtonEvent = struct {
    button: MouseButton,
    down: bool,
    x: f32 = 0,
    y: f32 = 0,
    clicks: u8 = 1,
    mod: u16 = 0,
};

const shift_bits = 0x0003;
const ctrl_bits = 0x00c0;
const alt_bits = 0x0300;
const gui_bits = 0x0c00;

/// What a mouse button does over a view with a `pointer` modifier. `button`
/// is the one that was pressed, and the one that holds the pointer from then
/// on. `x` and `y` count from the top left corner of that view. A hold ends
/// with `up`, or with `cancel` when the window loses the keyboard meanwhile.
pub const Pointer = struct {
    phase: enum {
        down,
        move,
        up,
        cancel,
    },
    button: MouseButton = .left,
    x: f32 = 0,
    y: f32 = 0,
    clicks: u8 = 1,
    mod: u16 = 0,

    pub fn shift(pointer: Pointer) bool {
        return pointer.mod & shift_bits != 0;
    }
};

pub const KeyPress = struct {
    key: u32 = 0,
    mod: u16 = 0,
    down: bool = false,
    repeat: bool = false,

    pub fn shift(press: KeyPress) bool {
        return press.mod & shift_bits != 0;
    }

    pub fn ctrl(press: KeyPress) bool {
        return press.mod & ctrl_bits != 0;
    }

    pub fn alt(press: KeyPress) bool {
        return press.mod & alt_bits != 0;
    }

    /// Whether the key of shortcuts is held: Cmd on macOS and Ctrl elsewhere,
    /// where Ctrl together with Alt is AltGr, which types characters.
    pub fn command(press: KeyPress) bool {
        if (builtin.os.tag.isDarwin()) return press.mod & gui_bits != 0;
        return press.ctrl() and !press.alt();
    }

    /// Whether the key is Ctrl, Shift, Alt or GUI on either side.
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

/// Text that was typed, or that an input method is still composing: each
/// composition replaces the one before, and an empty one ends it. `text` is
/// UTF-8 and only valid while the function it is given to runs. `marked` are
/// the bytes of a composition that the input method works on, with its caret
/// at their start, or null when it does not tell.
pub const TextInput = struct {
    text: []const u8,
    composing: bool = false,
    marked: ?types.Range = null,
};

/// How far the wheel turned while the pointer was at `at`. As SDL3 reports
/// it, a positive `x` is to the right and a positive `y` is away from the
/// user. `ticks_x` and `ticks_y` are the same turn in whole notches: a wheel
/// that turns smoothly collects a notch before it reports one. `flipped`
/// tells that the system turns the direction around, so that `x` and `y` are
/// the opposite of how the wheel turned. `mod` holds the modifier keys held
/// meanwhile.
pub const Wheel = struct {
    x: f32 = 0,
    y: f32 = 0,
    at: Point = .{},
    ticks_x: i32 = 0,
    ticks_y: i32 = 0,
    flipped: bool = false,
    mod: u16 = 0,

    pub fn shift(wheel: Wheel) bool {
        return wheel.mod & shift_bits != 0;
    }

    pub fn ctrl(wheel: Wheel) bool {
        return wheel.mod & ctrl_bits != 0;
    }
};

/// What the pointer does over a view with a `hover` modifier while no view
/// holds it: it comes over the view or something inside it, moves there, and
/// leaves. `x` and `y` count from the top left corner of that view.
pub const Hover = struct {
    phase: enum { enter, move, leave },
    x: f32 = 0,
    y: f32 = 0,
};

/// A file or a text that was dragged from elsewhere and let go over a view
/// with a `drop` modifier. `data` is the path of the file or the text itself:
/// it is UTF-8 and only valid while the function it is given to runs. `x` and
/// `y` count from the top left corner of that view. Files that are dropped
/// together arrive one after the other.
pub const Drop = struct {
    kind: enum { file, text },
    data: []const u8,
    x: f32 = 0,
    y: f32 = 0,
};

pub const Event = union(enum) {
    pointer_move: Point,
    pointer_leave,
    button: MouseButtonEvent,
    wheel: Wheel,
    /// `x` and `y` count from the top left corner of the window here.
    drop: Drop,
    key: KeyPress,
    text: TextInput,
    /// Whether the keyboard is with the window.
    active: bool,
    close,
};

/// Collects `target` and its ancestors. Like the other searches for input, it
/// passes over what a `when` does not show.
pub fn findPath(node: anytype, target: NodeId, path: *Path) bool {
    if (node.id != target and !each(node, .shown, findPath, .{ target, path })) {
        return false;
    }
    path.push(node.id);
    return true;
}

/// Collects the deepest node at `at` and its ancestors. Later children are in
/// front of earlier ones.
pub fn hit(node: anytype, at: Point, path: *Path) bool {
    const origin = offsetOf(node);
    const x = at.x - origin.x;
    const y = at.y - origin.y;
    if (x < 0 or x >= node.size.width or y < 0 or y >= node.size.height) {
        return false;
    }
    _ = each(node, .front, hit, .{ at, path });
    path.push(node.id);
    return true;
}

pub const Nearest = struct {
    tap: NodeId = 0,
    focusable: NodeId = 0,
};

/// Finds the nearest tap and the nearest focusable node among `target` and
/// its ancestors.
pub fn nearest(node: anytype, target: NodeId, found: *Nearest) bool {
    if (node.id != target and !each(node, .shown, nearest, .{ target, found })) {
        return false;
    }
    const Widget = @TypeOf(node.widget);
    if (comptime handles(Widget, .tap)) {
        if (found.tap == 0) found.tap = node.id;
    }
    if (comptime isFocusable(Widget)) {
        if (found.focusable == 0) found.focusable = node.id;
    }
    return true;
}

/// Records the focusable nodes around `current` while walking the tree in
/// order.
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

    /// Wraps around at both ends.
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
    if (comptime isFocusable(@TypeOf(node.widget)) and !wrapsStop(@TypeOf(node.*))) {
        walk.visit(node.id);
    }
    _ = each(node, .shown, walkFocus, .{walk});
}

fn boundsOf(node: anytype) types.Bounds {
    const at = offsetOf(node);
    return .{
        .x = at.x,
        .y = at.y,
        .w = node.size.width,
        .h = node.size.height,
    };
}

/// The node that takes typed text and where an input method shows what it
/// offers for it. `area` is null when the node takes none at the moment.
pub const Typing = struct {
    target: NodeId = 0,
    area: ?types.Bounds = null,
};

/// Finds the nearest node that takes typed text among `target` and its
/// ancestors. Its area is its bounds, unless a leaf inside it declares
/// `pub fn caret(leaf, bounds) ?ui.Bounds`: the leaf then says where in its
/// bounds the text goes, or null to take none.
pub fn typingArea(node: anytype, target: NodeId, found: *Typing) bool {
    if (node.id != target and !each(node, .shown, typingArea, .{ target, found })) {
        return false;
    }
    if (comptime handles(@TypeOf(node.widget), .input)) {
        if (found.target == 0) {
            found.target = node.id;
            found.area = boundsOf(node);
            _ = each(node, .shown, caretIn, .{&found.area});
        }
    }
    return true;
}

fn caretIn(node: anytype, area: *?types.Bounds) bool {
    if (comptime has(@TypeOf(node.widget), "caret")) {
        area.* = node.widget.caret(boundsOf(node));
        return true;
    }
    return each(node, .shown, caretIn, .{area});
}

/// What is offered to a node and then to its ancestors.
pub const Offer = union(enum) {
    click,
    wheel: Wheel,
    key: KeyPress,
    text: TextInput,
    pointer: Pointer,
    drop: Drop,
};

// Enter and Space activate a tap, except while text is typed: they belong to
// the text then.
fn activates(offer: Offer, state: *const State) bool {
    return switch (offer) {
        .click => true,
        .key => |press| state.typing == null and press.down and
            (press.key == keys.enter or press.key == keys.space),
        .wheel, .text, .pointer, .drop => false,
    };
}

fn handle(
    node: anytype,
    offer: Offer,
    owners: anytype,
    state: *const State,
) bool {
    const Widget = @TypeOf(node.widget);
    if (comptime !@hasDecl(Widget, "handler_kind")) return false;
    const f = Widget.handler;
    switch (comptime Widget.handler_kind) {
        .tap => {
            if (!activates(offer, state)) return false;
            _ = invoke(f, owners, state, {});
        },
        .input => {
            if (offer != .text) return false;
            invoke(f, owners, state, offer.text);
        },
        .key => if (offer != .key or !invoke(f, owners, state, offer.key)) return false,
        .wheel => if (offer != .wheel or !invoke(f, owners, state, offer.wheel)) return false,
        .pointer => {
            if (offer != .pointer) return false;
            const origin = offsetOf(node);
            var local = offer.pointer;
            local.x -= origin.x;
            local.y -= origin.y;
            if (!invoke(f, owners, state, local)) return false;
        },
        .drop => {
            if (offer != .drop) return false;
            const origin = offsetOf(node);
            var local = offer.drop;
            local.x -= origin.x;
            local.y -= origin.y;
            if (!invoke(f, owners, state, local)) return false;
        },
        .hover => return false,
    }
    markTargets(f, owners);
    return true;
}

/// Offers `offer` to `target` and then to its ancestors until one handles
/// it, which `by` then names. Returns whether `target` is inside `node`.
pub fn bubble(
    node: anytype,
    target: NodeId,
    offer: Offer,
    owners: anytype,
    state: *const State,
    by: *NodeId,
) bool {
    const inner = if (comptime node_zig.isComponent(@TypeOf(node.widget))) owners ++ .{node} else owners;
    if (node.id != target and !each(node, .shown, bubble, .{ target, offer, inner, state, by })) {
        return false;
    }
    if (by.* == 0 and handle(node, offer, owners, state)) by.* = node.id;
    return true;
}

/// Whether a node of type `N`, or one inside it, has a `hover` modifier.
pub fn watches(comptime N: type) bool {
    return node_zig.holds(N, isHover);
}

fn isHover(comptime Widget: type) bool {
    return handles(Widget, .hover);
}

/// What the pointer did since the views with a `hover` modifier were told
/// last: `was` and `is` are the paths it was over then and is over now.
pub const Seen = struct {
    was: []const NodeId,
    is: []const NodeId,
    moved: bool,
    at: Point,
};

/// Tells the views with a `hover` modifier what `seen` means to them, the
/// ones inside first. A view that a `when` hides is told that the pointer
/// left it. Sets `told` when a view was told.
pub fn watch(
    node: anytype,
    seen: Seen,
    owners: anytype,
    state: *const State,
    told: *bool,
) void {
    if (comptime !watches(@TypeOf(node.*))) return;
    const Widget = @TypeOf(node.widget);
    const inner = if (comptime node_zig.isComponent(Widget)) owners ++ .{node} else owners;
    _ = each(node, .all, watch, .{ seen, inner, state, told });
    if (comptime !handles(Widget, .hover)) return;

    const was = contains(seen.was, node.id);
    const is = contains(seen.is, node.id);
    if (was == is and !(is and seen.moved)) return;
    const origin = offsetOf(node);
    const hover: Hover = .{
        .phase = if (!was) .enter else if (!is) .leave else .move,
        .x = seen.at.x - origin.x,
        .y = seen.at.y - origin.y,
    };
    _ = invoke(Widget.handler, owners, state, hover);
    markTargets(Widget.handler, owners);
    told.* = true;
}

/// Hands the result of a background function to the `receive` of the
/// component `target`, or of the nearest one around it that takes the
/// result's type in the one parameter that its owners do not fill in. Returns
/// whether `target` is inside `node`.
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
    if (node.id != target and !each(node, .all, deliver, .{ target, task, inner, state, handled })) {
        return false;
    }
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
