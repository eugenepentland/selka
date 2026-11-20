//! Build a checked compilation with the new core and run it in a child process
//! (NEW-CORE-S5-UNITS-1).
//!
//! Unit tests execute guest programs the way a user does: `selka run`. The unit
//! test root compiles the front end as a file of its own module, so it cannot
//! import the core; it drives the `selka` executable the build names instead.
//! A compilation's sources (one file, or a project's modules and the files they
//! embed) are written once into a content-addressed directory under the suite
//! cache, so an unchanged program replays its last identical build. The run's
//! diagnostics come back as `diagnostic-v1` records: the build's own lines end at
//! the cache report, and a trap's record is turned back into the text the runtime
//! printed, machine record included, so a test sees what the old adapter showed.
const std = @import("std");
const budget = @import("memory_budget");
const language = @import("compiler.zig");
const project_compile = @import("project_compile.zig");
const trap_detail = @import("native_trap_detail.zig");
const wiring = @import("wiring/core_runner.zig");
const print_result_option = "--print-result";

/// Checking, host and child-process failures a guest execution can report.
/// `NewCoreBuildFailed` means `selka` refused or could not build a program the
/// front end accepted; its report is printed to the test's stderr.
pub const Error = project_compile.CheckError || std.process.RunError ||
    error{ UnreadableNativeResult, NewCoreBuildFailed, NativeHostFailed };

/// One native stack frame the runtime reported beneath a trap.
pub const Frame = struct { function: []const u8, path: []const u8, line: u64, column: u64 };

/// A native trap: the runtime code, the source position, the reported frames,
/// and the bounded detail the runtime captured at the failing operation.
pub const Trap = struct {
    code: []const u8,
    path: []const u8 = "",
    line: u64 = 0,
    column: u64 = 0,
    frames: []const Frame = &.{},
    detail: trap_detail.Detail = .{},
};

/// One native execution: the entry point's result, the trap that ended the run,
/// the guest's own streams and the process exit status. A successful run leaves
/// `trap.code` empty and `failed` false; a trapped one leaves `value` at zero.
/// The status is the program's own exit code — the entry `int` truncated to the
/// low 8 bits on a normal return, or the diagnostic status on a trap — so it no
/// longer distinguishes success from failure on its own; `failed` does.
pub const Run = struct {
    value: i64 = 0,
    trap: Trap = .{ .code = "" },
    stdout: []const u8 = "",
    stderr: []const u8 = "",
    status: u8 = 0,
    failed: bool = false,

    /// Whether the native runtime ended this program with a trap rather than a
    /// normal return. A nonzero status alone no longer implies a trap, because a
    /// program that returns a nonzero value exits with it.
    pub fn trapped(self: Run) bool {
        return self.failed;
    }
};

/// Execution budgets, grants and arguments, and the working directory for one run.
pub const Options = struct {
    max_steps: ?u64 = null,
    max_frames: ?u64 = null,
    /// Capability grants and the other `selka run` options (`--timeout=N`), then,
    /// after a `--`, the program's own arguments.
    arguments: []const []const u8 = &.{},
    directory: ?[]const u8 = null,
    /// The guest's environment, which `Environment` capabilities read; by default
    /// the guest sees only what the compiler needs.
    environment: ?*const std.process.Environ.Map = null,
    /// The guest's byte ceiling; the per-test default bounds every run.
    max_memory: ?u64 = null,
};

/// Build one checked compilation and run it once with the defaults: no step or
/// frame ceiling, the per-test byte ceiling. The argument is a single-file
/// (`compiler.Compilation`) or a project (`project_compile.Compilation`) compilation.
pub fn run(compilation: anytype) Error!Run {
    return runWithOptions(compilation, .{});
}

/// Build one checked compilation and run it once under explicit options.
pub fn runWithOptions(compilation: anytype, options: Options) Error!Run {
    try compilation.check();
    const session = try wiring.acquire();
    const a = session.allocator();
    const sources = if (@TypeOf(compilation.*) == project_compile.Compilation) try projectSources(a, compilation.index.project.modules.items) else try singleSource(a, compilation.src);
    return execute(session, try write(session, sources), options);
}

/// What a failed expectation of `Cases.check` or `expectEndedCleanly` returns, beside
/// the errors of the runs themselves.
pub const CheckError = Error || error{ TestUnexpectedResult, TestExpectedEqual };

/// One run of a batch (`runAll`): a single-file compilation and the run's options.
pub const Job = struct { compilation: *language.Compilation, options: Options = .{}, harness_steps: bool = false };

/// Build and run every job's program, `wiring.lanes()` at a time, and return the
/// runs in job order (NEW-CORE-S5-UNITS-BATCH-1). Each compilation is checked and its
/// sources written first, in job order, so a front-end error stops the batch before
/// any program runs; the first job that fails afterwards decides the error.
pub fn runAll(jobs: []const Job) Error![]Run {
    const session = try wiring.acquire();
    const a = session.allocator();
    const trees = try a.alloc(Tree, jobs.len);
    for (jobs, trees, 0..) |job, *tree, index| {
        // A job that reruns an earlier job's compilation (another budget) shares its tree.
        tree.* = for (jobs[0..index], trees[0..index]) |earlier, written| {
            if (earlier.compilation == job.compilation) break written;
        } else fresh: {
            try job.compilation.check();
            break :fresh try write(session, try singleSource(a, job.compilation.src));
        };
    }
    const programs = try a.alloc(?[]const u8, jobs.len);
    for (jobs, trees, programs, 0..) |job, tree, *program, index| {
        program.* = null;
        if (!job.harness_steps) continue;
        if (!harnessBudget(job.options)) return error.NativeHostFailed;
        program.* = for (jobs[0..index], programs[0..index]) |earlier, built| {
            if (earlier.compilation == job.compilation and earlier.harness_steps) break built;
        } else try buildExecutable(session, tree, true);
    }
    var queue: Queue = .{ .session = session, .jobs = jobs, .trees = trees, .programs = programs, .results = try a.alloc(Error!Run, jobs.len) };
    const helpers = try a.alloc(std.Thread, @min(wiring.lanes(), jobs.len) -| 1);
    var started: usize = 0;
    for (helpers) |*helper| {
        helper.* = std.Thread.spawn(.{}, Queue.drain, .{&queue}) catch break;
        started += 1;
    }
    queue.drain();
    for (helpers[0..started]) |helper| helper.join();
    const runs = try a.alloc(Run, jobs.len);
    for (queue.results, runs) |result, *outcome| outcome.* = try result;
    return runs;
}

/// The jobs of one `runAll`, taken in order by however many threads drain it.
const Queue = struct {
    session: *wiring.Session,
    jobs: []const Job,
    trees: []const Tree,
    programs: []const ?[]const u8,
    results: []Error!Run,
    next: std.atomic.Value(usize) = .init(0),

    fn drain(self: *Queue) void {
        while (true) {
            const at = self.next.fetchAdd(1, .monotonic);
            if (at >= self.jobs.len) return;
            self.results[at] = if (self.programs[at]) |program| executeBuilt(self.session, self.trees[at], program, self.jobs[at].options) else execute(self.session, self.trees[at], self.jobs[at].options);
        }
    }
};

/// Single-file programs a test collects and then runs as one batch (`runAll`). The
/// batch owns each program's source and compilation until `deinit`.
pub const Batch = struct {
    allocator: std.mem.Allocator,
    sources: std.ArrayList([]const u8) = .empty,
    compilations: std.ArrayList(*language.Compilation) = .empty,
    jobs: std.ArrayList(Job) = .empty,

    /// An empty batch whose programs live in `allocator`.
    pub fn init(allocator: std.mem.Allocator) Batch {
        return .{ .allocator = allocator };
    }

    /// Add the program `source`, named `path`, and one run of it under `options`.
    pub fn add(self: *Batch, path: []const u8, source: []const u8, options: Options) std.mem.Allocator.Error!void {
        const owned = try self.allocator.dupe(u8, source);
        errdefer self.allocator.free(owned);
        try self.sources.ensureUnusedCapacity(self.allocator, 1);
        try self.compilations.ensureUnusedCapacity(self.allocator, 1);
        const compilation = try self.allocator.create(language.Compilation);
        errdefer self.allocator.destroy(compilation);
        compilation.* = try language.Compilation.init(self.allocator, path, owned);
        self.sources.appendAssumeCapacity(owned);
        self.compilations.appendAssumeCapacity(compilation);
        try self.again(self.compilations.items.len - 1, options);
    }

    /// One more run, under `options`, of the batch's `program`-th program (in `add` order).
    pub fn again(self: *Batch, program: usize, options: Options) std.mem.Allocator.Error!void {
        try self.jobs.append(self.allocator, .{ .compilation = self.compilations.items[program], .options = options });
    }

    /// Collect one harness executable: unbounded, then steps 1 through `end - 1`.
    /// Two compiled-in endpoint runs follow, checked by `expectBudgetSweep`.
    /// Other build controls stay on the ordinary `add`/`again` path.
    pub fn budgetSweep(self: *Batch, path: []const u8, source: []const u8, options: Options, end: u64) Error!void {
        if (end <= 1 or options.max_steps != null or !harnessBudget(options)) return error.NativeHostFailed;
        try self.add(path, source, options);
        const program = self.compilations.items.len - 1;
        self.jobs.items[self.jobs.items.len - 1].harness_steps = true;
        var limited = options;
        for (1..end) |steps| {
            limited.max_steps = steps;
            try self.again(program, limited);
            self.jobs.items[self.jobs.items.len - 1].harness_steps = true;
        }
        limited.max_steps = 1;
        try self.again(program, limited);
        limited.max_steps = end - 1;
        try self.again(program, limited);
    }

    /// Build and run every job, returning the runs in job order.
    pub fn run(self: *Batch) Error![]Run {
        return runAll(self.jobs.items);
    }

    /// Release every program and the batch's lists.
    pub fn deinit(self: *Batch) void {
        for (self.compilations.items) |compilation| {
            compilation.deinit();
            self.allocator.destroy(compilation);
        }
        for (self.sources.items) |source| self.allocator.free(source);
        self.sources.deinit(self.allocator);
        self.compilations.deinit(self.allocator);
        self.jobs.deinit(self.allocator);
    }
};

/// The step-only harness keeps the unit suite's existing byte ceiling; callers
/// requiring frame accounting or another byte limit must use ordinary runs.
fn harnessBudget(options: Options) bool {
    return options.max_frames == null and (options.max_memory == null or options.max_memory == budget.test_default);
}

// spec-case: NATIVE-ARGV-1
test "harness budget sweeps reject unsupported ceilings before building" {
    var batch: Batch = .init(std.testing.allocator);
    defer batch.deinit();
    const source = "func main() -> i64:\n    return 0\n";
    try std.testing.expectError(error.NativeHostFailed, batch.budgetSweep("limits.selka", source, .{ .max_frames = 2 }, 4));
    try std.testing.expectError(error.NativeHostFailed, batch.budgetSweep("limits.selka", source, .{ .max_memory = 0 }, 4));
    try std.testing.expectError(error.NativeHostFailed, batch.budgetSweep("limits.selka", source, .{ .max_steps = 1 }, 4));
    try std.testing.expectError(error.NativeHostFailed, batch.budgetSweep("limits.selka", source, .{}, 1));
    try std.testing.expectEqual(@as(usize, 0), batch.jobs.items.len);
}

/// Programs a test collects with what each must do, return a value or trap with a
/// code (on a given line, when one is named), then runs as one batch (`check`).
pub const Cases = struct {
    batch: Batch,
    expected: std.ArrayList(Expected) = .empty,

    /// What one program must do; `stdout`, when named, is all it prints and is owned.
    pub const Expected = struct { value: i64 = 0, trap: ?[]const u8 = null, line: ?u64 = null, stdout: ?[]const u8 = null };

    /// No cases yet; programs live in `allocator`.
    pub fn init(allocator: std.mem.Allocator) Cases {
        return .{ .batch = .init(allocator) };
    }

    /// The program `source`, named `path`, returns `value`.
    pub fn returns(self: *Cases, path: []const u8, source: []const u8, value: i64) std.mem.Allocator.Error!void {
        try self.expect(path, source, .{ .value = value });
    }

    /// The program `source`, named `path`, traps with `code`, on `line` when one is given.
    pub fn traps(self: *Cases, path: []const u8, source: []const u8, code: []const u8, line: ?u64) std.mem.Allocator.Error!void {
        try self.expect(path, source, .{ .trap = code, .line = line });
    }

    /// The program `source`, named `path`, returns normally having printed exactly `stdout`.
    pub fn prints(self: *Cases, path: []const u8, source: []const u8, stdout: []const u8) std.mem.Allocator.Error!void {
        const owned = try self.batch.allocator.dupe(u8, stdout);
        errdefer self.batch.allocator.free(owned);
        try self.expect(path, source, .{ .stdout = owned });
    }

    fn expect(self: *Cases, path: []const u8, source: []const u8, expected: Expected) std.mem.Allocator.Error!void {
        try self.expected.ensureUnusedCapacity(self.batch.allocator, 1);
        try self.batch.add(path, source, .{});
        self.expected.appendAssumeCapacity(expected);
    }

    /// Run every program as one batch and compare each with what it must do; a
    /// mismatch prints the program's source.
    pub fn check(self: *Cases) CheckError!void {
        const runs = try self.batch.run();
        for (self.expected.items, runs, self.batch.sources.items) |expected, outcome, source| {
            errdefer report("native_execute: this program did not do what its case expects:\n{s}\n", .{source});
            const code = expected.trap orelse {
                try std.testing.expect(!outcome.trapped());
                const printed = expected.stdout orelse {
                    try std.testing.expectEqual(expected.value, outcome.value);
                    continue;
                };
                try std.testing.expectEqualStrings(printed, outcome.stdout);
                continue;
            };
            try std.testing.expectEqualStrings(code, outcome.trap.code);
            if (expected.line) |line| try std.testing.expectEqual(line, outcome.trap.line);
        }
    }

    /// Release every program and expectation.
    pub fn deinit(self: *Cases) void {
        for (self.expected.items) |expected| if (expected.stdout) |printed| self.batch.allocator.free(printed);
        self.expected.deinit(self.batch.allocator);
        self.batch.deinit();
    }
};

/// Every run returned or trapped with a runtime `R_*` code: none ended any other way,
/// as an owner released twice would abort the process.
pub fn expectEndedCleanly(runs: []const Run) CheckError!void {
    for (runs) |outcome| try std.testing.expect(!outcome.trapped() or std.mem.startsWith(u8, outcome.trap.code, "R_"));
}

/// A sweep's first and last limits agree byte-for-byte with ordinary compiled-in
/// runs; every trial either returned or reported a runtime trap, never a host crash.
pub fn expectBudgetSweep(runs: []const Run) CheckError!void {
    try std.testing.expect(runs.len >= 4);
    try expectEndedCleanly(runs);
    try expectSameRun(runs[1], runs[runs.len - 2]);
    try expectSameRun(runs[runs.len - 3], runs[runs.len - 1]);
}

fn expectSameRun(actual: Run, expected: Run) CheckError!void {
    try std.testing.expectEqual(expected.value, actual.value);
    try std.testing.expectEqual(expected.status, actual.status);
    try std.testing.expectEqual(expected.failed, actual.failed);
    try std.testing.expectEqualStrings(expected.stdout, actual.stdout);
    try std.testing.expectEqualStrings(expected.stderr, actual.stderr);
    try std.testing.expectEqualDeep(expected.trap, actual.trap);
}

/// Build one checked single-file compilation into an executable with `selka build`
/// and return its path; an identical earlier build is reused. The program grants
/// itself nothing beyond what a built executable grants.
pub fn executable(compilation: *language.Compilation) Error![]const u8 {
    try compilation.check();
    const session = try wiring.acquire();
    const a = session.allocator();
    const tree = try write(session, try singleSource(a, compilation.src));
    return buildExecutable(session, tree, false);
}

fn buildExecutable(session: *wiring.Session, tree: Tree, harness_steps: bool) Error![]const u8 {
    const a = session.allocator();
    const directory = try std.fs.path.join(a, &.{ session.cache, if (harness_steps) "step-exe" else "exe" });
    std.Io.Dir.cwd().createDirPath(session.io, directory) catch |err| return host(err);
    const output = try std.fs.path.join(a, &.{ directory, tree.identity });
    var arguments: std.ArrayList([]const u8) = .empty;
    try arguments.appendSlice(a, &.{ session.compiler, "build", tree.entry, "-o", output, try flag(a, "--zig=", session.zig), try flag(a, cache_option, try buildCache(session, tree)), "--diagnostics=json" });
    if (harness_steps) try arguments.append(a, "--test-step-budget");
    const argv = arguments.items;
    const outcome = std.process.run(a, session.io, .{ .argv = argv, .environ_map = try session.environment(null), .stdout_limit = .limited(1 << 20), .stderr_limit = .limited(4 << 20) }) catch |err| return host(err);
    if (outcome.term != .exited or outcome.term.exited != 0) return refused(argv, outcome.stderr);
    return output;
}

/// `selka`'s cache option, spelled with its value.
const cache_option = "--cache-dir=";

/// The new core's build cache for one compilation, inside the suite cache. A compilation has a
/// directory of its own, named by the identity of its files, because the build's stage stores
/// index every record they hold when a process opens them: in one shared directory each of the
/// suite's thousands of distinct programs would add records every later run reads and none
/// reuses, and the cost of a run grew with the programs before it. An unchanged program finds
/// the same directory and replays its last identical build, as it did in the shared one.
fn buildCache(session: *wiring.Session, tree: Tree) Error![]const u8 {
    return std.fs.path.join(session.allocator(), &.{ session.cache, "build", tree.identity });
}

// spec: NATIVE-EXECUTE-CACHE-1
test "each compilation builds in a cache directory named by the identity of its files" {
    var one = try language.Compilation.init(std.testing.allocator, "cache_one.selka", "func main() -> i64:\n    return 11\n");
    defer one.deinit();
    var two = try language.Compilation.init(std.testing.allocator, "cache_two.selka", "func main() -> i64:\n    return 12\n");
    defer two.deinit();
    try std.testing.expectEqual(@as(i64, 11), (try run(&one)).value);
    try std.testing.expectEqual(@as(i64, 12), (try run(&two)).value);
    const session = try wiring.acquire();
    const a = session.allocator();
    const first = try buildCache(session, try write(session, try singleSource(a, one.src)));
    const second = try buildCache(session, try write(session, try singleSource(a, two.src)));
    try std.testing.expect(!std.mem.eql(u8, first, second));
    try std.testing.expect(std.mem.startsWith(u8, first, session.cache));
    try std.Io.Dir.cwd().access(session.io, first, .{});
    try std.Io.Dir.cwd().access(session.io, second, .{});
    // The same files find the same directory, so an unchanged program replays its last build.
    try std.testing.expectEqualStrings(first, try buildCache(session, try write(session, try singleSource(a, one.src))));
}

fn flag(a: std.mem.Allocator, comptime name: []const u8, value: []const u8) Error![]const u8 {
    return std.mem.concat(a, u8, &.{ name, value });
}

/// Failure detail goes to the test's stderr.
const report = std.debug.print;

fn host(err: anyerror) Error {
    report("native_execute: host failure: {s}\n", .{@errorName(err)});
    return error.NativeHostFailed;
}

fn refused(argv: []const []const u8, text: []const u8) Error {
    report("native_execute: `selka {s}` refused a program the front end accepted:\n{s}\n", .{ argv[1], text });
    return error.NewCoreBuildFailed;
}

/// One source file of a compilation, at its path relative to the project root.
const File = struct { path: []const u8, bytes: []const u8 };

/// A compilation's files and the one `selka` is given.
const Sources = struct { entry: []const u8, files: []const File };

/// A compilation written out: its entry file, the prefix its diagnostics carry
/// that the compilation's own paths do not, and the content identity of its files.
const Tree = struct { entry: []const u8, prefix: []const u8, identity: []const u8 };

fn singleSource(a: std.mem.Allocator, src: language.source.Source) Error!Sources {
    var files: std.ArrayList(File) = .empty;
    try collect(a, &files, src);
    return .{ .entry = src.path, .files = files.items };
}

/// A project's own modules (the first is its entry); standard modules are the core's.
fn projectSources(a: std.mem.Allocator, modules: []const language.project.Module) Error!Sources {
    var files: std.ArrayList(File) = .empty;
    for (modules) |module| {
        if (std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        try collect(a, &files, module.src);
    }
    return .{ .entry = modules[0].src.path, .files = files.items };
}

/// Add one module's source, and every file it embeds, relative to its directory. A
/// path that leaves the directory it is written under cannot be written.
fn collect(a: std.mem.Allocator, files: *std.ArrayList(File), src: language.source.Source) Error!void {
    const relative = std.mem.trimStart(u8, src.path, "/");
    try files.append(a, .{ .path = relative, .bytes = src.bytes });
    const directory = std.fs.path.dirname(relative) orelse "";
    for (src.embeds) |embedded| {
        if (embedded.status != .ok) continue;
        try files.append(a, .{ .path = try std.fs.path.join(a, &.{ directory, embedded.path }), .bytes = embedded.contents });
    }
    for (files.items) |file| {
        var parts = std.mem.splitScalar(u8, file.path, '/');
        while (parts.next()) |part| if (std.mem.eql(u8, part, "..")) return host(error.PathLeavesTree);
    }
}

/// Write `sources` under `cache/src/IDENTITY`, unless an earlier run already did.
fn write(session: *wiring.Session, sources: Sources) Error!Tree {
    const a = session.allocator();
    var hash = std.crypto.hash.Blake3.init(.{});
    for (sources.files) |file| {
        hash.update(file.path);
        hash.update(&.{0});
        hash.update(std.mem.asBytes(&file.bytes.len));
        hash.update(file.bytes);
    }
    var digest: [16]u8 = undefined;
    hash.final(&digest);
    const identity = try a.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
    const root = try std.fs.path.join(a, &.{ session.cache, "src", identity });
    const absolute = std.fs.path.isAbsolute(sources.entry);
    const tree: Tree = .{
        .entry = try std.mem.concat(a, u8, &.{ root, if (absolute) "" else "/", sources.entry }),
        .prefix = if (absolute) root else try std.mem.concat(a, u8, &.{ root, "/" }),
        .identity = identity,
    };
    const cwd = std.Io.Dir.cwd();
    if (cwd.access(session.io, tree.entry, .{})) |_| return tree else |_| {}
    // Stage the files beside the tree and rename it into place, so a concurrent
    // shard never sees half a tree; the loser of a race discards its copy.
    session.staged += 1;
    const staging = try std.fmt.allocPrint(a, "{s}/src/.staging-{d}-{d}", .{ session.cache, std.os.linux.getpid(), session.staged });
    for (sources.files) |file| {
        const path = try std.fs.path.join(a, &.{ staging, file.path });
        if (std.fs.path.dirname(path)) |parent| cwd.createDirPath(session.io, parent) catch |err| return host(err);
        cwd.writeFile(session.io, .{ .sub_path = path, .data = file.bytes }) catch |err| return host(err);
    }
    cwd.rename(staging, cwd, root, session.io) catch {
        cwd.deleteTree(session.io, staging) catch |err| return host(err);
        cwd.access(session.io, tree.entry, .{}) catch |err| return host(err);
    };
    return tree;
}

/// The record line `--cache-report` adds after a build, which ends the build's output.
const cache_line = "{\"version\":\"diagnostic-v1\",\"kind\":\"message\",\"message\":\"selka-core: cache: ";

fn execute(session: *wiring.Session, tree: Tree, options: Options) Error!Run {
    const a = session.allocator();
    const tail = split(options.arguments);
    var argv: std.ArrayList([]const u8) = .empty;
    try argv.appendSlice(a, &.{ session.compiler, "run", tree.entry, try flag(a, "--zig=", session.zig), try flag(a, cache_option, try buildCache(session, tree)), "--diagnostics=json", "--cache-report" });
    if (!contains(tail.options, print_result_option)) try argv.append(a, print_result_option);
    try argv.append(a, try std.fmt.allocPrint(a, "--max-memory={d}", .{options.max_memory orelse budget.test_default}));
    if (options.max_steps) |steps| try argv.append(a, try std.fmt.allocPrint(a, "--max-steps={d}", .{steps}));
    if (options.max_frames) |frames| try argv.append(a, try std.fmt.allocPrint(a, "--max-frames={d}", .{frames}));
    try argv.appendSlice(a, tail.options);
    try argv.append(a, "--");
    try argv.appendSlice(a, tail.program);
    const outcome = try std.process.run(a, session.io, .{
        .argv = argv.items,
        .cwd = if (options.directory) |directory| .{ .path = directory } else .inherit,
        .environ_map = try session.environment(options.environment),
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    });
    const program = afterBuild(outcome.stderr) orelse return refused(argv.items, outcome.stderr);
    const stderr = try std.mem.replaceOwned(u8, a, try restore(a, program), tree.prefix, "");
    const status: u8 = switch (outcome.term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
    return adopt(a, outcome, stderr, status);
}

/// Execute an already instrumented sweep binary in a fresh process. The runtime
/// ceiling is private to this child; its argv and capability options are unchanged.
fn executeBuilt(session: *wiring.Session, tree: Tree, program: []const u8, options: Options) Error!Run {
    const a = session.allocator();
    const tail = split(options.arguments);
    const environment = try session.environment(options.environment);
    try environment.put("SELKA_TEST_MAX_STEPS", try std.fmt.allocPrint(a, "{d}", .{options.max_steps orelse 0}));
    var encoded: std.ArrayList(u8) = .empty;
    try encoded.appendSlice(a, print_result_option);
    for (tail.options) |item| {
        if (std.mem.eql(u8, item, print_result_option)) continue;
        try encoded.appendSlice(a, " \"");
        for (item) |byte| {
            if (byte == '"' or byte == '\\') try encoded.append(a, '\\');
            try encoded.append(a, byte);
        }
        try encoded.append(a, '"');
    }
    try environment.put("SELKA_OPTIONS", encoded.items);
    const argv = try std.mem.concat(a, []const u8, &.{ &.{program}, tail.program });
    const outcome = try std.process.run(a, session.io, .{
        .argv = argv,
        .cwd = if (options.directory) |directory| .{ .path = directory } else .inherit,
        .environ_map = environment,
        .stdout_limit = .limited(64 * 1024 * 1024),
        .stderr_limit = .limited(4 * 1024 * 1024),
    });
    const stderr = try std.mem.replaceOwned(u8, a, try restoreBudget(a, outcome.stderr), tree.prefix, "");
    const status: u8 = switch (outcome.term) {
        .exited => |code| code,
        .signal => |signal| @intCast(@min(255, 128 + @as(u32, @backingInt(signal)))),
        else => 2,
    };
    return adopt(a, outcome, stderr, status);
}

/// Preserve the adapter's established two-line rendering of an unlocated budget
/// diagnostic, even when this child bypasses the CLI's diagnostic-v1 translation.
fn restoreBudget(a: std.mem.Allocator, text: []const u8) Error![]const u8 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var start: usize = 0;
    while (lines.next()) |line| {
        defer start += line.len + 1;
        if (!std.mem.startsWith(u8, line, "error[")) continue;
        const close = std.mem.indexOf(u8, line, "]: ") orelse continue;
        const message = start + close + 3;
        return std.mem.concat(a, u8, &.{ text[0..message], "native execution failed\n", text[message..] });
    }
    return text;
}

/// Read the run the way the old adapter did: a clean return leaves stderr empty and
/// appends its `--print-result` line to stdout; a trap writes its text to stderr.
fn adopt(a: std.mem.Allocator, outcome: std.process.RunResult, stderr: []const u8, status: u8) Error!Run {
    if (outcome.term != .exited or stderr.len != 0) {
        const trap = parse(a, stderr) catch Trap{ .code = "" };
        // The machine record is transport, not a diagnostic: keep `stderr` as the
        // human text the caller saw before structured traps existed.
        const cleaned = trap_detail.strip(a, stderr) catch stderr;
        // ERROR-TRACE-2: a `main` that returned an `Err` reported it on stderr
        // and still returned, so its result line follows its output.
        const returned_err = std.mem.startsWith(u8, stderr, "error: ") and std.mem.indexOf(u8, stderr, diagnostic_marker) == null;
        if (outcome.term == .exited and returned_err) {
            if (divide(outcome.stdout)) |reported| return .{ .value = reported.value, .stdout = reported.output, .stderr = cleaned, .status = status } else |_| {}
        }
        if (trap.code.len != 0 or outcome.term != .exited) return .{ .trap = trap, .stdout = outcome.stdout, .stderr = cleaned, .status = status, .failed = true };
        // A program that wrote to stderr and returned normally is not a trap.
        if (divide(outcome.stdout)) |reported| return .{ .value = reported.value, .stdout = reported.output, .stderr = cleaned, .status = status } else |_| {}
        return .{ .trap = trap, .stdout = outcome.stdout, .stderr = cleaned, .status = status, .failed = true };
    }
    const reported = try divide(outcome.stdout);
    return .{ .value = reported.value, .stdout = reported.output, .stderr = stderr, .status = status };
}

/// The program's standard error: what follows the build's cache report, or null
/// when the build stopped before it (a refusal or a usage error).
fn afterBuild(stderr: []const u8) ?[]const u8 {
    var start: usize = 0;
    while (start < stderr.len) {
        const end = if (std.mem.indexOfScalarPos(u8, stderr, start, '\n')) |index| index + 1 else stderr.len;
        if (std.mem.startsWith(u8, stderr[start..end], cache_line)) return stderr[end..];
        start = end;
    }
    return null;
}

/// The runtime's own text for a program's standard error, from `--diagnostics=json`:
/// the trap record, the last line when there is one, becomes the located line, the
/// `in` frames and the machine record the runtime printed.
fn restore(a: std.mem.Allocator, text: []const u8) Error![]const u8 {
    const body = std.mem.trimEnd(u8, text, "\n");
    const start = if (std.mem.lastIndexOfScalar(u8, body, '\n')) |index| index + 1 else 0;
    const last = body[start..];
    if (!std.mem.startsWith(u8, last, "{\"version\":\"diagnostic-v1\",\"kind\":\"diagnostic\"")) return text;
    const parsed = std.json.parseFromSliceLeaky(std.json.Value, a, last, .{}) catch return text;
    const diagnostic = field(parsed, "diagnostic") orelse return text;
    const code = string(field(diagnostic, "code")) orelse return text;
    const message = string(field(diagnostic, "message")) orelse "";
    var out: std.Io.Writer.Allocating = .init(a);
    const w = &out.writer;
    w.writeAll(text[0..start]) catch return error.OutOfMemory;
    const location = field(diagnostic, "location");
    const path = string(field(location orelse .null, "path")) orelse "";
    if (path.len == 0) {
        // A budget trap has no location; its advice line was the record's message.
        w.print("error[{s}]: native execution failed\n{s}\n", .{ code, message }) catch return error.OutOfMemory;
    } else {
        const at = startOf(location.?);
        w.print("{s}:{d}:{d}: error[{s}]: {s}\n", .{ path, at.line, at.column, code, message }) catch return error.OutOfMemory;
    }
    const stack = field(diagnostic, "stack") orelse .null;
    if (field(stack, "frames")) |frames| if (frames == .array) for (frames.array.items) |frame| {
        const where = field(frame, "location") orelse continue;
        const at = startOf(where);
        w.print("  in {s} at {s}:{d}:{d}\n", .{ string(field(frame, "function")) orelse "", string(field(where, "path")) orelse "", at.line, at.column }) catch return error.OutOfMemory;
    };
    if (field(diagnostic, "trap_detail")) |detail| {
        const record = std.json.Stringify.valueAlloc(a, detail, .{}) catch return error.OutOfMemory;
        w.print("{s}{s}\n", .{ trap_detail.marker, record }) catch return error.OutOfMemory;
    }
    return out.written();
}

fn field(value: std.json.Value, name: []const u8) ?std.json.Value {
    if (value != .object) return null;
    return value.object.get(name);
}

fn string(value: ?std.json.Value) ?[]const u8 {
    const present = value orelse return null;
    return if (present == .string) present.string else null;
}

fn startOf(location: std.json.Value) struct { line: i64, column: i64 } {
    const start = field(location, "start") orelse return .{ .line = 0, .column = 0 };
    const line = field(start, "line") orelse std.json.Value{ .integer = 0 };
    const column = field(start, "column") orelse std.json.Value{ .integer = 0 };
    return .{ .line = if (line == .integer) line.integer else 0, .column = if (column == .integer) column.integer else 0 };
}

/// The options before a `--` and the program's arguments after it; with no `--`,
/// every value is an option.
fn split(arguments: []const []const u8) struct { options: []const []const u8, program: []const []const u8 } {
    for (arguments, 0..) |argument, index| {
        if (std.mem.eql(u8, argument, "--")) return .{ .options = arguments[0..index], .program = arguments[index + 1 ..] };
    }
    return .{ .options = arguments, .program = &.{} };
}

fn contains(items: []const []const u8, wanted: []const u8) bool {
    for (items) |item| if (std.mem.eql(u8, item, wanted)) return true;
    return false;
}

/// Separate the guest's own output from the entry result line `--print-result` appends.
fn divide(text: []const u8) Error!struct { output: []const u8, value: i64 } {
    if (text.len == 0 or text[text.len - 1] != '\n') return error.UnreadableNativeResult;
    const body = text[0 .. text.len - 1];
    const start = if (std.mem.lastIndexOfScalar(u8, body, '\n')) |index| index + 1 else 0;
    const value = std.fmt.parseInt(i64, body[start..], 10) catch return error.UnreadableNativeResult;
    return .{ .output = text[0..start], .value = value };
}

/// Recover the trap code, its source position and the reported frames from stderr.
fn parse(allocator: std.mem.Allocator, text: []const u8) Error!Trap {
    const detail = trap_detail.parse(allocator, text) orelse trap_detail.Detail{};
    var frames: std.ArrayList(Frame) = .empty;
    var diagnostic: []const u8 = "";
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.startsWith(u8, line, "  in ")) {
            const split_at = std.mem.lastIndexOf(u8, line, " at ") orelse continue;
            const place = position(line[split_at + 4 ..]) orelse continue;
            try frames.append(allocator, .{ .function = line[5..split_at], .path = place.path, .line = place.line, .column = place.column });
            continue;
        }
        // A failure-path assert message may precede the located diagnostic on
        // stderr, so find the diagnostic line instead of taking the first one.
        if (diagnostic.len == 0 and (std.mem.indexOf(u8, line, diagnostic_marker) != null or std.mem.startsWith(u8, line, budget_marker) or std.mem.startsWith(u8, line, "selka: --restrict is active"))) diagnostic = line;
    }
    const first = if (diagnostic.len == 0) std.mem.sliceTo(text, '\n') else diagnostic;
    if (std.mem.startsWith(u8, first, "selka: --restrict is active")) return .{ .code = "CapabilityUnavailable", .frames = frames.items, .detail = detail };
    if (std.mem.startsWith(u8, first, budget_marker)) {
        const close = std.mem.indexOfScalar(u8, first, ']') orelse return error.UnreadableNativeResult;
        return .{ .code = first[budget_marker.len..close], .frames = frames.items, .detail = detail };
    }
    if (std.mem.indexOf(u8, first, diagnostic_marker)) |marker| {
        const rest = first[marker + diagnostic_marker.len ..];
        const close = std.mem.indexOfScalar(u8, rest, ']') orelse return error.UnreadableNativeResult;
        const place = position(first[0..marker]) orelse return error.UnreadableNativeResult;
        return .{ .code = rest[0..close], .path = place.path, .line = place.line, .column = place.column, .frames = frames.items, .detail = detail };
    }
    // A budget without a location (`R_TIMEOUT: ...`) names its code before a colon.
    const colon = std.mem.indexOfScalar(u8, first, ':') orelse 0;
    return .{ .code = if (isCode(first[0..colon])) first[0..colon] else "", .frames = frames.items, .detail = detail };
}

/// Whether `text` spells a runtime code: upper-case letters, digits and underscores.
fn isCode(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |byte| {
        const allowed = std.ascii.isUpper(byte) or std.ascii.isDigit(byte) or byte == '_';
        if (!allowed) return false;
    }
    return true;
}

/// What separates a located diagnostic's position from its bracketed code.
const diagnostic_marker = ": error[";
/// How a trap without a location (a budget) begins.
const budget_marker = "error[";

/// Split a trailing `path:line:column` locator, which paths may themselves contain colons.
fn position(text: []const u8) ?struct { path: []const u8, line: u64, column: u64 } {
    const last = std.mem.lastIndexOfScalar(u8, text, ':') orelse return null;
    const previous = std.mem.lastIndexOfScalar(u8, text[0..last], ':') orelse return null;
    const line = std.fmt.parseInt(u64, text[previous + 1 .. last], 10) catch return null;
    const column = std.fmt.parseInt(u64, text[last + 1 ..], 10) catch return null;
    return .{ .path = text[0..previous], .line = line, .column = column };
}

// spec: NEW-CORE-S5-UNITS-1
test "native execution reports entry results, guest output and located traps" {
    const source =
        \\func main(out: Stream) -> i64:
        \\    print(out, "hello")
        \\    return 7
    ;
    var compilation = try language.Compilation.init(std.testing.allocator, "run.selka", source);
    defer compilation.deinit();
    const outcome = try run(&compilation);
    try std.testing.expectEqual(@as(i64, 7), outcome.value);
    try std.testing.expectEqualStrings("hello\n", outcome.stdout);
    // The entry returned 7, so the process exits 7; the value is not a trap.
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(@as(u8, 7), outcome.status);
    var trapped = try language.Compilation.init(std.testing.allocator, "trap.selka",
        \\func main() -> i64:
        \\    return divtrunc(1, 0)
    );
    defer trapped.deinit();
    const failure = try run(&trapped);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO", failure.trap.code);
    try std.testing.expect(failure.trapped());
    // The trap names the compilation's own path, not the directory it was built in.
    try std.testing.expectEqualStrings("trap.selka", failure.trap.path);
    try std.testing.expectEqual(@as(u64, 2), failure.trap.line);
    try std.testing.expectEqual(@as(u8, 1), failure.status);
    try std.testing.expectEqual(trap_detail.Operation.div, failure.trap.detail.operation);
    try std.testing.expectEqual(@as(i64, 1), failure.trap.detail.values.left);
    try std.testing.expectEqual(@as(i64, 0), failure.trap.detail.values.right);
}

// spec: NEW-CORE-S5-UNITS-BATCH-1
test "a batch runs its programs together and returns each run in job order" {
    var batch: Batch = .init(std.testing.allocator);
    defer batch.deinit();
    try batch.add("first.selka", "func main() -> i64:\n    return 1\n", .{});
    try batch.add("second.selka", "func main() -> i64:\n    return divtrunc(1, 0)\n", .{});
    try batch.add("loop.selka", "func main() -> i64:\n    while True:\n        pass\n    return 0\n", .{ .max_steps = 5 });
    // A rerun under another budget shares the program's written tree.
    try batch.again(2, .{ .max_steps = 9 });
    const runs = try batch.run();
    try std.testing.expectEqual(@as(usize, 4), runs.len);
    try std.testing.expectEqual(@as(i64, 1), runs[0].value);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO", runs[1].trap.code);
    try std.testing.expectEqualStrings("second.selka", runs[1].trap.path);
    try std.testing.expectEqualStrings("R_STEP_LIMIT", runs[2].trap.code);
    try std.testing.expectEqualStrings("R_STEP_LIMIT", runs[3].trap.code);
    // A program the front end rejects stops its batch before anything runs.
    var rejected: Batch = .init(std.testing.allocator);
    defer rejected.deinit();
    try rejected.add("fine.selka", "func main() -> i64:\n    return 0\n", .{});
    try rejected.add("bad.selka", "func main() -> i64:\n    return missing\n", .{});
    try std.testing.expectError(error.SourceError, rejected.run());
}

// spec-case: NEW-CORE-S5-UNITS-1
test "native execution separates the build's warnings from the program's standard error" {
    var compilation = try language.Compilation.init(std.testing.allocator, "warned.selka",
        \\func main(err: Stream) -> i64:
        \\    mut x = 1
        \\    const unused = 3
        \\    x = 2
        \\    print(err, "to err")
        \\    return x
    );
    defer compilation.deinit();
    const outcome = try run(&compilation);
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(@as(i64, 2), outcome.value);
    try std.testing.expectEqualStrings("to err\n", outcome.stderr);
}

// spec-case: NEW-CORE-S5-UNITS-1
test "a program only trusted source may spell is refused by selka, and a path that leaves its tree is not written" {
    var trusted = try language.Compilation.initTrusted(std.testing.allocator, "trusted.selka",
        // migrate-embedded: skip original trusted-source conditional removal witness
        \\result Time:
        \\    ok: i64,
        \\    err: i64
        \\
        \\
        \\func main(c: Clock) -> i64:
        \\    match clock_now[Time](c):
        \\        case ok(now):
        \\            return if (now > 0) then (0) else (1)
        \\        case err(e):
        \\            return e
    );
    defer trusted.deinit();
    // Preserve the old conditional; parser migration now precedes native trust checks.
    try std.testing.expectError(error.SourceError, run(&trusted));
    try std.testing.expectEqualStrings("E_CONDITIONAL_EXPRESSION_REMOVED", trusted.diagnostics.items[0].code);
    const modern_types = try std.mem.replaceOwned(u8, std.testing.allocator, trusted.src.bytes, "i64", "int");
    defer std.testing.allocator.free(modern_types);
    const modern_source = try std.mem.replaceOwned(u8, std.testing.allocator, modern_types, "return if (now > 0) then (0) else (1)", "if now > 0:\n                return 0\n            return 1");
    defer std.testing.allocator.free(modern_source);
    var modern_trusted = try language.Compilation.initTrusted(std.testing.allocator, "modern-trusted.selka", modern_source);
    defer modern_trusted.deinit();
    // Frontend trust permits the intrinsic. The real user-source child must
    // still refuse it after the native adapter writes ordinary source bytes.
    try modern_trusted.check();
    try std.testing.expectError(error.NewCoreBuildFailed, run(&modern_trusted));
    var escaping = try language.Compilation.init(std.testing.allocator, "../escape.selka", "func main() -> i64:\n    return 0\n");
    defer escaping.deinit();
    try std.testing.expectError(error.NativeHostFailed, run(&escaping));
    var modern_escaping = try language.Compilation.init(std.testing.allocator, "../escape.selka", "func main() -> int:\n    return 0\n");
    defer modern_escaping.deinit();
    try modern_escaping.check();
    try std.testing.expectError(error.NativeHostFailed, run(&modern_escaping));
}

/// An out-of-range write of a record element.
const record_element_write =
    \\record Row:
    \\    name: str
    \\
    \\
    \\func main() -> i64:
    \\    mut rows = [Row(name="a")]
    \\    rows[3] = Row(name="b")
    \\    return 0
;

// Original C0 literal-negative guests remain executable retirement diagnostics.
// The adjacent native matrix retains dynamic-negative trap detail coverage.
// spec-case: NEGATIVE-INDEX-FIX-1
test "literal negative native bounds guests report the removed feature" {
    const sources = [_][]const u8{
        "func main() -> i64:\n    mut xs = [1, 2]\n    return xs[-5]\n",
        "func main() -> i64:\n    mut xs = [1, 2]\n    xs[-5] = 9\n    return 0\n",
        "func main() -> i64:\n    mut xs: FixedArray[int, 2] = FixedArray[int, 2]([1, 2])\n    xs[-5] = 9\n    return 0\n",
        "func main() -> i64:\n    mut b = b\"abc\"\n    _ = b[-9]\n    return 0\n",
    };
    for (sources) |source| {
        var compilation = try language.Compilation.init(std.testing.allocator, "bounds-retired.selka", source);
        defer compilation.deinit();
        try std.testing.expectError(error.SourceError, compilation.check());
        var found = false;
        for (compilation.diagnostics.items) |diag| {
            if (std.mem.eql(u8, diag.code, "E_NEGATIVE_INDEX_REMOVED")) found = true;
        }
        try std.testing.expect(found);
    }
}

// spec: QBE-TRAP-DETAIL-1
test "native execution reports original bounds indexes for read write pop array text and bytes" {
    const Case = struct {
        source: []const u8,
        code: []const u8,
        operation: trap_detail.Operation,
        index: ?i64,
        length: u64,
        /// The human text the runtime rendered from the same structured detail.
        text: []const u8,
    };
    const cases = [_]Case{
        .{ .source = "func main() -> i64:\n    mut xs = [1]\n    return xs[14]\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = 14, .length = 1, .text = "(index 14, length 1)" },
        .{ .source = "func main() -> i64:\n    mut xs = [1, 2]\n    return xs[0 - len(xs) - 3]\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = -5, .length = 2, .text = "(index -5, length 2)" },
        .{ .source = "func main() -> i64:\n    mut xs = [1, 2]\n    xs[0 - len(xs) - 3] = 9\n    return 0\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = -5, .length = 2, .text = "(index -5, length 2)" },
        .{ .source = "func main() -> i64:\n    mut xs = [1, 2]\n    xs[14] = 9\n    return 0\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = 14, .length = 2, .text = "(index 14, length 2)" },
        .{ .source = record_element_write, .code = "R_LIST_BOUNDS", .operation = .index, .index = 3, .length = 1, .text = "(index 3, length 1)" },
        .{ .source = "import lists\n\n\nfunc main() -> i64:\n    mut xs: i64[] = []\n    return lists.pop(mut xs)\n", .code = "R_LIST_BOUNDS", .operation = .pop, .index = null, .length = 0, .text = "(length 0)" },
        .{ .source = "import lists\n\n\nfunc main() -> i64:\n    mut xs = [1, 2]\n    return lists.pop_at(mut xs, 7)\n", .code = "R_LIST_BOUNDS", .operation = .pop, .index = 7, .length = 2, .text = "(index 7, length 2)" },
        .{ .source = "func main() -> i64:\n    mut xs: FixedArray[int, 3] = FixedArray[int, 3]([1, 2, 3])\n    return xs[7]\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = 7, .length = 3, .text = "(index 7, length 3)" },
        .{
            .source = "func main() -> i64:\n    mut xs: FixedArray[int, 3] = FixedArray[int, 3]([1, 2, 3])\n    xs = replace(xs, 7, 9)\n    return xs[0]\n",
            .code = "R_LIST_BOUNDS",
            .operation = .index,
            .index = 7,
            .length = 3,
            .text = "(index 7, length 3)",
        },
        // PY-ARRAY-NEGATIVE-1: a fixed array reports the index as written,
        // without counting from the end, exactly as the list above does.
        .{
            .source = "func main() -> i64:\n    mut xs: FixedArray[int, 2] = FixedArray[int, 2]([1, 2])\n    mut i = -5\n    return xs[i]\n",
            .code = "R_LIST_BOUNDS",
            .operation = .index,
            .index = -5,
            .length = 2,
            .text = "(index -5, length 2)",
        },
        .{
            .source = "func main() -> i64:\n    mut xs: FixedArray[int, 2] = FixedArray[int, 2]([1, 2])\n    xs[0 - len(xs) - 3] = 9\n    return 0\n",
            .code = "R_LIST_BOUNDS",
            .operation = .index,
            .index = -5,
            .length = 2,
            .text = "(index -5, length 2)",
        },
        .{ .source = "func main() -> i64:\n    mut s = \"abc\"\n    _ = strings.char_at(s, 9)\n    return 0\n", .code = "R_TEXT_BOUNDS", .operation = .index, .index = 9, .length = 3, .text = "(index 9, length 3)" },
        .{ .source = "func main() -> i64:\n    mut b = b\"abc\"\n    _ = b[0 - len(b) - 6]\n    return 0\n", .code = "R_LIST_BOUNDS", .operation = .index, .index = -9, .length = 3, .text = "(index -9, length 3)" },
    };
    // The fixtures run as one-module projects so a `pop` case can carry the
    // `import lists` its retired spelling's repair writes. `stdlib_fixture`
    // cannot serve this file: it imports this one, so the provider is local.
    const Entry = struct {
        text: []const u8,
        pub fn read(context: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
            if (!std.mem.eql(u8, path, "main.selka")) return error.NotFound;
            return allocator.dupe(u8, (@as(*const @This(), @ptrCast(@alignCast(context.?)))).text);
        }
    };
    for (cases) |case| {
        var entry: Entry = .{ .text = case.source };
        var program: language.embedded_project.Program = undefined;
        try program.init(std.testing.allocator, .{ .context = &entry, .read = Entry.read });
        defer program.deinit();
        const outcome = try run(&program.compilation);
        try std.testing.expect(outcome.trapped());
        try std.testing.expectEqualStrings(case.code, outcome.trap.code);
        try std.testing.expectEqual(case.operation, outcome.trap.detail.operation);
        try std.testing.expectEqual(case.length, outcome.trap.detail.values.length);
        try std.testing.expect(outcome.trap.detail.has(trap_detail.present_length));
        if (case.index) |index| {
            try std.testing.expect(outcome.trap.detail.has(trap_detail.present_index));
            try std.testing.expectEqual(index, outcome.trap.detail.values.index);
        } else {
            try std.testing.expect(!outcome.trap.detail.has(trap_detail.present_index));
        }
        // The text diagnostic quotes the same values, without the machine record.
        try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, case.text) != null);
        try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, trap_detail.marker) == null);
    }
}

// spec-case: TEXT-BOUNDARY-1
test "a byte slice endpoint inside a scalar traps R_TEXT_BOUNDARY" {
    // U+00E9 is two octets (0xC3 0xA9), so offset 2 begins its continuation and a
    // slice that starts there would cut the scalar. The trap names the offset and
    // the byte length, and a whole scalar and an empty range stay valid.
    const source = "func main() -> int:\n    const text = \"héllo\"\n    return len(text[2:3])\n";
    var compilation = try language.Compilation.init(std.testing.allocator, "boundary.selka", source);
    defer compilation.deinit();
    const outcome = try run(&compilation);
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings("R_TEXT_BOUNDARY", outcome.trap.code);
    try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, "(offset 2, length 6") != null);
    // The message names the helpers that cannot fall inside a character (F-74).
    try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, "`strings.cut_octets`, `strings.char_slice` and `strings.starts_with_at`") != null);
    const scalars = "func main() -> int:\n    const text = \"héllo\"\n    return len(text[1:3]) + len(text[2:2])\n";
    var whole = try language.Compilation.init(std.testing.allocator, "boundary-ok.selka", scalars);
    defer whole.deinit();
    const fine = try run(&whole);
    try std.testing.expect(!fine.trapped());
    try std.testing.expectEqual(@as(i64, 2), fine.value);
}

// spec: TRAP-UNSIGNED-1
test "unsigned overflow cast and division traps quote their operands unsigned and signed ones unchanged" {
    const Case = struct { body: []const u8, code: []const u8, text: []const u8, unsigned: bool };
    const cases = [_]Case{
        .{ .body = "return i64(a + b)", .code = "R_OVERFLOW", .text = "(add: left 18446744073709551614, right 5, width 64)", .unsigned = true },
        .{ .body = "return i64(a * b)", .code = "R_OVERFLOW", .text = "(mul: left 18446744073709551614, right 5, width 64)", .unsigned = true },
        .{ .body = "return i64(a)", .code = "R_OVERFLOW", .text = "(cast: left 18446744073709551614, width 64)", .unsigned = true },
        .{ .body = "return i64(a // (b - b))", .code = "R_DIVISION_BY_ZERO", .text = "left 18446744073709551614, right 0)", .unsigned = true },
        .{ .body = "return i64(b - a)", .code = "R_OVERFLOW", .text = "(sub: left 5, right 18446744073709551614, width 64)", .unsigned = true },
        // A signed operation keeps its signed rendering byte for byte.
        .{ .body = "return c + 1", .code = "R_OVERFLOW", .text = "(add: left 9223372036854775807, right 1, width 64)", .unsigned = false },
        .{ .body = "return d * 2", .code = "R_OVERFLOW", .text = "(mul: left -9223372036854775807, right 2, width 64)", .unsigned = false },
    };
    for (cases) |case| {
        const source = try std.fmt.allocPrint(std.testing.allocator,
            \\func compute(a: u64, b: u64, c: i64, d: i64) -> i64:
            \\    {s}
            \\
            \\
            \\func main() -> i64:
            \\    return compute(18446744073709551614, 5, 9223372036854775807, -9223372036854775807)
        , .{case.body});
        defer std.testing.allocator.free(source);
        var compilation = try language.Compilation.init(std.testing.allocator, "unsigned.selka", source);
        defer compilation.deinit();
        const outcome = try run(&compilation);
        try std.testing.expect(outcome.trapped());
        try std.testing.expectEqualStrings(case.code, outcome.trap.code);
        try std.testing.expectEqual(case.unsigned, outcome.trap.detail.has(trap_detail.present_unsigned));
        try std.testing.expect(std.mem.indexOf(u8, outcome.stderr, case.text) != null);
    }
}

// spec-case: QBE-TRAP-DETAIL-1
test "native execution keeps the first trap detail and leaves budget traps detail-free" {
    var first = try language.Compilation.init(std.testing.allocator, "first.selka",
        \\func main() -> i64:
        \\    return divtrunc(1, 0) + (9223372036854775807 + 1)
    );
    defer first.deinit();
    const outcome = try run(&first);
    try std.testing.expectEqualStrings("R_DIVISION_BY_ZERO", outcome.trap.code);
    try std.testing.expectEqual(trap_detail.Operation.div, outcome.trap.detail.operation);
    var loop = try language.Compilation.init(std.testing.allocator, "budget.selka",
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer loop.deinit();
    const limited = try runWithOptions(&loop, .{ .max_steps = 17 });
    try std.testing.expectEqualStrings("R_STEP_LIMIT", limited.trap.code);
    try std.testing.expectEqual(@as(u32, 0), limited.trap.detail.version);
}

test "native execution honours step budgets and separates the result line from output" {
    var compilation = try language.Compilation.init(std.testing.allocator, "budget.selka",
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer compilation.deinit();
    const limited = try runWithOptions(&compilation, .{ .max_steps = 17 });
    try std.testing.expectEqualStrings("R_STEP_LIMIT", limited.trap.code);
    try std.testing.expectEqualStrings("", limited.stdout);
    const divided = try divide("a\nb\n12\n");
    try std.testing.expectEqualStrings("a\nb\n", divided.output);
    try std.testing.expectEqual(@as(i64, 12), divided.value);
    try std.testing.expectError(error.UnreadableNativeResult, divide("no newline"));
}

// spec: RUNTIME-UNBOUNDED-1
test "a native run completes a loop that outgrows the old default step budget" {
    var compilation = try language.Compilation.init(std.testing.allocator, "unbounded.selka",
        \\func main() -> i64:
        \\    mut i = 0
        \\    while i < 3000000:
        \\        i += 1
        \\    return i
    );
    defer compilation.deinit();
    // A 60-second guard keeps a regression from hanging the test runner; an
    // honest loop that needs tens of millions of steps must still finish.
    const outcome = try runWithOptions(&compilation, .{ .arguments = &.{"--timeout=60"} });
    try std.testing.expect(!outcome.trapped());
    try std.testing.expectEqual(@as(i64, 3000000), outcome.value);
}

// spec: RUNTIME-TIMEOUT-1
test "a wall-clock timeout ends an unbounded native run with R_TIMEOUT" {
    var compilation = try language.Compilation.init(std.testing.allocator, "timeout.selka",
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer compilation.deinit();
    const outcome = try runWithOptions(&compilation, .{ .arguments = &.{"--timeout=1"} });
    try std.testing.expect(outcome.trapped());
    try std.testing.expectEqualStrings("R_TIMEOUT", outcome.trap.code);
}

// spec-case: NATIVE-ARGV-1
test "harness step ceilings fail closed and ordinary executables ignore them" {
    var compilation = try language.Compilation.init(std.testing.allocator, "harness-limit.selka", "func main() -> i64:\n    return 7\n");
    defer compilation.deinit();
    try compilation.check();
    const session = try wiring.acquire();
    const tree = try write(session, try singleSource(session.allocator(), compilation.src));
    const instrumented = try buildExecutable(session, tree, true);
    const ordinary = try executable(&compilation);
    const unbounded = try rawHarnessRun(session, instrumented, "0", print_result_option);
    try std.testing.expectEqualStrings("7\n", unbounded.stdout);
    try std.testing.expectEqual(@as(u8, 7), unbounded.term.exited);
    const normal = try rawHarnessRun(session, ordinary, "invalid", print_result_option);
    try std.testing.expectEqualStrings("7\n", normal.stdout);
    try std.testing.expectEqual(@as(u8, 7), normal.term.exited);
    const declined = try rawHarnessRun(session, ordinary, "1", "--max-steps=1");
    try std.testing.expectEqual(@as(u8, 1), declined.term.exited);
    try std.testing.expect(std.mem.indexOf(u8, declined.stderr, "R_NO_STEP_ACCOUNTING") != null);
    for ([_]?[]const u8{ null, "", "-1", "invalid", "18446744073709551616" }) |ceiling| {
        const invalid = try rawHarnessRun(session, instrumented, ceiling, print_result_option);
        try std.testing.expectEqual(@as(u8, 2), invalid.term.exited);
        try std.testing.expectEqualStrings("", invalid.stdout);
        try std.testing.expect(std.mem.indexOf(u8, invalid.stderr, "harness step ceiling") != null);
    }
}

fn rawHarnessRun(session: *wiring.Session, program: []const u8, ceiling: ?[]const u8, options: []const u8) Error!std.process.RunResult {
    const environment = try session.environment(null);
    if (ceiling) |value| try environment.put("SELKA_TEST_MAX_STEPS", value);
    try environment.put("SELKA_OPTIONS", options);
    return std.process.run(session.allocator(), session.io, .{ .argv = &.{program}, .environ_map = environment });
}

// spec-case: NATIVE-ARGV-1
test "harness budget diagnostics preserve preceding guest stderr" {
    var batch: Batch = .init(std.testing.allocator);
    defer batch.deinit();
    try batch.budgetSweep("budget-output.selka",
        \\func main(err: Stream) -> i64:
        \\    print(err, "prefix")
        \\    mut count = 0
        \\    while count < 2:
        \\        count += 1
        \\    return count
    , .{}, 12);
    const runs = try batch.run();
    try expectBudgetSweep(runs);
    try std.testing.expectEqual(@as(i64, 2), runs[0].value);
    try std.testing.expect(std.mem.startsWith(u8, runs[1].stderr, "prefix\nerror[R_STEP_LIMIT]: native execution failed\n"));
}

// spec-case: NATIVE-ARGV-1
test "harness runtime options retain the wall clock timeout" {
    var compilation = try language.Compilation.init(std.testing.allocator, "harness-timeout.selka",
        \\func main() -> i64:
        \\    while True:
        \\        pass
        \\    return 0
    );
    defer compilation.deinit();
    const runs = try runAll(&.{.{ .compilation = &compilation, .harness_steps = true, .options = .{ .arguments = &.{"--timeout=1"} } }});
    try std.testing.expectEqual(@as(usize, 1), runs.len);
    try std.testing.expect(runs[0].trapped());
    try std.testing.expectEqualStrings("R_TIMEOUT", runs[0].trap.code);
    try std.testing.expectEqual(@as(u8, 1), runs[0].status);
}
