//! Native acceptance and type/effect boundaries for bounded in-memory memoization.
const std = @import("std");
const t = std.testing;
const fixture = @import("stdlib_fixture.zig");
const language = @import("compiler.zig");

// spec: STANDARD-MEMO-1
test "standard memo reuses tagged arguments with bounded FIFO and independent value snapshots" {
    const text = try std.Io.Dir.cwd().readFileAlloc(t.io, "tests/lang/memo_cache.selka", t.allocator, .limited(1 << 20));
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
    try rejectAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
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
    , " effects(managed_allocation)", "E_LAMBDA_CAPTURE");
    try rejectAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
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
    , " effects(host)", "E_GENERIC_INFERENCE");
    // A current named callback cannot capture a caller's local either.
    try reject(t.allocator,
        \\import memo
        \\func compute(key: memo.Key) -> int:
        \\    return offset
        \\func main() -> int:
        \\    mut offset = 7
        \\    _ = memo.create(1, compute)
        \\    return 0
    , "E_UNKNOWN_NAME");
}

// spec-case: STANDARD-MEMO-1
test "standard memo rejects same-shaped callback ceilings with clock or host effects" {
    try acceptAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
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
    , " effects(clock)");
    try acceptAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
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
    , " effects(host)");
    // Effect-ceiling-only rejection is retired. Explicit capability parameters
    // still make these callbacks incompatible with memo.create(Key -> V).
    try reject(t.allocator,
        \\import memo
        \\func forbidden(compute: func(Clock, memo.Key) -> int) -> int:
        \\    _ = memo.create(1, compute)
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_INFERENCE");
    try reject(t.allocator,
        \\import memo
        \\func forbidden(compute: func(Host, memo.Key) -> int) -> int:
        \\    _ = memo.create(1, compute)
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_INFERENCE");
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
    try rejectAfterEffects(t.allocator,
        // migrate-embedded: skip exact callback-output effect-removal witness
        \\import memo
        \\record CallbackOutput:
        \\    compute: func(int) -> int effects()
        \\func invalid(cache: memo.Cache[CallbackOutput]) -> int:
        \\    return 1
        \\func main() -> int:
        \\    return 0
    , " effects()", "E_GENERIC_REQUIREMENT");
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
    try rejectAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
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
    , " effects()", "E_TYPE");
    try rejectAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
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
    , " effects()", "E_TYPE");
}

// spec-case: STANDARD-MEMO-1
test "standard memo propagates traps from a fresh computation" {
    const original =
        // migrate-embedded: skip executable effects-removal witness; modern runtime counterpart below
        \\import memo
        \\func fragile(key: memo.Key) -> int effects():
        \\    match key:
        \\        case Number(value=value):
        \\            return 10 // value
        \\        case Text(value=_):
        \\            return 1
        \\        case Data(value=_):
        \\            return 1
        \\func main() -> int:
        \\    match memo.create(1, fragile):
        \\        case Ok(initial):
        \\            mut cache = initial
        \\            _ = memo.call(mut cache, memo.Key.Number(value=2))
        \\            return memo.call(mut cache, memo.Key.Number(value=0)).value
        \\        case Err(_):
        \\            return 1
    ;
    {
        var entry: fixture.Entry = .{ .text = original };
        var project = language.project.Project.init(t.allocator);
        defer project.deinit();
        try project.load(.{ .context = &entry, .read = fixture.Entry.read }, "main", .{});
        try t.expectError(error.SourceError, language.interfaces.build(&project));
        try t.expectEqualStrings("E_EFFECTS_REMOVED", project.problem.?.code);
    }
    const without_effects = try std.mem.replaceOwned(u8, t.allocator, original, " effects()", "");
    defer t.allocator.free(without_effects);
    const modern = try std.mem.replaceOwned(u8, t.allocator, without_effects, "mut cache = initial", "mut cache = own initial");
    defer t.allocator.free(modern);
    try t.expect(!std.mem.eql(u8, original, modern));
    try fixture.trap(t.allocator, modern, .{}, "R_DIVISION_BY_ZERO");
}

/// Keep each exact old input executable before checking its current counterpart.
fn afterEffects(allocator: std.mem.Allocator, text: []const u8, clause: []const u8) ![]u8 {
    try reject(allocator, text, "E_EFFECTS_REMOVED");
    try t.expect(std.mem.indexOf(u8, text, clause) != null);
    return std.mem.replaceOwned(u8, allocator, text, clause, "");
}

fn rejectAfterEffects(allocator: std.mem.Allocator, text: []const u8, clause: []const u8, code: []const u8) !void {
    const modern = try afterEffects(allocator, text, clause);
    defer allocator.free(modern);
    try reject(allocator, modern, code);
}

/// A function type's removed effect ceiling no longer rejects an otherwise matching callback.
fn acceptAfterEffects(allocator: std.mem.Allocator, text: []const u8, clause: []const u8) !void {
    const modern = try afterEffects(allocator, text, clause);
    defer allocator.free(modern);
    var entry: fixture.Entry = .{ .text = modern };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &entry, .read = fixture.Entry.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var compilation = try language.project_compile.Compilation.init(&index);
    try compilation.check();
}

/// Assert the intended semantic diagnostic after loading valid library source.
fn reject(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !void {
    var entry: fixture.Entry = .{ .text = text };
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    project.load(.{ .context = &entry, .read = fixture.Entry.read }, "main", .{}) catch |failure| {
        if (failure != error.SourceError) return failure;
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
    var index = language.interfaces.build(&project) catch |failure| {
        if (failure != error.SourceError) return failure;
        try t.expectEqualStrings(code, project.problem.?.code);
        return;
    };
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
    try acceptAfterEffects(t.allocator,
        // migrate-embedded: skip executable exact effect-removal witness with current counterpart
        \\import memo
        \\import persistent_memo
        \\func forbidden(fs: Filesystem, compute: func(memo.Key) -> bytes effects(host)) -> int:
        \\    const options = persistent_memo.Options(max_entries=1, max_bytes=64)
        \\    _ = persistent_memo.call(fs, options, compute, memo.Key.Number(value=1))
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , " effects(host)");
    // A hidden ceiling is retired; requiring Host explicitly remains a signature mismatch.
    try reject(t.allocator,
        \\import memo
        \\import persistent_memo
        \\func forbidden(fs: Filesystem, compute: func(Host, memo.Key) -> bytes) -> int:
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
    try acceptAfterEffects(t.allocator,
        // migrate-embedded: skip exact durable callback effect-removal witness
        \\import durable
        \\func forbidden(fs: Filesystem, request: durable.Request, compute: func(bytes, bytes) -> durable.Step effects(host)) -> int:
        \\    _ = durable.run(fs, request, compute)
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , " effects(host)");
    // The effect-only ceiling is retired; an explicit Host argument remains incompatible.
    try reject(t.allocator,
        \\import durable
        \\func forbidden(fs: Filesystem, request: durable.Request, compute: func(Host, bytes, bytes) -> durable.Step) -> int:
        \\    _ = durable.run(fs, request, compute)
        \\    return 0
        \\func main() -> int:
        \\    return 0
    , "E_TYPE");
}
