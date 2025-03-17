const std = @import("std");
const Allocator = std.mem.Allocator;

const zbuild = @import("zbuild");

/// set to false to help debug the generated build.zig file
const remove_build_file = true;

const cwd = "test";

const test_cases = &[_][]const u8{
    "fixtures/basic1.zbuild.json",
    "fixtures/basic2.zbuild.json",
    "fixtures/basic3.zbuild.json",
    "fixtures/basic4.zbuild.json",
    "fixtures/basic5.zbuild.json",
    "fixtures/basic6.zbuild.json",
};

fn maybeCleanup(should_cleanup: bool) void {
    if (should_cleanup) {
        const dir = std.fs.cwd().openDir(cwd, .{}) catch return;
        dir.deleteFile("build.zig") catch return;
        dir.deleteFile("build.zig.zon") catch return;
    }
}

/// - Load the zbuild file
/// - Generate the build and manifest files
/// - Run `zig build --help`
fn testSync(gpa: Allocator, arena: Allocator, should_cleanup: bool, global_opts: zbuild.GlobalOptions) !void {
    defer maybeCleanup(should_cleanup);

    const config = try zbuild.Config.load(arena, global_opts.zbuild_file);

    try zbuild.build.exec(
        gpa,
        arena,
        global_opts,
        config,
        .{
            .kind = .build,
            .args = &[1][]const u8{"--help"},
            .stderr_behavior = .Ignore,
            .stdout_behavior = .Ignore,
        },
    );
}

test "zbuild build --help" {
    const allocator = std.testing.allocator;

    for (test_cases) |test_case| {
        var arena_alloc = std.heap.ArenaAllocator.init(allocator);
        defer arena_alloc.deinit();
        const arena = arena_alloc.allocator();

        const zbuild_file = try std.fs.path.join(allocator, &[_][]const u8{ cwd, test_case });
        defer allocator.free(zbuild_file);

        var args = try zbuild.Args.initFromString(
            arena,
            try std.fmt.allocPrint(
                arena,
                "--project-dir {s} --zbuild-file {s}",
                .{ cwd, zbuild_file },
            ),
        );
        const global_opts = try zbuild.GlobalOptions.parseArgs(allocator, &args);
        defer global_opts.deinit(allocator);

        try testSync(allocator, arena, remove_build_file, global_opts);
    }
}
