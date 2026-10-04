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
const Tasks = @import("task.zig").Tasks;
const tree = @import("tree.zig");

// A tree of views with its focus and pointer. `Impl` hands over the events
// and receives the drawing: `next(wait)` returns the next event or null, and
// waits up to `wait` seconds for one to arrive, not at all for 0 and without
// end for infinity; `size()` and `now()`, in seconds, are read on every
// frame; `begin()` returns the canvas to draw to, or null to skip the
// drawing, and `end()` shows it; `wake()` makes a waiting `next`, or else
// the next one that waits, return, and is called from other threads;
// `input(area)` starts the typing of text at `area`, or stops it when the
// area is null; `copy(text)` puts text into the clipboard and returns
// whether it took it, and `paste(allocator)` returns a copy of what it
// holds, or null.
pub fn Scene(comptime Impl: type, comptime Root: type) type {
    if (!node_zig.isComponent(Root)) @compileError("the root must be a component with a view");
    inline for (.{
        "Options", "init", "deinit", "next",  "size", "now",
        "begin",   "end",  "wake",   "input", "copy", "paste",
    }) |name| {
        if (!@hasDecl(Impl, name)) @compileError(@typeName(Impl) ++ " is no implementation: it lacks " ++ name);
    }

    return struct {
        impl: Impl,
        state: node_zig.State,
        root: node_zig.Node(Root),
        size: Extent = .{},
        pointer: ?Point = null,
        pending: bool = true,
        // The node that holds the pointer, and where the pointer was seen
        // last, which is kept while it is outside the window.
        held: NodeId = 0,
        last: Point = .{},
        // When the last drawing asked for the next one.
        again: f64 = std.math.inf(f64),

        const Self = @This();

        // The scene keeps the only copy of `root` that stays up to date, so
        // what the root allocates is freed by its `unmount`, not by the
        // caller.
        pub fn init(gpa: std.mem.Allocator, options: Impl.Options, root: Root) !Self {
            const tasks = gpa.create(Tasks) catch @panic("out of memory");
            errdefer gpa.destroy(tasks);
            tasks.* = .{ .gpa = gpa, .wake = wake };
            var s: Self = .{
                .impl = try Impl.init(gpa, options),
                .state = .{ .gpa = gpa, .tasks = tasks, .host = .{ .impl = undefined, .paste = paste, .copy = copy } },
                .root = undefined,
            };
            s.state.host.impl = &s.impl;
            tree.mount(&s.root, root, &s.state, .{});
            return s;
        }

        // Waits for the functions that still run in the background. The
        // tree goes first, because an `unmount` may spawn one more.
        pub fn deinit(s: *Self) void {
            s.state.host.impl = &s.impl;
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

        // Whether the next frame is needed without waiting for input.
        pub fn busy(s: *const Self) bool {
            return s.pending or s.state.animating or s.strays();
        }

        // Whether a view holds the pointer outside its bounds.
        fn strays(s: *const Self) bool {
            return s.held != 0 and !node_zig.contains(s.state.hover.slice(), s.held);
        }

        // Returns false once the implementation reports a close. The scene
        // must stay where it is from its first frame on, because a function
        // in the background wakes the implementation where the last frame
        // found it.
        pub fn frame(s: *Self) !bool {
            s.state.host.impl = &s.impl;
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
                        if (s.state.hover.id() != 0) _ = s.offer(s.state.hover.id(), .{ .wheel = wheel });
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
                if (found and !handled) @panic("no component receives the result of a background function");
                if (handled) s.pending = true;
                task.destroy(task, s.state.gpa);
            }
        }

        // A path that went stale is found again, and dropped when its node
        // is gone or no longer shown. A new layout may have moved something
        // under a still pointer.
        fn update(s: *Self) void {
            const state = &s.state;
            const size = s.impl.size();
            s.pending = false;
            state.animating = false;
            state.built = false;
            state.stale = false;
            tree.rebuild(&s.root, state, .{});

            if (state.stale) {
                inline for (.{ &state.focus, &state.hover, &state.press }) |path| s.move(path, s.pathTo(path.id()));
                if (s.pathTo(s.held).id() == 0) s.held = 0;
            }
            if (state.built or !std.meta.eql(size, s.size)) {
                s.size = size;
                _ = pass.measure(&s.root, .tight(size));
                pass.layout(&s.root, .{});
                if (s.pointer) |at| s.hoverAt(at);
            }
            if (state.inputs != 0 or state.typing != null) s.retype();
        }

        // Asks the implementation for typed text where the focus is on an
        // input or inside one, and no longer when it is not.
        fn retype(s: *Self) void {
            var area: ?types.Bounds = null;
            const focus = s.state.focus.id();
            if (s.state.active and focus != 0) _ = input.typingArea(&s.root, focus, &area);
            if (std.meta.eql(area, s.state.typing)) return;
            s.state.typing = area;
            s.impl.input(area);
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

        fn hoverAt(s: *Self, at: ?Point) void {
            s.pointer = at;
            var path: Path = .{};
            if (at) |point| {
                s.last = point;
                _ = input.hit(&s.root, point, &path);
            }
            s.move(&s.state.hover, path);
        }

        // Tells the view that holds the pointer what the pointer does.
        fn hold(s: *Self, phase: @FieldType(input.Pointer, "phase")) void {
            if (s.held == 0) return;
            _ = s.offer(s.held, .{ .pointer = .{ .phase = phase, .x = s.last.x, .y = s.last.y } });
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

        // Pressing moves the focus to the nearest focusable node. The press
        // is offered to the views that take the pointer, and one that uses
        // it holds the pointer until the release. Otherwise a tap fires when
        // the left button goes up over the tap it went down on.
        fn pressButton(s: *Self, button: input.MouseButtonEvent) void {
            const state = &s.state;
            s.hoverAt(.{ .x = button.x, .y = button.y });
            if (button.button != .left) return;

            if (button.down) {
                s.setKeyboard(false);
                var found: input.Nearest = .{};
                _ = input.nearest(&s.root, state.hover.id(), &found);
                if (found.focusable != 0) s.move(&state.focus, state.hover.from(found.focusable));
                s.held = if (state.hover.id() == 0) 0 else s.offer(state.hover.id(), .{ .pointer = .{
                    .phase = .down,
                    .x = button.x,
                    .y = button.y,
                    .clicks = button.clicks,
                    .mod = button.mod,
                } });
                if (s.held == 0) s.move(&state.press, state.hover.from(found.tap));
                return;
            }

            if (s.held != 0) {
                s.hold(.up);
                s.held = 0;
                return;
            }
            const target = state.press.id();
            s.move(&state.press, .{});
            if (target != 0 and node_zig.contains(state.hover.slice(), target)) _ = s.offer(target, .click);
        }

        // Keys go to the focus first. Tab and Escape move it when nothing
        // used them.
        fn pressKey(s: *Self, press: input.KeyPress) void {
            const state = &s.state;
            if (press.down and !press.isModifier()) s.setKeyboard(true);
            if (state.focus.id() != 0 and s.offer(state.focus.id(), .{ .key = press }) != 0) return;
            if (!press.down) return;

            if (press.key == keys.tab) {
                var walk: input.FocusWalk = .{ .current = state.focus.id() };
                input.walkFocus(&s.root, &walk);
                s.move(&state.focus, s.pathTo(walk.result(press.shift())));
            } else if (press.key == keys.escape) {
                s.move(&state.focus, .{});
            }
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
