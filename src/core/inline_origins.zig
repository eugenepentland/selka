//! Sparse source ancestry outside Core IR, retained through optimizer edits.
const std = @import("std");
const ir = @import("ir.zig");

/// Maximum inline ancestry; expansion is refused before changing IR beyond it.
pub const max_depth = 32;

/// Provenance recording only allocates.
pub const Error = std.mem.Allocator.Error;

/// One exact specialized callee and its original call in the parent frame.
pub const Frame = struct { function: u32, call_span: u32, parent: ?u32 };

/// Only cloned blocks and instruction overrides allocate entries.
pub const Table = struct {
    blocks: std.AutoHashMapUnmanaged(u64, u32) = .empty,
    /// A present null is an explicit physical-caller scope, not block fallback.
    instructions: std.AutoHashMapUnmanaged(u64, ?u32) = .empty,
    frames: std.ArrayList(Frame) = .empty,
    interned: std.AutoHashMapUnmanaged(Frame, u32) = .empty,
    functions: std.AutoHashMapUnmanaged(u32, void) = .empty,

    /// Block ancestry, absent for ordinary source blocks.
    pub fn block(self: *const Table, function: u32, id: u32) ?u32 {
        return self.blocks.get(key(function, id));
    }

    /// An override takes precedence over the block's default ancestry.
    pub fn instruction(self: *const Table, function: u32, b: u32, ref: ir.Ref) ?u32 {
        if (self.instructions.get(key(function, @intCast(ref.index())))) |frame| return frame;
        return self.block(function, b);
    }

    /// Store one block's ancestry without a dense per-function table.
    pub fn setBlock(self: *Table, a: std.mem.Allocator, function: u32, id: u32, frame: ?u32) Error!void {
        if (frame) |origin| {
            try self.functions.put(a, function, {});
            try self.blocks.put(a, key(function, id), origin);
        } else _ = self.blocks.remove(key(function, id));
    }

    /// Store a copied instruction's exact ancestry.
    pub fn setInstruction(self: *Table, a: std.mem.Allocator, function: u32, ref: ir.Ref, frame: ?u32) Error!void {
        if (frame != null) try self.functions.put(a, function, {});
        if (!self.functions.contains(function)) return;
        try self.instructions.put(a, key(function, @intCast(ref.index())), frame);
    }

    /// A function-local editing handle; defaults stay empty for hand-built IR.
    pub fn context(self: *Table, function: u32) Context {
        return .{ .table = self, .function = function };
    }

    /// Preflight every ancestry composition, then prepare one bounded clone.
    pub fn prepare(self: *Table, a: std.mem.Allocator, site: Call, callee: *const ir.Function) Error!?Clone {
        const parent = self.instruction(site.caller, site.block, site.ref);
        const outer_depth = self.depth(parent) + 1;
        if (outer_depth > max_depth) return null;
        for (callee.blocks.items, 0..) |source, b| {
            if (outer_depth + self.depth(self.block(site.callee, @intCast(b))) > max_depth) return null;
            for (source.insts.items) |ref| {
                if (outer_depth + self.depth(self.instruction(site.callee, @intCast(b), ref)) > max_depth) return null;
            }
        }
        const outer = try self.intern(a, .{ .function = site.callee, .call_span = site.span, .parent = parent });
        return .{ .table = self, .caller = site.caller, .callee = site.callee, .outer = outer };
    }

    fn depth(self: *const Table, frame: ?u32) u32 {
        var current = frame;
        var count: u32 = 0;
        while (current) |id| : (count += 1) current = self.frames.items[id].parent;
        return count;
    }

    fn intern(self: *Table, a: std.mem.Allocator, frame: Frame) Error!u32 {
        const entry = try self.interned.getOrPut(a, frame);
        if (entry.found_existing) return entry.value_ptr.*;
        entry.value_ptr.* = @intCast(self.frames.items.len);
        try self.frames.append(a, frame);
        return entry.value_ptr.*;
    }
};

/// A call's real function identities and unchanged source position.
pub const Call = struct { caller: u32, callee: u32, block: u32, ref: ir.Ref, span: u32 };

/// Rebase any nested callee origin beneath this call's outer frame.
pub const Clone = struct {
    table: *Table,
    caller: u32,
    callee: u32,
    outer: u32,
    rebased: std.AutoHashMapUnmanaged(u32, u32) = .empty,

    /// CFG clones inherit block scopes; leaf overrides remain instruction-local.
    pub fn block(self: *Clone, a: std.mem.Allocator, source: u32, destination: u32) Error!void {
        const origin = try self.rebase(a, self.table.block(self.callee, source));
        try self.table.setBlock(a, self.caller, destination, origin);
    }

    /// Copy a leaf instruction's effective scope or a CFG instruction override.
    pub fn instruction(self: *Clone, a: std.mem.Allocator, b: u32, source: ir.Ref, destination: ir.Ref, leaf: bool) Error!void {
        const old = if (leaf) self.table.instruction(self.callee, b, source) else self.table.instructions.get(key(self.callee, @intCast(source.index()))) orelse return;
        const origin = try self.rebase(a, old);
        try self.table.setInstruction(a, self.caller, destination, origin);
    }

    fn rebase(self: *Clone, a: std.mem.Allocator, raw: ?u32) std.mem.Allocator.Error!u32 {
        const id = raw orelse return self.outer;
        if (self.rebased.get(id)) |known| return known;
        const original = self.table.frames.items[id];
        const parent = try self.rebase(a, original.parent);
        const next = try self.table.intern(a, .{ .function = original.function, .call_span = original.call_span, .parent = parent });
        try self.rebased.put(a, id, next);
        return next;
    }
};

/// Provenance editing for one real IR function.
pub const Context = struct {
    table: *Table,
    function: u32,

    /// Effective origin at a source instruction before it is moved.
    pub fn at(self: Context, block: u32, ref: ir.Ref) ?u32 {
        return self.table.instruction(self.function, block, ref);
    }

    /// New blocks inherit a selected source scope.
    pub fn setBlock(self: Context, a: std.mem.Allocator, block: u32, frame: ?u32) Error!void {
        try self.table.setBlock(a, self.function, block, frame);
    }

    /// New checked instructions inherit their update or definition anchor.
    pub fn setInstruction(self: Context, a: std.mem.Allocator, ref: ir.Ref, frame: ?u32) Error!void {
        try self.table.setInstruction(a, self.function, ref, frame);
    }

    /// A physical block split or loop duplicate retains its default scope.
    pub fn copyBlock(self: Context, a: std.mem.Allocator, source: u32, destination: u32) Error!void {
        try self.setBlock(a, destination, self.table.block(self.function, source));
    }

    /// Transfer a leaf override through an instruction clone.
    pub fn copyInstruction(self: Context, a: std.mem.Allocator, source: ir.Ref, destination: ir.Ref) Error!void {
        if (self.table.instructions.get(key(self.function, @intCast(source.index())))) |frame| try self.setInstruction(a, destination, frame);
    }
};

fn key(function: u32, id: u32) u64 {
    return (@as(u64, function) << 32) | id;
}
