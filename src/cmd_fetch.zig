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
    switch (opts.save) {
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
        else => {},
    }

    const zbuild_filename = try std.fs.path.join(gpa, &[_][]const u8{ global_opts.project_dir, global_opts.zbuild_file });
    defer gpa.free(zbuild_filename);
    const manifest_dir = try std.fs.cwd().openDir(global_opts.project_dir, .{});
    // if the name is known, we can update the config without loading the manifest
    // we first parse the manifest, run zig fetch, and then compare which dependency updated
    // then we update the config with the new dependency
    var old_manifest = try Manifest.load(gpa, arena, .{ .color = .auto, .dir = manifest_dir, .basename = "build.zig.zon" }) orelse fatal("failed to load manifest", .{});
    defer old_manifest.deinit(gpa);

    try runZigFetch(
        gpa,
        arena,
        .{ .cwd = global_opts.project_dir },
        global_opts.getZigEnv(),
        opts.path_or_url,
        opts.save,
    );

    var new_manifest = try Manifest.load(gpa, arena, .{ .color = .auto, .dir = manifest_dir, .basename = "build.zig.zon" }) orelse fatal("failed to load manifest", .{});
    defer new_manifest.deinit(gpa);

    for (new_manifest.dependencies.keys(), new_manifest.dependencies.values()) |n, new_dep| {
        switch (new_dep.location) {
            .url => |new_url| {
                if (old_manifest.dependencies.get(n)) |old_dep| {
                    if (old_dep.location == .url) {
                        if (mem.eql(u8, new_url, old_dep.location.url)) {
                            continue;
                        }
                    }
                }
            },
            .path => |new_path| {
                if (old_manifest.dependencies.get(n)) |old_dep| {
                    if (old_dep.location == .path) {
                        if (mem.eql(u8, new_path, old_dep.location.path)) {
                            continue;
                        }
                    }
                }
            },
        }
        try updateConfigDependency(
            gpa,
            arena,
            manifest_dir,
            global_opts.zbuild_file,
            n,
            new_dep.location.url,
            new_dep.hash,
        );
        break;
    }
    return cleanExit();
}

// Mostly copied from zig/src/main.zig
// Allows us to update the config file with the new dependency without affecting comments and existing user formatting
fn updateConfigDependency(
    gpa: Allocator,
    arena: Allocator,
    dir: std.fs.Dir,
    zbuild_file: []const u8,
    dep_name: []const u8,
    saved_path_or_url: []const u8,
    package_hash_slice: ?[]const u8,
) !void {
    var manifest = Manifest.load(
        gpa,
        arena,
        .{
            .color = .auto,
            .dir = dir,
            .basename = zbuild_file,
        },
    ) catch |err| {
        fatal("unable to open {s} file: {s}", .{ zbuild_file, @errorName(err) });
    } orelse fatal("{s} file not found", .{zbuild_file});
    defer manifest.deinit(gpa);

    var fixups: std.zig.Ast.Fixups = .{};
    defer fixups.deinit(gpa);

    const new_node_init =
        try std.fmt.allocPrint(arena,
            \\.{{
            \\            .url = "{}",
            \\        }}
        , .{
            std.zig.fmtEscapes(saved_path_or_url),
        });

    const new_node_text = try std.fmt.allocPrint(arena, ".{p_} = {s},\n", .{
        std.zig.fmtId(dep_name), new_node_init,
    });

    const dependencies_init = try std.fmt.allocPrint(arena, ".{{\n        {s}    }}", .{
        new_node_text,
    });

    const dependencies_text = try std.fmt.allocPrint(arena, ".dependencies = {s},\n", .{
        dependencies_init,
    });

    if (manifest.dependencies.get(dep_name)) |dep| {
        const location_replace = try std.fmt.allocPrint(
            arena,
            "\"{}\"",
            .{std.zig.fmtEscapes(saved_path_or_url)},
        );
        try fixups.replace_nodes_with_string.put(gpa, dep.location_node, location_replace);

        if (package_hash_slice) |hash| {
            const hash_replace = try std.fmt.allocPrint(
                arena,
                "\"{}\"",
                .{std.zig.fmtEscapes(hash)},
            );

            try fixups.replace_nodes_with_string.put(gpa, dep.hash_node, hash_replace);
        }
    } else if (manifest.dependencies.count() > 0) {
        // Add fixup for adding another dependency.
        const deps = manifest.dependencies.values();
        const last_dep_node = deps[deps.len - 1].node;
        try fixups.append_string_after_node.put(gpa, last_dep_node, new_node_text);
    } else if (manifest.dependencies_node != 0) {
        // Add fixup for replacing the entire dependencies struct.
        try fixups.replace_nodes_with_string.put(gpa, manifest.dependencies_node, dependencies_init);
    } else {
        // Add fixup for adding dependencies struct.
        try fixups.append_string_after_node.put(gpa, manifest.version_node, dependencies_text);
    }

    var rendered = std.ArrayList(u8).init(gpa);
    defer rendered.deinit();
    try manifest.ast.renderToArrayList(&rendered, fixups);

    dir.writeFile(.{ .sub_path = zbuild_file, .data = rendered.items }) catch |err| {
        fatal("unable to write {s} file: {s}", .{ zbuild_file, @errorName(err) });
    };
}
