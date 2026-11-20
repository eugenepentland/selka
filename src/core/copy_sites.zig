//! The copy sites of a Core body (rule C of the wave 2 plan): every instruction that duplicates
//! storage which already exists at run time. A copy site is written when `copy(value)` made it
//! (`flags.written_copy`); any other one is a hidden copy, and `verify_ir.writtenCopies` refuses
//! it under facts verification. The classification is shared by `cost --sites` and the verifier,
//! so the census and the guarantee name the same instructions.
//!
//! The one list (W4) is every `isSite` instruction plus the frame block (`block_frame`), in the
//! blocks `counted` admits. Each listed site reads one of three ways (`Reader.read`): **written**,
//! the source says `copy(...)` there; a **named operation**, an operation whose name says it makes
//! a new value (`sorted`, `+`, `.split`, `.encode`, a slice) marked it; or **implicit**, with no copy
//! on the page: a frame block, the dictionary store's copy of a borrowed key (the one documented
//! implicit copy, by the user's decision of 12 November 2026), the entry copy `old(...)` keeps for an
//! argument that is not a named place, or an unmarked copy, which the check refuses. `cost --sites` prints the reading of each row and the check counts them.
const std = @import("std");
const ir = @import("ir.zig");
const flags = @import("flags.zig");

/// How a listed copy reads on the page.
pub const Label = enum {
    /// The source says `copy(...)` at the site.
    written,
    /// An operation whose name says it makes a new value made the copy, and marked it.
    @"named operation",
    /// Nothing on the page says the copy happens.
    implicit,
};

/// Why an implicit copy has no `copy(` on the page.
pub const Implicit = enum {
    /// A frame block (RB1): the callee copies a plain parameter that a record or list of borrows holds,
    /// once per call when the caller passed a slice, and always for `bytes`. Counted, not refused (decision Q8).
    @"frame block",
    /// A dictionary or set store (`d[k] = v`, `sets.include`, `dicts.setdefault`) copies a borrowed key
    /// when it is new. Marked written, so the check accepts it.
    @"dictionary key",
    /// The entry copy of `old(...)` whose argument is not a named place, such as a call's borrowed result: the
    /// front end refuses `old(x)` of a managed place unless it is written `old(copy(x))` (W4), and keeps this copy
    /// for the other arguments. Marked written, so the check accepts it.
    @"old capture",
    /// A copy with no written mark: the check refuses it (`E_CORE_HIDDEN_COPY`).
    unwritten,
};

/// The reading of one listed site: its label and, for an implicit one, its kind.
pub const Reading = struct { label: Label, implicit: ?Implicit = null };

/// Counts of the listed sites by reading, as the check prints them under `--stats`.
pub const Census = struct {
    written: u32 = 0,
    named: u32 = 0,
    frame_blocks: u32 = 0,
    dictionary_keys: u32 = 0,
    old_captures: u32 = 0,
    unwritten: u32 = 0,

    /// Count one reading.
    pub fn add(self: *Census, reading: Reading) void {
        switch (reading.label) {
            .written => self.written += 1,
            .@"named operation" => self.named += 1,
            .implicit => switch (reading.implicit.?) {
                .@"frame block" => self.frame_blocks += 1,
                .@"dictionary key" => self.dictionary_keys += 1,
                .@"old capture" => self.old_captures += 1,
                .unwritten => self.unwritten += 1,
            },
        }
    }
};

/// Whether `inst` is in the one list of copy sites: a copy site (`isSite`) or a frame block.
pub fn listed(module: *const ir.Module, inst: ir.Inst) bool {
    return inst.op == .block_frame or isSite(module, inst);
}

/// Whether block `b` of a final body holds sites of the list: it is reachable from the entry
/// (`graph`, as the IR verifier computes it) and the build's facts (`known`, when it has any) do not
/// prove it unreachable. A block the facts prove dead never runs its copies: a release build drops it,
/// and a verify build traps on entering it.
pub fn counted(graph: []const bool, known: ?[]const bool, b: usize) bool {
    if (b >= graph.len or !graph[b]) return false;
    const facts = known orelse return true;
    return b >= facts.len or facts[b];
}

/// Reads the listed sites of one final body. `source` is the program's merged source text, which
/// `inst.span` offsets index; without it a marked copy reads as written, as it did before W4.
pub const Reader = struct {
    arena: std.mem.Allocator,
    module: *const ir.Module,
    f: *const ir.Function,
    source: ?[]const u8 = null,
    /// Per instruction, whether it is a dictionary store's copy of a borrowed key; built on first use.
    keys: ?[]bool = null,

    /// The reading of the listed site `ref`.
    pub fn read(self: *Reader, ref: ir.Ref) std.mem.Allocator.Error!Reading {
        const inst = self.f.inst(ref);
        if (inst.op == .block_frame) return .{ .label = .implicit, .implicit = .@"frame block" };
        if (!isWritten(inst)) return .{ .label = .implicit, .implicit = .unwritten };
        const text = self.source orelse return .{ .label = .written };
        const span = if (inst.span != 0) inst.span else self.f.span;
        if (span < text.len and std.mem.startsWith(u8, text[span..], "copy(")) return .{ .label = .written };
        if (span < text.len and std.mem.startsWith(u8, text[span..], "old(")) return .{ .label = .implicit, .implicit = .@"old capture" };
        if ((try self.keyCopies())[ref.index()]) return .{ .label = .implicit, .implicit = .@"dictionary key" };
        return .{ .label = .@"named operation" };
    }

    /// Mark the copies a dictionary store made of its key: the instructions with the store's own span
    /// that build the key of a `dict_insert` marked `flags.borrowed_key_insert` (the copy of a borrowed key
    /// happens on the store's missing edge, `build_dict.putKey` and `ownedDefault`). A `copy(k)` the source
    /// wrote has its own span, and a store of a consumed key has no mark.
    fn keyCopies(self: *Reader) std.mem.Allocator.Error![]bool {
        if (self.keys) |keys| return keys;
        const f = self.f;
        const keys = try self.arena.alloc(bool, f.insts.items.len);
        @memset(keys, false);
        var pending: std.ArrayList(ir.Ref) = .empty;
        defer pending.deinit(self.arena);
        for (f.blocks.items) |block| for (block.insts.items) |ref| {
            const store = f.inst(ref);
            if (store.op != .dict_insert or store.data & flags.borrowed_key_insert == 0) continue;
            const operands = f.operands(store.data);
            if (operands.len == 0) continue;
            pending.clearRetainingCapacity();
            try pending.append(self.arena, operands[0]);
            while (pending.pop()) |raw| {
                const at = f.resolve(raw);
                if (at == .none or at.index() >= keys.len or keys[at.index()]) continue;
                const part = f.inst(at);
                if (part.span != store.span) continue;
                keys[at.index()] = true;
                switch (part.op) {
                    .record_make, .phi => try pending.appendSlice(self.arena, f.operands(part.data)),
                    .union_make, .box_make => try pending.append(self.arena, part.a),
                    else => {},
                }
            }
        };
        self.keys = keys;
        return keys;
    }
};

/// Whether `inst` duplicates existing storage: the list, dictionary, buffer and text copies, a text
/// materialized from a view, a text slice that copies its octets, and a runtime helper whose name
/// says it copies (the copy helpers the runtime counts). An in-place helper, such as a list's
/// `reverse`, is not a copy.
pub fn isSite(module: *const ir.Module, inst: ir.Inst) bool {
    return switch (inst.op) {
        .list_copy, .dict_copy, .buffer_copy, .str_from_view, .str_slice => true,
        .call => calleeIsCopy(module, inst.a),
        else => false,
    };
}

/// Whether the instruction is a copy site that `copy(value)` wrote (or a named new value did).
pub fn isWritten(inst: ir.Inst) bool {
    return inst.data & flags.written_copy != 0;
}

/// Whether the value `raw` is, or forwards, a written copy: the copy the source spelled, followed
/// through the forwarding copies a pass left behind. A materialization of such a value stands for
/// that copy, so it is written too.
pub fn writtenSource(f: *const ir.Function, raw: ir.Ref) bool {
    return writtenOrigin(f, raw) != null;
}

/// The instruction that carries the written mark `raw` is or forwards (see `writtenSource`), or null.
pub fn writtenOrigin(f: *const ir.Function, raw: ir.Ref) ?ir.Ref {
    var at = raw;
    var steps: usize = 0;
    while (at != .none and steps < 16) : (steps += 1) {
        const inst = f.inst(at);
        if (isWritten(inst)) return at;
        if (inst.op != .copy) return null;
        at = inst.a;
    }
    return null;
}

/// The position a materialization of `raw` carries: the written copy's own when `raw` forwards one, so the
/// copy keeps the `copy(` its source wrote (W4), else `fallback` (the consumer's position).
pub fn writtenSpan(f: *const ir.Function, raw: ir.Ref, fallback: u32) u32 {
    const origin = writtenOrigin(f, raw) orelse return fallback;
    const span = f.inst(origin).span;
    return if (span != 0) span else fallback;
}

/// Whether `name` is the whitespace split's helper: the block form, or the span form a view receiver takes (CX2).
pub fn isWhitespaceSplit(name: []const u8) bool {
    return std.mem.eql(u8, name, "myl_core_str_split_whitespace") or std.mem.eql(u8, name, "myl_core_span_str_split_whitespace");
}

/// The short operation name a copy site reports: its op, or the runtime helper it calls.
pub fn siteName(module: *const ir.Module, inst: ir.Inst) []const u8 {
    if (inst.op != .call) return @tagName(inst.op);
    const index = inst.a.index();
    return if (index < module.functions.items.len) module.functions.items[index].name else @tagName(inst.op);
}

/// The runtime helpers that duplicate existing storage without `copy` in their names: an owned
/// bytes or text slice, the explicit-set trim, a stepped slice, and a buffer's snapshot. The census
/// counts each as a copy site; it is written only when a written copy produced it.
pub const duplicating_helpers = [_][]const u8{
    "myl_core_bytes_slice",
    "myl_core_buffer_slice",
    "myl_core_ir_str_slice_bytes",
    "myl_core_text_trim",
    "myl_core_bytes_trim",
    "myl_core_span_bytes_trim",
    "myl_core_str_slice_step",
    "myl_core_bytes_slice_step",
    "myl_core_buffer_snapshot",
    "myl_core_text_trim_span",
    "myl_core_owned_sort_keyed",
    "myl_core_owned_sort_keyed_record",
    "myl_core_str_split",
    "myl_core_buffer_split",
    "myl_core_str_split_whitespace",
    "myl_core_span_str_split_whitespace",
    "myl_core_text_encode",
    "myl_core_span_encode",
};

/// Whether the call's callee is a runtime helper that copies: its name marks a copy, or it is one of
/// `duplicating_helpers`. A declaration the compiler synthesized (no source span) may be a runtime
/// helper; a source `extern` never is.
fn calleeIsCopy(module: *const ir.Module, callee: ir.Ref) bool {
    const index = callee.index();
    if (index >= module.functions.items.len) return false;
    const function = module.functions.items[index];
    const helper = function.signature.linkage == .runtime_c or (function.signature.linkage == .extern_c and function.span == 0);
    if (!helper) return false;
    if (std.mem.indexOf(u8, function.name, "copy") != null) return true;
    for (duplicating_helpers) |name| if (std.mem.eql(u8, function.name, name)) return true;
    return false;
}
