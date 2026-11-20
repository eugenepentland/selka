//! The hooks the pinned Zig's fuzzer runtime exports, as inert definitions.
//!
//! Instrumented code references `__sanitizer_cov_*`; with these defined the linker
//! never pulls the fuzzer runtime's archive member (and with it the `runner_*`
//! symbols only the stock test runner provides) into the compiler executable. Test
//! binaries do link that runtime, through the test runner, so they must not define
//! these a second time.

/// Zig's fuzzer runtime exports this thread-local; instrumented code may reference it.
export threadlocal var __sancov_lowest_stack: usize = 0;

/// Indirect-call hook of the fuzzer runtime; the counters already say what ran.
export fn __sanitizer_cov_trace_pc_indir(callee: usize) void {
    _ = callee;
}
/// Constructor hook LLVM may call; the runtime reads the section bounds itself.
export fn __sanitizer_cov_8bit_counters_init(start: usize, end: usize) void {
    _ = start;
    _ = end;
}
/// Constructor hook LLVM may call; the runtime reads the section bounds itself.
export fn __sanitizer_cov_pcs_init(start: usize, end: usize) void {
    _ = start;
    _ = end;
}
