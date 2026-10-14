const anim = @import("anime.zig");
const gfx = @import("gfx");
const image_zig = @import("image.zig");
const text_zig = @import("text.zig");
const types = @import("types.zig");
const input = @import("input.zig");
const mod = @import("mod.zig");
const pass = @import("layout.zig");
const window = @import("window.zig");

test {
    @import("std").testing.refAllDecls(@This());
}

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
pub const startup = text_zig.startup;
pub const addFont = text_zig.addFont;
pub const textSystem = text_zig.system;
pub const setTextScale = text_zig.setScale;
pub const releaseImages = image_zig.release;

/// Lets go of the fonts and the images. The canvas that drew them has to
/// be gone by then.
pub fn shutdown() void {
    image_zig.shutdown();
    text_zig.shutdown();
}

pub const Color = types.Color;
pub const Point = types.Point;
pub const Extent = types.Extent;
pub const Size = types.Size;
pub const Bounds = types.Bounds;
pub const Range = types.Range;
pub const Constraint = types.Constraint;
pub const inf = types.inf;
pub const Alignment = types.Alignment;
pub const Placement = @import("popup.zig").Placement;
pub const Transition = @import("popup.zig").Transition;
pub const Animation = anim.Animation;
pub const Context = @import("cx.zig");
pub const Callback = @import("call.zig").Callback;

pub const measure = pass.measure;
pub const layout = pass.layout;
pub const offsetOf = @import("node.zig").offsetOf;
pub const Painter = @import("paint.zig").Painter;
pub const Canvas = gfx.Canvas;
pub const Layer = gfx.Layer;
pub const Corners = gfx.Corners;
pub const Insets = mod.Insets;

pub const Text = mod.Container(void, @import("view/text.zig").Text);
pub const Rect = mod.Container(void, @import("view/rect.zig").Rect);
pub const Picture = mod.Container(void, @import("view/image.zig").Picture);
pub const Image = image_zig.Image;

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
pub const each = @import("view/each.zig").each;
pub const Each = @import("view/each.zig").Each;
