const std = @import("std");

const model = @import("model.zig");
const value_mod = @import("value.zig");
const call = @import("../call.zig");
const invoke = call.invoke;
const same = @import("../anime.zig").same;

pub fn ComponentNode(comptime View: type, comptime Child: type) type {
    return struct {
        id: model.NodeId,
        offset: if (model.keepsOffset(View)) @import("../types.zig").Point else void,
        size: @import("../types.zig").Extent,
        widget: View,
        children: struct { Child },
        dirty: bool,
        arena: std.heap.ArenaAllocator.State,
        given: if (model.provides(View)) model.Provided(View) else void,

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
            node.widget = value;
            node.dirty = false;
            node.arena = .init;

            const inner = owners ++ .{node};
            if (comptime @hasDecl(Value, "mount")) {
                invoke(Value.mount, inner, state, {});
            }
            if (comptime model.provides(Value)) {
                node.given = value_mod.provided(Value, inner, state);
            }
            node.children[0].mount(Value.view, state, inner);
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
            if (origin == .view) return;
            if (!std.meta.eql(node.widget, value)) node.dirty = true;
            node.widget = value;
        }

        pub fn rebuild(node: *Self, state: *model.State, owners: anytype) void {
            const inner = owners ++ .{node};
            if (!node.dirty) return node.children[0].rebuild(state, inner);

            const last = node.arena.promote(state.gpa);
            node.arena = .init;
            node.dirty = false;
            state.built = true;

            if (comptime model.provides(View)) {
                const next = value_mod.provided(View, inner, state);
                if (!same(model.Provided(View), next, node.given)) {
                    node.children[0].markAll();
                }
                node.given = next;
            }
            node.children[0].apply(View.view, state, inner, .view);
            node.children[0].rebuild(state, inner);
            last.deinit();
        }

        pub fn destroy(node: *Self, state: *model.State, owners: anytype) void {
            const inner = owners ++ .{node};
            _ = model.each(node, .all, model.destroyChild, .{ state, inner });
            if (comptime model.handles(View, .input)) state.inputs -= 1;
            if (comptime @hasDecl(View, "unmount")) {
                invoke(View.unmount, inner, state, {});
            }
            node.arena.promote(state.gpa).deinit();
        }

        pub fn markAll(node: *Self) void {
            node.dirty = true;
            node.children[0].markAll();
        }

        pub fn markChanged(
            node: *Self,
            before: []const model.NodeId,
            after: []const model.NodeId,
        ) void {
            const was = model.contains(before, node.id);
            const is = model.contains(after, node.id);
            if (!was and !is) return;
            if (was != is) node.dirty = true;
            node.children[0].markChanged(before, after);
        }
    };
}
