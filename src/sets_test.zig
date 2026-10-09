//! `set[T]` and hashable dictionary keys: the checker's refusals, the traps a
//! set shares with a dictionary, the collector paths, and allocation
//! failure. Guest behaviour lives in `tests/lang/sets.selka`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// The accepted-method list an unknown method on a set names.
const set_methods = "accepted methods: add, clear, copy, difference, discard, intersection, isdisjoint, issubset, issuperset, pop, remove, symmetric_difference, union, update";

/// Check `source` and require its first diagnostic to carry `code` and a
/// message containing `fragment`.
fn rejected(source: []const u8, code: []const u8, fragment: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "sets.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, fragment) != null);
}

/// Run `source` natively under the stress collector and require the trap `code`.
fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "sets-trap.selka", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{});
    try t.expectEqualStrings(code, result.trap.code);
}

/// Run `source` natively under the stress collector and answer its result.
fn value(source: []const u8) !i64 {
    var c = try language.Compilation.init(t.allocator, "sets-value.selka", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{});
    try t.expectEqualStrings("", result.trap.code);
    return result.value;
}

// spec: HASH-KEYS-1
test "an unhashable key or element type is refused with the path to its offending part" {
    try rejected("func main() -> int:\n    mut d: dict[float, int] = {}\n    return len(d)\n", "E_DICT_KEY", "`float` cannot be a dictionary key: a float is not hashable because NaN is not equal to itself");
    try rejected(
        "record At:\n    x: float\n\nrecord Reading:\n    name: str\n    at: At\n\nfunc main() -> int:\n    mut d: dict[Reading, int] = {}\n    return len(d)\n",
        "E_DICT_KEY",
        "`Reading` cannot be a dictionary key: `Reading.at.x` is `float`",
    );
    try rejected("func main() -> int:\n    mut s = {(1, 2.5)}\n    return len(s)\n", "E_SET_ELEMENT", "`tuple[int, float][1]` is `float`");
    try rejected("func main() -> int:\n    mut s: set[int[]] = set()\n    return len(s)\n", "E_SET_ELEMENT", "is a shared reference whose contents can change after it is stored");
    try rejected("func main() -> int:\n    mut d = {{1}: 2}\n    return len(d)\n", "E_DICT_KEY", "`set[int]` cannot be a dictionary key");
    try rejected("enum Maybe:\n    none\n    some(value: float)\n\nfunc main() -> int:\n    mut s: set[Maybe] = set()\n    return len(s)\n", "E_SET_ELEMENT", "`Maybe.some.value` is `float`");
    try rejected("func keyed[T: copy + storable](value: T) -> set[T]:\n    return {value}\n\nfunc main() -> int:\n    return 0\n", "E_GENERIC_OPERATION", "requires declared integer support");
}

// spec-case: SET-1
test "a set is built only from set syntax and answers only the set vocabulary" {
    try rejected("func main() -> int:\n    mut s: set[int] = {}\n    return len(s)\n", "E_DICT_TYPE", "write `set()` for an empty set");
    try rejected("func main() -> int:\n    mut s = set()\n    return 0\n", "E_SET_INFERENCE", "annotate the binding");
    try rejected("func main() -> int:\n    mut s = {1}\n    return s[0]\n", "E_SET_INDEX", "a set is not indexable");
    try rejected("func main() -> int:\n    mut s = {1}\n    s[2] = ()\n    return 0\n", "E_SET_INDEX", "a set is not indexable");
    try rejected("func main() -> int:\n    mut s = {1}\n    return s.get(1, 0)\n", "E_LIST_METHOD", set_methods);
    try rejected("func main() -> int:\n    mut s = {1}\n    s.add(1, 2)\n    return 0\n", "E_ARITY", "`set[int].add(value: int) -> None` takes 1 argument");
    try rejected("func main() -> int:\n    mut s = {1}\n    s.add(\"x\")\n    return 0\n", "E_TYPE", "expected int, found str");
}

// spec-case: SET-1
test "a missing element, an empty pop and a resize during iteration trap like a dictionary" {
    try trapped("func main() -> int:\n    mut s = {1, 2}\n    s.remove(3)\n    return 0\n", "R_MISSING_KEY");
    try trapped("func main() -> int:\n    mut s: set[str] = set()\n    _ = s.pop()\n    return 0\n", "R_MISSING_KEY");
    try trapped("func main() -> int:\n    mut s = {1, 2}\n    for x in s:\n        s.add(x + 10)\n    return 0\n", "R_LIST_ITERATION_MUTATION");
    try t.expectEqual(@as(i64, 2), try value("func main() -> int:\n    mut s = {1, 2}\n    s.discard(3)\n    return len(s)\n"));
}

// spec-case: SET-OPERATORS-1
test "the set operators are refused on operands that are neither sets nor integers and a set has no augmented form" {
    try rejected("func main() -> int:\n    mut x = 1.5 | 2.5\n    return 0\n", "E_SET_OPERATOR", "two sets or two integers (`bit_or(a, b)`)");
    try rejected("func main() -> int:\n    mut x = \"a\" & \"b\"\n    return 0\n", "E_SET_OPERATOR", "`bit_and(a, b)`");
    try rejected("func main() -> int:\n    mut x = [1] ^ [2]\n    return 0\n", "E_SET_OPERATOR", "`bit_xor(a, b)`");
    // On two integers the operators are the bitwise ones (PY-SET-OPS-1).
    try t.expectEqual(@as(i64, 4), try value("func main() -> int:\n    return (6 | 3) + (6 & 3) - (6 ^ 3)\n"));
    try rejected("func main() -> int:\n    mut s = {1}\n    mut t = s + {2}\n    return len(t)\n", "E_SET_OPERATOR", "sets combine with `|`, `&`, `-` and `^`");
    try rejected("func main() -> int:\n    mut s = {1}\n    s -= {1}\n    return len(s)\n", "E_SET_OPERATOR", "a set has no augmented assignment");
    try rejected("def main() -> int:\n    s = {1}\n    s |= {2}\n    return len(s)\n", "E_EXPRESSION", "a set has no augmented assignment operator");
    try rejected("def touch(values: mut list[int]) -> None:\n    values[0] = 1\n\ndef main() -> int:\n    values = [1]\n    touch(&values)\n    return 0\n", "E_REMOVED_SPELLING", "write `mut value`");
    try t.expectEqual(@as(i64, 3), try value("func main() -> int:\n    return len({1, 2} | {2, 3}) + bit_or(0, 0)\n"));
}

// spec-case: SET-1
test "a set parameter a function writes must be declared and passed mut" {
    try rejected("func grow(s: set[int]) -> Unit:\n    s.add(1)\n\nfunc main() -> int:\n    mut t: set[int] = set()\n    grow(t)\n    return len(t)\n", "E_IMMUTABLE", "writable binding");
    try t.expectEqual(@as(i64, 2), try value("func grow(mut s: set[int]) -> Unit:\n    s.add(1)\n    s.update({2})\n\nfunc main() -> int:\n    mut t: set[int] = set()\n    grow(mut t)\n    return len(t)\n"));
}

// spec-case: HASH-KEYS-2
test "structural keys holding text survive stress collection, removal and settling" {
    try t.expectEqual(@as(i64, 1565), try value(
        \\record Named:
        \\    name: str
        \\    at: tuple[int, int]
        \\
        \\func main() -> int:
        \\    mut table: dict[Named, int] = {}
        \\    for i in range(300):
        \\        table[Named(name="n" + str(i), at=(i, 0 - i))] = i
        \\    for i in range(300):
        \\        if i % 2 == 1:
        \\            _ = table.pop(Named(name="n" + str(i), at=(i, 0 - i)))
        \\    mut total = 0
        \\    for key in table:
        \\        total += table[key]
        \\    return total // 20 + len(table) + table[Named(name="n" + str(298), at=(298, -298))]
        \\
    ));
}

// spec-case: SET-1
test "a set that outgrows the memory budget traps instead of corrupting the heap" {
    var c = try language.Compilation.init(t.allocator, "sets-budget.selka",
        \\func main() -> int:
        \\    mut chunk = "abcdefgh"
        \\    for i in range(9):
        \\        chunk = chunk + chunk
        \\    mut words: set[str] = set()
        \\    for i in range(100000):
        \\        words.add(chunk + str(i))
        \\    return len(words)
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .max_memory = 1 << 20 });
    try t.expectEqualStrings("R_MEMORY_BUDGET", result.trap.code);
}

// spec-case: SET-1
test "a program's own function named set keeps its name beside set literals" {
    try t.expectEqual(@as(i64, 43), try value(
        \\func set(mut values: int[], index: int, replacement: int) -> Unit:
        \\    values[index] = replacement
        \\
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    set(mut values, 0, 40)
        \\    mut seen = {values[0], values[1], 1}
        \\    return values[0] + len(seen)
        \\
    ));
}
