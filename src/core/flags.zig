//! Operand conventions the builder and the emitter share on top of `ir.zig`'s shapes.

/// `list_get.data` of the read a `pop` starts with: a failing index is reported as the pop
/// of an empty list (`R_LIST_BOUNDS`, operation `pop`), as the old core does.
pub const pop_read: u64 = 1;

/// The stream token of the entry adapter's error report (`print` with the `error_report` sink): the
/// emitter reports its one argument through the runtime's `myl_core_main_error_*`, which writes
/// `error: VALUE` and the error return trace to stderr (ERROR-TRACE-2).
pub const error_stream: i64 = 3;
