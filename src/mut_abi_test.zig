//! MUT-REBIND-CALLER-1 ABI selection and persisted authority regressions.
const std = @import("std");
const language = @import("compiler.zig");
const abi = @import("mut_abi.zig");
const t = std.testing;

const source =
    \\def payload(items: mut list[int]):
    \\    items.append(1)
    \\
    \\def recursive(items: mut list[int], count: int):
    \\    if count > 0:
    \\        forwarding(mut items, count - 1)
    \\    else:
    \\        items = [9]
    \\
    \\def forwarding(items: mut list[int], count: int):
    \\    recursive(mut items, count)
    \\
    \\def callback(items: mut list[int]):
    \\    items.append(2)
    \\
    \\def main() -> int:
    \\    items = [0]
    \\    payload(mut items)
    \\    forwarding(mut items, 2)
    \\    action = callback
    \\    action(mut items)
    \\    return len(items)
;

// spec-case: MUT-REBIND-CALLER-1
test "mut collection ABI propagates recursive rebinding and preserves direct payload parameters" {
    var compilation = try language.Compilation.init(t.allocator, "mut-abi.my", source);
    defer compilation.deinit();
    try compilation.emit();
    try assertAbi(compilation.code.?);
}

fn assertAbi(program: language.bytecode.Program) !void {
    var found: usize = 0;
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, "payload") or std.mem.eql(u8, function.name, "callback")) {
            try t.expect(!abi.reference(program.records, function, 0));
            found += 1;
        } else if (std.mem.eql(u8, function.name, "recursive") or
            std.mem.eql(u8, function.name, "forwarding"))
        {
            try t.expect(abi.reference(program.records, function, 0));
            found += 1;
        }
    }
    try t.expectEqual(@as(usize, 4), found);
}

fn named(program: language.bytecode.Program, name: []const u8) !language.bytecode.Function {
    for (program.functions) |function| if (std.mem.eql(u8, function.name, name)) return function;
    return error.TestUnexpectedResult;
}

// spec-case: MUT-REBIND-CALLER-1
test "mut collection child rebinding preserves the outer direct payload ABI" {
    const child_source =
        \\def child(items: mut list[int]):
        \\    items = [9]
        \\def outer(rows: mut list[list[int]]):
        \\    child(mut rows[0])
        \\    rows[1][0] = 7
        \\def main() -> int:
        \\    rows = [[1], [2]]
        \\    outer(mut rows)
        \\    return rows[0][0]
    ;
    var compilation = try language.Compilation.init(t.allocator, "mut-child-abi.my", child_source);
    defer compilation.deinit();
    try compilation.emit();
    const code = compilation.code.?;
    try t.expect(abi.reference(code.records, try named(code, "child"), 0));
    try t.expect(!abi.reference(code.records, try named(code, "outer"), 0));
}

fn reserve(a: std.mem.Allocator, program: language.bytecode.Program) !language.module_physical.Ids {
    var ids: language.module_physical.Ids = .{};
    for (program.functions) |item| try ids.functions.put(a, item.name, item.id);
    for (program.records) |item| try ids.records.put(a, item.name, item.id);
    return ids;
}

// spec-case: MUT-REBIND-CALLER-1
test "physical bytecode preserves caller storage ABI and rejects conflicting signatures" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var compilation = try language.Compilation.init(a, "mut-abi.my", source);
    try compilation.emit();
    const program = compilation.code.?;
    const function = try named(program, "recursive");
    const physical = language.module_physical;
    const data = try physical.write(a, .{ .functions = program.functions, .records = program.records }, function);
    const ids = try reserve(a, program);
    const restored = try physical.read(a, &ids, language.bytecode.Function, data);
    try t.expectEqual(function.signature.inferred.caller_storage, restored.signature.inferred.caller_storage);
    try t.expect(abi.reference(program.records, restored, 0));
    const originals = try a.dupe(language.bytecode.Function, program.functions);
    originals[@backingInt(function.id)].signature.inferred.caller_storage = 0;
    const selected = try a.alloc(bool, program.functions.len);
    @memset(selected, false);
    selected[@backingInt(function.id)] = true;
    const archive = try physical.archive(a, program, selected);
    const facts = try a.alloc(?language.native_interface.Imported, selected.len);
    @memset(facts, null);
    @memset(selected, false);
    const interface: language.module_interface.Interface = .{ .module = "mut-abi", .text = "", .emission = .{ .physical = archive } };
    try t.expectError(error.InternalError, @import("module_physical_inputs.zig").restore(
        a,
        .{ .functions = originals, .records = program.records },
        selected,
        facts,
        &.{interface},
    ));
}

// spec-case: MUT-REBIND-CALLER-1
test "module emission carries caller storage ABI and invalidates its identity" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const iface = language.module_interface;
    const reference: iface.Interface = .{ .module = "lib", .text = "", .emission = .{ .functions = &.{.{ .name = "lib::reset", .allocates = true, .writes = &.{true}, .caller_storage = 1 }} } };
    const payload: iface.Interface = .{ .module = "lib", .text = "", .emission = .{ .functions = &.{.{ .name = "lib::reset", .allocates = true, .writes = &.{true} }} } };
    const encoded = try iface.encode(a, reference);
    const restored = iface.decode(a, encoded) orelse return error.TestUnexpectedResult;
    try t.expectEqual(@as(u16, 1), restored.emission.functions[0].caller_storage);
    try t.expect(!std.mem.eql(u8, &iface.emissionHash(reference), &iface.emissionHash(payload)));
    try t.expectEqualSlices(u8, &iface.interfaceHash(reference), &iface.interfaceHash(payload));
}

// spec-case: MUT-REBIND-CALLER-1
test "semantic stand in facts preserve caller storage ABI through their codec" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const summaries = language.semantic_summary;
    const fact = summaries.fromFact(.{ .caller_storage = 1, .summary = .{ .mutates = 1, .writes = true, .external = true } });
    const table: summaries.Table = .{ .summaries = &.{.{ .key = "fn\x1flib\x1freset", .context = @splat(0), .region = .{ .len = 1, .digest = @splat(0) }, .fact = fact, .stubbable = true }} };
    const bytes = try summaries.encode(a, table);
    const decoded = summaries.decode(a, bytes) orelse return error.TestUnexpectedResult;
    try t.expect(summaries.sameFact(fact, decoded.summaries[0].fact));
    try t.expectEqual(@as(u16, 1), summaries.toFact(decoded.summaries[0].fact).caller_storage);
    var compilation = try language.Compilation.init(a, "mut-abi.my", source);
    try compilation.emit();
    const function = try named(compilation.code.?, "recursive");
    try t.expect(abi.valid(compilation.code.?.records, function, 1));
    try t.expect(!abi.valid(compilation.code.?.records, function, 2));
}
