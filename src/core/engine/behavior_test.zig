//! The engine's behaviour over the in-memory world: what is served, what is recomputed, what is cut off, and what the
//! engine refuses. Each test is a scenario of the spec's validation rules (§5) and error conditions.
const std = @import("std");
const engine_rules = @import("engine.zig");
const fixture_rules = @import("fixture_test.zig");
const script = @import("kinds/script.zig");
const context = @import("context.zig");
const digest_rules = @import("digest.zig");
const store_rules = @import("store.zig");
const Fixture = fixture_rules.Fixture;

const second = std.time.ns_per_s;

/// One node reading `/src/a.txt`.
const one_file: script.Graph = .{ .nodes = &.{fixture_rules.fileNode("/src/a.txt", .concat)} };

/// A fixture whose file `/src/a.txt` has been written, aged past the racy window, and read once.
fn aged(gpa: std.mem.Allocator, graph: script.Graph) fixture_rules.Failure!*Fixture {
    const fx = try Fixture.create(gpa, graph);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    fx.files.advance(second);
    return fx;
}

test "an unchanged file is served by the next process, which reads none of its bytes" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    try fx.restart(.{});
    fx.files.resetCounters();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), fx.files.count("reads"));
}

test "a touched file with the same bytes is served after one hash" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    try fx.restart(.{});
    fx.files.touch("/src/a.txt");
    fx.files.advance(second);
    fx.files.touch("/src/a.txt");
    fx.files.resetCounters();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 1), fx.files.count("reads"));
}

test "a changed file is recomputed, and the new result is what the next process is served" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/a.txt", "omega");
    try std.testing.expectEqualStrings("omega", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    fx.files.advance(second);
    try fx.restart(.{});
    try std.testing.expectEqualStrings("omega", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

test "a file rewritten within one clock tick with the same size is not mistaken for the file recorded" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    try fx.files.write("/src/a.txt", "aaaaa");
    // No time passes: the file was changed inside the racy window, so its tuple is not trusted.
    _ = try fx.run(0);
    try fx.restart(.{});
    try fx.files.write("/src/a.txt", "bbbbb");
    try std.testing.expectEqualStrings("bbbbb", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
}

test "a dependency recomputed to the same result leaves its dependent served: an early cutoff" {
    const graph: script.Graph = .{ .nodes = &.{
        fixture_rules.fileNode("/src/a.txt", .length),
        .{ .ops = &.{ .{ .node = 0 }, .{ .file = "/src/b.txt" } } },
    } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try fx.files.write("/src/b.txt", "bee");
    fx.files.advance(second);
    try std.testing.expectEqualStrings("5|bee", try fx.run(1));
    try fx.restart(.{});
    try fx.files.write("/src/a.txt", "gamma");
    fx.files.advance(second);
    try std.testing.expectEqualStrings("5|bee", try fx.run(1));
    const numbers = fx.numbers();
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.served));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.early_cutoffs));
}

test "a dependency whose result changed recomputes its dependent" {
    const graph: script.Graph = .{ .nodes = &.{ fixture_rules.fileNode("/src/a.txt", .length), .{ .ops = &.{.{ .node = 0 }} } } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try std.testing.expectEqualStrings("5", try fx.run(1));
    try fx.restart(.{});
    try fx.files.write("/src/a.txt", "longer");
    try std.testing.expectEqualStrings("6", try fx.run(1));
    try std.testing.expectEqual(@as(u64, 2), fx.numbers().count(.recomputed));
}

test "a placement variable changing leaves a query served, and a keyed one recomputes it" {
    const graph: script.Graph = .{ .nodes = &.{
        .{ .ops = &.{ .{ .variable = "PLACE_CACHE" }, .{ .file = "/src/a.txt" } } },
        .{ .ops = &.{ .{ .variable = "MODE" }, .{ .file = "/src/a.txt" } } },
    } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try fx.files.setVariable("PLACE_CACHE", "/one");
    try fx.files.setVariable("MODE", "debug");
    try std.testing.expectEqualStrings("/one|alpha", try fx.run(0));
    try std.testing.expectEqualStrings("debug|alpha", try fx.run(1));
    try fx.restart(.{});
    try fx.files.setVariable("PLACE_CACHE", "/two");
    try std.testing.expectEqualStrings("/one|alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try fx.files.setVariable("MODE", "release");
    try std.testing.expectEqualStrings("release|alpha", try fx.run(1));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
}

test "absent files, existence tests and listings are reads: a file appearing or going is a change" {
    const graph: script.Graph = .{ .nodes = &.{
        fixture_rules.fileNode("/src/late.txt", .concat),
        .{ .ops = &.{.{ .exists = "/src/probe" }} },
        .{ .ops = &.{.{ .listing = .{ .path = "/src" } }} },
    } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try std.testing.expectEqualStrings("~", try fx.run(0));
    try std.testing.expectEqualStrings("0", try fx.run(1));
    try std.testing.expectEqualStrings("a.txt", try fx.run(2));
    try fx.restart(.{});
    try fx.files.write("/src/late.txt", "here");
    fx.files.advance(second);
    try std.testing.expectEqualStrings("here", try fx.run(0));
    try std.testing.expectEqualStrings("0", try fx.run(1));
    try std.testing.expectEqualStrings("a.txt,late.txt", try fx.run(2));
    try std.testing.expectEqual(@as(u64, 2), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

test "a query is validated once per process and then answered from the memo" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    try fx.restart(.{});
    _ = try fx.run(0);
    fx.files.resetCounters();
    _ = try fx.run(0);
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.validated));
    try std.testing.expectEqual(@as(u64, 2), fx.numbers().count(.memo_hits));
    try std.testing.expectEqual(@as(u64, 0), fx.files.count("stats"));
}

test "a new revision forgets what was validated, so an edit under a long-lived process is seen" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    fx.files.advance(second);
    try fx.files.write("/src/a.txt", "omega");
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    fx.runner.newRevision();
    try std.testing.expectEqualStrings("omega", try fx.run(0));
}

test "queries that depend on each other are a cycle, and the cycle is named" {
    const graph: script.Graph = .{ .nodes = &.{ .{ .ops = &.{.{ .node = 1 }} }, .{ .ops = &.{.{ .node = 0 }} } } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try std.testing.expectError(error.Cycle, fx.run(0));
    const text = try fx.runner.lastCycle(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expectEqualStrings("script(0) -> script(1) -> script(0)", text);
}

test "a chain deeper than the limit is refused, and one within it is answered" {
    const link = [_]script.Node{
        .{ .ops = &.{.{ .node = 1 }} },    .{ .ops = &.{.{ .node = 2 }} }, .{ .ops = &.{.{ .node = 3 }} },
        .{ .ops = &.{.{ .node = 4 }} },    .{ .ops = &.{.{ .node = 5 }} }, .{ .ops = &.{.{ .node = 6 }} },
        .{ .ops = &.{.{ .file = "/x" }} },
    };
    const fx = try aged(std.testing.allocator, .{ .nodes = &link });
    defer fx.destroy();
    try fx.restart(.{ .depth_limit = 3 });
    try std.testing.expectError(error.DepthExceeded, fx.run(0));
    try fx.restart(.{ .depth_limit = 6 });
    try std.testing.expectEqualStrings("~", try fx.run(0));
}

test "a torn record is a miss that the recomputation heals" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    const path = try fx.recordPath(std.testing.allocator, 0);
    defer std.testing.allocator.free(path);
    const bytes = (try fx.runner.store.load(std.testing.allocator, path)).?;
    defer std.testing.allocator.free(bytes);
    bytes[bytes.len / 2] ^= 0x40;
    try std.testing.expect(try fx.runner.store.publish(std.testing.allocator, path, bytes));
    try fx.restart(.{});
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    try fx.restart(.{});
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

test "a record cut short, by a byte or to a header, is a miss that the recomputation heals" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    const path = try fx.recordPath(std.testing.allocator, 0);
    defer std.testing.allocator.free(path);
    const bytes = (try fx.runner.store.load(std.testing.allocator, path)).?;
    defer std.testing.allocator.free(bytes);
    for ([_]usize{ bytes.len - 1, bytes.len - 32, bytes.len / 2, 12, 0 }) |length| {
        try std.testing.expect(try fx.runner.store.publish(std.testing.allocator, path, bytes[0..length]));
        try fx.restart(.{});
        try std.testing.expectEqualStrings("alpha", try fx.run(0));
        try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    }
    try fx.restart(.{});
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

test "a payload over the threshold is an object, and a missing object is a miss" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    const big = try std.testing.allocator.alloc(u8, store_rules.object_threshold + 1);
    defer std.testing.allocator.free(big);
    @memset(big, 'q');
    try fx.files.write("/src/a.txt", big);
    fx.files.advance(second);
    try std.testing.expectEqual(big.len, (try fx.run(0)).len);
    try fx.restart(.{});
    try std.testing.expectEqual(big.len, (try fx.run(0)).len);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    const object = try fx.runner.store.objectPath(std.testing.allocator, digest_rules.hash(big));
    defer std.testing.allocator.free(object);
    store_rules.discard(std.testing.io, object);
    try fx.restart(.{});
    try std.testing.expectEqual(big.len, (try fx.run(0)).len);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
}

test "records are partitioned by code identity: another identity is served nothing of the first" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    fx.kind.identity = @splat(2);
    try fx.restart(.{});
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    const stamp = try std.fmt.allocPrint(std.testing.allocator, "{s}/{s}", .{ fx.runner.registry.entries[0].directory, store_rules.used_leaf });
    defer std.testing.allocator.free(stamp);
    try std.testing.expect(fx.runner.store.lastUse(std.testing.allocator, fx.runner.registry.entries[0].directory) != null);
    fx.kind.identity = @splat(1);
    try fx.restart(.{});
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

test "a kind that fails stores nothing, and the next call tries again" {
    const graph: script.Graph = .{ .nodes = &.{.{ .ops = &.{.{ .node = 9 }} }} };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try std.testing.expectError(error.Failed, fx.run(0));
    const path = try fx.recordPath(std.testing.allocator, 0);
    defer std.testing.allocator.free(path);
    try std.testing.expectEqual(@as(?[]u8, null), try fx.runner.store.load(std.testing.allocator, path));
    try std.testing.expectError(error.Failed, fx.run(0));
}

test "the registry refuses a bad name, a repeated name, a full table, an unknown kind and an oversized argument" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    var bad = fx.kind;
    bad.name = "Bad Name";
    try std.testing.expectError(error.InvalidKindName, fx.runner.register(&bad));
    try std.testing.expectError(error.DuplicateKind, fx.runner.register(&fx.kind));
    var other = fx.kind;
    other.name = "other";
    try std.testing.expectError(error.UnknownKind, fx.runner.query(&other, "0"));
    const huge = try std.testing.allocator.alloc(u8, digest_rules.max_argument + 1);
    defer std.testing.allocator.free(huge);
    try std.testing.expectError(error.ArgumentTooLong, fx.runner.query(&fx.kind, huge));
    var names: [32][8]u8 = undefined;
    var kinds: [32]context.Kind = undefined;
    for (&kinds, &names, 0..) |*slot, *name, at| {
        slot.* = fx.kind;
        slot.name = try std.fmt.bufPrint(name, "k{d}", .{at});
    }
    try std.testing.expectEqual(@as(?anyerror, error.TooManyKinds), registerAll(&fx.runner, &kinds));
}

/// Register `kinds` in turn; the first error, or null when all were accepted.
fn registerAll(runner: *engine_rules.Engine, kinds: []const context.Kind) ?anyerror {
    for (kinds) |*kind| runner.register(kind) catch |err| return err;
    return null;
}

test "a file hashed because its tuple moved is not hashed again once its record is refreshed" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    try fx.restart(.{});
    fx.files.advance(second);
    fx.files.touch("/src/a.txt");
    fx.files.advance(second);
    fx.files.resetCounters();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.files.count("reads"));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.refreshed));
    try fx.restart(.{});
    fx.files.resetCounters();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 0), fx.files.count("reads"));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.refreshed));
}

test "a file read within the racy window is hashed until it has aged, then its tuple is trusted" {
    const fx = try Fixture.create(std.testing.allocator, one_file);
    defer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    _ = try fx.run(0);
    try fx.restart(.{});
    fx.files.resetCounters();
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.files.count("reads"));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.refreshed));
    fx.files.advance(second);
    try fx.restart(.{});
    fx.files.resetCounters();
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.files.count("reads"));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.refreshed));
    try fx.restart(.{});
    fx.files.resetCounters();
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 0), fx.files.count("reads"));
}

/// A chain of `length` nodes in which each reads the next and the last reads `/src/a.txt`.
fn chain(a: std.mem.Allocator, length: usize) std.mem.Allocator.Error!script.Graph {
    const nodes = try a.alloc(script.Node, length);
    for (nodes, 0..) |*node, at| {
        const ops = try a.alloc(script.Op, 1);
        ops[0] = if (at + 1 == length) .{ .file = "/src/a.txt" } else .{ .node = @intCast(at + 1) };
        node.* = .{ .ops = ops, .fold = if (at % 2 == 0) .concat else .length };
    }
    return .{ .nodes = nodes };
}

test "a chain as deep as the default limit allows is computed, then validated by a new process, without exhausting the stack" {
    var scratch: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer scratch.deinit();
    const fx = try aged(std.testing.allocator, try chain(scratch.allocator(), 500));
    defer fx.destroy();
    const answer = try std.testing.allocator.dupe(u8, try fx.run(0));
    defer std.testing.allocator.free(answer);
    try std.testing.expectEqual(@as(u64, 500), fx.numbers().count(.recomputed));
    try fx.restart(.{});
    try std.testing.expectEqualStrings(answer, try fx.run(0));
    try std.testing.expectEqual(@as(u64, 500), fx.numbers().count(.served));
    try fx.files.write("/src/a.txt", "omega!");
    fx.files.advance(second);
    try fx.restart(.{});
    // The last three nodes see the change; the third folds it to the same length, which cuts the rest off.
    try std.testing.expectEqualStrings(answer, try fx.run(0));
    try std.testing.expectEqual(@as(u64, 3), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 497), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.early_cutoffs));
}

test "a peek serves a valid record without computing, and answers nothing for a query that would have to run" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    // Nothing is recorded yet: the peek answers null and computes nothing.
    try std.testing.expectEqual(@as(?engine_rules.Answer, null), try fx.runner.peek(&fx.kind, "0"));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.served));
    // After the query ran, a new process peeks the record and is served it.
    _ = try fx.run(0);
    try fx.restart(.{});
    const served = (try fx.runner.peek(&fx.kind, "0")).?;
    try std.testing.expectEqualStrings("alpha", try served.result.payload());
    try std.testing.expectEqual(engine_rules.Origin.served, served.origin);
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
    // The file changes: the record is stale, the peek says so and does not recompute it.
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/a.txt", "omega");
    try std.testing.expectEqual(@as(?engine_rules.Answer, null), try fx.runner.peek(&fx.kind, "0"));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
}

test "a record whose dependency now fails is invalid, and a recomputation that reads the failing dependency again reports the failure" {
    const graph: script.Graph = .{ .nodes = &.{ fixture_rules.fileNode("/src/a.txt", .length), .{ .ops = &.{.{ .node = 0 }} } } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try std.testing.expectEqualStrings("5", try fx.run(1));
    try fx.restart(.{});
    try fx.files.write("/src/a.txt", "longer");
    // Node 0 now fails for a reason of its own (it reads a node that does not exist), not because an argument is stale.
    fx.graph = .{ .nodes = &.{ .{ .ops = &.{ .{ .file = "/src/a.txt" }, .{ .node = 9 } } }, .{ .ops = &.{.{ .node = 0 }} } } };
    try std.testing.expectError(error.Failed, fx.run(1));
    try std.testing.expectError(error.Failed, fx.run(1));
}

test "a record whose dependency now fails recomputes when its own reads no longer name the dependency" {
    const graph: script.Graph = .{ .nodes = &.{ fixture_rules.fileNode("/src/a.txt", .length), .{ .ops = &.{.{ .node = 0 }} } } };
    const fx = try aged(std.testing.allocator, graph);
    defer fx.destroy();
    try fx.files.write("/src/b.txt", "bee");
    try std.testing.expectEqualStrings("5", try fx.run(1));
    try fx.restart(.{});
    try fx.files.write("/src/a.txt", "longer");
    fx.graph = .{ .nodes = &.{ .{ .ops = &.{ .{ .file = "/src/a.txt" }, .{ .node = 9 } } }, .{ .ops = &.{.{ .file = "/src/b.txt" }} } } };
    try std.testing.expectEqualStrings("bee", try fx.run(1));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
}
