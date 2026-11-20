//! Independent pure tooling tests: no compiler, guest execution or live fixtures.
/// The part of the compiler's language module that the command files this root compiles reach through `compiler_root`:
/// only the product's names, so this root still compiles no front end.
pub const compiler_language = struct {
    /// The product's names and helpers.
    pub const product = @import("product.zig");
};
test {
    _ = @import("docstring_examples_test.zig");
    _ = @import("release_foundations_test.zig");
    _ = @import("release_config_test.zig");
    _ = @import("input_probe_test.zig");
    _ = @import("format_difference_test.zig");
    _ = @import("fix_plan_test.zig");
    _ = @import("timings_test.zig");
    _ = @import("invalidation_test.zig");
    _ = @import("doc_coverage_test.zig");
}
