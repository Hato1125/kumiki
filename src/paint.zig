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
};

// Draws a widget in `paint`, and around its children in `beginPaint` and
// `endPaint`.
pub fn paint(node: anytype, canvas: *Canvas) void {
    const Widget = @TypeOf(node.widget);
    const p: Painter = .{ .canvas = canvas, .bounds = .{
        .x = node.offset.x,
        .y = node.offset.y,
        .w = node.size.width,
        .h = node.size.height,
    } };
    if (comptime has(Widget, "paint")) node.widget.paint(p);
    if (comptime has(Widget, "beginPaint")) node.widget.beginPaint(p);
    _ = node_zig.each(node, .shown, paint, .{canvas});
    if (comptime has(Widget, "endPaint")) node.widget.endPaint(p);
}
