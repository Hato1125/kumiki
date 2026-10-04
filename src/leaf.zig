const std = @import("std");

const canvas = @import("canvas.zig");
const types = @import("types.zig");
const Color = types.Color;
const Constraint = types.Constraint;
const Extent = types.Extent;
const mod = @import("mod.zig");
const Painter = @import("paint.zig").Painter;

pub const Text = struct {
    content: []const u8,
    font_size: f32 = 16,
    text_color: Color = .black,
    font_name: ?[:0]const u8 = null,
    line_height: ?f32 = null,
    letter_spacing: f32 = 0,

    pub fn size(text: Text, px: f32) Text {
        return mod.set(text, "font_size", px);
    }

    pub fn color(text: Text, c: Color) Text {
        return mod.set(text, "text_color", c);
    }

    // `name` is the file name of a loaded font without its extension.
    pub fn font(text: Text, name: [:0]const u8) Text {
        return mod.set(text, "font_name", name);
    }

    pub fn lineHeight(text: Text, px: f32) Text {
        return mod.set(text, "line_height", px);
    }

    pub fn tracking(text: Text, px: f32) Text {
        return mod.set(text, "letter_spacing", px);
    }

    fn style(text: Text) canvas.TextStyle {
        return .{
            .size = text.font_size,
            .font = text.font_name,
            .line_height = text.line_height,
            .tracking = text.letter_spacing,
        };
    }

    // The width up to where the next character would go. It counts the
    // spaces at the end, which `measure` leaves out, so a caret goes there.
    pub fn advance(text: Text) f32 {
        return canvas.textAdvance(text.content, text.style());
    }

    // The position in the text whose advance is nearest to `x`: a byte
    // offset between two code points, for a caret to go where a pointer is.
    pub fn indexAt(text: Text, x: f32) usize {
        return canvas.textIndexAt(text.content, text.style(), x);
    }

    // Wraps when the text is wider than the space offered.
    pub fn measure(text: Text, c: Constraint) Extent {
        const natural = canvas.measureText(text.content, text.style(), 0);
        if (std.math.isInf(c.max.width) or natural.width <= c.max.width) return c.constrain(natural);
        return c.constrain(canvas.measureText(text.content, text.style(), c.max.width));
    }

    pub fn paint(text: Text, p: Painter) void {
        const natural = canvas.measureText(text.content, text.style(), 0);
        const wrap = if (natural.width > p.bounds.w) p.bounds.w else 0;
        p.canvas.text(p.bounds.x, p.bounds.y, wrap, text.content, text.style(), text.text_color);
    }

    pub const padding = mod.padding;
    pub const frame = mod.frame;
    pub const flex = mod.flex;
    pub const bg = mod.bg;
    pub const clip = mod.clip;
    pub const opacity = mod.opacity;
    pub const tap = mod.tap;
    pub const key = mod.key;
    pub const input = mod.input;
    pub const wheel = mod.wheel;
    pub const pointer = mod.pointer;
    pub const animation = mod.animation;
    pub const with = mod.with;
};

// A rectangle that fills the space offered.
pub const Rect = struct {
    fill_color: Color = .black,
    stroke_color: Color = .transparent,
    stroke_width: f32 = 0,
    corner: f32 = 0,

    pub fn fill(rect: Rect, c: Color) Rect {
        return mod.set(rect, "fill_color", c);
    }

    // The stroke is drawn inside the rectangle.
    pub fn stroke(rect: Rect, c: Color, width: f32) Rect {
        return mod.set(mod.set(rect, "stroke_color", c), "stroke_width", width);
    }

    pub fn radius(rect: Rect, r: f32) Rect {
        return mod.set(rect, "corner", r);
    }

    pub fn measure(_: Rect, c: Constraint) Extent {
        return c.biggest();
    }

    pub fn paint(rect: Rect, p: Painter) void {
        p.fill(rect.corner, rect.fill_color);
        p.stroke(rect.corner, rect.stroke_width, rect.stroke_color);
    }

    pub const padding = mod.padding;
    pub const frame = mod.frame;
    pub const flex = mod.flex;
    pub const bg = mod.bg;
    pub const clip = mod.clip;
    pub const opacity = mod.opacity;
    pub const tap = mod.tap;
    pub const key = mod.key;
    pub const input = mod.input;
    pub const wheel = mod.wheel;
    pub const pointer = mod.pointer;
    pub const animation = mod.animation;
    pub const with = mod.with;
};

// How an image goes into a box of another shape: stretched over it, as
// large as fits inside, or as small as covers it with the rest cut off.
pub const Fit = enum { fill, contain, cover };

// An image at its own size, or smaller with the same shape where space is
// short. With a fit it takes the space offered instead, like a rect.
pub const Picture = struct {
    source: ?canvas.Image,
    fitting: ?Fit = null,

    pub fn fit(picture: Picture, how: Fit) Picture {
        return mod.set(picture, "fitting", how);
    }

    pub fn measure(picture: Picture, c: Constraint) Extent {
        const natural: Extent = if (picture.source) |image| image.size() else .{};
        if (picture.fitting != null) return c.constrain(.{
            .width = if (std.math.isInf(c.max.width)) natural.width else c.max.width,
            .height = if (std.math.isInf(c.max.height)) natural.height else c.max.height,
        });
        if (natural.width <= 0 or natural.height <= 0) return c.min;
        const scale = @min(1, c.max.width / natural.width, c.max.height / natural.height);
        return c.constrain(.{ .width = natural.width * scale, .height = natural.height * scale });
    }

    pub fn paint(picture: Picture, p: Painter) void {
        const image = picture.source orelse return;
        const natural = image.size();
        if (natural.width <= 0 or natural.height <= 0) return;
        const across = p.bounds.w / natural.width;
        const down = p.bounds.h / natural.height;
        const scale: [2]f32 = switch (picture.fitting orelse .contain) {
            .fill => .{ across, down },
            .contain => @splat(@min(across, down)),
            .cover => @splat(@max(across, down)),
        };
        const w = natural.width * scale[0];
        const h = natural.height * scale[1];
        const area: types.Bounds = .{
            .x = p.bounds.x + (p.bounds.w - w) / 2,
            .y = p.bounds.y + (p.bounds.h - h) / 2,
            .w = w,
            .h = h,
        };

        const covers = picture.fitting == .cover;
        if (covers) p.canvas.pushLayer();
        p.canvas.image(image, area);
        if (covers) p.canvas.popLayer(p.bounds, 0, 255);
    }

    pub const padding = mod.padding;
    pub const frame = mod.frame;
    pub const flex = mod.flex;
    pub const bg = mod.bg;
    pub const clip = mod.clip;
    pub const opacity = mod.opacity;
    pub const tap = mod.tap;
    pub const key = mod.key;
    pub const input = mod.input;
    pub const wheel = mod.wheel;
    pub const pointer = mod.pointer;
    pub const animation = mod.animation;
    pub const with = mod.with;
};

// Takes the free space of a row or column.
pub const Spacer = struct { flex: f32 = 1 };
