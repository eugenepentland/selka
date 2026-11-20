//! Bounded map captures and result transfer through the generated range worker.
const std = @import("std");
const printDiagnostics = std.debug.print;
const language = @import("selka");
const ir = @import("ir.zig");
const support = @import("test_support.zig");
const contract = @import("single_owner.zig");
const passes = @import("passes.zig");

const source =
    \\import parallel
    \\func transform(value: str) -> str:
    \\    return value + "!"
    \\func main(out: Stream) -> int:
    \\    const result = parallel.map(["input-" + str(7)], transform)
    \\    print(out, result[0])
    \\    return 0
;

const Entry = struct {
    text: []const u8,
    /// Load the entry and leave standard imports to the embedded loader.
    pub fn read(context: ?*anyopaque, a: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "result_support.selka")) return a.dupe(u8, result_library);
        if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
        return a.dupe(u8, (@as(*Entry, @ptrCast(@alignCast(context.?)))).text);
    }
};

fn module(a: std.mem.Allocator, input: []const u8) !ir.Module {
    var context: Entry = .{ .text = input };
    var project: language.embedded_project.Program = undefined;
    project.init(a, .{ .context = &context, .read = Entry.read }) catch |err| {
        for (project.compilation.diagnostics.items.items) |issue| printDiagnostics("{s}: {s} at {d}\n", .{ issue.code, issue.message, issue.span.start });
        return err;
    };
    const checked = project.compilation.program.?;
    var failure: contract.Failure = .{};
    try contract.check(a, checked, &failure);
    var refusal: @import("build.zig").Refusal = .{};
    return @import("build.zig").buildExecutable(a, .{
        .program = checked,
        .source = project.compilation.src,
    }, &refusal);
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-2
// FR59: the worker is a task thunk whose environment holds the input as a view, beside a lent box of its owner.
test "zero RC map worker borrows one source list and returns one owned chunk without element boxes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a, source);
    try support.verified(a, &m, &.{});
    var found: usize = 0;
    for (m.functions.items) |function| {
        if (!std.mem.startsWith(u8, function.name, "<task.thunk.")) continue;
        found += 1;
        try std.testing.expectEqual(.list, m.kind(function.signature.ret));
        const capture = m.compound(m.compound(function.signature.params[0]).box).record;
        try std.testing.expectEqual(@as(usize, 5), capture.len);
        try std.testing.expectEqual(.list_view, m.kind(capture[0]));
        try std.testing.expectEqual(.box, m.kind(capture[4]));
        try std.testing.expectEqual(@as(usize, 1), function.loops.items.len);
        var marked = false;
        for (function.insts.items) |inst| {
            try std.testing.expect(inst.op != .box_make);
            if (inst.op == .call and std.mem.eql(u8, m.functions.items[inst.a.index()].name, "myl_core_task_item")) marked = true;
        }
        try std.testing.expect(marked);
    }
    try std.testing.expectEqual(@as(usize, 1), found);
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
}

const result_source =
    \\import lists
    \\import strings
    \\import parallel
    \\func attempt(value: int) -> str fails str:
    \\    if value % 2 == 0:
    \\        return "ok-" + str(value)
    \\    fail "bad-" + str(value)
    \\func size(value: Result[str, str]) -> int:
    \\    match value:
    \\        case Ok(text):
    \\            return strings.char_count(text)
    \\        case Err(text):
    \\            return strings.char_count(text)
    \\func main(out: Stream) -> int:
    \\    mut values = parallel.map_results([0, 1, 2, 3], attempt)
    \\    const saved = copy(values)
    \\    mut total = len(values)
    \\    for value in values:
    \\        total += size(value)
    \\    match lists.pop(mut values):
    \\        case Ok(text):
    \\            total += strings.char_count(text)
    \\        case Err(text):
    \\            total += strings.char_count(text)
    \\    _ = values
    \\    const sizes = parallel.map(saved, size)
    \\    print(out, total, sizes[0], sizes[1], sizes[2], sizes[3])
    \\    _ = parallel.map_results([4, 5], attempt)
    \\    return 0
;

// spec: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 Result list map preserves managed payload ownership and explicit acknowledgment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a, result_source);
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
}

test "O3 parallel map workers borrow nested wrapper inputs and trailing arguments at the callback ABI" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a,
        \\import parallel
        \\record Label:
        \\    text: str
        \\    values: int[]
        \\func size(value: Result[int[]?, Label], before: Unit, extra: int[]?, after: Unit) -> int:
        \\    _ = before
        \\    _ = after
        \\    mut total = 0
        \\    match value:
        \\        case Ok(optional):
        \\            match optional:
        \\                case Some(values):
        \\                    total = len(values)
        \\                case None:
        \\                    total = 7
        \\        case Err(label):
        \\            total = len(label.text) + len(label.values)
        \\    match extra:
        \\        case Some(values):
        \\            total += len(values)
        \\        case None:
        \\            total += 11
        \\    return total
        \\func main() -> int:
        \\    mut values: Result[int[]?, Label][] = [Ok(Some([1, 2])), Ok(None), Err(Label(text="error", values=[3]))]
        \\    mut extra: int[]? = Some([4, 5, 6])
        \\    const sizes = parallel.map(values, size, (), extra, ())
        \\    extra = None
        \\    return sizes[0] + sizes[1] + sizes[2]
    );
    try support.verified(a, &m, &.{});
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
}

test "O3 direct calls and parallel map borrow boxed nested recursive wrappers" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a,
        \\import parallel
        \\record Node:
        \\    value: int
        \\    next: Node??
        \\func size(value: Node??) -> int:
        \\    match value:
        \\        case Some(inner):
        \\            match inner:
        \\                case Some(node):
        \\                    return node.value
        \\                case None:
        \\                    return 7
        \\        case None:
        \\            return 11
        \\func main() -> int:
        \\    mut first: Node?? = Some(Some(Node(value=5, next=None)))
        \\    mut middle: Node?? = Some(None)
        \\    mut empty: Node?? = None
        \\    const direct = size(first) + size(middle) + size(empty)
        \\    first = None
        \\    mut values: Node??[] = [Some(Some(Node(value=13, next=None))), Some(None), None]
        \\    const sizes = parallel.map(values, size)
        \\    return direct + sizes[0] + sizes[1] + sizes[2]
    );
    try support.verified(a, &m, &.{});
    const result = try passes.run(a, &m, .verify);
    try support.verified(a, &m, result.plans);
}

fn refusesResultList(backing: std.mem.Allocator, body: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), body);
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings(code, checked.diagnostics[0].code);
}

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 Result list rejects implicit abandonment overwrite clear and inspection loss" {
    // The table also covers a writing home, so every case is checked as a project.
    const prefix = "import lists\nfunc main() -> int:\n    mut values: Result[int, int][] = [Ok(3), Err(7)]\n";
    const cases = .{
        .{ "    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    return len(values)\n", "E_RESULT_UNHANDLED" },
        .{ "    values = []\n    _ = values\n    return 0\n", "E_RESULT_OVERWRITE" },
        .{ "    lists.clear(mut values)\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    _ = values[0]\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    for value in values:\n        _ = value\n        break\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    for value in values:\n        _ = value\n        return 0\n    _ = values\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    _ = values\n    _ = copy(values)\n    return 0\n", "E_RESULT_CONSUMED" },
        .{ "    _ = values[0:1]\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        // The prelude `sort` refuses a non-scalar element type before the
        // unhandled-result rule, so the retirement names the surviving code.
        .{ "    sort(mut values, reverse=True)\n    _ = values\n    return 0\n", "E_COLLECTION_METHOD" },
        .{ "    const clone = copy(values)\n    _ = values\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    for value in values:\n        continue\n    _ = values\n    return 0\n", "E_RESULT_UNHANDLED" },
        .{ "    _ = list(values)\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    _ = sorted(values)\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
        .{ "    for value in reversed(values):\n        _ = value\n    _ = values\n    return 0\n", "E_RESULT_OPERATION" },
    };
    inline for (cases) |case| try refusesResultList(std.testing.allocator, prefix ++ case[0], case[1]);
}

const result_library =
    \\public func make(value: int) -> Result[str, str][]:
    \\    return [Ok("ok-" + str(value)), Err("bad-" + str(value))]
    \\public func duplicate[T: storable](values: T[]) -> T[]:
    \\    const saved = copy(values)
    \\    _ = values
    \\    return saved
;

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 public Result list interfaces preserve storage and handling independently" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var m = try module(a,
        \\import result_support
        \\func main() -> int:
        \\    const values = result_support.make(3)
        \\    const copied = result_support.duplicate(values)
        \\    for value in copied:
        \\        _ = value
        \\    _ = copied
        \\    return 0
    );
    const optimized = try passes.run(a, &m, .verify);
    try support.verified(a, &m, optimized.plans);
    var context: Entry = .{ .text =
        \\import result_support
        \\func main() -> int:
        \\    const values = result_support.make(3)
        \\    return len(values)
    };
    var project: language.embedded_project.Program = undefined;
    try std.testing.expectError(error.SourceError, project.init(a, .{ .context = &context, .read = Entry.read }));
    try std.testing.expectEqualStrings("E_RESULT_UNHANDLED", project.compilation.diagnostics.items.items[0].code);
}

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 pending Results retain resource capability container boxing and generic copy boundaries" {
    try refusesResultList(std.testing.allocator,
        \\resource File: filesystem
        \\func main() -> int:
        \\    const values: Result[File, str][] = []
        \\    _ = values
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    // A capability is a scalar handle (5C), so a list of its pending Results is an ordinary Result list.
    {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const listed = try support.checkSource(arena.allocator(),
            \\func main() -> int:
            \\    const values: Result[Filesystem, str][] = []
            \\    _ = values
            \\    return 0
        );
        try std.testing.expect(listed.passed);
    }
    try refusesResultList(std.testing.allocator,
        \\func main() -> int:
        \\    const values: dict[int, Result[int, int]] = {}
        \\    _ = values
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\func main() -> int:
        \\    const values: set[Result[int, int]] = {}
        \\    _ = values
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\record Node:
        \\    value: Result[int, int]
        \\    next: Node?
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\record Box[T]:
        \\    value: T
        \\record Pending:
        \\    values: Result[int, int][]
        \\record Bad:
        \\    value: Box[Pending]
        \\func main() -> int:
        \\    return 0
    , "E_GENERIC_REQUIREMENT");
    try refusesResultList(std.testing.allocator,
        \\func ignore[T: storable](value: T) -> int:
        \\    return 0
        \\func main() -> int:
        \\    return ignore(3)
    , "E_RESULT_UNHANDLED");
}

fn ownedScheduler(parent: std.mem.Allocator, sanitized: bool) !void {
    var arena = std.heap.ArenaAllocator.init(parent);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    var fixture = try @import("native_fixture.zig").Fixture.init(a, root, @embedFile("a01_owned_scheduler_fixture.c"), .{ .counted = !sanitized, .sanitized = sanitized });
    const threads: []const []const u8 = if (sanitized) &.{"8"} else &.{ "1", "2", "8" };
    // ThreadSanitizer runs take 100,000 submits in the gate and a million under SELKA_FULL_STRESS.
    const mode = if (sanitized) @import("native_fixture.zig").stressMode("stress-tsan", "stress") else "stress";
    const report = if (std.mem.eql(u8, mode, "stress-tsan")) "110002 submits, binary depth 12, chain 2048" else "1010002 submits, binary depth 12, chain 2048";
    for (threads) |workers| {
        const ran = try fixture.run(mode, workers);
        try std.testing.expectEqual(@as(u8, 0), ran.status);
        try std.testing.expectEqualStrings("", ran.stderr);
        try std.testing.expect(std.mem.indexOf(u8, ran.stdout, report) != null);
        if (!sanitized) {
            for ([_][]const u8{ "\"runtime_retains\"", "\"runtime_releases\"", "\"shared_retains\"", "\"shared_releases\"", "\"share_marks\"" }) |marker|
                try std.testing.expect(std.mem.indexOf(u8, ran.counts, marker) == null);
            try std.testing.expect(std.mem.indexOf(u8, ran.counts, "\"live_bytes_at_exit\":0") != null);
        }
        if (!sanitized) if (fixture.environment.get("SELKA_P1_FIXTURE_OUTPUT")) |destination| {
            try std.Io.Dir.cwd().createDirPath(std.testing.io, destination);
            const name = try std.fmt.allocPrint(a, "{s}/a01-owned-scheduler-counts-{s}.json", .{ destination, workers });
            try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = name, .data = ran.counts });
        };
        const twice = try fixture.run("twice", workers);
        try std.testing.expectEqual(@as(u8, 1), twice.status);
        try std.testing.expect(std.mem.indexOf(u8, twice.stderr, "R_TASK_GROUP") != null);
        try std.testing.expect(std.mem.indexOf(u8, twice.stderr, "ThreadSanitizer") == null);
    }
    try fixture.exportBinary(if (sanitized) "a01-owned-scheduler-tsan" else "a01-owned-scheduler-counted");
}

// spec-case: NEW-CORE-ZERO-RC-TASKS-1
test "A01 zero RC scheduler million-submit nested and discarded-result stress" {
    try ownedScheduler(std.testing.allocator, false);
}

// spec-case: TSAN-BUILD-1
test "A01 zero RC scheduler submit stress has no ThreadSanitizer reports" {
    try ownedScheduler(std.testing.allocator, true);
}

const bare_fallible_source =
    \\import parallel
    \\func attempt(value: int) -> str fails str:
    \\    if value % 2 == 0:
    \\        return "ok-" + str(value)
    \\    fail "bad-" + str(value)
    \\func main(out: Stream) -> int:
    \\    const results = parallel.map([0, 1], attempt)
    \\    _ = results
    \\    return 0
;

const try_fallible_source =
    \\import parallel
    \\func attempt(value: int) -> str fails str:
    \\    if value % 2 == 0:
    \\        return "ok-" + str(value)
    \\    fail "bad-" + str(value)
    \\func all_ok(values: int[]) -> str[] fails str:
    \\    return try parallel.map(values, attempt)
    \\func main() -> int:
    \\    return 0
;

// A bare `parallel.map` of a fallible function keeps the old list-of-results meaning only as
// `parallel.map_results`; the bare spelling refuses with a rename fix that keeps the qualifier.
test "A bare parallel.map of a fallible function refuses with the parallel.map_results rename fix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), bare_fallible_source);
    try std.testing.expect(!checked.passed);
    try std.testing.expectEqualStrings("E_PARALLEL_MAP_FALLIBLE", checked.diagnostics[0].code);
    const fix = checked.diagnostics[0].provenance.fix orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings("parallel.map_results", fix.edit.text);
}

// The `try` form selects the fallible map, which type-checks as `R[] fails E`.
test "try parallel.map of a fallible function checks as the fallible map" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), try_fallible_source);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
    try std.testing.expect(checked.passed);
    try std.testing.expectEqual(@as(usize, 0), checked.diagnostics.len);
}

// `parallel.map` with trailing arguments (E1b): a `mut` argument is E_TASK_MUT; an `own` argument, more than five, and a
// fallible function are E_PARALLEL_MAP_ARGS. Each refusal names the call, so the checker reports it before any build.
const map_args_head =
    \\import parallel
    \\func scale_by(value: int, factor: int) -> int:
    \\    return value * factor
    \\func attempt(value: int, factor: int) -> int fails str:
    \\    return value * factor
    \\func take(own items: int[], factor: int) -> int:
    \\    return len(items) * factor
    \\func many(value: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    \\    return value + a + b + c + d + e + f
    \\func main(out: Stream) -> int:
    \\    mut factor = 3
    \\
;

fn refusedWithCode(allocator: std.mem.Allocator, body: []const u8, code: []const u8) !bool {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const checked = try support.checkSource(arena.allocator(), try std.mem.concat(arena.allocator(), u8, &.{ map_args_head, body }));
    if (checked.passed) return false;
    for (checked.diagnostics) |item| if (std.mem.eql(u8, item.code, code)) return true;
    return false;
}

test "parallel.map with a mut trailing argument is refused with E_TASK_MUT" {
    try std.testing.expect(try refusedWithCode(std.testing.allocator, "    const result = parallel.map([1, 2], scale_by, mut factor)\n    return result[0]\n", "E_TASK_MUT"));
}

test "parallel.map with an own trailing argument is refused with E_PARALLEL_MAP_ARGS" {
    try std.testing.expect(try refusedWithCode(std.testing.allocator, "    const result = parallel.map([1, 2], scale_by, own factor)\n    return result[0]\n", "E_PARALLEL_MAP_ARGS"));
}

test "parallel.map with six trailing arguments is refused with E_PARALLEL_MAP_ARGS" {
    try std.testing.expect(try refusedWithCode(std.testing.allocator, "    const result = parallel.map([1, 2], many, 1, 2, 3, 4, 5, 6)\n    return result[0]\n", "E_PARALLEL_MAP_ARGS"));
}

test "parallel.map of a fallible function with trailing arguments is refused with E_PARALLEL_MAP_ARGS" {
    try std.testing.expect(try refusedWithCode(std.testing.allocator, "    const result = try parallel.map([1, 2], attempt, factor)\n    return result[0]\n", "E_PARALLEL_MAP_ARGS"));
}
