//! RB1, records that hold borrows stage 1: every read-only place is a source of a borrowed record (1A). A bare plain
//! dictionary or set parameter is the caller's block, and `Some(place)` of a projection lends that place. Each escape keeps
//! the refusal it had before (the diagnostic, its location and its repair: `experiments/record-sources-20261109`). Guest
//! behaviour is `tests/lang/record_sources.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const ir = @import("ir.zig");
const report = std.debug.print;

const prelude =
    \\record Inner:
    \\    a: bytes
    \\    b: int
    \\
    \\record Table:
    \\    counts: dict[bytes, int]
    \\    tag: bytes
    \\
    \\record Opt:
    \\    ref: bytes?
    \\    n: int
    \\
    \\record Keep:
    \\    tables: Table[]
    \\    opts: Opt[]
    \\
    \\func table_size(t: Table) -> int:
    \\    return len(t.counts) + len(t.tag)
    \\
    \\func olen(o: Opt) -> int:
    \\    match o.ref:
    \\        case None:
    \\            return o.n
    \\        case Some(r):
    \\            return len(r) + o.n
    \\
    \\func take_table(own t: Table) -> int:
    \\    return len(t.counts)
    \\
    \\func take_opt(own o: Opt) -> int:
    \\    return o.n
    \\
    \\
;

/// The line the prelude ends on: a refusal's line in a case is this plus its line in the case.
const prelude_lines = std.mem.count(u8, prelude, "\n");

fn program(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ prelude, source });
}

/// `source` is refused with `code` at line `line` of the case (1-based) and a message holding `fragment`.
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, line: usize, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    // A program needs an entry; it follows the case, so the case's lines keep their numbers.
    const text = try std.mem.concat(a, u8, &.{ try program(a, source), "\nfunc main() -> int:\n    return 0\n" });
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    if (!std.mem.eql(u8, code, failure.code)) report("code {s}: {s}\n", .{ failure.code, failure.message });
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
    const at = failure.span.start;
    try std.testing.expectEqual(prelude_lines + line, std.mem.count(u8, text[0..at], "\n") + 1);
}

/// Check `source`, which the declaration of a `from` clause must refuse with E_BORROW_SOURCE: every source is a plain text or
/// bytes parameter, which arrives as a view and cannot lend the result (lane CB, defect 4).
fn refusesDeclaration(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), source);
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_BORROW_SOURCE", checked.diagnostics[0].code);
}

fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const checked = try support.checkedProgram(a, try program(a, source));
    unique.check(a, checked, &failure) catch |err| {
        report("refused: {s} {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try std.testing.expectEqualStrings("", failure.code);
}

const stored = "to keep both";

test "RB1 a dictionary or set parameter is a borrowed record source: an argument, a const, a from return" {
    try accepts(std.testing.allocator,
        \\record Names:
        \\    names: set[bytes]
        \\
        \\func f(counts: dict[bytes, int], inner: Inner) -> int:
        \\    const t = Table(counts=counts, tag=inner.a)
        \\    return table_size(Table(counts=counts, tag=b"")) + table_size(t)
        \\
        \\func g(counts: dict[bytes, int], inner: Inner) -> Table from counts, inner:
        \\    return Table(counts=counts, tag=inner.a)
        \\
        \\func h(names: set[bytes]) -> int:
        \\    const n = Names(names=names)
        \\    return len(n.names)
        \\
        \\func main() -> int:
        \\    mut d: dict[bytes, int] = {}
        \\    d[b"a"] = 1
        \\    const inner = Inner(a=b"xy", b=1)
        \\    return f(d, inner) + table_size(g(d, inner)) + h(set())
        \\
    );
}

test "RB1 Some of a projection is a borrowed record source: a field, an element, a dictionary value, a from return" {
    try accepts(std.testing.allocator,
        \\func of(inner: Inner) -> Opt from inner:
        \\    return Opt(ref=Some(inner.a), n=1)
        \\
        \\func elements(xs: bytes[], table: dict[bytes, bytes]) -> int:
        \\    mut total = 0
        \\    for i in range(len(xs)):
        \\        total += olen(Opt(ref=Some(xs[i]), n=0))
        \\    return total + olen(Opt(ref=Some(table[b"k"]), n=0))
        \\
        \\func main() -> int:
        \\    const owner = Inner(a=b"abc", b=1)
        \\    const o = Opt(ref=Some(owner.a), n=0)
        \\    return olen(o) + olen(of(owner))
        \\
    );
}

test "RB1 a record of a dictionary parameter keeps every escape's refusal: field store, return without from, move, mut out" {
    // An append to a local list made empty is a collection of borrows since RB2 (`record_collections_test.zig`).
    try accepts(std.testing.allocator,
        \\func f(counts: dict[bytes, int]) -> int:
        \\    mut out: Table[] = []
        \\    append(mut out, Table(counts=counts, tag=b""))
        \\    return len(out)
        \\
        \\func main() -> int:
        \\    mut d: dict[bytes, int] = {}
        \\    return f(d)
        \\
    );
    try refuses(std.testing.allocator,
        \\func f(counts: dict[bytes, int], mut keep: Keep) -> int:
        \\    keep.tables = [Table(counts=counts, tag=b"")]
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", 2, stored);
    try refuses(std.testing.allocator,
        \\func f(counts: dict[bytes, int]) -> Table:
        \\    return Table(counts=counts, tag=b"")
        \\
    , "E_SINGLE_OWNER_BORROW", 2, stored);
    try refuses(std.testing.allocator,
        \\func f(counts: dict[bytes, int]) -> int:
        \\    const t = Table(counts=counts, tag=b"")
        \\    return take_table(own t)
        \\
    , "E_SINGLE_OWNER_BORROW", 2, stored);
    try refuses(std.testing.allocator,
        \\func f(counts: dict[bytes, int], mut out: Table[]) -> int:
        \\    append(mut out, Table(counts=counts, tag=b""))
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", 2, stored);
}

test "RB1 a record of Some(place) keeps every escape's refusal: field store, return without from, move, a write while live" {
    // An append to a local list made empty is a collection of borrows since RB2 (`record_collections_test.zig`).
    try accepts(std.testing.allocator,
        \\func f(inner: Inner) -> int:
        \\    mut out: Opt[] = []
        \\    append(mut out, Opt(ref=Some(inner.a), n=0))
        \\    return len(out)
        \\
        \\func main() -> int:
        \\    return f(Inner(a=b"x", b=1))
        \\
    );
    try refuses(std.testing.allocator,
        \\func f(inner: Inner, mut keep: Keep) -> int:
        \\    keep.opts = [Opt(ref=Some(inner.a), n=0)]
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", 2, "");
    try refuses(std.testing.allocator,
        \\func f(inner: Inner) -> Opt:
        \\    return Opt(ref=Some(inner.a), n=0)
        \\
    , "E_SINGLE_OWNER_BORROW", 2, "");
    try refuses(std.testing.allocator,
        \\func f(inner: Inner) -> int:
        \\    const o = Opt(ref=Some(inner.a), n=0)
        \\    return take_opt(own o)
        \\
    , "E_SINGLE_OWNER_BORROW", 2, "");
    try refuses(std.testing.allocator,
        \\func f() -> int:
        \\    mut owner = Inner(a=b"abc", b=1)
        \\    const o = Opt(ref=Some(owner.a), n=0)
        \\    owner.a = b"zz"
        \\    return olen(o)
        \\
    , "E_OWN_MARKER", 3, "");
}

test "RB1 a from contract may return a record whose option field lends a projection of a declared owner" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const option = try module.intern(a, .{ .@"union" = &.{ .void, .bytes } });
    const record = try module.intern(a, .{ .record = &.{ option, .i64 } });
    const source = try module.intern(a, .{ .record = &.{ .bytes, .i64 } });
    const unrelated = try module.intern(a, .{ .record = &.{ .i64, .i64 } });
    const overlay = try module.borrowedType(a, record);
    try std.testing.expect(module.borrowCompatible(source, overlay));
    try std.testing.expect(!module.borrowCompatible(unrelated, overlay));
}

const frame_records =
    \\record Spot:
    \\    net: bytes
    \\    x: int
    \\
    \\record Line:
    \\    text: str
    \\    n: int
    \\
    \\record Names:
    \\    names: bytes[]
    \\
    \\func spot_len(s: Spot) -> int:
    \\    return len(s.net) + s.x
    \\
    \\func line_len(l: Line) -> int:
    \\    return len(l.text) + l.n
    \\
    \\func names_len(n: Names) -> int:
    \\    return len(n.names)
    \\
    \\
;

test "RB1 a text, bytes or list parameter held bare is a frame block: an argument, a const, a borrowed mut local" {
    try accepts(std.testing.allocator, frame_records ++
        \\func f(net: bytes, text: str, names: bytes[]) -> int:
        \\    mut total = spot_len(Spot(net=net, x=0))
        \\    const l = Line(text=text, n=1)
        \\    mut current = Names(names=names)
        \\    for i in range(2):
        \\        current = Names(names=names)
        \\        total += i
        \\    return total + line_len(l) + names_len(current)
        \\
        \\func main() -> int:
        \\    return f(b"ab", "cd", [b"e"])
        \\
    );
}

test "RB1 a record holding a frame block keeps every escape's refusal: return with or without from, move, task, mut out" {
    const frame_lines = std.mem.count(u8, frame_records, "\n");
    // A local list made empty may hold it since RB2: the list dies before the call returns (`record_collections_test.zig`).
    try accepts(std.testing.allocator, frame_records ++
        \\func f(net: bytes) -> int:
        \\    mut out: Spot[] = []
        \\    append(mut out, Spot(net=net, x=0))
        \\    return len(out)
        \\
        \\func main() -> int:
        \\    return f(b"VCC")
        \\
    );
    try refuses(std.testing.allocator, frame_records ++
        \\func f(net: bytes) -> Spot:
        \\    return Spot(net=net, x=0)
        \\
    , "E_SINGLE_OWNER_BORROW", frame_lines + 2, stored);
    // Under `from`, a frame block dies with the call. A text parameter is the clause's only source and cannot lend a record,
    // so the declaration refuses the clause first (lane CB).
    try refusesDeclaration(std.testing.allocator, frame_records ++
        \\func f(text: str) -> Line from text:
        \\    return Line(text=text, n=0)
        \\
    );
    try refuses(std.testing.allocator, frame_records ++
        \\func f(names: bytes[]) -> Names from names:
        \\    const n = Names(names=names)
        \\    return n
        \\
    , "E_SINGLE_OWNER_BORROW", frame_lines + 2, stored);
    try refuses(std.testing.allocator, frame_records ++
        \\func my_take(own s: Spot) -> int:
        \\    return s.x
        \\
        \\func f(net: bytes) -> int:
        \\    const s = Spot(net=net, x=0)
        \\    return my_take(own s)
        \\
    , "E_SINGLE_OWNER_BORROW", frame_lines + 5, stored);
    try refuses(std.testing.allocator, frame_records ++
        \\func f(net: bytes, mut out: Spot[]) -> int:
        \\    append(mut out, Spot(net=net, x=0))
        \\    return 0
        \\
    , "E_SINGLE_OWNER_BORROW", frame_lines + 2, stored);
}

test "RB1 a frame block is made where the record is built, with the text or list owner and none for bytes, and freed at every return" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = frame_records ++
        \\func f(net: bytes, text: str, build: bool) -> int:
        \\    if build:
        \\        return spot_len(Spot(net=net, x=0)) + line_len(Line(text=text, n=0)) + line_len(Line(text=text, n=1))
        \\    return len(net)
        \\
        \\func plain(net: bytes, text: str) -> int:
        \\    return len(net) + len(text)
        \\
        \\func main() -> int:
        \\    return f(b"ab", "cd", True) + plain(b"x", "y")
        \\
    ;
    const ir_text = try support.irText(a, source);
    const at = std.mem.indexOf(u8, ir_text, "fn f(") orelse return error.TestUnexpectedResult;
    const end = std.mem.indexOfPos(u8, ir_text, at + 1, "\nfn ") orelse ir_text.len;
    const body = ir_text[at..end];
    try std.testing.expectEqual(@as(usize, 3), std.mem.count(u8, body, "block_frame"));
    // Not in the entry block: a call that does not build the record copies nothing.
    const entry_end = std.mem.indexOf(u8, body, "\nb1:") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, body[0..entry_end], "block_frame") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, "block_frame bytes param0\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "block_frame str param1, param") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "drop") == null);
    const llvm = try support.llvmText(a, source);
    const f_at = std.mem.indexOf(u8, llvm, "define internal fastcc i64 @\"my.f\"(") orelse return error.TestUnexpectedResult;
    const f_end = std.mem.indexOfPos(u8, llvm, f_at, "\n}\n") orelse return error.TestUnexpectedResult;
    const f_text = llvm[f_at..f_end];
    // One slot per parameter, shared by both `Line` records, freed before each of the two returns.
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, f_text, "alloca ptr"));
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, f_text, "@myl_core_frame_block_release"));
    try std.testing.expectEqual(@as(usize, 2), std.mem.count(u8, f_text, "\n  ret "));
    const plain_at = std.mem.indexOf(u8, llvm, "define internal fastcc i64 @\"my.plain\"(") orelse return error.TestUnexpectedResult;
    const plain_end = std.mem.indexOfPos(u8, llvm, plain_at, "\n}\n") orelse return error.TestUnexpectedResult;
    try std.testing.expect(std.mem.indexOf(u8, llvm[plain_at..plain_end], "frame_block") == null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, llvm, "declare ptr @myl_core_frame_block("));
}

test "RB1 borrow_result never accepts a returned borrow that reaches a frame block, and the verifier types one" {
    const builder = @import("test_builder.zig");
    const valid = @import("borrow_result.zig").valid;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const record = try module.intern(a, .{ .record = &.{ .bytes, .i64 } });
    const overlay = try module.borrowedType(a, record);
    const contract: ir.BorrowContract = .{ .path = &.{}, .sources = &.{.{ .argument = 0 }} };
    var f: builder.Builder = .{ .arena = a, .function = .{ .name = "f", .signature = .{ .params = &.{.bytes_view}, .ret = overlay, .borrow = contract } } };
    const entry = try f.block();
    const param = try f.detached(.{ .op = .param, .ty = .bytes_view, .data = 0 });
    const frame = try f.put(entry, .{ .op = .block_frame, .ty = .bytes, .a = param });
    const lent = try f.put(entry, .{ .op = .borrow, .ty = .bytes, .a = frame });
    const zero = try f.detached(.{ .op = .iconst, .ty = .i64, .data = 0 });
    const made = try f.put(entry, .{ .op = .record_make, .ty = overlay, .data = try f.extra(&.{ lent, zero }) });
    _ = try f.put(entry, .{ .op = .ret, .ty = .void, .a = made });
    try std.testing.expect(!try valid(a, &module, &f.function, made));
}
