//! Prelude names for the binary64 unary operations the VM and native backend already run.
//! Guest code writes `sqrt(x)` rather than unwrapping a float into its `u64` bit pattern.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");

// Every spelling `operation` answers is a prelude name marked `float`, so the table and this dispatch cannot drift.
comptime {
    for (.{ "sqrt", "floor", "ceil", "trunc", "abs" }) |spelling| {
        const item = @import("prelude_names.zig").find(spelling) orelse @compileError("a float operation is missing from prelude_names: " ++ spelling);
        if (!item.float) @compileError("a float operation is not marked float in prelude_names: " ++ spelling);
    }
}

/// Binary64 unary operation named by a prelude helper, or null for every other name.
pub fn operation(name: []const u8) ?typed.UnaryOp {
    inline for (.{ "sqrt", "floor", "ceil", "trunc", "abs" }) |spelling| {
        if (std.mem.eql(u8, name, spelling)) return @field(typed.UnaryOp, "f64_" ++ spelling);
    }
    return null;
}

/// Whether `f64_<name>` consumes and answers one binary64 value rather than a
/// `u64` bit pattern. A module that declares its own `sqrt` shadows the prelude
/// helper, so this is how such a module still reaches the intrinsic.
pub fn floatwise(op: ast.UnaryOp) bool {
    return switch (op) {
        .f64_sqrt, .f64_floor, .f64_ceil, .f64_trunc, .f64_abs, .f64_neg, .f64_sin, .f64_cos => true,
        else => false,
    };
}
