//! Collector text parsers. Incomplete, multiplexed and inconsistent counts fail closed.
const std = @import("std");
const d = @import("data.zig");
const C = d.Context;
const V = d.Value;
fn tokens(c: *C, text: []const u8) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, text, " \t\r");
    while (it.next()) |v| try list.append(c.a, v);
    return list.toOwnedSlice(c.a);
}
fn count(text: []const u8) !f64 {
    const n = try std.fmt.parseInt(u64, std.mem.trim(u8, text, " \t"), 10);
    if (n > 1 << 53) return error.InvalidExperiment;
    return @floatFromInt(n);
}
/// Accept exactly one full-running positive perf event, with no scaling.
pub fn perf(c: *C, text: []const u8, event: []const u8) d.Error!V {
    return perfImpl(c, text, event) catch |err| d.failure(c, err);
}
fn perfImpl(c: *C, text: []const u8, event: []const u8) !V {
    return c.value(.{ .instructions = try perfCount(c, text, event) });
}
fn perfCount(c: *C, text: []const u8, event: []const u8) !f64 {
    var lines = std.mem.splitScalar(u8, text, '\n');
    var found: usize = 0;
    var instructions: f64 = 0;
    while (lines.next()) |line| {
        var fields = std.mem.splitScalar(u8, line, ';');
        const value = fields.next() orelse continue;
        _ = fields.next() orelse continue;
        const name = fields.next() orelse continue;
        if (!std.mem.eql(u8, std.mem.trim(u8, name, " \t"), event)) continue;
        const running_ns = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next() orelse return error.InvalidExperiment, " \t"));
        const fraction = try std.fmt.parseFloat(f64, std.mem.trim(u8, fields.next() orelse return error.InvalidExperiment, " \t"));
        instructions = try count(value);
        const valid_runtime = std.math.isFinite(running_ns) and running_ns > 0;
        if (instructions <= 0 or !valid_runtime or fraction != 100) return c.fail("invalid or multiplexed perf count");
        found += 1;
    }
    if (found != 1) return c.fail("expected exactly one fully counted perf event");
    return instructions;
}
/// Require every grouped runtime event exactly once, positive and fully counted.
pub fn runtime(c: *C, text: []const u8, instruction_event: []const u8) d.Error!V {
    return runtimeImpl(c, text, instruction_event) catch |err| d.failure(c, err);
}
fn runtimeImpl(c: *C, text: []const u8, instruction_event: []const u8) !V {
    const cycles = try std.mem.replaceOwned(u8, c.a, instruction_event, "instructions", "cycles");
    const reference = try std.mem.replaceOwned(u8, c.a, instruction_event, "instructions", "ref-cycles");
    return c.value(.{
        .instructions = try perfCount(c, text, instruction_event),
        .cycles = try perfCount(c, text, cycles),
        .reference_cycles = try perfCount(c, text, reference),
    });
}
fn resolve(c: *C, names: *V, value: []const u8) !V {
    if (value.len < 3 or value[0] != '(' or !std.ascii.isDigit(value[1])) return d.string(value);
    const close = std.mem.indexOfScalar(u8, value, ')') orelse return d.string(value);
    const id = value[1..close];
    _ = try std.fmt.parseInt(u32, id, 10);
    if (close + 1 < value.len) {
        if (value[close + 1] != ' ') return error.InvalidExperiment;
        try d.put(c, names, id, d.string(value[close + 2 ..]));
    }
    return d.req(names.*, id);
}
fn metric(event: []const u8) ?[]const u8 {
    const keys = [_][]const u8{ "Ir", "Dr", "Dw", "Ge" };
    const values = [_][]const u8{ d.key_instructions, "data_reads", "data_writes", "atomics" };
    for (keys, values) |k, v| if (std.mem.eql(u8, k, event)) return v;
    return null;
}
fn metrics(c: *C, events: []const []const u8, values: []const f64) !V {
    var result = d.object();
    for (events, values) |e, v| if (metric(e)) |key| {
        try d.put(c, &result, key, .{ .float = v });
    };
    return result;
}
fn costs(c: *C, events: []const []const u8, text: []const u8) ![]f64 {
    const cells = try tokens(c, text);
    if (cells.len > events.len) return error.InvalidExperiment;
    const result = try c.a.alloc(f64, events.len);
    @memset(result, 0);
    for (cells, 0..) |cell, i| result[i] = try count(cell);
    return result;
}
fn aggregate(c: *C, rows: *V, identity: V, values: V) !void {
    const key = try d.str(try c.hash(identity));
    var row = d.get(rows.*, key);
    if (row == .null) row = try d.clone(c, identity);
    for (try d.keys(c, values)) |k| {
        const before = d.get(row, k);
        try d.put(c, &row, k, .{ .float = (if (before == .null) @as(f64, 0) else try d.num(before)) + try d.num(d.get(values, k)) });
    }
    try d.put(c, rows, key, row);
}
const Position = struct { names: [][]const u8, previous: []i64 };
fn positions(c: *C, p: *Position, cells: []const []const u8) !i64 {
    var line: i64 = 0;
    for (p.names, 0..) |name, i| {
        const v = cells[i];
        if (!std.mem.eql(u8, v, "*")) {
            const number = try std.fmt.parseInt(i64, v, 0);
            if (v.len > 0 and (v[0] == '+' or v[0] == '-')) p.previous[i] = std.math.add(i64, p.previous[i], number) catch return error.InvalidExperiment else p.previous[i] = number;
        }
        if (std.mem.eql(u8, name, "line")) line = p.previous[i];
    }
    if (line < 0) return c.fail("negative profile line");
    return line;
}
/// Parse compressed names and positions; include self costs and exclude call arcs.
pub fn grind(c: *C, text: []const u8) d.Error!V {
    return grindImpl(c, text) catch |err| d.failure(c, err);
}
fn grindImpl(c: *C, text: []const u8) !V {
    var events: [][]const u8 = &.{};
    var pos: Position = .{ .names = try c.a.dupe([]const u8, &.{"line"}), .previous = try c.a.dupe(i64, &.{0}) };
    var summary: ?[]f64 = null;
    var totals: ?[]f64 = null;
    var sums: []f64 = &.{};
    var names = [_]V{ d.object(), d.object(), d.object() };
    var current = try c.value(.{ .file = "???", .function = "???", .object = "???" });
    var functions = d.object();
    var lines = d.object();
    var skip_arc = false;
    var input = std.mem.splitScalar(u8, text, '\n');
    while (input.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \r\t");
        if (line.len == 0 or line[0] == '#') continue;
        if (std.mem.startsWith(u8, line, "events:")) {
            if (events.len > 0) return c.fail("multiple event definitions in one profile");
            events = try tokens(c, line[7..]);
            sums = try c.a.alloc(f64, events.len);
            @memset(sums, 0);
        } else if (std.mem.startsWith(u8, line, "positions:")) {
            pos.names = try tokens(c, line[10..]);
            pos.previous = try c.a.alloc(i64, pos.names.len);
            @memset(pos.previous, 0);
        } else if (std.mem.startsWith(u8, line, "summary:")) {
            summary = try costs(c, events, line[8..]);
        } else if (std.mem.startsWith(u8, line, "totals:")) {
            totals = try costs(c, events, line[7..]);
        } else if (std.mem.indexOfScalar(u8, line, '=')) |eq| {
            const tag = line[0..eq];
            const value = line[eq + 1 ..];
            var index: ?usize = null;
            if (std.mem.eql(u8, tag, "fl") or std.mem.eql(u8, tag, "fi") or std.mem.eql(u8, tag, "fe")) index = 0;
            if (std.mem.eql(u8, tag, "cfl") or std.mem.eql(u8, tag, "cfi")) index = 0;
            if (std.mem.eql(u8, tag, "fn") or std.mem.eql(u8, tag, "cfn")) index = 1;
            if (std.mem.eql(u8, tag, "ob") or std.mem.eql(u8, tag, "cob")) index = 2;
            if (index) |i| {
                const value_name = try resolve(c, &names[i], value);
                if (tag[0] != 'c') try d.put(c, &current, ([_][]const u8{ "file", "function", "object" })[i], value_name);
            } else if (std.mem.eql(u8, tag, "calls")) skip_arc = true;
        } else if (std.ascii.isDigit(line[0]) or std.mem.indexOfScalar(u8, "+-*", line[0]) != null) {
            const cells = try tokens(c, line);
            if (events.len == 0 or cells.len <= pos.names.len or cells.len > pos.names.len + events.len) return c.fail("truncated or incompatible cost row");
            const lineno = try positions(c, &pos, cells);
            const values = try c.a.alloc(f64, events.len);
            @memset(values, 0);
            for (cells[pos.names.len..], 0..) |v, i| values[i] = try count(v);
            if (skip_arc) {
                skip_arc = false;
                continue;
            }
            for (sums, values) |*s, v| s.* += v;
            const measured = try metrics(c, events, values);
            try aggregate(c, &functions, current, measured);
            var source = try d.clone(c, current);
            try d.put(c, &source, "line", .{ .integer = lineno });
            try aggregate(c, &lines, source, measured);
        }
    }
    const total = totals orelse summary orelse return c.fail("missing profile totals");
    const measured = try metrics(c, events, total);
    if (d.get(measured, d.key_instructions) == .null or total.len != sums.len) return error.InvalidExperiment;
    for (total, sums) |a, b| if (a != b) return c.fail("Valgrind self costs do not reconcile with totals");
    var f = d.array(c);
    var l = d.array(c);
    for (functions.object.values()) |v| try d.add(c, &f, v);
    for (lines.object.values()) |v| try d.add(c, &l, v);
    return c.value(.{ .metrics = measured, .functions = f, .lines = l });
}
/// Normalize source paths and merge duplicate identities across child profiles.
pub fn normalize(c: *C, rows: V, project: []const u8, work: []const u8) d.Error!V {
    return normalizeImpl(c, rows, project, work) catch |err| d.failure(c, err);
}
fn normalizeImpl(c: *C, rows: V, project: []const u8, work: []const u8) !V {
    var indexed = d.object();
    for (try d.items(rows)) |source| {
        var identity = d.object();
        for ([_][]const u8{ "file", "function", "object", "line" }) |k| {
            var value = d.get(source, k);
            if (std.mem.eql(u8, k, "file") or std.mem.eql(u8, k, "object")) {
                const first = try std.mem.replaceOwned(u8, c.a, try d.str(value), project, "{root}");
                value = d.string(try std.mem.replaceOwned(u8, c.a, first, work, "{work}"));
            }
            if (value != .null) try d.put(c, &identity, k, value);
        }
        var measured = d.object();
        for ([_][]const u8{ d.key_instructions, "data_reads", "data_writes", "atomics" }) |k| if (d.get(source, k) != .null) {
            try d.put(c, &measured, k, d.get(source, k));
        };
        try aggregate(c, &indexed, identity, measured);
    }
    var result = d.array(c);
    for (indexed.object.values()) |v| try d.add(c, &result, v);
    std.mem.sort(V, result.array.items, {}, struct {
        fn less(_: void, a: V, b: V) bool {
            return (d.num(d.get(a, d.key_instructions)) catch 0) > (d.num(d.get(b, d.key_instructions)) catch 0);
        }
    }.less);
    return result;
}
