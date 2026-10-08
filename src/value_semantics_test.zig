//! Value semantics (`VALUE-SEMANTICS-1`..`-7`): the checker's verdicts and
//! messages with the switch on and off.
//! Guest behaviour under the switch is tested in `tests/value_semantics`.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const values = @import("value_semantics.zig");

const entry = "\n\ndef main() -> int:\n    return 0\n";

// spec-case: DICT-VIEWS-1
test "live dictionary view transfer policy follows builtin declaration identity" {
    const sources = [_][]const u8{
        "def saved(mapping: dict[int,int]) -> int:\n    for value in mapping.values():\n        return value\n    return 0\n" ++ entry,
        "record DictValues[K, V]:\n    values: list[V]\n\ndef saved(value: DictValues[int, int]) -> int:\n    return 0\n" ++ entry,
    };
    for (sources, 0..) |source, index| {
        var compilation = try compiler.Compilation.init(t.allocator, "views.my", source);
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

// spec-case: VALUE-SEMANTICS-1
test "legacy test fixtures explicitly restore the default value model" {
    try t.expect(values.enabled());
    const legacy = @import("test_support.zig").LegacySharing.enter();
    defer legacy.restore();
    try t.expect(!values.enabled());
    legacy.restore();
    try t.expect(values.enabled());
}

// A type cycle with only scalar fields requires no COW transfer, while a
// collection on another edge still does.
// spec-case: VALUE-SEMANTICS-2
test "recursive type reachability finds collections without treating a cycle as one" {
    const sources = [_][]const u8{
        "record Node:\n    value: int\n    next: Option[Node]\n\n" ++ entry,
        "record Node:\n    items: list[int]\n    next: Option[Node]\n\n" ++ entry,
    };
    for (sources, 0..) |source, index| {
        var compilation = try compiler.Compilation.init(t.allocator, "node.my", source);
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

// spec: RETURN-BORROW-1
test "physical return origins survive value copies and chained accessors" {
    const saved = Saved.set(true);
    defer saved.restore();
    const source =
        \\record Node:
        \\    data: bytes
        \\
        \\record Branch:
        \\    value: int
        \\    next: Option[Branch]
        \\
        \\def throughBox(branch: Branch) -> Branch:
        \\    return branch
        \\
        \\def at(nodes: list[Node], index: int) -> Node:
        \\    if index < 0 or index >= len(nodes):
        \\        return Node(data=b"")
        \\    return nodes[index]
        \\
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\def relay(nodes: list[Node], index: int) -> Node:
        \\    return identity[Node](at(nodes, index))
        \\
        \\def main() -> int:
        \\    nodes = [Node(data=b"abc")]
        \\    return len(relay(nodes, 0).data)
    ;
    var compilation = try compiler.Compilation.init(t.allocator, "borrow.my", source);
    defer compilation.deinit();
    try compilation.check();
    var found: usize = 0;
    for (compilation.program.?.functions) |function| {
        const target = std.mem.eql(u8, function.name, "at") or std.mem.eql(u8, function.name, "relay") or
            std.mem.eql(u8, function.name, "identity[Node]") or std.mem.eql(u8, function.name, "throughBox");
        if (!target) continue;
        if (!std.mem.eql(u8, function.name, "throughBox")) try t.expect(function.signature.return_origin == .fresh);
        switch (function.signature.inferred.borrow_origin) {
            .params => |positions| try t.expectEqualSlices(u16, &.{0}, positions),
            else => return error.TestUnexpectedResult,
        }
        found += 1;
    }
    try t.expectEqual(@as(usize, 4), found);
}

/// The switch as a test left it, restored when the test ends.
const Saved = struct {
    previous: bool,
    previous_counting: bool,
    fn set(on: bool) Saved {
        const saved: Saved = .{ .previous = values.enabled(), .previous_counting = values.counting() };
        values.setEnabled(on);
        values.setCounting(false);
        return saved;
    }
    fn restore(self: Saved) void {
        values.setEnabled(self.previous);
        values.setCounting(self.previous_counting);
    }
};

/// The first error's code and message when `body` (plus an entry point) is
/// checked with the switch at `on`, or `ok` and an empty message.
const Verdict = struct { code: []const u8, message: []const u8 };

fn verdict(a: std.mem.Allocator, body: []const u8, on: bool) !Verdict {
    const saved = Saved.set(on);
    defer saved.restore();
    const text = try std.mem.concat(a, u8, &.{ body, entry });
    var compilation = try compiler.Compilation.init(t.allocator, "rules.my", text);
    defer compilation.deinit();
    compilation.check() catch |err| switch (err) {
        error.SourceError => {},
        else => return err,
    };
    for (compilation.diagnostics.items) |item| if (item.severity == .err) return .{ .code = try a.dupe(u8, item.code), .message = try a.dupe(u8, item.message) };
    return .{ .code = "ok", .message = "" };
}

/// Expect the first error code of `body` with the switch off and on.
fn expectCodes(body: []const u8, off: []const u8, on: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expectEqualStrings(off, (try verdict(arena.allocator(), body, false)).code);
    const switched = try verdict(arena.allocator(), body, true);
    try t.expectEqualStrings(on, switched.code);
    // VALUE-SEMANTICS-4: no reference-model wording under the switch.
    for ([_][]const u8{ "reachable from the caller", "use `class`", "fresh local snapshot", "may alias" }) |phrase| {
        try t.expect(std.mem.indexOf(u8, switched.message, phrase) == null);
    }
}

/// The message of the first error of `body` under the switch.
fn switchedMessage(a: std.mem.Allocator, body: []const u8) ![]const u8 {
    return (try verdict(a, body, true)).message;
}

// spec-case: VALUE-SEMANTICS-4
test "a write to a local copy of a parameter needs no mut under the switch" {
    try expectCodes("def f(xs: list[int]) -> list[int]:\n    ys = xs\n    ys.append(1)\n    return ys\n", "E_MUTATION_MARKER", "ok");
    try expectCodes("def f(xss: list[list[int]]) -> list[list[int]]:\n    ys = xss.copy()\n    ys[0].append(1)\n    return ys\n", "E_MUTATION_MARKER", "ok");
    try expectCodes("def f(xss: list[list[int]]) -> int:\n    row = xss[0]\n    row.append(1)\n    return len(row)\n", "E_MUTATION_MARKER", "ok");
    try expectCodes("def identity(xs: list[int]) -> list[int]:\n    return xs\n\ndef f(xs: list[int]) -> int:\n    picked = identity(xs)\n    picked.append(0)\n    return len(picked)\n", "E_MUTATION_MARKER", "ok");
    try expectCodes("def f(grid: list[list[int]]) -> int:\n    total = 0\n    for row in grid:\n        local = row\n        local.append(0)\n        total = total + len(local)\n    return total\n", "E_MUTATION_MARKER", "ok");
}

// spec-case: VALUE-SEMANTICS-4
test "a parameter stays read-only and says so under the switch" {
    try expectCodes("def f(xs: list[int]) -> None:\n    xs.append(1)\n", "E_MUTATION_MARKER", "E_MUTATION_MARKER");
    try expectCodes("record R:\n    items: list[int]\n\ndef f(r: R) -> None:\n    r.items.append(1)\n", "E_MUTATION_MARKER", "E_MUTATION_MARKER");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const message = try switchedMessage(arena.allocator(), "def f(xs: list[int]) -> None:\n    xs.append(1)\n");
    try t.expect(std.mem.indexOf(u8, message, "read-only here; declare `xs: mut list[int]`") != null);
    try t.expect(std.mem.indexOf(u8, message, "assign it to a local (`copy = xs`)") != null);
}

// spec-case: VALUE-SEMANTICS-4
test "a write through a loop or match binding is a binding write" {
    try expectCodes("def f(grid: list[list[int]]) -> None:\n    for row in grid:\n        row.append(0)\n", "E_MUTATION_MARKER", "E_VALUE_BINDING_WRITE");
    try expectCodes("def f(grid: list[list[int]]) -> None:\n    for i, row in enumerate(grid):\n        row.append(i)\n", "E_MUTATION_MARKER", "E_VALUE_BINDING_WRITE");
    try expectCodes("def f(d: dict[str, list[int]]) -> None:\n    for v in d.values():\n        v.append(0)\n", "E_MUTATION_MARKER", "E_VALUE_BINDING_WRITE");
    try expectCodes("def f(d: dict[str, list[int]]) -> None:\n    for k, v in d.items():\n        v.append(0)\n", "E_MUTATION_MARKER", "E_VALUE_BINDING_WRITE");
    try expectCodes("record P:\n    x: int\n\ndef f(ps: list[P]) -> None:\n    for p in ps:\n        p.x = 1\n", "E_DEAD_RECORD_WRITE", "E_VALUE_BINDING_WRITE");
    try expectCodes("def fill(xs: mut list[int]) -> None:\n    xs.append(1)\n\ndef f(grid: list[list[int]]) -> None:\n    for row in grid:\n        fill(mut row)\n", "E_MUTATION_MARKER", "E_VALUE_BINDING_WRITE");
    const payload =
        \\def f(opt: Option[list[int]]) -> int:
        \\    match opt:
        \\        case Some(v):
        \\            v.append(1)
        \\            return len(v)
        \\        case None:
        \\            return 0
        \\
    ;
    try expectCodes(payload, "E_MUTATION_MARKER", "E_VALUE_BINDING_WRITE");
}

// spec-case: VALUE-SEMANTICS-4
test "a record loop binding is read-only and a match on a call result stays writable" {
    const loop_write = "record Body:\n    items: list[int]\n\ndef f(bodies: mut list[Body]) -> None:\n    for b in bodies:\n        b.items.append(1)\n";
    try expectCodes(loop_write, "ok", "E_MUTATION_MARKER");
    try t.expectEqual(@as(usize, 1), try countCode(loop_write, "E_VALUE_BINDING_WRITE", true));
    const call_result =
        \\def make() -> Option[list[int]]:
        \\    return Some([1])
        \\
        \\def f() -> int:
        \\    match make():
        \\        case Some(v):
        \\            v.append(2)
        \\            return len(v)
        \\        case None:
        \\            return 0
        \\
    ;
    try expectCodes(call_result, "ok", "ok");
    try expectCodes("def f(grid: list[list[int]]) -> int:\n    total = 0\n    for row in grid:\n        total = total + len(row)\n    return total\n", "ok", "ok");
}

// spec-case: VALUE-SEMANTICS-4
test "a write into a returned value is a temporary write" {
    const returned =
        \\record Env:
        \\    slots: list[int]
        \\
        \\def env_of(envs: list[Env], index: int) -> Env:
        \\    return envs[index]
        \\
        \\def f(envs: list[Env]) -> None:
        \\    env_of(envs, 0).slots.append(1)
        \\
    ;
    try expectCodes(returned, "E_MUTATION_MARKER", "E_VALUE_TEMPORARY_WRITE");
}

// spec-case: VALUE-SEMANTICS-3
test "a mut record parameter is inout and its argument must be a local" {
    try expectCodes("record C:\n    n: int\n\ndef f(c: mut C) -> None:\n    c.n = c.n + 1\n", "ok", "ok");
    try expectCodes("record Inner:\n    x: int\n    items: list[int]\n\nrecord Outer:\n    inner: Inner\n\ndef f(o: mut Outer) -> None:\n    o.inner.x = 3\n    o.inner.items.append(1)\n", "ok", "ok");
    const field_argument =
        \\record C:
        \\    n: int
        \\    items: list[int]
        \\
        \\record Holder:
        \\    c: C
        \\
        \\def f(c: mut C) -> None:
        \\    c.items.append(1)
        \\
        \\def g(h: mut Holder) -> None:
        \\    f(mut h.c)
        \\
    ;
    try expectCodes(field_argument, "E_MUTATION_MARKER", "E_MUTATION_MARKER");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(std.mem.indexOf(u8, try switchedMessage(arena.allocator(), field_argument), "`mut` on a record passes a variable itself") != null);
    try expectCodes("def f(n: mut int) -> None:\n    n = n + 1\n", "E_MUTATION_MARKER", "E_MUTATION_MARKER");
    try t.expect(std.mem.indexOf(u8, try switchedMessage(arena.allocator(), "def f(n: mut int) -> None:\n    n = n + 1\n"), "return the new value instead") != null);
}

// spec: VALUE-SEMANTICS-6
test "a mut parameter whose only change went to a local copy says to store it back" {
    const lost =
        \\def smooth(row: mut list[int]) -> None:
        \\    row.append(0)
        \\
        \\def smooth_rows(rows: mut list[list[int]]) -> None:
        \\    for i in range(len(rows)):
        \\        row = rows[i]
        \\        smooth(mut row)
        \\
    ;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const switched = try verdict(arena.allocator(), lost, true);
    try t.expectEqualStrings("E_MUTATION_MARKER", switched.code);
    try t.expect(std.mem.indexOf(u8, switched.message, "the only change goes to `row`, a copy of `rows[i]`") != null);
    try t.expect(std.mem.indexOf(u8, switched.message, "store the copy back after changing it (`rows[i] = row`)") != null);
    try t.expect(std.mem.indexOf(u8, switched.message, "remove `mut`") == null);
    const whole = try switchedMessage(arena.allocator(), "def grow(xs: mut list[int]) -> None:\n    ys = xs\n    ys.append(1)\n");
    try t.expect(std.mem.indexOf(u8, whole, "change `xs` in place") != null);
    const off = try verdict(arena.allocator(), lost, false);
    try t.expect(std.mem.indexOf(u8, off.message, "store the copy back") == null);
}

// spec-case: VALUE-SEMANTICS-7
test "old of a collection is a value under the switch" {
    const captured = "@ensures(len(xs) == len(old(xs)) + 1)\ndef push(xs: mut list[int]) -> None:\n    xs.append(1)\n";
    try expectCodes(captured, "E_CONTRACT_OLD_SHARED", "ok");
    const class_capture = "class Box:\n    n: int\n\n@ensures(old(b).n <= b.n)\ndef bump(b: mut Box) -> None:\n    b.n = b.n + 1\n";
    try expectCodes(class_capture, "E_CONTRACT_OLD_SHARED", "E_VALUE_CLASS");
}

// spec: VALUE-SEMANTICS-10
test "class and builtin Cell retire only under value semantics" {
    try expectCodes("class Box:\n    n: int\n", "ok", "E_VALUE_CLASS");
    try expectCodes("def peek(slot: Cell[int]) -> int:\n    return slot.value\n", "ok", "E_VALUE_CELL");
    try expectCodes("def make() -> int:\n    slot = Cell(value=3)\n    return slot.value\n", "ok", "E_VALUE_CELL");
    try expectCodes("record Cell:\n    value: int\n\ndef make() -> int:\n    return Cell(value=3).value\n", "ok", "ok");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const class_message = try switchedMessage(arena.allocator(), "class Box:\n    n: int\n");
    try t.expect(std.mem.indexOf(u8, class_message, "recursive union") != null);
    try t.expect(std.mem.indexOf(u8, class_message, "pool handle") != null);
    const cell_message = try switchedMessage(arena.allocator(), "def peek(slot: Cell[int]) -> int:\n    return slot.value\n");
    try t.expect(std.mem.indexOf(u8, cell_message, "store-back") != null);
}

/// How many diagnostics with `code` checking `body` reports with the switch at `on`.
fn countCode(body: []const u8, code: []const u8, on: bool) !usize {
    const saved = Saved.set(on);
    defer saved.restore();
    const text = try std.mem.concat(t.allocator, u8, &.{ body, entry });
    defer t.allocator.free(text);
    var compilation = try compiler.Compilation.init(t.allocator, "warnings.my", text);
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
    const reset = "record Counter:\n    n: int\n    items: list[int]\n\ndef reset(c: mut Counter) -> None:\n    c = Counter(n=0, items=[])\n";
    try t.expectEqual(@as(usize, 0), try countCode(reset, "W_UNUSED_BINDING", true));
    try t.expectEqual(@as(usize, 0), try countCode(reset, "E_MUTATION_MARKER", true));
}

// spec-case: D2-VIEW-STORAGE-1
test "D2 declarations reject nested recursive view projection storage" {
    const source = "record Viewed:\n    next: Option[Viewed]\n    views: [1]list[DictValues[int,int]]\n" ++ entry;
    var compilation = try compiler.Compilation.init(t.allocator, "reach.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_VIEW_STORED", compilation.diagnostics.items[0].code);
}
