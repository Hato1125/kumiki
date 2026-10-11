const std = @import("std");

const text_zig = @import("../text.zig");
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

    fn style(self: Text) text_zig.Style {
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
        return text_zig.advance(self.content, self.style());
    }

    /// The position in the text whose advance is nearest to `x`: a byte
    /// offset between two code points, for a caret to go where a pointer is.
    pub fn indexAt(self: Text, x: f32) usize {
        return text_zig.indexAt(self.content, self.style(), x);
    }

    /// Wraps when the text is wider than the space offered.
    pub fn measure(self: Text, c: Constraint) Extent {
        const natural = text_zig.measure(self.content, self.style(), 0);
        if (std.math.isInf(c.max.width) or natural.width <= c.max.width) {
            return c.constrain(natural);
        }
        return c.constrain(text_zig.measure(self.content, self.style(), c.max.width));
    }

    pub fn paint(self: Text, p: Painter) void {
        if (self.content.len == 0 or self.text_color.a == 0) return;
        const natural = text_zig.measure(self.content, self.style(), 0);
        const wrap = if (natural.width > p.bounds.w) p.bounds.w else 0;
        const laid = text_zig.layout(self.content, self.style(), wrap) orelse return;
        p.canvas.text(.{
            .x = p.bounds.x,
            .y = p.bounds.y,
            .layout = laid,
            .color = self.text_color,
        });
    }
};

pub fn text(content: []const u8) mod.Container(void, Text) {
    return mod.leaf(Text{ .content = content });
}
