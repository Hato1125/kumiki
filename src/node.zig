const model = @import("node/model.zig");
const animated = @import("node/animated.zig");
const component = @import("node/component.zig");
const container = @import("node/container.zig");
const list = @import("node/list.zig");

pub const NodeId = model.NodeId;
pub const State = model.State;
pub const Host = model.Host;
pub const Source = model.Source;
pub const Order = model.Order;
pub const HandlerKind = model.HandlerKind;

pub const Path = model.Path;
pub const depthOf = model.depthOf;
pub const contains = model.contains;
pub const offsetOf = model.offsetOf;
pub const each = model.each;

pub const isComponent = model.isComponent;
pub const isContainer = model.isContainer;
pub const isAnimated = model.isAnimated;
pub const isShow = model.isShow;
pub const isList = model.isList;
pub const isBare = model.isBare;
pub const isFocusable = model.isFocusable;
pub const isPopup = model.isPopup;

pub const Normalized = model.Normalized;
pub const Resolved = model.Resolved;
pub const ReturnOf = model.ReturnOf;
pub const provides = model.provides;
pub const Provided = model.Provided;
pub const has = model.has;
pub const holds = model.holds;
pub const handles = model.handles;

fn ViewChildren(comptime View: type) type {
    return @FieldType(View, "children");
}

fn FirstChild(comptime View: type) type {
    return @FieldType(ViewChildren(View), "0");
}

fn NodeChildren(comptime View: type) type {
    const Inside = ViewChildren(View);
    if (Inside == void) return void;

    const field_types = @typeInfo(Inside).@"struct".field_types;
    var element_types: [field_types.len]type = undefined;
    for (field_types, 0..) |Field, i| {
        element_types[i] = NodeOf(Field);
    }
    return @Tuple(&element_types);
}

fn RowOf(comptime View: type) type {
    const Config = @FieldType(View, "config");
    return Config.Row;
}

pub fn NodeOf(comptime View: type) type {
    @setEvalBranchQuota(10000);
    const V = Normalized(Resolved(View));

    if (comptime isComponent(V)) {
        return component.ComponentNode(V, NodeOf(@TypeOf(V.view)));
    }
    if (comptime isList(V)) {
        return list.ListNode(V, NodeOf(RowOf(V)));
    }
    if (comptime isAnimated(V)) {
        return animated.AnimatedNode(V, NodeOf(FirstChild(V)));
    }
    return container.ContainerNode(V, NodeChildren(V));
}

pub fn Node(comptime View: type) type {
    return NodeOf(View);
}
