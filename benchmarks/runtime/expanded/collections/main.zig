// Standard dynamic collections backed by libc malloc; nested snapshots duplicate all inner slices.
const std = @import("std");
const a = std.heap.c_allocator;
const MOD: i64 = 1_000_000_007;
const Value = union(enum) { integer: i64, boolean: bool };
const Row = struct { key: i64, ordinal: i64, value: i64 };
const Instruction = struct { op: u8, arg: usize };
const program_fixture = [_]Instruction{ .{ .op = 0, .arg = 0 }, .{ .op = 4, .arg = 0 }, .{ .op = 2, .arg = 0 }, .{ .op = 4, .arg = 1 }, .{ .op = 3, .arg = 1 }, .{ .op = 1, .arg = 0 }, .{ .op = 8, .arg = 0 }, .{ .op = 10, .arg = 29 }, .{ .op = 3, .arg = 1 }, .{ .op = 2, .arg = 2 }, .{ .op = 7, .arg = 0 }, .{ .op = 2, .arg = 0 }, .{ .op = 9, .arg = 0 }, .{ .op = 10, .arg = 18 }, .{ .op = 3, .arg = 0 }, .{ .op = 12, .arg = 31 }, .{ .op = 4, .arg = 0 }, .{ .op = 11, .arg = 24 }, .{ .op = 3, .arg = 0 }, .{ .op = 3, .arg = 1 }, .{ .op = 5, .arg = 0 }, .{ .op = 2, .arg = 1000003 }, .{ .op = 7, .arg = 0 }, .{ .op = 4, .arg = 0 }, .{ .op = 3, .arg = 1 }, .{ .op = 2, .arg = 1 }, .{ .op = 5, .arg = 0 }, .{ .op = 4, .arg = 1 }, .{ .op = 11, .arg = 4 }, .{ .op = 3, .arg = 0 }, .{ .op = 14, .arg = 0 }, .{ .op = 2, .arg = 3 }, .{ .op = 6, .arg = 0 }, .{ .op = 2, .arg = 7 }, .{ .op = 5, .arg = 0 }, .{ .op = 2, .arg = 1000003 }, .{ .op = 7, .arg = 0 }, .{ .op = 13, .arg = 0 } };
const Timespec = extern struct { sec: c_long, nsec: c_long };
extern "c" fn clock_gettime(clock: c_int, time: *Timespec) c_int;
extern "c" fn printf(format: [*:0]const u8, ...) c_int;
fn now() i64 {
    var ts: Timespec = undefined;
    if (clock_gettime(1, &ts) != 0) @panic("clock failed");
    return ts.sec * 1_000_000_000 + ts.nsec;
}
fn execute(program: []const Instruction, size: usize, seed: i64) !i64 {
    var stack: std.ArrayList(Value) = .empty;
    defer stack.deinit(a);
    var returns: std.ArrayList(usize) = .empty;
    defer returns.deinit(a);
    const variables = try a.alloc(i64, 2);
    defer a.free(variables);
    @memset(variables, 0);
    var pc: usize = 0;
    while (true) {
        const ins = program[pc];
        pc += 1;
        switch (ins.op) {
            0 => try stack.append(a, .{ .integer = seed }),
            1 => try stack.append(a, .{ .integer = @intCast(size) }),
            2 => try stack.append(a, .{ .integer = @intCast(ins.arg) }),
            3 => try stack.append(a, .{ .integer = variables[ins.arg] }),
            4 => variables[ins.arg] = stack.pop().?.integer,
            5...9 => {
                const b = stack.pop().?.integer;
                const left = stack.pop().?.integer;
                const v: Value = switch (ins.op) {
                    5 => .{ .integer = left + b },
                    6 => .{ .integer = left * b },
                    7 => .{ .integer = @mod(left, b) },
                    8 => .{ .boolean = left < b },
                    9 => .{ .boolean = left == b },
                    else => unreachable,
                };
                try stack.append(a, v);
            },
            10 => {
                if (!stack.pop().?.boolean) pc = ins.arg;
            },
            11 => pc = ins.arg,
            12 => {
                try returns.append(a, pc);
                pc = ins.arg;
            },
            13 => pc = returns.pop().?,
            14 => return stack.pop().?.integer,
            else => return error.BadOpcode,
        }
    }
}
fn fold(xs: []const i64) i64 {
    var sum: i64 = 0;
    for (xs, 0..) |v, j| sum += (@as(i64, @intCast(j)) + 1) * v;
    return sum;
}
fn lessInt(_: void, left: i64, right: i64) bool {
    return left < right;
}
fn lessRow(_: void, left: Row, right: Row) bool {
    return left.key < right.key;
}
const Inputs = struct { size: usize, seed: i64, values: []i64, keys: [][]u8, lookup: std.AutoHashMap(i64, i64), lookup_str: std.StringHashMap(i64), nested: [][]i64, program: []Instruction };
fn batchResult(kind: usize, batch: i64, input: *Inputs) !i64 {
    const size = input.size;
    const seed = input.seed;
    const n: i64 = @intCast(size);
    var sum: i64 = 0;
    if (kind == 0) {
        for (input.values) |v| sum += @mod(v + batch, 1009);
        return sum;
    }
    if (kind == 1) {
        var xs: std.ArrayList(i64) = .empty;
        defer xs.deinit(a);
        for (0..size) |j| try xs.append(a, @mod(seed + batch + @as(i64, @intCast(j)) * 13, 1009));
        return fold(xs.items);
    }
    if (kind == 2) {
        const xs = try a.alloc(i64, size);
        defer a.free(xs);
        for (xs, 0..) |*v, j| v.* = @mod(seed + batch + @as(i64, @intCast(j)) * 13, 1009);
        var filtered: std.ArrayList(i64) = .empty;
        defer filtered.deinit(a);
        for (xs) |v| {
            if (@mod(v, 3) == 0) try filtered.append(a, v);
        }
        return fold(filtered.items);
    }
    if (kind == 3 or kind == 4) {
        const string = kind == 4;
        for (0..size) |j| {
            const k = @mod(seed + @as(i64, @intCast(j)) * 17 + batch, n * 2);
            sum += if (string) input.lookup_str.get(input.keys[@intCast(k)]) orelse 17 else input.lookup.get(k) orelse 17;
        }
        return sum;
    }
    if (kind == 5) {
        var map = std.AutoHashMap(i64, i64).init(a);
        defer map.deinit();
        for (input.values, 0..) |v, j| try map.put(@intCast(j), v);
        for (0..size * 2) |j| {
            const k = @mod(seed + @as(i64, @intCast(j)) * 17 + batch, n * 2);
            try map.put(k, @mod((map.get(k) orelse 17) + @as(i64, @intCast(j)) + batch + 1, 1000003));
        }
        var iter = map.iterator();
        while (iter.next()) |entry| sum += entry.key_ptr.* + entry.value_ptr.*;
        return sum;
    }
    if (kind == 6) {
        var map = std.StringHashMap(i64).init(a);
        defer map.deinit();
        for (input.values, 0..) |v, j| try map.put(input.keys[j], v);
        for (0..size * 2) |j| {
            const k: usize = @intCast(@mod(seed + @as(i64, @intCast(j)) * 17 + batch, n * 2));
            try map.put(input.keys[k], @mod((map.get(input.keys[k]) orelse 17) + @as(i64, @intCast(j)) + batch + 1, 1000003));
        }
        for (input.keys, 0..) |key, j| {
            if (map.get(key)) |v| sum += @as(i64, @intCast(j)) + v;
        }
        return sum;
    }
    if (kind == 7) {
        var set = std.AutoHashMap(i64, void).init(a);
        defer set.deinit();
        for (0..size) |j| try set.put(@mod(seed + batch + @as(i64, @intCast(j)) * 13, @max(2, @divTrunc(n, 4))), {});
        var iter = set.keyIterator();
        while (iter.next()) |key| sum += key.*;
        return sum;
    }
    if (kind == 8) {
        for (0..size) |j| {
            const xs = try a.alloc(i64, 4);
            for (xs, 0..) |*v, k| v.* = seed + batch + @as(i64, @intCast(j)) + @as(i64, @intCast(k));
            for (xs) |v| sum += v;
            a.free(xs);
        }
        return sum;
    }
    if (kind == 9) {
        var lists: std.ArrayList([]i64) = .empty;
        defer lists.deinit(a);
        defer for (lists.items) |xs| a.free(xs);
        for (0..size) |j| {
            const xs = try a.alloc(i64, 4);
            for (xs, 0..) |*v, k| v.* = seed + batch + @as(i64, @intCast(j)) + @as(i64, @intCast(k));
            try lists.append(a, xs);
        }
        for (lists.items) |xs| {
            for (xs) |v| sum += v;
        }
        return sum;
    }
    if (kind == 10) {
        const snapshot = try a.alloc([]i64, size);
        defer a.free(snapshot);
        for (input.nested, 0..) |xs, j| snapshot[j] = try a.dupe(i64, xs);
        defer for (snapshot) |xs| a.free(xs);
        const index: usize = @intCast(@mod(seed + batch * 17, n));
        input.nested[index][1] = @mod(input.nested[index][1] + batch + 1, 1000003);
        return snapshot[index][1] + input.nested[index][1];
    }
    if (kind == 11) {
        const xs = try a.alloc(i64, size);
        defer a.free(xs);
        for (xs, 0..) |*v, j| v.* = @mod(seed + batch + @as(i64, @intCast(j)) * 13, 1009);
        std.mem.sort(i64, xs, {}, lessInt);
        return fold(xs);
    }
    if (kind == 12) {
        const rows = try a.alloc(Row, size);
        defer a.free(rows);
        for (rows, 0..) |*row, j| {
            const v = @mod(seed + batch + @as(i64, @intCast(j)) * 13, 1009);
            row.* = .{ .key = @mod(v, 17), .ordinal = @intCast(j), .value = v };
        }
        std.mem.sort(Row, rows, {}, lessRow);
        for (rows, 0..) |row, j| sum += (@as(i64, @intCast(j)) + 1) * (row.value * 17 + row.ordinal);
        return sum;
    }
    if (kind == 13) return execute(input.program, size, seed + batch);
    return error.UnknownCase;
}
fn run(argc: c_int, argv: [*][*:0]const u8) !c_int {
    if (argc != 5) return 2;
    const kind = std.mem.span(argv[1]);
    var case_id: usize = 14;
    const names = [_][]const u8{ "list_scan", "list_append", "list_filter", "dict_lookup", "dict_lookup_str", "dict_update", "dict_update_str", "set_dedup", "alloc_short", "alloc_retained", "mutate_nested", "sort_int", "sort_records", "lox_eval" };
    for (names, 0..) |name, id| {
        if (std.mem.eql(u8, name, kind)) case_id = id;
    }
    if (case_id == 14) return 2;
    const size = try std.fmt.parseInt(usize, std.mem.span(argv[2]), 10);
    const iterations = try std.fmt.parseInt(i64, std.mem.span(argv[3]), 10);
    const seed = try std.fmt.parseInt(i64, std.mem.span(argv[4]), 10);
    if (size < 2 or iterations < 1 or seed < 1 or seed > 1000000) return 2;
    const values = try a.alloc(i64, size);
    defer a.free(values);
    for (values, 0..) |*v, j| v.* = @mod(seed + @as(i64, @intCast(j)) * 13, 1009);
    const string = std.mem.eql(u8, kind, "dict_lookup_str") or std.mem.eql(u8, kind, "dict_update_str");
    const keys = try a.alloc([]u8, if (string) size * 2 else 0);
    defer a.free(keys);
    for (keys, 0..) |*key, j| key.* = try std.fmt.allocPrint(a, "{d}", .{j});
    defer for (keys) |key| a.free(key);
    var lookup = std.AutoHashMap(i64, i64).init(a);
    defer lookup.deinit();
    var lookup_str = std.StringHashMap(i64).init(a);
    defer lookup_str.deinit();
    for (values, 0..) |v, j| {
        if (std.mem.eql(u8, kind, "dict_lookup")) try lookup.put(@intCast(j), v);
        if (std.mem.eql(u8, kind, "dict_lookup_str")) try lookup_str.put(keys[j], v);
    }
    const nested = try a.alloc([]i64, if (std.mem.eql(u8, kind, "mutate_nested")) size else 0);
    defer a.free(nested);
    for (nested, 0..) |*xs, j| {
        xs.* = try a.alloc(i64, 4);
        for (xs.*, 0..) |*v, k| v.* = @mod(seed + @as(i64, @intCast(j)) * 13 + @as(i64, @intCast(k)), 1009);
    }
    defer for (nested) |xs| a.free(xs);
    const program = try a.dupe(Instruction, &program_fixture);
    defer a.free(program);
    var input = Inputs{ .size = size, .seed = seed, .values = values, .keys = keys, .lookup = lookup, .lookup_str = lookup_str, .nested = nested, .program = program };
    var checksum: i64 = 0;
    const start = now();
    var batch: i64 = 0;
    while (batch < iterations) : (batch += 1) checksum = @mod(checksum + try batchResult(case_id, batch, &input), MOD);
    const elapsed = now() - start;
    if (std.mem.eql(u8, kind, "mutate_nested")) {
        for (nested) |xs| {
            for (xs) |v| checksum = @mod(checksum + v, MOD);
        }
    }
    _ = printf("%lld %lld\n", @as(c_longlong, checksum), @as(c_longlong, elapsed));
    return 0;
}
/// Runs the collection or fixed-bytecode execution benchmark selected by argv.
pub export fn main(argc: c_int, argv: [*][*:0]const u8) c_int {
    return run(argc, argv) catch 1;
}
