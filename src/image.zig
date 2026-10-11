//! Reads image files. The canvas takes pixels, not files.

const std = @import("std");
const c = @import("c");
const gfx = @import("gfx");

const types = @import("types.zig");
const Extent = types.Extent;

const gpa = std.heap.c_allocator;

const Loaded = struct {
    // Kept until the image is first drawn, then handed to the canvas.
    pixels: ?[]u8,
    width: u32,
    height: u32,
    uploaded: ?gfx.Image = null,
};

var images: std.ArrayList(Loaded) = .empty;
// The canvas that holds the uploads.
var owner: ?*gfx.Canvas = null;

/// A PNG or JPG file that is read once and drawn as often as needed. It lives
/// until `shutdown`, and can only be drawn on one canvas.
pub const Image = struct {
    index: usize,

    pub fn load(path: [:0]const u8) !Image {
        const file = try readFile(path);
        defer gpa.free(file);
        const decoded = try decode(file);
        errdefer gpa.free(decoded.pixels.?);
        try images.append(gpa, decoded);
        return .{ .index = images.items.len - 1 };
    }

    pub fn deinit(image: Image) void {
        const loaded = &images.items[image.index];
        if (loaded.pixels) |pixels| gpa.free(pixels);
        if (loaded.uploaded) |uploaded| {
            if (owner) |canvas| canvas.destroyImage(uploaded);
        }
        loaded.* = .{ .pixels = null, .width = 0, .height = 0 };
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
        gpa.free(pixels);
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
        if (loaded.pixels) |pixels| gpa.free(pixels);
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

// Rows from the top down, four bytes a pixel: red, green, blue and alpha.
fn decode(file: []const u8) !Loaded {
    const png_magic = "\x89PNG";
    const jpg_magic = "\xff\xd8";
    if (std.mem.startsWith(u8, file, png_magic)) return decodePng(file);
    if (std.mem.startsWith(u8, file, jpg_magic)) return decodeJpg(file);
    return error.ImageLoad;
}

fn decodePng(file: []const u8) !Loaded {
    var png: c.png_image = std.mem.zeroes(c.png_image);
    png.version = c.PNG_IMAGE_VERSION;
    if (c.png_image_begin_read_from_memory(&png, file.ptr, file.len) == 0) {
        return error.ImageLoad;
    }
    defer c.png_image_free(&png);
    png.format = c.PNG_FORMAT_RGBA;

    const pixels = try gpa.alloc(u8, @as(usize, png.width) * png.height * 4);
    errdefer gpa.free(pixels);
    if (c.png_image_finish_read(&png, null, pixels.ptr, 0, null) == 0) {
        return error.ImageLoad;
    }
    return .{ .pixels = pixels, .width = png.width, .height = png.height };
}

fn decodeJpg(file: []const u8) !Loaded {
    const reader = c.tjInitDecompress() orelse return error.ImageLoad;
    defer _ = c.tjDestroy(reader);

    var width: c_int = 0;
    var height: c_int = 0;
    var subsampling: c_int = 0;
    var colorspace: c_int = 0;
    const header = c.tjDecompressHeader3(
        reader,
        file.ptr,
        @intCast(file.len),
        &width,
        &height,
        &subsampling,
        &colorspace,
    );
    if (header != 0 or width <= 0 or height <= 0) return error.ImageLoad;

    const wide: usize = @intCast(width);
    const high: usize = @intCast(height);
    const pixels = try gpa.alloc(u8, wide * high * 4);
    errdefer gpa.free(pixels);
    const read = c.tjDecompress2(
        reader,
        file.ptr,
        @intCast(file.len),
        pixels.ptr,
        width,
        0,
        height,
        c.TJPF_RGBA,
        0,
    );
    if (read != 0) return error.ImageLoad;
    return .{ .pixels = pixels, .width = @intCast(width), .height = @intCast(height) };
}
