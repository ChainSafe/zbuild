const std = @import("std");
const builtin = @import("builtin");
const Manifest = @import("Manifest.zig");
const GlobalOptions = @import("GlobalOptions.zig");
const strTupleLiteral = @import("ConfigBuildgen.zig").strTupleLiteral;
const fatal = @import("fatal.zig").fatal;
const runZigFetch = @import("run_zig.zig").runZigFetch;

const mem = std.mem;
const Allocator = mem.Allocator;
const Ast = std.zig.Ast;
const Color = std.zig.Color;

pub const SyncManifestOpts = struct {
    out_dir: ?[]const u8 = null,
};

pub fn syncManifest(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config, opts: SyncManifestOpts) !void {
    // naive strategy for now
    // fetch existing manifest (if any)
    // write new manifest based on config (except for dependencies, which get copied over from existing manifest)
    // if any dependencies are different or added, call zig fetch on them

    const build_root_directory = if (opts.out_dir) |manifest_dir|
        try std.fs.cwd().openDir(manifest_dir, .{})
    else
        std.fs.cwd();
    var manifest = try loadManifest(gpa, arena, .{
        .dir = build_root_directory,
        .color = .auto,
    });
    defer {
        if (manifest) |*m| {
            m.ast.deinit(gpa);
            m.deinit(gpa);
        }
    }

    const new_manifest_bytes = try allocPrintManifest(gpa, config, manifest);
    defer gpa.free(new_manifest_bytes);
    try build_root_directory.writeFile(.{
        .sub_path = "build.zig.zon",
        .data = new_manifest_bytes,
    });
    if (config.dependencies) |dependencies| {
        for (dependencies.map.keys(), dependencies.map.values()) |name, config_dep| {
            const path_or_url = switch (config_dep.value) {
                .path => config_dep.value.path.path,
                .url => config_dep.value.url.url,
            };

            if (manifest) |m| {
                if (m.dependencies.get(name)) |manifest_dep| {
                    if (depEql(manifest_dep, config_dep)) {
                        continue;
                    }
                }
            }
            try runZigFetch(
                gpa,
                arena,
                .{ .cwd = global_opts.project_dir },
                global_opts.getZigEnv(),
                path_or_url,
                .{ .exact = name },
            );
        }
    }
}

pub const LoadManifestOptions = struct {
    dir: std.fs.Dir,
    color: Color,
};

/// Mostly copy-pasted from zig/src/Package/Fetch.zig
pub fn loadManifest(
    gpa: Allocator,
    arena: Allocator,
    options: LoadManifestOptions,
) !?Manifest {
    const manifest_bytes = options.dir.readFileAllocOptions(
        arena,
        Manifest.basename,
        Manifest.max_bytes,
        null,
        1,
        0,
    ) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    var ast = try Ast.parse(gpa, manifest_bytes, .zon);
    errdefer ast.deinit(gpa);

    if (ast.errors.len > 0) {
        try std.zig.printAstErrorsToStderr(gpa, ast, Manifest.basename, options.color);
        return error.InvalidManifest;
    }

    var manifest = try Manifest.parse(gpa, ast, .{});
    errdefer manifest.deinit(gpa);

    if (manifest.errors.len > 0) {
        var wip_errors: std.zig.ErrorBundle.Wip = undefined;
        try wip_errors.init(gpa);
        defer wip_errors.deinit();

        const src_path = try wip_errors.addString(Manifest.basename);
        try manifest.copyErrorsIntoBundle(ast, src_path, &wip_errors);

        var error_bundle = try wip_errors.toOwnedBundle("");
        defer error_bundle.deinit(gpa);
        error_bundle.renderToStdErr(options.color.renderOptions());

        return error.InvalidManifest;
    }
    return manifest;
}

const Config = @import("Config.zig");

const manifest_template =
    \\// This file is generated by zbuild. Do not edit manually.
    \\
    \\.{{
    \\    .name = .{s},
    \\    .version = "{s}",
    \\    .fingerprint = {s},
    \\    .minimum_zig_version = "{s}",
    \\    .dependencies = {s},
    \\    .paths = {s},
    \\}}
;

fn allocPrintManifest(allocator: Allocator, config: Config, manifest: ?Manifest) ![]const u8 {
    return try std.fmt.allocPrint(allocator, manifest_template, .{
        config.name,
        config.version,
        config.fingerprint,
        config.minimum_zig_version,
        if (manifest) |m|
            m.ast.getNodeSource(m.dependencies_node)
        else
            ".{}",
        try strTupleLiteral(config.paths) orelse
            \\.{ "build.zig", "build.zig.zon", "src" }
        ,
    });
}

fn depEql(manifest_dep: Manifest.Dependency, config_dep: Config.Dependency) bool {
    if (config_dep.value == .path and manifest_dep.location != .path) {
        return false;
    }
    if (config_dep.value == .url and manifest_dep.location != .url) {
        return false;
    }
    const manifest_path_or_url, const config_path_or_url = switch (config_dep.value) {
        .path => .{ manifest_dep.location.path, config_dep.value.path.path },
        .url => .{ manifest_dep.location.url, config_dep.value.url.url },
    };
    return std.mem.eql(u8, manifest_path_or_url, config_path_or_url);
}
