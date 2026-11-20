//! `check-module FILE` reports the typed holes of FILE in full and counts those of the other modules it reached on one line
//! (`Session.foldForeignHoles`); a session that did not ask for the fold, and the JSON form, list every hole. The command-line
//! half is in `test/hole_replay_cli_test.zig`.
const std = @import("std");
const language = @import("selka");
const frontend = @import("frontend.zig");

const own_text =
    \\import stub_a
    \\import stub_b
    \\
    \\
    \\public func mine() -> int:
    \\    return todo[int]()
    \\
;
const stub_a_text =
    \\public func one() -> int:
    \\    return todo[int]()
    \\
    \\
    \\public func two() -> int:
    \\    return todo[int]()
    \\
;
const stub_b_text =
    \\public func one() -> int:
    \\    return todo[int]()
    \\
;

/// Check the library `own` of a three-module skeleton project and return what the session reported.
fn report(gpa: std.mem.Allocator, arena: std.mem.Allocator, fold: bool, format: language.diagnostic_output.Format) ![]const u8 {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "own.selka", .data = own_text });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "stub_a.selka", .data = stub_a_text });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "stub_b.selka", .data = stub_b_text });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", arena);
    var session = frontend.Session.init(gpa, std.testing.io, root);
    defer session.deinit();
    session.setReportFormat(format);
    session.setHoleTraps(false);
    var text: std.ArrayList(u8) = .empty;
    try session.declare(arena, "own", &text);
    try session.mergeDeclared(gpa, &text);
    if (fold) session.foldForeignHoles();
    try std.testing.expectError(error.SourceError, session.checkLibraryMerged(arena, null, &text));
    return text.items;
}

test "a folded library check prints its own holes in full and counts the others in one line" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const text = try report(std.testing.allocator, arena.allocator(), true, .text);
    try std.testing.expect(std.mem.indexOf(u8, text, "own.selka:6:12: error[E_TYPED_HOLE]") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "stub_a.selka") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "stub_b.selka") == null);
    try std.testing.expect(std.mem.indexOf(u8, text, "note: 3 typed holes in 2 other modules (check DIR lists them)\n") != null);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, text, "E_TYPED_HOLE"));
}

test "a library check that was not asked to fold, and the json form, list every hole" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const plain = try report(std.testing.allocator, arena.allocator(), false, .text);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, plain, "E_TYPED_HOLE"));
    try std.testing.expect(std.mem.indexOf(u8, plain, "other module") == null);
    const json = try report(std.testing.allocator, arena.allocator(), true, .json);
    try std.testing.expectEqual(@as(usize, 4), std.mem.count(u8, json, "\"code\":\"E_TYPED_HOLE\""));
    try std.testing.expect(std.mem.indexOf(u8, json, "other module") == null);
}
