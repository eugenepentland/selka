//! Scalar-range specialization of a certified growing append loop. Runtime
//! capacity, readiness, allocation and publication keep their ordinary order.
const std = @import("std");
const facts = @import("qbe_loop_facts.zig");
const frame = @import("qbe_rc_frame.zig");
const fresh = @import("qbe_rc_fresh_root.zig");

/// Only the existing quiet scalar append certificate can admit this exception.
/// An empty, untouched root cannot satisfy the old whole-loop room guard, so
/// its two copies instead differ only in proven scalar checks. Every guard
/// dependency is a private integer word; no speculative read can call or trap.
pub fn certify(comptime E: type, self: *E, loop: *const facts.Loop) bool {
    const state = frame.get(E, self) orelse return false;
    const code = self.function.scope.instructions;
    if (code.len > 4096 or loop.back < loop.head or loop.back >= code.len) return false;
    if (loop.back - loop.head > facts.max_body or loop.actions.len != loop.back - loop.head + 1) return false;
    const nodes = self.loop_plan.nodes;
    if (nodes.len > 4096) return false;
    const receiver = appendReceiver(loop) orelse return false;
    if (receiver >= nodes.len or nodes[receiver] != .leaf or nodes[receiver].leaf.kind != .local) return false;
    const root = nodes[receiver].leaf.slot;
    const certified = for (state.plan.append_loops) |proof| {
        if (proof.head == loop.head and proof.back == loop.back and proof.root == root) break true;
    } else false;
    if (!certified or !fresh.emptyBefore(E, self, root, loop.head)) return false;
    // The older append certificate admits scalar loads through references.
    // Allocation can drain callbacks, so this specialization additionally
    // refuses those words even when they occur only in a retained check.
    for (code[loop.head .. loop.back + 1]) |instruction| switch (instruction.op) {
        .load_local, .store_local => |slot| if (self.byReference(@backingInt(slot)) or self.callerStorage(@backingInt(slot))) return false,
        .buffer_operation => |operation| if (operation.kind != .append or @backingInt(operation.owner) != root) return false,
        else => {},
    };
    return safeGuards(E, self, loop, receiver);
}

fn appendReceiver(loop: *const facts.Loop) ?facts.NodeId {
    var result: ?facts.NodeId = null;
    for (loop.actions) |action| {
        if (action.value != null) return null;
        if (action.effect == .presized) {
            if (result != null) return null;
            result = action.receiver orelse return null;
        } else if (action.receiver != null) return null;
    }
    return result;
}

fn safeGuards(comptime E: type, self: *E, loop: *const facts.Loop, receiver: facts.NodeId) bool {
    var room = false;
    var budget: usize = 262144;
    for (loop.guard) |step| {
        const values: [2]?facts.NodeId = switch (step) {
            .bounded => |id| .{ id, null },
            .at_least => |bound| .{ bound.value, null },
            .order => |order| .{ order.value, order.limit },
            .spans => |span| .{ span.entry, span.bound },
            .room => |spare| blk: {
                if (room or spare.list != receiver) return false;
                room = true;
                break :blk .{ spare.entry, spare.bound };
            },
        };
        for (values) |id| if (id) |node| {
            if (!safeNode(E, self, node, 0, &budget)) return false;
        };
    }
    return room;
}

fn safeNode(comptime E: type, self: *E, id: facts.NodeId, depth: usize, budget: *usize) bool {
    const nodes = self.loop_plan.nodes;
    if (id >= nodes.len or depth > 32 or budget.* == 0) return false;
    budget.* -= 1;
    return switch (nodes[id]) {
        .constant => true,
        .leaf => |leaf| blk: {
            if (leaf.kind != .local and leaf.kind != .entry) break :blk false;
            break :blk privateInteger(E, self, leaf.slot, budget);
        },
        .operation => |operation| operation.operator != .quotient and operation.left < id and operation.right < id and
            safeNode(E, self, operation.left, depth + 1, budget) and safeNode(E, self, operation.right, depth + 1, budget),
        else => false,
    };
}

fn privateInteger(comptime E: type, self: *E, slot: usize, budget: *usize) bool {
    if (slot >= self.function.scope.locals.len or self.function.scope.locals[slot].ty != .i64) return false;
    if (self.byReference(slot) or self.callerStorage(slot)) return false;
    const code = self.function.scope.instructions;
    if (code.len > budget.*) return false;
    budget.* -= code.len;
    for (code) |instruction| switch (instruction.op) {
        // A scalar's ordinary slot can also escape through an explicit ref,
        // even when the ABI did not classify it as caller-backed storage.
        .ref_local, .move_local, .drop_local => |local| if (@backingInt(local) == slot) return false,
        else => {},
    };
    return true;
}

/// This certificate permits exactly the original append's allocating callee,
/// its nonmutating query and cold traps. The general copy-allocation veto and
/// operand-isolation veto stay unchanged for every other loop and call.
pub fn ordinaryCopy(text: []const u8) bool {
    if (text.len > 1024 * 1024 or std.mem.indexOf(u8, text, "call %") != null) return false;
    var appends: usize = 0;
    var rest = text;
    while (std.mem.indexOf(u8, rest, "call $")) |at| {
        rest = rest[at + "call $".len ..];
        const end = std.mem.indexOfAny(u8, rest, "( \t\n") orelse return false;
        const name = rest[0..end];
        if (std.mem.eql(u8, name, "myl_rc_list_append")) {
            appends += 1;
        } else if (!readyCall(name) and !std.mem.startsWith(u8, name, "myl_qbe_fail_")) return false;
        rest = rest[end..];
    }
    return appends == 1;
}

fn readyCall(name: []const u8) bool {
    return std.mem.eql(u8, name, "myl_rc_list_plain_ready") or std.mem.eql(u8, name, "myl_rc_list_plain_ready_hot");
}

const GuardFixture = struct {
    loop_plan: struct { nodes: []const facts.Node },
    function: struct { scope: struct {
        locals: []const struct { ty: @import("typed.zig").Type },
        instructions: []const @import("bytecode.zig").Instruction = &.{},
    } },
    reference: bool = false,
    caller: bool = false,

    /// Model an ABI reference in the speculative dependency refusal test.
    pub fn byReference(self: *GuardFixture, _: usize) bool {
        return self.reference;
    }
    /// Model caller-backed mutable storage in the dependency refusal test.
    pub fn callerStorage(self: *GuardFixture, _: usize) bool {
        return self.caller;
    }
};

// spec-case: RC-APPEND-RANGE-1
test "append range guard dependencies refuse aliases collection reads unsafe division cycles and exhausted work" {
    const t = std.testing;
    var nodes = [_]facts.Node{
        .{ .constant = 13 },
        .{ .leaf = .{ .kind = .local, .slot = 0 } },
        .{ .operation = .{ .operator = .mul, .left = 0, .right = 1 } },
    };
    var emitter: GuardFixture = .{ .loop_plan = .{ .nodes = &nodes }, .function = .{ .scope = .{ .locals = &.{.{ .ty = .i64 }} } } };
    var budget: usize = 262144;
    try t.expect(safeNode(GuardFixture, &emitter, 2, 0, &budget));
    emitter.reference = true;
    try t.expect(!safeNode(GuardFixture, &emitter, 2, 0, &budget));
    emitter.reference = false;
    emitter.caller = true;
    try t.expect(!safeNode(GuardFixture, &emitter, 2, 0, &budget));
    emitter.caller = false;
    emitter.function.scope.instructions = &.{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .ref_local = @fromBackingInt(@intCast(0)) } }};
    try t.expect(!safeNode(GuardFixture, &emitter, 2, 0, &budget));
    emitter.function.scope.instructions = &.{};
    for ([_]facts.Node{
        .unknown,
        .{ .length = 0 },
        .{ .element = .{ .receiver = 0, .index = 0, .collection = .i64 } },
        .{ .negative = 0 },
        .{ .leaf = .{ .kind = .carried, .slot = 0 } },
        .{ .leaf = .{ .kind = .local, .slot = 1 } },
        .{ .operation = .{ .operator = .quotient, .left = 0, .right = 1 } },
        .{ .operation = .{ .operator = .mul, .left = 2, .right = 1 } },
    }) |unsafe| {
        nodes[2] = unsafe;
        try t.expect(!safeNode(GuardFixture, &emitter, 2, 0, &budget));
    }
    nodes[2] = .{ .constant = 0 };
    try t.expect(!safeNode(GuardFixture, &emitter, 3, 0, &budget));
    try t.expect(!safeNode(GuardFixture, &emitter, 2, 33, &budget));
    budget = 0;
    try t.expect(!safeNode(GuardFixture, &emitter, 2, 0, &budget));
}
