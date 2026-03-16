const zbuild = @import("zbuild");
const std = @import("std");

pub fn build(b: *std.Build) void {
    // TODO: @import("build.zig.zon") requires a known result type in Zig 0.14.
    // Investigating whether later Zig versions lift this restriction.
    // For now, the manifest is defined inline.
    _ = zbuild.configureBuild(b, .{
        .name = .full_example,
        .version = "1.0.0",
        .description = "A comprehensive zbuild example showcasing all features",

        // --- Modules: reusable code units ---
        // Modules are registered with the build system and can be referenced
        // by name from executables, libraries, and tests via root_module.
        .modules = .{
            .math = .{
                .root_source_file = "src/lib.zig",
            },
        },

        // --- Executables ---
        // root_module can be an enum literal (.math) referencing a named module,
        // a string ("math"), or an inline struct with a full module definition.
        .executables = .{
            .demo = .{
                .root_module = .{
                    .root_source_file = "src/main.zig",
                    .imports = .{ .math, .config },
                },
            },
        },

        // --- Libraries ---
        .libraries = .{
            .mathlib = .{
                .root_module = .math,
            },
        },

        // --- Tests ---
        // Each test gets a test:<name> step and joins the aggregate "test" step.
        // Use -D<name>.filters=... to filter specific tests from the CLI.
        .tests = .{
            .unit = .{
                .root_module = .{
                    .root_source_file = "src/test.zig",
                    .imports = .{.math},
                },
            },
        },

        // --- Fmts ---
        // Wraps zig fmt. Each entry gets fmt:<name> and joins aggregate "fmt".
        .fmts = .{
            .src = .{
                .paths = .{"src"},
            },
        },

        // --- Runs ---
        // Short form: bare tuple of strings.
        // Long form: struct with cmd + optional cwd, env, depends_on, etc.
        .runs = .{
            .@"echo-version" = .{ "echo", "full_example v1.0.0" },
            .greet = .{
                .cmd = .{ "echo", "hello from zbuild" },
                .env = .{ .GREETING = "hello" },
                .inherit_stdio = true,
            },
        },

        // --- Options modules ---
        // Creates an importable module with build-time options.
        // Access in Zig: const config = @import("config");
        .options_modules = .{
            .config = .{
                .verbose = .{
                    .type = .bool,
                    .default = false,
                    .description = "Enable verbose output",
                },
            },
        },

        // --- Dependencies ---
        // To add an external dependency with comptime args:
        // .dependencies = .{
        //     .zlib = .{
        //         .args = .{ .shared = true },
        //     },
        // },
    }, .{
        .help_step = "info", // custom help step name
    }) catch |err| {
        std.log.err("zbuild: {}", .{err});
        return;
    };
}
