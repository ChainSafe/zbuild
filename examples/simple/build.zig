const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = try zbuild.configureBuild(b, @import("build.zig.zon"), .{});
}
