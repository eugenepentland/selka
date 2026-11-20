//! Materialize a borrowed view where an owned value is required.
//!
//! A view binding (wave 3: `const piece = text[a:b]` over immutable text) holds
//! the slice's borrowed octets, so a read costs nothing. Every use that needs an
//! owned `str` — a call to a function that does not take a span, an aggregate
//! field, a concatenation, a return from an owned function — gets a copy
//! (`str_from_view`) inserted immediately before it, which is the copy the
//! program made before the binding became a view. The admission list is exactly
//! the verifier's (`verify_ir.viewUses`), so the rewritten function verifies.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");
const copy_sites = @import("copy_sites.zig");

/// Insert the copies `f` needs; returns how many were added.
pub fn run(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    var changed: u32 = try materializeMerges(arena, module, f);
    for (f.blocks.items) |*block| {
        var out: std.ArrayList(ir.Ref) = .empty;
        try out.ensureTotalCapacity(arena, block.insts.items.len);
        for (block.insts.items) |ref| {
            var current = f.inst(ref);
            var slot: usize = 0;
            while (slot < f.valueOperands(current).len()) : (slot += 1) {
                const operand = f.resolve(f.valueOperands(current).get(slot));
                if (!f.inst(operand).ty.isSpan()) continue;
                if (admitted(module, f, current, slot)) continue;
                // A view handed to a written copy is copied by that copy's own work: the materialization is written too.
                const forwarded = f.valueOperands(current).get(slot);
                const written: u64 = if (copy_sites.writtenSource(f, forwarded) or copy_sites.isWritten(current)) flags.written_copy else 0;
                // A materialization that stands for a written copy keeps that copy's position (W4: `cost --sites` reads it).
                const copy = try copyOf(module, arena, f, operand, copy_sites.writtenSpan(f, forwarded, current.span), written);
                out.appendAssumeCapacity(copy);
                current = withOperand(f, current, slot, copy);
                changed += 1;
            }
            f.insts.items[ref.index()] = current;
            out.appendAssumeCapacity(ref);
        }
        block.insts = out;
    }
    return changed;
}

/// Materialize a view operand of an owned merge. A phi is a block's first
/// instruction, so the copy has to run at the end of each predecessor block and
/// the phi keeps the owned value (REGRESSION-R1).
fn materializeMerges(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    var block_index: usize = 0;
    while (block_index < f.blocks.items.len) : (block_index += 1) {
        var position: usize = 0;
        while (position < f.blocks.items[block_index].insts.items.len) : (position += 1) {
            const ref = f.blocks.items[block_index].insts.items[position];
            const inst = f.inst(ref);
            if (inst.op != .phi or inst.ty.isSpan()) continue;
            const preds = f.blocks.items[block_index].preds.items;
            const operands = f.operands(inst.data);
            if (operands.len != preds.len) continue;
            const start = ir.ExtraSlice.unpack(inst.data).start;
            var slot: usize = 0;
            while (slot < operands.len) : (slot += 1) {
                const operand = f.resolve(operands[slot]);
                if (!f.inst(operand).ty.isSpan()) continue;
                const copy = try copyOf(module, arena, f, operand, inst.span, 0);
                try insertBeforeTerminator(arena, f, preds[slot], copy);
                f.extra.items[start + slot] = copy;
                changed += 1;
            }
        }
    }
    return changed;
}

/// Put `ref` at the end of `block`, before its terminator.
fn insertBeforeTerminator(arena: std.mem.Allocator, f: *ir.Function, block: ir.BlockId, ref: ir.Ref) std.mem.Allocator.Error!void {
    const insts = &f.blocks.items[block.index()].insts;
    const end = if (insts.items.len == 0) 0 else insts.items.len - 1;
    try insts.insert(arena, end, ref);
}

/// Append the owned copy of `view`; returns its value. A view of text copies to
/// `str`, a view of bytes copies to `bytes` (`myl_core_view_copy_bytes`), so the
/// owned read keeps the family the program saw.
fn copyOf(module: *ir.Module, arena: std.mem.Allocator, f: *ir.Function, view: ir.Ref, span: u32, mark: u64) std.mem.Allocator.Error!ir.Ref {
    const ref: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
    if (!viewIsBytes(f, view, 0)) {
        try f.insts.append(arena, .{ .op = .str_from_view, .ty = .str, .a = view, .data = mark, .span = span });
        return ref;
    }
    const callee = try bytesCopyFunction(module, arena);
    const operands = try arena.alloc(ir.Ref, 1);
    operands[0] = view;
    const start: u32 = @intCast(f.extra.items.len);
    try f.extra.appendSlice(arena, operands);
    try f.insts.append(arena, .{ .op = .call, .ty = .bytes, .a = @fromBackingInt(callee), .data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack() | mark, .span = span });
    return ref;
}

/// Whether `view` borrows byte octets rather than text: follow the producer that
/// made it, because a merged or copied view keeps its source's family.
pub fn viewIsBytes(f: *const ir.Function, ref: ir.Ref, depth: usize) bool {
    _ = depth;
    // The family is the view's type (C9 bytes): a bytes view is `bytes_view` at every producer, parameter and merge.
    return f.inst(f.resolve(ref)).ty == .bytes_view;
}

/// The audited span copy of byte octets (`zero_rc.zig`: one span input, a fresh
/// byte result). Declared here because the builder declares it only when a
/// source-level `copy(value)` of a byte view exists.
fn bytesCopyFunction(module: *ir.Module, arena: std.mem.Allocator) std.mem.Allocator.Error!u32 {
    for (module.functions.items, 0..) |function, index| {
        if (!std.mem.eql(u8, function.name, "myl_core_view_copy_bytes")) continue;
        if (function.signature.ret == .bytes and std.mem.eql(ir.Type, function.signature.params, &.{.bytes})) return @intCast(index);
    }
    const index: u32 = @intCast(module.functions.items.len);
    // The runtime's copy of a bytes view (`zero_rc.zig` audits it; the emitter declares it as the runtime does): a span
    // argument declared as its owned block, as `Builder.runtimeFunction` declares it.
    try module.functions.append(arena, .{ .name = "myl_core_view_copy_bytes", .signature = .{ .params = try arena.dupe(ir.Type, &.{.bytes}), .ret = .bytes, .linkage = .extern_c, .passing = .{ .views = 1 } } });
    return index;
}

/// `inst` with operand `slot` replaced by `value`.
fn withOperand(f: *ir.Function, inst: ir.Inst, slot: usize, value: ir.Ref) ir.Inst {
    var updated = inst;
    const operands = f.valueOperands(inst);
    if (slot < operands.direct_len) {
        if (slot == 0) updated.a = value else updated.b = value;
        return updated;
    }
    const start = ir.ExtraSlice.unpack(inst.data).start;
    f.extra.items[start + slot - operands.direct_len] = value;
    return updated;
}

/// Whether the use of a view at operand `slot` needs no copy. This mirrors
/// `verify_ir.viewUses`: the two lists must stay equal, or the verifier refuses
/// what this pass leaves alone.
/// The value a slot of `inst` reads.
fn inst_operand(f: *const ir.Function, inst: ir.Inst, slot: usize) ir.Ref {
    return f.valueOperands(inst).get(slot);
}

fn admitted(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst, slot: usize) bool {
    return switch (inst.op) {
        // A merged view stays borrowed; an owned merge's view operands were
        // copied in their predecessors (`materializeMerges`). This is the
        // verifier's rule (`verify_ir.textViewUse`), and the two must agree.
        .phi => inst.ty.isSpan(),
        .str_from_view, .str_len, .list_len, .str_parse_int, .str_view_of, .copy => slot == 0,
        // The span of a parameter's frame header is read in place (C9 S1); its owner is a block, not a view.
        .text_frame => slot == 1,
        // A borrowed record's frame block reads its parameter's view in place (RB1).
        .block_frame => slot == 0,
        .list_get => slot == 0 and inst.ty == .u8,
        .buffer_append => slot == 1,
        // A character read of a view decodes in place (fuse_text_scalar).
        .str_code => slot == 0,
        .str_width => slot == 0,
        // A fixed-width read of a view loads its octets in place (build_byte_load).
        .byte_load => slot == 0,
        .str_append_char => slot == 1,
        // Transient wrappers and writeback tuples keep their borrowed leaf.
        // Ordinary owned aggregates still require owned operands.
        .union_make, .record_make => module.containsBorrow(inst.ty),
        // Borrowed text and byte results retain their declared representation.
        .ret => module.containsBorrow(f.signature.ret) and slot == 0,
        // A text view prints in place; a bytes view prints its octets as `b'...'`, so it is copied first.
        .print => !viewIsBytes(f, inst_operand(f, inst, slot), 0),
        // The probe's result is an integer; the dictionary it probes is the operand (CX2).
        .dict_find => slot == 1 and isSpanKeyed(module, f.inst(f.resolve(inst.a)).ty),
        .call => inst.a.index() < module.functions.items.len and admittedCall(module.functions.items[inst.a.index()].signature, slot),
        // Operand 0 is the function value; argument `slot - 1` is a view when the callable takes a view there.
        .call_indirect => slot >= 1 and admittedIndirect(module, f, inst, slot - 1),
        else => false,
    };
}

/// Whether `ty` is a dictionary keyed by text or bytes, the dictionaries a borrowed key may probe (CX2: a bytes
/// key hashes and compares its octets exactly as a text key does). A read-only borrowed dictionary
/// (`const t = record.table`) shares its storage type's layout, so it admits a borrowed key too, as the
/// verifier and the emitter already do (`verify_ir.compoundOf`, `emit_dict_span.lookedUp`).
fn isSpanKeyed(module: *const ir.Module, ty: ir.Type) bool {
    const dict = module.dictShape(ty) orelse return false;
    return dict.key == .str or dict.key == .bytes;
}

/// Whether parameter `slot` of `signature` takes a borrowed span: an internal
/// view parameter, or an extern span parameter. Mirrors `verify_ir.admittedView`.
fn admittedIndirect(module: *const ir.Module, f: *const ir.Function, inst: ir.Inst, argument: usize) bool {
    const callee = f.inst(f.resolve(inst.a)).ty;
    if (module.kind(callee) != .@"fn") return false;
    const params = module.compound(callee).@"fn".params;
    return argument < params.len and params[argument].isSpan();
}

fn admittedCall(sig: ir.Signature, slot: usize) bool {
    if (slot >= sig.params.len) return false;
    if (sig.linkage == .internal) return sig.params[slot].isSpan();
    if (sig.params[slot] != .str and sig.params[slot] != .bytes) return false;
    return sig.passing.viewAt(slot) and !sig.passing.takes(slot);
}
