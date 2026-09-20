//! Whole-directory native guest test runs fanned out across the machine's cores.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const invalidation = @import("invalidation.zig");
const budget = @import("memory_budget");
const snapshot = @import("native_test_snapshot.zig");
/// Directory discovery and child-report transport failures.
pub const Error = fs.Error || std.json.ParseError(std.json.Scanner) || std.Io.Dir.OpenError ||
    std.Io.Dir.SelectiveWalker.Error || std.Io.File.OpenError ||
    error{ TooManyTestPrograms, UnusableTestReport, DirectoryCasesUnsupported, DirectoryBenchmarksUnsupported };
/// Largest program count one directory run will fan out.
const program_limit = 4096;
const report_version = "native-tests-v1";
/// Byte ceiling for reading one candidate entry while deciding whether it is a root.
const entry_read_limit = 16 * 1024 * 1024;
/// Whether the command's source argument names a directory of programs rather
/// than one project entry.
pub fn selected(context: fs.Context, source: []const u8) bool {
    const info = std.Io.Dir.cwd().statFile(context.io, source, .{}) catch return false;
    return info.kind == .directory;
}
/// Every `.my` entry beneath `source`, in sorted path order, skipping the
/// generated directories a source tree carries alongside its programs. An entry
/// is a file that declares a top-level `main` — so a directory holding one
/// project is one program, not one per module — or a standalone `*_test.my`.
pub fn programs(context: fs.Context, source: []const u8) Error![]const []const u8 {
    const root = try context.absolute(source);
    var directory = try std.Io.Dir.cwd().openDir(context.io, root, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(context.io);
    var walker = try directory.walk(context.allocator);
    defer walker.deinit();
    var found: std.ArrayList([]const u8) = .empty;
    while (try walker.next(context.io)) |item| {
        if (generated(item.basename)) {
            walker.leave(context.io);
            continue;
        }
        if (item.kind != .file or !std.mem.endsWith(u8, item.path, ".my")) continue;
        try found.append(context.allocator, try std.fs.path.join(context.allocator, &.{ root, item.path }));
    }
    var entries: std.ArrayList([]const u8) = .empty;
    for (found.items) |path| {
        if (!isTestFile(path) and !try declaresMainFile(context, path)) continue;
        try bounded(entries.items.len);
        try entries.append(context.allocator, path);
    }
    std.mem.sort([]const u8, entries.items, {}, before);
    return entries.items;
}
/// A standalone test entry follows the `*_test.my` convention.
fn isTestFile(path: []const u8) bool {
    return std.mem.endsWith(u8, std.fs.path.basename(path), "_test.my");
}
/// A project root is a `.my` file with a top-level `main`; a module imported by
/// one has neither. An unreadable or oversized file is not treated as an entry.
fn declaresMainFile(context: fs.Context, path: []const u8) Error!bool {
    const bytes = std.Io.Dir.cwd().readFileAlloc(context.io, path, context.allocator, .limited(entry_read_limit)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    return snapshot.declaresMain(bytes);
}
/// Workers one directory run may keep busy: `--jobs`/`MYLANG_JOBS` when asked
/// for, otherwise the cores the machine has, capped by how many per-child
/// ceilings its free memory holds. A cold fan-out on a loaded machine then
/// waits instead of pushing the whole machine into swap.
fn width(context: fs.Context, opts: options.Options, programs_found: usize) usize {
    // Benchmark workers must not compete with each other, so a directory suite
    // measures one program at a time even on a many-core machine.
    if (opts.bench.pattern != null) return 1;
    return budget.workers(.{
        .jobs = opts.jobs,
        .programs = programs_found,
        .cores = std.Thread.getCpuCount() catch 1,
        .free = budget.available(context.io),
        .ceiling = opts.limits.max_memory orelse budget.test_default,
    });
}
/// Run one child command per program, bounded by cores and free memory, and
/// merge the reports those children write. Each child owns its own project, so
/// the shared object cache and receipt directory are the only state they
/// contend over.
pub fn run(context: fs.Context, opts: options.Options) Error!u8 {
    if (opts.cases != null) return error.DirectoryCasesUnsupported;
    // Baseline enforcement needs one aggregated report; a directory run reports
    // each program's benchmarks through its own exit status instead.
    if (opts.bench.output != null or opts.bench.baseline != null or opts.bench.policy != null) return error.DirectoryBenchmarksUnsupported;
    const a = context.allocator;
    const compiler = try std.Io.Dir.cwd().realPathFileAlloc(context.io, "/proc/self/exe", a);
    const paths = try programs(context, opts.source);
    const cache = try context.absolute(opts.cache);
    try context.mkdir(cache);
    const workspace = try context.temporary(cache);
    defer context.remove(workspace);
    const outcomes = try a.alloc(Outcome, paths.len);
    const workers = width(context, opts, paths.len);
    var start: usize = 0;
    while (start < paths.len) : (start += workers) {
        try wave(context, .{ .compiler = compiler, .options = opts, .workspace = workspace }, paths[start..@min(start + workers, paths.len)], outcomes[start..]);
    }
    return summarize(context, opts, paths, outcomes);
}
/// One child program's exit status and the report bytes it produced.
const Outcome = struct { code: u8, report: []const u8 };
/// Values shared by every child of a directory run.
const Fanout = struct { compiler: []const u8, options: options.Options, workspace: []const u8 };
fn wave(context: fs.Context, shared: Fanout, paths: []const []const u8, outcomes: []Outcome) Error!void {
    const a = context.allocator;
    const children = try a.alloc(std.process.Child, paths.len);
    const files = try a.alloc(std.Io.File, paths.len);
    const reports = try a.alloc([]const u8, paths.len);
    for (children, files, reports, paths, 0..) |*child, *file, *report, path, slot| {
        report.* = try std.fmt.allocPrint(a, "{s}/{d}.json", .{ shared.workspace, slot });
        file.* = try std.Io.Dir.cwd().createFile(context.io, report.*, .{});
        child.* = try std.process.spawn(context.io, .{ .argv = try argv(context, shared, path), .stdout = .{ .file = file.* } });
    }
    for (children, files, reports, outcomes[0..paths.len]) |*child, file, report, *outcome| {
        outcome.code = fs.exitCode(try child.wait(context.io));
        file.close(context.io);
        outcome.report = context.read(report) catch "";
    }
}
fn argv(context: fs.Context, shared: Fanout, source: []const u8) Error![]const []const u8 {
    const a = context.allocator;
    const opts = shared.options;
    var list: std.ArrayList([]const u8) = .empty;
    try list.appendSlice(a, &.{ shared.compiler, "test", source, "--json" });
    try list.appendSlice(a, &.{ "--filter", opts.filter, "--cache-dir", opts.cache });
    try list.appendSlice(a, &.{ "--qbe", opts.toolchain.qbe, "--zig", opts.toolchain.zig, "--mode", opts.mode });
    try list.appendSlice(a, &.{ "--max-steps", try decimal(a, opts.limits.max_steps) });
    try list.appendSlice(a, &.{ "--max-frames", try decimal(a, opts.limits.max_frames) });
    try list.appendSlice(a, &.{ "--max-calls", try decimal(a, opts.limits.max_calls) });
    try list.appendSlice(a, &.{ "--timeout-ms", try decimal(a, opts.limits.timeout_ms) });
    // Resolved before the fan-out, so every child enforces the same ceiling and
    // keys its receipts on it rather than rediscovering the environment itself.
    try list.appendSlice(a, &.{ "--max-memory", try decimal(a, opts.limits.max_memory orelse budget.test_default) });
    if (opts.flags.force) try list.append(a, "--force");
    if (opts.flags.no_cache) try list.append(a, "--no-cache");
    if (opts.flags.mutation_markers) try list.append(a, "--mutation-markers");
    // Each child derives its own program's affected selection against the same
    // reference, so a directory run narrows every project independently.
    if (opts.flags.affected) {
        try list.append(a, "--affected");
        if (opts.against) |reference| try list.appendSlice(a, &.{ "--against", reference });
    }
    if (opts.flags.gc_stress) try list.append(a, "--gc-stress");
    if (opts.bench.pattern) |pattern| {
        try list.appendSlice(a, &.{ "--bench", pattern, "--bench-profile", opts.bench.profile });
        if (opts.bench.only) try list.append(a, "--bench-only");
        try list.appendSlice(a, &.{ "--bench-warmup", try decimal(a, opts.bench.tuning.sampling.warmup_iterations) });
        try list.appendSlice(a, &.{ "--bench-batches", try decimal(a, opts.bench.tuning.sampling.batch_count) });
        try list.appendSlice(a, &.{ "--bench-batch-ms", try decimal(a, opts.bench.tuning.sampling.target_batch_ns / 1_000_000) });
        try list.appendSlice(a, &.{ "--bench-timeout-ms", try decimal(a, opts.bench.tuning.timeout_ms) });
    }
    try @import("native_link.zig").append(context, opts.link_arguments, &list, true);
    return list.items;
}
fn decimal(allocator: std.mem.Allocator, value: u64) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}
/// Merged counts over every child report of one directory run. `setup` counts
/// programs whose child produced no usable report — the work the run did not do.
const Totals = struct { passed: usize = 0, cached: usize = 0, failed: usize = 0, skipped: usize = 0, setup: usize = 0 };
fn summarize(context: fs.Context, opts: options.Options, paths: []const []const u8, outcomes: []const Outcome) Error!u8 {
    const a = context.allocator;
    var totals: Totals = .{};
    var rows: std.ArrayList(std.json.Value) = .empty;
    for (paths, outcomes) |path, outcome| {
        if (outcome.report.len == 0 or outcome.code == 2) {
            totals.setup += 1;
            // Name the program and its status: a totals-only reading of the
            // count line must never pass while whole programs are missing.
            try std.Io.File.stderr().writeStreamingAll(context.io, try droppedText(a, path, outcome));
            continue;
        }
        const parsed = try merged((try std.json.parseFromSlice(std.json.Value, a, outcome.report, .{ .allocate = .alloc_always })).value);
        totals.passed += @intCast(v.number(v.get(parsed, "passed")));
        totals.cached += @intCast(v.number(v.get(parsed, "cached")));
        totals.failed += @intCast(v.number(v.get(parsed, "failed")));
        totals.skipped += @intCast(v.number(v.get(parsed, "skipped")));
        for (v.array(v.get(parsed, "tests"))) |row| try rows.append(a, row);
    }
    try publish(context, opts.flags.output.json, paths.len, totals, rows.items);
    if (opts.flags.output.report) try reportWork(context, totals);
    // A benchmark run's children already fold their own correctness and
    // performance gates into one status, so the parent takes the most severe
    // child status instead of recomputing it from the test-case counts.
    if (opts.bench.pattern != null) return worstCode(outcomes);
    if (totals.setup != 0) return 2;
    if (totals.failed != 0) return 1;
    return if (totals.passed + totals.cached != 0) 0 else 3;
}
/// The stderr line naming one program whose child never produced a report.
fn droppedText(allocator: std.mem.Allocator, path: []const u8, outcome: Outcome) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "not run: {s} (exit {d}, no report)\n", .{ path, outcome.code });
}
/// Most severe child exit status: setup failure, then any failure, else green.
fn worstCode(outcomes: []const Outcome) u8 {
    var worst: u8 = 0;
    for (outcomes) |outcome| {
        if (outcome.code == 2) return 2;
        if (outcome.code == 1) worst = 1;
    }
    return worst;
}
/// A directory run reports the selected/executed/reused test counts it can
/// observe across children; per-stage compiler work is not aggregated here.
fn reportWork(context: fs.Context, totals: Totals) Error!void {
    var work: invalidation.Work = .{ .command = "test" };
    const executed = totals.passed + totals.failed;
    if (executed + totals.cached != 0) work.set(.executed_tests, executed, totals.cached);
    work.addBypass("directory-fanout-stage-detail", 1);
    const rendered = invalidation.renderWork(context.allocator, work) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidCurrent => return error.UnusableTestReport,
    };
    try std.Io.File.stderr().writeStreamingAll(context.io, try std.fmt.allocPrint(context.allocator, "{s}\n", .{rendered}));
}
fn publish(context: fs.Context, json: bool, count: usize, totals: Totals, rows: []const std.json.Value) Error!void {
    const a = context.allocator;
    const out = std.Io.File.stdout();
    if (!json) for (rows) |row| {
        const reason = v.text(v.get(row, "reason"));
        try out.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s} {s}{s}{s}\n", .{
            v.text(v.get(row, "status")), v.text(v.get(row, "name")), if (reason.len != 0) ": " else "", reason,
        }));
    };
    const text = if (json) try std.json.Stringify.valueAlloc(a, .{
        .version = report_version,
        .tests = rows,
        .passed = totals.passed,
        .failed = totals.failed,
        .skipped = totals.skipped,
        .cached = totals.cached,
        .executed = totals.passed + totals.failed,
        .programs = count,
        .dropped = totals.setup,
    }, .{}) else try summaryText(a, count, totals);
    try out.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{text}));
}
/// The merged count line of one directory run, carrying the programs whose child
/// produced no report so the totals cannot hide work the run never did.
fn summaryText(allocator: std.mem.Allocator, count: usize, totals: Totals) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{d} passed, {d} cached, {d} failed, {d} skipped, {d} dropped across {d} programs", .{
        totals.passed, totals.cached, totals.failed, totals.skipped, totals.setup, count,
    });
}
fn bounded(found: usize) Error!void {
    if (found >= program_limit) return error.TooManyTestPrograms;
}
fn merged(report: std.json.Value) Error!std.json.Value {
    if (!std.mem.eql(u8, v.text(v.get(report, "version")), report_version)) return error.UnusableTestReport;
    return report;
}
fn generated(basename: []const u8) bool {
    for ([_][]const u8{ ".mylang-cache", ".zig-cache", "zig-out", ".git" }) |name| {
        if (std.mem.eql(u8, name, basename)) return true;
    }
    return false;
}
fn before(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

// spec: NATIVE-TEST-4
test "a directory selects project roots and test-file entries, not every module" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    try context.mkdir(try std.fs.path.join(context.allocator, &.{ root, "nested" }));
    try context.mkdir(try std.fs.path.join(context.allocator, &.{ root, ".zig-cache" }));
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "second_test.my" }), "public def test_x() -> bool effects():\n    return True\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "first.my" }), "module first\nimport library\ndef main() -> int:\n    return 0\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "library.my" }), "module library\npublic def value() -> int effects():\n    return 1\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "notes.txt" }), "prose");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "nested", "third.my" }), "module third\ndef main() -> int:\n    return 0\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, ".zig-cache", "stale.my" }), "module stale\ndef main() -> int:\n    return 0\n");
    const found = try programs(context, root);
    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "first.my" }), found[0]);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "nested", "third.my" }), found[1]);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "second_test.my" }), found[2]);
    try std.testing.expect(selected(context, root));
    try std.testing.expect(!selected(context, found[0]));
}
// spec-case: NATIVE-TEST-4
test "each child command inherits the selection, budgets and tool choices of the run" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const opts = try options.parse(&.{ "suite", "--filter", "adder", "--force", "--no-cache", "--max-steps", "77", "--mode", "ReleaseFast" });
    const shared: Fanout = .{ .compiler = "/usr/bin/mylang", .options = opts, .workspace = "/tmp/work" };
    const line = try std.mem.join(context.allocator, " ", try argv(context, shared, "/programs/one.my"));
    try std.testing.expect(std.mem.startsWith(u8, line, "/usr/bin/mylang test /programs/one.my --json"));
    try std.testing.expect(std.mem.indexOf(u8, line, "--filter adder") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--max-steps 77") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--mode ReleaseFast") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--force") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--no-cache") != null);
    try std.testing.expectError(error.DirectoryCasesUnsupported, run(context, try options.parse(&.{ "suite", "--cases", "cases.json" })));
}
// spec: NATIVE-BENCH-6
test "a directory benchmark run is sequential and rejects aggregate artifacts" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const sequential = try options.parse(&.{ "suite", "--bench=*" });
    try std.testing.expectEqual(@as(usize, 1), width(context, sequential, 8));
    // Benchmarks are forwarded to each child, including identity and sampling.
    const shared: Fanout = .{ .compiler = "/usr/bin/mylang", .options = sequential, .workspace = "/tmp/work" };
    const line = try std.mem.join(context.allocator, " ", try argv(context, shared, "/programs/one.my"));
    try std.testing.expect(std.mem.indexOf(u8, line, "--bench *") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--bench-profile default") != null);
    // One aggregate report cannot serve a multi-program timing run.
    for ([_][]const []const u8{
        &.{ "suite", "--bench=*", "--bench-output", "out.json" },
        &.{ "suite", "--bench=*", "--bench-baseline", "base.json" },
        &.{ "suite", "--bench=*", "--bench-policy", "policy.json" },
    }) |args| {
        try std.testing.expectError(error.DirectoryBenchmarksUnsupported, run(context, try options.parse(args)));
    }
}

// spec-case: NATIVE-TEST-4
test "a directory run refuses unbounded fan-out and reports a child could not produce" {
    try bounded(program_limit - 1);
    try std.testing.expectError(error.TooManyTestPrograms, bounded(program_limit));
    try std.testing.expectError(error.UnusableTestReport, merged(.null));
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"version":"native-tests-v1","passed":2}
    , .{});
    defer parsed.deinit();
    try std.testing.expectEqual(@as(u64, 2), v.number(v.get(try merged(parsed.value), "passed")));
}
// spec: NATIVE-TEST-11
test "a directory summary counts and names every program whose child produced no report" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const totals = Totals{ .passed = 171, .cached = 0, .failed = 0, .skipped = 0, .setup = 3 };
    const line = try summaryText(context.allocator, 30, totals);
    try std.testing.expectEqualStrings("171 passed, 0 cached, 0 failed, 0 skipped, 3 dropped across 30 programs", line);
    const dropped = try droppedText(context.allocator, "tests/lang/callbacks.my", .{ .code = 2, .report = "" });
    try std.testing.expectEqualStrings("not run: tests/lang/callbacks.my (exit 2, no report)\n", dropped);
    const green = try summaryText(context.allocator, 2, .{ .passed = 227 });
    try std.testing.expectEqualStrings("227 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 2 programs", green);
}
