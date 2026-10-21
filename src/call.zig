const std = @import("std");

const Context = @import("cx.zig");
const Constraint = @import("types.zig").Constraint;
const node_zig = @import("node.zig");
const ReturnOf = node_zig.ReturnOf;
const State = node_zig.State;
const tree = @import("tree.zig");

/// Where a value lives among the owners: in a field of an owner, as what the
/// owner provides, or as the owner itself.
pub const Source = struct {
    owner: usize,
    field: ?[]const u8 = null,
    given: bool = false,
};

pub fn Pointee(comptime P: type) type {
    return switch (@typeInfo(P)) {
        .pointer => |pointer| pointer.child,
        else => P,
    };
}

fn WidgetOf(comptime Owner: type) type {
    return @FieldType(@typeInfo(Owner).pointer.child, "widget");
}

/// `Owners` holds pointers to the nodes of the enclosing components, the
/// outermost first. The nearest component of type `P`, or pointed to by `P`,
/// wins. When there is none, the value comes from the nearest component that
/// has a field of that type or provides that type, which lets components
/// share a value, such as a theme, without knowing who holds it.
pub fn find(comptime Owners: type, comptime P: type) ?Source {
    const T = Pointee(P);
    const owners = @typeInfo(Owners).@"struct".field_types;
    var i = owners.len;
    while (i > 0) {
        i -= 1;
        if (WidgetOf(owners[i]) == T) return .{ .owner = i };
    }

    i = owners.len;
    while (i > 0) {
        i -= 1;
        const Widget = WidgetOf(owners[i]);
        const info = @typeInfo(Widget).@"struct";
        var found: ?[]const u8 = null;
        for (info.field_names, info.field_types) |field_name, Field| {
            if (Field != T) continue;
            if (found != null) {
                @compileError(@typeName(Widget) ++
                    " has more than one field of type " ++ @typeName(T));
            }
            found = field_name;
        }
        const gives = node_zig.provides(Widget) and node_zig.Provided(Widget) == T;
        if (gives and found != null) {
            @compileError(@typeName(Widget) ++
                " both holds and provides a " ++ @typeName(T));
        }
        if (found) |name| return .{ .owner = i, .field = name };
        if (gives) return .{ .owner = i, .given = true };
    }
    return null;
}

pub fn source(comptime Owners: type, comptime P: type) Source {
    return find(Owners, P) orelse
        @compileError("no enclosing component is, holds or provides a " ++
            @typeName(Pointee(P)) ++ " for this parameter");
}

/// Whether a parameter of type `P` is filled in from the owners. One that is
/// not stands for the event.
pub fn fills(comptime Owners: type, comptime P: type) bool {
    return P == Context or P == Constraint or isCallback(P) or find(Owners, P) != null;
}

/// A function that a component is given when it is written in a view, for the
/// component to call later: `f` is a function, or `{}` for none. A function
/// of the component receives it by declaring a parameter of this type and
/// runs it with `call`. The parameters of `f` are filled in by type as if it
/// were given to a modifier at the place of the component, and the components
/// it receives as mutable pointers are built again.
pub fn Callback(comptime f: anytype) type {
    return struct {
        owners: *const anyopaque = undefined,
        state: *const State = undefined,
        run: *const fn (*const anyopaque, *const State) void = undefined,

        pub const callee = f;

        pub fn call(given: @This()) void {
            if (@TypeOf(f) != void) given.run(given.owners, given.state);
        }
    };
}

fn isCallback(comptime P: type) bool {
    return @typeInfo(P) == .@"struct" and @hasDecl(P, "callee");
}

// The owners of the place where the innermost of `Owners` is written.
fn Outer(comptime Owners: type) type {
    const field_types = @typeInfo(Owners).@"struct".field_types;
    return @Tuple(field_types[0 .. field_types.len - 1]);
}

fn bind(comptime P: type, owners: anytype, state: *const State) P {
    if (@TypeOf(P.callee) == void) return .{};
    const Owners = @TypeOf(owners.*);
    return .{
        .owners = owners,
        .state = state,
        .run = struct {
            fn run(erased: *const anyopaque, shared: *const State) void {
                const inner: *const Owners = @ptrCast(@alignCast(erased));
                var outer: Outer(Owners) = undefined;
                inline for (0..outer.len) |i| outer[i] = inner.*[i];
                invoke(P.callee, outer, shared, {});
                tree.markTargets(P.callee, outer);
            }
        }.run,
    };
}

fn argument(
    comptime P: type,
    owners: anytype,
    state: *const State,
    event: anytype,
) P {
    if (P == Context) {
        if (owners.len == 0) {
            @compileError("ui.Context is only available inside a component");
        }
        const node = owners.*[owners.len - 1];
        return .{
            .id = node.id,
            .state = state,
            .arena = &node.arena,
            .gpa = state.gpa,
            .size = node.size,
        };
    }
    if (P == Constraint) {
        if (owners.len == 0) {
            @compileError("ui.Constraint is only available inside a component");
        }
        const node = owners.*[owners.len - 1];
        node.read = node.constraint;
        return node.constraint;
    }
    if (P == @TypeOf(event)) return event;
    if (comptime isCallback(P)) return bind(P, owners, state);

    const from = comptime source(@TypeOf(owners.*), P);
    const pointer = comptime @typeInfo(P) == .pointer;
    if (comptime from.given) {
        if (comptime pointer and !@typeInfo(P).pointer.attrs.@"const") {
            @compileError("a " ++ @typeName(Pointee(P)) ++ " is provided, " ++
                "so it is received by value or as a const pointer");
        }
        const given = &owners.*[from.owner].given;
        return if (pointer) given else given.*;
    }
    const widget = &owners.*[from.owner].widget;
    const value = if (comptime from.field) |name| &@field(widget, name) else widget;
    return if (pointer) value else value.*;
}

/// Calls `f`, filling each parameter by its type: a component type, or a
/// pointer to one, receives the nearest enclosing component of that type, any
/// other type receives what the nearest component that holds or provides one
/// has of it, ui.Context receives the Context of the nearest component,
/// ui.Constraint what that component was last measured with, and the type of
/// `event` receives the event being handled. A component whose functions
/// receive ui.Constraint is built again when it is measured with another.
pub fn invoke(
    comptime f: anytype,
    owners: anytype,
    state: *const State,
    event: anytype,
) ReturnOf(f) {
    var args: std.meta.ArgsTuple(@TypeOf(f)) = undefined;
    inline for (@typeInfo(@TypeOf(f)).@"fn".param_types, 0..) |param_type, i| {
        const P = param_type orelse
            @compileError("parameters must have concrete types");
        args[i] = argument(P, &owners, state, event);
    }
    return @call(.auto, f, args);
}
