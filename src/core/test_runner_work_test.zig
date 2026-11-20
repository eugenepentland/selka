//! A test trial's work (NEW-CORE-TEST-WORK-1): the executed steps and peak managed
//! bytes `selka test --json` reports, the receipt that carries them to a cached
//! result, and the one `work:` line a plain run prints when a test's steps crossed 2x
//! since the last run of the same test in the same build mode.
const std = @import("std");
const options = @import("core_test_options");
const report = @import("test_runner_report.zig");
const counts = @import("test_runner_counts.zig");
const test_work = @import("test_work.zig");
const Value = std.json.Value;

/// A `bool` test whose loop runs ten times and allocates nothing: exactly 33 executed
/// blocks (one entry, one header per iteration, one body and one latch per iteration,
/// one exit — the last iteration's header is the failing condition). Its peak is one
/// 64 KiB chunk, the block the runtime already carves small allocations from when the
/// trial starts; the trial allocates nothing more.
const scalar_source =
    \\func test_work() -> bool:
    \\    mut total = 0
    \\    mut i = 0
    \\    while i < 10:
    \\        total += i
    \\        i += 1
    \\    return True
;

/// The same test appending to a list, whose growth allocates: used where the step
/// count has to change so the `work:` line can cross 2x.
fn loopSource(a: std.mem.Allocator, times: u32) ![]const u8 {
    return std.fmt.allocPrint(a,
        \\func test_work() -> bool:
        \\    mut xs: int[] = []
        \\    mut i = 0
        \\    while i < {d}:
        \\        append(mut xs, i)
        \\        i += 1
        \\    return True
    , .{times});
}

/// `selka test work_test.selka` in `root` with `flags`, under a private cache and no
/// shared receipts, answering its standard output.
fn run(a: std.mem.Allocator, root: []const u8, flags: []const []const u8, environment: *std.process.Environ.Map) ![]const u8 {
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{
        options.corePath(),
        "test",
        try std.fs.path.join(a, &.{ root, "work_test.selka" }),
        "--cache-dir",
        try std.fs.path.join(a, &.{ root, "cache" }),
        "--jobs",
        "1",
    });
    try argv.appendSlice(a, flags);
    const result = try std.process.run(a, std.testing.io, .{ .argv = argv.items, .environ_map = environment });
    return result.stdout;
}

/// The single test object of a `native-tests-v1` report.
fn onlyTest(report_text: []const u8, a: std.mem.Allocator) !Value {
    const parsed = try std.json.parseFromSliceLeaky(Value, a, report_text, .{});
    const tests = parsed.object.get("tests").?;
    try std.testing.expectEqual(@as(usize, 1), tests.array.items.len);
    return tests.array.items[0];
}

/// The integer `key` of a test object, or -1 when the report has no such field.
fn number(item: Value, key: []const u8) i64 {
    const found = item.object.get(key) orelse return -1;
    return if (found == .integer) found.integer else -1;
}

// spec: NEW-CORE-TEST-WORK-1
test "the work line prints exactly when a test's steps cross 2x since its last run in the same mode" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var line = [_]report.Verdict{.{ .name = "app::test_crossing", .status = .passed, .details = .{ .counts = .{ .steps = 41200, .peak_bytes = 100 } } }};
    // No previous record: nothing prints, and the record is made for the next run.
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    // 4.1x more steps: one line, with the counts grouped as a reader writes them.
    line[0].details = .{ .counts = .{ .steps = 168900, .peak_bytes = 100 } };
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("work: app::test_crossing steps 41,200 → 168,900 (4.1×)", line[0].details.work_line);
    // The comparison is against the last run, so an unchanged rerun is silent.
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    // The other direction has the same threshold: half the steps is one line.
    line[0].details = .{ .counts = .{ .steps = 84450, .peak_bytes = 100 } };
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("work: app::test_crossing steps 168,900 → 84,450 (0.5×)", line[0].details.work_line);
    // A change below 2x prints nothing but becomes the next baseline.
    line[0].details = .{ .counts = .{ .steps = 90000, .peak_bytes = 100 } };
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    // Exactly 2x is the threshold: it crosses.
    line[0].details = .{ .counts = .{ .steps = 180000, .peak_bytes = 100 } };
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("work: app::test_crossing steps 90,000 → 180,000 (2.0×)", line[0].details.work_line);
    // A run in another build mode has its own record: nothing to compare yet.
    line[0].details = .{ .counts = .{ .steps = 999999, .peak_bytes = 100 } };
    counts.compare(a, std.testing.io, cache, "release", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    line[0].details = .{ .counts = .{ .steps = 1999998, .peak_bytes = 100 } };
    counts.compare(a, std.testing.io, cache, "release", &line);
    try std.testing.expectEqualStrings("work: app::test_crossing steps 999,999 → 1,999,998 (2.0×)", line[0].details.work_line);
    // Peak memory alone never prints: the line watches executed steps.
    line[0].details = .{ .counts = .{ .steps = 1999998, .peak_bytes = 9000000 } };
    counts.compare(a, std.testing.io, cache, "release", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
}

// spec: NEW-CORE-TEST-WORK-1
test "a zero or damaged previous record prints nothing and the store replaces it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const cache = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var line = [_]report.Verdict{.{ .name = "app::test_zero", .status = .passed, .details = .{ .counts = .{ .steps = 1, .peak_bytes = 0 } } }};
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    // A ratio to zero is undefined: a record of zero steps prints nothing either.
    const zero_path = try std.fmt.allocPrint(a, "{s}/{s}/debug/{s}.txt", .{ cache, counts.root, std.fmt.bytesToHex(blake16("app::test_zero"), .lower) });
    try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(zero_path).?);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = zero_path, .data = "steps 0\npeak_bytes 0\n" });
    line[0].details = .{ .counts = .{ .steps = 400, .peak_bytes = 0 } };
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    // A record holding one line is damaged and reads as no record at all.
    line[0].details = .{ .counts = .{ .steps = 800, .peak_bytes = 0 } };
    line[0].name = "app::test_damaged";
    const path = try std.fmt.allocPrint(a, "{s}/tests/work-v1/debug/{s}.txt", .{ cache, std.fmt.bytesToHex(blake16("app::test_damaged"), .lower) });
    try std.Io.Dir.cwd().createDirPath(std.testing.io, std.fs.path.dirname(path).?);
    try std.Io.Dir.cwd().writeFile(std.testing.io, .{ .sub_path = path, .data = "steps 100\n" });
    try std.testing.expect(test_work.read(a, std.testing.io, path) == null);
    counts.compare(a, std.testing.io, cache, "debug", &line);
    try std.testing.expectEqualStrings("", line[0].details.work_line);
    // The comparison replaced the damaged record with the run's own counts.
    try std.testing.expect(test_work.read(a, std.testing.io, path) != null);
}

/// The 16-byte digest `recordPath` names a test's store file by.
fn blake16(name: []const u8) [16]u8 {
    var digest: [16]u8 = undefined;
    @import("fast_blake3.zig").hash(name, &digest);
    return digest;
}

// spec: NEW-CORE-TEST-WORK-1
test "selka test --json reports a trial's steps and peak bytes and its record repeats them" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "work_test.selka", .data = scalar_source });
    var environment = try options.privateEnvironment(a);
    const first = try onlyTest(try run(a, root, &.{ "--json", "--force" }, &environment), a);
    try std.testing.expectEqualStrings("passed", first.object.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 33), number(first, "steps"));
    try std.testing.expectEqual(@as(i64, 65536), number(first, "peak_bytes"));
    // The engine's record holds the counts, so a cached result carries them. Without the stored report the next run answers
    // from the test's own record.
    try std.Io.Dir.cwd().deleteTree(std.testing.io, try std.fs.path.join(a, &.{ root, "cache", "engine-v1", "records", "test-report" }));
    const cached = try onlyTest(try run(a, root, &.{"--json"}, &environment), a);
    try std.testing.expectEqualStrings("cached", cached.object.get("status").?.string);
    try std.testing.expectEqual(@as(i64, 33), number(cached, "steps"));
    try std.testing.expectEqual(@as(i64, 65536), number(cached, "peak_bytes"));
}

// spec: NEW-CORE-TEST-WORK-1
test "a plain selka test prints one work line only when a test's steps cross 2x, in either direction" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try options.privateEnvironment(a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "work_test.selka", .data = try loopSource(a, 100) });
    // No previous record: the listing is exactly what it was before work was counted.
    const first = try run(a, root, &.{}, &environment);
    try std.testing.expect(std.mem.indexOf(u8, first, "work: ") == null);
    try std.testing.expect(std.mem.startsWith(u8, first, "passed work_test::test_work\n1 passed"));
    // A tenth of the iterations halves the step count by more than 2x: one line.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "work_test.selka", .data = try loopSource(a, 10) });
    const shrunk = try run(a, root, &.{"--force"}, &environment);
    try std.testing.expect(std.mem.startsWith(u8, shrunk, "passed work_test::test_work\nwork: work_test::test_work steps "));
    try std.testing.expect(std.mem.indexOf(u8, shrunk, " → ") != null);
    try std.testing.expect(std.mem.endsWith(u8, shrunk, "1 passed, 0 cached, 0 failed, 0 skipped\n"));
    // And back up past 2x prints one line again, in the other direction of the ratio.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "work_test.selka", .data = try loopSource(a, 100) });
    const grown = try run(a, root, &.{"--force"}, &environment);
    try std.testing.expect(std.mem.startsWith(u8, grown, "passed work_test::test_work\nwork: work_test::test_work steps "));
}

/// A directory of two roots that import one library: each root's run lists the library's test and its own.
const two_roots = [_][2][]const u8{
    .{ "lib.selka", "public func value() -> int:\n    return 3\n\n\npublic func test_lib() -> bool:\n    return value() == 3\n" },
    .{ "one.selka", "import lib\n\n\npublic func test_one() -> bool:\n    return lib.value() + 1 == 4\n" },
    .{ "two.selka", "import lib\n\n\npublic func test_two() -> bool:\n    return lib.value() + 2 == 5\n" },
    .{ "selka.json", "{\"version\":2}" },
};

/// The `cache.work.rule` counts of every verdict that carries a work report, in report order.
fn rules(a: std.mem.Allocator, report_text: []const u8) ![]const [3]i64 {
    const parsed = try std.json.parseFromSliceLeaky(Value, a, report_text, .{});
    var found: std.ArrayList([3]i64) = .empty;
    for (parsed.object.get("tests").?.array.items) |item| {
        const cache = item.object.get("cache") orelse continue;
        const work = cache.object.get("work") orelse continue;
        if (work != .object) continue;
        const rule = work.object.get("rule").?;
        try found.append(a, .{ number(rule, "evaluations"), number(rule, "paths"), number(rule, "proofs") });
    }
    return found.items;
}

// spec: TEST-LOOP-RULE-COUNTS-1
test "the work report counts the shared tier's rule for each root: its evaluations, the paths they resolve and the proofs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    try temporary.dir.createDirPath(std.testing.io, "project");
    for (two_roots) |file| try temporary.dir.writeFile(std.testing.io, .{ .sub_path = try std.fs.path.join(a, &.{ "project", file[0] }), .data = file[1] });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    var environment = try options.privateEnvironment(a);
    const project = try std.fs.path.join(a, &.{ root, "project" });
    const cache = try std.fs.path.join(a, &.{ root, "cache" });
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const argv = [_][]const u8{ options.corePath(), "test", project, "--json", "--cache-dir", cache, "--shared-cache-dir", shared, "--jobs", "1" };
    const result = try std.process.run(a, std.testing.io, .{ .argv = &argv, .environ_map = &environment });
    try std.testing.expectEqual(std.process.Child.Term{ .exited = 0 }, result.term);
    // Each root reports its rule once, on its first verdict. `one` runs two tests (the library's, which it owns, and its
    // own), `two` only its own (stage 2). Each test's record is decided twice (its IR key when the private store misses and
    // the tier is asked, its program when the pass is published): 4 and 2 evaluations. Each root reads its program once for
    // the run (stage 1): the entry, its configuration and the 4 sources of the program the two roots are checked as resolve
    // once, 6 paths, where each evaluation resolved them again before (24). Each test's call tree is walked once: 2 and 1
    // proofs, where the runner and the rule walked it up to four times (8).
    const counted = try rules(a, result.stdout);
    try std.testing.expectEqual(@as(usize, 2), counted.len);
    try std.testing.expectEqual([3]i64{ 4, 6, 2 }, counted[0]);
    try std.testing.expectEqual([3]i64{ 2, 6, 1 }, counted[1]);
}
