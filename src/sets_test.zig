//! `set[T]` and hashable dictionary keys: the checker's refusals, the traps a
//! set shares with a dictionary, the collector and arena paths, and allocation
//! failure. Guest behaviour lives in `tests/lang/sets.my`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// The accepted-method list an unknown method on a set names.
const set_methods = "accepted methods: add, clear, copy, difference, discard, intersection, isdisjoint, issubset, issuperset, pop, remove, symmetric_difference, union, update";

/// Check `source` and require its first diagnostic to carry `code` and a
/// message containing `fragment`.
fn rejected(source: []const u8, code: []const u8, fragment: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "sets.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, fragment) != null);
}

/// Run `source` natively under the stress collector and require the trap `code`.
fn trapped(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "sets-trap.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings(code, result.trap.code);
}

/// Run `source` natively under the stress collector and answer its result.
fn value(source: []const u8) !i64 {
    var c = try language.Compilation.init(t.allocator, "sets-value.my", source);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqualStrings("", result.trap.code);
    return result.value;
}

// spec: HASH-KEYS-1
test "an unhashable key or element type is refused with the path to its offending part" {
    try rejected("def main() -> int:\n    d: dict[float, int] = {}\n    return len(d)\n", "E_DICT_KEY", "`float` cannot be a dictionary key: a float is not hashable because NaN is not equal to itself");
    try rejected(
        "record At:\n    x: float\n\nrecord Reading:\n    name: str\n    at: At\n\ndef main() -> int:\n    d: dict[Reading, int] = {}\n    return len(d)\n",
        "E_DICT_KEY",
        "`Reading` cannot be a dictionary key: `Reading.at.x` is `float`",
    );
    try rejected("def main() -> int:\n    s = {(1, 2.5)}\n    return len(s)\n", "E_SET_ELEMENT", "`tuple[int, float][1]` is `float`");
    try rejected("def main() -> int:\n    s: set[list[int]] = set()\n    return len(s)\n", "E_SET_ELEMENT", "is a shared reference whose contents can change after it is stored");
    try rejected("class Box:\n    n: int\n\ndef main() -> int:\n    s = {Box(n=1)}\n    return len(s)\n", "E_SET_ELEMENT", "`Box` cannot be a set element");
    try rejected("def main() -> int:\n    d = {{1}: 2}\n    return len(d)\n", "E_DICT_KEY", "`set[int]` cannot be a dictionary key");
    try rejected("union Maybe:\n    none,\n    some: float\n\ndef main() -> int:\n    s: set[Maybe] = set()\n    return len(s)\n", "E_SET_ELEMENT", "`Maybe.some` is `float`");
    try rejected("def keyed[T: copy + storable](value: T) -> set[T]:\n    return {value}\n\ndef main() -> int:\n    return 0\n", "E_GENERIC_OPERATION", "requires declared integer support");
}

// spec-case: SET-1
test "a set is built only from set syntax and answers only the set vocabulary" {
    try rejected("def main() -> int:\n    s: set[int] = {}\n    return len(s)\n", "E_DICT_TYPE", "write `set()` for an empty set");
    try rejected("def main() -> int:\n    s = set()\n    return 0\n", "E_SET_INFERENCE", "annotate the binding");
    try rejected("def main() -> int:\n    s = {1}\n    return s[0]\n", "E_SET_INDEX", "a set is not indexable");
    try rejected("def main() -> int:\n    s = {1}\n    s[2] = None\n    return 0\n", "E_SET_INDEX", "a set is not indexable");
    try rejected("def main() -> int:\n    s = {1}\n    return s.get(1, 0)\n", "E_LIST_METHOD", set_methods);
    try rejected("def main() -> int:\n    s = {1}\n    s.add(1, 2)\n    return 0\n", "E_ARITY", "`set[int].add(value: int) -> None` takes 1 argument");
    try rejected("def main() -> int:\n    s = {1}\n    s.add(\"x\")\n    return 0\n", "E_TYPE", "expected int, found str");
}

// spec-case: SET-1
test "a missing element, an empty pop and a resize during iteration trap like a dictionary" {
    try trapped("def main() -> int:\n    s = {1, 2}\n    s.remove(3)\n    return 0\n", "R_MISSING_KEY");
    try trapped("def main() -> int:\n    s: set[str] = set()\n    _ = s.pop()\n    return 0\n", "R_MISSING_KEY");
    try trapped("def main() -> int:\n    s = {1, 2}\n    for x in s:\n        s.add(x + 10)\n    return 0\n", "R_LIST_ITERATION_MUTATION");
    try t.expectEqual(@as(i64, 2), try value("def main() -> int:\n    s = {1, 2}\n    s.discard(3)\n    return len(s)\n"));
}

// spec-case: SET-OPERATORS-1
test "the set operators are refused on integers and a set has no augmented form" {
    try rejected("def main() -> int:\n    return 6 | 3\n", "E_SET_OPERATOR", "an integer bitwise operation is spelled `bit_or(a, b)`");
    try rejected("def main() -> int:\n    return 6 & 3\n", "E_SET_OPERATOR", "`bit_and(a, b)`");
    try rejected("def main() -> int:\n    return 6 ^ 3\n", "E_SET_OPERATOR", "`bit_xor(a, b)`");
    try rejected("def main() -> int:\n    s = {1}\n    t = s + {2}\n    return len(t)\n", "E_SET_OPERATOR", "sets combine with `|`, `&`, `-` and `^`");
    try rejected("def main() -> int:\n    s = {1}\n    s -= {1}\n    return len(s)\n", "E_SET_OPERATOR", "a set has no augmented assignment");
    try rejected("def main() -> int:\n    s = {1}\n    s |= {2}\n    return len(s)\n", "E_EXPRESSION", "a set has no augmented assignment operator");
    try rejected("def touch(values: mut list[int]) -> None:\n    values[0] = 1\n\ndef main() -> int:\n    values = [1]\n    touch(&values)\n    return 0\n", "E_REMOVED_SPELLING", "write `mut value`");
    try t.expectEqual(@as(i64, 3), try value("def main() -> int:\n    return len({1, 2} | {2, 3}) + bit_or(0, 0)\n"));
}

// spec-case: SET-1
test "a set parameter a function writes must be declared and passed mut" {
    try rejected("def grow(s: set[int]) -> None:\n    s.add(1)\n\ndef main() -> int:\n    t: set[int] = set()\n    grow(t)\n    return len(t)\n", "E_MUTATION_MARKER", "declare `s: mut set[int]`");
    try t.expectEqual(@as(i64, 2), try value("def grow(s: mut set[int]) -> None:\n    s.add(1)\n    s.update({2})\n\ndef main() -> int:\n    t: set[int] = set()\n    grow(mut t)\n    return len(t)\n"));
}

// spec-case: SET-1
test "a set store or update from inside an arena into an outer set is refused" {
    try rejected("def main() -> int:\n    outer: set[str] = set()\n    with arena() as scratch:\n        outer.add(\"a\" + str(1))\n    return len(outer)\n", "E_ARENA_ESCAPE", "outlives arena `scratch`");
    try rejected("def main() -> int:\n    outer: set[str] = set()\n    with arena() as scratch:\n        inner = {\"a\" + str(1)}\n        outer.update(inner)\n    return len(outer)\n", "E_ARENA_ESCAPE", "outlives arena `scratch`");
    try rejected("def main() -> int:\n    outer: dict[str, int] = {}\n    with arena() as scratch:\n        inner = {\"a\" + str(1): 1}\n        outer.update(inner)\n    return len(outer)\n", "E_ARENA_ESCAPE", "outlives arena `scratch`");
    try t.expectEqual(@as(i64, 39), try value(
        \\record Key:
        \\    name: str
        \\    n: int
        \\
        \\def main() -> int:
        \\    kept: set[Key] = set()
        \\    with arena() as scratch:
        \\        local: set[Key] = set()
        \\        for i in range(40):
        \\            local.add(Key(name=str(i), n=i))
        \\        local.discard(Key(name="7", n=7))
        \\        kept = scratch.escape(local)
        \\    found = 0
        \\    for i in range(40):
        \\        if Key(name=str(i), n=i) in kept:
        \\            found += 1
        \\    return found
        \\
    ));
}

// spec-case: HASH-KEYS-2
test "structural keys holding text survive stress collection, removal and settling" {
    try t.expectEqual(@as(i64, 1565), try value(
        \\record Named:
        \\    name: str
        \\    at: tuple[int, int]
        \\
        \\def main() -> int:
        \\    table: dict[Named, int] = {}
        \\    for i in range(300):
        \\        table[Named(name="n" + str(i), at=(i, 0 - i))] = i
        \\    for i in range(300):
        \\        if i % 2 == 1:
        \\            _ = table.pop(Named(name="n" + str(i), at=(i, 0 - i)))
        \\    total = 0
        \\    for key in table:
        \\        total += table[key]
        \\    return total // 20 + len(table) + table[Named(name="n" + str(298), at=(298, -298))]
        \\
    ));
}

// spec-case: SET-1
test "a set that outgrows the memory budget traps instead of corrupting the heap" {
    var c = try language.Compilation.init(t.allocator, "sets-budget.my",
        \\def main() -> int:
        \\    chunk = "abcdefgh"
        \\    for i in range(9):
        \\        chunk = chunk + chunk
        \\    words: set[str] = set()
        \\    for i in range(100000):
        \\        words.add(chunk + str(i))
        \\    return len(words)
        \\
    );
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .max_memory = 1 << 20 });
    try t.expectEqualStrings("R_MEMORY_BUDGET", result.trap.code);
}
