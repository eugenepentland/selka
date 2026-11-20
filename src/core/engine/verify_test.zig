//! Verify mode (spec §10), the soundness test (a read outside the context is found), in-flight markers (spec §8) and
//! a result identity smaller than the result's digest (spec §2).
const std = @import("std");
const fixture_rules = @import("fixture_test.zig");
const script = @import("kinds/script.zig");
const context = @import("context.zig");
const digest_rules = @import("digest.zig");
const store_rules = @import("store.zig");
const engine_rules = @import("engine.zig");
const Fixture = fixture_rules.Fixture;
const Context = context.Context;
const Kind = context.Kind;
const Error = context.Error;

const second = std.time.ns_per_s;
const one_file: script.Graph = .{ .nodes = &.{fixture_rules.fileNode("/src/a.txt", .concat)} };

/// State a kind reads without going through its context: the soundness hole verify mode exists to find. A test
/// changes it behind the engine's back.
const Hidden = struct { value: []const u8 };

fn leakyRun(ctx: *Context, _: []const u8) Error![]const u8 {
    const bytes = (try ctx.file("/src/a.txt")) orelse "~";
    return std.fmt.allocPrint(ctx.arena, "{s}+{s}", .{ bytes, ctx.kindData(Hidden).value });
}

fn shapeRun(ctx: *Context, _: []const u8) Error![]const u8 {
    const bytes = (try ctx.file("/src/a.txt")) orelse "~";
    if (std.mem.eql(u8, ctx.kindData(Hidden).value, "one")) return bytes;
    const extra = (try ctx.file("/src/b.txt")) orelse "~";
    return std.fmt.allocPrint(ctx.arena, "{s}{s}", .{ bytes, extra });
}

/// A fixture holding `/src/a.txt`, aged past the racy window.
fn aged(gpa: std.mem.Allocator, graph: script.Graph) fixture_rules.Failure!*Fixture {
    const fx = try Fixture.create(gpa, graph);
    errdefer fx.destroy();
    try fx.files.write("/src/a.txt", "alpha");
    fx.files.advance(second);
    return fx;
}

test "an honest kind is verified and agrees with its record" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    _ = try fx.run(0);
    try fx.restart(.{ .verify_every = 1 });
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.verified));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.verify_mismatches));
}

test "a read outside the context is served stale until verify mode recomputes it and fails" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    var hidden: Hidden = .{ .value = "one" };
    var leaky: Kind = .{ .name = "leaky", .identity = @splat(3), .run = leakyRun, .data = &hidden };
    try fx.restartWith(.{}, &.{&leaky});
    try std.testing.expectEqualStrings("alpha+one", try (try fx.runner.query(&leaky, "")).payload());
    hidden.value = "two";
    try fx.restartWith(.{}, &.{&leaky});
    try std.testing.expectEqualStrings("alpha+one", try (try fx.runner.query(&leaky, "")).payload());
    try fx.restartWith(.{ .verify_every = 1 }, &.{&leaky});
    try std.testing.expectError(error.VerifyMismatch, fx.runner.query(&leaky, ""));
    const text = try fx.runner.lastMismatch(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "E_ENGINE_VERIFY: leaky") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "none: the same reads gave another result") != null);
    try std.testing.expectEqual(@as(u64, 1), fx.runner.snapshot(&leaky).?.count(.verify_mismatches));
    // The mismatch healed the record: the next process is served what the kind gives now.
    try fx.restartWith(.{}, &.{&leaky});
    try std.testing.expectEqualStrings("alpha+two", try (try fx.runner.query(&leaky, "")).payload());
}

test "verify mode names the first read that no longer reproduces" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    var hidden: Hidden = .{ .value = "one" };
    var shaped: Kind = .{ .name = "shaped", .identity = @splat(4), .run = shapeRun, .data = &hidden };
    try fx.restartWith(.{}, &.{&shaped});
    _ = try fx.runner.query(&shaped, "");
    hidden.value = "two";
    try fx.restartWith(.{ .verify_every = 1 }, &.{&shaped});
    try std.testing.expectError(error.VerifyMismatch, fx.runner.query(&shaped, ""));
    const text = try fx.runner.lastMismatch(std.testing.allocator);
    defer std.testing.allocator.free(text);
    try std.testing.expect(std.mem.indexOf(u8, text, "first read that no longer reproduces: file /src/b.txt") != null);
}

test "the first divergence of two read lists is where they differ in what they saw or in length" {
    const record_rules = @import("record.zig");
    const a: record_rules.Read = .{ .exists = .{ .path = "/p", .present = true } };
    const b: record_rules.Read = .{ .exists = .{ .path = "/p", .present = false } };
    try std.testing.expectEqual(@as(?usize, null), engine_rules.firstDivergence(&.{ a, a }, &.{ a, a }));
    try std.testing.expectEqual(@as(?usize, 1), engine_rules.firstDivergence(&.{ a, a }, &.{ a, b }));
    try std.testing.expectEqual(@as(?usize, 1), engine_rules.firstDivergence(&.{a}, &.{ a, b }));
    try std.testing.expectEqual(@as(?usize, 0), engine_rules.firstDivergence(&.{a}, &.{}));
}

fn keyOfNode(fx: *Fixture, number: u32) std.fmt.BufPrintError!digest_rules.Digest {
    var text: [16]u8 = undefined;
    const argument = try std.fmt.bufPrint(&text, "{d}", .{number});
    return digest_rules.key(fx.kind.name, fx.kind.identity, argument);
}

test "a marker whose process is gone does not make an expensive kind wait" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    fx.kind.expensive = true;
    fx.kind.wait_ms = 5_000;
    try fx.restart(.{});
    const key = try keyOfNode(fx, 0);
    const marker = try store_rules.Marker.mine(std.testing.allocator, std.testing.io);
    defer std.testing.allocator.free(marker.host);
    const dead: store_rules.Marker = .{ .pid = 4_000_000, .start = 1, .host = marker.host };
    const text = try dead.text(std.testing.allocator);
    defer std.testing.allocator.free(text);
    const path = try fx.runner.store.inflightPath(std.testing.allocator, key);
    defer std.testing.allocator.free(path);
    try std.testing.expect(try fx.runner.store.publish(std.testing.allocator, path, text));
    const started = std.Io.Timestamp.now(std.testing.io, .awake).nanoseconds;
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expect(std.Io.Timestamp.now(std.testing.io, .awake).nanoseconds - started < 2 * second);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
    try std.testing.expect(!try store_rules.claimed(&fx.runner.store, std.testing.allocator, key));
}

test "a live marker is waited for up to the kind's bound, then the kind is computed" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    fx.kind.expensive = true;
    fx.kind.wait_ms = 150;
    try fx.restart(.{});
    const key = try keyOfNode(fx, 0);
    try std.testing.expectEqual(store_rules.Claim.claimed, try store_rules.claim(&fx.runner.store, std.testing.allocator, key));
    defer store_rules.release(&fx.runner.store, key);
    const started = std.Io.Timestamp.now(std.testing.io, .awake).nanoseconds;
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expect(std.Io.Timestamp.now(std.testing.io, .awake).nanoseconds - started >= 140 * std.time.ns_per_ms);
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.recomputed));
}

/// What another process does while a first holds the marker: compute the key, publish its record, release the marker.
fn otherProcess(fx: *Fixture, key: digest_rules.Digest, gpa: std.mem.Allocator) void {
    std.Io.sleep(std.testing.io, .fromMilliseconds(80), .awake) catch return;
    var twin = fx.kind;
    twin.expensive = false;
    var other = engine_rules.Engine.init(gpa, std.testing.io, fx.files.world(), .{ .work = fx.site.work }) catch return;
    defer other.deinit();
    other.register(&twin) catch return;
    _ = other.query(&twin, "0") catch return;
    store_rules.release(&other.store, key);
}

test "a process that finds a live marker is served the record the other process publishes" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    fx.kind.expensive = true;
    fx.kind.wait_ms = 5_000;
    try fx.restart(.{});
    const key = try keyOfNode(fx, 0);
    try std.testing.expectEqual(store_rules.Claim.claimed, try store_rules.claim(&fx.runner.store, std.testing.allocator, key));
    const other = try std.Thread.spawn(.{}, otherProcess, .{ fx, key, std.testing.allocator });
    defer other.join();
    try std.testing.expectEqualStrings("alpha", try fx.run(0));
    try std.testing.expectEqual(@as(u64, 1), fx.numbers().count(.served));
    try std.testing.expectEqual(@as(u64, 0), fx.numbers().count(.recomputed));
}

fn coarseRun(ctx: *Context, _: []const u8) Error![]const u8 {
    return (try ctx.file("/src/a.txt")) orelse "~";
}

fn coarseIdentity(payload: []const u8) digest_rules.Digest {
    return digest_rules.hash(payload[0..@min(1, payload.len)]);
}

fn outerRun(ctx: *Context, _: []const u8) Error![]const u8 {
    const inner: *const Kind = ctx.kindData(Kind);
    _ = try ctx.query(inner, "");
    return "done";
}

test "a kind's own result identity decides whether its dependents stay valid" {
    const fx = try aged(std.testing.allocator, one_file);
    defer fx.destroy();
    var coarse: Kind = .{ .name = "coarse", .identity = @splat(5), .run = coarseRun, .result_digest = coarseIdentity };
    var outer: Kind = .{ .name = "outer", .identity = @splat(6), .run = outerRun, .data = &coarse };
    try fx.restartWith(.{}, &.{ &coarse, &outer });
    _ = try fx.runner.query(&outer, "");
    try fx.restartWith(.{}, &.{ &coarse, &outer });
    try fx.files.write("/src/a.txt", "apple");
    fx.files.advance(second);
    try std.testing.expectEqualStrings("done", try (try fx.runner.query(&outer, "")).payload());
    try std.testing.expectEqual(@as(u64, 1), fx.runner.snapshot(&coarse).?.count(.recomputed));
    try std.testing.expectEqual(@as(u64, 1), fx.runner.snapshot(&coarse).?.count(.early_cutoffs));
    try std.testing.expectEqual(@as(u64, 1), fx.runner.snapshot(&outer).?.count(.served));
    try fx.restartWith(.{}, &.{ &coarse, &outer });
    try fx.files.write("/src/a.txt", "zebra");
    fx.files.advance(second);
    _ = try fx.runner.query(&outer, "");
    try std.testing.expectEqual(@as(u64, 1), fx.runner.snapshot(&outer).?.count(.recomputed));
}
