// Row `grid_dp` (CONTRACT.md): a minimum-cost path DP over two nested dynamic grids.
// Each grid is a `c_allocator` slice of `c_allocator` row slices, built row by row and freed inside every batch.
const std = @import("std");
const a = std.heap.c_allocator;
const MOD: i64 = 1_000_000_007;
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;

fn now() i64 {
    var ts: Timespec = undefined;
    if (clock_gettime(1, &ts) != 0) @panic("clock failed");
    return ts.sec * 1_000_000_000 + ts.nsec;
}

/// Largest `w` with `w * w <= n`, the same integer loop in every language.
fn isqrt(n: usize) usize {
    var w: usize = 0;
    while ((w + 1) * (w + 1) <= n) w += 1;
    return w;
}

fn allocGrid(h: usize, w: usize) ![][]i64 {
    const grid = try a.alloc([]i64, h);
    var built: usize = 0;
    errdefer {
        for (grid[0..built]) |row| a.free(row);
        a.free(grid);
    }
    while (built < h) : (built += 1) grid[built] = try a.alloc(i64, w);
    return grid;
}

fn freeGrid(grid: [][]i64) void {
    for (grid) |row| a.free(row);
    a.free(grid);
}

fn batchResult(w: usize, h: usize, batch: i64, seed: i64) !i64 {
    const cost = try allocGrid(h, w);
    defer freeGrid(cost);
    for (cost, 0..) |row, i| {
        for (row, 0..) |*cell, j| cell.* = @mod(seed + batch + 13 * @as(i64, @intCast(i * w + j)), 1009);
    }
    const dp = try allocGrid(h, w);
    defer freeGrid(dp);
    dp[0][0] = cost[0][0];
    for (1..w) |j| dp[0][j] = dp[0][j - 1] + cost[0][j];
    for (1..h) |i| {
        dp[i][0] = dp[i - 1][0] + cost[i][0];
        for (1..w) |j| dp[i][j] = cost[i][j] + @min(dp[i - 1][j], dp[i][j - 1]);
    }
    var part = dp[h - 1][w - 1];
    for (dp[h - 1]) |v| part += v;
    return part;
}

fn run(argc: c_int, argv: [*][*:0]const u8) !c_int {
    if (argc != 5) return 2;
    if (!std.mem.eql(u8, std.mem.span(argv[1]), "grid_dp")) return 2;
    const size = std.fmt.parseInt(usize, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1000000) return 2;
    const w = isqrt(size);
    const h = size / w;
    var checksum: i64 = 0;
    const start = now();
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) checksum = @mod(checksum + try batchResult(w, h, batch, seed), MOD);
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}

/// Runs the grid_dp row selected by argv: `grid_dp SIZE ITERATIONS SEED`.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    return run(argc, argv) catch 1;
}
