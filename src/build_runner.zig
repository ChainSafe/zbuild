//! Configures a Zig build graph from a comptime ZON manifest.
//!
//! The manifest is obtained via @import("build.zig.zon") in the user's build.zig:
//!
//!     const zbuild = @import("zbuild");
//!
//!     pub fn build(b: *std.Build) void {
//!         const result = zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err| {
//!             std.log.err("zbuild: {}", .{err});
//!             return;
//!         };
//!     }

const std = @import("std");

pub const Options = struct {
    /// Step name for the help command, or null to disable. Default: "help".
    help_step: ?[]const u8 = "help",
};

pub fn configureBuild(b: *std.Build, comptime manifest: anytype, comptime opts: Options) !BuildResult {
    comptime validateManifest(manifest);

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    var runner = BuildRunner{
        .b = b,
        .target = target,
        .optimize = optimize,
        .result = .{
            .executables = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator),
            .libraries = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator),
            .objects = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator),
            .tests = std.StringHashMap(*std.Build.Step.Compile).init(b.allocator),
            .modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
            .dependencies = std.StringHashMap(*std.Build.Dependency).init(b.allocator),
            .options_modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
            .runs = std.StringHashMap(*std.Build.Step.Run).init(b.allocator),
            .fmts = std.StringHashMap(*std.Build.Step.Fmt).init(b.allocator),
        },
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
            try runner.result.dependencies.put(field.name, dep);
        }
    }

    if (runner.validateResolvedManifest(manifest)) return error.InvalidManifest;

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
            const m = try runner.createModule(mod, field.name);
            const is_private = @hasField(@TypeOf(mod), "private") and mod.private;
            if (!is_private) {
                try b.modules.put(b.graph.arena, b.dupe(field.name), m);
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
            try runner.createFmt(field.name, @field(manifest.fmts, field.name), tls_run_fmt);
        }
    }

    // Phase 9: Create runs
    if (@hasField(@TypeOf(manifest), "runs")) {
        inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
            try runner.createRun(field.name, @field(manifest.runs, field.name));
        }
    }

    // Phase 10: Wire imports
    try runner.wireAllImports(manifest);

    // Phase 11: Wire depends_on
    runner.wireDependsOn(manifest);

    // Phase 12: Add help step
    if (opts.help_step) |step_name| {
        const help_step_impl = try b.allocator.create(std.Build.Step);
        const S = struct {
            fn make(step: *std.Build.Step, _: std.Build.Step.MakeOptions) anyerror!void {
                var stdout_buffer: [256]u8 = undefined;
                var stdout_writer = std.Io.File.stdout().writerStreaming(step.owner.graph.io, &stdout_buffer);
                try stdout_writer.interface.writeAll(comptime help.buildHelpText(manifest));
                try stdout_writer.interface.flush();
            }
        };
        help_step_impl.* = std.Build.Step.init(.{
            .id = .custom,
            .name = "help",
            .owner = b,
            .makeFn = S.make,
        });
        const tls = b.step(step_name, "Show project build information");
        tls.dependOn(help_step_impl);
    }

    return runner.result;
}

// --- Manifest validation ---
//
// Cross-reference checks run at comptime so typos in module names,
// dependency references, and artifact names become compile errors.

fn validateManifest(comptime manifest: anytype) void {
    // Validate artifact sections: root_module refs, depends_on, and inline module imports
    inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
        if (@hasField(@TypeOf(manifest), section)) {
            inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                const item = @field(@field(manifest, section), field.name);
                validateRootModuleRef(manifest, item.root_module, section, field.name);
                validateArtifactFields(manifest, item, section, field.name);
                if (@hasField(@TypeOf(item), "depends_on"))
                    validateDependsOn(manifest, item.depends_on, section, field.name);
                if (@typeInfo(@TypeOf(item.root_module)) == .@"struct") {
                    validateModuleDefinition(manifest, item.root_module, section, field.name);
                }
            }
        }
    }

    // Validate named module imports
    if (@hasField(@TypeOf(manifest), "modules")) {
        inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
            validateModuleDefinition(manifest, @field(manifest.modules, field.name), "modules", field.name);
        }
    }

    validateOptionsModules(manifest);

    // Validate runs: depends_on refs and stdin/stdin_file exclusion
    if (@hasField(@TypeOf(manifest), "runs")) {
        inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
            const run = @field(manifest.runs, field.name);
            if (@hasField(@TypeOf(run), "cmd")) {
                if (@hasField(@TypeOf(run), "depends_on"))
                    validateDependsOn(manifest, run.depends_on, "runs", field.name);
                if (@hasField(@TypeOf(run), "stdin") and @hasField(@TypeOf(run), "stdin_file"))
                    @compileError("runs '" ++ field.name ++ "': stdin and stdin_file are mutually exclusive");
                if (@hasField(@TypeOf(run), "cwd"))
                    validateLazyPathSyntax(manifest, run.cwd, "runs", field.name, "cwd");
                if (@hasField(@TypeOf(run), "stdin_file"))
                    validateLazyPathSyntax(manifest, run.stdin_file, "runs", field.name, "stdin_file");
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
        if (comptime std.mem.indexOfScalar(u8, dep_name, ':') != null) {
            // Explicit step reference: "prefix:artifact_name"
            if (!hasStepTarget(manifest, dep_name)) {
                @compileError(section ++ " '" ++ name ++ "': depends_on references unknown step '" ++ dep_name ++ "'");
            }
        } else {
            // Plain name: references an artifact's install step
            if (!hasArtifact(manifest, dep_name)) {
                @compileError(section ++ " '" ++ name ++ "': depends_on references unknown artifact '" ++ dep_name ++ "'");
            }
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

fn validateModuleDefinition(comptime manifest: anytype, comptime mod: anytype, comptime section: []const u8, comptime name: []const u8) void {
    const Mod = @TypeOf(mod);
    if (@hasField(Mod, "imports"))
        validateImports(manifest, mod.imports, section, name);
    if (@hasField(Mod, "link_libraries"))
        validateLinkLibraries(manifest, mod.link_libraries, section, name);
    if (@hasField(Mod, "root_source_file"))
        validateLazyPathSyntax(manifest, mod.root_source_file, section, name, "root_source_file");
    if (@hasField(Mod, "target"))
        validateTargetString(section, name, mod.target);
    if (@hasField(Mod, "include_paths")) {
        inline for (@typeInfo(@TypeOf(mod.include_paths)).@"struct".fields) |field| {
            validateLazyPathSyntax(manifest, @field(mod.include_paths, field.name), section, name, "include_paths");
        }
    }
}

fn validateArtifactFields(comptime manifest: anytype, comptime item: anytype, comptime section: []const u8, comptime name: []const u8) void {
    const Item = @TypeOf(item);
    if (@hasField(Item, "zig_lib_dir"))
        validateLazyPathSyntax(manifest, item.zig_lib_dir, section, name, "zig_lib_dir");
    if (@hasField(Item, "win32_manifest"))
        validateLazyPathSyntax(manifest, item.win32_manifest, section, name, "win32_manifest");
}

fn validateLinkLibraries(comptime manifest: anytype, comptime links: anytype, comptime section: []const u8, comptime name: []const u8) void {
    inline for (@typeInfo(@TypeOf(links)).@"struct".fields) |field| {
        const spec = toComptimeString(@field(links, field.name));
        const dep_name = comptimeBaseName(spec);
        const separator_count = comptime countSeparators(spec, ':');

        if (separator_count > 1 or dep_name.len == 0 or (separator_count == 1 and comptimeAfterSep(spec).len == 0)) {
            @compileError(section ++ " '" ++ name ++ "': link_libraries entry '" ++ spec ++ "' must be 'dep_name' or 'dep_name:artifact_name'");
        }
        if (!hasDependency(manifest, dep_name)) {
            @compileError(section ++ " '" ++ name ++ "': link_libraries references unknown dependency '" ++ dep_name ++ "'");
        }
    }
}

fn validateLazyPathSyntax(comptime manifest: anytype, comptime path: []const u8, comptime section: []const u8, comptime name: []const u8, comptime field_name: []const u8) void {
    const separator_count = comptime countSeparators(path, ':');
    if (separator_count == 0) return;

    const dep_name = comptimeBaseName(path);
    if (!hasDependency(manifest, dep_name)) return;

    if (separator_count > 2) {
        @compileError(section ++ " '" ++ name ++ "': " ++ field_name ++ " path '" ++ path ++ "' must be 'dep:path' or 'dep:wf_name:path'");
    }

    const rest = comptimeAfterSep(path);
    if (rest.len == 0) {
        @compileError(section ++ " '" ++ name ++ "': " ++ field_name ++ " path '" ++ path ++ "' is missing the dependency export name");
    }

    if (separator_count == 2 and comptime std.mem.indexOfScalar(u8, rest, ':') == 0) {
        @compileError(section ++ " '" ++ name ++ "': " ++ field_name ++ " path '" ++ path ++ "' is missing the WriteFiles name");
    }

    if (separator_count == 2 and comptime lastSegment(path).len == 0) {
        @compileError(section ++ " '" ++ name ++ "': " ++ field_name ++ " path '" ++ path ++ "' is missing the generated sub-path");
    }
}

fn validateTargetString(comptime section: []const u8, comptime name: []const u8, comptime target_str: []const u8) void {
    if (std.mem.eql(u8, target_str, "native")) return;
    _ = std.Target.Query.parse(.{ .arch_os_abi = target_str }) catch |err| {
        @compileError(section ++ " '" ++ name ++ "': invalid target '" ++ target_str ++ "' (" ++ @errorName(err) ++ ")");
    };
}

fn validateOptionsModules(comptime manifest: anytype) void {
    if (!@hasField(@TypeOf(manifest), "options_modules")) return;

    inline for (@typeInfo(@TypeOf(manifest.options_modules)).@"struct".fields) |module_field| {
        validateOptionsModule(module_field.name, @field(manifest.options_modules, module_field.name));
    }
}

fn validateOptionsModule(comptime module_name: []const u8, comptime options: anytype) void {
    const fields = @typeInfo(@TypeOf(options)).@"struct".fields;

    inline for (fields) |field| {
        validateOption(module_name, field.name, @field(options, field.name));
    }

    inline for (fields) |field| {
        const opt = @field(options, field.name);
        if (!comptime isEnumOptionType(optionTypeString(opt))) continue;

        const type_name = comptime resolvedOptionTypeName(field.name, opt);
        inline for (fields) |other_field| {
            if (comptime std.mem.eql(u8, type_name, other_field.name)) {
                @compileError("options_modules '" ++ module_name ++ "': generated type name '" ++ type_name ++ "' collides with option '" ++ other_field.name ++ "'");
            }
        }
    }

    inline for (fields, 0..) |field, i| {
        const opt = @field(options, field.name);
        if (!comptime isEnumOptionType(optionTypeString(opt))) continue;

        const type_name = comptime resolvedOptionTypeName(field.name, opt);
        const values = comptime enumOptionValues(opt);
        inline for (fields[i + 1 ..]) |other_field| {
            const other_opt = @field(options, other_field.name);
            if (!comptime isEnumOptionType(optionTypeString(other_opt))) continue;
            if (!comptime std.mem.eql(u8, type_name, resolvedOptionTypeName(other_field.name, other_opt))) continue;
            if (!comptime stringSlicesEql(values, enumOptionValues(other_opt))) {
                @compileError("options_modules '" ++ module_name ++ "': generated type name '" ++ type_name ++ "' is reused with different enum values");
            }
        }
    }
}

fn validateOption(comptime module_name: []const u8, comptime option_name: []const u8, comptime opt: anytype) void {
    const Opt = @TypeOf(opt);
    if (!@hasField(Opt, "type")) {
        @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': missing required field 'type'");
    }

    const type_str = comptime optionTypeString(opt);
    if (!comptime isSupportedOptionType(type_str)) {
        @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': unsupported option type '" ++ type_str ++ "'");
    }

    if (@hasField(Opt, "description")) {
        const description_check: []const u8 = opt.description;
        _ = description_check;
    }

    if (comptime isEnumOptionType(type_str)) {
        if (!@hasField(Opt, "values")) {
            @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': enum options require a non-empty 'values' field");
        }
        _ = comptime enumOptionValues(opt);

        if (@hasField(Opt, "type_name")) {
            const type_name: []const u8 = opt.type_name;
            if (!std.zig.isValidId(type_name) or std.zig.isPrimitive(type_name) or std.zig.isUnderscore(type_name)) {
                @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': type_name '" ++ type_name ++ "' must be a valid non-primitive Zig identifier");
            }
        }
    } else {
        if (@hasField(Opt, "values")) {
            @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': only enum options may declare 'values'");
        }
        if (@hasField(Opt, "type_name")) {
            @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': only enum options may declare 'type_name'");
        }
    }

    if (@hasField(Opt, "default")) {
        validateOptionDefault(module_name, option_name, opt);
    }
}

fn validateOptionDefault(comptime module_name: []const u8, comptime option_name: []const u8, comptime opt: anytype) void {
    const type_str = comptime optionTypeString(opt);
    if (comptime std.mem.eql(u8, type_str, "bool")) {
        const default_check: bool = opt.default;
        _ = default_check;
    } else if (comptime std.mem.eql(u8, type_str, "string")) {
        const default_check: []const u8 = opt.default;
        _ = default_check;
    } else if (comptime std.mem.eql(u8, type_str, "list")) {
        _ = comptime toStringSlice(opt.default);
    } else if (comptime std.mem.eql(u8, type_str, "enum")) {
        validateEnumChoice(module_name, option_name, toComptimeString(opt.default), enumOptionValues(opt));
    } else if (comptime std.mem.eql(u8, type_str, "enum_list")) {
        inline for (comptime toComptimeStringSlice(opt.default)) |value| {
            validateEnumChoice(module_name, option_name, value, enumOptionValues(opt));
        }
    } else if (comptime isIntType(type_str)) {
        validateNumericDefault(optionValueType(type_str), opt.default);
    } else if (comptime isFloatType(type_str)) {
        validateNumericDefault(optionValueType(type_str), opt.default);
    } else {
        @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': unsupported option type '" ++ type_str ++ "'");
    }
}

fn validateNumericDefault(comptime T: type, comptime value: anytype) void {
    switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int, .float, .comptime_float => {
            const default_check: T = value;
            _ = default_check;
        },
        else => @compileError("expected a numeric default value"),
    }
}

fn validateEnumChoice(comptime module_name: []const u8, comptime option_name: []const u8, comptime value: []const u8, comptime allowed: []const []const u8) void {
    if (!comptime stringSliceContains(allowed, value)) {
        @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': default value '" ++ value ++ "' is not present in 'values'");
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

fn hasDependency(comptime manifest: anytype, comptime name: []const u8) bool {
    if (@hasField(@TypeOf(manifest), "dependencies")) {
        if (@hasField(@TypeOf(manifest.dependencies), name)) return true;
    }
    return false;
}

fn hasStepTarget(comptime manifest: anytype, comptime step_ref: []const u8) bool {
    const prefix = comptimeBaseName(step_ref);
    const target_name = comptimeAfterSep(step_ref);

    // Map step prefixes to manifest sections
    const mapping = .{
        .{ "build-exe", "executables" },
        .{ "build-lib", "libraries" },
        .{ "build-obj", "objects" },
        .{ "build-test", "tests" },
        .{ "run", "executables" },
        .{ "test", "tests" },
        .{ "cmd", "runs" },
        .{ "fmt", "fmts" },
    };

    inline for (mapping) |entry| {
        if (comptime std.mem.eql(u8, prefix, entry[0])) {
            if (@hasField(@TypeOf(manifest), entry[1])) {
                if (@hasField(@TypeOf(@field(manifest, entry[1])), target_name)) return true;
            }
            return false;
        }
    }
    return false;
}

fn isImportable(comptime manifest: anytype, comptime name: []const u8) bool {
    if (hasModule(manifest, name)) return true;
    if (@hasField(@TypeOf(manifest), "options_modules")) {
        if (@hasField(@TypeOf(manifest.options_modules), name)) return true;
    }
    if (hasDependency(manifest, comptimeBaseName(name))) {
        const separator_count = countSeparators(name, ':');
        if (separator_count == 0) return true;
        if (separator_count == 1) return comptimeAfterSep(name).len != 0;
    }
    return false;
}

fn comptimeBaseName(comptime name: []const u8) []const u8 {
    for (name, 0..) |c, i| {
        if (c == ':') return name[0..i];
    }
    return name;
}

fn comptimeAfterSep(comptime name: []const u8) []const u8 {
    for (name, 0..) |c, i| {
        if (c == ':') return name[i + 1 ..];
    }
    return name;
}

fn lastSegment(comptime name: []const u8) []const u8 {
    var start: usize = 0;
    for (name, 0..) |c, i| {
        if (c == ':') start = i + 1;
    }
    return name[start..];
}

fn countSeparators(name: []const u8, separator: u8) usize {
    var count: usize = 0;
    for (name) |c| {
        if (c == separator) count += 1;
    }
    return count;
}

pub fn toComptimeString(comptime val: anytype) []const u8 {
    const ti = @typeInfo(@TypeOf(val));
    if (ti == .enum_literal) return @tagName(val);
    if (ti == .pointer) return val;
    @compileError("expected string or enum literal");
}

const help = @import("help.zig");

// --- BuildResult ---

pub const BuildResult = struct {
    executables: std.StringHashMap(*std.Build.Step.Compile),
    libraries: std.StringHashMap(*std.Build.Step.Compile),
    objects: std.StringHashMap(*std.Build.Step.Compile),
    tests: std.StringHashMap(*std.Build.Step.Compile),
    modules: std.StringHashMap(*std.Build.Module),
    dependencies: std.StringHashMap(*std.Build.Dependency),
    options_modules: std.StringHashMap(*std.Build.Module),
    runs: std.StringHashMap(*std.Build.Step.Run),
    fmts: std.StringHashMap(*std.Build.Step.Fmt),

    pub fn executable(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile {
        return self.executables.get(name);
    }
    pub fn library(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile {
        return self.libraries.get(name);
    }
    pub fn object(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile {
        return self.objects.get(name);
    }
    pub fn testArtifact(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile {
        return self.tests.get(name);
    }
    pub fn module(self: BuildResult, name: []const u8) ?*std.Build.Module {
        return self.modules.get(name);
    }
    pub fn dependency(self: BuildResult, name: []const u8) ?*std.Build.Dependency {
        return self.dependencies.get(name);
    }
    pub fn optionsModule(self: BuildResult, name: []const u8) ?*std.Build.Module {
        return self.options_modules.get(name);
    }
    pub fn run(self: BuildResult, name: []const u8) ?*std.Build.Step.Run {
        return self.runs.get(name);
    }
    pub fn fmt(self: BuildResult, name: []const u8) ?*std.Build.Step.Fmt {
        return self.fmts.get(name);
    }
};

// --- BuildRunner ---

const BuildRunner = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    result: BuildResult,
    install_steps: std.StringHashMap(*std.Build.Step), // internal: depends_on wiring

    const Error = error{ OutOfMemory, ModuleNotFound };
    const DependencyArtifactLookup = union(enum) {
        missing,
        ambiguous,
        found: *std.Build.Step.Compile,
    };

    fn validateResolvedManifest(self: *BuildRunner, comptime manifest: anytype) bool {
        var failed = false;

        if (@hasField(@TypeOf(manifest), "modules")) {
            inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
                failed = self.validateResolvedModuleDefinition("modules", field.name, @field(manifest.modules, field.name)) or failed;
            }
        }

        inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
            if (@hasField(@TypeOf(manifest), section)) {
                inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                    const item = @field(@field(manifest, section), field.name);
                    failed = self.validateResolvedArtifactFields(section, field.name, item) or failed;
                    if (@typeInfo(@TypeOf(item.root_module)) == .@"struct") {
                        failed = self.validateResolvedModuleDefinition(section, field.name, item.root_module) or failed;
                    }
                }
            }
        }

        if (@hasField(@TypeOf(manifest), "runs")) {
            inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
                const run = @field(manifest.runs, field.name);
                if (@hasField(@TypeOf(run), "cmd")) {
                    if (@hasField(@TypeOf(run), "cwd"))
                        failed = self.validateResolvedLazyPath(run.cwd, "runs", field.name, "cwd") or failed;
                    if (@hasField(@TypeOf(run), "stdin_file"))
                        failed = self.validateResolvedLazyPath(run.stdin_file, "runs", field.name, "stdin_file") or failed;
                }
            }
        }

        return failed;
    }

    fn validateResolvedModuleDefinition(self: *BuildRunner, comptime section: []const u8, comptime name: []const u8, comptime mod: anytype) bool {
        var failed = false;
        const Mod = @TypeOf(mod);

        if (@hasField(Mod, "imports"))
            failed = self.validateResolvedImports(mod.imports, section, name) or failed;
        if (@hasField(Mod, "link_libraries"))
            failed = self.validateResolvedLinkLibraries(mod.link_libraries, section, name) or failed;
        if (@hasField(Mod, "root_source_file"))
            failed = self.validateResolvedLazyPath(mod.root_source_file, section, name, "root_source_file") or failed;
        if (@hasField(Mod, "include_paths")) {
            inline for (@typeInfo(@TypeOf(mod.include_paths)).@"struct".fields) |field| {
                failed = self.validateResolvedLazyPath(@field(mod.include_paths, field.name), section, name, "include_paths") or failed;
            }
        }

        return failed;
    }

    fn validateResolvedArtifactFields(self: *BuildRunner, comptime section: []const u8, comptime name: []const u8, comptime item: anytype) bool {
        var failed = false;
        const Item = @TypeOf(item);

        if (@hasField(Item, "zig_lib_dir"))
            failed = self.validateResolvedLazyPath(item.zig_lib_dir, section, name, "zig_lib_dir") or failed;
        if (@hasField(Item, "win32_manifest"))
            failed = self.validateResolvedLazyPath(item.win32_manifest, section, name, "win32_manifest") or failed;

        return failed;
    }

    fn validateResolvedImports(self: *BuildRunner, comptime imports: anytype, comptime section: []const u8, comptime name: []const u8) bool {
        var failed = false;

        inline for (@typeInfo(@TypeOf(imports)).@"struct".fields) |field| {
            const import_name = comptime toComptimeString(@field(imports, field.name));
            if (self.result.modules.get(import_name) == null and self.result.options_modules.get(import_name) == null) {
                const dep_name = comptimeBaseName(import_name);
                if (self.result.dependencies.get(dep_name)) |dep| {
                    const module_name = if (countSeparators(import_name, ':') == 0) import_name else comptimeAfterSep(import_name);

                    if (dep.builder.modules.get(module_name) == null) {
                        self.invalidateManifest("dependency import '{s}' in {s} '{s}' could not resolve module '{s}' from dependency '{s}'", .{
                            import_name,
                            section,
                            name,
                            module_name,
                            dep_name,
                        });
                        failed = true;
                    }
                }
            }
        }

        return failed;
    }

    fn validateResolvedLinkLibraries(self: *BuildRunner, comptime links: anytype, comptime section: []const u8, comptime name: []const u8) bool {
        var failed = false;

        inline for (@typeInfo(@TypeOf(links)).@"struct".fields) |field| {
            const spec = comptime toComptimeString(@field(links, field.name));
            const dep_name = comptime comptimeBaseName(spec);
            const artifact_name = comptime comptimeAfterSep(spec);
            if (self.result.dependencies.get(dep_name)) |dep| {
                switch (lookupDependencyArtifact(dep, artifact_name)) {
                    .found => {},
                    .missing => {
                        self.invalidateManifest("{s} '{s}': link_libraries entry '{s}' could not resolve artifact '{s}' from dependency '{s}'", .{
                            section,
                            name,
                            spec,
                            artifact_name,
                            dep_name,
                        });
                        failed = true;
                    },
                    .ambiguous => {
                        self.invalidateManifest("{s} '{s}': link_libraries entry '{s}' resolves ambiguous artifact '{s}' from dependency '{s}'", .{
                            section,
                            name,
                            spec,
                            artifact_name,
                            dep_name,
                        });
                        failed = true;
                    },
                }
            } else {
                self.invalidateManifest("{s} '{s}': link_libraries references missing dependency '{s}'", .{ section, name, dep_name });
                failed = true;
            }
        }

        return failed;
    }

    fn validateResolvedLazyPath(self: *BuildRunner, path: []const u8, comptime section: []const u8, comptime name: []const u8, comptime field_name: []const u8) bool {
        const separator_count = countSeparators(path, ':');
        if (separator_count == 0) return false;

        var parts = std.mem.splitScalar(u8, path, ':');
        const dep_name = parts.first();
        const dep = self.result.dependencies.get(dep_name) orelse return false;
        const export_name = parts.next() orelse return false;

        if (separator_count == 1) {
            if (dep.builder.named_lazy_paths.get(export_name) == null) {
                self.invalidateManifest("{s} '{s}': {s} path '{s}' could not resolve named lazy path '{s}' from dependency '{s}'", .{
                    section,
                    name,
                    field_name,
                    path,
                    export_name,
                    dep_name,
                });
                return true;
            }
            return false;
        }

        if (dep.builder.named_writefiles.get(export_name) == null) {
            self.invalidateManifest("{s} '{s}': {s} path '{s}' could not resolve WriteFiles step '{s}' from dependency '{s}'", .{
                section,
                name,
                field_name,
                path,
                export_name,
                dep_name,
            });
            return true;
        }

        return false;
    }

    fn invalidateManifest(self: *BuildRunner, comptime fmt: []const u8, args: anytype) void {
        std.log.err("zbuild: " ++ fmt, args);
        self.b.invalid_user_input = true;
    }

    fn lookupDependencyArtifact(dep: *std.Build.Dependency, name: []const u8) DependencyArtifactLookup {
        var found: ?*std.Build.Step.Compile = null;
        for (dep.builder.install_tls.step.dependencies.items) |dep_step| {
            const inst = dep_step.cast(std.Build.Step.InstallArtifact) orelse continue;
            if (!std.mem.eql(u8, inst.artifact.name, name)) continue;
            if (found != null) return .ambiguous;
            found = inst.artifact;
        }
        return if (found) |artifact| .{ .found = artifact } else .missing;
    }

    // --- Module creation ---

    const module_passthrough_fields = .{
        "link_libc",       "link_libcpp",   "single_threaded",
        "strip",           "unwind_tables", "dwarf_format",
        "code_model",      "error_tracing", "omit_frame_pointer",
        "pic",             "red_zone",      "sanitize_c",
        "sanitize_thread", "stack_check",   "stack_protector",
        "fuzz",            "valgrind",
    };

    fn createModule(self: *BuildRunner, comptime mod: anytype, name: []const u8) Error!*std.Build.Module {
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
                const lib_spec = comptime toComptimeString(@field(mod.link_libraries, field.name));
                const dep_name = comptime comptimeBaseName(lib_spec);
                const artifact_name = comptime comptimeAfterSep(lib_spec);
                if (self.result.dependencies.get(dep_name)) |dep| {
                    switch (lookupDependencyArtifact(dep, artifact_name)) {
                        .found => |artifact| m.linkLibrary(artifact),
                        .missing => {
                            self.invalidateManifest("modules '{s}': link_libraries entry '{s}' could not resolve artifact '{s}' from dependency '{s}'", .{
                                name,
                                lib_spec,
                                artifact_name,
                                dep_name,
                            });
                            return error.ModuleNotFound;
                        },
                        .ambiguous => {
                            self.invalidateManifest("modules '{s}': link_libraries entry '{s}' resolves ambiguous artifact '{s}' from dependency '{s}'", .{
                                name,
                                lib_spec,
                                artifact_name,
                                dep_name,
                            });
                            return error.ModuleNotFound;
                        },
                    }
                }
            }
        }

        try self.result.modules.put(name, m);
        return m;
    }

    fn resolveModuleLink(self: *BuildRunner, comptime link: anytype, name: []const u8) Error!*std.Build.Module {
        const ti = @typeInfo(@TypeOf(link));
        if (ti == .enum_literal) {
            const mod_name = @tagName(link);
            return self.result.modules.get(mod_name) orelse {
                std.log.err("zbuild: module '{s}' not found", .{mod_name});
                return error.ModuleNotFound;
            };
        } else if (ti == .pointer) {
            const str: []const u8 = link;
            return self.result.modules.get(str) orelse {
                std.log.err("zbuild: module '{s}' not found", .{str});
                return error.ModuleNotFound;
            };
        } else if (ti == .@"struct") {
            const mod_name: []const u8 = if (@hasField(@TypeOf(link), "name")) link.name else name;
            return try self.createModule(link, mod_name);
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
        try self.result.executables.put(name, artifact);

        try self.installAndRegister("build-exe", "executable", name, artifact, .{
            .dest_sub_path = if (@hasField(Exe, "dest_sub_path")) exe.dest_sub_path else null,
        });

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

        var add_opts: std.Build.LibraryOptions = .{
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
        try self.result.libraries.put(name, artifact);

        if (@hasField(Lib, "linker_allow_shlib_undefined")) {
            artifact.linker_allow_shlib_undefined = lib.linker_allow_shlib_undefined;
        }

        try self.installAndRegister("build-lib", "library", name, artifact, .{
            .dest_sub_path = if (@hasField(Lib, "dest_sub_path")) lib.dest_sub_path else null,
        });
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
        try self.result.objects.put(name, artifact);

        try self.installAndRegister("build-obj", "object", name, artifact, .{});
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
        try self.result.tests.put(name, artifact);

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

    fn createFmt(self: *BuildRunner, comptime name: []const u8, comptime fmt: anytype, tls_run_fmt: *std.Build.Step) Error!void {
        const Fmt = @TypeOf(fmt);
        const step = self.b.addFmt(.{
            .paths = if (@hasField(Fmt, "paths")) comptime toStringSlice(fmt.paths) else &.{},
            .exclude_paths = if (@hasField(Fmt, "exclude_paths")) comptime toStringSlice(fmt.exclude_paths) else &.{},
            .check = if (@hasField(Fmt, "check")) fmt.check else false,
        });
        try self.result.fmts.put(name, step);

        const tls = self.b.step(
            self.b.fmt("fmt:{s}", .{name}),
            self.b.fmt("Run the {s} fmt", .{name}),
        );
        tls.dependOn(&step.step);
        tls_run_fmt.dependOn(&step.step);
    }

    fn createRun(self: *BuildRunner, comptime name: []const u8, comptime cmd: anytype) Error!void {
        const is_long_form = @hasField(@TypeOf(cmd), "cmd");
        const args_tuple = if (is_long_form) cmd.cmd else cmd;
        const run = self.b.addSystemCommand(comptime toStringSlice(args_tuple));
        try self.result.runs.put(name, run);

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
    }

    fn installAndRegister(
        self: *BuildRunner,
        comptime prefix: []const u8,
        comptime label: []const u8,
        comptime name: []const u8,
        artifact: *std.Build.Step.Compile,
        install_opts: std.Build.Step.InstallArtifact.Options,
    ) Error!void {
        const install = self.b.addInstallArtifact(artifact, install_opts);
        const tls = self.b.step(
            self.b.fmt(prefix ++ ":{s}", .{name}),
            self.b.fmt("Install the {s} " ++ label, .{name}),
        );
        tls.dependOn(&install.step);
        self.b.getInstallStep().dependOn(&install.step);
        try self.install_steps.put(name, &install.step);
    }

    // --- Options modules ---

    fn createOptionsModule(self: *BuildRunner, comptime name: []const u8, comptime options: anytype) !void {
        var source: std.ArrayList(u8) = .empty;
        defer source.deinit(self.b.allocator);

        try source.appendSlice(self.b.allocator, "//! Generated by zbuild.\n\n");

        var emitted_type_names: std.ArrayList([]const u8) = .empty;
        defer {
            for (emitted_type_names.items) |type_name| self.b.allocator.free(type_name);
            emitted_type_names.deinit(self.b.allocator);
        }

        const fields = @typeInfo(@TypeOf(options)).@"struct".fields;
        inline for (fields) |field| {
            const opt = @field(options, field.name);
            if (!comptime isEnumOptionType(optionTypeString(opt))) continue;

            const type_name = try self.optionTypeNameAlloc(field.name, opt);
            if (stringSliceContains(emitted_type_names.items, type_name)) {
                self.b.allocator.free(type_name);
            } else {
                try emitted_type_names.append(self.b.allocator, type_name);
                try emitEnumType(&source, self.b.allocator, type_name, enumOptionValues(opt));
                try source.appendSlice(self.b.allocator, "\n");
            }
        }

        inline for (fields) |field| {
            try self.emitOptionField(&source, name, field.name, @field(options, field.name));
        }

        const write_file = self.b.addWriteFiles();
        const generated = write_file.add(self.b.fmt("zbuild-options-{s}.zig", .{name}), source.items);
        const m = self.b.createModule(.{
            .root_source_file = generated,
        });
        try self.result.options_modules.put(name, m);
    }

    fn optionTypeNameAlloc(self: *BuildRunner, comptime option_name: []const u8, comptime opt: anytype) ![]const u8 {
        if (@hasField(@TypeOf(opt), "type_name")) {
            return self.b.allocator.dupe(u8, opt.type_name);
        }
        return pascalCaseAlloc(self.b.allocator, option_name);
    }

    fn emitOptionField(self: *BuildRunner, out: *std.ArrayList(u8), comptime module_name: []const u8, comptime option_name: []const u8, comptime opt: anytype) !void {
        const gpa = self.b.allocator;
        const Opt = @TypeOf(opt);
        const type_str = comptime optionTypeString(opt);
        const desc: []const u8 = if (@hasField(Opt, "description")) opt.description else "";
        const cli_name = comptime module_name ++ "." ++ option_name;

        if (comptime std.mem.eql(u8, type_str, "bool")) {
            const value = self.b.option(bool, cli_name, desc);
            if (@hasField(Opt, "default")) {
                try out.print(gpa, "pub const {f}: bool = {any};\n", .{
                    std.zig.fmtId(option_name),
                    value orelse opt.default,
                });
            } else if (value) |resolved| {
                try out.print(gpa, "pub const {f}: ?bool = {any};\n", .{
                    std.zig.fmtId(option_name),
                    resolved,
                });
            } else {
                try out.print(gpa, "pub const {f}: ?bool = null;\n", .{std.zig.fmtId(option_name)});
            }
            return;
        }

        if (comptime std.mem.eql(u8, type_str, "string")) {
            const value = self.b.option([]const u8, cli_name, desc);
            if (value) |resolved| {
                if (@hasField(Opt, "default")) {
                    try out.print(gpa, "pub const {f}: []const u8 = \"{f}\";\n", .{
                        std.zig.fmtId(option_name),
                        std.zig.fmtString(resolved),
                    });
                } else {
                    try out.print(gpa, "pub const {f}: ?[]const u8 = \"{f}\";\n", .{
                        std.zig.fmtId(option_name),
                        std.zig.fmtString(resolved),
                    });
                }
            } else if (@hasField(Opt, "default")) {
                try out.print(gpa, "pub const {f}: []const u8 = \"{f}\";\n", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtString(opt.default),
                });
            } else {
                try out.print(gpa, "pub const {f}: ?[]const u8 = null;\n", .{std.zig.fmtId(option_name)});
            }
            return;
        }

        if (comptime std.mem.eql(u8, type_str, "list")) {
            const value = self.b.option([]const []const u8, cli_name, desc);
            if (value) |resolved| {
                if (@hasField(Opt, "default")) {
                    try out.print(gpa, "pub const {f}: []const []const u8 = ", .{std.zig.fmtId(option_name)});
                } else {
                    try out.print(gpa, "pub const {f}: ?[]const []const u8 = ", .{std.zig.fmtId(option_name)});
                }
                try emitStringListLiteral(out, gpa, resolved);
                try out.appendSlice(gpa, ";\n");
            } else if (@hasField(Opt, "default")) {
                try out.print(gpa, "pub const {f}: []const []const u8 = ", .{std.zig.fmtId(option_name)});
                try emitStringListLiteral(out, gpa, comptime toStringSlice(opt.default));
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.print(gpa, "pub const {f}: ?[]const []const u8 = null;\n", .{std.zig.fmtId(option_name)});
            }
            return;
        }

        if (comptime std.mem.eql(u8, type_str, "enum")) {
            const allowed = comptime enumOptionValues(opt);
            const type_name = try self.optionTypeNameAlloc(option_name, opt);
            defer gpa.free(type_name);
            const value = self.b.option([]const u8, cli_name, desc);
            const resolved = if (value) |candidate|
                if (self.validateEnumOptionValue(cli_name, candidate, allowed))
                    @as(?[]const u8, candidate)
                else if (@hasField(Opt, "default"))
                    @as(?[]const u8, toComptimeString(opt.default))
                else
                    null
            else if (@hasField(Opt, "default"))
                @as(?[]const u8, toComptimeString(opt.default))
            else
                null;

            if (@hasField(Opt, "default")) {
                try out.print(gpa, "pub const {f}: {f} = .{f};\n", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtId(type_name),
                    std.zig.fmtIdFlags(resolved.?, .{ .allow_primitive = true, .allow_underscore = true }),
                });
            } else if (resolved) |tag| {
                try out.print(gpa, "pub const {f}: ?{f} = .{f};\n", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtId(type_name),
                    std.zig.fmtIdFlags(tag, .{ .allow_primitive = true, .allow_underscore = true }),
                });
            } else {
                try out.print(gpa, "pub const {f}: ?{f} = null;\n", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtId(type_name),
                });
            }
            return;
        }

        if (comptime std.mem.eql(u8, type_str, "enum_list")) {
            const allowed = comptime enumOptionValues(opt);
            const type_name = try self.optionTypeNameAlloc(option_name, opt);
            defer gpa.free(type_name);
            const value = self.b.option([]const []const u8, cli_name, desc);
            const resolved = if (value) |candidates|
                if (self.validateEnumOptionValues(cli_name, candidates, allowed))
                    @as(?[]const []const u8, candidates)
                else if (@hasField(Opt, "default"))
                    @as(?[]const []const u8, comptime toComptimeStringSlice(opt.default))
                else
                    null
            else if (@hasField(Opt, "default"))
                @as(?[]const []const u8, comptime toComptimeStringSlice(opt.default))
            else
                null;

            if (@hasField(Opt, "default")) {
                try out.print(gpa, "pub const {f}: []const {f} = ", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtId(type_name),
                });
                try emitEnumListLiteral(out, gpa, resolved.?);
                try out.appendSlice(gpa, ";\n");
            } else if (resolved) |tags| {
                try out.print(gpa, "pub const {f}: ?[]const {f} = ", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtId(type_name),
                });
                try emitEnumListLiteral(out, gpa, tags);
                try out.appendSlice(gpa, ";\n");
            } else {
                try out.print(gpa, "pub const {f}: ?[]const {f} = null;\n", .{
                    std.zig.fmtId(option_name),
                    std.zig.fmtId(type_name),
                });
            }
            return;
        }

        if (comptime isIntType(type_str) or isFloatType(type_str)) {
            const T = comptime optionValueType(type_str);
            const value = self.b.option(T, cli_name, desc);
            if (@hasField(Opt, "default")) {
                try out.print(gpa, "pub const {f}: {s} = {any};\n", .{
                    std.zig.fmtId(option_name),
                    type_str,
                    value orelse opt.default,
                });
            } else if (value) |resolved| {
                try out.print(gpa, "pub const {f}: ?{s} = {any};\n", .{
                    std.zig.fmtId(option_name),
                    type_str,
                    resolved,
                });
            } else {
                try out.print(gpa, "pub const {f}: ?{s} = null;\n", .{
                    std.zig.fmtId(option_name),
                    type_str,
                });
            }
            return;
        }

        @compileError("unknown option type '" ++ type_str ++ "'");
    }

    fn validateEnumOptionValue(self: *BuildRunner, name: []const u8, actual: []const u8, allowed: []const []const u8) bool {
        if (stringSliceContains(allowed, actual)) return true;
        self.logInvalidEnumOptionValue(name, actual, allowed);
        return false;
    }

    fn validateEnumOptionValues(self: *BuildRunner, name: []const u8, actual: []const []const u8, allowed: []const []const u8) bool {
        var ok = true;
        for (actual) |value| {
            ok = self.validateEnumOptionValue(name, value, allowed) and ok;
        }
        return ok;
    }

    fn logInvalidEnumOptionValue(self: *BuildRunner, name: []const u8, actual: []const u8, allowed: []const []const u8) void {
        var expected: std.ArrayList(u8) = .empty;
        defer expected.deinit(self.b.allocator);

        for (allowed, 0..) |value, i| {
            if (i > 0) expected.appendSlice(self.b.allocator, ", ") catch @panic("OOM");
            expected.appendSlice(self.b.allocator, value) catch @panic("OOM");
        }

        std.log.err("invalid value for -D{s}: '{s}' (expected one of: {s})", .{
            name,
            actual,
            expected.items,
        });
        self.b.invalid_user_input = true;
    }

    // --- Import wiring ---

    fn wireAllImports(self: *BuildRunner, comptime manifest: anytype) Error!void {
        if (@hasField(@TypeOf(manifest), "modules")) {
            inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
                const mod = @field(manifest.modules, field.name);
                if (@hasField(@TypeOf(mod), "imports")) {
                    if (self.result.modules.get(field.name)) |m| {
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
                            if (self.result.modules.get(mod_name)) |m| {
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
            const import_name = comptime toComptimeString(@field(imports, field.name));
            const resolved = try self.resolveImport(import_name);
            module.addImport(import_name, resolved);
        }
    }

    // --- depends_on wiring ---

    fn wireDependsOn(self: *BuildRunner, comptime manifest: anytype) void {
        // Artifacts: wire install step
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
        // Tests: wire via test run step
        if (@hasField(@TypeOf(manifest), "tests")) {
            inline for (@typeInfo(@TypeOf(manifest.tests)).@"struct".fields) |field| {
                const item = @field(manifest.tests, field.name);
                if (@hasField(@TypeOf(item), "depends_on")) {
                    if (self.b.top_level_steps.get(self.b.fmt("test:{s}", .{field.name}))) |tls| {
                        self.wireDependsOnList(&tls.step, item.depends_on);
                    }
                }
            }
        }
        // Runs: wire via cmd step
        if (@hasField(@TypeOf(manifest), "runs")) {
            inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
                const run = @field(manifest.runs, field.name);
                if (@hasField(@TypeOf(run), "cmd") and @hasField(@TypeOf(run), "depends_on")) {
                    if (self.b.top_level_steps.get(self.b.fmt("cmd:{s}", .{field.name}))) |tls| {
                        self.wireDependsOnList(&tls.step, run.depends_on);
                    }
                }
            }
        }
    }

    fn wireDependsOnList(self: *BuildRunner, step: *std.Build.Step, comptime deps: anytype) void {
        inline for (@typeInfo(@TypeOf(deps)).@"struct".fields) |field| {
            const dep_name = comptime toComptimeString(@field(deps, field.name));
            const dep_step = if (comptime std.mem.indexOfScalar(u8, dep_name, ':') != null)
                // Explicit step reference: look up by full step name
                if (self.b.top_level_steps.get(dep_name)) |tls| &tls.step else null
            else
                // Plain name: look up install step
                self.install_steps.get(dep_name);
            if (dep_step) |s| {
                step.dependOn(s);
            } else {
                std.log.warn("zbuild: depends_on references unknown step '{s}'", .{dep_name});
            }
        }
    }

    // --- Resolution helpers (runtime) ---

    fn resolveImport(self: *BuildRunner, import_name: []const u8) Error!*std.Build.Module {
        if (self.result.modules.get(import_name)) |m| return m;
        if (self.result.options_modules.get(import_name)) |m| return m;
        var parts = std.mem.splitScalar(u8, import_name, ':');
        const first = parts.first();
        if (self.result.dependencies.get(first)) |dep| {
            const module_name = if (parts.next()) |rest| rest else first;
            if (dep.builder.modules.get(module_name)) |module| return module;
            self.invalidateManifest("dependency import '{s}' could not resolve module '{s}' from dependency '{s}'", .{
                import_name,
                module_name,
                first,
            });
            return error.ModuleNotFound;
        }
        std.log.err("zbuild: unresolved import '{s}'", .{import_name});
        return error.ModuleNotFound;
    }

    fn resolveLazyPath(self: *BuildRunner, path: []const u8) std.Build.LazyPath {
        if (countSeparators(path, ':') == 0) return self.b.path(path);

        var parts = std.mem.splitScalar(u8, path, ':');
        const first = parts.first();
        if (self.result.dependencies.get(first)) |dep| {
            const next = parts.next() orelse return self.b.path(path);
            if (parts.next()) |last| {
                if (dep.builder.named_writefiles.get(next)) |write_files| {
                    return write_files.getDirectory().path(self.b, last);
                }
                self.invalidateManifest("lazy path '{s}' could not resolve WriteFiles step '{s}' from dependency '{s}'", .{
                    path,
                    next,
                    first,
                });
                return self.b.path(path);
            }
            if (dep.builder.named_lazy_paths.get(next)) |lazy_path| {
                return lazy_path;
            }
            self.invalidateManifest("lazy path '{s}' could not resolve named lazy path '{s}' from dependency '{s}'", .{
                path,
                next,
                first,
            });
            return self.b.path(path);
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

fn toComptimeStringSlice(comptime tuple: anytype) []const []const u8 {
    const fields = @typeInfo(@TypeOf(tuple)).@"struct".fields;
    var result: [fields.len][]const u8 = undefined;
    inline for (fields, 0..) |field, i| {
        result[i] = toComptimeString(@field(tuple, field.name));
    }
    const final = result;
    return &final;
}

fn optionTypeString(comptime opt: anytype) []const u8 {
    return toComptimeString(opt.type);
}

fn isSupportedOptionType(comptime t: []const u8) bool {
    return std.mem.eql(u8, t, "bool") or
        std.mem.eql(u8, t, "string") or
        std.mem.eql(u8, t, "list") or
        std.mem.eql(u8, t, "enum") or
        std.mem.eql(u8, t, "enum_list") or
        isIntType(t) or
        isFloatType(t);
}

fn isEnumOptionType(comptime t: []const u8) bool {
    return std.mem.eql(u8, t, "enum") or std.mem.eql(u8, t, "enum_list");
}

fn optionValueType(comptime t: []const u8) type {
    if (comptime std.mem.eql(u8, t, "bool")) return bool;
    if (comptime std.mem.eql(u8, t, "string")) return []const u8;
    if (comptime std.mem.eql(u8, t, "list")) return []const []const u8;

    inline for (.{
        .{ "i8", i8 },           .{ "u8", u8 },                     .{ "i16", i16 },               .{ "u16", u16 },
        .{ "i32", i32 },         .{ "u32", u32 },                   .{ "i64", i64 },               .{ "u64", u64 },
        .{ "i128", i128 },       .{ "u128", u128 },                 .{ "isize", isize },           .{ "usize", usize },
        .{ "c_short", c_short }, .{ "c_ushort", c_ushort },         .{ "c_int", c_int },           .{ "c_uint", c_uint },
        .{ "c_long", c_long },   .{ "c_ulong", c_ulong },           .{ "c_longlong", c_longlong }, .{ "c_ulonglong", c_ulonglong },
        .{ "f16", f16 },         .{ "f32", f32 },                   .{ "f64", f64 },               .{ "f80", f80 },
        .{ "f128", f128 },       .{ "c_longdouble", c_longdouble },
    }) |entry| {
        if (comptime std.mem.eql(u8, t, entry[0])) return entry[1];
    }

    @compileError("unsupported option type '" ++ t ++ "'");
}

fn enumOptionValues(comptime opt: anytype) []const []const u8 {
    const values = comptime toComptimeStringSlice(opt.values);
    if (values.len == 0) {
        @compileError("enum options require a non-empty 'values' field");
    }

    inline for (values, 0..) |value, i| {
        if (!comptime isValidEnumTagName(value)) {
            @compileError("invalid enum value '" ++ value ++ "': values must be non-empty Zig-style identifiers");
        }
        inline for (values[i + 1 ..]) |other| {
            if (comptime std.mem.eql(u8, value, other)) {
                @compileError("duplicate enum value '" ++ value ++ "'");
            }
        }
    }
    return values;
}

fn resolvedOptionTypeName(comptime option_name: []const u8, comptime opt: anytype) []const u8 {
    return if (@hasField(@TypeOf(opt), "type_name"))
        opt.type_name
    else
        comptimePascalCase(option_name);
}

fn comptimePascalCase(comptime name: []const u8) []const u8 {
    comptime var result: [name.len]u8 = undefined;
    comptime var len: usize = 0;
    comptime var upper = true;

    inline for (name) |c| {
        if (c == '_') {
            upper = true;
            continue;
        }
        result[len] = if (upper) std.ascii.toUpper(c) else c;
        len += 1;
        upper = false;
    }

    const final = result[0..len].*;
    return &final;
}

fn pascalCaseAlloc(allocator: std.mem.Allocator, name: []const u8) ![]const u8 {
    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);

    var upper = true;
    for (name) |c| {
        if (c == '_') {
            upper = true;
            continue;
        }
        try result.append(allocator, if (upper) std.ascii.toUpper(c) else c);
        upper = false;
    }

    return result.toOwnedSlice(allocator);
}

fn isValidEnumTagName(name: []const u8) bool {
    if (name.len == 0) return false;
    if (std.zig.isUnderscore(name)) return false;

    for (name, 0..) |c, i| {
        switch (c) {
            '_', 'a'...'z', 'A'...'Z' => {},
            '0'...'9' => if (i == 0) return false,
            else => return false,
        }
    }

    return true;
}

fn stringSliceContains(haystack: []const []const u8, needle: []const u8) bool {
    for (haystack) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}

fn stringSlicesEql(a: []const []const u8, b: []const []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |lhs, rhs| {
        if (!std.mem.eql(u8, lhs, rhs)) return false;
    }
    return true;
}

fn emitEnumType(out: *std.ArrayList(u8), gpa: std.mem.Allocator, type_name: []const u8, values: []const []const u8) !void {
    try out.print(gpa, "pub const {f} = enum {{\n", .{std.zig.fmtId(type_name)});
    for (values) |value| {
        try out.print(gpa, "    {f},\n", .{std.zig.fmtIdFlags(value, .{ .allow_primitive = true, .allow_underscore = true })});
    }
    try out.appendSlice(gpa, "};\n");
}

fn emitStringListLiteral(out: *std.ArrayList(u8), gpa: std.mem.Allocator, values: []const []const u8) !void {
    try out.appendSlice(gpa, "&.{\n");
    for (values) |value| {
        try out.print(gpa, "    \"{f}\",\n", .{std.zig.fmtString(value)});
    }
    try out.appendSlice(gpa, "}");
}

fn emitEnumListLiteral(out: *std.ArrayList(u8), gpa: std.mem.Allocator, values: []const []const u8) !void {
    try out.appendSlice(gpa, "&.{\n");
    for (values) |value| {
        try out.print(gpa, "    .{f},\n", .{std.zig.fmtIdFlags(value, .{ .allow_primitive = true, .allow_underscore = true })});
    }
    try out.appendSlice(gpa, "}");
}

fn isIntType(comptime t: []const u8) bool {
    return for ([_][]const u8{
        "i8",     "u8",      "i16",        "u16",         "i32",     "u32",      "i64",   "u64",
        "i128",   "u128",    "isize",      "usize",       "c_short", "c_ushort", "c_int", "c_uint",
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

test "toComptimeStringSlice" {
    const result = comptime toComptimeStringSlice(.{ .debug, "info", .warn });
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

test "hasDependency" {
    const manifest = .{
        .dependencies = .{
            .zlib = .{},
        },
    };
    try std.testing.expect(comptime hasDependency(manifest, "zlib"));
    try std.testing.expect(!comptime hasDependency(manifest, "missing"));
}

test "hasStepTarget" {
    const manifest = .{
        .executables = .{ .myapp = .{ .root_module = .{ .root_source_file = "src/main.zig" } } },
        .tests = .{ .unit = .{ .root_module = .{ .root_source_file = "src/test.zig" } } },
        .runs = .{ .deploy = .{ "echo", "deploy" } },
        .fmts = .{ .src = .{ .paths = .{"src"} } },
    };
    // Executable steps
    try std.testing.expect(comptime hasStepTarget(manifest, "build-exe:myapp"));
    try std.testing.expect(comptime hasStepTarget(manifest, "run:myapp"));
    try std.testing.expect(!comptime hasStepTarget(manifest, "run:missing"));
    // Test steps
    try std.testing.expect(comptime hasStepTarget(manifest, "test:unit"));
    try std.testing.expect(comptime hasStepTarget(manifest, "build-test:unit"));
    // Run steps
    try std.testing.expect(comptime hasStepTarget(manifest, "cmd:deploy"));
    try std.testing.expect(!comptime hasStepTarget(manifest, "cmd:missing"));
    // Fmt steps
    try std.testing.expect(comptime hasStepTarget(manifest, "fmt:src"));
    // Unknown prefix
    try std.testing.expect(!comptime hasStepTarget(manifest, "bogus:myapp"));
}

test "validateManifest accepts step references in depends_on" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .executables = .{
            .myapp = .{ .root_module = .{ .root_source_file = "src/main.zig" } },
        },
        .tests = .{
            .unit = .{ .root_module = .{ .root_source_file = "src/test.zig" } },
        },
        .runs = .{
            .deploy = .{
                .cmd = .{"./deploy.sh"},
                .depends_on = .{ .myapp, "test:unit" },
            },
        },
    });
}

test "isImportable" {
    const manifest = .{
        .modules = .{
            .core = .{ .root_source_file = "src/core.zig" },
        },
        .options_modules = .{
            .config = .{ .some_flag = .{ .type = .bool } },
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
    // Invalid dependency import syntax is rejected
    try std.testing.expect(!comptime isImportable(manifest, "zlib:"));
    try std.testing.expect(!comptime isImportable(manifest, "zlib:zlib:extra"));
    // Unknown is not importable
    try std.testing.expect(!comptime isImportable(manifest, "missing"));
}

test "comptimeBaseName" {
    try std.testing.expectEqualStrings("zlib", comptime comptimeBaseName("zlib"));
    try std.testing.expectEqualStrings("zlib", comptime comptimeBaseName("zlib:zlib"));
    try std.testing.expectEqualStrings("foo", comptime comptimeBaseName("foo:bar:baz"));
    try std.testing.expectEqualStrings("", comptime comptimeBaseName(""));
}

test "comptimeAfterSep" {
    try std.testing.expectEqualStrings("zlib", comptime comptimeAfterSep("zlib"));
    try std.testing.expectEqualStrings("zlib", comptime comptimeAfterSep("dep:zlib"));
    try std.testing.expectEqualStrings("bar:baz", comptime comptimeAfterSep("foo:bar:baz"));
    try std.testing.expectEqualStrings("", comptime comptimeAfterSep(""));
}

test "toComptimeString" {
    try std.testing.expectEqualStrings("hello", comptime toComptimeString("hello"));
    try std.testing.expectEqualStrings("world", comptime toComptimeString(.world));
}

test "countSeparators" {
    try std.testing.expectEqual(@as(usize, 0), countSeparators("plain", ':'));
    try std.testing.expectEqual(@as(usize, 1), countSeparators("dep:module", ':'));
    try std.testing.expectEqual(@as(usize, 2), countSeparators("dep:wf:path", ':'));
}

test "comptimePascalCase" {
    try std.testing.expectEqualStrings("LogLevel", comptime comptimePascalCase("log_level"));
    try std.testing.expectEqualStrings("EnabledLevels", comptime comptimePascalCase("enabled_levels"));
    try std.testing.expectEqualStrings("Http2", comptime comptimePascalCase("http2"));
}

test "resolvedOptionTypeName" {
    try std.testing.expectEqualStrings("LogLevel", comptime resolvedOptionTypeName("log_level", .{
        .type = .@"enum",
        .values = .{ .debug, .info, .warn },
    }));
    try std.testing.expectEqualStrings("Verbosity", comptime resolvedOptionTypeName("log_level", .{
        .type = .@"enum",
        .type_name = "Verbosity",
        .values = .{ .debug, .info, .warn },
    }));
}

test "validateManifest accepts typed options modules" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .options_modules = .{
            .config = .{
                .verbose = .{
                    .type = .bool,
                    .default = false,
                },
                .log_level = .{
                    .type = .@"enum",
                    .values = .{ .debug, .info, .warn },
                    .default = .info,
                },
                .enabled_levels = .{
                    .type = .enum_list,
                    .values = .{ .debug, .info, .warn },
                    .default = .{ .info, .warn },
                },
                .output_dir = .{
                    .type = .string,
                },
            },
        },
    });
}

test "validateManifest accepts minimal manifest" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
    });
}

test "validateManifest accepts valid cross-references" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
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
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .some_future_zig_field = "should be ignored",
    });
}

test "validateManifest accepts short-form runs" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .runs = .{
            .fmt = .{ "zig", "fmt", "src" },
        },
    });
}

test "validateManifest accepts long-form runs" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .executables = .{
            .myapp = .{ .root_module = .{ .root_source_file = "src/main.zig" } },
        },
        .runs = .{
            .deploy = .{
                .cmd = .{"./deploy.sh"},
                .cwd = "scripts",
                .env = .{ .NODE_ENV = "production" },
                .depends_on = .{.myapp},
            },
        },
    });
}

test "validateManifest accepts run and executable with same name" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .executables = .{
            .deploy = .{ .root_module = .{ .root_source_file = "src/main.zig" } },
        },
        .runs = .{
            .deploy = .{ "echo", "deploying" },
        },
    });
}

test "validateManifest accepts runs with unknown fields" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .runs = .{
            .deploy = .{
                .cmd = .{"./deploy.sh"},
                .some_future_field = "ignored",
            },
        },
    });
}
