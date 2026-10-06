const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const portable = b.option(bool, "portable", "portable mode") orelse false;

    const contents = b.fmt(
        "dep arch={s} os={s} abi={s} optimize={s} portable={}\n",
        .{
            @tagName(target.result.cpu.arch),
            @tagName(target.result.os.tag),
            @tagName(target.result.abi),
            @tagName(optimize),
            portable,
        },
    );
    b.addNamedLazyPath("args", b.addWriteFiles().add("args.txt", contents));
}
