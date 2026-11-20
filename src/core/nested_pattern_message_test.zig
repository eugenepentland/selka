//! The refusal of a binding that a nested pattern lends names the pattern the author wrote, never the local the compiler keeps
//! the layers in, says how to match the layers so the payload is owned, and offers no fix (a copy in the pattern is no program).
//! Each message here is checked with the program its advice writes, which the check accepts.
const std = @import("std");
const t = std.testing;
const language = @import("selka");
const support = @import("test_support.zig");
const ownership = @import("single_owner.zig");

const fresh_result = "func next_item(i: int) -> str? fails str:\n" ++
    "    if i > 3:\n" ++
    "        fail \"too big\"\n" ++
    "    return Some(str(i))\n\n";

/// The program with a `main`, which the front end requires and the functions under test do not need.
fn withMain(a: std.mem.Allocator, source: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ source, "\nfunc main() -> int:\n    return 0\n" });
}

fn refusal(a: std.mem.Allocator, source: []const u8) !ownership.Failure {
    const unit = try support.checkSource(a, try withMain(a, source));
    try t.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try t.expectError(error.Rejected, ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure));
    return failure;
}

fn accepted(a: std.mem.Allocator, source: []const u8) !void {
    const unit = try support.checkSource(a, try withMain(a, source));
    try t.expect(unit.passed);
    var failure: ownership.Failure = .{};
    try ownership.checkWithSource(a, unit.program.?, unit.src.?, &failure);
}

/// The refusal says `message` with rule B9, offers neither a copy nor another edit, and prints no name the compiler made.
fn expectRefusal(source: []const u8, message: []const u8, recipe: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const failure = try refusal(a, source);
    try t.expectEqualStrings("E_OWN_MARKER", failure.code);
    try t.expectEqual(@as(?language.ownership_rules.Rule, .B9), failure.rule);
    try t.expectEqualStrings(message, failure.message);
    try t.expect(failure.repair == .none);
    try t.expect(failure.copy.span == null and failure.copy.borrowed.len == 0);
    try t.expect(std.mem.indexOfScalar(u8, failure.message, 0) == null);
    try t.expect(std.mem.indexOf(u8, failure.message, "pattern2") == null);
    try accepted(a, recipe);
}

test "the refusal of a binding in a result of an option names the pattern and the layers to match (W1-F-3)" {
    try expectRefusal(fresh_result ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match next_item(i):
        \\        case Ok(Some(v)):
        \\            append(mut all, v)
        \\        case Ok(None):
        \\            return 0
        \\        case Err(m):
        \\            return len(m)
        \\    return len(all)
        \\
    , "`v` is lent by the value that `case Ok(Some(v))` matched, and the list `all` needs its own value; " ++
        "to give it, match one layer at a time (`case Ok(inner):`, then `match own inner:` with `case Some(v):`, and write `own v`), " ++
        "or write `copy(v)` to keep both", fresh_result ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match next_item(i):
        \\        case Ok(inner):
        \\            match own inner:
        \\                case Some(v):
        \\                    append(mut all, own v)
        \\                case None:
        \\                    return 0
        \\        case Err(m):
        \\            return len(m)
        \\    return len(all)
        \\
    );
}

test "the refusal of a binding three layers down matches each layer with a name of its own" {
    const head = "func next_item(i: int) -> str?? fails str:\n    if i > 3:\n        fail \"too big\"\n    return Some(Some(str(i)))\n\n";
    try expectRefusal(head ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match next_item(i):
        \\        case Ok(Some(Some(v))):
        \\            append(mut all, v)
        \\        case Ok(Some(None)):
        \\            return 0
        \\        case Ok(None):
        \\            return 0
        \\        case Err(m):
        \\            return len(m)
        \\    return len(all)
        \\
    , "`v` is lent by the value that `case Ok(Some(Some(v)))` matched, and the list `all` needs its own value; " ++
        "to give it, match one layer at a time (`case Ok(inner):`, then `match own inner:` with `case Some(inner2):`, " ++
        "then `match own inner2:` with `case Some(v):`, and write `own v`), or write `copy(v)` to keep both", head ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match next_item(i):
        \\        case Ok(inner):
        \\            match own inner:
        \\                case Some(inner2):
        \\                    match own inner2:
        \\                        case Some(v):
        \\                            append(mut all, own v)
        \\                        case None:
        \\                            return 0
        \\                case None:
        \\                    return 0
        \\        case Err(m):
        \\            return len(m)
        \\    return len(all)
        \\
    );
}

test "the refusal of a binding in a case of an option names the case and its label" {
    const head = "enum Slot:\n    filled(value: str)\n    empty\n\n" ++
        "func next_item(i: int) -> Slot?:\n    if i > 3:\n        return None\n    return Some(Slot.filled(value=str(i)))\n\n";
    try expectRefusal(head ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match next_item(i):
        \\        case Some(filled(value=v)):
        \\            append(mut all, v)
        \\        case Some(empty):
        \\            return 0
        \\        case None:
        \\            return 0
        \\    return len(all)
        \\
    , "`v` is lent by the value that `case Some(filled(value=v))` matched, and the list `all` needs its own value; " ++
        "to give it, match one layer at a time (`case Some(inner):`, then `match own inner:` with `case filled(value=v):`, " ++
        "and write `own v`), or write `copy(v)` to keep both", head ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match next_item(i):
        \\        case Some(inner):
        \\            match own inner:
        \\                case filled(value=v):
        \\                    append(mut all, own v)
        \\                case empty:
        \\                    return 0
        \\        case None:
        \\            return 0
        \\    return len(all)
        \\
    );
}

test "the refusal of a binding of a matched local names the local, and the match that gives it away" {
    try expectRefusal(fresh_result ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    const r = next_item(i)
        \\    match r:
        \\        case Ok(Some(v)):
        \\            append(mut all, v)
        \\        case Ok(None):
        \\            return 0
        \\        case Err(m):
        \\            return len(m)
        \\    return len(all)
        \\
    , "`v` is lent by the local `r`, and the list `all` needs its own value; " ++
        "to give it, match one layer at a time (`match own r:` with `case Ok(inner):`, then `match own inner:` with `case Some(v):`, " ++
        "and write `own v`; that gives `r` away), or write `copy(v)` to keep both", fresh_result ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    const r = next_item(i)
        \\    match own r:
        \\        case Ok(inner):
        \\            match own inner:
        \\                case Some(v):
        \\                    append(mut all, own v)
        \\                case None:
        \\                    return 0
        \\        case Err(m):
        \\            return len(m)
        \\    return len(all)
        \\
    );
}

test "the refusal of a binding of a plain parameter's pattern offers the copy alone" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const failure = try refusal(arena.allocator(),
        \\func gather(r: str??) -> int:
        \\    mut all: str[] = []
        \\    match r:
        \\        case Some(Some(v)):
        \\            append(mut all, v)
        \\        case Some(None):
        \\            return 0
        \\        case None:
        \\            return 0
        \\    return len(all)
        \\
    );
    try t.expectEqualStrings(
        "`v` is lent by the plain parameter `r`, and the list `all` needs its own value; write `copy(v)` to keep both",
        failure.message,
    );
    try t.expect(failure.repair == .none and failure.copy.span == null);
}

test "the refusal of a pattern with two bindings names the binding that moves and binds every field to a plain name" {
    const head = "enum Pair:\n    both(left: str?, right: str?)\n    neither\n\n" ++
        "func make(i: int) -> Pair:\n    if i > 3:\n        return Pair.neither\n    return Pair.both(left=Some(str(i)), right=Some(\"r\"))\n\n";
    try expectRefusal(head ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match make(i):
        \\        case both(left=Some(a), right=Some(b)):
        \\            append(mut all, a)
        \\            append(mut all, b)
        \\        case both(left=None, right=_):
        \\            return 0
        \\        case both(left=Some(_), right=None):
        \\            return 0
        \\        case neither:
        \\            return 0
        \\    return len(all)
        \\
    , "`a` is lent by the value that `case both(left=Some(a), right=Some(b))` matched, and the list `all` needs its own value; " ++
        "to give it, match one layer at a time (`case both(left=inner, right=other):`, then `match own inner:` with `case Some(a):`, " ++
        "and write `own a`), or write `copy(a)` to keep both", head ++
        \\func gather(i: int) -> int:
        \\    mut all: str[] = []
        \\    match make(i):
        \\        case both(left=inner, right=other):
        \\            match own inner:
        \\                case Some(a):
        \\                    append(mut all, own a)
        \\                case None:
        \\                    return 0
        \\            match own other:
        \\                case Some(b):
        \\                    append(mut all, own b)
        \\                case None:
        \\                    return 0
        \\        case neither:
        \\            return 0
        \\    return len(all)
        \\
    );
}

test "the refusal of a returned binding says the layers to match and that the value is then returned as it is" {
    const message = "`v` is lent by the value that `case Ok(Some(v))` matched, and the returned value would keep it after the match ends; " ++
        "to give it, match one layer at a time (`case Ok(inner):`, then `match own inner:` with `case Some(v):`, and return `v`), " ++
        "or write `copy(v)` to keep both";
    try expectRefusal(fresh_result ++
        \\func first(i: int) -> str:
        \\    match next_item(i):
        \\        case Ok(Some(v)):
        \\            return v
        \\        case Ok(None):
        \\            return "none"
        \\        case Err(m):
        \\            return m
        \\
    , message, fresh_result ++
        \\func first(i: int) -> str:
        \\    match next_item(i):
        \\        case Ok(inner):
        \\            match own inner:
        \\                case Some(v):
        \\                    return v
        \\                case None:
        \\                    return "none"
        \\        case Err(m):
        \\            return m
        \\
    );
}
