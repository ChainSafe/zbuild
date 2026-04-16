const std = @import("std");
const core = @import("core");
const shared = @import("shared");

pub fn main() void {
    std.debug.print("{s} {s}\n", .{ core.get(), shared.message });
}
