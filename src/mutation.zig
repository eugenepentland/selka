//! Shared classification for managed write operations.
//!
//! Concrete checking, abstract generic checking and IR validation all use this
//! one vocabulary so a write form cannot be classified differently by each
//! phase. The classifier is deliberately conservative: a managed receiver write
//! is recorded even when a later analysis might prove the receiver fresh.

const std = @import("std");
const typed = @import("typed.zig");
const buffer_operations = @import("buffer_operations.zig");
const source = @import("source.zig");
const model = @import("bytecode_model.zig");

/// Error set for mutation-footprint helpers.
pub const MutationError = error{OutOfMemory};

/// One managed operation category independent of its surface spelling.
pub const Operation = enum {
    /// Reads managed storage without changing it.
    read,
    /// Allocates a fresh outer container but preserves descendant origins.
    shallow_copy,
    /// Writes a receiver slot, element, field or buffer in place.
    receiver_write,
    /// Writes private local initialization; distinct from externally visible writes.
    local_initialization,
};

/// Classification result for one resolved operation.
pub const Classification = struct {
    operation: Operation,
    /// Whether the operation changes managed state reachable from the receiver.
    writes_receiver: bool,
    /// Whether the operation creates fresh outer storage while sharing descendants.
    severs_outer: bool,
};

/// A located write summary before parameter-origin resolution.
pub const Witness = struct {
    span: source.Span,
    operation: Operation,
    /// Direct enclosing parameter when the owner is statically known.
    input: ?u16 = null,
    /// Owner local slot when the receiver root is statically known.
    owner: ?typed.LocalId = null,
};

/// Classify one resolved buffer/collection operation.
pub fn buffer(kind: buffer_operations.Kind, dictionary: bool) Classification {
    const allocates = buffer_operations.managedAllocation(kind, dictionary);
    // Copies and slices allocate a fresh outer container while retaining the
    // origins of any managed elements they carry; they never write the receiver.
    if (kind == .copy or kind == .slice or kind == .slice_step) return .{ .operation = .shallow_copy, .writes_receiver = false, .severs_outer = true };
    if (kind.mutates()) return .{ .operation = .receiver_write, .writes_receiver = true, .severs_outer = allocates };
    return .{ .operation = .read, .writes_receiver = false, .severs_outer = false };
}

/// Resolve the root local slot of a typed access chain, if there is one.
fn rootLocal(program: typed.Program, node_id: typed.NodeId, depth: usize) ?typed.LocalId {
    if (depth == 256) return null;
    const node = program.nodes[@backingInt(node_id)];
    return switch (node.data) {
        .local => |slot| slot,
        .field => |field| rootLocal(program, field.base, depth + 1),
        .index => |index| rootLocal(program, index.base, depth + 1),
        .replace => |replace| rootLocal(program, replace.base, depth + 1),
        else => null,
    };
}

/// Map one local slot to an enclosing parameter position.
pub fn localInput(program: typed.Program, function: typed.Function, slot: typed.LocalId) ?u16 {
    _ = program;
    const index = @backingInt(slot);
    if (index >= function.signature.parameter_count) return null;
    return @intCast(index);
}

/// The local slot an expression reads through fields, indexes and element
/// replacements, or null when it is not a path rooted at a local.
pub fn nodeRoot(program: typed.Program, node_id: typed.NodeId) ?typed.LocalId {
    return rootLocal(program, node_id, 0);
}

/// Resolve an expression's root local to an enclosing parameter position.
pub fn nodeInput(program: typed.Program, function: typed.Function, node_id: typed.NodeId) ?u16 {
    return if (rootLocal(program, node_id, 0)) |slot| localInput(program, function, slot) else null;
}

/// Classify one checked expression node as a managed receiver write.
pub fn typedNode(program: typed.Program, function: typed.Function, node: typed.Node) ?Witness {
    switch (node.data) {
        .buffer_operation => |operation| {
            const local = if (@backingInt(operation.owner) < function.scope.locals.len) function.scope.locals[@backingInt(operation.owner)] else return null;
            if (!local.ty.isAggregate() or local.ty.recordIndex() >= program.records.len) return null;
            const record = program.records[local.ty.recordIndex()];
            const classification = buffer(operation.kind, record.collection.kind == .dictionary);
            if (!classification.writes_receiver and !classification.severs_outer) return null;
            return .{ .span = node.span, .operation = classification.operation, .input = localInput(program, function, operation.owner), .owner = operation.owner };
        },
        .replace => {
            if (!node.ty.isAggregate()) return null;
            if (node.ty.recordIndex() >= program.records.len) return null;
            if (!program.records[node.ty.recordIndex()].managed) return null;
            const owner = rootLocal(program, node.data.replace.base, 0);
            return .{ .span = node.span, .operation = .receiver_write, .input = if (owner) |slot| localInput(program, function, slot) else null, .owner = owner };
        },
        .update => |update| {
            if (!node.ty.isAggregate() or node.ty.recordIndex() >= program.records.len) return null;
            if (!program.records[node.ty.recordIndex()].isManagedRecord()) return null;
            const owner = rootLocal(program, update.base, 0);
            return .{ .span = node.span, .operation = .receiver_write, .input = if (owner) |slot| localInput(program, function, slot) else null, .owner = owner };
        },
        else => return null,
    }
}

/// Classify one instruction from the checked bytecode model.
pub fn instruction(program: model.Program, function: model.Function, op: @FieldType(model.Instruction, "op"), span: source.Span) ?Witness {
    switch (op) {
        .replace_index => |access| {
            const ty = access.ty;
            if (!ty.isAggregate()) return null;
            if (ty.recordIndex() >= program.records.len) return null;
            if (!program.records[ty.recordIndex()].managed) return null;
            return .{ .span = span, .operation = .receiver_write, .input = null };
        },
        .update_record => |update| {
            if (!update.ty.isAggregate() or update.ty.recordIndex() >= program.records.len) return null;
            if (!program.records[update.ty.recordIndex()].isManagedRecord()) return null;
            return .{ .span = span, .operation = .receiver_write, .input = null };
        },
        .buffer_operation => |operation| {
            if (@backingInt(operation.owner) >= function.scope.locals.len) return null;
            const local = function.scope.locals[@backingInt(operation.owner)];
            if (!local.ty.isAggregate() or local.ty.recordIndex() >= program.records.len) return null;
            const record = program.records[local.ty.recordIndex()];
            const classification = buffer(operation.kind, record.collection.kind == .dictionary);
            if (!classification.writes_receiver and !classification.severs_outer) return null;
            const input: ?u16 = if (@backingInt(operation.owner) < function.signature.parameter_count) @intCast(@backingInt(operation.owner)) else null;
            return .{ .span = span, .operation = classification.operation, .input = input, .owner = operation.owner };
        },
        else => return null,
    }
}

/// Insert one parameter position into a sorted duplicate-free footprint.
pub fn insertPosition(positions: *std.ArrayList(u16), allocator: std.mem.Allocator, position: u16) MutationError!void {
    for (positions.items) |existing| if (existing == position) return;
    try positions.append(allocator, position);
    std.mem.sort(u16, positions.items, {}, std.sort.asc(u16));
}

test "buffer classification separates receiver writes from shallow copies" {
    const t = std.testing;
    try t.expect(buffer(.append, false).writes_receiver);
    try t.expect(buffer(.write, true).writes_receiver);
    try t.expect(buffer(.update, true).writes_receiver);
    try t.expect(!buffer(.copy, false).writes_receiver);
    try t.expect(buffer(.copy, false).severs_outer);
    try t.expect(!buffer(.slice, false).writes_receiver);
    try t.expect(buffer(.slice, false).severs_outer);
    try t.expect(!buffer(.length, false).writes_receiver);
    try t.expect(!buffer(.index_of, false).writes_receiver);
}

test "position insertion normalizes duplicates and order" {
    const t = std.testing;
    var positions: std.ArrayList(u16) = .empty;
    defer positions.deinit(t.allocator);
    try insertPosition(&positions, t.allocator, 3);
    try insertPosition(&positions, t.allocator, 1);
    try insertPosition(&positions, t.allocator, 3);
    try t.expectEqualSlices(u16, &.{ 1, 3 }, positions.items);
}
