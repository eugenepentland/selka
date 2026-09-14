//! Whole-directory native guest test runs fanned out across the machine's cores.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const options = @import("native_test_options.zig");
const budget = @import("memory_budget");
/// Directory discovery and child-report transport failures.
pub const Error = fs.Error || std.json.ParseError(std.json.Scanner) || std.Io.Dir.OpenError ||
    std.Io.Dir.SelectiveWalker.Error || std.Io.File.OpenError ||
    error{ TooManyTestPrograms, UnusableTestReport, DirectoryCasesUnsupported };
/// Largest program count one directory run will fan out.
const program_limit = 4096;
const report_version = "native-tests-v1";
/// Whether the command's source argument names a directory of programs rather
/// than one project entry.
pub fn selected(context: fs.Context, source: []const u8) bool {
    const info = std.Io.Dir.cwd().statFile(context.io, source, .{}) catch return false;
    return info.kind == .directory;
}
/// Every `.my` program beneath `source`, in sorted path order, skipping the
/// generated directories a source tree carries alongside its programs.
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
        try bounded(found.items.len);
        try found.append(context.allocator, try std.fs.path.join(context.allocator, &.{ root, item.path }));
    }
    std.mem.sort([]const u8, found.items, {}, before);
    return found.items;
}
/// Workers one directory run may keep busy: `--jobs`/`MYLANG_JOBS` when asked
/// for, otherwise the cores the machine has, capped by how many per-child
/// ceilings its free memory holds. A cold fan-out on a loaded machine then
/// waits instead of pushing the whole machine into swap.
fn width(context: fs.Context, opts: options.Options, programs_found: usize) usize {
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
    return summarize(context, opts, paths.len, outcomes);
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
    try list.appendSlice(a, &.{ "--qbe", opts.qbe, "--zig", opts.zig, "--mode", opts.mode });
    try list.appendSlice(a, &.{ "--max-steps", try decimal(a, opts.limits.max_steps) });
    try list.appendSlice(a, &.{ "--max-frames", try decimal(a, opts.limits.max_frames) });
    try list.appendSlice(a, &.{ "--max-calls", try decimal(a, opts.limits.max_calls) });
    try list.appendSlice(a, &.{ "--timeout-ms", try decimal(a, opts.limits.timeout_ms) });
    // Resolved before the fan-out, so every child enforces the same ceiling and
    // keys its receipts on it rather than rediscovering the environment itself.
    try list.appendSlice(a, &.{ "--max-memory", try decimal(a, opts.limits.max_memory orelse budget.test_default) });
    if (opts.force) try list.append(a, "--force");
    try @import("native_link.zig").append(context, opts.link_arguments, &list, true);
    return list.items;
}
fn decimal(allocator: std.mem.Allocator, value: u64) Error![]const u8 {
    return std.fmt.allocPrint(allocator, "{d}", .{value});
}
/// Merged counts over every child report of one directory run.
const Totals = struct { passed: usize = 0, cached: usize = 0, failed: usize = 0, skipped: usize = 0, setup: usize = 0 };
fn summarize(context: fs.Context, opts: options.Options, count: usize, outcomes: []const Outcome) Error!u8 {
    const a = context.allocator;
    var totals: Totals = .{};
    var rows: std.ArrayList(std.json.Value) = .empty;
    for (outcomes) |outcome| {
        if (outcome.report.len == 0 or outcome.code == 2) {
            totals.setup += 1;
            continue;
        }
        const parsed = try merged((try std.json.parseFromSlice(std.json.Value, a, outcome.report, .{ .allocate = .alloc_always })).value);
        totals.passed += @intCast(v.number(v.get(parsed, "passed")));
        totals.cached += @intCast(v.number(v.get(parsed, "cached")));
        totals.failed += @intCast(v.number(v.get(parsed, "failed")));
        totals.skipped += @intCast(v.number(v.get(parsed, "skipped")));
        for (v.array(v.get(parsed, "tests"))) |row| try rows.append(a, row);
    }
    try publish(context, opts.json, count, totals, rows.items);
    if (totals.setup != 0) return 2;
    if (totals.failed != 0) return 1;
    return if (totals.passed + totals.cached != 0) 0 else 3;
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
    }, .{}) else try std.fmt.allocPrint(a, "{d} passed, {d} cached, {d} failed, {d} skipped across {d} programs", .{
        totals.passed, totals.cached, totals.failed, totals.skipped, count,
    });
    try out.writeStreamingAll(context.io, try std.fmt.allocPrint(a, "{s}\n", .{text}));
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
test "a directory selects every program beneath it in sorted order" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", context.allocator);
    try context.mkdir(try std.fs.path.join(context.allocator, &.{ root, "nested" }));
    try context.mkdir(try std.fs.path.join(context.allocator, &.{ root, ".zig-cache" }));
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "second.my" }), "module second\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "first.my" }), "module first\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "notes.txt" }), "prose");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "nested", "third.my" }), "module third\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, ".zig-cache", "stale.my" }), "module stale\n");
    const found = try programs(context, root);
    try std.testing.expectEqual(@as(usize, 3), found.len);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "first.my" }), found[0]);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "nested", "third.my" }), found[1]);
    try std.testing.expectEqualStrings(try std.fs.path.join(context.allocator, &.{ root, "second.my" }), found[2]);
    try std.testing.expect(selected(context, root));
    try std.testing.expect(!selected(context, found[0]));
}
// spec-case: NATIVE-TEST-4
test "each child command inherits the selection, budgets and tool choices of the run" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    const opts = try options.parse(&.{ "suite", "--filter", "adder", "--force", "--max-steps", "77", "--mode", "ReleaseFast" });
    const shared: Fanout = .{ .compiler = "/usr/bin/mylang", .options = opts, .workspace = "/tmp/work" };
    const line = try std.mem.join(context.allocator, " ", try argv(context, shared, "/programs/one.my"));
    try std.testing.expect(std.mem.startsWith(u8, line, "/usr/bin/mylang test /programs/one.my --json"));
    try std.testing.expect(std.mem.indexOf(u8, line, "--filter adder") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--max-steps 77") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--mode ReleaseFast") != null);
    try std.testing.expect(std.mem.indexOf(u8, line, "--force") != null);
    try std.testing.expectError(error.DirectoryCasesUnsupported, run(context, try options.parse(&.{ "suite", "--cases", "cases.json" })));
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
