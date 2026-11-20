//! Test root of the edit check's developer tools.
test {
    _ = @import("zig_functions.zig");
    _ = @import("dwarf_functions.zig");
    _ = @import("coverage_map.zig");
    _ = @import("build_id.zig");
    _ = @import("reexport.zig");
    _ = @import("pipeline_test.zig");
}
