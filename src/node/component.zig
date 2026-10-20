const std = @import("std");

const model = @import("model.zig");
const types = @import("../types.zig");
const value_mod = @import("value.zig");
const call = @import("../call.zig");
const same = @import("../anime.zig").same;

const NodeId = model.NodeId;
const State = model.State;
const Source = model.Source;
const Point = types.Point;
const Extent = types.Extent;
const Provided = model.Provided;
const begin = model.begin;
const contains = model.contains;
const handles = model.handles;
const isShow = model.isShow;
const keepsOffset = model.keepsOffset;
const provides = model.provides;
const destroyChild = model.destroyChild;
const invoke = call.invoke;
const provided = value_mod.provided;
const resolve = value_mod.resolve;

pub fn ComponentNode(comptime View: type, comptime Child: type) type {
    return struct {
        id: NodeId,
        offset: if (keepsOffset(View)) Point else void,
        size: Extent,
        widget: View,
        children: struct { Child },
        dirty: bool,
        arena: std.heap.ArenaAllocator.State,
        given: if (provides(View)) Provided(View) else void,

        const Self = @This();

        pub fn mount(
            node: *Self,
            value: anytype,
            state: *State,
            components: anytype,
        ) void {
            const Value = @TypeOf(value);
            if (comptime isShow(Value))
                return node.mount(
                    resolve(value, state, components),
                    state,
                    components,
                );

            begin(node, state);

            node.widget = value;
            node.dirty = false;
            node.arena = .init;

            const inner = components ++ .{node};

            if (comptime @hasDecl(Value, "mount"))
                invoke(Value.mount, inner, state, {});
            if (comptime provides(Value))
                node.given = provided(Value, inner, state);

            node.children[0].mount(Value.view, state, inner);
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

            if (origin == .written) return;
            if (!std.meta.eql(node.widget, value)) node.dirty = true;
            node.widget = value;
        }

        pub fn rebuild(node: *Self, state: *State, components: anytype) void {
            const inner = components ++ .{node};
            if (!node.dirty) return node.children[0].rebuild(state, inner);

            const last = node.arena.promote(state.gpa);
            node.arena = .init;
            node.dirty = false;
            state.built = true;

            if (comptime provides(View)) {
                const next = provided(View, inner, state);
                if (!same(Provided(View), next, node.given))
                    node.children[0].markAll();
                node.given = next;
            }

            node.children[0].apply(View.view, state, inner, .written);
            node.children[0].rebuild(state, inner);
            last.deinit();
        }

        pub fn destroy(node: *Self, state: *State, components: anytype) void {
            const inner = components ++ .{node};
            _ = model.each(node, .all, destroyChild, .{ state, inner });
            if (comptime handles(View, .input)) state.inputs -= 1;
            if (comptime @hasDecl(View, "unmount"))
                invoke(View.unmount, inner, state, {});
            node.arena.promote(state.gpa).deinit();
        }

        pub fn markAll(node: *Self) void {
            node.dirty = true;
            node.children[0].markAll();
        }

        pub fn markChanged(
            node: *Self,
            before: []const NodeId,
            after: []const NodeId,
        ) void {
            const was = contains(before, node.id);
            const is = contains(after, node.id);
            if (!was and !is) return;
            if (was != is) node.dirty = true;
            node.children[0].markChanged(before, after);
        }
    };
}
