const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const GlobalOptions = @import("GlobalOptions.zig");
const Config = @import("Config.zig");
const fatal = @import("fatal.zig").fatal;
const syncBuildFile = @import("sync_build_file.zig").syncBuildFile;
const syncManifest = @import("sync_manifest.zig").syncManifest;

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config) !void {
    if (global_opts.no_sync) {
        fatal("--no-sync is incompatible with the sync command", .{});
    }
    try syncBuildFile(gpa, arena, config, .{ .out_dir = global_opts.project_dir });
    try syncManifest(gpa, arena, global_opts, config, .{ .out_dir = global_opts.project_dir });
}
