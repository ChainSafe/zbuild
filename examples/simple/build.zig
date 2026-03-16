const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    // TODO: @import("build.zig.zon") requires a known result type in Zig 0.14.
    // Investigating whether later Zig versions lift this restriction.
    // For now, the manifest is defined inline.
    _ = zbuild.configureBuild(b, .{
        .name = .simple_example,
        .version = "0.1.0",
        .description = "A minimal zbuild example",
        .executables = .{
            .hello = .{
                .root_module = .{
                    .root_source_file = "src/main.zig",
                },
            },
        },
    }, .{}) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
