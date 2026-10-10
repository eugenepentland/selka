//! Indexed property generation and safe checkpoint accounting regression tests.
const std = @import("std");
const contract = @import("property_campaign_contract.zig");
const Policy = contract.Policy;
const Progress = contract.Progress;
const maximum_ordinal = contract.maximum_ordinal;
const property = @import("test_runner_property.zig");
const execute = @import("property_execute.zig");
const generate = @import("property_generate.zig");
const types = @import("property_types.zig");
const Value = std.json.Value;
const t = std.testing;
const property_name = "property::test_case";
const definitions =
    \\[{"name":"u8","kind":"integer","bits":8,"signed":false},
    \\ {"name":"bool","kind":"boolean"},{"name":"str","kind":"string"},
    \\ {"name":"List<str>","kind":"list","element":"str"},
    \\ {"name":"Record","kind":"record","fields":[{"name":"id","type":"u8"},{"name":"labels","type":"List<str>"}]}]
;

fn mockExecutor(a: std.mem.Allocator) !execute.Executor {
    const parsed = try std.json.parseFromSliceLeaky(Value, a, definitions, .{});
    return .{
        .context = .{ .arena = a, .backing = a, .io = t.io, .environment = .{ .block = .empty } },
        .types = parsed.array.items,
        .executable = "",
        .table_index = 0,
        .directory = "",
    };
}

fn mockProperty(a: std.mem.Allocator, executor: *const execute.Executor, policy: Policy, runs: u32, data: bool) !property.Property {
    var function = try std.json.parseFromSliceLeaky(Value, a,
        \\{"name":"property::test_case","parameters":[{"name":"n","type":"u8"}],"result":"bool"}
    , .{});
    if (!data) try function.object.put(a, "parameters", try std.json.parseFromSliceLeaky(Value, a, "[]", .{}));
    const setup = try property.Property.bind(executor.context, executor, function, .{}, .{ .seed = 7, .runs = runs, .policy = policy, .entry = "property.my" });
    return setup.ready;
}

fn passing(a: std.mem.Allocator, count: usize) ![]execute.Outcome {
    const outcomes = try a.alloc(execute.Outcome, count);
    @memset(outcomes, .{ .status = "value", .actual = .{ .bool = true } });
    return outcomes;
}

const Capture = struct {
    last: Progress = .{},
    calls: usize = 0,
    before: ?contract.CommitError = null,
    after: ?contract.CommitError = null,

    fn callback(self: *Capture) contract.Callback {
        return .{ .context = self, .commit = commit };
    }
    fn commit(context: *anyopaque, progress: Progress) contract.CommitError!void {
        const self: *Capture = @ptrCast(@alignCast(context));
        self.calls += 1;
        if (self.before) |err| return err;
        self.last = progress;
        if (self.after) |err| return err;
    }
};

fn generatedJson(a: std.mem.Allocator, schema: types.Schema, type_name: []const u8, ordinal: usize, budget: usize) ![]const u8 {
    var generator: generate.Generator = .{ .arena = a, .schema = schema, .stream = .init(7, ordinal), .size = generate.campaignSize(.indexed_v1, ordinal, budget) };
    return std.json.Stringify.valueAlloc(a, try generator.value(type_name, 0), .{});
}

fn discard(message: []const u8) execute.Outcome {
    return .{ .status = "trap", .trap = .{ .code = "R_REQUIRES", .frame = property_name, .message = message } };
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property generation is stable across budgets for scalar and nested values" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    const schema = try types.Schema.init(a, executor.types);
    for ([_]usize{ 0, 1, 98, 99, 100, 127, 128, 255, 999 }) |ordinal| {
        for ([_][]const u8{ "u8", "List<str>", "Record" }) |type_name| {
            const first = try generatedJson(a, schema, type_name, ordinal, 1000);
            try t.expectEqualStrings(first, try generatedJson(a, schema, type_name, ordinal, 2000));
        }
        for ([_]usize{ 1, 100, 1000, 2000 }) |budget| {
            try t.expectEqual(generate.sizeOf(ordinal, budget), generate.campaignSize(.legacy, ordinal, budget));
        }
    }
    try t.expectEqual(@as(usize, 100), generate.campaignSize(.indexed_v1, 999, 2000));
    try t.expect(generate.sizeOf(999, 1000) != generate.sizeOf(999, 2000));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property full restore owns clause names and starts no process" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    var bound = try mockProperty(a, &executor, .indexed_v1, 3, false);
    var capture: Capture = .{};
    const message = try a.dupe(u8, "requires");
    try bound.restoreCampaign(.{ .restored = .{ .next_ordinal = 5, .passed = 3, .discarded = 2, .clauses = &.{.{ .message = message, .count = 2 }} }, .callback = capture.callback() });
    var search: property.Search = .{};
    try t.expect(try bound.first(&search) == null);
    @memset(message, 'x');
    try t.expectEqual(@as(usize, 2), search.clauses.get("requires").?);
    const verdict = try bound.finish(&search, null);
    try t.expect(verdict.passed);
    try t.expectEqual(@as(usize, 0), verdict.evidence.counts.processes);
    const evidence = verdict.evidence.campaign.?;
    try t.expectEqual(@as(u64, 5), evidence.reused);
    try t.expectEqual(@as(u64, 5), evidence.next_ordinal);
    try t.expectEqual(@as(u64, 0), evidence.generated + evidence.submitted + evidence.observed + evidence.fresh_classified);
    try t.expectEqual(@as(usize, 0), capture.calls);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property checkpoints bounded chunks before interruption and resumes remaining ordinals" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    var bound = try mockProperty(a, &executor, .indexed_v1, 256, true);
    var interrupted: Capture = .{ .after = error.ReadFailed };
    try bound.restoreCampaign(.{ .callback = interrupted.callback() });
    var search: property.Search = .{};
    const first = (try bound.first(&search)).?;
    try t.expectEqual(contract.chunk_limit, first.inputs.len);
    try t.expectEqual(@as(u64, 0), search.work.last.next_ordinal);
    try t.expectError(error.ReadFailed, bound.finish(&search, .{ .outcomes = try passing(a, first.inputs.len), .complete = true }));
    try t.expectEqual(@as(u64, 128), interrupted.last.next_ordinal);
    try t.expectEqual(@as(u64, 128), interrupted.last.passed);
    var resumed = try mockProperty(a, &executor, .indexed_v1, 256, true);
    var completed: Capture = .{};
    try resumed.restoreCampaign(.{ .restored = interrupted.last, .callback = completed.callback() });
    var remainder: property.Search = .{};
    const next = (try resumed.first(&remainder)).?;
    try t.expectEqual(@as(usize, 128), remainder.batch[0].run);
    try t.expectEqual(@as(usize, 256), remainder.next_run);
    try t.expectEqual(@as(u64, 128), remainder.work.last.next_ordinal);
    const verdict = try resumed.finish(&remainder, .{ .outcomes = try passing(a, next.inputs.len), .complete = true });
    try t.expect(verdict.passed);
    try t.expectEqual(@as(usize, 1), verdict.evidence.counts.processes);
    try t.expectEqual(@as(u64, 128), verdict.evidence.campaign.?.reused);
    try t.expectEqual(@as(u64, 128), verdict.evidence.campaign.?.fresh_classified);
    try t.expectEqual(@as(u64, 256), completed.last.next_ordinal);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property discards occupy ordinals and restored clause order survives extension" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    var bound = try mockProperty(a, &executor, .indexed_v1, 3, false);
    var capture: Capture = .{ .after = error.ReadFailed };
    try bound.restoreCampaign(.{ .restored = .{ .next_ordinal = 4, .passed = 2, .discarded = 2, .clauses = &.{ .{ .message = "alpha", .count = 1 }, .{ .message = "beta", .count = 1 } } }, .callback = capture.callback() });
    var search: property.Search = .{};
    try t.expectEqual(@as(usize, 1), (try bound.first(&search)).?.inputs.len);
    try t.expectError(error.ReadFailed, bound.finish(&search, .{ .outcomes = &.{discard("beta")}, .complete = true }));
    try t.expectEqual(@as(u64, 5), capture.last.next_ordinal);
    try t.expectEqual(@as(u64, 3), capture.last.discarded);
    try t.expectEqualStrings("alpha", capture.last.clauses[0].message);
    try t.expectEqualStrings("beta", capture.last.clauses[1].message);
    try t.expectEqual(@as(u64, 2), capture.last.clauses[1].count);
    var resumed = try mockProperty(a, &executor, .indexed_v1, 3, false);
    try resumed.restoreCampaign(.{ .restored = capture.last });
    var remainder: property.Search = .{};
    _ = try resumed.first(&remainder);
    const verdict = try resumed.finish(&remainder, .{ .outcomes = try passing(a, 1), .complete = true });
    try t.expect(verdict.passed);
    try t.expectEqual(@as(usize, 3), verdict.evidence.counts.discarded);
    try t.expectEqual(@as(u64, 5), verdict.evidence.campaign.?.reused);
    try t.expectEqual(@as(u64, 6), verdict.evidence.campaign.?.next_ordinal);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property exhaustion rejects the failing chunk and invalid restored budgets" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    var bound = try mockProperty(a, &executor, .indexed_v1, 1, false);
    var capture: Capture = .{};
    const prefix: Progress = .{ .next_ordinal = 10, .discarded = 10, .clauses = &.{.{ .message = "alpha", .count = 10 }} };
    try bound.restoreCampaign(.{ .restored = prefix, .callback = capture.callback() });
    var search: property.Search = .{};
    _ = try bound.first(&search);
    const verdict = try bound.finish(&search, .{ .outcomes = &.{discard("alpha")}, .complete = true });
    try t.expect(!verdict.passed);
    try t.expectEqual(@as(usize, 11), verdict.evidence.counts.discarded);
    try t.expectEqual(@as(u64, 10), verdict.evidence.campaign.?.next_ordinal);
    try t.expectEqual(@as(usize, 0), capture.calls);
    try t.expectError(error.InvalidTestValue, bound.restoreCampaign(.{ .restored = .{ .next_ordinal = 2, .passed = 2 } }));
    try t.expectError(error.InvalidTestValue, bound.restoreCampaign(.{ .restored = .{ .next_ordinal = 11, .discarded = 11, .clauses = &.{.{ .message = "alpha", .count = 11 }} } }));
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property failure distinguishes submitted observed and classified inputs" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    for ([_]Policy{ .legacy, .indexed_v1 }) |policy| {
        var bound = try mockProperty(a, &executor, policy, 3, false);
        var capture: Capture = .{};
        if (policy == .indexed_v1) try bound.restoreCampaign(.{ .callback = capture.callback() });
        var search: property.Search = .{};
        const batch = (try bound.first(&search)).?;
        const outcomes = try passing(a, batch.inputs.len);
        outcomes[1].actual = .{ .bool = false };
        const verdict = try bound.finish(&search, .{ .outcomes = outcomes, .complete = true });
        try t.expect(!verdict.passed);
        try t.expectEqual(@as(usize, 1), verdict.evidence.failure.?.run);
        try t.expectEqual(@as(usize, 0), verdict.evidence.counts.attempts);
        try t.expectEqual(@as(usize, 0), capture.calls);
        if (verdict.evidence.campaign) |evidence| {
            try t.expectEqual(@as(u64, 3), evidence.generated);
            try t.expectEqual(@as(u64, 3), evidence.submitted);
            try t.expectEqual(@as(u64, 3), evidence.observed);
            try t.expectEqual(@as(u64, 2), evidence.fresh_classified);
            try t.expectEqual(@as(u64, 0), evidence.next_ordinal);
            try t.expect(std.mem.endsWith(u8, verdict.evidence.failure.?.reproduce, " --property-policy indexed-v1"));
        } else try t.expectEqualStrings("mylang test property.my --filter 'property::test_case' --seed 7 --property-runs 3", verdict.evidence.failure.?.reproduce);
    }
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property uncertain execution permanently disables prefix publication" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    var bound = try mockProperty(a, &executor, .indexed_v1, 3, false);
    var capture: Capture = .{};
    try bound.restoreCampaign(.{ .callback = capture.callback() });
    var search: property.Search = .{};
    _ = try bound.first(&search);
    const uncertain = try bound.finish(&search, .{ .outcomes = try passing(a, 3), .complete = false, .ending = "abnormal exit" });
    try t.expect(uncertain.passed);
    try t.expect(!search.work.publication);
    try t.expectEqual(@as(u64, 0), uncertain.evidence.campaign.?.next_ordinal);
    // Model the next successful dispatch without starting a native process.
    // The permanent latch must prevent it from covering the uncertain chunk.
    bound.settings.runs = 4;
    var input = search.batch[0];
    input.run = 3;
    search.batch = &.{input};
    search.next_run = 4;
    search.work.counts.generated += 1;
    search.work.counts.submitted += 1;
    search.processes += 1;
    const later = try bound.finish(&search, .{ .outcomes = try passing(a, 1), .complete = true });
    try t.expect(later.passed);
    try t.expectEqual(@as(u64, 0), later.evidence.campaign.?.next_ordinal);
    try t.expectEqual(@as(u64, 0), capture.last.next_ordinal);
    try t.expectEqual(@as(usize, 2), capture.calls);
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property checkpoint guard errors abort before success or publication" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    for ([_]contract.CommitError{ error.SourceChanged, error.ComponentUnavailable, error.ReadFailed, error.WriteFailed, error.OutOfMemory }) |err| {
        var bound = try mockProperty(a, &executor, .indexed_v1, 1, false);
        var capture: Capture = .{ .before = err };
        try bound.restoreCampaign(.{ .callback = capture.callback() });
        var search: property.Search = .{};
        _ = try bound.first(&search);
        try t.expectError(err, bound.finish(&search, .{ .outcomes = try passing(a, 1), .complete = true }));
        try t.expectEqual(@as(u64, 0), search.work.last.next_ordinal);
        try t.expectEqual(@as(u64, 0), capture.last.next_ordinal);
        try t.expectEqual(@as(usize, 1), capture.calls);
    }
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property cap leaves legacy first batch behavior intact" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const executor = try mockExecutor(a);
    for ([_]Policy{ .legacy, .indexed_v1 }) |policy| {
        var bound = try mockProperty(a, &executor, policy, 256, false);
        var search: property.Search = .{};
        const expected: usize = if (policy == .legacy) 256 else contract.chunk_limit;
        try t.expectEqual(expected, (try bound.first(&search)).?.inputs.len);
    }
}

// spec-case: NEW-CORE-PROPERTY-CAMPAIGN-1
test "indexed property contract names policies and rejects malformed cumulative prefixes" {
    try t.expectEqual(Policy.legacy, Policy.parse("legacy").?);
    try t.expectEqual(Policy.indexed_v1, Policy.parse("indexed-v1").?);
    try t.expectEqualStrings("indexed-v1", Policy.indexed_v1.name());
    try t.expect(Policy.parse("indexed-v2") == null);
    const valid: Progress = .{ .next_ordinal = 5, .passed = 2, .discarded = 3, .clauses = &.{.{ .message = "requires", .count = 3 }} };
    try t.expect(try valid.valid(t.allocator));
    var invalid = valid;
    invalid.next_ordinal += 1;
    try t.expect(!try invalid.valid(t.allocator));
    invalid = valid;
    invalid.clauses = &.{ .{ .message = "requires", .count = 1 }, .{ .message = "requires", .count = 2 } };
    try t.expect(!try invalid.valid(t.allocator));
    invalid = valid;
    invalid.clauses = &.{.{ .message = "requires", .count = 0 }};
    try t.expect(!try invalid.valid(t.allocator));
    invalid = .{ .next_ordinal = 0, .passed = std.math.maxInt(u64), .discarded = 1 };
    try t.expect(!try invalid.valid(t.allocator));
    try t.expect(!try (Progress{ .next_ordinal = maximum_ordinal + 1 }).valid(t.allocator));
}
