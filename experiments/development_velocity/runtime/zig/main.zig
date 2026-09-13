//! Frozen bounded-json-batch-v1 transport. Task behavior lives in app.zig.
const std = @import("std");
const app = @import("app.zig");

const A = std.mem.Allocator;
const V = std.json.Value;
const max_input = 1024 * 1024;

fn failure(a: A, name: []const u8) !V {
    var result: V = .{ .object = .{} };
    try result.object.put(a, "error", .{ .string = name });
    return result;
}

fn validDepth(input: []const u8) bool {
    var depth: usize = 0;
    var string = false;
    var escaped = false;
    for (input) |c| {
        if (string) {
            if (escaped) escaped = false else if (c == '\\') escaped = true else if (c == '"') string = false;
        } else switch (c) {
            '"' => string = true,
            '[', '{' => { depth += 1; if (depth > 32) return false; },
            ']', '}' => { if (depth == 0) return false; depth -= 1; },
            else => {},
        }
    }
    return true;
}

fn validNumbers(a: A, root: V) !bool {
    var pending: std.ArrayList(V) = .empty;
    defer pending.deinit(a);
    try pending.append(a, root);
    while (pending.pop()) |value| switch (value) {
        .number_string => |s| {
            if (std.mem.indexOfAny(u8, s, ".eE") == null) {
                _ = std.fmt.parseInt(i64, s, 10) catch return false;
            } else {
                const n = std.fmt.parseFloat(f64, s) catch return false;
                if (!std.math.isFinite(n)) return false;
            }
        },
        .array => |items| try pending.appendSlice(a, items.items),
        .object => |fields| try pending.appendSlice(a, fields.values()),
        else => {},
    };
    return true;
}

fn respond(a: A, input: []const u8) !V {
    if (input.len > max_input or !std.unicode.utf8ValidateSlice(input) or !validDepth(input))
        return failure(a, "invalid-envelope");
    const parsed = std.json.parseFromSlice(V, a, input, .{
        .parse_numbers = false,
        .duplicate_field_behavior = .@"error",
    }) catch return failure(a, "invalid-envelope");
    if (!try validNumbers(a, parsed.value)) return failure(a, "invalid-envelope");
    const root = parsed.value;
    if (root != .object or root.object.count() != 1 or !root.object.contains("requests"))
        return failure(a, "invalid-envelope");
    const requests = root.object.get("requests").?;
    if (requests != .array or requests.array.items.len > 64)
        return failure(a, "invalid-envelope");
    var results: V = .{ .array = std.json.Array.init(a) };
    for (requests.array.items) |request| {
        const value = app.run(a, request) catch try failure(a, "invalid-request");
        try results.array.append(value);
    }
    var result: V = .{ .object = .{} };
    try result.object.put(a, "results", results);
    return result;
}

pub fn main(init: std.process.Init) !void {
    const a = init.arena.allocator();
    var buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const input = reader.interface.allocRemaining(a, .limited(max_input + 1)) catch |err| switch (err) {
        error.StreamTooLong => {
            try std.Io.File.stdout().writeStreamingAll(init.io, "{\"error\":\"invalid-envelope\"}\n");
            return;
        },
        else => return err,
    };
    const output = try std.json.Stringify.valueAlloc(a, try respond(a, input), .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

test "transport accepts an empty batch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const value = try respond(a, "{\"requests\":[]}");
    try std.testing.expectEqual(@as(usize, 0), value.object.get("results").?.array.items.len);
}

test "transport rejects duplicate keys and excess nesting" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var duplicate = try respond(a, "{\"requests\":[],\"requests\":[]}");
    try std.testing.expectEqualStrings("invalid-envelope", duplicate.object.get("error").?.string);
    var deep: std.ArrayList(u8) = .empty;
    defer deep.deinit(a);
    try deep.appendSlice(a, "{\"requests\":[");
    try deep.appendNTimes(a, '[', 32);
    try deep.appendNTimes(a, ']', 32);
    try deep.appendSlice(a, "]}");
    var rejected = try respond(a, deep.items);
    try std.testing.expectEqualStrings("invalid-envelope", rejected.object.get("error").?.string);
}
