# zbuild

An opinionated build tool for Zig projects.

## Introduction

`zbuild` is a command-line build tool designed to simplify and enhance the build process for Zig projects. It leverages a ZON-based configuration file (`zbuild.zon`) to define project builds declaratively, generating a corresponding `build.zig` and `build.zig.zon` file that integrates seamlessly with Zig’s native build system. This approach reduces the complexity of writing and maintaining Zig build scripts manually, offering a structured alternative for managing dependencies, modules, executables, libraries, tests, and more.

Note: `zbuild` is under active development. Some features are incomplete or subject to change. Check the `docs/TODO.md` file for planned enhancements.

## Features

- **ZON-based Configuration**: Define your build in a `zbuild.zon` file instead of writing Zig code directly.
- **Automatic build.zig Generation**: Create a `build.zig` and `build.zig.zon` file from your configuration.
- **Comprehensive Build Support**: Manage dependencies, modules, executables, libraries, objects, tests, formatting, and run commands.
- **Command-Line Interface**: Execute common build tasks like compiling executables, running tests, and formatting code.

## Installation

Currently, zbuild must be built from source:

1. Clone the repository:
```bash
git clone https://github.com/chainsafe/zbuild.git
cd zbuild
```

2. Build the executable:
```bash
zig build -Doptimize=ReleaseFast
```

3. (Optional) Install it globally:
```bash
zig build install --prefix ~/.local
```

A pre-built binary distribution is planned for future releases once sufficient feature-completeness is achieved.

## Usage

`zbuild` provides a command-line interface with various commands to manage your Zig projects. Below is the general syntax and a list of available commands:

```
Usage: zbuild [global_options] [command] [options]
```

### Commands

- `init`: Initialize a new Zig project with a basic `zbuild.zon`, `build.zig`, `build.zig.zon`, and `src/main.zig` in the current directory.
- `fetch`: Copy a package into the global cache  and optionally add it to `zbuild.zon` and `build.zig.zon`
- `install`: Install all artifacts defined in `zbuild.zon`.
- `uninstall`: Uninstall all artifacts.
- `sync`: Synchronize `build.zig` and `build.zig.zon` with `zbuild.zon`.
- `build`: Run `zig build` with the generated `build.zig`.
- `build-exe <name>`: Build a specific executable defined in `zbuild.zon`.
- `build-lib <name>`: Build a specific library.
- `build-obj <name>`: Build a specific object file.
- `build-test <name>`: Build a specific test into an executable.
- `run <name>`: Run an executable or a custom run script.
- `test [name]`: Run all tests or a specific test.
- `fmt [name]`: Format code for all or a specific formatting target.
- `help`: Print the help message and exit.
- `version`: Print the version number and exit.

### Global Options

- `--project-dir <path>`: Set the project directory (default: `.`).
- `--zbuild-file <path>`: Specify the configuration file (default: `zbuild.zon`).
- `--no-sync`: Skip automatic synchronization of `build.zig` and `build.zig.zon`.

### General Options

- `-h, --help`: Print command-specific usage.

For command-specific options (e.g., `fetch`), use zbuild <command> --help.

## Configuration

The `zbuild.zon` file is the heart of the zbuild system. It defines your project’s structure and build settings. Below is an example configuration:

```zon
.{
    .name = .example_project,
    .version = "1.2.3",
    .description = "A comprehensive example",
    .fingerprint = 0x90797553773ca567,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .keywords = .{"example"},
    .dependencies = .{
        .mathlib = .{
            .path = "deps/mathlib",
        },
        .network = .{
            .url = "https://github.com/example/network/archive/v1.0.0.tar.gz",
        },
    },
    .options_modules = .{
        .build_options = .{
            .max_depth = .{
                .type = "usize",
                .default = 100,
            },
        },
    },
    .modules = .{
        .utils = .{
            .root_source_file = "src/utils/main.zig",
            .imports = .{.mathlib, .build_options},
            .link_libc = true,
        },
        .core = .{
            .root_source_file = "src/core/core.zig",
            .imports = .{.utils},
        },
    },
    .executables = .{
        .main_app = .{
            .root_module = .{
                .root_source_file = "src/main.zig",
                .imports = .{.core, .network},
            },
        },
    },
    .libraries = .{
        .libmath = .{
            .version = "0.1.0",
            .root_module = .utils,
            .linkage = .static,
        },
    },
    .tests = .{
        .unit_tests = .{
            .root_module = .{
                .root_source_file = "tests/unit.zig",
                .imports = .{.core, .utils},
            },
        },
    },
    .fmts = .{
        .source = .{
            .paths = .{"src", "tests"},
            .exclude_paths = .{"src/generated"},
            .check = true,
        },
    },
    .runs = .{
        .start_server = "zig run src/server.zig",
        .build_docs = "scripts/build_docs.sh",
    },
}
```

### Key Sections

- `name`, `version`, `fingerprint`, `minimum_zig_version`, `paths`: Project metadata (required).
- `dependencies`: External packages (path or URL).
- `options_modules`: Configurable build options bundled into modules.
- `modules`: Reusable code units with optional imports and build settings.
- `executables`, `libraries`, `objects`: Build targets with root modules.
- `tests`: Test targets with optional filters.
- `fmts`: Code formatting rules.
- `runs`: Custom shell commands.

## Hello World Example

Here’s a step-by-step example to create and build a simple Zig project with zbuild:

1. Initialize the project:

```bash
mkdir myproject
cd myproject
zbuild init
```

2. (Optional) Inspect `zbuild.zon`

```zon
.{
    .name = .myproject,
    .version = "0.1.0",
    .fingerprint = 0x<generated>,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .executables = .{
        .myproject = .{
            .root_module = .{
                .root_source_file = "src/main.zig",
            },
        },
    },
}
```

3. Update `src/main.zig`
```zig
const std = @import("std");
pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const arg = if (args.len >= 2) args[1] else "zbuild";
    std.debug.print("Hello {s}!\n", .{arg});
}
```

4. (Optional) Build the Executable:

```bash
zbuild build-exe myproject
```
This builds the `myproject` executable into `zig-out/bin`.

5. Run the Executable:

```bash
zbuild run myproject -- world
```

Outputs: `Hello, world!`

## Fetching Dependencies

Add a dependency to your project:
```bash
zbuild fetch --save=example https://github.com/example/repo/archive/v1.0.0.tar.gz
```

This updates `zbuild.zon` with:
```zon
.dependencies = .{
    .example = {
        .url = "https://github.com/example/repo/archive/v1.0.0.tar.gz,
    }
}
```

And synchronizes `build.zig.zon` with the fetched hash.


## Contributing

Contributions are welcome! To contribute:

1. Fork the repository on GitHub: https://github.com/chainsafe/zbuild.
2. Create a branch for your changes.
3. Submit a pull request with a clear description of your improvements.

Please open an issue first to discuss significant changes or report bugs.

## License

MIT
