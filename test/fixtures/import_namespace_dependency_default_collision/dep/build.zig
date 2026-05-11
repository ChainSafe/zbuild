const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = b.addModule("dep_pkg", .{
        .root_source_file = b.path("src/lib.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
}
