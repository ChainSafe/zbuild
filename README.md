# zbuild

Declarative build configuration for Zig projects.

## What is zbuild?

zbuild is a Zig library that configures your entire `std.Build` graph from the fields in your `build.zig.zon`. Using Zig 0.14's `@import("build.zig.zon")`, the compiler reads your manifest as a typed struct at comptime — no runtime parsing, no codegen, no intermediate representation. The build graph is generated directly by the compiler.

zbuild works alongside manual `build.zig` code. Use it for the declarative 90%, and write Zig for the rest.

## Before and after

Without zbuild, a single executable with install, run, and test steps requires ~25 lines of `build.zig`:

```zig
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.modules.put(b.dupe("myapp"), module) catch @panic("OOM");

    const exe = b.addExecutable(.{ .name = "myapp", .root_module = module });
    const install = b.addInstallArtifact(exe, .{});
    b.step("build-exe:myapp", "Install myapp").dependOn(&install.step);
    b.getInstallStep().dependOn(&install.step);

    const run = b.addRunArtifact(exe);
    if (b.args) |args| run.addArgs(args);
    b.step("run:myapp", "Run myapp").dependOn(&run.step);

    const test_exe = b.addTest(.{ .name = "myapp", .root_module = module });
    const run_test = b.addRunArtifact(test_exe);
    b.step("test:myapp", "Run myapp tests").dependOn(&run_test.step);
}
```

With zbuild, the same thing is declared in `build.zig.zon`:

```zig
.executables = .{
    .myapp = .{
        .root_module = .{
            .root_source_file = "src/main.zig",
        },
    },
},
.tests = .{
    .myapp = .{
        .root_module = .{
            .root_source_file = "src/main.zig",
        },
    },
},
```

And your entire `build.zig` becomes:

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err|
        std.log.err("zbuild: {}", .{err});
}
```

## Quickstart

**1. Add zbuild as a dependency:**

```bash
zig fetch --save=zbuild <zbuild-url-or-path>
```

**2. Create `build.zig`:**

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err|
        std.log.err("zbuild: {}", .{err});
}
```

**3. Add zbuild fields to your `build.zig.zon`:**

```zig
.{
    .name = .myproject,
    .version = "0.1.0",
    .fingerprint = 0xaabbccdd00112233,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .dependencies = .{
        .zbuild = .{ .path = "path/to/zbuild" },
    },
    .executables = .{
        .myapp = .{
            .root_module = .{
                .root_source_file = "src/main.zig",
            },
        },
    },
}
```

**4. Build and run:**

```bash
zig build              # build all artifacts
zig build run:myapp    # run the executable
zig build test         # run all tests
zig build help         # show project build info
```

## Features

- **Modules** — reusable code units with imports, include paths, and library linking
- **Executables** — with automatic install and run steps
- **Libraries** — static/dynamic with version and linkage control
- **Objects** — compiled object files
- **Tests** — with filters and an aggregate `test` step
- **Fmts** — `zig fmt` wrappers with path and exclusion control
- **Runs** — system commands in short form (tuple) or long form (struct with env, cwd, stdin, depends_on)
- **Options modules** — build-time options importable from Zig source code
- **Dependency args** — forward comptime arguments to `b.dependency()` calls
- **Comptime validation** — typos in module/artifact/import references become compile errors
- **Built-in help step** — `zig build help` shows a formatted overview of your project (reads `name`, `version`, `description` from your manifest)

## Documentation

- **[Schema Reference](docs/schema.md)** — complete field-by-field reference for all zbuild manifest sections
- **[Motivation](docs/motivation.md)** — why zbuild exists and how it works
- **[Simple Example](examples/simple/)** — minimal project, one executable
- **[Full Example](examples/full/)** — all features: modules, tests, runs, options, fmts

## Requirements

Zig 0.14+

## License

MIT
