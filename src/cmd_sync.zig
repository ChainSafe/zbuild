const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;
const GlobalOptions = @import("GlobalOptions.zig");
const Config = @import("Config.zig");

const static_build_zig =
    \\const std = @import("std");
    \\const zbuild = @import("zbuild");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    zbuild.configureBuild(b) catch |err| {
    \\        std.log.err("zbuild: {}", .{err});
    \\    };
    \\}
    \\
;

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config) !void {
    _ = gpa;
    _ = arena;
    _ = config;
    if (global_opts.no_sync) {
        fatal("--no-sync is incompatible with the sync command", .{});
    }

    var opened_dir: ?std.fs.Dir = null;
    defer if (opened_dir) |*d| d.close();

    const dir = if (global_opts.project_dir.len > 0 and !mem.eql(u8, global_opts.project_dir, ".")) blk: {
        opened_dir = try std.fs.cwd().openDir(global_opts.project_dir, .{});
        break :blk opened_dir.?;
    } else std.fs.cwd();

    dir.writeFile(.{
        .sub_path = "build.zig",
        .data = static_build_zig,
    }) catch |err| {
        fatal("failed to write build.zig: {s}", .{@errorName(err)});
    };
}
