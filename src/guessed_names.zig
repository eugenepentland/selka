//! The answer to a library function an author guessed from another language and the module does not have (lane MSG-F).
//!
//! `strings.index(text, part)`, `strings.has(text, part)`, `strings.len(text)`, `strings.is_empty(text)`, `strings.compare(a, b)`
//! and `lists.find(values, value)` were answered with the nearest spelling and the other standard modules that declare a function
//! of that name: `bytes.index`, `argparse.has`, `spans.is_empty`, `time.compare`. None of those takes the value in hand, so the author
//! learned nothing. The names that agents really wrote are answered here with what does the job for that kind of value, found by
//! trying it on the compiler: a function of the same module under its own name (`strings.text_index`), the operator `in`, the
//! builtin `len`, the comparison operators. A repair is offered only where the edit is certain: the same call under another name
//! with the same arguments and the same meaning (`rename`: `lists.has` is `lists.contains`), or the call rewritten as the operator
//! `in` when its operands were read (`operator`). `index` and `rindex` have none: `text_index` and `index_of` trap when the part is
//! absent, and the author may have meant an answer of -1 or `None` (`selka fix` runs after every check, and the program would
//! compile and trap at run time).
//! The names that a Python, JavaScript or Rust author reaches for on a list or a dictionary (`map`, `filter`, `reduce`, `fold`, `each`,
//! `for_each`, `any`, `all`, `sum`, `count`, `enumerate`, `zip`, `rindex`, `sets.find`, `dicts.index`) are answered with the form the language
//! has for the job: a `for` loop (there are no lambdas to hand to a `map`), a builtin (`sum`, `len`, `enumerate`, `zip`), `parallel.map` for a
//! named function over a list, the operator `in`, or the key. None has a repair: the rewrite is a loop, or the author may have meant either of
//! two answers, and `selka fix` runs after every check.
//! The sentence is the part after `module `strings` declares no `index`; `.
const std = @import("std");
const contains_removed = @import("contains_removed.zig");

/// What `selka fix` does for the answer.
pub const Repair = union(enum) {
    /// The sentence says what to write and no edit is made.
    none,
    /// The call is rewritten as the operator `in` with its operands swapped, when they were plain (`contains_removed.inFix`).
    operator: contains_removed.Receiver,
    /// The name after the module is replaced by this one, a function of the same module with the same arguments and the same meaning.
    rename: []const u8,
};

/// The answer for one guessed name: the sentence that follows the head of the message, and the repair.
pub const Answer = struct { sentence: []const u8, repair: Repair };

/// The standard modules of one kind of value, which a guessed name is answered for.
const Kind = enum { strings, bytes, lists, dicts, sets };

/// The names answered: the ones agents wrote, each found in the logs of the audit programs.
const Guess = enum { contains, has, includes, index, rindex, find, is_empty, len, compare, empty, map, filter, reduce, fold, each, for_each, any, all, sum, count, enumerate, zip };

/// The answer for the name `name` that the standard module `module` (spelled `alias` in the file) does not declare, or null when
/// the name is not one answered for that module. `written` is the call as the file wrote it when its operands are plain.
pub fn answer(allocator: std.mem.Allocator, module: []const u8, alias: []const u8, name: []const u8, written: ?contains_removed.Written) std.mem.Allocator.Error!?Answer {
    const kind = std.meta.stringToEnum(Kind, module) orelse return null;
    const guess = std.meta.stringToEnum(Guess, name) orelse return null;
    switch (guess) {
        .contains, .has, .includes => {
            if (kind == .lists) return if (guess == .contains) null else .{
                .sentence = try std.fmt.allocPrint(allocator, "whether a list holds a value is `{s}.contains(values, value)` (a list has no operator `in`)", .{alias}),
                .repair = .{ .rename = "contains" },
            };
            const receiver = contains_removed.receiverOfModule(module) orelse return null;
            const advice = try contains_removed.inAdvice(allocator, receiver, written);
            return .{
                .sentence = try std.fmt.allocPrint(allocator, "{s} (`lists.contains` is only for lists)", .{advice}),
                .repair = .{ .operator = receiver },
            };
        },
        .index => return switch (kind) {
            .dicts => .{
                .sentence = "a dictionary is read by its key, not by a position: `mapping[key]` traps when `key` is absent, " ++
                    "`dicts.find(mapping, key)` answers `None` then, and `dicts.get(mapping, key, 0)` answers a fallback",
                .repair = .none,
            },
            .strings => .{
                .sentence = try std.fmt.allocPrint(allocator, "the byte offset of the first occurrence is `{s}.text_index(text, part)`, which traps when `part` is absent " ++
                    "(`{s}.find(text, part)` answers `None` instead, and `{s}.char_index(text, part)` counts Unicode scalars)", .{ alias, alias, alias }),
                .repair = .none,
            },
            .lists => .{ .sentence = try indexOf(allocator, alias), .repair = .none },
            else => null,
        },
        .rindex => return switch (kind) {
            .strings => .{
                .sentence = try std.fmt.allocPrint(allocator, "the byte offset of the last occurrence is `{s}.text_rindex(text, part)`, which traps when `part` is absent " ++
                    "(`{s}.rfind(text, part)` answers `None` instead, and `{s}.char_rindex(text, part)` counts Unicode scalars)", .{ alias, alias, alias }),
                .repair = .none,
            },
            .lists => .{
                .sentence = "no function answers the position of the last equal element: `mut last = -1`, then `for index, item in enumerate(values):` " ++
                    "with `if item == value:` and `last = index` inside it",
                .repair = .none,
            },
            else => null,
        },
        .find => return switch (kind) {
            .lists => .{ .sentence = try indexOf(allocator, alias), .repair = .none },
            .sets => .{ .sentence = "a set keeps no positions to find by: whether it holds a value is the operator `in`, `value in seen`", .repair = .none },
            else => null,
        },
        .map, .filter, .reduce, .fold, .each, .for_each, .any, .all, .sum, .count, .enumerate, .zip => {
            const sentence = try loopSentence(allocator, guess, kind, alias) orelse return null;
            return .{ .sentence = sentence, .repair = .none };
        },
        .is_empty => return .{ .sentence = try std.fmt.allocPrint(allocator, "whether {s} is empty is the builtin `len`: write `len({s}) == 0`", .{ holder(kind), operand(kind) }), .repair = .none },
        .len => return .{ .sentence = try lengthSentence(allocator, kind, alias), .repair = .none },
        .empty => return .{ .sentence = emptySentence(kind), .repair = .none },
        .compare => return switch (kind) {
            .strings => .{
                .sentence = "texts compare with the operators `<`, `<=`, `==`, `!=`, `>=` and `>`, and `sort.compare_strs(a, b)` answers a negative number, zero or a positive number",
                .repair = .none,
            },
            .bytes => .{ .sentence = "bytes compare with the operators `<`, `<=`, `==`, `!=`, `>=` and `>`", .repair = .none },
            else => null,
        },
    }
}

/// The sentence for a name that is a loop or a builtin in the language (`map`, `filter`, `reduce`, `fold`, `each`, `for_each`, `any`, `all`,
/// `sum`, `count`, `enumerate`, `zip`) on a list, a set or a dictionary, or null for a kind that has no such answer. Every spelling in it
/// is written out so that it can be checked: a lambda is not written, so the job is a `for` loop over the value.
fn loopSentence(allocator: std.mem.Allocator, guess: Guess, kind: Kind, alias: []const u8) std.mem.Allocator.Error!?[]const u8 {
    if (kind != .lists and kind != .sets and kind != .dicts) return null;
    const dictionary = kind == .dicts;
    const head: []const u8 = if (dictionary) "for key, value in dicts.items(mapping):" else "for item in values:";
    const element: []const u8 = if (dictionary) "value" else "item";
    const whole: []const u8 = if (dictionary) "mapping" else "values";
    const parallel = "; `parallel.map(values, double)` applies a named function (`func double(item: int) -> int`) to every element on several threads";
    const map_list = "to apply a function to every element, loop and collect (a lambda is not written): `mut result: int[] = []`, then `{s}` with `append(mut result, item * 2)` in its body{s}";
    const map_dict = "to apply a function to every value, loop and collect (a lambda is not written): `mut result: dict[str, int] = {{}}`, then `{s}` with `result[key] = value * 2` in its body";
    const keep_list = "to keep the elements that pass, loop and collect: `mut kept: int[] = []`, then `{s}` with `if item > 1:` and `append(mut kept, item)` inside it";
    const keep_dict = "to keep the entries that pass, loop and collect: `mut kept: dict[str, int] = {{}}`, then `{s}` with `if value > 1:` and `kept[key] = value` inside it";
    const combine = "to combine the elements into one value, accumulate in a loop: `mut total = 0`, then `{s}` with `total += {s}` in its body; {s}";
    const any = "to ask whether some element passes, loop and keep the answer: `mut found = False`, then `{s}` with `if {s} > 1:` and `found = True` inside it";
    const all = "to ask whether every element passes, loop and keep the answer: `mut every = True`, then `{s}` with `if {s} <= 1:` and `every = False` inside it";
    const count = "the number of elements is the builtin `len({s})`; the number that pass a test is counted in a loop: `mut total = 0`, then `{s}` with `if {s} > 1:` and `total += 1` inside it";
    const source = "`{s}` is a builtin that stands in a `for`, not a function of `{s}`: write `{s}`{s}";
    return switch (guess) {
        .map => if (dictionary) try std.fmt.allocPrint(allocator, map_dict, .{head}) else try std.fmt.allocPrint(allocator, map_list, .{ head, if (kind == .lists) parallel else "" }),
        .filter => if (dictionary) try std.fmt.allocPrint(allocator, keep_dict, .{head}) else try std.fmt.allocPrint(allocator, keep_list, .{head}),
        .reduce, .fold => try std.fmt.allocPrint(allocator, combine, .{ head, element, switch (kind) {
            .dicts => "`sum(list(dicts.values(mapping)))` adds the values",
            .sets => "`sum(list(values))` adds a set of `int` or of `float`",
            else => "`sum(values)` adds a list of `int` or of `float`",
        } }),
        .each, .for_each => try std.fmt.allocPrint(allocator, "to do something with every element, loop over it: `{s}`, and write the body under it", .{head}),
        .any => try std.fmt.allocPrint(allocator, any ++ "; the builtin `any(flags)` takes a list of `bool`", .{ head, element }),
        .all => try std.fmt.allocPrint(allocator, all ++ "; the builtin `all(flags)` takes a list of `bool`", .{ head, element }),
        .sum => switch (kind) {
            .dicts => "the sum of the values is `sum(list(dicts.values(mapping)))`",
            .sets => "the sum of a set is `sum(list(values))`",
            else => "the sum of a list is the builtin `sum(values)`, for a list of `int` or of `float`",
        },
        .count => try std.fmt.allocPrint(allocator, count, .{ whole, head, element }),
        .enumerate => try std.fmt.allocPrint(allocator, source, .{ "enumerate", alias, "for index, item in enumerate(values):", if (kind == .lists) "" else " over a list" }),
        .zip => try std.fmt.allocPrint(allocator, source, .{ "zip", alias, "for left, right in zip(first, second):", if (kind == .lists) ", which stops at the shorter list" else " over two lists" }),
        else => null,
    };
}

/// The sentence for `empty`: an empty value is a literal (`""`, `b""`), and for a collection the literal with its type named, since a bare
/// `[]`, `{}` or `set()` has none (`mut values: int[] = []`).
fn emptySentence(kind: Kind) []const u8 {
    return switch (kind) {
        .strings => "empty text is the literal `\"\"`",
        .bytes => "empty bytes is the literal `b\"\"`",
        .lists => "an empty list is `[]` with its type named: `mut values: int[] = []`",
        .dicts => "an empty dictionary is `{}` with its type named: `mut mapping: dict[str, int] = {}`",
        .sets => "an empty set is `set()` with its type named: `mut seen: set[str] = set()`",
    };
}

/// What a list answers to a search by value: the position, trapping when absent, and the question whether it is there.
fn indexOf(allocator: std.mem.Allocator, alias: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "the position of the first equal element is `{s}.index_of(values, value)`, which traps when no element is equal " ++
        "(`{s}.contains(values, value)` asks whether one is)", .{ alias, alias });
}

/// The sentence for `len`: the builtin that counts, and for text the function that counts scalars instead of octets.
fn lengthSentence(allocator: std.mem.Allocator, kind: Kind, alias: []const u8) std.mem.Allocator.Error![]const u8 {
    if (kind == .strings) return std.fmt.allocPrint(allocator, "the length of text is the builtin `len(text)`, which counts octets; `{s}.char_count(text)` counts Unicode scalars", .{alias});
    return std.fmt.allocPrint(allocator, "the length of {s} is the builtin `len({s})`", .{ holder(kind), operand(kind) });
}

/// What a value of the module's kind is called in a sentence: `text`, `bytes`, `a list`.
fn holder(kind: Kind) []const u8 {
    return switch (kind) {
        .strings => "text",
        .bytes => "bytes",
        .lists => "a list",
        .dicts => "a dictionary",
        .sets => "a set",
    };
}

/// The name a message gives the value in a spelling it writes: `text`, `data`, `values`, `mapping`.
fn operand(kind: Kind) []const u8 {
    return switch (kind) {
        .strings => "text",
        .bytes => "data",
        .lists, .sets => "values",
        .dicts => "mapping",
    };
}
