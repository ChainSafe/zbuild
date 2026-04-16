const std = @import("std");
const math = @import("math");
const config = @import("config");

pub fn main() void {
    const result = math.add(2, 3);
    std.debug.print("2 + 3 = {d}\n", .{result});
    if (config.verbose)
        std.debug.print("(verbose mode enabled)\n", .{});

    switch (config.log_level) {
        .debug => std.debug.print("log level: debug\n", .{}),
        .info => std.debug.print("log level: info\n", .{}),
        .warn => std.debug.print("log level: warn\n", .{}),
    }

    if (config.output_dir) |dir|
        std.debug.print("output dir: {s}\n", .{dir});
}
