const std = @import("std");
const GlobalOptions = @import("GlobalOptions.zig");
const Args = @import("Args.zig");
const Config = @import("Config.zig");
const Manifest = @import("Manifest.zig");
const runZigFetch = @import("run_zig.zig").runZigFetch;
const Save = @import("run_zig.zig").ZigCmd.Fetch.Save;
const mem = std.mem;
const Allocator = mem.Allocator;
const cleanExit = std.process.cleanExit;

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
    config: *Config,
    opts: Opts,
) !void {
    const name = switch (opts.save) {
        .no => {
            // just run zig fetch, no need to update the config
            try runZigFetch(
                gpa,
                arena,
                .{ .cwd = global_opts.project_dir },
                global_opts.getZigEnv(),
                opts.path_or_url,
                opts.save,
            );
            return cleanExit();
        },
        .yes => |name| name,
        .exact => |name| name,
    };

    const zbuild_filename = try std.fs.path.join(gpa, &[_][]const u8{ global_opts.project_dir, global_opts.zbuild_file });
    defer gpa.free(zbuild_filename);
    const manifest_dir = try std.fs.cwd().openDir(global_opts.project_dir, .{});
    // if the name is known, we can update the config without loading the manifest
    // otherwise, we first parse the manifest, run zig fetch, and then compare which dependency updated
    // so we can determine the name
    if (name) |n| {
        try runZigFetch(
            gpa,
            arena,
            .{ .cwd = global_opts.project_dir },
            global_opts.getZigEnv(),
            opts.path_or_url,
            opts.save,
        );
        try config.addDependency(gpa, n, .{ .value = .{ .url = .{ .url = opts.path_or_url } } });
        try config.save(zbuild_filename);
    } else {
        var old_manifest = try Manifest.load(gpa, arena, .{ .color = .auto, .dir = manifest_dir }) orelse fatal("failed to load manifest", .{});
        defer old_manifest.deinit(gpa);

        try runZigFetch(
            gpa,
            arena,
            .{ .cwd = global_opts.project_dir },
            global_opts.getZigEnv(),
            opts.path_or_url,
            opts.save,
        );

        var new_manifest = try Manifest.load(gpa, arena, .{ .color = .auto, .dir = manifest_dir }) orelse fatal("failed to load manifest", .{});
        defer new_manifest.deinit(gpa);

        for (new_manifest.dependencies.keys(), new_manifest.dependencies.values()) |n, new_dep| {
            const config_dep = blk: switch (new_dep.location) {
                .url => |new_url| {
                    if (old_manifest.dependencies.get(n)) |old_dep| {
                        if (old_dep.location == .url) {
                            if (mem.eql(u8, new_url, old_dep.location.url)) {
                                continue;
                            }
                        }
                    }
                    break :blk Config.Dependency{ .value = .{ .url = .{ .url = new_url } } };
                },
                .path => |new_path| {
                    if (old_manifest.dependencies.get(n)) |old_dep| {
                        if (old_dep.location == .path) {
                            if (mem.eql(u8, new_path, old_dep.location.path)) {
                                continue;
                            }
                        }
                    }
                    break :blk Config.Dependency{ .value = .{ .path = .{ .path = new_path } } };
                },
            };
            try config.addDependency(gpa, n, config_dep);
            try config.save(zbuild_filename);
            break;
        }
    }
    return cleanExit();
}

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}
