//! The engine decides what `selka test` reuses. For every test the runner asks the engine whether a valid `test-exec` record
//! serves the argument this run built: before building, under the test's IR key (`ir`), and after the build, under the digest
//! of the linked program (`program`). A served pass is reused (the test is `cached`, with the work its record holds); anything
//! else runs, and its pass is recorded when the entry ends. An entry's report is replayed the same way, from a `test-report`
//! record, while every file its check read is as it was.
//!
//! **D-48 as a rule.** The engine is asked only with arguments this run produced: the IR key of the check that just ran, the
//! digest of the program that was just built, the settings and the keyed environment of this process, and the test's name.
//! They are built in one place (`engine_run.argumentOf`) from digests the call sites pass in by value; nothing here reads a
//! stored argument (a record's) to ask with. A record under a key the run did not produce is never reached, and an edit that
//! changes a test's program changes the key it is asked under. The one record that is served without such a key is the
//! entry's report (`replay`): its argument is the settings digest, the root and the filter, and the record's reads are every
//! file the check read, so it is served only while every one of them is as it was seen; a module source counts as it was
//! seen while its tokens are (`module-tokens`, D-TL6-1).
//!
//! **Checking a reuse.** When `SELKA_ENGINE_VERIFY=N` is set, one served record in N (by its key) is checked: the runner runs
//! the test anyway and `observe` compares the fresh verdict with the record; a fresh failure is a `verify` finding, counts in
//! `verdict_differs`, and removes the record (`Engine.forget`). A Debug compiler's default sampling is the engine's own and
//! does not check a run's reuses, so which tests a run reuses never depends on the keys it draws.
const std = @import("std");
const language = @import("selka");
const engine_run = @import("test_runner_engine.zig");
const notes_rules = @import("test_runner_notes.zig");
const receipt = @import("test_runner_receipt.zig");
const report = @import("test_runner_report.zig");
const run_tests = @import("test_runner_execute.zig");
const test_exec = @import("engine/kinds/test_exec.zig");
const frontend = @import("frontend.zig");
const discover = @import("test_runner_discover.zig");
const eligibility = @import("test_runner_eligibility.zig");

/// Why the runner reuses a test the engine served under its IR key.
pub const ir_reason = "engine-hit";
/// Why the runner reuses a test the engine served under the digest of its linked program.
pub const program_reason = "engine-program-hit";
/// Why a replayed test is `cached` when the engine served the entry's report.
pub const replay_reason = "engine-report-hit";

/// The state of the attached engine when it decides this run: the run is one the engine may reuse in (no force, no links,
/// no loader overrides, the legacy policy).
pub fn deciding(context: receipt.Context) ?*engine_run.State {
    const state = engine_run.attached() orelse return null;
    if (engine_run.modeOf(context) != .decide) return null;
    return state;
}

/// An entry's questions to the engine: the digests every argument of the run shares.
pub const Asker = struct {
    state: *engine_run.State,
    /// The entry's path as the run names it: the key of its notes.
    entry: []const u8,
    inputs: [32]u8,
    environment: [32]u8,
    /// What the shared tier's rule is applied to: the run's context and the program the tests come from. Without them
    /// (a bench) nothing is declared, and every record stays local.
    context: ?receipt.Context = null,
    checked: ?frontend.Checked = null,
    /// The shared tier rule's reading of `checked` in this run (`portable.Program`), given to what the entry declares.
    reading: ?*@import("test_runner_portable.zig").Program = null,

    /// Ask for the test `case` under its IR key `identity`, as `check` produced it.
    pub fn ir(self: Asker, a: std.mem.Allocator, case: discover.Case, identity: [32]u8) ?run_tests.Hit {
        return self.ask(a, 'i', &identity, case, null);
    }

    /// `ir`, telling the shared tier's rule whether every function the test reaches is `bare` (`test_runner_facts.bare`), as
    /// the key derivation found it: the rule then reads no program (D-T2-5).
    pub fn irKnown(self: Asker, a: std.mem.Allocator, case: discover.Case, identity: [32]u8, bare: ?bool) ?run_tests.Hit {
        return self.ask(a, 'i', &identity, case, bare);
    }

    /// Ask for the test `case` under the digest of the program the build just produced.
    pub fn program(self: Asker, a: std.mem.Allocator, case: discover.Case, program_key: [32]u8) ?run_tests.Hit {
        return self.ask(a, 'p', &program_key, case, null);
    }

    /// Declare to the shared tier's rule what the program arguments of the tests at `positions` are records of: a run
    /// records a pass under the program of every test it linked, also the ones the IR key already served.
    pub fn declarePrograms(self: Asker, a: std.mem.Allocator, chosen: []const run_tests.Selected, positions: []const usize, program_key: [32]u8) void {
        for (positions) |position| {
            const case = chosen[position].case;
            const argument = engine_run.argumentOf(a, .{ .tag = 'p', .basis = &program_key, .inputs = &self.inputs, .environment = &self.environment, .name = case.name }) catch continue;
            self.declare(argument, case, .program, null);
        }
    }

    fn declare(self: Asker, argument: []const u8, case: discover.Case, which: eligibility.Which, bare: ?bool) void {
        const context = self.context orelse return;
        const checked = self.checked orelse return;
        self.state.declare(argument, .{ .context = context, .checked = checked, .case = case, .which = which, .owner = self.entry, .bare = bare, .program = self.reading });
    }

    fn ask(self: Asker, a: std.mem.Allocator, tag: u8, basis: *const [32]u8, case: discover.Case, bare: ?bool) ?run_tests.Hit {
        const state = self.state;
        const argument = engine_run.argumentOf(a, .{ .tag = tag, .basis = basis, .inputs = &self.inputs, .environment = &self.environment, .name = case.name }) catch return null;
        self.declare(argument, case, if (tag == 'i') .ir else .program, bare);
        var change: notes_rules.Note = .{ .engine = .rerun };
        const served = state.runner.peek(&state.kinds.exec, argument) catch null;
        var hit: ?run_tests.Hit = null;
        if (served) |found| if (found.result.payload() catch null) |verdict| if (test_exec.isPass(verdict)) {
            const checked = state.checks(argument);
            change = .{ .engine = .reuse, .check = checked };
            if (!checked) hit = .{ .counts = countsOf(verdict), .reason = if (tag == 'i') ir_reason else program_reason };
        };
        state.notes().update(state.gpa, state.io, self.entry, case.name, change);
        return hit;
    }
};

/// The work a pass payload holds, as the report names it.
fn countsOf(payload: []const u8) ?report.Counts {
    const work = test_exec.workOf(payload) orelse return null;
    return .{ .steps = work.steps, .peak_bytes = work.peak_bytes };
}

/// The questions of `context`'s entry, when the engine decides its run. `settings` is the run's serialized execution
/// settings (`receipt.executionSettings`) and `checked` the program its tests come from, or null when the run's records stay
/// out of the shared tier (provider overlays, docstring examples). `program` is the rule's reading of `checked` for the run.
pub fn asker(context: receipt.Context, settings: []const u8, checked: ?frontend.Checked, program: ?*@import("test_runner_portable.zig").Program) ?Asker {
    const state = deciding(context) orelse return null;
    const environment = receipt.environmentDigest(context) catch return null;
    const inputs = receipt.executionInputs(context, settings) catch return null;
    return .{ .state = state, .entry = context.entry.path, .inputs = inputs, .environment = environment, .context = if (checked == null) null else context, .checked = checked, .reading = program };
}

/// The execution tier's view of the same questions: a function over an opaque `Asker`, so the executor imports none of this.
pub fn decider(holder: *const Asker) run_tests.Decider {
    return .{ .context = @constCast(holder), .program = askProgram };
}

fn askProgram(raw: *anyopaque, a: std.mem.Allocator, case: discover.Case, program_key: [32]u8) ?run_tests.Hit {
    const self: *const Asker = @ptrCast(@alignCast(raw));
    return self.program(a, case, program_key);
}

// --------------------------------------------------------------------------------------------------------- observing

/// Observe `entry` in the attached engine: settle each test the engine was asked about and record the verdicts of the tests
/// that ran or were reused, and publish the report of a complete run. Best effort: a failure to record is not a failure of
/// the run.
pub fn observeAttached(entry: engine_run.Entry) void {
    const state = engine_run.attached() orelse return;
    const began = std.Io.Timestamp.now(state.io, .awake);
    observe(state, entry);
    state.release(entry.context.entry.path);
    engine_run.spend(state, began);
}

/// Observe one entry.
pub fn observe(self: *engine_run.State, entry: engine_run.Entry) void {
    var scratch: std.heap.ArenaAllocator = .init(self.gpa);
    defer scratch.deinit();
    const a = scratch.allocator();
    const mode = engine_run.modeOf(entry.context);
    if (mode == .skip) return engine_run.add(self, .unobserved, entry.chosen.len);
    const arguments = engine_run.argumentsOf(a, entry) catch return;
    if (mode == .record_only) {
        engine_run.add(self, .unobserved, entry.chosen.len);
        return engine_run.learn(self, a, entry, arguments);
    }
    const path = receipt.entryPath(entry.context) catch return;
    publishReport(self, a, entry, path);
    for (entry.chosen, entry.verdicts, arguments) |item, verdict, args| {
        const note = self.notes().find(a, self.io, entry.context.entry.path, item.case.name) orelse continue;
        settle(self, a, .{ .path = path, .item = item, .verdict = verdict, .note = note }, args);
    }
}

/// A test as the settling sees it.
const Seen = struct { path: []const u8, item: run_tests.Selected, verdict: report.Verdict, note: notes_rules.Note };

/// Count what happened to one test, record its verdict, and log a checked record whose test now fails.
fn settle(self: *engine_run.State, a: std.mem.Allocator, seen: Seen, args: engine_run.Args) void {
    const note = seen.note;
    const name = seen.item.case.name;
    const status = seen.item.verdict.status;
    const failed = status == .failed;
    const reused = status == .cached and note.engine == .reuse;
    engine_run.count(self, .asked);
    if (reused) engine_run.count(self, .reused);
    if (status == .passed or failed) engine_run.count(self, .ran);
    if (note.check and (status == .passed or failed)) engine_run.count(self, .checked);
    // A test that passed, ran or reused, passes under every argument it has in this run: the one that served it is already
    // recorded, and the others (the program a reused test was linked into, the IR key of a test a program record served) are
    // recorded now, so the next run finds the test whichever way its key moved. A failure is never recorded, and removes
    // the pass a check found wrong.
    if (status == .passed or reused or failed) {
        const payload: ?[]const u8 = if (failed) null else engine_run.payloadOf(a, seen.verdict);
        if (engine_run.recordWith(self, args, payload) == .verify_failed) engine_run.verifyMismatch(self, a, seen.path, name);
    }
    if (note.check and failed) {
        engine_run.count(self, .verdict_differs);
        engine_run.finding(self, seen.path, name, "a served record was checked by running the test, and the test failed");
    }
}

// --------------------------------------------------------------------------------------------------------- the report

/// The magic line of a stored report.
const document_magic = "core-test-report-v2\n";

/// A stored report: the warnings its check printed, the files it reads (one a line), then the report itself, behind a magic
/// line and the lengths of the first two.
pub fn encodeDocument(a: std.mem.Allocator, found: engine_run.Report) std.mem.Allocator.Error![]const u8 {
    // The warnings keep, behind a marker, which of them `selka fix` repairs (`fix_tally.zig`), so a replay closes as the first run did.
    const warnings = try language.fix_tally.attach(a, found.warnings);
    return std.fmt.allocPrint(a, "{s}{d}\n{d}\n{s}{s}{s}", .{ document_magic, warnings.len, found.paths.len, warnings, found.paths, found.json });
}

/// The warnings, the files and the report a stored document holds, or null for any other bytes.
pub fn decodeDocument(payload: []const u8) ?engine_run.Report {
    if (!std.mem.startsWith(u8, payload, document_magic)) return null;
    var rest = payload[document_magic.len..];
    var lengths: [2]usize = undefined;
    for (&lengths) |*length| {
        const newline = std.mem.indexOfScalar(u8, rest, '\n') orelse return null;
        length.* = std.fmt.parseInt(usize, rest[0..newline], 10) catch return null;
        rest = rest[newline + 1 ..];
    }
    if (lengths[0] > rest.len or lengths[1] > rest.len - lengths[0]) return null;
    return .{ .warnings = language.fix_tally.detach(rest[0..lengths[0]]), .paths = rest[lengths[0]..][0..lengths[1]], .json = rest[lengths[0] + lengths[1] ..] };
}

/// Store the report of a complete, successful run, so the next run with the same settings and the same files replays it. A
/// report already served stays: it is replayed in the same form whichever run produced it, and verify mode never meets a
/// report that differs from the one stored.
fn publishReport(self: *engine_run.State, a: std.mem.Allocator, entry: engine_run.Entry, path: []const u8) void {
    var found = entry.report orelse return;
    const files = engine_run.reportFiles(a, entry) catch return;
    found.paths = std.mem.join(a, "\n", files) catch return;
    const payload = encodeDocument(a, found) catch return;
    publishUnder(self, a, .{ .argument = engine_run.reportArgumentOf(a, entry.context, entry.base, .bytes) catch return, .files = files, .payload = payload }, path);
    if (!engine_run.tokenReports(entry.context.environment)) return;
    const reads = engine_run.reportReads(a, entry) catch return;
    const argument = engine_run.reportArgumentOf(a, entry.context, entry.base, .tokens) catch return;
    if ((self.runner.peek(&self.kinds.report, argument) catch null) != null) return;
    engine_run.offerReport(self, argument, .{ .files = reads.files, .sources = reads.sources, .payload = payload });
    _ = engine_run.answerReport(self, a, argument, path);
}

/// Record the report `renewal` names under its argument, reading every one of its files by its bytes, unless a record is
/// there already.
fn publishUnder(self: *engine_run.State, a: std.mem.Allocator, renewal: receipt.Renewal, path: []const u8) void {
    if ((self.runner.peek(&self.kinds.report, renewal.argument) catch null) != null) return;
    engine_run.offerReport(self, renewal.argument, .{ .files = renewal.files, .payload = renewal.payload });
    _ = engine_run.answerReport(self, a, renewal.argument, path);
}

/// The report the engine serves for an entry whose run has the settings digest `base`, rendered as a replay (every test
/// `cached`), or null when none is stored or one of the files its check read changed. The caller validates the toolchain as
/// the receipts' replay did (`receipt.toolUnchanged`) where it must.
pub fn replay(context: receipt.Context, base: [32]u8) run_tests.Error!?receipt.Replay {
    const self = deciding(context) orelse return null;
    if (!receipt.replayAdmitted(context)) return null;
    const a = context.arena;
    // The record read by bytes first: an unchanged run validates it by the files' stat tuples alone (D-TL6-7).
    const bytes = engine_run.reportArgumentOf(a, context, base, .bytes) catch return null;
    if (self.runner.peek(&self.kinds.report, bytes) catch null) |served| {
        const stored = decodeDocument(served.result.payload() catch return null) orelse return null;
        return receipt.renderReplay(context, base, stored.json, stored.warnings, .{ .reason = replay_reason, .key_method = "engine-record" });
    }
    if (!engine_run.tokenReports(context.environment)) return null;
    const tokens = engine_run.reportArgumentOf(a, context, base, .tokens) catch return null;
    const served = self.runner.peek(&self.kinds.report, tokens) catch null;
    const payload = (served orelse return null).result.payload() catch return null;
    const stored = decodeDocument(payload) orelse return null;
    var replayed = try receipt.renderReplay(context, base, stored.json, stored.warnings, .{ .reason = replay_reason, .key_method = "engine-record" }) orelse return null;
    // The sources' tokens are as they were, so the report holds for the files as they are now: once the replay is accepted it
    // is recorded under their bytes too, and the next unchanged run finds it by their stat tuples again.
    var files: std.ArrayList([]const u8) = .empty;
    var lines = std.mem.splitScalar(u8, stored.paths, '\n');
    while (lines.next()) |line| if (line.len != 0) try files.append(a, line);
    replayed.renew = .{ .argument = bytes, .files = files.items, .payload = try a.dupe(u8, payload) };
    return replayed;
}

/// Count the tests of a replayed report, and record a report found through its sources' tokens under the files' bytes.
pub fn observeReplay(replayed: receipt.Replay) void {
    const self = engine_run.attached() orelse return;
    engine_run.add(self, .replayed, replayed.seen.tests);
    const renewal = replayed.renew orelse return;
    var scratch: std.heap.ArenaAllocator = .init(self.gpa);
    defer scratch.deinit();
    publishUnder(self, scratch.allocator(), renewal, "");
}

// ------------------------------------------------------------------------------------------------------------ tests

fn askerOn(bench: *engine_run.Bench) Asker {
    return .{ .state = bench.state, .entry = "lang.selka", .inputs = @splat(1), .environment = @splat(2) };
}

fn caseNamed(name: []const u8) discover.Case {
    return .{ .name = name, .function = @fromBackingInt(0), .shape = .boolean, .other_parameters = 0, .streams = &.{} };
}

fn selectedFor(name: []const u8, status: report.Status) run_tests.Selected {
    return .{
        .case = caseNamed(name),
        .verdict = .{ .name = name, .status = status },
        .ready = false,
    };
}

/// The two arguments `recordPass` records a pass under.
fn argsOf(questions: Asker, a: std.mem.Allocator, name: []const u8, ir: [32]u8, program: [32]u8) !engine_run.Args {
    return .{
        .ir = try engine_run.argumentOf(a, .{ .tag = 'i', .basis = &ir, .inputs = &questions.inputs, .environment = &questions.environment, .name = name }),
        .program = try engine_run.argumentOf(a, .{ .tag = 'p', .basis = &program, .inputs = &questions.inputs, .environment = &questions.environment, .name = name }),
    };
}

/// Record a pass of the test `name` under the IR key `ir` and the program `program` the way a run that executed it does.
fn recordPass(questions: Asker, a: std.mem.Allocator, name: []const u8, ir: [32]u8, program: [32]u8) !void {
    const args = try argsOf(questions, a, name, ir, program);
    const payload = try test_exec.payloadOf(a, .{ .steps = 7, .peak_bytes = 65536 });
    try std.testing.expect(engine_run.recordWith(questions.state, args, payload) != .verify_failed);
}

// spec: D-48
test "the engine serves a pass only under the arguments the run built: a key from before an edit finds nothing" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try engine_run.Bench.startWith(std.testing.allocator, "0");
    defer bench.deinit();
    const questions = askerOn(bench);
    const old_ir: [32]u8 = @splat(10);
    const new_ir: [32]u8 = @splat(11);
    const program: [32]u8 = @splat(20);
    // Nothing is recorded: the test runs.
    try std.testing.expect(questions.ir(a, caseNamed("lang::t"), old_ir) == null);
    try recordPass(questions, a, "lang::t", old_ir, program);
    // The key of the check that produced it serves the pass, with the work it reported.
    const hit = questions.ir(a, caseNamed("lang::t"), old_ir).?;
    try std.testing.expectEqualStrings(ir_reason, hit.reason);
    try std.testing.expectEqual(@as(u64, 65536), hit.counts.?.peak_bytes);
    // An edit moved the test's IR key. The old record is still in the store, and the new key finds nothing.
    try std.testing.expect(questions.ir(a, caseNamed("lang::t"), new_ir) == null);
    // The program that was linked has not changed: its digest serves, a program that changed finds nothing.
    try std.testing.expectEqualStrings(program_reason, questions.program(a, caseNamed("lang::t"), program).?.reason);
    try std.testing.expect(questions.program(a, caseNamed("lang::t"), @splat(21)) == null);
    // Another test, another settings digest and another environment are other arguments.
    try std.testing.expect(questions.ir(a, caseNamed("lang::u"), old_ir) == null);
    var other = questions;
    other.inputs = @splat(3);
    try std.testing.expect(other.ir(a, caseNamed("lang::t"), old_ir) == null);
    other = questions;
    other.environment = @splat(4);
    try std.testing.expect(other.program(a, caseNamed("lang::t"), program) == null);
}

test "a test the engine served is counted as reused, and one it did not serve as run" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try engine_run.Bench.startWith(std.testing.allocator, "0");
    defer bench.deinit();
    const questions = askerOn(bench);
    const state = bench.state;
    try recordPass(questions, a, "lang::served", @splat(1), @splat(2));
    _ = questions.ir(a, caseNamed("lang::served"), @splat(1)).?;
    try std.testing.expect(questions.ir(a, caseNamed("lang::ran"), @splat(3)) == null);
    const served = state.notes().find(a, state.io, "lang.selka", "lang::served").?;
    const ran = state.notes().find(a, state.io, "lang.selka", "lang::ran").?;
    settle(state, a, .{ .path = "lang.selka", .item = selectedFor("lang::served", .cached), .verdict = .{ .name = "lang::served", .status = .cached }, .note = served }, .{});
    settle(state, a, .{ .path = "lang.selka", .item = selectedFor("lang::ran", .passed), .verdict = .{ .name = "lang::ran", .status = .passed }, .note = ran }, .{ .ir = "i-ran" });
    try std.testing.expectEqual(@as(u64, 2), engine_run.tally(state, .asked));
    try std.testing.expectEqual(@as(u64, 1), engine_run.tally(state, .reused));
    try std.testing.expectEqual(@as(u64, 1), engine_run.tally(state, .ran));
    try std.testing.expectEqual(@as(u64, 0), engine_run.tally(state, .checked));
    // The pass that ran is recorded for the next run; nothing was logged.
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, "i-ran")) != null);
    try std.testing.expectEqual(@as(u64, 0), engine_run.tally(state, .verify));
}

test "verify mode runs a served test anyway, and a fresh failure is a finding that counts as a difference" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try engine_run.Bench.startWith(std.testing.allocator, "1");
    defer bench.deinit();
    const questions = askerOn(bench);
    const state = bench.state;
    try recordPass(questions, a, "lang::t", @splat(7), @splat(8));
    // Every record is checked: the engine serves the test, and the runner does not take the reuse without running it.
    try std.testing.expect(questions.ir(a, caseNamed("lang::t"), @splat(7)) == null);
    const note = state.notes().find(a, state.io, "lang.selka", "lang::t").?;
    try std.testing.expect(note.check);
    try std.testing.expectEqual(notes_rules.Choice.reuse, note.engine);
    // A checked test that passes again is run and counted; one that fails is a finding.
    settle(state, a, .{ .path = "lang.selka", .item = selectedFor("lang::t", .passed), .verdict = .{ .name = "lang::t", .status = .passed }, .note = note }, .{});
    try std.testing.expectEqual(@as(u64, 1), engine_run.tally(state, .checked));
    try std.testing.expectEqual(@as(u64, 0), engine_run.tally(state, .verify));
    settle(state, a, .{ .path = "lang.selka", .item = selectedFor("lang::t", .failed), .verdict = .{ .name = "lang::t", .status = .failed }, .note = note }, .{});
    try std.testing.expectEqual(@as(u64, 1), engine_run.tally(state, .verify));
    try std.testing.expectEqual(@as(u64, 1), engine_run.tally(state, .verdict_differs));
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, try bench.text(a), "\"class\":\"verify\""));
}

// spec: C2c1b
test "a seeded wrong record is served, the check fails, and the next run runs the test instead of serving it" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const bench = try engine_run.Bench.startWith(std.testing.allocator, "1");
    defer bench.deinit();
    const questions = askerOn(bench);
    const state = bench.state;
    const args = try argsOf(questions, a, "lang::t", @splat(1), @splat(2));
    // A record says the test passes, and it no longer does (the run that seeded it was wrong or the test changed under a key
    // that did not see it).
    try recordPass(questions, a, "lang::t", @splat(1), @splat(2));
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, args.ir.?)) != null);
    // The record is served: the check names it, and the runner runs the test anyway.
    try std.testing.expect(questions.ir(a, caseNamed("lang::t"), @splat(1)) == null);
    const note = state.notes().find(a, state.io, "lang.selka", "lang::t").?;
    try std.testing.expect(note.check and note.engine == .reuse);
    // The test fails: the check is a finding, and both records are gone.
    settle(state, a, .{ .path = "lang.selka", .item = selectedFor("lang::t", .failed), .verdict = .{ .name = "lang::t", .status = .failed }, .note = note }, args);
    try std.testing.expectEqual(@as(u64, 1), engine_run.tally(state, .verify));
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, args.ir.?)) == null);
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, args.program.?)) == null);
    // The next run asks again and nothing serves it: it runs the test.
    var next = questions;
    next.entry = "next.selka";
    try std.testing.expect(next.ir(a, caseNamed("lang::t"), @splat(1)) == null);
    try std.testing.expect(next.program(a, caseNamed("lang::t"), @splat(2)) == null);
    const again = state.notes().find(a, state.io, "next.selka", "lang::t").?;
    try std.testing.expectEqual(notes_rules.Choice.rerun, again.engine);
    try std.testing.expect(!again.check);
    // A later pass is recorded afresh.
    try recordPass(questions, a, "lang::t", @splat(1), @splat(2));
    try std.testing.expect((try state.runner.peek(&state.kinds.exec, args.ir.?)) != null);
}

test "a stored report round-trips with its warnings and refuses any other bytes" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const encoded = try encodeDocument(a, .{ .json = "{\"tests\":[]}\n", .warnings = "warning: w\n", .paths = "/p/a.selka\n/p/b.json" });
    const decoded = decodeDocument(encoded).?;
    try std.testing.expectEqualStrings("warning: w\n", decoded.warnings);
    try std.testing.expectEqualStrings("/p/a.selka\n/p/b.json", decoded.paths);
    try std.testing.expectEqualStrings("{\"tests\":[]}\n", decoded.json);
    const bare = decodeDocument(try encodeDocument(a, .{ .json = "x", .warnings = "" })).?;
    try std.testing.expectEqual(@as(usize, 0), bare.warnings.len);
    try std.testing.expectEqual(@as(?engine_run.Report, null), decodeDocument("lang::test_a\t61\n"));
    try std.testing.expectEqual(@as(?engine_run.Report, null), decodeDocument(document_magic ++ "9\n0\nshort"));
    try std.testing.expectEqual(@as(?engine_run.Report, null), decodeDocument(document_magic ++ "1\n9\nxshort"));
    try std.testing.expectEqual(@as(?engine_run.Report, null), decodeDocument(document_magic ++ "x\n"));
}
