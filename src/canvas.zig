const std = @import("std");
const c = @import("c");

const Coverage = @import("coverage.zig").Coverage;
const types = @import("types.zig");
const Bounds = types.Bounds;
const Color = types.Color;
const Extent = types.Extent;

// ThorVG takes font sizes in points, while katagi uses pixels.
const points_per_pixel = 0.75;

// From 0 to 100.
const blur_quality = 100;

const gpa = std.heap.c_allocator;

var default_font_buffer: [256]u8 = undefined;
var default_font: ?[:0]const u8 = null;

const LoadedFont = struct {
    name: []const u8,
    path: [:0]const u8,
    // Read from the file once the font is first given a fallback.
    coverage: ?Coverage = null,
};

var loaded_fonts: std.ArrayList(LoadedFont) = .empty;

/// Loads `font` for the text that names no font. An implementation calls this
/// before it measures or draws, and `shutdown` at its end.
pub fn startup(font: ?[:0]const u8) !void {
    if (c.tvg_engine_init(0) != c.TVG_RESULT_SUCCESS) return error.EngineInit;
    errdefer shutdown();
    default_font = null;
    const path = font orelse return;
    try addFont(path);
    default_font = std.fmt.bufPrintZ(&default_font_buffer, "{s}", .{std.fs.path.stem(path)}) catch
        return error.FontNameTooLong;
}

pub fn shutdown() void {
    for (loaded_fonts.items) |font| {
        if (font.coverage) |coverage| coverage.deinit(gpa);
        gpa.free(font.path);
    }
    loaded_fonts.clearAndFree(gpa);
    _ = c.tvg_engine_term();
}

/// Loads a font that text can ask for by name. ThorVG looks fonts up by the
/// file name without its extension.
pub fn addFont(path: [:0]const u8) !void {
    if (c.tvg_font_load(path) != c.TVG_RESULT_SUCCESS) return error.FontLoad;
    const kept = try gpa.dupeZ(u8, path);
    errdefer gpa.free(kept);
    try loaded_fonts.append(gpa, .{
        .name = std.fs.path.stem(kept),
        .path = kept,
    });
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

fn readCoverage(path: [:0]const u8) !Coverage {
    const file = try readFile(path);
    defer gpa.free(file);
    return Coverage.parse(gpa, file);
}

// A font that is not loaded, or whose file cannot be read, is taken to have
// every glyph, so its text never falls back.
fn coverageOf(name: []const u8) Coverage {
    for (loaded_fonts.items) |*font| {
        if (!std.mem.eql(u8, font.name, name)) continue;
        if (font.coverage == null) {
            font.coverage = readCoverage(font.path) catch .{};
        }
        return font.coverage.?;
    }
    return .{};
}

/// Sizes are in pixels. A null `font` is the one given to startup, and a null
/// `line_height` is the font's own. `fallback` is the font for the characters
/// that the font has no glyph for. The lines and the baseline stay those of
/// the font.
pub const TextStyle = struct {
    size: f32 = 16,
    font: ?[:0]const u8 = null,
    fallback: ?[:0]const u8 = null,
    line_height: ?f32 = null,
    tracking: f32 = 0,

    fn falling(style: TextStyle) TextStyle {
        var other = style;
        other.font = style.fallback;
        other.fallback = null;
        return other;
    }
};

// The C API takes NUL-terminated strings, so text is copied here first.
var text_buffer: std.ArrayList(u8) = .empty;

fn terminated(s: []const u8, tail: []const u8) [*:0]const u8 {
    text_buffer.clearRetainingCapacity();
    text_buffer.ensureTotalCapacity(std.heap.c_allocator, s.len + tail.len + 1) catch @panic("out of memory");
    text_buffer.appendSliceAssumeCapacity(s);
    text_buffer.appendSliceAssumeCapacity(tail);
    text_buffer.appendAssumeCapacity(0);
    return @ptrCast(text_buffer.items.ptr);
}

// The distance from the left edge to the right end of the ink. ThorVG gives
// no finite bounds for text without ink, such as spaces alone.
fn inkWidth(text: c.Tvg_Paint) f32 {
    var x: f32 = 0;
    var y: f32 = 0;
    var w: f32 = 0;
    var h: f32 = 0;
    _ = c.tvg_paint_get_aabb(text, &x, &y, &w, &h);
    return if (std.math.isFinite(x + w)) x + w else 0;
}

fn metricsOf(text: c.Tvg_Paint) c.Tvg_Text_Metrics {
    var metrics: c.Tvg_Text_Metrics = .{};
    _ = c.tvg_text_get_text_metrics(text, &metrics);
    return metrics;
}

fn lineAdvance(text: c.Tvg_Paint) f32 {
    return metricsOf(text).advance;
}

// A positive `width` wraps the text at that width. ThorVG only scales the
// advances, so the tracking is spread over the characters in proportion to
// their widths instead of evenly.
fn newText(s: []const u8, style: TextStyle, width: f32) c.Tvg_Paint {
    const text = c.tvg_text_new();
    _ = c.tvg_text_set_font(text, if (style.font orelse default_font) |name| name.ptr else null);
    _ = c.tvg_text_set_size(text, style.size * points_per_pixel);
    _ = c.tvg_text_set_text(text, terminated(s, ""));

    var letter: f32 = 1;
    if (style.tracking != 0 and s.len > 0) {
        const natural = inkWidth(text);
        const count: f32 = @floatFromInt(std.unicode.utf8CountCodepoints(s) catch s.len);
        if (natural > 0) letter = @max(0, 1 + style.tracking * count / natural);
    }
    var line: f32 = 1;
    if (style.line_height) |height| {
        const advance = lineAdvance(text);
        if (advance > 0) line = height / advance;
    }
    _ = c.tvg_text_spacing(text, letter, line);

    if (width > 0) {
        _ = c.tvg_text_layout(text, width, 0);
        _ = c.tvg_text_wrap_mode(text, c.TVG_TEXT_WRAP_SMART);
    }
    return text;
}

/// A positive `width` wraps the text at that width. ThorVG reports stale
/// bounds for an empty string, so its width is not asked for.
pub fn measureText(s: []const u8, style: TextStyle, width: f32) Extent {
    if (Rulers.mixing(s, style)) |rulers| {
        defer rulers.deinit();
        var size: Extent = .{};
        var lines: LineIterator = .{
            .rest = s,
            .width = width,
            .rulers = &rulers,
        };
        while (lines.next()) |line| {
            size.width = @max(size.width, rulers.lineWidth(line));
            size.height += rulers.lineHeight();
        }
        if (width > 0) size.width = @min(size.width, width);
        return size;
    }

    const text = newText(s, style, width);
    defer _ = c.tvg_paint_rel(text);

    const lines: f32 = @floatFromInt(@max(1, c.tvg_text_line_count(text)));
    const height = (style.line_height orelse lineAdvance(text)) * lines;
    if (s.len == 0) return .{ .height = height };

    const natural = inkWidth(text);
    return .{
        .width = if (width > 0) @min(natural, width) else natural,
        .height = height,
    };
}

// Measures how far texts in one style advance. The advance is read off the
// ink of a bar put after the text. ThorVG has metrics for each glyph, but
// once it is asked for those of a glyph without ink, such as a space, it no
// longer draws any text that starts with that glyph.
const Ruler = struct {
    text: c.Tvg_Paint,
    // How far the ink of the bar alone reaches.
    alone: f32,
    tracking: f32,

    const bar = "|";

    fn init(style: TextStyle) Ruler {
        var plain = style;
        plain.tracking = 0;
        const text = newText(bar, plain, 0);
        return .{
            .text = text,
            .alone = inkWidth(text),
            .tracking = style.tracking,
        };
    }

    fn deinit(ruler: Ruler) void {
        _ = c.tvg_paint_rel(ruler.text);
    }

    fn advance(ruler: Ruler, s: []const u8) f32 {
        if (s.len == 0) return 0;
        _ = c.tvg_text_set_text(ruler.text, terminated(s, bar));
        const count: f32 = @floatFromInt(std.unicode.utf8CountCodepoints(s) catch s.len);
        return inkWidth(ruler.text) - ruler.alone + ruler.tracking * count;
    }

    // How far the ink of `s` reaches, which leaves out the spaces at its end.
    fn ink(ruler: Ruler, s: []const u8) f32 {
        if (s.len == 0) return 0;
        _ = c.tvg_text_set_text(ruler.text, terminated(s, ""));
        const natural = inkWidth(ruler.text);
        if (natural == 0) return 0;
        const count: f32 = @floatFromInt(std.unicode.utf8CountCodepoints(s) catch s.len);
        return natural + ruler.tracking * count;
    }
};

// The first code point of `s`, which is not empty, and its length in bytes.
// A byte that starts no code point stands for itself.
fn firstCodePoint(s: []const u8) struct { u21, usize } {
    const length = std.unicode.utf8ByteSequenceLength(s[0]) catch return .{ s[0], 1 };
    if (length > s.len) return .{ s[0], 1 };
    return .{ std.unicode.utf8Decode(s[0..length]) catch return .{ s[0], 1 }, length };
}

// A stretch of text that one font draws.
const Run = struct {
    text: []const u8,
    falls_back: bool,
};

const RunIterator = struct {
    rest: []const u8,
    coverage: Coverage,

    fn next(runs: *RunIterator) ?Run {
        if (runs.rest.len == 0) return null;
        var end: usize = 0;
        var falls_back = false;
        while (end < runs.rest.len) {
            const code_point, const length = firstCodePoint(runs.rest[end..]);
            const lacking = !runs.coverage.has(code_point);
            if (end == 0) falls_back = lacking;
            if (lacking != falls_back) break;
            end += length;
        }
        defer runs.rest = runs.rest[end..];
        return .{ .text = runs.rest[0..end], .falls_back = falls_back };
    }
};

// Measures texts in a style whose characters may fall back to a second font.
const Rulers = struct {
    main: Ruler,
    fallback: ?Ruler = null,
    // Of the main font.
    coverage: Coverage = .{},
    metrics: c.Tvg_Text_Metrics,
    line_height: ?f32,

    fn init(style: TextStyle) Rulers {
        const main: Ruler = .init(style);
        var rulers: Rulers = .{
            .main = main,
            .metrics = metricsOf(main.text),
            .line_height = style.line_height,
        };
        const name = style.font orelse default_font orelse return rulers;
        if (style.fallback == null) return rulers;
        rulers.fallback = .init(style.falling());
        rulers.coverage = coverageOf(name);
        return rulers;
    }

    // The rulers of `style` when some of `s` falls back, and null when ThorVG
    // can lay the whole text out in the one font.
    fn mixing(s: []const u8, style: TextStyle) ?Rulers {
        if (style.fallback == null) return null;
        const rulers: Rulers = .init(style);
        var parts = rulers.runs(s);
        while (parts.next()) |run| if (run.falls_back) return rulers;
        rulers.deinit();
        return null;
    }

    fn deinit(rulers: Rulers) void {
        rulers.main.deinit();
        if (rulers.fallback) |ruler| ruler.deinit();
    }

    fn runs(rulers: Rulers, s: []const u8) RunIterator {
        return .{ .rest = s, .coverage = rulers.coverage };
    }

    fn of(rulers: Rulers, run: Run) Ruler {
        return if (run.falls_back) rulers.fallback.? else rulers.main;
    }

    fn lineHeight(rulers: Rulers) f32 {
        return rulers.line_height orelse rulers.metrics.advance;
    }

    fn advance(rulers: Rulers, s: []const u8) f32 {
        if (rulers.fallback == null) return rulers.main.advance(s);
        var total: f32 = 0;
        var parts = rulers.runs(s);
        while (parts.next()) |run| total += rulers.of(run).advance(run.text);
        return total;
    }

    // The width of a line up to the end of its ink.
    fn lineWidth(rulers: Rulers, line: []const u8) f32 {
        var before: f32 = 0;
        var width: f32 = 0;
        var parts = rulers.runs(line);
        while (parts.next()) |run| {
            const ink = rulers.of(run).ink(run.text);
            if (ink > 0) width = before + ink;
            before += rulers.of(run).advance(run.text);
        }
        return width;
    }
};

// East Asian text has no spaces, so a line may end after any such character.
fn breaksAnywhere(code_point: u21) bool {
    return code_point >= 0x2e80;
}

// Cuts a text into lines. A positive `width` wraps the text at that width:
// between words, and inside a word that is wider than a line of its own.
const LineIterator = struct {
    rest: []const u8,
    width: f32,
    rulers: *const Rulers,
    // A line feed at the very end still opens a line.
    pending: bool = true,

    fn next(lines: *LineIterator) ?[]const u8 {
        if (lines.rest.len == 0 and !lines.pending) return null;
        lines.pending = false;

        const limit = if (lines.width > 0) lines.width else std.math.inf(f32);
        var end: usize = 0;
        var x: f32 = 0;
        while (end < lines.rest.len and lines.rest[end] != '\n') {
            const word = nextWord(lines.rest[end..]);
            const inked = std.mem.trimEnd(u8, word, " ");
            if (x + lines.rulers.advance(inked) <= limit) {
                end += word.len;
                x += lines.rulers.advance(word);
                continue;
            }
            if (end > 0) break;
            while (end < word.len) {
                const length = firstCodePoint(word[end..])[1];
                const advance = lines.rulers.advance(word[end..][0..length]);
                if (end > 0 and x + advance > limit) break;
                end += length;
                x += advance;
            }
            break;
        }

        const line = lines.rest[0..end];
        lines.rest = lines.rest[end..];
        if (lines.rest.len > 0 and lines.rest[0] == '\n') {
            lines.rest = lines.rest[1..];
            lines.pending = true;
        }
        return line;
    }

    // The start of `s` up to where a line may end next: a word with the
    // spaces after it, or one East Asian character.
    fn nextWord(s: []const u8) []const u8 {
        var end: usize = 0;
        var spaces = false;
        while (end < s.len) {
            const code_point, const length = firstCodePoint(s[end..]);
            if (code_point == '\n') break;
            if (breaksAnywhere(code_point)) {
                return s[0..if (end == 0) length else end];
            }
            if (code_point == ' ') spaces = true else if (spaces) break;
            end += length;
        }
        return s[0..end];
    }
};

/// The distance from the start of `s` to where a character after it would go.
/// Unlike the width that measureText gives, it counts the spaces at the end.
pub fn textAdvance(s: []const u8, style: TextStyle) f32 {
    if (s.len == 0) return 0;
    const rulers: Rulers = .init(style);
    defer rulers.deinit();
    return rulers.advance(s);
}

fn isContinuation(byte: u8) bool {
    return byte & 0xc0 == 0x80;
}

/// The position in `s` whose advance is nearest to `x`: a byte offset between
/// two code points. The text is halved until two neighbors are left, since
/// ThorVG only tells how wide a whole text is.
pub fn textIndexAt(s: []const u8, style: TextStyle, x: f32) usize {
    const rulers: Rulers = .init(style);
    defer rulers.deinit();

    var low: usize = 0;
    var low_x: f32 = 0;
    var high = s.len;
    while (true) {
        var middle = low + (high - low) / 2;
        while (middle > low and isContinuation(s[middle])) middle -= 1;
        if (middle == low) {
            middle += 1;
            while (middle < high and isContinuation(s[middle])) middle += 1;
        }
        if (middle >= high) break;
        const middle_x = rulers.advance(s[0..middle]);
        if (middle_x <= x) {
            low = middle;
            low_x = middle_x;
        } else {
            high = middle;
        }
    }
    return if (x - low_x <= rulers.advance(s[0..high]) - x) low else high;
}

/// A PNG or JPG file that is read once and drawn as often as needed. It lives
/// between `startup` and `shutdown`.
pub const Image = struct {
    picture: c.Tvg_Paint,

    pub fn load(path: [:0]const u8) !Image {
        const picture = c.tvg_picture_new();
        _ = c.tvg_paint_ref(picture);
        errdefer _ = c.tvg_paint_unref(picture, true);
        if (c.tvg_picture_load(picture, path) != c.TVG_RESULT_SUCCESS) {
            return error.ImageLoad;
        }
        return .{ .picture = picture };
    }

    pub fn deinit(image: Image) void {
        _ = c.tvg_paint_unref(image.picture, true);
    }

    /// In the pixels of the file.
    pub fn size(image: Image) Extent {
        var size_now: Extent = .{};
        _ = c.tvg_picture_get_size(image.picture, &size_now.width, &size_now.height);
        return size_now;
    }
};

pub const Corners = struct {
    top_left: f32 = 0,
    top_right: f32 = 0,
    bottom_right: f32 = 0,
    bottom_left: f32 = 0,

    pub fn all(radius: f32) Corners {
        return .{
            .top_left = radius,
            .top_right = radius,
            .bottom_right = radius,
            .bottom_left = radius,
        };
    }
};

/// The stroke is centered on the outline.
pub const PathStyle = struct {
    fill: ?Color = null,
    stroke: ?Color = null,
    stroke_width: f32 = 1,
    cap: enum { butt, round, square } = .butt,
    join: enum { miter, round, bevel } = .miter,
};

/// An outline made with Canvas.path and drawn with Canvas.drawPath.
pub const Path = struct {
    shape: c.Tvg_Paint,

    pub fn moveTo(p: Path, x: f32, y: f32) void {
        _ = c.tvg_shape_move_to(p.shape, x, y);
    }

    pub fn lineTo(p: Path, x: f32, y: f32) void {
        _ = c.tvg_shape_line_to(p.shape, x, y);
    }

    pub fn cubicTo(
        p: Path,
        x1: f32,
        y1: f32,
        x2: f32,
        y2: f32,
        x: f32,
        y: f32,
    ) void {
        _ = c.tvg_shape_cubic_to(p.shape, x1, y1, x2, y2, x, y);
    }

    pub fn close(p: Path) void {
        _ = c.tvg_shape_close(p.shape);
    }

    pub fn circle(p: Path, cx: f32, cy: f32, radius: f32) void {
        _ = c.tvg_shape_append_circle(p.shape, cx, cy, radius, radius, true);
    }

    /// Radii too large for the rectangle shrink together. `k` is how far a
    /// control point sits from the end of a quarter circle, as a fraction of
    /// the radius.
    pub fn rect(p: Path, r: Bounds, corners: Corners) void {
        const w = @max(0, r.w);
        const h = @max(0, r.h);
        const across = @max(corners.top_left + corners.top_right, corners.bottom_left + corners.bottom_right);
        const down = @max(corners.top_left + corners.bottom_left, corners.top_right + corners.bottom_right);
        var fit: f32 = 1;
        if (across > w) fit = @min(fit, w / across);
        if (down > h) fit = @min(fit, h / down);
        const top_left = corners.top_left * fit;
        const top_right = corners.top_right * fit;
        const bottom_right = corners.bottom_right * fit;
        const bottom_left = corners.bottom_left * fit;

        const k = 1 - 0.5522848;
        const left = r.x;
        const top = r.y;
        const right = r.x + w;
        const bottom = r.y + h;

        p.moveTo(left + top_left, top);
        p.lineTo(right - top_right, top);
        p.cubicTo(right - top_right * k, top, right, top + top_right * k, right, top + top_right);
        p.lineTo(right, bottom - bottom_right);
        p.cubicTo(right, bottom - bottom_right * k, right - bottom_right * k, bottom, right - bottom_right, bottom);
        p.lineTo(left + bottom_left, bottom);
        p.cubicTo(left + bottom_left * k, bottom, left, bottom - bottom_left * k, left, bottom - bottom_left);
        p.lineTo(left, top + top_left);
        p.cubicTo(left, top + top_left * k, left + top_left * k, top, left + top_left, top);
        p.close();
    }
};

pub const Canvas = struct {
    tvg: c.Tvg_Canvas,
    gl: ?*anyopaque,
    width: u32,
    height: u32,
    scale: f32 = 1,
    layers: [32]c.Tvg_Paint = undefined,
    depth: usize = 0,
    /// The time of the frame being drawn, and when the next one is due at
    /// the latest. The scene sets both and reads `again` after the drawing.
    now: f64 = 0,
    again: f64 = std.math.inf(f64),

    pub fn init(gl_context: ?*anyopaque, width: u32, height: u32) !Canvas {
        if (gl_context == null) return error.InvalidTarget;
        const tvg = c.tvg_glcanvas_create(c.TVG_ENGINE_OPTION_DEFAULT) orelse return error.CanvasCreate;
        errdefer _ = c.tvg_canvas_destroy(tvg);

        var canvas: Canvas = .{
            .tvg = tvg,
            .gl = gl_context,
            .width = 0,
            .height = 0,
        };
        try canvas.resize(width, height);
        return canvas;
    }

    pub fn deinit(canvas: *Canvas) void {
        _ = c.tvg_canvas_destroy(canvas.tvg);
    }

    pub fn resize(canvas: *Canvas, width: u32, height: u32) !void {
        if (width == 0 or height == 0) return error.InvalidTarget;
        if (width == canvas.width and height == canvas.height) return;

        _ = c.tvg_canvas_sync(canvas.tvg);
        const format = c.TVG_COLORSPACE_ABGR8888S;
        const result = c.tvg_glcanvas_set_target(canvas.tvg, null, null, canvas.gl, 0, width, height, format);
        if (result != c.TVG_RESULT_SUCCESS) return error.Retarget;
        canvas.width = width;
        canvas.height = height;
    }

    pub fn begin(canvas: *Canvas) !void {
        canvas.depth = 0;
        if (c.tvg_canvas_remove(canvas.tvg, null) != c.TVG_RESULT_SUCCESS) {
            return error.Draw;
        }
    }

    pub fn end(canvas: *Canvas) !void {
        if (c.tvg_canvas_update(canvas.tvg) != c.TVG_RESULT_SUCCESS) {
            return error.Draw;
        }
        if (c.tvg_canvas_draw(canvas.tvg, true) != c.TVG_RESULT_SUCCESS) {
            return error.Draw;
        }
        if (c.tvg_canvas_sync(canvas.tvg) != c.TVG_RESULT_SUCCESS) {
            return error.Draw;
        }
    }

    pub fn fillRect(
        canvas: *Canvas,
        r: Bounds,
        radius: f32,
        color: Color,
    ) void {
        if (color.a == 0) return;
        const shape = canvas.roundedRect(r, radius);
        _ = c.tvg_shape_set_fill_color(shape, color.r, color.g, color.b, color.a);
        canvas.add(shape);
    }

    /// The stroke is kept inside `r`.
    pub fn strokeRect(
        canvas: *Canvas,
        r: Bounds,
        radius: f32,
        width: f32,
        color: Color,
    ) void {
        if (color.a == 0 or width <= 0) return;
        const half = width / 2;
        const inner: Bounds = .{
            .x = r.x + half,
            .y = r.y + half,
            .w = r.w - width,
            .h = r.h - width,
        };
        const shape = canvas.roundedRect(inner, @max(0, radius - half));
        _ = c.tvg_shape_set_stroke_width(shape, width * canvas.scale);
        _ = c.tvg_shape_set_stroke_color(shape, color.r, color.g, color.b, color.a);
        canvas.add(shape);
    }

    pub fn fillCircle(
        canvas: *Canvas,
        cx: f32,
        cy: f32,
        radius: f32,
        color: Color,
    ) void {
        if (color.a == 0) return;
        const circle = canvas.path();
        circle.circle(cx, cy, radius);
        _ = c.tvg_shape_set_fill_color(circle.shape, color.r, color.g, color.b, color.a);
        canvas.add(circle.shape);
    }

    /// Draws with (x, y) at the top left of the first line. A positive
    /// `width` wraps the text at that width. The glyphs sit in the middle of
    /// a line taller or shorter than the font's own.
    pub fn text(
        canvas: *Canvas,
        x: f32,
        y: f32,
        width: f32,
        s: []const u8,
        style: TextStyle,
        color: Color,
    ) void {
        if (s.len == 0 or color.a == 0) return;
        if (Rulers.mixing(s, style)) |rulers| {
            defer rulers.deinit();
            canvas.mixedText(x, y, width, s, style, color, &rulers);
            return;
        }
        const paint = newText(s, style, width);
        const lead = if (style.line_height) |height| (height - lineAdvance(paint)) / 2 else 0;
        canvas.addText(paint, x, y + lead, color);
    }

    // Draws every run of every line as a text of its own, with the fallback
    // font on the baseline of the main one.
    fn mixedText(
        canvas: *Canvas,
        x: f32,
        y: f32,
        width: f32,
        s: []const u8,
        style: TextStyle,
        color: Color,
        rulers: *const Rulers,
    ) void {
        var main = style;
        main.line_height = null;
        const fallback = main.falling();

        var top = y + (rulers.lineHeight() - rulers.metrics.advance) / 2;
        var lines: LineIterator = .{
            .rest = s,
            .width = width,
            .rulers = rulers,
        };
        while (lines.next()) |line| : (top += rulers.lineHeight()) {
            var left = x;
            var runs = rulers.runs(line);
            while (runs.next()) |run| {
                const paint = newText(run.text, if (run.falls_back) fallback else main, 0);
                const raise = rulers.metrics.ascent - metricsOf(paint).ascent;
                canvas.addText(paint, left, top + raise, color);
                left += rulers.of(run).advance(run.text);
            }
        }
    }

    fn addText(
        canvas: *Canvas,
        paint: c.Tvg_Paint,
        x: f32,
        y: f32,
        color: Color,
    ) void {
        _ = c.tvg_text_set_color(paint, color.r, color.g, color.b);
        _ = c.tvg_paint_set_opacity(paint, color.a);
        _ = c.tvg_paint_translate(paint, x * canvas.scale, y * canvas.scale);
        _ = c.tvg_paint_scale(paint, canvas.scale);
        canvas.add(paint);
    }

    /// Draws the whole image stretched over `r`. Every drawing is a duplicate,
    /// which shares the pixels of the image.
    pub fn image(canvas: *Canvas, source: Image, r: Bounds) void {
        const natural = source.size();
        if (natural.width <= 0 or natural.height <= 0) return;
        const picture = c.tvg_paint_duplicate(source.picture);
        _ = c.tvg_paint_set_transform(picture, &.{
            .e11 = r.w / natural.width * canvas.scale,
            .e12 = 0,
            .e13 = r.x * canvas.scale,
            .e21 = 0,
            .e22 = r.h / natural.height * canvas.scale,
            .e23 = r.y * canvas.scale,
            .e31 = 0,
            .e32 = 0,
            .e33 = 1,
        });
        canvas.add(picture);
    }

    /// An empty outline in the units of the other drawing calls.
    pub fn path(canvas: *Canvas) Path {
        const shape = c.tvg_shape_new();
        _ = c.tvg_paint_scale(shape, canvas.scale);
        return .{ .shape = shape };
    }

    /// Takes the path, which must not be used afterwards. ThorVG applies the
    /// scale of the shape to the stroke width.
    pub fn drawPath(canvas: *Canvas, p: Path, style: PathStyle) void {
        const fill = style.fill orelse Color.transparent;
        const stroke = style.stroke orelse Color.transparent;
        const stroked = stroke.a > 0 and style.stroke_width > 0;
        if (fill.a == 0 and !stroked) {
            _ = c.tvg_paint_rel(p.shape);
            return;
        }

        _ = c.tvg_shape_set_fill_color(p.shape, fill.r, fill.g, fill.b, fill.a);
        if (stroked) {
            _ = c.tvg_shape_set_stroke_width(p.shape, style.stroke_width);
            _ = c.tvg_shape_set_stroke_color(p.shape, stroke.r, stroke.g, stroke.b, stroke.a);
            _ = c.tvg_shape_set_stroke_cap(p.shape, switch (style.cap) {
                .butt => c.TVG_STROKE_CAP_BUTT,
                .round => c.TVG_STROKE_CAP_ROUND,
                .square => c.TVG_STROKE_CAP_SQUARE,
            });
            _ = c.tvg_shape_set_stroke_join(p.shape, switch (style.join) {
                .miter => c.TVG_STROKE_JOIN_MITER,
                .round => c.TVG_STROKE_JOIN_ROUND,
                .bevel => c.TVG_STROKE_JOIN_BEVEL,
            });
        }
        canvas.add(p.shape);
    }

    /// Collects the following drawing into a layer for popLayer or popBlurred.
    pub fn pushLayer(canvas: *Canvas) void {
        if (canvas.depth == canvas.layers.len) {
            @panic("layers nested too deeply");
        }
        canvas.layers[canvas.depth] = c.tvg_scene_new();
        canvas.depth += 1;
    }

    pub fn popLayer(
        canvas: *Canvas,
        clip: ?Bounds,
        radius: f32,
        opacity: u8,
    ) void {
        canvas.depth -= 1;
        const layer = canvas.layers[canvas.depth];
        if (clip) |r| {
            _ = c.tvg_paint_set_clip(layer, canvas.roundedRect(r, radius));
        }
        if (opacity < 255) _ = c.tvg_paint_set_opacity(layer, opacity);
        canvas.add(layer);
    }

    /// `sigma` is the standard deviation of the Gaussian. The layer itself is
    /// not scaled, so ThorVG takes it in pixels.
    pub fn popBlurred(canvas: *Canvas, sigma: f32) void {
        canvas.depth -= 1;
        const layer = canvas.layers[canvas.depth];
        if (sigma > 0) {
            _ = c.tvg_scene_add_effect_gaussian_blur(layer, sigma * canvas.scale, 0, 0, blur_quality);
        }
        canvas.add(layer);
    }

    fn roundedRect(canvas: *Canvas, r: Bounds, radius: f32) c.Tvg_Paint {
        const shape = canvas.path().shape;
        const corner = @min(radius, @min(r.w, r.h) / 2);
        _ = c.tvg_shape_append_rect(shape, r.x, r.y, @max(0, r.w), @max(0, r.h), corner, corner, true);
        return shape;
    }

    fn add(canvas: *Canvas, paint: c.Tvg_Paint) void {
        if (canvas.depth > 0) {
            _ = c.tvg_scene_add(canvas.layers[canvas.depth - 1], paint);
        } else {
            _ = c.tvg_canvas_add(canvas.tvg, paint);
        }
    }
};
