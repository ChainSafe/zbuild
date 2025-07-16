const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = @import("Config.zig");
const ConfigBuildgen = @import("ConfigBuildgen.zig");
const GlobalOptions = @import("GlobalOptions.zig");
const runZigFmt = @import("run_zig.zig").runZigFmt;

pub const SyncBuildFileOpts = struct {
    out_dir: ?[]const u8 = null,
    build_file: ?[]const u8 = null,
};

const max_bytes_zbuild_file = 16_000;

pub fn syncBuildFile(gpa: Allocator, arena: Allocator, config: Config, global_opts: GlobalOptions, opts: SyncBuildFileOpts) !void {
    const build_root_directory = std.fs.cwd();

    const out_dir = if (opts.out_dir) |o| try build_root_directory.openDir(o, .{}) else build_root_directory;
    const out_file = try out_dir.createFile(opts.build_file orelse "build.zig", .{ .truncate = true });
    errdefer out_file.close();
    const writer = out_file.writer().any();

    var buildgen = ConfigBuildgen.init(arena, config, writer);
    defer buildgen.deinit();

    try buildgen.write();

    // after writing, close the file and format it with `zig fmt`, which modifies files in-place
    out_file.close();
    try runZigFmt(
        gpa,
        arena,
        .{ .cwd = global_opts.project_dir, .stderr_behavior = .Ignore, .stdout_behavior = .Ignore },
        global_opts.getZigEnv(),
        &[_][]const u8{opts.build_file orelse "build.zig"},
    );
}
