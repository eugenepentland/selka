//! Bounded retention of a work directory's regenerable caches (`.selka-cache/core`): linked programs, `--link` objects, replay records, stage packs, demand and frontend records.
//! Each is rebuilt by a miss, so the collector removes whole files, oldest first, until the tiers fit their
//! bound. It never runs while a build or check of the same directory holds the directory's lease: every such
//! command holds a shared lease for as long as its stores are open, so a sweep that gets the lease exclusively
//! finds no open store and no in-flight publication, and it removes no stage pack an open store could list.
const std = @import("std");
const language = @import("selka");
const retention = language.native_cache_retention;
const work_lease = language.native_cache_work;
const markers = language.work_markers;
const stage_pack = @import("stage_pack.zig");
const stage_roots = @import("stage_roots.zig");
const stage_store = @import("stage_store.zig");
const engine_retention = @import("engine/retention.zig");
const engine_kinds = @import("engine/kinds.zig");

/// Failures of holding or sweeping a work directory; cache I/O failures are misses, not errors.
pub const Error = std.mem.Allocator.Error || error{WriteFailed};

/// The regenerable tiers of a work directory, relative to it, in no particular order. `ownership` is the pack store that
/// ownership proofs lived in before they moved to the engine's store (`engine-v1`); builds remove what an older compiler left.
pub const tiers = [_][]const u8{ "programs-v2", "programs-v1", "foreign-v1", "replay-v1", "stages-packed-v1", "lowering-assembly-v1", "ownership", "semantic", "frontend", "engine-v1" };

/// The environment variable of the bound in GiB (a fraction is allowed; 0 turns the collector off). Build-slot
/// admission reads the same variable for its developer caches.
pub const cap_variable = "SELKA_CACHE_TIERS_CAP_GB";

/// The bound when the variable is unset: the same 10 GiB that build-slot admission uses.
pub const default_cap_bytes: u64 = 10 * (1 << 30);

/// Seconds between automatic sweeps of one work directory, recorded in its `.retention-last` file.
pub const interval_seconds: i96 = 600;

const last_leaf = ".retention-last";
const sequence_leaf = "sequence";

/// What one sweep found and removed.
pub const Counts = struct { files: usize = 0, bytes: u64 = 0 };

/// The outcome of a sweep: `busy` when a build or check held the directory and nothing was touched.
pub const Report = struct { busy: bool = false, inventory: Counts = .{}, removed: Counts = .{} };

/// A shared hold on a work directory, kept while its stores are open. Releasing it lets a sweep run.
pub const Hold = struct {
    io: std.Io,
    lease: std.Io.File,

    /// Release the lease; a sweep that waited may now run.
    pub fn release(self: Hold) void {
        self.lease.close(self.io);
    }
};

/// Hold `work` (created when absent) for one build or check; the caller releases the hold when its stores close. A work
/// directory the compiler makes keeps itself out of git and backups (`work_markers`).
pub fn hold(a: std.mem.Allocator, io: std.Io, work: []const u8) Error!Hold {
    const fresh = markers.fresh(io, work);
    const lease = try work_lease.lease(a, io, work);
    markers.mark(a, io, work, fresh);
    return .{ .io = io, .lease = lease };
}

/// The automatic bound of `environ`: `SELKA_CACHE_TIERS_CAP_GB` as GiB, the default when unset or unreadable,
/// and null (off) for zero.
pub fn capBytes(environ: *const std.process.Environ.Map) ?u64 {
    const text = environ.get(cap_variable) orelse return default_cap_bytes;
    const gib = std.fmt.parseFloat(f64, text) catch return default_cap_bytes;
    if (!(gib >= 0)) return default_cap_bytes;
    if (gib == 0) return null;
    return @intFromFloat(@min(gib * 1073741824.0, 1.0e18));
}

/// The automatic collector, run by a build or check after its hold is released: at most once per
/// `interval_seconds`, only when no other command holds the directory, and only down to `capBytes`.
/// Failures are ignored; a collection that does not happen costs only disk.
pub fn automatic(a: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io, work: []const u8, environ: *const std.process.Environ.Map) void {
    const bound = capBytes(environ) orelse return;
    maintainStages(gpa, io, work);
    _ = removeLegacyOwnership(a, io, work);
    retireEngineWhenDue(a, io, work);
    const now = retention.retentionNanoseconds(io);
    if (lastSweep(a, io, work)) |last| {
        const elapsed = now - last;
        if (elapsed >= 0 and elapsed < interval_seconds * std.time.ns_per_s) return;
    }
    const report = sweep(a, io, work, bound) catch return;
    if (report.busy) return;
    recordSweep(a, io, work, now);
}

/// Retire the engine store's partitions and objects that no build keeps, when there are any (`engine/retention.zig`):
/// one directory listing and one small file decide, so a command pays nothing more on the hot path. Failures are
/// ignored.
pub fn retireEngineWhenDue(a: std.mem.Allocator, io: std.Io, work: []const u8) void {
    const now = retention.retentionNanoseconds(io);
    const stamp: i64 = @intCast(@min(now, std.math.maxInt(i64)));
    if (!engine_retention.due(a, io, work, stamp)) return;
    const current = engine_kinds.current(a) catch return;
    _ = engine_retention.retire(a, io, work, current, stamp) catch return;
}

const stages_leaf = "stages-packed-v1";
const compact_header = "selka-stage-compact-v2";
const compact_state_leaf = ".stage-compact-last";
const compact_log_leaf = ".stage-compact.log";
/// A store with this many packs is compacted whatever its dead fraction: every process indexes each pack it opens.
const pack_limit = 24;
/// A check is due again once the store has gained this many packs since the last one.
const pack_growth = 8;
/// A check is due again once this many root manifests have accumulated since the last one: a check prunes the manifests no root names.
const manifest_growth = 16;
/// The compaction log keeps about this many bytes of its newest lines.
const log_bytes = 16 << 10;

/// The most pack bytes one build's compaction rewrites. Rewriting every live record of the store took 3 to 14 s of the edit build at 400k (1 to 4 s at 99k), once
/// every second build of a type-edit loop, because each such build adds a dozen packs; the smallest packs hold the newest records, and merging them costs the bytes they hold.
pub const compaction_budget: u64 = 96 << 20;

/// A store whose packs hold more than this multiple of its live bytes is compacted whole whatever it costs: the budgeted compactions leave dead records in the
/// packs they do not take, and this bounds the disk they use.
const dead_multiple = 3;

/// The packs a pass leaves a store with, at most, when it only has to bring it under the limit: `pack_limit` less the growth that makes the next check due,
/// so the next check is `pack_growth` builds away.
const tiered_target: u64 = pack_limit - pack_growth;

/// The ids of the packs a budgeted compaction takes: the smallest packs first, each while the bytes taken stay within `budget`, and at least two (a lone pack is not merged
/// with anything). The newest records are in the smallest packs, and the packs an earlier compaction wrote are bands of up to `stage_pack.default_band_bytes`.
/// With a `target` the selection stops as soon as the store would be left with that many packs (the taken ones become one band): a build adds one small pack, so a
/// store of 128 MB of live records at the limit took the budget's 96 MB of packs and rewrote them (0.7-1.2 s) to remove a handful of 0.5 MB ones. A `target` of 0
/// is the plain smallest-first rule, which reaches the dead records of large packs.
fn smallestFirst(a: std.mem.Allocator, stats: []const stage_pack.PackStat, budget: u64, target: u64) std.mem.Allocator.Error![]const u32 {
    const order = try a.dupe(stage_pack.PackStat, stats);
    std.mem.sort(stage_pack.PackStat, order, {}, struct {
        fn smaller(_: void, left: stage_pack.PackStat, right: stage_pack.PackStat) bool {
            return if (left.bytes != right.bytes) left.bytes < right.bytes else left.id < right.id;
        }
    }.smaller);
    var taken: std.ArrayList(u32) = .empty;
    var bytes: u64 = 0;
    for (order) |pack| {
        if (taken.items.len >= 2 and bytes + pack.bytes > budget) break;
        // The packs left after this pass: those not taken, and the one band the taken ones become.
        if (target != 0 and taken.items.len >= 2 and order.len - taken.items.len + 1 <= target) break;
        try taken.append(a, pack.id);
        bytes += pack.bytes;
    }
    return if (taken.items.len >= 2) taken.items else &.{};
}

/// Compact part of the store: the smallest packs within `compaction_budget`, whose live records move into fresh bands and whose sources are removed (`State.compactIn`).
/// The wait of a build is therefore bounded by the budget, however large the store is. A store far past its live bytes (`dead_multiple`) is compacted whole. Liveness is the
/// roots' (`ranks`) in both cases, so a record a kept manifest or head names is kept; the packs outside the selection are not touched.
pub fn compactBudgeted(a: std.mem.Allocator, state: *stage_pack.State, ranks: *const stage_pack.Ranks, measured: stage_pack.Measure, budget: u64) std.mem.Allocator.Error!?stage_pack.Compaction {
    if (measured.pack_bytes > dead_multiple * measured.live_bytes + budget) return state.compactLive(ranks, stage_pack.default_band_bytes);
    // A store over its pack limit with few dead records is there only because every build adds a pack: merge just enough of the small ones. One with dead records
    // in its large packs (or under the limit, compacted for them) takes the plain rule, which reaches them.
    const only_packs = measured.packs >= pack_limit and measured.pack_bytes <= measured.live_bytes + measured.live_bytes / 4;
    const target: u64 = if (only_packs) tiered_target else 0;
    const chosen = try smallestFirst(a, try state.packStats(a, ranks), budget, target);
    if (chosen.len == 0) return null;
    return state.compactIn(ranks, stage_pack.default_band_bytes, chosen);
}

/// The packs of a stage store, their bytes, and (in the record of the last check) the live bytes that check measured.
const Totals = struct { count: u64 = 0, bytes: u64 = 0, live: u64 = 0, manifests: u64 = 0 };

/// Compact the stage store of `work` to its live records (`stage_pack.State.compactLive`) when it holds more than a quarter
/// of its live bytes again, or `pack_limit` packs. The live records are those the roots name (`stage_roots.zig`). A check is
/// due only once the store has grown by a quarter of its live bytes, or `pack_growth` packs, since the last one, so a command
/// usually reads one directory listing. Compaction takes the exclusive lease: a busy directory is checked by a later command.
/// Its decision is logged to `.stage-compact.log`. Failures are ignored, and cost only disk.
pub fn maintainStages(gpa: std.mem.Allocator, io: std.Io, work: []const u8) void {
    var small = std.heap.ArenaAllocator.init(gpa);
    defer small.deinit();
    const a = small.allocator();
    const root = std.fs.path.join(a, &.{ work, stages_leaf }) catch return;
    var now = packTotals(io, root);
    if (now.count == 0) return;
    now.manifests = stage_roots.manifestCount(io, a, root);
    if (lastCheck(a, io, work)) |base| if (!due(base, now)) return;
    const guard = (retention.Context.init(a, io, work, .compiler).tryExclusive() catch return) orelse return;
    defer guard.close(io);
    // The store takes the general-purpose allocator, so each band's and each block's memory returns to the OS when it is
    // released; the roots and the replay records are read in an arena that ends with the check.
    var full_check = std.heap.ArenaAllocator.init(gpa);
    defer full_check.deinit();
    const f = full_check.allocator();
    var storage = stage_store.Store.init(gpa, io, work) catch return;
    defer storage.deinit();
    const ranks = stage_roots.rank(f, io, work, root) catch return;
    const measured = storage.storage.measure(&ranks) catch return;
    if (reasonFor(measured)) |reason| {
        const started = retention.retentionNanoseconds(io);
        if (compactBudgeted(f, storage.storage, &ranks, measured, compaction_budget) catch return) |result| logCompaction(f, io, work, reason, result, retention.retentionNanoseconds(io) - started);
    }
    const after = packTotals(io, root);
    writeLastCheck(a, io, work, .{ .count = after.count, .bytes = after.bytes, .live = measured.live_bytes, .manifests = stage_roots.manifestCount(io, a, root) });
}

/// The directory the ownership proofs lived in before they moved to the engine's store: `ownership/<compiler identity>/...`, and
/// the flat `ownership/stages-packed-v1` before that.
const legacy_ownership_leaf = "ownership";

/// Remove the pack store older compilers kept ownership proofs in, when the work directory has one. Runs under the work
/// directory's exclusive lease, which no session holds while it has anything open (every build and check holds the lease for that
/// time), so a directory a build is using is left alone. Failures are ignored; what stays costs only disk. True when it removed.
pub fn removeLegacyOwnership(a: std.mem.Allocator, io: std.Io, work: []const u8) bool {
    const root = std.fs.path.join(a, &.{ work, legacy_ownership_leaf }) catch return false;
    std.Io.Dir.cwd().access(io, root, .{}) catch return false;
    const guard = (retention.Context.init(a, io, work, .compiler).tryExclusive() catch return false) orelse return false;
    defer guard.close(io);
    var parent = std.Io.Dir.cwd().openDir(io, work, .{}) catch return false;
    defer parent.close(io);
    parent.deleteTree(io, legacy_ownership_leaf) catch return false;
    return true;
}

/// The packs `root` lists and their bytes, from the directory listing alone.
fn packTotals(io: std.Io, root: []const u8) Totals {
    var totals: Totals = .{};
    var dir = std.Io.Dir.cwd().openDir(io, root, .{ .iterate = true }) catch return totals;
    defer dir.close(io);
    var entries = dir.iterate();
    while (entries.next(io) catch return totals) |entry| {
        if (entry.kind != .file or !std.mem.endsWith(u8, entry.name, ".pack")) continue;
        const status = dir.statFile(io, entry.name, .{ .follow_symlinks = false }) catch continue;
        totals.count += 1;
        totals.bytes += status.size;
    }
    return totals;
}

/// Whether the store has grown enough since the last check to check again.
fn due(base: Totals, now: Totals) bool {
    return now.bytes > base.bytes + base.live / 4 or now.count >= base.count + pack_growth or now.manifests >= base.manifests + manifest_growth;
}

/// Why a store with these measures is compacted, or null: its dead bytes exceed a quarter of its live bytes, or it has
/// `pack_limit` packs.
fn reasonFor(measured: stage_pack.Measure) ?[]const u8 {
    if (measured.packs >= pack_limit) return "packs";
    if (measured.pack_bytes > measured.live_bytes + measured.live_bytes / 4) return "dead";
    return null;
}

/// The totals the last check recorded, or null when none (or a damaged record) exists.
fn lastCheck(a: std.mem.Allocator, io: std.Io, work: []const u8) ?Totals {
    const path = std.fs.path.join(a, &.{ work, compact_state_leaf }) catch return null;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(256)) catch return null;
    var words = std.mem.tokenizeAny(u8, bytes, " \n");
    if (!std.mem.eql(u8, words.next() orelse return null, compact_header)) return null;
    const total = std.fmt.parseInt(u64, words.next() orelse return null, 10) catch return null;
    const count = std.fmt.parseInt(u64, words.next() orelse return null, 10) catch return null;
    const live = std.fmt.parseInt(u64, words.next() orelse return null, 10) catch return null;
    const manifests = std.fmt.parseInt(u64, words.next() orelse return null, 10) catch return null;
    return .{ .count = count, .bytes = total, .live = live, .manifests = manifests };
}

fn writeLastCheck(a: std.mem.Allocator, io: std.Io, work: []const u8, totals: Totals) void {
    const path = std.fs.path.join(a, &.{ work, compact_state_leaf }) catch return;
    const text = std.fmt.allocPrint(a, "{s} {d} {d} {d} {d}\n", .{ compact_header, totals.bytes, totals.count, totals.live, totals.manifests }) catch return;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text }) catch return;
}

/// Append one line to the compaction log: why the store was compacted, its packs and bytes before and after, its live
/// bytes, and the bands the rewrite took. The log keeps about `log_bytes` of its newest text.
fn logCompaction(a: std.mem.Allocator, io: std.Io, work: []const u8, reason: []const u8, result: stage_pack.Compaction, elapsed: i96) void {
    const path = std.fs.path.join(a, &.{ work, compact_log_leaf }) catch return;
    var previous: []const u8 = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(1 << 20)) catch &.{};
    if (previous.len > log_bytes) previous = previous[previous.len - log_bytes ..];
    const line = std.fmt.allocPrint(a, "{d} reason={s} packs {d}->{d} pack_bytes {d}->{d} live_bytes {d} bands {d} elapsed_ms {d}\n", .{
        retention.retentionNanoseconds(io),
        reason,
        result.before.packs,
        result.after.packs,
        result.before.pack_bytes,
        result.after.pack_bytes,
        result.before.live_bytes,
        result.passes,
        @divTrunc(elapsed, std.time.ns_per_ms),
    }) catch return;
    const text = std.mem.concat(a, u8, &.{ previous, line }) catch return;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text }) catch return;
}

/// Remove the oldest files of the regenerable tiers of `work` until they total at most `bound` bytes. Busy
/// (nothing removed) while any build or check holds the directory. Directories that do not exist are empty.
pub fn sweep(a: std.mem.Allocator, io: std.Io, work: []const u8, bound: u64) Error!Report {
    const context = retention.Context.init(a, io, work, .compiler);
    const guard = (context.tryExclusive() catch return error.WriteFailed) orelse return .{ .busy = true };
    defer guard.close(io);
    var found: std.ArrayList(Entry) = .empty;
    for (tiers) |tier| try collect(a, io, try std.fs.path.join(a, &.{ work, tier }), &found);
    std.mem.sort(Entry, found.items, {}, older);
    var report: Report = .{};
    for (found.items) |entry| {
        report.inventory.files += 1;
        report.inventory.bytes += entry.size;
    }
    var total = report.inventory.bytes;
    for (found.items) |entry| {
        if (total <= bound) break;
        std.Io.Dir.cwd().deleteFile(io, entry.path) catch continue;
        total -= entry.size;
        report.removed.files += 1;
        report.removed.bytes += entry.size;
    }
    return report;
}

/// One regular file of a tier: its path, size and modification time, and whether it is an abandoned partial.
const Entry = struct { path: []const u8, size: u64, mtime: i96, partial: bool };

/// Abandoned partials go first (no command can be publishing one while the lease is exclusive), then the oldest.
fn older(_: void, left: Entry, right: Entry) bool {
    if (left.partial != right.partial) return left.partial;
    if (left.mtime != right.mtime) return left.mtime < right.mtime;
    return std.mem.lessThan(u8, left.path, right.path);
}

/// Append every regular file under `directory`, recursively. Lock files, the `sequence` counter, claim
/// directories (`work`) and dot files are the stores' own and stay; so do symbolic links and special files.
fn collect(a: std.mem.Allocator, io: std.Io, directory: []const u8, found: *std.ArrayList(Entry)) Error!void {
    var dir = std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true, .follow_symlinks = false }) catch return;
    defer dir.close(io);
    var entries = dir.iterate();
    while (entries.next(io) catch return) |entry| {
        if (std.mem.startsWith(u8, entry.name, ".")) continue;
        if (entry.kind == .directory) {
            if (std.mem.eql(u8, entry.name, "work")) continue;
            try collect(a, io, try std.fs.path.join(a, &.{ directory, entry.name }), found);
            continue;
        }
        if (entry.kind != .file or std.mem.eql(u8, entry.name, sequence_leaf) or std.mem.endsWith(u8, entry.name, ".lock")) continue;
        const status = dir.statFile(io, entry.name, .{ .follow_symlinks = false }) catch continue;
        try found.append(a, .{
            .path = try std.fs.path.join(a, &.{ directory, entry.name }),
            .size = status.size,
            .mtime = status.mtime.nanoseconds,
            .partial = std.mem.endsWith(u8, entry.name, ".partial"),
        });
    }
}

fn lastSweep(a: std.mem.Allocator, io: std.Io, work: []const u8) ?i96 {
    const path = std.fs.path.join(a, &.{ work, last_leaf }) catch return null;
    const bytes = std.Io.Dir.cwd().readFileAlloc(io, path, a, .limited(64)) catch return null;
    return std.fmt.parseInt(i96, std.mem.trim(u8, bytes, " \n"), 10) catch null;
}

fn recordSweep(a: std.mem.Allocator, io: std.Io, work: []const u8, now: i96) void {
    const path = std.fs.path.join(a, &.{ work, last_leaf }) catch return;
    const text = std.fmt.allocPrint(a, "{d}\n", .{now}) catch return;
    std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = text }) catch return;
}

/// Write a `bytes`-long file at `root/parts...` (its directories made) dated `time` seconds after the epoch.
fn writeTier(io: std.Io, a: std.mem.Allocator, root: []const u8, parts: []const []const u8, bytes: usize, time: i96) !void {
    const path = try std.fs.path.join(a, &.{ root, try std.fs.path.join(a, parts) });
    if (std.fs.path.dirname(path)) |dir| try std.Io.Dir.cwd().createDirPath(io, dir);
    const data = try a.alloc(u8, bytes);
    @memset(data, 'x');
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = path, .data = data });
    try std.Io.Dir.cwd().setTimestamps(io, path, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = time * std.time.ns_per_s } } });
}

fn exists(io: std.Io, a: std.mem.Allocator, root: []const u8, tier: []const u8, name: []const u8) bool {
    const path = std.fs.path.join(a, &.{ root, tier, name }) catch return false;
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

test "a sweep removes the oldest files of every tier until the bound holds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try writeTier(io, a, root, &.{ "stages-packed-v1", "old.pack" }, 100, 10);
    try writeTier(io, a, root, &.{ "stages-packed-v1", "new.pack" }, 100, 30);
    try writeTier(io, a, root, &.{ "programs-v2", "oldest.program" }, 100, 5);
    try writeTier(io, a, root, &.{ "semantic", "middle.body" }, 100, 20);
    try writeTier(io, a, root, &.{ "ownership/stages-packed-v1", "owned.pack" }, 100, 40);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(a, &.{ root, "stages-packed-v1", "sequence" }), .data = "7" });
    const report = try sweep(a, io, root, 300);
    try std.testing.expectEqual(@as(usize, 2), report.removed.files);
    try std.testing.expect(!exists(io, a, root, "programs-v2", "oldest.program"));
    try std.testing.expect(!exists(io, a, root, "stages-packed-v1", "old.pack"));
    try std.testing.expect(exists(io, a, root, "stages-packed-v1", "new.pack"));
    try std.testing.expect(exists(io, a, root, "semantic", "middle.body"));
    try std.testing.expect(exists(io, a, root, "ownership/stages-packed-v1", "owned.pack"));
    try std.testing.expect(exists(io, a, root, "stages-packed-v1", "sequence"));
}

test "a sweep never runs while a build holds its work directory, and a removed pack costs only a miss" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const cache = try std.fs.path.join(a, &.{ root, ".selka-cache-core" });
    var store = try @import("stage_store.zig").Store.init(std.testing.allocator, io, cache);
    const key: @import("stage_store.zig").Digest = @splat(4);
    var build = try hold(a, io, cache);
    try std.testing.expect(try store.save(key, "a stage record"));
    try std.testing.expect(try store.flush());
    store.deinit();
    const busy = try sweep(a, io, cache, 0);
    try std.testing.expect(busy.busy);
    try std.testing.expectEqual(@as(usize, 0), busy.removed.files);
    build.release();
    const swept = try sweep(a, io, cache, 0);
    try std.testing.expect(!swept.busy);
    try std.testing.expect(swept.removed.files >= 1);
    var reopened = try @import("stage_store.zig").Store.init(std.testing.allocator, io, cache);
    defer reopened.deinit();
    try std.testing.expectEqual(@as(?[]u8, null), try reopened.load(a, key));
    try std.testing.expect(try reopened.save(key, "a stage record"));
    try std.testing.expect(try reopened.flush());
    try std.testing.expectEqualStrings("a stage record", (try reopened.load(a, key)).?);
}

fn readText(io: std.Io, a: std.mem.Allocator, root: []const u8, leaf: []const u8) ![]u8 {
    return std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(a, &.{ root, leaf }), a, .limited(4096));
}

/// Date both marker files of `folder` five seconds after the epoch, so that a rewrite shows.
fn dateMarkers(io: std.Io, a: std.mem.Allocator, folder: []const u8) !void {
    for ([_][]const u8{ markers.ignore_file, markers.tag_file }) |leaf| {
        try std.Io.Dir.cwd().setTimestamps(io, try std.fs.path.join(a, &.{ folder, leaf }), .{ .modify_timestamp = .{ .new = .{ .nanoseconds = 5 * std.time.ns_per_s } } });
    }
}

/// Both marker files of `folder` still carry the date `dateMarkers` gave them.
fn expectDated(io: std.Io, a: std.mem.Allocator, folder: []const u8) !void {
    for ([_][]const u8{ markers.ignore_file, markers.tag_file }) |leaf| {
        const status = try std.Io.Dir.cwd().statFile(io, try std.fs.path.join(a, &.{ folder, leaf }), .{});
        try std.testing.expectEqual(@as(i96, 5 * std.time.ns_per_s), status.mtime.nanoseconds);
    }
}

test "a hold of the default work directory leaves a .gitignore and a CACHEDIR.TAG in .selka-cache, once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const marked = try std.fs.path.join(a, &.{ root, ".selka-cache" });
    var first = try hold(a, io, try std.fs.path.join(a, &.{ marked, "core" }));
    first.release();
    try std.testing.expectEqualStrings("*\n", try readText(io, a, marked, markers.ignore_file));
    try std.testing.expectEqualStrings(markers.tag_text, try readText(io, a, marked, markers.tag_file));
    // A second hold rewrites neither file: both keep a modification time from long ago.
    try dateMarkers(io, a, marked);
    var second = try hold(a, io, try std.fs.path.join(a, &.{ marked, "core" }));
    second.release();
    try expectDated(io, a, marked);
}

test "a .gitignore that is already there is left alone, and a missing tag is still written" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const marked = try std.fs.path.join(a, &.{ root, ".selka-cache" });
    try std.Io.Dir.cwd().createDirPath(io, marked);
    try std.Io.Dir.cwd().writeFile(io, .{ .sub_path = try std.fs.path.join(a, &.{ marked, markers.ignore_file }), .data = "mine\n" });
    var build = try hold(a, io, try std.fs.path.join(a, &.{ marked, "core" }));
    build.release();
    try std.testing.expectEqualStrings("mine\n", try readText(io, a, marked, markers.ignore_file));
    try std.testing.expectEqualStrings(markers.tag_text, try readText(io, a, marked, markers.tag_file));
}

test "a --cache-dir the command creates gets the markers, and one that was already there does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const custom = try std.fs.path.join(a, &.{ root, "stores", "mine" });
    var created = try hold(a, io, custom);
    created.release();
    try std.testing.expectEqualStrings("*\n", try readText(io, a, custom, markers.ignore_file));
    try std.testing.expectEqualStrings(markers.tag_text, try readText(io, a, custom, markers.tag_file));
    // A folder that existed (here, the project's own) is never hidden from git by a build that names it.
    var sources = try hold(a, io, root);
    sources.release();
    try std.testing.expectError(error.FileNotFound, readText(io, a, root, markers.ignore_file));
    try std.testing.expectError(error.FileNotFound, readText(io, a, root, markers.tag_file));
}

test "the automatic bound reads the environment in GiB, with zero off and the default when unset" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var environment: std.process.Environ.Map = .init(arena.allocator());
    try std.testing.expectEqual(@as(?u64, default_cap_bytes), capBytes(&environment));
    try environment.put(cap_variable, "0");
    try std.testing.expectEqual(@as(?u64, null), capBytes(&environment));
    try environment.put(cap_variable, "0.5");
    try std.testing.expectEqual(@as(?u64, 1 << 29), capBytes(&environment));
    try environment.put(cap_variable, "not a number");
    try std.testing.expectEqual(@as(?u64, default_cap_bytes), capBytes(&environment));
}

test "maintenance compacts a store's dead records once the directory is free, and logs the decision" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    {
        var dead = try stage_store.Store.init(std.testing.allocator, io, work);
        defer dead.deinit();
        for (0..20) |index| try std.testing.expect(try dead.save(dead.key("maintain-test", &.{&[_]u8{@intCast(index)}}), "a dead record"));
        try std.testing.expect(try dead.flush());
    }
    {
        var live = try stage_store.Store.init(std.testing.allocator, io, work);
        defer live.deinit();
        for (20..30) |index| try std.testing.expect(try live.save(live.key("maintain-test", &.{&[_]u8{@intCast(index)}}), "a live record"));
        try std.testing.expect(try live.flush());
        stage_roots.retain(&live, a, io, "session-live", 0);
    }
    const build = try hold(a, io, work);
    maintainStages(std.testing.allocator, io, work);
    {
        var reader = try stage_store.Store.init(std.testing.allocator, io, work);
        defer reader.deinit();
        try std.testing.expect((try reader.load(a, reader.key("maintain-test", &.{&[_]u8{0}}))) != null);
    }
    build.release();
    maintainStages(std.testing.allocator, io, work);
    var reader = try stage_store.Store.init(std.testing.allocator, io, work);
    defer reader.deinit();
    try std.testing.expectEqual(@as(?[]u8, null), try reader.load(a, reader.key("maintain-test", &.{&[_]u8{0}})));
    try std.testing.expectEqualStrings("a live record", (try reader.load(a, reader.key("maintain-test", &.{&[_]u8{25}}))).?);
    const log = try std.Io.Dir.cwd().readFileAlloc(io, try std.fs.path.join(a, &.{ work, compact_log_leaf }), a, .limited(1 << 16));
    try std.testing.expect(std.mem.indexOf(u8, log, "reason=dead") != null);
}

test "the packs a budgeted compaction takes are the smallest ones within the budget, and at least two" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stats = [_]stage_pack.PackStat{
        .{ .id = 1, .mtime = 0, .bytes = 70 << 20, .live = 9 },
        .{ .id = 2, .mtime = 0, .bytes = 4 << 20, .live = 9 },
        .{ .id = 3, .mtime = 0, .bytes = 3 << 20, .live = 9 },
        .{ .id = 4, .mtime = 0, .bytes = 60 << 20, .live = 9 },
    };
    try std.testing.expectEqualSlices(u32, &.{ 3, 2 }, try smallestFirst(a, &stats, 10 << 20, 0));
    try std.testing.expectEqualSlices(u32, &.{ 3, 2, 4 }, try smallestFirst(a, &stats, 80 << 20, 0));
    // Two packs are taken even when the smallest pair is over the budget; one pack alone is not merged with anything.
    try std.testing.expectEqualSlices(u32, &.{ 3, 2 }, try smallestFirst(a, &stats, 1, 0));
    try std.testing.expectEqual(@as(usize, 0), (try smallestFirst(a, stats[0..1], 1 << 30, 0)).len);
    // With a target of 3 packs left, the 60 MB pack stays out: taking the two smallest already leaves 3 of 4.
    try std.testing.expectEqualSlices(u32, &.{ 3, 2 }, try smallestFirst(a, &stats, 80 << 20, 3));
}

/// `small` packs of 0.5 MB (ids from 0) and two bands of 64 and 32 MB (ids 100 and 101): a store at the pack limit when `small` is 22.
fn smallPacksAndBands(a: std.mem.Allocator, small: usize) std.mem.Allocator.Error!std.ArrayList(stage_pack.PackStat) {
    var stats: std.ArrayList(stage_pack.PackStat) = .empty;
    for (0..small) |id| try stats.append(a, .{ .id = @intCast(id), .mtime = 0, .bytes = 512 << 10, .live = 9 });
    try stats.append(a, .{ .id = 100, .mtime = 0, .bytes = 64 << 20, .live = 9 });
    try stats.append(a, .{ .id = 101, .mtime = 0, .bytes = 32 << 20, .live = 9 });
    return stats;
}

test "a targeted selection merges just the builds' small packs, and the plain rule still takes what the budget allows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stats = try smallPacksAndBands(a, 22);
    // 24 packs at the limit: nine merged into one leave 16, the next check's distance from the limit, and only 0.5 MB packs are rewritten.
    const tiered = try smallestFirst(a, stats.items, 96 << 20, tiered_target);
    try std.testing.expectEqual(@as(usize, 9), tiered.len);
    for (tiered) |id| try std.testing.expect(id < 100);
    // The plain rule takes the small ones and a band as well, as the budget allows it.
    try std.testing.expectEqual(@as(usize, 23), (try smallestFirst(a, stats.items, 96 << 20, 0)).len);
    // The budget still bounds a targeted pass: two packs at least, then the bytes.
    try std.testing.expectEqual(@as(usize, 2), (try smallestFirst(a, stats.items, 1, tiered_target)).len);
}

/// Write the records of the budget test: a big live record in a pack of its own, then six builds, each a pack of one live and one dead record. Returns the live keys
/// (the big one first) and the dead ones.
fn writeBudgetRounds(a: std.mem.Allocator, writer: *stage_store.Store) !struct { live: []const stage_store.Digest, dead: []const stage_store.Digest } {
    var live: std.ArrayList(stage_store.Digest) = .empty;
    var dead: std.ArrayList(stage_store.Digest) = .empty;
    const big = writer.key("maintain-test", &.{"big"});
    try std.testing.expect(try writer.save(big, try a.alloc(u8, 300 << 10)));
    try std.testing.expect(try writer.flush());
    try live.append(a, big);
    for (0..6) |round| {
        const live_key = writer.key("maintain-test", &.{ "live", &[_]u8{@intCast(round)} });
        const dead_key = writer.key("maintain-test", &.{ "dead", &[_]u8{@intCast(round)} });
        try std.testing.expect(try writer.save(live_key, "a live record"));
        try std.testing.expect(try writer.save(dead_key, "a dead record"));
        try std.testing.expect(try writer.flush());
        try live.append(a, live_key);
        try dead.append(a, dead_key);
    }
    return .{ .live = live.items, .dead = dead.items };
}

/// The ranks that name `keys`, in order.
fn rankedKeys(a: std.mem.Allocator, keys: []const stage_store.Digest) std.mem.Allocator.Error!stage_pack.Ranks {
    var ranks: stage_pack.Ranks = .empty;
    for (keys, 0..) |key, rank| try ranks.put(a, stage_roots.rankKey(key), rank);
    return ranks;
}

/// How many of `keys` the store `reader` holds.
fn heldCount(a: std.mem.Allocator, reader: *stage_store.Store, keys: []const stage_store.Digest) std.mem.Allocator.Error!usize {
    var held: usize = 0;
    for (keys) |key| held += @intFromBool((try reader.load(a, key)) != null);
    return held;
}

test "a budgeted compaction merges the small packs, keeps every live record, drops the dead ones and leaves a pack past the budget as it was" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    const packed_root = try std.fs.path.join(a, &.{ work, stages_leaf });
    var writer = try stage_store.Store.init(std.testing.allocator, io, work);
    defer writer.deinit();
    const written = try writeBudgetRounds(a, &writer);
    try std.testing.expectEqual(@as(usize, 7), written.live.len);
    const ranks = try rankedKeys(a, written.live);
    const before = packTotals(io, packed_root);
    try std.testing.expectEqual(@as(u64, 7), before.count);
    const measured = try writer.storage.measure(&ranks);
    const result = (try compactBudgeted(a, writer.storage, &ranks, measured, 100 << 10)) orelse return error.TestUnexpectedResult;
    // The six small packs became one; the big pack was not rewritten, so the store holds two packs.
    try std.testing.expectEqual(@as(u64, 7), result.before.packs);
    try std.testing.expectEqual(@as(u64, 2), result.after.packs);
    try std.testing.expectEqual(@as(u64, 2), packTotals(io, packed_root).count);
    try std.testing.expect(packTotals(io, packed_root).bytes < before.bytes);
    var reader = try stage_store.Store.init(std.testing.allocator, io, work);
    defer reader.deinit();
    try std.testing.expectEqual(written.live.len, try heldCount(a, &reader, written.live));
    try std.testing.expectEqual(@as(usize, 0), try heldCount(a, &reader, written.dead));
}

/// Run `rounds` edit builds against the stage store of `work`, each writing and maintaining it; returns the most packs it held
/// after a maintenance pass. Each build writes the same six keys with its own payloads, so every round supersedes the last.
fn editRounds(gpa: std.mem.Allocator, a: std.mem.Allocator, io: std.Io, work: []const u8, packed_root: []const u8, rounds: usize) !u64 {
    var most: u64 = 0;
    var previous: u64 = 0;
    for (0..rounds) |round| {
        var writer = try stage_store.Store.init(gpa, io, work);
        defer writer.deinit();
        for (0..6) |slot| {
            var payload: [32]u8 = undefined;
            const text = try std.fmt.bufPrint(&payload, "round {d} slot {d}", .{ round, slot });
            try std.testing.expect(try writer.save(writer.key("bounded-test", &.{&[_]u8{@intCast(slot)}}), text));
        }
        try std.testing.expect(try writer.flush());
        // Without the in-flush merge a build's flush adds exactly its own pack.
        try std.testing.expectEqual(previous + 1, packTotals(io, packed_root).count);
        stage_roots.retain(&writer, a, io, "session-live", 0);
        maintainStages(gpa, io, work);
        previous = packTotals(io, packed_root).count;
        most = @max(most, previous);
    }
    return most;
}

test "without the in-flush merge, repeated edit builds keep a bounded store, because maintenance compacts it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(io, ".", a);
    const packed_root = try std.fs.path.join(a, &.{ work, stages_leaf });
    const most = try editRounds(std.testing.allocator, a, io, work, packed_root, 40);
    // Maintenance bounds the packs: a directory that grew by one pack per build never reaches the pack limit.
    try std.testing.expect(most < pack_limit);
    var reader = try stage_store.Store.init(std.testing.allocator, io, work);
    defer reader.deinit();
    const newest = (try reader.load(a, reader.key("bounded-test", &.{&[_]u8{0}}))) orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("round 39 slot 0", newest);
}

/// Make an old ownership store under `root`: two identity directories with a pack each, and the flat layout beside them.
fn makeLegacy(io: std.Io, a: std.mem.Allocator, root: []const u8) !void {
    try writeTier(io, a, root, &.{ "ownership", "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "stages-packed-v1", "p.pack" }, 10, 1);
    try writeTier(io, a, root, &.{ "ownership", "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "stages-packed-v1", "p.pack" }, 10, 1);
    try writeTier(io, a, root, &.{ "ownership", "stages-packed-v1", "old.pack" }, 10, 1);
}

/// Whether `path` exists.
fn present(io: std.Io, path: []const u8) bool {
    _ = std.Io.Dir.cwd().statFile(io, path, .{}) catch return false;
    return true;
}

test "the pack store older compilers kept ownership proofs in is removed, and nothing else is" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try makeLegacy(io, a, root);
    try writeTier(io, a, root, &.{ "engine-v1", "records", "kept.rec" }, 10, 1);
    try std.testing.expect(removeLegacyOwnership(a, io, root));
    try std.testing.expect(!present(io, try std.fs.path.join(a, &.{ root, "ownership" })));
    try std.testing.expect(present(io, try std.fs.path.join(a, &.{ root, "engine-v1", "records", "kept.rec" })));
    try std.testing.expect(!removeLegacyOwnership(a, io, root));
}

test "the old ownership store is left alone while a build holds the work directory, and a build's collection removes it after" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try makeLegacy(io, a, root);
    var build = try hold(a, io, root);
    try std.testing.expect(!removeLegacyOwnership(a, io, root));
    try std.testing.expect(present(io, try std.fs.path.join(a, &.{ root, "ownership" })));
    build.release();
    var environment: std.process.Environ.Map = .init(a);
    automatic(a, std.testing.allocator, io, root, &environment);
    try std.testing.expect(!present(io, try std.fs.path.join(a, &.{ root, "ownership" })));
}

test "a build's automatic collection retires the engine partitions no build keeps" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const store = @import("engine/store.zig").Store.init(io, try std.fs.path.join(a, &.{ root, "engine-v1" }));
    for (1..5) |identity| {
        const directory = try store.partition(a, "engine-probe", @splat(@intCast(identity)));
        try std.Io.Dir.cwd().createDirPath(io, directory);
        store.touch(a, directory, @intCast(identity * 100));
    }
    var environment: std.process.Environ.Map = .init(a);
    automatic(a, std.testing.allocator, io, root, &environment);
    try std.testing.expect(present(io, try store.partition(a, "engine-probe", @splat(4))));
    try std.testing.expect(present(io, try store.partition(a, "engine-probe", @splat(3))));
    try std.testing.expect(!present(io, try store.partition(a, "engine-probe", @splat(2))));
    try std.testing.expect(!present(io, try store.partition(a, "engine-probe", @splat(1))));
}

test "the automatic sweep runs at most once per interval" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    var environment: std.process.Environ.Map = .init(a);
    try environment.put(cap_variable, "0.000001");
    try writeTier(io, a, root, &.{ "programs-v2", "first.bin" }, 5000, 1);
    automatic(a, std.testing.allocator, io, root, &environment);
    try std.testing.expect(!exists(io, a, root, "programs-v2", "first.bin"));
    // The record of that sweep is a number and a newline: it must read back, or every command sweeps (4,800 system calls at 99k).
    try std.testing.expect(lastSweep(a, io, root) != null);
    try writeTier(io, a, root, &.{ "programs-v2", "second.bin" }, 5000, 1);
    automatic(a, std.testing.allocator, io, root, &environment);
    try std.testing.expect(exists(io, a, root, "programs-v2", "second.bin"));
}
