# zbuild

Declarative `std.Build` graphs generated from `build.zig.zon` at comptime.

zbuild reads `@import("build.zig.zon")` as a typed value and turns it into normal `std.Build` calls. There is no runtime parser, and the graph is generated directly inside the build, not by an external codegen phase. It is a library that sits on top of Zig's native build graph.

## Start Here

- Want to try it immediately: use the quickstart below.
- Want the mental model first: read [Conceptual Model](docs/concepts.md).
- Want exact field-by-field details: read [Schema Reference](docs/schema.md).
- Want the rationale and tradeoffs: read [Why zbuild?](docs/motivation.md).

## Quickstart

### 1. Add zbuild as a dependency

```bash
zig fetch --save=zbuild <zbuild-url-or-path>
```

That writes the `.dependencies.zbuild` entry for you.

### 2. Create `build.zig`

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = try zbuild.configureBuild(b, @import("build.zig.zon"), .{});
}
```

### 3. Add zbuild-owned fields to `build.zig.zon`

```zig
.executables = .{
    .myapp = .{
        .root_module = .{
            .root_source_file = "src/main.zig",
        },
    },
},
```

Assume the rest of `build.zig.zon` is the normal Zig package metadata from your project or `zig init`.

### 4. Build it

```bash
zig build
zig build run:myapp
zig build help
```

### 5. Expand from there

Once the first executable works, add modules, tests, runs, fmts, options modules, or libraries as needed. The [simple example](examples/simple/) shows the minimal shape. The [full example](examples/full/) shows most of the library in one place.

## What zbuild gives you

- `modules` for reusable Zig modules with imports, include paths, and dependency libraries
- `executables`, `libraries`, and `objects`
- `tests` with per-test steps and an aggregate `test` step
- `fmts` with per-target steps and an aggregate `fmt` step
- `runs` for arbitrary system commands
- `aliases` for named aggregate steps such as `check`, `ci`, or `release`
- `options_modules` that become importable Zig config modules and `-Dmodule.option` CLI flags
- comptime dependency args forwarded to `b.dependency(...)`
- a built-in help step (`help` by default, configurable via `Options.help_step`)
- two-phase validation so local graph mistakes fail early

## First Mental Model

zbuild becomes easy to use once you keep three rules in your head:

1. `build.zig.zon` declares graph nodes.
   `modules`, `executables`, `libraries`, `tests`, `runs`, `fmts`, and `aliases` each map to a different kind of `std.Build` node or step.

2. Ownership is encoded in syntax.
   Enum literals like `.core`, `.config`, and `.myapp` mean "this belongs to the zbuild-owned graph".
   Bare strings like `"shared"` and `"gen:prep"` mean "this is manual `build.zig` state registered before `configureBuild`".

3. Validation happens in two phases.
   Local manifest structure and manifest-owned refs fail at comptime.
   Manual refs and dependency exports fail during configure, after zbuild can actually inspect them.

If you want the full model, including namespace rules and why those syntax splits exist, read [docs/concepts.md](docs/concepts.md).

## Working With Manual `build.zig` Code

zbuild does not replace `build.zig`. It owns the declarative 90%, and you keep Zig for the rest.

Register manual modules or steps before `configureBuild`:

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) !void {
    _ = b.addModule("shared", .{
        .root_source_file = b.path("src/shared.zig"),
        .target = b.resolveTargetQuery(.{}),
        .optimize = .Debug,
    });
    _ = b.step("gen:prep", "manual prep step");

    _ = try zbuild.configureBuild(b, @import("build.zig.zon"), .{});
}
```

Then reference those manual nodes from the manifest with bare strings:

```zig
.executables = .{
    .app = .{
        .root_module = "shared",
    },
},
.runs = .{
    .demo = .{
        .cmd = .{ "echo", "ok" },
        .depends_on = .{ "gen:prep" },
    },
},
```

## Documentation Map

- [Conceptual Model](docs/concepts.md): the bottom-up explanation of how the graph, namespaces, and validation fit together
- [Schema Reference](docs/schema.md): exact field types, syntax, and generated step names
- [Why zbuild?](docs/motivation.md): the problem it solves and the design constraints it follows
- [Simple Example](examples/simple/): the smallest useful project
- [Full Example](examples/full/): modules, tests, runs, fmts, and options modules together

## Requirements

Zig `0.16.0+`

## License

MIT
