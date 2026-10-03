const std = @import("std");
const c = @import("c");

const canvas_zig = @import("canvas.zig");
const Canvas = canvas_zig.Canvas;
const Extent = @import("types.zig").Extent;
const Event = @import("input.zig").Event;
const Scene = @import("scene.zig").Scene;

// The implementation of a Scene in a resizable SDL3 window with OpenGL 3.3.
pub const Window = struct {
    window: *c.SDL_Window,
    gl: c.SDL_GLContext,
    canvas: Canvas,

    // `font` is the TTF or OTF file of the text that names no font, and
    // `fonts` are more files for the text that asks for them by name.
    pub const Options = struct {
        title: [:0]const u8 = "katagi",
        width: u32 = 800,
        height: u32 = 600,
        font: ?[:0]const u8 = null,
        fonts: []const [:0]const u8 = &.{},
    };

    pub fn init(_: std.mem.Allocator, options: Options) !Window {
        if (!c.SDL_Init(c.SDL_INIT_VIDEO | c.SDL_INIT_EVENTS)) return error.SdlInit;
        errdefer c.SDL_Quit();
        try canvas_zig.startup(options.font);
        errdefer canvas_zig.shutdown();
        for (options.fonts) |path| try canvas_zig.addFont(path);

        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 3);
        _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
        const window = c.SDL_CreateWindow(
            options.title,
            @intCast(options.width),
            @intCast(options.height),
            c.SDL_WINDOW_OPENGL | c.SDL_WINDOW_HIGH_PIXEL_DENSITY | c.SDL_WINDOW_RESIZABLE,
        ) orelse return error.CreateWindow;
        errdefer c.SDL_DestroyWindow(window);

        const gl = c.SDL_GL_CreateContext(window) orelse return error.CreateGlContext;
        errdefer _ = c.SDL_GL_DestroyContext(gl);
        _ = c.SDL_GL_MakeCurrent(window, gl);
        _ = c.SDL_GL_SetSwapInterval(1);

        const pixels = pixelSize(window);
        return .{ .window = window, .gl = gl, .canvas = try .init(gl, pixels[0], pixels[1]) };
    }

    pub fn deinit(w: *Window) void {
        w.canvas.deinit();
        _ = c.SDL_GL_DestroyContext(w.gl);
        c.SDL_DestroyWindow(w.window);
        canvas_zig.shutdown();
        c.SDL_Quit();
    }

    // After waiting, null also stands for events the scene does not see,
    // such as a resize, so that the frame is drawn again.
    pub fn next(_: *Window, wait: bool) ?Event {
        var event: c.SDL_Event = undefined;
        var arrived = if (wait) c.SDL_WaitEvent(&event) else c.SDL_PollEvent(&event);
        if (wait and !arrived) @panic("SDL_WaitEvent failed");
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

    pub fn size(w: *Window) Extent {
        var width: c_int = 0;
        var height: c_int = 0;
        _ = c.SDL_GetWindowSize(w.window, &width, &height);
        return .{ .width = @floatFromInt(width), .height = @floatFromInt(height) };
    }

    pub fn now(_: *Window) f64 {
        return @as(f64, @floatFromInt(c.SDL_GetTicksNS())) / std.time.ns_per_s;
    }

    // A minimized window has nothing to draw to.
    pub fn begin(w: *Window) !?*Canvas {
        _ = c.SDL_GL_MakeCurrent(w.window, w.gl);
        const pixels = pixelSize(w.window);
        if (pixels[0] == 0 or pixels[1] == 0) return null;
        try w.canvas.resize(pixels[0], pixels[1]);
        w.canvas.scale = c.SDL_GetWindowPixelDensity(w.window);
        try w.canvas.begin();
        return &w.canvas;
    }

    pub fn end(w: *Window) !void {
        try w.canvas.end();
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
            c.SDL_EVENT_MOUSE_MOTION => .{ .pointer_move = .{ .x = event.motion.x, .y = event.motion.y } },
            c.SDL_EVENT_WINDOW_MOUSE_LEAVE => .pointer_leave,
            c.SDL_EVENT_MOUSE_BUTTON_DOWN, c.SDL_EVENT_MOUSE_BUTTON_UP => .{ .button = .{
                .button = @enumFromInt(event.button.button),
                .down = event.button.down,
                .x = event.button.x,
                .y = event.button.y,
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

// Opens a window showing `root`, a component, and returns when it is closed.
pub fn run(gpa: std.mem.Allocator, options: Window.Options, root: anytype) !void {
    var scene = try Scene(Window, @TypeOf(root)).init(gpa, options, root);
    defer scene.deinit();
    try scene.run();
}
