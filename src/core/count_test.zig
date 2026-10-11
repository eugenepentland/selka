//! Counting builds (`--counters`, NEW-CORE-COUNTERS-1..7): the counts a program
//! records, the checks it executes, the counting runtime's insertions, and that a
//! build without the flag emits no counter.
const std = @import("std");
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

fn contains(text: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, text, needle) != null;
}

/// What one run of a `test/core` fixture printed and the counters it wrote.
const Counted = struct { stdout: []const u8, stderr: []const u8, status: u8, counts: std.json.Value };

/// Build `test/core/<fixture>` (or an absolute source path) with `flags` and run it with `arguments`, its
/// counters written to `<root>/<label>.json`.
fn counted(a: std.mem.Allocator, root: []const u8, fixture: []const u8, flags: []const []const u8, arguments: []const []const u8) !Counted {
    const source = if (std.fs.path.isAbsolute(fixture)) fixture else try std.fmt.allocPrint(a, "{s}/{s}", .{ options.fixtures, fixture });
    const label = try std.fmt.allocPrint(a, "{s}{d}{d}", .{ std.fs.path.stem(std.fs.path.basename(fixture)), flags.len, arguments.len });
    const binary = try std.fs.path.join(a, &.{ root, label });
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ options.core_path, "build", source, "-o", binary, "--cache-dir", root });
    try argv.appendSlice(a, flags);
    const built = try std.process.run(a, std.testing.io, .{ .argv = argv.items });
    if (built.term != .exited or built.term.exited != 0) report("counting build: {s}{s}\n", .{ built.stdout, built.stderr });
    try std.testing.expect(built.term == .exited and built.term.exited == 0);
    const path = try std.fmt.allocPrint(a, "{s}.json", .{binary});
    var environment = std.process.Environ.Map.init(a);
    try environment.put("MYLANG_COUNTERS", path);
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

/// The sum of `name` over the sites of `kind` whose detail is `detail` and whose
/// emitting function is `function`.
fn sites(counts: std.json.Value, kind: []const u8, detail: []const u8, function: []const u8, name: []const u8) i64 {
    var total: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("detail").?.string, detail)) continue;
        if (!std.mem.eql(u8, object.get("function").?.string, function)) continue;
        total += object.get(name).?.integer;
    }
    return total;
}

/// The sum of `count` over the sites of `kind` emitted in `function`, whatever their detail.
fn executed(counts: std.json.Value, kind: []const u8, function: []const u8) i64 {
    var total: i64 = 0;
    for (counts.object.get("sites").?.array.items) |site| {
        const object = site.object;
        if (!std.mem.eql(u8, object.get("kind").?.string, kind) or !std.mem.eql(u8, object.get("function").?.string, function)) continue;
        total += object.get("count").?.integer;
    }
    return total;
}

fn firstLine(_: *const anyopaque, offset: u32) emit_llvm.Location {
    return .{ .line = 1, .column = offset + 1 };
}

fn calls(counts: std.json.Value, function: []const u8) i64 {
    for (counts.object.get("functions").?.array.items) |row| {
        if (std.mem.eql(u8, row.object.get("name").?.string, function)) return row.object.get("calls").?.integer;
    }
    return -1;
}

fn functionCount(counts: std.json.Value, function: []const u8, name: []const u8) i64 {
    for (counts.object.get("functions").?.array.items) |row| {
        if (std.mem.eql(u8, row.object.get("name").?.string, function)) return row.object.get(name).?.integer;
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
    \\        values.append(seed + i)
    \\    return values
    \\
    \\func returned_runtime(seed: int, count: int) -> int[]:
    \\    mut values: int[] = []
    \\    for i in range(count):
    \\        values.append(seed + i)
    \\    return values
    \\
    \\func main(args: str[], out: Stream) -> int:
    \\    const seed = len(args) + 3
    \\    const a = through_call(seed)
    \\    const b = local_only(seed)
    \\    const kept = returned(seed)
    \\    const dynamic = returned_runtime(seed, seed)
    \\    out.print(a, b, kept[2], len(dynamic))
    \\    return 0
;

// spec-case: NEW-CORE-STACK-2
test "stack borrowing and caller constructors eliminate allocation while runtime-sized returned storage stays managed" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "borrowed.my", .data = borrowed_stack_source });
    const source = try std.fs.path.join(a, &.{ root, "borrowed.my" });
    const plain = try counted(a, root, source, &.{}, &.{});
    try std.testing.expectEqualStrings("12 12 5 3\n", plain.stdout);
    try std.testing.expectEqual(@as(u8, 0), plain.status);
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
            try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "retain", function));
            try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "release", function));
            try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "release_unique", function));
        }
        try std.testing.expectEqual(@as(i64, 1), calls(result.counts, "fold"));
        // The constructor is now physically in main; counter attribution follows
        // the caller, while the dynamic constructor still executes its own call.
        try std.testing.expectEqual(@as(i64, -1), calls(result.counts, "returned"));
        try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, "main", "allocs"));
        try std.testing.expectEqual(@as(i64, 0), functionCount(result.counts, "main", "alloc_bytes"));
        try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "retain", "returned"));
        try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "release", "returned"));
        try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "release_unique", "returned"));
        try std.testing.expect(functionCount(result.counts, "returned_runtime", "allocs") > 0);
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
    const unoptimized = try counted(a, root, source, &.{ "--counters", "--unoptimized" }, &.{});
    try std.testing.expectEqualStrings(plain.stdout, unoptimized.stdout);
    try std.testing.expect(functionCount(unoptimized.counts, "through_call", "allocs") > 0);
    try std.testing.expect(functionCount(unoptimized.counts, "local_only", "allocs") > 0);
    try std.testing.expect(functionCount(unoptimized.counts, "returned", "allocs") > 0);
}

const unique_tree_source =
    \\func probe(n: int) -> int:
    \\    mut pages: int[][][] = []
    \\    for i in range(n):
    \\        mut rows: int[][] = []
    \\        rows.append([i, i + 1])
    \\        rows.append([])
    \\        pages.append(rows)
    \\    const saved = pages.copy()
    \\    pages = [[[n]], [[n + 1]]]
    \\    mut popped = pages.pop()
    \\    popped.append([9])
    \\    popped.clear()
    \\    if n % 2 == 0:
    \\        pages.clear()
    \\    return len(pages) * 100 + len(saved[0][0]) * 10 + len(saved) + saved[0][0][1]
    \\func main(args: str[], out: Stream) -> int:
    \\    out.print(probe(len(args)))
    \\    return 0
;

// spec-case: NEW-CORE-SINGLE-OWNER-2
test "single owner nested cleanup has no runtime RC after replacement pop clear and branches" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "tree.my", .data = unique_tree_source });
    const source = try std.fs.path.join(a, &.{ root, "tree.my" });
    const modes = [_][]const []const u8{
        &.{ "--counters", "--unoptimized", "--experimental-single-owner" },
        &.{ "--counters", "--release", "--experimental-single-owner" },
        &.{ "--counters", "--release", "--verify-facts", "--experimental-single-owner" },
    };
    for (modes) |flags| {
        for ([_][]const []const u8{ &.{ "x", "x" }, &.{ "x", "x", "x" } }, [_][]const u8{ "23\n", "124\n" }) |arguments, answer| {
            const result = try counted(a, root, source, flags, arguments);
            try std.testing.expectEqual(@as(u8, 0), result.status);
            try std.testing.expectEqualStrings(answer, result.stdout);
            try std.testing.expectEqualStrings("", result.stderr);
            try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
            for (result.counts.object.get("functions").?.array.items) |row| {
                const name = row.object.get("name").?.string;
                if (std.mem.eql(u8, name, "<outside>")) continue;
                try std.testing.expectEqual(@as(i64, 0), row.object.get("runtime_retains").?.integer);
                try std.testing.expectEqual(@as(i64, 0), row.object.get("runtime_releases").?.integer);
                try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "retain", name));
                try std.testing.expectEqual(@as(i64, 0), executed(result.counts, "release", name));
            }
            try std.testing.expect(field(result.counts, &.{ "kinds", "release_unique", "count" }) > 0);
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-2
// spec: NEW-CORE-ZERO-RC-ABI-1
test "zero RC whole program includes startup arguments and nested text cleanup" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "owned.my", .data =
        \\func main(args: str[], out: Stream) -> int:
        \\    mut texts: str[] = []
        \\    for arg in args:
        \\        texts.append(arg.copy())
        \\    mut text = ""
        \\    for i in range(20):
        \\        text += "aλ"
        \\    const saved = text.copy()
        \\    const part = saved[0:1]
        \\    out.print(len(texts), len(saved), part[0])
        \\    return 0
    });
    const source = try std.fs.path.join(a, &.{ root, "owned.my" });
    for ([_][]const []const u8{
        &.{ "--counters", "--unoptimized", "--experimental-zero-rc" },
        &.{ "--counters", "--release", "--verify-facts", "--experimental-zero-rc" },
    }) |flags| {
        const result = try counted(a, root, source, flags, &.{ "hello", "λ" });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("2 40 a\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        for ([_][]const u8{ "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "live_bytes_at_exit" }) |name| {
            try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", name }));
        }
        for ([_][]const u8{ "retain", "release", "unique_test" }) |name| {
            try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "kinds", name, "count" }));
        }
        try std.testing.expect(field(result.counts, &.{ "totals", "allocs" }) > 0);
        try std.testing.expect(field(result.counts, &.{ "kinds", "release_unique", "count" }) > 0);
    }
}

fn snapshotSource(comptime method: []const u8, comptime sharing: []const u8) []const u8 {
    return
    \\func main(args: str[], out: Stream) -> int:
    \\    mut rows: int[][] = []
    \\    for i in range(len(args) * 10):
    \\        rows.append([i, i + 1])
    \\
    ++ sharing ++ "    mut saved = rows." ++ method ++ "()\n" ++
        \\    saved[0].append(9)
        \\    out.print(len(rows[0]), len(saved[0]))
        \\    return 0
        \\
    ;
}

// spec-case: NEW-CORE-SINGLE-OWNER-4
test "single owner snapshots avoid eager child allocations while copy stays eager in shared families" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const sources = [_][]const u8{
        snapshotSource("snapshot", ""),
        snapshotSource("copy", ""),
        snapshotSource("copy", "    const shared = rows.snapshot()\n    assert len(shared) == len(rows)\n"),
    };
    var results: [3]Counted = undefined;
    for (sources, &results, 0..) |source, *result, index| {
        const name = try std.fmt.allocPrint(a, "snapshot-{d}.my", .{index});
        try directory.dir.writeFile(std.testing.io, .{ .sub_path = name, .data = source });
        result.* = try counted(a, root, try std.fs.path.join(a, &.{ root, name }), &.{ "--counters", "--release", "--experimental-single-owner" }, &.{ "x", "x", "x", "x" });
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("2 3\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", "live_bytes_at_exit" }));
    }
    const path = &.{ "totals", "allocs" };
    try std.testing.expect(field(results[0].counts, path) < field(results[1].counts, path));
    try std.testing.expectEqual(field(results[1].counts, path), field(results[2].counts, path));
    try std.testing.expectEqual(@as(i64, 2), field(results[0].counts, &.{ "totals", "list_copies" }));
    try std.testing.expectEqual(@as(i64, 40), field(results[2].counts, &.{ "totals", "list_copies" }));
}

// spec: NEW-CORE-COUNTERS-1
test "a counting build records copies, count updates, uniqueness tests and memory, and prints what an ordinary build prints" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const plain = try counted(a, root, "counters.my", &.{}, &.{});
    const debug = try counted(a, root, "counters.my", &.{ "--counters", "--unoptimized" }, &.{});
    try std.testing.expectEqualStrings("100 101 4\n", plain.stdout);
    try std.testing.expectEqualStrings(plain.stdout, debug.stdout);
    try std.testing.expectEqualStrings(plain.stderr, debug.stderr);
    try std.testing.expectEqual(plain.status, debug.status);
    try std.testing.expectEqualStrings("mylang-counters-v1", debug.counts.object.get("version").?.string);
    // `ys = xs; ys.append(5)` copies the hundred elements of `xs` once.
    try std.testing.expectEqual(@as(i64, 1), field(debug.counts, &.{ "kinds", "list_copy", "count" }));
    try std.testing.expectEqual(@as(i64, 800), field(debug.counts, &.{ "kinds", "list_copy", "bytes" }));
    try std.testing.expectEqual(@as(i64, 800), field(debug.counts, &.{ "totals", "list_copy_bytes" }));
    // `bump` lends its 40-byte element to `bumped` where it lies (NEW-CORE-CE2-RESULTS-4), which
    // copies it to update `a`, and copies the new record back in; the element it replaces is
    // released where it is, never copied out (NEW-CORE-CE-LISTS-2).
    try std.testing.expectEqual(@as(i64, 10), calls(debug.counts, "bump"));
    try std.testing.expectEqual(@as(i64, 0), sites(debug.counts, "record_copy", "list_get", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 400), sites(debug.counts, "record_copy", "record_set", "bumped", "bytes"));
    try std.testing.expectEqual(@as(i64, 400), sites(debug.counts, "record_copy", "list_set", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 0), sites(debug.counts, "record_copy", "list_set.old", "bump", "bytes"));
    try std.testing.expectEqual(@as(i64, 10), sites(debug.counts, "unique_test", "is_unique", "bump", "count"));
    try std.testing.expectEqual(@as(i64, 10), sites(debug.counts, "unique_test", "is_unique", "bump", "extra"));
    try std.testing.expectEqual(@as(i64, 121), sites(debug.counts, "list_push", "list_push", "main", "count"));
    // Growing `xs` to a hundred elements moves its earlier elements; the pushes that grew it say so.
    try std.testing.expectEqual(field(debug.counts, &.{ "totals", "list_grow_bytes" }) + field(debug.counts, &.{ "totals", "realloc_moved_bytes" }), field(debug.counts, &.{ "kinds", "list_push", "extra" }));
    try std.testing.expect(field(debug.counts, &.{ "kinds", "list_push", "extra" }) > 0);
    try std.testing.expect(field(debug.counts, &.{ "kinds", "retain", "count" }) >= 10);
    // Each retain in `bumped` shares one record's one-element list: 8 data bytes.
    try std.testing.expectEqual(@as(i64, 80), sites(debug.counts, "retain", "retain", "bumped", "bytes"));
    try std.testing.expect(field(debug.counts, &.{ "totals", "list_grows" }) > 0);
    try std.testing.expectEqual(field(debug.counts, &.{ "totals", "allocs" }), field(debug.counts, &.{ "totals", "frees" }));
    try std.testing.expectEqual(@as(i64, 0), field(debug.counts, &.{ "totals", "live_bytes_at_exit" }));
    try std.testing.expect(field(debug.counts, &.{ "totals", "peak_live_bytes" }) >= 800);
    // A release build counts the same copy; a trap still writes the counts.
    const release = try counted(a, root, "counters.my", &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqualStrings(plain.stdout, release.stdout);
    try std.testing.expectEqual(@as(i64, 800), field(release.counts, &.{ "kinds", "list_copy", "bytes" }));
    const trapped = try counted(a, root, "counters.my", &.{"--counters"}, &.{"trap"});
    try std.testing.expectEqual(@as(u8, 1), trapped.status);
    try std.testing.expect(contains(trapped.stderr, "R_LIST_BOUNDS"));
    try std.testing.expectEqual(@as(i64, 800), field(trapped.counts, &.{ "kinds", "list_copy", "bytes" }));
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
        \\    mut ys = xs
        \\    ys.append(1)
        \\    return ys
        \\func main(out: Stream) -> int:
        \\    out.print(len(twice([1, 2])))
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
        .source_path = "counters.my",
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
    const built = try cli_args.parse(a, .build, &.{ "p.my", "-o", "p", "--counters" }, "zig", &failure);
    try std.testing.expect(built.build.show.codegen.counters);
    const ran = try cli_args.parse(a, .run, &.{ "p.my", "--counters", "--release" }, "zig", &failure);
    try std.testing.expect(ran.build.show.codegen.counters and ran.build.mode == .release);
    try std.testing.expectError(error.Usage, cli_args.parse(a, .build, &.{ "p.my", "-o", "p", "--counters", "--counters" }, "zig", &failure));
    const plain = try cli_args.parse(a, .build, &.{ "p.my", "-o", "p" }, "zig", &failure);
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
        \\{"version":"mylang-counters-v1","totals":{},"kinds":{},
        \\"functions":[{"name":"main","calls":1,"allocs":3,"alloc_bytes":96,"list_copies":1,"list_copy_bytes":800,"list_grow_bytes":64,"runtime_retains":2},
        \\  {"name":"bump","calls":10},{"name":"<outside>","calls":0,"allocs":1}],
        \\"sites":[{"function":"bump","kind":"record_copy","count":20,"bytes":800,"extra":0},
        \\  {"function":"bump","kind":"unique_test","count":10,"bytes":0,"extra":7},
        \\  {"function":"bump","kind":"retain","count":10,"bytes":80,"extra":0},
        \\  {"function":"main","kind":"list_copy","count":1,"bytes":800,"extra":0}]}
    ;
    const section = try dynamic.rows(a, static, document);
    try std.testing.expectEqual(@as(usize, 3), section.len);
    try std.testing.expectEqual(@as(u64, 1), section[0].run.copies);
    try std.testing.expectEqual(@as(u64, 800), section[0].run.copied_bytes);
    try std.testing.expectEqual(@as(u64, 64), section[0].run.growth_bytes);
    try std.testing.expectEqual(@as(u64, 2), section[0].run.rc.runtime);
    try std.testing.expectEqual(@as(u64, 10), section[1].run.calls);
    try std.testing.expectEqual(@as(u64, 20), section[1].run.copies);
    try std.testing.expectEqual(@as(u64, 3), section[1].run.unique.shared);
    try std.testing.expectEqual(@as(u64, 10), section[1].run.rc.retains);
    try std.testing.expectEqual(@as(u64, 0), section[2].run.calls);
    var text: std.ArrayList(u8) = .empty;
    try dynamic.render(a, &text, section);
    try std.testing.expect(contains(text.items, "bump: calls 10; retains 10; releases 0; runtime count updates 0; unique tests 10 (3 shared); copies 20 (800 bytes)"));
    try std.testing.expect(contains(text.items, "TOTAL: calls 11;"));
    try std.testing.expectError(error.InvalidCounters, dynamic.rows(a, static, "{\"version\":\"cost-v1\"}"));
    try std.testing.expectError(error.InvalidCounters, dynamic.rows(a, static, "not json"));
    try std.testing.expectEqualStrings("c.json", command.parse(&.{ "p.my", "--counters", "c.json" }).?.counters.?);
    try std.testing.expectEqual(@as(?command.Request, null), command.parse(&.{ "p.my", "--counters", "a.json", "--counters", "b.json" }));
    try std.testing.expectEqual(@as(?command.Request, null), command.parse(&.{ "p.my", "--counters" }));
}

// spec: NEW-CORE-COUNTERS-6
test "a counting build counts each bounds, overflow, division and shift check it executes, at its site" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const plain = try counted(a, root, "counters_checks.my", &.{}, &.{});
    const debug = try counted(a, root, "counters_checks.my", &.{ "--counters", "--unoptimized" }, &.{});
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
    // A release build prints the same and still counts the checks its passes kept.
    const release = try counted(a, root, "counters_checks.my", &.{ "--counters", "--release" }, &.{});
    try std.testing.expectEqualStrings(plain.stdout, release.stdout);
    try std.testing.expect(field(release.counts, &.{ "kinds", "shift_check", "count" }) >= 4);
    // A build without the flag counts nothing: its text names no check site.
    const text = try support.llvmText(a, "func f(a: int, b: int) -> int:\n    return a // b\nfunc main() -> int:\n    return f(7, 2)\n");
    try std.testing.expect(!contains(text, "myl.cs."));
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
        \\{"version":"mylang-counters-v1","totals":{},"kinds":{},
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

// spec-case: NEW-CORE-ZERO-RC-VIEWS-1
test "zero RC views repeated borrowing performs no managed allocations or RC" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    try directory.dir.writeFile(std.testing.io, .{ .sub_path = "views.my", .data =
        \\func part(source: TextView, start: int) -> TextView noalloc:
        \\    return source.borrow(start, start + 3)
        \\func main(out: Stream) -> int:
        \\    const text = "aλ🙂z1234"
        \\    const full = text.borrow(0, len(text))
        \\    mut total = 0
        \\    for i in range(10000):
        \\        const view = part(full, i % 5)
        \\        total += len(view)
        \\    out.print(total)
        \\    return 0
    });
    const source = try std.fs.path.join(a, &.{ root, "views.my" });
    for ([_][]const []const u8{
        &.{ "--counters", "--unoptimized", "--experimental-zero-rc" },
        &.{ "--counters", "--release", "--verify-facts", "--experimental-zero-rc" },
    }) |flags| {
        const result = try counted(a, root, source, flags, &.{});
        try std.testing.expectEqual(@as(u8, 0), result.status);
        try std.testing.expectEqualStrings("30000\n", result.stdout);
        try std.testing.expectEqualStrings("", result.stderr);
        for ([_][]const u8{ "allocs", "reallocs", "runtime_retains", "runtime_releases", "shared_retains", "shared_releases", "live_bytes_at_exit" }) |name| {
            try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "totals", name }));
        }
        for ([_][]const u8{ "retain", "release", "unique_test" }) |name| {
            try std.testing.expectEqual(@as(i64, 0), field(result.counts, &.{ "kinds", name, "count" }));
        }
    }
}

// spec-case: NEW-CORE-ZERO-RC-PAYLOAD-TRANSFER-1
test "zero RC payload transfer counts boxed cleanup without retaining its children" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var directory = std.testing.tmpDir(.{});
    defer directory.cleanup();
    const root = try directory.dir.realPathFileAlloc(std.testing.io, ".", a);
    const result = try counted(a, root, "zero_rc_payload_box.my", &.{ "--experimental-zero-rc", "--release", "--counters" }, &.{});
    try std.testing.expectEqual(@as(u8, 0), result.status);
    try std.testing.expectEqualStrings("none\n15\n15\n", result.stdout);
    try std.testing.expectEqualStrings("", result.stderr);
    for ([_][]const []const u8{
        &.{ "kinds", "retain", "count" },  &.{ "kinds", "release", "count" },    &.{ "kinds", "unique_test", "count" },
        &.{ "totals", "runtime_retains" }, &.{ "totals", "runtime_releases" },   &.{ "totals", "shared_retains" },
        &.{ "totals", "shared_releases" }, &.{ "totals", "live_bytes_at_exit" },
    }) |path| try std.testing.expectEqual(@as(i64, 0), field(result.counts, path));
    try std.testing.expect(field(result.counts, &.{ "kinds", "release_unique", "count" }) > 0);
}
