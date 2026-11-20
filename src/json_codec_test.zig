//! `json.encode` and `json.decode` (CODEC-1, step 1): what the `codec` bound refuses at check time, with the field path
//! of the part that has no plain form, and that a decoded record that breaks its `@invariant` fails, never traps. The values, the
//! forms and every runtime refusal are guest tests in `tests/lang/json_codec.selka` and `tests/lang/json_codec_python_vectors.selka`.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const codec_form = @import("codec_form.zig");

/// Check `text` and require its first diagnostic to be `E_NO_CODEC` with a message holding every one of `pieces`.
fn refusedWith(text: []const u8, pieces: []const []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(), text);
    try t.expect(!checked.passed);
    try t.expectEqualStrings(codec_form.code, checked.diagnostics[0].code);
    for (pieces) |piece| try t.expect(std.mem.indexOf(u8, checked.diagnostics[0].message, piece) != null);
}

const head =
    \\import json
    \\
    \\
;

test "json codec: a function field is refused at the call, naming its path" {
    try refusedWith(head ++
        \\func twice(n: int) -> int:
        \\    return n * 2
        \\
        \\record Job:
        \\    name: str
        \\    run: func(int) -> int
        \\
        \\record Queue:
        \\    jobs: Job[]
        \\
        \\func main() -> int:
        \\    const text = json.encode(Queue(jobs=[Job(name="a", run=twice)])) else Err(_):
        \\        return 1
        \\    return len(text)
        \\
    , &.{ "`Queue` has no plain JSON form", "its part `jobs[].run`", "which no JSON can hold" });
}

test "json codec: a dictionary, bytes and a json.Json part are refused as not built yet" {
    try refusedWith(head ++
        \\record Counts:
        \\    by_name: dict[str, int]
        \\
        \\func main() -> int:
        \\    const value = json.decode[Counts]("{}") else Err(_):
        \\        return 1
        \\    return len(value.by_name)
        \\
    , &.{ "its part `by_name` is a `dict[str, int]`", "not built yet" });
    try refusedWith(head ++
        \\record Blob:
        \\    data: bytes
        \\
        \\func main() -> int:
        \\    const value = json.decode[Blob]("{}") else Err(_):
        \\        return 1
        \\    return len(value.data)
        \\
    , &.{ "its part `data` is a `bytes`", "not built yet" });
    try refusedWith(head ++
        \\record Mixed:
        \\    name: str
        \\    rest: json.Json?
        \\
        \\func main() -> int:
        \\    const value = json.decode[Mixed]("{}") else Err(_):
        \\        return 1
        \\    return len(value.name)
        \\
    , &.{ "its part `rest`", "not built yet" });
}

test "json codec: a set at the top level and a capability are refused" {
    try refusedWith(head ++
        \\func main() -> int:
        \\    const value = json.decode[set[int]]("[]") else Err(_):
        \\        return 1
        \\    return len(value)
        \\
    , &.{ "has no plain JSON form", "not built yet" });
    try refusedWith(head ++
        \\record Holder:
        \\    out: Stream
        \\
        \\func main(out: Stream) -> int:
        \\    const text = json.encode(Holder(out=out)) else Err(_):
        \\        return 1
        \\    return len(text)
        \\
    , &.{ "its part `out`", "which no JSON can hold" });
}

test "json codec: a generic bound forwards the codec promise and a concrete argument without a form is refused there" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(), head ++
        \\record Point:
        \\    x: int
        \\    y: float
        \\    label: str?
        \\
        \\func load[T: codec](text: str) -> T fails json.CodecError:
        \\    return try json.decode[T](text)
        \\
        \\func main() -> int:
        \\    const point = load[Point]("{\"x\": 1, \"y\": 2.5}") else Err(_):
        \\        return 1
        \\    return point.x
        \\
    );
    try refusedWith(head ++
        \\func load[T: codec](text: str) -> T fails json.CodecError:
        \\    return try json.decode[T](text)
        \\
        \\func main() -> int:
        \\    const table = load[dict[str, int]]("{}") else Err(_):
        \\        return 1
        \\    return len(table)
        \\
    , &.{"not built yet"});
}

test "json codec: a decoded record that breaks its invariant fails with kind invariant, and nothing traps" {
    try fixture.expect(t.allocator, head ++
        \\@invariant(self.low <= self.high, "a span never runs backwards")
        \\record Span:
        \\    low: int
        \\    high: int
        \\
        \\record Holder:
        \\    spans: Span[]
        \\
        \\func main() -> int:
        \\    const holder = json.decode[Holder]("{\"spans\": [{\"low\": 1, \"high\": 2}, {\"low\": 5, \"high\": 1}]}") else Err(e):
        \\        if e.kind == json.CodecErrorKind.invariant and e.path == "spans[1]":
        \\            return 7
        \\        return 1
        \\    return len(holder.spans)
        \\
    , .{}, 7);
    try fixture.expect(t.allocator, head ++
        \\@invariant(self.low <= self.high, "a span never runs backwards")
        \\record Span:
        \\    low: int
        \\    high: int
        \\
        \\func main() -> int:
        \\    const span = json.decode[Span]("{\"low\": 1, \"high\": 2}") else Err(_):
        \\        return 0
        \\    return span.high * 10 + span.low
        \\
    , .{}, 21);
}

test "json codec: a missing member takes its declared default, a constant and a constructor included" {
    try fixture.expect(t.allocator, head ++
        \\const LIMIT: int = 40
        \\
        \\record Inner:
        \\    a: int = 2
        \\
        \\record Outer:
        \\    limit: int = LIMIT
        \\    inner: Inner = Inner(a=1)
        \\    name: str
        \\
        \\func main() -> int:
        \\    const value = json.decode[Outer]("{\"name\": \"n\"}") else Err(_):
        \\        return 0
        \\    return value.limit + value.inner.a + len(value.name)
        \\
    , .{}, 42);
}
