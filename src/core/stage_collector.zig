//! The collector of the shared stage store (`stage-artifacts-v1`). Correctness never depends on it: a record it removes is a miss,
//! and the build recomputes the same bytes. What it protects is warmth. Each worktree writes a live root after a build: the
//! 8-byte prefixes of the shared keys that build used, with the work directory's path and the time. The collector keeps
//!   - every record a live root names (roots older than 14 days, or whose work directory is gone, are dropped);
//!   - every pack written or read since the oldest live lease began (the epoch E), with a 2 s margin for timestamp granularity,
//!     and every pack younger than 14 days.
//! Packs older than both are candidates: their live records move into fresh packs and the old packs are removed. Over the size
//! cap, the collector may also evict packs older than E - 2 s that hold no live record, oldest first. A reader that holds an
//! old pack open keeps reading it, and a reader that finds a removed record misses.
const std = @import("std");
const fast_blake3 = @import("fast_blake3.zig");
const packs = @import("stage_pack.zig");
const leases = @import("stage_leases.zig");

/// The directory of live roots under a namespace root.
pub const roots_leaf = "roots";
/// The suffix of a live root's file name.
pub const root_suffix = ".live";
const root_magic = "selka-stage-live-v1\n";
/// The files that order collections: the collector's exclusive lock, the time of the last one, and a probe whose
/// modification time reads the file system's clock.
pub const collector_leaf = "collector.lock";
pub const last_leaf = "collect.last";
pub const probe_leaf = "collect.probe";
/// The collection log, one line per collection that ran.
pub const log_leaf = "collect.log";
/// Live roots that are older than this do not protect their records.
pub const warm_ns: i96 = 14 * 24 * 60 * 60 * 1_000_000_000;
/// At most one collection in this interval.
pub const interval_ns: i96 = 600 * 1_000_000_000;
/// The margin that covers modification-time granularity around the epoch.
pub const margin_ns: i96 = 2 * 1_000_000_000;
/// The default size cap of the shared namespace, in bytes: about fourteen 400k-function states (250-300 MB each) or sixty 99k ones (63 MB
/// each), on a disk that also holds the compiler and test stores. A collection runs at most every ten minutes, so the namespace is soft
/// between them. `selka cache configure --kind stages --max-bytes N` persists another cap in the namespace's `policy` file.
pub const default_cap: u64 = 4 << 30;
/// The file of the namespace's policy: `max_bytes=N`, one line.
pub const policy_leaf = "policy";

/// What the collector enforces on a namespace, as persisted in its `policy` file.
pub const Policy = struct { max_bytes: u64 = default_cap };

/// The namespace's persisted policy, or the default when the file is absent or unreadable (a damaged policy never stops a build).
pub fn loadPolicy(a: std.mem.Allocator, io: std.Io, root: []const u8) Policy {
    const path = std.fs.path.join(a, &.{ root, policy_leaf }) catch return .{};
    const text = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(4096)) catch return .{};
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (!std.mem.startsWith(u8, line, "max_bytes=")) continue;
        const bytes = std.fmt.parseInt(u64, std.mem.trim(u8, line["max_bytes=".len..], " \r"), 10) catch return .{};
        return .{ .max_bytes = bytes };
    }
    return .{};
}

/// Why a policy could not be saved.
pub const PolicyError = error{WriteFailed};

/// Persist `policy` in namespace `root` by temporary file and rename, so a collector reading it sees the old or the new one whole.
pub fn savePolicy(a: std.mem.Allocator, io: std.Io, root: []const u8, policy: Policy) PolicyError!void {
    savePolicyChecked(a, io, root, policy) catch return error.WriteFailed;
}

fn savePolicyChecked(a: std.mem.Allocator, io: std.Io, root: []const u8, policy: Policy) !void {
    const final = try std.fs.path.join(a, &.{ root, policy_leaf });
    const temporary = try std.fmt.allocPrint(a, "{s}.partial", .{final});
    const text = try std.fmt.allocPrint(a, "max_bytes={d}\n", .{policy.max_bytes});
    var file = try std.Io.Dir.cwd().createFile(io, temporary, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, text);
    try std.Io.Dir.rename(std.Io.Dir.cwd(), temporary, std.Io.Dir.cwd(), final, io);
}
/// Records per compaction band, in bytes (`stage_pack.default_band_bytes`).
const band_bytes = packs.default_band_bytes;

/// What one collection did. `unmet` is set when the live and protected packs alone exceed the cap.
pub const Report = struct {
    /// A preview: nothing was compacted, evicted or dropped, and `bytes_after` is `bytes_before` less the packs it would evict.
    dry_run: bool = false,
    bytes_before: u64 = 0,
    bytes_after: u64 = 0,
    prefixes: u64 = 0,
    leases: u64 = 0,
    evicted: u64 = 0,
    unmet: bool = false,
};

/// The file name of the live root of work directory `work`: the first 16 hex digits of the BLAKE3 of its path.
pub fn rootFileName(a: std.mem.Allocator, work: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    fast_blake3.hash(work, &digest);
    const hex = std.fmt.bytesToHex(digest, .lower);
    return std.fmt.allocPrint(a, "{s}{s}", .{ hex[0..16], root_suffix });
}

/// Write the live root of work directory `work` in namespace `root`: its keys' 8-byte prefixes, sorted and unique, by temporary
/// file and rename. Best effort: a root that cannot be written costs its records their warmth, nothing else.
pub fn writeRoot(a: std.mem.Allocator, io: std.Io, root: []const u8, work: []const u8, keys: []const [32]u8) void {
    writeRootChecked(a, io, root, work, keys) catch return;
}

fn writeRootChecked(a: std.mem.Allocator, io: std.Io, root: []const u8, work: []const u8, keys: []const [32]u8) !void {
    const prefixes = try a.alloc([8]u8, keys.len);
    for (keys, prefixes) |key, *prefix| prefix.* = key[0..8].*;
    std.mem.sort([8]u8, prefixes, {}, lessPrefix);
    var count: usize = 0;
    for (prefixes, 0..) |prefix, index| {
        if (index == 0 or !std.mem.eql(u8, &prefix, &prefixes[index - 1])) {
            prefixes[count] = prefix;
            count += 1;
        }
    }
    var bytes: std.ArrayList(u8) = .empty;
    try bytes.appendSlice(a, root_magic);
    var length: [4]u8 = undefined;
    std.mem.writeInt(u32, &length, @intCast(work.len), .little);
    try bytes.appendSlice(a, &length);
    try bytes.appendSlice(a, work);
    var total: [8]u8 = undefined;
    std.mem.writeInt(u64, &total, count, .little);
    try bytes.appendSlice(a, &total);
    for (prefixes[0..count]) |prefix| try bytes.appendSlice(a, &prefix);
    const directory = try std.fs.path.join(a, &.{ root, roots_leaf });
    std.Io.Dir.cwd().createDirPath(io, directory) catch return error.WriteFailed;
    const name = try rootFileName(a, work);
    const final = try std.fs.path.join(a, &.{ directory, name });
    const temporary = try std.fmt.allocPrint(a, "{s}.partial", .{final});
    var file = try std.Io.Dir.cwd().createFile(io, temporary, .{});
    defer file.close(io);
    try file.writeStreamingAll(io, bytes.items);
    try std.Io.Dir.rename(std.Io.Dir.cwd(), temporary, std.Io.Dir.cwd(), final, io);
}

fn lessPrefix(_: void, lhs: [8]u8, rhs: [8]u8) bool {
    return std.mem.lessThan(u8, &lhs, &rhs);
}

/// One live root read back: its work directory and the 8-byte prefixes it names.
const Root = struct { work: []const u8, prefixes: []const [8]u8, mtime: i96, path: []const u8 };

fn readRoot(a: std.mem.Allocator, io: std.Io, path: []const u8) !?Root {
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(64 << 20)) catch return null;
    if (bytes.len < root_magic.len + 4 + 8 or !std.mem.eql(u8, bytes[0..root_magic.len], root_magic)) return null;
    const length = std.mem.readInt(u32, bytes[root_magic.len..][0..4], .little);
    const work_start = root_magic.len + 4;
    if (bytes.len < work_start + length + 8) return null;
    const work = bytes[work_start..][0..length];
    const count: usize = @intCast(std.mem.readInt(u64, bytes[work_start + length ..][0..8], .little));
    const body = work_start + length + 8;
    if (bytes.len != body + count * 8) return null;
    const prefixes = try a.alloc([8]u8, count);
    for (prefixes, 0..) |*prefix, index| prefix.* = bytes[body + index * 8 ..][0..8].*;
    const stat = std.Io.Dir.cwd().statFile(io, path, .{}) catch return null;
    return .{ .work = work, .prefixes = prefixes, .mtime = stat.mtime.nanoseconds, .path = path };
}

/// Collect the shared namespace `root`, whose packs `state` holds, if the interval has passed and no other collector runs.
/// Null when it did not run. The caller holds no lease on `root`'s registry lock.
pub fn collectIfDue(a: std.mem.Allocator, io: std.Io, root: []const u8, state: *packs.State, cap: u64) std.mem.Allocator.Error!?Report {
    const lock_file = std.Io.Dir.cwd().createFile(io, try std.fs.path.join(a, &.{ root, collector_leaf }), .{ .read = true, .truncate = false }) catch return null;
    defer lock_file.close(io);
    if (!(lock_file.tryLock(io, .exclusive) catch false)) return null;
    defer lock_file.unlock(io);
    const now = (try clockNow(a, io, root)) orelse return null;
    const last_path = try std.fs.path.join(a, &.{ root, last_leaf });
    if (std.Io.Dir.cwd().statFile(io, last_path, .{})) |stat| {
        if (now - stat.mtime.nanoseconds < interval_ns) return null;
    } else |_| {}
    const last = std.Io.Dir.cwd().createFile(io, last_path, .{ .truncate = false }) catch return null;
    defer last.close(io);
    // Without a stamp the interval cannot be kept, so the collection waits for a later build (warmth, never records).
    last.setTimestampsNow(io) catch return null;
    const report = try collect(a, io, root, state, cap, now);
    return report;
}

/// A collection now, whatever the interval says (`selka cache gc --kind stages --apply`): null when another collector holds the lock.
/// The preview takes no lock, since it changes nothing.
pub fn collectNow(a: std.mem.Allocator, io: std.Io, root: []const u8, state: *packs.State, request: Request) std.mem.Allocator.Error!?Report {
    const now = (try clockNow(a, io, root)) orelse return null;
    var timed = request;
    timed.now = now;
    if (request.dry_run) return collectWith(a, io, root, state, timed);
    const lock_file = std.Io.Dir.cwd().createFile(io, try std.fs.path.join(a, &.{ root, collector_leaf }), .{ .read = true, .truncate = false }) catch return null;
    defer lock_file.close(io);
    if (!(lock_file.tryLock(io, .exclusive) catch false)) return null;
    defer lock_file.unlock(io);
    return collectWith(a, io, root, state, timed);
}

/// The file system's clock: the modification time of the probe file, set now.
pub fn clockNow(a: std.mem.Allocator, io: std.Io, root: []const u8) std.mem.Allocator.Error!?i96 {
    const probe = std.Io.Dir.cwd().createFile(io, try std.fs.path.join(a, &.{ root, probe_leaf }), .{ .truncate = false }) catch return null;
    defer probe.close(io);
    probe.setTimestampsNow(io) catch return null;
    const stat = probe.stat(io) catch return null;
    return stat.mtime.nanoseconds;
}

/// What one collection is asked: the size cap, the time it runs at, and whether it only previews (changes no file).
pub const Request = struct { cap: u64, now: i96, dry_run: bool = false };

/// One collection at time `now`: scan the leases, read the live roots, compact the candidate packs, and evict over the cap.
pub fn collect(a: std.mem.Allocator, io: std.Io, root: []const u8, state: *packs.State, cap: u64, now: i96) std.mem.Allocator.Error!?Report {
    return collectWith(a, io, root, state, .{ .cap = cap, .now = now });
}

/// `collect`, or its preview: a dry run reads the leases and the live roots and reports the packs it would evict, and writes nothing.
pub fn collectWith(a: std.mem.Allocator, io: std.Io, root: []const u8, state: *packs.State, request: Request) std.mem.Allocator.Error!?Report {
    const cap = request.cap;
    const now = request.now;
    const dry_run = request.dry_run;
    const registry = std.Io.Dir.cwd().createFile(io, try std.fs.path.join(a, &.{ root, leases.registry_leaf }), .{ .read = true, .truncate = false }) catch return null;
    defer registry.close(io);
    registry.lock(io, .exclusive) catch return null;
    const scan = try leases.scan(io, root, a);
    registry.unlock(io);
    const epoch = if (scan.oldest) |oldest| @min(oldest, now) else now;
    const warm_cut = now - warm_ns;
    const cut = @min(epoch - margin_ns, warm_cut);
    var ranks: packs.Ranks = .empty;
    const directory = try std.fs.path.join(a, &.{ root, roots_leaf });
    var dropped: u64 = 0;
    if (std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true })) |opened| {
        var dir = opened;
        defer dir.close(io);
        var entries = dir.iterate();
        while (entries.next(io) catch null) |entry| {
            if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, root_suffix)) continue;
            const path = try std.fs.path.join(a, &.{ directory, entry.name });
            const root_file = (try readRoot(a, io, path)) orelse continue;
            const gone = if (std.Io.Dir.cwd().access(io, root_file.work, .{})) |_| false else |_| true;
            if (gone or root_file.mtime < warm_cut) {
                if (!dry_run) std.Io.Dir.cwd().deleteFile(io, path) catch continue;
                dropped += 1;
                continue;
            }
            for (root_file.prefixes) |prefix| {
                const rank = ranks.count();
                try ranks.put(a, std.mem.readInt(u64, &prefix, .little), rank);
            }
        }
    } else |_| {}
    const before = try state.packStats(a, &ranks);
    var bytes_before: u64 = 0;
    var candidates: std.ArrayList(u32) = .empty;
    for (before) |stat| {
        bytes_before += stat.bytes;
        if (stat.mtime < cut) try candidates.append(a, stat.id);
    }
    if (candidates.items.len > 0 and !dry_run) _ = try state.compactIn(&ranks, band_bytes, candidates.items);
    const after = if (dry_run) before else try state.packStats(a, &ranks);
    var bytes_after: u64 = 0;
    for (after) |stat| bytes_after += stat.bytes;
    var report: Report = .{ .dry_run = dry_run, .bytes_before = bytes_before, .bytes_after = bytes_after, .prefixes = ranks.count(), .leases = scan.live };
    if (bytes_after > cap) {
        // Oldest first, over the cap: packs older than the epoch's margin that no live root names.
        const Pick = struct { id: u32, mtime: i96, bytes: u64 };
        var picks: std.ArrayList(Pick) = .empty;
        for (after) |stat| {
            if (stat.live == 0 and stat.mtime < epoch - margin_ns) try picks.append(a, .{ .id = stat.id, .mtime = stat.mtime, .bytes = stat.bytes });
        }
        std.mem.sort(Pick, picks.items, {}, struct {
            fn older(_: void, lhs: Pick, rhs: Pick) bool {
                return lhs.mtime < rhs.mtime;
            }
        }.older);
        var total = bytes_after;
        var evict: std.ArrayList(u32) = .empty;
        for (picks.items) |pick| {
            if (total <= cap) break;
            try evict.append(a, pick.id);
            total -= pick.bytes;
        }
        if (evict.items.len > 0 and (dry_run or try state.retire(evict.items))) {
            report.evicted = evict.items.len;
            report.bytes_after = total;
        }
        if (report.bytes_after > cap) report.unmet = true;
    }
    if (!dry_run) try logCollection(a, io, root, report, dropped, now);
    return report;
}

/// Append one line describing the collection to `collect.log`. Best effort.
fn logCollection(a: std.mem.Allocator, io: std.Io, root: []const u8, report: Report, dropped: u64, now: i96) std.mem.Allocator.Error!void {
    const line = try std.fmt.allocPrint(a, "collect at={d} bytes={d}->{d} prefixes={d} leases={d} dropped_roots={d} evicted={d} unmet={}\n", .{
        @divTrunc(now, 1_000_000_000), report.bytes_before, report.bytes_after, report.prefixes, report.leases, dropped, report.evicted, report.unmet,
    });
    const log = std.Io.Dir.cwd().createFile(io, try std.fs.path.join(a, &.{ root, log_leaf }), .{ .truncate = false }) catch return;
    defer log.close(io);
    const stat = log.stat(io) catch return;
    log.writePositionalAll(io, line, stat.size) catch return;
}
