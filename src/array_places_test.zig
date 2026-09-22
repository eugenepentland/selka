//! Fixed-array element writes, `mut [N]T` parameters and array loops: the
//! rejections, traps and emitted-IL facts a guest test cannot observe.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const fixture_path = "places.my";
const Unit = struct { name: []const u8, symbol: []const u8, il: []const u8 };
const Manifest = struct { version: []const u8, abi: []const u8, functions: []Unit, entry: []const u8 };

fn emitted(source: []const u8) !std.json.Parsed(Manifest) {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    const manifest = try c.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    return std.json.parseFromSlice(Manifest, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}
fn named(manifest: Manifest, name: []const u8) ![]const u8 {
    for (manifest.functions) |unit| if (std.mem.eql(u8, unit.name, name)) return unit.il;
    return error.TestUnexpectedResult;
}
/// Check `source` and require its first diagnostic to carry `code` and a
/// message containing `fragment`.
fn reject(source: []const u8, code: []const u8, fragment: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, fixture_path, source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, fragment) != null);
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
test "an element write out of range or negative traps like a fixed-array read" {
    try trap(
        \\def main() -> int:
        \\    values: [4]int = [0, 0, 0, 0]
        \\    index = 4
        \\    values[index] = 5
        \\    return values[3]
    , "R_INDEX_BOUNDS", 4);
    try trap(
        \\def main() -> int:
        \\    values: [4]int = [0, 0, 0, 0]
        \\    values[-1] = 5
        \\    return values[3]
    , "R_INDEX_BOUNDS", 3);
    try trap(
        \\def main() -> int:
        \\    grid: [2][2]int = [[0, 0], [0, 0]]
        \\    column = 2
        \\    grid[1][column] += 1
        \\    return grid[1][1]
    , "R_INDEX_BOUNDS", 4);
}

// spec-case: PY-ARRAY-WRITE-1
test "an element write needs a mutable binding and a writable place" {
    try reject(
        \\def main() -> int:
        \\    words: [2]str = ["a", "b"]
        \\    with arena() as scratch:
        \\        words[0] = str(3) + "x"
        \\    return 0
    , "E_ARENA_ESCAPE", "outlives arena");
    try reject(
        \\def main() -> int:
        \\    text = "abc"
        \\    text[0] = "x"
        \\    return 0
    , "E_COLLECTION_METHOD", "");
}

// spec-case: PY-ARRAY-MUT-1
test "an element write through an array parameter that is not mut is rejected as for a list" {
    try reject(
        \\def set_first(values: [4]int) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [0, 0, 0, 0]
        \\    set_first(values)
        \\    return values[0]
    , "E_MUTATION_MARKER", "declare `values: mut [4]int`");
    try reject(
        \\def set_first(values: mut [4]int) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def forward(values: [4]int) -> None:
        \\    set_first(mut values)
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [0, 0, 0, 0]
        \\    forward(values)
        \\    return values[0]
    , "E_MUTATION_MARKER", "declare `values: mut [4]int`");
    try reject(
        \\def peek(values: mut [4]int) -> int:
        \\    return values[0]
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [0, 0, 0, 0]
        \\    return peek(mut values)
    , "E_MUTATION_MARKER", "never written");
    try reject(
        \\def set_first(values: mut [4]int) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [0, 0, 0, 0]
        \\    set_first(values)
        \\    return values[0]
    , "E_MUTATION_MARKER", "write `(mut values)`");
}

// spec-case: PY-ARRAY-MUT-1
test "a mut array parameter names the caller's variable and nothing else" {
    try reject(
        \\def reset(values: mut [4]int) -> None:
        \\    values = [0, 0, 0, 0]
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [1, 0, 0, 0]
        \\    reset(mut values)
        \\    return values[0]
    , "E_ASSIGNMENT_TARGET", "names the caller's array");
    try reject(
        \\record Box:
        \\    cells: [4]int
        \\
        \\
        \\def set_first(values: mut [4]int) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    box = Box(cells=[0, 0, 0, 0])
        \\    set_first(mut box.cells)
        \\    return box.cells[0]
    , "E_MUTATION_MARKER", "copy the field or element into a local");
    try reject(
        \\def set_first(values: mut [4]int) -> None:
        \\    values[0] = 1
        \\
        \\
        \\def main() -> int:
        \\    writer = set_first
        \\    return 0
    , "E_CALLBACK_TYPE", "cannot be used as a value");
}

// spec: QBE-ARRAYREF-1
test "a mut array argument is the caller's slot and the callee writes through it" {
    var parsed = try emitted(
        \\def set_first(values: mut [4]int, value: int) -> None:
        \\    values[0] = value
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [1, 2, 3, 4]
        \\    set_first(mut values, 9)
        \\    return values[0]
    );
    defer parsed.deinit();
    const callee = try named(parsed.value, "set_first");
    // The callee takes the caller's address: no entry copy, no scratch, and
    // the element is stored through the address its slot holds.
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, callee, "blit "));
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, callee, "%agg"));
    try t.expect(std.mem.indexOf(u8, callee, "storel %a0, %l0") != null);
    try t.expect(std.mem.indexOf(u8, callee, "=l loadl %l0") != null);
    try t.expect(std.mem.indexOf(u8, callee, "$myl_qbe_fail_array_bounds") != null);
    // The caller hands over its own slot rather than a snapshot of it.
    const caller = try named(parsed.value, "main");
    try t.expect(std.mem.indexOf(u8, caller, "storel %l0, %s0") != null);
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, caller, "blit "));
}

// spec-case: QBE-ARRAYREF-1
test "a read-only argument of an array already passed mut is a snapshot" {
    var parsed = try emitted(
        \\def reverse_into(target: mut [4]int, source: [4]int) -> None:
        \\    for index in range(4):
        \\        target[index] = source[3 - index]
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [1, 2, 3, 4]
        \\    reverse_into(mut values, values)
        \\    return values[0]
    );
    defer parsed.deinit();
    const caller = try named(parsed.value, "main");
    try t.expectEqual(@as(usize, 1), std.mem.count(u8, caller, "blit %l0, %agg"));
    var c = try language.Compilation.init(t.allocator, fixture_path,
        \\def reverse_into(target: mut [4]int, source: [4]int) -> None:
        \\    for index in range(4):
        \\        target[index] = source[3 - index]
        \\
        \\
        \\def main() -> int:
        \\    values: [4]int = [1, 2, 3, 4]
        \\    reverse_into(mut values, values)
        \\    return values[0] * 1000 + values[1] * 100 + values[2] * 10 + values[3]
    );
    defer c.deinit();
    try t.expectEqual(@as(i64, 4321), (try native.run(&c)).value);
}

// spec-case: QBE-ARRAYREF-1
test "an element write into a local array names no scratch" {
    var parsed = try emitted(
        \\def main() -> int:
        \\    values: [8]int = [0, 0, 0, 0, 0, 0, 0, 0]
        \\    for index in range(8):
        \\        values[index] = index
        \\    values[3] += values[7]
        \\    return values[3]
    );
    defer parsed.deinit();
    const body = try named(parsed.value, "main");
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, body, "blit "));
    try t.expectEqual(@as(usize, 0), std.mem.count(u8, body, "%agg"));
}
