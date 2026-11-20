//! `W_NEEDLESS_COPY`: the checker warns when a `copy(value)` carries no value,
//! with the certain repair that deletes it. Case (i) is a copy the callee, an
//! f-string hole or a print only reads; case (ii) is the last use of an owned
//! local. The B0 shapes are the acceptance evidence: the read-only-parameter
//! shape fires, and the copied-then-mutated shape must not.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const fixture = @import("stdlib_fixture.zig");
const needless_copy = @import("needless_copy.zig");
const source = @import("source.zig");

/// One warning as the test reads it: the wording, its repair and its place.
/// The spans and text are copied out of the compilation, which owns them.
const Warning = struct {
    message: []u8,
    edit_text: []u8,
    edit_span: source.Span,
    severity: language.diagnostic.Severity,
    /// The repair's further edits, when it has more than one (a consuming loop edits its header and its copy).
    more: []language.diagnostic.Edit = &.{},
};

/// Check `text` and return its `W_NEEDLESS_COPY` warnings.
fn copies(text: []const u8) ![]Warning {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try report.expectAccepted();
    var found: std.ArrayList(Warning) = .empty;
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, needless_copy.code)) continue;
        // Every warning of this pass carries the one edit that deletes the call;
        // a warning without one is dropped and the length assertion names it.
        const fix = item.provenance.fix orelse continue;
        const more = try t.allocator.alloc(language.diagnostic.Edit, fix.more.len);
        for (fix.more, more) |edit, *out| out.* = .{ .span = edit.span, .text = try t.allocator.dupe(u8, edit.text) };
        try found.append(t.allocator, .{
            .message = try t.allocator.dupe(u8, item.message),
            .edit_text = try t.allocator.dupe(u8, fix.edit.text),
            .edit_span = fix.edit.span,
            .severity = item.severity,
            .more = more,
        });
    }
    return found.toOwnedSlice(t.allocator);
}

/// Check `text` and return its `W_COPY_MOVE` hints: report-only warnings, so none carries a repair.
fn moveHints(text: []const u8) ![]Warning {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try report.expectAccepted();
    var found: std.ArrayList(Warning) = .empty;
    for (report.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, needless_copy.move_code)) continue;
        try t.expect(item.provenance.fix == null);
        try found.append(t.allocator, .{
            .message = try t.allocator.dupe(u8, item.message),
            .edit_text = try t.allocator.dupe(u8, ""),
            .edit_span = item.span,
            .severity = item.severity,
        });
    }
    return found.toOwnedSlice(t.allocator);
}

/// Release the warnings one check returned.
fn freeWarnings(found: []Warning) void {
    for (found) |item| {
        t.allocator.free(item.message);
        t.allocator.free(item.edit_text);
        for (item.more) |edit| t.allocator.free(edit.text);
        t.allocator.free(item.more);
    }
    t.allocator.free(found);
}

/// Apply the one edit of `item`'s repair to `text` and return the result. The
/// fixture is one module, so a merged-source span is its own byte range.
fn repaired(allocator: std.mem.Allocator, text: []const u8, item: Warning) ![]u8 {
    try t.expect(item.edit_span.start <= item.edit_span.end);
    try t.expect(item.edit_span.end <= text.len);
    // Apply the edits from the last position back, so an earlier edit does not move a later one.
    var edits: std.ArrayList(language.diagnostic.Edit) = .empty;
    defer edits.deinit(allocator);
    try edits.append(allocator, .{ .span = item.edit_span, .text = item.edit_text });
    try edits.appendSlice(allocator, item.more);
    std.mem.sort(language.diagnostic.Edit, edits.items, {}, struct {
        fn later(_: void, left: language.diagnostic.Edit, right: language.diagnostic.Edit) bool {
            return left.span.start > right.span.start;
        }
    }.later);
    var result = try allocator.dupe(u8, text);
    for (edits.items) |edit| {
        const next = try std.mem.concat(allocator, u8, &.{ result[0..edit.span.start], edit.text, result[edit.span.end..] });
        allocator.free(result);
        result = next;
    }
    return result;
}

/// Check that `text` with `item`'s repair applied carries no warning and still
/// checks: the plan's "fires only where the copy-free form provably checks".
fn expectRepairChecks(text: []const u8, item: Warning) !void {
    const fixed = try repaired(t.allocator, text, item);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Check that `text` with `item`'s repair applied still checks, and carries `others` warnings: the fixtures with several
/// findings repair one at a time, and each repaired program must be accepted.
fn expectRepairLeaves(text: []const u8, item: Warning, others: usize) !void {
    const fixed = try repaired(t.allocator, text, item);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(others, remaining.len);
}

/// Case (i), the read-only-parameter shape from B0: `total` only reads `xs`.
const read_only_parameter =
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        append(mut xs, i)
    \\    mut acc = 0
    \\    for i in range(n):
    \\        acc += total(copy(xs))
    \\    return acc
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run(2))
    \\    return 0
;

/// Case (i), the B0 negative: the copy is mutated before it is read.
const mutated_after_copy =
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(8):
    \\        append(mut xs, i)
    \\    mut acc = 0
    \\    for i in range(n):
    \\        mut ys = copy(xs)
    \\        append(mut ys, i)
    \\        acc += total(ys)
    \\    return acc
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run(2))
    \\    return 0
;

/// Case (ii), the B0 positive: the copy is the local's last use.
const last_use =
    \\func build(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(n):
    \\        append(mut xs, i)
    \\    const ys = copy(xs)
    \\    return ys
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(build(3)))
    \\    return 0
;

/// Case (ii), the B0 negative: the source is mutated after the copy.
const mutated_after_last_use =
    \\func build(n: int) -> int[]:
    \\    mut xs: int[] = []
    \\    for i in range(n):
    \\        append(mut xs, i)
    \\    const ys = copy(xs)
    \\    append(mut xs, -1)
    \\    return ys
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(build(3)))
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY fires on the read-only parameter shape and its repair checks" {
    const found = try copies(read_only_parameter);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`total` only reads `xs`, so pass `xs` itself rather than a copy", found[0].message);
    try t.expectEqual(language.diagnostic.Severity.warning, found[0].severity);
    try t.expectEqualStrings("xs", found[0].edit_text);
    try expectRepairChecks(read_only_parameter, found[0]);
}

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY stays silent when the copy is mutated before it is read" {
    const found = try copies(mutated_after_copy);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

// spec: NEEDLESS-COPY-2
test "W_NEEDLESS_COPY fires on a last use and its move repair checks" {
    const found = try copies(last_use);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`xs` is never used again, so bind `own xs` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own xs", found[0].edit_text);
    try expectRepairChecks(last_use, found[0]);
}

// spec: NEEDLESS-COPY-2
test "W_NEEDLESS_COPY stays silent when the source is used again" {
    const found = try copies(mutated_after_last_use);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// The print, stream-write and f-string shapes: every one only reads its value.
const printed =
    \\func main(out: Stream) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(3):
    \\        append(mut xs, i)
    \\    print(out, copy(xs))
    \\    print(out, f"{copy(xs)}")
    \\    write(out, "a")
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY fires on a printed value and an f-string hole" {
    const found = try copies(printed);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("print only reads `xs`, so print `xs` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("an f-string hole only reads `xs`, so write `{xs}` rather than a copy", found[1].message);
    try t.expectEqualStrings("xs", found[0].edit_text);
    try t.expectEqualStrings("xs", found[1].edit_text);
}

/// A copy whose receiver is a record field lowers through a temporary; the
/// repair hands over the field the source named.
const field_receiver =
    \\record Bag:
    \\    items: int[]
    \\
    \\
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func run() -> int:
    \\    mut bag = Bag(items=[])
    \\    append(mut bag.items, 1)
    \\    return total(copy(bag.items))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run())
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY fires on a field receiver and repairs to the field" {
    const found = try copies(field_receiver);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`total` only reads `bag.items`, so pass `bag.items` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("bag.items", found[0].edit_text);
    const fixed = try repaired(t.allocator, field_receiver, found[0]);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// One function with many candidate slots: field-receiver temporaries and named locals, copies
/// that only feed a read-only callee, copies that are mutated afterwards and a copy of a slice.
/// Each slot's answer comes from the function's one index of initializations.
const several_slots =
    \\record Bag:
    \\    items: int[]
    \\    names: str[]
    \\
    \\
    \\func total(xs: int[]) -> int:
    \\    mut sum = 0
    \\    for x in xs:
    \\        sum += x
    \\    return sum
    \\
    \\
    \\func count(names: str[]) -> int:
    \\    return len(names)
    \\
    \\
    \\func run() -> int:
    \\    mut bag = Bag(items=[], names=[])
    \\    append(mut bag.items, 1)
    \\    append(mut bag.names, "a")
    \\    mut xs: int[] = []
    \\    append(mut xs, 2)
    \\    const first = total(copy(bag.items))
    \\    const second = count(copy(bag.names))
    \\    mut ys = copy(xs)
    \\    append(mut ys, 3)
    \\    const third = total(copy(xs))
    \\    const fourth = copy(xs[0:1])
    \\    mut fifth = copy(bag.items)
    \\    append(mut fifth, 4)
    \\    return first + second + total(ys) + third + len(fourth) + len(fifth)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run())
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY reports exactly the provable copies of a function with many candidate slots" {
    const found = try copies(several_slots);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 4), found.len);
    try t.expectEqualStrings("`total` only reads `bag.items`, so pass `bag.items` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("`count` only reads `bag.names`, so pass `bag.names` itself rather than a copy", found[1].message);
    try t.expectEqualStrings("`total` only reads `xs`, so pass `xs` itself rather than a copy", found[2].message);
    try t.expectEqualStrings("bag.items", found[0].edit_text);
    try t.expectEqualStrings("bag.names", found[1].edit_text);
    try t.expectEqualStrings("xs", found[2].edit_text);
    // The last copy of `bag.items` is also the field's last use: `take` moves it out of the `mut` local.
    try t.expectEqualStrings("take(mut bag.items)", found[3].edit_text);
}

/// A copy inside a loop is not a last use: the move would run again next
/// iteration, so the copy is still needed. The `const` only reads `xs`, so it borrows it instead.
const copied_in_loop =
    \\func run(n: int) -> int:
    \\    mut xs: int[] = []
    \\    for i in range(n):
    \\        append(mut xs, i)
    \\    mut total = 0
    \\    for i in range(n):
    \\        const ys = copy(xs)
    \\        total += len(ys)
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run(2))
    \\    return 0
;

// spec: NEEDLESS-COPY-2
test "W_NEEDLESS_COPY never moves a copy inside a loop, and borrows what the loop only reads" {
    const found = try copies(copied_in_loop);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`ys` only reads `xs` while it is live, so bind `xs` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("xs", found[0].edit_text);
    try expectRepairClears(copied_in_loop, found[0]);
}

/// A parameter is caller storage, so its copy is not this pass's move.
const parameter_source =
    \\func build(xs: int[]) -> int[]:
    \\    const ys = copy(xs)
    \\    return ys
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(build([1, 2])))
    \\    return 0
;

// spec: NEEDLESS-COPY-2
test "W_NEEDLESS_COPY stays silent when the copied value is a parameter" {
    const found = try copies(parameter_source);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// A view of the source is live across the copy: moving the owner would
/// invalidate it, so the copy is not a move. Two reads of `xs` may coexist, so the `const` borrows it.
const viewed_source =
    \\func run() -> int:
    \\    mut xs: int[] = []
    \\    append(mut xs, 1)
    \\    append(mut xs, 2)
    \\    const part = xs[0:1]
    \\    const ys = copy(xs)
    \\    return len(part) + len(ys)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run())
    \\    return 0
;

// spec: NEEDLESS-COPY-2
test "W_NEEDLESS_COPY never moves a source with a live view, and borrows it beside the view" {
    const found = try copies(viewed_source);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("xs", found[0].edit_text);
    try t.expectEqualStrings("`ys` only reads `xs` while it is live, so bind `xs` itself rather than a copy", found[0].message);
    try expectRepairClears(viewed_source, found[0]);
}

/// A view a call returns is a borrow of `source`: copying it is what makes
/// `before` own its text, so the copy is needed and its repair is not offered.
const copied_call_view =
    \\func head(text: str) -> str from text:
    \\    return text[0:2]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut source = "abcd"
    \\    const piece = head(source)
    \\    const before = copy(piece)
    \\    source += "x"
    \\    print(out, len(before))
    \\    return 0
;

test "W_NEEDLESS_COPY stays silent on a copy of a view a call returns" {
    const found = try copies(copied_call_view);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// A match on a named value borrows its payload, so the copy there is needed.
const borrowed_payload =
    \\func pick(fold: str?) -> str:
    \\    const chosen: str
    \\    match fold:
    \\        case Some(value):
    \\            chosen = copy(value)
    \\        case None:
    \\            chosen = ""
    \\    return chosen
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(pick(Some("abc"))))
    \\    return 0
;

// spec: NEEDLESS-COPY-2
test "W_NEEDLESS_COPY stays silent on a borrowed match payload" {
    const found = try copies(borrowed_payload);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// The copy snapshots a receiver another operand of the same expression
/// mutates; VALUE-SEMANTICS-14 makes exactly that copy necessary.
const operand_snapshot =
    \\import lists
    \\
    \\func clear0(mut xs: int[]) -> int:
    \\    lists.clear(mut xs)
    \\    return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3]
    \\    mut value = lists.index_of(copy(xs), 3 * clear0(mut xs) + 3)
    \\    print(out, value)
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY stays silent when the same expression mutates the source" {
    const found = try copies(operand_snapshot);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Check that `text` with `item`'s repair applied carries no `W_NEEDLESS_COPY` warning and still checks, without
/// assuming the edit's text (the repairs of cases (iii) and (iv) name their own receivers).
fn expectRepairClears(text: []const u8, item: Warning) !void {
    const fixed = try repaired(t.allocator, text, item);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Case (iii): a `const` binds a copy of a parameter and only reads it, so it can borrow the parameter.
const binding_of_parameter =
    \\func show(out: Stream, words: str[]) -> int:
    \\    const copied = copy(words)
    \\    print(out, len(copied))
    \\    print(out, copied[0])
    \\    return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut words: str[] = []
    \\    append(mut words, "a")
    \\    print(out, show(out, words))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) fires on a const bound to a copy of a parameter, and the repair checks" {
    const found = try copies(binding_of_parameter);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`copied` only reads `words` while it is live, so bind `words` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("words", found[0].edit_text);
    try expectRepairClears(binding_of_parameter, found[0]);
}

/// Case (iii) on a field of a local record: `items` borrows `bag.items` while it is read.
const binding_of_field =
    \\record Bag:
    \\    items: str[]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut bag = Bag(items=["a", "b"])
    \\    const items = copy(bag.items)
    \\    print(out, len(items))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) fires on a const bound to a copy of a local's field" {
    const found = try copies(binding_of_field);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`items` only reads `bag.items` while it is live, so bind `bag.items` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("bag.items", found[0].edit_text);
    try expectRepairClears(binding_of_field, found[0]);
}

/// Case (iii) negative: the source changes while the binding is live, so the binding must keep its copy.
const binding_source_changed =
    \\record Bag:
    \\    items: str[]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut bag = Bag(items=["a"])
    \\    const items = copy(bag.items)
    \\    append(mut bag.items, "b")
    \\    print(out, len(items))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) stays silent when the source changes while the binding is live" {
    const found = try copies(binding_source_changed);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iii) negative: the binding is stored, so it must own its value.
const binding_stored =
    \\func show(words: str[]) -> int:
    \\    const copied = copy(words)
    \\    mut kept = copied
    \\    append(mut kept, "x")
    \\    return len(kept)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, show(["a"]))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) stays silent when the binding is stored" {
    const found = try copies(binding_stored);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iii) on a whole owned local: the binding borrows `xs` read-only, which `xs` being used again does not change.
const binding_of_owned_local =
    \\func run(out: Stream) -> int:
    \\    mut xs: int[] = [1, 2]
    \\    const ys = copy(xs)
    \\    print(out, len(ys))
    \\    print(out, len(xs))
    \\    return 0
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, run(out))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) borrows a whole owned local that is used again and only read" {
    const found = try copies(binding_of_owned_local);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`ys` only reads `xs` while it is live, so bind `xs` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("xs", found[0].edit_text);
    try expectRepairClears(binding_of_owned_local, found[0]);
}

/// Case (iii) on an element of a list parameter, a value of a `mut` dictionary parameter and a value of a dictionary a `take`
/// moved out of a field: each binding only reads its place while the place does not change.
const binding_of_element =
    \\record Span:
    \\    low: int
    \\    why: str
    \\
    \\
    \\record Sink:
    \\    by_root: dict[str, Span]
    \\
    \\
    \\func from_list(items: Span[]) -> int:
    \\    mut total = 0
    \\    for i in range(len(items)):
    \\        const span = copy(items[i])
    \\        total += span.low + len(span.why)
    \\    return total
    \\
    \\
    \\func from_mut_param(keys: str[], mut by_root: dict[str, Span]) -> int:
    \\    mut total = 0
    \\    for key in keys:
    \\        if key not in by_root:
    \\            continue
    \\        const span = copy(by_root[key])
    \\        total += span.low + len(span.why)
    \\    return total
    \\
    \\
    \\func from_taken(keys: str[], mut sink: Sink) -> int:
    \\    mut by_root: dict[str, Span] = take(mut sink.by_root)
    \\    mut total = 0
    \\    for key in keys:
    \\        if key not in by_root:
    \\            continue
    \\        const span = copy(by_root[key])
    \\        total += span.low + len(span.why)
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut sink = Sink(by_root={})
    \\    sink.by_root["a"] = Span(low=1, why="w")
    \\    mut by_root: dict[str, Span] = {}
    \\    by_root["a"] = Span(low=2, why="v")
    \\    print(out, from_list([Span(low=1, why="w")]), from_mut_param(["a"], mut by_root), from_taken(["a"], mut sink))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) fires on a const bound to a copy of a list element, of a mut parameter's value or of a taken dictionary's value" {
    const found = try copies(binding_of_element);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 3), found.len);
    try t.expectEqualStrings("`span` only reads `items[i]` while it is live, so bind `items[i]` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("items[i]", found[0].edit_text);
    try t.expectEqualStrings("by_root[key]", found[1].edit_text);
    try t.expectEqualStrings("by_root[key]", found[2].edit_text);
    const fixed = try repairedAll(binding_of_element, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Case (iii) negatives on a place inside a collection: the place is written while the binding is live (an element store, an append, a
/// call that takes the collection `mut`), the binding is stored in another collection, or it is read after the place changes.
const element_binding_negatives =
    \\record Span:
    \\    low: int
    \\    why: str
    \\
    \\
    \\func rewrite(mut items: Span[]):
    \\    items[0] = Span(low=9, why="x")
    \\
    \\
    \\func written(mut items: Span[]) -> int:
    \\    const span = copy(items[0])
    \\    items[0] = Span(low=3, why="y")
    \\    return span.low
    \\
    \\
    \\func appended(mut items: Span[]) -> int:
    \\    const span = copy(items[0])
    \\    append(mut items, Span(low=4, why="z"))
    \\    return span.low
    \\
    \\
    \\func through_call(mut items: Span[]) -> int:
    \\    const span = copy(items[0])
    \\    rewrite(mut items)
    \\    return span.low
    \\
    \\
    \\func stored(items: Span[], mut out: Span[]):
    \\    const span = copy(items[0])
    \\    append(mut out, span)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut items: Span[] = [Span(low=1, why="w")]
    \\    mut kept: Span[] = []
    \\    stored(items, mut kept)
    \\    print(out, written(mut items), appended(mut items), through_call(mut items), len(kept))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) stays silent when the element is written while the binding is live, or the binding is stored" {
    const found = try copies(element_binding_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iv): `label_of` returns a copy of its parameter's field, and its one call site only reads the result.
const copy_returned_field =
    \\record Node:
    \\    label: str
    \\
    \\
    \\func label_of(node: Node) -> str:
    \\    return copy(node.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const node = Node(label="abc")
    \\    print(out, label_of(node))
    \\    return 0
;

test "W_NEEDLESS_COPY preserves an owned return contract even when every caller only reads" {
    const found = try copies(copy_returned_field);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iv) negative: the one call site stores the result, which needs its own copy.
const copy_returned_stored =
    \\record Node:
    \\    label: str
    \\
    \\
    \\func label_of(node: Node) -> str:
    \\    return copy(node.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const node = Node(label="abc")
    \\    mut labels: str[] = []
    \\    append(mut labels, label_of(node))
    \\    print(out, len(labels))
    \\    return 0
;

test "W_NEEDLESS_COPY (iv) stays silent when a call site stores the returned borrow" {
    const found = try copies(copy_returned_stored);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iv) negative: a call site binds the result `mut`, which takes an owned value.
const copy_returned_mut_binding =
    \\record Node:
    \\    label: str
    \\
    \\
    \\func label_of(node: Node) -> str:
    \\    return copy(node.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const node = Node(label="abc")
    \\    mut text = label_of(node)
    \\    print(out, text)
    \\    return 0
;

test "W_NEEDLESS_COPY (iv) stays silent when a call site binds the result mut" {
    const found = try copies(copy_returned_mut_binding);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iv) negative: the function also returns a new value, so its result is not a borrow on every path.
const copy_returned_mixed =
    \\record Node:
    \\    label: str
    \\
    \\
    \\func label_or_new(node: Node) -> str:
    \\    if node.label == "":
    \\        return f"{node.label}!"
    \\    return copy(node.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const node = Node(label="abc")
    \\    print(out, label_or_new(node))
    \\    return 0
;

test "W_NEEDLESS_COPY (iv) stays silent when a return yields a new value" {
    const found = try copies(copy_returned_mixed);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iv) negative: a chained call returns the borrow to its own caller, which is not checked here.
const copy_returned_chained =
    \\record Node:
    \\    label: str
    \\
    \\
    \\func label_of(node: Node) -> str:
    \\    return copy(node.label)
    \\
    \\
    \\func outer(node: Node) -> str:
    \\    return label_of(node)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const node = Node(label="abc")
    \\    print(out, outer(node))
    \\    return 0
;

test "W_NEEDLESS_COPY (iv) stays silent when a call site returns the result onward" {
    const found = try copies(copy_returned_chained);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iv) negative: the checker refuses a whole parameter as a borrowed return, so the copy of it stays.
const copy_returned_whole_parameter =
    \\func echo(text: str, count: int) -> str:
    \\    if count > 0:
    \\        return copy(text)
    \\    return ""
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, echo("abc", 1))
    \\    return 0
;

test "W_NEEDLESS_COPY (iv) stays silent on a copy of a whole parameter" {
    const found = try copies(copy_returned_whole_parameter);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iii) on a parenthesized receiver: the repair names the field without the redundant parentheses.
const binding_of_parenthesized_field =
    \\record Pair:
    \\    text: str
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const pair = Pair(text="a")
    \\    const text = copy((pair.text))
    \\    print(out, len(text))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) repairs a parenthesized receiver to the place without parentheses" {
    const found = try copies(binding_of_parenthesized_field);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("pair.text", found[0].edit_text);
    try expectRepairClears(binding_of_parenthesized_field, found[0]);
}

/// Case (iv) negative: a public function may be called from other modules, which a check of this module cannot see, so its
/// copy stays (the module interface check requires the same report as the whole program).
const copy_returned_public =
    \\public record Node:
    \\    label: str
    \\
    \\
    \\public func label_of(node: Node) -> str:
    \\    return copy(node.label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const node = Node(label="abc")
    \\    print(out, label_of(node))
    \\    return 0
;

test "W_NEEDLESS_COPY (iv) stays silent on a return copy of a public function" {
    const found = try copies(copy_returned_public);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Borrowed aliases remain borrowed even when their local has no slice flag.
const copied_borrowed_alias =
    \\func snapshot(values: int[]) -> int:
    \\    const alias = values
    \\    mut kept = copy(alias)
    \\    append(mut kept, 2)
    \\    return len(kept)
    \\func main() -> int:
    \\    return snapshot([1])
;

const copied_declared_borrow =
    \\func part(values: int[]) -> int[] from values:
    \\    return values
    \\func main() -> int:
    \\    mut values = [1]
    \\    const view = part(values)
    \\    const alias = view
    \\    mut kept = copy(alias)
    \\    append(mut kept, 2)
    \\    append(mut values, 3)
    \\    return len(kept)
;

const copied_borrowed_optional =
    \\func part(text: str) -> str? from text:
    \\    return Some(text)
    \\func main() -> int:
    \\    mut text = "old"
    \\    const view = part(text)
    \\    const alias = view
    \\    const kept = copy(alias)
    \\    text += "changed"
    \\    match kept:
    \\        case Some(value):
    \\            return len(value)
    \\        case None:
    \\            return 0
;

const copied_optional_call_binding =
    \\func part(text: str) -> str? from text:
    \\    return Some(text)
    \\func read(value: str?) -> int:
    \\    match value:
    \\        case Some(text):
    \\            return len(text)
    \\        case None:
    \\            return 0
    \\func main() -> int:
    \\    mut text = "old"
    \\    const borrowed = part(text)
    \\    const kept = copy(borrowed)
    \\    text = "changed"
    \\    return read(kept)
;

const copied_whole_record_binding =
    \\record Holder:
    \\    text: str
    \\func whole(value: Holder) -> Holder from value:
    \\    return value
    \\func main() -> int:
    \\    mut value = Holder(text="old")
    \\    const borrowed = whole(value)
    \\    const kept = copy(borrowed)
    \\    value = Holder(text="changed")
    \\    return len(kept.text)
;

const owner_with_element_loan =
    \\func main() -> int:
    \\    mut rows = [[1], [2]]
    \\    const item = rows[0]
    \\    const kept = copy(rows)
    \\    return len(item) + len(kept)
;

test "W_NEEDLESS_COPY borrows an owner beside a live element loan, which only reads it" {
    const found = try copies(owner_with_element_loan);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("rows", found[0].edit_text);
    try expectRepairClears(owner_with_element_loan, found[0]);
}

test "W_NEEDLESS_COPY preserves borrowed aliases and owner snapshots" {
    const examples = [_][]const u8{
        copied_borrowed_alias,
        copied_declared_borrow,
        copied_borrowed_optional,
        copied_optional_call_binding,
        copied_whole_record_binding,
    };
    for (examples) |text| {
        const found = try copies(text);
        defer freeWarnings(found);
        try t.expectEqual(@as(usize, 0), found.len);
    }
}

const copied_owned_argument =
    \\func my_take(own values: int[]) -> int:
    \\    return len(values)
    \\func snapshot(values: int[]) -> int:
    \\    return my_take(copy(values))
    \\func main() -> int:
    \\    return snapshot([1])
;

const sibling_move_snapshot =
    \\func observe(left: int[], own right: int[]) -> int:
    \\    return len(left) + len(right)
    \\func main() -> int:
    \\    mut values = [1]
    \\    return observe(copy(values), own values)
;

const callback_mutation_snapshot =
    \\func change(mut values: int[]) -> int:
    \\    append(mut values, 2)
    \\    return 0
    \\func observe(values: int[], tag: int) -> int:
    \\    return len(values) + tag
    \\func snapshot(callback: func(mut values: int[]) -> int) -> int:
    \\    mut values = [1]
    \\    return observe(copy(values), callback(mut values))
    \\func main() -> int:
    \\    return snapshot(change)
;

const element_alias_snapshot =
    \\func change(mut rows: int[][]) -> int:
    \\    append(mut rows, [2])
    \\    return 0
    \\func observe(row: int[], tag: int) -> int:
    \\    return len(row) + tag
    \\func main() -> int:
    \\    mut rows = [[1]]
    \\    const row = rows[0]
    \\    return observe(copy(row), change(mut rows))
;

const declared_alias_snapshot =
    \\func first(rows: int[][]) -> int[] from rows:
    \\    return rows[0]
    \\func change(mut rows: int[][]) -> int:
    \\    append(mut rows, [2])
    \\    return 0
    \\func main(out: Stream) -> int:
    \\    mut rows = [[1]]
    \\    const row = first(rows)
    \\    print(out, copy(row), change(mut rows))
    \\    return 0
;

test "W_NEEDLESS_COPY preserves copies consumed or snapshotted across argument effects" {
    const examples = [_][]const u8{
        copied_owned_argument,
        sibling_move_snapshot,
        callback_mutation_snapshot,
        element_alias_snapshot,
        declared_alias_snapshot,
    };
    for (examples) |text| {
        const found = try copies(text);
        defer freeWarnings(found);
        try t.expectEqual(@as(usize, 0), found.len);
    }
}

const dependent_copy_initializers =
    \\func snapshot(values: int[]) -> int[]:
    \\    const first = copy(values)
    \\    const second = copy(first)
    \\    return second
    \\func main() -> int:
    \\    return len(snapshot([1]))
;

test "W_NEEDLESS_COPY dependent repairs retain the copy that supplies the owning result" {
    const found = try copies(dependent_copy_initializers);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("own first", found[0].edit_text);
    try expectRepairClears(dependent_copy_initializers, found[0]);
}

const owned_alias_move =
    \\func build() -> int[]:
    \\    mut values = [1]
    \\    const alias = own values
    \\    const kept = copy(alias)
    \\    return kept
    \\func main() -> int:
    \\    return len(build())
;

test "W_NEEDLESS_COPY still moves a proven owned alias at its final use" {
    const found = try copies(owned_alias_move);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("own alias", found[0].edit_text);
    try expectRepairClears(owned_alias_move, found[0]);
}

const borrowed_alias_copy =
    \\func build() -> int[]:
    \\    mut values = [1]
    \\    const alias = values
    \\    const kept = copy(alias)
    \\    return kept
    \\func main() -> int:
    \\    return len(build())
;

test "O4 copy repair preserves a const alias's required independent owner" {
    const found = try copies(borrowed_alias_copy);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

const generic_move_repair =
    \\func keep[T](own value: T) -> T:
    \\    const first = copy(value)
    \\    const second = copy(first)
    \\    return second
    \\func main() -> int:
    \\    const number = keep[int](3)
    \\    const values = keep[int[]]([1, 2])
    \\    return number + len(values)
;

test "O4 copy repair does not write own into a shared generic template" {
    const found = try copies(generic_move_repair);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (i) at a call to a generic instance of a standard module: the instance's checked name is
/// `lists::contains[main::Item]`, and the warning names it `contains[Item]`, not the tail `Item]` of its last `::`.
const generic_callee =
    \\import lists
    \\
    \\record Item:
    \\    a: int
    \\    name: str
    \\
    \\
    \\func has(items: Item[], v: Item) -> bool:
    \\    return lists.contains(items, copy(v))
    \\
    \\
    \\func main() -> int:
    \\    const items = [Item(a=1, name="x")]
    \\    if has(items, Item(a=2, name="y")):
    \\        return 1
    \\    return 0
;

test "W_NEEDLESS_COPY names a generic callee by its source name and readable type arguments" {
    const found = try copies(generic_callee);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`contains[Item]` only reads `v`, so pass `v` itself rather than a copy", found[0].message);
    try expectRepairChecks(generic_callee, found[0]);
}

/// Every repair of `found` applied at once, last first so the earlier spans stay put; the caller frees the result.
fn repairedAll(text: []const u8, found: []const Warning) ![]u8 {
    var fixed = try t.allocator.dupe(u8, text);
    var index = found.len;
    while (index > 0) {
        index -= 1;
        const next = try repaired(t.allocator, fixed, found[index]);
        t.allocator.free(fixed);
        fixed = next;
    }
    return fixed;
}

/// Case (v): a copy of an owned local or an `own` parameter at its last use, where the value is taken over: an append, a
/// dictionary key, a set member, a case payload, a constructor field, a list element, an `own` argument and a return.
const moved_at_last_use =
    \\import sets
    \\
    \\record Box:
    \\    name: str
    \\
    \\
    \\func eat(own s: str) -> int:
    \\    return len(s)
    \\
    \\
    \\func keep(own x: str, mut out: str[]):
    \\    append(mut out, copy(x))
    \\
    \\
    \\func fresh() -> str:
    \\    const x = "r" + str(1)
    \\    return copy(x)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut list: str[] = []
    \\    mut seen: dict[str, int] = {}
    \\    mut names: set[str] = set()
    \\    const a = "a" + str(1)
    \\    append(mut list, copy(a))
    \\    const b = "b" + str(2)
    \\    seen[copy(b)] = 1
    \\    const c = "c" + str(3)
    \\    sets.add(mut names, copy(c))
    \\    const d = "d" + str(4)
    \\    const some: str? = Some(copy(d))
    \\    const e = "e" + str(5)
    \\    const box = Box(name=copy(e))
    \\    const f = "f" + str(6)
    \\    const items = [copy(f)]
    \\    const g = "g" + str(7)
    \\    const n = eat(copy(g))
    \\    keep("k", mut list)
    \\    for i in range(2):
    \\        const inside = "i" + str(i)
    \\        append(mut list, copy(inside))
    \\    print(out, len(list), len(seen), len(names), some is None, box.name, len(items), n, fresh())
    \\    return 0
;

test "W_NEEDLESS_COPY (v) moves an owned local or own parameter at its last use where the value is taken over" {
    const found = try copies(moved_at_last_use);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 10), found.len);
    try t.expectEqualStrings("own x", found[0].edit_text);
    try t.expectEqualStrings("x", found[1].edit_text);
    try t.expect(std.mem.indexOf(u8, found[0].message, "is never used again, so pass `own x`") != null);
    try t.expect(std.mem.indexOf(u8, found[1].message, "so return `x` itself") != null);
    try t.expectEqualStrings("own inside", found[9].edit_text);
    const fixed = try repairedAll(moved_at_last_use, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Case (v) negatives: a value used again, read beside the copy in one statement, borrowed by a live alias or by a `mut`
/// local stored from places, matched around the copy, copied in a loop it was not declared in (a local or an `own`
/// parameter), a borrowed parameter, and a generic instance.
const moved_negatives =
    \\func pair(a: str, own b: str) -> int:
    \\    return len(a) + len(b)
    \\
    \\
    \\func loop_param(own x: str, mut out: str[]):
    \\    for i in range(2):
    \\        append(mut out, copy(x))
    \\
    \\
    \\func borrowed_param(x: str, mut out: str[]):
    \\    append(mut out, copy(x))
    \\
    \\
    \\func generic_keep[T](own x: T, mut out: T[]):
    \\    append(mut out, copy(x))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut list: str[] = []
    \\    const outside = "o" + str(1)
    \\    for i in range(2):
    \\        append(mut list, copy(outside))
    \\    const later = "l" + str(1)
    \\    append(mut list, copy(later))
    \\    print(out, later)
    \\    const same = "s" + str(1)
    \\    const p = pair(same, copy(same))
    \\    const aliased = "a" + str(1)
    \\    const alias = aliased
    \\    append(mut list, copy(aliased))
    \\    print(out, alias)
    \\    const first = "f" + str(1)
    \\    const second = "g" + str(1)
    \\    mut chosen = first
    \\    if len(list) > 3:
    \\        chosen = second
    \\    append(mut list, copy(first))
    \\    print(out, chosen)
    \\    const opt: str? = Some("x" + str(1))
    \\    match opt:
    \\        case Some(v):
    \\            const held: str? = Some(copy(opt.unwrap_or("")))
    \\            print(out, v, held is None)
    \\        case None:
    \\            pass
    \\    loop_param("p", mut list)
    \\    borrowed_param("q", mut list)
    \\    generic_keep("z", mut list)
    \\    print(out, len(list), p)
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent where the move would not check" {
    const found = try copies(moved_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (v) on a record, a list and a dictionary: the copy of an aggregate binds a receiver temporary to the value first, which
/// is part of the copy and not a second read. The last use of a value declared in the same `match` arm moves it too.
const moved_aggregates =
    \\record Block:
    \\    name: str
    \\    subs: Block[]
    \\
    \\
    \\enum Form:
    \\    sub_block
    \\    other
    \\
    \\
    \\func build(name: str) -> Block:
    \\    return Block(name=copy(name), subs=[])
    \\
    \\
    \\func words_of(name: str) -> str[]:
    \\    return [copy(name)]
    \\
    \\
    \\func into_list(name: str, mut out: Block[]):
    \\    const sb = build(name)
    \\    append(mut out, copy(sb))
    \\
    \\
    \\func into_arm(form: Form, name: str, mut out: Block[]) -> int:
    \\    mut seen = 0
    \\    match form:
    \\        case sub_block:
    \\            const sb = build(name)
    \\            seen += len(sb.name)
    \\            append(mut out, copy(sb))
    \\        case other:
    \\            pass
    \\    return seen
    \\
    \\
    \\func into_lists(name: str, mut out: str[][]):
    \\    const words = words_of(name)
    \\    append(mut out, copy(words))
    \\
    \\
    \\func into_record(name: str) -> Block:
    \\    const sb = build(name)
    \\    return Block(name=copy(name), subs=[copy(sb)])
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut blocks: Block[] = []
    \\    mut lists: str[][] = []
    \\    into_list("a", mut blocks)
    \\    print(out, into_arm(Form.sub_block, "b", mut blocks))
    \\    into_lists("c", mut lists)
    \\    print(out, len(blocks), len(lists), len(into_record("d").subs))
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY (v) moves a record, a list or a value declared in the same match arm at its last use" {
    const found = try copies(moved_aggregates);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 4), found.len);
    try t.expectEqualStrings("own sb", found[0].edit_text);
    try t.expectEqualStrings("own sb", found[1].edit_text);
    try t.expectEqualStrings("own words", found[2].edit_text);
    try t.expectEqualStrings("own sb", found[3].edit_text);
    try t.expect(std.mem.indexOf(u8, found[1].message, "`sb` is never used again, so pass `own sb`") != null);
    const fixed = try repairedAll(moved_aggregates, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Case (v) negatives on aggregates: a record used again, read beside the copy in the same call, borrowed by a live alias, copied
/// in a loop it was not declared in, and a borrowed parameter keep their copies.
const aggregate_negatives =
    \\record Block:
    \\    name: str
    \\    subs: Block[]
    \\
    \\
    \\func build(name: str) -> Block:
    \\    return Block(name=copy(name), subs=[])
    \\
    \\
    \\func both(a: Block, own b: Block) -> int:
    \\    return len(a.name) + len(b.name)
    \\
    \\
    \\func later(name: str, mut out: Block[]) -> int:
    \\    const sb = build(name)
    \\    append(mut out, copy(sb))
    \\    return len(sb.name)
    \\
    \\
    \\func beside(name: str) -> int:
    \\    const sb = build(name)
    \\    return both(sb, copy(sb))
    \\
    \\
    \\func aliased(name: str, mut out: Block[]) -> int:
    \\    const sb = build(name)
    \\    const alias = sb
    \\    append(mut out, copy(sb))
    \\    return len(alias.name)
    \\
    \\
    \\func looped(name: str, mut out: Block[]):
    \\    const sb = build(name)
    \\    for i in range(2):
    \\        append(mut out, copy(sb))
    \\
    \\
    \\func borrowed(sb: Block, mut out: Block[]):
    \\    append(mut out, copy(sb))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut blocks: Block[] = []
    \\    print(out, later("a", mut blocks), beside("b"), aliased("c", mut blocks))
    \\    looped("d", mut blocks)
    \\    borrowed(build("e"), mut blocks)
    \\    print(out, len(blocks))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent on a record that is used again, read beside the copy, aliased, looped or borrowed" {
    const found = try copies(aggregate_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (vi): the key of a dictionary store or a set add is copied, and the store would copy it only when it is new.
const store_keys =
    \\import dicts
    \\import sets
    \\
    \\
    \\record Pair:
    \\    name: str
    \\    count: int
    \\
    \\
    \\func by_parameter(key: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    index[copy(key)] = 1
    \\    return len(index)
    \\
    \\
    \\func by_loop(names: str[]) -> int:
    \\    mut index: dict[str, int] = {}
    \\    for name in names:
    \\        index[copy(name)] = 2
    \\    return len(index)
    \\
    \\
    \\func by_field(pair: Pair) -> int:
    \\    mut index: dict[str, int] = {}
    \\    index[copy(pair.name)] = pair.count
    \\    return len(index)
    \\
    \\
    \\func by_element(names: str[], at: int) -> int:
    \\    mut index: dict[str, int] = {}
    \\    index[copy(names[at])] = 3
    \\    return len(index)
    \\
    \\
    \\func into_set(key: str) -> int:
    \\    mut seen: set[str] = set()
    \\    sets.add(mut seen, copy(key))
    \\    return len(seen)
    \\
    \\
    \\func default_for(key: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    return dicts.setdefault(mut index, copy(key), 1)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, by_parameter("a"), by_loop(["a"]), by_field(Pair(name="a", count=1)), by_element(["a"], 0), into_set("a"), default_for("a"))
    \\    return 0
;

// spec: NEEDLESS-COPY-1
test "W_NEEDLESS_COPY (vi) writes a dictionary key and a set member as the store that copies it only when new" {
    const found = try copies(store_keys);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 6), found.len);
    try t.expectEqualStrings("key", found[0].edit_text);
    try t.expectEqualStrings("name", found[1].edit_text);
    try t.expectEqualStrings("pair.name", found[2].edit_text);
    try t.expectEqualStrings("names[at]", found[3].edit_text);
    try t.expectEqualStrings("sets.include(mut seen, key)", found[4].edit_text);
    try t.expectEqualStrings("a dictionary store copies `key` only when it is a new key, so write `key` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("`sets.include` copies `key` only when the set does not hold it yet, so pass `key` itself rather than a copy", found[4].message);
    try t.expectEqualStrings("key", found[5].edit_text);
    try t.expectEqualStrings("`dicts.setdefault` copies `key` only when it is a new key, so pass `key` itself rather than a copy", found[5].message);
    for (found) |item| try expectRepairLeaves(store_keys, item, 5);
}

/// Case (vi) negatives: a slice, a call result and a key the value changes are not places the store may borrow.
const store_key_negatives =
    \\import sets
    \\
    \\
    \\func slice_key(text: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    index[copy(text[1:3])] = 1
    \\    return len(index)
    \\
    \\
    \\func call_key(label: str?) -> int:
    \\    mut index: dict[str, int] = {}
    \\    index[copy(label.unwrap_or("none"))] = 1
    \\    return len(index)
    \\
    \\
    \\func grow(mut key: str) -> int:
    \\    key = key + "!"
    \\    return 1
    \\
    \\
    \\func changed_by_the_value(mut key: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    index[copy(key)] = grow(mut key)
    \\    return len(index)
    \\
    \\
    \\func literal_member(key: str) -> int:
    \\    const seen: set[str] = {copy(key)}
    \\    return len(seen)
    \\
    \\
    \\func generic_key[K: equality](key: K, mut index: dict[K, int]):
    \\    index[copy(key)] = 1
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut key = "k"
    \\    mut index: dict[str, int] = {}
    \\    generic_key("g", mut index)
    \\    print(out, slice_key("abcd"), call_key(None), changed_by_the_value(mut key), literal_member("a"), len(index))
    \\    return 0
;

test "W_NEEDLESS_COPY (vi) stays silent where the store would not borrow the key" {
    const found = try copies(store_key_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (vi) prefers the move when the key is an owned local at its last use: it copies nothing at all.
const store_key_moves =
    \\func last_use() -> int:
    \\    mut index: dict[str, int] = {}
    \\    const key: str = "a" + "b"
    \\    index[copy(key)] = 1
    \\    return len(index)
    \\
    \\
    \\func used_again() -> int:
    \\    mut index: dict[str, int] = {}
    \\    const key: str = "a" + "b"
    \\    index[copy(key)] = 1
    \\    return len(index) + len(key)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, last_use(), used_again())
    \\    return 0
;

test "W_NEEDLESS_COPY (vi) moves an owned key at its last use and borrows it otherwise" {
    const found = try copies(store_key_moves);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("own key", found[0].edit_text);
    try t.expectEqualStrings("key", found[1].edit_text);
    for (found) |item| try expectRepairLeaves(store_key_moves, item, 1);
}

/// Case (vi): the key of `dicts.add` and `dicts.append_to` is copied, and both borrow it and copy it only when it is new.
const library_keys =
    \\import dicts
    \\
    \\
    \\record Pair:
    \\    name: str
    \\    count: int
    \\
    \\
    \\func by_parameter(key: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    dicts.add(mut index, copy(key), 1)
    \\    return len(index)
    \\
    \\
    \\func by_loop(names: str[]) -> int:
    \\    mut index: dict[str, int] = {}
    \\    for name in names:
    \\        dicts.add(mut index, copy(name), 2)
    \\    return len(index)
    \\
    \\
    \\func by_field(pair: Pair) -> int:
    \\    mut groups: dict[str, int[]] = {}
    \\    dicts.append_to(mut groups, copy(pair.name), 7)
    \\    return len(groups)
    \\
    \\
    \\func by_record(pair: Pair) -> int:
    \\    mut groups: dict[Pair, str[]] = {}
    \\    dicts.append_to(mut groups, copy(pair), "x")
    \\    return len(groups)
    \\
    \\
    \\func last_use() -> int:
    \\    mut index: dict[str, int] = {}
    \\    const key: str = "a" + "b"
    \\    dicts.add(mut index, copy(key), 1)
    \\    return len(index)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, by_parameter("a"), by_loop(["a"]), by_field(Pair(name="a", count=1)), by_record(Pair(name="a", count=1)), last_use())
    \\    return 0
;

test "W_NEEDLESS_COPY (vi) deletes the copy of a dicts.add or dicts.append_to key, owned at its last use or not" {
    const found = try copies(library_keys);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 5), found.len);
    try t.expectEqualStrings("key", found[0].edit_text);
    try t.expectEqualStrings("name", found[1].edit_text);
    try t.expectEqualStrings("pair.name", found[2].edit_text);
    try t.expectEqualStrings("pair", found[3].edit_text);
    try t.expectEqualStrings("key", found[4].edit_text);
    try t.expectEqualStrings("`dicts.add` copies `key` only when it is a new key, so pass `key` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("`dicts.append_to` copies `pair.name` only when it is a new key, so pass `pair.name` itself rather than a copy", found[2].message);
    for (found) |item| try expectRepairLeaves(library_keys, item, 4);
}

/// Case (vi) negatives for the two library calls: a slice, a call result and a key the call's other operands change.
const library_key_negatives =
    \\import dicts
    \\
    \\
    \\func slice_key(text: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    dicts.add(mut index, copy(text[1:3]), 1)
    \\    return len(index)
    \\
    \\
    \\func grow(mut key: str) -> int:
    \\    key = key + "!"
    \\    return 1
    \\
    \\
    \\func changed_by_the_delta(mut key: str) -> int:
    \\    mut index: dict[str, int] = {}
    \\    dicts.add(mut index, copy(key), grow(mut key))
    \\    return len(index)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut key = "k"
    \\    print(out, slice_key("abcd"), changed_by_the_delta(mut key))
    \\    return 0
;

test "W_NEEDLESS_COPY (vi) keeps the copy of a dicts.add key that is a slice or that the call changes" {
    const found = try copies(library_key_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (iii) on a whole local, negatives: the local is written, moved or handed to a `mut` call while the binding is
/// live, the binding is stored, or the local is a loop variable that only borrows an element.
const owned_local_negatives =
    \\func grow(mut xs: int[]) -> int:
    \\    append(mut xs, 1)
    \\    return 1
    \\
    \\
    \\func written_while_live() -> int:
    \\    mut xs: int[] = [1, 2]
    \\    const ys = copy(xs)
    \\    append(mut xs, 3)
    \\    return len(ys)
    \\
    \\
    \\func changed_by_a_call() -> int:
    \\    mut xs: int[] = [1, 2]
    \\    const ys = copy(xs)
    \\    const n = grow(mut xs)
    \\    return len(ys) + n
    \\
    \\
    \\func assigned_while_live() -> int:
    \\    mut xs: int[] = [1, 2]
    \\    const ys = copy(xs)
    \\    xs = [3]
    \\    return len(ys)
    \\
    \\
    \\func stored(rows: int[][]) -> int:
    \\    mut xs: int[] = [1, 2]
    \\    const ys = copy(xs)
    \\    mut kept: int[][] = []
    \\    append(mut kept, own ys)
    \\    return len(kept) + len(rows) + len(xs)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, written_while_live(), changed_by_a_call(), assigned_while_live(), stored([]))
    \\    return 0
;

test "W_NEEDLESS_COPY (iii) keeps the copy of a whole local that changes or is moved while the binding is live" {
    const found = try copies(owned_local_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (vii): a copy of a value that is already new, a module constant, a call's fresh result or a concatenation,
/// duplicates a temporary in every position.
const fresh_operands =
    \\const family: str = "res-0402"
    \\
    \\
    \\record Spec:
    \\    family: str
    \\    value: str
    \\
    \\
    \\func make_text(n: int) -> str:
    \\    mut out: str = ""
    \\    for i in range(n):
    \\        out = out + "x"
    \\    return out
    \\
    \\
    \\func in_record(value: str) -> Spec:
    \\    return Spec(family=copy(family), value=copy(value))
    \\
    \\
    \\func returned() -> str:
    \\    return copy(family)
    \\
    \\
    \\func stored(mut spec: Spec):
    \\    spec.family = copy(make_text(3))
    \\
    \\
    \\func joined(left: str, right: str) -> str:
    \\    const both = copy(left + right)
    \\    return both
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut spec = in_record("v")
    \\    stored(mut spec)
    \\    print(out, spec.family, returned(), joined("a", "b"))
    \\    return 0
;

test "W_NEEDLESS_COPY (vii) deletes the copy of a module constant or a fresh call result" {
    const found = try copies(fresh_operands);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 4), found.len);
    try t.expectEqualStrings("family", found[0].edit_text);
    try t.expectEqualStrings("`family` already yields a new value, so the copy only duplicates a temporary; write `family` without it", found[0].message);
    try t.expectEqualStrings("family", found[1].edit_text);
    try t.expectEqualStrings("make_text(3)", found[2].edit_text);
    try t.expectEqualStrings("left + right", found[3].edit_text);
    for (found) |item| try expectRepairLeaves(fresh_operands, item, 3);
}

/// Case (vii) negatives: the copy of a borrowed call result, of a place and of a parameter is what makes the value
/// independent.
const fresh_operand_negatives =
    \\record Spec:
    \\    family: str
    \\    value: str
    \\
    \\
    \\func first(items: str[]) -> str from items:
    \\    return items[0]
    \\
    \\
    \\func borrowed_result(items: str[]) -> Spec:
    \\    return Spec(family=copy(first(items)), value="v")
    \\
    \\
    \\func place(spec: Spec) -> Spec:
    \\    return Spec(family=copy(spec.family), value=copy(spec.value))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, borrowed_result(["a"]).family, place(Spec(family="f", value="v")).value)
    \\    return 0
;

test "W_NEEDLESS_COPY (vii) keeps the copy of a borrowed call result or a place" {
    const found = try copies(fresh_operand_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (viii): the copy duplicates a value that borrows one parameter, an option's default, a call's declared borrowed
/// result or an element, and the position only reads it.
const borrowed_value_positives =
    \\import sets
    \\
    \\
    \\record Node:
    \\    text: str?
    \\    kids: Node[]
    \\
    \\
    \\record Net:
    \\    name: str
    \\
    \\
    \\func node_text(node: Node) -> str? from node:
    \\    return node.text
    \\
    \\
    \\func base(name: str) -> str from name:
    \\    return name[:2]
    \\
    \\
    \\func shown(text: str) -> int:
    \\    return len(text)
    \\
    \\
    \\func binding(list: Node[]) -> int:
    \\    const file = copy(node_text(list[1]).unwrap_or(""))
    \\    mut total = len(file)
    \\    for child in list[1:]:
    \\        total += len(child.kids)
    \\    return total + len(file)
    \\
    \\
    \\func argument(list: Node[]) -> int:
    \\    return shown(copy(node_text(list[0]).unwrap_or("")))
    \\
    \\
    \\func loop_call(nets: Net[]) -> int:
    \\    mut total = 0
    \\    for net in nets:
    \\        total += shown(copy(base(net.name)))
    \\    return total
    \\
    \\
    \\func collect(nets: Net[], mut seen: set[str]):
    \\    for net in nets:
    \\        sets.include(mut seen, copy(base(net.name)))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut seen: set[str] = set()
    \\    const nodes = [Node(text=Some("a"), kids=[]), Node(text=Some("bc"), kids=[])]
    \\    collect([Net(name="abc")], mut seen)
    \\    print(out, binding(nodes), argument(nodes), loop_call([Net(name="abc")]), len(seen))
    \\    return 0
;

test "W_NEEDLESS_COPY (viii) follows a borrowed value to the local it reads and checks the read-only position" {
    const found = try copies(borrowed_value_positives);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 4), found.len);
    try t.expectEqualStrings("`file` only reads `node_text(list[1]).unwrap_or(\"\")` while it is live, so bind `node_text(list[1]).unwrap_or(\"\")` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("node_text(list[1]).unwrap_or(\"\")", found[0].edit_text);
    try t.expectEqualStrings("`shown` only reads `node_text(list[0]).unwrap_or(\"\")`, so pass `node_text(list[0]).unwrap_or(\"\")` itself rather than a copy", found[1].message);
    try t.expectEqualStrings("base(net.name)", found[2].edit_text);
    try t.expectEqualStrings("base(net.name)", found[3].edit_text);
    for (found) |item| try expectRepairLeaves(borrowed_value_positives, item, 3);
}

/// Case (viii) negatives: the local is written while the binding is live, the call writes the local, or the value
/// borrows two locals.
const borrowed_value_negatives =
    \\record Node:
    \\    text: str?
    \\    kids: Node[]
    \\
    \\
    \\func node_text(node: Node) -> str? from node:
    \\    return node.text
    \\
    \\
    \\func pick(a: Node, b: Node) -> str? from a, b:
    \\    return a.text
    \\
    \\
    \\func shown(text: str) -> int:
    \\    return len(text)
    \\
    \\
    \\func shown_while_growing(mut list: Node[], text: str) -> int:
    \\    append(mut list, Node(text=None, kids=[]))
    \\    return len(text)
    \\
    \\
    \\func written_while_live(mut list: Node[]) -> int:
    \\    const file = copy(node_text(list[0]).unwrap_or(""))
    \\    append(mut list, Node(text=None, kids=[]))
    \\    return len(file)
    \\
    \\
    \\func writes_the_local(mut list: Node[]) -> int:
    \\    return shown_while_growing(mut list, copy(node_text(list[0]).unwrap_or("")))
    \\
    \\
    \\func two_locals(a: Node[], b: Node[]) -> int:
    \\    return shown(copy(pick(a[0], b[0]).unwrap_or("")))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut list = [Node(text=Some("a"), kids=[])]
    \\    print(out, written_while_live(mut list), writes_the_local(mut list), two_locals(list, list))
    \\    return 0
;

test "W_NEEDLESS_COPY (viii) keeps the copy where the borrowed local changes or two locals are read" {
    const found = try copies(borrowed_value_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (i) through a function value: the callable type says the position is a plain read, and the copy goes.
const invoke_argument =
    \\record Scope:
    \\    count: int
    \\
    \\
    \\func apply(set_state: func(mut s: Scope, text: str) -> Unit, mut scope: Scope, text: str) -> int:
    \\    mut st = text + "!"
    \\    set_state(mut scope, copy(st))
    \\    return len(st)
    \\
    \\
    \\func store(mut s: Scope, text: str):
    \\    s.count = len(text)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut scope = Scope(count=0)
    \\    print(out, apply(store, mut scope, "a"), scope.count)
    \\    return 0
;

test "W_NEEDLESS_COPY passes a plain argument of a function value itself" {
    const found = try copies(invoke_argument);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`set_state` only reads `st`, so pass `st` itself rather than a copy", found[0].message);
    try t.expectEqualStrings("st", found[0].edit_text);
    try expectRepairClears(invoke_argument, found[0]);
}

/// Case (i) through a function value, negatives: the callable type writes or takes the position.
const invoke_argument_negatives =
    \\func apply_mut(f: func(mut text: str) -> Unit, text: str) -> int:
    \\    mut copied = copy(text)
    \\    f(mut copied)
    \\    return len(copied)
    \\
    \\
    \\func apply_own(f: func(own text: str) -> Unit, text: str) -> int:
    \\    mut copied = copy(text)
    \\    f(own copied)
    \\    return len(text)
    \\
    \\
    \\func append_bang(mut text: str):
    \\    text = text + "!"
    \\
    \\
    \\func my_take(own text: str):
    \\    pass
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, apply_mut(append_bang, "a"), apply_own(my_take, "b"))
    \\    return 0
;

test "W_NEEDLESS_COPY keeps the copy given to a function value that writes or takes the position" {
    const found = try copies(invoke_argument_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (v) on a field: `own row.name` moves the field out of a record that nothing reads again, in a return, a
/// constructor field and an append.
const field_moves =
    \\record Row:
    \\    name: str
    \\    items: str[]
    \\    count: int
    \\
    \\
    \\record Out:
    \\    label: str
    \\    count: int
    \\
    \\
    \\func make(n: int) -> Row:
    \\    mut row = Row(name="r", items=[], count=n)
    \\    append(mut row.items, "a")
    \\    return row
    \\
    \\
    \\func returned(n: int) -> str:
    \\    const row = make(n)
    \\    return copy(row.name)
    \\
    \\
    \\func stored(n: int) -> Out:
    \\    const row = make(n)
    \\    return Out(label=copy(row.name), count=2)
    \\
    \\
    \\func appended(n: int) -> str[]:
    \\    const row = make(n)
    \\    mut names: str[] = []
    \\    append(mut names, copy(row.name))
    \\    return names
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, returned(1), stored(2).label, len(appended(3)))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) moves a field out of a record that is never used again" {
    const found = try copies(field_moves);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 3), found.len);
    try t.expectEqualStrings("`row` is never used again, so return `own row.name` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own row.name", found[0].edit_text);
    try t.expectEqualStrings("`row` is never used again, so pass `own row.name` and the copy becomes a move", found[1].message);
    try t.expectEqualStrings("own row.name", found[2].edit_text);
    for (found) |item| try expectRepairLeaves(field_moves, item, 2);
}

/// Case (v) on a field, negatives: the record is read again, another field is read beside the copy, the record is a
/// plain parameter or a loop variable, and the place is an element.
const field_move_negatives =
    \\record Row:
    \\    name: str
    \\    items: str[]
    \\    count: int
    \\
    \\
    \\record Out:
    \\    label: str
    \\    count: int
    \\
    \\
    \\func make(n: int) -> Row:
    \\    return Row(name="r", items=["a"], count=n)
    \\
    \\
    \\func used_again(n: int) -> Out:
    \\    const row = make(n)
    \\    const out = Out(label=copy(row.name), count=2)
    \\    return Out(label=out.label, count=len(row.items))
    \\
    \\
    \\func read_beside(n: int) -> Out:
    \\    const row = make(n)
    \\    return Out(label=copy(row.name), count=row.count)
    \\
    \\
    \\func parameter(row: Row) -> Out:
    \\    return Out(label=copy(row.name), count=2)
    \\
    \\
    \\func loop_variable(rows: Row[]) -> str[]:
    \\    mut names: str[] = []
    \\    for row in rows:
    \\        append(mut names, copy(row.name))
    \\    return names
    \\
    \\
    \\func element(n: int) -> str:
    \\    const rows = [make(n)]
    \\    return copy(rows[0].name)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, used_again(1).label, read_beside(2).label, parameter(make(3)).label, len(loop_variable([make(4)])), element(5))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) keeps the copy of a field whose record is read again, borrowed or an element" {
    const found = try copies(field_move_negatives);
    defer freeWarnings(found);
    // Case (v) moves none of them. The three copies of a place of a `const` local that nothing reads again are the `take` of case (x).
    try t.expectEqual(@as(usize, 3), found.len);
    for (found) |item| try t.expect(std.mem.startsWith(u8, item.edit_text, "take(mut "));
}

/// Case (ix): `for x in xs` copies each element into storage and nothing reads `xs` after the loop, so
/// `for x in own xs` hands each element over and the copy becomes `own x`.
const loop_moves =
    \\func make(n: int) -> str[]:
    \\    mut xs: str[] = []
    \\    for i in range(n):
    \\        append(mut xs, "a" + str(i))
    \\    return xs
    \\
    \\
    \\func moved(n: int) -> str[]:
    \\    const xs = make(n)
    \\    mut out: str[] = []
    \\    for x in xs:
    \\        append(mut out, copy(x))
    \\    return out
    \\
    \\
    \\func conditional(n: int) -> str[]:
    \\    mut xs = make(n)
    \\    mut out: str[] = []
    \\    for x in xs:
    \\        if len(out) < 100:
    \\            append(mut out, copy(x))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(moved(3)), len(conditional(2)))
    \\    return 0
;

test "W_NEEDLESS_COPY (ix) turns a copy of each element into a consuming loop over a list nothing reads again" {
    const found = try copies(loop_moves);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("`xs` is not used after the loop, so `for x in own xs` makes `x` an owned element and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own ", found[0].edit_text);
    try t.expectEqual(@as(usize, 1), found[0].more.len);
    try t.expectEqualStrings("own x", found[0].more[0].text);
    for (found) |item| try expectRepairLeaves(loop_moves, item, 1);
}

/// Case (ix) negatives: the list is read after the loop or inside it, the element is read after the copy, the list is a
/// plain parameter, or an outer loop runs the move again.
const loop_move_negatives =
    \\func make(n: int) -> str[]:
    \\    mut xs: str[] = []
    \\    for i in range(n):
    \\        append(mut xs, "a" + str(i))
    \\    return xs
    \\
    \\
    \\func list_used_after(n: int) -> int:
    \\    const xs = make(n)
    \\    mut out: str[] = []
    \\    for x in xs:
    \\        append(mut out, copy(x))
    \\    return len(out) + len(xs)
    \\
    \\
    \\func list_read_inside(n: int) -> int:
    \\    const xs = make(n)
    \\    mut out: str[] = []
    \\    for x in xs:
    \\        append(mut out, copy(x))
    \\        append(mut out, str(len(xs)))
    \\    return len(out)
    \\
    \\
    \\func element_read_after(n: int) -> int:
    \\    const xs = make(n)
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    for x in xs:
    \\        append(mut out, copy(x))
    \\        total += len(x)
    \\    return len(out) + total
    \\
    \\
    \\func parameter(xs: str[]) -> str[]:
    \\    mut out: str[] = []
    \\    for x in xs:
    \\        append(mut out, copy(x))
    \\    return out
    \\
    \\
    \\func outer_loop(n: int) -> int:
    \\    const xs = make(n)
    \\    mut out: str[] = []
    \\    for round in range(2):
    \\        for x in xs:
    \\            append(mut out, copy(x))
    \\    return len(out)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, list_used_after(2), list_read_inside(2), element_read_after(2), len(parameter(["a"])), outer_loop(2))
    \\    return 0
;

test "W_NEEDLESS_COPY (ix) keeps the copy where the list or the element is read again" {
    const found = try copies(loop_move_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (v) on a payload: a match that consumes a fresh call result owns its payload, so the copy of the payload at its
/// last use is `own payload`. A match on a borrowed parameter keeps its copy.
const payload_moves =
    \\enum Shape:
    \\    empty
    \\    named(value: str)
    \\
    \\
    \\func make(n: int) -> Shape:
    \\    if n > 0:
    \\        return Shape.named(value="n" + str(n))
    \\    return Shape.empty
    \\
    \\
    \\func risky(n: int) -> int fails str:
    \\    if n > 3:
    \\        fail "too big " + str(n)
    \\    return n
    \\
    \\
    \\func failure_of(n: int) -> str:
    \\    mut failure: str = "ok"
    \\    match risky(n):
    \\        case Ok(value):
    \\            failure = "fine" + str(value)
    \\        case Err(err):
    \\            failure = copy(err)
    \\    return failure
    \\
    \\
    \\func name_of(n: int) -> str:
    \\    mut name = ""
    \\    match make(n):
    \\        case named(value=text):
    \\            name = copy(text)
    \\        case empty:
    \\            name = "none"
    \\    return name
    \\
    \\
    \\func borrowed_name(shape: Shape) -> str:
    \\    mut name = ""
    \\    match shape:
    \\        case named(value=text):
    \\            name = copy(text)
    \\        case empty:
    \\            name = "none"
    \\    return name
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, failure_of(1), failure_of(9), name_of(2), borrowed_name(make(3)))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) moves the payload of a match that consumes a fresh result" {
    const found = try copies(payload_moves);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("`err` is never used again, so pass `own err` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own err", found[0].edit_text);
    try t.expectEqualStrings("own text", found[1].edit_text);
    for (found) |item| try expectRepairLeaves(payload_moves, item, 1);
}

/// Case (x): `take(mut place)` moves a field or an element out of a local and leaves the default behind, when the place
/// is not read again. A `mut` local or parameter gets the repair, a `const` local the hint to declare it `mut`.
const take_moves =
    \\record Props:
    \\    material: str
    \\    items: str[]
    \\    thickness: float
    \\    er: float
    \\
    \\
    \\record Entry:
    \\    material: str
    \\    thickness: float
    \\
    \\
    \\func parse(n: int) -> Props:
    \\    return Props(material="m" + str(n), items=["a"], thickness=1.5, er=3.0)
    \\
    \\
    \\func with_mut(n: int) -> Entry:
    \\    mut props = parse(n)
    \\    props.er = 4.0
    \\    return Entry(material=copy(props.material), thickness=props.thickness)
    \\
    \\
    \\func with_const(n: int) -> Entry:
    \\    const props = parse(n)
    \\    return Entry(material=copy(props.material), thickness=props.thickness)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, with_mut(1).material, with_const(2).material)
    \\    return 0
;

test "W_NEEDLESS_COPY (x) takes a field out of a mutable local that nothing reads again, and out of a const one it makes mut" {
    const found = try copies(take_moves);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("`props.material` is not read again, so `take(mut props.material)` moves it out and leaves the default behind", found[0].message);
    try t.expectEqualStrings("take(mut props.material)", found[0].edit_text);
    try t.expectEqualStrings("take(mut props.material)", found[1].edit_text);
    // Each repair leaves the other one standing: the const local's carries the `mut` of its declaration as a second edit.
    for (found) |item| try expectRepairLeaves(take_moves, item, 1);
    try t.expectEqual(@as(usize, 1), found[1].more.len);
    const hints = try moveHints(take_moves);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
}

/// Case (x) negatives: the field is read again (also by the next iteration of a loop), the record is a loop variable or a
/// parameter (a `mut` one is the caller's storage), and the field has no default to leave behind.
const take_negatives =
    \\record Props:
    \\    material: str
    \\    thickness: float
    \\
    \\
    \\record Entry:
    \\    material: str
    \\    thickness: float
    \\
    \\
    \\func parse(n: int) -> Props:
    \\    return Props(material="m" + str(n), thickness=1.5)
    \\
    \\
    \\func read_after(n: int) -> int:
    \\    mut props = parse(n)
    \\    const e = Entry(material=copy(props.material), thickness=1.0)
    \\    return len(props.material) + len(e.material)
    \\
    \\
    \\func whole_after(n: int) -> int:
    \\    mut props = parse(n)
    \\    const e = Entry(material=copy(props.material), thickness=1.0)
    \\    return len(parse(n).material) + len(props.material) + len(e.material)
    \\
    \\
    \\func loop_variable(rows: Props[]) -> str[]:
    \\    mut names: str[] = []
    \\    for row in rows:
    \\        append(mut names, copy(row.material))
    \\    return names
    \\
    \\
    \\func parameter(props: Props) -> Entry:
    \\    return Entry(material=copy(props.material), thickness=props.thickness)
    \\
    \\
    \\func mut_parameter(mut props: Props) -> Entry:
    \\    return Entry(material=copy(props.material), thickness=props.thickness)
    \\
    \\
    \\func in_a_loop(n: int) -> str[]:
    \\    mut props = parse(n)
    \\    mut out: str[] = []
    \\    for i in range(n):
    \\        append(mut out, copy(props.material))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut p = parse(5)
    \\    print(out, read_after(1), whole_after(2), len(loop_variable([parse(3)])), parameter(parse(4)).material, mut_parameter(mut p).material, len(in_a_loop(2)))
    \\    return 0
;

test "W_NEEDLESS_COPY (x) keeps the copy of a place that is read again, or of a loop variable or a plain parameter" {
    const found = try copies(take_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
    // The loop variable's copy is a loop hint, not a `take`: its list is a plain parameter nothing reads again.
    const hints = try moveHints(take_negatives);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 1), hints.len);
    try t.expect(std.mem.indexOf(u8, hints[0].message, "`for row in own rows`") != null);
}

/// Case (x) negative (FR67): the copy goes to an `own` parameter beside the same local passed `mut`, where
/// `take(mut run.name)` would change `run` while the call holds it (M5).
const take_beside_mut =
    \\record Run:
    \\    name: str
    \\    files: int
    \\
    \\
    \\func keep(mut totals: Run, own text: str):
    \\    totals.files = len(text)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut run = Run(name="n", files=0)
    \\    keep(mut run, copy(run.name))
    \\    print(out, run.files)
    \\    return 0
;

test "W_NEEDLESS_COPY (x) keeps the copy of a field given to an own parameter beside its local passed mut" {
    const found = try copies(take_beside_mut);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Case (xi): `copy(opt.unwrap_or(default))` of an option the function owns and reads nowhere else, or of a fresh call
/// result, is `options.take_or`.
const take_or_hints =
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
    \\func used_again(n: int) -> int:
    \\    const found = find(n)
    \\    mut out = ""
    \\    out = copy(found.unwrap_or(""))
    \\    return len(out) + len(found.unwrap_or("x"))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, from_local(1), from_call(2), used_again(3))
    \\    return 0
;

test "W_NEEDLESS_COPY (xi) writes options.take_or for an owned option or a fresh one that nothing reads again" {
    const found = try copies(take_or_hints);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 2), found.len);
    try t.expectEqualStrings("`found` is not used again, so `options.take_or(own found, \"\")` returns its payload without the copy", found[0].message);
    try t.expectEqualStrings("`find(n)` returns a new option, so `options.take_or(find(n), \"none\")` returns its payload without the copy", found[1].message);
    for (found) |item| try expectRepairLeaves(take_or_hints, item, 1);
    const hints = try moveHints(take_or_hints);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
}

/// Case (xii): a loop copies each element of a list that is a plain parameter and is not read after the loop.
const loop_hints =
    \\func names(rows: str[]) -> str[]:
    \\    mut out: str[] = []
    \\    for row in rows:
    \\        append(mut out, copy(row))
    \\    return out
    \\
    \\
    \\func read_after(rows: str[]) -> int:
    \\    mut out: str[] = []
    \\    for row in rows:
    \\        append(mut out, copy(row))
    \\    return len(out) + len(rows)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(names(["a"])), read_after(["b"]))
    \\    return 0
;

test "W_COPY_MOVE (xii) hints at a consuming loop over a plain parameter that is not read after the loop" {
    const hints = try moveHints(loop_hints);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 1), hints.len);
    try t.expectEqualStrings("`row` is copied out of each element of `rows`, which nothing reads after the loop; `for row in own rows` hands the " ++
        "elements over when `rows` is an owned local or an `own` parameter (each of its callers then gives its list with `own`)", hints[0].message);
}

/// Case (xiii): every return copies a place of one parameter (or hands back a fresh value), so the result could be `from`
/// that parameter. Two parameters, or a returned local, leave the copies alone.
const from_hints =
    \\record Rows:
    \\    names: str[]
    \\
    \\
    \\func dirname(path: str) -> str?:
    \\    const end = len(path) - 2
    \\    if end <= 0:
    \\        return None
    \\    return Some(copy(path[:end]))
    \\
    \\
    \\func find(rows: Rows, key: str) -> str?:
    \\    for name in rows.names:
    \\        if name == key:
    \\            return Some(copy(name))
    \\    return None
    \\
    \\
    \\func two_roots(a: str, b: str, which: int) -> str:
    \\    if which == 0:
    \\        return copy(a)
    \\    return copy(b)
    \\
    \\
    \\func fresh_other(a: str, which: int) -> str:
    \\    if which == 0:
    \\        return copy(a)
    \\    return a + "x"
    \\
    \\
    \\func declared(a: str) -> str from a:
    \\    return a
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, dirname("abcdef").unwrap_or(""), find(Rows(names=["a"]), "a").unwrap_or(""), two_roots("a", "b", 0), fresh_other("q", 1), declared("d"))
    \\    return 0
;

test "W_COPY_MOVE (xiii) hints at a from clause where every return copies a place of one parameter" {
    const hints = try moveHints(from_hints);
    defer freeWarnings(hints);
    // `fresh_other` returns a new value beside the copy: `from a` would be `E_BORROW_MIXED` whatever its callers do, so no hint.
    try t.expectEqual(@as(usize, 2), hints.len);
    try t.expectEqualStrings("every return of `dirname` copies a place of `path`: if every caller only reads the result, declare it `from path` and " ++
        "return the places themselves, so no caller copies; if a caller keeps the result, the copy is needed there", hints[0].message);
    try t.expect(std.mem.indexOf(u8, hints[1].message, "every return of `find` copies a place of `rows`") != null);
}

/// Case (v) on a payload, negatives and the failure: a declared borrowed result still lends its payload, so the match
/// does not own it; a copy of a dictionary value is not a `take` place; and the failure of a result is handed over bare,
/// as a return is.
const payload_borrowed_and_fail =
    \\func text_of(items: str[], at: int) -> str? from items:
    \\    if at < len(items):
    \\        return Some(items[at])
    \\    return None
    \\
    \\
    \\func borrowed(items: str[]) -> str:
    \\    mut out = ""
    \\    if text_of(items, 0) is Some(text):
    \\        out = copy(text)
    \\    return out
    \\
    \\
    \\func dictionary_value(key: str) -> str:
    \\    mut names: dict[str, str] = {}
    \\    names[key] = "v" + key
    \\    mut out = ""
    \\    out = copy(names[key])
    \\    return out
    \\
    \\
    \\func risky(n: int) -> int fails str:
    \\    if n > 3:
    \\        fail "too big " + str(n)
    \\    return n
    \\
    \\
    \\func rethrown(n: int) -> int fails str:
    \\    match risky(n):
    \\        case Ok(value):
    \\            return value
    \\        case Err(message):
    \\            fail copy(message)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    match rethrown(1):
    \\        case Ok(value):
    \\            print(out, borrowed(["a"]), dictionary_value("k"), value)
    \\        case Err(message):
    \\            print(out, message)
    \\    return 0
;

test "W_NEEDLESS_COPY (v) leaves a borrowed result's payload and a dictionary value alone, and fails bare" {
    const found = try copies(payload_borrowed_and_fail);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("message", found[0].edit_text);
    try expectRepairLeaves(payload_borrowed_and_fail, found[0], 0);
    const hints = try moveHints(payload_borrowed_and_fail);
    defer freeWarnings(hints);
    for (hints) |item| std.debug.print("unexpected hint: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), hints.len);
}

/// Case (xiv): the copy duplicates the payload of a match on a local that is not used after the match, so `match own`
/// makes the payload owned; and a loop copies the elements of a list a call returns, which needs a name to be consumed.
const match_own_hints =
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
    \\func explain(n: int) -> str fails str:
    \\    const failure = stat(n)
    \\    match failure:
    \\        case missing:
    \\            return "none"
    \\        case failed(message):
    \\            fail copy(message)
    \\
    \\
    \\func explain_again(n: int) -> str:
    \\    const failure = stat(n)
    \\    mut seen = ""
    \\    match failure:
    \\        case missing:
    \\            seen = "none"
    \\        case failed(message):
    \\            seen = copy(message)
    \\    match failure:
    \\        case missing:
    \\            return seen
    \\        case failed(message):
    \\            return seen + message
    \\
    \\
    \\func pads(n: int) -> str[]:
    \\    mut out: str[] = []
    \\    append(mut out, "p" + str(n))
    \\    return out
    \\
    \\
    \\func names(n: int) -> str[]:
    \\    mut out: str[] = []
    \\    for pad in pads(n):
    \\        append(mut out, copy(pad))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(names(1)))
    \\    return 0
;

test "W_NEEDLESS_COPY (xiv) repairs the payload of a match on a local nothing reads after, and a list the call returns" {
    // `explain_again` reads `failure` after its first match, so only `explain` is repaired (`match own failure:`, and the failed
    // name written bare); the loop over a call's list is a repair since FR25 (below). Nothing is left as a hint.
    const hints = try moveHints(match_own_hints);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
    const repairs = try copies(match_own_hints);
    defer freeWarnings(repairs);
    try t.expectEqual(@as(usize, 2), repairs.len);
    try t.expectEqualStrings("`failure` is not used after this match, so `match own failure:` makes `message` an owned payload and the copy becomes a move", repairs[0].message);
    try t.expectEqualStrings("own ", repairs[0].edit_text);
    try t.expectEqualStrings("message", repairs[0].more[0].text);
    try expectRepairLeaves(match_own_hints, repairs[0], 1);
    try t.expectEqualStrings("the list `pads(n)` returns is named by nothing else, so `for pad in own pads(n)` makes `pad` an owned element " ++
        "and the copy becomes a move", repairs[1].message);
    try t.expectEqualStrings("own ", repairs[1].edit_text);
    try t.expectEqualStrings("own pad", repairs[1].more[0].text);
    try expectRepairLeaves(match_own_hints, repairs[1], 1);
}

/// FR21: the programs of the hint for a loop over a call's list at a `return`, a `fail`, a returned field and a payload
/// returned out of `match own`: `own x` is refused at a returned name (`E_OWN_MARKER`), so each hint names the edit that checks.
const returned_hints =
    \\record Reading:
    \\    key: str
    \\    figure: str
    \\
    \\
    \\func readings() -> Reading[]:
    \\    return [Reading(key="a", figure="1"), Reading(key="b", figure="2")]
    \\
    \\
    \\func reading_of(key: str) -> Reading:
    \\    for reading in readings():
    \\        if reading.key == key:
    \\            return copy(reading)
    \\    return Reading(key="", figure="")
    \\
    \\
    \\func figure_of(key: str) -> str:
    \\    for reading in readings():
    \\        if reading.key == key:
    \\            return copy(reading.figure)
    \\    return ""
    \\
    \\
    \\func found_or_fail(key: str) -> int fails Reading:
    \\    for reading in readings():
    \\        if reading.key == key:
    \\            fail copy(reading)
    \\    return 0
    \\
    \\
    \\func maybe() -> Reading?:
    \\    return Some(Reading(key="a", figure="1"))
    \\
    \\
    \\func unwrapped() -> Reading:
    \\    const found = maybe()
    \\    match found:
    \\        case Some(reading):
    \\            return copy(reading)
    \\        case None:
    \\            return Reading(key="", figure="")
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, reading_of("a").figure, figure_of("b"), unwrapped().key)
    \\    return 0
;

test "W_COPY_MOVE names the edit that checks where the copy is returned or failed (FR21)" {
    // A returned or failed element is a repair since FR25 (the loops over `readings()` below), a returned field of it since
    // COPY-A2c (`return own reading.figure`, the edit that checks), and the payload of the `match` since COPY-A2a: no hint is left.
    const hints = try moveHints(returned_hints);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
    // The repairs come in the order of their functions: `reading_of`, `figure_of`, `found_or_fail`, `unwrapped`.
    const repairs = try copies(returned_hints);
    defer freeWarnings(repairs);
    try t.expectEqual(@as(usize, 4), repairs.len);
    for (repairs[0..3], [_][]const u8{ "reading", "own reading.figure", "reading" }) |item, moved| {
        try t.expectEqualStrings("the list `readings()` returns is named by nothing else, so `for reading in own readings()` makes " ++
            "`reading` an owned element and the copy becomes a move", item.message);
        try t.expectEqualStrings("own ", item.edit_text);
        try t.expectEqualStrings(moved, item.more[0].text);
        try expectRepairLeaves(returned_hints, item, 3);
    }
    try t.expectEqualStrings("`found` is not used after this match, so `match own found:` makes `reading` an owned payload and the copy becomes a move", repairs[3].message);
    try t.expectEqualStrings("reading", repairs[3].more[0].text);
    try expectRepairLeaves(returned_hints, repairs[3], 3);
}

/// FR25 (F-75's second half): a loop over a list a call returns takes it with `own`, so each element is owned and the copy of it
/// is a move: one repair of two edits, where the copy stands in a store, a `return` or a `fail`, nothing reads the element after
/// it, no view of it exists and no loop around the copy runs it twice. A condition that reads the element does not hold it.
const fresh_loop_moves =
    \\record Reading:
    \\    key: str
    \\    figure: str
    \\
    \\
    \\func values() -> str[]:
    \\    return ["a", "b"]
    \\
    \\
    \\func readings() -> Reading[]:
    \\    return [Reading(key="a", figure="1"), Reading(key="b", figure="2")]
    \\
    \\
    \\func first(xss: str[][]) -> str[] from xss:
    \\    return xss[0]
    \\
    \\
    \\func pick(value: str) -> str:
    \\    for one in values():
    \\        if value == one:
    \\            return copy(one)
    \\    return ""
    \\
    \\
    \\func collected() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func record_of(key: str) -> Reading:
    \\    for reading in readings():
    \\        if reading.key == key:
    \\            return copy(reading)
    \\    return Reading(key="", figure="")
    \\
    \\
    \\func twice(flag: bool) -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        if flag:
    \\            append(mut out, copy(one))
    \\        else:
    \\            append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func read_after() -> int:
    \\    mut out: str[] = []
    \\    mut n = 0
    \\    for one in values():
    \\        append(mut out, copy(one))
    \\        n += len(one)
    \\    return n + len(out)
    \\
    \\
    \\func lent(xss: str[][]) -> str[]:
    \\    mut out: str[] = []
    \\    for one in first(xss):
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func indexed() -> str[]:
    \\    mut out: str[] = []
    \\    for i, one in enumerate(values()):
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func nested() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        for i in range(2):
    \\            append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func field_of(key: str) -> str:
    \\    for reading in readings():
    \\        if reading.key == key:
    \\            return copy(reading.figure)
    \\    return ""
    \\
    \\
    \\func named_record(key: str) -> Reading:
    \\    const known = readings()
    \\    for reading in known:
    \\        if reading.key == key:
    \\            return copy(reading)
    \\    return Reading(key="", figure="")
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pick("b"), len(collected()), record_of("a").figure, twice(True), read_after(), len(lent([["x"]])), len(indexed()))
    \\    print(out, len(nested()), field_of("b"), named_record("a").key)
    \\    return 0
;

test "W_NEEDLESS_COPY (ix) takes the list a call returns: a return, a store and a fail become moves, and the shapes that are not certain keep their hint (FR25)" {
    const repairs = try copies(fresh_loop_moves);
    defer freeWarnings(repairs);
    // pick, collected, record_of and the second copy of twice; the first copy of twice reads the element again in the other branch.
    // Since COPY-A2c also the returned field of `field_of` and the record of `named_record`, over an owned local.
    try t.expectEqual(@as(usize, 6), repairs.len);
    try t.expectEqualStrings("the list `values()` returns is named by nothing else, so `for one in own values()` makes `one` an owned element and " ++
        "the copy becomes a move", repairs[0].message);
    try t.expectEqualStrings("own ", repairs[0].edit_text);
    try t.expectEqual(@as(usize, 1), repairs[0].more.len);
    try t.expectEqualStrings("one", repairs[0].more[0].text);
    try t.expectEqualStrings("own one", repairs[1].more[0].text);
    try t.expectEqualStrings("reading", repairs[2].more[0].text);
    try t.expectEqualStrings("own one", repairs[3].more[0].text);
    try t.expectEqualStrings("own reading.figure", repairs[4].more[0].text);
    try t.expectEqualStrings("`known` is not used after the loop, so `for reading in own known` makes `reading` an owned element and " ++
        "the copy becomes a move", repairs[5].message);
    try t.expectEqualStrings("reading", repairs[5].more[0].text);
    for (repairs) |item| try expectRepairLeaves(fresh_loop_moves, item, 5);
    // What stays a hint: the loop whose copy a loop around it runs twice.
    const hints = try moveHints(fresh_loop_moves);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 1), hints.len);
    try t.expectEqualStrings("`one` is copied out of each element of a list the call returns; `for one in own values():` hands the elements over, " ++
        "so write `own one` in place of `copy(one)`", hints[0].message);
}

/// FR26: a copy of an element that a view still reads draws no hint: the move the hint names would invalidate the view (V3), which
/// the checker refuses, and a hint must never advise an edit that is refused. The copy of an element nothing views keeps its repair.
/// FR27: a view that nothing reads from the copy on is not invalidated, so `viewed_returned`, whose view is read before the return,
/// draws its hint (the checker accepts the edit); the repair stays the broader test and still says nothing there.
const viewed_elements =
    \\func values() -> str[]:
    \\    return ["abc", "de"]
    \\
    \\
    \\func viewed_fresh() -> str[]:
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    for one in values():
    \\        const head = one[0:1]
    \\        append(mut out, copy(one))
    \\        total += len(head)
    \\    return out
    \\
    \\
    \\func viewed_named() -> str[]:
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    const items = values()
    \\    for one in items:
    \\        const head = one[0:1]
    \\        append(mut out, copy(one))
    \\        total += len(head)
    \\    return out
    \\
    \\
    \\func viewed_returned() -> str:
    \\    for one in values():
    \\        const head = one[0:1]
    \\        if len(head) > 0:
    \\            return copy(one)
    \\    return ""
    \\
    \\
    \\func not_viewed() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, viewed_fresh(), viewed_named(), viewed_returned(), not_viewed())
    \\    return 0
;

test "W_COPY_MOVE is withheld where a view of the element would be invalidated by the move (FR26)" {
    const hints = try moveHints(viewed_elements);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 1), hints.len);
    try t.expectEqualStrings("`one` is copied out of each element of a list the call returns; `for one in own values():` hands the elements over, " ++
        "so write `return one` in place of `return copy(one)`", hints[0].message);
    const repairs = try copies(viewed_elements);
    defer freeWarnings(repairs);
    try t.expectEqual(@as(usize, 1), repairs.len);
    try t.expectEqualStrings("own one", repairs[0].more[0].text);
    try t.expect(repairs[0].edit_span.start > std.mem.indexOf(u8, viewed_elements, "func not_viewed").?);
}

/// FR27: the hint asks whether a view is still read when the copy runs, not whether one exists. A view read after the copy, or
/// declared before a loop around the copy and read in it, keeps the hint back; so does a call's returned view that a `match`
/// holds through the arm of the copy, and a consuming loop that a loop around it would run again. The three copies that stay are
/// the ones whose view is read before the copy only, and `live_views_edited` makes each advised edit.
const live_views =
    \\func values() -> str[]:
    \\    return ["abc", "de"]
    \\
    \\
    \\func lend(value: str) -> str? from value:
    \\    if len(value) > 1:
    \\        return Some(value)
    \\    return None
    \\
    \\
    \\func read_after() -> str[]:
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    for one in values():
    \\        const head = one[0:1]
    \\        append(mut out, copy(one))
    \\        total += len(head)
    \\    return out
    \\
    \\
    \\func read_before() -> str[]:
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    for one in values():
    \\        const head = one[0:1]
    \\        total += len(head)
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func read_in_an_inner_loop() -> str[]:
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    for one in values():
    \\        const head = one[0:1]
    \\        for i in range(2):
    \\            total += len(head)
    \\            append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func list_viewed_before_the_loop(items: str[]) -> str[]:
    \\    mut out: str[] = []
    \\    const first = items[0]
    \\    mut total = len(first)
    \\    for one in items:
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func list_viewed_in_the_loop() -> str[]:
    \\    mut out: str[] = []
    \\    const items = values()
    \\    const first = items[0]
    \\    mut total = 0
    \\    for one in items:
    \\        total += len(first)
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func list_viewed_before_a_local() -> str[]:
    \\    mut out: str[] = []
    \\    const items = values()
    \\    const first = items[0]
    \\    mut total = len(first)
    \\    for one in items:
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func held_by_a_match() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        const shown = lend(one) else:
    \\            continue
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func inside_another_loop(rows: str[][]) -> str[]:
    \\    mut out: str[] = []
    \\    const items = values()
    \\    for row in rows:
    \\        for one in items:
    \\            append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, read_after(), read_before(), read_in_an_inner_loop(), list_viewed_before_the_loop(["a"]), list_viewed_in_the_loop())
    \\    print(out, list_viewed_before_a_local(), held_by_a_match(), inside_another_loop([["x"]]))
    \\    return 0
;

test "W_COPY_MOVE is given where no view is read from the copy on, and withheld where one is (FR27)" {
    const hints = try moveHints(live_views);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 3), hints.len);
    try t.expectEqualStrings("`one` is copied out of each element of a list the call returns; `for one in own values():` hands the elements over, " ++
        "so write `own one` in place of `copy(one)`", hints[0].message);
    try t.expect(hints[0].edit_span.start > std.mem.indexOf(u8, live_views, "func read_before").?);
    try t.expect(hints[0].edit_span.start < std.mem.indexOf(u8, live_views, "func read_in_an_inner_loop").?);
    try t.expectEqualStrings("`one` is copied out of each element of `items`, which nothing reads after the loop; `for one in own items` hands the " ++
        "elements over when `items` is an owned local or an `own` parameter (each of its callers then gives its list with `own`)", hints[1].message);
    try t.expectEqualStrings("`one` is copied out of each element of `items`, which nothing reads after the loop; `for one in own items` hands the " ++
        "elements over when `items` is an owned local or an `own` parameter", hints[2].message);
    // The repair is the broader test: a view of the element or the list anywhere in the function keeps it back.
    const repairs = try copies(live_views);
    defer freeWarnings(repairs);
    for (repairs) |item| try t.expect(item.edit_span.start > std.mem.indexOf(u8, live_views, "func held_by_a_match").? or
        item.edit_span.start < std.mem.indexOf(u8, live_views, "func read_before").?);
}

/// `live_views` with the three advised edits made: it checks and draws no hint for them.
const live_views_edited =
    \\func values() -> str[]:
    \\    return ["abc", "de"]
    \\
    \\
    \\func read_before() -> str[]:
    \\    mut out: str[] = []
    \\    mut total = 0
    \\    for one in own values():
    \\        const head = one[0:1]
    \\        total += len(head)
    \\        append(mut out, own one)
    \\    return out
    \\
    \\
    \\func list_viewed_before_the_loop(own items: str[]) -> str[]:
    \\    mut out: str[] = []
    \\    const first = items[0]
    \\    mut total = len(first)
    \\    for one in own items:
    \\        append(mut out, own one)
    \\    return out
    \\
    \\
    \\func list_viewed_before_a_local() -> str[]:
    \\    mut out: str[] = []
    \\    const items = values()
    \\    const first = items[0]
    \\    mut total = len(first)
    \\    for one in own items:
    \\        append(mut out, own one)
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, read_before(), list_viewed_before_the_loop(["a"]), list_viewed_before_a_local())
    \\    return 0
;

test "the edits the live-view hints advise are accepted, and leave no hint (FR27)" {
    const hints = try moveHints(live_views_edited);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
}

/// FR26: the answer "a view of this element exists" is kept per function, by slot. Two functions with the same locals in the same
/// slots answer for themselves, in either order, and the repair and the hint of one copy agree.
const viewed_by_function =
    \\func values() -> str[]:
    \\    return ["abc", "de"]
    \\
    \\
    \\func plain() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func viewed() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        const head = one[0:1]
    \\        append(mut out, copy(one))
    \\        out[0] = head
    \\    return out
    \\
    \\
    \\func plain_again() -> str[]:
    \\    mut out: str[] = []
    \\    for one in values():
    \\        append(mut out, copy(one))
    \\    return out
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, plain(), viewed(), plain_again())
    \\    return 0
;

test "the answer that a view of the element exists is kept per function (FR26)" {
    const repairs = try copies(viewed_by_function);
    defer freeWarnings(repairs);
    try t.expectEqual(@as(usize, 2), repairs.len);
    const viewed_at = std.mem.indexOf(u8, viewed_by_function, "func viewed()").?;
    const again_at = std.mem.indexOf(u8, viewed_by_function, "func plain_again()").?;
    try t.expect(repairs[0].edit_span.start < viewed_at);
    try t.expect(repairs[1].edit_span.start > again_at);
    const hints = try moveHints(viewed_by_function);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
}

/// The programs `returned_hints` advises, with every edit made: each checks and draws no hint.
const returned_edits_made =
    \\record Reading:
    \\    key: str
    \\    figure: str
    \\
    \\
    \\func readings() -> Reading[]:
    \\    return [Reading(key="a", figure="1"), Reading(key="b", figure="2")]
    \\
    \\
    \\func reading_of(key: str) -> Reading:
    \\    for reading in own readings():
    \\        if reading.key == key:
    \\            return reading
    \\    return Reading(key="", figure="")
    \\
    \\
    \\func figure_of(key: str) -> str:
    \\    for reading in own readings():
    \\        if reading.key == key:
    \\            return own reading.figure
    \\    return ""
    \\
    \\
    \\func found_or_fail(key: str) -> int fails Reading:
    \\    for reading in own readings():
    \\        if reading.key == key:
    \\            fail reading
    \\    return 0
    \\
    \\
    \\func maybe() -> Reading?:
    \\    return Some(Reading(key="a", figure="1"))
    \\
    \\
    \\func unwrapped() -> Reading:
    \\    const found = maybe()
    \\    match own found:
    \\        case Some(reading):
    \\            return reading
    \\        case None:
    \\            return Reading(key="", figure="")
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, reading_of("a").figure, figure_of("b"), unwrapped().key)
    \\    return 0
;

test "the edits W_COPY_MOVE names at a return and a fail check, and draw no hint (FR21)" {
    const hints = try moveHints(returned_edits_made);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
}

/// FR21: a loop over a wrapper of a list is not a loop over the list. `for i, x in enumerate(xs)` keeps the index and
/// `for x in own enumerate(xs)` is `E_ITERATION`; `reversed` and `zip` have the same problem.
const wrapped_iterables =
    \\func items() -> str[]:
    \\    return ["a", "b", "c"]
    \\
    \\
    \\func fresh_enumerate() -> str[]:
    \\    mut found: str[] = []
    \\    for index, item in enumerate(items()):
    \\        if index == 0:
    \\            append(mut found, "first")
    \\        else:
    \\            append(mut found, copy(item))
    \\    return found
    \\
    \\
    \\func named_enumerate() -> str[]:
    \\    const owned = items()
    \\    mut found: str[] = []
    \\    for index, item in enumerate(owned):
    \\        if index == 0:
    \\            append(mut found, "first")
    \\        else:
    \\            append(mut found, copy(item))
    \\    return found
    \\
    \\
    \\func named_reversed() -> str[]:
    \\    const owned = items()
    \\    mut found: str[] = []
    \\    for item in reversed(owned):
    \\        append(mut found, copy(item))
    \\    return found
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, len(fresh_enumerate()), len(named_enumerate()), len(named_reversed()))
    \\    return 0
;

test "a loop over enumerate or reversed of a list draws no consuming-loop hint and no repair (FR21)" {
    const hints = try moveHints(wrapped_iterables);
    defer freeWarnings(hints);
    try t.expectEqual(@as(usize, 0), hints.len);
    const repairs = try copies(wrapped_iterables);
    defer freeWarnings(repairs);
    try t.expectEqual(@as(usize, 0), repairs.len);
}

/// Case (x) negative: `dicts.get(map, key, fallback)` answers the fallback itself, so the result borrows the list the
/// fallback is an element of, and `take` of another element would write the list while the result is live.
const take_borrowed_fallback =
    \\import dicts
    \\
    \\
    \\record Pair:
    \\    first: str
    \\    second: str
    \\    first_name: str
    \\
    \\
    \\func pair(map: dict[str, str]) -> Pair:
    \\    mut pads: str[] = []
    \\    for key in dicts.keys(map):
    \\        append(mut pads, copy(key))
    \\    const first_name = dicts.get(map, pads[0], pads[0])
    \\    return Pair(first=copy(pads[0]), second=copy(pads[1]), first_name=copy(first_name))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, pair({"x": "1", "y": "2"}).second)
    \\    return 0
;

test "W_NEEDLESS_COPY (x) keeps the copy of an element while a get that answers its fallback borrows the list" {
    const found = try copies(take_borrowed_fallback);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// Three functions, each with its own copy: the pass keeps one function's walked body only while it warns that function, so
/// the second function's answer must not come from the first function's body.
const several_functions =
    \\record Row:
    \\    name: str
    \\    items: str[]
    \\
    \\
    \\func name_of(n: int) -> str:
    \\    const row = Row(name="r" + str(n), items=[])
    \\    return copy(row.name)
    \\
    \\
    \\func items_of(n: int) -> str[]:
    \\    const row = Row(name="r", items=["a" + str(n)])
    \\    return copy(row.items)
    \\
    \\
    \\func kept(n: int) -> int:
    \\    const row = Row(name="r", items=["a" + str(n)])
    \\    const again = copy(row.items)
    \\    return len(row.items) + len(again) + len(row.name)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, name_of(1), len(items_of(2)), kept(3))
    \\    return 0
;

test "W_NEEDLESS_COPY warns each function from its own body" {
    const found = try copies(several_functions);
    defer freeWarnings(found);
    // `name_of` and `items_of` move a field out of a record nothing reads again; `kept` reads `row.items` after its binding, which borrows it.
    try t.expectEqual(@as(usize, 3), found.len);
    try t.expectEqualStrings("`row` is never used again, so return `own row.name` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("`row` is never used again, so return `own row.items` and the copy becomes a move", found[1].message);
    try t.expectEqualStrings("`again` only reads `row.items` while it is live, so bind `row.items` itself rather than a copy", found[2].message);
}

// spec: FR14B-COPY-MOVE-JUDGED-1
test "the W_COPY_MOVE hints check judges against the callers are told apart, and a caller's stored answers round-trip" {
    const result = needless_copy.judgedByCallers("W_COPY_MOVE", "every return of `label` copies a place of `status`: if every caller only reads the result, declare it `from status`").?;
    try t.expectEqual(.result, result.form);
    try t.expectEqualStrings("status", result.parameter);
    const argument = needless_copy.judgedByCallers("W_COPY_MOVE", "`use.name` is copied out of each element of `uses`, which nothing reads after the loop; " ++
        "`for use in own uses` hands the elements over when `uses` is an owned local or an `own` parameter").?;
    try t.expectEqual(.argument, argument.form);
    try t.expectEqualStrings("uses", argument.parameter);
    try t.expectEqual(@as(?needless_copy.Judged, null), needless_copy.judgedByCallers("W_NEEDLESS_COPY", "every return of `f` copies a place of `x`"));
    try t.expectEqual(@as(?needless_copy.Judged, null), needless_copy.judgedByCallers("W_COPY_MOVE", "`x` is copied out of each element of a list the call returns"));
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const summary = @import("semantic_summary.zig");
    const keeps = [_]summary.Keep{
        .{ .callee = "fn\x1flib\x1f\x1fhttps_url", .parameter = "url", .result = true, .keeps = true },
        .{ .callee = "fn\x1flib\x1f\x1fnames_of", .parameter = "uses", .result = false, .keeps = false },
    };
    const row: summary.Summary = .{ .key = "fn\x1fkeep\x1f\x1fward", .context = @splat(1), .region = .{ .len = 3, .digest = @splat(2) }, .fact = .{}, .stubbable = true, .notes = .{ .complete = true, .keeps = &keeps } };
    const plain: summary.Summary = .{ .key = "fn\x1fkeep\x1f\x1fother", .context = @splat(3), .region = .{ .len = 4, .digest = @splat(4) }, .fact = .{}, .stubbable = true };
    const payload = try summary.encode(arena.allocator(), .{ .summaries = &.{ row, plain } });
    const decoded = summary.decode(arena.allocator(), payload).?;
    try t.expect(decoded.flagsAt(0).holds.keeps);
    try t.expect(!decoded.flagsAt(1).holds.keeps);
    const stored = decoded.keepsAt(0);
    try t.expectEqual(@as(usize, 2), stored.len);
    try t.expectEqualStrings("fn\x1flib\x1f\x1fhttps_url", stored[0].callee);
    try t.expectEqualStrings("uses", stored[1].parameter);
    try t.expect(stored[0].result and stored[0].keeps);
    try t.expect(!stored[1].result and !stored[1].keeps);
    try t.expectEqual(@as(usize, 0), decoded.keepsAt(1).len);
}

/// The last use of an owned local that sits in a branch (COPY-A1a): a condition that only reads the value does not hold it, and an
/// element write `items[0] = copy(x)` takes its value over as an assignment does.
const moved_in_branch =
    \\func chosen(own asked: str) -> str:
    \\    mut version = "none"
    \\    if len(asked) > 0:
    \\        version = copy(asked)
    \\    return version
    \\
    \\
    \\func spelled(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    mut version = "none"
    \\    if len(asked) > 5:
    \\        version = "far"
    \\    elif len(asked) > 0:
    \\        version = copy(asked)
    \\    return version
    \\
    \\
    \\func stored(n: int) -> str:
    \\    const loose = "l" + str(n)
    \\    mut items: str[] = ["a", "b"]
    \\    if len(items) > 5:
    \\        append(mut items, own loose)
    \\    else:
    \\        items[0] = copy(loose)
    \\    return items[0]
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const asked = "v" + str(2)
    \\    mut version = "none"
    \\    if len(asked) > 0:
    \\        version = copy(asked)
    \\    print(out, version, chosen("a"), spelled(1), stored(2))
    \\    return 0
;

// spec: FR14B-COPY-MOVE-JUDGED-1
test "W_NEEDLESS_COPY (v) moves the last use of an owned local that sits in a branch, and an element write takes its value over" {
    const found = try copies(moved_in_branch);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 4), found.len);
    try t.expectEqualStrings("`asked` is never used again, so pass `own asked` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own asked", found[0].edit_text);
    try t.expectEqualStrings("`loose` is never used again, so pass `own loose` and the copy becomes a move", found[2].message);
    try t.expectEqualStrings("own loose", found[2].edit_text);
    try t.expectEqualStrings("own asked", found[3].edit_text);
    const fixed = try repairedAll(moved_in_branch, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Branches where giving the value away would not check, or would change what a later read sees.
const branch_negatives =
    \\func after(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    mut version = "none"
    \\    if len(asked) > 0:
    \\        version = copy(asked)
    \\    return version + asked
    \\
    \\
    \\func other_arm(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    mut version = "none"
    \\    if len(asked) > 3:
    \\        version = copy(asked)
    \\    else:
    \\        version = asked + "!"
    \\    return version
    \\
    \\
    \\func around_while(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    mut version = "none"
    \\    mut turn = 0
    \\    while turn < 3:
    \\        if len(asked) > 0:
    \\            version = copy(asked)
    \\        turn = turn + 1
    \\    return version
    \\
    \\
    \\func around_for(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    mut version = "none"
    \\    for turn in range(3):
    \\        if turn > 0:
    \\            version = copy(asked)
    \\    return version
    \\
    \\
    \\func viewed(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    const seen = asked
    \\    mut version = "none"
    \\    if len(asked) > 0:
    \\        version = copy(asked)
    \\    return version + seen
    \\
    \\
    \\func size_of(text: str) -> int?:
    \\    return Some(len(text))
    \\
    \\
    \\func held_by_match(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    mut version = "none"
    \\    match size_of(asked):
    \\        case Some(size):
    \\            if size > 0:
    \\                version = copy(asked)
    \\        case None:
    \\            pass
    \\    return version
    \\
    \\
    \\func held_by_with(fs: Filesystem, n: int) -> str:
    \\    const asked = "d" + str(n)
    \\    mut version = "none"
    \\    with fs.open(asked, "r") as file:
    \\        if len(file.readlines()) > 0:
    \\            version = copy(asked)
    \\    return version
    \\
    \\
    \\func eat(own text: str) -> bool:
    \\    return len(text) > 0
    \\
    \\
    \\func in_condition(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    if eat(copy(asked)):
    \\        return "yes"
    \\    return "no"
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, after(1), other_arm(2), around_while(3), around_for(4), viewed(5), held_by_match(6), in_condition(7))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent where a branch's last use would not check" {
    const found = try copies(branch_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// A copy returned from a value a call's result handed over (COPY-A1b). A library function (`strings.decode`) and a capability's
/// method (`fs.read_file`) are nodes of their own, not calls, and a slice argument stages its operand in a block that ends in the
/// call; a failing function's `return` also wraps the value in an `Ok` that is written nowhere.
const returned_from_result =
    \\import filesystem
    \\import strings
    \\
    \\
    \\func program(cmdline: bytes) -> str:
    \\    mut end = 0
    \\    while end < len(cmdline) and int(cmdline[end]) != 0:
    \\        end += 1
    \\    const text = strings.decode(cmdline[0:end]) else Err(_):
    \\        return ""
    \\    return copy(text)
    \\
    \\
    \\func read(fs: Filesystem, path: str) -> bytes fails str:
    \\    match fs.read_file(path):
    \\        case Err(why):
    \\            if strings.find(why, "does not exist") is not None:
    \\                fail "missing"
    \\            fail "unreadable"
    \\        case Ok(text):
    \\            if len(text) > 100:
    \\                fail "too big"
    \\            return copy(text)
    \\
    \\
    \\func shout(n: int) -> str fails str:
    \\    if n < 0:
    \\        fail "negative"
    \\    const word = "w" + str(n)
    \\    return copy(word)
    \\
    \\
    \\func maybe(n: int) -> str?:
    \\    const label = "l" + str(n)
    \\    return copy(label)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut fs = filesystem.memory()
    \\    _ = fs.write_text("a.txt", "hello")
    \\    const data = read(fs, "a.txt") else Err(why):
    \\        print(out, why)
    \\        return 1
    \\    const word = shout(2) else Err(why):
    \\        print(out, why)
    \\        return 1
    \\    print(out, program(b"abc"), len(data), word, maybe(1))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) returns a value that came out of a library function's or a capability's result bare (COPY-A1b)" {
    const found = try copies(returned_from_result);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 4), found.len);
    try t.expectEqualStrings("`text` is never used again, so return `text` itself and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("text", found[0].edit_text);
    try t.expectEqualStrings("`text` is never used again, so return `text` itself and the copy becomes a move", found[1].message);
    try t.expectEqualStrings("text", found[1].edit_text);
    try t.expectEqualStrings("`word` is never used again, so return `word` itself and the copy becomes a move", found[2].message);
    try t.expectEqualStrings("word", found[2].edit_text);
    try t.expectEqualStrings("`label` is never used again, so return `label` itself and the copy becomes a move", found[3].message);
    try t.expectEqualStrings("label", found[3].edit_text);
    const fixed = try repairedAll(returned_from_result, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
    try t.expect(std.mem.indexOf(u8, fixed, "return text\n") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "copy(") == null);
}

/// Returns that would not check, or would change what a later read sees, though the value came out of a result.
const returned_from_result_negatives =
    \\import filesystem
    \\import strings
    \\
    \\
    \\func lend(items: str[], at: int) -> str? from items:
    \\    if at < len(items):
    \\        return Some(items[at])
    \\    return None
    \\
    \\
    \\func lent(items: str[]) -> str:
    \\    match lend(items[0:2], 0):
    \\        case Some(text):
    \\            return copy(text)
    \\        case None:
    \\            return ""
    \\
    \\
    \\func on_a_place(fs: Filesystem, path: str) -> bytes fails str:
    \\    const result = fs.read_file(path)
    \\    match result:
    \\        case Err(why):
    \\            fail "unreadable"
    \\        case Ok(text):
    \\            return copy(text)
    \\
    \\
    \\func after(cmdline: bytes) -> str:
    \\    const text = strings.decode(cmdline[0:2]) else Err(_):
    \\        return ""
    \\    mut kept = ""
    \\    if len(cmdline) > 3:
    \\        kept = copy(text)
    \\    return kept + text + "!"
    \\
    \\
    \\func read_again(fs: Filesystem, path: str) -> bytes fails str:
    \\    match fs.read_file(path):
    \\        case Err(why):
    \\            fail "unreadable"
    \\        case Ok(text):
    \\            mut kept = b""
    \\            if len(text) > 100:
    \\                kept = copy(text)
    \\            return kept + text[0:50]
    \\
    \\
    \\func an_element(texts: str[]) -> str:
    \\    for text in texts:
    \\        if len(text) > 2:
    \\            return copy(text)
    \\    return ""
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut fs = filesystem.memory()
    \\    _ = fs.write_text("a.txt", "hello")
    \\    const first = on_a_place(fs, "a.txt") else Err(_):
    \\        return 1
    \\    const second = read_again(fs, "a.txt") else Err(_):
    \\        return 1
    \\    print(out, lent(["a", "b"]), len(first), after(b"abcd"), len(second), an_element(["abc"]))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent where a returned result's payload is lent, held, or read again (COPY-A1b)" {
    const found = try copies(returned_from_result_negatives);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// An `Option` constructor around a copy is written nowhere only as the value of a `return` (COPY-A1b); in a field, an assignment,
/// an append, an `own` argument, or written out as `Some(...)`, the copy is a value taken over, and the edit is `own a`.
const wrapped_not_returned =
    \\record Row:
    \\    name: str
    \\    alt: str?
    \\
    \\
    \\func keep(own v: str?) -> int:
    \\    return len(v.unwrap_or(""))
    \\
    \\
    \\func in_field(n: int) -> str:
    \\    const a = "a" + str(n)
    \\    const row = Row(name="n", alt=copy(a))
    \\    return row.alt.unwrap_or("none")
    \\
    \\
    \\func in_assignment(n: int) -> str:
    \\    const a = "a" + str(n)
    \\    mut held: str? = None
    \\    if len(a) > 0:
    \\        held = copy(a)
    \\    return held.unwrap_or("none")
    \\
    \\
    \\func in_append(n: int) -> int:
    \\    const a = "a" + str(n)
    \\    mut xs: str?[] = []
    \\    append(mut xs, copy(a))
    \\    return len(xs)
    \\
    \\
    \\func in_argument(n: int) -> int:
    \\    const a = "a" + str(n)
    \\    return keep(copy(a))
    \\
    \\
    \\func written_out(n: int) -> str?:
    \\    const a = "a" + str(n)
    \\    return Some(copy(a))
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, in_field(1), in_assignment(2), in_append(3), in_argument(4), written_out(5).unwrap_or("none"))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) words a copy an Option constructor takes over, outside a return, as a pass of `own` (COPY-A1b)" {
    const found = try copies(wrapped_not_returned);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 5), found.len);
    for (found) |item| {
        try t.expectEqualStrings("`a` is never used again, so pass `own a` and the copy becomes a move", item.message);
        try t.expectEqualStrings("own a", item.edit_text);
    }
    const fixed = try repairedAll(wrapped_not_returned, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// A copy in a `return` or a `fail` has no path after it but the rest of its own statement (COPY-A1c): a later `return` that reads
/// the value stands after it in the source, on a path the copy never takes.
const early_return =
    \\import strings
    \\
    \\record Row:
    \\    name: str
    \\    alt: str
    \\
    \\
    \\func pick(n: int) -> Row:
    \\    const sc = Row(name="n" + str(n), alt="a")
    \\    if n > 3:
    \\        return Row(name=copy(sc.name), alt="early")
    \\    return Row(name=own sc.name, alt="late")
    \\
    \\
    \\func shout(n: int) -> str fails str:
    \\    const word = "w" + str(n)
    \\    if n < 0:
    \\        fail copy(word)
    \\    return copy(word)
    \\
    \\
    \\func first(ns: int[]) -> str:
    \\    for n in ns:
    \\        const t = "t" + str(n)
    \\        if n > 5:
    \\            return copy(t)
    \\        if n > 2:
    \\            return t + "!"
    \\    return "none"
    \\
    \\
    \\func after(cmdline: bytes) -> str:
    \\    const text = strings.decode(cmdline[0:2]) else Err(_):
    \\        return ""
    \\    if len(cmdline) > 3:
    \\        return copy(text)
    \\    return text + "!"
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const word = shout(1) else Err(why):
    \\        print(out, why)
    \\        return 1
    \\    print(out, pick(4).name, word, first([1, 9]), after(b"abcd"))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) moves the copy in an early return a later return reads after (COPY-A1c)" {
    const found = try copies(early_return);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 5), found.len);
    try t.expectEqualStrings("`sc` is never used again, so pass `own sc.name` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own sc.name", found[0].edit_text);
    try t.expectEqualStrings("`word` is never used again, so return `word` itself and the copy becomes a move", found[1].message);
    try t.expectEqualStrings("word", found[1].edit_text);
    try t.expectEqualStrings("word", found[2].edit_text);
    try t.expectEqualStrings("t", found[3].edit_text);
    try t.expectEqualStrings("text", found[4].edit_text);
    const fixed = try repairedAll(early_return, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Copies in a `return` that something still reads, on a path that can follow the copy or in the rest of the statement.
const early_return_read =
    \\import filesystem
    \\
    \\record Row:
    \\    name: str
    \\    alt: str
    \\
    \\
    \\func same_statement(n: int) -> Row:
    \\    const sc = Row(name="n" + str(n), alt="a")
    \\    return Row(name=copy(sc.name), alt=str(len(sc.alt)))
    \\
    \\
    \\func after_if(n: int) -> Row:
    \\    const sc = Row(name="n" + str(n), alt="a")
    \\    mut kept = Row(name="k", alt="k")
    \\    if n > 3:
    \\        kept = Row(name=copy(sc.name), alt="early")
    \\    return Row(name=kept.name + sc.name, alt="late")
    \\
    \\
    \\func around_loop(n: int) -> Row:
    \\    const sc = Row(name="n" + str(n), alt="a")
    \\    for k in range(3):
    \\        if k > n:
    \\            return Row(name=copy(sc.name), alt="early")
    \\    return Row(name=own sc.name, alt="late")
    \\
    \\
    \\func loop_later(ns: int[]) -> str:
    \\    mut kept = "none"
    \\    mut seen = ""
    \\    for n in ns:
    \\        const t = "t" + str(n)
    \\        kept = copy(t)
    \\        seen += t
    \\    return kept + seen
    \\
    \\
    \\func size_of(text: str) -> int?:
    \\    return Some(len(text))
    \\
    \\
    \\func in_match(n: int) -> str:
    \\    const asked = "v" + str(n)
    \\    match size_of(asked):
    \\        case Some(size):
    \\            if size > 3:
    \\                return copy(asked)
    \\        case None:
    \\            pass
    \\    return "none" + asked
    \\
    \\
    \\func in_with(fs: Filesystem, n: int) -> str:
    \\    const asked = "d" + str(n)
    \\    with fs.open(asked, "r") as file:
    \\        if len(file.readlines()) > 0:
    \\            return copy(asked)
    \\    return "none" + asked
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, same_statement(1).name, after_if(2).name, around_loop(3).name, loop_later([1, 2]), in_match(4))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent where a read can follow the copy in a return (COPY-A1c)" {
    const found = try copies(early_return_read);
    defer freeWarnings(found);
    // Case (v) writes no move. The one field of a `const` local that only another field is read beside is the `take` of case (x).
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("take(mut sc.name)", found[0].edit_text);
}

/// The last of several copies of one local in one constructor, list or call (COPY-A1c): the others run before it.
const last_of_several =
    \\record Row:
    \\    name: str
    \\    alt: str
    \\
    \\
    \\func pair(own a: str, own b: str) -> str:
    \\    return a + "/" + b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const s = "s" + str(1)
    \\    const r = Row(alt=copy(s), name=copy(s))
    \\    const t = "t" + str(2)
    \\    const u = pair(b=copy(t), a=copy(t))
    \\    const v = "v" + str(3)
    \\    const xs = [copy(v), copy(v), copy(v)]
    \\    const w = "w" + str(4)
    \\    const ys = pair(copy(w), copy(w))
    \\    const x = "x" + str(5)
    \\    const z = Row(name=copy(x), alt=copy(x))
    \\    print(out, r.name, u, xs[2], ys, z.alt)
    \\    return 0
;

test "W_NEEDLESS_COPY (v) moves the last of several copies of one local in an operand list (COPY-A1c)" {
    const found = try copies(last_of_several);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 5), found.len);
    try t.expectEqualStrings("`s` is never used again, so pass `own s` and the copy becomes a move", found[0].message);
    const fixed = try repairedAll(last_of_several, found);
    defer t.allocator.free(fixed);
    try t.expect(std.mem.indexOf(u8, fixed, "Row(alt=copy(s), name=own s)") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "pair(b=copy(t), a=own t)") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "[copy(v), copy(v), own v]") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "pair(copy(w), own w)") != null);
    try t.expect(std.mem.indexOf(u8, fixed, "Row(name=copy(x), alt=own x)") != null);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// Another mention of the local that is not an earlier copy in an operand of the same constructor, list or call.
const several_silent =
    \\record Row:
    \\    name: str
    \\    alt: str
    \\
    \\
    \\func pair(own a: str, own b: str) -> str:
    \\    return a + "/" + b
    \\
    \\
    \\func bang(own a: str) -> str:
    \\    return a + "!"
    \\
    \\
    \\func later_read(n: int) -> Row:
    \\    const s = "s" + str(n)
    \\    return Row(name=copy(s), alt=str(len(s)))
    \\
    \\
    \\func joined(n: int) -> Row:
    \\    const s = "s" + str(n)
    \\    return Row(name=copy(s) + "x", alt=copy(s))
    \\
    \\
    \\func nested(n: int) -> Row:
    \\    const s = "s" + str(n)
    \\    return Row(name=bang(copy(s)), alt=copy(s))
    \\
    \\
    \\func spelled(n: int) -> Row:
    \\    const s = "s" + str(n)
    \\    return Row(name=f"{s}x", alt=copy(s))
    \\
    \\
    \\func inside_one(n: int) -> str:
    \\    const s = "s" + str(n)
    \\    return pair(bang(copy(s)), s)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, later_read(1).name, joined(2).name, nested(3).name, spelled(4).name, inside_one(5))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent where another mention is not an earlier copy of the same operand list (COPY-A1c)" {
    const found = try copies(several_silent);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// A last use inside a `with` block whose head does not name the value (COPY-A1c): the body runs once and the scope holds only
/// what its head reads.
const in_with_body =
    \\import filesystem
    \\
    \\record State:
    \\    path: str
    \\    other: str
    \\
    \\
    \\func serve(fs: Filesystem, base: str) -> int:
    \\    const sums_path = base + ".sums"
    \\    with fs.open(base, "r") as held:
    \\        const state = State(path=copy(sums_path), other="x")
    \\        return len(held.readlines()) + len(state.path)
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut fs = filesystem.memory()
    \\    _ = fs.write_text("a.txt", "hello\nworld\n")
    \\    print(out, serve(fs, "a.txt"))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) moves the last use inside a `with` body whose head does not name the value (COPY-A1c)" {
    const found = try copies(in_with_body);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`sums_path` is never used again, so pass `own sums_path` and the copy becomes a move", found[0].message);
    try t.expectEqualStrings("own sums_path", found[0].edit_text);
    const fixed = try repairedAll(in_with_body, found);
    defer t.allocator.free(fixed);
    const remaining = try copies(fixed);
    defer freeWarnings(remaining);
    try t.expectEqual(@as(usize, 0), remaining.len);
}

/// A `with` whose head names the value, a value declared outside a loop the `with` sits in, and a later read of the value.
const with_silent =
    \\import filesystem
    \\import parallel
    \\
    \\record State:
    \\    path: str
    \\    other: str
    \\
    \\
    \\func named_in_head(fs: Filesystem, n: int) -> int:
    \\    const base = "d" + str(n)
    \\    with fs.open(base, "r") as held:
    \\        const state = State(path=copy(base), other="x")
    \\        return len(held.readlines()) + len(state.path)
    \\
    \\
    \\func around_loop(fs: Filesystem, n: int) -> int:
    \\    const path = "p" + str(n)
    \\    mut total = 0
    \\    for k in range(2):
    \\        with fs.open("a.txt", "r") as held:
    \\            const state = State(path=copy(path), other="x")
    \\            total += len(held.readlines()) + len(state.path)
    \\    return total
    \\
    \\
    \\func read_later(fs: Filesystem, n: int) -> int:
    \\    const path = "p" + str(n)
    \\    with fs.open("a.txt", "r") as held:
    \\        const state = State(path=copy(path), other="x")
    \\        _ = print_len(held.readlines(), state)
    \\    return len(path)
    \\
    \\
    \\func print_len(lines: str[], state: State) -> int:
    \\    return len(lines) + len(state.path)
    \\
    \\
    \\func task_len(text: str) -> int:
    \\    return len(text)
    \\
    \\
    \\func in_group(n: int) -> int:
    \\    const path = "p" + str(n)
    \\    mut total = 0
    \\    with parallel.group() as g:
    \\        const task = g.submit(task_len, path)
    \\        const state = State(path=copy(path), other="x")
    \\        total = task.result() + len(state.path)
    \\    return total
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    mut fs = filesystem.memory()
    \\    _ = fs.write_text("a.txt", "hello\nworld\n")
    \\    print(out, named_in_head(fs, 1), around_loop(fs, 2), read_later(fs, 3), in_group(4))
    \\    return 0
;

test "W_NEEDLESS_COPY (v) stays silent where a `with` holds the value or the body runs again (COPY-A1c)" {
    const found = try copies(with_silent);
    defer freeWarnings(found);
    for (found) |item| std.debug.print("unexpected: {s}\n", .{item.message});
    try t.expectEqual(@as(usize, 0), found.len);
}

/// An earlier copy passed to a read-only parameter is deleted by its own repair, so the later one cannot move beside it.
const mixed_parameters =
    \\func mix(a: str, own b: str) -> str:
    \\    return a + "/" + b
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    const s = "s" + str(1)
    \\    const u = mix(copy(s), copy(s))
    \\    print(out, u)
    \\    return 0
;

test "W_NEEDLESS_COPY (v) leaves the later copy beside an earlier one a read-only parameter takes (COPY-A1c)" {
    const found = try copies(mixed_parameters);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("`mix` only reads `s`, so pass `s` itself rather than a copy", found[0].message);
}

/// A copy of a value with no managed part at its last use (COPY-A1d): the repair is the bare value, because `own` on such a value
/// is `E_OWN_MARKER`. A value with one managed field keeps `own`.
const plain_values =
    \\record Colour:
    \\    red: int
    \\    green: int
    \\
    \\
    \\record Holder:
    \\    name: str
    \\    colour: Colour
    \\
    \\
    \\record Tagged:
    \\    name: str
    \\    level: int
    \\
    \\
    \\func make_colour(n: int) -> Colour:
    \\    return Colour(red=n, green=n + 1)
    \\
    \\
    \\func make_holder(n: int) -> Holder:
    \\    return Holder(name="h", colour=make_colour(n))
    \\
    \\
    \\func make_tagged(n: int) -> Tagged:
    \\    return Tagged(name="t", level=n)
    \\
    \\
    \\func store_record(n: int) -> Colour[]:
    \\    mut fills: Colour[] = []
    \\    const fill = make_colour(n)
    \\    append(mut fills, copy(fill))
    \\    return fills
    \\
    \\
    \\func store_field(n: int) -> Colour[]:
    \\    mut fills: Colour[] = []
    \\    const holder = make_holder(n)
    \\    append(mut fills, copy(holder.colour))
    \\    return fills
    \\
    \\
    \\func store_option(n: int) -> int?[]:
    \\    mut found: int?[] = []
    \\    const maybe: int? = Some(n)
    \\    append(mut found, copy(maybe))
    \\    return found
    \\
    \\
    \\func give_back(n: int) -> Colour:
    \\    const fill = make_colour(n)
    \\    return copy(fill)
    \\
    \\
    \\func store_tagged(n: int) -> Tagged[]:
    \\    mut tags: Tagged[] = []
    \\    const tag = make_tagged(n)
    \\    append(mut tags, copy(tag))
    \\    return tags
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, f"{len(store_record(1))} {len(store_field(1))} {len(store_option(1))} {give_back(1).red} {len(store_tagged(1))}")
    \\    return 0
;

test "W_NEEDLESS_COPY writes the bare value for a copy of a value with no managed part, and `own` for one with a managed field (COPY-A1d)" {
    const found = try copies(plain_values);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 5), found.len);
    const wording = "holds no managed value, so `copy(";
    try t.expectEqualStrings("`fill` holds no managed value, so `copy(fill)` copies nothing a plain use would not: write `fill`", found[0].message);
    try t.expectEqualStrings("fill", found[0].edit_text);
    try t.expectEqual(@as(usize, 0), found[0].more.len);
    try t.expectEqualStrings("`holder.colour` holds no managed value, so `copy(holder.colour)` copies nothing a plain use would not: write `holder.colour`", found[1].message);
    try t.expectEqualStrings("holder.colour", found[1].edit_text);
    try t.expect(std.mem.indexOf(u8, found[2].message, wording) != null);
    try t.expectEqualStrings("maybe", found[2].edit_text);
    try t.expectEqualStrings("`fill` holds no managed value, so `copy(fill)` copies nothing a plain use would not: write `fill`", found[3].message);
    try t.expectEqualStrings("fill", found[3].edit_text);
    try t.expectEqualStrings("`tag` is never used again, so pass `own tag` and the copy becomes a move", found[4].message);
    try t.expectEqualStrings("own tag", found[4].edit_text);
    for (found) |item| try expectRepairLeaves(plain_values, item, 4);
}

/// The same copies where the value is used again: a copy of a plain value in a position that stores it stays silent, as before
/// (the finding is the last use's), and a copy of a managed one is unchanged.
const plain_used_again =
    \\record Colour:
    \\    red: int
    \\    green: int
    \\
    \\
    \\func make_colour(n: int) -> Colour:
    \\    return Colour(red=n, green=n + 1)
    \\
    \\
    \\func store_twice(n: int) -> Colour[]:
    \\    mut fills: Colour[] = []
    \\    const fill = make_colour(n)
    \\    append(mut fills, copy(fill))
    \\    append(mut fills, copy(fill))
    \\    return fills
    \\
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, f"{len(store_twice(1))}")
    \\    return 0
;

test "W_NEEDLESS_COPY of a plain value used again keeps one finding, the last use's, written bare (COPY-A1d)" {
    const found = try copies(plain_used_again);
    defer freeWarnings(found);
    try t.expectEqual(@as(usize, 1), found.len);
    try t.expectEqualStrings("fill", found[0].edit_text);
    try expectRepairChecks(plain_used_again, found[0]);
}
