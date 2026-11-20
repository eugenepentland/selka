//! Views stored into owned storage or returned from local owners need an
//! explicit copy. Declared parameter views stay borrowed through standard
//! wrappers; mixed borrowed/fresh returns retain their R5 copy repair.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

/// `source` with the entry point a whole-program check needs.
fn withEntry(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ source, "\n\nfunc main() -> int:\n    return 0\n" });
}

/// Check `source`, which must pass, with the ownership contract.
fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, source);
    var failure: unique.Failure = .{};
    try unique.check(a, try support.checkedProgram(a, text), &failure);
}

/// Check `source`, which must be refused with `code` and exactly `message`, and
/// whose copy repair wraps exactly `wrapped`. The rendered JSON diagnostic must
/// carry the two repair edits `copy(` and `)`.
fn refuses(backing: std.mem.Allocator, source: []const u8, code: []const u8, message: []const u8, wrapped: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const text = try withEntry(a, source);
    var failure: unique.Failure = .{};
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    try std.testing.expectEqualStrings(message, failure.message);
    if (std.mem.eql(u8, code, "E_BORROW_MIXED")) try std.testing.expectEqual(language.ownership_rules.Rule.R5, failure.rule.?);
    if (std.mem.eql(u8, code, "E_SINGLE_OWNER_BORROW")) try std.testing.expectEqual(language.ownership_rules.Rule.R3, failure.rule.?);
    const spans = if (failure.copy.span) |span| &[_]language.source.Span{span} else failure.copy.borrowed;
    try std.testing.expectEqual(@as(usize, 1), spans.len);
    const span = spans[0];
    try std.testing.expectEqualStrings(wrapped, text[span.start..span.end]);
    var rendered: std.ArrayList(u8) = .empty;
    const src = try language.source.Source.init(a, "hidden.selka", text);
    try unique.render(a, src, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\"copy(\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\")\"") != null);
}

const make_text =
    \\func make() -> str:
    \\    return "abcdefgh"
    \\
    \\
;

test "rule C hidden copy C1: a slice assigned to an owned mut local is refused with the copy repair" {
    try refuses(std.testing.allocator, make_text ++
        \\func use() -> int:
        \\    const data = make()
        \\    mut cur = "start"
        \\    cur = data[0:2]
        \\    return len(cur)
        \\
    , "E_SLICE_ESCAPES", "`data[0:2]` is lent by the local `data`, and the `mut` local `cur` needs its own value; write `copy(data[0:2])` to keep both", "data[0:2]");
}

// A `mut` local stored only from slices of places borrows them (H4); one that also takes a fresh value owns it, so its slice
// store is refused.
test "rule C hidden copy C1: a slice declared into an owned mut local is refused, and a view binding is not" {
    try refuses(std.testing.allocator, make_text ++
        \\func use() -> int:
        \\    const data = make()
        \\    mut cur = data[0:2]
        \\    cur = cur + "!"
        \\    return len(cur)
        \\
    , "E_SLICE_ESCAPES", "`data[0:2]` is lent by the local `data`, and the `mut` local `cur` needs its own value; write `copy(data[0:2])` to keep both", "data[0:2]");
    try accepts(std.testing.allocator, make_text ++
        \\func use() -> int:
        \\    const data = make()
        \\    const piece = data[0:2]
        \\    return len(piece)
        \\
    );
}

test "rule C hidden copy C1: a deferred const that is a slice on one path and owned on another is refused" {
    try refuses(std.testing.allocator, make_text ++
        \\func use(flag: bool) -> int:
        \\    const data = make()
        \\    const h: str
        \\    if flag:
        \\        h = data[0:2]
        \\    else:
        \\        h = "zz"
        \\    return len(h)
        \\
    , "E_SLICE_ESCAPES", "`data[0:2]` is lent by the local `data`, and the local `h` needs its own value; write `copy(data[0:2])` to keep both", "data[0:2]");
}

test "rule C hidden copy C1: ownedViewStore names the binding and replaces its own marker in the repair" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = make_text ++
        // migrate-embedded: skip marked view escape and exact copy repair witness
        \\func use() -> int:
        \\    const data = make()
        \\    const piece = data[0:4]
        \\    mut cur = own piece
        \\    return len(cur)
        \\
    ;
    const text = try withEntry(a, source);
    const unit = try support.checkSource(a, text);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_SLICE_ESCAPES", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.V2, failure.rule.?);
    try std.testing.expectEqualStrings("`piece` is lent by the local `data`, and the `mut` local `cur` needs its own value; write `copy(piece)` to keep both", failure.message);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 2), edits.len);
    try std.testing.expectEqualStrings("own ", text[edits[0].span.start..edits[0].span.end]);
    try std.testing.expectEqualStrings("copy(", edits[0].text);
    try std.testing.expectEqualStrings("piece", text[edits[0].span.end..edits[1].span.start]);
    try std.testing.expectEqual(edits[1].span.start, edits[1].span.end);
    try std.testing.expectEqualStrings(")", edits[1].text);
    var rendered: std.ArrayList(u8) = .empty;
    try unique.render(a, unit.src.?, failure, .json, &rendered);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\"copy(\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, rendered.items, "\"text\":\")\"") != null);
    const fixed = try std.mem.concat(a, u8, &.{
        text[0..edits[0].span.start],                 edits[0].text,
        text[edits[0].span.end..edits[1].span.start], edits[1].text,
        text[edits[1].span.end..],
    });
    const expected = try std.mem.replaceOwned(u8, a, text, "own piece", "copy(piece)");
    try std.testing.expectEqualStrings(expected, fixed);
    const repaired = try support.checkSource(a, fixed);
    try std.testing.expect(repaired.passed);
    failure = .{};
    try unique.checkWithSource(a, repaired.program.?, repaired.src.?, &failure);
}

test "rule C hidden copy C1: explicit copies and a deferred const that is a view on every path are accepted" {
    try accepts(std.testing.allocator, make_text ++
        \\func use() -> int:
        \\    const data = make()
        \\    mut cur = copy(data[0:2])
        \\    cur = copy(data[1:3])
        \\    return len(cur)
        \\
    );
    try accepts(std.testing.allocator, make_text ++
        \\func use(flag: bool) -> int:
        \\    const data = make()
        \\    const h: str
        \\    if flag:
        \\        h = data[0:2]
        \\    else:
        \\        h = data[1:3]
        \\    return len(h)
        \\
    );
}

test "rule C hidden copy C1: a view of a temporary value names no local in its repair" {
    try refuses(std.testing.allocator, make_text ++
        \\func use() -> int:
        \\    mut cur = "start"
        \\    cur = (make() + "x")[0:2]
        \\    return len(cur)
        \\
    , "E_SLICE_ESCAPES", "`(make() + \"x\")[0:2]` is lent by a temporary value, and the `mut` local `cur` needs its own value; write `copy((make() + \"x\")[0:2])` to keep both", "(make() + \"x\")[0:2]");
}

test "rule C hidden copy C2: a returned local bytes slice is refused with the copy repair" {
    try refuses(std.testing.allocator,
        \\func head() -> bytes:
        \\    const source = copy(b"local bytes")
        \\    return source[0:4]
        \\
        \\
    , "E_SLICE_ESCAPES", "`source[0:4]` is lent by the local `source`, and the returned value would keep it after `source` ends; write `copy(source[0:4])` to keep both", "source[0:4]");
}

test "rule C hidden copy C2 and C3: a pure view return of str stays free" {
    try accepts(std.testing.allocator,
        \\func head(source: str) -> str from source:
        \\    return source[0:4]
        \\
        \\
    );
}

test "rule C hidden copy C3: a str view beside allocated storage is refused with its R5 copy repair" {
    try refuses(std.testing.allocator,
        \\func line_at(text: str, n: int) -> str from text:
        \\    if n < 0:
        \\        return "none" + str(n)
        \\    return text[0:n]
        \\
        \\
    , "E_BORROW_MIXED", "`line_at` returns a borrow on line 4 and a new value on line 3; write copy(...) around each borrowed return", "text[0:n]");
}

test "rule C hidden copy C3: a declared view wrapped in Some keeps None neutral" {
    try accepts(std.testing.allocator,
        \\func head(source: str) -> str? from source:
        \\    if len(source) < 4:
        \\        return None
        \\    return Some(source[0:4])
        \\
        \\
    );
}

test "rule C hidden copy C3: a declared view returned as a fails success keeps its owned failure" {
    try accepts(std.testing.allocator,
        \\func head(source: str) -> str from source fails str:
        \\    if len(source) < 4:
        \\        fail "short"
        \\    return source[0:4]
        \\
        \\
    );
}

test "rule C hidden copy C3: a view binding of the parameter returned on a mixed path is refused with the copy repair" {
    try refuses(std.testing.allocator,
        \\func line_at(text: str, n: int) -> str from text:
        \\    if n < 0:
        \\        return "none" + str(n)
        \\    const piece = text[0:n]
        \\    return piece
        \\
        \\
    , "E_BORROW_MIXED", "`line_at` returns a borrow on line 5 and a new value on line 3; write copy(...) around each borrowed return", "piece");
}

test "rule C hidden copy C1: the refusal names what an owned list or bytes local holds" {
    try refuses(std.testing.allocator,
        \\func use(xs: int[]) -> int:
        \\    mut part = xs[1:3]
        \\    if len(part) > 1:
        \\        part = [0]
        \\    return len(part)
        \\
    , "E_SLICE_ESCAPES", "`xs[1:3]` is lent by the plain parameter `xs`, and the `mut` local `part` needs its own value; write `copy(xs[1:3])` to keep both", "xs[1:3]");
    try refuses(std.testing.allocator,
        \\func use(data: bytes) -> int:
        \\    mut part = data[0:2]
        \\    if len(part) > 1:
        \\        part = copy(data)
        \\    return len(part)
        \\
    , "E_SLICE_ESCAPES", "`data[0:2]` is lent by the plain parameter `data`, and the `mut` local `part` needs its own value; write `copy(data[0:2])` to keep both", "data[0:2]");
}

test "rule C hidden copy C8: a view-returning call stored in a record field is refused with the copy repair" {
    try refuses(std.testing.allocator,
        \\record R:
        \\    name: str
        \\func head(source: str) -> str from source:
        \\    return source[0:4]
        \\func use(data: str) -> int:
        \\    const r = R(name=head(data))
        \\    return len(r.name)
        \\
        \\
    , "E_SLICE_ESCAPES", "`head(data)` is lent by the plain parameter `data`, and field `name` of `R` needs its own value; write `copy(head(data))` to keep both", "head(data)");
}

test "rule C hidden copy C8: a view-returning call appended to an owned list is refused with the copy repair" {
    try refuses(std.testing.allocator,
        \\func head(source: str) -> str from source:
        \\    return source[0:4]
        \\func use(data: str) -> int:
        \\    mut names: str[] = []
        \\    append(mut names, head(data))
        \\    return len(names)
        \\
        \\
    , "E_SLICE_ESCAPES", "`head(data)` is lent by the plain parameter `data`, and the list `names` needs its own value; write `copy(head(data))` to keep both", "head(data)");
}

test "rule C hidden copy C8: a view-returning call bound to an owned mut local is refused with the copy repair" {
    try refuses(std.testing.allocator,
        \\func head(source: str) -> str from source:
        \\    return source[0:4]
        \\func use(data: str) -> int:
        \\    mut cur = head(data)
        \\    cur = copy(cur)
        \\    return len(cur)
        \\
        \\
    , "E_SINGLE_OWNER_BORROW", "`head(data)` is lent by the plain parameter `data`, and the `mut` local `cur` needs its own value; write `copy(head(data))` to keep both", "head(data)");
}

test "rule C hidden copy C8: a declared view-returning call can be forwarded with the same source" {
    try accepts(std.testing.allocator,
        \\func head(source: str) -> str from source:
        \\    return source[0:4]
        \\func lead(data: str) -> str from data:
        \\    return head(data)
        \\
        \\
    );
}

test "rule C hidden copy C8: the copied call and a call read in place are accepted" {
    try accepts(std.testing.allocator,
        \\record R:
        \\    name: str
        \\func head(source: str) -> str from source:
        \\    return source[0:4]
        \\func use(data: str) -> int:
        \\    const r = R(name=copy(head(data)))
        \\    mut names: str[] = []
        \\    append(mut names, copy(head(data)))
        \\    mut cur = copy(head(data))
        \\    return len(r.name) + len(names) + len(cur) + len(head(data))
        \\
        \\
    );
}

const fallible_head =
    \\func plain(data: bytes, position: int) -> bytes from data fails str:
    \\    if position > len(data):
    \\        fail "short"
    \\    return data[position:]
    \\func withmut(data: bytes, mut position: int) -> bytes from data fails str:
    \\    if position > len(data):
    \\        fail "short"
    \\    const out = data[position:]
    \\    position = len(data)
    \\    return out
    \\
    \\
;

test "F3 try: a borrowed success is bound with const, read in place and forwarded, with or without a mut argument" {
    try accepts(std.testing.allocator, fallible_head ++
        \\func bound(data: bytes, start: int) -> int fails str:
        \\    mut at = start
        \\    const first = try withmut(data, mut at)
        \\    at = start * 2
        \\    const second = try plain(data, at)
        \\    return len(first) + len(second) + at
        \\func forward(data: bytes, start: int) -> bytes from data fails str:
        \\    return try plain(data, start)
        \\func forward_mut(data: bytes, mut position: int) -> bytes from data fails str:
        \\    return try withmut(data, mut position)
        \\
        \\
    );
}

test "F3 try: a borrowed success bound to an owned mut local is refused with the copy repair around the call" {
    try refuses(std.testing.allocator, fallible_head ++
        \\func use(data: bytes) -> int fails str:
        \\    mut kept = try plain(data, 1)
        \\    kept = copy(kept)
        \\    return len(kept)
        \\
        \\
    , "E_SINGLE_OWNER_BORROW", "`plain(data, 1)` is lent by the plain parameter `data`, and the `mut` local `kept` needs its own value; write `copy(plain(data, 1))` to keep both", "plain(data, 1)");
}

test "F3 try: the copied call and a copy of the const binding are accepted" {
    try accepts(std.testing.allocator, fallible_head ++
        \\func use(data: bytes) -> int fails str:
        \\    mut kept = try copy(plain(data, 1))
        \\    const part = try plain(data, 2)
        \\    mut other = copy(part)
        \\    return len(kept) + len(other)
        \\
        \\
    );
}

test "F3 try: the success of a borrowed call is still a borrow, so it cannot be stored in a list" {
    try refuses(std.testing.allocator, fallible_head ++
        \\func use(data: bytes) -> int fails str:
        \\    mut kept: bytes[] = []
        \\    const part = try plain(data, 1)
        \\    append(mut kept, part)
        \\    return len(kept)
        \\
        \\
    , "E_SINGLE_OWNER_BORROW", "`part` is lent by the plain parameter `data`, and the list `kept` needs its own value; write `copy(part)` to keep both", "part");
}

test "owned variant payloads refuse an optional byte slice stored in a field" {
    try refuses(std.testing.allocator,
        // migrate-embedded: skip intentional V2 variant payload diagnostic; exact copy repair asserted below
        \\record Kept:
        \\    data: bytes? = None
        \\func keep(data: bytes) -> Kept:
        \\    mut kept = Kept()
        \\    kept.data = Some(data[1:3])
        \\    return kept
    , "E_SLICE_ESCAPES", "`data[1:3]` is lent by the plain parameter `data`, and field `data` of `Kept` needs its own value; write `copy(data[1:3])` to keep both", "data[1:3]");
}

test "owned variant payloads refuse custom text and Result list slices" {
    try refuses(std.testing.allocator,
        // migrate-embedded: skip intentional V2 variant payload diagnostic; exact copy repair asserted below
        \\enum Packet:
        \\    text(value: str)
        \\func keep(data: str) -> int:
        \\    const packet = Packet.text(value=data[1:3])
        \\    return 0
    , "E_SLICE_ESCAPES", "`data[1:3]` is lent by the plain parameter `data`, and field `value` of `Packet.text` needs its own value; write `copy(data[1:3])` to keep both", "data[1:3]");
    try refuses(std.testing.allocator,
        // migrate-embedded: skip intentional V2 variant payload diagnostic; exact copy repair asserted below
        \\func keep(data: int[]) -> int:
        \\    const result: Result[int[], str] = Ok(data[1:3])
        \\    _ = own result
        \\    return 0
    , "E_SLICE_ESCAPES", "`data[1:3]` is lent by the plain parameter `data`, and the local `result` needs its own value; write `copy(data[1:3])` to keep both", "data[1:3]");
}

test "owned variant payloads keep declared optional and fallible borrowed returns" {
    try accepts(std.testing.allocator,
        \\func optional(data: bytes) -> bytes? from data:
        \\    return Some(data[1:3])
        \\func fallible(data: bytes) -> bytes from data fails str:
        \\    return data[1:3]
    );
}

test "owned variant payloads retain misplaced own marker diagnostics before slice repairs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try withEntry(a,
        // migrate-embedded: skip intentional variant payload misplaced-own diagnostic
        \\func keep(data: bytes) -> int:
        \\    const kept: bytes? = Some(own data[1:3])
        \\    return 0
    );
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.B2, failure.rule.?);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edits = failure.repair.explicit_fix;
    try std.testing.expectEqual(@as(usize, 1), edits.len);
    try std.testing.expectEqualStrings("own ", source[edits[0].span.start..edits[0].span.end]);
    try std.testing.expectEqualStrings("", edits[0].text);
}

test "O4 transfer staging preserves bound list slice escapes and their initializer copy repair" {
    try refuses(std.testing.allocator,
        \\func use() -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut outer: int[][] = [[1]]
        \\    const part = xs[1:3]
        \\    outer[0] = own part
        \\    return len(outer[0])
        \\
    , "E_SLICE_ESCAPES", "`xs[1:3]` is lent by the local `xs`, and the list `outer` needs its own value; write `copy(xs[1:3])` to keep both", "xs[1:3]");
    try refuses(std.testing.allocator,
        \\record Row:
        \\    items: int[]
        \\func use() -> int:
        \\    const xs = [1, 2, 3, 4]
        \\    mut rows = [Row(items=[1])]
        \\    const part = xs[1:3]
        \\    rows[0].items = own part
        \\    return len(rows[0].items)
        \\
    , "E_SLICE_ESCAPES", "`xs[1:3]` is lent by the local `xs`, and field `items` of `Row` needs its own value; write `copy(xs[1:3])` to keep both", "xs[1:3]");
}

test "O4 transfer staging preserves bound text and bytes slice escapes" {
    try refuses(std.testing.allocator,
        \\func use() -> int:
        \\    const text = "source-" + str(1)
        \\    mut outer = ["old"]
        \\    const part = text[1:3]
        \\    outer[0] = own part
        \\    return len(outer[0])
        \\
    , "E_SLICE_ESCAPES", "`text[1:3]` is lent by the local `text`, and the list `outer` needs its own value; write `copy(text[1:3])` to keep both", "text[1:3]");
    try refuses(std.testing.allocator,
        \\func use() -> int:
        \\    const data = b"source"
        \\    mut outer = [b"old"]
        \\    const part = data[1:3]
        \\    outer[0] = own part
        \\    return len(outer[0])
        \\
    , "E_SLICE_ESCAPES", "`data[1:3]` is lent by the local `data`, and the list `outer` needs its own value; write `copy(data[1:3])` to keep both", "data[1:3]");
}

test "O4 transfer staging accepts explicit slice copies and keeps owning transfers free of hidden copies" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source =
        \\record Carrier:
        \\    values: int[]
        \\    spare: str
        \\func put_owned(mut outer: int[][], own values: int[]):
        \\    outer[0] = own values
        \\func put_field(mut outer: int[][], own carrier: Carrier):
        \\    outer[0] = own carrier.values
        \\func read_slice(values: int[]) -> int:
        \\    const part = values[1:3]
        \\    return len(part) + part[0]
        \\func copied_slice(values: int[], mut outer: int[][]):
        \\    const part = copy(values[1:3])
        \\    outer[0] = own part
        \\func main() -> int:
        \\    mut outer = [[1]]
        \\    put_owned(mut outer, [5, 6])
        \\    put_field(mut outer, Carrier(values=[7, 8], spare="drop-" + str(1)))
        \\    const xs = [1, 2, 3, 4]
        \\    copied_slice(xs, mut outer)
        \\    return len(outer[0]) + read_slice(xs)
    ;
    var failure: unique.Failure = .{};
    try unique.check(a, try support.checkedProgram(a, source), &failure);
    var refusal: @import("build.zig").Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    var controls: usize = 0;
    var views: usize = 0;
    for (module.functions.items) |function| {
        const name = if (std.mem.lastIndexOf(u8, function.name, "::")) |at| function.name[at + 2 ..] else function.name;
        const control = std.mem.eql(u8, name, "put_owned") or std.mem.eql(u8, name, "put_field") or std.mem.eql(u8, name, "read_slice");
        if (!control) continue;
        controls += 1;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .list_copy and inst.op != .dict_copy and inst.op != .str_from_view);
            try std.testing.expect(inst.op != .list_new and inst.op != .list_push);
            if (inst.op == .list_slice_view) views += 1;
        }
    }
    try std.testing.expectEqual(@as(usize, 3), controls);
    try std.testing.expectEqual(@as(usize, 1), views);
    const result = try @import("passes.zig").run(a, &module, .verify);
    try support.verified(a, &module, result.plans);
}
