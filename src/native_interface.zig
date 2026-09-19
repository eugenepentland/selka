//! Shared frontend export snapshot consumed by independent native backends.
const typed = @import("typed.zig");
/// Public declaration roots and exact language-schema-v1 bytes from one check.
pub const Interface = struct {
    roots: []const typed.FunctionId = &.{},
    schema: ?[]const u8 = null,
    /// Emit per-instruction step-budget accounting with its position markers. A
    /// build that can never be given a runtime step ceiling turns this off.
    step_checks: bool = true,
};
