//! Contract clauses: where `@requires`, `@ensures` and `@invariant` may be
//! written, the diagnostics their conditions can raise, and the traps a
//! violated clause ends a native run with. Clauses that hold are guest tests
//! in `tests/lang/contracts.selka`; the CLI, cache and interface behaviour is in
//! `test/integration.zig`.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const fixture = @import("stdlib_fixture.zig");
const sema_contracts = @import("sema_contracts.zig");
const trap_detail = @import("native_trap_detail.zig");

const unit = "contracts.selka";

/// Check `text` and expect it rejected with `code` as its first error.
fn rejects(text: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.rejectsWith(arena.allocator(), text, code);
}

/// Check `text` and expect it accepted.
fn accepts(text: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try fixture.accept(arena.allocator(), text);
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

// spec-case: CONTRACT-OLD-1
// spec-case: VALUE-SEMANTICS-7
test "contracts: old owns deep aggregate captures across both return paths" {
    try returns(
        \\record State:
        \\    entries: dict[int, int[]]
        \\@ensures(old(copy(state)).entries[1][0] == 7)
        \\func update(mut state: State, first: bool) -> int:
        \\    state.entries[1][0] = 9
        \\    if first:
        \\        return 1
        \\    return 2
        \\@ensures(old(copy(text)) == "old")
        \\func my_append(mut text: str):
        \\    text += "!"
        \\func main() -> int:
        \\    mut state = State(entries={1: [7]})
        \\    const first = update(mut state, True)
        \\    state.entries[1][0] = 7
        \\    const second = update(mut state, False)
        \\    mut text = "old"
        \\    my_append(mut text)
        \\    return first * 100 + second * 10 + strings.char_count(text)
    , 124);
}

// spec: CONTRACT-SYNTAX-1
test "contracts: contract clauses attach to functions and records and nowhere else" {
    try accepts(
        \\@invariant(self.low <= self.high)
        \\@invariant(self.low >= 0, "never negative")
        \\record Range:
        \\    low: int
        \\    high: int
        \\
        \\@invariant(self.value < 10u8)
        \\record Digit:
        \\    value: u8
        \\
        \\@requires(value < 10u8)
        \\func from(value: u8) -> Digit:
        \\    return Digit(value=value)
        \\
        \\@ensures(result < 10u8)
        \\func raw(value: Digit) -> u8:
        \\    return value.value
        \\
        \\@requires(x > 0)
        \\@requires(x < 100, "small")
        \\@ensures(result > x)
        \\func next[T](x: int, tag: T) -> int:
        \\    return x + 1
        \\
        \\func main() -> int:
        \\    mut same = from(3u8) == from(3u8)
        \\    if same:
        \\        return next(Range(low=1, high=2).high, 0)
        \\    else:
        \\        return 0
    );
    try rejects("@invariant(True)\nclass C:\n    x: int\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\nunion U:\n    A,\n    B\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\ndef f() -> int:\n    return 0\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@requires(True)\nrecord R:\n    x: int\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@requires(True)\nextern func f(host: Host) -> int\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@requires(True)\nconst X: int = 3;\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\ntype Count = int;\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@invariant(True)\nrecord Box[T]:\n    value: T\n\nfunc main() -> int:\n    return 0\n", "E_CONTRACT_TARGET");
    try rejects("@deprecated(\"old\")\nrecord D:\n    value: u8\n\nfunc main() -> int:\n    return 0\n", "E_ATTRIBUTE_TARGET");
    try rejects("@requires(1)\nfunc f(x: int) -> int:\n    return x\n\nfunc main() -> int:\n    return f(1)\n", "E_TYPE");
}

test "contracts: the @invariant wrong-target message names only the record declaration" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const checked = try fixture.check(arena.allocator(), "@invariant(True)\nunion U:\n    A,\n    B\n\nfunc main() -> int:\n    return 0\n");
    try t.expect(!checked.passed);
    try t.expectEqualStrings("E_CONTRACT_TARGET", checked.diagnostics[0].code);
    try t.expectEqualStrings(
        "`@invariant` attaches to a `record` declaration; a union, enum, alias, constraint or function carries none",
        checked.diagnostics[0].message,
    );
}

// spec: CONTRACT-REQUIRES-1
test "contracts: a broken precondition traps R_REQUIRES at its clause and names the caller" {
    const text =
        \\@requires(amount > 0, "amount must be positive")
        \\@requires(amount < 100)
        \\func half(amount: int) -> int:
        \\    return amount // 2
        \\
        \\func main() -> int:
        \\    mut first = half(8)
        \\    return first + half(first - 4)
    ;
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    const run = try traps(&c, .{ .code = "R_REQUIRES", .line = 1, .column = 11, .text = "half requires `amount > 0`: amount must be positive" });
    try t.expect(std.mem.indexOf(u8, run.stderr, "precondition violated") != null);
    try t.expect(std.mem.indexOf(u8, run.stderr, "broken by the caller main at contracts.selka:8:20") != null);
    try t.expectEqual(@as(usize, 2), run.trap.frames.len);
    try t.expectEqualStrings("main", run.trap.frames[1].function);
    // The clauses are checked in source order, and a precondition only sees
    // the parameters: a body local is not in scope.
    try returns("@requires(x > 0)\n@requires(x < 10)\nfunc f(x: int) -> int:\n    return x\n\nfunc main() -> int:\n    return f(9)\n", 9);
    try rejects("@requires(y > 0)\nfunc f(x: int) -> int:\n    mut y = x\n    return y\n\nfunc main() -> int:\n    return f(1)\n", "E_UNKNOWN_NAME");
}

// spec: CONTRACT-ENSURES-1
test "contracts: a broken postcondition traps R_ENSURES at every normal return and skips an Err" {
    var early = try language.Compilation.init(t.allocator, unit,
        \\@ensures(result < 10, "stays small")
        \\func clamp(x: int) -> int:
        \\    if x > 50:
        \\        return x
        \\    return 1
        \\
        \\func main() -> int:
        \\    return clamp(3) + clamp(60)
    );
    defer early.deinit();
    _ = try traps(&early, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "clamp ensures `result < 10`: stays small" });
    // A procedure's implicit end is a normal return too.
    var procedure = try language.Compilation.init(t.allocator, unit,
        \\@ensures(len(items) == 1)
        \\func fill(mut items: int[]):
        \\    append(mut items, 1)
        \\    append(mut items, 2)
        \\
        \\func main() -> int:
        \\    mut items: int[] = []
        \\    fill(mut items)
        \\    return 0
    );
    defer procedure.deinit();
    _ = try traps(&procedure, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "fill ensures `len(items) == 1`" });
    // An `Err` return and a `?` that propagates one skip the clause; an `Ok`
    // payload is `result`.
    try returns(
        \\@ensures(result > 100)
        \\func check(x: int) -> int fails str:
        \\    if x < 0:
        \\        fail "negative"
        \\    return x
        \\
        \\func relay(x: int) -> int fails str:
        \\    mut value = try check(x)
        \\    return value
        \\
        \\func main() -> int:
        \\    match relay(-1):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 7
    , 7);
    var ok = try language.Compilation.init(t.allocator, unit,
        \\@ensures(result > 100)
        \\func check(x: int) -> int fails str:
        \\    return x
        \\
        \\func main() -> int:
        \\    match check(5):
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 7
    );
    defer ok.deinit();
    _ = try traps(&ok, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "check ensures `result > 100`" });
    try rejects("@ensures(result > 0)\nfunc f(result: int) -> int:\n    return 1\n\nfunc main() -> int:\n    return f(1)\n", sema_contracts.result_code);
    try rejects("@ensures(result > 0)\nfunc f(x: int):\n    pass\n\nfunc main() -> int:\n    f(1)\n    return 0\n", sema_contracts.result_code);
}

// spec: CONTRACT-OLD-1
test "contracts: old captures an entry value once and rejects a shared one" {
    var grown = try language.Compilation.init(t.allocator, unit,
        \\@ensures(len(items) == old(len(items)) + 1, "adds exactly one")
        \\func add(mut items: int[], value: int):
        \\    append(mut items, value)
        \\    if value > 5:
        \\        append(mut items, value)
        \\
        \\func main() -> int:
        \\    mut items: int[] = []
        \\    add(mut items, 1)
        \\    add(mut items, 9)
        \\    return len(items)
    );
    defer grown.deinit();
    _ = try traps(&grown, .{ .code = "R_ENSURES", .line = 1, .column = 10, .text = "add ensures `len(items) == old(len(items)) + 1`: adds exactly one" });
    // In the default model, old(...) captures an independent value.
    try returns("@ensures(len(items) == len(old(copy(items))) + 1)\nfunc add(mut items: int[]):\n    append(mut items, 0)\n\nfunc main() -> int:\n    mut items = [1]\n    add(mut items)\n    return len(items)\n", 2);
    try returns("@ensures(len(old(copy(items))) == 1)\nfunc add(mut items: int[]):\n    append(mut items, 0)\n\nfunc main() -> int:\n    mut items = [1]\n    add(mut items)\n    return len(items)\n", 2);
    // W4: the capture of a managed value is a copy, so the source writes it; a bare `old(items)` is refused.
    try rejects("@ensures(len(old(items)) == 1)\nfunc add(mut items: int[]):\n    append(mut items, 0)\n\nfunc main() -> int:\n    mut items = [1]\n    add(mut items)\n    return len(items)\n", sema_contracts.old_copy_code);
    try rejects("@requires(old(x) > 0)\ndef f(x: int) -> int:\n    return x\n\nfunc main() -> int:\n    return f(1)\n", sema_contracts.old_code);
    try rejects("func f(x: int) -> int:\n    return old(x)\n\nfunc main() -> int:\n    return f(1)\n", sema_contracts.old_code);
    try rejects("@ensures(old(old(x)) > 0)\nfunc f(x: int) -> int:\n    return x\n\nfunc main() -> int:\n    return f(1)\n", sema_contracts.old_code);
}

// spec: CONTRACT-PURE-1
test "contracts: a contract condition may allocate but have no other effect" {
    try rejects(
        \\func shout(out: Stream) -> bool:
        \\    print(out, "checked")
        \\    return True
        \\
        \\@requires(shout(out))
        \\func f(out: Stream, x: int) -> int:
        \\    return x
        \\
        \\func main(out: Stream) -> int:
        \\    return f(out, 1)
    , sema_contracts.effect_code);
    try rejects("import lists\n\n\n@requires(lists.pop(mut items) > 0)\nfunc f(mut items: int[]) -> int:\n    return 1\n\nfunc main() -> int:\n    mut items = [1]\n    return f(mut items)\n", sema_contracts.effect_code);
    try rejects(
        \\func grow(mut items: int[]) -> bool:
        \\    append(mut items, 1)
        \\    return True
        \\
        \\@requires(grow(mut items))
        \\func f(mut items: int[]) -> int:
        \\    return 1
        \\
        \\func main() -> int:
        \\    mut items = [1]
        \\    return f(mut items)
    , sema_contracts.effect_code);
    try rejects(
        \\func half(x: int) -> int fails str:
        \\    return x // 2
        \\
        \\@ensures((try half(result)) > 0)
        \\func f(x: int) -> int fails str:
        \\    return x
        \\
        \\func main() -> int:
        \\    return 0
    , sema_contracts.effect_code);
    // An invariant sees only `self`, yet a field of it is still storage the
    // condition must not change.
    try rejects(
        \\import lists
        \\
        \\
        \\@invariant(lists.pop(mut self.items) >= 0)
        \\record Bag:
        \\    items: int[]
        \\
        \\func main() -> int:
        \\    return len(Bag(items=[1]).items)
    , sema_contracts.effect_code);
    // A condition only observes: it cannot take a result-bearing value away
    // from the body that still owns it.
    try rejects(
        \\func value_or(outcome: Result[int, str]) -> int:
        \\    match outcome:
        \\        case Ok(value):
        \\            return value
        \\        case Err(_):
        \\            return 0
        \\
        \\@requires(value_or(outcome) > 0)
        \\func f(outcome: Result[int, str]) -> int:
        \\    return value_or(outcome)
        \\
        \\func main() -> int:
        \\    return f(Ok(1))
    , sema_contracts.effect_code);
    // Allocation, a helper that only allocates, a comprehension's own list
    // and `debug` are all effect-free for a contract.
    try accepts(
        \\func positive(values: int[]) -> bool:
        \\    debug(values)
        \\    mut positive_values: int[] = []
        \\    for v in values:
        \\        if v > 0:
        \\            append(mut positive_values, v)
        \\    return len(positive_values) == len(values)
        \\
        \\@requires(positive([x, x + 1]))
        \\@ensures(str(result) != "")
        \\func f(x: int) -> int:
        \\    return x
        \\
        \\func main() -> int:
        \\    return f(1)
    );
}

/// One program body after a shared head and where its invariant trap is reported.
const InvariantCase = struct { body: []const u8, line: u64, column: u64, runtime_body: ?[]const u8 = null, runtime_column: ?u64 = null };

/// Run `head` followed by each case body and expect the `Range` invariant to
/// trap at the case's position.
fn expectInvariantTraps(head: []const u8, cases: []const InvariantCase) !void {
    for (cases) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ head, case.body });
        defer t.allocator.free(text);
        if (case.runtime_body != null) {
            var original = try language.Compilation.init(t.allocator, unit, text);
            defer original.deinit();
            try t.expectError(error.SourceError, original.check());
            try t.expectEqualStrings("E_TUPLE_REMOVED", original.diagnostics.items[0].code);
        }
        const runtime_text = try std.mem.concat(t.allocator, u8, &.{ head, case.runtime_body orelse case.body });
        defer t.allocator.free(runtime_text);
        var c = try language.Compilation.init(t.allocator, unit, runtime_text);
        defer c.deinit();
        _ = try traps(&c, .{ .code = "R_INVARIANT", .line = case.line, .column = case.runtime_column orelse case.column, .text = "Range invariant `self.low <= self.high`: ordered" });
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
        \\func main() -> int:
        \\
    ;
    try expectInvariantTraps(head, &.{
        .{ .body = "    mut r = Range(low=5, high=1)\n    return r.low\n", .line = 11, .column = 13 },
        .{ .body = "    mut r = Range(low=50)\n    return r.low\n", .line = 11, .column = 13 },
        .{ .body = "    mut r = Range(low=1, high=2)\n    r.low = 9\n    return r.low\n", .line = 12, .column = 5 },
        .{ .body = "    mut r = Range(low=1, high=2)\n    r.high -= 5\n    return r.low\n", .line = 12, .column = 5 },
        .{ .body = "    mut r = replace(Range(low=1, high=2), high=0)\n    return r.low\n", .line = 11, .column = 13 },
        .{ .body = "    mut w = Window(span=Range(low=1, high=2), label=0)\n    w.span.low = 7\n    return w.label\n", .line = 12, .column = 5 },
        // migrate-embedded: skip -- preserve the original tuple runtime-negative input.
        .{
            .body = "    mut r = Range(low=1, high=2)\n    r.low, r.high = 5, 4\n    return r.low\n",
            .line = 12,
            .column = 5,
            .runtime_body = "    mut r = Range(low=1, high=2)\n    r = replace(r, low=5, high=4)\n    return r.low\n",
            .runtime_column = 9,
        },
    });
    var original_domain = try language.Compilation.init(t.allocator, unit,
        // migrate-embedded: skip original invariant runtime-negative source; modern trap counterpart follows
        \\@invariant(self.value <= 1000u32)
        \\record Millimeters:
        \\    value: u32
        \\
        \\func from(value: u32) -> Millimeters:
        \\    return Millimeters(value=value)
        \\
        \\func main() -> int:
        \\    mut distance = from(2000u32)
        \\    return if (distance == distance) then (1) else (0)
    );
    defer original_domain.deinit();
    try t.expectError(error.SourceError, original_domain.check());
    try t.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", original_domain.diagnostics.items[0].code);
    var domain = try language.Compilation.init(t.allocator, unit,
        \\@invariant(self.value <= 1000u32)
        \\record Millimeters:
        \\    value: u32
        \\
        \\func from(value: u32) -> Millimeters:
        \\    return Millimeters(value=value)
        \\
        \\func main() -> int:
        \\    mut distance = from(2000u32)
        \\    if distance == distance:
        \\        return 1
        \\    else:
        \\        return 0
    );
    defer domain.deinit();
    _ = try traps(&domain, .{ .code = "R_INVARIANT", .line = 6, .column = 12, .text = "Millimeters invariant `self.value <= 1000u32`" });
    // A plain copy is not a change, and a value the invariant allows runs on.
    try returns(head ++ "    mut r = Range(low=1, high=2)\n    const copy = r\n    return copy.high\n", 2);
}

/// The head of the `match mut` write programs: `poke` writes `r.high`'s payload through a binding and leaves its arm.
const binding_write_head =
    \\enum Bound:
    \\    open
    \\    at(value: int)
    \\    span(lo: int, hi: int)
    \\
    \\
    \\func limit(b: Bound) -> int:
    \\    match b:
    \\        case at(value=v):
    \\            return v
    \\        case span(lo=lo, hi=hi):
    \\            return hi - lo
    \\        case open:
    \\            return 1000
    \\
    \\
    \\@invariant(self.low <= limit(self.high), "ordered")
    \\record Range:
    \\    low: int
    \\    high: Bound
    \\
    \\
    \\func failing() -> int fails str:
    \\    fail "boom"
    \\
    \\
    \\func lower(mut v: int, by: int):
    \\    v = v - by
    \\
    \\
    \\func poke(mut r: Range, k: int) -> int fails str:
    \\
;
const binding_write_tail =
    \\    return 0
    \\
    \\
    \\func main() -> int:
    \\    mut r = Range(low=0, high=Bound.at(value=10))
    \\    match poke(mut r, 0):
    \\        case Ok(n):
    \\            return n + limit(r.high)
    \\        case Err(_):
    \\            return 99
    \\
;

/// One `poke` body and where its write's invariant trap is reported.
const BindingWrite = struct { body: []const u8, line: u64, column: u64 };

/// The `match mut` write programs, one per way of leaving the arm after the write and per write form.
const binding_writes = [_]BindingWrite{
    // fallout
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            v = -1
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 34,
        .column = 13,
    },
    // return
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            v = -1
        \\            return 2
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 34,
        .column = 13,
    },
    // break
    .{
        .body =
        \\    for i in range(2):
        \\        match mut r.high:
        \\            case at(value=v):
        \\                v = -1
        \\                break
        \\            case span(lo=lo, hi=hi):
        \\                return 1
        \\            case open:
        \\                return 1
        \\
        ,
        .line = 35,
        .column = 17,
    },
    // continue
    .{
        .body =
        \\    for i in range(2):
        \\        match mut r.high:
        \\            case at(value=v):
        \\                v = -1
        \\                continue
        \\            case span(lo=lo, hi=hi):
        \\                return 1
        \\            case open:
        \\                return 1
        \\
        ,
        .line = 35,
        .column = 17,
    },
    // fail
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            v = -1
        \\            fail "stop"
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 34,
        .column = 13,
    },
    // try
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            v = -1
        \\            const n = try failing()
        \\            return n
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 34,
        .column = 13,
    },
    // plus
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            v += -11
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 34,
        .column = 13,
    },
    // mutarg
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            lower(mut v, 11)
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 34,
        .column = 13,
    },
    // loop
    .{
        .body =
        \\    match mut r.high:
        \\        case at(value=v):
        \\            for i in range(20):
        \\                v -= 1
        \\        case span(lo=lo, hi=hi):
        \\            pass
        \\        case open:
        \\            pass
        \\
        ,
        .line = 35,
        .column = 17,
    },
};

/// "trapped" when every binding write program traps `R_INVARIANT` at its write, else the first that did not.
fn everyBindingWriteTraps() ![]const u8 {
    for (binding_writes) |case| {
        const text = try std.mem.concat(t.allocator, u8, &.{ binding_write_head, case.body, binding_write_tail });
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, unit, text);
        defer c.deinit();
        const run = try native.run(&c);
        const at = run.trapped() and std.mem.eql(u8, run.trap.code, "R_INVARIANT") and run.trap.line == case.line and run.trap.column == case.column;
        if (!at or std.mem.indexOf(u8, run.stderr, "Range invariant `self.low <= limit(self.high)`: ordered") == null) return case.body;
    }
    return "trapped";
}

// FX7b (the user's decision of 13 November, "Check after writes"): a write through a `match mut` binding into the place
// a record with an invariant holds is checked at the write, as a direct write is, however the arm is left after it.
test "contracts: a write through a match mut binding traps R_INVARIANT at the write, whatever leaves the arm after it" {
    try t.expectEqualStrings("trapped", try everyBindingWriteTraps());
    // A write the invariant allows runs on: 0 from `poke`, then the limit 3.
    try returns(binding_write_head ++ "    match mut r.high:\n        case at(value=v):\n            v = 3\n        case span(lo=lo, hi=hi):\n" ++
        "            pass\n        case open:\n            pass\n" ++ binding_write_tail, 3);
}

// FX7b: two writes through bindings, the first breaking an invariant over two payload fields and the second repairing
// it, trap at the first, as two direct writes do.
test "contracts: of two match mut writes the first that breaks the invariant traps, though the second would repair it" {
    var c = try language.Compilation.init(t.allocator, unit,
        \\enum Bound:
        \\    open
        \\    span(lo: int, hi: int)
        \\
        \\
        \\func limit(b: Bound) -> int:
        \\    match b:
        \\        case span(lo=lo, hi=hi):
        \\            return hi - lo
        \\        case open:
        \\            return 1000
        \\
        \\
        \\@invariant(limit(self.high) >= 0, "ordered")
        \\record Range:
        \\    low: int
        \\    high: Bound
        \\
        \\
        \\func main() -> int:
        \\    mut r = Range(low=0, high=Bound.span(lo=1, hi=5))
        \\    match mut r.high:
        \\        case span(lo=lo, hi=hi):
        \\            lo = 9
        \\            hi = 20
        \\        case open:
        \\            return 1
        \\    return limit(r.high)
        \\
    );
    defer c.deinit();
    _ = try traps(&c, .{ .code = "R_INVARIANT", .line = 24, .column = 13, .text = "Range invariant `limit(self.high) >= 0`: ordered" });
}

// spec: CONTRACT-TRAP-1
test "contracts: a run reports the contract's own trap code" {
    const text = "@requires(x > 0)\nfunc f(x: int) -> int:\n    return x\n\nfunc main() -> int:\n    return f(0)\n";
    var accounted = try language.Compilation.init(t.allocator, unit, text);
    defer accounted.deinit();
    _ = try traps(&accounted, .{ .code = "R_REQUIRES", .line = 1, .column = 11, .text = "f requires `x > 0`" });
    // A plain `assert` keeps `R_ASSERT`.
    var plain = try language.Compilation.init(t.allocator, unit, "func main() -> int:\n    assert 1 > 2, \"R_REQUIRES looks alike\"\n    return 0\n");
    defer plain.deinit();
    const asserted = try native.run(&plain);
    try t.expectEqualStrings("R_ASSERT", asserted.trap.code);
}

fn assertPrefixStaysLiteral(prefix: []const u8) !void {
    const text = try std.fmt.allocPrint(t.allocator, "func main() -> int:\n    assert False, \"{s}: ordinary assertion\"\n    return 0\n", .{prefix});
    defer t.allocator.free(text);
    var c = try language.Compilation.init(t.allocator, unit, text);
    defer c.deinit();
    const accounted = try native.run(&c);
    try t.expectEqualStrings("R_ASSERT", accounted.trap.code);
    try t.expect(std.mem.indexOf(u8, accounted.stderr, prefix) != null);
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
    const record = "x.selka:1:2: error[R_ENSURES]: postcondition violated: f ensures `result > 0`: why\n" ++ trap_detail.marker ++ "{\"version\":1,\"operation\":\"f ensures `result > 0`: why\"}\n";
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
        \\    spans: Span[]
        \\    best: Span?
        \\
        \\record ArgumentPair:
        \\    first: Span
        \\    second: int
        \\
        \\func test_holder(holder: Holder, keyed: dict[str, Span], pair: ArgumentPair) -> bool:
        \\    const first = pair.first
        \\    return len(holder.spans) + len(keyed) == 3 and first.low == 1
        \\
        \\func plain(holder: Holder) -> int:
        \\    return len(holder.spans)
        \\
        \\func main() -> int:
        \\    mut holder = Holder(spans=[Span(low=1, high=2), Span(low=3, high=3)], best=Some(Span(low=0, high=9)))
        \\    mut passed = test_holder(holder, {"a": Span(low=-1, high=1)}, ArgumentPair(first=Span(low=1, high=4), second=0))
        \\    const base = plain(holder)
        \\    if passed:
        \\        return base + 40
        \\    else:
        \\        return base + 0
    , 42);
}

// spec-case: DOMAIN-REMOVED-1
test "contracts original domain invariant trap source retains its retirement diagnostic" {
    // migrate-embedded: skip original C0 runtime-negative source; modern runtime counterpart remains above
    var legacy_0 = try language.Compilation.init(t.allocator, "original-retirement.selka",
        \\@invariant(unwrap(self) <= 1000u32)
        \\domain Millimeters: u32:
        \\    func from(value: u32) -> Millimeters:
        \\        return wrap[Millimeters](value)
        \\
        \\func main() -> int:
        \\    mut distance = Millimeters.from(2000u32)
        \\    return if (distance == distance) then (1) else (0)
    );
    defer legacy_0.deinit();
    try t.expectError(error.SourceError, legacy_0.check());
    try t.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", legacy_0.diagnostics.items[0].code);
    // Remove only the nested retired selection to expose the original domain refusal.
    const domain_only = try std.mem.replaceOwned(u8, t.allocator, legacy_0.src.bytes, "return if (distance == distance) then (1) else (0)", "if distance == distance:\n        return 1\n    else:\n        return 0");
    defer t.allocator.free(domain_only);
    var domain_legacy = try language.Compilation.init(t.allocator, "domain-retirement.selka", domain_only);
    defer domain_legacy.deinit();
    try t.expectError(error.SourceError, domain_legacy.check());
    const found_0 = for (domain_legacy.diagnostics.items) |item| {
        if (std.mem.eql(u8, item.code, "E_DOMAIN_REMOVED")) break true;
    } else false;
    try t.expect(found_0);
}

test "contracts: a postcondition on a Unit-fails function builds and checks only its success return" {
    // The proof-steps trial's D1: binding the `Unit` payload of the success
    // case, as the postcondition's own check does, once crashed the build.
    const need =
        \\enum Shortage:
        \\    Truncated
        \\
        \\@ensures(count > 5)
        \\func need(count: int) -> Unit fails Shortage:
        \\    if count < 0:
        \\        fail Shortage.Truncated
        \\    return ()
        \\
        \\func main() -> int:
        \\
    ;
    try returns(need ++ "    match need(-1):\n        case Ok(_):\n            return 0\n        case Err(_):\n            return 7\n", 7);
    try returns(need ++ "    match need(9):\n        case Ok(value):\n            _ = value\n            return 3\n        case Err(_):\n            return 7\n", 3);
    var broken = try language.Compilation.init(t.allocator, unit, need ++ "    match need(1):\n        case Ok(_):\n            return 0\n        case Err(_):\n            return 7\n");
    defer broken.deinit();
    _ = try traps(&broken, .{ .code = "R_ENSURES", .line = 4, .column = 10, .text = "need ensures `count > 5`" });
}

test "contracts: an invariant on a record with a managed field checks a store through a mut parameter after the write" {
    // The proof-steps trial's D2: the check once moved the parameter's record
    // into a hidden local (E_SINGLE_OWNER_BORROW, rule M1); it now reads the
    // written place back, so the store checks and a broken write traps there.
    const head =
        \\@invariant(self.line >= 1)
        \\record Cursor:
        \\    source: bytes
        \\    pos: int
        \\    line: int
        \\
        \\func step(mut cursor: Cursor, k: int):
        \\    cursor.pos = k
        \\    cursor.line = k + 1
        \\
        \\func main() -> int:
        \\    mut cursor = Cursor(source=b"abc", pos=0, line=1)
        \\
    ;
    try returns(head ++ "    step(mut cursor, 2)\n    return cursor.line + len(cursor.source)\n", 6);
    var broken = try language.Compilation.init(t.allocator, unit, head ++ "    step(mut cursor, -1)\n    return cursor.line\n");
    defer broken.deinit();
    _ = try traps(&broken, .{ .code = "R_INVARIANT", .line = 9, .column = 5, .text = "Cursor invariant `self.line >= 1`" });
}

test "contracts: take, exchange and an in-place update of a field check the record's invariant after the write" {
    // Proof-steps open item O-1: a `take`, an `exchange`, a collection update
    // or a `mut` argument on a field wrote the place without a record update,
    // so no invariant ran and the record was left in a state its type rules
    // out. Each now checks the record after the write and traps there.
    const head =
        \\@invariant(len(self.items) >= 1, "never empty")
        \\record Bag:
        \\    items: int[]
        \\    line: int
        \\
        \\func filled(k: int) -> int[]:
        \\    mut out: int[] = []
        \\    for i in range(k):
        \\        append(mut out, i)
        \\    return out
        \\
        \\func empty(mut items: int[]):
        \\    items = []
        \\
        \\func swap(mut bag: Bag, k: int) -> int:
        \\    const old = exchange(mut bag.items, filled(k))
        \\    return len(old)
        \\
        \\func grow(mut bag: Bag, k: int):
        \\    append(mut bag.items, k)
        \\    empty(mut bag.items)
        \\
        \\func through(hook: func(mut items: int[]) -> Unit, mut bag: Bag):
        \\    hook(mut bag.items)
        \\
        \\func main() -> int:
        \\    mut bag = Bag(items=[1, 2], line=1)
        \\
    ;
    try returns(head ++ "    const old = swap(mut bag, 3)\n    return old + len(bag.items)\n", 5);
    var taken = try language.Compilation.init(t.allocator, unit, head ++ "    const got = take(mut bag.items)\n    return len(got)\n");
    defer taken.deinit();
    _ = try traps(&taken, .{ .code = "R_INVARIANT", .line = 28, .column = 17, .text = "Bag invariant `len(self.items) >= 1`: never empty" });
    var exchanged = try language.Compilation.init(t.allocator, unit, head ++ "    return swap(mut bag, 0)\n");
    defer exchanged.deinit();
    _ = try traps(&exchanged, .{ .code = "R_INVARIANT", .line = 16, .column = 17, .text = "Bag invariant `len(self.items) >= 1`" });
    var cleared = try language.Compilation.init(t.allocator, unit, head ++ "    grow(mut bag, 4)\n    return len(bag.items)\n");
    defer cleared.deinit();
    _ = try traps(&cleared, .{ .code = "R_INVARIANT", .line = 21, .column = 5, .text = "Bag invariant `len(self.items) >= 1`" });
    var hooked = try language.Compilation.init(t.allocator, unit, head ++ "    through(empty, mut bag)\n    return len(bag.items)\n");
    defer hooked.deinit();
    _ = try traps(&hooked, .{ .code = "R_INVARIANT", .line = 24, .column = 5, .text = "Bag invariant `len(self.items) >= 1`" });
}

test "contracts: a write that breaks an invariant over several fields says the fields can be written together with replace" {
    // SP2-F-8: the first of two writes that restore an invariant over two fields traps, and the trap named no way out.
    const head =
        \\@invariant(self.count + len(self.free) <= len(self.keys), "every key and every free slot has a slot")
        \\record Slots:
        \\    keys: int[]
        \\    free: int[]
        \\    count: int
        \\
        \\func release(mut t: Slots, slot: int):
        \\    append(mut t.free, slot)
        \\    t.count = t.count - 1
        \\
        \\func store(mut t: Slots, slot: int):
        \\    t.free = [slot]
        \\    t.count = t.count - 1
        \\
        \\func together(mut t: Slots, slot: int):
        \\    const left = t.count - 1
        \\    t = replace(t, free=[slot], count=left)
        \\
        \\func main() -> int:
        \\    mut t = Slots(keys=[1, 2], free=[], count=2)
        \\
    ;
    const hint = "Slots invariant `self.count + len(self.free) <= len(self.keys)`: every key and every free slot has a slot; " ++
        "each write is checked on its own: to change the fields this invariant relates (count, free, keys) together, " ++
        "write them in one replace(record, field=value, ...)";
    var appended = try language.Compilation.init(t.allocator, unit, head ++ "    release(mut t, 0)\n    return t.count\n");
    defer appended.deinit();
    _ = try traps(&appended, .{ .code = "R_INVARIANT", .line = 8, .column = 5, .text = hint });
    var stored = try language.Compilation.init(t.allocator, unit, head ++ "    store(mut t, 0)\n    return t.count\n");
    defer stored.deinit();
    _ = try traps(&stored, .{ .code = "R_INVARIANT", .line = 12, .column = 5, .text = hint });
    // The repair the hint names: the two fields in one `replace`, which is checked once, after both.
    try returns(head ++ "    together(mut t, 0)\n    return t.count + len(t.free)\n", 2);
    // A construction is checked whole, so it says nothing of writes; neither does an invariant over one field.
    var built = try language.Compilation.init(t.allocator, unit, head ++ "    t = Slots(keys=[1], free=[2], count=1)\n    return t.count\n");
    defer built.deinit();
    const constructed = try traps(&built, .{ .code = "R_INVARIANT", .line = 21, .column = 9, .text = "Slots invariant `self.count + len(self.free) <= len(self.keys)`: every key and every free slot has a slot" });
    try t.expect(std.mem.indexOf(u8, constructed.stderr, "each write is checked") == null);
    var single = try language.Compilation.init(t.allocator, unit,
        \\@invariant(self.count >= 0, "never negative")
        \\record Counter:
        \\    count: int
        \\
        \\func main() -> int:
        \\    mut c = Counter(count=1)
        \\    c.count = -1
        \\    return c.count
        \\
    );
    defer single.deinit();
    const narrow = try traps(&single, .{ .code = "R_INVARIANT", .line = 7, .column = 5, .text = "Counter invariant `self.count >= 0`: never negative" });
    try t.expect(std.mem.indexOf(u8, narrow.stderr, "each write is checked") == null);
}

test "contracts: a body local named result resolves at a return after a loop and stays bound" {
    // The proof-steps trial's D3: the postcondition's hidden `result` holder,
    // made inside an inner block, once took the body's own `result` out of
    // scope when that block ended.
    const counting =
        \\@ensures(position > old(position))
        \\func count_up(mut position: int) -> int:
        \\    mut result = 0
        \\    while True:
        \\        result += 1
        \\        if result > 3:
        \\            position += 1
        \\            return result
        \\    return result
        \\
        \\func main() -> int:
        \\    mut position = 0
        \\    return count_up(mut position)
    ;
    try returns(counting, 4);
    // The local stays an active name after the inner return, so it cannot be declared again.
    try rejects(
        \\@ensures(result >= 0)
        \\func f(k: int) -> int:
        \\    const result = 1
        \\    if k > 5:
        \\        return result
        \\    const result = 3
        \\    return result
        \\
        \\func main() -> int:
        \\    return f(1)
    , "E_SHADOWING");
}
