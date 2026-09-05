//! Static resolved call references and explicit advisory structural metrics.
const std = @import("std");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const source = @import("source.zig");
pub const version = "quality-v1";
pub const Options = struct { max_function_lines: usize = 80, max_parameters: usize = 6, max_nesting: usize = 4, max_decisions: usize = 10, max_line_bytes: usize = 100 };
pub const Call = struct { callee: typed.FunctionId, span: source.Span };
pub const Function = struct {
    calls: []const Call = &.{},
    incoming_sites: usize = 0,
    reachable: bool = false,
    nodes: usize = 0,
    lines: usize = 0,
    longest_line: usize = 0,
    parameters: usize = 0,
    nesting: usize = 0,
    decisions: usize = 0,
};
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    functions: []Function,
    options: Options,
    pub fn deinit(self: *Analysis) void {
        self.arena.deinit();
    }
};
pub fn analyze(allocator: std.mem.Allocator, program: typed.Program, src: source.Source, options: Options) !Analysis {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const functions = try scratch.alloc(Function, program.functions.len);
    @memset(functions, .{});
    const line_lengths = try scratch.alloc(usize, src.line_starts.len);
    for (src.line_starts, line_lengths, 0..) |start, *length, i| {
        const end = if (i + 1 < src.line_starts.len) src.line_starts[i + 1] - 1 else src.bytes.len;
        length.* = std.mem.trimEnd(u8, src.bytes[start..end], "\r").len;
    }
    for (program.functions, functions) |function, *metrics| {
        metrics.parameters = function.parameter_count;
        const body = program.statements[@backingInt(function.body)].span;
        const first_line = src.physicalLocation(function.declaration.start).line - 1;
        const last_line = src.physicalLocation(body.end - 1).line - 1;
        metrics.lines = last_line - first_line + 1;
        for (line_lengths[first_line .. last_line + 1]) |length| metrics.longest_line = @max(metrics.longest_line, length);
        var walker = try walk.Walker.init(allocator, program, function.body);
        defer walker.deinit();
        var calls: std.ArrayList(Call) = .empty;
        var controls: std.ArrayList(usize) = .empty;
        defer controls.deinit(allocator);
        while (try walker.next()) |item| {
            metrics.nodes += 1;
            switch (item) {
                .expression => |id| {
                    const node = program.nodes[@backingInt(id)];
                    switch (node.data) {
                        .call => |call| {
                            try calls.append(scratch, .{ .callee = call.function, .span = node.span });
                            functions[@backingInt(call.function)].incoming_sites += 1;
                        },
                        .binary => |binary| if (binary.op == .logical_and or binary.op == .logical_or) {
                            metrics.decisions += 1;
                        },
                        .propagate => metrics.decisions += 1,
                        else => {},
                    }
                },
                .statement => |id| {
                    const statement = program.statements[@backingInt(id)];
                    while (controls.items.len != 0 and statement.span.start >= controls.items[controls.items.len - 1]) _ = controls.pop();
                    const control = switch (statement.data) {
                        .branch, .loop => blk: {
                            metrics.decisions += 1;
                            break :blk true;
                        },
                        .match => |match| blk: {
                            metrics.decisions += match.arms.len -| 1;
                            break :blk true;
                        },
                        else => false,
                    };
                    if (control) {
                        try controls.append(allocator, statement.span.end);
                        metrics.nesting = @max(metrics.nesting, controls.items.len);
                    }
                },
            }
        }
        metrics.calls = try calls.toOwnedSlice(scratch);
    }
    // Reachability follows resolved IDs, including cycles, once per function.
    var pending: std.ArrayList(typed.FunctionId) = .empty;
    defer pending.deinit(allocator);
    try pending.append(allocator, program.main);
    functions[@backingInt(program.main)].reachable = true;
    while (pending.pop()) |id| {
        for (functions[@backingInt(id)].calls) |call| {
            const target = &functions[@backingInt(call.callee)];
            if (target.reachable) continue;
            target.reachable = true;
            try pending.append(allocator, call.callee);
        }
    }
    return .{ .arena = arena, .functions = functions, .options = options };
}
fn signal(writer: *std.Io.Writer, name: []const u8, value: usize, limit: usize) error{OutOfMemory}!void {
    if (limit != 0 and value > limit) writer.print("  review: {s} {d} exceeds configured {d}; inspect cohesion before splitting\n", .{ name, value, limit }) catch return error.OutOfMemory;
}
pub fn render(allocator: std.mem.Allocator, analysis: Analysis, program: typed.Program, src: source.Source) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    writer.print("static quality report {s}\n", .{version}) catch return error.OutOfMemory;
    writer.writeAll("Reachability is from main over resolved calls, including untaken paths. Runtime coverage and assertions: not measured.\n") catch return error.OutOfMemory;
    for (program.functions, analysis.functions) |function, metrics| {
        const at = src.locate(function.declaration.start);
        writer.print("{s}:{d}:{d}: {s}; private={}; reachable-from-main={}; incoming-call-sites={d}\n", .{ at.path, at.line, at.column, function.name, function.restricted, metrics.reachable, metrics.incoming_sites }) catch return error.OutOfMemory;
        writer.print("  nodes={d} function-lines={d} longest-line-bytes={d} parameters={d} control-nesting={d} decision-points={d}\n", .{ metrics.nodes, metrics.lines, metrics.longest_line, metrics.parameters, metrics.nesting, metrics.decisions }) catch return error.OutOfMemory;
        if (!metrics.reachable) writer.writeAll(if (function.restricted) "  review: private function has no call path from main in this compilation\n" else "  review: no call path from main; external entry policy must be considered before removal\n") catch return error.OutOfMemory;
        for (metrics.calls) |call| {
            const site = src.locate(call.span.start);
            writer.print("  calls {s} at {s}:{d}:{d}\n", .{ program.functions[@backingInt(call.callee)].name, site.path, site.line, site.column }) catch return error.OutOfMemory;
        }
        for (function.locals) |local| {
            const location = src.locate(local.declaration.start);
            writer.print("  binding {s} at {d}:{d}: static reads={d} writes={d}\n", .{ local.name, location.line, location.column, local.reads, local.writes }) catch return error.OutOfMemory;
        }
        try signal(writer, "function-lines", metrics.lines, analysis.options.max_function_lines);
        try signal(writer, "parameters", metrics.parameters, analysis.options.max_parameters);
        try signal(writer, "control-nesting", metrics.nesting, analysis.options.max_nesting);
        try signal(writer, "decision-points", metrics.decisions, analysis.options.max_decisions);
        try signal(writer, "line-bytes", metrics.longest_line, analysis.options.max_line_bytes);
    }
    writer.writeAll("Advisory only. Metrics do not establish correctness, test coverage, or a requirement to extract helpers.\n") catch return error.OutOfMemory;
    return output.toOwnedSlice();
}
