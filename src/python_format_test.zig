//! Interpolated `f"..."` literals lower to str conversion and concatenation.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const io_render = @import("io_render.zig");

fn execute(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "format.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-FSTRING-1
test "format strings interpolate expressions and render every value" {
    try execute(
        \\def label(count: int, items: list[int]) -> str:
        \\    return f"total {count} of {len(items)} items"
        \\
        \\def main() -> int:
        \\    score = 0
        \\    if label(7, [1, 2, 3]) == "total 7 of 3 items":
        \\        score = score + 1
        \\    if f"{1 + 1}" == "2":
        \\        score = score + 2
        \\    if f"{True} {None} {1.5}" == "True None 1.5":
        \\        score = score + 4
        \\    name = "x"
        \\    if f"a\t{name}b" == "a\tx" + "b":
        \\        score = score + 8
        \\    if f"{f'{name}'}" == "x":
        \\        score = score + 16
        \\    return score
    , 31);
}

// spec: PY-FSTRING-2
test "doubled braces are literal and an empty format string is empty text" {
    try execute(
        \\def main() -> int:
        \\    score = 0
        \\    if f"{{literal}}" == "{literal}":
        \\        score = score + 1
        \\    if f"" == "":
        \\        score = score + 2
        \\    if f"no holes" == "no holes":
        \\        score = score + 4
        \\    return score
    , 7);
}

// spec-case: PY-FSTRING-2
test "malformed format strings and unconvertible values are rejected" {
    const header = "def main() -> int:\n    x = 1\n    _ = ";
    const capability = "def main(fs: Filesystem) -> int:\n    _ = f\"{fs}\"\n    return 0\n";
    try reject(capability, "E_TEXT_CONVERSION");
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body = "f\"{}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{x:.2f}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"a}b\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{1 2}\"", .code = "E_FORMAT_STRING" },
        .{ .body = "f\"{x\"", .code = "E_FORMAT_STRING" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, case.body, "\n    return 0\n" });
        defer t.allocator.free(text);
        try reject(text, case.code);
    }
}

// spec-case: PY-FSTRING-1
test "an f before anything but a quote stays an ordinary identifier" {
    try execute(
        \\def main() -> i64:
        \\    f = 42
        \\    return f
    , 42);
}

/// Every kind of value a hole renders, printed beside its own interpolation so
/// the two spellings must agree byte for byte, and scored so the converted text
/// is checked as well.
const rendered_holes =
    \\class Point:
    \\    x: int
    \\    y: int
    \\
    \\enum Colour:
    \\    red,
    \\    green
    \\
    \\def pick(n: int) -> Result[int, str]:
    \\    if n < 0:
    \\        return Err("nope")
    \\    return Ok(n)
    \\
    \\def main() -> int:
    \\    score = 0
    \\    values = [1, 2]
    \\    counts: dict[str, int] = {"k": 1}
    \\    spot = Point(x=1, y=2)
    \\    found: Option[int] = Some(4)
    \\    raw = b"ab"
    \\    print(values, f"{values}")
    \\    print(counts, f"{counts}")
    \\    print(spot, f"{spot}")
    \\    print(Colour.green, f"{Colour.green}")
    \\    print(pick(3), f"{pick(3)}")
    \\    print(pick(-1), f"{pick(-1)}")
    \\    print(found, f"{found}")
    \\    print(raw, f"{raw}")
    \\    if f"{values}" == "[1, 2]":
    \\        score = score + 1
    \\    if f"{counts}" == "{'k': 1}":
    \\        score = score + 2
    \\    if f"{spot} {Colour.green}" == "Point(x=1, y=2) Colour.green":
    \\        score = score + 4
    \\    if f"{pick(3)} {pick(-1)} {found}" == "Ok(3) Err('nope') Some(4)":
    \\        score = score + 8
    \\    if f"{raw}" == "b'ab'":
    \\        score = score + 16
    \\    return score
;

// spec-case: PY-FSTRING-1
test "a native build spells an interpolated aggregate exactly as print writes it" {
    var c = try language.Compilation.init(t.allocator, "format.my", rendered_holes);
    defer c.deinit();
    const outcome = try native.run(&c);
    try t.expectEqualStrings("", outcome.trap.code);
    try t.expectEqual(@as(i64, 31), outcome.value);
    try t.expectEqualStrings(
        \\[1, 2] [1, 2]
        \\{'k': 1} {'k': 1}
        \\Point(x=1, y=2) Point(x=1, y=2)
        \\Colour.green Colour.green
        \\Ok(3) Ok(3)
        \\Err('nope') Err('nope')
        \\Some(4) Some(4)
        \\b'ab' b'ab'
        \\
    , outcome.stdout);
}

// spec-case: PY-FSTRING-1
test "an aggregate hole renders through the renderers print itself calls" {
    var c = try language.Compilation.init(t.allocator, "format.my", rendered_holes);
    defer c.deinit();
    const manifest = try c.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_qbe_text_render") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_print_list") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_print_dictionary") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "myl_print_variant") != null);
}

// spec-case: PY-FSTRING-2
test "renderAlloc releases its partial buffer when the allocator fails" {
    var failing = t.FailingAllocator.init(t.allocator, .{ .fail_index = 0 });
    try t.expectError(error.OutOfMemory, io_render.renderAlloc(failing.allocator(), &.{}, .{ .i64 = 42 }));
}
