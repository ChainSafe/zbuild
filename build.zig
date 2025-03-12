// This file is generated by zbuild. Do not edit manually.

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module_zbuild = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.modules.put(b.dupe("zbuild"), module_zbuild) catch @panic("OOM");

    const exe_zbuild = b.addExecutable(.{
        .name = "zbuild",
        .root_module = module_zbuild,
    });

    const install_exe_zbuild = b.addInstallArtifact(exe_zbuild, .{});
    const install_tls_exe_zbuild = b.step("build-exe:zbuild", "Install the zbuild executable");
    install_tls_exe_zbuild.dependOn(&install_exe_zbuild.step);
    b.getInstallStep().dependOn(&install_exe_zbuild.step);

    const run_exe_zbuild = b.addRunArtifact(exe_zbuild);
    if (b.args) |args| run_exe_zbuild.addArgs(args);
    const run_tls_exe_zbuild = b.step("run:zbuild", "Run the zbuild executable");
    run_tls_exe_zbuild.dependOn(&run_exe_zbuild.step);

    const run_tls_test = b.step("test", "Run all tests");

    const test_zbuild = b.addTest(.{
        .name = "zbuild",
        .root_module = module_zbuild,
        .filters = &[_][]const u8{  },
    });
    const install_test_zbuild = b.addInstallArtifact(test_zbuild, .{});
    const install_tls_test_zbuild = b.step("build-test:zbuild", "Install the zbuild test");
    install_tls_test_zbuild.dependOn(&install_test_zbuild.step);

    const run_test_zbuild = b.addRunArtifact(test_zbuild);
    const run_tls_test_zbuild = b.step("test:zbuild", "Run the zbuild test");
    run_tls_test_zbuild.dependOn(&run_test_zbuild.step);
    run_tls_test.dependOn(&run_test_zbuild.step);

    const module_generate = b.createModule(.{
        .root_source_file = b.path("test/generate.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.modules.put(b.dupe("generate"), module_generate) catch @panic("OOM");

    const test_generate = b.addTest(.{
        .name = "generate",
        .root_module = module_generate,
        .filters = &[_][]const u8{  },
    });
    const install_test_generate = b.addInstallArtifact(test_generate, .{});
    const install_tls_test_generate = b.step("build-test:generate", "Install the generate test");
    install_tls_test_generate.dependOn(&install_test_generate.step);

    const run_test_generate = b.addRunArtifact(test_generate);
    const run_tls_test_generate = b.step("test:generate", "Run the generate test");
    run_tls_test_generate.dependOn(&run_test_generate.step);
    run_tls_test.dependOn(&run_test_generate.step);

    const run_tls_fmt = b.step("fmt", "Run all fmts");

    const fmt_all = b.addFmt(.{
        .paths = &[_][]const u8{ "src" },
        .exclude_paths = &.{},
        .check = false,
    });

    const run_tls_fmt_all = b.step("fmt:all", "Run the all fmt");
    run_tls_fmt_all.dependOn(&fmt_all.step);
    run_tls_fmt.dependOn(&fmt_all.step);

    module_generate.addImport("zbuild", b.modules.get("zbuild") orelse @panic("missing import zbuild"));

}
