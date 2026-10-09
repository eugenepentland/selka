//! Operand conventions the builder and the emitter share on top of `ir.zig`'s shapes.
const std = @import("std");
const ir = @import("ir.zig");

/// `list_get.data` of the read a `pop` starts with: a failing index is reported as the pop
/// of an empty list (`R_LIST_BOUNDS`, operation `pop`), as the old core does.
pub const pop_read: u64 = 1;
/// An indexed pop's checked read reports its index and length with operation `pop`.
pub const pop_index_read: u64 = 2;

/// The stream token of the entry adapter's error report (`print` with the `error_report` sink): the
/// emitter reports its one argument through the runtime's `myl_core_main_error_*`, which writes
/// `error: VALUE` and the error return trace to stderr (ERROR-TRACE-2).
pub const error_stream: i64 = 3;

/// The `data` bit of an `unreachable` that is a failed assertion (`assert`, `@requires`,
/// `@ensures`, `@invariant`): the low 32 bits index the message in `Module.strings` and bits
/// 32..39 hold the `typed.AssertionKind`. The emitter reports it through `myl_core_assert_fail`.
pub const assertion_trap: u64 = 1 << 63;

/// An `unreachable` reached when a refreshed iteration place changed its guarded length.
pub const iteration_trap: u64 = 1 << 61;

/// Allocation-free text-to-bytes identity; ownership treats its result as a source borrow.
pub const text_encode_symbol = "myl_core_text_encode";

/// The runtime's string comparison, declared in a module as a `runtime_c` function on first use
/// (`build.zig`) and emitted with `memory(argmem: read)` attributes (`emit_llvm.zig`).
pub const str_eq_symbol = "myl_core_str_eq";

/// The runtime's count of a string's Unicode scalars (`len(text)`).
pub const str_chars_symbol = "myl_core_str_chars";

/// Compiler-authorized scalar-index conversion, with a normalized or raw input.
pub const TextOffset = enum { normalized, raw };

/// Extern lookalikes have no authority to supply text cursor or diagnostic provenance.
pub fn textOffset(signature: ir.Signature, symbol: []const u8) ?TextOffset {
    if (signature.linkage != .runtime_c or signature.ret != .u64 or signature.owned != 0 or signature.views != 0) return null;
    if (signature.params.len != 2 or signature.params[0] != .str) return null;
    if (std.mem.eql(u8, symbol, "myl_core_str_offset") and (signature.params[1] == .i64 or signature.params[1] == .u64)) return .normalized;
    if (std.mem.eql(u8, symbol, "myl_core_str_index_offset") and signature.params[1] == .i64) return .raw;
    return null;
}

/// The runtime's string builders: concatenation, `separator.join(parts)`, and the text of an
/// integer or a boolean (`str(x)`, the parts of an f-string).
pub const str_join_symbol = "myl_core_str_join";
pub const str_from_i64_symbol = "myl_core_str_from_i64";
pub const str_from_u64_symbol = "myl_core_str_from_u64";
pub const str_from_bool_symbol = "myl_core_str_from_bool";

/// The runtime's consuming stable sort of a unique numeric, text or bytes list.
pub const list_sort_symbol = "myl_core_s2_sort_in_place";

/// Whether `symbol` names a runtime function that only reads the blocks it is passed.
pub fn readsOnly(symbol: []const u8) bool {
    if (std.mem.eql(u8, symbol, str_eq_symbol)) return true;
    // The span forms of the reading text helpers (NEW-CORE-S1-VIEW-4).
    for ([_][]const u8{ "myl_core_span_eq", "myl_core_span_chars", "myl_core_span_starts", "myl_core_span_ends", "myl_core_span_contains" }) |span| {
        if (std.mem.eql(u8, symbol, span)) return true;
    }
    return false;
}

/// Located text traps pack their explicit TrapKind in the low byte.
pub const text_trap: u64 = 1 << 58;
/// A failed dictionary read or pop reports the located missing-key trap.
pub const dict_missing_trap: u64 = 1 << 62;

/// Numeric buffer pushes format a bounded stack frame and append one fragment.
pub const buffer_append_int: u64 = 1;
/// Binary64 formatting preserves the ordinary `str(float)` spelling.
pub const buffer_append_float: u64 = 2;
/// Additive consuming buffer helper, signature `(byte_buffer, i64) -> byte_buffer`.
pub const buffer_int_symbol = "myl_core_buffer_append_i64";
/// Additive consuming buffer helper, signature `(byte_buffer, f64) -> byte_buffer`.
pub const buffer_float_symbol = "myl_core_buffer_append_f64";

/// A compiler place path detaches its parent before transferring a child slot.
pub const place_copy: u64 = 1 << 60;
/// Managed indexed reads in a nested assignment take the parent's slot owner.
pub const place_read: u64 = 1 << 60;

/// Whether an indexed read transfers its managed slot into a nested update. A `list_get_field`
/// of a path of at most four steps carries the mark next to its path (CE2-B, `xs[i].items.append(v)`).
pub fn transferredRead(inst: ir.Inst) bool {
    return switch (inst.op) {
        .list_get, .dict_entry_value => inst.data == place_read,
        .list_get_field => inst.data & 0xf <= 4 and inst.data & place_read != 0,
        else => false,
    };
}

/// A replacement paired with a transferred read must not release its old slot: a whole-element
/// store after a transferred element read, or a `list_set_field` after a transferred read of
/// the same field.
pub fn transferredSlot(function: *const ir.Function, inst: ir.Inst) bool {
    const field: ?u64 = switch (inst.op) {
        .list_set, .dict_set_value => null,
        .list_set_field => storedPath(function, inst) orelse return false,
        else => return false,
    };
    for (function.blocks.items) |block| for (block.insts.items) |ref| {
        const read = function.inst(ref);
        if (!transferredRead(read) or function.resolve(read.a) != function.resolve(inst.a) or function.resolve(read.b) != function.resolve(inst.b)) continue;
        const read_field: ?u64 = if (read.op == .list_get_field) read.data & ~place_read else null;
        if (read_field == field) return true;
    };
    return false;
}

/// The packed field path of a `list_set_field` (the `u64` constant in `extra[1]`).
fn storedPath(function: *const ir.Function, inst: ir.Inst) ?u64 {
    const operands = function.operands(inst.data);
    if (operands.len != 2) return null;
    const constant = function.inst(function.resolve(operands[1]));
    return if (constant.op == .iconst and constant.ty == .u64) constant.data else null;
}

/// Heap fill loops reserve a bounded prefix without changing their empty length.
pub const fill_capacity: u64 = 1 << 59;
/// Limit speculative initial room; longer fills continue ordinary geometric growth.
pub const fill_capacity_limit: u64 = 4096;
/// A unique counted fill uses its counter as the index within its reserved prefix.
pub const fill_push: u64 = 1 << 59;
