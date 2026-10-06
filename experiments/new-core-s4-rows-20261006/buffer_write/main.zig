const std = @import("std");
const gpa = std.heap.c_allocator;
const modulus: i64 = 1_000_000_007;
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;

fn now() i64 {
    var t: Timespec = undefined;
    if (clock_gettime(1, &t) != 0) @panic("clock failed");
    return t.sec * 1_000_000_000 + t.nsec;
}

/// Appends the decimal digits of SIZE values to a fresh byte list, then folds and frees it.
fn batchResult(size: i64, batch: i64, seed: i64) i64 {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(gpa);
    var j: i64 = 0;
    while (j < size) : (j += 1) {
        const v = @mod(seed + batch + 13 * j, 100_003);
        buf.print(gpa, "{d}", .{v}) catch @panic("allocation failed");
        buf.append(gpa, ',') catch @panic("allocation failed");
        if (@mod(j, 16) == 15) buf.append(gpa, '\n') catch @panic("allocation failed");
    }
    var h: i64 = 0;
    for (buf.items) |c| h = @mod(h * 131 + c, modulus);
    return @mod(@as(i64, @intCast(buf.items.len)) + h, modulus);
}

/// Runs the buffer_write microbenchmark: `CASE SIZE ITERATIONS SEED`.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    if (argc != 5) return 2;
    if (!std.mem.eql(u8, std.mem.span(argv[1]), "buffer_write")) return 2;
    const size = std.fmt.parseInt(i64, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1_000_000) return 2;
    const start = now();
    var checksum: i64 = 0;
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) {
        checksum = @mod(checksum + batchResult(size, batch, seed), modulus);
    }
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
