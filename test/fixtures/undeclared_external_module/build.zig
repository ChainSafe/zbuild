const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) void {
    _ = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });

    _ = zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
