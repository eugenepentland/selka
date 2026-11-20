//! 1A: a record built only from borrows of block-backed places is a borrowed value. It may be a `const` local, a borrowed
//! `mut` local, a read-only argument of a call, or a value returned under `from`; its loans are its fields' owners, held to
//! its last use. The unsound neighbours stay refused: a change or move of an owner while the record is live (also through a
//! `mut` argument of the same call), a store of the record in a list or an owned field, a move of it, a return without
//! `from`, and a record that mixes a borrow with a fresh value. A refusal the borrow causes is reported as before 1A, at the
//! field that needs `own` or `copy(...)`, with its certain repair. A plain text, bytes or list parameter arrives as a view,
//! so a record of one keeps its copy. Guest behaviour is `tests/lang/borrowed_records.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

const prelude =
    \\record View:
    \\    net: bytes
    \\    n: int
    \\
    \\record Block:
    \\    power: bytes
    \\    gnd: bytes
    \\    names: bytes[]
    \\
    \\record Edge:
    \\    names: bytes[]
    \\    top: int
    \\
    \\record Holder:
    \\    view: View
    \\
    \\func size(v: View) -> int:
    \\    return len(v.net) + v.n
    \\
    \\func change(mut b: Block):
    \\    b.power = b"changed"
    \\
    \\func block() -> Block:
    \\    return Block(power=b"pp", gnd=b"g", names=[b"a", b"bb"])
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
    if (!std.mem.eql(u8, code, failure.code)) report("code {s}: {s}\n", .{ failure.code, failure.message });
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

/// Apply each round's certain repair until the program checks; `rounds` is how many repairs that takes, and `expected` a
/// fragment of the repaired source.
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
    unique.checkWithSource(a, unit.program.?, unit.src.?, &failure) catch |err| {
        report("still refused: {s} {s}\n{s}\n", .{ failure.code, failure.message, current });
        return err;
    };
    if (std.mem.indexOf(u8, current, expected) == null) report("missing '{s}' in:\n{s}\n", .{ expected, current });
    try std.testing.expect(std.mem.indexOf(u8, current, expected) != null);
}

test "1A a record of borrowed fields is a temporary argument, a const, a borrowed mut local and a from result" {
    try accepts(std.testing.allocator,
        \\func edge_len(e: Edge) -> int:
        \\    return e.top + len(e.names)
        \\
        \\func from_param(b: Block) -> int:
        \\    return size(View(net=b.power, n=1)) + size(View(net=b.gnd, n=2))
        \\
        \\func from_owned() -> int:
        \\    const net = b"ab" + b"c"
        \\    const wired = [b"x"]
        \\    return size(View(net=net, n=0)) + edge_len(Edge(names=wired, top=1)) + len(net) + len(wired)
        \\
        \\func local(b: Block, flag: bool) -> int:
        \\    const v = View(net=b.power, n=3)
        \\    mut w = View(net=b.power, n=1)
        \\    if flag:
        \\        w = View(net=b.gnd, n=2)
        \\    return size(v) + size(w) + len(v.net)
        \\
        \\func looped(b: Block) -> int:
        \\    mut total = 0
        \\    for name in b.names:
        \\        total += size(View(net=name, n=1))
        \\    return total
        \\
        \\func view_of(b: Block) -> View from b:
        \\    return View(net=b.power, n=7)
        \\
        \\func maybe(b: Block) -> View? from b:
        \\    return Some(View(net=b.gnd, n=8))
        \\
        \\func main() -> int:
        \\    const b = block()
        \\    return from_param(b) + from_owned() + local(b, True) + looped(b) + size(view_of(b))
        \\
    );
}

test "1A nested borrowed records, a borrowed record local as a field and a literal beside the borrows" {
    try accepts(std.testing.allocator,
        \\record Pair:
        \\    left: View
        \\    right: View
        \\
        \\func pair_len(p: Pair) -> int:
        \\    return size(p.left) + size(p.right)
        \\
        \\func main() -> int:
        \\    const b = block()
        \\    const v = View(net=b.power, n=1)
        \\    return pair_len(Pair(left=View(net=b.gnd, n=2), right=v)) + size(View(net=b"lit", n=0))
        \\
    );
}

test "1A a change or move of an owner while the record is live is refused, also through a mut argument of the same call (recordExpression)" {
    try refuses(std.testing.allocator,
        \\func consume(own net: bytes) -> int:
        \\    return len(net)
        \\
        \\func main() -> int:
        \\    const net = b"ab" + b"c"
        \\    const v = View(net=net, n=0)
        \\    const gone = consume(own net)
        \\    return size(v) + gone
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut b = block()
        \\    const v = View(net=b.power, n=0)
        \\    b.power = b"other"
        \\    return size(v)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut b = block()
        \\    const v = View(net=b.power, n=0)
        \\    change(mut b)
        \\    return size(v)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func both(v: View, mut b: Block) -> int:
        \\    return size(v)
        \\
        \\func main() -> int:
        \\    mut b = block()
        \\    return both(View(net=b.power, n=0), mut b)
        \\
    , "E_OWN_MARKER", "to keep both");
    try refuses(std.testing.allocator,
        \\func both(mut b: Block, v: View) -> int:
        \\    return size(v)
        \\
        \\func main() -> int:
        \\    mut b = block()
        \\    return both(mut b, View(net=b.power, n=0))
        \\
    , "E_SINGLE_OWNER_OVERLAP", "lends a part of 'b' to the call");
}

test "1A a borrowed record cannot be stored in a list or an owned field, moved, or returned without from" {
    // A local list made empty that only ever lends is a collection of borrows (RB2); one that is stored or moved owns its
    // elements, so storing a borrowed record in it keeps 1A's refusal.
    try refuses(std.testing.allocator,
        \\func keep(own views: View[]) -> int:
        \\    return len(views)
        \\
        \\func f(b: Block) -> int:
        \\    mut views: View[] = []
        \\    append(mut views, View(net=b.power, n=0))
        \\    return keep(own views)
        \\
        \\func main() -> int:
        \\    return f(block())
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func f(b: Block, mut views: View[]) -> int:
        \\    const v = View(net=b.power, n=0)
        \\    append(mut views, v)
        \\    return len(views)
        \\
        \\func main() -> int:
        \\    mut views: View[] = []
        \\    return f(block(), mut views)
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func f(b: Block) -> int:
        \\    const v = View(net=b.power, n=0)
        \\    mut h = Holder(view=View(net=b"x", n=1))
        \\    h.view = v
        \\    return size(h.view)
        \\
        \\func main() -> int:
        \\    return f(block())
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func keep(own v: View) -> int:
        \\    return size(v)
        \\
        \\func f(b: Block) -> int:
        \\    const v = View(net=b.power, n=0)
        \\    return keep(own v)
        \\
        \\func main() -> int:
        \\    return f(block())
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func f(b: Block) -> int:
        \\    const v = View(net=b.power, n=0)
        \\    return len(take_field(v))
        \\
        \\func take_field(own v: View) -> bytes:
        \\    return own v.net
        \\
        \\func main() -> int:
        \\    return f(block())
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func f(b: Block) -> bytes:
        \\    const v = View(net=b.power, n=0)
        \\    return own v.net
        \\
        \\func main() -> int:
        \\    return len(f(block()))
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func view_of(b: Block) -> View:
        \\    return View(net=b.power, n=0)
        \\
        \\func main() -> int:
        \\    return size(view_of(block()))
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func view_of(b: Block) -> View from b:
        \\    const net = copy(b.power)
        \\    return View(net=net, n=0)
        \\
        \\func main() -> int:
        \\    return size(view_of(block()))
        \\
    , "E_OWN_MARKER", "to give it, or ");
    try refuses(std.testing.allocator,
        \\func pick(b: Block, flag: bool) -> View from b:
        \\    if flag:
        \\        return View(net=b.power, n=0)
        \\    return View(net=copy(b.gnd), n=1)
        \\
        \\func main() -> int:
        \\    return size(pick(block(), True))
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func pick(b: Block, other: Block) -> View from b:
        \\    return View(net=other.power, n=0)
        \\
        \\func main() -> int:
        \\    return size(pick(block(), block()))
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
}

test "1A a record mixing a borrow with a fresh value, a view source, and a borrow of a per-iteration owner keep their refusals" {
    // A bare plain bytes parameter is a frame block since RB1 (record_sources_test.zig); a `const` that borrows one is a view.
    try refuses(std.testing.allocator,
        \\record Two:
        \\    a: bytes
        \\    b: bytes
        \\
        \\func two(t: Two) -> int:
        \\    return len(t.a) + len(t.b)
        \\
        \\func f(b: Block) -> int:
        \\    return two(Two(a=b.power, b=b"x" + b"y"))
        \\
        \\func main() -> int:
        \\    return f(block())
        \\
    , "E_SINGLE_OWNER_BORROW", "to keep both");
    try refuses(std.testing.allocator,
        \\func outer(s: bytes) -> int:
        \\    const t = s
        \\    return size(View(net=t, n=0))
        \\
        \\func main() -> int:
        \\    return outer(b"ab")
        \\
    , "E_OWN_MARKER", "initializer of `");
    try refuses(std.testing.allocator,
        \\func f(names: bytes[]) -> int:
        \\    const outer = b"o" + b"p"
        \\    mut v = View(net=outer, n=0)
        \\    for name in names:
        \\        const net = name + b"!"
        \\        v = View(net=net, n=0)
        \\    return size(v)
        \\
        \\func main() -> int:
        \\    return f([b"a"])
        \\
    , "E_OWN_MARKER", "to give it, or ");
}

test "1A the refusal a borrowed record causes keeps its repair, and the repairs reach a clean check (plainRecordRefusal)" {
    try repairs(std.testing.allocator,
        \\func main() -> int:
        \\    mut b = block()
        \\    const v = View(net=b.power, n=0)
        \\    change(mut b)
        \\    return size(v)
        \\
    , 1, "View(net=copy(b.power), n=0)");
    try repairs(std.testing.allocator,
        \\func keep(own views: View[]) -> int:
        \\    return len(views)
        \\
        \\func main() -> int:
        \\    const b = block()
        \\    mut views: View[] = []
        \\    const v = View(net=b.power, n=0)
        \\    append(mut views, v)
        \\    return keep(own views)
        \\
    , 2, "const v = View(net=own b.power, n=0)\n    append(mut views, own v)");
}

test "1A a borrowed record is an overlay record_make of lent fields, emitted in memory when it is wide, and never dropped" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Placement:
        \\    net: bytes
        \\    label: bytes
        \\    x: int
        \\    y: int
        \\    angle: int
        \\    side: int
        \\
        \\record Bank:
        \\    power: bytes
        \\    gnd: bytes
        \\
        \\func width(p: Placement) -> int:
        \\    return len(p.net) + len(p.label) + p.x + p.y + p.angle + p.side
        \\
        \\func placed(b: Bank) -> int:
        \\    return width(Placement(net=b.power, label=b.gnd, x=1, y=2, angle=3, side=4))
        \\
        \\func main() -> int:
        \\    return placed(Bank(power=b"VCC", gnd=b"GND"))
        \\
    ;
    const ir_text = try support.irText(a, source);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "record_make borrowed[record{bytes, bytes, i64, i64, i64, i64}]") != null);
    try std.testing.expect(std.mem.indexOf(u8, ir_text, "borrow bytes") != null);
    const owned = try support.ownedText(a, source);
    const placed_at = std.mem.indexOf(u8, owned, "fn placed(") orelse return error.TestUnexpectedResult;
    const placed_end = std.mem.indexOfPos(u8, owned, placed_at + 1, "\nfn ") orelse owned.len;
    try std.testing.expect(std.mem.indexOf(u8, owned[placed_at..placed_end], "drop") == null);
    const llvm = try support.llvmText(a, source);
    try std.testing.expect(std.mem.indexOf(u8, llvm, "@\"my.placed\"") != null);
}

/// A record of borrows held by a `mut` local and written through a `mut` argument (FR46): the shape that recursed without end.
const cursor_head =
    \\record Token:
    \\    text: str
    \\    pos: int
    \\
    \\record Parser:
    \\    toks: Token[]
    \\    i: int
    \\
    \\record Pair:
    \\    toks: Token[]
    \\    names: str[]
    \\    i: int
    \\
    \\func cur(p: Parser) -> Token from p:
    \\    return p.toks[p.i]
    \\
    \\func advance(mut p: Parser):
    \\    p.i += 1
    \\
    \\func advance_pair(mut p: Pair):
    \\    p.i += 1
    \\
    \\func tokens() -> Token[]:
    \\    return [Token(text="a", pos=0), Token(text="b", pos=2)]
    \\
    \\
;

const own_toks = "field `toks` of `Parser` needs its own value; write `own toks` to give it, or `copy(toks)` to keep both";

test "FR46 a record of borrows held by a mut local and written through a mut argument is refused at its field, and the check ends (plainRecordRefusal)" {
    try refuses(std.testing.allocator, cursor_head ++
        \\func first_pos() -> int:
        \\    const toks: Token[] = [Token(text="a", pos=0), Token(text="b", pos=2)]
        \\    mut p = Parser(toks=toks, i=0)
        \\    advance(mut p)
        \\    return cur(p).pos
        \\
        \\func main() -> int:
        \\    return first_pos()
        \\
    , "E_OWN_MARKER", own_toks);
    try repairs(std.testing.allocator, cursor_head ++
        \\func first_pos() -> int:
        \\    const toks: Token[] = [Token(text="a", pos=0), Token(text="b", pos=2)]
        \\    mut p = Parser(toks=toks, i=0)
        \\    advance(mut p)
        \\    return cur(p).pos
        \\
        \\func main() -> int:
        \\    return first_pos()
        \\
    , 1, "mut p = Parser(toks=own toks, i=0)");
}

test "FR46 two records, a record in a loop, two borrowed fields and a record returned each end with the refusal at the field (plainRecordRefusal)" {
    try refuses(std.testing.allocator, cursor_head ++
        \\func f() -> int:
        \\    const a: Token[] = tokens()
        \\    const b: Token[] = tokens()
        \\    mut p = Parser(toks=a, i=0)
        \\    mut q = Parser(toks=b, i=0)
        \\    advance(mut p)
        \\    advance(mut q)
        \\    return cur(p).pos + cur(q).pos
        \\
        \\func main() -> int:
        \\    return f()
        \\
    , "E_OWN_MARKER", "a bare `a` only lends the local `a`, and field `toks` of `Parser` needs its own value; write `own a` to give it");
    try refuses(std.testing.allocator, cursor_head ++
        \\func f(n: int) -> int:
        \\    const toks: Token[] = tokens()
        \\    mut total = 0
        \\    for k in range(n):
        \\        mut p = Parser(toks=toks, i=0)
        \\        advance(mut p)
        \\        total += cur(p).pos
        \\    return total
        \\
        \\func main() -> int:
        \\    return f(2)
        \\
    , "E_OWN_MARKER", "field `toks` of `Parser` needs its own value; write `copy(toks)` to keep both");
    try refuses(std.testing.allocator, cursor_head ++
        \\func f() -> int:
        \\    const toks: Token[] = tokens()
        \\    const names: str[] = ["x", "y"]
        \\    mut p = Pair(toks=toks, names=names, i=0)
        \\    advance_pair(mut p)
        \\    return p.i
        \\
        \\func main() -> int:
        \\    return f()
        \\
    , "E_OWN_MARKER", "field `toks` of `Pair` needs its own value");
    try refuses(std.testing.allocator, cursor_head ++
        \\func f(toks: Token[]) -> Parser from toks:
        \\    mut p = Parser(toks=toks, i=0)
        \\    advance(mut p)
        \\    return p
        \\
        \\func main() -> int:
        \\    return cur(f(tokens())).pos
        \\
    , "E_SINGLE_OWNER_BORROW", "field `toks` of `Parser` needs its own value");
}
