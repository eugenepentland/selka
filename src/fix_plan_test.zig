//! One `mylang fix` round's choice of edits: duplicates apply once, a fix that
//! collides with a chosen one waits, and a fix whose own edits overlap is
//! withheld instead of corrupting the file.
const std = @import("std");
const t = std.testing;
const plan = @import("fix_plan.zig");

const path = "/project/main.my";

// spec-case: FIX-MIGRATION-OVERLAP-1
test "a fix round applies duplicates once, defers collisions and withholds self-overlapping fixes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outer: plan.Edit = .{ .path = path, .start = 10, .end = 40, .text = "(if (c) then (a) else (b))" };
    const inner: plan.Edit = .{ .path = path, .start = 20, .end = 30, .text = "(if (d) then (e) else (f))" };
    const header: plan.Edit = .{ .path = path, .start = 0, .end = 12, .text = "" };
    const elsewhere: plan.Edit = .{ .path = "/project/lib.my", .start = 20, .end = 30, .text = "x" };
    const fixes = [_]plan.Fix{
        .{ .code = "E_FRONTEND_SYNTAX", .edits = &.{inner} },
        .{ .code = "E_FRONTEND_SYNTAX", .edits = &.{inner} },
        .{ .code = "E_FRONTEND_SYNTAX", .edits = &.{outer} },
        .{ .code = "E_FRONTEND_VARIANT", .edits = &.{ header, outer } },
        .{ .code = "E_REMOVED_SPELLING", .edits = &.{elsewhere} },
    };
    const chosen = try plan.select(arena.allocator(), &fixes);
    try t.expectEqual(@as(usize, 2), chosen.chosen.len);
    try t.expectEqualStrings(inner.text, chosen.chosen[0].edit.text);
    try t.expectEqualStrings("E_REMOVED_SPELLING", chosen.chosen[1].code);
    try t.expectEqual(@as(usize, 1), chosen.withheld.len);
    try t.expectEqualStrings("E_FRONTEND_VARIANT", chosen.withheld[0].code);
}
