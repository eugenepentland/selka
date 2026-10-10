//! Independent admission, SCC and bounded incremental transport regressions.
const std = @import("std");
const wire = @import("cache_plan_protocol_v2.zig");
const oracle = @import("cache_plan_reference_v2.zig");

// spec-case: SELFHOST-CACHE-PLAN-2
test "incremental transpose cleans up every allocation failure and preserves repeated edges" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, transposeAllocations, .{});
    try std.testing.expectError(error.ComponentProtocol, wire.transpose(std.testing.allocator, .{ .digests = &.{@splat(1)}, .callees = &.{&.{1}} }));
}

fn transposeAllocations(a: std.mem.Allocator) !void {
    const rows = try wire.transpose(a, .{ .digests = &.{ @splat(1), @splat(2) }, .callees = &.{ &.{ 1, 1 }, &.{} } });
    defer {
        for (rows) |row| a.free(row);
        a.free(rows);
    }
    try std.testing.expectEqualSlices(u32, &.{ 0, 0 }, rows[1]);
    try std.testing.expectEqual(@as(usize, 0), rows[0].len);
}

// spec: SELFHOST-CACHE-PLAN-2
test "incremental planner reuses disjoint keys and affects transitive roots preserving multiplicity" {
    const a = std.testing.allocator;
    const input: wire.Incremental = .{
        .graph = .{ .digests = &.{ @splat(5), @splat(7), @splat(7), @splat(9) }, .callees = &.{ &.{ 1, 2 }, &.{0}, &.{1}, &.{} } },
        .topology = @splat(1),
        .roots = &.{ &.{ 0, 0 }, &.{3}, &.{ 1, 0 }, &.{} },
        .changed = &.{2},
        .candidates = &.{ true, true, true, false },
    };
    var result = try oracle.plan(a, input);
    defer result.deinit();
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 0, 3 }, result.indexes.groups);
    try std.testing.expectEqualSlices(bool, &.{ false, true, false, false }, result.reused);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, result.batches[0]);
    try std.testing.expectEqualSlices(u32, &.{2}, result.batches[2]);
    try std.testing.expectEqual(@as(u64, 3), result.work.affected_nodes);
    const request = try wire.request(a, input, 42);
    defer a.free(request.bytes);
    const response = try wire.response(a, result, request.identity);
    defer a.free(response);
    var decoded = try wire.reply(a, response, request.identity, input);
    defer decoded.deinit();
    try std.testing.expectEqualSlices(bool, result.reused, decoded.reused);
    try rejectFrames(a, response, request.identity, input);
}

fn rejectFrames(a: std.mem.Allocator, bytes: []u8, identity: @import("cache_plan_protocol.zig").Identity, input: wire.Incremental) !void {
    for (0..bytes.len) |length| try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes[0..length], identity, input));
    for ([_]usize{ 0, 8, 12, 16, 20, 24, 32, 63, 120, 124 }) |offset| {
        bytes[offset] ^= 1;
        try std.testing.expectError(error.ComponentProtocol, wire.reply(a, bytes, identity, input));
        bytes[offset] ^= 1;
    }
}

// spec-case: SELFHOST-CACHE-PLAN-2
test "incremental retained indexes admit unchanged keys and reject stale topology malformed reverse and duplicate changes" {
    const a = std.testing.allocator;
    var input: wire.Incremental = .{ .graph = .{ .digests = &.{ @splat(1), @splat(2) }, .callees = &.{ &.{1}, &.{} } }, .topology = @splat(3), .roots = &.{&.{0}}, .changed = &.{}, .candidates = &.{true} };
    var initial = try oracle.plan(a, input);
    defer initial.deinit();
    input.prior = initial.indexes;
    var warm = try oracle.plan(a, input);
    defer warm.deinit();
    try std.testing.expectEqualSlices(bool, &.{true}, warm.reused);
    try std.testing.expectEqual(@as(u64, 0), warm.work.closure_nodes);
    input.topology[0] ^= 1;
    try std.testing.expectError(error.ComponentProtocol, oracle.plan(a, input));
    input.topology[0] ^= 1;
    input.prior.?.reverse = &.{ &.{}, &.{} };
    try std.testing.expectError(error.ComponentProtocol, oracle.plan(a, input));
    input.prior = null;
    input.changed = &.{ 0, 0 };
    try std.testing.expectError(error.ComponentProtocol, oracle.plan(a, input));
}

// spec-case: SELFHOST-CACHE-PLAN-2
test "incremental SCC creation and splitting replace former graph dependencies" {
    const a = std.testing.allocator;
    var input: wire.Incremental = .{
        .graph = .{ .digests = &.{ @splat(1), @splat(2), @splat(3) }, .callees = &.{ &.{1}, &.{ 0, 2 }, &.{} } },
        .topology = @splat(1),
        .roots = &.{ &.{0}, &.{2} },
        .changed = &.{1},
        .candidates = &.{ true, true },
    };
    var cyclic = try oracle.plan(a, input);
    defer cyclic.deinit();
    try std.testing.expectEqualSlices(u32, &.{ 0, 0, 2 }, cyclic.indexes.groups);
    try std.testing.expectEqualSlices(u32, &.{ 1, 2 }, cyclic.batches[0]);
    input.graph.callees = &.{ &.{1}, &.{}, &.{} };
    input.topology = @splat(2);
    var split = try oracle.plan(a, input);
    defer split.deinit();
    try std.testing.expectEqualSlices(u32, &.{ 0, 1, 2 }, split.indexes.groups);
    try std.testing.expectEqualSlices(u32, &.{1}, split.batches[0]);
    try std.testing.expectEqualSlices(bool, &.{ false, true }, split.reused);
}

// spec-case: SELFHOST-CACHE-PLAN-2
test "incremental reply cannot reuse a missing candidate or exceed aggregate work" {
    const a = std.testing.allocator;
    const input: wire.Incremental = .{ .graph = .{ .digests = &.{}, .callees = &.{} }, .topology = @splat(1), .roots = &.{&.{}}, .changed = &.{}, .candidates = &.{false} };
    var result = try oracle.plan(a, input);
    defer result.deinit();
    const request = try wire.request(a, input, 7);
    defer a.free(request.bytes);
    const response = try wire.response(a, result, request.identity);
    defer a.free(response);
    std.mem.writeInt(u32, response[128..132], 1, .little);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, response, request.identity, input));
    std.mem.writeInt(u32, response[128..132], 0, .little);
    std.mem.writeInt(u64, response[64..72], wire.max_work, .little);
    std.mem.writeInt(u64, response[72..80], wire.max_work, .little);
    try std.testing.expectError(error.ComponentProtocol, wire.reply(a, response, request.identity, input));
}
