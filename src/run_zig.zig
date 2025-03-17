//! Simple wrapper around the `zig` executable.

const std = @import("std");
const Allocator = std.mem.Allocator;

const ZigEnv = @import("ZigEnv.zig");

pub fn runZigBuild(gpa: Allocator, arena: Allocator, child_opts: ChildOpts, env: ZigEnv, step: ?[]const u8, args: []const []const u8) !void {
    try runZig(gpa, arena, child_opts, env, .{
        .build = .{
            .step = step,
            .args = args,
        },
    });
}

pub fn runZigFetch(gpa: Allocator, arena: Allocator, child_opts: ChildOpts, env: ZigEnv, path_or_url: []const u8, save: ZigCmd.Fetch.Save) !void {
    try runZig(gpa, arena, child_opts, env, .{
        .fetch = .{
            .path_or_url = path_or_url,
            .save = save,
        },
    });
}

pub const ZigCmd = union(enum) {
    build: Build,
    fetch: Fetch,

    pub const Build = struct {
        step: ?[]const u8,
        args: []const []const u8,
    };

    pub const Fetch = struct {
        path_or_url: []const u8,
        save: Save = .no,

        pub const Save = union(enum) {
            no,
            yes: ?[]const u8,
            exact: ?[]const u8,
        };
    };
};

pub const ChildOpts = struct {
    cwd: ?[]const u8 = null,
    stdout_behavior: std.process.Child.StdIo = .Inherit,
    stderr_behavior: std.process.Child.StdIo = .Inherit,
};

pub fn runZig(gpa: Allocator, arena: Allocator, child_opts: ChildOpts, env: ZigEnv, cmd: ZigCmd) !void {
    var argv = std.ArrayList([]const u8).init(gpa);
    defer argv.deinit();

    try argv.append(env.zig_exe);

    switch (cmd) {
        .build => |build| {
            try argv.append("build");
            if (build.step) |s| {
                try argv.append(s);
            }
            try argv.appendSlice(build.args);
        },
        .fetch => |fetch| {
            try argv.append("fetch");
            try argv.append(fetch.path_or_url);
            switch (fetch.save) {
                .no => {},
                .yes => |name| {
                    if (name) |n| {
                        const arg = try std.fmt.allocPrint(arena, "--save={s}", .{n});
                        try argv.append(arg);
                    } else {
                        try argv.append("--save");
                    }
                },
                .exact => |name| {
                    if (name) |n| {
                        const arg = try std.fmt.allocPrint(arena, "--save={s}", .{n});
                        try argv.append(arg);
                    } else {
                        try argv.append("--save-exact");
                    }
                },
            }
        },
    }

    var child = std.process.Child.init(argv.items, gpa);
    child.cwd = child_opts.cwd;
    child.stdout_behavior = child_opts.stdout_behavior;
    child.stderr_behavior = child_opts.stderr_behavior;

    const term = try child.spawnAndWait();

    switch (term) {
        .Exited => |code| {
            if (code == 0) {
                return;
            } else {
                std.process.exit(code);
            }
        },
        else => {},
    }

    std.process.exit(1);
}
