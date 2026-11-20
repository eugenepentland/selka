//! The one message of an Escape refusal says four things in a fixed order, on one line (`escape_message.zig`).
const std = @import("std");
const t = std.testing;
const escape = @import("escape_message.zig");

fn expectMessage(facts: escape.Facts, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings(expected, try escape.compose(arena.allocator(), facts));
}

test "an escape message names what is lent, its lender, what the destination needs and both repairs in that order" {
    try expectMessage(.{
        .lent = "source",
        .lender = .{ .local = "source" },
        .destination = .{ .binding = .{ .name = "destination", .mutable = true } },
        .repairs = .{ .give_or_copy = .{} },
    }, "a bare `source` only lends the local `source`, and the `mut` local `destination` needs its own value; " ++
        "write `own source` to give it, or `copy(source)` to keep both");
    try expectMessage(.{
        .lent = "o",
        .lender = .{ .own_parameter = "o" },
        .destination = .{ .binding = .{ .name = "c", .mutable = false } },
        .repairs = .{ .give_or_copy = .{} },
    }, "a bare `o` only lends the `own` parameter `o`, and the local `c` needs its own value; " ++
        "write `own o` to give it, or `copy(o)` to keep both");
}

test "a destination that outlives the lender says so, and one that does not says what it needs" {
    try expectMessage(.{
        .lent = "p",
        .lender = .{ .plain_parameter = "p" },
        .destination = .{ .field = .{ .record = "TextBox", .name = "value", .leaves = true } },
        .repairs = .copy,
    }, "a bare `p` only lends the plain parameter `p`, and field `value` of `TextBox` would keep it after the call returns; " ++
        "write `copy(p)` to keep both");
    try expectMessage(.{
        .lent = "p",
        .lender = .{ .plain_parameter = "p" },
        .destination = .{ .field = .{ .record = "TextBox", .name = "value", .leaves = false } },
        .repairs = .copy,
    }, "a bare `p` only lends the plain parameter `p`, and field `value` of `TextBox` needs its own value; " ++
        "write `copy(p)` to keep both");
    try expectMessage(.{
        .lent = "mr.name",
        .lender = .{ .mut_parameter = "mr" },
        .destination = .{ .element = .{ .noun = "list", .name = "out", .leaves = true } },
        .repairs = .copy,
    }, "`mr.name` is lent by the `mut` parameter `mr`, and the list `out` would keep it after the call returns; " ++
        "write `copy(mr.name)` to keep both");
    try expectMessage(.{
        .lent = "total",
        .lender = .{ .local = "owner" },
        .destination = .returned,
        .repairs = .copy,
    }, "`total` is lent by the local `owner`, and the returned value would keep it after `owner` ends; " ++
        "write `copy(total)` to keep both");
}

test "a written own on a lent name says that own cannot give it" {
    try expectMessage(.{
        .lent = "own p",
        .lender = .{ .plain_parameter = "p" },
        .destination = .{ .argument = .{ .callee = "keep_text", .parameter = "s" } },
        .repairs = .copy,
    }, "`own p` cannot give the plain parameter `p`, which only lends it, " ++
        "and the `own` parameter `s` of `keep_text` needs its own value; write `copy(p)` to keep both");
}

test "a return offers the repairs its fix makes: declare from, remove own and declare, or remove own" {
    try expectMessage(.{
        .lent = "value",
        .lender = .{ .plain_parameter = "value" },
        .destination = .returned,
        .repairs = .{ .declare_from = .{ .sources = "value" } },
    }, "a bare `value` only lends the plain parameter `value`, and the returned value would keep it after the call returns; " ++
        "declare the result `from value`, or write `copy(value)` to keep both");
    try expectMessage(.{
        .lent = "own p",
        .lender = .{ .plain_parameter = "p" },
        .destination = .returned,
        .repairs = .{ .written_own = .{ .declare = "p" } },
    }, "`own p` cannot give the plain parameter `p`, which only lends it, and the returned value would keep it after the call returns; " ++
        "remove `own` and declare the result `from p`, or write `copy(p)` to keep both");
    try expectMessage(.{
        .lent = "own r.item",
        .lender = .{ .plain_parameter = "r" },
        .destination = .returned,
        .repairs = .{ .written_own = .borrow },
    }, "`r.item` is lent by the plain parameter `r`, and the returned value would keep it after the call returns; " ++
        "remove `own` to return the declared borrow, or write `copy(r.item)` to keep both");
}

test "a lent expression is quoted without its own marker and cut at the first line or the quote limit" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings("ts[0]", try escape.quote(a, "own ts[0]"));
    try t.expectEqualStrings("owner", try escape.quote(a, "owner"));
    try t.expectEqualStrings("combine(a,...", try escape.quote(a, "combine(a,\n    b)"));
    const long = try a.alloc(u8, 60);
    @memset(long, 'x');
    const expected = try std.fmt.allocPrint(a, "{s}...", .{long[0..48]});
    try t.expectEqualStrings(expected, try escape.quote(a, long));
}

test "a cut expression is never spelled inside a repair, and the message stays on one line" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const message = try escape.compose(arena.allocator(), .{
        .lent = "first_text(r)\n    + more",
        .lender = .{ .plain_parameter = "r" },
        .destination = .returned,
        .repairs = .{ .give_or_copy = .{} },
    });
    try t.expectEqualStrings(
        "`first_text(r)...` is lent by the plain parameter `r`, and the returned value would keep it after the call returns; " ++
            "write `own` before it to give it, or wrap it in `copy(...)` to keep both",
        message,
    );
    try t.expect(std.mem.indexOfScalar(u8, message, '\n') == null);
}

test "a write through a binding that only lends its place names the binding and both repairs" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try t.expectEqualStrings(
        "`c` is lent by the local `owner`, and a write through `c` needs its own value; " ++
            "write `mut c = own owner` to give it, or `mut c = copy(owner)` to keep both",
        try escape.composeWrite(a, .{ .binding = "c", .place = "owner", .lender = .{ .local = "owner" }, .can_give = true }),
    );
    try t.expectEqualStrings(
        "`c` is lent by the plain parameter `p`, and a write through `c` needs its own value; write `mut c = copy(p.name)` to keep both",
        try escape.composeWrite(a, .{ .binding = "c", .place = "p.name", .lender = .{ .plain_parameter = "p" }, .can_give = false }),
    );
}

test "the repairs of a written own, a binding and a join each name the edit their fix makes" {
    try expectMessage(.{
        .lent = "own ts[0]",
        .lender = .{ .plain_parameter = "ts" },
        .destination = .{ .binding = .{ .name = "c", .mutable = false } },
        .repairs = .{ .written_own = .lend },
    }, "`ts[0]` is lent by the plain parameter `ts`, and the local `c` needs its own value; " ++
        "remove `own` to lend it, or write `copy(ts[0])` to keep both");
    try expectMessage(.{
        .lent = "own ts[0]",
        .lender = .{ .plain_parameter = "ts" },
        .destination = .{ .binding = .{ .name = "c", .mutable = true } },
        .repairs = .{ .written_own = .then_copy },
    }, "`ts[0]` is lent by the plain parameter `ts`, and the `mut` local `c` needs its own value; " ++
        "remove `own`, then write `copy(ts[0])` to keep both");
    try expectMessage(.{
        .lent = "ts[0]",
        .lender = .{ .plain_parameter = "ts" },
        .destination = .{ .binding = .{ .name = "c", .mutable = true } },
        .repairs = .{ .binding = .{ .constant = "c" } },
    }, "`ts[0]` is lent by the plain parameter `ts`, and the `mut` local `c` needs its own value; " ++
        "bind `c` as `const` to read it, or write `copy(ts[0])` to keep both");
    try expectMessage(.{
        .lent = "alias",
        .lender = .{ .local = "owner" },
        .destination = .{ .binding = .{ .name = "retained", .mutable = true } },
        .repairs = .{ .binding = .{ .initializer = .{ .binding = "alias", .give = true } } },
    }, "`alias` is lent by the local `owner`, and the `mut` local `retained` needs its own value; " ++
        "write `own` in the initializer of `alias` to give it, or wrap that initializer in `copy(...)` to keep both");
    try expectMessage(.{
        .lent = "part",
        .lender = .{ .local = "left" },
        .other = .{ .local = "right" },
        .destination = .{ .binding = .{ .name = "part", .mutable = false } },
        .repairs = .each_branch,
    }, "`part` is lent by the local `left` or the local `right`, and the local `part` needs its own value; " ++
        "wrap what each branch assigns in `copy(...)` to keep both");
    try expectMessage(.{
        .lent = "p.name",
        .lender = .{ .plain_parameter = "p" },
        .destination = .{ .binding = .{ .name = "last", .mutable = true, .outlives = true } },
        .repairs = .copy,
    }, "`p.name` is lent by the plain parameter `p`, and the `mut` local `last` would keep it after the call returns; " ++
        "write `copy(p.name)` to keep both");
}

test "a lent value stored in a set is advised sets.include, which copies only a new element" {
    try expectMessage(.{
        .lent = "e.key",
        .lender = .{ .plain_parameter = "entries" },
        .destination = .{ .element = .{ .noun = "set", .name = "seen", .leaves = false } },
        .repairs = .copy,
    }, "`e.key` is lent by the plain parameter `entries`, and the set `seen` needs its own value; " ++
        "write `sets.include(mut seen, e.key)` to keep both (it copies `e.key` only when the set does not hold it yet)");
    try expectMessage(.{
        .lent = "key",
        .lender = .{ .local = "key" },
        .destination = .{ .element = .{ .noun = "set", .name = "seen", .leaves = false } },
        .repairs = .{ .give_or_copy = .{} },
    }, "a bare `key` only lends the local `key`, and the set `seen` needs its own value; " ++
        "write `own key` to give it, or write `sets.include(mut seen, key)` to keep both (it copies `key` only when the set does not hold it yet)");
    try expectMessage(.{
        .lent = "e.key",
        .lender = .{ .plain_parameter = "entries" },
        .destination = .{ .element = .{ .noun = "list", .name = "names", .leaves = false } },
        .repairs = .copy,
    }, "`e.key` is lent by the plain parameter `entries`, and the list `names` needs its own value; write `copy(e.key)` to keep both");
}

test "the advice to bind a fresh record first names the shape the refused expression reads (FR27)" {
    try expectMessage(.{
        .lent = "Name(text=t).text[0:2]",
        .lender = .fresh_record,
        .destination = .{ .binding = .{ .name = "piece", .mutable = false } },
        .repairs = .copy,
    }, "`Name(text=t).text[0:2]` is lent by a temporary value, and the local `piece` needs its own value; " ++
        "write `copy(Name(text=t).text[0:2])` to keep both, or bind the record to a local first and slice that local's field");
    try expectMessage(.{
        .lent = "Bag(items=[t]).items[0]",
        .lender = .fresh_record,
        .destination = .{ .binding = .{ .name = "piece", .mutable = false } },
        .repairs = .copy,
    }, "`Bag(items=[t]).items[0]` is lent by a temporary value, and the local `piece` needs its own value; " ++
        "write `copy(Bag(items=[t]).items[0])` to keep both, or bind the record to a local first and read the element from that local");
    try expectMessage(.{
        .lent = "Name(text=t).text",
        .lender = .fresh_record,
        .destination = .{ .element = .{ .noun = "list", .name = "out", .leaves = false } },
        .repairs = .copy,
    }, "`Name(text=t).text` is lent by a temporary value, and the list `out` needs its own value; " ++
        "write `copy(Name(text=t).text)` to keep both, or bind the record to a local first and read that local's field");
    // A slice of an element of a local record is a view for a `const` binding as it is for a `mut` one, so both get one sentence (FR69).
    try expectMessage(.{
        .lent = "Bag(items=[t]).items[0][0:1]",
        .lender = .fresh_record,
        .destination = .{ .binding = .{ .name = "piece", .mutable = false } },
        .repairs = .copy,
    }, "`Bag(items=[t]).items[0][0:1]` is lent by a temporary value, and the local `piece` needs its own value; " ++
        "write `copy(Bag(items=[t]).items[0][0:1])` to keep both, or bind the record to a local first and slice that local's field");
    try expectMessage(.{
        .lent = "rows_of(t).rows[0].text[0:1]",
        .lender = .fresh_record,
        .destination = .{ .binding = .{ .name = "piece", .mutable = false } },
        .repairs = .copy,
    }, "`rows_of(t).rows[0].text[0:1]` is lent by a temporary value, and the local `piece` needs its own value; " ++
        "write `copy(rows_of(t).rows[0].text[0:1])` to keep both, or bind the record to a local first and slice that local's field");
    try expectMessage(.{
        .lent = "Bag(items=[t]).items[0][0:1]",
        .lender = .fresh_record,
        .destination = .{ .binding = .{ .name = "piece", .mutable = true } },
        .repairs = .copy,
    }, "`Bag(items=[t]).items[0][0:1]` is lent by a temporary value, and the `mut` local `piece` needs its own value; " ++
        "write `copy(Bag(items=[t]).items[0][0:1])` to keep both, or bind the record to a local first and slice that local's field");
    // A stored slice is still a slice of the local, and a returned value would keep a local's: only `copy(...)` is said.
    try expectMessage(.{
        .lent = "Name(text=t).text[0:2]",
        .lender = .fresh_record,
        .destination = .{ .element = .{ .noun = "list", .name = "out", .leaves = false } },
        .repairs = .copy,
    }, "`Name(text=t).text[0:2]` is lent by a temporary value, and the list `out` needs its own value; " ++
        "write `copy(Name(text=t).text[0:2])` to keep both");
    try expectMessage(.{
        .lent = "Bag(items=[t]).items[0]",
        .lender = .fresh_record,
        .destination = .returned,
        .repairs = .copy,
    }, "`Bag(items=[t]).items[0]` is lent by a temporary value, and the returned value would keep it after the statement ends; " ++
        "write `copy(Bag(items=[t]).items[0])` to keep both");
}

test "the projection a lent expression spells is read from its last bracket group, outside quotes and nested brackets" {
    try t.expectEqual(escape.Projection.slice, escape.projectionOf("Name(text=t).text[0:2]"));
    try t.expectEqual(escape.Projection.slice, escape.projectionOf("rows()[i].text[:n]"));
    try t.expectEqual(escape.Projection.element, escape.projectionOf("Bag(items=[t]).items[0]"));
    try t.expectEqual(escape.Projection.element, escape.projectionOf("Cfg(map={\"k\": 1}).map[\"a:b\"]"));
    try t.expectEqual(escape.Projection.element, escape.projectionOf("Bag(items=[t]).items[at[1:2]]"));
    try t.expectEqual(escape.Projection.field, escape.projectionOf("Name(text=t).text"));
    try t.expectEqual(escape.Projection.field, escape.projectionOf(""));
}

test "COPY-B1 a plain parameter that the function can take own is told that form before the copy" {
    try expectMessage(.{
        .lent = "name",
        .lender = .{ .plain_parameter = "name" },
        .destination = .{ .field = .{ .record = "Row", .name = "name", .leaves = true } },
        .repairs = .copy,
        .form = .{ .take_parameter = .{ .parameter = "name", .declared = "own name: str" } },
    }, "a bare `name` only lends the plain parameter `name`, and field `name` of `Row` would keep it after the call returns; " ++
        "declare `name` as `own name: str` and write `own name` here to take it (a caller then gives it with `own name`, " ++
        "or copies if it reads it again), or write `copy(name)` to keep both");
    // A field of a parameter: the parameter is declared, the field is given.
    try expectMessage(.{
        .lent = "other.name",
        .lender = .{ .plain_parameter = "other" },
        .destination = .{ .field = .{ .record = "Row", .name = "name", .leaves = true } },
        .repairs = .copy,
        .form = .{ .take_parameter = .{ .parameter = "other", .declared = "own other: Row" } },
    }, "`other.name` is lent by the plain parameter `other`, and field `name` of `Row` would keep it after the call returns; " ++
        "declare `other` as `own other: Row` and write `own other.name` here to take it (a caller then gives it with `own other`, " ++
        "or copies if it reads it again), or write `copy(other.name)` to keep both");
    // A declaration the source did not spell is named without its type.
    try expectMessage(.{
        .lent = "v",
        .lender = .{ .plain_parameter = "v" },
        .destination = .{ .element = .{ .noun = "list", .name = "out", .leaves = false } },
        .repairs = .copy,
        .form = .{ .take_parameter = .{ .parameter = "v" } },
    }, "a bare `v` only lends the plain parameter `v`, and the list `out` needs its own value; " ++
        "declare `v` as an `own` parameter and write `own v` here to take it (a caller then gives it with `own v`, " ++
        "or copies if it reads it again), or write `copy(v)` to keep both");
}

test "COPY-B1 a lender that is no plain parameter, a cut expression and a set keep the text that names the copy alone" {
    // A local, a `mut` parameter and an element of a loop over a parameter name the copy alone, as they did.
    try expectMessage(.{
        .lent = "item",
        .lender = .{ .plain_parameter = "items" },
        .destination = .{ .element = .{ .noun = "list", .name = "out", .leaves = true } },
        .repairs = .copy,
    }, "`item` is lent by the plain parameter `items`, and the list `out` would keep it after the call returns; write `copy(item)` to keep both");
    try expectMessage(.{
        .lent = "name",
        .lender = .{ .mut_parameter = "name" },
        .destination = .{ .field = .{ .record = "Row", .name = "name", .leaves = true } },
        .repairs = .copy,
    }, "a bare `name` only lends the `mut` parameter `name`, and field `name` of `Row` would keep it after the call returns; write `copy(name)` to keep both");
    // The form is written for the whole expression, so a cut one and a set (whose own call keeps both) fall back to the copy.
    try expectMessage(.{
        .lent = "p.some_very_long_field_name.another_quite_long_field_name.and_one_more_field",
        .lender = .{ .plain_parameter = "p" },
        .destination = .{ .element = .{ .noun = "list", .name = "out", .leaves = false } },
        .repairs = .copy,
        .form = .{ .take_parameter = .{ .parameter = "p", .declared = "own p: Row" } },
    }, "`p.some_very_long_field_name.another_quite_long_f...` is lent by the plain parameter `p`, and the list `out` needs its own value; " ++
        "wrap it in `copy(...)` to keep both");
    try expectMessage(.{
        .lent = "key",
        .lender = .{ .plain_parameter = "key" },
        .destination = .{ .element = .{ .noun = "set", .name = "seen", .leaves = false } },
        .repairs = .copy,
        .form = .{ .take_parameter = .{ .parameter = "key", .declared = "own key: str" } },
    }, "a bare `key` only lends the plain parameter `key`, and the set `seen` needs its own value; " ++
        "write `sets.include(mut seen, key)` to keep both (it copies `key` only when the set does not hold it yet)");
}

test "a pattern's layer is named by the pattern the author wrote, and a name the compiler made is never printed" {
    try expectMessage(.{
        .lent = "v",
        .lender = .{ .matched = "Ok(Some(v))" },
        .destination = .{ .element = .{ .noun = "list", .name = "all", .leaves = false } },
        .repairs = .copy,
    }, "`v` is lent by the value that `case Ok(Some(v))` matched, and the list `all` needs its own value; write `copy(v)` to keep both");
    try expectMessage(.{
        .lent = "v",
        .lender = .{ .local = "\x00pattern269.0" },
        .destination = .{ .element = .{ .noun = "list", .name = "all", .leaves = true } },
        .repairs = .copy,
    }, "`v` is lent by a temporary value, and the list `all` would keep it after the statement ends; write `copy(v)` to keep both");
    try expectMessage(.{
        .lent = "v",
        .lender = .{ .matched = "Ok(Some(v))" },
        .destination = .returned,
        .repairs = .copy,
    }, "`v` is lent by the value that `case Ok(Some(v))` matched, and the returned value would keep it after the match ends; " ++
        "write `copy(v)` to keep both");
}

test "a binding of a nested pattern is repaired by matching its layers, or by the copy alone when nothing can give them" {
    try expectMessage(.{
        .lent = "own v",
        .lender = .{ .matched = "Ok(Some(v))" },
        .destination = .{ .binding = .{ .name = "kept", .mutable = false } },
        .repairs = .{ .binding = .{ .pattern = .{ .binding = "v", .pattern = "Ok(Some(v))", .at = 8, .matched = .fresh } } },
    }, "`v` is lent by the value that `case Ok(Some(v))` matched, and the local `kept` needs its own value; " ++
        "to give it, match one layer at a time (`case Ok(inner):`, then `match own inner:` with `case Some(v):`, and keep `own v`), " ++
        "or write `copy(v)` to keep both");
    try expectMessage(.{
        .lent = "v",
        .lender = .{ .plain_parameter = "r" },
        .destination = .{ .binding = .{ .name = "kept", .mutable = false } },
        .repairs = .{ .binding = .{ .pattern = .{ .binding = "v", .pattern = "Some(Some(v))", .at = 10, .matched = .lent } } },
    }, "`v` is lent by the plain parameter `r`, and the local `kept` needs its own value; write `copy(v)` to keep both");
}

fn expectInvalidated(facts: escape.InvalidatedFacts, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings(expected, try escape.composeInvalidated(arena.allocator(), facts));
}

test "FR57 a slice view that a write to another field of its record invalidated names the write, then the repairs that copy nothing, then the copy" {
    try expectInvalidated(.{
        .view = "piece",
        .slice = "r.buf[r.pos:end]",
        .lender = .{ .mut_parameter = "r" },
        .change = .{ .kind = .write, .text = "r.pos = end + 1", .at = .{ .line = 7, .column = 5 } },
        .read = .{ .line = 8, .column = 27 },
        .reorder = true,
        .respan = true,
    }, "`piece` is the slice `r.buf[r.pos:end]`, lent by the `mut` parameter `r`, and the write to `r.pos` at line 7, column 5 " ++
        "changes `r` as a whole, so `piece` cannot be read at line 8, column 27; use `piece` before line 7, keep its span " ++
        "(the start and length) and slice again where it is read, or wrap the initializer of `piece` in `copy(...)` to keep both");
}

test "FR57 a write to the whole owner and a call that takes it mut say what changed, without 'as a whole' for the owner itself" {
    try expectInvalidated(.{
        .view = "piece",
        .slice = "xs[0:5]",
        .lender = .{ .local = "xs" },
        .change = .{ .kind = .write, .text = "xs = xs + \"!\"", .at = .{ .line = 7, .column = 5 } },
        .read = .{ .line = 8, .column = 20 },
        .reorder = true,
        .respan = true,
    }, "`piece` is the slice `xs[0:5]`, lent by the local `xs`, and the write to `xs` at line 7, column 5 changes `xs`, " ++
        "so `piece` cannot be read at line 8, column 20; use `piece` before line 7, keep its span (the start and length) and " ++
        "slice again where it is read, or wrap the initializer of `piece` in `copy(...)` to keep both");
    try expectInvalidated(.{
        .view = "piece",
        .slice = "r.buf[1:3]",
        .lender = .{ .mut_parameter = "r" },
        .change = .{ .kind = .write, .text = "mut r.buf", .at = .{ .line = 14, .column = 20 } },
        .read = .{ .line = 15, .column = 16 },
        .reorder = true,
        .respan = true,
    }, "`piece` is the slice `r.buf[1:3]`, lent by the `mut` parameter `r`, and the `mut` argument `r.buf` at line 14, column 20 " ++
        "changes `r` as a whole, so `piece` cannot be read at line 15, column 16; use `piece` before line 14, keep its span " ++
        "(the start and length) and slice again where it is read, or wrap the initializer of `piece` in `copy(...)` to keep both");
}

test "FR57 a move of the source offers neither the span nor, out of order, the reorder" {
    try expectInvalidated(.{
        .view = "piece",
        .slice = "xs[0:5]",
        .lender = .{ .local = "xs" },
        .change = .{ .kind = .move, .text = "xs", .at = .{ .line = 10, .column = 19 } },
        .read = .{ .line = 11, .column = 20 },
        .reorder = true,
        .respan = false,
    }, "`piece` is the slice `xs[0:5]`, lent by the local `xs`, and `xs` is given away at line 10, column 19, " ++
        "so `piece` cannot be read at line 11, column 20; use `piece` before line 10, or wrap the initializer of `piece` in " ++
        "`copy(...)` to keep both");
    try expectInvalidated(.{
        .view = "piece",
        .slice = "net.name[1:]",
        .lender = .{ .local = "xs" },
        .change = .{ .kind = .move, .text = "net", .at = .{ .line = 9, .column = 30 } },
        .read = .{ .line = 8, .column = 10 },
        .reorder = false,
        .respan = false,
    }, "`piece` is the slice `net.name[1:]`, lent by the local `xs`, and `net` at line 9, column 30 gives `xs` away, " ++
        "so `piece` cannot be read at line 8, column 10; wrap the initializer of `piece` in `copy(...)` to keep both");
}

test "FR57 a view that a loan found live at the change has no read to name and is told to finish with it first" {
    try expectInvalidated(.{
        .view = "suffix",
        .slice = "net.name[1:]",
        .lender = .{ .local = "xs" },
        .change = .{ .kind = .write, .text = "xs[0] = Net(name=b\"zz\", label=\"q\")", .at = .{ .line = 6, .column = 9 } },
        .reorder = true,
        .respan = false,
    }, "`suffix` is the slice `net.name[1:]`, lent by the local `xs`, and the write to `xs[0]` at line 6, column 9 changes `xs` as a " ++
        "whole, while `suffix` is still read after it; finish with `suffix` before line 6, or wrap the initializer of `suffix` in " ++
        "`copy(...)` to keep both");
}

test "FR57 a slice is spelled from its owner only when its first name is the owner's" {
    try t.expect(escape.startsWithName("r.buf[r.pos:end]", "r"));
    try t.expect(escape.startsWithName("  xs[0:5]", "xs"));
    try t.expect(!escape.startsWithName("r2.buf[1:]", "r"));
    try t.expect(!escape.startsWithName("net.name[1:]", "xs"));
    try t.expect(!escape.startsWithName("", "r"));
}

test "FR57 a slice too long to quote and a change the text cannot name keep the sentence readable" {
    try expectInvalidated(.{
        .view = "piece",
        .slice = "reader.buffer.contents[reader.position.offset:reader.limit.end]",
        .lender = .{ .local = "reader" },
        .change = .{ .kind = .write, .text = "reader.position.offset = limit + 1", .at = .{ .line = 20, .column = 5 } },
        .read = .{ .line = 21, .column = 12 },
        .reorder = true,
        .respan = false,
    }, "`piece` is a slice view lent by the local `reader`, and the write to `reader.position.offset` at line 20, column 5 " ++
        "changes `reader` as a whole, so `piece` cannot be read at line 21, column 12; use `piece` before line 20, " ++
        "or wrap the initializer of `piece` in `copy(...)` to keep both");
}

test "FR57 the written place of a compound assignment and of an element is the target, not the comparison or the operator" {
    try expectInvalidated(.{
        .view = "v",
        .slice = "r.buf[1:3]",
        .lender = .{ .mut_parameter = "r" },
        .change = .{ .kind = .write, .text = "r.count += 1", .at = .{ .line = 3, .column = 5 } },
        .read = .{ .line = 4, .column = 9 },
        .reorder = true,
        .respan = false,
    }, "`v` is the slice `r.buf[1:3]`, lent by the `mut` parameter `r`, and the write to `r.count` at line 3, column 5 changes `r` as a whole, " ++
        "so `v` cannot be read at line 4, column 9; use `v` before line 3, or wrap the initializer of `v` in `copy(...)` to keep both");
    try expectInvalidated(.{
        .view = "v",
        .slice = "xs[1:3]",
        .lender = .{ .local = "xs" },
        .change = .{ .kind = .write, .text = "xs[a == 1] = 2", .at = .{ .line = 3, .column = 5 } },
        .read = .{ .line = 4, .column = 9 },
        .reorder = false,
        .respan = false,
    }, "`v` is the slice `xs[1:3]`, lent by the local `xs`, and the write to `xs[a == 1]` at line 3, column 5 changes `xs` as a whole, " ++
        "so `v` cannot be read at line 4, column 9; wrap the initializer of `v` in `copy(...)` to keep both");
}
