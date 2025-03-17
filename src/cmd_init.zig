const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const GlobalOptions = @import("GlobalOptions.zig");
const Config = @import("Config.zig");
const sync = @import("cmd_sync.zig");
const Package = @import("Package.zig");
const Manifest = @import("Manifest.zig");

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions) !void {
    const cwd = try std.fs.cwd().realpathAlloc(gpa, global_opts.project_dir);
    defer gpa.free(cwd);
    const name = try sanitizeExampleName(arena, std.fs.path.basename(cwd));
    const fingerprint = try std.fmt.allocPrint(
        gpa,
        "0x{x}",
        .{Package.Fingerprint.generate(name).int()},
    );
    defer gpa.free(fingerprint);

    var paths = [_][]const u8{ "build.zig", "build.zig.zon", "src" };

    var config = Config{
        .name = name,
        .version = "0.1.0",
        .minimum_zig_version = global_opts.version,
        .fingerprint = fingerprint,
        .paths = &paths,
    };

    try config.addExecutable(gpa, name, Config.Executable{ .root_module = .{ .value = .{ .module = .{
        .root_source_file = "src/main.zig",
    } } } });

    const zbuild_filename = try std.fs.path.join(gpa, &[_][]const u8{ cwd, global_opts.zbuild_file });
    defer gpa.free(zbuild_filename);
    try config.save(zbuild_filename);

    const src_dirname = try std.fs.path.join(gpa, &[_][]const u8{ cwd, "src" });
    defer gpa.free(src_dirname);
    std.fs.cwd().makeDir(src_dirname) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };
    const main_filename = try std.fs.path.join(gpa, &[_][]const u8{ src_dirname, "main.zig" });
    const main_file = try std.fs.cwd().createFile(main_filename, .{});
    defer main_file.close();

    try main_file.writeAll(main_bytes);

    if (!global_opts.no_sync) {
        try sync.exec(gpa, arena, global_opts, config);
    }
}

const main_bytes =
    \\//! By convention, main.zig is where your main function lives in the case that
    \\//! you are building an executable. If you are making a library, the convention
    \\//! is to delete this file and start with root.zig instead.
    \\const std = @import("std");
    \\
    \\pub fn main() !void {
    \\    // Prints to stderr (it's a shortcut based on `std.io.getStdErr()`)
    \\    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    \\
    \\    // stdout is for the actual output of your application, for example if you
    \\    // are implementing gzip, then only the compressed bytes should be sent to
    \\    // stdout, not any debugging messages.
    \\    const stdout_file = std.io.getStdOut().writer();
    \\    var bw = std.io.bufferedWriter(stdout_file);
    \\    const stdout = bw.writer();
    \\
    \\    try stdout.print("Run `zbuild test` to run the tests.\n", .{});
    \\
    \\    try bw.flush(); // Don't forget to flush!
    \\}
    \\
;

fn sanitizeExampleName(arena: Allocator, bytes: []const u8) error{OutOfMemory}![]const u8 {
    var result: std.ArrayListUnmanaged(u8) = .empty;
    for (bytes, 0..) |byte, i| switch (byte) {
        '0'...'9' => {
            if (i == 0) try result.append(arena, '_');
            try result.append(arena, byte);
        },
        '_', 'a'...'z', 'A'...'Z' => try result.append(arena, byte),
        '-', '.', ' ' => try result.append(arena, '_'),
        else => continue,
    };
    if (!std.zig.isValidId(result.items)) return "foo";
    if (result.items.len > Manifest.max_name_len)
        result.shrinkRetainingCapacity(Manifest.max_name_len);

    return result.toOwnedSlice(arena);
}
