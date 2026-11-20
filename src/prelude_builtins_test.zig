//! Prelude builtins reachable by their ordinary Python name without an import.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const tuple_before = @import("tuple_retirement_before.zig");

/// The program `text` returns `expected` (run with the test's other programs).
fn run(programs: *native.Cases, text: []const u8, expected: i64) !void {
    try programs.returns("prelude.selka", text, expected);
}

/// The program `text` traps with `code` (run with the test's other programs).
fn trapped(programs: *native.Cases, text: []const u8, code: []const u8) !void {
    try programs.traps("prelude-trap.selka", text, code, null);
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "prelude-invalid.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

/// `text` is refused with `E_METHOD_REMOVED` first, whose message and fix write `replacement` (W13-S5), and the rule
/// the method call also broke is reported next as `then`.
fn rejectMethodForm(text: []const u8, replacement: []const u8, then: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "prelude-invalid.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const items = compilation.diagnostics.items;
    try t.expectEqualStrings("E_METHOD_REMOVED", items[0].code);
    try t.expect(std.mem.indexOf(u8, items[0].message, replacement) != null);
    try t.expectEqualStrings(replacement, items[0].provenance.fix.?.edit.text);
    try t.expectEqualStrings(then, items[1].code);
}

fn rejectMigration(text: []const u8, replacement: []const u8, token: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "removed.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_REMOVED_SPELLING", item.code);
    try t.expectEqualStrings(token, compilation.src.text(item.span));
    try t.expect(std.mem.indexOf(u8, item.message, replacement) != null);
}

fn rejectRemovedLexicalNames() !void {
    const cases = [_]struct { spelling: []const u8, replacement: []const u8 }{
        .{ .spelling = "filesystem_cap", .replacement = "Filesystem" },
        .{ .spelling = "network_cap", .replacement = "Network" },
        .{ .spelling = "clock_cap", .replacement = "Clock" },
        .{ .spelling = "random_cap", .replacement = "Entropy" },
        .{ .spelling = "environment_cap", .replacement = "Environment" },
        .{ .spelling = "codec_encode", .replacement = "codec" },
        .{ .spelling = "codec_decode", .replacement = "codec" },
        .{ .spelling = "f64_add", .replacement = "float" },
        .{ .spelling = "f64_sub", .replacement = "float" },
        .{ .spelling = "f64_mul", .replacement = "float" },
        .{ .spelling = "f64_div", .replacement = "float" },
        .{ .spelling = "f64_eq", .replacement = "float" },
        .{ .spelling = "f64_lt", .replacement = "float" },
        .{ .spelling = "f64_le", .replacement = "float" },
        .{ .spelling = "f64_sqrt", .replacement = "sqrt" },
        .{ .spelling = "f64_floor", .replacement = "floor" },
        .{ .spelling = "f64_ceil", .replacement = "ceil" },
        .{ .spelling = "f64_trunc", .replacement = "trunc" },
        .{ .spelling = "f64_abs", .replacement = "abs" },
        .{ .spelling = "f64_neg", .replacement = "float" },
        .{ .spelling = "f64_from_u64", .replacement = "float" },
        .{ .spelling = "f64_to_u64", .replacement = "int" },
    };
    // An unreserved word (stage 0, F7) is an ordinary identifier, so only a *use*
    // of its spelling reports the migration and the case compiles one.
    for (cases) |case| try rejectRemovedUse(case.spelling, case.replacement);
}

/// Compile one use of a removed spelling — a capability type for a `*_cap` word, a
/// call for the float and codec families — and require its migration message.
fn rejectRemovedUse(spelling: []const u8, replacement: []const u8) !void {
    const text = if (std.mem.endsWith(u8, spelling, "_cap"))
        try std.fmt.allocPrint(t.allocator, "func main(x: {s}) -> int:\n    _ = x\n    return 0\n", .{spelling})
    else
        try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    _ = {s}(1)\n    return 0\n", .{spelling});
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "removed.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    var found = false;
    for (compilation.diagnostics.items) |item| {
        if (!std.mem.eql(u8, item.code, "E_REMOVED_SPELLING")) continue;
        try t.expect(std.mem.indexOf(u8, item.message, replacement) != null);
        found = true;
        break;
    }
    try t.expect(found);
}

// spec: PRELUDE-FOLD-1
test "sum adds a list of ints or floats and rejects other element types" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    return sum([1, 2, 3])\n", 6);
    try run(&programs, "func main() -> int:\n    return sum([])\n", 0);
    try run(&programs, "func main() -> int:\n    mut xs: int[] = []\n    return sum(xs)\n", 0);
    try run(&programs, "func main() -> int:\n    return int(sum([0.5, 1.25]) * 2.0)\n", 3);
    try reject("func main() -> int:\n    return sum([True])\n", "E_PRELUDE_TYPE");
    try programs.check();
}

// spec: PRELUDE-EXTREME-1
test "min and max accept a list or two scalars and trap on an empty list" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    return min([3, 1, 2])\n", 1);
    try run(&programs, "func main() -> int:\n    return max([3, 1, 2])\n", 3);
    try run(&programs, "func main() -> int:\n    return min(4, 2) + max(4, 2)\n", 6);
    try run(&programs, "func main() -> int:\n    if min([1.5, 0.5]) == 0.5:\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    if min([\"pear\", \"apple\"]) == \"apple\":\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    if min(1.5, 0.5) == 0.5 and max(1.5, 0.5) == 1.5:\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    if max(\"pear\", \"apple\") == \"pear\":\n        return 1\n    return 0\n", 1);
    try trapped(&programs, "func main() -> int:\n    mut xs: int[] = []\n    return min(xs)\n", "R_LIST_BOUNDS");
    try trapped(&programs, "func main() -> int:\n    return min([])\n", "R_LIST_BOUNDS");
    try trapped(&programs, "func main() -> int:\n    return max([])\n", "R_LIST_BOUNDS");
    try reject("func main() -> int:\n    return min([1], [2])\n", "E_PRELUDE_TYPE");
    try run(&programs,
        \\@noalloc
        \\func choose(words: str[]) -> bool:
        \\    return min(words) == "apple" and max(words) == "é"
        \\
        \\func main() -> int:
        \\    if choose(["é", "z", "apple"]):
        \\        return 1
        \\    return 0
    , 1);
    try run(&programs,
        \\func choose(words: str[]) -> str:
        \\    return copy(min(words))
        \\
        \\func main() -> int:
        \\    mut words = ["é", "z", "apple"]
        \\    const selected = choose(words)
        \\    words[2] = "pear"
        \\    if selected == "apple" and min(words) == "pear":
        \\        return 1
        \\    return 0
    , 1);
    try programs.check();
}

// spec: PRELUDE-SORT-1
test "sorted returns a new ascending list for int, float and str" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    mut ys = sorted([2, 1])\n    return ys[0]\n", 1);
    try run(&programs, "func main() -> int:\n    mut xs = [3, 1, 2]\n    mut ys = sorted(xs)\n    return xs[0] * 10 + ys[0]\n", 31);
    try run(&programs, "func main() -> int:\n    mut words = sorted([\"pear\", \"apple\"])\n    if words[0] == \"apple\" and words[1] == \"pear\":\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    mut ys = sorted([2.5, 0.5, 4.0])\n    return int(ys[0] * 2.0)\n", 1);
    try run(&programs, "func main() -> int:\n    return len(sorted([]))\n", 0);
    try run(&programs, "func main() -> int:\n    mut ys = sorted([9, 8, 7, 6, 5, 4, 3, 2, 1, 0])\n    if ys[0] == 0 and ys[9] == 9 and ys[4] == 4:\n        return 1\n    return 0\n", 1);
    try run(&programs,
        \\func main() -> int:
        \\    mut values: int[] = []
        \\    mut n = 2048
        \\    while n > 0:
        \\        append(mut values, n)
        \\        n -= 1
        \\    mut alias = copy(values)
        \\    mut ordered = sorted(values)
        \\    if alias[0] == 2048 and ordered[0] == 1 and ordered[2047] == 2048:
        \\        return 1
        \\    return 0
    , 1);
    try run(&programs,
        \\func main() -> int:
        \\    mut nan = 0.0 / 0.0
        \\    mut values = sorted([nan, 2.0, 0.0 - 0.0, 0.0, 0.0 - 1.0])
        \\    if values[0] == 0.0 - 1.0 and values[1] == 0.0 and values[2] == 0.0 and values[3] == 2.0 and values[4] != values[4]:
        \\        return 1
        \\    return 0
    , 1);
    try reject("func main() -> int:\n    return len(sorted([True, False]))\n", "E_PRELUDE_TYPE");
    try programs.check();
}

// spec: PRELUDE-SORT-KEY-1
test "sorted keys order records stably and diagnose invalid inputs" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs,
        \\record Item:
        \\    key: int
        \\    position: int
        \\
        \\
        \\func item_key(item: Item) -> int:
        \\    return item.key
        \\
        \\func main() -> int:
        \\    mut items = [Item(key=2, position=0), Item(key=1, position=1), Item(key=2, position=2)]
        \\    mut ordered = sorted(items, key=item_key)
        \\    return ordered[0].position * 100 + ordered[1].position * 10 + ordered[2].position
    , 102);
    try reject("func identity(value: int) -> int:\n    return value\nfunc main() -> int:\n    return len(sorted(1, key=identity))\n", "E_PRELUDE_TYPE");
    // A `bool` key is ordered, False first; its body's own type is the key type.
    try run(&programs, "func above_one(v: int) -> bool:\n    return v > 1\nfunc main() -> int:\n    mut ys = sorted([3, 1, 2], key=above_one)\n    return ys[0] * 100 + ys[1] * 10 + ys[2]\n", 132);
    try run(&programs, "func negative(v: int) -> int:\n    return 0 - v\nfunc main() -> int:\n    mut ys = sorted([3, 1, 2], key=negative, reverse=True)\n    return ys[0] * 100 + ys[1] * 10 + ys[2]\n", 123);
    try programs.check();
}

test "a callback that allocates keeps the caller's managed locals alive" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs,
        \\record Entry:
        \\    name: str
        \\    id: int
        \\
        \\
        \\func label(e: Entry) -> int:
        \\    return strings.char_count(e.name + "!") + e.id
        \\
        \\
        \\func main() -> int:
        \\    mut entries: Entry[] = []
        \\    for i in range(300):
        \\        append(mut entries, Entry(name=chr(19968 + (i * 37) % 11), id=i))
        \\    mut k = label
        \\    mut keys: int[] = []
        \\    for i in range(len(entries)):
        \\        mut e = copy(entries[i])
        \\        append(mut keys, k(e))
        \\    for i in range(300):
        \\        if strings.char_count(entries[i].name) != 1:
        \\            return 1
        \\    return 42 + len(keys) - 300
    , 42);
    try programs.check();
}

// spec: LIST-SORT-KEY-2
test "keyed sorts reject bad keys, a non-bool reverse and misplaced operands" {
    const entry = "record Entry:\n    rank: int\n    id: int\n\n\n";
    // The key must take one element and return an ordered key.
    const unordered = "record Entry:\n    rank: int[]\n    id: int\n\n\n";
    try reject(unordered ++ "func main() -> int:\n    mut xs = [Entry(rank=[1], id=0)]\n    sort(mut xs, key=lambda e: e)\n    return 0\n", "E_LAMBDA_REMOVED");
    try reject(unordered ++ "func whole(e: Entry) -> Entry:\n    return e\n\n\nfunc main() -> int:\n    mut xs = [Entry(rank=[1], id=0)]\n    sort(mut xs, key=whole)\n    return 0\n", "E_SORT_KEY");
    try reject(entry ++ "func pair(a: Entry, b: Entry) -> int:\n    return a.rank\n\n\nfunc main() -> int:\n    mut xs = [Entry(rank=1, id=0)]\n    sort(mut xs, key=pair)\n    return 0\n", "E_SORT_KEY");
    try reject("func length(s: str) -> int:\n    return strings.char_count(s)\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    return len(sorted(xs, key=length))\n", "E_SORT_KEY");
    try reject(entry ++ "func main() -> int:\n    mut xs = [Entry(rank=1, id=0)]\n    sort(mut xs, key=5)\n    return 0\n", "E_SORT_KEY");
    // `reverse` is a bool, and both operands are keyword-only and single.
    try reject("func main() -> int:\n    mut xs = [2, 1]\n    sort(mut xs, reverse=1)\n    return xs[0]\n", "E_TYPE");
    try reject("func main() -> int:\n    mut xs = [2, 1]\n    sort(mut xs, True)\n    return xs[0]\n", "E_CALL_ARGUMENT");
    try reject("func main() -> int:\n    mut xs = [2, 1]\n    sort(mut xs, reverse=True, reverse=False)\n    return xs[0]\n", "E_CALL_ARGUMENT");
    try reject("func main() -> int:\n    mut xs = [2, 1]\n    return len(sorted(xs, order=True))\n", "E_CALL_ARGUMENT");
    try reject("func identity(value: int) -> int:\n    return value\nfunc main() -> int:\n    mut xs = [2, 1]\n    return len(sorted(xs, identity))\n", "E_CALL_ARGUMENT");
    // A sort with no key needs elements with a native order.
    try reject(entry ++ "func main() -> int:\n    mut xs = [Entry(rank=1, id=0)]\n    sort(mut xs, reverse=True)\n    return 0\n", "E_COLLECTION_METHOD");
    // Among the collection methods only a list's `sort` takes named operands;
    // every other one, `append` included now that it is a prelude function,
    // takes its arguments by position.
    // The method form itself is refused now (W13-S5); its function form, `lists.exchange`, is an ordinary function
    // whose parameters may be named, so the positional rule is still reported only after the refusal.
    const holder = "record Holder:\n    items: int[]\n\n\nfunc main() -> int:\n    mut h = Holder(items=[1])\n";
    try rejectMethodForm(entry ++ holder ++ "    _ = h.items.exchange(index=0, replacement=2)\n    return 0\n", "lists.exchange(mut h.items, index=0, replacement=2)", "E_CALL_ARGUMENT");
}

// spec-case: LIST-SORT-KEY-2
test "a mut key and a comparison function are rejected with their repair" {
    try reject("record Box:\n    n: int\n\n\nfunc grow(mut b: Box) -> int effects(mutation):\n    b.n = b.n + 1\n    return b.n\n" ++
        "\n\nfunc main() -> int:\n    mut xs = [Box(n=1)]\n    sort(mut xs, key=grow)\n    return 0\n", "E_EFFECTS_REMOVED");
    var compilation = try language.Compilation.init(t.allocator, "cmp.selka", "func order(a: int) -> int:\n    return a\n\n\nfunc main() -> int:\n    mut xs = [2, 1]\n    sort(mut xs, cmp=order)\n    return xs[0]\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_CALL_ARGUMENT", item.code);
    try t.expectEqualStrings("cmp", compilation.src.text(item.related.?.span));
    try t.expectEqualStrings("sort(mut values: T[], key: func(T) -> K, reverse: bool) -> Unit", item.provenance.requirement.?.message);
    try t.expect(std.mem.indexOf(u8, item.related.?.message, "sort.sort_by_compare(mut values, compare)") != null);
    try t.expect(std.mem.indexOf(u8, item.related.?.message, "sort.sort_by_compare_with") != null);
}

// spec-case: LIST-SORT-KEY-2
test "a key with no order and a key of two elements are told about the comparison sort" {
    const entry = "record Entry:\n    rank: int[]\n    id: int\n\n\n";
    const sorting = "func main() -> int:\n    mut xs = [Entry(rank=[1], id=0)]\n    sort(mut xs, key=";
    var first = try language.Compilation.init(t.allocator, "key.selka", entry ++ "func whole(e: Entry) -> Entry:\n    return e\n\n\n" ++ sorting ++ "whole)\n    return 0\n");
    defer first.deinit();
    try t.expectError(error.SourceError, first.check());
    try t.expectEqualStrings("E_SORT_KEY", first.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, first.diagnostics.items[0].message, "which has no order") != null);
    try t.expect(std.mem.indexOf(u8, first.diagnostics.items[0].message, "`sort.sort_by_compare(mut values, compare)` (`import sort`)") != null);
    var second = try language.Compilation.init(t.allocator, "key.selka", entry ++ "func pair(a: Entry, b: Entry) -> int:\n    return a.id - b.id\n\n\n" ++ sorting ++ "pair)\n    return 0\n");
    defer second.deinit();
    try t.expectError(error.SourceError, second.check());
    try t.expectEqualStrings("E_SORT_KEY", second.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, second.diagnostics.items[0].message, "a function of two elements is a comparison: call `sort.sort_by_compare(mut values, compare)`") != null);
}

// spec-case: LAMBDA-KEY-INFER-1
test "hintSortKeywords: a lambda key whose body does not type on its own is one E_SORT_KEY quoting why" {
    const program =
        \\record Entry:
        \\    rank: int
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [Entry(rank=1)]
        \\    sort(mut xs, key=lambda e: e.missing)
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "key.selka", program);
    defer compilation.deinit();
    // `hintSortKeywords` catches the failed inference's error.SourceError and
    // marks the lambda, so the never-typed lambda adds no E_LAMBDA_CONTEXT.
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqual(@as(usize, 1), compilation.diagnostics.items.len);
    const item = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_SORT_KEY", item.code);
    try t.expectEqualStrings("lambda e: e.missing", compilation.src.text(item.span));
    try t.expect(std.mem.startsWith(u8, item.message, "this lambda's key type cannot be inferred from its body (E_"));
    try t.expect(std.mem.endsWith(u8, item.message, "); write a top-level key function with a declared result and pass it by name"));
    // Preserve the retired lambda guest and the no-order rejection via a named key.
    try reject("record Entry:\n    rank: int\n\n\nfunc main() -> int:\n    mut xs = [Entry(rank=1)]\n    sort(mut xs, key=lambda e: [e.rank])\n    return 0\n", "E_LAMBDA_REMOVED");
    try reject("record Entry:\n    rank: int\nfunc ranks(e: Entry) -> int[]:\n    return [e.rank]\nfunc main() -> int:\n    mut xs = [Entry(rank=1)]\n    sort(mut xs, key=ranks)\n    return 0\n", "E_SORT_KEY");
}

// spec: LIST-SORT-KEY-3
test "keyed sorts keep text keys rooted and traps come from the first element in input order" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs,
        \\record Entry:
        \\    name: str
        \\    id: int
        \\
        \\
        \\record PairKey:
        \\    name: str
        \\    descending_id: int
        \\
        \\func pair_key(e: Entry) -> PairKey:
        \\    return PairKey(name=copy(e.name), descending_id=0 - e.id)
        \\
        \\func label(e: Entry) -> str:
        \\    return e.name + "!"
        \\
        \\
        \\func main() -> int:
        \\    mut entries: Entry[] = []
        \\    for i in range(300):
        \\        append(mut entries, Entry(name=chr(19968 + (i * 37) % 11), id=i))
        \\    sort(mut entries, key=label, reverse=True)
        \\    for i in range(1, 300):
        \\        if ord(entries[i - 1].name) < ord(entries[i].name):
        \\            return 1
        \\        if entries[i - 1].name == entries[i].name and entries[i - 1].id > entries[i].id:
        \\            return 2
        \\    mut copied = sorted(entries, key=pair_key)
        \\    if copied[0].name != chr(19968) or copied[299].name != chr(19978):
        \\        return 3
        \\    return 42
    , 42);
    // Element 1 overflows and element 2 divides by zero: keys are computed in
    // input order, so the overflow is the trap, before any element moves.
    try trapped(&programs,
        \\func fragile(value: int) -> int:
        \\    if value == 1:
        \\        return 9223372036854775807 + value
        \\    if value == 2:
        \\        return 10 // (value - 2)
        \\    return value
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [2, 0, 1, 3]
        \\    sort(mut xs, key=fragile)
        \\    return xs[0]
    , "R_DIVISION_BY_ZERO");
    try trapped(&programs,
        \\func fragile(value: int) -> int:
        \\    if value == 1:
        \\        return 9223372036854775807 + value
        \\    if value == 2:
        \\        return 10 // (value - 2)
        \\    return value
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [0, 1, 2, 3]
        \\    mut ys = sorted(xs, key=fragile, reverse=True)
        \\    return ys[0]
    , "R_OVERFLOW");
    try programs.check();
}

// spec: PRELUDE-ABS-1
test "abs is total for int and still a float operation for float" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    return abs(0 - 42)\n", 42);
    try run(&programs, "func main() -> int:\n    return abs(7)\n", 7);
    try run(&programs, "func main() -> int:\n    return int(abs(0.0 - 2.5) * 2.0)\n", 5);
    try trapped(&programs, "func main() -> int:\n    return abs(0 - 9223372036854775807 - 1)\n", "R_OVERFLOW");
    try programs.check();
}

// spec: PRELUDE-ROUND-1
test "round returns the nearest integral float with halves away from zero" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    return int(round(1.6))\n", 2);
    try run(&programs, "func main() -> int:\n    return int(round(2.5))\n", 3);
    try run(&programs, "func main() -> int:\n    return int(round(0.0 - 2.5))\n", 0 - 3);
    try run(&programs, "func main() -> int:\n    return int(round(0.4))\n", 0);
    try run(&programs, "func main() -> int:\n    mut x = 1.0 / 0.0\n    if x > 0.0 and round(x) == x:\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    mut x = 0.0 / 0.0\n    if x != x and round(x) != round(x):\n        return 1\n    return 0\n", 1);
    try reject("func main() -> int:\n    return int(round(2))\n", "E_PRELUDE_TYPE");
    try programs.check();
}

// spec: PRELUDE-FOLD-2
test "any and all fold a list of conditions" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    if any([False, True]) and all([True, True]):\n        return 42\n    return 0\n", 42);
    try run(&programs, "func main() -> int:\n    if all([]):\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    if any([]):\n        return 1\n    return 0\n", 0);
    try reject("func main() -> int:\n    return int(any([1]))\n", "E_PRELUDE_TYPE");
    try programs.check();
}

// FR25 item 5: the signatures an arity refusal prints write a list as the source does, `T[]`, not `list[T]`.
test "the arity refusal of a list builtin prints its signature with the list spelled T[]" {
    const sources = [_]struct { call: []const u8, message: []const u8 }{
        .{ .call = "sum(1, 2)", .message = "`sum(values: int[]) -> int, or sum(values: float[]) -> float` takes 1 argument, but this call passes 2" },
        .{ .call = "reversed()", .message = "`reversed(values: T[]) -> T[], or reversed(text: str) -> str` takes 1 argument, but this call passes 0" },
        .{ .call = "any(1, 2)", .message = "`any(conditions: bool[]) -> bool` takes 1 argument, but this call passes 2" },
        .{ .call = "all()", .message = "`all(conditions: bool[]) -> bool` takes 1 argument, but this call passes 0" },
    };
    for (sources) |source| {
        const text = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    return len(str({s}))\n", .{source.call});
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "arity.selka", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_ARITY", compilation.diagnostics.items[0].code);
        try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, source.message) != null);
    }
}

// spec: PRELUDE-ITERATION-1
test "reversed, list and zip iterate or materialise without a new runtime" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // The body must be able to read every name these forms bind; each binding is
    // marked initialized before the body even though locals are function-scoped.
    try run(&programs, "func main() -> int:\n    mut ys = list(reversed([1, 2]))\n    return len(ys)\n", 2);
    try run(&programs, "func main() -> int:\n    return list(reversed([4, 5, 6]))[0]\n", 6);
    try run(&programs, "func main() -> int:\n    for value in reversed([1, 2, 3]):\n        return value\n    return 0\n", 3);
    try run(&programs, "func main() -> int:\n    if list(reversed(\"abc\"))[0] == \"c\":\n        return 1\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    for value in reversed(\"abc\"):\n        if value == \"c\":\n            return 1\n        return 0\n    return 0\n", 1);
    try run(&programs, "func main() -> int:\n    mut total = 0\n    for a, b in zip([1, 2], [3, 4]):\n        total = total + a + b\n    return total\n", 10);
    try run(&programs, "func main() -> int:\n    mut total = 0\n    for a, b in zip([1, 2, 3], [4]):\n        total = total + a + b\n    return total\n", 5);
    try run(&programs, "func main() -> int:\n    for a, b in zip([], []):\n        return a + b\n    return 7\n", 7);
    try run(&programs, "func main() -> int:\n    return len(list(range(3)))\n", 3);
    try run(&programs, "func main() -> int:\n    return list(range(2, 5))[2]\n", 4);
    try run(&programs, "func main() -> int:\n    return len(list(range(0)))\n", 0);
    try run(&programs, "func main() -> int:\n    mut xs = [1, 2]\n    return len(list(xs))\n", 2);
    try run(&programs, "func main() -> int:\n    return len(list(range(0 - 1)))\n", 0);
    try run(&programs, "func main() -> int:\n    mut total = 0\n    for a, b in zip(\"ab\", \"cd\"):\n        total = total + strings.char_count(a) + strings.char_count(b)\n    return total\n", 4);
    try reject("func range(n: int) -> int[]:\n    return [9, 9]\n\n\nfunc main() -> int:\n    return list(range(3))[1]\n", "E_BUILTIN_FUNCTION_NAME");
    try reject("func main() -> int:\n    return len(zip([1], [2]))\n", "E_PRELUDE_TYPE");
    try programs.check();
}

test "reversed keeps move-only and pending Result copy refusals" {
    try reject(
        \\resource File: filesystem
        \\func inspect(values: File[]) -> int:
        \\    return len(reversed(values))
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\func main() -> int:
        \\    mut values: Result[int, str][] = []
        \\    const backward = reversed(values)
        \\    _ = values
        \\    _ = backward
        \\    return 0
    , "E_RESULT_OPERATION");
}

// spec: PRELUDE-SHADOW-2
test "a declared len called bare is refused, and a declared replace still shadows its prelude operation" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // A bare call of a prelude name is always the builtin (W6): `len` is a prelude function, `replace` is not one.
    try reject("func len(value: int) -> int:\n    return value + 1\n\nfunc main() -> int:\n    return len(41)\n", "E_BUILTIN_FUNCTION_NAME");
    try run(&programs, "func replace(value: int) -> int:\n    return value + 2\n\nfunc main() -> int:\n    return replace(40)\n", 42);
    try reject("func len(left: int, right: int) -> int:\n    return left + right\n\nfunc main() -> int:\n    return len(1)\n", "E_BUILTIN_FUNCTION_NAME");
    try reject("func replace() -> int:\n    return 0\n\nfunc main() -> int:\n    return replace(1, 2, 3)\n", "E_ARITY");
    try programs.check();
}

// spec: CANONICAL-LEN-1
test "len returns int for every supported receiver and dot len is removed" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs, "func main() -> int:\n    mut fixed: FixedArray[int, 2] = FixedArray[int, 2]([20, 22])\n    return len(fixed)\n", 2);
    try run(&programs, "func main() -> int:\n    mut values = [1, 2]\n    return len(values)\n", 2);
    try run(&programs, "func main() -> int:\n    mut mapping = {\"a\": 1}\n    return len(mapping)\n", 1);
    try run(&programs, "func main() -> int:\n    return strings.char_count(\"xy\")\n", 2);
    try run(&programs, "func main() -> int:\n    mut raw = b\"ab\"\n    return len(raw)\n", 2);
    try rejectMigration("func main() -> int:\n    mut values = [1]\n    return values.len()\n", "len(", "len");
    try programs.check();
}

// spec: REMOVED-SPELLING-1
test "removed names and punctuation report their canonical migration" {
    try rejectRemovedLexicalNames();
    // `List[T]` has no plain rename: `list[int]` is not a type, so the message
    // gives the manual repair (`int[]`) and carries no edit.
    try rejectMigration("func main() -> int:\n    mut values: List[int] = []\n    return len(values)\n", "`int[]`", "List");
    try rejectMigration("func main() -> int:\n    mut values = [1]\n    values.push(2)\n    return 0\n", "append", "push");
    try rejectMigration("func main() -> int:\n    mut values = {\"a\": 1}\n    if values.contains(\"a\"):\n        return 1\n    return 0\n", "in", "contains");
    try rejectMigration("def touch(values: mut list[int]) -> None:\n    values[0] = 1\n\n\ndef main() -> int:\n    values = [1]\n    touch(&values)\n    return 0\n", "as in `mut value`", "&");
    try rejectMigration("def main() -> int:\n    return 1 => 1\n", "no replacement", "=>");
    try rejectMigration("func main() -> int:\n    const value = 5\n    return ~value\n", "`bit_not(value)`", "~");
}

// spec: PRELUDE-TYPES-2
test "prelude types are registered from syntax instead of raw source text" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // `strings.encode` needs `import strings` (W13-S5), so these three run as embedded projects.
    const fixture = @import("stdlib_fixture.zig");
    try t.expectEqual(@as(i64, 4), try fixture.value(t.allocator, "import strings\n\nfunc main() -> int:\n    mut n = 4 // 2\n    mut raw: bytes = strings.encode(\"hi\")\n    return len(raw) + n\n"));
    try t.expectEqual(@as(i64, 2), try fixture.value(t.allocator, "import strings\n\nfunc main() -> int:\n    mut raw = strings.encode(\"hi\")\n    return len(raw)\n"));
    try t.expectEqual(@as(i64, 42), try fixture.value(t.allocator, "import strings\n\nfunc main() -> int:\n    # bytes after a comment stays ordinary syntax\n    mut raw: bytes = strings.encode(\"hi\")\n    return len(raw) + 40\n"));
    try run(&programs, "record bytes:\n    value: int\n\nrecord str:\n    value: int\n\nfunc main() -> int:\n    mut raw: bytes = bytes(value=20)\n    mut text: str = str(value=22)\n    return raw.value + text.value\n", 42);
    try programs.check();
}

// spec: RECORD-KEY-1
test "wave1 record sort keys compare nested managed fields and preserve stable reverse order" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs,
        \\record Inner:
        \\    label: str
        \\    octets: bytes
        \\record Key:
        \\    inner: Inner
        \\    rank: i8
        \\record Item:
        \\    label: str
        \\    rank: i8
        \\    position: int
        \\func key(item: Item) -> Key:
        \\    return Key(inner=Inner(label=item.label + "!", octets=b"x"), rank=item.rank)
        \\func main() -> int:
        \\    mut items = [Item(label="b", rank=-1i8, position=0), Item(label="a", rank=2i8, position=1), Item(label="b", rank=-1i8, position=2)]
        \\    const forward = sorted(items, key=key)
        \\    sort(mut items, key=key, reverse=True)
        \\    if forward[0].position != 1 or forward[1].position != 0 or forward[2].position != 2:
        \\        return 1
        \\    return items[0].position * 100 + items[1].position * 10 + items[2].position
    , 21);
    try programs.check();
}
// spec-case: RECORD-KEY-1
test "wave1 record empty sort keys preserve input order" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs,
        \\record Empty:
        \\    pass
        \\func key(item: int) -> Empty:
        \\    return Empty()
        \\func main() -> int:
        \\    mut values = [3, 1, 2]
        \\    const copy = sorted(values, key=key, reverse=True)
        \\    sort(mut values, key=key)
        \\    return copy[0] * 100 + values[1] * 10 + copy[2]
    , 312);
    try programs.check();
}
// spec-case: RECORD-KEY-1
test "wave1 record wide sort keys use every leaf beyond byte offsets" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    const text = try wideSortProgram();
    defer t.allocator.free(text);
    try run(&programs, text, 123);
    try programs.check();
}
// spec-case: RECORD-KEY-1
test "wave1 record dictionary and set keys retain nominal identity and structural hashing" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try run(&programs,
        \\record Key:
        \\    text: str
        \\    number: int
        \\func main() -> int:
        \\    mut values: dict[Key, int] = {}
        \\    values[Key(text="same", number=4)] = 42
        \\    const keys = {Key(text="same", number=4), Key(text="same", number=4)}
        \\    if len(keys) != 1:
        \\        return 1
        \\    return values[Key(text="same", number=4)]
    , 42);
    try reject("record A:\n    n: int\nrecord B:\n    n: int\nfunc main() -> int:\n    mut values: dict[A, int] = {}\n    values[B(n=1)] = 2\n    return 0\n", "E_TYPE");
    try programs.check();
}

fn wideSortProgram() ![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(t.allocator);
    try text.appendSlice(t.allocator, "record Wide:\n");
    for (0..40) |i| try text.print(t.allocator, "    f{d}: u64\n", .{i});
    try text.appendSlice(t.allocator, "func key(item: int) -> Wide:\n    return Wide(");
    for (0..40) |i| {
        if (i != 0) try text.appendSlice(t.allocator, ", ");
        try text.print(t.allocator, "f{d}=", .{i});
        try text.appendSlice(t.allocator, if (i == 39) "u64(item)" else "0u64");
    }
    try text.appendSlice(t.allocator, ")\nfunc main() -> int:\n    const values = sorted([3, 1, 2], key=key)\n    return values[0] * 100 + values[1] * 10 + values[2]\n");
    const result = try text.toOwnedSlice(t.allocator);
    return result;
}

// spec-case: RECORD-KEY-1
test "wave1 record keys retain original scalar record diagnostic input bytes" {
    // The original bytes are immutable, so `sort`'s retirement answers them
    // first; the migrated counterparts carry the record-key diagnostics.
    try reject(tuple_before.original_record_lambda, "E_METHOD_REMOVED");
    try reject(tuple_before.original_record_named, "E_METHOD_REMOVED");
    try reject(
        \\record Entry:
        \\    rank: int
        \\    id: int
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [Entry(rank=1, id=0)]
        \\    sort(mut xs, key=lambda e: e)
        \\    return 0
        \\
    , "E_LAMBDA_REMOVED");
    var compilation = try language.Compilation.init(t.allocator, "record-key-migrated.selka",
        \\record Entry:
        \\    rank: int
        \\    id: int
        \\
        \\
        \\func whole(e: Entry) -> Entry:
        \\    return e
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [Entry(rank=1, id=0)]
        \\    sort(mut xs, key=whole)
        \\    return 0
        \\
    );
    defer compilation.deinit();
    // `whole` returns `Entry`, whose scalar fields have a native order, so the
    // migrated counterpart is the valid program the original bytes spelled.
    try compilation.check();
}

// spec-case: LIST-SORT-KEY-2
test "wave1 record key mutability rejection survives effect retirement" {
    try reject(
        \\record Box:
        \\    n: int
        \\func grow(mut b: Box) -> int:
        \\    b.n = b.n + 1
        \\    return b.n
        \\func main() -> int:
        \\    mut xs = [Box(n=1)]
        \\    sort(mut xs, key=grow)
        \\    return 0
    , "E_SORT_KEY");
}

// spec-case: PY-COLLECTIONS-1
test "a narrowed optional answers the retired list spelling and its repair runs" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // The receiver dispatch never sees a narrowed optional, so the spelling used
    // to check clean; it is refused now, and the repair writes back through the
    // optional exactly as the method did.
    const refused =
        \\func f(mut maybe: int[]?, item: int) -> int:
        \\    if maybe is None:
        \\        return 0
        \\    maybe.append(item)
        \\    return len(maybe)
        \\func main() -> int:
        \\    mut xs: int[]? = Some([1])
        \\    return f(mut xs, 2)
    ;
    var compilation = try language.Compilation.init(t.allocator, "narrowed-method.selka", refused);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const diagnostic = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_METHOD_REMOVED", diagnostic.code);
    try t.expectEqualStrings("append(mut maybe, item)", diagnostic.provenance.fix.?.edit.text);
    try run(&programs,
        \\func f(mut maybe: int[]?, item: int) -> int:
        \\    if maybe is None:
        \\        return 0
        \\    append(mut maybe, item)
        \\    return len(maybe)
        \\func main() -> int:
        \\    mut xs: int[]? = Some([1])
        \\    mut size = f(mut xs, 2)
        \\    if xs is not None:
        \\        size += len(xs)
        \\    return size
    , 4);
    try programs.check();
}

test "take and exchange write only a place they can write whole, and refuse the rest" {
    const holder = "record Holder:\n    items: int[]\n    count: int\n\n\n";
    // The place is marked `mut`; it is a local, a record field, a list element or a `match mut` binding (G3 3A). A
    // dictionary value, an octet of text and a call result are no place, and a type with no default cannot be taken.
    try reject("func main() -> int:\n    mut xs = [1]\n    _ = take(xs)\n    return 0\n", "E_MUTATION_MARKER");
    try reject("func main() -> int:\n    mut d = {\"a\": [1]}\n    _ = take(mut d[\"a\"])\n    return 0\n", "E_ASSIGNMENT_TARGET");
    try reject("func main() -> int:\n    mut xs = [\"ab\"]\n    _ = take(mut xs[0][0])\n    return 0\n", "E_ASSIGNMENT_TARGET");
    try reject("func rows() -> int[][]:\n    return [[1]]\n\n\nfunc main() -> int:\n    _ = take(mut rows()[0])\n    return 0\n", "E_ASSIGNMENT_TARGET");
    try reject(holder ++ "func main() -> int:\n    mut h = Holder(items=[1], count=1)\n    _ = take(mut h.count)\n    return 0\n", "E_TAKE_TYPE");
    try reject(holder ++ "func main() -> int:\n    mut hs = [Holder(items=[1], count=1)]\n    _ = take(mut hs[0])\n    return 0\n", "E_TAKE_TYPE");
    try reject("func swap(mut a: Filesystem, own b: Filesystem) -> Filesystem:\n    return exchange(mut a, own b)\n\n\nfunc main(fs: Filesystem) -> int:\n    return 0\n", "E_TAKE_TYPE");
    try reject("func main() -> int:\n    const xs = [1]\n    _ = take(mut xs)\n    return 0\n", "E_IMMUTABLE");
    try reject("func main() -> int:\n    mut xs = [1]\n    _ = exchange(mut xs, \"x\")\n    return 0\n", "E_TYPE");
    try reject("func main() -> int:\n    mut xs = [1]\n    _ = take(mut xs, 2)\n    return 0\n", "E_ARITY");
}

test "an element take checks its index before anything moves, and a trapping replacement or loop body traps cleanly" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // The index is checked before the element is taken, so a trap leaves no hole in the list.
    try trapped(&programs, "func main() -> int:\n    mut xs = [[1], [2]]\n    const got = take(mut xs[5])\n    return len(got)\n", "R_LIST_BOUNDS");
    // The replacement is built before the place is read, so a trap while building it moves nothing.
    try trapped(&programs, "func boom(xs: int[][]) -> int[]:\n    return [xs[9][0]]\n\n\nfunc main() -> int:\n    mut xs = [[1], [2]]\n    const old = exchange(mut xs[0], boom(xs))\n    return len(old)\n", "R_LIST_BOUNDS");
    // A trap in the middle of a consuming loop ends the program with the rest of the list still owned by the drain.
    try trapped(&programs, "func main() -> int:\n    const rows = [[1], [], [3]]\n    mut total = 0\n    for row in own rows:\n        total += row[0]\n    return total\n", "R_LIST_BOUNDS");
    try programs.check();
}

test "take of a type with no default names the exchange to write instead" {
    var compilation = try language.Compilation.init(t.allocator, "prelude-take-type.selka", "record Pin:\n    pad: int\n\n\nfunc main() -> int:\n    mut pins = [Pin(pad=1)]\n    const pin = take(mut pins[0])\n    return pin.pad\n");
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_TAKE_TYPE", first.code);
    try t.expect(std.mem.indexOf(u8, first.message, "`Pin` has none; write exchange(mut place, value)") != null);
}

/// FR91B: the first diagnostic of `body` (after a record `Pair` of two `Piece` fields, which have no default) is `E_TAKE_TYPE`
/// and holds `piece`.
fn takeTypeAdvice(body: []const u8, piece: []const u8) !void {
    const head = "record Piece:\n    order: func(int, int) -> int\n    items: int[]\n\n\nrecord Pair:\n    lo: Piece\n    hi: Piece\n\n\n" ++
        "func total(own a: Piece, own b: Piece) -> int:\n    return len(a.items) + len(b.items)\n\n\n";
    const text = try std.mem.concat(t.allocator, u8, &.{ head, body, "\n\n\nfunc main() -> int:\n    return 0\n" });
    defer t.allocator.free(text);
    var compilation = try language.Compilation.init(t.allocator, "prelude-take-fields.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_TAKE_TYPE", first.code);
    try t.expect(std.mem.indexOf(u8, first.message, piece) != null);
}

test "FR91B take of a field with no default, beside a move of another field of the record, names the moves in one statement" {
    const advice = "`Piece` has none; move the fields with `own` in one statement instead, as in `total(own q.lo, own q.hi)`, which " ++
        "leaves nothing behind, or write exchange(mut place, value) with the value to leave";
    try takeTypeAdvice("func both(own p: Pair) -> int:\n    mut q = own p\n    return total(take(mut q.lo), take(mut q.hi))", advice);
    try takeTypeAdvice("func both(own p: Pair) -> int:\n    mut q = own p\n    return total(own q.lo, take(mut q.hi))", advice);
    // The other field moved in the statement before or after: the two moves, written in one call.
    try takeTypeAdvice("func both(own p: Pair) -> int:\n    mut q = own p\n    const lo = own q.lo\n    return total(own lo, take(mut q.hi))", "as in `f(own q.lo, own q.hi)`");
    try takeTypeAdvice("func both(own p: Pair) -> int:\n    mut q = own p\n    const lo = take(mut q.lo)\n    return total(own lo, take(mut q.hi))", "as in `f(own q.lo, own q.hi)`");
    // A `mut` parameter is the caller's: no field moves out of it with `own`, so the message keeps the exchange alone.
    try takeTypeAdvice("func both(mut q: Pair) -> int:\n    return total(take(mut q.lo), take(mut q.hi))", "`Piece` has none; write exchange(mut place, value) with the value to leave");
}

/// The refused program's first diagnostic must carry `code` and a repair whose text is `expected`.
fn rejectWithRepair(text: []const u8, code: []const u8, expected: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "prelude-repair.selka", text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, first.code);
    try t.expectEqualStrings(expected, first.provenance.fix.?.edit.text);
}

test "take and exchange mark their place like append: a missing, owned or extra marker carries its exact repair" {
    // M3: the place takes `mut`, and no other operand does. W2: `own` on the place becomes `mut`.
    try rejectWithRepair("func main() -> int:\n    mut xs = [1]\n    _ = take(xs)\n    return 0\n", "E_MUTATION_MARKER", "mut ");
    try rejectWithRepair("func main() -> int:\n    mut xs = [1]\n    _ = take(own xs)\n    return 0\n", "E_OWN_MARKER", "mut ");
    try rejectWithRepair("func main() -> int:\n    mut xs = [1]\n    mut ys = [2]\n    _ = exchange(mut xs, mut ys)\n    return 0\n", "E_MUTATION_MARKER", "");
    try rejectWithRepair("func drain[T](mut values: T[]) -> T[]:\n    return take(values)\n\n\nfunc main() -> int:\n    return 0\n", "E_MUTATION_MARKER", "mut ");
}

test "take and exchange answer an optional place with None and a generic place with its own type" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // An optional's empty value is `None`; `exchange` infers its optional replacement from the place.
    try run(&programs,
        \\func main() -> int:
        \\    mut found: int[]? = Some([1, 2])
        \\    const got = take(mut found)
        \\    const none = exchange(mut found, Some([7]))
        \\    if got is None or none is not None or found is None:
        \\        return 1
        \\    return 42
    , 42);
    // A template body checks the place and the replacement symbolically; each specialization decides the empty value.
    try run(&programs,
        \\func drain[T](mut values: T[]) -> T[]:
        \\    return take(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut xs = ["a", "b"]
        \\    const got = drain(mut xs)
        \\    return len(got) * 10 + len(xs) + 20
    , 40);
    try reject("func drain[T](mut value: T) -> T:\n    return take(mut value)\n\n\nfunc main() -> int:\n    mut n = 3\n    return drain(mut n)\n", "E_TAKE_TYPE");
    try programs.check();
}
