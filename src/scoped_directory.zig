//! Shared literal path validation for concrete and unused generic dir calls.
const std = @import("std");

/// An empty path names the scoped root. Every nonempty slash-separated
/// component must stay inside it; NUL never names a guest path. A backslash is a byte of a name on Linux, the one system
/// the compiler targets, so `a\b` is a folder of that name and not two components.
pub fn valid(bytes: []const u8) bool {
    if (bytes.len == 0) return true;
    if (std.mem.indexOfScalar(u8, bytes, 0) != null) return false;
    var parts = std.mem.splitScalar(u8, bytes, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}
