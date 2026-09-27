//! Successful scalar-append admission reused only inside a closed physical loop.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const cow = @import("cow_plan.zig");
const frame = @import("qbe_rc_frame.zig");
const edges = @import("qbe_rc_edges.zig");
/// One separately accounted word belongs to this loop/root, never an operand.
pub const Certificate = @import("rc_append_loop.zig").Certificate;
/// Optional proof refusal retains the complete per-operation runtime query.
pub const Error = frame.Error;

/// Run after physical COW refinement; metadata/cleanup hooks are part of proof.
pub fn finalize(comptime E: type, self: *E) Error!void {
    const state = frame.get(E, self) orelse return;
    state.plan.append_loops = &.{};
    if (state.readonly or state.contract.result == .borrowed) return;
    const code = self.function.scope.instructions;
    if (code.len > 4096) return;
    var found: std.ArrayList(Certificate) = .empty;
    var budget: usize = 262144;
    const plan = self.cow.?.plan;
    for (plan.loops.entries, 0..) |entries, head| for (entries) |check| {
        if (check.elements or plan.loops.back[head] == cow.none) continue;
        const proof: Certificate = .{ .head = head, .back = plan.loops.back[head], .root = check.local };
        if (proof.back < head or proof.back - head > 1024 or !@import("qbe_rc_nonheld_capture.zig").scalarList(E, self, proof.root)) continue;
        if (code.len > budget) break;
        budget -= code.len;
        if (!try @import("qbe_rc_fresh_root.zig").proven(E, self, proof.root, head)) continue;
        if (!try quiet(E, self, proof)) continue;
        try found.append(self.allocator, proof);
    };
    state.plan.append_loops = try found.toOwnedSlice(self.allocator);
}

/// Every external entry passes this reset after all hoisted uniqueness checks.
/// Ordinary backedges target the instruction label and preserve the flag.
pub fn entry(comptime E: type, self: *E, head: usize) Error!void {
    const state = frame.get(E, self) orelse return;
    for (state.plan.append_loops, 0..) |proof, index| if (proof.head == head)
        try self.print(" storew 0, %rcappend{d}\n", .{index});
}

/// Only the certified root's actual append may use its private admission word.
pub fn at(comptime E: type, self: *E) ?usize {
    const state = frame.get(E, self) orelse return null;
    const op = self.function.scope.instructions[self.pc].op;
    if (op != .buffer_operation or op.buffer_operation.kind != .append) return null;
    for (state.plan.append_loops, 0..) |proof, index| {
        if (self.pc >= proof.head and self.pc <= proof.back and @backingInt(op.buffer_operation.owner) == proof.root) return index;
    }
    return null;
}

fn scalar(comptime E: type, self: *E, ty: typed.Type) bool {
    if (!self.isScalar(ty)) return false;
    const value = self.cow.?.rc.?.catalog.get(ty) catch return false;
    return !value.counted and !value.unique_drop;
}

fn quiet(comptime E: type, self: *E, proof: Certificate) Error!bool {
    const code = self.function.scope.instructions;
    const state = self.cow.?;
    const plan = state.plan;
    var append = false;
    for (code, 0..) |instruction, pc| {
        if (!@import("rc_append_loop.zig").validEdge(instruction.op, pc, proof)) return false;
        if (pc < proof.head or pc > proof.back or self.states[pc] == null) continue;
        if (instruction.inline_origin != null) return false;
        if (pc != proof.head and plan.entry(pc).len != 0) return false;
        const site = plan.at(pc);
        if (site.unique.len != 0 or site.unique_field != null or site.capture or site.fill) return false;
        if (site.shares.len != 0 or site.read_captures.len != 0) return false;
        if (state.captures[pc].begin != cow.none or state.captures[pc].active != cow.none) return false;
        for (state.rc.?.plan.records.transfers) |transfer| if (transfer.intercepts(pc)) return false;
        for (state.rc.?.plan.locals.edges) |edge| {
            if (edge.from != pc) continue;
            for (edge.releases) |release| if (try edges.releasesAt(E, self, pc, @backingInt(release.storage))) return false;
        }
        for (self.states[pc].?) |ty| if (!scalar(E, self, ty)) return false;
        if (!allowed(E, self, instruction.op, proof.root)) return false;
        if (instruction.op == .buffer_operation and instruction.op.buffer_operation.kind == .append) append = true;
    }
    return append;
}

// A cached true answer proves same-root scalar .write's actual binding has
// flat.count==0 and the death queue is empty. Its native_retain_replace takes
// the no-allocation/no-drain memmove path. Before that answer, the flag is zero
// and any ordinary write cleanup cannot invalidate a cached success.
fn allowed(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), root: usize) bool {
    return switch (op) {
        .load_local => |id| scalar(E, self, self.function.scope.locals[@backingInt(id)].ty),
        .store_local => |id| scalar(E, self, self.function.scope.locals[@backingInt(id)].ty) and
            !self.byReference(@backingInt(id)) and !self.callerStorage(@backingInt(id)),
        .value_copy => |copy| scalar(E, self, copy.ty),
        .buffer_operation => |operation| @backingInt(operation.owner) == root and scalar(E, self, operation.output) and switch (operation.kind) {
            .length, .capacity, .read, .write, .append => true,
            else => false,
        },
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
        .assert_true,
        .pop,
        => true,
        .push_integer => |value| scalar(E, self, value.ty),
        .cast_integer, .neg_integer, .wrap_domain, .unwrap_domain, .acknowledge => |ty| scalar(E, self, ty),
        .binary_integer => |operation| scalar(E, self, operation.ty),
        .cmp_domain => |comparison| scalar(E, self, comparison.ty),
        .cmp_enum => |comparison| scalar(E, self, comparison.ty),
        else => false,
    };
}
