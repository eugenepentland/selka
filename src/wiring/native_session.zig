//! Process-lifetime native build session shared by the Zig test suites.
//!
//! Resolving the toolchain, publishing the bundled runtime tree and opening the
//! object cache cost about a second; a suite that executes hundreds of guest
//! programs pays that once. Only the process wiring owns mutable global state,
//! so the session lives here and `native_execute.zig` stays a pure adapter.
const std = @import("std");
const fs = @import("../qbe_build_io.zig");
const native_build = @import("../qbe_build.zig");
const build_options = @import("../qbe_build_options.zig");
const harness = @import("native_test_options");

/// Toolchain resolution and cache-publication failures raised while opening a session.
pub const Error = native_build.Error;

/// The resolved native tools, published runtime tree and object cache identity.
pub const Toolchain = struct {
    zig: []const u8,
    qbe: []const u8,
    assets: []const u8,
    environment: []const u8,
    directory: []const u8,
};

/// One test binary's native build session: a process-lifetime arena and the toolchain.
pub const Session = struct {
    arena: std.heap.ArenaAllocator,
    io: std.Io,
    environ: std.process.Environ.Map,
    toolchain: Toolchain,

    /// Allocate values that outlive a single guest execution, such as captured output.
    pub fn allocator(self: *Session) std.mem.Allocator {
        return self.arena.allocator();
    }
};

var current: ?Session = null;

/// Build options naming the harness toolchain and the suites' shared object cache.
pub fn settings() build_options.Options {
    return .{ .source = "", .run = true, .cache = harness.cache_directory, .qbe = harness.qbe_path, .zig = harness.zig_path };
}

/// Open, or reuse, this process's native build session.
pub fn acquire() Error!*Session {
    if (current) |*existing| return existing;
    // The session outlives every individual test, so it cannot be charged to a
    // test allocator that verifies release at the end of each one. // allocator-ok
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const owner = arena.allocator();
    const environ: std.process.Environ.Map = .init(owner);
    current = .{ .arena = arena, .io = std.testing.io, .environ = environ, .toolchain = undefined };
    const session = &current.?;
    var context = try fs.Context.init(owner, session.io, &session.environ);
    const prepared = try native_build.prepare(context, settings());
    context.remove(prepared.cache.temporary);
    session.toolchain = .{
        .zig = try owner.dupe(u8, prepared.cache.zig),
        .qbe = try owner.dupe(u8, prepared.cache.qbe),
        .assets = try owner.dupe(u8, prepared.cache.assets),
        .environment = try owner.dupe(u8, prepared.cache.environment),
        .directory = try owner.dupe(u8, prepared.cache.directory),
    };
    try std.Io.Dir.cwd().createDirPath(session.io, try std.fmt.allocPrint(owner, "{s}/exe", .{session.toolchain.directory}));
    return session;
}

test "the native session resolves one toolchain and reuses it" {
    const first = try acquire();
    const second = try acquire();
    try std.testing.expectEqual(first, second);
    try std.testing.expect(first.toolchain.zig.len != 0 and first.toolchain.qbe.len != 0);
    try std.testing.expect(std.mem.endsWith(u8, first.toolchain.directory, harness.cache_directory[1..]));
}
