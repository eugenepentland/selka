//! Linux deployment defaults for bounded native components.
/// Used when the command environment does not configure TMPDIR.
pub const temporary_root = "/tmp";
/// Default native frontend implementation mode.
pub const reference_mode = "reference";

const std = @import("std");
const launch = @import("../component_launch.zig");
const retained = @import("../component_session.zig");
/// Explicit process capabilities and optional invocation-owned artifact authority.
pub const Runtime = struct {
    io: std.Io,
    environ: *const std.process.Environ.Map,
    component_dir: ?[]const u8 = null,
    timeout_ms: i64 = 30000,
    session: ?*retained.Session = null,
    /// Authenticate current deployment, optionally reusing invocation-owned authenticated bytes.
    pub fn artifact(self: Runtime, a: std.mem.Allocator, directory: []const u8, component: []const u8) launch.Error!launch.Verified {
        return if (self.session) |owner| owner.artifact(a, self.io, directory, component) else launch.artifact(a, self.io, directory, component);
    }
    /// Retain a verified immutable snapshot through the owning invocation or caller arena.
    pub fn snapshot(self: Runtime, a: std.mem.Allocator, directory: []const u8, component: []const u8) launch.Error!retained.View {
        return if (self.session) |owner| owner.snapshot(a, self.io, directory, component) else retained.fallback(a, self.io, directory, component);
    }
    /// Borrow a retained sealed descriptor or create a caller-owned fallback.
    pub fn seal(self: Runtime, contents: []const u8) launch.SnapshotError!retained.Executable {
        return if (self.session) |owner| owner.seal(self.io, contents) else .{ .file = try launch.sealedExecutable(self.io, contents) };
    }
};

/// Explicit independently executed frontend implementation mode.
pub const component_mode = "component";
