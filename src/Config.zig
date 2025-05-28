//! Configuration file (aka `zbuild.zon`) format for the Zig build system.
//! This file is meant to be a superset of the `build.zig.zon` manifest file format.

const std = @import("std");
const ArrayHashMap = std.StringArrayHashMap;

const Config = @This();

name: []const u8,
version: []const u8,
fingerprint: []const u8,
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

pub const Dependency = union(enum) {
    path: Path,
    url: Url,

    pub const Path = struct {
        path: []const u8,
        hash: ?[]const u8 = null,
        lazy: ?bool = null,
    };

    pub const Url = struct {
        url: []const u8,
        hash: ?[]const u8 = null,
        lazy: ?bool = null,
    };

    pub fn deinit(self: *Dependency, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .path => |*p| {
                gpa.free(p.path);
                if (p.hash) |h| gpa.free(h);
            },
            .url => |*u| {
                gpa.free(u.url);
                if (u.hash) |h| gpa.free(h);
            },
        }
    }
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

    pub fn deinit(self: *Option, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .bool,
            => |b| {
                gpa.free(b.type);
                if (b.description) |d| gpa.free(d);
            },
            .int => |i| {
                gpa.free(i.type);
                if (i.description) |d| gpa.free(d);
            },
            .float => |f| {
                gpa.free(f.type);
                if (f.description) |d| gpa.free(d);
            },
            .@"enum" => |e| {
                gpa.free(e.type);
                if (e.description) |d| gpa.free(d);
                for (e.enum_options) |eo| gpa.free(eo);
                gpa.free(e.enum_options);
                if (e.default) |d| gpa.free(d);
            },
            .enum_list => |e| {
                gpa.free(e.type);
                if (e.description) |d| gpa.free(d);
                for (e.enum_options) |eo| gpa.free(eo);
                gpa.free(e.enum_options);
                if (e.default) |d| {
                    for (d) |dd| gpa.free(dd);
                    gpa.free(d);
                }
            },
            .string,
            => |s| {
                gpa.free(s.type);
                if (s.description) |d| gpa.free(d);
                if (s.default) |d| gpa.free(d);
            },
            .build_id => |s| {
                gpa.free(s.type);
                if (s.description) |d| gpa.free(d);
                if (s.default) |d| gpa.free(d);
            },
            .lazy_path => |s| {
                gpa.free(s.type);
                if (s.description) |d| gpa.free(d);
                if (s.default) |d| gpa.free(d);
            },
            .list => |l| {
                gpa.free(l.type);
                if (l.description) |d| gpa.free(d);
                if (l.default) |d| {
                    for (d) |dd| gpa.free(dd);
                    gpa.free(d);
                }
            },
            .lazy_path_list => |l| {
                gpa.free(l.type);
                if (l.description) |d| gpa.free(d);
                if (l.default) |d| {
                    for (d) |dd| gpa.free(dd);
                    gpa.free(d);
                }
            },
        }
    }

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

    pub fn deinit(self: *WriteFile, gpa: std.mem.Allocator) void {
        if (self.items) |*i| {
            for (i.values()) |*v| {
                switch (v.*) {
                    .file => |f| {
                        gpa.free(f.type);
                        gpa.free(f.path);
                    },
                    .dir => |d| {
                        gpa.free(d.type);
                        gpa.free(d.path);
                        if (d.exclude_extensions) |e| {
                            for (e) |ee| gpa.free(ee);
                            gpa.free(e);
                        }
                        if (d.include_extensions) |e| {
                            for (e) |ee| gpa.free(ee);
                            gpa.free(e);
                        }
                    },
                }
            }
            for (i.keys()) |k| gpa.free(k);
            i.deinit();
        }
    }
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

    pub fn deinit(self: *Module, gpa: std.mem.Allocator) void {
        if (self.name) |n| gpa.free(n);
        if (self.root_source_file) |r| gpa.free(r);
        if (self.imports) |i| {
            for (i) |ii| gpa.free(ii);
            gpa.free(i);
        }
        if (self.target) |t| gpa.free(t);
    }
};

pub const ModuleLink = union(enum) {
    name: []const u8,
    module: Module,

    pub fn deinit(self: *ModuleLink, gpa: std.mem.Allocator) void {
        switch (self.*) {
            .name => |n| gpa.free(n),
            .module => |*m| m.deinit(gpa),
        }
    }
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

    depends_on: ?[][]const u8 = null,

    pub fn deinit(self: *Executable, gpa: std.mem.Allocator) void {
        if (self.name) |n| gpa.free(n);
        if (self.version) |v| gpa.free(v);
        self.root_module.deinit(gpa);
        if (self.zig_lib_dir) |z| gpa.free(z);
        if (self.win32_manifest) |w| gpa.free(w);
        if (self.depends_on) |d| {
            for (d) |dd| gpa.free(dd);
            gpa.free(d);
        }
    }
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

    pub fn deinit(self: *Library, gpa: std.mem.Allocator) void {
        if (self.name) |n| gpa.free(n);
        if (self.version) |v| gpa.free(v);
        self.root_module.deinit(gpa);
        if (self.zig_lib_dir) |z| gpa.free(z);
        if (self.win32_manifest) |w| gpa.free(w);
        if (self.depends_on) |d| {
            for (d) |dd| gpa.free(dd);
            gpa.free(d);
        }
    }
};

pub const Object = struct {
    name: ?[]const u8 = null,
    root_module: ModuleLink,
    max_rss: ?usize = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?[]const u8 = null,

    depends_on: ?[][]const u8 = null,

    pub fn deinit(self: *Object, gpa: std.mem.Allocator) void {
        if (self.name) |n| gpa.free(n);
        self.root_module.deinit(gpa);
        if (self.zig_lib_dir) |z| gpa.free(z);
        if (self.depends_on) |d| {
            for (d) |dd| gpa.free(dd);
            gpa.free(d);
        }
    }
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

    pub fn deinit(self: *Test, gpa: std.mem.Allocator) void {
        if (self.name) |n| gpa.free(n);
        self.root_module.deinit(gpa);
        if (self.zig_lib_dir) |z| gpa.free(z);
        for (self.filters) |f| gpa.free(f);
        gpa.free(self.filters);
        if (self.test_runner) |t| gpa.free(t);
    }
};

pub const Fmt = struct {
    paths: ?[][]const u8 = null,
    exclude_paths: ?[][]const u8 = null,
    check: ?bool = false,

    pub fn deinit(self: *Fmt, gpa: std.mem.Allocator) void {
        if (self.paths) |p| {
            for (p) |pp| gpa.free(pp);
            gpa.free(p);
        }
        if (self.exclude_paths) |e| {
            for (e) |ee| gpa.free(ee);
            gpa.free(e);
        }
    }
};

pub const Run = []const u8;

pub fn deinit(config: *Config, gpa: std.mem.Allocator) void {
    gpa.free(config.name);
    gpa.free(config.version);
    gpa.free(config.fingerprint);
    gpa.free(config.minimum_zig_version);
    for (config.paths) |path| gpa.free(path);
    gpa.free(config.paths);
    if (config.description) |desc| gpa.free(desc);
    if (config.keywords) |kws| {
        for (kws) |kw| gpa.free(kw);
        gpa.free(kws);
    }

    if (config.write_files) |*wfs| {
        for (wfs.values()) |*wf| wf.deinit(gpa);
        for (wfs.keys()) |k| gpa.free(k);
        wfs.deinit();
    }
    if (config.options) |*opts| {
        for (opts.values()) |*o| o.deinit(gpa);
        for (opts.keys()) |k| gpa.free(k);
        opts.deinit();
    }
    if (config.options_modules) |*opts| {
        for (opts.values()) |*o| {
            for (o.values()) |*oo| oo.deinit(gpa);
            for (o.keys()) |k| gpa.free(k);
            o.deinit();
        }
        for (opts.keys()) |k| gpa.free(k);
        opts.deinit();
    }
    if (config.modules) |*mods| {
        for (mods.values()) |*m| m.deinit(gpa);
        for (mods.keys()) |k| gpa.free(k);
        mods.deinit();
    }
    if (config.dependencies) |*deps| {
        for (deps.values()) |*d| d.deinit(gpa);
        for (deps.keys()) |k| gpa.free(k);
        deps.deinit();
    }
    if (config.executables) |*execs| {
        for (execs.values()) |*e| e.deinit(gpa);
        for (execs.keys()) |k| gpa.free(k);
        execs.deinit();
    }
    if (config.libraries) |*libs| {
        for (libs.values()) |*l| l.deinit(gpa);
        for (libs.keys()) |k| gpa.free(k);
        libs.deinit();
    }
    if (config.objects) |*objs| {
        for (objs.values()) |*o| o.deinit(gpa);
        for (objs.keys()) |k| gpa.free(k);
        objs.deinit();
    }
    if (config.tests) |*tests| {
        for (tests.values()) |*t| t.deinit(gpa);
        for (tests.keys()) |k| gpa.free(k);
        tests.deinit();
    }
    if (config.fmts) |*fmts| {
        for (fmts.values()) |*f| f.deinit(gpa);
        for (fmts.keys()) |k| gpa.free(k);
        fmts.deinit();
    }
    if (config.runs) |*runs| {
        for (runs.values()) |r| gpa.free(r);
        for (runs.keys()) |k| gpa.free(k);
        runs.deinit();
    }
    config.* = undefined;
}

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
    var parser = Parser.init(gpa, zoir, ast, &status);

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
    config: Config,

    const Self = @This();

    pub const Error = error{ OutOfMemory, ParseZon };

    pub fn init(gpa: std.mem.Allocator, zoir: std.zig.Zoir, ast: std.zig.Ast, status: *std.zon.parse.Status) Parser {
        return Parser{
            .gpa = gpa,
            .zoir = zoir,
            .ast = ast,
            .status = status,
            .config = Config{
                .name = "",
                .version = "",
                .fingerprint = "",
                .minimum_zig_version = "",
                .paths = &.{},
            },
        };
    }

    pub fn parse(self: *Self) Error!Config {
        // required fields
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
                self.config.name = try self.parseEnumLiteral(field_value);
            } else if (std.mem.eql(u8, field_name, "version")) {
                has_version = true;
                self.config.version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "fingerprint")) {
                has_fingerprint = true;
                const fingerprint_int = try self.parseT(u64, field_value);
                self.config.fingerprint = try std.fmt.allocPrint(self.gpa, "0x{x}", .{fingerprint_int});
            } else if (std.mem.eql(u8, field_name, "minimum_zig_version")) {
                has_minimum_zig_version = true;
                self.config.minimum_zig_version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "paths")) {
                has_paths = true;
                self.config.paths = try self.parseT([][]const u8, field_value);
            } else if (std.mem.eql(u8, field_name, "description")) {
                self.config.description = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "keywords")) {
                self.config.keywords = try self.parseT(?[][]const u8, field_value);
            } else if (std.mem.eql(u8, field_name, "dependencies")) {
                self.config.dependencies = try self.parseOptionalHashMap(Dependency, parseDependency, field_value);
            } else if (std.mem.eql(u8, field_name, "write_files")) {
                // config.write_files = ;
            } else if (std.mem.eql(u8, field_name, "options")) {
                self.config.options = try self.parseOptionalHashMap(Option, parseOption, field_value);
            } else if (std.mem.eql(u8, field_name, "options_modules")) {
                self.config.options_modules = try self.parseOptionalHashMap(OptionsModule, parseOptionsModule, field_value);
            } else if (std.mem.eql(u8, field_name, "modules")) {
                self.config.modules = try self.parseOptionalHashMap(Module, parseModule, field_value);
            } else if (std.mem.eql(u8, field_name, "executables")) {
                self.config.executables = try self.parseOptionalHashMap(Executable, parseExecutable, field_value);
            } else if (std.mem.eql(u8, field_name, "libraries")) {
                self.config.libraries = try self.parseOptionalHashMap(Library, parseLibrary, field_value);
            } else if (std.mem.eql(u8, field_name, "objects")) {
                self.config.objects = try self.parseOptionalHashMap(Object, parseObject, field_value);
            } else if (std.mem.eql(u8, field_name, "tests")) {
                self.config.tests = try self.parseOptionalHashMap(Test, parseTest, field_value);
            } else if (std.mem.eql(u8, field_name, "fmts")) {
                self.config.fmts = try self.parseOptionalHashMap(Fmt, parseFmt, field_value);
            } else if (std.mem.eql(u8, field_name, "runs")) {
                self.config.runs = try self.parseOptionalHashMap(Run, parseRun, field_value);
            } else {
                try self.returnParseErrorFmt("unknown field '{s}'", .{field_name}, field_value.getAstNode(self.zoir));
            }
        }
        if (!has_name) {
            try self.returnParseError("missing required field 'name'", self.ast.rootDecls()[0]);
        }
        if (!has_version) {
            try self.returnParseError("missing required field 'version'", self.ast.rootDecls()[0]);
        }
        if (!has_fingerprint) {
            try self.returnParseError("missing required field 'fingerprint'", self.ast.rootDecls()[0]);
        }
        if (!has_minimum_zig_version) {
            try self.returnParseError("missing required field 'minimum_zig_version'", self.ast.rootDecls()[0]);
        }
        if (!has_paths) {
            try self.returnParseError("missing required field 'paths'", self.ast.rootDecls()[0]);
        }
        return self.config;
    }

    fn parseDependency(self: *Self, index: std.zig.Zoir.Node.Index) Error!Dependency {
        const n = try self.parseStructLiteral(index);
        for (n.names) |name| {
            const field_name = name.get(self.zoir);
            if (std.mem.eql(u8, field_name, "path")) {
                return .{ .path = try self.parseT(Dependency.Path, index) };
            } else if (std.mem.eql(u8, field_name, "url")) {
                return .{ .url = try self.parseT(Dependency.Url, index) };
            }
        }
        try self.returnParseError("missing required field 'path' or 'url'", index.getAstNode(self.zoir));
    }

    fn parseWriteFile(self: *Self, index: std.zig.Zoir.Node.Index) Error!WriteFile {
        const n = try self.parseStructLiteral(index);
        var write_file = WriteFile{};
        for (n.names) |name| {
            const field_name = name.get(self.zoir);
            if (std.mem.eql(u8, field_name, "private")) {
                write_file.private = try self.parseT(?bool);
            } else if (std.mem.eql(u8, field_name, "items")) {
                write_file.items = try self.parseOptionalHashMap(WriteFile.Path, parseWriteFilePath, index);
            }
        }
        return write_file;
    }

    fn parseWriteFilePath(self: *Self, index: std.zig.Zoir.Node.Index) Error!WriteFile.Path {
        const n = try self.parseStructLiteral(index);
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "type")) {
                const t = try self.parseString(field_value);
                if (std.mem.eql(u8, t, "file")) {
                    return .{ .file = try self.parseT(WriteFile.File) };
                } else if (std.mem.eql(u8, t, "dir")) {
                    return .{ .dir = try self.parseT(WriteFile.Dir) };
                } else {
                    try self.returnParseErrorFmt("invalid type '{s}'", .{t}, field_value);
                }
            }
        }
        try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
    }

    fn parseOption(self: *Self, index: std.zig.Zoir.Node.Index) Error!Option {
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

    fn parseOptionEnum(self: *Self, index: std.zig.Zoir.Node.Index) Error!Option.Enum {
        const n = try self.parseStructLiteral(index);
        var option = Option.Enum{
            .enum_options = &.{},
            .type = "",
        };
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
                option.enum_options = try self.parseSlice([]const u8, parseEnumLiteral, field_value);
            } else if (std.mem.eql(u8, field_name, "description")) {
                option.description = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "default")) {
                option.default = try self.parseEnumLiteral(field_value);
            }
        }
        if (!has_type) {
            try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
        }
        if (!has_enum_options) {
            try self.returnParseError("missing required field 'enum_options'", index.getAstNode(self.zoir));
        }
        return option;
    }

    fn parseOptionEnumList(self: *Self, index: std.zig.Zoir.Node.Index) Error!Option.EnumList {
        const n = try self.parseStructLiteral(index);
        var option = Option.EnumList{
            .enum_options = &.{},
            .type = "",
        };
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
                option.enum_options = try self.parseSlice([]const u8, parseEnumLiteral, field_value);
            } else if (std.mem.eql(u8, field_name, "description")) {
                option.description = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "default")) {
                option.default = try self.parseSlice([]const u8, parseEnumLiteral, field_value);
            }
        }
        if (!has_type) {
            try self.returnParseError("missing required field 'type'", index.getAstNode(self.zoir));
        }
        if (!has_enum_options) {
            try self.returnParseError("missing required field 'enum_options'", index.getAstNode(self.zoir));
        }
        return option;
    }

    fn parseOptionsModule(self: *Self, index: std.zig.Zoir.Node.Index) Error!OptionsModule {
        return try self.parseHashMap(Option, parseOption, index);
    }

    fn parseModule(self: *Self, index: std.zig.Zoir.Node.Index) Error!Module {
        const n = try self.parseStructLiteral(index);
        var module = Module{};
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            // each field in Module
            if (std.mem.eql(u8, field_name, "name")) {
                module.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "root_source_file")) {
                module.root_source_file = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "imports")) {
                module.imports = try self.parseOptionalSlice([]const u8, parseStringOrEnumLiteral, field_value);
            } else if (std.mem.eql(u8, field_name, "private")) {
                module.private = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "target")) {
                module.target = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "optimize")) {
                module.optimize = try self.parseT(std.builtin.OptimizeMode, field_value);
            } else if (std.mem.eql(u8, field_name, "link_libc")) {
                module.link_libc = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "link_libcpp")) {
                module.link_libcpp = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "single_threaded")) {
                module.single_threaded = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "strip")) {
                module.strip = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "unwind_tables")) {
                module.unwind_tables = try self.parseT(std.builtin.UnwindTables, field_value);
            } else if (std.mem.eql(u8, field_name, "dwarf_format")) {
                module.dwarf_format = try self.parseT(std.dwarf.Format, field_value);
            } else if (std.mem.eql(u8, field_name, "code_model")) {
                module.code_model = try self.parseT(std.builtin.CodeModel, field_value);
            } else if (std.mem.eql(u8, field_name, "stack_protector")) {
                module.stack_protector = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "stack_check")) {
                module.stack_check = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "sanitize_c")) {
                module.sanitize_c = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "sanitize_thread")) {
                module.sanitize_thread = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "fuzz")) {
                module.fuzz = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "valgrind")) {
                module.valgrind = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "pic")) {
                module.pic = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "red_zone")) {
                module.red_zone = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "omit_frame_pointer")) {
                module.omit_frame_pointer = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "error_tracing")) {
                module.error_tracing = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "include_paths")) {
                module.include_paths = try self.parseOptionalSlice([]const u8, parseString, field_value);
            }
        }
        return module;
    }

    fn parseModuleLink(self: *Self, index: std.zig.Zoir.Node.Index) Error!ModuleLink {
        const node = index.get(self.zoir);
        switch (node) {
            .struct_literal => {
                return .{ .module = try self.parseModule(index) };
            },
            .string_literal => |n| {
                return .{ .name = try self.gpa.dupe(u8, n) };
            },
            .enum_literal => |n| {
                return .{ .name = try self.gpa.dupe(u8, n.get(self.zoir)) };
            },
            else => {
                try self.returnParseError("expected a string, enum literal, struct literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseExecutable(self: *Self, index: std.zig.Zoir.Node.Index) Error!Executable {
        const n = try self.parseStructLiteral(index);
        var executable = Executable{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "name")) {
                executable.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "version")) {
                executable.version = try self.parseVersionString(field_value);
            } else if (std.mem.eql(u8, field_name, "root_module")) {
                executable.root_module = try self.parseModuleLink(field_value);
                has_root_module = true;
            } else if (std.mem.eql(u8, field_name, "linkage")) {
                executable.linkage = try self.parseT(std.builtin.LinkMode, field_value);
            } else if (std.mem.eql(u8, field_name, "max_rss")) {
                executable.max_rss = try self.parseT(usize, field_value);
            } else if (std.mem.eql(u8, field_name, "use_llvm")) {
                executable.use_llvm = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "use_lld")) {
                executable.use_lld = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                executable.zig_lib_dir = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "win32_manifest")) {
                executable.win32_manifest = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "depends_on")) {
                executable.depends_on = try self.parseOptionalSlice([]const u8, parseStringOrEnumLiteral, field_value);
            }
        }
        if (!has_root_module) {
            try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        }
        return executable;
    }

    fn parseLibrary(self: *Self, index: std.zig.Zoir.Node.Index) Error!Library {
        const n = try self.parseStructLiteral(index);
        var library = Library{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "name")) {
                library.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "root_module")) {
                has_root_module = true;
                library.root_module = try self.parseModuleLink(field_value);
            } else if (std.mem.eql(u8, field_name, "linkage")) {
                library.linkage = try self.parseT(std.builtin.LinkMode, field_value);
            } else if (std.mem.eql(u8, field_name, "max_rss")) {
                library.max_rss = try self.parseT(usize, field_value);
            } else if (std.mem.eql(u8, field_name, "use_llvm")) {
                library.use_llvm = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "use_lld")) {
                library.use_lld = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                library.zig_lib_dir = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "win32_manifest")) {
                library.win32_manifest = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "depends_on")) {
                library.depends_on = try self.parseOptionalSlice([]const u8, parseStringOrEnumLiteral, field_value);
            }
        }
        if (!has_root_module) {
            try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        }
        return library;
    }

    fn parseObject(self: *Self, index: std.zig.Zoir.Node.Index) Error!Object {
        const n = try self.parseStructLiteral(index);
        var object = Object{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = try self.gpa.dupe(u8, name.get(self.zoir));
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "name")) {
                object.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "root_module")) {
                has_root_module = true;
                object.root_module = try self.parseModuleLink(field_value);
            } else if (std.mem.eql(u8, field_name, "max_rss")) {
                object.max_rss = try self.parseT(usize, field_value);
            } else if (std.mem.eql(u8, field_name, "use_llvm")) {
                object.use_llvm = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "use_lld")) {
                object.use_lld = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                object.zig_lib_dir = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "depends_on")) {
                object.depends_on = try self.parseOptionalSlice([]const u8, parseStringOrEnumLiteral, field_value);
            }
        }
        if (!has_root_module) {
            try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        }
        return object;
    }

    fn parseTest(self: *Self, index: std.zig.Zoir.Node.Index) Error!Test {
        const n = try self.parseStructLiteral(index);
        var t = Test{ .root_module = .{ .name = "" } };
        var has_root_module = false;
        for (n.names, 0..) |name, i| {
            const field_name = name.get(self.zoir);
            const field_value = n.vals.at(@intCast(i));
            if (std.mem.eql(u8, field_name, "name")) {
                t.name = try self.parseString(field_value);
            } else if (std.mem.eql(u8, field_name, "root_module")) {
                has_root_module = true;
                t.root_module = try self.parseModuleLink(field_value);
            } else if (std.mem.eql(u8, field_name, "max_rss")) {
                t.max_rss = try self.parseT(usize, field_value);
            } else if (std.mem.eql(u8, field_name, "use_llvm")) {
                t.use_llvm = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "use_lld")) {
                t.use_lld = try self.parseBool(field_value);
            } else if (std.mem.eql(u8, field_name, "zig_lib_dir")) {
                t.zig_lib_dir = try self.parseString(field_value);
            }
        }
        if (!has_root_module) {
            try self.returnParseError("missing required field 'root_module'", index.getAstNode(self.zoir));
        }
        return t;
    }

    fn parseFmt(self: *Self, index: std.zig.Zoir.Node.Index) Error!Fmt {
        return try self.parseT(Fmt, index);
    }

    fn parseRun(self: *Self, index: std.zig.Zoir.Node.Index) Error!Run {
        return try self.parseT(Run, index);
    }

    fn parseHashMap(
        self: *Self,
        comptime T: type,
        comptime parseItem: fn (self: *Self, index: std.zig.Zoir.Node.Index) Error!T,
        index: std.zig.Zoir.Node.Index,
    ) Error!ArrayHashMap(T) {
        const n = try self.parseStructLiteral(index);
        var items = ArrayHashMap(T).init(self.gpa);
        for (n.names, 0..) |name, i| {
            const field_name = try self.gpa.dupe(u8, name.get(self.zoir));
            const field_value = n.vals.at(@intCast(i));
            const item = try parseItem(self, field_value);
            try items.put(field_name, item);
        }
        return items;
    }

    fn parseOptionalHashMap(
        self: *Self,
        comptime T: type,
        comptime parseItem: fn (self: *Self, index: std.zig.Zoir.Node.Index) Error!T,
        index: std.zig.Zoir.Node.Index,
    ) Error!?ArrayHashMap(T) {
        const node = index.get(self.zoir);
        switch (node) {
            .struct_literal => |n| {
                var items = ArrayHashMap(T).init(self.gpa);
                for (n.names, 0..) |name, i| {
                    const field_name = try self.gpa.dupe(u8, name.get(self.zoir));
                    const field_value = n.vals.at(@intCast(i));
                    const item = try parseItem(self, field_value);
                    try items.put(field_name, item);
                }
                return items;
            },
            .empty_literal => {
                return null;
            },
            else => {
                try self.returnParseError("expected a struct literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseSlice(
        self: *Self,
        comptime T: type,
        comptime parseItem: fn (self: *Self, index: std.zig.Zoir.Node.Index) Error!T,
        index: std.zig.Zoir.Node.Index,
    ) Error![]T {
        const node = index.get(self.zoir);
        switch (node) {
            .array_literal => |a| {
                const slice = try self.gpa.alloc(T, a.len);
                for (0..a.len) |i| {
                    const item = a.at(@intCast(i));
                    slice[i] = try parseItem(self, item);
                }
                return slice;
            },
            else => {
                try self.returnParseError("expected an array literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseOptionalSlice(
        self: *Self,
        comptime T: type,
        comptime parseItem: fn (self: *Self, index: std.zig.Zoir.Node.Index) Error!T,
        index: std.zig.Zoir.Node.Index,
    ) Error!?[]T {
        const node = index.get(self.zoir);
        switch (node) {
            .array_literal => |a| {
                const slice = try self.gpa.alloc(T, a.len);
                for (0..a.len) |i| {
                    const item = a.at(@intCast(i));
                    slice[i] = try parseItem(self, item);
                }
                return slice;
            },
            .empty_literal => {
                return null;
            },
            else => {
                try self.returnParseError("expected an array literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseT(self: *Self, comptime T: type, index: std.zig.Zoir.Node.Index) Error!T {
        @setEvalBranchQuota(2_000);
        self.status.* = .{};
        return try std.zon.parse.fromZoirNode(T, self.gpa, self.ast, self.zoir, index, self.status, .{});
    }

    fn parseEnumLiteral(self: *Self, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .enum_literal => |n| {
                return try self.gpa.dupe(u8, n.get(self.zoir));
            },
            else => {
                try self.returnParseError("expected an enum literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseString(self: *Self, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .string_literal => |n| {
                return try self.gpa.dupe(u8, n);
            },
            else => {
                try self.returnParseError("expected a string literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseStringOrEnumLiteral(self: *Self, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .string_literal => |n| {
                return try self.gpa.dupe(u8, n);
            },
            .enum_literal => |n| {
                return try self.gpa.dupe(u8, n.get(self.zoir));
            },
            else => {
                try self.returnParseError("expected a string literal or enum literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseVersionString(self: *Self, index: std.zig.Zoir.Node.Index) Error![]const u8 {
        const node = index.get(self.zoir);
        switch (node) {
            .string_literal => |n| {
                _ = std.SemanticVersion.parse(n) catch {
                    try self.returnParseError("invalid version string", index.getAstNode(self.zoir));
                };
                return try self.gpa.dupe(u8, n);
            },
            else => {
                try self.returnParseError("expected an string literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseBool(self: *Self, index: std.zig.Zoir.Node.Index) Error!bool {
        const node = index.get(self.zoir);
        switch (node) {
            .true => {
                return true;
            },
            .false => {
                return false;
            },
            else => {
                try self.returnParseError("expected a boolean literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn parseStructLiteral(self: *Self, index: std.zig.Zoir.Node.Index) Error!std.meta.TagPayload(std.zig.Zoir.Node, .struct_literal) {
        const node = index.get(self.zoir);
        switch (node) {
            .struct_literal => |n| {
                return n;
            },
            else => {
                try self.returnParseError("expected a struct literal", index.getAstNode(self.zoir));
            },
        }
    }

    fn returnParseErrorFmt(self: *Self, comptime fmt: []const u8, args: anytype, node_index: std.zig.Ast.Node.Index) Error!noreturn {
        const message = try std.fmt.allocPrint(self.gpa, fmt, args);
        try self.returnParseError(message, node_index);
    }

    fn returnParseError(self: *Self, message: []const u8, node_index: std.zig.Ast.Node.Index) Error!noreturn {
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
            try self.writer.print("0x{x}", .{self.config.fingerprint});
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
            // if (self.config.libraries) |libraries| {
            //     const libs = try top_level.beginStructField("libraries", .{});
            //     for (libraries.keys(), libraries.values()) |name, item| {
            //         try self.serializeLibrary(libs, name, item);
            //     }
            //     try libs.end();
            // }
            // if (self.config.objects) |objects| {
            //     const objs = try top_level.beginStructField("objects", .{});
            //     for (objects.keys(), objects.values()) |name, item| {
            //         try self.serializeObject(objs, name, item);
            //     }
            //     try objs.end();
            // }
            // if (self.config.tests) |tests| {
            //     const tsts = try top_level.beginStructField("tests", .{});
            //     for (tests.keys(), tests.values()) |name, item| {
            //         try self.serializeTest(tsts, name, item);
            //     }
            //     try tsts.end();
            // }
            // if (self.config.fmts) |fmts| {
            //     const f = try top_level.beginStructField("fmts", .{});
            //     for (fmts.keys(), fmts.values()) |name, item| {
            //         try self.serializeFmt(f, name, item);
            //     }
            //     try f.end();
            // }
            // if (self.config.runs) |runs| {
            //     const r = try top_level.beginStructField("runs", .{});
            //     for (runs.keys(), runs.values()) |name, item| {
            //         try self.serializeRun(r, name, item);
            //     }
            //     try r.end();
            // }
            try top_level.end();
        }

        fn serializeDependency(
            outer: *std.zon.stringify.Serializer(Writer).Struct,
            name: []const u8,
            item: Dependency,
        ) !void {
            switch (item) {
                .path => |p| {
                    try outer.field(name, p, .{ .emit_default_optional_fields = false });
                },
                .url => |u| {
                    try outer.field(name, u, .{ .emit_default_optional_fields = false });
                },
            }
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
                    _ = e;
                    // TODO
                    // try opts.field(name, e, .{ .emit_default_optional_fields = false });
                },
                .enum_list => |el| {
                    _ = el;
                    // TODO
                    // try opts.field(name, el, .{ .emit_default_optional_fields = false });
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
    };
}

test {
    const gpa = std.testing.allocator;
    var status = std.zon.parse.Status{};
    var config = Config.parseFromFile(gpa, "foo.zon", &status) catch |err| {
        try status.format("error: {s}", .{}, std.io.getStdErr().writer());
        return err;
    };
    defer config.deinit(gpa);
    defer status.deinit(gpa);

    std.debug.print("{any}\n", .{config});

    // Check that the required fields are set
    // try std.testing.expect(config.name != null);
    // try std.testing.expect(config.version != null);
    // try std.testing.expect(config.fingerprint != null);
    // try std.testing.expect(config.minimum_zig_version != null);
}
