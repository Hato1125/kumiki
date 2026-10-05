const anim = @import("anime.zig");
const canvas = @import("canvas.zig");
const types = @import("types.zig");
const input = @import("input.zig");
const mod = @import("mod.zig");
const pass = @import("layout.zig");
const window = @import("window.zig");

pub const run = window.run;
pub const Window = window.Window;

pub const Scene = @import("scene.zig").Scene;
pub const Event = input.Event;
pub const MouseButton = input.MouseButton;
pub const MouseButtonEvent = input.MouseButtonEvent;
pub const Pointer = input.Pointer;
pub const Wheel = input.Wheel;
pub const Hover = input.Hover;
pub const Drop = input.Drop;
pub const KeyPress = input.KeyPress;
pub const Chord = input.Chord;
pub const TextInput = input.TextInput;
pub const keys = input.keys;
pub const startup = canvas.startup;
pub const shutdown = canvas.shutdown;
pub const addFont = canvas.addFont;

pub const Color = types.Color;
pub const Point = types.Point;
pub const Extent = types.Extent;
pub const Bounds = types.Bounds;
pub const Range = types.Range;
pub const Constraint = types.Constraint;
pub const inf = types.inf;
pub const Alignment = @import("view/stack.zig").Alignment;
pub const Placement = @import("popup.zig").Placement;
pub const Transition = @import("popup.zig").Transition;
pub const Animation = anim.Animation;
pub const Context = @import("cx.zig");
pub const Callback = @import("call.zig").Callback;

pub const measure = pass.measure;
pub const layout = pass.layout;
pub const offsetOf = @import("node.zig").offsetOf;
pub const Painter = @import("paint.zig").Painter;
pub const Canvas = canvas.Canvas;
pub const Path = canvas.Path;
pub const Corners = canvas.Corners;

pub const Text = @import("view/text.zig").Text;
pub const Rect = @import("view/rect.zig").Rect;
pub const Picture = @import("view/image.zig").Picture;
pub const Image = canvas.Image;

pub const show = @import("view/show.zig").show;
pub const wrap = mod.wrap;

pub const text = @import("view/text.zig").text;
pub const rect = @import("view/rect.zig").rect;
pub const image = @import("view/image.zig").image;
pub const spacer = @import("view/spacer.zig").spacer;
pub const row = @import("view/row.zig").row;
pub const column = @import("view/column.zig").column;
pub const stack = @import("view/stack.zig").stack;
pub const list = @import("view/list.zig").list;
pub const when = @import("view/when.zig").when;

pub fn Each(
    comptime n: usize,
    comptime F: anytype,
    comptime args: anytype,
) type {
    var element_types: [n]type = undefined;
    for (0..n) |i| element_types[i] = @call(.auto, F, args ++ .{i});
    return @Tuple(&element_types);
}

/// The tuple `.{ F(args..., 0){}, ..., F(args..., n - 1){} }` of components.
pub fn each(
    comptime n: usize,
    comptime F: anytype,
    comptime args: anytype,
) Each(n, F, args) {
    var components: Each(n, F, args) = undefined;
    inline for (0..n) |i| components[i] = .{};
    return components;
}
