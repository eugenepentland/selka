//! Independent scalar text oracles: no compiler, native build or live fixture reads.
test {
    _ = @import("number_text.zig");
    _ = @import("number_text_test.zig");
    _ = @import("format_spec_test.zig");
}
