//! `W_NEEDLESS_COPY` for case (xiv): a copy of the payload of `match r:` on a local `r` the function owns and reads nowhere
//! after the match is a repair of two edits (`match own r:` and `own p`, or the bare name where it is returned or failed), and
//! stays the `W_COPY_MOVE` hint wherever the rewrite is not certain (COPY-A2a).
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const needless_copy = @import("needless_copy.zig");
const fix_plan = @import("fix_plan.zig");

/// One finding of the pass: its wording, the edit it carries and the edits that go with it.
const Finding = struct { message: []const u8, edit: language.diagnostic.Edit, more: []const language.diagnostic.Edit };

/// The `W_NEEDLESS_COPY` repairs and the `W_COPY_MOVE` hints of one program.
const Scan = struct { repairs: []const Finding, hints: []const Finding };

/// Check `text` (it must be accepted) and return what the copy pass says of it. Everything lives in `arena`.
fn scan(arena: std.mem.Allocator, text: []const u8) !Scan {
    const report = try fixture.check(arena, text);
    try report.expectAccepted();
    var repairs: std.ArrayList(Finding) = .empty;
    var hints: std.ArrayList(Finding) = .empty;
    for (report.diagnostics) |item| {
        const repair = std.mem.eql(u8, item.code, needless_copy.code);
        if (!repair and !std.mem.eql(u8, item.code, needless_copy.move_code)) continue;
        const fix = item.provenance.fix;
        const found: Finding = .{
            .message = item.message,
            .edit = if (fix) |one| one.edit else .{ .span = item.span, .text = "" },
            .more = if (fix) |one| one.more else &.{},
        };
        try (if (repair) repairs else hints).append(arena, found);
    }
    return .{ .repairs = repairs.items, .hints = hints.items };
}

/// `text` with every distinct edit of `found` applied, the last position first, as `selka fix` applies a round: an edit two
/// repairs share is written once.
fn applied(arena: std.mem.Allocator, text: []const u8, found: []const Finding) ![]const u8 {
    var edits: std.ArrayList(language.diagnostic.Edit) = .empty;
    for (found) |item| {
        try appendOnce(arena, &edits, item.edit);
        for (item.more) |edit| try appendOnce(arena, &edits, edit);
    }
    std.mem.sort(language.diagnostic.Edit, edits.items, {}, struct {
        fn later(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start > right.span.start;
        }
    }.later);
    var result = text;
    for (edits.items) |edit| result = try std.mem.concat(arena, u8, &.{ result[0..edit.span.start], edit.text, result[edit.span.end..] });
    return result;
}

/// Append `edit` unless an identical one (same bytes, same text) is there already.
fn appendOnce(arena: std.mem.Allocator, edits: *std.ArrayList(language.diagnostic.Edit), edit: language.diagnostic.Edit) !void {
    for (edits.items) |known| {
        if (known.span.start == edit.span.start and known.span.end == edit.span.end and std.mem.eql(u8, known.text, edit.text)) return;
    }
    try edits.append(arena, edit);
}

/// The program after the repairs of `text` are applied: it checks (`scan` expects that) and has neither a repair nor a hint left.
fn expectRepairedClean(arena: std.mem.Allocator, text: []const u8, found: []const Finding) ![]const u8 {
    const fixed = try applied(arena, text, found);
    const after = try scan(arena, fixed);
    try t.expectEqual(@as(usize, 0), after.repairs.len);
    try t.expectEqual(@as(usize, 0), after.hints.len);
    return fixed;
}

/// A program where the rewrite is not certain: the pass says nothing as a repair and prints `hints` hints, each one the old text.
fn expectHintOnly(text: []const u8, hints: usize) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try scan(arena.allocator(), text);
    try t.expectEqual(@as(usize, 0), found.repairs.len);
    try t.expectEqual(hints, found.hints.len);
    for (found.hints) |hint| try t.expect(std.mem.indexOf(u8, hint.message, "is not used after this match: `match own ") != null);
}

const prelude =
    \\enum Failure:
    \\    missing
    \\    failed(message: str)
    \\
    \\
    \\func stat(n: int) -> Failure:
    \\    if n > 1:
    \\        return Failure.failed(message="m" + str(n))
    \\    return Failure.missing
    \\
    \\
;

const main_zero =
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(run(2)))
    \\    return 0
;

/// The payload is copied into a store: the repair is the head edit and the copy edit.
const into_a_store = prelude ++
    \\func run(n: int) -> str[]:
    \\    const failure = stat(n)
    \\    mut out: str[] = []
    \\    match failure:
    \\        case missing:
    \\            append(mut out, "none")
    \\        case failed(message):
    \\            append(mut out, copy(message))
    \\    return out
++ main_zero;

test "COPY-A2a: a copy of a match payload is a repair of two edits: match own, and own for the copy" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try scan(arena.allocator(), into_a_store);
    try t.expectEqual(@as(usize, 0), found.hints.len);
    try t.expectEqual(@as(usize, 1), found.repairs.len);
    const repair = found.repairs[0];
    try t.expectEqualStrings("`failure` is not used after this match, so `match own failure:` makes `message` an owned payload and the copy becomes a move", repair.message);
    // The head edit is an insertion in front of the scrutinee, after `match `.
    try t.expectEqualStrings("own ", repair.edit.text);
    try t.expectEqual(repair.edit.span.start, repair.edit.span.end);
    try t.expectEqualStrings("match ", into_a_store[repair.edit.span.start - 6 .. repair.edit.span.start]);
    try t.expectEqualStrings("failure:", into_a_store[repair.edit.span.start .. repair.edit.span.start + 8]);
    try t.expectEqual(@as(usize, 1), repair.more.len);
    try t.expectEqualStrings("own message", repair.more[0].text);
    try t.expectEqualStrings("copy(message)", into_a_store[repair.more[0].span.start..repair.more[0].span.end]);
    const fixed = try expectRepairedClean(arena.allocator(), into_a_store, found.repairs);
    try t.expect(std.mem.indexOf(u8, fixed, "match own failure:") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "append(mut out, own message)") != null);
}

/// A failed name is written bare (`fail own x` is `E_OWN_MARKER`), a failed or returned field takes the marker.
const returned_forms = prelude ++
    \\record Reading:
    \\    key: str
    \\    figure: str
    \\
    \\
    \\enum Found:
    \\    none
    \\    one(reading: Reading)
    \\
    \\
    \\func seek(n: int) -> Found:
    \\    if n > 1:
    \\        return Found.one(reading=Reading(key="k", figure="f"))
    \\    return Found.none
    \\
    \\
    \\func explain(n: int) -> str fails str:
    \\    const failure = stat(n)
    \\    match failure:
    \\        case missing:
    \\            return "none"
    \\        case failed(message):
    \\            fail copy(message)
    \\
    \\
    \\func figure(n: int) -> str:
    \\    const hit = seek(n)
    \\    match hit:
    \\        case none:
    \\            return ""
    \\        case one(reading):
    \\            return copy(reading.figure)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, figure(2))
    \\    return 0
;

test "COPY-A2a: a returned or failed name is written bare, a returned field takes own" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try scan(arena.allocator(), returned_forms);
    try t.expectEqual(@as(usize, 0), found.hints.len);
    try t.expectEqual(@as(usize, 2), found.repairs.len);
    try t.expectEqualStrings("message", found.repairs[0].more[0].text);
    try t.expectEqualStrings("own reading.figure", found.repairs[1].more[0].text);
    const fixed = try expectRepairedClean(arena.allocator(), returned_forms, found.repairs);
    try t.expect(std.mem.indexOf(u8, fixed, "fail message\n") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "return own reading.figure\n") != null);
}

/// Two arms copy their payloads of one `match`: two repairs that report one head edit.
const two_arms =
    \\enum Pair:
    \\    left(name: str)
    \\    right(name: str)
    \\    neither
    \\
    \\
    \\func pair(n: int) -> Pair:
    \\    if n > 1:
    \\        return Pair.left(name="l" + str(n))
    \\    return Pair.right(name="r")
    \\
    \\
    \\func run(n: int) -> str[]:
    \\    const chosen = pair(n)
    \\    mut out: str[] = []
    \\    match chosen:
    \\        case left(name):
    \\            append(mut out, copy(name))
    \\        case right(name):
    \\            append(mut out, copy(name))
    \\        case neither:
    \\            pass
    \\    return out
++ main_zero;

test "COPY-A2a: two arms that copy report one head edit, which a fix round applies once" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const memory = arena.allocator();
    const found = try scan(memory, two_arms);
    try t.expectEqual(@as(usize, 0), found.hints.len);
    try t.expectEqual(@as(usize, 2), found.repairs.len);
    const head = found.repairs[0].edit;
    try t.expectEqual(head.span.start, found.repairs[1].edit.span.start);
    try t.expectEqual(head.span.end, found.repairs[1].edit.span.end);
    try t.expectEqualStrings(head.text, found.repairs[1].edit.text);
    // `fix` plans a round from the edits of both fixes: the shared one is taken once, the two copies beside it.
    const first: [2]fix_plan.Edit = .{
        .{ .path = "m.selka", .start = head.span.start, .end = head.span.end, .text = head.text },
        .{ .path = "m.selka", .start = found.repairs[0].more[0].span.start, .end = found.repairs[0].more[0].span.end, .text = found.repairs[0].more[0].text },
    };
    const second: [2]fix_plan.Edit = .{
        first[0],
        .{ .path = "m.selka", .start = found.repairs[1].more[0].span.start, .end = found.repairs[1].more[0].span.end, .text = found.repairs[1].more[0].text },
    };
    const plan = try fix_plan.select(memory, &.{ .{ .code = "W_NEEDLESS_COPY", .edits = &first }, .{ .code = "W_NEEDLESS_COPY", .edits = &second } });
    try t.expectEqual(@as(usize, 3), plan.chosen.len);
    try t.expectEqual(@as(usize, 0), plan.withheld.len);
    const fixed = try expectRepairedClean(memory, two_arms, found.repairs);
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, fixed, "match own chosen:"));
    try t.expectEqual(@as(usize, 2), std.mem.count(u8, fixed, "append(mut out, own name)"));
}

test "COPY-A2a: the repair is withheld, and the hint stays, where another arm reads the owner" {
    try expectHintOnly(prelude ++
        \\func describe(failure: Failure) -> str:
        \\    match failure:
        \\        case missing:
        \\            return "none"
        \\        case failed(message):
        \\            return copy(message)
        \\
        \\
        \\func run(n: int) -> str[]:
        \\    const failure = stat(n)
        \\    mut out: str[] = []
        \\    match failure:
        \\        case missing:
        \\            append(mut out, describe(failure))
        \\        case failed(message):
        \\            append(mut out, copy(message))
        \\    return out
    ++ main_zero, 1);
}

test "COPY-A2a: the repair is withheld where the match runs again in a loop the owner is declared outside of" {
    try expectHintOnly(prelude ++
        \\func run(n: int) -> str[]:
        \\    const failure = stat(n)
        \\    mut out: str[] = []
        \\    for i in range(3):
        \\        match failure:
        \\            case missing:
        \\                append(mut out, "none" + str(i))
        \\            case failed(message):
        \\                append(mut out, copy(message))
        \\    return out
    ++ main_zero, 1);
}

test "COPY-A2a: a loop around the match does not withhold the repair when the owner is made inside it" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = prelude ++
        \\func run(n: int) -> str[]:
        \\    mut out: str[] = []
        \\    for i in range(3):
        \\        const failure = stat(n + i)
        \\        match failure:
        \\            case missing:
        \\                append(mut out, "none")
        \\            case failed(message):
        \\                append(mut out, copy(message))
        \\    return out
    ++ main_zero;
    const found = try scan(arena.allocator(), text);
    try t.expectEqual(@as(usize, 1), found.repairs.len);
    try t.expectEqual(@as(usize, 0), found.hints.len);
    _ = try expectRepairedClean(arena.allocator(), text, found.repairs);
}

test "COPY-A2a: the repair is withheld where the payload is read after the copy, and a later copy of it is the repair" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const text = prelude ++
        \\record Reading:
        \\    key: str
        \\    figure: str
        \\
        \\
        \\enum Found:
        \\    none
        \\    one(reading: Reading)
        \\
        \\
        \\func seek(n: int) -> Found:
        \\    if n > 1:
        \\        return Found.one(reading=Reading(key="k", figure="f"))
        \\    return Found.none
        \\
        \\
        \\func run(n: int) -> str[]:
        \\    const hit = seek(n)
        \\    mut out: str[] = []
        \\    match hit:
        \\        case none:
        \\            append(mut out, "none")
        \\        case one(reading):
        \\            append(mut out, copy(reading.key))
        \\            append(mut out, copy(reading.figure))
        \\    return out
    ++ main_zero;
    const found = try scan(arena.allocator(), text);
    // The first copy leaves `reading.figure` to be read, so it stays a hint; the last one is the move.
    try t.expectEqual(@as(usize, 1), found.hints.len);
    try t.expectEqual(@as(usize, 1), found.repairs.len);
    try t.expectEqualStrings("own reading.figure", found.repairs[0].more[0].text);
}

test "COPY-A2a: an `is` test is not a match statement: the hint stays" {
    try expectHintOnly(prelude ++
        \\func run(n: int) -> str[]:
        \\    const failure = stat(n)
        \\    mut out: str[] = []
        \\    if failure is failed(message):
        \\        append(mut out, copy(message))
        \\    return out
    ++ main_zero, 1);
}

/// A bind-or-else on a local nothing reads again takes `own` in front of the local, as a match does.
const bind_or_else =
    \\func maybe(n: int) -> str?:
    \\    if n > 1:
    \\        return Some("m" + str(n))
    \\    return None
    \\
    \\
    \\func run(n: int) -> str[]:
    \\    const found = maybe(n)
    \\    const text = found else:
    \\        return []
    \\    mut out: str[] = []
    \\    append(mut out, copy(text))
    \\    return out
++ main_zero;

test "COPY-A2a: a bind-or-else on an owned local nothing reads again is a repair of two edits" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try scan(arena.allocator(), bind_or_else);
    try t.expectEqual(@as(usize, 0), found.hints.len);
    try t.expectEqual(@as(usize, 1), found.repairs.len);
    try t.expectEqualStrings("`found` is not used after this binding, so `own found` in front of `else` makes `text` an owned payload and the copy becomes a move", found.repairs[0].message);
    try t.expectEqualStrings("own ", found.repairs[0].edit.text);
    try t.expectEqualStrings("own text", found.repairs[0].more[0].text);
    const fixed = try expectRepairedClean(arena.allocator(), bind_or_else, found.repairs);
    try t.expect(std.mem.indexOf(u8, fixed, "const text = own found else:") != null);
}

test "COPY-A2a: a bind-or-else whose owner is read later in its block stays a hint" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try scan(arena.allocator(), bind_or_else ++
        \\
        \\
        \\func again(n: int) -> int:
        \\    const found = maybe(n)
        \\    const text = found else:
        \\        return 0
        \\    mut out: str[] = []
        \\    append(mut out, copy(text))
        \\    return len(out) + len(found.unwrap_or(""))
    );
    // `run` is the repair; `again` reads `found` inside the rest of the block the binding holds, so it keeps its hint, in its old words.
    try t.expectEqual(@as(usize, 1), found.repairs.len);
    try t.expectEqual(@as(usize, 1), found.hints.len);
    try t.expectEqualStrings("`found` is not used after this match: `match own found:` makes `text` an owned payload, so `own text` replaces the copy", found.hints[0].message);
}

test "COPY-A2a: a match that already says own is not written twice: the hint stays" {
    try expectHintOnly(prelude ++
        \\func run(n: int) -> str[]:
        \\    const failure = stat(n)
        \\    mut out: str[] = []
        \\    match own failure:
        \\        case missing:
        \\            append(mut out, "none")
        \\        case failed(message):
        \\            append(mut out, copy(message))
        \\    return out
    ++ main_zero, 1);
}

/// A local an earlier condition tests is read as its payload where the test holds: `own` in front of it is no option any more.
const narrowed_head =
    \\func opt_text(n: int) -> str?:
    \\    if n > 1:
    \\        return Some("t" + str(n))
    \\    return None
    \\
    \\
    \\func run(n: int) -> str[]:
    \\    mut text: str? = None
    \\    if n > 0:
    \\        text = opt_text(n)
    \\    if n == 0 or text is None:
    \\        return []
    \\    mut out: str[] = []
    \\
;

test "COPY-A2a: a bind-or-else on a local an earlier condition narrowed is no repair, the hint stays (E_ELSE_OPERAND)" {
    try expectHintOnly(narrowed_head ++
        \\    const got = text else:
        \\        return []
        \\    append(mut out, copy(got))
        \\    return out
    ++ main_zero, 1);
}

test "COPY-A2a: a match on a local an earlier condition narrowed is no repair, the hint stays" {
    try expectHintOnly(narrowed_head ++
        \\    match text:
        \\        case Some(got):
        \\            append(mut out, copy(got))
        \\        case None:
        \\            pass
        \\    return out
    ++ main_zero, 1);
}
