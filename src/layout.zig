const types = @import("types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const node_zig = @import("node.zig");
const each = node_zig.each;
const has = node_zig.has;

// Measures `node` and everything inside it, and returns its size, which also
// stays in `node.size`. A config measures all of its children in
// `measureAll`, or the one child of a modifier in `measure`.
pub fn measure(node: anytype, c: Constraint) Extent {
    const Widget = @TypeOf(node.widget);
    const children = &node.children;
    node.size = if (comptime @TypeOf(children.*) == void)
        (if (comptime has(Widget, "measure")) node.widget.measure(c) else c.min)
    else if (comptime has(Widget, "measureAll"))
        node.widget.measureAll(children, c)
    else if (comptime has(Widget, "measure"))
        node.widget.measure(&children[children.len - 1], c)
    else
        measureLast(children, c);
    return node.size;
}

// Takes the size of the last child. The children before it, such as a
// background, are sized to it.
fn measureLast(children: anytype, c: Constraint) Extent {
    const size = measure(&children[children.len - 1], c);
    inline for (0..children.len - 1) |i| {
        _ = measure(&children[i], .tight(size));
    }
    return size;
}

// Places `node`, which was measured before, and everything inside it.
pub fn layout(node: anytype, at: Point) void {
    const Widget = @TypeOf(node.widget);
    const children = &node.children;
    if (comptime @TypeOf(node.offset) != void) node.offset = at;
    if (comptime @TypeOf(children.*) == void) return;
    if (comptime has(Widget, "layoutAll")) {
        return node.widget.layoutAll(children, at, node.size);
    }
    if (comptime has(Widget, "layout")) {
        return node.widget.layout(&children[children.len - 1], at, node.size);
    }
    _ = each(node, .all, layout, .{at});
}

// The share of the free space that a row or column gives this child, seen
// through components.
pub fn flexOf(node: anytype) f32 {
    const Widget = @TypeOf(node.widget);
    if (comptime node_zig.isComponent(Widget)) return flexOf(&node.children[0]);
    return if (comptime @hasField(Widget, "flex")) node.widget.flex else 0;
}
