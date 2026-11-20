//! Content identity of guest Zig, native CPU, bundled inputs and default loader.
//! A compact, checksummed memo avoids rereading unchanged tool bytes. Every call
//! validates all known generations; strict capture checks twice. Provisional
//! directory replay requires a final parent validation. Callers must spawn the
//! returned absolute path and verify before publishing. No subprocess runs.
const std = @import("std");
const product = @import("selka").product;
const builtin = @import("builtin");
const target_policy = @import("target.zig");
const discovery = @import("tool_discovery.zig");
const tool_files = @import("tool_files.zig");
// The toolchain identity describes the machine the tool runs on: the host. A build for another target adds that
// target's `-target` and CPU flags to its own keys (`unit_cache.key`).
const target = target_policy.host;
const fast_blake3 = @import("fast_blake3.zig");
/// SHA-256 through the optimized digest object: approving a Zig toolchain hashes its whole closure.
const Sha256 = @import("selka").fast_sha256.Sha256;
const Digest = [32]u8;
// v2: the system closure is resolved through the loader's cache (GH-3b), so a memo of v1 names another construction.
const magic = "core-tool-content-v2\x00";
const memo_length = magic.len + 96;
// v4 adds a validated directory-role byte (Input codec v2), retains all old
// full-stat/content inputs, and keys the additive reviewed discovery policy.
// v5 records each library root as one input instead of its whole tree.
// v6 adds the tracked files and directories of each library root (tool_files.zig).
// v7 resolves the system closure through the loader's cache and adds the `resolver` role (GH-3b).
// v8 adds the `system` role and the unreadable state of system inputs (GH-3b review, R5).
const hint_magic = "core-tool-inventory-v8\x00";
const hint_limit = 32 << 20;
const lib_directory = "ZIG_LIB_DIR";
// v4: the verdict covers the toolchain only; the system libraries are keyed, never approved (GH-3b).
const approval_magic = "core-tool-approval-v4\x00";
const approval_length = approval_magic.len + 65;
// Reviewed pinned distribution; names, version strings and static ELF metadata
// cannot establish that an arbitrary executable has no delegated dependencies.
const approved_zig = "58959f01285c05a74276f09327b551d42ed6006bf325a78dc661a024e314987b";
const approved_library = "e3a89bd78652c8c212a448ad182d1ef2188218de62dc56b369e5f8858bb847a0";
const platform = @import("core_tool_platform");
/// The system libraries built programs load, resolved as the loader resolves them; their bytes key every native result.
pub const closure = @import("native_closure.zig");

/// The directory the system closure is read below: "" (the machine itself) except in a compiler built with
/// `-Dtest-system-root=DIR`, or in a unit test that names one through `SELKA_TEST_SYSTEM_ROOT`. A production build never
/// reads that variable.
fn systemRoot(request: Request) []const u8 {
    if (builtin.is_test) if (request.environment.get("SELKA_TEST_SYSTEM_ROOT")) |root| return root;
    return builtSystemRoot();
}

/// Borrowed command resources. Returned paths have allocator lifetime.
pub const Request = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    environment: *const std.process.Environ.Map,
    executable: []const u8,
    cache: []const u8,
};

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
/// One thing a toolchain's identity covers (the executable, a library root with its tracked files, a
/// runtime or discovery input) with the status it had.
pub const Input = struct {
    path: []const u8,
    resolved: []const u8,
    info: ?std.Io.File.Stat,
    role: discovery.Role = .content,
    /// For a library root: the files and directories below it that `zig` can read,
    /// each with its status (tool_files.zig).
    files: []const tool_files.Entry = &.{},
    /// `tool_files.digest(files)`, which stands for the set in a generation.
    files_digest: Digest = @splat(0),
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
/// dependencies remain the driver's responsibility. A file that changes during
/// one capture is retried once, so a concurrent edit is a miss rather than an
/// error; only a second change inside the same capture reports SourceChanged.
pub fn capture(request: Request) Error!Identity {
    return captureWithRetry(request, false, 1);
}

/// Lend only a provisional read-only replay identity. A directory parent must
/// validate unchanged() after every child, before accepting aggregate success.
/// A miss or unproved executable retains strict content/second-scan guards.
pub fn captureReplayParent(request: Request) Error!Identity {
    return captureWithRetry(request, true, 1);
}

/// Capture once, then retry a single mid-capture input change from a fresh inventory.
fn captureWithRetry(request: Request, provisional: bool, retries: u8) Error!Identity {
    var remaining = retries;
    while (true) {
        if (captureMode(request, provisional)) |identity| {
            return identity;
        } else |err| {
            if (err != error.SourceChanged or remaining == 0) return err;
            remaining -= 1;
        }
    }
}

/// Read an untrusted warm identity without scanning library generations. Use
/// only for buffered read-only manifest replay, then require unchanged() and a
/// second dependency validation before accepting success. A miss or refusal
/// must discard the candidate and capture strictly before checking or building.
pub fn lookupReplayCandidate(request: Request) Error!?Identity {
    const found = (try replayCandidate(request)) orelse return null;
    return found.identity;
}

/// A warm identity read from the hint, with the inventory the hint recorded: what `lookupReplayCandidate`
/// gives, and what `Check` needs to look at the files again without reading the hint a second time.
pub const Candidate = struct { identity: Identity, inventory: []const Input };

/// `lookupReplayCandidate`, keeping the inventory.
pub fn replayCandidate(request: Request) Error!?Candidate {
    const path = resolve(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const cpu = nativeTarget(request.io) catch return null;
    const inputs = (try inventoryHint(request, path, cpu)) orelse return null;
    const old = candidateExecutable(inputs, path) orelse return null;
    const info = std.Io.Dir.cwd().statFile(request.io, path, .{}) catch return null;
    if (!sameStat(old, info)) return null;
    const identity = inventoryDigest(inputs, cpu);
    if (!safeEnvironment(request.environment)) return null;
    if ((try approvalMemo(request, identity)) != true) return null;
    const content = (try memo(request, identity)) orelse return null;
    return .{ .identity = .{ .path = path, .digest = content, .generation = identity, .native_target = cpu, .inputs = inputs.len, .memo_hit = true, .cacheable = true }, .inventory = inputs };
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
    const content = found orelse try contents(request, first.inputs, cpu);
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
    return unchangedFrom(request, original, null);
}

/// `unchanged` against an inventory already in hand (from `replayCandidate`) instead of the hint.
fn unchangedFrom(request: Request, original: Identity, given: ?[]const Input) Error!bool {
    const path = try resolve(request);
    if (!std.mem.eql(u8, path, original.path)) return false;
    const cpu = try nativeTarget(request.io);
    const known = given orelse try inventoryHint(request, path, cpu);
    const current = if (known) |inputs| (try refresh(request, inputs, cpu)) orelse try inventory(request, path, cpu) else try inventory(request, path, cpu);
    return std.mem.eql(u8, &current.generation, &original.generation);
}

/// `unchanged` running beside other work. A replay starts the check as soon as it has a candidate, so
/// the status of the toolchain's files is read while the record's own inputs are, and it asks for the
/// answer where it needs it. The check keeps its place in memory from `begin` to `finish`.
pub const Check = struct {
    request: Request,
    original: Identity,
    /// The inventory the candidate came from, when the caller has it.
    inventory: ?[]const Input = null,
    thread: ?std.Thread = null,
    result: Error!bool = false,

    /// Start the check on a thread of its own; when none can start, it runs here.
    ///
    /// The thread takes the default stack (16 MiB, committed on use). A libc-linked build places the
    /// binary's static thread-local block inside each thread's stack, and the compiler's own block is
    /// 262200 bytes (its PT_TLS segment), so a 256 KiB request is refused: `pthread_create` returns
    /// EINVAL, which Zig's std turns into `unreachable`. The regression is `Check.begin runs unchanged`
    /// under `zig build test-core -Dtest-libc=true`.
    pub fn begin(self: *Check) void {
        self.thread = std.Thread.spawn(.{}, run, .{self}) catch null;
        if (self.thread == null) run(self);
    }

    fn run(self: *Check) void {
        self.result = unchangedFrom(self.request, self.original, self.inventory);
    }

    /// Wait for the check and give its answer; asking again gives the same one.
    pub fn finish(self: *Check) Error!bool {
        if (self.thread) |thread| thread.join();
        self.thread = null;
        return self.result;
    }
};

/// Detect the current native CPU and Core code-generation flags without a tool. The
/// answer is a property of the machine and of this process's loader, which cannot change
/// while it runs, and detecting it reads the loader and libc files: about 3 ms in the Debug
/// compiler, paid two to four times by every command that identifies the toolchain. It is
/// detected once per process.
pub fn nativeTarget(io: std.Io) Error!Digest {
    const remembered = @import("selka").native_target_memo;
    if (remembered.recall()) |known| return known;
    const detected = try detectNativeTarget(io);
    remembered.remember(detected);
    return detected;
}

fn detectNativeTarget(io: std.Io) Error!Digest {
    const native = std.zig.system.resolveTargetQuery(io, .{ .cpu_model = .native }) catch return error.ReadFailed;
    var hash = fast_blake3.Blake3.init(.{});
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
    var hash = fast_blake3.Blake3.init(.{});
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
    try systemInputs(request, &inputs);
    if (addressSanitizer(request.environment)) _ = try addInput(request, &inputs, platform.address_runtime.path);
    for (try discovery.paths(request.arena, path)) |entry| {
        // An already inventoried library/runtime path retains its full guard.
        if (namedInput(inputs.items, entry.name) != null) continue;
        try inputs.append(request.arena, try snapshot(request, entry.name, entry.role));
    }
    std.mem.sort(Input, inputs.items, {}, before);
    return .{ .inputs = inputs.items, .generation = inventoryDigest(inputs.items, cpu) };
}

fn inventoryDigest(inputs: []const Input, cpu: Digest) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, "core-tool-generations-v5");
    field(&hash, &cpu);
    for (inputs) |input| generation(&hash, input);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn refresh(request: Request, inputs: []const Input, cpu: Digest) Error!?Inventory {
    const current = try request.arena.alloc(Input, inputs.len);
    // Paths found absent in this pass: an input recorded absent below one of them is absent
    // without a stat. Discovery lists hundreds of candidates below directories that are not there.
    var absent: std.StringHashMapUnmanaged(void) = .empty;
    for (inputs, current) |old, *input| {
        // A system input is looked at the way it was taken: never an error, and any change takes the inventory afresh.
        if (systemRole(old.role)) {
            const fresh = try readableSnapshot(request, old.path, old.role);
            if (!sameSnapshot(old, fresh)) return null;
            input.* = fresh;
            continue;
        }
        const info: ?std.Io.File.Stat = if (old.info == null and belowAbsent(&absent, old.path)) null else std.Io.Dir.cwd().statFile(request.io, old.path, .{}) catch |err| switch (err) {
            error.FileNotFound => null,
            error.NotDir => if (old.role != .content) null else return error.ReadFailed,
            else => return error.ReadFailed,
        };
        if (info == null) try absent.put(request.arena, old.path, {});
        if (old.info == null or info == null) {
            if (old.info != null or info != null) return null;
        } else if ((old.info.?.kind == .directory or info.?.kind == .directory) and old.role != .predicate) {
            if (!sameStat(old.info.?, info.?)) return null;
        } else if (old.info.?.kind != info.?.kind) return null;
        if (info != null and (old.role != .content or !std.mem.eql(u8, old.path, old.resolved))) {
            const resolved = std.Io.Dir.cwd().realPathFileAlloc(request.io, old.path, request.arena) catch |err| return readError(err);
            if (!std.mem.eql(u8, resolved, old.resolved)) return null;
        }
        // Any change among the files `zig` reads means the inventory is taken afresh, which gives the
        // changed files their new status and the toolchain a new generation.
        if (old.files.len != 0 and !tool_files.unchanged(request.io, old.resolved, old.files)) return null;
        input.* = .{ .path = old.path, .resolved = old.resolved, .info = info, .role = old.role, .files = old.files, .files_digest = old.files_digest };
    }
    return .{ .inputs = current, .generation = inventoryDigest(current, cpu), .hinted = true };
}

/// Whether a directory above `path` is among `absent`: nothing can be below it.
fn belowAbsent(absent: *const std.StringHashMapUnmanaged(void), path: []const u8) bool {
    var parent = std.fs.path.dirname(path);
    while (parent) |name| : (parent = std.fs.path.dirname(name)) if (absent.contains(name)) return true;
    return false;
}

/// The root of a library tree as one input; an absent root is an absent input.
fn libraryRoot(request: Request, inputs: *std.ArrayList(Input), visited: *std.StringHashMapUnmanaged(void), path: []const u8) Error!void {
    const input = try addInput(request, inputs, path);
    const info = input.info orelse return;
    if (info.kind != .directory) return error.ReadFailed;
    const first = !visited.contains(input.resolved);
    try visited.put(request.arena, input.resolved, {});
    if (!first) return;
    // The root's own status moves when its entries do; an edit inside the tree does not move
    // it, so the files `zig` reads are tracked one by one.
    const tracked = tool_files.collect(request.arena, request.io, input.resolved, threadSanitizer(request.environment)) catch |err| return readError(err);
    inputs.items[inputs.items.len - 1].files = tracked;
    inputs.items[inputs.items.len - 1].files_digest = tool_files.digest(tracked);
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

/// The system closure's inputs (`native_closure.zig`): the loader, every candidate of each name and the files the
/// preload file names, by content; the loader's cache and the preload file as resolvers. The cache's bytes are keyed as
/// well when it could not answer for a name. A file that cannot be read enters as absent, as the loader skips it.
fn systemInputs(request: Request, inputs: *std.ArrayList(Input)) Error!void {
    const root = systemRoot(request);
    const found = try closure.resolve(request.arena, request.io, root);
    for (found.files) |path| try addSystemInput(request, inputs, path, .system);
    for (found.preloaded) |path| try addSystemInput(request, inputs, path, .system);
    try addSystemInput(request, inputs, try closure.below(request.arena, root, closure.cache_path), if (found.cache_keyed) .keyed_resolver else .resolver);
    try addSystemInput(request, inputs, try closure.below(request.arena, root, closure.preload_path), .resolver);
}

fn addSystemInput(request: Request, inputs: *std.ArrayList(Input), path: []const u8, role: discovery.Role) Error!void {
    if (namedInput(inputs.items, path) != null) return;
    try inputs.append(request.arena, try readableSnapshot(request, path, role));
}

/// Whether `role` marks an input of the system closure (`systemInputs`).
fn systemRole(role: discovery.Role) bool {
    return role == .system or role == .resolver or role == .keyed_resolver;
}

/// The prefix of the resolved path of a system file that exists but cannot be read; the error's name follows it. It is
/// absolute (the inventory hint requires that) and holds a NUL, which no real path does.
const unreadable_marker = "/\x00unreadable ";

/// `snapshot` for a system file, which never fails: a file that is not there is absent; one that exists but cannot be
/// stat'ed, resolved or opened (a 0600 file of another user, a directory it cannot search, a path through a file, a
/// link loop) is unreadable, recorded with the error's name in place of its resolved path. The loader cannot load it
/// either, and the state stays the same from capture to refresh, so a build neither fails nor reuses across a change.
fn readableSnapshot(request: Request, path: []const u8, role: discovery.Role) Error!Input {
    const info = std.Io.Dir.cwd().statFile(request.io, path, .{}) catch |err| {
        if (err == error.FileNotFound) return .{ .path = path, .resolved = path, .info = null, .role = role };
        return unreadable(request, path, role, @errorName(err));
    };
    const resolved = std.Io.Dir.cwd().realPathFileAlloc(request.io, path, request.arena) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return unreadable(request, path, role, @errorName(err));
    };
    if (info.kind == .file) {
        const file = std.Io.Dir.cwd().openFile(request.io, resolved, .{}) catch |err| return unreadable(request, path, role, @errorName(err));
        file.close(request.io);
    }
    return .{ .path = path, .resolved = resolved, .info = info, .role = role };
}

fn unreadable(request: Request, path: []const u8, role: discovery.Role, why: []const u8) Error!Input {
    const marker = try std.mem.concat(request.arena, u8, &.{ unreadable_marker, why });
    return .{ .path = path, .resolved = marker, .info = null, .role = role };
}

/// Whether two snapshots of one system input agree: the same resolution (or the same unreadable state) and status.
fn sameSnapshot(old: Input, fresh: Input) bool {
    if (!std.mem.eql(u8, old.resolved, fresh.resolved)) return false;
    if (old.info == null or fresh.info == null) return old.info == null and fresh.info == null;
    return sameStat(old.info.?, fresh.info.?);
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

fn contents(request: Request, inputs: []const Input, cpu: Digest) Error!Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, "core-tool-content-v5");
    field(&hash, &cpu);
    for (inputs) |input| {
        field(&hash, input.path);
        field(&hash, input.resolved);
        field(&hash, @tagName(input.role));
        const info = input.info orelse {
            field(&hash, "absent");
            continue;
        };
        field(&hash, @tagName(info.kind));
        // A resolver (the loader's cache, the preload file) is keyed through the files it names.
        if (info.kind == .file and input.role != .resolver) field(&hash, &try fileContent(request, input));
        // A library root stands for its tree: its entries' additions, removals and
        // retargets reach the content identity through the root's own generation.
        if (info.kind == .directory and input.role == .content) generation(&hash, input);
        // The bytes of every tracked file, which the root's status does not stand for.
        if (input.files.len != 0) try tool_files.contentInto(request.io, input.resolved, input.files, &hash);
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn fileContent(request: Request, input: Input) Error!Digest {
    return fileHash(fast_blake3.Blake3, request, input);
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
    fast_blake3.hash(bytes[0 .. memo_length - 32], &checksum);
    if (!std.mem.eql(u8, bytes[memo_length - 32 ..], &checksum)) return null;
    return bytes[magic.len + 32 ..][0..32].*;
}

fn publish(request: Request, identity: Digest, content: Digest) Error!void {
    const path = try memoPath(request, identity);
    var bytes: [memo_length]u8 = undefined;
    @memcpy(bytes[0..magic.len], magic);
    @memcpy(bytes[magic.len..][0..32], &identity);
    @memcpy(bytes[magic.len + 32 ..][0..32], &content);
    fast_blake3.hash(bytes[0 .. memo_length - 32], bytes[memo_length - 32 ..]);
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
        return std.fs.path.join(request.arena, &.{ root, product.user_dir, "core-tools-v1" });
    if (request.environment.get("HOME")) |root| if (root.len != 0)
        return std.fs.path.join(request.arena, &.{ root, ".cache", product.user_dir, "core-tools-v1" });
    return request.cache;
}

fn hintKey(request: Request, path: []const u8, cpu: Digest) Error!Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, hint_magic);
    field(&hash, path);
    field(&hash, &cpu);
    closurePolicy(request, &hash);
    // A hint lists the candidates the compiler that wrote it looked for: another rule is another hint.
    closure.policy(&hash);
    field(&hash, if (threadSanitizer(request.environment)) "thread" else "");
    tool_files.definition(&hash);
    discovery.policy(&hash);
    if (request.environment.get(lib_directory)) |override| {
        field(&hash, try absolutePath(request, override));
    } else field(&hash, "");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn hintPath(request: Request, path: []const u8, cpu: Digest) Error![]const u8 {
    return hintPathOf(request, try hintKey(request, path, cpu));
}

fn hintPathOf(request: Request, key: Digest) Error![]const u8 {
    return std.fmt.allocPrint(request.arena, "{s}/tool-identity/{s}.inventory", .{ try cacheRoot(request), std.fmt.bytesToHex(key, .lower) });
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
    fast_blake3.hash(bytes[0 .. bytes.len - 32], &checksum);
    if (!std.mem.eql(u8, bytes[bytes.len - 32 ..], &checksum)) return null;
    return decodeHint(request.arena, bytes[hint_magic.len + 32 .. bytes.len - 32]) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
}

const HintError = std.Io.Reader.Error || error{ OutOfMemory, MalformedHint, Malformed };

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
        input.files_digest = (try reader.takeArray(32)).*;
        input.files = try tool_files.decode(a, &reader);
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
    try publishHintUnder(request, try hintKey(request, path, cpu), inputs);
}

fn publishHintUnder(request: Request, key: Digest, inputs: []const Input) Error!void {
    var text: std.Io.Writer.Allocating = .init(request.arena);
    const writer = &text.writer;
    try writer.writeAll(hint_magic);
    try writer.writeAll(&key);
    try writer.writeInt(u32, @intCast(inputs.len), .little);
    for (inputs) |input| try encodeInput(writer, input);
    var checksum: Digest = undefined;
    fast_blake3.hash(text.written(), &checksum);
    try writer.writeAll(&checksum);
    try publishBytes(request, try hintPathOf(request, key), text.written());
}

fn encodeInput(writer: *std.Io.Writer, input: Input) Error!void {
    try writer.writeInt(u32, @intCast(input.path.len), .little);
    try writer.writeAll(input.path);
    try writer.writeInt(u32, @intCast(input.resolved.len), .little);
    try writer.writeAll(input.resolved);
    try writer.writeByte(@backingInt(input.role));
    if (input.info) |info| {
        try writer.writeByte(1);
        try writer.writeInt(u64, info.inode, .little);
        try writer.writeInt(u64, info.size, .little);
        try writer.writeInt(i128, info.mtime.nanoseconds, .little);
        try writer.writeInt(i128, info.ctime.nanoseconds, .little);
        try writer.writeInt(u32, info.permissions.toMode(), .little);
        try writer.writeByte(@intCast(@backingInt(info.kind)));
    } else try writer.writeByte(0);
    try writer.writeAll(&input.files_digest);
    try tool_files.encode(writer, input.files);
}

fn absolutePath(request: Request, path: []const u8) Error![]const u8 {
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(request.io, ".", request.arena) catch |err| return readError(err);
    return std.fs.path.resolve(request.arena, &.{ cwd, path });
}

fn generation(hash: *fast_blake3.Blake3, input: Input) void {
    field(hash, input.path);
    field(hash, input.resolved);
    field(hash, @tagName(input.role));
    if (input.files.len != 0) field(hash, &input.files_digest);
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
    var a = fast_blake3.Blake3.init(.{});
    var b = fast_blake3.Blake3.init(.{});
    generation(&a, first);
    generation(&b, second);
    var x: Digest = undefined;
    var y: Digest = undefined;
    a.final(&x);
    b.final(&y);
    return std.mem.eql(u8, &x, &y);
}

fn field(hash: *fast_blake3.Blake3, bytes: []const u8) void {
    integer(hash, bytes.len);
    hash.update(bytes);
}

fn integer(hash: *fast_blake3.Blake3, value: i128) void {
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

/// The variable that makes `environment` unsafe for reuse (a compiler or loader override whose files the identity does
/// not capture), or null. Builds then reuse nothing.
pub fn unsafeVariable(environment: *const std.process.Environ.Map) ?[]const u8 {
    for (external_variables) |key| if (environment.get(key)) |value| if (value.len != 0) return key;
    var entries = environment.iterator();
    while (entries.next()) |entry| {
        const loader = std.mem.startsWith(u8, entry.key_ptr.*, "LD_") or std.mem.startsWith(u8, entry.key_ptr.*, "DYLD_");
        if (loader and entry.value_ptr.len != 0) return entry.key_ptr.*;
    }
    return null;
}

fn safeEnvironment(environment: *const std.process.Environ.Map) bool {
    return unsafeVariable(environment) == null;
}

const external_variables = [_][]const u8{
    "CPATH",                      "C_INCLUDE_PATH",           "CPLUS_INCLUDE_PATH",         "OBJC_INCLUDE_PATH",
    "LIBRARY_PATH",               "COMPILER_PATH",            "GCC_EXEC_PREFIX",            "SDKROOT",
    "SYSROOT",                    "CCC_OVERRIDE_OPTIONS",     "CCC_ADD_ARGS",               "CLANG_CONFIG_FILE_SYSTEM_DIR",
    "CLANG_CONFIG_FILE_USER_DIR", "ZIG_LIBC",                 "ZIG_BUILD_RUNNER",           "ZIG_DEBUG_CMD",
    "CC",                         "CXX",                      "AR",                         "AS",
    "LD",                         "RANLIB",                   "NM",                         "OBJCOPY",
    "STRIP",                      "MACOSX_DEPLOYMENT_TARGET", "IPHONEOS_DEPLOYMENT_TARGET", "RC_DEBUG_OPTIONS",
    "GLIBC_TUNABLES",
};

/// The key of a toolchain verdict. The system libraries do not decide it: they are keyed by `digest` (GH-3b).
fn approvalKey(request: Request, identity: Digest) Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, approval_magic);
    field(&hash, &identity);
    field(&hash, approved_zig);
    field(&hash, approved_library);
    closurePolicy(request, &hash);
    discovery.policy(&hash);
    field(&hash, if (builtin.is_test) "owned-test-fixtures-v1" else "production");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Thread mode builds the sanitizer runtime from the library's C++ sources, so it tracks more of the tree.
pub fn threadSanitizer(environment: *const std.process.Environ.Map) bool {
    return std.mem.eql(u8, environment.get("SELKA_CORE_SANITIZE") orelse "", "thread");
}

/// Address mode captures the separately supplied native sanitizer runtime.
pub fn addressSanitizer(environment: *const std.process.Environ.Map) bool {
    return std.mem.eql(u8, environment.get("SELKA_CORE_SANITIZE") orelse "", "address");
}

/// How the system closure is found (`native_closure.zig`), and where: a change of the rule is a change of every key.
fn closurePolicy(request: Request, hash: *fast_blake3.Blake3) void {
    field(hash, "native-closure-v1");
    field(hash, systemRoot(request));
    field(hash, closure.loader);
    for (closure.names) |name| field(hash, name);
    field(hash, closure.cache_path);
    field(hash, closure.preload_path);
    for (closure.default_directories) |directory| field(hash, directory);
    field(hash, if (addressSanitizer(request.environment)) platform.address_runtime.path else "");
}

fn approvalPath(request: Request, identity: Digest) Error![]const u8 {
    return std.fmt.allocPrint(request.arena, "{s}/approval-v4/{s}.memo", .{ try cacheRoot(request), std.fmt.bytesToHex(approvalKey(request, identity), .lower) });
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
    fast_blake3.hash(bytes[0 .. bytes.len - 32], &checksum);
    if (!std.mem.eql(u8, bytes[bytes.len - 32 ..], &checksum)) return null;
    return bytes[approval_magic.len + 32] == 1;
}

fn publishApproval(request: Request, identity: Digest, approved: bool) Error!void {
    var bytes: [approval_length]u8 = undefined;
    @memcpy(bytes[0..approval_magic.len], approval_magic);
    @memcpy(bytes[approval_magic.len..][0..32], &approvalKey(request, identity));
    bytes[approval_magic.len + 32] = @intFromBool(approved);
    fast_blake3.hash(bytes[0 .. bytes.len - 32], bytes[bytes.len - 32 ..]);
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

/// Whether results made with the toolchain at `path` may be reused: the pinned Zig distribution, standalone, with its
/// reviewed library tree. The system libraries and the C driver's discovery state are not asked: their bytes are in
/// `digest`, so every machine reuses under keys of its own (GH-3b).
fn reviewClosure(request: Request, path: []const u8, inputs: []const Input) Error!bool {
    if (!try toolchainReviewed(request, path, inputs)) return false;
    // A closure this compiler cannot key soundly (GH-3b review, R4 and D) names files the key cannot cover.
    return (try closure.resolve(request.arena, request.io, systemRoot(request))).unsound == null;
}

/// The toolchain half of `reviewClosure`: the pinned Zig distribution, standalone, with its reviewed library tree.
fn toolchainReviewed(request: Request, path: []const u8, inputs: []const Input) Error!bool {
    // This explicit target confines libc headers/CRT/link inputs to the reviewed
    // bundled distribution. Default native discovery also reads /usr inputs.
    if (!std.mem.eql(u8, target_policy.native_link_target, "x86_64-linux-gnu.2.31")) return false;
    if (!try standalone(request, path)) return false;
    const executable = candidateExecutable(inputs, path) orelse return false;
    const digest = try fileHash(Sha256, request, .{ .path = path, .resolved = path, .info = executable });
    if (!reviewedExecutable(digest)) return false;
    const adjacent = try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(path).?, "lib" });
    if (!try approvedLibrary(request, inputs, adjacent)) return false;
    if (request.environment.get(lib_directory)) |override| {
        if (!try approvedLibrary(request, inputs, try absolutePath(request, override))) return false;
    }
    return true;
}

/// One file of the system closure as `selka native show` prints it: where the loader looks, what that resolves to, and
/// the lowercase hex SHA-256 of its bytes (`absent` when it is not there or cannot be read).
pub const SystemFile = struct { path: []const u8, resolved: []const u8, sha256: []const u8 };

/// The machine's system closure now, for `selka native show`.
pub const System = struct {
    /// The loader and the candidates of each name that are there (readable or not).
    files: []const SystemFile,
    /// The files the preload file names that are there.
    preloaded: []const SystemFile,
    /// How many candidates are keyed as absent (the default directories' hwcaps and legacy subdirectories, mostly).
    absent: usize,
    /// The loader's cache could not be parsed, so its bytes are keyed too.
    cache_keyed: bool,
    /// Why the closure cannot be keyed soundly, so reuse is off (`native_closure.Closure.unsound`), or null.
    unsound: ?[]const u8,
    /// SHA-256 over every candidate's path, resolved path and digest (absent ones included): the closure alone, without
    /// the CPU and the toolchain, which the toolchain identity adds.
    digest: [64]u8,
};

/// Read the machine's system closure as builds key it.
pub fn system(request: Request) Error!System {
    const found = try closure.resolve(request.arena, request.io, systemRoot(request));
    var hash = Sha256.init(.{});
    shaField(&hash, "native-closure-show-v2");
    var absent: usize = 0;
    const files = try systemFiles(request, found.files, &hash, &absent);
    shaField(&hash, "preloaded");
    const preloaded = try systemFiles(request, found.preloaded, &hash, &absent);
    shaField(&hash, if (found.cache_keyed) "cache-keyed" else "cache-resolves");
    var raw: Digest = undefined;
    hash.final(&raw);
    return .{ .files = files, .preloaded = preloaded, .absent = absent, .cache_keyed = found.cache_keyed, .unsound = found.unsound, .digest = std.fmt.bytesToHex(raw, .lower) };
}

/// The present files among `paths` (an unreadable one with `unreadable (ERROR)` for its digest), every one hashed into
/// `hash`, and the absent ones counted.
fn systemFiles(request: Request, paths: []const []const u8, hash: *Sha256, absent: *usize) Error![]const SystemFile {
    var files: std.ArrayList(SystemFile) = .empty;
    for (paths) |path| {
        const input = try readableSnapshot(request, path, .system);
        const kind = if (input.info) |info| info.kind else .unknown;
        const blocked = std.mem.startsWith(u8, input.resolved, unreadable_marker);
        const digest: []const u8 = if (kind == .file)
            try request.arena.dupe(u8, &std.fmt.bytesToHex(try fileHash(Sha256, request, input), .lower))
        else if (blocked)
            try std.fmt.allocPrint(request.arena, "unreadable ({s})", .{input.resolved[unreadable_marker.len..]})
        else if (input.info != null) @tagName(kind) else "absent";
        const file: SystemFile = .{ .path = path, .resolved = if (blocked) path else input.resolved, .sha256 = digest };
        for ([_][]const u8{ file.path, file.resolved, file.sha256 }) |part| shaField(hash, part);
        if (input.info == null and !blocked) absent.* += 1 else try files.append(request.arena, file);
    }
    return files.items;
}

/// Every reason results made with the toolchain `identity` names are not reused, joined by "; ", or null when they
/// are: for `selka native show`, which must not hide one reason behind another.
pub fn reuseRefusal(request: Request, identity: Identity) Error!?[]const u8 {
    if (identity.cacheable) return null;
    var reasons: std.ArrayList(u8) = .empty;
    if (unsafeVariable(request.environment)) |name| try reasons.print(request.arena, "; {s} is set (a loader or compiler override the key does not cover)", .{name});
    if ((try closure.resolve(request.arena, request.io, systemRoot(request))).unsound) |why| try reasons.print(request.arena, "; {s}", .{why});
    const taken = try inventory(request, identity.path, identity.native_target);
    if (!try toolchainReviewed(request, identity.path, taken.inputs)) try reasons.appendSlice(request.arena, "; the Zig toolchain is not the pinned distribution, or not as it was installed");
    if (reasons.items.len == 0) return "the toolchain identity changed while it was read; run the command again";
    return reasons.items[2..];
}

/// The directory the system closure is read below in this compiler: "" except in one built with `-Dtest-system-root`,
/// which `selka --version` and `selka native show` name so it is not mistaken for an ordinary compiler.
pub fn builtSystemRoot() []const u8 {
    return if (@hasDecl(platform, "system_root")) platform.system_root else "";
}

/// The directory of this user's tool-identity memos (the same place builds keep them).
pub fn memoDirectory(request: Request) Error![]const u8 {
    return cacheRoot(request);
}

fn namedInput(inputs: []const Input, path: []const u8) ?Input {
    for (inputs) |input| if (std.mem.eql(u8, input.path, path)) return input;
    return null;
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
    var hash = Sha256.init(.{});
    shaField(&hash, "core-approved-zig-library-v1");
    for (chosen.items, 0..) |input, index| {
        if (index != 0 and std.mem.eql(u8, chosen.items[index - 1].relative, input.relative)) continue;
        const info = input.original.info orelse return null;
        if (info.kind != .file and info.kind != .directory) return null;
        shaField(&hash, input.relative);
        shaField(&hash, @tagName(info.kind));
        if (info.kind == .file) shaField(&hash, &try fileHash(Sha256, request, input.original));
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

fn libraryBefore(_: void, left: LibraryInput, right: LibraryInput) bool {
    return std.mem.lessThan(u8, left.relative, right.relative);
}

fn shaField(hash: *Sha256, bytes: []const u8) void {
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
        return .{ .arena = a, .io = std.testing.io, .environment = &self.environment, .executable = "zig", .cache = try std.fs.path.join(a, &.{ root, "cache" }) };
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
    // A file outside what `zig` reads (here, at the root of the library) is not a build
    // input; the root's entries are.
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

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "a same-size edit of a file zig reads, with its modification time put back, unproves an approved toolchain" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const approved = try capture(request);
    try std.testing.expect(approved.cacheable);
    try std.testing.expect(try unchanged(request, approved));
    const info = try fixture.temporary.dir.statFile(request.io, "lib/std/std.zig", .{});
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "other" });
    try fixture.temporary.dir.setTimestamps(request.io, "lib/std/std.zig", .{ .modify_timestamp = .init(info.mtime) });
    try std.testing.expect(!try unchanged(request, approved));
    const edited = try capture(request);
    try std.testing.expect(!edited.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &edited.digest, &approved.digest));
    try std.testing.expect(!std.mem.eql(u8, &edited.generation, &approved.generation));
    // Putting the original bytes back restores the review's verdict only through a fresh review.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "first" });
    const restored = try capture(request);
    try std.testing.expect(restored.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &restored.generation, &approved.generation));
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "a header that appears on the include path, or an edited one, moves the toolchain's identity" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try fixture.temporary.dir.createDirPath(request.io, "lib/include");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/include/stdbool.h", .data = "#define true 1\n" });
    const original = try capture(request);
    try std.testing.expect(try unchanged(request, original));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/include/stdbool.h", .data = "#define true 0\n" });
    try std.testing.expect(!try unchanged(request, original));
    const edited = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &edited.digest, &original.digest));
    try std.testing.expect(try unchanged(request, edited));
    // A header that is new beside the ones `zig` opened moves the directory they are in.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/include/stdint.h", .data = "shadow" });
    try std.testing.expect(!try unchanged(request, edited));
    const added = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &added.digest, &edited.digest));
    // A Zig source that appears among those compiler-rt and the stubs are built from shadows nothing:
    // imports name exact paths, so only the files already there are tracked.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/extra.zig", .data = "pub const x = 1;" });
    try std.testing.expect(try unchanged(request, added));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "other" });
    try std.testing.expect(!try unchanged(request, added));
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "an input below a directory that is absent is absent without a stat, and a directory that appears is a change" {
    var absent: std.StringHashMapUnmanaged(void) = .empty;
    defer absent.deinit(std.testing.allocator);
    try absent.put(std.testing.allocator, "/opt/gcc", {});
    try std.testing.expect(belowAbsent(&absent, "/opt/gcc/x86_64-linux-gnu"));
    try std.testing.expect(belowAbsent(&absent, "/opt/gcc/x86_64-linux-gnu/13"));
    try std.testing.expect(!belowAbsent(&absent, "/opt/gcc"));
    try std.testing.expect(!belowAbsent(&absent, "/opt/gcc-cross/x86_64-linux-gnu"));
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    // The library root holds no `gcc` directory, so discovery's candidates below it are recorded
    // absent; a directory made there moves the toolchain's identity.
    try fixture.temporary.dir.createDirPath(request.io, "lib/gcc/x86_64-linux-gnu");
    try std.testing.expect(!try unchanged(request, original));
}

// A libc-linked binary aborted here before the thread stack was raised: the thread could not start.
test "Check.begin keeps a thread of its own on the default stack" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    var check: Check = .{ .request = request, .original = original };
    check.begin();
    try std.testing.expect(check.thread != null);
    try std.testing.expect(try check.finish());
}

// spec-case: PROVABLE-CACHE-K1-TOOLFILES-1
test "Check.begin runs unchanged on a thread of its own and finish gives its answer, again and again" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    var same: Check = .{ .request = request, .original = original };
    same.begin();
    try std.testing.expect(try same.finish());
    try std.testing.expect(try same.finish());
    // With the inventory of the candidate in hand, the hint is not read again.
    const candidate = (try replayCandidate(request)).?;
    try std.testing.expectEqual(original.generation, candidate.identity.generation);
    var kept: Check = .{ .request = request, .original = candidate.identity, .inventory = candidate.inventory };
    kept.begin();
    try std.testing.expect(try kept.finish());
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "other" });
    var kept_edited: Check = .{ .request = request, .original = candidate.identity, .inventory = candidate.inventory };
    kept_edited.begin();
    try std.testing.expect(!try kept_edited.finish());
    var edited: Check = .{ .request = request, .original = original };
    edited.begin();
    try std.testing.expect(!try edited.finish());
    var failing: Check = .{ .request = request, .original = original };
    failing.request.arena = std.testing.failing_allocator;
    failing.begin();
    try std.testing.expectError(error.OutOfMemory, failing.finish());
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
    // A linked tree is reviewed at approval; only the files `zig` reads are rescanned per build.
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
    fast_blake3.hash(old_hint[0 .. old_hint.len - 32], old_hint[old_hint.len - 32 ..][0..32]);
    fast_blake3.hash(old_hint[0 .. old_hint.len - 32], old_hint[old_hint.len - 32 ..][0..32]);
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
    // A file `zig` reads edited in place: the hint still names the original, and the final
    // validation refuses it.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/std/std.zig", .data = "other" });
    const edited = (try lookupReplayCandidate(request)).?;
    try std.testing.expectEqual(original.digest, edited.digest);
    try std.testing.expect(!try unchanged(request, edited));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "lib/added.h", .data = "added" });
    const expanded = (try lookupReplayCandidate(request)).?;
    try std.testing.expect(!try unchanged(request, expanded));
    const fresh = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &fresh.digest, &original.digest));
}

// spec-case: NEW-CORE-S4-TEST-3
test "a changed tool input is a fresh capture miss, never SourceChanged" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    const original = try capture(request);
    try fixture.staticTool(2);
    const fresh = try capture(request);
    try std.testing.expect(!std.mem.eql(u8, &fresh.digest, &original.digest));
    try std.testing.expect(!std.mem.eql(u8, &fresh.generation, &original.generation));
    try std.testing.expect(try unchanged(request, fresh));
    try std.testing.expect(!try unchanged(request, original));
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

/// A system root in the fixture's directory, named for its captures through `SELKA_TEST_SYSTEM_ROOT`: the loader, the
/// four libraries under `lib/`, and a loader cache that maps each name to its file. No list names any of it.
fn systemRootFixture(fixture: *Fixture, request: Request) !void {
    const directory = fixture.temporary.dir;
    try directory.createDirPath(request.io, "system/etc");
    try directory.createDirPath(request.io, "system/lib64");
    try directory.createDirPath(request.io, "system/lib/other");
    try directory.writeFile(request.io, .{ .sub_path = "system/lib64/ld-linux-x86-64.so.2", .data = "loader" });
    for (closure.names) |name| try directory.writeFile(request.io, .{ .sub_path = try std.fs.path.join(request.arena, &.{ "system/lib", name }), .data = name });
    try writeSystemCache(fixture, request, "/lib/libm.so.6");
    try fixture.environment.put("SELKA_TEST_SYSTEM_ROOT", try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(request.cache).?, "system" }));
}

/// The fixture's loader cache, mapping each name to `/lib/NAME` except `libm.so.6`, which it maps to `libm`.
fn writeSystemCache(fixture: *Fixture, request: Request, libm: []const u8) !void {
    var entries: [closure.names.len]closure.Entry = undefined;
    for (closure.names, &entries) |name, *entry| {
        const path = if (std.mem.eql(u8, name, "libm.so.6")) libm else try std.fs.path.join(request.arena, &.{ "/lib", name });
        entry.* = .{ .name = name, .path = path };
    }
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.cache", .data = try closure.render(request.arena, &entries, false) });
}

/// The entry of `files` whose path ends in `suffix`.
fn systemFile(files: []const SystemFile, suffix: []const u8) ?SystemFile {
    for (files) |file| if (std.mem.endsWith(u8, file.path, suffix)) return file;
    return null;
}

// GH-3b: no machine falls back to reusing nothing; its libraries' bytes give it keys of its own.
test "a system closure no list names is reusable, and one changed byte in a closure library moves the digest" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const first = try capture(request);
    try std.testing.expect(first.cacheable);
    try std.testing.expect(systemFile((try system(request)).files, "/system/lib/libm.so.6") != null);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/lib/libm.so.6", .data = "libm.so.7" });
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
}

test "a rewritten loader cache that maps the names to the same files keeps the digest" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const first = try capture(request);
    try fixture.temporary.dir.deleteFile(request.io, "system/etc/ld.so.cache");
    try writeSystemCache(&fixture, request, "/lib/libm.so.6");
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &first.generation, &second.generation));
    try std.testing.expectEqual(first.digest, second.digest);
    try std.testing.expect(!(try system(request)).cache_keyed);
}

// GH-3f: the promise of the closure key. An install that adds a library none of the names refers to (an unattended upgrade
// of `libgstreamer`, which `ldconfig` then lists) changes nothing the loader could load for a built program, so no result
// goes cold; a byte of a library it could load still moves the digest.
test "an unrelated library added to a default directory and to the loader cache keeps the digest" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const first = try capture(request);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/lib/libgstreamer-1.0.so.0", .data = "an unrelated library" });
    var entries: [closure.names.len + 1]closure.Entry = undefined;
    for (closure.names, entries[0..closure.names.len]) |name, *entry| entry.* = .{ .name = name, .path = try std.fs.path.join(request.arena, &.{ "/lib", name }) };
    entries[closure.names.len] = .{ .name = "libgstreamer-1.0.so.0", .path = "/lib/libgstreamer-1.0.so.0" };
    try fixture.temporary.dir.deleteFile(request.io, "system/etc/ld.so.cache");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.cache", .data = try closure.render(request.arena, &entries, false) });
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &first.generation, &second.generation));
    try std.testing.expectEqual(first.digest, second.digest);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/lib/libm.so.6", .data = "libm.so.7" });
    try std.testing.expect(!std.mem.eql(u8, &second.digest, &(try capture(request)).digest));
}

/// The key an inventory hint had before GH-3f: `hintKey` without `closure.policy`.
fn keyBeforeClosureRules(request: Request, path: []const u8, cpu: Digest) !Digest {
    var hash = fast_blake3.Blake3.init(.{});
    field(&hash, hint_magic);
    field(&hash, path);
    field(&hash, &cpu);
    closurePolicy(request, &hash);
    field(&hash, if (threadSanitizer(request.environment)) "thread" else "");
    tool_files.definition(&hash);
    discovery.policy(&hash);
    field(&hash, "");
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// `inputs` without the absent candidates below a `tls` or `haswell` subdirectory: what an older rule did not look for.
fn withoutLegacyCandidates(request: Request, inputs: []const Input) ![]const Input {
    var kept: std.ArrayList(Input) = .empty;
    for (inputs) |input| {
        const legacy = std.mem.indexOf(u8, input.path, "/tls/") != null or std.mem.indexOf(u8, input.path, "/haswell/") != null;
        if (!(legacy and input.info == null)) try kept.append(request.arena, input);
    }
    return kept.items;
}

// GH-3f, the fault of 19 November: a hint written by a compiler that looked for fewer candidates (565 inputs where 949 are
// made now) was read by the compiler that looks for more, because the key held the default directories and not their
// subdirectories. Every input of that hint was unchanged, so its inventory and its identity were kept until the loader cache
// changed, and the identity then moved with nothing installed that the loader could load.
test "a hint recorded under another closure rule is not read" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const path = try resolve(request);
    const cpu = try nativeTarget(request.io);
    const fresh = try inventory(request, path, cpu);
    const older = try withoutLegacyCandidates(request, fresh.inputs);
    try std.testing.expect(older.len < fresh.inputs.len);
    try publishHintUnder(request, try keyBeforeClosureRules(request, path, cpu), older);
    const first = try capture(request);
    try std.testing.expect(!first.memo_hit);
    try std.testing.expectEqual(try contents(request, fresh.inputs, cpu), first.digest);
    try std.testing.expectEqual(fresh.inputs.len, first.inputs);
}

test "a loader cache that maps a name to another file moves the digest" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const first = try capture(request);
    // The same bytes at another place: the loader would load another file.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/lib/other/libm.so.6", .data = "libm.so.6" });
    try writeSystemCache(&fixture, request, "/lib/other/libm.so.6");
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
}

test "without a loader cache the default directories and the cache's absence are keyed" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    try fixture.temporary.dir.deleteFile(request.io, "system/etc/ld.so.cache");
    try fixture.temporary.dir.createDirPath(request.io, "system/usr/lib64");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/usr/lib64/libc.so.6", .data = "fedora libc" });
    const first = try capture(request);
    try std.testing.expect(first.cacheable);
    const found = try system(request);
    try std.testing.expect(found.cache_keyed);
    try std.testing.expect(!std.mem.eql(u8, systemFile(found.files, "/system/usr/lib64/libc.so.6").?.sha256, "absent"));
    // An absent candidate is keyed but not listed.
    try std.testing.expect(systemFile(found.files, "/system/lib64/libc.so.6") == null);
    try std.testing.expect(found.absent != 0);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/usr/lib64/libc.so.6", .data = "fedora libd" });
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &(try capture(request)).digest));
}

// GH-3b, decision 1: a preload file is machine state like the libraries; what it names is keyed and reuse stays on.
test "a non-empty preload keeps reuse on, and one changed byte in a file it names moves the digest" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const clear = try capture(request);
    try fixture.temporary.dir.createDirPath(request.io, "system/opt");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/opt/hook.so", .data = "hook" });
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "/opt/hook.so /opt/missing.so\n" });
    const first = try capture(request);
    try std.testing.expect(first.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &clear.digest, &first.digest));
    const found = try system(request);
    try std.testing.expect(!std.mem.eql(u8, systemFile(found.preloaded, "/system/opt/hook.so").?.sha256, "absent"));
    try std.testing.expect(systemFile(found.preloaded, "/system/opt/missing.so") == null);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/opt/hook.so", .data = "hool" });
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
}

// GH-3b review, R1: the loader falls back to the default directories when the file the cache lists cannot be opened.
test "a default-directory library moves the digest even when the cache lists the name elsewhere" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    try fixture.temporary.dir.createDirPath(request.io, "system/usr/local/lib");
    try fixture.temporary.dir.createDirPath(request.io, "system/lib/x86_64-linux-gnu");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/usr/local/lib/libgcc_s.so.1", .data = "listed" });
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/lib/x86_64-linux-gnu/libgcc_s.so.1", .data = "fallback" });
    var entries: [1]closure.Entry = .{.{ .name = "libgcc_s.so.1", .path = "/usr/local/lib/libgcc_s.so.1" }};
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.cache", .data = try closure.render(request.arena, &entries, false) });
    const first = try capture(request);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/lib/x86_64-linux-gnu/libgcc_s.so.1", .data = "fallbacl" });
    const second = try capture(request);
    try std.testing.expect(second.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &second.digest));
    // The listed file goes without `ldconfig`: the loader now loads the fallback, and the key moves again.
    try fixture.temporary.dir.deleteFile(request.io, "system/usr/local/lib/libgcc_s.so.1");
    try std.testing.expect(!std.mem.eql(u8, &second.digest, &(try capture(request)).digest));
}

// GH-3b review, R5: a system file the user cannot read is keyed as unreadable; the build neither fails nor reuses across.
// This shape needs no permissions, so it holds as root too (containers run as root).
test "a closure path through a regular file is keyed as unreadable and no capture fails" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    try fixture.temporary.dir.createDirPath(request.io, "system/opt");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/opt/hook.so", .data = "hook" });
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "/opt/hook.so/inner\n" });
    try writeSystemCache(&fixture, request, "/lib/libm.so.6/inner");
    const first = try capture(request);
    try std.testing.expect(first.cacheable);
    try std.testing.expect(try unchanged(request, first));
    const second = try capture(request);
    try std.testing.expectEqual(first.digest, second.digest);
    try std.testing.expectEqual(first.generation, second.generation);
    const found = try system(request);
    try std.testing.expect(std.mem.startsWith(u8, systemFile(found.preloaded, "/system/opt/hook.so/inner").?.sha256, "unreadable ("));
    try std.testing.expect(std.mem.startsWith(u8, systemFile(found.files, "/system/lib/libm.so.6/inner").?.sha256, "unreadable ("));
}

// GH-3b review, R5: the shapes that need permissions (a file that cannot be opened, one below a directory that cannot be
// searched). Root reads through mode 0, so `modeZeroShapes` checks nothing as root.
test "a closure file that cannot be opened or searched is keyed as unreadable and no capture fails" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try modeZeroShapes(&fixture);
    // Whoever runs it, the fixture's directory is left as it was found: removable.
    try std.testing.expect((try fixture.temporary.dir.statFile(std.testing.io, ".", .{})).kind == .directory);
}

fn modeZeroShapes(fixture: *Fixture) !void {
    if (std.os.linux.geteuid() == 0) return;
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(fixture, request);
    const directory = fixture.temporary.dir;
    try directory.createDirPath(request.io, "system/opt");
    try directory.createDirPath(request.io, "system/lib/sealed");
    try directory.writeFile(request.io, .{ .sub_path = "system/opt/locked.so", .data = "locked" });
    try directory.writeFile(request.io, .{ .sub_path = "system/lib/sealed/libm.so.6", .data = "sealed" });
    try directory.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "/opt/locked.so\n" });
    try writeSystemCache(fixture, request, "/lib/sealed/libm.so.6");
    try directory.setFilePermissions(request.io, "system/opt/locked.so", .fromMode(0o000), .{});
    try directory.setFilePermissions(request.io, "system/lib/sealed", .fromMode(0o000), .{});
    defer directory.setFilePermissions(request.io, "system/lib/sealed", .fromMode(0o755), .{}) catch {};
    defer directory.setFilePermissions(request.io, "system/opt/locked.so", .fromMode(0o644), .{}) catch {};
    const first = try capture(request);
    try std.testing.expect(first.cacheable);
    try std.testing.expect(try unchanged(request, first));
    const second = try capture(request);
    try std.testing.expectEqual(first.digest, second.digest);
    try std.testing.expectEqual(first.generation, second.generation);
    const found = try system(request);
    try std.testing.expect(std.mem.startsWith(u8, systemFile(found.preloaded, "/system/opt/locked.so").?.sha256, "unreadable ("));
    try std.testing.expect(std.mem.startsWith(u8, systemFile(found.files, "/system/lib/sealed/libm.so.6").?.sha256, "unreadable ("));
    // Readable again is another closure.
    try directory.setFilePermissions(request.io, "system/opt/locked.so", .fromMode(0o644), .{});
    try std.testing.expect(!std.mem.eql(u8, &first.digest, &(try capture(request)).digest));
}

// GH-3b review, R4: a preload entry that cannot be keyed soundly turns reuse off, and nothing fails.
test "a preload entry with a relative path or an unknown token turns reuse off without an error" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "lib/hook.so\n" });
    const relative = try capture(request);
    try std.testing.expect(!relative.cacheable);
    try std.testing.expect(std.mem.indexOf(u8, (try reuseRefusal(request, relative)).?, "relative path") != null);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "$ORIGIN/hook.so\n" });
    try std.testing.expect(!(try capture(request)).cacheable);
    // A comment and `$LIB` are what glibc reads too: reuse is on again.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "/usr/$LIB/hook.so # a comment\n" });
    try std.testing.expect((try capture(request)).cacheable);
}

test "a preload file emptied takes its files out of the closure and keeps reuse on" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    try fixture.temporary.dir.createDirPath(request.io, "system/opt");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/opt/hook.so", .data = "hook" });
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "/opt/hook.so\n" });
    const with = try capture(request);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/etc/ld.so.preload", .data = "" });
    const emptied = try capture(request);
    try std.testing.expect(emptied.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &with.digest, &emptied.digest));
    try std.testing.expectEqual(@as(usize, 0), (try system(request)).preloaded.len);
    // The hook's bytes no longer key anything.
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "system/opt/hook.so", .data = "hool" });
    try std.testing.expectEqual(emptied.digest, (try capture(request)).digest);
}

// GH-3b: the approvals file of `selka native approve` is read by nothing.
test "an approvals file, even an unparsable one, changes no capture" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const request = try fixture.request();
    try fixture.staticTool(1);
    try systemRootFixture(&fixture, request);
    const without = try capture(request);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "native-approvals", .data = "not an approvals file\n" });
    try fixture.environment.put("SELKA_NATIVE_APPROVALS", try std.fs.path.join(request.arena, &.{ std.fs.path.dirname(request.cache).?, "native-approvals" }));
    const with = try capture(request);
    try std.testing.expect(with.cacheable);
    try std.testing.expectEqual(without.digest, with.digest);
    try std.testing.expectEqual(without.generation, with.generation);
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
    // The preload file is a resolver, as `systemInputs` takes it.
    inputs.items[1].role = .resolver;
    _ = try addInput(request, &inputs, alias);
    const cpu = try nativeTarget(request.io);
    const original = inventoryDigest(inputs.items, cpu);
    const info = try fixture.temporary.dir.statFile(request.io, "libc.so.6", .{});
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "libc.so.6", .data = "other" });
    try fixture.temporary.dir.setTimestamps(request.io, "libc.so.6", .{ .modify_timestamp = .init(info.mtime) });
    const changed = (try refresh(request, inputs.items, cpu)).?;
    try std.testing.expect(!std.mem.eql(u8, &original, &changed.generation));
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "ld.so.preload", .data = "injected.so" });
    try std.testing.expect((try refresh(request, changed.inputs, cpu)) == null);
    // Emptied, it is still a change of what it names.
    const present = try request.arena.dupe(Input, changed.inputs);
    present[1] = try readableSnapshot(request, absent, .resolver);
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "ld.so.preload", .data = "" });
    try std.testing.expect((try refresh(request, present, cpu)) == null);
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
    const original = inventoryDigest(inputs.items, cpu);
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
    const original = inventoryDigest(inputs.items, cpu);
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
// The discovery state is keyed, not approved (GH-3b): the addition moves the digest, so no old result is served.
test "discovery higher priority resource addition refuses old replay and moves the digest" {
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
    const initial = try capture(request);
    try std.testing.expect(initial.cacheable);
    try std.testing.expect((try lookupReplayCandidate(request)) != null);
    try fixture.temporary.dir.createDirPath(request.io, "tool/lib/clang/22/share");
    try fixture.temporary.dir.writeFile(request.io, .{ .sub_path = "tool/lib/clang/22/share/ubsan_ignorelist.txt", .data = "# owned outside resource\n" });
    const provisional = (try lookupReplayCandidate(request)).?;
    try std.testing.expect(!try unchanged(request, provisional));
    const after = try capture(request);
    try std.testing.expect(after.cacheable);
    try std.testing.expect(!std.mem.eql(u8, &initial.digest, &after.digest));
    try std.testing.expect(!std.mem.eql(u8, &initial.generation, &after.generation));
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
