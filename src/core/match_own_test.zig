//! 2A: `match own name:` consumes a named owner, an owned local or an `own` parameter, so its payload bindings own their
//! values and `own payload.field` takes one field. The unsound neighbours stay refused: a use of the owner after the match
//! or inside an arm, a borrowed or `mut` parameter, a borrowed local, a field place, a live borrow of the owner, a move in a
//! loop of an owner declared outside it, `match mut own`, and a payload read after a field moved out of it. Guest behaviour
//! is `tests/lang/match_own.selka`.
const std = @import("std");
const language = @import("selka");
const unique = @import("single_owner.zig");
const support = @import("test_support.zig");
const report = std.debug.print;

fn refuses(backing: std.mem.Allocator, source: []const u8, expected: language.ownership_rules.Refusal, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const program = try support.checkedProgram(a, try std.mem.concat(a, u8, &.{ prelude, source }));
    try std.testing.expectError(error.Rejected, unique.check(a, program, &failure));
    try std.testing.expectEqualStrings(expected.code, failure.code);
    try std.testing.expectEqual(expected.rule, failure.rule.?);
    try std.testing.expect(language.ownership_rules.valid(.{ .code = failure.code, .rule = failure.rule.? }));
    if (std.mem.indexOf(u8, failure.message, fragment) == null) report("missing '{s}' in: {s}\n", .{ fragment, failure.message });
    try std.testing.expect(std.mem.indexOf(u8, failure.message, fragment) != null);
}

fn accepts(backing: std.mem.Allocator, source: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    var failure: unique.Failure = .{};
    const program = try support.checkedProgram(a, try std.mem.concat(a, u8, &.{ prelude, source }));
    unique.check(a, program, &failure) catch |err| {
        report("refused: {s} {s}\n", .{ failure.code, failure.message });
        return err;
    };
    try std.testing.expectEqualStrings("", failure.code);
}

const prelude =
    \\record Account:
    \\    name: str
    \\    holds: int[]
    \\
    \\enum Slot:
    \\    empty
    \\    account(value: Account)
    \\
    \\record Box:
    \\    slot: Slot
    \\
    \\enum Wrap:
    \\    missing
    \\    inner(value: Slot)
    \\
    \\func make(n: int) -> Slot:
    \\    if n == 0:
    \\        return Slot.empty
    \\    return Slot.account(value=Account(name="a", holds=[n]))
    \\
    \\
;

test "match own consumes an owned local and an own parameter, and a payload field moves out of it" {
    try accepts(std.testing.allocator,
        \\func drain(own s: Slot) -> int[]:
        \\    match own s:
        \\        case account(value=payload):
        \\            return own payload.holds
        \\        case empty:
        \\            return []
        \\
        \\func main() -> int:
        \\    const s = make(1)
        \\    match own s:
        \\        case account(value=payload):
        \\            const kept = own payload
        \\            return len(kept.holds) + len(drain(make(2)))
        \\        case empty:
        \\            return 0
        \\
    );
    try accepts(std.testing.allocator,
        \\func temporary() -> int[]:
        \\    match make(3):
        \\        case account(value=payload):
        \\            return own payload.holds
        \\        case empty:
        \\            return []
        \\
        \\func main() -> int:
        \\    return len(temporary())
        \\
    );
}

test "the owner a match own consumed is unavailable after the match and inside its arms" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const s = make(1)
        \\    match own s:
        \\        case account(value=payload):
        \\            pass
        \\        case empty:
        \\            pass
        \\    match s:
        \\        case account(value=p):
        \\            return 1
        \\        case empty:
        \\            return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 }, "'s' was moved");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const s = make(1)
        \\    match own s:
        \\        case account(value=payload):
        \\            match s:
        \\                case account(value=q):
        \\                    return 1
        \\                case empty:
        \\                    return 2
        \\        case empty:
        \\            return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 }, "'s' was moved");
}

test "match own refuses a borrowed parameter, a mut parameter and a borrowed local, offering the removal of the marker" {
    try refuses(std.testing.allocator,
        \\func f(s: Slot) -> int:
        \\    match own s:
        \\        case account(value=payload):
        \\            return len(payload.holds)
        \\        case empty:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(make(1))
        \\
    , .{ .code = "E_OWN_MARKER", .rule = .W2 }, "'s' is a borrowed parameter, so `match own` cannot consume it");
    try refuses(std.testing.allocator,
        \\func f(mut s: Slot) -> int:
        \\    match own s:
        \\        case account(value=payload):
        \\            return len(payload.holds)
        \\        case empty:
        \\            return 0
        \\
        \\func main() -> int:
        \\    mut s = make(1)
        \\    return f(mut s)
        \\
    , .{ .code = "E_OWN_MARKER", .rule = .W2 }, "write `match mut s:` to write into it");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const b = Box(slot=make(1))
        \\    const v = b.slot
        \\    match own v:
        \\        case account(value=payload):
        \\            return len(payload.holds)
        \\        case empty:
        \\            return 0
        \\
    , .{ .code = "E_OWN_MARKER", .rule = .W2 }, "'v' borrows another owner");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const w = Wrap.inner(value=make(1))
        \\    match w:
        \\        case inner(value=payload):
        \\            match own payload:
        \\                case account(..):
        \\                    return 1
        \\                case empty:
        \\                    return 2
        \\        case missing:
        \\            return 0
        \\
    , .{ .code = "E_OWN_MARKER", .rule = .W2 }, "'payload' borrows another owner");
}

test "match own refuses a field place, match mut own, a live borrow of the owner and a move in a loop" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const b = Box(slot=make(1))
        \\    match own b.slot:
        \\        case account(value=payload):
        \\            return len(payload.holds)
        \\        case empty:
        \\            return 0
        \\
    , .{ .code = "E_OWN_MARKER", .rule = .W2 }, "not a field or element place");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    mut s = make(1)
        \\    match mut own s:
        \\        case account(value=payload):
        \\            append(mut payload.holds, 3)
        \\        case empty:
        \\            pass
        \\    return 0
        \\
    , .{ .code = "E_OWN_MARKER", .rule = .W2 }, "would consume it; remove own");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const s = make(1)
        \\    const alias = s
        \\    match own s:
        \\        case account(value=payload):
        \\            pass
        \\        case empty:
        \\            pass
        \\    match alias:
        \\        case account(value=p):
        \\            return 1
        \\        case empty:
        \\            return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_OVERLAP", .rule = .R2 }, "while 'alias' borrows it");
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const s = make(1)
        \\    mut n = 0
        \\    for i in range(3):
        \\        match own s:
        \\            case account(value=payload):
        \\                n = n + 1
        \\            case empty:
        \\                pass
        \\    return n
        \\
    , .{ .code = "E_SINGLE_OWNER_LOOP", .rule = .B6 }, "moved inside a loop");
}

test "a payload a field moved out of is consumed whole" {
    try refuses(std.testing.allocator,
        \\func main() -> int:
        \\    const s = make(1)
        \\    match own s:
        \\        case account(value=payload):
        \\            const h = own payload.holds
        \\            return len(h) + len(payload.name)
        \\        case empty:
        \\            return 0
        \\
    , .{ .code = "E_SINGLE_OWNER_MOVED", .rule = .B3 }, "'payload' was moved");
}

test "a match own refusal offers the removal of the marker, which checks as a borrowing match" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{
        prelude,
        \\func f(s: Slot) -> int:
        \\    match own s:
        \\        case account(value=payload):
        \\            return len(payload.holds)
        \\        case empty:
        \\            return 0
        \\
        \\func main() -> int:
        \\    return f(make(1))
        \\
    });
    const unit = try support.checkSource(a, source);
    try std.testing.expect(unit.passed);
    var failure: unique.Failure = .{};
    try std.testing.expectError(error.Rejected, unique.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    try std.testing.expectEqualStrings("E_OWN_MARKER", failure.code);
    try std.testing.expect(failure.repair == .explicit_fix);
    const edit = failure.repair.explicit_fix[0];
    const repaired = try std.mem.concat(a, u8, &.{ source[0..edit.span.start], edit.text, source[edit.span.end..] });
    try std.testing.expect(std.mem.indexOf(u8, repaired, "    match s:\n") != null);
    const after = try support.checkSource(a, repaired);
    try std.testing.expect(after.passed);
    failure = .{};
    try unique.checkWithSource(a, after.program.?, after.src.?, &failure);
}
