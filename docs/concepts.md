# Conceptual Model

This page answers the question the README does not try to answer in full: what is zbuild actually doing?

If the README is the top-down path, this is the bottom-up path. The goal here is not to teach every field. The goal is to make the whole library feel coherent.

## 1. zbuild is a translation layer

zbuild is not a new build system. It is a compile-time translation layer on top of `std.Build`.

The pipeline is:

1. Zig evaluates `@import("build.zig.zon")` as a typed anonymous struct.
2. zbuild validates that value.
3. zbuild emits ordinary `std.Build` modules, artifacts, and steps from it.

That has three consequences:

- The compiler is the parser.
- The manifest type is the schema.
- The escape hatch is always just normal `build.zig` code.

## 2. The manifest is a graph declaration

Different sections create different kinds of graph nodes:

| Section | Produces | Main public names |
|---|---|---|
| `modules` | reusable Zig modules | enum-literal import names like `.core` |
| `options_modules` | generated Zig config modules | enum-literal import names like `.config`; CLI flags like `-Dconfig.verbose` |
| `executables` | installable executable artifacts | `.myapp`, `build-exe:myapp`, `run:myapp` |
| `libraries` | installable library artifacts | `.mylib`, `build-lib:mylib` |
| `objects` | installable object artifacts | `.myobj`, `build-obj:myobj` |
| `tests` | test artifacts plus run/install steps | `test`, `test:unit`, `build-test:unit` |
| `fmts` | formatting steps | `fmt`, `fmt:src` |
| `runs` | arbitrary command steps | `cmd:deploy` |
| `aliases` | named aggregate top-level steps | `check`, `ci`, `release` |
| `dependencies` | loaded dependency build graphs | default module refs like `.zlib`, submodule refs like `"zlib:zlib"` |

This is the first important idea: zbuild sections are not random manifest blobs. Each section exists because it corresponds to a specific class of `std.Build` node.

## 3. Ownership lives in syntax

The cleanest part of zbuild's design is that reference syntax encodes ownership.

### `root_module`

- `.core` means a zbuild-owned named module
- `"shared"` means a manual module created with `b.addModule(...)` before `configureBuild`
- inline struct means define the module right here

### `imports`

- `.core` means a named module
- `.config` means an options module
- `.zlib` means a dependency default module
- `"shared"` means a manual module
- `"zlib:zlib"` means a dependency submodule

### `depends_on`

- `.myapp` means the install step for artifact `myapp`
- `"run:myapp"` means the exact generated step named `run:myapp`
- `"gen:prep"` means the exact manual top-level step named `gen:prep`

That syntax split is the main reason the API can stay terse without becoming ambiguous everywhere.

## 4. There are multiple namespaces, on purpose

zbuild does not have one universal bag of names. It has several namespaces with different rules.

### Import namespace

Named modules, options modules, and dependency default modules all share one enum-literal import namespace.

Examples:

- `.core`
- `.config`
- `.zlib`

Those names must be unique across those categories. zbuild rejects collisions instead of picking one by precedence.

### Manual-module namespace

Bare strings in `root_module` and `imports` are reserved for manual modules registered before `configureBuild`.

Example:

- `"shared"`

This is a separate namespace on purpose. If a name belongs to zbuild, you should use the zbuild syntax for it.

### Artifact shorthand namespace

Executables, libraries, and objects share one shorthand namespace for `depends_on`.

Example:

- `.myapp`
- `.mylib`

That shorthand maps to exactly one install step, so installable artifact names must be unique across those sections.

### Top-level step namespace

Generated step names and manual top-level steps live together in the top-level step namespace.

Examples:

- `build-exe:myapp`
- `run:myapp`
- `test`
- `cmd:deploy`
- `check`
- `gen:prep`

Strings in `depends_on` target exact step names in this namespace.

Some bare names are only reserved conditionally: `"test"` and `"fmt"` are zbuild-owned only when the manifest actually defines `tests` or `fmts`; otherwise those names remain available for manual top-level steps.

## 5. Private modules are still zbuild modules

`modules.<name>.private = true` means "do not export this module to `b.modules`", not "pretend it does not exist".

Private named modules are still:

- part of the zbuild-owned graph
- referenceable from other zbuild manifest entries
- subject to the same zbuild namespace rules

The difference is visibility to outside `build.zig` consumers, not visibility inside the manifest.

## 6. Validation splits by what is actually knowable

zbuild validates in two phases because some facts are available at comptime and some are not.

### Compile time

These fail with `@compileError`:

- unknown fields inside zbuild-owned sections
- bad local refs to zbuild-owned modules, artifacts, and generated steps
- namespace collisions within the zbuild-owned graph
- malformed reference syntax
- typed option schema mistakes

### Configure time

These fail while `configureBuild` runs, before the build graph executes:

- missing manual modules or steps
- missing dependency exports
- missing dependency-backed lazy paths
- dependency artifact lookup failures

This is not an arbitrary split. It follows ownership and knowability:

- manifest-owned graph: knowable at comptime
- manual/dependency state: only knowable after `build.zig` and `b.dependency(...)` have run

## 7. Options modules are generated config APIs

`options_modules` are not just CLI flags. Each entry creates an importable Zig module.

```zig
.options_modules = .{
    .config = .{
        .verbose = .{
            .type = .bool,
            .default = false,
        },
        .log_level = .{
            .type = .@"enum",
            .values = .{ .debug, .info, .warn },
            .default = .info,
        },
    },
},
```

Users set values with:

```bash
zig build -Dconfig.verbose=true -Dconfig.log_level=warn
```

And Zig code imports:

```zig
const config = @import("config");
```

That is why `options_modules` live in the import namespace but are not valid `root_module` targets: they are config surfaces, not compilation roots.

## 8. Interop is explicit, not magical

Manual `build.zig` code still matters. The rule is simple:

- register manual modules and manual top-level steps before `configureBuild`
- reference them from the manifest with bare strings

Example:

```zig
_ = b.addModule("shared", .{
    .root_source_file = b.path("src/shared.zig"),
    .target = b.resolveTargetQuery(.{}),
    .optimize = .Debug,
});
_ = b.step("gen:prep", "manual prep step");
```

Manifest side:

```zig
.root_module = "shared"
.imports = .{"shared"}
.depends_on = .{"gen:prep"}
```

Aliases use that same `depends_on` model, but only create a named grouping step. They do not introduce a command or artifact of their own.

That model stays understandable because the syntax tells you when you are leaving the zbuild-owned world.

## 9. Why this feels coherent

zbuild gets leverage from using Zig's own semantics instead of fighting them:

- `build.zig.zon` is already typed
- `std.Build` is already the backend
- `build.zig` is already the escape hatch

So the library only needs to add:

- a graph-oriented manifest surface
- a consistent reference model
- early validation

That is the whole design in one sentence: zbuild makes the static parts of a Zig build graph declarative without pretending the dynamic parts are declarative too.
