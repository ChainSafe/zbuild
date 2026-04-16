# ZON Schema Reference

This is the complete reference for zbuild's manifest fields. These fields are added to your standard `build.zig.zon` alongside Zig's own fields (`name`, `version`, `fingerprint`, `minimum_zig_version`, `paths`, `description`, `dependencies`).

Fields not recognized by zbuild are silently ignored, ensuring forward compatibility with future Zig versions.

## `modules`

Reusable code units registered with the build system. Modules can be referenced by name from executables, libraries, and tests via their `root_module` field.

```zig
.modules = .{
    .core = .{
        .root_source_file = "src/core.zig",
        .imports = .{ .utils, .zlib },
        .link_libc = true,
    },
},
```

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root_source_file` | string | — | Path to the root source file |
| `target` | string | host | `"native"` or arch-os-abi triple (e.g. `"x86_64-linux-gnu"`) |
| `optimize` | enum literal | project default | `.Debug`, `.ReleaseSafe`, `.ReleaseFast`, `.ReleaseSmall` |
| `imports` | tuple | — | Modules, options_modules, or dependencies to import |
| `link_libraries` | tuple of strings | — | Dependency library artifacts to link (see below) |
| `include_paths` | tuple of strings | — | Include paths for C/C++ headers |
| `private` | bool | `false` | When `true`, not exported to `b.modules` |

### Passthrough fields

These map directly to `std.Build.Module.CreateOptions`:

`link_libc`, `link_libcpp`, `single_threaded`, `strip`, `unwind_tables`, `dwarf_format`, `code_model`, `error_tracing`, `omit_frame_pointer`, `pic`, `red_zone`, `sanitize_c`, `sanitize_thread`, `stack_check`, `stack_protector`, `fuzz`, `valgrind`

### `link_libraries` syntax

Format: `"dep_name"` or `"dep_name:artifact_name"`. Resolves a library artifact from a declared dependency. This is distinct from LazyPath resolution.

```zig
.link_libraries = .{ "zlib", "openssl:libssl" },
```

### `imports` syntax

Import entries can reference:
- **Named modules:** `.core` or `"core"`
- **Options modules:** `.config`
- **Dependencies:** `.zlib` (imports the dependency's default module)
- **Dependency sub-modules:** `"zlib:zlib"` (imports a specific module from a dependency)
- **Manual modules:** bare strings like `"shared"` resolved from `b.addModule(...)` before `configureBuild`

## `executables`

Build targets that produce executable binaries. Each entry creates `build-exe:<name>` (install) and `run:<name>` (execute) steps.

```zig
.executables = .{
    .myapp = .{
        .root_module = .core,          // reference a named module
        .version = "1.0.0",
    },
},
```

### Root module forms

The `root_module` field accepts three forms:

1. **Enum literal** — references a named zbuild module: `.root_module = .core`
2. **String** — references a named zbuild module or a manual `b.addModule(...)` module registered before `configureBuild`: `.root_module = "core"`
3. **Inline struct** — defines the module inline, with an optional `name` override:
   ```zig
   .root_module = .{
       .root_source_file = "src/main.zig",
       .imports = .{ .core, .config },
       .name = "custom_name",  // optional: internal inline-module name used for import wiring
   },
   ```

Inline root modules are not importable targets in the manifest. If provided, `root_module.name` must be unique across all inline root modules and must not collide with a named module.

### Fields

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root_module` | ref or struct | required | See root module forms above |
| `version` | string | — | Semantic version (e.g. `"1.0.0"`) |
| `linkage` | enum literal | — | `.static` or `.dynamic` |
| `dest_sub_path` | string | — | Custom install subdirectory |
| `depends_on` | tuple | — | Steps that must complete first (artifact install step or exact top-level step name) |
| `max_rss` | int | — | Maximum RSS for the build step |
| `use_llvm` | bool | — | Use LLVM backend |
| `use_lld` | bool | — | Use LLD linker |
| `zig_lib_dir` | string | — | Custom Zig lib directory (LazyPath resolved) |
| `win32_manifest` | string | — | Win32 manifest file (LazyPath resolved) |

## `libraries`

Same fields as executables, plus `linker_allow_shlib_undefined`. Each entry creates a `build-lib:<name>` step.

```zig
.libraries = .{
    .mylib = .{
        .root_module = .core,
        .linkage = .static,
        .version = "0.1.0",
    },
},
```

| Additional Field | Type | Default | Description |
|------------------|------|---------|-------------|
| `linker_allow_shlib_undefined` | bool | — | Allow undefined symbols in shared libs |

## `objects`

Compiled object files. Simpler subset — no `version`, `linkage`, `dest_sub_path`, or `win32_manifest`. Each entry creates a `build-obj:<name>` step.

```zig
.objects = .{
    .myobj = .{
        .root_module = .core,
    },
},
```

Supported fields: `root_module`, `max_rss`, `use_llvm`, `use_lld`, `zig_lib_dir`.

## `tests`

Test targets. Each entry creates `test:<name>` (run) and `build-test:<name>` (install) steps. All tests also join the aggregate `test` step.

```zig
.tests = .{
    .unit = .{
        .root_module = .{
            .root_source_file = "src/test.zig",
            .imports = .{.core},
        },
        .filters = .{ "specific_test_name" },
    },
},
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `root_module` | ref or struct | required | See root module forms |
| `filters` | tuple of strings | — | Test name filters |
| `max_rss` | int | — | Maximum RSS |
| `use_llvm` | bool | — | Use LLVM backend |
| `use_lld` | bool | — | Use LLD linker |
| `zig_lib_dir` | string | — | Custom Zig lib directory |

Filters can be overridden from the CLI: `-D<test_name>.filters=specific_test`.

## `fmts`

Wraps `zig fmt`. Each entry creates `fmt:<name>` and joins the aggregate `fmt` step.

```zig
.fmts = .{
    .src = .{
        .paths = .{ "src", "tests" },
        .exclude_paths = .{ "src/generated" },
        .check = true,
    },
},
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `paths` | tuple of strings | `&.{}` | Paths to format |
| `exclude_paths` | tuple of strings | `&.{}` | Paths to exclude |
| `check` | bool | `false` | Check formatting without modifying |

## `runs`

System commands. Each entry creates a `cmd:<name>` step. Two syntax forms:

### Short form

Bare tuple of strings — becomes `addSystemCommand` args:

```zig
.runs = .{
    .fmt = .{ "zig", "fmt", "src" },
},
```

### Long form

Struct with `cmd` plus optional fields:

```zig
.runs = .{
    .deploy = .{
        .cmd = .{ "./scripts/deploy.sh", "--env", "staging" },
        .cwd = "scripts",
        .env = .{ .NODE_ENV = "production" },
        .inherit_stdio = true,
        .depends_on = .{.myapp},
    },
},
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `cmd` | tuple of strings | required | Command and arguments |
| `cwd` | string | inherit | Working directory (LazyPath resolved) |
| `env` | struct | inherit | Environment variables (field name = key, value = value) |
| `inherit_stdio` | bool | `false` | Forward stdio to terminal |
| `stdin` | string | — | Bytes piped to stdin |
| `stdin_file` | string | — | File piped to stdin (LazyPath resolved) |
| `depends_on` | tuple | — | Steps that must complete first (artifact install step or exact top-level step name) |

`stdin` and `stdin_file` are mutually exclusive.

`depends_on` accepts both enum literals and strings:
- **Enum literals:** `.myapp` resolves to the install step for artifact `myapp`
- **Strings:** `"test:unit"`, `"fmt"`, or `"gen:prep"` resolve to a top-level step by exact name
- **Legacy bare artifact strings:** `"myapp"` still resolve to the artifact install step if an artifact with that name exists

Manual top-level steps must be created with `b.step(...)` before calling `configureBuild`.

## `options_modules`

Configurable build options exposed as importable Zig modules. Users set values via `-D<module>.<option>=<value>`.

```zig
.options_modules = .{
    .config = .{
        .verbose = .{
            .type = .bool,
            .default = false,
            .description = "Enable verbose output",
        },
        .log_level = .{
            .type = .@"enum",
            .values = .{ .debug, .info, .warn },
            .default = .info,
            .description = "Log level",
        },
        .output_dir = .{
            .type = .string,
            .description = "Optional output directory",
        },
    },
},
```

Access in Zig source:

```zig
const config = @import("config");

if (config.output_dir) |dir| {
    _ = dir;
}

switch (config.log_level) {
    .debug => {},
    .info => {},
    .warn => {},
}
```

### Option fields

| Field | Type | Description |
|-------|------|-------------|
| `type` | enum literal or string | Required. See supported types below |
| `default` | varies | Default value (type must match) |
| `values` | tuple | Required for `.@"enum"` and `.enum_list`; must be non-empty |
| `type_name` | string | Optional for enum kinds. Defaults to PascalCase of the option name |
| `description` | string | Shown in `zig build --help` |

### Supported types

The `type` field accepts either enum literals (`.bool`) or strings (`"bool"`). Enum literals are preferred.

If an option has a `default`, the generated field type is `T`. Without a `default`, the generated field type is `?T`.

| Type | Generated Zig type | Default type |
|------|---------------------|--------------|
| `.bool` | `bool` / `?bool` | `bool` |
| `.string` | `[]const u8` / `?[]const u8` | `[]const u8` |
| `.list` | `[]const []const u8` / `?[]const []const u8` | tuple of strings |
| `.@"enum"` | `<TypeName>` / `?<TypeName>` | enum literal or string |
| `.enum_list` | `[]const <TypeName>` / `?[]const <TypeName>` | tuple of enum literals or strings |
| `.i8` .. `.u64`, `.isize`, `.usize` | corresponding int / optional int | int literal |
| `.c_int`, `.c_uint`, etc. | corresponding C int / optional C int | int literal |
| `.f16` .. `.f128`, `.c_longdouble` | corresponding float / optional float | float literal |

Enum kinds generate a public Zig enum type in the imported module:

```zig
pub const LogLevel = enum {
    debug,
    info,
    warn,
};

pub const log_level: LogLevel = .info;
```

## `dependencies`

Standard Zig dependencies declared in `build.zig.zon`. zbuild adds support for an `args` field to forward comptime arguments:

```zig
.dependencies = .{
    .zlib = .{
        .url = "https://example.com/zlib.tar.gz",
        .hash = "...",
        .args = .{ .shared = true },  // forwarded to b.dependency("zlib", .{ .shared = true })
    },
},
```

Without `args`, dependencies are resolved with `b.dependency(name, .{})`.

## LazyPath resolution

String paths in fields like `root_source_file`, `cwd`, `zig_lib_dir`, and `include_paths` are resolved via colon-delimited syntax:

| Format | Resolves to |
|--------|-------------|
| `"src/main.zig"` | Local file: `b.path("src/main.zig")` |
| `"dep:path"` | Named lazy path from dependency `dep` |
| `"dep:wf_name:path"` | File `path` within dependency `dep`'s named WriteFiles step `wf_name` |

**Note:** Avoid naming dependencies the same as local directories (e.g., `src`). A path like `"src:file.zig"` would resolve as a dependency reference rather than a local path.

## Validation

zbuild validates in two phases:

- **Compile time (`@compileError`)** for local graph structure and manifest syntax
- **Configure time (hard build failure before graph execution)** for dependency exports that are only knowable after `b.dependency(...)` loads the dependency build graph

Compile-time validation covers:

- `root_module` enum references must point to a declared module; bare string refs may defer to manual `b.addModule(...)` modules
- `depends_on` enum references and manifest-owned step names; external manual steps are resolved later from `b.top_level_steps`
- `imports` syntax, local/dependency references, and dependency base names; bare string imports may defer to manual `b.addModule(...)` modules
- `link_libraries` syntax and dependency base names
- dependency-backed LazyPath syntax (`"dep:path"` / `"dep:wf_name:path"`)
- target strings on modules
- `stdin` and `stdin_file` on the same run are mutually exclusive

Configure-time validation covers:

- manual modules referenced from `root_module` and `imports`
- manual or aggregate top-level steps referenced from `depends_on`
- dependency default modules and sub-modules referenced from `imports`
- dependency artifacts referenced from `link_libraries`
- dependency named lazy paths and named `WriteFile` steps referenced from LazyPath fields

These configure-time failures stop `zig build` before the graph runs; they do not degrade into stdlib panics.

Unknown fields at any level are silently ignored for forward compatibility with future Zig versions.

## `configureBuild` options

The third argument to `configureBuild` is a comptime `Options` struct:

```zig
zbuild.configureBuild(b, @import("build.zig.zon"), .{
    .help_step = "info",  // default: "help", null to disable
}) catch |err| ...;
```

| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `help_step` | `?[]const u8` | `"help"` | Step name for the help command, or `null` to disable |

The help step prints a formatted overview of your project, reading `name`, `version`, and `description` from the standard `build.zig.zon` metadata.
