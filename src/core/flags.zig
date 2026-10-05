//! Operand conventions the builder and the emitter share on top of `ir.zig`'s shapes.

/// `list_get.data` of the read a `pop` starts with: a failing index is reported as the pop
/// of an empty list (`R_LIST_BOUNDS`, operation `pop`), as the old core does.
pub const pop_read: u64 = 1;

/// The stream token of the entry adapter's error report (`print` with the `error_report` sink): the
/// emitter reports its one argument through the runtime's `myl_core_main_error_*`, which writes
/// `error: VALUE` and the error return trace to stderr (ERROR-TRACE-2).
pub const error_stream: i64 = 3;

/// The `data` bit of an `unreachable` that is a failed assertion (`assert`, `@requires`,
/// `@ensures`, `@invariant`): the low 32 bits index the message in `Module.strings` and bits
/// 32..39 hold the `typed.AssertionKind`. The emitter reports it through `myl_core_assert_fail`.
pub const assertion_trap: u64 = 1 << 63;

/// The runtime's string comparison, declared in a module as an `extern_c` function on first use
/// (`build.zig`) and emitted with `memory(argmem: read)` attributes (`emit_llvm.zig`).
pub const str_eq_symbol = "myl_core_str_eq";
