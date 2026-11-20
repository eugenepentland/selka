//! `.copy()` is a prelude function: one home for independent storage.
const std = @import("std");

/// Stable code for the removed `.copy()` method.
pub const code = "E_COPY_METHOD_REMOVED";
/// The message naming the prelude spelling.
pub const message = "`copy()` is a function now; write `copy(value)` for independent storage";
/// The message for a file that declares or binds `copy` itself, where the
/// rewrite would capture the user's name and the migration stays by hand.
pub const claimed_message = "`copy()` is a function now; this file declares or binds `copy`, so write `copy(value)` by hand";

/// The replacement text for one removed method: the prelude call over the
/// receiver's own source text.
pub fn callText(allocator: std.mem.Allocator, receiver: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "copy({s})", .{receiver});
}
