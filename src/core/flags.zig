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

/// The `data` of an `unreachable` reached when a nested `match mut` binding's union is no longer in the binding's case
/// (FX7, `build.caseGuard`): the emitter reports `R_CORE_FACT` at the instruction's span. Equality, not a bit test.
pub const case_trap: u64 = 1 << 53;

/// The `data` of an `unreachable` that is a typed hole (`todo[T]()` checked in trap mode): the emitter
/// reports `R_TYPED_HOLE` at the instruction's span. Equality, not a bit test, so no other trap shares it.
pub const typed_hole_trap: u64 = 1 << 54;

/// The `data` bit of a `box_make` that holds borrowed contents (E1b, a lent task argument): the box owns its shell
/// and nothing else. Its operand is borrowed, not consumed; it gets no layout, so dropping the box frees the shell only.
pub const lent_box: u64 = 1 << 60;

/// The runtime's string comparison, declared in a module as a `runtime_c` function on first use
/// (`build.zig`) and emitted with `memory(argmem: read)` attributes (`emit_llvm.zig`).
pub const str_eq_symbol = "myl_core_str_eq";

/// The runtime's count of a string's Unicode scalars (`len(text)`).
pub const str_chars_symbol = "myl_core_str_chars";

/// Compiler-authorized scalar-index conversion, with a normalized or raw input.
pub const TextOffset = enum { normalized, raw };

/// Extern lookalikes have no authority to supply text cursor or diagnostic provenance.
pub fn textOffset(signature: ir.Signature, symbol: []const u8) ?TextOffset {
    if (signature.linkage != .runtime_c or signature.ret != .u64 or !signature.passing.eql(.{})) return null;
    if (signature.params.len != 2 or signature.params[0] != .str) return null;
    if (std.mem.eql(u8, symbol, "myl_core_str_offset") and (signature.params[1] == .i64 or signature.params[1] == .u64)) return .normalized;
    if (std.mem.eql(u8, symbol, "myl_core_str_index_offset") and signature.params[1] == .i64) return .raw;
    return null;
}

/// The runtime's string builders: concatenation, `separator.join(parts)`, and the text of an
/// integer or a boolean (`str(x)`, the parts of an f-string).
pub const str_join_symbol = "myl_core_str_join";
/// The join over a list view of text parts (C9 lists): the parts are read in place.
pub const str_join_view_symbol = "myl_core_str_join_view";
pub const str_from_i64_symbol = "myl_core_str_from_i64";
pub const str_from_u64_symbol = "myl_core_str_from_u64";
pub const str_from_bool_symbol = "myl_core_str_from_bool";

/// The runtime's consuming stable sort of a unique numeric, text or bytes list.
pub const list_sort_symbol = "myl_core_s2_sort_in_place";

/// Whether `symbol` names a runtime function that only reads the blocks it is passed.
pub fn readsOnly(symbol: []const u8) bool {
    if (std.mem.eql(u8, symbol, str_eq_symbol)) return true;
    // The span forms of the reading text helpers (NEW-CORE-S1-VIEW-4).
    for ([_][]const u8{ "myl_core_split_end", "myl_core_split_next", "myl_core_span_eq", "myl_core_span_chars", "myl_core_span_starts", "myl_core_span_ends", "myl_core_span_contains" }) |span| {
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
/// Consuming buffer helper behind `append_array`: `(byte_buffer, address of an inline u8 array, i64
/// array length, i64 start, i64 end) -> byte_buffer`, which copies `array[start:end]` in one step.
pub const buffer_octets_symbol = "myl_core_buffer_append_octets";
/// Additive consuming buffer helper, signature `(byte_buffer, f64) -> byte_buffer`.
pub const buffer_float_symbol = "myl_core_buffer_append_f64";

/// The `data` bit 63 of a copy that `copy(value)` writes: the source spelled the copy, or a named
/// operation whose meaning is a new value did (`sorted`, `+`). Every copy site of a Core body
/// carries it or is a hidden copy (`copy_sites.zig`, `verify_ir.writtenCopies`). An instruction
/// with an `extra` list keeps it beside the list length (`ExtraSlice.unpack` ignores it).
pub const written_copy: u64 = 1 << 63;
/// The same bit 63 on a `dict_insert`, which is no copy site: the store copied a borrowed key on its missing
/// edge (`build_dict.putKey`, `ownedDefault`), the one documented implicit copy, which `cost --sites` labels
/// "implicit (dictionary key)" (W4, `copy_sites.Reader`). The key copy itself carries `written_copy`.
pub const borrowed_key_insert: u64 = 1 << 63;
/// A compiler place path detaches its parent before transferring a child slot.
pub const place_copy: u64 = 1 << 60;
/// Managed indexed reads in a nested assignment take the parent's slot owner.
pub const place_read: u64 = 1 << 60;

/// A dictionary pop transfers the key (bit 0) or value (bit 1) before removal.
pub const dict_take_key: u64 = 1 << 56;
pub const dict_take_value: u64 = 1 << 57;
pub const dict_take_mask: u64 = dict_take_key | dict_take_value;

/// Whether an indexed read transfers its managed slot into a nested update. A `list_get_field`
/// of a path of at most four steps carries the mark next to its path (CE2-B, `xs[i].items.append(v)`).
pub fn transferredRead(inst: ir.Inst) bool {
    return switch (inst.op) {
        .list_get => inst.data == place_read,
        .dict_entry_key => inst.data == place_read or inst.data & dict_take_key != 0,
        .dict_entry_value => inst.data == place_read or inst.data & dict_take_value != 0,
        .list_get_field => inst.data & 0xf <= 4 and inst.data & place_read != 0,
        else => false,
    };
}

/// Heap fill loops reserve a bounded prefix without changing their empty length.
pub const fill_capacity: u64 = 1 << 59;
/// Speculative initial room of a counted fill whose body can trap (any body without `fill_exact`).
///
/// Why a bound at all: the reservation is made before the body runs. For `for i in range(10**13):
/// append(mut out, 100 // (i - 3))` a whole-count reservation would first ask the allocator for
/// 8 TB, and a refused allocation is the out-of-memory fatal, not a trap; the division at i = 3 would
/// never be reported. A 4096 prefix keeps that allocation small, so the body's own trap comes first.
/// The test that shows both sides is "a trap-free counted fill reserves its count once ..." in
/// `count_test.zig`: `k1b_fill_trap_late.selka` traps at index 5000, after the list has grown past the prefix. The SPEC line (NEW-CORE-FILL-S4-1)
/// states the cap without this reason; the reason is recorded here and in `lanes/k1b.md` (D3).
///
/// Cost: a counted fill whose body can trap grows by doubling past 4096 and copies its elements at
/// each doubling (the memmove in K1's baseline profile). A trap-free body does not pay it (`fill_exact`).
pub const fill_capacity_limit: u64 = 4096;
/// Marks a counted fill whose body cannot trap or call out (`or`ed into `fill_capacity`): it reserves
/// its whole count, so its pushes never grow the list. The emitter takes the whole count only while
/// count times the element stride fits; a larger count takes the speculative prefix.
pub const fill_exact: u64 = 1 << 56;
/// Whether a `list_new`'s data word names a counted fill, exact or speculative.
pub fn isFillCapacity(data: u64) bool {
    return data & fill_capacity != 0;
}
/// A unique counted fill uses its counter as the index within its reserved prefix.
pub const fill_push: u64 = 1 << 59;
