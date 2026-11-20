//! `out.print`: Python rendering of every ordinary value shape, `sep=`/`end=` keywords,
//! the `output` effect that `noio` withholds, and the native backend's rejection.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const io_render = @import("io_render.zig");

const module = "io-print.selka";

/// The program `text` returns normally having printed exactly `expected` (run with
/// the test's other programs).
fn expectOutput(programs: *native.Cases, text: []const u8, expected: []const u8) !void {
    try programs.prints(module, text, expected);
}

/// The program `text`, checked as an embedded project so it may import a module,
/// returns normally having printed exactly `expected`; run under the same default
/// options `native.Cases` uses.
fn expectProjectOutput(text: []const u8, expected: []const u8) !void {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var entry: Entry = .{ .text = text };
    var project: language.embedded_project.Program = undefined;
    try project.init(t.allocator, .{ .context = &entry, .read = Entry.read });
    defer project.deinit();
    const result = try native.run(&project.compilation);
    try t.expect(!result.trapped());
    try t.expectEqualStrings(expected, result.stdout);
}

fn reject(text: []const u8, code: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, module, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

// spec: IO-1
test "IO-1 print renders scalars, text, bytes and containers with Python spellings" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 42)\n    return 0\n", "42\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1, 2, 3)\n    return 0\n", "1 2 3\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out)\n    return 0\n", "\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, True, False, ())\n    return 0\n", "True False None\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1.5)\n    print(out, 3.0)\n    return 0\n", "1.5\n3.0\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"hi there\")\n    return 0\n", "hi there\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, b\"a\\n\\xff\")\n    return 0\n", "b'a\\n\\xff'\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, [1, 2, 3])\n    return 0\n", "[1, 2, 3]\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, [\"a\", \"b\"])\n    return 0\n", "['a', 'b']\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    mut counts = {\"a\": 1, \"b\": 2}\n    print(out, counts)\n    return 0\n", "{'a': 1, 'b': 2}\n");
    try programs.check();
}

// spec: STREAM-FUNCTIONS-1
test "STREAM-FUNCTIONS-1 the stream-first forms print, write and flush answer unit" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1, 2, sep=\"-\")\n    return 0\n", "1-2\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"a\", end=\"\")\n    print(out, \"b\")\n    return 0\n", "ab\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    write(out, \"raw\")\n    write(out, b\"bytes\")\n    flush(out)\n    print(out, \"!\")\n    return 0\n", "rawbytes!\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out)\n    write(out, \"tail\\n\")\n    flush(out)\n    return 0\n", "\ntail\n");
    try programs.check();
}

// spec: STREAM-FUNCTIONS-1
test "STREAM-FUNCTIONS-1 arity and a unit result are checked" {
    try reject("func main(out: Stream) -> int:\n    flush(out, out)\n    return 0\n", "E_ARITY");
    try reject("func main(out: Stream) -> int:\n    write(out, 1)\n    return 0\n", "E_TYPE");
    try reject("func main(out: Stream) -> int:\n    const count = write(out, \"x\")\n    return count\n", "E_TYPE");
}

// spec: IO-2
test "IO-2 print renders records, enums, unions and checked results by name" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    const record = "record Point:\n    x: int\n    y: int\n\nfunc main(out: Stream) -> int:\n    print(out, Point(x=1, y=2))\n    return 0\n";
    try expectOutput(&programs, record, "Point(x=1, y=2)\n");
    const colours = "enum Colour:\n    red\n    green\n\n\nfunc main(out: Stream) -> int:\n    print(out, Colour.green)\n    return 0\n";
    try expectOutput(&programs, colours, "Colour.green\n");
    const shape = "enum Shape:\n    dot(value: i64)\n    gap\n\n\nfunc main(out: Stream) -> int:\n    print(out, Shape.dot(value=7))\n    print(out, Shape.gap)\n    return 0\n";
    try expectOutput(&programs, shape, "Shape.dot(value=7)\nShape.gap\n");
    const checked = "func pick(n: int) -> int fails str:\n    if n < 0:\n        fail \"negative\"\n    return n\n\nfunc main(out: Stream) -> int:\n    print(out, pick(3))\n    print(out, pick(-1))\n    return 0\n";
    try expectOutput(&programs, checked, "Ok(3)\nErr('negative')\n");
    const option = "func main(out: Stream) -> int:\n    mut found: int? = Some(4)\n    mut missing: int? = None\n    print(out, found, missing)\n    return 0\n";
    try expectOutput(&programs, option, "Some(4) None\n");
    try programs.check();
}

// FR-421: a user enum's nullary `none` is `Kind.none`, never Option's `None`, and its
// `some` stays qualified too; the builtin Option keeps the prelude spelling.
test "IO-2 print qualifies a user enum case spelled like a prelude case" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    const kind = "enum Kind:\n    none\n    some(value: int)\n\n\nfunc main(out: Stream) -> int:\n    print(out, Kind.none)\n    print(out, Kind.some(value=1))\n    const absent: int? = None\n    print(out, absent)\n    return 0\n";
    try expectOutput(&programs, kind, "Kind.none\nKind.some(value=1)\nNone\n");
    try programs.check();
}

// spec: IO-3
test "IO-3 print accepts sep and end keyword arguments and rejects other keywords" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1, 2, sep=\"-\")\n    return 0\n", "1-2\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1, end=\"\")\n    print(out, 2)\n    return 0\n", "12\n");
    // The result line follows the guest's own bytes, so a run ends with a newline.
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1, 2, sep=\"\", end=\"!\")\n    print(out)\n    return 0\n", "12!\n");
    try reject("func main(out: Stream) -> int:\n    print(out, 1, flush=True)\n    return 0\n", "E_IO_ARGUMENT");
    try reject("func main(out: Stream) -> int:\n    print(out, 1, sep=\"-\", sep=\",\")\n    return 0\n", "E_IO_ARGUMENT");
    try reject("func main(out: Stream) -> int:\n    print(out, sep=\"-\", 1)\n    return 0\n", "E_CALL_ARGUMENT");
    try reject("func main(out: Stream) -> int:\n    print(out, 1, sep=2)\n    return 0\n", "E_TYPE");
    try programs.check();
}

// spec: IO-4
test "IO-4 print contributes the output effect that noio withholds" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    try reject("func main(out: Stream) -> int noio:\n    print(out, 1)\n    return 0\n", "E_EFFECTS_REMOVED");
    try reject("func emit(out: Stream) -> Unit:\n    print(out, 1)\n\nfunc main(out: Stream) -> int noio:\n    emit(out)\n    return 0\n", "E_EFFECTS_REMOVED");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, 1)\n    return 0\n", "1\n");
    try expectOutput(&programs, "@noalloc\nfunc main(out: Stream) -> int:\n    print(out, 1)\n    return 0\n", "1\n");
    try programs.check();
}

// spec: IO-5
test "IO-5 print rejects values without a Python rendering, and a declared print called bare is refused" {
    const capability = "func main(fs: Filesystem, out: Stream) -> int:\n    print(out, fs)\n    return 0\n";
    try reject(capability, "E_IO_ARGUMENT");
    // A bare call of a prelude name is always the builtin (W6), so a module `print` called bare no longer shadows it.
    const shadow = "func print(value: int) -> int:\n    return value\n\nfunc main() -> int:\n    return print(7)\n";
    try reject(shadow, "E_BUILTIN_FUNCTION_NAME");
}

test "render names printable types and shortens qualified record names" {
    try t.expect(!io_render.printable(.filesystem_cap, &.{}));
    try t.expect(io_render.printable(.i64, &.{}));
    try t.expectEqualStrings("Point", io_render.shortName("module::Point"));
}

// spec-case: IO-5
test "generic function bodies reject the reserved io builtins with a located diagnostic" {
    try reject("func show[T](value: T) -> int:\n    print(value)\n    return 0\n\nfunc main() -> int:\n    return show(7)\n", "E_GENERIC_BODY_UNSUPPORTED");
    try reject("func look[T](fs: Filesystem, value: T) -> int:\n    _ = exists(fs, \"x\")\n    return 0\n\nfunc main(fs: Filesystem) -> int:\n    return look(fs, 7)\n", "E_GENERIC_BODY_UNSUPPORTED");
}

// spec: IO-15
test "IO-15 a Stream held in a record field is bound to a name, then printed and written" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    const source =
        \\record Sink:
        \\    stream: Stream
        \\    label: str
        \\
        \\record Pair:
        \\    first: Sink
        \\    count: int
        \\
        \\func emit(sink: Sink) -> int:
        \\    const held = sink.stream
        \\    write(held, b"hello\n")
        \\    mut written = len(b"hello\n")
        \\    print(held, sink.label, written)
        \\    return written
        \\
        \\func main(out: Stream) -> int:
        \\    mut pair = Pair(first=Sink(stream=out, label="n"), count=1)
        \\    const first = pair.first.stream
        \\    write(first, "x\n")
        \\    return emit(pair.first) - 6
    ;
    try expectOutput(&programs, source, "x\nhello\nn 6\n");
    try reject("record Sink:\n    stream: Stream\n\nfunc main(out: Stream) -> int:\n    mut sink = Sink(stream=out)\n    sink.stream.flush()\n    return 0\n", "E_COLLECTION_METHOD");
    try programs.check();
}

// spec: IO-15
test "IO-15 a Stream held in a record field is printed, written and flushed as the field, with no name bound first" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    const source =
        \\record Sink:
        \\    stream: Stream
        \\    label: str
        \\
        \\record Pair:
        \\    first: Sink
        \\    count: int
        \\
        \\func emit(sink: Sink) -> int:
        \\    write(sink.stream, b"hello\n")
        \\    print(sink.stream, sink.label, 7, sep="-", end="!\n")
        \\    flush(sink.stream)
        \\    return 1
        \\
        \\func deep(mut pair: Pair, n: int):
        \\    pair.count += n
        \\    print(pair.first.stream, "deep", pair.count)
        \\
        \\func main(out: Stream) -> int:
        \\    mut pair = Pair(first=Sink(stream=out, label="n"), count=1)
        \\    deep(mut pair, 2)
        \\    return emit(pair.first) - 1
    ;
    try expectOutput(&programs, source, "deep 3\nhello\nn-7!\n");
    // A field that is no Stream keeps the diagnostic every other first argument of a bare print gets.
    try reject("record Sink:\n    stream: Stream\n    label: str\n\nfunc main(out: Stream) -> int:\n    const sink = Sink(stream=out, label=\"n\")\n    print(sink.label, 1)\n    return 0\n", "E_OUTPUT_CAPABILITY");
    try reject("record Sink:\n    stream: Stream\n\nfunc main(out: Stream) -> int:\n    const sink = Sink(stream=out)\n    print(sink.absent, 1)\n    return 0\n", "E_UNKNOWN_FIELD");
    try programs.check();
}

test "QBE-BULK-TEXT-1 raw top-level text is encoded into the line buffer in one pass" {
    var programs: native.Cases = .init(t.allocator);
    defer programs.deinit();
    // Empty text writes nothing and still ends the line.
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"\")\n    return 0\n", "\n");
    // ASCII past the buffer's first 64-byte capacity, so the reserve path runs.
    const long: [70]u8 = @splat('a');
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"" ++ long ++ "\")\n    return 0\n", long ++ "\n");
    // Two-, three- and four-byte scalars widen exactly as the per-scalar encoder
    // did, and a line that grows across several values keeps every byte.
    const wide = "h\u{00e9}\u{2192}\u{1F600}";
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"h\\u00e9\\u2192\\U0001F600\")\n    return 0\n", wide ++ "\n");
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"" ++ long ++ "\", \"h\\u00e9\\u2192\\U0001F600\", sep=\"\")\n    return 0\n", long ++ wide ++ "\n");
    // Top-level text is raw: quotes, backslashes, tabs, newlines and NUL scalars
    // reach the stream unchanged.
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, \"a'b\\\\c\\td\\ne\\0f\")\n    return 0\n", "a'b\\c\td\ne\x00f\n");
    // Inside a container the same text is still repr-quoted, with the quote rule
    // choosing `"` for a value that holds an apostrophe and no `"` (FR-418).
    try expectOutput(&programs, "func main(out: Stream) -> int:\n    print(out, [\"a'b\", \"c\\nd\"])\n    return 0\n", "[\"a'b\", 'c\\nd']\n");
    // Text built at run time — joined, sliced and replaced, so heap strings
    // rather than literal images — takes the same path. It imports `strings`,
    // so it runs as an embedded project rather than a single unit.
    const built = "import strings\n\nfunc main(out: Stream) -> int:\n    mut text = strings.join([\"a\", \"b\", \"c\"], \"-\")\n" ++
        "    print(out, strings.char_slice(text, 1, 4))\n    print(out, strings.replace(text, \"-\", \"\\u00e9\"))\n    return 0\n";
    try expectProjectOutput(built, "-b-\na\u{00e9}b\u{00e9}c\n");
    // `stream.write` is the other raw-text caller and returns the scalar count.
    const write = "func show(log: Stream) -> int:\n    write(log, \"h\\u00e9\\u2192\\U0001F600\")\n    return 4\n\nfunc main(out: Stream) -> int:\n    print(out, show(out))\n    return 0\n";
    try expectOutput(&programs, write, wide ++ "4\n");
    try programs.check();
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

/// `runStreams` for a program that imports a standard module: the source is an
/// embedded project, since a single unit cannot carry an `import`.
fn runStreamsProject(text: []const u8) !struct { stdout: []const u8, stderr: []const u8 } {
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return a.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    var entry: Entry = .{ .text = text };
    var project: language.embedded_project.Program = undefined;
    try project.init(t.allocator, .{ .context = &entry, .read = Entry.read });
    defer project.deinit();
    const outcome = native.run(&project.compilation) catch |err| {
        @import("diagnostics_test.zig").report(project.compilation.diagnostics.items.items);
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
    const both = "func main(out: Stream, err: Stream) -> int:\n    print(out, \"out\")\n    print(err, \"err\")\n    return 0\n";
    const result = try runStreams(both);
    try t.expectEqualStrings("out\n", result.stdout);
    try t.expectEqualStrings("err\n", result.stderr);
}

// spec-case: STREAM-CAPABILITY-1
test "STREAM-CAPABILITY a helper takes any Stream name and writes to it" {
    const source = "func show(log: Stream) -> int:\n    write(log, \"abcd\")\n    return 4\n\nfunc main(out: Stream, err: Stream) -> int:\n    print(out, show(out))\n    print(err, show(err))\n    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("abcd4\n", result.stdout);
    try t.expectEqualStrings("abcd4\n", result.stderr);
}

// spec: STREAM-BYTES-1
test "STREAM-BYTES raw writes preserve binary octets and return byte counts" {
    const source =
        "func send(log: Stream, data: bytes) -> int:\n" ++
        "    write(log, data)\n" ++
        "    return len(data)\n" ++
        "\n" ++
        "func main(out: Stream, err: Stream) -> int:\n" ++
        "    print(out, send(out, b\"A\\0\\xff\"))\n" ++
        "    print(err, send(err, b\"B\\0\\xff\"))\n" ++
        "    print(out, send(out, b\"\"))\n" ++
        "    write(out, \"λ\")\n" ++
        "    write(out, b\"λ\")\n" ++
        "    print(out, 1, len(b\"λ\"))\n" ++
        "    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("A\x00\xff3\n0\nλλ1 2\n", result.stdout);
    try t.expectEqualStrings("B\x00\xff3\n", result.stderr);
}

// spec-case: STREAM-BYTES-1
test "STREAM-BYTES rejects non byte values and preserves the output effect" {
    try reject("func main(out: Stream) -> int:\n    write(out, 42)\n    return 0\n", "E_TYPE");
    try reject("func main(out: Stream) -> int noio:\n    write(out, b\"x\")\n    return 0\n", "E_EFFECTS_REMOVED");
}

// spec-case: STREAM-BYTES-1
test "STREAM-BYTES traps R_OUTPUT when the native byte sink refuses output" {
    var compilation = try language.Compilation.init(t.allocator, module, "func main(out: Stream) -> int:\n    write(out, b\"raw\\0\\xff\")\n    return 0\n");
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
    try reject("func main(log: Stream) -> int:\n    return 0\n", "E_MAIN");
}

// spec-case: STREAM-CAPABILITY-1
test "STREAM-CAPABILITY bare print and eprint need a Stream and name the fix" {
    const bare = "func main() -> int:\n    print(1)\n    return 0\n";
    var compilation = try language.Compilation.init(t.allocator, module, bare);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_OUTPUT_CAPABILITY", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, "add `out: Stream`") != null);
    try reject("func main() -> int:\n    eprint(1)\n    return 0\n", "E_OUTPUT_CAPABILITY");
}

// spec: DEBUG-LINE-1
test "DEBUG-LINE-1 debug writes to stderr and contributes no output effect" {
    const source = "func main() -> int:\n    debug(\"trace\")\n    return 0\n";
    const result = try runStreams(source);
    try t.expectEqualStrings("", result.stdout);
    try t.expectEqualStrings("trace\n", result.stderr);
}

// spec: STREAM-BYTES-2
test "STREAM-BYTES-2 a mutable buffer writes its own octets without a snapshot" {
    const source =
        "import buffers\n\nfunc emit(log: Stream) -> int:\n" ++
        "    mut empty: int[] = []\n" ++
        "    mut buffer = byte_buffer(empty)\n" ++
        "    if not buffers.append_range(mut buffer, b\"head\\0\\xff\", 0, 6):\n" ++
        "        return 0 - 1\n" ++
        "    buffers.append_float(mut buffer, 2.5)\n" ++
        "    write(log, buffer)\n" ++
        "    mut written = len(buffer)\n" ++
        "    if not buffers.append_byte(mut buffer, 33):\n" ++
        "        return 0 - 1\n" ++
        "    write(log, buffer)\n" ++
        "    return written\n" ++
        "\n" ++
        "func main(out: Stream) -> int:\n" ++
        "    mut count = emit(out)\n" ++
        "    print(out, count)\n" ++
        "    return 0\n";
    const result = try runStreamsProject(source);
    try t.expectEqualStrings("head\x00\xff2.5head\x00\xff2.5!9\n", result.stdout);
}

// spec-case: STREAM-BYTES-2
test "STREAM-BYTES-2 a buffer write keeps the output effect of the bytes it writes" {
    try reject(
        "func main(out: Stream) -> int noio:\n" ++
            "    mut empty: int[] = []\n" ++
            "    mut buffer = byte_buffer(empty)\n" ++
            "    write(out, buffer)\n    return 0\n",
        "E_EFFECTS_REMOVED",
    );
}

// spec-case: VALUE-SEMANTICS-14
test "VALUE-SEMANTICS-14 print preserves copied operands across later writes" {
    const program =
        \\import lists
        \\
        \\
        \\func push(mut xs: int[]) -> int:
        \\    append(mut xs, 9)
        \\    return 1
        \\
        \\func main(out: Stream) -> int:
        \\    mut zs = [1, 2, 3]
        \\    const before_push = copy(zs)
        \\    print(out, before_push, push(mut zs), zs)
        \\    const before_pop = copy(zs)
        \\    print(out, before_pop, lists.pop(mut zs))
        \\    return 0
        \\
    ;
    const expected = "[1, 2, 3] 1 [1, 2, 3, 9]\n[1, 2, 3, 9] 9\n";
    try expectProjectOutput(program, expected);
}
