const std = @import("std");

const model = @import("model.zig");
const value_mod = @import("value.zig");
const pass = @import("../layout.zig");

pub fn AnimatedNode(comptime View: type, comptime Child: type) type {
    return struct {
        id: model.NodeId,
        offset: if (model.keepsOffset(View)) @import("../types.zig").Point else void,
        size: @import("../types.zig").Extent,
        widget: @FieldType(View, "config"),
        children: struct { Child },

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
            const target = value_mod.resolve(value.children[0], state, owners);
            node.widget = .{ .spec = value.config.spec, .tween = .init(target) };
            node.children[0].mount(target, state, owners);
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

            const ChildView = @TypeOf(value.children[0]);
            const spec = value.config.spec;
            const tween = &node.widget.tween;
            node.widget.spec = spec;
            tween.retarget(spec, value_mod.resolve(value.children[0], state, owners), state.now);
            const shown: model.Origin = if (comptime model.isShow(ChildView)) .function else origin;
            node.children[0].apply(tween.at(spec, state.now), state, owners, shown);
            if (tween.running) state.animating = true;
        }

        pub fn rebuild(node: *Self, state: *model.State, owners: anytype) void {
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
                    pass.layout(node, model.offsetOf(node));
                } else {
                    state.built = true;
                }
            }
            _ = model.each(node, .all, model.rebuildChild, .{ state, owners });
        }

        pub fn destroy(node: *Self, state: *model.State, owners: anytype) void {
            _ = model.each(node, .all, model.destroyChild, .{ state, owners });
            if (comptime model.handles(@TypeOf(node.widget), .input)) state.inputs -= 1;
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
