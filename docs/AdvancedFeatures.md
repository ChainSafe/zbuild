# Advanced Features

## WriteFiles: Managing Generated Files

The `write_files` feature in `zbuild` allows you to define sets of files or directories to be copied or generated during the build process. This is particularly useful for managing assets, configuration files, or generated code that your project depends on. The `write_files` section in `zbuild.zon` lets you specify these resources declaratively, and `zbuild` will generate the corresponding `build.zig` code to handle them.

### Configuration
The `write_files` field is an object where each key is a named set of files, and the value defines the files or directories to include. Each entry can be marked as `private` (accessible only within the build script) or public (installable as part of the build output). The `items` field specifies the source paths and their destinations.
Here’s an example `zbuild.zon` snippet:

```zon
.{
    .name = .myproject,
    .version = "0.1.0",
    .fingerprint = 0x90797553773ca567,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .write_files = .{
        .assets = .{
            .items = .{
                .@"logo.png" = .{
                    .type = "file",
                    .path = "resources/logo.png",
                },
                .config = .{
                    .type = "dir",
                    .path = "resources/config",
                    .exclude_extensions = .{".tmp"},
                },
            },
        },
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

#### How It Works
- `private`: If `true`, the files are added via `b.addWriteFiles()`, making them available only within the build script. If `false` or omitted, `b.addNamedWriteFiles()` is used, and the files are installable.
- `items`: A map of destination paths to source specifications:
  - `file`: Copies a single file (e.g., `resources/logo.png` to `logo.png` in the write files directory).

  - `dir`: Copies a directory, with optional `exclude_extensions` or `include_extensions` filters.

In the generated `build.zig`, this translates to:

```zig
const write_files_assets = b.addNamedWriteFiles();

...

_ = write_files_assets.addCopyFile(b.path("resources/logo.png"), "logo.png");
_ = write_files_assets.addCopyDirectory(b.path("resources/config"), "config", .{ .exclude_extensions = &[_][]const u8{"tmp"} });
```

## LazyPath Resolution: Flexible File References
`LazyPath` resolution enhances `zbuild` by allowing you to reference files dynamically across different sources (e.g., project files, `write_files`, `dependencies`, or `options`) using a colon-delimited syntax. This feature provides a flexible way to manage file paths without hardcoding them, making your build configuration more portable and maintainable.

### Syntax
Paths in zbuild.zon can use the following format:
- Simple Path: `src/main.zig` – A direct filesystem path relative to the project root.
- Prefixed Path: `<source>[:<path>]` – Specifies the source of the path, such as the name of a write_files, dependency, or option.

Supported sources include:
- writefiles: `<name>:<path>`: References a file or directory from a `write_files` set.
- dependency named lazy path: `<name>:<path>`: References a file from a dependency’s named lazy paths.
- dependency named writefiles: `<name>:<writefile>:<path>`: References a file from a dependency’s named write files.
- options: `<name>`: References a `LazyPath` option value from the `options` section.

### Configuration Example
Here’s an extended `zbuild.zon` showcasing `LazyPath` resolution:

```zon
.{
    .name = .myproject,
    .version = "0.1.0",
    .fingerprint = 0x90797553773ca567,
    .minimum_zig_version = "0.14.0",
    .paths = .{ "build.zig", "build.zig.zon", "src" },
    .dependencies = .{
        .bar = .{
            .url = "git+https://github.com/org/bar",
        },
    },
    .modules = .{
        .foo = .{
            .root_source_file = "bar:some_output",
        },
    },
}
```

#### How It Works
- `bar:some_output`: Resolves to the named lazy file `some_output` from the `bar` dependency.

### Usage
- Extensibility: The `LazyPath` system supports additional sources like dependencies or options, making it adaptable to complex workflows.
