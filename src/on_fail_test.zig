//! The refused half of `on fail:` (D-FFI-15, `docs/results-and-options.md#cleanup-on-failure`): each form the rule's
//! table refuses, with its code and message, plus the formatter's round trip and `on` as a module name. The accepted half
//! is `tests/lang/on_fail.selka`, and the C-backed one `test/core/c_on_fail.selka`.
const std = @import("std");
const t = std.testing;
const options = @import("test_paths");
/// Failure detail goes to the test's stderr.
const report = std.debug.print;

/// The declarations every case shares: a `@linear` token, its closer, and a step that fails.
const head =
    \\@linear
    \\record Token:
    \\    id: int
    \\
    \\
    \\func make(id: int) -> Token:
    \\    return Token(id=id)
    \\
    \\
    \\func close(own token: Token):
    \\    _ = own token.id
    \\
    \\
    \\func step(n: int) -> int fails str:
    \\    if n > 2:
    \\        fail "step"
    \\    return n
    \\
;

/// Run the compiler with `args` (a path `FILE` in them is the project's `name`) in a fresh directory holding `files`.
fn compile(a: std.mem.Allocator, files: []const [2][]const u8, args: []const []const u8) !std.process.RunResult {
    var directory = t.tmpDir(.{});
    defer directory.cleanup();
    for (files) |file| try directory.dir.writeFile(t.io, .{ .sub_path = file[0], .data = file[1] });
    const root = try directory.dir.realPathFileAlloc(t.io, ".", a);
    const argv = try std.mem.concat(a, []const u8, &.{ &.{options.corePath()}, args });
    return std.process.run(a, t.io, .{ .argv = argv, .cwd = .{ .path = root } });
}

/// `body` after the shared declarations is refused, first with `code`, and the message contains `fragment`.
fn expectRefused(body: []const u8, code: []const u8, fragment: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ head, "\n", body, "\n\nfunc main() -> int:\n    return 0\n" });
    const result = try compile(a, &.{.{ "clauses.selka", source }}, &.{ "check", "clauses.selka", "--no-cache", "--diagnostics=json" });
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
}

// spec-case: ON-FAIL-1
test "on fail is refused in a function that does not fail, and where no failure exit reaches it" {
    try expectRefused(
        \\func plain() -> int:
        \\    const token = make(1)
        \\    on fail: close(own token)
        \\    close(own token)
        \\    return 0
    , "E_ON_FAIL", "declares no `fails`");
    try expectRefused(
        \\func nothing_follows() -> int fails str:
        \\    const token = make(1)
        \\    on fail: close(own token)
        \\    close(own token)
        \\    return 0
    , "E_ON_FAIL", "no failure exit reaches this `on fail:`");
    try expectRefused(
        \\func disarmed_first() -> int fails str:
        \\    const token = make(1)
        \\    on fail: close(own token)
        \\    close(own token)
        \\    const value = try step(1)
        \\    return value
    , "E_ON_FAIL", "no failure exit reaches this `on fail:`");
}

// spec-case: ON-FAIL-1
test "an on fail clause cannot try, fail, return, break, continue or hold another clause" {
    const fragment = "it cannot `try`, `fail`, `return`, `break`, `continue`";
    try expectRefused(
        \\func tries() -> int fails str:
        \\    on fail: _ = try step(1)
        \\    return try step(1)
    , "E_ON_FAIL", fragment);
    try expectRefused(
        \\func fails_again() -> int fails str:
        \\    on fail: fail "again"
        \\    const value = try step(1)
        \\    return value
    , "E_ON_FAIL", fragment);
    try expectRefused(
        \\func returns() -> int fails str:
        \\    on fail:
        \\        return 0
        \\    const value = try step(1)
        \\    return value
    , "E_ON_FAIL", fragment);
    try expectRefused(
        \\func breaks() -> int fails str:
        \\    for i in range(2):
        \\        on fail:
        \\            break
        \\        _ = try step(i)
        \\    return 0
    , "E_ON_FAIL", fragment);
    try expectRefused(
        \\func continues() -> int fails str:
        \\    for i in range(2):
        \\        on fail: continue
        \\        _ = try step(i)
        \\    return 0
    , "E_ON_FAIL", fragment);
    try expectRefused(
        \\func nested() -> int fails str:
        \\    on fail:
        \\        on fail: _ = 1
        \\    const value = try step(1)
        \\    return value
    , "E_ON_FAIL", fragment);
}

// spec-case: ON-FAIL-1
test "an on fail clause leaves no new owner live, consumes only owners live at its exits, and names none declared after it" {
    try expectRefused(
        \\func leaves_owner() -> int fails str:
        \\    on fail:
        \\        const extra = make(2)
        \\    const value = try step(1)
        \\    return value
    , "E_LINEAR_UNCONSUMED", "`extra` is not consumed");
    try expectRefused(
        \\func consumed_before() -> int fails str:
        \\    const token = make(1)
        \\    close(own token)
        \\    on fail: close(own token)
        \\    const value = try step(1)
        \\    return value
    , "E_LINEAR_CONSUMED", "`token` was already consumed");
    try expectRefused(
        \\func declared_after() -> int fails str:
        \\    on fail: close(own token)
        \\    const token = make(1)
        \\    const value = try step(1)
        \\    close(own token)
        \\    return value
    , "E_ON_FAIL", "comes after the `on fail:` that consumes it");
}

// spec-case: ON-FAIL-1
test "in reach of on fail, a try is a declaration or a statement, and an owner consumed on one branch only stays refused" {
    try expectRefused(
        \\func assigned() -> int fails str:
        \\    const token = make(1)
        \\    on fail: close(own token)
        \\    mut value = 0
        \\    value = try step(1)
        \\    close(own token)
        \\    return value
    , "E_ON_FAIL", "`try` is a declaration's value");
    // The only exit is in a position the clause does not cover: that position is the error, and the clause is not
    // reported as one no exit reaches.
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const looped =
        \\func looped() -> int fails str:
        \\    mut total = 0
        \\    for i in range(3):
        \\        const token = make(20 + i)
        \\        on fail: close(own token)
        \\        total += try step(i)
        \\        close(own token)
        \\    return total
    ;
    try expectRefused(looped, "E_ON_FAIL", "`try` is a declaration's value");
    const source = try std.mem.concat(arena.allocator(), u8, &.{ head, "\n", looped, "\n\nfunc main() -> int:\n    return 0\n" });
    const result = try compile(arena.allocator(), &.{.{ "clauses.selka", source }}, &.{ "check", "clauses.selka", "--no-cache" });
    try t.expect(std.mem.indexOf(u8, result.stderr, "never runs") == null);
    try expectRefused(
        \\func one_branch(flag: bool) -> int fails str:
        \\    const token = make(1)
        \\    on fail: close(own token)
        \\    if flag:
        \\        close(own token)
        \\    const value = try step(1)
        \\    return value
    , "E_LINEAR_USE", "every path must leave a `@linear` owner in the same state");
}

// spec-case: ON-FAIL-1
test "the formatter keeps both forms of on fail, and on stays a module name" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const canonical =
        \\func run() -> int fails str:
        \\    mut stage = 0
        \\    on fail: stage = 1
        \\    on fail:
        \\        stage = 2
        \\        stage = 3
        \\    const value = try step(1)
        \\    return value + stage
        \\
    ;
    const source = try std.mem.concat(a, u8, &.{ head, "\n\n", canonical });
    const kept = try compile(a, &.{.{ "clauses.selka", source }}, &.{ "fmt", "--check", "clauses.selka" });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, kept.term);
    // A colon after a parameter named `fail` keeps the layout it had before `on fail:` existed.
    const parameter = "func checked(fail : bool) -> int:\n    return 0\n";
    const unchanged = try compile(a, &.{.{ "parameter.selka", parameter }}, &.{ "fmt", "--check", "parameter.selka" });
    try t.expectEqual(std.process.Child.Term{ .exited = 0 }, unchanged.term);
    const module = "public func on(value: int) -> int:\n    return value + 1\n";
    const entry = "import on\n\n\nfunc main() -> int:\n    return on.on(41)\n";
    const ran = try compile(a, &.{ .{ "on.selka", module }, .{ "main.selka", entry } }, &.{ "run", "main.selka", "--print-result", "--no-cache" });
    try t.expectEqualStrings("42\n", ran.stdout);
}

/// `body` after the shared declarations checks without a diagnostic.
fn expectAccepted(body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const source = try std.mem.concat(a, u8, &.{ head, "\n", body, "\n\nfunc main() -> int:\n    return 0\n" });
    const result = try compile(a, &.{.{ "clauses.selka", source }}, &.{ "check", "clauses.selka", "--no-cache", "--diagnostics=json" });
    if (std.mem.indexOf(u8, result.stderr, "\"code\":\"") != null) report("expected no diagnostic, got:\n{s}\n", .{result.stderr});
    try t.expect(std.mem.indexOf(u8, result.stderr, "\"code\":\"") == null);
}

// spec-case: ON-FAIL-1
test "a head that consumes the owner disarms its clause for the blocks it heads, so their exits do not consume it again" {
    try expectAccepted(
        \\func headed() -> int fails str:
        \\    mut held: Token? = Some(make(1))
        \\    on fail:
        \\        match own held:
        \\            case Some(token):
        \\                close(own token)
        \\            case None:
        \\                pass
        \\    _ = try step(1)
        \\    match own held:
        \\        case Some(token):
        \\            on fail: close(own token)
        \\            _ = try step(2)
        \\            close(own token)
        \\        case None:
        \\            pass
        \\    return 0
    );
}

// spec-case: ON-FAIL-1
test "selka reference answers E_ON_FAIL with its meaning and its guide" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const answered = try compile(arena.allocator(), &.{}, &.{ "reference", "--query", "E_ON_FAIL" });
    try t.expect(std.mem.indexOf(u8, answered.stdout, "E_ON_FAIL") != null);
    try t.expect(std.mem.indexOf(u8, answered.stdout, "on fail:") != null);
}
