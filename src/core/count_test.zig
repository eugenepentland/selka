//! Counting builds (`--counters`, NEW-CORE-COUNTERS-1..7): the counts a program
//! records, the checks it executes, the counting runtime's insertions, and that a
//! build without the flag emits no counter.
const std = @import("std");
const stable_dir = @import("stable_dir.zig");
const options = @import("core_test_options");
const support = @import("test_support.zig");
const driver = @import("driver.zig");
const count_runtime = @import("count_runtime.zig");
const emit_count = @import("emit_count.zig");
const emit_llvm = @import("emit_llvm.zig");
const emit_units = @import("emit_units.zig");
const passes = @import("passes.zig");
const pipeline = @import("pipeline.zig");
const build = @import("build.zig");
const report = std.debug.print;
const functions_key = "functions";

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// What one run of a `test/core` fixture printed and the counters it wrote.
const Counted = struct { stdout: []const u8, stderr: []const u8, status: u8, counts: std.json.Value };

/// Build `test/core/<fixture>` (or an absolute source path) with `flags` and run it with `arguments`, its
/// counters written to `<root>/<label>.json`.
fn counted(a: std.mem.Allocator, root: []const u8, fixture: []const u8, flags: []const []const u8, arguments: []const []const u8) !Counted {
    try support.requireReleaseArgs(flags);
    const source = if (std.fs.path.isAbsolute(fixture)) fixture else try std.fmt.allocPrint(a, "{s}/{s}", .{ options.fixtures, fixture });
    const label = try std.fmt.allocPrint(a, "{s}{d}{d}", .{ std.fs.path.stem(std.fs.path.basename(fixture)), flags.len, arguments.len });
    const binary = try std.fs.path.join(a, &.{ root, label });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.corePath(), "build", source, "-o", binary, "--cache-dir", try options.suiteCache(a, @src()) });
    try argv.appendSlice(a, flags);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("counting build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("SELKA_COUNTERS", path);
    var run_argv: std.ArrayList([]const u8) = .empty;
    try run_argv.append(a, binary);
    try run_argv.appendSlice(a, arguments);
    const ran = try std.process.run(a, std.testing.io, .{ .argv = run_argv.items, .environ_map = &environment });
    const status: u8 = if (ran.term == .exited) ran.term.exited else 255;
    const text = std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(16 << 20)) catch "null";
    const counts = try std.json.parseFromSliceLeaky(std.json.Value, a, text, .{});
    return .{ .stdout = ran.stdout, .stderr = ran.stderr, .status = status, .counts = counts };
}

fn field(value: std.json.Value, path: []const []const u8) i64 {
    var at = value;
    for (path) |name| at = at.object.get(name) orelse return -1;
    return at.integer;
}

/// Retired runtime and site fields must be absent from the current schema.
fn retiredCountersAbsent(counts: std.json.Value) !void {
    for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |name|
        try std.testing.expect(counts.object.get("totals").?.object.get(name) == null);
    for ([_][]const u8{ "retain", "release", "release_unique", "unique_test" }) |name|
        try std.testing.expect(counts.object.get("kinds").?.object.get(name) == null);
    for (counts.object.get(functions_key).?.array.items) |row| {
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "share_marks" }) |name|
            try std.testing.expect(row.object.get(name) == null);
    }
}

/// Whether `qualified` names `function`: a project compilation prefixes the
/// fixture's module (`count_moves::main`), a single unit leaves the name bare.
fn named(qualified: []const u8, function: []const u8) bool {
    if (qualified.len < function.len) return false;
    if (!std.mem.eql(u8, qualified[qualified.len - function.len ..], function)) return false;
    if (qualified.len == function.len) return true;
    return std.mem.eql(u8, qualified[qualified.len - function.len - 2 .. qualified.len - function.len], "::");
}

/// The sum of `name` for sites matching one kind, operation and function.
fn sites(counts: std.json.Value, kind: []const u8, detail: []const u8, function: []const u8, name: []const u8) i64 {
    var total: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("detail").?.string, detail)) continue;
        if (!named(object.get("function").?.string, function)) continue;
        total += object.get(name).?.integer;
    }
    return total;
}

/// The sum of `count` over the sites of `kind` emitted in `function`, whatever their detail.
fn executed(counts: std.json.Value, kind: []const u8, function: []const u8) i64 {
    var total: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !named(object.get("function").?.string, function)) continue;
        total += object.get("count").?.integer;
    }
    return total;
}

fn firstLine(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn calls(counts: std.json.Value, function: []const u8) i64 {
    for (counts.object.get(functions_key).?.array.items) |row| {
        if (named(row.object.get("name").?.string, function)) return row.object.get("calls").?.integer;
    }
    return -1;
}

fn functionCount(counts: std.json.Value, function: []const u8, name: []const u8) i64 {
    for (counts.object.get(functions_key).?.array.items) |row| {
        if (named(row.object.get("name").?.string, function)) return row.object.get(name).?.integer;
    }
    return -1;
}

const borrowed_stack_source =
    \\func fold(values: int[]) -> int:
    \\    mut total = 0
    \\    for value in values:
    \\        total += value
    \\    return total
    \\
    \\func through_call(seed: int) -> int:
    \\    mut values = [seed, seed + 1, seed + 2]
    \\    return fold(values)
    \\
    \\func local_only(seed: int) -> int:
    \\    mut values = [seed, seed + 1, seed + 2]
    \\    mut total = 0
    \\    for value in values:
    \\        total += value
    \\    return total
    \\
    \\func returned(seed: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(3):
    \\        append(mut values, seed + i)
    \\    return values
    \\
    \\func returned_runtime(seed: int, count: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(count):
    \\        append(mut values, seed + i)
    \\    return values
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const seed = len(args) + 3
    \\    const a = through_call(seed)
    \\    const b = local_only(seed)
    \\    const kept = returned(seed)
    \\    const dynamic = returned_runtime(seed, seed)
    \\    print(out, a, b, kept[2], len(dynamic))
    \\    return 0
;

// spec-case: NEW-CORE-STACK-2
test "stack borrowing and caller constructors eliminate allocation while runtime-sized returned storage stays managed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "borrowed.selka", .data = borrowed_stack_source });
    const source = try std.fs.path.join(a, &.{ root, "borrowed.selka" });
    const plain = try counted(a, root, source, &.{}, &.{});
    try std.testing.expectEqualStrings("12 12 5 3\n", plain.stdout);
    try std.testing.expectEqual(@as(u8, 0), plain.status);
    const unoptimized = try counted(a, root, source, &.{ "--counters", "--unoptimized" }, &.{});
    try std.testing.expectEqualStrings(plain.stdout, unoptimized.stdout);
    try std.testing.expectEqual(@as(i64, 1), calls(unoptimized.counts, "fold"));
    try std.testing.expect(functionCount(unoptimized.counts, "through_call", "allocs") > 0);
    try std.testing.expect(functionCount(unoptimized.counts, "local_only", "allocs") > 0);
    try std.testing.expect(functionCount(unoptimized.counts, "returned", "allocs") > 0);
    const modes = [_][]const []const u8{ &.{"--counters"}, &.{ "--counters", "--release" }, &.{ "--counters", "--release", "--verify-facts" } };
    for (modes) |flags| {
        const result = try counted(a, root, source, flags, &.{});
        try std.testing.expectEqualStrings(plain.stdout, result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expectEqual(@as(u8, 0), result.status);
        for ([_][]const u8{ "through_call", "local_only" }) |function| {
            try std.testing.expectEqual(@as(i64, 1), calls(result.counts, function));
            try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, function, "allocs"));
            try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, function, "alloc_bytes"));
            try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, function, "list_copies"));
        }
        // Ownership's scalar-reader pass clones fold into through_call; counts
        // follow the physical caller, as they do for the constructor below.
        try std.testing.expectEqual(@as(i64, -1), calls(result.counts, "fold"));
        // The constructor is now physically in main; counter attribution follows
        // the caller, while the dynamic constructor still executes its own call.
        try std.testing.expectEqual(@as(i64, -1), calls(result.counts, "returned"));
        try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, "main", "allocs"));
        try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, "main", "alloc_bytes"));

        try std.testing.expect(functionCount(result.counts, "returned_runtime", "allocs") > 0);
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

const unique_tree_source =
    \\import lists
    \\
    \\func probe(n: int) -> int:
    \\    mut pages: int[][][] = []
    \\    for i in range(n):
    \\        mut rows: int[][] = []
    \\        append(mut rows, [i, i + 1])
    \\        append(mut rows, [])
    \\        append(mut pages, own rows)
    \\    const saved = copy(pages)
    \\    pages = [[[n]], [[n + 1]]]
    \\    mut popped = lists.pop(mut pages)
    \\    append(mut popped, [9])
    \\    lists.clear(mut popped)
    \\    if n % 2 == 0:
    \\        lists.clear(mut pages)
    \\    return len(pages) * 100 + len(saved[0][0]) * 10 + len(saved) + saved[0][0][1]
    \\func main(args: str[], out: Stream) -> int:
    \\    print(out, probe(len(args)))
    \\    return 0
;

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested cleanup has no runtime RC after replacement pop clear and branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "tree.selka", .data = unique_tree_source });
    const source = try std.fs.path.join(a, &.{ root, "tree.selka" });
    const modes = [_][]const []const u8{
        &.{
            "--counters",
            "--unoptimized",
        },
        &.{
            "--counters",
            "--release",
        },
        &.{
            "--counters",
            "--release",
            "--verify-facts",
        },
    };
    for (modes) |flags| {
        for ([_][]const []const u8{ &.{ "x", "x" }, &.{ "x", "x", "x" } }, [_][]const u8{ "23\n", "124\n" }) |arguments, answer| {
            const result = try counted(a, root, source, flags, arguments);
            try std.testing.expectEqual(@as(u8, 0), result.status);
            try std.testing.expectEqualStrings(answer, result.stdout);
            try std.testing.expectEqualStrings("", result.stderr);
            try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
            try retiredCountersAbsent(result.counts);
            try std.testing.expect(field(result.counts, &.{ "totals", "frees" }) > 0);
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-2
// spec: NEW-CORE-ZERO-RC-ABI-1
test "zero RC whole program includes startup arguments and nested text cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "owned.selka", .data =
        \\func main(args: str[], out: Stream) -> int:
        \\    mut texts: str[] = []
        \\    for arg in args:
        \\        append(mut texts, copy(arg))
        \\    mut text = ""
        \\    for i in range(20):
        \\        text += "aλ"
        \\    const saved = copy(text)
        \\    const part = strings.char_slice(saved, 0, 1)
        \\    print(out, len(texts), strings.char_count(saved), strings.char_at(part, 0))
        \\    return 0
    });
    const source = try std.fs.path.join(a, &.{ root, "owned.selka" });
    for ([_][]const []const u8{
        &.{
            "--counters",
            "--unoptimized",
        },
        &.{
            "--counters",
            "--release",
            "--verify-facts",
        },
    }) |flags| {
        const result = try counted(a, root, source, flags, &.{ "hello", "λ" });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("2 40 a\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
        try retiredCountersAbsent(result.counts);
        try std.testing.expect(field(result.counts, &.{ "totals", "allocs" }) > 0);
        try std.testing.expect(field(result.counts, &.{ "totals", "frees" }) > 0);
    }
}

// spec: NEW-CORE-COUNTERS-1
// A counted fill whose body cannot trap reserves its whole count (no growth); one whose body can
// trap keeps the 4096 prefix, so a trap past it follows growth and the division is the failure reported.
test "a trap-free counted fill reserves its count once, and a fill whose body can trap keeps its prefix" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const large = try counted(a, root, "k1b_fill_large.selka", &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqualStrings("200000\n", large.stdout);
    try std.testing.expectEqual(@as(u8, 0), large.status);
    try std.testing.expectEqual(@as(i64, 0), field(large.counts, &.{ "totals", "list_grows" }));
    try std.testing.expectEqual(@as(i64, 0), field(large.counts, &.{ "totals", "reallocs" }));
    const late = try counted(a, root, "k1b_fill_trap_late.selka", &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqual(@as(u8, 1), late.status);
    try std.testing.expect(contains(late.stderr, "R_DIVISION_BY_ZERO"));
    // A large block grows by realloc (counted as reallocs), a small one as list_grows.
    try std.testing.expect(field(late.counts, &.{ "totals", "list_grows" }) + field(late.counts, &.{ "totals", "reallocs" }) >= 1);
}

test "zero RC counting builds record explicit copies, growth, sites, cleanup and traps exactly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const plain = try counted(a, root, "counters.selka", &.{}, &.{});
    try std.testing.expectEqualStrings("100 101 4\n", plain.stdout);
    try std.testing.expectEqualStrings("", plain.stderr);
    try std.testing.expectEqual(@as(u8, 0), plain.status);
    // A fatal bounds error still writes all traffic accumulated before the trap.
    // Fatal termination does not unwind the live owners; do not call this leak-free.
    const trapped = try counted(a, root, "counters.selka", &.{
        "--counters",
    }, &.{"trap"});
    try std.testing.expectEqualStrings(plain.stdout, trapped.stdout);
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(contains(trapped.stderr, "R_LIST_BOUNDS"));
    try std.testing.expectEqual(@as(i64, 11), field(trapped.counts, &.{ "totals", "list_copies" }));
    try std.testing.expectEqual(@as(i64, 880), field(trapped.counts, &.{ "totals", "list_copy_bytes" }));
    const modes = [_][]const []const u8{
        &.{ "--counters", "--unoptimized" },
        &.{ "--counters", "--optimize-debug" },
        &.{ "--counters", "--release" },
        &.{ "--counters", "--release", "--verify-facts" },
        &.{ "--counters", "--release", "--no-facts" },
    };
    for (modes) |flags| {
        const result = try counted(a, root, "counters.selka", flags, &.{});
        try std.testing.expectEqualStrings(plain.stdout, result.stdout);
        try std.testing.expectEqualStrings(plain.stderr, result.stderr);
        try std.testing.expectEqual(plain.status, result.status);
        try copiedFixtureCounts(result.counts);
    }
}

fn copiedFixtureCounts(counts: std.json.Value) !void {
    const list_copy = "list_copy";
    const record_copy = "record_copy";
    const list_push = "list_push";
    try std.testing.expectEqualStrings("selka-counters-v1", counts.object.get("version").?.string);
    // One independent hundred-element list plus ten one-element record children.
    try std.testing.expectEqual(@as(i64, 11), field(counts, &.{ "kinds", list_copy, "count" }));
    try std.testing.expectEqual(@as(i64, 880), field(counts, &.{ "kinds", list_copy, "bytes" }));
    try std.testing.expectEqual(@as(i64, 11), field(counts, &.{ "totals", "list_copies" }));
    try std.testing.expectEqual(@as(i64, 880), field(counts, &.{ "totals", "list_copy_bytes" }));
    try std.testing.expectEqual(@as(i64, 10), calls(counts, "bump"));
    try std.testing.expectEqual(@as(i64, 0), sites(counts, record_copy, "list_get", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 0), sites(counts, record_copy, "record_set", "bumped", "bytes"));
    try std.testing.expectEqual(@as(i64, 80), sites(counts, list_copy, list_copy, "bumped", "bytes"));
    try std.testing.expectEqual(@as(i64, 400), sites(counts, record_copy, "list_set", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 0), sites(counts, record_copy, "list_set.old", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 121), sites(counts, list_push, list_push, "main", "count"));
    try std.testing.expectEqual(@as(i64, 7), field(counts, &.{ "totals", "list_grows" }));
    try std.testing.expectEqual(@as(i64, 1280), field(counts, &.{ "totals", "list_grow_bytes" }));
    try std.testing.expectEqual(field(counts, &.{ "totals", "list_grow_bytes" }) + field(counts, &.{ "totals", "realloc_moved_bytes" }), field(counts, &.{ "kinds", list_push, "extra" }));
    try retiredCountersAbsent(counts);
    // Static xs/ps empties avoid two 32-byte headers; first growth still allocates.
    try std.testing.expectEqual(@as(i64, 29), field(counts, &.{ "totals", "allocs" }));
    try std.testing.expectEqual(@as(i64, 29), field(counts, &.{ "totals", "frees" }));
    try std.testing.expectEqual(@as(i64, 5352), field(counts, &.{ "totals", "alloc_bytes" }));
    try std.testing.expectEqual(@as(i64, 0), field(counts, &.{ "totals", "live_bytes_at_exit" }));
    try std.testing.expectEqual(@as(i64, 3560), field(counts, &.{ "totals", "peak_live_bytes" }));
}

// spec-case: NEW-CORE-COUNTERS-1
test "zero RC counters include recursive boxed list copies without counting box shells twice" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const source =
        \\# Exact copy traffic: one 3-element scalar list and one 2-element list below
        \\# recursive boxes. Box payload copying is not a list-copy event.
        \\import lists
        \\
        \\enum Tree:
        \\    leaf(items: int[])
        \\    node(child: Tree)
        \\
        \\func score(tree: Tree) -> int:
        \\    match tree:
        \\        case leaf(items=items):
        \\            return len(items) + items[0]
        \\        case node(child=child):
        \\            return 1 + score(child)
        \\
        \\func main(args: str[], out: Stream) -> int:
        \\    const seed = len(args) + 3
        \\    mut values = [seed, seed + 1, seed + 2]
        \\    const flat = copy(values)
        \\    assert values[0] == flat[0]
        \\    lists.clear(mut values)
        \\    mut tree = Tree.leaf(items=[seed, seed + 1])
        \\    for i in range(3):
        \\        tree = Tree.node(child=own tree)
        \\    const saved = copy(tree)
        \\    assert score(tree) == score(saved)
        \\    tree = Tree.leaf(items=[])
        \\    print(out, score(saved), flat[0], len(flat))
        \\    return 0
    ;
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "recursive_copy_counts.selka", .data = source });
    const path = try std.fs.path.join(a, &.{ root, "recursive_copy_counts.selka" });
    const modes = [_][]const []const u8{
        &.{ "--counters", "--unoptimized" },
        &.{ "--counters", "--release" },
    };
    for (modes) |flags| {
        const result = try counted(a, root, path, flags, &.{});
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("8 3 3\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        // The ordinary list-copy helper accounts for 24 bytes exactly once;
        // the generated callback copies another 16 bytes below three recursive boxes.
        try std.testing.expectEqual(@as(i64, 2), field(result.counts, &.{ "totals", "list_copies" }));
        try std.testing.expectEqual(@as(i64, 40), field(result.counts, &.{ "totals", "list_copy_bytes" }));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "dict_copies" }));
        try std.testing.expectEqual(field(result.counts, &.{ "totals", "allocs" }), field(result.counts, &.{ "totals", "frees" }));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

// spec: NEW-CORE-COUNTERS-2
test "the counting runtime inserts every hook once into the unchanged runtime source and refuses a runtime that moved" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const counting = try count_runtime.source(a, driver.runtime_source);
    try std.testing.expect(std.mem.startsWith(u8, counting, driver.runtime_source[0..64]));
    try std.testing.expect(std.mem.endsWith(u8, counting, count_runtime.body));
    try std.testing.expect(!contains(driver.runtime_source, "myl_count_"));
    try std.testing.expectEqual(driver.runtime_source.len + count_runtime.inserted + 1 + count_runtime.body.len, counting.len);
    try std.testing.expect(contains(counting, "    myl_count_dump();\n    leak_report();\n"));
    try std.testing.expectError(error.AnchorMissing, count_runtime.source(a, "int main(void) { return 0; }\n"));
    const doubled = try std.mem.concat(a, u8, &.{ driver.runtime_source, driver.runtime_source });
    try std.testing.expectError(error.AnchorMissing, count_runtime.source(a, doubled));
    // The runtime's site kind names are `emit_count.Kind`'s, in order.
    var expected: std.ArrayList(u8) = .empty;
    inline for (@typeInfo(emit_count.Kind).@"enum".field_names, 0..) |kind, i| try expected.print(a, "{s}\"{s}\"", .{ if (i == 0) "" else ", ", kind });
    const listed = std.mem.collapseRepeats(u8, try std.mem.replaceOwned(u8, a, kindList(count_runtime.body), "\n    ", " "), ' ');
    try std.testing.expectEqualStrings(expected.items, std.mem.trim(u8, listed, " ,"));
    // The block, element-move, sort-comparison and sorted-element kinds are appended
    // last in both, so every earlier site kind keeps its recorded offset.
    const kinds = @typeInfo(emit_count.Kind).@"enum".field_names;
    try std.testing.expectEqualStrings("blocks", kinds[kinds.len - 4]);
    try std.testing.expectEqualStrings("element_moves", kinds[kinds.len - 3]);
    try std.testing.expectEqualStrings("sort_compares", kinds[kinds.len - 2]);
    try std.testing.expectEqualStrings("elements_sorted", kinds[kinds.len - 1]);
    const table = std.mem.trim(u8, kindList(count_runtime.body), " \n");
    try std.testing.expect(std.mem.endsWith(u8, table, "\"blocks\", \"element_moves\", \"sort_compares\", \"elements_sorted\","));
    try std.testing.expectEqual(@as(usize, 40), emit_count.function_slots);
    try std.testing.expectEqual(@as(u32, 8 + 32 * 8), emit_count.function_blocks);
    try std.testing.expectEqual(@as(u32, 8 + 37 * 8), emit_count.function_elements_sorted);
    // The runtime's function slot table names the sorted-element total at slot 37.
    try std.testing.expect(std.mem.indexOf(u8, count_runtime.body, "\"sort_compares\", \"elements_sorted\", NULL, NULL,") != null);
}

/// The initializer of `myl_count_kinds` in core_count.c.
fn kindList(body: []const u8) []const u8 {
    const start = std.mem.indexOf(u8, body, "myl_count_kinds[] = {").? + "myl_count_kinds[] = {".len;
    const end = std.mem.indexOfPos(u8, body, start, "};").?;
    return std.mem.trim(u8, body[start..end], " \n");
}

// spec: NEW-CORE-COUNTERS-3
test "without --counters the emitted text names no counter and links the ordinary runtime; with it every function is counted" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const program =
        \\func twice(xs: int[]) -> int[]:
        \\    mut ys = copy(xs)
        \\    append(mut ys, 1)
        \\    return ys
        \\func main(out: Stream) -> int:
        \\    print(out, len(twice([1, 2])))
        \\    return 0
    ;
    const plain = try support.llvmText(a, program);
    try std.testing.expect(!contains(plain, "myl_count"));
    try std.testing.expect(!contains(plain, "myl.cs."));
    try std.testing.expect(!emit_units.unit("whole", "", .program, plain).dependencies.counting);
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, program, &refusal);
    const result = try passes.debug(a, &module);
    const context: u8 = 0;
    const counting = try emit_llvm.emitModule(a, &module, .{
        .locator = .{ .context = &context, .locate = firstLine },
        .source_path = "counters.selka",
        .main = .{ .parameters = &.{"out"} },
        .analysis = support.analysis(&result),
        .counters = true,
    });
    try std.testing.expect(emit_units.unit("whole", "", .program, counting).dependencies.counting);
    try std.testing.expect(contains(counting, "section \"myl_count_fns\""));
    try std.testing.expect(contains(counting, "section \"myl_count_sites\""));
    try std.testing.expect(contains(counting, "@llvm.used = appending global"));
    try std.testing.expect(contains(counting, ", ptr @myl_count_copy_site, align 8\n"));
    try std.testing.expect(contains(counting, emit_count.epilogue));
    try std.testing.expect(contains(counting, "call ptr @myl_core_list_new_slow(i64 %cap, i64 %size)\n  ret ptr %made"));
    try std.testing.expectEqual(std.mem.count(u8, counting, "%myl.cnt.saved = load ptr"), std.mem.count(u8, counting, "section \"myl_count_fns\""));
}

// spec: NEW-CORE-COUNTERS-4
test "--counters is a build and run flag given once, and part of the build's replay key" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cli_args = @import("cli_args.zig");
    var failure: cli_args.Failure = .usage;
    const built = try cli_args.parse(a, .build, &.{ "p.selka", "-o", "p", "--counters" }, "zig", &failure);
    try std.testing.expect(built.build.show.codegen.counters);
    const ran = try cli_args.parse(a, .run, &.{ "p.selka", "--counters", "--release" }, "zig", &failure);
    try std.testing.expect(ran.build.show.codegen.counters and ran.build.mode == .release);
    try std.testing.expectError(error.Usage, cli_args.parse(a, .build, &.{ "p.selka", "-o", "p", "--counters", "--counters" }, "zig", &failure));
    const plain = try cli_args.parse(a, .build, &.{ "p.selka", "-o", "p" }, "zig", &failure);
    try std.testing.expect(!plain.build.show.codegen.counters);
    const default: pipeline.Codegen = .{};
    try std.testing.expect(!default.counters);
}

// spec: NEW-CORE-COUNTERS-5
test "cost --counters adds one counting run's executions per function after the unchanged static report" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cost = @import("cost.zig");
    const dynamic = @import("cost_dynamic.zig");
    const command = @import("cost_command.zig");
    var functions = [_]cost.Function{ .{ .name = "main", .counts = .{} }, .{ .name = "bump", .counts = .{} }, .{ .name = "idle", .counts = .{} } };
    const static: cost.Report = .{ .functions = &functions, .totals = .{} };
    const document =
        \\{"version":"selka-counters-v1","totals":{},"kinds":{},
        \\"functions":[{"name":"main","calls":1,"allocs":3,"alloc_bytes":96,"list_copies":1,"list_copy_bytes":800,"list_grow_bytes":64},
        \\  {"name":"bump","calls":10},{"name":"<outside>","calls":0,"allocs":1}],
        \\"sites":[{"function":"bump","kind":"record_copy","count":20,"bytes":800,"extra":0},
        \\  {"function":"main","kind":"list_copy","count":1,"bytes":800,"extra":0}]}
    ;
    const section = try dynamic.rows(a, static, document);
    try std.testing.expectEqual(@as(usize, 3), section.len);
    try std.testing.expectEqual(@as(u64, 1), section[0].run.copies);
    try std.testing.expectEqual(@as(u64, 800), section[0].run.copied_bytes);
    try std.testing.expectEqual(@as(u64, 64), section[0].run.growth_bytes);
    try std.testing.expectEqual(@as(u64, 10), section[1].run.calls);
    try std.testing.expectEqual(@as(u64, 20), section[1].run.copies);
    try std.testing.expectEqual(@as(u64, 0), section[2].run.calls);
    var text: std.ArrayList(u8) = .empty;
    try dynamic.render(a, &text, section);
    try std.testing.expect(contains(text.items, "bump: calls 10; copies 20 (800 bytes)"));
    try std.testing.expect(contains(text.items, "TOTAL: calls 11;"));
    try std.testing.expectError(error.InvalidCounters, dynamic.rows(a, static, "{\"version\":\"cost-v1\"}"));
    try std.testing.expectError(error.InvalidCounters, dynamic.rows(a, static, "not json"));
    try std.testing.expectEqualStrings("c.json", command.parse(&.{ "p.selka", "--counters", "c.json" }).?.counters.?);
    try std.testing.expectEqual(@as(?command.Request, null), command.parse(&.{ "p.selka", "--counters", "a.json", "--counters", "b.json" }));
    try std.testing.expectEqual(@as(?command.Request, null), command.parse(&.{ "p.selka", "--counters" }));
}

// spec: NEW-CORE-COUNTERS-6
test "a counting build counts each bounds, overflow, division and shift check it executes, at its site" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const plain = try counted(a, root, "counters_checks.selka", &.{}, &.{});
    const debug = try counted(a, root, "counters_checks.selka", &.{ "--counters", "--unoptimized" }, &.{});
    try std.testing.expectEqualStrings("25\n", plain.stdout);
    try std.testing.expectEqualStrings(plain.stdout, debug.stdout);
    try std.testing.expectEqual(plain.status, debug.status);
    // Four calls of each helper; `grow` runs three times per iteration.
    try std.testing.expectEqual(@as(i64, 4), executed(debug.counts, "bounds_check", "pick"));
    try std.testing.expectEqual(@as(i64, 4), sites(debug.counts, "bounds_check", "list_get", "pick", "count"));
    try std.testing.expectEqual(@as(i64, 12), executed(debug.counts, "overflow_check", "grow"));
    try std.testing.expectEqual(@as(i64, 4), executed(debug.counts, "division_check", "share"));
    try std.testing.expectEqual(@as(i64, 4), executed(debug.counts, "shift_check", "lift"));
    try std.testing.expectEqual(@as(i64, 0), executed(debug.counts, "bounds_check", "grow"));
    try std.testing.expect(field(debug.counts, &.{ "kinds", "bounds_check", "count" }) >= 4);
    try std.testing.expect(field(debug.counts, &.{ "kinds", "other_check", "count" }) >= 0);
    // A build without the flag counts nothing: its text names no check site.
    const text = try support.llvmText(a, "func f(a: int, b: int) -> int:\n    return a // b\nfunc main() -> int:\n    return f(7, 2)\n");
    try std.testing.expect(!contains(text, "myl.cs."));
    // A release build prints the same and still counts the checks its passes kept.
    const release = try counted(a, root, "counters_checks.selka", &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqualStrings(plain.stdout, release.stdout);
    try std.testing.expect(field(release.counts, &.{ "kinds", "shift_check", "count" }) >= 4);
}

// spec: NEW-CORE-COUNTERS-7
test "cost --counters adds the checks each function executed, by kind, to its row and the total" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const cost = @import("cost.zig");
    const dynamic = @import("cost_dynamic.zig");
    var functions = [_]cost.Function{ .{ .name = "main", .counts = .{} }, .{ .name = "pick", .counts = .{} } };
    const static: cost.Report = .{ .functions = &functions, .totals = .{} };
    const document =
        \\{"version":"selka-counters-v1","totals":{},"kinds":{},
        \\"functions":[{"name":"main","calls":1},{"name":"pick","calls":4}],
        \\"sites":[{"function":"pick","kind":"bounds_check","count":4,"bytes":0,"extra":0},
        \\  {"function":"pick","kind":"bounds_check","count":2,"bytes":0,"extra":0},
        \\  {"function":"main","kind":"overflow_check","count":12,"bytes":0,"extra":0},
        \\  {"function":"main","kind":"division_check","count":4,"bytes":0,"extra":0},
        \\  {"function":"main","kind":"shift_check","count":3,"bytes":0,"extra":0},
        \\  {"function":"main","kind":"other_check","count":1,"bytes":0,"extra":0}]}
    ;
    const section = try dynamic.rows(a, static, document);
    try std.testing.expectEqual(@as(u64, 6), section[1].checks.bounds);
    try std.testing.expectEqual(@as(u64, 12), section[0].checks.overflow);
    try std.testing.expectEqual(@as(u64, 4), section[0].checks.division);
    try std.testing.expectEqual(@as(u64, 3), section[0].checks.shift);
    try std.testing.expectEqual(@as(u64, 1), section[0].checks.other);
    try std.testing.expectEqual(@as(u64, 0), section[0].checks.bounds);
    var text: std.ArrayList(u8) = .empty;
    try dynamic.render(a, &text, section);
    try std.testing.expect(contains(text.items, "pick: calls 4;"));
    try std.testing.expect(contains(text.items, "; checks: bounds 6, overflow 0, division 0, shift 0, other 0\n"));
    try std.testing.expect(contains(text.items, "TOTAL: calls 5;"));
    try std.testing.expect(contains(text.items, "checks: bounds 6, overflow 12, division 4, shift 3, other 1\n"));
    const json = try std.json.Stringify.valueAlloc(a, section[1], .{});
    try std.testing.expect(contains(json, "\"checks\":{\"bounds\":6,\"overflow\":0,\"division\":0,\"shift\":0,\"other\":0}"));
}

// spec-case: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer counts boxed cleanup without retaining its children" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const result = try counted(a, root, "zero_rc_payload_box.selka", &.{ "--release", "--counters" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), result.status);
    try std.testing.expectEqualStrings("none\n15\n15\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
    try retiredCountersAbsent(result.counts);
    try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    try std.testing.expect(field(result.counts, &.{ "totals", "frees" }) > 0);
}

// spec-case: NEW-CORE-ZERO-RC-MATCH-TRANSFER-1
test "zero RC fresh match transfers boxed payloads across allocation and return" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{
        &.{ "--unoptimized", "--counters" },
        &.{ "--release", "--verify-facts", "--counters" },
    }) |flags| {
        const result = try counted(a, root, "zero_rc_match_box.selka", flags, &.{});
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("62\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try retiredCountersAbsent(result.counts);
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

/// An f-string printed in a loop: every hole family whose rendering allocates
/// nothing, with and without a specification.
const format_printed_source =
    \\func render(out: Stream, n: int) -> int:
    \\    for i in range(n):
    \\        print(out, f"row {i}: value={i * 3} {i:04d} {True} {'ab'} {b'in'}")
    \\    return 0
    \\
    \\func main(out: Stream) -> int:
    \\    return render(out, 3)
;

/// The same pieces stored in a `str` instead of printed: the one allocation a
/// format string's own text needs.
const format_bound_source =
    \\func line(n: int) -> str:
    \\    return f"row {n}: value={n * 3} {n:04d} {True} {'ab'} {b'in'}"
    \\
    \\func main(out: Stream) -> int:
    \\    const text = line(3)
    \\    print(out, text)
    \\    return 0
;

/// An f-string whose holes are an aggregate: their own renderings are allowed to
/// allocate, and only the joined text stops being one.
const format_aggregate_source =
    \\record Point:
    \\    x: int
    \\    y: int
    \\
    \\func main(out: Stream) -> int:
    \\    mut point = Point(x=2, y=3)
    \\    mut values = [2, 3]
    \\    const text = f"point {point} values {values}"
    \\    print(out, text, point, values)
    \\    return 0
;

/// A program with no work: the control for a counting run's startup allocations.
const format_control_source =
    \\func main() -> int:
    \\    return 0
;

// spec-case: PY-FSTRING-1
test "printing an f-string allocates nothing and binding one allocates once" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "format_printed.selka", .data = format_printed_source });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "format_bound.selka", .data = format_bound_source });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "format_aggregate.selka", .data = format_aggregate_source });
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "format_control.selka", .data = format_control_source });
    const control = try counted(a, root, try std.fs.path.join(a, &.{ root, "format_control.selka" }), &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), control.status);
    try std.testing.expectEqualStrings("", control.stdout);
    try std.testing.expectEqual(@as(i64, 0), field(control.counts, &.{ "totals", "allocs" }));

    // Printing writes each piece to the stream, so a scalar, text or byte hole
    // makes no block at all, and the control above shows no startup noise.
    const printed_lines = "row 0: value=0 0000 True ab b'in'\nrow 1: value=3 0001 True ab b'in'\nrow 2: value=6 0002 True ab b'in'\n";
    const printed = try counted(a, root, try std.fs.path.join(a, &.{ root, "format_printed.selka" }), &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), printed.status);
    try std.testing.expectEqualStrings(printed_lines, printed.stdout);
    try std.testing.expectEqualStrings("", printed.stderr);
    try std.testing.expectEqual(@as(i64, 0), field(printed.counts, &.{ "totals", "allocs" }));
    try std.testing.expectEqual(@as(i64, 0), functionCount(printed.counts, "render", "allocs"));
    try std.testing.expectEqual(@as(i64, 0), field(printed.counts, &.{ "totals", "live_bytes_at_exit" }));

    // Storing the same pieces reserves one buffer and fills it in place: exactly
    // one allocation more than printing them, and no text copy per hole.
    const bound = try counted(a, root, try std.fs.path.join(a, &.{ root, "format_bound.selka" }), &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), bound.status);
    try std.testing.expectEqualStrings("row 3: value=9 0003 True ab b'in'\n", bound.stdout);
    try std.testing.expectEqualStrings("", bound.stderr);
    try std.testing.expectEqual(@as(i64, 1), field(bound.counts, &.{ "totals", "allocs" }));
    try std.testing.expectEqual(@as(i64, 0), field(bound.counts, &.{ "totals", "text_copies" }));
    try std.testing.expectEqual(@as(i64, 0), field(bound.counts, &.{ "totals", "live_bytes_at_exit" }));

    // A hole whose own rendering allocates (a record, a list) keeps that
    // allocation, so this program is never claimed to be free of them.
    const aggregate = try counted(a, root, try std.fs.path.join(a, &.{ root, "format_aggregate.selka" }), &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), aggregate.status);
    try std.testing.expectEqualStrings("point Point(x=2, y=3) values [2, 3] Point(x=2, y=3) [2, 3]\n", aggregate.stdout);
    try std.testing.expectEqualStrings("", aggregate.stderr);
    try std.testing.expect(field(aggregate.counts, &.{ "totals", "allocs" }) > 1);
    try std.testing.expectEqual(@as(i64, 0), field(aggregate.counts, &.{ "totals", "live_bytes_at_exit" }));
}

/// A counted loop: a call, a while header, a body and a return, so the executed
/// basic blocks of each emitted function are a fixed number.
const blocks_source =
    \\func sum_upto(n: int) -> int:
    \\    mut total = 0
    \\    mut i = 0
    \\    while i < n:
    \\        total += i
    \\        i += 1
    \\    return total
    \\
    \\func main(out: Stream) -> int:
    \\    print(out, sum_upto(3))
    \\    return 0
;

/// Native list mutations: one insert, one pop(index) and one remove, each at a
/// known position of a known list, so the shifted elements are exact.
const moves_source =
    \\import lists
    \\
    \\func main(out: Stream) -> int:
    \\    mut xs = [1, 2, 3, 4]
    \\    lists.insert(mut xs, 0, 9)
    \\    const popped = lists.pop_at(mut xs, 0)
    \\    lists.remove(mut xs, 2)
    \\    print(out, xs, popped)
    \\    return 0
;

/// One plain and one keyed stable sort over fixed inputs.
const sorts_source =
    \\record Row:
    \\    rank: int
    \\    name: str
    \\
    \\func by_name(row: Row) -> str:
    \\    return copy(row.name)
    \\
    \\func main(out: Stream) -> int:
    \\    mut values = [3, 1, 2]
    \\    sort(mut values)
    \\    mut rows = [Row(rank=2, name="b"), Row(rank=1, name="a")]
    \\    sort(mut rows, key=by_name)
    \\    print(out, values, rows)
    \\    return 0
;

/// One written fixture: its file name, its source and the counting flags to build it with.
const Fixture = struct { name: []const u8, source: []const u8, flags: []const []const u8 };

/// Write `fixture` in `directory` and build and run it, its counters written beside it.
fn countedFixture(a: std.mem.Allocator, directory: anytype, root: []const u8, fixture: Fixture) !Counted {
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = fixture.name, .data = fixture.source });
    return counted(a, root, try std.fs.path.join(a, &.{ root, fixture.name }), fixture.flags, &.{});
}

test "a counting build counts every executed basic block of each emitted function exactly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{
        &.{ "--counters", "--unoptimized" },
        &.{ "--counters", "--release" },
    }) |flags| {
        const result = try countedFixture(a, directory, root, .{ .name = "count-blocks.selka", .source = blocks_source, .flags = flags });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("3\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        // Five emitted blocks: the entry once, the while header four times
        // (i = 0..3), the body and the latch three times each and the exit once.
        // At n = 3 that is 12 entries in `sum_upto`, plus the one block `main`
        // enters once.
        try std.testing.expectEqual(@as(i64, 1), functionCount(result.counts, "main", "blocks"));
        try std.testing.expectEqual(@as(i64, 12), functionCount(result.counts, "sum_upto", "blocks"));
        try std.testing.expectEqual(@as(i64, 13), field(result.counts, &.{ "totals", "blocks" }));
        try std.testing.expectEqual(@as(i64, 13), field(result.counts, &.{ "kinds", "blocks", "count" }));
        try std.testing.expectEqual(@as(i64, 1), executed(result.counts, "blocks", "main"));
        try std.testing.expectEqual(@as(i64, 12), executed(result.counts, "blocks", "sum_upto"));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

test "a counting build counts the elements a native insert, remove and pop shift, at the operation" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{
        &.{ "--counters", "--unoptimized" },
        &.{ "--counters", "--release" },
    }) |flags| {
        const result = try countedFixture(a, directory, root, .{ .name = "count_moves.selka", .source = moves_source, .flags = flags });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("[1, 3, 4] 9\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        // insert(0, 9) pushes the ninth onto a four-element list and shifts all
        // five, pop(0) shifts the five it holds, and remove(2) finds index 1 of the
        // four left and shifts three: 13 elements of eight bytes each. The list is
        // never copied as a whole.
        try std.testing.expectEqual(@as(i64, 13), functionCount(result.counts, "main", "element_moves"));
        try std.testing.expectEqual(@as(i64, 104), functionCount(result.counts, "main", "element_move_bytes"));
        try std.testing.expectEqual(@as(i64, 13), field(result.counts, &.{ "totals", "element_moves" }));
        try std.testing.expectEqual(@as(i64, 104), field(result.counts, &.{ "totals", "element_move_bytes" }));
        try std.testing.expectEqual(@as(i64, 13), field(result.counts, &.{ "kinds", "element_moves", "count" }));
        try std.testing.expectEqual(@as(i64, 104), field(result.counts, &.{ "kinds", "element_moves", "bytes" }));
        try std.testing.expectEqual(@as(i64, 13), sites(result.counts, "element_moves", "list_rotate", "main", "count"));
        try std.testing.expectEqual(@as(i64, 104), sites(result.counts, "element_moves", "list_rotate", "main", "bytes"));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "list_copies" }));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

test "a counting build counts each comparison of the plain and keyed stable sorts, at the sort" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{
        &.{ "--counters", "--unoptimized" },
        &.{ "--counters", "--release" },
    }) |flags| {
        const result = try countedFixture(a, directory, root, .{ .name = "count-sorts.selka", .source = sorts_source, .flags = flags });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("[1, 2, 3] [Row(rank=1, name='a'), Row(rank=2, name='b')]\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        // Sorting [3, 1, 2] by insertion order takes three comparisons; the keyed
        // sort of two rows compares their text keys once.
        try std.testing.expectEqual(@as(i64, 3), sites(result.counts, "sort_compares", "list_sort", "main", "count"));
        try std.testing.expectEqual(@as(i64, 1), sites(result.counts, "sort_compares", "sort_keyed", "main", "count"));
        try std.testing.expectEqual(@as(i64, 4), functionCount(result.counts, "main", "sort_compares"));
        try std.testing.expectEqual(@as(i64, 4), field(result.counts, &.{ "totals", "sort_compares" }));
        try std.testing.expectEqual(@as(i64, 4), field(result.counts, &.{ "kinds", "sort_compares", "count" }));
        // Every sort also counts the elements it starts with: three and two here.
        try std.testing.expectEqual(@as(i64, 3), sites(result.counts, "elements_sorted", "list_sort", "main", "count"));
        try std.testing.expectEqual(@as(i64, 2), sites(result.counts, "elements_sorted", "sort_keyed", "main", "count"));
        try std.testing.expectEqual(@as(i64, 5), functionCount(result.counts, "main", "elements_sorted"));
        try std.testing.expectEqual(@as(i64, 5), field(result.counts, &.{ "totals", "elements_sorted" }));
        try std.testing.expectEqual(@as(i64, 5), field(result.counts, &.{ "kinds", "elements_sorted", "count" }));
        // The key function returns `copy(row.name)`, so each of the two key
        // evaluations is one text copy of a borrowed key.
        try std.testing.expectEqual(@as(i64, 2), functionCount(result.counts, "by_name", "text_copies"));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

/// A 300-element integer list in no order, sorted twice: above 256 elements the
/// runtime sorts integers by radix distribution, which compares no elements, so
/// `sort_compares` stays 0 while the sorts still process 600 elements.
const radix_sort_source =
    \\func main(out: Stream) -> int:
    \\    mut values: int[] = []
    \\    mut i = 0
    \\    while i < 300:
    \\        append(mut values, (i * 37) % 300)
    \\        i += 1
    \\    sort(mut values)
    \\    sort(mut values)
    \\    print(out, len(values), values[0], values[299])
    \\    return 0
;

test "a counting build counts the elements a sort processes even when it compares none" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    for ([_][]const []const u8{
        &.{ "--counters", "--unoptimized" },
        &.{ "--counters", "--release" },
    }) |flags| {
        const result = try countedFixture(a, directory, root, .{ .name = "count-radix-sort.selka", .source = radix_sort_source, .flags = flags });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("300 0 299\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        // Two sorts of 300 elements each: exactly 600 elements sorted, and no
        // comparison at all on the radix path.
        try std.testing.expectEqual(@as(i64, 600), sites(result.counts, "elements_sorted", "list_sort", "main", "count"));
        try std.testing.expectEqual(@as(i64, 600), functionCount(result.counts, "main", "elements_sorted"));
        try std.testing.expectEqual(@as(i64, 600), field(result.counts, &.{ "totals", "elements_sorted" }));
        try std.testing.expectEqual(@as(i64, 600), field(result.counts, &.{ "kinds", "elements_sorted", "count" }));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "sort_compares" }));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "kinds", "sort_compares", "count" }));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
}

// The list helpers move elements (Part 4 of the eda roadmap): `lists.pop_at` takes the element out and moves
// the tail down with exchanges, so it makes no copy; `lists.exchange` hands back the former element and takes
// its replacement `own` (C2b, 25 October), so it makes none either. It copied a borrowed replacement before.
// A record holding a list makes any list copy visible.
test "lists pop_at and exchange move their elements and their replacement, and copy nothing" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = stable_dir.tmpDir(std.testing.allocator, @src());
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "list_moves.selka", .data = list_moves_source });
    const source = try std.fs.path.join(a, &.{ root, "list_moves.selka" });
    const modes = [_][]const []const u8{ &.{"--counters"}, &.{ "--counters", "--release" } };
    for (modes) |flags| {
        const result = try counted(a, root, source, flags, &.{});
        try std.testing.expectEqualStrings("", result.stdout);
        try std.testing.expectEqual(@as(u8, 117), result.status);
        try std.testing.expectEqual(@as(i64, 0), instantiatedSites(result.counts, "list_copy", "list_copy", "lists::pop_at"));
        try std.testing.expectEqual(@as(i64, 0), instantiatedSites(result.counts, "record_copy", "list_get", "lists::pop_at"));
        try std.testing.expectEqual(@as(i64, 0), instantiatedSites(result.counts, "list_copy", "list_copy", "lists::exchange"));
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "list_copies" }));
    }
}

/// The count of one kind's sites inside a generic stdlib function, whose qualified name carries its
/// type arguments (`lists::exchange[main::Item]`), so the match is on the name's prefix.
fn instantiatedSites(counts: std.json.Value, kind: []const u8, detail: []const u8, qualified: []const u8) i64 {
    var total: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("detail").?.string, detail)) continue;
        const name = object.get("function").?.string;
        if (!std.mem.startsWith(u8, name, qualified)) continue;
        total += object.get("count").?.integer;
    }
    return total;
}

/// Two `pop_at` calls and one `exchange` on a list of records that each hold a list.
const list_moves_source =
    \\import lists
    \\
    \\
    \\record Item:
    \\    name: int
    \\    holds: int[]
    \\
    \\
    \\func main() -> int:
    \\    mut xs = [Item(name=1, holds=[10]), Item(name=2, holds=[20]), Item(name=3, holds=[30]), Item(name=4, holds=[40])]
    \\    const middle = lists.pop_at(mut xs, 1)
    \\    const former = lists.exchange(mut xs, 0, Item(name=9, holds=[9]))
    \\    const last = lists.pop_at(mut xs, len(xs) - 1)
    \\    return middle.name * 10 + former.name + last.name * 100 + len(xs) * 1000
    \\
;
