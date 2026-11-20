//! RB1: the frame blocks of a function (`ir.Op.block_frame`). A borrowed record, or an element of a local collection of borrows
//! (H5), that holds a read-only text, bytes or list parameter bare holds a block: the parameter's C9 owner when the argument was a whole value, else a copy of the view this
//! call makes at its first use. Each parameter has one slot (an entry-block `alloca ptr`, null until the copy is made), so
//! every use of the parameter in the call, in a loop or not, shares one copy; every return frees it
//! (`myl_core_frame_block_release`). The copy has static storage, so no drop frees it or its elements. That nothing that
//! holds it outlives the call is the checker's (`Roots.frame`, rule R4) and `borrow_result`'s (AXIOMS A18).
const std = @import("std");
const ir = @import("ir.zig");

/// What emitting a frame block can fail with: allocation, or a `block_frame` whose parameter has no slot.
pub const Error = error{ OutOfMemory, UnsupportedEntry, UnsupportedInstruction };

const make_symbol = "myl_core_frame_block";
const release_symbol = "myl_core_frame_block_release";
/// Runtime block kinds (`core_rt.c`): list 0, text 1, bytes 3.
const kind_list = 0;
const kind_str = 1;
const kind_bytes = 3;

/// The slots of `function`'s frame blocks, by the resolved parameter view each one copies: one `alloca ptr` stored null in
/// the entry block per parameter. Empty for a function with no `block_frame`, which then emits nothing more.
pub fn plan(comptime Emitter: type, self: Emitter) Error!void {
    const f = self.function;
    for (f.blocks.items) |block| for (block.insts.items) |ref| {
        const inst = f.inst(ref);
        if (inst.op != .block_frame) continue;
        const key: u32 = @intCast(f.resolve(inst.a).index());
        if (self.block_frames.contains(key)) continue;
        const slot = try self.fresh("%frame.block");
        try self.state.allocas.print(self.a(), "  {s} = alloca ptr, align 8\n  store ptr null, ptr {s}, align 8\n", .{ slot, slot });
        try self.block_frames.put(self.a(), key, slot);
    };
    if (self.block_frames.count() == 0) return;
    try declare(Emitter, self, make_symbol, "declare ptr @myl_core_frame_block(ptr, i64, ptr, ptr, i64, i32, ptr) nounwind\n");
    try declare(Emitter, self, release_symbol, "declare void @myl_core_frame_block_release(ptr) nounwind\n");
}

/// `name = block_frame a, b`: the owner when it is not the sentinel, else the slot's copy, made now when the slot is empty.
pub fn instruction(comptime Emitter: type, self: Emitter, out: anytype, name: []const u8, inst: ir.Inst) Error!void {
    const f = self.function;
    const m = self.state.module;
    const slot = self.block_frames.get(@intCast(f.resolve(inst.a).index())) orelse return error.UnsupportedInstruction;
    const view = try self.value(inst.a);
    const data = try self.fresh("%frame.data");
    const len = try self.fresh("%frame.len");
    try out.print(self.a(), "  {s} = extractvalue {{ ptr, i64 }} {s}, 0\n  {s} = extractvalue {{ ptr, i64 }} {s}, 1\n", .{ data, view, len, view });
    const owner = if (inst.b == .none) "null" else try self.value(inst.b);
    var kind: u32 = kind_bytes;
    var element_size: u32 = 1;
    var layout: []const u8 = "null";
    if (inst.ty == .str) kind = kind_str;
    if (m.kind(inst.ty) == .list) {
        const element = m.compound(inst.ty).list;
        kind = kind_list;
        element_size = self.state.stride(element);
        if (m.managed(element)) layout = try self.state.layoutSymbol(element);
    }
    try out.print(self.a(), "  {s} = call ptr @myl_core_frame_block(ptr {s}, i64 {s}, ptr {s}, ptr {s}, i64 {d}, i32 {d}, ptr {s})\n", .{ name, data, len, owner, slot, element_size, kind, layout });
}

/// Free every frame block copy this call made: emitted before each `ret`.
pub fn release(comptime Emitter: type, self: Emitter, out: anytype) Error!void {
    var slots = self.block_frames.valueIterator();
    while (slots.next()) |slot| try out.print(self.a(), "  call void @myl_core_frame_block_release(ptr {s})\n", .{slot.*});
}

fn declare(comptime Emitter: type, self: Emitter, symbol: []const u8, line: []const u8) Error!void {
    for (self.state.declared.items) |known| if (std.mem.eql(u8, known, symbol)) return;
    try self.state.declared.append(self.a(), symbol);
    try self.state.externs.appendSlice(self.a(), line);
}
