// A modifier is a method of every view that wraps the view in a Container:
// children and a config that measures, places and paints them.

const std = @import("std");

const anim = @import("anime.zig");
const types = @import("types.zig");
const Color = types.Color;
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("layout.zig");
const Resolved = @import("node.zig").Resolved;
const Painter = @import("paint.zig").Painter;
const Alignment = @import("stack.zig").Alignment;

const mod = @This();

pub fn Container(comptime Children: type, comptime Config: type) type {
    return struct {
        children: Children,
        config: Config,

        const Self = @This();

        fn set(self: Self, comptime setting: []const u8, value: @FieldType(Config, setting)) Self {
            return .{ .children = self.children, .config = mod.set(self.config, setting, value) };
        }

        // The settings of rows, columns and stacks. A declaration is
        // analyzed only when it is used, so each exists for the configs
        // with a field of that name.
        pub fn gap(self: Self, value: @FieldType(Config, "gap")) Self {
            return self.set("gap", value);
        }

        pub fn main(self: Self, value: @FieldType(Config, "main")) Self {
            return self.set("main", value);
        }

        pub fn cross(self: Self, value: @FieldType(Config, "cross")) Self {
            return self.set("cross", value);
        }

        pub fn alignment(self: Self, value: @FieldType(Config, "alignment")) Self {
            return self.set("alignment", value);
        }

        pub const padding = mod.padding;
        pub const frame = mod.frame;
        pub const flex = mod.flex;
        pub const bg = mod.bg;
        pub const clip = mod.clip;
        pub const opacity = mod.opacity;
        pub const tap = mod.tap;
        pub const key = mod.key;
        pub const animation = mod.animation;
        pub const with = mod.with;
    };
}

// A copy of `view` with one field changed.
pub fn set(view: anytype, comptime field: []const u8, value: @FieldType(@TypeOf(view), field)) @TypeOf(view) {
    var next = view;
    @field(next, field) = value;
    return next;
}

// Method calls may pass `self` by pointer.
fn Base(comptime Self: type) type {
    return switch (@typeInfo(Self)) {
        .pointer => |pointer| pointer.child,
        else => Self,
    };
}

fn base(self: anytype) Base(@TypeOf(self)) {
    return if (@typeInfo(@TypeOf(self)) == .pointer) self.* else self;
}

fn Wrapped(comptime Self: type, comptime Config: type) type {
    return Container(struct { Base(Self) }, Config);
}

// Wraps the view in `config`, a struct that may declare any of
// `measure(config, child, constraint) Extent`,
// `layout(config, child, position, size) void`,
// `beginPaint(config, painter) void` and `endPaint(config, painter) void`.
// Without them the view keeps the size and the position of its child.
pub fn with(self: anytype, config: anytype) Wrapped(@TypeOf(self), @TypeOf(config)) {
    return .{ .children = .{base(self)}, .config = config };
}

const Insets = struct {
    top: f32 = 0,
    right: f32 = 0,
    bottom: f32 = 0,
    left: f32 = 0,

    pub fn from(spec: anytype) Insets {
        const Spec = @TypeOf(spec);
        if (Spec == Insets) return spec;
        if (@typeInfo(Spec) != .@"struct") {
            return .{ .top = float(spec), .right = float(spec), .bottom = float(spec), .left = float(spec) };
        }
        var insets: Insets = .{};
        if (@hasField(Spec, "x")) insets.left = float(spec.x);
        if (@hasField(Spec, "x")) insets.right = float(spec.x);
        if (@hasField(Spec, "y")) insets.top = float(spec.y);
        if (@hasField(Spec, "y")) insets.bottom = float(spec.y);
        inline for (@typeInfo(Insets).@"struct".fields) |edge| {
            if (@hasField(Spec, edge.name)) @field(insets, edge.name) = float(@field(spec, edge.name));
        }
        return insets;
    }

    fn float(value: anytype) f32 {
        return switch (@typeInfo(@TypeOf(value))) {
            .int => @floatFromInt(value),
            .float => @floatCast(value),
            else => value,
        };
    }

    pub fn measure(insets: Insets, child: anytype, c: Constraint) Extent {
        const dx = insets.left + insets.right;
        const dy = insets.top + insets.bottom;
        const size = pass.measure(child, c.deflate(dx, dy));
        return c.constrain(.{ .width = size.width + dx, .height = size.height + dy });
    }

    pub fn layout(insets: Insets, child: anytype, at: Point, _: Extent) void {
        pass.layout(child, .{ .x = at.x + insets.left, .y = at.y + insets.top });
    }
};

// `spec` is a number for all edges, or a struct with any of `x`, `y`, `top`,
// `right`, `bottom` and `left`.
pub fn padding(self: anytype, spec: anytype) Wrapped(@TypeOf(self), Insets) {
    return with(self, Insets.from(spec));
}

// Gives the child a fixed size, or one that grows up to `max_width` and
// `max_height` where space allows, and places it inside.
const Frame = struct {
    width: ?f32 = null,
    height: ?f32 = null,
    max_width: ?f32 = null,
    max_height: ?f32 = null,
    alignment: Alignment = .center,

    fn outer(fixed: ?f32, max: ?f32, low: f32, high: f32, child: f32) f32 {
        if (fixed) |size| return std.math.clamp(size, low, high);
        if (max) |size| return if (std.math.isInf(high)) child else @max(child, @min(size, high));
        return child;
    }

    pub fn measure(f: Frame, child: anytype, c: Constraint) Extent {
        const size = pass.measure(child, .{ .max = .{
            .width = @min(f.width orelse f.max_width orelse types.inf, c.max.width),
            .height = @min(f.height orelse f.max_height orelse types.inf, c.max.height),
        } });
        return c.constrain(.{
            .width = outer(f.width, f.max_width, c.min.width, c.max.width, size.width),
            .height = outer(f.height, f.max_height, c.min.height, c.max.height, size.height),
        });
    }

    pub fn layout(f: Frame, child: anytype, at: Point, size: Extent) void {
        pass.layout(child, f.alignment.place(at, size, child.size));
    }
};

pub fn frame(self: anytype, spec: Frame) Wrapped(@TypeOf(self), Frame) {
    return with(self, spec);
}

const Flexed = struct { flex: f32 };

pub fn flex(self: anytype, factor: f32) Wrapped(@TypeOf(self), Flexed) {
    return with(self, Flexed{ .flex = factor });
}

const Fill = struct {
    color: Color,

    pub fn beginPaint(fill: Fill, p: Painter) void {
        p.fill(0, fill.color);
    }
};

// A config that leaves everything to the passes: the view takes the size and
// the position of its last child, and a child before it is drawn behind it
// at its size.
const Plain = struct {};

fn Backed(comptime Self: type, comptime Back: type) type {
    return if (Back == Color) Wrapped(Self, Fill) else Container(struct { Back, Base(Self) }, Plain);
}

// `back` is a view to draw behind this one at its size, or a color.
pub fn bg(self: anytype, back: anytype) Backed(@TypeOf(self), @TypeOf(back)) {
    if (@TypeOf(back) == Color) return with(self, Fill{ .color = back });
    return .{ .children = .{ back, base(self) }, .config = .{} };
}

const Clip = struct {
    radius: f32,

    pub fn beginPaint(_: Clip, p: Painter) void {
        p.canvas.pushLayer();
    }

    pub fn endPaint(clipped: Clip, p: Painter) void {
        p.canvas.popLayer(p.bounds, clipped.radius, 255);
    }
};

pub fn clip(self: anytype, radius: f32) Wrapped(@TypeOf(self), Clip) {
    return with(self, Clip{ .radius = radius });
}

const Opacity = struct {
    value: f32,

    pub fn beginPaint(_: Opacity, p: Painter) void {
        p.canvas.pushLayer();
    }

    pub fn endPaint(o: Opacity, p: Painter) void {
        p.canvas.popLayer(null, 0, @intFromFloat(@round(std.math.clamp(o.value, 0, 1) * 255)));
    }
};

pub fn opacity(self: anytype, value: f32) Wrapped(@TypeOf(self), Opacity) {
    return with(self, Opacity{ .value = value });
}

fn Tap(comptime action: anytype) type {
    return struct {
        pub const tap_action = action;
    };
}

// Runs `action` on a click, or on Enter or Space while focused. Components
// that `action` receives as mutable pointers are built again after it runs.
pub fn tap(self: anytype, comptime action: anytype) Wrapped(@TypeOf(self), Tap(action)) {
    return with(self, Tap(action){});
}

fn Key(comptime handler: anytype) type {
    return struct {
        pub const key_handler = handler;
    };
}

// Offers key presses to `handler`, which returns whether it used the key.
pub fn key(self: anytype, comptime handler: anytype) Wrapped(@TypeOf(self), Key(handler)) {
    return with(self, Key(handler){});
}

fn Animated(comptime Child: type) type {
    return struct {
        spec: anim.Animation,
        tween: anim.Tween(Resolved(Child)) = undefined,
    };
}

// Moves the view from the value it shows to a new one over time whenever it
// is built with a different value.
pub fn animation(self: anytype, spec: anim.Animation) Wrapped(@TypeOf(self), Animated(Base(@TypeOf(self)))) {
    return with(self, Animated(Base(@TypeOf(self))){ .spec = spec });
}

// Gives modifiers to a value that has none, such as a component.
pub fn wrap(child: anytype) Wrapped(@TypeOf(child), Plain) {
    return with(child, Plain{});
}
