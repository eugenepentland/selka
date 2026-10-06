// Row `tree_build_walk` (S4 CONTRACT.md): nodes are `c_allocator` allocations linked by optional
// pointers (null is Leaf) and freed by a recursive `destroy` inside each batch.
const std = @import("std");
const a = std.heap.c_allocator;
const MOD: i64 = 1_000_000_007;
const Node = struct { left: ?*Node, value: i64, right: ?*Node };
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
fn now() i64 {
    var ts: Timespec = undefined;
    if (clock_gettime(1, &ts) != 0) @panic("clock failed");
    return ts.sec * 1_000_000_000 + ts.nsec;
}
fn destroy(tree: ?*Node) void {
    const node = tree orelse return;
    destroy(node.left);
    destroy(node.right);
    a.destroy(node);
}
fn build(lo: i64, hi: i64, base: i64) error{OutOfMemory}!?*Node {
    if (lo >= hi) return null;
    const mid = @divTrunc(lo + hi, 2);
    const left = try build(lo, mid, base);
    errdefer destroy(left);
    const right = try build(mid + 1, hi, base);
    errdefer destroy(right);
    const node = try a.create(Node);
    node.* = .{ .left = left, .value = @mod(base + 13 * mid, 1009), .right = right };
    return node;
}
fn walk(tree: ?*const Node, depth: i64) i64 {
    const node = tree orelse return 0;
    return (depth + 1) * node.value + walk(node.left, depth + 1) + walk(node.right, depth + 1);
}
fn run(argc: c_int, argv: [*][*:0]const u8) !c_int {
    if (argc != 5 or !std.mem.eql(u8, std.mem.span(argv[1]), "tree_build_walk")) return 2;
    const size = std.fmt.parseInt(i64, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1000000) return 2;
    var checksum: i64 = 0;
    const start = now();
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) {
        const tree = try build(0, size, seed + batch);
        const part = @mod(walk(tree, 0), MOD);
        destroy(tree);
        checksum = @mod(checksum + part, MOD);
    }
    const elapsed = now() - start;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
/// Runs the tree_build_walk row selected by argv.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    return run(argc, argv) catch 1;
}
