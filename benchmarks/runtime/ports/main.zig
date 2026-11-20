// Dynamic collections use the general-purpose libc allocator. Shared batches
// duplicate the entire values slice and free the snapshot inside the kernel.
const std = @import("std");
const allocator = std.heap.c_allocator;
const modulus: i64 = 1_000_000_007;
const Record = struct { code: i64, bias: i64, payload: []i64 };
const Value = union(enum) { integer: i64, boolean: bool };
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
fn now() i64 {
    var time: Timespec = undefined;
    if (clock_gettime(1, &time) != 0) @panic("monotonic clock failed");
    return time.sec * 1_000_000_000 + time.nsec;
}
fn readRecord(record: *const Record) i64 {
    return record.code + record.bias + record.payload[0];
}
/// Runs the runtime kernel selected by the four positional arguments.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    if (argc != 5) return 2;
    const kind = std.mem.span(argv[1]);
    const size = std.fmt.parseInt(usize, std.mem.span(argv[2]), 10) catch return 2;
    const iterations = std.fmt.parseInt(i64, std.mem.span(argv[3]), 10) catch return 2;
    const seed = std.fmt.parseInt(i64, std.mem.span(argv[4]), 10) catch return 2;
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1_000_000) return 2;
    const n: i64 = @intCast(size);
    var checksum: i64 = 0;
    var elapsed: i64 = 0;
    if (std.mem.eql(u8, kind, "record_reads")) {
        const records = allocator.alloc(Record, size) catch @panic("allocation failed");
        defer allocator.free(records);
        for (records, 0..) |*record, j| {
            const index: i64 = @intCast(j);
            const payload = allocator.alloc(i64, 4) catch @panic("allocation failed");
            for (payload, 0..) |*v, k| v.* = index + seed + @as(i64, @intCast(k));
            record.* = .{ .code = @mod(seed + index * 17, 1009), .bias = @mod(seed * 3 + index * 7, 257), .payload = payload };
        }
        defer for (records) |record| allocator.free(record.payload);
        var index: usize = @intCast(@mod(seed, n));
        const start = now();
        var step: i64 = 0;
        while (step < iterations) : (step += 1) {
            const v = readRecord(&records[index]);
            checksum = @mod(checksum + v, modulus);
            index = @intCast(@mod(@as(i64, @intCast(index)) + 2 * seed + 1, n));
        }
        elapsed = now() - start;
    } else if (std.mem.eql(u8, kind, "tagged_stack")) {
        const opcodes = allocator.alloc(i64, size) catch @panic("allocation failed");
        defer allocator.free(opcodes);
        for (opcodes, 0..) |*op, j| op.* = @mod(@as(i64, @intCast(j)) + seed, 4);
        var stack: std.ArrayList(Value) = .empty;
        defer stack.deinit(allocator);
        stack.append(allocator, .{ .integer = seed }) catch @panic("allocation failed");
        stack.append(allocator, .{ .boolean = false }) catch @panic("allocation failed");
        var cursor: usize = 0;
        const start = now();
        var step: i64 = 0;
        while (step < iterations) : (step += 1) {
            const popped = stack.pop().?;
            const base = stack.items[0].integer;
            const op = opcodes[cursor];
            const delta: i64 = switch (popped) {
                .boolean => |b| switch (op) {
                    0 => if (b) 3 else 1,
                    1 => 7,
                    2 => 11,
                    3 => 13,
                    else => unreachable,
                },
                .integer => |v| @mod(v, switch (op) {
                    0 => @as(i64, 5),
                    1 => 7,
                    2 => 11,
                    3 => 13,
                    else => unreachable,
                }),
            };
            const next = @mod(base + delta + op + 1, 1_000_003);
            stack.items[0] = .{ .integer = next };
            const top: Value = if (op == 0 or op == 2) .{ .boolean = @mod(next, 2) == 0 } else .{ .integer = @mod(next, 97) };
            stack.append(allocator, top) catch @panic("allocation failed");
            cursor = (cursor + 1) % size;
        }
        elapsed = now() - start;
        checksum = stack.items[0].integer * 101 + switch (stack.items[1]) {
            .integer => |v| v,
            .boolean => |b| @as(i64, @intFromBool(b)),
        };
    } else if (std.mem.eql(u8, kind, "mutate_unique") or std.mem.eql(u8, kind, "mutate_shared")) {
        const shared = std.mem.eql(u8, kind, "mutate_shared");
        const values = allocator.alloc(i64, size) catch @panic("allocation failed");
        defer allocator.free(values);
        for (values, 0..) |*v, j| v.* = @mod(seed + @as(i64, @intCast(j)) * 13, 1009);
        const start = now();
        var batch: i64 = 0;
        while (batch < iterations) : (batch += 1) {
            const index: usize = @intCast(@mod(seed + batch * 17, n));
            if (shared) {
                const snapshot = allocator.dupe(i64, values) catch @panic("allocation failed");
                values[index] = @mod(values[index] + batch + 1, 1_000_003);
                checksum = @mod(checksum + snapshot[index] + values[index], modulus);
                allocator.free(snapshot);
            } else {
                values[index] = @mod(values[index] + batch + 1, 1_000_003);
                checksum = @mod(checksum + values[index], modulus);
            }
        }
        elapsed = now() - start;
        for (values) |v| checksum = @mod(checksum + v, modulus);
    } else return 2;
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
