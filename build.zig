const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const gfx = b.dependency("gfx", .{
        .target = target,
        .optimize = optimize,
    }).module("gfx");

    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    }).artifact("SDL3");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(sdl.getEmittedIncludeTree());

    const kumiki = b.addModule("kumiki", .{
        .root_source_file = b.path("src/kumiki.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    kumiki.addImport("c", translate_c.createModule());
    kumiki.addImport("gfx", gfx);
    kumiki.linkLibrary(sdl);
    // gfx draws with OpenGL ES and leaves the linking to whoever makes the
    // context. The other two read the image files.
    kumiki.linkSystemLibrary("GLESv2", .{});
    kumiki.linkSystemLibrary("libpng", .{});
    kumiki.linkSystemLibrary("libturbojpeg", .{});

    const check = b.addTest(.{ .root_module = kumiki });
    b.default_step.dependOn(&check.step);
}
