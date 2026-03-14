const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;
const GlobalOptions = @import("GlobalOptions.zig");
const Config = @import("Config.zig");
const syncBuildFile = @import("sync_build_file.zig").syncBuildFile;

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config) !void {
    if (global_opts.no_sync) {
        fatal("--no-sync is incompatible with the sync command", .{});
    }
    try syncBuildFile(gpa, arena, config, global_opts, .{ .out_dir = global_opts.project_dir });
}
