//! Exercise the trusted trial boundary: the request layout the guest decodes,
//! the observation it publishes, the kernel contract and the native invocation.
//! Whole-trial agreement with the fixed oracle is `tests/board_trial.py`.
const std = @import("std");
const t = std.testing;
const native = @import("host_native");
const host = @import("host.zig");
const transport = @import("transport.zig");
const input = @import("input.zig");
const kernel = @import("kernel.zig");
const m = @import("model.zig");
const outline: m.Rect = .{ .x = @fromBackingInt(0), .y = @fromBackingInt(0), .width = @fromBackingInt(10), .height = @fromBackingInt(10) };
const region: m.Region = .{ .rect = outline, .face = .top, .blocks = .{ .via = true }, .allow_nets = &.{} };
const via: m.Feature = .{ .via = .{ .net = @fromBackingInt(1), .rect = outline } };
const board: m.Board = .{ .outline = outline, .components = &.{}, .nets = &.{@fromBackingInt(1)}, .regions = &.{region}, .features = &.{via} };
/// One complete report observation, as the guest publishes it.
fn report(violations: u8, present: u8, region_index: u8) [28]u8 {
    var bytes: [28]u8 = @splat(0);
    bytes[1] = violations;
    bytes[9] = present;
    bytes[18] = 1;
    bytes[19] = 1;
    bytes[20] = region_index;
    return bytes;
}
/// The offsets the guest's `wire` module names, read back out of its own source.
fn offset(name: []const u8) !i64 {
    const source = @embedFile("guest/wire.my");
    const start = std.mem.indexOf(u8, source, name) orelse return error.MissingOffset;
    const line = source[start + name.len ..];
    return std.fmt.parseInt(i64, std.mem.trim(u8, line[0 .. std.mem.indexOfScalar(u8, line, '\n') orelse 0], " "), 10);
}

// spec: BOARD-TRIAL-1
test "the request layout the host writes is the one the guest source says it reads" {
    try t.expectEqual(@as(i64, transport.request_bytes), try offset("const REQUEST: i64 ="));
    try t.expectError(error.MissingOffset, offset("const NOTHING: i64 ="));
    var bytes: transport.Request = undefined;
    transport.encode(board, &bytes);
    // The outline occupies four signed micrometre fields at the front.
    try t.expectEqual(@as(i64, 10), std.mem.readInt(i64, bytes[16..24], .little));
    // Exactly one net is present, and the remaining catalog slots stay absent.
    const nets: usize = @intCast(try offset("const NETS: i64 ="));
    try t.expectEqual(@as(u8, 1), bytes[nets]);
    try t.expectEqual(@as(u64, 1), std.mem.readInt(u64, bytes[nets + 1 ..][0..8], .little));
    try t.expectEqual(@as(u8, 0), bytes[nets + 9]);
    // The region declares its face and blocks exactly one family.
    const regions: usize = @intCast(try offset("const REGIONS: i64 ="));
    try t.expectEqual(@as(u8, 0), bytes[regions + 33]);
    try t.expectEqualSlices(u8, &.{ 0, 0, 1 }, bytes[regions + 34 ..][0..3]);
    // The sole feature is a through-via naming net one.
    const features: usize = @intCast(try offset("const FEATURES: i64 ="));
    try t.expectEqualSlices(u8, &.{ 1, 2 }, bytes[features..][0..2]);
    try t.expectEqual(@as(u64, 1), std.mem.readInt(u64, bytes[features + 34 ..][0..8], .little));
}

// spec-case: BOARD-TRIAL-1
test "an observation is read back only in the exact widths the guest publishes" {
    const violation = try transport.decode(&report(1, 1, 0));
    try t.expectEqualDeep(m.Outcome{ .ok = .{ .violations = 1, .first = .{ .feature = 0, .kind = .keepout, .region = 0 } } }, violation);
    try t.expectEqualDeep(m.Outcome{ .ok = .{ .violations = 3, .first = null } }, try transport.decode(&report(3, 0, 0)));
    try t.expectEqualDeep(m.Outcome{ .err = .{ .input = .missing_net } }, try transport.decode(&.{ 1, 7 }));
    try t.expectEqualDeep(m.Outcome{ .err = .{ .geometry = .unavailable } }, try transport.decode(&.{ 2, 1 }));
    try t.expectError(error.InvalidObservation, transport.decode(&.{}));
    try t.expectError(error.InvalidObservation, transport.decode(&.{ 3, 0 }));
    try t.expectError(error.InvalidObservation, transport.decode(&.{ 1, 8 }));
    try t.expectError(error.InvalidObservation, transport.decode(&.{ 2, 2 }));
    try t.expectError(error.InvalidObservation, transport.decode(&.{0}));
    const trailing = report(1, 1, 0) ++ [_]u8{0};
    try t.expectError(error.InvalidObservation, transport.decode(&trailing));
    var undeclared = report(1, 1, 0);
    undeclared[18] = 2;
    try t.expectError(error.InvalidObservation, transport.decode(&undeclared));
}

// spec-case: BOARD-TRIAL-1
test "the trusted provider linked into every guest declares only the trial boundary" {
    try t.expect(std.mem.indexOf(u8, host.provider, "MylangNativeProviders mylang_native_providers(void)") != null);
    try t.expect(std.mem.indexOf(u8, host.provider, "\"io::length\"") != null);
    try t.expect(std.mem.indexOf(u8, host.provider, "\"io::byte\"") != null);
    try t.expect(std.mem.indexOf(u8, host.provider, "\"io::put\"") != null);
    try t.expect(std.mem.indexOf(u8, host.provider, "\"geometry::overlap\"") != null);
    // Observation bytes reach a private file the driver publishes, never stdout.
    try t.expect(std.mem.indexOf(u8, host.provider, "MYLANG_BOARD_OBSERVATION") != null);
    try t.expect(std.mem.indexOf(u8, host.provider, "stdout") == null);
    // The provider and the host agree on the one request width, digit for digit.
    var width: [32]u8 = undefined;
    try t.expect(std.mem.indexOf(u8, host.provider, try std.fmt.bufPrint(&width, "REQUEST {d}", .{transport.request_bytes})) != null);
}

test "trial kernel validates endpoints before arithmetic even when unavailable" {
    var state: kernel.Kernel = .{ .unavailable = true };
    var invalid = outline;
    invalid.x = @fromBackingInt(std.math.maxInt(i64));
    try t.expectEqualDeep(kernel.Result{ .err = .invalid_bounds }, state.intersect(invalid, outline));
    try t.expectEqual(@as(u64, 1), state.calls);
    try t.expectEqualDeep(kernel.Result{ .err = .unavailable }, state.intersect(outline, outline));
    try t.expectEqual(@as(u64, 2), state.calls);
    // The kernel's own count reaches the driver as the provider wrote it.
    try t.expectEqual(@as(u64, 12), try host.counted("12\n"));
    try t.expectError(error.InvalidCallCount, host.counted(""));
    try t.expectError(error.InvalidCallCount, host.counted("many"));
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

// spec: BOARD-ABSTRACTION-1
test "trial catalogs keep a shared numeric identity apart across the trial boundary" {
    var shared = board;
    shared.components = &.{@fromBackingInt(7)};
    shared.nets = &.{@fromBackingInt(7)};
    shared.features = &.{.{ .component = .{ .id = @fromBackingInt(7), .face = .top, .rect = outline } }};
    var bytes: transport.Request = undefined;
    transport.encode(shared, &bytes);
    const components: usize = @intCast(try offset("const COMPONENTS: i64 ="));
    const nets: usize = @intCast(try offset("const NETS: i64 ="));
    // The same number reaches two separately addressed catalogs, never one.
    try t.expectEqual(@as(u64, 7), std.mem.readInt(u64, bytes[components + 1 ..][0..8], .little));
    try t.expectEqual(@as(u64, 7), std.mem.readInt(u64, bytes[nets + 1 ..][0..8], .little));
    try t.expect(components != nets);
    // The feature names the component family, so its identity cannot be a net.
    const features: usize = @intCast(try offset("const FEATURES: i64 ="));
    try t.expectEqual(@as(u8, 0), bytes[features + 1]);
    // The guest still reads both through one shared slot and one membership helper.
    try t.expect(std.mem.indexOf(u8, @embedFile("guest/model.my"), "union Slot[T]:") != null);
    try t.expect(std.mem.indexOf(u8, @embedFile("guest/inventory.my"), "def has[T: equality]") != null);
    try t.expect(std.mem.indexOf(u8, @embedFile("guest/request.my"), "def slot[T](present: bool, value: T) -> m.Slot[T]:") != null);
}

test "a native guest reports its entry result on its own final output line" {
    try t.expectEqual(@as(i64, 0), try native.outcome("0\n"));
    try t.expectEqual(@as(i64, -3), try native.outcome("noise\n-3\n"));
    try t.expectError(error.InvalidGuestResult, native.outcome(""));
    try t.expectError(error.InvalidGuestResult, native.outcome("trapped\n"));
    const options = try native.command(t.allocator, &.{"--max-steps=1"});
    defer t.allocator.free(options);
    try t.expectEqualSlices([]const u8, &.{ "--print-result", "--max-steps=1" }, options);
}
