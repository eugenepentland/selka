//! Value semantics (`VALUE-SEMANTICS-1`..`-7`): the checker's verdicts and
//! messages with the switch on and off.
//! Guest behaviour under the switch is tested in `tests/value_semantics`.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const values = @import("value_semantics.zig");

const entry = "\n\nfunc main() -> int:\n    return 0\n";

// spec-case: DICT-VIEWS-1
test "live dictionary view transfer policy follows builtin declaration identity" {
    const sources = [_][]const u8{
        "func saved(mapping: dict[int,int]) -> int:\n    for value in mapping.values():\n        return value\n    return 0\n" ++ entry,
        "record DictValues[K, V]:\n    values: V[]\n\nfunc saved(value: DictValues[int, int]) -> int:\n    return 0\n" ++ entry,
    };
    for (sources, 0..) |source, index| {
        var compilation = try compiler.Compilation.init(t.allocator, "views.selka", source);
        defer compilation.deinit();
        try compilation.check();
        const records = compilation.program.?.records;
        var found = false;
        for (records) |record| {
            if (!std.mem.startsWith(u8, record.name, "DictValues<")) continue;
            found = true;
            try t.expectEqual(index == 0, values.isLiveView(records, record.id));
        }
        try t.expect(found);
    }
}

// A type cycle with only scalar fields requires no COW transfer, while a
// collection on another edge still does.
// spec-case: VALUE-SEMANTICS-2
test "recursive type reachability finds collections without treating a cycle as one" {
    const sources = [_][]const u8{
        "record Node:\n    value: int\n    next: Node?\n\n" ++ entry,
        "record Node:\n    items: int[]\n    next: Node?\n\n" ++ entry,
    };
    for (sources, 0..) |source, index| {
        var compilation = try compiler.Compilation.init(t.allocator, "node.selka", source);
        defer compilation.deinit();
        try compilation.check();
        const records = compilation.program.?.records;
        var found = false;
        for (records) |record| {
            if (!std.mem.eql(u8, record.name, "Node")) continue;
            found = true;
            try t.expectEqual(index == 1, values.needsCopy(records, record.id));
            try t.expect(values.copiesAll(records, record.id));
        }
        try t.expect(found);
    }
}

/// The first error's code and message when `body` (plus an entry point) is
/// checked with the switch at `on`, or `ok` and an empty message.
const Verdict = struct { code: []const u8, message: []const u8 };

fn verdict(a: std.mem.Allocator, body: []const u8) !Verdict {
    const text = try std.mem.concat(a, u8, &.{ body, entry });
    var compilation = try compiler.Compilation.init(t.allocator, "rules.selka", text);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    for (compilation.diagnostics.items) |item| if (item.severity == .err) return .{ .code = try a.dupe(u8, item.code), .message = try a.dupe(u8, item.message) };
    return .{ .code = "ok", .message = "" };
}

/// Expect the first error code of `body`.
fn expectCode(body: []const u8, code: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = try verdict(arena.allocator(), body);
    try t.expectEqualStrings(code, found.code);
    // VALUE-SEMANTICS-4: no reference-model wording.
    for ([_][]const u8{ "reachable from the caller", "use `class`", "fresh local snapshot", "may alias" }) |phrase| {
        try t.expect(std.mem.indexOf(u8, found.message, phrase) == null);
    }
}

/// The message of the first error of `body`.
fn switchedMessage(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    return (try verdict(a, body)).message;
}

// spec-case: VALUE-SEMANTICS-4
test "a write to a local copy of a parameter needs no mut" {
    try expectCode("func f(xs: int[]) -> int[]:\n    mut ys = xs\n    ys.append(1)\n    return ys\n", "ok");
    try expectCode("func f(xss: int[][]) -> int[][]:\n    mut ys = xss.copy()\n    ys[0].append(1)\n    return ys\n", "ok");
    try expectCode("func f(xss: int[][]) -> int:\n    mut row = xss[0]\n    row.append(1)\n    return len(row)\n", "ok");
    try expectCode("func identity(xs: int[]) -> int[]:\n    return xs\n\nfunc f(xs: int[]) -> int:\n    mut picked = identity(xs)\n    picked.append(0)\n    return len(picked)\n", "ok");
    try expectCode("func f(grid: int[][]) -> int:\n    mut total = 0\n    for row in grid:\n        mut local = row\n        local.append(0)\n        total = total + len(local)\n    return total\n", "ok");
}

// spec-case: VALUE-SEMANTICS-4
test "a parameter stays read-only and says so" {
    try expectCode("func f(xs: int[]) -> Unit:\n    xs.append(1)\n", "E_IMMUTABLE");
    try expectCode("record R:\n    items: int[]\n\nfunc f(r: R) -> Unit:\n    r.items.append(1)\n", "E_IMMUTABLE");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const message = try switchedMessage(arena.allocator(), "func f(xs: int[]) -> Unit:\n    xs.append(1)\n");
    try t.expect(std.mem.indexOf(u8, message, "writable binding") != null);
}

// spec-case: VALUE-SEMANTICS-4
test "a write through a loop or match binding is a binding write" {
    try expectCode("func f(grid: int[][]) -> Unit:\n    for row in grid:\n        row.append(0)\n", "E_IMMUTABLE");
    try expectCode("func f(grid: int[][]) -> Unit:\n    for i, row in enumerate(grid):\n        row.append(i)\n", "E_IMMUTABLE");
    try expectCode("func f(d: dict[str, int[]]) -> Unit:\n    for v in d.values():\n        v.append(0)\n", "E_IMMUTABLE");
    try expectCode("func f(d: dict[str, int[]]) -> Unit:\n    for k, v in d.items():\n        v.append(0)\n", "E_IMMUTABLE");
    try expectCode("record P:\n    x: int\n\nfunc f(ps: P[]) -> Unit:\n    for p in ps:\n        p.x = 1\n", "E_IMMUTABLE");
    try expectCode("func fill(mut xs: int[]) -> Unit:\n    xs.append(1)\n\nfunc f(grid: int[][]) -> Unit:\n    for row in grid:\n        fill(mut row)\n", "E_IMMUTABLE");
    const payload =
        \\func f(opt: int[]?) -> int:
        \\    match opt:
        \\        case Some(v):
        \\            v.append(1)
        \\            return len(v)
        \\        case None:
        \\            return 0
        \\
    ;
    try expectCode(payload, "E_IMMUTABLE");
}

// spec-case: VALUE-SEMANTICS-4
test "record loops and match payloads remain readonly even for temporary results" {
    const loop_write = "record Body:\n    items: int[]\n\nfunc f(mut bodies: Body[]) -> Unit:\n    for b in bodies:\n        b.items.append(1)\n";
    try expectCode(loop_write, "E_IMMUTABLE");
    try t.expectEqual(@as(usize, 1), try countCode(loop_write, "E_IMMUTABLE"));
    const call_result =
        \\func make() -> int[]?:
        \\    return Some([1])
        \\
        \\func f() -> int:
        \\    match make():
        \\        case Some(v):
        \\            v.append(2)
        \\            return len(v)
        \\        case None:
        \\            return 0
        \\
    ;
    try expectCode(call_result, "E_IMMUTABLE");
    try expectCode("func f(grid: int[][]) -> int:\n    mut total = 0\n    for row in grid:\n        total = total + len(row)\n    return total\n", "ok");
}

// spec-case: VALUE-SEMANTICS-4
test "a write into a returned value is a temporary write" {
    const returned =
        \\record Env:
        \\    slots: int[]
        \\
        \\func env_of(envs: Env[], index: int) -> Env:
        \\    return envs[index]
        \\
        \\func f(envs: Env[]) -> Unit:
        \\    env_of(envs, 0).slots.append(1)
        \\
    ;
    try expectCode(returned, "E_ASSIGNMENT_TARGET");
}

// spec-case: VALUE-SEMANTICS-3
test "mut scalar record and nested field parameters expose caller updates" {
    try expectCode("record C:\n    n: int\n\nfunc f(mut c: C) -> Unit:\n    c.n = c.n + 1\n", "ok");
    try expectCode("record Inner:\n    x: int\n    items: int[]\n\nrecord Outer:\n    inner: Inner\n\nfunc f(mut o: Outer) -> Unit:\n    o.inner.x = 3\n    o.inner.items.append(1)\n", "ok");
    const field_argument =
        \\record C:
        \\    n: int
        \\    items: int[]
        \\
        \\record Holder:
        \\    c: C
        \\
        \\func f(mut c: C) -> Unit:
        \\    c.items.append(1)
        \\
        \\func g(mut h: Holder) -> Unit:
        \\    f(mut h.c)
        \\
    ;
    try expectCode(field_argument, "ok");
    try expectCode("func f(mut n: int) -> Unit:\n    n = n + 1\n", "ok");
}

// spec: VALUE-SEMANTICS-6
test "writes to a private copy remain independent of unused caller-update capability" {
    const lost =
        \\func smooth(mut row: int[]) -> Unit:
        \\    row.append(0)
        \\
        \\func smooth_rows(mut rows: int[][]) -> Unit:
        \\    for i in range(len(rows)):
        \\        mut row = rows[i]
        \\        smooth(mut row)
        \\
    ;
    try expectCode(lost, "ok");
    var compilation = try compiler.Compilation.init(t.allocator, "local-copy.selka", lost ++
        "\nfunc main() -> int:\n    mut rows = [[1], [2]]\n    smooth_rows(mut rows)\n    return len(rows[0])\n");
    defer compilation.deinit();
    const result = try @import("native_execute.zig").run(&compilation);
    try t.expectEqual(@as(i64, 1), result.value);
}

// spec-case: VALUE-SEMANTICS-7
test "old of a collection is a value" {
    const captured = "@ensures(len(xs) == len(old(xs)) + 1)\nfunc push(mut xs: int[]) -> Unit:\n    xs.append(1)\n";
    try expectCode(captured, "ok");
    const class_capture = "class Box:\n    n: int\n\n@ensures(old(b).n <= b.n)\nfunc bump(mut b: Box) -> Unit:\n    b.n = b.n + 1\n";
    try expectCode(class_capture, "E_VALUE_CLASS");
}

// spec: VALUE-SEMANTICS-10
test "class and builtin Cell are retired" {
    try expectCode("class Box:\n    n: int\n", "E_VALUE_CLASS");
    try expectCode("func peek(slot: Cell[int]) -> int:\n    return slot.value\n", "E_VALUE_CELL");
    try expectCode("func make() -> int:\n    mut slot = Cell(value=3)\n    return slot.value\n", "E_VALUE_CELL");
    try expectCode("record Cell:\n    value: int\n\nfunc make() -> int:\n    return Cell(value=3).value\n", "ok");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const class_message = try switchedMessage(arena.allocator(), "class Box:\n    n: int\n");
    try t.expect(std.mem.indexOf(u8, class_message, "recursive union") != null);
    try t.expect(std.mem.indexOf(u8, class_message, "pool handle") != null);
    const cell_message = try switchedMessage(arena.allocator(), "func peek(slot: Cell[int]) -> int:\n    return slot.value\n");
    try t.expect(std.mem.indexOf(u8, cell_message, "store-back") != null);
}

/// How many diagnostics with `code` checking `body` reports.
fn countCode(body: []const u8, code: []const u8) !usize {
    const text = try std.mem.concat(t.allocator, u8, &.{ body, entry });
    defer t.allocator.free(text);
    var compilation = try compiler.Compilation.init(t.allocator, "warnings.selka", text);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    var count: usize = 0;
    for (compilation.diagnostics.items) |item| count += @intFromBool(std.mem.eql(u8, item.code, code));
    return count;
}

// spec-case: VALUE-SEMANTICS-3
test "rebinding a mut record parameter is a use that reaches the caller" {
    const reset = "record Counter:\n    n: int\n    items: int[]\n\nfunc reset(mut c: Counter) -> Unit:\n    c = Counter(n=0, items=[])\n";
    try t.expectEqual(@as(usize, 0), try countCode(reset, "W_UNUSED_BINDING"));
    try t.expectEqual(@as(usize, 0), try countCode(reset, "E_MUTATION_MARKER"));
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 declarations reject nested recursive view projection storage" {
    const source = "record Viewed:\n    next: Viewed?\n    views: FixedArray[DictValues[int,int][], 1]\n" ++ entry;
    var compilation = try compiler.Compilation.init(t.allocator, "reach.selka", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_VIEW_STORED", compilation.diagnostics.items[0].code);
}
