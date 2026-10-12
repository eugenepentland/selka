//! Slices that are only read borrow their source (NEW-CORE-S1-VIEW-1, NEW-CORE-S1-VIEW-4).
//!
//! `d.get(s[i:j], …)`, `s[i:j] in d`, `d[s[i:j]]` and the fused get-then-set update all
//! probe with the slice and, on a miss, may insert it; `s[i:j] == t`, `len(s[i:j])`,
//! `s[i:j].startswith(p)`, `.endswith(p)` and `p in s[i:j]` only read it. When those are
//! the slice's only uses, the slice becomes a `str_slice_view` of `s`: a probe hashes and
//! compares the octets in place, a read calls the runtime's span form of the same helper
//! (its `str` parameters take `(data, length)` spans), and an insert materializes its own
//! key (`str_from_view`) right before it, keeping the probe it already has. The view lives
//! in SSA only (`verify_ir`), and ownership keeps `s` alive and unchanged for as long as
//! any use of the view remains (a borrowed part's uses keep its parent live, `own.zig`),
//! so the view never dangles.
const std = @import("std");
const ir = @import("ir.zig");

/// A runtime text helper that only reads its `str` arguments, and its span form.
const SpanForm = struct { text: []const u8, span: []const u8 };

/// The helpers a borrowed slice may be passed to: every `str` parameter of the span form
/// is a `(data, length)` span, and each answers what the text form answers.
const span_forms = [_]SpanForm{
    .{ .text = "myl_core_str_split_offsets", .span = "myl_core_span_split_offsets" },
    .{ .text = "myl_core_str_split_prefix_1", .span = "myl_core_span_split_prefix_1" },
    .{ .text = "myl_core_str_split_prefix_2", .span = "myl_core_span_split_prefix_2" },
    .{ .text = "myl_core_str_split_prefix_3", .span = "myl_core_span_split_prefix_3" },
    .{ .text = "myl_core_str_split_prefix_4", .span = "myl_core_span_split_prefix_4" },
    .{ .text = "myl_core_str_split_prefix_5", .span = "myl_core_span_split_prefix_5" },
    .{ .text = "myl_core_str_split_prefix_6", .span = "myl_core_span_split_prefix_6" },
    .{ .text = "myl_core_str_split_prefix_7", .span = "myl_core_span_split_prefix_7" },
    .{ .text = "myl_core_str_split_prefix_8", .span = "myl_core_span_split_prefix_8" },
    .{ .text = "myl_core_str_eq", .span = "myl_core_span_eq" },
    .{ .text = "myl_core_str_chars", .span = "myl_core_span_chars" },
    .{ .text = "myl_core_str_starts", .span = "myl_core_span_starts" },
    .{ .text = "myl_core_str_ends", .span = "myl_core_span_ends" },
    .{ .text = "myl_core_str_contains", .span = "myl_core_span_contains" },
};

/// Rewrite every qualifying slice of every internal function; returns how many changed.
pub fn run(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!u32 {
    return runRecording(arena, module, null);
}

/// Record every helper declaration request in its original producer traversal order.
pub fn runRecording(arena: std.mem.Allocator, module: *ir.Module, requests: ?[]std.ArrayList(u32)) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    const count = module.functions.items.len;
    for (0..count) |index| {
        // Declaring a span helper may move the module's function array.
        var function = module.functions.items[index];
        if (function.signature.linkage != .internal) continue;
        const events = if (requests) |all| if (index < all.len) &all[index] else null else null;
        changed += if (events) |capture| try rewriteRecording(arena, module, &function, capture) else try rewriteFunction(arena, module, &function);
        module.functions.items[index] = function;
    }
    return changed;
}

/// Rewrite the qualifying slices of one function; returns how many changed.
pub fn rewriteFunction(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    return rewriteRecording(arena, module, f, null);
}

fn rewriteRecording(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function, requests: ?*std.ArrayList(u32)) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    const count = f.insts.items.len;
    var copies: u32 = 0;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        // An explicit snapshot used solely for reads can borrow under the same
        // complete-use and parent-stability proof as a slice. Inserts still
        // construct an independent key on their miss path below.
        if (module.zero_rc and count <= 4096 and copies < 32 and inst.ty == .str) {
            if (@import("inline_snapshot.zig").source(module, f, inst)) |source| {
                copies += 1;
                const ref: ir.Ref = @fromBackingInt(@intCast(index));
                if (!onlyReads(f, module, ref) or try updated(arena, f, module, source)) continue;
                const zero: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
                try f.insts.append(arena, .{ .op = .iconst, .ty = .u64 });
                const len: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
                try f.insts.append(arena, .{ .op = .str_len, .ty = .u64, .a = source, .span = inst.span });
                try before(arena, f, ref, zero);
                try before(arena, f, ref, len);
                const start: u32 = @intCast(f.extra.items.len);
                try f.extra.append(arena, len);
                f.insts.items[index] = .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = zero, .data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack(), .span = inst.span };
                try rewriteUsesRecording(arena, f, module, ref, requests);
                changed += 1;
                continue;
            }
        }
        if (inst.op == .str_from_view and onlyReads(f, module, @fromBackingInt(@intCast(index)))) {
            if (module.zero_rc and try updated(arena, f, module, f.resolve(inst.a))) continue;
            f.insts.items[index] = .{ .op = .copy, .ty = .str_view, .a = inst.a, .span = inst.span };
            try rewriteUsesRecording(arena, f, module, f.resolve(inst.a), requests);
            changed += 1;
            continue;
        }
        const bytes = byteSlice(f, module, inst);
        if ((inst.op != .str_slice or inst.ty != .str) and !bytes) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(index));
        const source = if (bytes) f.operands(inst.data)[0] else inst.a;
        if (!onlyReads(f, module, ref) or try updated(arena, f, module, f.resolve(source))) continue;
        if (bytes) {
            const args = f.operands(inst.data);
            const start: u32 = @intCast(f.extra.items.len);
            const end = args[2];
            f.insts.items[index].a = args[0];
            f.insts.items[index].b = args[1];
            try f.extra.append(arena, end);
            f.insts.items[index].data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack();
        }
        f.insts.items[index].op = .str_slice_view;
        f.insts.items[index].ty = .str_view;
        try rewriteUsesRecording(arena, f, module, ref, requests);
        changed += 1;
    }
    return changed;
}

fn byteSlice(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.ty != .bytes or inst.a.index() >= module.functions.items.len or f.operands(inst.data).len != 3) return false;
    const target = module.functions.items[inst.a.index()];
    if (target.signature.linkage == .internal or target.signature.owned != 0 or target.signature.views != 0) return false;
    return std.mem.eql(u8, target.name, "myl_core_bytes_slice") and std.mem.eql(ir.Type, target.signature.params, &.{ .bytes, .i64, .i64 });
}

/// Whether every use of `slice` is the key of a text-dictionary lookup or insert, or an
/// argument of a reading helper with a span form, and there is at least one. A forwarding
/// copy stands for the slice itself.
pub fn onlyReads(f: *const ir.Function, module: *const ir.Module, slice: ir.Ref) bool {
    var uses: usize = 0;
    for (f.insts.items) |inst| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != slice) continue;
            uses += 1;
            if (inst.op == .call) {
                if (spanForm(module, inst) == null) return false;
                continue;
            }
            const span_read = inst.op == .str_len or inst.op == .list_len or inst.op == .str_parse_int or inst.op == .str_view_of;
            if (span_read and at == 0) continue;
            const lookup = inst.op == .dict_find and at == 1;
            const insertion = inst.op == .dict_insert and at == 2;
            if (!lookup and !insertion) return false;
            const ty = f.inst(f.resolve(inst.a)).ty;
            if (module.kind(ty) != .dict or module.compound(ty).dict.key != .str) return false;
        }
    }
    return uses != 0;
}

/// Whether `source`, or a phi it flows into, is updated in place anywhere in `f` (a
/// consuming update, or a call that takes it over as a `mut` argument). A view keeps its
/// source live, so an update while the view is live would copy the whole source instead
/// of updating it in place: such a slice stays a copy.
pub fn updated(arena: std.mem.Allocator, f: *const ir.Function, module: *const ir.Module, source: ir.Ref) std.mem.Allocator.Error!bool {
    if (module.zero_rc) return ownedUpdated(arena, f, module, source);
    const aliases = try arena.alloc(bool, f.insts.items.len);
    defer arena.free(aliases);
    @memset(aliases, false);
    aliases[source.index()] = true;
    var grew = true;
    while (grew) {
        grew = false;
        for (f.insts.items, 0..) |inst, index| {
            if (inst.op != .phi or aliases[index]) continue;
            for (f.operands(inst.data)) |operand| {
                if (!aliases[f.resolve(operand).index()]) continue;
                aliases[index] = true;
                grew = true;
                break;
            }
        }
    }
    for (f.insts.items) |inst| {
        if (inst.op.consumesOperand0() and inst.a != .none and aliases[f.resolve(inst.a).index()]) return true;
        const owned = switch (inst.op) {
            .call => if (inst.a.index() < module.functions.items.len) module.functions.items[inst.a.index()].signature.owned else continue,
            .call_indirect => module.compound(f.inst(f.resolve(inst.a)).ty).@"fn".owned,
            else => continue,
        };
        for (f.operands(inst.data), 0..) |argument, at| {
            if (at < 64 and owned & (@as(u64, 1) << @intCast(at)) != 0 and aliases[f.resolve(argument).index()]) return true;
        }
    }
    return false;
}

// A checked owner cannot be retained to keep an optimizer-created view alive.
// Follow its borrowed parent chain and phi aliases, and leave the source slice
// materialized if any of those owners transfers into storage or an owning call.
const AliasEdge = struct { target: ir.Ref, next: u32 };
const no_edge = std.math.maxInt(u32);

fn ownedUpdated(arena: std.mem.Allocator, f: *const ir.Function, module: *const ir.Module, source: ir.Ref) std.mem.Allocator.Error!bool {
    const length = f.insts.items.len;
    const heads = try arena.alloc(u32, length);
    defer arena.free(heads);
    @memset(heads, no_edge);
    var edges: std.ArrayList(AliasEdge) = .empty;
    defer edges.deinit(arena);
    // Reverse phi edges let each alias be visited once, including loop backedges.
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op != .phi) continue;
        for (f.operands(inst.data)) |operand| {
            const owner = f.resolve(operand).index();
            try edges.append(arena, .{ .target = @fromBackingInt(@intCast(index)), .next = heads[owner] });
            heads[owner] = @intCast(edges.items.len - 1);
        }
    }
    const aliases = try arena.alloc(bool, length);
    defer arena.free(aliases);
    @memset(aliases, false);
    var pending: std.ArrayList(ir.Ref) = .empty;
    defer pending.deinit(arena);
    try alias(arena, f, aliases, &pending, source);
    while (pending.pop()) |ref| {
        const inst = f.inst(ref);
        if (borrowedParent(f, module, inst)) |parent| try alias(arena, f, aliases, &pending, parent);
        if (inst.op == .phi) for (f.operands(inst.data)) |operand| try alias(arena, f, aliases, &pending, operand);
        var edge = heads[ref.index()];
        while (edge != no_edge) : (edge = edges.items[edge].next) try alias(arena, f, aliases, &pending, edges.items[edge].target);
    }
    for (f.insts.items) |inst| {
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            const operand = f.resolve(operands.get(at));
            if (aliases[operand.index()] and f.inst(operand).op != .str_const and takesOwner(f, module, inst, at)) return true;
        }
    }
    return false;
}

fn alias(arena: std.mem.Allocator, f: *const ir.Function, aliases: []bool, pending: *std.ArrayList(ir.Ref), value: ir.Ref) std.mem.Allocator.Error!void {
    const ref = f.resolve(value);
    if (aliases[ref.index()]) return;
    aliases[ref.index()] = true;
    try pending.append(arena, ref);
}

fn borrowedParent(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst) ?ir.Ref {
    return switch (inst.op) {
        .list_get, .list_get_field, .record_get, .union_payload, .box_get, .dict_entry_key, .dict_entry_value, .array_get, .str_view_of, .str_slice_view => inst.a,
        .call => if (module.functions.items[inst.a.index()].signature.viewSource()) |at| f.operands(inst.data)[at] else null,
        else => null,
    };
}

fn takesOwner(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst, at: usize) bool {
    if (at == 0 and inst.op.consumesOperand0()) return true;
    const signature: ?ir.Signature = switch (inst.op) {
        .call => module.functions.items[inst.a.index()].signature,
        .call_indirect => module.compound(f.inst(f.resolve(inst.a)).ty).@"fn",
        else => null,
    };
    if (signature) |sig| {
        // valueOperands includes the indirect callee before the arguments.
        const first: usize = if (inst.op == .call_indirect) 1 else 0;
        if (at < first or at - first >= 64) return false;
        return (sig.owned | sig.consumes) & (@as(u64, 1) << @intCast(at - first)) != 0;
    }
    return switch (inst.op) {
        .list_push, .record_set, .union_make, .union_take, .box_make, .box_take, .ret, .release, .record_make => true,
        .list_set, .list_set_field, .array_set, .dict_set_value, .dict_insert => at >= 2,
        else => false,
    };
}

/// The span form of a direct call of a reading helper, every parameter a borrowed `str`.
/// The builder declares these helpers `runtime_c` (`str_eq`) or `extern_c` (the others);
/// either way the symbol is the runtime's own, since a second definition of a `myl_core_`
/// symbol cannot link beside the runtime object.
fn spanForm(module: *const ir.Module, call: ir.Inst) ?SpanForm {
    if (call.a.index() >= module.functions.items.len) return null;
    const callee = module.functions.items[call.a.index()];
    const signature = callee.signature;
    if (decodeForm(module, callee)) |form| return form;
    if (signature.linkage == .internal or signature.owned != 0) return null;
    for (signature.params) |param| if (param != .str and param != .bytes) return null;
    for (span_forms) |form| {
        // A call another slice already moved to the span form keeps it.
        const spans = signature.linkage == .runtime_c and signature.views == (@as(u64, 1) << @intCast(signature.params.len)) - 1;
        if (!std.mem.eql(u8, callee.name, if (spans) form.span else form.text)) continue;
        if (!spans and signature.views != 0) return null;
        const offsets = std.mem.startsWith(u8, form.text, "myl_core_str_split_");
        if (offsets) return if (module.kind(signature.ret) == .list) form else null;
        const ret: ir.Type = if (std.mem.eql(u8, form.text, "myl_core_str_chars")) .u64 else .bool;
        return if (signature.ret == ret) form else null;
    }
    return null;
}

// Validation borrows exactly the selected octets; successful decoding constructs
// an independent string. Admit only compiler-declared one-argument readers.
fn decodeForm(module: *const ir.Module, callee: ir.Function) ?SpanForm {
    const sig = callee.signature;
    if (!module.zero_rc or sig.linkage != .runtime_c) return null;
    if (sig.owned != 0 or sig.consumes != 0) return null;
    const forms = [_]SpanForm{
        .{ .text = "myl_core_bytes_utf8_count", .span = "myl_core_span_utf8_count" },
        .{ .text = "myl_core_bytes_decode_text", .span = "myl_core_span_decode_text" },
    };
    for (forms, 0..) |form, i| {
        const span = std.mem.eql(u8, callee.name, form.span);
        if (!span and !std.mem.eql(u8, callee.name, form.text)) continue;
        const ret: ir.Type = if (i == 0) .i64 else .str;
        if (sig.ret != ret or sig.views != @as(u64, if (span) 1 else 0)) return null;
        if (!std.mem.eql(ir.Type, sig.params, if (span) &.{.str} else &.{.bytes})) return null;
        for (module.functions.items) |decl| {
            if (!std.mem.eql(u8, decl.name, form.span)) continue;
            const candidate = decl.signature;
            if (candidate.linkage != .runtime_c or candidate.owned != 0 or candidate.consumes != 0) return null;
            if (candidate.views != 1 or candidate.ret != ret or !std.mem.eql(ir.Type, candidate.params, &.{.str})) return null;
        }
        return form;
    }
    return null;
}

/// The span form's declaration, added on first use: the text form's signature with every
/// parameter a span.
fn spanCallee(arena: std.mem.Allocator, module: *ir.Module, text: ir.Signature, symbol: []const u8) std.mem.Allocator.Error!ir.Ref {
    const views: u64 = (@as(u64, 1) << @intCast(text.params.len)) - 1;
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage == .runtime_c and function.signature.views == views and std.mem.eql(u8, function.name, symbol)) return @fromBackingInt(@intCast(index));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    const params = try arena.alloc(ir.Type, text.params.len);
    @memset(params, .str);
    try module.functions.append(arena, .{ .name = symbol, .signature = .{ .params = params, .ret = text.ret, .linkage = .runtime_c, .views = views } });
    return ref;
}

/// Retype the view's copies, call each reading helper's span form, and give each insert
/// a key materialized from the view.
pub fn rewriteUses(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, view: ir.Ref) std.mem.Allocator.Error!void {
    return rewriteUsesRecording(arena, f, module, view, null);
}

fn rewriteUsesRecording(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, view: ir.Ref, requests: ?*std.ArrayList(u32)) std.mem.Allocator.Error!void {
    const count = f.insts.items.len;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        if (inst.op == .copy and f.resolve(inst.a) == view) {
            f.insts.items[index].ty = .str_view;
            continue;
        }
        if (inst.op == .list_len and f.resolve(inst.a) == view) f.insts.items[index].op = .str_len;
        if (inst.op == .call and usesValue(f, inst, view)) {
            const form = spanForm(module, inst) orelse continue;
            const callee = try spanCallee(arena, module, module.functions.items[inst.a.index()].signature, form.span);
            f.insts.items[index].a = callee;
            if (requests) |events| try events.append(arena, @intCast(callee.index()));
            continue;
        }
        if (inst.op != .dict_insert or f.resolve(f.operands(inst.data)[0]) != view) continue;
        const value = f.operands(inst.data)[1];
        const key: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
        try f.insts.append(arena, .{ .op = .str_from_view, .ty = .str, .a = view, .span = inst.span });
        try before(arena, f, @fromBackingInt(@intCast(index)), key);
        const start: u32 = @intCast(f.extra.items.len);
        try f.extra.appendSlice(arena, &.{ key, value });
        f.insts.items[index].data = (ir.ExtraSlice{ .start = start, .len = 2 }).pack();
    }
}

fn usesValue(f: *const ir.Function, inst: ir.Inst, value: ir.Ref) bool {
    const operands = f.valueOperands(inst);
    for (0..operands.len()) |at| if (f.resolve(operands.get(at)) == value) return true;
    return false;
}

fn before(arena: std.mem.Allocator, f: *ir.Function, ref: ir.Ref, added: ir.Ref) std.mem.Allocator.Error!void {
    for (f.blocks.items) |*block| {
        if (std.mem.indexOfScalar(ir.Ref, block.insts.items, ref)) |at| {
            try block.insts.insert(arena, at, added);
            return;
        }
    }
    // An instruction no block holds is dead: its key is never emitted either.
}
