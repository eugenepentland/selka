//! Bounded, deterministic edit-distance review of checked canonical body lines.
const std = @import("std");
const typed = @import("typed.zig");
pub const version = "near-v1";
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
/// Output storage belongs to output_allocator; pairwise matrices are freed promptly.
/// Inputs are representatives of exact groups, in first-declaration order.
pub fn discover(output_allocator: std.mem.Allocator, temporary: std.mem.Allocator, inputs: []const Input, options: Options) !Result {
    if (options.similarity_percent == 0 or options.similarity_percent >= 100 or options.max_work == 0 or options.max_pairs == 0) return error.InvalidThreshold;
    const bodies = try output_allocator.alloc(Body, inputs.len);
    for (inputs, bodies) |input, *parsed| parsed.* = try body(output_allocator, input.bytes);
    var pairs: std.ArrayList(Pair) = .empty;
    var remaining = options.max_work;
    var truncated = false;
    outer: for (bodies, 0..) |left, i| {
        for (bodies[i + 1 ..], i + 1..) |right, j| {
            // Charge header comparison bytes and pair enumeration, including rejects.
            const header_cost = @max(left.header.len, right.header.len) +| 1;
            if (remaining < header_cost or pairs.items.len == options.max_pairs) {
                truncated = true;
                break :outer;
            }
            remaining -= header_cost;
            if (!std.mem.eql(u8, left.header, right.header)) continue;
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
            const cells = rows *| cols;
            const cost = cells +| left_bytes *| right.lines.len +| right_bytes *| left.lines.len;
            if (cost > remaining) {
                truncated = true;
                break :outer;
            }
            remaining -= cost;
            const matrix = try temporary.alloc(usize, cells);
            defer temporary.free(matrix);
            for (0..rows) |r| matrix[r * cols] = r;
            for (0..cols) |c| matrix[c] = c;
            for (left.lines, 1..) |a, r| {
                for (right.lines, 1..) |b, c| {
                    const substitution: usize = if (std.mem.eql(u8, a, b)) 0 else 1;
                    matrix[r * cols + c] = @min(matrix[(r - 1) * cols + c - 1] + substitution, @min(matrix[(r - 1) * cols + c] + 1, matrix[r * cols + c - 1] + 1));
                }
            }
            const distance = matrix[cells - 1];
            if (distance == 0 or distance > allowance) continue;
            var changes: std.ArrayList(Change) = .empty;
            var r = left.lines.len;
            var c = right.lines.len;
            while (r != 0 or c != 0) {
                const current = matrix[r * cols + c];
                if (r != 0 and c != 0 and std.mem.eql(u8, left.lines[r - 1], right.lines[c - 1]) and current == matrix[(r - 1) * cols + c - 1]) {
                    r -= 1;
                    c -= 1;
                } else if (r != 0 and c != 0 and current == matrix[(r - 1) * cols + c - 1] + 1) {
                    try changes.append(output_allocator, .{ .before = left.lines[r - 1], .after = right.lines[c - 1] });
                    r -= 1;
                    c -= 1;
                } else if (r != 0 and current == matrix[(r - 1) * cols + c] + 1) {
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
