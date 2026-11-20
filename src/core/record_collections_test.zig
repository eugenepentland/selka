//! RB2, records that hold borrows stage 2: collections of borrows. A local `mut` list made empty whose every append stores a
//! borrow is a borrowed collection: it owns its buffer and lends its elements (`list[borrowed T]` in Core), and it holds what
//! its elements borrow until its last use. Each escape keeps the refusal it had before (the diagnostic, its location and its
//! repair: `experiments/record-collections-20261109`). Guest behaviour is `tests/lang/record_collections.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

const prelude =
    \\import lists
    \\import parallel
    \\
    \\record Spot:
    \\    net: bytes
    \\    x: int
    \\
    \\record Inner:
    \\    a: bytes
    \\    b: int
    \\
    \\record Keep:
    \\    spots: Spot[]
    \\    names: bytes[]
    \\
    \\record Lent:
    \\    a: bytes
    \\    b: int
    \\    names: bytes[]
    \\
    \\
;

/// The line the prelude ends on: a refusal's line in a case is this plus its line in the case.
const prelude_lines = std.mem.count(u8, prelude, "\n");

/// `source` (with the prelude) is refused with `code` at line `line` of the case (1-based) and a message holding `fragment`.
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, line: usize, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const text = try std.mem.concat(a, u8, &.{ prelude, source });
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    if (!std.mem.eql(u8, code, failure.code)) report("code {s}: {s}\n", .{ failure.code, failure.message });
    try std.testing.expectEqualStrings(code, failure.code);
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
    try std.testing.expectEqual(prelude_lines + line, std.mem.count(u8, text[0..failure.span.start], "\n") + 1);
}

/// Check `source` (with the prelude), which the declaration of a `from` clause must refuse with E_BORROW_SOURCE: every source is a plain text or
/// bytes parameter, which arrives as a view and cannot lend the result (lane CB, defect 4).
fn refusesDeclaration(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), try std.mem.concat(arena.allocator(), u8, &.{ prelude, source }));
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_BORROW_SOURCE", checked.diagnostics[0].code);
}

fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const checked = try support.checkedProgram(a, try std.mem.concat(a, u8, &.{ prelude, source }));
    unique.check(a, checked, &failure) catch |err| {
        report("refused: {s} {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try std.testing.expectEqualStrings("", failure.code);
}

const marker = "to give it, or `copy(";
const reused = "write `copy(";
const consuming = "; write `copy(";
/// The advice of a plain parameter's field that the function can take `own` (COPY-B1): that form first, then the copy.
const taking = "to take it (a caller then gives it with `own inner`, or copies if it reads it again), or write `copy(";

test "RB2 a local list of borrowed records or of borrowed text is a collection of borrows" {
    try accepts(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot[] = []
        \\    append(mut spots, Spot(net=owner.a, x=1))
        \\    mut names: bytes[] = []
        \\    for i in range(3):
        \\        append(mut names, owner.a)
        \\    append(mut names, b"lit")
        \\    return len(spots) + len(names) + len(names[0])
        \\
    );
}

test "RB2 a collection of borrows holds its sources to its last use: a write while it lives, a per-iteration owner, an alias" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut owner = Inner(a=b"abc", b=1)
        \\    mut names: bytes[] = []
        \\    append(mut names, owner.a)
        \\    owner.a = b"x"
        \\    return len(names[0])
        \\
    , "E_OWN_MARKER", 4, reused);
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut names: bytes[] = []
        \\    for i in range(3):
        \\        const tmp = Inner(a=b"x", b=i)
        \\        append(mut names, tmp.a)
        \\    return len(names)
        \\
    , "E_OWN_MARKER", 5, marker);
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut owner = Inner(a=b"abc", b=1)
        \\    mut names: bytes[] = []
        \\    append(mut names, owner.a)
        \\    const e = names[0]
        \\    owner.a = b"x"
        \\    return len(e)
        \\
    , "E_OWN_MARKER", 4, reused);
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut owner = Inner(a=b"abc", b=1)
        \\    mut names: bytes[] = []
        \\    for i in range(3):
        \\        owner.a = b"x"
        \\        append(mut names, owner.a)
        \\    return len(names)
        \\
    , "E_OWN_MARKER", 6, reused);
}

test "RB2 a collection of borrows keeps every escape's refusal: a stored or moved list, mut out, a return without from, a task, a mixed element" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot[] = []
        \\    append(mut spots, Spot(net=owner.a, x=2))
        \\    mut keep = Keep(spots=[], names=[])
        \\    keep.spots = own spots
        \\    return len(keep.spots)
        \\
    , "E_OWN_MARKER", 4, marker);
    try refuses(std.testing.allocator,
        \\func fill(inner: Inner, mut out: Spot[]):
        \\    append(mut out, Spot(net=inner.a, x=1))
        \\
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut out: Spot[] = []
        \\    fill(owner, mut out)
        \\    return len(out)
        \\
    , "E_SINGLE_OWNER_BORROW", 2, taking);
    try refuses(std.testing.allocator,
        \\func spots_of(inner: Inner) -> Spot[]:
        \\    mut out: Spot[] = []
        \\    append(mut out, Spot(net=inner.a, x=1))
        \\    return out
        \\
        \\func main() -> int:
        \\    return len(spots_of(Inner(a=b"abc", b=1)))
        \\
    , "E_SINGLE_OWNER_BORROW", 3, taking);
    try refuses(std.testing.allocator,
        \\record Item:
        \\    message: str
        \\    ref: bytes
        \\
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut items: Item[] = []
        \\    append(mut items, Item(message=f"m{owner.b}", ref=owner.a))
        \\    return len(items)
        \\
    , "E_OWN_MARKER", 8, marker);
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot[] = []
        \\    append(mut spots, Spot(net=owner.a, x=2))
        \\    mut other = own spots
        \\    return len(other)
        \\
    , "E_OWN_MARKER", 4, marker);
}

test "RB2 a task takes no collection of borrows, and a library call that stores into one keeps the owner's refusal" {
    try refuses(std.testing.allocator,
        \\func count(spots: Spot[]) -> int:
        \\    return len(spots)
        \\
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot[] = []
        \\    append(mut spots, Spot(net=owner.a, x=2))
        \\    with parallel.group() as group:
        \\        const task = group.submit(count, spots)
        \\        return task.result()
        \\
    , "E_OWN_MARKER", 7, marker);
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot[] = []
        \\    append(mut spots, Spot(net=owner.a, x=2))
        \\    lists.insert(mut spots, 0, Spot(net=b"q", x=1))
        \\    return len(spots)
        \\
    , "E_OWN_MARKER", 4, marker);
}

test "RB2 a list literal of borrows is a collection of borrows: a const and an argument built for one call; a record may lend one" {
    try accepts(std.testing.allocator,
        \\func size(names: bytes[]) -> int:
        \\    return len(names)
        \\
        \\func keep_len(k: Keep) -> int:
        \\    return len(k.spots) + len(k.names)
        \\
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    const names = [owner.a, b"de"]
        \\    mut spots: Spot[] = []
        \\    append(mut spots, Spot(net=owner.a, x=1))
        \\    return size(names) + size([owner.a]) + keep_len(Keep(spots=spots, names=names))
        \\
    );
}

test "RB2 a list literal of borrows keeps the owner's refusal when it is stored or returned" {
    try refuses(std.testing.allocator,
        \\func f(inner: Inner) -> bytes[]:
        \\    return [inner.a]
        \\
        \\func main() -> int:
        \\    return len(f(Inner(a=b"x", b=1)))
        \\
    , "E_SINGLE_OWNER_BORROW", 2, "");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut keep = Keep(spots=[], names=[])
        \\    keep.names = [owner.a]
        \\    return len(keep.names)
        \\
    , "E_OWN_MARKER", 4, "");
}

test "RB2 a new collection of borrows is not returned under from: the refusal is main's" {
    // A list returned under `from` stays a view of its sources (D-RB2-10). The source holds a list of bytes (`Lent.names`), so
    // the declaration can lend a `bytes[]` and the body's refusal is the one reported (a record with no list cannot lend
    // one: lane HC refuses that declaration with E_BORROW_SOURCE).
    try refuses(std.testing.allocator,
        \\func nets(inner: Lent) -> bytes[] from inner:
        \\    mut out: bytes[] = []
        \\    append(mut out, inner.a)
        \\    return out
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", 3, consuming);
    try refuses(std.testing.allocator,
        \\func pair(inner: Lent) -> bytes[] from inner:
        \\    return [inner.a, inner.a]
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", 2, consuming);
}

test "RB2 a list returned under from keeps the owner's refusal for an undeclared source, a local owner and a frame block" {
    try refuses(std.testing.allocator,
        \\func undeclared(inner: Lent, other: Lent) -> bytes[] from inner:
        \\    mut out: bytes[] = []
        \\    append(mut out, inner.a)
        \\    append(mut out, other.a)
        \\    return out
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", 3, consuming);
    try refuses(std.testing.allocator,
        \\func local_owner(inner: Lent) -> bytes[] from inner:
        \\    const mine = Lent(a=b"zz", b=1, names=[])
        \\    mut out: bytes[] = []
        \\    append(mut out, mine.a)
        \\    return out
        \\
        \\func main() -> int:
        \\    return 0
        \\
    , "E_OWN_MARKER", 4, marker);
    // A bytes parameter as the clause's only source cannot lend a list: the declaration refuses the clause first (lane CB).
    try refusesDeclaration(std.testing.allocator,
        \\func framed(net: bytes) -> Spot[] from net:
        \\    mut out: Spot[] = []
        \\    append(mut out, Spot(net=net, x=1))
        \\    return out
        \\
        \\func main() -> int:
        \\    return 0
        \\
    );
}

test "RB2 a local returned under from that joins borrowed list results is accepted, as before RB2" {
    try accepts(std.testing.allocator,
        \\func tags(keep: Keep) -> bytes[] from keep:
        \\    return keep.names
        \\
        \\func tail(keep: Keep) -> bytes[] from keep:
        \\    return keep.names[1:]
        \\
        \\func pick(keep: Keep, c: bool, n: int) -> bytes[] from keep:
        \\    mut names = tags(keep)
        \\    if c:
        \\        names = tail(keep)
        \\    for i in range(n):
        \\        names = tags(keep)
        \\    return names
        \\
        \\func main() -> int:
        \\    return len(pick(Keep(spots=[], names=[b"a", b"b"]), True, 2))
        \\
    );
}

test "RB2 a dictionary of borrows lends its values and keeps the owner's refusal for a write while it lives, a store or a return" {
    try accepts(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut table: dict[bytes, bytes] = {}
        \\    table[owner.a] = owner.a
        \\    mut names: bytes[] = []
        \\    append(mut names, owner.a)
        \\    names[0] = owner.a
        \\    return len(table[b"abc"]) + len(names[0])
        \\
    );
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut owner = Inner(a=b"abc", b=1)
        \\    mut d: dict[bytes, bytes] = {}
        \\    d[b"k"] = owner.a
        \\    owner.a = b"x"
        \\    return len(d[b"k"])
        \\
    , "E_OWN_MARKER", 4, reused);
    try refuses(std.testing.allocator,
        \\func table(inner: Inner) -> dict[bytes, bytes]:
        \\    mut d: dict[bytes, bytes] = {}
        \\    d[b"k"] = inner.a
        \\    return d
        \\
        \\func main() -> int:
        \\    return len(table(Inner(a=b"a", b=1)))
        \\
    , "E_SINGLE_OWNER_BORROW", 3, taking);
}

test "RB2 an option of a borrowed record is an element of borrows, and a write to its source while the list lives is refused" {
    try accepts(std.testing.allocator,
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot?[] = []
        \\    append(mut spots, Some(Spot(net=owner.a, x=4)))
        \\    append(mut spots, None)
        \\    return len(spots)
        \\
    );
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut owner = Inner(a=b"abc", b=1)
        \\    mut spots: Spot?[] = []
        \\    append(mut spots, Some(Spot(net=owner.a, x=4)))
        \\    owner.a = b"x"
        \\    return len(spots)
        \\
    , "E_OWN_MARKER", 4, reused);
}
