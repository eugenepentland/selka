//! `out.print`: Python rendering of every ordinary value shape, `sep=`/`end=` keywords,
//! the `output` effect that `noio` withholds, and the native backend's rejection.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const io_render = @import("io_render.zig");

const module = "io-print.my";

/// Execute one program natively and return everything it wrote to standard output.
fn output(text: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    const outcome = native.run(&compilation) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    return outcome.stdout;
}

fn expectOutput(text: []const u8, expected: []const u8) !void {
    try t.expectEqualStrings(expected, try output(text));
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: IO-1
test "IO-1 print renders scalars, text, bytes and containers with Python spellings" {
    try expectOutput("def main(out: Stream) -> int:\n    out.print(42)\n    return 0\n", "42\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(1, 2, 3)\n    return 0\n", "1 2 3\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print()\n    return 0\n", "\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(True, False, None)\n    return 0\n", "True False None\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(1.5)\n    out.print(3.0)\n    return 0\n", "1.5\n3.0\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(\"hi there\")\n    return 0\n", "hi there\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(b\"a\\n\\xff\")\n    return 0\n", "b'a\\n\\xff'\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print([1, 2, 3])\n    return 0\n", "[1, 2, 3]\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print([\"a\", \"b\"])\n    return 0\n", "['a', 'b']\n");
    try expectOutput("def main(out: Stream) -> int:\n    counts = {\"a\": 1, \"b\": 2}\n    out.print(counts)\n    return 0\n", "{'a': 1, 'b': 2}\n");
}

// spec: IO-2
test "IO-2 print renders records, enums, unions and checked results by name" {
    const record = "record Point:\n    x: int\n    y: int\n\ndef main(out: Stream) -> int:\n    out.print(Point(x=1, y=2))\n    return 0\n";
    try expectOutput(record, "Point(x=1, y=2)\n");
    const colours = "enum Colour:\n    red,\n    green\n\n\ndef main(out: Stream) -> int:\n    out.print(Colour.green)\n    return 0\n";
    try expectOutput(colours, "Colour.green\n");
    const shape = "union Shape:\n    dot: i64,\n    gap\n\n\ndef main(out: Stream) -> int:\n    out.print(Shape.dot(7))\n    out.print(Shape.gap)\n    return 0\n";
    try expectOutput(shape, "Shape.dot(7)\nShape.gap\n");
    const checked = "def pick(n: int) -> Result[int, str]:\n    if n < 0:\n        return Err(\"negative\")\n    return Ok(n)\n\ndef main(out: Stream) -> int:\n    out.print(pick(3))\n    out.print(pick(-1))\n    return 0\n";
    try expectOutput(checked, "Ok(3)\nErr('negative')\n");
    const option = "def main(out: Stream) -> int:\n    found: Option[int] = Some(4)\n    missing: Option[int] = None\n    out.print(found, missing)\n    return 0\n";
    try expectOutput(option, "Some(4) None\n");
}

// spec: IO-3
test "IO-3 print accepts sep and end keyword arguments and rejects other keywords" {
    try expectOutput("def main(out: Stream) -> int:\n    out.print(1, 2, sep=\"-\")\n    return 0\n", "1-2\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(1, end=\"\")\n    out.print(2)\n    return 0\n", "12\n");
    // The result line follows the guest's own bytes, so a run ends with a newline.
    try expectOutput("def main(out: Stream) -> int:\n    out.print(1, 2, sep=\"\", end=\"!\")\n    out.print()\n    return 0\n", "12!\n");
    try reject("def main(out: Stream) -> int:\n    out.print(1, flush=True)\n    return 0\n", "E_IO_ARGUMENT");
    try reject("def main(out: Stream) -> int:\n    out.print(1, sep=\"-\", sep=\",\")\n    return 0\n", "E_IO_ARGUMENT");
    try reject("def main(out: Stream) -> int:\n    out.print(sep=\"-\", 1)\n    return 0\n", "E_CALL_ARGUMENT");
    try reject("def main(out: Stream) -> int:\n    out.print(1, sep=2)\n    return 0\n", "E_TYPE");
}

// spec: IO-4
test "IO-4 print contributes the output effect that noio withholds" {
    try reject("def main(out: Stream) -> int noio:\n    out.print(1)\n    return 0\n", "E_EFFECT_BOUND");
    try reject("def emit(out: Stream) -> None:\n    out.print(1)\n\ndef main(out: Stream) -> int noio:\n    emit(out)\n    return 0\n", "E_EFFECT_BOUND");
    try expectOutput("def main(out: Stream) -> int effects(output):\n    out.print(1)\n    return 0\n", "1\n");
    try expectOutput("def main(out: Stream) -> int noalloc:\n    out.print(1)\n    return 0\n", "1\n");
}

// spec: IO-5
test "IO-5 print rejects values without a Python rendering and shadowing restores the name" {
    const capability = "def main(fs: Filesystem, out: Stream) -> int:\n    out.print(fs)\n    return 0\n";
    try reject(capability, "E_IO_ARGUMENT");
    const shadow = "def print(value: int) -> int:\n    return value\n\ndef main() -> int:\n    return print(7)\n";
    var compilation = try language.Compilation.init(t.allocator, module, shadow);
    defer compilation.deinit();
    const result = try native.run(&compilation);
    try t.expectEqual(@as(i64, 7), result.value);
    try t.expectEqualStrings("", result.stdout);
}

test "render names printable types and shortens qualified record names" {
    try t.expect(!io_render.printable(.filesystem_cap, &.{}));
    try t.expect(io_render.printable(.i64, &.{}));
    try t.expectEqualStrings("Point", io_render.shortName("module::Point"));
}

// spec-case: IO-5
test "generic function bodies reject the reserved io builtins with a located diagnostic" {
    try reject("def show[T](value: T) -> int:\n    print(value)\n    return 0\n\ndef main() -> int:\n    return show(7)\n", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("def look[T](fs: Filesystem, value: T) -> int:\n    _ = exists(fs, \"x\")\n    return 0\n\ndef main(fs: Filesystem) -> int:\n    return look(fs, 7)\n", "E_GENERIC_BODY_UNSUPPORTED");
}

// spec: IO-15
test "IO-15 print and write work on a Stream held in a record field" {
    const source =
        \\record Sink:
        \\    stream: Stream
        \\    label: str
        \\
        \\record Pair:
        \\    first: Sink
        \\    count: int
        \\
        \\def emit(sink: Sink) -> int:
        \\    written = sink.stream.write(b"hello\n")
        \\    sink.stream.print(sink.label, written)
        \\    return written
        \\
        \\def main(out: Stream) -> int:
        \\    pair = Pair(first=Sink(stream=out, label="n"), count=1)
        \\    _ = pair.first.stream.write("x\n")
        \\    return emit(pair.first) - 6
    ;
    try expectOutput(source, "x\nhello\nn 6\n");
    try reject("record Sink:\n    stream: Stream\n\ndef main(out: Stream) -> int:\n    sink = Sink(stream=out)\n    sink.stream.flush()\n    return 0\n", "E_COLLECTION_METHOD");
}

test "QBE-BULK-TEXT-1 raw top-level text is encoded into the line buffer in one pass" {
    // Empty text writes nothing and still ends the line.
    try expectOutput("def main(out: Stream) -> int:\n    out.print(\"\")\n    return 0\n", "\n");
    // ASCII past the buffer's first 64-byte capacity, so the reserve path runs.
    const long: [70]u8 = @splat('a');
    try expectOutput("def main(out: Stream) -> int:\n    out.print(\"" ++ long ++ "\")\n    return 0\n", long ++ "\n");
    // Two-, three- and four-byte scalars widen exactly as the per-scalar encoder
    // did, and a line that grows across several values keeps every byte.
    const wide = "h\u{00e9}\u{2192}\u{1F600}";
    try expectOutput("def main(out: Stream) -> int:\n    out.print(\"h\\u00e9\\u2192\\U0001F600\")\n    return 0\n", wide ++ "\n");
    try expectOutput("def main(out: Stream) -> int:\n    out.print(\"" ++ long ++ "\", \"h\\u00e9\\u2192\\U0001F600\", sep=\"\")\n    return 0\n", long ++ wide ++ "\n");
    // Top-level text is raw: quotes, backslashes, tabs, newlines and NUL scalars
    // reach the stream unchanged.
    try expectOutput("def main(out: Stream) -> int:\n    out.print(\"a'b\\\\c\\td\\ne\\0f\")\n    return 0\n", "a'b\\c\td\ne\x00f\n");
    // Inside a container the same text is still repr-quoted and escaped.
    try expectOutput("def main(out: Stream) -> int:\n    out.print([\"a'b\", \"c\\nd\"])\n    return 0\n", "['a\\'b', 'c\\nd']\n");
    // Text built at run time — joined, sliced and replaced, so heap strings
    // rather than literal images — takes the same path.
    const built = "def main(out: Stream) -> int:\n    text = \"-\".join([\"a\", \"b\", \"c\"])\n    out.print(text[1:4])\n    out.print(text.replace(\"-\", \"\\u00e9\"))\n    return 0\n";
    try expectOutput(built, "-b-\na\u{00e9}b\u{00e9}c\n");
    // `stream.write` is the other raw-text caller and returns the scalar count.
    const write = "def show(log: Stream) -> int:\n    return log.write(\"h\\u00e9\\u2192\\U0001F600\")\n\ndef main(out: Stream) -> int:\n    out.print(show(out))\n    return 0\n";
    try expectOutput(write, wide ++ "4\n");
}

/// Execute one program natively and return both standard streams. A guest that
/// writes to stderr takes the runner's trap path, so its stdout still carries
/// the `--print-result` line; strip that final line here.
fn runStreams(text: []const u8) !struct { stdout: []const u8, stderr: []const u8 } {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    const outcome = native.run(&compilation) catch |err| {
        @import("diagnostics_test.zig").report(compilation.diagnostics.items);
        return err;
    };
    try t.expectEqualStrings("", outcome.trap.code);
    var stdout = outcome.stdout;
    if (outcome.failed) {
        const body = if (stdout.len != 0 and stdout[stdout.len - 1] == '\n') stdout[0 .. stdout.len - 1] else stdout;
        const start = if (std.mem.lastIndexOfScalar(u8, body, '\n')) |index| index + 1 else 0;
        stdout = if (start == 0) "" else stdout[0..start];
    }
    return .{ .stdout = stdout, .stderr = outcome.stderr };
}

// spec: STREAM-CAPABILITY-1
test "STREAM-CAPABILITY out.print and err.print route a Stream receiver to its fd" {
    const both = "def main(out: Stream, err: Stream) -> int:\n    out.print(\"out\")\n    err.print(\"err\")\n    return 0\n";
    const result = try runStreams(both);
    try t.expectEqualStrings("out\n", result.stdout);
    try t.expectEqualStrings("err\n", result.stderr);
}

// spec-case: STREAM-CAPABILITY-1
test "STREAM-CAPABILITY a helper takes any Stream name and stream.write returns its count" {
    const source = "def show(log: Stream) -> int:\n    return log.write(\"abcd\")\n\ndef main(out: Stream, err: Stream) -> int:\n    out.print(show(out))\n    err.print(show(err))\n    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("abcd4\n", result.stdout);
    try t.expectEqualStrings("abcd4\n", result.stderr);
}

// spec: STREAM-BYTES-1
test "STREAM-BYTES raw writes preserve binary octets and return byte counts" {
    const source =
        "def send(log: Stream, data: bytes) -> int:\n    return log.write(data)\n\n" ++
        "def main(out: Stream, err: Stream) -> int:\n" ++
        "    out.print(send(out, b\"A\\0\\xff\"))\n" ++
        "    err.print(send(err, b\"B\\0\\xff\"))\n" ++
        "    out.print(send(out, b\"\"))\n" ++
        "    out.print(out.write(\"λ\"), out.write(b\"λ\"))\n" ++
        "    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("A\x00\xff3\n0\nλλ1 2\n", result.stdout);
    try t.expectEqualStrings("B\x00\xff3\n", result.stderr);
}

// spec-case: STREAM-BYTES-1
test "STREAM-BYTES rejects non byte values and preserves the output effect" {
    try reject("def main(out: Stream) -> int:\n    return out.write(42)\n", "E_TYPE");
    try reject("def main(out: Stream) -> int noio:\n    return out.write(b\"x\")\n", "E_EFFECT_BOUND");
}

// spec-case: STREAM-BYTES-1
test "STREAM-BYTES traps R_OUTPUT when the native byte sink refuses output" {
    var compilation = try language.Compilation.init(t.allocator, module, "def main(out: Stream) -> int:\n    _ = out.write(b\"raw\\0\\xff\")\n    return 0\n");
    defer compilation.deinit();
    const executable = try native.executable(&compilation);
    const full = std.Io.Dir.openFileAbsolute(t.io, "/dev/full", .{ .mode = .write_only }) catch
        return error.SkipZigTest;
    defer full.close(t.io);
    var child = try std.process.spawn(t.io, .{
        .argv = &.{executable},
        .stdout = .{ .file = full },
        .stderr = .pipe,
    });
    var buffer: [4096]u8 = undefined;
    var reader = child.stderr.?.readerStreaming(t.io, &buffer);
    const diagnostic = try reader.interface.allocRemaining(t.allocator, .limited(64 * 1024));
    defer t.allocator.free(diagnostic);
    const term = try child.wait(t.io);
    try t.expect(term == .exited and term.exited != 0);
    try t.expect(std.mem.indexOf(u8, diagnostic, "R_OUTPUT") != null);
}

// spec-case: STREAM-CAPABILITY-1
test "STREAM-CAPABILITY entry Stream parameters must be named out or err" {
    try reject("def main(log: Stream) -> int:\n    return 0\n", "E_MAIN");
}

// spec-case: STREAM-CAPABILITY-1
test "STREAM-CAPABILITY bare print and eprint need a Stream and name the fix" {
    const bare = "def main() -> int:\n    print(1)\n    return 0\n";
    var compilation = try language.Compilation.init(t.allocator, module, bare);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_OUTPUT_CAPABILITY", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, "add `out: Stream`") != null);
    try reject("def main() -> int:\n    eprint(1)\n    return 0\n", "E_OUTPUT_CAPABILITY");
}

// spec: DEBUG-LINE-1
test "DEBUG-LINE-1 debug writes to stderr and contributes no output effect" {
    const source = "def main() -> int noio:\n    debug(\"trace\")\n    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("", result.stdout);
    try t.expectEqualStrings("trace\n", result.stderr);
}

// spec: STREAM-BYTES-2
test "STREAM-BYTES-2 a mutable buffer writes its own octets without a snapshot" {
    const source =
        "def emit(log: Stream) -> int:\n" ++
        "    empty: list[int] = []\n" ++
        "    buffer = byte_buffer(empty)\n" ++
        "    if not buffer.append_range(b\"head\\0\\xff\", 0, 6):\n" ++
        "        return 0 - 1\n" ++
        "    if not buffer.append_float(2.5):\n" ++
        "        return 0 - 1\n" ++
        "    written = log.write(buffer)\n" ++
        "    if not buffer.append_byte(33):\n" ++
        "        return 0 - 1\n" ++
        "    _ = log.write(buffer)\n" ++
        "    return written\n" ++
        "\n" ++
        "def main(out: Stream) -> int:\n" ++
        "    count = emit(out)\n" ++
        "    out.print(count)\n" ++
        "    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("head\x00\xff2.5head\x00\xff2.5!9\n", result.stdout);
}

// spec-case: STREAM-BYTES-2
test "STREAM-BYTES-2 a buffer write keeps the output effect of the bytes it writes" {
    try reject(
        "def main(out: Stream) -> int noio:\n" ++
            "    empty: list[int] = []\n" ++
            "    buffer = byte_buffer(empty)\n" ++
            "    return out.write(buffer)\n",
        "E_EFFECT_BOUND",
    );
}

// spec-case: VALUE-SEMANTICS-14
test "VALUE-SEMANTICS-14 print renders a lent operand as it was before a later operand writes it" {
    const program = "def push(xs: mut list[int]) -> int:\n    xs.append(9)\n    return 1\n\ndef main(out: Stream) -> int:\n    zs = [1, 2, 3]\n    out.print(zs, push(mut zs), zs)\n    out.print(zs, zs.pop())\n    return 0\n";
    const expected = "[1, 2, 3] 1 [1, 2, 3, 9]\n[1, 2, 3, 9] 9\n";
    try expectOutput(program, expected);
}
