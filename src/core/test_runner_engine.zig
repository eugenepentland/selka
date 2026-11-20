//! The engine of a `selka test` process: what decides which verdicts a run reuses, how it is asked, and what it records.
//!
//! One `State` per process holds an engine over the work directory, the two kinds (`test-exec`, `test-report`) and the
//! answers the runner computed that the kinds hand back (a kind's body does not run the test: the runner builds and runs a
//! selection's tests in processes of its own, so it decides before running, `Engine.peek`, and hands the verdict it found to the
//! kind when it records one). `test_runner_decide.zig` asks and compares; this file is the state, the arguments, the
//! recording and the log.
//!
//! The log holds one JSON line for each `verify` finding (a served record checked by running the test, and the test failed) and
//! one `summary` line per process with the counters of `Tally`; a log past 64 MiB takes no more lines.
const std = @import("std");
const product = @import("selka").product;
const language = @import("selka");
const engine = @import("engine/engine.zig");
const engine_kinds = @import("engine/kinds.zig");
const os_world = @import("engine/os_world.zig");
const shared_records = @import("engine/shared_records.zig");
const options_rules = @import("test_runner_options.zig");
const engine_command = @import("engine/command.zig");
const test_exec = @import("engine/kinds/test_exec.zig");
const test_report = @import("engine/kinds/test_report.zig");
const module_tokens = @import("engine/kinds/module_tokens.zig");
const test_facts = @import("engine/kinds/test_facts.zig");
const test_graph = @import("engine/kinds/test_graph.zig");
const test_records = @import("test_records.zig");
const context_rules = @import("engine/context.zig");
const report = @import("test_runner_report.zig");
const receipt = @import("test_runner_receipt.zig");
const run_tests = @import("test_runner_execute.zig");
const notes_rules = @import("test_runner_notes.zig");
const digest_rules = @import("engine/digest.zig");
const eligibility_rules = @import("test_runner_eligibility.zig");

/// The variable that switches the engine off (`0` or `off`): nothing is reused or recorded, every test runs. Any other
/// value, and no value, leave it on.
pub const switch_variable = "SELKA_ENGINE_SHADOW";
/// The variable naming the file findings are appended to; unset, `<cache-dir>/engine-v1/shadow.jsonl`.
pub const log_variable = "SELKA_ENGINE_SHADOW_LOG";
/// The variable naming the run: when set, every line the process writes carries it as `tag`, so a log shared by several
/// sessions can be read for one session's lines. It changes no result.
pub const tag_variable = "SELKA_ENGINE_SHADOW_TAG";
/// The variable that turns the report's token reads off (`0` or `off`, placement): a run then records and replays only the
/// report that reads every file by its bytes, as before stage 6 of the test-loop plan, which is the oracle of D-TL6-2.
pub const tokens_variable = "SELKA_TEST_TOKEN_REPORTS";

/// Whether a report reads its module sources through `module-tokens`: unless `tokens_variable` is `0` or `off`.
pub fn tokenReports(environment: *const std.process.Environ.Map) bool {
    const value = environment.get(tokens_variable) orelse return true;
    return !std.mem.eql(u8, value, "0") and !std.mem.eql(u8, value, "off");
}

/// The digest `module-tokens` records for a source: the runner's (`test_runner_tokens.zig`), so the kind names no front end.
const tokens_source: module_tokens.Source = .{ .digest = @import("test_runner_tokens.zig").digest };

/// A process writes at most this many finding lines; the rest are counted in its summary line.
pub const line_limit = 4000;

/// What the engine counts, per process.
pub const Tally = enum {
    /// Tests the engine was asked about: tests the runner could key.
    asked,
    /// Tests of entries the engine does not decide by policy (a forced run, a loader override, links): not asked.
    unobserved,
    /// Tests the engine served and the runner reused without running.
    reused,
    /// Tests the engine did not serve, which ran (a served record that verify mode chose to check counts here too).
    ran,
    /// Served records checked by running the test.
    checked,
    /// Tests reused by replaying a whole report.
    replayed,
    /// Findings: a checked record whose test now fails, or a query verify mode recomputed and got another result for.
    verify,
    /// Checked records whose test now fails.
    verdict_differs,
    /// Records the receipts' portability rule keeps out of the shared tier (counted when the rule is first applied).
    local_only,
    /// Finding lines dropped past `line_limit`.
    dropped,
    /// Microseconds spent observing, summed over the threads that did.
    spent_us,
};

const tally_count = std.enums.values(Tally).len;

/// What the runner computed that the kinds hand back, by the kind's argument, and the kinds' sources.
const Answers = struct {
    mutex: std.Io.Mutex = .init,
    arena: std.heap.ArenaAllocator,
    exec: std.StringHashMapUnmanaged([]const u8) = .empty,
    reports: std.StringHashMapUnmanaged(test_report.Answer) = .empty,
    sources: struct { exec: test_exec.Source, report: test_report.Source },
    /// One served `test-exec` record in this many (by key) is checked by running the test: `SELKA_ENGINE_VERIFY`, and not
    /// at all when it is unset. A Debug compiler's default sampling is the engine's own and does not check a run's reuses.
    check_every: u32,
    /// The decisions taken so far, by entry and test.
    notes: notes_rules.Notes,
};

/// The findings log and the counters.
const Sink = struct {
    mutex: std.Io.Mutex = .init,
    path: []const u8,
    /// The work directory, named in the summary line so a shared log tells the worktrees apart.
    work: []const u8,
    /// The run's tag (`tag_variable`), borrowed from the environment, or empty.
    tag: []const u8 = "",
    written: usize = 0,
    tallies: [tally_count]std.atomic.Value(u64) = @splat(.init(0)),
};

/// The values the runner offers the `test-facts` and `test-graph` kinds while it records one (a record's key, then its encoded
/// value), and the kinds' sources.
const Offers = struct {
    mutex: std.Io.Mutex = .init,
    facts: std.StringHashMapUnmanaged([]const u8) = .empty,
    graph: std.StringHashMapUnmanaged([]const u8) = .empty,
    sources: struct { facts: test_facts.Source, graph: test_graph.Source },
};

/// The kinds, as this process registers them (their data is this process's answers and offers).
const Kinds = struct { exec: context_rules.Kind, tokens: context_rules.Kind, report: context_rules.Kind, facts: context_rules.Kind, graph: context_rules.Kind, offers: Offers };

/// What the engine reads and writes outside its work directory: the machine, the per-user store of shared records, and
/// which records may use it.
const Machine = struct { os: os_world.OsWorld, records: ?shared_records.Records = null, eligibility: eligibility_rules.Table };

/// The engine of one process. Heap-allocated: the engine points into it and must not move.
pub const State = struct {
    gpa: std.mem.Allocator,
    io: std.Io,
    machine: Machine,
    runner: engine.Engine,
    kinds: Kinds,
    answers: Answers,
    sink: Sink,

    /// Free the engine, the answers and the state itself.
    pub fn deinit(self: *State) void {
        self.runner.deinit();
        freeOffers(self);
        self.answers.exec.deinit(self.gpa);
        self.answers.reports.deinit(self.gpa);
        self.answers.arena.deinit();
        self.answers.notes.deinit(self.gpa);
        self.machine.eligibility.deinit(self.gpa);
        self.gpa.free(self.sink.path);
        self.gpa.destroy(self);
    }

    /// Declare that the `test-exec` argument names a record of `subject`: the shared tier consults the receipts' portability
    /// rule for it, when it is first used (`test_runner_eligibility.zig`).
    pub fn declare(self: *State, argument: []const u8, subject: eligibility_rules.Subject) void {
        self.machine.eligibility.declare(self.gpa, self.io, argument, subject);
    }

    /// Drop what the run of the entry at `owner` declared.
    pub fn release(self: *State, owner: []const u8) void {
        self.machine.eligibility.release(self.gpa, self.io, owner);
    }

    /// Whether the runner checks a served record of `argument` by running the test: verify mode named in the environment
    /// samples one key in `check_every`.
    pub fn checks(self: *const State, argument: []const u8) bool {
        const every = self.answers.check_every;
        if (every == 0) return false;
        const key = digest_rules.key(self.kinds.exec.name, self.kinds.exec.identity, argument);
        return digest_rules.sample(key) % every == 0;
    }

    /// The decisions taken so far, by entry and test.
    pub fn notes(self: *State) *notes_rules.Notes {
        return &self.answers.notes;
    }
};

/// Start the engine of a process whose work directory is `cache`, or null when the environment switches it off or the engine
/// cannot start. The caller attaches it (`engine_session.attach`) and ends it with `end`.
pub fn begin(gpa: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, cache: []const u8, shared: ?[]const u8) ?*State {
    if (environment.get(switch_variable)) |value| {
        if (std.mem.eql(u8, value, "0") or std.mem.eql(u8, value, "off")) return null;
    }
    const self = gpa.create(State) catch return null;
    const path = logPath(gpa, environment, cache) catch {
        gpa.destroy(self);
        return null;
    };
    self.* = .{
        .gpa = gpa,
        .io = io,
        .machine = .{ .os = .{ .io = io, .environment = environment, .work = cache }, .eligibility = eligibility_rules.Table.init(gpa) },
        .runner = undefined,
        .kinds = .{ .exec = engine_kinds.test_exec, .tokens = engine_kinds.module_tokens, .report = engine_kinds.test_report, .facts = engine_kinds.test_facts, .graph = engine_kinds.test_graph, .offers = .{
            .sources = .{ .facts = .{ .context = self, .answer = factsAnswer }, .graph = .{ .context = self, .answer = graphAnswer } },
        } },
        .answers = .{ .arena = .init(gpa), .sources = .{
            .exec = .{ .context = self, .answer = execAnswer },
            .report = .{ .context = self, .answer = reportAnswer },
        }, .check_every = checkEvery(environment), .notes = notes_rules.Notes.init(gpa) },
        .sink = .{ .path = path, .work = cache, .tag = environment.get(tag_variable) orelse "" },
    };
    self.kinds.exec.data = &self.answers.sources.exec;
    self.kinds.tokens.data = &tokens_source;
    self.answers.sources.report.tokens = &self.kinds.tokens;
    self.kinds.report.data = &self.answers.sources.report;
    self.kinds.facts.data = &self.kinds.offers.sources.facts;
    self.kinds.graph.data = &self.kinds.offers.sources.graph;
    if (options_rules.sharedCache(shared, environment)) |directory| {
        self.machine.records = shared_records.Records.open(self.answers.arena.allocator(), io, directory) catch null;
    }
    self.runner = engine.Engine.init(gpa, io, self.machine.os.world(), .{
        .work = cache,
        .verify_every = engine_command.verifyEvery(environment),
        .timing = language.engine_session.reportRequested(),
        .shared = if (self.machine.records) |*records| records.tier() else null,
    }) catch {
        self.answers.arena.deinit();
        self.answers.notes.deinit(gpa);
        self.machine.eligibility.deinit(gpa);
        gpa.free(path);
        gpa.destroy(self);
        return null;
    };
    self.runner.register(&self.kinds.exec) catch return discard(self);
    self.runner.register(&self.kinds.tokens) catch return discard(self);
    self.runner.register(&self.kinds.report) catch return discard(self);
    self.runner.register(&self.kinds.facts) catch return discard(self);
    self.runner.register(&self.kinds.graph) catch return discard(self);
    self.runner.share(&self.kinds.exec, .{ .context = self, .allows = shareAllows });
    // The planning records are content-addressed (a key is the digest of what the value depends on) and name the entry by its
    // root-relative path, so another tree's record is the same query. The graph's head is replaced by `forget` and a new answer,
    // which removes it from the tier as well. A record whose payload is an object stays local: this tier keeps records only.
    self.runner.share(&self.kinds.facts, null);
    self.runner.share(&self.kinds.graph, null);
    return self;
}

/// How often the runner checks a served record by running the test: `SELKA_ENGINE_VERIFY=N` checks one in N, an unset or
/// malformed value none.
fn checkEvery(environment: *const std.process.Environ.Map) u32 {
    const value = environment.get(engine_command.verify_variable) orelse return 0;
    return std.fmt.parseInt(u32, value, 10) catch 0;
}

/// The shared tier's filter: a record of a test the receipts' portability rule keeps private stays local.
fn shareAllows(raw: *anyopaque, argument: []const u8) bool {
    const self: *State = @ptrCast(@alignCast(raw));
    const decision = self.machine.eligibility.decide(self.gpa, self.io, argument);
    if (decision.newly_local) count(self, .local_only);
    return decision.allowed;
}

fn discard(self: *State) ?*State {
    self.runner.deinit();
    self.answers.arena.deinit();
    self.answers.notes.deinit(self.gpa);
    self.machine.eligibility.deinit(self.gpa);
    self.gpa.free(self.sink.path);
    self.gpa.destroy(self);
    return null;
}

/// The value of the log variable that names the per-user log: `$XDG_CACHE_HOME/selka/engine-shadow/shadow.jsonl` when
/// `XDG_CACHE_HOME` is absolute, else `$HOME/.cache/selka/engine-shadow/shadow.jsonl`. The gate and the edit check use it
/// because `env` cannot expand `~`.
pub const user_log = "@user";

fn logPath(gpa: std.mem.Allocator, environment: *const std.process.Environ.Map, cache: []const u8) std.mem.Allocator.Error![]const u8 {
    const named = environment.get(log_variable) orelse "";
    if (std.mem.eql(u8, named, user_log)) if (userLog(gpa, environment)) |path| return path else |_| {};
    if (named.len != 0 and !std.mem.eql(u8, named, user_log)) return gpa.dupe(u8, named);
    return std.fmt.allocPrint(gpa, "{s}/engine-v1/shadow.jsonl", .{cache});
}

fn userLog(gpa: std.mem.Allocator, environment: *const std.process.Environ.Map) error{ OutOfMemory, NoHome }![]const u8 {
    if (environment.get("XDG_CACHE_HOME")) |base| if (std.fs.path.isAbsolute(base)) return std.fs.path.join(gpa, &.{ base, product.user_dir, "engine-shadow", "shadow.jsonl" });
    const home = environment.get("HOME") orelse return error.NoHome;
    if (!std.fs.path.isAbsolute(home)) return error.NoHome;
    return std.fs.path.join(gpa, &.{ home, ".cache", product.user_dir, "engine-shadow", "shadow.jsonl" });
}

/// End the engine: write the process's summary line, print the engine report when the command asked for it, and free it.
pub fn end(self: *State, io: std.Io) void {
    language.engine_session.attach(null);
    summarize(self);
    if (language.engine_session.reportRequested()) printReport(self, io);
    self.deinit();
}

fn printReport(self: *State, io: std.Io) void {
    var buffer: [4096]u8 = undefined;
    var writer = std.Io.File.stderr().writer(io, &buffer);
    self.runner.report(&writer.interface) catch return;
    writer.interface.flush() catch return;
}

/// Count one `which`.
pub fn count(self: *State, which: Tally) void {
    add(self, which, 1);
}

/// Count `by` of `which`.
pub fn add(self: *State, which: Tally, by: u64) void {
    _ = self.sink.tallies[@backingInt(which)].fetchAdd(by, .monotonic);
}

/// How many `which` the process has counted.
pub fn tally(self: *State, which: Tally) u64 {
    return self.sink.tallies[@backingInt(which)].load(.monotonic);
}

// ------------------------------------------------------------------------------------------------- the kinds' sources

fn execAnswer(raw: *anyopaque, argument: []const u8) ?[]const u8 {
    const self: *State = @ptrCast(@alignCast(raw));
    self.answers.mutex.lockUncancelable(self.io);
    defer self.answers.mutex.unlock(self.io);
    return self.answers.exec.get(argument);
}

fn reportAnswer(raw: *anyopaque, argument: []const u8) ?test_report.Answer {
    const self: *State = @ptrCast(@alignCast(raw));
    self.answers.mutex.lockUncancelable(self.io);
    defer self.answers.mutex.unlock(self.io);
    return self.answers.reports.get(argument);
}

fn offerExec(self: *State, argument: []const u8, payload: []const u8) void {
    self.answers.mutex.lockUncancelable(self.io);
    defer self.answers.mutex.unlock(self.io);
    const a = self.answers.arena.allocator();
    const key = a.dupe(u8, argument) catch return;
    self.answers.exec.put(self.gpa, key, payload) catch return;
}

fn withdrawExec(self: *State, argument: []const u8) void {
    self.answers.mutex.lockUncancelable(self.io);
    defer self.answers.mutex.unlock(self.io);
    _ = self.answers.exec.remove(argument);
}

/// Hand the `test-report` kind the answer for `argument`: the files its check read and the report document it stores.
pub fn offerReport(self: *State, argument: []const u8, answer: test_report.Answer) void {
    self.answers.mutex.lockUncancelable(self.io);
    defer self.answers.mutex.unlock(self.io);
    const a = self.answers.arena.allocator();
    const key = a.dupe(u8, argument) catch return;
    const files = a.alloc([]const u8, answer.files.len) catch return;
    for (answer.files, files) |path, *slot| slot.* = a.dupe(u8, path) catch return;
    const sources = a.alloc([]const u8, answer.sources.len) catch return;
    for (answer.sources, sources) |path, *slot| slot.* = a.dupe(u8, path) catch return;
    const payload = a.dupe(u8, answer.payload) catch return;
    self.answers.reports.put(self.gpa, key, .{ .files = files, .sources = sources, .payload = payload }) catch return;
}

// -------------------------------------------------------------------------------------------- the planning records

const Record = test_records.Which;

/// The planning records of the engine attached to this process, or none: the runner's facts and graph reach the engine only
/// through this table (`test_records.zig` is a leaf of the test-runner stage).
pub fn planning() test_records.Records {
    const state = attached() orelse return .none;
    return planningOf(state);
}

/// The planning records of `state`.
pub fn planningOf(state: *State) test_records.Records {
    return .{ .context = state, .vtable = &record_table };
}

const record_table: test_records.Vtable = .{ .load = loadThrough, .save = saveThrough };

fn loadThrough(raw: *anyopaque, a: std.mem.Allocator, which: Record, key: *const [32]u8) ?[]const u8 {
    const self: *State = @ptrCast(@alignCast(raw));
    return loadRecord(self, a, which, key);
}

fn saveThrough(raw: *anyopaque, which: Record, key: *const [32]u8, bytes: []const u8, replace: bool) bool {
    const self: *State = @ptrCast(@alignCast(raw));
    return saveRecord(self, which, key, bytes, replace);
}

fn kindOf(self: *State, which: Record) *context_rules.Kind {
    return switch (which) {
        .facts => &self.kinds.facts,
        .graph => &self.kinds.graph,
    };
}

fn offersOf(self: *State, which: Record) *std.StringHashMapUnmanaged([]const u8) {
    return switch (which) {
        .facts => &self.kinds.offers.facts,
        .graph => &self.kinds.offers.graph,
    };
}

fn factsAnswer(raw: *anyopaque, argument: []const u8) ?[]const u8 {
    const self: *State = @ptrCast(@alignCast(raw));
    self.kinds.offers.mutex.lockUncancelable(self.io);
    defer self.kinds.offers.mutex.unlock(self.io);
    return self.kinds.offers.facts.get(argument);
}

fn graphAnswer(raw: *anyopaque, argument: []const u8) ?[]const u8 {
    const self: *State = @ptrCast(@alignCast(raw));
    self.kinds.offers.mutex.lockUncancelable(self.io);
    defer self.kinds.offers.mutex.unlock(self.io);
    return self.kinds.offers.graph.get(argument);
}

fn freeOffers(self: *State) void {
    inline for (.{ .facts, .graph }) |which| {
        var offers = offersOf(self, which);
        var entries = offers.iterator();
        while (entries.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        offers.deinit(self.gpa);
    }
}

/// The value recorded under the 32-byte `key` for `which`, copied into `a`, or null when no valid record serves it. A record the
/// engine cannot read is a miss: the runner then computes the value, as it does for a key it never recorded.
pub fn loadRecord(self: *State, a: std.mem.Allocator, which: Record, key: *const [32]u8) ?[]const u8 {
    const answered = (self.runner.peek(kindOf(self, which), key) catch return null) orelse return null;
    const payload = answered.result.payload() catch return null;
    return a.dupe(u8, payload) catch null;
}

/// Record `value` under `key` for `which`. A record already there stays (the keys are of immutable values) unless `replace`,
/// which makes `value` the record. True when the engine holds a record under the key afterwards.
pub fn saveRecord(self: *State, which: Record, key: *const [32]u8, value: []const u8, replace: bool) bool {
    const kind = kindOf(self, which);
    if (replace) {
        self.runner.forget(kind, key);
    } else if ((self.runner.peek(kind, key) catch null) != null) return true;
    const owned_key = self.gpa.dupe(u8, key) catch return false;
    const owned_value = self.gpa.dupe(u8, value) catch {
        self.gpa.free(owned_key);
        return false;
    };
    {
        self.kinds.offers.mutex.lockUncancelable(self.io);
        defer self.kinds.offers.mutex.unlock(self.io);
        const offers = offersOf(self, which);
        const slot = offers.getOrPut(self.gpa, owned_key) catch {
            self.gpa.free(owned_key);
            self.gpa.free(owned_value);
            return false;
        };
        if (slot.found_existing) {
            self.gpa.free(owned_key);
            self.gpa.free(slot.value_ptr.*);
        }
        slot.value_ptr.* = owned_value;
    }
    defer withdrawRecord(self, which, key);
    _ = self.runner.answer(kind, key) catch return false;
    return true;
}

fn withdrawRecord(self: *State, which: Record, key: *const [32]u8) void {
    self.kinds.offers.mutex.lockUncancelable(self.io);
    defer self.kinds.offers.mutex.unlock(self.io);
    const removed = offersOf(self, which).fetchRemove(key) orelse return;
    self.gpa.free(removed.key);
    self.gpa.free(removed.value);
}

// ------------------------------------------------------------------------------------------------------- the log

/// One line of the log.
const Line = struct {
    v: u8 = 1,
    class: []const u8,
    @"test": ?[]const u8 = null,
    entry: []const u8,
    detail: ?[]const u8 = null,
    /// The run's tag, set by `emit` when the run has one.
    tag: ?[]const u8 = null,
};

/// Count `which` and append `line` to the log.
fn emit(self: *State, which: Tally, line: Line) void {
    count(self, which);
    var scratch: std.heap.ArenaAllocator = .init(self.gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var tagged = line;
    if (self.sink.tag.len != 0) tagged.tag = self.sink.tag;
    const text = std.json.Stringify.valueAlloc(a, tagged, .{ .emit_null_optional_fields = false }) catch return;
    write(self, a, text);
}

/// A finding: a served record that a run of the test `name` of `entry` found wrong, or a query verify mode recomputed. It
/// counts under `verify` and is logged with `detail`.
pub fn finding(self: *State, entry: []const u8, name: ?[]const u8, detail: []const u8) void {
    emit(self, .verify, .{ .class = "verify", .@"test" = name, .entry = entry, .detail = detail });
}

fn write(self: *State, a: std.mem.Allocator, text: []const u8) void {
    self.sink.mutex.lockUncancelable(self.io);
    defer self.sink.mutex.unlock(self.io);
    if (self.sink.written >= line_limit) return count(self, .dropped);
    self.sink.written += 1;
    const line = std.fmt.allocPrint(a, "{s}\n", .{text}) catch return;
    appendLine(self.io, self.sink.path, line, log_limit_bytes);
}

/// A log that has grown past this many bytes takes no more lines: the reader rotates it.
pub const log_limit_bytes = 64 << 20;

/// Append `line` to `path` under an advisory lock, creating the file and its directory, unless the file already holds
/// `limit` bytes.
fn appendLine(io: std.Io, path: []const u8, line: []const u8, limit: u64) void {
    if (std.fs.path.dirname(path)) |directory| std.Io.Dir.cwd().createDirPath(io, directory) catch return;
    const file = std.Io.Dir.cwd().createFile(io, path, .{ .truncate = false, .read = true }) catch return;
    defer file.close(io);
    const locked = if (file.lock(io, .exclusive)) true else |_| false;
    defer if (locked) file.unlock(io);
    const offset = file.length(io) catch return;
    if (offset >= limit) return;
    file.writePositionalAll(io, line, offset) catch return;
}

fn summarize(self: *State) void {
    if (tally(self, .asked) + tally(self, .replayed) + tally(self, .unobserved) == 0) return;
    var scratch: std.heap.ArenaAllocator = .init(self.gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    var text: std.ArrayList(u8) = .empty;
    text.print(a, "{{\"v\":1,\"class\":\"summary\",\"pid\":{d},\"work\":{f}", .{ std.os.linux.getpid(), std.json.fmt(self.sink.work, .{}) }) catch return;
    for (std.enums.values(Tally)) |which| text.print(a, ",\"{s}\":{d}", .{ @tagName(which), tally(self, which) }) catch return;
    if (self.sink.tag.len != 0) text.print(a, ",\"tag\":{f}", .{std.json.fmt(self.sink.tag, .{})}) catch return;
    text.append(a, '}') catch return;
    appendLine(self.io, self.sink.path, std.fmt.allocPrint(a, "{s}\n", .{text.items}) catch return, log_limit_bytes);
}

// ----------------------------------------------------------------------------------------------------- observing

/// The report a complete, successful run produced, and the warnings its check printed: what a later run replays. `diagnostics`
/// is what the check printed (not stored): a module any of it or of `warnings` names is read by its bytes (`reportReads`), and
/// so is every module `examples` names (`name:` a line, not stored): a docstring example's key holds the lines its program
/// maps back to, so a line shift moves it.
/// `paths` (stored) are the files the report reads, one a line, so that a replay found through the sources' tokens can record
/// the report again under the files' bytes (D-TL6-7).
pub const Report = struct { json: []const u8, warnings: []const u8, diagnostics: []const u8 = "", paths: []const u8 = "", examples: []const u8 = "" };

/// The two records of an entry's report (D-TL6-7): one that reads every file by its bytes, which an unchanged run finds by the
/// files' stat tuples alone, and one that reads module sources through `module-tokens`, which a comment edit or a line shift
/// leaves valid. Only the first is kept when `tokens_variable` is off.
pub const ReportReads = enum { bytes, tokens };

/// What one entry's run hands the engine after its tests have run.
pub const Entry = struct {
    context: receipt.Context,
    base: [32]u8,
    dependencies: []const receipt.Dependency,
    chosen: []const run_tests.Selected,
    verdicts: []const report.Verdict,
    executions: []const run_tests.Executed,
    /// The report a later run may replay, when this run was complete and successful and the policy lets it be replayed.
    report: ?Report = null,
};

/// The engine attached to this process, if there is one.
pub fn attached() ?*State {
    const raw = language.engine_session.current() orelse return null;
    return @ptrCast(@alignCast(raw));
}

/// Add the time since `began` to the observing time.
pub fn spend(self: *State, began: std.Io.Timestamp) void {
    spendBetween(self, began, std.Io.Timestamp.now(self.io, .awake));
}

fn spendBetween(self: *State, began: std.Io.Timestamp, ended: std.Io.Timestamp) void {
    const spent = began.durationTo(ended);
    add(self, .spent_us, @intCast(@max(0, @divTrunc(spent.nanoseconds, std.time.ns_per_us))));
}

/// Log a verify-mode mismatch, the one failure of a query the engine reports as a finding of its own: a kind's answer
/// changed while every read it made still saw the same.
pub fn verifyMismatch(self: *State, a: std.mem.Allocator, entry: []const u8, name: ?[]const u8) void {
    const detail = self.runner.lastMismatch(a) catch "verify mismatch";
    finding(self, entry, name, detail);
}

/// What the engine does with a run.
pub const Mode = enum {
    /// The engine decides what the run reuses and records its passes.
    decide,
    /// A forced run: nothing is reused, but its passes are true and the engine records them, so the first unforced run after a
    /// forced gate finds a warm store.
    record_only,
    /// A run the engine does not decide (narrowed by git state, refused by admission, not the legacy policy).
    skip,
};

/// What the engine does with a run of `context`.
pub fn modeOf(context: receipt.Context) Mode {
    var unforced = context;
    unforced.options.controls.force = false;
    const admitted = context.options.controls.scope.against == null and receipt.executionReusable(unforced);
    if (!admitted or context.options.properties.policy != .legacy) return .skip;
    return if (context.options.controls.force) .record_only else .decide;
}

/// Record the passes of a forced run, with the work each reported.
pub fn learn(self: *State, a: std.mem.Allocator, entry: Entry, arguments: []const Args) void {
    for (entry.chosen, entry.verdicts, arguments) |item, verdict, args| {
        if (item.verdict.status == .passed) _ = recordWith(self, args, payloadOf(a, verdict));
    }
}

/// The record payload of a pass whose verdict reported `verdict.details.counts`.
pub fn payloadOf(a: std.mem.Allocator, verdict: report.Verdict) []const u8 {
    const counts = verdict.details.counts orelse return test_exec.passed;
    return test_exec.payloadOf(a, .{ .steps = counts.steps, .peak_bytes = counts.peak_bytes }) catch test_exec.passed;
}

/// The two `test-exec` arguments a test can be asked under, each `tag || basis || inputs || environment || name`, the
/// digests 32 bytes each. `ir` (tag `i`) is the test's IR key (`Selected.identity`), which every test the runner can reuse
/// has, linked or not; `program` (tag `p`) is the digest of the linked program, which only a test consulted at the execution
/// tier has. A record under either says the test passed there; D-42 argues why either can only be served when the program it
/// would link is the one the record saw.
pub const Args = struct { ir: ?[]const u8 = null, program: ?[]const u8 = null };

/// What a `test-exec` argument is made of: the basis (the IR key or the program key), the run's settings digest, its keyed
/// environment's digest and the test's name.
pub const Parts = struct { tag: u8, basis: *const [32]u8, inputs: *const [32]u8, environment: *const [32]u8, name: []const u8 };

/// The one place a `test-exec` argument is built, `tag || basis || inputs || environment || name`. Every site that asks the
/// engine about a test, or records its verdict, builds the argument here from the digests of the current run: there is no
/// way to ask under a stored or guessed key (D-48).
pub fn argumentOf(a: std.mem.Allocator, parts: Parts) std.mem.Allocator.Error![]const u8 {
    return std.mem.concat(a, u8, &.{ &.{parts.tag}, parts.basis, parts.inputs, parts.environment, parts.name });
}

/// Each chosen test's arguments for this run: the settings digest, the keyed environment's digest, the IR key, and the
/// program key of the linked program that ran it.
pub fn argumentsOf(a: std.mem.Allocator, entry: Entry) std.mem.Allocator.Error![]Args {
    const out = try a.alloc(Args, entry.chosen.len);
    @memset(out, .{});
    const environment = try receipt.environmentDigest(entry.context);
    if (receipt.executionSettings(entry.context)) |settings| {
        const inputs = try receipt.executionInputs(entry.context, settings);
        for (entry.chosen, out) |item, *slot| {
            const identity = item.identity orelse continue;
            slot.ir = try argumentOf(a, .{ .tag = 'i', .basis = &identity, .inputs = &inputs, .environment = &environment, .name = item.case.name });
        }
    } else |_| {}
    for (entry.executions) |executed| {
        const inputs = try receipt.executionInputs(entry.context, executed.settings);
        for (executed.positions) |position| {
            out[position].program = try argumentOf(a, .{ .tag = 'p', .basis = &executed.program_key, .inputs = &inputs, .environment = &environment, .name = entry.chosen[position].case.name });
        }
    }
    return out;
}

/// Answer the report query for `argument`, logging a verify-mode mismatch against `path`; null when it could not be answered.
pub fn answerReport(self: *State, a: std.mem.Allocator, argument: []const u8, path: []const u8) ?engine.Answer {
    return self.runner.answer(&self.kinds.report, argument) catch |err| {
        if (err == error.VerifyMismatch) verifyMismatch(self, a, path, null);
        return null;
    };
}

/// The `test-report` argument of an entry: its settings digest, its root as an absolute path, and what decides which tests
/// the report lists: the entry's root-relative path (the settings leave it out, D-TL2-1), the name filter, and the modules a
/// directory run left to other roots (D-TL2-2 of experiments/test-loop-20261109/DECISIONS.md).
pub fn reportArgumentOf(a: std.mem.Allocator, context: receipt.Context, base: [32]u8, reads: ReportReads) @import("test_runner_property.zig").Error![]const u8 {
    const root = context.entry.root;
    const absolute = std.Io.Dir.cwd().realPathFileAlloc(context.io, root, a) catch root;
    var parts: std.ArrayList([]const u8) = .empty;
    try parts.appendSlice(a, &.{ &base, absolute, "\x00", try receipt.entryPath(context), "\x00", context.options.filter, "\x00" });
    if (context.options.controls.scope.skipped) |modules| {
        try parts.append(a, "skipping");
        for (modules) |module| try parts.appendSlice(a, &.{ "\x00", module });
    } else try parts.append(a, "every");
    // A report read through `module-tokens` and one read by bytes are two records (D-TL6-7).
    try parts.append(a, if (reads == .tokens) "\x00tokens" else "\x00bytes");
    return std.mem.concat(a, u8, parts.items);
}

/// The files the front end read to check the entry, as absolute paths without repeats.
pub fn reportFiles(a: std.mem.Allocator, entry: Entry) std.mem.Allocator.Error![]const []const u8 {
    const cwd = std.Io.Dir.cwd().realPathFileAlloc(entry.context.io, ".", a) catch return &.{};
    var files: std.ArrayList([]const u8) = .empty;
    for (entry.dependencies) |dependency| {
        const absolute = try std.fs.path.resolve(a, &.{ cwd, dependency.path });
        var present = false;
        for (files.items) |known| present = present or std.mem.eql(u8, known, absolute);
        if (!present) try files.append(a, absolute);
    }
    return files.items;
}

/// What a report reads: `files` by their bytes, `sources` through `module-tokens`.
pub const Reads = struct { files: []const []const u8, sources: []const []const u8 };

/// The reads of `entry`'s token record (D-TL6-1): a module source (`.selka`) through `module-tokens`, unless the oracle switch is off,
/// the module holds a docstring example the run tested (D-TL6-8), or what the check printed names it (a warning's text holds its line, its column and its source line, which a comment edit
/// or a line shift moves); every other file by its bytes (the cases file, the configuration, embedded assets, interface files).
pub fn reportReads(a: std.mem.Allocator, entry: Entry) std.mem.Allocator.Error!Reads {
    const all = try reportFiles(a, entry);
    if (!tokenReports(entry.context.environment)) return .{ .files = all, .sources = &.{} };
    const printed: []const []const u8 = if (entry.report) |found| &.{ found.warnings, found.diagnostics, found.examples } else &.{};
    var files: std.ArrayList([]const u8) = .empty;
    var sources: std.ArrayList([]const u8) = .empty;
    for (all) |path| {
        var named = false;
        for (printed) |text| named = named or mentions(text, std.fs.path.basename(path));
        try (if (product.isSource(path) and !named) &sources else &files).append(a, path);
    }
    return .{ .files = files.items, .sources = sources.items };
}

/// Whether `text` names the file `name` as a diagnostic does, `name:` after the start of a line, a space or a separator.
/// It may name more files than the diagnostics point into (another directory's file of the same name), which only reads
/// that file by its bytes.
fn mentions(text: []const u8, name: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, text, from, name)) |at| : (from = at + 1) {
        const before_ok = at == 0 or std.mem.indexOfScalar(u8, "\n\r\t /\\", text[at - 1]) != null;
        const after = at + name.len;
        if (before_ok and after < text.len and text[after] == ':') return true;
    }
    return false;
}

// spec-case: TEST-LOOP-TOKEN-REPORTS-1
test "a module a printed diagnostic names is read by its bytes, and only a name followed by a colon counts" {
    const printed = "eval/instance.selka:43:7: warning[W_TEST]: text\n      code\nnoise.selka:3:11: warning[W_TEST]: more\n";
    try std.testing.expect(mentions(printed, "instance.selka"));
    try std.testing.expect(mentions(printed, "noise.selka"));
    try std.testing.expect(!mentions(printed, "env.selka"));
    try std.testing.expect(!mentions(printed, "code"));
    try std.testing.expect(!mentions("see lib.selka for more", "lib.selka"));
    try std.testing.expect(mentions("/abs/path/lib.selka:1:1: warning", "lib.selka"));
}

/// How the fresh verdict compared with the record the engine served.
pub const Recorded = enum { stored, same, differs, absent, verify_failed };

/// Hand the engine the verdict a run found under each of the test's arguments and let it record a pass (the arguments name
/// exactly what the run keyed); when it serves a record instead, say whether the record's verdict is the one the run found.
/// A failure is withdrawn, never recorded or served.
pub fn record(self: *State, args: Args, passed: bool) Recorded {
    return recordWith(self, args, if (passed) test_exec.passed else null);
}

/// `record` for a pass that carries its work: `payload` is the record's payload (`test_exec.payloadOf`), null for a failure.
pub fn recordWith(self: *State, args: Args, payload: ?[]const u8) Recorded {
    var result: Recorded = .absent;
    for ([_]?[]const u8{ args.program, args.ir }) |candidate| {
        const own = candidate orelse continue;
        if (payload) |offered| offerExec(self, own, offered) else withdrawExec(self, own);
        const answered = self.runner.answer(&self.kinds.exec, own) catch |err| {
            if (err == error.VerifyMismatch) return .verify_failed;
            continue;
        };
        const served = answered.result.payload() catch |err| {
            if (err == error.VerifyMismatch) return .verify_failed;
            continue;
        };
        const here: Recorded = if (answered.origin == .recomputed) .stored else if (test_exec.isPass(served) == (payload != null)) .same else .differs;
        // A served pass that the test now fails is wrong: forget it, so no later run serves it again.
        if (here == .differs and payload == null) self.runner.forget(&self.kinds.exec, own);
        if (here == .differs or result == .absent) result = here;
    }
    return result;
}

// ------------------------------------------------------------------------------------------------------------ tests

/// An engine over a temporary work directory whose log is `shadow.jsonl` beside it.
pub const Bench = struct {
    gpa: std.mem.Allocator,
    temporary: std.testing.TmpDir,
    environment: std.process.Environ.Map,
    state: *State,
    work: []const u8,
    log: []const u8,

    /// What starting a bench can fail on.
    pub const StartError = std.mem.Allocator.Error || std.Io.Dir.RealPathFileAllocError;

    /// A bench whose runner checks every served record (`SELKA_ENGINE_VERIFY=1`).
    pub fn start(gpa: std.mem.Allocator) StartError!*Bench {
        return startWith(gpa, "1");
    }

    /// A bench with `SELKA_ENGINE_VERIFY=verify`.
    pub fn startWith(gpa: std.mem.Allocator, verify: []const u8) StartError!*Bench {
        const self = try gpa.create(Bench);
        self.gpa = gpa;
        self.temporary = std.testing.tmpDir(.{});
        const real = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", gpa);
        defer gpa.free(real);
        self.work = try gpa.dupe(u8, real);
        self.log = try std.fmt.allocPrint(gpa, "{s}/shadow.jsonl", .{self.work});
        self.environment = .init(gpa);
        try self.environment.put(log_variable, self.log);
        try self.environment.put("SELKA_ENGINE_VERIFY", verify);
        try self.environment.put(tag_variable, "bench");
        self.state = begin(gpa, std.testing.io, &self.environment, self.work, null).?;
        return self;
    }

    /// End the engine and free the bench.
    pub fn deinit(self: *Bench) void {
        end(self.state, std.testing.io);
        self.environment.deinit();
        self.gpa.free(self.log);
        self.gpa.free(self.work);
        self.temporary.cleanup();
        self.gpa.destroy(self);
    }

    /// The log's text.
    pub fn text(self: *Bench, a: std.mem.Allocator) std.Io.Dir.ReadFileAllocError![]const u8 {
        return std.Io.Dir.cwd().readFileAlloc(std.testing.io, self.log, a, .limited(1 << 20));
    }
};

test "the engine opens the shared tier named by the test store's directory and shares test-exec and the planning records, not the report or the tokens" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const work = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(work);
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    const state = begin(std.testing.allocator, std.testing.io, &environment, work, work).?;
    defer state.deinit();
    try std.testing.expect(state.machine.records != null);
    // In the order `begin` registers them: test-exec, module-tokens, test-report, test-facts, test-graph.
    try std.testing.expect(state.runner.registry.entries[0].shared);
    try std.testing.expect(!state.runner.registry.entries[1].shared);
    try std.testing.expect(!state.runner.registry.entries[2].shared);
    try std.testing.expect(state.runner.registry.entries[3].shared);
    try std.testing.expect(state.runner.registry.entries[4].shared);
    const without = begin(std.testing.allocator, std.testing.io, &environment, work, "").?;
    defer without.deinit();
    try std.testing.expect(without.machine.records == null);
    try std.testing.expect(without.runner.setup.config.shared == null);
}

test "the time spent observing is counted in microseconds and never negative" {
    const bench = try Bench.start(std.testing.allocator);
    spendBetween(bench.state, .{ .nanoseconds = 1_000 }, .{ .nanoseconds = 3_501_000 });
    spendBetween(bench.state, .{ .nanoseconds = 9_000 }, .{ .nanoseconds = 1_000 });
    try std.testing.expectEqual(@as(u64, 3500), tally(bench.state, .spent_us));
    bench.deinit();
}

test "a pass is recorded under both keys of a test, and either one serves the next run" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const bench = try Bench.startWith(std.testing.allocator, "0");
    defer bench.deinit();
    const state = bench.state;
    const first: Args = .{ .ir = "i-key", .program = "p-key" };
    try std.testing.expectEqual(Recorded.stored, record(state, first, true));
    // The same test under the same keys is served the record: the pass is the same.
    try std.testing.expectEqual(Recorded.same, record(state, first, true));
    // A compiler edit moved the IR key; the program key still serves.
    const moved: Args = .{ .ir = "i-key-2", .program = "p-key" };
    try std.testing.expectEqual(Recorded.differs, record(state, .{ .program = "p-key" }, false));
    try std.testing.expectEqual(Recorded.stored, record(state, moved, true));
    // A failing test is never recorded, whatever it was keyed by.
    try std.testing.expectEqual(Recorded.absent, record(state, .{ .ir = "i-key-3" }, false));
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, "i-key-3")) == null);
}

test "a pass that carries its work is served with the work" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try Bench.startWith(std.testing.allocator, "0");
    defer bench.deinit();
    const state = bench.state;
    const verdict: report.Verdict = .{ .name = "t", .status = .passed, .details = .{ .counts = .{ .steps = 9, .peak_bytes = 65536 } } };
    _ = recordWith(state, .{ .ir = "k" }, payloadOf(a, verdict));
    const served = (try state.runner.peek(&state.kinds.exec, "k")).?;
    try std.testing.expectEqual(@as(u64, 9), test_exec.workOf(try served.result.payload()).?.steps);
}

test "the passes of a forced run are recorded so the next unforced run finds the engine warm" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try Bench.startWith(std.testing.allocator, "0");
    defer bench.deinit();
    const state = bench.state;
    const passing: run_tests.Selected = .{
        .case = .{ .name = "lang::test_a", .function = @fromBackingInt(0), .shape = .boolean, .other_parameters = 0, .streams = &.{} },
        .verdict = .{ .name = "lang::test_a", .status = .passed },
        .ready = false,
    };
    var failing = passing;
    failing.case.name = "lang::test_b";
    failing.verdict = .{ .name = "lang::test_b", .status = .failed };
    const chosen = [_]run_tests.Selected{ passing, failing };
    const verdicts = [_]report.Verdict{ passing.verdict, failing.verdict };
    const entry: Entry = .{ .context = undefined, .base = @splat(0), .dependencies = &.{}, .chosen = &chosen, .verdicts = &verdicts, .executions = &.{} };
    learn(state, a, entry, &.{ .{ .program = "program-a" }, .{ .program = "program-b" } });
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, "program-a")) != null);
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, "program-b")) == null);
}

test "a finding is logged with its entry and test, counted, and the log takes no more past its limit" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try Bench.startWith(std.testing.allocator, "0");
    defer bench.deinit();
    finding(bench.state, "lang.selka", "lang::t", "the test failed");
    try std.testing.expectEqual(@as(u64, 1), tally(bench.state, .verify));
    const logged = try bench.text(a);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, logged, "\"class\":\"verify\""));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, logged, "\"tag\":\"bench\""));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, logged, "\"test\":\"lang::t\""));
}

test "a log that has reached its size limit takes no more lines" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const real = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    const path = try std.fmt.allocPrint(a, "{s}/nested/log.jsonl", .{real});
    appendLine(std.testing.io, path, "first\n", 8);
    appendLine(std.testing.io, path, "second\n", 8);
    appendLine(std.testing.io, path, "third\n", 8);
    const text = try std.Io.Dir.cwd().readFileAlloc(std.testing.io, path, a, .limited(1 << 10));
    try std.testing.expectEqualStrings("first\nsecond\n", text);
}

test "the engine is off when the environment says so, and logs where the variable points" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    try environment.put(switch_variable, "off");
    try std.testing.expectEqual(@as(?*State, null), begin(std.testing.allocator, std.testing.io, &environment, "work", null));
    try std.testing.expectEqualStrings("work/engine-v1/shadow.jsonl", try logPath(a, &environment, "work"));
    try environment.put(log_variable, "elsewhere.jsonl");
    try std.testing.expectEqualStrings("elsewhere.jsonl", try logPath(a, &environment, "work"));
    // `@user` is the per-user log: under an absolute XDG_CACHE_HOME, else under HOME, else the work directory's own.
    try environment.put(log_variable, user_log);
    try std.testing.expectEqualStrings("work/engine-v1/shadow.jsonl", try logPath(a, &environment, "work"));
    try std.testing.expectError(error.NoHome, userLog(a, &environment));
    try environment.put("HOME", "/home/someone");
    try std.testing.expectEqualStrings("/home/someone/.cache/selka/engine-shadow/shadow.jsonl", try logPath(a, &environment, "work"));
    try environment.put("XDG_CACHE_HOME", "/xdg");
    try std.testing.expectEqualStrings("/xdg/selka/engine-shadow/shadow.jsonl", try logPath(a, &environment, "work"));
}

test "a served record is checked by running the test only when the environment names verify mode, one key in N" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    try std.testing.expectEqual(@as(u32, 0), checkEvery(&environment));
    try environment.put("SELKA_ENGINE_VERIFY", "16");
    try std.testing.expectEqual(@as(u32, 16), checkEvery(&environment));
    try environment.put("SELKA_ENGINE_VERIFY", "many");
    try std.testing.expectEqual(@as(u32, 0), checkEvery(&environment));
    const every = try Bench.startWith(std.testing.allocator, "1");
    defer every.deinit();
    const never = try Bench.startWith(std.testing.allocator, "0");
    defer never.deinit();
    try std.testing.expect(every.state.checks("any argument"));
    try std.testing.expect(!never.state.checks("any argument"));
}

test "verify mode finding a served report that the same files no longer give is a finding of its own" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try Bench.startWith(std.testing.allocator, "1");
    defer bench.deinit();
    const state = bench.state;
    // Two reports are stored; the files are as they were, but the run now produces other reports: verify mode recomputes
    // each served record, and finds it does not reproduce.
    offerReport(state, "first argument", .{ .files = &.{}, .payload = "first report" });
    offerReport(state, "second argument", .{ .files = &.{}, .payload = "second report" });
    try std.testing.expect(answerReport(state, a, "first argument", "lang.selka") != null);
    try std.testing.expect(answerReport(state, a, "second argument", "lang.selka") != null);
    offerReport(state, "first argument", .{ .files = &.{}, .payload = "another first report" });
    offerReport(state, "second argument", .{ .files = &.{}, .payload = "another second report" });
    state.runner.newRevision();
    try std.testing.expectError(error.VerifyMismatch, state.runner.answer(&state.kinds.report, "second argument"));
    try std.testing.expect(answerReport(state, a, "first argument", "lang.selka") == null);
    try std.testing.expectEqual(@as(u64, 1), tally(state, .verify));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, try bench.text(a), "\"class\":\"verify\""));
}

test "G4e the planning records keep a value under its key for the next process, replace it on request, and miss for a key never recorded" {
    var bench = try Bench.start(std.testing.allocator);
    defer bench.deinit();
    const records = planningOf(bench.state);
    const key: [32]u8 = @splat(1);
    try std.testing.expect(records.save(.facts, &key, "one", false));
    const first = records.load(std.testing.allocator, .facts, &key).?;
    defer std.testing.allocator.free(first);
    try std.testing.expectEqualStrings("one", first);
    // A record already there stays unless the caller replaces it; the other kind and another key hold nothing.
    try std.testing.expect(records.save(.facts, &key, "two", false));
    const kept = records.load(std.testing.allocator, .facts, &key).?;
    defer std.testing.allocator.free(kept);
    try std.testing.expectEqualStrings("one", kept);
    try std.testing.expect(records.save(.facts, &key, "two", true));
    const replaced = records.load(std.testing.allocator, .facts, &key).?;
    defer std.testing.allocator.free(replaced);
    try std.testing.expectEqualStrings("two", replaced);
    try std.testing.expect(records.load(std.testing.allocator, .graph, &key) == null);
    try std.testing.expect(records.load(std.testing.allocator, .facts, &@as([32]u8, @splat(9))) == null);
    // Another process over the same work directory finds what this one recorded.
    const later = begin(std.testing.allocator, std.testing.io, &bench.environment, bench.work, null).?;
    defer end(later, std.testing.io);
    const found = planningOf(later).load(std.testing.allocator, .facts, &key).?;
    defer std.testing.allocator.free(found);
    try std.testing.expectEqualStrings("two", found);
}

test "G4e a process with no engine records no planning value and finds none" {
    const none: test_records.Records = .none;
    const key: [32]u8 = @splat(3);
    try std.testing.expect(!none.save(.graph, &key, "value", true));
    try std.testing.expect(none.load(std.testing.allocator, .graph, &key) == null);
}

test "G4c a planning value one work directory recorded is found from another through the shared tier, and a replaced head replaces the shared one" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var environment: std.process.Environ.Map = .init(a);
    const shared = try std.fs.path.join(a, &.{ root, "shared" });
    const fact: [32]u8 = @splat(1);
    const head: [32]u8 = @splat(2);
    const first = begin(std.testing.allocator, std.testing.io, &environment, try std.fs.path.join(a, &.{ root, "one" }), shared).?;
    defer end(first, std.testing.io);
    try std.testing.expect(planningOf(first).save(.facts, &fact, "a fact", false));
    try std.testing.expect(planningOf(first).save(.graph, &head, "generation 1", false));
    const second = begin(std.testing.allocator, std.testing.io, &environment, try std.fs.path.join(a, &.{ root, "two" }), shared).?;
    defer end(second, std.testing.io);
    const seen = planningOf(second).load(a, .facts, &fact).?;
    try std.testing.expectEqualStrings("a fact", seen);
    try std.testing.expectEqualStrings("generation 1", planningOf(second).load(a, .graph, &head).?);
    // The second tree replaces the head: a third finds the new generation, not the one the first published.
    try std.testing.expect(planningOf(second).save(.graph, &head, "generation 2", true));
    const third = begin(std.testing.allocator, std.testing.io, &environment, try std.fs.path.join(a, &.{ root, "three" }), shared).?;
    defer end(third, std.testing.io);
    try std.testing.expectEqualStrings("generation 2", planningOf(third).load(a, .graph, &head).?);
    // A tree with no tier sees neither.
    const alone = begin(std.testing.allocator, std.testing.io, &environment, try std.fs.path.join(a, &.{ root, "four" }), "").?;
    defer end(alone, std.testing.io);
    try std.testing.expect(planningOf(alone).load(a, .facts, &fact) == null);
}
