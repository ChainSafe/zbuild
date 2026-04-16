const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) void {
    _ = b.step("cmd:demo", "manual demo step");

    _ = zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
