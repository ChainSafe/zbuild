# Why zbuild?

## The problem

Zig's build system is powerful — it's a full programming environment written in Zig itself. But that power comes with verbosity. Adding a single executable with install, run, and test steps requires ~25 lines of boilerplate. Multiply by N targets, wire in dependencies and modules, and the `build.zig` file becomes a maintenance burden.

For newcomers, `build.zig` is one of the steepest parts of learning Zig. The build API is large, the patterns are repetitive, and small mistakes produce confusing errors.

## The insight

Zig's `@import("build.zig.zon")` gives comptime access to the project manifest as a typed anonymous struct. This changes everything:

- **The compiler is the parser.** No runtime ZON parsing, no custom IR, no serialization.
- **The type system is the schema.** Invalid field types are caught by the compiler.
- **Validation splits cleanly by what is actually knowable.** Local manifest structure fails at comptime; dependency exports are validated immediately after dependency loading, before the build graph runs.
- **`inline for` over struct fields** generates specialized code per manifest entry. Zero runtime overhead.

## Before and after

A typical `build.zig` for one executable with tests:

```zig
const std = @import("std");
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("myapp", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

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

With zbuild, the same thing is declared in `build.zig.zon` alongside your normal project metadata:

```zig
.executables = .{
    .myapp = .{
        .root_module = .{ .root_source_file = "src/main.zig" },
    },
},
.tests = .{
    .myapp = .{
        .root_module = .{ .root_source_file = "src/main.zig" },
    },
},
```

And `build.zig` becomes:

```zig
const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    zbuild.configureBuild(b, @import("build.zig.zon"), .{}) catch |err|
        std.log.err("zbuild: {}", .{err});
}
```

zbuild eliminates the repetitive wiring. You declare what you want; the compiler generates the build graph.

## What zbuild is NOT

zbuild is not a replacement for `build.zig`. It handles the declarative 90% — the static build graph that most projects need. For conditional logic, platform-specific targets, or custom build steps, write that code in `build.zig` alongside the `configureBuild` call. Since zbuild takes `*std.Build` and returns, you can do anything before or after it. If the manifest needs to reference a manual module or top-level step, use an explicit manifest ref like `.{ .external_module = "shared" }` or `.{ .external_step = "gen:prep" }`, and create it before calling `configureBuild`.

The escape hatch is always there.

## Inspiration

zbuild draws from Cargo (`Cargo.toml`) and npm (`package.json`) — tools that let developers declare what to build rather than how to build it. Unlike those, zbuild doesn't replace the build system. It rides on top of Zig's native build system, generating the same `std.Build` calls you'd write by hand.
