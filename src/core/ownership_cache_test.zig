//! Ownership reuse must remain incremental without accepting a stale success.
const std = @import("std");
const frontend = @import("frontend.zig");
const ownership = @import("ownership_cache.zig");
const stage = @import("stage_store.zig");
const demand = @import("lowering_demand.zig");

const entry = "import lib\nfunc main() -> int:\n    return lib.change(4) + lib.keep(5)\n";
const library = "public func change(x: int) -> int:\n    return x + 1\npublic func keep(x: int) -> int:\n    return x * 2\n";
const Outcome = struct { valid: bool, work: frontend.Statistics, ownership: ownership.Work, diagnostics: []const u8 };

fn check(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, cached: bool) !Outcome {
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    if (cached) try session.enableCache(backing, try std.fs.path.join(a, &.{ root, "cache" }));
    session.validationOnly();
    var messages: std.ArrayList(u8) = .empty;
    const valid = if (session.check(a, "main", &messages)) |_| true else |err| switch (err) {
        error.SourceError => false,
        else => return err,
    };
    return .{ .valid = valid, .work = session.statistics(), .ownership = session.ownershipWork(), .diagnostics = messages.items };
}

fn fixture(directory: std.Io.Dir, lib: []const u8) !void {
    try directory.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = entry });
    try directory.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib });
}

const generic_entry =
    \\import lib
    \\func main() -> int:
    \\    return lib.outer[int](7) + lib.outer[int[]]([1])
;
const generic_library =
    \\public func outer[T](value: T) -> int:
    \\    return inner[T](copy(value))
    \\func inner[T](own value: T) -> int:
    \\    const moved = own value
    \\    _ = moved
    \\    return 0
;

test "O2 ownership checks imported nested generic instances after semantic cache replay" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = generic_entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = generic_library });
    // `main`, `outer` and `inner` for `int` and `int[]`, and the `str` and record instances `check` makes to judge both
    // templates at their declaration (W3 step 2): nine functions.
    const cold = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(cold.valid);
    try std.testing.expectEqual(@as(usize, 9), cold.ownership.checked);
    // A second check finds both templates' judgments held and makes none of their stand-ins: the five functions it has are
    // reused.
    const warm = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(warm.valid);
    try std.testing.expectEqual(@as(usize, 5), warm.ownership.reused);
    try std.testing.expectEqual(@as(usize, 0), warm.ownership.checked);
    try directory.dir.deleteTree(std.testing.io, "cache/engine-v1/records/ownership-proof");
    const replayed = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(replayed.valid);
    try std.testing.expect(replayed.work.reused > 0);
    try std.testing.expectEqual(@as(usize, 9), replayed.ownership.checked);
    try std.testing.expectEqual(@as(usize, 0), replayed.ownership.reused);
}

test "O2 ownership refuses a changed and replayed managed generic body beside scalar instances" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = generic_entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = generic_library });
    try std.testing.expect((try check(a, std.testing.allocator, root, true)).valid);
    const invalid = try std.mem.replaceOwned(u8, a, generic_library, "_ = moved", "_ = value");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = invalid });
    const changed = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(!changed.valid);
    try std.testing.expect(std.mem.indexOf(u8, changed.diagnostics, "E_SINGLE_OWNER_MOVED") != null);
    const replayed = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(!replayed.valid);
    try std.testing.expect(replayed.work.reused > 0);
    try std.testing.expect(std.mem.indexOf(u8, replayed.diagnostics, "E_SINGLE_OWNER_MOVED") != null);
    // A program that calls the template with `int` alone is refused too: `check` judges `inner` at its declaration for a
    // managed `T` (W3 step 2), where before only a managed instance reported it.
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "import lib\nfunc main() -> int:\n    return lib.outer[int](7)\n" });
    const scalar_only = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(!scalar_only.valid);
    try std.testing.expect(std.mem.indexOf(u8, scalar_only.diagnostics, "the body of `inner` is refused when `T` is") != null);
}

const DigestFiles = struct {
    main: []const u8 = entry,
    lib: []const u8 = library,
    empty: ?[]const u8 = null,
    reads: usize = 0,

    fn read(pointer: ?*anyopaque, a: std.mem.Allocator, path: []const u8, limit: usize) @import("selka").project.ReadError![]u8 {
        const self: *DigestFiles = @ptrCast(@alignCast(pointer.?));
        self.reads += 1;
        const bytes = if (std.mem.eql(u8, path, "main.selka")) self.main else if (std.mem.eql(u8, path, "lib.selka") or std.mem.eql(u8, path, "strings.selka")) self.lib else remaining: {
            if (std.mem.eql(u8, path, "empty.selka")) break :remaining self.empty orelse return error.NotFound;
            return error.NotFound;
        };
        if (bytes.len > limit) return error.TooLarge;
        return a.dupe(u8, bytes);
    }

    fn provider(self: *DigestFiles) @import("selka").project.Provider {
        return .{ .context = self, .read = read };
    }
};

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 deferred source digests preserve verdict keys and materialize immutable provider snapshots" {
    const language = @import("selka");
    const a = std.testing.allocator;
    var files: DigestFiles = .{};
    var eager = language.project.Project.init(a);
    defer eager.deinit();
    try eager.load(files.provider(), "main", .{});
    var deferred = language.project.Project.init(a);
    defer deferred.deinit();
    try deferred.load(files.provider(), "main", .{ .digests = .deferred });
    try std.testing.expect(eager.progress.source_digests_ready);
    try std.testing.expect(!deferred.progress.source_digests_ready);
    var cache = language.frontend_cache.Cache.init(a, std.testing.io, "unused", "");
    defer cache.deinit();
    const before = cache.verdictKeyFor(&deferred, .text);
    try std.testing.expectEqualSlices(u8, &cache.verdictKeyFor(&eager, .text), &before);
    // An overlay/provider change after loading cannot alter either snapshot.
    files.lib = entry;
    const reads = files.reads;
    deferred.ensureSourceDigests();
    try std.testing.expectEqual(reads, files.reads);
    try std.testing.expect(deferred.progress.source_digests_ready);
    for (eager.modules.items, deferred.modules.items) |left, right| try std.testing.expectEqualSlices(u8, &left.digest, &right.digest);
    const eager_text = try eager.render(a);
    defer a.free(eager_text);
    const deferred_text = try deferred.render(a);
    defer a.free(deferred_text);
    try std.testing.expectEqualStrings(eager_text, deferred_text);
    deferred.ensureSourceDigests();
    try std.testing.expectEqual(reads, files.reads);
    try std.testing.expectEqualSlices(u8, &before, &cache.verdictKeyFor(&deferred, .text));
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 deferred source digest verdict hits preserve warnings and reject byte path and policy mutations" {
    const language = @import("selka");
    const a = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root);
    var cache = language.frontend_cache.Cache.init(a, std.testing.io, root, "");
    defer cache.deinit();
    var files: DigestFiles = .{};
    var saved = language.project.Project.init(a);
    defer saved.deinit();
    try saved.load(files.provider(), "main", .{});
    try cache.setPolicyIdentity("configured-policy-A");
    try cache.rememberVerdict(&saved, .text, "warning: preserved\n");
    var warm = language.project.Project.init(a);
    defer warm.deinit();
    try warm.load(files.provider(), "main", .{ .digests = .deferred });
    const warnings = (try cache.lookupVerdict(a, &warm, .text)).?;
    defer a.free(warnings);
    try std.testing.expectEqualStrings("warning: preserved\n", warnings);
    try std.testing.expect(!warm.progress.source_digests_ready);
    try cache.setPolicyIdentity("configured-policy-B");
    try std.testing.expect(try cache.lookupVerdict(a, &warm, .text) == null);
    try cache.setPolicyIdentity("configured-policy-A");
    warm.modules.items[1].src.path = "different/lib.selka";
    try std.testing.expect(try cache.lookupVerdict(a, &warm, .text) == null);
    files.lib = try std.mem.replaceOwned(u8, a, library, "x + 1", "x + 9");
    defer a.free(files.lib);
    var changed = language.project.Project.init(a);
    defer changed.deinit();
    try changed.load(files.provider(), "main", .{ .digests = .deferred });
    try std.testing.expect(try cache.lookupVerdict(a, &changed, .text) == null);
    changed.ensureSourceDigests();
    try std.testing.expect(changed.progress.source_digests_ready);
    try std.testing.expect(!std.mem.eql(u8, &saved.modules.items[1].digest, &changed.modules.items[1].digest));
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 deferred source digests can materialize incomplete graphs for failure consumers" {
    const language = @import("selka");
    var files: DigestFiles = .{ .main = "import empty\nimport missing\n", .empty = "" };
    var eager = language.project.Project.init(std.testing.allocator);
    defer eager.deinit();
    try std.testing.expectError(error.SourceError, eager.load(files.provider(), "main", .{}));
    var loaded = language.project.Project.init(std.testing.allocator);
    defer loaded.deinit();
    try std.testing.expectError(error.SourceError, loaded.load(files.provider(), "main", .{ .digests = .deferred }));
    try std.testing.expectEqual(@as(usize, 3), loaded.modules.items.len);
    try std.testing.expect(loaded.modules.items[1].state.digest_pending);
    try std.testing.expect(!loaded.modules.items[2].state.digest_pending);
    // A provider failure leaves a placeholder's digest unspecified. Preserve
    // that field rather than conflating an unread source with a valid empty file.
    eager.modules.items[2].digest = @splat(0x5a);
    loaded.modules.items[2].digest = @splat(0x5a);
    loaded.ensureSourceDigests();
    try std.testing.expect(loaded.progress.source_digests_ready);
    for (eager.modules.items, loaded.modules.items) |left, right| try std.testing.expectEqualSlices(u8, &left.digest, &right.digest);
}

// spec: LOCAL-STDLIB-SOURCE-1
// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 deferred source digests match embedded and provider-overridden standard modules" {
    const language = @import("selka");
    const a = std.testing.allocator;
    const imported = try std.mem.replaceOwned(u8, a, entry, "import lib", "import strings as lib");
    defer a.free(imported);
    var files: DigestFiles = .{ .main = imported };
    for ([_]bool{ false, true }) |standard_from_provider| {
        var eager = language.project.Project.init(a);
        defer eager.deinit();
        try eager.load(files.provider(), "main", .{ .standard = .{ .from_provider = standard_from_provider } });
        var deferred = language.project.Project.init(a);
        defer deferred.deinit();
        try deferred.load(files.provider(), "main", .{ .standard = .{ .from_provider = standard_from_provider }, .digests = .deferred });
        const strings = deferred.modules.items[deferred.names.get("strings").?];
        try std.testing.expectEqualStrings(if (standard_from_provider) "strings.selka" else "@stdlib/strings.selka", strings.src.path);
        try std.testing.expectEqual(standard_from_provider, std.mem.eql(u8, library, strings.src.bytes));
        var cache = language.frontend_cache.Cache.init(a, std.testing.io, "unused", "");
        defer cache.deinit();
        try std.testing.expectEqualSlices(u8, &cache.verdictKeyFor(&eager, .text), &cache.verdictKeyFor(&deferred, .text));
        deferred.ensureSourceDigests();
        for (eager.modules.items, deferred.modules.items) |left, right| try std.testing.expectEqualSlices(u8, &left.digest, &right.digest);
    }
}

fn refuseLowering(_: *const anyopaque, _: []const u8, _: stage.Digest, _: stage.Digest) bool {
    return false;
}

// spec-case: NEW-CORE-DEMAND-1
test "W07 ownership semantic proofs reuse concrete functions without lowering artifacts" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library);
    try std.testing.expect((try check(a, std.testing.allocator, root, true)).valid);
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(std.testing.allocator, try std.fs.path.join(a, &.{ root, "cache" }));
    const context: u8 = 0;
    session.configureDemand(.{ .context = &context, .allow = refuseLowering });
    var messages: std.ArrayList(u8) = .empty;
    _ = try session.check(a, "main", &messages);
    for (session.demandState().?.omitted) |omitted| try std.testing.expect(!omitted);
    try std.testing.expectEqual(@as(usize, 3), session.ownershipWork().reused);
    try std.testing.expectEqual(@as(usize, 0), session.ownershipWork().checked);
}

// spec-case: NEW-CORE-DEMAND-1
test "W07 ownership cache omits validated bodies and rechecks only changed functions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library);
    const cold = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(cold.valid);
    try std.testing.expectEqual(@as(usize, 0), cold.ownership.reused);
    const warm = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(warm.valid);
    try std.testing.expectEqual(@as(usize, 3), warm.ownership.reused);
    try std.testing.expectEqual(@as(usize, 0), warm.ownership.checked);
    try fixture(directory.dir, "public func change(x: int) -> int:\n    return x + 9\npublic func keep(x: int) -> int:\n    return x * 2\n");
    const edited = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(edited.valid);
    try std.testing.expectEqual(@as(usize, 2), edited.ownership.reused);
    try std.testing.expectEqual(@as(usize, 1), edited.ownership.checked);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership cache loss forces concrete checking despite surviving semantic summaries" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library);
    _ = try check(a, std.testing.allocator, root, true);
    try std.testing.expect((try check(a, std.testing.allocator, root, true)).ownership.reused > 0);
    try directory.dir.deleteTree(std.testing.io, "cache/engine-v1/records/ownership-proof");
    const lost = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(lost.valid);
    try std.testing.expectEqual(@as(usize, 0), lost.ownership.reused);
    try std.testing.expectEqual(@as(usize, 3), lost.ownership.checked);
}

const builder = @import("build.zig");
const lowering = @import("lowering_cache.zig");
const emitter = @import("emit_llvm.zig");

fn locate(_: *const anyopaque, span: u32) emitter.Location {
    return .{ .path = "ownership-demand.selka", .line = 1, .column = span + 1 };
}

fn compareBuild(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8) !usize {
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var store = try stage.Store.init(backing, std.testing.io, cache);
    defer store.deinit();
    var proof = try demand.Context.init(a, &store, false);
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(backing, cache);
    session.configureDemand(proof.callback());
    var messages: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "main", &messages);
    const state = session.demandState().?;
    proof.attach(state.prepared, state.omitted);
    var lowered = lowering.Cache.init(&store);
    lowered.demand = &proof;
    var refusal: builder.Refusal = .{};
    const actual = try builder.buildExecutableCached(a, .{ .program = checked.program, .source = checked.src }, &refusal, &lowered);
    try proof.finish();
    _ = try store.flush();
    var full = frontend.Session.init(backing, std.testing.io, root);
    defer full.deinit();
    const fresh = try full.check(a, "main", &messages);
    const expected = try builder.buildExecutable(a, .{ .program = fresh.program, .source = fresh.src }, &refusal);
    const context: u8 = 0;
    const options: emitter.Options = .{ .locator = .{ .context = &context, .locate = locate }, .source_path = "main.selka", .main = .{} };
    try std.testing.expectEqualStrings(try emitter.emitModule(a, &expected, options), try emitter.emitModule(a, &actual, options));
    return proof.count();
}

// spec-case: NEW-CORE-DEMAND-1
test "W07 ownership demand lowering omits safe bodies and reproduces eager LLVM after an edit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library);
    try std.testing.expectEqual(@as(usize, 0), try compareBuild(a, std.testing.allocator, root));
    try std.testing.expectEqual(@as(usize, 2), try compareBuild(a, std.testing.allocator, root));
    try fixture(directory.dir, "public func change(x: int) -> int:\n    return x + 9\npublic func keep(x: int) -> int:\n    return x * 2\n");
    try std.testing.expectEqual(@as(usize, 1), try compareBuild(a, std.testing.allocator, root));
}

/// One demand build of the fixture with the ownership cache and the lowering receipts as the build command holds them; how many functions the
/// hosts' module answers covered, and how many bodies were left out.
fn moduleBuild(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8) !struct { covered: u32, omitted: usize } {
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    var store = try stage.Store.init(backing, std.testing.io, cache);
    defer store.deinit();
    var proof = try demand.Context.init(a, &store, false);
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(backing, cache);
    session.configureDemand(proof.callback());
    var messages: std.ArrayList(u8) = .empty;
    const checked = try session.check(a, "main", &messages);
    const state = session.demandState().?;
    proof.attach(state.prepared, state.omitted);
    var lowered = lowering.Cache.init(&store);
    lowered.demand = &proof;
    var refusal: builder.Refusal = .{};
    _ = try builder.buildExecutableCached(a, .{ .program = checked.program, .source = checked.src }, &refusal, &lowered);
    try proof.finish();
    _ = try store.flush();
    return .{ .covered = state.prepared.grouping.covered, .omitted = proof.count() };
}

// spec-case: NEW-CORE-DEMAND-1
test "G2p the hosts answer for a module on the second build, and an edit leaves the edited module to the per-function path" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library);
    const cold = try moduleBuild(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(usize, 0), cold.omitted);
    try std.testing.expectEqual(@as(u32, 0), cold.covered);
    // The records the cold build wrote answer for the library's two functions as a module.
    const warm = try moduleBuild(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(usize, 2), warm.omitted);
    try std.testing.expectEqual(@as(u32, 2), warm.covered);
    // An edit moves the library's signature: nothing is covered, and the function that did not change is still left out.
    try fixture(directory.dir, "public func change(x: int) -> int:\n    return x + 9\npublic func keep(x: int) -> int:\n    return x * 2\n");
    const edited = try moduleBuild(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(usize, 1), edited.omitted);
    try std.testing.expectEqual(@as(u32, 0), edited.covered);
    // The edit's records stand: the same source again is covered, and so is the original, whose record was kept beside it.
    const repeat = try moduleBuild(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(usize, 2), repeat.omitted);
    try std.testing.expectEqual(@as(u32, 2), repeat.covered);
    try fixture(directory.dir, library);
    const reverted = try moduleBuild(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(u32, 2), reverted.covered);
}

/// The library edited into `states` states, each built twice: how many functions the second build of the last was covered for, and
/// every earlier second build must have been covered for both.
fn everyStateCovered(a: std.mem.Allocator, backing: std.mem.Allocator, directory: std.Io.Dir, root: []const u8, states: usize) !u32 {
    var covered: u32 = 0;
    for (0..states) |state| {
        const text = try std.fmt.allocPrint(a, "public func change(x: int) -> int:\n    return x + {d}\npublic func keep(x: int) -> int:\n    return x * 2\n", .{state + 20});
        try fixture(directory, text);
        _ = try moduleBuild(a, backing, root);
        covered = (try moduleBuild(a, backing, root)).covered;
        try std.testing.expectEqual(@as(u32, 2), covered);
    }
    return covered;
}

// spec-case: NEW-CORE-DEMAND-1
test "G2p a module answer is never more than the answers for its functions: not after the ownership records are lost, nor once a function's proofs outgrow the record" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library);
    _ = try moduleBuild(a, std.testing.allocator, root);
    try std.testing.expectEqual(@as(u32, 2), (try moduleBuild(a, std.testing.allocator, root)).covered);
    // The ownership records are lost while the lowering receipts survive. A Debug compiler holds every module answer against the function
    // answers, so a marker that outlived its proofs would stop the build; here nothing is covered, and the next builds prove it all again.
    try directory.dir.deleteTree(std.testing.io, "cache/engine-v1/records/ownership-proof");
    try std.testing.expectEqual(@as(u32, 0), (try moduleBuild(a, std.testing.allocator, root)).covered);
    try std.testing.expectEqual(@as(u32, 2), (try moduleBuild(a, std.testing.allocator, root)).covered);
    // One function takes more states than a record keeps proofs of it, so the record lets go of the oldest. Each state is built twice: the
    // second build of a state is answered for the module, and every answer is compared with the functions' own.
    try std.testing.expectEqual(@as(u32, 2), try everyStateCovered(a, std.testing.allocator, directory.dir, root, 6));
    // The first state is back: whichever of its proofs the record kept, no answer says more than the functions do.
    try fixture(directory.dir, library);
    try std.testing.expect((try moduleBuild(a, std.testing.allocator, root)).covered <= 2);
    try std.testing.expectEqual(@as(u32, 2), (try moduleBuild(a, std.testing.allocator, root)).covered);
}

fn openFailure(backing: std.mem.Allocator, root: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    var cache = try ownership.Cache.init(arena.allocator(), backing, std.testing.io, root);
    defer cache.deinit();
    try cache.open("main.selka");
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership openOwnershipCache storage propagates allocation failures without leaks" {
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, openFailure, .{root});
}

fn cliCheck(a: std.mem.Allocator, root: []const u8, environment: *const std.process.Environ.Map) !std.process.RunResult {
    const tools = @import("core_test_options");
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ tools.corePath(), "check", try std.fs.path.join(a, &.{ root, "main.selka" }), "--cache-dir", try std.fs.path.join(a, &.{ root, "cli-cache" }), "--report", "--diagnostics=json" });
    return std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = environment });
}

fn expectUndeclared(report: []const u8) !void {
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, report, "\"code\":\"E_BORROW_UNDECLARED\""));
    try std.testing.expect(std.mem.indexOf(u8, report, "\"rule\":\"R4\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, report, "\"text\":\" from xs\"") != null);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership plain check verdicts reuse successful checks and invalidate body edits" {
    const tools = @import("core_test_options");
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try tools.privateEnvironment(a);
    defer environment.deinit();
    const invalid = library ++ "public func copied(xs: int[]) -> int[]:\n    return xs\n";
    try fixture(directory.dir, invalid);
    const plain = try cliCheck(a, root, &environment);
    try std.testing.expect(plain.term == .exited and plain.term.exited == 1);
    try expectUndeclared(plain.stderr);
    try fixture(directory.dir, library);
    const cold = try cliCheck(a, root, &environment);
    try std.testing.expect(cold.term == .exited and cold.term.exited == 0);
    const warm = try cliCheck(a, root, &environment);
    try std.testing.expect(warm.term == .exited and warm.term.exited == 0);
    try std.testing.expect(std.mem.indexOf(u8, warm.stderr, "\"reused_results\":1") != null);
    try fixture(directory.dir, invalid);
    const changed = try cliCheck(a, root, &environment);
    try std.testing.expect(changed.term == .exited and changed.term.exited == 1);
    try expectUndeclared(changed.stderr);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership cache invalidates unchanged bodies when a record becomes an owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const scalar = "public record Box:\n    value: int\npublic func transfer(x: Box) -> Box:\n    return x\n";
    const managed = "public record Box:\n    value: int[]\npublic func transfer(x: Box) -> Box:\n    mut kept = x\n    return kept\n";
    try fixture(directory.dir, library ++ scalar);
    try std.testing.expect((try check(a, std.testing.allocator, root, true)).valid);
    const warm = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(warm.ownership.reused > 0);
    try fixture(directory.dir, library ++ managed);
    const changed = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(!changed.valid);
    const fresh = try check(a, std.testing.allocator, root, false);
    try std.testing.expectEqualStrings(fresh.diagnostics, changed.diagnostics);
    try std.testing.expect(std.mem.indexOf(u8, changed.diagnostics, "E_SINGLE_OWNER_BORROW") != null);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership headerless checks reuse typed bodies and reject edited borrowed returns" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fs.path.join(a, &.{ root, "main.selka" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const safe = "func copied(xs: int[]) -> int[]:\n    return copy(xs)\nfunc main() -> int:\n    return 42\n";
    const refused = "func copied(xs: int[]) -> int[]:\n    return xs\nfunc main() -> int:\n    return 42\n";
    for ([_][]const u8{ safe, safe, refused }, 0..) |source, phase| {
        try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source });
        var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
        defer session.deinit();
        try session.enableCache(std.testing.allocator, cache);
        session.validationOnly();
        session.setFormat(.json);
        var messages: std.ArrayList(u8) = .empty;
        const valid = if (session.checkFile(a, path, &messages)) |_| true else |err| switch (err) {
            error.SourceError => false,
            else => return err,
        };
        try std.testing.expectEqual(phase != 2, valid);
        if (phase == 1) try std.testing.expectEqual(@as(usize, 2), session.ownershipWork().reused);
        if (phase == 2) try expectUndeclared(messages.items);
    }
}

fn selectConcreteFailure(backing: std.mem.Allocator, root: []const u8, program: @import("selka").typed.Program, source: @import("selka").source.Source) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var cache = try ownership.Cache.init(a, backing, std.testing.io, root);
    defer cache.deinit();
    var messages: std.ArrayList(u8) = .empty;
    try std.testing.expect(try cache.validate(a, program, source, .text, &messages));
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership selectConcrete propagates allocation failures without leaks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var compilation = try @import("selka").Compilation.init(a, "main.selka", "func main() -> int:\n    return 42\n");
    try compilation.check();
    try std.testing.checkAllAllocationFailures(std.testing.allocator, selectConcreteFailure, .{ root, compilation.program.?, compilation.src });
}

// spec-case: NOALLOC-ATTRIBUTE-1
test "W07 ownership noalloc checkAllocationContracts keeps validation-only scope" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try fixture(directory.dir, library ++ "@noalloc\npublic func copied(xs: int[]) -> int[]:\n    return copy(xs)\n");
    var session = frontend.Session.init(std.testing.allocator, std.testing.io, root);
    defer session.deinit();
    var messages: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.SourceError, session.check(a, "main", &messages));
    try std.testing.expect(std.mem.indexOf(u8, messages.items, "E_NOALLOC_ALLOCATES") != null);
    try std.testing.expect((try check(a, std.testing.allocator, root, true)).valid);
}

const chain_body = "    return n + 1\n";
const ChainOutcome = struct { valid: bool, checked: usize, summaries: usize, facts: []const u8, diagnostics: []const u8 };

fn chainFixture(a: std.mem.Allocator, directory: std.Io.Dir, body: []const u8) !void {
    const lib = try std.mem.concat(a, u8, &.{
        "public func leaf(n: int) -> int:\n",                                                                                                                                    body,
        "public func middle(n: int) -> int:\n    return leaf(n)\npublic func outer(n: int) -> int:\n    return middle(n)\npublic func keep(n: int) -> int:\n    return n * 2\n",
    });
    defer a.free(lib);
    try directory.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib });
    try directory.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = "import lib\nfunc main() -> int:\n    return lib.outer(4) + lib.keep(5)\n" });
}

fn chainCheck(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, cached: bool) !ChainOutcome {
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    if (cached) {
        try session.enableCache(backing, try std.fs.path.join(a, &.{ root, "cache" }));
        // Force summary reuse independently of retained checked trees.
        session.caches.frontend.?.semantic.reuse.max_bytes = 0;
    }
    session.validationOnly();
    var messages: std.ArrayList(u8) = .empty;
    const checked = session.check(a, "main", &messages) catch |err| switch (err) {
        error.SourceError => return .{ .valid = false, .checked = session.statistics().checked, .summaries = session.statistics().summaries, .facts = "", .diagnostics = messages.items },
        else => return err,
    };
    var facts: std.Io.Writer.Allocating = .init(a);
    defer facts.deinit();
    for (checked.program.functions) |function| try facts.writer.print("{s}: {any} {any} {any}\n", .{ function.name, function.signature.mutates, function.signature.return_origin, function.signature.inferred });
    return .{ .valid = true, .checked = session.statistics().checked, .summaries = session.statistics().summaries, .facts = try facts.toOwnedSlice(), .diagnostics = messages.items };
}

// spec-case: CHECK-SUMMARY-1
test "W07 ownership validation reuses transitive callers after an unchanged-fact body edit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try chainFixture(a, directory.dir, chain_body);
    try std.testing.expect((try chainCheck(a, std.testing.allocator, root, true)).valid);
    try chainFixture(a, directory.dir, "    return n + 9\n");
    const warm = try chainCheck(a, std.testing.allocator, root, true);
    const cold = try chainCheck(a, std.testing.allocator, root, false);
    try std.testing.expect(warm.valid and cold.valid);
    try std.testing.expectEqual(@as(usize, 2), warm.checked);
    try std.testing.expectEqual(@as(usize, 3), warm.summaries);
    try std.testing.expectEqualStrings(cold.facts, warm.facts);
    try std.testing.expectEqualStrings(cold.diagnostics, warm.diagnostics);
}

// spec-case: CHECK-SUMMARY-2
test "W07 ownership validation retries changed callee facts before reusing callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try chainFixture(a, directory.dir, chain_body);
    const initial = try chainCheck(a, std.testing.allocator, root, true);
    try std.testing.expect(initial.valid);
    try chainFixture(a, directory.dir, "    mut xs = [n]\n    append(mut xs, n + 1)\n    return xs[0]\n");
    const warm = try chainCheck(a, std.testing.allocator, root, true);
    const cold = try chainCheck(a, std.testing.allocator, root, false);
    try std.testing.expect(warm.valid and cold.valid);
    try std.testing.expectEqual(@as(usize, 5), warm.checked);
    try std.testing.expectEqual(@as(usize, 0), warm.summaries);
    try std.testing.expect(!std.mem.eql(u8, initial.facts, cold.facts));
    try std.testing.expectEqualStrings(cold.facts, warm.facts);
    try std.testing.expectEqualStrings(cold.diagnostics, warm.diagnostics);
    const repeated = try chainCheck(a, std.testing.allocator, root, true);
    try std.testing.expect(repeated.valid);
    try std.testing.expectEqualStrings(cold.facts, repeated.facts);
}

// spec-case: CHECK-SUMMARY-1
test "W07 ownership validation reuses unchanged declared facts through an edited cycle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try chainFixture(a, directory.dir, "    if n == 0:\n        return 1\n    return outer(n - 1)\n");
    const initial = try chainCheck(a, std.testing.allocator, root, true);
    try std.testing.expect(initial.valid);
    try chainFixture(a, directory.dir, "    if n == 0:\n        return 9\n    return outer(n - 1)\n");
    const warm = try chainCheck(a, std.testing.allocator, root, true);
    const cold = try chainCheck(a, std.testing.allocator, root, false);
    try std.testing.expect(warm.valid and cold.valid);
    // Only leaf and main need checking: callers consume declared signatures,
    // so the unchanged cycle no longer needs an inferred-fact fixed point.
    try std.testing.expectEqual(@as(usize, 2), warm.checked);
    try std.testing.expectEqual(@as(usize, 3), warm.summaries);
    // Uncached sessions do not publish reuse counters; their full semantic
    // output is the reference for the cached check.
    try std.testing.expectEqualStrings(initial.facts, cold.facts);
    try std.testing.expectEqualStrings(cold.facts, warm.facts);
    try std.testing.expectEqualStrings(cold.diagnostics, warm.diagnostics);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership validation never publishes a refused callee success beside cached callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try chainFixture(a, directory.dir, chain_body);
    try std.testing.expect((try chainCheck(a, std.testing.allocator, root, true)).valid);
    try chainFixture(a, directory.dir, "    mut first = [n]\n    const second = own first\n    return len(first) + len(second)\n");
    const warm = try chainCheck(a, std.testing.allocator, root, true);
    const repeated = try chainCheck(a, std.testing.allocator, root, true);
    const cold = try chainCheck(a, std.testing.allocator, root, false);
    try std.testing.expect(!warm.valid and !repeated.valid and !cold.valid);
    try std.testing.expect(std.mem.indexOf(u8, warm.diagnostics, "E_SINGLE_OWNER_MOVED") != null);
    try std.testing.expectEqualStrings(cold.diagnostics, warm.diagnostics);
    try std.testing.expectEqualStrings(cold.diagnostics, repeated.diagnostics);
}

// spec-case: NEW-CORE-DEMAND-1
test "W07 ownership lowering keeps the callers' artifacts after a callee's body edit, and reproduces eager LLVM" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try chainFixture(a, directory.dir, chain_body);
    try std.testing.expectEqual(@as(usize, 0), try compareBuild(a, std.testing.allocator, root));
    try std.testing.expectEqual(@as(usize, 4), try compareBuild(a, std.testing.allocator, root));
    try chainFixture(a, directory.dir, "    return n + 9\n");
    // The edited `leaf` is lowered again; `middle`, `outer` and `keep` stay out (a lowered function reads its callees' signatures, not
    // their bodies), and `compareBuild` checks the emitted LLVM against an eager build of the same program.
    try std.testing.expectEqual(@as(usize, 3), try compareBuild(a, std.testing.allocator, root));
}

const typed = @import("selka").typed;

fn digestChain(a: std.mem.Allocator, depth: usize, right: bool) !typed.Program {
    const nodes = try a.alloc(typed.Node, depth * 2 + 1);
    nodes[0] = .{ .ty = .i64, .span = .{ .start = 0, .end = 1 }, .data = .{ .integer = 1 } };
    for (0..depth) |index| {
        const leaf = index * 2 + 1;
        nodes[leaf] = .{ .ty = .i64, .span = .{ .start = leaf, .end = leaf + 1 }, .data = .{ .integer = @intCast(index + 2) } };
        nodes[leaf + 1] = .{ .ty = .i64, .span = .{ .start = 0, .end = leaf + 1 }, .data = .{ .binary = .{
            .op = .add,
            .left = @fromBackingInt(@intCast(if (right) leaf else leaf - 1)),
            .right = @fromBackingInt(@intCast(if (right) leaf - 1 else leaf)),
            .op_span = .{ .start = leaf, .end = leaf + 1 },
        } } };
    }
    const statements = try a.alloc(typed.Statement, 1);
    statements[0] = .{ .span = .{ .start = 0, .end = nodes.len }, .terminates = true, .data = .{ .ret = @fromBackingInt(@intCast(nodes.len - 1)) } };
    const functions = try a.alloc(typed.Function, 1);
    functions[0] = .{ .scope = .{ .body_complete = true, .body = @fromBackingInt(@intCast(0)) }, .id = @fromBackingInt(@intCast(0)), .name = "main", .declaration = .{ .start = 0, .end = 1 } };
    return .{ .nodes = nodes, .statements = statements, .functions = functions, .main = @fromBackingInt(@intCast(0)) };
}

// O4 adds own=false and type_dependent=false after view=false in seven nodes. The
// declaration/function signatures and ordered expression payloads keep their
// O3 representation, so each fixture grows from 342 to 356 bytes; G-D5 then leaves the
// two bytes of `signature.inferred` out of a declaration, and each shrinks by two.
// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership digest pins declared signatures and ordered tree encoding" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const left = try digestChain(arena.allocator(), 3, false);
    const right = try digestChain(arena.allocator(), 3, true);
    const lc = try lowering.Catalog.prepare(left);
    const rc = try lowering.Catalog.prepare(right);
    const ld = try lc.ownershipDigest(std.testing.allocator, left.functions[0]);
    const rd = try rc.ownershipDigest(std.testing.allocator, right.functions[0]);
    try std.testing.expectEqualStrings("8b9722e13aad66fd0e266bce6516a4805f8d1b4a1b692230dd441335053b24d1", &std.fmt.bytesToHex(ld, .lower));
    try std.testing.expectEqualStrings("ee92cf8854ab01ca46f9c89afebfd33bd963dcb6fd9c386da8dca75999064a8f", &std.fmt.bytesToHex(rd, .lower));
    try std.testing.expect(!std.mem.eql(u8, &ld, &rd));
}

test "G-D5 the declaration prefix ignores what the origin analysis inferred about a function, and the function's own digest does not" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try digestChain(arena.allocator(), 3, false);
    const before = try lowering.Catalog.prepare(program);
    const own_before = try before.ownershipDigest(std.testing.allocator, program.functions[0]);
    @constCast(program.functions)[0].signature.inferred.writes = true;
    @constCast(program.functions)[0].signature.inferred.external = true;
    const after = try lowering.Catalog.prepare(program);
    var left = before.prefix;
    var right = after.prefix;
    var left_digest: [32]u8 = undefined;
    var right_digest: [32]u8 = undefined;
    left.final(&left_digest);
    right.final(&right_digest);
    try std.testing.expectEqual(left_digest, right_digest);
    // The function's own key still holds its write facts: its tree hash covers its whole signature.
    const own_after = try after.ownershipDigest(std.testing.allocator, program.functions[0]);
    try std.testing.expect(!std.mem.eql(u8, &own_before, &own_after));
    // What the function declares is still part of the prefix.
    @constCast(program.functions)[0].signature.declared_mutates = &.{0};
    const declared = try lowering.Catalog.prepare(program);
    var moved = declared.prefix;
    var moved_digest: [32]u8 = undefined;
    moved.final(&moved_digest);
    try std.testing.expect(!std.mem.eql(u8, &left_digest, &moved_digest));
}

fn recordType(index: usize) typed.Type {
    return @fromBackingInt(typed.Type.record_base + index);
}

/// A program with records A and B that name each other, an unrelated record C, and three functions: `main`, `use_a` (a parameter of
/// type A) and `use_c` (returns C). Every table is mutable through `@constCast`.
fn reachFixture(a: std.mem.Allocator) !typed.Program {
    const body = try digestChain(a, 1, false);
    const span: @TypeOf(body.nodes[0].span) = .{ .start = 0, .end = 1 };
    const records = try a.dupe(typed.Record, &.{
        .{ .id = recordType(0), .name = "A", .declaration = span, .fields = try a.dupe(typed.Field, &.{ .{ .name = "x", .declaration = span, .ty = .i64 }, .{ .name = "next", .declaration = span, .ty = recordType(1) } }) },
        .{ .id = recordType(1), .name = "B", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "back", .declaration = span, .ty = recordType(0) }}) },
        .{ .id = recordType(2), .name = "C", .declaration = span, .fields = try a.dupe(typed.Field, &.{.{ .name = "y", .declaration = span, .ty = .i64 }}) },
    });
    const locals = try a.dupe(typed.Local, &.{.{ .name = "value", .declaration = span, .ty = recordType(0), .mutable = false }});
    const functions = try a.dupe(typed.Function, &.{
        .{ .scope = .{ .body_complete = true, .body = @fromBackingInt(0) }, .id = @fromBackingInt(0), .name = "main", .declaration = span },
        .{ .scope = .{ .body_complete = true, .body = @fromBackingInt(0), .locals = locals }, .signature = .{ .parameter_count = 1 }, .id = @fromBackingInt(1), .name = "use_a", .declaration = span },
        .{ .scope = .{ .body_complete = true, .body = @fromBackingInt(0) }, .signature = .{ .return_type = recordType(2) }, .id = @fromBackingInt(2), .name = "use_c", .declaration = span },
    });
    return .{ .nodes = body.nodes, .statements = body.statements, .functions = functions, .main = @fromBackingInt(0), .records = records };
}

fn reachOf(a: std.mem.Allocator, program: typed.Program, index: usize) !?[32]u8 {
    var reach = try lowering.OwnershipReach.init(a, program);
    return reach.digest(a, program.functions[index]);
}

test "G1c the reach of a function follows a cycle of records, sees a change anywhere in it, and sees nothing else" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try reachFixture(a);
    const main = (try reachOf(a, program, 0)).?;
    const use_a = (try reachOf(a, program, 1)).?;
    const use_c = (try reachOf(a, program, 2)).?;
    try std.testing.expect(!std.mem.eql(u8, &use_a, &use_c));
    // B is reached from A through the cycle: a field of B changes what use_a depends on, and nothing about use_c or main.
    @constCast(program.records[1].fields)[0].ty = .i64;
    try std.testing.expect(!std.mem.eql(u8, &use_a, &(try reachOf(a, program, 1)).?));
    try std.testing.expectEqual(use_c, (try reachOf(a, program, 2)).?);
    try std.testing.expectEqual(main, (try reachOf(a, program, 0)).?);
    @constCast(program.records[1].fields)[0].ty = recordType(0);
    try std.testing.expectEqual(use_a, (try reachOf(a, program, 1)).?);
    // C is reached only by use_c.
    @constCast(program.records[2].fields)[0].ty = .u8;
    try std.testing.expect(!std.mem.eql(u8, &use_c, &(try reachOf(a, program, 2)).?));
    try std.testing.expectEqual(use_a, (try reachOf(a, program, 1)).?);
    try std.testing.expectEqual(main, (try reachOf(a, program, 0)).?);
}

test "G1c the reach of a function does not depend on the order the functions are asked in, and a reference out of range has no reach" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try reachFixture(a);
    var forward = try lowering.OwnershipReach.init(a, program);
    var backward = try lowering.OwnershipReach.init(a, program);
    const first = [_]?[32]u8{ try forward.digest(a, program.functions[0]), try forward.digest(a, program.functions[1]), try forward.digest(a, program.functions[2]) };
    const second = [_]?[32]u8{ try backward.digest(a, program.functions[0]), try backward.digest(a, program.functions[1]), try backward.digest(a, program.functions[2]) };
    const reversed = [_]?[32]u8{ try backward.digest(a, program.functions[2]), try backward.digest(a, program.functions[1]), try backward.digest(a, program.functions[0]) };
    try std.testing.expectEqual(first, second);
    try std.testing.expectEqual(first[2], reversed[0]);
    try std.testing.expectEqual(first[0], reversed[2]);
    // A parameter of a record the program does not have: no digest, so the function is always checked; the others are unaffected.
    @constCast(program.functions[1].scope.locals)[0].ty = recordType(9);
    try std.testing.expectEqual(@as(?[32]u8, null), try reachOf(a, program, 1));
    try std.testing.expectEqual(first[2], try reachOf(a, program, 2));
}

test "O4 ownership digest sees own markers independently of source positions" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try digestChain(arena.allocator(), 3, false);
    const catalog = try lowering.Catalog.prepare(program);
    const before = try catalog.ownershipDigest(std.testing.allocator, program.functions[0]);
    @constCast(program.nodes)[0].own = true;
    const marked = try catalog.ownershipDigest(std.testing.allocator, program.functions[0]);
    try std.testing.expect(!std.mem.eql(u8, &before, &marked));
    @constCast(program.nodes)[0].span.end += 1;
    try std.testing.expectEqual(marked, try catalog.ownershipDigest(std.testing.allocator, program.functions[0]));
    @constCast(program.nodes)[0].own = false;
    try std.testing.expectEqual(before, try catalog.ownershipDigest(std.testing.allocator, program.functions[0]));
    @constCast(program.nodes)[0].type_dependent = true;
    const dependent = try catalog.ownershipDigest(std.testing.allocator, program.functions[0]);
    try std.testing.expect(!std.mem.eql(u8, &before, &dependent));
    try std.testing.expect(!std.mem.eql(u8, &marked, &dependent));
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership digest traverses deep left and right expressions without host recursion" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const left = try digestChain(a, 4096, false);
    const right = try digestChain(a, 4096, true);
    const lc = try lowering.Catalog.prepare(left);
    const rc = try lowering.Catalog.prepare(right);
    const ld = try lc.ownershipDigest(std.testing.allocator, left.functions[0]);
    const rd = try rc.ownershipDigest(std.testing.allocator, right.functions[0]);
    try std.testing.expect(!std.mem.eql(u8, &ld, &rd));
    @constCast(left.nodes)[0].data.integer += 1;
    const changed = try lc.ownershipDigest(std.testing.allocator, left.functions[0]);
    try std.testing.expect(!std.mem.eql(u8, &ld, &changed));
}

fn digestFailure(backing: std.mem.Allocator, program: typed.Program) !void {
    const catalog = try lowering.Catalog.prepare(program);
    _ = try catalog.ownershipDigest(backing, program.functions[0]);
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership digest releases iterative path storage on allocation failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try digestChain(arena.allocator(), 32, false);
    try std.testing.checkAllAllocationFailures(std.testing.allocator, digestFailure, .{program});
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership digest rejects invalid references and graph cycles while accepting shared children" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program = try digestChain(a, 3, false);
    const catalog = try lowering.Catalog.prepare(program);
    const nodes = @constCast(program.nodes);
    const last = nodes.len - 1;
    nodes[last].data.binary.right = nodes[last].data.binary.left;
    const shared = try catalog.ownershipDigest(std.testing.allocator, program.functions[0]);
    try std.testing.expect(!std.mem.eql(u8, &shared, &@as(stage.Digest, @splat(0))));
    nodes[last].data.binary.left = @fromBackingInt(@intCast(last));
    try std.testing.expectError(error.InvalidSnapshot, catalog.ownershipDigest(std.testing.allocator, program.functions[0]));
    nodes[last].data.binary.left = @fromBackingInt(@intCast(nodes.len));
    try std.testing.expectError(error.InvalidSnapshot, catalog.ownershipDigest(std.testing.allocator, program.functions[0]));
    const children = try a.dupe(typed.StatementId, &.{@fromBackingInt(@intCast(0))});
    @constCast(program.statements)[0].data = .{ .block = children };
    try std.testing.expectError(error.InvalidSnapshot, catalog.ownershipDigest(std.testing.allocator, program.functions[0]));
    @constCast(program.functions)[0].scope.body = @fromBackingInt(@intCast(program.statements.len));
    try std.testing.expectError(error.InvalidSnapshot, catalog.ownershipDigest(std.testing.allocator, program.functions[0]));
}

fn digestLoweringKey(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, program: typed.Program) !stage.Digest {
    var store = try stage.Store.init(backing, std.testing.io, root);
    defer store.deinit();
    var cache = lowering.Cache.init(&store);
    var module: @import("ir.zig").Module = .{};
    var discovery: lowering.Discovery = .{};
    var types: std.AutoHashMapUnmanaged(typed.Type, @import("ir.zig").Type) = .empty;
    const context: lowering.Context = .{ .arena = a, .input = .{ .program = program, .source = null, .drop_debug = false }, .module = &module, .discovery = &discovery, .types = &types };
    var session = try lowering.Session.prepare(&cache, context);
    return (try session.key(context, program.functions[0])).key;
}

test "O4 ownership and lowering keys distinguish owning RHS staging from reads" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var program = try digestChain(a, 0, false);
    const statements = try a.alloc(typed.Statement, 3);
    statements[0] = .{ .span = .{ .start = 0, .end = 1 }, .terminates = false, .data = .{ .initialize = .{ .slot = @fromBackingInt(0), .value = @fromBackingInt(0) } } };
    statements[1] = program.statements[0];
    statements[2] = .{ .span = .{ .start = 0, .end = 1 }, .terminates = true, .data = .{ .block = &.{ @fromBackingInt(0), @fromBackingInt(1) } } };
    program.statements = statements;
    const function = &@constCast(program.functions)[0];
    function.scope.body = @fromBackingInt(2);
    function.scope.locals = try a.dupe(typed.Local, &.{.{ .name = "temporary", .declaration = .{ .start = 0, .end = 1 }, .ty = .i64, .mutable = false, .usage = .{ .temporary = true } }});
    const catalog = try lowering.Catalog.prepare(program);
    const proof = try catalog.ownershipDigest(std.testing.allocator, function.*);
    const lowered = try digestLoweringKey(a, std.testing.allocator, root, program);
    statements[0].data.initialize.transfer = true;
    try std.testing.expect(!std.mem.eql(u8, &proof, &try catalog.ownershipDigest(std.testing.allocator, function.*)));
    try std.testing.expect(!std.mem.eql(u8, &lowered, &try digestLoweringKey(a, std.testing.allocator, root, program)));
    statements[0].data.initialize.transfer = false;
    try std.testing.expectEqual(proof, try catalog.ownershipDigest(std.testing.allocator, function.*));
    try std.testing.expectEqual(lowered, try digestLoweringKey(a, std.testing.allocator, root, program));
}

// spec-case: NEW-CORE-STAGE-CACHE-1
test "W07 lowering body keys traverse deep typed expressions and retain span and own sensitivity" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const program = try digestChain(a, 4096, true);
    const first = try digestLoweringKey(a, std.testing.allocator, root, program);
    @constCast(program.nodes)[0].span.end += 1;
    const second = try digestLoweringKey(a, std.testing.allocator, root, program);
    try std.testing.expect(!std.mem.eql(u8, &first, &second));
    @constCast(program.nodes)[0].own = true;
    const marked = try digestLoweringKey(a, std.testing.allocator, root, program);
    try std.testing.expect(!std.mem.eql(u8, &second, &marked));
    @constCast(program.nodes)[0].type_dependent = true;
    const dependent = try digestLoweringKey(a, std.testing.allocator, root, program);
    try std.testing.expect(!std.mem.eql(u8, &marked, &dependent));
}

fn admitAllocationBody(_: *const anyopaque, _: []const u8, _: stage.Digest, _: stage.Digest) bool {
    return true;
}

fn allocationBuild(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, cached: bool) !Outcome {
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    if (cached) try session.enableCache(backing, try std.fs.path.join(a, &.{ root, "cache" }));
    const context: u8 = 0;
    // Even an admitted lowering artifact cannot hide an allocation contract.
    session.configureDemand(.{ .context = &context, .allow = admitAllocationBody, .body_dependencies = false, .facts_unread = true });
    var messages: std.ArrayList(u8) = .empty;
    const valid = if (session.check(a, "main", &messages)) |_| true else |err| switch (err) {
        error.SourceError => false,
        else => return err,
    };
    return .{ .valid = valid, .work = session.statistics(), .ownership = session.ownershipWork(), .diagnostics = messages.items };
}

// spec-case: FRONTEND-CORE-NOALLOC-1
// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "W07 ownership validation omits bounded bodies while lowering preserves allocation checks" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source =
        \\func helper(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return True
        \\@noalloc
        \\func bounded(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return helper(values, key)
        \\func main() -> int:
        \\    return 0
    ;
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source });
    try std.testing.expect((try check(a, std.testing.allocator, root, true)).valid);
    const warm = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(warm.valid);
    try std.testing.expectEqual(@as(usize, 2), warm.work.summaries);
    try std.testing.expectEqual(@as(usize, 0), warm.work.checked);
    try std.testing.expectEqual(@as(usize, 3), warm.work.reused);
    try std.testing.expectEqual(@as(usize, 3), warm.ownership.reused);
    try std.testing.expect((try allocationBuild(a, std.testing.allocator, root, true)).valid);
    const changed = try std.mem.replaceOwned(u8, a, source, "return True", "return key in values");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = changed });
    const validation = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(validation.valid);
    try std.testing.expectEqual(@as(usize, 0), validation.diagnostics.len);
    const fresh_validation = try check(a, std.testing.allocator, root, false);
    try std.testing.expect(fresh_validation.valid);
    try std.testing.expectEqualStrings(fresh_validation.diagnostics, validation.diagnostics);
    const fresh = try allocationBuild(a, std.testing.allocator, root, false);
    try std.testing.expect(!fresh.valid);
    try std.testing.expect(std.mem.indexOf(u8, fresh.diagnostics, "E_NOALLOC_ALLOCATES") != null);
    for (0..2) |_| {
        const cached = try allocationBuild(a, std.testing.allocator, root, true);
        try std.testing.expect(!cached.valid);
        try std.testing.expectEqualStrings(fresh.diagnostics, cached.diagnostics);
    }
}

// spec-case: FRONTEND-CORE-NOALLOC-1
test "F35 a build's allocation contract follows a promise through bodies it did not change, and a callee two calls down starting to allocate is found" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source =
        \\func leaf(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return True
        \\func middle(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return leaf(values, key)
        \\@noalloc
        \\func bounded(values: dict[FixedArray[Unit, 2], int], key: FixedArray[Unit, 2]) -> bool:
        \\    return middle(values, key)
        \\func other() -> int:
        \\    return 1
        \\func main() -> int:
        \\    return other()
    ;
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = source });
    try std.testing.expect((try allocationBuild(a, std.testing.allocator, root, true)).valid);
    const warm = try allocationBuild(a, std.testing.allocator, root, true);
    try std.testing.expect(warm.valid);
    // The promise holds while an unrelated function changes: nothing of the promise's callees is checked again.
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = try std.mem.replaceOwned(u8, a, source, "    return 1", "    return 2") });
    const unrelated = try allocationBuild(a, std.testing.allocator, root, true);
    try std.testing.expect(unrelated.valid);
    // `leaf`, two calls below the promise and not the promise's caller's concern, starts to allocate: the cached build says what a fresh one says.
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = try std.mem.replaceOwned(u8, a, source, "    return True", "    return key in values") });
    const fresh = try allocationBuild(a, std.testing.allocator, root, false);
    try std.testing.expect(!fresh.valid);
    try std.testing.expect(std.mem.indexOf(u8, fresh.diagnostics, "E_NOALLOC_ALLOCATES") != null);
    for (0..2) |_| {
        const cached = try allocationBuild(a, std.testing.allocator, root, true);
        try std.testing.expect(!cached.valid);
        try std.testing.expectEqualStrings(fresh.diagnostics, cached.diagnostics);
    }
}

// spec-case: NEW-CORE-ZERO-RC-CACHE-1
test "F35 a callee body edit that moves what it does with its arguments leaves its caller's ownership results as a fresh build reports them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const callee_source =
        \\public func head(items: int[]) -> int[] from items:
        \\    return items[0:1]
        \\
        \\
        \\public func take(own items: int[]) -> int:
        \\    return len(items)
        \\
        \\
        \\public func grow(mut items: int[]) -> int:
        \\    return len(items)
        \\
    ;
    const caller_source =
        \\import lib
        \\
        \\
        \\func use() -> int:
        \\    mut xs: int[] = [1, 2]
        \\    const h = lib.head(xs)
        \\    const seen = len(h)
        \\    append(mut xs, 3)
        \\    mut ys: int[] = [4]
        \\    const moved = lib.take(own ys)
        \\    mut zs: int[] = [5]
        \\    return seen + moved + lib.grow(mut zs)
        \\
        \\
        \\func main() -> int:
        \\    return use()
        \\
    ;
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = caller_source });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = callee_source });
    try std.testing.expect((try allocationBuild(a, std.testing.allocator, root, true)).valid);
    const warm = try allocationBuild(a, std.testing.allocator, root, true);
    try std.testing.expect(warm.valid);
    // Each callee body now does something else with its argument: the accessor copies instead of borrowing, the consumer reads only
    // part of what it was given, the mutator stops writing. The caller's trees stay out, and what is reported is what a fresh build reports.
    const edits = [_][2][]const u8{
        .{ "    return items[0:1]", "    return copy(items[0:1])" },
        .{ "    return len(items)\n\n\npublic func grow", "    return len(items) + items[0]\n\n\npublic func grow" },
        .{ "public func grow(mut items: int[]) -> int:\n    return len(items)", "public func grow(mut items: int[]) -> int:\n    append(mut items, 1)\n    return len(items)" },
    };
    for (edits) |edit| {
        try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = try std.mem.replaceOwned(u8, a, callee_source, edit[0], edit[1]) });
        const fresh = try allocationBuild(a, std.testing.allocator, root, false);
        const cached = try allocationBuild(a, std.testing.allocator, root, true);
        try std.testing.expectEqual(fresh.valid, cached.valid);
        try std.testing.expectEqualStrings(fresh.diagnostics, cached.diagnostics);
        try std.testing.expect(cached.work.checked < 3);
        try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = callee_source });
        _ = try allocationBuild(a, std.testing.allocator, root, true);
    }
}

/// `check`, with verify mode checking one proven function in `every` anyway (1: every one).
fn checkVerifying(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, every: u32) !Outcome {
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    try session.enableCache(backing, try std.fs.path.join(a, &.{ root, "cache" }));
    session.caches.ownership.?.policy.verify_every = every;
    session.validationOnly();
    var messages: std.ArrayList(u8) = .empty;
    const valid = if (session.check(a, "main", &messages)) |_| true else |err| switch (err) {
        error.SourceError => false,
        else => return err,
    };
    return .{ .valid = valid, .work = session.statistics(), .ownership = session.ownershipWork(), .diagnostics = messages.items };
}

test "G1c an edit and its revert: the proofs of the first state are still held, not flipped away by the second" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = generic_entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = generic_library });
    const cold = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(cold.valid);
    try std.testing.expectEqual(@as(usize, 9), cold.ownership.checked);
    // The generic body changes: its four instances (two the program makes, two that judge it at its declaration) are proven
    // under other digests, and nothing else is checked.
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = try std.mem.replaceOwned(u8, a, generic_library, "return 0", "return 2") });
    const edited = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(edited.valid);
    try std.testing.expectEqual(@as(usize, 4), edited.ownership.checked);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = generic_library });
    const reverted = try check(a, std.testing.allocator, root, true);
    try std.testing.expect(reverted.valid);
    try std.testing.expectEqual(@as(usize, 0), reverted.ownership.checked);
    try std.testing.expectEqual(@as(usize, 5), reverted.ownership.reused);
}

test "G1c verify mode checks a proven function anyway, and a run without it omits the check" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = generic_entry });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = generic_library });
    const cold = try checkVerifying(a, std.testing.allocator, root, 0);
    try std.testing.expect(cold.valid);
    try std.testing.expectEqual(@as(usize, 9), cold.ownership.checked);
    const omitted = try checkVerifying(a, std.testing.allocator, root, 0);
    try std.testing.expectEqual(@as(usize, 0), omitted.ownership.checked);
    try std.testing.expectEqual(@as(usize, 5), omitted.ownership.reused);
    const verified = try checkVerifying(a, std.testing.allocator, root, 1);
    try std.testing.expect(verified.valid);
    try std.testing.expectEqual(@as(usize, 9), verified.ownership.checked);
    try std.testing.expectEqual(@as(usize, 0), verified.ownership.reused);
}
