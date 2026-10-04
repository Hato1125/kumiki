// An implementation without a window: events come from a queue that the test
// fills, and the test sets the time and the size.

const std = @import("std");
const ui = @import("katagi");

const Fake = @This();

pub const Options = struct {
    font: ?[:0]const u8 = null,
    size: ui.Extent = .{ .width = 400, .height = 300 },
};

gpa: std.mem.Allocator,
queue: [16]ui.Event = undefined,
first: usize = 0,
count: usize = 0,
extent: ui.Extent,
seconds: f64 = 0,
// Drawn to when set. A canvas needs OpenGL, so only views that leave it
// alone can be painted here.
canvas: ?*ui.Canvas = null,
// Where the scene asked for typed text, or null while it asks for none, and
// how often it stopped asking.
typing: ?ui.Bounds = null,
stops: u32 = 0,
// How long the scene was ready to wait for the last event it asked for.
waited: f64 = 0,
// What was copied last. A test copies here itself to have it pasted, and
// sets `refuses` to have the next copies fail.
clipboard: std.ArrayList(u8) = .empty,
refuses: bool = false,

pub fn init(gpa: std.mem.Allocator, options: Options) !Fake {
    try ui.startup(options.font);
    return .{ .gpa = gpa, .extent = options.size };
}

pub fn deinit(fake: *Fake) void {
    fake.clipboard.deinit(fake.gpa);
    ui.shutdown();
}

pub fn push(fake: *Fake, event: ui.Event) void {
    fake.queue[(fake.first + fake.count) % fake.queue.len] = event;
    fake.count += 1;
}

pub fn next(fake: *Fake, wait: f64) ?ui.Event {
    fake.waited = wait;
    if (fake.count == 0) return null;
    defer fake.first = (fake.first + 1) % fake.queue.len;
    fake.count -= 1;
    return fake.queue[fake.first];
}

pub fn size(fake: *const Fake) ui.Extent {
    return fake.extent;
}

pub fn now(fake: *const Fake) f64 {
    return fake.seconds;
}

pub fn begin(fake: *Fake) !?*ui.Canvas {
    return fake.canvas;
}

pub fn end(_: *Fake) !void {}

// Nothing waits here: a test keeps advancing frames on its own.
pub fn wake(_: *Fake) void {}

pub fn input(fake: *Fake, area: ?ui.Bounds) void {
    if (area == null) fake.stops += 1;
    fake.typing = area;
}

pub fn paste(fake: *Fake, into: std.mem.Allocator) ?[]const u8 {
    if (fake.clipboard.items.len == 0) return null;
    return into.dupe(u8, fake.clipboard.items) catch @panic("out of memory");
}

pub fn copy(fake: *Fake, text: []const u8) bool {
    if (fake.refuses) return false;
    fake.clipboard.clearRetainingCapacity();
    fake.clipboard.appendSlice(fake.gpa, text) catch @panic("out of memory");
    return true;
}
