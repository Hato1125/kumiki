const std = @import("std");

const model = @import("model.zig");
const types = @import("../types.zig");
const value_mod = @import("value.zig");
const call = @import("../call.zig");

const NodeId = model.NodeId;
const State = model.State;
const Source = model.Source;
const Point = types.Point;
const Extent = types.Extent;
const begin = model.begin;
const contains = model.contains;
const each = model.each;
const handles = model.handles;
const isShow = model.isShow;
const keepsOffset = model.keepsOffset;
const destroyChild = model.destroyChild;
const rebuildChild = model.rebuildChild;
const markAllChild = model.markAllChild;
const markChangedChild = model.markChangedChild;
const invoke = call.invoke;
const resolve = value_mod.resolve;

pub fn ListNode(comptime View: type, comptime Row: type) type {
    return struct {
        id: NodeId,
        offset: if (keepsOffset(View)) Point else void,
        size: Extent,
        widget: @FieldType(View, "config"),
        children: std.ArrayList(Row),

        const Self = @This();

        pub fn mount(
            node: *Self,
            value: anytype,
            state: *State,
            components: anytype,
        ) void {
            const Value = @TypeOf(value);
            if (comptime isShow(Value))
                return node.mount(resolve(value, state, components), state, components);

            begin(node, state);

            node.widget = value.config;
            node.children = .empty;
            node.syncList(state, components);
        }

        pub fn apply(
            node: *Self,
            value: anytype,
            state: *State,
            components: anytype,
            comptime origin: Source,
        ) void {
            const Value = @TypeOf(value);
            if (comptime isShow(Value))
                return node.apply(
                    resolve(value, state, components),
                    state,
                    components,
                    .returned,
                );

            if (origin == .returned) node.widget.adopt(value.config);
            node.syncList(state, components);
        }

        pub fn rebuild(node: *Self, state: *State, components: anytype) void {
            _ = each(node, .all, rebuildChild, .{ state, components });
        }

        pub fn destroy(node: *Self, state: *State, components: anytype) void {
            _ = each(node, .all, destroyChild, .{ state, components });
            if (comptime handles(@TypeOf(node.widget), .input)) state.inputs -= 1;
            node.children.deinit(state.gpa);
            node.widget.deinitKeys(state.gpa);
        }

        pub fn markAll(node: *Self) void {
            _ = each(node, .all, markAllChild, .{});
        }

        pub fn markChanged(
            node: *Self,
            before: []const NodeId,
            after: []const NodeId,
        ) void {
            if (!contains(before, node.id) and !contains(after, node.id)) return;
            _ = each(node, .all, markChangedChild, .{ before, after });
        }

        fn syncList(node: *Self, state: *State, components: anytype) void {
            const List = @TypeOf(node.widget);
            const elements = invoke(List.source, components, state, {});
            state.stale = true;
            if (comptime List.keyed)
                return node.syncKeyed(elements, state, components);

            const rows = &node.children;
            const kept = @min(elements.len, rows.items.len);

            for (rows.items[0..kept], 0..) |*row, i|
                row.apply(List.item(elements, i), state, components, .returned);
            for (rows.items[kept..]) |*row|
                row.destroy(state, components);

            rows.shrinkRetainingCapacity(kept);
            rows.ensureTotalCapacity(state.gpa, elements.len) catch @panic("out of memory");
            for (kept..elements.len) |i|
                rows.addOneAssumeCapacity().mount(
                    List.item(elements, i),
                    state,
                    components,
                );
        }

        fn syncKeyed(
            node: *Self,
            elements: anytype,
            state: *State,
            components: anytype,
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
                    row.apply(List.item(elements, i), state, components, .returned);
                    next = j + 1;
                } else {
                    keys.appendAssumeCapacity(List.ownKey(state.gpa, element.id));
                    row.mount(List.item(elements, i), state, components);
                }
            }
            for (old_rows.items, old_keys.items) |*row, key| {
                if (row.id == 0) continue;
                row.destroy(state, components);
                List.freeKey(state.gpa, key);
            }
        }
    };
}
