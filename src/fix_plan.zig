//! Which published fix edits one `mylang fix` round applies. A fix is all of
//! one diagnostic's edits; a round takes every fix whose edits collide with no
//! edit already taken, leaves a colliding fix for the next round (which sees
//! the updated file), and withholds a fix whose own edits overlap one another,
//! because no order of applying them is sound (FIX-MIGRATION-OVERLAP-1).
const std = @import("std");

/// One edit a child check published, with its file resolved to an absolute path.
pub const Edit = struct { path: []const u8, start: usize, end: usize, text: []const u8 };
/// One diagnostic's fix: all of its edits apply together or not at all.
pub const Fix = struct { code: []const u8, edits: []const Edit };
/// One edit a round applies and the diagnostic code whose fix it belongs to.
pub const Planned = struct { code: []const u8, edit: Edit };
/// One round's decision: the distinct edits to apply, and the fixes withheld
/// because their own edits overlap.
pub const Plan = struct { chosen: []const Planned, withheld: []const Fix };

/// Choose one round's edits from the fixes a check published, in order. An
/// edit identical to a chosen one (the same repair reported twice, as a
/// generic function's instances do) is a duplicate, not a collision, and is
/// applied once.
pub fn select(allocator: std.mem.Allocator, fixes: []const Fix) std.mem.Allocator.Error!Plan {
    var taken: std.ArrayList(Planned) = .empty;
    var withheld: std.ArrayList(Fix) = .empty;
    for (fixes) |fix| {
        if (selfOverlapping(fix)) {
            try withheld.append(allocator, fix);
            continue;
        }
        if (collides(fix, taken.items)) continue;
        for (fix.edits) |edit| {
            const seen = for (taken.items) |other| {
                if (same(edit, other.edit)) break true;
            } else false;
            if (!seen) try taken.append(allocator, .{ .code = fix.code, .edit = edit });
        }
    }
    return .{ .chosen = taken.items, .withheld = withheld.items };
}

/// Whether two different edits of `fix` itself overlap.
fn selfOverlapping(fix: Fix) bool {
    for (fix.edits, 0..) |edit, index| for (fix.edits[index + 1 ..]) |other| {
        if (!same(edit, other) and overlaps(edit, other)) return true;
    };
    return false;
}

/// Whether any edit of `fix` overlaps a different edit already taken.
fn collides(fix: Fix, taken: []const Planned) bool {
    for (fix.edits) |edit| for (taken) |other| {
        if (!same(edit, other.edit) and overlaps(edit, other.edit)) return true;
    };
    return false;
}

fn same(a: Edit, b: Edit) bool {
    return a.start == b.start and a.end == b.end and std.mem.eql(u8, a.path, b.path) and std.mem.eql(u8, a.text, b.text);
}

/// Whether two different edits of one file touch the same bytes or the same
/// insertion point, where applying both would depend on their order.
fn overlaps(a: Edit, b: Edit) bool {
    if (!std.mem.eql(u8, a.path, b.path)) return false;
    if (a.start == b.start) return true;
    return a.start < b.end and b.start < a.end;
}
