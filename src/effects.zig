//! Monotone effect inference over resolved calls, with finite witness paths.
const std = @import("std");
const typed = @import("typed.zig");
const sets = @import("effect_set.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const Witness = struct { span: Span, via: ?usize = null };
const Edge = struct { caller: usize, span: Span };
const State = struct { mask: sets.Mask = 0, witnesses: [6]?Witness = @splat(null), callers: std.ArrayList(Edge) = .empty, queued: bool = false };
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

pub fn check(allocator: std.mem.Allocator, program: typed.Program, sink: *diagnostic.Sink) diagnostic.Error!void {
    var graph = try Graph.init(allocator, program.functions.len);
    defer graph.deinit();
    const cleanup_masks = cleanupMasks(allocator, program.records) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => unreachable,
    };
    defer allocator.free(cleanup_masks);
    for (program.functions, 0..) |function, index| {
        seedOwnership(&graph, index, function.return_type, function.locals, function.declaration, cleanup_masks) catch unreachable;
        var walker = try @import("typed_walk.zig").Walker.init(allocator, program, function.body);
        defer walker.deinit();
        while (try walker.next()) |item| if (item == .expression) {
            const node = program.nodes[@backingInt(item.expression)];
            switch (node.data) {
                .acquire_resource => graph.direct(index, typed.resourceKind(typed.resultShape(node.ty, program.records).?.ok_type, program.records).?.effect(), node.span),
                .complete_resource => graph.direct(index, typed.resourceKind(typed.completionShape(node.ty, program.records).?.resource_type, program.records).?.effect(), node.span),
                .resource_io => |io| graph.direct(index, typed.resourceKind(function.locals[@backingInt(io.owner)].ty, program.records).?.effect(), node.span),
                .environment_get => graph.direct(index, .environment, node.span),
                .external_read => |read| graph.direct(index, read.kind.effect(), node.span),
                .acquire_buffer => graph.direct(index, .allocation, node.span),
                .buffer_operation => |op| if (bufferAllocates(op.kind)) {
                    graph.direct(index, .allocation, node.span);
                },
                .call => |call| graph.call(index, @backingInt(call.function), node.span) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InternalError => unreachable, // Resolved typed function identity.
                },
                .restrict_resource, .integer, .boolean, .local, .read_ref, .read_field, .propagate, .read_slice, .len_slice, .cast, .wrap, .variant, .unwrap, .array, .index, .replace, .length, .record, .update, .field, .unary, .binary => {},
            }
        };
        // Ownership-bearing signatures and locals conservatively include their
        // fallback cleanup effect, including on traps and propagated errors.
    }
    try graph.infer();
    for (@constCast(program.functions), 0..) |*function, index| {
        function.effects = graph.states[index].mask;
        const bound = function.effect_bound orelse continue;
        const forbidden = function.effects & ~bound.allowed;
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

/// Independently recompute effects from emitted operations, including all call forms.
pub fn validate(allocator: std.mem.Allocator, program: @import("bytecode.zig").Program) !void {
    var graph = try Graph.init(allocator, program.functions.len);
    defer graph.deinit();
    const cleanup_masks = try cleanupMasks(allocator, program.records);
    defer allocator.free(cleanup_masks);
    for (program.functions, 0..) |function, index| {
        try seedOwnership(&graph, index, function.return_type, function.locals, .{ .start = 0, .end = 0 }, cleanup_masks);
        for (function.instructions) |instruction| switch (instruction.op) {
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
                if (@backingInt(io.owner) >= function.locals.len) return error.InternalError;
                const kind = typed.resourceKind(function.locals[@backingInt(io.owner)].ty, program.records) orelse return error.InternalError;
                graph.direct(index, kind.effect(), instruction.span);
            },
            .environment_get => graph.direct(index, .environment, instruction.span),
            .external_read => |read| graph.direct(index, read.kind.effect(), instruction.span),
            .acquire_buffer => graph.direct(index, .allocation, instruction.span),
            .buffer_operation => |op| if (bufferAllocates(op.kind)) {
                graph.direct(index, .allocation, instruction.span);
            },
            .call => |callee| try graph.call(index, @backingInt(callee), instruction.span),
            .call_refs => |call| try graph.call(index, @backingInt(call.function), instruction.span),
            .call_borrow => |call| try graph.call(index, @backingInt(call.function), instruction.span),
            .restrict_resource, .push_i64, .add_i64_checked, .sub_i64_checked, .mul_i64_checked, .div_i64_checked, .rem_i64_checked, .neg_i64_checked, .cmp_i64, .try_result, .push_bool, .push_integer, .cast_integer, .wrap_domain, .make_variant, .switch_variant, .cmp_enum, .unwrap_domain, .neg_integer, .binary_integer, .make_record, .update_record, .get_field, .get_index, .replace_index, .array_length, .begin_borrow, .begin_slice, .read_slice, .write_slice, .len_slice, .end_borrow, .read_ref, .read_field, .write_ref, .move_local, .drop_local, .load_local, .store_local, .cmp_bool, .not_bool, .pop, .acknowledge, .jump, .jump_if_false, .ret, .ret_ref, .capture_ref => {},
        };
    }
    try graph.infer();
    for (program.functions, graph.states) |function, state| {
        if (function.effects != state.mask) return error.InternalError;
        if (function.effect_bound) |bound| if (bound.allowed & ~sets.all != 0 or state.mask & ~bound.allowed != 0) return error.InternalError;
    }
}

fn bufferAllocates(kind: @import("buffer_operations.zig").Kind) bool {
    return switch (kind) {
        .reserve => true,
        .length, .capacity, .read, .write, .append, .resize => false,
    };
}

test "effect lattice propagates independent effects through cycles without contaminating unrelated functions" {
    const t = std.testing;
    var graph = try Graph.init(t.allocator, 4);
    defer graph.deinit();
    const span: Span = .{ .start = 0, .end = 1 };
    try graph.call(0, 1, span);
    try graph.call(1, 2, span);
    try graph.call(2, 1, span);
    for (std.meta.tags(sets.Effect)) |effect| graph.direct(if (effect == .environment) 3 else 2, effect, span);
    try graph.infer();
    for (graph.states[0..3]) |state| try t.expectEqual(sets.all & ~sets.bit(.environment), state.mask);
    try t.expectEqual(sets.bit(.environment), graph.states[3].mask);
    try t.expectEqual(@as(?usize, 1), graph.states[0].witnesses[@backingInt(sets.Effect.allocation)].?.via);
    try t.expectEqual(@as(?usize, 2), graph.states[1].witnesses[@backingInt(sets.Effect.allocation)].?.via);
}

fn typeMask(ty: typed.Type, masks: []const sets.Mask) error{InternalError}!sets.Mask {
    if (!ty.isAggregate()) return 0;
    if (ty.recordIndex() >= masks.len) return error.InternalError;
    return masks[ty.recordIndex()];
}
fn cleanupMasks(allocator: std.mem.Allocator, records: []const typed.Record) ![]sets.Mask {
    const masks = try allocator.alloc(sets.Mask, records.len);
    errdefer allocator.free(masks);
    @memset(masks, 0);
    var changed = true;
    while (changed) {
        changed = false;
        for (records, 0..) |record, index| {
            var mask: sets.Mask = if (record.resource) |kind| sets.bit(kind.effect()) else 0;
            if (record.array) |array| {
                if (array.length != 0) mask |= try typeMask(array.element, masks);
            } else if (record.variants) |variants| {
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
fn seedOwnership(graph: *Graph, index: usize, result: typed.Type, locals: []const typed.Local, span: Span, masks: []const sets.Mask) !void {
    var mask = try typeMask(result, masks);
    for (locals) |local| mask |= try typeMask(local.ty, masks);
    for (std.meta.tags(sets.Effect)) |effect| if (mask & sets.bit(effect) != 0) {
        graph.direct(index, effect, span);
    };
}
