const std = @import("std");
const gfx = @import("gfx");

pub const inf = std.math.inf(f32);

pub const Point = struct { x: f32 = 0, y: f32 = 0 };
pub const Extent = struct { width: f32 = 0, height: f32 = 0 };
pub const Bounds = struct { x: f32 = 0, y: f32 = 0, w: f32 = 0, h: f32 = 0 };

/// Where something smaller sits inside a larger area: 0 is the left or top
/// edge and 1 is the right or bottom edge.
pub const Alignment = struct {
    x: f32 = 0.5,
    y: f32 = 0.5,

    pub const top_left: Alignment = .{ .x = 0, .y = 0 };
    pub const top: Alignment = .{ .x = 0.5, .y = 0 };
    pub const top_right: Alignment = .{ .x = 1, .y = 0 };
    pub const left: Alignment = .{ .x = 0, .y = 0.5 };
    pub const center: Alignment = .{ .x = 0.5, .y = 0.5 };
    pub const right: Alignment = .{ .x = 1, .y = 0.5 };
    pub const bottom_left: Alignment = .{ .x = 0, .y = 1 };
    pub const bottom: Alignment = .{ .x = 0.5, .y = 1 };
    pub const bottom_right: Alignment = .{ .x = 1, .y = 1 };

    pub fn place(a: Alignment, at: Point, outer: Extent, inner: Extent) Point {
        return .{
            .x = at.x + (outer.width - inner.width) * a.x,
            .y = at.y + (outer.height - inner.height) * a.y,
        };
    }
};

/// The bytes of a text from `start` up to `end`.
pub const Range = struct {
    start: usize = 0,
    end: usize = 0,

    pub fn len(range: Range) usize {
        return range.end - range.start;
    }
};

pub const Color = gfx.Color;

pub const Constraint = struct {
    min: Extent = .{},
    max: Extent = .{ .width = inf, .height = inf },

    pub fn tight(e: Extent) Constraint {
        return .{ .min = e, .max = e };
    }

    pub fn loosen(c: Constraint) Constraint {
        return .{ .max = c.max };
    }

    pub fn constrain(c: Constraint, e: Extent) Extent {
        return .{
            .width = std.math.clamp(e.width, c.min.width, c.max.width),
            .height = std.math.clamp(e.height, c.min.height, c.max.height),
        };
    }

    /// The largest finite size: the maximum where it is bounded, else the minimum.
    pub fn biggest(c: Constraint) Extent {
        return .{
            .width = if (std.math.isInf(c.max.width)) c.min.width else c.max.width,
            .height = if (std.math.isInf(c.max.height)) c.min.height else c.max.height,
        };
    }

    pub fn deflate(c: Constraint, dx: f32, dy: f32) Constraint {
        return .{
            .min = .{
                .width = @max(0, c.min.width - dx),
                .height = @max(0, c.min.height - dy),
            },
            .max = .{
                .width = @max(0, c.max.width - dx),
                .height = @max(0, c.max.height - dy),
            },
        };
    }
};
