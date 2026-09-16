//! Focused native guest test driver acceptance without the interpreter corpus.
test {
    _ = @import("native_test_environment.zig");
    _ = @import("native_test_cases.zig");
    _ = @import("native_test_snapshot.zig");
    _ = @import("native_test_plan.zig");
    _ = @import("native_test_dependencies.zig");
    _ = @import("native_test_execute.zig");
    _ = @import("native_test_wire.zig");
    _ = @import("native_test_options.zig");
    _ = @import("native_test_receipts.zig");
    _ = @import("native_test_contracts.zig");
    _ = @import("native_test_graph.zig");
    _ = @import("native_test_session.zig");
    _ = @import("native_test_directory.zig");
    _ = @import("native_test_command.zig");
}
