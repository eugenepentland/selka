//! Type-disjoint text work cannot publish a fresh scalar dictionary root.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const cow = @import("cow_plan.zig");
const model = @import("rc_dictionary_tail.zig");
const effects = @import("qbe_rc_dictionary_effects.zig");
const Error = @import("qbe_rc_frame.zig").Error;
const Op = @FieldType(bytecode.Instruction, "op");

/// An ordinary owning key may be rebuilt each iteration. Its immutable text
/// shape contains only octets, so its shares, allocations and drops cannot
/// add an owner or callback to the dictionary. Keep the old key/drop protocol.
pub fn lifetime(comptime E: type, self: *E, proof: model.Certificate, definition: usize, back: usize, budget: *model.Budget) Error!bool {
    const plan = self.cow.?.plan;
    const physical = self.cow.?.rc.?.plan;
    for (physical.dictionary_tails) |other| {
        if (!budget.take(1)) return false;
        if (other.root == proof.root and other.start != proof.start) return false;
    }
    for (plan.loops.entries) |entries| {
        if (!budget.take(entries.len + 1)) return false;
        for (entries) |check| if (check.local == proof.root) return false;
    }
    for (definition..back + 1) |pc| {
        if (!budget.take(1)) return false;
        const instruction = self.function.scope.instructions[pc];
        const stack = self.states[pc] orelse return false;
        if (instruction.inline_origin != null) return false;
        if (!try quiet(E, self, proof, pc, budget)) return false;
        if (pc == definition) continue;
        if (pc >= proof.start and pc <= proof.start + 4) continue;
        if (!try operation(E, self, proof, instruction.op)) return false;
        for (stack) |ty| {
            if (!budget.take(1) or !try disjoint(E, self, ty)) return false;
        }
    }
    return true;
}

fn quiet(comptime E: type, self: *E, proof: model.Certificate, pc: usize, budget: *model.Budget) Error!bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    const physical = state.rc.?.plan;
    if (!budget.take(physical.records.transfers.len + physical.records.writes.len + 1)) return false;
    if (effects.intercepted(E, self, pc)) return false;
    if (pc >= proof.start and pc <= proof.start + 4) {
        if (!effects.quiet(E, self, proof, pc)) return false;
    } else {
        if (site.capture or site.fill or site.unique_field != null) return false;
        if (site.unique.len != 0) return false;
        if (site.read_captures.len != 0 or state.plan.entry(pc).len != 0) return false;
        if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
        const stack = self.states[pc] orelse return false;
        for (site.shares) |depth| {
            if (!budget.take(1) or depth >= stack.len) return false;
            if (!try disjoint(E, self, stack[depth])) return false;
        }
    }
    for (physical.locals.edges) |edge| {
        if (!budget.take(1)) return false;
        if (edge.from != pc) continue;
        for (edge.releases) |release| {
            if (!budget.take(1)) return false;
            const local = @backingInt(release.storage);
            // The certified borrowed receiver's guard is always zero.
            if (local == proof.receiver) continue;
            if (local == proof.root or local >= self.function.scope.locals.len) return false;
            if (!try disjoint(E, self, self.function.scope.locals[local].ty)) return false;
        }
    }
    return true;
}

fn operation(comptime E: type, self: *E, proof: model.Certificate, op: Op) Error!bool {
    const catalog = &self.cow.?.rc.?.catalog;
    if (try @import("qbe_rc_read_loans.zig").scalar(E, self, op, catalog)) return true;
    return switch (op) {
        .pop => true,
        .load_local, .store_local => |local| disjoint(E, self, self.function.scope.locals[@backingInt(local)].ty),
        .value_copy => |copy| text(E, self, copy.ty),
        .array_length => |ty| text(E, self, ty),
        .make_record => |record| record.fields == 0 and record.payload.len != 0 and try text(E, self, record.ty),
        .buffer_operation => |buffer| blk: {
            const owner = @backingInt(buffer.owner);
            if (owner == proof.root) break :blk (buffer.kind == .get or buffer.kind == .length) and try disjoint(E, self, buffer.output);
            if (!try text(E, self, self.function.scope.locals[owner].ty)) break :blk false;
            break :blk (buffer.kind == .slice or buffer.kind == .length) and try disjoint(E, self, buffer.output);
        },
        else => false,
    };
}

fn disjoint(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    const shape = self.cow.?.rc.?.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
    if (shape.unique_drop) return false;
    return !shape.counted or try text(E, self, ty);
}
fn text(comptime E: type, self: *E, ty: typed.Type) Error!bool {
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.box) return false;
    if (record.collection.kind != .string and record.collection.kind != .bytes) return false;
    const shape = self.cow.?.rc.?.catalog.get(ty) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else false;
    return !shape.unique_drop;
}
