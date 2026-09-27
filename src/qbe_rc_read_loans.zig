//! Compiler receiver loans confined to inert collection read chains.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const input = @import("rc_input.zig");
const shapes = @import("rc_shape.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const rejected = ~@as(usize, 0);
/// Analysis and emission failures shared with the RC emitter.
pub const Error = error{ InternalError, OutOfMemory, WriteFailed, SourceError };

const Check = struct {
    definitions: []usize,
    stores: []usize,
    pending: []usize,
    count: usize = 0,
    remaining: usize = 262144,
};

/// Annotate single-definition compiler receivers and projected read chains.
/// Every borrowed descendant is anchored directly by the stable named root.
pub fn bind(comptime E: type, self: *E, bindings: []input.Binding, catalog: *shapes.Catalog) Error!void {
    const code = self.function.scope.instructions;
    const definitions = try self.allocator.alloc(usize, bindings.len);
    defer self.allocator.free(definitions);
    const stores = try self.allocator.alloc(usize, bindings.len);
    defer self.allocator.free(stores);
    const pending = try self.allocator.alloc(usize, bindings.len);
    defer self.allocator.free(pending);
    var check: Check = .{ .definitions = definitions, .stores = stores, .pending = pending };
    @memset(definitions, 0);
    @memset(stores, rejected);
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null) continue;
        switch (instruction.op) {
            .store_local => |local| {
                definitions[@backingInt(local)] +|= 1;
                stores[@backingInt(local)] = pc;
            },
            // Pattern bindings have unrepresented physical parents here.
            .switch_variant => |dispatch| for (dispatch.arms) |arm| {
                if (arm.slot) |local| definitions[@backingInt(local)] = rejected;
            },
            else => {},
        }
    }
    for (code, 0..) |instruction, pc| {
        if (self.states[pc] == null or instruction.op != .store_local or pc == 0) continue;
        const target = @backingInt(instruction.op.store_local);
        if (definitions[target] != 1 or !self.function.scope.locals[target].usage.temporary) continue;
        if (self.isBranchTarget(pc) or code[pc - 1].op != .load_local) continue;
        const source = @backingInt(code[pc - 1].op.load_local);
        if (definitions[source] == rejected) continue;
        if (source >= self.function.signature.parameter_count and definitions[source] == 0) continue;
        if (!candidate(E, self, source, target)) continue;
        if (!try chain(E, self, target, &check, catalog)) continue;
        for (pending[0..check.count]) |local| bindings[local].anchor = .{ .storage = bindings[source].storage };
    }
}

fn chain(comptime E: type, self: *E, target: usize, check: *Check, catalog: *shapes.Catalog) Error!bool {
    check.count = 1;
    check.pending[0] = target;
    var at: usize = 0;
    while (at < check.count) : (at += 1) {
        const cost = self.function.scope.instructions.len;
        if (cost > check.remaining) return false;
        check.remaining -= cost;
        if (!try valid(E, self, check.pending[at], check, catalog)) return false;
    }
    return true;
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

fn valid(comptime E: type, self: *E, target: usize, check: *Check, catalog: *shapes.Catalog) Error!bool {
    var read = false;
    for (self.function.scope.instructions, 0..) |instruction, pc| {
        if (pc == check.stores[target] or self.states[pc] == null or !self.live.?.before(pc, target)) continue;
        const op = instruction.op;
        if (op == .cast_integer) {
            const stack = self.states[pc].?;
            if (stack.len == 0 or !try plain(E, self, stack[stack.len - 1], catalog)) return false;
        }
        if (op == .buffer_operation) {
            const operation = op.buffer_operation;
            if (@backingInt(operation.owner) != target) return false;
            if (operation.kind != .length and operation.kind != .read) return false;
            if (!try terminal(E, self, operation.output, catalog)) {
                if (operation.kind != .read) return false;
                if (try @import("qbe_rc_plain_projection.zig").end(E, self, pc, catalog) == null and !child(E, self, pc, check)) return false;
            }
            read = true;
        } else if (!try scalar(E, self, op, catalog)) return false;
    }
    return read;
}

// Only an immediate compiler receiver can consume a borrowed managed result.
// A named row, return, callback argument or aggregate publication still owns.
fn child(comptime E: type, self: *E, pc: usize, check: *Check) bool {
    const code = self.function.scope.instructions;
    const owner = @backingInt(code[pc].op.buffer_operation.owner);
    const parent = self.function.scope.locals[owner].ty;
    // Text indexing constructs an owned character; only list reads lend an
    // existing managed element whose physical lifetime follows this root.
    if (self.program.records[parent.recordIndex()].collection.kind != .list) return false;
    if (pc + 1 >= code.len or code[pc + 1].op != .store_local or self.isBranchTarget(pc + 1)) return false;
    const local = @backingInt(code[pc + 1].op.store_local);
    if (check.definitions[local] != 1 or check.stores[local] != pc + 1) return false;
    if (local < self.function.signature.parameter_count or !self.function.scope.locals[local].usage.temporary) return false;
    if (self.byReference(local) or self.callerStorage(local) or self.cow.?.plan.place(local) != null) return false;
    const ty = self.function.scope.locals[local].ty;
    if (!ty.isAggregate() or ty != code[pc].op.buffer_operation.output) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box or record.collection.kind == .dictionary) return false;
    for (check.pending[0..check.count]) |previous| if (previous == local) return false;
    check.pending[check.count] = local;
    check.count += 1;
    return true;
}

/// The next store adopts this managed read as an anchored compiler loan.
/// Its consumed index is plain, so the result's operand guard stays clear.
pub fn borrowedResult(comptime E: type, self: *E, op: Op) Error!bool {
    if (try @import("qbe_rc_plain_projection.zig").borrowed(E, self, op)) return true;
    if (op != .buffer_operation or op.buffer_operation.kind != .read) return false;
    const code = self.function.scope.instructions;
    if (self.pc + 1 >= code.len or code[self.pc + 1].op != .store_local) return false;
    const state = self.cow.?.rc orelse return false;
    const target = @backingInt(code[self.pc + 1].op.store_local);
    const ownership = state.plan.locals.entry[target].ownership;
    return ownership == .borrowed and ownership.borrowed == .storage;
}

fn plain(comptime E: type, self: *E, ty: typed.Type, catalog: *shapes.Catalog) Error!bool {
    if (!self.isScalar(ty)) return false;
    return terminal(E, self, ty, catalog);
}

// Plain inline results are copied to operand scratch by values.finish before
// the receiver anchor can end. No interior pointer or ownership token escapes.
// Keep the intervening instruction whitelist scalar-only.
fn terminal(comptime E: type, self: *E, ty: typed.Type, catalog: *shapes.Catalog) Error!bool {
    _ = self;
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
    const ownership = state.plan.locals.entry[index].ownership;
    if (ownership != .borrowed or ownership.borrowed != .storage) return false;
    const payload = try self.load("s", operand);
    try self.print(" storel %v{d}, %l{d}\n", .{ payload, index });
    return true;
}
