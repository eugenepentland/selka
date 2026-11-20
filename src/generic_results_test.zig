//! Result obligations in uninstantiated templates and their executable specializations.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const schema =
    \\result R:
    \\    ok: i64,
    \\    err: i64
    \\
    \\
    \\
;
fn reject(body: []const u8, code: []const u8) !void {
    const bytes = try std.mem.concat(t.allocator, u8, &.{
        schema, body, "\n\n\n",
        \\func main() -> i64:
        \\    return 0
    });
    defer t.allocator.free(bytes);
    var c = try language.Compilation.init(t.allocator, "generic-result-invalid.selka", bytes);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
    if (std.mem.eql(u8, code, "E_RESULT_CONSUMED")) try t.expectEqual(language.ownership_rules.Rule.L1, c.diagnostics.items[0].provenance.rule.?);
}
fn run(bytes: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "generic-result.selka", bytes);
    defer c.deinit();
    try t.expectEqual(expected, (try native.run(&c)).value);
}
const scenario_source = schema ++
    \\func step[T](r: R) -> R:
    \\    const value = try r
    \\    return R.ok(value + 1)
    \\
    \\
    \\func consume(r: R) -> bool:
    \\    _ = r
    \\    return True
    \\
    \\
    \\func flow[T](flag: bool, r: R) -> i64:
    \\    if flag:
    \\        _ = r
    \\        return 1
    \\    _ = r
    \\    mut n = 0
    \\    mut item = R.ok(0)
    \\    while n < 3:
    \\        _ = item
    \\        item = R.err(n)
    \\        n += 1
    \\    _ = item
    \\    _ = False and consume(R.err(1))
    \\    return n
    \\
    \\
    \\func main() -> i64:
    \\    mut n = flow[bool](True, R.ok(1)) + flow[bool](False, R.err(2))
    \\    match step[bool](R.ok(4)):
    \\        case ok(value):
    \\            return value + n
    \\        case err(_):
    \\            return 0
;
const nested_source = schema ++
    \\enum U:
    \\    a(value: R)
    \\    b
    \\
    \\
    \\func make[T: integer](n: T) -> R:
    \\    return R.ok(i64(n))
    \\
    \\
    \\func my_take[T](u: U) -> i64:
    \\    match u:
    \\        case a(value=r):
    \\            match r:
    \\                case ok(n):
    \\                    return n
    \\                case err(n):
    \\                    return 0 - n
    \\        case b:
    \\            return 0
    \\
    \\
    \\func main() -> i64:
    \\    return my_take[bool](U.a(value=make[u8](7u8))) + my_take[bool](U.a(value=R.err(2))) + my_take[bool](U.b)
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "generic-results.selka", scenario_source);
    defer c.deinit();
    try t.expectEqual(@as(i64, 9), (try native.run(&c)).value);
}
test "generic result construction nested matching and native emission survive allocation failures" {
    try run(nested_source, 5);
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}

test "generic branches restore result state and merge only continuing paths" {
    try reject(
        \\func f[T](flag: bool, r: R) -> i64:
        \\    if flag:
        \\        _ = r
        \\    return 0
    , "E_RESULT_PATH");
    try reject(
        \\func f[T](flag: bool, r: R) -> i64:
        \\    if flag:
        \\        return 0
        \\    _ = r
        \\    return 1
    , "E_RESULT_UNHANDLED");
    try run(schema ++
        \\func f[T](flag: bool, r: R) -> i64:
        \\    if flag:
        \\        _ = r
        \\        return 1
        \\    _ = r
        \\    return 2
        \\
        \\
        \\func main() -> i64:
        \\    return f[bool](True, R.err(3)) + f[bool](False, R.ok(4))
    , 3);
    try run(schema ++
        \\func f[T](flag: bool, r: R) -> i64:
        \\    if flag:
        \\        _ = r
        \\    else:
        \\        _ = r
        \\    return 7
        \\
        \\
        \\func main() -> i64:
        \\    return f[bool](True, R.err(3)) + f[bool](False, R.ok(4))
    , 14);
}

test "generic matches transfer nested payloads and merge outer obligations" {
    try reject(
        \\enum E:
        \\    a
        \\    b
        \\
        \\
        \\func f[T](e: E, r: R) -> i64:
        \\    match e:
        \\        case a:
        \\            _ = r
        \\        case b:
        \\            pass
        \\    return 0
    , "E_RESULT_PATH");
    try reject(
        \\enum U:
        \\    a(value: R)
        \\    b
        \\
        \\
        \\func f[T](u: U) -> i64:
        \\    match u:
        \\        case a(value=_):
        \\            pass
        \\        case b:
        \\            pass
        \\    return 0
    , "E_RESULT_DISCARD");
    try reject(
        \\enum U:
        \\    a(value: R)
        \\    b
        \\
        \\
        \\func f[T](u: U) -> i64:
        \\    match u:
        \\        case a(value=r):
        \\            pass
        \\        case b:
        \\            pass
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try run(schema ++
        \\enum E:
        \\    a
        \\    b
        \\
        \\
        \\func f[T](e: E, r: R) -> i64:
        \\    match e:
        \\        case a:
        \\            _ = r
        \\            return 1
        \\        case b:
        \\            pass
        \\    _ = r
        \\    return 2
        \\
        \\
        \\func main() -> i64:
        \\    return f[bool](E.a, R.err(3)) + f[bool](E.b, R.ok(4))
    , 3);
}

test "generic acknowledgement retains operand traps" {
    var c = try language.Compilation.init(t.allocator, "generic-result-trap.selka", schema ++
        \\func f[T: integer](n: T) -> i64:
        \\    _ = R.err(divtrunc(7, i64(n)))
        \\    return 0
        \\
        \\
        \\func main() -> i64:
        \\    return f[u8](0u8)
    );
    defer c.deinit();
    try t.expectEqualStrings("R_DIVISION_BY_ZERO", (try native.run(&c)).trap.code);
}

// spec: GENERIC-RESULT-1
test "uncalled generic templates cannot drop duplicate or overwrite results" {
    try reject(
        \\func f[T](r: R) -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\func f[T]() -> i64:
        \\    mut r = R.ok(1)
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\func f[T](r: R) -> i64:
        \\    mut moved = r
        \\    _ = r
        \\    _ = moved
        \\    return 0
    , "E_RESULT_CONSUMED");
    try reject(
        \\func f[T]() -> i64:
        \\    mut r = R.ok(1)
        \\    r = R.err(2)
        \\    _ = r
        \\    return 0
    , "E_RESULT_OVERWRITE");
}

// spec: OPTION-TRY-2
test "generic option propagation unwraps Some forwards None and rejects a result return" {
    try run(
        \\func forward[T](value: T?) -> T?:
        \\    mut item = try value
        \\    return Some(item)
        \\
        \\
        \\func main() -> i64:
        \\    match forward[i64](Some(41)):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            return 0
    , 41);
    try run(
        \\func forward[T](value: T?) -> T?:
        \\    mut item = try value
        \\    return Some(item)
        \\
        \\
        \\func main() -> i64:
        \\    match forward[i64](None):
        \\        case Some(value):
        \\            return value
        \\        case None:
        \\            return 7
    , 7);
    try reject(
        \\func broken[T](value: T?) -> i64:
        \\    return try value
    , "E_TRY_RETURN");
}

test "F3 pending Result fixed array writes retain L1 independently of B1" {
    // migrate-embedded: skip original fixed-array Result overwrite refusal
    try reject(
        \\func my_write[T](own values: FixedArray[R, 1]):
        \\    values[0] = R.ok(2)
    , "E_RESULT_CONSUMED");
    // migrate-embedded: skip original consumed fixed-array Result refusal
    try reject(
        \\func my_write[T](own values: FixedArray[R, 1]):
        \\    _ = values
        \\    values[0] = R.ok(2)
    , "E_RESULT_CONSUMED");
}

test "F3 consumed Result field and tuple targets retain their availability checks" {
    // migrate-embedded: skip original consumed Result field target refusal
    try reject(
        \\record Box:
        \\    result: R
        \\func my_write[T](own box: Box):
        \\    _ = box
        \\    box.result = R.ok(2)
    , "E_RESULT_CONSUMED");
    // migrate-embedded: skip original consumed Result tuple-place refusal
    try reject(
        \\record Box:
        \\    result: R
        \\func my_write[T](own box: Box):
        \\    _ = box
        \\    mut count = 0
        \\    box.result, count = (R.ok(2), 3)
    , "E_RESULT_CONSUMED");
}

test "F3 acknowledged Result arrays and writable ordinary arrays remain accepted" {
    var compilation = try language.Compilation.init(t.allocator, "f3-result-array-controls.selka", schema ++
        \\func acknowledge[T](own values: FixedArray[R, 1]):
        \\    _ = values
        \\func my_write[T](own values: FixedArray[i64, 1]):
        \\    values[0] = 2
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 1), compilation.program.?.functions.len);
}
