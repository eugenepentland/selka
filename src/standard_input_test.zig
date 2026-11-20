//! The `Input` capability's checking: what the methods accept, what they refuse and how, and that
//! an ordinary program cannot reach the in-memory constructor.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const module = "input.selka";

/// Check `source` as an ordinary program and answer the first diagnostic's code, or "" when it checks.
fn codeOf(source: []const u8) ![]const u8 {
    var c = try language.Compilation.init(t.allocator, module, source);
    defer c.deinit();
    c.check() catch |err| switch (err) {
        error.SourceError => return t.allocator.dupe(u8, c.diagnostics.items[0].code),
        else => return err,
    };
    return t.allocator.dupe(u8, "");
}

fn expectCode(source: []const u8, code: []const u8) !void {
    const found = try codeOf(source);
    defer t.allocator.free(found);
    try t.expectEqualStrings(code, found);
}

test "an Input parameter reads with every method and checks clean" {
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    mut buffer = byte_buffer([])
        \\    const head = stdin.read(4)
        \\    const frame = stdin.read_exact(2)
        \\    const line = stdin.read_line()
        \\    const count = stdin.read_into(mut buffer, 8)
        \\    print(out, len(head), frame is None, line is None, count)
        \\    return 0
    , "");
}

test "an Input method refuses a wrong argument type, a wrong count and an unknown method" {
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    print(out, stdin.read("many"))
        \\    return 0
    , "E_TYPE");
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    print(out, stdin.read_line(3))
        \\    return 0
    , "E_ARITY");
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    print(out, stdin.poll())
        \\    return 0
    , "E_UNKNOWN_TYPE");
}

test "read_into needs the mut marker, a writable byte_buffer named by a local, and an int count" {
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    mut buffer = byte_buffer([])
        \\    print(out, stdin.read_into(buffer, 4))
        \\    return 0
    , "E_MUTATION_MARKER");
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    const buffer = byte_buffer([])
        \\    print(out, stdin.read_into(mut buffer, 4))
        \\    return 0
    , "E_IMMUTABLE");
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    mut text = "abc"
        \\    print(out, stdin.read_into(mut text, 4))
        \\    return 0
    , "E_TYPE");
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    mut buffer = byte_buffer([])
        \\    print(out, stdin.read_into(mut buffer, "four"))
        \\    return 0
    , "E_TYPE");
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    mut buffer = byte_buffer([])
        \\    print(out, stdin.read_into(mut buffer))
        \\    return 0
    , "E_ARITY");
}

test "an entry point takes at most one Input" {
    try expectCode(
        \\func main(first: Input, second: Input, out: Stream) -> int:
        \\    print(out, first.read(1), second.read(1))
        \\    return 0
    , "E_MAIN");
}

test "an ordinary program cannot spell the in-memory input constructor" {
    try expectCode(
        \\func main(out: Stream) -> int:
        \\    const stdin = __stand_in[Input](b"abc")
        \\    print(out, stdin.read(1))
        \\    return 0
    , "E_INTERNAL_NAME");
}

test "a declared type named Input keeps its own meaning" {
    try expectCode(
        \\record Input:
        \\    text: str
        \\
        \\
        \\func main(out: Stream) -> int:
        \\    const input = Input(text="x")
        \\    print(out, input.text)
        \\    return 0
    , "");
}

test "an Input is not a resource a with scope can open" {
    try expectCode(
        \\func main(stdin: Input, out: Stream) -> int:
        \\    with stdin as f:
        \\        print(out, 1)
        \\    return 0
    , "E_TYPE");
}

test "a generic function body cannot read an Input" {
    try expectCode(
        \\func my_take[T](stdin: Input, value: T) -> int:
        \\    return len(stdin.read(3))
        \\
        \\
        \\func main(stdin: Input, out: Stream) -> int:
        \\    print(out, my_take(stdin, 1))
        \\    return 0
    , "E_GENERIC_BODY_UNSUPPORTED");
}
