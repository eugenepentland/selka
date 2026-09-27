//! Final emitted-call veto shared by closed ownership-borrow certificates.
const std = @import("std");
/// Only cold failing calls may cross a proved raw-borrow interval.
pub fn quietCopy(text: []const u8) bool {
    if (text.len > 1024 * 1024) return false;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "call %") != null) return false;
        const at = std.mem.indexOf(u8, line, "call $") orelse continue;
        if (!std.mem.startsWith(u8, line[at..], "call $myl_qbe_fail_")) return false;
    }
    return true;
}
