const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "zsockacc",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const lib = b.addModule("root", .{ .root_source_file = b.path("src/root.zig") });

    {
        const args = .{ .target = target, .optimize = optimize };
        const network = b.dependency("network", args).module("network");
        const zutil = b.dependency("zutil", .{}).module("zutil");
        const zbinutils = b.dependency("zbinutils", .{}).module("binutils");

        exe.root_module.addImport("network", network);
        exe.root_module.addImport("zutil", zutil);
        exe.root_module.addImport("zbinutils", zbinutils);

        lib.addImport("network", network);
        lib.addImport("zutil", zutil);
        lib.addImport("zbinutils", zbinutils);
    }

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);
}
