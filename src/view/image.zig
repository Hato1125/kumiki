const std = @import("std");

const gfx = @import("gfx");

const Image = @import("../image.zig").Image;
const types = @import("../types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const mod = @import("../mod.zig");
const Painter = @import("../paint.zig").Painter;

/// How an image goes into a box of another shape: stretched over it, as
/// large as fits inside, or as small as covers it with the rest cut off.
pub const Fit = gfx.Fit;

/// The config of an image at its own size, or smaller with the same shape
/// where space is short. With a fit it takes the space offered instead, like
/// a rect. Its settings are methods of the container.
pub const Picture = struct {
    source: ?Image,
    fitting: ?Fit = null,

    pub fn measure(picture: Picture, c: Constraint) Extent {
        const natural: Extent = if (picture.source) |source| source.size() else .{};
        if (picture.fitting != null) return c.constrain(.{
            .width = if (std.math.isInf(c.max.width)) natural.width else c.max.width,
            .height = if (std.math.isInf(c.max.height)) natural.height else c.max.height,
        });
        if (natural.width <= 0 or natural.height <= 0) return c.min;
        const scale = @min(1, c.max.width / natural.width, c.max.height / natural.height);
        return c.constrain(.{
            .width = natural.width * scale,
            .height = natural.height * scale,
        });
    }

    pub fn paint(picture: Picture, p: Painter) void {
        const source = picture.source orelse return;
        const uploaded = source.on(p.canvas) orelse return;
        p.canvas.image(.{
            .image = uploaded,
            .x = p.bounds.x,
            .y = p.bounds.y,
            .width = p.bounds.w,
            .height = p.bounds.h,
            .fit = picture.fitting orelse .contain,
        });
    }
};

/// Shows `source`, or nothing while it is null.
pub fn image(source: ?Image) mod.Container(void, Picture) {
    return mod.leaf(Picture{ .source = source });
}
