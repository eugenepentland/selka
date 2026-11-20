//! A guessed library name is answered with what does the job for that kind of value, never with a module that cannot take it (lane MSG-F).
//!
//! Each row is a name an audit program really wrote (`strings.index`, `lists.find`, `strings.has`, `strings.len`, ...) with the exact message the
//! compiler gives, the one repair it offers (or none), and the spellings the message suggests. Every suggested spelling is checked in a
//! program of its own, so a suggestion can never again name a call that does not fit the value in hand (`bytes.index` for a text).
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const standard_library = @import("standard_library.zig");

/// The program every row is written into: one statement `const r = EXPRESSION`, with a value of each kind in hand. `main` may fail so that a
/// suggested call that fails (`strings.decode`) is written with `try`.
const head =
    \\import strings
    \\import bytes
    \\import lists
    \\import dicts
    \\import sets
    \\import sort
    \\import parallel
    \\
    \\
    \\func double(item: int) -> int:
    \\    return item * 2
    \\
    \\
    \\func main(out: Stream) -> int fails str:
    \\    const text = "hello"
    \\    const part = "ell"
    \\    const parts = ["a", "b"]
    \\    const data = b"hello"
    \\    const piece = b"ell"
    \\    const values = [1, 2, 3]
    \\    const value = 2
    \\    const mapping = {"a": 1}
    \\    const key = "a"
    \\    const seen = {1, 2}
    \\    const flags = [True, False]
    \\
;

/// One guessed name: the expression that was written, what the compiler says of it, the single repair (the span's text and what replaces it,
/// null for none) and the spellings the message suggests.
const Row = struct {
    guess: []const u8,
    message: []const u8,
    repair: ?[2][]const u8 = null,
    suggested: []const []const u8 = &.{},
    /// Spellings the message describes without writing them out (`text < part` for "the operators `<`, ..."): each must check too.
    described: []const []const u8 = &.{},
    /// Names the message offers without a call (`did you mean `strip`?`): each must appear in it between backticks.
    named: []const []const u8 = &.{},
    /// The message names a set `values`, so `values` is the set in the program of this row instead of the list.
    set_values: bool = false,
    /// Statements the message describes (a loop, for a job with no function): each is written into `main` and must check.
    bodies: []const []const u8 = &.{},
    /// Pieces of those statements the message quotes: each must appear in it between backticks and in one of `bodies`.
    pieces: []const []const u8 = &.{},
};

/// The program with `expression` as the value of `r`, and `values` a set when `set_values`; an `expression` that is a binding (`mut ...`) is the
/// whole body of `main`.
fn program(allocator: std.mem.Allocator, expression: []const u8, set_values: bool) ![]u8 {
    // A whole binding (`mut seen: set[str] = set()`) stands alone in a program of its own.
    if (std.mem.startsWith(u8, expression, "mut ")) return std.fmt.allocPrint(allocator, "func main(out: Stream) -> int:\n    {s}\n    print(out, \"x\")\n    return 0\n", .{expression});
    const values = if (set_values) try std.mem.replaceOwned(u8, allocator, head, "const values = [1, 2, 3]", "const values = {1, 2}") else head;
    return std.fmt.allocPrint(allocator, "{s}    const r = {s}\n    print(out, f\"{{r}}\")\n    return 0\n", .{ values, expression });
}

/// The program with the statements `body` in `main`, after the values of the head, and `values` a set when `set_values`.
fn bodyProgram(allocator: std.mem.Allocator, body: []const u8, set_values: bool) ![]u8 {
    const values = if (set_values) try std.mem.replaceOwned(u8, allocator, head, "const values = [1, 2, 3]", "const values = {1, 2}") else head;
    // A loop that names its own `key` and `value` takes them out of the head, where a second binding of the name would be refused.
    const named = if (std.mem.indexOf(u8, body, "key, value in") != null)
        try std.mem.replaceOwned(u8, allocator, try std.mem.replaceOwned(u8, allocator, values, "    const key = \"a\"\n", ""), "    const value = 2\n", "")
    else
        values;
    var text: std.ArrayList(u8) = .empty;
    try text.appendSlice(allocator, named);
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| try text.print(allocator, "    {s}\n", .{line});
    try text.appendSlice(allocator, "    print(out, \"x\")\n    return 0\n");
    return text.items;
}

/// Check `expression` in the program: it must be refused with `E_UNKNOWN_SYMBOL` and `row.message`, with the repair of `row`, and each suggestion
/// must appear in the message between backticks and check in a program of its own.
fn expectRow(allocator: std.mem.Allocator, row: Row) !void {
    const written = try program(allocator, row.guess, row.set_values);
    const refused = try fixture.check(allocator, written);
    try t.expect(!refused.passed);
    const item = refused.firstError().?;
    try t.expectEqualStrings("E_UNKNOWN_SYMBOL", item.code);
    try t.expectEqualStrings(row.message, item.message);
    if (row.repair) |wanted| {
        const fix = item.provenance.fix.?;
        try t.expectEqualStrings(wanted[0], refused.text(fix.edit.span));
        try t.expectEqualStrings(wanted[1], fix.edit.text);
        try t.expectEqual(@as(usize, 0), fix.more.len);
        const mended = try std.mem.concat(allocator, u8, &.{ written[0..fix.edit.span.start], fix.edit.text, written[fix.edit.span.end..] });
        const accepted = try fixture.check(allocator, mended);
        try t.expect(accepted.firstError() == null);
    } else try t.expect(item.provenance.fix == null);
    for (row.described) |spelling| {
        const accepted = try fixture.check(allocator, try program(allocator, spelling, row.set_values));
        try t.expect(accepted.firstError() == null);
    }
    for (row.bodies) |body| {
        const accepted = try fixture.check(allocator, try bodyProgram(allocator, body, row.set_values));
        try t.expect(accepted.firstError() == null);
    }
    for (row.pieces) |piece| {
        const quoted = try std.fmt.allocPrint(allocator, "`{s}`", .{piece});
        try t.expect(std.mem.indexOf(u8, row.message, quoted) != null);
        var found = false;
        for (row.bodies) |body| found = found or std.mem.indexOf(u8, body, piece) != null;
        try t.expect(found);
    }
    for (row.named) |name| {
        const quoted = try std.fmt.allocPrint(allocator, "`{s}`", .{name});
        try t.expect(std.mem.indexOf(u8, row.message, quoted) != null);
    }
    for (row.suggested) |spelling| {
        const quoted = try std.fmt.allocPrint(allocator, "`{s}`", .{spelling});
        try t.expect(std.mem.indexOf(u8, row.message, quoted) != null);
        const accepted = try fixture.check(allocator, try program(allocator, spelling, row.set_values));
        try t.expect(accepted.firstError() == null);
    }
}

fn expectRows(rows: []const Row) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for (rows) |row| try expectRow(arena.allocator(), row);
}

const text_index_message = "module `strings` declares no `index`; the byte offset of the first occurrence is `strings.text_index(text, part)`, which traps when " ++
    "`part` is absent (`strings.find(text, part)` answers `None` instead, and `strings.char_index(text, part)` counts Unicode scalars)";
const text_rindex_message = "module `strings` declares no `rindex`; the byte offset of the last occurrence is `strings.text_rindex(text, part)`, which traps when " ++
    "`part` is absent (`strings.rfind(text, part)` answers `None` instead, and `strings.char_rindex(text, part)` counts Unicode scalars)";
const in_text = "whether text holds a part is the operator `in`: write `part in text` (`lists.contains` is only for lists)";

test "a guessed name of text is answered with the call, operator or builtin that does the job for text" {
    try expectRows(&.{
        .{
            .guess = "strings.index(text, part)",
            .message = text_index_message,
            .suggested = &.{ "strings.text_index(text, part)", "strings.find(text, part)", "strings.char_index(text, part)" },
        },
        .{
            .guess = "strings.rindex(text, part)",
            .message = text_rindex_message,
            .suggested = &.{ "strings.text_rindex(text, part)", "strings.rfind(text, part)", "strings.char_rindex(text, part)" },
        },
        .{
            .guess = "strings.has(text, part)",
            .message = "module `strings` declares no `has`; " ++ in_text,
            .repair = .{ "strings.has(text, part)", "part in text" },
            .suggested = &.{"part in text"},
        },
        .{
            .guess = "strings.includes(text, part)",
            .message = "module `strings` declares no `includes`; " ++ in_text,
            .repair = .{ "strings.includes(text, part)", "part in text" },
            .suggested = &.{"part in text"},
        },
        .{
            .guess = "strings.contains(text, part)",
            .message = "module `strings` declares no `contains`; " ++ in_text,
            .repair = .{ "strings.contains(text, part)", "part in text" },
            .suggested = &.{"part in text"},
        },
        .{
            .guess = "strings.is_empty(text)",
            .message = "module `strings` declares no `is_empty`; whether text is empty is the builtin `len`: write `len(text) == 0`",
            .suggested = &.{"len(text) == 0"},
        },
        .{
            .guess = "strings.len(text)",
            .message = "module `strings` declares no `len`; the length of text is the builtin `len(text)`, which counts octets; `strings.char_count(text)` counts Unicode scalars",
            .suggested = &.{ "len(text)", "strings.char_count(text)" },
        },
        .{
            .guess = "strings.compare(text, part)",
            .message = "module `strings` declares no `compare`; texts compare with the operators `<`, `<=`, `==`, `!=`, `>=` and `>`, and `sort.compare_strs(a, b)` answers a negative number, zero or a positive number",
            .described = &.{ "text < part", "text >= part", "sort.compare_strs(text, part)" },
        },
        .{ .guess = "strings.empty()", .message = "module `strings` declares no `empty`; empty text is the literal `\"\"`", .suggested = &.{"\"\""} },
        .{ .guess = "bytes.empty()", .message = "module `bytes` declares no `empty`; empty bytes is the literal `b\"\"`", .suggested = &.{"b\"\""} },
    });
}

// `selka fix` runs after every check, so a rename that picks a behaviour would be applied unseen: `text_index` and `index_of` trap when the part is
// absent, and the author may have meant an answer of -1 (Go's `Index`) or `None` (`find`). The sentence names them; no edit is made.
test "strings.index, strings.rindex and lists.index name their functions and carry no fix" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    for ([_][]const u8{ "strings.index(text, part)", "strings.rindex(text, part)", "lists.index(values, value)" }) |guess| {
        const refused = try fixture.check(arena.allocator(), try program(arena.allocator(), guess, false));
        const item = refused.firstError().?;
        try t.expectEqualStrings("E_UNKNOWN_SYMBOL", item.code);
        try t.expect(item.provenance.fix == null);
    }
}

test "a guessed name of a list is answered with the call that does the job for a list" {
    const position = "the position of the first equal element is `lists.index_of(values, value)`, which traps when no element is equal (`lists.contains(values, value)` asks whether one is)";
    const holds = "whether a list holds a value is `lists.contains(values, value)` (a list has no operator `in`)";
    try expectRows(&.{
        .{
            .guess = "lists.index(values, value)",
            .message = "module `lists` declares no `index`; " ++ position,

            .suggested = &.{ "lists.index_of(values, value)", "lists.contains(values, value)" },
        },
        .{
            .guess = "lists.find(values, value)",
            .message = "module `lists` declares no `find`; " ++ position,
            .suggested = &.{ "lists.index_of(values, value)", "lists.contains(values, value)" },
        },
        .{
            .guess = "lists.has(values, value)",
            .message = "module `lists` declares no `has`; " ++ holds,
            .repair = .{ "has", "contains" },
            .suggested = &.{"lists.contains(values, value)"},
        },
        .{
            .guess = "lists.includes(values, value)",
            .message = "module `lists` declares no `includes`; " ++ holds,
            .repair = .{ "includes", "contains" },
            .suggested = &.{"lists.contains(values, value)"},
        },
        .{
            .guess = "lists.is_empty(values)",
            .message = "module `lists` declares no `is_empty`; whether a list is empty is the builtin `len`: write `len(values) == 0`",
            .suggested = &.{"len(values) == 0"},
        },
        .{ .guess = "lists.len(values)", .message = "module `lists` declares no `len`; the length of a list is the builtin `len(values)`", .suggested = &.{"len(values)"} },
        .{
            .guess = "lists.empty()",
            .message = "module `lists` declares no `empty`; an empty list is `[]` with its type named: `mut values: int[] = []`",
            .suggested = &.{"mut values: int[] = []"},
        },
    });
}

// The names an author from Python, JavaScript or Rust reaches for on a list: the language has a `for` loop where they write a lambda, builtins
// where they write `sum` or `enumerate`, and `parallel.map` for a named function on several threads. Every statement the message quotes is
// written into `main` and checked, so a loop in a message is one that compiles. No row has a repair: the rewrite is a loop.
test "a guessed name of a list that is a loop or a builtin in this language is answered with the form that does the job" {
    const head_values = "`for item in values:`";
    const each = "; to do something with every element, loop over it: " ++ head_values ++ ", and write the body under it";
    try expectRows(&.{
        .{
            .guess = "lists.map(values, double)",
            .message = "module `lists` declares no `map`; to apply a function to every element, loop and collect (a lambda is not written): `mut result: int[] = []`, " ++
                "then " ++ head_values ++ " with `append(mut result, item * 2)` in its body; `parallel.map(values, double)` applies a named function " ++
                "(`func double(item: int) -> int`) to every element on several threads",
            .bodies = &.{ "mut result: int[] = []\nfor item in values:\n    append(mut result, item * 2)", "const result = parallel.map(values, double)" },
            .pieces = &.{ "mut result: int[] = []", "for item in values:", "append(mut result, item * 2)", "parallel.map(values, double)" },
        },
        .{
            .guess = "lists.filter(values, value)",
            .message = "module `lists` declares no `filter`; to keep the elements that pass, loop and collect: `mut kept: int[] = []`, then " ++ head_values ++
                " with `if item > 1:` and `append(mut kept, item)` inside it",
            .bodies = &.{"mut kept: int[] = []\nfor item in values:\n    if item > 1:\n        append(mut kept, item)"},
            .pieces = &.{ "mut kept: int[] = []", "for item in values:", "if item > 1:", "append(mut kept, item)" },
        },
        .{
            .guess = "lists.reduce(values, value)",
            .message = "module `lists` declares no `reduce`; to combine the elements into one value, accumulate in a loop: `mut total = 0`, then " ++ head_values ++
                " with `total += item` in its body; `sum(values)` adds a list of `int` or of `float`",
            .suggested = &.{"sum(values)"},
            .bodies = &.{"mut total = 0\nfor item in values:\n    total += item"},
            .pieces = &.{ "mut total = 0", "for item in values:", "total += item" },
        },
        .{
            .guess = "lists.fold(values, value)",
            .message = "module `lists` declares no `fold`; to combine the elements into one value, accumulate in a loop: `mut total = 0`, then " ++ head_values ++
                " with `total += item` in its body; `sum(values)` adds a list of `int` or of `float`",
            .suggested = &.{"sum(values)"},
            .bodies = &.{"mut total = 0\nfor item in values:\n    total += item"},
        },
        .{
            .guess = "lists.each(values, double)",
            .message = "module `lists` declares no `each`" ++ each,
            .bodies = &.{"for item in values:\n    print(out, f\"{item}\")"},
            .pieces = &.{"for item in values:"},
        },
        .{
            .guess = "lists.for_each(values, double)",
            .message = "module `lists` declares no `for_each`" ++ each,
            .bodies = &.{"for item in values:\n    print(out, f\"{item}\")"},
        },
        .{
            .guess = "lists.any(values, double)",
            .message = "module `lists` declares no `any`; to ask whether some element passes, loop and keep the answer: `mut found = False`, then " ++ head_values ++
                " with `if item > 1:` and `found = True` inside it; the builtin `any(flags)` takes a list of `bool`",
            .suggested = &.{"any(flags)"},
            .bodies = &.{"mut found = False\nfor item in values:\n    if item > 1:\n        found = True"},
            .pieces = &.{ "mut found = False", "for item in values:", "if item > 1:", "found = True" },
        },
        .{
            .guess = "lists.all(values, double)",
            .message = "module `lists` declares no `all`; to ask whether every element passes, loop and keep the answer: `mut every = True`, then " ++ head_values ++
                " with `if item <= 1:` and `every = False` inside it; the builtin `all(flags)` takes a list of `bool`",
            .suggested = &.{"all(flags)"},
            .bodies = &.{"mut every = True\nfor item in values:\n    if item <= 1:\n        every = False"},
            .pieces = &.{ "mut every = True", "for item in values:", "if item <= 1:", "every = False" },
        },
        .{
            .guess = "lists.sum(values)",
            .message = "module `lists` declares no `sum`; the sum of a list is the builtin `sum(values)`, for a list of `int` or of `float`",
            .suggested = &.{"sum(values)"},
        },
        .{
            .guess = "lists.count(values, value)",
            .message = "module `lists` declares no `count`; the number of elements is the builtin `len(values)`; the number that pass a test is counted in a loop: " ++
                "`mut total = 0`, then " ++ head_values ++ " with `if item > 1:` and `total += 1` inside it",
            .suggested = &.{"len(values)"},
            .bodies = &.{"mut total = 0\nfor item in values:\n    if item > 1:\n        total += 1"},
            .pieces = &.{ "mut total = 0", "for item in values:", "if item > 1:", "total += 1" },
        },
        .{
            .guess = "lists.enumerate(values)",
            .message = "module `lists` declares no `enumerate`; `enumerate` is a builtin that stands in a `for`, not a function of `lists`: " ++
                "write `for index, item in enumerate(values):`",
            .bodies = &.{"for index, item in enumerate(values):\n    print(out, f\"{index} {item}\")"},
            .pieces = &.{"for index, item in enumerate(values):"},
        },
        .{
            .guess = "lists.zip(values, values)",
            .message = "module `lists` declares no `zip`; `zip` is a builtin that stands in a `for`, not a function of `lists`: " ++
                "write `for left, right in zip(first, second):`, which stops at the shorter list",
            .bodies = &.{"const first = [1, 2]\nconst second = [3]\nfor left, right in zip(first, second):\n    print(out, f\"{left} {right}\")"},
            .pieces = &.{"for left, right in zip(first, second):"},
        },
        .{
            .guess = "lists.rindex(values, value)",
            .message = "module `lists` declares no `rindex`; no function answers the position of the last equal element: `mut last = -1`, then " ++
                "`for index, item in enumerate(values):` with `if item == value:` and `last = index` inside it",
            .bodies = &.{"mut last = -1\nfor index, item in enumerate(values):\n    if item == value:\n        last = index"},
            .pieces = &.{ "mut last = -1", "for index, item in enumerate(values):", "if item == value:", "last = index" },
        },
    });
}

// A dictionary is walked by `for key, value in dicts.items(mapping):`, a set by `for item in values:`; `sets.find` and `dicts.index` have no
// function and are told what the set and the dictionary answer instead (the operator `in`; the key).
test "a guessed name of a dictionary or a set is answered with the loop, builtin or operator that does the job" {
    const items = "`for key, value in dicts.items(mapping):`";
    try expectRows(&.{
        .{
            .guess = "dicts.map(mapping, double)",
            .message = "module `dicts` declares no `map`; to apply a function to every value, loop and collect (a lambda is not written): " ++
                "`mut result: dict[str, int] = {}`, then " ++ items ++ " with `result[key] = value * 2` in its body",
            .bodies = &.{"mut result: dict[str, int] = {}\nfor key, value in dicts.items(mapping):\n    result[key] = value * 2"},
            .pieces = &.{ "mut result: dict[str, int] = {}", "for key, value in dicts.items(mapping):", "result[key] = value * 2" },
        },
        .{
            .guess = "dicts.filter(mapping, double)",
            .message = "module `dicts` declares no `filter`; to keep the entries that pass, loop and collect: `mut kept: dict[str, int] = {}`, then " ++ items ++
                " with `if value > 1:` and `kept[key] = value` inside it",
            .bodies = &.{"mut kept: dict[str, int] = {}\nfor key, value in dicts.items(mapping):\n    if value > 1:\n        kept[key] = value"},
            .pieces = &.{ "mut kept: dict[str, int] = {}", "if value > 1:", "kept[key] = value" },
        },
        .{
            .guess = "dicts.reduce(mapping, double)",
            .message = "module `dicts` declares no `reduce`; to combine the elements into one value, accumulate in a loop: `mut total = 0`, then " ++ items ++
                " with `total += value` in its body; `sum(list(dicts.values(mapping)))` adds the values",
            .suggested = &.{"sum(list(dicts.values(mapping)))"},
            .bodies = &.{"mut total = 0\nfor key, value in dicts.items(mapping):\n    total += value"},
            .pieces = &.{ "mut total = 0", "for key, value in dicts.items(mapping):", "total += value" },
        },
        .{
            .guess = "dicts.each(mapping, double)",
            .message = "module `dicts` declares no `each`; to do something with every element, loop over it: " ++ items ++ ", and write the body under it",
            .bodies = &.{"for key, value in dicts.items(mapping):\n    print(out, f\"{key} {value}\")"},
            .pieces = &.{"for key, value in dicts.items(mapping):"},
        },
        .{
            .guess = "dicts.any(mapping, double)",
            .message = "module `dicts` declares no `any`; to ask whether some element passes, loop and keep the answer: `mut found = False`, then " ++ items ++
                " with `if value > 1:` and `found = True` inside it; the builtin `any(flags)` takes a list of `bool`",
            .bodies = &.{"mut found = False\nfor key, value in dicts.items(mapping):\n    if value > 1:\n        found = True"},
            .pieces = &.{ "mut found = False", "if value > 1:", "found = True" },
        },
        .{
            .guess = "dicts.sum(mapping)",
            .message = "module `dicts` declares no `sum`; the sum of the values is `sum(list(dicts.values(mapping)))`",
            .suggested = &.{"sum(list(dicts.values(mapping)))"},
        },
        .{
            .guess = "dicts.count(mapping, key)",
            .message = "module `dicts` declares no `count`; the number of elements is the builtin `len(mapping)`; the number that pass a test is counted in a loop: " ++
                "`mut total = 0`, then " ++ items ++ " with `if value > 1:` and `total += 1` inside it",
            .suggested = &.{"len(mapping)"},
            .bodies = &.{"mut total = 0\nfor key, value in dicts.items(mapping):\n    if value > 1:\n        total += 1"},
            .pieces = &.{ "mut total = 0", "if value > 1:", "total += 1" },
        },
        .{
            .guess = "dicts.zip(mapping, mapping)",
            .message = "module `dicts` declares no `zip`; `zip` is a builtin that stands in a `for`, not a function of `dicts`: " ++
                "write `for left, right in zip(first, second):` over two lists",
            .bodies = &.{"const first = [1, 2]\nconst second = [3]\nfor left, right in zip(first, second):\n    print(out, f\"{left} {right}\")"},
            .pieces = &.{"for left, right in zip(first, second):"},
        },
        .{
            .guess = "dicts.index(mapping, key)",
            .message = "module `dicts` declares no `index`; a dictionary is read by its key, not by a position: `mapping[key]` traps when `key` is absent, " ++
                "`dicts.find(mapping, key)` answers `None` then, and `dicts.get(mapping, key, 0)` answers a fallback",
            .suggested = &.{ "mapping[key]", "dicts.find(mapping, key)", "dicts.get(mapping, key, 0)" },
        },
        .{
            .guess = "sets.map(seen, double)",
            .message = "module `sets` declares no `map`; to apply a function to every element, loop and collect (a lambda is not written): " ++
                "`mut result: int[] = []`, then `for item in values:` with `append(mut result, item * 2)` in its body",
            .set_values = true,
            .bodies = &.{"mut result: int[] = []\nfor item in values:\n    append(mut result, item * 2)"},
            .pieces = &.{ "mut result: int[] = []", "for item in values:", "append(mut result, item * 2)" },
        },
        .{
            .guess = "sets.sum(seen)",
            .message = "module `sets` declares no `sum`; the sum of a set is `sum(list(values))`",
            .set_values = true,
            .suggested = &.{"sum(list(values))"},
        },
        .{
            .guess = "sets.reduce(seen, double)",
            .message = "module `sets` declares no `reduce`; to combine the elements into one value, accumulate in a loop: `mut total = 0`, then `for item in values:` " ++
                "with `total += item` in its body; `sum(list(values))` adds a set of `int` or of `float`",
            .set_values = true,
            .suggested = &.{"sum(list(values))"},
            .bodies = &.{"mut total = 0\nfor item in values:\n    total += item"},
        },
        .{
            .guess = "sets.find(seen, value)",
            .message = "module `sets` declares no `find`; a set keeps no positions to find by: whether it holds a value is the operator `in`, `value in seen`",
            .suggested = &.{"value in seen"},
        },
    });
}

test "a guessed name of bytes, a set or a dictionary is answered with the operator or builtin that does the job" {
    const in_bytes = "whether bytes hold a byte or a run of bytes is the operator `in`: write `piece in data` (`lists.contains` is only for lists)";
    const in_set = "whether a set holds a value is the operator `in`: write `value in seen` (`lists.contains` is only for lists)";
    const in_dictionary = "whether a dictionary has a key is the operator `in`: write `key in mapping` (`lists.contains` is only for lists)";
    try expectRows(&.{
        .{
            .guess = "bytes.has(data, piece)",
            .message = "module `bytes` declares no `has`; " ++ in_bytes,
            .repair = .{ "bytes.has(data, piece)", "piece in data" },
            .suggested = &.{"piece in data"},
        },
        .{
            .guess = "bytes.includes(data, piece)",
            .message = "module `bytes` declares no `includes`; " ++ in_bytes,
            .repair = .{ "bytes.includes(data, piece)", "piece in data" },
            .suggested = &.{"piece in data"},
        },
        .{
            .guess = "bytes.contains(data, piece)",
            .message = "module `bytes` declares no `contains`; " ++ in_bytes,
            .repair = .{ "bytes.contains(data, piece)", "piece in data" },
            .suggested = &.{"piece in data"},
        },
        .{
            .guess = "bytes.is_empty(data)",
            .message = "module `bytes` declares no `is_empty`; whether bytes is empty is the builtin `len`: write `len(data) == 0`",
            .suggested = &.{"len(data) == 0"},
        },
        .{ .guess = "bytes.len(data)", .message = "module `bytes` declares no `len`; the length of bytes is the builtin `len(data)`", .suggested = &.{"len(data)"} },
        .{
            .guess = "bytes.compare(data, piece)",
            .message = "module `bytes` declares no `compare`; bytes compare with the operators `<`, `<=`, `==`, `!=`, `>=` and `>`",
            .described = &.{ "data < piece", "data == piece" },
        },
        .{
            .guess = "sets.has(seen, value)",
            .message = "module `sets` declares no `has`; " ++ in_set,
            .repair = .{ "sets.has(seen, value)", "value in seen" },
            .suggested = &.{"value in seen"},
        },
        .{
            .guess = "sets.includes(seen, value)",
            .message = "module `sets` declares no `includes`; " ++ in_set,
            .repair = .{ "sets.includes(seen, value)", "value in seen" },
            .suggested = &.{"value in seen"},
        },
        .{
            .guess = "sets.contains(seen, value)",
            .message = "module `sets` declares no `contains`; " ++ in_set,
            .repair = .{ "sets.contains(seen, value)", "value in seen" },
            .suggested = &.{"value in seen"},
        },
        .{
            .guess = "sets.is_empty(seen)",
            .message = "module `sets` declares no `is_empty`; whether a set is empty is the builtin `len`: write `len(values) == 0`",
            .suggested = &.{"len(values) == 0"},
            .set_values = true,
        },
        .{
            .guess = "sets.len(seen)",
            .message = "module `sets` declares no `len`; the length of a set is the builtin `len(values)`",
            .suggested = &.{"len(values)"},
            .set_values = true,
        },
        .{
            .guess = "dicts.has(mapping, key)",
            .message = "module `dicts` declares no `has`; " ++ in_dictionary,
            .repair = .{ "dicts.has(mapping, key)", "key in mapping" },
            .suggested = &.{"key in mapping"},
        },
        .{
            .guess = "dicts.includes(mapping, key)",
            .message = "module `dicts` declares no `includes`; " ++ in_dictionary,
            .repair = .{ "dicts.includes(mapping, key)", "key in mapping" },
            .suggested = &.{"key in mapping"},
        },
        .{
            .guess = "dicts.contains(mapping, key)",
            .message = "module `dicts` declares no `contains`; " ++ in_dictionary,
            .repair = .{ "dicts.contains(mapping, key)", "key in mapping" },
            .suggested = &.{"key in mapping"},
        },
        .{
            .guess = "dicts.is_empty(mapping)",
            .message = "module `dicts` declares no `is_empty`; whether a dictionary is empty is the builtin `len`: write `len(mapping) == 0`",
            .suggested = &.{"len(mapping) == 0"},
        },
        .{
            .guess = "sets.empty()",
            .message = "module `sets` declares no `empty`; an empty set is `set()` with its type named: `mut seen: set[str] = set()`",
            .suggested = &.{"mut seen: set[str] = set()"},
        },
        .{
            .guess = "dicts.empty()",
            .message = "module `dicts` declares no `empty`; an empty dictionary is `{}` with its type named: `mut mapping: dict[str, int] = {}`",
            .suggested = &.{"mut mapping: dict[str, int] = {}"},
        },
        .{
            .guess = "dicts.len(mapping)",
            .message = "module `dicts` declares no `len`; the length of a dictionary is the builtin `len(mapping)`",
            .suggested = &.{"len(mapping)"},
        },
    });
}

test "a misspelled name of the audit logs keeps its close name, and a pointer to another module is gone where the module cannot take the value" {
    try expectRows(&.{
        .{ .guess = "strings.trim(text)", .message = "module `strings` declares no `trim`; did you mean `strip`?", .named = &.{"strip"}, .described = &.{"strings.strip(text)"} },
        .{
            .guess = "strings.startswith(text, part)",
            .message = "module `strings` declares no `startswith`; did you mean `starts_with`?",
            .named = &.{"starts_with"},
            .described = &.{"strings.starts_with(text, part)"},
        },
        .{
            .guess = "strings.endswith(text, part)",
            .message = "module `strings` declares no `endswith`; did you mean `ends_with`?",
            .named = &.{"ends_with"},
            .described = &.{"strings.ends_with(text, part)"},
        },
        .{
            .guess = "bytes.startswith(data, piece)",
            .message = "module `bytes` declares no `startswith`; did you mean `starts_with`?",
            .named = &.{"starts_with"},
            .described = &.{"bytes.starts_with(data, piece)"},
        },
        .{
            .guess = "strings.joinx(parts, part)",
            .message = "module `strings` declares no `joinx`; did you mean `join`?",
            .named = &.{"join"},
            .described = &.{"strings.join(parts, part)"},
        },
        .{
            .guess = "strings.decode_lossy(data)",
            .message = "module `strings` declares no `decode_lossy`; did you mean `decode`?",
            .named = &.{"decode"},
            .described = &.{"try strings.decode(data)"},
        },
        .{ .guess = "strings.f(text)", .message = "module `strings` declares no `f`" },
        .{ .guess = "strings.parse_int(text)", .message = "module `strings` declares no `parse_int`" },
        .{
            .guess = "lists.join(parts, part)",
            .message = "module `lists` declares no `join`; the standard modules `bytes` and `strings` declare a function `join` (import one, as in `bytes.join(...)`)",
        },
        .{
            .guess = "strings.basename(text)",
            .message = "module `strings` declares no `basename`; the standard module `path` declares a function `basename` (import it and call `path.basename(...)`)",
        },
    });
}

test "a module of one kind of value points only to modules whose function takes that kind first" {
    var found: [5][]const u8 = undefined;
    // Each of these names exists in other modules, none of which takes the value the guess was written with.
    const refused = [_][2][]const u8{
        .{ "find", "lists" },      .{ "index", "strings" },   .{ "rindex", "strings" }, .{ "has", "strings" },  .{ "is_empty", "strings" },
        .{ "compare", "strings" }, .{ "compare", "lists" },   .{ "count", "lists" },    .{ "get", "lists" },    .{ "sum", "lists" },
        .{ "append", "lists" },    .{ "reverse", "strings" }, .{ "get", "strings" },    .{ "last", "strings" }, .{ "index", "dicts" },
        .{ "empty", "strings" },   .{ "empty", "sets" },      .{ "empty", "lists" },    .{ "empty", "dicts" },
    };
    for (refused) |pair| try t.expectEqual(@as(usize, 0), standard_library.exporting(pair[0], pair[1], &found));
    // A function that does take the kind is still named, with a `mut` first parameter too, and a module that is no kind of value is unfiltered.
    try t.expectEqual(@as(usize, 1), standard_library.exporting("basename", "strings", &found));
    try t.expectEqualStrings("path", found[0]);
    try t.expectEqual(@as(usize, 1), standard_library.exporting("sort_ints", "lists", &found));
    try t.expectEqualStrings("sort", found[0]);
    try t.expectEqual(@as(usize, 2), standard_library.exporting("decode", "bytes", &found));
    try t.expectEqualStrings("cache_record", found[0]);
    try t.expectEqualStrings("strings", found[1]);
    try t.expectEqual(@as(usize, 4), standard_library.exporting("find", "time", &found));
}
