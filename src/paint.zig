const Canvas = @import("canvas.zig").Canvas;
const types = @import("types.zig");
const node_zig = @import("node.zig");
const has = node_zig.has;

pub const Painter = struct {
    canvas: *Canvas,
    bounds: types.Bounds,

    pub fn fill(p: Painter, radius: f32, color: types.Color) void {
        p.canvas.fillRect(p.bounds, radius, color);
    }

    pub fn stroke(p: Painter, radius: f32, width: f32, color: types.Color) void {
        p.canvas.strokeRect(p.bounds, radius, width, color);
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
/// `endPaint`.
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
    _ = node_zig.each(node, .shown, paint, .{canvas});
    if (comptime has(Widget, "endPaint")) node.widget.endPaint(p);
}
