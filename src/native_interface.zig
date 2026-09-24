//! Shared frontend export snapshot consumed by independent native backends.
const typed = @import("typed.zig");
/// The safety and accounting code one emission is asked to generate. Every
/// field defaults to the fully checked, fully accounted program, so a caller
/// that names nothing gets the language's normal guarantees.
pub const Policy = struct {
    /// Drop `debug` statement lowering. Consumed before QBE emission, by the
    /// lowering step, so the backend never reads it.
    drop_debug: bool = false,
    /// Emit per-instruction step-budget accounting with its position markers. A
    /// build that can never be given a runtime step ceiling turns this off.
    step_checks: bool = true,
    /// Emit the per-call depth ceiling and its counter. A build that can never
    /// be given a runtime frame ceiling turns this off.
    frame_checks: bool = true,
    /// Emit the value guards the language's traps are made of: integer overflow
    /// on `+ - * // %` and unary `-`, narrowing integer casts, and index bounds
    /// on lists, fixed arrays, `bytes`, `str` and dictionary position reads.
    /// `mylang build --unchecked` turns this off, and with neither step nor
    /// frame accounting it also removes the per-call frame record, the
    /// stack-floor test and the position stores (`QBE-UNCHECKED-1`). Allocation
    /// failure, memory budgeting, GC roots and host-call validation are not
    /// part of this field and are always emitted.
    checks: bool = true,
};
/// Public declaration roots and exact language-schema-v1 bytes from one check.
pub const Interface = struct {
    roots: []const typed.FunctionId = &.{},
    schema: ?[]const u8 = null,
    /// The safety and accounting code the backend generates for this program.
    policy: Policy = .{},
    /// Persistent per-function unit reuse, or null to emit every unit fresh.
    reuse: ?@import("qbe_fragments.zig").Reuse = null,
};
