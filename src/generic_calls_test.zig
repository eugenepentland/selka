//! Generic calls preserve requirements, nominal namespaces, and symbolic identities.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const diagnostic = @import("diagnostic.zig");
const bodies = @import("generic_bodies.zig");
// A domain-qualified call may name its type argument explicitly: `D.hidden[U](x)`.
const declarations =
    \\func identity[U](x: U) -> U:
    \\    return x
    \\
    \\
    \\func numeric[N: integer](x: N) -> N:
    \\    return x
    \\
    \\
    \\
;
const valid = declarations ++
    \\func duo[A: integer, B](x: A, y: B) -> B:
    \\    _ = x
    \\    return y
    \\
    \\
    \\func permute[T, U: integer](x: T, y: U) -> T:
    \\    return duo[U, T](y, x)
    \\
    \\
    \\func forward[T: integer](x: T) -> T:
    \\    return identity[T](numeric[T](x))
    \\
    \\
    \\func concrete[T](x: T) -> i64:
    \\    _ = identity[T](x)
    \\    return numeric[i64](3)
    \\
    \\
    \\func recurse[T: integer](x: T) -> T:
    \\    if x == T(0):
    \\        return x
    \\    return recurse[T](x - T(1))
    \\
    \\
    \\func first[T](x: T) -> T:
    \\    return second[T](x)
    \\
    \\
    \\func second[U](x: U) -> U:
    \\    return first[U](x)
    \\
    \\
    \\domain D: i64:
    \\    private func hidden[T](x: T) -> T:
    \\        return x
    \\
    \\    func public[U](x: U) -> U:
    \\        return D.hidden[U](x)
    \\
    \\
    \\func main() -> i64:
    \\    return 0
;
fn scenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, "calls.selka", valid);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
// spec: GENERIC-CALL-1
test "generic calls forward contracts substitute types and check recursion without body expansion" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
const helpers =
    \\func leaf(x: i64) -> i64:
    \\    return numeric[i64](x)
    \\
    \\
    \\func middle(x: i64) -> i64:
    \\    return leaf(x) + leaf(x)
    \\
    \\
    \\func even(x: i64) -> bool:
    \\    if x == 0:
    \\        return True
    \\    return odd(x - 1)
    \\
    \\
    \\func odd(x: i64) -> bool:
    \\    if x == 0:
    \\        return False
    \\    return even(x - 1)
    \\
    \\
    \\func generic[T](x: T) -> i64:
    \\    _ = x
    \\    if even(4):
    \\        return middle(3)
    \\    return leaf(2)
    \\
    \\
    \\func unused(c: Clock) -> i64:
    \\    _ = clock_now[Time](c)
    \\    return 0
    \\
    \\
    \\
;
fn helperScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.initTrusted(allocator, "helpers.selka", declarations ++ helpers);
    defer compilation.deinit();
    try compilation.parse();
    var sink: diagnostic.Sink = .{ .allocator = compilation.arena.allocator() };
    try bodies.check(allocator, compilation.src, compilation.syntax.?, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
// spec: GENERIC-HELPER-1
test "generic calls check reachable concrete helpers transitively without expanding recursion" {
    try helperScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), helperScenario, .{});
}

test "generic calls reject invalid contracts identities arity and private access" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body =
        \\func f[T](x: T) -> T:
        \\    return numeric[T](x)
        , .code = "E_GENERIC_ARGUMENT" },
        .{ .body =
        \\func f[T](x: T) -> bool:
        \\    _ = x
        \\    return numeric[bool](True)
        , .code = "E_GENERIC_ARGUMENT" },
        .{ .body =
        \\func f[T, U](x: T, y: U) -> U:
        \\    _ = y
        \\    return identity[U](x)
        , .code = "E_GENERIC_TYPE" },
        .{ .body =
        \\func f[T](x: T) -> T:
        \\    return identity[T, T](x)
        , .code = "E_GENERIC_ARITY" },
        .{ .body =
        \\func f[T](x: T) -> T:
        \\    return identity[T](x, x)
        , .code = "E_ARITY" },
        .{ .body =
        \\func f[T](x: T) -> T:
        \\    return missing(x)
        , .code = "E_UNKNOWN_FUNCTION" },
        .{ .body =
        \\domain D: i64:
        \\    private func hidden[T](x: T) -> T:
        \\        return x
        \\
        \\
        \\domain E: i64:
        \\    func f[T](x: T) -> T:
        \\        return D.hidden[T](x)
        , .code = "E_PRIVATE_FUNCTION" },

        .{ .body =
        \\domain D: i64:
        \\    private func hidden[T](x: T) -> T:
        \\        return x
        \\
        \\
        \\func f[T](x: T) -> T:
        \\    return D.hidden[T](x)
        , .code = "E_PRIVATE_FUNCTION" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{
            declarations, case.body, "\n\n\n",
            \\func main() -> i64:
            \\    return 0
        });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "bad.selka", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "generic calls reject hidden effects and invalid concrete helper bodies" {
    const cases = [_]struct { body: []const u8, code: []const u8 }{
        .{ .body =
        \\func helper(x: i64) -> i64:
        \\    return True
        , .code = "E_GENERIC_TYPE" },
        .{ .body =
        \\func helper(x: i64) -> i64:
        \\    if x == 0:
        \\        return 0
        , .code = "E_MISSING_RETURN" },
        .{ .body =
        \\func helper(x: bool) -> i64:
        \\    _ = x
        \\    return 0
        , .code = "E_GENERIC_TYPE" },
        .{ .body =
        \\func helper[T, U](x: T) -> T:
        \\    return x
        , .code = "E_GENERIC_INFERENCE" },
    };
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{
            case.body, "\n\n\n",
            \\func f[T](x: T) -> i64:
            \\    _ = x
            \\    return helper(1)
        });
        defer t.allocator.free(text);
        var compilation = try language.Compilation.init(t.allocator, "invalid-helper.selka", text);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings(case.code, compilation.diagnostics.items[0].code);
    }
}

test "generic calls reject reachable clock effects even behind cycles and false branches" {
    const effectful =
        \\result Time:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func helper(c: Clock) -> i64:
        \\    return hidden(c)
        \\
        \\
        \\func hidden(c: Clock) -> i64:
        \\    if False:
        \\        _ = clock_now[Time](c)
        \\        return helper(c)
        \\    return 0
        \\
        \\
        \\
    ;
    var ordinary = try language.Compilation.initTrusted(t.allocator, "ordinary.selka", effectful ++
        \\func main(c: Clock) -> i64:
        \\    return helper(c)
    );
    defer ordinary.deinit();
    try ordinary.check();
    var generic = try language.Compilation.initTrusted(t.allocator, "generic.selka", effectful ++
        \\func f[T](x: T, c: Clock) -> i64 effects():
        \\    _ = x
        \\    return helper(c)
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer generic.deinit();
    try t.expectError(error.SourceError, generic.check());
    try t.expectEqualStrings("E_EFFECT_BOUND", generic.diagnostics.items[0].code);
    try t.expectEqualStrings("effects()", generic.src.text(generic.diagnostics.items[0].span));
}
