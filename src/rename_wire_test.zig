//! The declaration a shadowing refusal names, read from its `diagnostic-v1` line (lane FR30).
const std = @import("std");
const t = std.testing;
const rename_wire = @import("rename_wire.zig");

/// The line `selka check --diagnostics=json` prints for the site's F-79 program (a local `label` hides the function `label`).
const refusal =
    \\{"version":"diagnostic-v1","kind":"diagnostic","diagnostic":{"code":"E_SHADOWING","severity":"error","message":"binding `label` would hide the function `label`: a name is bound once where it is visible, so choose another name","location":{"path":"f.selka","start":{"line":25,"column":11},"end":{"line":25,"column":16},"bytes":{"start":717,"end":722}},"notes":[{"role":"related","message":"declared here","location":{"path":"f.selka","start":{"line":9,"column":6},"end":{"line":9,"column":11},"bytes":{"start":379,"end":384}}},{"role":"requirement","message":"rename the binding","location":{"path":"f.selka","start":{"line":25,"column":11},"end":{"line":25,"column":16},"bytes":{"start":717,"end":722}}}],"stack":{"frames":[],"omitted":0}}}
;

// spec: RENAME-CLI-20
test "RENAME-CLI-20: the refusal's related note is the declaration it names, and a diagnostic without one names none" {
    const parsed = try std.json.parseFromSlice(rename_wire.Wire, t.allocator, refusal, .{ .ignore_unknown_fields = true });
    defer parsed.deinit();
    const named = rename_wire.declaredHere(parsed.value.diagnostic.?.notes).?;
    try t.expectEqualStrings("f.selka", named.path);
    try t.expectEqual(@as(usize, 379), named.start);
    // The requirement note is not a declaration, and a note without bytes cannot be matched.
    const requirement: rename_wire.Note = .{ .role = "requirement", .location = .{ .path = "f.selka", .bytes = .{ .start = 717, .end = 722 } } };
    try t.expect(rename_wire.declaredHere(&.{requirement}) == null);
    const unplaced: rename_wire.Note = .{ .role = "related", .location = .{ .path = "f.selka" } };
    try t.expect(rename_wire.declaredHere(&.{ unplaced, requirement }) == null);
    try t.expect(rename_wire.declaredHere(&.{}) == null);
}
