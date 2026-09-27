//! Scalar receiver loans preserve roots and refuse observable snapshot windows.
const std = @import("std");
const compiler = @import("compiler.zig");
const runtime = @import("runtime_mode.zig");
const t = std.testing;
const Manifest = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn copiesIn(source: []const u8, name: []const u8) !usize {
    return callsIn(source, name, false);
}

fn callsIn(source: []const u8, name: []const u8, loans: bool) !usize {
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
        if (loans and std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, "call $myl_rc_native_loan");
        if (std.mem.eql(u8, function.name, name)) return std.mem.count(u8, function.il, "call $myl_rc_native_publish") + std.mem.count(u8, function.il, "call $myl_rc_native_retain");
    }
    return error.TestUnexpectedResult;
}

// spec: RC-PLAIN-READ-LOAN-1
test "RC plain aggregate reads borrow their inert receiver until the inline copy" {
    try t.expectEqual(@as(usize, 0), try callsIn(
        \\record Point:
        \\    x: int
        \\    y: int
        \\def selected(rows: list[Point], at: int, output: mut list[int]) -> int:
        \\    point = rows[at]
        \\    output.append(point.x)
        \\    return point.y
        \\def main() -> int:
        \\    output: list[int] = []
        \\    return selected([Point(3, 7)], -1, mut output)
    , "selected", true));
}

// spec-case: RC-PLAIN-READ-LOAN-1
test "RC plain aggregate read callbacks retain the captured list loan" {
    try t.expect(try callsIn(
        \\record Point:
        \\    x: int
        \\    y: int
        \\def change(rows: mut list[Point]) -> int:
        \\    rows.clear()
        \\    rows.append(Point(9, 11))
        \\    return 0
        \\def selected(rows: mut list[Point]) -> int:
        \\    return rows[change(mut rows)].x
        \\def main() -> int:
        \\    rows = [Point(3, 7)]
        \\    return selected(mut rows)
    , "selected", true) > 0);
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

const field_source =
    \\record Label:
    \\    data: bytes
    \\    number: int
    \\record Row:
    \\    left: Label
    \\    number: int
    \\record HeldRow:
    \\    view: DictValues[int, int]
    \\    number: int
    \\def selected(rows: list[Row], at: int, output: mut list[int]) -> int:
    \\    number = rows[at].left.number
    \\    output.append(number)
    \\    return number
    \\def escaped(rows: list[Row], at: int, output: mut list[int]) -> int:
    \\    row = rows[at]
    \\    output.append(row.number)
    \\    return row.left.number
    \\def change(rows: mut list[Row]) -> int:
    \\    rows[0] = Row(Label(b"new", 9), 11)
    \\    return 0
    \\def callback(rows: mut list[Row]) -> int:
    \\    return rows[change(mut rows)].left.number
    \\def held(rows: list[HeldRow], output: mut list[int]) -> int:
    \\    number = rows[0].number
    \\    output.append(number)
    \\    return number
    \\def main() -> int:
    \\    output: list[int] = []
    \\    return selected([Row(Label(b"value", 3), 7)], -1, mut output)
;

// spec: RC-PLAIN-FIELD-LOAN-1
test "RC plain field chains retain only the stable list root" {
    try t.expectEqual(@as(usize, 0), try callsIn(field_source, "selected", true));
    try t.expectEqual(@as(usize, 0), try copiesIn(field_source, "selected"));
}

// spec-case: RC-PLAIN-FIELD-LOAN-1
test "RC plain field chains refuse escaped records callbacks and live views" {
    try t.expect(try callsIn(field_source, "escaped", true) > 0);
    try t.expect(try callsIn(field_source, "callback", true) > 0);
    try t.expect(try callsIn(field_source, "held", true) > 0);
}

// spec-case: RC-PLAIN-FIELD-LOAN-1
test "RC plain field chains refuse more than eight adjacent projections" {
    const text =
        \\record Base:
        \\    text: bytes
        \\    value: int
        \\record A:
        \\    next: Base
        \\record B:
        \\    next: A
        \\record C:
        \\    next: B
        \\record D:
        \\    next: C
        \\record E:
        \\    next: D
        \\record F:
        \\    next: E
        \\record G:
        \\    next: F
        \\record H:
        \\    next: G
        \\def admitted(rows: list[G], output: mut list[int]) -> int:
        \\    n = rows[0].next.next.next.next.next.next.next.value
        \\    output.append(n)
        \\    return n
        \\def refused(rows: list[H], output: mut list[int]) -> int:
        \\    n = rows[0].next.next.next.next.next.next.next.next.value
        \\    output.append(n)
        \\    return n
        \\def main() -> int:
        \\    return 0
    ;
    try t.expectEqual(@as(usize, 0), try callsIn(text, "admitted", true));
    try t.expect(try callsIn(text, "refused", true) > 0);
}
