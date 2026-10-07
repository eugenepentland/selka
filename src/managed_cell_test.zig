//! Managed `Cell[T]` construction, shared mutation, GC rooting, and content policy.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const module = "managed-cell.my";

fn run(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(t.allocator, module, source);
    defer compilation.deinit();
    const outcome = native.runWithOptions(&compilation, .{}) catch |err| {
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

// spec-case: MANAGED-CELL-1
test "Cell rejects result obligations equality and rendering" {
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
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
        \\def main(out: Stream) -> int:
        \\    cell = Cell(value=1)
        \\    out.print(cell)
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
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
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
