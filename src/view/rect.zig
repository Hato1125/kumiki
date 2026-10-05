const types = @import("../types.zig");
const Color = types.Color;
const Constraint = types.Constraint;
const Extent = types.Extent;
const mod = @import("../mod.zig");
const Painter = @import("../paint.zig").Painter;

/// A rectangle that fills the space offered.
pub const Rect = struct {
    fill_color: Color = .black,
    stroke_color: Color = .transparent,
    stroke_width: f32 = 0,
    corner: f32 = 0,

    pub fn fill(self: Rect, c: Color) Rect {
        return mod.set(self, "fill_color", c);
    }

    /// The stroke is drawn inside the rectangle.
    pub fn stroke(self: Rect, c: Color, width: f32) Rect {
        return mod.set(mod.set(self, "stroke_color", c), "stroke_width", width);
    }

    pub fn radius(self: Rect, r: f32) Rect {
        return mod.set(self, "corner", r);
    }

    pub fn measure(_: Rect, c: Constraint) Extent {
        return c.biggest();
    }

    pub fn paint(self: Rect, p: Painter) void {
        p.fill(self.corner, self.fill_color);
        p.stroke(self.corner, self.stroke_width, self.stroke_color);
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
    pub const hover = mod.hover;
    pub const drop = mod.drop;
    pub const popup = mod.popup;
    pub const shortcut = mod.shortcut;
    pub const animation = mod.animation;
    pub const with = mod.with;
};

pub fn rect() Rect {
    return .{};
}
