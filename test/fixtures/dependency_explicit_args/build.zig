const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) !void {
    const result = try zbuild.configureBuild(b, @import("build.zig.zon"), .{});
    // Check generated data at make time, including when configuration is cached.
    const cases = .{
        .{ "dep_inherit", "dep arch=powerpc64 os=linux abi=none optimize=fast portable=true\n" },
        .{ "dep_explicit", "dep arch=mips64 os=linux abi=none optimize=fast portable=true\n" },
        .{ "dep_defaults", "dep arch=powerpc64 os=linux abi=none optimize=safe portable=false\n" },
        .{ "dep_partial", "dep arch=powerpc64 os=linux abi=none optimize=safe portable=true\n" },
    };
    inline for (cases) |case| {
        const check = b.addCheckFile(result.dependency(case[0]).?.namedLazyPath("args"), .{
            .expected_exact = case[1],
        });
        b.getInstallStep().dependOn(&check.step);
    }
}
