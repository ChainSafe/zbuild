# Motivation for zbuild

## Why zbuild?

The Zig programming language offers a powerful and flexible build system integrated directly into its toolchain via `build.zig` files. This system, while highly customizable and programmatic, can become complex and verbose for larger projects or for developers who prefer a declarative approach to configuration. `zbuild` was created to address these challenges by providing an opinionated, JSON-based alternative to Zig's native build system, aiming to streamline the build process while retaining the power of Zig’s capabilities.

The motivation behind `zbuild` stems from a desire to improve the developer experience for Zig projects, making it easier to define, manage, and share build configurations without sacrificing the language’s strengths. Here’s why `zbuild` exists and what it seeks to achieve:

---

## Problems with the Status Quo

### 1. Complexity of `build.zig`
Zig’s build system is a full-fledged programming environment written in Zig itself. While this offers unparalleled flexibility—allowing dynamic build logic, conditional compilation, and custom steps—it comes with a steep learning curve:
- Developers must write and maintain imperative Zig code for tasks like adding executables, libraries, or dependencies.
- Common build patterns (e.g., adding an executable with a test) require repetitive boilerplate code.
- Debugging build scripts can be challenging due to their programmatic nature.

For small projects, this might be manageable, but as projects grow, the `build.zig` file can become a maintenance burden, especially for teams or newcomers unfamiliar with Zig’s build internals.

### 2. Lack of Declarative Configuration
Many modern build tools (e.g., `Cargo` for Rust, `npm`/`package.json` for Node.js) offer declarative configuration files that define what to build rather than how to build it. Zig’s `build.zig` requires developers to specify both, which can feel overly hands-on for straightforward projects. There’s no built-in way to define a project’s structure in a simple, human-readable format without writing code.

### 3. Inconsistent Build Patterns
Without a standardized structure, different Zig projects may adopt wildly different `build.zig` conventions. This inconsistency makes it harder for developers to:
- Quickly understand a new project’s build setup.
- Reuse build logic across projects.
- Share build configurations with the community.

### 4. Limited Tooling Integration
While Zig’s build system is powerful, its programmatic nature doesn’t lend itself easily to integration with external tools like IDEs or CI/CD pipelines, which often expect structured configuration files (e.g., JSON or YAML) for validation, autocompletion, or automation.

---

## Goals of zbuild

`zbuild` aims to address these issues by introducing a layer of abstraction over Zig’s build system, guided by the following goals:

### 1. Simplify Build Definition
By using a JSON-based configuration file (`zbuild.json`), `zbuild` allows developers to declaratively specify their project’s components—dependencies, modules, executables, libraries, tests, and more—without writing Zig code. This reduces the cognitive load and makes build setup accessible to developers who may not be Zig experts.

For example, instead of writing:

```zig
const std = @import("std");

pub fn build(b: *std.Build) void {
    const module_myapp = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
    });
    b.modules.put(b.dupe("myapp"), module_myapp) catch @panic("OOM");

    const exe_myapp = b.addExecutable(.{
        .name = "myapp",
        .root_module = module_myapp,
    });

    const install_exe_myapp = b.addInstallArtifact(exe_myapp, .{});
    const install_tls_exe_myapp = b.step("build-exe:myapp", "Install the myapp executable");
    install_tls_exe_myapp.dependOn(&install_exe_myapp.step);
    b.getInstallStep().dependOn(&install_exe_myapp.step);

    const run_exe_myapp = b.addRunArtifact(exe_myapp);
    if (b.args) |args| run_exe_myapp.addArgs(args);
    const run_tls_exe_myapp = b.step("run:myapp", "Run the myapp executable");
    run_tls_exe_myapp.dependOn(&run_exe_myapp.step);

    const test_myapp = b.addTest(.{
        .name = "myapp",
        .root_module = module_myapp,
    });
    const install_test_myapp = b.addInstallArtifact(test_myapp, .{});
    const install_tls_test_myapp = b.step("build-test:myapp", "Install the myapp test");
    install_tls_test_myapp.dependOn(&install_test_myapp.step);

    const run_test_myapp = b.addRunArtifact(test_myapp);
    const run_tls_test_myapp = b.step("test:myapp", "Run the myapp test");
    run_tls_test_myapp.dependOn(&run_test_myapp.step);
}
```


You can define:
```json
{
  "name": "project",
  "version": "0.1.0",
  "executables": {
    "myapp": {
      "root_module": {
        "root_source_file": "src/main.zig"
      }
    }
  }
}
```

And let `zbuild` generate the necessary `build.zig`.

### 2. Reduce Boilerplate
`zbuild` automates repetitive tasks like creating install steps, run commands, and tests for each target. It enforces a consistent structure, eliminating the need to manually replicate common patterns across projects.

### 3. Enhance Readability and Maintainability
A JSON configuration is inherently more readable and diff-friendly than a programmatic script. It’s easier to see at a glance what a project builds, what it depends on, and how it’s configured. This also simplifies maintenance, as changes to the build setup are more predictable and less error-prone.

### 4. Enable Tooling Support
The zbuild.json format, paired with a JSON schema (extension/schema.json), enables integration with editors like VSCode for autocompletion, validation, and error checking. This structured format also makes it feasible to integrate with CI/CD systems or other tools that parse configuration files.

### 5. Preserve Zig’s Power
While zbuild introduces a declarative layer, it doesn’t abandon Zig’s flexibility. It generates a build.zig file that can be customized further if needed, allowing developers to drop down to the native build system for advanced use cases. The generated file serves as a starting point, not a limitation.

### 6. Foster a Standard Build Workflow
By providing an opinionated structure, zbuild encourages a consistent build workflow across Zig projects. This standardization can lower the barrier to entry for new contributors and make it easier to share build configurations or adopt best practices.

## Usecases

`zbuild` is particularly valuable for:
- **Beginners**: Developers new to Zig can define builds without learning the intricacies of build.zig.
- **Large Projects**: Teams managing multiple targets (executables, libraries, tests) benefit from a centralized, declarative configuration.
- **Open-Source Projects**: A readable `zbuild.json` makes it easier for contributors to understand and modify the build setup.

## Trade-Offs
Introducing `zbuild` comes with trade-offs:
- **Opinionation**: The tool enforces a specific structure, which may not suit every project’s needs. Developers requiring full control may prefer raw build.zig.
- **Additional Layer**: zbuild adds a dependency and an extra step (generating `build.zig`), which could introduce complexity in some workflows.
- **Incomplete Features**: As an evolving project, `zbuild` lacks some planned features (e.g., `init`, `fetch`, `depends_on`), limiting its current scope.

Despite these trade-offs, the benefits of simplicity, consistency, and tooling support outweigh the drawbacks for many use cases.

## Inspiration
- **npm (Node.js)**: `package.json` provides a structured way to define scripts, dependencies, and metadata.
`zbuild` draws inspiration from:
- **Cargo (Rust)**: A declarative Cargo.toml simplifies Rust project builds while retaining flexibility via `build.rs`.

Unlike these tools, zbuild is tailored to Zig’s unique ecosystem, leveraging its native build system rather than replacing it.

## Future Vision
The long-term vision for zbuild includes:
- Full support for all Zig build features (e.g., custom steps, dependency fetching).
- A robust init command to scaffold new projects.
- Integration with Zig’s package manager for seamless dependency management.
- A community-driven ecosystem of reusable zbuild.json templates.

By addressing the pain points of Zig’s build system and offering a user-friendly alternative, zbuild aims to become a valuable tool in the Zig developer’s toolkit, enhancing productivity without compromising the language’s core principles.

