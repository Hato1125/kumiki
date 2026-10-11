const std = @import("std");
const c = @import("c");

const gfx = @import("gfx");

const image_zig = @import("image.zig");
const text_zig = @import("text.zig");
const types = @import("types.zig");
const Extent = types.Extent;
const Event = @import("input.zig").Event;
const Scene = @import("scene.zig").Scene;

/// The implementation of a Scene in a resizable SDL3 window with OpenGL ES
/// 3.0.
pub const Window = struct {
    window: *c.SDL_Window,
    gl: c.SDL_GLContext,
    // On the heap, because the images remember which canvas holds them.
    canvas: *gfx.Canvas,

    /// `font` is the TTF or OTF file of the text that names no font, and
    /// `fonts` are more files for the text that asks for them by name.
    pub const Options = struct {
        title: [:0]const u8 = "kumiki",
        width: u32 = 800,
        height: u32 = 600,
        min: Extent = .{},
        max: Extent = .{},
        font: ?[:0]const u8 = null,
        fonts: []const [:0]const u8 = &.{},
    };

    pub fn init(allocator: std.mem.Allocator, options: Options) !Window {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) {
            return error.SdlInit;
        }
        errdefer c.SDL_Quit();
        try text_zig.startup(options.font);
        errdefer text_zig.shutdown();
        for (options.fonts) |path| try text_zig.addFont(path);

        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 0);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_ES);
        const window = c.SDL_CreateWindow(
            options.title,
            @intCast(options.width),
            @intCast(options.height),
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE,
        ) orelse return error.CreateWindow;
        errdefer c.SDL_DestroyWindow(window);

        _ = c.SDL_SetWindowMinimumSize(
            window,
            std.math.lossyCast(c_int, options.min.width),
            std.math.lossyCast(c_int, options.min.height),
        );
        _ = c.SDL_SetWindowMaximumSize(
            window,
            std.math.lossyCast(c_int, options.max.width),
            std.math.lossyCast(c_int, options.max.height),
        );

        const gl = c.SDL_GL_CreateContext(window) orelse return error.CreateGlContext;
        errdefer _ = c.SDL_GL_DestroyContext(gl);
        _ = c.SDL_GL_MakeCurrent(window, gl);
        _ = c.SDL_GL_SetSwapInterval(1);

        const canvas = try allocator.create(gfx.Canvas);
        errdefer allocator.destroy(canvas);
        canvas.* = try .init(allocator, .{
            .loader = c.SDL_GL_GetProcAddress,
            .texts = try text_zig.system(),
        });
        return .{
            .window = window,
            .gl = gl,
            .canvas = canvas,
        };
    }

    pub fn deinit(w: *Window) void {
        const allocator = w.canvas.allocator;
        image_zig.release();
        w.canvas.deinit();
        allocator.destroy(w.canvas);
        _ = c.SDL_GL_DestroyContext(w.gl);
        c.SDL_DestroyWindow(w.window);
        image_zig.shutdown();
        text_zig.shutdown();
        c.SDL_Quit();
    }

    /// After waiting, null also stands for events the scene does not see,
    /// such as a resize, so that the frame is drawn again.
    pub fn next(_: *Window, wait: f64) ?Event {
        var event: c.SDL_Event = undefined;
        var arrived = if (wait <= 0)
            c.SDL_PollEvent(&event)
        else if (std.math.isInf(wait))
            c.SDL_WaitEvent(&event)
        else
            c.SDL_WaitEventTimeout(&event, std.math.lossyCast(i32, @ceil(wait * std.time.ms_per_s)));
        if (std.math.isInf(wait) and !arrived) @panic("SDL_WaitEvent failed");
        while (arrived) : (arrived = c.SDL_PollEvent(&event)) {
            if (convert(&event)) |converted| return converted;
        }
        return null;
    }

    pub fn wake(_: *Window) void {
        var event = std.mem.zeroes(c.SDL_Event);
        event.type = c.SDL_EVENT_USER;
        _ = c.SDL_PushEvent(&event);
    }

    /// Shows the candidates of an input method near `area`. Stopping the
    /// input ends a composition on most systems, and clearing it on the rest.
    pub fn input(w: *Window, area: ?types.Bounds) void {
        const at = area orelse {
            _ = c.SDL_ClearComposition(w.window);
            _ = c.SDL_StopTextInput(w.window);
            return;
        };
        const rect: c.SDL_Rect = .{
            .x = std.math.lossyCast(c_int, at.x),
            .y = std.math.lossyCast(c_int, at.y),
            .w = std.math.lossyCast(c_int, at.w),
            .h = std.math.lossyCast(c_int, at.h),
        };
        _ = c.SDL_SetTextInputArea(w.window, &rect, 0);
        _ = c.SDL_StartTextInput(w.window);
    }

    pub fn paste(_: *Window, into: std.mem.Allocator) ?[]const u8 {
        const text = c.SDL_GetClipboardText() orelse return null;
        defer c.SDL_free(text);
        const held = std.mem.span(text);
        if (held.len == 0) return null;
        return into.dupe(u8, held) catch @panic("out of memory");
    }

    // SDL takes a NUL-terminated string.
    pub fn copy(_: *Window, text: []const u8) bool {
        const terminated = std.heap.c_allocator.dupeZ(u8, text) catch @panic("out of memory");
        defer std.heap.c_allocator.free(terminated);
        return c.SDL_SetClipboardText(terminated);
    }

    pub fn size(w: *Window) Extent {
        var width: c_int = 0;
        var height: c_int = 0;
        _ = c.SDL_GetWindowSize(w.window, &width, &height);
        return .{
            .width = @floatFromInt(width),
            .height = @floatFromInt(height),
        };
    }

    pub fn now(_: *Window) f64 {
        return @as(f64, @floatFromInt(c.SDL_GetTicksNS())) / std.time.ns_per_s;
    }

    /// A minimized window has nothing to draw to.
    pub fn begin(w: *Window) !?*gfx.Canvas {
        _ = c.SDL_GL_MakeCurrent(w.window, w.gl);
        const pixels = pixelSize(w.window);
        if (pixels[0] == 0 or pixels[1] == 0) return null;
        const scale = c.SDL_GetWindowPixelDensity(w.window);
        text_zig.setScale(scale);
        w.canvas.begin(.{
            .width = pixels[0],
            .height = pixels[1],
            .scale = scale,
            .background = .transparent,
        });
        return w.canvas;
    }

    pub fn end(w: *Window) !void {
        w.canvas.end();
        _ = c.SDL_GL_SwapWindow(w.window);
    }

    fn pixelSize(window: *c.SDL_Window) [2]u32 {
        var width: c_int = 0;
        var height: c_int = 0;
        _ = c.SDL_GetWindowSizeInPixels(window, &width, &height);
        return .{ @intCast(@max(0, width)), @intCast(@max(0, height)) };
    }

    fn convert(event: *const c.SDL_Event) ?Event {
        return switch (event.type) {
            c.SDL_EVENT_QUIT, c.SDL_EVENT_WINDOW_CLOSE_REQUESTED => .close,
            c.SDL_EVENT_MOUSE_MOTION => .{ .pointer_move = .{
                .x = event.motion.x,
                .y = event.motion.y,
            } },
            c.SDL_EVENT_WINDOW_MOUSE_LEAVE => .pointer_leave,
            c.SDL_EVENT_WINDOW_FOCUS_GAINED => .{ .active = true },
            c.SDL_EVENT_WINDOW_FOCUS_LOST => .{ .active = false },
            c.SDL_EVENT_WINDOW_EXPOSED, c.SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED => .redraw,
            c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => .{ .button = .{
                .button = @enumFromInt(event.button.button),
                .down = event.button.down,
                .x = event.button.x,
                .y = event.button.y,
                .clicks = event.button.clicks,
                .mod = c.SDL_GetModState(),
            } },
            c.SDL_EVENT_MOUSE_WHEEL => .{ .wheel = .{
                .x = event.wheel.x,
                .y = event.wheel.y,
                .at = .{ .x = event.wheel.mouse_x, .y = event.wheel.mouse_y },
                .ticks_x = event.wheel.integer_x,
                .ticks_y = event.wheel.integer_y,
                .flipped = event.wheel.direction == c.SDL_MOUSEWHEEL_FLIPPED,
                .mod = c.SDL_GetModState(),
            } },
            c.SDL_EVENT_DROP_FILE, c.SDL_EVENT_DROP_TEXT => .{ .drop = .{
                .kind = if (event.type == c.SDL_EVENT_DROP_FILE) .file else .text,
                .data = std.mem.span(event.drop.data),
                .x = event.drop.x,
                .y = event.drop.y,
            } },
            c.SDL_EVENT_TEXT_INPUT => .{ .text = .{
                .text = std.mem.span(event.text.text),
            } },
            c.SDL_EVENT_TEXT_EDITING => .{ .text = .{
                .text = std.mem.span(event.edit.text),
                .composing = true,
                .marked = marked(std.mem.span(event.edit.text), event.edit.start, event.edit.length),
            } },
            c.SDL_EVENT_KEY_DOWN, c.SDL_EVENT_KEY_UP => .{ .key = .{
                .key = event.key.key,
                .mod = event.key.mod,
                .down = event.key.down,
                .repeat = event.key.repeat,
            } },
            else => null,
        };
    }
};

// SDL counts the marked part of a composition in characters, from `start`
// over `length` of them, and gives -1 for what it does not know.
fn marked(text: []const u8, start: i32, length: i32) ?types.Range {
    if (start < 0) return null;
    var range: types.Range = .{ .start = text.len, .end = text.len };
    var characters: i32 = 0;
    for (text, 0..) |byte, at| {
        if (byte & 0xc0 == 0x80) continue;
        if (characters == start) range.start = at;
        if (characters == start + @max(0, length)) {
            range.end = at;
            break;
        }
        characters += 1;
    }
    return range;
}

/// Opens a window showing `root`, a component, and returns when it is closed.
pub fn run(
    gpa: std.mem.Allocator,
    options: Window.Options,
    root: anytype,
) !void {
    var scene = try Scene(Window, @TypeOf(root)).init(gpa, options, root);
    defer scene.deinit();
    try scene.run();
}
