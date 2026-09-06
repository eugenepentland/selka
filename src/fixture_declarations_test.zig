//! Shared source declarations used by independent feature tests without changing fixture bytes.
/// Buffer owner and typed acquisition/status results for authority tests.
pub const allocator_results = "buffer B: i64; result R { ok: B, err: i64 } result Status { ok: bool, err: i64 } ";
/// Scalar ok/err result used by handling and propagation tests.
pub const scalar_result = "result R { ok: i64, err: i64 } ";

/// Concrete generic buffer acquisition, mutation and scalar result contracts.
pub const generic_buffer_results = "buffer B:i64;result A{ok:B,err:i64}result S{ok:bool,err:i64}result R{ok:i64,err:i64}";
