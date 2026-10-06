//! Test root of the new compiler core (`zig build test-core`): unit tests of
//! each stage, then the end-to-end slice programs under `test/core`.
comptime {
    _ = @import("frontend_test.zig");
    _ = @import("build_test.zig");
    _ = @import("emit_llvm_test.zig");
    _ = @import("driver_test.zig");
    _ = @import("facts_test.zig");
    _ = @import("vector_test.zig");
    _ = @import("e2e_test.zig");
    _ = @import("values_test.zig");
    _ = @import("verify_ir_test.zig");
    _ = @import("value_build_test.zig");
    _ = @import("value_e2e_test.zig");
    _ = @import("value_facts_test.zig");
    _ = @import("value_emit_test.zig");
    _ = @import("test_runner_test.zig");
    _ = @import("conformance_test.zig");
    _ = @import("rows_test.zig");
    _ = @import("own_test.zig");
    _ = @import("trace_test.zig");
    _ = @import("s2_ir_test.zig");
    _ = @import("iteration_test.zig");
    _ = @import("text_test.zig");
    _ = @import("function_build_test.zig");
    _ = @import("dict_test.zig");
    _ = @import("number_test.zig");
    _ = @import("s3_ir_test.zig");
    _ = @import("s3_number_test.zig");
    _ = @import("s3_numeric_test.zig");
}
