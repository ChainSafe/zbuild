const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) void {
    _ = b.addModule("core", .{
        .root_source_file = b.path("src/manual_core.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });

    _ = zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
