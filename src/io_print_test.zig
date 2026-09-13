//! `print`: Python rendering of every ordinary value shape, `sep=`/`end=` keywords,
//! the `output` effect that `noio` withholds, and the native backend's rejection.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const io_render = @import("io_render.zig");

const module = "io-print.my";

/// Execute one program and return everything it wrote to standard output.
fn output(allocator: std.mem.Allocator, text: []const u8) ![]u8 {
    var compilation = try language.Compilation.init(allocator, module, text);
    defer compilation.deinit();
    var written: std.Io.Writer.Allocating = .init(allocator);
    errdefer written.deinit();
    const result = compilation.executeWithOptions(allocator, .{ .output = &written.writer }) catch |err| {
        if (err != error.OutOfMemory) @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    if (result == .trap) {
        written.deinit();
        try t.expectEqualStrings("", result.trap.code);
        unreachable;
    }
    return written.toOwnedSlice();
}

fn expectOutput(text: []const u8, expected: []const u8) !void {
    const written = try output(t.allocator, text);
    defer t.allocator.free(written);
    try t.expectEqualStrings(expected, written);
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: IO-1
test "IO-1 print renders scalars, text, bytes and containers with Python spellings" {
    try expectOutput("def main() -> int:\n    print(42)\n    return 0\n", "42\n");
    try expectOutput("def main() -> int:\n    print(1, 2, 3)\n    return 0\n", "1 2 3\n");
    try expectOutput("def main() -> int:\n    print()\n    return 0\n", "\n");
    try expectOutput("def main() -> int:\n    print(True, False, None)\n    return 0\n", "True False None\n");
    try expectOutput("def main() -> int:\n    print(1.5)\n    print(3.0)\n    return 0\n", "1.5\n3.0\n");
    try expectOutput("def main() -> int:\n    print(\"hi there\")\n    return 0\n", "hi there\n");
    try expectOutput("def main() -> int:\n    print(b\"a\\n\\xff\")\n    return 0\n", "b'a\\n\\xff'\n");
    try expectOutput("def main() -> int:\n    print([1, 2, 3])\n    return 0\n", "[1, 2, 3]\n");
    try expectOutput("def main() -> int:\n    print([\"a\", \"b\"])\n    return 0\n", "['a', 'b']\n");
    try expectOutput("def main() -> int:\n    counts = {\"a\": 1, \"b\": 2}\n    print(counts)\n    return 0\n", "{'a': 1, 'b': 2}\n");
}

// spec: IO-2
test "IO-2 print renders records, enums, unions and checked results by name" {
    const record = "class Point:\n    x: int\n    y: int\n\ndef main() -> int:\n    print(Point(x=1, y=2))\n    return 0\n";
    try expectOutput(record, "Point(x=1, y=2)\n");
    const colours = "enum Colour { red, green }\ndef main() -> int:\n    print(Colour.green)\n    return 0\n";
    try expectOutput(colours, "Colour.green\n");
    const shape = "union Shape { dot: i64, gap }\ndef main() -> int:\n    print(new Shape.dot(7))\n    print(new Shape.gap)\n    return 0\n";
    try expectOutput(shape, "Shape.dot(7)\nShape.gap\n");
    const checked = "def pick(n: int) -> Result[int, str]:\n    if n < 0:\n        return Err(\"negative\")\n    return Ok(n)\n\ndef main() -> int:\n    print(pick(3))\n    print(pick(-1))\n    return 0\n";
    try expectOutput(checked, "Ok(3)\nErr('negative')\n");
    const option = "def main() -> int:\n    found: Option[int] = Some(4)\n    missing: Option[int] = None\n    print(found, missing)\n    return 0\n";
    try expectOutput(option, "Some(4) None\n");
}

// spec: IO-3
test "IO-3 print accepts sep and end keyword arguments and rejects other keywords" {
    try expectOutput("def main() -> int:\n    print(1, 2, sep=\"-\")\n    return 0\n", "1-2\n");
    try expectOutput("def main() -> int:\n    print(1, end=\"\")\n    print(2)\n    return 0\n", "12\n");
    try expectOutput("def main() -> int:\n    print(1, 2, sep=\"\", end=\"!\")\n    return 0\n", "12!");
    try reject("def main() -> int:\n    print(1, flush=True)\n    return 0\n", "E_IO_ARGUMENT");
    try reject("def main() -> int:\n    print(1, sep=\"-\", sep=\",\")\n    return 0\n", "E_IO_ARGUMENT");
    try reject("def main() -> int:\n    print(sep=\"-\", 1)\n    return 0\n", "E_CALL_ARGUMENT");
    try reject("def main() -> int:\n    print(1, sep=2)\n    return 0\n", "E_TYPE");
}

// spec: IO-4
test "IO-4 print contributes the output effect that noio withholds" {
    try reject("def main() -> int noio:\n    print(1)\n    return 0\n", "E_EFFECT_BOUND");
    try reject("def emit() -> None:\n    print(1)\n\ndef main() -> int noio:\n    emit()\n    return 0\n", "E_EFFECT_BOUND");
    try expectOutput("def main() -> int effects(output):\n    print(1)\n    return 0\n", "1\n");
    try expectOutput("def main() -> int noalloc:\n    print(1)\n    return 0\n", "1\n");
}

// spec: IO-5
test "IO-5 print rejects values without a Python rendering and shadowing restores the name" {
    const capability = "def main(fs: filesystem_cap) -> int:\n    print(fs)\n    return 0\n";
    try reject(capability, "E_IO_ARGUMENT");
    const shadow = "def print(value: int) -> int:\n    return value\n\ndef main() -> int:\n    return print(7)\n";
    var compilation = try language.Compilation.init(t.allocator, module, shadow);
    defer compilation.deinit();
    const result = try compilation.executeWithOptions(t.allocator, .{});
    try t.expectEqual(@as(i64, 7), result.value);
}

test "print discards output when the host supplies no writer and renders deep graphs" {
    var compilation = try language.Compilation.init(t.allocator, module, "def main() -> int:\n    print(\"quiet\")\n    return 5\n");
    defer compilation.deinit();
    const result = try compilation.executeWithOptions(t.allocator, .{});
    try t.expectEqual(@as(i64, 5), result.value);
}

test "render reports Unprintable for authority values that have no Python spelling" {
    var buffer: [64]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);
    const capability: language.vm.Value = .{ .capability = .{ .environment_capability = .{ .execution = 1 } } };
    try t.expectError(error.Unprintable, io_render.render(&writer, &.{}, capability, 0));
    try t.expect(!io_render.printable(.filesystem_cap, &.{}));
    try t.expect(io_render.printable(.i64, &.{}));
    try t.expectEqualStrings("Point", io_render.shortName("module::Point"));
}

// spec-case: IO-5
test "generic function bodies reject the reserved io builtins with a located diagnostic" {
    try reject("def show[T](value: T) -> int:\n    print(value)\n    return 0\n\ndef main() -> int:\n    return show(7)\n", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("def look[T](fs: filesystem_cap, value: T) -> int:\n    _ = exists(fs, \"x\")\n    return 0\n\ndef main(fs: filesystem_cap) -> int:\n    return look(fs, 7)\n", "E_GENERIC_BODY_UNSUPPORTED");
}

// spec: IO-6
test "IO-6 the native backend lowers print through generated per-type renderers" {
    const source =
        \\class Point:
        \\    x: int
        \\    y: float
        \\
        \\enum Colour { red, green }
        \\
        \\def main() -> int:
        \\    rows: dict[str, list[bytes]] = {"a": [b"\\x00"]}
        \\    found: Option[Point] = Some(Point(x=1, y=2.5))
        \\    print(rows, found, Colour.green, sep="-", end="!\\n")
        \\    print()
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, module, source);
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    for ([_][]const u8{ "myl_qbe_print_begin", "myl_qbe_print_finish", "myl_qbe_print_raw", "myl_print_dictionary", "myl_print_bytes", "myl_print_record", "myl_print_variant", "myl_print_float" }) |symbol| {
        try t.expect(std.mem.indexOf(u8, manifest, symbol) != null);
    }
    // Case spellings and field names travel in the generated renderers.
    try t.expect(std.mem.indexOf(u8, manifest, "\\\"Colour.green\\\"") != null);
    try t.expect(std.mem.indexOf(u8, manifest, "\\\"Some\\\"") != null);
}

// spec-case: IO-6
test "IO-6 a program that never prints carries no rendering runtime" {
    var compilation = try language.Compilation.init(t.allocator, module, "def main() -> int:\n    return 7\n");
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    try t.expect(std.mem.indexOf(u8, manifest, "native_print.h") == null);
}
