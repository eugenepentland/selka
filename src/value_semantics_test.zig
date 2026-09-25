//! Value semantics (`VALUE-SEMANTICS-1`..`-7`): the checker's verdicts and
//! messages with the switch on and off, the copy sites lowering places and the
//! ones the ownership analysis keeps, and the cache keys the switch changes.
//! Guest behaviour under the switch is tested in `tests/value_semantics`.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const values = @import("value_semantics.zig");
const fragments = @import("qbe_fragments.zig");

const entry = "\n\ndef main() -> int:\n    return 0\n";

/// The switch as a test left it, restored when the test ends.
const Saved = struct {
    previous: bool,
    fn set(on: bool) Saved {
        const saved: Saved = .{ .previous = values.enabled() };
        values.setEnabled(on);
        return saved;
    }
    fn restore(self: Saved) void {
        values.setEnabled(self.previous);
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

/// How many copy sites lowering placed in `source`, and how many of them the
/// ownership analysis keeps as real copies.
const Sites = struct { placed: usize = 0, copies: usize = 0 };

fn sites(source: []const u8, on: bool) !Sites {
    const saved = Saved.set(on);
    defer saved.restore();
    var compilation = try compiler.Compilation.init(t.allocator, "sites.my", source);
    defer compilation.deinit();
    const text = try compilation.explainOwnership(t.allocator);
    defer t.allocator.free(text);
    var counted: Sites = .{};
    counted.placed = std.mem.count(u8, text, "\"site\":");
    counted.copies = std.mem.count(u8, text, "\"copy\":true");
    return counted;
}

const assignments =
    \\def main() -> int:
    \\    a = [1]
    \\    b = a
    \\    b.append(2)
    \\    c = b
    \\    c.append(3)
    \\    return len(a) * 10 + len(c)
    \\
;

// spec-case: VALUE-SEMANTICS-1
test "value semantics off places no copy site at all" {
    const off = try sites(assignments, false);
    try t.expectEqual(@as(usize, 0), off.placed);
    const on = try sites(assignments, true);
    try t.expect(on.placed >= 2);
}

// spec-case: VALUE-SEMANTICS-2
test "a copy another name still reads is kept and a dead source moves" {
    // `b = a` copies (`a` is read after `b` is written); `c = b` moves (`b`
    // is dead), as does the literal's move into `a`.
    const on = try sites(assignments, true);
    try t.expectEqual(@as(usize, 1), on.copies);
    try t.expect(on.placed > on.copies);
}

// spec-case: VALUE-SEMANTICS-2
test "a transfer neither side writes is a borrow and copies nothing" {
    const shared =
        \\def total(xs: list[int]) -> int:
        \\    return len(xs)
        \\
        \\def main() -> int:
        \\    a = [1, 2]
        \\    b = a
        \\    return total(b) + total(a)
        \\
    ;
    const on = try sites(shared, true);
    try t.expect(on.placed >= 1);
    try t.expectEqual(@as(usize, 0), on.copies);
}

// spec-case: VALUE-SEMANTICS-2
test "a list read out of a class object is always a real copy" {
    const through_class =
        \\class Box:
        \\    items: list[int]
        \\
        \\def main() -> int:
        \\    box = Box(items=[1])
        \\    taken = box.items
        \\    return len(taken)
        \\
    ;
    const on = try sites(through_class, true);
    try t.expect(on.copies >= 1);
}

// spec-case: VALUE-SEMANTICS-2
test "a shallow copy of nested lists copies the inner lists" {
    const nested =
        \\def main() -> int:
        \\    grid = [[1], [2]]
        \\    rows = grid.copy()
        \\    return len(rows) + len(grid)
        \\
    ;
    const on = try sites(nested, true);
    try t.expect(on.copies >= 1);
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
test "a class binding and a match on a call result stay writable" {
    try expectCodes("class Body:\n    x: int\n\ndef f(bodies: mut list[Body]) -> None:\n    for b in bodies:\n        b.x = 1\n", "ok", "ok");
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
    try expectCodes("record C:\n    n: int\n\ndef f(c: mut C) -> None:\n    c.n = c.n + 1\n", "E_MUTATION_MARKER", "ok");
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
    try expectCodes(field_argument, "ok", "E_MUTATION_MARKER");
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    try t.expect(std.mem.indexOf(u8, try switchedMessage(arena.allocator(), field_argument), "`mut` on a record passes a variable itself") != null);
    try expectCodes("def f(n: mut int) -> None:\n    n = n + 1\n", "E_MUTATION_MARKER", "E_MUTATION_MARKER");
    try t.expect(std.mem.indexOf(u8, try switchedMessage(arena.allocator(), "def f(n: mut int) -> None:\n    n = n + 1\n"), "return the new value instead") != null);
}

// spec-case: VALUE-SEMANTICS-5
test "a read-only argument never overlaps and one a mut argument reaches is a snapshot" {
    try expectCodes("def touch(x: mut list[int], y: list[int]) -> None:\n    x.append(len(y))\n\ndef use(a: mut list[int], b: list[int]) -> None:\n    touch(mut a, b)\n", "E_MUTATION_OVERLAP", "ok");
    const helper =
        \\def walk(adj: list[list[int]], node: int, path: mut list[int], found: mut list[list[int]]) -> None:
        \\    path.append(node)
        \\    found.append(path.copy())
        \\    for nxt in adj[node]:
        \\        walk(adj, nxt, mut path, mut found)
        \\    _ = path.pop()
        \\
    ;
    try expectCodes(helper, "E_MUTATION_OVERLAP", "ok");
    const same_root =
        \\def touch(x: mut list[int], y: list[int]) -> int:
        \\    x.append(len(y))
        \\    return len(y)
        \\
        \\def main() -> int:
        \\    a = [1, 2]
        \\    return touch(mut a, a)
        \\
    ;
    const on = try sites(same_root, true);
    try t.expect(on.copies >= 1);
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
test "old of a collection is a value under the switch and a class stays shared" {
    const captured = "@ensures(len(xs) == len(old(xs)) + 1)\ndef push(xs: mut list[int]) -> None:\n    xs.append(1)\n";
    try expectCodes(captured, "E_CONTRACT_OLD_SHARED", "ok");
    const class_capture = "class Box:\n    n: int\n\n@ensures(old(b).n <= b.n)\ndef bump(b: mut Box) -> None:\n    b.n = b.n + 1\n";
    try expectCodes(class_capture, "E_CONTRACT_OLD_SHARED", "E_CONTRACT_OLD_SHARED");
}

// spec-case: VALUE-SEMANTICS-1
test "the switch changes the fragment record key and nothing without it" {
    const identity: fragments.Digest = @splat(7);
    const saved = Saved.set(false);
    defer saved.restore();
    const off = fragments.recordKey(identity, false);
    values.setEnabled(true);
    const on = fragments.recordKey(identity, false);
    values.setEnabled(false);
    try t.expect(!std.mem.eql(u8, &off, &on));
    try t.expectEqualSlices(u8, &off, &fragments.recordKey(identity, false));
    try t.expect(values.environmentEnables("1"));
    try t.expect(!values.environmentEnables("0"));
    try t.expect(!values.environmentEnables(null));
}
