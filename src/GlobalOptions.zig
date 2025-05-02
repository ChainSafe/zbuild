//! Collects options from the environment, `zig env`, and command line arguments.

const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const Args = @import("Args.zig");
const ZigEnv = @import("ZigEnv.zig");
const fatal = std.process.fatal;

const GlobalOptions = @This();

zig_exe: []const u8,
lib_dir: []const u8,
std_dir: []const u8,
global_cache_dir: []const u8,
version: []const u8,

project_dir: []const u8,
zbuild_file: []const u8,
no_sync: bool,

const GlobalArgs = enum {
    zig_exe,
    lib_dir,
    std_dir,
    global_cache_dir,
    project_dir,
    zbuild_file,
    no_sync,
};

pub fn deinit(self: GlobalOptions, allocator: Allocator) void {
    allocator.free(self.zig_exe);
    allocator.free(self.lib_dir);
    allocator.free(self.std_dir);
    allocator.free(self.global_cache_dir);
    allocator.free(self.version);
    allocator.free(self.project_dir);
    allocator.free(self.zbuild_file);
}

pub fn parseArgs(allocator: Allocator, args: *Args) !GlobalOptions {
    const zig_env = try ZigEnv.parse(allocator);

    var opts = GlobalOptions{
        .zig_exe = zig_env.zig_exe,
        .lib_dir = zig_env.lib_dir,
        .std_dir = zig_env.std_dir,
        .global_cache_dir = zig_env.global_cache_dir,
        .version = zig_env.version,
        .project_dir = try allocator.dupe(u8, "."),
        .zbuild_file = try allocator.dupe(u8, "zbuild.zon"),
        .no_sync = false,
    };

    iter: while (args.peek()) |arg| {
        if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
            return opts;
        }

        const arg_type = if (mem.eql(u8, arg, "--zig-exe"))
            GlobalArgs.zig_exe
        else if (mem.eql(u8, arg, "--global-cache-dir"))
            GlobalArgs.global_cache_dir
        else if (mem.eql(u8, arg, "--zig-lib-dir"))
            GlobalArgs.lib_dir
        else if (mem.eql(u8, arg, "--zig-std-dir"))
            GlobalArgs.std_dir
        else if (mem.eql(u8, arg, "--project-dir"))
            GlobalArgs.project_dir
        else if (mem.eql(u8, arg, "--zbuild-file"))
            GlobalArgs.zbuild_file
        else if (mem.eql(u8, arg, "--no-sync")) {
            opts.no_sync = true;
            continue;
        } else {
            break :iter;
        };

        _ = args.next();
        const arg_next = args.next() orelse fatal("expected argument after '{s}'", .{arg});
        const arg_value = try allocator.dupe(u8, arg_next);
        switch (arg_type) {
            .zig_exe => {
                allocator.free(opts.zig_exe);
                opts.zig_exe = arg_value;
            },
            .global_cache_dir => {
                allocator.free(opts.global_cache_dir);
                opts.global_cache_dir = arg_value;
            },
            .lib_dir => {
                allocator.free(opts.lib_dir);
                opts.lib_dir = arg_value;
            },
            .std_dir => {
                allocator.free(opts.std_dir);
                opts.std_dir = arg_value;
            },
            .project_dir => {
                allocator.free(opts.project_dir);
                opts.project_dir = arg_value;
            },
            .zbuild_file => {
                allocator.free(opts.zbuild_file);
                opts.zbuild_file = arg_value;
            },
            else => unreachable,
        }
    }

    return opts;
}

pub fn getZigEnv(self: GlobalOptions) ZigEnv {
    return .{
        .zig_exe = self.zig_exe,
        .lib_dir = self.lib_dir,
        .std_dir = self.std_dir,
        .global_cache_dir = self.global_cache_dir,
        .version = self.version,
    };
}
