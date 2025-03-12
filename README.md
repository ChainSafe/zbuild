# zbuild

An opinionated build tool for Zig projects.

## Introduction

`zbuild` is a command-line build tool designed to simplify and enhance the build process for Zig projects. It allows you to define your project's build configuration in a `zbuild.json` file, which `zbuild` uses to generate a corresponding `build.zig` file compatible with the Zig build system. This approach provides a structured, configuration-driven alternative to writing Zig build scripts manually, making it easier to manage dependencies, executables, libraries, and other build artifacts.

Note: `zbuild` is currently under development. Some features are incomplete or subject to change. Check the `docs/TODO.md` file for planned enhancements.

## Features

- **JSON-based Configuration**: Define your build in a `zbuild.json` file instead of writing Zig code directly.
- **Automatic build.zig Generation**: Use the generate command to create a build.zig file from your configuration.
- **Comprehensive Build Support**: Manage dependencies, modules, executables, libraries, objects, tests, formatting, and run commands.
- **Command-Line Interface**: Execute common build tasks like compiling executables, running tests, and formatting code.
- **IDE Support**: Includes a JSON schema (`extension/schema.json`) for validating `zbuild.json` in editors like VSCode.

## Installation

TODO

## Usage

`zbuild` provides a command-line interface with various commands to manage your Zig projects. Below is the general syntax and a list of available commands:

```
Usage: zbuild [command] [options]
```

### Commands

- `init`: Initialize a Zig package in the current directory. (Not yet implemented)
- `fetch`: Copy a package into the global cache. (Not yet implemented)
- `install`: Install all artifacts defined in `zbuild.json`.
- `uninstall`: Uninstall all artifacts.
- `build-exe <name>`: Build a specific executable defined in `zbuild.json`.
- `build-lib <name>`: Build a specific library.
- `build-obj <name>`: Build a specific object file.
- `build-test <name>`: Build a test into an executable.
- `run <name>`: Run an executable or a run script.
- `test [name]`: Perform unit testing (optional name for specific test).
- `fmt [name]`: Format source code (optional name for specific fmt target).
- `build`: Run the standard `zig build` command with the generated `build.zig`.
- `generate`: Create a `build.zig` file from `zbuild.json`.
- `help`: Print the help message and exit.
- `version`: Print the version number and exit.

General Options

- `-h, --help`: Print command-specific usage.

## Configuration

The `zbuild.json` file is the heart of the zbuild system. It defines your project’s structure and build settings. Below is an example configuration:

```json
{
  "name": "example_project",
  "version": "1.2.3",
  "description": "A comprehensive example",
  "keywords": ["example"],
  "dependencies": {
    "mathlib": {
      "path": "deps/mathlib"
    },
    "network": {
      "url": "https://github.com/example/network/archive/v1.0.0.tar.gz"
    }
  },
  "options_modules": {
    "build_options": {
      "max_depth": {
        "type": "usize",
        "default": 100
      },
    }
  },
  "modules": {
    "utils": {
      "root_source_file": "src/utils/main.zig",
      "imports": ["mathlib", "build_options"],
      "link_libc": true
    },
    "core": {
      "root_source_file": "src/core/core.zig",
      "imports": ["utils"]
    }
  },
  "executables": {
    "main_app": {
      "root_module": {
        "root_source_file": "src/main.zig",
        "imports": ["core", "network"]
      }
    }
  },
  "libraries": {
    "libmath": {
      "version": "0.1.0",
      "root_module": "utils",
      "linkage": "static",
    }
  },
  "tests": {
    "unit_tests": {
      "name": "unit_tests",
      "root_module": {
        "root_source_file": "tests/unit.zig",
        "imports": ["core", "utils"]
      }
    }
  },
  "fmts": {
    "source": {
      "paths": ["src", "tests"],
      "exclude_paths": ["src/generated"],
      "check": true
    }
  },
  "runs": {
    "start_server": "zig run src/server.zig",
    "build_docs": "scripts/build_docs.sh"
  }
}
```

### Key Sections

- **Project Metadata**: Defines the project's identity and purpose.
- **Dependencies**: Manages external libraries or packages.
- **Modules**: Organizes reusable code units.
- **Executables**: Specifies buildable programs.
- **Libraries**: Configures libraries for reuse or sharing.
- **Tests**: Sets up testing configurations.
- **Fmts**: Controls code formatting rules.
- **Runs**: Provides custom commands for project tasks.

For a full list of configuration options, refer to the schema.json (`extension/schema.json`) file, which provides detailed validation rules for zbuild.json. This schema can be used in editors like VSCode for autocompletion and error checking.

## Hello World Example

Here’s a step-by-step example to create and build a simple Zig project with zbuild:

- Create a Project Directory:

```bash
mkdir myproject
cd myproject
```

- Initialize the project:

```bash
zbuild init
```

- Add an executable to `zbuild.json`

```json
{
  "name": "myproject",
  "version": "1.0.0",
  "executables": {
    "hello": {
      "root_module": {
        "root_source_file": "src/main.zig"
      }
    }
  }
}
```

- Edit a Source File:

Edit `src/main.zig` with a simple program:

```zig
const std = @import("std");

pub fn main() !void {
    std.debug.print("Hello, zbuild!\n", .{});
}
```

- The project can now be built/run/tested

- Build the Executable:

```bash
zbuild build-exe hello
```

This builds the `hello` executable into `zig-out/bin`.

- Run the Executable:

```bash
zbuild run hello
```

Outputs: `Hello, zbuild!`

## Contributing

Contributions are welcome! To contribute:

1. Fork the repository on GitHub: https://github.com/chainsafe/zbuild.
2. Create a branch for your changes.
3. Submit a pull request with a clear description of your improvements.

Please open an issue first to discuss significant changes or report bugs.

## License

MIT
