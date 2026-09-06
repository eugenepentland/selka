//! Exercise the trusted trial boundary with leak detection and allocation failures.
const std = @import("std");
const t = std.testing;
const application = @import("app.zig");
const values = @import("values.zig");
const input = @import("input.zig");
const Geometry = @import("geometry.zig").Geometry;
const Kernel = @import("kernel.zig").Kernel;
const m = @import("model.zig");
const outline: m.Rect = .{ .x = @fromBackingInt(0), .y = @fromBackingInt(0), .width = @fromBackingInt(10), .height = @fromBackingInt(10) };
const region: m.Region = .{ .rect = outline, .face = .top, .blocks = .{ .via = true }, .allow_nets = &.{} };
const via: m.Feature = .{ .via = .{ .net = @fromBackingInt(1), .rect = outline } };
const board: m.Board = .{ .outline = outline, .components = &.{}, .nets = &.{@fromBackingInt(1)}, .regions = &.{region}, .features = &.{via} };
fn snapshotScenario(allocator: std.mem.Allocator, meta: values.Meta) !void {
    var snapshot = try values.Snapshot.init(allocator, meta, board);
    defer snapshot.deinit();
    try t.expectEqualDeep(outline, try values.rect(meta, try meta.field(snapshot.value, "outline")));
}
fn callbackScenario(allocator: std.mem.Allocator, meta: values.Meta, rect: values.Value, unavailable: bool) !void {
    var geometry: Geometry = .{ .meta = meta, .kernel = .{ .unavailable = unavailable } };
    const result = try geometry.contact(allocator, rect, rect);
    defer result.release(allocator);
    try t.expectEqualStrings(if (unavailable) "err" else "ok", try meta.tag(result));
    try t.expectEqual(@as(u64, 1), geometry.kernel.calls);
}
// spec: BOARD-TRIAL-1
test "trial snapshot and callback allocation failures release all ordinary value graphs" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = application.embedded });
    defer app.deinit();
    const meta = app.geometry.meta;
    try snapshotScenario(t.allocator, meta);
    var stable = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(stable.allocator(), snapshotScenario, .{meta});
    var snapshot = try values.Snapshot.init(t.allocator, meta, board);
    defer snapshot.deinit();
    const rect = try meta.field(snapshot.value, "outline");
    for ([_]bool{ false, true }) |unavailable| {
        try callbackScenario(t.allocator, meta, rect, unavailable);
        try t.checkAllAllocationFailures(stable.allocator(), callbackScenario, .{ meta, rect, unavailable });
    }
}
test "trial VM reports typed failure then starts a fresh successful geometry session" {
    var app: application.App = undefined;
    try app.init(t.allocator, .{ .context = null, .read = application.embedded });
    defer app.deinit();
    try t.expectError(error.GuestTrap, app.run(t.allocator, board, false, .{ .execution = .{ .max_steps = 1 } }));
    try t.expectEqualStrings("R_STEP_LIMIT", app.trap.?.code);
    try t.expectEqual(@as(u64, 0), app.geometry.kernel.calls);
    const failed = try app.run(t.allocator, board, true, .{});
    try t.expectEqualDeep(m.Observation{ .outcome = .{ .err = .{ .geometry = .unavailable } }, .calls = 1 }, failed);
    const succeeded = try app.run(t.allocator, board, false, .{});
    try t.expectEqualDeep(m.Observation{ .outcome = .{ .ok = .{ .violations = 1, .first = .{ .feature = 0, .kind = .keepout, .region = 0 } } }, .calls = 1 }, succeeded);
    var oversized = board;
    oversized.nets = &.{ @fromBackingInt(1), @fromBackingInt(2), @fromBackingInt(3), @fromBackingInt(4), @fromBackingInt(5) };
    try t.expectError(error.SnapshotCapacity, values.Snapshot.init(t.allocator, app.geometry.meta, oversized));
    try t.expectError(error.SnapshotSchemaMismatch, values.rect(app.geometry.meta, .{ .i64 = 0 }));
    const meta = app.geometry.meta;
    const definitions = try t.allocator.dupe(@typeInfo(@TypeOf(meta.records)).pointer.child, meta.records);
    defer t.allocator.free(definitions);
    definitions[(try meta.find("ids::NetId")).recordIndex()].shape.domain = .i64;
    try t.expectError(error.SnapshotSchemaMismatch, values.Snapshot.init(t.allocator, .{ .records = definitions }, board));
}
test "trial kernel validates endpoints before arithmetic even when unavailable" {
    var kernel: Kernel = .{ .unavailable = true };
    var invalid = outline;
    invalid.x = @fromBackingInt(std.math.maxInt(i64));
    try t.expectEqualDeep(@import("kernel.zig").Result{ .err = .invalid_bounds }, kernel.intersect(invalid, outline));
    try t.expectEqual(@as(u64, 1), kernel.calls);
}
test "trial transport rejects partial allocations without leaking caller arena storage" {
    const bytes =
        \\{"name":"bad","unavailable":false,"input":{"version":1,"board":{"outline":[0,0,10,10],"components":[],"nets":[1],"regions":[{"rect":[0,0,1,1],"face":"top","blocks":["via"],"allow_nets":[]}],"features":[{"kind":"via","net":true,"rect":[0,0,1,1]}]}}}
    ;
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const parsed = try std.json.parseFromSlice(std.json.Value, arena.allocator(), bytes, .{ .parse_numbers = false });
    try t.expectError(error.InvalidSnapshot, input.request(arena.allocator(), parsed.value));
}
