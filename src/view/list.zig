const std = @import("std");

const types = @import("../types.zig");
const Constraint = types.Constraint;
const Extent = types.Extent;
const Point = types.Point;
const pass = @import("../layout.zig");
const mod = @import("../mod.zig");
const ReturnOf = @import("../node.zig").ReturnOf;

/// Stacks one row per element of the slice that `source_fn` returns. Rows
/// follow the `id` field of the elements when they have one, and their index
/// otherwise.
pub fn List(comptime source_fn: anytype, comptime make: anytype) type {
    const Slice = ReturnOf(source_fn);
    const Element = @typeInfo(Slice).pointer.child;
    const Id = if (@typeInfo(Element) == .@"struct" and @hasField(Element, "id")) @FieldType(Element, "id") else void;
    const is_string = Id == []const u8;

    return struct {
        spacing: f32 = 0,
        keys: if (keyed) std.ArrayList(Id) else void = if (keyed) .empty else {},

        const Self = @This();

        pub const source = source_fn;
        pub const Row = ReturnOf(make);
        pub const keyed = Id != void;

        pub fn gap(self: Self, spacing: f32) Self {
            return mod.set(self, "spacing", spacing);
        }

        /// Takes the settings of `next`. The keys stay, because they belong
        /// to the rows.
        pub fn adopt(self: *Self, next: Self) void {
            self.spacing = next.spacing;
        }

        /// `make` takes a pointer to the element when its parameter is one,
        /// so rows can change their element.
        pub fn item(elements: Slice, i: usize) Row {
            const Param = @typeInfo(@TypeOf(make)).@"fn".params[0].type.?;
            return make(if (comptime @typeInfo(Param) == .pointer) &elements[i] else elements[i]);
        }

        pub fn sameKey(a: Id, b: Id) bool {
            return if (comptime is_string) std.mem.eql(u8, a, b) else a == b;
        }

        /// String keys are copied because the elements may change them.
        pub fn ownKey(gpa: std.mem.Allocator, id: Id) Id {
            return if (comptime is_string) gpa.dupe(u8, id) catch @panic("out of memory") else id;
        }

        pub fn freeKey(gpa: std.mem.Allocator, id: Id) void {
            if (comptime is_string) gpa.free(id);
        }

        pub fn deinitKeys(self: *Self, gpa: std.mem.Allocator) void {
            if (comptime !keyed) return;
            for (self.keys.items) |id| freeKey(gpa, id);
            self.keys.deinit(gpa);
        }

        pub fn measureAll(self: Self, rows: anytype, c: Constraint) Extent {
            var size: Extent = .{};
            for (rows.items, 0..) |*row, i| {
                const row_size = pass.measure(row, .{
                    .max = .{ .width = c.max.width, .height = types.inf },
                });
                size.width = @max(size.width, row_size.width);
                size.height += row_size.height + if (i == 0) 0 else self.spacing;
            }
            if (!std.math.isInf(c.max.width)) size.width = c.max.width;
            return c.constrain(size);
        }

        pub fn layoutAll(self: Self, rows: anytype, at: Point, _: Extent) void {
            var y = at.y;
            for (rows.items) |*row| {
                pass.layout(row, .{ .x = at.x, .y = y });
                y += row.size.height + self.spacing;
            }
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
        pub const animation = mod.animation;
        pub const with = mod.with;
    };
}

/// `source` returns a slice and `make` turns an element, or a pointer to it,
/// into the view of its row. The parameters of `source` are filled in by type
/// like those of `ui.show`.
pub fn list(
    comptime source: anytype,
    comptime make: anytype,
) List(source, make) {
    return .{};
}
