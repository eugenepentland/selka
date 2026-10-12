//! Running the selected tests of one test executable.
//!
//! A property test (generated inputs) runs its own search in processes of its own
//! (PROPERTY-TEST-4). Every other test is one plain trial, and plain trials share
//! processes (NEW-CORE-TEST-BATCH-1): a worker takes the next run of pending tests,
//! about the pending count over the worker count, and one process of the executable
//! answers them in table order. Each trial runs in its own forked child, with fresh
//! capability stand-ins, its own captured output and its own step, frame, memory and
//! wall-clock budgets, so a test sees nothing of the tests before it. A test that ends
//! its process without answering keeps the answers before it: a trial's timeout is
//! its verdict, anything else is rerun alone for a verdict of its own, and the rest
//! of the run continues in a new process.
const std = @import("std");
const discover = @import("test_runner_discover.zig");
const report = @import("test_runner_report.zig");
const typed = @import("mylang").typed;
const property = @import("test_runner_property.zig");
const property_types = @import("property_types.zig");
const property_schema = @import("property_schema.zig");
const property_execute = @import("property_execute.zig");
const v = @import("property_value.zig");
const Options = @import("test_runner_options.zig").Options;
const spawn = @import("process_spawn.zig");
const root_share = @import("test_runner_shared.zig");
const Value = std.json.Value;
const receipt = @import("test_runner_receipt.zig");
const campaign_contract = @import("property_campaign_contract.zig");
const campaign_receipt = @import("property_campaign_receipt.zig");

/// What stops a run: memory, or an output stream that cannot be written.
pub const Error = property.Error;

/// One selected test and its place in the report. `ready` tests have no verdict yet:
/// their `verdict` is filled in by building and running them.
pub const Selected = struct { case: discover.Case, verdict: report.Verdict, ready: bool, identity: ?[32]u8 = null, cache_reason: ?[]const u8 = null, key_method: []const u8 = "reachable-ir", settings: Value = .null };

/// The cases-file key holding a test's expected result.
pub const expectation = "expected";

/// The arena, child-output allocator, I/O and environment the test processes use; the
/// arena must be thread-safe.
pub const Resources = struct { arena: std.mem.Allocator, backing: std.mem.Allocator, io: std.Io, environment: spawn.Environment, campaign: ?*const Campaign = null };

/// Captured checking inputs and provider/tool contracts guarded at each range boundary.
pub const Campaign = struct {
    context: receipt.Context,
    inputs: []const receipt.Dependency,
    backing: std.mem.Allocator,

    /// Reject a range if its checked sources, toolchain or planner deployment changed.
    pub fn unchanged(self: Campaign) campaign_contract.CommitError!bool {
        var scratch = std.heap.ArenaAllocator.init(self.backing);
        defer scratch.deinit();
        var context = self.context;
        context.arena = scratch.allocator();
        receipt.validatePlan(context) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.WriteFailed => error.WriteFailed,
            else => error.ComponentUnavailable,
        };
        const sources = receipt.unchanged(context, self.inputs) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
        if (!sources) return false;
        const tool = receipt.toolUnchanged(context) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
        return tool;
    }
};

/// A built test executable and the checked program its tests come from.
pub const Executable = struct { path: []const u8, program: typed.Program };

/// How many test processes run at once, and at most how many plain tests one answers:
/// `MYLANG_TEST_ISOLATE=1` gives each its own, the differential oracle for batching.
/// With a directory run's `permits`, each test process also holds one of them.
pub const Workers = struct { width: usize, batch: usize = std.math.maxInt(usize), permits: ?*root_share.Permits = null };

/// Whether `MYLANG_TEST_ISOLATE=1` asks for one process per plain test.
pub fn isolated(environment: *const std.process.Environ.Map) bool {
    return std.mem.eql(u8, environment.get("MYLANG_TEST_ISOLATE") orelse "", "1");
}

/// What the execution tier looks receipts up under: the run's receipt context and
/// the built program's exact key (`driver.Outcome.program_key`).
pub const Linked = struct { context: receipt.Context, program_key: [32]u8 };

/// One built program's execution-tier keys (EXEC-RECEIPT-1): each consulted test's
/// position in the run's selection and its key, and the whole-program key over all
/// of them (EXEC-RECEIPT-3).
pub const Executed = struct { positions: []const usize, keys: []const [32]u8, whole: [32]u8 };

/// Before the first trial of a linked program, look up the whole-program execution
/// receipt and then each test's for `chosen[positions]` (tests without live effects).
/// A hit is `cached` with `whole-exec-receipt-hit` or `exec-receipt-hit` and runs no
/// trial. Null when the execution tier is not admitted: forced, `--link`, loader
/// overrides, an unproved toolchain or an indexed property campaign.
pub fn reuse(linked: Linked, chosen: []Selected, positions: []const usize) Error!?Executed {
    const context = linked.context;
    if (positions.len == 0 or context.options.properties.policy != .legacy or !receipt.executionReusable(context)) return null;
    const a = context.arena;
    const settings = try receipt.executionSettings(context);
    const keys = try a.alloc([32]u8, positions.len);
    const names = try a.alloc([]const u8, positions.len);
    for (positions, keys, names) |position, *key, *name| {
        name.* = chosen[position].case.name;
        key.* = try receipt.executionKey(context, .{ .program_key = linked.program_key, .name = name.*, .settings = settings });
    }
    const whole = try receipt.wholeExecutionKey(context, linked.program_key, names, settings);
    const every = try receipt.executionHit(context, whole);
    for (positions, keys) |position, key| {
        const reason = if (every) "whole-exec-receipt-hit" else if (try receipt.executionHit(context, key)) "exec-receipt-hit" else continue;
        const item = &chosen[position];
        item.verdict = .{ .name = item.case.name, .status = .cached };
        item.ready = false;
        item.cache_reason = reason;
    }
    return .{ .positions = positions, .keys = keys, .whole = whole };
}

/// Whether `reason` names an execution-tier hit.
pub fn executionHit(reason: ?[]const u8) bool {
    const found = reason orelse return false;
    return std.mem.eql(u8, found, "exec-receipt-hit") or std.mem.eql(u8, found, "whole-exec-receipt-hit");
}

/// Run `chosen[positions]` with `workers`. The test at `positions[i]` is row `i` of the
/// executable's dispatch table; a test no longer `ready` (an execution receipt
/// answered it) keeps its row and runs no trial.
pub fn run(resources: Resources, options: Options, executable: Executable, chosen: []Selected, positions: []const usize, workers: Workers) Error!void {
    const a = resources.arena;
    const shared: Shared = .{
        .resources = resources,
        .options = options,
        .program = executable.program,
        .executor = .{
            .context = .{ .arena = a, .backing = resources.backing, .io = resources.io, .environment = resources.environment },
            .types = try property_schema.definitions(a, executable.program),
            .executable = executable.path,
            .table_index = 0,
            .directory = "",
            .source_path = std.Io.Dir.cwd().realPathFileAlloc(resources.io, options.path, a) catch options.path,
        },
    };
    var searches: std.ArrayList(Pending) = .empty;
    var plains: std.ArrayList(Pending) = .empty;
    for (positions, 0..) |position, row| {
        const selected = &chosen[position];
        if (!selected.ready) continue;
        const pending = try shared.prepare(selected, row) orelse continue;
        try (if (pending.search) &searches else &plains).append(a, pending);
    }
    if (searches.items.len + plains.items.len == 0) return;
    const width = @max(1, @min(workers.width, searches.items.len + plains.items.len));
    var queue: Queue = .{ .shared = &shared, .searches = searches.items, .plains = plains.items, .workers = .{ .width = width, .batch = @max(1, workers.batch), .permits = workers.permits } };
    // NEW-CORE-TEST-QUEUE-1: each thread takes the next work as soon as its last ends.
    const threads = try a.alloc(std.Thread, width - 1);
    const failures = try a.alloc(?Error, width);
    @memset(failures, null);
    var started: usize = 0;
    for (threads, failures[1..]) |*thread, *failure| {
        thread.* = std.Thread.spawn(.{}, Queue.drain, .{ &queue, failure }) catch break;
        started += 1;
    }
    queue.drain(&failures[0]);
    for (threads[0..started]) |thread| thread.join();
    for (failures) |failure| if (failure) |err| return err;
}

/// What every process of one executable shares. The executor's row and directory are
/// set per process.
const Shared = struct {
    resources: Resources,
    options: Options,
    program: typed.Program,
    executor: property_execute.Executor,

    /// `selected`'s pending work, or null once an invalid cases-file argument gave it
    /// its verdict.
    fn prepare(self: *const Shared, selected: *Selected, row: usize) Error!?Pending {
        const case = selected.case;
        const function = try functionValue(self.resources.arena, self.program, case);
        const arguments = v.get(selected.settings, "arguments");
        const fixed = arguments == .object and arguments.object.count() != 0;
        if (case.other_parameters != 0 and !fixed) return .{ .selected = selected, .row = row, .function = function, .search = true };
        const words = if (fixed) self.executor.encode(function, arguments) catch |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            selected.verdict = .{ .name = case.name, .status = .failed, .reason = "invalid cases-file arguments" };
            return null;
        } else &.{};
        return .{ .selected = selected, .row = row, .function = function, .words = words };
    }

    /// A private directory for one worker's trial files, and the executor that uses it.
    fn executorIn(self: *const Shared, directory: []const u8, row: usize) property_execute.Executor {
        var executor = self.executor;
        executor.directory = directory;
        executor.table_index = row;
        return executor;
    }

    fn privateDirectory(self: *const Shared) Error![]const u8 {
        var nonce: [16]u8 = undefined;
        std.Io.random(self.resources.io, &nonce);
        const directory = try std.fmt.allocPrint(self.resources.arena, "{s}/tests/private-{s}", .{ self.options.build.cache, std.fmt.bytesToHex(nonce, .lower) });
        std.Io.Dir.cwd().createDirPath(self.resources.io, directory) catch return error.WriteFailed;
        return directory;
    }

    /// Run a property test's search in its own processes.
    fn search(self: *const Shared, pending: Pending) Error!void {
        const case = pending.selected.case;
        const directory = try self.privateDirectory();
        defer removePrivate(self.resources.io, directory);
        const executor = self.executorIn(directory, pending.row);
        const limits: property_execute.Limits = .{ .timeout_ms = self.options.controls.timeout_ms };
        const settings: property.Settings = .{ .seed = entropySeed(self.options.properties.seed, case.name), .runs = self.options.properties.runs, .entry = self.options.path, .policy = self.options.properties.policy };
        const setup = try property.Property.bind(executor.context, &executor, pending.function, limits, settings);
        var bound = switch (setup) {
            .invalid => |reason| {
                pending.selected.verdict = .{ .name = case.name, .status = .failed, .reason = reason };
                return;
            },
            .ready => |ready| ready,
        };
        var checkpoint: ?Checkpoint = null;
        defer if (checkpoint) |*saved| saved.deinit();
        if (self.options.properties.policy == .indexed_v1) if (self.resources.campaign) |guard| {
            const eligible = std.mem.eql(u8, receipt.reuseReason(guard.context), "no-success-receipt");
            checkpoint = try Checkpoint.init(guard.*, self.options.build.cache, if (eligible) pending.selected.identity else null, self.options.properties.runs);
            const saved = &checkpoint.?;
            try bound.restoreCampaign(.{ .restored = saved.expected orelse .{}, .callback = .{ .context = saved, .commit = Checkpoint.commit } });
        };
        var state: property.Search = .{};
        const first = try bound.first(&state);
        const answer = if (first) |batch| (try property_execute.executeBatches(executor.context, &.{batch}, limits, 1))[0] else null;
        const verdict = try bound.finish(&state, answer);
        pending.selected.verdict = .{ .name = case.name, .status = if (verdict.passed) .passed else .failed, .reason = verdict.reason, .property = verdict.evidence };
    }

    /// Run plain tests in as few processes as their endings allow: one, unless a test
    /// ends its process without answering.
    fn plain(self: *const Shared, batch: []const Pending) Error!void {
        const directory = try self.privateDirectory();
        defer removePrivate(self.resources.io, directory);
        const executor = self.executorIn(directory, 0);
        var rest = batch;
        while (rest.len != 0) {
            const answered = try self.trials(&executor, rest);
            const done = @min(answered.outcomes.len, rest.len);
            for (rest[0..done], answered.outcomes[0..done]) |pending, outcome| pending.selected.verdict = try self.grade(pending, outcome);
            if (done == rest.len) return;
            // The process ended inside `rest[done]`'s trial. Its own timeout is its
            // verdict; any other ending is rerun alone, unless it already ran alone.
            const ended = rest[done];
            if (answered.timed_out or answered.alarm or rest.len == 1) {
                ended.selected.verdict = try self.unanswered(ended, answered);
            } else {
                const alone = try self.trials(&executor, rest[done..][0..1]);
                ended.selected.verdict = if (alone.outcomes.len != 0) try self.grade(ended, alone.outcomes[0]) else try self.unanswered(ended, alone);
            }
            rest = rest[done + 1 ..];
        }
    }

    fn trials(self: *const Shared, executor: *const property_execute.Executor, batch: []const Pending) Error!property_execute.BatchOutcome {
        const a = self.resources.arena;
        const requested = try a.alloc(property_execute.Trial, batch.len);
        for (requested, batch) |*trial, pending| trial.* = .{ .row = pending.row, .function = pending.function, .words = pending.words };
        // Each trial holds itself to the timeout; the process as a whole gets one
        // timeout, plus a second of slack, per trial.
        const each: u64 = @as(u64, self.options.controls.timeout_ms) + 1000;
        const whole: u32 = @intCast(@min(each * batch.len, std.math.maxInt(u32)));
        return executor.trials(requested, .{ .timeout_ms = whole });
    }

    /// The verdict of a test whose process ended before it answered.
    fn unanswered(self: *const Shared, pending: Pending, ending: property_execute.BatchOutcome) Error!report.Verdict {
        const name = pending.selected.case.name;
        if (ending.timed_out or ending.alarm) return .{ .name = name, .status = .failed, .reason = try std.fmt.allocPrint(self.resources.arena, "timed out after {d} ms", .{self.options.controls.timeout_ms}) };
        return .{ .name = name, .status = .failed, .reason = ending.ending };
    }

    /// The verdict of a plain test's answer.
    fn grade(self: *const Shared, pending: Pending, outcome: property_execute.Outcome) Error!report.Verdict {
        const a = self.resources.arena;
        const program = self.program;
        const selected = pending.selected;
        const case = selected.case;
        const explicit = selected.settings == .object and selected.settings.object.contains(expectation);
        const returned = std.mem.eql(u8, outcome.status, "value");
        const matches = if (!returned) false else if (explicit) try expectedResult(a, program, case, v.get(selected.settings, expectation), outcome.actual) else truth(outcome.actual);
        const passed = returned and matches;
        if (explicit and !passed and returned) {
            const expected_text = try std.json.Stringify.valueAlloc(a, v.get(selected.settings, expectation), .{});
            const actual_text = if (outcome.actual == .string and integerResult(program, case)) outcome.actual.string else try std.json.Stringify.valueAlloc(a, outcome.actual, .{});
            return .{ .name = case.name, .status = .failed, .reason = try std.fmt.allocPrint(a, "expected {s}, got {s}", .{ expected_text, actual_text }) };
        }
        return .{ .name = case.name, .status = if (passed) .passed else .failed, .reason = if (passed) "" else try ordinaryReason(a, outcome) };
    }
};

/// One property's captured-input guard and bounded expected-prefix allocation arena.
const Checkpoint = struct {
    guard: Campaign,
    root: []const u8,
    key: ?campaign_receipt.Digest,
    expected: ?campaign_contract.Progress = null,
    progress_arena: std.heap.ArenaAllocator,

    fn init(guard: Campaign, root: []const u8, key: ?campaign_receipt.Digest, budget: u32) Error!Checkpoint {
        if (!try guard.unchanged()) return error.SourceChanged;
        var result: Checkpoint = .{ .guard = guard, .root = root, .key = key, .progress_arena = .init(guard.backing) };
        errdefer result.deinit();
        if (key) |identity| result.expected = try result.store(result.progress_arena.allocator()).load(identity, budget);
        if (!try guard.unchanged()) return error.SourceChanged;
        return result;
    }

    fn deinit(self: *Checkpoint) void {
        self.progress_arena.deinit();
    }

    fn store(self: *Checkpoint, allocator: std.mem.Allocator) campaign_receipt.Store {
        return .{ .arena = allocator, .io = self.guard.context.io, .root = self.root };
    }

    fn commit(raw: *anyopaque, progress: campaign_contract.Progress) campaign_contract.CommitError!void {
        const self: *Checkpoint = @ptrCast(@alignCast(raw));
        if (!try self.guard.unchanged()) return error.SourceChanged;
        const key = self.key orelse return;
        if (!try self.store(self.guard.backing).commit(key, self.expected, progress)) return;
        var next_arena = std.heap.ArenaAllocator.init(self.guard.backing);
        errdefer next_arena.deinit();
        var expected = progress;
        const a = next_arena.allocator();
        const clauses = try a.alloc(campaign_contract.Clause, progress.clauses.len);
        for (progress.clauses, clauses) |source, *target| target.* = .{ .message = try a.dupe(u8, source.message), .count = source.count };
        expected.clauses = clauses;
        self.progress_arena.deinit();
        self.progress_arena = next_arena;
        self.expected = expected;
    }
};

/// One selected test waiting to run: its table row, its signature, and either the
/// fixed inputs of its one plain trial or a property search.
const Pending = struct { selected: *Selected, row: usize, function: Value, words: []const u64 = &.{}, search: bool = false };

/// One unit of a worker's work: a property search, or a run of plain tests.
const Work = union(enum) { search: Pending, plain: []const Pending };

/// The pending work of one executable, taken by every worker thread: property searches
/// first, one each, then runs of plain tests.
const Queue = struct {
    shared: *const Shared,
    searches: []const Pending,
    plains: []const Pending,
    workers: Workers,
    taken: struct { searches: std.atomic.Value(usize) = .init(0), plains: std.atomic.Value(usize) = .init(0) } = .{},

    fn drain(self: *Queue, failure: *?Error) void {
        const io = self.shared.resources.io;
        while (true) {
            const searched = self.taken.searches.fetchAdd(1, .monotonic);
            const work: Work = if (searched < self.searches.len) .{ .search = self.searches[searched] } else if (self.next()) |batch| .{ .plain = batch } else return;
            if (self.workers.permits) |permits| permits.acquire(io, 1);
            const result = switch (work) {
                .search => |pending| self.shared.search(pending),
                .plain => |batch| self.shared.plain(batch),
            };
            if (self.workers.permits) |permits| permits.release(io, 1);
            result catch |err| {
                failure.* = err;
                return;
            };
        }
    }

    /// The next run of plain tests: the pending count over the worker count, rounded
    /// up, so early runs are long and the last ones short enough to balance the end.
    fn next(self: *Queue) ?[]const Pending {
        const width = self.workers.width;
        while (true) {
            const start = self.taken.plains.load(.monotonic);
            if (start >= self.plains.len) return null;
            const size = @min(self.workers.batch, (self.plains.len - start + width - 1) / width);
            if (self.taken.plains.cmpxchgWeak(start, start + size, .monotonic, .monotonic) == null) return self.plains[start..][0..size];
        }
    }
};

/// Stable stand-in/property seed, identical to native_test_wire.entropySeed.
pub fn entropySeed(explicit: ?u64, name: []const u8) u64 {
    if (explicit) |seed| return seed;
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(name, &digest, .{});
    return std.mem.readInt(u64, digest[0..8], .little);
}

fn functionValue(a: std.mem.Allocator, program: typed.Program, case: discover.Case) Error!Value {
    const f = program.functions[@backingInt(case.function)];
    var out: std.json.ObjectMap = .empty;
    try out.put(a, "name", .{ .string = case.name });
    try out.put(a, "result", .{ .string = typed.typeName(f.signature.return_type, program.records) });
    var parameters: std.json.Array = .init(a);
    for (f.scope.locals[0..f.signature.parameter_count]) |parameter| {
        var item: std.json.ObjectMap = .empty;
        try item.put(a, "name", .{ .string = parameter.name });
        try item.put(a, "type", .{ .string = typed.typeName(parameter.ty, program.records) });
        try item.put(a, "mode", .{ .string = "value" });
        try parameters.append(.{ .object = item });
    }
    try out.put(a, "parameters", .{ .array = parameters });
    return .{ .object = out };
}

/// NATIVE-TEST-8: whether `case` returns a plain integer, whose value a failed typed
/// expectation quotes bare (`got 3`) rather than in the cases encoding (`got "3"`).
fn integerResult(program: typed.Program, case: discover.Case) bool {
    const name = typed.typeName(program.functions[@backingInt(case.function)].signature.return_type, program.records);
    for ([_][]const u8{ "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64" }) |integer| if (std.mem.eql(u8, name, integer)) return true;
    return false;
}

fn expectedResult(a: std.mem.Allocator, program: typed.Program, case: discover.Case, expected: Value, actual: Value) Error!bool {
    const schema = try property_types.Schema.init(a, try property_schema.definitions(a, program));
    const function = program.functions[@backingInt(case.function)];
    const name = typed.typeName(function.signature.return_type, program.records);
    const validation = @import("property_validate.zig");
    validation.validate(schema, name, expected, 0) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    validation.validate(schema, name, actual, 0) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return false;
    };
    return validation.equivalent(expected, actual);
}
fn truth(value: Value) bool {
    if (value == .bool) return value.bool;
    return std.mem.eql(u8, v.text(v.get(value, "case")), "ok") and v.get(value, "value") == .bool and v.get(value, "value").bool;
}

/// Best-effort retirement only touches the selected test's owned directory.
pub fn removePrivate(io: std.Io, directory: []const u8) void {
    std.Io.Dir.cwd().deleteTree(io, directory) catch return;
}

// spec-case: NEW-CORE-TEST-BATCH-1
test "Queue.drain stops its worker at the first error and reports it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    // A file where the cache directory should be: no private directory can be made.
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "cache", .data = "" });
    const cache = try temporary.dir.realPathFileAlloc(std.testing.io, "cache", a);
    const resources: Resources = .{ .arena = a, .backing = std.testing.allocator, .io = std.testing.io, .environment = .{ .block = .empty } };
    const context: property_execute.Context = .{ .arena = a, .backing = std.testing.allocator, .io = std.testing.io, .environment = .{ .block = .empty } };
    const shared: Shared = .{
        .resources = resources,
        .options = .{ .path = "x.my", .build = .{ .zig = "zig", .cache = cache } },
        .program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(@intCast(0)) },
        .executor = .{ .context = context, .types = &.{}, .executable = "", .table_index = 0, .directory = "" },
    };
    var selected: Selected = .{ .case = .{ .name = "x::test_x", .function = @fromBackingInt(@intCast(0)), .shape = .boolean, .other_parameters = 0, .streams = &.{} }, .verdict = .{ .name = "x::test_x", .status = .skipped }, .ready = true };
    const plains: []const Pending = &.{.{ .selected = &selected, .row = 0, .function = .null }};
    var queue: Queue = .{ .shared = &shared, .searches = &.{}, .plains = plains, .workers = .{ .width = 1 } };
    var failure: ?Error = null;
    queue.drain(&failure);
    try std.testing.expectEqual(@as(?Error, error.WriteFailed), failure);
    try std.testing.expectEqual(report.Status.skipped, selected.verdict.status);
    try std.testing.expectEqual(@as(?[]const Pending, null), queue.next());
}

// spec-case: NEW-CORE-S3-RUNNER-1
test "removePrivate retires trial files and accepts an already absent directory" {
    var temp = std.testing.tmpDir(.{});
    defer temp.cleanup();
    const a = std.testing.allocator;
    const root = try temp.dir.realPathFileAlloc(std.testing.io, ".", a);
    defer a.free(root);
    const directory = try std.fs.path.join(a, &.{ root, "private" });
    defer a.free(directory);
    const file = try std.fs.path.join(a, &.{ directory, "trial.input" });
    defer a.free(file);
    const cwd = std.Io.Dir.cwd();
    try cwd.createDirPath(std.testing.io, directory);
    try cwd.writeFile(std.testing.io, .{ .sub_path = file, .data = "owned trial" });
    removePrivate(std.testing.io, directory);
    try std.testing.expectError(error.FileNotFound, cwd.openDir(std.testing.io, directory, .{}));
    removePrivate(std.testing.io, directory);
}
fn ordinaryReason(a: std.mem.Allocator, outcome: property_execute.Outcome) Error![]const u8 {
    var reason = outcome.diagnostics;
    if (std.mem.eql(u8, outcome.status, "value")) {
        const actual = outcome.actual;
        const text = if (actual == .bool) (if (actual.bool) "true" else "false") else try std.json.Stringify.valueAlloc(a, actual, .{});
        const expected = if (actual == .bool) "true" else "{\"case\":\"ok\",\"value\":true}";
        reason = try std.fmt.allocPrint(a, "expected {s}, got {s}", .{ expected, text });
        if (outcome.trace.len != 0) reason = try std.fmt.allocPrint(a, "{s}\n{s}", .{ reason, std.mem.trimEnd(u8, outcome.trace, "\n") });
    }
    if (outcome.output.len != 0) reason = try std.fmt.allocPrint(a, "{s}\n{s}", .{ reason, outcome.output });
    return reason;
}

fn testCampaignGuard(a: std.mem.Allocator, root: []const u8, environment: *const std.process.Environ.Map) !Campaign {
    const path = try std.fs.path.join(a, &.{ root, "app.my" });
    const inputs = try a.alloc(receipt.Dependency, 1);
    inputs[0] = .{ .path = path, .digest = try receipt.readDigest(a, std.testing.io, path) };
    return .{
        .context = .{
            .arena = a,
            .io = std.testing.io,
            .environment = environment,
            .options = .{ .path = path, .build = .{ .zig = "unselected-tool" } },
            .entry = .{ .path = path, .root = root, .name = "app" },
            .identity = .{ .tool = .{ .path = "unselected-tool", .digest = @splat(0), .generation = @splat(0), .native_target = @splat(0), .inputs = 0, .memo_hit = false } },
        },
        .inputs = inputs,
        .backing = a,
    };
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property checkpoint init and commit reject a changed source before loading or publishing progress" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "before" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const guard = try testCampaignGuard(a, root, &environment);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "after" });
    try std.testing.expect(!try guard.unchanged());
    try std.testing.expectError(error.SourceChanged, Checkpoint.init(guard, root, @splat(7), 32));
    var checkpoint: Checkpoint = .{ .guard = guard, .root = root, .key = @splat(7), .progress_arena = .init(std.testing.allocator) };
    defer checkpoint.deinit();
    try std.testing.expectError(error.SourceChanged, Checkpoint.commit(&checkpoint, .{ .next_ordinal = 1, .passed = 1 }));
    try std.testing.expect((try checkpoint.store(a).load(@splat(7), 32)) == null);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "property checkpoint source guard propagates ReadFailed instead of publishing unreadable inputs" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "app.my", .data = "before" });
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const guard = try testCampaignGuard(a, root, &environment);
    try temporary.dir.deleteFile(std.testing.io, "app.my");
    try temporary.dir.createDir(std.testing.io, "app.my", .default_dir);
    try std.testing.expectError(error.ReadFailed, guard.unchanged());
    try std.testing.expectError(error.ReadFailed, Checkpoint.init(guard, root, @splat(7), 32));
}
