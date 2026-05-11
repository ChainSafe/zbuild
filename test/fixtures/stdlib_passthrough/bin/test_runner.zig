const builtin = @import("builtin");
const std = @import("std");
const testing = std.testing;

pub fn main() !void {
    testing.io_instance = .init(testing.allocator, .{});

    var failed: usize = 0;
    for (builtin.test_functions) |test_fn| {
        test_fn.func() catch |err| switch (err) {
            error.SkipZigTest => continue,
            else => {
                std.debug.print("{s}: {t}\n", .{ test_fn.name, err });
                failed += 1;
            },
        };
    }

    if (failed != 0) std.process.exit(1);
}
