const std = @import("std");
const core = @import("core");
const shared = @import("shared");

pub fn main(init: std.process.Init) !void {
    std.debug.print("{s} {s}\n", .{ core.get(), shared.message });
    const args = try init.minimal.args.toSlice(init.arena.allocator());
    for (args[1..]) |arg| std.debug.print("arg: {s}\n", .{arg});
}
