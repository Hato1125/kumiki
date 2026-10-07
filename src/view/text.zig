const std = @import("std");

const canvas = @import("../canvas.zig");
const types = @import("../types.zig");
const Color = types.Color;
const Constraint = types.Constraint;
const Extent = types.Extent;
const mod = @import("../mod.zig");
const Painter = @import("../paint.zig").Painter;

/// The config of a text. Its settings are methods of the container.
pub const Text = struct {
    content: []const u8,
    font_size: f32 = 16,
    text_color: Color = .black,
    font_name: ?[:0]const u8 = null,
    fallback_name: ?[:0]const u8 = null,
    line_height: ?f32 = null,
    letter_spacing: f32 = 0,

    fn style(self: Text) canvas.TextStyle {
        return .{
            .size = self.font_size,
            .font = self.font_name,
            .fallback = self.fallback_name,
            .line_height = self.line_height,
            .tracking = self.letter_spacing,
        };
    }

    /// The width up to where the next character would go. It counts the
    /// spaces at the end, which `measure` leaves out, so a caret goes there.
    pub fn advance(self: Text) f32 {
        return canvas.textAdvance(self.content, self.style());
    }

    /// The position in the text whose advance is nearest to `x`: a byte
    /// offset between two code points, for a caret to go where a pointer is.
    pub fn indexAt(self: Text, x: f32) usize {
        return canvas.textIndexAt(self.content, self.style(), x);
    }

    /// Wraps when the text is wider than the space offered.
    pub fn measure(self: Text, c: Constraint) Extent {
        const natural = canvas.measureText(self.content, self.style(), 0);
        if (std.math.isInf(c.max.width) or natural.width <= c.max.width) {
            return c.constrain(natural);
        }
        return c.constrain(canvas.measureText(self.content, self.style(), c.max.width));
    }

    pub fn paint(self: Text, p: Painter) void {
        const natural = canvas.measureText(self.content, self.style(), 0);
        const wrap = if (natural.width > p.bounds.w) p.bounds.w else 0;
        p.canvas.text(p.bounds.x, p.bounds.y, wrap, self.content, self.style(), self.text_color);
    }
};

pub fn text(content: []const u8) mod.Container(void, Text) {
    return mod.leaf(Text{ .content = content });
}
