//! Checker rules for parallel task groups (E1): `with parallel.group() as g:`, `g.submit(fn, ARGS)`,
//! `t.result()` and the `E_TASK_*` refusals of concurrency plan 2 §6.2. These are check-only tests: the
//! lowering has its own tests (`task_group_lower_test.zig`), and the last test here pins that a group program builds.
const std = @import("std");
const language = @import("selka");
const support = @import("test_support.zig");
const build = @import("build.zig");
const ownership = @import("single_owner.zig");

/// Print a failing check's diagnostics to the test's stderr.
const report = std.debug.print;

/// The declarations every rule program shares: one pure function of each shape a submit can take.
const declarations =
    // migrate-embedded: skip shared declaration prefix keeps the parallel import required by concatenated test guests
    \\import parallel
    \\
    \\func double(value: int) -> int:
    \\    return value * 2
    \\
    \\func total(values: int[]) -> int:
    \\    mut sum = 0
    \\    for value in values:
    \\        sum += value
    \\    return sum
    \\
    \\func scale(values: int[], weight: int) -> int:
    \\    return len(values) * weight
    \\
    \\func load(path: str) -> int fails str:
    \\    if len(path) == 0:
    \\        fail "empty path"
    \\    return len(path)
    \\
    \\func bump(mut n: int) -> int:
    \\    n += 1
    \\    return n
    \\
    \\func tick(n: int):
    \\    return
    \\
;

/// The declarations with a `main` that returns zero: the entry every rule program checks against.
const header = declarations ++ "func main() -> int:\n    return 0\n";

/// A group whose two handles are both read: the shape every lowering test starts from.
const two_handles =
    \\func go(board: int[]) -> int:
    \\    with parallel.group() as g:
    \\        const a = g.submit(total, board)
    \\        const b = g.submit(total, board)
    \\        return a.result() + b.result()
    \\
;

/// Check the header and `body` as one program, with an arena the caller frees.
fn check(arena: std.mem.Allocator, body: []const u8) !support.Checked {
    return support.checkSource(arena, try std.mem.concat(arena, u8, &.{ header, body }));
}

/// Whether the program checks and holds no error.
fn accepted(allocator: std.mem.Allocator, body: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    if (!checked.passed) for (checked.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
    return checked.passed;
}

/// Whether the program is refused and one of its diagnostics has `code`.
fn refusedWith(allocator: std.mem.Allocator, body: []const u8, code: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    if (checked.passed) report("expected {s}, but the program checked\n", .{code});
    if (checked.passed) return false;
    for (checked.diagnostics) |item| if (std.mem.eql(u8, item.code, code)) return true;
    for (checked.diagnostics) |item| report("expected {s}, got {s}: {s}\n", .{ code, item.code, item.message });
    return false;
}

/// Conflict typing succeeds; Core checks the loan lasting until the group closes.
fn refusedLoan(allocator: std.mem.Allocator, body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    try std.testing.expect(checked.passed);
    var failure: ownership.Failure = .{};
    try std.testing.expectError(error.Rejected, ownership.checkWithSource(arena.allocator(), checked.program.?, checked.src.?, &failure));
    try std.testing.expectEqualStrings("E_TASK_LOAN", failure.code);
    try std.testing.expectEqual(language.ownership_rules.Rule.K1, failure.rule.?);
}

/// Whether a diagnostic with `code` says `needle` somewhere in its message.
fn refusedMessageHas(allocator: std.mem.Allocator, body: []const u8, code: []const u8, needle: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    for (checked.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, code)) continue;
        if (std.mem.indexOf(u8, item.message, needle) != null) return true;
    }
    return false;
}

/// Whether the complete program `text` (with its own imports) is refused with `code`.
fn refusedSource(allocator: std.mem.Allocator, text: []const u8, code: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), text);
    if (checked.passed) return false;
    for (checked.diagnostics) |item| if (std.mem.eql(u8, item.code, code)) return true;
    return false;
}

/// The typed task nodes of a checked program: one count per kind.
const TaskCounts = struct { opens: usize = 0, submits: usize = 0, results: usize = 0 };

/// Count the group, submit and result nodes of a checked program.
fn countTaskNodes(program: language.typed.Program) TaskCounts {
    var counts: TaskCounts = .{};
    for (program.nodes) |node| switch (node.data) {
        .task_group_open => counts.opens += 1,
        .task_submit => counts.submits += 1,
        .task_result => counts.results += 1,
        else => {},
    };
    return counts;
}

const fallible_try =
    \\func go() -> int fails str:
    \\    with parallel.group() as g:
    \\        const t = g.submit(load, "abc")
    \\        const n = try t.result()
    \\        return n
    \\
;

const fallible_match =
    \\func go() -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(load, "abc")
    \\        match t.result():
    \\            case Ok(value):
    \\                return value
    \\            case Err(error):
    \\                return 0
    \\
;

const bare_unit =
    \\func go() -> int:
    \\    mut counter = 0
    \\    with parallel.group() as g:
    \\        g.submit(tick, counter)
    \\    return counter
    \\
;

const loop_handles =
    \\func go(data: int[]) -> int:
    \\    mut sum = 0
    \\    with parallel.group() as g:
    \\        for value in data:
    \\            const t = g.submit(double, value)
    \\            sum += t.result()
    \\    return sum
    \\
;

const nested_groups =
    \\func go() -> int:
    \\    mut out = 0
    \\    with parallel.group() as outer:
    \\        const a = outer.submit(double, 3)
    \\        with parallel.group() as inner:
    \\            const b = inner.submit(double, 4)
    \\            out = b.result()
    \\        out += a.result()
    \\    return out
    \\
;

const while_continue =
    \\func go(limit: int) -> int:
    \\    mut i = 0
    \\    mut sum = 0
    \\    while i < limit:
    \\        i += 1
    \\        with parallel.group() as g:
    \\            const t = g.submit(double, i)
    \\            if i == 2:
    \\                continue
    \\            sum += t.result()
    \\    return sum
    \\
;

const label_ok =
    \\func go() -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(scale, [1, 2], weight=2)
    \\        return t.result()
    \\
;

const loan_read =
    \\func go() -> int:
    \\    mut data = [1, 2, 3]
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, data)
    \\        const n = len(data)
    \\        return t.result() + n
    \\
;

const loan_after_block =
    \\func go() -> int:
    \\    mut data = [1, 2, 3]
    \\    mut sum = 0
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, data)
    \\        sum = t.result()
    \\    data[0] = 9
    \\    return sum + data[0]
    \\
;

const loan_write =
    \\func go() -> int:
    \\    mut data = [1, 2, 3]
    \\    mut sum = 0
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, data)
    \\        data[0] = 9
    \\        sum = t.result()
    \\    return sum
    \\
;

const loan_mut_pass =
    \\func go() -> int:
    \\    mut data = [1, 2, 3]
    \\    mut sum = 0
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, data)
    \\        append(mut data, 4)
    \\        sum = t.result()
    \\    return sum
    \\
;

const loan_own_move =
    \\func consume(own values: int[]) -> int:
    \\    return len(values)
    \\
    \\func go() -> int:
    \\    mut data = [1, 2, 3]
    \\    mut sum = 0
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, data)
    \\        const k = g.submit(consume, own data)
    \\        sum = t.result() + k.result()
    \\    return sum
    \\
;

const loop_mut_handle =
    \\func go(data: int[]) -> int:
    \\    mut sum = 0
    \\    with parallel.group() as g:
    \\        for value in data:
    \\            mut t = g.submit(double, value)
    \\            sum += t.result()
    \\    return sum
    \\
;

const mut_argument =
    \\func go() -> int:
    \\    mut counter = 0
    \\    with parallel.group() as g:
    \\        const t = g.submit(bump, mut counter)
    \\        return t.result()
    \\
;

const host_argument =
    \\func probe(host: Host, n: int) -> int:
    \\    return n
    \\
    \\func go(host: Host) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(probe, host, 3)
    \\        return t.result()
    \\
;

const resource_argument =
    \\resource Poller: network
    \\
    \\record Session:
    \\    poller: Poller
    \\
    \\func use(own session: Session) -> int:
    \\    return 1
    \\
    \\func go(own session: Session) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(use, own session)
    \\        return t.result()
    \\
;

test "task groups: the accepted shapes check" {
    try std.testing.expect(try accepted(std.testing.allocator, two_handles));
    try std.testing.expect(try accepted(std.testing.allocator, fallible_try));
    try std.testing.expect(try accepted(std.testing.allocator, fallible_match));
    try std.testing.expect(try accepted(std.testing.allocator, bare_unit));
    try std.testing.expect(try accepted(std.testing.allocator, loop_handles));
    try std.testing.expect(try accepted(std.testing.allocator, nested_groups));
    try std.testing.expect(try accepted(std.testing.allocator, while_continue));
}

test "task groups: a group opens only as a with scope with a name and no arguments" {
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    const g = parallel.group()\n    return 0\n", "E_TASK_GROUP"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group():\n        return 0\n", "E_TASK_GROUP"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group(3) as g:\n        return 0\n", "E_TASK_GROUP"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.spawn(double, 3)\n        return t.result()\n", "E_TASK_GROUP"));
}

test "task groups: a group or handle does not escape its block" {
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const h = g\n        return 0\n", "E_TASK_ESCAPE"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func keep(n: int) -> int:\n    return n\n\nfunc go() -> int:\n    with parallel.group() as g:\n        return keep(g)\n", "E_TASK_ESCAPE"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(double, 3)\n        const copy_of = t\n        return copy_of.result()\n", "E_TASK_ESCAPE"));
}

test "task handles initialise a const binding and nothing else" {
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        mut t = g.submit(double, 3)\n        return t.result()\n", "E_TASK_HANDLE"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        return g.submit(double, 3).result()\n", "E_TASK_HANDLE"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(double, 3)\n        return t.wait()\n", "E_TASK_HANDLE"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(double, 3)\n        return t.result(1)\n", "E_TASK_HANDLE"));
}

test "task handles inside a loop point the repair at parallel.map" {
    try std.testing.expect(try refusedWith(std.testing.allocator, loop_mut_handle, "E_TASK_HANDLE"));
    try std.testing.expect(try refusedMessageHas(std.testing.allocator, loop_mut_handle, "E_TASK_HANDLE", "parallel.map"));
}

test "the loop hint of a task handle writes parallel.map's arguments in the order of the call" {
    try std.testing.expect(try refusedMessageHas(
        std.testing.allocator,
        loop_mut_handle,
        "E_TASK_HANDLE",
        "a task handle must initialise a `const` binding, as in `const t = g.submit(fn, ARGS)`; inside a loop, `parallel.map(values, fn, ARGS)` runs one task per item and collects the results",
    ));
    try std.testing.expect(!try refusedMessageHas(std.testing.allocator, loop_mut_handle, "E_TASK_HANDLE", "parallel.map(fn, items"));
}

test "task handles are read with result before their block ends" {
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(double, 3)\n        return 0\n", "E_TASK_RESULT_UNREAD"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        g.submit(double, 3)\n        return 0\n", "E_TASK_RESULT_UNREAD"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        g.submit(load, \"abc\")\n        return 0\n", "E_TASK_RESULT_UNREAD"));
}

test "task submit refuses a mut argument and names the owned alternative" {
    try std.testing.expect(try refusedWith(std.testing.allocator, mut_argument, "E_TASK_MUT"));
    try std.testing.expect(try refusedMessageHas(std.testing.allocator, mut_argument, "E_TASK_MUT", "own"));
}

test "task submit refuses the Host capability" {
    try std.testing.expect(try refusedWith(std.testing.allocator, host_argument, "E_TASK_HOST"));
}

test "task submit refuses an argument that holds an owned resource" {
    try std.testing.expect(try refusedWith(std.testing.allocator, resource_argument, "E_TASK_RESOURCE"));
}

test "task submit checks its arguments exactly as a direct call does" {
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(double, 3, 4)\n        return t.result()\n", "E_ARITY"));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(scale, [1], factor=2)\n        return t.result()\n", "E_CALL_ARGUMENT"));
    try std.testing.expect(try accepted(std.testing.allocator, label_ok));
    try std.testing.expect(try refusedWith(std.testing.allocator, "func go() -> int:\n    with parallel.group() as g:\n        const t = g.submit(double(3), 1)\n        return t.result()\n", "E_TASK_GROUP"));
}

test "task groups: a lent owner is read-only until its group closes" {
    try refusedLoan(std.testing.allocator, loan_write);
    try refusedLoan(std.testing.allocator, loan_mut_pass);
    try refusedLoan(std.testing.allocator, loan_own_move);
    try std.testing.expect(try accepted(std.testing.allocator, loan_read));
    try std.testing.expect(try accepted(std.testing.allocator, loan_after_block));
}

test "task groups: the typed tree carries the group, submit and result nodes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), two_handles);
    try std.testing.expect(checked.passed);
    const counts = countTaskNodes(checked.program.?);
    try std.testing.expectEqual(@as(usize, 1), counts.opens);
    try std.testing.expectEqual(@as(usize, 2), counts.submits);
    try std.testing.expectEqual(@as(usize, 2), counts.results);
}

test "task groups: build lowers a program that opens a group" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var refusal: build.Refusal = .{};
    // `main` calls the group function: only what `main` reaches is lowered, so the program needs a caller.
    const source = try std.mem.concat(arena.allocator(), u8, &.{ declarations, two_handles, "func main() -> int:\n    return go([1, 2, 3])\n" });
    _ = try support.buildSource(arena.allocator(), source, &refusal);
    try std.testing.expectEqual(@as(usize, 0), refusal.reason.len);
}

/// A Unit function over a managed value, so a bare submit of it is accepted and its argument is a managed owner.
const show_declaration =
    \\func show(values: int[]):
    \\    return
    \\
;

/// A bare submit of a value declared in a loop body: the loop's drop comes before the join (E1b).
const lent_in_loop =
    \\func go(data: int[]) -> int:
    \\    with parallel.group() as g:
    \\        for value in data:
    \\            const fresh = [value, value]
    \\            g.submit(show, fresh)
    \\    return 0
    \\
;

/// A handle submit of a value declared in a branch: its result read does not keep the value alive.
const lent_in_branch =
    \\func go(flag: int) -> int:
    \\    with parallel.group() as g:
    \\        if flag > 0:
    \\            const fresh = [flag, flag]
    \\            const t = g.submit(total, fresh)
    \\            return t.result()
    \\        return 0
    \\
;

/// A handle submit of a value declared in a `while` body (another nested block).
const lent_in_while =
    \\func go(limit: int) -> int:
    \\    mut i = 0
    \\    with parallel.group() as g:
    \\        while i < limit:
    \\            i += 1
    \\            const fresh = [i, i]
    \\            const t = g.submit(total, fresh)
    \\            return t.result()
    \\        return 0
    \\
;

/// Values declared before the `with` and at its top level: both outlive the join, and both are accepted.
const lent_outliving =
    \\func go(data: int[]) -> int:
    \\    const before = [1, 2, 3]
    \\    with parallel.group() as g:
    \\        const top = [data[0], 2]
    \\        const t = g.submit(total, top)
    \\        g.submit(show, before)
    \\        return t.result() + total(before)
    \\
;

/// A scalar loop variable is copied into the task, so it is not an owner and needs no join-order rule.
const scalar_loop_variable =
    \\func go(data: int[]) -> int:
    \\    with parallel.group() as g:
    \\        for value in data:
    \\            g.submit(tick, value)
    \\    return 0
    \\
;

/// A handle's result read twice: the first read takes the value out of the task (E1b).
const second_read =
    \\func go() -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(double, 3)
    \\        const a = t.result()
    \\        return a + t.result()
    \\
;

test "task groups: a value lent to a task that is declared in a nested block is refused" {
    try std.testing.expect(try refusedWith(std.testing.allocator, show_declaration ++ lent_in_loop, "E_TASK_LOAN"));
    try std.testing.expect(try refusedWith(std.testing.allocator, lent_in_branch, "E_TASK_LOAN"));
    try std.testing.expect(try refusedWith(std.testing.allocator, lent_in_while, "E_TASK_LOAN"));
}

test "task groups: a value lent to a task that outlives its group, or a scalar copy, is accepted" {
    try std.testing.expect(try accepted(std.testing.allocator, show_declaration ++ lent_outliving));
    try std.testing.expect(try accepted(std.testing.allocator, show_declaration ++ scalar_loop_variable));
}

test "task groups: a task's result can be read once" {
    try std.testing.expect(try refusedWith(std.testing.allocator, second_read, "E_TASK_HANDLE"));
}

/// A managed list element lent directly: refused, because the ownership pass cannot lend an element (E1b).
const element_refused =
    \\func go() -> int:
    \\    const rows = [[1, 2], [3]]
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, rows[1])
    \\        return t.result()
    \\
;

/// The same element bound to a top-level local first: accepted.
const element_bound =
    \\func go() -> int:
    \\    const rows = [[1, 2], [3]]
    \\    with parallel.group() as g:
    \\        const row = rows[1]
    \\        const t = g.submit(total, row)
    \\        return t.result()
    \\
;

/// A scalar list element is copied into the task, so it is accepted.
const scalar_element =
    \\func go() -> int:
    \\    const xs = [1, 2, 3]
    \\    with parallel.group() as g:
    \\        const t = g.submit(double, xs[1])
    \\        return t.result()
    \\
;

/// A dictionary value lent directly: accepted (its drop follows the join, as the lowering test shows).
const dict_value =
    \\func go() -> int:
    \\    const table = {"k": [7, 8]}
    \\    with parallel.group() as g:
    \\        const t = g.submit(total, table["k"])
    \\        return t.result()
    \\
;

test "task groups: a managed list element lent directly is refused; a bound element, a scalar and a dictionary value are accepted" {
    try std.testing.expect(try refusedWith(std.testing.allocator, element_refused, "E_TASK_LOAN"));
    try std.testing.expect(try accepted(std.testing.allocator, element_bound));
    try std.testing.expect(try accepted(std.testing.allocator, scalar_element));
    try std.testing.expect(try accepted(std.testing.allocator, dict_value));
}

test "task groups: a borrowed call result given to a task directly is refused, and its copy is accepted" {
    const design =
        \\record Design:
        \\    name: str
        \\    nets: int[]
        \\
        \\func nets_of(design: Design) -> int[] from design:
        \\    return design.nets
        \\
        \\
    ;
    const bare =
        \\func go(d: Design) -> int:
        \\    with parallel.group() as g:
        \\        const t = g.submit(scale, nets_of(d), 2)
        \\        return t.result()
        \\
    ;
    const copied =
        \\func go(d: Design) -> int:
        \\    with parallel.group() as g:
        \\        const t = g.submit(scale, copy(nets_of(d)), 2)
        \\        return t.result()
        \\
    ;
    try std.testing.expect(try refusedWith(std.testing.allocator, design ++ bare, "E_TASK_LOAN"));
    try std.testing.expect(try accepted(std.testing.allocator, design ++ copied));
}

test "task groups: a two-source selection given to a task directly is refused" {
    const text =
        \\func measure(text: str) -> int:
        \\    return len(text)
        \\
        \\func go(first: str, second: str) -> int:
        \\    with parallel.group() as g:
        \\        const t = g.submit(measure, min(first, second))
        \\        return t.result()
        \\
    ;
    try std.testing.expect(try refusedWith(std.testing.allocator, text, "E_TASK_LOAN"));
}

test "task groups: a dictionary lookup with a fallback given to a task directly is refused" {
    const text =
        \\import dicts
        \\import parallel
        \\
        \\func scale(values: int[], weight: int) -> int:
        \\    return len(values) * weight
        \\
        \\func go(table: dict[int, int[]], fallback: int[]) -> int:
        \\    with parallel.group() as g:
        \\        const t = g.submit(scale, dicts.get(table, 1, fallback), 2)
        \\        return t.result()
        \\
        \\func main() -> int:
        \\    return 0
        \\
    ;
    try std.testing.expect(try refusedSource(std.testing.allocator, text, "E_TASK_LOAN"));
}
