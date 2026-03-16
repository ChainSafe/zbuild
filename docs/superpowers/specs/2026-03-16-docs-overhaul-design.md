# Documentation Overhaul Design

## Problem

All existing documentation describes the old zbuild (a CLI tool that generated `build.zig` from `zbuild.zon`). The project has been rewritten as a library using `@import("build.zig.zon")` + comptime metaprogramming. Every doc file is stale. There are no examples. There is no schema reference. A user cannot learn how to use zbuild from the existing docs.

## Audience

- **Beginners:** Want a simpler build experience. Need a quickstart and copy-paste examples.
- **Experienced Zig developers:** Know `build.zig` well. Need a schema reference, the rationale, and confidence they can escape back to manual code.

## Approach

B + C hybrid: README as landing page, `docs/` for reference material, `examples/` as compilable annotated projects that double as documentation and integration tests.

## File Structure

### Delete

- `docs/MOTIVATION.md` — stale (references CLI tool)
- `docs/TODO.md` — stale (references old parser/Config.zig)
- `docs/AdvancedFeatures.md` — documents dropped `write_files` feature
- `docs/STRUCTURAL_ISSUES.md` — documents bugs in deleted code
- `docs/superpowers/` — internal working documents, not user-facing

### Create

```
README.md                          ← rewrite from scratch
docs/
  schema.md                        ← complete ZON schema reference
  motivation.md                    ← why zbuild, as a library
examples/
  simple/
    build.zig                      ← 5-line zbuild integration
    build.zig.zon                  ← minimal: one executable
    src/main.zig                   ← hello world
  full/
    build.zig                      ← zbuild with custom Options
    build.zig.zon                  ← modules, options, tests, runs, fmts
    src/main.zig                   ← uses the module
    src/lib.zig                    ← a module with a function
    src/test.zig                   ← test that imports the module
```

### Keep unchanged

- `build.zig`, `build.zig.zon`, `src/` — zbuild's own build

---

## README.md

Target: ~120 lines. A user decides whether to adopt zbuild within 30 seconds.

### Structure

1. **One-liner:** "Declarative build configuration for Zig projects."
2. **The pitch** (3-4 sentences): What it is, the key insight (`@import("build.zig.zon")` + comptime), the escape hatch (works alongside manual `build.zig`).
3. **Before/after:** 25 lines of `build.zig` vs 10 lines of ZON. The money shot.
4. **Quickstart:** Add zbuild as a dependency, write the 5-line `build.zig`, add fields to `build.zig.zon`, `zig build`. No CLI install — it's just a Zig dependency.
5. **Feature list:** Bullet points — modules, executables, libraries, tests, fmts, runs, options modules, dependency args, comptime validation, built-in help step (reads `name`, `version`, `description` from standard ZON metadata).
6. **Links:** `docs/schema.md` for full reference, `examples/` for working projects.
7. **Requirements:** Zig 0.14+
8. **License:** MIT

No contributing section (repo URL not finalized). No installation section (it's a library dependency, not a binary).

---

## docs/schema.md

Target: ~300 lines. The complete reference. An experienced dev looks up any field and knows exactly what it does, what it maps to in `std.Build`, and the default.

### Structure

1. **Intro:** One paragraph — complete reference for zbuild's manifest fields. Unknown fields are silently ignored (forward compat).

2. **Section-by-section reference** with field tables per manifest section:

   **`modules`** — `root_source_file`, `target` (string: `"native"` or arch-os-abi triple like `"x86_64-linux-gnu"`), `optimize` (enum literal: `.Debug`, `.ReleaseSafe`, `.ReleaseFast`, `.ReleaseSmall`), `imports`, `link_libraries`, `include_paths`, `private`, all passthrough fields (`link_libc`, `link_libcpp`, `single_threaded`, `strip`, `unwind_tables`, `dwarf_format`, `code_model`, `error_tracing`, `omit_frame_pointer`, `pic`, `red_zone`, `sanitize_c`, `sanitize_thread`, `stack_check`, `stack_protector`, `fuzz`, `valgrind`). Root module link syntax (enum literal, string, inline struct with optional `name` override). `link_libraries` colon syntax: `"dep_name:artifact_name"` (resolves a library artifact from a dependency; distinct from LazyPath resolution).

   **`executables`** — `root_module` (three forms: enum literal reference, string reference, inline struct with optional `name` override), `version`, `linkage`, `dest_sub_path`, `depends_on`, passthrough fields (`max_rss`, `use_llvm`, `use_lld`), `zig_lib_dir`, `win32_manifest`. Steps: `build-exe:<name>`, `run:<name>`.

   **`libraries`** — Same as executables plus `linker_allow_shlib_undefined`, `zig_lib_dir`, `win32_manifest`. Steps: `build-lib:<name>`.

   **`objects`** — Simpler subset (no version/linkage/dest_sub_path/win32_manifest). Supports `zig_lib_dir` and passthrough fields. Steps: `build-obj:<name>`.

   **`tests`** — `root_module`, `filters`, passthrough fields (`max_rss`, `use_llvm`, `use_lld`), `zig_lib_dir`. Steps: `test:<name>`, `build-test:<name>`, aggregate `test`. CLI override: `-D<name>.filters=...`.

   **`fmts`** — `paths`, `exclude_paths`, `check`. Steps: `fmt:<name>`, aggregate `fmt`.

   **`runs`** — Dual-form syntax. Short form: bare tuple of strings. Long form: struct with `cmd`, `cwd`, `env`, `inherit_stdio`, `stdin`, `stdin_file`, `depends_on`. Steps: `cmd:<name>`.

   **`options_modules`** — Types: `bool`, `string`, `list`, `enum`, `enum_list`, int types, float types. Fields: `type`, `default`, `description`. How to `@import` the resulting module.

   **`dependencies`** — `args` field for forwarding comptime dependency args.

3. **LazyPath resolution** — Colon syntax for path strings: `"path"` (local), `"dep:path"` (named lazy path from dependency), `"dep:<write_files_name>:<path>"` (file within a dependency's named WriteFiles step). How `resolveLazyPath` dispatches.

4. **Comptime validation** — What gets checked (root_module refs, depends_on refs, import refs, stdin/stdin_file mutual exclusion). What doesn't (unknown fields silently ignored).

### Field table format

| Field | Type | Default | Maps to |
|-------|------|---------|---------|
| `root_source_file` | string | — | `Module.CreateOptions.root_source_file` |

---

## docs/motivation.md

Target: ~80 lines. Readable in 2 minutes.

### Structure

1. **The problem** (5-6 lines): `build.zig` is powerful but verbose. Common patterns require 20+ lines per target. Scales poorly, intimidating for newcomers.
2. **The insight** (3-4 lines): `@import("build.zig.zon")` + comptime. Compiler is the parser, type system is the schema, `@compileError` is validation. Zero runtime parsing.
3. **Before/after:** Side-by-side comparison with commentary.
4. **What zbuild is NOT:** Not a replacement for `build.zig`. Handles the declarative 90%. Mix with manual code. Escape hatch always available.
5. **Inspiration:** Cargo, npm. Unlike those, zbuild rides on top of the build system rather than replacing it.

---

## examples/simple/

Minimum viable zbuild project. One executable, no dependencies, no modules.

- **`build.zig.zon`:** Project metadata, one executable with inline root_module, zbuild as path dependency (`../..`).
- **`build.zig`:** Import zbuild, call `configureBuild(b, @import("build.zig.zon"), .{})`, error handler.
- **`src/main.zig`:** Hello world.

No comments explaining comptime mechanics. Just the smallest thing that works.

Must compile with `zig build` from the example directory.

## examples/full/

Showcases every zbuild feature. Heavily commented ZON.

- **`build.zig.zon`:** modules (with imports, link_libc), executables (referencing named module), libraries, tests, fmts, runs (short + long form), options_modules. zbuild as path dependency.
- **`build.zig`:** zbuild with custom `Options` (renamed help step).
- **`src/lib.zig`:** Module with an exported function.
- **`src/main.zig`:** Imports the module.
- **`src/test.zig`:** Test that imports the module.

Dependencies section omitted from compilable code (no real URL). Shown as a commented example explaining "uncomment when you have a real dep."

Must compile with `zig build` from the example directory.

---

## Constraints

- Both examples use `zbuild` as a `.path = "../.."` dependency so they compile from the repo checkout.
- Examples must actually compile. They serve as integration tests.
- Schema reference is derived from the actual code in `build_runner.zig`. If the code changes, the schema doc must be updated.
- Unknown manifest fields are silently ignored for forward compatibility. The schema doc only documents zbuild-recognized fields.
