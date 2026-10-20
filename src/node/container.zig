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
const isBare = model.isBare;
const isShow = model.isShow;
const keepsOffset = model.keepsOffset;
const destroyChild = model.destroyChild;
const rebuildChild = model.rebuildChild;
const markAllChild = model.markAllChild;
const markChangedChild = model.markChangedChild;
const invoke = call.invoke;
const normalize = value_mod.normalize;
const resolve = value_mod.resolve;

pub fn ContainerNode(comptime View: type, comptime Children: type) type {
    return struct {
        id: NodeId,
        offset: if (keepsOffset(View)) Point else void,
        size: Extent,
        widget: @FieldType(View, "config"),
        children: Children,

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
            if (comptime isBare(Value))
                return node.mount(
                    normalize(value, state, components),
                    state,
                    components,
                );

            begin(node, state);

            node.widget = value.config;
            if (comptime handles(@TypeOf(value.config), .input))
                state.inputs += 1;
            if (comptime @hasDecl(@TypeOf(value.config), "cond"))
                node.widget.active = invoke(@TypeOf(value.config).cond, components, state, {});
            if (comptime @TypeOf(value.children) == void) return;

            inline for (0..value.children.len) |i|
                node.children[i].mount(value.children[i], state, components);
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
            if (comptime isBare(Value))
                return node.apply(
                    normalize(value, state, components),
                    state,
                    components,
                    origin,
                );

            if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
                const active = invoke(@TypeOf(value.config).cond, components, state, {});
                if (active != node.widget.active) state.stale = true;
                if (origin == .returned) {
                    if (comptime @hasDecl(@TypeOf(value.config), "adopt"))
                        node.widget.adopt(value.config)
                    else
                        node.widget = value.config;
                }
                node.widget.active = active;
            } else if (origin == .returned) {
                node.widget = value.config;
            }
            if (comptime @TypeOf(value.children) == void) return;

            inline for (0..value.children.len) |i|
                node.children[i].apply(
                    value.children[i],
                    state,
                    components,
                    origin,
                );
        }

        pub fn rebuild(node: *Self, state: *State, components: anytype) void {
            if (comptime @TypeOf(node.children) == void) return;
            _ = each(node, .all, rebuildChild, .{ state, components });
        }

        pub fn destroy(node: *Self, state: *State, components: anytype) void {
            _ = each(node, .all, destroyChild, .{ state, components });
            if (comptime handles(@TypeOf(node.widget), .input)) state.inputs -= 1;
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
    };
}
