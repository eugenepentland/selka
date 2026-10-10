//! A same-compiler directory parent may lend its tool identity for read-only
//! manifest replay. A miss must discard the ticket and establish a full local
//! identity before any build or cache publication. Parent validates all library
//! generations after its children; borrowed success remains provisional.
const std = @import("std");
const tool = @import("tool_identity.zig");
const linux = std.os.linux;
const version = "core-tool-ticket-v2";
const limit = 16 << 10;

/// Internal stdin transport marker; omit it from receipt keys and guest env.
pub const hint = "MYL_CORE_PARENT_TOOL_TICKET";

/// Resources and compiler identity supplied by the command, never the ticket.
pub const Request = struct {
    tool: tool.Request,
    compiler_identity: []const u8,
    component_identity: [32]u8 = @splat(0),
    input: std.Io.File = .stdin(),
};

const Envelope = struct { version: []const u8, compiler_identity: []const u8, component_identity: [32]u8, parent_pid: linux.pid_t, identity: tool.Identity, executable_generation: ?[32]u8, checksum: [32]u8 = @splat(0) };
/// Invalid foreign tickets fall back to full capture; only allocation escapes.
pub const Error = error{OutOfMemory};

/// Encode a captured identity to an invocation-owned private stdin file.
pub fn encode(request: Request, identity: tool.Identity) tool.Error![]const u8 {
    const stamp = if (identity.cacheable) try tool.executableGeneration(request.tool, identity.path) else null;
    var envelope: Envelope = .{ .version = version, .compiler_identity = request.compiler_identity, .component_identity = request.component_identity, .parent_pid = linux.getpid(), .identity = identity, .executable_generation = stamp };
    envelope.checksum = try checksum(request.tool.arena, envelope);
    return std.json.Stringify.valueAlloc(request.tool.arena, envelope, .{});
}

/// Borrow only from the actual live parent running this exact executable.
/// Missing/invalid hints never read stdin; malformed/foreign payloads are misses.
pub fn borrow(request: Request) Error!?tool.Identity {
    if (!std.mem.eql(u8, request.tool.environment.get(hint) orelse "", "1")) return null;
    const parent = linux.getppid();
    if (!sameCompiler(parent)) return null;
    var buffer: [256]u8 = undefined;
    var reader = request.input.readerStreaming(request.tool.io, &buffer);
    const bytes = reader.interface.allocRemaining(request.tool.arena, .limited(limit)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (linux.getppid() != parent) return null;
    return checked(request, bytes, parent);
}

fn checked(request: Request, bytes: []const u8, parent: linux.pid_t) Error!?tool.Identity {
    if (bytes.len >= limit) return null;
    const envelope = std.json.parseFromSliceLeaky(Envelope, request.tool.arena, bytes, .{}) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (!std.mem.eql(u8, &envelope.checksum, &try checksum(request.tool.arena, envelope))) return null;
    if (!std.mem.eql(u8, envelope.version, version)) return null;
    if (!std.mem.eql(u8, envelope.compiler_identity, request.compiler_identity)) return null;
    if (!std.mem.eql(u8, &envelope.component_identity, &request.component_identity)) return null;
    if (envelope.parent_pid != parent or !sameCompiler(parent)) return null;
    if (!envelope.identity.cacheable or !std.fs.path.isAbsolute(envelope.identity.path)) return null;
    const path = tool.resolve(request.tool) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (!std.mem.eql(u8, path, envelope.identity.path)) return null;
    const expected = envelope.executable_generation orelse return null;
    const current = tool.executableGeneration(request.tool, path) catch return null;
    if (!std.mem.eql(u8, &current, &expected)) return null;
    const cpu = tool.nativeTarget(request.tool.io) catch return null;
    if (!std.mem.eql(u8, &cpu, &envelope.identity.native_target)) return null;
    return envelope.identity;
}

fn checksum(a: std.mem.Allocator, encoded: Envelope) Error![32]u8 {
    var envelope = encoded;
    envelope.checksum = @splat(0);
    const bytes = try std.json.Stringify.valueAlloc(a, envelope, .{});
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return digest;
}

fn sameCompiler(parent: linux.pid_t) bool {
    var path: [64]u8 = undefined;
    const bytes = std.fmt.bufPrint(&path, "/proc/{d}/exe\x00", .{parent}) catch return false;
    const name = bytes[0 .. bytes.len - 1 :0];
    var own: linux.Statx = undefined;
    var other: linux.Statx = undefined;
    const mask: linux.STATX = .{ .INO = true, .SIZE = true, .MTIME = true, .CTIME = true, .MODE = true };
    if (linux.errno(linux.statx(std.posix.AT.FDCWD, "/proc/self/exe", 0, mask, &own)) != .SUCCESS) return false;
    if (linux.errno(linux.statx(std.posix.AT.FDCWD, name, 0, mask, &other)) != .SUCCESS) return false;
    const needed: u32 = @bitCast(mask);
    const ours: u32 = @bitCast(own.mask);
    const theirs: u32 = @bitCast(other.mask);
    if (ours & needed != needed or theirs & needed != needed) return false;
    if (own.dev_major != other.dev_major or own.dev_minor != other.dev_minor) return false;
    if (own.ino != other.ino or own.size != other.size or own.mode != other.mode) return false;
    if (own.mtime.sec != other.mtime.sec or own.mtime.nsec != other.mtime.nsec) return false;
    return own.ctime.sec == other.ctime.sec and own.ctime.nsec == other.ctime.nsec;
}

// spec-case: NEW-CORE-S4-TEST-3
test "tool tickets require same compiler provenance and ignore missing internal hints" {
    try std.testing.expect(sameCompiler(linux.getpid()));
    try std.testing.expect(!sameCompiler(0));
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const request: Request = .{ .tool = .{ .arena = std.testing.allocator, .io = std.testing.io, .environment = &environment, .executable = "missing", .cache = "unused" }, .compiler_identity = "compiler" };
    try std.testing.expectEqual(@as(?tool.Identity, null), try borrow(request));
}

// spec-case: NEW-CORE-S4-TEST-3
test "tool tickets reject damaged foreign and uncacheable identities" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const request: Request = .{ .tool = .{ .arena = a, .io = std.testing.io, .environment = &environment, .executable = "missing", .cache = "unused" }, .compiler_identity = "compiler" };
    const identity: tool.Identity = .{ .path = "/missing", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = true };
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, "damaged", linux.getpid()));
    var foreign = request;
    foreign.compiler_identity = "foreign compiler";
    const bytes = try encode(foreign, identity);
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, bytes, linux.getpid()));
    const ours = try encode(request, identity);
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, ours, linux.getpid()));
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, ours, 0));
}

// spec-case: NEW-CORE-S4-TEST-3
test "valid tool tickets bind the executable generation and native CPU" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const path = try std.Io.Dir.cwd().realPathFileAlloc(std.testing.io, "/proc/self/exe", a);
    const request: Request = .{ .tool = .{ .arena = a, .io = std.testing.io, .environment = &environment, .executable = path, .cache = "unused" }, .compiler_identity = "compiler" };
    const identity: tool.Identity = .{ .path = path, .digest = @splat(0), .generation = @splat(0), .native_target = try tool.nativeTarget(std.testing.io), .inputs = 1, .memo_hit = true, .cacheable = true };
    const bytes = try encode(request, identity);
    const borrowed = (try checked(request, bytes, linux.getpid())).?;
    try std.testing.expectEqual(identity.digest, borrowed.digest);
    var envelope = try std.json.parseFromSliceLeaky(Envelope, a, bytes, .{});
    envelope.executable_generation.?[0] ^= 1;
    envelope.checksum = try checksum(a, envelope);
    const altered = try std.json.Stringify.valueAlloc(a, envelope, .{});
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, altered, linux.getpid()));
    envelope = try std.json.parseFromSliceLeaky(Envelope, a, bytes, .{});
    envelope.identity.native_target[0] ^= 1;
    envelope.checksum = try checksum(a, envelope);
    const other_cpu = try std.json.Stringify.valueAlloc(a, envelope, .{});
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, other_cpu, linux.getpid()));
    envelope = try std.json.parseFromSliceLeaky(Envelope, a, bytes, .{});
    envelope.component_identity[0] ^= 1;
    envelope.checksum = try checksum(a, envelope);
    const other_component = try std.json.Stringify.valueAlloc(a, envelope, .{});
    try std.testing.expectEqual(@as(?tool.Identity, null), try checked(request, other_component, linux.getpid()));
}
