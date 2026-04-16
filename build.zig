const std = @import("std");
const build_runner = @import("src/build_runner.zig");

// Re-export the zbuild API so dependents can use @import("zbuild").configureBuild
pub const configureBuild = build_runner.configureBuild;
pub const Options = build_runner.Options;
pub const BuildResult = build_runner.BuildResult;

const FixtureCommand = struct {
    name: []const u8,
    cwd: []const u8,
    build_args: []const []const u8 = &.{},
    expect_exit: u8 = 0,
    stdout_match: ?[]const u8 = null,
    stderr_match: ?[]const u8 = null,
};

fn addFixtureCommand(b: *std.Build, aggregate: *std.Build.Step, command: FixtureCommand) void {
    const run = b.addSystemCommand(&.{ b.graph.zig_exe, "build" });
    run.addArgs(command.build_args);
    run.setCwd(b.path(command.cwd));
    run.expectExitCode(command.expect_exit);
    if (command.stdout_match) |expected| run.expectStdOutMatch(expected);
    if (command.stderr_match) |expected| run.expectStdErrMatch(expected);

    const step = b.step(
        b.fmt("test:fixture:{s}", .{command.name}),
        b.fmt("Run fixture check {s}", .{command.name}),
    );
    step.dependOn(&run.step);
    aggregate.dependOn(&run.step);
}

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

    const tls_test_fixtures = b.step("test:fixtures", "Run fixture integration tests");
    tls_run_test.dependOn(tls_test_fixtures);

    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "examples-full-build",
        .cwd = "examples/full",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "examples-full-info",
        .cwd = "examples/full",
        .build_args = &.{"info"},
        .stdout_match = "full_example v1.0.0",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "manual-interop-build",
        .cwd = "test/fixtures/manual_interop",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "manual-interop-run",
        .cwd = "test/fixtures/manual_interop",
        .build_args = &.{"run:myapp"},
        .stderr_match = "manual manual",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "manual-interop-cmd",
        .cwd = "test/fixtures/manual_interop",
        .build_args = &.{"cmd:demo"},
        .stdout_match = "manual interop ok",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "undeclared-external-module",
        .cwd = "test/fixtures/undeclared_external_module",
        .expect_exit = 2,
        .stderr_match = "import references unknown target 'shared'",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "undeclared-external-step",
        .cwd = "test/fixtures/undeclared_external_step",
        .expect_exit = 2,
        .stderr_match = "depends_on references unknown step 'gen:prep'",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "manual-module-collision",
        .cwd = "test/fixtures/manual_module_collision",
        .expect_exit = 1,
        .stderr_match = "named module 'core' collides with an existing module registered before configureBuild",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "manual-step-collision",
        .cwd = "test/fixtures/manual_step_collision",
        .expect_exit = 1,
        .stderr_match = "run command step 'cmd:demo' collides with an existing top-level step registered before configureBuild",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "inline-name-collision",
        .cwd = "test/fixtures/inline_name_collision",
        .expect_exit = 2,
        .stderr_match = "collides with named module",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "dependency-bad-import",
        .cwd = "test/fixtures/dependency_bad_import",
        .expect_exit = 1,
        .stderr_match = "could not resolve module 'missing' from dependency 'dep_pkg'",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "dependency-bad-lazy-path",
        .cwd = "test/fixtures/dependency_bad_lazy_path",
        .expect_exit = 1,
        .stderr_match = "could not resolve named lazy path 'missing' from dependency 'dep_pkg'",
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "stdlib-passthrough-library",
        .cwd = "test/fixtures/stdlib_passthrough",
        .build_args = &.{"build-lib:mylib"},
    });
    addFixtureCommand(b, tls_test_fixtures, .{
        .name = "stdlib-passthrough-test",
        .cwd = "test/fixtures/stdlib_passthrough",
        .build_args = &.{"build-test:unit"},
    });
}
