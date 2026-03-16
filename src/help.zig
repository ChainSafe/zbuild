const std = @import("std");
const build_runner = @import("build_runner.zig");
const toComptimeString = build_runner.toComptimeString;

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
        const fields = @typeInfo(@TypeOf(manifest.modules)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nModules:\n";
            inline for (fields) |field| {
                const mod = @field(manifest.modules, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22);
                if (@hasField(@TypeOf(mod), "root_source_file"))
                    text = text ++ mod.root_source_file;
                text = text ++ "\n";
            }
        }
    }

    // Executables
    if (@hasField(@TypeOf(manifest), "executables")) {
        const fields = @typeInfo(@TypeOf(manifest.executables)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nExecutables:" ++ comptimePad("", 10) ++ "zig build run:<name>\n";
            inline for (fields) |field| {
                const exe = @field(manifest.executables, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22) ++ describeRootModule(exe.root_module) ++ "\n";
            }
        }
    }

    // Libraries
    if (@hasField(@TypeOf(manifest), "libraries")) {
        const fields = @typeInfo(@TypeOf(manifest.libraries)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nLibraries:" ++ comptimePad("", 12) ++ "zig build build-lib:<name>\n";
            inline for (fields) |field| {
                const lib = @field(manifest.libraries, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22) ++ describeRootModule(lib.root_module) ++ "\n";
            }
        }
    }

    // Objects
    if (@hasField(@TypeOf(manifest), "objects")) {
        const fields = @typeInfo(@TypeOf(manifest.objects)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nObjects:" ++ comptimePad("", 14) ++ "zig build build-obj:<name>\n";
            inline for (fields) |field| {
                const obj = @field(manifest.objects, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22) ++ describeRootModule(obj.root_module) ++ "\n";
            }
        }
    }

    // Tests
    if (@hasField(@TypeOf(manifest), "tests")) {
        const fields = @typeInfo(@TypeOf(manifest.tests)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nTests:" ++ comptimePad("", 16) ++ "zig build test:<name> | zig build test\n";
            inline for (fields) |field| {
                const t = @field(manifest.tests, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22) ++ describeRootModule(t.root_module) ++ "\n";
            }
        }
    }

    // Fmts
    if (@hasField(@TypeOf(manifest), "fmts")) {
        const fields = @typeInfo(@TypeOf(manifest.fmts)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nFmts:" ++ comptimePad("", 17) ++ "zig build fmt:<name> | zig build fmt\n";
            inline for (fields) |field| {
                const fmt = @field(manifest.fmts, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22);
                if (@hasField(@TypeOf(fmt), "paths"))
                    text = text ++ "paths: " ++ comptimeJoinTuple(fmt.paths);
                text = text ++ "\n";
            }
        }
    }

    // Runs
    if (@hasField(@TypeOf(manifest), "runs")) {
        const fields = @typeInfo(@TypeOf(manifest.runs)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nRuns:" ++ comptimePad("", 17) ++ "zig build cmd:<name>\n";
            inline for (fields) |field| {
                const run = @field(manifest.runs, field.name);
                text = text ++ "  " ++ comptimePad(field.name, 22) ++ describeRunCmd(run) ++ "\n";
            }
        }
    }

    // Options modules
    if (@hasField(@TypeOf(manifest), "options_modules")) {
        const mod_fields = @typeInfo(@TypeOf(manifest.options_modules)).@"struct".fields;
        if (mod_fields.len > 0) {
            text = text ++ "\nOptions:" ++ comptimePad("", 14) ++ "-D<name>=<value>\n";
            inline for (mod_fields) |mod_field| {
                const options = @field(manifest.options_modules, mod_field.name);
                inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |opt_field| {
                    const opt = @field(options, opt_field.name);
                    text = text ++ "  " ++ comptimePad(mod_field.name ++ "." ++ opt_field.name, 22);
                    text = text ++ toComptimeString(opt.type);
                    if (@hasField(@TypeOf(opt), "default"))
                        text = text ++ " (default: " ++ describeValue(opt.default) ++ ")";
                    if (@hasField(@TypeOf(opt), "description"))
                        text = text ++ " — " ++ opt.description;
                    text = text ++ "\n";
                }
            }
        }
    }

    // Dependencies
    if (@hasField(@TypeOf(manifest), "dependencies")) {
        const fields = @typeInfo(@TypeOf(manifest.dependencies)).@"struct".fields;
        if (fields.len > 0) {
            text = text ++ "\nDependencies:\n";
            inline for (fields) |field| {
                text = text ++ "  " ++ field.name ++ "\n";
            }
        }
    }

    return text;
}

pub fn comptimePad(comptime s: []const u8, comptime width: usize) []const u8 {
    if (s.len >= width) return s ++ " ";
    const padding = [1]u8{' '} ** (width - s.len);
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
    const fields = @typeInfo(@TypeOf(tuple)).@"struct".fields;
    var result: []const u8 = "";
    inline for (fields, 0..) |field, i| {
        if (i > 0) result = result ++ " ";
        result = result ++ @field(tuple, field.name);
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
