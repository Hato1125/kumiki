const std = @import("std");

const model = @import("model.zig");
const value_mod = @import("value.zig");
const call = @import("../call.zig");
const invoke = call.invoke;

pub fn ListNode(comptime View: type, comptime Row: type) type {
    return struct {
        id: model.NodeId,
        offset: if (model.keepsOffset(View)) @import("../types.zig").Point else void,
        size: @import("../types.zig").Extent,
        widget: @FieldType(View, "config"),
        children: std.ArrayList(Row),

        const Self = @This();

        pub fn mount(
            node: *Self,
            value: anytype,
            state: *model.State,
            owners: anytype,
        ) void {
            const Value = @TypeOf(value);
            if (comptime model.isShow(Value)) {
                return node.mount(value_mod.resolve(value, state, owners), state, owners);
            }

            state.next_id += 1;
            node.id = state.next_id;
            if (comptime @TypeOf(node.offset) != void) node.offset = .{};
            node.size = .{};
            node.widget = value.config;
            node.children = .empty;
            node.syncList(state, owners);
        }

        pub fn apply(
            node: *Self,
            value: anytype,
            state: *model.State,
            owners: anytype,
            comptime origin: model.Origin,
        ) void {
            const Value = @TypeOf(value);
            if (comptime model.isShow(Value)) {
                return node.apply(
                    value_mod.resolve(value, state, owners),
                    state,
                    owners,
                    .function,
                );
            }
            if (origin == .function) node.widget.adopt(value.config);
            node.syncList(state, owners);
        }

        pub fn rebuild(node: *Self, state: *model.State, owners: anytype) void {
            _ = model.each(node, .all, model.rebuildChild, .{ state, owners });
        }

        pub fn destroy(node: *Self, state: *model.State, owners: anytype) void {
            _ = model.each(node, .all, model.destroyChild, .{ state, owners });
            if (comptime model.handles(@TypeOf(node.widget), .input)) {
                state.inputs -= 1;
            }
            node.children.deinit(state.gpa);
            node.widget.deinitKeys(state.gpa);
        }

        pub fn markAll(node: *Self) void {
            _ = model.each(node, .all, model.markAllChild, .{});
        }

        pub fn markChanged(
            node: *Self,
            before: []const model.NodeId,
            after: []const model.NodeId,
        ) void {
            if (!model.contains(before, node.id) and !model.contains(after, node.id)) {
                return;
            }
            _ = model.each(node, .all, model.markChangedChild, .{ before, after });
        }

        fn syncList(node: *Self, state: *model.State, owners: anytype) void {
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
            state: *model.State,
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
