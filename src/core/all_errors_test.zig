//! The ownership check reports every independent refusal of a program (F-RC-214): one or more per refused function, each
//! function checked again past a refusal with a certain repair, and a refused check's recovered program judged without the
//! bodies that failed and their callers.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");
const recovered_ownership = @import("recovered_ownership.zig");

/// Every refusal `checkEvery` reports for a checked program, `text CODE` per line in source order.
fn listed(a: std.mem.Allocator, src: language.source.Source, every: *ownership.Every) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    for (ownership.distinct(every)) |failure| try out.print(a, "{s} {s}\n", .{ src.text(failure.span), failure.code });
    return out.items;
}

fn refusals(a: std.mem.Allocator, source: []const u8, every: *ownership.Every) ![]const u8 {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    try ownership.checkEvery(a, unit.program.?, null, unit.src.?, every);
    return listed(a, unit.src.?, every);
}

test "every refused function reports, and a missing own is read past to the next one of the same call" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var every: ownership.Every = .{};
    try std.testing.expectEqualStrings("first E_OWN_MARKER\nsecond E_OWN_MARKER\nthird E_OWN_MARKER\nlone E_OWN_MARKER\n", try refusals(arena.allocator(),
        \\record Three:
        \\    a: bytes
        \\    b: bytes
        \\    c: bytes
        \\func make(name: bytes) -> Three:
        \\    const first = name + b"1"
        \\    const second = name + b"2"
        \\    const third = name + b"3"
        \\    return Three(a=first, b=second, c=third)
        \\func other(name: bytes) -> Three:
        \\    const lone = name + b"x"
        \\    return Three(a=lone, b=b"", c=b"")
        \\func main() -> int:
        \\    return len(make(b"a").a) + len(other(b"c").a)
    , &every));
    try std.testing.expectEqual(@as(usize, 2), every.rejected.items.len);
    try std.testing.expect(!every.truncated);
}

test "a refusal with no certain repair ends its function (checkFunction offers no rewrite): a moved list used again is reported once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var every: ownership.Every = .{};
    try std.testing.expectEqualStrings("mut xs E_SINGLE_OWNER_MOVED\n", try refusals(arena.allocator(),
        \\func h(items: int[]) -> int:
        \\    mut xs = copy(items)
        \\    const kept = own xs
        \\    append(mut xs, 1)
        \\    append(mut xs, 2)
        \\    return len(xs) + len(kept)
        \\func main() -> int:
        \\    return h([1])
    , &every));
}

test "one function reports at most function_limit refusals" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var source: std.ArrayList(u8) = .empty;
    // The list is returned, so it owns its elements: each append needs `own` (a local list that only lends is RB2's).
    try source.appendSlice(a, "func many(name: bytes) -> bytes[]:\n    mut out: bytes[] = []\n");
    for (0..ownership.function_limit + 5) |index| try source.print(a, "    const v{d} = name + b\"{d}\"\n    append(mut out, v{d})\n", .{ index, index, index });
    try source.appendSlice(a, "    return out\nfunc main() -> int:\n    return len(many(b\"x\"))\n");
    var every: ownership.Every = .{};
    _ = try refusals(a, source.items, &every);
    try std.testing.expectEqual(@as(usize, ownership.function_limit), every.failures.items.len);
    try std.testing.expect(every.truncated);
}

test "a refused check's recovered program is judged without the body that failed and without its callers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "mixed.selka",
        \\record Pair:
        \\    left: bytes
        \\    right: bytes
        \\func broken(n: int) -> bytes:
        \\    return n + b"x"
        \\func pair(name: bytes) -> Pair:
        \\    const l = name + b"l"
        \\    return Pair(left=l, right=b"")
        \\func uses_broken(name: bytes) -> Pair:
        \\    const r = broken(1)
        \\    return Pair(left=r, right=b"")
        \\func main() -> int:
        \\    return len(pair(b"x").left)
    );
    try std.testing.expectError(error.SourceError, unit.check());
    const program = (try unit.holeProgram(false)).?;
    try std.testing.expect(recovered_ownership.recovered(program));
    const found = try recovered_ownership.collect(a, std.testing.allocator, program, unit.src);
    try std.testing.expectEqual(@as(usize, 1), found.len);
    try std.testing.expectEqualStrings("E_OWN_MARKER", found[0].code);
    try std.testing.expectEqualStrings("l", unit.src.text(found[0].span));
}

const two_copies =
    \\record Pair:
    \\    left: bytes
    \\    right: bytes
    \\func make(name: bytes, other: bytes) -> Pair:
    \\    return Pair(left=own name, right=own other)
    \\func again(name: bytes, other: bytes) -> Pair:
    \\    return Pair(left=own name, right=own other)
    \\func main() -> int:
    \\    return len(make(b"a", b"b").left) + len(again(b"c", b"d").left)
;

test "checkEvery makes each function's work and copyProgramIn's tables in Every.work and releases them all: the leak check sees none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    // The results go to the arena; every rewrite (two copy repairs a function) and every check's work to the testing allocator,
    // which fails the test if anything allocated there is still held when it ends.
    var every: ownership.Every = .{ .work = std.testing.allocator };
    try std.testing.expectEqualStrings("own name E_SINGLE_OWNER_BORROW\nown other E_SINGLE_OWNER_BORROW\nown name E_SINGLE_OWNER_BORROW\nown other E_SINGLE_OWNER_BORROW\n", try refusals(arena.allocator(), two_copies, &every));
    try std.testing.expectEqual(@as(usize, 2), every.rejected.items.len);
}

/// Run `checkEvery` on `two_copies` with its work allocator (over `backing`) failing at each allocation in turn, until a run
/// allocates nothing that fails; the number of runs that failed. Each failed run must end in `error.OutOfMemory` and hold
/// nothing of the work allocator.
fn failEachWorkAllocation(a: std.mem.Allocator, backing: std.mem.Allocator) !usize {
    const unit = try support.checkSource(a, two_copies);
    var index: usize = 0;
    while (true) : (index += 1) {
        var failing = std.testing.FailingAllocator.init(backing, .{ .fail_index = index });
        var every: ownership.Every = .{ .work = failing.allocator() };
        ownership.checkEvery(a, unit.program.?, null, unit.src.?, &every) catch |err| {
            try std.testing.expectEqual(error.OutOfMemory, err);
            try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
            continue;
        };
        try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
        if (!failing.has_induced_failure) return index;
    }
}

test "checkEvery releases copyProgramIn's tables and every function's work when an allocation of Every.work fails" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const unit = try support.checkSource(arena.allocator(), two_copies);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    var every: ownership.Every = .{ .work = failing.allocator() };
    try std.testing.expectError(error.OutOfMemory, ownership.checkEvery(arena.allocator(), unit.program.?, null, unit.src.?, &every));
    try std.testing.expect(try failEachWorkAllocation(arena.allocator(), std.testing.allocator) > 4);
}

test "the check lexes the source for a claim on copy once, and an allocation failure answers claimed without remembering it" {
    const declares = "func copy(value: int) -> int:\n    return value\n";
    const uses = "func count(value: bytes) -> bytes:\n    return copy(value)\n";
    var claim: ownership.CopyClaim = .{};
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    // The first ask runs out of memory: claimed, so no repair is offered, and nothing is remembered.
    try std.testing.expect(claim.claimed(failing.allocator(), uses));
    try std.testing.expectEqual(@as(?bool, null), claim.known);
    // The next ask lexes and learns that a use of `copy` is no claim.
    try std.testing.expect(!claim.claimed(std.testing.allocator, uses));
    try std.testing.expectEqual(@as(?bool, false), claim.known);
    // Learned, it allocates nothing and ignores the text it is given (a check has one source).
    failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expect(!claim.claimed(failing.allocator(), declares));
    var declared: ownership.CopyClaim = .{};
    try std.testing.expect(declared.claimed(std.testing.allocator, declares));
    try std.testing.expectEqual(@as(?bool, true), declared.known);
}

/// A module whose functions need every kind of repair `checkEvery` reads past: two copies in a row (`Pair`), three missing markers in a
/// row (`Three`), and one function of each beside a function that is accepted, so a rewrite of one is read by the checks of the next.
fn mixedRepairs(a: std.mem.Allocator, count: usize) ![]const u8 {
    var source: std.ArrayList(u8) = .empty;
    try source.appendSlice(a, "record Pair:\n    left: bytes\n    right: bytes\nrecord Three:\n    a: bytes\n    b: bytes\n    c: bytes\n" ++
        "func fine(name: bytes) -> bytes:\n    return name + b\"!\"\n");
    for (0..count) |index| {
        try source.print(a, "func pair_{d}(name: bytes, other: bytes) -> Pair:\n    return Pair(left=own name, right=own other)\n", .{index});
        try source.print(a, "func three_{d}(name: bytes) -> Three:\n    const first = name + b\"1\"\n    const second = name + b\"2\"\n    const third = name + b\"3\"\n    return Three(a=first, b=second, c=third)\n", .{index});
        try source.print(a, "func later_{d}(name: bytes) -> bytes:\n    return fine(name)\n", .{index});
    }
    try source.appendSlice(a, "func main() -> int:\n    return len(fine(b\"a\"))\n");
    return source.items;
}

test "the rewrites of repairs patch one shared copy of the tables and report what copying them for each rewrite reports" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const unit = try support.checkSource(a, try mixedRepairs(a, 12));
    try std.testing.expect(unit.passed);
    var shared: ownership.Every = .{ .work = std.testing.allocator };
    try ownership.checkEvery(a, unit.program.?, null, unit.src.?, &shared);
    var copied: ownership.Every = .{ .work = std.testing.allocator, .share_tables = false };
    try ownership.checkEvery(a, unit.program.?, null, unit.src.?, &copied);
    // 12 * (2 copies + 3 markers) refusals, in the same order and each distinct, whichever way the rewrites are made.
    try std.testing.expectEqual(@as(usize, 60), shared.failures.items.len);
    try std.testing.expectEqualStrings(try listed(a, unit.src.?, &copied), try listed(a, unit.src.?, &shared));
    try std.testing.expectEqual(copied.rejected.items.len, shared.rejected.items.len);
    try std.testing.expectEqual(copied.truncated, shared.truncated);
    // The program the check read is as it was: a second check of it reports the same again.
    var again: ownership.Every = .{ .work = std.testing.allocator };
    try ownership.checkEvery(a, unit.program.?, null, unit.src.?, &again);
    try std.testing.expectEqualStrings(try listed(a, unit.src.?, &copied), try listed(a, unit.src.?, &again));
}
