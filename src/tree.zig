const call = @import("call.zig");
const node_zig = @import("node.zig");
const Source = node_zig.Source;
const State = node_zig.State;

pub fn mount(node: anytype, value: anytype, state: *State, components: anytype) void {
    node.mount(value, state, components);
}

pub fn apply(
    node: anytype,
    value: anytype,
    state: *State,
    components: anytype,
    comptime origin: Source,
) void {
    node.apply(value, state, components, origin);
}

pub fn destroy(node: anytype, state: *State, components: anytype) void {
    node.destroy(state, components);
}

pub fn rebuild(node: anytype, state: *State, components: anytype) void {
    node.rebuild(state, components);
}

pub fn markAll(node: anytype) void {
    node.markAll();
}

/// Marks the components that entered or left the path.
pub fn markChanged(
    node: anytype,
    before: []const node_zig.NodeId,
    after: []const node_zig.NodeId,
) void {
    node.markChanged(before, after);
}

/// A component received as a mutable pointer may have been changed, so it and
/// everything inside it are built again. The same goes for the component
/// holding a field received as a mutable pointer. A pointer that no owner
/// fills in is the event, such as the result of a background function.
pub fn markTargets(comptime f: anytype, components: anytype) void {
    inline for (@typeInfo(@TypeOf(f)).@"fn".params) |param| {
        const P = param.type.?;
        if (comptime @typeInfo(P) == .pointer and !@typeInfo(P).pointer.is_const) {
            if (comptime call.find(@TypeOf(components), P)) |from| {
                components[from.owner].markAll();
            }
        }
    }
}
