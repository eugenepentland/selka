//! Managed `Cell[T]` construction, shared mutation, GC rooting, and content policy.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const module = "managed-cell.my";

fn run(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, module, source);
    defer compilation.deinit();
    const outcome = native.runWithOptions(&compilation, .{ .gc_stress = true }) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(expected, outcome.value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: MANAGED-CELL-1
test "Cell construction reads and replacement share mutation across aliases and calls under GC stress" {
    try run(
        \\def bump(cell: Cell[int]) -> None:
        \\    cell.value = cell.value + 1
        \\
        \\
        \\def main() -> int:
        \\    cell = Cell(value=40)
        \\    alias = cell
        \\    bump(alias)
        \\    bump(cell)
        \\    return cell.value
    , 42);
    try run(
        \\def push(cell: Cell[list[int]]) -> None:
        \\    cell.value.append(7)
        \\
        \\
        \\def main() -> int:
        \\    cell = Cell[int](value=1)
        \\    alias = cell
        \\    alias.value = 6
        \\    if cell.value != 6:
        \\        return 1
        \\    values = Cell(value=[1, 2])
        \\    push(values)
        \\    return values.value[2]
    , 7);
}

// spec-case: MANAGED-CELL-1
test "Cell rejects result obligations equality and rendering" {
    try reject(
        \\def main() -> int:
        \\    cell: Cell[Result[int, str]] = Cell(value=Ok(1))
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(
        \\def main() -> int:
        \\    left = Cell(value=1)
        \\    right = Cell(value=1)
        \\    if left == right:
        \\        return 1
        \\    return 0
    , "E_CELL_EQUALITY");
    try reject(
        \\def main() -> int:
        \\    cell = Cell(value=1)
        \\    print(cell)
        \\    return 0
    , "E_IO_ARGUMENT");
    try reject(
        \\def build() -> Cell[int] noalloc:
        \\    return Cell(value=1)
        \\
        \\
        \\def main() -> int:
        \\    return build().value
    , "E_EFFECT_BOUND");
}

// spec: CELL-COLLECTION-1
test "Cell is rejected by collection and prelude operations instead of crashing" {
    try reject(
        \\def main() -> int:
        \\    cell = Cell(value=1)
        \\    sorted(cell, key=lambda x: x)
        \\    return 0
    , "E_PRELUDE_TYPE");
    try reject(
        \\def first[T](cell: Cell[T]) -> T:
        \\    return cell[0]
        \\
        \\
        \\def main() -> int:
        \\    cell = Cell(value=1)
        \\    return first(cell)
    , "E_LIST_TYPE");
}

// spec: CELL-GENERIC-1
test "generic Cell construction is recognized and tracks allocation effects" {
    try run(
        \\def make[T](value: T) -> Cell[T]:
        \\    return Cell(value=value)
        \\
        \\
        \\def main() -> int:
        \\    cell = make(41)
        \\    return cell.value + 1
    , 42);
    try reject(
        \\def make[T](value: T) -> Cell[T] noalloc:
        \\    return Cell(value=value)
        \\
        \\
        \\def main() -> int:
        \\    return 0
    , "E_EFFECT_BOUND");
    try reject(
        \\def make[T](value: T) -> Cell[T] noalloc:
        \\    return Cell[T](value=value)
        \\
        \\
        \\def main() -> int:
        \\    return 0
    , "E_EFFECT_BOUND");
    try run(
        \\def make[T]() -> Cell[list[T]]:
        \\    return Cell(value=[])
        \\
        \\
        \\def main() -> int:
        \\    return len(make[i64]().value)
    , 0);
    try run(
        \\def zero[T](unused: T) -> Cell[float]:
        \\    _ = unused
        \\    return Cell(value=0)
        \\
        \\
        \\def main() -> int:
        \\    cell = zero(1)
        \\    if cell.value == 0.0:
        \\        return 0
        \\    return 1
    , 0);
}

// spec: CELL-EQUALITY-1
test "Cell equality is rejected for membership search and nested containers" {
    try reject(
        \\def main() -> int:
        \\    cell = Cell(value=1)
        \\    if cell in [cell]:
        \\        return 1
        \\    return 0
    , "E_CELL_EQUALITY");
    try reject(
        \\def main() -> int:
        \\    values = [Cell(value=1)]
        \\    return values.index(Cell(value=1))
    , "E_CELL_EQUALITY");
    try reject(
        \\record Holder:
        \\    cell: Cell[int]
        \\
        \\
        \\def main() -> int:
        \\    item = Holder(cell=Cell(value=1))
        \\    if item in [item]:
        \\        return 1
        \\    return 0
    , "E_CELL_EQUALITY");
    try reject(
        \\def main() -> int:
        \\    return [Cell(value=1)].index(Cell(value=1))
    , "E_CELL_EQUALITY");
    try reject(
        \\def main() -> int:
        \\    [Cell(value=1)].remove(Cell(value=1))
        \\    return 0
    , "E_CELL_EQUALITY");
    try reject(
        \\record Holder:
        \\    cells: list[Cell[int]]
        \\
        \\
        \\def main() -> int:
        \\    holder = Holder(cells=[Cell(value=1)])
        \\    return holder.cells.index(Cell(value=1))
    , "E_CELL_EQUALITY");
    try reject(
        \\def make() -> list[Cell[int]]:
        \\    return [Cell(value=1)]
        \\
        \\
        \\def main() -> int:
        \\    return make().remove(Cell(value=1))
    , "E_CELL_EQUALITY");
    try run(
        \\def main() -> int:
        \\    values = {"answer": Cell(value=42)}
        \\    if "answer" in values:
        \\        return values["answer"].value
        \\    return 0
    , 42);
}
