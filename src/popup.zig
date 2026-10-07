//! A popup is a view with something to show in front of everything else. What
//! it shows stays where it is written in the tree, so it finds its owners and
//! hands on its keys like any other view, but it is placed, drawn and hit in
//! passes of its own, after the rest.

const std = @import("std");

const anim = @import("anime.zig");
const invoke = @import("call.zig").invoke;
const Canvas = @import("canvas.zig").Canvas;
const input = @import("input.zig");
const pass = @import("layout.zig");
const node_zig = @import("node.zig");
const State = node_zig.State;
const each = node_zig.each;
const isPopup = node_zig.isPopup;
const painter = @import("paint.zig");
const Alignment = @import("view/stack.zig").Alignment;
const markTargets = @import("tree.zig").markTargets;
const types = @import("types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;

/// Where a popup goes: its point `to` lies on the point `from` of the view it
/// belongs to, moved by `offset`. A popup that would leave the window that
/// way goes to the opposite side of the view, the placement mirrored, and
/// where that leaves the window too, it is moved back inside from where it
/// was asked for. Across and down are decided apart.
pub const Placement = struct {
    from: Alignment = .bottom_left,
    to: Alignment = .top_left,
    offset: Point = .{},
};

/// How a popup comes and goes: it fades over `fade`, and grows from `scale`
/// times its size over `grow`, out of the point where it meets its view. It
/// goes the same way back, and takes no input meanwhile. Without durations it
/// shows and hides at once.
pub const Transition = struct {
    scale: f32 = 1,
    grow: anim.Animation = .{ .duration = 0 },
    fade: anim.Animation = .{ .duration = 0 },
};

/// The config of a popup: the first child is the view and the second what it
/// shows while `cond_fn` returns true. The view alone is measured and placed
/// with the rest of the tree. `active` is whether the popup is open, which is
/// when it takes input, and `visible` whether it is drawn, which it still is
/// while it goes. `origin` is the point of the popup that meets the view.
pub fn Popup(comptime cond_fn: anytype, comptime dismiss_fn: anytype) type {
    return struct {
        active: bool = false,
        placement: Placement = .{},
        transition: Transition = .{},
        visible: bool = false,
        origin: Alignment = .top_left,
        grown: anim.Tween(f32) = .init(0),
        faded: anim.Tween(f32) = .init(0),

        const Self = @This();

        pub const cond = cond_fn;
        pub const dismiss = dismiss_fn;

        /// Takes the settings of a popup that a function returned, and keeps
        /// how far this one has come.
        pub fn adopt(p: *Self, next: Self) void {
            p.placement = next.placement;
            p.transition = next.transition;
        }

        pub fn shows(p: Self, comptime child: usize) bool {
            return child == 0 or p.active;
        }

        pub fn measureAll(_: Self, children: anytype, c: Constraint) Extent {
            return pass.measure(&children[0], c);
        }

        pub fn layoutAll(_: Self, children: anytype, at: Point, _: Extent) void {
            pass.layout(&children[0], at);
        }
    };
}

fn pops(comptime N: type) bool {
    return node_zig.holds(N, isPopup);
}

/// Moves the popups that come or go forward in time, after the tree was
/// built.
pub fn advance(node: anytype, state: *State) void {
    if (comptime !pops(@TypeOf(node.*))) return;
    if (comptime isPopup(@TypeOf(node.widget))) {
        const popup = &node.widget;
        const transition = popup.transition;
        const target: f32 = if (popup.active) 1 else 0;
        popup.grown.retarget(transition.grow, target, state.now);
        popup.faded.retarget(transition.fade, target, state.now);
        popup.grown.finish(transition.grow, state.now);
        popup.faded.finish(transition.fade, state.now);
        popup.visible = popup.active or popup.faded.running;
        if (popup.grown.running or popup.faded.running) state.animating = true;
    }
    _ = each(node, .all, advance, .{state});
}

const Side = struct {
    at: f32,
    to: f32,
};

// Where a popup of length `length` begins along one axis, and which of its
// points meets the view then. `start` and `extent` are those of the view.
fn along(
    start: f32,
    extent: f32,
    length: f32,
    from: f32,
    to: f32,
    offset: f32,
    window: f32,
) Side {
    const asked = start + extent * from - length * to + offset;
    if (asked >= 0 and asked + length <= window) return .{ .at = asked, .to = to };
    const mirrored = start + extent * (1 - from) - length * (1 - to) - offset;
    if (mirrored >= 0 and mirrored + length <= window) {
        return .{ .at = mirrored, .to = 1 - to };
    }
    return .{ .at = std.math.clamp(asked, 0, @max(0, window - length)), .to = to };
}

/// Measures and places what the popups show, once everything else has its
/// place. A popup may be as large as the window.
pub fn place(node: anytype, window: Extent) void {
    if (comptime !pops(@TypeOf(node.*))) return;
    if (comptime isPopup(@TypeOf(node.widget))) {
        if (node.widget.visible) {
            const placement = node.widget.placement;
            const content = &node.children[1];
            const size = pass.measure(content, .{ .max = window });
            const across = along(
                node.offset.x,
                node.size.width,
                size.width,
                placement.from.x,
                placement.to.x,
                placement.offset.x,
                window.width,
            );
            const down = along(
                node.offset.y,
                node.size.height,
                size.height,
                placement.from.y,
                placement.to.y,
                placement.offset.y,
                window.height,
            );
            node.widget.origin = .{ .x = across.to, .y = down.to };
            pass.layout(content, .{ .x = across.at, .y = down.at });
        }
    }
    _ = each(node, .shown, place, .{window});
}

/// Draws what the popups show, a popup inside another in front of it.
pub fn paint(node: anytype, canvas: *Canvas) void {
    if (comptime !pops(@TypeOf(node.*))) return;
    if (comptime isPopup(@TypeOf(node.widget))) {
        paint(&node.children[0], canvas);
        const popup = &node.widget;
        if (!popup.visible) return;
        const content = &node.children[1];
        const transition = popup.transition;
        const opacity = popup.faded.at(transition.fade, canvas.now);
        const grown = popup.grown.at(transition.grow, canvas.now);
        const scale = transition.scale + (1 - transition.scale) * grown;
        const settled = opacity >= 1 and scale == 1;
        if (!settled) canvas.pushLayer();
        painter.paint(content, canvas);
        paint(content, canvas);
        if (settled) return;
        const at = node_zig.offsetOf(content);
        return canvas.popScaled(.{
            .x = at.x + content.size.width * popup.origin.x,
            .y = at.y + content.size.height * popup.origin.y,
        }, scale, opacity);
    }
    _ = each(node, .shown, paint, .{canvas});
}

/// The first focusable node of the view of the outermost popup on `path`
/// that is no longer open: where the focus goes when it was in what that
/// popup showed. Returns whether there is such a popup.
pub fn anchorOf(node: anytype, path: []const node_zig.NodeId, anchor: *node_zig.NodeId) bool {
    if (comptime !pops(@TypeOf(node.*))) return false;
    if (!node_zig.contains(path, node.id)) return false;
    if (comptime isPopup(@TypeOf(node.widget))) {
        if (!node.widget.active and node_zig.contains(path, node.children[1].id)) {
            var walk: input.FocusWalk = .{ .current = 0 };
            input.walkFocus(&node.children[0], &walk);
            anchor.* = walk.first;
            return true;
        }
    }
    return each(node, .all, anchorOf, .{ path, anchor });
}

/// Collects the deepest node at `at` in what the open popups show, and its
/// ancestors. Sets `open` when a popup is open, whether `at` is in it or not.
pub fn hit(node: anytype, at: Point, path: anytype, open: *bool) bool {
    if (comptime !pops(@TypeOf(node.*))) return false;
    const found = shown: {
        if (comptime isPopup(@TypeOf(node.widget))) {
            if (node.widget.active) {
                open.* = true;
                const content = &node.children[1];
                break :shown hit(content, at, path, open) or
                    input.hit(content, at, path) or
                    hit(&node.children[0], at, path, open);
            }
        }
        break :shown each(node, .front, hit, .{ at, path, open });
    };
    if (found) path.push(node.id);
    return found;
}

/// Records the focusable nodes of the open popup in front. Returns false
/// when no popup is open.
pub fn walkFocus(node: anytype, walk: *input.FocusWalk) bool {
    if (comptime !pops(@TypeOf(node.*))) return false;
    if (comptime isPopup(@TypeOf(node.widget))) {
        if (node.widget.active) {
            const content = &node.children[1];
            if (!walkFocus(content, walk)) input.walkFocus(content, walk);
            return true;
        }
    }
    return each(node, .front, walkFocus, .{walk});
}

/// Offers `press` to the shortcuts in what the open popup in front shows.
/// Returns false when no popup is open.
pub fn shortcut(
    node: anytype,
    press: input.KeyPress,
    owners: anytype,
    state: *const State,
    by: *node_zig.NodeId,
) bool {
    if (comptime !pops(@TypeOf(node.*))) return false;
    const Widget = @TypeOf(node.widget);
    const inner = if (comptime node_zig.isComponent(Widget)) owners ++ .{node} else owners;
    if (comptime isPopup(Widget)) {
        if (node.widget.active) {
            const content = &node.children[1];
            if (!shortcut(content, press, inner, state, by)) {
                input.shortcut(content, press, inner, state, by);
            }
            return true;
        }
    }
    return each(node, .front, shortcut, .{ press, inner, state, by });
}

/// Runs the `dismiss` of the popups that are open, the ones inside first.
/// Sets `told` when one ran.
pub fn dismiss(
    node: anytype,
    owners: anytype,
    state: *const State,
    told: *bool,
) void {
    if (comptime !pops(@TypeOf(node.*))) return;
    const Widget = @TypeOf(node.widget);
    const inner = if (comptime node_zig.isComponent(Widget)) owners ++ .{node} else owners;
    _ = each(node, .shown, dismiss, .{ inner, state, told });
    if (comptime !isPopup(Widget)) return;
    if (!node.widget.active) return;
    _ = invoke(Widget.dismiss, owners, state, {});
    markTargets(Widget.dismiss, owners);
    told.* = true;
}
