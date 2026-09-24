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

/// The manifest, unit text included, the compiler emits for one program.
fn emitted(allocator: std.mem.Allocator, source: []const u8) ![]const u8 {
    var compilation = try language.Compilation.init(t.allocator, "trace.my", source);
    defer compilation.deinit();
    return compilation.emitQbe(allocator);
}

/// How many times `needle` occurs in `text`.
fn occurrences(text: []const u8, needle: []const u8) usize {
    return std.mem.count(u8, text, needle);
}

// spec: ERROR-TRACE-1
test "an Err records its construction, each ? that passes it on and the case a ? converts it to" {
    const outcome = try run(
        \\union AppError:
        \\    Config: str,
        \\    Usage: int
        \\
        \\def parse_port(text: str) -> Result[int, str]:
        \\    if len(text) == 0:
        \\        return Err("empty port")
        \\    return Ok(len(text))
        \\
        \\def read_config(text: str) -> Result[int, str]:
        \\    port = parse_port(text)?
        \\    return Ok(port + 1)
        \\
        \\def load(text: str) -> Result[int, AppError]:
        \\    return Ok(read_config(text)?)
        \\
        \\def main() -> Result[int, AppError]:
        \\    port = load("")?
        \\    return Ok(port)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 1), outcome.status);
    try t.expectEqualStrings(
        \\error: AppError.Config('empty port')
        \\  trace.my:7:16   parse_port   Err(...) created
        \\  trace.my:11:12  read_config  ? propagated
        \\  trace.my:15:15  load         ? converted to AppError.Config
        \\  trace.my:18:12  main         ? propagated
        \\
    , outcome.stderr);
}

// spec-case: ERROR-TRACE-1
test "a returned Err the return did not build records the return, through a variable, a call or a conditional" {
    const outcome = try run(
        \\def check(value: int) -> Result[int, int]:
        \\    failed: Result[int, int] = Err(value)
        \\    return failed
        \\
        \\def pass_on(result: Result[int, int]) -> Result[int, int]:
        \\    return result
        \\
        \\def choose(value: int) -> Result[int, int]:
        \\    return Ok(value) if value > 10 else pass_on(check(value))
        \\
        \\def main() -> Result[int, int]:
        \\    return Ok(choose(4)?)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 4), outcome.status);
    try t.expectEqualStrings(
        \\error: 4
        \\  trace.my:2:32   check    Err(...) created
        \\  trace.my:3:5    check    returned
        \\  trace.my:6:5    pass_on  returned
        \\  trace.my:9:5    choose   returned
        \\  trace.my:12:15  main     ? propagated
        \\
    , outcome.stderr);
}

// spec-case: ERROR-TRACE-1
test "a handled Err appends nothing and the next Err starts a fresh trace" {
    const outcome = try run(
        \\def fail(code: int) -> Result[int, int]:
        \\    return Err(code)
        \\
        \\def forward(code: int) -> Result[int, int]:
        \\    return Ok(fail(code)?)
        \\
        \\def main() -> Result[int, int]:
        \\    recovered = 0
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
        \\  trace.my:15:12  main  Err(...) created
        \\
    , outcome.stderr);
}

// spec-case: ERROR-TRACE-1
test "a runtime operation that answers Err starts the trace at its call" {
    const outcome = try run(
        \\def load(fs: Filesystem) -> Result[str, str]:
        \\    return Ok(fs.read_text("/nonexistent/error-trace-probe")?)
        \\
        \\def main(fs: Filesystem) -> Result[int, str]:
        \\    text = load(fs)?
        \\    return Ok(len(text))
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 1), outcome.status);
    try t.expect(std.mem.startsWith(u8, outcome.stderr, "error: "));
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "trace.my:2:15  load  Err produced by the runtime\n") != null);
    try t.expect(std.mem.indexOf(u8, outcome.stderr, "trace.my:2:15  load  ? propagated\n") != null);
    try t.expect(std.mem.endsWith(u8, outcome.stderr, "trace.my:5:12  main  ? propagated\n"));
}

// spec-case: ERROR-TRACE-1
test "the success paths execute no trace store: a returned Ok checks nothing and a ? records only past its error branch" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const ok_only = try emitted(arena.allocator(),
        \\def make_ok(value: int) -> Result[int, str]:
        \\    return Ok(value)
        \\
        \\def main() -> int:
        \\    match make_ok(3):
        \\        case Ok(value):
        \\            return value
        \\        case Err(message):
        \\            return len(message)
    );
    try t.expectEqual(@as(usize, 0), occurrences(ok_only, "myl_qbe_error_trace"));
    const propagating = try emitted(arena.allocator(),
        \\def make_ok(value: int) -> Result[int, str]:
        \\    return Ok(value)
        \\
        \\def twice(value: int) -> Result[int, str]:
        \\    return Ok(make_ok(value)? * 2)
        \\
        \\def main() -> int:
        \\    match twice(3):
        \\        case Ok(value):
        \\            return value
        \\        case Err(message):
        \\            return len(message)
    );
    // One `?`: its error branch appends once; the construction and the return
    // of `Ok(...)` record nothing.
    try t.expectEqual(@as(usize, 1), occurrences(propagating, "myl_qbe_error_trace"));
    const branch = std.mem.indexOf(u8, propagating, "@tryerror").?;
    try t.expect(std.mem.indexOf(u8, propagating, "call $myl_qbe_error_trace_append(").? > branch);
}

// spec-case: ERROR-TRACE-1
test "each trace record is one call to a cold recorder that collects nothing" {
    const error_trace = @import("qbe_error_trace.zig");
    const roots = @import("qbe_roots.zig");
    const llvm_runtime = @import("qbe_build_llvm_runtime.zig");
    try t.expect(roots.pureCallee(error_trace.origin_symbol));
    try t.expect(roots.pureCallee(error_trace.append_symbol));
    try t.expectEqualStrings("cold nounwind", llvm_runtime.attributes(error_trace.origin_symbol));
    try t.expectEqualStrings("cold nounwind", llvm_runtime.attributes(error_trace.append_symbol));
}

// spec: ERROR-TRACE-2
test "main's Err is reported as error: VALUE and its trace, and keeps its exit status" {
    const status = try run(
        \\def main() -> Result[None, int]:
        \\    return Err(3)
    );
    try t.expect(!status.trapped());
    try t.expectEqual(@as(u8, 3), status.status);
    try t.expectEqualStrings("error: 3\n  trace.my:2:12  main  Err(...) created\n", status.stderr);
    const message = try run(
        \\def main() -> Result[int, str]:
        \\    return Err("no input")
    );
    try t.expect(!message.trapped());
    try t.expectEqual(@as(u8, 1), message.status);
    try t.expectEqualStrings("error: no input\n  trace.my:2:12  main  Err(...) created\n", message.stderr);
    const fine = try run(
        \\def main() -> Result[int, str]:
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
        \\def parse(value: int) -> Result[int, str]:
        \\    if value > 100:
        \\        return Err("too big")
        \\    return Ok(value)
        \\
        \\def main() -> Result[int, str]:
        \\    return Ok(parse(200)?)
    );
    try t.expect(!folded.trapped());
    try t.expectEqualStrings("error: too big\n  trace.my:4:16  parse  Err(...) created\n  trace.my:8:15  main   ? propagated\n", folded.stderr);
    const broken = try run(
        \\@ensures(result < 1000)
        \\def huge(value: int) -> Result[int, str]:
        \\    return Ok(value * 1000)
        \\
        \\def main() -> Result[int, str]:
        \\    _ = huge(1)
        \\    return Ok(huge(5)?)
    );
    try t.expect(broken.trapped());
    try t.expectEqualStrings("R_ENSURES", broken.trap.code);
    try t.expect(std.mem.indexOf(u8, broken.stderr, "error: ") == null);
}

// spec: RESULT-MAIN-2
test "main may fail with any printable error, which exits 1" {
    const outcome = try run(
        \\union Problem:
        \\    Missing: str,
        \\    BadDigit: int
        \\
        \\def main() -> Result[None, Problem]:
        \\    return Err(Problem.BadDigit(3))
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 1), outcome.status);
    try t.expectEqualStrings("error: Problem.BadDigit(3)\n  trace.my:6:12  main  Err(...) created\n", outcome.stderr);
}

// spec: ERROR-TRACE-4
test "a trace longer than the ring keeps the origin and the last 32 sites and counts the rest" {
    const outcome = try run(
        \\def descend(depth: int) -> Result[int, int]:
        \\    if depth == 0:
        \\        return Err(9)
        \\    return Ok(descend(depth - 1)? + 1)
        \\
        \\def main() -> Result[int, int]:
        \\    return Ok(descend(40)?)
    );
    try t.expect(!outcome.trapped());
    try t.expectEqual(@as(u8, 9), outcome.status);
    // 40 `?` in `descend` and one in `main` append 41 sites; the ring keeps 32.
    try t.expect(std.mem.startsWith(u8, outcome.stderr, "error: 9\n  trace.my:3:16  descend  Err(...) created\n  ... 9 more entries dropped ...\n"));
    try t.expectEqual(@as(usize, 31), occurrences(outcome.stderr, "descend  ? propagated\n"));
    try t.expect(std.mem.endsWith(u8, outcome.stderr, "  trace.my:7:15  main     ? propagated\n"));
}
