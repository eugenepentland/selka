//! W28 (D-W28-1): a task may not take a capability that reads or writes the outside world. `E_TASK_CAPABILITY` refuses
//! every capability type but `Host` (which keeps `E_TASK_HOST`) as a `g.submit` argument, as a `parallel.map` trailing
//! argument and as the items of a map, directly and inside a record, list, dictionary, option or union. A value that holds
//! no capability is accepted as before. These are check-only tests; `tests/lang/parallel_map.selka` runs the accepted shapes.
const std = @import("std");
const support = @import("test_support.zig");

/// Print a failing check's diagnostics to the test's stderr.
const report = std.debug.print;

const code = "E_TASK_CAPABILITY";

/// Check `body` after `import parallel` and an empty `main`, in an arena the caller frees. The `import` lines a body
/// begins with join the header's, since every import comes before the first declaration.
fn check(arena: std.mem.Allocator, body: []const u8) !support.Checked {
    var imports: usize = 0;
    while (std.mem.startsWith(u8, body[imports..], "import ")) imports = std.mem.indexOfScalarPos(u8, body, imports, '\n').? + 1;
    const header = "import parallel\nimport filesystem\n";
    const entry = "\nfunc main() -> int:\n    return 0\n\n";
    return support.checkSource(arena, try std.mem.concat(arena, u8, &.{ header, body[0..imports], entry, body[imports..] }));
}

/// Whether `body` checks with no error.
fn accepted(allocator: std.mem.Allocator, body: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    if (!checked.passed) for (checked.diagnostics) |item| report("{s}: {s}\n", .{ item.code, item.message });
    return checked.passed;
}

/// Whether `body` is refused with `wanted` and that diagnostic's message contains every one of `needles`.
fn refused(allocator: std.mem.Allocator, body: []const u8, wanted: []const u8, needles: []const []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    if (checked.passed) report("expected {s}, but the program checked\n", .{wanted});
    if (checked.passed) return false;
    for (checked.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, wanted)) continue;
        for (needles) |needle| if (std.mem.indexOf(u8, item.message, needle) == null) {
            report("{s} lacks \"{s}\": {s}\n", .{ wanted, needle, item.message });
            return false;
        };
        return true;
    }
    for (checked.diagnostics) |item| report("expected {s}, got {s}: {s}\n", .{ wanted, item.code, item.message });
    return false;
}

/// A group that submits `use(cap)` for a capability parameter of type `type_name`, with the task reading it.
fn submitted(arena: std.mem.Allocator, type_name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(arena,
        \\func use(cap: {s}, n: int) -> int:
        \\    _ = cap
        \\    return n
        \\
        \\func go(cap: {s}) -> int:
        \\    with parallel.group() as g:
        \\        const t = g.submit(use, cap, 1)
        \\        return t.result()
        \\
    , .{ type_name, type_name });
}

/// Whether a direct submit of a `type_name` capability is refused with a message that names the argument and the type.
fn refusesDirect(allocator: std.mem.Allocator, type_name: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const named = try std.fmt.allocPrint(arena.allocator(), "`{s}`", .{type_name});
    return refused(allocator, try submitted(arena.allocator(), type_name), code, &.{ "`cap`", named, "outside world" });
}

test "a task refuses each capability type given directly to submit" {
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Stream"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Filesystem"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Network"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Clock"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Entropy"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Environment"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Process"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Input"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Stop"));
    try std.testing.expect(try refusesDirect(std.testing.allocator, "Registers"));
}

test "Host keeps its own refusal, E_TASK_HOST" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expect(try refused(std.testing.allocator, try submitted(arena.allocator(), "Host"), "E_TASK_HOST", &.{"Host"}));
}

const in_record =
    \\record Ctx:
    \\    label: str
    \\    fs: Filesystem
    \\
    \\func peek(ctx: Ctx) -> bool:
    \\    return ctx.fs.exists(ctx.label)
    \\
    \\func go(fs: Filesystem) -> bool:
    \\    const ctx = Ctx(label="x", fs=fs)
    \\    with parallel.group() as g:
    \\        const t = g.submit(peek, ctx)
    \\        return t.result()
    \\
;

const in_nested_record =
    \\record Inner:
    \\    entropy: Entropy
    \\
    \\record Outer:
    \\    inner: Inner
    \\    count: int
    \\
    \\func draw(outer: Outer) -> int:
    \\    return outer.count
    \\
    \\func go(entropy: Entropy) -> int:
    \\    const outer = Outer(inner=Inner(entropy=entropy), count=3)
    \\    with parallel.group() as g:
    \\        const t = g.submit(draw, outer)
    \\        return t.result()
    \\
;

const in_list =
    \\func count(streams: Stream[]) -> int:
    \\    return len(streams)
    \\
    \\func go(out: Stream) -> int:
    \\    const streams = [out, out]
    \\    with parallel.group() as g:
    \\        const t = g.submit(count, streams)
    \\        return t.result()
    \\
;

const in_option =
    \\func has(clock: Clock?) -> bool:
    \\    match clock:
    \\        case Some(c):
    \\            return True
    \\        case None:
    \\            return False
    \\
    \\func go(clock: Clock) -> bool:
    \\    const maybe: Clock? = Some(clock)
    \\    with parallel.group() as g:
    \\        const t = g.submit(has, maybe)
    \\        return t.result()
    \\
;

const in_union =
    \\enum Source:
    \\    fixed(n: int)
    \\    live(env: Environment)
    \\
    \\func pick(source: Source) -> int:
    \\    match source:
    \\        case fixed(n):
    \\            return n
    \\        case live(env):
    \\            return len(env.names())
    \\
    \\func go(env: Environment) -> int:
    \\    const source = Source.live(env=env)
    \\    with parallel.group() as g:
    \\        const t = g.submit(pick, source)
    \\        return t.result()
    \\
;

const in_dictionary =
    \\func size(table: dict[str, Process]) -> int:
    \\    return len(table)
    \\
    \\func go(proc: Process) -> int:
    \\    mut table: dict[str, Process] = {}
    \\    table["a"] = proc
    \\    with parallel.group() as g:
    \\        const t = g.submit(size, table)
    \\        return t.result()
    \\
;

test "a task refuses a value that holds a capability and names where it is held" {
    try std.testing.expect(try refused(std.testing.allocator, in_record, code, &.{ "`ctx`", "`Filesystem`", "field `fs`" }));
    try std.testing.expect(try refused(std.testing.allocator, in_nested_record, code, &.{ "`Entropy`", "field `inner`, then field `entropy`" }));
    try std.testing.expect(try refused(std.testing.allocator, in_list, code, &.{ "`streams`", "`Stream[]`", "an element" }));
    try std.testing.expect(try refused(std.testing.allocator, in_option, code, &.{ "`maybe`", "`Clock?`", "its value" }));
    try std.testing.expect(try refused(std.testing.allocator, in_union, code, &.{ "`Environment`", "case `live`" }));
    try std.testing.expect(try refused(std.testing.allocator, in_dictionary, code, &.{ "`Process`", "dict[str, Process]" }));
}

const map_trailing =
    \\func scale(value: int, out: Stream) -> int:
    \\    print(out, value)
    \\    return value * 2
    \\
    \\func go(out: Stream) -> int:
    \\    const doubled = parallel.map([1, 2, 3], scale, out)
    \\    return len(doubled)
    \\
;

const map_trailing_record =
    \\record Sink:
    \\    out: Stream
    \\    tag: int
    \\
    \\func scale(value: int, sink: Sink) -> int:
    \\    return value * sink.tag
    \\
    \\func go(out: Stream) -> int:
    \\    const sink = Sink(out=out, tag=2)
    \\    const doubled = parallel.map([1, 2, 3], scale, sink)
    \\    return len(doubled)
    \\
;

const map_items =
    \\func probe(fs: Filesystem) -> bool:
    \\    return fs.exists("x")
    \\
    \\func go(fs: Filesystem) -> int:
    \\    const results = parallel.map([fs, fs], probe)
    \\    return len(results)
    \\
;

const map_results_items =
    \\record Job:
    \\    fs: Filesystem
    \\    name: str
    \\
    \\func probe(job: Job) -> bool:
    \\    return job.fs.exists(job.name)
    \\
    \\func go(fs: Filesystem) -> int:
    \\    mut jobs: Job[] = []
    \\    append(mut jobs, Job(fs=fs, name="a"))
    \\    const results = parallel.map_results(jobs, probe)
    \\    return len(results)
    \\
;

test "parallel.map refuses a capability among its trailing arguments and its items" {
    try std.testing.expect(try refused(std.testing.allocator, map_trailing, code, &.{ "`out`", "parallel.map task", "print it after" }));
    try std.testing.expect(try refused(std.testing.allocator, map_trailing_record, code, &.{ "`sink`", "field `out`" }));
    try std.testing.expect(try refused(std.testing.allocator, map_items, code, &.{ "the items of `[fs, fs]`", "are each a `Filesystem`" }));
    try std.testing.expect(try refused(std.testing.allocator, map_results_items, code, &.{ "the items of `jobs`", "field `fs`" }));
}

const network_service =
    \\func ask(net: Network) -> int:
    \\    _ = net
    \\    return 0
    \\
    \\func go(net: Network) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(ask, net)
    \\        return t.result()
    \\
;

const stop_in_record =
    \\record Services:
    \\    stop: Stop
    \\    turns: int
    \\
    \\func work(services: Services, n: int) -> int:
    \\    return n + services.turns
    \\
    \\func go(stop: Stop) -> int:
    \\    const services = Services(stop=stop, turns=1)
    \\    with parallel.group() as g:
    \\        const t = g.submit(work, services, 1)
    \\        return t.result()
    \\
;

const stop_answer_as_value =
    \\import process
    \\func work(n: int, stopping: bool) -> int:
    \\    if stopping:
    \\        return 0
    \\    return n * 2
    \\
    \\func go(stop: Stop) -> int:
    \\    if process.stop_requested(stop):
    \\        return 0
    \\    const doubled = parallel.map([1, 2, 3], work, process.stop_requested(stop))
    \\    return len(doubled)
    \\
;

test "a task refuses a Stop, held or direct, and says how a task learns of a stop (FR5b)" {
    try std.testing.expect(try refused(std.testing.allocator, stop_in_record, code, &.{ "`Stop`", "field `stop`", "process.stop_requested(stop)", "as a bool" }));
    try std.testing.expect(try accepted(std.testing.allocator, stop_answer_as_value));
}

test "a refused Network names the one event loop that accepts and dials" {
    try std.testing.expect(try refused(std.testing.allocator, network_service, code, &.{ "network.dial", "dialling-from-the-event-loop" }));
}

const generic_task =
    \\func touch[T](value: T) -> int:
    \\    return 1
    \\
    \\func go(out: Stream) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(touch, out)
    \\        return t.result()
    \\
;

test "a generic task function stays refused as a function value, before any argument rule" {
    try std.testing.expect(try refused(std.testing.allocator, generic_task, "E_CALLBACK_TYPE", &.{"nongeneric"}));
}

const plain_values =
    \\record Row:
    \\    name: str
    \\    cells: int[]
    \\
    \\enum Shape:
    \\    dot
    \\    line(n: int)
    \\
    \\func weigh(row: Row, shape: Shape, label: str, extra: int[]) -> int:
    \\    match shape:
    \\        case dot:
    \\            return len(row.cells) + len(extra)
    \\        case line(n):
    \\            return n + len(label)
    \\
    \\func scale(value: int, row: Row) -> int:
    \\    return value * len(row.cells)
    \\
    \\func go() -> int:
    \\    const row = Row(name="r", cells=[1, 2])
    \\    const shape = Shape.line(n=3)
    \\    const extra = [4, 5]
    \\    mut got = 0
    \\    with parallel.group() as g:
    \\        const t = g.submit(weigh, row, shape, "ab", extra)
    \\        got = t.result()
    \\    const scaled = parallel.map([1, 2], scale, row)
    \\    return got + scaled[1]
    \\
;

const own_stand_in =
    \\func work(n: int) -> bool:
    \\    const fs = filesystem.memory()
    \\    _ = fs.write_text("x", str(n))
    \\    return fs.exists("x")
    \\
    \\func go() -> int:
    \\    const results = parallel.map([1, 2, 3], work)
    \\    return len(results)
    \\
;

const mut_argument =
    \\func touch(values: int[]) -> int:
    \\    return len(values)
    \\
    \\func go() -> int:
    \\    mut values: int[] = [1]
    \\    with parallel.group() as g:
    \\        const t = g.submit(touch, mut values)
    \\        return t.result()
    \\
;

test "a task still takes values that hold no capability, and makes its own stand-ins" {
    try std.testing.expect(try accepted(std.testing.allocator, plain_values));
    try std.testing.expect(try accepted(std.testing.allocator, own_stand_in));
    try std.testing.expect(try refused(std.testing.allocator, mut_argument, "E_TASK_MUT", &.{"own"}));
}

/// Whether `body`'s first `E_TASK_CAPABILITY` carries a fix; false also when no such diagnostic is reported.
fn offersFix(allocator: std.mem.Allocator, body: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try check(arena.allocator(), body);
    for (checked.diagnostics) |item| if (std.mem.eql(u8, item.code, code)) return item.provenance.fix != null;
    report("no {s} reported\n", .{code});
    return false;
}

const unread_parameter =
    \\func weigh(n: int, _out: Stream) -> int:
    \\    return n
    \\
    \\func go(out: Stream) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(weigh, 1, out)
    \\        return t.result()
    \\
;

const unread_but_called_twice =
    \\func weigh(n: int, _out: Stream) -> int:
    \\    return n
    \\
    \\func go(out: Stream) -> int:
    \\    const direct = weigh(2, out)
    \\    with parallel.group() as g:
    \\        const t = g.submit(weigh, 1, out)
    \\        return t.result() + direct
    \\
;

const unread_but_public =
    \\public func weigh(n: int, _out: Stream) -> int:
    \\    return n
    \\
    \\func go(out: Stream) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(weigh, 1, out)
    \\        return t.result()
    \\
;

const read_parameter =
    \\func weigh(n: int, out: Stream) -> int:
    \\    print(out, n)
    \\    return n
    \\
    \\func go(out: Stream) -> int:
    \\    with parallel.group() as g:
    \\        const t = g.submit(weigh, 1, out)
    \\        return t.result()
    \\
;

test "the certain repair is offered only for a parameter nothing reads, of a private function used once" {
    try std.testing.expect(try offersFix(std.testing.allocator, unread_parameter));
    try std.testing.expect(!try offersFix(std.testing.allocator, unread_but_called_twice));
    try std.testing.expect(!try offersFix(std.testing.allocator, unread_but_public));
    try std.testing.expect(!try offersFix(std.testing.allocator, read_parameter));
}
