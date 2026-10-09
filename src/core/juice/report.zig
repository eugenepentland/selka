//! Platform-independent comparisons. Work is an instruction ratio, never a time ratio.
const std = @import("std");
const key_function = "function";
const key_delta_per_unit = "delta_per_unit";
const key_candidate = "candidate";
const key_available = "available";
const key_libraries = "libraries";
const key_build_config = "build_config";
const key_workloads = "workloads";
const key_instruction_ratio = "instruction_ratio";
const key_juice_comparison_v1 = "juice-comparison-v1";
const d = @import("data.zig");
const C = d.Context;
const V = d.Value;
const contextual = [_][]const u8{ "alloc_bytes", "free_bytes", "realloc_added_bytes", "realloc_moves", "realloc_moved_bytes", "peak_live_bytes" };

/// Load complete records and verify every referenced raw artifact.
pub fn load(c: *C, path: []const u8) d.Error!V {
    return loadImpl(c, path) catch |err| d.failure(c, err);
}
fn loadImpl(c: *C, path: []const u8) !V {
    const r = try c.read(path);
    if (!d.is(d.get(r, "version"), "juice-v1") or !d.is(d.get(r, "status"), "complete")) return c.fail("expected a complete juice-v1 record");
    const evidence = d.get(r, "evidence");
    if (evidence != .null) for (try d.keys(c, evidence)) |name| {
        try d.relative(name);
        const artifact = try c.join(&.{ std.fs.path.dirname(path) orelse ".", name });
        if (!d.equal(try c.fileHash(artifact), d.get(evidence, name))) return c.fail("missing or modified raw evidence");
    };
    return r;
}
/// Changed keys retain both arms, with null for missing data.
pub fn differences(c: *C, before: V, after: V) d.Error!V {
    return differencesImpl(c, before, after) catch |err| d.failure(c, err);
}
fn differencesImpl(c: *C, before: V, after: V) !V {
    var union_keys = try d.clone(c, before);
    for (try d.keys(c, after)) |k| try d.put(c, &union_keys, k, d.get(after, k));
    var result = d.object();
    for (try d.keys(c, union_keys)) |k| if (!d.equal(d.get(before, k), d.get(after, k))) {
        try d.put(c, &result, k, try c.value(.{ .base = d.get(before, k), .candidate = d.get(after, k) }));
    };
    return result;
}
fn empty(v: V) V {
    return if (v == .null) d.object() else v;
}
fn list(c: *C, v: V) V {
    return if (v == .null) d.array(c) else v;
}
fn index(c: *C, rows: V, fields: []const []const u8) !V {
    var result = d.object();
    for (try d.items(list(c, rows))) |row| {
        var identity = d.array(c);
        for (fields) |field| try d.add(c, &identity, d.get(row, field));
        const key = try d.str(try c.hash(identity));
        if (d.get(result, key) != .null) return c.fail("duplicate attribution identity");
        try d.put(c, &result, key, row);
    }
    return result;
}
fn unionOf(c: *C, a: V, b: V) !V {
    var result = try d.clone(c, a);
    for (try d.keys(c, b)) |k| try d.put(c, &result, k, d.get(b, k));
    return result;
}
fn numeric(v: V, key: []const u8) !f64 {
    const n = d.get(v, key);
    return if (n == .null) 0 else d.num(n);
}
fn fieldsOf(c: *C, row: V, fields: []const []const u8) !V {
    var result = d.object();
    for (fields) |field| try d.put(c, &result, field, d.get(row, field));
    return result;
}
fn attribution(c: *C, a: V, b: V, au: f64, bu: f64) !V {
    const fields = &.{ "file", key_function, "object", "line" };
    const ai = try index(c, a, fields);
    const bi = try index(c, b, fields);
    var result = d.array(c);
    for (try d.keys(c, try unionOf(c, ai, bi))) |key| {
        const left = d.get(ai, key);
        const right = d.get(bi, key);
        const an = try numeric(left, d.key_instructions) / au;
        const bn = try numeric(right, d.key_instructions) / bu;
        if (an == bn) continue;
        var row = try fieldsOf(c, if (right == .null) left else right, fields);
        try d.put(c, &row, "base_per_unit", .{ .float = an });
        try d.put(c, &row, "candidate_per_unit", .{ .float = bn });
        try d.put(c, &row, key_delta_per_unit, .{ .float = bn - an });
        try d.put(c, &row, "match", d.string(if (left != .null and right != .null) "same location" else "added or removed location"));
        try d.add(c, &result, row);
    }
    std.mem.sort(V, result.array.items, {}, struct {
        fn less(_: void, a1: V, b1: V) bool {
            return @abs(d.num(d.get(a1, key_delta_per_unit)) catch 0) > @abs(d.num(d.get(b1, key_delta_per_unit)) catch 0);
        }
    }.less);
    return result;
}
fn numericFields(c: *C, row: V) !V {
    var result = d.object();
    for (try d.keys(c, empty(row))) |key| {
        const v = d.get(row, key);
        if (v == .integer or v == .float) try d.put(c, &result, key, v);
    }
    return result;
}
fn semantic(c: *C, a: V, b: V) !V {
    const av = d.get(a, "semantic");
    const bv = d.get(b, "semantic");
    if (av == .null or bv == .null) return c.value(.{ .status = "unavailable" });
    if (!d.equal(d.get(a, "counter_semantics"), d.get(b, "counter_semantics")) or !d.equal(d.get(av, "version"), d.get(bv, "version"))) return c.value(.{
        .status = "incompatible",
        .reason = "counter hook contracts differ",
    });
    var functions = d.array(c);
    const ai = try index(c, d.get(av, d.key_functions), &.{"name"});
    const bi = try index(c, d.get(bv, d.key_functions), &.{"name"});
    for (try d.keys(c, try unionOf(c, ai, bi))) |key| {
        const left = d.get(ai, key);
        const right = d.get(bi, key);
        const changes = try differences(c, try numericFields(c, left), try numericFields(c, right));
        if (changes.object.count() > 0) try d.add(c, &functions, try c.value(.{ .function = d.get(if (right == .null) left else right, "name"), .changes = changes }));
    }
    const fields = &.{ key_function, "origin", "path", "line", "column", "kind", "detail" };
    const sa = try index(c, d.get(av, "sites"), fields);
    const sb = try index(c, d.get(bv, "sites"), fields);
    var sites = d.array(c);
    for (try d.keys(c, try unionOf(c, sa, sb))) |key| {
        const left = d.get(sa, key);
        const right = d.get(sb, key);
        const l = try c.value(.{ .count = try numeric(left, "count"), .bytes = try numeric(left, "bytes"), .extra = try numeric(left, "extra") });
        const r = try c.value(.{ .count = try numeric(right, "count"), .bytes = try numeric(right, "bytes"), .extra = try numeric(right, "extra") });
        if (d.equal(l, r)) continue;
        var site = try fieldsOf(c, if (right == .null) left else right, fields);
        try d.put(c, &site, "base", l);
        try d.put(c, &site, key_candidate, r);
        try d.put(c, &site, "match", d.string(if (left != .null and right != .null) "same location" else "added or removed location"));
        try d.add(c, &sites, site);
    }
    return c.value(.{
        .status = "compatible",
        .totals = try differences(c, try d.req(av, "totals"), try d.req(bv, "totals")),
        .contextual_metrics = contextual,
        .functions = functions,
        .sites = sites,
        .requested_allocation_bytes = .{
            .status = "unavailable",
            .reason = "v1 counters expose allocated class/usable sizes",
        },
        .kinds = try differences(c, empty(d.get(av, "kinds")), empty(d.get(bv, "kinds"))),
        .site_scope = "before LLVM optimization; source sites retained in capture records",
    });
}
/// Comparison controls hold the application or compiler fixed and bound observed spread.
pub const Options = struct { mode: []const u8 = "combined", max_spread: f64 = 0.005, min_change: f64 = 0.001 };
fn risk(c: *C, risks: *V, text: []const u8) !void {
    try d.add(c, risks, d.string(text));
}
fn sumField(code: V, key: []const u8) !f64 {
    const functions = try d.req(code, d.key_functions);
    if (functions != .object) return error.InvalidExperiment;
    var total: f64 = 0;
    for (functions.object.values()) |f| total += try numeric(f, key);
    return total;
}
fn codeRisks(c: *C, a: V, b: V, libraries: V) !V {
    var risks = d.array(c);
    if (libraries.object.count() > 0) try risk(c, &risks, "linked library set changed; costs include library startup/work");
    if (!d.equal(d.get(a, key_available), .{
        .bool = true,
    }) or !d.equal(d.get(b, key_available), .{
        .bool = true,
    })) try risk(c, &risks, "static code analysis unavailable; instruction mix unresolved");
    for ([_][]const u8{ "atomic_sites", "divide_sites" }) |key| if (try sumField(b, key) > try sumField(a, key)) try risk(c, &risks, try std.fmt.allocPrint(c.a, "static {s} increased; hotness unresolved", .{
        key,
    }));
    return risks;
}
fn measurements(v: V) !void {
    const median = try d.positive(try d.req(v, "median"));
    const low = try d.positive(try d.req(v, "min"));
    const high = try d.positive(try d.req(v, "max"));
    const spread = try d.num(try d.req(v, "spread"));
    if (low > median or high < median or spread < 0 or @abs(spread - (high - low) / median) > 1e-10) return error.InvalidExperiment;
    const samples = try d.items(try d.req(v, "samples"));
    if (samples.len < 2 or samples.len > 30) return error.InvalidExperiment;
    for (samples) |s| {
        const n = try d.positive(s);
        if (n < low or n > high) return error.InvalidExperiment;
    }
}
fn workload(c: *C, a: V, b: V, risks_initial: V, options: Options) !V {
    if (!d.equal(try d.req(a, "correctness"), try d.req(b, "correctness"))) return c.fail("baseline and candidate outputs differ");
    const am = try d.req(try d.req(a, "metrics"), d.key_instructions);
    const bm = try d.req(try d.req(b, "metrics"), d.key_instructions);
    try measurements(am);
    try measurements(bm);
    const au = try d.positive(try d.req(a, "units"));
    const bu = try d.positive(try d.req(b, "units"));
    const ratio = (try d.num(d.get(bm, "median")) / bu) / (try d.num(d.get(am, "median")) / au);
    const low = (try d.num(d.get(bm, "min")) / bu) / (try d.num(d.get(am, "max")) / au);
    const high = (try d.num(d.get(bm, "max")) / bu) / (try d.num(d.get(am, "min")) / au);
    const stable = @max(try d.num(d.get(am, "spread")), try d.num(d.get(bm, "spread"))) <= options.max_spread;
    const direction = directionOf(stable, low, high, options.min_change);
    var risks = d.array(c);
    for (try d.items(risks_initial)) |r| try d.add(c, &risks, r);
    for ([_][]const u8{ "atomics", "data_reads", "data_writes" }) |metric| {
        const x = d.get(d.get(a, "metrics"), metric);
        const y = d.get(d.get(b, "metrics"), metric);
        if (x != .null and y != .null and try d.num(d.get(y, "median")) / bu > try d.num(d.get(x, "median")) / au) try risk(c, &risks, try std.fmt.allocPrint(c.a, "{s} per completed unit increased", .{
            metric,
        }));
    }
    const sem = try semantic(c, a, b);
    if (d.is(d.get(sem, "status"), "incompatible")) try risk(c, &risks, "semantic counter contracts changed");
    if (d.is(d.get(sem, "status"), "compatible")) for (try d.keys(c, d.get(sem, "totals"))) |key| {
        if (std.mem.endsWith(u8, key, "copy_bytes") or std.mem.eql(u8, key, "allocs") or std.mem.eql(u8, key, "shared_retains") or std.mem.eql(u8, key, "shared_releases")) {
            const delta = d.get(d.get(sem, "totals"), key);
            const before = d.get(delta, "base");
            const after = d.get(delta, key_candidate);
            if (before == .null or after == .null) continue;
            if (try d.num(after) > try d.num(before)) {
                try risk(c, &risks, try std.fmt.allocPrint(c.a, "semantic {s} increased", .{key}));
            }
        }
    };
    var metrics = d.object();
    for (try d.keys(c, try unionOf(c, d.get(a, "metrics"), d.get(b, "metrics")))) |k| try d.put(c, &metrics, k, try c.value(.{
        .base = d.get(d.get(a, "metrics"), k),
        .candidate = d.get(d.get(b, "metrics"), k),
    }));
    var result = try fieldsOf(c, a, &.{ "units", "unit", "family", "tier", "scope", "weight" });
    const more = try c.value(.{
        .juice = ratio * 100,
        .instruction_ratio = ratio,
        .ratio_envelope = .{
            low, high,
        },
        .envelope_meaning = "observed min/max repeat range, not a statistical confidence interval",
        .direction = direction,
        .assessment = if (std.mem.eql(u8, direction, "less-work") and risks.array.items.len > 0) "mixed" else direction,
        .repeatable = stable,
        .risks = risks,
        .metrics = metrics,
        .semantic = sem,
        .functions = try attribution(c, d.get(a, d.key_functions), d.get(b, d.key_functions), au, bu),
        .lines = try attribution(c, d.get(a, "lines"), d.get(b, "lines"), au, bu),
        .coverage = "measured scenario only; whole-job representativeness unverified",
    });
    for (try d.keys(c, more)) |k| try d.put(c, &result, k, d.get(more, k));
    return result;
}
/// Compare only matched contracts and contexts; reject changed installed libraries.
pub fn compare(c: *C, a: V, b: V, options: Options) d.Error!V {
    return compareImpl(c, a, b, options) catch |err| d.failure(c, err);
}
fn compareImpl(c: *C, a: V, b: V, options: Options) !V {
    if (!d.equal(try d.req(a, "contract"), try d.req(b, "contract"))) return c.fail("workload contracts differ");
    var ac = try d.clone(c, try d.req(a, "context"));
    var bc = try d.clone(c, try d.req(b, "context"));
    const al = empty(d.get(ac, key_libraries));
    const bl = empty(d.get(bc, key_libraries));
    _ = ac.object.swapRemove(key_libraries);
    _ = bc.object.swapRemove(key_libraries);
    if (!d.equal(ac, bc)) return c.fail("measurement contexts differ (CPU, collector, kernel or execution path)");
    for (try d.keys(c, al)) |key| if (d.get(bl, key) != .null and !d.equal(d.get(al, key), d.get(bl, key))) return c.fail("installed shared library changed");
    if (std.mem.eql(u8, options.mode, "backend") and !d.equal(try d.req(a, "sources"), try d.req(b, "sources"))) return c.fail("backend comparison requires identical application sources");
    if (std.mem.eql(u8, options.mode, "application") and !d.equal(try d.req(a, key_build_config), try d.req(b, key_build_config))) return c.fail("application comparison requires identical compiler and build configuration");
    const aw = try d.req(a, key_workloads);
    const bw = try d.req(b, key_workloads);
    if (aw != .object or bw != .object or aw.object.count() == 0 or aw.object.count() != bw.object.count()) return c.fail("workload sets differ or are empty");
    const library_changes = try differences(c, al, bl);
    try d.put(c, &ac, key_libraries, try unionOf(c, al, bl));
    const code_a = try d.req(try d.req(a, "build"), "code");
    const code_b = try d.req(try d.req(b, "build"), "code");
    const risks = try codeRisks(c, code_a, code_b, library_changes);
    var cells = d.object();
    var weighted: f64 = 0;
    var weight: f64 = 0;
    for (try d.keys(c, aw)) |key| {
        const cell = try workload(c, d.get(aw, key), try d.req(bw, key), risks, options);
        try d.put(c, &cells, key, cell);
        const w = try d.positive(try d.req(cell, "weight"));
        weighted += w * @log(try d.positive(d.get(cell, key_instruction_ratio)));
        weight += w;
    }
    const ca = d.get(d.get(a, "build"), "static_cost");
    const cb = d.get(d.get(b, "build"), "static_cost");
    const costs = if (d.is(d.get(ca, "version"), "cost-v1") and d.is(d.get(cb, "version"), "cost-v1")) try c.value(.{
        .scope = "static Core sites/LLVM remarks, not executions",
        .totals = try differences(c, d.get(ca, "totals"), d.get(cb, "totals")),
    }) else try c.value(.{
        .status = "unavailable or incompatible",
    });
    return c.value(.{
        .version = key_juice_comparison_v1,
        .identity_scheme = "mylang-juice-native-v1",
        .base = try d.req(a, "name"),
        .candidate = try d.req(b, "name"),
        .mode = options.mode,
        .context_id = try c.hash(ac),
        .collector = try d.req(a, "collector"),
        .source_roots = .{
            .base = d.get(a, "source_root"),
            .candidate = d.get(b, "source_root"),
        },
        .library_changes = library_changes,
        .base_id = try c.hash(a),
        .candidate_id = try c.hash(b),
        .workloads = cells,
        .change_id = try c.hash(try c.value(.{
            try d.req(a, "sources"), try d.req(a, key_build_config), try d.req(b, "sources"), try d.req(b, key_build_config),
        })),
        .meaning = "100 × candidate instructions per completed unit / baseline; not a time ratio",
        .max_spread = options.max_spread,
        .min_change = options.min_change,
        .runtime_prediction = .{
            .status = "uncalibrated",
        },
        .code = .{
            .available = d.equal(d.get(code_a, key_available), .{
                .bool = true,
            }) and d.equal(d.get(code_b, key_available), .{
                .bool = true,
            }),
            .sections = try differences(c, d.get(code_a, "sections"), d.get(code_b, "sections")),
            .functions = try differences(c, d.get(code_a, d.key_functions), d.get(code_b, d.key_functions)),
            .scope = "static bytes and instruction sites, not executions",
        },
        .static_cost = costs,
        .suite_juice = 100 * @exp(weighted / weight),
        .suite_meaning = "weighted geometric mean of selected scenarios; not whole-job runtime",
    });
}
/// Match short scenarios to larger cases for the same change and host context.
pub fn validate(c: *C, quick: V, larger: V, tolerance: f64) d.Error!V {
    return validateImpl(c, quick, larger, tolerance) catch |err| d.failure(c, err);
}
fn validateImpl(c: *C, quick: V, larger: V, tolerance: f64) !V {
    if (!d.is(d.get(quick, "version"), key_juice_comparison_v1) or !d.is(d.get(larger, "version"), key_juice_comparison_v1)) return c.fail("expected comparison reports");
    const same_context = d.equal(try d.req(quick, "context_id"), try d.req(larger, "context_id"));
    const same_change = d.equal(try d.req(quick, "change_id"), try d.req(larger, "change_id"));
    if (!same_context or !same_change) return c.fail("quick and validation reports compare different changes or contexts");
    var families = d.object();
    var passed = true;
    for (try d.keys(c, try d.req(quick, key_workloads))) |name| {
        const cell = d.get(d.get(quick, key_workloads), name);
        if (!d.is(d.get(cell, "tier"), "quick")) continue;
        var errors = d.array(c);
        var directions = d.array(c);
        var ok = d.equal(d.get(cell, "repeatable"), .{ .bool = true });
        for (try d.keys(c, try d.req(larger, key_workloads))) |other_name| {
            const other = d.get(d.get(larger, key_workloads), other_name);
            const same_family = d.equal(d.get(cell, "family"), d.get(other, "family"));
            const same_unit = d.equal(d.get(cell, "unit"), d.get(other, "unit"));
            const same_scope = d.equal(d.get(cell, "scope"), d.get(other, "scope"));
            if (!d.is(d.get(other, "tier"), "validation")) continue;
            if (!(same_family and same_unit and same_scope)) continue;
            const err = @abs(try d.positive(d.get(cell, key_instruction_ratio)) / try d.positive(d.get(other, key_instruction_ratio)) - 1);
            const direction = d.equal(d.get(cell, "direction"), d.get(other, "direction"));
            try d.add(c, &errors, .{ .float = err });
            try d.add(c, &directions, .{ .bool = direction });
            ok = ok and direction and err <= tolerance and d.equal(d.get(other, "repeatable"), .{ .bool = true });
        }
        ok = ok and errors.array.items.len > 0;
        passed = passed and ok;
        const family = try d.str(try d.req(cell, "family"));
        var group = empty(d.get(families, family));
        try d.put(c, &group, name, try c.value(.{ .passed = ok, .relative_errors = errors, .directions_agree = directions }));
        try d.put(c, &families, family, group);
    }
    if (families.object.count() == 0) return c.fail("no quick scenarios to validate");
    return c.value(.{ .version = "juice-scenario-validation-v1", .families = families, .passed = passed, .scope = "agreement for these changes and inputs, not a universal coverage guarantee" });
}
/// Human-readable report with explicit uncertainty and measured-scenario scope.
pub fn render(c: *C, report: V) d.Error![]const u8 {
    return renderImpl(c, report) catch |err| d.failure(c, err);
}
fn renderImpl(c: *C, report: V) ![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    try out.print(c.a, "Juice: {s} → {s}\nBaseline 100; lower means fewer instructions per completed unit, not proportionally less time.\n\n| Workload | Juice | Assessment | Repeat range |\n|---|---:|---|---|\n", .{
        try d.str(d.get(report, "base")), try d.str(d.get(report, key_candidate)),
    });
    for (try d.keys(c, d.get(report, key_workloads))) |name| {
        const cell = d.get(d.get(report, key_workloads), name);
        const envelope = try d.items(d.get(cell, "ratio_envelope"));
        if (envelope.len != 2) return error.InvalidExperiment;
        try out.print(c.a, "| {s} | {d:.3} | {s} | {d:.3}–{d:.3} |\n", .{
            name, try d.num(d.get(cell, "juice")), try d.str(d.get(cell, "assessment")), 100 * try d.num(envelope[0]), 100 * try d.num(envelope[1]),
        });
    }
    try out.print(c.a, "\nSelected-scenario index: {d:.3} (weighted geometric mean).\nCoverage: selected scenarios only. Repeat ranges are observations, not confidence intervals.\n", .{
        try d.num(d.get(report, "suite_juice")),
    });
    for (try d.keys(c, d.get(report, key_workloads))) |name| {
        const cell = d.get(d.get(report, key_workloads), name);
        for (try d.items(d.get(cell, "risks"))) |r| try out.print(c.a, "\n- {s}: {s}\n", .{ name, try d.str(r) });
        const rows = try d.items(d.get(cell, d.key_functions));
        for (rows[0..@min(rows.len, 5)]) |r| try out.print(c.a, "- {s}: {s}, {d:.3} instructions/{s} ({s})\n", .{
            name, try d.str(d.get(r, key_function)), try d.num(d.get(r, key_delta_per_unit)), try d.str(d.get(cell, "unit")), try d.str(d.get(r, "file")),
        });
    }
    try out.print(c.a, "\nRuntime estimate: {s}. See JSON for all semantic sites, functions and model details.\n", .{try d.str(d.get(d.get(report, "runtime_prediction"), "status"))});
    return out.toOwnedSlice(c.a);
}

fn directionOf(stable: bool, low: f64, high: f64, minimum: f64) []const u8 {
    if (!stable) return "uncertain";
    if (low >= 1 - minimum and high <= 1 + minimum) return "unchanged";
    if (high < 1 - minimum) return "less-work";
    if (low > 1 + minimum) return "more-work";
    return "uncertain";
}
