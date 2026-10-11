const std = @import("std");
const gfx = @import("gfx");

const types = @import("types.zig");
const node_zig = @import("node.zig");
const has = node_zig.has;

/// What a frame is drawn to. `now` is the time of the frame and `again` is
/// when the next one is due at the latest; the scene sets both and reads
/// `again` after the drawing.
pub const Target = struct {
    canvas: *gfx.Canvas,
    now: f64 = 0,
    again: f64 = std.math.inf(f64),
};

pub const Painter = struct {
    canvas: *gfx.Canvas,
    bounds: types.Bounds,
    target: *Target,

    /// The bounds in the form the canvas takes them, for a clip.
    pub fn box(p: Painter) gfx.Bounds {
        return .{
            .x = p.bounds.x,
            .y = p.bounds.y,
            .width = p.bounds.w,
            .height = p.bounds.h,
        };
    }

    pub fn fill(p: Painter, corners: gfx.Corners, color: gfx.Color) void {
        if (color.a == 0) return;
        p.canvas.rect(.{
            .x = p.bounds.x,
            .y = p.bounds.y,
            .width = p.bounds.w,
            .height = p.bounds.h,
            .color = color,
            .corners = corners,
        });
    }

    /// The stroke is kept inside the bounds.
    pub fn stroke(p: Painter, corners: gfx.Corners, width: f32, color: gfx.Color) void {
        if (color.a == 0 or width <= 0) return;
        p.canvas.rect(.{
            .x = p.bounds.x,
            .y = p.bounds.y,
            .width = p.bounds.w,
            .height = p.bounds.h,
            .color = .transparent,
            .corners = corners,
            .border = .{ .width = width, .color = color },
        });
    }

    /// The time of this frame in seconds, on the clock of Context.now.
    pub fn now(p: Painter) f64 {
        return p.target.now;
    }

    /// Asks for another frame at `time`, for a drawing that changes with the
    /// time, such as a blinking caret, without anything being built again.
    pub fn again(p: Painter, time: f64) void {
        p.target.again = @min(p.target.again, time);
    }
};

/// Draws a widget in `paint`, and around its children in `beginPaint` and
/// `endPaint`. What a popup shows is left to `popup.paint`, which draws it
/// after everything else.
pub fn paint(node: anytype, target: *Target) void {
    const Widget = @TypeOf(node.widget);
    const at = node_zig.offsetOf(node);
    const p: Painter = .{
        .canvas = target.canvas,
        .bounds = .{
            .x = at.x,
            .y = at.y,
            .w = node.size.width,
            .h = node.size.height,
        },
        .target = target,
    };

    if (comptime has(Widget, "paint")) node.widget.paint(p);
    if (comptime has(Widget, "beginPaint")) node.widget.beginPaint(p);

    if (comptime node_zig.isPopup(Widget)) {
        paint(&node.children[0], target);
    } else {
        _ = node_zig.each(node, .shown, paint, .{target});
    }
    if (comptime has(Widget, "endPaint")) node.widget.endPaint(p);
}
