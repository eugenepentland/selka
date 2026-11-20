//! Static resolved call references and explicit advisory structural metrics.
/// Failures returned by analyze; callers must handle these boundary errors.
pub const AnalyzeError = error{
    InvalidQualityRoot,
    OutOfMemory,
};

const std = @import("std");

/// Parameters that carry data, not authority: a capability parameter is the
/// caller's grant, so it does not count toward the size budget (wave 2 stage 5).
fn dataParameterCount(function: typed.Function) usize {
    var count: usize = 0;
    for (function.scope.locals) |local| {
        if (local.origin != .parameter) continue;
        if (local.ty.capabilityIndex() != null) continue;
        count += 1;
    }
    return count;
}
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");
const source = @import("source.zig");
const ast = @import("ast.zig");
const entry_adapter = @import("entry_adapter.zig");
const invariant_callbacks = @import("invariant_callbacks.zig");
pub const version = "quality-v1";
pub const module_version = "quality-modules-v1";
/// Thresholds for function size, parameter count, nesting, decisions, and line width.
pub const Options = struct { max_function_lines: usize = 60, max_parameters: usize = 5, max_nesting: usize = 4, max_decisions: usize = 10, max_line_bytes: usize = 100 };
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
/// `syntax` is the parsed program the checked one came from: control nesting is measured on it.
pub fn analyze(allocator: std.mem.Allocator, program: typed.Program, src: source.Source, syntax: ast.Program, options: Options) AnalyzeError!Analysis {
    return analyzeWithExports(allocator, program, src, syntax, options, null);
}
/// Analyze structure and reachability with optional additional public interface roots.
pub fn analyzeWithExports(allocator: std.mem.Allocator, program: typed.Program, src: source.Source, syntax: ast.Program, options: Options, exports: ?[]const typed.FunctionId) AnalyzeError!Analysis {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const functions = try scratch.alloc(Function, program.functions.len);
    @memset(functions, .{});
    var declared: std.AutoHashMapUnmanaged(usize, usize) = .empty;
    for (syntax.functions, 0..) |function, i| try declared.put(scratch, function.name.start, i);
    const line_lengths = try scratch.alloc(usize, src.line_starts.len);
    for (src.line_starts, line_lengths, 0..) |start, *length, i| {
        const end = if (i + 1 < src.line_starts.len) src.line_starts[i + 1] - 1 else src.bytes.len;
        length.* = std.mem.trimEnd(u8, src.bytes[start..end], "\r").len;
    }
    for (program.functions, functions) |function, *metrics| {
        metrics.structure.parameters = dataParameterCount(function);
        const body = program.statements[@backingInt(function.scope.body)].span;
        const first_line = src.physicalLocation(function.declaration.start).line - 1;
        const last_line = src.physicalLocation(body.end - 1).line - 1;
        metrics.structure.lines = last_line - first_line + 1;
        for (line_lengths[first_line .. last_line + 1]) |length| metrics.structure.longest_line = @max(metrics.structure.longest_line, length);
        var walker = try walk.Walker.init(allocator, program, function.scope.body);
        defer walker.deinit();
        var calls: std.ArrayList(Call) = .empty;
        while (try walker.next()) |item| {
            metrics.structure.nodes += 1;
            switch (item) {
                .expression => |id| try measureExpression(scratch, program, functions, &calls, id),
                .statement => {},
            }
        }
        metrics.calls = try calls.toOwnedSlice(scratch);
        if (parsedBody(syntax, declared, function)) |parsed| {
            metrics.structure.nesting = try controlNesting(allocator, syntax, parsed);
            metrics.structure.decisions = try decisionPoints(allocator, syntax, parsed);
        }
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

fn measureExpression(scratch: std.mem.Allocator, program: typed.Program, functions: []Function, calls: *std.ArrayList(Call), id: typed.NodeId) !void {
    const node = program.nodes[@backingInt(id)];
    switch (node.data) {
        .call => |call| {
            try calls.append(scratch, .{ .callee = call.function, .span = node.span });
            functions[@backingInt(call.function)].incoming_sites += 1;
        },
        else => {},
    }
}

/// The parsed body of one checked function, or null when there is none to measure: a
/// compiler-made function has no written control structure, and a checked function with no
/// parsed declaration has none either. Such functions measure 0 nesting and 0 decisions.
fn parsedBody(syntax: ast.Program, declared: std.AutoHashMapUnmanaged(usize, usize), function: typed.Function) ?ast.StatementId {
    if (compilerMade(function.name)) return null;
    const index = declared.get(function.declaration.start) orelse return null;
    const source_function = syntax.functions[index];
    if (source_function.name.end != function.declaration.end) return null;
    return source_function.body;
}

/// Functions the compiler makes rather than the program writes: the entry wrapper, which shares
/// its declaration's span, and the invariant callbacks.
fn compilerMade(name: []const u8) bool {
    return std.mem.eql(u8, name, entry_adapter.wrapper_name) or invariant_callbacks.isName(name);
}

/// One parsed statement waiting to be visited, with the control levels open around it.
const Visit = struct { statement: ast.StatementId, level: usize };

/// Deepest control level of one parsed body. `if`, `for`, `while` and `match` each open one
/// level for their body; the arms of a `match` share its level. An `elif` is a sibling of its
/// `if` and opens no level of its own: the parser stores it as a bare branch in `else_body`,
/// while a written `else` always holds a block.
fn controlNesting(allocator: std.mem.Allocator, syntax: ast.Program, body: ast.StatementId) std.mem.Allocator.Error!usize {
    var pending: std.ArrayList(Visit) = .empty;
    defer pending.deinit(allocator);
    try pending.append(allocator, .{ .statement = body, .level = 0 });
    var deepest: usize = 0;
    while (pending.pop()) |visit| {
        const inner = visit.level + 1;
        switch (syntax.statements.items[@backingInt(visit.statement)].data) {
            .block => |children| for (children) |child| try pending.append(allocator, .{ .statement = child, .level = visit.level }),
            .with_scope => |scope| try pending.append(allocator, .{ .statement = scope.body, .level = visit.level }),
            .branch => |branch| {
                deepest = @max(deepest, inner);
                try pending.append(allocator, .{ .statement = branch.then_body, .level = inner });
                if (branch.else_body) |other| try pending.append(allocator, .{ .statement = other, .level = if (continuesChain(syntax, other)) visit.level else inner });
            },
            .match => |match| {
                deepest = @max(deepest, inner);
                // A bind-or-else's success arm holds the statements after the declaration, which stand at its level;
                // only its `else` block is one level deeper, as an `if` body is (F-70).
                for (match.arms) |arm| try pending.append(allocator, .{ .statement = arm.body, .level = if (arm.alternatives.role == .success) visit.level else inner });
            },
            .for_each => |each| {
                deepest = @max(deepest, inner);
                try pending.append(allocator, .{ .statement = each.body, .level = inner });
            },
            .for_range => |range| {
                deepest = @max(deepest, inner);
                try pending.append(allocator, .{ .statement = range.body, .level = inner });
            },
            .loop => |loop| {
                deepest = @max(deepest, inner);
                // `while x is P(y):` is a loop over the `match` the parser builds for it: one level, as the source reads.
                try pushLoopBody(allocator, &pending, syntax, .{ .statement = loop.body, .level = inner });
            },
            else => {},
        }
    }
    return deepest;
}

/// Whether an `else` body continues its `if` chain: an `elif`, or `elif x is P(y):`, the `match` the parser builds for it.
fn continuesChain(syntax: ast.Program, other: ast.StatementId) bool {
    return switch (syntax.statements.items[@backingInt(other)].data) {
        .branch => true,
        .match => |match| isTest(match.arms),
        else => false,
    };
}

/// Push a loop's body at its level: the arms of the `match` of `while x is P(y):`, which the source writes as one level,
/// or the body itself.
fn pushLoopBody(allocator: std.mem.Allocator, pending: *std.ArrayList(Visit), syntax: ast.Program, body: Visit) std.mem.Allocator.Error!void {
    const looped = syntax.statements.items[@backingInt(body.statement)].data;
    if (looped != .match or !isTest(looped.match.arms)) return pending.append(allocator, body);
    for (looped.match.arms) |arm| try pending.append(allocator, .{ .statement = arm.body, .level = body.level });
}

/// Whether a `match` is the one the parser builds for a binding `is` test: it ends with the synthetic wildcard arm.
fn isTest(arms: []const ast.MatchArm) bool {
    return arms.len != 0 and arms[arms.len - 1].internal.wildcard;
}

/// A parsed statement or expression of one body whose decisions are still to be counted.
const Pending = union(enum) { statement: ast.StatementId, expression: ast.NodeId };

/// The worklist of one decision count: each visited node pushes the children it holds.
const Worklist = struct {
    allocator: std.mem.Allocator,
    items: std.ArrayList(Pending) = .empty,

    fn deinit(self: *Worklist) void {
        self.items.deinit(self.allocator);
    }

    fn statement(self: *Worklist, id: ast.StatementId) std.mem.Allocator.Error!void {
        try self.items.append(self.allocator, .{ .statement = id });
    }

    fn expression(self: *Worklist, id: ast.NodeId) std.mem.Allocator.Error!void {
        try self.items.append(self.allocator, .{ .expression = id });
    }

    fn optionalExpression(self: *Worklist, id: ?ast.NodeId) std.mem.Allocator.Error!void {
        if (id) |value| try self.expression(value);
    }

    fn optionalStatement(self: *Worklist, id: ?ast.StatementId) std.mem.Allocator.Error!void {
        if (id) |value| try self.statement(value);
    }

    fn expressions(self: *Worklist, ids: []const ast.NodeId) std.mem.Allocator.Error!void {
        for (ids) |id| try self.expression(id);
    }
};

/// Decision points of one parsed body. Each written `if`, `elif`, `for` and `while` is one; a
/// written `match` is `arms - 1`, so a `case _` counts; each written `and` or `or`, and each
/// written `try`, is one. The compiler's own branches (a slice's bounds checks, a literal-arm
/// chain, the `try` it lowers) are not in the parsed tree, so they count nothing.
fn decisionPoints(allocator: std.mem.Allocator, syntax: ast.Program, body: ast.StatementId) std.mem.Allocator.Error!usize {
    var work: Worklist = .{ .allocator = allocator };
    defer work.deinit();
    try work.statement(body);
    var count: usize = 0;
    while (work.items.pop()) |item| {
        switch (item) {
            .statement => |id| {
                const statement = syntax.statements.items[@backingInt(id)];
                count += statementDecisions(statement);
                try pushStatementChildren(&work, statement);
            },
            .expression => |id| {
                const node = syntax.nodes.items[@backingInt(id)];
                count += expressionDecisions(node);
                try pushExpressionChildren(&work, node);
            },
        }
    }
    return count;
}

/// Decisions one parsed statement adds: one for each `if` (an `elif` is an `if` statement too),
/// `for` and `while`, and `arms - 1` for a `match`.
fn statementDecisions(statement: ast.Statement) usize {
    return switch (statement.data) {
        .branch, .for_each, .for_range, .loop => 1,
        .match => |match| match.arms.len -| 1,
        else => 0,
    };
}

/// Decisions one parsed expression adds: one for each `and` and `or`, one for each `try`, one for
/// each conditional expression, and `arms - 1` for a `match` expression. Comparison chains add
/// none: their implicit `and` is not written.
fn expressionDecisions(node: ast.Node) usize {
    return switch (node.data) {
        .binary => |binary| @intFromBool(binary.op == .logical_and or binary.op == .logical_or),
        .propagate, .conditional => 1,
        .match_expression => |match| match.arms.len -| 1,
        else => 0,
    };
}

/// Push the statements and expressions one parsed statement holds directly.
fn pushStatementChildren(work: *Worklist, statement: ast.Statement) std.mem.Allocator.Error!void {
    switch (statement.data) {
        .with_scope => |scope| {
            try work.optionalExpression(scope.resource);
            try work.statement(scope.body);
        },
        .block => |children| for (children) |child| try work.statement(child),
        .assertion => |assertion| {
            try work.expression(assertion.condition);
            try work.optionalExpression(assertion.value);
        },
        .ret, .fail, .yield_value, .discard => |value| try work.expression(value),
        .loop_exit => {},
        .for_each => |each| {
            try work.expression(each.iterable);
            try work.statement(each.body);
        },
        .for_range => |range| {
            try work.expression(range.start);
            try work.expression(range.end);
            try work.optionalExpression(range.step);
            try work.statement(range.body);
        },
        .branch => |branch| {
            try work.expression(branch.condition);
            try work.statement(branch.then_body);
            try work.optionalStatement(branch.else_body);
        },
        .match => |match| {
            try work.expression(match.value);
            try pushArms(work, match.arms);
        },
        .loop => |loop| {
            try work.expression(loop.condition);
            try work.statement(loop.body);
        },
        .binding => |binding| try work.expression(binding.value),
        .assignment => |assignment| try work.expression(assignment.value),
        .gather_step => |step| {
            try work.expression(step.value);
            try work.optionalExpression(step.key);
        },
    }
}

/// Push the literal alternatives and the body of each match arm.
fn pushArms(work: *Worklist, arms: []const ast.MatchArm) std.mem.Allocator.Error!void {
    for (arms) |arm| {
        try work.expressions(arm.literals);
        try work.statement(arm.body);
    }
}

/// Push the expressions and statements one parsed expression holds directly. Every node kind is
/// named, so a new kind is a compile error here until its children are counted.
fn pushExpressionChildren(work: *Worklist, node: ast.Node) std.mem.Allocator.Error!void {
    switch (node.data) {
        .synthetic_name, .integer, .bytes, .text, .boolean, .unit, .name => {},
        .list_literal, .format, .dictionary_literal, .set_literal, .tuple => |items| try work.expressions(items),
        .field_assignment => |assign| {
            try work.expression(assign.target);
            try work.expression(assign.value);
        },
        .index_assignment => |assign| {
            try work.expression(assign.target);
            try work.expression(assign.value);
        },
        .method_call => |call| {
            try work.expression(call.base);
            try work.expressions(call.arguments);
        },
        .list_operation => |operation| {
            try work.expression(operation.base);
            try work.expressions(operation.arguments);
        },
        .buffer_operation => |operation| try work.expressions(operation.arguments),
        .file_operation => |operation| try work.optionalExpression(operation.argument),
        .slice => |slice| {
            try work.expression(slice.base);
            try work.optionalExpression(slice.start);
            try work.optionalExpression(slice.end);
            try work.optionalExpression(slice.step);
        },
        .format_field => |field| try work.expression(field.value),
        .comprehension => |comprehension| {
            try work.expression(comprehension.output);
            switch (comprehension.source) {
                .iterable => |collection| try work.expression(collection),
                .range => |bounds| {
                    try work.expression(bounds.start);
                    try work.expression(bounds.end);
                    try work.optionalExpression(bounds.step);
                },
            }
            try work.optionalExpression(comprehension.filter);
        },
        .gather => |gather| try work.statement(gather.loop),
        .membership => |membership| {
            try work.expression(membership.needle);
            try work.expression(membership.container);
        },
        .propagate, .unwrap, .length, .mut_argument, .own_argument => |value| try work.expression(value),
        .acquire_resource => |acquire| {
            try work.expression(acquire.capability);
            try work.expression(acquire.request);
        },
        .complete_resource => |resource| try work.expression(resource.value),
        .resource_io => |io| try work.optionalExpression(io.value),
        .restrict_resource => |restrict| try work.expression(restrict.value),
        .environment_get => |get| {
            try work.expression(get.capability);
            try work.expression(get.name);
        },
        .external_read => |read| try work.expression(read.capability),
        .stand_in => |stand_in| {
            try work.expression(stand_in.first);
            try work.optionalExpression(stand_in.second);
        },
        .arena_escape => |escape| try work.expression(escape.value),
        .cast, .wrap => |typed_value| try work.expression(typed_value.value),
        .variant => |variant| {
            try work.optionalExpression(variant.value);
            try work.expressions(variant.values);
        },
        .index => |element| {
            try work.expression(element.base);
            try work.expression(element.index);
        },
        .replace => |replace| {
            try work.expression(replace.base);
            try work.expression(replace.index);
            try work.expression(replace.value);
        },
        .record => |record| for (record.fields) |field| try work.expression(field.value),
        .field => |field| try work.expression(field.base),
        .call => |call| try work.expressions(call.arguments),
        .unary => |unary| try work.expression(unary.operand),
        .binary => |binary| {
            try work.expression(binary.left);
            try work.expression(binary.right);
        },
        .conditional => |conditional| {
            try work.expression(conditional.condition);
            try work.expression(conditional.then_value);
            try work.expression(conditional.else_value);
        },
        .match_expression => |match| {
            try work.expression(match.value);
            try pushArms(work, match.arms);
        },
        .accept_resource => |accept| try work.expression(accept.value),
        .variant_test => |variant| try work.expression(variant.value),
    }
}
