//! Monotone effect inference over resolved calls, with finite witness paths.
/// Failures returned by validate; callers must handle these boundary errors.
pub const ValidateError = error{
    InternalError,
    OutOfMemory,
};
/// Stable diagnostic code for an exported declaration without a declared ceiling.
pub const effect_ceiling = "E_EFFECT_CEILING";

const std = @import("std");
const typed = @import("typed.zig");
const sets = @import("effect_set.zig");
const Span = @import("source.zig").Span;
const diagnostic = @import("diagnostic.zig");
const mutation = @import("mutation.zig");
const bytecode_model = @import("bytecode_model.zig");
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
/// Inferred per-function mutation footprint and return-origin bound.
const Facts = struct {
    mutates: []const u16,
    return_origin: typed.ReturnOrigin,
    mutation_facts: typed.MutationFacts,
};

const ReturnContext = struct {
    allocator: std.mem.Allocator,
    positions: *std.ArrayList(u16),
    saw_params: *bool,
    unknown: *bool,
};

/// Record the sound return-origin contribution of one returned expression.
fn returnContribution(program: typed.Program, function: typed.Function, value: typed.NodeId, ctx: *ReturnContext) error{OutOfMemory}!void {
    const node = program.nodes[@backingInt(value)];
    if (!node.ty.isAggregate()) return;
    if (mutation.nodeInput(program, function, value)) |position| {
        ctx.saw_params.* = true;
        try mutation.insertPosition(ctx.positions, ctx.allocator, position);
        return;
    }
    switch (node.data) {
        .integer, .boolean, .unit, .function_value, .environment_get, .external_read => {},
        .local, .call, .invoke, .complete_resource, .acquire_resource, .acquire_buffer, .array, .record, .variant, .update => {
            if (node.ty.isAggregate()) ctx.unknown.* = true;
        },
        .binary, .unary, .cast, .wrap, .unwrap, .length, .field, .index, .replace, .buffer_operation, .file_access, .file_method, .print, .arena_escape, .block_value, .propagate, .restrict_resource => {
            if (node.ty.isAggregate()) ctx.unknown.* = true;
        },
        .resource_io => {
            if (node.ty.isAggregate()) ctx.unknown.* = true;
        },
    }
}

/// Whether a type is a managed aggregate whose fresh outer identity can be proven here.
fn isManagedAggregate(program: typed.Program, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < program.records.len and program.records[ty.recordIndex()].managed;
}

/// Whether a returned local is initialized from a definitely fresh constructed value.
fn blockValueFresh(program: typed.Program, body: typed.StatementId, value: typed.NodeId, depth: usize) bool {
    if (depth == 256) return false;
    const returned = program.nodes[@backingInt(value)];
    if (returned.data != .local) return false;
    const block = program.statements[@backingInt(body)].data.block;
    for (block) |statement_id| {
        const statement = program.statements[@backingInt(statement_id)];
        switch (statement.data) {
            .initialize => |store| if (store.slot == returned.data.local) return isFreshValue(program, store.value, depth + 1),
            else => {},
        }
    }
    return false;
}

/// Whether an expression constructs a fresh outer managed value below this pass.
fn isFreshValue(program: typed.Program, value: typed.NodeId, depth: usize) bool {
    if (depth == 256) return false;
    const node = program.nodes[@backingInt(value)];
    if (!isManagedAggregate(program, node.ty)) return false;
    return switch (node.data) {
        .acquire_buffer => true,
        .array, .record => true,
        .block_value => |block| blockValueFresh(program, block.body, block.value, depth + 1),
        else => false,
    };
}

/// Resolve a value's direct parameter origin through simple local copies.
fn valueOrigin(program: typed.Program, function: typed.Function, value: typed.NodeId, origins: []const ?u16, depth: usize) ?u16 {
    if (depth == 256) return null;
    const node = program.nodes[@backingInt(value)];
    switch (node.data) {
        .local => |slot| {
            const index = @backingInt(slot);
            if (index < function.signature.parameter_count) return @intCast(index);
            return if (index < origins.len) origins[index] else null;
        },
        .field => |field| return valueOrigin(program, function, field.base, origins, depth + 1),
        .index => |index| return valueOrigin(program, function, index.base, origins, depth + 1),
        .cast, .wrap, .unwrap => |operand| return valueOrigin(program, function, operand, origins, depth + 1),
        .propagate => |propagate| return valueOrigin(program, function, propagate.value, origins, depth + 1),
        .block_value => |block| return valueOrigin(program, function, block.value, origins, depth + 1),
        else => return mutation.nodeInput(program, function, value),
    }
}

const ExpressionMutationContext = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    fresh: []const bool,
    origins: []const ?u16,
    positions: *std.ArrayList(u16),
};

/// Record one expression write unless the receiver is a proven-fresh local.
/// Returns true when a managed receiver write was found, fresh-local or not.
fn recordExpressionMutation(ctx: *const ExpressionMutationContext, node: typed.Node) error{OutOfMemory}!?bool {
    const witness = mutation.typedNode(ctx.program, ctx.function, node) orelse return null;
    if (witness.operation != .receiver_write) return null;
    const owner_is_fresh = if (witness.owner) |owner| @backingInt(owner) < ctx.fresh.len and ctx.fresh[@backingInt(owner)] else false;
    if (!owner_is_fresh) {
        const input = witness.input orelse if (witness.owner) |owner| ctx.origins[@backingInt(owner)] else null;
        if (input) |position| try mutation.insertPosition(ctx.positions, ctx.allocator, position);
    }
    return !owner_is_fresh;
}

/// Infer one function's direct write footprint and return-origin bound from its checked body.
fn inferFacts(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function) error{ OutOfMemory, InternalError }!Facts {
    var mutate_positions: std.ArrayList(u16) = .empty;
    defer mutate_positions.deinit(allocator);
    var return_positions: std.ArrayList(u16) = .empty;
    defer return_positions.deinit(allocator);
    var saw_params = false;
    var saw_write = false;
    var saw_external = false;
    var unknown = function.policy.host != null or function.policy.c_abi;
    const fresh = try allocator.alloc(bool, function.scope.locals.len);
    defer allocator.free(fresh);
    @memset(fresh, false);
    const origins = try allocator.alloc(?u16, function.scope.locals.len);
    defer allocator.free(origins);
    @memset(origins, null);
    var walker = try @import("typed_walk.zig").Walker.init(allocator, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .expression => |id| {
            const write = try recordExpressionMutation(&.{
                .allocator = allocator,
                .program = program,
                .function = function,
                .fresh = fresh,
                .origins = origins,
                .positions = &mutate_positions,
            }, program.nodes[@backingInt(id)]);
            if (write) |external| {
                saw_write = true;
                saw_external = external or saw_external;
            }
        },
        .statement => |id| {
            const statement = program.statements[@backingInt(id)];
            switch (statement.data) {
                .initialize => |store| if (@backingInt(store.slot) < fresh.len) {
                    fresh[@backingInt(store.slot)] = isFreshValue(program, store.value, 0);
                    origins[@backingInt(store.slot)] = valueOrigin(program, function, store.value, origins, 0);
                },
                .assign => |store| if (@backingInt(store.slot) < fresh.len) {
                    fresh[@backingInt(store.slot)] = isFreshValue(program, store.value, 0);
                    origins[@backingInt(store.slot)] = valueOrigin(program, function, store.value, origins, 0);
                },
                .ret => |value| {
                    var ctx: ReturnContext = .{
                        .allocator = allocator,
                        .positions = &return_positions,
                        .saw_params = &saw_params,
                        .unknown = &unknown,
                    };
                    try returnContribution(program, function, value, &ctx);
                },
                else => {},
            }
        },
    };
    const mutates = try mutate_positions.toOwnedSlice(allocator);
    const return_origin: typed.ReturnOrigin = if (unknown) .unknown else if (saw_params) .{ .params = try return_positions.toOwnedSlice(allocator) } else .fresh;
    return .{ .mutates = mutates, .return_origin = return_origin, .mutation_facts = .{ .writes = saw_write, .external = saw_external } };
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

/// Canonical source spelling of one inferred effect set, e.g. `effects(clock)`.
fn effectsText(allocator: std.mem.Allocator, mask: sets.Mask) diagnostic.Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    var separator = false;
    for (std.meta.tags(sets.Effect)) |effect| {
        if (mask & sets.bit(effect) == 0) continue;
        if (separator) list.appendSlice(allocator, ", ") catch return error.OutOfMemory;
        list.appendSlice(allocator, @tagName(effect)) catch return error.OutOfMemory;
        separator = true;
    }
    return std.fmt.allocPrint(allocator, "effects({s})", .{list.items}) catch return error.OutOfMemory;
}

/// Build the located diagnostic text for an exported body without a ceiling.
/// The list is the inferred transitive effect set, described as a suggested
/// upper bound so callers can copy a narrow contract rather than `effects(all)`.
fn suggestedCeiling(allocator: std.mem.Allocator, mask: sets.Mask) diagnostic.Error![]const u8 {
    const bound = try effectsText(allocator, mask);
    return std.fmt.allocPrint(allocator, "exported function requires an explicit effect ceiling; the body's compiler-derived bound is {s}", .{bound}) catch return error.OutOfMemory;
}

/// Bundles the inferred graph with the program it indexes for violation reports.
const BoundContext = struct { program: typed.Program, graph: *const Graph };

/// Append one `E_EFFECT_BOUND` diagnostic together with the inferred bound and
/// the originating witness. Callers collect every violation before failing so a
/// single migration/diagnostic run lists all mismatched declarations.
fn appendBoundViolation(allocator: std.mem.Allocator, ctx: BoundContext, index: usize, effect: sets.Effect, bound: sets.Bound, sink: *diagnostic.Sink) diagnostic.Error!void {
    const program = ctx.program;
    const graph = ctx.graph;
    const function = program.functions[index];
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
    const inferred = try effectsText(allocator, graph.states[index].mask);
    path.writer.print("; inferred bound is {s}", .{inferred}) catch return error.OutOfMemory;
    const message = allocator.dupe(u8, path.written()) catch return error.OutOfMemory;
    sink.items.append(allocator, .{
        .code = "E_EFFECT_BOUND",
        .span = bound.span,
        .message = message,
        .related = .{ .span = graph.states[cursor].witnesses[@backingInt(effect)].?.span, .message = "effect originates at this operation or owned type" },
    }) catch return error.OutOfMemory;
}

/// Report every exported declaration that lacks an explicit effect ceiling.
fn reportMissingCeilings(
    allocator: std.mem.Allocator,
    program: typed.Program,
    graph: *const Graph,
    exported: []const bool,
    sink: *diagnostic.Sink,
) diagnostic.Error!bool {
    var missing = false;
    for (program.functions, 0..) |function, index| {
        if (index >= exported.len or !exported[index]) continue;
        if (function.policy.effect_bound != null) continue;
        var suggested = graph.states[index].mask;
        if (function.signature.mutation_facts.external) suggested |= sets.bit(.mutation);
        const message = try suggestedCeiling(allocator, suggested);
        sink.items.append(allocator, .{ .code = effect_ceiling, .span = function.declaration, .message = message }) catch return error.OutOfMemory;
        missing = true;
    }
    return missing;
}

/// Infer transitive effects and reject function bodies that exceed declared effect bounds.
pub fn check(allocator: std.mem.Allocator, program: typed.Program, exported: []const bool, sink: *diagnostic.Sink) diagnostic.Error!void {
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
        const facts = inferFacts(allocator, program, function) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InternalError => return error.InternalError,
        };
        const mutable = @constCast(&program.functions[index]);
        mutable.signature.mutates = facts.mutates;
        mutable.signature.return_origin = facts.return_origin;
        mutable.signature.mutation_facts = facts.mutation_facts;
        var walker = try @import("typed_walk.zig").Walker.init(allocator, program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| if (item == .expression) {
            const node = program.nodes[@backingInt(item.expression)];
            switch (node.data) {
                .acquire_resource => graph.direct(index, typed.resourceKind(typed.resultShape(node.ty, program.records).?.ok_type, program.records).?.effect(), node.span),
                .complete_resource => graph.direct(index, typed.resourceKind(typed.completionShape(node.ty, program.records).?.resource_type, program.records).?.effect(), node.span),
                .resource_io => |io| graph.direct(index, typed.resourceKind(function.scope.locals[@backingInt(io.owner)].ty, program.records).?.effect(), node.span),
                .environment_get => graph.direct(index, .environment, node.span),
                .print => graph.direct(index, .output, node.span),
                .file_access, .file_method => graph.direct(index, .filesystem, node.span),
                .external_read => |read| graph.direct(index, read.kind.effect(), node.span),
                .cast => if (allocatingSequence(program.records, node.ty)) {
                    graph.direct(index, .managed_allocation, node.span);
                },
                .array, .record => if (node.ty.isAggregate() and program.records[node.ty.recordIndex()].managed) {
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
                    inline for (std.meta.tags(sets.Effect)) |effect| if (effect != .mutation and contract.effects & sets.bit(effect) != 0) graph.direct(index, effect, node.span);
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
    // M2: enforce the checked call-duration mutation guarantee. This computes
    // transitive write footprints and return-alias bounds to a fixed point,
    // attributes writes to caller inputs through aliases and calls, and rejects
    // writes that exceed a declared ceiling or unknown-overlap call arguments.
    const mutation_violated = @import("origins.zig").check(allocator, program, exported, sink) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    // E2: every exported declaration must publish an explicit ceiling. The
    // suggestion is derived from this body's inferred transitive effects (a
    // bound, never an unconditional `effects(all)`), and remains distinct from
    // the raw inferred mask stored below for diagnostics/cacheability.
    const missing_ceilings = try reportMissingCeilings(allocator, program, &graph, exported, sink);
    for (@constCast(program.functions), 0..) |*function, index| {
        function.policy.effects = graph.states[index].mask;
        if (function.signature.mutation_facts.external) function.policy.effects |= sets.bit(.mutation);
    }
    var violated = mutation_violated or missing_ceilings;
    for (program.functions, 0..) |function, index| {
        const bound = function.policy.effect_bound orelse continue;
        const forbidden = function.policy.effects & ~bound.allowed;
        if (forbidden == 0) continue;
        for (std.meta.tags(sets.Effect)) |effect| {
            // `mutation` permission and footprint violations are reported by
            // origins.check with argument witnesses; the effect graph does not
            // carry a mutation witness.
            if (effect == .mutation) continue;
            if (forbidden & sets.bit(effect) == 0) continue;
            try appendBoundViolation(allocator, .{ .program = program, .graph = &graph }, index, effect, bound, sink);
            violated = true;
        }
    }
    if (violated) return error.SourceError;
}

/// Resolved declaration edge collected while checking symbolic template bodies.
pub const AbstractCall = struct { caller: usize, callee: usize, span: Span };
/// Check abstract cleanup/call effects before any generic specialization exists.
pub fn checkAbstract(allocator: std.mem.Allocator, functions: []const @import("ast.zig").Function, masks: []const sets.Mask, calls: []const AbstractCall, exported: []const bool, sink: *diagnostic.Sink) diagnostic.Error!void {
    if (functions.len != masks.len or functions.len != exported.len) return error.InternalError;
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
    var missing_ceiling = false;
    for (functions, 0..) |function, index| {
        if (!exported[index] or function.policy.effect_bound != null) continue;
        var suggested = graph.states[index].mask;
        if (function.signature.inferred_mutation_writes) suggested |= sets.bit(.mutation);
        const message = try suggestedCeiling(allocator, suggested);
        sink.items.append(allocator, .{ .code = effect_ceiling, .span = function.name, .message = message }) catch return error.OutOfMemory;
        missing_ceiling = true;
    }
    var violated = missing_ceiling;
    for (functions, 0..) |function, index| {
        const bound = function.policy.effect_bound orelse continue;
        const forbidden = graph.states[index].mask & ~bound.allowed;
        for (std.meta.tags(sets.Effect)) |effect| {
            if (forbidden & sets.bit(effect) == 0) continue;
            var origin = index;
            while (graph.states[origin].witnesses[@backingInt(effect)].?.via) |callee| origin = callee;
            const inferred = try effectsText(sink.allocator, graph.states[index].mask);
            const message = try std.fmt.allocPrint(sink.allocator, "effect `{s}` from an operation, owned cleanup or a reachable helper exceeds declared bound; inferred bound is {s}", .{ @tagName(effect), inferred });
            sink.items.append(sink.allocator, .{
                .code = "E_EFFECT_BOUND",
                .span = bound.span,
                .message = message,
                .related = .{ .span = graph.states[origin].witnesses[@backingInt(effect)].?.span, .message = "effect originates in this function's operations or owned types" },
            }) catch return error.OutOfMemory;
            violated = true;
        }
    }
    // M2: an abstract generic body that writes an input must publish the same
    // `effects(mutation)` and `mutates(...)` permission an ordinary body needs.
    for (functions) |function| {
        // Ordinary bodies are enforced by the concrete origin pass with full
        // freshness and call substitution; only abstract generic templates are
        // checked here.
        if (function.signature.type_parameters.len == 0) continue;
        // The abstract classifier does not track fresh local storage, so an
        // unattributed write may be a local builder. Concrete specializations
        // re-check those bodies with full origin analysis; only writes tied to a
        // declared input position are enforced here.
        const inferred = positionMask(function.signature.inferred_mutates);
        if (inferred == 0) continue;
        const bound = function.policy.effect_bound orelse continue;
        const has_permission = bound.allowed & sets.bit(.mutation) != 0;
        const permitted = positionMask(function.signature.mutates);
        if (has_permission and inferred & ~permitted == 0) continue;
        sink.items.append(sink.allocator, .{
            .code = "E_MUTATION_PERMISSION",
            .span = bound.span,
            .message = "managed write in a generic body exceeds its declared mutation contract",
        }) catch return error.OutOfMemory;
        violated = true;
    }
    if (violated) return error.SourceError;
}

fn positionMask(positions: []const u16) sets.Mask {
    var mask: u16 = 0;
    for (positions) |position| mask |= @as(u16, 1) << @intCast(position);
    return mask;
}

/// Check one instruction-level mutation witness against the checked summary.
fn instructionSummaryValid(function: bytecode_model.Function, witness: mutation.Witness) bool {
    if (witness.operation != .receiver_write) return true;
    if (!function.signature.mutation_facts.writes) return false;
    const input = witness.input orelse return true;
    return containsPosition(function.signature.mutates, input);
}

/// Seed the independently recomputed effects contributed by one instruction.
fn seedInstructionEffects(
    program: bytecode_model.Program,
    function: bytecode_model.Function,
    graph: *Graph,
    index: usize,
    instruction: bytecode_model.Instruction,
) ValidateError!void {
    switch (instruction.op) {
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
        .print => graph.direct(index, .output, instruction.span),
        .file_access, .file_method => graph.direct(index, .filesystem, instruction.span),
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
            inline for (std.meta.tags(sets.Effect)) |effect| if (effect != .mutation and contract.effects & sets.bit(effect) != 0) graph.direct(index, effect, instruction.span);
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
    }
}

/// Independently recompute effects from emitted operations, including all call forms.
pub fn validate(allocator: std.mem.Allocator, program: bytecode_model.Program) ValidateError!void {
    var graph = try Graph.init(allocator, program.functions.len);
    defer graph.deinit();
    const cleanup_masks = try cleanupMasks(allocator, program.records);
    defer allocator.free(cleanup_masks);
    for (program.functions, 0..) |function, index| {
        if (function.policy.host) |span| try seedHost(&graph, index, function.policy.effect_bound, span);
        try seedOwnership(&graph, index, function.signature.return_type, function.scope.locals, .{ .start = 0, .end = 0 }, cleanup_masks);
        for (function.scope.instructions) |instruction| {
            if (mutation.instruction(program, function, instruction.op, instruction.span)) |witness| {
                if (!instructionSummaryValid(function, witness)) return error.InternalError;
            }
            try seedInstructionEffects(program, function, &graph, index, instruction);
        }
        if (!normalizedPositions(function.signature.mutates, function.signature.parameter_count)) return error.InternalError;
        if (!positionsInRange(function.signature.declared_mutates, function.signature.parameter_count)) return error.InternalError;
        if (function.policy.effect_bound) |bound| {
            const declared = positionMask(function.signature.declared_mutates);
            if (positionMask(function.signature.mutates) & ~declared != 0) return error.InternalError;
            if (function.signature.mutation_facts.external and bound.allowed & sets.bit(.mutation) == 0) return error.InternalError;
        }
        switch (function.signature.return_origin) {
            .params => |positions| if (!normalizedPositions(positions, function.signature.parameter_count)) return error.InternalError,
            else => {},
        }
    }
    try graph.infer();
    for (program.functions, graph.states) |function, state| {
        const masked_state = state.mask & ~sets.bit(.mutation);
        const masked_policy = function.policy.effects & ~sets.bit(.mutation);
        if (masked_policy != masked_state) return error.InternalError;
        if (function.policy.effect_bound) |bound| if (bound.allowed & ~sets.all != 0 or masked_state & ~bound.allowed != 0) return error.InternalError;
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

fn containsPosition(positions: []const u16, position: u16) bool {
    for (positions) |candidate| if (candidate == position) return true;
    return false;
}

fn positionsInRange(positions: []const u16, parameter_count: usize) bool {
    for (positions) |position| if (position >= parameter_count) return false;
    return true;
}

fn normalizedPositions(positions: []const u16, parameter_count: usize) bool {
    if (!positionsInRange(positions, parameter_count)) return false;
    for (positions, 0..) |position, i| {
        if (i != 0 and positions[i - 1] >= position) return false;
    }
    return true;
}

fn stateBit(mask: sets.Mask, effect: sets.Effect) sets.Mask {
    return mask & sets.bit(effect);
}

fn managedType(records: []const typed.Record, ty: typed.Type) ValidateError!bool {
    if (!ty.isAggregate()) return error.InternalError;
    if (ty.recordIndex() >= records.len) return error.InternalError;
    return records[ty.recordIndex()].managed;
}
