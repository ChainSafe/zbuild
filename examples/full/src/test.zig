const std = @import("std");
const math = @import("math");

test "add" {
    try std.testing.expectEqual(@as(i32, 5), math.add(2, 3));
    try std.testing.expectEqual(@as(i32, 0), math.add(-1, 1));
}

test "multiply" {
    try std.testing.expectEqual(@as(i32, 6), math.multiply(2, 3));
    try std.testing.expectEqual(@as(i32, 0), math.multiply(0, 42));
}
