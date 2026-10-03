// An implementation without a window: events come from a queue that the test
// fills, and the test sets the time and the size.

const std = @import("std");
const ui = @import("katagi");

const Fake = @This();

pub const Options = struct {
    font: ?[:0]const u8 = null,
    size: ui.Extent = .{ .width = 400, .height = 300 },
};

queue: [16]ui.Event = undefined,
first: usize = 0,
count: usize = 0,
extent: ui.Extent,
seconds: f64 = 0,
// Drawn to when set. A canvas needs OpenGL, so only views that leave it
// alone can be painted here.
canvas: ?*ui.Canvas = null,

pub fn init(_: std.mem.Allocator, options: Options) !Fake {
    try ui.startup(options.font);
    return .{ .extent = options.size };
}

pub fn deinit(_: *Fake) void {
    ui.shutdown();
}

pub fn push(fake: *Fake, event: ui.Event) void {
    fake.queue[(fake.first + fake.count) % fake.queue.len] = event;
    fake.count += 1;
}

pub fn next(fake: *Fake, _: bool) ?ui.Event {
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
