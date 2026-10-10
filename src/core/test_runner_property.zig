//! Core-owned port of native_test_property generation/trial/shrink accounting.
//! Property tests (PROPERTY-TEST-1..4). A discovered `test_` function with
//! data parameters and no cases-file `arguments` runs against generated
//! inputs: every input is drawn from the parameter types by a stream seeded
//! from the test's seed and run number, many inputs run in one native process,
//! an input that breaks the test's own precondition is discarded, and the first
//! failing input is shrunk to a minimal counterexample the report prints as
//! mylang literals with the seed, the run and a reproduction command.
const std = @import("std");
const fs = @import("property_execute.zig");
const v = @import("property_value.zig");
const execute = @import("property_execute.zig");
const types = @import("property_types.zig");
const generate = @import("property_generate.zig");
const shrink = @import("property_shrink.zig");
const render = @import("property_render.zig");
const Value = std.json.Value;

/// Generated inputs a property must pass when `--property-runs` names none.
pub const default_runs = 100;
/// Discarded inputs, as a multiple of the requested runs, after which a
/// property fails instead of drawing more.
pub const discard_factor = 10;
/// Shrink candidates one failure may execute before its search stops.
pub const shrink_budget = 2000;
/// Shrink candidates the first batch of a parameter's candidates runs; each
/// later batch without a failing candidate doubles, up to `shrink_chunk`.
/// Most steps adopt one of the first few candidates, so a small first batch
/// wastes few executions and a growing one bounds the process launches.
const shrink_first = 8;
const shrink_chunk = 128;
/// Copied nodes one batch request may carry before the rest wait for the next.
const batch_nodes = 500_000;
/// Property setup, generation and execution failures.
pub const Error = execute.Error || render.Error || error{ComponentUnavailable};

/// The run's identity: the seed inputs are drawn from, how many must pass,
/// and the entry path the reproduction command names.
pub const Settings = struct { seed: u64, runs: u32 = default_runs, entry: []const u8 = "" };
/// One data parameter the generator fills.
const Parameter = struct { name: []const u8, type: []const u8 };
/// One generated input: its run number, a value per data parameter, and the
/// copied nodes a batch carries it as.
const Input = struct { run: usize, values: []const Value, nodes: []const u64 };

/// How a property ended: passed or failed, the failure text, and the
/// evidence the JSON report carries as the result's `property` object.
pub const Verdict = struct { passed: bool, reason: []const u8 = "", evidence: Evidence };
/// What one property run did, and for a falsified property its counterexample.
pub const Evidence = struct { seed: u64, counts: Counts, failure: ?*const Failure = null };
/// How much work one property did: the runs asked for, the inputs that passed
/// and were discarded, the batch processes it started, and its shrinking.
pub const Counts = struct { runs: usize, passed: usize = 0, discarded: usize = 0, processes: usize = 0, shrinks: usize = 0, attempts: usize = 0 };
/// A falsified property's counterexample.
pub const Failure = struct {
    /// The zero-based run whose input failed first.
    run: usize,
    /// The shrunk input: typed JSON arguments (a cases-file `arguments`
    /// object) and each parameter's literal spelling.
    minimal: Rendered,
    /// The input as generated, before shrinking.
    original: Rendered,
    reason: []const u8,
    reproduce: []const u8,
    /// False when the input ran out of time: every candidate could take as
    /// long, so the input is reported as generated.
    shrunk: bool = true,
    /// Why the input as generated failed, when that differs from `reason`:
    /// shrinking keeps any failing candidate, not only one that fails alike.
    first_reason: []const u8 = "",
};
/// One input as typed JSON arguments and as literal source, both keyed by parameter.
pub const Rendered = struct { arguments: Value, literals: Value };

/// A bound property, or why its signature cannot be generated.
pub const Setup = union(enum) { ready: Property, invalid: []const u8 };
/// How one executed input counts: a pass, a failure, or a discard naming the
/// precondition it broke.
const Class = union(enum) { pass, fail: []const u8, discard: []const u8 };

/// One property test's run: the library that executes it, the checked
/// function, the schema and the parameters inputs are drawn for.
pub const Property = struct {
    context: fs.Context,
    executor: *const execute.Executor,
    function: Value,
    limits: execute.Limits,
    settings: Settings,
    schema: types.Schema,
    parameters: []const Parameter,

    /// Bind one discovered property test to its library, or name why its
    /// signature cannot be generated: a parameter whose type is refused, or a
    /// result that is not `bool` or `Result[bool, E]`.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    pub fn bind(context: fs.Context, executor: *const execute.Executor, function: Value, limits: execute.Limits, settings: Settings) Error!Setup {
        const a = context.arena;
        const schema = try types.Schema.init(a, executor.types);
        var parameters: std.ArrayList(Parameter) = .empty;
        for (v.array(v.get(function, "parameters"))) |parameter| {
            const type_name = v.text(v.get(parameter, "type"));
            if (injected(type_name)) continue;
            const name = v.text(v.get(parameter, "name"));
            if (try types.refused(schema, type_name)) |found| return .{ .invalid = try refusedText(a, name, type_name, found) };
            try parameters.append(a, .{ .name = name, .type = type_name });
        }
        const result = v.text(v.get(function, "result"));
        if (!types.verdict(schema, result)) return .{ .invalid = try std.fmt.allocPrint(a, non_bool_result, .{result}) };
        return .{ .ready = .{ .context = context, .executor = executor, .function = function, .limits = limits, .settings = settings, .schema = schema, .parameters = parameters.items } };
    }
    /// The first batch: the inputs of every requested run, which the command
    /// executes beside every other property's first batch.
    pub fn first(self: *Property, search: *Search) Error!execute.BatchCall {
        search.processes += 1;
        return self.draw(search, self.settings.runs);
    }
    /// The evidence of a run so far, with any shrinking counts.
    fn tally(self: *Property, search: *Search, shrunk: Shrunk) Evidence {
        return .{ .seed = self.settings.seed, .counts = .{
            .runs = self.settings.runs,
            .passed = search.passed,
            .discarded = search.discarded,
            .processes = search.processes,
            .shrinks = shrunk.steps,
            .attempts = shrunk.attempts,
        } };
    }
    /// Classify the first batch's outcomes, draw more inputs while discards
    /// leave runs to fill, and shrink the first failure.
    pub fn finish(self: *Property, search: *Search, outcome: execute.BatchOutcome) Error!Verdict {
        var answer = outcome;
        const runs: usize = self.settings.runs;
        while (true) {
            if (try self.absorb(search, answer)) |verdict| return verdict;
            if (search.passed >= runs) return .{ .passed = true, .evidence = self.tally(search, .{ .values = &.{}, .reason = "" }) };
            if (search.discarded > discard_factor * runs) return self.exhausted(search);
            answer = try self.one(search, try self.draw(search, self.refill(search)));
        }
    }
    /// How many more inputs to draw: the runs still missing, scaled by the
    /// share of inputs that have passed so far, and never more than the
    /// discards the property has left.
    fn refill(self: *Property, search: *Search) usize {
        const runs: usize = self.settings.runs;
        const missing = runs - search.passed;
        const scaled = if (search.passed == 0) missing * 4 else (missing * search.next_run + search.passed - 1) / search.passed;
        return @max(1, @min(scaled, discard_factor * runs + missing - @min(search.discarded, discard_factor * runs)));
    }
    /// Generate up to `wanted` inputs from the next run on, bounded by the
    /// batch's input and node limits, and encode them into one batch call.
    // twin-drift-ok: Core carries each copied node as two words, so count pairs against the unchanged node ceiling.
    fn draw(self: *Property, search: *Search, wanted: usize) Error!execute.BatchCall {
        const a = self.context.arena;
        var inputs: std.ArrayList(Input) = .empty;
        var nodes: usize = 0;
        while (inputs.items.len < @min(wanted, execute.batch_limit) and nodes < batch_nodes) {
            const input = try self.generated(search.next_run);
            search.next_run += 1;
            nodes += input.nodes.len / 2;
            try inputs.append(a, input);
        }
        search.batch = inputs.items;
        return self.call(inputs.items);
    }
    /// One batch call carrying these inputs.
    fn call(self: *Property, inputs: []const Input) Error!execute.BatchCall {
        const encoded = try self.context.arena.alloc([]const u64, inputs.len);
        for (encoded, inputs) |*slot, input| slot.* = input.nodes;
        return .{ .executor = self.executor, .function = self.function, .inputs = encoded };
    }
    /// The input of one run: every data parameter drawn from the run's own stream.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn generated(self: *Property, run: usize) Error!Input {
        const a = self.context.arena;
        var generator: generate.Generator = .{
            .arena = a,
            .schema = self.schema,
            .stream = .init(self.settings.seed, run),
            .size = generate.sizeOf(run, self.settings.runs),
        };
        const values = try a.alloc(Value, self.parameters.len);
        for (values, self.parameters) |*slot, parameter| slot.* = try generator.value(parameter.type, 0);
        return .{ .run = run, .values = values, .nodes = try self.encode(values) };
    }
    fn encode(self: *Property, values: []const Value) Error![]const u64 {
        return self.executor.encode(self.function, try self.arguments(values));
    }
    /// The named typed JSON arguments of one input, as a cases file spells them.
    fn arguments(self: *Property, values: []const Value) Error!Value {
        var object: std.json.ObjectMap = .empty;
        for (self.parameters, values) |parameter, value| try object.put(self.context.arena, parameter.name, value);
        return .{ .object = object };
    }
    /// Run one batch call in its own process.
    fn one(self: *Property, search: *Search, batch: execute.BatchCall) Error!execute.BatchOutcome {
        search.processes += 1;
        const answered = try execute.executeBatches(self.context, &.{batch}, self.limits, 1);
        return answered[0];
    }
    /// Count one batch's outcomes in input order. A child that died before
    /// answering every input is asked again for the input it died on, alone,
    /// and then for the rest in a new batch. The first failure ends the
    /// search in a verdict.
    fn absorb(self: *Property, search: *Search, outcome: execute.BatchOutcome) Error!?Verdict {
        const batch = search.batch;
        var answer = outcome;
        var offset: usize = 0;
        while (true) {
            if (try self.count(search, batch[offset..][0..answer.outcomes.len], answer.outcomes)) |verdict| return verdict;
            offset += answer.outcomes.len;
            if (offset >= batch.len or search.passed >= self.settings.runs) return null;
            const died = batch[offset .. offset + 1];
            const alone = try self.one(search, try self.call(died));
            if (alone.outcomes.len == 0) {
                const verdict = try self.falsified(search, died[0], .{ .reason = try self.ending(alone), .shrink = !alone.timed_out });
                return verdict;
            }
            if (try self.count(search, died, alone.outcomes)) |verdict| return verdict;
            offset += 1;
            if (offset >= batch.len) return null;
            answer = try self.one(search, try self.call(batch[offset..]));
        }
    }
    /// Classify answered inputs in order until the runs are full or one fails.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn count(self: *Property, search: *Search, inputs: []const Input, outcomes: []const execute.Outcome) Error!?Verdict {
        for (outcomes, inputs) |result, input| {
            if (search.passed >= self.settings.runs) return null;
            switch (try self.classify(result)) {
                .pass => search.passed += 1,
                .discard => |clause| {
                    try search.discard(self.context.arena, clause);
                    if (search.discarded > discard_factor * @as(usize, self.settings.runs)) {
                        const verdict = try self.exhausted(search);
                        return verdict;
                    }
                },
                .fail => |reason| {
                    const verdict = try self.falsified(search, input, .{ .reason = reason });
                    return verdict;
                },
            }
        }
        return null;
    }
    fn ending(self: *Property, outcome: execute.BatchOutcome) Error![]const u8 {
        if (outcome.timed_out) return std.fmt.allocPrint(self.context.arena, "the input ran past --timeout-ms {d}", .{self.limits.timeout_ms});
        return std.fmt.allocPrint(self.context.arena, "the test process ended without answering: {s}", .{outcome.ending});
    }
    /// A pass is `True` or `Ok(True)`. A trap of the test's own `@requires`
    /// (its innermost frame is the test itself), or a decoded input invariant,
    /// is a discard; every other
    /// trap, `False`, `Ok(False)` and `Err(...)` is a failure.
    // twin-drift-ok: Preserve old verdict and discard grading; the independent Core port borrows its command arena.
    fn classify(self: *Property, outcome: execute.Outcome) Error!Class {
        const name = v.text(v.get(self.function, "name"));
        if (std.mem.eql(u8, outcome.status, "trap")) {
            const own = std.mem.eql(u8, outcome.trap.code, "R_REQUIRES") and std.mem.eql(u8, outcome.trap.frame, name);
            // Reserved compiler-generated frame names identify decode validation,
            // before the selected test body runs. Source cannot declare one.
            const decoded = std.mem.eql(u8, outcome.trap.code, "R_INVARIANT") and std.mem.startsWith(u8, outcome.trap.frame, "@invariant:");
            if (own or decoded) return .{ .discard = outcome.trap.message };
            return .{ .fail = try self.withOutput(std.mem.trimEnd(u8, outcome.diagnostics, "\n"), outcome.output) };
        }
        if (!std.mem.eql(u8, outcome.status, "value")) return .{ .fail = try self.withOutput(std.mem.trimEnd(u8, outcome.diagnostics, "\n"), outcome.output) };
        const actual = outcome.actual;
        if (actual == .bool) return if (actual.bool) .pass else .{ .fail = try self.withOutput("returned False", outcome.output) };
        const verdict = v.get(actual, "value");
        if (std.mem.eql(u8, v.text(v.get(actual, "case")), "ok")) {
            return if (verdict == .bool and verdict.bool) .pass else .{ .fail = try self.withOutput("returned Ok(False)", outcome.output) };
        }
        const renderer: render.Renderer = .{ .schema = self.schema, .module = self.module() };
        const result = v.text(v.get(self.function, "result"));
        const spelled = try renderer.literal(self.context.arena, result, actual);
        // ERROR-TRACE-3: an `Err` says where it was created and propagated.
        const trace = std.mem.trimEnd(u8, outcome.trace, "\n");
        const returned = if (trace.len == 0)
            try std.fmt.allocPrint(self.context.arena, "returned {s}", .{spelled})
        else
            try std.fmt.allocPrint(self.context.arena, "returned {s}\nerror return trace:\n{s}", .{ spelled, trace });
        return .{ .fail = try self.withOutput(returned, outcome.output) };
    }
    fn withOutput(self: *Property, reason: []const u8, output: []const u8) Error![]const u8 {
        if (output.len == 0) return reason;
        return std.fmt.allocPrint(self.context.arena, "{s}\n{s}", .{ reason, output });
    }
    /// The module part of the test's qualified name.
    fn module(self: *Property) []const u8 {
        const name = v.text(v.get(self.function, "name"));
        return name[0 .. std.mem.indexOf(u8, name, "::") orelse 0];
    }
    /// Too many inputs broke a precondition to reach the requested runs.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn exhausted(self: *Property, search: *Search) Error!Verdict {
        const a = self.context.arena;
        var clause: []const u8 = "";
        var most: usize = 0;
        var iterator = search.clauses.iterator();
        while (iterator.next()) |entry| if (entry.value_ptr.* > most) {
            most = entry.value_ptr.*;
            clause = entry.key_ptr.*;
        };
        const reason = try std.fmt.allocPrint(a, "too many discarded inputs: {d} of {d} generated inputs broke a precondition before {d} of {d} runs passed; most often {s}\n  reproduce: {s}", .{
            search.discarded, search.discarded + search.passed, search.passed, self.settings.runs, clause, try self.reproduction(),
        });
        return .{ .passed = false, .reason = reason, .evidence = self.tally(search, .{ .values = &.{}, .reason = "" }) };
    }
    /// Shrink a failing input and build the report. An input that ran out of
    /// time is reported as generated: every candidate could take as long.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn falsified(self: *Property, search: *Search, input: Input, cause: Cause) Error!Verdict {
        var shrunk: Shrunk = .{ .values = input.values, .reason = cause.reason };
        if (cause.shrink) try self.minimize(search, &shrunk);
        const a = self.context.arena;
        const failure = try a.create(Failure);
        failure.* = .{
            .run = input.run,
            .minimal = try self.rendered(shrunk.values),
            .original = try self.rendered(input.values),
            .reason = shrunk.reason,
            .reproduce = try self.reproduction(),
            .shrunk = cause.shrink,
            .first_reason = if (std.mem.eql(u8, shrunk.reason, cause.reason)) "" else cause.reason,
        };
        var counted = self.tally(search, shrunk);
        counted.failure = failure;
        return .{ .passed = false, .reason = try self.describe(counted), .evidence = counted };
    }
    /// Greedy shrinking: shrink each parameter in turn for as long as one of
    /// its simpler candidates, run in order, still fails; repeat the pass
    /// while any parameter changed, and stop at a pass with no change or when
    /// the attempt budget is spent.
    // twin-drift-ok: Preserve old shrink ordering and budgets; the independent Core port borrows its command arena.
    fn minimize(self: *Property, search: *Search, shrunk: *Shrunk) Error!void {
        var changed = true;
        while (changed and shrunk.attempts < shrink_budget) {
            changed = false;
            for (self.parameters, 0..) |parameter, index| {
                while (shrunk.attempts < shrink_budget) {
                    var candidates: shrink.Candidates = .{ .arena = self.context.arena, .schema = self.schema };
                    try candidates.of(parameter.type, shrunk.values[index]);
                    if (!try self.firstFailing(search, shrunk, .{ .index = index, .candidates = candidates.items.items })) break;
                    changed = true;
                }
            }
        }
    }
    /// Try one parameter's candidates in batches; true after adopting the
    /// first one that still fails.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn firstFailing(self: *Property, search: *Search, shrunk: *Shrunk, slot: Slot) Error!bool {
        const a = self.context.arena;
        const index = slot.index;
        const candidates = slot.candidates;
        var start: usize = 0;
        var chunk: usize = shrink_first;
        while (start < candidates.len and shrunk.attempts < shrink_budget) : (chunk = @min(2 * chunk, shrink_chunk)) {
            const count_now = @min(candidates.len - start, chunk, shrink_budget - shrunk.attempts);
            const trial = try a.alloc(Input, count_now);
            for (trial, candidates[start..][0..count_now]) |*input, candidate| {
                const changed = try a.dupe(Value, shrunk.values);
                changed[index] = candidate;
                input.* = .{ .run = 0, .values = changed, .nodes = try self.encode(changed) };
            }
            const answer = try self.one(search, try self.call(trial));
            shrunk.attempts += answer.outcomes.len;
            for (answer.outcomes, trial[0..answer.outcomes.len]) |result, input| switch (try self.classify(result)) {
                .fail => |reason| return shrunk.adopt(input.values, reason),
                else => {},
            };
            start += answer.outcomes.len;
            if (answer.outcomes.len == count_now) continue;
            // A candidate that killed its process fails only if it kills a
            // process of its own too; the candidates after it run next.
            const died = trial[answer.outcomes.len .. answer.outcomes.len + 1];
            const alone = try self.one(search, try self.call(died));
            shrunk.attempts += 1;
            start += 1;
            if (alone.outcomes.len == 0) {
                if (alone.timed_out) continue;
                return shrunk.adopt(died[0].values, try self.ending(alone));
            }
            switch (try self.classify(alone.outcomes[0])) {
                .fail => |reason| return shrunk.adopt(died[0].values, reason),
                else => {},
            }
        }
        return false;
    }
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn rendered(self: *Property, values: []const Value) Error!Rendered {
        const a = self.context.arena;
        const renderer: render.Renderer = .{ .schema = self.schema, .module = self.module() };
        var literals: std.json.ObjectMap = .empty;
        for (self.parameters, values) |parameter, value| try literals.put(a, parameter.name, .{ .string = try renderer.literal(a, parameter.type, value) });
        return .{ .arguments = try self.arguments(values), .literals = .{ .object = literals } };
    }
    /// The command that replays this property's generation and shrinking.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn reproduction(self: *Property) Error![]const u8 {
        const a = self.context.arena;
        const name = v.text(v.get(self.function, "name"));
        const runs = if (self.settings.runs == default_runs) "" else try std.fmt.allocPrint(a, " --property-runs {d}", .{self.settings.runs});
        return std.fmt.allocPrint(a, "mylang test {s} --filter '{s}' --seed {d}{s}", .{ self.settings.entry, name, self.settings.seed, runs });
    }
    /// The failure text `mylang test` prints after `failed NAME: `.
    // twin-drift-ok: Preserve the old property algorithm in the independent Core port; its command allocator is borrowed as arena.
    fn describe(self: *Property, counted: Evidence) Error![]const u8 {
        var out: std.Io.Writer.Allocating = .init(self.context.arena);
        defer out.deinit();
        const w = &out.writer;
        const failure = counted.failure.?;
        const counts = counted.counts;
        try w.print("falsified after {d} passing run{s}", .{ counts.passed, plural(counts.passed) });
        if (counts.discarded != 0) try w.print(", {d} discarded", .{counts.discarded});
        try w.print(" (seed {d})\n", .{counted.seed});
        if (failure.shrunk) {
            try w.print("  minimal input ({d} shrink{s}, {d} attempt{s}):\n", .{ counts.shrinks, plural(counts.shrinks), counts.attempts, plural(counts.attempts) });
        } else try w.writeAll("  input (not shrunk: it ran out of time, and so could every candidate):\n");
        try self.listInput(w, failure.minimal);
        try w.print("  original input (run {d}):\n", .{failure.run + 1});
        try self.listInput(w, failure.original);
        try reasonLines(w, "reason", failure.reason);
        if (failure.first_reason.len != 0) try reasonLines(w, "original reason", failure.first_reason);
        try w.print("  reproduce: {s}", .{failure.reproduce});
        return out.toOwnedSlice();
    }
    fn listInput(self: *Property, w: *std.Io.Writer, input: Rendered) Error!void {
        for (self.parameters) |parameter| try w.print("    {s} = {s}\n", .{ parameter.name, v.text(v.get(input.literals, parameter.name)) });
    }
};

/// Generation progress for one property: the next run to draw, how many
/// inputs passed or were discarded (and by which precondition), and the
/// inputs of the batch in flight.
pub const Search = struct {
    next_run: usize = 0,
    passed: usize = 0,
    discarded: usize = 0,
    /// Batch processes started for this property, the first one included.
    processes: usize = 0,
    clauses: std.array_hash_map.String(usize) = .empty,
    batch: []const Input = &.{},

    fn discard(self: *Search, allocator: std.mem.Allocator, clause: []const u8) error{OutOfMemory}!void {
        self.discarded += 1;
        const entry = try self.clauses.getOrPut(allocator, clause);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
};

/// A shrink in progress: the smallest failing input so far and why it fails.
const Shrunk = struct {
    values: []const Value,
    reason: []const u8,
    steps: usize = 0,
    attempts: usize = 0,

    fn adopt(self: *Shrunk, values: []const Value, reason: []const u8) bool {
        self.values = values;
        self.reason = reason;
        self.steps += 1;
        return true;
    }
};

/// Why an input failed, and whether its counterexample may be shrunk.
const Cause = struct { reason: []const u8, shrink: bool = true };
/// One parameter's shrink candidates, in the order they are tried.
const Slot = struct { index: usize, candidates: []const Value };
/// One labelled reason, its continuation lines indented under it.
fn reasonLines(w: *std.Io.Writer, label: []const u8, reason: []const u8) std.Io.Writer.Error!void {
    try w.print("  {s}: ", .{label});
    var lines = std.mem.splitScalar(u8, reason, '\n');
    var first_line = true;
    while (lines.next()) |line| {
        if (!first_line) try w.writeAll("\n    ");
        try w.writeAll(line);
        first_line = false;
    }
    try w.writeByte('\n');
}
fn plural(count: usize) []const u8 {
    return if (count == 1) "" else "s";
}

/// Whether the runner injects a parameter of this type instead of drawing it.
fn injected(type_name: []const u8) bool {
    for ([_][]const u8{ "stream_cap", "clock_cap", "random_cap", "filesystem_cap", "network_cap", "environment_cap" }) |name| {
        if (std.mem.eql(u8, type_name, name)) return true;
    }
    return false;
}
/// The refusal of a property test whose result is neither `bool` nor `Result[bool, E]`.
pub const non_bool_result = "a property test returns bool or Result[bool, E], not {s}";

/// Why property test parameter `parameter: type_name` cannot be generated, naming the
/// type inside it that `found` refuses when that is not the parameter's own type.
pub fn refusedText(allocator: std.mem.Allocator, parameter: []const u8, type_name: []const u8, found: types.Refusal) Error![]const u8 {
    const spelled = if (std.mem.eql(u8, type_name, "host_cap")) "Host" else type_name;
    if (std.mem.eql(u8, found.type, type_name)) {
        return std.fmt.allocPrint(allocator, "property test parameter `{s}: {s}` cannot be generated: {s}", .{ parameter, spelled, found.reason });
    }
    return std.fmt.allocPrint(allocator, "property test parameter `{s}: {s}` cannot be generated: it holds {s}, and {s}", .{ parameter, spelled, found.type, found.reason });
}
