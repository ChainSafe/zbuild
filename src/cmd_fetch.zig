const std = @import("std");
const GlobalOptions = @import("GlobalOptions.zig");
const Args = @import("Args.zig");
const runZigFetch = @import("run_zig.zig").runZigFetch;
const Save = @import("run_zig.zig").ZigCmd.Fetch.Save;
const mem = std.mem;
const Allocator = mem.Allocator;
const cleanExit = std.process.cleanExit;
const fatal = std.process.fatal;

const usage_fetch =
    \\Usage: zbuild fetch [options] <url>
    \\Usage: zbuild fetch [options] <path>
    \\
    \\    Copy a package into the global cache and print its hash.
    \\    <url> must point to one of the following:
    \\      - A git+http / git+https server for the package
    \\      - A tarball file (with or without compression) containing
    \\        package source
    \\      - A git bundle file containing package source
    \\
    \\Examples:
    \\
    \\  zbuild fetch --save git+https://example.com/andrewrk/fun-example-tool.git
    \\  zbuild fetch --save https://example.com/andrewrk/fun-example-tool/archive/refs/heads/master.tar.gz
    \\
    \\Options:
    \\  -h, --help                    Print this help and exit
    \\  --global-cache-dir [path]     Override path to global Zig cache directory
    \\  --debug-hash                  Print verbose hash information to stdout
    \\  --save                        Add the fetched package to build.zig.zon
    \\  --save=[name]                 Add the fetched package to build.zig.zon as name
    \\  --save-exact                  Add the fetched package to build.zig.zon, storing the URL verbatim
    \\  --save-exact=[name]           Add the fetched package to build.zig.zon as name, storing the URL verbatim
    \\
;

pub const Opts = struct {
    save: Save = .no,
    debug_hash: bool = false,
    global_cache_dir: ?[]const u8 = null,
    path_or_url: []const u8,
};

pub fn parseArgs(args: *Args) !Opts {
    var opts: Opts = .{ .path_or_url = undefined };
    var opt_path_or_url: ?[]const u8 = null;
    while (args.next()) |arg| {
        if (mem.startsWith(u8, arg, "-")) {
            if (mem.eql(u8, arg, "-h") or mem.eql(u8, arg, "--help")) {
                const stdout = std.io.getStdOut().writer();
                try stdout.writeAll(usage_fetch);
                return std.process.exit(0);
            } else if (mem.eql(u8, arg, "--global-cache-dir")) {
                const value = args.next() orelse fatal("expected argument after '{s}'", .{arg});
                opts.global_cache_dir = value;
            } else if (mem.eql(u8, arg, "--debug-hash")) {
                opts.debug_hash = true;
            } else if (mem.eql(u8, arg, "--save")) {
                opts.save = .{ .yes = null };
            } else if (mem.startsWith(u8, arg, "--save=")) {
                opts.save = .{ .yes = arg["--save=".len..] };
            } else if (mem.eql(u8, arg, "--save-exact")) {
                opts.save = .{ .exact = null };
            } else if (mem.startsWith(u8, arg, "--save-exact=")) {
                opts.save = .{ .exact = arg["--save-exact=".len..] };
            } else {
                fatal("unrecognized parameter: '{s}'", .{arg});
            }
        } else if (opt_path_or_url != null) {
            fatal("unexpected extra parameter: '{s}'", .{arg});
        } else {
            opt_path_or_url = arg;
        }
    }
    opts.path_or_url = opt_path_or_url orelse fatal("missing url or path parameter", .{});
    return opts;
}

pub fn exec(
    gpa: Allocator,
    arena: Allocator,
    global_opts: GlobalOptions,
    opts: Opts,
) !void {
    try runZigFetch(
        gpa,
        arena,
        .{ .cwd = global_opts.project_dir },
        global_opts.getZigEnv(),
        opts.path_or_url,
        opts.save,
    );
    if (opts.save == .no) {
        return cleanExit();
    }
}
