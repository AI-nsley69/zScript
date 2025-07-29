const std = @import("std");

const build_zig_zon = @embedFile("build.zig.zon");

// Although this function looks imperative, note that its job is to
// declaratively construct a build graph that will be executed by an external
// runner.
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "zscript",
        .root_module = exe_mod,
    });

    // Zli
    const zli_dep = b.dependency("zli", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("zli", zli_dep.module("zli"));

    const ansi_term_dep = b.dependency("ansi_term", .{ .target = target, .optimize = optimize });
    exe.root_module.addImport("ansi_term", ansi_term_dep.module("ansi_term"));

    // https://renerocks.ai/blog/2025-04-27--version-in-zig/
    var build_conf = std.Build.Step.Options.create(b);
    build_conf.addOption([]const u8, "contents", build_zig_zon);
    exe.root_module.addOptions("build.zig.zon", build_conf);

    const tracy_dep = b.dependency("tracy", .{
        .target = target,
        .optimize = optimize,
        .enable = b.option(bool, "tracy", "Enable profiling with Tracy") orelse false,
        .wait = true,
    });
    exe.root_module.addImport("tracy", tracy_dep.module("tracy"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_module = exe_mod,
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);

    // Similar to creating the run step earlier, this exposes a `test` step to
    // the `zig build --help` menu, providing a way for the user to request
    // running the unit tests.
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
