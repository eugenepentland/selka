//! Exact groups and opt-in bounded near candidates over checked trees.
//! No rewriting, execution, or validity rules.
const reference_format = "reference {d}\n";
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
    if (function.signature.return_reference) |contract| {
        writer.print("return reference from {d} mutable {} slice {}\n", .{ @backingInt(contract.parameter), contract.mutable, contract.slice }) catch return error.OutOfMemory;
    } else {
        writer.writeAll("return value\n") catch return error.OutOfMemory;
    }
    writer.print("effects {d} bound {?d}\n", .{ function.policy.effects, if (function.policy.effect_bound) |bound| @as(?u8, bound.allowed) else null }) catch return error.OutOfMemory;
    writer.print("conversion {}\n", .{function.policy.conversion}) catch return error.OutOfMemory;
    if (function.policy.owner) |owner| writer.print("owner domain {s}\n", .{typed.typeName(owner, program.records)}) catch return error.OutOfMemory else writer.writeAll("owner none\n") catch return error.OutOfMemory;
    writer.print("private {}\n", .{function.policy.restricted}) catch return error.OutOfMemory;
    // Slot identities are declaration order within a function, including parameters.
    // Names, spans, and advisory use counters have no role in structural equality.
    for (function.scope.locals) |local| {
        writer.print("local {s} {} reference {?} slice {}\n", .{
            typed.typeName(local.ty, program.records),
            local.mutable,
            local.parameter.reference_parameter,
            local.parameter.slice_parameter,
        }) catch return error.OutOfMemory;
    }
    for (function.scope.references) |reference| {
        writer.print("reference {s} owner {d} parent {?d} mutable {} parameter {} slice {}\n", .{
            typed.typeName(reference.ty, program.records),
            @backingInt(reference.owner),
            if (reference.parent) |parent| @as(?usize, @backingInt(parent)) else null,
            reference.mutable,
            reference.mode.parameter,
            reference.mode.slice,
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
            .pool_operation => |operation| {
                writer.print("pool {s} local {d}\n", .{ @tagName(operation.kind), @backingInt(operation.owner) }) catch return error.OutOfMemory;
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .expression = operation.arguments[i] });
                }
            },
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
            .read_field, .take_field => |read| writer.print("{s} owner={d} field={d}\n", .{ @tagName(node.data), @backingInt(read.owner), read.field }) catch return error.OutOfMemory,
            .resource_io => |io| {
                writer.print("resource {s} owner={d} reference={?d}\n", .{ @tagName(io.kind), @backingInt(io.owner), if (io.reference) |ref_id| @as(?usize, @backingInt(ref_id)) else null }) catch return error.OutOfMemory;
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
            .acquire_buffer, .acquire_pool => |acquire| {
                try work.append(allocator, .{ .expression = acquire.capacity });
                try work.append(allocator, .{ .expression = acquire.allocator });
            },
            .reset_arena, .cast, .wrap, .unwrap => |operand| try work.append(allocator, .{ .expression = operand }),
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
            .boolean => |value| writer.print("{}\n", .{value}) catch return error.OutOfMemory,
            .read_slice => |read| {
                writer.print(reference_format, .{@backingInt(read.reference)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = read.index });
            },
            .len_slice => |reference| writer.print(reference_format, .{@backingInt(reference)}) catch return error.OutOfMemory,
            .read_ref => |reference_id| writer.print(reference_format, .{@backingInt(reference_id)}) catch return error.OutOfMemory,
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
            .call => |call| {
                // Normalize only direct self-recursion. Other callees retain
                // resolved names; mutual-recursion components are not renamed.
                if (call.function == function.id) {
                    writer.writeAll("self\n") catch return error.OutOfMemory;
                } else {
                    const callee = program.functions[@backingInt(call.function)].name;
                    writer.print("callee {d}:{s}\n", .{ callee.len, callee }) catch return error.OutOfMemory;
                }
                writer.print("args {d} references {any}\n", .{ call.arguments.len, call.references }) catch return error.OutOfMemory;
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
            .arena_scope => |scope| {
                writer.print("arena allocator={d}\n", .{@backingInt(scope.slot)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .statement = scope.body });
                try work.append(allocator, .{ .expression = scope.parent });
            },
            .block => |children| {
                writer.print("children {d}\n", .{children.len}) catch return error.OutOfMemory;
                var i = children.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(allocator, .{ .statement = children[i] });
                }
            },
            .ret, .discard, .acknowledge => |value| try work.append(allocator, .{ .expression = value }),
            .ret_ref => |reference| writer.print(reference_format, .{@backingInt(reference)}) catch return error.OutOfMemory,
            .borrow_call => |borrow| {
                writer.print(reference_format, .{@backingInt(borrow.reference)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .statement = borrow.body });
                try work.append(allocator, .{ .expression = borrow.call });
            },
            .borrow => |borrow| {
                writer.print(reference_format, .{@backingInt(borrow.reference)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .statement = borrow.body });
                writer.print("range {}\n", .{borrow.range != null}) catch return error.OutOfMemory;
                if (borrow.range) |range| {
                    try work.append(allocator, .{ .expression = range.end });
                    try work.append(allocator, .{ .expression = range.start });
                }
            },
            .write_slice => |write| {
                writer.print(reference_format, .{@backingInt(write.reference)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = write.value });
                try work.append(allocator, .{ .expression = write.index });
            },
            .write_ref => |write| {
                writer.print(reference_format, .{@backingInt(write.reference)}) catch return error.OutOfMemory;
                try work.append(allocator, .{ .expression = write.value });
            },
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
            .loop => |loop| {
                try work.append(allocator, .{ .statement = loop.body });
                try work.append(allocator, .{ .expression = loop.condition });
            },
        }
    }
};
