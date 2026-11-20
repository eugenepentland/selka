//! `W_NEEDLESS_COPY` repairs that replace a copy by `take(mut place)` of a `const` local (case x) and by
//! `options.take_or(own option, default)` (case xi): every edit of each repair, two repairs on one local through the round's
//! own selection (`fix_plan.select`), and each condition that keeps the `W_COPY_MOVE` hint instead.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const needless_copy = @import("needless_copy.zig");
const fix_plan = @import("fix_plan.zig");
const copy_take_repair = @import("copy_take_repair.zig");

const Edit = language.diagnostic.Edit;

/// One finding of the pass as a test reads it: the code, the wording and every edit of its repair, the main edit first.
const Finding = struct { code: []const u8, message: []const u8, edits: []const Edit };

/// The `W_NEEDLESS_COPY` repairs and `W_COPY_MOVE` hints of `text`, which must check. Everything is the arena's.
fn findings(arena: std.mem.Allocator, text: []const u8) ![]const Finding {
    const report = try fixture.check(arena, text);
    try report.expectAccepted();
    var found: std.ArrayList(Finding) = .empty;
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, needless_copy.code) and !std.mem.eql(u8, item.code, needless_copy.move_code)) continue;
        var edits: std.ArrayList(Edit) = .empty;
        if (item.provenance.fix) |fix| {
            try edits.append(arena, fix.edit);
            try edits.appendSlice(arena, fix.more);
        }
        try found.append(arena, .{ .code = item.code, .message = item.message, .edits = edits.items });
    }
    return found.items;
}

/// How many of `found` are repairs (the code `W_NEEDLESS_COPY`), and how many are hints (`W_COPY_MOVE`).
fn count(found: []const Finding, wanted: []const u8) usize {
    var total: usize = 0;
    for (found) |item| {
        if (std.mem.eql(u8, item.code, wanted)) total += 1;
    }
    return total;
}

/// The text after one `selka fix` round over `found`: the edits `fix_plan.select` takes, the later ones first.
fn fixed(arena: std.mem.Allocator, text: []const u8, found: []const Finding) ![]const u8 {
    var fixes: std.ArrayList(fix_plan.Fix) = .empty;
    for (found) |item| {
        if (item.edits.len == 0) continue;
        var edits: std.ArrayList(fix_plan.Edit) = .empty;
        for (item.edits) |edit| try edits.append(arena, .{ .path = "main", .start = edit.span.start, .end = edit.span.end, .text = edit.text });
        try fixes.append(arena, .{ .code = item.code, .edits = edits.items });
    }
    const plan = try fix_plan.select(arena, fixes.items);
    const chosen = try arena.dupe(fix_plan.Planned, plan.chosen);
    std.mem.sort(fix_plan.Planned, chosen, {}, struct {
        fn later(_: void, left: fix_plan.Planned, right: fix_plan.Planned) bool {
            return left.edit.start > right.edit.start;
        }
    }.later);
    var result = text;
    for (chosen) |item| result = try std.mem.concat(arena, u8, &.{ result[0..item.edit.start], item.edit.text, result[item.edit.end..] });
    return result;
}

/// Whether `text` holds `needle` exactly `times` times.
fn occurrences(text: []const u8, needle: []const u8, times: usize) !void {
    try t.expectEqual(times, std.mem.count(u8, text, needle));
}

const props_record =
    \\record Props:
    \\    material: str
    \\    items: str[]
    \\    thickness: float
    \\
    \\
    \\record Entry:
    \\    material: str
    \\    items: str[]
    \\    thickness: float
    \\
    \\
    \\func parse(n: int) -> Props:
    \\    return Props(material="m" + str(n), items=["a"], thickness=1.5)
    \\
    \\
;

const const_take =
    props_record ++
    \\func entry(n: int) -> Entry:
    \\    const props = parse(n)
    \\    return Entry(material=copy(props.material), items=[], thickness=props.thickness)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, entry(1).material)
    \\    return 0
    ;

test "W_NEEDLESS_COPY (x) takes a field of a const local: the copy and the declaration are one repair" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), const_take);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings(needless_copy.code, found[0].code);
    try t.expectEqual(@as(usize, 2), found[0].edits.len);
    try t.expectEqualStrings("take(mut props.material)", found[0].edits[0].text);
    try t.expectEqualStrings("mut", found[0].edits[1].text);
    try t.expectEqualStrings("const", const_take[found[0].edits[1].span.start..found[0].edits[1].span.end]);
    const after = try fixed(arena.allocator(), const_take, found);
    try occurrences(after, "mut props = parse(n)", 1);
    try occurrences(after, "Entry(material=take(mut props.material), items=[], thickness=props.thickness)", 1);
    // The result checks, and a second round has nothing of this kind left to say.
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

const two_fields =
    props_record ++
    \\func entry(n: int) -> Props:
    \\    const props = parse(n)
    \\    return Props(material=copy(props.material), items=copy(props.items), thickness=props.thickness)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, entry(1).material)
    \\    return 0
    ;

test "W_NEEDLESS_COPY (x) two fields of one const local share the declaration edit and `mut` is written once" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), two_fields);
    try t.expectEqual(@as(usize, 2), found.len);
    for (found) |item| try t.expectEqual(@as(usize, 2), item.edits.len);
    // The two repairs carry one identical edit: the `const` word of the declaration.
    try t.expectEqual(found[0].edits[1].span.start, found[1].edits[1].span.start);
    try t.expectEqual(found[0].edits[1].span.end, found[1].edits[1].span.end);
    const after = try fixed(arena.allocator(), two_fields, found);
    try occurrences(after, "mut props = parse(n)", 1);
    try occurrences(after, "mut mut", 0);
    try occurrences(after, "take(mut props.material)", 1);
    try occurrences(after, "take(mut props.items)", 1);
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

const declared_forms =
    props_record ++
    \\func typed(n: int) -> Entry:
    \\    const props: Props = parse(n)
    \\    return Entry(material=copy(props.material), items=[], thickness=props.thickness)
    \\
    \\
    \\func later(n: int) -> Entry:
    \\    const props: Props
    \\    props = parse(n)
    \\    return Entry(material=copy(props.material), items=[], thickness=props.thickness)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, typed(1).material, later(2).material)
    \\    return 0
    ;

test "W_NEEDLESS_COPY (x) a const local declared with a type, or assigned later, is made mut by replacing the word" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), declared_forms);
    try t.expectEqual(@as(usize, 2), found.len);
    const after = try fixed(arena.allocator(), declared_forms, found);
    try occurrences(after, "mut props: Props = parse(n)", 1);
    try occurrences(after, "mut props: Props\n", 1);
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

const take_or_forms =
    \\func find(n: int) -> str?:
    \\    if n > 0:
    \\        return Some("n" + str(n))
    \\    return None
    \\
    \\
    \\func from_local(n: int) -> str:
    \\    const found = find(n)
    \\    mut out = ""
    \\    out = copy(found.unwrap_or(""))
    \\    return out
    \\
    \\
    \\func from_call(n: int) -> str:
    \\    mut out = ""
    \\    out = copy(find(n).unwrap_or("none"))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, from_local(1), from_call(2))
    \\    return 0
;

test "W_NEEDLESS_COPY (xi) writes options.take_or for an owned option and a fresh one, and the import the unit lacks" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), take_or_forms);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings(needless_copy.code, found[0].code);
    try t.expectEqualStrings("options.take_or(own found, \"\")", found[0].edits[0].text);
    try t.expectEqualStrings("options.take_or(find(n), \"none\")", found[1].edits[0].text);
    // Both repairs insert the same `import options` line: one edit to the file, the second repair adds nothing.
    for (found) |item| {
        try t.expectEqual(@as(usize, 2), item.edits.len);
        try t.expectEqualStrings("import options\n\n", item.edits[1].text);
    }
    const after = try fixed(arena.allocator(), take_or_forms, found);
    try occurrences(after, "import options", 1);
    try occurrences(after, "out = options.take_or(own found, \"\")", 1);
    try occurrences(after, "out = options.take_or(find(n), \"none\")", 1);
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

test "W_NEEDLESS_COPY (xi) adds no import to a unit that has one" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = "import options\n\n\n" ++ take_or_forms;
    const found = try findings(arena.allocator(), text);
    try t.expectEqual(@as(usize, 2), found.len);
    for (found) |item| try t.expectEqual(@as(usize, 1), item.edits.len);
    const after = try fixed(arena.allocator(), text, found);
    try occurrences(after, "import options", 1);
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

/// Case (x) and (xi) shapes whose rewrite is not certain: each stays the `W_COPY_MOVE` hint, with no repair.
const withheld =
    props_record ++
    \\func find(n: int) -> str?:
    \\    if n > 0:
    \\        return Some("n" + str(n))
    \\    return None
    \\
    \\
    \\record Tag:
    \\    size: int
    \\    name: str
    \\
    \\
    \\func same_statement(n: int) -> Tag:
    \\    const found = find(n)
    \\    return Tag(size=len(found.unwrap_or("x")), name=copy(found.unwrap_or("")))
    \\
    \\
    \\func shadowed(n: int) -> str:
    \\    const options = find(n)
    \\    mut out = ""
    \\    out = copy(options.unwrap_or(""))
    \\    return out
    \\
    \\
    \\func in_a_loop(n: int) -> str[]:
    \\    const found = find(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(found.unwrap_or("")))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, same_statement(1).name, shadowed(2), len(in_a_loop(3)))
    \\    return 0
    ;

test "W_COPY_MOVE stays a hint where the option is read in the same statement, the name options is taken, or a loop runs the move twice" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), withheld);
    try t.expectEqual(@as(usize, 0), count(found, needless_copy.code));
    try t.expectEqual(@as(usize, 3), count(found, needless_copy.move_code));
    for (found) |item| try t.expectEqual(@as(usize, 0), item.edits.len);
}

/// The payload a bind-or-else binds (`const at = sc.at_v else:`) is a borrow of `sc` that no store of its own shows: the checker
/// refuses a `take` of `sc.cite` while it lives (`E_SINGLE_OWNER_OVERLAP`), so the `const` local and the `mut` one both keep the copy.
const payload_view =
    \\record Level:
    \\    offset: float = 0.0
    \\    of: bytes = b""
    \\
    \\
    \\record Scan:
    \\    at_v: Level? = None
    \\    cite: bytes? = None
    \\
    \\
    \\record Charge:
    \\    at_v: float
    \\    cite: bytes?
    \\
    \\
    \\func scan(n: int) -> Scan:
    \\    if n > 0:
    \\        return Scan(at_v=Some(Level(offset=float(n), of=b"")), cite=Some(b"c"))
    \\    return Scan()
    \\
    \\
    \\func constant(self: Level) -> float?:
    \\    if len(self.of) == 0:
    \\        return Some(self.offset)
    \\    return None
    \\
    \\
    \\func charge_const(n: int) -> Charge?:
    \\    const sc = scan(n)
    \\    const at = sc.at_v else:
    \\        return None
    \\    const vgs = constant(at) else:
    \\        return None
    \\    return Some(Charge(at_v=vgs, cite=copy(sc.cite)))
    \\
    \\
    \\func charge_mut(n: int) -> Charge?:
    \\    mut sc = scan(n)
    \\    const at = sc.at_v else:
    \\        return None
    \\    const vgs = constant(at) else:
    \\        return None
    \\    return Some(Charge(at_v=vgs, cite=copy(sc.cite)))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, charge_const(1) is None, charge_mut(2) is None)
    \\    return 0
;

test "W_NEEDLESS_COPY (x) writes no take while a bind-or-else payload borrows the local" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), payload_view);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// A payload binding borrows its scrutinee only where it lives: after the `match` that binds it the place is free to take.
const payload_gone =
    \\record Term:
    \\    rail: bytes?
    \\    pad: bytes
    \\    net: bytes
    \\
    \\
    \\record Group:
    \\    rail: bytes
    \\    pad: bytes
    \\    net: bytes
    \\
    \\
    \\func term_of(n: int) -> Term:
    \\    return Term(rail=Some(b"r"), pad=b"p", net=b"n")
    \\
    \\
    \\func after_match(n: int) -> Group:
    \\    const term = term_of(n)
    \\    mut rail = b"none"
    \\    match term.rail:
    \\        case Some(name):
    \\            rail = copy(name)
    \\        case None:
    \\            pass
    \\    return Group(rail=rail, pad=copy(term.pad), net=term.net)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, after_match(1).pad)
    \\    return 0
;

test "W_NEEDLESS_COPY (x) takes a place once the match that bound a payload of it is over" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), payload_gone);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings(needless_copy.code, found[0].code);
    try t.expectEqualStrings("take(mut term.pad)", found[0].edits[0].text);
    const after = try fixed(arena.allocator(), payload_gone, found);
    try occurrences(after, "mut term = term_of(n)", 1);
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

/// A payload bound by an `is` test borrows its scrutinee until its last read: a take after that read checks, and a take before a
/// read of the payload is the refusal `E_SINGLE_OWNER_OVERLAP` (the repair is written for the first and not the second).
const payload_reads =
    \\record Level:
    \\    offset: float = 0.0
    \\    of: bytes = b""
    \\
    \\
    \\record Scan:
    \\    at_v: Level? = None
    \\    cite: bytes? = None
    \\    note: bytes? = None
    \\
    \\
    \\record Charge:
    \\    at_v: float
    \\    cite: bytes?
    \\    note: bytes?
    \\
    \\
    \\func scan(n: int) -> Scan:
    \\    return Scan(at_v=Some(Level(offset=float(n), of=b"x")), cite=Some(b"c"), note=Some(b"n"))
    \\
    \\
    \\func level(self: Level) -> float:
    \\    return self.offset + float(len(self.of))
    \\
    \\
    \\func read_before(n: int) -> Charge:
    \\    const sc = scan(n)
    \\    mut total = 0.0
    \\    if sc.at_v is Some(at):
    \\        total = level(at)
    \\        return Charge(at_v=total, cite=copy(sc.cite), note=sc.note)
    \\    return Charge(at_v=total, cite=None, note=sc.note)
    \\
    \\
    \\func read_after(n: int) -> Charge:
    \\    const sc = scan(n)
    \\    mut total = 0.0
    \\    if sc.at_v is Some(at):
    \\        const cite = copy(sc.cite)
    \\        total = level(at)
    \\        return Charge(at_v=total, cite=cite, note=sc.note)
    \\    return Charge(at_v=total, cite=None, note=sc.note)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(read_before(1).cite.unwrap_or(b"")), len(read_after(2).cite.unwrap_or(b"")))
    \\    return 0
;

test "W_NEEDLESS_COPY (x) takes a place after the last read of an is-test payload, and keeps the copy before a later read of it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try findings(arena.allocator(), payload_reads);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("take(mut sc.cite)", found[0].edits[0].text);
    const after = try fixed(arena.allocator(), payload_reads, found);
    const again = try findings(arena.allocator(), after);
    try t.expectEqual(@as(usize, 0), again.len);
}

/// The span of the first `name` in `text`, as a declaration's name span.
fn nameSpan(text: []const u8, name: []const u8) !language.source.Span {
    const start = std.mem.indexOf(u8, text, name) orelse return error.TestUnexpectedResult;
    return .{ .start = start, .end = start + name.len };
}

test "copy_take_repair.constWord finds the const word of one declared name and of nothing else" {
    const text = "const props = g()\nconst typed: int\nconst left, right = pair()\nmut held = g()\nconstant gone = g()\nx.const dotted = g()\n";
    const props = copy_take_repair.constWord(text, try nameSpan(text, "props"), "props") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("const", text[props.start..props.end]);
    try t.expectEqual(@as(usize, 0), props.start);
    const typed = copy_take_repair.constWord(text, try nameSpan(text, "typed"), "typed") orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("const", text[typed.start..typed.end]);
    // One of several names, a `mut` declaration, a longer word, a field named const and a wrong name each have no word to replace.
    try t.expectEqual(@as(?language.source.Span, null), copy_take_repair.constWord(text, try nameSpan(text, "left"), "left"));
    try t.expectEqual(@as(?language.source.Span, null), copy_take_repair.constWord(text, try nameSpan(text, "right"), "right"));
    try t.expectEqual(@as(?language.source.Span, null), copy_take_repair.constWord(text, try nameSpan(text, "held"), "held"));
    try t.expectEqual(@as(?language.source.Span, null), copy_take_repair.constWord(text, try nameSpan(text, "gone"), "gone"));
    try t.expectEqual(@as(?language.source.Span, null), copy_take_repair.constWord(text, try nameSpan(text, "dotted"), "dotted"));
    try t.expectEqual(@as(?language.source.Span, null), copy_take_repair.constWord(text, try nameSpan(text, "props"), "other"));
}
