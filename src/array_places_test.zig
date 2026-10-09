//! Fixed-array element writes, `mut [N]T` parameters and array loops: the
//! rejections and traps a guest test cannot observe.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const fixture_path = "places.my";

/// Check `source` and require its first diagnostic to carry `code` and a
/// message containing `fragment`.
fn reject(source: []const u8, code: []const u8, fragment: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, fragment) != null);
}
/// Run a supported array update and check its caller-visible result.
fn expectValue(source: []const u8, wanted: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, fixture_path, source);
    defer compilation.deinit();
    try t.expectEqual(wanted, (try native.run(&compilation)).value);
}
/// Run `source` natively and require a trap with `code` at `line`.
fn trap(source: []const u8, code: []const u8, line: u64) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    const result = try native.run(&c);
    try t.expectEqualStrings(code, result.trap.code);
    try t.expectEqual(line, result.trap.line);
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
        \\    values[-5] = 5
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
        \\    grid[row][-1] += 1
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
