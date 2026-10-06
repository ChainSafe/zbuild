const std = @import("std");
const build_runner = @import("build_runner.zig");
const toComptimeString = build_runner.toComptimeString;

pub fn createStep(b: *std.Build, comptime manifest: anytype) *std.Build.Step.Run {
    const files = b.addWriteFiles();
    _ = files.add("help.txt", comptime buildHelpText(manifest));
    const main = files.add("help.zig",
        \\const std = @import("std");
        \\pub fn main(init: std.process.Init) !void {
        \\    try std.Io.File.stdout().writeStreamingAll(init.io, @embedFile("help.txt"));
        \\}
        \\
    );
    const exe = b.addExecutable(.{
        .name = "zbuild-help",
        .root_module = b.createModule(.{
            .root_source_file = main,
            // Help must run on the build host even when the project cross-compiles.
            .target = b.graph.host,
            .optimize = .debug,
        }),
    });
    return b.addRunArtifact(exe);
}

pub fn buildHelpText(comptime manifest: anytype) []const u8 {
    var text: []const u8 = "";

    // Header
    if (@hasField(@TypeOf(manifest), "name"))
        text = text ++ @tagName(manifest.name);
    if (@hasField(@TypeOf(manifest), "version"))
        text = text ++ " v" ++ manifest.version;
    if (@hasField(@TypeOf(manifest), "description"))
        text = text ++ " — " ++ manifest.description;
    text = text ++ "\n";

    // Modules
    if (@hasField(@TypeOf(manifest), "modules")) {
        const fields = @typeInfo(@TypeOf(manifest.modules)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nModules:\n";
            inline for (fields) |field_name| {
                const mod = @field(manifest.modules, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22);
                if (@hasField(@TypeOf(mod), "root_source_file"))
                    text = text ++ mod.root_source_file;
                text = text ++ "\n";
            }
        }
    }

    // Executables
    if (@hasField(@TypeOf(manifest), "executables")) {
        const fields = @typeInfo(@TypeOf(manifest.executables)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nExecutables:" ++ comptimePad("", 10) ++ "zig build run:<name>\n";
            inline for (fields) |field_name| {
                const exe = @field(manifest.executables, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22) ++ describeRootModule(exe.root_module) ++ "\n";
            }
        }
    }

    // Libraries
    if (@hasField(@TypeOf(manifest), "libraries")) {
        const fields = @typeInfo(@TypeOf(manifest.libraries)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nLibraries:" ++ comptimePad("", 12) ++ "zig build build-lib:<name>\n";
            inline for (fields) |field_name| {
                const lib = @field(manifest.libraries, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22) ++ describeRootModule(lib.root_module) ++ "\n";
            }
        }
    }

    // Objects
    if (@hasField(@TypeOf(manifest), "objects")) {
        const fields = @typeInfo(@TypeOf(manifest.objects)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nObjects:" ++ comptimePad("", 14) ++ "zig build build-obj:<name>\n";
            inline for (fields) |field_name| {
                const obj = @field(manifest.objects, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22) ++ describeRootModule(obj.root_module) ++ "\n";
            }
        }
    }

    // Tests
    if (@hasField(@TypeOf(manifest), "tests")) {
        const fields = @typeInfo(@TypeOf(manifest.tests)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nTests:" ++ comptimePad("", 16) ++ "zig build test:<name> | zig build test\n";
            inline for (fields) |field_name| {
                const t = @field(manifest.tests, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22) ++ describeRootModule(t.root_module) ++ "\n";
            }
        }
    }

    // Fmts
    if (@hasField(@TypeOf(manifest), "fmts")) {
        const fields = @typeInfo(@TypeOf(manifest.fmts)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nFmts:" ++ comptimePad("", 17) ++ "zig build fmt:<name> | zig build fmt\n";
            inline for (fields) |field_name| {
                const fmt = @field(manifest.fmts, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22);
                if (@hasField(@TypeOf(fmt), "paths"))
                    text = text ++ "paths: " ++ comptimeJoinTuple(fmt.paths);
                text = text ++ "\n";
            }
        }
    }

    // Runs
    if (@hasField(@TypeOf(manifest), "runs")) {
        const fields = @typeInfo(@TypeOf(manifest.runs)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nRuns:" ++ comptimePad("", 17) ++ "zig build cmd:<name>\n";
            inline for (fields) |field_name| {
                const run = @field(manifest.runs, field_name);
                text = text ++ "  " ++ comptimePad(field_name, 22) ++ describeRunCmd(run) ++ "\n";
            }
        }
    }

    // Options modules
    if (@hasField(@TypeOf(manifest), "options_modules")) {
        const mod_fields = @typeInfo(@TypeOf(manifest.options_modules)).@"struct".field_names;
        if (mod_fields.len > 0) {
            text = text ++ "\nOptions:" ++ comptimePad("", 14) ++ "-D<module>.<option>=<value>\n";
            inline for (mod_fields) |mod_field_name| {
                const options = @field(manifest.options_modules, mod_field_name);
                inline for (@typeInfo(@TypeOf(options)).@"struct".field_names) |opt_field_name| {
                    const opt = @field(options, opt_field_name);
                    text = text ++ "  " ++ comptimePad(mod_field_name ++ "." ++ opt_field_name, 22);
                    text = text ++ toComptimeString(opt.type);
                    if (@hasField(@TypeOf(opt), "default"))
                        text = text ++ " (default: " ++ describeValue(opt.default) ++ ")";
                    if ((std.mem.eql(u8, toComptimeString(opt.type), "enum") or std.mem.eql(u8, toComptimeString(opt.type), "enum_list")) and @hasField(@TypeOf(opt), "values"))
                        text = text ++ " values: " ++ comptimeJoinValues(opt.values);
                    if (@hasField(@TypeOf(opt), "description"))
                        text = text ++ " — " ++ opt.description;
                    text = text ++ "\n";
                }
            }
        }
    }

    // Dependencies
    if (@hasField(@TypeOf(manifest), "dependencies")) {
        const fields = @typeInfo(@TypeOf(manifest.dependencies)).@"struct".field_names;
        if (fields.len > 0) {
            text = text ++ "\nDependencies:\n";
            inline for (fields) |field_name| {
                text = text ++ "  " ++ field_name ++ "\n";
            }
        }
    }

    return text;
}

pub fn comptimePad(comptime s: []const u8, comptime width: usize) []const u8 {
    if (s.len >= width) return s ++ " ";
    const padding: [width - s.len]u8 = @splat(' ');
    return s ++ &padding;
}

fn describeRootModule(comptime root_module: anytype) []const u8 {
    const ti = @typeInfo(@TypeOf(root_module));
    if (ti == .enum_literal) return "module: " ++ @tagName(root_module);
    if (ti == .pointer) return "module: " ++ @as([]const u8, root_module);
    if (@hasField(@TypeOf(root_module), "root_source_file"))
        return root_module.root_source_file;
    return "(inline module)";
}

fn describeRunCmd(comptime cmd: anytype) []const u8 {
    if (@hasField(@TypeOf(cmd), "cmd")) return comptimeJoinTuple(cmd.cmd);
    return comptimeJoinTuple(cmd);
}

fn comptimeJoinTuple(comptime tuple: anytype) []const u8 {
    const fields = @typeInfo(@TypeOf(tuple)).@"struct".field_names;
    var result: []const u8 = "";
    inline for (fields, 0..) |field_name, i| {
        if (i > 0) result = result ++ " ";
        result = result ++ @field(tuple, field_name);
    }
    return result;
}

fn comptimeJoinValues(comptime tuple: anytype) []const u8 {
    const fields = @typeInfo(@TypeOf(tuple)).@"struct".field_names;
    var result: []const u8 = "";
    inline for (fields, 0..) |field_name, i| {
        if (i > 0) result = result ++ ", ";
        result = result ++ describeValue(@field(tuple, field_name));
    }
    return result;
}

pub fn describeValue(comptime val: anytype) []const u8 {
    const ti = @typeInfo(@TypeOf(val));
    if (ti == .enum_literal) return @tagName(val);
    if (ti == .pointer) return val;
    if (ti == .bool) return if (val) "true" else "false";
    if (ti == .comptime_int or ti == .int) return std.fmt.comptimePrint("{d}", .{val});
    if (ti == .comptime_float or ti == .float) return std.fmt.comptimePrint("{d}", .{val});
    return "...";
}

// --- Tests ---

test "buildHelpText minimal" {
    const text = comptime buildHelpText(.{
        .name = .myproject,
        .version = "0.1.0",
    });
    try std.testing.expect(std.mem.indexOf(u8, text, "myproject v0.1.0") != null);
}

test "buildHelpText full manifest" {
    const text = comptime buildHelpText(.{
        .name = .myproject,
        .version = "1.0.0",
        .description = "A test project",
        .modules = .{
            .core = .{ .root_source_file = "src/core.zig" },
        },
        .executables = .{
            .myapp = .{ .root_module = .core },
        },
        .tests = .{
            .unit = .{ .root_module = .core },
        },
        .runs = .{
            .fmt = .{ "zig", "fmt", "src" },
            .deploy = .{ .cmd = .{ "./deploy.sh", "--prod" } },
        },
        .options_modules = .{
            .config = .{
                .verbose = .{ .type = .bool, .default = false, .description = "Verbose output" },
                .log_level = .{
                    .type = .@"enum",
                    .values = .{ .debug, .info, .warn },
                    .default = .info,
                    .description = "Log level",
                },
            },
        },
        .dependencies = .{
            .zlib = .{},
        },
    });
    try std.testing.expect(std.mem.indexOf(u8, text, "myproject v1.0.0 — A test project") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Modules:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "core") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "src/core.zig") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Executables:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "module: core") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Tests:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Runs:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "zig fmt src") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "./deploy.sh --prod") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Options:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "-D<module>.<option>=<value>") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "config.verbose") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "config.log_level") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "bool") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "values: debug, info, warn") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "default: false") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Verbose output") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "Dependencies:") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "zlib") != null);
}

test "comptimePad" {
    try std.testing.expectEqualStrings("hi    ", comptime comptimePad("hi", 6));
    try std.testing.expectEqualStrings("toolong ", comptime comptimePad("toolong", 4));
}

test "describeValue" {
    try std.testing.expectEqualStrings("true", comptime describeValue(true));
    try std.testing.expectEqualStrings("false", comptime describeValue(false));
    try std.testing.expectEqualStrings("hello", comptime describeValue("hello"));
    try std.testing.expectEqualStrings("info", comptime describeValue(.info));
    try std.testing.expectEqualStrings("42", comptime describeValue(42));
}
