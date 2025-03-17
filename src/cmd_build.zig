const std = @import("std");
const mem = std.mem;
const Allocator = mem.Allocator;

const Config = @import("Config.zig");
const Args = @import("Args.zig");
const GlobalOptions = @import("GlobalOptions.zig");
const sync = @import("cmd_sync.zig");
const runZigBuild = @import("run_zig.zig").runZigBuild;
const fatal = @import("fatal.zig").fatal;

/// Different kinds of zig build commands
pub const BuildKind = enum {
    build,
    install,
    uninstall,

    build_exe,
    build_lib,
    build_obj,
    build_test,
    run,

    @"test",
    fmt,
};

pub const BuildOpts = struct {
    kind: BuildKind,
    cmd: ?[]const u8 = null,
    args: []const []const u8,
    stderr_behavior: ?std.process.Child.StdIo = .Inherit,
    stdout_behavior: ?std.process.Child.StdIo = .Inherit,
};

fn usage(kind: BuildKind) void {
    _ = kind;
}

fn list(kind: BuildKind, config: Config) void {
    _ = kind;
    _ = config;
}

pub fn parseArgs(args: *Args, kind: BuildKind, config: Config) BuildOpts {
    switch (kind) {
        .build, .install, .uninstall => return .{ .kind = kind, .args = args.rest() },
        else => {},
    }
    const arg = args.peek() orelse return .{ .kind = kind, .args = args.rest() };
    if (mem.eql(u8, arg, "--help") or mem.eql(u8, arg, "-h")) {
        usage(kind);
        return std.process.exit(0);
    } else if (mem.eql(u8, arg, "--list") or mem.eql(u8, arg, "-l")) {
        list(kind, config);
        return std.process.exit(0);
    } else if (mem.startsWith(u8, arg, "-")) {
        if (kind == .build_exe or kind == .build_lib or kind == .build_obj or kind == .build_test) {
            fatal("expected additional argument", .{});
        }
        return .{ .kind = kind, .args = args.rest() };
    } else {
        return .{ .kind = kind, .cmd = args.next() orelse fatal("expected command argument", .{}), .args = args.rest() };
    }
}

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config, opts: BuildOpts) !void {
    if (!global_opts.no_sync) {
        try sync.exec(gpa, arena, global_opts, config);
    }
    var step_name: [512]u8 = undefined;
    const step = switch (opts.kind) {
        .build => null,
        .install => "install",
        .uninstall => "uninstall",

        .build_exe => try std.fmt.bufPrint(&step_name, "build-exe:{s}", .{opts.cmd orelse unreachable}),
        .build_lib => try std.fmt.bufPrint(&step_name, "build-lib:{s}", .{opts.cmd orelse unreachable}),
        .build_obj => try std.fmt.bufPrint(&step_name, "build-obj:{s}", .{opts.cmd orelse unreachable}),
        .build_test => try std.fmt.bufPrint(&step_name, "build-test:{s}", .{opts.cmd orelse unreachable}),
        .run => try std.fmt.bufPrint(&step_name, "run:{s}", .{opts.cmd orelse unreachable}),

        .@"test" => if (opts.cmd) |c|
            try std.fmt.bufPrint(&step_name, "test:{s}", .{c})
        else
            "test",
        .fmt => if (opts.cmd) |c|
            try std.fmt.bufPrint(&step_name, "fmt:{s}", .{c})
        else
            "fmt",
    };

    try runZigBuild(
        gpa,
        arena,
        .{
            .cwd = global_opts.project_dir,
            .stderr_behavior = opts.stderr_behavior orelse .Inherit,
            .stdout_behavior = opts.stdout_behavior orelse .Inherit,
        },
        global_opts.getZigEnv(),
        step,
        opts.args,
    );
}
