//! Numeric loops need no collection lifetime certificate when they touch no edges.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");

/// Admit only an already planned integer loop with no explicit or implicit
/// ownership action. Range guards, original fallback and emitted-call veto stay.
pub fn proven(comptime E: type, self: *E, head: usize, back: usize) bool {
    const code = self.function.scope.instructions;
    if (back < head or back >= code.len) return false;
    if (code.len > 4096 or back - head > @import("qbe_loop_facts.zig").max_body) return false;
    const state = self.cow orelse return false;
    const rc = state.rc orelse return false;
    const entry = self.states[head] orelse return false;
    if (entry.len != 0) return false;
    if (rc.plan.locals.edges.len > 4096) return false;
    for (rc.plan.locals.edges) |edge| {
        if (edge.from >= head and edge.from <= back and edge.releases.len != 0) return false;
    }
    var remaining: usize = 262144;
    for (head..back + 1) |pc| {
        if (code[pc].inline_origin != null) return false;
        const site = state.plan.at(pc);
        if (site.unique.len != 0 or site.unique_field != null) return false;
        if (site.fill or site.capture or site.shares.len != 0 or site.read_captures.len != 0) return false;
        if (state.plan.entry(pc).len != 0) return false;
        const capture = state.captures[pc];
        if (capture.begin != cow.none or capture.active != cow.none) return false;
        const stack = self.states[pc] orelse continue;
        if (stack.len > remaining) return false;
        remaining -= stack.len;
        for (stack) |ty| if (!scalar(ty)) return false;
        if (!operation(E, self, code[pc].op)) return false;
    }
    return true;
}

fn scalar(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool or ty == .unit;
}

fn operation(comptime E: type, self: *E, op: Op) bool {
    return switch (op) {
        .load_local, .store_local => |id| blk: {
            const local = @backingInt(id);
            if (self.byReference(local) or self.callerStorage(local)) break :blk false;
            break :blk scalar(self.function.scope.locals[local].ty);
        },
        .push_integer => |value| scalar(value.ty),
        .cast_integer, .neg_integer, .acknowledge => |ty| scalar(ty),
        .binary_integer => |binary| scalar(binary.ty),
        .push_i64,
        .push_bool,
        .push_unit,
        .pop,
        .jump,
        .jump_if_false,
        .cmp_i64,
        .cmp_bool,
        .not_bool,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        .assert_true,
        => true,
        else => false,
    };
}
