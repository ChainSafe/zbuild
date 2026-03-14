//! Configuration file (aka `zbuild.zon`) format for the Zig build system.
//! This file is meant to be a superset of the `build.zig.zon` manifest file format.

const std = @import("std");
const ArrayHashMap = std.StringArrayHashMap;

const Config = @This();

name: []const u8,
version: []const u8,
fingerprint: u64,
minimum_zig_version: []const u8,
paths: [][]const u8,
description: ?[]const u8 = null,
keywords: ?[][]const u8 = null,
dependencies: ?ArrayHashMap(Dependency) = null,
write_files: ?ArrayHashMap(WriteFile) = null,
options: ?ArrayHashMap(Option) = null,
options_modules: ?ArrayHashMap(OptionsModule) = null,
modules: ?ArrayHashMap(Module) = null,
executables: ?ArrayHashMap(Executable) = null,
libraries: ?ArrayHashMap(Library) = null,
objects: ?ArrayHashMap(Object) = null,
tests: ?ArrayHashMap(Test) = null,
fmts: ?ArrayHashMap(Fmt) = null,
runs: ?ArrayHashMap(Run) = null,

pub const Dependency = struct {
    typ: enum { path, url },
    value: []const u8,
    hash: ?[]const u8 = null,
    lazy: ?bool = null,
    args: ?ArrayHashMap(Arg) = null,

    const Arg = union(enum) {
        bool: bool,
        int: i64,
        float: f64,
        @"enum": []const u8,
        string: []const u8,
        null: void,
    };

};

pub const Option = union(enum) {
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

    pub fn isValidIntType(t: []const u8) bool {
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

    pub fn isValidFloatType(t: []const u8) bool {
        return std.mem.eql(u8, t, "f16") or
            std.mem.eql(u8, t, "f32") or
            std.mem.eql(u8, t, "f64") or
            std.mem.eql(u8, t, "f80") or
            std.mem.eql(u8, t, "f128") or
            std.mem.eql(u8, t, "c_longdouble");
    }
};

pub const OptionsModule = ArrayHashMap(Option);

pub const WriteFile = struct {
    private: ?bool = null,
    items: ?ArrayHashMap(Path) = null,

    pub const Path = union(enum) {
        file: File,
        dir: Dir,

        pub const File = struct {
            type: []const u8,
            path: []const u8,
        };

        pub const Dir = struct {
            type: []const u8,
            path: []const u8,
            exclude_extensions: ?[][]const u8 = null,
            include_extensions: ?[][]const u8 = null,
        };
    };

};

pub const Module = struct {
    name: ?[]const u8 = null,
    root_source_file: ?[]const u8 = null,
    imports: ?[][]const u8 = null,
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
    include_paths: ?[][]const u8 = null,
    link_libraries: ?[][]const u8 = null,

};

pub const ModuleLink = union(enum) {
    name: []const u8,
    module: Module,

};

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

    // install artifact options
    dest_sub_path: ?[]const u8 = null,

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
    linker_allow_shlib_undefined: ?bool = null,

    // install artifact options
    dest_sub_path: ?[]const u8 = null,

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


pub fn addDependency(config: *Config, gpa: std.mem.Allocator, name: []const u8, dependency: Dependency) !void {
    if (config.dependencies == null) {
        config.dependencies = ArrayHashMap(Dependency).init(gpa);
    }
    try config.dependencies.?.put(name, dependency);
}

pub fn addExecutable(config: *Config, gpa: std.mem.Allocator, name: []const u8, executable: Executable) !void {
    if (config.executables == null) {
        config.executables = ArrayHashMap(Executable).init(gpa);
    }
    try config.executables.?.put(name, executable);
}

pub fn parseFromFile(gpa: std.mem.Allocator, zbuild_file: []const u8, wip_bundle: ?*std.zig.ErrorBundle.Wip) !Config {
    const source = try std.fs.cwd().readFileAllocOptions(gpa, zbuild_file, 16_000, null, @alignOf(u8), 0);
    defer gpa.free(source);

    var ast = try std.zig.Ast.parse(gpa, source, .zon);
    defer ast.deinit(gpa);

    var zoir = try std.zig.ZonGen.generate(gpa, ast, .{});
    defer zoir.deinit(gpa);

    if (zoir.hasCompileErrors()) {
        if (wip_bundle) |wip| {
            try wip.addZoirErrorMessages(zoir, ast, source, zbuild_file);
        }

        return error.ParseZoir;
    }

    return parseFromZoir(gpa, zbuild_file, zoir, ast, wip_bundle);
}

pub fn parseFromZoir(gpa: std.mem.Allocator, zbuild_file: []const u8, zoir: std.zig.Zoir, ast: std.zig.Ast, wip_bundle: ?*std.zig.ErrorBundle.Wip) Parser.Error!Config {
    var status = std.zon.parse.Status{};
    var parser = Parser{ .gpa = gpa, .zoir = zoir, .ast = ast, .status = &status };

    return parser.parse() catch |e| {
        if (status.type_check) |err| {
            const err_span = ast.tokenToSpan(err.token);
            const err_loc = std.zig.findLineColumn(ast.source, err_span.main);

            if (wip_bundle) |wip| {
                try wip.addRootErrorMessage(.{
                    .msg = try wip.addString(err.message),
                    .src_loc = try wip.addSourceLocation(.{
                        .src_path = try wip.addString(zbuild_file),
                        .line = @intCast(err_loc.line),
                        .column = @intCast(err_loc.column),
                        .span_start = err_span.start,
                        .span_end = err_span.end,
                        .span_main = err_span.main,
                        .source_line = try wip.addString(err_loc.source_line),
                    }),
                });
            }
        }
        return e;
    };
}

const Parser = struct {
    gpa: std.mem.Allocator,
    zoir: std.zig.Zoir,
    ast: std.zig.Ast,
    status: *std.zon.parse.Status,

    const Error = error{ OutOfMemory, ParseZon, NegativeIntoUnsigned, TargetTooSmall };

    fn parse(self: *Parser) Error!Config {
        var config = Config{
            .name = "",
            .version = "",
            .fingerprint = 0,
            .minimum_zig_version = "",
            .paths = &.{},
        };

        var has_name = false;
        var has_version = false;
        var has_fingerprint = false;
        var has_minimum_zig_version = false;
        var has_paths = false;

        const r = try self.parseStructLiteral(.root);
        for (r.names, 0..) |n, i| {
            const field_name = n.get(self.zoir);
            const field_value = r.vals.at(@intCast(i));

            if (std.mem.eql(u8, field_name, "name")) {
                has_name = true;
                config.name = try self.parseEnumLiteral(field_value);
            } else if (std.mem.eql(u8, field_name, "version")) {
                has_version = true;
                config.version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "fingerprint")) {
                has_fingerprint = true;
                config.fingerprint = try self.parseT(u64, field_value);
            } else if (std.mem.eql(u8, field_name, "minimum_zig_version")) {
                has_minimum_zig_version = true;
                config.minimum_zig_version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "paths")) {
                has_paths = true;
                config.paths = try self.parseT([][]const u8, field_value);
            } else if (std.mem.eql(u8, field_name, "description")) {
                config.description = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "keywords")) {
                config.keywords = try self.parseT(?[][]const u8, field_value);
            } else if (std.mem.eql(u8, field_name, "dependencies")) {
                config.dependencies = try self.parseHashMap(Dependency, parseDependency, field_value);
            } else if (std.mem.eql(u8, field_name, "write_files")) {
                config.write_files = try self.parseHashMap(WriteFile, parseWriteFile, field_value);
            } else if (std.mem.eql(u8, field_name, "options")) {
                config.options = try self.parseHashMap(Option, parseOption, field_value);
            } else if (std.mem.eql(u8, field_name, "options_modules")) {
                config.options_modules = try self.parseHashMap(OptionsModule, parseOptionsModule, field_value);
            } else if (std.mem.eql(u8, field_name, "modules")) {
                config.modules = try self.parseHashMap(Module, parseModule, field_value);
            } else if (std.mem.eql(u8, field_name, "executables")) {
                config.executables = try self.parseHashMap(Executable, parseExecutable, field_value);
            } else if (std.mem.eql(u8, field_name, "libraries")) {
                config.libraries = try self.parseHashMap(Library, parseLibrary, field_value);
            } else if (std.mem.eql(u8, field_name, "objects")) {
                config.objects = try self.parseHashMap(Object, parseObject, field_value);
            } else if (std.mem.eql(u8, field_name, "tests")) {
                config.tests = try self.parseHashMap(Test, parseTest, field_value);
            } else if (std.mem.eql(u8, field_name, "fmts")) {
                config.fmts = try self.parseHashMap(Fmt, parseFmt, field_value);
            } else if (std.mem.eql(u8, field_name, "runs")) {
                config.runs = try self.parseHashMap(Run, parseRun, field_value);
            } else {
                // Ignore unknown fields — this allows build.zig.zon standard fields
                // that zbuild doesn't use (like Zig-added future fields) to pass through.
            }
        }

        if (!has_name) try self.returnParseError("missing required field 'name'", self.ast.rootDecls()[0]);
        if (!has_version) try self.returnParseError("missing required field 'version'", self.ast.rootDecls()[0]);
        if (!has_fingerprint) try self.returnParseError("missing required field 'fingerprint'", self.ast.rootDecls()[0]);
        if (!has_minimum_zig_version) try self.returnParseError("missing required field 'minimum_zig_version'", self.ast.rootDecls()[0]);
        if (!has_paths) try self.returnParseError("missing required field 'paths'", self.ast.rootDecls()[0]);

        return config;
    }

    // -- Layer 2: HashMap parsing --

    fn parseHashMap(
        self: *Parser,
        comptime V: type,
        comptime parseItem: fn (*Parser, std.zig.Zoir.Node.Index) Error!V,
        index: std.zig.Zoir.Node.Index,
    ) Error!?ArrayHashMap(V) {
        const node = index.get(self.zoir);
        switch (node) {
            .struct_literal => |n| {
                var items = ArrayHashMap(V).init(self.gpa);
                for (n.names, 0..) |name, i| {
                    const field_name = try self.gpa.dupe(u8, name.get(self.zoir));
                    const field_value = n.vals.at(@intCast(i));
                    try items.put(field_name, try parseItem(self, field_value));
                }
                return items;
            },
            .empty_literal => return null,
            else => {
                try self.returnParseError("expected a struct literal", index.getAstNode(self.zoir));
            },
        }
    }

    // -- Layer 3: Types parsed with inline for + fromZoirNode --

    fn parseModule(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Module {
        const n = try self.parseStructLiteral(index);
        var module = Module{};
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "imports")) {
                module.imports = try self.parseStringOrEnumSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "name")) {
                module.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "root_source_file")) {
                module.root_source_file = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "target")) {
                module.target = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "private")) {
                module.private = try self.parseT(bool, field_value);
            } else if (std.mem.eql(u8, field_name, "include_paths")) {
                module.include_paths = try self.parseStringOrEnumSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "link_libraries")) {
                module.link_libraries = try self.parseStringOrEnumSlice(field_value);
            } else {
                inline for (@typeInfo(Module).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field_name, field.name)) {
                        @field(module, field.name) = try self.parseT(field.type, field_value);
                        break;
                    }
                }
            }
        }
        return module;
    }

    fn parseExecutable(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Executable {
        const n = try self.parseStructLiteral(index);
        var exe = Executable{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "root_module")) {
                exe.root_module = try self.parseModuleLink(field_value);
                has_root_module = true;
            } else if (std.mem.eql(u8, field_name, "name")) {
                exe.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "version")) {
                exe.version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "depends_on")) {
                exe.depends_on = try self.parseStringOrEnumSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                exe.zig_lib_dir = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "win32_manifest")) {
                exe.win32_manifest = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "dest_sub_path")) {
                exe.dest_sub_path = try self.parseString(field_value);
            } else {
                inline for (@typeInfo(Executable).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field_name, field.name)) {
                        @field(exe, field.name) = try self.parseT(field.type, field_value);
                        break;
                    }
                }
            }
        }
        if (!has_root_module) try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        return exe;
    }

    fn parseLibrary(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Library {
        const n = try self.parseStructLiteral(index);
        var lib = Library{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "root_module")) {
                lib.root_module = try self.parseModuleLink(field_value);
                has_root_module = true;
            } else if (std.mem.eql(u8, field_name, "name")) {
                lib.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "version")) {
                lib.version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "depends_on")) {
                lib.depends_on = try self.parseStringOrEnumSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                lib.zig_lib_dir = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "win32_manifest")) {
                lib.win32_manifest = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "dest_sub_path")) {
                lib.dest_sub_path = try self.parseString(field_value);
            } else {
                inline for (@typeInfo(Library).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field_name, field.name)) {
                        @field(lib, field.name) = try self.parseT(field.type, field_value);
                        break;
                    }
                }
            }
        }
        if (!has_root_module) try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        return lib;
    }

    fn parseObject(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Object {
        const n = try self.parseStructLiteral(index);
        var obj = Object{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "root_module")) {
                obj.root_module = try self.parseModuleLink(field_value);
                has_root_module = true;
            } else if (std.mem.eql(u8, field_name, "name")) {
                obj.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "depends_on")) {
                obj.depends_on = try self.parseStringOrEnumSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                obj.zig_lib_dir = try self.parseString(field_value);
            } else {
                inline for (@typeInfo(Object).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field_name, field.name)) {
                        @field(obj, field.name) = try self.parseT(field.type, field_value);
                        break;
                    }
                }
            }
        }
        if (!has_root_module) try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        return obj;
    }

    fn parseTest(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Test {
        const n = try self.parseStructLiteral(index);
        var t = Test{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "root_module")) {
                t.root_module = try self.parseModuleLink(field_value);
                has_root_module = true;
            } else if (std.mem.eql(u8, field_name, "name")) {
                t.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "filters")) {
                t.filters = try self.parseStringOrEnumSlice(field_value) orelse &.{};
            } else if (std.mem.eql(u8, field_name, "test_runner")) {
                t.test_runner = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                t.zig_lib_dir = try self.parseString(field_value);
            } else {
                inline for (@typeInfo(Test).@"struct".fields) |field| {
                    if (std.mem.eql(u8, field_name, field.name)) {
                        @field(t, field.name) = try self.parseT(field.type, field_value);
                        break;
                    }
                }
            }
        }
        if (!has_root_module) try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        return t;
    }

    fn parseFmt(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Fmt {
        return try self.parseT(Fmt, index);
    }

    fn parseRun(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Run {
        return try self.parseString(index);
    }

    fn parseWriteFile(self: *Parser, index: std.zig.Zoir.Node.Index) Error!WriteFile {
        const n = try self.parseStructLiteral(index);
        var wf = WriteFile{};
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "private")) {
                wf.private = try self.parseT(bool, field_value);
            } else if (std.mem.eql(u8, field_name, "items")) {
                wf.items = try self.parseHashMap(WriteFile.Path, parseWriteFilePath, field_value);
            }
        }
        return wf;
    }

    fn parseWriteFilePath(self: *Parser, index: std.zig.Zoir.Node.Index) Error!WriteFile.Path {
        const n = try self.parseStructLiteral(index);
        var path_str: ?[]const u8 = null;
        var type_str: ?[]const u8 = null;
        var exclude_extensions: ?[][]const u8 = null;
        var include_extensions: ?[][]const u8 = null;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "type")) {
                type_str = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "path")) {
                path_str = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "exclude_extensions")) {
                exclude_extensions = try self.parseStringOrEnumSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "include_extensions")) {
                include_extensions = try self.parseStringOrEnumSlice(field_value);
            }
        }
        const t = type_str orelse {
            try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
        };
        const p = path_str orelse {
            try self.returnParseError("missing required field 'path'", index.getAstNode(self.zoir));
        };
        if (std.mem.eql(u8, t, "file")) {
            return .{ .file = .{ .type = t, .path = p } };
        } else if (std.mem.eql(u8, t, "dir")) {
            return .{ .dir = .{
                .type = t,
                .path = p,
                .exclude_extensions = exclude_extensions,
                .include_extensions = include_extensions,
            } };
        } else {
            try self.returnParseErrorFmt("invalid write_file type '{s}'", .{t}, index.getAstNode(self.zoir));
        }
    }

    // -- Layer 4: Custom parsers --

    fn parseDependency(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Dependency {
        const n = try self.parseStructLiteral(index);
        var dep = Dependency{ .typ = undefined, .value = undefined };
        var has_type_field = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "path")) {
                dep.typ = .path;
                dep.value = try self.parseString(field_value);
                has_type_field = true;
            } else if (std.mem.eql(u8, field_name, "url")) {
                dep.typ = .url;
                dep.value = try self.parseString(field_value);
                has_type_field = true;
            } else if (std.mem.eql(u8, field_name, "hash")) {
                dep.hash = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "lazy")) {
                dep.lazy = try self.parseT(bool, field_value);
            } else if (std.mem.eql(u8, field_name, "args")) {
                dep.args = try self.parseHashMap(Dependency.Arg, parseDependencyArg, field_value);
            }
        }
        if (!has_type_field) try self.returnParseError("missing required field 'path' or 'url'", index.getAstNode(self.zoir));
        return dep;
    }

    fn parseDependencyArg(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Dependency.Arg {
        const node = index.get(self.zoir);
        switch (node) {
            .true => return .{ .bool = true },
            .false => return .{ .bool = false },
            .int_literal => |i| return .{ .int = switch (i) {
                .small => |s| s,
                .big => |b| try b.toInt(i64),
            } },
            .float_literal => |f| return .{ .float = @floatCast(f) },
            .enum_literal => |e| return .{ .@"enum" = try self.gpa.dupe(u8, e.get(self.zoir)) },
            .string_literal => |s| return .{ .string = try self.gpa.dupe(u8, s) },
            .null => return .{ .null = {} },
            else => try self.returnParseError("expected a bool, int, float, string literal, or enum literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseModuleLink(self: *Parser, index: std.zig.Zoir.Node.Index) Error!ModuleLink {
        const node = index.get(self.zoir);
        switch (node) {
            .struct_literal => return .{ .module = try self.parseModule(index) },
            .string_literal => |n| return .{ .name = try self.gpa.dupe(u8, n) },
            .enum_literal => |n| return .{ .name = try self.gpa.dupe(u8, n.get(self.zoir)) },
            else => try self.returnParseError("expected a string, enum literal, or struct literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseOption(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Option {
        const n = try self.parseStructLiteral(index);
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "type")) {
                const t = try self.parseString(field_value);
                if (Option.isValidIntType(t)) {
                    return .{ .int = try self.parseT(Option.Int, index) };
                } else if (Option.isValidFloatType(t)) {
                    return .{ .float = try self.parseT(Option.Float, index) };
                } else if (std.mem.eql(u8, t, "bool")) {
                    return .{ .bool = try self.parseT(Option.Bool, index) };
                } else if (std.mem.eql(u8, t, "enum")) {
                    return .{ .@"enum" = try self.parseOptionEnum(index) };
                } else if (std.mem.eql(u8, t, "enum_list")) {
                    return .{ .enum_list = try self.parseOptionEnumList(index) };
                } else if (std.mem.eql(u8, t, "string")) {
                    return .{ .string = try self.parseT(Option.String, index) };
                } else if (std.mem.eql(u8, t, "list")) {
                    return .{ .list = try self.parseT(Option.List, index) };
                } else if (std.mem.eql(u8, t, "build_id")) {
                    return .{ .build_id = try self.parseT(Option.BuildId, index) };
                } else if (std.mem.eql(u8, t, "lazy_path")) {
                    return .{ .lazy_path = try self.parseT(Option.LazyPath, index) };
                } else if (std.mem.eql(u8, t, "lazy_path_list")) {
                    return .{ .lazy_path_list = try self.parseT(Option.LazyPathList, index) };
                } else {
                    try self.returnParseErrorFmt("invalid type '{s}'", .{t}, field_value.getAstNode(self.zoir));
                }
            }
        }
        try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
    }

    fn parseOptionEnum(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Option.Enum {
        const n = try self.parseStructLiteral(index);
        var option = Option.Enum{ .enum_options = &.{}, .type = "" };
        var has_type = false;
        var has_enum_options = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "type")) {
                has_type = true;
                option.type = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "enum_options")) {
                has_enum_options = true;
                option.enum_options = try self.parseEnumLiteralSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "description")) {
                option.description = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "default")) {
                option.default = try self.parseEnumLiteral(field_value);
            }
        }
        if (!has_type) try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
        if (!has_enum_options) try self.returnParseError("missing required field 'enum_options'", index.getAstNode(self.zoir));
        return option;
    }

    fn parseOptionEnumList(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Option.EnumList {
        const n = try self.parseStructLiteral(index);
        var option = Option.EnumList{ .enum_options = &.{}, .type = "" };
        var has_type = false;
        var has_enum_options = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "type")) {
                has_type = true;
                option.type = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "enum_options")) {
                has_enum_options = true;
                option.enum_options = try self.parseEnumLiteralSlice(field_value);
            } else if (std.mem.eql(u8, field_name, "description")) {
                option.description = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "default")) {
                option.default = try self.parseEnumLiteralSlice(field_value);
            }
        }
        if (!has_type) try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
        if (!has_enum_options) try self.returnParseError("missing required field 'enum_options'", index.getAstNode(self.zoir));
        return option;
    }

    fn parseOptionsModule(self: *Parser, index: std.zig.Zoir.Node.Index) Error!OptionsModule {
        return (try self.parseHashMap(Option, parseOption, index)) orelse ArrayHashMap(Option).init(self.gpa);
    }

    // -- Primitives --

    fn parseT(self: *Parser, comptime T: type, index: std.zig.Zoir.Node.Index) Error!T {
        @setEvalBranchQuota(2_000);
        self.status.* = .{};
        return try std.zon.parse.fromZoirNode(T, self.gpa, self.ast, self.zoir, index, self.status, .{});
    }

    fn parseString(self: *Parser, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .string_literal => |n| return try self.gpa.dupe(u8, n),
            else => try self.returnParseError("expected a string literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseEnumLiteral(self: *Parser, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .enum_literal => |n| return try self.gpa.dupe(u8, n.get(self.zoir)),
            else => try self.returnParseError("expected an enum literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseVersionString(self: *Parser, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .string_literal => |n| {
                _ = std.SemanticVersion.parse(n) catch {
                    try self.returnParseError("invalid version string", index.getAstNode(self.zoir));
                };
                return try self.gpa.dupe(u8, n);
            },
            else => try self.returnParseError("expected a string literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseStringOrEnumSlice(self: *Parser, index: std.zig.Zoir.Node.Index) Error!?[][]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .array_literal => |a| {
                const slice = try self.gpa.alloc([]const u8, a.len);
                for (0..a.len) |i| {
                    const item = a.at(@intCast(i));
                    const item_node = item.get(self.zoir);
                    slice[i] = switch (item_node) {
                        .string_literal => |s| try self.gpa.dupe(u8, s),
                        .enum_literal => |e| try self.gpa.dupe(u8, e.get(self.zoir)),
                        else => {
                            try self.returnParseError("expected string or enum literal", item.getAstNode(self.zoir));
                        },
                    };
                }
                return slice;
            },
            .empty_literal => return null,
            else => try self.returnParseError("expected an array literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseEnumLiteralSlice(self: *Parser, index: std.zig.Zoir.Node.Index) Error![][]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .array_literal => |a| {
                const slice = try self.gpa.alloc([]const u8, a.len);
                for (0..a.len) |i| {
                    const item = a.at(@intCast(i));
                    slice[i] = try self.parseEnumLiteral(item);
                }
                return slice;
            },
            else => try self.returnParseError("expected an array literal", index.getAstNode(self.zoir)),
        }
    }

    fn parseStructLiteral(self: *Parser, index: std.zig.Zoir.Node.Index) Error!std.meta.TagPayload(std.zig.Zoir.Node, .struct_literal) {
        const node = index.get(self.zoir);
        switch (node) {
            .struct_literal => |n| return n,
            else => try self.returnParseError("expected a struct literal", index.getAstNode(self.zoir)),
        }
    }

    fn returnParseErrorFmt(self: *Parser, comptime fmt: []const u8, args: anytype, node_index: std.zig.Ast.Node.Index) Error!noreturn {
        const message = try std.fmt.allocPrint(self.gpa, fmt, args);
        self.status.* = .{
            .ast = self.ast,
            .zoir = self.zoir,
            .type_check = .{
                .message = message,
                .owned = true,
                .token = self.ast.firstToken(node_index),
                .offset = 0,
                .note = null,
            },
        };
        return error.ParseZon;
    }

    fn returnParseError(self: *Parser, message: []const u8, node_index: std.zig.Ast.Node.Index) Error!noreturn {
        self.status.* = .{
            .ast = self.ast,
            .zoir = self.zoir,
            .type_check = .{
                .message = message,
                .owned = false,
                .token = self.ast.firstToken(node_index),
                .offset = 0,
                .note = null,
            },
        };
        return error.ParseZon;
    }
};

pub fn serialize(config: Config, writer: anytype) !void {
    var serializer = Serializer(@TypeOf(writer)).init(config, writer);
    try serializer.serialize();
}

pub fn serializeToFile(config: Config, file_path: []const u8) !void {
    const file = try std.fs.cwd().createFile(file_path, .{});
    defer file.close();
    try serialize(config, file.writer());
}

fn Serializer(Writer: type) type {
    return struct {
        config: Config,
        writer: Writer,

        const Self = @This();

        pub fn init(config: Config, writer: Writer) Self {
            return Self{
                .config = config,
                .writer = writer,
            };
        }

        pub fn serialize(self: *Self) !void {
            var serializer = std.zon.stringify.serializer(self.writer, .{});
            var top_level = try serializer.beginStruct(.{});
            try top_level.field("name", self.config.name, .{});
            try top_level.field("version", self.config.version, .{});
            try top_level.fieldPrefix("fingerprint");
            try self.writer.print("0x{x:0>16}", .{self.config.fingerprint});
            try top_level.field("minimum_zig_version", self.config.minimum_zig_version, .{});
            try top_level.field("paths", self.config.paths, .{});
            if (self.config.description) |desc| {
                try top_level.field("description", desc, .{});
            }
            if (self.config.keywords) |keywords| {
                try top_level.field("keywords", keywords, .{});
            }
            if (self.config.dependencies) |dependencies| {
                var deps = try top_level.beginStructField("dependencies", .{});
                for (dependencies.keys(), dependencies.values()) |name, item| {
                    try serializeDependency(&deps, name, item);
                }
                try deps.end();
            }
            if (self.config.write_files) |write_files| {
                var wf = try top_level.beginStructField("write_files", .{});
                for (write_files.keys(), write_files.values()) |name, item| {
                    try serializeWriteFile(&wf, name, item);
                }
                try wf.end();
            }
            if (self.config.options) |options| {
                var opts = try top_level.beginStructField("options", .{});
                for (options.keys(), options.values()) |name, item| {
                    try serializeOption(&opts, name, item);
                }
                try opts.end();
            }
            if (self.config.options_modules) |options_modules| {
                var opt_modules = try top_level.beginStructField("options_modules", .{});
                for (options_modules.keys(), options_modules.values()) |opt_module_name, opt_module| {
                    var opts = try opt_modules.beginStructField(opt_module_name, .{});
                    for (opt_module.keys(), opt_module.values()) |name, item| {
                        try serializeOption(&opts, name, item);
                    }
                    try opts.end();
                }
                try opt_modules.end();
            }
            if (self.config.modules) |modules| {
                var mods = try top_level.beginStructField("modules", .{});
                for (modules.keys(), modules.values()) |name, item| {
                    try serializeModule(&mods, name, item);
                }
                try mods.end();
            }
            if (self.config.executables) |executables| {
                var exes = try top_level.beginStructField("executables", .{});
                for (executables.keys(), executables.values()) |name, item| {
                    try serializeExecutable(&exes, name, item);
                }
                try exes.end();
            }
            if (self.config.libraries) |libraries| {
                var libs = try top_level.beginStructField("libraries", .{});
                for (libraries.keys(), libraries.values()) |name, item| {
                    try serializeLibrary(&libs, name, item);
                }
                try libs.end();
            }
            if (self.config.objects) |objects| {
                var objs = try top_level.beginStructField("objects", .{});
                for (objects.keys(), objects.values()) |name, item| {
                    try serializeObject(&objs, name, item);
                }
                try objs.end();
            }
            if (self.config.tests) |tests_map| {
                var tsts = try top_level.beginStructField("tests", .{});
                for (tests_map.keys(), tests_map.values()) |name, item| {
                    try serializeTest(&tsts, name, item);
                }
                try tsts.end();
            }
            if (self.config.fmts) |fmts| {
                var f = try top_level.beginStructField("fmts", .{});
                for (fmts.keys(), fmts.values()) |name, item| {
                    try f.field(name, item, .{ .emit_default_optional_fields = false });
                }
                try f.end();
            }
            if (self.config.runs) |runs| {
                var r = try top_level.beginStructField("runs", .{});
                for (runs.keys(), runs.values()) |name, item| {
                    try r.field(name, item, .{});
                }
                try r.end();
            }
            try top_level.end();
        }

        fn serializeDependency(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Dependency,
        ) !void {
            var inner = try outer.beginStructField(name, .{});
            switch (item.typ) {
                .path => try inner.field("path", item.value, .{}),
                .url => try inner.field("url", item.value, .{}),
            }
            if (item.hash) |hash| {
                try inner.field("hash", hash, .{});
            }
            if (item.lazy) |lazy| {
                try inner.field("lazy", lazy, .{});
            }
            if (item.args) |args| {
                var args_inner = try inner.beginStructField("args", .{});
                for (args.keys(), args.values()) |arg_name, arg_value| {
                    switch (arg_value) {
                        .bool => |b| {
                            try args_inner.field(arg_name, b, .{});
                        },
                        .int => |i| {
                            try args_inner.field(arg_name, i, .{});
                        },
                        .float => |f| {
                            try args_inner.field(arg_name, f, .{});
                        },
                        .string => |s| {
                            try args_inner.field(arg_name, s, .{});
                        },
                        .@"enum" => |e| {
                            try args_inner.fieldPrefix(arg_name);
                            try args_inner.container.serializer.writer.print(".{}", .{std.zig.fmtId(e)});
                        },
                        .null => {
                            try args_inner.field(arg_name, null, .{});
                        },
                    }
                }
                try args_inner.end();
            }
            try inner.end();
        }

        fn serializeWriteFile(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: WriteFile,
        ) !void {
            var inner = try outer.beginStructField(name, .{});
            if (item.private) |p| {
                try inner.field("private", p, .{});
            }
            if (item.items) |items| {
                var items_struct = try inner.beginStructField("items", .{});
                for (items.keys(), items.values()) |item_name, item_value| {
                    var item_struct = try items_struct.beginStructField(item_name, .{});
                    switch (item_value) {
                        .file => |f| {
                            try item_struct.field("type", f.type, .{});
                            try item_struct.field("path", f.path, .{});
                        },
                        .dir => |d| {
                            try item_struct.field("type", d.type, .{});
                            try item_struct.field("path", d.path, .{});
                            if (d.exclude_extensions) |exclude_extensions| {
                                try item_struct.field("exclude_extensions", exclude_extensions, .{});
                            }
                            if (d.include_extensions) |include_extensions| {
                                try item_struct.field("include_extensions", include_extensions, .{});
                            }
                        },
                    }
                    try item_struct.end();
                }
                try items_struct.end();
            }
            try inner.end();
        }

        fn serializeOption(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Option,
        ) !void {
            switch (item) {
                .int => |i| {
                    try outer.field(name, i, .{ .emit_default_optional_fields = false });
                },
                .float => |f| {
                    try outer.field(name, f, .{ .emit_default_optional_fields = false });
                },
                .bool => |b| {
                    try outer.field(name, b, .{ .emit_default_optional_fields = false });
                },
                .@"enum" => |e| {
                    var inner = try outer.beginStructField(name, .{});
                    try inner.field("type", e.type, .{});
                    if (e.description) |desc| {
                        try inner.field("description", desc, .{});
                    }
                    if (e.default) |default| {
                        try inner.fieldPrefix("default");
                        try inner.container.serializer.writer.print(".{}", .{std.zig.fmtId(default)});
                    }
                    var opts_arr = try inner.beginArrayField("enum_options", .{});
                    for (e.enum_options) |opt| {
                        try opts_arr.fieldPrefix();
                        try opts_arr.container.serializer.writer.print(".{}", .{std.zig.fmtId(opt)});
                    }
                    try opts_arr.end();
                    try inner.end();
                },
                .enum_list => |el| {
                    var inner = try outer.beginStructField(name, .{});
                    try inner.field("type", el.type, .{});
                    if (el.description) |desc| {
                        try inner.field("description", desc, .{});
                    }
                    if (el.default) |defaults| {
                        var default_arr = try inner.beginArrayField("default", .{});
                        for (defaults) |d| {
                            try default_arr.fieldPrefix();
                            try default_arr.container.serializer.writer.print(".{}", .{std.zig.fmtId(d)});
                        }
                        try default_arr.end();
                    }
                    var opts_arr = try inner.beginArrayField("enum_options", .{});
                    for (el.enum_options) |opt| {
                        try opts_arr.fieldPrefix();
                        try opts_arr.container.serializer.writer.print(".{}", .{std.zig.fmtId(opt)});
                    }
                    try opts_arr.end();
                    try inner.end();
                },
                .string => |s| {
                    try outer.field(name, s, .{ .emit_default_optional_fields = false });
                },
                .list => |l| {
                    try outer.field(name, l, .{ .emit_default_optional_fields = false });
                },
                .build_id => |b| {
                    try outer.field(name, b, .{ .emit_default_optional_fields = false });
                },
                .lazy_path => |lp| {
                    try outer.field(name, lp, .{ .emit_default_optional_fields = false });
                },
                .lazy_path_list => |lpl| {
                    try outer.field(name, lpl, .{ .emit_default_optional_fields = false });
                },
            }
        }

        fn serializeModule(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Module,
        ) !void {
            try outer.field(name, item, .{ .emit_default_optional_fields = false });
        }

        fn serializeExecutable(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Executable,
        ) !void {
            var inner = try outer.beginStructField(name, .{});
            if (item.name) |n| {
                try inner.field("name", n, .{});
            }
            if (item.version) |version| {
                try inner.field("version", version, .{});
            }
            switch (item.root_module) {
                .name => |n| {
                    try inner.field("root_module", n, .{});
                },
                .module => |m| {
                    try serializeModule(&inner, "root_module", m);
                },
            }
            if (item.linkage) |linkage| {
                try inner.field("linkage", linkage, .{});
            }
            if (item.max_rss) |max_rss| {
                try inner.field("max_rss", max_rss, .{});
            }
            if (item.use_llvm) |use_llvm| {
                try inner.field("use_llvm", use_llvm, .{});
            }
            if (item.use_lld) |use_lld| {
                try inner.field("use_lld", use_lld, .{});
            }
            if (item.zig_lib_dir) |zig_lib_dir| {
                try inner.field("zig_lib_dir", zig_lib_dir, .{});
            }
            if (item.win32_manifest) |win32_manifest| {
                try inner.field("win32_manifest", win32_manifest, .{});
            }
            if (item.depends_on) |depends_on| {
                try inner.field("depends_on", depends_on, .{});
            }
            try inner.end();
        }

        fn serializeLibrary(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Library,
        ) !void {
            var inner = try outer.beginStructField(name, .{});
            if (item.name) |n| {
                try inner.field("name", n, .{});
            }
            if (item.version) |version| {
                try inner.field("version", version, .{});
            }
            switch (item.root_module) {
                .name => |n| {
                    try inner.field("root_module", n, .{});
                },
                .module => |m| {
                    try serializeModule(&inner, "root_module", m);
                },
            }
            if (item.linkage) |linkage| {
                try inner.field("linkage", linkage, .{});
            }
            if (item.max_rss) |max_rss| {
                try inner.field("max_rss", max_rss, .{});
            }
            if (item.use_llvm) |use_llvm| {
                try inner.field("use_llvm", use_llvm, .{});
            }
            if (item.use_lld) |use_lld| {
                try inner.field("use_lld", use_lld, .{});
            }
            if (item.zig_lib_dir) |zig_lib_dir| {
                try inner.field("zig_lib_dir", zig_lib_dir, .{});
            }
            if (item.win32_manifest) |win32_manifest| {
                try inner.field("win32_manifest", win32_manifest, .{});
            }
            if (item.linker_allow_shlib_undefined) |v| {
                try inner.field("linker_allow_shlib_undefined", v, .{});
            }
            if (item.dest_sub_path) |dest_sub_path| {
                try inner.field("dest_sub_path", dest_sub_path, .{});
            }
            if (item.depends_on) |depends_on| {
                try inner.field("depends_on", depends_on, .{});
            }
            try inner.end();
        }

        fn serializeObject(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Object,
        ) !void {
            var inner = try outer.beginStructField(name, .{});
            if (item.name) |n| {
                try inner.field("name", n, .{});
            }
            switch (item.root_module) {
                .name => |n| {
                    try inner.field("root_module", n, .{});
                },
                .module => |m| {
                    try serializeModule(&inner, "root_module", m);
                },
            }
            if (item.max_rss) |max_rss| {
                try inner.field("max_rss", max_rss, .{});
            }
            if (item.use_llvm) |use_llvm| {
                try inner.field("use_llvm", use_llvm, .{});
            }
            if (item.use_lld) |use_lld| {
                try inner.field("use_lld", use_lld, .{});
            }
            if (item.zig_lib_dir) |zig_lib_dir| {
                try inner.field("zig_lib_dir", zig_lib_dir, .{});
            }
            if (item.depends_on) |depends_on| {
                try inner.field("depends_on", depends_on, .{});
            }
            try inner.end();
        }

        fn serializeTest(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Test,
        ) !void {
            var inner = try outer.beginStructField(name, .{});
            if (item.name) |n| {
                try inner.field("name", n, .{});
            }
            switch (item.root_module) {
                .name => |n| {
                    try inner.field("root_module", n, .{});
                },
                .module => |m| {
                    try serializeModule(&inner, "root_module", m);
                },
            }
            if (item.max_rss) |max_rss| {
                try inner.field("max_rss", max_rss, .{});
            }
            if (item.use_llvm) |use_llvm| {
                try inner.field("use_llvm", use_llvm, .{});
            }
            if (item.use_lld) |use_lld| {
                try inner.field("use_lld", use_lld, .{});
            }
            if (item.zig_lib_dir) |zig_lib_dir| {
                try inner.field("zig_lib_dir", zig_lib_dir, .{});
            }
            if (item.filters.len > 0) {
                try inner.field("filters", item.filters, .{});
            }
            if (item.test_runner) |test_runner| {
                try inner.field("test_runner", test_runner, .{});
            }
            try inner.end();
        }
    };
}

// -- Tests --

fn testParse(source: [:0]const u8) !Config {
    const gpa = std.testing.allocator;

    var ast = try std.zig.Ast.parse(gpa, source, .zon);
    defer ast.deinit(gpa);

    var zoir = try std.zig.ZonGen.generate(gpa, ast, .{});
    defer zoir.deinit(gpa);

    if (zoir.hasCompileErrors()) return error.ParseZoir;

    return parseFromZoir(gpa, "<test>", zoir, ast, null);
}

fn testParseFail(source: [:0]const u8) !void {
    const gpa = std.testing.allocator;

    var ast = try std.zig.Ast.parse(gpa, source, .zon);
    defer ast.deinit(gpa);

    var zoir = try std.zig.ZonGen.generate(gpa, ast, .{});
    defer zoir.deinit(gpa);

    if (zoir.hasCompileErrors()) return; // expected failure

    _ = parseFromZoir(gpa, "<test>", zoir, ast, null) catch return;
    return error.ExpectedParseFailure;
}

test "parse minimal config" {
    const config = try testParse(
        \\.{
        \\    .name = .basic,
        \\    .version = "0.1.0",
        \\    .fingerprint = 0x90797553773ca567,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\}
    );
    try std.testing.expectEqualStrings("basic", config.name);
    try std.testing.expectEqualStrings("0.1.0", config.version);
    try std.testing.expectEqual(@as(u64, 0x90797553773ca567), config.fingerprint);
    try std.testing.expectEqualStrings("0.14.0", config.minimum_zig_version);
    try std.testing.expectEqual(@as(usize, 1), config.paths.len);
    try std.testing.expectEqualStrings("src", config.paths[0]);

    // Optional fields should be null
    try std.testing.expect(config.description == null);
    try std.testing.expect(config.modules == null);
    try std.testing.expect(config.executables == null);
    try std.testing.expect(config.dependencies == null);
}

test "parse config with module" {
    const config = try testParse(
        \\.{
        \\    .name = .mylib,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x1234567890abcdef,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .modules = .{
        \\        .core = .{
        \\            .root_source_file = "src/core.zig",
        \\            .link_libc = true,
        \\            .optimize = .ReleaseFast,
        \\        },
        \\    },
        \\}
    );

    const modules = config.modules orelse return error.ExpectedModules;
    try std.testing.expectEqual(@as(usize, 1), modules.count());
    const core = modules.get("core") orelse return error.ExpectedCoreModule;
    try std.testing.expectEqualStrings("src/core.zig", core.root_source_file.?);
    try std.testing.expectEqual(true, core.link_libc.?);
    try std.testing.expectEqual(std.builtin.OptimizeMode.ReleaseFast, core.optimize.?);
    try std.testing.expect(core.strip == null);
    try std.testing.expect(core.target == null);
}

test "parse config with executable and inline module" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "0.2.0",
        \\    .fingerprint = 0xabcdef1234567890,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .executables = .{
        \\        .main = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/main.zig",
        \\            },
        \\        },
        \\    },
        \\}
    );

    const exes = config.executables orelse return error.ExpectedExecutables;
    try std.testing.expectEqual(@as(usize, 1), exes.count());
    const main_exe = exes.get("main") orelse return error.ExpectedMainExe;
    try std.testing.expectEqual(ModuleLink.module, std.meta.activeTag(main_exe.root_module));
    try std.testing.expectEqualStrings("src/main.zig", main_exe.root_module.module.root_source_file.?);
}

test "parse config with executable referencing named module" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "0.2.0",
        \\    .fingerprint = 0xabcdef1234567890,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .executables = .{
        \\        .main = .{
        \\            .root_module = .core,
        \\        },
        \\    },
        \\}
    );

    const exes = config.executables orelse return error.ExpectedExecutables;
    const main_exe = exes.get("main") orelse return error.ExpectedMainExe;
    try std.testing.expectEqual(ModuleLink.name, std.meta.activeTag(main_exe.root_module));
    try std.testing.expectEqualStrings("core", main_exe.root_module.name);
}

test "parse config with dependency" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "0.1.0",
        \\    .fingerprint = 0x1111111111111111,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .dependencies = .{
        \\        .zlib = .{
        \\            .url = "https://example.com/zlib.tar.gz",
        \\            .hash = "abc123",
        \\            .lazy = true,
        \\        },
        \\        .local_dep = .{
        \\            .path = "../other",
        \\        },
        \\    },
        \\}
    );

    const deps = config.dependencies orelse return error.ExpectedDependencies;
    try std.testing.expectEqual(@as(usize, 2), deps.count());

    const zlib = deps.get("zlib") orelse return error.ExpectedZlib;
    try std.testing.expect(zlib.typ == .url);
    try std.testing.expectEqualStrings("https://example.com/zlib.tar.gz", zlib.value);
    try std.testing.expectEqualStrings("abc123", zlib.hash.?);
    try std.testing.expectEqual(true, zlib.lazy.?);

    const local = deps.get("local_dep") orelse return error.ExpectedLocalDep;
    try std.testing.expect(local.typ == .path);
    try std.testing.expectEqualStrings("../other", local.value);
    try std.testing.expect(local.hash == null);
    try std.testing.expect(local.lazy == null);
}

test "parse config with library" {
    const config = try testParse(
        \\.{
        \\    .name = .mylib,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x2222222222222222,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .libraries = .{
        \\        .mylib = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/lib.zig",
        \\            },
        \\            .version = "2.0.0",
        \\            .linkage = .dynamic,
        \\        },
        \\    },
        \\}
    );

    const libs = config.libraries orelse return error.ExpectedLibraries;
    const lib = libs.get("mylib") orelse return error.ExpectedMylib;
    try std.testing.expectEqualStrings("2.0.0", lib.version.?);
    try std.testing.expectEqual(std.builtin.LinkMode.dynamic, lib.linkage.?);
}

test "parse config with test section" {
    const config = try testParse(
        \\.{
        \\    .name = .mylib,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x3333333333333333,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .tests = .{
        \\        .unit = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/test.zig",
        \\            },
        \\            .filters = .{"specific_test"},
        \\        },
        \\    },
        \\}
    );

    const tests = config.tests orelse return error.ExpectedTests;
    const unit = tests.get("unit") orelse return error.ExpectedUnit;
    try std.testing.expectEqual(@as(usize, 1), unit.filters.len);
    try std.testing.expectEqualStrings("specific_test", unit.filters[0]);
}

test "parse config with runs" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x4444444444444444,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .runs = .{
        \\        .docs = "echo 'hello'",
        \\    },
        \\}
    );

    const runs = config.runs orelse return error.ExpectedRuns;
    const docs = runs.get("docs") orelse return error.ExpectedDocs;
    try std.testing.expectEqualStrings("echo 'hello'", docs.*);
}

test "parse config with options" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x5555555555555555,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .options = .{
        \\        .verbose = .{
        \\            .type = "bool",
        \\            .default = false,
        \\            .description = "Enable verbose output",
        \\        },
        \\        .threads = .{
        \\            .type = "usize",
        \\            .default = 4,
        \\        },
        \\    },
        \\}
    );

    const opts = config.options orelse return error.ExpectedOptions;
    try std.testing.expectEqual(@as(usize, 2), opts.count());

    const verbose = opts.get("verbose") orelse return error.ExpectedVerbose;
    try std.testing.expect(verbose == .bool);
    try std.testing.expectEqual(false, verbose.bool.default.?);

    const threads = opts.get("threads") orelse return error.ExpectedThreads;
    try std.testing.expect(threads == .int);
    try std.testing.expectEqual(@as(i64, 4), threads.int.default.?);
}

test "parse config with options_modules" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x6666666666666666,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .options_modules = .{
        \\        .build_options = .{
        \\            .debug_mode = .{
        \\                .type = "bool",
        \\                .default = false,
        \\            },
        \\        },
        \\    },
        \\}
    );

    const opt_modules = config.options_modules orelse return error.ExpectedOptionsModules;
    try std.testing.expectEqual(@as(usize, 1), opt_modules.count());
    const build_opts = opt_modules.get("build_options") orelse return error.ExpectedBuildOptions;
    try std.testing.expectEqual(@as(usize, 1), build_opts.count());
}

test "parse config with module imports" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x7777777777777777,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .modules = .{
        \\        .core = .{
        \\            .root_source_file = "src/core.zig",
        \\            .imports = .{ .utils, "other_dep" },
        \\        },
        \\    },
        \\}
    );

    const modules = config.modules orelse return error.ExpectedModules;
    const core = modules.get("core") orelse return error.ExpectedCore;
    const imports = core.imports orelse return error.ExpectedImports;
    try std.testing.expectEqual(@as(usize, 2), imports.len);
    try std.testing.expectEqualStrings("utils", imports[0]);
    try std.testing.expectEqualStrings("other_dep", imports[1]);
}

test "parse fails on missing required field" {
    try testParseFail(
        \\.{
        \\    .name = .basic,
        \\    .version = "0.1.0",
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\}
    );
}

test "parse fails on invalid version string" {
    try testParseFail(
        \\.{
        \\    .name = .basic,
        \\    .version = "not_a_version",
        \\    .fingerprint = 0x1234567890abcdef,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\}
    );
}

test "parse config with description and keywords" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x8888888888888888,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .description = "A test application",
        \\    .keywords = .{ "test", "app" },
        \\}
    );

    try std.testing.expectEqualStrings("A test application", config.description.?);
    const keywords = config.keywords.?;
    try std.testing.expectEqual(@as(usize, 2), keywords.len);
    try std.testing.expectEqualStrings("test", keywords[0]);
    try std.testing.expectEqualStrings("app", keywords[1]);
}

test "parse config with dependency args" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x9999999999999999,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .dependencies = .{
        \\        .dep = .{
        \\            .path = "../dep",
        \\            .args = .{
        \\                .enable_feature = true,
        \\                .count = 42,
        \\                .name = "hello",
        \\            },
        \\        },
        \\    },
        \\}
    );

    const deps = config.dependencies orelse return error.ExpectedDeps;
    const dep = deps.get("dep") orelse return error.ExpectedDep;
    const args = dep.args orelse return error.ExpectedArgs;
    try std.testing.expectEqual(@as(usize, 3), args.count());

    const enable = args.get("enable_feature") orelse return error.ExpectedArg;
    try std.testing.expect(enable == .bool);
    try std.testing.expectEqual(true, enable.bool);
}

test "parse config with fmts" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0xaaaaaaaaaaaaaaaa,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .fmts = .{
        \\        .check = .{
        \\            .paths = .{"src"},
        \\            .check = true,
        \\        },
        \\    },
        \\}
    );

    const fmts = config.fmts orelse return error.ExpectedFmts;
    const check = fmts.get("check") orelse return error.ExpectedCheck;
    try std.testing.expectEqual(true, check.check.?);
    const fmt_paths = check.paths orelse return error.ExpectedPaths;
    try std.testing.expectEqual(@as(usize, 1), fmt_paths.len);
}

// -- Serializer round-trip tests --

fn testSerializeRoundTrip(source: [:0]const u8) !void {
    const gpa = std.testing.allocator;

    // Phase 1: Parse original
    const config = try testParse(source);

    // Phase 2: Serialize to string
    var buf = std.ArrayList(u8).init(gpa);
    defer buf.deinit();
    try serialize(config, buf.writer());

    // Phase 3: Re-parse the serialized output
    const serialized = try buf.toOwnedSliceSentinel(0);
    defer gpa.free(serialized);

    const config2 = try testParse(serialized);

    // Phase 4: Compare key fields
    try std.testing.expectEqualStrings(config.name, config2.name);
    try std.testing.expectEqualStrings(config.version, config2.version);
    try std.testing.expectEqual(config.fingerprint, config2.fingerprint);
    try std.testing.expectEqualStrings(config.minimum_zig_version, config2.minimum_zig_version);
    try std.testing.expectEqual(config.paths.len, config2.paths.len);

    // Compare optional sections presence
    try std.testing.expectEqual(config.modules != null, config2.modules != null);
    try std.testing.expectEqual(config.executables != null, config2.executables != null);
    try std.testing.expectEqual(config.libraries != null, config2.libraries != null);
    try std.testing.expectEqual(config.objects != null, config2.objects != null);
    try std.testing.expectEqual(config.tests != null, config2.tests != null);
    try std.testing.expectEqual(config.fmts != null, config2.fmts != null);
    try std.testing.expectEqual(config.runs != null, config2.runs != null);
    try std.testing.expectEqual(config.dependencies != null, config2.dependencies != null);

    // Compare counts where present
    if (config.modules) |m| try std.testing.expectEqual(m.count(), config2.modules.?.count());
    if (config.executables) |e| try std.testing.expectEqual(e.count(), config2.executables.?.count());
    if (config.libraries) |l| try std.testing.expectEqual(l.count(), config2.libraries.?.count());
    if (config.tests) |t| try std.testing.expectEqual(t.count(), config2.tests.?.count());
    if (config.runs) |r| try std.testing.expectEqual(r.count(), config2.runs.?.count());
    if (config.dependencies) |d| try std.testing.expectEqual(d.count(), config2.dependencies.?.count());
}

test "serialize round-trip: minimal config" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .basic,
        \\    .version = "0.1.0",
        \\    .fingerprint = 0x90797553773ca567,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\}
    );
}

test "serialize round-trip: config with modules" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .mylib,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x1234567890abcdef,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .modules = .{
        \\        .core = .{
        \\            .root_source_file = "src/core.zig",
        \\            .link_libc = true,
        \\        },
        \\    },
        \\}
    );
}

test "serialize round-trip: config with executables" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .myapp,
        \\    .version = "0.2.0",
        \\    .fingerprint = 0xabcdef1234567890,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .executables = .{
        \\        .main = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/main.zig",
        \\            },
        \\        },
        \\    },
        \\}
    );
}

test "serialize round-trip: config with libraries" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .mylib,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x2222222222222222,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .libraries = .{
        \\        .mylib = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/lib.zig",
        \\            },
        \\            .version = "2.0.0",
        \\        },
        \\    },
        \\}
    );
}

test "serialize round-trip: config with tests" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .mylib,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x3333333333333333,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .tests = .{
        \\        .unit = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/test.zig",
        \\            },
        \\        },
        \\    },
        \\}
    );
}

test "serialize round-trip: config with runs" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0x4444444444444444,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .runs = .{
        \\        .docs = "echo hello",
        \\    },
        \\}
    );
}

test "serialize round-trip: config with dependencies including hash and lazy" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .myapp,
        \\    .version = "0.1.0",
        \\    .fingerprint = 0x1111111111111111,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .dependencies = .{
        \\        .zlib = .{
        \\            .url = "https://example.com/zlib.tar.gz",
        \\            .hash = "abc123",
        \\            .lazy = true,
        \\        },
        \\    },
        \\}
    );
}

test "parse config with depends_on" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0xbbbbbbbbbbbbbbbb,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .executables = .{
        \\        .server = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/server.zig",
        \\            },
        \\            .depends_on = .{ .proto_lib },
        \\        },
        \\    },
        \\    .libraries = .{
        \\        .proto_lib = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/proto.zig",
        \\            },
        \\        },
        \\    },
        \\}
    );

    const exes = config.executables orelse return error.ExpectedExes;
    const server = exes.get("server") orelse return error.ExpectedServer;
    const depends_on = server.depends_on orelse return error.ExpectedDependsOn;
    try std.testing.expectEqual(@as(usize, 1), depends_on.len);
    try std.testing.expectEqualStrings("proto_lib", depends_on[0]);
}

test "serialize round-trip: config with depends_on" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0xbbbbbbbbbbbbbbbb,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .executables = .{
        \\        .server = .{
        \\            .root_module = .{
        \\                .root_source_file = "src/server.zig",
        \\            },
        \\            .depends_on = .{ .proto_lib },
        \\        },
        \\    },
        \\}
    );
}

test "serialize round-trip: config with fmts" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0xaaaaaaaaaaaaaaaa,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .fmts = .{
        \\        .check = .{
        \\            .paths = .{"src"},
        \\            .check = true,
        \\        },
        \\    },
        \\}
    );
}

test "parse config with write_files" {
    const config = try testParse(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0xcccccccccccccccc,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .write_files = .{
        \\        .generated = .{
        \\            .items = .{
        \\                .config_h = .{
        \\                    .type = "file",
        \\                    .path = "config.h",
        \\                },
        \\                .assets = .{
        \\                    .type = "dir",
        \\                    .path = "assets",
        \\                    .exclude_extensions = .{".tmp"},
        \\                },
        \\            },
        \\        },
        \\    },
        \\}
    );

    const wf = config.write_files orelse return error.ExpectedWriteFiles;
    const generated = wf.get("generated") orelse return error.ExpectedGenerated;
    const items = generated.items orelse return error.ExpectedItems;
    try std.testing.expectEqual(@as(usize, 2), items.count());

    const config_h = items.get("config_h") orelse return error.ExpectedConfigH;
    try std.testing.expect(config_h == .file);
    try std.testing.expectEqualStrings("config.h", config_h.file.path);

    const assets = items.get("assets") orelse return error.ExpectedAssets;
    try std.testing.expect(assets == .dir);
    try std.testing.expectEqualStrings("assets", assets.dir.path);
    const excl = assets.dir.exclude_extensions orelse return error.ExpectedExclude;
    try std.testing.expectEqual(@as(usize, 1), excl.len);
    try std.testing.expectEqualStrings(".tmp", excl[0]);
}

test "serialize round-trip: config with write_files" {
    try testSerializeRoundTrip(
        \\.{
        \\    .name = .myapp,
        \\    .version = "1.0.0",
        \\    .fingerprint = 0xcccccccccccccccc,
        \\    .minimum_zig_version = "0.14.0",
        \\    .paths = .{"src"},
        \\    .write_files = .{
        \\        .generated = .{
        \\            .items = .{
        \\                .config_h = .{
        \\                    .type = "file",
        \\                    .path = "config.h",
        \\                },
        \\            },
        \\        },
        \\    },
        \\}
    );
}
