const std = @import("std");
const math = @import("math");
const config = @import("config");

pub fn main() void {
    const result = math.add(2, 3);
    std.debug.print("2 + 3 = {d}\n", .{result});
    if (config.verbose)
        std.debug.print("(verbose mode enabled)\n", .{});
}
