//! Python named arguments retain declaration identity, source order, and cleanup.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

const ordered =
    \\def mark(log: list[int], value: int) -> int:
    \\    log.append(value)
    \\    return value
    \\
    \\def combine(a: int, b: int = 2) -> int:
    \\    return a * 10 + b
    \\
    \\def main() -> int:
    \\    log: list[int] = []
    \\    answer = combine(b=mark(log, 2), a=mark(log, 4))
    \\    return answer + log[0] * 100 + log[1] * 1000
;
fn execute(allocator: std.mem.Allocator, text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(allocator, "calls.my", text);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}
// spec: PYTHON-CALL-1
test "Python keyword calls evaluate effects in source order before parameter binding" {
    try execute(t.allocator, ordered, 4242);
    try execute(t.allocator, "def add(a: int, b: int = 2) -> int:\n    return a + b\n\ndef main() -> int:\n    return add(a=40)\n", 42);
    try execute(t.allocator, "def add(a: int, b: int = 2) -> int:\n    return a + b\n\ndef main() -> int:\n    return add(a=40) + add(a=1)\n", 45);
    try execute(t.allocator, "def pick[T](first: T, second: T) -> T:\n    _ = second\n    return first\n\ndef main() -> int:\n    return pick(second=2, first=42)\n", 42);
}

// spec: PYTHON-CALL-2
test "Python calls reject unknown duplicate missing and misplaced arguments and invalid defaults" {
    const header = "def add(a: int, b: int = 2) -> int:\n    return a + b\n\ndef main() -> int:\n    return ";
    for ([_][]const u8{ "add(unknown=1)", "add(a=1, a=2)", "add(1, a=2)", "add()", "add(1, 2, 3)", "add(a=1, 2)" }) |call| {
        const text = try std.mem.concat(t.allocator, u8, &.{ header, call, "\n" });
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "bad.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
    }
}

// spec-case: PYTHON-CALL-2
test "Python defaults reject mutable expressions and mismatched scalar types" {
    for ([_][]const u8{
        "def bad(a: int = True):\n    pass\n\ndef main() -> int:\n    return 0\n",
        "def bad(a: int = 1, b: int):\n    pass\n\ndef main() -> int:\n    return 0\n",
        "def bad(a: list[int] = []):\n    pass\n\ndef main() -> int:\n    return 0\n",
        "def bad(a: int = 1 + 2):\n    pass\n\ndef main() -> int:\n    return 0\n",
    }) |text| {
        var c = try language.Compilation.init(t.allocator, "default.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
    }
}

// spec: PYTHON-CALL-3
test "Python empty and positional record constructors resolve alongside keyword functions" {
    const text =
        \\class Empty:
        \\    pass
        \\
        \\class Box[T]:
        \\    value: T
        \\
        \\def make[T](value: T) -> Box[T]:
        \\    return Box[T](value=value)
        \\
        \\def main() -> int:
        \\    _ = Empty()
        \\    first = Box[int](40)
        \\    second = make(value=2)
        \\    return first.value + second.value
        \\
    ;
    try execute(t.allocator, text, 42);
}

// spec: PYTHON-CALL-5
test "Python default changes invalidate checked caller reuse" {
    var cache = language.semantic_cache.Cache.init(t.allocator, 8 * 1024 * 1024);
    defer cache.deinit();
    for ([_]struct { default: []const u8, expected: i64 }{ .{ .default = "2", .expected = 42 }, .{ .default = "3", .expected = 43 } }) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ "def add(a: int, b: int = ", case.default, ") -> int:\n    return a + b\n\ndef main() -> int:\n    return add(a=40)\n" });
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "cached.my", text);
        defer c.deinit();
        try c.checkWithCache(&cache);
        try t.expectEqual(case.expected, (try native.run(&c)).value);
    }
}

// spec-case: PYTHON-CALL-1
test "Python keyword scalar and reference calls emit native source with identical side effects" {
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, "test/fixtures/python-calls.my", t.allocator, .limited(8192));
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, "native-calls.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 2442), (try native.run(&c)).value);
}

// spec: PYTHON-CALL-4
test "Python keyword call temporaries remain rooted under GC stress and are reclaimed" {
    const text =
        \\def make(value: int) -> list[int]:
        \\    xs: list[int] = []
        \\    xs.append(value)
        \\    return xs
        \\
        \\def use(first: list[int], second: list[int]) -> int:
        \\    return first[0] * 10 + second[0]
        \\
        \\def main() -> int:
        \\    answer = use(second=make(2), first=make(4))
        \\    _ = make(0)
        \\    return answer
        \\
    ;
    var c = try language.Compilation.init(t.allocator, "roots.my", text);
    defer c.deinit();
    const result = try native.runWithOptions(&c, .{ .gc_stress = true });
    try t.expectEqual(@as(i64, 42), result.value);
}
