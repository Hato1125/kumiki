const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Both are built from source, so nothing is taken from the system.
    const thorvg = b.dependency("thorvg", .{ .target = target, .optimize = optimize }).artifact("thorvg");
    const sdl = b.dependency("sdl", .{ .target = target, .optimize = optimize }).artifact("SDL3");

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

    const test_step = b.step("test", "Run the tests");
    const anim = b.createModule(.{ .root_source_file = b.path("src/anime.zig") });
    for ([_][]const u8{ "scene", "anime" }) |name| {
        const tests = b.addTest(.{
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("tests/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "katagi", .module = katagi },
                    .{ .name = "anim", .module = anim },
                },
            }),
        });
        const run_tests = b.addRunArtifact(tests);
        // The tests load the font from assets/.
        run_tests.setCwd(b.path("."));
        test_step.dependOn(&run_tests.step);
    }

    for ([_][]const u8{ "counter", "todo", "animation", "demo", "input" }) |name| {
        const exe = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("examples/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
                .imports = &.{.{ .name = "katagi", .module = katagi }},
            }),
        });
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        // The examples load the font from assets/.
        run.setCwd(b.path("."));
        b.step(name, b.fmt("Run examples/{s}.zig", .{name})).dependOn(&run.step);
    }
}
