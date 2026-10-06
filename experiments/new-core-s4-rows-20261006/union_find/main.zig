// Row `union_find` (CONTRACT.md): union by linking roots, path halving that mutates `parent`.
// `parent` is one `c_allocator` slice per batch; `find` takes `[]usize` and writes through it.
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

fn find(parent: []usize, start: usize) usize {
    var x = start;
    while (parent[x] != x) {
        parent[x] = parent[parent[x]];
        x = parent[x];
    }
    return x;
}

fn batchResult(size: usize, batch: i64, seed: i64) !i64 {
    const n: i64 = @intCast(size);
    const parent = try a.alloc(usize, size);
    defer a.free(parent);
    for (parent, 0..) |*p, j| p.* = j;
    var j: i64 = 0;
    while (j < n) : (j += 1) {
        const x: usize = @intCast(@mod(seed + batch + 13 * j, n));
        const y: usize = @intCast(@mod(seed + 7 * batch + 17 * j + 1, n));
        const ra = find(parent, x);
        const rb = find(parent, y);
        if (ra != rb) parent[ra] = rb;
    }
    var components: i64 = 0;
    for (0..size) |k| {
        if (find(parent, k) == k) components += 1;
    }
    var rootsum: i64 = 0;
    for (0..size) |k| rootsum += @intCast(find(parent, k));
    return @mod(components * 1000003 + rootsum, MOD);
}

fn run(argc: c_int, argv: [*][*:0]const u8) !c_int {
    if (argc != 5) return 2;
    if (!std.mem.eql(u8, std.mem.span(argv[1]), "union_find")) return 2;
    const size = std.fmt.parseInt(usize, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1000000) return 2;
    var checksum: i64 = 0;
    const start = now();
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) checksum = @mod(checksum + try batchResult(size, batch, seed), MOD);
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}

/// Runs the union_find row selected by argv: `union_find SIZE ITERATIONS SEED`.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    return run(argc, argv) catch 1;
}
