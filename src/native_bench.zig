//! Sampling statistics, versioned performance baselines, and reviewed policy.
//! Comparison decisions are pure functions over synthetic samples, so thresholds
//! are tested without reading a clock.
const std = @import("std");
const v = @import("qbe_build_value.zig");
const execute = @import("native_test_execute.zig");
const cases = @import("native_test_cases.zig");
const fs = @import("qbe_build_io.zig");
const Value = std.json.Value;
// JSON member names shared by every parser and renderer in this module.
const key_allowed_growth = "allowed_growth_percent";
const key_minimum_delta = "minimum_meaningful_delta_ns";
const key_max_ceiling = "max_ns_per_op";
const key_arguments = "arguments";
const key_expected = "expected";
const key_workload = "workload_version";
const key_fixture = "fixture_identity";
const key_median = "median_ns_per_op";
const key_spread = "spread_percent";
const key_raw = "raw";
const key_iterations = "iterations";
const key_duration = "duration_ns";
const key_revision = "revision";
const key_approver = "approver";
const key_reason = "reason";
const key_profile = "runner_profile";
const key_old_median = "old_median_ns_per_op";
const key_new_median = "new_median_ns_per_op";
const key_identity = "identity";
const key_tools = "tools";
const key_platform = "platform";
const key_compiler = "compiler";
const key_zig = "zig";
const key_qbe = "qbe";
const key_os = "os";
const key_arch = "arch";
const key_mode = "mode";
const key_boundary = "boundary_version";
const key_warmup = "warmup_iterations";
const key_batch_count = "batch_count";
const key_target = "target_batch_ns";
const key_version = "version";
const key_measurements = "measurements";
const key_comparisons = "comparisons";
const key_failures = "failures";
const key_status = "status";
const key_verdict = "verdict";
const key_complete = "complete";
const key_baseline_ns = "baseline_ns_per_op";
const key_current_ns = "current_ns_per_op";
const key_percent_change = "percent_change";
const key_provenance = "provenance";
const key_history = "history";
const key_benchmarks = "benchmarks";
const key_required = "required";
const key_noise = "noise";
const key_sizes = "sizes";
const key_skip = "skip";
const key_providers = "providers";
const key_id = "id";
const key_default = "default";
/// The declared timing boundary for guest benchmarks: one complete native
/// copied-value call, including argument and result codec costs.
pub const boundary = "native-copied-value-call-v1";
/// Version tags rejected when absent or mismatched.
pub const policy_version = "bench-policy-v1";
pub const baseline_version = "bench-baseline-v1";
pub const report_version = "bench-report-v1";
/// Retained baseline history cap so one file cannot grow without bound.
pub const history_limit = 256;
/// Malformed comparison artifacts never silently become a green gate.
pub const Error = error{ InvalidBenchPolicy, InvalidBenchBaseline, InvalidBenchReport, InvalidBenchPromotion, InvalidBenchCases, UnknownBenchmark, MissingBenchExpectation, OutOfMemory };
/// Sampling configuration re-exported so callers name one type.
pub const Sampling = execute.Sampling;
/// Raw batch duration and iteration count, shared with the native protocol.
pub const Batch = execute.Batch;
/// One discovered benchmark: its validated case plus the stable identity a
/// baseline keys on. A sized function yields one selection per named size.
pub const Selection = struct {
    case: cases.Case,
    id: []const u8,
    size: []const u8 = "",
    workload_version: u64 = 1,
    fixture_identity: []const u8 = "",
};
const bench_settings_keys = [_][]const u8{ key_arguments, key_expected, key_skip, key_providers, key_sizes, key_workload, key_fixture };
const size_settings_keys = [_][]const u8{ key_arguments, key_expected };
fn benchName(name: []const u8) bool {
    const start = if (std.mem.lastIndexOf(u8, name, "::")) |split| split + 2 else 0;
    return std.mem.startsWith(u8, name[start..], "bench_");
}
const Workload = struct { name: []const u8, function: Value, size: []const u8 = "", workload: u64 = 1, pinned: []const u8 = "" };
const Sample = struct { arguments: Value = .null, expected: Value = .null, skip: ?[]const u8 = null, providers: Value = .null, settings: Value = .null, explicit: bool = false };
fn appendCase(allocator: std.mem.Allocator, selected: *std.ArrayList(Selection), workload: Workload, sample: Sample) Error!void {
    if (sample.skip == null and !sample.explicit) {
        if (!eql(v.text(v.get(workload.function, "result")), "bool")) return error.MissingBenchExpectation;
    }
    const case: cases.Case = .{
        .name = workload.name,
        .function = workload.function,
        .arguments = if (sample.arguments == .null) .{ .object = .empty } else sample.arguments,
        .expected = if (sample.explicit) sample.expected else .{ .bool = true },
        .providers = sample.providers,
        .settings = sample.settings,
        .declared = .{ .skip = sample.skip },
    };
    const id = if (workload.size.len == 0) workload.name else std.fmt.allocPrint(allocator, "{s}[{s}]", .{ workload.name, workload.size }) catch return error.OutOfMemory;
    var buffer: std.Io.Writer.Allocating = .init(allocator);
    defer buffer.deinit();
    const w = &buffer.writer;
    w.print("{s}\n{d}\n{s}\n", .{ workload.name, workload.workload, workload.size }) catch return error.OutOfMemory;
    std.json.Stringify.value(sample.arguments, .{}, w) catch return error.OutOfMemory;
    w.writeAll("\n") catch return error.OutOfMemory;
    std.json.Stringify.value(sample.providers, .{}, w) catch return error.OutOfMemory;
    const fixture = if (workload.pinned.len != 0) workload.pinned else fs.hash(allocator, buffer.written()) catch return error.OutOfMemory;
    selected.append(allocator, .{ .case = case, .id = id, .size = workload.size, .workload_version = workload.workload, .fixture_identity = fixture }) catch return error.OutOfMemory;
}
fn buildSelections(allocator: std.mem.Allocator, selected: *std.ArrayList(Selection), function: Value, name: []const u8, settings: Value) Error!void {
    if (settings != .null and settings != .object) return error.InvalidBenchCases;
    if (settings != .null and !keysAllowed(settings, &bench_settings_keys)) return error.InvalidBenchCases;
    const skip = blk: {
        const item = v.get(settings, key_skip);
        if (item != .null and item != .string) return error.InvalidBenchCases;
        break :blk if (item == .string and item.string.len != 0) item.string else null;
    };
    const providers = v.get(settings, key_providers);
    if (providers != .null and providers != .object) return error.InvalidBenchCases;
    const top = v.get(settings, key_arguments);
    if (top != .null and top != .object) return error.InvalidBenchCases;
    const workload = if (v.get(settings, key_workload) == .null) 1 else integer(v.get(settings, key_workload)) orelse return error.InvalidBenchCases;
    if (workload == 0) return error.InvalidBenchCases;
    const pinned = v.text(v.get(settings, key_fixture));
    const top_explicit = settings == .object and settings.object.contains(key_expected);
    const sizes = v.get(settings, key_sizes);
    if (sizes != .null) {
        if (sizes != .object or sizes.object.count() == 0) return error.InvalidBenchCases;
        var entries = sizes.object.iterator();
        while (entries.next()) |entry| {
            const size = entry.key_ptr.*;
            const value = entry.value_ptr.*;
            if (size.len == 0 or value != .object or !keysAllowed(value, &size_settings_keys)) return error.InvalidBenchCases;
            const arguments = v.get(value, key_arguments);
            if (arguments != .null and arguments != .object) return error.InvalidBenchCases;
            try appendCase(allocator, selected, .{
                .name = name,
                .function = function,
                .size = size,
                .workload = workload,
                .pinned = pinned,
            }, .{
                .arguments = if (arguments == .null) top else arguments,
                .expected = v.get(value, key_expected),
                .skip = skip,
                .providers = providers,
                .settings = if (value.object.contains(key_expected)) value else settings,
                .explicit = value.object.contains(key_expected) or top_explicit,
            });
        }
    } else {
        try appendCase(allocator, selected, .{ .name = name, .function = function, .workload = workload, .pinned = pinned }, .{
            .arguments = top,
            .expected = v.get(settings, key_expected),
            .skip = skip,
            .providers = providers,
            .settings = settings,
            .explicit = top_explicit,
        });
    }
}
/// Discover exported `bench_` functions matching a pattern and validate every
/// named case, size, expectation, provider map and workload version.
pub fn discover(allocator: std.mem.Allocator, schema: Value, config: Value, pattern: []const u8) Error![]Selection {
    if (config != .null and config != .object) return error.InvalidBenchCases;
    const functions = v.array(v.get(schema, "functions"));
    if (config == .object) {
        var entries = config.object.iterator();
        while (entries.next()) |entry| {
            const found = for (functions) |function| {
                if (eql(v.text(v.get(function, "name")), entry.key_ptr.*)) break true;
            } else false;
            if (!found) return error.UnknownBenchmark;
        }
    }
    var selected: std.ArrayList(Selection) = .empty;
    errdefer selected.deinit(allocator);
    for (functions) |function| {
        const name = v.text(v.get(function, "name"));
        if (!benchName(name) or !cases.matches(pattern, name)) continue;
        try buildSelections(allocator, &selected, function, name, v.get(config, name));
    }
    return selected.toOwnedSlice(allocator) catch return error.OutOfMemory;
}
/// Lower-is-better limits for one benchmark. Growth is a regression only when
/// both the relative limit and the absolute delta floor are exceeded.
pub const Limits = struct {
    allowed_growth_percent: f64 = 10.0,
    minimum_meaningful_delta_ns: f64 = 1.0,
    max_ns_per_op: ?f64 = null,
};
/// Noise budget and the single predefined confirmation run.
pub const Noise = struct {
    max_relative_spread_percent: f64 = 25.0,
    near_limit_margin_percent: f64 = 10.0,
    confirmation_runs: u8 = 1,
};
/// Approved policy: default limits, per-benchmark overrides and required suite.
pub const Policy = struct {
    runner_profile: []const u8 = key_default,
    default: Limits = .{},
    overrides: std.StringHashMapUnmanaged(Limits) = .empty,
    required: []const []const u8 = &.{},
    noise: Noise = .{},

    /// Limits for one benchmark ID: an override when present, else the default.
    pub fn limitFor(self: Policy, id: []const u8) Limits {
        return self.overrides.get(id) orelse self.default;
    }
};
/// Run identity that a baseline measurement must match to stay comparable.
pub const Identity = struct {
    mode: []const u8 = "Debug",
    runner_profile: []const u8 = key_default,
    boundary_version: u64 = 1,
    warmup_iterations: u64 = 3,
    batch_count: u64 = 9,
    target_batch_ns: u64 = 250_000_000,
};
/// Tool and platform provenance retained beside the measurements.
pub const Tools = struct { compiler: []const u8 = "", zig: []const u8 = "", qbe: []const u8 = "" };
/// Operating system and CPU architecture observed for the run.
pub const Platform = struct { os: []const u8 = "", arch: []const u8 = "" };
/// Run provenance: revision, comparable identity, tools and platform.
pub const Provenance = struct { revision: []const u8 = "", identity: Identity = .{}, tools: Tools = .{}, platform: Platform = .{} };
/// One approved measurement with its workload and fixture identity.
pub const Measurement = struct {
    id: []const u8,
    workload_version: u64 = 1,
    fixture_identity: []const u8 = "",
    median_ns_per_op: f64,
    spread_percent: f64 = 0,
    raw: []const Batch = &.{},
};
/// Retained record of one reviewed baseline replacement.
pub const HistoryEntry = struct {
    revision: []const u8 = "",
    approver: []const u8 = "",
    reason: []const u8 = "",
    runner_profile: []const u8 = "",
    old_median_ns_per_op: f64 = 0,
    new_median_ns_per_op: f64 = 0,
};
/// An approved baseline plus the provenance needed for compatibility checks.
pub const Baseline = struct {
    provenance: Provenance = .{},
    measurements: []const Measurement = &.{},
    history: []const HistoryEntry = &.{},

    /// Find the approved measurement for a benchmark ID.
    pub fn find(self: Baseline, id: []const u8) ?Measurement {
        for (self.measurements) |item| if (std.mem.eql(u8, item.id, id)) return item;
        return null;
    }
};
/// Computed sample statistics; the median is the reported ns/op.
pub const Stats = struct {
    median_ns_per_op: f64 = 0,
    spread_percent: f64 = 0,
    sample_count: usize = 0,
    calibrated_iterations: u64 = 0,
};
/// The decision for one benchmark under the approved policy.
pub const Verdict = enum { pass, regression, ceiling, unbaselined, incompatible, inconclusive, missing };
/// One benchmark's comparison result with the numbers that produced it.
pub const Comparison = struct {
    id: []const u8,
    verdict: Verdict,
    reason: []const u8,
    baseline_ns_per_op: f64 = 0,
    current_ns_per_op: f64 = 0,
    percent_change: f64 = 0,
    limits: Limits = .{},
};
/// Everything needed to compare one run against policy and baseline.
pub const Run = struct { policy: *const Policy, baseline: ?*const Baseline, identity: Identity = .{} };
/// One benchmark that did not produce a passing measurement.
pub const Failure = struct { id: []const u8, status: []const u8, reason: []const u8 = "" };
/// A rendered run report and the fields promotion consumes.
pub const ReportInput = struct {
    provenance: Provenance,
    measurements: []const Measurement,
    comparisons: []const Comparison,
    failures: []const Failure = &.{},
    complete: bool,
    passed: bool,
};
/// A reviewed promotion: an approved candidate plus who approved it and why.
pub const Promotion = struct {
    report: ReportInput,
    approver: []const u8,
    reason: []const u8,
    revision: []const u8,
    old_baseline: ?*const Baseline = null,
};

const Entry = struct { key: []const u8, value: Value };
fn makeObject(allocator: std.mem.Allocator, entries: []const Entry) Error!Value {
    var map: std.json.ObjectMap = .empty;
    for (entries) |entry| map.put(allocator, entry.key, entry.value) catch return error.OutOfMemory;
    return .{ .object = map };
}
fn eql(left: []const u8, right: []const u8) bool {
    return std.mem.eql(u8, left, right);
}
fn real(value: Value) ?f64 {
    return switch (value) {
        .integer => |number| @floatFromInt(number),
        .float => |number| number,
        else => null,
    };
}
fn integer(value: Value) ?u64 {
    return switch (value) {
        .integer => |number| if (number < 0) null else @intCast(number),
        else => null,
    };
}
fn keysAllowed(value: Value, allowed: []const []const u8) bool {
    if (value != .object) return false;
    var entries = value.object.iterator();
    while (entries.next()) |entry| {
        const known = for (allowed) |name| {
            if (eql(entry.key_ptr.*, name)) break true;
        } else false;
        if (!known) return false;
    }
    return true;
}
/// Per-batch nanoseconds per operation; a zero-iteration batch is invalid.
pub fn nsPerOp(batch: Batch) ?f64 {
    if (batch.iterations == 0) return null;
    return @as(f64, @floatFromInt(batch.duration_ns)) / @as(f64, @floatFromInt(batch.iterations));
}
fn percentile(sorted: []const f64, fraction: f64) f64 {
    if (sorted.len == 0) return 0;
    if (sorted.len == 1) return sorted[0];
    const position = fraction * @as(f64, @floatFromInt(sorted.len - 1));
    const low: usize = @intFromFloat(@floor(position));
    const high: usize = @intFromFloat(@ceil(position));
    const weight = position - @as(f64, @floatFromInt(low));
    return sorted[low] * (1 - weight) + sorted[high] * weight;
}
/// Median ns/op over the per-batch rates plus the interquartile spread relative
/// to the median. Empty input reports zero samples rather than a false value.
pub fn summarize(allocator: std.mem.Allocator, raw: []const Batch, calibrated_iterations: u64) Error!Stats {
    const rates = try allocator.alloc(f64, raw.len);
    defer allocator.free(rates);
    for (raw, rates) |batch, *rate| rate.* = nsPerOp(batch) orelse return error.InvalidBenchReport;
    std.mem.sort(f64, rates, {}, std.sort.asc(f64));
    const median = percentile(rates, 0.5);
    const spread = if (median == 0) 0 else (percentile(rates, 0.75) - percentile(rates, 0.25)) / median * 100;
    return .{ .median_ns_per_op = median, .spread_percent = spread, .sample_count = rates.len, .calibrated_iterations = calibrated_iterations };
}
fn limitsFromFields(value: Value) Error!Limits {
    var limits: Limits = .{};
    if (value.object.get(key_allowed_growth)) |item| limits.allowed_growth_percent = real(item) orelse return error.InvalidBenchPolicy;
    if (value.object.get(key_minimum_delta)) |item| limits.minimum_meaningful_delta_ns = real(item) orelse return error.InvalidBenchPolicy;
    if (value.object.get(key_max_ceiling)) |item| {
        if (item != .null) {
            const ceiling = real(item) orelse return error.InvalidBenchPolicy;
            if (ceiling <= 0) return error.InvalidBenchPolicy;
            limits.max_ns_per_op = ceiling;
        }
    }
    if (limits.allowed_growth_percent < 0 or limits.minimum_meaningful_delta_ns < 0) return error.InvalidBenchPolicy;
    return limits;
}
fn parseLimits(value: Value) Error!Limits {
    if (!keysAllowed(value, &.{ key_allowed_growth, key_minimum_delta, key_max_ceiling })) return error.InvalidBenchPolicy;
    return limitsFromFields(value);
}
fn parseNoise(value: Value) Error!Noise {
    if (!keysAllowed(value, &.{ "max_relative_spread_percent", "near_limit_margin_percent", "confirmation_runs" })) return error.InvalidBenchPolicy;
    var noise: Noise = .{};
    if (value.object.get("max_relative_spread_percent")) |item| noise.max_relative_spread_percent = real(item) orelse return error.InvalidBenchPolicy;
    if (value.object.get("near_limit_margin_percent")) |item| noise.near_limit_margin_percent = real(item) orelse return error.InvalidBenchPolicy;
    if (value.object.get("confirmation_runs")) |item| {
        const runs = integer(item) orelse return error.InvalidBenchPolicy;
        if (runs > 1) return error.InvalidBenchPolicy;
        noise.confirmation_runs = @intCast(runs);
    }
    if (noise.max_relative_spread_percent < 0 or noise.near_limit_margin_percent < 0) return error.InvalidBenchPolicy;
    return noise;
}
fn stringList(allocator: std.mem.Allocator, value: Value) Error![]const []const u8 {
    if (value != .array) return error.InvalidBenchPolicy;
    const list = try allocator.alloc([]const u8, value.array.items.len);
    for (value.array.items, list) |item, *out| {
        if (item != .string or item.string.len == 0) return error.InvalidBenchPolicy;
        out.* = item.string;
    }
    return list;
}
/// Parse and validate an approved policy. Unknown keys, versions and numbers reject.
pub fn parsePolicy(allocator: std.mem.Allocator, bytes: []const u8) Error!Policy {
    const parsed = std.json.parseFromSlice(Value, allocator, bytes, .{ .allocate = .alloc_always }) catch return error.InvalidBenchPolicy;
    const root = parsed.value;
    if (!keysAllowed(root, &.{ key_version, key_profile, key_default, key_benchmarks, key_required, key_noise })) return error.InvalidBenchPolicy;
    if (!eql(v.text(v.get(root, key_version)), policy_version)) return error.InvalidBenchPolicy;
    var policy: Policy = .{ .overrides = .empty };
    if (v.get(root, key_profile) != .null) {
        policy.runner_profile = v.text(v.get(root, key_profile));
        if (policy.runner_profile.len == 0) return error.InvalidBenchPolicy;
    }
    if (v.get(root, key_default) != .null) policy.default = try parseLimits(v.get(root, key_default));
    if (v.get(root, key_noise) != .null) policy.noise = try parseNoise(v.get(root, key_noise));
    if (v.get(root, key_required) != .null) policy.required = try stringList(allocator, v.get(root, key_required));
    if (v.get(root, key_benchmarks) != .null) {
        const list = v.get(root, key_benchmarks);
        if (list != .array) return error.InvalidBenchPolicy;
        for (list.array.items) |item| {
            if (!keysAllowed(item, &.{ key_id, key_allowed_growth, key_minimum_delta, key_max_ceiling })) return error.InvalidBenchPolicy;
            const id = v.text(v.get(item, key_id));
            if (id.len == 0 or policy.overrides.contains(id)) return error.InvalidBenchPolicy;
            policy.overrides.put(allocator, id, try limitsFromFields(item)) catch return error.OutOfMemory;
        }
    }
    return policy;
}
fn parseIdentity(value: Value) Error!Identity {
    if (!keysAllowed(value, &.{ key_mode, key_profile, key_boundary, key_warmup, key_batch_count, key_target })) return error.InvalidBenchBaseline;
    var identity: Identity = .{};
    if (v.get(value, key_mode) != .null) identity.mode = v.text(v.get(value, key_mode));
    if (v.get(value, key_profile) != .null) identity.runner_profile = v.text(v.get(value, key_profile));
    if (v.get(value, key_boundary) != .null) identity.boundary_version = integer(v.get(value, key_boundary)) orelse return error.InvalidBenchBaseline;
    if (v.get(value, key_warmup) != .null) identity.warmup_iterations = integer(v.get(value, key_warmup)) orelse return error.InvalidBenchBaseline;
    if (v.get(value, key_batch_count) != .null) identity.batch_count = integer(v.get(value, key_batch_count)) orelse return error.InvalidBenchBaseline;
    if (v.get(value, key_target) != .null) identity.target_batch_ns = integer(v.get(value, key_target)) orelse return error.InvalidBenchBaseline;
    if (identity.mode.len == 0 or identity.runner_profile.len == 0 or identity.boundary_version == 0 or identity.batch_count == 0) return error.InvalidBenchBaseline;
    return identity;
}
fn parseProvenance(value: Value) Error!Provenance {
    if (!keysAllowed(value, &.{ key_revision, key_identity, key_tools, key_platform })) return error.InvalidBenchBaseline;
    var provenance: Provenance = .{};
    provenance.revision = v.text(v.get(value, key_revision));
    if (v.get(value, key_identity) == .null) return error.InvalidBenchBaseline;
    provenance.identity = try parseIdentity(v.get(value, key_identity));
    const tools = v.get(value, key_tools);
    if (tools != .null) {
        if (!keysAllowed(tools, &.{ key_compiler, key_zig, key_qbe })) return error.InvalidBenchBaseline;
        provenance.tools = .{ .compiler = v.text(v.get(tools, key_compiler)), .zig = v.text(v.get(tools, key_zig)), .qbe = v.text(v.get(tools, key_qbe)) };
    }
    const platform = v.get(value, key_platform);
    if (platform != .null) {
        if (!keysAllowed(platform, &.{ key_os, key_arch })) return error.InvalidBenchBaseline;
        provenance.platform = .{ .os = v.text(v.get(platform, key_os)), .arch = v.text(v.get(platform, key_arch)) };
    }
    return provenance;
}
fn parseBatches(allocator: std.mem.Allocator, value: Value) Error![]const Batch {
    if (value != .array or value.array.items.len == 0) return error.InvalidBenchBaseline;
    const raw = try allocator.alloc(Batch, value.array.items.len);
    for (value.array.items, raw) |item, *batch| {
        if (!keysAllowed(item, &.{ key_iterations, key_duration })) return error.InvalidBenchBaseline;
        const iterations = integer(v.get(item, key_iterations)) orelse return error.InvalidBenchBaseline;
        if (iterations == 0) return error.InvalidBenchBaseline;
        batch.* = .{ .iterations = iterations, .duration_ns = integer(v.get(item, key_duration)) orelse return error.InvalidBenchBaseline };
    }
    return raw;
}
fn parseMeasurement(allocator: std.mem.Allocator, value: Value) Error!Measurement {
    if (!keysAllowed(value, &.{ key_id, key_workload, key_fixture, key_median, key_spread, key_raw })) return error.InvalidBenchBaseline;
    const id = v.text(v.get(value, key_id));
    if (id.len == 0) return error.InvalidBenchBaseline;
    const median = real(v.get(value, key_median)) orelse return error.InvalidBenchBaseline;
    if (median <= 0) return error.InvalidBenchBaseline;
    const spread = real(v.get(value, key_spread)) orelse return error.InvalidBenchBaseline;
    if (spread < 0) return error.InvalidBenchBaseline;
    const workload = integer(v.get(value, key_workload)) orelse return error.InvalidBenchBaseline;
    if (workload == 0) return error.InvalidBenchBaseline;
    return .{
        .id = id,
        .workload_version = workload,
        .fixture_identity = v.text(v.get(value, key_fixture)),
        .median_ns_per_op = median,
        .spread_percent = spread,
        .raw = try parseBatches(allocator, v.get(value, key_raw)),
    };
}
fn parseHistory(allocator: std.mem.Allocator, value: Value) Error![]const HistoryEntry {
    if (value != .array) return error.InvalidBenchBaseline;
    const entries = try allocator.alloc(HistoryEntry, value.array.items.len);
    for (value.array.items, entries) |item, *entry| {
        if (!keysAllowed(item, &.{ key_revision, key_approver, key_reason, key_profile, key_old_median, key_new_median })) return error.InvalidBenchBaseline;
        const old = real(v.get(item, key_old_median)) orelse return error.InvalidBenchBaseline;
        const new = real(v.get(item, key_new_median)) orelse return error.InvalidBenchBaseline;
        if (old < 0 or new < 0) return error.InvalidBenchBaseline;
        entry.* = .{
            .revision = v.text(v.get(item, key_revision)),
            .approver = v.text(v.get(item, key_approver)),
            .reason = v.text(v.get(item, key_reason)),
            .runner_profile = v.text(v.get(item, key_profile)),
            .old_median_ns_per_op = old,
            .new_median_ns_per_op = new,
        };
    }
    return entries;
}
/// Parse and validate an approved baseline. Unknown versions, duplicate IDs,
/// nonpositive timings and malformed batches reject before any comparison.
pub fn parseBaseline(allocator: std.mem.Allocator, bytes: []const u8) Error!Baseline {
    const parsed = std.json.parseFromSlice(Value, allocator, bytes, .{ .allocate = .alloc_always }) catch return error.InvalidBenchBaseline;
    const root = parsed.value;
    if (!keysAllowed(root, &.{ key_version, key_provenance, key_measurements, key_history })) return error.InvalidBenchBaseline;
    if (!eql(v.text(v.get(root, key_version)), baseline_version)) return error.InvalidBenchBaseline;
    if (v.get(root, key_provenance) == .null or v.get(root, key_measurements) != .array) return error.InvalidBenchBaseline;
    var baseline: Baseline = .{ .provenance = try parseProvenance(v.get(root, key_provenance)) };
    const list = v.get(root, key_measurements);
    const measurements = try allocator.alloc(Measurement, list.array.items.len);
    for (list.array.items, 0..) |item, index| {
        measurements[index] = try parseMeasurement(allocator, item);
        for (measurements[0..index]) |prior| {
            if (eql(prior.id, measurements[index].id)) return error.InvalidBenchBaseline;
        }
    }
    baseline.measurements = measurements;
    if (v.get(root, key_history) != .null) baseline.history = try parseHistory(allocator, v.get(root, key_history));
    return baseline;
}
/// Whether an identity matches the baseline provenance closely enough to compare.
pub fn comparable(identity: Identity, approved: Identity) bool {
    return eql(identity.mode, approved.mode) and eql(identity.runner_profile, approved.runner_profile) and
        identity.boundary_version == approved.boundary_version and identity.warmup_iterations == approved.warmup_iterations and
        identity.batch_count == approved.batch_count and identity.target_batch_ns == approved.target_batch_ns;
}
/// Decide one benchmark. Equality with a limit passes; growth below the absolute
/// delta floor is ignored; every incompatible or missing input is explicit.
pub fn compare(run: Run, current: Measurement) Comparison {
    const limits = run.policy.limitFor(current.id);
    if (!eql(run.policy.runner_profile, run.identity.runner_profile)) return .{ .id = current.id, .verdict = .incompatible, .reason = "policy runner profile does not match the run", .limits = limits };
    const baseline = run.baseline orelse return .{ .id = current.id, .verdict = .unbaselined, .reason = "no approved baseline", .limits = limits };
    if (!comparable(run.identity, baseline.provenance.identity)) return .{ .id = current.id, .verdict = .incompatible, .reason = "measurement identity differs from the baseline", .limits = limits };
    const approved = baseline.find(current.id) orelse return .{ .id = current.id, .verdict = .unbaselined, .reason = "no approved measurement for this benchmark", .limits = limits };
    if (approved.workload_version != current.workload_version or !eql(approved.fixture_identity, current.fixture_identity)) {
        return .{ .id = current.id, .verdict = .incompatible, .reason = "workload version or fixture identity differs from the baseline", .limits = limits };
    }
    const percent = (current.median_ns_per_op - approved.median_ns_per_op) / approved.median_ns_per_op * 100;
    var result: Comparison = .{
        .id = current.id,
        .verdict = .pass,
        .reason = "within limits",
        .baseline_ns_per_op = approved.median_ns_per_op,
        .current_ns_per_op = current.median_ns_per_op,
        .percent_change = percent,
        .limits = limits,
    };
    if (limits.max_ns_per_op) |ceiling| {
        if (current.median_ns_per_op > ceiling) {
            result.verdict = .ceiling;
            result.reason = "nanoseconds per operation exceed the absolute ceiling";
            return result;
        }
    }
    const delta = current.median_ns_per_op - approved.median_ns_per_op;
    if (percent > limits.allowed_growth_percent and delta > limits.minimum_meaningful_delta_ns) {
        result.verdict = .regression;
        result.reason = "relative growth exceeds the allowed limit";
    }
    return result;
}
/// Whether a comparison is close enough to a limit, or noisy enough, to warrant
/// the single predefined confirmation run before the verdict is trusted.
pub fn needsConfirmation(policy: *const Policy, current: Measurement, comparison: Comparison) bool {
    if (current.spread_percent > policy.noise.max_relative_spread_percent) return true;
    const margin = policy.noise.near_limit_margin_percent / 100;
    if (comparison.limits.max_ns_per_op) |ceiling| {
        if (current.median_ns_per_op >= ceiling * (1 - margin)) return true;
    }
    if (comparison.baseline_ns_per_op > 0) {
        const threshold = comparison.baseline_ns_per_op * (1 + comparison.limits.allowed_growth_percent / 100);
        if (current.median_ns_per_op >= threshold * (1 - margin)) return true;
    }
    return false;
}
/// Downgrade a passing comparison to inconclusive when the combined samples
/// still exceed the noise budget after the single predefined confirmation.
pub fn applyNoiseBudget(policy: *const Policy, current: Measurement, comparison: Comparison) Comparison {
    if (comparison.verdict != .pass) return comparison;
    if (current.spread_percent <= policy.noise.max_relative_spread_percent) return comparison;
    var result = comparison;
    result.verdict = .inconclusive;
    result.reason = "measurement noise exceeds the policy budget after confirmation";
    return result;
}
/// Whether every required benchmark ID has a passing measurement. A missing or
/// removed required case is incomplete coverage, never a green gate.
pub fn coversRequired(policy: *const Policy, measurements: []const Measurement) bool {
    for (policy.required) |required| {
        var found = false;
        for (measurements) |measurement| {
            if (std.mem.eql(u8, measurement.id, required)) {
                found = true;
                break;
            }
        }
        if (!found) return false;
    }
    return true;
}
/// Concatenate two runs' raw batches so a confirmation is evaluated as one sample.
pub fn combinedRaw(allocator: std.mem.Allocator, first: []const Batch, second: []const Batch) Error![]const Batch {
    const raw = try allocator.alloc(Batch, first.len + second.len);
    @memcpy(raw[0..first.len], first);
    @memcpy(raw[first.len..], second);
    return raw;
}
/// Human-readable verdict tag for reports and text summaries.
pub fn verdictName(verdict: Verdict) []const u8 {
    return switch (verdict) {
        .pass => "pass",
        .regression => "regression",
        .ceiling => "ceiling",
        .unbaselined => "unbaselined",
        .incompatible => "incompatible",
        .inconclusive => "inconclusive",
        .missing => "missing",
    };
}
/// Overall gate outcome: any non-pass verdict or incomplete coverage blocks.
pub fn allPassed(comparisons: []const Comparison, complete: bool) bool {
    if (!complete or comparisons.len == 0) return false;
    for (comparisons) |comparison| if (comparison.verdict != .pass) return false;
    return true;
}
fn identityValue(allocator: std.mem.Allocator, identity: Identity) Error!Value {
    return makeObject(allocator, &.{
        .{ .key = key_mode, .value = .{ .string = identity.mode } },
        .{ .key = key_profile, .value = .{ .string = identity.runner_profile } },
        .{ .key = key_boundary, .value = .{ .integer = @intCast(identity.boundary_version) } },
        .{ .key = key_warmup, .value = .{ .integer = @intCast(identity.warmup_iterations) } },
        .{ .key = key_batch_count, .value = .{ .integer = @intCast(identity.batch_count) } },
        .{ .key = key_target, .value = .{ .integer = @intCast(identity.target_batch_ns) } },
    });
}
fn limitsValue(allocator: std.mem.Allocator, limits: Limits) Error!Value {
    return makeObject(allocator, &.{
        .{ .key = key_allowed_growth, .value = .{ .float = limits.allowed_growth_percent } },
        .{ .key = key_minimum_delta, .value = .{ .float = limits.minimum_meaningful_delta_ns } },
        .{ .key = key_max_ceiling, .value = if (limits.max_ns_per_op) |ceiling| .{ .float = ceiling } else .null },
    });
}
fn provenanceValue(allocator: std.mem.Allocator, provenance: Provenance) Error!Value {
    const tools = try makeObject(allocator, &.{
        .{ .key = key_compiler, .value = .{ .string = provenance.tools.compiler } },
        .{ .key = key_zig, .value = .{ .string = provenance.tools.zig } },
        .{ .key = key_qbe, .value = .{ .string = provenance.tools.qbe } },
    });
    const platform = try makeObject(allocator, &.{
        .{ .key = key_os, .value = .{ .string = provenance.platform.os } },
        .{ .key = key_arch, .value = .{ .string = provenance.platform.arch } },
    });
    return makeObject(allocator, &.{
        .{ .key = key_revision, .value = .{ .string = provenance.revision } },
        .{ .key = key_identity, .value = try identityValue(allocator, provenance.identity) },
        .{ .key = key_tools, .value = tools },
        .{ .key = key_platform, .value = platform },
    });
}
fn rawValue(allocator: std.mem.Allocator, raw: []const Batch) Error!Value {
    var array: std.json.Array = .init(allocator);
    for (raw) |batch| array.append(try makeObject(allocator, &.{
        .{ .key = key_iterations, .value = .{ .integer = @intCast(batch.iterations) } },
        .{ .key = key_duration, .value = .{ .integer = @intCast(batch.duration_ns) } },
    })) catch return error.OutOfMemory;
    return .{ .array = array };
}
fn measurementValue(allocator: std.mem.Allocator, measurement: Measurement) Error!Value {
    return makeObject(allocator, &.{
        .{ .key = key_id, .value = .{ .string = measurement.id } },
        .{ .key = key_workload, .value = .{ .integer = @intCast(measurement.workload_version) } },
        .{ .key = key_fixture, .value = .{ .string = measurement.fixture_identity } },
        .{ .key = key_median, .value = .{ .float = measurement.median_ns_per_op } },
        .{ .key = key_spread, .value = .{ .float = measurement.spread_percent } },
        .{ .key = key_raw, .value = try rawValue(allocator, measurement.raw) },
    });
}
fn comparisonValue(allocator: std.mem.Allocator, comparison: Comparison) Error!Value {
    return makeObject(allocator, &.{
        .{ .key = key_id, .value = .{ .string = comparison.id } },
        .{ .key = "verdict", .value = .{ .string = verdictName(comparison.verdict) } },
        .{ .key = key_reason, .value = .{ .string = comparison.reason } },
        .{ .key = key_baseline_ns, .value = .{ .float = comparison.baseline_ns_per_op } },
        .{ .key = key_current_ns, .value = .{ .float = comparison.current_ns_per_op } },
        .{ .key = key_percent_change, .value = .{ .float = comparison.percent_change } },
        .{ .key = "limits", .value = try limitsValue(allocator, comparison.limits) },
    });
}
fn historyValue(allocator: std.mem.Allocator, entry: HistoryEntry) Error!Value {
    return makeObject(allocator, &.{
        .{ .key = key_revision, .value = .{ .string = entry.revision } },
        .{ .key = key_approver, .value = .{ .string = entry.approver } },
        .{ .key = key_reason, .value = .{ .string = entry.reason } },
        .{ .key = key_profile, .value = .{ .string = entry.runner_profile } },
        .{ .key = key_old_median, .value = .{ .float = entry.old_median_ns_per_op } },
        .{ .key = key_new_median, .value = .{ .float = entry.new_median_ns_per_op } },
    });
}
/// Serialize a run report with raw samples, provenance and every verdict.
pub fn renderReport(allocator: std.mem.Allocator, report: ReportInput) Error![]const u8 {
    var measurements: std.json.Array = .init(allocator);
    for (report.measurements) |measurement| measurements.append(try measurementValue(allocator, measurement)) catch return error.OutOfMemory;
    var comparisons: std.json.Array = .init(allocator);
    for (report.comparisons) |comparison| comparisons.append(try comparisonValue(allocator, comparison)) catch return error.OutOfMemory;
    var failures: std.json.Array = .init(allocator);
    for (report.failures) |failure| failures.append(try makeObject(allocator, &.{
        .{ .key = key_id, .value = .{ .string = failure.id } },
        .{ .key = key_status, .value = .{ .string = failure.status } },
        .{ .key = key_reason, .value = .{ .string = failure.reason } },
    })) catch return error.OutOfMemory;
    const root = try makeObject(allocator, &.{
        .{ .key = key_version, .value = .{ .string = report_version } },
        .{ .key = "boundary", .value = .{ .string = boundary } },
        .{ .key = key_complete, .value = .{ .bool = report.complete } },
        .{ .key = "passed", .value = .{ .bool = report.passed } },
        .{ .key = key_provenance, .value = try provenanceValue(allocator, report.provenance) },
        .{ .key = key_measurements, .value = .{ .array = measurements } },
        .{ .key = key_comparisons, .value = .{ .array = comparisons } },
        .{ .key = key_failures, .value = .{ .array = failures } },
    });
    return std.json.Stringify.valueAlloc(allocator, root, .{}) catch return error.OutOfMemory;
}
/// Promote a complete, passing candidate into a new approved baseline. History
/// retains every replaced measurement together with its approver and reason.
pub fn promote(allocator: std.mem.Allocator, promotion: Promotion) Error![]const u8 {
    if (!promotion.report.complete or !promotion.report.passed) return error.InvalidBenchPromotion;
    if (promotion.approver.len == 0 or promotion.reason.len == 0) return error.InvalidBenchPromotion;
    var measurements: std.json.Array = .init(allocator);
    for (promotion.report.measurements) |measurement| measurements.append(try measurementValue(allocator, measurement)) catch return error.OutOfMemory;
    var history: std.json.Array = .init(allocator);
    var retained: usize = 0;
    if (promotion.old_baseline) |old| {
        for (old.history) |entry| {
            if (retained >= history_limit) break;
            history.append(try historyValue(allocator, entry)) catch return error.OutOfMemory;
            retained += 1;
        }
        for (promotion.report.measurements) |measurement| {
            const previous = old.find(measurement.id) orelse continue;
            if (previous.median_ns_per_op == measurement.median_ns_per_op) continue;
            if (retained >= history_limit) break;
            history.append(try historyValue(allocator, .{
                .revision = promotion.revision,
                .approver = promotion.approver,
                .reason = promotion.reason,
                .runner_profile = promotion.report.provenance.identity.runner_profile,
                .old_median_ns_per_op = previous.median_ns_per_op,
                .new_median_ns_per_op = measurement.median_ns_per_op,
            })) catch return error.OutOfMemory;
            retained += 1;
        }
    }
    const provenance = try provenanceValue(allocator, .{
        .revision = promotion.revision,
        .identity = promotion.report.provenance.identity,
        .tools = promotion.report.provenance.tools,
        .platform = promotion.report.provenance.platform,
    });
    const root = try makeObject(allocator, &.{
        .{ .key = key_version, .value = .{ .string = baseline_version } },
        .{ .key = key_provenance, .value = provenance },
        .{ .key = key_measurements, .value = .{ .array = measurements } },
        .{ .key = key_history, .value = .{ .array = history } },
    });
    return std.json.Stringify.valueAlloc(allocator, root, .{}) catch return error.OutOfMemory;
}

// spec: NATIVE-BENCH-2
test "benchmark statistics use the median rate and an interquartile spread" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const stats = try summarize(a, &.{
        .{ .iterations = 100, .duration_ns = 1000 },
        .{ .iterations = 100, .duration_ns = 1100 },
        .{ .iterations = 100, .duration_ns = 1200 },
        .{ .iterations = 100, .duration_ns = 1300 },
        .{ .iterations = 100, .duration_ns = 1400 },
    }, 100);
    try std.testing.expectApproxEqAbs(@as(f64, 12), stats.median_ns_per_op, 0.0001);
    try std.testing.expectApproxEqAbs(@as(f64, 16.666666666666664), stats.spread_percent, 0.0001);
    try std.testing.expectEqual(@as(usize, 5), stats.sample_count);
    try std.testing.expectEqual(@as(u64, 100), stats.calibrated_iterations);
    try std.testing.expectEqual(@as(?f64, null), nsPerOp(.{ .iterations = 0, .duration_ns = 1 }));
    try std.testing.expectError(error.InvalidBenchReport, summarize(a, &.{.{ .iterations = 0, .duration_ns = 1 }}, 1));
}

// spec: NATIVE-BENCH-3
test "benchmark policy validation accepts limits overrides and rejects malformed data" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const policy = try parsePolicy(a,
        \\{"version":"bench-policy-v1","runner_profile":"linux-release","default":{"allowed_growth_percent":10,"minimum_meaningful_delta_ns":2,"max_ns_per_op":500},
        \\ "benchmarks":[{"id":"main::bench_sum","allowed_growth_percent":0}],"required":["main::bench_sum"],
        \\ "noise":{"max_relative_spread_percent":15,"near_limit_margin_percent":5,"confirmation_runs":1}}
    );
    try std.testing.expectEqualStrings("linux-release", policy.runner_profile);
    try std.testing.expectEqual(@as(f64, 10), policy.default.allowed_growth_percent);
    try std.testing.expectEqual(@as(f64, 0), policy.limitFor("main::bench_sum").allowed_growth_percent);
    try std.testing.expectEqual(@as(f64, 500), policy.limitFor("main::bench_other").max_ns_per_op.?);
    try std.testing.expectEqual(@as(usize, 1), policy.required.len);
    try std.testing.expectEqual(@as(u8, 1), policy.noise.confirmation_runs);
    for ([_][]const u8{
        \\{"version":"bench-policy-v2"}
        ,
        \\{"version":"bench-policy-v1","default":{"allowed_growth_percent":-1}}
        ,
        \\{"version":"bench-policy-v1","default":{"max_ns_per_op":0}}
        ,
        \\{"version":"bench-policy-v1","default":{"unknown":1}}
        ,
        \\{"version":"bench-policy-v1","benchmarks":[{"id":"x"},{"id":"x"}]}
        ,
        \\{"version":"bench-policy-v1","noise":{"confirmation_runs":2}}
        ,
    }) |bytes| try std.testing.expectError(error.InvalidBenchPolicy, parsePolicy(a, bytes));
}

// spec-case: NATIVE-BENCH-3
test "benchmark baseline parsing rejects duplicate ids and nonpositive timings" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const provenance = "{\"revision\":\"abc\",\"identity\":{\"mode\":\"ReleaseFast\",\"runner_profile\":\"r\"," ++
        "\"boundary_version\":1,\"warmup_iterations\":3,\"batch_count\":9,\"target_batch_ns\":250000000}," ++
        "\"tools\":{\"compiler\":\"c\",\"zig\":\"z\",\"qbe\":\"q\"},\"platform\":{\"os\":\"linux\",\"arch\":\"x86_64\"}}";
    const measurement = "{\"id\":\"main::bench_sum\",\"workload_version\":1,\"fixture_identity\":\"f\",\"median_ns_per_op\":12.5,\"spread_percent\":1.0,\"raw\":[{\"iterations\":10,\"duration_ns\":125}]}";
    const good = try std.fmt.allocPrint(a, "{{\"version\":\"bench-baseline-v1\",\"provenance\":{s},\"measurements\":[{s}]}}", .{ provenance, measurement });
    const baseline = try parseBaseline(a, good);
    try std.testing.expectEqual(@as(f64, 12.5), baseline.find("main::bench_sum").?.median_ns_per_op);
    const duplicate = try std.fmt.allocPrint(a, "{{\"version\":\"bench-baseline-v1\",\"provenance\":{s},\"measurements\":[{s},{s}]}}", .{ provenance, measurement, measurement });
    try std.testing.expectError(error.InvalidBenchBaseline, parseBaseline(a, duplicate));
    const nonpositive = try std.fmt.allocPrint(a, "{{\"version\":\"bench-baseline-v1\",\"provenance\":{s},\"measurements\":[{{\"id\":\"x\",\"median_ns_per_op\":0,\"raw\":[{{\"iterations\":1,\"duration_ns\":1}}]}}]}}", .{provenance});
    try std.testing.expectError(error.InvalidBenchBaseline, parseBaseline(a, nonpositive));
    try std.testing.expectError(error.InvalidBenchBaseline, parseBaseline(a, "{\"version\":\"bench-baseline-v2\"}"));
    const empty = try parseBaseline(a, "{\"version\":\"bench-baseline-v1\",\"provenance\":" ++ provenance ++ ",\"measurements\":[]}");
    try std.testing.expectEqual(@as(usize, 0), empty.measurements.len);
    try std.testing.expectError(error.InvalidBenchBaseline, parseBaseline(a, "{\"version\":\"bench-baseline-v1\",\"provenance\":" ++ provenance ++ ",\"measurements\":[],\"extra\":1}"));
}

fn at(id: []const u8, median: f64) Measurement {
    return .{ .id = id, .median_ns_per_op = median, .fixture_identity = "f" };
}
const debug_identity: Identity = .{ .mode = "Debug", .runner_profile = "r", .boundary_version = 1, .warmup_iterations = 3, .batch_count = 9, .target_batch_ns = 250000000 };

// spec: NATIVE-BENCH-4
test "benchmark comparison applies thresholds, floors and absolute ceilings exactly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const policy = try parsePolicy(a, "{\"version\":\"bench-policy-v1\",\"runner_profile\":\"r\",\"default\":{\"allowed_growth_percent\":10,\"minimum_meaningful_delta_ns\":5,\"max_ns_per_op\":1000}}");
    const baseline: Baseline = .{ .provenance = .{ .identity = debug_identity }, .measurements = &.{at("main::bench_sum", 100)} };
    const run: Run = .{ .policy = &policy, .baseline = &baseline, .identity = .{ .mode = "Debug", .runner_profile = "r" } };
    try std.testing.expectEqual(Verdict.pass, compare(run, at("main::bench_sum", 102)).verdict);
    // Equality with the relative limit passes even when the delta floor is met.
    try std.testing.expectEqual(Verdict.pass, compare(run, at("main::bench_sum", 110)).verdict);
    const regression = compare(run, at("main::bench_sum", 111));
    try std.testing.expectEqual(Verdict.regression, regression.verdict);
    try std.testing.expectApproxEqAbs(@as(f64, 11), regression.percent_change, 0.0001);
    // The absolute ceiling is independent of relative growth.
    const ceiling_baseline: Baseline = .{ .provenance = .{ .identity = debug_identity }, .measurements = &.{at("main::bench_ceiling", 1000)} };
    const ceiling_run: Run = .{ .policy = &policy, .baseline = &ceiling_baseline, .identity = .{ .mode = "Debug", .runner_profile = "r" } };
    try std.testing.expectEqual(Verdict.pass, compare(ceiling_run, at("main::bench_ceiling", 1000)).verdict);
    try std.testing.expectEqual(Verdict.ceiling, compare(ceiling_run, at("main::bench_ceiling", 1001)).verdict);
    // Zero tolerance with a zero delta floor turns any growth into a regression.
    const zero = try parsePolicy(a, "{\"version\":\"bench-policy-v1\",\"runner_profile\":\"r\",\"default\":{\"allowed_growth_percent\":0,\"minimum_meaningful_delta_ns\":0}}");
    const zero_run: Run = .{ .policy = &zero, .baseline = &baseline, .identity = .{ .mode = "Debug", .runner_profile = "r" } };
    try std.testing.expectEqual(Verdict.pass, compare(zero_run, at("main::bench_sum", 100)).verdict);
    try std.testing.expectEqual(Verdict.regression, compare(zero_run, at("main::bench_sum", 100.5)).verdict);
    // A new benchmark, a changed fixture and a changed mode are explicit.
    try std.testing.expectEqual(Verdict.unbaselined, compare(run, at("main::bench_new", 1)).verdict);
    const changed_fixture = Measurement{ .id = "main::bench_sum", .median_ns_per_op = 100, .fixture_identity = "g" };
    try std.testing.expectEqual(Verdict.incompatible, compare(run, changed_fixture).verdict);
    const wrong_mode: Run = .{ .policy = &policy, .baseline = &baseline, .identity = .{ .mode = "ReleaseFast", .runner_profile = "r" } };
    try std.testing.expectEqual(Verdict.incompatible, compare(wrong_mode, at("main::bench_sum", 100)).verdict);
    const no_baseline: Run = .{ .policy = &policy, .baseline = null, .identity = .{ .mode = "Debug", .runner_profile = "r" } };
    try std.testing.expectEqual(Verdict.unbaselined, compare(no_baseline, at("main::bench_sum", 100)).verdict);
    try std.testing.expect(!allPassed(&.{regression}, true));
    try std.testing.expect(!allPassed(&.{regression}, false));
    try std.testing.expect(allPassed(&.{compare(run, at("main::bench_sum", 100))}, true));
}

// spec-case: NATIVE-BENCH-4
test "noise policy requests at most one confirmation near a limit" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const policy = try parsePolicy(a, "{\"version\":\"bench-policy-v1\",\"runner_profile\":\"r\"," ++
        "\"default\":{\"allowed_growth_percent\":10,\"minimum_meaningful_delta_ns\":1,\"max_ns_per_op\":100}," ++
        "\"noise\":{\"max_relative_spread_percent\":5,\"near_limit_margin_percent\":10}}");
    const comparison = Comparison{ .id = "b", .verdict = .pass, .reason = "within limits", .baseline_ns_per_op = 50, .current_ns_per_op = 54, .percent_change = 8, .limits = policy.default };
    const noisy = Measurement{ .id = "b", .median_ns_per_op = 54, .spread_percent = 9, .raw = &.{.{ .iterations = 1, .duration_ns = 54 }} };
    try std.testing.expect(needsConfirmation(&policy, noisy, comparison));
    const quiet = Measurement{ .id = "b", .median_ns_per_op = 54, .spread_percent = 1, .raw = &.{.{ .iterations = 1, .duration_ns = 54 }} };
    try std.testing.expect(needsConfirmation(&policy, quiet, comparison));
    // A wide allowance puts the value far from both the ceiling and the
    // relative threshold, so no confirmation is needed.
    const far_limits = Limits{ .allowed_growth_percent = 100, .minimum_meaningful_delta_ns = 1, .max_ns_per_op = 10_000 };
    const far = Comparison{ .id = "b", .verdict = .pass, .reason = "within limits", .baseline_ns_per_op = 50, .current_ns_per_op = 51, .percent_change = 2, .limits = far_limits };
    const safe = Measurement{ .id = "b", .median_ns_per_op = 51, .spread_percent = 1, .raw = &.{.{ .iterations = 1, .duration_ns = 51 }} };
    try std.testing.expect(!needsConfirmation(&policy, safe, far));
    const combined = try combinedRaw(a, &.{.{ .iterations = 1, .duration_ns = 50 }}, &.{.{ .iterations = 1, .duration_ns = 60 }});
    try std.testing.expectEqual(@as(usize, 2), combined.len);
}

// spec: NATIVE-BENCH-5
test "a report renders raw samples and a reviewed promotion records its reason" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const measurement = Measurement{ .id = "main::bench_sum", .median_ns_per_op = 12.5, .spread_percent = 2, .fixture_identity = "f", .raw = &.{.{ .iterations = 10, .duration_ns = 125 }} };
    const comparison = Comparison{ .id = "main::bench_sum", .verdict = .pass, .reason = "within limits", .baseline_ns_per_op = 12, .current_ns_per_op = 12.5, .percent_change = 4.16, .limits = .{} };
    const report: ReportInput = .{
        .provenance = .{ .identity = .{ .mode = "ReleaseFast", .runner_profile = "r" } },
        .measurements = &.{measurement},
        .comparisons = &.{comparison},
        .failures = &.{.{ .id = "main::bench_bad", .status = "trap", .reason = "boom" }},
        .complete = true,
        .passed = true,
    };
    const rendered = try renderReport(a, report);
    const parsed = try std.json.parseFromSlice(Value, a, rendered, .{});
    try std.testing.expectEqualStrings(report_version, v.text(v.get(parsed.value, key_version)));
    try std.testing.expectEqualStrings(boundary, v.text(v.get(parsed.value, "boundary")));
    try std.testing.expect(v.boolean(v.get(parsed.value, key_complete)));
    try std.testing.expectEqual(@as(usize, 1), v.array(v.get(parsed.value, key_measurements)).len);
    try std.testing.expectEqualStrings("pass", v.text(v.get(v.array(v.get(parsed.value, "comparisons"))[0], "verdict")));
    const incomplete: ReportInput = .{ .provenance = report.provenance, .measurements = report.measurements, .comparisons = report.comparisons, .complete = false, .passed = false };
    try std.testing.expectError(error.InvalidBenchPromotion, promote(a, .{ .report = incomplete, .approver = "maintainer", .reason = "faster", .revision = "deadbeef" }));
    const previous_json = "{\"version\":\"bench-baseline-v1\",\"provenance\":{\"identity\":{" ++
        "\"mode\":\"ReleaseFast\",\"runner_profile\":\"r\",\"boundary_version\":1," ++
        "\"warmup_iterations\":3,\"batch_count\":9,\"target_batch_ns\":250000000}}," ++
        "\"measurements\":[{\"id\":\"main::bench_sum\",\"workload_version\":1,\"fixture_identity\":\"f\"," ++
        "\"median_ns_per_op\":12.0,\"spread_percent\":0.5,\"raw\":[{\"iterations\":10,\"duration_ns\":120}]}]}";
    const previous = try parseBaseline(a, previous_json);
    const promoted = try promote(a, .{ .report = report, .approver = "maintainer", .reason = "accept 4% growth", .revision = "deadbeef", .old_baseline = &previous });
    const baseline = try parseBaseline(a, promoted);
    try std.testing.expectEqual(@as(f64, 12.5), baseline.find("main::bench_sum").?.median_ns_per_op);
    try std.testing.expectEqualStrings("deadbeef", baseline.provenance.revision);
    try std.testing.expectEqual(@as(usize, 1), baseline.history.len);
    try std.testing.expectEqualStrings("maintainer", baseline.history[0].approver);
    try std.testing.expectEqual(@as(f64, 12.0), baseline.history[0].old_median_ns_per_op);
    try std.testing.expect(!allPassed(&.{comparison}, false));
}

// spec: NATIVE-BENCH-1
test "benchmark discovery validates cases, named sizes and expectations" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const schema = (try std.json.parseFromSlice(Value, a,
        \\{"functions":[{"name":"main::bench_sum","result":"i64"},{"name":"main::bench_ok","result":"bool"}]}
    , .{})).value;
    const config = (try std.json.parseFromSlice(Value, a,
        \\{"main::bench_sum":{"sizes":{"small":{"arguments":{"n":"1"},"expected":"1"},"large":{"arguments":{"n":"100"},"expected":"5050"}},"workload_version":2},"main::bench_ok":{}}
    , .{})).value;
    const selected = try discover(a, schema, config, "*");
    try std.testing.expectEqual(@as(usize, 3), selected.len);
    try std.testing.expectEqualStrings("main::bench_sum[small]", selected[0].id);
    try std.testing.expectEqualStrings("main::bench_sum[large]", selected[1].id);
    try std.testing.expectEqualStrings("main::bench_ok", selected[2].id);
    try std.testing.expectEqual(@as(u64, 2), selected[0].workload_version);
    try std.testing.expect(selected[0].fixture_identity.len != 0);
    try std.testing.expect(!std.mem.eql(u8, selected[0].fixture_identity, selected[1].fixture_identity));
    try std.testing.expectEqualStrings("1", selected[0].case.arguments.object.get("n").?.string);
    try std.testing.expect(selected[2].case.expected.bool);
    // A non-object configuration, an unknown key and malformed settings reject.
    try std.testing.expectError(error.InvalidBenchCases, discover(a, schema, .{ .bool = true }, "*"));
    const unknown = (try std.json.parseFromSlice(Value, a,
        \\{"main::bench_missing":{}}
    , .{})).value;
    try std.testing.expectError(error.UnknownBenchmark, discover(a, schema, unknown, "*"));
    const misspelled = (try std.json.parseFromSlice(Value, a,
        \\{"main::bench_sum":{"sizez":{}}}
    , .{})).value;
    try std.testing.expectError(error.InvalidBenchCases, discover(a, schema, misspelled, "bench_sum"));
    const empty_sizes = (try std.json.parseFromSlice(Value, a,
        \\{"main::bench_sum":{"sizes":{}}}
    , .{})).value;
    try std.testing.expectError(error.InvalidBenchCases, discover(a, schema, empty_sizes, "bench_sum"));
    // A non-boolean result without an explicit expectation is a configuration error.
    try std.testing.expectError(error.MissingBenchExpectation, discover(a, schema, .null, "bench_sum"));
}

fn parseComparisonReport(allocator: std.mem.Allocator, value: Value) Error!Comparison {
    if (!keysAllowed(value, &.{ key_id, key_verdict, key_reason, key_baseline_ns, key_current_ns, key_percent_change, "limits" })) return error.InvalidBenchReport;
    const id = v.text(v.get(value, key_id));
    if (id.len == 0) return error.InvalidBenchReport;
    const verdict = std.meta.stringToEnum(Verdict, v.text(v.get(value, key_verdict))) orelse return error.InvalidBenchReport;
    const limits_value = v.get(value, "limits");
    if (!keysAllowed(limits_value, &.{ key_allowed_growth, key_minimum_delta, key_max_ceiling })) return error.InvalidBenchReport;
    var limits: Limits = .{
        .allowed_growth_percent = real(v.get(limits_value, key_allowed_growth)) orelse return error.InvalidBenchReport,
        .minimum_meaningful_delta_ns = real(v.get(limits_value, key_minimum_delta)) orelse return error.InvalidBenchReport,
    };
    if (v.get(limits_value, key_max_ceiling) != .null) limits.max_ns_per_op = real(v.get(limits_value, key_max_ceiling)) orelse return error.InvalidBenchReport;
    _ = allocator;
    return .{
        .id = id,
        .verdict = verdict,
        .reason = v.text(v.get(value, key_reason)),
        .baseline_ns_per_op = real(v.get(value, key_baseline_ns)) orelse 0,
        .current_ns_per_op = real(v.get(value, key_current_ns)) orelse 0,
        .percent_change = real(v.get(value, key_percent_change)) orelse 0,
        .limits = limits,
    };
}
fn parseFailureReport(value: Value) Error!Failure {
    if (!keysAllowed(value, &.{ key_id, key_status, key_reason })) return error.InvalidBenchReport;
    const id = v.text(v.get(value, key_id));
    const status = v.text(v.get(value, key_status));
    if (id.len == 0 or status.len == 0) return error.InvalidBenchReport;
    return .{ .id = id, .status = status, .reason = v.text(v.get(value, key_reason)) };
}
/// Parse a candidate run report back into comparable fields for promotion.
pub fn parseReport(allocator: std.mem.Allocator, bytes: []const u8) Error!ReportInput {
    const parsed = std.json.parseFromSlice(Value, allocator, bytes, .{ .allocate = .alloc_always }) catch return error.InvalidBenchReport;
    const root = parsed.value;
    if (!keysAllowed(root, &.{ key_version, "boundary", key_complete, "passed", key_provenance, key_measurements, key_comparisons, key_failures })) return error.InvalidBenchReport;
    if (!eql(v.text(v.get(root, key_version)), report_version)) return error.InvalidBenchReport;
    if (v.get(root, key_measurements) != .array or v.get(root, key_complete) != .bool or v.get(root, "passed") != .bool) return error.InvalidBenchReport;
    const provenance = parseProvenance(v.get(root, key_provenance)) catch return error.InvalidBenchReport;
    const list = v.get(root, key_measurements);
    const measurements = try allocator.alloc(Measurement, list.array.items.len);
    for (list.array.items, 0..) |item, index| {
        measurements[index] = parseMeasurement(allocator, item) catch return error.InvalidBenchReport;
    }
    var comparisons: []const Comparison = &.{};
    const comparisons_value = v.get(root, key_comparisons);
    if (comparisons_value != .null) {
        if (comparisons_value != .array) return error.InvalidBenchReport;
        const parse_comparisons = try allocator.alloc(Comparison, comparisons_value.array.items.len);
        for (comparisons_value.array.items, 0..) |item, index| parse_comparisons[index] = try parseComparisonReport(allocator, item);
        comparisons = parse_comparisons;
    }
    var failures: []const Failure = &.{};
    const failures_value = v.get(root, key_failures);
    if (failures_value != .null) {
        if (failures_value != .array) return error.InvalidBenchReport;
        const parse_failures = try allocator.alloc(Failure, failures_value.array.items.len);
        for (failures_value.array.items, 0..) |item, index| parse_failures[index] = try parseFailureReport(item);
        failures = parse_failures;
    }
    return .{
        .provenance = provenance,
        .measurements = measurements,
        .comparisons = comparisons,
        .failures = failures,
        .complete = v.boolean(v.get(root, key_complete)),
        .passed = v.boolean(v.get(root, "passed")),
    };
}

// spec-case: NATIVE-BENCH-4
test "unresolved noise is inconclusive and required coverage must be present" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const policy = try parsePolicy(a, "{\"version\":\"bench-policy-v1\",\"runner_profile\":\"r\",\"noise\":{\"max_relative_spread_percent\":5},\"required\":[\"main::bench_sum\"]}");
    const passing = Comparison{ .id = "main::bench_sum", .verdict = .pass, .reason = "within limits" };
    const quiet = Measurement{ .id = "main::bench_sum", .median_ns_per_op = 10, .spread_percent = 1 };
    const noisy = Measurement{ .id = "main::bench_sum", .median_ns_per_op = 10, .spread_percent = 9 };
    try std.testing.expectEqual(Verdict.pass, applyNoiseBudget(&policy, quiet, passing).verdict);
    const inconclusive = applyNoiseBudget(&policy, noisy, passing);
    try std.testing.expectEqual(Verdict.inconclusive, inconclusive.verdict);
    // A regression stays a regression even when the samples are noisy.
    try std.testing.expectEqual(Verdict.regression, applyNoiseBudget(&policy, noisy, .{ .id = "main::bench_sum", .verdict = .regression, .reason = "growth" }).verdict);
    try std.testing.expect(coversRequired(&policy, &.{quiet}));
    try std.testing.expect(!coversRequired(&policy, &.{.{ .id = "main::bench_other", .median_ns_per_op = 1 }}));
}
