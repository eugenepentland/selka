//! Independent pure tooling tests: no compiler, guest execution or live fixtures.
test {
    _ = @import("input_probe_test.zig");
    _ = @import("fix_plan_test.zig");
    _ = @import("timings_test.zig");
    _ = @import("invalidation_test.zig");
    _ = @import("doc_coverage_test.zig");
}
