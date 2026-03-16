# BuildResult API Design

## Problem

`configureBuild` returns `!void`. All created artifacts, modules, dependencies, runs, and fmts are local to the function and discarded. Users who want to extend an artifact zbuild created (add C sources, link flags, custom steps) or reference zbuild-created entities from manual build code have no way to access them.

Modules registered with `b.modules` are accessible after the call, but private modules, compile artifacts, dependencies, options modules, runs, and fmts are not.

## Design

### `BuildResult` struct

Returned by `configureBuild`. Holds typed hashmaps — one per entity kind. Getter methods return optionals.

```zig
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

    pub fn executable(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile;
    pub fn library(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile;
    pub fn object(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile;
    pub fn testArtifact(self: BuildResult, name: []const u8) ?*std.Build.Step.Compile;
    pub fn module(self: BuildResult, name: []const u8) ?*std.Build.Module;
    pub fn dependency(self: BuildResult, name: []const u8) ?*std.Build.Dependency;
    pub fn optionsModule(self: BuildResult, name: []const u8) ?*std.Build.Module;
    pub fn run(self: BuildResult, name: []const u8) ?*std.Build.Step.Run;
    pub fn fmt(self: BuildResult, name: []const u8) ?*std.Build.Step.Fmt;
};
```

### Integration with BuildRunner

`BuildResult` becomes the runner's storage for all user-facing state. `BuildRunner` holds a `result: BuildResult` field plus internal-only state:

```zig
const BuildRunner = struct {
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    result: BuildResult,
    install_steps: std.StringHashMap(*std.Build.Step),  // internal, for depends_on wiring
};
```

`configureBuild` returns `runner.result` at the end.

### `install_steps` stays internal

`install_steps` maps artifact names to their `*Step` (install step). It cannot be derived from the per-kind maps because `*Step.Compile` has no back-reference to its `*Step.InstallArtifact`. It remains a private implementation detail used only by `wireDependsOn` / `wireDependsOnList`.

### Changes to `configureBuild`

- Return type: `!void` → `!BuildResult`
- Each `createX` function stores the artifact in the appropriate result map
- Returns `runner.result` after all phases complete

### Backwards compatibility

Non-breaking. Callers using `try configureBuild(...)` or `configureBuild(...) catch ...` continue to work — they ignore the return value. The `BuildResult` struct and getters are additive.

### What each `createX` stores

| Function | Stores in |
|----------|-----------|
| `createExecutable` | `result.executables` + `install_steps` |
| `createLibrary` | `result.libraries` + `install_steps` |
| `createObject` | `result.objects` + `install_steps` |
| `createTest` | `result.tests` |
| `createRun` | `result.runs` |
| `createFmt` | `result.fmts` |
| `createModule` | `result.modules` (already does this) |
| `createOptionsModule` | `result.options_modules` (already does this) |
| Phase 1 (dependencies) | `result.dependencies` (already does this) |
