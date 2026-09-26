//! Contract clauses: where `@requires`, `@ensures` and `@invariant` may be
//! written, the diagnostics their conditions can raise, and the traps a
//! violated clause ends a native run with. Clauses that hold are guest tests
//! in `tests/lang/contracts.my`; the CLI, cache and interface behaviour is in
//! `test/integration.zig`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const sema_contracts = @import("sema_contracts.zig");
const trap_detail = @import("native_trap_detail.zig");

const unit = "contracts.my";

/// Check `text` and expect it rejected with `code` as its first error.
fn rejects(text: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

/// Check `text` and expect it accepted.
fn accepts(text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    try c.check();
}

/// Run `text` and expect it to return `expected`.
fn returns(text: []const u8, expected: i64) !void {
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    const run = try native.run(&c);
    try t.expect(!run.trapped());
    try t.expectEqual(expected, run.value);
}

/// Where one expected trap is reported.
const Expected = struct { code: []const u8, line: u64, column: u64, text: []const u8 };

/// Run `text` and expect it to trap as `expected` describes, with the
/// human line quoting `expected.text`. Returns the run for further checks.
fn traps(c: *language.Compilation, expected: Expected) !native.Run {
    const run = try native.run(c);
    try t.expect(run.trapped());
    try t.expectEqualStrings(expected.code, run.trap.code);
    try t.expectEqual(expected.line, run.trap.line);
    try t.expectEqual(expected.column, run.trap.column);
    try t.expect(std.mem.indexOf(u8, run.stderr, expected.text) != null);
    try t.expectEqual(@as(u8, 1), run.status);
    return run;
}

// spec: CONTRACT-SYNTAX-1
test "contracts: contract clauses attach to functions, records and domains and nowhere else" {
    try accepts(
        \\@invariant(self.low <= self.high)
        \\@invariant(self.low >= 0, "never negative")
        \\record Range:
        \\    low: int
        \\    high: int
        \\
        \\@invariant(unwrap(self) < 10u8)
        \\domain Digit: u8:
        \\    @requires(value < 10u8)
        \\    def from(value: u8) -> Digit:
        \\        return wrap[Digit](value)
        \\
        \\    @ensures(result < 10u8)
        \\    private def raw(value: Digit) -> u8:
        \\        return unwrap(value)
        \\
        \\@requires(x > 0)
        \\@requires(x < 100, "small")
        \\@ensures(result > x)
        \\def next[T](x: int, tag: T) -> int:
        \\    return x + 1
        \\
        \\def main() -> int:
        \\    same = Digit.from(3u8) == Digit.from(3u8)
        \\    return next(Range(1, 2).high, 0) if same else 0
    );
    try rejects("@invariant(True)\nclass C:\n    x: int\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\nunion U:\n    A,\n    B\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\ndef f() -> int:\n    return 0\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@requires(True)\nrecord R:\n    x: int\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@requires(True)\nextern def f(host: Host) -> int effects(host);\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@requires(True)\nconst X: int = 3;\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\ntype Count = int;\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\nrecord Box[T]:\n    value: T\n\ndef main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("domain D: u8:\n    @deprecated(\"old\")\n    def f() -> int:\n        return 0\n\ndef main() -> int:\n    return 0\n", "E_ATTRIBUTE_TARGET");
    try rejects("@requires(1)\ndef f(x: int) -> int:\n    return x\n\ndef main() -> int:\n    return f(1)\n", "E_TYPE");
}

// spec: CONTRACT-REQUIRES-1
test "contracts: a broken precondition traps R_REQUIRES at its clause and names the caller" {
    const text =
        \\@requires(amount > 0, "amount must be positive")
        \\@requires(amount < 100)
        \\def half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\def main() -> int:
        \\    first = half(8)
        \\    return first + half(first - 4)
    ;
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    const run = try traps(&c, .{ .code = "R_REQUIRES", .line = 1, .column = 11, .text = "half requires `amount > 0`: amount must be positive" });
    try t.expect(std.mem.indexOf(u8, run.stderr, "precondition violated") != null);
    try t.expect(std.mem.indexOf(u8, run.stderr, "broken by the caller main at contracts.my:8:20") != null);
    try t.expectEqual(@as(usize, 2), run.trap.frames.len);
    try t.expectEqualStrings("main", run.trap.frames[1].function);
    // The clauses are checked in source order, and a precondition only sees
    // the parameters: a body local is not in scope.
    try returns("@requires(x > 0)\n@requires(x < 10)\ndef f(x: int) -> int:\n    return x\n\ndef main() -> int:\n    return f(9)\n", 9);
    try rejects("@requires(y > 0)\ndef f(x: int) -> int:\n    y = x\n    return y\n\ndef main() -> int:\n    return f(1)\n", "E_UNKNOWN_NAME");
}

// spec: CONTRACT-ENSURES-1
test "contracts: a broken postcondition traps R_ENSURES at every normal return and skips an Err" {
    var early = try language.Compilation.init(t.allocator, unit,
        \\@ensures(result < 10, "stays small")
        \\def clamp(x: int) -> int:
        \\    if x > 50:
        \\        return x
        \\    return 1
        \\
        \\def main() -> int:
        \\    return clamp(3) + clamp(60)
    );
    defer early.deinit();
    _ = try traps(&early, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "clamp ensures `result < 10`: stays small" });
    // A procedure's implicit end is a normal return too.
    var procedure = try language.Compilation.init(t.allocator, unit,
        \\@ensures(len(items) == 1)
        \\def fill(items: mut list[int]):
        \\    items.append(1)
        \\    items.append(2)
        \\
        \\def main() -> int:
        \\    items: list[int] = []
        \\    fill(mut items)
        \\    return 0
    );
    defer procedure.deinit();
    _ = try traps(&procedure, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "fill ensures `len(items) == 1`" });
    // An `Err` return and a `?` that propagates one skip the clause; an `Ok`
    // payload is `result`.
    try returns(
        \\@ensures(result > 100)
        \\def check(x: int) -> Result[int, str]:
        \\    if x < 0:
        \\        return Err("negative")
        \\    return Ok(x)
        \\
        \\def relay(x: int) -> Result[int, str]:
        \\    value = check(x)?
        \\    return Ok(value)
        \\
        \\def main() -> int:
        \\    match relay(-1):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 7
    , 7);
    var ok = try language.Compilation.init(t.allocator, unit,
        \\@ensures(result > 100)
        \\def check(x: int) -> Result[int, str]:
        \\    return Ok(x)
        \\
        \\def main() -> int:
        \\    match check(5):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 7
    );
    defer ok.deinit();
    _ = try traps(&ok, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "check ensures `result > 100`" });
    try rejects("@ensures(result > 0)\ndef f(result: int) -> int:\n    return 1\n\ndef main() -> int:\n    return f(1)\n", sema_contracts.result_code);
    try rejects("@ensures(result > 0)\ndef f(x: int):\n    pass\n\ndef main() -> int:\n    f(1)\n    return 0\n", sema_contracts.result_code);
}

// spec: CONTRACT-OLD-1
test "contracts: old captures an entry value once and rejects a shared one" {
    var grown = try language.Compilation.init(t.allocator, unit,
        \\@ensures(len(items) == old(len(items)) + 1, "adds exactly one")
        \\def add(items: mut list[int], value: int):
        \\    items.append(value)
        \\    if value > 5:
        \\        items.append(value)
        \\
        \\def main() -> int:
        \\    items: list[int] = []
        \\    add(mut items, 1)
        \\    add(mut items, 9)
        \\    return len(items)
    );
    defer grown.deinit();
    _ = try traps(&grown, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "add ensures `len(items) == old(len(items)) + 1`: adds exactly one" });
    // A fresh copy of a shared value is a value of its own.
    try returns("@ensures(len(items) == len(old(items.copy())) + 1)\ndef add(items: mut list[int]):\n    items.append(0)\n\ndef main() -> int:\n    items = [1]\n    add(mut items)\n    return len(items)\n", 2);
    try rejects("@ensures(len(old(items)) == 0)\ndef add(items: mut list[int]):\n    items.append(0)\n\ndef main() -> int:\n    items = [1]\n    add(mut items)\n    return 0\n", sema_contracts.old_shared_code);
    try rejects("@ensures(len(old(rows.copy())) == 0)\ndef add(rows: mut list[list[int]]):\n    rows.append([0])\n\ndef main() -> int:\n    rows = [[1]]\n    add(mut rows)\n    return 0\n", sema_contracts.old_shared_code);
    try rejects("@requires(old(x) > 0)\ndef f(x: int) -> int:\n    return x\n\ndef main() -> int:\n    return f(1)\n", sema_contracts.old_code);
    try rejects("def f(x: int) -> int:\n    return old(x)\n\ndef main() -> int:\n    return f(1)\n", sema_contracts.old_code);
    try rejects("@ensures(old(old(x)) > 0)\ndef f(x: int) -> int:\n    return x\n\ndef main() -> int:\n    return f(1)\n", sema_contracts.old_code);
}

// spec: CONTRACT-PURE-1
test "contracts: a contract condition may allocate but have no other effect" {
    try rejects(
        \\def shout(out: Stream) -> bool:
        \\    out.print("checked")
        \\    return True
        \\
        \\@requires(shout(out))
        \\def f(out: Stream, x: int) -> int:
        \\    return x
        \\
        \\def main(out: Stream) -> int:
        \\    return f(out, 1)
    , sema_contracts.effect_code);
    try rejects("@requires(items.pop() > 0)\ndef f(items: mut list[int]) -> int:\n    return 1\n\ndef main() -> int:\n    items = [1]\n    return f(mut items)\n", sema_contracts.effect_code);
    try rejects(
        \\def grow(items: mut list[int]) -> bool:
        \\    items.append(1)
        \\    return True
        \\
        \\@requires(grow(mut items))
        \\def f(items: mut list[int]) -> int:
        \\    return 1
        \\
        \\def main() -> int:
        \\    items = [1]
        \\    return f(mut items)
    , sema_contracts.effect_code);
    try rejects(
        \\def half(x: int) -> Result[int, str]:
        \\    return Ok(x // 2)
        \\
        \\@ensures(half(result)? > 0)
        \\def f(x: int) -> Result[int, str]:
        \\    return Ok(x)
        \\
        \\def main() -> int:
        \\    return 0
    , sema_contracts.effect_code);
    // An invariant sees only `self`, yet a field of it is still storage the
    // condition must not change.
    try rejects(
        \\@invariant(self.items.pop() >= 0)
        \\record Bag:
        \\    items: list[int]
        \\
        \\def main() -> int:
        \\    return len(Bag([1]).items)
    , sema_contracts.effect_code);
    // A condition only observes: it cannot take a result-bearing value away
    // from the body that still owns it.
    try rejects(
        \\def value_or(outcome: Result[int, str]) -> int:
        \\    match outcome:
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 0
        \\
        \\@requires(value_or(outcome) > 0)
        \\def f(outcome: Result[int, str]) -> int:
        \\    return value_or(outcome)
        \\
        \\def main() -> int:
        \\    return f(Ok(1))
    , sema_contracts.effect_code);
    // Allocation, a helper that only allocates, a comprehension's own list
    // and `debug` are all effect-free for a contract.
    try accepts(
        \\def positive(values: list[int]) -> bool:
        \\    debug(values)
        \\    return len([v for v in values if v > 0]) == len(values)
        \\
        \\@requires(positive([x, x + 1]))
        \\@ensures(str(result) != "")
        \\def f(x: int) -> int:
        \\    return x
        \\
        \\def main() -> int:
        \\    return f(1)
    );
}

/// One program body after a shared head and where its invariant trap is reported.
const InvariantCase = struct { body: []const u8, line: u64, column: u64 };

/// Run `head` followed by each case body and expect the `Range` invariant to
/// trap at the case's position.
fn expectInvariantTraps(head: []const u8, cases: []const InvariantCase) !void {
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ head, case.body });
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, unit, text);
        defer c.deinit();
        _ = try traps(&c, .{ .code = "R_INVARIANT", .line = case.line, .column = case.column, .text = "Range invariant `self.low <= self.high`: ordered" });
    }
}

// spec: CONTRACT-INVARIANT-1
test "contracts: an invariant traps R_INVARIANT where a value is built or changed" {
    const head =
        \\@invariant(self.low <= self.high, "ordered")
        \\record Range:
        \\    low: int
        \\    high: int = 10
        \\
        \\record Window:
        \\    span: Range
        \\    label: int
        \\
        \\def main() -> int:
        \\
    ;
    try expectInvariantTraps(head, &.{
        .{ .body = "    r = Range(5, 1)\n    return r.low\n", .line = 11, .column = 9 },
        .{ .body = "    r = Range(low=50)\n    return r.low\n", .line = 11, .column = 9 },
        .{ .body = "    r = Range(1, 2)\n    r.low = 9\n    return r.low\n", .line = 12, .column = 5 },
        .{ .body = "    r = Range(1, 2)\n    r.high -= 5\n    return r.low\n", .line = 12, .column = 5 },
        .{ .body = "    r = replace(Range(1, 2), high=0)\n    return r.low\n", .line = 11, .column = 9 },
        .{ .body = "    w = Window(span=Range(1, 2), label=0)\n    w.span.low = 7\n    return w.label\n", .line = 12, .column = 5 },
        .{ .body = "    r = Range(1, 2)\n    r.low, r.high = 5, 4\n    return r.low\n", .line = 12, .column = 5 },
    });
    var domain = try language.Compilation.init(t.allocator, unit,
        \\@invariant(unwrap(self) <= 1000u32)
        \\domain Millimeters: u32:
        \\    def from(value: u32) -> Millimeters:
        \\        return wrap[Millimeters](value)
        \\
        \\def main() -> int:
        \\    distance = Millimeters.from(2000u32)
        \\    return 1 if distance == distance else 0
    );
    defer domain.deinit();
    _ = try traps(&domain, .{ .code = "R_INVARIANT", .line = 4, .column = 16, .text = "Millimeters invariant `unwrap(self) <= 1000u32`" });
    // A plain copy is not a change, and a value the invariant allows runs on.
    try returns(head ++ "    r = Range(1, 2)\n    copy = r\n    return copy.high\n", 2);
}

// spec: CONTRACT-TRAP-1
test "contracts: every run protocol reports the contract's own trap code" {
    const text = "@requires(x > 0)\ndef f(x: int) -> int:\n    return x\n\ndef main() -> int:\n    return f(0)\n";
    var accounted = try language.Compilation.init(t.allocator, unit, text);
    defer accounted.deinit();
    _ = try traps(&accounted, .{ .code = "R_REQUIRES", .line = 1, .column = 11, .text = "f requires `x > 0`" });
    // The protocol a published executable and an unbounded `mylang run` use
    // links no frame record, and still reports the same trap.
    var fast = try language.Compilation.init(t.allocator, unit, text);
    defer fast.deinit();
    const run = try native.runUnaccounted(&fast, .{});
    try t.expectEqualStrings("R_REQUIRES", run.trap.code);
    try t.expectEqual(@as(u64, 1), run.trap.line);
    try t.expect(std.mem.indexOf(u8, run.stderr, "f requires `x > 0`") != null);
    // A plain `assert` keeps `R_ASSERT`.
    var plain = try language.Compilation.init(t.allocator, unit, "def main() -> int:\n    assert 1 > 2, \"R_REQUIRES looks alike\"\n    return 0\n");
    defer plain.deinit();
    const asserted = try native.run(&plain);
    try t.expectEqualStrings("R_ASSERT", asserted.trap.code);
}

fn assertPrefixStaysLiteral(prefix: []const u8) !void {
    const text = try std.fmt.allocPrint(t.allocator, "def main() -> int:\n    assert False, \"{s}: ordinary assertion\"\n    return 0\n", .{prefix});
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    const accounted = try native.run(&c);
    try t.expectEqualStrings("R_ASSERT", accounted.trap.code);
    try t.expect(std.mem.indexOf(u8, accounted.stderr, prefix) != null);
    const fast = try native.runUnaccounted(&c, .{});
    try t.expectEqualStrings("R_ASSERT", fast.trap.code);
    try t.expect(std.mem.indexOf(u8, fast.stderr, prefix) != null);
}

// spec: CONTRACT-TRAP-2
test "contracts: literal assert prefixes cannot impersonate contract traps" {
    try assertPrefixStaysLiteral("R_REQUIRES");
    try assertPrefixStaysLiteral("R_ENSURES");
    try assertPrefixStaysLiteral("R_INVARIANT");
}

// spec-case: CONTRACT-TRAP-1
test "contracts: a contract trap message folds its clause and the record reads back its fields" {
    const message = try sema_contracts.trapMessage(t.allocator, .requires, "withdraw", "amount >\n        0", "must be positive");
    defer t.allocator.free(message);
    try t.expectEqualStrings("withdraw requires `amount > 0`: must be positive", message);
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const record = "x.my:1:2: error[R_ENSURES]: postcondition violated: f ensures `result > 0`: why\n" ++ trap_detail.marker ++ "{\"version\":1,\"operation\":\"f ensures `result > 0`: why\"}\n";
    const found = trap_detail.contract(arena.allocator(), "R_ENSURES", record).?;
    try t.expectEqualStrings("ensures", found.kind);
    try t.expectEqualStrings("f", found.subject);
    try t.expectEqualStrings("result > 0", found.clause);
    try t.expectEqualStrings("why", found.message.?);
    try t.expect(trap_detail.contract(arena.allocator(), "R_ASSERT", record) == null);
    try t.expect(trap_detail.messageTrap("R_INVARIANT"));
}

// spec: PROPERTY-TEST-2
test "contracts: a test checks its parameters' invariants on entry and passes every value guest code built" {
    try returns(
        \\@invariant(self.low <= self.high)
        \\record Span:
        \\    low: int
        \\    high: int
        \\
        \\record Holder:
        \\    spans: list[Span]
        \\    best: Option[Span]
        \\
        \\def test_holder(holder: Holder, keyed: dict[str, Span], pair: tuple[Span, int]) -> bool:
        \\    first, _ = pair
        \\    return len(holder.spans) + len(keyed) == 3 and first.low == 1
        \\
        \\def plain(holder: Holder) -> int:
        \\    return len(holder.spans)
        \\
        \\def main() -> int:
        \\    holder = Holder(spans=[Span(1, 2), Span(3, 3)], best=Some(Span(0, 9)))
        \\    passed = test_holder(holder, {"a": Span(-1, 1)}, (Span(1, 4), 0))
        \\    return plain(holder) + (40 if passed else 0)
    , 42);
}
