//! Used to determine the current zig exe, version, and other information.
//! Simply calls `zig env` and parses the output

const std = @import("std");

zig_exe: []const u8,
lib_dir: []const u8,
std_dir: []const u8,
global_cache_dir: []const u8,
version: []const u8,

pub fn deinit(self: @This(), allocator: std.mem.Allocator) void {
    allocator.free(self.zig_exe);
    allocator.free(self.lib_dir);
    allocator.free(self.std_dir);
    allocator.free(self.global_cache_dir);
    allocator.free(self.version);
}

/// Simply calls `zig env` and parses the output
pub fn parse(allocator: std.mem.Allocator) !@This() {
    var env_map = try std.process.getEnvMap(allocator);
    defer env_map.deinit();

    const result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "env" },
        .env_map = &env_map,
    });
    defer allocator.free(result.stdout);
    defer allocator.free(result.stderr);

    if (result.term != .Exited and result.term.Exited != 0) {
        return error.UnexpectedExitCode;
    }

    const env = try std.json.parseFromSlice(@This(), allocator, result.stdout, .{ .ignore_unknown_fields = true });
    defer env.deinit();

    return .{
        .zig_exe = try allocator.dupe(u8, env.value.zig_exe),
        .lib_dir = try allocator.dupe(u8, env.value.lib_dir),
        .std_dir = try allocator.dupe(u8, env.value.std_dir),
        .global_cache_dir = try allocator.dupe(u8, env.value.global_cache_dir),
        .version = try allocator.dupe(u8, env.value.version),
    };
}

test "ZigEnv.parse" {
    const allocator = std.testing.allocator;

    const env = try parse(allocator);
    defer env.deinit(allocator);

    std.debug.print("{s}\n", .{env.zig_exe});
    std.debug.print("{s}\n", .{env.lib_dir});
    std.debug.print("{s}\n", .{env.std_dir});
    std.debug.print("{s}\n", .{env.global_cache_dir});
    std.debug.print("{s}\n", .{env.version});
}
