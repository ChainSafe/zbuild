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
        .inline_modules = std.StringHashMap(*std.Build.Module).init(b.allocator),
        .manual_modules = std.StringHashMap(void).init(b.allocator),
        .manual_steps = std.StringHashMap(void).init(b.allocator),
    };
    defer runner.manual_modules.deinit();
    defer runner.manual_steps.deinit();

    try runner.snapshotPreexistingNamespaces();
    comptime validateManifest(manifest, opts);

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
    if (try runner.validateNamespaceReservations(manifest, opts)) return error.InvalidManifest;

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
            const m = try runner.createModule(mod, field.name, &runner.result.modules);
            const is_private = @hasField(@TypeOf(mod), "private") and mod.private;
            if (!is_private) {
                try runner.registerPublicModule(field.name, m);
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
        const tls_run_test = try runner.createTopLevelStep("test", "Run all tests");
        inline for (@typeInfo(@TypeOf(manifest.tests)).@"struct".fields) |field| {
            try runner.createTest(field.name, @field(manifest.tests, field.name), tls_run_test);
        }
    }

    // Phase 8: Create fmts
    if (@hasField(@TypeOf(manifest), "fmts")) {
        const tls_run_fmt = try runner.createTopLevelStep("fmt", "Run all fmts");
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
    try runner.wireDependsOn(manifest, opts);

    // Phase 12: Add help step
    if (opts.help_step) |step_name| {
        const tls = try runner.createTopLevelStep(step_name, "Show project build information");
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
        tls.dependOn(help_step_impl);
    }

    return runner.result;
}

// --- Manifest validation ---
//
// Cross-reference checks run at comptime for manifest-owned targets so typos in
// local module names, dependency references, and artifact names become compile
// errors. Manual build.zig modules and steps are validated during configure.

fn validateManifest(comptime manifest: anytype, comptime opts: Options) void {
    validateInlineModuleNames(manifest);

    // Validate artifact sections: root_module refs, depends_on, and inline module imports
    inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
        if (@hasField(@TypeOf(manifest), section)) {
            inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                const item = @field(@field(manifest, section), field.name);
                validateArtifactSectionFields(section, field.name, item);
                validateRootModuleRef(manifest, item.root_module, section, field.name);
                validateArtifactFields(manifest, item, section, field.name);
                if (@hasField(@TypeOf(item), "depends_on"))
                    validateDependsOn(manifest, opts, item.depends_on, section, field.name);
                if (isInlineRootModuleType(@TypeOf(item.root_module))) {
                    validateModuleDefinition(manifest, item.root_module, section, field.name, true, false);
                }
            }
        }
    }

    // Validate named module imports
    if (@hasField(@TypeOf(manifest), "modules")) {
        inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
            validateModuleDefinition(manifest, @field(manifest.modules, field.name), "modules", field.name, false, true);
        }
    }

    if (@hasField(@TypeOf(manifest), "fmts")) {
        inline for (@typeInfo(@TypeOf(manifest.fmts)).@"struct".fields) |field| {
            validateFmtFields(field.name, @field(manifest.fmts, field.name));
        }
    }

    validateOptionsModules(manifest);

    // Validate runs: depends_on refs and stdin/stdin_file exclusion
    if (@hasField(@TypeOf(manifest), "runs")) {
        inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
            const run = @field(manifest.runs, field.name);
            if (@hasField(@TypeOf(run), "cmd")) {
                validateRunFields(field.name, run);
                if (@hasField(@TypeOf(run), "depends_on"))
                    validateDependsOn(manifest, opts, run.depends_on, "runs", field.name);
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

fn validateArtifactSectionFields(comptime section: []const u8, comptime name: []const u8, comptime item: anytype) void {
    inline for (@typeInfo(@TypeOf(item)).@"struct".fields) |field| {
        if (!isKnownArtifactField(section, field.name)) {
            @compileError(section ++ " '" ++ name ++ "': unknown field '" ++ field.name ++ "'");
        }
    }
}

const UpstreamFieldBinding = enum {
    passthrough,
    adapted,
    ignored,
};

fn isKnownArtifactField(comptime section: []const u8, comptime field_name: []const u8) bool {
    if (artifactOptionsFieldBinding(section, field_name)) |binding| {
        return binding != .ignored;
    }

    if (comptime std.mem.eql(u8, field_name, "depends_on")) return true;

    if ((comptime std.mem.eql(u8, section, "executables") or std.mem.eql(u8, section, "libraries")) and
        comptime std.mem.eql(u8, field_name, "dest_sub_path"))
    {
        return true;
    }

    if (comptime std.mem.eql(u8, section, "libraries") and
        std.mem.eql(u8, field_name, "linker_allow_shlib_undefined"))
    {
        return true;
    }

    return false;
}

fn validateFmtFields(comptime name: []const u8, comptime fmt: anytype) void {
    inline for (@typeInfo(@TypeOf(fmt)).@"struct".fields) |field| {
        if (!std.mem.eql(u8, field.name, "paths") and
            !std.mem.eql(u8, field.name, "exclude_paths") and
            !std.mem.eql(u8, field.name, "check"))
        {
            @compileError("fmts '" ++ name ++ "': unknown field '" ++ field.name ++ "'");
        }
    }
}

fn validateRunFields(comptime name: []const u8, comptime run: anytype) void {
    inline for (@typeInfo(@TypeOf(run)).@"struct".fields) |field| {
        if (!std.mem.eql(u8, field.name, "cmd") and
            !std.mem.eql(u8, field.name, "cwd") and
            !std.mem.eql(u8, field.name, "env") and
            !std.mem.eql(u8, field.name, "inherit_stdio") and
            !std.mem.eql(u8, field.name, "stdin") and
            !std.mem.eql(u8, field.name, "stdin_file") and
            !std.mem.eql(u8, field.name, "depends_on"))
        {
            @compileError("runs '" ++ name ++ "': unknown field '" ++ field.name ++ "'");
        }
    }
}

fn validateInlineModuleNames(comptime manifest: anytype) void {
    inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
        if (!@hasField(@TypeOf(manifest), section)) continue;

        const items = @field(manifest, section);
        const item_fields = @typeInfo(@TypeOf(items)).@"struct".fields;
        inline for (item_fields, 0..) |field, i| {
            const item = @field(items, field.name);
            if (!isInlineRootModuleType(@TypeOf(item.root_module))) continue;

            const inline_name = inlineRootModuleName(field.name, item.root_module);
            if (hasModule(manifest, inline_name)) {
                @compileError(section ++ " '" ++ field.name ++ "': inline root_module name '" ++ inline_name ++ "' collides with named module '" ++ inline_name ++ "'");
            }

            inline for (item_fields[i + 1 ..]) |other_field| {
                const other_item = @field(items, other_field.name);
                if (!isInlineRootModuleType(@TypeOf(other_item.root_module))) continue;
                const other_name = inlineRootModuleName(other_field.name, other_item.root_module);
                if (comptime std.mem.eql(u8, inline_name, other_name)) {
                    @compileError(section ++ " '" ++ field.name ++ "': inline root_module name '" ++ inline_name ++ "' collides with " ++ section ++ " '" ++ other_field.name ++ "'");
                }
            }

            inline for (.{ "executables", "libraries", "objects", "tests" }) |other_section| {
                if (comptime std.mem.eql(u8, section, other_section)) continue;
                if (!@hasField(@TypeOf(manifest), other_section)) continue;

                inline for (@typeInfo(@TypeOf(@field(manifest, other_section))).@"struct".fields) |other_field| {
                    const other_item = @field(@field(manifest, other_section), other_field.name);
                    if (!isInlineRootModuleType(@TypeOf(other_item.root_module))) continue;
                    const other_name = inlineRootModuleName(other_field.name, other_item.root_module);
                    if (comptime std.mem.eql(u8, inline_name, other_name)) {
                        @compileError(section ++ " '" ++ field.name ++ "': inline root_module name '" ++ inline_name ++ "' collides with " ++ other_section ++ " '" ++ other_field.name ++ "'");
                    }
                }
            }
        }
    }
}

fn inlineRootModuleName(comptime artifact_name: []const u8, comptime root_module: anytype) []const u8 {
    return if (@hasField(@TypeOf(root_module), "name")) root_module.name else artifact_name;
}

fn validateRootModuleRef(
    comptime manifest: anytype,
    comptime root_module: anytype,
    comptime section: []const u8,
    comptime name: []const u8,
) void {
    const ti = @typeInfo(@TypeOf(root_module));
    if (ti == .@"struct") return; // inline module, nothing to cross-reference

    const ref_name = if (ti == .enum_literal)
        @tagName(root_module)
    else if (ti == .pointer)
        @as([]const u8, root_module)
    else
        @compileError("root_module must be a string, enum literal, or struct");

    if (ti == .enum_literal) {
        if (!hasModule(manifest, ref_name)) {
            @compileError(section ++ " '" ++ name ++ "': root_module references unknown module '" ++ ref_name ++ "'");
        }
        return;
    }

    if (ref_name.len == 0) {
        @compileError(section ++ " '" ++ name ++ "': root_module cannot reference an empty manual module name");
    }
    if (countSeparators(ref_name, ':') != 0) {
        @compileError(section ++ " '" ++ name ++ "': root_module string refs are reserved for bare manual module names");
    }
    if (hasModule(manifest, ref_name)) {
        @compileError(section ++ " '" ++ name ++ "': root_module string refs are reserved for manual modules; use ." ++ ref_name ++ " for zbuild modules");
    }
}

fn validateDependsOn(
    comptime manifest: anytype,
    comptime opts: Options,
    comptime deps: anytype,
    comptime section: []const u8,
    comptime name: []const u8,
) void {
    inline for (@typeInfo(@TypeOf(deps)).@"struct".fields) |field| {
        const raw = @field(deps, field.name);
        const ti = @typeInfo(@TypeOf(raw));
        const dep_name = toComptimeString(raw);

        if (ti == .enum_literal) {
            if (!hasArtifact(manifest, dep_name)) {
                @compileError(section ++ " '" ++ name ++ "': depends_on references unknown artifact '" ++ dep_name ++ "'");
            }
            continue;
        }

        if (ti != .pointer) {
            @compileError(section ++ " '" ++ name ++ "': depends_on entries must be strings or enum literals");
        }

        if (dep_name.len == 0) {
            @compileError(section ++ " '" ++ name ++ "': depends_on cannot contain an empty step reference");
        }

        if (countSeparators(dep_name, ':') == 0 and hasArtifact(manifest, dep_name)) {
            @compileError(section ++ " '" ++ name ++ "': depends_on string refs are reserved for top-level steps; use ." ++ dep_name ++ " for artifact install steps");
        }

        if (isManifestStepRef(manifest, opts, dep_name)) {
            continue; // manifest-owned top-level step
        }

        if (isReservedGeneratedStepName(opts, dep_name)) {
            @compileError(section ++ " '" ++ name ++ "': depends_on references unknown step '" ++ dep_name ++ "'");
        }
    }
}

fn validateImports(
    comptime manifest: anytype,
    comptime imports: anytype,
    comptime section: []const u8,
    comptime name: []const u8,
) void {
    inline for (@typeInfo(@TypeOf(imports)).@"struct".fields) |field| {
        const raw = @field(imports, field.name);
        const ti = @typeInfo(@TypeOf(raw));
        const import_name = toComptimeString(raw);

        if (ti == .enum_literal) {
            if (isImportable(manifest, import_name)) continue;
            @compileError(section ++ " '" ++ name ++ "': import references unknown target '" ++ import_name ++ "'");
        }

        if (import_name.len == 0) {
            @compileError(section ++ " '" ++ name ++ "': import references cannot be empty");
        }

        const separator_count = countSeparators(import_name, ':');
        if (separator_count == 0) {
            if (isImportable(manifest, import_name)) {
                @compileError(section ++ " '" ++ name ++ "': import string refs are reserved for manual modules; use ." ++ import_name ++ " for zbuild modules, options modules, and dependency default modules");
            }
            continue;
        }

        if (separator_count != 1) {
            @compileError(section ++ " '" ++ name ++ "': import references must be a bare manual module name or 'dependency:module'");
        }

        const dep_name = comptimeBaseName(import_name);
        const mod_name = comptimeAfterSep(import_name);
        if (!hasDependency(manifest, dep_name) or mod_name.len == 0) {
            @compileError(section ++ " '" ++ name ++ "': import references unknown target '" ++ import_name ++ "'");
        }
    }
}

fn validateModuleDefinition(
    comptime manifest: anytype,
    comptime mod: anytype,
    comptime section: []const u8,
    comptime name: []const u8,
    comptime allow_name: bool,
    comptime allow_private: bool,
) void {
    validateModuleFields(mod, section, name, allow_name, allow_private);

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

fn validateModuleFields(comptime mod: anytype, comptime section: []const u8, comptime name: []const u8, comptime allow_name: bool, comptime allow_private: bool) void {
    inline for (@typeInfo(@TypeOf(mod)).@"struct".fields) |field| {
        if (!isKnownModuleField(field.name, allow_name, allow_private)) {
            const context = if (allow_name)
                section ++ " '" ++ name ++ "' root_module"
            else
                section ++ " '" ++ name ++ "'";
            @compileError(context ++ ": unknown field '" ++ field.name ++ "'");
        }
    }
}

fn isKnownModuleField(comptime field_name: []const u8, comptime allow_name: bool, comptime allow_private: bool) bool {
    if (moduleCreateOptionsFieldBinding(field_name) != null) return true;
    if (comptime std.mem.eql(u8, field_name, "link_libraries") or std.mem.eql(u8, field_name, "include_paths"))
        return true;

    if (allow_name and comptime std.mem.eql(u8, field_name, "name")) return true;
    if (allow_private and comptime std.mem.eql(u8, field_name, "private")) return true;

    return false;
}

fn hasStructField(comptime T: type, comptime field_name: []const u8) bool {
    return @hasField(T, field_name);
}

fn moduleCreateOptionsFieldBinding(comptime field_name: []const u8) ?UpstreamFieldBinding {
    if (!hasStructField(std.Build.Module.CreateOptions, field_name)) return null;

    if (comptime std.mem.eql(u8, field_name, "root_source_file") or
        std.mem.eql(u8, field_name, "imports") or
        std.mem.eql(u8, field_name, "target") or
        std.mem.eql(u8, field_name, "optimize"))
    {
        return .adapted;
    }

    return .passthrough;
}

fn executableOptionsFieldBinding(comptime field_name: []const u8) ?UpstreamFieldBinding {
    if (!hasStructField(std.Build.ExecutableOptions, field_name)) return null;

    if (comptime std.mem.eql(u8, field_name, "name")) return .ignored;
    if (comptime std.mem.eql(u8, field_name, "root_module") or
        std.mem.eql(u8, field_name, "version") or
        std.mem.eql(u8, field_name, "zig_lib_dir") or
        std.mem.eql(u8, field_name, "win32_manifest"))
    {
        return .adapted;
    }

    return .passthrough;
}

fn libraryOptionsFieldBinding(comptime field_name: []const u8) ?UpstreamFieldBinding {
    if (!hasStructField(std.Build.LibraryOptions, field_name)) return null;

    if (comptime std.mem.eql(u8, field_name, "name")) return .ignored;
    if (comptime std.mem.eql(u8, field_name, "root_module") or
        std.mem.eql(u8, field_name, "version") or
        std.mem.eql(u8, field_name, "zig_lib_dir") or
        std.mem.eql(u8, field_name, "win32_manifest") or
        std.mem.eql(u8, field_name, "win32_module_definition"))
    {
        return .adapted;
    }

    return .passthrough;
}

fn objectOptionsFieldBinding(comptime field_name: []const u8) ?UpstreamFieldBinding {
    if (!hasStructField(std.Build.ObjectOptions, field_name)) return null;

    if (comptime std.mem.eql(u8, field_name, "name")) return .ignored;
    if (comptime std.mem.eql(u8, field_name, "root_module") or
        std.mem.eql(u8, field_name, "zig_lib_dir"))
    {
        return .adapted;
    }

    return .passthrough;
}

fn testOptionsFieldBinding(comptime field_name: []const u8) ?UpstreamFieldBinding {
    if (!hasStructField(std.Build.TestOptions, field_name)) return null;

    if (comptime std.mem.eql(u8, field_name, "name")) return .ignored;
    if (comptime std.mem.eql(u8, field_name, "root_module") or
        std.mem.eql(u8, field_name, "filters") or
        std.mem.eql(u8, field_name, "test_runner") or
        std.mem.eql(u8, field_name, "zig_lib_dir"))
    {
        return .adapted;
    }

    return .passthrough;
}

fn artifactOptionsFieldBinding(comptime section: []const u8, comptime field_name: []const u8) ?UpstreamFieldBinding {
    if (comptime std.mem.eql(u8, section, "executables")) return executableOptionsFieldBinding(field_name);
    if (comptime std.mem.eql(u8, section, "libraries")) return libraryOptionsFieldBinding(field_name);
    if (comptime std.mem.eql(u8, section, "objects")) return objectOptionsFieldBinding(field_name);
    if (comptime std.mem.eql(u8, section, "tests")) return testOptionsFieldBinding(field_name);
    @compileError("unknown artifact section '" ++ section ++ "'");
}

fn copyModulePassthroughFields(comptime Mod: type, mod: Mod, opts: *std.Build.Module.CreateOptions) void {
    inline for (@typeInfo(Mod).@"struct".fields) |field| {
        if (comptime moduleCreateOptionsFieldBinding(field.name) == .passthrough) {
            @field(opts.*, field.name) = @field(mod, field.name);
        }
    }
}

fn copyArtifactPassthroughFields(comptime section: []const u8, comptime Item: type, item: Item, opts: anytype) void {
    inline for (@typeInfo(Item).@"struct".fields) |field| {
        if (comptime artifactOptionsFieldBinding(section, field.name) == .passthrough) {
            @field(opts.*, field.name) = @field(item, field.name);
        }
    }
}

fn assertModuleCreateOptionsCoverage() void {
    inline for (@typeInfo(std.Build.Module.CreateOptions).@"struct".fields) |field| {
        if (moduleCreateOptionsFieldBinding(field.name) == null) {
            @compileError("unhandled std.Build.Module.CreateOptions field '" ++ field.name ++ "'");
        }
    }
}

fn assertExecutableOptionsCoverage() void {
    inline for (@typeInfo(std.Build.ExecutableOptions).@"struct".fields) |field| {
        if (executableOptionsFieldBinding(field.name) == null) {
            @compileError("unhandled std.Build.ExecutableOptions field '" ++ field.name ++ "'");
        }
    }
}

fn assertLibraryOptionsCoverage() void {
    inline for (@typeInfo(std.Build.LibraryOptions).@"struct".fields) |field| {
        if (libraryOptionsFieldBinding(field.name) == null) {
            @compileError("unhandled std.Build.LibraryOptions field '" ++ field.name ++ "'");
        }
    }
}

fn assertObjectOptionsCoverage() void {
    inline for (@typeInfo(std.Build.ObjectOptions).@"struct".fields) |field| {
        if (objectOptionsFieldBinding(field.name) == null) {
            @compileError("unhandled std.Build.ObjectOptions field '" ++ field.name ++ "'");
        }
    }
}

fn assertTestOptionsCoverage() void {
    inline for (@typeInfo(std.Build.TestOptions).@"struct".fields) |field| {
        if (testOptionsFieldBinding(field.name) == null) {
            @compileError("unhandled std.Build.TestOptions field '" ++ field.name ++ "'");
        }
    }
}

comptime {
    assertModuleCreateOptionsCoverage();
    assertExecutableOptionsCoverage();
    assertLibraryOptionsCoverage();
    assertObjectOptionsCoverage();
    assertTestOptionsCoverage();
}

fn validateArtifactFields(
    comptime manifest: anytype,
    comptime item: anytype,
    comptime section: []const u8,
    comptime name: []const u8,
) void {
    const Item = @TypeOf(item);
    if (@hasField(Item, "version"))
        validateSemverString(section, name, item.version);
    if (@hasField(Item, "zig_lib_dir"))
        validateLazyPathSyntax(manifest, item.zig_lib_dir, section, name, "zig_lib_dir");
    if (@hasField(Item, "win32_manifest"))
        validateLazyPathSyntax(manifest, item.win32_manifest, section, name, "win32_manifest");
    if (@hasField(Item, "win32_module_definition"))
        validateLazyPathSyntax(manifest, item.win32_module_definition, section, name, "win32_module_definition");
    if (@hasField(Item, "test_runner"))
        validateTestRunner(manifest, section, name, item.test_runner);
    if (@hasField(Item, "emit_object")) {
        const emit_object_check: bool = item.emit_object;
        _ = emit_object_check;
    }
}

fn validateTestRunner(comptime manifest: anytype, comptime section: []const u8, comptime name: []const u8, comptime test_runner: anytype) void {
    const Runner = @TypeOf(test_runner);
    inline for (@typeInfo(Runner).@"struct".fields) |field| {
        if (!std.mem.eql(u8, field.name, "path") and !std.mem.eql(u8, field.name, "mode")) {
            @compileError(section ++ " '" ++ name ++ "': test_runner: unknown field '" ++ field.name ++ "'");
        }
    }

    if (!@hasField(Runner, "path")) {
        @compileError(section ++ " '" ++ name ++ "': test_runner is missing required field 'path'");
    }
    if (!@hasField(Runner, "mode")) {
        @compileError(section ++ " '" ++ name ++ "': test_runner is missing required field 'mode'");
    }

    validateLazyPathSyntax(manifest, test_runner.path, section, name, "test_runner.path");
    const mode_check: enum { simple, server } = test_runner.mode;
    _ = mode_check;
}

fn validateSemverString(comptime section: []const u8, comptime name: []const u8, comptime version: []const u8) void {
    _ = std.SemanticVersion.parse(version) catch |err| {
        @compileError(section ++ " '" ++ name ++ "': invalid semantic version '" ++ version ++ "' (" ++ @errorName(err) ++ ")");
    };
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
    inline for (@typeInfo(Opt).@"struct".fields) |field| {
        if (!std.mem.eql(u8, field.name, "type") and
            !std.mem.eql(u8, field.name, "default") and
            !std.mem.eql(u8, field.name, "description") and
            !std.mem.eql(u8, field.name, "values") and
            !std.mem.eql(u8, field.name, "type_name"))
        {
            @compileError("options_modules '" ++ module_name ++ "." ++ option_name ++ "': unknown field '" ++ field.name ++ "'");
        }
    }

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

fn hasOptionsModule(comptime manifest: anytype, comptime name: []const u8) bool {
    if (@hasField(@TypeOf(manifest), "options_modules")) {
        if (@hasField(@TypeOf(manifest.options_modules), name)) return true;
    }
    return false;
}

fn isInlineRootModuleType(comptime T: type) bool {
    return @typeInfo(T) == .@"struct";
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

fn isAggregateStepRef(comptime manifest: anytype, comptime opts: Options, comptime step_ref: []const u8) bool {
    if (comptime std.mem.eql(u8, step_ref, "test")) return @hasField(@TypeOf(manifest), "tests");
    if (comptime std.mem.eql(u8, step_ref, "fmt")) return @hasField(@TypeOf(manifest), "fmts");
    if (opts.help_step) |help_step| {
        if (comptime std.mem.eql(u8, step_ref, help_step)) return true;
    }
    return false;
}

fn hasReservedGeneratedStepPrefix(comptime step_ref: []const u8) bool {
    inline for (.{ "build-exe:", "build-lib:", "build-obj:", "build-test:", "run:", "test:", "cmd:", "fmt:" }) |prefix| {
        if (comptime std.mem.startsWith(u8, step_ref, prefix)) return true;
    }
    return false;
}

fn isReservedGeneratedStepName(comptime opts: Options, comptime step_ref: []const u8) bool {
    if (comptime std.mem.eql(u8, step_ref, "test") or std.mem.eql(u8, step_ref, "fmt")) return true;
    if (opts.help_step) |help_step| {
        if (comptime std.mem.eql(u8, step_ref, help_step)) return true;
    }
    return hasReservedGeneratedStepPrefix(step_ref);
}

fn isManifestStepRef(comptime manifest: anytype, comptime opts: Options, comptime step_ref: []const u8) bool {
    return hasStepTarget(manifest, step_ref) or isAggregateStepRef(manifest, opts, step_ref);
}

fn isImportable(comptime manifest: anytype, comptime name: []const u8) bool {
    if (hasModule(manifest, name)) return true;
    if (hasOptionsModule(manifest, name)) return true;
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
    inline_modules: std.StringHashMap(*std.Build.Module), // internal: inline root modules only
    manual_modules: std.StringHashMap(void),
    manual_steps: std.StringHashMap(void),

    const Error = error{ OutOfMemory, ModuleNotFound, NameCollision };
    const DependencyArtifactLookup = union(enum) {
        missing,
        ambiguous,
        found: *std.Build.Step.Compile,
    };

    fn snapshotPreexistingNamespaces(self: *BuildRunner) !void {
        var module_it = self.b.modules.iterator();
        while (module_it.next()) |entry| {
            try self.manual_modules.put(entry.key_ptr.*, {});
        }

        var step_it = self.b.top_level_steps.iterator();
        while (step_it.next()) |entry| {
            try self.manual_steps.put(entry.key_ptr.*, {});
        }
    }

    fn validateResolvedManifest(self: *BuildRunner, comptime manifest: anytype) bool {
        var failed = false;

        if (@hasField(@TypeOf(manifest), "modules")) {
            inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
                failed = self.validateResolvedModuleDefinition(manifest, "modules", field.name, @field(manifest.modules, field.name)) or failed;
            }
        }

        inline for (.{ "executables", "libraries", "objects", "tests" }) |section| {
            if (@hasField(@TypeOf(manifest), section)) {
                inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                    const item = @field(@field(manifest, section), field.name);
                    failed = self.validateResolvedArtifactFields(section, field.name, item) or failed;
                    if (isInlineRootModuleType(@TypeOf(item.root_module))) {
                        failed = self.validateResolvedModuleDefinition(manifest, section, field.name, item.root_module) or failed;
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

    fn validateNamespaceReservations(self: *BuildRunner, comptime manifest: anytype, comptime opts: Options) !bool {
        var failed = false;
        var reserved_imports = std.StringHashMap([]const u8).init(self.b.allocator);
        defer reserved_imports.deinit();
        var reserved_steps = std.StringHashMap([]const u8).init(self.b.allocator);
        defer reserved_steps.deinit();

        if (@hasField(@TypeOf(manifest), "modules")) {
            inline for (@typeInfo(@TypeOf(manifest.modules)).@"struct".fields) |field| {
                const mod = @field(manifest.modules, field.name);
                const is_private = @hasField(@TypeOf(mod), "private") and mod.private;
                failed = try self.reserveOwnedImportName(
                    &reserved_imports,
                    field.name,
                    if (is_private) "private named module" else "named module",
                ) or failed;
                if (!is_private) {
                    failed = try self.ensurePublicModuleNameAvailable(field.name, "named module") or failed;
                }
            }
        }

        if (@hasField(@TypeOf(manifest), "options_modules")) {
            inline for (@typeInfo(@TypeOf(manifest.options_modules)).@"struct".fields) |field| {
                failed = try self.reserveOwnedImportName(&reserved_imports, field.name, "options module") or failed;
            }
        }

        if (@hasField(@TypeOf(manifest), "dependencies")) {
            inline for (@typeInfo(@TypeOf(manifest.dependencies)).@"struct".fields) |field| {
                if (self.result.dependencies.get(field.name)) |dep| {
                    if (dep.builder.modules.get(field.name) != null) {
                        failed = try self.reserveOwnedImportName(&reserved_imports, field.name, "dependency default module") or failed;
                    }
                }
            }
        }

        inline for (.{ "executables", "libraries", "objects" }) |section| {
            if (!@hasField(@TypeOf(manifest), section)) continue;
            inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                const prefix = switch (section[0]) {
                    'e' => "build-exe:",
                    'l' => "build-lib:",
                    'o' => "build-obj:",
                    else => unreachable,
                };
                failed = try self.reserveTopLevelStepName(
                    &reserved_steps,
                    self.b.fmt(prefix ++ "{s}", .{field.name}),
                    section ++ " install step",
                ) or failed;
                if (comptime std.mem.eql(u8, section, "executables")) {
                    failed = try self.reserveTopLevelStepName(
                        &reserved_steps,
                        self.b.fmt("run:{s}", .{field.name}),
                        "executable run step",
                    ) or failed;
                }
            }
        }

        if (@hasField(@TypeOf(manifest), "tests")) {
            failed = try self.reserveTopLevelStepName(&reserved_steps, "test", "test aggregate step") or failed;
            inline for (@typeInfo(@TypeOf(manifest.tests)).@"struct".fields) |field| {
                failed = try self.reserveTopLevelStepName(
                    &reserved_steps,
                    self.b.fmt("build-test:{s}", .{field.name}),
                    "test install step",
                ) or failed;
                failed = try self.reserveTopLevelStepName(
                    &reserved_steps,
                    self.b.fmt("test:{s}", .{field.name}),
                    "test run step",
                ) or failed;
            }
        }

        if (@hasField(@TypeOf(manifest), "fmts")) {
            failed = try self.reserveTopLevelStepName(&reserved_steps, "fmt", "fmt aggregate step") or failed;
            inline for (@typeInfo(@TypeOf(manifest.fmts)).@"struct".fields) |field| {
                failed = try self.reserveTopLevelStepName(
                    &reserved_steps,
                    self.b.fmt("fmt:{s}", .{field.name}),
                    "fmt step",
                ) or failed;
            }
        }

        if (@hasField(@TypeOf(manifest), "runs")) {
            inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
                failed = try self.reserveTopLevelStepName(
                    &reserved_steps,
                    self.b.fmt("cmd:{s}", .{field.name}),
                    "run command step",
                ) or failed;
            }
        }

        if (opts.help_step) |step_name| {
            failed = try self.reserveTopLevelStepName(&reserved_steps, step_name, "help step") or failed;
        }

        return failed;
    }

    fn reserveOwnedImportName(
        self: *BuildRunner,
        reserved: *std.StringHashMap([]const u8),
        name: []const u8,
        origin: []const u8,
    ) !bool {
        const gop = try reserved.getOrPut(name);
        if (gop.found_existing) {
            self.invalidateManifest("{s} '{s}' collides with another zbuild-owned import name ({s})", .{
                origin,
                name,
                gop.value_ptr.*,
            });
            return true;
        }
        gop.value_ptr.* = origin;

        return false;
    }

    fn ensurePublicModuleNameAvailable(self: *BuildRunner, name: []const u8, origin: []const u8) !bool {
        if (self.b.modules.get(name) != null) {
            self.invalidateManifest("{s} '{s}' collides with an existing module registered before configureBuild", .{
                origin,
                name,
            });
            return true;
        }

        return false;
    }

    fn reserveTopLevelStepName(
        self: *BuildRunner,
        reserved: *std.StringHashMap([]const u8),
        name: []const u8,
        origin: []const u8,
    ) !bool {
        const gop = try reserved.getOrPut(name);
        if (gop.found_existing) {
            self.invalidateManifest("{s} '{s}' collides with another zbuild-generated step ({s})", .{
                origin,
                name,
                gop.value_ptr.*,
            });
            return true;
        }
        gop.value_ptr.* = origin;

        if (self.b.top_level_steps.get(name) != null) {
            self.invalidateManifest("{s} '{s}' collides with an existing top-level step registered before configureBuild", .{
                origin,
                name,
            });
            return true;
        }

        return false;
    }

    fn registerPublicModule(self: *BuildRunner, name: []const u8, module: *std.Build.Module) Error!void {
        if (self.b.modules.get(name) != null) {
            self.invalidateManifest("named module '{s}' collides with an existing module registered before configureBuild", .{name});
            return error.NameCollision;
        }
        try self.b.modules.put(self.b.graph.arena, self.b.dupe(name), module);
    }

    fn createTopLevelStep(self: *BuildRunner, name: []const u8, description: []const u8) Error!*std.Build.Step {
        if (self.b.top_level_steps.get(name) != null) {
            self.invalidateManifest("top-level step '{s}' collides with an existing step named '{s}'", .{ name, name });
            return error.NameCollision;
        }
        return self.b.step(name, description);
    }

    fn validateResolvedModuleDefinition(self: *BuildRunner, comptime manifest: anytype, comptime section: []const u8, comptime name: []const u8, comptime mod: anytype) bool {
        var failed = false;
        const Mod = @TypeOf(mod);

        if (@hasField(Mod, "imports"))
            failed = self.validateResolvedImports(manifest, mod.imports, section, name) or failed;
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

    fn validateResolvedImports(self: *BuildRunner, comptime manifest: anytype, comptime imports: anytype, comptime section: []const u8, comptime name: []const u8) bool {
        var failed = false;

        inline for (@typeInfo(@TypeOf(imports)).@"struct".fields) |field| {
            const raw = @field(imports, field.name);
            const import_name = comptime toComptimeString(raw);
            switch (@typeInfo(@TypeOf(raw))) {
                .enum_literal => {
                    if (comptime hasModule(manifest, import_name) or hasOptionsModule(manifest, import_name)) continue;
                    if (self.result.dependencies.get(import_name)) |dep| {
                        if (dep.builder.modules.get(import_name) == null) {
                            self.invalidateManifest("dependency import '{s}' in {s} '{s}' could not resolve default module '{s}' from dependency '{s}'", .{
                                import_name,
                                section,
                                name,
                                import_name,
                                import_name,
                            });
                            failed = true;
                        }
                    }
                },
                .pointer => {
                    if (countSeparators(import_name, ':') == 0) {
                        if (!self.manual_modules.contains(import_name) or self.b.modules.get(import_name) == null) {
                            self.invalidateManifest("manual import '{s}' in {s} '{s}' could not resolve a module registered before configureBuild", .{
                                import_name,
                                section,
                                name,
                            });
                            failed = true;
                        }
                        continue;
                    }

                    const dep_name = comptimeBaseName(import_name);
                    const module_name = comptimeAfterSep(import_name);
                    if (self.result.dependencies.get(dep_name)) |dep| {
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
                    } else {
                        self.invalidateManifest("dependency import '{s}' in {s} '{s}' references missing dependency '{s}'", .{
                            import_name,
                            section,
                            name,
                            dep_name,
                        });
                        failed = true;
                    }
                },
                else => unreachable,
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

    fn createModule(
        self: *BuildRunner,
        comptime mod: anytype,
        name: []const u8,
        registry: *std.StringHashMap(*std.Build.Module),
    ) Error!*std.Build.Module {
        const Mod = @TypeOf(mod);
        var opts: std.Build.Module.CreateOptions = .{
            .root_source_file = if (@hasField(Mod, "root_source_file")) self.resolveLazyPath(mod.root_source_file) else null,
            .target = if (@hasField(Mod, "target")) self.resolveTarget(mod.target) else self.target,
            .optimize = if (@hasField(Mod, "optimize")) mod.optimize else self.optimize,
        };
        copyModulePassthroughFields(Mod, mod, &opts);
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

        if (registry != &self.result.modules and self.result.modules.get(name) != null) {
            self.invalidateManifest("inline root_module name '{s}' collides with named module '{s}'", .{ name, name });
            return error.NameCollision;
        }
        if (registry.get(name) != null) {
            self.invalidateManifest("duplicate module registration for '{s}'", .{name});
            return error.NameCollision;
        }

        try registry.put(name, m);
        return m;
    }

    fn resolveModuleLink(self: *BuildRunner, comptime link: anytype, comptime name: []const u8) Error!*std.Build.Module {
        const ti = @typeInfo(@TypeOf(link));
        if (ti == .enum_literal) {
            const mod_name = @tagName(link);
            return self.result.modules.get(mod_name) orelse {
                std.log.err("zbuild: module '{s}' not found", .{mod_name});
                return error.ModuleNotFound;
            };
        } else if (ti == .pointer) {
            const str: []const u8 = link;
            if (countSeparators(str, ':') == 0 and self.manual_modules.contains(str)) {
                if (self.b.modules.get(str)) |module| return module;
            }
            self.invalidateManifest("root_module '{s}' could not resolve a manual module registered before configureBuild", .{str});
            return error.ModuleNotFound;
        } else if (ti == .@"struct") {
            const mod_name = inlineRootModuleName(name, link);
            return try self.createModule(link, mod_name, &self.inline_modules);
        } else {
            @compileError("root_module must be a string, enum literal, or struct");
        }
    }

    // --- Artifact creation ---

    fn createExecutable(self: *BuildRunner, comptime name: []const u8, comptime exe: anytype) Error!void {
        const Exe = @TypeOf(exe);
        const root_module = try self.resolveModuleLink(exe.root_module, name);

        var add_opts: std.Build.ExecutableOptions = .{
            .name = name,
            .root_module = root_module,
            .version = if (@hasField(Exe, "version")) std.SemanticVersion.parse(exe.version) catch unreachable else null,
        };
        copyArtifactPassthroughFields("executables", Exe, exe, &add_opts);
        if (@hasField(Exe, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(exe.zig_lib_dir);
        if (@hasField(Exe, "win32_manifest")) add_opts.win32_manifest = self.resolveLazyPath(exe.win32_manifest);

        const artifact = self.b.addExecutable(add_opts);
        try self.result.executables.put(name, artifact);

        try self.installAndRegister("build-exe", "executable", name, artifact, .{
            .dest_sub_path = if (@hasField(Exe, "dest_sub_path")) exe.dest_sub_path else null,
        });

        const run = self.b.addRunArtifact(artifact);
        if (self.b.args) |args| run.addArgs(args);
        const tls_run = try self.createTopLevelStep(
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
            .version = if (@hasField(Lib, "version")) std.SemanticVersion.parse(lib.version) catch unreachable else null,
        };
        copyArtifactPassthroughFields("libraries", Lib, lib, &add_opts);
        if (@hasField(Lib, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(lib.zig_lib_dir);
        if (@hasField(Lib, "win32_manifest")) add_opts.win32_manifest = self.resolveLazyPath(lib.win32_manifest);
        if (@hasField(Lib, "win32_module_definition")) add_opts.win32_module_definition = self.resolveLazyPath(lib.win32_module_definition);

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
        copyArtifactPassthroughFields("objects", Obj, obj, &add_opts);
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
        copyArtifactPassthroughFields("tests", T, t, &add_opts);
        if (@hasField(T, "zig_lib_dir")) add_opts.zig_lib_dir = self.resolveLazyPath(t.zig_lib_dir);
        if (@hasField(T, "test_runner")) {
            add_opts.test_runner = .{
                .path = self.resolveLazyPath(t.test_runner.path),
                .mode = t.test_runner.mode,
            };
        }

        const artifact = self.b.addTest(add_opts);
        try self.result.tests.put(name, artifact);

        const install = self.b.addInstallArtifact(artifact, .{});
        const tls_install = try self.createTopLevelStep(
            self.b.fmt("build-test:{s}", .{name}),
            self.b.fmt("Install the {s} test", .{name}),
        );
        tls_install.dependOn(&install.step);

        const run = self.b.addRunArtifact(artifact);
        const tls_run = try self.createTopLevelStep(
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

        const tls = try self.createTopLevelStep(
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

        const tls = try self.createTopLevelStep(
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
        const tls = try self.createTopLevelStep(
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
                    if (isInlineRootModuleType(@TypeOf(item.root_module))) {
                        if (@hasField(@TypeOf(item.root_module), "imports")) {
                            const mod_name = inlineRootModuleName(field.name, item.root_module);
                            if (self.inline_modules.get(mod_name)) |m| {
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
            const raw = @field(imports, field.name);
            const import_name = comptime toComptimeString(raw);
            const resolved = switch (@typeInfo(@TypeOf(raw))) {
                .enum_literal => try self.resolveOwnedImport(import_name),
                .pointer => if (countSeparators(import_name, ':') == 0)
                    try self.resolveManualImport(import_name)
                else
                    try self.resolveDependencyImport(import_name),
                else => unreachable,
            };
            module.addImport(import_name, resolved);
        }
    }

    // --- depends_on wiring ---

    fn wireDependsOn(self: *BuildRunner, comptime manifest: anytype, comptime opts: Options) Error!void {
        // Artifacts: wire install step
        inline for (.{ "executables", "libraries", "objects" }) |section| {
            if (@hasField(@TypeOf(manifest), section)) {
                inline for (@typeInfo(@TypeOf(@field(manifest, section))).@"struct".fields) |field| {
                    const item = @field(@field(manifest, section), field.name);
                    if (@hasField(@TypeOf(item), "depends_on")) {
                        if (self.install_steps.get(field.name)) |this_step| {
                            try self.wireDependsOnList(manifest, opts, this_step, item.depends_on);
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
                        try self.wireDependsOnList(manifest, opts, &tls.step, item.depends_on);
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
                        try self.wireDependsOnList(manifest, opts, &tls.step, run.depends_on);
                    }
                }
            }
        }
    }

    fn wireDependsOnList(self: *BuildRunner, comptime manifest: anytype, comptime opts: Options, step: *std.Build.Step, comptime deps: anytype) Error!void {
        inline for (@typeInfo(@TypeOf(deps)).@"struct".fields) |field| {
            const raw = @field(deps, field.name);
            const dep_name = comptime toComptimeString(raw);
            const dep_step = switch (@typeInfo(@TypeOf(raw))) {
                .enum_literal => self.install_steps.get(dep_name),
                .pointer => blk: {
                    if (isManifestStepRef(manifest, opts, dep_name)) {
                        if (self.b.top_level_steps.get(dep_name)) |tls| break :blk &tls.step;
                        break :blk null;
                    }
                    if (!self.manual_steps.contains(dep_name)) break :blk null;
                    if (self.b.top_level_steps.get(dep_name)) |tls| break :blk &tls.step;
                    break :blk null;
                },
                else => @compileError("depends_on entries must be strings or enum literals"),
            };
            if (dep_step) |s| {
                step.dependOn(s);
            } else {
                self.invalidateManifest("depends_on reference '{s}' could not resolve an artifact install step or top-level step registered before configureBuild", .{dep_name});
                return error.ModuleNotFound;
            }
        }
    }

    // --- Resolution helpers (runtime) ---

    fn resolveOwnedImport(self: *BuildRunner, import_name: []const u8) Error!*std.Build.Module {
        if (self.result.modules.get(import_name)) |m| return m;
        if (self.result.options_modules.get(import_name)) |m| return m;
        if (self.result.dependencies.get(import_name)) |dep| {
            if (dep.builder.modules.get(import_name)) |module| return module;
            self.invalidateManifest("dependency import '{s}' could not resolve default module '{s}' from dependency '{s}'", .{
                import_name,
                import_name,
                import_name,
            });
            return error.ModuleNotFound;
        }
        self.invalidateManifest("unresolved import '{s}' (expected a zbuild module, options module, or dependency default module)", .{import_name});
        return error.ModuleNotFound;
    }

    fn resolveDependencyImport(self: *BuildRunner, import_name: []const u8) Error!*std.Build.Module {
        var parts = std.mem.splitScalar(u8, import_name, ':');
        const first = parts.first();
        if (self.result.dependencies.get(first)) |dep| {
            const module_name = parts.next() orelse unreachable;
            if (dep.builder.modules.get(module_name)) |module| return module;
            self.invalidateManifest("dependency import '{s}' could not resolve module '{s}' from dependency '{s}'", .{
                import_name,
                module_name,
                first,
            });
            return error.ModuleNotFound;
        }
        self.invalidateManifest("dependency import '{s}' references missing dependency '{s}'", .{ import_name, first });
        return error.ModuleNotFound;
    }

    fn resolveManualImport(self: *BuildRunner, import_name: []const u8) Error!*std.Build.Module {
        if (self.manual_modules.contains(import_name)) {
            if (self.b.modules.get(import_name)) |module| return module;
        }
        self.invalidateManifest("manual import '{s}' could not resolve a module registered before configureBuild", .{import_name});
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
    }, .{});
}

test "validateManifest accepts manual build.zig string refs" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .modules = .{
            .core = .{
                .root_source_file = "src/core.zig",
                .imports = .{"shared"},
            },
        },
        .executables = .{
            .myapp = .{
                .root_module = "shared",
                .depends_on = .{"gen:prep"},
            },
        },
        .runs = .{
            .deploy = .{
                .cmd = .{"./deploy.sh"},
                .depends_on = .{"gen:prep"},
            },
        },
    }, .{});
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

test "inlineRootModuleName" {
    try std.testing.expectEqualStrings("demo", comptime inlineRootModuleName("demo", .{
        .root_source_file = "src/main.zig",
    }));
    try std.testing.expectEqualStrings("custom_name", comptime inlineRootModuleName("demo", .{
        .root_source_file = "src/main.zig",
        .name = "custom_name",
    }));
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
    }, .{});
}

test "validateManifest accepts minimal manifest" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
    }, .{});
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
    }, .{});
}

test "validateManifest accepts unknown top-level fields" {
    // Top-level unknown fields may belong to Zig itself, so zbuild leaves them alone.
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.16.0",
        .paths = .{"."},
        .some_future_zig_field = "should be ignored",
    }, .{});
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
    }, .{});
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
    }, .{});
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
    }, .{});
}
