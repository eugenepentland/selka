//! The removed integer bit operators. `&`, `|` and `^` now name the prelude
//! operation they spell, and each carries the edit that call takes.
const std = @import("std");

/// Stable code for the removed `&`, `|` and `^` operators on integers.
pub const code = "E_BIT_OPERATOR_REMOVED";
/// The message naming the prelude operations.
pub const message = "`&`, `|` and `^` are not operators; combine integers with `bit_and(a, b)`, `bit_or(a, b)` and `bit_xor(a, b)`";

/// The replacement text for one removed operator: the prelude call with both
/// operand texts, which keeps their source spelling.
pub fn callText(allocator: std.mem.Allocator, builtin: []const u8, left: []const u8, right: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}({s}, {s})", .{ builtin, left, right });
}
