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
// spec: CALLBACK-1
test "callbacks infer function values and invoke passed exact signatures" {
    try run(
        \\def inc(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def main() -> i64:
        \\    f = inc
        \\    return f(4)
    , 5);
    try run(
        \\def inc(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def apply(f: def(i64) -> i64 effects(), x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\def main() -> i64:
        \\    return apply(inc, 8)
    , 9);
}

// spec: PY-LAMBDA-1
test "expression lambdas use an expected callback signature and invoke correctly" {
    try run(
        \\def apply(f: def(int) -> int effects(), value: int) -> int:
        \\    return f(value)
        \\
        \\
        \\def main() -> int:
        \\    return apply(lambda value: value + 2, 40)
    , 42);
    try run(
        \\const OFFSET: int = 2
        \\
        \\
        \\def apply(f: def(int) -> int effects(), value: int) -> int:
        \\    return f(value)
        \\
        \\
        \\def main() -> int:
        \\    return apply(lambda value: value + OFFSET, 40)
    , 42);
}

// spec: PY-LAMBDA-2
test "lambdas reject missing context wrong results effects and local captures" {
    try reject("def main() -> int:\n    f = lambda value: value\n    return 0\n", "E_LAMBDA_CONTEXT");
    try reject(
        "def apply(f: def(int) -> bool effects()) -> int:\n    return 0\n\ndef main() -> int:\n    return apply(lambda value: value + 1)\n",
        "E_TYPE",
    );
    try reject(
        "def apply(f: def(int) -> None effects()) -> int:\n    return 0\n\ndef main() -> int:\n    return apply(lambda value: print(value))\n",
        "E_EFFECT_BOUND",
    );
    var capture = try language.Compilation.init(
        t.allocator,
        "lambda-capture.my",
        "def apply(f: def(int) -> int effects()) -> int:\n    return f(1)\n\ndef main() -> int:\n    offset = 2\n    return apply(lambda value: value + offset)\n",
    );
    defer capture.deinit();
    try t.expectError(error.SourceError, capture.check());
    try t.expectEqualStrings("E_LAMBDA_CAPTURE", capture.diagnostics.items[0].code);
    try t.expectEqualStrings("offset", capture.src.text(capture.diagnostics.items[0].span));
}

// spec-case: CALLBACK-1
test "a callback type names itself the way the surface writes it" {
    var c = try language.Compilation.init(t.allocator, "callback-name.my",
        \\def apply(f: def(i64) -> i64 effects(), x: i64) -> i64:
        \\    return f(x)
        \\
        \\
        \\def main() -> i64:
        \\    return apply(7, 8)
    );
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_TYPE", c.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "def@") != null);
    try t.expect(std.mem.indexOf(u8, c.diagnostics.items[0].message, "fn") == null);
}

fn reject(source: []const u8, code: []const u8) !void {
    const complete = try std.mem.concat(t.allocator, u8, &.{
        source,
        if (std.mem.indexOf(u8, source, "def main") == null)
            \\def main() -> i64:
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
    \\class Box:
    \\    value: [2]i64
    \\
    \\
    \\def make(ctx: i64, n: i64) -> Box effects():
    \\    return Box(value=[n + ctx, n + 1])
    \\
    \\
    \\def apply[T](f: def(T, i64) -> Box effects(), ctx: T, n: i64) -> Box:
    \\    return f(ctx, n)
    \\
    \\
    \\def main() -> i64:
    \\    context = 0
    \\    a = apply[i64](make, context, 7)
    \\    f = make
    \\    b = f(context, 9)
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
    \\module main
    \\import helpers as c
    \\
    \\
    \\def descending(a: i64, b: i64) -> bool effects():
    \\    return a > b
    \\
    \\
    \\def twice(x: i64) -> i64 effects():
    \\    return x * 2
    \\
    \\
    \\def main() -> i64:
    \\    a: [4]i64 = [3, 1, 4, 2]
    \\    sorted = c.sort_by(a, descending)
    \\    doubled = c.transform(sorted, twice)
    \\    return doubled[0] * 10 + doubled[3]
;
const helpers_source =
    \\module helpers
    \\export sort_by
    \\export transform
    \\
    \\
    \\def sort_by(a: [4]i64, less: def(i64, i64) -> bool effects()) -> [4]i64:
    \\    v = a
    \\    i = 0
    \\    while i < 4:
    \\        j = 0
    \\        while j < 3:
    \\            if less(v[j + 1], v[j]):
    \\                tmp = v[j]
    \\                v = replace(v, j, v[j + 1])
    \\                v = replace(v, j + 1, tmp)
    \\            j += 1
    \\        i += 1
    \\    return v
    \\
    \\
    \\def transform(a: [4]i64, f: def(i64) -> i64 effects()) -> [4]i64:
    \\    v = a
    \\    i = 0
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
    \\module main
    \\
    \\
    \\def apply(f: def(int) -> int effects(), value: int) -> int:
    \\    return f(value)
    \\
    \\
    \\def main() -> int:
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

test "callbacks reject forged target signatures and invalid dynamic calls" {
    const source =
        \\def f(x: i64) -> i64 effects():
        \\    return x
        \\
        \\
        \\def g(x: bool) -> i64 effects():
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    cb = f
        \\    return cb(1)
    ;
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

fn invokeInstruction(instructions: []language.bytecode.Instruction) !*language.bytecode.Instruction {
    for (instructions) |*instruction| if (instruction.op == .invoke) return instruction;
    try t.expect(false);
    unreachable;
}

test "callbacks retain values through records arrays and ordinary generic forwarding" {
    try run(
        \\type F = def(i64) -> i64 effects()
        \\
        \\
        \\class Box[T]:
        \\    value: T
        \\
        \\
        \\def inc(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def get[T](b: Box[T]) -> T:
        \\    return b.value
        \\
        \\
        \\def repeat[T](f: F, x: i64, tag: T) -> i64:
        \\    _ = tag
        \\    return f(f(x))
        \\
        \\
        \\def main() -> i64:
        \\    b = Box[F](value=inc)
        \\    all: [1]F = [get[F](b)]
        \\    f = all[0]
        \\    return repeat[bool](f, 5, True)
    , 7);
    try run(
        \\def inc(x: i64) -> i64 effects():
        \\    return x + 1
        \\
        \\
        \\def choose() -> def(i64) -> i64 effects():
        \\    return inc
        \\
        \\
        \\def main() -> i64:
        \\    f = choose()
        \\    return f(8)
    , 9);
}

test "callbacks reject malformed invoke metadata and dispatch dynamically selected targets" {
    const source =
        \\def f(x: i64) -> i64 effects():
        \\    return x
        \\
        \\
        \\def g(x: bool) -> i64 effects():
        \\    return 0
        \\
        \\
        \\def main() -> i64:
        \\    unused = g
        \\    _ = unused
        \\    cb = f
        \\    return cb(1)
    ;
    var c = try language.Compilation.init(t.allocator, "malformed-invoke.my", source);
    defer c.deinit();
    try c.emit();
    var program = c.code.?;
    const functions = try t.allocator.dupe(language.bytecode.Function, program.functions);
    defer t.allocator.free(functions);
    const main_index = @backingInt(program.main);
    const instructions = try t.allocator.dupe(language.bytecode.Instruction, functions[main_index].scope.instructions);
    defer t.allocator.free(instructions);
    functions[main_index].scope.instructions = instructions;
    program.functions = functions;
    const other_signature = (try functionInstruction(instructions)).op.function_value.ty;
    for (instructions) |*instruction| {
        if (instruction.op != .invoke) continue;
        const saved = instruction.*;
        instruction.op.invoke = .i64;
        try t.expectError(error.InternalError, language.bytecode.validate(t.allocator, program));
        instruction.op.invoke = other_signature;
        // Stack-height validation cannot prove a dynamically selected callback's type.
        try language.bytecode.validate(t.allocator, program);
        instruction.* = saved;
        try t.expectEqual(@as(i64, 1), (try native.run(&c)).value);
        return;
    }
    try t.expect(false);
}
