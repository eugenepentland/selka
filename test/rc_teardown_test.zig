//! RC traps and exits against the tracing collector, through the CLI. A trap
//! runs no frame cleanup: the resource registry closes every resource exactly
//! once, as it does for the collector, and the heap is then released
//! wholesale. A normal exit drops exactly the values its frame still owns. Each
//! program runs under both runtimes in its own directory; everything a user
//! can observe must match, and the counting RC runtime must balance its
//! allocations, retirements, owners and holds.
const std = @import("std");
const testing = std.testing;
const options = @import("test_options");

const counts_marker = "MYLANG_RC_COUNTS ";

/// What one run shows a user, with the RC count record split off stderr.
const Observed = struct {
    stdout: []const u8,
    stderr: []const u8,
    term: std.process.Child.Term,
    counts: []const u8,
    files: []const u8,
};

/// Run `text` with `runtime` flags in a fresh directory and record the streams,
/// termination, count record and the files the program left behind.
fn observe(a: std.mem.Allocator, runtime: []const []const u8, text: []const u8) !Observed {
    var temp = testing.tmpDir(.{ .iterate = true });
    defer temp.cleanup();
    try temp.dir.writeFile(testing.io, .{ .sub_path = "teardown.my", .data = text });
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, options.compiler_path, a);
    const qbe = try std.Io.Dir.cwd().realPathFileAlloc(testing.io, options.qbe_path, a);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ compiler, "run", "teardown.my", try std.fmt.allocPrint(a, "--qbe={s}", .{qbe}), "--zig=" ++ options.zig_path });
    try argv.appendSlice(a, runtime);
    const result = try std.process.run(a, testing.io, .{ .argv = argv.items, .cwd = .{ .dir = temp.dir } });
    var stderr: std.ArrayList(u8) = .empty;
    var counts: []const u8 = "";
    var lines = std.mem.splitScalar(u8, result.stderr, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, counts_marker)) {
            counts = line[counts_marker.len..];
            continue;
        }
        try stderr.appendSlice(a, line);
        try stderr.append(a, '\n');
    }
    try temp.dir.deleteFile(testing.io, "teardown.my");
    return .{ .stdout = result.stdout, .stderr = stderr.items, .term = result.term, .counts = counts, .files = try listing(a, temp.dir) };
}

/// Every file the guest left, sorted by name, each with its contents.
fn listing(a: std.mem.Allocator, directory: std.Io.Dir) ![]const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var walker = directory.iterate();
    while (try walker.next(testing.io)) |entry| {
        if (entry.kind != .file) continue;
        try names.append(a, try a.dupe(u8, entry.name));
    }
    std.mem.sort([]const u8, names.items, {}, struct {
        fn less(_: void, left: []const u8, right: []const u8) bool {
            return std.mem.lessThan(u8, left, right);
        }
    }.less);
    var out: std.ArrayList(u8) = .empty;
    for (names.items) |name| {
        const data = try directory.readFileAlloc(testing.io, name, a, .limited(1 << 20));
        try out.print(a, "{s}={s};", .{ name, data });
    }
    return out.items;
}

fn number(value: std.json.Value, key: []const u8) !i64 {
    const field = value.object.get(key) orelse return error.TestUnexpectedResult;
    return switch (field) {
        .integer => |integer| integer,
        else => error.TestUnexpectedResult,
    };
}

/// The counting runtime reports once, after teardown, and every allocation,
/// owner and hold it counted is matched by a retirement or release.
fn expectBalanced(a: std.mem.Allocator, record: []const u8) !void {
    try testing.expect(record.len != 0);
    const parsed = try std.json.parseFromSliceLeaky(std.json.Value, a, record, .{});
    try testing.expect(parsed.object.get("saturated").?.bool == false);
    const allocated = try number(parsed, "heap_allocate");
    try testing.expect(allocated > 0);
    try testing.expectEqual(allocated, try number(parsed, "retire"));
    try testing.expectEqual(allocated + try number(parsed, "owner_acquire"), try number(parsed, "owner_release"));
    try testing.expectEqual(try number(parsed, "hold_acquire"), try number(parsed, "hold_release"));
}

/// Run under the collector and the counting RC runtime and require identical
/// observations; return the RC observation for program-specific checks.
fn matchesCollector(a: std.mem.Allocator, text: []const u8) !Observed {
    const collected = try observe(a, &.{}, text);
    const counted = try observe(a, &.{"--rc-runtime=stats"}, text);
    try testing.expectEqualStrings(collected.stdout, counted.stdout);
    try testing.expectEqualStrings(collected.stderr, counted.stderr);
    try testing.expectEqual(collected.term, counted.term);
    try testing.expectEqualStrings(collected.files, counted.files);
    try testing.expectEqualStrings("", collected.counts);
    try expectBalanced(a, counted.counts);
    return counted;
}

const deep_files =
    \\record Level:
    \\    depth: int
    \\    names: list[str]
    \\
    \\def dig(fs: Filesystem, out: Stream, depth: int, trail: list[Level]) -> int:
    \\    held = Level(depth=depth, names=["level" + str(depth)])
    \\    if depth == 0:
    \\        out.print("bottom", len(trail))
    \\        return trail[len(trail)].depth
    \\    with fs.open("level" + str(depth) + ".txt", "w") as f:
    \\        _ = f.write("depth " + str(depth) + "\n")
    \\        more = trail
    \\        more.append(held)
    \\        return dig(fs, out, depth - 1, more) + len(held.names)
    \\
    \\def main(fs: Filesystem, out: Stream) -> int:
    \\    out.print("start")
    \\    return dig(fs, out, 12, [])
;

const inline_resources =
    \\resource File: filesystem
    \\
    \\result Open:
    \\    ok: File,
    \\    err: i64
    \\
    \\record Failure:
    \\    resource: File
    \\    code: i64
    \\
    \\result Finish:
    \\    ok: bool,
    \\    err: Failure
    \\
    \\result Status:
    \\    ok: i64,
    \\    err: i64
    \\
    \\def request(depth: int) -> [4]u8:
    \\    return [99u8, 58u8, 102u8, u8(48 + depth)]
    \\
    \\def finish(file: File) -> Status:
    \\    match complete_resource[Finish](file):
    \\        case Finish.ok(done):
    \\            _ = done
    \\            return Ok(0)
    \\        case Finish.err(failure):
    \\            return Err(failure.code)
    \\
    \\def hold(fs: Filesystem, depth: int, names: list[str]) -> Status:
    \\    file = acquire_resource[Open](fs, request(depth))?
    \\    if depth == 0:
    \\        return Ok(len(names[len(names)]))
    \\    more = names
    \\    more.append("f" + str(depth))
    \\    below = hold(fs, depth - 1, more)?
    \\    _ = finish(file)?
    \\    return Ok(below + 1)
    \\
    \\def main(fs: Filesystem) -> i64:
    \\    match hold(fs, 8, ["root"]):
    \\        case Status.ok(value):
    \\            return value
    \\        case Status.err(code):
    \\            return -code
;

const arena_trap =
    \\record Node:
    \\    items: list[int]
    \\    label: str
    \\
    \\def explode(n: int) -> int:
    \\    return 10 // n
    \\
    \\def main(out: Stream) -> int:
    \\    keep: list[Node] = [Node(items=[1, 2], label="outer")]
    \\    total = 0
    \\    with arena() as scratch:
    \\        inner: list[Node] = []
    \\        for i in range(5):
    \\            inner.append(Node(items=[i, i + 1], label="inner"))
    \\        inner.append(keep[0])
    \\        total = len(inner) + len(keep[0].items)
    \\        out.print("in arena", total)
    \\        total = total + explode(len(inner) - 6)
    \\    return total
;

const pinned_trap =
    \\record Box:
    \\    items: list[int]
    \\
    \\def explode(n: int) -> int:
    \\    return 10 // n
    \\
    \\def fill(boxes: mut list[Box], n: int) -> int:
    \\    boxes[0].items.append(explode(n))
    \\    return len(boxes[0].items)
    \\
    \\def grow(d: mut dict[str, list[int]], n: int) -> int:
    \\    d["a"].append(explode(n))
    \\    return len(d["a"])
    \\
    \\def main(out: Stream) -> int:
    \\    boxes = [Box(items=[1])]
    \\    d: dict[str, list[int]] = {"a": [1]}
    \\    out.print(fill(mut boxes, 2))
    \\    out.print(grow(mut d, 5))
    \\    return grow(mut d, 0) + fill(mut boxes, 0)
;

const nested_returns =
    \\record Box:
    \\    items: list[int]
    \\
    \\def value(n: int) -> Result[int, str]:
    \\    if n > 2:
    \\        return Err("big" + str(n))
    \\    return Ok(n)
    \\
    \\def fill(boxes: mut list[Box], n: int) -> Result[int, str]:
    \\    i = 0
    \\    while i < n:
    \\        boxes[0].items.append(value(i)?)
    \\        i += 1
    \\    return Ok(len(boxes[0].items))
    \\
    \\def grow(d: mut dict[str, list[int]], n: int) -> Result[int, str]:
    \\    d["a"].append(value(n)?)
    \\    return Ok(len(d["a"]))
    \\
    \\def first_big(rows: list[list[int]], limit: int) -> int:
    \\    for row in rows:
    \\        for item in row:
    \\            if item > limit:
    \\                return item
    \\    return -1
    \\
    \\def inside(limit: int) -> int:
    \\    with arena() as scratch:
    \\        rows: list[list[int]] = [[1, 2], [limit, 9]]
    \\        if limit > 3:
    \\            return first_big(rows, 3)
    \\    return 0
    \\
    \\def show(out: Stream, result: Result[int, str]) -> None:
    \\    match result:
    \\        case Ok(v):
    \\            out.print(v)
    \\        case Err(e):
    \\            out.print(e)
    \\
    \\def main(out: Stream) -> int:
    \\    boxes = [Box(items=[1])]
    \\    show(out, fill(mut boxes, 5))
    \\    d: dict[str, list[int]] = {"a": [1]}
    \\    show(out, grow(mut d, 1))
    \\    show(out, grow(mut d, 7))
    \\    out.print(len(boxes[0].items), len(d["a"]))
    \\    out.print(first_big([[1], [2, 8]], 5), first_big([[1]], 5))
    \\    out.print(inside(7), inside(2))
    \\    return 0
;

const conditional =
    \\def maybe(flag: int) -> int:
    \\    if flag > 1:
    \\        extra = [flag, flag]
    \\        if flag > 5:
    \\            return len(extra)
    \\    if flag == 3:
    \\        return 3
    \\    return 1
    \\
    \\def search(items: list[str], target: str) -> int:
    \\    found = -1
    \\    index = 0
    \\    while index < len(items):
    \\        current = items[index] + "!"
    \\        if current == target + "!":
    \\            found = index
    \\            break
    \\        index += 1
    \\    return found
    \\
    \\def label(flag: int) -> str:
    \\    text = "other"
    \\    if flag > 0:
    \\        text = "positive" + str(flag)
    \\    chosen: Option[int] = None
    \\    if flag == 1:
    \\        chosen = Some(flag)
    \\    match chosen:
    \\        case Some(one):
    \\            names = ["one", str(one)]
    \\            return text + names[0]
    \\        case None:
    \\            pass
    \\    return text
    \\
    \\def main(out: Stream) -> int:
    \\    out.print(maybe(0), maybe(3), maybe(4), maybe(9))
    \\    out.print(search(["a", "b", "c"], "b"), search(["a"], "z"))
    \\    out.print(label(1), label(2), label(0))
    \\    return 0
;

// spec: RC-TRAP-TEARDOWN-1
test "RC-TRAP-TEARDOWN-1 a trap deep in recursion holding open files matches the collector" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const observed = try matchesCollector(arena.allocator(), deep_files);
    try testing.expectEqual(std.process.Child.Term{ .exited = 1 }, observed.term);
    try testing.expectEqualStrings("start\nbottom 12\n", observed.stdout);
    try testing.expect(std.mem.indexOf(u8, observed.stderr, "error[R_LIST_BOUNDS]") != null);
    try testing.expect(std.mem.indexOf(u8, observed.stderr, "in dig at teardown.my:9:") != null);
    try testing.expect(std.mem.indexOf(u8, observed.files, "level12.txt=depth 12\n;") != null);
}

// spec-case: RC-TRAP-TEARDOWN-1
test "RC-TRAP-TEARDOWN-1 a trap closes inline resources held in stack slots once, like the collector" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const observed = try matchesCollector(arena.allocator(), inline_resources);
    try testing.expect(std.mem.indexOf(u8, observed.stderr, "error[R_LIST_BOUNDS]") != null);
    try testing.expectEqualStrings("f0=;f1=;f2=;f3=;f4=;f5=;f6=;f7=;f8=;", observed.files);
}

// spec-case: RC-TRAP-TEARDOWN-1
test "RC-TRAP-TEARDOWN-1 a trap inside an arena discards its regions and balances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const observed = try matchesCollector(arena.allocator(), arena_trap);
    try testing.expect(std.mem.indexOf(u8, observed.stderr, "error[R_DIVISION_BY_ZERO]") != null);
    try testing.expectEqualStrings("in arena 8\n", observed.stdout);
}

// spec-case: RC-TRAP-TEARDOWN-1
test "RC-TRAP-TEARDOWN-1 a trap with open receiver scopes and pins abandons them and balances" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const observed = try matchesCollector(arena.allocator(), pinned_trap);
    try testing.expect(std.mem.indexOf(u8, observed.stderr, "error[R_DIVISION_BY_ZERO]") != null);
    try testing.expectEqualStrings("2\n2\n", observed.stdout);
}

// spec: RC-EXIT-SCOPES-1
test "RC-EXIT-SCOPES-1 early returns from open receiver scopes, loops and arenas balance" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const observed = try matchesCollector(arena.allocator(), nested_returns);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, observed.term);
    try testing.expectEqualStrings("big3\n2\nbig7\n4 2\n8 -1\n7 0\n", observed.stdout);
}

// spec-case: RC-STATIC-DROPS-1
test "RC-STATIC-DROPS-1 conditionally initialized locals drop exactly once on every exit" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const observed = try matchesCollector(arena.allocator(), conditional);
    try testing.expectEqual(std.process.Child.Term{ .exited = 0 }, observed.term);
    try testing.expectEqualStrings("1 3 1 2\n1 -1\npositive1one positive2 other\n", observed.stdout);
}
