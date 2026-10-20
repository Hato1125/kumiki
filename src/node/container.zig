const model = @import("model.zig");
const value_mod = @import("value.zig");
const call = @import("../call.zig");
const invoke = call.invoke;

pub fn ContainerNode(comptime View: type, comptime Children: type) type {
    return struct {
        id: model.NodeId,
        offset: if (model.keepsOffset(View)) @import("../types.zig").Point else void,
        size: @import("../types.zig").Extent,
        widget: @FieldType(View, "config"),
        children: Children,

        const Self = @This();

        pub fn mount(
            node: *Self,
            value: anytype,
            state: *model.State,
            components: anytype,
        ) void {
            const Value = @TypeOf(value);
            if (comptime model.isShow(Value)) {
                return node.mount(value_mod.resolve(value, state, components), state, components);
            }
            if (comptime model.isBare(Value)) {
                return node.mount(value_mod.normalize(value, state, components), state, components);
            }

            state.next_id += 1;
            node.id = state.next_id;
            if (comptime @TypeOf(node.offset) != void) node.offset = .{};
            node.size = .{};
            node.widget = value.config;
            if (comptime model.handles(@TypeOf(value.config), .input)) {
                state.inputs += 1;
            }
            if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
                node.widget.active = invoke(@TypeOf(value.config).cond, components, state, {});
            }
            if (comptime @TypeOf(value.children) == void) return;
            inline for (0..value.children.len) |i| {
                node.children[i].mount(value.children[i], state, components);
            }
        }

        pub fn apply(
            node: *Self,
            value: anytype,
            state: *model.State,
            components: anytype,
            comptime origin: model.Source,
        ) void {
            const Value = @TypeOf(value);
            if (comptime model.isShow(Value)) {
                return node.apply(
                    value_mod.resolve(value, state, components),
                    state,
                    components,
                    .returned,
                );
            }
            if (comptime model.isBare(Value)) {
                return node.apply(
                    value_mod.normalize(value, state, components),
                    state,
                    components,
                    origin,
                );
            }

            if (comptime @hasDecl(@TypeOf(value.config), "cond")) {
                const active = invoke(@TypeOf(value.config).cond, components, state, {});
                if (active != node.widget.active) state.stale = true;
                if (origin == .returned) {
                    if (comptime @hasDecl(@TypeOf(value.config), "adopt")) {
                        node.widget.adopt(value.config);
                    } else {
                        node.widget = value.config;
                    }
                }
                node.widget.active = active;
            } else if (origin == .returned) {
                node.widget = value.config;
            }
            if (comptime @TypeOf(value.children) == void) return;
            inline for (0..value.children.len) |i| {
                node.children[i].apply(value.children[i], state, components, origin);
            }
        }

        pub fn rebuild(node: *Self, state: *model.State, components: anytype) void {
            if (comptime @TypeOf(node.children) == void) return;
            _ = model.each(node, .all, model.rebuildChild, .{ state, components });
        }

        pub fn destroy(node: *Self, state: *model.State, components: anytype) void {
            _ = model.each(node, .all, model.destroyChild, .{ state, components });
            if (comptime model.handles(@TypeOf(node.widget), .input)) {
                state.inputs -= 1;
            }
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
    };
}
