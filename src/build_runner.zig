//! Configures a Zig build graph from a zbuild Config.
//! Replaces string-concatenation codegen (ConfigBuildgen) with direct API calls.

const std = @import("std");
const Config = @import("Config.zig");

pub fn configureBuild(b: *std.Build) !void {
    const config = try Config.parseFromFile(b.allocator, "build.zig.zon", null);
    try configureWithConfig(b, config);
}

fn configureWithConfig(b: *std.Build, config: Config) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var runner = BuildRunner{
        .b = b,
        .config = config,
        .target = target,
        .optimize = optimize,
        .modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
        .dependencies = std.StringHashMap(*std.Build.Dependency).init(b.allocator),
        .options_modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
        .install_steps = std.StringHashMap(*std.Build.Step).init(b.allocator),
    };

    // Phase 1: Create options modules
    if (config.options_modules) |options_modules| {
        for (options_modules.keys(), options_modules.values()) |name, options| {
            try runner.createOptionsModule(name, options);
        }
    }

    // Phase 2: Create dependencies
    if (config.dependencies) |dependencies| {
        for (dependencies.keys(), dependencies.values()) |name, dep| {
            try runner.createDependency(name, dep);
        }
    }

    // Phase 3: Create named modules
    if (config.modules) |modules| {
        for (modules.keys(), modules.values()) |name, module| {
            const m = try runner.createModule(module, name);
            if (!(module.private orelse true)) {
                b.modules.put(b.dupe(name), m) catch @panic("OOM");
            }
            try runner.modules.put(name, m);
        }
    }

    // Phase 4: Create executables
    if (config.executables) |executables| {
        for (executables.keys(), executables.values()) |name, exe| {
            try runner.createExecutable(name, exe);
        }
    }

    // Phase 5: Create libraries
    if (config.libraries) |libraries| {
        for (libraries.keys(), libraries.values()) |name, lib| {
            try runner.createLibrary(name, lib);
        }
    }

    // Phase 6: Create objects
    if (config.objects) |objects| {
        for (objects.keys(), objects.values()) |name, obj| {
            try runner.createObject(name, obj);
        }
    }

    // Phase 7: Create tests
    var tls_run_test: ?*std.Build.Step = null;

    if (config.modules) |modules| {
        if (modules.count() > 0 or (config.tests != null and config.tests.?.count() > 0)) {
            tls_run_test = b.step("test", "Run all tests");
        }
        for (modules.keys()) |name| {
            if (config.tests == null or !config.tests.?.contains(name)) {
                try runner.createTest(name, .{
                    .root_module = .{ .name = name },
                    .filters = &.{},
                }, tls_run_test.?);
            }
        }
    }

    if (config.tests) |tests| {
        if (tls_run_test == null) {
            tls_run_test = b.step("test", "Run all tests");
        }
        for (tests.keys(), tests.values()) |name, t| {
            try runner.createTest(name, t, tls_run_test.?);
        }
    }

    // Phase 8: Create fmts
    if (config.fmts) |fmts| {
        const tls_run_fmt = b.step("fmt", "Run all fmts");
        for (fmts.keys(), fmts.values()) |name, fmt| {
            try runner.createFmt(name, fmt, tls_run_fmt);
        }
    }

    // Phase 9: Create runs
    if (config.runs) |runs| {
        for (runs.keys(), runs.values()) |name, run| {
            runner.createRun(name, run);
        }
    }

    // Phase 10: Wire imports for all modules
    try runner.wireAllImports(config);

    // Phase 11: Wire depends_on for artifacts
    runner.wireDependsOn(config);
}

const BuildRunner = struct {
    b: *std.Build,
    config: Config,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modules: std.StringHashMap(*std.Build.Module),
    dependencies: std.StringHashMap(*std.Build.Dependency),
    options_modules: std.StringHashMap(*std.Build.Module),
    install_steps: std.StringHashMap(*std.Build.Step),

    fn createModule(self: *BuildRunner, module: Config.Module, name: []const u8) !*std.Build.Module {
        const m = self.b.createModule(.{
            .root_source_file = if (module.root_source_file) |f| self.resolveLazyPath(f) else null,
            .target = if (module.target) |t| self.resolveTarget(t) else self.target,
            .optimize = module.optimize orelse self.optimize,
            .link_libc = module.link_libc,
            .link_libcpp = module.link_libcpp,
            .single_threaded = module.single_threaded,
            .strip = module.strip,
            .unwind_tables = module.unwind_tables,
            .dwarf_format = module.dwarf_format,
            .code_model = module.code_model,
            .error_tracing = module.error_tracing,
            .omit_frame_pointer = module.omit_frame_pointer,
            .pic = module.pic,
            .red_zone = module.red_zone,
            .sanitize_c = module.sanitize_c,
            .sanitize_thread = module.sanitize_thread,
            .stack_check = module.stack_check,
            .stack_protector = module.stack_protector,
            .fuzz = module.fuzz,
            .valgrind = module.valgrind,
        });

        if (module.include_paths) |paths| {
            for (paths) |path| {
                m.addIncludePath(self.resolveLazyPath(path));
            }
        }

        if (module.link_libraries) |libs| {
            for (libs) |lib| {
                var parts = std.mem.splitScalar(u8, lib, ':');
                const dep_name = parts.first();
                const artifact_name = if (parts.next()) |rest| rest else dep_name;
                if (self.dependencies.get(dep_name)) |dep| {
                    m.linkLibrary(dep.artifact(artifact_name));
                }
            }
        }

        try self.modules.put(name, m);
        return m;
    }

    fn resolveModuleLink(self: *BuildRunner, link: Config.ModuleLink, fallback_name: []const u8) !*std.Build.Module {
        switch (link) {
            .name => |n| {
                return self.modules.get(n) orelse {
                    std.log.err("zbuild: module '{s}' not found", .{n});
                    return error.ModuleNotFound;
                };
            },
            .module => |m| {
                const name = m.name orelse fallback_name;
                return try self.createModule(m, name);
            },
        }
    }

    fn createDependency(self: *BuildRunner, name: []const u8, dep: Config.Dependency) !void {
        _ = dep;
        const d = self.b.dependency(name, .{});
        try self.dependencies.put(name, d);
    }

    fn createOptionsModule(self: *BuildRunner, name: []const u8, options: Config.OptionsModule) !void {
        const opts = self.b.addOptions();
        for (options.keys(), options.values()) |opt_name, opt_value| {
            self.addOption(opts, opt_name, opt_value);
        }
        const m = opts.createModule();
        try self.options_modules.put(name, m);
    }

    fn addOption(self: *BuildRunner, opts: *std.Build.Step.Options, name: []const u8, value: Config.Option) void {
        _ = self;
        switch (value) {
            .bool => |v| {
                const val = opts.step.owner.option(bool, name, v.description orelse "");
                opts.addOption(bool, name, val orelse v.default orelse false);
            },
            .int => |v| {
                const val = opts.step.owner.option(i64, name, v.description orelse "");
                opts.addOption(i64, name, val orelse v.default orelse 0);
            },
            .float => |v| {
                const val = opts.step.owner.option(f64, name, v.description orelse "");
                opts.addOption(f64, name, val orelse v.default orelse 0.0);
            },
            .string => |v| {
                const val = opts.step.owner.option([]const u8, name, v.description orelse "");
                if (val orelse v.default) |s| {
                    opts.addOption([]const u8, name, s);
                }
            },
            .list => |v| {
                const val = opts.step.owner.option([]const []const u8, name, v.description orelse "");
                if (val orelse v.default) |l| {
                    opts.addOption([]const []const u8, name, l);
                }
            },
            .@"enum" => |v| {
                const val = opts.step.owner.option([]const u8, name, v.description orelse "");
                if (val orelse v.default) |e| {
                    opts.addOption([]const u8, name, e);
                }
            },
            .enum_list => |v| {
                const val = opts.step.owner.option([]const []const u8, name, v.description orelse "");
                if (val orelse v.default) |e| {
                    opts.addOption([]const []const u8, name, e);
                }
            },
            .build_id => {},
            .lazy_path => {},
            .lazy_path_list => {},
        }
    }

    fn createExecutable(self: *BuildRunner, name: []const u8, exe: Config.Executable) !void {
        const root_module = try self.resolveModuleLink(exe.root_module, name);

        const artifact = self.b.addExecutable(.{
            .name = name,
            .version = if (exe.version) |v| std.SemanticVersion.parse(v) catch null else null,
            .root_module = root_module,
            .linkage = exe.linkage,
            .max_rss = exe.max_rss,
            .use_llvm = exe.use_llvm,
            .use_lld = exe.use_lld,
            .zig_lib_dir = if (exe.zig_lib_dir) |d| self.resolveLazyPath(d) else null,
            .win32_manifest = if (exe.win32_manifest) |d| self.resolveLazyPath(d) else null,
        });

        const install = self.b.addInstallArtifact(artifact, .{
            .dest_sub_path = if (exe.dest_sub_path) |p| @ptrCast(p) else null,
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

    fn createLibrary(self: *BuildRunner, name: []const u8, lib: Config.Library) !void {
        const root_module = try self.resolveModuleLink(lib.root_module, name);

        const artifact = self.b.addLibrary(.{
            .name = name,
            .version = if (lib.version) |v| std.SemanticVersion.parse(v) catch null else null,
            .root_module = root_module,
            .linkage = lib.linkage,
            .max_rss = lib.max_rss,
            .use_llvm = lib.use_llvm,
            .use_lld = lib.use_lld,
            .zig_lib_dir = if (lib.zig_lib_dir) |d| self.resolveLazyPath(d) else null,
            .win32_manifest = if (lib.win32_manifest) |d| self.resolveLazyPath(d) else null,
        });

        if (lib.linker_allow_shlib_undefined) |v| {
            artifact.linker_allow_shlib_undefined = v;
        }

        const install = self.b.addInstallArtifact(artifact, .{
            .dest_sub_path = if (lib.dest_sub_path) |p| @ptrCast(p) else null,
        });

        const tls_install = self.b.step(
            self.b.fmt("build-lib:{s}", .{name}),
            self.b.fmt("Install the {s} library", .{name}),
        );
        tls_install.dependOn(&install.step);
        self.b.getInstallStep().dependOn(&install.step);
        try self.install_steps.put(name, &install.step);
    }

    fn createObject(self: *BuildRunner, name: []const u8, obj: Config.Object) !void {
        const root_module = try self.resolveModuleLink(obj.root_module, name);

        const artifact = self.b.addObject(.{
            .name = name,
            .root_module = root_module,
            .max_rss = obj.max_rss,
            .use_llvm = obj.use_llvm,
            .use_lld = obj.use_lld,
            .zig_lib_dir = if (obj.zig_lib_dir) |d| self.resolveLazyPath(d) else null,
        });

        const install = self.b.addInstallArtifact(artifact, .{});
        const tls_install = self.b.step(
            self.b.fmt("build-obj:{s}", .{name}),
            self.b.fmt("Install the {s} object", .{name}),
        );
        tls_install.dependOn(&install.step);
        self.b.getInstallStep().dependOn(&install.step);
        try self.install_steps.put(name, &install.step);
    }

    fn createTest(self: *BuildRunner, name: []const u8, t: Config.Test, tls_run_test: *std.Build.Step) !void {
        const root_module = try self.resolveModuleLink(t.root_module, name);

        const filters_option = self.b.option(
            []const []const u8,
            self.b.fmt("{s}.filters", .{name}),
            self.b.fmt("{s} test filters", .{name}),
        );

        const artifact = self.b.addTest(.{
            .name = name,
            .root_module = root_module,
            .max_rss = t.max_rss,
            .use_llvm = t.use_llvm,
            .use_lld = t.use_lld,
            .zig_lib_dir = if (t.zig_lib_dir) |d| self.resolveLazyPath(d) else null,
            .filters = filters_option orelse if (t.filters.len > 0) t.filters else &.{},
        });

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

    fn createFmt(self: *BuildRunner, name: []const u8, fmt: Config.Fmt, tls_run_fmt: *std.Build.Step) !void {
        const step = self.b.addFmt(.{
            .paths = fmt.paths orelse &.{},
            .exclude_paths = fmt.exclude_paths orelse &.{},
            .check = fmt.check orelse false,
        });

        const tls = self.b.step(
            self.b.fmt("fmt:{s}", .{name}),
            self.b.fmt("Run the {s} fmt", .{name}),
        );
        tls.dependOn(&step.step);
        tls_run_fmt.dependOn(&step.step);
    }

    fn createRun(self: *BuildRunner, name: []const u8, cmd: Config.Run) void {
        var args = std.ArrayList([]const u8).init(self.b.allocator);
        var it = std.mem.splitScalar(u8, cmd, ' ');
        while (it.next()) |arg| {
            if (arg.len > 0) args.append(arg) catch @panic("OOM");
        }

        const run = self.b.addSystemCommand(args.items);
        const tls = self.b.step(
            self.b.fmt("run:{s}", .{name}),
            self.b.fmt("Run the {s} command", .{name}),
        );
        tls.dependOn(&run.step);
    }

    fn wireAllImports(self: *BuildRunner, config: Config) !void {
        if (config.modules) |modules| {
            for (modules.keys(), modules.values()) |name, module| {
                if (module.imports) |imports| {
                    const m = self.modules.get(name) orelse continue;
                    self.wireImports(m, imports);
                }
            }
        }
        // Wire imports for inline modules in executables/libraries/objects/tests
        inline for (.{ config.executables, config.libraries, config.objects }) |maybe_map| {
            if (maybe_map) |map| {
                for (map.values()) |item| {
                    if (item.root_module == .module) {
                        if (item.root_module.module.imports) |imports| {
                            const name = item.root_module.module.name orelse continue;
                            const m = self.modules.get(name) orelse continue;
                            self.wireImports(m, imports);
                        }
                    }
                }
            }
        }
        if (config.tests) |tests| {
            for (tests.values()) |t| {
                if (t.root_module == .module) {
                    if (t.root_module.module.imports) |imports| {
                        const name = t.root_module.module.name orelse continue;
                        const m = self.modules.get(name) orelse continue;
                        self.wireImports(m, imports);
                    }
                }
            }
        }
    }

    fn wireDependsOn(self: *BuildRunner, config: Config) void {
        inline for (.{
            config.executables,
            config.libraries,
            config.objects,
        }) |maybe_map| {
            if (maybe_map) |map| {
                for (map.keys(), map.values()) |name, item| {
                    if (@field(item, "depends_on")) |deps| {
                        const this_step = self.install_steps.get(name) orelse continue;
                        for (deps) |dep_name| {
                            const dep_step = self.install_steps.get(dep_name) orelse {
                                std.log.warn("zbuild: depends_on references unknown artifact '{s}'", .{dep_name});
                                continue;
                            };
                            this_step.dependOn(dep_step);
                        }
                    }
                }
            }
        }
    }

    fn wireImports(self: *BuildRunner, module: *std.Build.Module, imports: []const []const u8) void {
        for (imports) |import_name| {
            const resolved = self.resolveImport(import_name);
            module.addImport(import_name, resolved);
        }
    }

    fn resolveImport(self: *BuildRunner, import_name: []const u8) *std.Build.Module {
        if (self.modules.get(import_name)) |m| return m;
        if (self.options_modules.get(import_name)) |m| return m;
        var parts = std.mem.splitScalar(u8, import_name, ':');
        const first = parts.first();
        if (self.dependencies.get(first)) |dep| {
            const module_name = if (parts.next()) |rest| rest else first;
            return dep.module(module_name);
        }
        @panic(self.b.fmt("zbuild: unresolved import '{s}'", .{import_name}));
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
