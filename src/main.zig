const std = @import("std");
const builtin = @import("builtin");
const process = std.process;
const Allocator = std.mem.Allocator;
const mem = std.mem;

pub const Config = @import("Config.zig");
pub const ConfigBuildgen = @import("ConfigBuildgen.zig");
pub const Args = @import("Args.zig");
pub const GlobalOptions = @import("GlobalOptions.zig");

pub const init = @import("cmd_init.zig");
pub const fetch = @import("cmd_fetch.zig");
pub const build = @import("cmd_build.zig");
pub const sync = @import("cmd_sync.zig");
const fatal = std.process.fatal;

pub const std_options: std.Options = .{
    .log_level = .info,
};

const usage =
    \\Usage: zbuild [global_options] [command] [options]
    \\
    \\Commands:
    \\
    \\  init             Initialize a Zig package in the current directory
    \\  fetch            Copy a package into global cache
    \\
    \\  install          Install all artifacts
    \\  uninstall        Uninstall all artifacts
    \\  build            Run `zig build`
    \\  sync             Sync build.zig and build.zig.zon
    \\  build-exe        Build an executable
    \\  build-lib        Build a library
    \\  build-obj        Build an object file
    \\  build-test       Build a test into an executable
    \\  run              Run an executable or run script
    \\  test             Perform unit testing
    \\  fmt              Format source code
    \\
    \\  help             Print this help and exit
    \\  version          Print version number and exit
    \\
    \\Global Options:
    \\
    \\  --zig-exe [path]              Override path to Zig executable
    \\  --global-cache-dir [path]     Override path to global Zig cache directory
    \\  --zig-lib-dir [path]          Override path to Zig library directory
    \\  --zig-std-dir [path]          Override path to Zig standard library directory
    \\  --project-dir [path]          Override path to project directory
    \\  --zbuild-file [path]          Override path to zbuild file
    \\  --no-sync                     Skip automatic synchronization of build.zig and build.zig.zon
    \\
    \\General Options:
    \\
    \\  -h, --help       Print command-specific usage
    \\
;

pub fn main() anyerror!void {
    // Here we use an ArenaAllocator because a build is a short-lived,
    // one shot program. We don't need to waste time freeing memory and finding places to squish
    // bytes into. So we free everything all at once at the very end.
    var gpa = std.heap.DebugAllocator(.{}){};
    const gpa_allocator = gpa.allocator();
    var arena_instance = std.heap.ArenaAllocator.init(gpa_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var args = try Args.initFromProcessArgs(arena);
    _ = args.next();

    return mainArgs(gpa_allocator, arena, &args);
}

fn mainArgs(gpa: Allocator, arena: Allocator, args: *Args) !void {
    const first_arg = args.peek() orelse {
        cmdUsage();
        fatal("expected command argument", .{});
    };

    // commands that shouldn't ever have any side effects
    if (mem.eql(u8, first_arg, "help") or mem.eql(u8, first_arg, "--help") or mem.eql(u8, first_arg, "-h")) {
        cmdUsage();
        return;
    } else if (mem.eql(u8, first_arg, "version")) {
        std.log.info("zig version: {s}", .{builtin.zig_version_string});
        return;
    }

    const global_opts = try GlobalOptions.parseArgs(gpa, args);
    defer global_opts.deinit(gpa);

    const cmd = args.next() orelse {
        cmdUsage();
        fatal("expected command argument", .{});
    };

    if (mem.eql(u8, cmd, "init")) {
        try init.exec(gpa, arena, global_opts);
        return;
    }

    var wip_bundle: std.zig.ErrorBundle.Wip = undefined;
    try wip_bundle.init(gpa);
    const config = Config.parseFromFile(arena, global_opts.zbuild_file, &wip_bundle) catch |err| switch (err) {
        error.FileNotFound => {
            fatal("no zbuild file found", .{});
        },
        error.OutOfMemory => {
            fatal("out of memory", .{});
        },
        else => {
            var error_bundle = try wip_bundle.toOwnedBundle("");
            error_bundle.renderToStdErr(.{ .ttyconf = .escape_codes });
            std.process.exit(1);
        },
    };

    if (mem.eql(u8, cmd, "sync")) {
        try sync.exec(gpa, arena, global_opts, config);
    } else if (mem.eql(u8, cmd, "fetch")) {
        try fetch.exec(
            gpa,
            arena,
            global_opts,
            try fetch.parseArgs(args),
        );
    } else {
        var kind: build.BuildKind = undefined;
        if (mem.eql(u8, cmd, "build")) {
            kind = .build;
        } else if (mem.eql(u8, cmd, "install")) {
            kind = .install;
        } else if (mem.eql(u8, cmd, "uninstall")) {
            kind = .uninstall;
        } else if (mem.eql(u8, cmd, "build-exe")) {
            kind = .build_exe;
        } else if (mem.eql(u8, cmd, "build-lib")) {
            kind = .build_lib;
        } else if (mem.eql(u8, cmd, "build-obj")) {
            kind = .build_obj;
        } else if (mem.eql(u8, cmd, "build-test")) {
            kind = .build_test;
        } else if (mem.eql(u8, cmd, "run")) {
            kind = .run;
        } else if (mem.eql(u8, cmd, "test")) {
            kind = .@"test";
        } else if (mem.eql(u8, cmd, "fmt")) {
            kind = .fmt;
        } else {
            cmdUsage();
            fatal("unknown command: {s}", .{cmd});
        }
        const opts = build.parseArgs(args, kind, config);
        try build.exec(gpa, arena, global_opts, config, opts);
    }
}

fn cmdUsage() void {
    std.log.info("{s}", .{usage});
}
