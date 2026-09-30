//! Focused native guest test driver acceptance without the interpreter corpus.
/// Canonical project loader exposed to native-test snapshot identity.
pub const snapshot_project = @import("project.zig");
/// Compile-time file embedding exposed to native-test snapshot capture.
pub const snapshot_embed = @import("embed.zig");
/// The compiler's language module, for the per-module build `mylang test` runs through.
pub const compiler_language = @import("compiler.zig");
test {
    _ = @import("module_build.zig");
    _ = @import("native_test_environment.zig");
    _ = @import("native_test_cases.zig");
    _ = @import("native_test_snapshot.zig");
    _ = @import("native_test_plan.zig");
    _ = @import("native_test_dependencies.zig");
    _ = @import("native_test_facts.zig");
    _ = @import("native_test_execute.zig");
    _ = @import("native_test_wire.zig");
    _ = @import("native_test_options.zig");
    _ = @import("native_test_receipts.zig");
    _ = @import("native_test_contracts.zig");
    _ = @import("native_test_graph.zig");
    _ = @import("native_test_session.zig");
    _ = @import("native_test_directory.zig");
    _ = @import("native_test_command.zig");
    _ = @import("native_bench.zig");
    _ = @import("native_bench_command.zig");
}
