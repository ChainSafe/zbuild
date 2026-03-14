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
