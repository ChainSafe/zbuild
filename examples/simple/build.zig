const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    _ = zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
