//! Exact candidates over checked trees. No rewriting, execution, or validity rules.
const std = @import("std");
const typed = @import("typed.zig");
const Source = @import("source.zig").Source;

pub const version = "exact-v7";
pub const Population = enum { production, tests, generated, reference, intentional };
pub const Options = struct { min_nodes: usize = 8, population: Population = .production };
pub const Group = struct { members: []const typed.FunctionId, nodes: usize };
pub const Analysis = struct {
    arena: std.heap.ArenaAllocator,
    groups: []const Group,
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
    writer.print("{s} fn {s} {d} {d}\n", .{ version, typed.typeName(function.return_type, program.records), function.parameter_count, function.locals.len }) catch return error.OutOfMemory;
    writer.print("conversion {}\n", .{function.conversion}) catch return error.OutOfMemory;
    if (function.owner) |owner| writer.print("owner domain {s}\n", .{typed.typeName(owner, program.records)}) catch return error.OutOfMemory else writer.writeAll("owner none\n") catch return error.OutOfMemory;
    writer.print("private {}\n", .{function.restricted}) catch return error.OutOfMemory;
    // Slot identities are declaration order within a function, including parameters.
    // Names, spans, and advisory use counters have no role in structural equality.
    for (function.locals) |local| writer.print("local {s} {}\n", .{ typed.typeName(local.ty, program.records), local.mutable }) catch return error.OutOfMemory;
    try work.append(allocator, .{ .statement = function.body });
    while (work.pop()) |task| {
        nodes += 1;
        switch (task) {
            .expression => |id| {
                const node = program.nodes[@backingInt(id)];
                writer.print("expr {s} {s}\n", .{ typed.typeName(node.ty, program.records), @tagName(node.data) }) catch return error.OutOfMemory;
                switch (node.data) {
                    .variant => |variant| {
                        writer.print("variant {s}\n", .{program.records[node.ty.recordIndex()].variants.?.cases[variant.tag].name}) catch return error.OutOfMemory;
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
                    .cast, .wrap, .unwrap => |operand| try work.append(allocator, .{ .expression = operand }),
                    .record => |fields| {
                        try recordFields(allocator, writer, &work, program, node.ty, fields);
                    },
                    .update => |update| {
                        try recordFields(allocator, writer, &work, program, node.ty, update.fields);
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
                        writer.print("args {d}\n", .{call.arguments.len}) catch return error.OutOfMemory;
                        var i = call.arguments.len;
                        while (i > 0) {
                            i -= 1;
                            try work.append(allocator, .{ .expression = call.arguments[i] });
                        }
                    },
                }
            },
            .statement => |id| {
                const statement = program.statements[@backingInt(id)];
                writer.print("stmt {s}\n", .{@tagName(statement.data)}) catch return error.OutOfMemory;
                switch (statement.data) {
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
                        const variants = program.records[ty.recordIndex()].variants.?;
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
            },
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
pub fn discover(allocator: std.mem.Allocator, program: typed.Program, options: Options) !Analysis {
    if (options.min_nodes == 0) return error.InvalidThreshold;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const scratch = arena.allocator();
    const Bucket = struct { members: std.ArrayList(typed.FunctionId) = .empty, nodes: usize };
    var index: std.StringHashMapUnmanaged(usize) = .empty;
    var buckets: std.ArrayList(Bucket) = .empty;
    var examined_bytes: usize = 0;
    var indexed: usize = 0;
    for (program.functions) |function| {
        const key = try canonical(scratch, program, function);
        examined_bytes += key.bytes.len;
        if (key.nodes < options.min_nodes) continue;
        indexed += 1;
        const entry = try index.getOrPut(scratch, key.bytes);
        if (!entry.found_existing) {
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
    return .{ .arena = arena, .groups = try groups.toOwnedSlice(scratch), .functions_examined = program.functions.len, .functions_indexed = indexed, .canonical_bytes = examined_bytes, .options = options };
}

pub fn render(allocator: std.mem.Allocator, analysis: Analysis, program: typed.Program, source: Source) ![]u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    const writer = &output.writer;
    writer.print("duplicate discovery {s}; population={s}; min-nodes={d}\n", .{ version, @tagName(analysis.options.population), analysis.options.min_nodes }) catch return error.OutOfMemory;
    for (analysis.groups, 0..) |group, i| {
        writer.print("candidate {d}: exact checked structure, {d} nodes, {d} functions\n", .{ i + 1, group.nodes, group.members.len }) catch return error.OutOfMemory;
        for (group.members) |id| {
            const function = program.functions[@backingInt(id)];
            const at = source.locate(function.declaration.start);
            writer.print("  {s}:{d}:{d}: {s}\n", .{ source.path, at.line, at.column, function.name }) catch return error.OutOfMemory;
        }
        const representative = program.functions[@backingInt(group.members[0])];
        const body = source.text(program.statements[@backingInt(representative.body)].span);
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
        writer.writeAll("  shared: types, literals, operators, control flow, local slots, and resolved calls\n  normalized: local/parameter names, source spelling, and direct self-recursion\n  review: no canonical helper declared; shared structure does not establish shared domain policy\n") catch return error.OutOfMemory;
    }
    writer.print("{d} candidate groups; {d}/{d} functions indexed\n", .{ analysis.groups.len, analysis.functions_indexed, analysis.functions_examined }) catch return error.OutOfMemory;
    writer.writeAll("Advisory only. Independent implementations may remain separate; no code was merged.\n") catch return error.OutOfMemory;
    return output.toOwnedSlice();
}
