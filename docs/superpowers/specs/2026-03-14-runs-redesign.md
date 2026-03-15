# Runs Field Redesign

## Problem

The current `runs` implementation accepts a single string per command and splits it on spaces at runtime (`std.mem.splitScalar`). This is:

- **Fragile** — arguments with spaces are impossible to express
- **Inconsistent** — the rest of the manifest is comptime-native tuples/structs, but runs does runtime string parsing
- **Limited** — no way to set environment variables, working directory, stdin, stdio mode, or step ordering

## Design

### Dual-form ZON syntax

**Short form** — bare tuple of strings for simple commands:

```zig
.runs = .{
    .fmt = .{ "zig", "fmt", "src" },
    .check = .{ "zig", "build", "test" },
},
```

**Long form** — struct with `cmd` plus optional configuration fields:

```zig
.runs = .{
    .deploy = .{
        .cmd = .{ "./scripts/deploy.sh", "--env", "staging" },
        .cwd = "scripts",
        .env = .{
            .NODE_ENV = "production",
            .VERBOSE = "1",
        },
        .inherit_stdio = true,
        .stdin = "input data here",
        .depends_on = .{ .mylib },
    },
},
```

### Form detection

`@hasField(@TypeOf(val), "cmd")` distinguishes long form (struct with `cmd` field) from short form (bare tuple).

### Long form fields

| Field | Type | Default | Maps to |
|-------|------|---------|---------|
| `cmd` | tuple of strings | required | `addSystemCommand` args via `toStringSlice` |
| `cwd` | string | omitted (inherit) | `run.setCwd(resolveLazyPath(...))` |
| `env` | struct of key=value strings | omitted (inherit) | `run.setEnvironmentVariable` per field |
| `inherit_stdio` | bool | `false` | `run.stdio = .inherit` when true |
| `stdin` | string | omitted | `run.setStdIn(.{ .bytes = stdin })` — ZON string passes directly as `[]const u8` |
| `stdin_file` | string (path) | omitted | `run.setStdIn(.{ .lazy_path = resolveLazyPath(...) })` |
| `depends_on` | tuple of enum literals | omitted | `run.step.dependOn` on named artifact steps |

### Constraints

- `stdin` and `stdin_file` are mutually exclusive. Both present → `@compileError`.
- `depends_on` entries must reference declared artifacts (executables, libraries, objects). Invalid references → `@compileError` via cross-reference validation.
- Run names must not collide with executable names, since executables use `run:<name>` steps. Runs use a distinct `cmd:<name>` step prefix to avoid this.

## Implementation

### `createRun` rewrite

Replace the runtime string-split implementation with comptime-aware dual-form dispatch:

1. Detect form via `@hasField(@TypeOf(cmd), "cmd")`
2. Extract args tuple (from `cmd.cmd` or `cmd` directly)
3. Convert to slice via `comptime toStringSlice(args_tuple)` and pass to `addSystemCommand`
4. Apply optional long-form fields when present using `@hasField` checks
5. Create the `cmd:<name>` top-level step (distinct from `run:<name>` used by executables)
6. Wire `depends_on` inside `createRun` itself: look up artifacts from `self.install_steps`, call `run.step.dependOn`. Use warn-and-skip pattern (consistent with `wireDependsOnList`) for runtime lookup misses.

`createRun` signature stays `void` (no error return), consistent with the existing pattern.

### Validation

Add a new validation block in `validateManifest` specifically for runs (separate from the artifact validation, since runs don't have `root_module`):

- Iterate `manifest.runs` fields
- For long-form entries (`@hasField("cmd")`): validate `depends_on` references against declared artifacts, check `stdin`/`stdin_file` mutual exclusion
- Short-form entries: no validation needed (just a tuple of strings)

### Error handling

- Invalid cross-references: `@compileError` with descriptive message (comptime)
- `stdin` + `stdin_file` conflict: `@compileError("runs '<name>': stdin and stdin_file are mutually exclusive")`
- Allocation failures: `@panic("OOM")` (consistent with rest of codebase)

## Testing

- Short form: tuple of strings creates system command step
- Long form: struct with `cmd` + `env` + `cwd` applies all options
- Validation: `depends_on` referencing unknown artifact → compile error (documented constraint, not testable in `test` blocks)
- `stdin`/`stdin_file` mutual exclusion → compile error (documented constraint)
- Unknown fields in a run struct are silently ignored (consistent with other sections). Conflicting known fields (`stdin` + `stdin_file`) produce a `@compileError`.
