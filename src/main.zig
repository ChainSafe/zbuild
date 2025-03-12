const std = @import("std");
const builtin = @import("builtin");
const process = std.process;
const Allocator = std.mem.Allocator;
const mem = std.mem;

pub const Config = @import("Config.zig");
pub const ConfigBuildgen = @import("ConfigBuildgen.zig");
pub const generate = @import("generate.zig").generate;
pub const GenerateOpts = @import("generate.zig").GenerateOpts;

const usage =
    \\Usage: zbuild [command] [options]
    \\
    \\Commands:
    \\
    \\  init             Initialize a Zig package in the current directory
    \\  fetch            Copy a package into global cache
    \\
    \\  install          Install all artifacts
    \\  uninstall        Uninstall all artifacts
    \\  build-exe        Build an executable
    \\  build-lib        Build a library
    \\  build-obj        Build an object file
    \\  build-test       Build a test into an executable
    \\  run              Run an executable or run script
    \\  test             Perform unit testing
    \\  fmt              Format source code
    \\
    \\  build            Run `zig build`
    \\  generate         Create a build.zig from zbuild.json 
    \\
    \\  help             Print this help and exit
    \\  version          Print version number and exit
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage
    \\
;

pub fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    process.exit(1);
}

pub fn main() anyerror!void {
    // Here we use an ArenaAllocator because a build is a short-lived,
    // one shot program. We don't need to waste time freeing memory and finding places to squish
    // bytes into. So we free everything all at once at the very end.
    var gpa = std.heap.DebugAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    var arena_instance = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    const args = try process.argsAlloc(arena);

    return mainArgs(arena, args);
}

fn mainArgs(arena: Allocator, args: []const []const u8) !void {
    if (args.len <= 1) {
        cmdUsage();
        fatal("expected command argument", .{});
    }

    const cmd = args[1];
    const cmd_args = args[2..];

    if (mem.eql(u8, cmd, "init")) {
        fatal("not implemented", .{});
        return;
    } else if (mem.eql(u8, cmd, "fetch")) {
        fatal("not implemented", .{});
        return;
    } else if (mem.eql(u8, cmd, "help") or mem.eql(u8, cmd, "--help") or mem.eql(u8, cmd, "-h")) {
        cmdUsage();
        return;
    } else if (mem.eql(u8, cmd, "version")) {
        std.log.info("zig version: {s}", .{builtin.zig_version_string});
        return;
    } else if (mem.eql(u8, cmd, "generate")) {
        try cmdGenerate(arena, cmd_args);
        return;
    }

    // All other commands require an up-to-date zbuild.json file
    try cmdGenerate(arena, cmd_args);

    if (mem.eql(u8, cmd, "install")) {
        try runZigBuild(arena, "install", cmd_args);
    } else if (mem.eql(u8, cmd, "uninstall")) {
        try runZigBuild(arena, "uninstall", cmd_args);
    } else if (mem.eql(u8, cmd, "build-exe")) {
        try runZbuildCommand(arena, "build-exe", cmd_args, .{ .subcommand_required = true });
    } else if (mem.eql(u8, cmd, "build-lib")) {
        try runZbuildCommand(arena, "build-lib", cmd_args, .{ .subcommand_required = true });
    } else if (mem.eql(u8, cmd, "build-obj")) {
        try runZbuildCommand(arena, "build-obj", cmd_args, .{ .subcommand_required = true });
    } else if (mem.eql(u8, cmd, "build-test")) {
        try runZbuildCommand(arena, "build-test", cmd_args, .{ .subcommand_required = true });
    } else if (mem.eql(u8, cmd, "run")) {
        try runZbuildCommand(arena, "run", cmd_args, .{ .subcommand_required = true });
    } else if (mem.eql(u8, cmd, "test")) {
        try runZbuildCommand(arena, "test", cmd_args, .{ .subcommand_required = false });
    } else if (mem.eql(u8, cmd, "fmt")) {
        try runZbuildCommand(arena, "fmt", cmd_args, .{ .subcommand_required = false });
    } else if (mem.eql(u8, cmd, "build")) {
        try runZigBuild(arena, null, cmd_args);
    } else {
        cmdUsage();
        fatal("invalid command argument: {s}", .{cmd});
    }
}

fn cmdGenerate(arena: Allocator, args: []const []const u8) !void {
    _ = args;

    try generate(arena, .{});
}

fn runZigBuild(arena: Allocator, step: ?[]const u8, args: []const []const u8) !void {
    var argv = std.ArrayList([]const u8).init(arena);
    try argv.append("zig");
    try argv.append("build");
    if (step) |s| {
        try argv.append(s);
    }
    try argv.appendSlice(args);

    var env_map = try process.getEnvMap(arena);
    const result = std.process.execve(
        arena,
        argv.items,
        &env_map,
    );
    _ = @intFromError(result);
}

fn cmdUsage() void {
    std.log.info("{s}", .{usage});
}

fn cmdHelp(arena: Allocator, cmd: []const u8, action: []const u8) !void {
    _ = arena;
    _ = cmd;
    _ = action;
    // try runZigBuild(
    //     arena,
    //     cmd,
    //     &.{action},
    // );
}

const ZbuildOpts = struct {
    subcommand_required: bool = true,
};

/// args[0] is the "subcommand"
fn runZbuildCommand(arena: Allocator, cmd: []const u8, args: []const []const u8, comptime opts: ZbuildOpts) !void {
    if (args.len < 1) {
        if (opts.subcommand_required) {
            try cmdHelp(arena, cmd, "help");
            fatal("expected additional argument", .{});
        } else {
            try runZigBuild(
                arena,
                cmd,
                &.{},
            );
        }
    }
    const first = args[0];
    const rest = args[1..];

    if (mem.eql(u8, first, "help") or mem.eql(u8, first, "--help") or mem.eql(u8, first, "-h")) {
        return cmdHelp(arena, cmd, "help");
    } else if (mem.eql(u8, first, "list") or mem.eql(u8, first, "--list") or mem.eql(u8, first, "-l")) {
        return cmdHelp(arena, cmd, "list");
    } else if (mem.startsWith(u8, first, "-")) {
        if (opts.subcommand_required) {
            try cmdHelp(arena, cmd, "list");
            fatal("expected additional argument", .{});
        } else {
            try runZigBuild(
                arena,
                cmd,
                args,
            );
        }
    } else {
        try runZigBuild(
            arena,
            try std.fmt.allocPrint(arena, "{s}:{s}", .{ cmd, first }),
            rest,
        );
    }
}
