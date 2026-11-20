//! The refused half of the `@linear` rules (D-FFI-11, `docs/records-and-unions.md#linear-records`): each path a linear
//! owner can take that the checker refuses, with its code and message; the accepted half is `tests/lang/linear_records.selka`.
const std = @import("std");
const t = std.testing;
const options = @import("test_paths");
/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// The declarations every case shares: a C handle, a `@linear` record around it, its maker, its closer and a borrower.
const head =
    \\extern type Db
    \\
    \\extern func db_open(host: Host) -> Db
    \\extern func db_close(host: Host, db: Db) -> i32
    \\
    \\
    \\@linear
    \\record Conn:
    \\    db: Db
    \\    id: int = 0
    \\
    \\
    \\func open(host: Host) -> Conn:
    \\    return Conn(db=db_open(host))
    \\
    \\
    \\func close(host: Host, own conn: Conn) -> i32:
    \\    const db = own conn.db
    \\    return db_close(host, db)
    \\
    \\
    \\func use(mut conn: Conn) -> bool:
    \\    return conn.db != Db()
;

/// The diagnostics `selka check` prints for `body` after the shared declarations and an entry point.
fn checked(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    const source = try std.mem.concat(a, u8, &.{ head, "\n", body, "\n\nfunc main() -> int:\n    return 0\n" });
    try directory.dir.writeFile(t.io, .{ .sub_path = "linear.selka", .data = source });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, "linear.selka" }), "--no-cache", "--diagnostics=json" } });
    return result.stderr;
}

/// `body` is refused, first with `code`, and the message contains `fragment`.
fn expectRefused(body: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const stderr = try checked(arena.allocator(), body);
    const at = std.mem.indexOf(u8, stderr, "\"code\":\"").?;
    const rest = stderr[at + 8 ..];
    const end = std.mem.indexOfScalar(u8, rest, '"').?;
    if (!std.mem.eql(u8, rest[0..end], code)) report("expected {s}, got:\n{s}\n", .{ code, stderr });
    try t.expectEqualStrings(code, rest[0..end]);
    try t.expect(std.mem.indexOf(u8, stderr, fragment) != null);
}

test "linear records refuse an owner left at the end of its block" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "FR42 the advice for an owner that is not ended names the field forms that end it and not a discard of a list or text field" {
    const kept = "where the field is kept (`const kept = own conn.field`, `return own conn.field`); " ++
        "`_ = own conn.field` of a list or text field only reads it";
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "or end it with `own conn.field` " ++ kept);
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    _ = own conn
        \\    return 0
    , "E_LINEAR_USE", "or end it with `own value.field` where the field is kept (`const kept = own value.field`)");
}

test "linear records refuse an early return while the owner is live" {
    try expectRefused(
        \\func f(host: Host, flag: bool) -> int:
        \\    const conn = open(host)
        \\    if flag:
        \\        return 1
        \\    return int(close(host, own conn))
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "linear records refuse a fail while the owner is live" {
    try expectRefused(
        \\func f(host: Host, flag: bool) -> int fails str:
        \\    const conn = open(host)
        \\    if flag:
        \\        fail "no"
        \\    return int(close(host, own conn))
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "linear records refuse a try that propagates while the owner is live" {
    try expectRefused(
        \\func g(x: int) -> int fails str:
        \\    return x
        \\
        \\func f(host: Host) -> int fails str:
        \\    const conn = open(host)
        \\    const v = try g(1)
        \\    return int(close(host, own conn)) + v
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

/// What a refused `try` over a live `@linear` owner `conn` says (lane MSG-C, SP2-F-3): it names the `on fail:` clause and its shape.
const try_failure_text = "`@linear` owner `conn` is not consumed before this path leaves its scope: if this `try` fails the function leaves with " ++
    "`conn` still live, so end it on that exit with an `on fail:` clause written right after `conn` is declared, " ++
    "`on fail: close(own conn)` (`close` stands for the function that takes `conn` as an `own` parameter and ends it; the clause " ++
    "runs on every failure exit after it and never on the success path); or end it before this `try`: give it to an `own` " ++
    "parameter, return it, move it into another owner, or end it with `own conn.field` where the field is kept " ++
    "(`const kept = own conn.field`, `return own conn.field`); `_ = own conn.field` of a list or text field only reads it";

test "a try that would lose a live owner names the on fail clause and its shape, in a function and in a generic one" {
    try expectRefused(
        \\func g(x: int) -> int fails str:
        \\    return x
        \\
        \\func f(host: Host) -> int fails str:
        \\    const conn = open(host)
        \\    try g(1)
        \\    return int(close(host, own conn))
    , "E_LINEAR_UNCONSUMED", try_failure_text);
    try expectRefused(
        \\func g(x: int) -> int fails str:
        \\    return x
        \\
        \\func f[T](value: T, host: Host) -> int fails str:
        \\    const conn = open(host)
        \\    const v = try g(1)
        \\    return int(close(host, own conn)) + v
    , "E_LINEAR_UNCONSUMED", try_failure_text);
    // The same owner, with the clause: accepted, so the advice is the repair.
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const repaired = try checked(arena.allocator(),
        \\func g(x: int) -> int fails str:
        \\    return x
        \\
        \\func f(host: Host) -> int fails str:
        \\    const conn = open(host)
        \\    on fail: _ = close(host, own conn)
        \\    try g(1)
        \\    return int(close(host, own conn))
    );
    try t.expect(std.mem.indexOf(u8, repaired, "E_LINEAR_UNCONSUMED") == null);
}

test "the owner an option try would lose keeps the plain advice: on fail runs for a failure, not for None" {
    try expectRefused(
        \\func g(x: int) -> int?:
        \\    return Some(x)
        \\
        \\func f(host: Host) -> int?:
        \\    const conn = open(host)
        \\    const v = try g(1)
        \\    return Some(int(close(host, own conn)) + v)
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed before this path leaves its scope; give it to an `own` parameter, return it");
}

test "linear records refuse a break out of a body that owns one" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    for i in range(3):
        \\        const conn = open(host)
        \\        if i == 1:
        \\            break
        \\        _ = close(host, own conn)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "linear records refuse a continue out of a body that owns one" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    for i in range(3):
        \\        const conn = open(host)
        \\        if i == 1:
        \\            continue
        \\        _ = close(host, own conn)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "linear records refuse an owner declared before a loop and consumed inside it" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    for i in range(3):
        \\        _ = close(host, own conn)
        \\    return 0
    , "E_LINEAR_USE", "declared outside a loop");
}

test "linear records refuse an outer owner consumed inside a loop that then breaks" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    while True:
        \\        _ = close(host, own conn)
        \\        break
        \\    return 0
    , "E_LINEAR_USE", "declared outside a loop");
}

test "linear records refuse a match own arm that does not consume its binding" {
    try expectRefused(
        \\func pick(host: Host) -> Conn?:
        \\    return Some(open(host))
        \\
        \\func f(host: Host) -> int:
        \\    match own pick(host):
        \\        case Some(conn):
        \\            return 0
        \\        case None:
        \\            return 0
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "linear records refuse a branch that consumes and one that does not" {
    try expectRefused(
        \\func f(host: Host, flag: bool) -> int:
        \\    const conn = open(host)
        \\    if flag:
        \\        _ = close(host, own conn)
        \\    return 0
    , "E_LINEAR_USE", "same state");
}

test "linear records refuse a consumption inside a short-circuit operand" {
    try expectRefused(
        \\func f(host: Host, flag: bool) -> bool:
        \\    const conn = open(host)
        \\    return flag and close(host, own conn) == i32(0)
    , "E_LINEAR_USE", "same state");
}

test "linear records refuse a use after the owner was consumed" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    _ = close(host, own conn)
        \\    return int(close(host, own conn))
    , "E_LINEAR_CONSUMED", "already consumed");
}

test "linear records refuse a use after a binding moved the owner" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    const next = conn
        \\    _ = close(host, own next)
        \\    return int(close(host, own conn))
    , "E_LINEAR_CONSUMED", "already consumed");
}

test "linear records refuse an explicit discard" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    _ = own conn
        \\    return 0
    , "E_LINEAR_USE", "cannot be discarded");
}

test "linear records refuse a copy" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    const twin = copy(conn)
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", "cannot be copied");
}

test "LINEAR-LEND a plain parameter of a linear type is a read-only loan the callee reads, lends on and need not consume" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const accepted = try checked(arena.allocator(),
        \\record Holder:
        \\    conn: Conn
        \\    n: int
        \\
        \\func peek(conn: Conn) -> int:
        \\    return conn.id
        \\
        \\func twice(conn: Conn) -> int:
        \\    return peek(conn) + peek(conn)
        \\
        \\func inner(holder: Holder) -> int:
        \\    return holder.n + peek(holder.conn)
        \\
        \\func f(host: Host) -> int:
        \\    mut conn = open(host)
        \\    const a = peek(conn)
        \\    _ = use(mut conn)
        \\    const b = twice(conn)
        \\    const holder = Holder(conn=open(host), n=1)
        \\    const c = inner(holder)
        \\    _ = close(host, own holder.conn)
        \\    return a + b + c + int(close(host, own conn))
    );
    try t.expect(std.mem.indexOf(u8, accepted, "\"severity\":\"error\"") == null);
    // The caller still owns what it lent: it must consume it on every path, and cannot use it after it did.
    try expectRefused(
        \\func peek(conn: Conn) -> int:
        \\    return conn.id
        \\
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return peek(conn)
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
    try expectRefused(
        \\func peek(conn: Conn) -> int:
        \\    return conn.id
        \\
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    _ = close(host, own conn)
        \\    return peek(conn)
    , "E_LINEAR_CONSUMED", "already consumed");
}

/// `bad`'s plain parameter `conn` is a read-only loan, so `body` (its body) is refused with the loan's message.
fn expectLoanRefused(comptime body: []const u8) !void {
    try expectRefused("func peek(conn: Conn) -> int:\n    return conn.id\n\nfunc bad(host: Host, conn: Conn) -> Conn:\n" ++ body, "E_LINEAR_USE", "a plain parameter is a read-only loan of the caller's `@linear` owner");
    try expectRefused("func bad(host: Host, conn: Conn) -> Conn:\n" ++ body, "E_LINEAR_USE", "`own` takes the value");
}

test "LINEAR-LEND a plain linear parameter cannot be moved, consumed, written, replaced or lent mut" {
    try expectLoanRefused("    _ = close(host, own conn)\n    return open(host)");
    try expectLoanRefused("    return conn");
    try expectLoanRefused("    const kept = own conn\n    return kept");
    try expectLoanRefused("    const kept = conn\n    return kept");
    try expectLoanRefused("    const db = own conn.db\n    return open(host)");
    try expectLoanRefused("    _ = use(mut conn)\n    return open(host)");
    try expectLoanRefused("    conn.id = 2\n    return open(host)");
    try expectLoanRefused("    conn = open(host)\n    return open(host)");
    try expectLoanRefused("    _ = conn\n    return open(host)");
    try expectLoanRefused("    const wrapped: Conn? = Some(conn)\n    return open(host)");
}

test "LINEAR-LEND a plain linear parameter cannot be given in a fail, a constructor or a match mut" {
    try expectRefused(
        \\record Holder:
        \\    conn: Conn
        \\
        \\func bad(conn: Conn) -> Holder:
        \\    return Holder(conn=conn)
    , "E_LINEAR_USE", "a plain parameter is a read-only loan");
    try expectRefused(
        \\func bad(conn: Conn) -> int fails Conn:
        \\    fail conn
    , "E_LINEAR_USE", "a plain parameter is a read-only loan");
    try expectRefused(
        \\enum Slot:
        \\    busy(held: Conn)
        \\    idle
        \\
        \\func bad(slot: Slot):
        \\    match mut slot:
        \\        case busy(held):
        \\            _ = use(mut held)
        \\        case idle:
        \\            pass
    , "E_LINEAR_USE", "a plain parameter is a read-only loan");
}

test "LINEAR-LEND a plain linear parameter borrows only a named owner or a field of one, and not through a function value" {
    const peek = "func peek(conn: Conn) -> int:\n    return conn.id\n\n";
    try expectRefused(peek ++
        \\func f(host: Host) -> int:
        \\    return peek(open(host))
    , "E_LINEAR_USE", "a value made for the call would be dropped unconsumed");
    try expectRefused(peek ++
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return peek(own conn)
    , "E_LINEAR_USE", "written without `own`");
    try expectRefused(
        \\func maybe(conn: Conn?) -> int:
        \\    return 0
        \\
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    const n = maybe(conn)
        \\    return n + int(close(host, own conn))
    , "E_LINEAR_USE", "of the parameter's own type");
    try expectRefused(peek ++
        \\func f(host: Host) -> int:
        \\    const look = peek
        \\    const conn = open(host)
        \\    const n = look(conn)
        \\    return n + int(close(host, own conn))
    , "E_LINEAR_USE", "a call through a function value cannot lend");
}

/// The callees the same-call cases share: each takes one `Conn` plain beside one given `own` or `mut`.
const same_call =
    \\record Box:
    \\    conn: Conn
    \\    n: int = 0
    \\
    \\func look_close(host: Host, a: Conn, own b: Conn) -> int:
    \\    return a.id + int(close(host, own b))
    \\
    \\func close_look(host: Host, own b: Conn, a: Conn) -> int:
    \\    return a.id + int(close(host, own b))
    \\
    \\func look_take(host: Host, a: Conn, own b: Box) -> int:
    \\    return a.id + int(close(host, own b.conn))
    \\
    \\func look_bump(a: Conn, mut b: Conn) -> int:
    \\    b.id = b.id + 1
    \\    return a.id
    \\
    \\func bump_look(mut b: Conn, a: Conn) -> int:
    \\    b.id = b.id + 1
    \\    return a.id
    \\
    \\func look_bump_box(a: Conn, mut b: Box) -> int:
    \\    b.n = b.n + 1
    \\    return a.id
    \\
    \\func look_both(a: Conn, b: Conn) -> int:
    \\    return a.id + b.id
    \\
;

/// `body` beside the same-call callees is refused because a loan and an `own` or `mut` of the same owner share one call.
fn expectOverlapRefused(comptime body: []const u8) !void {
    try expectRefused(same_call ++ body, "E_LINEAR_USE", "loan of a `@linear` owner lasts for the whole call");
}

test "LINEAR-LEND a loan lasts for the whole call: the same call cannot give the owner own" {
    try expectOverlapRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return look_close(host, conn, own conn)
    );
    // In the other order the `own` is checked first, so the loan reads an owner already given away.
    try expectRefused(same_call ++
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return close_look(host, own conn, conn)
    , "E_LINEAR_CONSUMED", "already consumed");
}

test "LINEAR-LEND a loan of a field cannot share a call with the own of the record that holds it" {
    try expectOverlapRefused(
        \\func f(host: Host) -> int:
        \\    const box = Box(conn=open(host))
        \\    return look_take(host, box.conn, own box)
    );
}

test "LINEAR-LEND a loan cannot share a call with a mut lend of the same owner, in either order" {
    try expectOverlapRefused(
        \\func f(host: Host) -> int:
        \\    mut conn = open(host)
        \\    const n = look_bump(conn, mut conn)
        \\    return n + int(close(host, own conn))
    );
    try expectOverlapRefused(
        \\func f(host: Host) -> int:
        \\    mut conn = open(host)
        \\    const n = bump_look(mut conn, conn)
        \\    return n + int(close(host, own conn))
    );
    try expectOverlapRefused(
        \\func f(host: Host) -> int:
        \\    mut box = Box(conn=open(host))
        \\    const n = look_bump_box(box.conn, mut box)
        \\    return n + int(close(host, own box.conn))
    );
}

test "LINEAR-LEND two loans of the same owner share a call" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const accepted = try checked(arena.allocator(), same_call ++
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    const n = look_both(conn, conn)
        \\    return n + int(close(host, own conn))
    );
    try t.expect(std.mem.indexOf(u8, accepted, "\"severity\":\"error\"") == null);
}

test "linear records refuse a mut parameter given away" {
    try expectRefused(
        \\func bad(host: Host, mut conn: Conn) -> int:
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", "lends its `@linear` owner");
}

test "linear records refuse a mut parameter ended by a field read" {
    try expectRefused(
        \\func bad(host: Host, mut conn: Conn) -> int:
        \\    const db = own conn.db
        \\    return 0
    , "E_LINEAR_USE", "lends its `@linear` owner");
}

test "linear records refuse a bare owner given to an own parameter" {
    try expectRefused(
        \\func f(host: Host) -> int:
        \\    const conn = open(host)
        \\    return int(close(host, conn))
    , "E_LINEAR_USE", "moves only with `own`");
}

test "linear records refuse take of a linear field" {
    try expectRefused(
        \\record Pair:
        \\    left: Conn
        \\    right: int
        \\
        \\func f(host: Host) -> int:
        \\    mut pair = Pair(left=open(host), right=1)
        \\    const c = take(mut pair.left)
        \\    _ = close(host, own c)
        \\    return int(close(host, own pair.left))
    , "E_TAKE_TYPE", "take and exchange");
}

test "linear records refuse exchange of a linear field" {
    try expectRefused(
        \\record Pair:
        \\    left: Conn
        \\    right: int
        \\
        \\func f(host: Host) -> int:
        \\    mut pair = Pair(left=open(host), right=1)
        \\    const c = exchange(mut pair.left, open(host))
        \\    _ = close(host, own c)
        \\    return int(close(host, own pair.left))
    , "E_TAKE_TYPE", "take and exchange");
}

test "linear records refuse a list of linear values" {
    try expectRefused(
        \\func f() -> int:
        \\    mut xs: Conn[] = []
        \\    return len(xs)
    , "E_LINEAR_USE", "cannot hold a `@linear` value");
}

test "linear records refuse a dictionary of linear values" {
    try expectRefused(
        \\func f() -> int:
        \\    mut d: dict[str, Conn] = {}
        \\    return len(d)
    , "E_LINEAR_USE", "cannot hold a `@linear` value");
}

// spec-case: LINEAR-RECORDS-1
test "the refusal of a container of linear values points at the type that names the container" {
    // The body's second line is `    mut xs: Conn[] = []`: the type starts in column 13.
    const line = std.mem.count(u8, head, "\n") + 3;
    const at = try std.fmt.allocPrint(t.allocator, "\"start\":{{\"line\":{d},\"column\":13}}", .{line});
    defer t.allocator.free(at);
    try expectRefused(
        \\func f() -> int:
        \\    mut xs: Conn[] = []
        \\    return len(xs)
    , "E_LINEAR_USE", at);
}

test "linear records refuse a generic function instantiated with a linear type" {
    try expectRefused(
        \\func id[T](own x: T) -> T:
        \\    return x
        \\
        \\func f(host: Host) -> int:
        \\    const conn = id(open(host))
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", "generic function");
}

test "linear records refuse a function that returns one and leaks it on its error path" {
    try expectRefused(
        \\func open_checked(host: Host) -> Conn fails str:
        \\    const conn = open(host)
        \\    if conn.db == Db():
        \\        fail "no database"
        \\    return conn
    , "E_LINEAR_UNCONSUMED", "`conn` is not consumed");
}

test "linear records refuse a write of a linear field, which would end the owner it replaces" {
    try expectRefused(
        \\record Pair:
        \\    left: Conn
        \\    right: int
        \\
        \\func f(host: Host) -> int:
        \\    mut pair = Pair(left=open(host), right=1)
        \\    pair.left = open(host)
        \\    return int(close(host, own pair.left))
    , "E_LINEAR_USE", "would end the `@linear` owner it replaces");
}

test "linear records refuse a field read that would copy a linear field out of its holder" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const pair = pair_of(host)
        \\    const c = pair.left
        \\    _ = close(host, own c)
        \\    const d = own pair.left
        \\    return int(close(host, own d))
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse a nested field read of a linear field" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const o = Outer(inner=pair_of(host), n=0)
        \\    const c = o.inner.left
        \\    _ = close(host, own c)
        \\    return int(close(host, own o.inner.left))
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse a field read through an alias of an alias" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const pair = pair_of(host)
        \\    const q = own pair
        \\    const r = own q
        \\    const c = r.left
        \\    return int(close(host, own c))
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse a linear field projected out of a call result" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const c = pair_of(host).left
        \\    return int(close(host, own c))
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse a plain field read out of a linear call result, which would drop it" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    return pair_of(host).right
    , "E_LINEAR_USE", "bind a `@linear` value to a name");
}

test "linear records refuse a projection inside a loop" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const pair = pair_of(host)
        \\    for i in range(2):
        \\        const c = pair.left
        \\        _ = close(host, own c)
        \\    return int(close(host, own pair.left))
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse a linear field given to an own parameter without own" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const pair = pair_of(host)
        \\    return int(close(host, pair.left))
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse own of a plain field that would drop the linear one" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const pair = pair_of(host)
        \\    return own pair.right
    , "E_LINEAR_USE", "would drop the `@linear` field `left`");
}

test "linear records refuse own of a nested plain field that would drop a linear one" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const o = Outer(inner=pair_of(host), n=0)
        \\    return own o.inner.right
    , "E_LINEAR_USE", "would drop the `@linear` field `left`");
}

test "linear records refuse a record with two linear fields" {
    try expectRefusedWith(holders_short,
        \\record Two:
        \\    a: Conn
        \\    b: Conn
        \\
        \\func f() -> int:
        \\    return 0
    , "E_LINEAR_USE", "`a` and `b` both do");
}

test "linear records refuse a record with a linear field and an option of one" {
    try expectRefusedWith(holders_short,
        \\record Two:
        \\    a: Conn
        \\    b: Conn?
        \\
        \\func f() -> int:
        \\    return 0
    , "E_LINEAR_USE", "`a` and `b` both do");
}

test "linear records refuse a second consumption after a plain match consumed an option" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    const o: Conn? = Some(open(host))
        \\    match o:
        \\        case Some(c):
        \\            _ = close(host, own c)
        \\        case None:
        \\            pass
        \\    match own o:
        \\        case Some(c):
        \\            return int(close(host, own c))
        \\        case None:
        \\            return 0
    , "E_LINEAR_CONSUMED", "already consumed");
}

test "linear records refuse a match mut binding given away" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    mut o: Conn? = Some(open(host))
        \\    match mut o:
        \\        case Some(c):
        \\            _ = close(host, own c)
        \\        case None:
        \\            pass
        \\    match own o:
        \\        case Some(c):
        \\            return int(close(host, own c))
        \\        case None:
        \\            return 0
    , "E_LINEAR_USE", "a `match mut` binding is lent, not owned");
}

test "linear records refuse a reassignment of a live owner" {
    try expectRefusedWith(holders_short,
        \\func f(host: Host) -> int:
        \\    mut conn = open(host)
        \\    conn = open(host)
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", "would end the `@linear` owner it replaces");
}

test "linear records refuse a print of an owner, which would consume it without ending it" {
    try expectRefusedWith(holders_long,
        \\func f(host: Host, out: Stream) -> int:
        \\    const conn = open(host)
        \\    print(out, conn.id)
        \\    print(out, conn)
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", "without ending it");
}

test "linear records refuse a comparison of two owners" {
    try expectRefusedWith(holders_long,
        \\func f(host: Host) -> bool:
        \\    const a = open(host)
        \\    const b = open(host)
        \\    const same = a == b
        \\    _ = close(host, own a)
        \\    _ = close(host, own b)
        \\    return same
    , "E_LINEAR_USE", "without ending it");
}

test "linear records refuse an own of a plain field three holders deep that would drop the linear one" {
    try expectRefusedWith(holders_long,
        \\func f(host: Host) -> int:
        \\    const l3 = L3(inner=L2(inner=pair_of(host), tag=2), tag=3)
        \\    return own l3.inner.tag
    , "E_LINEAR_USE", "would drop the `@linear` field `inner`");
}

test "linear records refuse an own of a plain field beside an option that holds an owner" {
    try expectRefusedWith(holders_long,
        \\func f(host: Host) -> int:
        \\    const box = Box(maybe=Some(open(host)), tag=1)
        \\    return own box.tag
    , "E_LINEAR_USE", "would drop the `@linear` field `maybe`");
}

test "linear records refuse a plain match of an option field inside a holder" {
    try expectRefusedWith(holders_long,
        \\func f(host: Host) -> int:
        \\    const box = Box(maybe=Some(open(host)), tag=1)
        \\    match box.maybe:
        \\        case Some(c):
        \\            return int(close(host, own c))
        \\        case None:
        \\            return 0
    , "E_LINEAR_USE", "a plain read would make a second owner");
}

test "linear records refuse an outer owner left live by a break out of a nested loop" {
    try expectRefusedWith(holders_long,
        \\func f(host: Host) -> int:
        \\    for i in range(3):
        \\        const a = open(host)
        \\        for j in range(3):
        \\            if j == 1:
        \\                break
        \\        if i == 1:
        \\            break
        \\        _ = close(host, own a)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "`a` is not consumed");
}

/// Holder records some cases share.
const holders_short =
    \\record Pair:
    \\    left: Conn
    \\    right: int
    \\
    \\record Outer:
    \\    inner: Pair
    \\    n: int
    \\
    \\func pair_of(host: Host) -> Pair:
    \\    return Pair(left=open(host), right=1)
    \\
;

/// Holder records some cases share.
const holders_long =
    \\record Pair:
    \\    left: Conn
    \\    right: int
    \\
    \\record L2:
    \\    inner: Pair
    \\    tag: int
    \\
    \\record L3:
    \\    inner: L2
    \\    tag: int
    \\
    \\record Box:
    \\    maybe: Conn?
    \\    tag: int
    \\
    \\func pair_of(host: Host) -> Pair:
    \\    return Pair(left=open(host), right=1)
    \\
;

/// `expectRefused` of `body` after the `holders` declarations.
fn expectRefusedWith(holders: []const u8, body: []const u8, code: []const u8, fragment: []const u8) !void {
    const joined = try std.mem.concat(t.allocator, u8, &.{ holders, "\n", body });
    defer t.allocator.free(joined);
    try expectRefused(joined, code, fragment);
}

// spec-case: LINEAR-RECORDS-1
test "linear records accept every consuming path, and an ordinary scalar record keeps E_OWN_MARKER on a field" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const accepted = try checked(arena.allocator(),
        \\func f(host: Host, flag: bool) -> int:
        \\    const conn = open(host)
        \\    if flag:
        \\        return int(close(host, own conn))
        \\    mut next = own conn
        \\    _ = use(mut next)
        \\    const db = own next.db
        \\    return int(db_close(host, db))
    );
    try t.expect(std.mem.indexOf(u8, accepted, "\"severity\":\"error\"") == null);
    // `@linear` beside `@invariant`, and on a record that also holds a runtime resource: both marks are accepted.
    const both = try checked(arena.allocator(),
        \\@invariant(self.id >= 0)
        \\@linear
        \\record Checked:
        \\    db: Db
        \\    id: int
        \\
        \\resource Ticket: filesystem
        \\
        \\@linear
        \\record Held:
        \\    ticket: Ticket
        \\    db: Db
        \\
        \\func f(host: Host) -> int:
        \\    const c = Checked(db=db_open(host), id=1)
        \\    return int(db_close(host, own c.db))
    );
    try t.expect(std.mem.indexOf(u8, both, "\"severity\":\"error\"") == null);
    try expectRefused(
        \\record Plain:
        \\    db: Db
        \\
        \\func f() -> int:
        \\    const p = Plain(db=Db())
        \\    const d = own p.db
        \\    return 0
    , "E_OWN_MARKER", "no managed storage");
}

test "linear records refuse the mark on a union, on a generic record and a bare own-parameter argument carries the own repair" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try expectRefused("@linear\nunion U:\n    a(x: int)", "E_ATTRIBUTE_TARGET", "attaches to a `record`");
    try expectRefused("@linear\nrecord Box[T]:\n    value: T", "E_ATTRIBUTE_TARGET", "non-generic `record`");
    const bare = try checked(arena.allocator(), "func f(host: Host) -> int:\n    const conn = open(host)\n    return int(close(host, conn))");
    try t.expect(std.mem.indexOf(u8, bare, "\"text\":\"own \"") != null);
}

test "linear records refuse a parallel task argument and a task result" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const task_source =
        \\import parallel
        \\
        \\@linear
        \\record Token:
        \\    id: int
        \\
        \\func work(mut token: Token) -> int:
        \\    return token.id
        \\
        \\func made(id: int) -> Token:
        \\    return Token(id=id)
        \\
        \\func end(own token: Token) -> int:
        \\    return own token.id
        \\
    ;
    try expectTaskRefusal(arena.allocator(), task_source ++
        \\func main() -> int:
        \\    const token = made(1)
        \\    with parallel.group() as g:
        \\        const job = g.submit(end, own token)
        \\        return job.result()
        \\
    );
    try expectTaskRefusal(arena.allocator(), task_source ++
        \\func main() -> int:
        \\    with parallel.group() as g:
        \\        const job = g.submit(made, 1)
        \\        const token = job.result()
        \\        return end(own token)
        \\
    );
}

/// `source`, a whole program, is refused with the task message of `E_LINEAR_USE`.
fn expectTaskRefusal(a: std.mem.Allocator, source: []const u8) !void {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    try directory.dir.writeFile(t.io, .{ .sub_path = "task.selka", .data = source });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const result = try std.process.run(a, t.io, .{ .argv = &.{ options.corePath(), "check", try std.fs.path.join(a, &.{ root, "task.selka" }), "--no-cache" } });
    if (std.mem.indexOf(u8, result.stderr, "parallel task") == null) report("{s}\n", .{result.stderr});
    try t.expect(std.mem.indexOf(u8, result.stderr, "error[E_LINEAR_USE]") != null);
    try t.expect(std.mem.indexOf(u8, result.stderr, "parallel task") != null);
}

// spec-case: LINEAR-RECORDS-3
test "linear records: an @linear record formats to itself and keeps its parse" {
    const language = @import("compiler.zig");
    const source =
        \\@linear
        \\record Lease:
        \\    id: int
        \\
        \\
        \\func release(own lease: Lease) -> int:
        \\    return own lease.id
        \\
        \\
        \\func main() -> int:
        \\    const lease = Lease(id=4)
        \\    return release(own lease)
        \\
    ;
    var c = try language.Compilation.init(t.allocator, "lease.selka", source);
    defer c.deinit();
    const formatted = try c.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expectEqualStrings(source, formatted);
    var again = try language.Compilation.init(t.allocator, "lease.selka", formatted);
    defer again.deinit();
    try again.check();
}

/// A union that holds a `@linear` owner in one case (FX8, decision LIN): `match mut` lends it, it does not end it.
const slot_holder =
    \\enum Slot:
    \\    busy(held: Conn)
    \\    idle
    \\
    \\func release(host: Host, own slot: Slot) -> int:
    \\    match own slot:
    \\        case busy(held):
    \\            return int(close(host, own held))
    \\        case idle:
    \\            return 0
    \\
;

/// `body` of `f(host: Host, flag: bool) -> int`, after a slot is made and a `match mut slot:` is opened with `arm` in the
/// busy case, then `after` once the match is done.
fn lentSlot(comptime arm: []const u8, comptime after: []const u8) []const u8 {
    return "func f(host: Host, flag: bool) -> int:\n    mut slot = Slot.busy(held=open(host))\n    match mut slot:\n" ++
        "        case busy(held):\n" ++ arm ++ "        case idle:\n            pass\n" ++ after;
}

test "linear records refuse a match mut that is the only use of its owner, and an overwrite of the owner in its arms" {
    // From the `match mut` binding of linear payloads until FX8 the match counted as consuming the owner, so both were accepted.
    try expectRefusedWith(slot_holder, lentSlot("            pass\n", "    return 0\n"), "E_LINEAR_UNCONSUMED", "a `match mut` lends `slot` to its arms and does not end it");
    try expectRefusedWith(slot_holder, lentSlot("            pass\n", "    return 0\n"), "E_LINEAR_UNCONSUMED", "end it with `own slot.field` where the field is kept (`const kept = own slot.field`");
    try expectRefusedWith(slot_holder,
        \\func f(host: Host) -> int:
        \\    mut slot = Slot.busy(held=open(host))
        \\    match mut slot:
        \\        case busy(held):
        \\            slot = Slot.idle
        \\        case idle:
        \\            slot = Slot.idle
        \\    return release(host, own slot)
    , "E_LINEAR_USE", "this assignment would end the `@linear` value `slot` holds unconsumed");
    try expectRefusedWith(slot_holder, lentSlot("            if flag:\n                slot = Slot.idle\n", "    return release(host, own slot)\n"), "E_LINEAR_USE", "a `match mut` lends `slot`");
}

// FX9: replacing the matched owner while the arm's binding is still used afterwards is also the hold's refusal
// (E_SINGLE_OWNER_OVERLAP, the source ownership check); for a `@linear` owner the front end's own refusal comes first.
test "linear records refuse an overwrite of the owner before a later use of the arm's binding with E_LINEAR_USE first" {
    const holders = slot_holder ++ "\nfunc touch(mut c: Conn) -> int:\n    return 1\n\n";
    const arm = "            slot = Slot.idle\n            _ = touch(mut held)\n";
    try expectRefusedWith(holders, lentSlot(arm, "    return release(host, own slot)\n"), "E_LINEAR_USE", "a `match mut` lends `slot`");
}

test "linear records refuse a match mut arm that leaves by return, break or continue with the matched owner unconsumed" {
    try expectRefusedWith(slot_holder, lentSlot("            if flag:\n                return 1\n", "    return release(host, own slot)\n"), "E_LINEAR_UNCONSUMED", "a `match mut` lends `slot`");
    try expectRefusedWith(slot_holder,
        \\func f(host: Host, flag: bool) -> int:
        \\    for i in range(2):
        \\        mut slot = Slot.busy(held=open(host))
        \\        match mut slot:
        \\            case busy(held):
        \\                if flag:
        \\                    break
        \\            case idle:
        \\                pass
        \\        _ = release(host, own slot)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "`slot` is not consumed");
    try expectRefusedWith(slot_holder,
        \\func f(host: Host, flag: bool) -> int:
        \\    for i in range(2):
        \\        mut slot = Slot.busy(held=open(host))
        \\        match mut slot:
        \\            case busy(held):
        \\                if flag:
        \\                    continue
        \\            case idle:
        \\                pass
        \\        _ = release(host, own slot)
        \\    return 0
    , "E_LINEAR_UNCONSUMED", "`slot` is not consumed");
}

test "linear records refuse a match mut arm that fails with the matched owner unconsumed" {
    try expectRefusedWith(slot_holder ++ "\nenum Problem:\n    bad\n\n",
        \\func f(host: Host, flag: bool) -> int fails Problem:
        \\    mut slot = Slot.busy(held=open(host))
        \\    match mut slot:
        \\        case busy(held):
        \\            if flag:
        \\                fail Problem.bad
        \\        case idle:
        \\            pass
        \\    return release(host, own slot)
    , "E_LINEAR_UNCONSUMED", "`slot` is not consumed");
}

test "linear records refuse every move of a match mut binding: own, own of a field, an alias, a store, a return, an end" {
    const lent = "a `match mut` binding is lent, not owned";
    const later = "    return release(host, own slot)\n";
    try expectRefusedWith(slot_holder, lentSlot("            _ = close(host, own held)\n", later), "E_LINEAR_USE", lent);
    try expectRefusedWith(slot_holder, lentSlot("            const other = held\n            _ = close(host, own other)\n", later), "E_LINEAR_USE", lent);
    try expectRefusedWith(slot_holder, lentSlot("            const o: Conn? = Some(held)\n            _ = o\n", later), "E_LINEAR_USE", lent);
    // `own held.id` ends a record; a `match mut` binding has nothing to end, and the front end says it was consumed (open).
    try expectRefusedWith(slot_holder, lentSlot("            _ = own held.id\n", later), "E_LINEAR_CONSUMED", "already consumed");
    try expectRefusedWith(slot_holder,
        \\func g(host: Host) -> Conn:
        \\    mut slot = Slot.busy(held=open(host))
        \\    match mut slot:
        \\        case busy(held):
        \\            return held
        \\        case idle:
        \\            pass
        \\    _ = release(host, own slot)
        \\    return open(host)
    , "E_LINEAR_USE", lent);
}

/// An option of a `@linear` record, a holder record around one, and the option of the holder: the receivers an
/// `unwrap_or` test calls.
const unwrap_holder =
    \\record Holder:
    \\    conn: Conn
    \\
    \\
    \\func maybe(host: Host, present: bool) -> Conn?:
    \\    if present:
    \\        return Some(open(host))
    \\    return None
    \\
    \\
    \\func held(host: Host, present: bool) -> Holder?:
    \\    if present:
    \\        return Some(Holder(conn=open(host)))
    \\    return None
    \\
    \\
;

test "linear records refuse unwrap_or on a call's option with a message that names match own, not an internal error" {
    const way = "take the payload with `match own value:` and make the default in the `None` arm";
    try expectRefusedWith(unwrap_holder,
        \\func f(host: Host) -> int:
        \\    const conn = maybe(host, True).unwrap_or(open(host))
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", way);
    try expectRefusedWith(unwrap_holder,
        \\func f(host: Host) -> int:
        \\    return int(close(host, own unwrap_or(maybe(host, True), open(host))))
    , "E_LINEAR_USE", way);
    try expectRefusedWith(unwrap_holder,
        \\func f(host: Host) -> int:
        \\    const holder = held(host, True).unwrap_or(Holder(conn=open(host)))
        \\    return int(close(host, own holder.conn))
    , "E_LINEAR_USE", way);
}

test "linear records refuse unwrap_or on a local option the same way, and the accepted spelling checks" {
    try expectRefusedWith(unwrap_holder,
        \\func f(host: Host) -> int:
        \\    const option = maybe(host, True)
        \\    const conn = option.unwrap_or(open(host))
        \\    return int(close(host, own conn))
    , "E_LINEAR_USE", "take the payload with `match own value:` and make the default in the `None` arm");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const accepted = try checked(arena.allocator(), unwrap_holder ++ "\n" ++
        \\func f(host: Host) -> int:
        \\    match own maybe(host, True):
        \\        case Some(conn):
        \\            return int(close(host, own conn))
        \\        case None:
        \\            return int(close(host, open(host)))
    );
    try t.expect(std.mem.indexOf(u8, accepted, "\"severity\":\"error\"") == null);
}
