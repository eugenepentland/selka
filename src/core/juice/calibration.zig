//! Explicit held-out timing calibration; capture wall times never train a model.
const std = @import("std");
const key_context_id = "context_id";
const key_validation = "validation";
const d = @import("data.zig");
const C = d.Context;
const V = d.Value;
fn member(array: V, needle: V) !bool {
    for (try d.items(array)) |v| if (d.equal(v, needle)) return true;
    return false;
}
fn relativeRead(c: *C, root: []const u8, path: V) !V {
    return c.read(try c.join(&.{ root, try d.str(path) }));
}
fn timingRatio(c: *C, timing: V, comparison: V, name: V) !f64 {
    if (!d.is(d.get(timing, "version"), "juice-timing-evidence-v1") or (try d.str(try d.req(timing, "method"))).len == 0) return c.fail("timing evidence requires a method and version");
    for ([_][]const u8{ "base_id", "candidate_id", key_context_id }) |key| if (!d.equal(try d.req(timing, key), try d.req(comparison, key))) return c.fail("timing evidence does not match compared builds and context");
    if (!d.equal(try d.req(timing, "workload"), name)) return c.fail("timing evidence names another workload");
    const pairs = try d.items(try d.req(timing, "pairs"));
    if (pairs.len < 5) return c.fail("at least five paired timings required");
    const ratios = try c.a.alloc(f64, pairs.len);
    for (pairs, ratios) |pair, *ratio| {
        const p = try d.items(pair);
        if (p.len != 2) return error.InvalidExperiment;
        ratio.* = try d.positive(p[1]) / try d.positive(p[0]);
    }
    const summary = try d.summary(c, ratios);
    if (try d.num(d.get(summary, "spread")) > 0.03) return c.fail("timing ratios vary by more than 3%");
    return d.num(d.get(summary, "median"));
}
/// Fit a positive ratio exponent only after disjoint-family held-out validation.
pub fn fit(c: *C, path: []const u8) d.Error!V {
    return fitImpl(c, path) catch |err| d.failure(c, err);
}
fn fitImpl(c: *C, path: []const u8) !V {
    const dataset = try c.read(path);
    const root = std.fs.path.dirname(path) orelse ".";
    if (!d.is(d.get(dataset, "version"), "juice-calibration-data-v1")) return c.fail("expected juice-calibration-data-v1");
    var context: V = .null;
    var seen = d.object();
    var points = d.array(c);
    var train_families = d.object();
    var held_families = d.object();
    var train_count: usize = 0;
    var held_count: usize = 0;
    var denominator: f64 = 0;
    var numerator: f64 = 0;
    var low: f64 = std.math.inf(f64);
    var high: f64 = 0;
    for (try d.items(try d.req(dataset, "points"))) |point| {
        const comparison = try relativeRead(c, root, try d.req(point, "comparison"));
        if (!d.is(d.get(comparison, "version"), "juice-comparison-v1")) return c.fail("calibration requires comparison reports");
        if (context != .null and !d.equal(context, try d.req(comparison, key_context_id))) return c.fail("calibration cannot mix measurement contexts");
        context = try d.req(comparison, key_context_id);
        const name = try d.req(point, "workload");
        const cell = try d.req(try d.req(comparison, "workloads"), try d.str(name));
        if (!d.equal(d.get(cell, "repeatable"), .{ .bool = true }) or (try d.items(d.get(cell, "risks"))).len != 0) return c.fail("calibration needs stable observations without cost risks");
        const timing = try relativeRead(c, root, try d.req(point, "timing_evidence"));
        const ratio = try timingRatio(c, timing, comparison, name);
        const split = try d.req(point, "split");
        if (!d.is(split, "train") and !d.is(split, key_validation)) return c.fail("split must be train or validation");
        const identity = try d.str(try c.hash(try c.value(.{ try d.req(comparison, "base_id"), try d.req(comparison, "candidate_id"), name })));
        if (d.get(seen, identity) != .null) return c.fail("duplicate calibration observation");
        try d.put(c, &seen, identity, .{ .bool = true });
        const family = try d.req(cell, "family");
        const work = try d.positive(try d.req(cell, "instruction_ratio"));
        low = @min(low, work);
        high = @max(high, work);
        if (d.is(split, "train")) {
            train_count += 1;
            try d.put(c, &train_families, try d.str(family), .null);
            denominator += @log(work) * @log(work);
            numerator += @log(work) * @log(ratio);
        } else {
            held_count += 1;
            try d.put(c, &held_families, try d.str(family), .null);
        }
        try d.add(c, &points, try c.value(.{
            .family = family,
            .split = split,
            .work = work,
            .time = ratio,
            .comparison_sha256 = try c.fileHash(try c.join(&.{
                root, try d.str(d.get(point, "comparison")),
            })),
            .timing_sha256 = try c.fileHash(try c.join(&.{
                root, try d.str(d.get(point, "timing_evidence")),
            })),
        }));
    }
    if (train_count < 6 or held_count < 3 or train_families.object.count() < 2 or held_families.object.count() == 0) return c.fail("need six training observations across two families and three held-out observations");
    for (try d.keys(c, train_families)) |family| if (held_families.object.contains(family)) return c.fail("training and validation families must be disjoint");
    if (denominator < 0.001) return c.fail("training changes too small to identify a useful model");
    const exponent = numerator / denominator;
    if (exponent <= 0 or exponent > 3 or !std.math.isFinite(exponent)) return c.fail("no plausible positive instruction/time relationship");
    const errors = try c.a.alloc(f64, held_count);
    var at: usize = 0;
    var directional: f64 = 0;
    var correct: f64 = 0;
    for (try d.items(points)) |p| if (d.is(d.get(p, "split"), key_validation)) {
        const work = try d.num(d.get(p, "work"));
        const time = try d.num(d.get(p, "time"));
        errors[at] = @abs(std.math.pow(f64, work, exponent) / time - 1);
        at += 1;
        if (@abs(time - 1) > 0.03) {
            directional += 1;
            if ((work - 1) * (time - 1) > 0) correct += 1;
        }
    };
    const stats = try d.summary(c, errors);
    const accuracy = if (directional > 0) correct / directional else 0;
    if (try d.num(d.get(stats, "max")) > 0.10 or accuracy < 0.8) return c.fail("model failed held-out error/direction validation");
    var families = d.array(c);
    for (try d.keys(c, train_families)) |f| try d.add(c, &families, d.string(f));
    for (try d.keys(c, held_families)) |f| try d.add(c, &families, d.string(f));
    return c.value(.{
        .version = "juice-model-v1",
        .context_id = context,
        .exponent = exponent,
        .meaning = "runtime ratio = instruction ratio ** exponent; CPU-bound trend only",
        .families = families,
        .work_range = .{
            low, high,
        },
        .validation = .{
            .max_relative_error = d.get(stats, "max"),
            .median_relative_error = d.get(stats, "median"),
            .direction_accuracy = accuracy,
            .observations = held_count,
        },
        .points = points,
        .dataset_sha256 = try c.fileHash(path),
    });
}
/// Add estimates only inside the model's context, families and measured range.
pub fn predict(c: *C, report: *V, model: V) d.Error!void {
    return predictImpl(c, report, model) catch |err| d.failure(c, err);
}
fn predictImpl(c: *C, report: *V, model: V) !void {
    if (!d.is(d.get(model, "version"), "juice-model-v1") or !d.equal(try d.req(report.*, key_context_id), try d.req(model, key_context_id))) return c.fail("model context or version does not match");
    const exponent = try d.positive(try d.req(model, "exponent"));
    if (exponent > 3) return error.InvalidExperiment;
    const range = try d.items(try d.req(model, "work_range"));
    if (range.len != 2 or try d.positive(range[0]) > try d.positive(range[1])) return error.InvalidExperiment;
    var cells = d.object();
    const workloads = try d.req(report.*, "workloads");
    for (try d.keys(c, workloads)) |name| {
        const cell = d.get(workloads, name);
        const ratio = try d.positive(d.get(cell, "instruction_ratio"));
        const reason: ?[]const u8 = if (!try member(try d.req(model, "families"), try d.req(cell, "family"))) "workload family outside calibration" else if (!d.equal(d.get(cell, "repeatable"), .{
            .bool = true,
        }) or (try d.items(d.get(cell, "risks"))).len != 0) "unstable observations or unresolved cost risks" else if (ratio < try d.num(range[0]) or ratio > try d.num(range[1])) "change outside calibrated range" else null;
        const value = if (reason) |r| try c.value(.{
            .reason = r,
        }) else try c.value(.{
            .ratio = std.math.pow(f64, ratio, exponent),
            .validation_max_error = try d.req(try d.req(model, key_validation), "max_relative_error"),
            .scope = "model estimate; held-out error is not a confidence bound",
        });
        try d.put(c, &cells, name, value);
    }
    try d.put(c, report, "runtime_prediction", try c.value(.{ .status = "calibrated estimates where applicable", .model_id = try c.hash(model), .workloads = cells }));
}
