const std = @import("std");
const Config = @import("Config.zig");
const ConfigBuildgen = @import("ConfigBuildgen.zig");

pub const GenerateOpts = struct {
    zbuild_file: ?[]const u8 = null,
    out_dir: ?[]const u8 = null,
    build_file: ?[]const u8 = null,
};

const max_bytes_zbuild_file = 16_000;

pub fn generate(arena: std.mem.Allocator, opts: GenerateOpts) !void {
    const zbuild_file = opts.zbuild_file orelse "zbuild.json";
    const build_root_directory = std.fs.cwd();
    const config_file = try build_root_directory.openFile(zbuild_file, .{ .mode = .read_only });
    const config_json = try config_file.readToEndAlloc(arena, max_bytes_zbuild_file);
    const config = try std.json.parseFromSlice(Config, arena, config_json, .{});
    defer config.deinit();

    const out_dir = if (opts.out_dir) |o| try build_root_directory.openDir(o, .{}) else build_root_directory;
    const out_file = try out_dir.createFile(opts.build_file orelse "build.zig", .{ .truncate = true });
    const writer = out_file.writer().any();

    var buildgen = ConfigBuildgen.init(arena, config.value, writer);
    defer buildgen.deinit();

    try buildgen.write();
}
