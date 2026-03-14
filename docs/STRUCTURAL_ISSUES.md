# Structural Issues

A comprehensive audit of the zbuild codebase covering bugs, architectural gaps, and design improvements.

---

## 1. Critical — Crashes, compile failures, or data corruption

### 1.1 `write_files` parser is a stub
**Config.zig:648-649**

The top-level parse branch for `write_files` is an empty comment:
```zig
} else if (std.mem.eql(u8, field_name, "write_files")) {
    // config.write_files = ;
}
```
Any `write_files` in zbuild.zon is silently discarded.

### 1.2 `parseWriteFile` / `parseWriteFilePath` won't compile
**Config.zig:768-771, 785, 787**

`parseT` is called with wrong arity (missing `index` argument). The loop in `parseWriteFile` iterates `n.names` without capturing the value index, so `field_value` is unavailable. These functions are unreachable (due to 1.1) but would fail to compile if called.

### 1.3 `ZigEnv` exit code check is always false
**ZigEnv.zig:33**

```zig
if (result.term != .Exited and result.term.Exited != 0) {
```
`!= .Exited AND .Exited != 0` can never be simultaneously true. Should be `or`. Zig errors (signal termination, non-zero exit) are silently ignored.

### 1.4 `--no-sync` causes infinite loop
**GlobalOptions.zig:73-76**

The flag is set and `continue`s without calling `args.next()`, so the same arg is re-read forever.

### 1.5 `cmd_fetch` accesses wrong union variant
**cmd_fetch.zig:152**

`new_dep.location.url` is accessed unconditionally. For `.path` dependencies this is a tagged-union safety panic.

### 1.6 Missing `.` before `include_extensions` in format string
**ConfigBuildgen.zig:285**

```zig
\\... .exclude_extensions = {s}, include_extensions = {s} ...
```
Missing leading dot generates invalid Zig: `.{ .exclude_extensions = ..., include_extensions = ... }`.

### 1.7 Fingerprint serialization bug
**Config.zig:1352-1353**

`{x}` format on a `[]const u8` string emits byte-hex instead of the fingerprint value. Should use `{s}`.

---

## 2. High — Silent data loss or incorrect behavior

### 2.1 `hash` and `lazy` never parsed from dependencies
**Config.zig:690-716**

`parseDependency` has no branches for `hash` or `lazy`. Both are silently ignored, breaking URL dependency hashing and lazy fetch.

### 2.2 `Library.version` not parsed
**Config.zig:1017-1053**

No parse branch for `"version"`. Always null after parsing. Compare with `parseExecutable` which handles it.

### 2.3 `Test.test_runner` not parsed
**Config.zig:1085-1113**

Field exists in the struct but has no parse branch. Also not emitted in codegen (`writeTest`).

### 2.4 Module `private` logic is inverted
**ConfigBuildgen.zig:506**

`private orelse true` means all modules are exported to `b.modules` by default. A field named `private` defaulting to true (= exported) is semantically backwards.

### 2.5 `depends_on` parsed but never emitted
**ConfigBuildgen.zig (entire)**

`Executable.depends_on`, `Library.depends_on`, `Object.depends_on` are all parsed and freed in `deinit` but no `step.dependOn(...)` call is ever generated.

### 2.6 Unused-variable detection only scans top-level modules
**ConfigBuildgen.zig:151-208**

The logic that marks `target`, `optimize`, `dep_*`, and `options_module_*` as unused only iterates `self.modules`. Projects using only inline modules in executables (a common pattern) will get false `_ = dep_foo;` emissions — which break compilation when the same dep is used in an import.

### 2.7 Serializer has libraries/objects/tests/fmts/runs commented out
**Config.zig:1408-1442**

Five major sections are dead code. `Config.serialize()` silently drops them.

### 2.8 `enum`/`enum_list` options are TODO stubs in serializer
**Config.zig:1537-1546**

Both branches are no-ops. Options of these types are silently dropped during re-serialization.

### 2.9 `description` and `keywords` not written to `build.zig.zon`
**sync_manifest.zig:75-87**

The manifest template has no placeholders for these fields. Dropped on every sync.

### 2.10 `hash`/`lazy` not serialized for dependencies
**Config.zig:1446-1484**

Even if parsed (they aren't — see 2.1), the serializer doesn't write them. URL dependency round-trips lose their hash.

### 2.11 Memory leak: `Module.deinit` doesn't free `include_paths`
**Config.zig:303-315**

`include_paths: ?[][]const u8` is parsed and used in codegen but never freed. Each string in the slice and the slice itself leak.

### 2.12 No rollback on fetch failure during manifest sync
**sync_manifest.zig:40-64**

`build.zig.zon` is written before `zig fetch` runs. If fetch fails mid-loop, the manifest is left in an inconsistent state.

### 2.13 `updateConfigDependency` treats zbuild.zon as build.zig.zon
**cmd_fetch.zig:162-244**

Uses `Manifest.load` which is a `build.zig.zon` parser. Will fail if zbuild.zon contains zbuild-specific fields.

### 2.14 `writeImport` uses wrong module ID when inline module has `.name`
**ConfigBuildgen.zig:918-930**

When an inline module specifies a `.name`, the import code references `module_{exe_key}` but the module was defined as `module_{module_name}`.

---

## 3. Medium — Memory leaks, inconsistencies, incomplete features

### 3.1 `Executable.deinit` doesn't free `dest_sub_path`
**Config.zig:346-356**

### 3.2 `Library.deinit` doesn't free `dest_sub_path`
**Config.zig:376-386**

### 3.3 `parseObject` leaks field name
**Config.zig:1060**

`gpa.dupe(u8, name.get(self.zoir))` without free. All other parsers use `name.get(self.zoir)` directly.

### 3.4 `wip_bundle` never deinit'd on success path
**main.zig:105-119**

No `defer wip_bundle.deinit(gpa)` before the parse call. Memory leak every successful run.

### 3.5 `ast.deinit` called before `manifest.deinit`
**sync_manifest.zig:33-38**

Fragile ordering leaves `m.ast` as a dangling reference between the two deinit calls.

### 3.6 Opened `Dir` handles never closed
**sync_manifest.zig:24-27, cmd_fetch.zig:106, sync_build_file.zig:17-19**

File descriptor leaks when `out_dir` is non-null.

### 3.7 `zig fmt` errors suppressed
**sync_build_file.zig:32-37**

Both stderr and stdout are `.Ignore`. Codegen bugs produce unformatted invalid files with no diagnostic.

### 3.8 `usage` and `list` functions are empty stubs
**cmd_build.zig:36-43**

`--help`/`--list` for build commands print nothing.

### 3.9 `Args.zig` test references non-existent function
**Args.zig:78**

Calls `Args.parse` but the function is named `initFromString`. Test won't compile.

### 3.10 `returnParseError` sets `.owned = false` on heap-allocated message
**Config.zig:1306-1319**

`allocPrint`'d message passed with `.owned = false` leaks the string.

### 3.11 `dependencies_node == 0` used as sentinel
**Manifest.zig:46**

`0` is a valid AST node index. When no dependencies field exists, `getNodeSource(0)` returns the entire file source.

---

## 4. Low — Cosmetic or fragile design

### 4.1 Shared `scratch` buffer is fragile
**ConfigBuildgen.zig:1022**

`fmtId`, `resolveLazyPath`, `resolvedTarget`, `optimize`, `semanticVersion`, etc. all write to one threadlocal 4096-byte buffer. No live bug currently but any reordering or nesting will silently corrupt output.

### 4.2 Run step description says "Run the {name} run"
**ConfigBuildgen.zig:858**

Redundant "run" in user-facing string.

### 4.3 `run:{name}` step name collision
**ConfigBuildgen.zig**

Executables and custom runs both generate `run:{name}` steps. Same-name causes a Zig build panic.

### 4.4 `version` command prints Zig version, not zbuild version
**main.zig:88**

### 4.5 Two-phase sync writes `build.zig` before `build.zig.zon`
**cmd_sync.zig:14-15**

If manifest sync fails, `build.zig` references deps not in the manifest.

### 4.6 `include_extensions` defaults to `null` while `exclude_extensions` defaults to `&.{}`
**ConfigBuildgen.zig:292**

Inconsistent codegen for the two sibling fields.

---

## 5. Architectural Issues

### 5.1 `Config.zig` is a 1600-line mega-file with four responsibilities

It contains the data model, the ZON parser (~730 lines), the serializer (~280 lines), and deinit logic. These could be separate modules sharing the type definitions.

### 5.2 No shared "artifact type" abstraction

`Executable`, `Library`, `Object`, and `Test` share ~80% of fields (`root_module`, `max_rss`, `use_llvm`, `use_lld`, `zig_lib_dir`, `depends_on`...) but are four independent structs. This produces:

- Four near-identical `parseX` functions (manual `if/else if` chains over the same fields)
- Four near-identical `writeX` codegen functions (same field-emission boilerplate)
- Four near-identical `deinit` methods

A `CompileTarget` base struct with comptime composition would collapse ~400 lines.

### 5.3 Parser uses no reflection — every field is manually listed twice

Each field appears once in the struct definition and once in a hand-rolled `if/else if (std.mem.eql(...))` parse chain. No compile-time check keeps them in sync. This is the root cause of 2.1, 2.2, 2.3, 2.5, and 2.8 — fields defined in the struct but missing from the parser or serializer.

A comptime `inline for` over `@typeInfo(T).@"struct".fields` would eliminate this entire class of bug.

### 5.4 Serializer mirrors the parser's problems

Also a manual field-by-field emission, ~60% complete. Same comptime reflection fix applies.

### 5.5 Codegen has no intermediate representation

`ConfigBuildgen` writes directly to a `Writer` via string concatenation. No AST or IR for the output means:

- The unused-variable detection (5.2, 2.6) is a heuristic scan of the input Config, not structural analysis of the output
- The scratch buffer (4.1) exists because there's no arena for temporary codegen strings
- Cross-references require ad-hoc symbol tables (`self.modules`, `self.dependencies`, etc.)

### 5.6 `writeImports` generic is a type switch

**ConfigBuildgen.zig:236-244**

```zig
const imports = switch (T) {
    Config.Module => item.imports orelse continue,
    else => blk: { ... switch (item.root_module) { ... } },
};
```

A comptime generic that switches on its type parameter isn't generic — it's coupled to the specific types that exist today.

### 5.7 `deinit` ceremony repeats ~9 times

`Config.deinit` has the same 3-line map-cleanup pattern for every collection. A single `fn deinitMap(comptime V, ...)` would replace all instances.

### 5.8 Manifest is a parallel data model

`Manifest` (for `build.zig.zon`) and `Config.Dependency` (for `zbuild.zon`) are parallel representations of the same dependency data. The bridge function `depEql` and the AST-splicing hack in `allocPrintManifest` paper over the gap.

### 5.9 Commands have no shared interface

Each `cmd_*.zig` exports an `exec` with a compatible-but-not-enforced signature. No dispatch table, no `Command` interface, no comptime validation. Dispatch in `main.zig` is a flat `mem.eql` chain.

### 5.10 `strTupleLiteral` imported across module boundaries

**sync_manifest.zig:6**

`sync_manifest` imports `strTupleLiteral` from `ConfigBuildgen.zig`, coupling manifest generation to build file generation. This helper belongs in a shared utility module.
