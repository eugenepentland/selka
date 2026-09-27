//! Linear fresh constructor operands can move directly into a guarded body.
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const frame = @import("qbe_rc_frame.zig");
const values = @import("qbe_rc_values.zig");
const loans = @import("qbe_rc_loans.zig");
const cow = @import("cow_plan.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const limit = 128;
/// Native emission failures; proof refusal retains ordinary typed preparation.
pub const Error = frame.Error;

/// Emit a guarded direct relocation and leave the ordinary fallback open.
/// The caller closes the returned label after its unchanged slow path.
pub fn begin(comptime E: type, self: *E, ty: typed.Type, operand: usize, source: usize, destination: usize) Error!?usize {
    if (!try certify(E, self)) return null;
    if ((try self.layout(ty)).size > 256) return null;
    const index = values.journalIndex(E, self, operand);
    const owner = try loans.owner(E, self, index);
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcfresh{d}, @rcfreshslow{d}\n@rcfresh{d}\n", .{ owner, label, label, label });
    // The internal construction guard already owns every initialized field.
    // These stores cannot trap or call out; future failure sees exactly one home.
    try self.print(values.blit_value, .{ source, destination, (try self.layout(ty)).size });
    try frame.initialized(E, self, index, false);
    try self.print(" jmp @rcfreshdone{d}\n@rcfreshslow{d}\n", .{ label, label });
    return label;
}

/// Preflight an entire bounded constructor before allocation or guard changes.
/// The closed grammar proves one inherited region; dynamic role refusal enters
/// the original complete constructor, including its partial-body journal.
pub fn beginSpan(comptime E: type, self: *E, ty: typed.Type, base: usize, count: usize) Error!?usize {
    if (count == 0 or count > limit or !try certify(E, self)) return null;
    if (try self.largeResult(self.function)) return null;
    if ((try self.layout(ty)).size > 256) return null;
    const state = frame.get(E, self).?;
    const result = state.catalog.get(ty) catch return error.InternalError;
    if (!result.counted or result.unique_drop) return null;
    const stack = self.states[self.pc] orelse return error.InternalError;
    if (base > stack.len or count > stack.len - base) return error.InternalError;
    for (stack[base..][0..count]) |input| {
        const shape = state.catalog.get(input) catch return error.InternalError;
        if (shape.unique_drop or (try self.layout(input)).size > 256) return null;
    }
    var ready: ?usize = null;
    for (stack[base..][0..count], base..) |input, operand| {
        const shape = state.catalog.get(input) catch return error.InternalError;
        if (!shape.counted) continue;
        const owner = try ordinaryRole(E, self, values.journalIndex(E, self, operand));
        if (ready) |previous| {
            const combined = self.temp();
            try self.print(" %v{d} =w and %v{d}, %v{d}\n", .{ combined, previous, owner });
            ready = combined;
        } else ready = owner;
    }
    const label = self.temp();
    if (ready) |condition| try self.print(" jnz %v{d}, @rcspan{d}, @rcspanslow{d}\n", .{ condition, label, label }) else try self.print(" jmp @rcspan{d}\n", .{label});
    try self.print("@rcspan{d}\n", .{label});
    return label;
}

fn ordinaryRole(comptime E: type, self: *E, index: usize) Error!usize {
    const live = self.temp();
    const flags = self.temp();
    const accepted = self.temp();
    const result = self.temp();
    try self.print(" %v{d} =w loaduw %v{d}\n %v{d} =w loaduw %v{d}\n", .{ live, try frame.guard(E, self, index), flags, try frame.entryField(E, self, index, 24) });
    try self.print(" %v{d} =w ceqw %v{d}, 2\n %v{d} =w and %v{d}, %v{d}\n", .{ accepted, flags, result, live, accepted });
    return result;
}

/// A closed scalar-input body creates only linearly consumed fresh bundles.
/// Self recursion is inductive over successful returns; all other calls refuse.
pub fn certify(comptime E: type, self: *E) Error!bool {
    const state = frame.get(E, self) orelse return false;
    const function = self.function;
    const code = function.scope.instructions;
    if (self.entry or self.heap_frame or @import("qbe_rc_borrow.zig").active(E, self)) return false;
    if (function.policy.c_abi or function.policy.host != null or code.len == 0 or code.len > limit) return false;
    if (function.signature.mutates.len != 0 or function.signature.declared_mutates.len != 0) return false;
    for (function.scope.locals) |local| if (!scalar(local.ty)) return false;
    const analysis = self.ownership orelse return false;
    // An immutable pointer copy still creates another ordinary owner, even
    // when mutable-history needsCopy sees no semantic SHARE operation.
    for (analysis.copies) |copied| if (copied) return false;
    for (analysis.transfers) |transfer| if (transfer.class != .move) return false;
    for (code, 0..) |instruction, pc| {
        if (instruction.inline_origin != null) return false;
        const capture = self.cow.?.captures[pc];
        if (capture.begin != cow.none or capture.active != cow.none) return false;
        const site = self.cow.?.plan.at(pc);
        if (site.read_captures.len != 0 or site.shares.len != 0) return false;
        if (site.unique.len != 0 or site.unique_field != null) return false;
        const stack = self.states[pc] orelse continue;
        for (stack) |ty| {
            const shape = state.catalog.get(ty) catch return error.InternalError;
            if (shape.unique_drop or !shape.copyable) return false;
            if (!ordinary(self.program.records, ty)) return false;
        }
        if (!allowed(E, self, pc, instruction.op, stack)) return false;
    }
    return ordinary(self.program.records, function.signature.return_type);
}

fn scalar(ty: typed.Type) bool {
    return ty.integer() != null or ty == .bool or ty == .unit;
}

fn allowed(comptime E: type, self: *E, pc: usize, op: Op, stack: []const typed.Type) bool {
    return switch (op) {
        .push_i64,
        .push_integer,
        .push_bool,
        .push_unit,
        .cmp_i64,
        .cmp_bool,
        .not_bool,
        .add_i64_checked,
        .sub_i64_checked,
        .mul_i64_checked,
        .div_i64_checked,
        .rem_i64_checked,
        .neg_i64_checked,
        => true,
        .load_local, .store_local => |id| scalar(self.function.scope.locals[@backingInt(id)].ty),
        .make_record => |record| ordinary(self.program.records, record.ty),
        .make_variant => |variant| ordinary(self.program.records, variant.ty),
        .call => |id| id == self.function.id,
        .ret => stack.len == 1,
        .jump => |target| stack.len == 0 and forward(E, self, pc, target),
        .jump_if_false => |target| stack.len == 1 and stack[0] == .bool and forward(E, self, pc, target),
        // Even an analysis-elided copy stays out of the initial closed grammar.
        // This also rejects all physical loan and future publication operations.
        else => false,
    };
}

fn forward(comptime E: type, self: *E, pc: usize, target: usize) bool {
    if (target <= pc or target >= self.states.len) return false;
    const stack = self.states[target] orelse return false;
    return stack.len == 0;
}

const Types = struct {
    seen: [limit]typed.Type = undefined,
    len: usize = 0,
    remaining: usize = limit * 4,

    fn add(self: *Types, ty: typed.Type) bool {
        if (self.remaining == 0) return false;
        self.remaining -= 1;
        for (self.seen[0..self.len]) |seen| if (seen == ty) return true;
        if (self.len == self.seen.len) return false;
        self.seen[self.len] = ty;
        self.len += 1;
        return true;
    }
};

// Follow every logical/physical type edge, including immutable box contents.
// Cycles use the fixed visited table; budget exhaustion conservatively refuses.
fn ordinary(records: []const typed.Record, root: typed.Type) bool {
    var types: Types = .{};
    if (!types.add(root)) return false;
    var next: usize = 0;
    while (next < types.len) : (next += 1) {
        const ty = types.seen[next];
        if (scalar(ty)) continue;
        if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
        const record = records[ty.recordIndex()];
        if (record.isCollection() or record.shape.resource != null or record.contract.callback != null) return false;
        if (record.shape.builtin == .live_view or (record.managed and !record.collection.box)) return false;
        if (record.shape.domain) |backing| if (!types.add(backing)) return false;
        if (record.shape.array) |array| if (!types.add(array.element)) return false;
        if (record.shape.variants) |variants| {
            if (variants.fallible) return false;
            for (variants.cases) |variant| if (variant.payload) |payload| if (!types.add(payload)) return false;
        }
        for (record.fields) |field| if (!types.add(field.ty)) return false;
    }
    return true;
}
