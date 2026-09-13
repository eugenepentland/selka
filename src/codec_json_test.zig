//! Domain codec JSON tests verify shared budgets, typed rejections, ownership, and forged contract failures.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const codec = language.codec_json;
const source =
    \\class Wire:
    \\    n: i64
    \\
    \\
    \\class Why:
    \\    code: i64
    \\
    \\
    \\result Decoded:
    \\    ok: Positive,
    \\    err: Why
    \\
    \\
    \\domain Positive: i64:
    \\    codec Wire:
    \\        decode: dec,
    \\        encode: enc
    \\
    \\    def dec(x: Wire) -> Decoded:
    \\        if x.n <= 0:
    \\            return Err(Why(code=-1))
    \\        return Ok(wrap<Positive>(x.n))
    \\
    \\    def enc(x: Positive) -> Wire:
    \\        return Wire(n=unwrap(x))
    \\
    \\
    \\class Pair:
    \\    items: [2]Positive
    \\
    \\
    \\def main() -> i64:
    \\    return 0
;
const good = "{\"version\":\"typed-json-v1\",\"type\":\"Pair\",\"value\":{\"items\":[{\"n\":\"7\"},{\"n\":\"9\"}]}}";
const bad = "{\"version\":\"typed-json-v1\",\"type\":\"Pair\",\"value\":{\"items\":[{\"n\":\"7\"},{\"n\":\"0\"}]}}";
fn find(records: []const typed.Record, name: []const u8) typed.Type {
    for (records) |record| if (std.mem.eql(u8, name, record.name)) return record.id;
    unreachable;
}
fn scenario(allocator: std.mem.Allocator) !void {
    var c = try language.Compilation.init(allocator, "codec-json.my", source);
    defer c.deinit();
    try c.emit();
    var failure: codec.Failure = .{};
    defer failure.deinit(allocator);
    const ty = find(c.code.?.records, "Pair");
    var stats: codec.Statistics = .{};
    const value = try codec.decode(allocator, c.code.?, ty, good, .{ .statistics = &stats }, &failure);
    defer value.release(allocator);
    const text = try codec.encode(allocator, c.code.?, ty, value, .{}, &failure);
    defer allocator.free(text);
    try t.expectEqualStrings(good, text);
    const unexpected = codec.decode(allocator, c.code.?, ty, bad, .{}, &failure) catch |err| {
        if (err == error.OutOfMemory) return err;
        try t.expectEqual(error.DomainCodecRejected, err);
        try t.expectEqualStrings("/value/items/1", failure.location.text());
        try t.expectEqualStrings("Why", typed.typeName(failure.execution.rejection.?.typeOf(), c.code.?.records));
        try t.expectEqual(@as(i64, -1), failure.execution.rejection.?.aggregate.fields[0].i64);
        try t.expectError(error.UnreleasedCodecFailure, codec.decode(allocator, c.code.?, ty, good, .{}, &failure));
        try t.expectEqual(@as(i64, -1), failure.execution.rejection.?.aggregate.fields[0].i64);
        return;
    };
    unexpected.release(allocator);
    return error.TestExpectedRejection;
}
test "codec JSON UnreleasedCodecFailure preserves typed rejections under allocation failures" {
    try scenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), scenario, .{});
}
/// A run under a tighter budget either fits or reports the memory limit.
fn expectMemoryBound(outcome: anyerror!@import("value.zig").Value) !void {
    const bounded = outcome catch |err| return t.expectEqual(error.CodecMemoryLimit, err);
    bounded.release(t.allocator);
}
// spec: WIRE-5
test "codec JSON shares instruction call traversal and memory budgets across nested values" {
    var c = try language.Compilation.init(t.allocator, "budgets.my", source);
    defer c.deinit();
    try c.emit();
    const code = c.code.?;
    const ty = find(code.records, "Pair");
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    var stats: codec.Statistics = .{};
    const measured = try codec.decode(t.allocator, code, ty, good, .{ .statistics = &stats }, &failure);
    measured.release(t.allocator);
    const exact = stats;
    // A budgeted run cannot grow its arena in place, so it needs room for the copy.
    const at_limit = try codec.decode(t.allocator, code, ty, good, .{ .max_steps = exact.steps, .max_bytes = 4 * exact.peak_bytes }, &failure);
    at_limit.release(t.allocator);
    try t.expectError(error.CodecMemoryLimit, codec.decode(t.allocator, code, ty, good, .{ .max_bytes = 1 }, &failure));
    try expectMemoryBound(codec.decode(t.allocator, code, ty, good, .{ .max_bytes = exact.peak_bytes - 1, .statistics = &stats }, &failure));
    try t.expectError(error.DomainCodecTrap, codec.decode(t.allocator, code, ty, good, .{ .max_steps = exact.steps - 1, .statistics = &stats }, &failure));
    try t.expectEqualStrings("R_STEP_LIMIT", failure.execution.trap.?.code);
    try t.expectEqualStrings("/value/items/1", failure.location.text());
    try t.expectError(error.CodecCallLimit, codec.decode(t.allocator, code, ty, good, .{ .max_calls = 1, .statistics = &stats }, &failure));
    try t.expectEqualStrings("/value/items/1", failure.location.text());
    try t.expectError(error.CodecValueLimit, codec.decode(t.allocator, code, ty, good, .{ .json = .{ .max_values = exact.values - 1 } }, &failure));
    try t.expectError(error.InvalidCodecBudget, codec.decode(t.allocator, code, ty, good, .{ .max_calls = 0 }, &failure));
}
const Provider = struct {
    fn read(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
        if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
            \\module main
            \\import data
            \\
            \\
            \\def main() -> i64:
            \\    return 0
        );
        if (std.mem.eql(u8, path, "data.my")) return allocator.dupe(u8, "module data;export Wire;export Why;export Decoded;export Positive;export Pair;" ++ source);
        return error.NotFound;
    }
};
const project_good = "{\"version\":\"typed-json-v1\",\"type\":\"data::Pair\",\"value\":{\"items\":[{\"n\":\"7\"},{\"n\":\"9\"}]}}";
fn projectScenario(allocator: std.mem.Allocator) !void {
    var project = language.project.Project.init(allocator);
    defer project.deinit();
    try project.load(.{ .context = null, .read = Provider.read }, "main", .{});
    var index = try language.interfaces.build(&project);
    var c = try language.project_compile.Compilation.init(&index);
    var failure: codec.Failure = .{};
    defer failure.deinit(allocator);
    var stats: codec.Statistics = .{};
    const text = try codec.canonicalProject(allocator, &c, project_good, .{ .statistics = &stats }, &failure);
    defer allocator.free(text);
    try t.expectEqualStrings(project_good, text);
    // Do not treat a legitimate host allocation failure as a failed rejection test.
    const unexpected = codec.canonicalProject(allocator, &c, project_good, .{ .max_calls = 3 }, &failure) catch |err| {
        if (err == error.OutOfMemory) return err;
        try t.expectEqual(error.CodecCallLimit, err);
        try t.expectEqualStrings("/value/items/1", failure.location.text());
        return;
    };
    allocator.free(unexpected);
    return error.TestExpectedLimit;
}
test "codec JSON project round trips share both direction budgets under every allocation failure" {
    try projectScenario(t.allocator);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), projectScenario, .{});
}
test "codec JSON excludes unregistered domains in inactive branches and zero arrays" {
    var c = try language.Compilation.init(t.allocator, "opaque.my",
        \\domain D: i64:
        \\    pass
        \\
        \\
        \\union U:
        \\    none,
        \\    some: D
        \\
        \\
        \\class Z:
        \\    a: [0]D
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    for ([_][]const u8{ "U", "Z" }, [_][]const u8{ "{\"case\":\"none\"}", "{\"a\":[]}" }) |name, value| {
        const bytes = try std.fmt.allocPrint(t.allocator, "{{\"version\":\"typed-json-v1\",\"type\":\"{s}\",\"value\":{s}}}", .{ name, value });
        defer t.allocator.free(bytes);
        try t.expectError(error.NoImplicitCodec, codec.decode(t.allocator, c.code.?, find(c.code.?.records, name), bytes, .{}, &failure));
        try t.expectEqualStrings("/type", failure.location.text());
    }
}
test "codec JSON keeps wire depth separate from private domain storage and preserves u64 extrema" {
    var c = try language.Compilation.init(t.allocator, "width.my",
        \\result R:
        \\    ok: D,
        \\    err: bool
        \\
        \\
        \\domain D: u64:
        \\    codec u64:
        \\        decode: dec,
        \\        encode: enc
        \\
        \\    def dec(x: u64) -> R:
        \\        return Ok(wrap<D>(x))
        \\
        \\    def enc(x: D) -> u64:
        \\        return unwrap(x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    const bytes = "{\"version\":\"typed-json-v1\",\"type\":\"D\",\"value\":\"18446744073709551615\"}";
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    const ty = find(c.code.?.records, "D");
    const options: codec.Options = .{ .json = .{ .max_depth = 1, .max_values = 2 } };
    const value = try codec.decode(t.allocator, c.code.?, ty, bytes, options, &failure);
    defer value.release(t.allocator);
    const encoded = try codec.encode(t.allocator, c.code.?, ty, value, options, &failure);
    defer t.allocator.free(encoded);
    try t.expectEqualStrings(bytes, encoded);
    try t.expectError(error.CodecWorkLimit, codec.encode(t.allocator, c.code.?, ty, value, .{ .max_work_values = 1 }, &failure));
}
test "codec JSON traps retain source traces and frame budgets" {
    var c = try language.Compilation.init(t.allocator, "loop.my",
        \\result R:
        \\    ok: D,
        \\    err: i64
        \\
        \\
        \\domain D: i64:
        \\    codec i64:
        \\        decode: dec,
        \\        encode: enc
        \\
        \\    def dec(x: i64) -> R:
        \\        return D.dec(x)
        \\
        \\    def enc(x: D) -> i64:
        \\        return unwrap(x)
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer c.deinit();
    try c.emit();
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    try t.expectError(error.DomainCodecTrap, codec.decode(t.allocator, c.code.?, find(c.code.?.records, "D"), "{\"version\":\"typed-json-v1\",\"type\":\"D\",\"value\":\"1\"}", .{ .max_frames = 2 }, &failure));
    try t.expectEqualStrings("/value", failure.location.text());
    try t.expectEqualStrings("R_FRAME_LIMIT", failure.execution.trap.?.code);
    try t.expectEqual(@as(usize, 2), failure.execution.trap.?.stack.len);
    try t.expectEqualStrings("D.dec", failure.execution.trap.?.stack.frames[0].function);
}
test "codec JSON rejects recursive host codec metadata before wire traversal" {
    var c = try language.Compilation.init(t.allocator, "metadata.my", source);
    defer c.deinit();
    try c.emit();
    var code = c.code.?;
    const records = try t.allocator.dupe(typed.Record, code.records);
    defer t.allocator.free(records);
    const domain = find(records, "Positive");
    records[domain.recordIndex()].contract.codec.?.wire = domain;
    code.records = records;
    var failure: codec.Failure = .{};
    defer failure.deinit(t.allocator);
    try t.expectError(error.NoImplicitCodec, codec.decode(t.allocator, code, find(records, "Pair"), good, .{}, &failure));
    try t.expectEqualStrings("/type", failure.location.text());
}
test "codec execution rejects exhausted steps and forged wire contracts" {
    var c = try language.Compilation.init(t.allocator, "codec-contract.my", source);
    defer c.deinit();
    try c.emit();
    const runtime = @import("codec_execution.zig");
    var failure: runtime.Failure = .{};
    defer failure.deinit(t.allocator);
    var execution: runtime.Execution = .{
        .backend = .{ .dispatch = @import("vm.zig").invoke, .program = c.code.? },
        .max_steps = 0,
        .max_frames = 256,
        .max_calls = 10,
        .arguments = .{},
        .failure = &failure,
    };
    try t.expectError(error.CodecStepLimit, execution.invoke(t.allocator, c.code.?.main, &.{}));
    try t.expectEqual(@as(usize, 0), execution.used.calls);
    const domain = find(c.code.?.records, "Positive");
    const value = try typed.Value.create(t.allocator, domain, &.{.{ .i64 = 7 }});
    defer value.release(t.allocator);
    @constCast(c.code.?.records)[domain.recordIndex()].contract.codec.?.wire = .bool;
    execution.max_steps = 1000000;
    try t.expectError(error.InvalidCodecContract, execution.encode(t.allocator, domain, value));
}
