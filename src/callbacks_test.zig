//! Typed noncapturing callbacks preserve signatures, effects and ordinary ownership transfers.
const std = @import("std");
const print = std.debug.print;
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const function_identity_code = @import("function_same.zig").code;
const support = @import("test_support.zig");
fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "callback.selka", source);
    defer c.deinit();
    const outcome = native.run(&c) catch |err| {
        for (c.diagnostics.items) |d| print("{s}: {s} ({s})\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    try t.expectEqual(expected, outcome.value);
}

const identity_source =
    \\record Stored[T: storable]:
    \\    compute: func(int) -> T
    \\
    \\func first(value: int) -> int:
    \\    return value + 1
    \\
    \\func twin(value: int) -> int:
    \\    return value + 1
    \\
    \\func select(flag: bool) -> func(int) -> int:
    \\    if flag:
    \\        return first
    \\    else:
    \\        return twin
    \\
    \\func matches[T: storable](entry: Stored[T], current: func(int) -> T) -> bool:
    \\    return same_function(entry.compute, current)
    \\
    \\func compare(left: func(int) -> int, right: func(int) -> int) -> bool:
    \\    return same_function(left, right)
    \\
    \\func main(args: str[]) -> int:
    \\    mut selected = select(len(args) > 0)
    \\    mut saved = Stored[int](compute=selected)
    \\    if not same_function(first, first) or same_function(first, twin):
    \\        return 1
    \\    if not compare(selected, twin) or compare(selected, first):
    \\        return 2
    \\    if not matches[int](saved, twin) or matches[int](saved, first):
    \\        return 3
    \\    if not same_function(selected, saved.compute):
    \\        return 4
    \\    return 42
;

fn runIdentity(release: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "function-identity.selka", identity_source);
    defer compilation.deinit();
    if (release) try support.requireRelease();
    const outcome = native.runWithOptions(&compilation, .{ .arguments = if (release) &.{"--release"} else &.{} }) catch |err| {
        for (compilation.diagnostics.items) |d| print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expect(!outcome.trapped());
}

// spec: FUNCTION-IDENTITY-1
test "same_function identifies returned stored and generic callbacks in debug" {
    try runIdentity(false);
}

// spec-case: FUNCTION-IDENTITY-1
test "same_function preserves distinct identical-body declarations in release" {
    try runIdentity(true);
}

// FR-422: a function value stored in a record field is called after binding it; a
// direct call through the field names that one spelling instead of a method.
test "a callback stored in a record field is refused with the binding spelling" {
    const source =
        \\record Handler:
        \\    callback: func(int) -> int
        \\
        \\func twice(value: int) -> int:
        \\    return value * 2
        \\
        \\func make() -> Handler:
        \\    return Handler(callback=twice)
        \\
        \\func main() -> int:
        \\    const handler = make()
        \\    return handler.callback(21)
    ;
    var local = try language.Compilation.init(t.allocator, "callback-field.selka", source);
    defer local.deinit();
    try t.expectError(error.SourceError, local.check());
    try t.expectEqualStrings("E_COLLECTION_METHOD", local.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, local.diagnostics.items[0].message, "bind it first") != null);
    const temporary =
        \\record Handler:
        \\    callback: func(int) -> int
        \\
        \\func twice(value: int) -> int:
        \\    return value * 2
        \\
        \\func make() -> Handler:
        \\    return Handler(callback=twice)
        \\
        \\func main() -> int:
        \\    return make().callback(21)
    ;
    var expression = try language.Compilation.init(t.allocator, "callback-field-temporary.selka", temporary);
    defer expression.deinit();
    try t.expectError(error.SourceError, expression.check());
    try t.expectEqualStrings("E_COLLECTION_METHOD", expression.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, expression.diagnostics.items[0].message, "bind it first") != null);
}

// spec-case: FUNCTION-IDENTITY-1
test "same_function rejects noncallable operands arity and incompatible signatures" {
    try reject("func main() -> int:\n    _ = same_function(1, 1)\n    return 0\n", function_identity_code);
    try reject("func main() -> int:\n    _ = same_function(main)\n    return 0\n", "E_ARITY");
    try reject("func first(value: int) -> int:\n    return value\nfunc other(value: bool) -> int:\n    return 1\nfunc main() -> int:\n    _ = same_function(first, other)\n    return 0\n", function_identity_code);
    try reject("func compare[T](left: func(T) -> int, right: func(bool) -> int) -> bool:\n    return same_function(left, right)\n", function_identity_code);
    try reject("func compare[T](left: func(mut value: T) -> int, right: func(T) -> int) -> bool:\n    return same_function(left, right)\n", function_identity_code);
    try reject("func main() -> int:\n    _ = main == main\n    return 0\n", "E_TYPE");
}

// spec-case: FUNCTION-IDENTITY-1
test "same_function remains shadowable by an ordinary declaration" {
    try run("func my_same_function(left: int, right: int) -> int:\n    return left + right\nfunc main() -> int:\n    return my_same_function(20, 22)\n", 42);
}
// spec: PY-LAMBDA-2
test "lambdas reject missing context wrong results effects and local captures" {
    try reject("func main() -> int:\n    mut f = lambda value: value\n    return 0\n", "E_LAMBDA_REMOVED");
    try reject(
        "func apply(f: func(int) -> bool) -> int:\n    return 0\n\nfunc main() -> int:\n    return apply(lambda value: value + 1)\n",
        "E_TYPE",
    );
    try reject(
        "func apply(f: func(int) -> Unit) -> int:\n    return 0\n\nfunc main() -> int:\n    return apply(lambda value: print(value))\n",
        "E_OUTPUT_CAPABILITY",
    );
    var capture = try language.Compilation.init(
        t.allocator,
        "lambda-capture.selka",
        "func apply(f: func(int) -> int) -> int:\n    return f(1)\n\nfunc main() -> int:\n    mut offset = 2\n    return apply(lambda value: value + offset)\n",
    );
    defer capture.deinit();
    try t.expectError(error.SourceError, capture.check());
    try t.expectEqualStrings("E_LAMBDA_CAPTURE", capture.diagnostics.items[0].code);
    try t.expectEqualStrings("offset", capture.src.text(capture.diagnostics.items[0].span));
}

// spec-case: CALLBACK-1
test "a callback type names itself the way the surface writes it" {
    var c = try language.Compilation.init(t.allocator, "callback-name.selka",
        \\func apply(f: func(i64) -> i64, x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(7, 8)
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TYPE", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "func(int) -> int") != null);
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
    var c = try language.Compilation.init(t.allocator, "invalid-callback.selka", complete);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const allocation_source =
    \\record Box:
    \\    value: FixedArray[i64, 2]
    \\
    \\
    \\func make(ctx: i64, n: i64) -> Box:
    \\    return Box(value=FixedArray[int, 2]([n + ctx, n + 1]))
    \\
    \\
    \\func apply[T](f: func(T, i64) -> Box, ctx: T, n: i64) -> Box:
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
    var c = try language.Compilation.init(allocator, "allocation-callback.selka", allocation_source);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.selka", formatted);
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
    \\func descending(a: i64, b: i64) -> bool:
    \\    return a > b
    \\
    \\
    \\func twice(x: i64) -> i64:
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
    \\public func sort_by(a: FixedArray[i64, 4], less: func(i64, i64) -> bool) -> FixedArray[i64, 4]:
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
    \\public func transform(a: FixedArray[i64, 4], f: func(i64) -> i64) -> FixedArray[i64, 4]:
    \\    mut v = a
    \\    mut i = 0
    \\    while i < 4:
    \\        v = replace(v, i, f(v[i]))
    \\        i += 1
    \\    return v
;
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    const bytes = if (std.mem.eql(u8, path, "main.selka")) module_source else if (std.mem.eql(u8, path, "helpers.selka")) helpers_source else return error.NotFound;
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
    \\func apply(f: func(int) -> int, value: int) -> int:
    \\    return f(value)
    \\
    \\
    \\func doubled(value: int) -> int:
    \\    return value * 2
    \\
    \\func main() -> int:
    \\    return apply(doubled, 21)
;
fn moduleLambdaRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
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
// spec-case: EFFECTS-REMOVED-1
test "callbacks carry authority through their explicit capability parameters" {
    try run("func announce(out: Stream, value: int) -> int:\n    print(out, value)\n    return value\n\n" ++
        "func apply(callback: func(Stream, int) -> int, out: Stream) -> int:\n    return callback(out, 42)\n\n" ++
        "func main(out: Stream) -> int:\n    return apply(announce, out)\n", 42);
}

// spec-case: CALLBACK-1
test "E1 unused declarations and unrelated callback shapes stay rejected" {
    try reject(
        \\func wrong_parameter(x: bool) -> i64:
        \\    return 0
        \\
        \\
        \\func apply(f: func(i64) -> i64, x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(wrong_parameter, 1)
    , "E_TYPE");
    try reject(
        \\func wrong_result(x: i64) -> bool:
        \\    return True
        \\
        \\
        \\func apply(f: func(i64) -> i64, x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\func main() -> i64:
        \\    return apply(wrong_result, 1)
    , "E_TYPE");
}

// spec-case: CALLBACK-1
// spec-case: EFFECTS-REMOVED-1
test "unused generic declarations preserve callback signature compatibility" {
    try run("func unused[T](callback: func(T) -> T, value: T) -> T:\n    const forwarded: func(T) -> T = callback\n    _ = forwarded\n    return value\n\nfunc main() -> int:\n    return 0\n", 0);
}

test "O3 callback results own fresh storage without caller mutation obligations" {
    try run(
        \\func make() -> int[]:
        \\    return []
        \\func apply(factory: func() -> int[]) -> int:
        \\    mut values = factory()
        \\    append(mut values, 42)
        \\    return values[0]
        \\func main() -> int:
        \\    return apply(make)
    , 42);
}

const digest_source =
    \\record Saved[T: storable]:
    \\    compute: func(int) -> T
    \\
    \\func helper(value: int) -> int:
    \\    return value + 1
    \\
    \\func first(value: int) -> int:
    \\    return helper(value)
    \\
    \\func second(value: int) -> int:
    \\    return helper(value) + 1
    \\
    \\func pick(flag: bool) -> func(int) -> int:
    \\    if flag:
    \\        return first
    \\    else:
    \\        return second
    \\
    \\func key[T: storable](saved: Saved[T]) -> str:
    \\    return function_digest(saved.compute)
    \\
    \\func main(args: str[]) -> int:
    \\    const selected = pick(len(args) > 0)
    \\    const saved = Saved[int](compute=selected)
    \\    const first_key = function_digest(first)
    \\    const second_key = function_digest(second)
    \\    if strings.char_count(first_key) != 64 or strings.char_count(second_key) != 64 or first_key == second_key:
    \\        return 1
    \\    if function_digest(selected) != second_key:
    \\        return 2
    \\    if strings.char_count(key[int](saved)) != 64 or key[int](saved) != key[int](saved):
    \\        return 3
    \\    return 42
;
fn runDigest(release: bool) !void {
    var compilation = try language.Compilation.init(t.allocator, "callable-digest.selka", digest_source);
    defer compilation.deinit();
    if (release) try support.requireRelease();
    const outcome = native.runWithOptions(&compilation, .{ .arguments = if (release) &.{"--release"} else &.{} }) catch |err| {
        for (compilation.diagnostics.items) |d| print("{s}: {s}\n", .{ d.code, d.message });
        return err;
    };
    try t.expectEqual(@as(i64, 42), outcome.value);
    try t.expect(!outcome.trapped());
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest identifies runtime-selected returned and stored generic callbacks in debug" {
    try runDigest(false);
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest identifies runtime-selected callbacks in release" {
    try runDigest(true);
}

// spec-case: FUNCTION-DIGEST-1
test "function_digest rejects nonfunctions and arity including unused generic bodies" {
    try reject("func main() -> int:\n    _ = function_digest(1)\n    return 0\n", "E_FUNCTION_DIGEST");
    try reject("func main() -> int:\n    _ = function_digest(main, main)\n    return 0\n", "E_ARITY");
    try reject("func key[T](value: T) -> str:\n    return function_digest(value)\n", "E_FUNCTION_DIGEST");
}

// spec-case: CALLBACK-1
test "callback argument slots retain exact mutation ABI and named labels without effect adoption" {
    try reject(
        "func read(values: int[]) -> int:\n    return len(values)\n" ++
            "func apply(callback: func(mut values: int[]) -> int, mut values: int[]) -> int:\n    return callback(mut values)\n" ++
            "func main() -> int:\n    mut values = [42]\n    return apply(read, mut values)\n",
        "E_TYPE",
    );
    try reject(
        "func calculate(named actual: int) -> int:\n    return actual\n" ++
            "func apply(callback: func(named expected: int) -> int) -> int:\n    return callback(expected=42)\n" ++
            "func main() -> int:\n    return apply(calculate)\n",
        "E_TYPE",
    );
    try run(
        "func increment(mut values: int[]) -> int:\n    values[0] += 1\n    return values[0]\n" ++
            "func apply(callback: func(mut values: int[]) -> int, mut values: int[]) -> int:\n    return callback(mut values)\n" ++
            "func main() -> int:\n    mut values = [41]\n    return apply(increment, mut values)\n",
        42,
    );
}

// spec-case: CALLBACK-1
test "cached callable recipes reject a changed mutation ABI like a cold check" {
    var cache = language.semantic_cache.Cache.init(t.allocator, 1024 * 1024);
    defer cache.deinit();
    const matching =
        "func read(mut values: int[]) -> int:\n    return len(values)\n" ++
        "func apply(callback: func(mut values: int[]) -> int, mut values: int[]) -> int:\n    return callback(mut values)\n" ++
        "func unrelated() -> int:\n    return 7\n" ++
        "func main() -> int:\n    mut values = [42]\n    return apply(read, mut values) + unrelated() - 7\n";
    var first = try language.Compilation.init(t.allocator, "callback-cache.selka", matching);
    defer first.deinit();
    try first.checkWithCache(&cache);
    const changed = try std.mem.replaceOwned(u8, t.allocator, matching, "func read(mut values", "func read(values");
    defer t.allocator.free(changed);
    var warm = try language.Compilation.init(t.allocator, "callback-cache.selka", changed);
    defer warm.deinit();
    try t.expectError(error.SourceError, warm.checkWithCache(&cache));
    try t.expectEqualStrings("E_TYPE", warm.diagnostics.items[0].code);
    try t.expect(cache.statistics.reused >= 1);
    var cold = try language.Compilation.init(t.allocator, "callback-cache.selka", changed);
    defer cold.deinit();
    try t.expectError(error.SourceError, cold.check());
    try t.expectEqualStrings(cold.diagnostics.items[0].code, warm.diagnostics.items[0].code);
    try t.expectEqualStrings(cold.diagnostics.items[0].message, warm.diagnostics.items[0].message);
    try t.expectEqual(cold.diagnostics.items[0].span, warm.diagnostics.items[0].span);
}
