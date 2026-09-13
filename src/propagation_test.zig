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
    "mut counter = 0; borrow mut counter as r { write_ref(r, 1); return new Outer.ok(new " ++
    "[2]Item [new Item { n: 3 }, new Item { n: fail(flag)? }]); } } fn main() -> i64 { " ++
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
