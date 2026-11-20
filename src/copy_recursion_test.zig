//! `W_COPY_IN_RECURSION` (O4): a copy of a function's context passed into its own recursive call warns, naming the
//! borrowed form; the fix deletes every copy of the constructor only where the result is a borrowed record the
//! ownership checker accepts, and the fixed program checks clean.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const copy_recursion = @import("copy_recursion.zig");

const prelude =
    \\record Block:
    \\    name: bytes
    \\    subs: Sub[]
    \\
    \\record Sub:
    \\    name: bytes
    \\    block: Block
    \\
    \\record Scope:
    \\    block: Block
    \\    name: bytes = b""
    \\    parent: Scope? = None
    \\
    \\func depth(scope: Scope) -> int:
    \\    match scope.parent:
    \\        case None:
    \\            return 0
    \\        case Some(p):
    \\            return 1 + depth(p)
    \\
    \\
;

const main_text =
    \\
    \\func main() -> int:
    \\    return walk(Scope(block=Block(name=b"t", subs=[])))
    \\
;

const Found = struct { count: usize, fixed: usize, edits: usize };

/// The `W_COPY_IN_RECURSION` warnings of `body` (between the prelude and `main`), how many carry a fix and how many edits.
fn warnings(body: []const u8) !Found {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const report = try fixture.check(a, try std.mem.concat(a, u8, &.{ prelude, body, main_text }));
    try report.expectAccepted();
    var found: Found = .{ .count = 0, .fixed = 0, .edits = 0 };
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, copy_recursion.code)) continue;
        found.count += 1;
        const fix = item.provenance.fix orelse continue;
        found.fixed += 1;
        found.edits += fix.count();
    }
    return found;
}

/// Apply every `W_COPY_IN_RECURSION` fix of `body` and return the fixed text, which must check with no such warning left.
fn fixed(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    const text = try std.mem.concat(a, u8, &.{ prelude, body, main_text });
    const report = try fixture.check(a, text);
    try report.expectAccepted();
    var edits: std.ArrayList(@import("diagnostic.zig").Edit) = .empty;
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, copy_recursion.code)) continue;
        const fix = item.provenance.fix orelse continue;
        for (0..fix.count()) |k| try edits.append(a, fix.at(k));
    }
    std.mem.sort(@import("diagnostic.zig").Edit, edits.items, {}, later);
    var current: []const u8 = text;
    for (edits.items) |edit| current = try std.mem.concat(a, u8, &.{ current[0..edit.span.start], edit.text, current[edit.span.end..] });
    const again = try fixture.check(a, current);
    try again.expectAccepted();
    for (again.diagnostics) |item| try t.expect(!std.mem.eql(u8, item.code, copy_recursion.code));
    return current;
}

fn later(_: void, left: @import("diagnostic.zig").Edit, right: @import("diagnostic.zig").Edit) bool {
    return left.span.start > right.span.start;
}

test "W_COPY_IN_RECURSION fixes the walk shape to a borrowed record that checks" {
    const body =
        \\func walk(scope: Scope) -> int:
        \\    mut total = depth(scope)
        \\    for sb in scope.block.subs:
        \\        total += walk(Scope(block=copy(sb.block), name=copy(sb.name), parent=Some(copy(scope))))
        \\    return total
        \\
    ;
    const found = try warnings(body);
    try t.expectEqual(@as(usize, 1), found.count);
    try t.expectEqual(@as(usize, 1), found.fixed);
    try t.expectEqual(@as(usize, 3), found.edits);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = try fixed(arena.allocator(), body);
    try t.expect(std.mem.indexOf(u8, text, "walk(Scope(block=sb.block, name=sb.name, parent=Some(scope)))") != null);
}

test "W_COPY_IN_RECURSION reports without a fix where the borrowed form is not certain" {
    // A fresh field beside the copies makes the record an owner.
    const mixed = try warnings(
        \\func walk(scope: Scope) -> int:
        \\    mut total = depth(scope)
        \\    for sb in scope.block.subs:
        \\        total += walk(Scope(block=copy(sb.block), name=b"x" + sb.name, parent=Some(copy(scope))))
        \\    return total
        \\
    );
    try t.expectEqual(@as(usize, 1), mixed.count);
    try t.expectEqual(@as(usize, 0), mixed.fixed);
    // An `own` parameter takes its argument: the record must be an owner.
    const owned = try warnings(
        \\func walk(own scope: Scope) -> int:
        \\    mut total = depth(scope)
        \\    for sb in scope.block.subs:
        \\        total += walk(Scope(block=copy(sb.block), parent=Some(copy(scope))))
        \\    return total
        \\
    );
    try t.expectEqual(@as(usize, 1), owned.count);
    try t.expectEqual(@as(usize, 0), owned.fixed);
}

test "W_COPY_IN_RECURSION stays silent for a copy of a local, a call that is not recursive, and a context passed in place" {
    const quiet = try warnings(
        \\func other(scope: Scope) -> int:
        \\    return depth(scope)
        \\
        \\func walk(scope: Scope) -> int:
        \\    mut total = depth(scope)
        \\    const made = Block(name=b"m", subs=[])
        \\    total += other(Scope(block=copy(scope.block), parent=Some(copy(scope))))
        \\    for sb in scope.block.subs:
        \\        total += walk(Scope(block=copy(made), parent=Some(scope)))
        \\        total += walk(Scope(block=sb.block, name=sb.name, parent=Some(scope)))
        \\    return total
        \\
    );
    try t.expectEqual(@as(usize, 0), quiet.count);
}

/// The `W_NEEDLESS_COPY` warnings with a fix, and their edits, among `text`'s diagnostics (RB1's record copies).
fn needless(text: []const u8) !Found {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try report.expectAccepted();
    var found: Found = .{ .count = 0, .fixed = 0, .edits = 0 };
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, "W_NEEDLESS_COPY")) continue;
        const fix = item.provenance.fix orelse continue;
        if (std.mem.indexOf(u8, item.message, "a record whose fields all borrow") == null) continue;
        found.count += 1;
        found.fixed += 1;
        found.edits += fix.count();
    }
    return found;
}

const sources_prelude =
    \\record Spot:
    \\    net: bytes
    \\    tag: str
    \\
    \\record Table:
    \\    counts: dict[bytes, int]
    \\    names: bytes[]
    \\
    \\record Opt:
    \\    ref: bytes?
    \\
    \\record Inner:
    \\    a: bytes
    \\
    \\func spot_len(s: Spot) -> int:
    \\    return len(s.net) + len(s.tag)
    \\
    \\func size(t: Table) -> int:
    \\    return len(t.counts) + len(t.names)
    \\
    \\func olen(o: Opt) -> int:
    \\    match o.ref:
    \\        case None:
    \\            return 0
    \\        case Some(r):
    \\            return len(r)
    \\
    \\func my_take(own s: Spot) -> int:
    \\    return len(s.net)
    \\
    \\
;

test "RB1 W_NEEDLESS_COPY fixes copies of read-only parameters and Some(place) in a record passed to a call" {
    const found = try needless(sources_prelude ++
        \\func f(net: bytes, tag: str, counts: dict[bytes, int], names: bytes[], inner: Inner) -> int:
        \\    return spot_len(Spot(net=copy(net), tag=copy(tag))) + size(Table(counts=copy(counts), names=copy(names))) + olen(Opt(ref=Some(copy(inner.a))))
        \\
        \\func main() -> int:
        \\    return f(b"a", "b", {}, [], Inner(a=b"c"))
        \\
    );
    try t.expectEqual(@as(usize, 3), found.count);
    try t.expectEqual(@as(usize, 5), found.edits);
}

test "RB1 W_NEEDLESS_COPY stays silent where the record would not borrow: a fresh field, an own parameter, a const, a mut parameter" {
    const found = try needless(sources_prelude ++
        \\func f(net: bytes, mut other: bytes) -> int:
        \\    mut total = spot_len(Spot(net=copy(net), tag="x" + "y"))
        \\    total += my_take(Spot(net=copy(net), tag=""))
        \\    const kept = Spot(net=copy(net), tag="")
        \\    total += spot_len(Spot(net=copy(other), tag=""))
        \\    return total + my_take(own kept)
        \\
        \\func main() -> int:
        \\    mut b = b"z"
        \\    return f(b"a", mut b)
        \\
    );
    try t.expectEqual(@as(usize, 0), found.count);
}
