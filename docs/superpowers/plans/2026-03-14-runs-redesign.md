# Runs Field Redesign Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the runtime string-splitting `runs` implementation with a comptime dual-form syntax (bare tuple or struct with `cmd` + options).

**Architecture:** Detect short form (bare tuple) vs long form (struct with `cmd` field) at comptime via `@hasField`. Convert args via `toStringSlice`, apply optional fields (`cwd`, `env`, `inherit_stdio`, `stdin`, `stdin_file`, `depends_on`) using `@hasField` checks. Add comptime cross-reference validation for `depends_on` and mutual exclusion for `stdin`/`stdin_file`.

**Tech Stack:** Zig 0.14, comptime metaprogramming, `std.Build.Step.Run`

---

## Chunk 1: Implementation

### Task 1: Add runs validation to `validateManifest`

**Files:**
- Modify: `src/build_runner.zig:118-162` (inside `validateManifest`)

- [ ] **Step 1: Add the runs validation block**

Add after the existing imports validation block (after line 161, before the closing `}`):

```zig
    // Validate runs fields
    if (@hasField(@TypeOf(manifest), "runs")) {
        inline for (@typeInfo(@TypeOf(manifest.runs)).@"struct".fields) |field| {
            const run = @field(manifest.runs, field.name);
            if (@hasField(@TypeOf(run), "cmd")) {
                // Long form — validate depends_on and stdin/stdin_file exclusion
                if (@hasField(@TypeOf(run), "depends_on")) {
                    validateDependsOn(manifest, run.depends_on, "runs", field.name);
                }
                if (@hasField(@TypeOf(run), "stdin") and @hasField(@TypeOf(run), "stdin_file")) {
                    @compileError("runs '" ++ field.name ++ "': stdin and stdin_file are mutually exclusive");
                }
            }
        }
    }
```

- [ ] **Step 2: Run tests to verify nothing broke**

Run: `zig build test`
Expected: All 13 tests pass (no runs validation exercised yet, just structural addition).

- [ ] **Step 3: Commit**

```bash
git add src/build_runner.zig
git commit -m "feat: add comptime validation for runs fields"
```

### Task 2: Rewrite `createRun` with dual-form support

**Files:**
- Modify: `src/build_runner.zig:485-499` (replace `createRun`)

- [ ] **Step 1: Replace `createRun` implementation**

Replace the entire `createRun` function (lines 485-499) with:

```zig
    fn createRun(self: *BuildRunner, comptime name: []const u8, comptime cmd: anytype) void {
        const is_long_form = @hasField(@TypeOf(cmd), "cmd");
        const args_tuple = if (is_long_form) cmd.cmd else cmd;
        const run = self.b.addSystemCommand(comptime toStringSlice(args_tuple));

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

        // Wire depends_on
        if (is_long_form and @hasField(@TypeOf(cmd), "depends_on")) {
            inline for (@typeInfo(@TypeOf(cmd.depends_on)).@"struct".fields) |field| {
                const dep_name = comptime toComptimeString(@field(cmd.depends_on, field.name));
                if (self.install_steps.get(dep_name)) |dep_step| {
                    run.step.dependOn(dep_step);
                } else {
                    std.log.warn("zbuild: runs '{s}' depends_on references unknown artifact '{s}'", .{ name, dep_name });
                }
            }
        }
    }
```

- [ ] **Step 2: Build to verify compilation**

Run: `zig build test`
Expected: All 13 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/build_runner.zig
git commit -m "feat: rewrite createRun with dual-form comptime support"
```

### Task 3: Add tests

**Files:**
- Modify: `src/build_runner.zig` (test section at end of file)

**Note:** We cannot test the full `createRun` in unit tests because it requires a real `std.Build` instance. We can test comptime validation paths. The `stdin`/`stdin_file` mutual exclusion produces a `@compileError`, which Zig test blocks cannot catch — this is a documented constraint, not a coverage gap.

**Breaking change:** The step prefix changes from `run:<name>` to `cmd:<name>`. Anyone using `zig build run:<name>` for system-command runs will need to use `cmd:<name>` instead. Executable `run:<name>` steps are unaffected.

- [ ] **Step 1: Add validation tests for runs**

Add after the existing `validateManifest accepts unknown top-level fields` test:

```zig
test "validateManifest accepts short-form runs" {
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.14.0",
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
        .minimum_zig_version = "0.14.0",
        .paths = .{"."},
        .executables = .{
            .myapp = .{ .root_module = .{ .root_source_file = "src/main.zig" } },
        },
        .runs = .{
            .deploy = .{
                .cmd = .{ "./deploy.sh" },
                .cwd = "scripts",
                .env = .{ .NODE_ENV = "production" },
                .depends_on = .{.myapp},
            },
        },
    });
}

test "validateManifest accepts run and executable with same name" {
    // cmd:<name> prefix for runs vs run:<name> for executables avoids collision
    comptime validateManifest(.{
        .name = .myproject,
        .version = "0.1.0",
        .fingerprint = 0x1234,
        .minimum_zig_version = "0.14.0",
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
        .minimum_zig_version = "0.14.0",
        .paths = .{"."},
        .runs = .{
            .deploy = .{
                .cmd = .{ "./deploy.sh" },
                .some_future_field = "ignored",
            },
        },
    });
}
```

- [ ] **Step 2: Run tests**

Run: `zig build test`
Expected: All 17 tests pass.

- [ ] **Step 3: Commit**

```bash
git add src/build_runner.zig
git commit -m "test: add validation tests for runs dual-form syntax"
```
