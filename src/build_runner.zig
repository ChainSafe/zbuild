//! Configures a Zig build graph from a comptime ZON manifest.
//!
//! The manifest is obtained via @import("build.zig.zon") in the user's build.zig:
//!
//!     const zbuild = @import("zbuild");
//!
//!     pub fn build(b: *std.Build) void {
//!         zbuild.configureBuild(b, @import("build.zig.zon")) catch |err| {
//!             std.log.err("zbuild: {}", .{err});
//!         };
//!     }

const std = @import("std");

pub fn configureBuild(b: *std.Build, comptime manifest: anytype) !void {
    comptime validateManifest(manifest);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var runner = BuildRunner{
        .b = b,
        .target = target,
        .optimize = optimize,
        .modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
        .dependencies = std.StringHashMap(*std.Build.Dependency).init(b.allocator),
        .options_modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
        .install_steps = std.StringHashMap(*std.Build.Step).init(b.allocator),
    };

    // Phase 1: Resolve dependencies (comptime args forwarding)
    if (@hasField(@TypeOf(manifest), "dependencies")) {
        inline for (@typeInfo(@TypeOf(manifest.dependencies)).@"struct".fields) |field| {
            const decl = @field(manifest.dependencies, field.name);
            const dep = if (@hasField(@TypeOf(decl), "args"))
                b.dependency(field.name, decl.args)
            else
                b.dependency(field.name, .{});
            try runner.dependencies.put(field.name, dep);
        }
    }

    // Phase 2: Create options modules
    if (@hasField(@TypeOf(manifest), "options_modules")) {
        inline for (@typeInfo(@TypeOf(manifest.options_modules)).@"struct".fields) |field| {
            try runner.createOptionsModule(field.name, @field(manifest.options_modules, field.name));
        }
    }

    // Phase 3: Create named modules
    if (@hasField(@TypeOf(manifest), "modules")) {
        inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
            const mod = @field(manifest.modules, field.name);
            const m = runner.createModule(mod, field.name);
            const is_private = @hasField(@TypeOf(mod), "private") and mod.private;
            if (!is_private) {
                b.modules.put(b.dupe(field.name), m) catch @panic("OOM");
            }
        }
    }

    // Phase 4: Create executables
    if (@hasField(@TypeOf(manifest), "executables")) {
        inline for (@typeInfo(@TypeOf(manifest.executables)).@"struct".fields) |field| {
            try runner.createExecutable(field.name, @field(manifest.executables, field.name));
        }
    }

    // Phase 5: Create libraries
    if (@hasField(@TypeOf(manifest), "libraries")) {
        inline for (@typeInfo(@TypeOf(manifest.libraries)).@"struct".fields) |field| {
            try runner.createLibrary(field.name, @field(manifest.libraries, field.name));
        }
    }

    // Phase 6: Create objects
    if (@hasField(@TypeOf(manifest), "objects")) {
        inline for (@typeInfo(@TypeOf(manifest.objects)).@"struct".fields) |field| {
            try runner.createObject(field.name, @field(manifest.objects, field.name));
        }
    }

    // Phase 7: Create tests
    if (@hasField(@TypeOf(manifest), "tests")) {
        const tls_run_test = b.step("test", "Run all tests");
        inline for (@typeInfo(@TypeOf(manifest.tests)).@"struct".fields) |field| {
            try runner.createTest(field.name, @field(manifest.tests, field.name), tls_run_test);
        }
    }

    // Phase 8: Create fmts
    if (@hasField(@TypeOf(manifest), "fmts")) {
        const tls_run_fmt = b.step("fmt", "Run all fmts");
        inline for (@typeInfo(@TypeOf(manifest.fmts)).@"struct".fields) |field| {
            runner.createFmt(field.name, @field(manifest.fmts, field.name), tls_run_fmt);
        }
    }

    // Phase 9: Create runs
    if (@hasField(@TypeOf(manifest), "runs")) {
        inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
            runner.createRun(field.name, @field(manifest.runs, field.name));
        }
    }

    // Phase 10: Wire imports
    try runner.wireAllImports(manifest);

    // Phase 11: Wire depends_on
    runner.wireDependsOn(manifest);
}

// --- Manifest validation ---
//
// Cross-reference checks run at comptime so typos in module names,
// dependency references, and artifact names become compile errors.

fn validateManifest(comptime manifest: anytype) void {
    // Validate root_module name references point to declared modules
    inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
        if (@hasField(@TypeOf(manifest), section)) {
            inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                const item = @field(@field(manifest, section), field.name);
                validateRootModuleRef(manifest, item.root_module, section, field.name);
            }
        }
    }

    // Validate depends_on references point to declared artifacts
    inline for (.{ "executables", "libraries", "objects" }) |section| {
        if (@hasField(@TypeOf(manifest), section)) {
            inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                const item = @field(@field(manifest, section), field.name);
                if (@hasField(@TypeOf(item), "depends_on")) {
                    validateDependsOn(manifest, item.depends_on, section, field.name);
                }
            }
        }
    }

    // Validate imports reference declared modules, options_modules, or dependencies
    if (@hasField(@TypeOf(manifest), "modules")) {
        inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
            const mod = @field(manifest.modules, field.name);
            if (@hasField(@TypeOf(mod), "imports")) {
                validateImports(manifest, mod.imports, "modules", field.name);
            }
        }
    }
    inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
        if (@hasField(@TypeOf(manifest), section)) {
            inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                const item = @field(@field(manifest, section), field.name);
                if (@typeInfo(@TypeOf(item.root_module)) == .@"struct") {
                    if (@hasField(@TypeOf(item.root_module), "imports")) {
                        validateImports(manifest, item.root_module.imports, section, field.name);
                    }
                }
            }
        }
    }

    // Validate runs fields
    if (@hasField(@TypeOf(manifest), "runs")) {
        inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
            const run = @field(manifest.runs, field.name);
            if (@hasField(@TypeOf(run), "cmd")) {
                // Long form — validate depends_on and stdin/stdin_file exclusion
                if (@hasField(@TypeOf(run), "depends_on")) {
                    validateDependsOn(manifest, run.depends_on, "runs", field.name);
                }
                if (@hasField(@TypeOf(run), "stdin") and @hasField(@TypeOf(run), "stdin_file")) {
                    @compileError("runs '" ++ field.name ++ "': stdin and stdin_file are mutually exclusive");
                }
            }
        }
    }
}

fn validateRootModuleRef(comptime manifest: anytype, comptime root_module: anytype, comptime section: []const u8, comptime name: []const u8) void {
    const ti = @typeInfo(@TypeOf(root_module));
    const ref_name = if (ti == .enum_literal)
        @tagName(root_module)
    else if (ti == .pointer)
        @as([]const u8, root_module)
    else
        return; // struct = inline module, nothing to cross-reference

    if (!hasModule(manifest, ref_name)) {
        @compileError(section ++ " '" ++ name ++ "': root_module references unknown module '" ++ ref_name ++ "'");
    }
}

fn validateDependsOn(comptime manifest: anytype, comptime deps: anytype, comptime section: []const u8, comptime name: []const u8) void {
    inline for (@typeInfo(@TypeOf(deps)).@"struct".fields) |field| {
        const dep_name = toComptimeString(@field(deps, field.name));
        if (!hasArtifact(manifest, dep_name)) {
            @compileError(section ++ " '" ++ name ++ "': depends_on references unknown artifact '" ++ dep_name ++ "'");
        }
    }
}

fn validateImports(comptime manifest: anytype, comptime imports: anytype, comptime section: []const u8, comptime name: []const u8) void {
    inline for (@typeInfo(@TypeOf(imports)).@"struct".fields) |field| {
        const import_name = toComptimeString(@field(imports, field.name));
        if (!isImportable(manifest, import_name)) {
            @compileError(section ++ " '" ++ name ++ "': import references unknown target '" ++ import_name ++ "'");
        }
    }
}

fn hasModule(comptime manifest: anytype, comptime name: []const u8) bool {
    if (@hasField(@TypeOf(manifest), "modules")) {
        if (@hasField(@TypeOf(manifest.modules), name)) return true;
    }
    return false;
}

fn hasArtifact(comptime manifest: anytype, comptime name: []const u8) bool {
    inline for (.{ "executables", "libraries", "objects" }) |section| {
        if (@hasField(@TypeOf(manifest), section)) {
            if (@hasField(@TypeOf(@field(manifest, section)), name)) return true;
        }
    }
    return false;
}

fn isImportable(comptime manifest: anytype, comptime name: []const u8) bool {
    if (hasModule(manifest, name)) return true;
    if (@hasField(@TypeOf(manifest), "options_modules")) {
        if (@hasField(@TypeOf(manifest.options_modules), name)) return true;
    }
    if (@hasField(@TypeOf(manifest), "dependencies")) {
        const base = comptimeBaseName(name);
        if (@hasField(@TypeOf(manifest.dependencies), base)) return true;
    }
    return false;
}

fn comptimeBaseName(comptime name: []const u8) []const u8 {
    for (name, 0..) |c, i| {
        if (c == ':') return name[0..i];
    }
    return name;
}

fn toComptimeString(comptime val: anytype) []const u8 {
    const ti = @typeInfo(@TypeOf(val));
    if (ti == .enum_literal) return @tagName(val);
    if (ti == .pointer) return val;
    @compileError("expected string or enum literal");
}

// --- BuildRunner ---

const BuildRunner = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modules: std.StringHashMap(*std.Build.Module),
    dependencies: std.StringHashMap(*std.Build.Dependency),
    options_modules: std.StringHashMap(*std.Build.Module),
    install_steps: std.StringHashMap(*std.Build.Step),

    const Error = error{ OutOfMemory, ModuleNotFound };

    // --- Module creation ---

    const module_passthrough_fields = .{
        "link_libc",       "link_libcpp",     "single_threaded",
        "strip",           "unwind_tables",   "dwarf_format",
        "code_model",      "error_tracing",   "omit_frame_pointer",
        "pic",             "red_zone",        "sanitize_c",
        "sanitize_thread", "stack_check",     "stack_protector",
        "fuzz",            "valgrind",
    };

    fn createModule(self: *BuildRunner, comptime mod: anytype, name: []const u8) *std.Build.Module {
        const Mod = @TypeOf(mod);
        var opts: std.Build.Module.CreateOptions = .{
            .root_source_file = if (@hasField(Mod, "root_source_file")) self.resolveLazyPath(mod.root_source_file) else null,
            .target = if (@hasField(Mod, "target")) self.resolveTarget(mod.target) else self.target,
            .optimize = if (@hasField(Mod, "optimize")) mod.optimize else self.optimize,
        };
        inline for (module_passthrough_fields) |fname| {
            if (@hasField(Mod, fname)) {
                @field(opts, fname) = @field(mod, fname);
            }
        }
        const m = self.b.createModule(opts);

        if (@hasField(Mod, "include_paths")) {
            inline for (@typeInfo(@TypeOf(mod.include_paths)).@"struct".fields) |field| {
                m.addIncludePath(self.resolveLazyPath(@field(mod.include_paths, field.name)));
            }
        }

        if (@hasField(Mod, "link_libraries")) {
            inline for (@typeInfo(@TypeOf(mod.link_libraries)).@"struct".fields) |field| {
                const lib_spec: []const u8 = @field(mod.link_libraries, field.name);
                var parts = std.mem.splitScalar(u8, lib_spec, ':');
                const dep_name = parts.first();
                const artifact_name = if (parts.next()) |rest| rest else dep_name;
                if (self.dependencies.get(dep_name)) |dep| {
                    m.linkLibrary(dep.artifact(artifact_name));
                }
            }
        }

        self.modules.put(name, m) catch @panic("OOM");
        return m;
    }

    fn resolveModuleLink(self: *BuildRunner, comptime link: anytype, name: []const u8) Error!*std.Build.Module {
        const ti = @typeInfo(@TypeOf(link));
        if (ti == .enum_literal) {
            const mod_name = @tagName(link);
            return self.modules.get(mod_name) orelse {
                std.log.err("zbuild: module '{s}' not found", .{mod_name});
                return error.ModuleNotFound;
            };
        } else if (ti == .pointer) {
            const str: []const u8 = link;
            return self.modules.get(str) orelse {
                std.log.err("zbuild: module '{s}' not found", .{str});
                return error.ModuleNotFound;
            };
        } else if (ti == .@"struct") {
            const mod_name: []const u8 = if (@hasField(@TypeOf(link), "name")) link.name else name;
            return self.createModule(link, mod_name);
        } else {
            @compileError("root_module must be a string, enum literal, or struct");
        }
    }

    // --- Artifact creation ---

    const artifact_passthrough_fields = .{ "max_rss", "use_llvm", "use_lld" };

    fn createExecutable(self: *BuildRunner, comptime name: []const u8, comptime exe: anytype) Error!void {
        const Exe = @TypeOf(exe);
        const root_module = try self.resolveModuleLink(exe.root_module, name);

        var add_opts: std.Build.ExecutableOptions = .{
            .name = name,
            .root_module = root_module,
            .version = if (@hasField(Exe, "version")) std.SemanticVersion.parse(exe.version) catch null else null,
        };
        inline for (artifact_passthrough_fields) |fname| {
            if (@hasField(Exe, fname)) {
                @field(add_opts, fname) = @field(exe, fname);
            }
        }
        if (@hasField(Exe, "linkage")) add_opts.linkage = exe.linkage;
        if (@hasField(Exe, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(exe.zig_lib_dir);
        if (@hasField(Exe, "win32_manifest")) add_opts.win32_manifest = self.resolveLazyPath(exe.win32_manifest);

        const artifact = self.b.addExecutable(add_opts);

        const install = self.b.addInstallArtifact(artifact, .{
            .dest_sub_path = if (@hasField(Exe, "dest_sub_path")) exe.dest_sub_path else null,
        });

        const tls_install = self.b.step(
            self.b.fmt("build-exe:{s}", .{name}),
            self.b.fmt("Install the {s} executable", .{name}),
        );
        tls_install.dependOn(&install.step);
        self.b.getInstallStep().dependOn(&install.step);
        try self.install_steps.put(name, &install.step);

        const run = self.b.addRunArtifact(artifact);
        if (self.b.args) |args| run.addArgs(args);
        const tls_run = self.b.step(
            self.b.fmt("run:{s}", .{name}),
            self.b.fmt("Run the {s} executable", .{name}),
        );
        tls_run.dependOn(&run.step);
    }

    fn createLibrary(self: *BuildRunner, comptime name: []const u8, comptime lib: anytype) Error!void {
        const Lib = @TypeOf(lib);
        const root_module = try self.resolveModuleLink(lib.root_module, name);

        var add_opts: std.Build.StaticLibraryOptions = .{
            .name = name,
            .root_module = root_module,
            .version = if (@hasField(Lib, "version")) std.SemanticVersion.parse(lib.version) catch null else null,
        };
        inline for (artifact_passthrough_fields) |fname| {
            if (@hasField(Lib, fname)) {
                @field(add_opts, fname) = @field(lib, fname);
            }
        }
        if (@hasField(Lib, "linkage")) add_opts.linkage = lib.linkage;
        if (@hasField(Lib, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(lib.zig_lib_dir);
        if (@hasField(Lib, "win32_manifest")) add_opts.win32_manifest = self.resolveLazyPath(lib.win32_manifest);

        const artifact = self.b.addLibrary(add_opts);

        if (@hasField(Lib, "linker_allow_shlib_undefined")) {
            artifact.linker_allow_shlib_undefined = lib.linker_allow_shlib_undefined;
        }

        const install = self.b.addInstallArtifact(artifact, .{
            .dest_sub_path = if (@hasField(Lib, "dest_sub_path")) lib.dest_sub_path else null,
        });

        const tls_install = self.b.step(
            self.b.fmt("build-lib:{s}", .{name}),
            self.b.fmt("Install the {s} library", .{name}),
        );
        tls_install.dependOn(&install.step);
        self.b.getInstallStep().dependOn(&install.step);
        try self.install_steps.put(name, &install.step);
    }

    fn createObject(self: *BuildRunner, comptime name: []const u8, comptime obj: anytype) Error!void {
        const Obj = @TypeOf(obj);
        const root_module = try self.resolveModuleLink(obj.root_module, name);

        var add_opts: std.Build.ObjectOptions = .{
            .name = name,
            .root_module = root_module,
        };
        inline for (artifact_passthrough_fields) |fname| {
            if (@hasField(Obj, fname)) {
                @field(add_opts, fname) = @field(obj, fname);
            }
        }
        if (@hasField(Obj, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(obj.zig_lib_dir);

        const artifact = self.b.addObject(add_opts);

        const install = self.b.addInstallArtifact(artifact, .{});
        const tls_install = self.b.step(
            self.b.fmt("build-obj:{s}", .{name}),
            self.b.fmt("Install the {s} object", .{name}),
        );
        tls_install.dependOn(&install.step);
        self.b.getInstallStep().dependOn(&install.step);
        try self.install_steps.put(name, &install.step);
    }

    fn createTest(self: *BuildRunner, comptime name: []const u8, comptime t: anytype, tls_run_test: *std.Build.Step) Error!void {
        const T = @TypeOf(t);
        const root_module = try self.resolveModuleLink(t.root_module, name);

        const filters_option = self.b.option(
            []const []const u8,
            self.b.fmt("{s}.filters", .{name}),
            self.b.fmt("{s} test filters", .{name}),
        );

        var add_opts: std.Build.TestOptions = .{
            .name = name,
            .root_module = root_module,
            .filters = filters_option orelse if (@hasField(T, "filters")) comptime toStringSlice(t.filters) else &.{},
        };
        inline for (artifact_passthrough_fields) |fname| {
            if (@hasField(T, fname)) {
                @field(add_opts, fname) = @field(t, fname);
            }
        }
        if (@hasField(T, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(t.zig_lib_dir);

        const artifact = self.b.addTest(add_opts);

        const install = self.b.addInstallArtifact(artifact, .{});
        const tls_install = self.b.step(
            self.b.fmt("build-test:{s}", .{name}),
            self.b.fmt("Install the {s} test", .{name}),
        );
        tls_install.dependOn(&install.step);

        const run = self.b.addRunArtifact(artifact);
        const tls_run = self.b.step(
            self.b.fmt("test:{s}", .{name}),
            self.b.fmt("Run the {s} test", .{name}),
        );
        tls_run.dependOn(&run.step);
        tls_run_test.dependOn(&run.step);
    }

    fn createFmt(self: *BuildRunner, comptime name: []const u8, comptime fmt: anytype, tls_run_fmt: *std.Build.Step) void {
        const Fmt = @TypeOf(fmt);
        const step = self.b.addFmt(.{
            .paths = if (@hasField(Fmt, "paths")) comptime toStringSlice(fmt.paths) else &.{},
            .exclude_paths = if (@hasField(Fmt, "exclude_paths")) comptime toStringSlice(fmt.exclude_paths) else &.{},
            .check = if (@hasField(Fmt, "check")) fmt.check else false,
        });

        const tls = self.b.step(
            self.b.fmt("fmt:{s}", .{name}),
            self.b.fmt("Run the {s} fmt", .{name}),
        );
        tls.dependOn(&step.step);
        tls_run_fmt.dependOn(&step.step);
    }

    fn createRun(self: *BuildRunner, comptime name: []const u8, comptime cmd: anytype) void {
        const is_long_form = @hasField(@TypeOf(cmd), "cmd");
        const args_tuple = if (is_long_form) cmd.cmd else cmd;
        const run = self.b.addSystemCommand(comptime toStringSlice(args_tuple));

        // Long form options
        if (is_long_form) {
            if (@hasField(@TypeOf(cmd), "cwd"))
                run.setCwd(self.resolveLazyPath(cmd.cwd));

            if (@hasField(@TypeOf(cmd), "env")) {
                inline for (@typeInfo(@TypeOf(cmd.env)).@"struct".fields) |field| {
                    run.setEnvironmentVariable(field.name, @field(cmd.env, field.name));
                }
            }

            if (@hasField(@TypeOf(cmd), "inherit_stdio")) {
                if (cmd.inherit_stdio) run.stdio = .inherit;
            }

            if (@hasField(@TypeOf(cmd), "stdin"))
                run.setStdIn(.{ .bytes = cmd.stdin });

            if (@hasField(@TypeOf(cmd), "stdin_file"))
                run.setStdIn(.{ .lazy_path = self.resolveLazyPath(cmd.stdin_file) });
        }

        const tls = self.b.step(
            self.b.fmt("cmd:{s}", .{name}),
            self.b.fmt("Run the {s} command", .{name}),
        );
        tls.dependOn(&run.step);

        // Wire depends_on
        if (is_long_form and @hasField(@TypeOf(cmd), "depends_on")) {
            inline for (@typeInfo(@TypeOf(cmd.depends_on)).@"struct".fields) |field| {
                const dep_name = comptime toComptimeString(@field(cmd.depends_on, field.name));
                if (self.install_steps.get(dep_name)) |dep_step| {
                    run.step.dependOn(dep_step);
                } else {
                    std.log.warn("zbuild: runs '{s}' depends_on references unknown artifact '{s}'", .{ name, dep_name });
                }
            }
        }
    }

    // --- Options modules ---

    fn createOptionsModule(self: *BuildRunner, comptime name: []const u8, comptime options: anytype) !void {
        const opts = self.b.addOptions();
        inline for (@typeInfo(@TypeOf(options)).@"struct".fields) |field| {
            self.addOption(opts, field.name, @field(options, field.name));
        }
        const m = opts.createModule();
        try self.options_modules.put(name, m);
    }

    fn addOption(self: *BuildRunner, opts: *std.Build.Step.Options, comptime name: []const u8, comptime opt: anytype) void {
        _ = self;
        const Opt = @TypeOf(opt);
        const desc: []const u8 = if (@hasField(Opt, "description")) opt.description else "";
        const type_str = opt.type;

        if (comptime std.mem.eql(u8, type_str, "bool")) {
            const default: bool = if (@hasField(Opt, "default")) opt.default else false;
            const val = opts.step.owner.option(bool, name, desc);
            opts.addOption(bool, name, val orelse default);
        } else if (comptime std.mem.eql(u8, type_str, "string")) {
            const val = opts.step.owner.option([]const u8, name, desc);
            if (val orelse if (@hasField(Opt, "default")) @as(?[]const u8, opt.default) else null) |s| {
                opts.addOption([]const u8, name, s);
            }
        } else if (comptime std.mem.eql(u8, type_str, "list")) {
            const val = opts.step.owner.option([]const []const u8, name, desc);
            if (val orelse if (@hasField(Opt, "default")) @as(?[]const []const u8, comptime toStringSlice(opt.default)) else null) |l| {
                opts.addOption([]const []const u8, name, l);
            }
        } else if (comptime std.mem.eql(u8, type_str, "enum")) {
            const val = opts.step.owner.option([]const u8, name, desc);
            if (val orelse if (@hasField(Opt, "default")) @as(?[]const u8, @tagName(opt.default)) else null) |e| {
                opts.addOption([]const u8, name, e);
            }
        } else if (comptime std.mem.eql(u8, type_str, "enum_list")) {
            const val = opts.step.owner.option([]const []const u8, name, desc);
            if (val orelse if (@hasField(Opt, "default")) @as(?[]const []const u8, comptime toEnumSlice(opt.default)) else null) |e| {
                opts.addOption([]const []const u8, name, e);
            }
        } else if (comptime isIntType(type_str)) {
            const default: i64 = if (@hasField(Opt, "default")) opt.default else 0;
            const val = opts.step.owner.option(i64, name, desc);
            opts.addOption(i64, name, val orelse default);
        } else if (comptime isFloatType(type_str)) {
            const default: f64 = if (@hasField(Opt, "default")) opt.default else 0.0;
            const val = opts.step.owner.option(f64, name, desc);
            opts.addOption(f64, name, val orelse default);
        } else {
            @compileError("unknown option type '" ++ type_str ++ "'");
        }
    }

    // --- Import wiring ---

    fn wireAllImports(self: *BuildRunner, comptime manifest: anytype) Error!void {
        if (@hasField(@TypeOf(manifest), "modules")) {
            inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
                const mod = @field(manifest.modules, field.name);
                if (@hasField(@TypeOf(mod), "imports")) {
                    if (self.modules.get(field.name)) |m| {
                        try self.wireModuleImports(m, mod.imports);
                    }
                }
            }
        }

        // Wire imports for inline modules in executables, libraries, objects, tests
        inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
            if (@hasField(@TypeOf(manifest), section)) {
                inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                    const item = @field(@field(manifest, section), field.name);
                    if (@typeInfo(@TypeOf(item.root_module)) == .@"struct") {
                        if (@hasField(@TypeOf(item.root_module), "imports")) {
                            const mod_name: []const u8 = if (@hasField(@TypeOf(item.root_module), "name"))
                                item.root_module.name
                            else
                                field.name;
                            if (self.modules.get(mod_name)) |m| {
                                try self.wireModuleImports(m, item.root_module.imports);
                            }
                        }
                    }
                }
            }
        }
    }

    fn wireModuleImports(self: *BuildRunner, module: *std.Build.Module, comptime imports: anytype) Error!void {
        inline for (@typeInfo(@TypeOf(imports)).@"struct".fields) |field| {
            const import_name: []const u8 = @field(imports, field.name);
            const resolved = try self.resolveImport(import_name);
            module.addImport(import_name, resolved);
        }
    }

    // --- depends_on wiring ---

    fn wireDependsOn(self: *BuildRunner, comptime manifest: anytype) void {
        inline for (.{ "executables", "libraries", "objects" }) |section| {
            if (@hasField(@TypeOf(manifest), section)) {
                inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                    const item = @field(@field(manifest, section), field.name);
                    if (@hasField(@TypeOf(item), "depends_on")) {
                        if (self.install_steps.get(field.name)) |this_step| {
                            self.wireDependsOnList(this_step, item.depends_on);
                        }
                    }
                }
            }
        }
    }

    fn wireDependsOnList(self: *BuildRunner, step: *std.Build.Step, comptime deps: anytype) void {
        inline for (@typeInfo(@TypeOf(deps)).@"struct".fields) |field| {
            const dep_name: []const u8 = @field(deps, field.name);
            const dep_step = self.install_steps.get(dep_name) orelse {
                std.log.warn("zbuild: depends_on references unknown artifact '{s}'", .{dep_name});
                continue;
            };
            step.dependOn(dep_step);
        }
    }

    // --- Resolution helpers (runtime) ---

    fn resolveImport(self: *BuildRunner, import_name: []const u8) Error!*std.Build.Module {
        if (self.modules.get(import_name)) |m| return m;
        if (self.options_modules.get(import_name)) |m| return m;
        var parts = std.mem.splitScalar(u8, import_name, ':');
        const first = parts.first();
        if (self.dependencies.get(first)) |dep| {
            const module_name = if (parts.next()) |rest| rest else first;
            return dep.module(module_name);
        }
        std.log.err("zbuild: unresolved import '{s}'", .{import_name});
        return error.ModuleNotFound;
    }

    fn resolveLazyPath(self: *BuildRunner, path: []const u8) std.Build.LazyPath {
        var parts = std.mem.splitScalar(u8, path, ':');
        const first = parts.first();
        if (self.dependencies.get(first)) |dep| {
            const next = parts.next() orelse return dep.namedLazyPath(first);
            if (parts.next()) |last| {
                return dep.namedWriteFiles(next).getDirectory().path(self.b, last);
            }
            return dep.namedLazyPath(next);
        }
        return self.b.path(path);
    }

    fn resolveTarget(self: *BuildRunner, target_str: []const u8) std.Build.ResolvedTarget {
        if (std.mem.eql(u8, target_str, "native")) return self.target;
        return self.b.resolveTargetQuery(
            std.Target.Query.parse(.{ .arch_os_abi = target_str }) catch @panic("invalid target"),
        );
    }
};

// --- Comptime helpers ---

fn toStringSlice(comptime tuple: anytype) []const []const u8 {
    const fields = @typeInfo(@TypeOf(tuple)).@"struct".fields;
    var result: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        result[i] = @field(tuple, field.name);
    }
    const final = result;
    return &final;
}

fn toEnumSlice(comptime tuple: anytype) []const []const u8 {
    const fields = @typeInfo(@TypeOf(tuple)).@"struct".fields;
    var result: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        result[i] = @tagName(@field(tuple, field.name));
    }
    const final = result;
    return &final;
}

fn isIntType(comptime t: []const u8) bool {
    return for ([_][]const u8{
        "i8",  "u8",  "i16", "u16", "i32",  "u32",  "i64",  "u64",
        "i128", "u128", "isize", "usize",
        "c_short", "c_ushort", "c_int", "c_uint",
        "c_long", "c_ulong", "c_longlong", "c_ulonglong",
    }) |valid| {
        if (std.mem.eql(u8, t, valid)) break true;
    } else false;
}

fn isFloatType(comptime t: []const u8) bool {
    return for ([_][]const u8{
        "f16", "f32", "f64", "f80", "f128", "c_longdouble",
    }) |valid| {
        if (std.mem.eql(u8, t, valid)) break true;
    } else false;
}

// --- Tests ---

test "toStringSlice" {
    const result = comptime toStringSlice(.{ "hello", "world" });
    try std.testing.expectEqual(2, result.len);
    try std.testing.expectEqualStrings("hello", result[0]);
    try std.testing.expectEqualStrings("world", result[1]);
}

test "toStringSlice empty" {
    const result = comptime toStringSlice(.{});
    try std.testing.expectEqual(0, result.len);
}

test "toEnumSlice" {
    const result = comptime toEnumSlice(.{ .debug, .info, .warn });
    try std.testing.expectEqual(3, result.len);
    try std.testing.expectEqualStrings("debug", result[0]);
    try std.testing.expectEqualStrings("info", result[1]);
    try std.testing.expectEqualStrings("warn", result[2]);
}

test "isIntType" {
    try std.testing.expect(comptime isIntType("i32"));
    try std.testing.expect(comptime isIntType("u64"));
    try std.testing.expect(comptime isIntType("usize"));
    try std.testing.expect(comptime isIntType("c_int"));
    try std.testing.expect(!comptime isIntType("f32"));
    try std.testing.expect(!comptime isIntType("bool"));
    try std.testing.expect(!comptime isIntType("string"));
}

test "isFloatType" {
    try std.testing.expect(comptime isFloatType("f32"));
    try std.testing.expect(comptime isFloatType("f64"));
    try std.testing.expect(comptime isFloatType("c_longdouble"));
    try std.testing.expect(!comptime isFloatType("i32"));
    try std.testing.expect(!comptime isFloatType("bool"));
}

test "hasModule" {
    const manifest = .{
        .modules = .{
            .core = .{ .root_source_file = "src/core.zig" },
            .utils = .{ .root_source_file = "src/utils.zig" },
        },
    };
    try std.testing.expect(comptime hasModule(manifest, "core"));
    try std.testing.expect(comptime hasModule(manifest, "utils"));
    try std.testing.expect(!comptime hasModule(manifest, "missing"));
    // No modules section at all
    try std.testing.expect(!comptime hasModule(.{}, "anything"));
}

test "hasArtifact" {
    const manifest = .{
        .executables = .{ .myapp = .{ .root_module = .{ .root_source_file = "src/main.zig" } } },
        .libraries = .{ .mylib = .{ .root_module = .{ .root_source_file = "src/lib.zig" } } },
    };
    try std.testing.expect(comptime hasArtifact(manifest, "myapp"));
    try std.testing.expect(comptime hasArtifact(manifest, "mylib"));
    try std.testing.expect(!comptime hasArtifact(manifest, "missing"));
}

test "isImportable" {
    const manifest = .{
        .modules = .{
            .core = .{ .root_source_file = "src/core.zig" },
        },
        .options_modules = .{
            .config = .{ .some_flag = .{ .type = "bool" } },
        },
        .dependencies = .{
            .zlib = .{},
        },
    };
    // Module is importable
    try std.testing.expect(comptime isImportable(manifest, "core"));
    // Options module is importable
    try std.testing.expect(comptime isImportable(manifest, "config"));
    // Dependency is importable (plain name)
    try std.testing.expect(comptime isImportable(manifest, "zlib"));
    // Dependency sub-module is importable (colon-separated)
    try std.testing.expect(comptime isImportable(manifest, "zlib:zlib"));
    // Unknown is not importable
    try std.testing.expect(!comptime isImportable(manifest, "missing"));
}

test "comptimeBaseName" {
    try std.testing.expectEqualStrings("zlib", comptime comptimeBaseName("zlib"));
    try std.testing.expectEqualStrings("zlib", comptime comptimeBaseName("zlib:zlib"));
    try std.testing.expectEqualStrings("foo", comptime comptimeBaseName("foo:bar:baz"));
    try std.testing.expectEqualStrings("", comptime comptimeBaseName(""));
}

test "toComptimeString" {
    try std.testing.expectEqualStrings("hello", comptime toComptimeString("hello"));
    try std.testing.expectEqualStrings("world", comptime toComptimeString(.world));
}

test "validateManifest accepts minimal manifest" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.14.0",
        .paths = .{"."},
    });
}

test "validateManifest accepts valid cross-references" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.14.0",
        .paths = .{"."},
        .modules = .{
            .core = .{ .root_source_file = "src/core.zig" },
        },
        .executables = .{
            .myapp = .{
                .root_module = .core,
            },
        },
        .libraries = .{
            .mylib = .{
                .root_module = .{
                    .root_source_file = "src/lib.zig",
                    .imports = .{.core},
                },
            },
        },
    });
}

test "validateManifest accepts unknown top-level fields" {
    // Forward compatibility: unknown fields should NOT cause errors
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.14.0",
        .paths = .{"."},
        .some_future_zig_field = "should be ignored",
    });
}
