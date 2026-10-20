const std = @import("std");

const model = @import("model.zig");
const types = @import("../types.zig");
const value_mod = @import("value.zig");
const pass = @import("../layout.zig");

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
const offsetOf = model.offsetOf;
const destroyChild = model.destroyChild;
const rebuildChild = model.rebuildChild;
const markAllChild = model.markAllChild;
const markChangedChild = model.markChangedChild;
const resolve = value_mod.resolve;

pub fn AnimatedNode(comptime View: type, comptime Child: type) type {
    return struct {
        id: NodeId,
        offset: if (keepsOffset(View)) Point else void,
        size: Extent,
        widget: @FieldType(View, "config"),
        children: struct { Child },

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

            const target = resolve(value.children[0], state, components);
            node.widget = .{
                .spec = value.config.spec,
                .tween = .init(target),
            };

            node.children[0].mount(target, state, components);
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

            const ChildView = @TypeOf(value.children[0]);
            const spec = value.config.spec;
            const tween = &node.widget.tween;
            node.widget.spec = spec;
            tween.retarget(spec, resolve(value.children[0], state, components), state.now);

            const shown: Source = if (comptime isShow(ChildView)) .returned else origin;
            node.children[0].apply(tween.at(spec, state.now), state, components, shown);
            if (tween.running) state.animating = true;
        }

        pub fn rebuild(node: *Self, state: *State, components: anytype) void {
            const tween = &node.widget.tween;
            if (tween.running) {
                node.children[0].apply(
                    tween.at(node.widget.spec, state.now),
                    state,
                    components,
                    .returned,
                );

                tween.finish(node.widget.spec, state.now);
                if (tween.running) state.animating = true;
                if (std.meta.eql(pass.measure(node, node.widget.constraint), node.size)) {
                    pass.layout(node, offsetOf(node));
                } else {
                    state.built = true;
                }
            }
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
