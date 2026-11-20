//! Fixed-array element writes, `mut [N]T` parameters and array loops: the
//! rejections and traps a guest test cannot observe.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");

const fixture_path = "places.selka";

/// Check `source` and require its first diagnostic to carry `code` and a
/// message containing `fragment`.
fn reject(source: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), source);
    try t.expect(!report.passed);
    try t.expectEqualStrings(code, report.diagnostics[0].code);
    try t.expect(std.mem.indexOf(u8, report.diagnostics[0].message, fragment) != null);
}
/// Run a supported array update and check its caller-visible result.
fn expectValue(source: []const u8, wanted: i64) !void {
    try t.expectEqual(wanted, try fixture.value(t.allocator, source));
}
/// Run `source` natively and require a trap with `code` at `line`.
fn trap(source: []const u8, code: []const u8, line: u64) !void {
    try fixture.trappedAt(t.allocator, source, code, line);
}

// spec-case: PY-ARRAY-WRITE-1
test "an element write out of range traps like a fixed-array read" {
    try trap(
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    mut index = 4
        \\    values[index] = 5
        \\    return values[3]
    , "R_LIST_BOUNDS", 4);
    try trap(
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    values[-len(values) - 1] = 5
        \\    return values[3]
    , "R_LIST_BOUNDS", 3);
    try trap(
        \\func main() -> int:
        \\    mut grid: FixedArray[FixedArray[int, 2], 2] = FixedArray[FixedArray[int, 2], 2]([FixedArray[int, 2]([0, 0]), FixedArray[int, 2]([0, 0])])
        \\    mut column = 2
        \\    grid[1][column] += 1
        \\    return grid[1][1]
    , "R_LIST_BOUNDS", 4);
}

// spec: PY-ARRAY-NEGATIVE-1
test "a fixed-array index below minus its length traps where it is written" {
    try trap(
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
        \\    mut index = -5
        \\    return values[index]
    , "R_LIST_BOUNDS", 4);
    try trap(
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
        \\    mut index = -9
        \\    values = replace(values, index, 0)
        \\    return values[0]
    , "R_LIST_BOUNDS", 4);
    try trap(
        \\func main() -> int:
        \\    mut grid: FixedArray[FixedArray[int, 2], 2] = FixedArray[FixedArray[int, 2], 2]([FixedArray[int, 2]([0, 0]), FixedArray[int, 2]([0, 0])])
        \\    mut row = -3
        \\    grid[row][1] += 1
        \\    return grid[1][1]
    , "R_LIST_BOUNDS", 4);
    try trap(
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
        \\    mut total = 0
        \\    for i, value in enumerate(values):
        \\        const shifted = i - 9
        \\        total += values[shifted] + value
        \\    return total
    , "R_LIST_BOUNDS", 6);
}

// spec-case: PY-ARRAY-WRITE-1
test "an element write needs a mutable binding and a writable place" {
    try reject(
        \\func main() -> int:
        \\    mut text = "abc"
        \\    text[0] = "x"
        \\    return 0
    , "E_COLLECTION_METHOD", "");
}

// spec-case: PY-ARRAY-MUT-1
test "an element write through an array parameter that is not mut is rejected as for a list" {
    try reject(
        \\func set_first(values: FixedArray[int, 4]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    set_first(values)
        \\    return values[0]
    , "E_IMMUTABLE", "mutable binding");
    try reject(
        \\func set_first(mut values: FixedArray[int, 4]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func forward(values: FixedArray[int, 4]) -> Unit:
        \\    set_first(mut values)
        \\
        \\
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    forward(values)
        \\    return values[0]
    , "E_IMMUTABLE", "read-only");
    try expectValue(
        \\func peek(mut values: FixedArray[int, 4]) -> int:
        \\    return values[0]
        \\
        \\
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    return peek(mut values)
    , 0);
    try reject(
        \\func set_first(mut values: FixedArray[int, 4]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    set_first(values)
        \\    return values[0]
    , "E_MUTATION_MARKER", "write `(mut values)`");
}

// spec-case: PY-ARRAY-MUT-1
test "mut arrays support whole rebinding interior targets and function values" {
    try expectValue(
        \\func reset(mut values: FixedArray[int, 4]) -> Unit:
        \\    values = FixedArray[int, 4]([0, 0, 0, 0])
        \\
        \\
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 0, 0, 0])
        \\    reset(mut values)
        \\    return values[0]
    , 0);
    try expectValue(
        \\record Box:
        \\    cells: FixedArray[int, 4]
        \\
        \\
        \\func set_first(mut values: FixedArray[int, 4]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
        \\    mut box = Box(cells=FixedArray[int, 4]([0, 0, 0, 0]))
        \\    set_first(mut box.cells)
        \\    return box.cells[0]
    , 1);
    try expectValue(
        \\func set_first(mut values: FixedArray[int, 4]) -> Unit:
        \\    values[0] = 1
        \\
        \\
        \\func main() -> int:
        \\    const writer = set_first
        \\    mut values = FixedArray[int, 4]([0, 0, 0, 0])
        \\    writer(mut values)
        \\    return values[0]
    , 1);
}

test "a read-only argument of an array already passed mut is a snapshot" {
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\func reverse_into(mut target: FixedArray[int, 4], source: FixedArray[int, 4]) -> Unit:
        \\    for index in range(4):
        \\        target[index] = source[3 - index]
        \\
        \\
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([1, 2, 3, 4])
        \\    reverse_into(mut values, values)
        \\    return values[0] * 1000 + values[1] * 100 + values[2] * 10 + values[3]
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 4321), (try native.run(&c)).value);
}

/// Check one source and compare its first certain negative-index migration edit.
fn negativeFix(text: []const u8, replacement: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try t.expect(!report.passed);
    try t.expectEqualStrings("E_NEGATIVE_INDEX_REMOVED", report.diagnostics[0].code);
    try t.expectEqualStrings(replacement, report.diagnostics[0].provenance.fix.?.edit.text);
    try t.expectEqual(@as(usize, 1), report.diagnostics.len);
}

/// Index of the first diagnostic carrying `code`: one expression can be refused
/// twice (`xs[-9::-1]` removes its step and withholds the negative position).
fn indexOfCode(report: fixture.Report, code: []const u8) !usize {
    var found: ?usize = null;
    for (report.diagnostics, 0..) |d, i| {
        if (found == null and std.mem.eql(u8, d.code, code)) found = i;
    }
    try t.expect(found != null);
    return found.?;
}

/// An impure or global-getter base receives the diagnostic without a speculative edit.
fn negativeNoFix(text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const report = try fixture.check(arena.allocator(), text);
    try t.expect(!report.passed);
    const at = try indexOfCode(report, "E_NEGATIVE_INDEX_REMOVED");
    try t.expect(report.diagnostics[at].provenance.fix == null);
}

// spec: STEPPED-SLICE-1
test "wave3 stepped slice repair is certain and points at the removed step" {
    var compilation = try language.Compilation.init(
        t.allocator,
        fixture_path,
        "func main() -> int:\n    mut xs = [1, 2, 3, 4]\n    return len(xs[0:4:2])\n",
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const refused = compilation.diagnostics.items[0];
    try t.expectEqualStrings("E_STEPPED_SLICE_REMOVED", refused.code);
    // The span is the step the removal takes away, not the whole slice.
    try t.expectEqualStrings("2", compilation.src.text(refused.span));
    try t.expect(refused.provenance.fix != null);
    const repair = refused.provenance.fix.?.edit.text;
    try t.expect(std.mem.indexOf(u8, repair, "lists.stride(xs, 0, 4, 2)") != null);
}

// spec: NEGATIVE-INDEX-FIX-1
test "WAVE1 constant negatives carry certain sequence and slice edits" {
    try negativeFix("func main() -> int:\n    mut xs = [1, 2]\n    return xs[-1]\n", "len(xs) - 1");
    try negativeFix("func main() -> int:\n    mut xs = [1, 2]\n    return xs[0 - 1]\n", "len(xs) - 1");
    try negativeFix("func main() -> int:\n    mut xs = [1, 2]\n    return len(xs[3 - 5:])\n", "max(len(xs) - 2, 0)");
    try negativeFix("func main() -> int:\n    mut xs = [1, 2]\n    return len(xs[-5:])\n", "max(len(xs) - 5, 0)");
    try negativeFix("func last[T: copy + storable](xs: T[]) -> T:\n    return xs[-1]\n\n\nfunc main() -> int:\n    return 0\n", "len(xs) - 1");
    try negativeFix("func tail[T: copy + storable](xs: T[]) -> T[]:\n    return xs[-2:]\n\n\nfunc main() -> int:\n    return 0\n", "max(len(xs) - 2, 0)");
    try negativeFix("func last[T: copy + storable](xs: T[]) -> T:\n    return xs[-1]\n\n\nfunc main() -> int:\n    return last([1, 2])\n", "len(xs) - 1");
}

// spec: NEGATIVE-INDEX-FIX-2
// spec-case: STEPPED-SLICE-1
test "WAVE1 impure and global getter bases withhold negative position fixes" {
    try negativeNoFix("func main() -> int:\n    mut xs = [1, 2]\n    return len(xs[-9::-1])\n");
    try negativeNoFix("func values() -> int[]:\n    return [1, 2]\n\n\nfunc main() -> int:\n    return values()[-1]\n");
    try negativeNoFix("const WORD: str = \"xy\"\n\n\nfunc main() -> int:\n    return strings.char_count(strings.char_at(WORD, -1))\n");
    try negativeNoFix("func shorten(mut xs: int[]) -> int:\n    append(mut xs, 3)\n    return 0\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    return len(xs[shorten(mut xs):-1])\n");
}

// spec: NEGATIVE-INDEX-TRAP-1
test "WAVE1 computed negative sequence positions trap including formerly in-range negatives" {
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    return xs[i]\n", "R_LIST_BOUNDS", 4);
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    xs[i] = 3\n    return 0\n", "R_LIST_BOUNDS", 4);
    try trap("func main() -> int:\n    mut xs: FixedArray[int, 2] = FixedArray[int, 2]([1, 2])\n    mut i = -1\n    return xs[i]\n", "R_LIST_BOUNDS", 4);
    try trap("func main() -> int:\n    mut text = \"aé中😀b\"\n    mut i = -1\n    return strings.char_count(strings.char_at(text, i))\n", "R_TEXT_BOUNDS", 4);
    try trap("func main() -> int:\n    mut data = b\"abcd\"\n    mut i = -1\n    return data[i]\n", "R_LIST_BOUNDS", 4);
}

// spec: NEGATIVE-SLICE-TRAP-1
test "WAVE1 computed negative slice bounds trap even for empty or reversed ranges" {
    try trap("func main() -> int:\n    mut xs: int[] = []\n    mut i = -1\n    return len(xs[i:])\n", "R_LIST_BOUNDS", 4);
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    return len(xs[1:i])\n", "R_LIST_BOUNDS", 4);
    try trap("func main() -> int:\n    mut text = \"aé中😀b\"\n    mut i = -1\n    return strings.char_count(strings.char_slice(text, i, None))\n", "R_TEXT_BOUNDS", 4);
    try trap("func main() -> int:\n    mut data = b\"abcd\"\n    mut i = -1\n    return len(data[0:i])\n", "R_LIST_BOUNDS", 4);
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    return len(lists.stride(xs, i, 0, 1))\n", "R_LIST_BOUNDS", 4);
}

// spec: NEGATIVE-POSITION-METHOD-1
test "WAVE1 explicit negative list method positions trap and omitted pop keeps the tail" {
    try trap("import lists\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    return lists.pop_at(mut xs, i)\n", "R_LIST_BOUNDS", 7);
    try trap("import lists\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    return lists.exchange(mut xs, i, 3)\n", "R_LIST_BOUNDS", 7);
    try trap("import lists\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    mut i = -1\n    lists.insert(mut xs, i, 3)\n    return 0\n", "R_LIST_BOUNDS", 7);
    try expectValue("import lists\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    return lists.pop(mut xs)\n", 2);
}

// spec: NONNEGATIVE-BOUND-1
test "WAVE1 positive upper bounds clamp and omitted reverse slice bounds stay distinct" {
    try expectValue("func main() -> int:\n    mut xs = [1, 2, 3]\n    return len(xs[1:99]) + len(xs[99:]) + len(lists.stride(xs, None, None, -1))\n", 5);
    try expectValue("func main() -> int:\n    mut text = \"aé中😀b\"\n" ++
        "    return strings.char_count(strings.char_slice(text, 1, 99)) + strings.char_count(strings.char_slice(text, 99, None)) + strings.char_count(strings.char_stride(text, None, None, -1))\n", 9);
    try expectValue("func main() -> int:\n    mut data = b\"abcd\"\n    return len(data[1:99]) + len(data[99:])\n", 3);
    try expectValue("func main() -> int:\n    mut xs = [1, 2]\n    const bound = 18446744073709551615u64\n    return len(xs[0:bound]) + len(xs[bound:])\n", 2);
}

// spec: NEGATIVE-DICT-KEY-1
test "WAVE1 negative integer dictionary keys remain ordinary keys in concrete and generic bodies" {
    try expectValue("func value[T: copy + storable](mapping: dict[int, T]) -> T:\n    return mapping[-1]\n\n\nfunc main() -> int:\n    mut mapping: dict[int, int] = {-1: 42}\n    return value(mapping)\n", 42);
}

// spec-case: NEGATIVE-POSITION-METHOD-1
test "WAVE1 insertion evaluates position and value once in order and accepts unsigned positions" {
    try expectValue(
        \\import lists
        \\
        \\
        \\func mark(mut state: int[], tag: int) -> int:
        \\    state[0] = state[0] * 10 + tag
        \\    if tag == 1:
        \\        return 99
        \\    return 9
        \\
        \\
        \\func main() -> int:
        \\    mut xs = [1, 2]
        \\    mut state = [0]
        \\    lists.insert(mut xs, mark(mut state, 1), mark(mut state, 2))
        \\    return state[0] * 100 + xs[2]
    , 1209);
    try expectValue("import lists\n\n\nfunc main() -> int:\n    mut xs = [1, 2]\n    lists.insert(mut xs, 18446744073709551615u64, 9)\n    return len(xs) * 10 + xs[2]\n", 39);
}

// spec-case: NEGATIVE-GUARD-NOALLOC-1
test "WAVE1 slice guards root text before evaluating a bound exactly once" {
    try expectValue(
        \\func start(mut text: str, mut calls: int[]) -> int:
        \\    text = "changed"
        \\    calls[0] += 1
        \\    return 1
        \\
        \\
        \\func main() -> int:
        \\    mut text = "abc"
        \\    mut calls = [0]
        \\    const receiver = copy(text)
        \\    const part = strings.char_slice(receiver, start(mut text, mut calls), 99)
        \\    return strings.char_count(part) * 100 + strings.char_count(text) * 10 + calls[0]
    , 271);
}

// spec-case: NEGATIVE-INDEX-FIX-1
test "WAVE1 negative position fixes preserve arithmetic overflow and unsigned underflow traps" {
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    return xs[-128i8 - 1i8]\n", "R_OVERFLOW", 3);
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    return xs[0u8 - 1u8]\n", "R_OVERFLOW", 3);
    try trap("func main() -> int:\n    mut xs = [1, 2]\n    return xs[(127i8 + 1i8) - 2i8]\n", "R_OVERFLOW", 3);
}

// spec-case: NEGATIVE-INDEX-FIX-1
test "a list writer home keeps the method spelling's negative position repair" {
    // `lists.insert(mut values, -1, 3)` takes the collection it writes as its
    // marked first argument, so the clamp names that place and not the call.
    try negativeFix(
        // migrate-embedded: skip negative-position repair input must retain its negative operand
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    lists.insert(mut values, -1, 3)
        \\    return len(values)
    , "max(len(values) - 1, 0)");
    try negativeFix(
        // migrate-embedded: skip negative-position repair input must retain its negative operand
        \\import lists
        \\
        \\
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    _ = lists.pop_at(mut values, -2)
        \\    return len(values)
    , "len(values) - 2");
}

// spec-case: NEGATIVE-RANGE-BOUNDS-1
test "WAVE1 bounded search and numeric range constants have certain fixes in named direct and unused generic forms" {
    const calls = [_][]const u8{
        "strings.char_find(text, \"\", -1)",
        "strings.char_rfind(text, \"\", -1)",
        "strings.char_index(text, \"\", -1)",
        "strings.char_rindex(text, \"\", -1)",
        "strings.char_count_of(text, \"\", -1)",
        "strings.char_startswith(text, \"\", -1)",
        "strings.char_endswith(text, \"\", -1)",
    };
    for (calls) |call| {
        const source = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    const text = \"abc\"\n    _ = {s}\n    return 0\n", .{call});
        defer t.allocator.free(source);
        try negativeFix(source, "max(strings.char_count(text) - 1, 0)");
    }
    try negativeFix("import bytes\n\nfunc main() -> int:\n    _ = bytes.parse_int_range(b\"123\", -1, 99)\n    return 0\n", "max(len(b\"123\") - 1, 0)");
    try negativeFix("func value[T: copy](text: str, ignored: T) -> int:\n    return strings.char_find(text, \"\", -1)\n\n\nfunc main() -> int:\n    return 0\n", "max(strings.char_count(text) - 1, 0)");
    try negativeFix("import bytes\n\nfunc value[T: copy](data: bytes, ignored: T) -> int:\n    _ = bytes.parse_int_range(data, 0, -1)\n    return 0\n\n\nfunc main() -> int:\n    return 0\n", "max(len(data) - 1, 0)");
}

// spec-case: NEGATIVE-RANGE-BOUNDS-1
test "WAVE1 impure search needle and getter receiver withhold bound edits" {
    try negativeNoFix("func needle() -> str:\n    return \"a\"\n\n\nfunc main() -> int:\n    const text = \"abc\"\n    return strings.char_find(text, needle(), -1)\n");
    try negativeNoFix("func text() -> str:\n    return \"abc\"\n\n\nfunc main() -> int:\n    return strings.char_find(text(), \"\", -1)\n");
}

// spec-case: NEGATIVE-RANGE-BOUNDS-1
test "WAVE1 generated clamp bounds check in unused and instantiated generic bodies" {
    // `bytes.strip_chars` needs `import bytes` (W13-S5), so this body is checked as an embedded project,
    // where `strings.char_rfind` needs its import too.
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(),
        \\import bytes
        \\import strings
        \\
        \\func generic_methods[T: copy](marker: T, text: str, raw: bytes) -> bool:
        \\    _ = marker
        \\    return strings.char_rfind(text, "é", 1, max(strings.char_count(text) - 1, 0)) == 3 and bytes.strip_chars(raw, b"a") == b"\xffa\xff"
        \\
        \\
        \\func main() -> int:
        \\    return 0
    );
    const sources = [_][]const u8{
        "func value[T: copy](marker: T, text: str) -> int:\n    _ = marker\n    return max(strings.char_count(text) - 1, 0)\n\n\nfunc main() -> int:\n    return value(1, \"abc\")\n",
        "func value[T: integer](a: T, b: T) -> T:\n    return min(a, b)\n\n\nfunc main() -> int:\n    return value(1, 2)\n",
        "func value[T: copy](marker: T) -> bool:\n    _ = marker\n    return max(1.0, 2.0) == 2.0 and min(\"a\", \"b\") == \"a\"\n\n\nfunc main() -> int:\n    return 0\n",
        "func pick_max(a: int, b: int) -> bool:\n    return a == b\n\n\nfunc value[T: copy](marker: T) -> bool:\n    _ = marker\n    return pick_max(1, 2)\n\n\nfunc main() -> int:\n    return 0\n",
    };
    for (sources) |text| {
        var compilation = try language.Compilation.init(t.allocator, fixture_path, text);
        defer compilation.deinit();
        try compilation.check();
    }
}

// spec-case: NEGATIVE-RANGE-BOUNDS-1
test "WAVE1 generic scalar clamp rejects mixed and unordered operands" {
    const sources = [_][]const u8{
        "func value[T: copy](marker: T) -> int:\n    _ = marker\n    return max(1, \"a\")\n\n\nfunc main() -> int:\n    return 0\n",
        "func value[T: copy](marker: T) -> bool:\n    _ = marker\n    return min(True, False)\n\n\nfunc main() -> int:\n    return 0\n",
    };
    for (sources) |text| {
        var compilation = try language.Compilation.init(t.allocator, fixture_path, text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expect(!std.mem.startsWith(u8, compilation.diagnostics.items[0].code, "E_UNKNOWN"));
    }
}

// spec-case: NEGATIVE-INDEX-FIX-2
test "WAVE1 generated clamp fixes withhold edits for top level max shadowing" {
    try negativeNoFix("func max(a: int, b: int) -> int:\n    return a + b\n\n\nfunc main() -> int:\n    const text = \"abc\"\n    return strings.char_rfind(text, \"\", 0, -1)\n");
}

// spec-case: NEGATIVE-INDEX-FIX-1
test "the original negative-position trap sources retain executable retirement diagnostics" {
    // migrate-embedded: skip original C0 runtime-negative source; modern runtime counterpart remains above
    var legacy_0 = try language.Compilation.init(t.allocator, "original-retirement.selka",
        \\func main() -> int:
        \\    mut values: FixedArray[int, 4] = FixedArray[int, 4]([0, 0, 0, 0])
        \\    values[-5] = 5
        \\    return values[3]
    );
    defer legacy_0.deinit();
    try t.expectError(error.SourceError, legacy_0.check());
    const found_0 = for (legacy_0.diagnostics.items) |item| {
        if (std.mem.eql(u8, item.code, "E_NEGATIVE_INDEX_REMOVED")) break true;
    } else false;
    try t.expect(found_0);
}

// spec-case: NEGATIVE-INDEX-FIX-1
test "the original nested negative-position source retains its retirement diagnostic" {
    // migrate-embedded: skip original C0 runtime-negative source; modern runtime counterpart remains above
    var legacy_1 = try language.Compilation.init(t.allocator, "original-retirement.selka",
        \\func main() -> int:
        \\    mut grid: FixedArray[FixedArray[int, 2], 2] = FixedArray[FixedArray[int, 2], 2]([FixedArray[int, 2]([0, 0]), FixedArray[int, 2]([0, 0])])
        \\    mut row = -3
        \\    grid[row][-1] += 1
        \\    return grid[1][1]
    );
    defer legacy_1.deinit();
    try t.expectError(error.SourceError, legacy_1.check());
    const found_1 = for (legacy_1.diagnostics.items) |item| {
        if (std.mem.eql(u8, item.code, "E_NEGATIVE_INDEX_REMOVED")) break true;
    } else false;
    try t.expect(found_1);
}
