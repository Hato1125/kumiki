const std = @import("std");

const canvas = @import("../canvas.zig");
const types = @import("../types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const mod = @import("../mod.zig");
const Painter = @import("../paint.zig").Painter;

/// How an image goes into a box of another shape: stretched over it, as
/// large as fits inside, or as small as covers it with the rest cut off.
pub const Fit = enum { fill, contain, cover };

/// An image at its own size, or smaller with the same shape where space is
/// short. With a fit it takes the space offered instead, like a rect.
pub const Picture = struct {
    source: ?canvas.Image,
    fitting: ?Fit = null,

    pub fn fit(picture: Picture, how: Fit) Picture {
        return mod.set(picture, "fitting", how);
    }

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
        const natural = source.size();
        if (natural.width <= 0 or natural.height <= 0) return;
        const across = p.bounds.w / natural.width;
        const down = p.bounds.h / natural.height;
        const scale: [2]f32 = switch (picture.fitting orelse .contain) {
            .fill => .{ across, down },
            .contain => @splat(@min(across, down)),
            .cover => @splat(@max(across, down)),
        };
        const w = natural.width * scale[0];
        const h = natural.height * scale[1];
        const area: types.Bounds = .{
            .x = p.bounds.x + (p.bounds.w - w) / 2,
            .y = p.bounds.y + (p.bounds.h - h) / 2,
            .w = w,
            .h = h,
        };

        const covers = picture.fitting == .cover;
        if (covers) p.canvas.pushLayer();
        p.canvas.image(source, area);
        if (covers) p.canvas.popLayer(p.bounds, 0, 255);
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

/// Shows `source`, or nothing while it is null.
pub fn image(source: ?canvas.Image) Picture {
    return .{ .source = source };
}
