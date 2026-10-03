//! A stricter closed field transfer lends its actual field to one mut call.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const authority = @import("rc_field_authority.zig");
const Error = authority.Error;

/// Refine an existing ownership/alias proof without accepting new guest syntax.
/// Only one direct record-inout call, with plain operands and result, qualifies.
pub fn qualifies(comptime E: type, comptime P: type, self: *E, proof: P, catalog: *shapes.Catalog) Error!bool {
    if (self.step_checks or !proof.returns()) return false;
    if (!typed.referenceRecord(self.program.records, proof.source.ty)) return false;
    const code = self.function.scope.instructions;
    var reference: ?usize = null;
    var call: ?usize = null;
    for (proof.store + 1..proof.writeback) |pc| {
        if (self.isBranchTarget(pc) or self.states[pc] == null) return false;
        switch (code[pc].op) {
            .ref_local => |id| {
                if (@backingInt(id) != proof.target or reference != null) return false;
                reference = pc;
            },
            .call => {
                if (call != null or reference == null) return false;
                if (!try accepts(E, P, self, proof, reference.?, pc, catalog)) return false;
                call = pc;
            },
            else => if (!try plainInstruction(E, self, code[pc].op, catalog)) return false,
        }
    }
    if (call == null or reference == null) return false;
    if (!soleTarget(E, P, self, proof, reference.?)) return false;
    // The source load is also skipped. The original proof checks other steps.
    const site = self.cow.?.plan.at(proof.projection - 1);
    if (site.unique.len != 0 or site.unique_field != null or site.fill or site.capture) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0) return false;
    return self.cow.?.plan.entry(proof.projection - 1).len == 0;
}

fn soleTarget(comptime E: type, comptime P: type, self: *E, proof: P, reference: usize) bool {
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .store_local => |id| if (@backingInt(id) == proof.target and pc != proof.store) return false,
        .load_local => |id| if (@backingInt(id) == proof.target and pc != proof.writeback) return false,
        .ref_local => |id| if (@backingInt(id) == proof.target and pc != reference) return false,
        .move_local, .drop_local => |id| if (@backingInt(id) == proof.target) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |slot| if (@backingInt(slot) == proof.target) return false;
        },
        else => {},
    };
    return true;
}

fn accepts(comptime E: type, comptime P: type, self: *E, proof: P, reference: usize, pc: usize, catalog: *shapes.Catalog) Error!bool {
    const callee = self.program.functions[@backingInt(self.function.scope.instructions[pc].op.call)];
    const count = callee.signature.parameter_count;
    const stack = self.states[pc] orelse return false;
    if (stack.len != count or callee.signature.declared_mutates.len != 1) return false;
    const parameter = callee.signature.declared_mutates[0];
    if (parameter >= count or callee.scope.locals[parameter].ty != proof.source.ty) return false;
    const operands = self.ownership.?.operands[pc] orelse return false;
    if (operands.len != count) return false;
    for (operands, callee.scope.locals[0..count], 0..) |operand, local, index| {
        if (index != parameter) {
            if (!try plain(catalog, local.ty)) return false;
            continue;
        }
        if (operand.origin != .local or operand.local != proof.target) return false;
        if (operand.part != .whole or operand.read != reference) return false;
    }
    if (!try plain(catalog, callee.signature.return_type)) return false;
    return directGraph(self.program.functions, @backingInt(self.function.scope.instructions[pc].op.call));
}

fn plainInstruction(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), catalog: *shapes.Catalog) Error!bool {
    return switch (op) {
        .load_local => |id| !self.byReference(@backingInt(id)) and try plain(catalog, self.function.scope.locals[@backingInt(id)].ty),
        .value_copy => |copy| plain(catalog, copy.ty),
        .push_unit, .push_bool, .push_i64, .push_integer, .pop, .acknowledge => true,
        else => false,
    };
}

fn plain(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    const layout = catalog.native.layout(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    if (layout.drop or layout.trace or layout.copy == .prohibited) return false;
    return authority.safe(catalog, ty);
}

const Graph = struct {
    pending: [256]usize = undefined,
    seen: [256]usize = undefined,
    count: usize = 0,
    visited: usize = 0,
    remaining: usize = 65536,

    fn append(self: *Graph, id: usize) bool {
        for (self.seen[0..self.visited]) |previous| if (previous == id) return true;
        if (self.count == self.pending.len or self.visited == self.seen.len) return false;
        self.pending[self.count] = id;
        self.count += 1;
        self.seen[self.visited] = id;
        self.visited += 1;
        return true;
    }
};

// No callable argument or reachable indirect/host call can observe the parent.
// Ordinary callee branches/returns and allocation retain their own lowering.
fn directGraph(functions: []const bytecode.Function, entry: usize) bool {
    var graph: Graph = .{};
    if (!graph.append(entry)) return false;
    while (graph.count != 0) {
        graph.count -= 1;
        const callee = functions[graph.pending[graph.count]];
        if (callee.policy.c_abi or callee.policy.host != null) return false;
        if (callee.scope.instructions.len > graph.remaining) return false;
        graph.remaining -= callee.scope.instructions.len;
        for (callee.scope.instructions) |instruction| switch (instruction.op) {
            .invoke => return false,
            .call => |id| if (!graph.append(@backingInt(id))) return false,
            else => {},
        };
    }
    return true;
}
