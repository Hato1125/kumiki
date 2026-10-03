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
const tree = @import("tree.zig");

// A tree of views with its focus and pointer. `Impl` hands over the events
// and receives the drawing: `next(wait)` returns the next event or null, and
// with `wait` only once something has arrived; `size()` and `now()`, in
// seconds, are read on every frame; `begin()` returns the canvas to draw to,
// or null to skip the drawing, and `end()` shows it.
pub fn Scene(comptime Impl: type, comptime Root: type) type {
    if (!node_zig.isComponent(Root)) @compileError("the root must be a component with a view");
    inline for (.{ "Options", "init", "deinit", "next", "size", "now", "begin", "end" }) |name| {
        if (!@hasDecl(Impl, name)) @compileError(@typeName(Impl) ++ " is no implementation: it lacks " ++ name);
    }

    return struct {
        impl: Impl,
        state: node_zig.State,
        root: node_zig.Node(Root),
        size: Extent = .{},
        pointer: ?Point = null,
        pending: bool = true,

        const Self = @This();

        // The scene keeps the only copy of `root` that stays up to date, so
        // what the root allocates is freed by its `unmount`, not by the
        // caller.
        pub fn init(gpa: std.mem.Allocator, options: Impl.Options, root: Root) !Self {
            var s: Self = .{ .impl = try Impl.init(gpa, options), .state = .{ .gpa = gpa }, .root = undefined };
            tree.mount(&s.root, root, &s.state, .{});
            return s;
        }

        pub fn deinit(s: *Self) void {
            tree.destroy(&s.root, &s.state, .{});
            s.impl.deinit();
        }

        pub fn run(s: *Self) !void {
            while (try s.frame()) {}
        }

        // Whether the next frame is needed without waiting for input.
        pub fn busy(s: *const Self) bool {
            return s.pending or s.state.animating;
        }

        // Returns false once the implementation reports a close.
        pub fn frame(s: *Self) !bool {
            var wait = !s.busy();
            while (s.impl.next(wait)) |event| : (wait = false) {
                switch (event) {
                    .pointer_move => |at| s.hoverAt(at),
                    .pointer_leave => s.hoverAt(null),
                    .button => |button| s.pressButton(button),
                    .key => |press| s.pressKey(press),
                    .close => return false,
                }
            }
            s.update();

            if (try s.impl.begin()) |canvas| {
                paint(&s.root, canvas);
                try s.impl.end();
            }
            return true;
        }

        // A path that went stale is found again, and dropped when its node
        // is gone or no longer shown. A new layout may have moved something
        // under a still pointer.
        fn update(s: *Self) void {
            const state = &s.state;
            const size = s.impl.size();
            s.pending = false;
            state.now = s.impl.now();
            state.animating = false;
            state.built = false;
            state.stale = false;
            tree.rebuild(&s.root, state, .{});

            if (state.stale) {
                inline for (.{ &state.focus, &state.hover, &state.press }) |path| s.move(path, s.pathTo(path.id()));
            }
            if (!state.built and std.meta.eql(size, s.size)) return;

            s.size = size;
            _ = pass.measure(&s.root, .tight(size));
            pass.layout(&s.root, .{});
            if (s.pointer) |at| s.hoverAt(at);
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
            if (at) |point| _ = input.hit(&s.root, point, &path);
            s.move(&s.state.hover, path);
        }

        // A tap fires when the left button goes up over the tap it went down
        // on. Pressing moves the focus to the nearest focusable node.
        fn pressButton(s: *Self, button: input.MouseButtonEvent) void {
            const state = &s.state;
            s.hoverAt(.{ .x = button.x, .y = button.y });
            if (button.button != .left) return;

            if (button.down) {
                s.setKeyboard(false);
                var found: input.Nearest = .{};
                _ = input.nearest(&s.root, state.hover.id(), &found);
                s.move(&state.press, state.hover.from(found.tap));
                if (found.focusable != 0) s.move(&state.focus, state.hover.from(found.focusable));
                return;
            }

            const target = state.press.id();
            s.move(&state.press, .{});
            if (target != 0 and node_zig.contains(state.hover.slice(), target)) _ = s.offer(target, null);
        }

        // Keys go to the focus first. Tab and Escape move it when nothing
        // used them.
        fn pressKey(s: *Self, press: input.KeyPress) void {
            const state = &s.state;
            if (press.down and !press.isModifier()) s.setKeyboard(true);
            if (state.focus.id() != 0 and s.offer(state.focus.id(), press)) return;
            if (!press.down) return;

            if (press.key == keys.tab) {
                var walk: input.FocusWalk = .{ .current = state.focus.id() };
                input.walkFocus(&s.root, &walk);
                s.move(&state.focus, s.pathTo(walk.result(press.shift())));
            } else if (press.key == keys.escape) {
                s.move(&state.focus, .{});
            }
        }

        fn offer(s: *Self, target: NodeId, press: ?input.KeyPress) bool {
            var handled = false;
            _ = input.bubble(&s.root, target, press, .{}, &s.state, &handled);
            if (handled) s.pending = true;
            return handled;
        }
    };
}
