const std = @import("std");

const Container = @import("mod.zig").Container;
const leaf = @import("mod.zig").leaf;
const Tasks = @import("task.zig").Tasks;
const types = @import("types.zig");
const call = @import("call.zig");
const invoke = call.invoke;
const same = @import("anime.zig").same;
const pass = @import("layout.zig");

/// Counts up from 1. 0 stands for no node.
pub const NodeId = u32;

/// A node and its ancestors, the node itself first, in a tree that is `depth`
/// nodes deep, as `depthOf` counts it.
pub fn Path(comptime depth: usize) type {
    return struct {
        ids: [depth]NodeId = undefined,
        len: usize = 0,

        const Self = @This();

        pub fn slice(path: *const Self) []const NodeId {
            return path.ids[0..path.len];
        }

        pub fn id(path: *const Self) NodeId {
            return if (path.len == 0) 0 else path.ids[0];
        }

        pub fn push(path: *Self, node: NodeId) void {
            path.ids[path.len] = node;
            path.len += 1;
        }

        /// The part of the path from `node` up to the root.
        pub fn from(path: *const Self, node: NodeId) Self {
            var tail: Self = .{};
            const start = std.mem.indexOfScalar(NodeId, path.slice(), node) orelse return tail;
            for (path.ids[start..path.len]) |ancestor| tail.push(ancestor);
            return tail;
        }
    };
}

pub fn contains(path: []const NodeId, id: NodeId) bool {
    return std.mem.indexOfScalar(NodeId, path, id) != null;
}

/// How many nodes lie on the longest way from a node of type `N` down to a
/// leaf, the node itself included: no path in its tree is longer.
pub fn depthOf(comptime N: type) usize {
    return Depth(N).of;
}

// A large tree would exceed the branch quota when counted in one evaluation,
// so every type of node gets a declaration of its own, which counts apart.
fn Depth(comptime N: type) type {
    return struct {
        const of: usize = 1 + inside: {
            const Inside = @FieldType(N, "children");
            if (Inside == void) break :inside 0;

            if (@hasField(Inside, "items")) {
                break :inside Depth(
                    @typeInfo(@FieldType(Inside, "items"))
                        .pointer
                        .child,
                ).of;
            }

            var deepest: usize = 0;
            for (@typeInfo(Inside).@"struct".fields) |child| {
                deepest = @max(deepest, Depth(child.type).of);
            }
            break :inside deepest;
        };
    };
}

/// What a scene shares with every pass over its tree. `animating`, `built` and
/// `stale` tell what the last build did: an animation still runs, something
/// was built again, a path may have changed because a list matched its rows
/// again or a `when` switched. `keyboard` is whether the last input came from
/// the keyboard, and `active` whether the keyboard is with the window of the
/// scene at all. `tasks` lives on the heap, because functions in the
/// background point at it while the scene may still be moved. `inputs` counts
/// the nodes that take typed text, and `typing` is where the implementation
/// was asked for it. `wanted` points at the component that asked for the
/// focus, where the scene keeps it until the tree is built, and `closed` at
/// whether a function asked to close the scene. `focus`, `hover` and `press`
/// are the paths that the scene keeps.
pub const State = struct {
    gpa: std.mem.Allocator,
    tasks: *Tasks,
    host: Host,
    wanted: *NodeId,
    closed: *bool,
    inputs: u32 = 0,
    typing: ?types.Bounds = null,
    active: bool = true,
    next_id: NodeId = 0,
    now: f64 = 0,
    animating: bool = false,
    built: bool = false,
    stale: bool = false,
    focus: []const NodeId = &.{},
    hover: []const NodeId = &.{},
    press: []const NodeId = &.{},
    keyboard: bool = false,
};

/// The implementation as a Context reaches it, for its clipboard. The scene
/// points `impl` at where the implementation is before it runs functions.
pub const Host = struct {
    impl: *anyopaque,
    paste: *const fn (*anyopaque, std.mem.Allocator) ?[]const u8,
    copy: *const fn (*anyopaque, []const u8) bool,
};

fn configHas(comptime View: type, comptime name: []const u8) bool {
    return isContainer(View) and @hasDecl(@FieldType(View, "config"), name);
}

pub fn isComponent(comptime T: type) bool {
    return @hasDecl(T, "view");
}

/// Every view but a component is a container: `children`, which a leaf has
/// none of, and a `config` that measures, places and paints them.
pub fn isContainer(comptime T: type) bool {
    return !isComponent(T) and @hasField(T, "children");
}

pub fn isAnimated(comptime View: type) bool {
    return isContainer(View) and @hasField(@FieldType(View, "config"), "tween");
}

pub fn isShow(comptime View: type) bool {
    return configHas(View, "func");
}

/// Whether `T` is the view of a list or its config, which is its widget.
pub fn isList(comptime T: type) bool {
    return @hasDecl(T, "source") or configHas(T, "source");
}

/// A struct that is neither a component nor a container, such as one of a
/// user's that measures and paints itself, stands for a leaf with it as the
/// config.
pub fn isBare(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and !isComponent(T) and !isContainer(T);
}

/// The view that a value stands for: a bare struct is given the container of
/// a leaf.
pub fn Normalized(comptime View: type) type {
    return if (isBare(View)) Container(void, View) else View;
}

pub const HandlerKind = enum {
    tap,
    key,
    input,
    wheel,
    pointer,
    hover,
    drop,
    shortcut,
};

pub fn handles(comptime T: type, comptime kind: HandlerKind) bool {
    return @hasDecl(T, "handler_kind") and T.handler_kind == kind;
}

pub fn isFocusable(comptime T: type) bool {
    return handles(T, .tap) or handles(T, .key) or handles(T, .input);
}

/// A popup is a container of a view and of what it shows in front of
/// everything else while it is open.
pub fn isPopup(comptime T: type) bool {
    return has(T, "dismiss");
}

/// Whether the widget of a node of type `N`, or of one inside it, matches.
pub fn holds(comptime N: type, comptime matches: fn (comptime type) bool) bool {
    return Holding(N, matches).any;
}

// The answer is a declaration of its own for every type of node, because a
// large tree would exceed the branch quota when counted in one evaluation.
fn Holding(comptime N: type, comptime matches: fn (comptime type) bool) type {
    return struct {
        const any = matches(@FieldType(N, "widget")) or inside: {
            const Inside = @FieldType(N, "children");
            if (Inside == void) break :inside false;
            if (@hasField(Inside, "items")) {
                const Row = @typeInfo(@FieldType(Inside, "items")).pointer.child;
                break :inside Holding(Row, matches).any;
            }
            for (@typeInfo(Inside).@"struct".fields) |child| {
                if (Holding(child.type, matches).any) break :inside true;
            }
            break :inside false;
        };
    };
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
    return if (isShow(View)) ReturnOf(@FieldType(View, "config").func) else View;
}

// Whether a node of `View` keeps its position. One that leaves its children
// where it is, as a component always does, is where its last child is and
// keeps none.
fn keepsOffset(comptime View: type) bool {
    if (isComponent(View)) return false;
    if (@FieldType(View, "children") == void) return true;
    const Config = @FieldType(View, "config");
    return @hasDecl(Config, "layout") or @hasDecl(Config, "layoutAll");
}

pub const Origin = enum { view, function };

fn provided(comptime View: type, inner: anytype, state: *State) Provided(View) {
    comptime for (@typeInfo(@TypeOf(View.provide)).@"fn".params) |param| {
        if (call.Pointee(param.type.?) == Provided(View)) {
            @compileError("the provide of " ++ @typeName(View) ++
                " receives the type it provides");
        }
    };
    return invoke(View.provide, inner, state, {});
}

fn resolve(
    value: anytype,
    state: *State,
    owners: anytype,
) Resolved(@TypeOf(value)) {
    const Value = @TypeOf(value);
    if (comptime !isShow(Value)) return value;
    return invoke(@FieldType(Value, "config").func, owners, state, {});
}

fn destroyChild(node: anytype, state: *State, owners: anytype) void {
    node.destroy(state, owners);
}

fn rebuildChild(node: anytype, state: *State, owners: anytype) void {
    node.rebuild(state, owners);
}

fn markAllChild(node: anytype) void {
    node.markAll();
}

fn markChangedChild(
    node: anytype,
    before: []const NodeId,
    after: []const NodeId,
) void {
    node.markChanged(before, after);
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
        widget: if (isContainer(View)) @FieldType(View, "config") else View,
        children: Children(View),
        dirty: if (isComponent(View)) bool else void,
        arena: if (isComponent(View)) std.heap.ArenaAllocator.State else void,
        given: if (provides(View)) Provided(View) else void,

        const Self = @This();

        pub fn mount(
            node: *Self,
            value: anytype,
            state: *State,
            owners: anytype,
        ) void {
            const Value = @TypeOf(value);
            if (comptime isShow(Value))
                return node.mount(resolve(value, state, owners), state, owners);
            if (comptime isBare(Value))
                return node.mount(leaf(value), state, owners);

            state.next_id += 1;
            node.id = state.next_id;

            if (comptime @TypeOf(node.offset) != void) node.offset = .{};
            node.size = .{};
            if (comptime isComponent(Value)) {
                node.widget = value;
                node.dirty = false;
                node.arena = .init;
                const inner = owners ++ .{node};
                if (comptime @hasDecl(Value, "mount")) {
                    invoke(Value.mount, inner, state, {});
                }
                if (comptime provides(Value)) node.given = provided(Value, inner, state);
                node.children[0].mount(Value.view, state, inner);
            } else if (comptime isList(Value)) {
                node.widget = value.config;
                node.children = .empty;
                node.syncList(state, owners);
            } else if (comptime isAnimated(Value)) {
                const target = resolve(value.children[0], state, owners);
                node.widget = .{ .spec = value.config.spec, .tween = .init(target) };
                node.children[0].mount(target, state, owners);
            } else {
                node.widget = value.config;
                if (comptime handles(@TypeOf(value.config), .input)) {
                    state.inputs += 1;
                }
                if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
                    node.widget.active = invoke(@TypeOf(value.config).cond, owners, state, {});
                }
                if (comptime @TypeOf(value.children) == void) return;
                inline for (0..value.children.len) |i| {
                    node.children[i].mount(value.children[i], state, owners);
                }
            }
        }

        pub fn destroy(node: *Self, state: *State, owners: anytype) void {
            const Widget = @TypeOf(node.widget);
            const inner = if (comptime isComponent(Widget)) owners ++ .{node} else owners;
            _ = each(node, .all, destroyChild, .{ state, inner });
            if (comptime handles(Widget, .input)) state.inputs -= 1;
            if (comptime isComponent(Widget)) {
                if (comptime @hasDecl(Widget, "unmount")) {
                    invoke(Widget.unmount, inner, state, {});
                }
                node.arena.promote(state.gpa).deinit();
            } else if (comptime isList(Widget)) {
                node.children.deinit(state.gpa);
                node.widget.deinitKeys(state.gpa);
            }
        }

        pub fn apply(
            node: *Self,
            value: anytype,
            state: *State,
            owners: anytype,
            comptime origin: Origin,
        ) void {
            const Value = @TypeOf(value);
            if (comptime isShow(Value)) {
                return node.apply(resolve(value, state, owners), state, owners, .function);
            }
            if (comptime isBare(Value)) {
                return node.apply(leaf(value), state, owners, origin);
            }

            if (comptime isComponent(Value)) {
                if (origin == .view) return;
                if (!std.meta.eql(node.widget, value)) node.dirty = true;
                node.widget = value;
            } else if (comptime isList(Value)) {
                if (origin == .function) node.widget.adopt(value.config);
                node.syncList(state, owners);
            } else if (comptime isAnimated(Value)) {
                const Child = @TypeOf(value.children[0]);
                const spec = value.config.spec;
                const tween = &node.widget.tween;
                node.widget.spec = spec;
                tween.retarget(spec, resolve(value.children[0], state, owners), state.now);
                const shown: Origin = if (comptime isShow(Child)) .function else origin;
                node.children[0].apply(tween.at(spec, state.now), state, owners, shown);
                if (tween.running) state.animating = true;
            } else {
                if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
                    const active = invoke(@TypeOf(value.config).cond, owners, state, {});
                    if (active != node.widget.active) state.stale = true;
                    if (origin == .function) {
                        if (comptime @hasDecl(@TypeOf(value.config), "adopt")) {
                            node.widget.adopt(value.config);
                        } else {
                            node.widget = value.config;
                        }
                    }
                    node.widget.active = active;
                } else if (origin == .function) {
                    node.widget = value.config;
                }
                if (comptime @TypeOf(value.children) == void) return;
                inline for (0..value.children.len) |i| {
                    node.children[i].apply(value.children[i], state, owners, origin);
                }
            }
        }

        pub fn rebuild(node: *Self, state: *State, owners: anytype) void {
            const Widget = @TypeOf(node.widget);
            if (comptime isComponent(Widget)) {
                const inner = owners ++ .{node};
                if (node.dirty) {
                    @branchHint(.unlikely);
                    const last = node.arena.promote(state.gpa);
                    node.arena = .init;
                    node.dirty = false;
                    state.built = true;

                    if (comptime provides(Widget)) {
                        const next = provided(Widget, inner, state);
                        if (!same(Provided(Widget), next, node.given)) {
                            node.children[0].markAll();
                        }
                        node.given = next;
                    }
                    node.children[0].apply(Widget.view, state, inner, .view);
                    node.children[0].rebuild(state, inner);
                    return last.deinit();
                }
                return node.children[0].rebuild(state, inner);
            }
            if (comptime @TypeOf(node.children) == void) return;
            if (comptime @hasField(Widget, "tween")) {
                const tween = &node.widget.tween;
                if (tween.running) {
                    node.children[0].apply(
                        tween.at(node.widget.spec, state.now),
                        state,
                        owners,
                        .function,
                    );

                    tween.finish(node.widget.spec, state.now);
                    if (tween.running) state.animating = true;
                    const size = node.size;
                    if (std.meta.eql(pass.measure(node, node.widget.constraint), size)) {
                        pass.layout(node, offsetOf(node));
                    } else {
                        state.built = true;
                    }
                }
            }
            _ = each(node, .all, rebuildChild, .{ state, owners });
        }

        pub fn markAll(node: *Self) void {
            if (comptime isComponent(@TypeOf(node.widget))) node.dirty = true;
            _ = each(node, .all, markAllChild, .{});
        }

        pub fn markChanged(
            node: *Self,
            before: []const NodeId,
            after: []const NodeId,
        ) void {
            const was = contains(before, node.id);
            const is = contains(after, node.id);
            if (!was and !is) return;
            if (comptime isComponent(@TypeOf(node.widget))) {
                if (was != is) node.dirty = true;
            }
            _ = each(node, .all, markChangedChild, .{ before, after });
        }

        fn syncList(node: *Self, state: *State, owners: anytype) void {
            const List = @TypeOf(node.widget);
            const elements = invoke(List.source, owners, state, {});
            state.stale = true;
            if (comptime List.keyed)
                return node.syncKeyed(elements, state, owners);

            const rows = &node.children;
            const kept = @min(elements.len, rows.items.len);

            for (rows.items[0..kept], 0..) |*row, i|
                row.apply(List.item(elements, i), state, owners, .function);
            for (rows.items[kept..]) |*row|
                row.destroy(state, owners);

            rows.shrinkRetainingCapacity(kept);
            rows.ensureTotalCapacity(state.gpa, elements.len) catch @panic("out of memory");
            for (kept..elements.len) |i| {
                rows.addOneAssumeCapacity().mount(List.item(elements, i), state, owners);
            }
        }

        fn syncKeyed(
            node: *Self,
            elements: anytype,
            state: *State,
            owners: anytype,
        ) void {
            const List = @TypeOf(node.widget);
            var old_rows = node.children;
            var old_keys = node.widget.keys;
            defer old_rows.deinit(state.gpa);
            defer old_keys.deinit(state.gpa);

            const rows = &node.children;
            const keys = &node.widget.keys;
            rows.* = .empty;
            keys.* = .empty;
            rows.ensureTotalCapacityPrecise(state.gpa, elements.len) catch @panic("out of memory");
            keys.ensureTotalCapacityPrecise(state.gpa, elements.len) catch @panic("out of memory");

            var next: usize = 0;
            for (elements, 0..) |element, i| {
                const row = rows.addOneAssumeCapacity();
                const found = for (0..old_rows.items.len) |n| {
                    const j = (next + n) % old_rows.items.len;
                    if (old_rows.items[j].id != 0 and List.sameKey(old_keys.items[j], element.id)) {
                        break j;
                    }
                } else null;

                if (found) |j| {
                    row.* = old_rows.items[j];
                    old_rows.items[j].id = 0;
                    keys.appendAssumeCapacity(old_keys.items[j]);
                    row.apply(List.item(elements, i), state, owners, .function);
                    next = j + 1;
                } else {
                    keys.appendAssumeCapacity(List.ownKey(state.gpa, element.id));
                    row.mount(List.item(elements, i), state, owners);
                }
            }
            for (old_rows.items, old_keys.items) |*row, key| {
                if (row.id == 0) continue;
                row.destroy(state, owners);
                List.freeKey(state.gpa, key);
            }
        }
    };
}

pub fn NodeOf(comptime View: type) type {
    return Node(Normalized(Resolved(View)));
}

/// Where a node is: at its own offset, or where its last child is for a node
/// that keeps none.
pub fn offsetOf(node: anytype) types.Point {
    if (comptime @TypeOf(node.offset) != void) return node.offset;
    return offsetOf(&node.children[node.children.len - 1]);
}

fn Children(comptime View: type) type {
    if (isComponent(View)) return struct { NodeOf(@TypeOf(View.view)) };
    if (!isContainer(View)) {
        @compileError(@typeName(View) ++ " is no view: not a struct");
    }
    if (isList(View)) return std.ArrayList(Node(@FieldType(View, "config").Row));
    const Inside = @FieldType(View, "children");
    if (Inside == void) return void;
    const fields = @typeInfo(Inside).@"struct".fields;
    var element_types: [fields.len]type = undefined;
    for (fields, 0..) |field, i| element_types[i] = NodeOf(field.type);
    return @Tuple(&element_types);
}

pub const Order = enum {
    all,
    shown,
    front,
};

/// Calls `f(child, args...)` for the children of `node` until a call returns
/// true. `shown` leaves out what a config with a `cond` does not show, such as
/// the other side of a `when`, and `front` also starts from the child in
/// front.
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
        if (!partly or node.widget.shows(i)) {
            if (stops(@call(.auto, f, .{&children[i]} ++ args))) return true;
        }
    }
    return false;
}

fn stops(result: anytype) bool {
    return @TypeOf(result) == bool and result;
}
