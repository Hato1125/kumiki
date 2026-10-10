const canvas_zig = @import("canvas.zig");
const Canvas = canvas_zig.Canvas;
const Corners = canvas_zig.Corners;
const types = @import("types.zig");
const node_zig = @import("node.zig");
const has = node_zig.has;

pub const Painter = struct {
    canvas: *Canvas,
    bounds: types.Bounds,

    pub fn fill(p: Painter, corners: Corners, color: types.Color) void {
        p.canvas.fillRect(p.bounds, corners, color);
    }

    pub fn stroke(p: Painter, corners: Corners, width: f32, color: types.Color) void {
        p.canvas.strokeRect(p.bounds, corners, width, color);
    }

    /// The time of this frame in seconds, on the clock of Context.now.
    pub fn now(p: Painter) f64 {
        return p.canvas.now;
    }

    /// Asks for another frame at `time`, for a drawing that changes with the
    /// time, such as a blinking caret, without anything being built again.
    pub fn again(p: Painter, time: f64) void {
        p.canvas.again = @min(p.canvas.again, time);
    }
};

/// Draws a widget in `paint`, and around its children in `beginPaint` and
/// `endPaint`. What a popup shows is left to `popup.paint`, which draws it
/// after everything else.
pub fn paint(node: anytype, canvas: *Canvas) void {
    const Widget = @TypeOf(node.widget);
    const at = node_zig.offsetOf(node);
    const p: Painter = .{ .canvas = canvas, .bounds = .{
        .x = at.x,
        .y = at.y,
        .w = node.size.width,
        .h = node.size.height,
    } };
    if (comptime has(Widget, "paint")) node.widget.paint(p);
    if (comptime has(Widget, "beginPaint")) node.widget.beginPaint(p);
    if (comptime node_zig.isPopup(Widget)) {
        paint(&node.children[0], canvas);
    } else {
        _ = node_zig.each(node, .shown, paint, .{canvas});
    }
    if (comptime has(Widget, "endPaint")) node.widget.endPaint(p);
}
