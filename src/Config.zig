//! Configuration file (aka `zbuild.json`) format for the Zig build system.

const std = @import("std");

const CompactUnion = @import("compact_union.zig").CompactUnion;
const ArrayHashMap = std.json.ArrayHashMap;

const Config = @This();

name: []const u8,
version: []const u8,
fingerprint: []const u8,
minimum_zig_version: []const u8,
paths: ?[][]const u8 = null,
description: ?[]const u8 = null,
keywords: ?[][]const u8 = null,
dependencies: ?ArrayHashMap(Dependency) = null,
options: ?ArrayHashMap(Option) = null,
options_modules: ?ArrayHashMap(OptionsModule) = null,
modules: ?ArrayHashMap(Module) = null,
executables: ?ArrayHashMap(Executable) = null,
libraries: ?ArrayHashMap(Library) = null,
objects: ?ArrayHashMap(Object) = null,
tests: ?ArrayHashMap(Test) = null,
fmts: ?ArrayHashMap(Fmt) = null,
runs: ?ArrayHashMap(Run) = null,

pub const Dependency = CompactUnion(union(enum) {
    path: Path,
    url: Url,

    pub const Path = struct {
        path: []const u8,
    };

    pub const Url = struct {
        url: []const u8,
    };

    const TagType = @typeInfo(@This()).@"union".tag_type.?;
    pub fn enumFromValue(source: std.json.Value) ?TagType {
        if (source == .object) {
            if (source.object.get("path") != null) {
                return .path;
            } else if (source.object.get("url") != null) {
                return .url;
            }
        }
        return null;
    }
});

pub const Option = CompactUnion(union(enum) {
    bool: Bool,
    int: Int,
    float: Float,
    @"enum": Enum,
    enum_list: EnumList,
    string: String,
    list: List,
    build_id: BuildId,
    lazy_path: LazyPath,
    lazy_path_list: LazyPathList,

    pub const Bool = struct {
        default: ?bool = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Int = struct {
        default: ?i64 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Float = struct {
        default: ?f64 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const Enum = struct {
        default: ?[]const u8 = null,
        enum_options: [][]const u8,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const EnumList = struct {
        default: ?[][]const u8 = null,
        enum_options: [][]const u8,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const String = struct {
        default: ?[]const u8 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const List = struct {
        default: ?[][]const u8 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const BuildId = struct {
        default: ?[]const u8 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const LazyPath = struct {
        default: ?[]const u8 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };
    pub const LazyPathList = struct {
        default: ?[][]const u8 = null,
        type: []const u8,
        description: ?[]const u8 = null,
    };

    fn isValidIntType(t: []const u8) bool {
        return std.mem.eql(u8, t, "i8") or
            std.mem.eql(u8, t, "u8") or
            std.mem.eql(u8, t, "i16") or
            std.mem.eql(u8, t, "u16") or
            std.mem.eql(u8, t, "i32") or
            std.mem.eql(u8, t, "u32") or
            std.mem.eql(u8, t, "i64") or
            std.mem.eql(u8, t, "u64") or
            std.mem.eql(u8, t, "i128") or
            std.mem.eql(u8, t, "u128") or
            std.mem.eql(u8, t, "isize") or
            std.mem.eql(u8, t, "usize") or
            std.mem.eql(u8, t, "c_short") or
            std.mem.eql(u8, t, "c_ushort") or
            std.mem.eql(u8, t, "c_int") or
            std.mem.eql(u8, t, "c_uint") or
            std.mem.eql(u8, t, "c_long") or
            std.mem.eql(u8, t, "c_ulong") or
            std.mem.eql(u8, t, "c_longlong") or
            std.mem.eql(u8, t, "c_ulonglong");
    }

    fn isValidFloatType(t: []const u8) bool {
        return std.mem.eql(u8, t, "f16") or
            std.mem.eql(u8, t, "f32") or
            std.mem.eql(u8, t, "f64") or
            std.mem.eql(u8, t, "f80") or
            std.mem.eql(u8, t, "f128") or
            std.mem.eql(u8, t, "c_longdouble");
    }

    const TagType = @typeInfo(@This()).@"union".tag_type.?;
    pub fn enumFromValue(source: std.json.Value) ?TagType {
        if (source != .object) return null;
        const type_value = source.object.get("type") orelse return null;
        if (type_value != .string) return null;
        const t = type_value.string;
        if (std.mem.eql(u8, t, "bool")) {
            return .bool;
        } else if (std.mem.eql(u8, t, "enum")) {
            return .@"enum";
        } else if (std.mem.eql(u8, t, "enum_list")) {
            return .enum_list;
        } else if (std.mem.eql(u8, t, "string")) {
            return .string;
        } else if (std.mem.eql(u8, t, "list")) {
            return .list;
        } else if (std.mem.eql(u8, t, "lazy_path")) {
            return .lazy_path;
        } else if (std.mem.eql(u8, t, "lazy_path_list")) {
            return .lazy_path_list;
        } else if (std.mem.eql(u8, t, "build_id")) {
            return .build_id;
        } else if (isValidIntType(t)) {
            return .int;
        } else if (isValidFloatType(t)) {
            return .float;
        }

        return null;
    }
});

pub const OptionsModule = ArrayHashMap(Option);

pub const Module = struct {
    name: ?[]const u8 = null,
    root_source_file: ?[]const u8 = null,
    imports: ?[][]const u8 = null,
    // options: ?ArrayHashMap(OptionsModule) = null,
    private: ?bool = null,

    target: ?[]const u8 = null,
    optimize: ?std.builtin.OptimizeMode = null,
    link_libc: ?bool = null,
    link_libcpp: ?bool = null,
    single_threaded: ?bool = null,
    strip: ?bool = null,
    unwind_tables: ?std.builtin.UnwindTables = null,
    dwarf_format: ?std.dwarf.Format = null,
    code_model: ?std.builtin.CodeModel = null,
    stack_protector: ?bool = null,
    stack_check: ?bool = null,
    sanitize_c: ?bool = null,
    sanitize_thread: ?bool = null,
    fuzz: ?bool = null,
    valgrind: ?bool = null,
    pic: ?bool = null,
    red_zone: ?bool = null,
    omit_frame_pointer: ?bool = null,
    error_tracing: ?bool = null,
};

pub const ModuleLink = CompactUnion(union(enum) {
    name: []const u8,
    module: Module,

    const TagType = @typeInfo(@This()).@"union".tag_type.?;
    pub fn enumFromValue(source: std.json.Value) ?TagType {
        if (source == .string) {
            return .name;
        } else if (source == .object) {
            return .module;
        }
        return null;
    }
});

pub const Executable = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    root_module: ModuleLink,
    linkage: ?std.builtin.LinkMode = null,
    max_rss: ?usize = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?[]const u8 = null,
    win32_manifest: ?[]const u8 = null,

    depends_on: ?[][]const u8 = null,
};

pub const Library = struct {
    name: ?[]const u8 = null,
    version: ?[]const u8 = null,
    root_module: ModuleLink,
    linkage: ?std.builtin.LinkMode = null,
    max_rss: ?usize = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?[]const u8 = null,
    win32_manifest: ?[]const u8 = null,

    depends_on: ?[][]const u8 = null,
};

pub const Object = struct {
    name: ?[]const u8 = null,
    root_module: ModuleLink,
    max_rss: ?usize = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?[]const u8 = null,

    depends_on: ?[][]const u8 = null,
};

pub const Test = struct {
    name: ?[]const u8 = null,
    root_module: ModuleLink,
    max_rss: ?usize = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?[]const u8 = null,

    filters: []const []const u8 = &.{},
    test_runner: ?[]const u8 = null,
};

pub const Fmt = struct {
    paths: ?[][]const u8 = null,
    exclude_paths: ?[][]const u8 = null,
    check: ?bool = false,
};

pub const Run = []const u8;

pub fn load(arena: std.mem.Allocator, zbuild_file: []const u8) !Config {
    const config_bytes = try std.fs.cwd().readFileAlloc(arena, zbuild_file, 16_000);
    return try std.json.parseFromSliceLeaky(Config, arena, config_bytes, .{});
}

pub fn save(config: Config, zbuild_file: []const u8) !void {
    const file = try std.fs.cwd().createFile(zbuild_file, .{});
    defer file.close();

    const writer = file.writer();
    try std.json.stringify(
        config,
        .{
            .whitespace = .indent_2,
            .emit_null_optional_fields = false,
        },
        writer,
    );
}

pub fn addDependency(config: *Config, gpa: std.mem.Allocator, name: []const u8, dependency: Dependency) !void {
    if (config.dependencies == null) {
        config.dependencies = .{ .map = std.StringArrayHashMapUnmanaged(Dependency).empty };
    }
    try config.dependencies.?.map.put(gpa, name, dependency);
}

pub fn addExecutable(config: *Config, gpa: std.mem.Allocator, name: []const u8, executable: Executable) !void {
    if (config.executables == null) {
        config.executables = .{ .map = std.StringArrayHashMapUnmanaged(Executable).empty };
    }
    try config.executables.?.map.put(gpa, name, executable);
}

test "Config - json parsing" {
    const allocator = std.testing.allocator;
    const config_json_strs = [_][]const u8{
        \\{
        \\  "name": "myproject",
        \\  "version": "1.2.3",
        \\  "dependencies": {},
        \\  "modules": {
        \\    "foo": {
        \\      "root_source_file": "src/foo/main.zig"
        \\    }
        \\  },
        \\  "executables": {
        \\    "foo": {
        \\      "root_module": "bar",
        \\      "version": "1.2.3"
        \\    }
        \\  },
        \\  "fmts": {
        \\    "all": {
        \\      "paths": ["src"]
        \\    }
        \\  },
        \\  "runs": {
        \\    "simple": "echo hello"
        \\  }
        \\}
    };

    for (config_json_strs) |config_json_str| {
        const config_json = try std.json.parseFromSlice(Config, allocator, config_json_str, .{});
        defer config_json.deinit();
    }
}
