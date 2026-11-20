//! One `selka fix` round's choice of edits: duplicates apply once, a fix that
//! collides with a chosen one waits, and a fix whose own edits overlap is
//! withheld instead of corrupting the file.
const std = @import("std");
const t = std.testing;
const plan = @import("fix_plan.zig");

const path = "/project/main.selka";

// spec-case: FIX-MIGRATION-OVERLAP-1
test "a fix round applies duplicates once, defers collisions and withholds self-overlapping fixes" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const outer: plan.Edit = .{ .path = path, .start = 10, .end = 40, .text = "(if (c) then (a) else (b))" };
    const inner: plan.Edit = .{ .path = path, .start = 20, .end = 30, .text = "(if (d) then (e) else (f))" };
    const header: plan.Edit = .{ .path = path, .start = 0, .end = 12, .text = "" };
    const elsewhere: plan.Edit = .{ .path = "/project/lib.selka", .start = 20, .end = 30, .text = "x" };
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

// spec-case: FIX-FILE-1
test "onlyIn keeps the fixes whose edits are all in one file and counts the others whole, with the files they reach" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const own: plan.Edit = .{ .path = path, .start = 1, .end = 2, .text = "mut " };
    const lib: plan.Edit = .{ .path = "/project/lib.selka", .start = 5, .end = 9, .text = "" };
    const other: plan.Edit = .{ .path = "/project/other.selka", .start = 5, .end = 9, .text = "" };
    const fixes = [_]plan.Fix{
        .{ .code = "E_MUTATION_MARKER", .edits = &.{own} },
        .{ .code = "W_UNUSED_IMPORT", .edits = &.{lib} },
        .{ .code = "E_BUILTIN_TYPE_NAME", .edits = &.{ own, lib, other } },
        .{ .code = "W_UNUSED_IMPORT", .edits = &.{lib} },
    };
    const split = try plan.onlyIn(arena.allocator(), path, &fixes);
    try t.expectEqual(@as(usize, 1), split.own.len);
    try t.expectEqualStrings("E_MUTATION_MARKER", split.own[0].code);
    try t.expectEqual(@as(usize, 3), split.elsewhere.fixes);
    try t.expectEqual(@as(usize, 2), split.elsewhere.files);
    const none = try plan.onlyIn(arena.allocator(), path, &.{});
    try t.expectEqual(@as(usize, 0), none.own.len);
    try t.expectEqual(@as(usize, 0), none.elsewhere.fixes);
}

// spec-case: FIX-MIGRATION-1
test "a rename waits while a file that does not parse imports a module it edits" {
    const declaration: plan.Edit = .{ .path = "/project/lib.selka", .start = 12, .end = 15, .text = "lib_len" };
    const call: plan.Edit = .{ .path = "/project/good.selka", .start = 40, .end = 47, .text = "lib.lib_len" };
    const rename: plan.Fix = .{ .code = "E_BUILTIN_FUNCTION_NAME", .edits = &.{ declaration, call } };
    const unrelated: plan.Fix = .{ .code = "E_REMOVED_SPELLING", .edits = &.{ declaration, call } };
    const type_rename: plan.Fix = .{ .code = "E_BUILTIN_TYPE_NAME", .edits = &.{declaration} };
    const broken: plan.Unparsed = .{ .path = "/project/broken.selka", .imports = &.{ "lib", "other" } };
    const nested: plan.Unparsed = .{ .path = "/project/app.selka", .imports = &.{"shapes.lib"} };
    const apart: plan.Unparsed = .{ .path = "/project/apart.selka", .imports = &.{ "other", "tools.more" } };
    try t.expectEqualStrings("/project/broken.selka", plan.blockedBy(rename, &.{ apart, broken }).?.file.path);
    try t.expectEqualStrings("/project/app.selka", plan.blockedBy(rename, &.{nested}).?.file.path);
    try t.expectEqualStrings("shapes.lib", plan.blockedBy(rename, &.{nested}).?.module);
    try t.expectEqualStrings("/project/broken.selka", plan.blockedBy(type_rename, &.{broken}).?.file.path);
    try t.expect(plan.blockedBy(rename, &.{apart}) == null);
    try t.expect(plan.blockedBy(rename, &.{}) == null);
    try t.expect(plan.blockedBy(unrelated, &.{broken}) == null);
    // The unparsed file itself being edited by the rename is no reason to wait: its own edits are what it gets.
    const edited: plan.Unparsed = .{ .path = "/project/lib.selka", .imports = &.{"lib"} };
    try t.expect(plan.blockedBy(.{ .code = "E_BUILTIN_FUNCTION_NAME", .edits = &.{declaration} }, &.{edited}) == null);
}

// spec-case: FIX-GENERATED-1
test "withoutFiles sets a fix aside whole when any of its edits is in a skipped file and keeps the rest in order" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const generated = "/project/detail_view.selka";
    const own: plan.Edit = .{ .path = path, .start = 1, .end = 2, .text = "mut " };
    const there: plan.Edit = .{ .path = generated, .start = 5, .end = 9, .text = "" };
    const fixes = [_]plan.Fix{
        .{ .code = "E_MUTATION_MARKER", .edits = &.{own} },
        .{ .code = "W_MATCH_IS", .edits = &.{there} },
        .{ .code = "E_BUILTIN_FUNCTION_NAME", .edits = &.{ own, there } },
        .{ .code = "W_NEEDLESS_COPY", .edits = &.{own} },
    };
    var skipped: std.StringHashMapUnmanaged(void) = .empty;
    try skipped.put(arena.allocator(), generated, {});
    const split = try plan.withoutFiles(arena.allocator(), &fixes, &skipped);
    try t.expectEqual(@as(usize, 2), split.kept.len);
    try t.expectEqualStrings("E_MUTATION_MARKER", split.kept[0].code);
    try t.expectEqualStrings("W_NEEDLESS_COPY", split.kept[1].code);
    try t.expectEqual(@as(usize, 2), split.set_aside.len);
    try t.expectEqualStrings("W_MATCH_IS", split.set_aside[0].code);
    try t.expectEqualStrings("E_BUILTIN_FUNCTION_NAME", split.set_aside[1].code);
}

// spec-case: FIX-MIGRATION-1
test "import lines a file lacks that belong at one point are merged into one sorted insertion, and the others keep their places (FR28)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const strings: plan.Edit = .{ .path = path, .start = 0, .end = 0, .text = "import strings\n\n" };
    const lists: plan.Edit = .{ .path = path, .start = 0, .end = 0, .text = "import lists\n\n" };
    const hex: plan.Edit = .{ .path = path, .start = 0, .end = 0, .text = "import hex\n\n" };
    const bytes: plan.Edit = .{ .path = path, .start = 0, .end = 0, .text = "import bytes\n\n" };
    const later: plan.Edit = .{ .path = path, .start = 40, .end = 40, .text = "import time\n" };
    const other_file: plan.Edit = .{ .path = "/project/lib.selka", .start = 0, .end = 0, .text = "import math\n\n" };
    const header: plan.Edit = .{ .path = path, .start = 0, .end = 0, .text = "# a comment\n" };
    const fixes = [_]plan.Fix{
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{strings} },
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{lists} },
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{later} },
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{hex} },
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{strings} },
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{bytes} },
        .{ .code = "E_MODULE_NOT_IMPORTED", .edits = &.{other_file} },
        .{ .code = "E_FRONTEND_SYNTAX", .edits = &.{header} },
    };
    const chosen = try plan.select(arena.allocator(), &fixes);
    // One insertion of the four lines in the order the block keeps, `import time` after them, the other file's own line, and
    // the insertion of another code at the same point still waits for the next round.
    try t.expectEqual(@as(usize, 3), chosen.chosen.len);
    try t.expectEqualStrings("import bytes\nimport hex\nimport lists\nimport strings\n\n", chosen.chosen[0].edit.text);
    try t.expectEqualStrings("import time\n", chosen.chosen[1].edit.text);
    try t.expectEqualStrings("import math\n\n", chosen.chosen[2].edit.text);
    try t.expectEqual(@as(usize, 0), chosen.withheld.len);
}

// spec-case: FIX-MIGRATION-1
test "a W_COPY_RETURNED fix waits for a round with no other fix, and several of them alone are all taken" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const result: plan.Edit = .{ .path = path, .start = 30, .end = 30, .text = " from row" };
    const place: plan.Edit = .{ .path = path, .start = 50, .end = 62, .text = "row.names" };
    const second: plan.Edit = .{ .path = "/project/lib.selka", .start = 8, .end = 8, .text = " from row" };
    const loop: plan.Edit = .{ .path = "/project/lib.selka", .start = 90, .end = 90, .text = "own " };
    const returned = [_]plan.Fix{
        .{ .code = "W_COPY_RETURNED", .edits = &.{ result, place } },
        .{ .code = "W_COPY_RETURNED", .edits = &.{second} },
    };
    // Another fix anywhere in the round, whichever file or place it is in and whether it comes before or after: none is taken.
    const with_other = [_]plan.Fix{ returned[0], .{ .code = "W_COPY_FOR_STORE", .edits = &.{loop} }, returned[1] };
    const waiting = try plan.select(arena.allocator(), &with_other);
    try t.expectEqual(@as(usize, 1), waiting.chosen.len);
    try t.expectEqualStrings("W_COPY_FOR_STORE", waiting.chosen[0].code);
    // A fix of its own that collides with a chosen one waits too, and the round still has no W_COPY_RETURNED edit.
    const colliding = [_]plan.Fix{ .{ .code = "E_OWN_MARKER", .edits = &.{result} }, .{ .code = "E_OWN_MARKER", .edits = &.{.{ .path = path, .start = 30, .end = 30, .text = "own " }} }, returned[0] };
    const collided = try plan.select(arena.allocator(), &colliding);
    try t.expectEqual(@as(usize, 1), collided.chosen.len);
    try t.expectEqualStrings("E_OWN_MARKER", collided.chosen[0].code);
    // Alone, in any number, every one is taken, with its edits, in order.
    const alone = try plan.select(arena.allocator(), &returned);
    try t.expectEqual(@as(usize, 3), alone.chosen.len);
    try t.expectEqualStrings(" from row", alone.chosen[0].edit.text);
    try t.expectEqualStrings("row.names", alone.chosen[1].edit.text);
    try t.expectEqualStrings("/project/lib.selka", alone.chosen[2].edit.path);
    // A fix withheld for overlapping itself is applied by no round, so it does not hold the W_COPY_RETURNED fix back.
    const overlapping: plan.Fix = .{ .code = "E_FRONTEND_VARIANT", .edits = &.{ result, .{ .path = path, .start = 28, .end = 40, .text = "" } } };
    const only_withheld = try plan.select(arena.allocator(), &.{ overlapping, returned[1] });
    try t.expectEqual(@as(usize, 1), only_withheld.chosen.len);
    try t.expectEqual(@as(usize, 1), only_withheld.withheld.len);
}
