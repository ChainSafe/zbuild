const std = @import("std");

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
    }
}

fn validateZigBuild(allocator: std.mem.Allocator) !void {
    var child = std.process.Child.init(&[_][]const u8{ "zig", "build", "--help" }, allocator);
    child.cwd = cwd;
    child.stderr_behavior = .Pipe;
    child.stdout_behavior = .Pipe;

    try child.spawn();
    switch (try child.wait()) {
        .Exited => |code| if (code == 0) return,
        else => {},
    }

    return error.UnexpectedExitCode;
}

fn testGenerate(allocator: std.mem.Allocator, should_cleanup: bool, opts: zbuild.GenerateOpts) !void {
    errdefer maybeCleanup(should_cleanup);
    defer maybeCleanup(should_cleanup);

    var a = std.heap.ArenaAllocator.init(allocator);
    defer a.deinit();
    const alloc = a.allocator();

    try zbuild.generate(alloc, opts);
    try validateZigBuild(alloc);
}

test "generate valid build.zig" {
    const allocator = std.testing.allocator;

    for (test_cases) |test_case| {
        const zbuild_file = try std.fs.path.join(allocator, &[_][]const u8{ cwd, test_case });
        defer allocator.free(zbuild_file);

        try testGenerate(allocator, remove_build_file, .{ .zbuild_file = zbuild_file, .out_dir = cwd });
    }
}
