//! zbuild — declarative build configuration for Zig projects.
//!
//! Add zbuild as a dependency, then call `configureBuild` from your build.zig:
//!
//!     const zbuild = @import("zbuild");
//!
//!     pub fn build(b: *std.Build) void {
//!         zbuild.configureBuild(b) catch |err| {
//!             std.log.err("zbuild: {}", .{err});
//!         };
//!     }

pub const Config = @import("Config.zig");
pub const build_runner = @import("build_runner.zig");
pub const configureBuild = build_runner.configureBuild;
