//! The refused half of `for x in detach place:` (LOOPDETACH, `docs/value-semantics.md#setting-a-list-aside-for-a-loop`):
//! each refusal with its code and message, the trap of a place written while it was set aside, the shape the front end
//! generates for an exit (which the ownership check's rule depends on), the formatter, and `detach` as a name. The
//! accepted half is `tests/lang/loop_detach.selka`.
const std = @import("std");
const t = std.testing;
const options = @import("test_paths");
/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// The declarations every case shares: a record holding lists, a call that changes it, and a step that fails.
const head =
    \\record Entry:
    \\    name: str
    \\    expr: int
    \\
    \\
    \\record Env:
    \\    items: Entry[]
    \\    count: int = 0
    \\    rows: Entry[][]
    \\    table: dict[str, Entry[]]
    \\
    \\
    \\func touch(mut ev: Env):
    \\    ev.count += 1
    \\
    \\
    \\func step(n: int) -> int fails str:
    \\    if n > 2:
    \\        fail "step"
    \\    return n
    \\
    \\
    \\func add(n: int, mut ev: Env):
    \\    ev.count += n
    \\
;

/// Run the compiler with `args` in a fresh directory holding `name` with `text`.
fn compile(a: std.mem.Allocator, name: []const u8, text: []const u8, args: []const []const u8) !std.process.RunResult {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = name, .data = text });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const argv = try std.mem.concat(a, []const u8, &.{ &.{options.corePath()}, args });
    return std.process.run(a, t.io, .{ .argv = argv, .cwd = .{ .path = root } });
}

/// The program of `imports`, the shared declarations, `body`, and a `main`.
fn program(a: std.mem.Allocator, imports: []const u8, body: []const u8) ![]const u8 {
    return std.mem.concat(a, u8, &.{ imports, head, "\n", body, "\n\nfunc main() -> int:\n    return 0\n" });
}

/// `body` after the shared declarations is refused, first with `code`, and the message contains `fragment`.
fn expectRefused(body: []const u8, code: []const u8, fragment: []const u8) !void {
    return expectRefusedWith("", body, code, fragment);
}

/// `expectRefused` of a program that begins with `imports`.
fn expectRefusedWith(imports: []const u8, body: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try compile(a, "detach.selka", try program(a, imports, body), &.{ "check", "detach.selka", "--no-cache", "--diagnostics=json" });
    const stderr = result.stderr;
    const at = std.mem.indexOf(u8, stderr, "\"code\":\"") orelse {
        report("expected {s}, got no diagnostic:\n{s}\n", .{ code, stderr });
        return error.TestUnexpectedResult;
    };
    const rest = stderr[at + 8 ..];
    const end = std.mem.indexOfScalar(u8, rest, '"').?;
    if (!std.mem.eql(u8, rest[0..end], code) or std.mem.indexOf(u8, stderr, fragment) == null) report("expected {s} with \"{s}\", got:\n{s}\n", .{ code, fragment, stderr });
    try t.expectEqualStrings(code, rest[0..end]);
    try t.expect(std.mem.indexOf(u8, stderr, fragment) != null);
    // No refusal shows the hidden local's name, which no source can write.
    try t.expect(std.mem.indexOf(u8, stderr, "detached") == null);
}

/// `body` after the shared declarations checks without a diagnostic.
fn expectAccepted(body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try compile(a, "detach.selka", try program(a, "", body), &.{ "check", "detach.selka", "--no-cache", "--diagnostics=json" });
    if (std.mem.indexOf(u8, result.stderr, "\"code\":\"") != null) report("expected no diagnostic, got:\n{s}\n", .{result.stderr});
    try t.expect(std.mem.indexOf(u8, result.stderr, "\"code\":\"") == null);
}

const borrowed_exit = "this exit hands on a value that borrows from the loop's element or its collection";

test "a value that leaves a detach loop and borrows its element or list is refused, by name of the repair (condition 2)" {
    try expectRefused(
        \\func f(mut ev: Env) -> Entry:
        \\    for it in detach ev.items:
        \\        touch(mut ev)
        \\        return it
        \\    return Entry(name="", expr=0)
    , "E_SINGLE_OWNER_OVERLAP", borrowed_exit);
    try expectRefused(
        \\func f(mut ev: Env) -> str:
        \\    for it in detach ev.items:
        \\        touch(mut ev)
        \\        return it.name
        \\    return ""
    , "E_SINGLE_OWNER_OVERLAP", "return copy(...) of it, or return a position");
    // A failure value read from the element names the list the loop set aside as the user wrote it.
    try expectRefused(
        \\func f(mut ev: Env) -> int fails str:
        \\    for it in detach ev.items:
        \\        touch(mut ev)
        \\        fail it.name
        \\    return 1
    , "E_SINGLE_OWNER_BORROW", "the list the `detach` loop set aside from `ev.items`");
    // A `const` alias of the element is part of the loan set (condition 1): what it borrows ends at the put-back too.
    try expectRefused(
        \\func f(mut ev: Env) -> str:
        \\    for it in detach ev.items:
        \\        const name = it.name
        \\        touch(mut ev)
        \\        if len(name) > 1:
        \\            return name
        \\    return ""
    , "E_SINGLE_OWNER_OVERLAP", borrowed_exit);
    // A list a loop over the element's field borrows, returned from inside that loop.
    try expectRefused(
        \\func f(mut ev: Env) -> Entry[]:
        \\    for row in detach ev.rows:
        \\        touch(mut ev)
        \\        return row
        \\    return []
    , "E_SINGLE_OWNER_OVERLAP", borrowed_exit);
    // A copy, a scalar and a position leave.
    try expectAccepted(
        \\func f(mut ev: Env) -> str:
        \\    for it in detach ev.items:
        \\        touch(mut ev)
        \\        if it.expr > 1:
        \\            return copy(it.name)
        \\    return ""
    );
}

test "a hand-written put-back before a return inside a for loop keeps its refusal" {
    try expectRefused(
        \\func f(mut ev: Env) -> int:
        \\    const items = take(mut ev.items)
        \\    for it in items:
        \\        if it.expr > 1:
        \\            ev.items = own items
        \\            return 1
        \\    ev.items = own items
        \\    return 0
    , "E_SINGLE_OWNER_OVERLAP", "another argument or iteration borrows it");
}

test "a task or a match mut that holds the loop's element keeps its refusal at an exit (conditions 4 and 5)" {
    // The loop variable is read-only, so no `match mut` or other writable loan of an element is open across the put-back.
    try expectRefused(
        \\func f(mut ev: Env):
        \\    for it in detach ev.items:
        \\        it.expr = 3
    , "E_IMMUTABLE", "read-only");
    // A task lent the element is joined when its group's block ends, after the put-back: the exit keeps the task refusal.
    try expectRefusedWith("import parallel\n\n\n",
        \\func weigh(e: Entry) -> int:
        \\    return e.expr
        \\
        \\
        \\func f(mut ev: Env) -> int:
        \\    for it in detach ev.items:
        \\        touch(mut ev)
        \\        with parallel.group() as g:
        \\            const t = g.submit(weigh, it)
        \\            if it.expr > 1:
        \\                return 5
        \\            ev.count += t.result()
        \\    return 0
    , "E_TASK_LOAN", "lent to a task of an open task group");
}

test "a detach loop's source is a place that can be put back" {
    try expectRefused(
        \\func rows() -> int[]:
        \\    return [1]
        \\
        \\
        \\func f(mut ev: Env):
        \\    for b in detach rows():
        \\        touch(mut ev)
    , "E_ITERATION", "`detach` takes a collection out of a place");
    try expectRefused(
        \\func f(mut ev: Env):
        \\    mut i = 0
        \\    for b in detach ev.rows[i]:
        \\        touch(mut ev)
        \\        i += 1
    , "E_ITERATION", "an index in the place is a number or a name the loop cannot change");
    try expectRefused(
        \\func f(mut ev: Env):
        \\    for b in detach ev.table["a"]:
        \\        touch(mut ev)
    , "E_ITERATION", "`detach` does not reach a dictionary value");
    try expectRefused(
        \\func f(mut ev: Env):
        \\    for i, b in detach ev.items:
        \\        touch(mut ev)
    , "E_ITERATION", "a `detach` loop binds one name");
    try expectRefused(
        \\func f(ev: Env) -> int:
        \\    for b in detach ev.items:
        \\        return b.expr
        \\    return 0
    , "E_IMMUTABLE", "read-only");
}

test "a place an enclosing detach loop set aside, or one inside it, is refused" {
    try expectRefused(
        \\func f(mut ev: Env):
        \\    for a in detach ev.items:
        \\        for b in detach ev.items:
        \\            touch(mut ev)
    , "E_ITERATION", "`ev.items` is set aside by the `detach` loop around this one");
    try expectRefused(
        \\func f(mut ev: Env):
        \\    for a in detach ev.rows:
        \\        for b in detach ev.rows[0]:
        \\            touch(mut ev)
    , "E_ITERATION", "`ev.rows` is set aside by the `detach` loop around this one");
}

test "a try in a detach loop is a declaration's value or a statement" {
    const position = "in a `detach` loop, a failing `try` puts the collection back before its error leaves";
    try expectRefused(
        \\func f(mut ev: Env) -> int fails str:
        \\    for b in detach ev.items:
        \\        ev.count = try step(b.expr)
        \\    return 1
    , "E_TRY_POSITION", position);
    try expectRefused(
        \\func f(mut ev: Env) -> int fails str:
        \\    for b in detach ev.items:
        \\        add(try step(b.expr), mut ev)
        \\    return 1
    , "E_TRY_POSITION", position);
    // TRY-2: a `try` in an operand, a condition or a format string's hole is refused as one in an argument is.
    try expectRefused(
        \\func f(mut ev: Env) -> int fails str:
        \\    for b in detach ev.items:
        \\        add(1 + try step(b.expr), mut ev)
        \\    return 1
    , "E_TRY_POSITION", position);
    try expectRefused(
        \\func f(mut ev: Env) -> int fails str:
        \\    for b in detach ev.items:
        \\        if try step(b.expr) > 1:
        \\            touch(mut ev)
        \\    return 1
    , "E_TRY_POSITION", position);
    try expectRefused(
        \\func f(mut ev: Env) -> int fails str:
        \\    for b in detach ev.items:
        \\        touch(mut ev)
        \\        return try step(b.expr)
        \\    return 1
    , "E_TRY_POSITION", position);
    try expectRefused(
        \\func maybe(n: int) -> int?:
        \\    if n > 1:
        \\        return None
        \\    return Some(n)
        \\
        \\
        \\func f(mut ev: Env) -> int?:
        \\    for b in detach ev.items:
        \\        const v = try maybe(b.expr)
        \\        add(v, mut ev)
        \\    return Some(1)
    , "E_TRY_POSITION", "a `try` on an optional would leave without putting the collection back");
    try expectAccepted(
        \\func f(mut ev: Env) -> int fails str:
        \\    for b in detach ev.items:
        \\        const v = try step(b.expr)
        \\        add(v, mut ev)
        \\        try step(v)
        \\        if v > 1:
        \\            return v
        \\    return 1
    );
}

test "a place written while its collection was set aside traps at the put-back, naming the place and the loop's line" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\record Env:
        \\    items: int[]
        \\
        \\
        \\func grow(mut ev: Env):
        \\    append(mut ev.items, 9)
        \\
        \\
        \\func main() -> int:
        \\    mut ev = Env(items=[1, 2])
        \\    for item in detach ev.items:
        \\        grow(mut ev)
        \\    return len(ev.items)
        \\
    ;
    const ran = try compile(a, "grow.selka", text, &.{ "run", "grow.selka", "--no-cache" });
    try t.expect(std.mem.indexOf(u8, ran.stderr, "R_ASSERT") != null);
    try t.expect(std.mem.indexOf(u8, ran.stderr, "the `detach` loop on line 11 puts `ev.items` back, but `ev.items` was written") != null);
}

test "an exit from a detach loop holds its value, puts the collection back and leaves at once (conditions 2, 3 and 5)" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const text =
        \\record Env:
        \\    items: int[]
        \\    count: int = 0
        \\
        \\
        \\func touch(mut ev: Env):
        \\    ev.count += 1
        \\
        \\
        \\func f(mut ev: Env) -> int:
        \\    for it in detach ev.items:
        \\        touch(mut ev)
        \\        if it > 1:
        \\            return it
        \\    return 0
        \\
        \\
        \\func main() -> int:
        \\    mut ev = Env(items=[1, 2])
        \\    return f(mut ev)
        \\
    ;
    const dumped = try compile(a, "shape.selka", text, &.{ "dump-typed", "shape.selka", "f" });
    const out = dumped.stdout;
    // The value is held in `<return>` before the put-back (2); the put-back is the `exchange` and its trap check, and the
    // `return` of the held value follows it with nothing between (3); no `on fail:` clause or scope close runs after (5).
    const exit =
        \\                    initialize %6
        \\                      local : i64 %5
        \\                    block
        \\                      initialize %7
        \\                        place_exchange : List<i64> ...
        \\                      assertion the `detach` loop on line 11 puts `ev.items` back
    ;
    try t.expect(std.mem.indexOf(u8, out, exit) != null);
    try t.expect(std.mem.indexOf(u8, out, "local %6 <return>: i64") != null);
    try t.expect(std.mem.indexOf(u8, out, "local %1 ev.items (set aside by its `detach` loop): List<i64> mut owns") != null);
    try t.expect(std.mem.indexOf(u8, out, "detached") == null);
    const after = std.mem.indexOf(u8, out, exit).? + exit.len;
    const ret = std.mem.indexOfPos(u8, out, after, "                    ret\n                      local : i64 %6") orelse return error.TestUnexpectedResult;
    // Between the trap check and the `return` there is only the rest of the check's own line and its condition.
    try t.expect(std.mem.indexOf(u8, out[after..ret], "initialize") == null);
    try t.expect(std.mem.indexOf(u8, out[after..ret], "call :") == null);
}

test "the formatter keeps a detach loop, and detach stays a name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const canonical =
        \\record Env:
        \\    items: int[]
        \\
        \\
        \\func run(mut ev: Env):
        \\    for item in detach ev.items:
        \\        append(mut ev.items, item)
        \\
        \\
        \\func main() -> int:
        \\    const detach = [1, 2]
        \\    mut total = 0
        \\    for item in detach:
        \\        total += item
        \\    return total
        \\
    ;
    const kept = try compile(a, "loop.selka", canonical, &.{ "fmt", "--check", "loop.selka" });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, kept.term);
    const ran = try compile(a, "loop.selka", canonical, &.{ "run", "loop.selka", "--print-result", "--no-cache" });
    try t.expectEqualStrings("3\n", ran.stdout);
}
