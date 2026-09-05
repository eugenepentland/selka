const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const discovery = language.duplicates;
const source = "fn a(x: i64) -> i64 { return x * 2 + 1; } fn copy(y: i64) -> i64 { return y * 2 + 1; } fn b(x: i64) -> i64 { return x * 2 + 3; } fn main() -> i64 { return 0; }";

test "approximate discovery reports literal drift once per exact-group representative" {
    var c = try language.Compilation.init(t.allocator, "near.my", source);
    defer c.deinit();
    try c.check();
    var result = try discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .min_nodes = 1 });
    defer result.deinit();
    try t.expectEqual(@as(usize, 1), result.groups.len);
    try t.expectEqual(@as(usize, 1), result.approximate.pairs.len);
    const pair = result.approximate.pairs[0];
    try t.expectEqual(@as(usize, 1), pair.distance);
    try t.expectEqualStrings("1", pair.changes[0].before.?);
    try t.expectEqualStrings("3", pair.changes[0].after.?);
    try t.expect(!result.approximate.truncated);
    try t.expect(c.code == null);
    const first = try discovery.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(first);
    const second = try discovery.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(second);
    try t.expectEqualStrings(first, second);
    try t.expect(std.mem.indexOf(u8, first, "not semantic equivalence") != null);
    var exact = try discovery.discover(t.allocator, c.program.?, .{ .min_nodes = 1 });
    defer exact.deinit();
    try t.expectEqual(@as(usize, 0), exact.approximate.pairs.len);
    try t.expectEqual(@as(usize, 0), exact.approximate.work);
}
test "near reports explain changed operators and resolved callees" {
    for ([_][]const u8{
        "fn a(x: i64) -> i64 { return x * 2 + 1; } fn b(x: i64) -> i64 { return x * 2 - 1; } fn main() -> i64 { return 0; }",
        "fn left(x: i64) -> i64 { return x; } fn right(x: i64) -> i64 { return x; } fn a(x: i64) -> i64 { return left(x) * 2; } fn b(x: i64) -> i64 { return right(x) * 2; } fn main() -> i64 { return 0; }",
    }, [_][]const u8{ "sub", "callee 5:right" }) |text, expected| {
        var c = try language.Compilation.init(t.allocator, "near.my", text);
        defer c.deinit();
        try c.check();
        var result = try discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .min_nodes = 1 });
        defer result.deinit();
        const rendered = try discovery.render(t.allocator, result, c.program.?, c.src);
        defer t.allocator.free(rendered);
        try t.expect(std.mem.indexOf(u8, rendered, expected) != null);
        try t.expect(result.approximate.pairs.len != 0);
    }
}
test "near search retains signature effect and nominal boundaries and excludes unrelated bodies" {
    const text = "domain D: i64 {} fn a(x: i64) -> i64 { return x * 2 + 1; } fn b(x: i64) -> i64 effects() { return x * 2 + 3; } fn c(x: bool) -> bool { return !x; } fn d(x: D) -> D { return x; } fn e(x: i64) -> i64 { if x > 0 { return x; } return 0; } fn main() -> i64 { return 0; }";
    var c = try language.Compilation.init(t.allocator, "near.my", text);
    defer c.deinit();
    try c.check();
    var result = try discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .min_nodes = 1 });
    defer result.deinit();
    try t.expectEqual(@as(usize, 0), result.approximate.pairs.len);
}
test "line edit alignment describes inserted statements without relabeling them exact" {
    const text = "fn a(x: i64) -> i64 { return x * 2 + 1; } fn b(x: i64) -> i64 { discard x; return x * 2 + 1; } fn main() -> i64 { return 0; }";
    var c = try language.Compilation.init(t.allocator, "near.my", text);
    defer c.deinit();
    try c.check();
    var result = try discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .min_nodes = 1, .near_options = .{ .similarity_percent = 70 } });
    defer result.deinit();
    try t.expectEqual(@as(usize, 0), result.groups.len);
    try t.expectEqual(@as(usize, 1), result.approximate.pairs.len);
    var saw_insertion = false;
    for (result.approximate.pairs[0].changes) |change| if (change.before == null) {
        saw_insertion = true;
    };
    try t.expect(saw_insertion);
}
test "bounded near discovery explicitly reports incomplete work and validates budgets" {
    var c = try language.Compilation.init(t.allocator, "near.my", source);
    defer c.deinit();
    try c.check();
    var result = try discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .min_nodes = 1, .near_options = .{ .max_work = 1 } });
    defer result.deinit();
    try t.expect(result.approximate.truncated);
    try t.expect(result.approximate.work <= 1);
    const rendered = try discovery.render(t.allocator, result, c.program.?, c.src);
    defer t.allocator.free(rendered);
    try t.expect(std.mem.indexOf(u8, rendered, "Incomplete approximate search") != null);
    for ([_]discovery.near.Options{ .{ .max_work = 0 }, .{ .max_pairs = 0 }, .{ .similarity_percent = 100 }, .{ .similarity_percent = 0 } }) |options| {
        try t.expectError(error.InvalidThreshold, discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .near_options = options }));
    }
}
fn allocationScenario(allocator: std.mem.Allocator, c: *language.Compilation) !void {
    var result = try discovery.discover(allocator, c.program.?, .{ .approximate = true, .min_nodes = 1 });
    defer result.deinit();
    const rendered = try discovery.render(allocator, result, c.program.?, c.src);
    defer allocator.free(rendered);
    try t.expectEqual(@as(usize, 1), result.approximate.pairs.len);
}
test "near comparison matrix output and rendering release every failed allocation" {
    var c = try language.Compilation.init(t.allocator, "near.my", source);
    defer c.deinit();
    try c.check();
    var no_resize = t.FailingAllocator.init(t.allocator, .{ .resize_fail_index = 0 });
    try t.checkAllAllocationFailures(no_resize.allocator(), allocationScenario, .{&c});
}

test "near pair limits bound repeated drift reports while exact groups remain complete" {
    const text = source ++ " fn more(x: i64) -> i64 { return x * 2 + 5; }";
    var c = try language.Compilation.init(t.allocator, "near.my", text);
    defer c.deinit();
    try c.check();
    var result = try discovery.discover(t.allocator, c.program.?, .{ .approximate = true, .min_nodes = 1, .near_options = .{ .max_pairs = 1 } });
    defer result.deinit();
    try t.expectEqual(@as(usize, 1), result.groups.len);
    try t.expectEqual(@as(usize, 1), result.approximate.pairs.len);
    try t.expect(result.approximate.truncated);
    try t.expect(result.approximate.work <= result.options.near_options.max_work);
}

const near = discovery.near;
fn indexedInput(allocator: std.mem.Allocator, id: usize, header: usize) !near.Input {
    return .{ .function = @fromBackingInt(id), .bytes = try std.fmt.allocPrint(allocator, "signature {d}\nstmt block\na\nb\nc\nd\ne\nf\ng\nh\n{d}\n", .{ header, id }) };
}
test "header index retains source pair order across interleaved buckets" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var inputs: [5]near.Input = undefined;
    for (&inputs, [_]usize{ 0, 1, 0, 1, 0 }, 0..) |*input, header, id| input.* = try indexedInput(allocator, id, header);
    const result = try near.discover(allocator, t.allocator, &inputs, .{});
    try t.expect(!result.truncated);
    try t.expectEqual(@as(usize, 4), result.pairs.len);
    for (result.pairs, [_][2]usize{ .{ 0, 2 }, .{ 0, 4 }, .{ 1, 3 }, .{ 2, 4 } }) |pair, expected| {
        try t.expectEqual(expected[0], @backingInt(pair.left));
        try t.expectEqual(expected[1], @backingInt(pair.right));
        try t.expectEqual(@as(usize, 1), pair.distance);
    }
    const limited = try near.discover(allocator, t.allocator, &inputs, .{ .max_pairs = 2 });
    try t.expect(limited.truncated);
    try t.expectEqual(@as(usize, 2), limited.pairs.len);
    try t.expectEqual(@as(usize, 4), @backingInt(limited.pairs[1].right));
}
test "header index discovers distant compatible functions within a subquadratic budget" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const inputs = try allocator.alloc(near.Input, 1024);
    for (inputs, 0..) |*input, id| input.* = try indexedInput(allocator, id, if (id == inputs.len - 1) 0 else id);
    const result = try near.discover(allocator, t.allocator, inputs, .{ .max_work = 250_000 });
    try t.expect(!result.truncated);
    try t.expect(result.work < 250_000);
    try t.expectEqual(@as(usize, 1), result.pairs.len);
    try t.expectEqual(@as(usize, 0), @backingInt(result.pairs[0].left));
    try t.expectEqual(@as(usize, 1023), @backingInt(result.pairs[0].right));
    const short = try near.discover(allocator, t.allocator, inputs, .{ .max_work = 2000 });
    try t.expect(short.truncated);
    try t.expect(short.work <= 2000);
    try t.expectEqual(@as(usize, 0), short.pairs.len);
}

// A deliberately full, small matrix is the independent oracle for the bounded
// representation. Exhaust all short binary sequences, including unequal lengths.
fn compareWithFullMatrix(left: []const []const u8, right: []const []const u8, percent: u8) !void {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var inputs: [2]near.Input = undefined;
    for ([_][]const []const u8{ left, right }, &inputs, 0..) |lines, *input, id| {
        const bytes = try std.mem.join(allocator, "\n", lines);
        input.* = .{ .function = @fromBackingInt(id), .bytes = bytes };
    }
    var full: [6][6]usize = undefined;
    for (0..left.len + 1) |r| full[r][0] = r;
    for (0..right.len + 1) |c| full[0][c] = c;
    for (left, 1..) |a, r| for (right, 1..) |b, c| {
        full[r][c] = @min(full[r - 1][c - 1] + @as(usize, if (std.mem.eql(u8, a, b)) 0 else 1), @min(full[r - 1][c] + 1, full[r][c - 1] + 1));
    };
    const distance = full[left.len][right.len];
    const result = try near.discover(allocator, t.allocator, &inputs, .{ .similarity_percent = percent });
    try t.expect(!result.truncated);
    if (distance == 0 or distance > @max(left.len, right.len) * (100 - @as(usize, percent)) / 100) {
        try t.expectEqual(@as(usize, 0), result.pairs.len);
        return;
    }
    try t.expectEqual(@as(usize, 1), result.pairs.len);
    try t.expectEqual(distance, result.pairs[0].distance);
    var changes: [10]near.Change = undefined;
    var count: usize = 0;
    var r = left.len;
    var c = right.len;
    while (r != 0 or c != 0) {
        if (r > 0 and c > 0 and std.mem.eql(u8, left[r - 1], right[c - 1]) and full[r][c] == full[r - 1][c - 1]) {
            r -= 1;
            c -= 1;
            continue;
        }
        if (r > 0 and c > 0 and full[r][c] == full[r - 1][c - 1] + 1) {
            changes[count] = .{ .before = left[r - 1], .after = right[c - 1] };
            r -= 1;
            c -= 1;
        } else if (r > 0 and full[r][c] == full[r - 1][c] + 1) {
            changes[count] = .{ .before = left[r - 1], .after = null };
            r -= 1;
        } else {
            changes[count] = .{ .before = null, .after = right[c - 1] };
            c -= 1;
        }
        count += 1;
    }
    std.mem.reverse(near.Change, changes[0..count]);
    try t.expectEqualDeep(@as([]const near.Change, changes[0..count]), result.pairs[0].changes);
}
test "banded distance and edit explanations agree with a full matrix over short sequences" {
    for (0..5) |left_length| for (0..5) |right_length| {
        for (0..@as(usize, 1) << @intCast(left_length)) |a| for (0..@as(usize, 1) << @intCast(right_length)) |b| {
            var left: [5][]const u8 = undefined;
            var right: [5][]const u8 = undefined;
            left[0] = "stmt block";
            right[0] = "stmt block";
            for (left[1 .. left_length + 1], 0..) |*line, bit| line.* = if (a & (@as(usize, 1) << @intCast(bit)) == 0) "a" else "b";
            for (right[1 .. right_length + 1], 0..) |*line, bit| line.* = if (b & (@as(usize, 1) << @intCast(bit)) == 0) "a" else "b";
            for ([_]u8{ 1, 50, 80, 90, 99 }) |percent| try compareWithFullMatrix(left[0 .. left_length + 1], right[0 .. right_length + 1], percent);
        };
    };
}
test "banded comparison finds long literal drift within the default work budget" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    var left: [1000][]const u8 = @splat("a");
    left[0] = "stmt block";
    var right = left;
    right[999] = "b";
    const inputs = [_]near.Input{
        .{ .function = @fromBackingInt(0), .bytes = try std.mem.join(allocator, "\n", &left) },
        .{ .function = @fromBackingInt(1), .bytes = try std.mem.join(allocator, "\n", &right) },
    };
    const result = try near.discover(allocator, t.allocator, &inputs, .{});
    try t.expect(!result.truncated);
    try t.expect(result.work < 1_000_000);
    try t.expectEqual(@as(usize, 1), result.pairs.len);
    try t.expectEqual(@as(usize, 1), result.pairs[0].distance);
    try t.expectEqualStrings("a", result.pairs[0].changes[0].before.?);
    try t.expectEqualStrings("b", result.pairs[0].changes[0].after.?);
}
