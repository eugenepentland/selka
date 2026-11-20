//! The projection read (spec §17.3): a query that reads some of another query's parts is valid while those parts are,
//! whatever else the other query holds. These tests are the behaviour of record format 2's tag 7 over the in-memory
//! world: the early cutoff a part gives and a whole-result read does not, an absent part, the one-record rule, the
//! check verify mode makes on the parts table, `explain`, and a format 1 record on disk.
const std = @import("std");
const explain_rules = @import("explain.zig");
const fixture_rules = @import("fixture_test.zig");
const record_rules = @import("record.zig");
const script = @import("kinds/script.zig");
const context = @import("context.zig");
const digest_rules = @import("digest.zig");
const world_rules = @import("world.zig");
const Fixture = fixture_rules.Fixture;
const Context = context.Context;
const Kind = context.Kind;
const Error = context.Error;

const second = std.time.ns_per_s;

/// Node 0 reads `/src/a.txt` and `/src/b.txt` and publishes each as a part (`p0`, `p1`). Node 1 reads part `p0` of node 0
/// only, node 2 reads the whole of node 0, node 3 reads `p1` and a part node 0 does not publish.
const graph: script.Graph = .{ .nodes = &.{
    .{
        .ops = &.{ .{ .file = "/src/a.txt" }, .{ .file = "/src/b.txt" } },
        .expose = &.{ .{ .name = "p0", .op = 0 }, .{ .name = "p1", .op = 1 } },
    },
    .{ .ops = &.{.{ .part = .{ .node = 0, .names = &.{"p0"} } }} },
    .{ .ops = &.{.{ .node = 0 }} },
    .{ .ops = &.{.{ .part = .{ .node = 0, .names = &.{ "p1", "pz" } } }} },
} };

/// A fixture over `graph` with both files written and aged past the racy window.
fn aged(gpa: std.mem.Allocator) fixture_rules.Failure!*Fixture {
    const fx = try Fixture.create(gpa, graph);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    try fx.files.write("/src/b.txt", "bravo");
    fx.files.advance(second);
    return fx;
}

fn expectPiece(text: []const u8, source: []const u8) !void {
    const shown = digest_rules.hex(digest_rules.hash(source));
    try std.testing.expectEqualStrings(shown[0..8], text[0..8]);
}

test "a change to a part nobody named leaves the reader served, and the cutoff is counted" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    const first = try std.testing.allocator.dupe(u8, try fx.run(1));
    defer std.testing.allocator.free(first);
    try expectPiece(first, "alpha");
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/b.txt", "bravo changed");
    fx.files.advance(second);
    try std.testing.expectEqualStrings(first, try fx.run(1));
    const numbers = fx.numbers();
    // The producer ran again (its file changed); the reader was served: its part is as it was.
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.served));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.early_cutoffs));
}

test "a change to the part that was named recomputes the reader" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    const first = try std.testing.allocator.dupe(u8, try fx.run(1));
    defer std.testing.allocator.free(first);
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/a.txt", "alpha changed");
    fx.files.advance(second);
    const now = try fx.run(1);
    try expectPiece(now, "alpha changed");
    try std.testing.expect(!std.mem.eql(u8, first, now));
    try std.testing.expectEqual(@as(u64, 2), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.served));
}

test "a query that reads the whole dependency is recomputed by the change a part read ignores" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    _ = try fx.run(1);
    _ = try fx.run(2);
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/b.txt", "bravo changed");
    fx.files.advance(second);
    _ = try fx.run(2);
    _ = try fx.run(1);
    // The producer and the whole-result reader ran; the part reader was served.
    try std.testing.expectEqual(@as(u64, 2), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
}

test "a part the dependency does not publish is absent, and stays absent while the dependency changes" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    const first = try std.testing.allocator.dupe(u8, try fx.run(3));
    defer std.testing.allocator.free(first);
    try std.testing.expect(std.mem.endsWith(u8, first, ",~"));
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/a.txt", "alpha changed");
    fx.files.advance(second);
    try std.testing.expectEqualStrings(first, try fx.run(3));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
}

test "a record holds the parts its query published, in byte order, and one read per projection" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    _ = try fx.run(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const producer = try fx.recordPath(a, 0);
    const found = try record_rules.decode(a, (try fx.runner.store.load(a, producer)).?);
    try std.testing.expectEqual(@as(usize, 2), found.parts.len);
    try std.testing.expectEqualStrings("p0", found.parts[0].name);
    try std.testing.expectEqualStrings("p1", found.parts[1].name);
    try std.testing.expectEqual(digest_rules.hash("alpha"), found.parts[0].digest);
    const reader = try fx.recordPath(a, 1);
    const reading = try record_rules.decode(a, (try fx.runner.store.load(a, reader)).?);
    try std.testing.expectEqual(@as(usize, 1), reading.reads.len);
    try std.testing.expectEqual(@as(usize, 1), reading.reads[0].part.parts.len);
    try std.testing.expectEqualStrings("p0", reading.reads[0].part.parts[0].name);
    try std.testing.expectEqual(digest_rules.hash("alpha"), reading.reads[0].part.parts[0].digest);
    try std.testing.expectEqual(found.key, reading.reads[0].part.key);
}

/// A node that asks for the same projection twice, and for the same names in another order.
const repeating: script.Graph = .{ .nodes = &.{
    .{
        .ops = &.{ .{ .file = "/src/a.txt" }, .{ .file = "/src/b.txt" } },
        .expose = &.{ .{ .name = "p0", .op = 0 }, .{ .name = "p1", .op = 1 } },
    },
    .{ .ops = &.{
        .{ .part = .{ .node = 0, .names = &.{ "p1", "p0" } } },
        .{ .part = .{ .node = 0, .names = &.{ "p0", "p1", "p0" } } },
        .{ .part = .{ .node = 0, .names = &.{"p0"} } },
    } },
} };

test "the same projection asked twice is one read, in whatever order and with whatever repeats it was named" {
    const fx = try Fixture.create(std.testing.allocator, repeating);
    defer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    try fx.files.write("/src/b.txt", "bravo");
    fx.files.advance(second);
    _ = try fx.run(1);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const reading = try record_rules.decode(a, (try fx.runner.store.load(a, try fx.recordPath(a, 1))).?);
    // {p0, p1} twice is one read; {p0} is another.
    try std.testing.expectEqual(@as(usize, 2), reading.reads.len);
    try std.testing.expectEqual(@as(usize, 2), reading.reads[0].part.parts.len);
    try std.testing.expectEqualStrings("p0", reading.reads[0].part.parts[0].name);
    try std.testing.expectEqualStrings("p1", reading.reads[0].part.parts[1].name);
}

/// What a kind that publishes parts needs to change behind the engine's back.
const Producer = struct { digest: digest_rules.Digest, payload: []const u8 };

fn producerRun(ctx: *Context, _: []const u8) Error![]const u8 {
    const data = ctx.kindData(Producer);
    try ctx.exposePart("decl", data.digest);
    return data.payload;
}

fn clashRun(ctx: *Context, _: []const u8) Error![]const u8 {
    try ctx.exposePart("decl", @splat(1));
    try ctx.exposePart("decl", @splat(1));
    try ctx.exposePart("decl", @splat(2));
    return "";
}

test "a part published under two digests is a failure of the kind, and the same digest twice is one part" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    var clash: Kind = .{ .name = "clash", .identity = @splat(5), .run = clashRun };
    try fx.restartWith(.{}, &.{&clash});
    try std.testing.expectError(error.Failed, fx.runner.query(&clash, ""));
}

test "verify mode compares the parts table: a kind whose parts change under an unchanged result is found" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    var data: Producer = .{ .digest = @splat(1), .payload = "same payload" };
    var producer: Kind = .{ .name = "producer", .identity = @splat(6), .run = producerRun, .data = &data };
    try fx.restartWith(.{}, &.{&producer});
    _ = try fx.runner.query(&producer, "");
    // A new process, with the kind's parts different and its payload not.
    data.digest = @splat(2);
    try fx.restartWith(.{ .verify_every = 1 }, &.{&producer});
    try std.testing.expectError(error.VerifyMismatch, fx.runner.query(&producer, ""));
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const text = try fx.runner.lastMismatch(arena.allocator());
    try std.testing.expect(std.mem.indexOf(u8, text, "the parts table differs") != null);
}

test "explain names the part that changed, and finds nothing to recompute for a part that did not" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    _ = try fx.run(1);
    _ = try fx.run(3);
    try fx.restart(.{});
    fx.files.advance(second);
    try fx.files.write("/src/a.txt", "alpha changed");
    fx.files.advance(second);
    // The producer is recomputed by another query, so its record now holds the new parts.
    _ = try fx.run(0);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const named = try explain_rules.explain(&fx.runner, a, &fx.kind, "1");
    try std.testing.expect(named == .changed);
    try std.testing.expect(std.mem.startsWith(u8, named.changed.read, "part script"));
    try std.testing.expect(std.mem.startsWith(u8, named.changed.now, "part p0: "));
    const unnamed = try explain_rules.explain(&fx.runner, a, &fx.kind, "3");
    try std.testing.expect(unnamed == .served);
}

test "a record written in format 1 is still served, and is rewritten when its tuple is refreshed" {
    const fx = try Fixture.create(std.testing.allocator, .{ .nodes = &.{fixture_rules.fileNode("/src/a.txt", .concat)} });
    defer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    fx.files.advance(second);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try fx.recordPath(a, 0);
    const old: record_rules.Record = .{
        .kind = fx.kind.name,
        .identity = fx.kind.identity,
        .key = digest_rules.key(fx.kind.name, fx.kind.identity, "0"),
        .argument = "0",
        .result = digest_rules.hash("alpha"),
        .payload = .{ .inline_bytes = "alpha" },
        .reads = &.{.{ .file = .{ .path = "/src/a.txt", .present = true, .digest = digest_rules.hash("alpha"), .stat = world_rules.Stat.none } }},
    };
    const bytes = try record_rules.encodeFormat(a, old, 1);
    try std.testing.expect(try fx.runner.store.publish(a, path, bytes));
    try fx.restart(.{});
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
    // Serving it refreshed the file's tuple, which rewrites the record in the current format.
    const rewritten = (try fx.runner.store.load(a, path)).?;
    try std.testing.expectEqual(record_rules.format_version, std.mem.readInt(u32, rewritten[record_rules.magic.len..][0..4], .little));
}

test "a record of a format this engine does not know is a miss: the query is recomputed, not failed" {
    const fx = try aged(std.testing.allocator);
    defer fx.destroy();
    _ = try fx.run(0);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const path = try fx.recordPath(a, 0);
    const kept = (try fx.runner.store.load(a, path)).?;
    const future = try a.dupe(u8, kept);
    std.mem.writeInt(u32, future[record_rules.magic.len..][0..4], 3, .little);
    try std.testing.expect(try fx.runner.store.publish(a, path, future));
    try fx.restart(.{});
    _ = try fx.run(0);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.served));
}
