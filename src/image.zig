//! Reads image files. The canvas takes pixels, not files.

const std = @import("std");
const gfx = @import("gfx");

const types = @import("types.zig");
const Extent = types.Extent;

const gpa = std.heap.c_allocator;

const Loaded = struct {
    // Kept until the image is first drawn, then handed to the canvas. The
    // decoder allocates them, so they are freed with `std.c.free`.
    pixels: ?[]u8,
    width: u32,
    height: u32,
    uploaded: ?gfx.Image = null,
};

var images: std.ArrayList(Loaded) = .empty;
// The canvas that holds the uploads.
var owner: ?*gfx.Canvas = null;

/// A PNG, JPG or WebP file that is read once and drawn as often as needed. It
/// lives until `shutdown`, and can only be drawn on one canvas. A WebP file
/// cannot be animated, and one that is transparent has to be lossless.
pub const Image = struct {
    index: usize,

    pub fn load(path: [:0]const u8) !Image {
        const file = try readFile(path);
        defer gpa.free(file);
        const decoded = try decode(file);
        errdefer std.c.free(decoded.pixels.?.ptr);
        try images.append(gpa, decoded);
        return .{ .index = images.items.len - 1 };
    }

    pub fn deinit(image: Image) void {
        const loaded = &images.items[image.index];
        if (loaded.pixels) |pixels| std.c.free(pixels.ptr);
        if (loaded.uploaded) |uploaded| {
            if (owner) |canvas| canvas.destroyImage(uploaded);
        }

        loaded.* = .{
            .pixels = null,
            .width = 0,
            .height = 0,
        };
    }

    /// In the pixels of the file.
    pub fn size(image: Image) Extent {
        const loaded = images.items[image.index];
        return .{
            .width = @floatFromInt(loaded.width),
            .height = @floatFromInt(loaded.height),
        };
    }

    /// What `canvas` draws the image as. The pixels go to the canvas the
    /// first time. Null for an image that was let go of or that the canvas
    /// could not take.
    pub fn on(image: Image, canvas: *gfx.Canvas) ?gfx.Image {
        const loaded = &images.items[image.index];
        if (loaded.uploaded) |uploaded| return uploaded;
        const pixels = loaded.pixels orelse return null;
        loaded.uploaded = canvas.createImage(.{
            .width = loaded.width,
            .height = loaded.height,
            .pixels = pixels,
        }) catch return null;
        std.c.free(pixels.ptr);
        loaded.pixels = null;
        owner = canvas;
        return loaded.uploaded;
    }
};

/// An implementation calls this before the canvas it draws on goes away:
/// the uploads go with it.
pub fn release() void {
    for (images.items) |*loaded| loaded.uploaded = null;
    owner = null;
}

pub fn shutdown() void {
    for (images.items) |loaded| {
        if (loaded.pixels) |pixels| std.c.free(pixels.ptr);
    }
    images.clearAndFree(gpa);
}

fn readFile(path: [:0]const u8) ![]u8 {
    const file = std.c.fopen(path, "rb") orelse return error.FileOpen;
    defer _ = std.c.fclose(file);
    var bytes: std.ArrayList(u8) = .empty;
    errdefer bytes.deinit(gpa);
    while (true) {
        try bytes.ensureUnusedCapacity(gpa, 64 * 1024);
        const space = bytes.unusedCapacitySlice();
        const count = std.c.fread(space.ptr, 1, space.len, file);
        if (count == 0) break;
        bytes.items.len += count;
    }
    return bytes.toOwnedSlice(gpa);
}

// Defined in image.c.
extern fn kumiki_decode_image(data: [*]const u8, length: usize, width: *u32, height: *u32) ?[*]u8;

fn decode(file: []const u8) !Loaded {
    var width: u32 = 0;
    var height: u32 = 0;
    const pixels = kumiki_decode_image(file.ptr, file.len, &width, &height) orelse
        return error.ImageLoad;
    return .{
        .pixels = pixels[0 .. @as(usize, width) * height * 4],
        .width = width,
        .height = height,
    };
}
