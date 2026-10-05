//! Test root of the new compiler core (`zig build test-core`): unit tests of
//! each stage, then the end-to-end slice programs under `test/core`.
comptime {
    _ = @import("frontend_test.zig");
    _ = @import("build_test.zig");
    _ = @import("emit_llvm_test.zig");
    _ = @import("driver_test.zig");
    _ = @import("facts_test.zig");
    _ = @import("e2e_test.zig");
}
