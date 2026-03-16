# Documentation Overhaul Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace all stale documentation with accurate docs for the library-based zbuild, including a README, schema reference, motivation doc, and two compilable example projects.

**Architecture:** Delete everything from the CLI tool era. Write new docs from scratch. Ship two examples (`simple/` and `full/`) that compile against zbuild as a path dependency — these serve as both documentation and integration tests.

**Tech Stack:** Markdown, Zig 0.14, ZON

---

## Chunk 1: Cleanup and core docs

### Task 1: Delete stale documentation

**Files:**
- Delete: `docs/MOTIVATION.md`
- Delete: `docs/TODO.md`
- Delete: `docs/AdvancedFeatures.md`
- Delete: `docs/STRUCTURAL_ISSUES.md`

**Note:** `docs/superpowers/` deletion is deferred to the final task since it contains this plan and the spec.

- [ ] **Step 1: Remove stale doc files**

```bash
rm docs/MOTIVATION.md docs/TODO.md docs/AdvancedFeatures.md docs/STRUCTURAL_ISSUES.md
```

- [ ] **Step 2: Commit**

```bash
git add -u
git commit -m "docs: remove stale documentation from CLI tool era"
```

### Task 2: Write README.md

**Files:**
- Create: `README.md` (rewrite from scratch)

- [ ] **Step 1: Write the README**

The README must contain these sections in order:

1. **Title + one-liner**: "zbuild" / "Declarative build configuration for Zig projects."
2. **Pitch** (3-4 sentences): Library that configures `std.Build` from your `build.zig.zon` at comptime. Key insight: `@import("build.zig.zon")` gives the compiler access to the manifest as a typed struct — no runtime parsing, no codegen, no IR. Works alongside manual `build.zig` code — the escape hatch is always there.
3. **Before/after code comparison**: Show ~25 lines of manual `build.zig` (add module, add executable, install, run step, test) vs the equivalent ZON (~10 lines) + 5-line build.zig. Use the same example from `docs/motivation.md` but keep it concise.
4. **Quickstart** (numbered steps):
   - Add zbuild as a dependency: `zig fetch --save=zbuild <url>` (or path dep for local)
   - Create `build.zig`:
     ```zig
     const zbuild = @import("zbuild");
     const std = @import("std");
     pub fn build(b: *std.Build) void {
         zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err|
             std.log.err("zbuild: {}", .{err});
     }
     ```
   - Add zbuild fields to `build.zig.zon` (show minimal executable example)
   - `zig build`, `zig build run:<name>`, `zig build test`, `zig build help`
5. **Features** (bullet list): modules, executables, libraries, objects, tests, fmts, runs (short + long form), options modules, dependency args forwarding, comptime cross-reference validation, built-in help step
6. **Links**: `docs/schema.md`, `docs/motivation.md`, `examples/`
7. **Requirements**: Zig 0.14+
8. **License**: MIT

Target: ~120 lines total.

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: rewrite README for library-based zbuild"
```

### Task 3: Write docs/motivation.md

**Files:**
- Create: `docs/motivation.md`

- [ ] **Step 1: Write the motivation doc**

Sections:

1. **The problem** (~6 lines): Zig's `build.zig` is powerful but verbose. Adding one executable with install + run + test requires ~25 lines of boilerplate. Multiply by N targets and the build script becomes a maintenance burden. Newcomers face a steep learning curve.

2. **The insight** (~4 lines): Zig 0.14 added `@import("build.zig.zon")`, which gives comptime access to the manifest as a typed anonymous struct. This means: the compiler is the parser, the type system is the schema, `@compileError` is the validation framework, and `inline for` over struct fields generates specialized code per manifest entry. Zero runtime parsing, zero codegen.

3. **Before/after**: Full side-by-side showing manual `build.zig` (~25 lines for one exe + test) vs ZON manifest (~12 lines) + 5-line `build.zig`. Brief commentary: "zbuild eliminates the repetitive wiring. You declare what you want; the compiler generates the build graph."

4. **What zbuild is NOT** (~4 lines): Not a replacement for `build.zig`. It handles the declarative 90% — the static build graph. For conditional logic, platform-specific targets, or custom build steps, write that code in `build.zig` alongside the `configureBuild` call. The escape hatch is always there.

5. **Inspiration** (~3 lines): Cargo (`Cargo.toml`), npm (`package.json`). Unlike those, zbuild doesn't replace the build system — it rides on top of Zig's native build system.

Target: ~80 lines.

- [ ] **Step 2: Commit**

```bash
git add docs/motivation.md
git commit -m "docs: add motivation doc explaining library approach"
```

### Task 4: Write docs/schema.md

**Files:**
- Create: `docs/schema.md`

- [ ] **Step 1: Write the schema reference**

This is the largest doc. Structure:

**Intro paragraph**: Complete reference for zbuild manifest fields added to `build.zig.zon`. Standard Zig fields (`name`, `version`, `fingerprint`, `minimum_zig_version`, `paths`, `description`, `dependencies`) are passed through to the Zig build system as normal. Fields not recognized by zbuild are silently ignored for forward compatibility.

**Sections** (one heading per manifest section, each with a field table):

**`modules`**: Reusable code units registered with the build system.

| Field | Type | Default | Maps to |
|-------|------|---------|---------|
| `root_source_file` | string | — | `Module.CreateOptions.root_source_file` |
| `target` | string | host target | `"native"` or arch-os-abi triple (e.g. `"x86_64-linux-gnu"`) |
| `optimize` | enum literal | project default | `.Debug`, `.ReleaseSafe`, `.ReleaseFast`, `.ReleaseSmall` |
| `imports` | tuple of enum literals/strings | — | `module.addImport()` per entry |
| `link_libraries` | tuple of strings | — | `module.linkLibrary()` — format: `"dep_name"` or `"dep_name:artifact_name"` |
| `include_paths` | tuple of strings | — | `module.addIncludePath()` per entry |
| `private` | bool | `false` | When `true`, module is not exported to `b.modules` |
| `link_libc` | bool | omit | `Module.CreateOptions.link_libc` |
| *(16 more passthrough fields)* | bool/enum | omit | Direct passthrough to `Module.CreateOptions` |

Document the three root_module forms: enum literal (`.mymod` — references a named module), string (`"mymod"` — same), inline struct (full module definition with optional `name` override).

**`executables`**: Build targets that produce executable binaries.

| Field | Type | Default | Maps to |
|-------|------|---------|---------|
| `root_module` | ref or struct | required | See root_module forms above |
| `version` | string | — | Parsed as `SemanticVersion` |
| `linkage` | enum literal | — | `.static` or `.dynamic` |
| `dest_sub_path` | string | — | `InstallArtifact.Options.dest_sub_path` |
| `depends_on` | tuple | — | Step ordering against other artifacts |
| `max_rss`, `use_llvm`, `use_lld` | bool/int | omit | Passthrough |
| `zig_lib_dir` | string | — | LazyPath resolved |
| `win32_manifest` | string | — | LazyPath resolved |

Steps created: `build-exe:<name>`, `run:<name>`.

**`libraries`**: Same fields as executables, plus `linker_allow_shlib_undefined`. Steps: `build-lib:<name>`.

**`objects`**: Subset — `root_module`, passthrough fields, `zig_lib_dir`. No version/linkage/dest_sub_path/win32_manifest. Steps: `build-obj:<name>`.

**`tests`**: `root_module`, `filters` (tuple of strings), passthrough fields, `zig_lib_dir`. Steps: `test:<name>`, `build-test:<name>`, aggregate `test`. CLI: `-D<name>.filters=...` overrides manifest filters.

**`fmts`**:

| Field | Type | Default | Maps to |
|-------|------|---------|---------|
| `paths` | tuple of strings | `&.{}` | `addFmt(.paths)` |
| `exclude_paths` | tuple of strings | `&.{}` | `addFmt(.exclude_paths)` |
| `check` | bool | `false` | `addFmt(.check)` |

Steps: `fmt:<name>`, aggregate `fmt`.

**`runs`**: Dual-form syntax.

Short form: `.myrun = .{ "cmd", "arg1", "arg2" }` — bare tuple → `addSystemCommand`.

Long form:

| Field | Type | Default | Maps to |
|-------|------|---------|---------|
| `cmd` | tuple of strings | required | `addSystemCommand` args |
| `cwd` | string | inherit | `run.setCwd()` — LazyPath resolved |
| `env` | struct | inherit | `run.setEnvironmentVariable()` per field |
| `inherit_stdio` | bool | `false` | `run.stdio = .inherit` when true |
| `stdin` | string | — | `run.setStdIn(.{ .bytes = ... })` |
| `stdin_file` | string | — | `run.setStdIn(.{ .lazy_path = ... })` — mutually exclusive with `stdin` |
| `depends_on` | tuple | — | Step ordering against artifacts |

Steps: `cmd:<name>`.

**`options_modules`**: Configurable build options exposed as importable modules.

| Type string | Zig type | Default type |
|-------------|----------|--------------|
| `"bool"` | `bool` | `bool` |
| `"string"` | `[]const u8` | `[]const u8` |
| `"list"` | `[]const []const u8` | tuple of strings |
| `"enum"` | `[]const u8` | enum literal |
| `"enum_list"` | `[]const []const u8` | tuple of enum literals |
| `"i32"`, `"u64"`, etc. | corresponding int | int |
| `"f32"`, `"f64"`, etc. | corresponding float | float |

Each option: `{ .type = "bool", .default = true, .description = "Enable feature" }`. Access in Zig: `const config = @import("config");` then `config.enable_feature`.

**`dependencies`**: The `args` field forwards comptime arguments to `b.dependency()`. Example: `.mydep = .{ .args = .{ .enable_foo = true } }`.

**LazyPath resolution**: String paths in fields like `root_source_file`, `cwd`, `zig_lib_dir` are resolved via colon syntax:
- `"src/main.zig"` — local file path
- `"dep:path"` — named lazy path from dependency `dep`
- `"dep:wf_name:path"` — file `path` within dependency `dep`'s named WriteFiles step `wf_name`

**Comptime validation**: zbuild validates cross-references at compile time:
- `root_module` enum/string refs must point to a declared module
- `depends_on` refs must point to a declared artifact
- `imports` refs must point to a module, options_module, or dependency
- `stdin` + `stdin_file` on the same run → `@compileError`
- Unknown fields are silently ignored (forward compatibility)

Target: ~300 lines.

- [ ] **Step 2: Commit**

```bash
git add docs/schema.md
git commit -m "docs: add complete ZON schema reference"
```

---

## Chunk 2: Examples

### Task 5: Create examples/simple/

**Files:**
- Create: `examples/simple/build.zig.zon`
- Create: `examples/simple/build.zig`
- Create: `examples/simple/src/main.zig`

- [ ] **Step 1: Write build.zig.zon**

```zig
.{
    .name = .simple_example,
    .version = "0.1.0",
    .fingerprint = 0xaabbccdd00112233,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .description = "A minimal zbuild example",
    .dependencies = .{
        .zbuild = .{ .path = "../.." },
    },
    .executables = .{
        .hello = .{
            .root_module = .{
                .root_source_file = "src/main.zig",
            },
        },
    },
}
```

- [ ] **Step 2: Write build.zig**

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err|
        std.log.err("zbuild: {}", .{err});
}
```

- [ ] **Step 3: Write src/main.zig**

```zig
const std = @import("std");

pub fn main() void {
    std.debug.print("Hello from zbuild!\n", .{});
}
```

- [ ] **Step 4: Verify it compiles**

```bash
cd examples/simple && zig build
```

Expected: builds successfully, produces `zig-out/bin/hello`.

- [ ] **Step 5: Verify it runs**

```bash
cd examples/simple && zig build run:hello
```

Expected: prints "Hello from zbuild!"

- [ ] **Step 6: Verify help step works**

```bash
cd examples/simple && zig build help
```

Expected: prints project info including "simple_example v0.1.0"

- [ ] **Step 7: Commit**

```bash
git add examples/simple/
git commit -m "docs: add simple example project"
```

### Task 6: Create examples/full/

**Files:**
- Create: `examples/full/build.zig.zon`
- Create: `examples/full/build.zig`
- Create: `examples/full/src/lib.zig`
- Create: `examples/full/src/main.zig`
- Create: `examples/full/src/test.zig`

- [ ] **Step 1: Write src/lib.zig**

```zig
/// A simple math module to demonstrate zbuild's module system.
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn multiply(a: i32, b: i32) i32 {
    return a * b;
}
```

- [ ] **Step 2: Write src/main.zig**

```zig
const std = @import("std");
const math = @import("math");
const config = @import("config");

pub fn main() void {
    const result = math.add(2, 3);
    std.debug.print("2 + 3 = {d}\n", .{result});
    if (config.verbose)
        std.debug.print("(verbose mode enabled)\n", .{});
}
```

- [ ] **Step 3: Write src/test.zig**

```zig
const std = @import("std");
const math = @import("math");

test "add" {
    try std.testing.expectEqual(@as(i32, 5), math.add(2, 3));
    try std.testing.expectEqual(@as(i32, 0), math.add(-1, 1));
}

test "multiply" {
    try std.testing.expectEqual(@as(i32, 6), math.multiply(2, 3));
    try std.testing.expectEqual(@as(i32, 0), math.multiply(0, 42));
}
```

- [ ] **Step 4: Write build.zig.zon**

```zig
.{
    .name = .full_example,
    .version = "1.0.0",
    .fingerprint = 0x1122334455667788,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .description = "A comprehensive zbuild example showcasing all features",

    .dependencies = .{
        .zbuild = .{ .path = "../.." },
        // To add an external dependency:
        // .zlib = .{
        //     .url = "https://github.com/example/zlib-zig/archive/v1.0.0.tar.gz",
        //     .hash = "...",
        //     .args = .{ .shared = true },  // forwarded to b.dependency() at comptime
        // },
    },

    // --- Modules: reusable code units ---
    // Modules are registered with the build system and can be referenced
    // by name from executables, libraries, and tests via root_module.
    .modules = .{
        .math = .{
            .root_source_file = "src/lib.zig",
        },
    },

    // --- Executables ---
    // root_module can be an enum literal (.math) referencing a named module,
    // a string ("math"), or an inline struct with a full module definition.
    .executables = .{
        .demo = .{
            .root_module = .{
                .root_source_file = "src/main.zig",
                .imports = .{ .math, .config },
            },
        },
    },

    // --- Libraries ---
    .libraries = .{
        .mathlib = .{
            .root_module = .math,
        },
    },

    // --- Tests ---
    // Each test gets a test:<name> step and joins the aggregate "test" step.
    // Use -D<name>.filters=... to filter specific tests from the CLI.
    .tests = .{
        .unit = .{
            .root_module = .{
                .root_source_file = "src/test.zig",
                .imports = .{.math},
            },
        },
    },

    // --- Fmts ---
    // Wraps zig fmt. Each entry gets fmt:<name> and joins aggregate "fmt".
    .fmts = .{
        .src = .{
            .paths = .{"src"},
        },
    },

    // --- Runs ---
    // Short form: bare tuple of strings.
    // Long form: struct with cmd + optional cwd, env, depends_on, etc.
    .runs = .{
        // Short form: bare tuple of strings
        .@"echo-version" = .{ "echo", "full_example v1.0.0" },
        // Long form: struct with cmd + options
        .greet = .{
            .cmd = .{ "echo", "hello from zbuild" },
            .env = .{ .GREETING = "hello" },
            .inherit_stdio = true,
        },
    },

    // --- Options modules ---
    // Creates an importable module with build-time options.
    // Access in Zig: const config = @import("config");
    .options_modules = .{
        .config = .{
            .verbose = .{
                .type = "bool",
                .default = false,
                .description = "Enable verbose output",
            },
        },
    },
}
```

- [ ] **Step 5: Write build.zig**

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    zbuild.configureBuild(b, @import("build.zig.zon"), .{
        .help_step = "info",
    }) catch |err|
        std.log.err("zbuild: {}", .{err});
}
```

- [ ] **Step 6: Verify it compiles**

```bash
cd examples/full && zig build
```

Expected: builds successfully.

- [ ] **Step 7: Verify executable runs**

```bash
cd examples/full && zig build run:demo
```

Expected: prints "2 + 3 = 5"

- [ ] **Step 8: Verify tests pass**

```bash
cd examples/full && zig build test
```

Expected: tests pass.

- [ ] **Step 9: Verify custom help step**

```bash
cd examples/full && zig build info
```

Expected: prints project info with "full_example v1.0.0", lists modules, executables, libraries, tests, runs, options, etc.

- [ ] **Step 10: Verify runs**

```bash
cd examples/full && zig build cmd:echo-version
```

Expected: prints "full_example v1.0.0"

- [ ] **Step 11: Commit**

```bash
git add examples/full/
git commit -m "docs: add full example project showcasing all features"
```

### Task 7: Delete docs/superpowers/

**Files:**
- Delete: `docs/superpowers/` (entire directory — specs and plans from development)

**Note:** This is last because it contains the plan and spec used during implementation.

- [ ] **Step 1: Remove the directory**

```bash
rm -rf docs/superpowers/
```

- [ ] **Step 2: Commit**

```bash
git add -u
git commit -m "docs: remove internal superpowers working documents"
```
