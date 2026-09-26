//! Compiler receiver loans confined to scalar collection reads.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const input = @import("rc_input.zig");
const shapes = @import("rc_shape.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const rejected = ~@as(usize, 0);
/// Analysis and emission failures shared with the RC emitter.
pub const Error = error{ InternalError, OutOfMemory, WriteFailed, SourceError };

/// Annotate only single-definition compiler receivers whose complete live
/// ranges contain scalar operations and non-owning collection reads.
pub fn bind(comptime E: type, self: *E, bindings: []input.Binding, catalog: *shapes.Catalog) Error!void {
    const code = self.function.scope.instructions;
    const definitions = try self.allocator.alloc(usize, bindings.len);
    defer self.allocator.free(definitions);
    @memset(definitions, 0);
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null) continue;
        switch (instruction.op) {
            .store_local => |local| definitions[@backingInt(local)] +|= 1,
            // Pattern bindings can be loans whose physical parent is outside
            // this initial proof; do not use them as receiver anchors.
            .switch_variant => |dispatch| for (dispatch.arms) |arm| {
                if (arm.slot) |local| definitions[@backingInt(local)] = rejected;
            },
            else => {},
        }
    }
    // Refusal falls back to ordinary ownership; analysis work stays bounded.
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null or instruction.op != .store_local or pc == 0) continue;
        const target = @backingInt(instruction.op.store_local);
        if (definitions[target] != 1 or !self.function.scope.locals[target].usage.temporary) continue;
        if (self.isBranchTarget(pc) or code[pc - 1].op != .load_local) continue;
        const source = @backingInt(code[pc - 1].op.load_local);
        if (definitions[source] == rejected) continue;
        if (source >= self.function.signature.parameter_count and definitions[source] == 0) continue;
        if (!candidate(E, self, source, target)) continue;
        if (code.len > remaining) break;
        remaining -= code.len;
        if (!try valid(E, self, target, pc, catalog)) continue;
        bindings[target].anchor = .{ .storage = bindings[source].storage };
    }
}

fn candidate(comptime E: type, self: *E, source: usize, target: usize) bool {
    if (source == target or target < self.function.signature.parameter_count) return false;
    const from = self.function.scope.locals[source];
    const into = self.function.scope.locals[target];
    if (from.usage.temporary or from.ty != into.ty or !into.ty.isAggregate()) return false;
    if (self.byReference(source) or self.callerStorage(source) or self.byReference(target)) return false;
    const plan = self.cow.?.plan;
    if (plan.place(source) != null) return false;
    if (source < plan.aliases.len and plan.aliases[source] != @import("cow_plan.zig").none) return false;
    const record = self.program.records[into.ty.recordIndex()];
    if (!record.isCollection() or record.collection.box or record.collection.kind == .dictionary) return false;
    return plan.place(target) == null;
}

fn valid(comptime E: type, self: *E, target: usize, store_pc: usize, catalog: *shapes.Catalog) Error!bool {
    var read = false;
    for (self.function.scope.instructions, 0..) |instruction, pc| {
        if (pc == store_pc or self.states[pc] == null or !self.live.?.before(pc, target)) continue;
        const op = instruction.op;
        if (op == .cast_integer) {
            const stack = self.states[pc].?;
            if (stack.len == 0 or !try plain(E, self, stack[stack.len - 1], catalog)) return false;
        }
        if (op == .buffer_operation) {
            const operation = op.buffer_operation;
            if (@backingInt(operation.owner) != target) return false;
            if (operation.kind != .length and operation.kind != .read) return false;
            if (!try plain(E, self, operation.output, catalog)) return false;
            read = true;
        } else if (!try scalar(E, self, op, catalog)) return false;
    }
    return read;
}

fn plain(comptime E: type, self: *E, ty: typed.Type, catalog: *shapes.Catalog) Error!bool {
    if (!self.isScalar(ty)) return false;
    const shape = catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    return !shape.counted and !shape.unique_drop;
}

fn scalar(comptime E: type, self: *E, op: Op, catalog: *shapes.Catalog) Error!bool {
    return switch (op) {
        .push_i64,
        .push_bool,
        .push_unit,
        .jump,
        .jump_if_false,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        .cmp_i64,
        .cmp_bool,
        .not_bool,
        .unary_float,
        => true,
        .load_local, .store_local => |local| plain(E, self, self.function.scope.locals[@backingInt(local)].ty, catalog),
        .push_integer => |value| plain(E, self, value.ty, catalog),
        .cast_integer, .neg_integer, .wrap_domain, .unwrap_domain => |ty| plain(E, self, ty, catalog),
        .binary_integer => |operation| plain(E, self, operation.ty, catalog),
        .cmp_domain => |comparison| plain(E, self, comparison.ty, catalog),
        .cmp_enum => |comparison| plain(E, self, comparison.ty, catalog),
        else => false,
    };
}

/// Store a certified borrowed pointer with a clear journal guard. Its source
/// load is borrowed, and the planner retains the physical source anchor.
pub fn store(comptime E: type, self: *E, index: usize, operand: usize) Error!bool {
    const state = self.cow.?.rc orelse return false;
    const ownership = state.locals.entry[index].ownership;
    if (ownership != .borrowed or ownership.borrowed != .storage) return false;
    const payload = try self.load("s", operand);
    try self.print(" storel %v{d}, %l{d}\n", .{ payload, index });
    return true;
}
