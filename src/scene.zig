const std = @import("std");

const types = @import("types.zig");
const Extent = types.Extent;
const Point = types.Point;
const input = @import("input.zig");
const keys = input.keys;
const pass = @import("layout.zig");
const node_zig = @import("node.zig");
const NodeId = node_zig.NodeId;
const Path = node_zig.Path;
const paint = @import("paint.zig").paint;
const popup = @import("popup.zig");
const Tasks = @import("task.zig").Tasks;
const tree = @import("tree.zig");

/// A tree of views with its focus and pointer. `Impl` hands over the events
/// and receives the drawing: `next(wait)` returns the next event or null, and
/// waits up to `wait` seconds for one to arrive, not at all for 0 and without
/// end for infinity; `size()` and `now()`, in seconds, are read on every
/// frame; `begin()` returns the canvas to draw to, or null to skip the
/// drawing, and `end()` shows it; `wake()` makes a waiting `next`, or else
/// the next one that waits, return, and is called from other threads;
/// `input(area)` starts the typing of text at `area`, or stops it when the
/// area is null, which also ends what an input method is composing;
/// `copy(text)` puts text into the clipboard and returns whether it took it,
/// and `paste(allocator)` returns a copy of what it holds, or null.
pub fn Scene(comptime Impl: type, comptime Root: type) type {
    if (!node_zig.isComponent(Root)) {
        @compileError("the root must be a component with a view");
    }
    inline for (.{
        "Options", "init", "deinit", "next",  "size", "now",
        "begin",   "end",  "wake",   "input", "copy", "paste",
    }) |name| {
        if (!@hasDecl(Impl, name)) {
            @compileError(@typeName(Impl) ++
                " is no implementation: it lacks " ++ name);
        }
    }

    return struct {
        impl: Impl,
        state: node_zig.State,
        root: node_zig.Node(Root),
        size: Extent = .{},
        pointer: ?Point = null,
        pending: bool = true,
        /// The node that holds the pointer and the button it holds it with,
        /// and where the pointer was seen last, which is kept while it is
        /// outside the window.
        held: NodeId = 0,
        held_by: input.MouseButton = .left,
        last: Point = .{},
        /// What the views that watch the pointer were told last: the path
        /// it was over, and where it was.
        told: Path = .{},
        told_at: Point = .{},
        /// The node that takes the typed text.
        typing: NodeId = 0,
        /// The component that asked for the focus since the last build.
        wanted: NodeId = 0,
        /// When the last drawing asked for the next one.
        again: f64 = std.math.inf(f64),

        const Self = @This();

        /// The scene keeps the only copy of `root` that stays up to date, so
        /// what the root allocates is freed by its `unmount`, not by the
        /// caller.
        pub fn init(
            gpa: std.mem.Allocator,
            options: Impl.Options,
            root: Root,
        ) !Self {
            const tasks = gpa.create(Tasks) catch @panic("out of memory");
            errdefer gpa.destroy(tasks);
            tasks.* = .{ .gpa = gpa, .wake = wake };
            var s: Self = .{
                .impl = try Impl.init(gpa, options),
                .state = .{
                    .gpa = gpa,
                    .tasks = tasks,
                    .wanted = undefined,
                    .host = .{
                        .impl = undefined,
                        .paste = paste,
                        .copy = copy,
                    },
                },
                .root = undefined,
            };
            s.state.host.impl = &s.impl;
            s.state.wanted = &s.wanted;
            tree.mount(&s.root, root, &s.state, .{});
            return s;
        }

        /// Waits for the functions that still run in the background. The
        /// tree goes first, because an `unmount` may spawn one more.
        pub fn deinit(s: *Self) void {
            s.state.host.impl = &s.impl;
            s.state.wanted = &s.wanted;
            tree.destroy(&s.root, &s.state, .{});
            s.state.tasks.deinit();
            s.impl.deinit();
            s.state.gpa.destroy(s.state.tasks);
        }

        fn wake(impl: *anyopaque) void {
            Impl.wake(@ptrCast(@alignCast(impl)));
        }

        fn paste(impl: *anyopaque, into: std.mem.Allocator) ?[]const u8 {
            return Impl.paste(@ptrCast(@alignCast(impl)), into);
        }

        fn copy(impl: *anyopaque, text: []const u8) bool {
            return Impl.copy(@ptrCast(@alignCast(impl)), text);
        }

        pub fn run(s: *Self) !void {
            while (try s.frame()) {}
        }

        /// Whether the next frame is needed without waiting for input.
        pub fn busy(s: *const Self) bool {
            return s.pending or s.state.animating or s.strays();
        }

        // Whether a view holds the pointer outside its bounds.
        fn strays(s: *const Self) bool {
            return s.held != 0 and !node_zig.contains(s.state.hover.slice(), s.held);
        }

        /// Returns false once the implementation reports a close. The scene
        /// must stay where it is from its first frame on, because a function
        /// in the background wakes the implementation where the last frame
        /// found it.
        pub fn frame(s: *Self) !bool {
            s.state.host.impl = &s.impl;
            s.state.wanted = &s.wanted;
            s.state.tasks.waker.store(&s.impl, .release);
            var wait = if (s.busy()) 0 else s.again - s.impl.now();
            while (s.impl.next(wait)) |event| : (wait = 0) {
                s.state.now = s.impl.now();
                switch (event) {
                    .pointer_move => |at| {
                        s.hoverAt(at);
                        s.hold(.move);
                    },
                    .pointer_leave => s.hoverAt(null),
                    .button => |button| s.pressButton(button),
                    .wheel => |wheel| {
                        s.hoverAt(wheel.at);
                        if (s.state.hover.id() != 0) {
                            _ = s.offer(s.state.hover.id(), .{ .wheel = wheel });
                        }
                    },
                    .drop => |drop| {
                        s.hoverAt(.{ .x = drop.x, .y = drop.y });
                        if (s.state.hover.id() != 0) {
                            _ = s.offer(s.state.hover.id(), .{ .drop = drop });
                        }
                    },
                    .key => |press| s.pressKey(press),
                    .text => |text| if (s.state.focus.id() != 0) {
                        _ = s.offer(s.state.focus.id(), .{ .text = text });
                    },
                    .active => |active| s.activate(active),
                    .close => return false,
                }
            }
            s.state.now = s.impl.now();
            if (s.strays()) s.hold(.move);
            s.receive();
            s.update();

            s.again = std.math.inf(f64);
            if (try s.impl.begin()) |canvas| {
                canvas.now = s.state.now;
                canvas.again = s.again;
                paint(&s.root, canvas);
                popup.paint(&s.root, canvas);
                s.again = canvas.again;
                try s.impl.end();
            }
            return true;
        }

        // Hands over what the background functions that have ended returned.
        // A result is dropped when the component that spawned it is gone.
        fn receive(s: *Self) void {
            while (s.state.tasks.take()) |task| {
                var handled = false;
                const found = input.deliver(&s.root, task.tag, task, .{}, &s.state, &handled);
                if (found and !handled) {
                    @panic("no component receives the result of a background function");
                }
                if (handled) s.pending = true;
                task.destroy(task, s.state.gpa);
            }
        }

        // A path that went stale is found again, and dropped when its node
        // is gone or no longer shown. The focus that was in a popup goes back
        // to the view of the popup when that closes. A new layout may have moved something
        // under a still pointer.
        fn update(s: *Self) void {
            const state = &s.state;
            const size = s.impl.size();
            s.pending = false;
            state.animating = false;
            state.built = false;
            state.stale = false;
            tree.rebuild(&s.root, state, .{});
            popup.advance(&s.root, state);

            if (state.stale) {
                var focus = s.pathTo(state.focus.id());
                if (focus.id() == 0) {
                    var anchor: NodeId = 0;
                    _ = popup.anchorOf(&s.root, state.focus.slice(), &anchor);
                    focus = s.pathTo(anchor);
                }
                s.move(&state.focus, focus);
                inline for (.{ &state.hover, &state.press }) |path| {
                    s.move(path, s.pathTo(path.id()));
                }
                if (s.pathTo(s.held).id() == 0) s.held = 0;
            }
            if (s.wanted != 0) {
                var walk: input.FocusWalk = .{ .current = 0 };
                _ = input.walkFocusIn(&s.root, s.wanted, &walk);
                s.wanted = 0;
                if (walk.first != 0) s.move(&state.focus, s.pathTo(walk.first));
            }
            if (state.built or !std.meta.eql(size, s.size)) {
                s.size = size;
                _ = pass.measure(&s.root, .tight(size));
                pass.layout(&s.root, .{});
                popup.place(&s.root, size);
                if (s.pointer) |at| s.hoverAt(at);
            }
            if (state.inputs != 0 or s.typing != 0) s.retype();
        }

        // Asks the implementation for typed text where the focus is on an
        // input or inside one, and no longer when it is not. The input that
        // the typing leaves is offered an empty composition, and the
        // implementation is stopped, so that a composition under way ends
        // on both sides instead of going on in the next input.
        fn retype(s: *Self) void {
            var found: input.Typing = .{};
            const focus = s.state.focus.id();
            if (s.state.active and focus != 0) {
                _ = input.typingArea(&s.root, focus, &found);
            }
            if (found.target != s.typing and s.typing != 0) {
                _ = s.offer(s.typing, .{
                    .text = .{ .text = "", .composing = true },
                });
                if (s.state.typing != null) s.impl.input(null);
                s.state.typing = null;
            }
            s.typing = found.target;
            if (std.meta.eql(found.area, s.state.typing)) return;
            s.state.typing = found.area;
            s.impl.input(found.area);
        }

        fn pathTo(s: *Self, id: NodeId) Path {
            var path: Path = .{};
            if (id != 0) _ = input.findPath(&s.root, id, &path);
            return path;
        }

        // The components that the path enters or leaves are built again.
        fn move(s: *Self, path: *Path, next: Path) void {
            if (next.id() == path.id()) return;
            tree.markChanged(&s.root, path.slice(), next.slice());
            path.* = next;
            s.pending = true;
        }

        // The components around the focus show it differently, so they are
        // built again when the kind of input changes.
        fn setKeyboard(s: *Self, keyboard: bool) void {
            if (keyboard == s.state.keyboard) return;
            s.state.keyboard = keyboard;
            tree.markChanged(&s.root, s.state.focus.slice(), &.{});
            s.pending = true;
        }

        // While a popup is open, the pointer is over what the popups show
        // or over nothing.
        fn hoverAt(s: *Self, at: ?Point) void {
            s.pointer = at;
            var path: Path = .{};
            if (at) |point| {
                s.last = point;
                var open = false;
                if (!popup.hit(&s.root, point, &path, &open) and !open) {
                    _ = input.hit(&s.root, point, &path);
                }
            }
            s.move(&s.state.hover, path);
            s.watch();
        }

        // Tells the views with a `hover` modifier what the pointer did since
        // they were told last. A path that went stale in between is told at
        // the next hit.
        fn watch(s: *Self) void {
            if (comptime !input.watches(@TypeOf(s.root))) return;
            const hover = &s.state.hover;
            const moved = !std.meta.eql(s.last, s.told_at);
            if (!moved and hover.id() == s.told.id()) return;

            var told = false;
            input.watch(&s.root, .{
                .was = s.told.slice(),
                .is = hover.slice(),
                .moved = moved,
                .at = s.last,
            }, .{}, &s.state, &told);
            s.told = hover.*;
            s.told_at = s.last;
            if (told) s.pending = true;
        }

        // Returns whether a popup was open to be dismissed.
        fn dismiss(s: *Self) bool {
            var told = false;
            popup.dismiss(&s.root, .{}, &s.state, &told);
            if (told) s.pending = true;
            return told;
        }

        // Tells the view that holds the pointer what the pointer does.
        fn hold(s: *Self, phase: @FieldType(input.Pointer, "phase")) void {
            if (s.held == 0) return;
            _ = s.offer(s.held, .{ .pointer = .{
                .phase = phase,
                .button = s.held_by,
                .x = s.last.x,
                .y = s.last.y,
            } });
        }

        // Without the keyboard nothing has the focus, so what shows the
        // focus is built again. A pointer that is held is let go, because
        // its release may never arrive.
        fn activate(s: *Self, active: bool) void {
            if (active == s.state.active) return;
            s.state.active = active;
            tree.markChanged(&s.root, s.state.focus.slice(), &.{});
            s.pending = true;
            if (active) return;
            s.hold(.cancel);
            s.held = 0;
            s.move(&s.state.press, .{});
        }

        // A press outside the open popups dismisses them. The left button
        // does nothing else then, so that the view of a popup does not open
        // it again, while another button goes on to what lies there once the
        // popups are gone, so that a menu can open again where it is asked
        // for. Pressing the left button moves the focus to the nearest
        // focusable node. A press is offered to the views that take the pointer, and
        // one that uses it holds the pointer until that button is released:
        // the other buttons do nothing meanwhile, and a tap that was pressed
        // is let go. Otherwise a tap fires when the left button goes up over
        // the tap it went down on.
        fn pressButton(s: *Self, button: input.MouseButtonEvent) void {
            const state = &s.state;
            s.hoverAt(.{ .x = button.x, .y = button.y });
            const left = button.button == .left;

            if (button.down) {
                if (s.held != 0) return;
                if (state.hover.id() == 0 and s.dismiss()) {
                    if (left) return;
                    s.update();
                    s.hoverAt(.{ .x = button.x, .y = button.y });
                }
                var found: input.Nearest = .{};
                if (left) {
                    s.setKeyboard(false);
                    _ = input.nearest(&s.root, state.hover.id(), &found);
                    if (found.focusable != 0) {
                        s.move(&state.focus, state.hover.from(found.focusable));
                    }
                }
                s.held = if (state.hover.id() == 0) 0 else s.offer(state.hover.id(), .{ .pointer = .{
                    .phase = .down,
                    .button = button.button,
                    .x = button.x,
                    .y = button.y,
                    .clicks = button.clicks,
                    .mod = button.mod,
                } });
                s.held_by = button.button;
                if (s.held != 0) {
                    s.move(&state.press, .{});
                } else if (left) {
                    s.move(&state.press, state.hover.from(found.tap));
                }
                return;
            }

            if (s.held != 0) {
                if (button.button != s.held_by) return;
                s.hold(.up);
                s.held = 0;
                return;
            }
            if (!left) return;
            const target = state.press.id();
            s.move(&state.press, .{});
            if (target != 0 and node_zig.contains(state.hover.slice(), target)) {
                _ = s.offer(target, .click);
            }
        }

        // Keys go to the focus first, and then to the shortcuts. When nothing
        // used them, Tab moves the focus and Escape drops it. While a popup is open, the focus moves
        // inside the one in front, with the up and down keys too, and Escape
        // dismisses the popups instead.
        fn pressKey(s: *Self, press: input.KeyPress) void {
            const state = &s.state;
            if (press.down and !press.isModifier()) s.setKeyboard(true);
            if (state.focus.id() != 0 and s.offer(state.focus.id(), .{ .key = press }) != 0) {
                return;
            }
            if (!press.down) return;
            if (s.shortcut(press)) return;

            if (press.key == keys.escape) {
                if (!s.dismiss()) s.move(&state.focus, .{});
                return;
            }
            const tab = press.key == keys.tab;
            const arrow = press.key == keys.up or press.key == keys.down;
            if (!tab and !arrow) return;
            var walk: input.FocusWalk = .{ .current = state.focus.id() };
            const inside = popup.walkFocus(&s.root, &walk);
            if (!inside and !tab) return;
            if (!inside) input.walkFocus(&s.root, &walk);
            const backward = if (tab) press.shift() else press.key == keys.up;
            s.move(&state.focus, s.pathTo(walk.result(backward)));
        }

        // Returns whether a shortcut ran.
        fn shortcut(s: *Self, press: input.KeyPress) bool {
            if (comptime !input.binds(@TypeOf(s.root))) return false;
            var by: NodeId = 0;
            if (!popup.shortcut(&s.root, press, .{}, &s.state, &by)) {
                input.shortcut(&s.root, press, .{}, &s.state, &by);
            }
            if (by != 0) s.pending = true;
            return by != 0;
        }

        // Returns the node that handled it, or 0.
        fn offer(s: *Self, target: NodeId, what: input.Offer) NodeId {
            var by: NodeId = 0;
            _ = input.bubble(&s.root, target, what, .{}, &s.state, &by);
            if (by != 0) s.pending = true;
            return by;
        }
    };
}
