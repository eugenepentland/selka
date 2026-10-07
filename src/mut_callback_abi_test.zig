//! MUT-REBIND-CALLER-1 callbacks retain their targets' published physical ABI.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const adapter = @import("mut_callback_abi.zig");
const t = std.testing;
const list: typed.Type = @fromBackingInt(typed.Type.record_base);
const callback: typed.Type = @fromBackingInt(typed.Type.record_base + 1);
const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };

fn fixture(a: std.mem.Allocator, mask: u16) !bytecode.Program {
    const records = try a.dupe(typed.Record, &.{
        .{ .id = list, .name = "list", .declaration = span, .fields = &.{}, .managed = true, .shape = .{ .buffer = .i64 } },
        .{
            .id = callback,
            .name = "callback",
            .declaration = span,
            .fields = &.{},
            .shape = .{ .domain = .u64 },
            .contract = .{ .callback = .{
                .parameters = &.{ list, list, list },
                .return_type = list,
                .effects = 0,
                .mutates = &.{ 0, 1 },
                .return_origin = .{ .params = &.{0} },
            } },
        },
    });
    const locals = try a.dupe(typed.Local, &.{
        .{ .name = "payload", .declaration = span, .ty = list, .mutable = true, .origin = .parameter },
        .{ .name = "storage", .declaration = span, .ty = list, .mutable = true, .origin = .parameter },
        .{ .name = "readonly", .declaration = span, .ty = list, .mutable = false, .origin = .parameter },
    });
    const main = try a.dupe(bytecode.Instruction, &.{
        .{ .span = span, .op = .{ .function_value = .{ .ty = callback, .function = @fromBackingInt(1) } } },
        .{ .span = span, .op = .pop },
        .{ .span = span, .op = .{ .function_value = .{ .ty = callback, .function = @fromBackingInt(1) } } },
        .{ .span = span, .op = .pop },
        .{ .span = span, .op = .{ .push_i64 = 0 } },
        .{ .span = span, .op = .ret },
    });
    const body = try a.dupe(bytecode.Instruction, &.{
        .{ .span = span, .op = .{ .load_local = @fromBackingInt(0) } },
        .{ .span = span, .op = .ret },
    });
    const functions = try a.dupe(bytecode.Function, &.{
        .{ .id = @fromBackingInt(0), .name = "main", .scope = .{ .instructions = main } },
        .{
            .id = @fromBackingInt(1),
            .name = "mixed",
            .signature = .{
                .parameter_count = 3,
                .return_type = list,
                .declared_mutates = &.{ 0, 1 },
                .return_origin = .{ .params = &.{0} },
                .inferred = .{ .caller_storage = mask, .borrow_origin = .{ .params = &.{0} } },
            },
            .scope = .{ .locals = locals, .instructions = body },
        },
    });
    return .{ .functions = functions, .records = records };
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter preserves mixed canonical ABI and owned return metadata" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const original = try fixture(arena.allocator(), 2);
    const result = try adapter.adapt(arena.allocator(), original);
    try bytecode.validate(arena.allocator(), result);
    try t.expectEqual(@as(usize, 3), result.functions.len);
    try t.expectEqual(@as(u16, 2), result.functions[1].signature.inferred.caller_storage);
    try t.expectEqual(@as(usize, 1), @backingInt(original.functions[0].scope.instructions[0].op.function_value.function));
    try assertWrapper(result);
}

fn assertWrapper(code: bytecode.Program) !void {
    const wrapper = code.functions[2];
    const body = wrapper.scope.instructions;
    try t.expectEqual(@as(usize, 2), @backingInt(code.functions[0].scope.instructions[0].op.function_value.function));
    try t.expectEqual(@as(usize, 2), @backingInt(code.functions[0].scope.instructions[2].op.function_value.function));
    try t.expect(adapter.isAdapter(wrapper.name));
    try t.expectEqual(@as(u16, 3), wrapper.signature.inferred.caller_storage);
    try t.expectEqual(list, wrapper.signature.return_type);
    try t.expect(typed.ReturnOrigin.eql(code.functions[1].signature.return_origin, wrapper.signature.return_origin));
    try t.expect(typed.ReturnOrigin.eql(code.functions[1].signature.inferred.borrow_origin, wrapper.signature.inferred.borrow_origin));
    try t.expectEqual(@as(usize, 5), body.len);
    try t.expectEqual(@as(usize, 0), @backingInt(body[0].op.load_local));
    try t.expectEqual(@as(usize, 1), @backingInt(body[1].op.ref_local));
    try t.expectEqual(@as(usize, 2), @backingInt(body[2].op.load_local));
    try t.expectEqual(@as(usize, 1), @backingInt(body[3].op.call));
    try t.expect(body[4].op == .ret);
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter leaves uniformly addressed targets unchanged" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const original = try fixture(arena.allocator(), 3);
    const result = try adapter.adapt(arena.allocator(), original);
    try bytecode.validate(arena.allocator(), result);
    try t.expectEqual(@as(usize, 2), result.functions.len);
    try t.expectEqual(original.functions[0].scope.instructions.ptr, result.functions[0].scope.instructions.ptr);
    try t.expectEqual(@as(usize, 1), @backingInt(result.functions[0].scope.instructions[0].op.function_value.function));
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter reuses archived wrappers and is idempotent" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const once = try adapter.adapt(a, try fixture(a, 2));
    const twice = try adapter.adapt(a, once);
    try t.expectEqual(@as(usize, 3), twice.functions.len);
    const restored = try rawTarget(a, twice);
    const reused = try adapter.adapt(a, restored);
    try bytecode.validate(a, reused);
    try t.expectEqual(@as(usize, 3), reused.functions.len);
    try assertWrapper(reused);
}

fn rawTarget(a: std.mem.Allocator, code: bytecode.Program) !bytecode.Program {
    const functions = try a.dupe(bytecode.Function, code.functions);
    const body = try a.dupe(bytecode.Instruction, functions[0].scope.instructions);
    body[0].op.function_value.function = @fromBackingInt(1);
    functions[0].scope.instructions = body;
    return .{ .functions = functions, .records = code.records, .main = code.main };
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter reserves stable IDs before cached bodies are lowered" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try fixture(a, 2);
    const functions = try a.dupe(bytecode.Function, original.functions);
    functions[0].scope.instructions = original.functions[0].scope.instructions[4..];
    functions[1].scope.instructions = &.{};
    const prepared = try adapter.prepare(a, .{ .functions = functions, .records = original.records }, &.{@fromBackingInt(1)});
    try t.expectEqual(@as(usize, 3), prepared.functions.len);
    try t.expectEqual(@as(usize, 0), prepared.functions[1].scope.instructions.len);
    try t.expectEqual(@as(usize, 2), @backingInt(prepared.functions[2].id));
    const fresh = try a.dupe(bytecode.Function, prepared.functions);
    fresh[0] = original.functions[0];
    fresh[1] = original.functions[1];
    const result = try adapter.adapt(a, .{ .functions = fresh, .records = original.records });
    try bytecode.validate(a, result);
    try t.expectEqual(@as(usize, 3), result.functions.len);
    try t.expectEqualStrings("mixed", adapter.canonicalName(result.functions[2].name));
    try t.expectEqualStrings("mixed", adapter.canonicalName(result.functions[1].name));
    try assertWrapper(result);
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter symbolic archive identity is independent of consumer source positions" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const first = try adapter.adapt(a, try shiftedSource(a, try fixture(a, 2), 10));
    const second = try adapter.adapt(a, try shiftedSource(a, try fixture(a, 2), 90));
    const physical = @import("module_physical.zig");
    const first_data = try physical.write(a, .{ .functions = first.functions, .records = first.records }, first.functions[2]);
    const second_data = try physical.write(a, .{ .functions = second.functions, .records = second.records }, second.functions[2]);
    try t.expectEqualStrings(first_data.name, second_data.name);
    try t.expectEqualSlices(u8, first_data.bytes, second_data.bytes);
    try t.expectEqual(@as(usize, 10), first.functions[1].scope.locals[0].declaration.start);
    try t.expectEqual(@as(usize, 90), second.functions[1].scope.locals[0].declaration.start);
}

fn shiftedSource(a: std.mem.Allocator, code: bytecode.Program, offset: usize) !bytecode.Program {
    const functions = try a.dupe(bytecode.Function, code.functions);
    const locals = try a.dupe(typed.Local, functions[1].scope.locals);
    for (locals) |*local| local.declaration = .{ .start = offset, .end = offset + 1 };
    const body = try a.dupe(bytecode.Instruction, functions[0].scope.instructions);
    for (body) |*instruction| instruction.span = .{ .start = offset, .end = offset + 1 };
    functions[0].scope.instructions = body;
    functions[1].scope.locals = locals;
    functions[1].policy.effect_bound = .{ .allowed = 0, .span = .{ .start = offset, .end = offset + 1 } };
    return .{ .functions = functions, .records = code.records, .main = code.main };
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter rejects conflicting archived wrapper ABI" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const restored = try rawTarget(a, try adapter.adapt(a, try fixture(a, 2)));
    const functions = try a.dupe(bytecode.Function, restored.functions);
    functions[2].signature.inferred.caller_storage = 2;
    var malformed = restored;
    malformed.functions = functions;
    try t.expectError(error.InternalError, adapter.adapt(a, malformed));
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter rejects nonexistent function targets" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const original = try fixture(a, 2);
    const functions = try a.dupe(bytecode.Function, original.functions);
    const body = try a.dupe(bytecode.Instruction, functions[0].scope.instructions);
    body[0].op.function_value.function = @fromBackingInt(functions.len);
    functions[0].scope.instructions = body;
    var malformed = original;
    malformed.functions = functions;
    try t.expectError(error.InternalError, adapter.adapt(a, malformed));
}

const nested_source =
    \\def change(first: mut list[int], second: mut list[int], replacement: list[int]) -> list[list[int]]:
    \\    first.append(8)
    \\    second = replacement
    \\    second.append(9)
    \\    return [first, second]
    \\def main() -> int:
    \\    rows = [[1], [2]]
    \\    saved = rows
    \\    action = change
    \\    result = action(mut rows[0], mut rows[1], [3])
    \\    rows[0].append(10)
    \\    return 1 if rows == [[1, 8, 10], [3, 9]] and saved == [[1], [2]] and result == [[1, 8], [3, 9]] else 0
;

fn runSource(input: []const u8, collector: bool) !@import("native_execute.zig").Run {
    const compiler = @import("compiler.zig");
    const runtime = @import("runtime_mode.zig");
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(if (collector) .gc else .rc);
    var compilation = try compiler.Compilation.init(t.allocator, "mut-callback-storage.my", input);
    defer compilation.deinit();
    return @import("native_execute.zig").runWithOptions(&compilation, .{});
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter RC keeps two interior slots and managed returns independent" {
    const result = try runSource(nested_source, false);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1), result.value);
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter GC stress keeps two interior slots and managed returns independent" {
    const result = try runSource(nested_source, true);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1), result.value);
}

const rows_snapshot_source =
    \\def replace(target: mut list[int], snapshot: list[list[int]]) -> list[int]:
    \\    target = [9]
    \\    return snapshot[0]
    \\def main() -> int:
    \\    rows = [[1]]
    \\    saved = rows
    \\    prior = replace(mut rows[0], rows)
    \\    rows[0].append(10)
    \\    other = [[2]]
    \\    other_saved = other
    \\    action = replace
    \\    other_prior = action(mut other[0], other)
    \\    other[0].append(11)
    \\    return 1 if rows == [[9, 10]] and saved == [[1]] and prior == [1] and other == [[9, 11]] and other_saved == [[2]] and other_prior == [2] else 0
;

const field_snapshot_source =
    \\record Box:
    \\    items: list[int]
    \\def replace(target: mut list[int], snapshot: Box) -> list[int]:
    \\    target = [9]
    \\    return snapshot.items
    \\def main() -> int:
    \\    box = Box([1])
    \\    saved = box
    \\    prior = replace(mut box.items, box)
    \\    box.items.append(10)
    \\    other = Box([2])
    \\    other_saved = other
    \\    action = replace
    \\    other_prior = action(mut other.items, other)
    \\    other.items.append(11)
    \\    return 1 if box.items == [9, 10] and saved.items == [1] and prior == [1] and other.items == [9, 11] and other_saved.items == [2] and other_prior == [2] else 0
;

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter later readonly rows preserve captured RC leaf and snapshots" {
    const result = try runSource(rows_snapshot_source, false);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1), result.value);
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter later readonly rows preserve captured GC leaf and snapshots" {
    const result = try runSource(rows_snapshot_source, true);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1), result.value);
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter later readonly record preserves captured RC field and snapshots" {
    const result = try runSource(field_snapshot_source, false);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1), result.value);
}

// spec-case: MUT-REBIND-CALLER-1
test "mut callback adapter later readonly record preserves captured GC field and snapshots" {
    const result = try runSource(field_snapshot_source, true);
    try t.expectEqualStrings("", result.trap.code);
    try t.expectEqual(@as(i64, 1), result.value);
}
