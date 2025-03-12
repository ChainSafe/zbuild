const std = @import("std");

/// A union wrapper class for json parsing that avoids a wrapper json object
///
/// For example, allows the following
///
/// ```zig
/// union {
///     a: u8,
///     b: bool,
///     c: struct { x: u8, y: u8 },
/// }
/// ```
///
/// To be parsed from / serialized as
///
/// ```json
/// 55
/// ```
/// or
/// ```
/// false
/// ```
/// or
/// ```
/// { x: 1, y: 2 }
/// ```
pub fn CompactUnion(comptime T: type) type {
    const typeInfo = @typeInfo(T);
    if (typeInfo != .@"union") @compileError("can only be used with unions");
    if (!@hasDecl(T, "enumFromValue")) @compileError("union must have enumFromValue(std.json.Value)?TagType decl");
    return struct {
        value: T,

        pub const Type = T;

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !@This() {
            const value = try std.json.innerParse(std.json.Value, allocator, source, options);

            return try jsonParseFromValue(allocator, value, options);
        }

        pub fn jsonParseFromValue(allocator: std.mem.Allocator, source: std.json.Value, options: std.json.ParseOptions) !@This() {
            if (T.enumFromValue(source)) |tag| {
                const tag_name = @tagName(tag);
                inline for (typeInfo.@"union".fields) |field| {
                    if (std.mem.eql(u8, field.name, tag_name)) {
                        return .{ .value = @unionInit(T, field.name, try std.json.innerParseFromValue(field.type, allocator, source, options)) };
                    }
                }
            }
            return error.UnexpectedToken;
        }

        pub fn jsonStringify(self: @This(), jws: anytype) !void {
            inline for (typeInfo.@"union".fields) |field| {
                if (std.mem.eql(u8, field.name, @tagName(self.value))) {
                    try jws.write(@field(self.value, field.name));
                    return;
                }
            }
            unreachable;
        }
    };
}

test "CompactUnion" {
    const T1 = CompactUnion(union(enum) {
        a: u8,
        b: bool,
        c: []const u8,

        const TagType = @typeInfo(@This()).@"union".tag_type.?;
        pub fn enumFromValue(source: std.json.Value) ?TagType {
            return switch (source) {
                .string => .c,
                .bool => .b,
                .integer => .a,
                else => null,
            };
        }
    });

    const t1_data = .{
        .{ "true", T1{ .value = .{ .b = true } } },
        .{ "55", T1{ .value = .{ .a = 55 } } },
        .{ "\"hello\"", T1{ .value = .{ .c = "hello" } } },
    };

    inline for (t1_data) |test_case| {
        const parsed = try std.json.parseFromSlice(T1, std.testing.allocator, test_case[0], .{});
        defer parsed.deinit();

        try std.testing.expectEqualDeep(test_case[1], parsed.value);

        const stringified = try std.json.stringifyAlloc(std.testing.allocator, test_case[1], .{});
        defer std.testing.allocator.free(stringified);

        try std.testing.expectEqualStrings(test_case[0], stringified);
    }
}
