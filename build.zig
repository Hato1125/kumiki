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

    // Wuffs reads the image files. It is optimized whatever the rest is
    // built as: unoptimized, it takes several times as long to decode.
    kumiki.addIncludePath(b.dependency("wuffs", .{}).path("release/c"));
    kumiki.addCSourceFile(.{
        .file = b.path("src/image.c"),
        .flags = &.{ "-O2", "-fno-sanitize=undefined" },
    });

    const check = b.addTest(.{ .root_module = kumiki });
    b.default_step.dependOn(&check.step);
}
