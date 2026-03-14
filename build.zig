const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zbuild library module (for use by zbuild-powered projects)
    const zbuild_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.modules.put(b.dupe("zbuild"), zbuild_module) catch @panic("OOM");

    // zbuild executable
    const exe = b.addExecutable(.{
        .name = "zbuild",
        .root_module = zbuild_module,
    });
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run:zbuild", "Run the zbuild executable");
    run_step.dependOn(&run_exe.step);

    // Tests
    const tls_run_test = b.step("test", "Run all tests");

    // zbuild unit tests
    const test_zbuild = b.addTest(.{
        .name = "zbuild",
        .root_module = zbuild_module,
        .filters = b.option([]const []const u8, "zbuild.filters", "zbuild test filters") orelse &.{},
    });
    const run_test_zbuild = b.addRunArtifact(test_zbuild);
    const tls_test_zbuild = b.step("test:zbuild", "Run the zbuild test");
    tls_test_zbuild.dependOn(&run_test_zbuild.step);
    tls_run_test.dependOn(&run_test_zbuild.step);

    // sync integration test
    const sync_module = b.createModule(.{
        .root_source_file = b.path("test/sync.zig"),
        .target = target,
        .optimize = optimize,
    });
    sync_module.addImport("zbuild", zbuild_module);

    const test_sync = b.addTest(.{
        .name = "sync",
        .root_module = sync_module,
        .filters = b.option([]const []const u8, "sync.filters", "sync test filters") orelse &.{},
    });
    const run_test_sync = b.addRunArtifact(test_sync);
    const tls_test_sync = b.step("test:sync", "Run the sync test");
    tls_test_sync.dependOn(&run_test_sync.step);
    tls_run_test.dependOn(&run_test_sync.step);
}
