//! 4f: a `mut` local whose every assignment reads a place holds a borrow. The unsound neighbours stay refused: a change of
//! a root while the local is live (before or after a reassignment, and across the iterations of a loop), a change, move or
//! store of the local, a return without a `from` contract, and a borrow of an owner a loop makes again in each iteration.
//! A refusal that holding the borrow causes is reported as before 4f, at the store that needs `copy(...)`, with its
//! certain repair. Guest behaviour is `tests/lang/borrowed_mut_locals.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

const prelude =
    \\record Port:
    \\    name: bytes
    \\    net: bytes
    \\    pins: int[]
    \\
    \\record Block:
    \\    ports: Port[]
    \\    title: bytes
    \\
    \\
;

fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const unit = try support.checkSource(a, try std.mem.concat(a, u8, &.{ prelude, source }));
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
}

fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const program = try support.checkedProgram(a, try std.mem.concat(a, u8, &.{ prelude, source }));
    unique.check(a, program, &failure) catch |err| {
        report("refused: {s} {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try std.testing.expectEqualStrings("", failure.code);
}

/// Apply each round's certain repair until the program checks; `rounds` is how many repairs that takes.
fn repairs(backing: std.mem.Allocator, source: []const u8, rounds: usize, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var current = try std.mem.concat(a, u8, &.{ prelude, source });
    for (0..rounds) |_| {
        const unit = try support.checkSource(a, current);
        try std.testing.expect(unit.passed);
        var failure: unique.Failure = .{};
        try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
        const span = failure.copy.span orelse {
            try std.testing.expect(failure.repair == .explicit_fix);
            const edit = failure.repair.explicit_fix[0];
            current = try std.mem.concat(a, u8, &.{ current[0..edit.span.start], edit.text, current[edit.span.end..] });
            continue;
        };
        current = try std.mem.concat(a, u8, &.{ current[0..span.start], "copy(", current[span.start..span.end], ")", current[span.end..] });
    }
    const unit = try support.checkSource(a, current);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try unique.checkWithSource(a, unit.program.?, unit.src.?, &failure);
    try std.testing.expect(std.mem.indexOf(u8, current, expected) != null);
}

test "4f a mut local whose every assignment reads a place borrows, in branches and loops" {
    try accepts(std.testing.allocator,
        \\func chosen(p: Port) -> int:
        \\    mut net = p.name
        \\    if len(p.net) > 0:
        \\        net = p.net
        \\    return len(net)
        \\
        \\func longest(b: Block) -> int:
        \\    mut best = b.title
        \\    for p in b.ports:
        \\        if len(p.name) > len(best):
        \\            best = p.name
        \\    return len(best)
        \\
        \\func returned(p: Port) -> bytes from p:
        \\    mut net = p.name
        \\    if len(p.net) > 0:
        \\        net = p.net
        \\    return net
        \\
        \\func main() -> int:
        \\    const p = Port(name=b"ab", net=b"c", pins=[])
        \\    const b = Block(ports=[copy(p)], title=b"t")
        \\    return chosen(p) + longest(b) + len(returned(p))
        \\
    );
}

test "4f a root changed while the borrowing mut local is live is refused, also across loop iterations (borrowedMutLoopBack)" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut p = Port(name=b"ab", net=b"", pins=[1])
        \\    mut n = p.name
        \\    if len(p.net) > 0:
        \\        n = p.net
        \\    p.name = b"zz"
        \\    return len(n)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func main(out: Stream) -> int:
        \\    mut q = Port(name=b"ab", net=b"", pins=[1])
        \\    const b = Block(ports=[], title=b"t")
        \\    mut cur = b.title
        \\    for i in range(3):
        \\        q.name = b"changed"
        \\        print(out, len(cur))
        \\        cur = q.name
        \\    return 0
        \\
    , "E_OWN_MARKER", "to give it, or ");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut b = Block(ports=[Port(name=b"ab", net=b"", pins=[1])], title=b"t")
        \\    mut n = b.title
        \\    if len(b.ports) > 0:
        \\        n = b.ports[0].name
        \\    b.ports[0].name = b"changed"
        \\    return len(n)
        \\
    , "E_OWN_MARKER", "to keep both");
}

test "4f a borrowing mut local cannot be changed, moved, stored or returned without from" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const p = Port(name=b"ab", net=b"", pins=[1])
        \\    mut pins = p.pins
        \\    if len(p.net) > 0:
        \\        pins = p.pins
        \\    append(mut pins, 4)
        \\    return len(pins)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func eat(own x: bytes) -> int:
        \\    return len(x)
        \\
        \\func main() -> int:
        \\    const p = Port(name=b"ab", net=b"", pins=[1])
        \\    mut n = p.name
        \\    if len(p.net) > 0:
        \\        n = p.net
        \\    return eat(own n)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const p = Port(name=b"ab", net=b"", pins=[1])
        \\    mut n = p.name
        \\    if len(p.net) > 0:
        \\        n = p.net
        \\    mut keep: bytes[] = []
        \\    append(mut keep, n)
        \\    return len(keep)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func pick(p: Port) -> bytes:
        \\    mut n = p.name
        \\    if len(p.net) > 0:
        \\        n = p.net
        \\    return n
        \\
        \\func main() -> int:
        \\    return len(pick(Port(name=b"ab", net=b"", pins=[1])))
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
}

test "4f a borrowing mut local may not outlive an owner a loop makes again in each iteration" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const b = Block(ports=[], title=b"t")
        \\    mut n = b.title
        \\    for i in range(3):
        \\        const p = Port(name=b"ab", net=b"", pins=[1])
        \\        if i == 1:
        \\            n = p.name
        \\    return len(n)
        \\
    , "E_OWN_MARKER", "to give it, or ");
}

test "4f the refusal a borrow causes keeps the copy repair, and the repairs reach a clean check (finishFunction)" {
    try repairs(std.testing.allocator,
        \\func main() -> int:
        \\    const p = Port(name=b"ab", net=b"cd", pins=[1])
        \\    mut pins = p.pins
        \\    if len(p.net) > 0:
        \\        pins = p.pins
        \\    append(mut pins, 4)
        \\    return len(pins)
        \\
    , 2, "mut pins = copy(p.pins)\n    if len(p.net) > 0:\n        pins = own p.pins\n");
}

test "4f a mut local stored from elements borrows the list, which stays held, and a change of it keeps the element repair" {
    try accepts(std.testing.allocator,
        \\func main() -> int:
        \\    const rows = [[1], [2, 3]]
        \\    mut longest = rows[0]
        \\    if len(rows[1]) > len(longest):
        \\        longest = rows[1]
        \\    return len(longest)
        \\
    );
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut rows = [[1], [2, 3]]
        \\    mut longest = rows[0]
        \\    if len(rows[1]) > len(longest):
        \\        longest = rows[1]
        \\    append(mut rows, [4])
        \\    return len(longest)
        \\
    , "E_SINGLE_OWNER_BORROW", "needs its own value");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const rows = [[1], [2, 3]]
        \\    mut longest = rows[0]
        \\    if len(rows[1]) > len(longest):
        \\        longest = rows[1]
        \\    append(mut longest, 4)
        \\    return len(longest)
        \\
    , "E_SINGLE_OWNER_BORROW", "needs its own value");
}
