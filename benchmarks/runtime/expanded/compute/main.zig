const std = @import("std");
const allocator = std.heap.c_allocator;
const modulus: i64 = 1_000_000_007;
const Triple = struct { a: i64, b: i64, c: i64 };
const Packet = struct { identifier: i64, payload_sum: i64, length: i64 };
const PacketResult = union(enum) { ok: Packet, err: i64 };
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
fn now() i64 {
    var time: Timespec = undefined;
    if (clock_gettime(1, &time) != 0) @panic("monotonic clock failed");
    return time.sec * 1_000_000_000 + time.nsec;
}
fn affineA(x: i64) i64 {
    return x * 3 + 7;
}
fn affineB(x: i64) i64 {
    return x * 5 + 11;
}
fn score(r: Triple) i64 {
    return r.a + r.b * 3 + r.c * 5;
}
fn optional(x: i64, phase: i64) ?i64 {
    return if (@mod(x, 4) == 0) null else x + phase;
}
fn checked(x: i64, phase: i64) error{Invalid}!i64 {
    if (@mod(x, 5) == 0) return error.Invalid;
    return x + phase;
}
fn forwarded(x: i64, phase: i64) error{Invalid}!i64 {
    const value = try checked(x, phase);
    return value * 3 + 1;
}
fn search(xs: []const i64, key: i64) i64 {
    var low: usize = 0;
    var high: usize = xs.len;
    while (low < high) {
        const middle = (low + high) / 2;
        if (xs[middle] < key) {
            low = middle + 1;
        } else {
            high = middle;
        }
    }
    return if (low < xs.len and xs[low] == key) @as(i64, @intCast(low)) + 1 else 0;
}
fn frame(j: i64, seed: i64) []u8 {
    const id = @mod(seed + j * 17, 65536);
    const raw = allocator.alloc(u8, 10) catch @panic("allocation failed");
    raw[0] = 165;
    raw[1] = 1;
    raw[2] = @intCast(@divTrunc(id, 256));
    raw[3] = @intCast(@mod(id, 256));
    raw[4] = 4;
    for (0..4) |k| raw[5 + k] = @intCast(@mod(seed + j * 13 + @as(i64, @intCast(k)) * 7, 256));
    var check: i64 = 0;
    for (raw[0..9]) |b| check += b;
    raw[9] = @intCast(@mod(check, 256));
    switch (@mod(j, 4)) {
        1 => raw[0] = 164,
        2 => raw[9] +%= 1,
        3 => raw[4] = 5,
        else => {},
    }
    return raw;
}
fn decode(raw: []const u8) PacketResult {
    if (raw.len < 6) return .{ .err = 3 };
    if (raw[0] != 165) return .{ .err = 1 };
    if (raw[1] != 1) return .{ .err = 2 };
    const length: usize = raw[4];
    if (raw.len != length + 6) return .{ .err = 3 };
    var check: i64 = 0;
    for (raw[0 .. raw.len - 1]) |b| check += b;
    if (@mod(check, 256) != raw[raw.len - 1]) return .{ .err = 4 };
    var total: i64 = 0;
    for (raw[5 .. raw.len - 1]) |b| total += b;
    return .{ .ok = .{ .identifier = @as(i64, raw[2]) * 256 + raw[3], .payload_sum = total, .length = @intCast(length) } };
}
/// Runs one complete dataset pass per iteration for the selected compute case.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    if (argc != 5) return 2;
    const names = [_][]const u8{ "integer_math", "float_math", "branch_predictable", "branch_mixed", "record_construct", "record_update", "call_direct", "call_indirect", "option_handle", "result_propagate", "binary_search", "packet_decode" };
    var kind: usize = names.len;
    for (names, 0..) |name, index| {
        if (std.mem.eql(u8, name, std.mem.span(argv[1]))) kind = index;
    }
    if (kind == names.len) return 2;
    const size = std.fmt.parseInt(usize, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1_000_000) return 2;
    const values = allocator.alloc(i64, size) catch @panic("allocation failed");
    defer allocator.free(values);
    const ordered = allocator.alloc(i64, size) catch @panic("allocation failed");
    defer allocator.free(ordered);
    const flags = allocator.alloc(bool, size) catch @panic("allocation failed");
    defer allocator.free(flags);
    const records = allocator.alloc(Triple, size) catch @panic("allocation failed");
    defer allocator.free(records);
    const frames = allocator.alloc([]u8, size) catch @panic("allocation failed");
    defer allocator.free(frames);
    for (values, 0..) |*v, j| {
        const index: i64 = @intCast(j);
        const x = @mod(seed + index * 37, 1009);
        v.* = x;
        ordered[j] = index * 3 + @mod(seed, 11);
        flags[j] = if (kind == 2) j % 16 != 0 else @mod(x * 73 + index * 19 + seed, 101) < 50;
        records[j] = .{ .a = x, .b = @mod(x, 17), .c = @mod(x * 3, 101) };
        frames[j] = frame(index, seed);
    }
    defer for (frames) |raw| allocator.free(raw);
    const function: *const fn (i64) i64 = if (@mod(seed, 2) == 0) affineA else affineB;
    var checksum: i64 = 0;
    const start = now();
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) {
        const phase = @mod(batch, 17);
        var pass_total: i64 = 0;
        for (values, 0..) |x, j| {
            const value: i64 = switch (kind) {
                0 => @mod(@divTrunc((x + phase) * 17 + 23, 7), 1009),
                1 => @intFromFloat(((@as(f64, @floatFromInt(x)) / 8.0 + @as(f64, @floatFromInt(phase)) / 4.0) * (@as(f64, @floatFromInt(x)) / 16.0 + 1.0) + 0.5) * 128.0),
                2, 3 => if (flags[j]) (x + phase) * 3 + 1 else (x + phase) * 5 + 7,
                4 => score(.{ .a = x + phase, .b = @mod(x, 17), .c = @mod(x * 3 + phase, 101) }),
                5 => update: {
                    var r = records[j];
                    r.a = x + phase;
                    r.b = @mod(x, 17);
                    r.c = @mod(x * 3 + phase, 101);
                    break :update score(r);
                },
                6 => affineA(x + phase),
                7 => function(x + phase),
                8 => if (optional(x, phase)) |v| v * 3 + 1 else 19,
                9 => forwarded(x, phase) catch 7,
                10 => search(ordered, @mod(x + phase, @as(i64, @intCast(size)) * 3 + 3) + @mod(seed, 11)),
                11 => switch (decode(frames[j])) {
                    .ok => |p| p.identifier + p.payload_sum * 3 + p.length,
                    .err => |e| e * 101,
                },
                else => unreachable,
            };
            pass_total += value;
        }
        checksum = @mod(checksum + pass_total, modulus);
    }
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
