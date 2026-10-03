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
    pub const animation = mod.animation;
    pub const with = mod.with;
};

// Takes the free space of a row or column.
pub const Spacer = struct { flex: f32 = 1 };
