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
const contract = @import("runtime_contract");
const runtime_mode = @import("../runtime_mode.zig");

/// Toolchain resolution and cache-publication failures raised while opening a session.
pub const Error = native_build.Error;

/// The resolved native tools, published runtime tree and object cache identity.
pub const Toolchain = struct {
    zig: []const u8,
    qbe: []const u8,
    assets: []const u8,
    environment: []const u8,
    /// This environment's object generation, where the suites' cached objects live.
    directory: []const u8,
    /// This environment's executable generation, where built guest programs live.
    executables: []const u8,
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

/// One session per ownership contract: each links against its own runtime
/// archive and keys its objects under its own build environment.
var sessions: [@typeInfo(contract.Selection).@"enum".field_names.len]?Session = @splat(null);

/// Build options naming the harness toolchain and the suites' shared object cache.
pub fn settings() build_options.Options {
    return .{ .source = "", .run = true, .cache = harness.cache_directory, .codegen = .{ .qbe = harness.qbe_path }, .zig = harness.zig_path };
}

/// Open, or reuse, this process's native build session for the ownership
/// contract in-process emission currently lowers for (legacy sharing included),
/// so a manifest emitted under one contract is validated, compiled and linked
/// under the same one.
pub fn acquire() Error!*Session {
    const selection = runtime_mode.lowered();
    const slot = &sessions[@backingInt(selection)];
    if (slot.*) |*existing| return existing;
    // The session outlives every individual test, so it cannot be charged to a
    // test allocator that verifies release at the end of each one. // allocator-ok
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    const owner = arena.allocator();
    var environ: std.process.Environ.Map = .init(owner);
    try environ.put(contract.variable, selection.identity());
    slot.* = .{ .arena = arena, .io = std.testing.io, .environ = environ, .toolchain = undefined };
    const session = &slot.*.?;
    var context = try fs.Context.init(owner, session.io, &session.environ);
    const prepared = try native_build.prepare(context, settings());
    context.remove(prepared.cache.temporary);
    // Opening this compiler's executable generation evicts every other one, the
    // way `prepare` already did for the objects.
    const executables = try native_build.generation(context, prepared.root, "exe", native_build.generation_identity);
    session.toolchain = .{
        .zig = try owner.dupe(u8, prepared.cache.zig),
        .qbe = try owner.dupe(u8, prepared.cache.codegen.tool),
        .assets = try owner.dupe(u8, prepared.cache.assets),
        .environment = try owner.dupe(u8, prepared.cache.environment),
        .directory = try owner.dupe(u8, prepared.cache.directory),
        .executables = try owner.dupe(u8, executables),
    };
    return session;
}

// spec-case: QBE-GENERATION-1
test "the native session resolves one toolchain and reuses it" {
    const first = try acquire();
    const second = try acquire();
    try std.testing.expectEqual(first, second);
    try std.testing.expect(first.toolchain.zig.len != 0 and first.toolchain.qbe.len != 0);
    // Objects and executables each live in one generation directory under the suite cache.
    const objects = try std.fmt.allocPrint(std.testing.allocator, "{s}/objects/", .{harness.cache_directory[1..]});
    defer std.testing.allocator.free(objects);
    const executables = try std.fmt.allocPrint(std.testing.allocator, "{s}/exe/", .{harness.cache_directory[1..]});
    defer std.testing.allocator.free(executables);
    try std.testing.expect(std.mem.indexOf(u8, first.toolchain.directory, objects) != null);
    try std.testing.expect(std.mem.indexOf(u8, first.toolchain.executables, executables) != null);
    try std.testing.expectEqual(@as(usize, 64), std.fs.path.basename(first.toolchain.directory).len);
    try std.testing.expectEqual(@as(usize, 64), std.fs.path.basename(first.toolchain.executables).len);
}

// spec-case: RC-DEFAULT-1
test "each ownership contract gets its own native session and build environment" {
    const saved = runtime_mode.get();
    defer runtime_mode.set(saved);
    runtime_mode.set(.gc);
    const gc = try acquire();
    runtime_mode.set(.rc);
    const rc = try acquire();
    try std.testing.expect(gc != rc);
    try std.testing.expectEqualStrings("gc-v1", gc.environ.get(contract.variable).?);
    try std.testing.expectEqualStrings("rc-v4", rc.environ.get(contract.variable).?);
    try std.testing.expect(!std.mem.eql(u8, gc.toolchain.environment, rc.toolchain.environment));
    try std.testing.expectEqual(rc, try acquire());
}
