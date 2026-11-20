//! The shared tier (C2e1): what one tree publishes another is served, a shared record is validated by its reads like a
//! local one, a record that disagrees about a result is kept and counted, and a damaged one is a miss.
const std = @import("std");
const fixture_rules = @import("fixture_test.zig");
const script = @import("kinds/script.zig");
const compiler_records = @import("compiler_records.zig");
const digest_rules = @import("digest.zig");
const record_rules = @import("record.zig");
const shared_records = @import("shared_records.zig");
const shared_tier = @import("shared_tier.zig");
const store_rules = @import("store.zig");
const Fixture = fixture_rules.Fixture;

const second = std.time.ns_per_s;
const one_file: script.Graph = .{ .nodes = &.{fixture_rules.fileNode("/src/a.txt", .concat)} };

/// A shared tier in a temporary directory, heap-allocated so the engines may point into it.
const Shared = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    records: shared_records.Records,
    root: []const u8,

    fn create(gpa: std.mem.Allocator) !*Shared {
        const self = try gpa.create(Shared);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        self.root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        self.records = try shared_records.Records.open(a, std.testing.io, self.root);
        return self;
    }

    fn tier(self: *Shared) shared_tier.Tier {
        return self.records.tier();
    }

    fn destroy(self: *Shared) void {
        self.arena.deinit();
        self.temporary.cleanup();
        self.gpa.destroy(self);
    }
};

/// A tree: a fixture whose file `/src/a.txt` holds `text`, aged past the racy window, with the shared tier on.
fn tree(gpa: std.mem.Allocator, shared: *Shared, text: []const u8) !*Fixture {
    const fx = try Fixture.create(gpa, one_file);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", text);
    fx.files.advance(second);
    try fx.restart(.{ .shared = shared.tier() });
    return fx;
}

test "shared tier: a second tree is served from the shared tier what the first computed" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    const second_tree = try tree(std.testing.allocator, shared, "alpha");
    defer second_tree.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.shared_published));
    try std.testing.expectEqualStrings("alpha", try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.shared_hits));
    // The adopted record is local now: an engine without the tier finds it in the second tree's work directory.
    try second_tree.restart(.{});
    try std.testing.expectEqualStrings("alpha", try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.shared_hits));
}

test "shared tier: a record served to a tree whose file has another tuple is adopted once, with that tree's tuple" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    const second_tree = try tree(std.testing.allocator, shared, "alpha");
    defer second_tree.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    // The second tree's file holds the same bytes under a new tuple: serving the shared record refreshes the tuple of the local copy.
    try second_tree.files.write("/src/a.txt", "alpha");
    second_tree.files.advance(second);
    try second_tree.restart(.{ .shared = shared.tier() });
    try std.testing.expectEqualStrings("alpha", try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.refreshed));
    // The copy kept the refreshed tuple (the adoption did not write the other tree's bytes over it): the next process hashes nothing.
    try second_tree.restart(.{});
    try std.testing.expectEqualStrings("alpha", try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.refreshed));
}

test "shared tier: a tree whose file differs is not served another's record; it publishes its own variant, and a third tree with that file is served it" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    const other = try tree(std.testing.allocator, shared, "beta");
    defer other.destroy();
    const third = try tree(std.testing.allocator, shared, "beta");
    defer third.destroy();
    const fourth = try tree(std.testing.allocator, shared, "alpha");
    defer fourth.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    // The other tree's file differs: the shared record's read does not hold, so the query is computed, not served, and the result is
    // another variant of the key, not a disagreement about the first.
    try std.testing.expectEqualStrings("beta", try other.run(0));
    try std.testing.expectEqual(@as(u64, 0), other.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 1), other.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), other.numbers().count(.shared_published));
    try std.testing.expectEqual(@as(u64, 0), other.numbers().count(.shared_mismatches));
    // Each later tree is served the variant its file reads, from whichever slot holds it.
    try std.testing.expectEqualStrings("beta", try third.run(0));
    try std.testing.expectEqual(@as(u64, 0), third.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), third.numbers().count(.shared_hits));
    try std.testing.expectEqualStrings("alpha", try fourth.run(0));
    try std.testing.expectEqual(@as(u64, 0), fourth.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), fourth.numbers().count(.shared_hits));
    // Nothing was logged as a determinism mismatch.
    const log = try std.fmt.allocPrint(shared.arena.allocator(), "{s}/native-tests-v3/mismatches.log", .{shared.root});
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(std.testing.io, log, .{}));
    try first.restart(.{ .shared = shared.tier() });
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.recomputed));
}

test "shared tier: a record served from the work directory that the tier lacks is published to it" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    try first.restart(.{});
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try first.restart(.{ .shared = shared.tier() });
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.shared_published));
    const later = try tree(std.testing.allocator, shared, "alpha");
    defer later.destroy();
    try std.testing.expectEqualStrings("alpha", try later.run(0));
    try std.testing.expectEqual(@as(u64, 1), later.numbers().count(.shared_hits));
}

test "shared tier: a record served from the work directory is published when the first slot of its key holds another variant" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    const other = try tree(std.testing.allocator, shared, "beta");
    defer other.destroy();
    try other.restart(.{});
    try std.testing.expectEqualStrings("beta", try other.run(0));
    try other.restart(.{ .shared = shared.tier() });
    try std.testing.expectEqualStrings("beta", try other.run(0));
    try std.testing.expectEqual(@as(u64, 0), other.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), other.numbers().count(.shared_published));
    const later = try tree(std.testing.allocator, shared, "beta");
    defer later.destroy();
    try std.testing.expectEqualStrings("beta", try later.run(0));
    try std.testing.expectEqual(@as(u64, 1), later.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 0), later.numbers().count(.recomputed));
}

test "shared tier: a kind that is not shared neither publishes to the tier nor reads it, and a damaged shared record is a miss" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    first.runner.registry.entries[0].shared = false;
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.shared_published));
    const second_tree = try tree(std.testing.allocator, shared, "alpha");
    defer second_tree.destroy();
    try std.testing.expectEqualStrings("alpha", try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.recomputed));
    // Damage the record the second tree published: a third tree computes rather than trust it.
    var walker = try shared.temporary.dir.openDir(std.testing.io, "native-tests-v3/engine", .{ .iterate = true });
    defer walker.close(std.testing.io);
    var iterator = walker.iterate();
    const entry = (try iterator.next(std.testing.io)).?;
    try walker.writeFile(std.testing.io, .{ .sub_path = entry.name, .data = "damaged" });
    const third = try tree(std.testing.allocator, shared, "alpha");
    defer third.destroy();
    try std.testing.expectEqualStrings("alpha", try third.run(0));
    try std.testing.expectEqual(@as(u64, 0), third.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 1), third.numbers().count(.recomputed));
}

/// A filter that allows exactly the arguments in `denied` to stay local: it refuses those and allows the rest.
const Refusing = struct {
    denied: []const []const u8,

    fn allows(raw: *anyopaque, argument: []const u8) bool {
        const self: *const Refusing = @ptrCast(@alignCast(raw));
        for (self.denied) |name| if (std.mem.eql(u8, name, argument)) return false;
        return true;
    }

    fn filter(self: *Refusing) shared_tier.Filter {
        return .{ .context = self, .allows = allows };
    }
};

test "shared tier: a forgotten record is gone from the memo, the work directory and the tier, and is computed again" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    const other = try tree(std.testing.allocator, shared, "alpha");
    defer other.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.shared_published));
    // The first tree finds the answer wrong: its memo, its store and the tier lose the record.
    first.runner.forget(&first.kind, "0");
    try std.testing.expect(!shared.records.store.recordPresent(@import("digest.zig").key(first.kind.name, first.kind.identity, "0")));
    try std.testing.expectEqual(@as(?@import("engine.zig").Answer, null), try first.runner.peek(&first.kind, "0"));
    // Another tree no longer finds it in the tier: it computes the record itself.
    try std.testing.expectEqualStrings("alpha", try other.run(0));
    try std.testing.expectEqual(@as(u64, 1), other.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), other.numbers().count(.shared_hits));
    // Forgetting what is not there is not an error.
    first.runner.forget(&first.kind, "7");
}

test "shared tier: a query the filter refuses neither goes to the tier nor comes from it" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    var refusing: Refusing = .{ .denied = &.{"0"} };
    const first = try tree(std.testing.allocator, shared, "alpha");
    defer first.destroy();
    try first.restart(.{ .shared = shared.tier(), .filter = refusing.filter() });
    const second_tree = try tree(std.testing.allocator, shared, "alpha");
    defer second_tree.destroy();
    try second_tree.restart(.{ .shared = shared.tier(), .filter = refusing.filter() });
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.shared_published));
    try std.testing.expectEqualStrings("alpha", try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.shared_hits));
}

/// A filter that allows every query and counts how often it is asked.
const Asking = struct {
    asked: usize = 0,

    fn allows(raw: *anyopaque, _: []const u8) bool {
        const self: *Asking = @ptrCast(@alignCast(raw));
        self.asked += 1;
        return true;
    }

    fn filter(self: *Asking) shared_tier.Filter {
        return .{ .context = self, .allows = allows };
    }
};

// spec: T2-LAZY-FILTER-1
test "shared tier: a record the work directory serves outside a sweep never asks the kind's filter" {
    const shared = try Shared.create(std.testing.allocator);
    defer shared.destroy();
    var asking: Asking = .{};
    const fx = try tree(std.testing.allocator, shared, "alpha");
    defer fx.destroy();
    try fx.restart(.{ .shared = shared.tier(), .filter = asking.filter() });
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expect(asking.asked > 0);
    // The next process finds the partition unswept: it serves the record and asks the filter before it fills the tier.
    try fx.restart(.{ .shared = shared.tier(), .filter = asking.filter() });
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    // The one after that finds the stamp: the work directory serves the record and the filter (the test runner's
    // portability rule, which builds the test's program) is not asked.
    try fx.restart(.{ .shared = shared.tier(), .filter = asking.filter() });
    const before = asking.asked;
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(before, asking.asked);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

/// A compiler artifact store as the shared tier, in a temporary directory, heap-allocated so the engines may point into it.
const Compiler = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,
    records: compiler_records.Records,
    root: []const u8,

    fn create(gpa: std.mem.Allocator) !*Compiler {
        const self = try gpa.create(Compiler);
        errdefer gpa.destroy(self);
        self.gpa = gpa;
        self.temporary = std.testing.tmpDir(.{});
        errdefer self.temporary.cleanup();
        self.arena = .init(gpa);
        errdefer self.arena.deinit();
        const a = self.arena.allocator();
        self.root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
        self.records = try compiler_records.Records.open(a, std.testing.io, self.root);
        return self;
    }

    fn tier(self: *Compiler) shared_tier.Tier {
        return self.records.tier();
    }

    fn destroy(self: *Compiler) void {
        self.arena.deinit();
        self.temporary.cleanup();
        self.gpa.destroy(self);
    }
};

/// `tree`, over any tier.
fn treeOn(gpa: std.mem.Allocator, tier: shared_tier.Tier, text: []const u8) !*Fixture {
    const fx = try Fixture.create(gpa, one_file);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", text);
    fx.files.advance(second);
    try fx.restart(.{ .shared = tier });
    return fx;
}

/// A payload past the size at which the engine stores it as an object.
fn largeText(gpa: std.mem.Allocator) ![]u8 {
    const text = try gpa.alloc(u8, 3 * store_rules.object_threshold);
    for (text, 0..) |*byte, index| byte.* = 'a' + @as(u8, @intCast(index % 23));
    return text;
}

test "compiler tier: a record whose payload is an object travels with it, and the shared object becomes the second tree's own" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    const text = try largeText(std.testing.allocator);
    defer std.testing.allocator.free(text);
    const first = try treeOn(std.testing.allocator, compiler.tier(), text);
    defer first.destroy();
    const second_tree = try treeOn(std.testing.allocator, compiler.tier(), text);
    defer second_tree.destroy();
    try std.testing.expectEqualStrings(text, try first.run(0));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.shared_published));
    try std.testing.expectEqualStrings(text, try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.object_misses));
    // The object was copied into the second tree's store when its payload was first used: no tier is needed to read it again.
    try second_tree.restart(.{});
    try std.testing.expectEqualStrings(text, try second_tree.run(0));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.object_misses));
}

test "compiler tier: a damaged shared object is a miss that is computed again, and a served record opens no object until asked" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    const text = try largeText(std.testing.allocator);
    defer std.testing.allocator.free(text);
    const first = try treeOn(std.testing.allocator, compiler.tier(), text);
    defer first.destroy();
    try std.testing.expectEqualStrings(text, try first.run(0));
    // Damage the object in the tier (its header no longer matches its bytes).
    const object = try std.fmt.allocPrint(std.testing.allocator, "compiler-artifacts-v2/engine_object/{s}.blob", .{digest_rules.hex(digest_rules.hash(text))});
    defer std.testing.allocator.free(object);
    try compiler.temporary.dir.writeFile(std.testing.io, .{ .sub_path = object, .data = "damaged" });
    const second_tree = try treeOn(std.testing.allocator, compiler.tier(), text);
    defer second_tree.destroy();
    const answered = try second_tree.runner.query(&second_tree.kind, "0");
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 0), second_tree.numbers().count(.object_reads));
    try std.testing.expectEqualStrings(text, try answered.payload());
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.object_misses));
    try std.testing.expectEqual(@as(u64, 1), second_tree.numbers().count(.recomputed));
}

test "compiler tier: a record served from the work directory goes to the tier with its object, and a tier with no objects keeps such a record local" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    const text = try largeText(std.testing.allocator);
    defer std.testing.allocator.free(text);
    const first = try treeOn(std.testing.allocator, compiler.tier(), text);
    defer first.destroy();
    try first.restart(.{});
    try std.testing.expectEqualStrings(text, try first.run(0));
    try first.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings(text, try first.run(0));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.shared_published));
    const later = try treeOn(std.testing.allocator, compiler.tier(), text);
    defer later.destroy();
    try std.testing.expectEqualStrings(text, try later.run(0));
    try std.testing.expectEqual(@as(u64, 1), later.numbers().count(.shared_hits));
    try std.testing.expectEqual(@as(u64, 0), later.numbers().count(.recomputed));
    // The native test store keeps records only: the same record never reaches it, nor is looked up in it.
    const records_only = try Shared.create(std.testing.allocator);
    defer records_only.destroy();
    const writer = try tree(std.testing.allocator, records_only, text);
    defer writer.destroy();
    try std.testing.expectEqualStrings(text, try writer.run(0));
    try std.testing.expectEqual(@as(u64, 0), writer.numbers().count(.shared_published));
    try std.testing.expect(!records_only.tier().holdsObjects());
    try std.testing.expect(compiler.tier().holdsObjects());
}

/// A tier that counts the records fetched and the probes asked of it, and forwards everything to another.
const Counting = struct {
    inner: shared_tier.Tier,
    fetches: usize = 0,
    probes: usize = 0,

    fn tier(self: *Counting) shared_tier.Tier {
        return .{ .context = self, .vtable = &counting_vtable };
    }

    fn of(raw: *anyopaque) *Counting {
        return @ptrCast(@alignCast(raw));
    }

    fn fetch(raw: *anyopaque, a: std.mem.Allocator, key: digest_rules.Digest) ?[]const u8 {
        of(raw).fetches += 1;
        return of(raw).inner.fetch(a, key);
    }

    fn contains(raw: *anyopaque, key: digest_rules.Digest) bool {
        return of(raw).inner.contains(key);
    }

    fn holds(raw: *anyopaque, key: digest_rules.Digest, bytes: []const u8) bool {
        of(raw).probes += 1;
        return of(raw).inner.holds(key, bytes);
    }

    fn identity(raw: *anyopaque) digest_rules.Digest {
        return of(raw).inner.identity().?;
    }

    fn publish(raw: *anyopaque, a: std.mem.Allocator, key: digest_rules.Digest, bytes: []const u8, result: digest_rules.Digest) shared_tier.Outcome {
        return of(raw).inner.publish(a, key, bytes, result);
    }

    fn forget(raw: *anyopaque, key: digest_rules.Digest) void {
        of(raw).inner.forget(key);
    }

    fn fetchObject(raw: *anyopaque, a: std.mem.Allocator, digest: digest_rules.Digest) ?[]const u8 {
        return of(raw).inner.fetchObject(a, digest);
    }

    fn publishObject(raw: *anyopaque, a: std.mem.Allocator, digest: digest_rules.Digest, bytes: []const u8) shared_tier.Outcome {
        return of(raw).inner.publishObject(a, digest, bytes);
    }
};

const counting_vtable: shared_tier.VTable = .{
    .fetch = Counting.fetch,
    .contains = Counting.contains,
    .holds = Counting.holds,
    .identity = Counting.identity,
    .publish = Counting.publish,
    .forget = Counting.forget,
    .objects = .{ .fetch = Counting.fetchObject, .publish = Counting.publishObject },
};

test "compiler tier: a record served from the work directory that the tier holds is told so by the tier's header, and the tier's record is not read" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    var counting: Counting = .{ .inner = compiler.tier() };
    const first = try treeOn(std.testing.allocator, counting.tier(), "alpha");
    defer first.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 1), first.numbers().count(.shared_published));
    // A new process over the same work directory: the record is served from it, the tier is asked whether it holds those bytes, and says yes.
    const fetched = counting.fetches;
    try first.restart(.{ .shared = counting.tier() });
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), first.numbers().count(.shared_published));
    try std.testing.expectEqual(@as(usize, 1), counting.probes);
    try std.testing.expectEqual(fetched, counting.fetches);
}

test "compiler tier: forgetting a record removes it from the tier, and another result under its key is kept out and logged" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    const first = try treeOn(std.testing.allocator, compiler.tier(), "alpha");
    defer first.destroy();
    const other = try treeOn(std.testing.allocator, compiler.tier(), "alpha");
    defer other.destroy();
    try std.testing.expectEqualStrings("alpha", try first.run(0));
    const key = digest_rules.key(first.kind.name, first.kind.identity, "0");
    try std.testing.expect(compiler.records.store.present(.engine_record, key));
    first.runner.forget(&first.kind, "0");
    try std.testing.expect(!compiler.records.store.present(.engine_record, key));
    try std.testing.expectEqualStrings("alpha", try other.run(0));
    try std.testing.expectEqual(@as(u64, 1), other.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), other.numbers().count(.shared_hits));
    // A tree whose file reads otherwise is not a disagreement: its record is another variant of the key, and forgetting the query
    // removes every variant.
    const differing = try treeOn(std.testing.allocator, compiler.tier(), "beta");
    defer differing.destroy();
    try std.testing.expectEqualStrings("beta", try differing.run(0));
    try std.testing.expectEqual(@as(u64, 0), differing.numbers().count(.shared_mismatches));
    try std.testing.expectEqual(@as(u64, 1), differing.numbers().count(.shared_published));
    const second_slot = digest_rules.variantKey(key, 1);
    try std.testing.expect(compiler.records.store.present(.engine_record, key) and compiler.records.store.present(.engine_record, second_slot));
    differing.runner.forget(&differing.kind, "0");
    try std.testing.expect(!compiler.records.store.present(.engine_record, key) and !compiler.records.store.present(.engine_record, second_slot));
}

test "compiler tier: a work directory whose record no longer holds is served the tier's variant for its file, and more versions than slots all stay correct" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    const worktree = try treeOn(std.testing.allocator, compiler.tier(), "alpha");
    defer worktree.destroy();
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    // The file changes: the local record is stale, the result is computed, and the tier holds both versions.
    try worktree.files.write("/src/a.txt", "beta");
    worktree.files.advance(second);
    try worktree.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings("beta", try worktree.run(0));
    try std.testing.expectEqual(@as(u64, 1), worktree.numbers().count(.recomputed));
    // The file changes back (a revert, a branch switch): the local record is the other version's, and the tier serves this one.
    try worktree.files.write("/src/a.txt", "alpha");
    worktree.files.advance(second);
    try worktree.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(u64, 0), worktree.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), worktree.numbers().count(.shared_hits));
    // Many more versions than the tier has slots: every run still gives the file's own result, with no disagreement logged.
    const versions = [_][]const u8{ "v1", "v2", "v3", "v4", "v5", "v6", "v7", "v8", "alpha", "v3" };
    for (versions) |text| {
        try worktree.files.write("/src/a.txt", text);
        worktree.files.advance(second);
        try worktree.restart(.{ .shared = compiler.tier() });
        try std.testing.expectEqualStrings(text, try worktree.run(0));
        try std.testing.expectEqual(@as(u64, 0), worktree.numbers().count(.shared_mismatches));
    }
}

test "compiler tier: two encodings of one result, which differ in the stat tuples of their reads, are the same record" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const identity: digest_rules.Digest = @splat(1);
    const key = digest_rules.key("probe", identity, "x");
    const result = digest_rules.hash("answer");
    const stale: record_rules.Read = .{ .file = .{ .path = "/src/a.txt", .present = true, .digest = digest_rules.hash("alpha"), .stat = .none } };
    const tuple: record_rules.Read = .{ .file = .{ .path = "/src/a.txt", .present = true, .digest = digest_rules.hash("alpha"), .stat = .{ .inode = 7, .size = 5, .mtime = 1, .ctime = 1 } } };
    const base: record_rules.Record = .{ .kind = "probe", .identity = identity, .key = key, .argument = "x", .result = result, .payload = .{ .inline_bytes = "answer" }, .reads = &.{stale} };
    const first = try record_rules.encode(a, base);
    var again = base;
    again.reads = &.{tuple};
    const second_bytes = try record_rules.encode(a, again);
    try std.testing.expect(!std.mem.eql(u8, first, second_bytes));
    const tier = compiler.tier();
    try std.testing.expectEqual(shared_tier.Outcome.stored, tier.publish(a, key, first, result));
    try std.testing.expectEqual(shared_tier.Outcome.present, tier.publish(a, key, second_bytes, result));
    // The same reads with another result are a determinism mismatch (different reads would be another variant): kept out and logged.
    try std.testing.expectEqual(shared_tier.Outcome.mismatch, tier.publish(a, key, second_bytes, digest_rules.hash("another")));
    const log = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, try std.fmt.allocPrint(a, "{s}/compiler-artifacts-v2/mismatches.log", .{compiler.root}), a, .limited(1 << 12));
    try std.testing.expect(std.mem.startsWith(u8, log, "mismatch engine_record "));
    try std.testing.expectEqualSlices(u8, first, tier.fetch(a, key).?);
    try std.testing.expect(tier.contains(key));
    tier.forget(key);
    try std.testing.expect(!tier.contains(key));
    try std.testing.expectEqual(@as(?[]const u8, null), tier.fetch(a, key));
    try std.testing.expectEqual(shared_tier.Outcome.stored, tier.publishObject(a, result, "answer"));
    try std.testing.expectEqualStrings("answer", tier.fetchObject(a, result).?);
}

test "FX11 compiler tier: a variant that loses the race for an address, and another writer's table under a key that reads nothing, are kept out with no mismatch" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const identity: digest_rules.Digest = @splat(2);
    const key = digest_rules.key("probe", identity, "main.selka");
    const alpha: record_rules.Read = .{ .file = .{ .path = "/src/main.selka", .present = true, .digest = digest_rules.hash("alpha"), .stat = .none } };
    const beta: record_rules.Read = .{ .file = .{ .path = "/src/main.selka", .present = true, .digest = digest_rules.hash("beta"), .stat = .none } };
    const base: record_rules.Record = .{ .kind = "probe", .identity = identity, .key = key, .argument = "main.selka", .result = digest_rules.hash("alpha"), .payload = .{ .inline_bytes = "alpha" }, .reads = &.{alpha} };
    var other = base;
    other.result = digest_rules.hash("beta");
    other.payload = .{ .inline_bytes = "beta" };
    other.reads = &.{beta};
    const tier = compiler.tier();
    const first = try record_rules.encode(a, base);
    try std.testing.expectEqual(shared_tier.Outcome.stored, tier.publish(a, key, first, base.result));
    // Two programs' `main.selka`, both choosing the first free slot before either was published: the second is another variant.
    try std.testing.expectEqual(shared_tier.Outcome.skipped, tier.publish(a, key, try record_rules.encode(a, other), other.result));
    try std.testing.expectEqualSlices(u8, first, tier.fetch(a, key).?);
    // A kind that reads nothing (an ownership-proof table): another program's table under the key is not a disagreement.
    const table_key = digest_rules.key("table", identity, "main\x00zero-rc\x00main");
    var table = base;
    table.kind = "table";
    table.key = table_key;
    table.reads = &.{};
    var other_table = table;
    other_table.result = digest_rules.hash("another table");
    try std.testing.expectEqual(shared_tier.Outcome.stored, tier.publish(a, table_key, try record_rules.encode(a, table), table.result));
    try std.testing.expectEqual(shared_tier.Outcome.skipped, tier.publish(a, table_key, try record_rules.encode(a, other_table), other_table.result));
    const log = try std.fmt.allocPrint(a, "{s}/compiler-artifacts-v2/mismatches.log", .{compiler.root});
    try std.testing.expectError(error.FileNotFound, std.Io.Dir.cwd().statFile(std.testing.io, log, .{}));
    // The same reads with another result are still a determinism mismatch, logged.
    var same_reads = base;
    same_reads.result = digest_rules.hash("gamma");
    try std.testing.expectEqual(shared_tier.Outcome.mismatch, tier.publish(a, key, try record_rules.encode(a, same_reads), same_reads.result));
    const lines = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, log, a, .limited(1 << 12));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, lines, "\n"));
}

test "read signature: it ignores the stat tuples and a placement variable's value, and moves with a digest, a path or a value" {
    const stale: record_rules.Read = .{ .file = .{ .path = "/src/a.txt", .present = true, .digest = digest_rules.hash("alpha"), .stat = .none } };
    const tuple: record_rules.Read = .{ .file = .{ .path = "/src/a.txt", .present = true, .digest = digest_rules.hash("alpha"), .stat = .{ .inode = 7, .size = 5, .mtime = 1, .ctime = 1 } } };
    const changed: record_rules.Read = .{ .file = .{ .path = "/src/a.txt", .present = true, .digest = digest_rules.hash("beta"), .stat = .none } };
    const moved: record_rules.Read = .{ .file = .{ .path = "/src/b.txt", .present = true, .digest = digest_rules.hash("alpha"), .stat = .none } };
    const here: record_rules.Read = .{ .variable = .{ .name = "WHERE", .set = true, .value = "/tmp/one", .placement = true } };
    const there: record_rules.Read = .{ .variable = .{ .name = "WHERE", .set = true, .value = "/tmp/two", .placement = true } };
    const mode: record_rules.Read = .{ .variable = .{ .name = "MODE", .set = true, .value = "debug", .placement = false } };
    const other_mode: record_rules.Read = .{ .variable = .{ .name = "MODE", .set = true, .value = "release", .placement = false } };
    try std.testing.expectEqual(record_rules.readSignature(&.{stale}), record_rules.readSignature(&.{tuple}));
    try std.testing.expect(!std.mem.eql(u8, &record_rules.readSignature(&.{stale}), &record_rules.readSignature(&.{changed})));
    try std.testing.expect(!std.mem.eql(u8, &record_rules.readSignature(&.{stale}), &record_rules.readSignature(&.{moved})));
    try std.testing.expectEqual(record_rules.readSignature(&.{ stale, here }), record_rules.readSignature(&.{ stale, there }));
    try std.testing.expect(!std.mem.eql(u8, &record_rules.readSignature(&.{mode}), &record_rules.readSignature(&.{other_mode})));
    // The order of the reads is part of what was read.
    try std.testing.expect(!std.mem.eql(u8, &record_rules.readSignature(&.{ stale, mode }), &record_rules.readSignature(&.{ mode, stale })));
    // Slot 0 is the key; the other slots are distinct addresses.
    const key = digest_rules.key("probe", @splat(1), "x");
    try std.testing.expectEqual(key, digest_rules.variantKey(key, 0));
    try std.testing.expect(!std.mem.eql(u8, &digest_rules.variantKey(key, 1), &digest_rules.variantKey(key, 2)));
    try std.testing.expect(!std.mem.eql(u8, &digest_rules.variantKey(key, 1), &key));
}

const hour = 60 * 60 * second;

test "tier sweep: the tier is asked about a kind's served records once an hour, not on every build" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    var counting: Counting = .{ .inner = compiler.tier() };
    const worktree = try treeOn(std.testing.allocator, counting.tier(), "alpha");
    defer worktree.destroy();
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    // The first process that serves the record has no stamp to go by, so it asks; the next ones, within the hour, do not.
    try worktree.restart(.{ .shared = counting.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(usize, 1), counting.probes);
    try worktree.restart(.{ .shared = counting.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try worktree.restart(.{ .shared = counting.tier() });
    worktree.files.advance(hour - second);
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(usize, 1), counting.probes);
    try std.testing.expectEqual(@as(u64, 0), worktree.numbers().count(.recomputed));
    // An hour after the stamp it asks again.
    try worktree.restart(.{ .shared = counting.tier() });
    worktree.files.advance(2 * second);
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(usize, 2), counting.probes);
}

test "tier sweep: a kind with no stamp and a tier that moved are asked at once, whatever the stamp of another kind or tier says" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    var counting: Counting = .{ .inner = compiler.tier() };
    const worktree = try treeOn(std.testing.allocator, counting.tier(), "alpha");
    defer worktree.destroy();
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try worktree.restart(.{ .shared = counting.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(usize, 1), counting.probes);
    // Another code identity is another partition, with a stamp of its own: its record, made without the tier, is asked about in the first process
    // that serves it, seconds after the first kind was stamped.
    worktree.kind.identity = @splat(2);
    try worktree.restart(.{});
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try worktree.restart(.{ .shared = counting.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(usize, 2), counting.probes);
    try std.testing.expectEqual(@as(u64, 1), worktree.numbers().count(.shared_published));
    // The tier moves (another directory): the stamp names the old one, so the new one is asked and filled at once.
    const moved = try Compiler.create(std.testing.allocator);
    defer moved.destroy();
    var after: Counting = .{ .inner = moved.tier() };
    try worktree.restart(.{ .shared = after.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(usize, 1), after.probes);
    try std.testing.expectEqual(@as(u64, 1), worktree.numbers().count(.shared_published));
    try std.testing.expect(moved.records.store.present(.engine_record, digest_rules.key(worktree.kind.name, worktree.kind.identity, "0")));
    // The engine stamps the tier it was given when it ends, so it must end before the tier does.
    try worktree.restart(.{});
}

test "tier sweep: a sweep repairs a tier record that is missing or damaged, and until the sweep is due the repair waits" {
    const compiler = try Compiler.create(std.testing.allocator);
    defer compiler.destroy();
    const worktree = try treeOn(std.testing.allocator, compiler.tier(), "alpha");
    defer worktree.destroy();
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try worktree.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    const key = digest_rules.key(worktree.kind.name, worktree.kind.identity, "0");
    // The tier loses the record after the sweep: the next builds of the hour serve from the work directory and leave it lost.
    compiler.tier().forget(key);
    try worktree.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(u64, 0), worktree.numbers().count(.shared_published));
    try std.testing.expect(!compiler.records.store.present(.engine_record, key));
    // An hour on, the sweep publishes it again.
    worktree.files.advance(hour + second);
    try worktree.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(u64, 1), worktree.numbers().count(.shared_published));
    try std.testing.expect(compiler.records.store.present(.engine_record, key));
    // A damaged tier record is a miss for a reader and is replaced by the next sweep.
    const damaged = try std.fmt.allocPrint(std.testing.allocator, "compiler-artifacts-v2/engine_record/{s}.blob", .{digest_rules.hex(key)});
    defer std.testing.allocator.free(damaged);
    try worktree.restart(.{});
    try compiler.temporary.dir.writeFile(std.testing.io, .{ .sub_path = damaged, .data = "damaged" });
    try std.testing.expectEqual(@as(?[]const u8, null), compiler.tier().fetch(compiler.arena.allocator(), key));
    worktree.files.advance(hour + second);
    try worktree.restart(.{ .shared = compiler.tier() });
    try std.testing.expectEqualStrings("alpha", try worktree.run(0));
    try std.testing.expectEqual(@as(u64, 1), worktree.numbers().count(.shared_published));
    try std.testing.expect(compiler.tier().fetch(compiler.arena.allocator(), key) != null);
}
