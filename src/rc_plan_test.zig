//! Physical ownership regressions independent of RC runtime implementation.
const std = @import("std");
const compiler = @import("compiler.zig");
const native = @import("native_types.zig");
const typed = @import("typed.zig");
const shapes = @import("rc_shape.zig");
const model = @import("rc_model.zig");
const calls = @import("rc_calls.zig");
const transfers = @import("rc_transfer.zig");
const plans = @import("rc_plan.zig");
const slots = @import("qbe_rc_slots.zig");
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

    fn typeNamed(self: *const ShapeFixture, name: []const u8) !typed.Type {
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
test "RC-OWNERSHIP-PLAN-1 raw resources keep unique cleanup without an RC header" {
    var fixture = try ShapeFixture.init("def main() -> int:\n    return 0\n");
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const file = try facts.get(.file);
    const integer = try facts.get(.i64);
    try t.expect(!file.counted);
    try t.expect(file.unique_drop);
    try t.expect(!file.copyable);
    try t.expect(!integer.counted);
    try t.expect(!integer.unique_drop);
    try t.expect(!(try facts.get(.text_file)).counted);
    const metadata_text = try @import("rc_descriptors.zig").generate(t.allocator, &fixture.layouts);
    defer t.allocator.free(metadata_text);
    try t.expect(try rawResourceShape(&fixture, metadata_text, .file));
    try t.expect(try rawResourceShape(&fixture, metadata_text, .text_file));
}

fn rawResourceShape(fixture: *ShapeFixture, text: []const u8, ty: typed.Type) !bool {
    const a = fixture.arena.allocator();
    const name = try @import("rc_descriptors.zig").symbol(a, &fixture.layouts, ty);
    const definition = try std.fmt.allocPrint(a, "const myl_rc_shape {s} = {{.size=8,.kind=MYL_RC_SHAPE_NONE}};", .{name});
    return std.mem.indexOf(u8, text, definition) != null;
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
    const contract = try calls.guest(fixture.arena.allocator(), &facts, function, "rc-v2");
    try t.expect(function.signature.inferred.borrow_origin == .params);
    try t.expectEqualSlices(u16, &.{0}, function.signature.inferred.borrow_origin.params);
    try t.expect(contract.result == .owned);
    try t.expect(contract.failure == .parameter_contracts);
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
    const contract = try calls.guest(fixture.arena.allocator(), &facts, function, "rc-v2");
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
        .shape = .{ .unique_drop = true, .copyable = false },
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
    try t.expectEqual(transfers.Operation.take_unique, plan.operation);
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

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 move-only guest parameters preserve callee drop ownership" {
    var fixture = try ShapeFixture.init("def consume(file: File) -> int:\n    return 0\n\ndef main() -> int:\n    return 0\n");
    defer fixture.deinit();
    try fixture.compilation.emit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const function = try namedFunction(fixture.compilation.code.?, "consume");
    const contract = try calls.guest(fixture.arena.allocator(), &facts, function, "rc-v2");
    try t.expectEqualSlices(model.Parameter, &.{.consume_on_entry}, contract.parameters);
    try t.expect(contract.failure == .parameter_contracts);
}

fn planInput(fixture: *ShapeFixture, facts: *shapes.Catalog, name: []const u8) !plans.Input {
    try fixture.compilation.emit();
    const a = fixture.arena.allocator();
    const program = fixture.compilation.code.?;
    const function = try namedFunction(program, name);
    const ir = try @import("native_ir.zig").analyze(a, program, function);
    const pinned = try a.alloc(bool, function.scope.locals.len);
    for (function.scope.locals, pinned) |local, *pin| pin.* = (try facts.get(local.ty)).unique_drop;
    const live = try @import("qbe_liveness.zig").solve(a, .{ .function = function, .states = ir.states, .pinned = pinned });
    const analysis = try @import("ownership.zig").analyze(a, .{ .program = program, .function = function, .states = ir.states, .live = live });
    const bindings = try a.alloc(@import("rc_input.zig").Binding, function.scope.locals.len);
    for (bindings, 0..) |*binding, index| binding.* = .{ .storage = @fromBackingInt(@intCast(index)) };
    return .{
        .code = .{ .program = program, .function = function, .states = ir.states },
        .flow = .{ .live = live, .ownership = analysis },
        .physical = .{ .catalog = facts, .locals = bindings },
        .contracts = .{ .current = try calls.guest(a, facts, function, "rc-v2") },
        .policy = .{ .abi = "rc-v2" },
    };
}

fn localIndex(input: plans.Input, name: []const u8) !usize {
    for (input.code.function.scope.locals, 0..) |local, index| if (std.mem.eql(u8, local.name, name)) return index;
    return error.TestUnexpectedResult;
}

fn firstReference(input: plans.Input, local: usize) !usize {
    for (input.code.function.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op == .ref_local and @backingInt(instruction.op.ref_local) == local) return pc;
    }
    return error.TestUnexpectedResult;
}

fn firstRelease(plan: plans.Plan, id: model.StorageId) !usize {
    var first: usize = std.math.maxInt(usize);
    for (plan.edges) |edge| for (edge.releases) |release| {
        if (release.storage == id) first = @min(first, edge.from);
    };
    if (first == std.math.maxInt(usize)) return error.TestUnexpectedResult;
    return first;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 final ref_local liveness delays edge release until the consuming call" {
    var fixture = try ShapeFixture.init(
        \\record Data:
        \\    values: list[int]
        \\
        \\def consume(data: mut Data) -> int:
        \\    data.values.append(4)
        \\    return len(data.values)
        \\
        \\def main() -> int:
        \\    data = Data([1, 2, 3])
        \\    scratch = [9, 10]
        \\    size = consume(mut data)
        \\    return size + len(scratch)
    );
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const input = try planInput(&fixture, &facts, "main");
    const data = try localIndex(input, "data");
    const plan = try plans.build(fixture.arena.allocator(), input);
    const reference = try firstReference(input, data);
    try t.expect(plan.entry[data].ownership == .empty);
    try t.expect(try firstRelease(plan, input.physical.locals[data].storage) > reference);
    try t.expect(input.flow.live.before(reference, data));
}

fn falseEdgeDrops(input: plans.Input, plan: plans.Plan, local: usize) bool {
    for (input.code.function.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op != .jump_if_false) continue;
        for (plan.edges) |edge| {
            if (edge.from != pc or edge.to != instruction.op.jump_if_false) continue;
            for (edge.releases) |release| if (release.storage == input.physical.locals[local].storage) return true;
        }
    }
    return false;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 branch cleanup belongs to the actual unused successor edge" {
    var fixture = try ShapeFixture.init(
        \\def choose(use: bool) -> int:
        \\    values = [1, 2]
        \\    if use:
        \\        return len(values)
        \\    return 0
        \\
        \\def main() -> int:
        \\    return choose(False)
    );
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    var input = try planInput(&fixture, &facts, "choose");
    const plan = try plans.build(fixture.arena.allocator(), input);
    try t.expect(falseEdgeDrops(input, plan, try localIndex(input, "values")));
    input.policy.abi = "rc-v1";
    try t.expectError(error.AbiMismatch, plans.build(fixture.arena.allocator(), input));
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 entry-owned resources have a guard but no early edge drop" {
    var fixture = try ShapeFixture.init("def consume(file: File) -> int:\n    return 0\n\ndef main() -> int:\n    return 0\n");
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    var input = try planInput(&fixture, &facts, "consume");
    const plan = try plans.build(fixture.arena.allocator(), input);
    try t.expect(plan.entry[0].ownership == .owned);
    try t.expectEqual(@as(usize, 1), plan.cleanup.len);
    try t.expectEqual(@as(usize, 0), plan.edges.len);
    input.physical.locals = &.{};
    try t.expectError(error.InvalidState, plans.build(fixture.arena.allocator(), input));
}

fn cleanupCount(plan: plans.Plan, id: model.StorageId) usize {
    var count: usize = 0;
    for (plan.cleanup) |release| if (release.storage == id) {
        count += 1;
    };
    return count;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 actual storage aliases share one cleanup guard" {
    var fixture = try ShapeFixture.init(
        \\record Data:
        \\    values: list[int]
        \\
        \\def main() -> int:
        \\    first = Data([1])
        \\    second = first
        \\    return len(second.values)
    );
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const input = try planInput(&fixture, &facts, "main");
    const first = try localIndex(input, "first");
    const second = try localIndex(input, "second");
    const bindings = @constCast(input.physical.locals);
    bindings[second].storage = bindings[first].storage;
    const plan = try plans.build(fixture.arena.allocator(), input);
    try t.expectEqual(plan.entry[first].storage, plan.entry[second].storage);
    try t.expectEqual(@as(usize, 1), cleanupCount(plan, bindings[first].storage));
    bindings[first].anchor = .{ .storage = bindings[first].storage };
    try t.expectError(error.InvalidState, plans.build(fixture.arena.allocator(), input));
}

fn firstDefinition(input: plans.Input, local: usize) !usize {
    for (input.code.function.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op == .store_local and @backingInt(instruction.op.store_local) == local) return pc;
    }
    return error.TestUnexpectedResult;
}

fn lastBackEdge(input: plans.Input) !usize {
    var result: ?usize = null;
    for (input.code.function.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op == .jump and instruction.op.jump < pc) result = pc;
    }
    return result orelse error.TestUnexpectedResult;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 zero iteration does not initialize a loop-only owner" {
    var fixture = try ShapeFixture.init(
        \\def walk(limit: int) -> int:
        \\    total = 0
        \\    while total < limit:
        \\        values = [total]
        \\        total = total + len(values)
        \\    return total
        \\
        \\def main() -> int:
        \\    return walk(0)
    );
    defer fixture.deinit();
    var facts = try shapes.Catalog.init(t.allocator, &fixture.layouts);
    defer facts.deinit();
    const input = try planInput(&fixture, &facts, "walk");
    const local = try localIndex(input, "values");
    const plan = try plans.build(fixture.arena.allocator(), input);
    const release = try firstRelease(plan, input.physical.locals[local].storage);
    try t.expect(plan.entry[local].ownership == .empty);
    try t.expect(release >= try firstDefinition(input, local));
    try t.expect(release <= try lastBackEdge(input));
}

const SlotEmitter = struct {
    output: std.Io.Writer.Allocating,
    serial: usize = 100,

    fn init() SlotEmitter {
        return .{ .output = .init(t.allocator) };
    }

    fn deinit(self: *SlotEmitter) void {
        self.output.deinit();
    }

    /// Allocate an SSA identity distinct from the fixture's incoming addresses.
    pub fn temp(self: *SlotEmitter) usize {
        defer self.serial += 1;
        return self.serial;
    }

    /// Write one lowered instruction sequence to this test's native IR buffer.
    pub fn print(self: *SlotEmitter, comptime format: []const u8, args: anytype) slots.Error!void {
        self.output.writer.print(format, args) catch return error.OutOfMemory;
    }

    /// Stable stand-in for the already-tested physical native descriptor symbol.
    pub fn descriptor(_: *SlotEmitter, _: typed.Type) slots.Error![]const u8 {
        return "fixture_descriptor";
    }
};

fn at(text: []const u8, needle: []const u8) !usize {
    return std.mem.indexOf(u8, text, needle) orelse error.TestUnexpectedResult;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 slot ownership publishes only beyond the runtime failure branch" {
    var emitter = SlotEmitter.init();
    defer emitter.deinit();
    const lower = slots.Lower(SlotEmitter);
    try lower.transfer(&emitter, .{ .ty = .i64, .destination = 1, .source = 2, .region = 3, .mode = .copy_empty });
    try lower.initialized(&emitter, 4, true);
    const text = emitter.output.written();
    const helper = try at(text, "call $myl_rc_native_copy");
    const status = try at(text, "call $myl_rc_take_failure");
    const trap = try at(text, "call $myl_qbe_rc_status");
    const failure = try at(text, "jmp @failure");
    const published = try at(text, "storew 1, %v4");
    try t.expect(helper < status);
    try t.expect(status < trap);
    try t.expect(trap < failure);
    try t.expect(failure < published);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 raw resource slot cleanup clears its guard before closing" {
    var emitter = SlotEmitter.init();
    defer emitter.deinit();
    try slots.Lower(SlotEmitter).release(&emitter, .{ .ty = .file, .address = 1, .guard = 2, .unique_drop = true, .counted = false });
    const text = emitter.output.written();
    try t.expect(try at(text, "storew 0, %v2") < try at(text, "call $myl_native_owned_drop"));
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_native_drop") == null);
    try t.expect(std.mem.indexOf(u8, text, "@rcreleased") != null);
}

const Emitted = struct { functions: []const struct { name: []const u8, il: []const u8 } };

fn lowered(source: []const u8) !std.json.Parsed(Emitted) {
    var compilation = try compiler.Compilation.init(t.allocator, "rc_frame.my", source);
    defer compilation.deinit();
    const manifest = try compilation.emitQbe(t.allocator);
    defer t.allocator.free(manifest);
    return std.json.parseFromSlice(Emitted, t.allocator, manifest, .{ .allocate = .alloc_always, .ignore_unknown_fields = true });
}

fn functionText(program: Emitted, name: []const u8) ![]const u8 {
    for (program.functions) |function| if (std.mem.eql(u8, function.name, name)) return function.il;
    return error.TestUnexpectedResult;
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 borrowed parameter result publishes before frame cleanup" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def selected(value: list[int]) -> list[int]:
        \\    return value
        \\
        \\def main() -> int:
        \\    values = [1, 2]
        \\    return len(selected(values))
    );
    defer result.deinit();
    const text = try functionText(result.value, "selected");
    try t.expect(try at(text, "myl_qbe_rc_frame_enter") < try at(text, "myl_rc_native_copy"));
    try t.expect(try at(text, "myl_rc_native_copy") < try at(text, "myl_qbe_rc_frame_cleanup"));
    try t.expect(try at(text, "myl_qbe_rc_frame_cleanup") < try at(text, "myl_qbe_rc_frame_leave"));
    try t.expect(std.mem.indexOf(u8, text, "myl_qbe_cow_transfer") == null);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 compiler journals owned runtime results and transactional local stores" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def main() -> int:
        \\    values = [1, 2]
        \\    other = values
        \\    values = [3]
        \\    return len(other) + len(values)
    );
    defer result.deinit();
    const text = try functionText(result.value, "main");
    try t.expect(try at(text, "call $myl_native_list_new") < try at(text, "call $myl_rc_native_take"));
    try t.expect(std.mem.indexOf(u8, text, "%rcwork") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_slot_drop") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_frame_leave") != null);
}

// spec: RC-UNIQUE-LOWER-1
test "RC-UNIQUE-LOWER-1 mutations use typed owner counts inside loops" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def main() -> int:
        \\    values = [1, 2]
        \\    other = values
        \\    i = 0
        \\    while i < 3:
        \\        values.append(i)
        \\        i += 1
        \\    return len(other)
    );
    defer result.deinit();
    const text = try functionText(result.value, "main");
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_unique_local") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_native_cow_unique") == null);
    try t.expect(std.mem.indexOf(u8, text, "@ce") == null);
}

// spec-case: RC-AGGREGATE-1
test "RC aggregate managed bodies with unique fields install finalizers" {
    var fixture = try ShapeFixture.init(
        \\record Owner:
        \\    handle: TextFile
        \\    next: Option[Owner]
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer fixture.deinit();
    const generated = try @import("rc_descriptors.zig").generate(t.allocator, &fixture.layouts);
    defer t.allocator.free(generated);
    try t.expect(std.mem.indexOf(u8, generated, ".finalize=myl_rc_finalize_unique") != null);
}

// spec-case: RC-UNIQUE-LOWER-1
test "RC-UNIQUE-LOWER-1 nested receiver replaces its owned field before borrowing" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def main() -> int:
        \\    original = [[1, 2]]
        \\    changed = original
        \\    changed[0].append(3)
        \\    return len(original[0])
    );
    defer result.deinit();
    const text = try functionText(result.value, "main");
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_unique_field") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_native_cow_unique") == null);
}

// spec: RC-RECEIVER-LOWER-1
test "RC-RECEIVER-LOWER-1 outgoing mutable arguments hold a nested runtime scope" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def change(value: mut list[int]) -> int:
        \\    value.append(3)
        \\    return len(value)
        \\def main() -> int:
        \\    value = [1, 2]
        \\    return change(mut value)
    );
    defer result.deinit();
    const text = try functionText(result.value, "main");
    try t.expect(try at(text, "call $myl_qbe_rc_scope_begin") < try at(text, "call $myl_qbe_rc_scope_pin"));
    try t.expect(try at(text, "call $myl_qbe_rc_scope_pin") < try at(text, "call $myl_qbe_rc_scope_end"));
    try t.expect(std.mem.indexOf(u8, text, "call $myl_native_cow_unique") == null);
}

// spec-case: RC-OWNERSHIP-PLAN-1
test "RC-OWNERSHIP-PLAN-1 semantic move from readonly parameter checks physical guard" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def selected(candidate: Result[list[int], list[int]]) -> Result[list[int], list[int]]:
        \\    items = candidate?
        \\    return Ok(items)
        \\def main() -> int:
        \\    _ = selected(Ok([1]))
        \\    return 0
    );
    defer result.deinit();
    const text = try functionText(result.value, "selected");
    try t.expect(std.mem.indexOf(u8, text, "=w loaduw") != null);
    try t.expect(std.mem.indexOf(u8, text, "@rccopy") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_native_copy") != null);
}

// spec: RC-NARROWED-MUTATION-1
test "RC-NARROWED-MUTATION-1 compiler Option receivers detach the source edge" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\def change(candidate: mut Option[list[int]]) -> int:
        \\    if candidate is None:
        \\        return 0
        \\    candidate.append(2)
        \\    return len(candidate)
        \\def main() -> int:
        \\    candidate: Option[list[int]] = Some([1])
        \\    return change(mut candidate)
    );
    defer result.deinit();
    const text = try functionText(result.value, "change");
    try t.expect(std.mem.indexOf(u8, text, "call $myl_qbe_rc_unique_field") != null);
    try t.expect(try at(text, "call $myl_qbe_rc_unique_field") < try at(text, "call $myl_rc_list_append"));
}

// spec-case: AUGMENTED-FIELD-1
test "RC augmented list field publishes the captured extended value" {
    const mode = @import("runtime_mode.zig");
    const saved = mode.get();
    defer mode.set(saved);
    mode.set(.rc);
    var result = try lowered(
        \\record Row:
        \\    items: list[int]
        \\def main() -> int:
        \\    row = Row(items=[1])
        \\    row.items += [2]
        \\    return len(row.items)
    );
    defer result.deinit();
    const text = try functionText(result.value, "main");
    try t.expect(std.mem.indexOf(u8, text, "call $myl_native_list_extend") != null);
    try t.expect(std.mem.indexOf(u8, text, "call $myl_rc_native_take") != null);
}
