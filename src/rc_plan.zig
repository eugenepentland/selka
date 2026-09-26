//! Canonical local storage and guarded CFG releases (RC-OWNERSHIP-PLAN-1).
//! Operand and partial-construction ownership is added at lowering checkpoints;
//! this pass never releases a local across an unconsumed operand stack.
const std = @import("std");
const typed = @import("typed.zig");
const model = @import("rc_model.zig");
const shapes = @import("rc_shape.zig");
const input_model = @import("rc_input.zig");

/// The finalized facts accepted by the planner.
pub const Input = input_model.Input;
/// Invalid internal facts or allocation failure; never an optimization refusal.
pub const Error = @import("native_types.zig").Error || error{ InvalidState, AbiMismatch };
/// One physical slot, possibly named by several local aliases.
pub const Storage = struct {
    id: model.StorageId,
    ty: typed.Type,
    shape: shapes.Shape,
    initial: model.Ownership,
    /// A frame-owned slot's initialized-token bit; borrowed slots have none.
    guard: ?model.GuardId,
};
/// Drop only if this physical slot has committed an initialized owned value.
pub const Release = struct { storage: model.StorageId, guard: model.GuardId };
/// Cleanup after one real CFG edge, including its match-payload binding.
pub const Edge = struct { from: usize, to: usize, releases: []const Release };
/// The local part of a physical plan, independent of emission retries.
pub const Plan = struct {
    storage: []const Storage,
    entry: []const model.ValueState,
    edges: []const Edge,
    /// Unique resources stay in the existing drop order until final cleanup.
    cleanup: []const Release,
};

/// Build canonical entry obligations and early local releases from final facts.
pub fn build(a: std.mem.Allocator, input: Input) Error!Plan {
    try validate(input);
    var storage: std.ArrayList(Storage) = .empty;
    const entry = try a.alloc(model.ValueState, input.physical.locals.len);
    var cleanup: std.ArrayList(Release) = .empty;
    for (input.code.function.scope.locals, input.physical.locals, 0..) |local, binding, index| {
        const at = find(storage.items, binding.storage) orelse next: {
            const shape = try input.physical.catalog.get(local.ty);
            const initial = try initialOwnership(input, index, shape);
            const frame_slot = initial != .plain and initial != .inout and binding.anchor == null;
            const guard: ?model.GuardId = if (frame_slot) @fromBackingInt(@intCast(storage.items.len)) else null;
            try storage.append(a, .{ .id = binding.storage, .ty = local.ty, .shape = shape, .initial = initial, .guard = guard });
            if (guard) |bit| try cleanup.append(a, .{ .storage = binding.storage, .guard = bit });
            break :next storage.items.len - 1;
        };
        const slot = storage.items[at];
        if (slot.ty != local.ty) return error.InvalidState;
        if (binding.anchor) |anchor| if (slot.initial != .borrowed or !std.meta.eql(anchor, slot.initial.borrowed)) return error.InvalidState;
        entry[index] = .{ .value = @fromBackingInt(@intCast(index)), .ty = local.ty, .storage = slot.id, .shape = slot.shape, .ownership = slot.initial };
    }
    try validateAnchors(storage.items);
    std.mem.reverse(Release, cleanup.items);
    const rows = try a.alloc(bool, input.code.states.len * storage.items.len);
    @memset(rows, false);
    for (storage.items, 0..) |slot, index| rows[index] = slot.initial == .owned;
    var builder: EdgeBuilder = .{
        .a = a,
        .input = input,
        .storage = storage.items,
        .rows = rows,
        .scratch = try a.alloc(bool, storage.items.len),
    };
    while (builder.changed) {
        builder.changed = false;
        try builder.visit(false);
    }
    try builder.visit(true);
    return .{ .storage = try storage.toOwnedSlice(a), .entry = entry, .edges = try builder.edges.toOwnedSlice(a), .cleanup = try cleanup.toOwnedSlice(a) };
}

fn validate(input: Input) Error!void {
    const function = input.code.function;
    const count = function.scope.locals.len;
    const length = function.scope.instructions.len;
    if (input.physical.locals.len != count or input.code.states.len != length) return error.InvalidState;
    if (input.flow.ownership.roles.len != count or input.contracts.current.parameters.len != function.signature.parameter_count) return error.InvalidState;
    if (input.flow.live.live_in.len != length * input.flow.live.words or input.flow.live.live_out.len != length * input.flow.live.words) return error.InvalidState;
    if (input.flow.live.words != (count + 63) / 64) return error.InvalidState;
    if (input.mutation.places.sites.len != 0 and input.mutation.places.sites.len != length) return error.InvalidState;
    if (!std.mem.eql(u8, input.contracts.current.abi, input.policy.abi)) return error.AbiMismatch;
    for (input.contracts.functions) |contract| if (!std.mem.eql(u8, contract.abi, input.policy.abi)) return error.AbiMismatch;
}

fn initialOwnership(input: Input, index: usize, shape: shapes.Shape) Error!model.Ownership {
    if (!shape.counted and !shape.unique_drop) return .plain;
    if (index < input.contracts.current.parameters.len) return switch (input.contracts.current.parameters[index]) {
        .read, .mutable_payload => .{ .borrowed = .{ .parameter = @intCast(index) } },
        .caller_storage => .{ .inout = .{ .parameter = @intCast(index) } },
        .consume_on_entry => .{ .owned = .{ .token = @fromBackingInt(@intCast(index)) } },
        .consume_on_success => error.InvalidState,
    };
    if (input.physical.locals[index].anchor) |anchor| return .{ .borrowed = anchor };
    return .empty;
}

fn find(storage: []const Storage, id: model.StorageId) ?usize {
    for (storage, 0..) |slot, index| if (slot.id == id) return index;
    return null;
}

fn validateAnchors(storage: []const Storage) Error!void {
    for (storage) |slot| {
        var current = slot;
        var steps: usize = 0;
        while (current.initial == .borrowed and current.initial.borrowed == .storage) : (steps += 1) {
            if (steps >= storage.len) return error.InvalidState;
            const parent = find(storage, current.initial.borrowed.storage) orelse return error.InvalidState;
            current = storage[parent];
        }
    }
}

const EdgeBuilder = struct {
    a: std.mem.Allocator,
    input: Input,
    storage: []const Storage,
    edges: std.ArrayList(Edge) = .empty,
    rows: []bool,
    scratch: []bool,
    changed: bool = true,

    fn visit(self: *EdgeBuilder, emit: bool) Error!void {
        for (self.input.code.function.scope.instructions, 0..) |instruction, pc| {
            if (self.input.code.states[pc] == null) continue;
            switch (instruction.op) {
                .ret => {},
                .jump => |target| try self.add(pc, target, null, emit),
                .jump_if_false => |target| {
                    try self.add(pc, target, null, emit);
                    try self.add(pc, pc + 1, null, emit);
                },
                .try_result => |propagate| {
                    try self.add(pc, propagate.error_target, null, emit);
                    try self.add(pc, pc + 1, null, emit);
                },
                .switch_variant => |dispatch| for (dispatch.arms) |arm| try self.add(pc, arm.target, arm.slot, emit),
                else => try self.add(pc, pc + 1, null, emit),
            }
        }
    }

    fn add(self: *EdgeBuilder, from: usize, to: usize, bound: ?typed.LocalId, emit: bool) Error!void {
        if (to >= self.input.code.states.len) return error.InvalidState;
        const stack = self.input.code.states[to] orelse return error.InvalidState;
        const width = self.storage.len;
        @memcpy(self.scratch, self.rows[from * width ..][0..width]);
        switch (self.input.code.function.scope.instructions[from].op) {
            .store_local => |local| try self.set(local, true),
            .drop_local, .move_local => |local| try self.set(local, false),
            else => {},
        }
        if (bound) |local| try self.set(local, true);
        var releases: std.ArrayList(Release) = .empty;
        for (self.storage, self.scratch) |slot, *initialized| {
            const guard = slot.guard orelse continue;
            // Pending operands may still borrow a dead local; retain it until
            // the consuming operation's successors have an empty stack.
            if (!initialized.* or stack.len != 0) continue;
            if (slot.shape.unique_drop or self.needed(to, slot.id)) continue;
            initialized.* = false;
            if (emit) try releases.append(self.a, .{ .storage = slot.id, .guard = guard });
        }
        if (emit) {
            if (releases.items.len != 0) try self.edges.append(self.a, .{ .from = from, .to = to, .releases = try releases.toOwnedSlice(self.a) });
        } else for (self.rows[to * width ..][0..width], self.scratch) |*target, incoming| {
            if (incoming and !target.*) {
                target.* = true;
                self.changed = true;
            }
        }
    }

    fn set(self: *EdgeBuilder, local: typed.LocalId, initialized: bool) Error!void {
        const index = @backingInt(local);
        if (index >= self.input.physical.locals.len) return error.InvalidState;
        const slot = find(self.storage, self.input.physical.locals[index].storage) orelse return error.InvalidState;
        if (self.storage[slot].guard != null) self.scratch[slot] = initialized;
    }

    fn needed(self: *const EdgeBuilder, pc: usize, id: model.StorageId) bool {
        for (self.input.physical.locals, 0..) |binding, index| {
            if (!self.input.flow.live.before(pc, index)) continue;
            if (binding.storage == id or self.anchored(binding.storage, id, 0)) return true;
        }
        return false;
    }

    fn anchored(self: *const EdgeBuilder, source: model.StorageId, target: model.StorageId, depth: usize) bool {
        if (depth > self.storage.len) return true;
        const index = find(self.storage, source) orelse return true;
        const ownership = self.storage[index].initial;
        if (ownership != .borrowed) return false;
        if (ownership.borrowed != .storage) return false;
        const parent = ownership.borrowed.storage;
        return parent == target or self.anchored(parent, target, depth + 1);
    }
};
