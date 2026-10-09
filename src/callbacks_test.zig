//! Typed noncapturing callbacks preserve signatures, effects and ordinary ownership transfers.
const std = @import("std");
const print = std.debug.print;
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "callback.my", source);
    defer c.deinit();
    const outcome = native.run(&c) catch |err| {
        for (c.diagnostics.items) |d| print("{s}: {s} ({s})\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    try t.expectEqual(expected, outcome.value);
}
// spec: PY-LAMBDA-2
test "lambdas reject missing context wrong results effects and local captures" {
    try reject("func main() -> int:\n    mut f = lambda value: value\n    return 0\n", "E_LAMBDA_CONTEXT");
    try reject(
        "func apply(f: func(int) -> bool effects()) -> int:\n    return 0\n\nfunc main() -> int:\n    return apply(lambda value: value + 1)\n",
        "E_TYPE",
    );
    try reject(
        "func apply(f: func(int) -> Unit effects()) -> int:\n    return 0\n\nfunc main() -> int:\n    return apply(lambda value: print(value))\n",
        "E_OUTPUT_CAPABILITY",
    );
    var capture = try language.Compilation.init(
        t.allocator,
        "lambda-capture.my",
        "func apply(f: func(int) -> int effects()) -> int:\n    return f(1)\n\nfunc main() -> int:\n    mut offset = 2\n    return apply(lambda value: value + offset)\n",
    );
    defer capture.deinit();
    try t.expectError(error.SourceError, capture.check());
    try t.expectEqualStrings("E_LAMBDA_CAPTURE", capture.diagnostics.items[0].code);
    try t.expectEqualStrings("offset", capture.src.text(capture.diagnostics.items[0].span));
}

// spec-case: CALLBACK-1
test "a callback type names itself the way the surface writes it" {
    var c = try language.Compilation.init(t.allocator, "callback-name.my",
        \\func apply(f: func(i64) -> i64 effects(), x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(7, 8)
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TYPE", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "func(int) -> int effects()") != null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "fn") == null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "def@") == null);
}

fn reject(source: []const u8, code: []const u8) !void {
    const complete = try std.mem.concat(t.allocator, u8, &.{
        source,
        if (std.mem.indexOf(u8, source, "func main") == null)
            \\func main() -> i64:
            \\    return 0
        else
            "",
    });
    defer t.allocator.free(complete);
    var c = try language.Compilation.init(t.allocator, "invalid-callback.my", complete);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const allocation_source =
    \\record Box:
    \\    value: FixedArray[i64, 2]
    \\
    \\
    \\func make(ctx: i64, n: i64) -> Box effects():
    \\    return Box(value=FixedArray[int, 2]([n + ctx, n + 1]))
    \\
    \\
    \\func apply[T](f: func(T, i64) -> Box effects(), ctx: T, n: i64) -> Box:
    \\    return f(ctx, n)
    \\
    \\
    \\func main() -> i64:
    \\    mut context = 0
    \\    mut a = apply[i64](make, context, 7)
    \\    mut f = make
    \\    mut b = f(context, 9)
    \\    return a.value[0] + b.value[1]
;

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "allocation-callback.my", allocation_source);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    try t.expectEqual(@as(i64, 17), (try native.run(&copy)).value);
}

test "callbacks compile format execute and emit under every failed allocation" {
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}

const module_source =
    \\import helpers as c
    \\
    \\
    \\func descending(a: i64, b: i64) -> bool effects():
    \\    return a > b
    \\
    \\
    \\func twice(x: i64) -> i64 effects():
    \\    return x * 2
    \\
    \\
    \\func main() -> i64:
    \\    mut a: FixedArray[i64, 4] = FixedArray[i64, 4]([3, 1, 4, 2])
    \\    mut sorted = c.sort_by(a, descending)
    \\    mut doubled = c.transform(sorted, twice)
    \\    return doubled[0] * 10 + doubled[3]
;
const helpers_source =
    \\
    \\
    \\public func sort_by(a: FixedArray[i64, 4], less: func(i64, i64) -> bool effects()) -> FixedArray[i64, 4] effects():
    \\    mut v = a
    \\    mut i = 0
    \\    while i < 4:
    \\        mut j = 0
    \\        while j < 3:
    \\            if less(v[j + 1], v[j]):
    \\                mut tmp = v[j]
    \\                v = replace(v, j, v[j + 1])
    \\                v = replace(v, j + 1, tmp)
    \\            j += 1
    \\        i += 1
    \\    return v
    \\
    \\
    \\public func transform(a: FixedArray[i64, 4], f: func(i64) -> i64 effects()) -> FixedArray[i64, 4] effects():
    \\    mut v = a
    \\    mut i = 0
    \\    while i < 4:
    \\        v = replace(v, i, f(v[i]))
    \\        i += 1
    \\    return v
;
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const bytes = if (std.mem.eql(u8, path, "main.my")) module_source else if (std.mem.eql(u8, path, "helpers.my")) helpers_source else return error.NotFound;
    if (bytes.len > limit) return error.TooLarge;
    return allocator.dupe(u8, bytes);
}

test "callbacks drive sorting and visitor helpers across module boundaries" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = moduleRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 82), (try native.run(&program.compilation)).value);
}

const module_lambda_source =
    \\
    \\
    \\func apply(f: func(int) -> int effects(), value: int) -> int:
    \\    return f(value)
    \\
    \\
    \\func main() -> int:
    \\    return apply(lambda value: value * 2, 21)
;
fn moduleLambdaRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (module_lambda_source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, module_lambda_source);
}
// spec-case: PY-LAMBDA-1
test "module projects preserve expression lambdas through merging and execution" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = moduleLambdaRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&program.compilation)).value);
}

// spec-case: CALLBACK-1
test "E1 pure callbacks enter output-permitting slots and the reverse direction rejects" {
    try run(
        \\func pure(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\func apply(f: func(i64) -> i64 effects(output), x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main(out: Stream) -> i64:
        \\    _ = out
        \\    return apply(pure, 41)
    , 42);

    const reverse =
        \\func impure(out: Stream, x: i64) -> i64 effects(output):
        \\    out.print(x)
        \\    return x
        \\
        \\
        \\func apply(f: func(Stream, i64) -> i64 effects(), out: Stream, x: i64) -> i64:
        \\    return f(out, x)
        \\
        \\
        \\func main(out: Stream) -> i64:
        \\    return apply(impure, out, 1)
    ;
    var c = try language.Compilation.init(t.allocator, "effect-reverse.my", reverse);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TYPE", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "expected func(stream_cap, int) -> int effects()") != null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "found func(stream_cap, int) -> int effects(output)") != null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "def@") == null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "effects(0)") == null);

    // The destination ceiling still governs the call inside `apply`, even though
    // the concrete target is pure.
    try reject(
        \\func pure(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\func apply(f: func(i64) -> i64 effects(output), x: i64) -> i64 effects():
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(pure, 41)
    , "E_EFFECT_BOUND");
}

// spec-case: CALLBACK-1
test "E1 unused declarations and unrelated callback shapes stay rejected" {
    try reject(
        \\func impure(out: Stream, x: i64) -> i64 effects(output):
        \\    out.print(x)
        \\    return x
        \\
        \\
        \\func unused(out: Stream) -> i64:
        \\    mut f: func(Stream, i64) -> i64 effects() = impure
        \\    return f(out, 0)
        \\
    , "E_TYPE");
    try reject(
        \\func wrong_parameter(x: bool) -> i64 effects():
        \\    return 0
        \\
        \\
        \\func apply(f: func(i64) -> i64 effects(output), x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(wrong_parameter, 1)
    , "E_TYPE");
    try reject(
        \\func wrong_result(x: i64) -> bool effects():
        \\    return True
        \\
        \\
        \\func apply(f: func(i64) -> i64 effects(output), x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(wrong_result, 1)
    , "E_TYPE");
}

// spec-case: CALLBACK-1
test "E1 unused generic declarations use the directional callback relation" {
    try run(
        \\func unused[T](f: func(T) -> T effects(), value: T) -> T:
        \\    mut g: func(T) -> T effects(output) = f
        \\    return value
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    , 0);
    try reject(
        \\func unused[T](f: func(T) -> T effects(output), value: T) -> T:
        \\    mut g: func(T) -> T effects() = f
        \\    return value
        \\
    , "E_GENERIC_TYPE");
}
