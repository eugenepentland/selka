//! Exercise the existing completed-publication predicate without widening it.
const std = @import("std");
const compiler = @import("compiler.zig");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const state_model = @import("qbe_rc_state.zig");
const runtime = @import("runtime_mode.zig");
const none = @import("cow_plan.zig").none;
const t = std.testing;
const Capture = struct { begin: u32 = none, active: u32 = none };
const Cow = struct { rc: ?*state_model.State, captures: []Capture };
const Emitter = struct {
    native_variants: @import("runtime_contract").native_variants.Policy = .qbe_v2,
    allocator: std.mem.Allocator,
    program: bytecode.Program,
    function: bytecode.Function,
    pc: usize,
    branch_targets: []bool,
    states: []?[]const typed.Type,
    ownership: ?struct { copies: []bool } = null,
    cow: ?*Cow,
};
const schema =
    \\union Choice:
    \\    empty,
    \\    number: int,
    \\    items: list[int]
    \\def make() -> Choice:
    \\    return Choice.number(7)
    \\def borrowed(value: Choice) -> Choice:
    \\    return value
    \\def main() -> int:
    \\    return 0
;

fn function(program: bytecode.Program, name: []const u8) !bytecode.Function {
    for (program.functions) |item| if (std.mem.eql(u8, item.name, name)) return item;
    return error.TestUnexpectedResult;
}

/// Pass the private production predicate from its own test block. Use the
/// actual compiled schema/types and alter only its explicit refusal inputs.
pub fn exercise(comptime check: anytype) !void {
    const saved = runtime.get();
    defer runtime.set(saved);
    runtime.set(.rc);
    var compilation = try compiler.Compilation.init(t.allocator, "variant_witness.my", schema);
    defer compilation.deinit();
    const il = try compilation.emitQbeWithOptions(t.allocator, .{ .native_variants = .qbe_v2 });
    defer t.allocator.free(il);
    const program = compilation.code.?;
    const made = try function(program, "make");
    const borrowed = try function(program, "borrowed");
    const ty = made.signature.return_type;
    var catalog = try native.Catalog.initRecords(t.allocator, program.records);
    defer catalog.deinit();
    var state: state_model.State = .{
        .catalog = try shapes.Catalog.init(t.allocator, &catalog),
        .plan = undefined,
        .contract = .{ .parameters = &.{.read}, .result = .owned, .abi = runtime.identity() },
        .operands = &.{},
        .pending = 32,
        .active = true,
    };
    defer state.catalog.deinit();
    const count: usize = 4;
    var branches: [count]bool = @splat(false);
    const stack = [_]typed.Type{ty};
    var states: [count]?[]const typed.Type = @splat(&stack);
    var captures: [count]Capture = @splat(.{});
    var cow: Cow = .{ .rc = &state, .captures = &captures };
    var code: [count]bytecode.Instruction = @splat(made.scope.instructions[0]);
    code[2].op = .{ .make_variant = .{ .ty = ty, .tag = 1 } };
    code[3].op = .ret;
    var current = made;
    current.scope.instructions = &code;
    current.scope.locals = borrowed.scope.locals;
    var emitter: Emitter = .{ .allocator = t.allocator, .program = program, .function = current, .pc = 3, .branch_targets = &branches, .states = &states, .cow = &cow };
    try t.expect(try check(Emitter, &emitter, ty, 0));
    branches[3] = true;
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    branches[3] = false;
    state.readonly = true;
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    state.readonly = false;
    state.contract.result = .{ .borrowed = .{ .parameter = 0, .shape_identity = @splat(0), .dependency_identity = @splat(0) } };
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    state.contract.result = .owned;
    captures[2].active = 0;
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    captures[2] = .{ .begin = 0 };
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    captures[2] = .{};
    try t.expect(!try check(Emitter, &emitter, ty, 1));
    states[3] = null;
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    states[3] = &stack;
    code[2].op = .{ .invoke = ty };
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    code[2].op = .{ .value_copy = .{ .ty = ty, .site = .ret } };
    code[1].op = .{ .load_local = @fromBackingInt(0) };
    var copies: [count]bool = @splat(false);
    emitter.ownership = .{ .copies = &copies };
    try t.expect(!try check(Emitter, &emitter, ty, 0));
    copies[2] = true;
    try t.expect(try check(Emitter, &emitter, ty, 0));
}

// spec-case: RC-NATIVE-VARIANT-1
// spec-case: RC-DISJOINT-TAKE-1
test "RC-NATIVE-VARIANT-1 disjoint witness refuses branch borrowed callback capture and elided snapshot inputs" {
    try exercise(@import("qbe_rc_values.zig").producedOwner);
}
