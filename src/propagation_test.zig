//! Error propagation with `?`: unwrapping success, forwarding compatible error
//! payloads by case name, and the cleanup each propagation path performs.
const fixture_path = "propagation.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const declaration = @import("fixture_declarations_test.zig").scalar_result;
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try native.run(&compilation)).value);
}
fn reject(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(testing.allocator, u8, &.{ declaration, body });
    defer testing.allocator.free(source);
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const owned_source =
    \\class Item:
    \\    n: i64
    \\
    \\
    \\class Error:
    \\    detail: [2]Item
    \\
    \\
    \\result Inner:
    \\    ok: i64,
    \\    err: Error
    \\
    \\
    \\result Outer:
    \\    err: Error,
    \\    ok: [2]Item
    \\
    \\
    \\def fail(flag: bool) -> Inner:
    \\    if flag:
    \\        return Err(Error(detail=[Item(n=7), Item(n=8)]))
    \\    return Ok(9)
    \\
    \\
    \\def build(flag: bool) -> Outer:
    \\    counter = 0
    \\    counter = 1
    \\    _ = counter
    \\    return Ok([Item(n=3), Item(n=fail(flag)?)])
    \\
    \\
    \\def main() -> i64:
    \\    match build(True):
    \\        case Outer.ok(items):
    \\            return items[1].n
    \\        case Outer.err(error):
    \\            return error.detail[0].n
;
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 7), (try native.run(&compilation)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "propagation releases partial aggregate operands and survives every allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    const success = try std.mem.replaceOwned(u8, testing.allocator, owned_source, "match build(True)", "match build(False)");
    defer testing.allocator.free(success);
    try result(success, 9);
}

test "bytecode validates propagation result identity and failure stack targets" {
    var compilation = try language.Compilation.init(testing.allocator, "invalid-try.my", owned_source);
    defer compilation.deinit();
    try compilation.emit();
    const original = compilation.code.?;
    const functions = try testing.allocator.dupe(language.bytecode.Function, original.functions);
    defer testing.allocator.free(functions);
    const instructions = try testing.allocator.dupe(language.bytecode.Instruction, functions[1].scope.instructions);
    defer testing.allocator.free(instructions);
    functions[1].scope.instructions = instructions;
    var program = original;
    program.functions = functions;
    const propagation = try @import("instruction_test.zig").index(instructions, .try_result);
    instructions[propagation].op.try_result.error_target = instructions.len;
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    instructions[propagation] = original.functions[1].scope.instructions[propagation];
    instructions[propagation].op.try_result.output = .i64;
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
    instructions[propagation] = original.functions[1].scope.instructions[propagation];
    instructions[propagation].op.try_result.input = .bool;
    try testing.expectError(error.InternalError, language.bytecode.validate(testing.allocator, program));
}

// spec: CORE-11
test "try unwraps success and remaps errors between nominal result types by named cases" {
    try result(
        \\enum E:
        \\    missing
        \\
        \\
        \\result Input:
        \\    err: E,
        \\    ok: i64
        \\
        \\
        \\result Output:
        \\    ok: bool,
        \\    err: E
        \\
        \\
        \\def test_value(r: Input) -> Output:
        \\    return Ok(r? > 5)
        \\
        \\
        \\def handle(r: Output) -> i64:
        \\    match r:
        \\        case Output.ok(value):
        \\            if value:
        \\                return 7
        \\            return 1
        \\        case Output.err(e):
        \\            match e:
        \\                case E.missing:
        \\                    return 3
        \\
        \\
        \\def main() -> i64:
        \\    return handle(test_value(Ok(8))) + handle(test_value(Err(E.missing)))
    , 10);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def f(r: R) -> R:
        \\    return Ok(2 * r? + 1)
        \\
        \\
        \\def main() -> i64:
        \\    match f(Ok(3)):
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(ignored):
        \\            return 0
    , 7);
}

test "propagation cannot abandon pending locals parameters or unfinished expression results" {
    try reject(
        \\def f(r: R, other: R) -> R:
        \\    return R.ok(r?)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\def f(r: R) -> R:
        \\    ignored = R.err(3)
        \\    value = r?
        \\    _ = ignored
        \\    return R.ok(value)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_UNHANDLED");
    try reject(
        \\def consume(r: R, n: i64) -> i64:
        \\    _ = r
        \\    return n
        \\
        \\
        \\def f(r: R) -> R:
        \\    return R.ok(consume(R.err(7), r?))
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_PROPAGATION");
    try reject(
        \\class Wrapper:
        \\    r: R
        \\
        \\
        \\def consume(w: Wrapper, n: i64) -> i64:
        \\    _ = w
        \\    return n
        \\
        \\
        \\def f(r: R) -> R:
        \\    first = R.err(7)
        \\    return R.ok(consume(Wrapper(r=first), r?))
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_PROPAGATION");
    try reject(
        \\class Pair:
        \\    first: R
        \\    second: i64
        \\
        \\
        \\result Wrapped:
        \\    ok: Pair,
        \\    err: i64
        \\
        \\
        \\def f(r: R) -> Wrapped:
        \\    return Ok(Pair(first=R.err(7), second=r?))
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    , "E_RESULT_PROPAGATION");
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def f(r: R, other: R) -> R:
        \\    _ = other
        \\    return Ok(r?)
        \\
        \\
        \\def main() -> i64:
        \\    match f(Err(7), Ok(1)):
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
    , 7);
}

test "nested results can be propagated repeatedly or explicitly acknowledged after unwrapping" {
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\result Outer:
        \\    ok: R,
        \\    err: i64
        \\
        \\
        \\def flatten(r: Outer) -> R:
        \\    return Ok(r??)
        \\
        \\
        \\def handle(r: R) -> i64:
        \\    match r:
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
        \\
        \\
        \\def main() -> i64:
        \\    return handle(flatten(Ok(Ok(1)))) + handle(flatten(Ok(Err(2)))) + handle(flatten(Err(3)))
    , 6);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\result Outer:
        \\    ok: R,
        \\    err: i64
        \\
        \\
        \\def f(r: Outer) -> R:
        \\    _ = r?
        \\    return Ok(7)
        \\
        \\
        \\def main() -> i64:
        \\    match f(Ok(Err(3))):
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
    , 7);
    try result(
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\result Outer:
        \\    ok: R,
        \\    err: i64
        \\
        \\
        \\def f(r: Outer) -> R:
        \\    _ = r?
        \\    return Ok(5)
        \\
        \\
        \\def main() -> i64:
        \\    match f(Ok(Ok(1))):
        \\        case R.ok(n):
        \\            return n
        \\        case R.err(e):
        \\            return e
    , 5);
}

test "duplicate discovery retains propagation operations and target result types" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my",
        \\result R:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\def a(r: R) -> R:
        \\    return Ok(r? + 1)
        \\
        \\
        \\def b(other: R) -> R:
        \\    return Ok(other? + 1)
        \\
        \\
        \\def c(r: R) -> R:
        \\    match r:
        \\        case R.ok(n):
        \\            return Ok(n + 1)
        \\        case R.err(e):
        \\            return Err(e)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}
