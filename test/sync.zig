const std = @import("std");
const Allocator = std.mem.Allocator;

const zbuild = @import("zbuild");

const cwd = "test";

const test_cases = &[_][]const u8{
    "fixtures/basic1.build.zig.zon",
    "fixtures/basic2.build.zig.zon",
    "fixtures/basic3.build.zig.zon",
    "fixtures/basic4.build.zig.zon",
    "fixtures/basic5.build.zig.zon",
    "fixtures/basic6.build.zig.zon",
};

fn cleanup() void {
    const dir = std.fs.cwd().openDir(cwd, .{}) catch return;
    dir.deleteFile("build.zig") catch {};
}

/// Test that each fixture can be parsed and that sync writes a valid build.zig
fn testSync(gpa: Allocator, arena: Allocator, global_opts: zbuild.GlobalOptions) !void {
    defer cleanup();

    // Phase 1: Verify the config parses without error
    const config = try zbuild.Config.parseFromFile(arena, global_opts.zbuild_file, null);

    // Phase 2: Run sync to generate build.zig
    try zbuild.sync.exec(gpa, arena, global_opts, config);

    // Phase 3: Verify build.zig was written with the static template
    var opened_dir: ?std.fs.Dir = null;
    defer if (opened_dir) |*d| d.close();

    const dir = if (global_opts.project_dir.len > 0 and !std.mem.eql(u8, global_opts.project_dir, ".")) blk: {
        opened_dir = try std.fs.cwd().openDir(global_opts.project_dir, .{});
        break :blk opened_dir.?;
    } else std.fs.cwd();

    const build_zig = try dir.readFileAlloc(gpa, "build.zig", 4096);
    defer gpa.free(build_zig);

    // Verify it contains the zbuild import
    try std.testing.expect(std.mem.indexOf(u8, build_zig, "zbuild.configureBuild") != null);
}

test "zbuild sync generates static build.zig" {
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

        try testSync(allocator, arena, global_opts);
    }
}
