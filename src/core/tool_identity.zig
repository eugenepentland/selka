//! Content identity of guest Zig, native CPU, bundled inputs and default loader.
//! A compact, checksummed memo avoids rereading unchanged tool bytes. Every call
//! validates all known generations; strict capture checks twice. Provisional
//! directory replay requires a final parent validation. Callers must spawn the
//! returned absolute path and verify before publishing. No subprocess runs.
const std = @import("std");
const builtin = @import("builtin");
const target_policy = @import("target.zig");
const discovery = @import("tool_discovery.zig");
const target = target_policy.current;
const Digest = [32]u8;
const magic = "core-tool-content-v1\x00";
const memo_length = magic.len + 96;
// v4 adds a validated directory-role byte (Input codec v2), retains all old
// full-stat/content inputs, and keys the additive reviewed discovery policy.
// v5 records each library root as one input instead of its whole tree.
// v6 binds the complete reviewed profile catalog and inventories its union.
const hint_magic = "core-tool-inventory-v6\x00";
const hint_limit = 32 << 20;
const lib_directory = "ZIG_LIB_DIR";
const approval_magic = "core-tool-approval-v3\x00";
const approval_length = approval_magic.len + 65;
// Reviewed pinned distribution; names, version strings and static ELF metadata
// cannot establish that an arbitrary executable has no delegated dependencies.
const approved_zig = "1d314883fd8cf4490c1c29dd73ad8b64e319a8a53c4d9087d1135b52977df37f";
const approved_library = "e6b4a1cd237963366bfba71c9e3b33d3b052274e4963d9a85d26fda3c9adf3f6";
const platform = @import("core_tool_platform");

/// Borrowed command resources. Returned paths have allocator lifetime.
pub const Request = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    executable: []const u8,
    cache: []const u8,
    /// Owned test fixtures only; production has no profile override capability.
    test_profiles: if (builtin.is_test) ?*?[]const platform.Profile else void = if (builtin.is_test) null else {},
};

fn profilesFor(request: Request) []const platform.Profile {
    if (builtin.is_test) {
        if (request.test_profiles) |slot| if (slot.*) |profiles| return profiles;
    }
    return &platform.profiles;
}

/// Content and generation identities must both survive a command unchanged.
pub const Identity = struct {
    path: []const u8,
    digest: Digest,
    generation: Digest,
    native_target: Digest,
    inputs: usize,
    memo_hit: bool,
    cacheable: bool = false,
};

/// Missing tools and racing inputs cannot establish a reusable identity.
pub const Error = error{ OutOfMemory, ToolNotFound, ReadFailed, WriteFailed, SourceChanged };
const Input = struct {
    path: []const u8,
    resolved: []const u8,
    info: ?std.Io.File.Stat,
    role: discovery.Role = .content,
};
const Inventory = struct { inputs: []const Input, generation: Digest, hinted: bool = false };

/// Resolve explicit paths or PATH like a direct guest-tool spawn. The caller
/// must spawn Identity.path: Zig's POSIX spawn searches the parent PATH rather
/// than a separately supplied child environment map. No sibling-tool override.
pub fn resolve(request: Request) Error![]const u8 {
    if (std.mem.indexOfScalar(u8, request.executable, '/') != null)
        return (try executablePath(request, request.executable)) orelse error.ToolNotFound;
    var paths = std.mem.splitScalar(u8, request.environment.get("PATH") orelse std.Io.Threaded.default_PATH, ':');
    while (paths.next()) |directory| {
        const candidate = try std.fs.path.join(request.arena, &.{ directory, request.executable });
        if (try executablePath(request, candidate)) |path| return path;
    }
    return error.ToolNotFound;
}

fn executablePath(request: Request, path: []const u8) Error!?[]const u8 {
    const info = std.Io.Dir.cwd().statFile(request.io, path, .{}) catch return null;
    if (info.kind != .file) return null;
    std.Io.Dir.cwd().access(request.io, path, .{ .execute = true }) catch return null;
    return std.Io.Dir.cwd().realPathFileAlloc(request.io, path, request.arena) catch |err| return readError(err);
}

/// Hash complete content on a miss; stable generations reuse a fixed-size memo.
/// Adjacent lib and ZIG_LIB_DIR are both conservative inputs, including absent
/// roots, directory entries and followed symlinks. Other explicit native/sysroot
/// dependencies remain the driver's responsibility.
pub fn capture(request: Request) Error!Identity {
    return captureMode(request, false);
}

/// Lend only a provisional read-only replay identity. A directory parent must
/// validate unchanged() after every child, before accepting aggregate success.
/// A miss or unproved executable retains strict content/second-scan guards.
pub fn captureReplayParent(request: Request) Error!Identity {
    return captureMode(request, true);
}

/// Read an untrusted warm identity without scanning library generations. Use
/// only for buffered read-only manifest replay, then require unchanged() and a
/// second dependency validation before accepting success. A miss or refusal
/// must discard the candidate and capture strictly before checking or building.
pub fn lookupReplayCandidate(request: Request) Error!?Identity {
    const path = resolve(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const cpu = nativeTarget(request.io) catch return null;
    const inputs = (try inventoryHint(request, path, cpu)) orelse return null;
    const old = candidateExecutable(inputs, path) orelse return null;
    const info = std.Io.Dir.cwd().statFile(request.io, path, .{}) catch return null;
    if (!sameStat(old, info)) return null;
    const identity = inventoryDigest(request, inputs, cpu);
    if (!safeEnvironment(request.environment)) return null;
    if ((try approvalMemo(request, identity)) != true) return null;
    const content = (try memo(request, identity)) orelse return null;
    return .{ .path = path, .digest = content, .generation = identity, .native_target = cpu, .inputs = inputs.len, .memo_hit = true, .cacheable = true };
}

fn candidateExecutable(inputs: []const Input, path: []const u8) ?std.Io.File.Stat {
    for (inputs) |input| {
        if (!std.mem.eql(u8, input.path, path)) continue;
        if (!std.mem.eql(u8, input.resolved, path)) return null;
        const info = input.info orelse return null;
        return if (info.kind == .file) info else null;
    }
    return null;
}

fn captureMode(request: Request, provisional: bool) Error!Identity {
    const path = try resolve(request);
    const cpu = try nativeTarget(request.io);
    const known = try inventoryHint(request, path, cpu);
    const first = if (known) |inputs| (try refresh(request, inputs, cpu)) orelse try inventory(request, path, cpu) else try inventory(request, path, cpu);
    const found = try memo(request, first.generation);
    const content = found orelse try contents(request, path, first.inputs, cpu);
    const cacheable = try approvedClosure(request, path, first, cpu);
    const may_lend = provisional and found != null and cacheable;
    if (!may_lend) {
        const second_path = try resolve(request);
        if (!std.mem.eql(u8, path, second_path)) return error.SourceChanged;
        const second_cpu = try nativeTarget(request.io);
        const second = (try refresh(request, first.inputs, second_cpu)) orelse try inventory(request, second_path, second_cpu);
        if (!std.mem.eql(u8, &first.generation, &second.generation)) return error.SourceChanged;
    }
    if (found == null) try publish(request, first.generation, content);
    if (!first.hinted or found == null) try publishHint(request, path, cpu, first.inputs);
    return .{ .path = path, .digest = content, .generation = first.generation, .native_target = cpu, .inputs = first.inputs.len, .memo_hit = found != null, .cacheable = cacheable };
}

/// Revalidate tool selection, CPU and every library generation before replay or
/// publication. An unchanged-content rewrite is still a changed command input.
pub fn unchanged(request: Request, original: Identity) Error!bool {
    const path = try resolve(request);
    if (!std.mem.eql(u8, path, original.path)) return false;
    const cpu = try nativeTarget(request.io);
    const known = try inventoryHint(request, path, cpu);
    const current = if (known) |inputs| (try refresh(request, inputs, cpu)) orelse try inventory(request, path, cpu) else try inventory(request, path, cpu);
    return std.mem.eql(u8, &current.generation, &original.generation);
}

/// Detect the current native CPU and Core code-generation flags without a tool.
pub fn nativeTarget(io: std.Io) Error!Digest {
    const native = std.zig.system.resolveTargetQuery(io, .{ .cpu_model = .native }) catch return error.ReadFailed;
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, "core-native-cpu-v2");
    field(&hash, @tagName(native.cpu.arch));
    field(&hash, native.cpu.model.name);
    field(&hash, native.cpu.features.asBytes());
    field(&hash, @tagName(native.os.tag));
    field(&hash, @tagName(native.abi));
    field(&hash, target.triple);
    field(&hash, target_policy.native_link_target);
    for (target.cpu_flags) |flag| field(&hash, flag);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Cheap executable generation check for a provisional parent ticket.
pub fn executableGeneration(request: Request, path: []const u8) Error!Digest {
    const info = std.Io.Dir.cwd().statFile(request.io, path, .{}) catch return error.ReadFailed;
    var hash = std.crypto.hash.Blake3.init(.{});
    generation(&hash, .{ .path = path, .resolved = path, .info = info });
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn inventory(request: Request, path: []const u8, cpu: Digest) Error!Inventory {
    var inputs: std.ArrayList(Input) = .empty;
    var visited: std.StringHashMapUnmanaged(void) = .empty;
    defer visited.deinit(request.arena);
    _ = try addInput(request, &inputs, path);
    // A library root is one input: its own generation changes when entries are added,
    // removed or retargeted. Its contents are reviewed once, at approval, and that
    // verdict is memoized by this generation; an installed toolchain does not change
    // files in place, and walking ~24k library files on every build cost ~65 ms.
    const adjacent = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(path) orelse ".", "lib" });
    try libraryRoot(request, &inputs, &visited, adjacent);
    if (request.environment.get(lib_directory)) |override| {
        const absolute = try absolutePath(request, override);
        try libraryRoot(request, &inputs, &visited, absolute);
    }
    for (profilesFor(request)) |profile| {
        for (profile.runtime.files) |input| {
            if (namedInput(inputs.items, input.path) == null) _ = try addInput(request, &inputs, input.path);
        }
        if (namedInput(inputs.items, profile.runtime.preload) == null) _ = try addInput(request, &inputs, profile.runtime.preload);
    }
    for (try discovery.catalogPaths(request.arena, path, profilesFor(request))) |entry| {
        // An already inventoried library/runtime path retains its full guard.
        if (namedInput(inputs.items, entry.name) != null) continue;
        try inputs.append(request.arena, try snapshot(request, entry.name, entry.role));
    }
    std.mem.sort(Input, inputs.items, {}, before);
    return .{ .inputs = inputs.items, .generation = inventoryDigest(request, inputs.items, cpu) };
}

fn inventoryDigest(request: Request, inputs: []const Input, cpu: Digest) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, "core-tool-generations-v4");
    discovery.profilePolicy(std.crypto.hash.Blake3, &hash, profilesFor(request));
    field(&hash, &cpu);
    for (inputs) |input| generation(&hash, input);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn refresh(request: Request, inputs: []const Input, cpu: Digest) Error!?Inventory {
    const current = try request.arena.alloc(Input, inputs.len);
    for (inputs, current) |old, *input| {
        const info: ?std.Io.File.Stat = std.Io.Dir.cwd().statFile(request.io, old.path, .{}) catch |err| switch (err) {
            error.FileNotFound => null,
            error.NotDir => if (old.role != .content) null else return error.ReadFailed,
            else => return error.ReadFailed,
        };
        if (old.info == null or info == null) {
            if (old.info != null or info != null) return null;
        } else if ((old.info.?.kind == .directory or info.?.kind == .directory) and old.role != .predicate) {
            if (!sameStat(old.info.?, info.?)) return null;
        } else if (old.info.?.kind != info.?.kind) return null;
        if (info != null and (old.role != .content or !std.mem.eql(u8, old.path, old.resolved))) {
            const resolved = std.Io.Dir.cwd().realPathFileAlloc(request.io, old.path, request.arena) catch |err| return readError(err);
            if (!std.mem.eql(u8, resolved, old.resolved)) return null;
        }
        input.* = .{ .path = old.path, .resolved = old.resolved, .info = info, .role = old.role };
    }
    return .{ .inputs = current, .generation = inventoryDigest(request, current, cpu), .hinted = true };
}

/// The root of a library tree as one input; an absent root is an absent input.
fn libraryRoot(request: Request, inputs: *std.ArrayList(Input), visited: *std.StringHashMapUnmanaged(void), path: []const u8) Error!void {
    const input = try addInput(request, inputs, path);
    const info = input.info orelse return;
    if (info.kind != .directory) return error.ReadFailed;
    try visited.put(request.arena, input.resolved, {});
}

fn library(request: Request, inputs: *std.ArrayList(Input), visited: *std.StringHashMapUnmanaged(void), path: []const u8) Error!void {
    const input = try addInput(request, inputs, path);
    const info = input.info orelse return;
    if (info.kind != .directory) return error.ReadFailed;
    if (visited.contains(input.resolved)) return;
    try visited.put(request.arena, input.resolved, {});
    var directory = std.Io.Dir.cwd().openDir(request.io, input.resolved, .{ .iterate = true }) catch return error.ReadFailed;
    defer directory.close(request.io);
    var walker = try directory.walk(request.arena);
    defer walker.deinit();
    while (walker.next(request.io) catch return error.ReadFailed) |entry| {
        const child = try std.fs.path.join(request.arena, &.{ input.resolved, entry.path });
        if (entry.kind == .sym_link) {
            const linked = std.Io.Dir.cwd().statFile(request.io, child, .{}) catch return error.ReadFailed;
            if (linked.kind == .directory) {
                try library(request, inputs, visited, child);
                continue;
            }
        }
        _ = try addInput(request, inputs, child);
    }
}

fn addInput(request: Request, inputs: *std.ArrayList(Input), path: []const u8) Error!Input {
    const input = try snapshot(request, path, .content);
    try inputs.append(request.arena, input);
    return input;
}

fn snapshot(request: Request, path: []const u8, role: discovery.Role) Error!Input {
    const info: ?std.Io.File.Stat = std.Io.Dir.cwd().statFile(request.io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => null,
        error.NotDir => if (role != .content) null else return error.ReadFailed,
        else => return error.ReadFailed,
    };
    const resolved = if (info != null) std.Io.Dir.cwd().realPathFileAlloc(request.io, path, request.arena) catch |err| return readError(err) else path;
    return .{ .path = path, .resolved = resolved, .info = info, .role = role };
}

fn contents(request: Request, path: []const u8, inputs: []const Input, cpu: Digest) Error!Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, "core-tool-content-v4");
    discovery.profilePolicy(std.crypto.hash.Blake3, &hash, profilesFor(request));
    field(&hash, &cpu);
    // Profile membership can differ while every enumerated file is identical.
    // Bind the observed state under each profile ID, not just the allowlist.
    for (profilesFor(request)) |profile| {
        field(&hash, profile.id);
        field(&hash, &try discovery.profileState(request.arena, request.io, path, profile.discovery));
    }
    for (inputs) |input| {
        field(&hash, input.path);
        field(&hash, input.resolved);
        field(&hash, @tagName(input.role));
        const info = input.info orelse {
            field(&hash, "absent");
            continue;
        };
        field(&hash, @tagName(info.kind));
        if (info.kind == .file) field(&hash, &try fileContent(request, input));
        // A library root stands for its tree: its entries' additions, removals and
        // retargets reach the content identity through the root's own generation.
        if (info.kind == .directory and input.role == .content) generation(&hash, input);
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn fileContent(request: Request, input: Input) Error!Digest {
    return fileHash(std.crypto.hash.Blake3, request, input);
}

fn fileHash(comptime Hash: type, request: Request, input: Input) Error!Digest {
    const file = std.Io.Dir.cwd().openFile(request.io, input.resolved, .{}) catch return error.ReadFailed;
    defer file.close(request.io);
    if (!sameStat(input.info.?, file.stat(request.io) catch return error.ReadFailed)) return error.SourceChanged;
    var hash = Hash.init(.{});
    var buffer: [64 << 10]u8 = undefined;
    var offset: u64 = 0;
    while (true) {
        const count = file.readPositionalAll(request.io, &buffer, offset) catch return error.ReadFailed;
        hash.update(buffer[0..count]);
        offset += count;
        if (count < buffer.len) break;
    }
    if (offset != input.info.?.size) return error.SourceChanged;
    if (!sameStat(input.info.?, file.stat(request.io) catch return error.ReadFailed)) return error.SourceChanged;
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn memo(request: Request, identity: Digest) Error!?Digest {
    const path = try memoPath(request, identity);
    const bytes = std.Io.Dir.cwd().readFileAlloc(request.io, path, request.arena, .limited(memo_length + 1)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (bytes.len != memo_length or !std.mem.eql(u8, bytes[0..magic.len], magic)) return null;
    if (!std.mem.eql(u8, bytes[magic.len..][0..32], &identity)) return null;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes[0 .. memo_length - 32], &checksum, .{});
    if (!std.mem.eql(u8, bytes[memo_length - 32 ..], &checksum)) return null;
    return bytes[magic.len + 32 ..][0..32].*;
}

fn publish(request: Request, identity: Digest, content: Digest) Error!void {
    const path = try memoPath(request, identity);
    var bytes: [memo_length]u8 = undefined;
    @memcpy(bytes[0..magic.len], magic);
    @memcpy(bytes[magic.len..][0..32], &identity);
    @memcpy(bytes[magic.len + 32 ..][0..32], &content);
    std.crypto.hash.Blake3.hash(bytes[0 .. memo_length - 32], bytes[memo_length - 32 ..], .{});
    try publishBytes(request, path, &bytes);
}

fn publishBytes(request: Request, path: []const u8, bytes: []const u8) Error!void {
    const cwd = std.Io.Dir.cwd();
    cwd.createDirPath(request.io, std.fs.path.dirname(path).?) catch return error.WriteFailed;
    var nonce: [16]u8 = undefined;
    std.Io.random(request.io, &nonce);
    const pending = try std.fmt.allocPrint(request.arena, "{s}.{s}.pending", .{ path, std.fmt.bytesToHex(nonce, .lower) });
    defer retire(request.io, pending);
    cwd.writeFile(request.io, .{ .sub_path = pending, .data = bytes }) catch return error.WriteFailed;
    cwd.rename(pending, cwd, path, request.io) catch return error.WriteFailed;
}

fn memoPath(request: Request, identity: Digest) Error![]const u8 {
    return std.fmt.allocPrint(request.arena, "{s}/tool-identity/{s}.memo", .{ try cacheRoot(request), std.fmt.bytesToHex(identity, .lower) });
}

fn cacheRoot(request: Request) Error![]const u8 {
    if (request.environment.get("XDG_CACHE_HOME")) |root| if (root.len != 0)
        return std.fs.path.join(request.arena, &.{ root, "mylang", "core-tools-v1" });
    if (request.environment.get("HOME")) |root| if (root.len != 0)
        return std.fs.path.join(request.arena, &.{ root, ".cache", "mylang", "core-tools-v1" });
    return request.cache;
}

fn hintKey(request: Request, path: []const u8, cpu: Digest) Error!Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, hint_magic);
    field(&hash, path);
    field(&hash, &cpu);
    discovery.profilePolicy(std.crypto.hash.Blake3, &hash, profilesFor(request));
    if (request.environment.get(lib_directory)) |override| {
        field(&hash, try absolutePath(request, override));
    } else field(&hash, "");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn hintPath(request: Request, path: []const u8, cpu: Digest) Error![]const u8 {
    return std.fmt.allocPrint(request.arena, "{s}/tool-identity/{s}.inventory", .{ try cacheRoot(request), std.fmt.bytesToHex(try hintKey(request, path, cpu), .lower) });
}

fn inventoryHint(request: Request, path: []const u8, cpu: Digest) Error!?[]const Input {
    const bytes = std.Io.Dir.cwd().readFileAlloc(request.io, try hintPath(request, path, cpu), request.arena, .limited(hint_limit)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (bytes.len < hint_magic.len + 68) return null;
    if (!std.mem.eql(u8, bytes[0..hint_magic.len], hint_magic)) return null;
    if (!std.mem.eql(u8, bytes[hint_magic.len..][0..32], &try hintKey(request, path, cpu))) return null;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes[0 .. bytes.len - 32], &checksum, .{});
    if (!std.mem.eql(u8, bytes[bytes.len - 32 ..], &checksum)) return null;
    return decodeHint(request.arena, bytes[hint_magic.len + 32 .. bytes.len - 32]) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

const HintError = std.Io.Reader.Error || error{ OutOfMemory, MalformedHint };

fn decodeHint(a: std.mem.Allocator, bytes: []const u8) HintError![]const Input {
    var reader = std.Io.Reader.fixed(bytes);
    const count = try reader.takeInt(u32, .little);
    if (count == 0 or count > 100000) return error.MalformedHint;
    const inputs = try a.alloc(Input, count);
    for (inputs, 0..) |*input, index| {
        const path = try reader.take(try reader.takeInt(u32, .little));
        const resolved = try reader.take(try reader.takeInt(u32, .little));
        if (!std.fs.path.isAbsolute(path) or !std.fs.path.isAbsolute(resolved)) return error.MalformedHint;
        const role = std.enums.fromInt(discovery.Role, try reader.takeByte()) orelse return error.MalformedHint;
        input.* = .{ .path = path, .resolved = resolved, .info = try decodeStat(&reader), .role = role };
        if (index != 0 and before({}, input.*, inputs[index - 1])) return error.MalformedHint;
    }
    if (reader.bufferedLen() != 0) return error.MalformedHint;
    return inputs;
}

fn decodeStat(reader: *std.Io.Reader) HintError!?std.Io.File.Stat {
    const present = try reader.takeByte();
    if (present == 0) return null;
    if (present != 1) return error.MalformedHint;
    const inode = try reader.takeInt(u64, .little);
    const size = try reader.takeInt(u64, .little);
    const mtime = try reader.takeInt(i128, .little);
    const ctime = try reader.takeInt(i128, .little);
    const mode = try reader.takeInt(u32, .little);
    const kind = std.enums.fromInt(std.Io.File.Kind, try reader.takeByte()) orelse return error.MalformedHint;
    const modified = std.math.cast(i96, mtime) orelse return error.MalformedHint;
    const changed = std.math.cast(i96, ctime) orelse return error.MalformedHint;
    return .{ .inode = inode, .size = size, .mtime = .{ .nanoseconds = modified }, .ctime = .{ .nanoseconds = changed }, .permissions = .fromMode(mode), .kind = kind, .nlink = 0, .atime = null, .block_size = 1 };
}

fn publishHint(request: Request, path: []const u8, cpu: Digest, inputs: []const Input) Error!void {
    var text: std.Io.Writer.Allocating = .init(request.arena);
    const writer = &text.writer;
    try writer.writeAll(hint_magic);
    try writer.writeAll(&try hintKey(request, path, cpu));
    try writer.writeInt(u32, @intCast(inputs.len), .little);
    for (inputs) |input| try encodeInput(writer, input);
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(text.written(), &checksum, .{});
    try writer.writeAll(&checksum);
    try publishBytes(request, try hintPath(request, path, cpu), text.written());
}

fn encodeInput(writer: *std.Io.Writer, input: Input) Error!void {
    try writer.writeInt(u32, @intCast(input.path.len), .little);
    try writer.writeAll(input.path);
    try writer.writeInt(u32, @intCast(input.resolved.len), .little);
    try writer.writeAll(input.resolved);
    try writer.writeByte(@backingInt(input.role));
    const info = input.info orelse return writer.writeByte(0);
    try writer.writeByte(1);
    try writer.writeInt(u64, info.inode, .little);
    try writer.writeInt(u64, info.size, .little);
    try writer.writeInt(i128, info.mtime.nanoseconds, .little);
    try writer.writeInt(i128, info.ctime.nanoseconds, .little);
    try writer.writeInt(u32, info.permissions.toMode(), .little);
    try writer.writeByte(@intCast(@backingInt(info.kind)));
}

fn absolutePath(request: Request, path: []const u8) Error![]const u8 {
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(request.io, ".", request.arena) catch |err| return readError(err);
    return std.fs.path.resolve(request.arena, &.{ cwd, path });
}

fn generation(hash: *std.crypto.hash.Blake3, input: Input) void {
    field(hash, input.path);
    field(hash, input.resolved);
    field(hash, @tagName(input.role));
    const info = input.info orelse {
        field(hash, "absent");
        return;
    };
    field(hash, @tagName(info.kind));
    integer(hash, info.inode);
    if (input.role == .predicate and info.kind == .directory) {
        integer(hash, info.permissions.toMode());
        return;
    }
    integer(hash, info.size);
    integer(hash, info.mtime.nanoseconds);
    integer(hash, info.ctime.nanoseconds);
    integer(hash, info.permissions.toMode());
}

fn sameStat(left: std.Io.File.Stat, right: std.Io.File.Stat) bool {
    const first: Input = .{ .path = "", .resolved = "", .info = left };
    const second: Input = .{ .path = "", .resolved = "", .info = right };
    var a = std.crypto.hash.Blake3.init(.{});
    var b = std.crypto.hash.Blake3.init(.{});
    generation(&a, first);
    generation(&b, second);
    var x: Digest = undefined;
    var y: Digest = undefined;
    a.final(&x);
    b.final(&y);
    return std.mem.eql(u8, &x, &y);
}

fn field(hash: *std.crypto.hash.Blake3, bytes: []const u8) void {
    integer(hash, bytes.len);
    hash.update(bytes);
}

fn integer(hash: *std.crypto.hash.Blake3, value: i128) void {
    var bytes: [16]u8 = undefined;
    std.mem.writeInt(i128, &bytes, value, .little);
    hash.update(&bytes);
}

fn before(_: void, left: Input, right: Input) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}

fn readError(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
}

fn retire(io: std.Io, path: []const u8) void {
    std.Io.Dir.cwd().deleteFile(io, path) catch return;
}

fn safeEnvironment(environment: *const std.process.Environ.Map) bool {
    const external = [_][]const u8{
        "CPATH",                      "C_INCLUDE_PATH",           "CPLUS_INCLUDE_PATH",         "OBJC_INCLUDE_PATH",
        "LIBRARY_PATH",               "COMPILER_PATH",            "GCC_EXEC_PREFIX",            "SDKROOT",
        "SYSROOT",                    "CCC_OVERRIDE_OPTIONS",     "CCC_ADD_ARGS",               "CLANG_CONFIG_FILE_SYSTEM_DIR",
        "CLANG_CONFIG_FILE_USER_DIR", "ZIG_LIBC",                 "ZIG_BUILD_RUNNER",           "ZIG_DEBUG_CMD",
        "CC",                         "CXX",                      "AR",                         "AS",
        "LD",                         "RANLIB",                   "NM",                         "OBJCOPY",
        "STRIP",                      "MACOSX_DEPLOYMENT_TARGET", "IPHONEOS_DEPLOYMENT_TARGET", "RC_DEBUG_OPTIONS",
        "GLIBC_TUNABLES",
    };
    for (external) |key| if (environment.get(key)) |value| if (value.len != 0) return false;
    var entries = environment.iterator();
    while (entries.next()) |entry| {
        const loader = std.mem.startsWith(u8, entry.key_ptr.*, "LD_") or std.mem.startsWith(u8, entry.key_ptr.*, "DYLD_");
        if (loader and entry.value_ptr.len != 0) return false;
    }
    return true;
}

fn approvalKey(request: Request, identity: Digest) Digest {
    var hash = std.crypto.hash.Blake3.init(.{});
    field(&hash, approval_magic);
    field(&hash, &identity);
    field(&hash, approved_zig);
    field(&hash, approved_library);
    discovery.profilePolicy(std.crypto.hash.Blake3, &hash, profilesFor(request));
    field(&hash, if (builtin.is_test) "owned-test-fixtures-v1" else "production");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn approvalPath(request: Request, identity: Digest) Error![]const u8 {
    return std.fmt.allocPrint(request.arena, "{s}/approval-v3/{s}.memo", .{ try cacheRoot(request), std.fmt.bytesToHex(approvalKey(request, identity), .lower) });
}

fn approvalMemo(request: Request, identity: Digest) Error!?bool {
    const bytes = std.Io.Dir.cwd().readFileAlloc(request.io, try approvalPath(request, identity), request.arena, .limited(approval_length + 1)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    if (bytes.len != approval_length or !std.mem.eql(u8, bytes[0..approval_magic.len], approval_magic)) return null;
    if (!std.mem.eql(u8, bytes[approval_magic.len..][0..32], &approvalKey(request, identity))) return null;
    if (bytes[approval_magic.len + 32] > 1) return null;
    var checksum: Digest = undefined;
    std.crypto.hash.Blake3.hash(bytes[0 .. bytes.len - 32], &checksum, .{});
    if (!std.mem.eql(u8, bytes[bytes.len - 32 ..], &checksum)) return null;
    return bytes[approval_magic.len + 32] == 1;
}

fn publishApproval(request: Request, identity: Digest, approved: bool) Error!void {
    var bytes: [approval_length]u8 = undefined;
    @memcpy(bytes[0..approval_magic.len], approval_magic);
    @memcpy(bytes[approval_magic.len..][0..32], &approvalKey(request, identity));
    bytes[approval_magic.len + 32] = @intFromBool(approved);
    std.crypto.hash.Blake3.hash(bytes[0 .. bytes.len - 32], bytes[bytes.len - 32 ..], .{});
    try publishBytes(request, try approvalPath(request, identity), &bytes);
}

fn approvedClosure(request: Request, path: []const u8, first: Inventory, cpu: Digest) Error!bool {
    if (!safeEnvironment(request.environment)) return false;
    if (try approvalMemo(request, first.generation)) |approved| return approved;
    const approved = try reviewClosure(request, path, first.inputs);
    const final = (try refresh(request, first.inputs, cpu)) orelse return error.SourceChanged;
    if (!std.mem.eql(u8, &first.generation, &final.generation)) return error.SourceChanged;
    try publishApproval(request, first.generation, approved);
    return approved;
}

fn matchesDigest(digest: Digest, expected: []const u8) bool {
    const hexadecimal = std.fmt.bytesToHex(digest, .lower);
    return std.mem.eql(u8, &hexadecimal, expected);
}

fn reviewedExecutable(digest: Digest) bool {
    if (matchesDigest(digest, approved_zig)) return true;
    if (!builtin.is_test) return false;
    // Tiny owned ELF fixtures never execute a compiler. Production has no
    // caller-provided trust switch and never approves these content identities.
    if (matchesDigest(digest, "2398875e514133130959973c3e5b86d2a3d99c1035ec315ee6ac102406a302fb")) return true;
    return matchesDigest(digest, "b6106403c349f4f3df7c30a9417f5a028fb6a73c7c993336787a7b63c1afff50");
}

fn reviewedLibrary(digest: Digest) bool {
    if (matchesDigest(digest, approved_library)) return true;
    if (!builtin.is_test) return false;
    return matchesDigest(digest, "ebac2ea5add534a13068bbc01177980c5ab49aa30e14435f8c061d4a966ebbf9");
}

fn reviewClosure(request: Request, path: []const u8, inputs: []const Input) Error!bool {
    // This explicit target confines libc headers/CRT/link inputs to the reviewed
    // bundled distribution. Default native discovery also reads /usr inputs.
    if (!std.mem.eql(u8, target_policy.native_link_target, "x86_64-linux-gnu.2.31")) return false;
    if (!try standalone(request, path)) return false;
    const executable = candidateExecutable(inputs, path) orelse return false;
    const digest = try fileHash(std.crypto.hash.sha2.Sha256, request, .{ .path = path, .resolved = path, .info = executable });
    if (!reviewedExecutable(digest)) return false;
    const adjacent = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(path).?, "lib" });
    if (!try approvedLibrary(request, inputs, adjacent)) return false;
    if (request.environment.get(lib_directory)) |override| {
        if (!try approvedLibrary(request, inputs, try absolutePath(request, override))) return false;
    }
    return approvedProfiles(request, path, inputs, profilesFor(request));
}

fn namedInput(inputs: []const Input, path: []const u8) ?Input {
    for (inputs) |input| if (std.mem.eql(u8, input.path, path)) return input;
    return null;
}

fn approvedProfiles(request: Request, path: []const u8, inputs: []const Input, profiles: []const platform.Profile) Error!bool {
    for (profiles) |profile| {
        if (!try approvedRuntimeProfile(request, inputs, profile.runtime)) continue;
        if (try discovery.approvedProfile(request.arena, request.io, path, profile.discovery)) return true;
    }
    return false;
}

fn approvedRuntime(request: Request, inputs: []const Input) Error!bool {
    return approvedRuntimeProfile(request, inputs, profilesFor(request)[0].runtime);
}

fn approvedRuntimeProfile(request: Request, inputs: []const Input, runtime: platform.Runtime) Error!bool {
    const preload = namedInput(inputs, runtime.preload) orelse return false;
    if (preload.info) |info| if (info.kind != .file or info.size != 0) return false;
    for (runtime.files) |expected| {
        const input = namedInput(inputs, expected.path) orelse return false;
        const info = input.info orelse return false;
        if (info.kind != .file) return false;
        if (!std.mem.eql(u8, input.resolved, expected.resolved)) return false;
        if (!matchesDigest(try fileHash(std.crypto.hash.sha2.Sha256, request, input), expected.sha256)) return false;
    }
    return true;
}

fn approvedLibrary(request: Request, inputs: []const Input, path: []const u8) Error!bool {
    const root = std.Io.Dir.cwd().realPathFileAlloc(request.io, path, request.arena) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    // The build inventory holds only the root; review the complete tree here.
    if (namedInput(inputs, path) == null and namedInput(inputs, root) == null) return false;
    var walked: std.ArrayList(Input) = .empty;
    var visited: std.StringHashMapUnmanaged(void) = .empty;
    defer visited.deinit(request.arena);
    library(request, &walked, &visited, root) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    const digest = (try libraryContent(request, walked.items, root)) orelse return false;
    return reviewedLibrary(digest);
}

const LibraryInput = struct { relative: []const u8, original: Input };

fn relativeLibraryInput(root: []const u8, input: Input) ?[]const u8 {
    if (std.mem.eql(u8, input.resolved, root)) return "";
    if (!std.mem.eql(u8, input.path, input.resolved)) return null;
    if (!std.mem.startsWith(u8, input.path, root)) return null;
    if (input.path.len <= root.len or input.path[root.len] != '/') return null;
    return input.path[root.len + 1 ..];
}

fn libraryContent(request: Request, inputs: []const Input, root: []const u8) Error!?Digest {
    var chosen: std.ArrayList(LibraryInput) = .empty;
    for (inputs) |input| {
        const nested = std.mem.startsWith(u8, input.path, root) and input.path.len > root.len;
        if (nested and input.path[root.len] == '/' and !std.mem.eql(u8, input.path, input.resolved)) return null;
        if (relativeLibraryInput(root, input)) |relative| try chosen.append(request.arena, .{ .relative = relative, .original = input });
    }
    std.mem.sort(LibraryInput, chosen.items, {}, libraryBefore);
    if (chosen.items.len == 0 or chosen.items[0].relative.len != 0) return null;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    shaField(&hash, "core-approved-zig-library-v1");
    for (chosen.items, 0..) |input, index| {
        if (index != 0 and std.mem.eql(u8, chosen.items[index - 1].relative, input.relative)) continue;
        const info = input.original.info orelse return null;
        if (info.kind != .file and info.kind != .directory) return null;
        shaField(&hash, input.relative);
        shaField(&hash, @tagName(info.kind));
        if (info.kind == .file) shaField(&hash, &try fileHash(std.crypto.hash.sha2.Sha256, request, input.original));
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn libraryBefore(_: void, left: LibraryInput, right: LibraryInput) bool {
    return std.mem.lessThan(u8, left.relative, right.relative);
}

fn shaField(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    var length: [16]u8 = undefined;
    std.mem.writeInt(u128, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

fn standalone(request: Request, path: []const u8) Error!bool {
    const file = std.Io.Dir.cwd().openFile(request.io, path, .{}) catch return error.ReadFailed;
    defer file.close(request.io);
    var header: [64]u8 = undefined;
    if ((file.readPositionalAll(request.io, &header, 0) catch return error.ReadFailed) != header.len) return false;
    if (!std.mem.eql(u8, header[0..4], "\x7fELF")) return false;
    if (header[4] != 2 or header[5] != 1) return false;
    const kind = std.mem.readInt(u16, header[16..18], .little);
    if (kind != @backingInt(std.elf.ET.EXEC) and kind != @backingInt(std.elf.ET.DYN)) return false;
    const offset = std.mem.readInt(u64, header[32..40], .little);
    const width = std.mem.readInt(u16, header[54..56], .little);
    const count = std.mem.readInt(u16, header[56..58], .little);
    if (width != 56 or count == 0 or count > 128) return false;
    var entry: [56]u8 = undefined;
    for (0..count) |index| {
        const position = std.math.add(u64, offset, index * width) catch return false;
        if ((file.readPositionalAll(request.io, &entry, position) catch return error.ReadFailed) != entry.len) return false;
        const tag = std.mem.readInt(u32, entry[0..4], .little);
        if (tag == @backingInt(std.elf.PT.INTERP) or tag == @backingInt(std.elf.PT.DYNAMIC)) return false;
    }
    if (request.environment.get("ZIG_LIBC")) |libc| if (libc.len != 0) return false;
    const lib = request.environment.get(lib_directory) orelse try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(path).?, "lib" });
    const standard = try std.fs.path.join(request.arena, &.{ lib, "std", "std.zig" });
    const info = std.Io.Dir.cwd().statFile(request.io, standard, .{}) catch return false;
    return info.kind == .file;
}

const Fixture = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    environment: std.process.Environ.Map,
    profiles: ?[]const platform.Profile = null,

    fn init(allocator: std.mem.Allocator) Fixture {
        return .{ .temporary = std.testing.tmpDir(.{}), .arena = .init(allocator), .environment = .init(allocator) };
    }
    fn deinit(self: *Fixture) void {
        self.environment.deinit();
        self.arena.deinit();
        self.temporary.cleanup();
    }
    fn request(self: *Fixture) !Request {
        const a = self.arena.allocator();
        const root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        try self.environment.put("PATH", root);
        return .{ .arena = a, .io = std.testing.io, .environment = &self.environment, .executable = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }), .test_profiles = &self.profiles };
    }
    fn tool(self: *Fixture, bytes: []const u8) !void {
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "zig", .data = bytes });
        try self.temporary.dir.setFilePermissions(std.testing.io, "zig", .executable_file, .{});
    }

    // A structural ELF fixture for identity tests; it never executes a compiler.
    fn staticTool(self: *Fixture, marker: u8) !void {
        var bytes: [120]u8 = @splat(0);
        @memcpy(bytes[0..4], "\x7fELF");
        bytes[4] = 2;
        bytes[5] = 1;
        std.mem.writeInt(u16, bytes[16..18], @backingInt(std.elf.ET.EXEC), .little);
        std.mem.writeInt(u64, bytes[32..40], 64, .little);
        std.mem.writeInt(u16, bytes[54..56], 56, .little);
        std.mem.writeInt(u16, bytes[56..58], 1, .little);
        std.mem.writeInt(u32, bytes[64..68], @backingInt(std.elf.PT.LOAD), .little);
        bytes[119] = marker;
        try self.tool(&bytes);
        try self.temporary.dir.createDirPath(std.testing.io, "lib/std");
        try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib/std/std.zig", .data = "first" });
        if (self.profiles == null) {
            const request_value = try self.request();
            const root = std.fs.path.dirname(request_value.cache).?;
            const runtime = try std.fs.path.join(request_value.arena, &.{ root, "native-runtime" });
            const distro = try std.fs.path.join(request_value.arena, &.{ root, "native-distro" });
            try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "native-runtime", .data = "owned runtime" });
            try self.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "native-distro", .data = "owned distro" });
            const profiles = try request_value.arena.alloc(platform.Profile, 1);
            profiles[0] = try ownedProfile(request_value, try resolve(request_value), runtime, distro);
            self.profiles = profiles;
        }
    }

    fn replaceSnapshot(inputs: []Input, path: []const u8, resolved: []const u8, info: ?std.Io.File.Stat) void {
        for (inputs) |*input| if (std.mem.eql(u8, input.path, path)) {
            input.resolved = resolved;
            input.info = info;
        };
    }
};

// spec-case: NEW-CORE-S4-TEST-3
test "tool identity resolves executable PATH and propagates allocation failure" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try std.testing.expectError(error.ToolNotFound, resolve(request));
    try fixture.tool("first");
    const found = try resolve(request);
    try std.testing.expect(std.fs.path.isAbsolute(found));
    var failing = request;
    failing.arena = std.testing.failing_allocator;
    try std.testing.expectError(error.OutOfMemory, resolve(failing));
}

// spec-case: NEW-CORE-S4-TEST-3
test "tool memo is reusable and corruption is a content rehash" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    const cold = try capture(request);
    const warm = try capture(request);
    try std.testing.expect(!cold.memo_hit);
    try std.testing.expect(!cold.cacheable);
    try std.testing.expectEqual(cold.generation, warm.generation);
    try std.testing.expect(warm.memo_hit);
    try std.testing.expectEqual(cold.digest, warm.digest);
    try std.testing.expect(try unchanged(request, warm));
    const path = try memoPath(request, cold.generation);
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = path, .data = "damaged" });
    const repaired = try capture(request);
    try std.testing.expect(!repaired.memo_hit);
    try std.testing.expectEqual(cold.digest, repaired.digest);
}

// spec-case: NEW-CORE-S4-TEST-3
test "same-size executable edit with restored mtime invalidates tool identity" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    const original = try capture(request);
    const info = try fixture.temporary.dir.statFile(request.io, "zig", .{});
    try fixture.tool("other");
    try fixture.temporary.dir.setTimestamps(request.io, "zig", .{ .modify_timestamp = .init(info.mtime) });
    try std.testing.expect(!try unchanged(request, original));
    const changed = try capture(request);
    try std.testing.expect(!changed.memo_hit);
    try std.testing.expect(!std.mem.eql(u8, &changed.digest, &original.digest));
}

// spec-case: NEW-CORE-S4-TEST-3
// spec: NEW-CORE-S4-TOOL-1
test "library edits additions removals and an override invalidate tool identity" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    try fixture.temporary.dir.createDirPath(request.io, "lib");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/header.h", .data = "first" });
    const original = try capture(request);
    // An in-place edit inside an installed library is not a build input; only the
    // root's entries are.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/header.h", .data = "other" });
    try std.testing.expect(try unchanged(request, original));
    const edited = try capture(request);
    try std.testing.expectEqual(original.digest, edited.digest);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/added.h", .data = "added" });
    try std.testing.expect(!try unchanged(request, edited));
    const added = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &added.digest, &edited.digest));
    try fixture.temporary.dir.deleteFile(request.io, "lib/header.h");
    const removed = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &removed.digest, &added.digest));
    try fixture.temporary.dir.createDirPath(request.io, "override");
    const override = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(original.path).?, "override" });
    try fixture.environment.put(lib_directory, override);
    const overridden = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &overridden.digest, &removed.digest));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "override/custom.h", .data = "custom" });
    try std.testing.expect(!try unchanged(request, overridden));
}

// spec-case: NEW-CORE-S4-TEST-3
test "PATH selection and linked library content are command dependencies" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    try fixture.temporary.dir.createDirPath(request.io, "other");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "other/zig", .data = "other" });
    try fixture.temporary.dir.setFilePermissions(request.io, "other/zig", .executable_file, .{});
    const first = try capture(request);
    const root = std.fs.path.dirname(first.path).?;
    try fixture.environment.put("PATH", try std.fs.path.join(request.arena, &.{ root, "other" }));
    try std.testing.expect(!try unchanged(request, first));
    const replaced = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, replaced.path, first.path));
    try fixture.temporary.dir.createDirPath(request.io, "other/lib");
    try fixture.temporary.dir.createDirPath(request.io, "outside");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "outside/header.h", .data = "first" });
    try fixture.temporary.dir.symLink(request.io, "../../outside", "other/lib/include", .{ .is_directory = true });
    const linked = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &linked.digest, &replaced.digest));
    // A linked tree is reviewed at approval, not rescanned per build.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "outside/header.h", .data = "other" });
    try std.testing.expect(try unchanged(request, linked));
    try fixture.temporary.dir.deleteFile(request.io, "other/lib/include");
    try std.testing.expect(!try unchanged(request, linked));
}

// spec-case: NEW-CORE-S4-TEST-3
test "inventoryHint corruption rediscovers libraries and invalid library roots refuse reuse" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    try fixture.temporary.dir.createDirPath(request.io, "lib");
    const original = try capture(request);
    try std.testing.expect((try inventoryHint(request, original.path, original.native_target)) != null);
    const damaged = try hintPath(request, original.path, original.native_target);
    const old_hint = try std.Io.Dir.cwd().readFileAlloc(request.io, damaged, request.arena, .limited(hint_limit));
    @memcpy(old_hint[0..hint_magic.len], "core-tool-inventory-v3\x00");
    std.crypto.hash.Blake3.hash(old_hint[0 .. old_hint.len - 32], old_hint[old_hint.len - 32 ..][0..32], .{});
    std.crypto.hash.Blake3.hash(old_hint[0 .. old_hint.len - 32], old_hint[old_hint.len - 32 ..][0..32], .{});
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = damaged, .data = old_hint });
    try std.testing.expect((try inventoryHint(request, original.path, original.native_target)) == null);
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = damaged, .data = "damaged" });
    try std.testing.expect((try inventoryHint(request, original.path, original.native_target)) == null);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/new.h", .data = "new" });
    const changed = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &changed.digest, &original.digest));
    const warm = try capture(request);
    try std.testing.expect(warm.memo_hit);
    try fixture.temporary.dir.deleteTree(request.io, "lib");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib", .data = "not a library directory" });
    try std.testing.expectError(error.ReadFailed, capture(request));
}

// spec-case: NEW-CORE-S4-TEST-3
test "inventoryHint allocation failure propagates instead of becoming a cache miss" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    const original = try capture(request);
    var failing = request;
    failing.arena = std.testing.failing_allocator;
    try std.testing.expectError(error.OutOfMemory, inventoryHint(failing, original.path, original.native_target));
}

// spec-case: NEW-CORE-S4-TEST-3
test "MalformedHint rejects invalid count relative paths presence and timestamps" {
    const empty: [4]u8 = @splat(0);
    try std.testing.expectError(error.MalformedHint, decodeHint(std.testing.allocator, &empty));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bytes: std.Io.Writer.Allocating = .init(arena.allocator());
    try bytes.writer.writeInt(u32, 1, .little);
    try encodeInput(&bytes.writer, .{ .path = "relative", .resolved = "relative", .info = null });
    try std.testing.expectError(error.MalformedHint, decodeHint(arena.allocator(), bytes.written()));
    var presence = std.Io.Reader.fixed(&.{2});
    try std.testing.expectError(error.MalformedHint, decodeStat(&presence));
    var metadata: [54]u8 = @splat(0);
    metadata[0] = 1;
    metadata[53] = @intCast(@backingInt(std.Io.File.Kind.file));
    std.mem.writeInt(i128, metadata[17..33], std.math.maxInt(i128), .little);
    var timestamp = std.Io.Reader.fixed(&metadata);
    try std.testing.expectError(error.MalformedHint, decodeStat(&timestamp));
}

// spec-case: NEW-CORE-S4-TEST-3
test "fileContent refuses SourceChanged generations and standalone rejects delegated scripts" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    var inputs: std.ArrayList(Input) = .empty;
    const original = try addInput(request, &inputs, try resolve(request));
    try fixture.tool("other");
    try std.testing.expectError(error.SourceChanged, fileContent(request, original));
    try fixture.tool("#!/bin/sh\n# A delegated compiler has dependencies beyond the wrapper bytes.\nexec zig-real \"$@\"\n");
    const script = try captureReplayParent(request);
    try std.testing.expect(!script.cacheable);
    try std.testing.expect(!try standalone(request, script.path));
}

// spec-case: NEW-CORE-S4-TEST-3
test "lookupReplayCandidate misses damaged memos executable edits and allocation failure" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    const candidate = (try lookupReplayCandidate(request)).?;
    try std.testing.expectEqual(original.digest, candidate.digest);
    try std.testing.expect(try unchanged(request, candidate));
    const path = try memoPath(request, original.generation);
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = path, .data = "damaged" });
    try std.testing.expect((try lookupReplayCandidate(request)) == null);
    _ = try capture(request);
    try fixture.staticTool(2);
    try std.testing.expect((try lookupReplayCandidate(request)) == null);
    var failing = request;
    failing.arena = std.testing.failing_allocator;
    try std.testing.expectError(error.OutOfMemory, lookupReplayCandidate(failing));
}

// spec-case: NEW-CORE-S4-TEST-3
test "lookupReplayCandidate library edits and additions require final unchanged refusal" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "other" });
    const edited = (try lookupReplayCandidate(request)).?;
    try std.testing.expectEqual(original.digest, edited.digest);
    try std.testing.expect(try unchanged(request, edited));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/added.h", .data = "added" });
    const expanded = (try lookupReplayCandidate(request)).?;
    try std.testing.expect(!try unchanged(request, expanded));
    const fresh = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &fresh.digest, &original.digest));
}

// spec-case: NEW-CORE-S4-TEST-3
test "closure approval refuses unknown static executables and unknown library contents" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(99);
    const delegated = try capture(request);
    try std.testing.expect(try standalone(request, delegated.path));
    try std.testing.expect(!delegated.cacheable);
    try std.testing.expect((try lookupReplayCandidate(request)) == null);
    try fixture.staticTool(1);
    const approved = try capture(request);
    try std.testing.expect(approved.cacheable);
    // An unreviewed tree is refused whenever its root changes and review reruns.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "unreviewed library" });
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/marker", .data = "root entry" });
    try std.testing.expect(!(try capture(request)).cacheable);
    try fixture.temporary.dir.deleteFile(request.io, "lib/marker");
    try fixture.staticTool(1);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/unreviewed.h", .data = "outside include" });
    try std.testing.expect(!(try capture(request)).cacheable);
}

// spec-case: NEW-CORE-S4-TEST-3
test "approval memo damage is a miss and library aliases cannot hide outside inputs" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    try std.testing.expect(original.cacheable);
    const path = try approvalPath(request, original.generation);
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = path, .data = "damaged" });
    try std.testing.expect((try approvalMemo(request, original.generation)) == null);
    try std.testing.expect((try lookupReplayCandidate(request)) == null);
    try std.testing.expect((try capture(request)).cacheable);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "outside.h", .data = "external contents" });
    try fixture.temporary.dir.symLink(request.io, "../outside.h", "lib/added.h", .{});
    try std.testing.expect(!(try capture(request)).cacheable);
    var failing = request;
    failing.arena = std.testing.failing_allocator;
    try std.testing.expectError(error.OutOfMemory, approvalMemo(failing, original.generation));
}

// spec-case: NEW-CORE-S4-TEST-3
test "approval rejects uncaptured compiler environment paths without publishing trust" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try std.testing.expect((try capture(request)).cacheable);
    for ([_][]const u8{ "CPATH", "C_INCLUDE_PATH", "LIBRARY_PATH", "SDKROOT", "CCC_OVERRIDE_OPTIONS", "ZIG_LIBC", "LD_PRELOAD" }) |key| {
        try fixture.environment.put(key, "/untracked/input");
        try std.testing.expect(!(try captureReplayParent(request)).cacheable);
        try std.testing.expect((try lookupReplayCandidate(request)) == null);
        _ = fixture.environment.swapRemove(key);
    }
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "occupied", .data = "not a directory" });
    var unwritable = request;
    unwritable.cache = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname((try resolve(request))).?, "occupied" });
    try std.testing.expectError(error.WriteFailed, publishApproval(unwritable, @splat(0), true));
}

// spec-case: NEW-CORE-S4-TEST-3
test "approvedLibrary refuses missing trees and propagates allocation failure" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const path = try resolve(request);
    const cpu = try nativeTarget(request.io);
    const first = try inventory(request, path, cpu);
    const library_path = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(path).?, "lib" });
    try std.testing.expect(try approvedLibrary(request, first.inputs, library_path));
    try std.testing.expect(!try approvedLibrary(request, first.inputs, "/missing/approved-library"));
    var failing = request;
    failing.arena = std.testing.failing_allocator;
    try std.testing.expectError(error.OutOfMemory, approvedLibrary(failing, first.inputs, library_path));
}

// spec-case: NEW-CORE-S4-TEST-3
test "approvedRuntime refuses missing unknown preload and SourceChanged runtime inputs" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const captured = try inventory(request, try resolve(request), try nativeTarget(request.io));
    const runtime = profilesFor(request)[0].runtime;
    for (runtime.files) |expected| try std.testing.expect(namedInput(captured.inputs, expected.path) != null);
    try std.testing.expect(namedInput(captured.inputs, runtime.preload) != null);
    try std.testing.expect(try approvedRuntime(request, captured.inputs));
    try std.testing.expect(!try approvedRuntime(request, &.{}));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "native-input", .data = "unreviewed runtime" });
    var private: std.ArrayList(Input) = .empty;
    const native_path = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(try resolve(request)).?, "native-input" });
    const native = try addInput(request, &private, native_path);
    const modified = try request.arena.dupe(Input, captured.inputs);
    Fixture.replaceSnapshot(modified, runtime.preload, native.resolved, native.info);
    try std.testing.expect(!try approvedRuntime(request, modified));
    @memcpy(modified, captured.inputs);
    Fixture.replaceSnapshot(modified, runtime.files[0].path, native.resolved, native.info);
    try std.testing.expect(!try approvedRuntime(request, modified));
    Fixture.replaceSnapshot(modified, runtime.files[0].path, runtime.files[0].resolved, native.info);
    try std.testing.expectError(error.SourceChanged, approvedRuntime(request, modified));
}

// spec-case: NEW-CORE-S4-TEST-3
test "runtime generation refresh refuses changed bytes absence and alias retarget" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    const root = std.fs.path.dirname(try resolve(request)).?;
    const path = try std.fs.path.join(request.arena, &.{ root, "libc.so.6" });
    const absent = try std.fs.path.join(request.arena, &.{ root, "ld.so.preload" });
    const alias = try std.fs.path.join(request.arena, &.{ root, "loader" });
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "libc.so.6", .data = "first" });
    try fixture.temporary.dir.symLink(request.io, "libc.so.6", "loader", .{});
    var inputs: std.ArrayList(Input) = .empty;
    _ = try addInput(request, &inputs, path);
    _ = try addInput(request, &inputs, absent);
    _ = try addInput(request, &inputs, alias);
    const cpu = try nativeTarget(request.io);
    const original = inventoryDigest(request, inputs.items, cpu);
    const info = try fixture.temporary.dir.statFile(request.io, "libc.so.6", .{});
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "libc.so.6", .data = "other" });
    try fixture.temporary.dir.setTimestamps(request.io, "libc.so.6", .{ .modify_timestamp = .init(info.mtime) });
    const changed = (try refresh(request, inputs.items, cpu)).?;
    try std.testing.expect(!std.mem.eql(u8, &original, &changed.generation));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "ld.so.preload", .data = "injected.so" });
    try std.testing.expect((try refresh(request, changed.inputs, cpu)) == null);
    try fixture.temporary.dir.deleteFile(request.io, "ld.so.preload");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "other-loader", .data = "other" });
    try fixture.temporary.dir.deleteFile(request.io, "loader");
    try fixture.temporary.dir.symLink(request.io, "other-loader", "loader", .{});
    try std.testing.expect((try refresh(request, changed.inputs, cpu)) == null);
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery predicates tolerate output neighbors but membership guards refuse additions" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    try fixture.temporary.dir.createDirPath(request.io, "query");
    try fixture.temporary.dir.createDirPath(request.io, "versions/15");
    const root = std.fs.path.dirname(try resolve(request)).?;
    var inputs: std.ArrayList(Input) = .empty;
    _ = try addInput(request, &inputs, try std.fs.path.join(request.arena, &.{ root, "query" }));
    inputs.items[0].role = .predicate;
    _ = try addInput(request, &inputs, try std.fs.path.join(request.arena, &.{ root, "versions" }));
    inputs.items[1].role = .membership;
    const cpu = try nativeTarget(request.io);
    const original = inventoryDigest(request, inputs.items, cpu);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "query/native-output", .data = "owned staging" });
    const output = (try refresh(request, inputs.items, cpu)).?;
    try std.testing.expectEqual(original, output.generation);
    try fixture.temporary.dir.createDirPath(request.io, "versions/16");
    try std.testing.expect((try refresh(request, inputs.items, cpu)) == null);
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery file restored mtime and absent resource invalidate provisional generation" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.tool("first");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "distro", .data = "first" });
    const root = std.fs.path.dirname(try resolve(request)).?;
    var inputs: std.ArrayList(Input) = .empty;
    _ = try addInput(request, &inputs, try std.fs.path.join(request.arena, &.{ root, "distro" }));
    inputs.items[0].role = .discovery_file;
    _ = try addInput(request, &inputs, try std.fs.path.join(request.arena, &.{ root, "resource" }));
    inputs.items[1].role = .predicate;
    const cpu = try nativeTarget(request.io);
    const original = inventoryDigest(request, inputs.items, cpu);
    const info = try fixture.temporary.dir.statFile(request.io, "distro", .{});
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "distro", .data = "other" });
    try fixture.temporary.dir.setTimestamps(request.io, "distro", .{ .modify_timestamp = .init(info.mtime) });
    const edited = (try refresh(request, inputs.items, cpu)).?;
    try std.testing.expect(!std.mem.eql(u8, &original, &edited.generation));
    try fixture.temporary.dir.createDirPath(request.io, "resource/share");
    try std.testing.expect((try refresh(request, edited.inputs, cpu)) == null);
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery roles roundtrip and invalid role bytes cannot become warm hints" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var bytes: std.Io.Writer.Allocating = .init(arena.allocator());
    try bytes.writer.writeInt(u32, 1, .little);
    const input: Input = .{ .path = "/owned", .resolved = "/owned", .info = null, .role = .discovery_file };
    try encodeInput(&bytes.writer, input);
    const decoded = try decodeHint(arena.allocator(), bytes.written());
    try std.testing.expectEqual(input.role, decoded[0].role);
    bytes.written()[4 + 4 + input.path.len + 4 + input.resolved.len] = 255;
    try std.testing.expectError(error.MalformedHint, decodeHint(arena.allocator(), bytes.written()));
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery higher priority resource addition refuses old replay and unknown copy reuse" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var request = try fixture.request();
    try fixture.staticTool(1);
    const bytes = try fixture.temporary.dir.readFileAlloc(request.io, "zig", request.arena, .limited(121));
    try fixture.temporary.dir.createDirPath(request.io, "tool/distribution/lib/std");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "tool/distribution/zig", .data = bytes });
    try fixture.temporary.dir.setFilePermissions(request.io, "tool/distribution/zig", .executable_file, .{});
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "tool/distribution/lib/std/std.zig", .data = "first" });
    request.executable = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(try resolve(request)).?, "tool/distribution/zig" });
    const copied_profiles = try request.arena.dupe(platform.Profile, profilesFor(request));
    copied_profiles[0].discovery.state = try request.arena.dupe(u8, &std.fmt.bytesToHex(try discovery.profileState(request.arena, request.io, request.executable, copied_profiles[0].discovery), .lower));
    fixture.profiles = copied_profiles;
    const initial = try capture(request);
    try std.testing.expect(initial.cacheable);
    try std.testing.expect((try lookupReplayCandidate(request)) != null);
    try fixture.temporary.dir.createDirPath(request.io, "tool/lib/clang/22/share");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "tool/lib/clang/22/share/ubsan_ignorelist.txt", .data = "# owned outside resource\n" });
    const provisional = (try lookupReplayCandidate(request)).?;
    try std.testing.expect(!try unchanged(request, provisional));
    const after = try capture(request);
    try std.testing.expect(!after.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &initial.digest, &after.digest));
    try std.testing.expect((try lookupReplayCandidate(request)) == null);
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery NotDir fallback retains parent contents and old content refusal" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var request = try fixture.request();
    try fixture.temporary.dir.createDirPath(request.io, "tool/distribution");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "tool/distribution/zig", .data = "unproved" });
    try fixture.temporary.dir.setFilePermissions(request.io, "tool/distribution/zig", .executable_file, .{});
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "tool/lib", .data = "first" });
    request.executable = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(request.cache).?, "tool/distribution/zig" });
    const initial = try capture(request);
    try std.testing.expect(!initial.cacheable);
    try std.testing.expect(try unchanged(request, initial));
    const root = std.fs.path.dirname(std.fs.path.dirname(initial.path).?).?;
    const parent_path = try std.fs.path.join(request.arena, &.{ root, "lib" });
    const child_path = try std.fs.path.join(request.arena, &.{ parent_path, "gcc" });
    try std.testing.expectError(error.ReadFailed, snapshot(request, child_path, .content));
    const child = try snapshot(request, child_path, .membership);
    try std.testing.expect(child.info == null);
    const info = try std.Io.Dir.cwd().statFile(request.io, parent_path, .{});
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = parent_path, .data = "other" });
    try std.Io.Dir.cwd().setTimestamps(request.io, parent_path, .{ .modify_timestamp = .init(info.mtime) });
    try std.testing.expect(!try unchanged(request, initial));
    try std.testing.expect(!std.mem.eql(u8, &initial.digest, &(try capture(request)).digest));
}

fn ownedProfile(request: Request, path: []const u8, runtime_path: []const u8, discovery_path: []const u8) !platform.Profile {
    const files = try request.arena.alloc(platform.RuntimeFile, 1);
    const info = try std.Io.Dir.cwd().statFile(request.io, runtime_path, .{});
    const runtime_hash = try fileHash(std.crypto.hash.sha2.Sha256, request, .{ .path = runtime_path, .resolved = runtime_path, .info = info });
    files[0] = .{ .path = runtime_path, .resolved = runtime_path, .sha256 = try request.arena.dupe(u8, &std.fmt.bytesToHex(runtime_hash, .lower)) };
    const discovery_files = try request.arena.alloc(platform.DiscoveryFile, 1);
    discovery_files[0] = .{ .path = discovery_path };
    const prefix = std.fs.path.dirname(runtime_path).?;
    var profile: platform.Profile = .{
        .id = runtime_path,
        .runtime = .{ .files = files, .preload = try std.fs.path.join(request.arena, &.{ prefix, "absent-preload" }) },
        .discovery = .{ .state = "", .files = discovery_files, .predicates = &.{}, .installation = prefix, .system_prefix = prefix, .installation_predicates = &.{} },
    };
    profile.discovery.state = try request.arena.dupe(u8, &std.fmt.bytesToHex(try discovery.profileState(request.arena, request.io, path, profile.discovery), .lower));
    return profile;
}

// spec: CORE-TOOL-PROFILES-1
test "reviewed profiles reject mixed runtime and discovery closures" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    const root = std.fs.path.dirname(request.cache).?;
    const path = try std.fs.path.join(request.arena, &.{ root, "zig" });
    const runtime = try std.fs.path.join(request.arena, &.{ root, "runtime" });
    const distro = try std.fs.path.join(request.arena, &.{ root, "distro" });
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = runtime, .data = "runtime-A" });
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = distro, .data = "distro-A" });
    const first = try ownedProfile(request, path, runtime, distro);
    var inputs: std.ArrayList(Input) = .empty;
    _ = try addInput(request, &inputs, runtime);
    _ = try addInput(request, &inputs, first.runtime.preload);
    try std.testing.expect(try approvedProfiles(request, path, inputs.items, &.{first}));
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = runtime, .data = "runtime-B" });
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = distro, .data = "distro-B" });
    const second = try ownedProfile(request, path, runtime, distro);
    inputs.clearRetainingCapacity();
    _ = try addInput(request, &inputs, runtime);
    _ = try addInput(request, &inputs, second.runtime.preload);
    try std.testing.expect(try approvedProfiles(request, path, inputs.items, &.{ first, second }));
    try std.Io.Dir.cwd().writeFile(request.io, .{ .sub_path = distro, .data = "distro-A" });
    try std.testing.expect(!try approvedProfiles(request, path, inputs.items, &.{ first, second }));
    try std.testing.expect(!try approvedProfiles(request, path, &.{}, &.{ first, second }));
}

// spec-case: CORE-TOOL-PROFILES-1
test "profile policy edits isolate warm content approvals and replay candidates" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    try std.testing.expect(original.cacheable);
    try std.testing.expect((try lookupReplayCandidate(request)) != null);
    const changed = try request.arena.dupe(platform.Profile, profilesFor(request));
    changed[0].id = "owned-replacement-profile";
    fixture.profiles = changed;
    try std.testing.expect((try lookupReplayCandidate(request)) == null);
    try std.testing.expect(!try unchanged(request, original));
    const replacement = try capture(request);
    try std.testing.expect(replacement.cacheable);
    try std.testing.expect(!replacement.memo_hit);
    try std.testing.expect(!std.mem.eql(u8, &original.digest, &replacement.digest));
    try std.testing.expect(!std.mem.eql(u8, &original.generation, &replacement.generation));
}

// spec-case: CORE-TOOL-PROFILES-1
test "approved profile membership changes isolate semantic content identities" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const path = try resolve(request);
    const profiles = try request.arena.alloc(platform.Profile, 2);
    profiles[0] = profilesFor(request)[0];
    profiles[0].discovery.system_prefix = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(path).?, "host" });
    try fixture.temporary.dir.createDirPath(request.io, "host/lib/gcc/x86_64-linux-gnu/14");
    profiles[0].discovery.state = try request.arena.dupe(u8, &std.fmt.bytesToHex(try discovery.profileState(request.arena, request.io, path, profiles[0].discovery), .lower));
    profiles[1] = profiles[0];
    profiles[1].id = "owned-additional-gcc-profile";
    try fixture.temporary.dir.createDirPath(request.io, "host/lib/gcc/x86_64-linux-gnu/15");
    profiles[1].discovery.state = try request.arena.dupe(u8, &std.fmt.bytesToHex(try discovery.profileState(request.arena, request.io, path, profiles[1].discovery), .lower));
    try fixture.temporary.dir.deleteTree(request.io, "host/lib/gcc/x86_64-linux-gnu/15");
    fixture.profiles = profiles;
    const first = try capture(request);
    try std.testing.expect(first.cacheable);
    try fixture.temporary.dir.createDirPath(request.io, "host/lib/gcc/x86_64-linux-gnu/15");
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!try unchanged(request, first));
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
}
