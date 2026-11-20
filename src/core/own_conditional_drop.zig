//! Give branch-local owners a null value on paths where they were never built.
const std = @import("std");
const ir = @import("ir.zig");
const origins = @import("inline_origins.zig");

/// Cleanup construction only allocates ordinary phi operands and provenance.
pub const Error = error{OutOfMemory};

const Death = struct { owner: ir.Ref, from: u32, to: ?u32 };

/// SSA availability of a managed owner at each scheduled cleanup block.
pub const Builder = struct {
    arena: std.mem.Allocator,
    scratch: std.mem.Allocator,
    function: *ir.Function,
    origin: ?origins.Context,
    values: std.AutoHashMapUnmanaged(u64, ir.Ref) = .empty,
    deaths: std.AutoHashMapUnmanaged(Death, void) = .empty,
    empties: std.AutoHashMapUnmanaged(ir.Ref, ir.Ref) = .empty,

    /// A block cleanup leaves no owner on any outgoing edge.
    pub fn clearAfter(self: *Builder, owner: ir.Ref, block: u32) Error!void {
        try self.deaths.put(self.scratch, .{ .owner = owner, .from = block, .to = null }, {});
    }

    /// An edge cleanup only clears the owner for that successor.
    pub fn clearEdge(self: *Builder, owner: ir.Ref, from: u32, to: u32) Error!void {
        try self.deaths.put(self.scratch, .{ .owner = owner, .from = from, .to = to }, {});
    }

    /// A missing path carries managed `undef`, emitted as null or zero storage.
    pub fn read(self: *Builder, owner: ir.Ref, definition: u32, block: u32) Error!ir.Ref {
        if (block == definition) return owner;
        const key = (@as(u64, @backingInt(owner)) << 32) | block;
        if (self.values.get(key)) |value| return self.function.resolve(value);
        const ty = self.function.inst(owner).ty;
        const preds = self.function.blocks.items[block].preds.items;
        if (preds.len == 0) {
            const absent = try self.empty(owner);
            try self.values.put(self.scratch, key, absent);
            return absent;
        }
        // Publish the incomplete phi before following a loop predecessor.
        const phi = try self.append(.{ .op = .phi, .ty = ty });
        try self.function.blocks.items[block].insts.insert(self.arena, 0, phi);
        try self.values.put(self.scratch, key, phi);
        if (self.origin) |origin| try origin.setInstruction(self.arena, phi, origin.table.block(origin.function, block));
        const operands = try self.scratch.alloc(ir.Ref, preds.len);
        for (preds, operands) |pred, *value| value.* = try self.incoming(owner, definition, @intCast(pred.index()), block);
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.appendSlice(self.arena, operands);
        self.function.insts.items[phi.index()].data = (ir.ExtraSlice{ .start = start, .len = @intCast(operands.len) }).pack();
        return self.simplify(phi, block, operands);
    }

    /// The value `read` made for `owner` at `block`, if it made one; null when none was needed.
    pub fn peek(self: *const Builder, owner: ir.Ref, block: u32) ?ir.Ref {
        const key = (@as(u64, @backingInt(owner)) << 32) | block;
        const value = self.values.get(key) orelse return null;
        return self.function.resolve(value);
    }

    fn incoming(self: *Builder, owner: ir.Ref, definition: u32, from: u32, to: u32) Error!ir.Ref {
        if (self.deaths.contains(.{ .owner = owner, .from = from, .to = null })) return self.empty(owner);
        if (self.deaths.contains(.{ .owner = owner, .from = from, .to = to })) return self.empty(owner);
        return self.read(owner, definition, from);
    }

    fn empty(self: *Builder, owner: ir.Ref) Error!ir.Ref {
        if (self.empties.get(owner)) |value| return value;
        const value = try self.append(.{ .op = .undef, .ty = self.function.inst(owner).ty });
        try self.empties.put(self.scratch, owner, value);
        return value;
    }

    fn append(self: *Builder, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@as(u32, @intCast(self.function.insts.items.len)));
        try self.function.insts.append(self.arena, inst);
        return ref;
    }

    fn simplify(self: *Builder, phi: ir.Ref, block: u32, operands: []const ir.Ref) Error!ir.Ref {
        var same: ir.Ref = .none;
        for (operands) |raw| {
            const value = self.function.resolve(raw);
            if (value == phi or value == same) continue;
            if (same != .none) return phi;
            same = value;
        }
        const ty = self.function.inst(phi).ty;
        if (same == .none) same = try self.append(.{ .op = .undef, .ty = ty });
        self.function.insts.items[phi.index()] = .{ .op = .copy, .ty = ty, .a = same };
        const instructions = &self.function.blocks.items[block].insts;
        _ = instructions.orderedRemove(std.mem.indexOfScalar(ir.Ref, instructions.items, phi).?);
        return same;
    }
};
