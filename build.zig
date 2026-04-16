const std = @import("std");
const build_runner = @import("src/build_runner.zig");

// Re-export the zbuild API so dependents can use @import("zbuild").configureBuild
pub const configureBuild = build_runner.configureBuild;
pub const Options = build_runner.Options;
pub const BuildResult = build_runner.BuildResult;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zbuild library module (for use by zbuild-powered projects)
    const zbuild_module = b.addModule("zbuild", .{
        .root_source_file = b.path("src/build_runner.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Tests
    const tls_run_test = b.step("test", "Run all tests");

    const test_zbuild = b.addTest(.{
        .name = "zbuild",
        .root_module = zbuild_module,
        .filters = b.option([]const []const u8, "zbuild.filters", "zbuild test filters") orelse &.{},
    });
    const run_test_zbuild = b.addRunArtifact(test_zbuild);
    const tls_test_zbuild = b.step("test:zbuild", "Run the zbuild tests");
    tls_test_zbuild.dependOn(&run_test_zbuild.step);
    tls_run_test.dependOn(&run_test_zbuild.step);
}
