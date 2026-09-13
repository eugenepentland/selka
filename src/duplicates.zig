//! Exact groups and opt-in bounded near candidates over checked trees.
//! No rewriting, execution, or validity rules.
/// Failures returned by discover; callers must handle these boundary errors.
pub const DiscoverError = error{
    InternalError,
    InvalidThreshold,
    OutOfMemory,
};

const std = @import("std");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;

pub const version = "exact-v28";
/// Declared origin of the functions included in a duplicate discovery report.
pub const Population = enum { production, tests, generated, reference, intentional };
pub const near = @import("near_duplicates.zig");
/// Minimum body size, population identity, and optional bounded near-match settings.
pub const Options = struct { min_nodes: usize = 8, population: Population = .production, approximate: bool = false, near_options: near.Options = .{} };
/// Function identities with identical normalized bodies and their shared node count.
pub const Group = struct { members: []const typed.FunctionId, nodes: usize };
/// Owned exact and approximate discovery results; release their storage with deinit.
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    groups: []const Group,
    approximate: near.Result,
    functions_examined: usize,
    functions_indexed: usize,
    canonical_bytes: usize,
    options: Options,

    pub fn deinit(self: *Analysis) void {
        self.arena.deinit();
    }
};
const Work = union(enum) { expression: typed.NodeId, statement: typed.StatementId };
const Canonical = struct { bytes: []const u8, nodes: usize };

fn canonical(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function) !Canonical {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    var work: std.ArrayList(Work) = .empty;
    defer work.deinit(allocator);
    const writer = &output.writer;
    var nodes: usize = 0;
    writer.print("{s} fn {s} {d} {d}\n", .{ version, typed.typeName(function.signature.return_type, program.records), function.signature.parameter_count, function.scope.locals.len }) catch return error.OutOfMemory;
    writer.writeAll("return value\n") catch return error.OutOfMemory;
    writer.print("effects {d} bound {?d}\n", .{ function.policy.effects, if (function.policy.effect_bound) |bound| @as(?@import("effect_set.zig").Mask, bound.allowed) else null }) catch return error.OutOfMemory;
    writer.print("conversion {}\n", .{function.policy.conversion}) catch return error.OutOfMemory;
    if (function.policy.owner) |owner| writer.print("owner domain {s}\n", .{typed.typeName(owner, program.records)}) catch return error.OutOfMemory else writer.writeAll("owner none\n") catch return error.OutOfMemory;
    writer.print("private {}\n", .{function.policy.restricted}) catch return error.OutOfMemory;
    // Slot identities are declaration order within a function, including parameters.
    // Names, spans, and advisory use counters have no role in structural equality.
    for (function.scope.locals) |local| {
        writer.print("local {s} {}\n", .{
            typed.typeName(local.ty, program.records),
            local.mutable,
        }) catch return error.OutOfMemory;
    }
    try work.append(allocator, .{ .statement = function.scope.body });
    const context: CanonicalWriter = .{ .allocator = allocator, .writer = writer, .work = &work, .program = program, .function = function };
    while (work.pop()) |task| {
        nodes += 1;
        switch (task) {
            .expression => |id| try context.expression(id),
            .statement => |id| try context.writeStatement(id),
        }
    }
    return .{ .bytes = try output.toOwnedSlice(), .nodes = nodes };
}

fn recordFields(allocator: std.mem.Allocator, writer: *std.Io.Writer, work: *std.ArrayList(Work), program: typed.Program, ty: typed.Type, fields: []const typed.FieldInit) !void {
    writer.print("fields {d}\n", .{fields.len}) catch return error.OutOfMemory;
    for (fields) |field| writer.print("field {s}\n", .{program.records[ty.recordIndex()].fields[field.index].name}) catch return error.OutOfMemory;
    var i = fields.len;
    while (i > 0) {
        i -= 1;
        try work.append(allocator, .{ .expression = fields[i].value });
    }
}

/// Keys include the complete canonical structure: the hash map compares bytes
/// after hashing. A hash collision alone can never produce an exact finding.
/// Index groups once and report membership, avoiding a quadratic list of pairs.
pub fn discover(allocator: std.mem.Allocator, program: typed.Program, options: Options) DiscoverError!Analysis {
    if (options.min_nodes == 0) return error.InvalidThreshold;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const Bucket = struct { members: std.ArrayList(typed.FunctionId) = .empty, nodes: usize };
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    var buckets: std.ArrayList(Bucket) = .empty;
    var examined_bytes: usize = 0;
    var indexed: usize = 0;
    var representatives: std.ArrayList(near.Input) = .empty;
    var examined: usize = 0;
    for (program.functions) |function| {
        if (function.policy.host != null) continue;
        examined += 1;
        const key = try canonical(scratch, program, function);
        examined_bytes += key.bytes.len;
        if (key.nodes < options.min_nodes) continue;
        indexed += 1;
        const entry = try index.getOrPut(scratch, key.bytes);
        if (!entry.found_existing) {
            if (options.approximate) try representatives.append(scratch, .{ .function = function.id, .bytes = key.bytes });
            entry.value_ptr.* = buckets.items.len;
            try buckets.append(scratch, .{ .nodes = key.nodes });
        }
        try buckets.items[entry.value_ptr.*].members.append(scratch, function.id);
    }
    var groups: std.ArrayList(Group) = .empty;
    for (buckets.items) |bucket| {
        if (bucket.members.items.len < 2) continue;
        try groups.append(scratch, .{ .members = bucket.members.items, .nodes = bucket.nodes });
    }
    const approximate: near.Result = if (options.approximate) try near.discover(scratch, allocator, representatives.items, options.near_options) else .{ .pairs = &.{}, .work = 0, .truncated = false };
    return .{ .arena = arena, .approximate = approximate, .groups = try groups.toOwnedSlice(scratch), .functions_examined = examined, .functions_indexed = indexed, .canonical_bytes = examined_bytes, .options = options };
}

/// Allocate a textual discovery report containing source locations and normalized match evidence.
pub fn render(allocator: std.mem.Allocator, analysis: Analysis, program: typed.Program, source: Source) std.mem.Allocator.Error![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    writer.print("duplicate discovery {s}; population={s}; min-nodes={d}\n", .{ version, @tagName(analysis.options.population), analysis.options.min_nodes }) catch return error.OutOfMemory;
    for (analysis.groups, 0..) |group, i| {
        writer.print("candidate {d}: exact checked structure, {d} nodes, {d} functions\n", .{ i + 1, group.nodes, group.members.len }) catch return error.OutOfMemory;
        for (group.members) |id| {
            const function = program.functions[@backingInt(id)];
            const at = source.locate(function.declaration.start);
            writer.print("  {s}:{d}:{d}: {s}\n", .{ at.path, at.line, at.column, function.name }) catch return error.OutOfMemory;
        }
        const representative = program.functions[@backingInt(group.members[0])];
        const body = source.text(program.statements[@backingInt(representative.scope.body)].span);
        writer.writeAll("  shared body (first member's spelling):\n") catch return error.OutOfMemory;
        var lines = std.mem.splitScalar(u8, body, '\n');
        var shown: usize = 0;
        while (lines.next()) |line| {
            if (shown == 12) {
                writer.writeAll("    ... remaining lines at the source location above\n") catch return error.OutOfMemory;
                break;
            }
            writer.print("    {s}\n", .{line}) catch return error.OutOfMemory;
            shown += 1;
        }
        writer.writeAll("  shared: types, literals, operators, control flow, local slots, and resolved calls\n  " ++
            "normalized: local/parameter names, source spelling, and direct self-recursion\n  review: " ++
            "no canonical helper declared; shared structure does not establish shared domain " ++
            "policy\n") catch return error.OutOfMemory;
    }
    writer.print("{d} candidate groups; {d}/{d} functions indexed\n", .{ analysis.groups.len, analysis.functions_indexed, analysis.functions_examined }) catch return error.OutOfMemory;
    if (analysis.options.approximate) {
        writer.print("approximate {s}: minimum line similarity={d}%; work={d}/{d}; truncated={}\n", .{
            near.version,
            analysis.options.near_options.similarity_percent,
            analysis.approximate.work,
            analysis.options.near_options.max_work,
            analysis.approximate.truncated,
        }) catch return error.OutOfMemory;
        for (analysis.approximate.pairs) |pair| {
            writer.print("near candidate: {d} canonical-line edits / {d} body lines; not semantic equivalence\n", .{ pair.distance, pair.lines }) catch return error.OutOfMemory;
            for ([_]typed.FunctionId{ pair.left, pair.right }) |id| {
                const function = program.functions[@backingInt(id)];
                const at = source.locate(function.declaration.start);
                writer.print("  {s}:{d}:{d}: {s} (exact-group representative)\n", .{ at.path, at.line, at.column, function.name }) catch return error.OutOfMemory;
            }
            for (pair.changes[0..@min(pair.changes.len, 8)]) |change| {
                if (change.before) |line| writer.print("    - {s}\n", .{line}) catch return error.OutOfMemory;
                if (change.after) |line| writer.print("    + {s}\n", .{line}) catch return error.OutOfMemory;
            }
            if (pair.changes.len > 8) writer.writeAll("    ... further canonical edits omitted; inspect both source bodies\n") catch return error.OutOfMemory;
        }
        writer.print("{d} approximate pairs; matching headers required; review differences and domain intent\n", .{analysis.approximate.pairs.len}) catch return error.OutOfMemory;
        if (analysis.approximate.truncated) writer.writeAll("Incomplete approximate search: work or pair limit reached; absence is not evidence of no near matches.\n") catch return error.OutOfMemory;
    }
    writer.writeAll("Advisory only. Independent implementations may remain separate; no code was merged.\n") catch return error.OutOfMemory;
    return output.toOwnedSlice();
}

const CanonicalWriter = struct {
    allocator: std.mem.Allocator,
    writer: *std.Io.Writer,
    work: *std.ArrayList(Work),
    program: typed.Program,
    function: typed.Function,
    fn expression(self: CanonicalWriter, id: typed.NodeId) !void {
        const allocator = self.allocator;
        const writer = self.writer;
        const work = self.work;
        const program = self.program;
        const function = self.function;

        const node = program.nodes[@backingInt(id)];
        writer.print("expr {s} {s} obligation {}\n", .{ typed.typeName(node.ty, program.records), @tagName(node.data), typed.requiresHandling(node.ty, program.records) }) catch return error.OutOfMemory;
        writer.print("move-only {}\n", .{typed.moveOnly(node.ty, program.records)}) catch return error.OutOfMemory;
        switch (node.data) {
            .buffer_operation => |operation| {
                writer.print("buffer {s} local {d}\n", .{ @tagName(operation.kind), @backingInt(operation.owner) }) catch return error.OutOfMemory;
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .expression = operation.arguments[i] });
                }
            },
            .propagate => |propagate| {
                writer.print("propagate to {s}\n", .{typed.typeName(propagate.output, program.records)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = propagate.value });
            },
            .block_value => |block| {
                try work.append(allocator, .{ .expression = block.value });
                try work.append(allocator, .{ .statement = block.body });
            },
            .variant => |variant| {
                writer.print("variant {s}\n", .{program.records[node.ty.recordIndex()].shape.variants.?.cases[variant.tag].name}) catch return error.OutOfMemory;
                if (variant.value) |value| try work.append(allocator, .{ .expression = value });
            },
            .array => |values| {
                writer.print("elements {d}\n", .{values.len}) catch return error.OutOfMemory;
                var i = values.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .expression = values[i] });
                }
            },
            .index => |access| {
                try work.append(allocator, .{ .expression = access.index });
                try work.append(allocator, .{ .expression = access.base });
            },
            .replace => |replace| {
                try work.append(allocator, .{ .expression = replace.value });
                try work.append(allocator, .{ .expression = replace.index });
                try work.append(allocator, .{ .expression = replace.base });
            },
            .length => |base| try work.append(allocator, .{ .expression = base }),
            .resource_io => |io| {
                writer.print("resource {s} owner={d}\n", .{ @tagName(io.kind), @backingInt(io.owner) }) catch return error.OutOfMemory;
                if (io.value) |value| try work.append(allocator, .{ .expression = value });
            },
            .restrict_resource => |restrict| {
                writer.print("permissions {d}\n", .{restrict.permissions}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = restrict.value });
            },
            .environment_get => |get| {
                try work.append(allocator, .{ .expression = get.name });
                try work.append(allocator, .{ .expression = get.capability });
            },
            .complete_resource => |value| try work.append(allocator, .{ .expression = value }),
            .acquire_resource => |acquire| {
                try work.append(allocator, .{ .expression = acquire.request });
                try work.append(allocator, .{ .expression = acquire.capability });
            },
            .external_read => |read| {
                writer.print("external {s}\n", .{@tagName(read.kind)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = read.capability });
            },
            .acquire_buffer => |acquire| try work.append(allocator, .{ .expression = acquire.capacity }),
            .file_access => |call| {
                writer.print("file access {s} mode={c} text={}\n", .{ @tagName(call.kind), call.mode, call.text }) catch return error.OutOfMemory;
                var index = call.arguments.len;
                while (index > 0) {
                    index -= 1;
                    try work.append(allocator, .{ .expression = call.arguments[index] });
                }
            },
            .file_method => |call| {
                writer.print("file method {s} local={d} text={}\n", .{ @tagName(call.kind), @backingInt(call.owner), call.text }) catch return error.OutOfMemory;
                if (call.argument) |value| try work.append(allocator, .{ .expression = value });
            },
            .print => |output| {
                writer.print("print {d} {d}{d}\n", .{ output.arguments.len, @intFromBool(output.separator != null), @intFromBool(output.terminator != null) }) catch return error.OutOfMemory;
                if (output.terminator) |value| try work.append(allocator, .{ .expression = value });
                if (output.separator) |value| try work.append(allocator, .{ .expression = value });
                var index = output.arguments.len;
                while (index > 0) {
                    index -= 1;
                    try work.append(allocator, .{ .expression = output.arguments[index] });
                }
            },
            .arena_escape, .cast, .wrap, .unwrap => |operand| try work.append(allocator, .{ .expression = operand }),
            .record => |fields| {
                try recordFields(allocator, writer, work, program, node.ty, fields);
            },
            .update => |update| {
                try recordFields(allocator, writer, work, program, node.ty, update.fields);
                try work.append(allocator, .{ .expression = update.base });
            },
            .field => |field| {
                const base_type = program.nodes[@backingInt(field.base)].ty;
                const name = program.records[base_type.recordIndex()].fields[field.index].name;
                writer.print("field {s}\n", .{name}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = field.base });
            },
            .integer => |value| writer.print("{d}\n", .{value}) catch return error.OutOfMemory,
            .unit => writer.writeAll("unit\n") catch return error.OutOfMemory,
            .boolean => |value| writer.print("{}\n", .{value}) catch return error.OutOfMemory,
            .local => |slot| writer.print("{d}\n", .{@backingInt(slot)}) catch return error.OutOfMemory,
            .unary => |unary| {
                writer.print("{s}\n", .{@tagName(unary.op)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = unary.operand });
            },
            .binary => |binary| {
                writer.print("{s}\n", .{@tagName(binary.op)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = binary.right });
                try work.append(allocator, .{ .expression = binary.left });
            },
            .function_value => |target| writer.print("function {s}\n", .{program.functions[@backingInt(target)].name}) catch return error.OutOfMemory,
            .invoke => |call| {
                try work.append(allocator, .{ .expression = call.callee });
                for (call.arguments) |argument| try work.append(allocator, .{ .expression = argument });
            },
            .call => |call| {
                // Normalize only direct self-recursion. Other callees retain
                // resolved names; mutual-recursion components are not renamed.
                if (call.function == function.id) {
                    writer.writeAll("self\n") catch return error.OutOfMemory;
                } else {
                    const callee = program.functions[@backingInt(call.function)].name;
                    writer.print("callee {d}:{s}\n", .{ callee.len, callee }) catch return error.OutOfMemory;
                }
                writer.print("args {d}\n", .{call.arguments.len}) catch return error.OutOfMemory;
                var i = call.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .expression = call.arguments[i] });
                }
            },
        }
    }
    fn writeStatement(self: CanonicalWriter, id: typed.StatementId) !void {
        const allocator = self.allocator;
        const writer = self.writer;
        const work = self.work;
        const program = self.program;

        const statement = program.statements[@backingInt(id)];
        writer.print("stmt {s}\n", .{@tagName(statement.data)}) catch return error.OutOfMemory;
        switch (statement.data) {
            .with_scope => |scope| {
                writer.print("with locals={d} resource={d}\n", .{ @backingInt(scope.slot), @intFromBool(scope.resource != null) }) catch return error.OutOfMemory;
                try work.append(allocator, .{ .statement = scope.body });
                if (scope.resource) |value| try work.append(allocator, .{ .expression = value });
            },
            .block => |children| {
                writer.print("children {d}\n", .{children.len}) catch return error.OutOfMemory;
                var i = children.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .statement = children[i] });
                }
            },
            .ret, .discard => |value| try work.append(allocator, .{ .expression = value }),
            .initialize, .assign => |store| {
                writer.print("slot {d}\n", .{@backingInt(store.slot)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = store.value });
            },
            .match => |match| {
                const ty = program.nodes[@backingInt(match.value)].ty;
                const variants = program.records[ty.recordIndex()].shape.variants.?;
                writer.print("arms {d}\n", .{match.arms.len}) catch return error.OutOfMemory;
                for (match.arms) |arm| writer.print("case {s} slot {?d}\n", .{ variants.cases[arm.tag].name, if (arm.slot) |slot| @as(?usize, @backingInt(slot)) else null }) catch return error.OutOfMemory;
                var i = match.arms.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .statement = match.arms[i].body });
                }
                try work.append(allocator, .{ .expression = match.value });
            },
            .branch => |branch| {
                writer.print("else {}\n", .{branch.else_body != null}) catch return error.OutOfMemory;
                if (branch.else_body) |body| try work.append(allocator, .{ .statement = body });
                try work.append(allocator, .{ .statement = branch.then_body });
                try work.append(allocator, .{ .expression = branch.condition });
            },
            .loop_exit => |exit| writer.print("continue {}\n", .{exit.continuing}) catch return error.OutOfMemory,
            .loop => |loop| {
                if (loop.step) |step| try work.append(allocator, .{ .statement = step });
                try work.append(allocator, .{ .statement = loop.body });
                try work.append(allocator, .{ .expression = loop.condition });
            },
        }
    }
};
