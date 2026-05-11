# Why zbuild?

zbuild exists for a specific kind of Zig project:

- the build graph is mostly static
- the same `std.Build` patterns repeat across many targets
- the team wants earlier, clearer failures than "some code in `build.zig` did the wrong thing"

It is not trying to remove Zig from the build story. It is trying to remove repetitive graph wiring from the parts that are already declarative in practice.

## The problem it attacks

Zig's build system is powerful because it is just Zig. That is also the source of the friction:

- a small executable often turns into a surprising amount of `build.zig`
- adding tests, runs, install steps, and module wiring scales linearly in boilerplate
- newcomers must learn a large API before they can express a simple graph

For a lot of projects, that is the wrong abstraction level. The graph is static. The code is just encoding structure.

## The design bet

zbuild makes one strong bet:

> `build.zig.zon` plus comptime is already enough structure to describe most static build graphs.

That bet only works because Zig already gives zbuild the important pieces:

- `@import("build.zig.zon")` returns a typed value at comptime
- `std.Build` is the real backend
- `build.zig` remains available for everything dynamic

So zbuild does not need a runtime parser, a custom IR, or a replacement toolchain. It only needs a coherent manifest surface and a disciplined translation into `std.Build`.

## What zbuild optimizes for

zbuild is trying to maximize four things at once:

- **Terseness** for the common static graph cases
- **Coherence** through explicit ownership and naming rules
- **Early failure** for manifest-owned mistakes
- **Interop** with manual `build.zig` code when the graph stops being static

That is why the library uses syntax splits like enum literals vs strings instead of trying to infer intent from arbitrary names. The API is smaller and more learnable when "what kind of thing is this?" has a visible answer.

## What it does not try to be

zbuild is not:

- a replacement for `build.zig`
- a universal abstraction over every `std.Build` feature
- a promise that all validation can happen at comptime

If you need platform-conditional logic, generated inputs, custom discovery, or one-off graph surgery, write that in `build.zig`. zbuild is meant to coexist with that code, not ban it.

## How to read the docs

- Start with the [README](../README.md) if you want the fastest path from zero to a working build.
- Read [Conceptual Model](concepts.md) if you want the bottom-up explanation of namespaces, ownership, and validation phases.
- Keep [Schema Reference](schema.md) open when you need exact field types and generated step names.
