//! The whole-build replay: an unchanged `mylang-core build` publishes the
//! executable its last identical build produced, without running the front end,
//! the whole-program pipeline, emission or any tool.
//!
//! One record per entry and settings lives in `<cache>/replay-v1/<key>`; the last
//! successful build wins the slot. The key covers the compiler's identity, the
//! command's flags, the entry and its project configuration (resolved afresh on
//! every build), the toolchain identity and the complete environment. The record
//! lists every file the build read, by absolute path, with the digest of the
//! bytes the build used:
//! - each module source of the graph, as the front end checked it (a module name
//!   names exactly one file, and the standard library is part of the compiler);
//! - every embedded file and, for `interface_files` projects, every generated
//!   interface file (or its absence);
//! - each `--link` C source and every header its compiler depfile listed.
//! It also holds the program store entry with its digest and file status, and the
//! report text the build printed. A replay rereads and rehashes every listed file,
//! revalidates the toolchain, and checks the program entry before copying it.
const std = @import("std");
const language = @import("mylang");
const frontend = @import("frontend.zig");
const project_entry = @import("project_entry.zig");
const tool_identity = @import("tool_identity.zig");
const unit_cache = @import("unit_cache.zig");
const Digest = unit_cache.Digest;

/// What a build is, besides its sources: the command and where it caches.
pub const Context = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    /// The build's cache directory (`--cache-dir`).
    cache: []const u8,
    /// The `zig` the command named (`--zig`, `ZIG`, or `zig` on `PATH`).
    zig: []const u8,
    /// A canonical encoding of every flag that changes the executable.
    flags: []const u8,
    entry: project_entry.Entry,
};

/// Why a replay could not be read or written; a damaged record is a miss.
pub const Error = language.frontend_runtime.HostError || error{WriteFailed};

const version = "core-build-replay-v1";
const flags_magic = "SLKKEY01";
const Stamp = struct { size: u64, inode: u64, mtime: i64, ctime: i64 };
const Entry = struct { path: []const u8, digest: []const u8 };
const Snapshot = struct { key: []const u8, dependencies: []const Entry, program: []const u8, digest: []const u8, stamp: Stamp, report: []const u8 };
const Envelope = struct { version: []const u8, payload: []const u8, checksum: []const u8 };

/// Publish the recorded executable to `output` and append the recorded report when
/// every input is unchanged; false (a miss) otherwise, having written nothing.
pub fn replay(context: Context, output: []const u8, report: *std.ArrayList(u8)) Error!bool {
    const verified = try boundary(context);
    if (!verified.reuse) return false;
    const a = context.arena;
    const request = toolRequest(context);
    const candidate = tool_identity.lookupReplayCandidate(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    } orelse return false;
    const key = try settingsKey(context, candidate);
    const snapshot = try load(context, key) orelse return false;
    const dependencies = try a.alloc(unit_cache.Dependency, snapshot.dependencies.len);
    for (snapshot.dependencies, dependencies) |entry, *dependency| dependency.* = .{ .path = entry.path, .digest = parseDigest(entry.digest) };
    for (snapshot.dependencies, dependencies) |entry, dependency| if (entry.digest.len != 0 and dependency.digest == null) return false;
    if (!try unit_cache.unchanged(a, context.io, dependencies)) return false;
    // The candidate came from a memo; the replay is accepted only for the same
    // executable, CPU and library generations.
    const same_tool = tool_identity.unchanged(request, candidate) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    if (!same_tool) return false;
    if (!try programIntact(context, snapshot)) return false;
    _ = try boundary(context);
    @import("driver.zig").copyOutput(context.io, snapshot.program, output) catch return false;
    try report.appendSlice(a, snapshot.report);
    return true;
}

/// The files a checked build read, with the digests of the bytes it used; take
/// them before anything else reads the disk (`entry.validate` reads interface
/// files). Null when the set cannot be pinned exactly.
pub fn inputs(context: Context, session: *const frontend.Session) Error!?[]const unit_cache.Dependency {
    var files: std.ArrayList(unit_cache.Dependency) = .empty;
    if (!try captured(context, session, &files)) return null;
    return files.items;
}

/// Record a successful build. Nothing is recorded for an unproved toolchain, a
/// build whose `--link` inputs changed while they compiled, unpinned `sources`
/// (`inputs`), or a file that changed after the build read it.
pub fn remember(context: Context, sources: ?[]const unit_cache.Dependency, tool: tool_identity.Identity, outcome: Outcome, report: []const u8) Error!void {
    if (!(try boundary(context)).reuse) return;
    const a = context.arena;
    if (!tool.cacheable) return;
    const program = outcome.program orelse return;
    const foreign = outcome.foreign orelse return;
    var files: std.ArrayList(unit_cache.Dependency) = .empty;
    try files.appendSlice(a, sources orelse return);
    try files.appendSlice(a, foreign);
    if (!try unit_cache.unchanged(a, context.io, files.items)) return;
    const status = std.Io.Dir.cwd().statFile(context.io, program.path, .{}) catch return;
    const entries = try a.alloc(Entry, files.items.len);
    for (files.items, entries) |file, *entry| entry.* = .{ .path = file.path, .digest = if (file.digest) |digest| try hex(a, digest) else "" };
    const key = try settingsKey(context, tool);
    const snapshot: Snapshot = .{ .key = try hex(a, key), .dependencies = entries, .program = program.path, .digest = try hex(a, program.digest), .stamp = stamp(status), .report = report };
    const payload = std.json.Stringify.valueAlloc(a, snapshot, .{}) catch return error.OutOfMemory;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(payload, &checksum, .{});
    const envelope: Envelope = .{ .version = version, .payload = payload, .checksum = try hex(a, checksum) };
    const bytes = std.json.Stringify.valueAlloc(a, envelope, .{}) catch return error.OutOfMemory;
    try atomicWrite(context, try recordPath(context, key), bytes);
}

/// The parts of `driver.Outcome` a record needs.
pub const Outcome = struct { program: ?unit_cache.Found, foreign: ?[]const unit_cache.Dependency };

/// The record's key: compiler, flags, entry, configuration, toolchain and environment.
pub fn settingsKey(context: Context, tool: tool_identity.Identity) Error!Digest {
    const verified = try boundary(context);
    var hash = std.crypto.hash.Blake3.init(.{});
    unit_cache.field(&hash, &verified.identity);
    unit_cache.field(&hash, version);
    unit_cache.field(&hash, frontend.compiler_identity);
    unit_cache.field(&hash, context.flags);
    // `--link` compiles name their sources relative to it in debug information.
    unit_cache.field(&hash, std.Io.Dir.cwd().realPathFileAlloc(context.io, ".", context.arena) catch "");
    unit_cache.field(&hash, context.zig);
    unit_cache.field(&hash, tool.path);
    unit_cache.field(&hash, &tool.digest);
    unit_cache.field(&hash, &tool.native_target);
    unit_cache.field(&hash, context.entry.path);
    unit_cache.field(&hash, context.entry.root);
    unit_cache.field(&hash, context.entry.name);
    if (context.entry.configuration) |configured| {
        unit_cache.field(&hash, configured.path);
        unit_cache.field(&hash, configured.bytes);
        if (configured.policy) |policy| {
            unit_cache.field(&hash, policy.path);
            unit_cache.field(&hash, policy.bytes);
        }
    } else unit_cache.field(&hash, "no configuration");
    try environmentInto(context.arena, &hash, context.environment);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Reauthenticate the producer captured in build flags before emission or publication.
pub fn validate(context: Context) Error!language.frontend_runtime.Verified {
    return boundary(context);
}

/// Capture verified frontend authority alongside build flags without retaining artifact paths.
pub fn bindFlags(a: std.mem.Allocator, bytes: []const u8, runtime: language.frontend_runtime.Runtime) Error![]const u8 {
    const verified = try language.frontend_runtime.verify(a, runtime);
    return std.mem.concat(a, u8, &.{ flags_magic, &verified.identity, bytes });
}

fn boundary(context: Context) Error!language.frontend_runtime.Verified {
    const verified = try language.frontend_runtime.verify(context.arena, .{ .io = context.io, .environ = context.environment });
    if (std.mem.startsWith(u8, context.flags, flags_magic)) {
        if (context.flags.len < 40) return error.ComponentProtocol;
        if (!std.mem.eql(u8, context.flags[8..40], &verified.identity)) return error.ComponentChanged;
    }
    return verified;
}

/// The environment, in name order: anything the toolchain or the core reads from
/// it may change the executable or the report. Only the shell's own bookkeeping
/// (`_`, the last command's path; `SHLVL`; `OLDPWD`), which no tool reads, is left
/// out, so the same build from a script or a prompt replays alike.
fn environmentInto(a: std.mem.Allocator, hash: *std.crypto.hash.Blake3, environment: *const std.process.Environ.Map) Error!void {
    var names: std.ArrayList([]const u8) = .empty;
    var entries = environment.iterator();
    while (entries.next()) |entry| {
        if (shellBookkeeping(entry.key_ptr.*)) continue;
        try names.append(a, entry.key_ptr.*);
    }
    std.mem.sort([]const u8, names.items, {}, before);
    for (names.items) |name| {
        unit_cache.field(hash, name);
        unit_cache.field(hash, environment.get(name).?);
    }
}

fn shellBookkeeping(name: []const u8) bool {
    return std.mem.eql(u8, name, "_") or std.mem.eql(u8, name, "SHLVL") or std.mem.eql(u8, name, "OLDPWD");
}

fn before(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// Every source, embedded file and interface file the build read, with the bytes
/// the front end used. False when the set cannot be pinned exactly.
fn captured(context: Context, session: *const frontend.Session, files: *std.ArrayList(unit_cache.Dependency)) Error!bool {
    const a = context.arena;
    if (session.single) |unit| return loaded(context, files, context.entry.path, unit.src);
    const interfaces = if (context.entry.configuration) |configured| configured.document.interface_files else false;
    var entry_read = false;
    for (session.project.modules.items) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        const path = try std.fs.path.join(a, &.{ context.entry.root, module.src.path });
        entry_read = entry_read or std.mem.eql(u8, path, context.entry.path);
        if (!try loaded(context, files, path, module.src)) return false;
        if (!interfaces) continue;
        const api = try std.fmt.allocPrint(a, "{s}.api", .{path[0 .. path.len - ".my".len]});
        const digest = unit_cache.fileDigest(a, context.io, api) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return false,
        };
        try files.append(a, .{ .path = api, .digest = digest });
    }
    // The entry file decides whether the build checks a module graph at all.
    return entry_read;
}

fn loaded(context: Context, files: *std.ArrayList(unit_cache.Dependency), path: []const u8, source: language.source.Source) Error!bool {
    const a = context.arena;
    var digest: Digest = undefined;
    std.crypto.hash.Blake3.hash(source.bytes, &digest, .{});
    try files.append(a, .{ .path = path, .digest = digest });
    for (source.embeds) |embed| {
        if (embed.status != .ok) return false;
        var embedded: Digest = undefined;
        std.crypto.hash.Blake3.hash(embed.contents, &embedded, .{});
        const asset = try std.fs.path.resolve(a, &.{ std.fs.path.dirname(path) orelse ".", embed.path });
        try files.append(a, .{ .path = asset, .digest = embedded });
    }
    return true;
}

/// The program entry must still hold the bytes recorded: the same file status
/// (a rewrite changes it), else the same digest.
fn programIntact(context: Context, snapshot: Snapshot) Error!bool {
    const status = std.Io.Dir.cwd().statFile(context.io, snapshot.program, .{}) catch return false;
    if (std.meta.eql(stamp(status), snapshot.stamp)) return true;
    const expected = parseDigest(snapshot.digest) orelse return false;
    const actual = unit_cache.fileDigest(context.arena, context.io, snapshot.program) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ReadFailed => return false,
    } orelse return false;
    return std.mem.eql(u8, &actual, &expected);
}

fn stamp(status: std.Io.File.Stat) Stamp {
    return .{ .size = status.size, .inode = @intCast(status.inode), .mtime = @intCast(status.mtime.nanoseconds), .ctime = @intCast(status.ctime.nanoseconds) };
}

fn load(context: Context, key: Digest) Error!?Snapshot {
    const a = context.arena;
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, try recordPath(context, key), a, .limited(64 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const envelope = std.json.parseFromSliceLeaky(Envelope, a, bytes, .{}) catch return null;
    if (!std.mem.eql(u8, envelope.version, version)) return null;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(envelope.payload, &checksum, .{});
    const recorded = parseDigest(envelope.checksum) orelse return null;
    if (!std.mem.eql(u8, &checksum, &recorded)) return null;
    const snapshot = std.json.parseFromSliceLeaky(Snapshot, a, envelope.payload, .{}) catch return null;
    const stored_key = parseDigest(snapshot.key) orelse return null;
    if (!std.mem.eql(u8, &stored_key, &key)) return null;
    return snapshot;
}

fn recordPath(context: Context, key: Digest) Error![]const u8 {
    return std.fmt.allocPrint(context.arena, "{s}/replay-v1/{s}", .{ context.cache, std.fmt.bytesToHex(key, .lower) });
}

fn toolRequest(context: Context) tool_identity.Request {
    return .{ .arena = context.arena, .io = context.io, .environment = context.environment, .executable = context.zig, .cache = context.cache };
}

fn hex(a: std.mem.Allocator, digest: Digest) Error![]const u8 {
    return a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

fn parseDigest(text: []const u8) ?Digest {
    if (text.len != 64) return null;
    var digest: Digest = undefined;
    _ = std.fmt.hexToBytes(&digest, text) catch return null;
    return digest;
}

fn atomicWrite(context: Context, path: []const u8, bytes: []const u8) Error!void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(context.io, std.fs.path.dirname(path).?) catch return error.WriteFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(context.io, &nonce);
    const partial = try std.fmt.allocPrint(context.arena, "{s}.{s}.partial", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    defer removeFile(context.io, partial);
    cwd.writeFile(context.io, .{ .sub_path = partial, .data = bytes }) catch return error.WriteFailed;
    cwd.rename(partial, cwd, path, context.io) catch return error.WriteFailed;
}

fn removeFile(io: std.Io, path: []const u8) void {
    // A published record already moved away; otherwise discard this build's file.
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "replay keys cover flags, the tool, configuration and the environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    try environment.put("B", "2");
    try environment.put("A", "1");
    const tool: tool_identity.Identity = .{ .path = "/zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = true, .cacheable = true };
    const context: Context = .{ .arena = a, .io = std.testing.io, .environment = &environment, .cache = "cache", .zig = "zig", .flags = "{\"release\":false}", .entry = .{ .path = "/p/main.my", .root = "/p", .name = "main" } };
    const original = try settingsKey(context, tool);
    var changed = context;
    changed.flags = "{\"release\":true}";
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(changed, tool)));
    var other_tool = tool;
    other_tool.digest = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(context, other_tool)));
    other_tool = tool;
    other_tool.native_target = @splat(9);
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(context, other_tool)));
    try environment.put("A", "changed");
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(context, tool)));
    try environment.put("A", "1");
    try std.testing.expectEqual(original, try settingsKey(context, tool));
    try environment.put("_", "/usr/bin/taskset");
    try environment.put("SHLVL", "3");
    try std.testing.expectEqual(original, try settingsKey(context, tool));
    changed = context;
    changed.entry.path = "/p/other.my";
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(changed, tool)));
}
// spec-case: SELFHOST-FRONTEND-CACHE-1
test "bindFlags captures producer authority and boundary rejects changed authority before replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    const flags_snapshot = try bindFlags(a, "flags", .{ .io = std.testing.io, .environ = &environment });
    const context: Context = .{ .arena = a, .io = std.testing.io, .environment = &environment, .cache = "cache", .zig = "unused", .flags = flags_snapshot, .entry = .{ .path = "fixture", .root = ".", .name = "fixture" } };
    try std.testing.expect((try boundary(context)).reuse);
    @constCast(flags_snapshot)[8] ^= 1;
    try std.testing.expectError(error.ComponentChanged, boundary(context));
    var report: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.ComponentChanged, replay(context, "output", &report));
}
