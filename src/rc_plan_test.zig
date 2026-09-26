//! Physical ownership regressions independent of RC runtime implementation.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const model = @import("rc_model.zig");
const calls = @import("rc_calls.zig");
const transfers = @import("rc_transfer.zig");
const t = std.testing;

const ShapeFixture = struct {
    arena: std.heap.ArenaAllocator,
    compilation: compiler.Compilation,
    layouts: native.Catalog,

    fn init(source: []const u8) !ShapeFixture {
        var compilation = try compiler.Compilation.init(t.allocator, "rc_shape.my", source);
        errdefer compilation.deinit();
        try compilation.check();
        var arena = std.heap.ArenaAllocator.init(t.allocator);
        errdefer arena.deinit();
        const records = try @import("recursive_boxes.zig").physical(arena.allocator(), compilation.program.?.records);
        return .{ .arena = arena, .compilation = compilation, .layouts = try native.Catalog.initRecords(t.allocator, records) };
    }

    fn deinit(self: *ShapeFixture) void {
        self.layouts.deinit();
        self.arena.deinit();
        self.compilation.deinit();
    }

    fn typeNamed(self: *const ShapeFixture, name: []const u8) !@import("typed.zig").Type {
        for (self.layouts.records) |record| if (std.mem.eql(u8, record.name, name)) return record.id;
        return error.TestUnexpectedResult;
    }
};

// spec: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 immutable backing and pure recursive boxes still own edges" {
    var fixture = try ShapeFixture.init(
        \\record View:
        \\    data: bytes
        \\
        \\record Node:
        \\    number: int
        \\    next: Option[Node]
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const view = try fixture.typeNamed("View");
    const node = try fixture.typeNamed("Node");
    try t.expect(!@import("value_semantics.zig").needsCopy(fixture.layouts.records, view));
    try t.expect(!@import("value_semantics.zig").needsCopy(fixture.layouts.records, node));
    try t.expect((try facts.get(view)).counted);
    try t.expect((try facts.get(node)).counted);
    try t.expect(!(try facts.get(view)).unique_drop);
    try t.expect((try facts.get(node)).copyable);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 resources own lifetime without becoming copyable" {
    var fixture = try ShapeFixture.init("def main() -> int:\n    return 0\n");
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const file = try facts.get(.file);
    const integer = try facts.get(.i64);
    try t.expect(file.counted);
    try t.expect(file.unique_drop);
    try t.expect(!file.copyable);
    try t.expect(!integer.counted);
    try t.expect(!integer.unique_drop);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 mixed fresh provenance keeps canonical owned result" {
    var fixture = try ShapeFixture.init(
        \\def choose(source: list[list[int]], fresh: bool) -> list[int]:
        \\    if fresh:
        \\        return [7, 8]
        \\    return source[0]
        \\
        \\def main() -> int:
        \\    return len(choose([[1, 2]], True))
    );
    defer fixture.deinit();
    try fixture.compilation.emit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const function = try namedFunction(fixture.compilation.code.?, "choose");
    const contract = try calls.guest(fixture.arena.allocator(), &facts, function, "rc-v1");
    try t.expect(function.signature.inferred.borrow_origin == .params);
    try t.expectEqualSlices(u16, &.{0}, function.signature.inferred.borrow_origin.params);
    try t.expect(contract.result == .owned);
    try t.expect(contract.failure == .caller_keeps_inputs);
    try t.expectEqualSlices(model.Parameter, &.{ .read, .read }, contract.parameters);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 mut aggregates and mutable payloads keep distinct call contracts" {
    var fixture = try ShapeFixture.init(
        \\record Data:
        \\    items: list[int]
        \\
        \\def change(data: mut Data, items: mut list[int], array: mut [1]list[int]) -> int:
        \\    data.items.append(4)
        \\    items.append(5)
        \\    array[0] = [6]
        \\    return len(data.items) + len(items)
        \\
        \\def main() -> int:
        \\    data = Data([1])
        \\    items = [2]
        \\    array: [1]list[int] = [[3]]
        \\    return change(mut data, mut items, mut array)
    );
    defer fixture.deinit();
    try fixture.compilation.emit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const function = try namedFunction(fixture.compilation.code.?, "change");
    const contract = try calls.guest(fixture.arena.allocator(), &facts, function, "rc-v1");
    try t.expect(contract.result == .plain);
    try t.expectEqualSlices(model.Parameter, &.{ .caller_storage, .mutable_payload, .caller_storage }, contract.parameters);
}

fn namedFunction(program: @import("bytecode.zig").Program, name: []const u8) !@import("bytecode.zig").Function {
    for (program.functions) |function| if (std.mem.eql(u8, function.name, name)) return function;
    return error.TestUnexpectedResult;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 ownership metadata names pointer bodies and inline variant layouts" {
    var fixture = try ShapeFixture.init(
        \\record Node:
        \\    number: int
        \\    next: Option[Node]
        \\
        \\record Holder:
        \\    values: [2]bytes
        \\    choice: Result[bytes, int]
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer fixture.deinit();
    const text = try @import("rc_descriptors.zig").generate(t.allocator, &fixture.layouts);
    defer t.allocator.free(text);
    try t.expect(std.mem.indexOf(u8, text, "MYL_RC_SHAPE_POINTER") != null);
    try t.expect(std.mem.indexOf(u8, text, "_body_rc =") != null);
    try t.expect(std.mem.indexOf(u8, text, ".count=2,.stride=8") != null);
    try t.expect(std.mem.indexOf(u8, text, ".tag_offset=0") != null);
    try t.expect(std.mem.indexOf(u8, text, "myl_rc_generated_module = {.abi=MYL_RC_ABI_VERSION") != null);
}

fn ownedValue(storage: u32, token: u32) model.ValueState {
    return .{
        .value = @fromBackingInt(@intCast(storage)),
        .ty = .file,
        .storage = @fromBackingInt(@intCast(storage)),
        .shape = .{ .counted = true, .unique_drop = true, .copyable = false },
        .ownership = .{ .owned = .{ .token = @fromBackingInt(@intCast(token)) } },
    };
}

fn shareableValue(storage: u32, token: u32) !model.ValueState {
    var fixture = try ShapeFixture.init("record Data:\n    values: list[int]\n\ndef main() -> int:\n    return 0\n");
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    var value = ownedValue(storage, token);
    value.ty = try fixture.typeNamed("Data");
    value.shape = try facts.get(value.ty);
    return value;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 canonical borrowed result acquires ownership even at last use" {
    var source = try shareableValue(0, 0);
    source.ownership = .{ .borrowed = .{ .parameter = 0 } };
    var destination = source;
    destination.storage = @fromBackingInt(@intCast(1));
    destination.value = @fromBackingInt(@intCast(1));
    destination.ownership = .empty;
    const plan = try transfers.plan(.{ .slots = .{ .source = source, .destination = destination }, .intent = .last_use, .token = @fromBackingInt(@intCast(7)), .checkpoint = .{ .pc = 3 } });
    try t.expectEqual(transfers.Operation.copy, plan.operation);
    try t.expect(plan.success.source.ownership == .borrowed);
    try t.expect(plan.success.destination.ownership == .owned);
    try t.expectEqual(@as(model.TokenId, @fromBackingInt(@intCast(7))), plan.success.destination.ownership.owned.token);
    try t.expect(plan.failure().destination.ownership == .empty);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 owning replacement commits only at precise helper success" {
    const source = ownedValue(0, 2);
    const destination = ownedValue(1, 3);
    const plan = try transfers.plan(.{ .slots = .{ .source = source, .destination = destination }, .intent = .last_use, .token = @fromBackingInt(@intCast(4)), .checkpoint = .{ .pc = 8, .step = 2 } });
    try t.expectEqual(transfers.Operation.take, plan.operation);
    try t.expect(plan.success.source.ownership == .empty);
    try t.expectEqual(@as(model.TokenId, @fromBackingInt(@intCast(4))), plan.success.destination.ownership.owned.token);
    try t.expectEqualDeep(source, plan.failure().source);
    try t.expectEqualDeep(destination, plan.failure().destination);
    try t.expectEqual(@as(u32, 2), plan.checkpoint.step);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 same physical slot self assignment preserves one owner" {
    const value = ownedValue(0, 9);
    const plan = try transfers.plan(.{ .slots = .{ .source = value, .destination = value }, .intent = .copy, .token = @fromBackingInt(@intCast(10)), .checkpoint = .{ .pc = 2 } });
    try t.expectEqual(transfers.Operation.self, plan.operation);
    try t.expectEqualDeep(value, plan.success.source);
    try t.expectEqualDeep(value, plan.success.destination);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 unique and conditional owners cannot silently become snapshots" {
    const source = ownedValue(0, 0);
    var destination = ownedValue(1, 1);
    destination.ownership = .empty;
    var input: transfers.Input = .{ .slots = .{ .source = source, .destination = destination }, .intent = .copy, .token = @fromBackingInt(@intCast(2)), .checkpoint = .{ .pc = 4 } };
    try t.expectError(error.CopyProhibited, transfers.plan(input));
    input.intent = .last_use;
    input.slots.source.ownership.owned.initialized = @fromBackingInt(@intCast(0));
    try t.expectError(error.InvalidState, transfers.plan(input));
    input.slots.source.ty = .i64;
    try t.expectError(error.TypeMismatch, transfers.plan(input));
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 held receiver publication preserves its nonsharing hold" {
    var source = try shareableValue(0, 0);
    source.ownership = .{ .held = @fromBackingInt(@intCast(3)) };
    var destination = source;
    destination.storage = @fromBackingInt(@intCast(1));
    destination.value = @fromBackingInt(@intCast(1));
    destination.ownership = .empty;
    const plan = try transfers.plan(.{ .slots = .{ .source = source, .destination = destination }, .intent = .last_use, .token = @fromBackingInt(@intCast(8)), .checkpoint = .{ .pc = 5 } });
    try t.expectEqual(transfers.Operation.copy, plan.operation);
    try t.expectEqual(source.ownership, plan.success.source.ownership);
    try t.expect(plan.success.destination.ownership == .owned);
}

const Metadata = struct { runtime_data: []const u8 };

fn metadata() !std.json.Parsed(Metadata) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_metadata.my",
        \\record Node:
        \\    label: bytes
        \\    next: Option[Node]
        \\
        \\record Data:
        \\    nodes: [2]Node
        \\    result: Result[bytes, int]
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    return std.json.parseFromSlice(Metadata, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn metadataCompiles(data: []const u8) !bool {
    var temporary = t.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(t.io, .{ .sub_path = "native_heap.h", .data = @embedFile("native_heap.h") });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "native_rc.h", .data = @embedFile("native_rc.h") });
    try temporary.dir.writeFile(t.io, .{ .sub_path = "ownership.c", .data = data });
    const zig = @import("native_test_options").zig_path;
    const result = try std.process.run(t.allocator, t.io, .{
        .argv = &.{ zig, "cc", "-std=c11", "-Werror", "-c", "ownership.c", "-o", "ownership.o" },
        .cwd = .{ .dir = temporary.dir },
    });
    defer t.allocator.free(result.stdout);
    defer t.allocator.free(result.stderr);
    const success = result.term == .exited and result.term.exited == 0;
    if (!success) try std.Io.File.stderr().writeStreamingAll(t.io, result.stderr);
    return success;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 selected RC metadata compiles against the frozen C ABI" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.gc);
    var gc = try metadata();
    defer gc.deinit();
    try t.expect(std.mem.indexOf(u8, gc.value.runtime_data, "myl_rc_generated_module") == null);
    mode.set(.rc);
    var rc = try metadata();
    defer rc.deinit();
    try t.expect(std.mem.indexOf(u8, rc.value.runtime_data, "const myl_rc_module myl_rc_generated_module") != null);
    try t.expect(try metadataCompiles(rc.value.runtime_data));
}
