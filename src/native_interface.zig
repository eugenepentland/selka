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
    /// Emit copy-on-write value semantics (`COW-UNIQUE-1`): `checks` shares a
    /// payload at every transfer the ownership analysis calls a copy and makes
    /// it unique before every in-place write; `counting` also counts every
    /// inline check, mark and pin (`COW-STATS-1`).
    cow: Cow = .off,
};
/// Which copy-on-write code a build emits.
pub const Cow = @import("cow_plan.zig").Mode;
/// Public declaration roots and exact language-schema-v1 bytes from one check.
pub const Interface = struct {
    roots: []const typed.FunctionId = &.{},
    schema: ?[]const u8 = null,
    /// The safety and accounting code the backend generates for this program.
    policy: Policy = .{},
    /// Persistent per-function unit reuse, or null to emit every unit fresh.
    reuse: ?@import("qbe_fragments.zig").Reuse = null,
};
