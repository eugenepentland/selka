//! Closed direct-field ownership movement, independent of semantic copy bits.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const shapes = @import("rc_shape.zig");
const Op = @FieldType(bytecode.Instruction, "op");
/// An initialized caller-owned inline record field that may be temporarily empty.
pub const Source = struct { local: usize, field: usize, ty: typed.Type };
/// Exact extraction and unconditional return positions for one physical owner.
pub const Certificate = struct {
    source: Source,
    target: usize,
    projection: usize,
    store: usize,
    writeback: usize,
    commit: usize,
};
/// Proof refusal is ordinary lowering; malformed native layouts are compiler errors.
pub const Error = error{ InternalError, OutOfMemory };

/// Certify bounded straight-line intervals with no authority to observe the hole.
/// Semantic SHARE decisions alone never authorize physical ownership movement.
pub fn build(comptime E: type, self: *E, catalog: *shapes.Catalog) Error![]const Certificate {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or self.function.policy.c_abi or self.function.policy.host != null) return &.{};
    var found: std.ArrayList(Certificate) = .empty;
    var remaining: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .get_field or self.states[pc] == null) continue;
        if (code.len > remaining) break;
        remaining -= code.len;
        const proof = try extraction(E, self, pc, catalog) orelse continue;
        const end = try returned(E, self, proof, catalog) orelse continue;
        if (found.items.len != 0 and found.items[found.items.len - 1].commit >= pc - 1) continue;
        var complete = proof;
        complete.writeback = end;
        complete.commit = end + 10;
        try found.append(self.allocator, complete);
    }
    return found.toOwnedSlice(self.allocator);
}

fn extraction(comptime E: type, self: *E, pc: usize, catalog: *shapes.Catalog) Error!?Certificate {
    const code = self.function.scope.instructions;
    if (pc == 0 or pc + 2 >= code.len) return null;
    if (code[pc - 1].op != .load_local or code[pc + 1].op != .value_copy or code[pc + 2].op != .store_local) return null;
    if (code[pc + 1].op.value_copy.site != .assign) return null;
    const source = @backingInt(code[pc - 1].op.load_local);
    const target = @backingInt(code[pc + 2].op.store_local);
    if (self.moves.resolve(source) != source) return null;
    const locals = self.function.scope.locals;
    if (!self.callerStorage(source) or target < self.function.signature.parameter_count or locals[target].usage.temporary) return null;
    if (self.byReference(target) or self.callerStorage(target) or source == target) return null;
    if (self.cow.?.plan.place(target) != null) return null;
    const owner_ty = locals[source].ty;
    const owner = self.program.records[owner_ty.recordIndex()];
    if (!owner.isRecord() or owner.managed or (try shape(catalog, owner_ty)).unique_drop) return null;
    if (@import("value_semantics.zig").containsLiveView(self.program.records, owner_ty)) return null;
    const ty = locals[target].ty;
    if (!ty.isAggregate()) return null;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return null;
    if (!try @import("rc_field_authority.zig").safe(catalog, ty)) return null;
    if ((try shape(catalog, ty)).unique_drop or (catalog.native.layout(ty) catch return error.InternalError).size != 8) return null;
    for (locals[0..self.function.signature.parameter_count], 0..) |local, index| {
        if (index != source and !try plain(catalog, local.ty)) return null;
        if (index != source and @import("ownership_model.zig").writesParameter(self.function, index)) return null;
    }
    for (pc..pc + 3) |at| if (!straight(E, self, at)) return null;
    if ((self.states[pc - 1] orelse return null).len != 0) return null;
    const analysis = self.ownership orelse return null;
    if (analysis.roles[target] != .owned or code[pc + 1].op.value_copy.ty != ty) return null;
    for (locals, 0..) |_, index| {
        if (index != source and analysis.rootOf(@intCast(index)) == source and self.live.?.before(pc - 1, index)) return null;
    }
    return .{ .source = .{ .local = source, .field = code[pc].op.get_field, .ty = ty }, .target = target, .projection = pc, .store = pc + 2, .writeback = 0, .commit = 0 };
}

fn returned(comptime E: type, self: *E, proof: Certificate, catalog: *shapes.Catalog) Error!?usize {
    const code = self.function.scope.instructions;
    for (proof.store + 1..code.len) |pc| {
        if (writeback(E, self, proof, pc)) return pc;
        if (!straight(E, self, pc) or !try permitted(E, self, proof, pc, catalog)) return null;
    }
    return null;
}

fn straight(comptime E: type, self: *E, pc: usize) bool {
    if (self.states[pc] == null or self.isBranchTarget(pc)) return false;
    const op = self.function.scope.instructions[pc].op;
    var buffer: [2]usize = undefined;
    return @import("ownership_sources.zig").fallsThrough(op) and
        @import("ownership_sources.zig").branchTargets(op, &buffer).len == 0 and op != .switch_variant;
}

fn permitted(comptime E: type, self: *E, proof: Certificate, pc: usize, catalog: *shapes.Catalog) Error!bool {
    const op = self.function.scope.instructions[pc].op;
    return switch (op) {
        .load_local => |id| @backingInt(id) == proof.target or try plain(catalog, self.function.scope.locals[@backingInt(id)].ty),
        .store_local, .move_local, .drop_local => |id| try plain(catalog, self.function.scope.locals[@backingInt(id)].ty),
        .value_copy => |copy| try plain(catalog, copy.ty),
        .call => |id| call(E, self, proof, pc, self.program.functions[@backingInt(id)], catalog),
        .push_i64, .push_integer, .push_bool, .push_unit => true,
        .pop, .acknowledge => blk: {
            const stack = self.states[pc].?;
            break :blk stack.len != 0 and try plain(catalog, stack[stack.len - 1]);
        },
        else => false,
    };
}

fn call(comptime E: type, self: *E, proof: Certificate, pc: usize, callee: bytecode.Function, catalog: *shapes.Catalog) Error!bool {
    if (callee.policy.c_abi or callee.policy.host != null or !try plain(catalog, callee.signature.return_type)) return false;
    const operands = self.ownership.?.operands[pc] orelse return false;
    if (operands.len != callee.signature.parameter_count) return false;
    var mutable_target = false;
    for (callee.scope.locals[0..callee.signature.parameter_count], operands, 0..) |parameter, operand, index| {
        if (try plain(catalog, parameter.ty)) continue;
        if (parameter.ty != proof.source.ty or operand.origin != .local) return false;
        if (operand.part != .whole or operand.local != proof.target) return false;
        if (!@import("ownership_model.zig").writesParameter(callee, index) or mutable_target) return false;
        mutable_target = true;
    }
    return mutable_target;
}

fn writeback(comptime E: type, self: *E, proof: Certificate, pc: usize) bool {
    const code = self.function.scope.instructions;
    if (pc + 10 >= code.len) return false;
    const ops = code[pc..][0..11];
    if (!localIs(ops[0].op, .load_local, proof.target) or ops[1].op != .store_local) return false;
    const value = @backingInt(ops[1].op.store_local);
    if (!localIs(ops[2].op, .load_local, proof.source.local) or ops[3].op != .store_local) return false;
    const parent = @backingInt(ops[3].op.store_local);
    const locals = self.function.scope.locals;
    if (!locals[value].usage.temporary or !locals[parent].usage.temporary) return false;
    if (value == parent) return false;
    if (value == proof.source.local or value == proof.target or parent == proof.source.local or parent == proof.target) return false;
    if (!localIs(ops[4].op, .load_local, proof.source.local) or !localIs(ops[5].op, .store_local, parent)) return false;
    if (!localIs(ops[6].op, .load_local, parent) or !localIs(ops[7].op, .load_local, value)) return false;
    if (ops[8].op != .value_copy or ops[8].op.value_copy.site != .store or ops[9].op != .update_record) return false;
    const update = ops[9].op.update_record;
    if (update.ty != locals[proof.source.local].ty or update.indices.len != 1 or update.indices[0] != proof.source.field) return false;
    if (!localIs(ops[10].op, .store_local, proof.source.local)) return false;
    for (pc..pc + 11) |at| if (!straight(E, self, at)) return false;
    for ([_]usize{ proof.target, value, parent }) |local| if (self.live.?.after(pc + 10, local)) return false;
    return true;
}

fn localIs(op: Op, comptime tag: std.meta.Tag(Op), index: usize) bool {
    return op == tag and @backingInt(@field(op, @tagName(tag))) == index;
}

fn shape(catalog: *shapes.Catalog, ty: typed.Type) Error!shapes.Shape {
    return catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

// Plain numeric aggregates can cross a call; callable/capability/handle bits
// cannot. Both workspace and visited-node work are bounded for shared schemas.
fn plain(catalog: *shapes.Catalog, ty: typed.Type) Error!bool {
    var pending: [64]typed.Type = undefined;
    pending[0] = ty;
    var count: usize = 1;
    var remaining: usize = 1024;
    while (count != 0) {
        if (remaining == 0) return false;
        remaining -= 1;
        count -= 1;
        const current = pending[count];
        const layout = catalog.native.layout(current) catch return error.InternalError;
        if (layout.drop or layout.copy == .prohibited) return false;
        switch (layout.kind) {
            .scalar => if (!current.isInteger() and current != .bool and current != .unit) return false,
            .record, .variant, .domain, .array => {
                if (layout.fields.len > pending.len - count) return false;
                for (layout.fields) |field| {
                    pending[count] = field.ty;
                    count += 1;
                }
            },
            else => return false,
        }
    }
    return true;
}
