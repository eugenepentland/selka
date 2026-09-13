//! Prelude names for the binary64 unary operations the VM and native backend already run.
//! Guest code writes `sqrt(x)` rather than unwrapping a float into its `u64` bit pattern.
const std = @import("std");
const typed = @import("typed.zig");

/// Binary64 unary operation named by a prelude helper, or null for every other name.
pub fn operation(name: []const u8) ?typed.UnaryOp {
    inline for (.{ "sqrt", "floor", "ceil", "trunc", "abs" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return @field(typed.UnaryOp, "f64_" ++ spelling);
    }
    return null;
}
