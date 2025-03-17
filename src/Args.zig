//! Parse, iterate over command-line arguments
const std = @import("std");

const Args = @This();

args: std.ArrayList([]const u8),
index: usize = 0,

pub fn deinit(self: Args) void {
    for (self.args.items) |arg| {
        self.args.allocator.free(arg);
    }
    self.args.deinit();
}

pub fn initFromProcessArgs(allocator: std.mem.Allocator) !Args {
    var it = try std.process.argsWithAllocator(allocator);
    defer it.deinit();
    return try initFromIterator(allocator, &it);
}

pub fn initFromString(allocator: std.mem.Allocator, input: []const u8) !Args {
    var it = try std.process.ArgIteratorGeneral(.{ .single_quotes = true }).init(allocator, input);
    defer it.deinit();
    return try initFromIterator(allocator, &it);
}

pub fn initFromIterator(allocator: std.mem.Allocator, it: anytype) !Args {
    var args = std.ArrayList([]const u8).init(allocator);
    while (it.next()) |arg| {
        try args.append(try allocator.dupe(u8, arg));
    }

    return .{ .args = args };
}

pub fn next(self: *Args) ?[]const u8 {
    if (self.index == self.args.items.len) return null;

    const arg = self.args.items[self.index];
    self.index += 1;
    return arg;
}

pub fn peek(self: *Args) ?[]const u8 {
    if (self.index == self.args.items.len) return null;

    return self.args.items[self.index];
}

pub fn rest(self: *Args) []const []const u8 {
    return self.args.items[self.index..];
}

const TestCase = struct {
    input: []const u8,
    expected: []const []const u8,
};
const test_cases = &[_]TestCase{
    .{
        .input =
        \\name=Alice "age=30 years" "quoted \"text\""
        ,
        .expected = &[_][]const u8{
            \\name=Alice
            ,
            \\age=30 years
            ,
            \\quoted "text"
            ,
        },
    },
};

test "parse" {
    const allocator = std.testing.allocator;
    for (test_cases) |tc| {
        var args = try Args.parse(allocator, tc.input);
        defer args.deinit();

        const actual = args.args.items;
        const expected = tc.expected;

        try std.testing.expectEqualDeep(expected, actual);
    }
}
