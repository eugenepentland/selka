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
            const classic = try proven(E, self, site, stores, false);
            const extended = !classic and try @import("qbe_rc_fresh_root.zig").proven(E, self, site.local, site.hoisted);
            if (classic or (extended and try proven(E, self, site, stores, true))) {
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

/// A fast loop may cache storage only inside a physically proved interval.
/// The emitter still rejects checks left inside it and any allocating helper
/// that the fast copy actually emits. The ordinary loop remains the fallback.
pub fn permitsVersion(comptime E: type, self: *E, head: usize, back: usize) bool {
    if (frame.get(E, self) == null) return false;
    const plan = self.cow.?.plan;
    for (plan.loops.entries, 0..) |entries, outer| {
        if (head < outer or back > plan.loops.back[outer]) continue;
        // Late dictionary entries cover uniqueness only. They never authorize
        // cached-storage fast loops, even if this query is reused after veto.
        for (entries) |entry| if (listElement(E, self, self.function.scope.locals[entry.local].ty) != null) return true;
    }
    return false;
}

/// What one loop proof admits: its root, the receiver stores certified
/// borrowed, whether the fresh-root extension applies, and per instruction the
/// operand height of a pending octet-append source (`none` elsewhere).
const Proof = struct { root: usize, stores: []const bool, extended: bool, sources: []const u32 = &.{} };

fn proven(comptime E: type, self: *E, site: ownership.Cow, stores: []const bool, extended: bool) Error!bool {
    const code = self.function.scope.instructions;
    const head = site.hoisted;
    const back = self.cow.?.plan.loops.back[head];
    if (code.len > 4096 or back == cow.none or back < head or back - head > 1024) return false;
    if (site.pc < head or site.pc > back) return false;
    const root = self.function.scope.locals[site.local];
    if (root.usage.temporary and !extended) return false;
    if (self.byReference(site.local) or self.callerStorage(site.local)) return false;
    if (!self.live.?.before(head, site.local) or self.cow.?.plan.place(site.local) != null) return false;
    var proof: Proof = .{ .root = site.local, .stores = stores, .extended = extended };
    if (octetBuffer(E, self, root.ty)) |octet| {
        if (site.elements or !plain(E, self, octet)) return false;
        proof.sources = try octetSources(E, self, site.local, head, back) orelse return false;
    } else {
        const element = listElement(E, self, root.ty) orelse return false;
        if (site.elements) {
            const leaf = listElement(E, self, element) orelse return false;
            if (!plain(E, self, leaf)) return false;
        } else if (!plain(E, self, element) and listElement(E, self, element) == null) return false;
    }
    for (code, 0..) |instruction, pc| {
        if (invalidEdge(instruction.op, pc, head, back)) return false;
        if (pc < head or pc > back or self.states[pc] == null) continue;
        if (!allowed(E, self, pc, proof)) return false;
    }
    return true;
}

/// RC-BUFFER-HOIST-1: the octet element of the mutable `byte_buffer`, whose
/// in-place appends only ever write octets into the receiver's own storage.
fn octetBuffer(comptime E: type, self: *E, ty: typed.Type) ?typed.Type {
    if (!ty.isAggregate()) return null;
    const record = self.program.records[ty.recordIndex()];
    if (!record.managed or !record.isCollection()) return null;
    if (record.collection.kind != .bytes or !std.mem.eql(u8, record.name, @import("nominal_templates.zig").byte_buffer_name)) return null;
    return record.shape.buffer;
}

/// Per instruction of the loop, the operand height holding the source an
/// append of the octet-buffer root reads (`append_range`'s data, or
/// `append_utf8`'s text), or `none`. Each such source must be exactly the
/// value one `load_local` of another local pushed, carried unconsumed by the
/// ownership analysis's operand flow to the append with no branch entering in
/// between: it is only ever a borrowed read of a local the loop cannot store.
/// Null when an append's source is anything else, which keeps its checks.
fn octetSources(comptime E: type, self: *E, root: usize, head: usize, back: usize) Error!?[]u32 {
    const code = self.function.scope.instructions;
    const flow = (self.ownership orelse return null).operands;
    const sources = try self.allocator.alloc(u32, code.len);
    @memset(sources, cow.none);
    for (head..back + 1) |pc| {
        const operation = switch (code[pc].op) {
            .buffer_operation => |operation| operation,
            else => continue,
        };
        if (@backingInt(operation.owner) != root) continue;
        if (operation.kind != .buffer_append_range and operation.kind != .buffer_append_utf8) continue;
        const stack = flow[pc] orelse return null;
        if (stack.len < operation.kind.arity()) return null;
        const height = stack.len - operation.kind.arity();
        const source = stack[height];
        if (source.origin != .local or source.part != .whole or source.local == root) return null;
        if (source.read == cow.none or source.read < head or source.read >= pc) return null;
        switch (code[source.read].op) {
            .load_local => |slot| if (@backingInt(slot) != source.local) return null,
            else => return null,
        }
        for (source.read + 1..pc + 1) |at| {
            if (self.isBranchTarget(at)) return null;
            const carried = flow[at] orelse return null;
            if (carried.len <= height or !carried[height].eql(source)) return null;
            sources[at] = @intCast(height);
        }
    }
    return sources;
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
        const role = self.cow.?.rc.?.plan.locals.entry[local].ownership;
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

fn allowed(comptime E: type, self: *E, pc: usize, proof: Proof) bool {
    const code = self.function.scope.instructions;
    const op = code[pc].op;
    const inputs = self.states[pc].?;
    for (inputs, 0..) |ty, height| if (!plain(E, self, ty)) {
        if (pendingSource(proof, pc) == height) continue;
        if (inputs.len != 1 or !borrowedStore(proof.stores, pc)) return false;
    };
    return switch (op) {
        .load_local => |id| plain(E, self, self.function.scope.locals[@backingInt(id)].ty) or borrowedStore(proof.stores, pc + 1) or
            pendingSource(proof, pc + 1) == inputs.len,
        .store_local => |id| @backingInt(id) != proof.root and (plain(E, self, self.function.scope.locals[@backingInt(id)].ty) or borrowedStore(proof.stores, pc)),
        .value_copy => |copy| plain(E, self, copy.ty),
        .buffer_operation => |operation| operationAllowed(E, self, pc, operation, proof),
        .make_record => |record| proof.extended and plain(E, self, record.ty) and
            !self.program.records[record.ty.recordIndex()].isManagedRecord(),
        .ret => proof.extended and plain(E, self, self.function.signature.return_type),
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

fn operationAllowed(comptime E: type, self: *E, pc: usize, operation: anytype, proof: Proof) bool {
    const owner = @backingInt(operation.owner);
    if (owner == proof.root and octetBuffer(E, self, self.function.scope.locals[owner].ty) != null) {
        if (!plain(E, self, operation.output)) return false;
        return switch (operation.kind) {
            .buffer_append_byte, .buffer_append_int, .buffer_append_float, .buffer_reserve => true,
            .buffer_append_range, .buffer_append_utf8 => pendingSource(proof, pc) == self.states[pc].?.len - operation.kind.arity(),
            else => false,
        };
    }
    const element = listElement(E, self, self.function.scope.locals[owner].ty) orelse return false;
    return switch (operation.kind) {
        .length, .capacity => plain(E, self, operation.output),
        .read => plain(E, self, operation.output) or borrowedStore(proof.stores, pc + 1),
        .write => plain(E, self, element) and plain(E, self, operation.output),
        .append => proof.extended and plain(E, self, element) and plain(E, self, operation.output),
        else => false,
    };
}

/// The operand height of the certified octet-append source pending before
/// instruction `pc`, or `none`.
fn pendingSource(proof: Proof, pc: usize) usize {
    return if (pc < proof.sources.len and proof.sources[pc] != cow.none) proof.sources[pc] else cow.none;
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
