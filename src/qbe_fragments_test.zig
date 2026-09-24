//! Per-function QBE unit reuse (`QBE-FRAGMENT-REUSE-1`): a project emitted
//! through a fragment store after an edit must be byte-for-byte the manifest a
//! fresh emission of the edited project produces, while every unit whose
//! emission inputs did not change is answered from the store.
const std = @import("std");
const language = @import("compiler.zig");
const fragments = @import("qbe_fragments.zig");
const units = @import("qbe_build_units.zig");
const t = std.testing;

/// The two modules of one version of the test project.
const Files = struct { main: []const u8, helper: []const u8 };

fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    const files: *const Files = @ptrCast(@alignCast(context.?));
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8, files.main);
    if (std.mem.eql(u8, path, "helper.my")) return allocator.dupe(u8, files.helper);
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
    for (document.object.get("functions").?.array.items) |unit| {
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
    try t.expectEqual(@as(usize, 0), cold.statistics.meta_hits);
    try t.expectEqual(cold.statistics.misses, cold.statistics.meta_misses);
    // Nothing changed: every unit's metadata is read, none computed.
    const warm = try emitLean(a, root, &original);
    try t.expectEqual(@as(usize, 0), warm.statistics.meta_misses);
    try t.expectEqualStrings(cold.manifest, warm.manifest);
    // A body edit in `helper` recomputes the metadata of helper's units only,
    // and a unit whose positions did not move keeps its digest.
    const body = try emitLean(a, root, &body_edit);
    try t.expect(body.statistics.meta_misses >= 1 and body.statistics.meta_misses <= 5);
    try t.expectEqual(body.statistics.meta_hits + body.statistics.meta_misses, cold.statistics.meta_misses);
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
