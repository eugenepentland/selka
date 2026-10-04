//! A checked scalar-list read lends its integer index through one exact update.
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const runtime = @import("runtime_mode.zig");
const Op = @FieldType(bytecode.Instruction, "op");
const max_code = 4096;
const max_interval = 256;

/// The frontend's private index, exact normalizer and final scalar access.
pub const Access = struct { start: usize, index: usize, owner: usize, at: usize, write: bool };
/// Only integer locals survive a detach: no interior storage address does.
pub const Proof = struct { read: Access, write: Access, root: usize, source: usize, value: usize };

/// RC-INDEX-UPDATE-1: skip only a later impossible negative correction. The
/// first read and its complete fallback stay. Retained accesses keep their
/// result protocols; the skipped correction has no physical ownership work.
pub fn branch(comptime E: type, self: *E) frame.Error!bool {
    if (!eligible(E, self) or self.pc < 3) return false;
    const next = normalizer(self.function.scope.instructions, self.pc - 3) orelse return false;
    const exact = (if (next.write) try update(E, self, next) else try forwarded(E, self, next)) orelse return false;
    try self.print(" # RC-INDEX-UPDATE-1 index {d} checked {d} pc {d}\n", .{ next.index, exact.read.index, self.pc });
    try self.print(" storel %v{d}, %l{d}\n", .{ try self.load("l", exact.read.index), next.index });
    try self.print(" jmp @{s}{d}\n", .{ self.labelPrefix(next.start + 9), next.start + 9 });
    return true;
}

/// An already checked normalized integer is in bounds after scalar COW.
pub fn checkedWrite(comptime E: type, self: *E) frame.Error!bool {
    if (!eligible(E, self) or self.pc < 11) return false;
    const access = normalizer(self.function.scope.instructions, self.pc - 11) orelse return false;
    if (!access.write or access.at != self.pc) return false;
    const proof = try update(E, self, access);
    return proof != null;
}

/// The exact i64 bits just stored, after the successful original write.
pub fn value(comptime E: type, self: *E) frame.Error!?usize {
    if (!eligible(E, self) or self.pc < 10) return null;
    const access = normalizer(self.function.scope.instructions, self.pc - 10) orelse return null;
    if (access.write or access.at != self.pc) return null;
    const proof = try forwarded(E, self, access) orelse return null;
    try self.print(" # RC-INDEX-UPDATE-1 value {d} write {d} pc {d}\n", .{ proof.value, proof.write.at, self.pc });
    const result = try self.load("l", proof.value);
    return result;
}

/// A forwarded read needs no independent positive-index fast read.
pub fn forwardRead(comptime E: type, self: *E, start: usize) frame.Error!bool {
    if (!eligible(E, self)) return false;
    const access = normalizer(self.function.scope.instructions, start) orelse return false;
    if (access.write) return false;
    const proof = try forwarded(E, self, access);
    return proof != null;
}

fn eligible(comptime E: type, self: *E) bool {
    if (!runtime.enabled() or runtime.counting() or self.arenas) return false;
    if (!self.checks or self.step_checks or self.frame_checks) return false;
    if (self.version != null or self.original != null or self.fused != null) return false;
    const state = frame.get(E, self) orelse return false;
    if (state.readonly or state.contract.result == .borrowed) return false;
    return self.function.scope.instructions.len <= max_code;
}

fn update(comptime E: type, self: *E, write: Access) frame.Error!?Proof {
    const code = self.function.scope.instructions;
    if (!write.write or write.start < 4) return null;
    if (!list(E, self, write.owner)) return null;
    const root = captured(E, self, write.owner, write.start - 3) orelse return null;
    const source = input(code, write) orelse return null;
    const rhs = local(code[write.at - 1].op) orelse return null;
    if (!privateInteger(E, self, source) or !privateInteger(E, self, rhs)) return null;
    if (!@import("qbe_rc_inert_receiver.zig").emptyLocal(E, self, write.owner)) return null;
    const begin = write.start -| max_interval;
    var pc = write.start;
    while (pc > begin) {
        pc -= 1;
        const read = normalizer(code, pc) orelse continue;
        if (read.write or read.at >= write.start or !list(E, self, read.owner)) continue;
        if (input(code, read) != source or read.start < 4) continue;
        if (captured(E, self, read.owner, read.start - 3) != root) continue;
        const proof: Proof = .{ .read = read, .write = write, .root = root, .source = source, .value = rhs };
        if (!indexPrivate(E, self, read) or !indexPrivate(E, self, write)) return null;
        if (!try closed(E, self, proof, null)) return null;
        return proof;
    }
    return null;
}

fn forwarded(comptime E: type, self: *E, read: Access) frame.Error!?Proof {
    const code = self.function.scope.instructions;
    if (read.write or read.start < 4 or !list(E, self, read.owner)) return null;
    const root = followingCaptured(E, self, read.owner, read.start - 3) orelse return null;
    const source = input(code, read) orelse return null;
    const begin = read.start -| max_interval;
    var pc = read.start;
    while (pc > begin) {
        pc -= 1;
        const write = normalizer(code, pc) orelse continue;
        if (!write.write or write.at >= read.start) continue;
        const proof = try update(E, self, write) orelse return null;
        if (proof.root != root or proof.source != source) return null;
        if (!indexPrivate(E, self, read) or !try closed(E, self, proof, read)) return null;
        return proof;
    }
    return null;
}

/// Exact canonical signed normalization, with one private RHS load for writes.
pub fn normalizer(code: []const bytecode.Instruction, start: usize) ?Access {
    if (start + 11 >= code.len) return null;
    const index = local(code[start].op) orelse return null;
    if (code[start + 1].op != .push_i64 or code[start + 1].op.push_i64 != 0) return null;
    if (code[start + 2].op != .cmp_i64 or code[start + 2].op.cmp_i64 != .lt) return null;
    if (code[start + 3].op != .jump_if_false or code[start + 3].op.jump_if_false != start + 9) return null;
    if (code[start + 4].op != .buffer_operation) return null;
    const length = code[start + 4].op.buffer_operation;
    if (length.kind != .length or length.output != .u64) return null;
    if (code[start + 5].op != .cast_integer or code[start + 5].op.cast_integer != .i64) return null;
    if (local(code[start + 6].op) != index or code[start + 7].op != .add_i64_checked) return null;
    if (code[start + 8].op != .store_local or @backingInt(code[start + 8].op.store_local) != index) return null;
    if (local(code[start + 9].op) != index) return null;
    var at = start + 10;
    const write = code[at].op == .load_local;
    if (write) at += 1;
    if (code[at].op != .buffer_operation) return null;
    const access = code[at].op.buffer_operation;
    if (access.owner != length.owner or access.output != (if (write) typed.Type.unit else .i64)) return null;
    const kind: @TypeOf(access.kind) = if (write) .write else .read;
    if (access.kind != kind) return null;
    return .{ .start = start, .index = index, .owner = @backingInt(length.owner), .at = at, .write = write };
}

fn input(code: []const bytecode.Instruction, access: Access) ?usize {
    if (access.start < 2 or code[access.start - 1].op != .store_local) return null;
    if (@backingInt(code[access.start - 1].op.store_local) != access.index) return null;
    return local(code[access.start - 2].op);
}

fn local(op: Op) ?usize {
    return if (op == .load_local) @backingInt(op.load_local) else null;
}

fn list(comptime E: type, self: *E, owner: usize) bool {
    const ty = self.function.scope.locals[owner].ty;
    if (!ty.isAggregate()) return false;
    const record = self.program.records[ty.recordIndex()];
    return record.managed and record.isCollection() and !record.collection.box and
        record.collection.kind == .list and record.shape.buffer == .i64;
}

fn captured(comptime E: type, self: *E, owner: usize, at: usize) ?usize {
    if (!@import("qbe_rc_nonheld_capture.zig").ordinaryInput(E, self, owner, at)) return null;
    return local(self.function.scope.instructions[at - 1].op);
}

// Only a following read may have a plain prefix. Unlike the first/write
// captures, its existing token protocol is retained in full, even if it holds
// the receiver. The closed interval separately audits entries and releases.
fn followingCaptured(comptime E: type, self: *E, owner: usize, at: usize) ?usize {
    if (at == 0) return null;
    const before = self.states[at - 1] orelse return null;
    const after = self.states[at] orelse return null;
    if (after.len != before.len + 1 or after[before.len] != self.function.scope.locals[owner].ty) return null;
    for (before, after[0..before.len]) |left, right| {
        if (left != right or !scalar(left)) return null;
    }
    return @import("qbe_rc_nonheld_capture.zig").ordinaryPublication(E, self, owner, at);
}

fn privateInteger(comptime E: type, self: *E, index: usize) bool {
    if (self.function.scope.locals[index].ty != .i64) return false;
    if (self.byReference(index) or self.callerStorage(index) or self.moves.aliased(index)) return false;
    for (self.function.scope.instructions) |instruction| switch (instruction.op) {
        .ref_local, .move_local, .drop_local => |id| if (@backingInt(id) == index) return false,
        .switch_variant => |dispatch| for (dispatch.arms) |arm| {
            if (arm.slot) |id| if (@backingInt(id) == index) return false;
        },
        else => {},
    };
    return true;
}

fn indexPrivate(comptime E: type, self: *E, access: Access) bool {
    if (!privateInteger(E, self, access.index) or !self.function.scope.locals[access.index].usage.temporary) return false;
    for (self.function.scope.instructions, 0..) |instruction, pc| switch (instruction.op) {
        .load_local => |id| if (@backingInt(id) == access.index and pc != access.start and pc != access.start + 6 and pc != access.start + 9) return false,
        .store_local => |id| if (@backingInt(id) == access.index and pc != access.start - 1 and pc != access.start + 8) return false,
        else => {},
    };
    return true;
}

fn closed(comptime E: type, self: *E, proof: Proof, following: ?Access) frame.Error!bool {
    const code = self.function.scope.instructions;
    const end = if (following) |access| access.at else proof.write.at;
    const start = proof.read.start - 4;
    if (end < start or end - start > max_interval) return false;
    if (!entries(code, start, end, proof, following)) return false;
    for (start..end + 1) |pc| {
        if (self.states[pc] == null or code[pc].inline_origin != null) return false;
        if (!plainStack(E, self, pc, proof, following)) return false;
        if (!allowed(E, self, pc, proof, following)) return false;
        if (!try quiet(E, self, pc, proof)) return false;
    }
    return true;
}

fn plainStack(comptime E: type, self: *E, pc: usize, proof: Proof, following: ?Access) bool {
    const stack = self.states[pc].?;
    for (stack, 0..) |ty, height| {
        if (scalar(ty)) continue;
        if (height + 1 != stack.len or ty != self.function.scope.locals[proof.root].ty) return false;
        if (pc == proof.read.start - 3 or pc == proof.write.start - 3) continue;
        if (following) |access| if (pc == access.start - 3) continue;
        return false;
    }
    return true;
}

fn allowed(comptime E: type, self: *E, pc: usize, proof: Proof, following: ?Access) bool {
    const op = self.function.scope.instructions[pc].op;
    return switch (op) {
        .load_local, .store_local => |id| blk: {
            const index = @backingInt(id);
            if (self.byReference(index) or self.callerStorage(index)) break :blk false;
            if (op == .store_local and (index == proof.source or index == proof.root)) break :blk false;
            if (following != null and pc > proof.write.at and op == .store_local and index == proof.value) break :blk false;
            if (scalar(self.function.scope.locals[index].ty)) break :blk true;
            if (pc == proof.read.start - 4) break :blk local(op) == proof.root;
            if (pc == proof.read.start - 3) break :blk op == .store_local and index == proof.read.owner;
            if (pc == proof.write.start - 4) break :blk local(op) == proof.root;
            if (pc == proof.write.start - 3) break :blk op == .store_local and index == proof.write.owner;
            if (following) |access| {
                if (pc == access.start - 4) break :blk local(op) == proof.root;
                if (pc == access.start - 3) break :blk op == .store_local and index == access.owner;
            }
            break :blk false;
        },
        .buffer_operation => buffer(pc, op, proof.read) or buffer(pc, op, proof.write) or
            (if (following) |access| buffer(pc, op, access) else false),
        .jump_if_false => normalBranch(pc, proof.read) or normalBranch(pc, proof.write) or
            (if (following) |access| normalBranch(pc, access) else false),
        .push_i64, .push_bool, .push_unit, .cmp_i64, .cmp_bool, .not_bool, .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked, .pop => true,
        .binary_integer => |operation| operation.ty == .i64 and
            (operation.op == .floor_div or operation.op == .floor_rem),
        .cast_integer => |ty| ty == .i64,
        else => false,
    };
}

fn scalar(ty: typed.Type) bool {
    return ty == .i64 or ty == .u64 or ty == .bool or ty == .unit;
}

fn buffer(pc: usize, op: Op, access: Access) bool {
    if (pc != access.start + 4 and pc != access.at) return false;
    return op.buffer_operation.owner == @as(typed.LocalId, @fromBackingInt(access.owner));
}

fn normalBranch(pc: usize, access: Access) bool {
    return pc == access.start + 3;
}

/// Every entry is audited, including unreachable Result and switch edges.
pub fn entries(code: []const bytecode.Instruction, start: usize, end: usize, proof: Proof, following: ?Access) bool {
    for (code, 0..) |instruction, pc| {
        var buffer_: [2]usize = undefined;
        for (@import("ownership_sources.zig").branchTargets(instruction.op, &buffer_)) |target| {
            if (!edge(pc, target, start, end, proof, following)) return false;
        }
        if (instruction.op == .switch_variant) for (instruction.op.switch_variant.arms) |arm| {
            if (!edge(pc, arm.target, start, end, proof, following)) return false;
        };
    }
    return true;
}

fn edge(pc: usize, target: usize, start: usize, end: usize, proof: Proof, following: ?Access) bool {
    if (target < start or target > end) return true;
    if (target == start and (pc < start or pc > end)) return true;
    if (canonicalEdge(pc, target, proof.read) or canonicalEdge(pc, target, proof.write)) return true;
    return if (following) |access| canonicalEdge(pc, target, access) else false;
}

fn canonicalEdge(pc: usize, target: usize, access: Access) bool {
    return pc == access.start + 3 and target == access.start + 9;
}

fn quiet(comptime E: type, self: *E, pc: usize, proof: Proof) frame.Error!bool {
    const state = self.cow.?;
    const site = state.plan.at(pc);
    if (site.capture or site.fill or site.unique_field != null) return false;
    if (site.shares.len != 0 or site.read_captures.len != 0) return false;
    if (state.plan.entry(pc).len != 0) return false;
    if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
    for (site.unique) |unique| {
        if (pc != proof.write.start - 4 or unique.local != proof.root or unique.alias != cow.none) return false;
    }
    const records = state.rc.?.plan.records;
    for (records.transfers) |transfer| if (transfer.intercepts(pc)) return false;
    for (records.writes) |write| if (pc >= write.start and pc < write.start + 8) return false;
    for (records.reads) |read| if (pc >= read.start and pc <= read.end) return false;
    for (state.rc.?.plan.locals.edges) |edge_| {
        if (edge_.from != pc) continue;
        for (edge_.releases) |release| {
            if (try @import("qbe_rc_edges.zig").releasesAt(E, self, pc, @backingInt(release.storage))) return false;
        }
    }
    return true;
}
