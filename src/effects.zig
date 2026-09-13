//! Monotone effect inference over resolved calls, with finite witness paths.
/// Failures returned by validate; callers must handle these boundary errors.
pub const ValidateError = error{
    InternalError,
    OutOfMemory,
};

const std = @import("std");
const typed = @import("typed.zig");
const sets = @import("effect_set.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Witness = struct { span: Span, via: ?usize = null };
const Edge = struct { caller: usize, span: Span };
fn allocatingSequence(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const kind = records[ty.recordIndex()].collection.kind;
    return kind == .string or kind == .bytes;
}
/// Element reads allocate only for strings, whose elements are fresh strings.
fn allocatingElement(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    return records[ty.recordIndex()].collection.kind == .string;
}
const State = struct { mask: sets.Mask = 0, witnesses: [std.meta.tags(sets.Effect).len]?Witness = @splat(null), callers: std.ArrayList(Edge) = .empty, queued: bool = false };
const Graph = struct {
    allocator: std.mem.Allocator,
    states: []State,
    fn init(allocator: std.mem.Allocator, count: usize) !Graph {
        const states = try allocator.alloc(State, count);
        @memset(states, .{});
        return .{ .allocator = allocator, .states = states };
    }
    fn deinit(self: *Graph) void {
        for (self.states) |*state| state.callers.deinit(self.allocator);
        self.allocator.free(self.states);
    }
    fn direct(self: *Graph, function: usize, effect: sets.Effect, span: Span) void {
        const state = &self.states[function];
        state.mask |= sets.bit(effect);
        if (state.witnesses[@backingInt(effect)] == null) state.witnesses[@backingInt(effect)] = .{ .span = span };
    }
    fn call(self: *Graph, caller: usize, callee: usize, span: Span) !void {
        if (caller >= self.states.len or callee >= self.states.len) return error.InternalError;
        try self.states[callee].callers.append(self.allocator, .{ .caller = caller, .span = span });
    }
    fn infer(self: *Graph) !void {
        var work: std.ArrayList(usize) = .empty;
        defer work.deinit(self.allocator);
        for (self.states, 0..) |*state, index| if (state.mask != 0) {
            try work.append(self.allocator, index);
            state.queued = true;
        };
        while (work.pop()) |callee| {
            self.states[callee].queued = false;
            const effects = self.states[callee].mask;
            for (self.states[callee].callers.items) |edge| {
                const caller = &self.states[edge.caller];
                const added = effects & ~caller.mask;
                if (added == 0) continue;
                caller.mask |= added;
                inline for (std.meta.tags(sets.Effect)) |effect| {
                    if (added & sets.bit(effect) != 0) caller.witnesses[@backingInt(effect)] = .{ .span = edge.span, .via = callee };
                }
                if (!caller.queued) {
                    try work.append(self.allocator, edge.caller);
                    caller.queued = true;
                }
            }
        }
    }
};

/// Infer transitive effects and reject function bodies that exceed declared effect bounds.
pub fn check(allocator: std.mem.Allocator, program: typed.Program, sink: *diagnostic.Sink) diagnostic.Error!void {
    var graph = try Graph.init(allocator, program.functions.len);
    defer graph.deinit();
    const cleanup_masks = cleanupMasks(allocator, program.records) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => unreachable,
    };
    defer allocator.free(cleanup_masks);
    for (program.functions, 0..) |function, index| {
        if (function.policy.host) |span| try seedHost(&graph, index, function.policy.effect_bound, span);
        try seedOwnership(&graph, index, function.signature.return_type, function.scope.locals, function.declaration, cleanup_masks);
        var walker = try @import("typed_walk.zig").Walker.init(allocator, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| if (item == .expression) {
            const node = program.nodes[@backingInt(item.expression)];
            switch (node.data) {
                .acquire_resource => graph.direct(index, typed.resourceKind(typed.resultShape(node.ty, program.records).?.ok_type, program.records).?.effect(), node.span),
                .complete_resource => graph.direct(index, typed.resourceKind(typed.completionShape(node.ty, program.records).?.resource_type, program.records).?.effect(), node.span),
                .resource_io => |io| graph.direct(index, typed.resourceKind(function.scope.locals[@backingInt(io.owner)].ty, program.records).?.effect(), node.span),
                .environment_get => graph.direct(index, .environment, node.span),
                .external_read => |read| graph.direct(index, read.kind.effect(), node.span),
                .cast => if (allocatingSequence(program.records, node.ty)) {
                    graph.direct(index, .managed_allocation, node.span);
                },
                .array => if (node.ty.isAggregate() and program.records[node.ty.recordIndex()].managed) {
                    graph.direct(index, .managed_allocation, node.span);
                },
                .binary => |binary| if (binary.op == .add and allocatingSequence(program.records, node.ty)) {
                    graph.direct(index, .managed_allocation, node.span);
                },
                .index => if (allocatingSequence(program.records, node.ty)) {
                    graph.direct(index, .managed_allocation, node.span);
                },
                .acquire_buffer => graph.direct(index, .managed_allocation, node.span),
                .buffer_operation => |op| {
                    const managed = program.records[function.scope.locals[@backingInt(op.owner)].ty.recordIndex()].managed;
                    const dictionary = program.records[function.scope.locals[@backingInt(op.owner)].ty.recordIndex()].collection.kind == .dictionary;
                    if (managed and @import("buffer_operations.zig").managedAllocation(op.kind, dictionary)) graph.direct(index, .managed_allocation, node.span);
                },
                .invoke => |call| {
                    const contract = @import("callables.zig").signature(program.nodes[@backingInt(call.callee)].ty, program.records).?;
                    inline for (std.meta.tags(sets.Effect)) |effect| if (contract.effects & sets.bit(effect) != 0) graph.direct(index, effect, node.span);
                },
                .call => |call| graph.call(index, @backingInt(call.function), node.span) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InternalError => unreachable, // Resolved typed function identity.
                },
                .arena_escape => graph.direct(index, .managed_allocation, node.span),
                .restrict_resource,
                .function_value,
                .integer,
                .boolean,
                .unit,
                .local,
                .propagate,
                .wrap,
                .variant,
                .block_value,
                .unwrap,
                .replace,
                .length,
                .record,
                .update,
                .field,
                .unary,
                => {},
            }
        };
        // Ownership-bearing signatures and locals conservatively include their
        // fallback cleanup effect, including on traps and propagated errors.
    }
    try graph.infer();
    for (@constCast(program.functions), 0..) |*function, index| {
        function.policy.effects = graph.states[index].mask;
        const bound = function.policy.effect_bound orelse continue;
        const forbidden = function.policy.effects & ~bound.allowed;
        if (forbidden == 0) continue;
        for (std.meta.tags(sets.Effect)) |effect| {
            if (forbidden & sets.bit(effect) == 0) continue;
            var path: std.Io.Writer.Allocating = .init(allocator);
            defer path.deinit();
            path.writer.print("effect `{s}` exceeds declared bound: {s}", .{ @tagName(effect), function.name }) catch return error.OutOfMemory;
            var cursor = index;
            var steps: usize = 0;
            while (graph.states[cursor].witnesses[@backingInt(effect)].?.via) |callee| {
                path.writer.print(" -> {s}", .{program.functions[callee].name}) catch return error.OutOfMemory;
                cursor = callee;
                steps += 1;
                std.debug.assert(steps < program.functions.len);
            }
            const message = try allocator.dupe(u8, path.written());
            return sink.failRelated("E_EFFECT_BOUND", bound.span, message, .{ .span = graph.states[cursor].witnesses[@backingInt(effect)].?.span, .message = "effect originates at this operation or owned type" });
        }
    }
}

/// Resolved declaration edge collected while checking symbolic template bodies.
pub const AbstractCall = struct { caller: usize, callee: usize, span: Span };
/// Check abstract cleanup/call effects before any generic specialization exists.
pub fn checkAbstract(allocator: std.mem.Allocator, functions: []const @import("ast.zig").Function, masks: []const sets.Mask, calls: []const AbstractCall, sink: *diagnostic.Sink) diagnostic.Error!void {
    if (functions.len != masks.len) return error.InternalError;
    var graph = try Graph.init(allocator, functions.len);
    defer graph.deinit();
    for (functions, masks, 0..) |function, mask, index| {
        if (function.policy.host) |span| try seedHost(&graph, index, function.policy.effect_bound, span);
        for (std.meta.tags(sets.Effect)) |effect| {
            if (mask & sets.bit(effect) != 0) graph.direct(index, effect, function.name);
        }
    }
    for (calls) |edge| try graph.call(edge.caller, edge.callee, edge.span);
    try graph.infer();
    for (functions, 0..) |function, index| {
        const bound = function.policy.effect_bound orelse continue;
        const forbidden = graph.states[index].mask & ~bound.allowed;
        for (std.meta.tags(sets.Effect)) |effect| {
            if (forbidden & sets.bit(effect) == 0) continue;
            var origin = index;
            while (graph.states[origin].witnesses[@backingInt(effect)].?.via) |callee| origin = callee;
            const message = try std.fmt.allocPrint(sink.allocator, "effect `{s}` from an operation, owned cleanup or a reachable helper exceeds declared bound", .{@tagName(effect)});
            return sink.failRelated("E_EFFECT_BOUND", bound.span, message, .{ .span = graph.states[origin].witnesses[@backingInt(effect)].?.span, .message = "effect originates in this function's operations or owned types" });
        }
    }
}

/// Independently recompute effects from emitted operations, including all call forms.
pub fn validate(allocator: std.mem.Allocator, program: @import("bytecode_model.zig").Program) ValidateError!void {
    var graph = try Graph.init(allocator, program.functions.len);
    defer graph.deinit();
    const cleanup_masks = try cleanupMasks(allocator, program.records);
    defer allocator.free(cleanup_masks);
    for (program.functions, 0..) |function, index| {
        if (function.policy.host) |span| try seedHost(&graph, index, function.policy.effect_bound, span);
        try seedOwnership(&graph, index, function.signature.return_type, function.scope.locals, .{ .start = 0, .end = 0 }, cleanup_masks);
        for (function.scope.instructions) |instruction| switch (instruction.op) {
            .acquire_resource => |acquire| {
                const shape = typed.resultShape(acquire.output, program.records) orelse return error.InternalError;
                const kind = typed.resourceKind(shape.ok_type, program.records) orelse return error.InternalError;
                graph.direct(index, kind.effect(), instruction.span);
            },
            .complete_resource => |output| {
                const shape = typed.completionShape(output, program.records) orelse return error.InternalError;
                graph.direct(index, typed.resourceKind(shape.resource_type, program.records).?.effect(), instruction.span);
            },
            .resource_io => |io| {
                if (@backingInt(io.owner) >= function.scope.locals.len) return error.InternalError;
                const kind = typed.resourceKind(function.scope.locals[@backingInt(io.owner)].ty, program.records) orelse return error.InternalError;
                graph.direct(index, kind.effect(), instruction.span);
            },
            .environment_get => graph.direct(index, .environment, instruction.span),
            .external_read => |read| graph.direct(index, read.kind.effect(), instruction.span),
            .cast_integer => |ty| if (allocatingSequence(program.records, ty)) {
                graph.direct(index, .managed_allocation, instruction.span);
            },
            .make_record => |record| if (try managedType(program.records, record.ty)) {
                graph.direct(index, .managed_allocation, instruction.span);
            },
            .binary_integer => |binary| if (binary.op == .add and allocatingSequence(program.records, binary.ty)) {
                graph.direct(index, .managed_allocation, instruction.span);
            },
            .get_index => |ty| if (allocatingElement(program.records, ty)) {
                graph.direct(index, .managed_allocation, instruction.span);
            },
            .acquire_buffer => |ty| if (try managedType(program.records, ty)) graph.direct(index, .managed_allocation, instruction.span) else return error.InternalError,
            .buffer_operation => |op| {
                if (@backingInt(op.owner) >= function.scope.locals.len) return error.InternalError;
                const managed = try managedType(program.records, function.scope.locals[@backingInt(op.owner)].ty);
                const dictionary = program.records[function.scope.locals[@backingInt(op.owner)].ty.recordIndex()].collection.kind == .dictionary;
                if (managed and @import("buffer_operations.zig").managedAllocation(op.kind, dictionary)) {
                    graph.direct(index, .managed_allocation, instruction.span);
                }
            },
            .invoke => |ty| {
                const contract = @import("callables.zig").signature(ty, program.records) orelse return error.InternalError;
                inline for (std.meta.tags(sets.Effect)) |effect| if (contract.effects & sets.bit(effect) != 0) graph.direct(index, effect, instruction.span);
            },
            .call => |callee| try graph.call(index, @backingInt(callee), instruction.span),
            .arena_escape => graph.direct(index, .managed_allocation, instruction.span),
            .begin_arena,
            .end_arena,
            .restrict_resource,
            .function_value,
            .push_i64,
            .add_i64_checked,
            .sub_i64_checked,
            .mul_i64_checked,
            .div_i64_checked,
            .rem_i64_checked,
            .unary_float,
            .neg_i64_checked,
            .cmp_i64,
            .try_result,
            .push_bool,
            .push_unit,
            .push_integer,
            .wrap_domain,
            .make_variant,
            .switch_variant,
            .cmp_domain,
            .cmp_enum,
            .unwrap_domain,
            .neg_integer,
            .update_record,
            .get_field,
            .replace_index,
            .array_length,
            .move_local,
            .drop_local,
            .load_local,
            .store_local,
            .cmp_bool,
            .not_bool,
            .pop,
            .acknowledge,
            .jump,
            .jump_if_false,
            .assert_true,
            .ret,
            => {},
        };
    }
    try graph.infer();
    for (program.functions, graph.states) |function, state| {
        if (function.policy.effects != state.mask) return error.InternalError;
        if (function.policy.effect_bound) |bound| if (bound.allowed & ~sets.all != 0 or state.mask & ~bound.allowed != 0) return error.InternalError;
    }
}

test "effect lattice propagates independent effects through cycles without contaminating unrelated functions" {
    const t = std.testing;
    var graph = try Graph.init(t.allocator, 4);
    defer graph.deinit();
    const span: Span = .{ .start = 0, .end = 1 };
    try graph.call(0, 1, span);
    try graph.call(1, 2, span);
    try graph.call(2, 1, span);
    seedIndependentEffects(&graph, span);
    try graph.infer();
    for (graph.states[0..3]) |state| try t.expectEqual(sets.all & ~sets.bit(.environment), state.mask);
    try t.expectEqual(sets.bit(.environment), graph.states[3].mask);
    try t.expectEqual(@as(?usize, 1), graph.states[0].witnesses[@backingInt(sets.Effect.filesystem)].?.via);
    try t.expectEqual(@as(?usize, 2), graph.states[1].witnesses[@backingInt(sets.Effect.filesystem)].?.via);
}

fn typeMask(ty: typed.Type, masks: []const sets.Mask) error{InternalError}!sets.Mask {
    if (!ty.isAggregate()) return 0;
    if (ty.recordIndex() >= masks.len) return error.InternalError;
    return masks[ty.recordIndex()];
}
/// Compute fallback cleanup effects for each complete nominal type graph.
pub fn cleanupMasks(allocator: std.mem.Allocator, records: []const typed.Record) ValidateError![]sets.Mask {
    const masks = try allocator.alloc(sets.Mask, records.len);
    errdefer allocator.free(masks);
    @memset(masks, 0);
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, index| {
            var mask: sets.Mask = if (record.shape.resource) |kind| sets.bit(kind.effect()) else 0;
            if (record.shape.array) |array| {
                if (array.length != 0) mask |= try typeMask(array.element, masks);
            } else if (record.shape.variants) |variants| {
                for (variants.cases) |case| if (case.payload) |payload| {
                    mask |= try typeMask(payload, masks);
                };
            } else {
                for (record.fields) |field| {
                    mask |= try typeMask(field.ty, masks);
                }
            }
            if (mask != masks[index]) {
                masks[index] = mask;
                changed = true;
            }
        }
    }
    return masks;
}
fn seedOwnership(graph: *Graph, index: usize, result: ?typed.Type, locals: []const typed.Local, span: Span, masks: []const sets.Mask) !void {
    var mask: sets.Mask = if (result) |ty| try typeMask(ty, masks) else 0;
    for (locals) |local| {
        mask |= try typeMask(local.ty, masks);
    }
    for (std.meta.tags(sets.Effect)) |effect| if (mask & sets.bit(effect) != 0) {
        graph.direct(index, effect, span);
    };
}

fn seedIndependentEffects(graph: *Graph, span: Span) void {
    for (std.meta.tags(sets.Effect)) |effect| graph.direct(if (effect == .environment) 3 else 2, effect, span);
}

fn seedHost(graph: *Graph, index: usize, bound: ?sets.Bound, span: Span) error{InternalError}!void {
    const allowed = (bound orelse return error.InternalError).allowed;
    if (allowed & ~sets.all != 0 or allowed & sets.bit(.host) == 0) return error.InternalError;
    for (std.meta.tags(sets.Effect)) |effect| if (allowed & sets.bit(effect) != 0) graph.direct(index, effect, span);
}

fn managedType(records: []const typed.Record, ty: typed.Type) ValidateError!bool {
    if (!ty.isAggregate()) return error.InternalError;
    if (ty.recordIndex() >= records.len) return error.InternalError;
    return records[ty.recordIndex()].managed;
}
