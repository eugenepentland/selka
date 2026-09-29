//! Per-function QBE unit reuse (`QBE-FRAGMENT-REUSE-1`): a project emitted
//! through a fragment store after an edit must be byte-for-byte the manifest a
//! fresh emission of the edited project produces, while every unit whose
//! emission inputs did not change is answered from the store.
const std = @import("std");
const language = @import("compiler.zig");
const fragments = @import("qbe_fragments.zig");
const units = @import("qbe_build_units.zig");
const t = std.testing;
/// The manifest member listing every unit.
const functions_member = "functions";
/// The modules of one version of the test project; `other` is imported only
/// by the three-module stand-in project.
const Files = struct { main: []const u8, helper: []const u8, other: []const u8 = "" };

fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const files: *const Files = @ptrCast(@alignCast(context.?));
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, files.main);
    if (std.mem.eql(u8, path, "helper.my")) return allocator.dupe(u8, files.helper);
    if (std.mem.eql(u8, path, "other.my") and files.other.len != 0) return allocator.dupe(u8, files.other);
    return error.NotFound;
}

const main_source =
    \\module main
    \\import helper
    \\
    \\
    \\def main(out: Stream) -> int:
    \\    p = helper.Pair(left=1, right=2)
    \\    xs = helper.scale([1, 2, 3], helper.total(p))
    \\    out.print(helper.first(xs))
    \\    out.print(str(p.left))
    \\    out.print(helper.describe(xs))
    \\    return 0
    \\
;

const helper_source =
    \\module helper
    \\
    \\
    \\public record Pair:
    \\    left: int
    \\    right: int
    \\
    \\
    \\public def total(p: Pair) -> int:
    \\    return p.left + p.right
    \\
    \\
    \\public def scale(xs: list[int], k: int) -> list[int]:
    \\    out: list[int] = []
    \\    for x in xs:
    \\        out.append(x * k)
    \\    return out
    \\
    \\
    \\public def first(xs: list[int]) -> int:
    \\    return xs[0]
    \\
    \\
    \\# Converting a list to text needs its renderer, which the build finds
    \\# through this unit's operand stacks even when the unit itself is reused.
    \\public def describe(xs: list[int]) -> str:
    \\    return f"{xs}"
    \\
;

/// The project before any edit.
const original: Files = .{ .main = main_source, .helper = helper_source };

/// A body edit in one function.
const body_edit: Files = .{ .main = main_source, .helper = replaced(helper_source, "    return p.left + p.right\n", "    return p.left + p.right + 7\n") };

/// A new function ahead of every other declaration, so every later function
/// id and every source offset in the module shifts.
const interface_edit: Files = .{ .main = main_source, .helper = replaced(helper_source, "module helper\n", "module helper\n\n\npublic def zero() -> int:\n    return 0\n") };

/// A signature edit: `first` takes the position to read, and its caller passes it.
const signature_edit: Files = .{
    .main = replaced(main_source, "helper.first(xs)", "helper.first(xs, 1)"),
    .helper = replaced(helper_source, "public def first(xs: list[int]) -> int:\n    return xs[0]\n", "public def first(xs: list[int], at: int) -> int:\n    return xs[at]\n"),
};

/// A record schema edit: `Pair` gains a field every constructor must name.
const schema_edit: Files = .{
    .main = replaced(main_source, "helper.Pair(left=1, right=2)", "helper.Pair(left=1, middle=5, right=2)"),
    .helper = replaced(helper_source, "    left: int\n    right: int\n", "    left: int\n    middle: int\n    right: int\n"),
};

fn replaced(comptime text: []const u8, comptime needle: []const u8, comptime replacement: []const u8) []const u8 {
    const at = std.mem.indexOf(u8, text, needle) orelse @compileError("missing edit site");
    return text[0..at] ++ replacement ++ text[at + needle.len ..];
}

/// One emission of `files`, through `reuse` when it is non-null.
fn emit(allocator: std.mem.Allocator, files: *const Files, reuse: ?fragments.Reuse) ![]u8 {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = @constCast(files), .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.reuse = reuse;
    return compilation.emitQbe(allocator);
}

/// A fragment store rooted at `root`, reopened from disk as a new process would.
const Opened = struct {
    arena: std.heap.ArenaAllocator,
    store: fragments.Store,
    fn init(self: *Opened, root: []const u8) !void {
        self.arena = .init(t.allocator);
        self.store = try fragments.Store.open(self.arena.allocator(), t.io, root, "test-compiler", "main.my");
    }
    fn deinit(self: *Opened) void {
        self.store.deinit();
        self.arena.deinit();
    }
};

/// Emit `files` through a store reopened at `root` and compare it with a fresh
/// emission; returns the store's reuse counters for that emission.
fn expectReusedEqualsFresh(root: []const u8, files: *const Files) !fragments.Statistics {
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    const reused = try emit(t.allocator, files, .{ .store = &opened.store });
    defer t.allocator.free(reused);
    const fresh = try emit(t.allocator, files, null);
    defer t.allocator.free(fresh);
    try t.expectEqualStrings(fresh, reused);
    return opened.store.statistics;
}

// spec: QBE-FRAGMENT-REUSE-1
test "an edited project reuses every unchanged unit and emits exactly what a fresh build emits" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    // A cold store emits every unit; an unchanged rebuild emits none.
    const cold = try expectReusedEqualsFresh(root, &original);
    try t.expectEqual(@as(usize, 0), cold.hits);
    try t.expect(cold.misses >= 4);
    const warm = try expectReusedEqualsFresh(root, &original);
    try t.expectEqual(@as(usize, 0), warm.misses);
    try t.expectEqual(cold.misses, warm.hits);
    // A body edit re-emits the edited function, not its neighbours.
    const body = try expectReusedEqualsFresh(root, &body_edit);
    try t.expect(body.misses >= 1 and body.misses < cold.misses);
    try t.expect(body.hits >= 3);
    // Shifting every id and offset in a module leaves the old units reusable.
    const shifted = try expectReusedEqualsFresh(root, &interface_edit);
    try t.expect(shifted.hits >= 3);
    // A changed signature and a changed record schema reach their users.
    _ = try expectReusedEqualsFresh(root, &signature_edit);
    _ = try expectReusedEqualsFresh(root, &schema_edit);
    // And the original project still comes back unchanged.
    const back = try expectReusedEqualsFresh(root, &original);
    try t.expectEqual(@as(usize, 0), back.misses);
}

/// Both units spell the same positions and assertion messages, pc by pc.
fn expectSamePositions(spelled: std.json.Value, compact: std.json.Value) !void {
    var expected: units.Positions = .init(spelled);
    var actual: units.Positions = .init(compact);
    try t.expectEqual(expected.count, actual.count);
    try t.expect(actual.count > 0);
    for (0..actual.count) |pc| {
        const want = expected.next().?;
        const got = actual.next().?;
        try t.expectEqualStrings(want.path, got.path);
        try t.expectEqual(want.line, got.line);
        try t.expectEqual(want.column, got.column);
        try t.expectEqualStrings(expected.message(pc), actual.message(pc));
    }
    try t.expect(actual.next() == null);
}

/// The one unit of `manifest` named `name`, parsed, or null when absent.
fn unitNamed(allocator: std.mem.Allocator, manifest: []const u8, name: []const u8) !?std.json.Value {
    const document = try std.json.parseFromSliceLeaky(std.json.Value, allocator, manifest, .{});
    for (document.object.get(functions_member).?.array.items) |unit| {
        if (std.mem.eql(u8, unit.object.get("name").?.string, name)) return unit;
    }
    return null;
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "a lean manifest names each unit's stored text by digest instead of carrying it" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    const lean = try emit(a, &original, .{ .store = &opened.store, .lean = true });
    const fresh = try emit(a, &original, null);
    const stored = (try unitNamed(a, lean, "helper::total")).?;
    const inline_unit = (try unitNamed(a, fresh, "helper::total")).?;
    try t.expect(stored.object.get("il") == null);
    const store = (try std.json.parseFromSliceLeaky(std.json.Value, a, lean, .{})).object.get("store").?.string;
    const text = try storedText(a, store, stored.object.get("il_digest").?.string);
    try t.expectEqualStrings(inline_unit.object.get("il").?.string, text);
    // Everything but the unit texts is the fresh manifest's.
    try t.expectEqualStrings(inline_unit.object.get("symbol").?.string, stored.object.get("symbol").?.string);
    // EMIT-META-1 (spec-case): the lean unit names its metadata record, which
    // spells the same positions compactly (BUILD-POSITIONS-1) and the same name
    // and inline frames.
    try t.expect(stored.object.get("locations") == null and stored.object.get("positions") == null);
    const record = try std.json.parseFromSliceLeaky(std.json.Value, a, try storedText(a, store, stored.object.get("meta_digest").?.string), .{});
    try t.expectEqualStrings("helper::total", record.object.get("name").?.string);
    try t.expectEqual(inline_unit.object.get("inlines").?.array.items.len, record.object.get("inlines").?.array.items.len);
    try expectSamePositions(inline_unit, record);
}

/// A stored text read back from `store` by its hex digest, checked against it.
fn storedText(allocator: std.mem.Allocator, store: []const u8, digest: []const u8) ![]u8 {
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, try std.fs.path.join(allocator, &.{ store, digest }), allocator, .unlimited);
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(text, &hash, .{});
    try t.expectEqualStrings(&std.fmt.bytesToHex(hash, .lower), digest);
    return text;
}

/// One lean emission of `files` through a store reopened at `root`: its
/// reuse counters and its manifest.
const LeanRun = struct { statistics: fragments.Statistics, manifest: []u8 };
fn emitLean(allocator: std.mem.Allocator, root: []const u8, files: *const Files) !LeanRun {
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    const manifest = try emit(allocator, files, .{ .store = &opened.store, .lean = true, .executable = true });
    return .{ .statistics = opened.store.statistics, .manifest = manifest };
}

/// The `meta_digest` of the unit named `name`.
fn metaDigest(allocator: std.mem.Allocator, manifest: []const u8, name: []const u8) ![]const u8 {
    return (try unitNamed(allocator, manifest, name)).?.object.get("meta_digest").?.string;
}

// spec: EMIT-META-1
test "an edit computes metadata only for units of the sources it changed" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const cold = try emitLean(a, root, &original);
    try t.expectEqual(@as(usize, 0), cold.statistics.meta.hits);
    try t.expectEqual(cold.statistics.misses, cold.statistics.meta.misses);
    // A record just computed also travels inline, so the build need not read it back.
    try t.expectEqual(cold.statistics.meta.misses, std.mem.count(u8, cold.manifest, "\"meta\":{"));
    // Nothing changed: every unit's metadata is read, none computed, none inline.
    const warm = try emitLean(a, root, &original);
    try t.expectEqual(@as(usize, 0), warm.statistics.meta.misses);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, warm.manifest, "\"meta\":{"));
    try t.expectEqualStrings(try metaDigest(a, cold.manifest, "helper::total"), try metaDigest(a, warm.manifest, "helper::total"));
    // A body edit in `helper` recomputes the metadata of helper's units only,
    // and a unit whose positions did not move keeps its digest.
    const body = try emitLean(a, root, &body_edit);
    try t.expect(body.statistics.meta.misses >= 1 and body.statistics.meta.misses <= 5);
    try t.expectEqual(body.statistics.meta.hits + body.statistics.meta.misses, cold.statistics.meta.misses);
    try t.expectEqualStrings(try metaDigest(a, cold.manifest, "main::main"), try metaDigest(a, body.manifest, "main::main"));
    try t.expectEqualStrings(try metaDigest(a, cold.manifest, "helper::first"), try metaDigest(a, body.manifest, "helper::first"));
    // An executable's lean manifest carries no library-only facts.
    try t.expect(std.mem.indexOf(u8, body.manifest, "\"test_dependencies\"") == null);
    try t.expect(std.mem.indexOf(u8, body.manifest, "\"export\"") == null);
    try t.expect(std.mem.indexOf(u8, body.manifest, "\"schema\":null") != null);
}

// spec-case: QBE-FRAGMENT-REUSE-1
test "a stored text that disappears is a miss, never a stale answer" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    const key: fragments.Digest = @splat(7);
    const answer = try opened.store.remember(key, "export function $f() {\n@start\n ret\n}\n", .{ .implementation_hash = "", .dependencies = &.{}, .cacheable = true, .pure = true, .reasons = &.{} });
    opened.store.flush();
    var again: Opened = undefined;
    try again.init(root);
    defer again.deinit();
    try t.expect((try again.store.unit(key)) != null);
    try t.expectEqualStrings("export function $f() {\n@start\n ret\n}\n", try again.store.read(answer.il));
    try std.Io.Dir.cwd().deleteFile(t.io, try again.store.path(answer.il));
    try t.expectError(error.FragmentMissing, again.store.read(answer.il));
    try t.expect((try again.store.unit(key)) == null);
}

// spec: EMIT-REPLAY-1
test "a remembered emission replays its warnings and manifest until a unit text it names is gone" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    const unit = try opened.store.remember(@splat(1), "export function $g() {\n@start\n ret\n}\n", .{ .implementation_hash = "", .dependencies = &.{}, .cacheable = true, .pure = true, .reasons = &.{} });
    const key: fragments.Ticket = .{ .slot = @splat(8), .key = @splat(9) };
    try t.expect((try fragments.Replay.load(a, t.io, .{ .root = root, .identity = "test-compiler" }, key)) == null);
    const texts = try opened.store.texts(a);
    try t.expectEqual(@as(usize, 1), texts.len);
    fragments.Replay.remember(a, t.io, .{ .root = root, .identity = "test-compiler" }, key, .{ .warnings = "warning: w\n", .manifest = "{\"functions\":[]}" }, texts);
    const replayed = (try fragments.Replay.load(a, t.io, .{ .root = root, .identity = "test-compiler" }, key)).?;
    try t.expectEqualStrings("warning: w\n", replayed.warnings);
    try t.expectEqualStrings("{\"functions\":[]}", replayed.manifest);
    // The slot keeps only its latest emission: other inputs miss.
    try t.expect((try fragments.Replay.load(a, t.io, .{ .root = root, .identity = "test-compiler" }, .{ .slot = key.slot, .key = @splat(1) })) == null);
    // Another compiler identity never sees it.
    try t.expect((try fragments.Replay.load(a, t.io, .{ .root = root, .identity = "other-compiler" }, key)) == null);
    // A named unit text that left the store voids the replay.
    try std.Io.Dir.cwd().deleteFile(t.io, try opened.store.path(unit.il));
    try t.expect((try fragments.Replay.load(a, t.io, .{ .root = root, .identity = "test-compiler" }, key)) == null);
}

// spec: MANIFEST-STREAM-1
test "remembering an emission writes its manifest to the record without copying it" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const manifest = try a.alloc(u8, 4 * 1024 * 1024);
    @memset(manifest, 'm');
    const key: fragments.Ticket = .{ .slot = @splat(3), .key = @splat(4) };
    const place: fragments.Place = .{ .root = root, .identity = "test-compiler" };
    var counting = t.FailingAllocator.init(t.allocator, .{});
    var scratch = std.heap.ArenaAllocator.init(counting.allocator());
    defer scratch.deinit();
    fragments.Replay.remember(scratch.allocator(), t.io, place, key, .{ .warnings = "warning: w\n", .manifest = manifest }, &.{});
    // The record's own buffers are a few hundred bytes, not a 4 MiB copy.
    try t.expect(counting.allocated_bytes < 64 * 1024);
    const replayed = (try fragments.Replay.load(a, t.io, place, key)).?;
    try t.expectEqualStrings("warning: w\n", replayed.warnings);
    try t.expectEqualSlices(u8, manifest, replayed.manifest);
}

/// Whether a stored text is still on disk.
fn onDisk(store: *fragments.Store, digest: fragments.Digest) !bool {
    std.Io.Dir.cwd().access(t.io, try store.path(digest), .{}) catch return false;
    return true;
}

/// A text written straight into `store`, which no pack or replay names.
fn orphan(store: *fragments.Store, text: []const u8) !fragments.Digest {
    var digest: fragments.Digest = undefined;
    std.crypto.hash.Blake3.hash(text, &digest, .{});
    try std.Io.Dir.cwd().writeFile(t.io, .{ .sub_path = try store.path(digest), .data = text });
    return digest;
}

// spec: FRAGMENT-SWEEP-1
test "a sweep removes only the texts no pack or replay names, and never while another process holds the store" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    const packed_unit = try opened.store.remember(@splat(3), "export function $p() {\n@start\n ret\n}\n", .{ .implementation_hash = "", .dependencies = &.{}, .cacheable = true, .pure = true, .reasons = &.{} });
    const meta = try opened.store.rememberMeta(@splat(4), "{\"name\":\"p\"}");
    opened.store.flush();
    // A text only a remembered emission names, and one nothing names.
    const replayed = try orphan(&opened.store, "export function $r() {\n@start\n ret\n}\n");
    fragments.Replay.remember(a, t.io, .{ .root = root, .identity = "test-compiler" }, .{ .slot = @splat(5), .key = @splat(6) }, .{ .warnings = "", .manifest = "{}" }, &.{replayed});
    const garbage = try orphan(&opened.store, "export function $g() {\n@start\n ret\n}\n");
    // Few texts written since the last sweep: no sweep, whoever holds the store.
    opened.store.sweep();
    try t.expect(try onDisk(&opened.store, garbage));
    // Past the threshold, but another process still holds the store: no sweep.
    opened.store.statistics.texts.written = 10_000;
    var other: Opened = undefined;
    try other.init(root);
    opened.store.sweep();
    try t.expect(try onDisk(&opened.store, garbage));
    try t.expectEqual(@as(usize, 0), opened.store.statistics.texts.swept);
    other.deinit();
    // Alone past the threshold: only the unnamed text goes.
    opened.store.sweep();
    try t.expectEqual(@as(usize, 1), opened.store.statistics.texts.swept);
    try t.expect(!try onDisk(&opened.store, garbage));
    try t.expect(try onDisk(&opened.store, packed_unit.il));
    try t.expect(try onDisk(&opened.store, meta));
    try t.expect(try onDisk(&opened.store, replayed));
}

/// One lean executable emission of `files` through a store reopened at
/// `root`, checked the way `build` checks it (EMIT-STANDIN-1): a function
/// whose record is current is stood in rather than lowered.
fn emitStandIn(allocator: std.mem.Allocator, root: []const u8, files: *const Files) !LeanRun {
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = @constCast(files), .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    compilation.reuse = .{ .store = &opened.store, .lean = true, .executable = true };
    var cache = language.semantic_cache.Cache.init(t.allocator, 0);
    defer cache.deinit();
    var request: language.semantic_summary.Request = .{ .facts_only = true };
    cache.context.summaries = &request;
    try compilation.checkWithCache(&cache);
    const manifest = try compilation.emitQbe(allocator);
    return .{ .statistics = opened.store.statistics, .manifest = manifest };
}

/// Both manifests hand the build the same program: every unit names the
/// same text, facts and metadata, and every program-wide member but the
/// store's own path is the same.
fn expectSameBuild(allocator: std.mem.Allocator, expected: []const u8, actual: []const u8) !void {
    const left = (try std.json.parseFromSliceLeaky(std.json.Value, allocator, expected, .{})).object;
    const right = (try std.json.parseFromSliceLeaky(std.json.Value, allocator, actual, .{})).object;
    for ([_][]const u8{ "text_format", "runtime_data", "host", "entry", "entry_parameters" }) |member| {
        try t.expectEqualStrings(try std.json.Stringify.valueAlloc(allocator, left.get(member).?, .{}), try std.json.Stringify.valueAlloc(allocator, right.get(member).?, .{}));
    }
    const want = left.get(functions_member).?.array.items;
    const got = right.get(functions_member).?.array.items;
    try t.expectEqual(want.len, got.len);
    for (want, got) |one, other| try t.expectEqualStrings(try unitShape(allocator, one), try unitShape(allocator, other));
}

/// A lean unit's name, symbol, text digest, facts and metadata digest.
fn unitShape(allocator: std.mem.Allocator, unit: std.json.Value) ![]const u8 {
    const fields = unit.object;
    // Borrowed alternates are regenerated from the complete physical proof.
    if (fields.get("il") != null) return std.json.Stringify.valueAlloc(allocator, unit, .{});
    return std.fmt.allocPrint(allocator, "{s} {s} {s} {s} {s}", .{
        fields.get("name").?.string,
        fields.get("symbol").?.string,
        fields.get("il_digest").?.string,
        fields.get("il_facts").?.string,
        fields.get("meta_digest").?.string,
    });
}

/// Emit `files` with stand-ins through `root` and in full through
/// `reference`, require the same build, and return the stand-in counters.
fn expectStandInMatches(allocator: std.mem.Allocator, root: []const u8, reference: []const u8, files: *const Files) !fragments.Standin {
    const stood = try emitStandIn(allocator, root, files);
    const full = try emitLean(allocator, reference, files);
    try expectSameBuild(allocator, full.manifest, stood.manifest);
    return stood.statistics.standin;
}

// spec: EMIT-STANDIN-1
test "an executable's emission lowers only what an edit changed and emits what a full emission emits" {
    // RC-DEFAULT-1: reads the tracing collector's lowering, not the RC default's.
    const collector_runtime = language.runtime_mode.pinCollector();
    defer language.runtime_mode.set(collector_runtime);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const root = try std.fs.path.join(a, &.{ base, "standin" });
    const reference = try std.fs.path.join(a, &.{ base, "full" });
    // A cold store lowers every function and leaves records.
    const cold = try expectStandInMatches(a, root, reference, &original);
    try t.expectEqual(@as(usize, 0), cold.reused);
    // Unchanged: only what is always lowered (the printing entry, the text
    // renderer) and what a caller may inline (`total`) is lowered again;
    // `scale` and `first` are stood in.
    const warm = try expectStandInMatches(a, root, reference, &original);
    try t.expectEqual(@as(usize, 2), warm.reused);
    try t.expectEqual(cold.lowered, warm.lowered + warm.reused);
    // Every kind of edit still emits exactly the full emission. A body edit
    // moves the positions of every function in its source, so none of
    // `helper` is stood in; the three-module test below counts what is.
    const body = try expectStandInMatches(a, root, reference, &body_edit);
    try t.expectEqual(cold.lowered, body.lowered + body.reused);
    _ = try expectStandInMatches(a, root, reference, &interface_edit);
    _ = try expectStandInMatches(a, root, reference, &signature_edit);
    _ = try expectStandInMatches(a, root, reference, &schema_edit);
    // Coming back lowers what the edits' records replaced; the build after
    // that stands the same two functions in again.
    _ = try expectStandInMatches(a, root, reference, &original);
    const again = try expectStandInMatches(a, root, reference, &original);
    try t.expectEqual(warm.reused, again.reused);
}

/// A module no edit below touches; neither function is an inline candidate.
const other_source =
    \\module other
    \\
    \\
    \\public def grow(xs: list[int], k: int) -> list[int]:
    \\    out: list[int] = []
    \\    for x in xs:
    \\        out.append(x + k)
    \\    return out
    \\
    \\
    \\public def last(xs: list[int]) -> int:
    \\    return xs[len(xs) - 1]
    \\
;

/// The entry of the three-module project: it uses `helper` and `other`.
const three_main_source = replaced(
    replaced(main_source, "import helper\n", "import helper\nimport other\n"),
    "    out.print(str(p.left))\n",
    "    ys = other.grow(xs, 4)\n    out.print(other.last(ys))\n    out.print(str(p.left))\n",
);

/// The three-module project before and after a body edit in `helper`.
const three: Files = .{ .main = three_main_source, .helper = helper_source, .other = other_source };
const three_body_edit: Files = .{ .main = three_main_source, .helper = body_edit.helper, .other = other_source };

// spec-case: EMIT-STANDIN-1
test "a body edit in one module stands in every function of the modules it did not touch" {
    // RC-DEFAULT-1: reads the tracing collector's lowering, not the RC default's.
    const collector_runtime = language.runtime_mode.pinCollector();
    defer language.runtime_mode.set(collector_runtime);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const root = try std.fs.path.join(a, &.{ base, "standin" });
    const reference = try std.fs.path.join(a, &.{ base, "full" });
    const cold = try expectStandInMatches(a, root, reference, &three);
    try t.expectEqual(@as(usize, 0), cold.reused);
    // Unchanged: `scale`, `first`, `grow` and `last` are stood in.
    const warm = try expectStandInMatches(a, root, reference, &three);
    try t.expectEqual(@as(usize, 4), warm.reused);
    try t.expectEqual(cold.lowered, warm.lowered + warm.reused);
    // The edit moves positions in `helper` only, so its functions are lowered
    // again while `grow` and `last` in `other` stay stood in.
    const body = try expectStandInMatches(a, root, reference, &three_body_edit);
    try t.expectEqual(@as(usize, 2), body.reused);
    try t.expectEqual(cold.lowered, body.lowered + body.reused);
    // A function keeps one record, which the edit replaced, so going back
    // lowers `helper` once more and the next unchanged build stands it in.
    const back = try expectStandInMatches(a, root, reference, &three);
    try t.expectEqual(@as(usize, 2), back.reused);
    const again = try expectStandInMatches(a, root, reference, &three);
    try t.expectEqual(@as(usize, 4), again.reused);
}

const rc_main =
    \\module main
    \\import helper
    \\def main() -> int:
    \\    nodes = [helper.Span(b"abc", 2)]
    \\    selected = helper.at(nodes, 0)
    \\    return selected.start
;
const rc_helper =
    \\module helper
    \\public record Span:
    \\    source: bytes
    \\    start: int
    \\def empty() -> Span:
    \\    return Span(b"", 0)
    \\public def at(nodes: list[Span], index: int) -> Span:
    \\    if index < 0 or index >= len(nodes):
    \\        return empty()
    \\    return nodes[index]
;
const rc_original: Files = .{ .main = rc_main, .helper = rc_helper };
const rc_transitive: Files = .{ .main = rc_main, .helper = replaced(rc_helper, "return Span(b\"\", 0)", "return Span(b\"\", 7)") };
const rc_fresh: Files = .{ .main = rc_main, .helper = replaced(rc_helper, "return Span(b\"\", 0)", "return Span(bytes([7]), 0)") };

// spec: RC-BORROW-CACHE-1
test "RC-BORROW-CACHE-1 caller fragments follow transitive proof edits and refusal" {
    const runtime = @import("runtime_mode.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const cold = try expectReusedEqualsFresh(root, &rc_original);
    const warm = try expectReusedEqualsFresh(root, &rc_original);
    try t.expectEqual(cold.misses, warm.hits);
    try t.expectEqual(@as(usize, 0), warm.misses);
    const transitive = try expectReusedEqualsFresh(root, &rc_transitive);
    try t.expect(transitive.misses >= 2);
    const fresh = try expectReusedEqualsFresh(root, &rc_fresh);
    try t.expect(fresh.misses >= 2);
    _ = try expectReusedEqualsFresh(root, &rc_original);
}

// spec-case: RC-BORROW-CACHE-1
test "RC-BORROW-CACHE-1 stand-ins lower complete proofs and preserve alternate metadata" {
    const runtime = @import("runtime_mode.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const root = try std.fs.path.join(a, &.{ base, "standin" });
    const reference = try std.fs.path.join(a, &.{ base, "full" });
    const cold = try expectStandInMatches(a, root, reference, &rc_original);
    const warm = try expectStandInMatches(a, root, reference, &rc_original);
    try t.expectEqual(cold.lowered, warm.lowered);
    try t.expectEqual(@as(usize, 0), warm.reused);
    _ = try expectStandInMatches(a, root, reference, &rc_transitive);
    _ = try expectStandInMatches(a, root, reference, &rc_fresh);
    const restored = try expectStandInMatches(a, root, reference, &rc_original);
    try t.expectEqual(cold.lowered, restored.lowered);
}

const rc_loop_helper = replaced(
    rc_helper,
    "    if index < 0 or index >= len(nodes):\n        return empty()\n    return nodes[index]",
    "    i = 0\n    while i < len(nodes):\n        node = nodes[i]\n        if node.start == index:\n            return node\n        i += 1\n    return empty()",
);

const rc_loop_fresh = replaced(rc_loop_helper, "b\"\"", "bytes([7])");

// spec-case: RC-BORROW-LOOP-1
test "RC-BORROW-LOOP-1 warm callers follow loop certificates and fresh fallback refusal" {
    const runtime = @import("runtime_mode.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const looping: Files = .{ .main = rc_main, .helper = rc_loop_helper };
    const fresh: Files = .{ .main = rc_main, .helper = rc_loop_fresh };
    const cold = try expectReusedEqualsFresh(root, &looping);
    const warm = try expectReusedEqualsFresh(root, &looping);
    try t.expectEqual(cold.misses, warm.hits);
    try t.expectEqual(@as(usize, 0), warm.misses);
    const refused = try expectReusedEqualsFresh(root, &fresh);
    try t.expect(refused.misses >= 2);
    _ = try expectReusedEqualsFresh(root, &looping);
}

const rc_composed_helper = replaced(rc_loop_helper, "public def at(", "def picked(") ++
    "\npublic def at(nodes: list[Span], index: int) -> Span:\n    a = picked(nodes, index)\n    b = picked(nodes, index + 1)\n    if a.start < b.start:\n        return a\n    return b\n";
const rc_composed_fresh = replaced(rc_composed_helper, "b\"\"", "bytes([7])");

// spec-case: RC-BORROW-COMPOSE-1
test "RC-BORROW-COMPOSE-1 caller cache follows transitive callee certificate loss" {
    const runtime = @import("runtime_mode.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(t.io, ".", t.allocator);
    defer t.allocator.free(root);
    const composed: Files = .{ .main = rc_main, .helper = rc_composed_helper };
    const lost: Files = .{ .main = rc_main, .helper = rc_composed_fresh };
    const cold = try expectReusedEqualsFresh(root, &composed);
    const warm = try expectReusedEqualsFresh(root, &composed);
    try t.expectEqual(cold.misses, warm.hits);
    try t.expectEqual(@as(usize, 0), warm.misses);
    const refused = try expectReusedEqualsFresh(root, &lost);
    try t.expect(refused.misses >= 3);
    _ = try expectReusedEqualsFresh(root, &composed);
}

/// `other` with a pure function that writes its record parameter: a caller
/// may pass the record's address without a copy only while no such write
/// exists, and it learns that from the callee's facts.
const writing_other_source =
    \\module other
    \\
    \\
    \\public record Box:
    \\    a: int
    \\    b: int
    \\
    \\
    \\public def flip(box: Box) -> int effects():
    \\    box = Box(a=box.b, b=box.a)
    \\    if box.a > 1000:
    \\        return flip(box)
    \\    return box.a * 10 + box.b
    \\
    \\
    \\public def keep(box: Box) -> int effects():
    \\    if box.a > 1000:
    \\        return keep(box)
    \\    return box.a * 10 + box.b
    \\
    \\
    \\public def merge(box: Box, extra: int) -> int effects():
    \\    if box.a > 1000:
    \\        return merge(box, extra)
    \\    return box.a + extra
    \\
;

/// Reads each element of a list of records in place across pure calls.
const borrowing_loop = "    boxes = [other.Box(a=1, b=2), other.Box(a=3, b=4)]\n    spare = 0\n    for s in boxes:\n" ++
    "        spare += other.flip(s) + s.b + other.keep(s)\n    out.print(spare)\n";

/// The three-module project whose entry reads each list element in place
/// across calls to `other.flip` and `other.keep`: the element may stay
/// borrowed across a pure call only when the callee writes no record
/// parameter (`QBE-ELEMREF-4`), and `flip` writes one.
const writing: Files = .{
    .main = replaced(three_main_source, "    ys = other.grow(xs, 4)\n    out.print(other.last(ys))\n", borrowing_loop),
    .helper = helper_source,
    .other = writing_other_source,
};

/// `writing` after an edit to its entry only.
const writing_edited: Files = .{ .main = replaced(writing.main, "a=3, b=4", "a=3, b=5"), .helper = helper_source, .other = writing_other_source };

// spec: EMIT-WRITES-1
test "a caller reads a stood-in callee's parameter writes from its facts, not from a body it did not lower" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const root = try std.fs.path.join(a, &.{ base, "standin" });
    const reference = try std.fs.path.join(a, &.{ base, "full" });
    _ = try expectStandInMatches(a, root, reference, &writing);
    // An edit to the entry alone: `flip`, `keep` and `merge` are stood in with
    // empty bodies, and the entry's unit is emitted afresh — the text must
    // still be the full emission's, which copies each element before `flip`.
    const edited = try expectStandInMatches(a, root, reference, &writing_edited);
    try t.expect(edited.reused >= 3);
}

/// The lean executable emission's report of `files`, through a store at `root`.
fn reportOf(allocator: std.mem.Allocator, root: []const u8, files: *const Files, executable: bool) !fragments.Report {
    var opened: Opened = undefined;
    try opened.init(root);
    defer opened.deinit();
    var report: fragments.Report = .{ .arena = allocator };
    const manifest = try emit(t.allocator, files, .{ .store = &opened.store, .lean = true, .executable = executable, .report = &report });
    t.allocator.free(manifest);
    return report;
}

fn unitKey(report: fragments.Report, name: []const u8) []const u8 {
    for (report.functions) |entry| if (std.mem.eql(u8, entry.name, name)) return entry.keys.unit;
    return "";
}

/// `helper` with a function that invokes a function value, and `other` taking
/// one more function as a value where nothing reaches it.
const invoking_helper_source = helper_source ++
    \\
    \\
    \\public def apply(f: def(int) -> int effects(), value: int) -> int effects():
    \\    return f(value)
    \\
    \\
    \\public def bump(value: int) -> int effects():
    \\    return value + 1
    \\
;
const invoking: Files = .{
    .main = replaced(main_source, "    return 0\n", "    return helper.apply(helper.bump, 1)\n"),
    .helper = invoking_helper_source,
};
const invoking_more: Files = .{
    .main = invoking.main,
    .helper = invoking_helper_source ++ "\n\npublic def pick() -> def(int) -> int effects():\n    return total_of\n\n\ndef total_of(value: int) -> int effects():\n    return value\n",
};

// spec: EMIT-VALUE-TARGETS-1
test "an executable's invoking unit keys on no program-wide function-value target set" {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try directory.dir.realPathFileAlloc(t.io, ".", a);
    // A function value taken somewhere else in the program: the executable's
    // key of `apply` holds, since its text never read the target set.
    const before = try reportOf(a, try std.fs.path.join(a, &.{ base, "e1" }), &invoking, true);
    const after = try reportOf(a, try std.fs.path.join(a, &.{ base, "e2" }), &invoking_more, true);
    try t.expect(unitKey(before, "helper::apply").len != 0);
    try t.expectEqualStrings(unitKey(before, "helper::apply"), unitKey(after, "helper::apply"));
    // A library's unit lists every target as a dependency, so its key moves.
    const library_before = try reportOf(a, try std.fs.path.join(a, &.{ base, "l1" }), &invoking, false);
    const library_after = try reportOf(a, try std.fs.path.join(a, &.{ base, "l2" }), &invoking_more, false);
    try t.expect(!std.mem.eql(u8, unitKey(library_before, "helper::apply"), unitKey(library_after, "helper::apply")));
    try t.expect(!std.mem.eql(u8, unitKey(before, "helper::apply"), unitKey(library_before, "helper::apply")));
}

/// Lower `files` and return the first-pass key of the function named `name`.
fn localKey(allocator: std.mem.Allocator, files: *const Files, name: []const u8) !fragments.Digest {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = @constCast(files), .read = read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.emit();
    const code = compilation.code.?;
    var keys = try fragments.Keys.init(allocator, code);
    defer keys.deinit();
    for (code.functions, 0..) |function, at| {
        if (std.mem.eql(u8, function.name, name)) return keys.local(at, .{ .step_checks = true, .frame_checks = true, .checks = true, .arenas = false, .entry = false });
    }
    return error.TestUnexpectedResult;
}

// spec: QBE-FRAGMENT-REUSE-2
test "a caller's key reads each callee parameter's name and type, not the callee body's use of it" {
    // `keep` reassigning its parameter makes that local mutable in its own
    // check; a module compiled against `other`'s interface sees `pass`.
    const reassigning: Files = .{
        .main = writing.main,
        .helper = helper_source,
        .other = comptime replaced(writing_other_source, "    if box.a > 1000:\n        return keep(box)\n", "    box = Box(a=box.a, b=box.b)\n    if box.a > 1000:\n        return keep(box)\n"),
    };
    const plain = try localKey(t.allocator, &writing, "main::main");
    const moved = try localKey(t.allocator, &reassigning, "main::main");
    try t.expectEqualSlices(u8, &plain, &moved);
}
