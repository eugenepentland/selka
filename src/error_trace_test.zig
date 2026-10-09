//! Error return traces (`ERROR-TRACE-1` .. `ERROR-TRACE-4`): which sites an
//! `Err` records on its way out of `main`, and how the entry reports them.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

/// Build one guest program named `trace.my` and run it once natively.
fn run(source: []const u8) !native.Run {
    var compilation = try language.Compilation.init(t.allocator, "trace.my", source);
    defer compilation.deinit();
    return native.run(&compilation);
}

/// How many times `needle` occurs in `text`.
fn occurrences(text: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, text, needle);
}

// spec: ERROR-TRACE-1
test "an Err records its construction, each try that passes it on and the case try converts it to" {
    const outcome = try run(
        \\enum AppError:
        \\    Config(value: str)
        \\    Usage(value: int)
        \\
        \\func parse_port(text: str) -> Result[int, str]:
        \\    if len(text) == 0:
        \\        return Err("empty port")
        \\    return Ok(len(text))
        \\
        \\func read_config(text: str) -> Result[int, str]:
        \\    mut port = try parse_port(text)
        \\    return Ok(port + 1)
        \\
        \\func load(text: str) -> Result[int, AppError]:
        \\    const parsed = try read_config(text)
        \\    return Ok(parsed)
        \\
        \\func main() -> Result[int, AppError]:
        \\    mut port = try load("")
        \\    return Ok(port)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 1), outcome.status);
    try t.expectEqualStrings(
        \\error: AppError.Config(value='empty port')
        \\  trace.my:7:16   parse_port   Err(...) created
        \\  trace.my:11:16  read_config  try propagated
        \\  trace.my:15:20  load         try converted to AppError.Config
        \\  trace.my:19:16  main         try propagated
        \\
    , outcome.stderr);
}

// spec-case: ERROR-TRACE-1
test "a returned Err the return did not build records the return, through a variable, a call or a conditional" {
    const outcome = try run(
        \\func check(value: int) -> Result[int, int]:
        \\    mut failed: Result[int, int] = Err(value)
        \\    return failed
        \\
        \\func pass_on(result: Result[int, int]) -> Result[int, int]:
        \\    return result
        \\
        \\func choose(value: int) -> Result[int, int]:
        \\    return if (value > 10) then (Ok(value)) else (pass_on(check(value)))
        \\
        \\func main() -> Result[int, int]:
        \\    const parsed = try choose(4)
        \\    return Ok(parsed)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 4), outcome.status);
    try t.expectEqualStrings(
        \\error: 4
        \\  trace.my:2:36   check    Err(...) created
        \\  trace.my:3:5    check    returned
        \\  trace.my:6:5    pass_on  returned
        \\  trace.my:9:5    choose   returned
        \\  trace.my:12:20  main     try propagated
        \\
    , outcome.stderr);
}

// spec-case: ERROR-TRACE-1
test "a handled Err appends nothing and the next Err starts a fresh trace" {
    const outcome = try run(
        \\func fail(code: int) -> Result[int, int]:
        \\    return Err(code)
        \\
        \\func forward(code: int) -> Result[int, int]:
        \\    const parsed = try fail(code)
        \\    return Ok(parsed)
        \\
        \\func main() -> Result[int, int]:
        \\    mut recovered = 0
        \\    _ = forward(1)
        \\    match forward(2):
        \\        case Ok(value):
        \\            recovered += value
        \\        case Err(code):
        \\            recovered += code
        \\    return Err(recovered + 5)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 7), outcome.status);
    try t.expectEqualStrings(
        \\error: 7
        \\  trace.my:16:12  main  Err(...) created
        \\
    , outcome.stderr);
}

// spec-case: ERROR-TRACE-1
test "a runtime operation that answers Err starts the trace at its call" {
    const outcome = try run(
        \\func load(fs: Filesystem) -> Result[str, str]:
        \\    const parsed = try fs.read_text("/nonexistent/error-trace-probe")
        \\    return Ok(parsed)
        \\
        \\func main(fs: Filesystem) -> Result[int, str]:
        \\    mut text = try load(fs)
        \\    return Ok(len(text))
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 1), outcome.status);
    try t.expect(std.mem.startsWith(u8, outcome.stderr, "error: "));
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "trace.my:2:24  load  Err produced by the runtime\n") != null);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "trace.my:2:20  load  try propagated\n") != null);
    try t.expect(std.mem.endsWith(u8, outcome.stderr, "trace.my:6:16  main  try propagated\n"));
}

// spec: ERROR-TRACE-2
test "main's Err is reported as error: VALUE and its trace, and keeps its exit status" {
    const status = try run(
        \\func main() -> Result[Unit, int]:
        \\    return Err(3)
    );
    try t.expect(!status.trapped());
    try t.expectEqual(@as(u8, 3), status.status);
    try t.expectEqualStrings("error: 3\n  trace.my:2:12  main  Err(...) created\n", status.stderr);
    const message = try run(
        \\func main() -> Result[int, str]:
        \\    return Err("no input")
    );
    try t.expect(!message.trapped());
    try t.expectEqual(@as(u8, 1), message.status);
    try t.expectEqualStrings("error: no input\n  trace.my:2:12  main  Err(...) created\n", message.stderr);
    const fine = try run(
        \\func main() -> Result[int, str]:
        \\    return Ok(6)
    );
    try t.expect(!fine.trapped());
    try t.expectEqual(@as(u8, 6), fine.status);
    try t.expectEqualStrings("", fine.stderr);
}

// spec-case: ERROR-TRACE-2
test "a return on the Err's own line folds into it, and a broken contract is still a trap" {
    const folded = try run(
        \\@ensures(result < 1000)
        \\func parse(value: int) -> Result[int, str]:
        \\    if value > 100:
        \\        return Err("too big")
        \\    return Ok(value)
        \\
        \\func main() -> Result[int, str]:
        \\    const parsed = try parse(200)
        \\    return Ok(parsed)
    );
    try t.expect(!folded.trapped());
    try t.expectEqualStrings("error: too big\n  trace.my:4:16  parse  Err(...) created\n  trace.my:8:20  main   try propagated\n", folded.stderr);
    const broken = try run(
        \\@ensures(result < 1000)
        \\func huge(value: int) -> Result[int, str]:
        \\    return Ok(value * 1000)
        \\
        \\func main() -> Result[int, str]:
        \\    _ = huge(1)
        \\    const parsed = try huge(5)
        \\    return Ok(parsed)
    );
    try t.expect(broken.trapped());
    try t.expectEqualStrings("R_ENSURES", broken.trap.code);
    try t.expect(std.mem.indexOf(u8, broken.stderr, "error: ") == null);
}

// spec: RESULT-MAIN-2
test "main may fail with any printable error, which exits 1" {
    const outcome = try run(
        \\enum Problem:
        \\    Missing(value: str)
        \\    BadDigit(value: int)
        \\
        \\func main() -> Result[Unit, Problem]:
        \\    return Err(Problem.BadDigit(value=3))
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 1), outcome.status);
    try t.expectEqualStrings("error: Problem.BadDigit(value=3)\n  trace.my:6:12  main  Err(...) created\n", outcome.stderr);
}

// spec: ERROR-TRACE-4
test "a trace longer than the ring keeps the origin and the last 32 sites and counts the rest" {
    const outcome = try run(
        \\func descend(depth: int) -> Result[int, int]:
        \\    if depth == 0:
        \\        return Err(9)
        \\    const parsed = try descend(depth - 1)
        \\    return Ok(parsed + 1)
        \\
        \\func main() -> Result[int, int]:
        \\    const parsed = try descend(40)
        \\    return Ok(parsed)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 9), outcome.status);
    // 40 `try` in `descend` and one in `main` append 41 sites; the ring keeps 32.
    try t.expect(std.mem.startsWith(u8, outcome.stderr, "error: 9\n  trace.my:3:16  descend  Err(...) created\n  ... 9 more entries dropped ...\n"));
    try t.expectEqual(@as(usize, 31), occurrences(outcome.stderr, "descend  try propagated\n"));
    try t.expect(std.mem.endsWith(u8, outcome.stderr, "  trace.my:8:20  main     try propagated\n"));
}
