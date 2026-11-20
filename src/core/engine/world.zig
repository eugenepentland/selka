//! The world a query reads (spec §4): the files, directories, variables and tools behind the engine's context.
//!
//! The context is the only handle a query gets to the world; the world is the handle the context gets to the
//! machine. It is an interface so that the engine runs the same code over the operating system (`os_world.zig`) and
//! over an in-memory filesystem with a clock a test sets (`memory_world.zig`), and so that this file, the context
//! and the store stay free of the compiler's own modules: a kind's code identity is the import closure of its roots,
//! and the engine runtime is in every closure. The assumptions of §4 that are not reads (the timestamp granularity,
//! which variables are placement) are `Assumptions` and `World.placement`, in one place.
const std = @import("std");
const digest_rules = @import("digest.zig");
const Digest = digest_rules.Digest;

/// The stat tuple a file read records and a validation compares. All zero means no tuple: the file is hashed.
pub const Stat = struct {
    inode: u64,
    size: u64,
    mtime: i64,
    ctime: i64,

    /// The tuple of "none seen": validation of a read that recorded it always hashes.
    pub const none: Stat = .{ .inode = 0, .size = 0, .mtime = 0, .ctime = 0 };

    /// Whether this is `none`. A real file never has inode 0.
    pub fn isNone(self: Stat) bool {
        return self.inode == 0;
    }

    /// Whether both tuples describe the same file state.
    pub fn eql(self: Stat, other: Stat) bool {
        return self.inode == other.inode and self.size == other.size and self.mtime == other.mtime and self.ctime == other.ctime;
    }

    /// The later of the two timestamps: the moment the file last changed, as far as its tuple can tell.
    pub fn changed(self: Stat) i64 {
        return @max(self.mtime, self.ctime);
    }
};

/// How a world read can fail. An absent file or directory is a null answer, not an error.
pub const ReadError = error{ OutOfMemory, ReadFailed };

/// The pseudo-directory whose listing is the environment that enters identities: `list` of this path names one
/// `NAME=VALUE` entry for every variable the world keys (placement and dropped variables are left out), so a variable
/// that is newly set, changed or unset is a change of the listing. A query reads it through `Context.environment`.
pub const environment_path = "\x00environment";

/// The assumptions of spec §4, written down once. They are configuration of the context, not reads.
pub const Assumptions = struct {
    /// A file whose last change is this recent when it is observed is not trusted to its stat tuple: the kernel stamps
    /// files with a clock that ticks every few milliseconds, so a second write within one tick keeps the tuple of the
    /// first (the racy-git case). 50 ms is more than ten ticks of the coarsest kernel clock (HZ=100).
    racy_window_ns: i64 = 50 * std.time.ns_per_ms,
    /// The largest file a query may read through the context.
    file_limit: usize = 256 << 20,
};

/// The operations the context needs. Every function may be called from any thread.
pub const World = struct {
    context: *anyopaque,
    vtable: *const VTable,

    /// The function table of a world.
    pub const VTable = struct {
        /// The stat tuple of the file or directory at `path`, or null when nothing is there.
        stat: *const fn (context: *anyopaque, path: []const u8) ?Stat,
        /// The bytes of the file at `path` in `arena`, or null when it is absent.
        read: *const fn (context: *anyopaque, arena: std.mem.Allocator, path: []const u8, limit: usize) ReadError!?[]const u8,
        /// The names the filter numbered `filter` keeps among the entries of the directory at `path`, in `arena`, or
        /// null when the directory cannot be opened. Filter 0 keeps every name.
        list: *const fn (context: *anyopaque, arena: std.mem.Allocator, path: []const u8, filter: u8) ReadError!?[]const []const u8,
        /// The value of the environment variable `name`, or null when it is unset.
        variable: *const fn (context: *anyopaque, name: []const u8) ?[]const u8,
        /// Whether `name` is a placement variable: read and recorded, never compared (spec §4).
        placement: *const fn (context: *anyopaque, name: []const u8) bool,
        /// The identity of the tool at `path`, or null when it cannot be found.
        tool: *const fn (context: *anyopaque, arena: std.mem.Allocator, path: []const u8) ReadError!?Digest,
        /// The clock the file timestamps are on, in nanoseconds since the epoch.
        now: *const fn (context: *anyopaque) i64,
    };

    /// The stat tuple at `path`, or null.
    pub fn stat(self: World, path: []const u8) ?Stat {
        return self.vtable.stat(self.context, path);
    }

    /// The bytes at `path`, or null.
    pub fn read(self: World, arena: std.mem.Allocator, path: []const u8, limit: usize) ReadError!?[]const u8 {
        return self.vtable.read(self.context, arena, path, limit);
    }

    /// The names `filter` keeps in the directory at `path`, or null.
    pub fn list(self: World, arena: std.mem.Allocator, path: []const u8, filter: u8) ReadError!?[]const []const u8 {
        return self.vtable.list(self.context, arena, path, filter);
    }

    /// The variable `name`, or null.
    pub fn variable(self: World, name: []const u8) ?[]const u8 {
        return self.vtable.variable(self.context, name);
    }

    /// Whether the variable `name` is placement.
    pub fn placement(self: World, name: []const u8) bool {
        return self.vtable.placement(self.context, name);
    }

    /// The identity of the tool at `path`, or null.
    pub fn tool(self: World, arena: std.mem.Allocator, path: []const u8) ReadError!?Digest {
        return self.vtable.tool(self.context, arena, path);
    }

    /// The current time on the timestamps' clock.
    pub fn now(self: World) i64 {
        return self.vtable.now(self.context);
    }
};

test "a stat tuple of zeros is no tuple, and any real tuple differs from it" {
    const real: Stat = .{ .inode = 9, .size = 3, .mtime = 5, .ctime = 6 };
    try std.testing.expect(Stat.none.isNone());
    try std.testing.expect(!real.isNone());
    try std.testing.expect(real.eql(real));
    try std.testing.expect(!real.eql(Stat.none));
    try std.testing.expectEqual(@as(i64, 6), real.changed());
}
