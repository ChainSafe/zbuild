const std = @import("std");
const Allocator = std.mem.Allocator;

const Config = @import("Config.zig");
const ConfigBuildgen = @import("ConfigBuildgen.zig");

pub const SyncBuildFileOpts = struct {
    out_dir: ?[]const u8 = null,
    build_file: ?[]const u8 = null,
};

const max_bytes_zbuild_file = 16_000;

pub fn syncBuildFile(gpa: Allocator, arena: Allocator, config: Config, opts: SyncBuildFileOpts) !void {
    _ = gpa;
    const build_root_directory = std.fs.cwd();

    const out_dir = if (opts.out_dir) |o| try build_root_directory.openDir(o, .{}) else build_root_directory;
    const out_file = try out_dir.createFile(opts.build_file orelse "build.zig", .{ .truncate = true });
    defer out_file.close();
    const writer = out_file.writer().any();

    var buildgen = ConfigBuildgen.init(arena, config, writer);
    defer buildgen.deinit();

    try buildgen.write();
}
