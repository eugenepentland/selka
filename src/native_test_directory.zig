//! Whole-directory native guest test runs fanned out across the machine's cores.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const build_options = @import("qbe_build_options.zig");
const invalidation = @import("invalidation.zig");
const budget = @import("memory_budget");
const snapshot = @import("native_test_snapshot.zig");
/// Directory discovery and child-report transport failures.
pub const Error = fs.Error || snapshot.Error || std.json.ParseError(std.json.Scanner) || std.Io.Dir.OpenError ||
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
/// The programs one directory run spawns, plus every source beneath the
/// directory that declares a test, which some child must load.
pub const Selection = struct { entries: []const []const u8, tested: []const []const u8 };
/// Every `.my` entry beneath `source`, in sorted path order, skipping the
/// generated directories a source tree carries alongside its programs. An entry
/// is a file that declares a top-level `main` — so a directory holding one
/// project is one program, not one per module — or a standalone `*_test.my`,
/// or a library that declares a test no other entry's import closure reaches.
/// Of several such libraries, one imported by another is left to its importer,
/// so no test runs twice.
pub fn programs(context: fs.Context, source: []const u8) Error!Selection {
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
    var tested: std.ArrayList([]const u8) = .empty;
    var libraries: std.ArrayList([]const u8) = .empty;
    for (found.items) |path| {
        const bytes = try entryBytes(context, path);
        const tests = declaresTests(bytes);
        if (tests) try tested.append(context.allocator, path);
        if (isTestFile(path) or snapshot.declaresMain(bytes)) {
            try bounded(entries.items.len);
            try entries.append(context.allocator, path);
        } else if (tests) try libraries.append(context.allocator, path);
    }
    var reached: std.StringHashMapUnmanaged(void) = .empty;
    for (entries.items) |entry| for (try snapshot.reach(context, entry)) |path| try reached.put(context.allocator, path, {});
    var orphans: std.ArrayList(Orphan) = .empty;
    for (libraries.items) |path| {
        if (!reached.contains(path)) try orphans.append(context.allocator, .{ .path = path, .closure = try snapshot.reach(context, path) });
    }
    for (orphans.items, 0..) |orphan, index| {
        if (importedByOther(orphans.items, index)) continue;
        try bounded(entries.items.len);
        try entries.append(context.allocator, orphan.path);
    }
    std.mem.sort([]const u8, entries.items, {}, before);
    return .{ .entries = entries.items, .tested = tested.items };
}
/// A library with tests that no program imports, and the sources it reaches.
const Orphan = struct { path: []const u8, closure: []const []const u8 };
/// Whether another unreached library imports this one, directly or not, so
/// running that library also runs this one's tests. Imports are acyclic, so
/// following importers always ends at a library nothing imports.
fn importedByOther(orphans: []const Orphan, index: usize) bool {
    for (orphans, 0..) |other, position| {
        if (position == index) continue;
        for (other.closure[1..]) |path| if (std.mem.eql(u8, path, orphans[index].path)) return true;
    }
    return false;
}
/// A standalone test entry follows the `*_test.my` convention.
fn isTestFile(path: []const u8) bool {
    return std.mem.endsWith(u8, std.fs.path.basename(path), "_test.my");
}
/// One candidate's bytes. An unreadable or oversized file reads as empty, so it
/// is neither an entry nor a test source.
fn entryBytes(context: fs.Context, path: []const u8) Error![]const u8 {
    return std.Io.Dir.cwd().readFileAlloc(context.io, path, context.allocator, .limited(entry_read_limit)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return "",
    };
}
/// Whether a source declares a function discovery would run: a `test_` name,
/// public or not, or the `@test` attribute.
fn declaresTests(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        var line = std.mem.trim(u8, raw, " \t\r");
        if (std.mem.eql(u8, line, "@test")) return true;
        if (std.mem.startsWith(u8, line, "public ")) line = std.mem.trimStart(u8, line["public ".len..], " \t");
        if (!std.mem.startsWith(u8, line, "def ")) continue;
        if (std.mem.startsWith(u8, std.mem.trimStart(u8, line["def ".len..], " \t"), "test_")) return true;
    }
    return false;
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
    const selection = try programs(context, opts.source);
    const paths = selection.entries;
    const cache = try context.absolute(opts.cache);
    try context.mkdir(cache);
    const workspace = try context.owned(cache);
    defer context.remove(workspace);
    const outcomes = try a.alloc(Outcome, paths.len);
    const workers = width(context, opts, paths.len);
    const shared: Fanout = .{ .compiler = compiler, .options = opts, .workspace = workspace, .jobs = childJobs(workers, paths.len) };
    var start: usize = 0;
    while (start < paths.len) : (start += workers) {
        try wave(context, shared, paths[start..@min(start + workers, paths.len)], outcomes[start..]);
    }
    return summarize(context, opts, selection, outcomes);
}
/// One child program's exit status and the report bytes it produced.
const Outcome = struct { code: u8, report: []const u8 };
/// Values shared by every child of a directory run. `jobs` is the test-process
/// width each child may use, so the run as a whole stays within `workers`.
const Fanout = struct { compiler: []const u8, options: options.Options, workspace: []const u8, jobs: usize = 1 };
/// Split the run's worker width between the programs running at once: many
/// programs get one test process each, and a lone program gets every worker.
fn childJobs(workers: usize, found: usize) usize {
    return @max(1, workers / @max(1, @min(found, workers)));
}
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
    // A nameless backend is the child's own QBE, so it is forwarded only when the
    // caller named one; `--release` already names its mode.
    if (opts.toolchain.qbe.len != 0) try list.appendSlice(a, &.{ "--qbe", opts.toolchain.qbe });
    try list.appendSlice(a, &.{ "--zig", opts.toolchain.zig });
    try list.appendSlice(a, if (build_options.release(opts.link_arguments)) &.{build_options.release_flag} else &.{ "--mode", opts.mode });
    try list.appendSlice(a, &.{ "--max-steps", try decimal(a, opts.limits.max_steps) });
    try list.appendSlice(a, &.{ "--max-frames", try decimal(a, opts.limits.max_frames) });
    try list.appendSlice(a, &.{ "--max-calls", try decimal(a, opts.limits.max_calls) });
    try list.appendSlice(a, &.{ "--timeout-ms", try decimal(a, opts.limits.timeout_ms) });
    // Resolved before the fan-out, so every child enforces the same ceiling and
    // keys its receipts on it rather than rediscovering the environment itself.
    try list.appendSlice(a, &.{ "--max-memory", try decimal(a, opts.limits.max_memory orelse budget.test_default) });
    try list.appendSlice(a, &.{ "--jobs", try decimal(a, shared.jobs) });
    if (opts.flags.force) try list.append(a, "--force");
    if (opts.flags.no_cache) try list.append(a, "--no-cache");
    // Each child derives its own program's affected selection against the same
    // reference, so a directory run narrows every project independently.
    if (opts.flags.affected) {
        try list.append(a, "--affected");
        if (opts.against) |reference| try list.appendSlice(a, &.{ "--against", reference });
    }
    if (opts.flags.gc_stress) try list.append(a, "--gc-stress");
    if (opts.determinism.seed) |seed| try list.appendSlice(a, &.{ "--seed", try decimal(a, seed) });
    const runs = opts.determinism.property_runs;
    if (runs != (options.Determinism{}).property_runs) try list.appendSlice(a, &.{ "--property-runs", try decimal(a, runs) });
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
/// programs whose child produced no usable report — the work the run did not do
/// — and `unloaded` the test-declaring sources no reporting child loaded.
const Totals = struct { passed: usize = 0, cached: usize = 0, failed: usize = 0, skipped: usize = 0, setup: usize = 0, unloaded: usize = 0 };
fn summarize(context: fs.Context, opts: options.Options, selection: Selection, outcomes: []const Outcome) Error!u8 {
    const a = context.allocator;
    const paths = selection.entries;
    var totals: Totals = .{};
    var rows: std.ArrayList(std.json.Value) = .empty;
    // Sources some child loaded, plus each dropped program, which its own
    // `not run` line already accounts for.
    var accounted: std.StringHashMapUnmanaged(void) = .empty;
    for (paths, outcomes) |path, outcome| {
        if (outcome.report.len == 0 or outcome.code == 2) {
            totals.setup += 1;
            try accounted.put(a, path, {});
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
        for (v.array(v.get(parsed, "modules"))) |module| try accounted.put(a, v.text(module), {});
    }
    // Discovery chose these programs so that every test-declaring source is
    // loaded by one of them. A source no child reports loading lost its tests,
    // so it is named and fails the run rather than vanishing from the counts.
    const unloaded = try unloadedSources(a, selection.tested, accounted);
    totals.unloaded = unloaded.len;
    for (unloaded) |path| try std.Io.File.stderr().writeStreamingAll(context.io, try unloadedText(a, path));
    try publish(context, opts.flags.output.json, paths.len, totals, rows.items);
    if (opts.flags.output.report) try reportWork(context, totals);
    // A benchmark run's children already fold their own correctness and
    // performance gates into one status, so the parent takes the most severe
    // child status instead of recomputing it from the test-case counts.
    if (opts.bench.pattern != null) return if (totals.unloaded != 0) 2 else worstCode(outcomes);
    if (totals.setup + totals.unloaded != 0) return 2;
    if (totals.failed != 0) return 1;
    return if (totals.passed + totals.cached != 0) 0 else 3;
}
/// The stderr line naming one program whose child never produced a report.
fn droppedText(allocator: std.mem.Allocator, path: []const u8, outcome: Outcome) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "not run: {s} (exit {d}, no report)\n", .{ path, outcome.code });
}
/// The test-declaring sources no reporting child loaded, in selection order.
fn unloadedSources(allocator: std.mem.Allocator, tested: []const []const u8, loaded: std.StringHashMapUnmanaged(void)) Error![]const []const u8 {
    var missing: std.ArrayList([]const u8) = .empty;
    for (tested) |path| if (!loaded.contains(path)) try missing.append(allocator, path);
    return missing.items;
}
/// The stderr line naming one test-declaring source no program loaded.
fn unloadedText(allocator: std.mem.Allocator, path: []const u8) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "not run: {s} (declares tests, but no program loaded it)\n", .{path});
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
        .unloaded = totals.unloaded,
    }, .{}) else try summaryText(a, count, totals);
    try out.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{text}));
}
/// The merged count line of one directory run, carrying the programs whose child
/// produced no report so the totals cannot hide work the run never did, and any
/// test-declaring source no program loaded.
fn summaryText(allocator: std.mem.Allocator, count: usize, totals: Totals) Error![]const u8 {
    const line = try std.fmt.allocPrint(allocator, "{d} passed, {d} cached, {d} failed, {d} skipped, {d} dropped across {d} programs", .{
        totals.passed, totals.cached, totals.failed, totals.skipped, totals.setup, count,
    });
    if (totals.unloaded == 0) return line;
    return std.fmt.allocPrint(allocator, "{s}, {d} test sources not loaded", .{ line, totals.unloaded });
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
    const selection = try programs(context, root);
    const found = selection.entries;
    try std.testing.expectEqual(@as(usize, 1), selection.tested.len);
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
    // `--release` reaches each child once, in place of the mode it already names.
    const release: Fanout = .{ .compiler = "/usr/bin/mylang", .options = try options.parse(&.{ "suite", "--release" }), .workspace = "/tmp/work" };
    const released = try std.mem.join(context.allocator, " ", try argv(context, release, "/programs/one.my"));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, released, "--release"));
    try std.testing.expect(std.mem.indexOf(u8, released, "--mode") == null);
}
// spec-case: NATIVE-TEST-PARALLEL-1
test "a directory run shares its worker width between the programs it runs at once" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    try std.testing.expectEqual(@as(usize, 12), childJobs(12, 1));
    try std.testing.expectEqual(@as(usize, 4), childJobs(12, 3));
    try std.testing.expectEqual(@as(usize, 1), childJobs(12, 106));
    try std.testing.expectEqual(@as(usize, 1), childJobs(1, 5));
    const shared: Fanout = .{ .compiler = "/usr/bin/mylang", .options = try options.parse(&.{"suite"}), .workspace = "/tmp/work", .jobs = childJobs(12, 3) };
    const line = try std.mem.join(context.allocator, " ", try argv(context, shared, "/programs/one.my"));
    try std.testing.expect(std.mem.indexOf(u8, line, "--jobs 4") != null);
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
// spec-case: NATIVE-TEST-14
test "a directory selects a test-declaring library only when no entry already loads it" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    const join = struct {
        fn path(c: fs.Context, base: []const u8, name: []const u8) ![]const u8 {
            return std.fs.path.join(c.allocator, &.{ base, name });
        }
    }.path;
    try context.write(try join(context, root, "first.my"), "module first\nimport helper\ndef main() -> int:\n    return 0\n");
    try context.write(try join(context, root, "helper.my"), "module helper\npublic def test_helper() -> bool:\n    return True\n");
    try context.write(try join(context, root, "inner.my"), "module inner\npublic def test_inner() -> bool:\n    return True\n");
    try context.write(try join(context, root, "outer.my"), "module outer\nimport inner\n\n@test\ndef checks_outer() -> bool:\n    return True\n");
    try context.write(try join(context, root, "plain.my"), "module plain\npublic def value() -> int:\n    return 1\n");
    const selection = try programs(context, root);
    try std.testing.expectEqual(@as(usize, 2), selection.entries.len);
    try std.testing.expectEqualStrings(try join(context, root, "first.my"), selection.entries[0]);
    try std.testing.expectEqualStrings(try join(context, root, "outer.my"), selection.entries[1]);
    try std.testing.expectEqual(@as(usize, 3), selection.tested.len);
    try std.testing.expect(declaresTests("def   test_private() -> bool:\n"));
    try std.testing.expect(!declaresTests("def tested() -> bool:\n    return test_value()\n"));
}
// spec: NATIVE-TEST-15
test "a directory run names and fails on every test-declaring source no child loaded" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var loaded: std.StringHashMapUnmanaged(void) = .empty;
    try loaded.put(context.allocator, "/suite/first.my", {});
    try loaded.put(context.allocator, "/suite/helper.my", {});
    const missing = try unloadedSources(context.allocator, &.{ "/suite/first.my", "/suite/orphan.my", "/suite/helper.my" }, loaded);
    try std.testing.expectEqual(@as(usize, 1), missing.len);
    try std.testing.expectEqualStrings("/suite/orphan.my", missing[0]);
    try std.testing.expectEqualStrings("not run: /suite/orphan.my (declares tests, but no program loaded it)\n", try unloadedText(context.allocator, missing[0]));
    const line = try summaryText(context.allocator, 2, .{ .passed = 3, .unloaded = 1 });
    try std.testing.expectEqualStrings("3 passed, 0 cached, 0 failed, 0 skipped, 0 dropped across 2 programs, 1 test sources not loaded", line);
}
