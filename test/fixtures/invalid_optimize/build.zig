const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) !void {
    _ = try zbuild.configureBuild(b, @import("build.zig.zon"), .{});
}
