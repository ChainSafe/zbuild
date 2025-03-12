//! Parse command-line argument string into a list of args.
//! This is a simple parser that splits the input string on spaces and quotes and supports escaping
const std = @import("std");

const Args = @This();

args: std.ArrayList([]const u8),

pub fn deinit(self: Args) void {
    for (self.args.items) |arg| {
        self.args.allocator.free(arg);
    }
    self.args.deinit();
}

pub fn parse(allocator: std.mem.Allocator, input: []const u8) !Args {
    var args = std.ArrayList([]const u8).init(allocator);
    var i: usize = 0;
    var start: usize = 0;
    var quote_char: ?u8 = null; // Tracks ' or " when in quotes, null when not

    var buffer = std.ArrayList(u8).init(allocator);
    defer buffer.deinit();

    while (i < input.len) : (i += 1) {
        const c = input[i];

        // Handle escapes
        if (c == '\\' and i + 1 < input.len) {
            const next = input[i + 1];
            i += 1; // Skip the backslash
            if (quote_char) |qc| {
                // Inside quotes: only escape the active quote or backslash
                if (next == qc or next == '\\') {
                    try buffer.append(next);
                } else {
                    // Preserve the backslash and next character literally
                    try buffer.append('\\');
                    try buffer.append(next);
                }
            } else {
                // Outside quotes: escape the next character (e.g., space) to prevent splitting
                try buffer.append(next);
            }
            continue;
        }

        switch (c) {
            '"', '\'' => {
                if (quote_char) |qc| {
                    // We're in quotes; check if this matches the opening quote
                    if (c == qc) {
                        // End of quoted string
                        if (buffer.items.len > 0) {
                            try args.append(try buffer.toOwnedSlice());
                        }
                        quote_char = null;
                        start = i + 1;
                    } else {
                        // Different quote type inside quotes, treat as literal
                        try buffer.append(c);
                    }
                } else {
                    // Start of quoted string
                    if (i > start and buffer.items.len > 0) {
                        try args.append(try buffer.toOwnedSlice());
                    }
                    quote_char = c;
                    start = i + 1;
                }
            },
            ' ' => if (quote_char == null) {
                // Split on space outside quotes
                if (i > start or buffer.items.len > 0) {
                    if (buffer.items.len > 0) {
                        try args.append(try buffer.toOwnedSlice());
                    } else {
                        try args.append(try allocator.dupe(u8, input[start..i]));
                    }
                }
                start = i + 1;
            } else {
                // Inside quotes, treat space as literal
                try buffer.append(c);
            },
            else => {
                // Add character to buffer
                try buffer.append(c);
            },
        }
    }

    // Handle any remaining content
    if (start < input.len or buffer.items.len > 0) {
        if (buffer.items.len > 0) {
            try args.append(try buffer.toOwnedSlice());
        } else if (start < input.len) {
            try args.append(try allocator.dupe(u8, input[start..]));
        }
    }

    return .{ .args = args };
}

const TestCase = struct {
    input: []const u8,
    expected: []const []const u8,
};
const test_cases = &[_]TestCase{
    .{
        .input =
        \\name=Alice "age=30 years" "quoted \"text\"" unquoted\ space
        ,
        .expected = &[_][]const u8{
            \\name=Alice
            ,
            \\age=30 years
            ,
            \\quoted "text"
            ,
            \\unquoted space
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
