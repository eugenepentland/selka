//! Bounded, deterministic edit-distance review of checked canonical body lines.
const std = @import("std");
const typed = @import("typed.zig");
pub const version = "near-v3";
pub const Input = struct { function: typed.FunctionId, bytes: []const u8 };
pub const Change = struct { before: ?[]const u8, after: ?[]const u8 };
pub const Pair = struct { left: typed.FunctionId, right: typed.FunctionId, distance: usize, lines: usize, changes: []const Change };
pub const Options = struct { similarity_percent: u8 = 90, max_work: usize = 1_000_000, max_pairs: usize = 100 };
pub const Result = struct { pairs: []const Pair, work: usize, truncated: bool };
const Body = struct { header: []const u8, lines: []const []const u8 };
fn body(allocator: std.mem.Allocator, bytes: []const u8) !Body {
    const start = std.mem.indexOf(u8, bytes, "stmt ") orelse return error.InternalError;
    var lines: std.ArrayList([]const u8) = .empty;
    var split = std.mem.tokenizeScalar(u8, bytes[start..], '\n');
    while (split.next()) |line| try lines.append(allocator, line);
    return .{ .header = bytes[0..start], .lines = try lines.toOwnedSlice(allocator) };
}
// Stable merge sorting bounds header comparisons and preserves declaration order
// within each header bucket. Budget exhaustion abandons the incomplete index.
fn indexHeaders(allocator: std.mem.Allocator, bodies: []const Body, remaining: *usize) !?[]usize {
    if (bodies.len > remaining.*) return null;
    remaining.* -= bodies.len;
    const order = try allocator.alloc(usize, bodies.len);
    defer allocator.free(order);
    const scratch = try allocator.alloc(usize, bodies.len);
    defer allocator.free(scratch);
    const next = try allocator.alloc(usize, bodies.len);
    errdefer allocator.free(next);
    for (order, next, 0..) |*item, *link, i| {
        item.* = i;
        link.* = bodies.len;
    }
    var width: usize = 1;
    while (width < bodies.len) : (width = @min(width *| 2, bodies.len)) {
        var start: usize = 0;
        while (start < bodies.len) {
            const middle = @min(start +| width, bodies.len);
            const end = @min(middle +| width, bodies.len);
            var a = start;
            var b = middle;
            for (start..end) |out| {
                if (remaining.* == 0) {
                    allocator.free(next);
                    return null;
                }
                remaining.* -= 1;
                const take_left = if (a == middle) false else if (b == end) true else blk: {
                    const cost = @max(bodies[order[a]].header.len, bodies[order[b]].header.len) +| 1;
                    if (cost > remaining.*) {
                        allocator.free(next);
                        return null;
                    }
                    remaining.* -= cost;
                    break :blk std.mem.order(u8, bodies[order[a]].header, bodies[order[b]].header) != .gt;
                };
                scratch[out] = if (take_left) order[a] else order[b];
                if (take_left) a += 1 else b += 1;
            }
            start = end;
        }
        if (bodies.len > remaining.*) {
            allocator.free(next);
            return null;
        }
        remaining.* -= bodies.len;
        @memcpy(order, scratch);
    }
    for (order[0..if (order.len == 0) 0 else order.len - 1], 0..) |left, position| {
        const right = order[position + 1];
        const cost = @max(bodies[left].header.len, bodies[right].header.len) +| 1;
        if (cost > remaining.*) {
            allocator.free(next);
            return null;
        }
        remaining.* -= cost;
        if (std.mem.eql(u8, bodies[left].header, bodies[right].header)) next[left] = right;
    }
    return next;
}
// An accepted alignment cannot leave the allowance-wide diagonal band: reaching
// an offset of k requires at least k insertions/deletions. Keep the band for exact
// traceback; values outside it are above the acceptance threshold.
const Matrix = struct {
    cells: []usize,
    width: usize,
    allowance: usize,
    columns: usize,
    fn start(self: Matrix, row: usize) usize {
        return row -| self.allowance;
    }
    fn get(self: Matrix, row: usize, column: usize) usize {
        if (column >= self.columns or column < self.start(row) or column > row +| self.allowance) return self.allowance + 1;
        return self.cells[row * self.width + column - self.start(row)];
    }
    fn set(self: Matrix, row: usize, column: usize, value: usize) void {
        self.cells[row * self.width + column - self.start(row)] = @min(value, self.allowance + 1);
    }
};
/// Output storage belongs to output_allocator; pairwise matrices are freed promptly.
/// Inputs are representatives of exact groups, in first-declaration order.
pub fn discover(output_allocator: std.mem.Allocator, temporary: std.mem.Allocator, inputs: []const Input, options: Options) !Result {
    if (options.similarity_percent == 0 or options.similarity_percent >= 100 or options.max_work == 0 or options.max_pairs == 0) return error.InvalidThreshold;
    const bodies = try output_allocator.alloc(Body, inputs.len);
    for (inputs, bodies) |input, *parsed| parsed.* = try body(output_allocator, input.bytes);
    var pairs: std.ArrayList(Pair) = .empty;
    var remaining = options.max_work;
    var truncated = false;
    const next = try indexHeaders(temporary, bodies, &remaining) orelse return .{ .pairs = &.{}, .work = options.max_work - remaining, .truncated = true };
    defer temporary.free(next);
    outer: for (bodies, 0..) |left, i| {
        var j = next[i];
        while (j < bodies.len) : (j = next[j]) {
            const right = bodies[j];
            // Header identity is established by the index. Charge candidate visits.
            if (remaining == 0 or pairs.items.len == options.max_pairs) {
                truncated = true;
                break :outer;
            }
            remaining -= 1;
            const longest = @max(left.lines.len, right.lines.len);
            const allowance = longest / 100 * (100 - options.similarity_percent) + longest % 100 * (100 - options.similarity_percent) / 100;
            if (longest - @min(left.lines.len, right.lines.len) > allowance) continue;
            // Charge compared line bytes as well as matrix cells. This bounds long
            // literal/callee lines, not only short-token dynamic programming work.
            var left_bytes: usize = 0;
            var right_bytes: usize = 0;
            for (left.lines) |line| left_bytes +|= line.len;
            for (right.lines) |line| right_bytes +|= line.len;
            const rows = left.lines.len +| 1;
            const cols = right.lines.len +| 1;
            const band = allowance *| 2 +| 1;
            const width = @min(cols, band);
            const cells = rows *| width;
            const cost = cells +| left_bytes *| @min(right.lines.len, band) +| right_bytes *| @min(left.lines.len, band);
            if (cost > remaining) {
                truncated = true;
                break :outer;
            }
            remaining -= cost;
            const storage = try temporary.alloc(usize, cells);
            defer temporary.free(storage);
            @memset(storage, allowance + 1);
            const matrix: Matrix = .{ .cells = storage, .width = width, .allowance = allowance, .columns = cols };
            for (0..rows) |r| {
                const end = @min(cols, r +| allowance +| 1);
                for (matrix.start(r)..end) |c| {
                    if (r == 0) {
                        matrix.set(r, c, c);
                    } else if (c == 0) {
                        matrix.set(r, c, r);
                    } else {
                        const substitution: usize = if (std.mem.eql(u8, left.lines[r - 1], right.lines[c - 1])) 0 else 1;
                        matrix.set(r, c, @min(matrix.get(r - 1, c - 1) + substitution, @min(matrix.get(r - 1, c) + 1, matrix.get(r, c - 1) + 1)));
                    }
                }
            }
            const distance = matrix.get(left.lines.len, right.lines.len);
            if (distance == 0 or distance > allowance) continue;
            var changes: std.ArrayList(Change) = .empty;
            var r = left.lines.len;
            var c = right.lines.len;
            while (r != 0 or c != 0) {
                const current = matrix.get(r, c);
                if (r != 0 and c != 0 and std.mem.eql(u8, left.lines[r - 1], right.lines[c - 1]) and current == matrix.get(r - 1, c - 1)) {
                    r -= 1;
                    c -= 1;
                } else if (r != 0 and c != 0 and current == matrix.get(r - 1, c - 1) + 1) {
                    try changes.append(output_allocator, .{ .before = left.lines[r - 1], .after = right.lines[c - 1] });
                    r -= 1;
                    c -= 1;
                } else if (r != 0 and current == matrix.get(r - 1, c) + 1) {
                    try changes.append(output_allocator, .{ .before = left.lines[r - 1], .after = null });
                    r -= 1;
                } else {
                    try changes.append(output_allocator, .{ .before = null, .after = right.lines[c - 1] });
                    c -= 1;
                }
            }
            std.mem.reverse(Change, changes.items);
            try pairs.append(output_allocator, .{ .left = inputs[i].function, .right = inputs[j].function, .distance = distance, .lines = longest, .changes = try changes.toOwnedSlice(output_allocator) });
        }
    }
    return .{ .pairs = try pairs.toOwnedSlice(output_allocator), .work = options.max_work - remaining, .truncated = truncated };
}
