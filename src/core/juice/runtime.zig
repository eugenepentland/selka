//! Frequency-normalized CPU cost estimates and independent elapsed-time validation.
const std = @import("std");
const key_reference_cycles = "reference_cycles";
const d = @import("data.zig");
const C = d.Context;
const V = d.Value;
const spread_limit = 0.03;
const target_error = 0.05;

fn summary(c: *C, cell: V, metric: []const u8) !V {
    const recorded = try d.req(try d.req(cell, "metrics"), metric);
    const samples = try d.items(try d.req(recorded, "samples"));
    if (samples.len < 2 or samples.len > 30) return c.fail("runtime proxy requires 2..30 complete samples");
    const values = try c.a.alloc(f64, samples.len);
    for (samples, values) |sample, *value| value.* = try d.positive(sample);
    const actual = try d.summary(c, values);
    for ([_][]const u8{ "median", "min", "max", "spread" }) |key| {
        if (try d.num(try d.req(recorded, key)) != try d.num(d.get(actual, key))) return c.fail("runtime metric summary disagrees with samples");
    }
    return actual;
}
fn ratio(c: *C, a: V, b: V, metric: []const u8) !V {
    const left = try summary(c, a, metric);
    const right = try summary(c, b, metric);
    const scale = try d.positive(d.get(a, "units")) / try d.positive(d.get(b, "units"));
    const pairing = d.get(a, "pairing");
    if (pairing != .null or d.get(b, "pairing") != .null) {
        if (!d.equal(pairing, d.get(b, "pairing"))) return c.fail("runtime pairing identities differ");
        const paired = try pairedRatios(c, left, right, pairing);
        return c.value(.{
            .ratio = scale * try d.positive(d.get(paired, "median")),
            .observed_range = .{ scale * try d.positive(d.get(paired, "min")), scale * try d.positive(d.get(paired, "max")) },
            .max_spread = d.get(paired, "spread"),
            .pair_ratios = d.get(paired, "samples"),
            .method = "median of alternating capture-pair ratios",
        });
    }
    return c.value(.{
        .ratio = scale * try d.positive(d.get(right, "median")) / try d.positive(d.get(left, "median")),
        .observed_range = .{
            scale * try d.positive(d.get(right, "min")) / try d.positive(d.get(left, "max")),
            scale * try d.positive(d.get(right, "max")) / try d.positive(d.get(left, "min")),
        },
        .max_spread = @max(try d.num(d.get(left, "spread")), try d.num(d.get(right, "spread"))),
        .method = "ratio of independent capture medians",
    });
}
fn pairedRatios(c: *C, left: V, right: V, pairing: V) !V {
    if (!d.is(d.get(pairing, "method"), "alternating-captures-v1") or (try d.str(try d.req(pairing, "id"))).len == 0) return c.fail("invalid runtime pairing method or identity");
    const group_size = try d.positive(try d.req(pairing, "samples_per_pair"));
    if (group_size != @trunc(group_size) or group_size > 30) return error.InvalidExperiment;
    const group: usize = @intFromFloat(group_size);
    const a = try d.items(d.get(left, "samples"));
    const b = try d.items(d.get(right, "samples"));
    if (a.len != b.len or a.len % group != 0 or a.len / group < 5) return c.fail("runtime pairing needs five complete equal-sized pairs");
    const values = try c.a.alloc(f64, a.len / group);
    for (values, 0..) |*value, index| {
        const av = try c.a.alloc(f64, group);
        const bv = try c.a.alloc(f64, group);
        for (0..group) |at| {
            av[at] = try d.positive(a[index * group + at]);
            bv[at] = try d.positive(b[index * group + at]);
        }
        const baseline = try d.summary(c, av);
        const candidate = try d.summary(c, bv);
        value.* = try d.positive(d.get(candidate, "median")) / try d.positive(d.get(baseline, "median"));
    }
    return d.summary(c, values);
}
/// Estimate CPU-bound time separately from instruction work; never certify accuracy.
pub fn estimate(c: *C, a: V, b: V) d.Error!V {
    return estimateImpl(c, a, b) catch |err| d.failure(c, err);
}
fn estimateImpl(c: *C, a: V, b: V) !V {
    if (d.get(d.get(a, "metrics"), key_reference_cycles) == .null or d.get(d.get(b, "metrics"), key_reference_cycles) == .null) return c.value(.{
        .status = "unavailable",
        .reason = "capture both builds with --profile runtime",
    });
    const cycles = try ratio(c, a, b, "cycles");
    const reference = try ratio(c, a, b, key_reference_cycles);
    const instructions = try ratio(c, a, b, "instructions");
    const stable = try d.num(d.get(reference, "max_spread")) <= spread_limit;
    return c.value(.{
        .status = if (stable) "estimated" else "uncertain",
        .estimated_ratio = if (stable) d.get(reference, "ratio") else .null,
        .reference_cycles = reference,
        .cycles = cycles,
        .cpi_ratio = try d.positive(d.get(cycles, "ratio")) / try d.positive(d.get(instructions, "ratio")),
        .target_relative_error = target_error,
        .accuracy_validated = false,
        .spread_limit = spread_limit,
        .meaning = "reference cycles per completed unit; CPU-bound same-hardware runtime proxy, excluding kernel work and time descheduled or waiting for I/O",
        .range_meaning = "observed counter or paired-ratio range, not a runtime error bound or confidence interval",
    });
}
fn timings(c: *C, evidence: V) !V {
    const pairs = try d.items(try d.req(evidence, "pairs"));
    if (pairs.len < 5 or pairs.len > 1000) return c.fail("runtime validation requires 5..1000 independent paired timings");
    const ratios = try c.a.alloc(f64, pairs.len);
    for (pairs, ratios) |pair, *value| {
        const arms = try d.items(pair);
        if (arms.len != 2) return error.InvalidExperiment;
        value.* = try d.positive(arms[1]) / try d.positive(arms[0]);
    }
    return d.summary(c, ratios);
}
/// Check the fixed five-percent target against identity-matched independent timings.
pub fn validate(c: *C, comparison: V, evidence: V) d.Error!V {
    return validateImpl(c, comparison, evidence) catch |err| d.failure(c, err);
}
fn validateImpl(c: *C, comparison: V, evidence: V) !V {
    if (!d.is(d.get(comparison, "version"), "juice-comparison-v1") or !d.is(d.get(evidence, "version"), "juice-timing-evidence-v1")) return c.fail("runtime validation requires a comparison and juice-timing-evidence-v1");
    if ((try d.str(try d.req(evidence, "method"))).len == 0) return c.fail("independent timing method is required");
    for ([_][]const u8{ "base_id", "candidate_id", "context_id" }) |key| {
        if (!d.equal(try d.req(comparison, key), try d.req(evidence, key))) return c.fail("timings do not match compared builds and context");
    }
    const name = try d.req(evidence, "workload");
    const cell = try d.req(try d.req(comparison, "workloads"), try d.str(name));
    const proxy = try d.req(cell, "runtime_proxy");
    const measured = try timings(c, evidence);
    const observed = try d.positive(d.get(measured, "median"));
    const estimate_value = d.get(proxy, "estimated_ratio");
    const available = d.is(d.get(proxy, "status"), "estimated") and estimate_value != .null;
    const err = if (available) @abs(try d.positive(estimate_value) / observed - 1) else std.math.inf(f64);
    const stable = try d.num(d.get(measured, "spread")) <= spread_limit;
    const passed = available and stable and err <= target_error;
    return c.value(.{
        .version = "juice-runtime-validation-v1",
        .workload = name,
        .comparison_sha256 = try c.hash(comparison),
        .timing_sha256 = try c.hash(evidence),
        .passed = passed,
        .status = if (!available or !stable) "uncertain" else if (passed) "within-target" else "outside-target",
        .target_relative_error = target_error,
        .relative_error = if (available) d.Value{ .float = err } else .null,
        .instruction_relative_error = @abs(try d.positive(d.get(cell, "instruction_ratio")) / observed - 1),
        .estimated_ratio = estimate_value,
        .timing_ratio = observed,
        .timing_ratios = measured,
        .timing_repeatable = stable,
        .missed_regression = available and stable and observed > 1.05 and try d.positive(estimate_value) <= 1,
        .false_alarm = available and stable and observed <= 1 and try d.positive(estimate_value) > 1.05,
        .scope = "this measured change and scenario only; does not qualify unseen changes, workloads or machines",
    });
}
