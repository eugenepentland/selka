//! Typed noncapturing callbacks preserve signatures, effects and ordinary ownership transfers.
const std = @import("std");
const print = std.debug.print;
const t = std.testing;
const language = @import("compiler.zig");
fn run(source: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, "callback.my", source);
    defer c.deinit();
    const outcome = c.execute(t.allocator) catch |err| {
        for (c.diagnostics.items) |d| print("{s}: {s} ({s})\n", .{ d.code, d.message, c.src.text(d.span) });
        return err;
    };
    try t.expectEqual(expected, outcome.value);
}
// spec: CALLBACK-1
test "callbacks infer function values and invoke passed exact signatures" {
    try run("fn inc(x:i64)->i64 effects(){return x+1;}fn main()->i64{let f=inc;return f(4);}", 5);
    try run("fn inc(x:i64)->i64 effects(){return x+1;}fn apply(f:fn(i64)->i64 effects(),x:i64)->i64{return f(x);}" ++
        "fn main()->i64{return apply(inc,8);}", 9);
}

fn reject(source: []const u8, code: []const u8) !void {
    const complete = try std.mem.concat(t.allocator, u8, &.{ source, if (std.mem.indexOf(u8, source, "fn main") == null) "fn main()->i64{return 0;}" else "" });
    defer t.allocator.free(complete);
    var c = try language.Compilation.init(t.allocator, "invalid-callback.my", complete);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

const allocation_source = "struct Box{value:[2]i64}fn make(ctx:&i64,n:i64)->Box effects(){return new Box{value:new [2]i64 [n+read_ref(ctx),n+1]};}" ++
    "fn apply<T:copy>(f:fn(&T,i64)->Box effects(),ctx:&T,n:i64)->Box{return f(ctx,n);}" ++
    "fn main()->i64{let context=0;borrow context as ctx{let a=apply::<i64>(make,ctx,7);let f=make;let b=f(ctx,9);return a.value[0]+b.value[1];}}";

fn allocationScenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "allocation-callback.my", allocation_source);
    defer c.deinit();
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var copy = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer copy.deinit();
    try t.expectEqual(@as(i64, 17), (try copy.execute(allocator)).value);
}

test "callbacks compile format execute and emit under every failed allocation" {
    try allocationScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), allocationScenario, .{});
}

const module_source = "module main;import std_collections as c;" ++
    "fn descending(a:i64,b:i64)->bool effects(){return a>b;}fn twice(x:i64)->i64 effects(){return x*2;}" ++
    "fn main()->i64{let mut a=new [4]i64 [3,1,4,2];borrow mut a[0..4] as view{" ++
    "discard c::sort_by_i64(view,descending);discard c::transform_i64(view,twice);}return a[0]*10+a[3];}";
fn moduleRead(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
    if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
    if (module_source.len > limit) return error.TooLarge;
    return allocator.dupe(u8, module_source);
}

test "callbacks drive standard library sorting and visitors across module boundaries" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = moduleRead });
    defer program.deinit();
    try t.expectEqual(@as(i64, 82), (try language.vm.run(t.allocator, program.compilation.code.?)).value);
}

test "callbacks reject forged target signatures and invalid dynamic calls" {
    const source = "fn f(x:i64)->i64 effects(){return x;}fn g(x:bool)->i64 effects(){return 0;}" ++
        "fn main()->i64{let cb=f;return cb(1);}";
    var c = try language.Compilation.init(t.allocator, "forged-callback.my", source);
    defer c.deinit();
    try c.emit();
    const original = c.code.?;
    const functions = try t.allocator.dupe(language.bytecode.Function, original.functions);
    defer t.allocator.free(functions);
    const main_index = @backingInt(original.main);
    const instructions = try t.allocator.dupe(language.bytecode.Instruction, functions[main_index].scope.instructions);
    defer t.allocator.free(instructions);
    functions[main_index].scope.instructions = instructions;
    var program = original;
    program.functions = functions;
    const instruction = try functionInstruction(instructions);
    const saved = instruction.*;
    instruction.op.function_value.function = @fromBackingInt(1);
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    instruction.* = saved;
    instruction.op.function_value.function = @fromBackingInt(functions.len);
    try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
    instruction.* = saved;
}

fn functionInstruction(instructions: []language.bytecode.Instruction) !*language.bytecode.Instruction {
    for (instructions) |*instruction| if (instruction.op == .function_value) return instruction;
    try t.expect(false);
    unreachable;
}

const ContextFixture = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const source = @embedFile("stdlib/fixtures/callback_context.my");
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (source.len > limit) return error.TooLarge;
        return allocator.dupe(u8, source);
    }
};
// spec: CALLBACK-ALGORITHMS-1
test "generic collection callbacks sort search and filter borrowed JSON document IDs with explicit ties" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = ContextFixture.read });
    defer program.deinit();
    const outcome = try language.vm.run(t.allocator, program.compilation.code.?);
    try t.expectEqual(@as(i64, 42), outcome.value);
}

fn invokeInstruction(instructions: []language.bytecode.Instruction) !*language.bytecode.Instruction {
    for (instructions) |*instruction| if (instruction.op == .invoke) return instruction;
    try t.expect(false);
    unreachable;
}
