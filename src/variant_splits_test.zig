const std = @import("std");
const source = @import("source.zig");
const variant_splits = @import("variant_splits.zig");

const plain =
    \\func f(error: http.Error) -> int:
    \\    match error:
    \\        case Incomplete:
    \\            return 1
    \\        case Malformed(value=detail):
    \\            print(detail)
    \\            return 2
    \\        case Unsupported(value=_):
    \\            return 3
    \\
;

const nested =
    \\func g(r: Result[int, http.Error]) -> bool:
    \\    match r:
    \\        case Ok(_):
    \\            return True
    \\        case Err(http.Error.Malformed(value=_)):
    \\            return False
    \\        case Err(Incomplete):
    \\            return False
    \\
;

fn armAt(bytes: []const u8, head: []const u8, from: []const u8, to: []const u8) variant_splits.Arm {
    const head_start = std.mem.indexOf(u8, bytes, head).?;
    const body_start = std.mem.indexOfPos(u8, bytes, head_start, from).?;
    const body_end = std.mem.indexOfPos(u8, bytes, body_start, to).? + to.len;
    return .{
        .head = .{ .start = head_start, .end = head_start + std.mem.indexOf(u8, head, "(").? },
        .body = .{ .start = body_start, .end = body_end },
    };
}

test "a split case names the case it used to be and any other case names nothing" {
    try std.testing.expectEqualStrings("Malformed", variant_splits.formerly("http::Error", "HeaderTooLarge").?);
    try std.testing.expectEqualStrings("Malformed", variant_splits.formerly("http::Error", "BodyTooLarge").?);
    try std.testing.expectEqualStrings("Unsupported", variant_splits.formerly("http::Error", "UnsupportedVersion").?);
    try std.testing.expect(variant_splits.formerly("http::Error", "Malformed") == null);
    try std.testing.expect(variant_splits.formerly("csv.Error", "HeaderTooLarge") == null);
}

test "an arm is copied whole under the new case name and inserted after the arm" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "main.selka", plain);
    const arm = armAt(plain, "Malformed(value=detail)", "print(detail)", "return 2");
    const edit = (try variant_splits.copyArm(arena.allocator(), src, arm, "HeaderTooLarge")).?;
    try std.testing.expectEqualStrings("\n        case HeaderTooLarge(value=detail):\n            print(detail)\n            return 2", edit.text);
    const after = std.mem.indexOf(u8, plain, "return 2").? + "return 2".len;
    try std.testing.expectEqual(after, edit.span.start);
    try std.testing.expectEqual(after, edit.span.end);
}

test "a nested pattern keeps its wrapper and qualifier in the copy" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "main.selka", nested);
    const head = std.mem.indexOf(u8, nested, "Malformed").?;
    const body = std.mem.indexOf(u8, nested, "return False").?;
    const arm: variant_splits.Arm = .{ .head = .{ .start = head, .end = head + "Malformed".len }, .body = .{ .start = body, .end = body + "return False".len } };
    const edit = (try variant_splits.copyArm(arena.allocator(), src, arm, "BodyTooLarge")).?;
    try std.testing.expectEqualStrings("\n        case Err(http.Error.BodyTooLarge(value=_)):\n            return False", edit.text);
}

test "a body span that runs into the next arm gets no copy" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const src = try source.Source.init(arena.allocator(), "main.selka", plain);
    const arm = armAt(plain, "Malformed(value=detail)", "print(detail)", "return 3");
    try std.testing.expect((try variant_splits.copyArm(arena.allocator(), src, arm, "HeaderTooLarge")) == null);
}

test "a case name that does not open a case line gets no copy" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const text = "func h() -> int:\n    const x = Malformed(value=1)\n    return 2\n";
    const src = try source.Source.init(arena.allocator(), "main.selka", text);
    const arm = armAt(text, "Malformed(value=1)", "return 2", "return 2");
    try std.testing.expect((try variant_splits.copyArm(arena.allocator(), src, arm, "HeaderTooLarge")) == null);
}
