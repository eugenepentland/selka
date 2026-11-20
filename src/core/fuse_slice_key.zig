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
const flags = @import("flags.zig");
const copy_sites = @import("copy_sites.zig");

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

/// Rewrite only the slices whose every use is a pure read. A dictionary insert
/// is a write, so it disqualifies the slice here: the release pipeline borrows a
/// key and re-inserts a materialized one, but a build-mode-independent rewrite
/// keeps the copy instead (its probe/key pairing is the release pass's).
pub fn rewriteReadOnly(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function) std.mem.Allocator.Error!u32 {
    return rewriteStrict(arena, module, f, null);
}

fn rewriteStrict(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function, requests: ?*std.ArrayList(u32)) std.mem.Allocator.Error!u32 {
    return rewriteRecordingMode(arena, module, f, requests, true);
}

fn rewriteRecording(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function, requests: ?*std.ArrayList(u32)) std.mem.Allocator.Error!u32 {
    return rewriteRecordingMode(arena, module, f, requests, false);
}

fn rewriteRecordingMode(arena: std.mem.Allocator, module: *ir.Module, f: *ir.Function, requests: ?*std.ArrayList(u32), strict: bool) std.mem.Allocator.Error!u32 {
    var changed: u32 = 0;
    const count = f.insts.items.len;
    var copies: u32 = 0;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        // An explicit snapshot used solely for reads can borrow under the same
        // complete-use and parent-stability proof as a slice. Inserts still
        // construct an independent key on their miss path below.
        if (count <= 4096 and copies < 32 and inst.ty == .str) {
            if (@import("inline_snapshot.zig").source(module, f, inst)) |source| {
                copies += 1;
                const ref: ir.Ref = @fromBackingInt(@intCast(index));
                if (!readsOnly(f, module, ref, strict) or try updated(arena, f, module, source)) continue;
                const zero: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
                try f.insts.append(arena, .{ .op = .iconst, .ty = .u64 });
                const len: ir.Ref = @fromBackingInt(@intCast(f.insts.items.len));
                try f.insts.append(arena, .{ .op = .str_len, .ty = .u64, .a = source, .span = inst.span });
                try before(arena, f, ref, zero);
                try before(arena, f, ref, len);
                const start: u32 = @intCast(f.extra.items.len);
                try f.extra.append(arena, len);
                f.insts.items[index] = .{ .op = .str_view_of, .ty = .str_view, .a = source, .b = zero, .data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack(), .span = inst.span };
                // The snapshot's key materialization stands for the copy it replaces: its mark carries over.
                try rewriteUsesRecording(arena, f, module, ref, inst.data & flags.written_copy, requests);
                changed += 1;
                continue;
            }
        }
        // The owned copy of a bytes view (`myl_core_view_copy_bytes`) that only reads: it borrows as a text view
        // does, so `decode` and the other span forms read the view.
        const bytes_copy = inst.op == .call and isBytesViewCopy(module, inst);
        if ((inst.op == .str_from_view or bytes_copy) and readsOnly(f, module, @fromBackingInt(@intCast(index)), strict)) {
            const source = if (bytes_copy) f.operands(inst.data)[0] else inst.a;
            if (try updated(arena, f, module, f.resolve(source))) continue;
            f.insts.items[index] = .{ .op = .copy, .ty = viewTypeOf(f, source), .a = source, .data = inst.data & flags.written_copy, .span = inst.span };
            // The forwarded copy's key materialization stands for the copy it replaces: its mark carries over.
            try rewriteUsesRecording(arena, f, module, f.resolve(source), inst.data & flags.written_copy, requests);
            changed += 1;
            continue;
        }
        // A text slice the builder already borrows (`str_slice_view`, a view-marked `text[a:b]` or
        // `strings.char_slice`) gets the span rewrites of a copy that only reads it: its readers call
        // the span forms, and it allocates nothing.
        if (inst.op == .str_slice_view and inst.ty.isSpan() and !f.inst(f.resolve(inst.a)).ty.isSpan()) {
            const view_ref: ir.Ref = @fromBackingInt(@intCast(index));
            if (!readsOnly(f, module, view_ref, strict) or try updated(arena, f, module, f.resolve(inst.a))) continue;
            try rewriteUsesRecording(arena, f, module, view_ref, 0, requests);
            changed += 1;
            continue;
        }
        // An owned trim whose result only reads it (CX-4) borrows the octets it keeps, as a slice does: the call
        // becomes the borrowed form of the same trim, and its readers take the span forms. Its result borrows
        // the receiver alone (the set is read during the call), so only the receiver's stability is checked.
        const trim: ?TrimView = if (inst.op == .call) trimView(module, inst) else null;
        if (trim) |view| {
            const ref: ir.Ref = @fromBackingInt(@intCast(index));
            // A byte slice of a bytes trim that only reads is a read of the trim too (lane HC): it becomes a slice of the
            // borrowed trim.
            const sliced = !view.text;
            if (!readsOnlyMode(f, module, ref, strict, sliced) or try updated(arena, f, module, f.resolve(f.operands(inst.data)[0]))) continue;
            const callee = try trimCallee(arena, module, view);
            f.insts.items[index].a = callee;
            f.insts.items[index].ty = view.ret;
            if (requests) |events| try events.append(arena, @intCast(callee.index()));
            if (sliced) try sliceTrimView(arena, f, module, ref, requests);
            try rewriteUsesRecording(arena, f, module, ref, inst.data & flags.written_copy, requests);
            changed += 1;
            continue;
        }
        const bytes = byteSlice(f, module, inst);
        const text_bytes = textByteSlice(f, module, inst);
        if (!bytes and !text_bytes) {
            if (inst.op != .str_slice or inst.ty != .str) continue;
        }
        const ref: ir.Ref = @fromBackingInt(@intCast(index));
        const source = if (bytes) f.operands(inst.data)[0] else inst.a;
        // A view has no block to take a view of, so a slice of a view keeps its copy.
        if (f.inst(f.resolve(source)).ty.isSpan()) continue;
        if (!readsOnly(f, module, ref, strict) or try updated(arena, f, module, f.resolve(source))) continue;
        if (bytes or text_bytes) {
            const args = f.operands(inst.data);
            const start: u32 = @intCast(f.extra.items.len);
            const end = args[2];
            f.insts.items[index].a = args[0];
            f.insts.items[index].b = args[1];
            try f.extra.append(arena, end);
            f.insts.items[index].data = (ir.ExtraSlice{ .start = start, .len = 1 }).pack();
        }
        f.insts.items[index].op = if (text_bytes) .str_slice_bytes_view else .str_slice_view;
        f.insts.items[index].ty = viewTypeOf(f, source);
        try rewriteUsesRecording(arena, f, module, ref, 0, requests);
        changed += 1;
    }
    return changed;
}

/// The phase-2 byte-offset text slice: a copy call whose view form the emitter
/// produces with the same clamps and the same boundary trap.
/// Whether no operand of `inst` is a borrowed text view (C9 2b): a helper whose text arguments are spans
/// takes a view's span without a copy, and the fusions over owned operands below only admit owned text.
pub fn ownedOperands(f: *const ir.Function, inst: ir.Inst) bool {
    for (f.operands(inst.data)) |operand| if (f.inst(f.resolve(operand)).ty.isSpan()) return false;
    return true;
}

/// The view type a borrowed slice of `source` has: a bytes source borrows as `bytes_view` (C9 bytes), text as `str_view`.
fn viewTypeOf(f: *const ir.Function, source: ir.Ref) ir.Type {
    const ty = f.inst(f.resolve(source)).ty;
    return if (ty == .bytes or ty == .bytes_view) .bytes_view else .str_view;
}

/// The borrowed form of an owned trim (CX-4): the runtime symbol it becomes, its family and its view result.
const TrimView = struct { symbol: []const u8, text: bool, ret: ir.Type };

/// The trim calls a read-only result may borrow: the owned helpers and their span forms (`build.spanRedirect`).
/// Each takes the receiver, the set, the direction and the explicit flag, and returns an owned copy.
const trim_forms = [_]struct { name: []const u8, text: bool }{
    .{ .name = "myl_core_text_trim", .text = true },
    .{ .name = "myl_core_text_trim_span", .text = true },
    .{ .name = "myl_core_bytes_trim", .text = false },
    .{ .name = "myl_core_span_bytes_trim", .text = false },
};

/// The views of a borrowed trim: its receiver and its set are spans.
const trim_views: u64 = 0b11;

/// The borrowed trim of `inst` when it calls an owned trim helper with its four operands and an owned result of
/// the receiver's family; null for any other call.
fn trimView(module: *const ir.Module, inst: ir.Inst) ?TrimView {
    if (inst.a.index() >= module.functions.items.len or ir.ExtraSlice.unpack(inst.data).len != 4) return null;
    const target = module.functions.items[inst.a.index()];
    if (target.signature.linkage == .internal or target.signature.passing.hasExtras()) return null;
    for (trim_forms) |form| {
        if (!std.mem.eql(u8, target.name, form.name)) continue;
        const family: ir.Type = if (form.text) .str else .bytes;
        const params = target.signature.params;
        const operands_match = params.len == 4 and params[0] == family and params[1] == family;
        if (!operands_match or params[2] != .i32 or params[3] != .bool) return null;
        if (target.signature.ret != family) return null;
        return .{ .symbol = if (form.text) "myl_core_span_text_trim_view" else "myl_core_span_bytes_trim_view", .text = form.text, .ret = if (form.text) .str_view else .bytes_view };
    }
    return null;
}

/// The borrowed trim's declaration, added on first use: the family's operands as spans, an `i32` direction and a
/// `bool` flag, and a view result borrowed from its receiver.
fn trimCallee(arena: std.mem.Allocator, module: *ir.Module, view: TrimView) std.mem.Allocator.Error!ir.Ref {
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage == .runtime_c and function.signature.passing.eql(.{ .views = trim_views }) and function.signature.ret == view.ret and std.mem.eql(u8, function.name, view.symbol))
            return @fromBackingInt(@intCast(index));
    }
    const family: ir.Type = if (view.text) .str else .bytes;
    const params = try arena.dupe(ir.Type, &.{ family, family, .i32, .bool });
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = view.symbol, .signature = .{ .params = params, .ret = view.ret, .linkage = .runtime_c, .passing = .{ .views = trim_views }, .borrow = .{ .sources = &.{.{ .argument = 0 }} } } });
    return ref;
}

/// Whether `inst` is a borrowed byte slice of an owned bytes value: `t[a:b]` with its bounds already clamped by the builder.
fn byteSliceView(inst: ir.Inst) bool {
    return inst.op == .str_slice_view and inst.ty == .bytes_view;
}

/// Turn each byte slice of `trim`, a bytes trim that has just become a view, into the same slice of the view
/// (`myl_core_span_bytes_slice_view`, octet offsets): a `str_slice_view` needs an owned source, so the slice cannot stay one.
/// Its bounds are the builder's clamped ones, which the helper clamps again to the same values. Its readers then take the
/// span forms, as the trim's do.
fn sliceTrimView(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, trim: ir.Ref, requests: ?*std.ArrayList(u32)) std.mem.Allocator.Error!void {
    const count = f.insts.items.len;
    for (0..count) |index| {
        const inst = f.insts.items[index];
        if (!byteSliceView(inst) or f.resolve(inst.a) != trim) continue;
        const ref: ir.Ref = @fromBackingInt(@intCast(index));
        const callee = try sliceViewCallee(arena, module);
        if (requests) |events| try events.append(arena, @intCast(callee.index()));
        const end = f.operands(inst.data)[0];
        const start: u32 = @intCast(f.extra.items.len);
        try f.extra.appendSlice(arena, &.{ inst.a, inst.b, end });
        f.insts.items[index] = .{ .op = .call, .ty = .bytes_view, .a = callee, .data = (ir.ExtraSlice{ .start = start, .len = 3 }).pack(), .span = inst.span };
        try rewriteUsesRecording(arena, f, module, ref, 0, requests);
    }
}

/// The span helper that slices a bytes view by octets (`zero_rc`: one view argument, a result borrowed from it), declared on
/// first use as the trim's view is: a runtime declaration a fusion appends (`fusion_checkpoint.seed` replays only those).
fn sliceViewCallee(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!ir.Ref {
    const symbol = "myl_core_span_bytes_slice_view";
    const params = [_]ir.Type{ .bytes, .i64, .i64 };
    for (module.functions.items, 0..) |function, index| {
        const sig = function.signature;
        if (sig.linkage == .runtime_c and sig.ret == .bytes_view and std.mem.eql(ir.Type, sig.params, &params) and std.mem.eql(u8, function.name, symbol))
            return @fromBackingInt(@intCast(index));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    try module.functions.append(arena, .{ .name = symbol, .signature = .{
        .params = try arena.dupe(ir.Type, &params),
        .ret = .bytes_view,
        .linkage = .runtime_c,
        .passing = .{ .views = 1 },
        .borrow = .{ .sources = try arena.dupe(ir.BorrowSource, &.{.{ .argument = 0 }}) },
    } });
    return ref;
}

fn textByteSlice(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.ty != .str or inst.a.index() >= module.functions.items.len) return false;
    if (f.operands(inst.data).len != 3 or !ownedOperands(f, inst)) return false;
    const target = module.functions.items[inst.a.index()];
    if (target.signature.linkage == .internal or !target.signature.passing.eql(.{ .views = 1 })) return false;
    return std.mem.eql(u8, target.name, "myl_core_ir_str_slice_bytes") and std.mem.eql(ir.Type, target.signature.params, &.{ .str, .i64, .i64 });
}

fn byteSlice(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.op != .call or inst.ty != .bytes or inst.a.index() >= module.functions.items.len or f.operands(inst.data).len != 3) return false;
    const target = module.functions.items[inst.a.index()];
    if (target.signature.linkage == .internal or !target.signature.passing.eql(.{})) return false;
    return std.mem.eql(u8, target.name, "myl_core_bytes_slice") and std.mem.eql(ir.Type, target.signature.params, &.{ .bytes, .i64, .i64 });
}

/// Whether every use of `slice` is the key of a text-dictionary lookup or insert, or an
/// argument of a reading helper with a span form, and there is at least one. A forwarding
/// copy stands for the slice itself.
pub fn onlyReads(f: *const ir.Function, module: *const ir.Module, slice: ir.Ref) bool {
    return readsOnly(f, module, slice, false);
}

/// `onlyReads` with a mode: `strict` also refuses a dictionary insert, which the
/// release pipeline borrows and re-keys but a build-mode-independent rewrite
/// leaves as a copy.
fn readsOnly(f: *const ir.Function, module: *const ir.Module, slice: ir.Ref, strict: bool) bool {
    return readsOnlyMode(f, module, slice, strict, false);
}

/// `readsOnly`, where `sliced` also admits a byte slice of `slice` (`t[a:b]` of an owned bytes value, a `str_slice_view` of
/// type `bytes_view`) whose own uses only read it: once `slice` is a view, that slice is a view of the same octets
/// (`sliceTrimView`).
fn readsOnlyMode(f: *const ir.Function, module: *const ir.Module, slice: ir.Ref, strict: bool, sliced: bool) bool {
    var uses: usize = 0;
    for (f.insts.items, 0..) |inst, index| {
        if (inst.op == .copy) continue;
        const operands = f.valueOperands(inst);
        for (0..operands.len()) |at| {
            if (f.resolve(operands.get(at)) != slice) continue;
            uses += 1;
            if (sliced and at == 0 and byteSliceView(inst) and readsOnly(f, module, @fromBackingInt(@intCast(index)), strict)) continue;
            if (strict and inst.op == .dict_insert) return false;
            if (inst.op == .call) {
                // Audited span readers borrow this operand, including ordered stream writes.
                if (spanArgument(module, inst, at)) continue;
                const form = spanForm(module, inst) orelse return false;
                if (strict and !spanDeclared(module, form.span)) return false;
                continue;
            }
            // Plain print consumes text synchronously and already admits a text span.
            if (inst.op == .print and at != 0 and f.inst(slice).ty == .str) continue;
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

/// A runtime span parameter reads its exact argument without retaining an owner.
fn spanArgument(module: *const ir.Module, call: ir.Inst, at: usize) bool {
    if (call.a.index() >= module.functions.items.len) return false;
    const sig = module.functions.items[call.a.index()].signature;
    if (sig.linkage == .internal or at >= sig.params.len) return false;
    const ty = sig.params[at];
    return (ty == .str or ty == .bytes) and sig.passing.viewAt(at) and !sig.passing.takes(at);
}

/// Whether `source`, or a phi it flows into, is updated in place anywhere in `f` (a
/// consuming update, or a call that takes it over as a `mut` argument). A view keeps its
/// source live, so an update while the view is live would copy the whole source instead
/// of updating it in place: such a slice stays a copy.
pub fn updated(arena: std.mem.Allocator, f: *const ir.Function, module: *const ir.Module, source: ir.Ref) std.mem.Allocator.Error!bool {
    return ownedUpdated(arena, f, module, source);
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
        .borrow, .list_get, .list_get_field, .record_get, .union_payload, .box_get, .dict_entry_key, .dict_entry_value, .array_get, .str_view_of, .str_slice_view => inst.a,
        .call => if (module.functions.items[inst.a.index()].signature.viewSource()) |at| f.operands(inst.data)[at] else null,
        else => null,
    };
}

/// Whether the span form `symbol` is already declared, so a rewrite needs no new
/// function. A declaration mid-build would move the module's function array while
/// an analysis of it is live, which a demand-restored build must not do.
fn spanDeclared(module: *const ir.Module, symbol: []const u8) bool {
    for (module.functions.items) |function| {
        if (!std.mem.eql(u8, function.name, symbol)) continue;
        const sig = function.signature;
        if (sig.linkage == .internal or sig.ret == .void or sig.params.len > 64 or sig.passing.hasExtras()) continue;
        const all: u64 = if (sig.params.len == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(sig.params.len)) - 1;
        if (!sig.passing.eql(.{ .views = all })) continue;
        return true;
    }
    return false;
}

fn takesOwner(f: *const ir.Function, module: *const ir.Module, inst: ir.Inst, at: usize) bool {
    // A managed phi takes ownership on its incoming edge. A later copy of that
    // phi may donate storage, so its append receiver does not prove independence.
    if (inst.op == .phi) return !inst.ty.isSpan() and module.managed(inst.ty);
    if (at == 0 and inst.op.consumesOperand0()) return true;
    const signature: ?ir.Signature = switch (inst.op) {
        .call => module.functions.items[inst.a.index()].signature,
        .call_indirect => module.compound(f.inst(f.resolve(inst.a)).ty).@"fn",
        else => null,
    };
    if (signature) |sig| {
        // valueOperands includes the indirect callee before the arguments.
        const first: usize = if (inst.op == .call_indirect) 1 else 0;
        if (at < first) return false;
        return sig.passing.takes(at - first);
    }
    return switch (inst.op) {
        .list_push, .record_set, .union_make, .union_take, .record_take, .box_make, .box_take, .ret, .drop, .record_make => true,
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
    if (signature.linkage == .internal or signature.params.len > 64) return null;
    if (signature.passing.hasOwned() or signature.passing.hasConsumes() or signature.passing.hasExtras()) return null;
    for (signature.params) |param| if (param != .str and param != .bytes) return null;
    for (span_forms) |form| {
        // A call another slice already moved to the span form keeps it.
        const all: u64 = if (signature.params.len == 64) std.math.maxInt(u64) else (@as(u64, 1) << @intCast(signature.params.len)) - 1;
        const spans = signature.linkage == .runtime_c and signature.passing.views == all;
        if (!std.mem.eql(u8, callee.name, if (spans) form.span else form.text)) continue;
        if (!spans and signature.passing.views != 0) return null;
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
    if (sig.linkage != .runtime_c) return null;
    if (sig.passing.hasOwned() or sig.passing.hasConsumes() or sig.passing.hasExtras()) return null;
    const forms = [_]SpanForm{
        .{ .text = "myl_core_bytes_utf8_count", .span = "myl_core_span_utf8_count" },
        .{ .text = "myl_core_bytes_decode_text", .span = "myl_core_span_decode_text" },
    };
    for (forms, 0..) |form, i| {
        const span = std.mem.eql(u8, callee.name, form.span);
        if (!span and !std.mem.eql(u8, callee.name, form.text)) continue;
        const ret: ir.Type = if (i == 0) .i64 else .str;
        if (sig.ret != ret or sig.passing.views != @as(u64, if (span) 1 else 0)) return null;
        if (!std.mem.eql(ir.Type, sig.params, if (span) &.{.str} else &.{.bytes})) return null;
        for (module.functions.items) |decl| {
            if (!std.mem.eql(u8, decl.name, form.span)) continue;
            const candidate = decl.signature;
            if (candidate.linkage != .runtime_c or !candidate.passing.eql(.{ .views = 1 })) return null;
            if (candidate.ret != ret or !std.mem.eql(ir.Type, candidate.params, &.{.str})) return null;
        }
        return form;
    }
    return null;
}

/// The span form's declaration, added on first use: the text form's signature with every
/// parameter a span.
/// Whether `inst` calls the runtime's copy of a bytes view: one argument, a view, the bytes result.
fn isBytesViewCopy(module: *const ir.Module, inst: ir.Inst) bool {
    if (inst.a.index() >= module.functions.items.len) return false;
    const target = module.functions.items[inst.a.index()];
    return std.mem.eql(u8, target.name, "myl_core_view_copy_bytes") and inst.ty == .bytes and target.signature.params.len == 1;
}

fn spanCallee(arena: std.mem.Allocator, module: *ir.Module, text: ir.Signature, symbol: []const u8) std.mem.Allocator.Error!ir.Ref {
    var passing_modes: ir.ParameterPassing = .{};
    for (text.params, 0..) |_, index| try passing_modes.setView(arena, index);
    for (module.functions.items, 0..) |function, index| {
        if (function.signature.linkage == .runtime_c and function.signature.passing.eql(passing_modes) and std.mem.eql(u8, function.name, symbol)) return @fromBackingInt(@intCast(index));
    }
    const ref: ir.Ref = @fromBackingInt(@intCast(module.functions.items.len));
    const params = try arena.alloc(ir.Type, text.params.len);
    @memset(params, .str);
    try module.functions.append(arena, .{ .name = symbol, .signature = .{ .params = params, .ret = text.ret, .linkage = .runtime_c, .passing = passing_modes } });
    return ref;
}

/// Retype the view's copies, call each reading helper's span form, and give each insert
/// a key materialized from the view.
pub fn rewriteUses(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, view: ir.Ref, mark: u64) std.mem.Allocator.Error!void {
    return rewriteUsesRecording(arena, f, module, view, mark, null);
}

fn rewriteUsesRecording(arena: std.mem.Allocator, f: *ir.Function, module: *ir.Module, view: ir.Ref, mark: u64, requests: ?*std.ArrayList(u32)) std.mem.Allocator.Error!void {
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
        // The key's materialization is the written copy that stood for it, when the key forwards one.
        const key_mark: u64 = if (mark != 0 or copy_sites.writtenSource(f, f.operands(inst.data)[0])) flags.written_copy else 0;
        // It keeps the written copy's own position, so `cost --sites` still finds the `copy(` the source wrote (W4).
        const span = copy_sites.writtenSpan(f, f.operands(inst.data)[0], inst.span);
        try f.insts.append(arena, .{ .op = .str_from_view, .ty = .str, .a = view, .data = key_mark, .span = span });
        try before(arena, f, @fromBackingInt(@intCast(index)), key);
        const start: u32 = @intCast(f.extra.items.len);
        try f.extra.appendSlice(arena, &.{ key, value });
        f.insts.items[index].data = (ir.ExtraSlice{ .start = start, .len = 2 }).pack() | (inst.data & flags.borrowed_key_insert);
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
