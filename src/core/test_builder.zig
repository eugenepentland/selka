//! Small SSA construction tools shared by test dispatch and copied-value adapters.
const std = @import("std");
const ir = @import("ir.zig");
/// Allocation is the only construction failure.
pub const Error = error{OutOfMemory};
/// One synthesized function under construction.
pub const Builder = struct {
    arena: std.mem.Allocator,
    function: ir.Function,
    /// Add an initially empty basic block.
    pub fn block(self: *Builder) Error!ir.BlockId {
        const id: ir.BlockId = @fromBackingInt(@intCast(self.function.blocks.items.len));
        try self.function.blocks.append(self.arena, .{});
        return id;
    }
    /// Add a parameter or constant outside the instruction lists.
    pub fn detached(self: *Builder, inst: ir.Inst) Error!ir.Ref {
        const ref: ir.Ref = @fromBackingInt(@intCast(self.function.insts.items.len));
        try self.function.insts.append(self.arena, inst);
        return ref;
    }
    /// Add an integer constant with its exact bit pattern.
    pub fn constant(self: *Builder, ty: ir.Type, value: i64) Error!ir.Ref {
        return self.detached(.{ .op = .iconst, .ty = ty, .data = @bitCast(value) });
    }
    /// Add an instruction to a basic block.
    pub fn put(self: *Builder, at: ir.BlockId, inst: ir.Inst) Error!ir.Ref {
        const ref = try self.detached(inst);
        try self.function.blocks.items[at.index()].insts.append(self.arena, ref);
        return ref;
    }
    /// Store an operand slice in the function's extra array.
    pub fn extra(self: *Builder, refs: []const ir.Ref) Error!u64 {
        const start: u32 = @intCast(self.function.extra.items.len);
        try self.function.extra.appendSlice(self.arena, refs);
        return (ir.ExtraSlice{ .start = start, .len = @intCast(refs.len) }).pack();
    }
    /// Add an edge and update the target's predecessor order.
    pub fn jump(self: *Builder, from: ir.BlockId, to: ir.BlockId) Error!void {
        _ = try self.put(from, .{ .op = .jump, .ty = .void, .data = @backingInt(to) });
        try self.function.blocks.items[to.index()].preds.append(self.arena, from);
    }
    /// Add a conditional edge and both predecessor entries.
    pub fn branch(self: *Builder, from: ir.BlockId, condition: ir.Ref, yes: ir.BlockId, no: ir.BlockId) Error!void {
        _ = try self.put(from, .{ .op = .branch, .ty = .void, .a = condition, .data = ir.packTargets(yes, no) });
        try self.function.blocks.items[yes.index()].preds.append(self.arena, from);
        try self.function.blocks.items[no.index()].preds.append(self.arena, from);
    }
    /// Add a call to an already declared function.
    pub fn call(self: *Builder, at: ir.BlockId, module: *const ir.Module, callee: u32, args: []const ir.Ref) Error!ir.Ref {
        return self.put(at, .{ .op = .call, .ty = module.functions.items[callee].signature.ret, .a = @fromBackingInt(callee), .data = try self.extra(args) });
    }
};
/// Declare a runtime helper once, retaining its explicit Core signature.
pub fn helper(a: std.mem.Allocator, module: *ir.Module, name: []const u8, params: []const ir.Type, ret: ir.Type) Error!u32 {
    for (module.functions.items, 0..) |f, index| if (std.mem.eql(u8, f.name, name) and f.signature.ret == ret and std.mem.eql(ir.Type, f.signature.params, params)) return @intCast(index);
    const index: u32 = @intCast(module.functions.items.len);
    try module.functions.append(a, .{ .name = name, .signature = .{ .params = try a.dupe(ir.Type, params), .ret = ret, .linkage = .runtime_c } });
    return index;
}
