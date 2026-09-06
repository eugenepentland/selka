//! Static resolved call references and explicit advisory structural metrics.
/// Failures returned by analyze; callers must handle these boundary errors.
pub const AnalyzeError = error{
    InvalidQualityRoot,
    OutOfMemory,
};

const std = @import("std");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const source = @import("source.zig");
pub const version = "quality-v1";
pub const module_version = "quality-modules-v1";
/// Thresholds for function size, parameter count, nesting, decisions, and line width.
pub const Options = struct { max_function_lines: usize = 80, max_parameters: usize = 6, max_nesting: usize = 4, max_decisions: usize = 10, max_line_bytes: usize = 100 };
/// Resolved callee identity and source location of a static call site.
pub const Call = struct { callee: typed.FunctionId, span: source.Span };
/// Per-function complexity metrics and static reachability/call evidence.
pub const Function = struct {
    calls: []const Call = &.{},
    incoming_sites: usize = 0,
    reachable: bool = false,
    exported: bool = false,
    reachable_from_exports: bool = false,
    structure: Structure = .{},
};
/// Measured syntax size, nesting, decision count, and source-line dimensions.
pub const Structure = struct {
    nodes: usize = 0,
    lines: usize = 0,
    longest_line: usize = 0,
    parameters: usize = 0,
    nesting: usize = 0,
    decisions: usize = 0,
};
/// Owned quality metrics, call graph evidence, and resulting diagnostics.
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    functions: []Function,
    options: Options,
    module_roots: bool,
    pub fn deinit(self: *Analysis) void {
        self.arena.deinit();
    }
};
/// Analyze checked function structure and reachability from the program entry point.
pub fn analyze(allocator: std.mem.Allocator, program: typed.Program, src: source.Source, options: Options) AnalyzeError!Analysis {
    return analyzeWithExports(allocator, program, src, options, null);
}
/// Analyze structure and reachability with optional additional public interface roots.
pub fn analyzeWithExports(allocator: std.mem.Allocator, program: typed.Program, src: source.Source, options: Options, exports: ?[]const typed.FunctionId) AnalyzeError!Analysis {
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
        metrics.structure.parameters = function.signature.parameter_count;
        const body = program.statements[@backingInt(function.scope.body)].span;
        const first_line = src.physicalLocation(function.declaration.start).line - 1;
        const last_line = src.physicalLocation(body.end - 1).line - 1;
        metrics.structure.lines = last_line - first_line + 1;
        for (line_lengths[first_line .. last_line + 1]) |length| metrics.structure.longest_line = @max(metrics.structure.longest_line, length);
        var walker = try walk.Walker.init(allocator, program, function.scope.body);
        defer walker.deinit();
        var calls: std.ArrayList(Call) = .empty;
        var controls: std.ArrayList(usize) = .empty;
        defer controls.deinit(allocator);
        while (try walker.next()) |item| {
            metrics.structure.nodes += 1;
            switch (item) {
                .expression => |id| try measureExpression(scratch, program, functions, metrics, &calls, id),
                .statement => |id| try measureStatement(allocator, program, metrics, &controls, id),
            }
        }
        metrics.calls = try calls.toOwnedSlice(scratch);
    }
    try markReachable(allocator, functions, &.{program.main}, "reachable");
    if (exports) |roots| {
        for (roots) |root| {
            if (@backingInt(root) >= functions.len) return error.InvalidQualityRoot;
            functions[@backingInt(root)].exported = true;
        }
        try markReachable(allocator, functions, roots, "reachable_from_exports");
    }
    return .{ .arena = arena, .functions = functions, .options = options, .module_roots = exports != null };
}
fn markReachable(allocator: std.mem.Allocator, functions: []Function, roots: []const typed.FunctionId, comptime field: []const u8) !void {
    var pending: std.ArrayList(typed.FunctionId) = .empty;
    defer pending.deinit(allocator);
    for (roots) |root| {
        if (@backingInt(root) >= functions.len) return error.InvalidQualityRoot;
        if (@field(functions[@backingInt(root)], field)) continue;
        @field(functions[@backingInt(root)], field) = true;
        try pending.append(allocator, root);
    }
    while (pending.pop()) |id| {
        for (functions[@backingInt(id)].calls) |call| {
            const target = &functions[@backingInt(call.callee)];
            if (@field(target, field)) continue;
            @field(target, field) = true;
            try pending.append(allocator, call.callee);
        }
    }
}

fn signal(writer: *std.Io.Writer, name: []const u8, value: usize, limit: usize) error{OutOfMemory}!void {
    if (limit != 0 and value > limit) writer.print("  review: {s} {d} exceeds configured {d}; inspect cohesion before splitting\n", .{ name, value, limit }) catch return error.OutOfMemory;
}
/// Allocate a source-located report of function metrics and static call evidence.
pub fn render(allocator: std.mem.Allocator, analysis: Analysis, program: typed.Program, src: source.Source) std.mem.Allocator.Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    writer.print("static quality report {s}\n", .{if (analysis.module_roots) module_version else version}) catch return error.OutOfMemory;
    writer.writeAll("Reachability is from main over resolved calls, including untaken paths. Runtime coverage and assertions: not measured.\n") catch return error.OutOfMemory;
    if (analysis.module_roots) writer.writeAll("Scope: reachable module graph. Export reachability starts at every exported function and " ++
        "public method of an exported domain; it is not evidence of external " ++
        "callers.\n") catch return error.OutOfMemory;
    for (program.functions, analysis.functions) |function, metrics| {
        const at = src.locate(function.declaration.start);
        writer.print("{s}:{d}:{d}: {s}; private={}; reachable-from-main={}; incoming-call-sites={d}\n", .{
            at.path,
            at.line,
            at.column,
            function.name,
            function.policy.restricted,
            metrics.reachable,
            metrics.incoming_sites,
        }) catch return error.OutOfMemory;
        writer.print("  nodes={d} function-lines={d} longest-line-bytes={d} parameters={d} control-nesting={d} " ++
            "decision-points={d}" ++
            "\n", .{
            metrics.structure.nodes,
            metrics.structure.lines,
            metrics.structure.longest_line,
            metrics.structure.parameters,
            metrics.structure.nesting,
            metrics.structure.decisions,
        }) catch return error.OutOfMemory;
        if (analysis.module_roots) {
            writer.print("  module-exported={} reachable-from-exports={} domain-private={}\n", .{ metrics.exported, metrics.reachable_from_exports, function.policy.restricted }) catch return error.OutOfMemory;
            if (!metrics.reachable and !metrics.reachable_from_exports) writer.writeAll("  review: no call path from main or exported interfaces in this graph; review before removal\n") catch return error.OutOfMemory;
        } else if (!metrics.reachable) {
            const advice = if (function.policy.restricted) "  review: private function has no call path from main in this compilation\n" else "  review: no call path from main; external entry policy must be considered before removal\n";
            writer.writeAll(advice) catch return error.OutOfMemory;
        }
        for (metrics.calls) |call| {
            const site = src.locate(call.span.start);
            writer.print("  calls {s} at {s}:{d}:{d}\n", .{ program.functions[@backingInt(call.callee)].name, site.path, site.line, site.column }) catch return error.OutOfMemory;
        }
        for (function.scope.locals) |local| {
            const location = src.locate(local.declaration.start);
            writer.print("  binding {s} at {d}:{d}: static reads={d} writes={d}\n", .{ local.name, location.line, location.column, local.usage.reads, local.usage.writes }) catch return error.OutOfMemory;
        }
        try signal(writer, "function-lines", metrics.structure.lines, analysis.options.max_function_lines);
        try signal(writer, "parameters", metrics.structure.parameters, analysis.options.max_parameters);
        try signal(writer, "control-nesting", metrics.structure.nesting, analysis.options.max_nesting);
        try signal(writer, "decision-points", metrics.structure.decisions, analysis.options.max_decisions);
        try signal(writer, "line-bytes", metrics.structure.longest_line, analysis.options.max_line_bytes);
    }
    writer.writeAll("Advisory only. Metrics do not establish correctness, test coverage, or a requirement to extract helpers.\n") catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

fn measureExpression(scratch: std.mem.Allocator, program: typed.Program, functions: []Function, metrics: *Function, calls: *std.ArrayList(Call), id: typed.NodeId) !void {
    const node = program.nodes[@backingInt(id)];
    switch (node.data) {
        .call => |call| {
            try calls.append(scratch, .{ .callee = call.function, .span = node.span });
            functions[@backingInt(call.function)].incoming_sites += 1;
        },
        .binary => |binary| if (binary.op == .logical_and or binary.op == .logical_or) {
            metrics.structure.decisions += 1;
        },
        .propagate => metrics.structure.decisions += 1,
        else => {},
    }
}

fn measureStatement(allocator: std.mem.Allocator, program: typed.Program, metrics: *Function, controls: *std.ArrayList(usize), id: typed.StatementId) !void {
    const statement = program.statements[@backingInt(id)];
    while (controls.items.len != 0 and statement.span.start >= controls.items[controls.items.len - 1]) _ = controls.pop();
    const control = switch (statement.data) {
        .branch, .loop => blk: {
            metrics.structure.decisions += 1;
            break :blk true;
        },
        .match => |match| blk: {
            metrics.structure.decisions += match.arms.len -| 1;
            break :blk true;
        },
        else => false,
    };
    if (control) {
        try controls.append(allocator, statement.span.end);
        metrics.structure.nesting = @max(metrics.structure.nesting, controls.items.len);
    }
}
