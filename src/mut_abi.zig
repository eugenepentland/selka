//! Per-parameter mut collection ABI: rebound variables use caller storage;
//! never-rebound direct parameters keep the pinned mutable-payload fast path.
const std = @import("std");
const typed = @import("typed.zig");
const Walker = @import("typed_walk.zig").Walker;
const values = @import("value_semantics.zig");

const Edge = struct { caller: usize, parameter: u16, callee: usize, target: u16 };

/// Whether a type is a list, mapping or set whose whole binding can be replaced.
pub fn collection(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    if (!records[ty.recordIndex()].isCollection()) return false;
    return switch (records[ty.recordIndex()].collection.kind) {
        .list, .dictionary => true,
        else => false,
    };
}

/// Whether a lowered mut parameter receives the address of the caller's variable.
pub fn reference(records: []const typed.Record, function: anytype, position: usize) bool {
    if (position >= function.signature.parameter_count) return false;
    if (std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(position)) == null) return false;
    return typed.referenceMut(records, function.scope.locals[position].ty) or
        (position >= 16 and collection(records, function.scope.locals[position].ty)) or
        (position < 16 and function.signature.inferred.caller_storage & (@as(u16, 1) << @intCast(position)) != 0);
}

/// Whether every persisted storage bit names a declared mut collection parameter.
pub fn valid(records: []const typed.Record, function: anytype, mask: u16) bool {
    var position: u5 = 0;
    while (position < 16) : (position += 1) {
        if (mask & (@as(u16, 1) << @intCast(position)) == 0) continue;
        if (position >= function.signature.parameter_count or position >= function.scope.locals.len) return false;
        if (std.mem.indexOfScalar(u16, function.signature.declared_mutates, position) == null) return false;
        if (!collection(records, function.scope.locals[position].ty)) return false;
    }
    return true;
}

/// Compute a monotone whole-program ABI map, including recursive forwarding.
/// Callback calls use caller storage; adapters preserve each target's direct ABI.
pub fn collect(allocator: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error![]u16 {
    const masks = try allocator.alloc(u16, program.functions.len);
    for (masks, program.functions) |*mask, function| mask.* = function.signature.inferred.caller_storage;
    var edges: std.ArrayList(Edge) = .empty;
    defer edges.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        var scratch = std.heap.ArenaAllocator.init(allocator);
        defer scratch.deinit();
        const a = scratch.allocator();
        const facts = try values.Facts.collect(a, program, function);
        var walker = try Walker.init(a, program, function.scope.body);
        const scan = Scan{ .program = program, .function = function, .facts = &facts, .index = index, .masks = masks, .edges = &edges, .allocator = allocator };
        while (try walker.next()) |item| switch (item) {
            .statement => |id| scan.statement(id),
            .expression => |id| try scan.expression(id),
        };
    }
    var changed = true;
    while (changed) {
        changed = false;
        for (edges.items) |edge| {
            if (edge.target < 16 and masks[edge.callee] & (@as(u16, 1) << @intCast(edge.target)) == 0) continue;
            const bit = @as(u16, 1) << @intCast(edge.parameter);
            if (masks[edge.caller] & bit != 0) continue;
            masks[edge.caller] |= bit;
            changed = true;
        }
    }
    return masks;
}

fn collectionParameter(program: typed.Program, function: typed.Function, position: usize) bool {
    return position < 16 and position < function.signature.parameter_count and
        std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(position)) != null and
        collection(program.records, function.scope.locals[position].ty);
}

const Scan = struct {
    program: typed.Program,
    function: typed.Function,
    facts: *const values.Facts,
    index: usize,
    masks: []u16,
    edges: *std.ArrayList(Edge),
    allocator: std.mem.Allocator,

    fn statement(self: Scan, id: typed.StatementId) void {
        switch (self.program.statements[@backingInt(id)].data) {
            .assign => |store| if (!store.element and collectionParameter(self.program, self.function, @backingInt(store.slot))) {
                self.masks[self.index] |= @as(u16, 1) << @intCast(@backingInt(store.slot));
            },
            else => {},
        }
    }

    fn parameter(self: Scan, argument: typed.NodeId) ?u16 {
        const named = self.wholeLocal(argument) orelse return null;
        if (!collectionParameter(self.program, self.function, @backingInt(named))) return null;
        return @intCast(@backingInt(named));
    }

    fn wholeLocal(self: Scan, argument: typed.NodeId) ?typed.LocalId {
        var current = argument;
        var hops: usize = 0;
        while (hops < 64) : (hops += 1) switch (self.program.nodes[@backingInt(current)].data) {
            .local => |slot| {
                const index = @backingInt(slot);
                if (!self.facts.synthetic[index]) return slot;
                current = self.facts.stores[index] orelse return null;
            },
            .block_value => |block| current = block.value,
            else => return null,
        };
        return null;
    }

    fn expression(self: Scan, id: typed.NodeId) std.mem.Allocator.Error!void {
        switch (self.program.nodes[@backingInt(id)].data) {
            .call => |call| {
                const callee = self.program.functions[@backingInt(call.function)];
                for (callee.signature.declared_mutates) |position| {
                    if (position >= call.arguments.len) continue;
                    const parameter_index = self.parameter(call.arguments[position]) orelse continue;
                    try self.edges.append(self.allocator, .{ .caller = self.index, .parameter = parameter_index, .callee = @backingInt(call.function), .target = position });
                }
            },
            .invoke => |call| {
                const ty = self.program.nodes[@backingInt(call.callee)].ty;
                const signature = self.program.records[ty.recordIndex()].contract.callback orelse return;
                for (signature.mutates) |position| {
                    if (position >= call.arguments.len) continue;
                    const parameter_index = self.parameter(call.arguments[position]) orelse continue;
                    self.masks[self.index] |= @as(u16, 1) << @intCast(parameter_index);
                }
            },
            else => {},
        }
    }
};
