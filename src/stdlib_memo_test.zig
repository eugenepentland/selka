//! Native acceptance and type/effect boundaries for bounded in-memory memoization.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const language = @import("compiler.zig");

// spec: STANDARD-MEMO-1
test "standard memo reuses tagged arguments with bounded FIFO and independent value snapshots" {
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/lang/memo_cache.my", t.allocator, .limited(1 << 20));
    defer t.allocator.free(text);
    try fixture.run(t.allocator, text, 42);
}

// spec-case: STANDARD-MEMO-1
test "standard memo rejects direct and transitive externally mutating callbacks" {
    try reject(t.allocator,
        \\import memo
        \\func change(mut key: memo.Key) -> int:
        \\    key = memo.Key.Number(value=99)
        \\    return 99
        \\func main() -> int:
        \\    match memo.create(1, change):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, memo.Key.Number(value=1)).value
        \\        case Err(_):
        \\            return 0
    , "E_TYPE");
    try reject(t.allocator,
        \\import memo
        \\func helper(mut key: memo.Key) -> int:
        \\    key = memo.Key.Number(value=99)
        \\    return 99
        \\func change(mut key: memo.Key) -> int:
        \\    return helper(mut key)
        \\func main() -> int:
        \\    match memo.create(1, change):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, memo.Key.Number(value=1)).value
        \\        case Err(_):
        \\            return 0
    , "E_TYPE");
}

// spec-case: STANDARD-MEMO-1
test "standard memo rejects captured locals and Host callbacks" {
    try reject(t.allocator,
        \\import memo
        \\func main() -> int:
        \\    mut offset = 7
        \\    mut compute: func(memo.Key) -> int effects(managed_allocation) = lambda key: offset
        \\    match memo.create(1, compute):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, memo.Key.Number(value=1)).value
        \\        case Err(_):
        \\            return 0
    , "E_LAMBDA_CAPTURE");
    try reject(t.allocator,
        \\import memo
        \\extern func foreign(host: Host, value: i64) -> i64 effects(host)
        \\func call_host(host: Host, key: memo.Key) -> int:
        \\    return int(foreign(host, 1i64))
        \\func main() -> int:
        \\    match memo.create(1, call_host):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, memo.Key.Number(value=1)).value
        \\        case Err(_):
        \\            return 0
    , "E_GENERIC_INFERENCE");
}

// spec-case: STANDARD-MEMO-1
test "standard memo rejects same-shaped callback ceilings with clock or host effects" {
    try reject(t.allocator,
        \\import memo
        \\func forbidden(compute: func(memo.Key) -> int effects(clock)) -> int:
        \\    match memo.create(1, compute):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, memo.Key.Number(value=1)).value
        \\        case Err(_):
        \\            return 0
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
    try reject(t.allocator,
        \\import memo
        \\func forbidden(compute: func(memo.Key) -> int effects(host)) -> int:
        \\    match memo.create(1, compute):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, memo.Key.Number(value=1)).value
        \\        case Err(_):
        \\            return 0
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
}

// spec-case: STANDARD-MEMO-1
test "standard memo rejects callback capability and nested callback output types" {
    try reject(t.allocator,
        \\import memo
        \\func invalid(cache: memo.Cache[Host]) -> int:
        \\    return 1
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(t.allocator,
        \\import memo
        \\record CallbackOutput:
        \\    compute: func(int) -> int effects()
        \\func invalid(cache: memo.Cache[CallbackOutput]) -> int:
        \\    return 1
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(t.allocator,
        \\import memo
        \\resource Owned: filesystem
        \\func invalid(cache: memo.Cache[Owned]) -> int:
        \\    return 1
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try reject(t.allocator,
        \\import memo
        \\func invalid(cache: memo.Cache[Result[int, str]]) -> int:
        \\    return 1
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
}

// spec-case: STANDARD-MEMO-1
test "standard memo requires closed keys rather than mutable lists or floats" {
    try reject(t.allocator,
        \\import memo
        \\func number(key: memo.Key) -> int effects():
        \\    return 42
        \\func main() -> int:
        \\    match memo.create(1, number):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, [1]).value
        \\        case Err(_):
        \\            return 0
    , "E_TYPE");
    try reject(t.allocator,
        \\import memo
        \\func number(key: memo.Key) -> int effects():
        \\    return 42
        \\func main() -> int:
        \\    match memo.create(1, number):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            return memo.call(mut cache, 1.0).value
        \\        case Err(_):
        \\            return 0
    , "E_TYPE");
}

// spec-case: STANDARD-MEMO-1
test "standard memo propagates traps from a fresh computation" {
    try fixture.trap(t.allocator,
        \\import memo
        \\func fragile(key: memo.Key) -> int effects():
        \\    match key:
        \\        case memo.Key.Number(value=value):
        \\            return 10 // value
        \\        case memo.Key.Text(value=_):
        \\            return 1
        \\        case memo.Key.Data(value=_):
        \\            return 1
        \\func main() -> int:
        \\    match memo.create(1, fragile):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            _ = memo.call(mut cache, memo.Key.Number(value=2))
        \\            return memo.call(mut cache, memo.Key.Number(value=0)).value
        \\        case Err(_):
        \\            return 1
    , .{}, "R_DIVISION_BY_ZERO");
}

/// Assert the intended semantic diagnostic after loading valid library source.
fn reject(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var entry: fixture.Entry = .{ .text = text };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &entry, .read = fixture.Entry.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try t.expectError(error.SourceError, compilation.check());
    for (compilation.diagnostics.items.items) |item| {
        if (item.severity != .err) continue;
        try t.expectEqualStrings(code, item.code);
        return;
    }
    return error.TestUnexpectedResult;
}

// spec-case: STANDARD-PERSISTENT-MEMO-1
test "persistent memo rejects callbacks with hidden host effects" {
    try reject(t.allocator,
        \\import memo
        \\import persistent_memo
        \\func forbidden(fs: Filesystem, compute: func(memo.Key) -> bytes effects(host)) -> int:
        \\    const options = persistent_memo.Options(max_entries=1, max_bytes=64)
        \\    _ = persistent_memo.call(fs, options, compute, memo.Key.Number(value=1))
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
}

// spec-case: STANDARD-DURABLE-1
test "durable run rejects caller mutation and hidden host effects" {
    try reject(t.allocator,
        \\import durable
        \\func change(chunk: bytes, mut state: bytes) -> durable.Step:
        \\    state = chunk
        \\    return durable.Step(output=chunk, state=state)
        \\func forbidden(fs: Filesystem, request: durable.Request) -> int:
        \\    _ = durable.run(fs, request, change)
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
    try reject(t.allocator,
        \\import durable
        \\func forbidden(fs: Filesystem, request: durable.Request, compute: func(bytes, bytes) -> durable.Step effects(host)) -> int:
        \\    _ = durable.run(fs, request, compute)
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
}
