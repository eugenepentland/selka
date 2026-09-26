//! Physical loop-entry uniqueness after receiver and local lifetimes stabilize.
const std = @import("std");
const typed = @import("typed.zig");
const cow = @import("cow_plan.zig");
const ownership = @import("ownership.zig");
const frame = @import("qbe_rc_frame.zig");
const inert = @import("qbe_rc_inert_receiver.zig");
/// Optional proof refusal keeps all original checks; allocation failures propagate.
pub const Error = frame.Error;

/// Refine only checks already hoisted by semantic analysis, after physical
/// loans are known. Preserve the place graph and its conservative liveness.
pub fn refine(comptime E: type, self: *E) Error!bool {
    _ = frame.get(E, self) orelse return false;
    const original = self.ownership orelse return false;
    const stores = try receiverStores(E, self);
    var checks: std.ArrayList(ownership.Cow) = .empty;
    var accepted = false;
    var budget: usize = 262144;
    for (original.cows) |site| {
        var check = site;
        check.hoisted = cow.none;
        if (site.needed and site.hoisted != cow.none and budget >= self.function.scope.instructions.len) {
            budget -= self.function.scope.instructions.len;
            if (proven(E, self, site, stores)) {
                check.hoisted = site.hoisted;
                accepted = true;
                // Element detachment requires an already unique outer list.
                // Keep this root check first even for caller-owned parameters.
                if (site.elements) {
                    var root = check;
                    root.elements = false;
                    try checks.append(self.allocator, root);
                }
            }
        }
        try checks.append(self.allocator, check);
    }
    if (!accepted) return false;
    var analysis = original;
    analysis.cows = checks.items;
    const candidate = try cow.plan(self.allocator, .{
        .program = self.program,
        .function = self.function,
        .states = self.states,
        .analysis = analysis,
        .shares = false,
    });
    const previous = self.cow.?.plan;
    if (!std.mem.eql(u32, previous.aliases, candidate.aliases)) return false;
    if (previous.places.len != candidate.places.len) return false;
    for (previous.places, candidate.places) |left, right| if (!std.meta.eql(left, right)) return false;
    self.cow.?.plan = candidate;
    return true;
}

/// An entry check covers the exact owning slot throughout its proved loop.
/// The entry instruction itself must still emit the actual runtime check.
pub fn covers(comptime E: type, self: *E, local: usize) bool {
    const plan = self.cow.?.plan;
    for (plan.loops.entries, 0..) |entries, head| {
        if (self.pc <= head or self.pc > plan.loops.back[head]) continue;
        for (entries) |entry| if (!entry.elements and entry.local == local) return true;
    }
    return false;
}

fn proven(comptime E: type, self: *E, site: ownership.Cow, stores: []const bool) bool {
    const code = self.function.scope.instructions;
    const head = site.hoisted;
    const back = self.cow.?.plan.loops.back[head];
    if (code.len > 4096 or back == cow.none or back < head or back - head > 1024) return false;
    if (site.pc < head or site.pc > back) return false;
    const root = self.function.scope.locals[site.local];
    if (root.usage.temporary or self.byReference(site.local) or self.callerStorage(site.local)) return false;
    if (!self.live.?.before(head, site.local) or self.cow.?.plan.place(site.local) != null) return false;
    const element = listElement(E, self, root.ty) orelse return false;
    if (site.elements) {
        const leaf = listElement(E, self, element) orelse return false;
        if (!plain(E, self, leaf)) return false;
    } else if (!plain(E, self, element) and listElement(E, self, element) == null) return false;
    for (code, 0..) |instruction, pc| {
        if (invalidEdge(instruction.op, pc, head, back)) return false;
        if (pc < head or pc > back or self.states[pc] == null) continue;
        if (!allowed(E, self, pc, site.local, stores)) return false;
    }
    return true;
}

fn plain(comptime E: type, self: *E, ty: typed.Type) bool {
    const shape = self.cow.?.rc.?.catalog.get(ty) catch return false;
    return !shape.counted and !shape.unique_drop;
}

fn listElement(comptime E: type, self: *E, ty: typed.Type) ?typed.Type {
    if (!ty.isAggregate()) return null;
    const record = self.program.records[ty.recordIndex()];
    if (!record.isCollection() or record.collection.kind != .list or record.collection.box) return null;
    return record.shape.buffer;
}

fn receiverStores(comptime E: type, self: *E) Error![]bool {
    const code = self.function.scope.instructions;
    const result = try self.allocator.alloc(bool, code.len);
    @memset(result, false);
    var budget: usize = 262144;
    for (code, 0..) |instruction, pc| {
        if (self.isBranchTarget(pc) or instruction.op != .store_local) continue;
        const local = @backingInt(instruction.op.store_local);
        if (!self.function.scope.locals[local].usage.temporary) continue;
        const role = self.cow.?.rc.?.locals.entry[local].ownership;
        if (role == .borrowed and role.borrowed == .storage) {
            result[pc] = true;
        } else if (code.len <= budget) {
            budget -= code.len;
            result[pc] = inert.proven(E, self, local);
        }
    }
    return result;
}

fn borrowedStore(stores: []const bool, pc: usize) bool {
    return pc < stores.len and stores[pc];
}

fn allowed(comptime E: type, self: *E, pc: usize, root: usize, stores: []const bool) bool {
    const code = self.function.scope.instructions;
    const op = code[pc].op;
    const inputs = self.states[pc].?;
    for (inputs) |ty| if (!plain(E, self, ty)) {
        if (inputs.len != 1 or !borrowedStore(stores, pc)) return false;
    };
    return switch (op) {
        .load_local => |id| plain(E, self, self.function.scope.locals[@backingInt(id)].ty) or borrowedStore(stores, pc + 1),
        .store_local => |id| @backingInt(id) != root and (plain(E, self, self.function.scope.locals[@backingInt(id)].ty) or borrowedStore(stores, pc)),
        .value_copy => |copy| plain(E, self, copy.ty),
        .buffer_operation => |operation| operationAllowed(E, self, pc, operation, stores),
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
        .assert_true,
        .pop,
        => true,
        .push_integer => |value| plain(E, self, value.ty),
        .cast_integer, .neg_integer, .wrap_domain, .unwrap_domain, .acknowledge => |ty| plain(E, self, ty),
        .binary_integer => |operation| plain(E, self, operation.ty),
        .cmp_domain => |comparison| plain(E, self, comparison.ty),
        .cmp_enum => |comparison| plain(E, self, comparison.ty),
        else => false,
    };
}

fn operationAllowed(comptime E: type, self: *E, pc: usize, operation: anytype, stores: []const bool) bool {
    const element = listElement(E, self, self.function.scope.locals[@backingInt(operation.owner)].ty) orelse return false;
    return switch (operation.kind) {
        .length, .capacity => plain(E, self, operation.output),
        .read => plain(E, self, operation.output) or borrowedStore(stores, pc + 1),
        .write => plain(E, self, element) and plain(E, self, operation.output),
        else => false,
    };
}

fn invalidEdge(op: @FieldType(@import("bytecode.zig").Instruction, "op"), pc: usize, head: usize, back: usize) bool {
    return switch (op) {
        .jump, .jump_if_false => |target| if (pc >= head and pc <= back) target < head else target > head and target <= back,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.target > head and arm.target <= back) break true;
        } else false,
        .try_result => |propagate| propagate.error_target > head and propagate.error_target <= back,
        else => false,
    };
}
