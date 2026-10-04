const anim = @import("anime.zig");
const canvas = @import("canvas.zig");
const Flex = @import("flex.zig").Flex;
const types = @import("types.zig");
const input = @import("input.zig");
const leaf = @import("leaf.zig");
const List = @import("list.zig").List;
const mod = @import("mod.zig");
const pass = @import("layout.zig");
const show_zig = @import("show.zig");
const Stack = @import("stack.zig").Stack;
const window = @import("window.zig");

pub const run = window.run;
pub const Window = window.Window;

pub const Scene = @import("scene.zig").Scene;
pub const Event = input.Event;
pub const MouseButtonEvent = input.MouseButtonEvent;
pub const Wheel = input.Wheel;
pub const KeyPress = input.KeyPress;
pub const TextInput = input.TextInput;
pub const keys = input.keys;
pub const startup = canvas.startup;
pub const shutdown = canvas.shutdown;
pub const addFont = canvas.addFont;

pub const Color = types.Color;
pub const Point = types.Point;
pub const Extent = types.Extent;
pub const Bounds = types.Bounds;
pub const Constraint = types.Constraint;
pub const inf = types.inf;
pub const Animation = anim.Animation;
pub const Context = @import("cx.zig");
pub const Callback = @import("call.zig").Callback;

pub const measure = pass.measure;
pub const layout = pass.layout;
pub const Painter = @import("paint.zig").Painter;
pub const Canvas = canvas.Canvas;
pub const Path = canvas.Path;
pub const Corners = canvas.Corners;

pub const Text = leaf.Text;
pub const Rect = leaf.Rect;
pub const Picture = leaf.Picture;
pub const Image = canvas.Image;

pub const show = show_zig.show;
pub const wrap = mod.wrap;

pub fn text(content: []const u8) Text {
    return .{ .content = content };
}

pub fn rect() Rect {
    return .{};
}

// Shows `source`, or nothing while it is null.
pub fn image(source: ?Image) Picture {
    return .{ .source = source };
}

pub fn spacer() leaf.Spacer {
    return .{};
}

pub fn row(children: anytype) mod.Container(Plain(@TypeOf(children)), Flex(.horizontal)) {
    return .{ .children = children, .config = .{} };
}

pub fn column(children: anytype) mod.Container(Plain(@TypeOf(children)), Flex(.vertical)) {
    return .{ .children = children, .config = .{} };
}

pub fn stack(children: anytype) mod.Container(Plain(@TypeOf(children)), Stack) {
    return .{ .children = children, .config = .{} };
}

// `source` returns a slice and `make` turns an element, or a pointer to it,
// into the view of its row. The parameters of `source` are filled in by type
// like those of `ui.show`.
pub fn list(comptime source: anytype, comptime make: anytype) List(source, make) {
    return .{};
}

fn When(comptime cond: anytype, comptime A: type, comptime B: type) type {
    return mod.Container(struct { A, B }, show_zig.When(cond));
}

// Shows `a` while `cond` returns true and `b` otherwise. The parameters of
// `cond` are filled in by type like those of `ui.show`.
pub fn when(comptime cond: anytype, a: anytype, b: anytype) When(cond, @TypeOf(a), @TypeOf(b)) {
    return .{ .children = .{ a, b }, .config = .{} };
}

pub fn Each(comptime n: usize, comptime F: anytype, comptime args: anytype) type {
    var element_types: [n]type = undefined;
    for (0..n) |i| element_types[i] = @call(.auto, F, args ++ .{i});
    return @Tuple(&element_types);
}

// The tuple `.{ F(args..., 0){}, ..., F(args..., n - 1){} }` of components.
pub fn each(comptime n: usize, comptime F: anytype, comptime args: anytype) Each(n, F, args) {
    var components: Each(n, F, args) = undefined;
    inline for (0..n) |i| components[i] = .{};
    return components;
}

// Tuple literals with compile-time values get comptime fields, which would
// make two literals of the same shape different types.
fn Plain(comptime Tuple: type) type {
    const fields = @typeInfo(Tuple).@"struct".fields;
    var element_types: [fields.len]type = undefined;
    for (fields, 0..) |field, i| element_types[i] = field.type;
    return @Tuple(&element_types);
}
