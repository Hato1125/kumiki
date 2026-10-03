const std = @import("std");

const Context = @import("cx.zig");
const node_zig = @import("node.zig");
const ReturnOf = node_zig.ReturnOf;
const State = node_zig.State;

// Where a value lives among the owners: in a field of an owner, or as the
// owner itself when `field` is null.
pub const Source = struct {
    owner: usize,
    field: ?[]const u8 = null,
};

fn Pointee(comptime P: type) type {
    return switch (@typeInfo(P)) {
        .pointer => |pointer| pointer.child,
        else => P,
    };
}

fn WidgetOf(comptime Owner: type) type {
    return @FieldType(@typeInfo(Owner).pointer.child, "widget");
}

// `Owners` holds pointers to the nodes of the enclosing components, the
// outermost first. The nearest component of type `P`, or pointed to by `P`,
// wins. When there is none, the value is the field of that type in the
// nearest component that has one, which lets components share a value, such
// as a theme, without knowing who holds it.
pub fn find(comptime Owners: type, comptime P: type) ?Source {
    const T = Pointee(P);
    const owners = @typeInfo(Owners).@"struct".fields;
    var i = owners.len;
    while (i > 0) {
        i -= 1;
        if (WidgetOf(owners[i].type) == T) return .{ .owner = i };
    }

    i = owners.len;
    while (i > 0) {
        i -= 1;
        const Widget = WidgetOf(owners[i].type);
        var found: ?[]const u8 = null;
        for (@typeInfo(Widget).@"struct".fields) |field| {
            if (field.type != T) continue;
            if (found != null) {
                @compileError(@typeName(Widget) ++ " has more than one field of type " ++ @typeName(T));
            }
            found = field.name;
        }
        if (found) |name| return .{ .owner = i, .field = name };
    }
    return null;
}

pub fn source(comptime Owners: type, comptime P: type) Source {
    return find(Owners, P) orelse
        @compileError("no enclosing component is or holds a " ++ @typeName(Pointee(P)) ++ " for this parameter");
}

// Whether a parameter of type `P` is filled in from the owners. One that is
// not stands for the event.
pub fn fills(comptime Owners: type, comptime P: type) bool {
    return P == Context or find(Owners, P) != null;
}

fn argument(comptime P: type, owners: anytype, state: *const State, event: anytype) P {
    if (P == Context) {
        if (owners.len == 0) @compileError("ui.Context is only available inside a component");
        const node = owners[owners.len - 1];
        return .{ .id = node.id, .state = state, .arena = &node.arena, .gpa = state.gpa };
    }
    if (P == @TypeOf(event)) return event;

    const from = comptime source(@TypeOf(owners), P);
    const widget = &owners[from.owner].widget;
    const value = if (comptime from.field) |name| &@field(widget, name) else widget;
    return if (comptime @typeInfo(P) == .pointer) value else value.*;
}

// Calls `f`, filling each parameter by its type: a component type, or a
// pointer to one, receives the nearest enclosing component of that type, any
// other type receives the field of that type in the nearest component that
// has one, ui.Context receives the Context of the nearest component and the
// type of `event` receives the event being handled.
pub fn invoke(comptime f: anytype, owners: anytype, state: *const State, event: anytype) ReturnOf(f) {
    var args: std.meta.ArgsTuple(@TypeOf(f)) = undefined;
    inline for (@typeInfo(@TypeOf(f)).@"fn".params, 0..) |param, i| {
        const P = param.type orelse @compileError("parameters must have concrete types");
        args[i] = argument(P, owners, state, event);
    }
    return @call(.auto, f, args);
}
