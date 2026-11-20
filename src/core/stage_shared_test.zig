//! The shared stage tier: two work directories on one shared root (routing, equal publications, mismatches, the legacy
//! private read) and the scope table's coverage of every scope literal in `src/core`.
const std = @import("std");
const stage = @import("stage_store.zig");
const scopes = @import("stage_scopes.zig");
const optimization_cache = @import("optimization_cache.zig");
const test_paths = @import("core_test_options");
const policy = @import("selka").shared_cache_policy;

const io = std.testing.io;
const shared_scope = "lowering-receipt-v7";
const private_scope = "optimizer-shortcut-v2";
const pure_scope = "llvm-unit-v1";

/// Two directories beside each other: `one` and `two` are work directories, `shared` the shared root.
const Fixture = struct {
    gpa: std.mem.Allocator,
    directory: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init(gpa: std.mem.Allocator) Fixture {
        return .{ .gpa = gpa, .directory = std.testing.tmpDir(.{}), .arena = std.heap.ArenaAllocator.init(gpa) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.directory.cleanup();
    }

    /// The absolute path of `name` under the fixture directory.
    fn path(self: *Fixture, name: []const u8) ![]const u8 {
        const root = try self.directory.dir.realPathFileAlloc(io, ".", self.arena.allocator());
        return std.fs.path.join(self.arena.allocator(), &.{ root, name });
    }

    /// A store whose work directory is `work`, sharing the fixture's shared root when `shared` is set.
    fn open(self: *Fixture, work: []const u8, shared: bool, publish: bool) !stage.Store {
        const cache = try self.path(work);
        const shared_root: ?[]const u8 = if (shared) try self.path("shared") else null;
        return stage.Store.initWithOptions(self.gpa, io, cache, .{ .shared = shared_root, .publish = publish });
    }

    /// The shared store's packs state, which counts the publications made through it.
    fn sharedStatistics(store: *const stage.Store) @import("stage_pack.zig").Publication {
        return store.shared.?.state.statistics().publication;
    }

    /// The shared store's check counts (`Checks`).
    fn sharedChecks(store: *const stage.Store) @import("stage_pack.zig").Checks {
        return store.shared.?.state.checks;
    }
};

test "a shared record published by one work directory loads in another, and an equal publication writes nothing" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key(shared_scope, &.{"parts"});
    try std.testing.expect(try one.save(digest, "payload"));
    try std.testing.expect(try one.flush());
    var two = try fixture.open("two", true, true);
    defer two.deinit();
    const again = two.key(shared_scope, &.{"parts"});
    try std.testing.expectEqualSlices(u8, &digest, &again);
    const loaded = (try two.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("payload", loaded);
    const written = Fixture.sharedStatistics(&two).records_saved;
    try std.testing.expect(try two.save(digest, "payload"));
    try std.testing.expect(try two.flush());
    try std.testing.expectEqual(written, Fixture.sharedStatistics(&two).records_saved);
    try std.testing.expectEqual(@as(u64, 1), Fixture.sharedChecks(&two).present);
}

test "a lowering receipt under one key takes its newer value, since it is validated against its proofs on every use" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key(shared_scope, &.{"receipt"});
    try std.testing.expect(try one.save(digest, "older proofs"));
    try std.testing.expect(try one.flush());
    var two = try fixture.open("two", true, true);
    defer two.deinit();
    _ = two.key(shared_scope, &.{"receipt"});
    try std.testing.expect(try two.save(digest, "newer proofs"));
    try std.testing.expect(try two.flush());
    try std.testing.expectEqual(@as(u64, 0), Fixture.sharedChecks(&two).mismatches);
    var three = try fixture.open("three", true, false);
    defer three.deinit();
    _ = three.key(shared_scope, &.{"receipt"});
    const loaded = (try three.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("newer proofs", loaded);
}

test "a shared record is found by a digest the reading store did not compute, as a stored record names it" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key(shared_scope, &.{"named"});
    try std.testing.expect(try one.save(digest, "named payload"));
    try std.testing.expect(try one.flush());
    var two = try fixture.open("two", true, false);
    defer two.deinit();
    try std.testing.expect(try two.contains(digest));
    const loaded = (try two.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("named payload", loaded);
    const absent = two.key(shared_scope, &.{"never saved"});
    try std.testing.expect(!(try two.contains(absent)));
}

test "a different payload under one pure shared key keeps the first record and logs one mismatch" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key(pure_scope, &.{"contested"});
    try std.testing.expect(try one.save(digest, "first"));
    try std.testing.expect(try one.flush());
    var two = try fixture.open("two", true, true);
    defer two.deinit();
    _ = two.key(pure_scope, &.{"contested"});
    try std.testing.expect(try two.save(digest, "second"));
    try std.testing.expect(try two.flush());
    try std.testing.expectEqual(@as(u64, 1), Fixture.sharedChecks(&two).mismatches);
    const loaded = (try two.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("first", loaded);
    const log = try std.Io.Dir.cwd().readFileAlloc(io, try fixture.path("shared/stage-artifacts-v1/mismatches.log"), std.testing.allocator, .limited(4096));
    defer std.testing.allocator.free(log);
    try std.testing.expect(std.mem.startsWith(u8, log, "mismatch stage "));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, log, "\n"));
}

test "F54 an artifact the shared store refused is kept in the work directory and read from there first; the shared record stays for the others" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key("lowered-function-v16", &.{"function"});
    const header = one.key("lowered-header-source-v10", &.{"function"});
    try std.testing.expect(try one.save(digest, "artifact of the first order"));
    try std.testing.expect(try one.flush());
    var two = try fixture.open("two", true, true);
    defer two.deinit();
    try std.testing.expectEqualSlices(u8, &digest, &two.key("lowered-function-v16", &.{"function"}));
    _ = two.key("lowered-header-source-v10", &.{"function"});
    // The second build lowered the function in another order: the shared store keeps the first writer's artifact (one mismatch,
    // logged), and the second keeps its own, in its work directory, for its own reads. A batch with a header that agrees is no mismatch.
    try std.testing.expect(try one.save(header, "header"));
    try std.testing.expect(try one.flush());
    try std.testing.expect(try two.saveAll(&.{ .{ .key = digest, .payload = "artifact of the second order" }, .{ .key = header, .payload = "header" } }));
    try std.testing.expect(try two.flush());
    try std.testing.expectEqual(@as(u64, 1), Fixture.sharedChecks(&two).mismatches);
    // A record whose build keeps its own copy is not a determinism bug: the mismatch log, which names those, stays empty.
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().access(io, try fixture.path("shared/stage-artifacts-v1/mismatches.log"), .{}));
    const own = (try two.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(own);
    try std.testing.expectEqualStrings("artifact of the second order", own);
    const first = (try one.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("artifact of the first order", first);
    // A third build with no artifact of its own reads the shared one.
    var three = try fixture.open("three", true, true);
    defer three.deinit();
    _ = three.key("lowered-function-v16", &.{"function"});
    const shared = (try three.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(shared);
    try std.testing.expectEqualStrings("artifact of the first order", shared);
    // The single-record path keeps back as well.
    try std.testing.expect(try three.save(digest, "artifact of the third order"));
    const third = (try three.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(third);
    try std.testing.expectEqualStrings("artifact of the third order", third);
}

test "F54 a scope whose record is the same bytes under its key keeps nothing back when the shared store refuses it" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key(pure_scope, &.{"pure"});
    try std.testing.expect(try one.save(digest, "first"));
    try std.testing.expect(try one.flush());
    var two = try fixture.open("two", true, true);
    defer two.deinit();
    _ = two.key(pure_scope, &.{"pure"});
    try std.testing.expect(try two.saveAll(&.{.{ .key = digest, .payload = "second" }}));
    try std.testing.expect(try two.flush());
    try std.testing.expect(!try two.storage.holds(digest));
    const loaded = (try two.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("first", loaded);
}

test "a private scope never reaches the shared store, and a shared scope saved without a shared root stays readable" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var legacy = try fixture.open("work", false, true);
    defer legacy.deinit();
    const moved = legacy.key(shared_scope, &.{"legacy"});
    try std.testing.expect(try legacy.save(moved, "older"));
    try std.testing.expect(try legacy.flush());
    var shared = try fixture.open("work", true, true);
    defer shared.deinit();
    const found = (try shared.load(std.testing.allocator, moved)).?;
    defer std.testing.allocator.free(found);
    try std.testing.expectEqualStrings("older", found);
    const private = shared.key(private_scope, &.{"local"});
    try std.testing.expect(try shared.save(private, "private"));
    try std.testing.expect(try shared.flush());
    try std.testing.expect(!(try shared.shared.?.state.contains(private)));
    try std.testing.expect(try shared.contains(private));
}

test "a read-only store loads the shared records and publishes nothing to them" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    var one = try fixture.open("one", true, true);
    defer one.deinit();
    const digest = one.key(shared_scope, &.{"read-only"});
    try std.testing.expect(try one.save(digest, "stored"));
    try std.testing.expect(try one.flush());
    var reader = try fixture.open("reader", true, false);
    defer reader.deinit();
    _ = reader.key(shared_scope, &.{"read-only"});
    const loaded = (try reader.load(std.testing.allocator, digest)).?;
    defer std.testing.allocator.free(loaded);
    try std.testing.expectEqualStrings("stored", loaded);
    const fresh = reader.key(shared_scope, &.{"read-only-new"});
    try std.testing.expect(try reader.save(fresh, "private-only"));
    try std.testing.expect(try reader.flush());
    try std.testing.expect(!(try one.shared.?.state.contains(fresh)));
    try std.testing.expect(try reader.storage.contains(fresh));
}

/// The number of scope literals of the non-test sources under `src/core` that the table does not list, and how many
/// literals it checked. A literal is a `key(`, `keyAt(`, `readKey(` or `writeKey(` first argument, or a `scope =` value.
fn unlistedScopes(a: std.mem.Allocator) !struct { checked: usize, unlisted: usize } {
    var directory = try std.Io.Dir.cwd().openDir(io, "src/core", .{ .iterate = true });
    defer directory.close(io);
    var checked: usize = 0;
    var unlisted: usize = 0;
    var entries = directory.iterate();
    while (try entries.next(io)) |entry| {
        if (!std.mem.endsWith(u8, entry.name, ".zig") or std.mem.endsWith(u8, entry.name, "_test.zig")) continue;
        const text = try directory.readFileAlloc(io, entry.name, a, .limited(1 << 22));
        for (markers) |marker| {
            var at: usize = 0;
            while (std.mem.indexOfPos(u8, text, at, marker)) |found| {
                const start = found + marker.len;
                const end = std.mem.indexOfScalarPos(u8, text, start, '"') orelse break;
                const literal = text[start..end];
                at = end + 1;
                if (literal.len == 0 or std.mem.indexOfAny(u8, literal, " \n") != null) continue;
                checked += 1;
                if (scopes.table.get(literal) == null) unlisted += 1;
            }
        }
    }
    return .{ .checked = checked, .unlisted = unlisted };
}

const markers = [_][]const u8{ "key(\"", "keyAt(\"", "readKey(\"", "writeKey(\"", "_scope = \"" };

test "every scope literal of the production sources under src/core is listed in the route table" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const result = try unlistedScopes(arena.allocator());
    try std.testing.expect(result.checked >= 30);
    try std.testing.expectEqual(@as(usize, 0), result.unlisted);
}

/// The number of optimizer stage names (`optimization_cache.Stage`) the route table does not list.
fn unlistedStages() usize {
    var unlisted: usize = 0;
    for (std.enums.values(optimization_cache.Stage)) |stage_name| {
        if (scopes.table.get(@tagName(stage_name)) == null) unlisted += 1;
    }
    return unlisted;
}

test "a native receipt is shared, and a missing unit object behind it rebuilds the unit (stage_receipt_test.zig)" {
    try std.testing.expectEqual(scopes.Route.shared, scopes.routeOf("native-unit-receipt-v1"));
}

test "the key of the assembly record is a private scope, listed so that no work directory shares its file" {
    try std.testing.expectEqual(scopes.Route.private, scopes.routeOf("lowering-assembly-v1"));
    try std.testing.expect(scopes.table.has("lowering-assembly-v1"));
}

test "every optimizer stage name is listed in the route table" {
    try std.testing.expectEqual(@as(usize, 0), unlistedStages());
    try std.testing.expect(scopes.table.get("final") != null);
}

test "an unusable shared directory keeps the store private, and an out-of-memory open is an error" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.directory.dir.writeFile(io, .{ .sub_path = "blocked", .data = "a file where the directory belongs" });
    const shared_root = try fixture.path("blocked");
    try std.testing.expect((try stage.Store.openShared(std.testing.allocator, io, shared_root, @splat(0), .{ .shared = shared_root })) == null);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, stage.Store.openShared(failing.allocator(), io, try fixture.path("shared"), @splat(0), .{ .shared = "unused" }));
}

test "every stage-table scope is in the route table, and the stage of a scope is what its table entry says" {
    for (scopes.stage_scope_names) |scope| {
        try std.testing.expect(scopes.table.get(scope) != null);
    }
    try std.testing.expectEqual(scopes.Stage.lower, scopes.stageOf("lowered-function-v15"));
    try std.testing.expectEqual(scopes.Stage.opt, scopes.stageOf("optimizer-chunk-v3"));
    try std.testing.expectEqual(scopes.Stage.emit, scopes.stageOf("llvm-unit-v1"));
    try std.testing.expectEqual(scopes.Stage.whole, scopes.stageOf("a-scope-nobody-listed"));
    try std.testing.expectEqual(scopes.Stage.test_runner, scopes.stageOf("core-test-function-facts-v3"));
    try std.testing.expectEqual(scopes.Stage.test_runner, scopes.stageOf("test-graph-head-v1"));
    try std.testing.expectEqual(scopes.Stage.test_runner, scopes.stageOf("test-graph-nodes-v1"));
    try std.testing.expectEqual(scopes.Stage.test_runner, scopes.stageOf("test-graph-tests-v1"));
    try std.testing.expectEqual(scopes.Stage.test_runner, scopes.stageOf("test-graph-indexes-v1"));
    try std.testing.expectEqual(scopes.Stage.whole, scopes.stageOf("llvm-test"));
}

/// Open a store on a fresh work directory of `fixture` with the given stage identities (null: the build's own).
fn openWithStages(fixture: *Fixture, work: []const u8, identities: ?stage.StageDigests) !stage.Store {
    const cache = try fixture.path(work);
    return stage.Store.initWithOptions(fixture.gpa, io, cache, .{ .identities = identities });
}

/// How many scope and stage pairs break the key rule: a scope's key must move when its own stage's identity changes,
/// and stay put when any other stage's identity changes; and a part change must move every scope's key.
fn keyRuleViolations(gpa: std.mem.Allocator) !usize {
    var fixture = Fixture.init(gpa);
    defer fixture.deinit();
    var base = try openWithStages(&fixture, "base", null);
    defer base.deinit();
    var violations: usize = 0;
    for (scopes.stage_scope_names) |scope| {
        const first = base.key(scope, &.{"a"});
        const second = base.key(scope, &.{"b"});
        if (std.mem.eql(u8, &first, &second)) violations += 1;
    }
    for (0..scopes.stage_count) |which| {
        var changed = stage.defaultStageDigests();
        changed[which][0] ^= 0xff;
        const work = try std.fmt.allocPrint(fixture.arena.allocator(), "stage-{d}", .{which});
        var other = try openWithStages(&fixture, work, changed);
        defer other.deinit();
        for (scopes.stage_scope_names) |scope| {
            const moved = !std.mem.eql(u8, &base.key(scope, &.{"a"}), &other.key(scope, &.{"a"}));
            const own = @as(usize, @backingInt(scopes.stageOf(scope))) == which;
            if (moved != own) violations += 1;
        }
    }
    return violations;
}

test "every stage-scoped key moves with its own stage's identity, with no other stage's, and with each part" {
    try std.testing.expectEqual(@as(usize, 0), try keyRuleViolations(std.testing.allocator));
}

/// The stage-scoped scopes plus one unlisted scope, which every key routes to the `whole` stage.
const probe_scopes = scopes.stage_scope_names ++ [_][]const u8{"unlisted-probe-scope"};

/// Records one build served (`served`) out of the records of its stage (`total`).
const Tally = struct { served: usize = 0, total: usize = 0 };

/// `before` after a back-end-only edit: the optimizer's identity moves, the emitter's moves with it (its identity chains
/// from the optimizer's), and so does the whole compiler's. The front, lower and test-runner identities do not move.
fn editedBackEnd(before: stage.StageDigests) stage.StageDigests {
    var after = before;
    after[@backingInt(scopes.Stage.opt)] = digestOf("optimizer identity after the edit");
    after[@backingInt(scopes.Stage.emit)] = digestOf("emitter identity chained after the optimizer edit");
    after[@backingInt(scopes.Stage.whole)] = digestOf("whole compiler identity after the edit");
    return after;
}

fn digestOf(text: []const u8) stage.Digest {
    var out: stage.Digest = undefined;
    std.crypto.hash.sha2.Sha256.hash(text, &out, .{});
    return out;
}

/// Save one record per probe scope in the work directory `work`, keyed under `identities`, and publish it.
fn writeRecords(fixture: *Fixture, work: []const u8, identities: stage.StageDigests) !void {
    var store = try openWithStages(fixture, work, identities);
    defer store.deinit();
    for (probe_scopes) |scope| _ = try store.save(store.key(scope, &.{"record"}), scope);
    try std.testing.expect(try store.flush());
}

/// What a build with `identities` finds in `work`: per stage, how many of its probe records are still served.
fn servedByStage(fixture: *Fixture, work: []const u8, identities: stage.StageDigests) ![scopes.stage_count]Tally {
    var store = try openWithStages(fixture, work, identities);
    defer store.deinit();
    var tally: [scopes.stage_count]Tally = undefined;
    @memset(&tally, Tally{});
    for (probe_scopes) |scope| {
        const index = @backingInt(scopes.stageOf(scope));
        tally[index].total += 1;
        if (try store.load(fixture.arena.allocator(), store.key(scope, &.{"record"})) != null) tally[index].served += 1;
    }
    return tally;
}

/// Whether every probe record is served (a stage with no probe records, `front` here, counts as served).
fn allServed(tally: [scopes.stage_count]Tally) bool {
    var served = true;
    for (tally) |item| served = served and item.served == item.total;
    return served;
}

test "a back-end-only edit keeps the lower records warm and sends the optimizer, emitter and whole records cold" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const before = stage.defaultStageDigests();
    const after = editedBackEnd(before);
    try writeRecords(&fixture, "work", before);
    const front = @backingInt(scopes.Stage.front);
    const lower = @backingInt(scopes.Stage.lower);
    const opt = @backingInt(scopes.Stage.opt);
    const emit = @backingInt(scopes.Stage.emit);
    const whole = @backingInt(scopes.Stage.whole);
    const runner = @backingInt(scopes.Stage.test_runner);
    // Control: the build that wrote the records finds every one of them.
    const control = try servedByStage(&fixture, "work", before);
    try std.testing.expect(allServed(control));
    try std.testing.expect(control[lower].total != 0 and control[opt].total != 0 and control[emit].total != 0 and control[whole].total != 0);
    const warm = try servedByStage(&fixture, "work", after);
    try std.testing.expectEqualSlices(u8, &before[front], &after[front]);
    try std.testing.expect(warm[lower].total != 0);
    try std.testing.expectEqual(warm[lower].total, warm[lower].served);
    try std.testing.expectEqual(@as(usize, 0), warm[opt].served);
    try std.testing.expectEqual(@as(usize, 0), warm[emit].served);
    try std.testing.expectEqual(@as(usize, 0), warm[whole].served);
    try std.testing.expect(warm[opt].total != 0 and warm[emit].total != 0 and warm[whole].total != 0);
    // The test-runner stage chains from `lower`, not from the emitter, so an emitter edit keeps its records warm.
    try std.testing.expect(warm[runner].total != 0);
    try std.testing.expectEqual(warm[runner].total, warm[runner].served);
}

test "F54 the environment a test builds for a compiler child disables every shared store, the stage store included, whatever the home holds" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment = try test_paths.privateEnvironment(a);
    try environment.put("HOME", "/home/user");
    try environment.put("XDG_CACHE_HOME", "/xdg");
    try std.testing.expectEqual(@as(?policy.Selection, null), try policy.resolve(a, &environment, .stages, null));
    try std.testing.expectEqual(@as(?policy.Selection, null), try policy.resolve(a, &environment, .compiler, null));
    try std.testing.expectEqual(@as(?policy.Selection, null), try policy.resolve(a, &environment, .tests, null));
    // Without the helper the per-user directory would be selected, which is what a test that ran a compiler unprepared would reach.
    var bare: std.process.Environ.Map = .init(a);
    try bare.put("HOME", "/home/user");
    try std.testing.expect((try policy.resolve(a, &bare, .stages, null)) != null);
}

/// Save one record per probe scope through a store on work directory `work` that publishes to the fixture's shared root,
/// keyed under `identities`.
fn publishRecords(fixture: *Fixture, work: []const u8, identities: stage.StageDigests) !void {
    const cache = try fixture.path(work);
    var store = try stage.Store.initWithOptions(fixture.gpa, io, cache, .{ .shared = try fixture.path("shared"), .publish = true, .identities = identities });
    defer store.deinit();
    for (probe_scopes) |scope| _ = try store.save(store.key(scope, &.{"record"}), scope);
    try std.testing.expect(try store.flush());
}

/// How many of the shared probe records of the `opt` stage a store with `identities` on a fresh work directory `work` finds,
/// through the shared root only.
fn optServedFromShared(fixture: *Fixture, work: []const u8, identities: stage.StageDigests) !Tally {
    const cache = try fixture.path(work);
    var store = try stage.Store.initWithOptions(fixture.gpa, io, cache, .{ .shared = try fixture.path("shared"), .publish = false, .identities = identities });
    defer store.deinit();
    var tally: Tally = .{};
    for (probe_scopes) |scope| {
        if (scopes.stageOf(scope) != .opt or scopes.routeOf(scope) != .shared) continue;
        tally.total += 1;
        if (try store.load(fixture.arena.allocator(), store.key(scope, &.{"record"})) != null) tally.served += 1;
    }
    return tally;
}

// Lane VAL, phase 2: the ownership certificate's format (`ownership_export.magic`, now v2) and the validator are in the `opt`
// stage's source closure (the test of the optimizer stage's identity in `build_identity_rules_test.zig`), so two compilers
// on either side of the format change have different `opt` identities. Sharing one per-user stage store, each finds the
// other's optimizer records as misses, never as errors, in both directions, and still finds its own.
test "two compilers on either side of the certificate format change miss each other's optimizer records, both ways" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const v2 = stage.defaultStageDigests();
    const v1 = editedBackEnd(v2);
    try publishRecords(&fixture, "new", v2);
    try publishRecords(&fixture, "old", v1);
    const new_reads_old = try optServedFromShared(&fixture, "new-reader", v2);
    const old_reads_new = try optServedFromShared(&fixture, "old-reader", v1);
    try std.testing.expect(new_reads_old.total != 0);
    // Each finds its own records (the ones it published) and none of the other's: one record per scope per compiler.
    try std.testing.expectEqual(new_reads_old.total, new_reads_old.served);
    try std.testing.expectEqual(old_reads_new.total, old_reads_new.served);
    // A store that only the other compiler published to: everything is a miss, and no load fails.
    var lone = Fixture.init(std.testing.allocator);
    defer lone.deinit();
    try publishRecords(&lone, "old", v1);
    try std.testing.expectEqual(@as(usize, 0), (try optServedFromShared(&lone, "new-reader", v2)).served);
    var other = Fixture.init(std.testing.allocator);
    defer other.deinit();
    try publishRecords(&other, "new", v2);
    try std.testing.expectEqual(@as(usize, 0), (try optServedFromShared(&other, "old-reader", v1)).served);
}
