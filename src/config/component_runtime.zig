//! Linux deployment defaults for bounded native components.
/// Used when the command environment does not configure TMPDIR.
pub const temporary_root = "/tmp";
/// Default native frontend implementation mode.
pub const reference_mode = "reference";

const std = @import("std");
/// Explicit process capabilities shared by the frontend boundaries.
pub const Runtime = struct { io: std.Io, environ: *const std.process.Environ.Map, component_dir: ?[]const u8 = null, timeout_ms: i64 = 30000 };

/// Explicit independently executed frontend implementation mode.
pub const component_mode = "component";
