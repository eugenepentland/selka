//! A session that keeps every tree (a test run's check: no lowering host, not validation-only) finds held ownership proofs by
//! the receipts of its unchanged bodies, as `check` does, and still keeps every tree (lane EM, stage 3,
//! `experiments/test-loop-20261109/DECISIONS.md` EM3-1 to EM3-4). Its verdicts are the ones a full check gives.
const std = @import("std");
const frontend = @import("frontend.zig");
const ownership = @import("ownership_cache.zig");

/// What one check of the fixture said, and how its ownership validation found its proofs.
const Outcome = struct {
    valid: bool,
    diagnostics: []const u8,
    work: ownership.Work,
    /// Subjects proven by a semantic receipt, and by their tree's reach digest.
    receipts: usize = 0,
    reaches: usize = 0,
    /// Bodies the planner left out (none, for a session that keeps every tree).
    omitted: usize = 0,
    /// Whether `main`, which the planner never stands in for, has a proof subject by its reach digest.
    main_by_reach: bool = false,
};

/// How a check is run: cached or not, and with the receipt route on or off (`SELKA_OWNERSHIP_RECEIPTS`).
const Mode = enum { fresh, receipts, reaches };

/// Check the fixture as a test run's session does: every tree kept, allocation contracts checked.
fn kept(a: std.mem.Allocator, backing: std.mem.Allocator, root: []const u8, mode: Mode) !Outcome {
    var session = frontend.Session.init(backing, std.testing.io, root);
    defer session.deinit();
    if (mode != .fresh) {
        try session.enableCache(backing, try std.fs.path.join(a, &.{ root, "cache" }));
        session.caches.ownership.?.policy.receipts = mode == .receipts;
    }
    var messages: std.ArrayList(u8) = .empty;
    const valid = if (session.check(a, "main", &messages)) |_| true else |err| switch (err) {
        error.SourceError => false,
        else => return err,
    };
    var outcome: Outcome = .{ .valid = valid, .diagnostics = messages.items, .work = session.ownershipWork() };
    if (session.demandState()) |state| for (state.omitted) |left_out| {
        outcome.omitted += @intFromBool(left_out);
    };
    const cache = session.caches.ownership orelse return outcome;
    const program = session.graph.compilation.program orelse return outcome;
    for (cache.policy.subjects, 0..) |subject, index| {
        if (subject.digest == null) continue;
        if (subject.receipt) outcome.receipts += 1 else outcome.reaches += 1;
        if (index < program.functions.len and std.mem.eql(u8, program.functions[index].name, "main::main") and !subject.receipt) outcome.main_by_reach = true;
    }
    return outcome;
}

const callee_source =
    \\public func head(items: int[]) -> int[]:
    \\    return copy(items[0:1])
    \\
    \\
    \\public func take(own items: int[]) -> int:
    \\    return len(items)
    \\
    \\
    \\public func spare(x: int) -> int:
    \\    return x + 1
    \\
;
const caller_source =
    \\import lib
    \\
    \\
    \\func use() -> int:
    \\    mut xs: int[] = [1, 2]
    \\    const h = lib.head(xs)
    \\    append(mut xs, 3)
    \\    mut ys: int[] = [4]
    \\    return len(h) + lib.take(own ys) + lib.spare(1)
    \\
    \\
    \\func main() -> int:
    \\    return use()
    \\
;

fn write(directory: std.Io.Dir, lib: []const u8) !void {
    try directory.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = caller_source });
    try directory.writeFile(std.testing.io, .{ .sub_path = "lib.selka", .data = lib });
}

/// The fixture's warm verdicts with the route on and off and its fresh verdict, after `lib` replaces the callee module.
const Three = struct { receipts: Outcome, reaches: Outcome, fresh: Outcome };

fn afterEdit(a: std.mem.Allocator, backing: std.mem.Allocator, directory: std.Io.Dir, root: []const u8, lib: []const u8) !Three {
    try write(directory, callee_source);
    _ = try kept(a, backing, root, .receipts);
    _ = try kept(a, backing, root, .receipts);
    try write(directory, lib);
    const receipts = try kept(a, backing, root, .receipts);
    // The route off is the oracle: reset to the warm state first, so it meets the same edit.
    try write(directory, callee_source);
    _ = try kept(a, backing, root, .reaches);
    try write(directory, lib);
    return .{ .receipts = receipts, .reaches = try kept(a, backing, root, .reaches), .fresh = try kept(a, backing, root, .fresh) };
}

fn expectSameVerdicts(three: Three) !void {
    try std.testing.expectEqual(three.fresh.valid, three.receipts.valid);
    try std.testing.expectEqual(three.fresh.valid, three.reaches.valid);
    try std.testing.expectEqualStrings(three.fresh.diagnostics, three.receipts.diagnostics);
    try std.testing.expectEqualStrings(three.fresh.diagnostics, three.reaches.diagnostics);
}

test "a session that keeps every tree reuses held proofs by their receipts and leaves no body out" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const backing = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try write(directory.dir, callee_source);
    const cold = try kept(a, backing, root, .receipts);
    try std.testing.expect(cold.valid);
    const warm = try kept(a, backing, root, .receipts);
    try std.testing.expect(warm.valid);
    try std.testing.expectEqual(@as(usize, 0), warm.omitted);
    try std.testing.expect(warm.receipts > 0);
    try std.testing.expect(warm.work.reused > 0);
    // With the route off the same proofs are found by every function's reach digest.
    const reaching = try kept(a, backing, root, .reaches);
    try std.testing.expect(reaching.valid);
    try std.testing.expectEqual(@as(usize, 0), reaching.receipts);
    try std.testing.expect(reaching.reaches >= warm.receipts);
}

test "where the planner forms no receipt, the route proves a function by its tree's reach digest, never as proven" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const backing = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try write(directory.dir, callee_source);
    _ = try kept(a, backing, root, .receipts);
    const warm = try kept(a, backing, root, .receipts);
    // `main` never stands in for itself in the planner, so it has no receipt: its subject is its reach digest.
    try std.testing.expect(warm.main_by_reach);
    try std.testing.expect(warm.reaches > 0);
    // A body that moves what it then reads is refused when a receipt cannot vouch for it, whatever the record held before.
    const broken = try std.mem.replaceOwned(u8, a, caller_source, "    return use()", "    mut zs: int[] = [1]\n    const ws = own zs\n    return use() + len(zs) + len(ws)");
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "main.selka", .data = broken });
    const refused = try kept(a, backing, root, .receipts);
    try std.testing.expect(!refused.valid);
    try std.testing.expect(std.mem.indexOf(u8, refused.diagnostics, "E_SINGLE_OWNER_MOVED") != null);
    const fresh = try kept(a, backing, root, .fresh);
    try std.testing.expectEqualStrings(fresh.diagnostics, refused.diagnostics);
}

test "an edit that breaks ownership in a callee's body is refused in a warm session that keeps every tree, as a full check refuses it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const backing = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const body = try std.mem.replaceOwned(u8, a, callee_source, "    return len(items)", "    const other = own items\n    return len(items) + len(other)");
    const three = try afterEdit(a, backing, directory.dir, root, body);
    try std.testing.expect(!three.receipts.valid);
    try std.testing.expect(std.mem.indexOf(u8, three.receipts.diagnostics, "E_SINGLE_OWNER_MOVED") != null);
    try expectSameVerdicts(three);
}

test "an edit to a callee's signature refuses the unedited caller whose verdict depends on it, as a full check does" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const backing = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    // `head` now lends a part of its argument: the caller's `append(mut xs, 3)` while `h` is live is refused in `use`.
    const signature = try std.mem.replaceOwned(u8, a, callee_source, "public func head(items: int[]) -> int[]:\n    return copy(items[0:1])", "public func head(items: int[]) -> int[] from items:\n    return items[0:1]");
    const three = try afterEdit(a, backing, directory.dir, root, signature);
    try std.testing.expect(!three.receipts.valid);
    try std.testing.expect(std.mem.indexOf(u8, three.receipts.diagnostics, "main.selka") != null);
    try expectSameVerdicts(three);
}

test "a callee body edit that leaves the program valid gives the verdicts a full check gives, and keeps reusing the unedited proofs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const backing = std.testing.allocator;
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const harmless = try std.mem.replaceOwned(u8, a, callee_source, "    return x + 1", "    return x + 2");
    const three = try afterEdit(a, backing, directory.dir, root, harmless);
    try std.testing.expect(three.receipts.valid);
    try expectSameVerdicts(three);
    try std.testing.expect(three.receipts.work.reused > 0);
    var environment = std.process.Environ.Map.init(a);
    try std.testing.expect(ownership.receiptsFrom(&environment));
    try environment.put("SELKA_OWNERSHIP_RECEIPTS", "0");
    try std.testing.expect(!ownership.receiptsFrom(&environment));
}
