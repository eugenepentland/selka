//! Bounded JSON workflow planning with deterministic graph validation and scheduling.
//! Responses share the caller arena until encoding finishes.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Value = std.json.Value;
const max_input = 1024 * 1024;
const max_jobs = 128;
const invalid_request = "invalid-request";
const invalid_manifest = "invalid-manifest";

/// Reads one request and emits its complete response on standard output.
pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    var buffer: [8192]u8 = undefined;
    var reader = std.Io.File.stdin().readerStreaming(init.io, &buffer);
    const input = reader.interface.allocRemaining(arena, .limited(max_input + 1)) catch |err| switch (err) {
        error.StreamTooLong => {
            try std.Io.File.stdout().writeStreamingAll(init.io, "{\"error\":\"invalid-request\"}\n");
            return;
        },
        else => return err,
    };
    const result = try respond(arena, input);
    const output = try std.json.Stringify.valueAlloc(arena, result, .{});
    try std.Io.File.stdout().writeStreamingAll(init.io, output);
    try std.Io.File.stdout().writeStreamingAll(init.io, "\n");
}

fn object() Value {
    return .{ .object = .{} };
}
fn array(a: Allocator) Value {
    return .{ .array = std.json.Array.init(a) };
}
fn put(a: Allocator, obj: *Value, key: []const u8, value: Value) !void {
    try obj.object.put(a, key, value);
}
fn failure(a: Allocator, name: []const u8) !Value {
    var result = object();
    try put(a, &result, "error", .{ .string = name });
    return result;
}

/// Checks every number before schema validation, including numbers in unknown
/// fields. An explicit stack avoids recursion on adversarial nested JSON.
fn validNumbers(a: Allocator, root: Value) !bool {
    var pending: std.ArrayList(Value) = .empty;
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

// Count only structural containers; escaped quotes and string contents do not
// affect nesting. The JSON parser subsequently validates matching delimiters.
fn validDepth(input: []const u8) bool {
    var depth: usize = 0;
    var in_string = false;
    var escaped = false;
    for (input) |c| {
        if (in_string) {
            if (escaped) {
                escaped = false;
            } else if (c == '\\') {
                escaped = true;
            } else if (c == '"') {
                in_string = false;
            }
        } else switch (c) {
            '"' => in_string = true,
            '[', '{' => {
                depth += 1;
                if (depth > 64) return false;
            },
            ']', '}' => {
                if (depth == 0) return false;
                depth -= 1;
            },
            else => {},
        }
    }
    return true;
}

/// The caller owns an arena whose lifetime includes response encoding.
pub fn respond(a: Allocator, input: []const u8) Allocator.Error!Value {
    if (input.len > max_input) return failure(a, invalid_request);
    if (!std.unicode.utf8ValidateSlice(input)) return failure(a, invalid_request);
    if (!validDepth(input)) return failure(a, invalid_request);
    // Keep number lexemes so 1.0 never becomes an integer, and overflowing
    // integers cannot silently become imprecise floating point values.
    const parsed = std.json.parseFromSlice(Value, a, input, .{
        .parse_numbers = false,
        .duplicate_field_behavior = .@"error",
        .allocate = .alloc_always,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return failure(a, invalid_request),
    };
    // Output identifiers borrow parsed strings, so parsing shares the caller's
    // request arena and remains alive until the response has been encoded.
    const root = parsed.value;
    if (!try validNumbers(a, root)) return failure(a, invalid_request);
    if (root != .object or root.object.count() != 1) return failure(a, invalid_request);
    const cases = root.object.get("cases") orelse return failure(a, invalid_request);
    if (cases != .array or cases.array.items.len > 64) return failure(a, invalid_request);
    var results = array(a);
    for (cases.array.items) |manifest| try results.array.append(try plan(a, manifest));
    var response = object();
    try put(a, &response, "results", results);
    return response;
}

const Job = struct {
    id: []const u8,
    duration: i64,
    needs: []const Value,
};
fn identifier(v: Value) bool {
    if (v != .string) return false;
    const id = v.string;
    if (id.len == 0 or id.len > 32 or id[0] < 'a' or id[0] > 'z') return false;
    for (id[1..]) |c| {
        const letter = c >= 'a' and c <= 'z';
        const digit = c >= '0' and c <= '9';
        const separator = c == '_' or c == '-';
        const alphanumeric = letter or digit;
        if (!alphanumeric and !separator) return false;
    }
    return true;
}
fn integer(v: Value) ?i64 {
    if (v != .number_string or std.mem.indexOfAny(u8, v.number_string, ".eE") != null) return null;
    return std.fmt.parseInt(i64, v.number_string, 10) catch null;
}
fn lessJob(_: void, lhs: Job, rhs: Job) bool {
    return std.mem.lessThan(u8, lhs.id, rhs.id);
}
fn lessString(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
fn equal(lhs: []const u8, rhs: []const u8) bool {
    return std.mem.eql(u8, lhs, rhs);
}
fn namedFailure(a: Allocator, name: []const u8, field: []const u8, names: [][]const u8) !Value {
    std.mem.sort([]const u8, names, {}, lessString);
    var values = array(a);
    for (names, 0..) |id, i| {
        if (i == 0 or !equal(id, names[i - 1])) try values.array.append(.{ .string = id });
    }
    var result = try failure(a, name);
    try put(a, &result, field, values);
    return result;
}
fn findJob(jobs: []const Job, id: []const u8) ?usize {
    for (jobs, 0..) |job, i| if (equal(job.id, id)) return i;
    return null;
}

fn plan(a: Allocator, manifest: Value) !Value {
    if (manifest != .object or manifest.object.count() != 2) return failure(a, invalid_manifest);
    const version = manifest.object.get("version") orelse return failure(a, invalid_manifest);
    if ((integer(version) orelse return failure(a, invalid_manifest)) != 1) return failure(a, invalid_manifest);
    const raw = manifest.object.get("jobs") orelse return failure(a, invalid_manifest);
    if (raw != .array or raw.array.items.len > max_jobs) return failure(a, invalid_manifest);
    const jobs = try a.alloc(Job, raw.array.items.len);
    for (raw.array.items, jobs) |v, *job| {
        if (v != .object or v.object.count() != 3) return failure(a, invalid_manifest);
        const id = v.object.get("id") orelse return failure(a, invalid_manifest);
        const duration = v.object.get("duration") orelse return failure(a, invalid_manifest);
        const needs = v.object.get("needs") orelse return failure(a, invalid_manifest);
        const d = integer(duration) orelse return failure(a, invalid_manifest);
        if (!identifier(id)) return failure(a, invalid_manifest);
        if (d < 0 or d > 1000000 or needs != .array) return failure(a, invalid_manifest);
        if (needs.array.items.len > max_jobs) return failure(a, invalid_manifest);
        for (needs.array.items) |need| if (!identifier(need)) return failure(a, invalid_manifest);
        job.* = .{ .id = id.string, .duration = d, .needs = needs.array.items };
    }
    std.mem.sort(Job, jobs, {}, lessJob);
    var names: std.ArrayList([]const u8) = .empty;
    for (jobs, 0..) |job, i| {
        if (i > 0 and equal(job.id, jobs[i - 1].id)) try names.append(a, job.id);
    }
    if (names.items.len != 0) return namedFailure(a, "duplicate-id", "ids", names.items);
    for (jobs) |job| {
        for (job.needs, 0..) |need, i| {
            var repeated = false;
            for (job.needs[0..i]) |earlier| {
                if (equal(need.string, earlier.string)) repeated = true;
            }
            if (repeated) {
                try names.append(a, job.id);
                break;
            }
        }
    }
    if (names.items.len != 0) return namedFailure(a, "duplicate-dependency", "jobs", names.items);
    for (jobs) |job| {
        for (job.needs) |need| {
            if (findJob(jobs, need.string) == null) try names.append(a, need.string);
        }
    }
    if (names.items.len != 0) return namedFailure(a, "unknown-dependency", "ids", names.items);
    return schedule(a, jobs);
}

const Graph = struct {
    prerequisites: [max_jobs][max_jobs]bool = @splat(@splat(false)),
    count: usize,

    fn ready(self: *const Graph, index: usize, removed: []const bool) bool {
        if (removed[index]) return false;
        for (0..self.count) |dep| {
            if (self.prerequisites[index][dep] and !removed[dep]) return false;
        }
        return true;
    }
};

fn schedule(a: Allocator, jobs: []const Job) !Value {
    var graph: Graph = .{ .count = jobs.len };
    for (jobs, 0..) |job, i| {
        for (job.needs) |need| graph.prerequisites[i][findJob(jobs, need.string).?] = true;
    }
    var removed: [max_jobs]bool = @splat(false);
    var starts: [max_jobs]i64 = @splat(0);
    var finishes: [max_jobs]i64 = @splat(0);
    var order = array(a);
    var makespan: i64 = 0;
    while (order.array.items.len < jobs.len) {
        var selected: ?usize = null;
        for (0..jobs.len) |i| {
            if (graph.ready(i, &removed)) {
                selected = i;
                break;
            }
        }
        const index = selected orelse {
            var blocked: std.ArrayList([]const u8) = .empty;
            for (jobs, 0..) |job, i| if (!removed[i]) try blocked.append(a, job.id);
            return namedFailure(a, "cycle", "blocked", blocked.items);
        };
        for (0..jobs.len) |dep| {
            if (graph.prerequisites[index][dep]) starts[index] = @max(starts[index], finishes[dep]);
        }
        finishes[index] = starts[index] + jobs[index].duration;
        makespan = @max(makespan, finishes[index]);
        removed[index] = true;
        try order.array.append(.{ .string = jobs[index].id });
    }
    removed = @splat(false);
    var layers = array(a);
    var remaining = jobs.len;
    while (remaining > 0) {
        var layer = array(a);
        var round: [max_jobs]bool = @splat(false);
        for (jobs, 0..) |job, i| {
            if (graph.ready(i, &removed)) {
                round[i] = true;
                try layer.array.append(.{ .string = job.id });
            }
        }
        for (round, 0..) |ready, i| {
            if (ready) {
                removed[i] = true;
                remaining -= 1;
            }
        }
        try layers.array.append(layer);
    }
    var timings = array(a);
    for (jobs, 0..) |job, i| {
        var timing = object();
        try put(a, &timing, "id", .{ .string = job.id });
        try put(a, &timing, "start", .{ .integer = starts[i] });
        try put(a, &timing, "finish", .{ .integer = finishes[i] });
        try timings.array.append(timing);
    }
    var result = object();
    try put(a, &result, "order", order);
    try put(a, &result, "layers", layers);
    try put(a, &result, "timings", timings);
    try put(a, &result, "makespan", .{ .integer = makespan });
    return result;
}

fn expectResponse(backing: Allocator, input: []const u8, expected: []const u8) !void {
    var arena = std.heap.ArenaAllocator.init(backing);
    defer arena.deinit();
    const a = arena.allocator();
    const result = try respond(a, input);
    const actual = try std.json.Stringify.valueAlloc(a, result, .{});
    try std.testing.expectEqualStrings(expected, actual);
}

// spec: Successful result - [PLANNER-ORDER] `order`: a topological order choosing the ASCII-smallest *currently ready* job
// spec: Successful result - [PLANNER-LAYERS] `layers`: synchronous dependency rounds. Each round contains all currently
// spec: Successful result - [PLANNER-TIMINGS] `timings`: one `{"id":ID,"start":N,"finish":N}` per job, sorted by ID.
test "ready order differs from layers and timings follow critical paths" {
    try expectResponse(std.testing.allocator,
        \\{"cases":[{"version":1,"jobs":[{"id":"z","duration":5,"needs":[]},{"id":"b","duration":2,"needs":[]},{"id":"a","duration":3,"needs":["b"]},{"id":"end","duration":0,"needs":["z","a"]}]}]}
    ,
        \\{"results":[{"order":["b","a","z","end"],"layers":[["b","z"],["a"],["end"]],"timings":[{"id":"a","start":2,"finish":5},{"id":"b","start":0,"finish":2},{"id":"end","start":5,"finish":5},{"id":"z","start":0,"finish":5}],"makespan":5}]}
    );
}

// spec: Successful result - [PLANNER-MAKESPAN] `makespan`: maximum finish, or zero for the empty graph.
test "empty graphs and case order" {
    try expectResponse(
        std.testing.allocator,
        "{\"cases\":[{\"version\":1,\"jobs\":[]},false]}",
        "{\"results\":[{\"order\":[],\"layers\":[],\"timings\":[],\"makespan\":0},{\"error\":\"invalid-manifest\"}]}",
    );
    try expectResponse(std.testing.allocator, "{\"cases\":[]}", "{\"results\":[]}");
}

test "global JSON errors override per-manifest errors" {
    const invalid = [_][]const u8{
        "{\"cases\":[],\"cases\":[]}",
        "{\"cases\":[{\"version\":1,\"jobs\":[],\"x\":{\"a\":1,\"\\u0061\":2}}]}",
        "{\"cases\":[null,{\"x\":9223372036854775808}]}",
        "{\"cases\":[{\"x\":-9223372036854775809}]}",
        "{\"cases\":[{\"x\":1e9999}]}",
        "{\"cases\":[NaN]}",
        "{\"cases\":[Infinity]}",
        "{\"cases\":[\"\xff\"]}",
        "{\"cases\":[\"\\ud800\"]}",
        "{\"cases\":[]} true",
        "{\"cases\":[01]}",
        "{\"cases\":[],\"extra\":null}",
        "[]",
    };
    for (invalid) |input| try expectResponse(std.testing.allocator, input, "{\"error\":\"invalid-request\"}");
}

test "schema distinguishes integer lexemes and checks all jobs first" {
    const manifests = [_][]const u8{
        "{\"version\":1.0,\"jobs\":[]}",
        "{\"version\":true,\"jobs\":[]}",
        "{\"version\":1,\"jobs\":[{\"id\":\"a\",\"duration\":1e0,\"needs\":[]}]}",
        "{\"version\":1,\"jobs\":[{\"id\":\"a\",\"duration\":true,\"needs\":[]}]}",
        "{\"version\":1,\"jobs\":[{\"id\":\"A\",\"duration\":0,\"needs\":[]}]}",
        "{\"version\":1,\"jobs\":[{\"id\":\"a\",\"duration\":0,\"needs\":[\"z\",\"z\"]},null]}",
        "{\"version\":1,\"jobs\":[{\"id\":\"a\",\"duration\":-1,\"needs\":[]}]}",
        "{\"version\":1,\"jobs\":[{\"id\":\"a\",\"duration\":1000001,\"needs\":[]}]}",
        "{\"version\":1,\"jobs\":[],\"x\":9223372036854775807}",
    };
    for (manifests) |manifest| {
        const input = try std.fmt.allocPrint(std.testing.allocator, "{{\"cases\":[{s}]}}", .{manifest});
        defer std.testing.allocator.free(input);
        try expectResponse(std.testing.allocator, input, "{\"results\":[{\"error\":\"invalid-manifest\"}]}");
    }
}

test "duplicate ID phase precedes duplicate dependencies" {
    try expectResponse(std.testing.allocator,
        \\{"cases":[{"version":1,"jobs":[{"id":"z","duration":0,"needs":["missing","missing"]},{"id":"a","duration":0,"needs":[]},{"id":"z","duration":0,"needs":[]},{"id":"a","duration":0,"needs":[]},{"id":"a","duration":0,"needs":[]}]}]}
    ,
        \\{"results":[{"error":"duplicate-id","ids":["a","z"]}]}
    );
}

test "duplicate dependency phase precedes missing references and sorts IDs" {
    try expectResponse(std.testing.allocator,
        \\{"cases":[{"version":1,"jobs":[{"id":"z","duration":0,"needs":["x","x","x"]},{"id":"a","duration":0,"needs":["missing"]},{"id":"b","duration":0,"needs":["b","b"]}]}]}
    ,
        \\{"results":[{"error":"duplicate-dependency","jobs":["b","z"]}]}
    );
}

test "unknown references precede cycles and are distinct and sorted" {
    try expectResponse(std.testing.allocator,
        \\{"cases":[{"version":1,"jobs":[{"id":"z","duration":0,"needs":["z","y","a"]},{"id":"b","duration":0,"needs":["y"]}]}]}
    ,
        \\{"results":[{"error":"unknown-dependency","ids":["a","y"]}]}
    );
}

test "cycle reports downstream blocked nodes but excludes removable roots" {
    try expectResponse(std.testing.allocator,
        \\{"cases":[{"version":1,"jobs":[{"id":"tail","duration":1,"needs":["loop"]},{"id":"root","duration":1,"needs":[]},{"id":"loop","duration":1,"needs":["loop","root"]}]}]}
    ,
        \\{"results":[{"error":"cycle","blocked":["loop","tail"]}]}
    );
}

test "size limit applies to all input bytes" {
    const input = try std.testing.allocator.alloc(u8, max_input + 1);
    defer std.testing.allocator.free(input);
    @memset(input, ' ');
    @memcpy(input[0..12], "{\"cases\":[]}");
    try expectResponse(std.testing.allocator, input[0..max_input], "{\"results\":[]}");
    try expectResponse(std.testing.allocator, input, "{\"error\":\"invalid-request\"}");
}

fn maximumChain(a: Allocator) Allocator.Error!Value {
    var raw_jobs = array(a);
    for (0..max_jobs) |offset| {
        const index = max_jobs - 1 - offset;
        var job = object();
        try put(a, &job, "id", .{ .string = try std.fmt.allocPrint(a, "j{d:0>3}", .{index}) });
        try put(a, &job, "duration", .{ .integer = 1000000 });
        var needs = array(a);
        if (index > 0) try needs.array.append(.{ .string = try std.fmt.allocPrint(a, "j{d:0>3}", .{index - 1}) });
        try put(a, &job, "needs", needs);
        try raw_jobs.array.append(job);
    }
    return raw_jobs;
}

test "maximum graph accumulates durations without truncation and ignores input order" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var raw_jobs = try maximumChain(a);
    var manifest = object();
    try put(a, &manifest, "version", .{ .integer = 1 });
    try put(a, &manifest, "jobs", raw_jobs);
    var cases = array(a);
    try cases.array.append(manifest);
    var request = object();
    try put(a, &request, "cases", cases);
    const response = try respond(a, try std.json.Stringify.valueAlloc(a, request, .{}));
    const result = response.object.get("results").?.array.items[0];
    try std.testing.expectEqual(@as(i64, 128000000), result.object.get("makespan").?.integer);
    try std.testing.expectEqual(@as(usize, 128), result.object.get("layers").?.array.items.len);
    const timings = result.object.get("timings").?.array.items;
    for (timings, 0..) |timing, index| {
        try std.testing.expectEqual(@as(i64, @intCast(index * 1000000)), timing.object.get("start").?.integer);
        try std.testing.expectEqual(@as(i64, @intCast((index + 1) * 1000000)), timing.object.get("finish").?.integer);
    }
    try raw_jobs.array.append(raw_jobs.array.items[0]);
    try put(a, &manifest, "jobs", raw_jobs);
    cases.array.items[0] = manifest;
    try put(a, &request, "cases", cases);
    try expectResponse(
        std.testing.allocator,
        try std.json.Stringify.valueAlloc(a, request, .{}),
        "{\"results\":[{\"error\":\"invalid-manifest\"}]}",
    );
}

test "envelope case count boundary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var cases = array(a);
    for (0..64) |_| try cases.array.append(.null);
    var request = object();
    try put(a, &request, "cases", cases);
    const response = try respond(a, try std.json.Stringify.valueAlloc(a, request, .{}));
    try std.testing.expectEqual(@as(usize, 64), response.object.get("results").?.array.items.len);
    try cases.array.append(.null);
    try put(a, &request, "cases", cases);
    try expectResponse(
        std.testing.allocator,
        try std.json.Stringify.valueAlloc(a, request, .{}),
        "{\"error\":\"invalid-request\"}",
    );
}

test "container depth 64 accepted and 65 rejected ignoring string delimiters" {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);
    for ([_]usize{ 62, 63 }) |nested| {
        bytes.clearRetainingCapacity();
        try bytes.appendSlice(std.testing.allocator, "{\"cases\":[");
        try bytes.appendNTimes(std.testing.allocator, '[', nested);
        try bytes.appendSlice(std.testing.allocator, "\"[{}]\\\"[\"");
        try bytes.appendNTimes(std.testing.allocator, ']', nested);
        try bytes.appendSlice(std.testing.allocator, "]}");
        try expectResponse(
            std.testing.allocator,
            bytes.items,
            if (nested == 62) "{\"results\":[{\"error\":\"invalid-manifest\"}]}" else "{\"error\":\"invalid-request\"}",
        );
    }
}

test "request parsing propagates OutOfMemory" {
    var buffer: [0]u8 = .{};
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    try std.testing.expectError(error.OutOfMemory, respond(fixed.allocator(), "{\"cases\":[]}"));
}
