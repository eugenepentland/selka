//! MUT-EXCLUSIVE-1..3: the places two `mut` arguments of one call name must be
//! disjoint. Each rejected call is checked for its code, the argument it points
//! at and the reason in its message; each legal call must check clean.
const std = @import("std");
const t = std.testing;
const compiler = @import("compiler.zig");
const LegacySharing = @import("test_support.zig").LegacySharing;
const File = compiler.embedded_project.File;

const helpers =
    \\record R:
    \\    rows: list[list[int]]
    \\    n: int
    \\
    \\record S:
    \\    a: list[int]
    \\    b: list[int]
    \\
    \\enum Status:
    \\    ok,
    \\    failed
    \\
    \\def two(a: mut list[int], b: mut list[int]) -> None:
    \\    a.append(1)
    \\    b.append(2)
    \\
    \\def nested(xs: mut list[list[int]], ys: mut list[int]) -> None:
    \\    xs.append([5])
    \\    ys.append(9)
    \\
    \\def same(xs: mut list[list[int]], ys: mut list[list[int]]) -> None:
    \\    xs.append([5])
    \\    ys.append([9])
    \\
    \\def rec(a: mut R, xs: mut list[list[int]]) -> None:
    \\    a.n = a.n + 1
    \\    xs.append([1])
    \\
    \\def records(a: mut S, b: mut S) -> None:
    \\    a.a.append(1)
    \\    b.b.append(2)
    \\
    \\def read_one(a: mut list[int], b: list[int]) -> int:
    \\    a.append(len(b))
    \\    return len(b)
    \\
    \\def make(p: mut list[int]) -> int:
    \\    p.append(3)
    \\    return len(p)
    \\
    \\def emit(p: mut list[int], c: int) -> None:
    \\    p.append(c)
    \\
    \\def inner_first(ys: mut list[int], xs: mut list[list[int]]) -> None:
    \\    ys.append(9)
    \\    xs.append([5])
    \\
    \\
;

/// The first diagnostic of `body` appended to the helper declarations: its
/// code, message, and the source text of its span and related span.
const Verdict = struct { code: []const u8, message: []const u8, span: []const u8, related: []const u8, later: bool };

fn verdict(allocator: std.mem.Allocator, body: []const u8) !?Verdict {
    return verdictOf(allocator, try std.mem.concat(allocator, u8, &.{ helpers, body }));
}

/// The first diagnostic of a whole program, as `verdict` reports it.
fn verdictOf(allocator: std.mem.Allocator, bytes: []const u8) !?Verdict {
    var compilation = try compiler.Compilation.init(allocator, "mut-exclusive.my", bytes);
    if (compilation.check()) |_| return null else |err| if (err != error.SourceError) return err;
    const first = compilation.diagnostics.items[0];
    return .{
        .code = first.code,
        .message = first.message,
        .span = compilation.src.text(first.span),
        .related = if (first.related) |related| compilation.src.text(related.span) else "",
        .later = if (first.related) |related| related.span.start < first.span.start else false,
    };
}

/// What an accepted program reports in place of a diagnostic.
const accepted_code = "accepted";
const accepted: Verdict = .{ .code = accepted_code, .message = "", .span = "", .related = "", .later = false };

/// `needle` when `message` contains it, otherwise the whole message, so a
/// failed comparison prints the message it looked in.
fn containing(message: []const u8, needle: []const u8) []const u8 {
    return if (std.mem.indexOf(u8, message, needle) != null) needle else message;
}

/// Check that `body` is rejected at `span` (the later argument) with a message
/// containing `why`, and that the related span is `related`.
fn rejects(comptime body: []const u8, span: []const u8, related: []const u8, why: []const u8) !void {
    return rejectsProgram(helpers ++ body, span, related, why);
}

/// `rejects` for a whole program, without the helper declarations.
fn rejectsProgram(bytes: []const u8, span: []const u8, related: []const u8, why: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = (try verdictOf(arena.allocator(), bytes)) orelse accepted;
    try t.expectEqualStrings("E_MUTATION_OVERLAP", found.code);
    try t.expectEqualStrings(span, found.span);
    try t.expectEqualStrings(related, found.related);
    try t.expect(found.later or std.mem.indexOf(u8, found.message, "receiver `") != null);
    try t.expectEqualStrings(why, containing(found.message, why));
}

/// Check that `body` checks clean; a failure prints the diagnostic's message.
fn accepts(body: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const found = (try verdict(arena.allocator(), body)) orelse accepted;
    try t.expectEqualStrings("", found.message);
    try t.expectEqualStrings(accepted_code, found.code);
}

fn main(comptime statements: []const u8) []const u8 {
    return "def main() -> int:\n" ++ statements ++ "    return 0\n";
}

// spec: MUT-EXCLUSIVE-1
test "two mut arguments naming one place or a place and its part are rejected" {
    try rejects(main("    b = [[1, 2], [3]]\n    same(mut b, mut b)\n"), "mut b", "mut b", "both name `b`");
    try rejects(main("    a = [[1, 2], [3]]\n    nested(mut a, mut a[0])\n"), "mut a[0]", "mut a", "`a[0]` is part of `a`");
    try rejects(main("    r = R([[1, 2], [3]], 0)\n    rec(mut r, mut r.rows)\n"), "mut r.rows", "mut r", "`r.rows` is part of `r`");
    try rejects(main("    xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[0])\n"), "mut xs[0]", "mut xs[0]", "both name `xs[0]`");
    try rejects(main("    s = S([1], [2])\n    two(mut s.a, mut s.a)\n"), "mut s.a", "mut s.a", "both name `s.a`");
}

// spec-case: MUT-EXCLUSIVE-1
test "two mut indices that are not two different constants may name one element" {
    try rejects(main("    xs = [[1], [2], [3]]\n    i = 0\n    j = 1\n    two(mut xs[i], mut xs[j])\n"), "mut xs[j]", "mut xs[i]", "`i` and `j` are not");
    try rejects(main("    xs = [[1], [2], [3]]\n    i = 0\n    two(mut xs[i], mut xs[0])\n"), "mut xs[0]", "mut xs[i]", "may name one element");
    try rejects(main("    xs = [[1], [2], [3]]\n    two(mut xs[-1], mut xs[2])\n"), "mut xs[2]", "mut xs[-1]", "a negative index counts back from the end");
    try rejects(main("    xs = [[1], [2], [3]]\n    two(mut xs[1 + 1], mut xs[0])\n"), "mut xs[0]", "mut xs[1 + 1]", "`1 + 1` and `0` are not");
    try rejects(main("    d = {1: [1], 2: [2]}\n    k = 1\n    two(mut d[k], mut d[2])\n"), "mut d[2]", "mut d[k]", "may name one entry");
    try rejects(main("    rows = [S([1], [2]), S([3], [4])]\n    i = 0\n    j = 1\n    two(mut rows[i].a, mut rows[j].a)\n"), "mut rows[j].a", "mut rows[i].a", "`i` and `j` are not");
    const table = "    t: [Status]list[int] = {Status.ok: [1], Status.failed: [2]}\n    two(mut t[Status.ok], mut t[Status.ok])\n";
    try rejects(main(table), "mut t[Status.ok]", "mut t[Status.ok]", "both name `t[Status.ok]`");
}

// spec-case: MUT-EXCLUSIVE-1
test "mut arguments naming provably disjoint places stay legal" {
    try accepts(main("    s = S([1], [2])\n    two(mut s.a, mut s.b)\n"));
    try accepts(main("    xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[2])\n"));
    try accepts(main("    xs = [[1], [2], [3]]\n    two(mut xs[-1], mut xs[-2])\n"));
    try accepts(main("    d = {\"a\": [1], \"b\": [2]}\n    two(mut d[\"a\"], mut d[\"b\"])\n"));
    try accepts(main("    d = {-1: [1], 2: [2]}\n    two(mut d[-1], mut d[2])\n"));
    try accepts(main("    rows = [S([1], [2]), S([3], [4])]\n    i = 0\n    j = 1\n    two(mut rows[i].a, mut rows[j].b)\n"));
    try accepts(main("    t: [Status]list[int] = {Status.ok: [1], Status.failed: [2]}\n    two(mut t[Status.ok], mut t[Status.failed])\n"));
    try accepts(main("    a = [1]\n    b = [2]\n    two(mut a, mut b)\n"));
    try accepts("const LAST: int = 2\n\n" ++ comptime main("    xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[LAST])\n"));
    try accepts(main("    s = S([1], [2])\n    o = S([3], [4])\n    records(mut s, mut o)\n"));
}

// spec: MUT-EXCLUSIVE-2
test "the exclusivity rule covers keyword and indirect calls but not read-only or nested arguments" {
    try rejects(main("    xs = [[1], [2], [3]]\n    two(b=mut xs[0], a=mut xs[0])\n"), "mut xs[0]", "mut xs[0]", "both name `xs[0]`");
    try accepts(main("    xs = [[1], [2], [3]]\n    two(b=mut xs[2], a=mut xs[0])\n"));
    try rejects(main("    v = [1]\n    action = two\n    action(mut v, mut v)\n"), "mut v", "mut v", "both name `v`");
    try accepts(main("    v = [1]\n    w = [2]\n    action = two\n    action(mut v, mut w)\n"));
    try accepts(main("    a = [1, 2]\n    _ = read_one(mut a, a)\n"));
    try accepts(main("    p = [1]\n    emit(mut p, make(mut p))\n"));
    const legacy = LegacySharing.enter();
    defer legacy.restore();
    try rejects(main("    b = [[1, 2], [3]]\n    same(mut b, mut b)\n"), "mut b", "mut b", "both name `b`");
    try accepts(main("    xs = [[1], [2], [3]]\n    two(mut xs[0], mut xs[2])\n"));
}

// spec: MUT-EXCLUSIVE-3
test "the exclusivity diagnostic points at the later argument and spells the rewrite" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const body = main("    a = [[1, 2], [3]]\n    nested(mut a, mut a[0])\n");
    const found = (try verdict(arena.allocator(), body)) orelse accepted;
    try t.expectEqualStrings("E_MUTATION_OVERLAP", found.code);
    try t.expectEqualStrings("mut a[0]", found.span);
    try t.expectEqualStrings("mut a", found.related);
    try t.expectEqualStrings(
        "`nested` receives overlapping `mut` arguments `mut a` and `mut a[0]`: `a[0]` is part of `a`, and two `mut` arguments of one call must name disjoint places. " ++
            "Copy one into a local, pass `mut` that local and store it back (`copy = a[0]`, pass `mut copy`, then `a[0] = copy`), " ++
            "or pass the enclosing value `mut a` once",
        found.message,
    );
    // A contained place is the one to copy even when it comes first.
    const reversed = (try verdict(arena.allocator(), main("    a = [[1, 2], [3]]\n    inner_first(mut a[0], mut a)\n"))) orelse accepted;
    try t.expectEqualStrings("mut a", reversed.span);
    try t.expect(std.mem.indexOf(u8, reversed.message, "`a[0]` is part of `a`") != null);
    try t.expect(std.mem.indexOf(u8, reversed.message, "(`copy = a[0]`, pass `mut copy`, then `a[0] = copy`)") != null);
    const keyword = (try verdict(arena.allocator(), main("    xs = [[1], [2]]\n    i = 1\n    two(b=mut xs[i], a=mut xs[0])\n"))) orelse accepted;
    try t.expectEqualStrings("mut xs[0]", keyword.span);
    try t.expectEqualStrings("mut xs[i]", keyword.related);
    try t.expect(std.mem.indexOf(u8, keyword.message, "pass the enclosing value `mut xs` once") != null);
}

// The aliasing calls guest tests made before MUT-EXCLUSIVE-1, each now rejected;
// the guest tests pass disjoint places instead (tests/lang/mut_argument_places.my,
// rc_mut_aliases.my, rc_mut_list_aliases.my, mut_record_call_window.my,
// rc_caller_field_reads.my, migrated/effects_case_6.my and
// tests/value_semantics/{calls,field_return,index_return}.my).
// spec-case: MUT-EXCLUSIVE-1
test "the aliasing calls converted guest tests used to make are rejected" {
    const dictionaries = "def write_twice(first: mut dict[int, int], second: mut dict[int, int]) -> int:\n    first[1] = 13\n    second[1] = 17\n    return first[1]\n\n";
    try rejectsProgram(dictionaries ++ "def main() -> int:\n    original = {0: {1: 7}}\n    return write_twice(mut original[0], mut original[0])\n", "mut original[0]", "mut original[0]", "both name `original[0]`");
    try rejectsProgram(dictionaries ++ "def main() -> int:\n    original = {1: 7}\n    action = write_twice\n    return action(mut original, mut original)\n", "mut original", "mut original", "both name `original`");
    const frames = "record Frame:\n    rows: list[list[int]]\n    n: int\n\ndef interval(frame: mut Frame, other: mut Frame) -> int:\n    frame.n = frame.n + 1\n    other.rows = [[7]]\n    return 0\n\n" ++
        "def contained(frame: mut Frame, rows: mut list[list[int]]) -> int:\n    frame.n = frame.n + 1\n    rows.clear()\n    return 0\n\n";
    try rejectsProgram(frames ++ "def main() -> int:\n    frame = Frame([[1, 2], [3]], 0)\n    return interval(mut frame, mut frame)\n", "mut frame", "mut frame", "both name `frame`");
    try rejectsProgram(frames ++ "def main() -> int:\n    frame = Frame([[1, 2], [3]], 0)\n    return contained(mut frame, mut frame.rows)\n", "mut frame.rows", "mut frame", "`frame.rows` is part of `frame`");
    const lists = "def write_both(x: mut list[int], y: mut list[int]) -> None:\n    x[0] = 1\n    y[0] = 2\n\ndef use(values: mut list[int]) -> None:\n    write_both(mut values, mut values)\n\n";
    try rejectsProgram(lists ++ "def main() -> int:\n    values = [0, 0]\n    use(mut values)\n    return values[0]\n", "mut values", "mut values", "both name `values`");
    const both = "def touch_both(first: mut list[int], second: mut list[int], source: list[int]) -> int:\n    first.append(len(source))\n    second.append(len(source))\n    return len(source)\n\n";
    try rejectsProgram(both ++ "def main() -> int:\n    items = [1, 2]\n    return touch_both(mut items, mut items, items)\n", "mut items", "mut items", "both name `items`");
}

/// An embedded two-module project: `main` plus the `library.lists` module.
const Files = struct {
    entries: []const File,
    fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) compiler.project.ReadError![]u8 {
        const self: *Files = @ptrCast(@alignCast(context.?));
        return compiler.embedded_project.read(allocator, self.entries, path, limit);
    }
};

const library =
    \\module library.lists
    \\
    \\
    \\public def two(a: mut list[int], b: mut list[int]) -> None:
    \\    a.append(1)
    \\    b.append(2)
    \\
;

/// The first diagnostic code of the project whose `main` calls `call`, and the
/// source text it points at; "accepted" and "" when the project checks clean.
fn qualified(allocator: std.mem.Allocator, comptime call: []const u8) ![2][]const u8 {
    const main_source = "module main\nimport library.lists as lists\n\n\ndef main() -> int:\n    v = [1]\n    w = [2]\n    " ++ call ++ "\n    return len(v) + len(w)\n";
    var files: Files = .{ .entries = &.{ .{ .path = "main.my", .bytes = main_source }, .{ .path = "library/lists.my", .bytes = library } } };
    var project = compiler.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = &files, .read = Files.read }, "main", .{});
    var index = try compiler.interfaces.build(&project);
    var compilation = try compiler.project_compile.Compilation.init(&index);
    if (compilation.check()) |_| return .{ accepted_code, "" } else |err| if (err != error.SourceError) return err;
    const first = compilation.diagnostics.items.items[0];
    return .{ first.code, try allocator.dupe(u8, compilation.src.text(first.span)) };
}

// spec-case: MUT-EXCLUSIVE-2
test "the exclusivity rule covers a module-qualified call" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const rejected = try qualified(arena.allocator(), "lists.two(mut v, mut v)");
    try t.expectEqualStrings("E_MUTATION_OVERLAP", rejected[0]);
    try t.expectEqualStrings("mut v", rejected[1]);
    const legal = try qualified(arena.allocator(), "lists.two(mut v, mut w)");
    try t.expectEqualStrings(accepted_code, legal[0]);
}

// spec: MUT-OVERLAP-RECEIVER-1
test "receiver overlap rejects assignments and updates while keeping independent roots" {
    try rejects(main("    p = [1]\n    p[make(mut p)] = 9\n"), "mut p", "p[make(mut p)]", "own statement first");
    try rejects(main("    p = [1]\n    p[0] = make(mut p)\n"), "mut p", "p[0]", "own statement first");
    try rejects(main("    p = [1]\n    p.append(make(mut p))\n"), "mut p", "p", "own statement first");
    try accepts(main("    p = [1]\n    q = [2]\n    p[0] = make(mut q)\n"));
    try accepts(main("    p = [1]\n    value = make(mut p)\n    p[0] = value\n"));
    try accepts(main("    p = [1]\n    p.append(len(p))\n"));
    try accepts(main("    s = S([1], [2])\n    s.a[0] = make(mut s.b)\n"));
}

// spec-case: MUT-OVERLAP-RECEIVER-1
test "receiver overlap covers enclosing records and nested constant paths" {
    try rejects(main("    r = R([[1]], 0)\n    r.rows[0].append(make(mut r.rows[0]))\n"), "mut r.rows[0]", "r.rows[0]", "own statement first");
    const points = "record Point:\n    x: int\n\ndef save(points: mut list[Point]) -> int:\n    points.append(Point(1))\n    return 0\n\n" ++
        "def main() -> int:\n    points = [Point(0)]\n    points[save(mut points)].x = 13\n    return 0\n";
    try rejectsProgram(points, "mut points", "points[save(mut points)].x", "own statement first");
    try accepts(main("    r = R([[1], [2]], 0)\n    r.rows[0].append(make(mut r.rows[1]))\n"));
}

// spec-case: MUT-OVERLAP-RECEIVER-1
test "receiver overlap covers mapping and set updates keyword calls and function values" {
    const set = "def select(flags: mut set[int]) -> int:\n    flags.add(2)\n    return 3\n\n";
    try rejectsProgram(set ++ "def main() -> int:\n    flags = {1}\n    flags.add(select(mut flags))\n    return len(flags)\n", "mut flags", "flags", "own statement first");
    try rejectsProgram(set ++ "def main() -> int:\n    flags = {1}\n    flags.discard(select(mut flags))\n    return len(flags)\n", "mut flags", "flags", "own statement first");
    const dict = "def select(values: mut dict[int, int]) -> int:\n    values[2] = 3\n    return 0\n\n";
    try rejectsProgram(dict ++ "def main() -> int:\n    values = {0: 1}\n    values[select(mut values)] = 9\n    return len(values)\n", "mut values", "values[select(mut values)]", "own statement first");
    try rejects(main("    p = [1]\n    p[0] = make(p=mut p)\n"), "mut p", "p[0]", "own statement first");
    try rejects(main("    p = [1]\n    action = make\n    p[action(mut p)] = 9\n"), "mut p", "p[action(mut p)]", "own statement first");
}

// spec-case: MUT-OVERLAP-RECEIVER-1
test "receiver overlap uses the collection method vocabulary for byte buffers" {
    const buffer = "def grow(buffer: mut byte_buffer) -> int:\n    _ = buffer.append_byte(1)\n    return 2\n\n";
    try rejectsProgram(buffer ++ "def main() -> int:\n    buffer = byte_buffer([1])\n    _ = buffer.append_byte(grow(mut buffer))\n    return len(buffer)\n", "mut buffer", "buffer", "own statement first");
    try rejectsProgram(buffer ++ "def main() -> int:\n    buffer = byte_buffer([1])\n    _ = buffer.reserve(grow(mut buffer))\n    return len(buffer)\n", "mut buffer", "buffer", "own statement first");
}

// spec-case: PY-ARRAY-MUT-1
test "whole fixed array mut parameter rebinding remains an assignment target error" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const source = "def reset(values: mut [2]int):\n    values = [3, 4]\n\ndef main() -> int:\n    values: [2]int = [1, 2]\n    reset(mut values)\n    return values[0]\n";
    const found = (try verdictOf(arena.allocator(), source)) orelse return error.TestUnexpectedResult;
    try t.expectEqualStrings("E_ASSIGNMENT_TARGET", found.code);
    try t.expectEqualStrings("values", found.span);
}
