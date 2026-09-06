//! Shared source declarations used by independent feature tests without changing fixture bytes.
/// Buffer owner and typed acquisition/status results for authority tests.
pub const allocator_results = "buffer B: i64; result R { ok: B, err: i64 } result Status { ok: bool, err: i64 } ";
/// Scalar ok/err result used by handling and propagation tests.
pub const scalar_result = "result R { ok: i64, err: i64 } ";
