//! Compare actual changed-source checks and test execution, excluding source generation.
const std = @import("std");
const language = @import("mylang");
const functions = 80;
const statements = 40;
const samples = 21;
fn source(allocator: std.mem.Allocator, edit: usize) ![]u8 {
    var out: std.Io.Writer.Allocating = .init(allocator);
    errdefer out.deinit();
    const w = &out.writer;
    for (0..functions) |f| {
        try w.print("fn f{d}(n:i64)->i64{{let a0=n;", .{f});
        for (1..statements + 1) |s| try w.print("let a{d}=a{d}+{d};", .{ s, s - 1, if (f == 0 and s == 1) edit + 1 else @as(usize, 1) });
        try w.print("return a{d};}}", .{statements});
    }
    try w.writeAll("fn main()->i64{return ");
    for (0..functions) |f| {
        if (f != 0) try w.writeByte('+');
        try w.print("f{d}(1)", .{f});
    }
    try w.writeAll(";}");
    return out.toOwnedSlice();
}
const Timing = struct { check: i96, total: i96 };
fn measured(init: std.process.Init, cache: ?*language.semantic_cache.Cache, bytes: []const u8, expected: i64) !Timing {
    const start = std.Io.Timestamp.now(init.io, .awake);
    var compilation = try language.Compilation.init(init.gpa, "edited.my", bytes);
    defer compilation.deinit();
    try compilation.checkWithCache(cache);
    const checked = std.Io.Timestamp.now(init.io, .awake);
    const result = try compilation.execute(init.gpa);
    if (result != .value or result.value != expected) return error.ResultMismatch;
    const end = std.Io.Timestamp.now(init.io, .awake);
    return .{ .check = start.durationTo(checked).nanoseconds, .total = start.durationTo(end).nanoseconds };
}
fn quantiles(times: *[samples]i96) struct { p50_ns: i96, p95_ns: i96 } {
    std.mem.sort(i96, times, {}, std.sort.asc(i96));
    return .{ .p50_ns = times[samples / 2], .p95_ns = times[(samples * 95 + 99) / 100 - 1] };
}
pub fn main(init: std.process.Init) !void {
    var cache = language.semantic_cache.Cache.init(init.gpa, 32 * 1024 * 1024);
    defer cache.deinit();
    const baseline = try source(init.gpa, 0);
    defer init.gpa.free(baseline);
    _ = try measured(init, &cache, baseline, functions * (statements + 1));
    var cached_check: [samples]i96 = undefined;
    var cached_total: [samples]i96 = undefined;
    var fresh_check: [samples]i96 = undefined;
    var fresh_total: [samples]i96 = undefined;
    for (0..samples) |i| {
        const edit = i % 7 + 1;
        const bytes = try source(init.gpa, edit);
        defer init.gpa.free(bytes);
        const expected: i64 = @intCast(functions * (statements + 1) + edit);
        // Alternate order to reduce one-sided warm-cache scheduling bias.
        const fresh_first = if (i % 2 == 0) try measured(init, null, bytes, expected) else null;
        const reused = cache.statistics.reused;
        const cached = try measured(init, &cache, bytes, expected);
        if (cache.statistics.reused - reused != functions) return error.ReuseMismatch;
        const fresh = fresh_first orelse try measured(init, null, bytes, expected);
        cached_check[i] = cached.check;
        cached_total[i] = cached.total;
        fresh_check[i] = fresh.check;
        fresh_total[i] = fresh.total;
    }
    const output = try std.json.Stringify.valueAlloc(init.gpa, .{
        .functions = functions + 1,
        .statements_per_function = statements,
        .edited_functions = 1,
        .samples = samples,
        .cached_check = quantiles(&cached_check),
        .fresh_check = quantiles(&fresh_check),
        .cached_edit_to_test = quantiles(&cached_total),
        .fresh_edit_to_test = quantiles(&fresh_total),
        .queries = cache.statistics,
    }, .{});
    defer init.gpa.free(output);
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}
