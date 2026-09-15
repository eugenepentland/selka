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
