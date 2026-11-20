//! Lazy payloads (spec §5): a served query hands back a result whose payload is read when first used. Validating a query
//! never opens the object a large result is stored as, so an object that is gone, or damaged, is found at first use and
//! answered by running the query again, never by an error.
const std = @import("std");
const fixture_rules = @import("fixture_test.zig");
const script = @import("kinds/script.zig");
const context = @import("context.zig");
const digest_rules = @import("digest.zig");
const store_rules = @import("store.zig");
const Fixture = fixture_rules.Fixture;
const Context = context.Context;
const Kind = context.Kind;
const Error = context.Error;

const second = std.time.ns_per_s;

/// Larger than the object threshold, so a node that returns it stores it as an object.
const big_length = store_rules.object_threshold + 100;

/// The bytes of the large source file: a pattern, so a flipped byte is a different file.
const big: [big_length]u8 = fill: {
    @setEvalBranchQuota(20_000);
    var bytes: [big_length]u8 = undefined;
    for (&bytes, 0..) |*byte, at| byte.* = @intCast(at % 251);
    break :fill bytes;
};

/// Node 0 returns the large file, which makes its result an object; node 1 folds node 0's result to its length.
const object_graph: script.Graph = .{ .nodes = &.{
    fixture_rules.fileNode("/src/a.txt", .concat),
    .{ .ops = &.{.{ .node = 0 }}, .fold = .length },
} };

/// A fixture whose node 0 has been computed, so its record and its object are in the store.
fn withObject(gpa: std.mem.Allocator) anyerror!*Fixture {
    const fx = try Fixture.create(gpa, object_graph);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", &big);
    fx.files.advance(second);
    try std.testing.expectEqualSlices(u8, &big, try fx.run(0));
    return fx;
}

/// The path of the object node 0's result is stored as, in `a`.
fn objectFile(fx: *Fixture, a: std.mem.Allocator) anyerror![]const u8 {
    return fx.runner.store.objectPath(a, digest_rules.hash(&big));
}

/// Flip one byte of the stored object without changing its size.
fn damage(fx: *Fixture) anyerror!void {
    var arena: std.heap.ArenaAllocator = .init(fx.site.gpa);
    defer arena.deinit();
    const path = try objectFile(fx, arena.allocator());
    const bytes = (try fx.runner.store.load(arena.allocator(), path)).?;
    bytes[bytes.len / 2] ^= 0x01;
    try std.testing.expect(try fx.runner.store.publish(arena.allocator(), path, bytes));
}

/// Delete the stored object.
fn remove(fx: *Fixture) anyerror!void {
    var arena: std.heap.ArenaAllocator = .init(fx.site.gpa);
    defer arena.deinit();
    store_rules.discard(std.testing.io, try objectFile(fx, arena.allocator()));
}

test "a served query whose payload nobody asks for opens no object, even when the object is gone" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    try remove(fx);
    try fx.restart(.{});
    const result = try fx.runner.query(&fx.kind, "0");
    try std.testing.expectEqual(digest_rules.hash(&big), result.digest);
    const numbers = fx.numbers();
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.served));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.object_reads));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.object_misses));
}

test "the payload of a served object is read once, on first use, and kept for the revision" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    try fx.restart(.{});
    const result = try fx.runner.query(&fx.kind, "0");
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.object_reads));
    try std.testing.expectEqualSlices(u8, &big, try result.payload());
    try std.testing.expectEqualSlices(u8, &big, try result.payload());
    try std.testing.expectEqualSlices(u8, &big, try (try fx.runner.query(&fx.kind, "0")).payload());
    const numbers = fx.numbers();
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.object_reads));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.object_misses));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.recomputed));
}

test "a query that reads a served object's digest, not its bytes, is validated without opening it" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    _ = try fx.run(1);
    try remove(fx);
    try fx.restart(.{});
    try std.testing.expectEqualStrings("4196", try fx.run(1));
    const numbers = fx.numbers();
    try std.testing.expectEqual(@as(u64, 2), numbers.count(.served));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), numbers.count(.object_reads));
}

test "an object found missing at first use is a miss that recomputes, and the next process finds the object again" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    try remove(fx);
    try fx.restart(.{});
    const result = try fx.runner.query(&fx.kind, "0");
    try std.testing.expectEqualSlices(u8, &big, try result.payload());
    const numbers = fx.numbers();
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.served));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.object_reads));
    try std.testing.expectEqual(@as(u64, 1), numbers.count(.object_misses));
    try fx.restart(.{});
    try std.testing.expectEqualSlices(u8, &big, try fx.run(0));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.object_misses));
}

test "a flipped byte in an object is caught at first use, recomputed, and mended" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    try damage(fx);
    try fx.restart(.{});
    const result = try fx.runner.query(&fx.kind, "0");
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.object_misses));
    try std.testing.expectEqualSlices(u8, &big, try result.payload());
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_misses));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    try fx.restart(.{});
    try std.testing.expectEqualSlices(u8, &big, try fx.run(0));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.object_misses));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_reads));
}

test "an object cut short is caught at first use, recomputed, and mended" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    var arena: std.heap.ArenaAllocator = .init(fx.site.gpa);
    defer arena.deinit();
    const path = try objectFile(fx, arena.allocator());
    for ([_]usize{ big_length - 1, big_length / 2, 1, 0 }) |length| {
        try std.testing.expect(try fx.runner.store.publish(arena.allocator(), path, big[0..length]));
        try fx.restart(.{});
        const result = try fx.runner.query(&fx.kind, "0");
        try std.testing.expectEqualSlices(u8, &big, try result.payload());
        try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_misses));
        try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    }
    try fx.restart(.{});
    try std.testing.expectEqualSlices(u8, &big, try fx.run(0));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.object_misses));
}

test "verify mode reads a sampled object and compares it, and mends one that is gone or damaged without an error" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    try fx.restart(.{ .verify_every = 1 });
    _ = try fx.runner.query(&fx.kind, "0");
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.verified));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_reads));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.verify_mismatches));
    try damage(fx);
    try fx.restart(.{ .verify_every = 1 });
    const result = try fx.runner.query(&fx.kind, "0");
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_misses));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.verify_mismatches));
    try std.testing.expectEqualSlices(u8, &big, try result.payload());
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_misses));
}

/// State a kind reads without the context: what makes a recomputation give another result.
const Hidden = struct { value: []const u8 };

/// The large file followed by the hidden value, so the result is an object that the hidden value changes.
fn hiddenRun(ctx: *Context, _: []const u8) Error![]const u8 {
    const bytes = (try ctx.file("/src/a.txt")) orelse "~";
    return std.fmt.allocPrint(ctx.arena, "{s}{s}", .{ bytes, ctx.kindData(Hidden).value });
}

test "an object missing at first use whose recomputation gives another result is a verify mismatch, and the record is mended" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    var hidden: Hidden = .{ .value = "one" };
    var kind: Kind = .{ .name = "hidden-tail", .identity = @splat(5), .run = hiddenRun, .data = &hidden };
    try fx.restartWith(.{}, &.{&kind});
    const first = try (try fx.runner.query(&kind, "")).payload();
    try std.testing.expectEqual(@as(usize, big_length + 3), first.len);
    hidden.value = "two";
    try fx.restartWith(.{}, &.{&kind});
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const stale = try fx.runner.query(&kind, "");
    const object = try fx.runner.store.objectPath(arena.allocator(), stale.digest);
    store_rules.discard(std.testing.io, object);
    try std.testing.expectError(error.VerifyMismatch, stale.payload());
    const text = try fx.runner.lastMismatch(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "E_ENGINE_VERIFY: hidden-tail") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "at first use") != null);
    try std.testing.expectEqual(@as(u64, 1), fx.runner.snapshot(&kind).?.count(.verify_mismatches));
    try fx.restartWith(.{}, &.{&kind});
    const mended = try (try fx.runner.query(&kind, "")).payload();
    try std.testing.expect(std.mem.endsWith(u8, mended, "two"));
}

/// Read `result`'s payload and count a difference from `big`.
fn readAndCompare(result: context.Result, wrong: *std.atomic.Value(u32)) void {
    const bytes = result.payload() catch {
        _ = wrong.fetchAdd(1, .monotonic);
        return;
    };
    if (!std.mem.eql(u8, bytes, &big)) _ = wrong.fetchAdd(1, .monotonic);
}

/// Four threads use `result` at once.
fn readInThreads(result: context.Result, wrong: *std.atomic.Value(u32)) !void {
    var threads: [4]std.Thread = undefined;
    for (&threads) |*thread| thread.* = try std.Thread.spawn(.{}, readAndCompare, .{ result, wrong });
    for (threads) |thread| thread.join();
}

test "threads that use one served object at once read it, or recompute it, once" {
    const fx = try withObject(std.testing.allocator);
    defer fx.destroy();
    try remove(fx);
    try fx.restart(.{});
    const result = try fx.runner.query(&fx.kind, "0");
    var wrong: std.atomic.Value(u32) = .init(0);
    try readInThreads(result, &wrong);
    try std.testing.expectEqual(@as(u32, 0), wrong.load(.monotonic));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.object_misses));
}

test "a resident result answers its payload without a handle" {
    const result = context.Result.resident("bytes", @splat(1), &.{});
    try std.testing.expectEqualStrings("bytes", try result.payload());
    try std.testing.expect(result.body == .resident);
}

/// A lazy payload that counts how often it is loaded.
const Counting = struct {
    base: context.Lazy,
    calls: u32 = 0,

    fn load(lazy: *context.Lazy) Error![]const u8 {
        const self: *Counting = @fieldParentPtr("base", lazy);
        self.calls += 1;
        return "loaded";
    }
};

test "a lazy payload is loaded on the first get and answered from memory after it" {
    var counting: Counting = .{ .base = .{ .load = Counting.load, .io = std.testing.io } };
    const result: context.Result = .{ .digest = @splat(2), .body = .{ .lazy = &counting.base } };
    try std.testing.expectEqual(@as(u32, 0), counting.calls);
    try std.testing.expectEqualStrings("loaded", try result.payload());
    try std.testing.expectEqualStrings("loaded", try result.payload());
    try std.testing.expectEqual(@as(u32, 1), counting.calls);
}
