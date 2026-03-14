# zbuild Architecture Refactor

## Problem

zbuild's core pipeline (zbuild.zon -> Config -> build.zig + build.zig.zon) has structural deficiencies that produce bugs systematically. The hand-rolled parser doesn't stay in sync with the data model. The string-concatenation codegen is fragile. Two ZON files with overlapping data require a brittle sync mechanism. These aren't isolated bugs — they're consequences of the architecture.

## Solution

Three composable changes that eliminate the code that contains most bugs:

1. **Single ZON file** — merge zbuild.zon into build.zig.zon
2. **std.zon.parse-based Config** — replace the hand-rolled parser with Zig's stdlib
3. **Static build.zig** — replace codegen with a fixed build.zig that reads the config at build time

## Execution Order

```
Phase A (single file)  ->  Phase B (std.zon.parse)  ->  Phase C (static build.zig)
```

Each phase is independently shippable. If Phase C proves harder than expected, Phases A+B alone are still a major improvement.

---

## Phase A: Single ZON File

### Change

Eliminate zbuild.zon as a separate file. The project's `build.zig.zon` becomes the single source of truth, containing both standard Zig manifest fields and zbuild-specific fields. Zig's build system ignores unknown fields by design (confirmed: Manifest.zig lines 272-275 explicitly skip unknown fields for forward compatibility).

**Assumption:** The upstream Zig compiler's manifest parser also ignores unknown fields. This is the documented intent (the comment says "so that we can add fields in future zig versions") and has been verified in zbuild's local copy. If a future Zig version adds strict validation, this approach would need revisiting.

### Deletions

- `sync_manifest.zig` — no more translating zbuild.zon to build.zig.zon
- `Manifest.zig` — no more parallel data model
- The `depEql` bridge function
- The AST-splicing hack in `allocPrintManifest`

### Changes

- `--zbuild-file` flag defaults to `build.zig.zon` instead of `zbuild.zon`
- `cmd_fetch.zig` operates directly on `build.zig.zon`
- `cmd_init` writes a single `build.zig.zon` with both standard and zbuild fields
- Config parser reads `build.zig.zon`
- Update test fixtures from `.zbuild.zon` to `.build.zig.zon` extension

### Migration

Existing users merge their `zbuild.zon` content into `build.zig.zon` and delete `zbuild.zon`. A `zbuild migrate` command could automate this but is not required for the initial implementation.

### Bugs Fixed

- 2.9: description/keywords not written to build.zig.zon (no translation needed)
- 2.10: hash/lazy not serialized (single file, no re-serialization)
- 2.12: no rollback on fetch failure (no two-phase sync)
- 4.5: two-phase sync ordering (eliminated)
- 5.8: parallel data model (eliminated)

---

## Phase B: std.zon.parse-based Config

### Change

Replace the hand-rolled per-field `if/else if` dispatch chains with `std.zon.parse.fromZoirNode` for types that map cleanly to ZON structs. Keep a thin custom layer for the top-level Config (which uses `StringArrayHashMap`) and a few types with non-standard ZON representations.

### API Reality

Zig 0.14's `std.zon.parse` provides three entry points:

- `fromSlice(T, gpa, source, status?, options)` — parses raw ZON source bytes
- `fromZoir(T, gpa, ast, zoir, status?, options)` — parses pre-lowered Zoir
- `fromZoirNode(T, gpa, ast, zoir, node, status?, options)` — parses a specific node

**There is no `zonParse` hook.** Custom types cannot register parsing callbacks. `StringArrayHashMap(T)` is not natively parseable. The approach must account for this.

### Parsing Strategy

**Layer 1 — Top-level Config:** A thin custom parser (~50 lines) that iterates the top-level struct literal fields by name and dispatches to the appropriate sub-parser. This replaces the current `parse()` function but is much shorter because it only handles the top-level field routing, not recursive field-by-field parsing of every nested type.

**Layer 2 — HashMap fields:** A generic `parseHashMap(T, ...)` function (~25 lines, similar to the existing `parseOptionalHashMap`) iterates a ZON struct literal's named fields and calls `fromZoirNode(T, ...)` for each value. This handles `modules`, `executables`, `libraries`, `objects`, `tests`, `fmts`, `options_modules`, and `dependencies` (with a custom value parser for deps).

**Layer 3 — Value types parsed automatically by std.zon.parse:** `Module`, `Executable`, `Library`, `Object`, `Test`, `Fmt` are plain structs with optional fields. `fromZoirNode` handles them directly — all `bool`, `enum`, `[]const u8`, `?[][]const u8` fields parse automatically via comptime reflection. **This eliminates all the `if/else if` dispatch chains** (the bulk of the parser code).

**Layer 4 — Types needing custom parsing (~80 lines total):**
- **Dependency** — discriminated on `path` vs `url` field presence. Custom parser checks which field is present and constructs the tagged value.
- **ModuleLink** — bare enum literal (`.foo`) vs inline struct. Custom parser checks the ZON node type.
- **Option** — discriminated by a `type` string field. Custom parser reads `type`, then parses remaining fields according to variant.
- **Run** — plain string value, trivial custom parser.

### Shared CompileTarget Base

Introduce a common struct for fields shared across Executable, Library, Object, Test:

```zig
pub const CompileTarget = struct {
    name: ?[]const u8 = null,
    root_module: ModuleLink,
    max_rss: ?usize = null,
    use_llvm: ?bool = null,
    use_lld: ?bool = null,
    zig_lib_dir: ?[]const u8 = null,
    depends_on: ?[][]const u8 = null,
};

pub const Executable = struct {
    base: CompileTarget,
    version: ?[]const u8 = null,
    linkage: ?std.builtin.LinkMode = null,
    win32_manifest: ?[]const u8 = null,
    dest_sub_path: ?[]const u8 = null,
};

pub const Library = struct {
    base: CompileTarget,
    version: ?[]const u8 = null,
    linkage: ?std.builtin.LinkMode = null,
    linker_allow_shlib_undefined: ?bool = null,
    dest_sub_path: ?[]const u8 = null,
};

pub const Object = struct {
    base: CompileTarget,
};

pub const Test = struct {
    base: CompileTarget,
    test_runner: ?[]const u8 = null,
    filters: ?[][]const u8 = null,
};
```

**Note on CompileTarget and fromZoirNode:** Since `std.zon.parse` handles nested structs, the `base: CompileTarget` field will parse correctly as long as the ZON uses a nested `.base = .{ ... }` syntax. If we want flat field syntax (`.use_llvm = true` directly on the executable, not `.base = .{ .use_llvm = true }`), then Executable etc. would need to inline the CompileTarget fields instead of embedding it. The ZON ergonomics should determine this — **flat is better for users**, so we inline the fields and use a comptime helper to share the field definitions:

```zig
const compile_target_fields = .{
    .{ "name", ?[]const u8, null },
    .{ "root_module", ModuleLink, ... },
    // ...
};

// Or simpler: just list the shared fields in a comment and keep them in sync.
// The parsing correctness is enforced by std.zon.parse matching struct fields,
// not by comptime field generation.
```

The pragmatic approach: keep the fields inlined in each struct (no `base:` nesting), and use `std.zon.parse.fromZoirNode` for each type directly. The duplication is in the type definitions (~5 shared fields x 4 types = 20 lines), not in the parsing or codegen logic.

### Fingerprint Field

Currently stored as `[]const u8` (a hex string like `"0x90797553773ca567"`). In `build.zig.zon` the fingerprint is a number literal (`0x90797553773ca567`). The Config struct should store it as `u64` to match the ZON representation. The serializer emits it as `0x{x:0>16}`. Downstream code that uses it as a string (the manifest template) will format it on output.

### Deletions

- All per-type `parseX` functions and their `if/else if` dispatch chains (~500 lines)
- All per-type `deinit` methods — `std.zon.parse`-allocated types use `std.zon.parse.free` for uniform cleanup (~100 lines)
- The `parseT`, `parseBool`, `parseString`, `parseEnumLiteral` helpers (replaced by `fromZoirNode`)

### What Remains

- Config.zig type definitions (~300 lines)
- Top-level parse + HashMap iteration + 4 custom parsers (~160 lines)
- Serializer (~300 lines, unchanged, cleanup deferred)
- Total: ~760 lines (down from ~1600)

### write_files

The `write_files` parser is currently a stub (Config.zig:648-649). This is a pre-existing incomplete feature. This refactor does not fix it — the stub remains. Implementing `write_files` is orthogonal and can be done after the refactor by adding the `WriteFile` type with appropriate custom parsing.

### Bugs Fixed

- 2.1: hash/lazy never parsed (struct fields are parsed automatically by fromZoirNode)
- 2.2: Library.version not parsed (same)
- 2.3: Test.test_runner not parsed (same)
- 2.11: include_paths not freed (std.zon.parse.free handles cleanup)
- 3.1: Executable.dest_sub_path not freed (same)
- 3.2: Library.dest_sub_path not freed (same)
- 3.3: parseObject leaks field name (no manual field name handling)
- 3.10: returnParseError leaks message (no manual error construction)
- 5.3: parser uses no reflection (std.zon.parse uses comptime reflection for struct fields)
- 5.7: deinit ceremony repeats (uniform free)

---

## Phase C: Static build.zig

### Change

Replace the string-concatenation codegen (ConfigBuildgen) with a fixed `build.zig` that every project uses. At build time, it reads `build.zig.zon`, parses it into Config structs, and calls the Zig build API directly.

### Architecture

zbuild becomes a Zig package dependency of the project. The static `build.zig`:

```zig
const std = @import("std");
const zbuild = @import("zbuild");

pub fn build(b: *std.Build) void {
    zbuild.configureBuild(b) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
```

The `configureBuild` function lives in zbuild's library code. It:
1. Reads `build.zig.zon` from `b.build_root_directory`
2. Parses it into Config using the Phase B parsing infrastructure
3. Walks the Config and calls `b.addExecutable(...)`, `b.addTest(...)`, etc.

This is the same logic as ConfigBuildgen but calling APIs directly instead of emitting strings that call APIs.

### zbuild's Own Build

zbuild itself does NOT use the static `build.zig` pattern. It keeps its own hand-written `build.zig` (or the one generated by the current zbuild.zig). There is no circular dependency — zbuild builds itself normally, and user projects depend on the built zbuild package.

### Deletions

- `ConfigBuildgen.zig` (~1280 lines)
- `sync_build_file.zig`
- The `scratch` buffer, `fmtId`, `allocFmtId`, all format-string machinery
- The unused-variable detection
- The `zig fmt` post-processing step
- The `writeImport` / `resolveImport` string-based resolution

### Changes

- New `src/build_runner.zig` containing `configureBuild` — estimated ~500 lines
- zbuild exposes Config types as a public module
- `zbuild sync` simplifies to: ensure build.zig has the static template, ensure build.zig.zon has zbuild as a dependency
- `cmd_init` writes the static build.zig template

### configureBuild Sketch

The function must handle:
- Creating modules from `config.modules` (with include_paths, link_libraries, etc.)
- Creating executables/libraries/objects from their respective config sections
- Resolving ModuleLink references (`.name` pointing to a named module, or inline module definitions)
- Wiring imports: local modules, options modules, and dependency modules
- Creating options and options_modules
- Setting up install steps, run steps, test steps
- Handling `depends_on` step dependencies (currently unimplemented in codegen — this is where we actually implement it)
- Detecting step name collisions (run:{name} for executables vs custom runs) and erroring

This is ~500 lines because the logic is the same as ConfigBuildgen minus all string formatting overhead. The import resolution becomes direct map lookups and API calls instead of string interpolation.

### How zbuild Gets Into Projects

It becomes a dependency in `build.zig.zon`:
```zon
.dependencies = .{
    .zbuild = .{
        .url = "https://github.com/chainsafe/zbuild/archive/...",
        .hash = "...",
    },
},
```

`zbuild init` and `zbuild fetch` add this automatically.

### Escape Hatch

Users who outgrow zbuild can copy the `configureBuild` logic, remove the dependency, and customize. The code is readable Zig, not generated string soup.

### Bugs Fixed

- 1.6: missing dot in format string (no format strings)
- 2.5: depends_on not emitted (implement directly in configureBuild)
- 2.6: unused-variable detection incomplete (no generated variables)
- 2.14: writeImport wrong module ID (direct API calls, no string identifiers)
- 3.7: zig fmt errors suppressed (no fmt step)
- 4.1: scratch buffer fragility (eliminated)
- 4.3: run step name collision (detect and error at build time)
- 4.6: include_extensions default inconsistency (direct API calls)
- 5.5: no codegen IR (eliminated — no codegen)
- 5.6: writeImports type switch (eliminated)
- 5.10: strTupleLiteral cross-import (eliminated)

---

## Testing Strategy

### Gate 1: Existing Fixtures Pass

All 6 fixture files (basic1-basic6) must produce a valid build that passes `zig build --help`. The existing E2E test in `test/sync.zig` must not regress. Fixtures are renamed from `.zbuild.zon` to `.build.zig.zon`.

### Gate 2: Parse Fidelity Tests

New unit tests that parse each fixture into a Config struct and assert specific field values:

- basic2: `link_libc = true`, `single_threaded = true`, specific code_model values
- basic5: options modules with typed defaults
- basic4: executables and libraries with specific linkage

Catches "field parsed but wrong value" and "field silently ignored."

### Gate 3: Build Graph Tests

Parse a fixture, run `configureBuild`, verify the resulting build graph:

- Expected number of executables, tests, libraries
- Install steps and run steps exist
- Module imports are resolved correctly
- Dependency references are wired up

### Gate 4: Single-File Validation

Verify that a `build.zig.zon` with zbuild-specific fields is accepted by both:

- zbuild's parser (parses all fields)
- Zig's build system (ignores unknown fields, builds normally)

### Gate 5: Custom Parser Types

Unit tests for each type with custom deserialization:

- Dependency: `{ .url = "..." }` vs `{ .path = "..." }` with args
- ModuleLink: bare `.name` vs inline `{ .root_source_file = "..." }`
- Option: each variant (bool, int, enum, list, etc.)

---

## Scope

### Estimated Impact

| Phase | Lines Deleted | Lines Added | Risk |
|-------|-------------|-------------|------|
| A: Single file | ~200 | ~50 | Low |
| B: std.zon.parse | ~600 (parser + deinit) | ~160 | Medium |
| C: Static build.zig | ~1300 (codegen + sync) | ~500 | Medium |
| **Total** | **~2100** | **~710** | |

Net reduction: ~1400 lines. Core logic shrinks from ~4500 to ~2400 lines.

### Out of Scope

- cmd_fetch bug fixes (orthogonal, own PR)
- Serializer rewrite (used only by cmd_init, cleanup later)
- CLI argument parsing improvements
- New features (c_source_files, system_libraries, etc.)
- write_files implementation (pre-existing stub, orthogonal)

### Fallback

Each phase is independently shippable. If Phase C proves too complex, ship Phases A+B alone — they eliminate ~800 lines and fix the majority of parser/sync bugs.
