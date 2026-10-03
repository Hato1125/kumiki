const std = @import("std");

const call = @import("call.zig");
const invoke = call.invoke;
const node_zig = @import("node.zig");
const Resolved = node_zig.Resolved;
const State = node_zig.State;
const contains = node_zig.contains;
const each = node_zig.each;
const isComponent = node_zig.isComponent;
const isContainer = node_zig.isContainer;
const isList = node_zig.isList;
const isShow = node_zig.isShow;

fn isAnimated(comptime View: type) bool {
    return isContainer(View) and @hasField(@FieldType(View, "config"), "tween");
}

// What a view stands for: the result of its function for a `show`.
fn resolve(value: anytype, state: *State, owners: anytype) Resolved(@TypeOf(value)) {
    const View = @TypeOf(value);
    return if (comptime isShow(View)) invoke(View.func, owners, state, {}) else value;
}

// Builds the node of `value` in `node`. A node holds the nodes of everything
// inside it, so returning nodes by value would copy a large tree once per
// level and overflow the stack.
//
// A component may declare `pub fn mount` and `pub fn unmount`. They run when
// its node enters and leaves the tree, and their parameters are filled in by
// type, as described at `invoke` in call.zig.
pub fn mount(node: anytype, value: anytype, state: *State, owners: anytype) void {
    const View = @TypeOf(value);
    if (comptime isShow(View)) return mount(node, resolve(value, state, owners), state, owners);

    state.next_id += 1;
    node.id = state.next_id;
    node.offset = .{};
    node.size = .{};
    if (comptime isComponent(View)) {
        node.widget = value;
        node.dirty = false;
        node.arena = .init;
        const inner = owners ++ .{node};
        if (comptime @hasDecl(View, "mount")) invoke(View.mount, inner, state, {});
        mount(&node.children[0], View.view, state, inner);
    } else if (comptime isList(View)) {
        node.widget = value;
        node.children = .empty;
        syncList(node, state, owners);
    } else if (comptime !isContainer(View)) {
        node.widget = value;
    } else if (comptime isAnimated(View)) {
        const target = resolve(value.children[0], state, owners);
        node.widget = .{ .spec = value.config.spec, .tween = .init(target) };
        mount(&node.children[0], target, state, owners);
    } else {
        node.widget = value.config;
        if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
            node.widget.active = invoke(@TypeOf(value.config).cond, owners, state, {});
        }
        inline for (0..value.children.len) |i| mount(&node.children[i], value.children[i], state, owners);
    }
}

pub fn destroy(node: anytype, state: *State, owners: anytype) void {
    const Widget = @TypeOf(node.widget);
    const inner = if (comptime isComponent(Widget)) owners ++ .{node} else owners;
    _ = each(node, .all, destroy, .{ state, inner });
    if (comptime isComponent(Widget)) {
        if (comptime @hasDecl(Widget, "unmount")) invoke(Widget.unmount, inner, state, {});
        node.arena.promote(state.gpa).deinit();
    } else if (comptime isList(Widget)) {
        node.children.deinit(state.gpa);
        node.widget.deinitKeys(state.gpa);
    }
}

// Where a value given to `apply` comes from. A value written in a `view` is
// the same on every build, so the node already holds it, while a function
// may return a different one.
const Origin = enum { view, function };

// Brings `node` up to date with `value`. A component written in a view is
// left alone, because storing it again would erase the state in its fields.
// One returned by a function is built again unless it is identical, slices
// compared by where they point: what it shows may point at older strings.
fn apply(node: anytype, value: anytype, state: *State, owners: anytype, comptime origin: Origin) void {
    const View = @TypeOf(value);
    if (comptime isShow(View)) return apply(node, resolve(value, state, owners), state, owners, .function);

    if (comptime isComponent(View)) {
        if (origin == .view) return;
        if (!std.meta.eql(node.widget, value)) node.dirty = true;
        node.widget = value;
    } else if (comptime isList(View)) {
        if (origin == .function) node.widget.adopt(value);
        syncList(node, state, owners);
    } else if (comptime !isContainer(View)) {
        if (origin == .function) node.widget = value;
    } else if (comptime isAnimated(View)) {
        const Child = @TypeOf(value.children[0]);
        const spec = value.config.spec;
        const tween = &node.widget.tween;
        node.widget.spec = spec;
        tween.retarget(spec, resolve(value.children[0], state, owners), state.now);
        const shown: Origin = if (comptime isShow(Child)) .function else origin;
        apply(&node.children[0], tween.at(spec, state.now), state, owners, shown);
        if (tween.running) state.animating = true;
    } else {
        if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
            const active = invoke(@TypeOf(value.config).cond, owners, state, {});
            if (active != node.widget.active) state.stale = true;
            node.widget.active = active;
        } else if (origin == .function) {
            node.widget = value.config;
        }
        inline for (0..value.children.len) |i| apply(&node.children[i], value.children[i], state, owners, origin);
    }
}

// Visits every node, builds the components marked dirty again and moves
// the running animations forward. The strings of the last build are freed
// only after everything inside was built too, because the new values are
// compared with the old ones.
pub fn rebuild(node: anytype, state: *State, owners: anytype) void {
    const Widget = @TypeOf(node.widget);
    if (comptime isComponent(Widget)) {
        const inner = owners ++ .{node};
        if (node.dirty) {
            @branchHint(.unlikely);
            node.dirty = false;
            state.built = true;
            const last = node.arena.promote(state.gpa);
            node.arena = .init;
            apply(&node.children[0], Widget.view, state, inner, .view);
            rebuild(&node.children[0], state, inner);
            return last.deinit();
        }
        return rebuild(&node.children[0], state, inner);
    }
    if (comptime @TypeOf(node.children) == void) return;
    if (comptime @hasField(Widget, "tween")) {
        const tween = &node.widget.tween;
        if (tween.running) {
            state.built = true;
            apply(&node.children[0], tween.at(node.widget.spec, state.now), state, owners, .function);
            tween.finish(node.widget.spec, state.now);
            if (tween.running) state.animating = true;
        }
    }
    _ = each(node, .all, rebuild, .{ state, owners });
}

pub fn markAll(node: anytype) void {
    if (comptime isComponent(@TypeOf(node.widget))) node.dirty = true;
    _ = each(node, .all, markAll, .{});
}

// Marks the components that entered or left the path.
pub fn markChanged(node: anytype, before: []const node_zig.NodeId, after: []const node_zig.NodeId) void {
    const was = contains(before, node.id);
    const is = contains(after, node.id);
    if (!was and !is) return;
    if (comptime isComponent(@TypeOf(node.widget))) {
        if (was != is) node.dirty = true;
    }
    _ = each(node, .all, markChanged, .{ before, after });
}

// A component received as a mutable pointer may have been changed, so it and
// everything inside it are built again. The same goes for the component
// holding a field received as a mutable pointer.
pub fn markTargets(comptime f: anytype, owners: anytype) void {
    inline for (@typeInfo(@TypeOf(f)).@"fn".params) |param| {
        const P = param.type.?;
        if (comptime @typeInfo(P) == .pointer and !@typeInfo(P).pointer.is_const) {
            markAll(owners[comptime call.source(@TypeOf(owners), P).owner]);
        }
    }
}

fn syncList(node: anytype, state: *State, owners: anytype) void {
    const List = @TypeOf(node.widget);
    const elements = invoke(List.source, owners, state, {});
    state.stale = true;
    if (comptime List.keyed) return syncKeyed(node, elements, state, owners);

    const rows = &node.children;
    const kept = @min(elements.len, rows.items.len);
    for (rows.items[0..kept], 0..) |*row, i| apply(row, List.item(elements, i), state, owners, .function);
    for (rows.items[kept..]) |*row| destroy(row, state, owners);
    rows.shrinkRetainingCapacity(kept);
    rows.ensureTotalCapacity(state.gpa, elements.len) catch @panic("out of memory");
    for (kept..elements.len) |i| mount(rows.addOneAssumeCapacity(), List.item(elements, i), state, owners);
}

// Rows follow the `id` of their elements, so moving or removing an element
// keeps the focus and the state of the other rows. Rows mostly keep their
// order, so the search for a row starts after the last match. A row that was
// taken gives up its id.
fn syncKeyed(node: anytype, elements: anytype, state: *State, owners: anytype) void {
    const List = @TypeOf(node.widget);
    var old_rows = node.children;
    var old_keys = node.widget.keys;
    defer old_rows.deinit(state.gpa);
    defer old_keys.deinit(state.gpa);

    const rows = &node.children;
    const keys = &node.widget.keys;
    rows.* = .empty;
    keys.* = .empty;
    rows.ensureTotalCapacity(state.gpa, elements.len) catch @panic("out of memory");
    keys.ensureTotalCapacity(state.gpa, elements.len) catch @panic("out of memory");

    var next: usize = 0;
    for (elements, 0..) |element, i| {
        const row = rows.addOneAssumeCapacity();
        const found = for (0..old_rows.items.len) |n| {
            const j = (next + n) % old_rows.items.len;
            if (old_rows.items[j].id != 0 and List.sameKey(old_keys.items[j], element.id)) break j;
        } else null;

        if (found) |j| {
            row.* = old_rows.items[j];
            old_rows.items[j].id = 0;
            keys.appendAssumeCapacity(old_keys.items[j]);
            apply(row, List.item(elements, i), state, owners, .function);
            next = j + 1;
        } else {
            keys.appendAssumeCapacity(List.ownKey(state.gpa, element.id));
            mount(row, List.item(elements, i), state, owners);
        }
    }
    for (old_rows.items, old_keys.items) |*row, key| {
        if (row.id == 0) continue;
        destroy(row, state, owners);
        List.freeKey(state.gpa, key);
    }
}
