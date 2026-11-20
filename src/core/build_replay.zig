//! The whole-build replay: an unchanged `selka-core build` publishes the
//! executable its last identical build produced, without running the front end,
//! the whole-program pipeline, emission or any tool.
//!
//! Records live in `<cache>/replay-v1/<key>.<inputs>`: per entry and settings, the
//! `records_per_key` builds with different inputs that were used last (written, or
//! served by a replay) each keep a record, so undoing an edit or switching back to a
//! branch replays too, however many other states were built in between. The key covers the
//! compiler's identity, the command's flags, the entry and its project configuration
//! (resolved afresh on every build), the toolchain identity and the environment
//! variables the identity contract keys (`environment_identity.zon`: a terminal's
//! size, a job count or a cache location is not one). A record is the build's inputs
//! handle (`inputs.zig`): every file the build read, by absolute path, with the
//! digest of the bytes the build used, and the directory listings it consulted:
//! - each module source of the graph, as the front end checked it (a module name
//!   names exactly one file, and the standard library is part of the compiler);
//! - every embedded file and, for `interface_files` projects, every generated
//!   interface file (or its absence);
//! - each `--link` C source and every header its compiler depfile listed.
//! It also holds the program store entry with its digest and file status, and the
//! report text the build printed. A replay stats every listed file, hashes any
//! changed metadata (inode, size, modification or change time),
//! revalidates the toolchain, and checks the program entry before copying it.
const std = @import("std");
const product = @import("selka").product;
const fast_blake3 = @import("fast_blake3.zig");
const language = @import("selka");
const demand_generation = @import("demand_generation.zig");
const frontend = @import("frontend.zig");
const inputs_handle = @import("inputs.zig");
const program_store = @import("program_store.zig");
const project_entry = @import("project_entry.zig");
const replay_record = @import("replay_record.zig");
const tool_identity = @import("tool_identity.zig");
const unit_cache = @import("unit_cache.zig");
const Digest = unit_cache.Digest;

/// How many records, each for a different set of inputs, one entry and settings keep.
const records_per_key = 4;

/// What a build is, besides its sources: the command and where it caches.
pub const Context = struct {
    arena: std.mem.Allocator,
    io: std.Io,
    /// Where the build's step inputs are read and recorded: the sources the front
    /// end loaded, the keyed environment, and what `Entry.shadowedStandard`
    /// listed. The record kept for the build is this handle's.
    handle: *inputs_handle.Handle,
    /// The build's cache directory (`--cache-dir`).
    cache: []const u8,
    /// The `zig` the command named (`--zig`, `ZIG`, or `zig` on `PATH`).
    zig: []const u8,
    /// A canonical encoding of every flag that changes the executable.
    flags: []const u8,
    entry: project_entry.Entry,
};

/// Why a replay could not be read or written; a damaged record is a miss.
pub const Error = error{ OutOfMemory, WriteFailed };

const Stamp = struct { size: u64, inode: u64, mtime: i64, ctime: i64 };
/// The demand generation the recorded build published and its scope (`replay_record.zig`). Ownership proofs name no generation.
pub const Published = replay_record.Published;
const Snapshot = struct { key: []const u8, inputs: []const inputs_handle.Wire, program: []const u8, digest: []const u8, stamp: Stamp, report: []const u8, published: Published = .{} };
const Envelope = replay_record.Envelope;

/// Publish the recorded executable to `output` and append the recorded report when
/// every input is unchanged; false (a miss) otherwise, having written nothing.
pub fn replay(context: Context, output: []const u8, report: *std.ArrayList(u8)) Error!bool {
    const a = context.arena;
    const request = toolRequest(context);
    const found = tool_identity.replayCandidate(request) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    } orelse return false;
    const candidate = found.identity;
    // The candidate came from a memo; the replay is accepted only for the same executable, CPU and
    // library generations. Reading the status of the toolchain's files overlaps with reading the record's.
    var tool: tool_identity.Check = .{ .request = request, .original = candidate, .inventory = found.inventory };
    tool.begin();
    defer _ = tool.finish() catch false;
    const key = try settingsKey(context, candidate);
    // The newest record first: the usual unchanged rebuild matches it at once.
    for (try recordNames(context, key)) |name| {
        const snapshot = try load(context, name, key) orelse continue;
        const recorded = try inputs_handle.fromWire(a, snapshot.inputs) orelse continue;
        // If this build misses, its own record starts from this one's file stamps (`Handle.seal`).
        context.handle.inherit(recorded);
        var live = context.handle.live;
        live.observed = context.handle;
        if (!try inputs_handle.unchanged(live, recorded)) continue;
        const same_tool = tool.finish() catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            return false;
        };
        if (!same_tool) return false;
        if (!try programIntact(context, snapshot)) continue;
        _ = program_store.place(context.io, &.{snapshot.program}, output, program_store.hardLink) catch return false;
        try report.appendSlice(a, language.fix_tally.detach(snapshot.report));
        // The next real build reads the state this tree's build published, not the state of the last tree built.
        try demand_generation.adopt(a, context.io, demand_generation.demandScope(context.cache, context.entry.path, context.flags), snapshot.published.demand);
        // This build used the record and its program: retention keeps what builds last returned to, not only what they last wrote (F58).
        markUsed(context, name);
        program_store.markUsed(a, context.io, snapshot.program);
        return true;
    }
    return false;
}

/// Pin the files a checked build read, with the digests of the bytes it used, into
/// the build's handle; take them before anything else reads the disk
/// (`entry.validate` reads interface files). False when the set cannot be pinned
/// exactly, and the build then leaves no record.
pub fn inputs(context: Context, session: *const frontend.Session) Error!bool {
    return captured(context, session);
}

/// Record a successful build. Nothing is recorded for an unproved toolchain, a
/// build whose `--link` inputs changed while they compiled, sources that `inputs`
/// could not pin, or a file that changed after the build read it.
pub fn remember(context: Context, pinned: bool, tool: tool_identity.Identity, outcome: Outcome, report: []const u8, published: Published) Error!void {
    const a = context.arena;
    if (!tool.cacheable or !pinned) return;
    const program = outcome.program orelse return;
    const foreign = outcome.foreign orelse return;
    const status = std.Io.Dir.cwd().statFile(context.io, program.path, .{}) catch return;
    const key = try settingsKey(context, tool);
    try context.handle.merge(foreign);
    const sealed = try context.handle.seal() orelse return;
    // The report keeps, behind a marker, which of its diagnostics `selka fix` repairs, so a replay closes as this build does.
    const kept = try language.fix_tally.attach(a, report);
    const snapshot: Snapshot = .{
        .key = try hex(a, key),
        .inputs = try inputs_handle.toWire(a, sealed),
        .program = program.path,
        .digest = try hex(a, program.digest),
        .stamp = stamp(status),
        .report = kept,
        .published = published,
    };
    const payload = std.json.Stringify.valueAlloc(a, snapshot, .{ .emit_null_optional_fields = false }) catch return error.OutOfMemory;
    var checksum: Digest = undefined;
    fast_blake3.hash(payload, &checksum);
    const envelope: Envelope = .{ .version = replay_record.version, .payload = payload, .checksum = try hex(a, checksum) };
    const bytes = std.json.Stringify.valueAlloc(a, envelope, .{}) catch return error.OutOfMemory;
    try atomicWrite(context, try recordPath(context, key, inputs_handle.identityDigest(sealed)), bytes);
    try keepNewest(context, key);
}

/// The names of `key`'s records in the record directory, the one used last first: a record is as new as its modification time, which
/// `remember` sets when it writes the record and `markUsed` sets when a replay serves it.
fn recordNames(context: Context, key: Digest) Error![]const []const u8 {
    const a = context.arena;
    const Named = struct { name: []const u8, written: i96 };
    var found: std.ArrayList(Named) = .empty;
    var directory = std.Io.Dir.cwd().openDir(context.io, try recordDirectory(context), .{ .iterate = true }) catch return &.{};
    defer directory.close(context.io);
    const prefix = try std.fmt.allocPrint(a, "{s}.", .{std.fmt.bytesToHex(key, .lower)});
    var entries = directory.iterate();
    while (entries.next(context.io) catch return &.{}) |entry| {
        if (entry.kind != .file or !std.mem.startsWith(u8, entry.name, prefix) or std.mem.endsWith(u8, entry.name, ".partial")) continue;
        const status = directory.statFile(context.io, entry.name, .{}) catch continue;
        try found.append(a, .{ .name = try a.dupe(u8, entry.name), .written = status.mtime.nanoseconds });
    }
    std.mem.sort(Named, found.items, {}, struct {
        fn newer(_: void, left: Named, right: Named) bool {
            return left.written > right.written or (left.written == right.written and std.mem.lessThan(u8, left.name, right.name));
        }
    }.newer);
    const names = try a.alloc([]const u8, found.items.len);
    for (found.items, names) |item, *name| name.* = item.name;
    return names;
}

/// Mark the record `name` as used now, so `keepNewest` ranks by use and not only by when a record was written: a build that returns to an
/// earlier state keeps that state's record however many other states were built since. Best effort, and only for a file of the cache's
/// own (`program_store.stampUsed`).
fn markUsed(context: Context, name: []const u8) void {
    const path = std.fs.path.join(context.arena, &.{ recordDirectory(context) catch return, name }) catch return;
    program_store.stampUsed(context.io, path);
}

/// Remove `key`'s records beyond the newest `records_per_key` (the ones used last); best effort, since a
/// stale extra record is only a slower miss.
fn keepNewest(context: Context, key: Digest) Error!void {
    const names = try recordNames(context, key);
    if (names.len <= records_per_key) return;
    var directory = std.Io.Dir.cwd().openDir(context.io, try recordDirectory(context), .{}) catch return;
    defer directory.close(context.io);
    for (names[records_per_key..]) |name| directory.deleteFile(context.io, name) catch continue;
}

/// The parts of `driver.Outcome` a record needs.
pub const Outcome = struct { program: ?unit_cache.Found, foreign: ?[]const inputs_handle.Input };

/// The record's key: compiler, flags, entry, configuration, toolchain and the keyed environment.
pub fn settingsKey(context: Context, tool: tool_identity.Identity) Error!Digest {
    var hash = fast_blake3.Blake3.init(.{});
    unit_cache.field(&hash, replay_record.version);
    unit_cache.field(&hash, frontend.compiler_identity);
    unit_cache.field(&hash, context.flags);
    // `--link` compiles name their sources relative to it in debug information.
    unit_cache.field(&hash, context.handle.workingDirectory());
    unit_cache.field(&hash, context.zig);
    unit_cache.field(&hash, tool.path);
    unit_cache.field(&hash, &tool.digest);
    unit_cache.field(&hash, &tool.native_target);
    unit_cache.field(&hash, context.entry.path);
    unit_cache.field(&hash, context.entry.root);
    unit_cache.field(&hash, context.entry.name);
    if (context.entry.configuration) |configured| {
        unit_cache.field(&hash, configured.path);
        // Less the `stores` member (FR8): where the stores are is placement, and a file without one keys as it always did.
        unit_cache.field(&hash, try configured.keyBytes(context.arena));
        if (configured.policy) |policy| {
            unit_cache.field(&hash, policy.path);
            unit_cache.field(&hash, policy.bytes);
        }
    } else unit_cache.field(&hash, "no configuration");
    for (try context.handle.keyedEnvironment()) |variable| {
        unit_cache.field(&hash, variable.name);
        unit_cache.field(&hash, variable.value.?);
    }
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

/// Every source, embedded file and interface file the build read, with the bytes
/// the front end used, pinned into the handle. False when the set cannot be pinned
/// exactly.
fn captured(context: Context, session: *const frontend.Session) Error!bool {
    const a = context.arena;
    if (session.single) |unit| return loaded(context, context.entry.path, unit.src);
    const interfaces = if (context.entry.configuration) |configured| configured.document.interface_files else false;
    var entry_read = false;
    for (session.project.modules.items) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        const path = try std.fs.path.join(a, &.{ context.entry.root, module.src.path });
        entry_read = entry_read or std.mem.eql(u8, path, context.entry.path);
        if (!try loaded(context, path, module.src)) return false;
        if (!interfaces) continue;
        const api = try std.fmt.allocPrint(a, "{s}.api", .{product.chopSource(path)});
        _ = context.handle.digest(api) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ReadFailed => return false,
        };
    }
    // The entry file decides whether the build checks a module graph at all.
    return entry_read;
}

fn loaded(context: Context, path: []const u8, source: language.source.Source) Error!bool {
    try context.handle.pin(path, source.bytes);
    for (source.embeds) |embed| {
        if (embed.status != .ok) return false;
        const asset = try std.fs.path.resolve(context.arena, &.{ std.fs.path.dirname(path) orelse ".", embed.path });
        try context.handle.pin(asset, embed.contents);
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

fn load(context: Context, name: []const u8, key: Digest) Error!?Snapshot {
    const a = context.arena;
    const path = try std.fs.path.join(a, &.{ try recordDirectory(context), name });
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, path, a, .limited(64 << 20)) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return null;
    };
    const envelope = replay_record.open(a, bytes) orelse return null;
    const snapshot = std.json.parseFromSliceLeaky(Snapshot, a, envelope.payload, .{}) catch return null;
    const stored_key = parseDigest(snapshot.key) orelse return null;
    if (!std.mem.eql(u8, &stored_key, &key)) return null;
    return snapshot;
}

fn recordDirectory(context: Context) Error![]const u8 {
    return std.fs.path.join(context.arena, &.{ context.cache, "replay-v1" });
}

fn recordPath(context: Context, key: Digest, inputs_digest: Digest) Error![]const u8 {
    return std.fmt.allocPrint(context.arena, "{s}/replay-v1/{s}.{s}", .{ context.cache, std.fmt.bytesToHex(key, .lower), std.fmt.bytesToHex(inputs_digest, .lower) });
}

fn toolRequest(context: Context) tool_identity.Request {
    return .{ .arena = context.arena, .io = context.io, .environment = context.handle.live.environment, .executable = context.zig, .cache = context.cache };
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
test "replay keys cover flags, the tool, configuration and the keyed environment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    try environment.put("SOURCE_DATE_EPOCH", "2");
    try environment.put("SELKA_CORE_LAYOUT", "1");
    var handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    const tool: tool_identity.Identity = .{ .path = "/zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = true, .cacheable = true };
    const context: Context = .{ .arena = a, .io = std.testing.io, .handle = &handle, .cache = "cache", .zig = "zig", .flags = "{\"release\":false}", .entry = .{ .path = "/p/main.selka", .root = "/p", .name = "main" } };
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
    try environment.put("SELKA_CORE_LAYOUT", "changed");
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(context, tool)));
    try environment.put("SELKA_CORE_LAYOUT", "1");
    try std.testing.expectEqual(original, try settingsKey(context, tool));
    try environment.put("SOURCE_DATE_EPOCH", "3");
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(context, tool)));
    try environment.put("SOURCE_DATE_EPOCH", "2");
    // Shell bookkeeping, placement and unclassified variables never enter the key.
    try environment.put("_", "/usr/bin/taskset");
    try environment.put("SHLVL", "3");
    try environment.put("SELKA_PROFILE_DIR", "/independent/profile/archive");
    try environment.put("SELKA_ADMISSION_KIND", "timing");
    try environment.put("HOME", "/elsewhere");
    try environment.put("TMPDIR", "/scratch");
    try environment.put("PATH", "/opt/bin:/usr/bin");
    try environment.put("UNRELATED_TOOL_SETTING", "1");
    try std.testing.expectEqual(original, try settingsKey(context, tool));
    changed = context;
    changed.entry.path = "/p/other.selka";
    try std.testing.expect(!std.mem.eql(u8, &original, &try settingsKey(changed, tool)));
}

/// Write `count` records of `key` named by their index, record i with the modification time of second 1000 + i: a higher index is newer.
fn writeRecords(context: Context, key: Digest, count: u8) !void {
    const directory = try recordDirectory(context);
    try std.Io.Dir.cwd().createDirPath(context.io, directory);
    for (0..count) |index| {
        const path = try std.fmt.allocPrint(context.arena, "{s}/{s}.{d}", .{ directory, std.fmt.bytesToHex(key, .lower), index });
        try std.Io.Dir.cwd().writeFile(context.io, .{ .sub_path = path, .data = "record" });
        const written: i96 = (1000 + @as(i96, @intCast(index))) * std.time.ns_per_s;
        try std.Io.Dir.cwd().setTimestamps(context.io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = written } } });
    }
}

// spec-case: NEW-CORE-S4-REPLAY-1
test "retention keeps the records used last, so a record a replay served outlives newer ones, and a hard-linked record keeps its time" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    var handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const context: Context = .{ .arena = a, .io = std.testing.io, .handle = &handle, .cache = root, .zig = "zig", .flags = "{}", .entry = .{ .path = "/p/main.selka", .root = "/p", .name = "main" } };
    const key: Digest = @splat(7);
    const prefix = try std.fmt.allocPrint(a, "{s}.", .{std.fmt.bytesToHex(key, .lower)});
    // Five records, record 0 the oldest written; a replay serves it, and the next build writes nothing newer than the others.
    try writeRecords(context, key, records_per_key + 1);
    markUsed(context, try std.fmt.allocPrint(a, "{s}0", .{prefix}));
    const names = try recordNames(context, key);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}0", .{prefix}), names[0]);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}4", .{prefix}), names[1]);
    try keepNewest(context, key);
    const kept = try recordNames(context, key);
    try std.testing.expectEqual(@as(usize, records_per_key), kept.len);
    try std.testing.expectEqualStrings(try std.fmt.allocPrint(a, "{s}0", .{prefix}), kept[0]);
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(std.testing.io, try std.fmt.allocPrint(a, "{s}/replay-v1/{s}1", .{ root, prefix }), .{}));
    // A record with a second name keeps its time: moving it would move the other name's order too. An absent record is no error.
    const linked = try std.fmt.allocPrint(a, "{s}/replay-v1/{s}4", .{ root, prefix });
    const second_name = try std.fmt.allocPrint(a, "{s}/second-name", .{root});
    try std.Io.Dir.cwd().hardLink(linked, std.Io.Dir.cwd(), second_name, std.testing.io, .{});
    markUsed(context, try std.fmt.allocPrint(a, "{s}4", .{prefix}));
    markUsed(context, "absent");
    const status = try std.Io.Dir.cwd().statFile(std.testing.io, linked, .{});
    try std.testing.expectEqual(@as(i96, 1004 * std.time.ns_per_s), status.mtime.nanoseconds);
}

// spec-case: PROVABLE-CACHE-K1-ENV-1
test "a terminal, locale, placement or bookkeeping variable changes nothing a replay is keyed by, a keyed one does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    const tool: tool_identity.Identity = .{ .path = "/zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = true, .cacheable = true };
    const context: Context = .{ .arena = a, .io = std.testing.io, .handle = &handle, .cache = "cache", .zig = "zig", .flags = "{}", .entry = .{ .path = "/p/main.selka", .root = "/p", .name = "main" } };
    const original = try settingsKey(context, tool);
    const ignored = [_][2][]const u8{
        .{ "TERM", "xterm-256color" },         .{ "COLUMNS", "132" },             .{ "LINES", "50" },
        .{ "LANG", "C.UTF-8" },                .{ "TZ", "UTC" },                  .{ "HOME", "/home/other" },
        .{ "PATH", "/elsewhere" },             .{ "TMPDIR", "/tmp/other" },       .{ "SELKA_JOBS", "3" },
        .{ "SELKA_PROFILE_DIR", "/p" },        .{ "ZIG_GLOBAL_CACHE_DIR", "/g" }, .{ "ZIG_LOCAL_CACHE_DIR", "/l" },
        .{ "_", "/usr/bin/taskset" },          .{ "SHLVL", "3" },                 .{ "OLDPWD", "/old" },
        .{ "SOME_UNLISTED_NAME", "anything" },
    };
    for (ignored) |pair| {
        try environment.put(pair[0], pair[1]);
        try std.testing.expectEqual(original, try settingsKey(context, tool));
    }
}

// spec-case: PROVABLE-CACHE-K1-ENV-1
test "each variable the contract keys changes a replay key when set, changed or removed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    var handle = inputs_handle.Handle.init(a, std.testing.io, &environment);
    const tool: tool_identity.Identity = .{ .path = "/zig", .digest = @splat(1), .generation = @splat(2), .native_target = @splat(3), .inputs = 0, .memo_hit = true, .cacheable = true };
    const context: Context = .{ .arena = a, .io = std.testing.io, .handle = &handle, .cache = "cache", .zig = "zig", .flags = "{}", .entry = .{ .path = "/p/main.selka", .root = "/p", .name = "main" } };
    const original = try settingsKey(context, tool);
    const keyed = [_][]const u8{ "SELKA_CORE_SANITIZE", "SOURCE_DATE_EPOCH", "ZERO_AR_DATE", "CCC_OVERRIDE_OPTIONS", "ZIG_LIB_DIR", "CPATH", "LD_PRELOAD", "SELKA_X" };
    for (keyed) |name| {
        try environment.put(name, "1");
        const set = try settingsKey(context, tool);
        try std.testing.expect(!std.mem.eql(u8, &original, &set));
        try environment.put(name, "2");
        try std.testing.expect(!std.mem.eql(u8, &set, &try settingsKey(context, tool)));
        _ = environment.swapRemove(name);
        try std.testing.expectEqual(original, try settingsKey(context, tool));
    }
}
