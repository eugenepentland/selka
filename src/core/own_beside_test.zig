//! FR61: an `own` marker that the checker proves beside another refusal of the same function, and the message of one it
//! still withholds. The marker's edit stands when the function as written stops at the same refusal and the moved local is
//! used nowhere else; else the message says that the repair waits for that refusal and where it is.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");

const records =
    \\record Parser:
    \\    toks: str[]
    \\    i: int
    \\
    \\record Call:
    \\    name: str
    \\    args: str[]
    \\
    \\func advance(mut p: Parser):
    \\    p.i += 1
    \\
    \\func word(mut p: Parser) -> str:
    \\    const w = copy(p.toks[p.i])
    \\    advance(mut p)
    \\    return w
    \\
    \\func main() -> int:
    \\    return 0
    \\
;

/// The loop gives `a` away and nothing reads it after; the overlap of the second loop has no repair.
const beside = records ++
    \\func parse(mut p: Parser) -> Call:
    \\    mut args: str[] = []
    \\    for i in range(0, 3):
    \\        const a = word(mut p)
    \\        append(mut args, a)
    \\    for tk in p.toks:
    \\        advance(mut p)
    \\    return Call(name="f", args=copy(args))
    \\
;

/// The same move with `a` read again after the overlap: `own a` would leave that read refused once the overlap is repaired.
const read_later = records ++
    \\func parse(mut p: Parser) -> Call:
    \\    mut args: str[] = []
    \\    for i in range(0, 3):
    \\        const a = word(mut p)
    \\        append(mut args, a)
    \\        for tk in p.toks:
    \\            advance(mut p)
    \\        p.toks[0] = a
    \\    return Call(name="f", args=copy(args))
    \\
;

/// `a` is declared before the loop that gives it away: a second turn would give it again.
const declared_outside = records ++
    \\func parse(mut p: Parser) -> Call:
    \\    mut args: str[] = []
    \\    const a = word(mut p)
    \\    for i in range(0, 3):
    \\        append(mut args, a)
    \\        for tk in p.toks:
    \\            advance(mut p)
    \\    return Call(name="f", args=copy(args))
    \\
;

fn ownershipFailure(a: std.mem.Allocator, source: []const u8, code: []const u8) !unique.Failure {
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings(code, failure.code);
    return failure;
}

/// The line of `failure` in `source`.
fn line(a: std.mem.Allocator, source: []const u8, failure: unique.Failure) !usize {
    const unit = try support.checkSource(a, source);
    return unit.src.?.locate(failure.span.start).line;
}

test "FR61 an own marker beside an overlap it cannot repair carries its edit, and written it leaves only that overlap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const marker = try ownershipFailure(a, beside, "E_OWN_MARKER");
    try std.testing.expect(marker.repair == .explicit_fix);
    try std.testing.expectEqual(@as(usize, 1), marker.repair.explicit_fix.len);
    const edit = marker.repair.explicit_fix[0];
    try std.testing.expectEqualStrings("own ", edit.text);
    try std.testing.expectEqualStrings("a", beside[marker.span.start..marker.span.end]);
    const fixed = try std.mem.concat(a, u8, &.{ beside[0..edit.span.start], edit.text, beside[edit.span.end..] });
    const left = try ownershipFailure(a, fixed, "E_SINGLE_OWNER_OVERLAP");
    // The overlap the function holds without the marker, at `advance(mut p)` of the second loop.
    try std.testing.expectEqual(@as(usize, 25), try line(a, fixed, left));
    try std.testing.expect(std.mem.indexOf(u8, marker.message, "write `own a` to give it, or `copy(a)` to keep both") != null);
    try std.testing.expect(std.mem.indexOf(u8, marker.message, "waits") == null);
}

test "FR61 a moved local read again past the overlap gets no own edit, and the message says the repair waits for the overlap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const marker = try ownershipFailure(a, read_later, "E_OWN_MARKER");
    try std.testing.expect(marker.repair == .none);
    try std.testing.expect(marker.copy.span == null);
    const wanted = "the repair waits for the error at line 25, column 21: once that is repaired, write `own a` to give it, or `copy(a)`";
    try std.testing.expect(std.mem.indexOf(u8, marker.message, wanted) != null);
}

test "FR61 a local declared outside the loop that gives it away gets no own edit beside the overlap" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const marker = try ownershipFailure(a, declared_outside, "E_OWN_MARKER");
    try std.testing.expect(marker.repair == .none);
    try std.testing.expect(std.mem.indexOf(u8, marker.message, "the repair waits for the error at line 25, column 21") != null);
}
