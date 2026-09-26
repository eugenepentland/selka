//! Advisory migration analysis for code that still relies on shared values.
//!
//! The pass runs on the checked program, with the value-semantics switch off.
//! It records a source-to-destination transfer and only warns when a later
//! write to one home can be observed through the other. It uses the same
//! managed-value and path facts as value-semantics lowering. The warning is
//! advisory because class graphs and indirect calls can require a human
//! migration rather than a source edit.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const values = @import("value_semantics.zig");
const value_checks = @import("value_semantics_check.zig");
const mutation = @import("mutation.zig");

pub const code = "W_ALIAS_DEPENDENT";
const Category = enum { local_alias, class_graph, store, across_call };
const Transfer = struct {
    span: source.Span,
    src: typed.LocalId,
    dst: typed.LocalId,
    category: Category,
};
const Access = struct { span: source.Span, root: typed.LocalId, write: bool, sync_from: ?typed.LocalId = null };
const Context = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    facts: *const values.Facts,
    transfers: *std.ArrayList(Transfer),
    accesses: *std.ArrayList(Access),
};

/// Add advisory warnings for transfer sites that have an observed write/read
/// divergence. A switch-on check reports the value errors instead.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: typed.Program, sink: *diagnostic.Sink) std.mem.Allocator.Error!void {
    if (values.enabled()) return;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    for (program.functions) |function| {
        if (function.policy.host != null) continue;
        const facts = try values.Facts.collect(a, program, function);
        var transfers: std.ArrayList(Transfer) = .empty;
        var accesses: std.ArrayList(Access) = .empty;
        const ctx: Context = .{ .allocator = a, .program = program, .function = function, .facts = &facts, .transfers = &transfers, .accesses = &accesses };
        var walker = try typed_walk.Walker.init(a, program, function.scope.body);
        while (try walker.next()) |item| switch (item) {
            .statement => |id| try statement(ctx, id),
            .expression => |id| try expression(ctx, id),
        };
        for (transfers.items) |transfer| {
            if (transfer.src == transfer.dst) continue;
            if (!diverges(function, transfer, accesses.items)) continue;
            if (alreadyReported(program, sink, transfer.span)) continue;
            const fix = try storeBackFix(allocator, src, function, transfer, accesses.items);
            try sink.items.append(allocator, .{
                .code = code,
                .severity = .warning,
                .span = transfer.span,
                .message = message(transfer.category),
                .provenance = .{ .fix = fix },
            });
        }
        // A `for` or match binding and a direct write to a function result
        // have no ordinary named assignment site. Reuse the switch's checked
        // write witnesses, but render them as migration warnings here.
        var candidates: diagnostic.Sink = .{ .allocator = a };
        _ = try value_checks.checkWrites(a, program, @backingInt(function.id), &candidates);
        for (candidates.items.items) |candidate| {
            if (alreadyReported(program, sink, candidate.span)) continue;
            const category: Category = if (std.mem.eql(u8, candidate.code, value_checks.temporary_write_code)) .across_call else .local_alias;
            try sink.items.append(allocator, .{ .code = code, .severity = .warning, .span = candidate.span, .message = message(category) });
        }
    }
}

fn message(category: Category) []const u8 {
    return switch (category) {
        .local_alias => "local alias: this shared collection is written after another name takes it; value semantics gives each name an independent value",
        .class_graph => "class graph: this transfer relies on shared object identity; migrate the graph to explicit ownership or an object table before retiring class",
        .store => "store: this value is held in another collection, field or payload and later written through a different path; store the updated value back",
        .across_call => "across a call: a returned or retained argument is later written through another path; return and store back the updated value or use a mut parameter",
    };
}

fn alreadyReported(program: typed.Program, sink: *diagnostic.Sink, span: source.Span) bool {
    _ = program;
    for (sink.items.items) |item| {
        if (std.mem.eql(u8, item.code, code) and item.span.start == span.start) return true;
    }
    return false;
}

fn diverges(function: typed.Function, transfer: Transfer, accesses: []const Access) bool {
    for (accesses) |write| {
        if (!write.write or write.span.start < transfer.span.end) continue;
        const other = if (write.root == transfer.dst) transfer.src else if (write.root == transfer.src) transfer.dst else continue;
        if (@backingInt(other) < function.signature.parameter_count and !synced(accesses, other, write.root, write.span.end, std.math.maxInt(usize))) return true;
        for (accesses) |read| {
            if (read.write or read.sync_from != null or read.root != other or read.span.start < write.span.end) continue;
            if (syncContains(accesses, other, write.root, read.span) or synced(accesses, other, write.root, write.span.end, read.span.start)) continue;
            return true;
        }
    }
    return false;
}

fn synced(accesses: []const Access, target: typed.LocalId, from: typed.LocalId, after: usize, before: usize) bool {
    for (accesses) |access| {
        if (access.sync_from != from or access.root != target) continue;
        if (access.span.start >= after and access.span.end <= before) return true;
    }
    return false;
}

fn syncContains(accesses: []const Access, target: typed.LocalId, from: typed.LocalId, span: source.Span) bool {
    for (accesses) |access| {
        if (access.sync_from != from or access.root != target) continue;
        if (span.start >= access.span.start and span.end <= access.span.end) return true;
    }
    return false;
}

/// Attach a one-step repair only when the copy is between two mutable named
/// locals and the first divergent write occupies a standalone source line.
/// Rechecking after the insertion can publish the next repair in a loop.
fn storeBackFix(allocator: std.mem.Allocator, src: source.Source, function: typed.Function, transfer: Transfer, accesses: []const Access) !?diagnostic.Fix {
    if (transfer.category != .local_alias) return null;
    const first = function.scope.locals[@backingInt(transfer.src)];
    const second = function.scope.locals[@backingInt(transfer.dst)];
    if (!first.mutable or !second.mutable) return null;
    if (!values.namedHome(function, @backingInt(transfer.src))) return null;
    if (!values.namedHome(function, @backingInt(transfer.dst))) return null;
    for (accesses) |write| {
        if (!write.write or write.span.start < transfer.span.end) continue;
        const other = if (write.root == transfer.dst) transfer.src else if (write.root == transfer.src) transfer.dst else continue;
        if (synced(accesses, other, write.root, write.span.end, std.math.maxInt(usize))) continue;
        const to = function.scope.locals[@backingInt(other)];
        const from = function.scope.locals[@backingInt(write.root)];
        if (@backingInt(other) < function.signature.parameter_count) {
            var declared = false;
            for (function.signature.declared_mutates) |position| if (position == @backingInt(other)) {
                declared = true;
            };
            if (!declared) return null;
        }
        if (write.span.end > src.bytes.len) return null;
        const end = std.mem.indexOfScalarPos(u8, src.bytes, write.span.end, '\n') orelse src.bytes.len;
        const start = if (std.mem.lastIndexOfScalar(u8, src.bytes[0..write.span.start], '\n')) |at| at + 1 else 0;
        const line = src.bytes[start..end];
        const trimmed = std.mem.trimStart(u8, line, " \t");
        if (!standaloneWrite(trimmed)) return null;
        const indent = line[0 .. line.len - trimmed.len];
        const replacement = try std.fmt.allocPrint(allocator, "\n{s}{s} = {s}", .{ indent, to.name, from.name });
        return .{ .edit = .{ .span = .{ .start = end, .end = end }, .text = replacement } };
    }
    return null;
}

fn standaloneWrite(line: []const u8) bool {
    if (line.len == 0) return false;
    for ([_][]const u8{ "return ", "if ", "while ", "for ", "case ", "match ", "assert ", "with " }) |header| {
        if (std.mem.startsWith(u8, line, header)) return false;
    }
    return true;
}

fn addAccess(allocator: std.mem.Allocator, accesses: *std.ArrayList(Access), root: ?typed.LocalId, span: source.Span, write: bool) !void {
    if (root) |slot| try accesses.append(allocator, .{ .span = span, .root = slot, .write = write });
}

fn addTransfer(ctx: Context, value: typed.NodeId, target: typed.LocalId, span: source.Span, category: Category) !void {
    const ty = ctx.program.nodes[@backingInt(value)].ty;
    if (!values.needsCopy(ctx.program.records, ty) and !hasClass(ctx.program.records, ty, 0)) return;
    if (ctx.facts.classify(value, target) == .fresh and category != .across_call) return;
    const root = valueRoot(ctx.program, ctx.facts, value) orelse return;
    const final_category: Category = if (hasClass(ctx.program.records, ty, 0)) .class_graph else category;
    try ctx.transfers.append(ctx.allocator, .{ .span = span, .src = root, .dst = target, .category = final_category });
}

fn valueRoot(program: typed.Program, facts: *const values.Facts, id: typed.NodeId) ?typed.LocalId {
    const node = program.nodes[@backingInt(id)];
    switch (node.data) {
        .call => |call| {
            const callee = program.functions[@backingInt(call.function)];
            const position = switch (callee.signature.return_origin) {
                .params => |positions| if (positions.len == 1) positions[0] else return null,
                else => return null,
            };
            if (position >= call.arguments.len) return null;
            return valueRoot(program, facts, call.arguments[position]);
        },
        else => {},
    }
    const slot = values.pathRoot(program, id) orelse return null;
    return values.namedRoot(facts, slot) orelse slot;
}

fn statement(ctx: Context, id: typed.StatementId) !void {
    const stmt = ctx.program.statements[@backingInt(id)];
    switch (stmt.data) {
        .initialize, .assign => |store| {
            if (stmt.data == .assign) if (valueRoot(ctx.program, ctx.facts, store.value)) |origin| {
                try ctx.accesses.append(ctx.allocator, .{ .span = stmt.span, .root = store.slot, .write = false, .sync_from = origin });
            };
            if (ctx.facts.namedStore(store.slot)) {
                const value = ctx.program.nodes[@backingInt(store.value)];
                const category: Category = if (value.data == .call) .across_call else .local_alias;
                try addTransfer(ctx, store.value, store.slot, stmt.span, category);
                // A record, array or wrapper keeps each transferred component
                // even when the outer value itself was just constructed.
                try storedChildren(ctx, store.value, store.slot);
            }
            const value = ctx.program.nodes[@backingInt(store.value)];
            if (value.data == .update or value.data == .replace) {
                try addAccess(ctx.allocator, ctx.accesses, values.namedRoot(ctx.facts, store.slot) orelse store.slot, stmt.span, true);
            }
        },
        .match => |matched| for (matched.arms) |arm| if (arm.slot) |slot| {
            try addTransfer(ctx, matched.value, slot, stmt.span, .local_alias);
        },
        else => {},
    }
}

fn storedChildren(ctx: Context, id: typed.NodeId, target: typed.LocalId) !void {
    const node = ctx.program.nodes[@backingInt(id)];
    switch (node.data) {
        .record => |fields| for (fields) |field| {
            try addTransfer(ctx, field.value, target, ctx.program.nodes[@backingInt(field.value)].span, .store);
        },
        .array => |elements| for (elements) |element| {
            try addTransfer(ctx, element, target, ctx.program.nodes[@backingInt(element)].span, .store);
        },
        .variant => |variant| if (variant.value) |value| {
            try addTransfer(ctx, value, target, ctx.program.nodes[@backingInt(value)].span, .store);
        },
        .wrap => |value| try addTransfer(ctx, value, target, ctx.program.nodes[@backingInt(value)].span, .store),
        else => {},
    }
}

fn expression(ctx: Context, id: typed.NodeId) !void {
    const node = ctx.program.nodes[@backingInt(id)];
    switch (node.data) {
        .local => |slot| try addAccess(ctx.allocator, ctx.accesses, values.namedRoot(ctx.facts, slot) orelse slot, node.span, false),
        .buffer_operation => |operation| {
            if (operation.kind.mutates()) try addAccess(ctx.allocator, ctx.accesses, values.namedRoot(ctx.facts, operation.owner) orelse operation.owner, node.span, true);
            if (values.storedArgument(ctx.program.records, ctx.function.scope.locals[@backingInt(operation.owner)].ty, operation.kind)) |position| {
                if (position < operation.arguments.len) {
                    const value = operation.arguments[position];
                    try addTransfer(ctx, value, operation.owner, node.span, .store);
                }
            }
        },
        .call => |call| {
            const callee = ctx.program.functions[@backingInt(call.function)];
            for (callee.signature.declared_mutates) |position| {
                if (position >= call.arguments.len) continue;
                try addAccess(ctx.allocator, ctx.accesses, valueRoot(ctx.program, ctx.facts, call.arguments[position]), node.span, true);
            }
        },
        else => {
            if (mutation.typedNode(ctx.program, ctx.function, node)) |witness| if (witness.operation == .receiver_write) {
                try addAccess(ctx.allocator, ctx.accesses, if (witness.owner) |owner| values.namedRoot(ctx.facts, owner) orelse owner else null, witness.span, true);
            };
        },
    }
}

fn hasClass(records: []const typed.Record, ty: typed.Type, depth: usize) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len or depth > 32) return false;
    const record = records[ty.recordIndex()];
    if (record.isManagedRecord()) return true;
    if (record.isCollection()) return if (record.shape.buffer) |child| hasClass(records, child, depth + 1) else false;
    if (record.shape.array) |array| if (hasClass(records, array.element, depth + 1)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| if (case.payload) |payload| {
        if (hasClass(records, payload, depth + 1)) return true;
    };
    for (record.fields) |field| if (hasClass(records, field.ty, depth + 1)) return true;
    return false;
}
