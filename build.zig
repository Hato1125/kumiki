const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const thorvg = b.dependency("thorvg", .{
        .target = target,
        .optimize = optimize,
    }).artifact("thorvg");

    const sdl = b.dependency("sdl", .{
        .target = target,
        .optimize = optimize,
    }).artifact("SDL3");

    const translate_c = b.addTranslateC(.{
        .root_source_file = b.path("src/c.h"),
        .target = target,
        .optimize = optimize,
    });
    translate_c.addIncludePath(thorvg.getEmittedIncludeTree());
    translate_c.addIncludePath(sdl.getEmittedIncludeTree());

    const katagi = b.addModule("katagi", .{
        .root_source_file = b.path("src/katagi.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    katagi.addImport("c", translate_c.createModule());
    katagi.linkLibrary(thorvg);
    katagi.linkLibrary(sdl);
}
