const std = @import("std");
const config = @import("config");

fn logLevelString(level: @TypeOf(config.log_level)) []const u8 {
    return switch (level) {
        .debug => "debug",
        .info => "info",
        .warn => "warn",
    };
}

pub fn main() !void {
    std.debug.print("level={s} tracing={} asset={s}\n", .{
        logLevelString(config.log_level),
        config.enable_tracing,
        config.asset_dir orelse "none",
    });
}
