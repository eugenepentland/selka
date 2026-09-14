//! Unicode text and ordered dictionary surface: literals, aliases, equality and membership.
const std = @import("std");
const values = @import("runtime_values.zig");
const t = std.testing;
const debug = std.debug.print;
const str_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));
const dict_type: values.Type = @fromBackingInt(@intCast(34));

fn runSource(source: []const u8, expected: i64) !void {
    const language = @import("compiler.zig");
    var compilation = try language.Compilation.init(t.allocator, "managed-values.my", source);
    defer compilation.deinit();
    const result = @import("native_execute.zig").run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(expected, result.value);
}

// spec: PY-TEXT-1
test "managed text source literals concat equality Unicode index and length" {
    try runSource(
        \\def main() -> i64:
        \\    value: str = b"hé🙂"
        \\    suffix: str = b"!"
        \\    all = value + suffix
        \\    if all[3] == suffix:
        \\        return len(all)
        \\    return 0
    , 4);
}

// spec: PY-DICT-1
test "managed dictionary source literals indexing alias updates get and snapshots" {
    try runSource(
        \\def main() -> i64:
        \\    scores: dict[str, i64] = {b"x": 1}
        \\    alias = scores
        \\    alias[b"x"] = 40
        \\    names = scores.keys()
        \\    key: str = b"x"
        \\    if names[0] == key:
        \\        return scores.get(b"x", 0) + scores.get(b"missing", 2)
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    scores = {1: 40, 2: 2}
        \\    return scores[1] + scores[2]
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    text: str = b"a,b,"
        \\    parts = text.split(b",")
        \\    sep: str = b","
        \\    joined = sep.join(parts)
        \\    if joined == text:
        \\        return len(joined)
        \\    return 0
    , 4);
}

test "managed str conversion source evaluates argument once" {
    try runSource(
        \\def next(xs: List[i64]) -> i64:
        \\    xs.append(1)
        \\    return 42
        \\
        \\
        \\def main() -> i64:
        \\    xs: List[i64] = []
        \\    s = str(next(xs))
        \\    expected: str = b"42"
        \\    if s == expected:
        \\        return i64(xs.len())
        \\    return 0
    , 1);
}

test "managed equality source compares values rather than insertion order" {
    try runSource(
        \\def main() -> i64:
        \\    a = {1: 10, 2: 20}
        \\    b = {2: 20, 1: 10}
        \\    if a == b:
        \\        return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    a: List[i64] = []
        \\    b: List[i64] = []
        \\    a.append(42)
        \\    b.append(42)
        \\    if a == b:
        \\        if a.contains(42):
        \\            return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    text: str = b"hé🙂"
        \\    if text.contains(b"é🙂"):
        \\        return 42
        \\    return 0
    , 42);
}

test "user nominal str declaration preserves its declared fields" {
    try runSource(
        \\class str:
        \\    n: i64
        \\
        \\
        \\def main() -> i64:
        \\    value = str(n=42)
        \\    return value.n
    , 42);
}

test "managed membership source searches list values dictionary keys and text" {
    try runSource(
        \\def main() -> i64:
        \\    values = {1: 10, 2: 20}
        \\    if 2 in values:
        \\        return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.append(42)
        \\    if 42 in values:
        \\        return 42
        \\    return 0
    , 42);
    try runSource(
        \\def main() -> i64:
        \\    text: str = b"hé🙂"
        \\    part: str = b"é🙂"
        \\    if part in text:
        \\        return 42
        \\    return 0
    , 42);
}
