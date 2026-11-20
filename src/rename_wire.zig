//! The `diagnostic-v1` fields `selka rename` compares between two checks, and the declaration a shadowing refusal names (F-79).
//!
//! A refusal of `E_SHADOWING` carries a `related` note, `declared here`, at the function, constant, type or constraint its binding
//! would hide. A rename whose target is that declaration cures the refusal, so the comparison of the checks reads the note.
const std = @import("std");

/// Where a `diagnostic-v1` diagnostic or note points.
pub const Location = struct { path: []const u8 = "", bytes: ?struct { start: usize = 0, end: usize = 0 } = null };

/// A note of a diagnostic: its role and where it points.
pub const Note = struct { role: []const u8 = "", location: ?Location = null };

/// One `diagnostic-v1` line, the fields a verdict compares.
pub const Wire = struct {
    diagnostic: ?struct {
        code: []const u8 = "",
        severity: []const u8 = "",
        message: []const u8 = "",
        location: ?Location = null,
        notes: []const Note = &.{},
    } = null,
};

/// Where the declaration a shadowing refusal names is: the first `related` note that has a byte position; null when it has none.
pub fn declaredHere(notes: []const Note) ?struct { path: []const u8, start: usize } {
    for (notes) |note| {
        if (!std.mem.eql(u8, note.role, "related")) continue;
        const spot = note.location orelse continue;
        const bytes = spot.bytes orelse continue;
        return .{ .path = spot.path, .start = bytes.start };
    }
    return null;
}
