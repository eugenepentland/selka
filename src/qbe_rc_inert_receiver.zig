//! Bounded proofs that a captured list receiver needs no temporary pin scope.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const Path = struct { locals: [8]usize = undefined, len: usize = 0 };

/// Keep the ordinary owning anchor live through a closed scalar-only interval.
/// Unknown effects, managed publication, callbacks, backwards edges and entries
/// bypassing the capture retain the complete existing held/pinned protocol.
pub fn proven(comptime E: type, self: *E, local: usize) bool {
    const code = self.function.scope.instructions;
    if (code.len > 4096 or !self.function.scope.locals[local].usage.temporary) return false;
    const start = definition(E, self, local) orelse return false;
    var end: ?usize = null;
    var path: Path = .{};
    for (code, 0..) |instruction, pc| {
        if (instruction.op != .buffer_operation) continue;
        const operation = instruction.op.buffer_operation;
        if (!operation.kind.writesReceiver()) continue;
        const candidate = ancestors(E, self, @backingInt(operation.owner)) orelse continue;
        if (!contains(candidate, local)) continue;
        if (end != null) return false;
        end = pc;
        path = candidate;
    }
    const stop = end orelse return false;
    if (stop <= start or stop - start > 256) return false;
    const root = path.locals[path.len - 1];
    if (self.function.scope.locals[root].usage.temporary or !self.live.?.before(stop, root)) return false;
    const receiver = self.function.scope.locals[path.locals[0]].ty;
    const element = self.program.records[receiver.recordIndex()].shape.buffer orelse return false;
    if (!plain(E, self, element)) return false;
    const inputs = self.states[stop] orelse return false;
    for (inputs) |ty| if (!plain(E, self, ty)) return false;
    if (!plain(E, self, code[stop].op.buffer_operation.output)) return false;
    for (code, 0..) |instruction, pc| {
        if (externalEntry(instruction.op, pc, start, stop)) return false;
        if (pc > start and pc < stop and !inert(E, self, pc, path, local)) return false;
    }
    return true;
}

fn contains(path: Path, local: usize) bool {
    for (path.locals[0..path.len]) |index| if (index == local) return true;
    return false;
}

fn ancestors(comptime E: type, self: *E, first: usize) ?Path {
    var path: Path = .{};
    var at = first;
    const plan = self.cow.?.plan;
    while (path.len < path.locals.len) {
        if (!list(E, self, at) or contains(path, at)) return null;
        path.locals[path.len] = at;
        path.len += 1;
        if (plan.place(at)) |place| {
            if (place.step != .element or place.box != null) return null;
            at = place.parent;
        } else if (at < plan.aliases.len and plan.aliases[at] != cow.none) {
            at = plan.aliases[at];
        } else return if (path.len > 1) path else null;
    }
    return null;
}

fn definition(comptime E: type, self: *E, local: usize) ?usize {
    var result: ?usize = null;
    for (self.function.scope.instructions, 0..) |instruction, pc| {
        if (instruction.op != .store_local or @backingInt(instruction.op.store_local) != local) continue;
        if (result != null) return null;
        result = pc;
    }
    return result;
}

fn list(comptime E: type, self: *E, index: usize) bool {
    const ty = self.function.scope.locals[index].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.isCollection() and record.collection.kind == .list and !record.collection.box;
}

fn plain(comptime E: type, self: *E, ty: typed.Type) bool {
    const shape = self.cow.?.rc.?.catalog.get(ty) catch return false;
    return !shape.counted and !shape.unique_drop;
}

fn inert(comptime E: type, self: *E, pc: usize, path: Path, local: usize) bool {
    const op = self.function.scope.instructions[pc].op;
    const inputs = self.states[pc] orelse return false;
    for (inputs) |ty| if (!plain(E, self, ty)) {
        if (inputs.len != 1 or op != .store_local or !contains(path, @backingInt(op.store_local))) return false;
    };
    return switch (op) {
        .load_local => |id| plain(E, self, self.function.scope.locals[@backingInt(id)].ty),
        .store_local => |id| store(E, self, pc, @backingInt(id), path, local),
        .value_copy => |copy| plain(E, self, copy.ty),
        .buffer_operation => |operation| switch (operation.kind) {
            .length, .capacity => list(E, self, @backingInt(operation.owner)),
            .read => read(E, self, pc, path),
            else => false,
        },
        .jump, .jump_if_false => |target| target > pc,
        .push_i64,
        .push_integer,
        .push_bool,
        .push_unit,
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
        .wrap_domain,
        .unwrap_domain,
        .assert_true,
        => true,
        .cast_integer, .neg_integer => |ty| ty.integer() != null,
        .binary_integer => |operation| operation.ty.integer() != null,
        else => false,
    };
}

fn store(comptime E: type, self: *E, pc: usize, index: usize, path: Path, local: usize) bool {
    if (!contains(path, index)) return plain(E, self, self.function.scope.locals[index].ty);
    // Only a new descendant receiver can be filled. The captured receiver and
    // all its owning ancestors must keep exactly the same physical storage.
    for (path.locals[0..path.len]) |item| {
        if (item == local) return false;
        if (item == index) return definition(E, self, index) == pc;
    }
    return false;
}

fn read(comptime E: type, self: *E, pc: usize, path: Path) bool {
    const code = self.function.scope.instructions;
    const operation = code[pc].op.buffer_operation;
    if (!list(E, self, @backingInt(operation.owner))) return false;
    if (plain(E, self, operation.output)) return true;
    if (!contains(path, @backingInt(operation.owner)) or pc + 1 >= code.len) return false;
    return code[pc + 1].op == .store_local and contains(path, @backingInt(code[pc + 1].op.store_local));
}

fn externalEntry(op: Op, pc: usize, start: usize, stop: usize) bool {
    return switch (op) {
        .jump, .jump_if_false => |target| invalidEdge(pc, target, start, stop),
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (invalidEdge(pc, arm.target, start, stop)) break true;
        } else false,
        .try_result => |propagate| invalidEdge(pc, propagate.error_target, start, stop),
        else => false,
    };
}

fn invalidEdge(pc: usize, target: usize, start: usize, stop: usize) bool {
    if (pc > start and pc < stop) return target <= pc or target > stop;
    return target > start and target <= stop;
}
