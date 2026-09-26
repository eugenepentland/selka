//! Scalar receiver loans preserve roots and refuse observable snapshot windows.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn copiesIn(source: []const u8, name: []const u8) !usize {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "rc_read_loans.my", source);
    defer compilation.deinit();
    const emitted = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(emitted);
    var manifest = try std.json.parseFromSlice(Manifest, t.allocator, emitted, .{ .ignore_unknown_fields = true });
    defer manifest.deinit();
    for (manifest.value.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, "call $myl_rc_native_copy");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-READ-LOAN-1
test "RC scalar receiver loans avoid copies through negative-index control flow" {
    try t.expectEqual(@as(usize, 0), try copiesIn(
        \\def scan(xs: list[int], at: int) -> int:
        \\    return len(xs) + xs[at]
        \\def main() -> int:
        \\    return scan([1, 2, 3], -1)
    , "scan"));
}

// spec-case: RC-READ-LOAN-1
test "RC scalar receiver loans keep snapshots around mutating index callbacks" {
    try t.expect(try copiesIn(
        \\def change(xs: mut list[int]) -> int:
        \\    xs[0] = 9
        \\    return 0
        \\def scan(xs: mut list[int]) -> int:
        \\    return xs[change(mut xs)]
        \\def main() -> int:
        \\    values = [1, 2, 3]
        \\    return scan(mut values)
    , "scan") > 0);
}

// spec-case: RC-READ-LOAN-1
test "RC scalar receiver loans do not borrow managed element results" {
    try t.expect(try copiesIn(
        \\def selected(xs: list[list[int]], at: int) -> list[int]:
        \\    return xs[at]
        \\def main() -> int:
        \\    return len(selected([[1]], 0))
    , "selected") > 0);
}

// spec: RC-NESTED-READ-LOAN-1
test "RC nested receiver loans borrow rows until a scalar result" {
    try t.expectEqual(@as(usize, 0), try copiesIn(
        \\def selected(rows: list[list[int]], i: int, j: int, output: mut list[int]) -> int:
        \\    value = rows[i][j]
        \\    output.append(value)
        \\    return value
        \\def main() -> int:
        \\    output: list[int] = []
        \\    return selected([[1]], 0, 0, mut output)
    , "selected"));
}

// spec-case: RC-NESTED-READ-LOAN-1
test "RC nested receiver loans refuse a callback inside a projected row" {
    try t.expect(try copiesIn(
        \\def change(rows: mut list[list[int]]) -> int:
        \\    rows[0][0] = 9
        \\    return 0
        \\def selected(rows: mut list[list[int]]) -> int:
        \\    return rows[0][change(mut rows)]
        \\def main() -> int:
        \\    rows = [[1]]
        \\    return selected(mut rows)
    , "selected") > 0);
}

// spec-case: RC-NESTED-READ-LOAN-1
test "RC nested receiver loans retain ownership for named rows" {
    try t.expect(try copiesIn(
        \\def selected(rows: list[list[int]], output: mut list[int]) -> int:
        \\    row = rows[0]
        \\    output.append(7)
        \\    return row[0]
        \\def main() -> int:
        \\    output: list[int] = []
        \\    return selected([[1]], mut output)
    , "selected") > 0);
}
