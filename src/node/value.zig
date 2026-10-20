const model = @import("model.zig");
const leaf = @import("../mod.zig").leaf;
const call = @import("../call.zig");
const invoke = call.invoke;

pub fn provided(
    comptime View: type,
    inner: anytype,
    state: *model.State,
) model.Provided(View) {
    comptime for (@typeInfo(@TypeOf(View.provide)).@"fn".params) |param| {
        if (call.Pointee(param.type.?) == model.Provided(View)) {
            @compileError("the provide of " ++ @typeName(View) ++
                " receives the type it provides");
        }
    };
    return invoke(View.provide, inner, state, {});
}

pub fn resolve(
    value: anytype,
    state: *model.State,
    owners: anytype,
) model.Resolved(@TypeOf(value)) {
    const Value = @TypeOf(value);
    if (comptime !model.isShow(Value)) return value;
    return invoke(@FieldType(Value, "config").func, owners, state, {});
}

pub fn normalize(
    value: anytype,
    state: *model.State,
    owners: anytype,
) model.Normalized(model.Resolved(@TypeOf(value))) {
    const Value = @TypeOf(value);
    if (comptime model.isShow(Value)) {
        return normalize(resolve(value, state, owners), state, owners);
    }
    if (comptime model.isBare(Value)) {
        return leaf(value);
    }
    return value;
}
