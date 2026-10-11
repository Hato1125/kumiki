//! The fonts by name and the measuring of text. A text is laid out once
//! and the layout serves both the measuring and the drawing.

const std = @import("std");
const gfx = @import("gfx");

const types = @import("types.zig");
const Extent = types.Extent;

const gpa = std.heap.c_allocator;

// Text is measured before there is a canvas, and in tests there never is
// one, so the layouts are made here rather than by a canvas.
var texts: ?gfx.TextSystem = null;

// How many pixels make up one unit of the sizes.
var scale: f32 = 1;

/// The scene calls this before it measures with the scale that its
/// implementation draws at, so that what is measured is what is drawn.
pub fn setScale(pixels_per_unit: f32) void {
    scale = pixels_per_unit;
}

const LoadedFont = struct {
    name: []const u8,
    font: gfx.Font,
};

var loaded_fonts: std.ArrayList(LoadedFont) = .empty;
var default_font: ?gfx.Font = null;

/// Loads `font` for the text that names no font. An implementation calls this
/// before it measures or draws, and `shutdown` at its end.
pub fn startup(font: ?[:0]const u8) !void {
    texts = try .init(gpa);
    errdefer shutdown();
    default_font = null;
    const path = font orelse return;
    try addFont(path);
    default_font = loaded_fonts.items[loaded_fonts.items.len - 1].font;
}

pub fn shutdown() void {
    for (loaded_fonts.items) |font| gpa.free(font.name);
    loaded_fonts.clearAndFree(gpa);
    if (texts) |*started| started.deinit();
    texts = null;
}

/// Loads a font that text can ask for by name, which is the file name
/// without its extension.
pub fn addFont(path: [:0]const u8) !void {
    const started = try system();
    const font = try started.loadFont(path, .{});
    const name = try gpa.dupe(u8, std.fs.path.stem(path));
    errdefer gpa.free(name);
    try loaded_fonts.append(gpa, .{ .name = name, .font = font });
}

/// What a canvas has to share to draw the layouts made here.
pub fn system() !*gfx.TextSystem {
    return &(texts orelse return error.NotStarted);
}

fn fontNamed(name: []const u8) ?gfx.Font {
    for (loaded_fonts.items) |loaded| {
        if (std.mem.eql(u8, loaded.name, name)) return loaded.font;
    }
    return null;
}

/// Sizes are in pixels. A null `font` is the one given to startup, and a null
/// `line_height` is the font's own. `fallback` is the font for the characters
/// that the font has no glyph for. The lines and the baseline stay those of
/// the font.
pub const Style = struct {
    size: f32 = 16,
    font: ?[:0]const u8 = null,
    fallback: ?[:0]const u8 = null,
    line_height: ?f32 = null,
    tracking: f32 = 0,
};

/// `s` laid out for drawing with `Canvas.text`. A positive `width` wraps
/// the text at that width. Null when no font can be found for the style.
/// The layout is only good until the next one is asked for.
pub fn layout(s: []const u8, style: Style, width: f32) ?*gfx.TextLayout {
    const started = system() catch return null;

    var fonts: [2]gfx.Font = undefined;
    var count: usize = 0;
    const named = if (style.font) |name| fontNamed(name) else null;
    const first = if (loaded_fonts.items.len > 0) loaded_fonts.items[0].font else null;
    if (named orelse default_font orelse first) |font| {
        fonts[count] = font;
        count += 1;
    }
    if (style.fallback) |name| {
        if (fontNamed(name)) |font| {
            fonts[count] = font;
            count += 1;
        }
    }

    return started.cached(s, .{
        .fonts = fonts[0..count],
        .size = style.size,
        .line_height = style.line_height,
        .tracking = style.tracking,
        .width = if (width > 0) width else null,
    }, scale);
}

/// A positive `width` wraps the text at that width. The width leaves out the
/// spaces at the end of a line.
pub fn measure(s: []const u8, style: Style, width: f32) Extent {
    const laid = layout(s, style, width) orelse return .{};
    return .{
        // A word longer than the line is not broken.
        .width = if (width > 0) @min(laid.width, width) else laid.width,
        .height = laid.height,
    };
}

/// The distance from the start of `s` to where a character after it would go.
/// Unlike the width that `measure` gives, it counts the spaces at the end.
pub fn advance(s: []const u8, style: Style) f32 {
    if (s.len == 0) return 0;
    const laid = layout(s, style, 0) orelse return 0;
    return laid.caret(s.len).x;
}

/// The position in `s` whose advance is nearest to `x`: a byte offset between
/// two characters.
pub fn indexAt(s: []const u8, style: Style, x: f32) usize {
    const laid = layout(s, style, 0) orelse return 0;
    return laid.indexAt(x, 0);
}
