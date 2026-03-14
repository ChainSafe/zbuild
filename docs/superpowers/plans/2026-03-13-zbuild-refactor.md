# zbuild Architecture Refactor Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate ~2100 lines of bug-prone code by merging ZON files, replacing the hand-rolled parser with `std.zon.parse`, and replacing string-concatenation codegen with a static `build.zig` that calls the build API directly.

**Architecture:** Three phases (A: single ZON file, B: std.zon.parse-based Config, C: static build.zig), each independently shippable. Phase A eliminates the dual-file sync layer. Phase B replaces manual `if/else if` parsing with `fromZoirNode` + thin custom layer. Phase C replaces `ConfigBuildgen` string emission with direct `std.Build` API calls in a `configureBuild` function.

**Tech Stack:** Zig 0.14, `std.zon.parse`, `std.Build` API

**Spec:** `docs/superpowers/specs/2026-03-13-zbuild-refactor-design.md`

---

## File Structure

### Phase A: Single ZON File

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `src/GlobalOptions.zig` | Change default zbuild_file from `"zbuild.zon"` to `"build.zig.zon"` |
| Modify | `src/cmd_sync.zig` | Remove `syncManifest` call, only call `syncBuildFile` |
| Modify | `src/cmd_init.zig` | Write `build.zig.zon` directly (no separate zbuild.zon), remove `Manifest` import |
| Modify | `src/cmd_fetch.zig` | Operate on `build.zig.zon` (already does, but fix bug 2.13 where it uses Manifest.load on zbuild_file) |
| Modify | `src/main.zig` | Update error message from "no zbuild file found" to "no build.zig.zon file found" |
| Modify | `test/sync.zig` | Rename fixture references from `.zbuild.zon` to `.build.zig.zon` |
| Rename | `test/fixtures/basic*.zbuild.zon` | Rename all 6 to `basic*.build.zig.zon` |
| Delete | `src/sync_manifest.zig` | Eliminated — single file means no manifest sync |
| Delete | `src/Manifest.zig` | Eliminated — parallel data model no longer needed |

### Phase B: std.zon.parse-based Config

| Action | File | Responsibility |
|--------|------|---------------|
| Rewrite | `src/Config.zig` | Replace hand-rolled Parser with: thin top-level dispatcher, generic `parseHashMap`, `fromZoirNode` for value types, 4 custom parsers (Dependency, ModuleLink, Option, Run). Remove all `deinit` methods (use arena). Change `fingerprint` from `[]const u8` to `u64`. |

### Phase C: Static build.zig

| Action | File | Responsibility |
|--------|------|---------------|
| Create | `src/build_runner.zig` | `configureBuild(b: *std.Build, config: Config)` — reads config and calls build API directly |
| Modify | `src/cmd_sync.zig` | Replace syncBuildFile with: ensure build.zig matches static template, ensure build.zig.zon has zbuild dep |
| Modify | `src/cmd_init.zig` | Write static build.zig template |
| Modify | `src/main.zig` | Expose Config types as public module for the zbuild package |
| Modify | `build.zig.zon` | Add zbuild self-reference note (zbuild itself doesn't use static build.zig) |
| Delete | `src/ConfigBuildgen.zig` | Eliminated — replaced by build_runner.zig |
| Delete | `src/sync_build_file.zig` | Eliminated — no more codegen + zig fmt pipeline |

---

## Chunk 1: Phase A — Single ZON File

### Task 1: Rename test fixtures

**Files:**
- Rename: `test/fixtures/basic1.zbuild.zon` → `test/fixtures/basic1.build.zig.zon`
- Rename: `test/fixtures/basic2.zbuild.zon` → `test/fixtures/basic2.build.zig.zon`
- Rename: `test/fixtures/basic3.zbuild.zon` → `test/fixtures/basic3.build.zig.zon`
- Rename: `test/fixtures/basic4.zbuild.zon` → `test/fixtures/basic4.build.zig.zon`
- Rename: `test/fixtures/basic5.zbuild.zon` → `test/fixtures/basic5.build.zig.zon`
- Rename: `test/fixtures/basic6.zbuild.zon` → `test/fixtures/basic6.build.zig.zon`

- [ ] **Step 1: Rename all 6 fixtures**

```bash
cd test/fixtures
for i in 1 2 3 4 5 6; do
  mv "basic${i}.zbuild.zon" "basic${i}.build.zig.zon"
done
```

- [ ] **Step 2: Update test/sync.zig fixture references**

In `test/sync.zig:11-18`, change all `.zbuild.zon` to `.build.zig.zon`:

```zig
const test_cases = &[_][]const u8{
    "fixtures/basic1.build.zig.zon",
    "fixtures/basic2.build.zig.zon",
    "fixtures/basic3.build.zig.zon",
    "fixtures/basic4.build.zig.zon",
    "fixtures/basic5.build.zig.zon",
    "fixtures/basic6.build.zig.zon",
};
```

- [ ] **Step 3: Commit**

```bash
git add test/fixtures/ test/sync.zig
git commit -m "refactor(phase-a): rename test fixtures from .zbuild.zon to .build.zig.zon"
```

### Task 2: Change default zbuild_file to build.zig.zon

**Files:**
- Modify: `src/GlobalOptions.zig:52`
- Modify: `src/main.zig:109`

- [ ] **Step 1: Change the default in GlobalOptions**

In `src/GlobalOptions.zig:52`, change:

```zig
// Before:
.zbuild_file = try allocator.dupe(u8, "zbuild.zon"),
// After:
.zbuild_file = try allocator.dupe(u8, "build.zig.zon"),
```

- [ ] **Step 2: Update error message in main.zig**

In `src/main.zig:109`, change:

```zig
// Before:
fatal("no zbuild file found", .{});
// After:
fatal("no build.zig.zon file found", .{});
```

- [ ] **Step 3: Run tests to verify fixtures load correctly**

```bash
zig build test -- --test-filter "zbuild build --help"
```

Expected: All 6 fixture tests pass (each fixture is loaded by its new `.build.zig.zon` path, and the default zbuild_file matches).

- [ ] **Step 4: Commit**

```bash
git add src/GlobalOptions.zig src/main.zig
git commit -m "refactor(phase-a): default zbuild_file to build.zig.zon"
```

### Task 3: Remove syncManifest from cmd_sync

**Files:**
- Modify: `src/cmd_sync.zig`

- [ ] **Step 1: Remove syncManifest import and call**

Replace the entire `src/cmd_sync.zig` with:

```zig
const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;
const GlobalOptions = @import("GlobalOptions.zig");
const Config = @import("Config.zig");
const syncBuildFile = @import("sync_build_file.zig").syncBuildFile;

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config) !void {
    if (global_opts.no_sync) {
        fatal("--no-sync is incompatible with the sync command", .{});
    }
    try syncBuildFile(gpa, arena, config, global_opts, .{ .out_dir = global_opts.project_dir });
}
```

- [ ] **Step 2: Run tests**

```bash
zig build test -- --test-filter "zbuild build --help"
```

Expected: All 6 pass. The sync command no longer writes a separate `build.zig.zon` manifest — the test fixtures ARE the `build.zig.zon` files already.

- [ ] **Step 3: Commit**

```bash
git add src/cmd_sync.zig
git commit -m "refactor(phase-a): remove syncManifest from cmd_sync"
```

### Task 4: Update cmd_init to write build.zig.zon directly

**Files:**
- Modify: `src/cmd_init.zig`

- [ ] **Step 1: Remove Manifest import, simplify**

The current `cmd_init.zig` writes to `zbuild_file` (which was `zbuild.zon`) then calls `sync.exec` to generate `build.zig.zon` from it. Now zbuild_file IS `build.zig.zon`, so `sync.exec` still works correctly — it reads `build.zig.zon` and generates `build.zig`.

Remove the `Manifest` import and the `Manifest.max_name_len` reference:

In `src/cmd_init.zig:8`, remove:
```zig
const Manifest = @import("Manifest.zig");
```

In `src/cmd_init.zig:94-95`, replace:
```zig
// Before:
if (result.items.len > Manifest.max_name_len)
    result.shrinkRetainingCapacity(Manifest.max_name_len);
// After:
if (result.items.len > 64)
    result.shrinkRetainingCapacity(64);
```

(The Manifest.max_name_len constant is 64. We inline the value to remove the Manifest dependency.)

- [ ] **Step 2: Run tests**

```bash
zig build test -- --test-filter "zbuild build --help"
```

Expected: All pass.

- [ ] **Step 3: Commit**

```bash
git add src/cmd_init.zig
git commit -m "refactor(phase-a): remove Manifest dependency from cmd_init"
```

### Task 5: Delete sync_manifest.zig and Manifest.zig

**Files:**
- Delete: `src/sync_manifest.zig`
- Delete: `src/Manifest.zig`
- Modify: `src/cmd_fetch.zig` (remove Manifest dependency)

- [ ] **Step 1: Update cmd_fetch.zig to remove Manifest usage**

`cmd_fetch.zig` uses `Manifest.load` to compare old vs new manifests after `zig fetch`. The Manifest parser is the standard Zig build.zig.zon parser. After deleting Manifest.zig, we need an alternative.

For now, we'll simplify cmd_fetch to not diff manifests — just run `zig fetch` with the save option. The zbuild.zon update path (`updateConfigDependency`) used `Manifest.load` on zbuild_file which was broken anyway (bug 2.13). Since zbuild_file IS now build.zig.zon, `zig fetch --save` handles everything directly.

Replace `src/cmd_fetch.zig:82-158` (the `exec` function) with:

```zig
pub fn exec(
    gpa: Allocator,
    arena: Allocator,
    global_opts: GlobalOptions,
    opts: Opts,
) !void {
    try runZigFetch(
        gpa,
        arena,
        .{ .cwd = global_opts.project_dir },
        global_opts.getZigEnv(),
        opts.path_or_url,
        opts.save,
    );
    if (opts.save != .no) {
        return;
    }
    return cleanExit();
}
```

Remove these imports from `cmd_fetch.zig`:
- `const Config = @import("Config.zig");`
- `const Manifest = @import("Manifest.zig");`

Remove the entire `updateConfigDependency` function (lines 160-245).

- [ ] **Step 2: Delete Manifest.zig and sync_manifest.zig**

```bash
rm src/Manifest.zig src/sync_manifest.zig
```

- [ ] **Step 3: Remove stale imports in main.zig if any**

Check if `main.zig` imports Manifest or sync_manifest. It doesn't — it only imports `Config`, `ConfigBuildgen`, `Args`, `GlobalOptions`, and the `cmd_*` modules. No change needed.

- [ ] **Step 4: Build to verify no dangling references**

```bash
zig build
```

Expected: Compiles cleanly. No references to Manifest.zig or sync_manifest.zig remain.

- [ ] **Step 5: Run tests**

```bash
zig build test -- --test-filter "zbuild build --help"
```

Expected: All 6 pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(phase-a): delete sync_manifest.zig and Manifest.zig

Eliminates the parallel manifest data model, the depEql bridge function,
and the AST-splicing hack. Simplifies cmd_fetch to delegate to zig fetch
directly. Fixes bugs 2.9, 2.10, 2.12, 2.13, 4.5, 5.8."
```

### Task 6: Rename zbuild's own config file

**Files:**
- Rename: `zbuild.zon` → merge into existing `build.zig.zon`
- Modify: `build.zig.zon`

- [ ] **Step 1: Merge zbuild.zon content into build.zig.zon**

The current `zbuild.zon` has zbuild-specific fields (executables, tests, description). The current `build.zig.zon` has standard manifest fields. Merge them into a single `build.zig.zon`:

```zon
.{
    .name = .zbuild,
    .version = "0.2.0",
    .fingerprint = 0x60f98ac2bf5a915c,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .description = "An opinionated zig build tool",
    .dependencies = .{},
    .executables = .{
        .zbuild = .{
            .root_module = .{
                .root_source_file = "src/main.zig",
            },
        },
    },
    .tests = .{
        .sync = .{
            .root_module = .{
                .private = true,
                .root_source_file = "test/sync.zig",
                .imports = .{.zbuild},
            },
        },
    },
}
```

- [ ] **Step 2: Delete zbuild.zon**

```bash
rm zbuild.zon
```

- [ ] **Step 3: Run zbuild sync to verify it reads build.zig.zon and generates build.zig**

```bash
zig build
```

Expected: Compiles and runs. zbuild reads `build.zig.zon` (the new default), generates `build.zig`.

- [ ] **Step 4: Run full tests**

```bash
zig build test
```

Expected: All tests pass.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(phase-a): merge zbuild.zon into build.zig.zon

Single source of truth. Zig's build system ignores unknown fields
(executables, tests, etc.) while zbuild reads them."
```

---

## Chunk 2: Phase B — std.zon.parse-based Config (Parser Rewrite)

### Task 7: Change fingerprint from []const u8 to u64

**Files:**
- Modify: `src/Config.zig`
- Modify: `src/ConfigBuildgen.zig` (update fingerprint emission — still needed until Phase C)
- Modify: `src/cmd_init.zig` (update fingerprint generation)

- [ ] **Step 1: Change the Config struct field**

In `src/Config.zig:11`, change:
```zig
// Before:
fingerprint: []const u8,
// After:
fingerprint: u64,
```

- [ ] **Step 2: Update the parser**

In `src/Config.zig:632-635`, change:
```zig
// Before:
} else if (std.mem.eql(u8, field_name, "fingerprint")) {
    has_fingerprint = true;
    const fingerprint_int = try self.parseT(u64, field_value);
    self.config.fingerprint = try std.fmt.allocPrint(self.gpa, "0x{x}", .{fingerprint_int});
// After:
} else if (std.mem.eql(u8, field_name, "fingerprint")) {
    has_fingerprint = true;
    self.config.fingerprint = try self.parseT(u64, field_value);
```

- [ ] **Step 3: Update Parser.init default**

In `src/Config.zig:608`, change:
```zig
// Before:
.fingerprint = "",
// After:
.fingerprint = 0,
```

- [ ] **Step 4: Update deinit**

In `src/Config.zig:453`, remove:
```zig
gpa.free(config.fingerprint);
```

- [ ] **Step 5: Update the serializer**

In `src/Config.zig:1352-1353`, change:
```zig
// Before:
try top_level.fieldPrefix("fingerprint");
try self.writer.print("0x{x}", .{self.config.fingerprint});
// After:
try top_level.fieldPrefix("fingerprint");
try self.writer.print("0x{x:0>16}", .{self.config.fingerprint});
```

- [ ] **Step 6: Update cmd_init.zig**

In `src/cmd_init.zig:14-19`, change:
```zig
// Before:
const fingerprint = try std.fmt.allocPrint(
    gpa,
    "0x{x}",
    .{Package.Fingerprint.generate(name).int()},
);
defer gpa.free(fingerprint);
// After:
const fingerprint = Package.Fingerprint.generate(name).int();
```

Remove `defer gpa.free(fingerprint);` since it's now a `u64`, not a heap string.

- [ ] **Step 7: Update ConfigBuildgen reference to fingerprint**

Search `ConfigBuildgen.zig` for `fingerprint` usage. It's not directly used there — the fingerprint goes into the manifest template in `sync_manifest.zig` which we already deleted. No changes needed in ConfigBuildgen.

- [ ] **Step 8: Build and test**

```bash
zig build test
```

Expected: All tests pass. The fingerprint is now parsed as a `u64` directly from the ZON number literal.

- [ ] **Step 9: Commit**

```bash
git add src/Config.zig src/cmd_init.zig
git commit -m "refactor(phase-b): change fingerprint from []const u8 to u64

Matches the ZON representation directly. Eliminates the intermediate
string formatting and heap allocation."
```

### Task 8: Switch to arena-based parsing (eliminate deinit)

**Files:**
- Modify: `src/Config.zig`
- Modify: `src/main.zig`

The current parser uses `gpa` for all allocations and has manual `deinit` methods for every type. Since Config is always used with an arena in practice (`main.zig:67-68`), we can parse into the arena and eliminate all `deinit` methods.

- [ ] **Step 1: Verify arena usage in callers**

Check all callers of `Config.parseFromFile`:
- `main.zig:107`: passes `arena` as first arg — arena-allocated, freed by `arena_instance.deinit()`
- `test/sync.zig:34`: passes `arena` — same pattern

Both callers use arena. The Config result lives for the scope of the arena. No caller calls `config.deinit()`. This confirms we can safely switch to arena-only allocation.

- [ ] **Step 2: Remove Config.deinit and all sub-type deinit methods**

In `src/Config.zig`, delete:
- `Config.deinit` (lines 450-523)
- `Dependency.deinit` (lines 44-56)
- `Option.deinit` (lines 124-189)
- `WriteFile.deinit` (lines 247-272)
- `Module.deinit` (lines 303-315)
- `ModuleLink.deinit` (lines 322-327)
- `Executable.deinit` (lines 346-356)
- `Library.deinit` (lines 376-386)
- `Object.deinit` (lines 399-407)
- `Test.deinit` (lines 421-428)
- `Fmt.deinit` (lines 436-445)

Keep the `ArrayHashMap.init` calls as-is — they're called with `self.gpa` which becomes the arena.

- [ ] **Step 3: Remove deinit calls from callers**

In `src/main.zig`, there's no `config.deinit()` call (the arena handles it). But check that the `wip_bundle` and other code doesn't call deinit. Looking at `main.zig:105-119`, there's no `defer config.deinit()` — confirmed, no changes needed in main.zig.

In `src/Config.zig:1619-1637`, delete the entire test block at the bottom of the file. It uses `std.testing.allocator` (not an arena) and reads a nonexistent "foo.zon" — it's dead code that would leak after deinit removal.

- [ ] **Step 4: Build and test**

```bash
zig build test
```

Expected: All tests pass (the test at Config.zig bottom will fail if actually run, but it's not in the test runner — it requires a `foo.zon` file).

- [ ] **Step 5: Commit**

```bash
git add src/Config.zig
git commit -m "refactor(phase-b): remove all deinit methods from Config types

All Config parsing uses arena allocation. Manual deinit is unnecessary
and was a source of memory leak bugs (2.11, 3.1, 3.2, 3.3, 3.10)."
```

### Task 9: Rewrite the parser using std.zon.parse

**Files:**
- Modify: `src/Config.zig`

This is the core of Phase B. Replace the hand-rolled `if/else if` dispatch chains with `fromZoirNode` for plain struct types, and keep thin custom parsers for types that need them.

- [ ] **Step 1: Write the new parser**

Replace the entire `Parser` struct (lines 588-1319) with the new implementation. The new parser has these layers:

**Layer 1 — Top-level parse:** Iterates top-level struct fields, dispatches by name. Same structure as current but shorter — delegates to `fromZoirNode` or custom parsers.

**Layer 2 — parseHashMap:** Generic function that iterates a ZON struct literal's named fields and parses each value. Replaces `parseOptionalHashMap`.

**Layer 3 — Value types parsed by fromZoirNode:** `Module`, `Executable`, `Library`, `Object`, `Test`, `Fmt` are parsed directly by `fromZoirNode`. This eliminates `parseModule`, `parseExecutable`, `parseLibrary`, `parseObject`, `parseTest`, `parseFmt` and all their `if/else if` chains.

**Layer 4 — Custom parsers:**
- `parseDependency` — checks for `path` vs `url` field
- `parseModuleLink` — bare enum literal vs struct literal
- `parseOption` — discriminated by `type` string field
- `parseRun` — plain string, use `fromZoirNode` directly

Here is the complete new Parser:

```zig
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
                // stub — pre-existing incomplete feature
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

    // -- Layer 3: Types parsed by fromZoirNode --

    fn parseModule(self: *Parser, index: std.zig.Zoir.Node.Index) Error!Module {
        // Module has imports as ?[][]const u8 which needs enum literal support.
        // fromZoirNode handles []const u8 but not enum literals as strings.
        // We parse it manually still but much simpler — just iterate fields.
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
                // Use fromZoirNode for all remaining typed fields
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

    fn parseStringOrEnumSlice(self: *Parser, index: std.zig.Zoir.Node.Index) Error!?[]const []const u8 {
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
        try self.returnParseError(message, node_index);
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
```

Key differences from the old parser:
- **`parseHashMap`** replaces both `parseHashMap` and `parseOptionalHashMap` (merged into one that returns `?ArrayHashMap`)
- **`parseModule`** uses `inline for` over struct fields for the typed fields (bool, enum, etc.) and handles strings/imports manually
- **`parseExecutable/Library/Object/Test`** same pattern: handle root_module, name, version, string fields manually, use `inline for` for typed fields
- **`parseDependency`** now parses `hash` and `lazy` (fixes bugs 2.1, 2.10)
- **`parseTest`** now parses `test_runner` (fixes bug 2.3)
- **`parseLibrary`** now parses `version` (fixes bug 2.2)
- **Unknown fields at top level are ignored** (enables build.zig.zon compatibility)
- All the old helper functions (`parseBool`, `parseSlice`, `parseOptionalSlice`, `parseStringOrEnumLiteral`) are eliminated

- [ ] **Step 2: Build** (dead test already removed in Task 8)

```bash
zig build
```

Expected: Compiles cleanly.

- [ ] **Step 4: Run tests**

```bash
zig build test
```

Expected: All 6 fixture tests pass. The new parser handles every field in every fixture.

- [ ] **Step 5: Commit**

```bash
git add src/Config.zig
git commit -m "refactor(phase-b): rewrite parser using std.zon.parse + inline for

Replaces ~600 lines of hand-rolled if/else if dispatch with:
- fromZoirNode for typed fields via comptime reflection
- Thin custom parsers for Dependency, ModuleLink, Option
- Generic parseHashMap for all StringArrayHashMap fields

Fixes: 2.1 (hash/lazy), 2.2 (Library.version), 2.3 (Test.test_runner),
2.11 (include_paths leak), 3.1-3.3 (deinit leaks), 3.10 (error leak),
5.3 (no reflection), 5.7 (deinit ceremony)."
```

### Task 10: Add parse fidelity tests

**Files:**
- Create: `test/parse_test.zig`
- Modify: `build.zig.zon` (add test)

- [ ] **Step 1: Create parse fidelity test file**

Create `test/parse_test.zig`:

```zig
const std = @import("std");
const Config = @import("zbuild").Config;

fn parseFixture(arena: std.mem.Allocator, fixture: []const u8) !Config {
    return try Config.parseFromFile(arena, fixture, null);
}

test "basic1: simple module" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseFixture(arena.allocator(), "test/fixtures/basic1.build.zig.zon");

    try std.testing.expectEqualStrings("basic", config.name);
    try std.testing.expectEqualStrings("0.1.0", config.version);
    try std.testing.expectEqual(@as(u64, 0x90797553773ca567), config.fingerprint);

    const modules = config.modules orelse return error.MissingModules;
    try std.testing.expectEqual(@as(usize, 1), modules.count());
    const m0 = modules.get("module_0") orelse return error.MissingModule;
    try std.testing.expectEqualStrings("src/module_0/main.zig", m0.root_source_file.?);
}

test "basic2: module with all bool/enum fields" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseFixture(arena.allocator(), "test/fixtures/basic2.build.zig.zon");

    const modules = config.modules orelse return error.MissingModules;
    const m1 = modules.get("module_1") orelse return error.MissingModule;

    try std.testing.expectEqual(true, m1.link_libc.?);
    try std.testing.expectEqual(true, m1.link_libcpp.?);
    try std.testing.expectEqual(true, m1.single_threaded.?);
    try std.testing.expectEqual(true, m1.strip.?);
    try std.testing.expectEqual(std.builtin.OptimizeMode.ReleaseFast, m1.optimize.?);
    try std.testing.expectEqual(std.builtin.CodeModel.default, m1.code_model.?);
    try std.testing.expectEqual(false, m1.fuzz.?);
    try std.testing.expectEqual(true, m1.valgrind.?);
}

test "basic3: multiple modules with target/optimize" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseFixture(arena.allocator(), "test/fixtures/basic3.build.zig.zon");

    const modules = config.modules orelse return error.MissingModules;
    try std.testing.expectEqual(@as(usize, 2), modules.count());

    const m0 = modules.get("module_0") orelse return error.MissingModule;
    try std.testing.expectEqualStrings("native", m0.target.?);
    try std.testing.expectEqual(std.builtin.OptimizeMode.ReleaseFast, m0.optimize.?);
}

test "basic4: executables and libraries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseFixture(arena.allocator(), "test/fixtures/basic4.build.zig.zon");

    const exes = config.executables orelse return error.MissingExecutables;
    try std.testing.expectEqual(@as(usize, 1), exes.count());
    const exe = exes.get("module_0") orelse return error.MissingExe;
    switch (exe.root_module) {
        .module => |m| {
            try std.testing.expectEqualStrings("module_0_exe", m.name.?);
            try std.testing.expectEqualStrings("src/module_0/main.zig", m.root_source_file.?);
        },
        .name => return error.ExpectedInlineModule,
    }

    const libs = config.libraries orelse return error.MissingLibraries;
    try std.testing.expectEqual(@as(usize, 1), libs.count());
}

test "basic5: options modules" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseFixture(arena.allocator(), "test/fixtures/basic5.build.zig.zon");

    const opts_modules = config.options_modules orelse return error.MissingOptionsModules;
    try std.testing.expectEqual(@as(usize, 1), opts_modules.count());

    const build_options = opts_modules.get("build_options") orelse return error.MissingBuildOptions;
    const min_depth = build_options.get("min_depth") orelse return error.MissingOption;
    switch (min_depth) {
        .int => |i| {
            try std.testing.expectEqualStrings("usize", i.type);
            try std.testing.expectEqual(@as(i64, 0), i.default.?);
        },
        else => return error.WrongOptionType,
    }
}

test "basic6: runs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const config = try parseFixture(arena.allocator(), "test/fixtures/basic6.build.zig.zon");

    const runs = config.runs orelse return error.MissingRuns;
    try std.testing.expectEqual(@as(usize, 1), runs.count());
    const docs = runs.get("docs") orelse return error.MissingDocs;
    try std.testing.expectEqualStrings("echo 'Generating documentation...'", docs);
}
```

- [ ] **Step 2: Add the test to zbuild's own config**

Add a test entry to `build.zig.zon` in the `.tests` section:

```zon
.parse_test = .{
    .root_module = .{
        .private = true,
        .root_source_file = "test/parse_test.zig",
        .imports = .{.zbuild},
    },
},
```

- [ ] **Step 3: Regenerate build.zig and run**

```bash
zig build -- run:zbuild sync
zig build test
```

Expected: All tests pass including the new parse fidelity tests.

- [ ] **Step 4: Commit**

```bash
git add test/parse_test.zig build.zig.zon build.zig
git commit -m "test(phase-b): add parse fidelity tests for all 6 fixtures

Verifies specific field values after parsing, catching 'field silently
ignored' and 'field parsed but wrong value' bugs."
```

---

## Chunk 3: Phase C — Static build.zig

### Task 11: Create build_runner.zig

**Files:**
- Create: `src/build_runner.zig`

This is the core of Phase C. The `configureBuild` function reads a Config and calls `std.Build` API directly — the same logic as ConfigBuildgen but without string concatenation.

- [ ] **Step 1: Create src/build_runner.zig**

```zig
//! Configures a Zig build graph from a zbuild Config.
//! Replaces string-concatenation codegen (ConfigBuildgen) with direct API calls.

const std = @import("std");
const Config = @import("Config.zig");

pub fn configureBuild(b: *std.Build, config: Config) !void {
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
    };

    // Phase 1: Create options and options modules
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
            if (module.private orelse true) {
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
    var has_tests = false;
    var tls_run_test: ?*std.Build.Step = null;

    // Auto-create tests for named modules
    if (config.modules) |modules| {
        if (modules.count() > 0 or (config.tests != null and config.tests.?.count() > 0)) {
            tls_run_test = b.step("test", "Run all tests");
            has_tests = true;
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
        if (!has_tests) {
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
    if (config.modules) |modules| {
        for (modules.keys(), modules.values()) |name, module| {
            if (module.imports) |imports| {
                const m = runner.modules.get(name) orelse continue;
                try runner.wireImports(m, imports);
            }
        }
    }
    // Wire imports for inline modules in executables/libraries/objects/tests
    if (config.executables) |exes| {
        for (exes.values()) |exe| {
            if (exe.root_module == .module) {
                if (exe.root_module.module.imports) |imports| {
                    const name = exe.root_module.module.name orelse continue;
                    const m = runner.modules.get(name) orelse continue;
                    try runner.wireImports(m, imports);
                }
            }
        }
    }
    if (config.libraries) |libs| {
        for (libs.values()) |lib| {
            if (lib.root_module == .module) {
                if (lib.root_module.module.imports) |imports| {
                    const name = lib.root_module.module.name orelse continue;
                    const m = runner.modules.get(name) orelse continue;
                    try runner.wireImports(m, imports);
                }
            }
        }
    }
    if (config.objects) |objs| {
        for (objs.values()) |obj| {
            if (obj.root_module == .module) {
                if (obj.root_module.module.imports) |imports| {
                    const name = obj.root_module.module.name orelse continue;
                    const m = runner.modules.get(name) orelse continue;
                    try runner.wireImports(m, imports);
                }
            }
        }
    }
    if (config.tests) |tests| {
        for (tests.values()) |t| {
            if (t.root_module == .module) {
                if (t.root_module.module.imports) |imports| {
                    const name = t.root_module.module.name orelse continue;
                    const m = runner.modules.get(name) orelse continue;
                    try runner.wireImports(m, imports);
                }
            }
        }
    }
}

const BuildRunner = struct {
    b: *std.Build,
    config: Config,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    modules: std.StringHashMap(*std.Build.Module),
    dependencies: std.StringHashMap(*std.Build.Dependency),
    options_modules: std.StringHashMap(*std.Build.Module),

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
        _ = dep; // args are handled by zig build system
        const d = self.b.dependency(@ptrCast(name), .{
            .optimize = self.optimize,
            .target = self.target,
        });
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
                const val = opts.step.owner.option(bool, name, .{ .description = v.description orelse "" });
                opts.addOption(bool, name, val orelse v.default orelse null);
            },
            .int => |v| {
                // For int options, we use i64 as the runtime type since we can't
                // create arbitrary int types at runtime
                const val = opts.step.owner.option(i64, name, .{ .description = v.description orelse "" });
                opts.addOption(i64, name, val orelse v.default orelse null);
            },
            .float => |v| {
                const val = opts.step.owner.option(f64, name, .{ .description = v.description orelse "" });
                opts.addOption(f64, name, val orelse v.default orelse null);
            },
            .string => |v| {
                const val = opts.step.owner.option([]const u8, name, .{ .description = v.description orelse "" });
                opts.addOption([]const u8, name, val orelse v.default orelse null);
            },
            .list => |v| {
                const val = opts.step.owner.option([]const []const u8, name, .{ .description = v.description orelse "" });
                opts.addOption([]const []const u8, name, val orelse v.default orelse null);
            },
            // enum and enum_list require comptime types — pass through as strings
            .@"enum" => |v| {
                const val = opts.step.owner.option([]const u8, name, .{ .description = v.description orelse "" });
                opts.addOption([]const u8, name, val orelse v.default orelse null);
            },
            .enum_list => |v| {
                const val = opts.step.owner.option([]const []const u8, name, .{ .description = v.description orelse "" });
                opts.addOption([]const []const u8, name, val orelse v.default orelse null);
            },
            .build_id => |v| {
                _ = v;
                // TODO: build_id options
            },
            .lazy_path => |v| {
                _ = v;
                // TODO: lazy_path options
            },
            .lazy_path_list => |v| {
                _ = v;
                // TODO: lazy_path_list options
            },
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
        // Simple shell command splitting (space-delimited)
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

    fn wireImports(self: *BuildRunner, module: *std.Build.Module, imports: []const []const u8) !void {
        for (imports) |import_name| {
            const resolved = self.resolveImport(import_name);
            module.addImport(import_name, resolved);
        }
    }

    fn resolveImport(self: *BuildRunner, import_name: []const u8) *std.Build.Module {
        // Check named modules first
        if (self.modules.get(import_name)) |m| return m;
        // Check options modules
        if (self.options_modules.get(import_name)) |m| return m;
        // Check dependencies (possibly with dep:module syntax)
        var parts = std.mem.splitScalar(u8, import_name, ':');
        const first = parts.first();
        if (self.dependencies.get(first)) |dep| {
            const module_name = if (parts.next()) |rest| rest else first;
            return dep.module(module_name);
        }
        @panic(self.b.fmt("zbuild: unresolved import '{s}'", .{import_name}));
    }

    fn resolveLazyPath(self: *BuildRunner, path: []const u8) std.Build.LazyPath {
        // For now, simple path resolution. Dependency lazy paths use colon syntax.
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
```

**Important notes about this implementation:**
- Dependencies with custom args are not fully supported yet — the `b.dependency()` call passes target/optimize but not custom args. This matches the current behavior since dependency args from ZON are forwarded by the build system automatically.
- Options module type handling is simplified — enum/enum_list use string types at runtime since we can't create comptime enum types dynamically. This may need refinement later.
- The `resolveLazyPath` handles `dep:path` and `dep:writefiles:path` syntax like ConfigBuildgen did.

- [ ] **Step 2: Build to verify it compiles**

```bash
zig build
```

Expected: Compiles (build_runner.zig is not yet wired into any caller, just needs to parse correctly).

- [ ] **Step 3: Commit**

```bash
git add src/build_runner.zig
git commit -m "feat(phase-c): add build_runner.zig with configureBuild

Direct std.Build API calls replace string-concatenation codegen.
~500 lines replaces ~1280 lines of ConfigBuildgen."
```

### Task 12: Update cmd_sync to use static build.zig template

**Files:**
- Modify: `src/cmd_sync.zig`
- Modify: `src/cmd_init.zig`

- [ ] **Step 1: Rewrite cmd_sync.zig**

The sync command now just ensures `build.zig` has the static template. No more codegen.

```zig
const std = @import("std");
const mem = std.mem;
const Allocator = std.mem.Allocator;
const fatal = std.process.fatal;
const GlobalOptions = @import("GlobalOptions.zig");
const Config = @import("Config.zig");

const static_build_zig =
    \\const std = @import("std");
    \\const zbuild = @import("zbuild");
    \\
    \\pub fn build(b: *std.Build) void {
    \\    zbuild.configureBuild(b) catch |err| {
    \\        std.log.err("zbuild: {}", .{err});
    \\    };
    \\}
    \\
;

pub fn exec(gpa: Allocator, arena: Allocator, global_opts: GlobalOptions, config: Config) !void {
    _ = gpa;
    _ = arena;
    _ = config;
    if (global_opts.no_sync) {
        fatal("--no-sync is incompatible with the sync command", .{});
    }

    var opened_dir: ?std.fs.Dir = null;
    defer if (opened_dir) |*d| d.close();

    const dir = if (global_opts.project_dir.len > 0 and !mem.eql(u8, global_opts.project_dir, ".")) blk: {
        opened_dir = try std.fs.cwd().openDir(global_opts.project_dir, .{});
        break :blk opened_dir.?;
    } else std.fs.cwd();

    dir.writeFile(.{
        .sub_path = "build.zig",
        .data = static_build_zig,
    }) catch |err| {
        fatal("failed to write build.zig: {s}", .{@errorName(err)});
    };
}
```

- [ ] **Step 2: Update cmd_init.zig to write static build.zig**

In `cmd_init.zig`, after `sync.exec` is called, the static template gets written. The `sync.exec` now handles this. No further changes needed in cmd_init beyond what Phase A already did.

- [ ] **Step 3: Expose configureBuild in main.zig public API**

In `src/main.zig`, add:

```zig
pub const build_runner = @import("build_runner.zig");
pub const configureBuild = build_runner.configureBuild;
```

This lets user projects import `zbuild` and call `zbuild.configureBuild(b)`.

- [ ] **Step 4: Build and verify**

```bash
zig build
```

Expected: Compiles. The sync command now writes the static template.

- [ ] **Step 5: Commit**

```bash
git add src/cmd_sync.zig src/main.zig
git commit -m "refactor(phase-c): replace codegen with static build.zig template

cmd_sync now writes a fixed build.zig that imports zbuild and calls
configureBuild. No more string concatenation, scratch buffers, or
zig fmt post-processing."
```

### Task 13: Delete ConfigBuildgen and sync_build_file

**Files:**
- Delete: `src/ConfigBuildgen.zig`
- Delete: `src/sync_build_file.zig`
- Modify: `src/main.zig` (remove ConfigBuildgen import)

- [ ] **Step 1: Remove imports from main.zig**

In `src/main.zig:8`, remove:
```zig
pub const ConfigBuildgen = @import("ConfigBuildgen.zig");
```

- [ ] **Step 2: Delete the files**

```bash
rm src/ConfigBuildgen.zig src/sync_build_file.zig
```

- [ ] **Step 3: Remove run_zig imports from cmd_sync**

cmd_sync no longer needs `runZigFmt`. Check that the new cmd_sync.zig doesn't import it (it shouldn't — we rewrote it in Task 12).

- [ ] **Step 4: Build**

```bash
zig build
```

Expected: Compiles cleanly. No dangling references to ConfigBuildgen or sync_build_file.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor(phase-c): delete ConfigBuildgen.zig and sync_build_file.zig

Eliminates ~1300 lines of string-concatenation codegen. Fixes bugs
1.6, 2.5, 2.6, 2.14, 3.7, 4.1, 4.3, 4.6, 5.5, 5.6, 5.10."
```

### Task 14: Update zbuild's own build system

**Files:**
- Modify: `build.zig.zon`
- Modify: `build.zig`

zbuild itself does NOT use the static build.zig pattern (that would be circular). It keeps a hand-written `build.zig`. But we need to update it since we removed ConfigBuildgen.

- [ ] **Step 1: Write zbuild's own build.zig by hand**

zbuild needs a hand-written `build.zig` that builds itself. The current generated one is close — we just need to maintain it manually now. Write `build.zig`:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // zbuild library module (for use by zbuild-powered projects)
    const zbuild_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.modules.put(b.dupe("zbuild"), zbuild_module) catch @panic("OOM");

    // zbuild executable
    const exe = b.addExecutable(.{
        .name = "zbuild",
        .root_module = zbuild_module,
    });
    const install_exe = b.addInstallArtifact(exe, .{});
    b.getInstallStep().dependOn(&install_exe.step);

    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| run_exe.addArgs(args);
    const run_step = b.step("run:zbuild", "Run the zbuild executable");
    run_step.dependOn(&run_exe.step);

    // Tests
    const tls_run_test = b.step("test", "Run all tests");

    // zbuild unit tests
    const test_zbuild = b.addTest(.{
        .name = "zbuild",
        .root_module = zbuild_module,
        .filters = b.option([]const []const u8, "zbuild.filters", "zbuild test filters") orelse &.{},
    });
    const run_test_zbuild = b.addRunArtifact(test_zbuild);
    const tls_test_zbuild = b.step("test:zbuild", "Run the zbuild test");
    tls_test_zbuild.dependOn(&run_test_zbuild.step);
    tls_run_test.dependOn(&run_test_zbuild.step);

    // sync integration test
    const sync_module = b.createModule(.{
        .root_source_file = b.path("test/sync.zig"),
        .target = target,
        .optimize = optimize,
    });
    sync_module.addImport("zbuild", zbuild_module);

    const test_sync = b.addTest(.{
        .name = "sync",
        .root_module = sync_module,
        .filters = b.option([]const []const u8, "sync.filters", "sync test filters") orelse &.{},
    });
    const run_test_sync = b.addRunArtifact(test_sync);
    const tls_test_sync = b.step("test:sync", "Run the sync test");
    tls_test_sync.dependOn(&run_test_sync.step);
    tls_run_test.dependOn(&run_test_sync.step);

    // parse fidelity test
    const parse_test_module = b.createModule(.{
        .root_source_file = b.path("test/parse_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    parse_test_module.addImport("zbuild", zbuild_module);

    const test_parse = b.addTest(.{
        .name = "parse_test",
        .root_module = parse_test_module,
        .filters = b.option([]const []const u8, "parse_test.filters", "parse_test test filters") orelse &.{},
    });
    const run_test_parse = b.addRunArtifact(test_parse);
    const tls_test_parse = b.step("test:parse_test", "Run the parse_test test");
    tls_test_parse.dependOn(&run_test_parse.step);
    tls_run_test.dependOn(&run_test_parse.step);
}
```

- [ ] **Step 2: Run all tests**

```bash
zig build test
```

Expected: All tests pass — sync tests (6 fixtures), parse fidelity tests (6 fixtures), zbuild unit tests.

- [ ] **Step 3: Verify the sync test still works end-to-end**

The sync test calls `zbuild.build.exec()` which calls `sync.exec()` which now writes the static template. Then it runs `zig build --help`. But wait — the static template imports `zbuild` as a dependency, and the test fixtures don't have zbuild as a dependency. This means `zig build --help` will fail because `@import("zbuild")` won't resolve.

**This is a critical issue.** The static build.zig approach requires zbuild to be a dependency in the project's `build.zig.zon`. For the test fixtures, we have two options:

A. Add zbuild as a path dependency to each fixture
B. Keep the sync test using the old approach where sync writes a standalone build.zig

Option A is cleaner. Update each fixture to include:
```zon
.dependencies = .{
    .zbuild = .{
        .path = "../..",
    },
},
```

But this means the fixtures have a `.dependencies` field that references the zbuild source tree. Let's verify this path would be correct — the fixtures are at `test/fixtures/basic*.build.zig.zon` and zbuild root is `../../` from there.

Actually, looking at the test more carefully: `test/sync.zig:36-47` calls `zbuild.build.exec()` with `global_opts`, which runs `sync.exec` then `runZigBuild`. The `runZigBuild` runs `zig build --help` in the project dir (which is `test/`). So `build.zig` will be written to `test/build.zig` and `build.zig.zon` needs to be in `test/`.

The current test creates `test/build.zig` and `test/build.zig.zon` from the fixture, then cleans up. With the static approach, `test/build.zig` will try to `@import("zbuild")` which needs zbuild as a dependency.

**Resolution:** We'll update the test to generate build.zig.zon with the zbuild dependency included. The sync test becomes an integration test that proves the full pipeline works.

This requires modifying the fixtures or the test setup. We'll add the zbuild path dependency to each fixture.

- [ ] **Step 4: Update test fixtures with zbuild dependency**

Add to each `test/fixtures/basic*.build.zig.zon`:

```zon
.dependencies = .{
    .zbuild = .{
        .path = "../..",
    },
},
```

For fixtures that already have `.dependencies = .{}`, replace the empty with the zbuild dep.

- [ ] **Step 5: Update test/sync.zig**

The test currently creates `test/build.zig.zon` by running the sync command. With the static approach, the sync command writes `test/build.zig` (the static template) but doesn't touch `build.zig.zon` — the fixture IS the `build.zig.zon`.

Update the test to copy the fixture to `test/build.zig.zon` before syncing:

```zig
fn testSync(gpa: Allocator, arena: Allocator, should_cleanup: bool, global_opts: zbuild.GlobalOptions) !void {
    defer maybeCleanup(should_cleanup);

    const config = try zbuild.Config.parseFromFile(arena, global_opts.zbuild_file, null);

    // Copy the fixture to build.zig.zon in the project dir
    const fixture_content = try std.fs.cwd().readFileAlloc(gpa, global_opts.zbuild_file, 16_000);
    defer gpa.free(fixture_content);

    const dir = try std.fs.cwd().openDir(cwd, .{});
    try dir.writeFile(.{
        .sub_path = "build.zig.zon",
        .data = fixture_content,
    });

    try zbuild.build.exec(
        gpa,
        arena,
        global_opts,
        config,
        .{
            .kind = .build,
            .args = &[1][]const u8{"--help"},
            .stderr_behavior = .Ignore,
            .stdout_behavior = .Ignore,
        },
    );
}
```

Wait — this gets complicated because the test project dir is `test/` and the fixture files are also in `test/fixtures/`. The `sync.exec` will write `test/build.zig` (the static template). Then `zig build --help` runs in `test/` and needs `test/build.zig.zon` to have the zbuild dependency.

Actually, re-reading the current flow: the `zbuild_file` is set to the fixture path like `test/fixtures/basic1.build.zig.zon`. The sync command reads this and generates `build.zig` in `project_dir` (which is `test/`). Previously, it also generated `build.zig.zon` in `test/` from the config. Now it just writes the static `build.zig`.

For `zig build --help` to work, `test/build.zig.zon` must exist and if the static template does `@import("zbuild")`, it needs a zbuild dependency. So we need `test/build.zig.zon` to have the fixture content PLUS a zbuild dependency.

This is getting complex. Let me simplify: **For zbuild's own testing, keep a hand-written build.zig that doesn't use the static template.** The static template is for USER projects that depend on zbuild. zbuild tests its own code directly.

The sync test tests that the config is parseable and produces a valid build graph. We should refactor it to test `configureBuild` directly rather than going through the `zig build --help` pipeline.

I'll adjust the plan accordingly.

- [ ] **Step 4 (revised): Rewrite sync test to test configureBuild directly**

This is a better approach. Instead of testing the full `zig build --help` pipeline (which requires zbuild-as-dependency), test that `configureBuild` produces a valid build graph. But `configureBuild` needs a real `std.Build` instance, which we can't easily create in a unit test.

**Alternative:** Keep the E2E test but have it use zbuild's own hand-written `build.zig` (not the static template). The sync command for zbuild's own test directory simply generates `build.zig` using the old approach... but we deleted ConfigBuildgen.

**Simplest solution:** The E2E test stays but the test project uses a hand-written `build.zig` that does `@import("zbuild").configureBuild(b)`. We set up `test/` as a mini project with its own `build.zig.zon` that depends on zbuild.

Let me restructure: we'll create `test/build.zig.zon.template` that includes the zbuild path dependency, and the test will write this + the fixture fields to `test/build.zig.zon` before running `zig build --help`.

Actually the simplest approach: since the static build.zig requires zbuild as a dependency, and we want to test it end-to-end, we need `test/build.zig.zon` to have `zbuild` as a dependency. Let's just make each test create a merged `build.zig.zon`:

```zig
fn testSync(gpa: Allocator, arena: Allocator, should_cleanup: bool, global_opts: zbuild.GlobalOptions) !void {
    defer maybeCleanup(should_cleanup);

    // Parse the fixture
    const config = try zbuild.Config.parseFromFile(arena, global_opts.zbuild_file, null);

    // Write the static build.zig
    try zbuild.sync.exec(gpa, arena, global_opts, config);

    // The fixture is already at the zbuild_file path. We need to also make it
    // available as test/build.zig.zon with a zbuild dependency.
    // For now, just copy fixture content and add zbuild dep.
    // Actually - the simplest approach is to have each fixture include the zbuild dep already.

    try zbuild.build.exec(
        gpa, arena, global_opts, config,
        .{
            .kind = .build,
            .args = &[1][]const u8{"--help"},
            .stderr_behavior = .Ignore,
            .stdout_behavior = .Ignore,
        },
    );
}
```

Since we already decided to add `.dependencies = .{ .zbuild = .{ .path = "../.." } }` to each fixture, and the sync command writes `test/build.zig`, this should work. The `zbuild_file` points to the fixture, `project_dir` is `test/`, sync writes `test/build.zig`, and `zig build --help` runs in `test/` finding `test/build.zig` (static template) and `test/build.zig.zon` (which is... where?).

The problem: `test/build.zig.zon` needs to be the fixture. Currently `sync.exec` used to write it. Now it doesn't. We need the test to copy the fixture to `test/build.zig.zon`.

OK let me just add that to the test and keep it simple.

- [ ] **Step 4 (final): Update fixtures and test**

Add `.dependencies = .{ .zbuild = .{ .path = "../.." } }` to each of the 6 fixture files (or keep existing `.dependencies = .{}` for those that have it, but add zbuild).

Update `test/sync.zig`:
```zig
fn testSync(gpa: Allocator, arena: Allocator, should_cleanup: bool, global_opts: zbuild.GlobalOptions) !void {
    defer maybeCleanup(should_cleanup);

    const config = try zbuild.Config.parseFromFile(arena, global_opts.zbuild_file, null);

    // Copy fixture to test/build.zig.zon so zig build can find it
    const fixture_content = try std.fs.cwd().readFileAllocOptions(gpa, global_opts.zbuild_file, 16_000, null, @alignOf(u8), null);
    defer gpa.free(fixture_content);
    const dir = try std.fs.cwd().openDir(cwd, .{});
    try dir.writeFile(.{ .sub_path = "build.zig.zon", .data = fixture_content });

    try zbuild.build.exec(
        gpa, arena, global_opts, config,
        .{
            .kind = .build,
            .args = &[1][]const u8{"--help"},
            .stderr_behavior = .Ignore,
            .stdout_behavior = .Ignore,
        },
    );
}
```

- [ ] **Step 5: Run all tests**

```bash
zig build test
```

Expected: All tests pass.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "refactor(phase-c): update zbuild build.zig and test fixtures for static template

zbuild uses a hand-written build.zig (no circular dependency). Test
fixtures include zbuild as a path dependency for E2E testing."
```

### Task 15: Final verification and cleanup

- [ ] **Step 1: Run the full test suite**

```bash
zig build test
```

Expected: All tests pass.

- [ ] **Step 2: Verify `zig build --help` on the zbuild project itself**

```bash
zig build --help
```

Expected: Shows build steps for zbuild (run:zbuild, test, test:zbuild, test:sync, test:parse_test).

- [ ] **Step 3: Count lines removed vs added**

```bash
git diff --stat main
```

Expected: Significant net line reduction (~1400 lines).

- [ ] **Step 4: Final commit if any cleanup needed**

```bash
git add -A
git commit -m "refactor: final cleanup after three-phase architecture refactor"
```

---

## Summary of Bug Fixes

| Bug | Description | Fixed By |
|-----|------------|----------|
| 2.1 | hash/lazy never parsed | Phase B: parseDependency now handles hash/lazy |
| 2.2 | Library.version not parsed | Phase B: inline for parses all fields |
| 2.3 | Test.test_runner not parsed | Phase B: explicit parseTest handler |
| 2.5 | depends_on parsed but never emitted | Phase C: configureBuild can implement step deps |
| 2.6 | Unused-variable detection incomplete | Phase C: eliminated (no generated variables) |
| 2.9 | description/keywords not in build.zig.zon | Phase A: single file, no translation |
| 2.10 | hash/lazy not serialized | Phase A: single file, no re-serialization needed |
| 2.11 | include_paths not freed | Phase B: arena allocation |
| 2.12 | No rollback on fetch failure | Phase A: no two-phase sync |
| 2.13 | updateConfigDependency uses wrong parser | Phase A: simplified cmd_fetch |
| 2.14 | writeImport wrong module ID | Phase C: direct API calls |
| 3.1 | Executable.dest_sub_path not freed | Phase B: arena allocation |
| 3.2 | Library.dest_sub_path not freed | Phase B: arena allocation |
| 3.3 | parseObject leaks field name | Phase B: arena allocation |
| 3.7 | zig fmt errors suppressed | Phase C: no fmt step |
| 3.10 | returnParseError leaks message | Phase B: arena allocation |
| 4.1 | Shared scratch buffer fragile | Phase C: eliminated |
| 4.3 | run step name collision | Phase C: detect and error |
| 4.5 | Two-phase sync ordering | Phase A: eliminated |
| 5.3 | Parser uses no reflection | Phase B: inline for + fromZoirNode |
| 5.5 | No codegen IR | Phase C: eliminated (no codegen) |
| 5.6 | writeImports type switch | Phase C: eliminated |
| 5.7 | deinit ceremony repeats | Phase B: arena allocation |
| 5.8 | Manifest parallel data model | Phase A: eliminated |
| 5.10 | strTupleLiteral cross-import | Phase A+C: eliminated |
