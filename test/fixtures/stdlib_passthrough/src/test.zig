const std = @import("std");
const core = @import("core");

test "add" {
    try std.testing.expectEqual(@as(i32, 5), core.add(2, 3));
}
