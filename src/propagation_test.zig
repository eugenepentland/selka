const fixture_path = "propagation.my";
const std = @import("std");
const testing = std.testing;
const language = @import("compiler.zig");
const LimitedLiveAllocator = @import("test_support.zig").LimitedLiveAllocator;
const declaration = @import("fixture_declarations_test.zig").scalar_result;
fn result(source: []const u8, expected: i64) !void {
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectEqual(expected, (try compilation.execute(testing.allocator)).value);
}
fn reject(body: []const u8, code: []const u8) !void {
    const source = try std.mem.concat(testing.allocator, u8, &.{ declaration, body });
    defer testing.allocator.free(source);
    var compilation = try language.Compilation.init(testing.allocator, fixture_path, source);
    defer compilation.deinit();
    try testing.expectError(error.SourceError, compilation.check());
    try testing.expectEqualStrings(code, compilation.diagnostics.items[0].code);
}

const owned_source = "struct Item { n: i64 } struct Error { detail: [2]Item } result Inner { ok: i64, err: " ++
    "Error } result Outer { err: Error, ok: [2]Item } fn fail(flag: bool) -> Inner { if " ++
    "flag { return new Inner.err(new Error { detail: new [2]Item [new Item { n: 7 }, new " ++
    "Item { n: 8 }] }); } return new Inner.ok(9); } fn build(flag: bool) -> Outer { let " ++
    "mut counter = 0; counter = 1; _ = counter; return new Outer.ok(new " ++
    "[2]Item [new Item { n: 3 }, new Item { n: fail(flag)? }]); } fn main() -> i64 { " ++
    "match build(true) { Outer.ok(items) => { return items[1].n; }, Outer.err(error) => { " ++
    "return error.detail[0].n; } } }";
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var compilation = try language.Compilation.init(allocator, fixture_path, owned_source);
    defer compilation.deinit();
    try testing.expectEqual(@as(i64, 7), (try compilation.execute(allocator)).value);
    const dump = try compilation.dump(allocator);
    defer allocator.free(dump);
    var discovery = try language.duplicates.discover(allocator, compilation.program.?, .{});
    defer discovery.deinit();
}

test "propagation releases partial aggregate operands and survives every allocation failure" {
    var no_resize = testing.FailingAllocator.init(testing.allocator, .{ .resize_fail_index = 0 });
    try testing.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{});
    const success = try std.mem.replaceOwned(u8, testing.allocator, owned_source, "match build(true)", "match build(false)");
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
    try result("enum E { missing } result Input { err: E, ok: i64 } result Output { ok: bool, err: E " ++
        "} fn test_value(r: Input) -> Output { return new Output.ok(r? > 5); } fn " ++
        "handle(r: Output) -> i64 { match r { Output.ok(value) => { if value { return 7; } " ++
        "return 1; }, Output.err(e) => { match e { E.missing => { return 3; } } } } } fn " ++
        "main() -> i64 { return handle(test_value(new Input.ok(8))) + handle(test_value(new " ++
        "Input.err(new E.missing))); }", 10);
    try result("result R { ok: i64, err: i64 } fn f(r: R) -> R { return new R.ok(2 * r? + 1); } fn main() -> i64 { match f(new R.ok(3)) { R.ok(n) => { return n; }, R.err(ignored) => { return 0; } } }", 7);
}

test "propagation cannot abandon pending locals parameters or unfinished expression results" {
    try reject("fn f(r: R, other: R) -> R { return new R.ok(r?); } fn main() -> i64 { return 0; }", "E_RESULT_UNHANDLED");
    try reject("fn f(r: R) -> R { let ignored = new R.err(3); let value = r?; _ = ignored; return new R.ok(value); } fn main() -> i64 { return 0; }", "E_RESULT_UNHANDLED");
    try reject("fn consume(r: R, n: i64) -> i64 { _ = r; return n; } fn f(r: R) -> R { return new R.ok(consume(new R.err(7), r?)); } fn main() -> i64 { return 0; }", "E_RESULT_PROPAGATION");
    try reject("struct Wrapper { r: R } fn consume(w: Wrapper, n: i64) -> i64 { _ = w; " ++
        "return n; } fn f(r: R) -> R { let first = new R.err(7); return new R.ok(consume(new " ++
        "Wrapper { r: first }, r?)); } fn main() -> i64 { return 0; }", "E_RESULT_PROPAGATION");
    try reject("struct Pair { first: R, second: i64 } result Wrapped { ok: Pair, err: i64 } fn f(r: " ++
        "R) -> Wrapped { return new Wrapped.ok(new Pair { first: new R.err(7), second: r? }" ++
        "); } fn main() -> i64 { return 0; }", "E_RESULT_PROPAGATION");
    try result("result R { ok: i64, err: i64 } fn f(r: R, other: R) -> R { _ = other; return new R.ok(r?); } fn main() -> i64 { match f(new R.err(7), new R.ok(1)) { R.ok(n) => { return n; }, R.err(e) => { return e; } } }", 7);
}

test "nested results can be propagated repeatedly or explicitly acknowledged after unwrapping" {
    try result("result R { ok: i64, err: i64 } result Outer { ok: R, err: i64 } fn flatten(r: Outer) " ++
        "-> R { return new R.ok(r??); } fn handle(r: R) -> i64 { match r { R.ok(n) => { " ++
        "return n; }, R.err(e) => { return e; } } } fn main() -> i64 { return " ++
        "handle(flatten(new Outer.ok(new R.ok(1)))) + handle(flatten(new Outer.ok(new " ++
        "R.err(2)))) + handle(flatten(new Outer.err(3))); }", 6);
    try result("result R { ok: i64, err: i64 } result Outer { ok: R, err: i64 } fn f(r: Outer) -> R " ++
        "{ _ = r?; return new R.ok(7); } fn main() -> i64 { match f(new " ++
        "Outer.ok(new R.err(3))) { R.ok(n) => { return n; }, R.err(e) => { return e; } } }", 7);
    try reject("result Outer { ok: R, err: i64 } fn f(r: Outer) -> R { _ = r?; return new R.ok(0); } fn main() -> i64 { return 0; }", "E_RESULT_DISCARD");
}

test "duplicate discovery retains propagation operations and target result types" {
    var compilation = try language.Compilation.init(testing.allocator, "duplicates.my", "result R { ok: i64, err: i64 } fn a(r: R) -> R { return new R.ok(r? + 1); } fn " ++
        "b(other: R) -> R { return new R.ok(other? + 1); } fn c(r: R) -> R { match r { " ++
        "R.ok(n) => { return new R.ok(n + 1); }, R.err(e) => { return new R.err(e); } } } fn " ++
        "main() -> i64 { return 0; }");
    defer compilation.deinit();
    try compilation.check();
    var discovery = try language.duplicates.discover(testing.allocator, compilation.program.?, .{ .min_nodes = 1 });
    defer discovery.deinit();
    try testing.expectEqual(@as(usize, 1), discovery.groups.len);
    try testing.expectEqual(@as(usize, 2), discovery.groups[0].members.len);
}
