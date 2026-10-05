//! Monotone effect inference over resolved calls, with finite witness paths.
/// Failures returned by validate; callers must handle these boundary errors.
pub const ValidateError = error{
    InternalError,
    OutOfMemory,
};
/// Diagnostic code for a body that exceeds the ceiling its signature implies.
const bound_code = "E_EFFECT_BOUND";
/// Diagnostic code for a contract condition with an effect beyond allocation.
const contract_effect_code = "E_CONTRACT_EFFECT";
/// Diagnostic code for a clause that names an effect no parameter supplies.
const unsupplied_clause_code = "E_DERIVED_EFFECTS";
/// Diagnostic code for a clause that restates the ceiling its parameters imply.
const restating_clause_code = "W_DERIVED_EFFECTS";
/// Diagnostic code for a capability parameter the body never reads.
pub const unused_capability_code = "E_UNUSED_CAPABILITY";
const std = @import("std");
const typed = @import("typed.zig");
const sets = @import("effect_set.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const Span = source.Span;
const diagnostic = @import("diagnostic.zig");
const mutation = @import("mutation.zig");
const origin_pass = @import("origins.zig");
const bytecode_model = @import("bytecode_model.zig");
const callables = @import("callables.zig");
const typed_walk = @import("typed_walk.zig");
const entry_adapter = @import("entry_adapter.zig");
const mut_abi = @import("mut_abi.zig");
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
/// Whether a managed aggregate literal allocates backing storage. A compile-time
/// `str` literal is an immutable constant whose codepoints the checker already
/// materialized, so it contributes no `managed_allocation`; a computed string
/// (concatenation, slice, conversion) still does through its own operation.
fn literalAllocates(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    return record.managed and record.collection.kind != .string;
}
/// Inferred per-function mutation footprint and return-origin bound.
const Facts = struct {
    mutates: []const u16,
    return_origin: typed.ReturnOrigin,
    inferred: typed.InferredFacts,
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
        .integer, .boolean, .unit, .blob, .function_value, .environment_get, .environment_only, .environment_names, .external_read, .host_resource, .stand_in => {},
        .local, .call, .invoke, .complete_resource, .acquire_resource, .acquire_buffer, .array, .record, .variant, .update => {
            if (node.ty.isAggregate()) ctx.unknown.* = true;
        },
        .binary, .unary, .cast, .wrap, .unwrap, .length, .field, .index, .replace, .buffer_operation, .file_access, .file_method, .print, .stream_write, .arena_escape, .block_value, .propagate, .restrict_resource, .dir_resource => {
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
        .array, .record, .blob => true,
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

/// The parameter position an assignment writes through: fixed-array elements
/// and whole `mut` record or collection variables reach caller storage.
fn elementWriteInput(program: typed.Program, function: typed.Function, statement: typed.Statement) ?u16 {
    if (statement.data != .assign) return null;
    const store = statement.data.assign;
    const slot = @backingInt(store.slot);
    if (slot >= function.signature.parameter_count) return null;
    const ty = function.scope.locals[slot].ty;
    const array_write = store.element and typed.referenceArray(program.records, ty);
    const caller_write = std.mem.indexOfScalar(u16, function.signature.declared_mutates, @intCast(slot)) != null and
        (typed.referenceRecord(program.records, ty) or mut_abi.collection(program.records, ty));
    if (!array_write and !caller_write) return null;
    return @intCast(slot);
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
    var walker = try typed_walk.Walker.init(allocator, program, function.scope.body);
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
            if (elementWriteInput(program, function, statement)) |position| {
                saw_write = true;
                saw_external = true;
                try mutation.insertPosition(&mutate_positions, allocator, position);
            }
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
    return .{ .mutates = mutates, .return_origin = return_origin, .inferred = .{ .writes = saw_write, .external = saw_external } };
}

const State = struct {
    mask: sets.Mask = 0,
    /// Effects that never leave this function: see `containedEffects`.
    contained: sets.Mask = 0,
    witnesses: [std.meta.tags(sets.Effect).len]?Witness = @splat(null),
    callers: std.ArrayList(Edge) = .empty,
    queued: bool = false,
};
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
        if (state.contained & sets.bit(effect) != 0) return;
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
                const added = effects & ~caller.mask & ~caller.contained;
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

/// The effect one capability parameter type permits, or null for a value type.
fn capabilityEffect(ty: typed.Type) ?sets.Effect {
    return switch (ty.capabilityIndex() orelse return null) {
        0 => .clock,
        1 => .random,
        2 => .filesystem,
        3 => .network,
        4 => .environment,
        5 => .output,
        6 => .host,
        else => null,
    };
}

/// The parameter declaration that would supply one effect, spelled as the paste
/// a rejection asks for. `managed_allocation` is ambient, so nothing supplies it
/// and the table has no entry: it is never an unsupplied effect.
pub fn supplyingParameter(effect: sets.Effect) ?[]const u8 {
    return switch (effect) {
        .filesystem => "fs: Filesystem",
        .network => "net: Network",
        .clock => "clock: Clock",
        .random => "entropy: Entropy",
        .environment => "env: Environment",
        .host => "host: Host",
        .output => "out: Stream",
        .mutation => "changed: mut T",
        .managed_allocation => null,
    };
}

/// Walk one type for the effects it carries. `ownership_only` reads just the
/// external resource families — what dropping the value needs — while the
/// authority walk also adds capability effects and bounded callback ceilings.
///
/// `path` holds the types on the current walk, so a shape that reaches itself
/// (a `class` node holding a union that holds the class again) contributes each
/// type once instead of expanding every path: the union of the effects a type
/// carries is the same however many times the walk arrives at it.
fn walkTypeEffects(
    comptime ownership_only: bool,
    records: []const typed.Record,
    ty: typed.Type,
    path: *[64]typed.Type,
    depth: usize,
) sets.Mask {
    var mask: sets.Mask = 0;
    if (!ownership_only) {
        // A capability and a callback are builtins rather than catalog records,
        // so both are read before the aggregate walk below.
        if (capabilityEffect(ty)) |effect| mask |= sets.bit(effect);
        if (callables.signature(ty, records)) |contract| mask |= callbackContribution(contract);
    }
    if (depth == path.len or !ty.isAggregate() or ty.recordIndex() >= records.len) return mask;
    for (path[0..depth]) |seen| if (seen == ty) return mask;
    path[depth] = ty;
    const record = records[ty.recordIndex()];
    if (record.shape.resource) |kind| mask |= sets.bit(kind.effect());
    if (record.shape.array) |array| {
        if (array.length != 0) mask |= walkTypeEffects(ownership_only, records, array.element, path, depth + 1);
    } else if (record.shape.variants) |variants| {
        for (variants.cases) |case| {
            if (case.payload) |payload| mask |= walkTypeEffects(ownership_only, records, payload, path, depth + 1);
        }
    } else if (record.contract.callback == null) {
        for (record.fields) |field| {
            mask |= walkTypeEffects(ownership_only, records, field.ty, path, depth + 1);
        }
    }
    return mask;
}

/// Effects one type's ownership implies: an external resource family carries its
/// own effect, and every element, case payload or field contributes what it
/// holds. This mirrors `cleanupMasks` for one type, without building the whole
/// catalog's fixpoint.
pub fn ownershipMask(records: []const typed.Record, ty: typed.Type) sets.Mask {
    var path: [64]typed.Type = undefined;
    return walkTypeEffects(true, records, ty, &path, 0);
}

/// Effect a callback parameter's contract contributes. A bounded ceiling is a
/// declared promise and is honoured; an omitted ceiling is the unbounded `all`
/// mask, which is not a declaration at all, so it contributes nothing and an
/// invoke through the value contributes nothing either. The value's own
/// signature is where that authority is declared.
fn callbackContribution(contract: typed.Callable) sets.Mask {
    return if (contract.effects == sets.all) 0 else contract.effects;
}

/// Authority one parameter type carries, walked through elements, case payloads
/// and fields: a capability type permits its effect wherever it is held, a
/// callback type the bounded ceiling it declares, and an owned resource the
/// effect of dropping it. A record that holds an `Environment` therefore permits
/// `environment` exactly as an `Environment` parameter does.
pub fn authorityMask(records: []const typed.Record, ty: typed.Type) sets.Mask {
    var path: [64]typed.Type = undefined;
    return walkTypeEffects(false, records, ty, &path, 0);
}

/// Effect ceiling a signature implies by construction: one effect per capability
/// parameter, `mutation` for every `mut` parameter, the declared ceiling of every
/// callback parameter, `managed_allocation`, which is always permitted, and the
/// effects the signature's own ownership carries, because an owned resource the
/// body may drop is authority the signature already grants. A body may not
/// exceed this set; a clause may only narrow it further.
pub fn derivedCeiling(records: []const typed.Record, function: typed.Function) sets.Mask {
    const signature = function.signature;
    if (signature.parameter_count > function.scope.locals.len) return sets.all;
    var mask: sets.Mask = sets.bit(.managed_allocation);
    mask |= ownershipMask(records, signature.return_type);
    for (function.scope.locals[0..signature.parameter_count]) |parameter| {
        mask |= authorityMask(records, parameter.ty);
    }
    for (signature.declared_mutates) |position| {
        if (position < signature.parameter_count) mask |= sets.bit(.mutation);
    }
    return mask;
}

/// The capability effects a deterministic stand-in can exercise.
const stand_in_effects = sets.bit(.clock) | sets.bit(.random) | sets.bit(.filesystem) | sets.bit(.network) | sets.bit(.environment);

/// Effects that stay inside one function (TEST-CAPS-4). Real authority reaches a
/// body only through its parameters, so a clock, entropy, filesystem, network
/// or environment capability the body holds without a parameter that supplies
/// that effect can only be a deterministic stand-in built by `time.simulated_clock`
/// and its siblings; using one reaches nothing outside the process, so it is not
/// an effect of the function. A `Host` parameter, a `host def` or an `extern def`
/// can reach the host by other means, so they contain nothing.
pub fn containedEffects(records: []const typed.Record, signature: typed.FunctionSignature, locals: []const typed.Local, policy: typed.FunctionPolicy) sets.Mask {
    if (policy.host != null or policy.c_abi or signature.parameter_count > locals.len) return 0;
    var supplied: sets.Mask = 0;
    for (locals[0..signature.parameter_count]) |parameter| supplied |= authorityMask(records, parameter.ty);
    if (supplied & sets.bit(.host) != 0) return 0;
    return stand_in_effects & ~supplied;
}

/// Ceiling a checked function is actually held to. A `host def` or `extern def`
/// has no body to derive from and declares its authority directly, so its clause
/// stays the ceiling; every other function is bounded by the derived set, and a
/// clause narrows it further.
pub fn effectiveCeiling(records: []const typed.Record, function: typed.Function) sets.Mask {
    const declared = if (function.policy.effect_bound) |bound| bound.allowed else null;
    if (function.policy.host != null or function.policy.c_abi) return declared orelse sets.all;
    const derived = derivedCeiling(records, function);
    return if (declared) |mask| mask & derived else derived;
}

/// Whether the source at `span` is an effect clause the source actually wrote.
/// A synthesized bound — a constant getter's, or a lambda's destination
/// contract — carries a span that names the declaration instead, and none of the
/// clause diagnostics apply to it.
pub fn writtenClause(src: source.Source, span: Span) bool {
    const text = src.text(span);
    return std.mem.startsWith(u8, text, "effects") or std.mem.startsWith(u8, text, "noalloc") or std.mem.startsWith(u8, text, "noio");
}

/// Whether a clause is one of the negative forms (`noalloc`, `noio`) rather than
/// an explicit `effects(...)` list. Only an explicit list names effects, so only
/// it can name one that no parameter supplies.
pub fn negativeClause(src: source.Source, span: Span) bool {
    const text = src.text(span);
    return std.mem.startsWith(u8, text, "noalloc") or std.mem.startsWith(u8, text, "noio");
}

/// Append one `E_EFFECT_BOUND` for a body that exceeds the ceiling its own
/// parameter list implies. There is no clause to point at, so the diagnostic
/// sits on the operation (or the call) that reaches the effect and names the
/// parameter that would permit it.
fn appendDerivedViolation(allocator: std.mem.Allocator, ctx: BoundContext, index: usize, effect: sets.Effect, sink: *diagnostic.Sink) diagnostic.Error!void {
    const program = ctx.program;
    const graph = ctx.graph;
    const function = program.functions[index];
    const witness = graph.states[index].witnesses[@backingInt(effect)].?;
    var path: std.Io.Writer.Allocating = .init(allocator);
    defer path.deinit();
    path.writer.print("effect `{s}` exceeds this signature's ceiling: {s}", .{ @tagName(effect), function.name }) catch return error.OutOfMemory;
    var cursor = index;
    var steps: usize = 0;
    while (graph.states[cursor].witnesses[@backingInt(effect)].?.via) |callee| {
        path.writer.print(" -> {s}", .{program.functions[callee].name}) catch return error.OutOfMemory;
        cursor = callee;
        steps += 1;
        std.debug.assert(steps < program.functions.len);
    }
    if (supplyingParameter(effect)) |paste| {
        path.writer.print(", which no parameter permits; add `{s}` to the parameters", .{paste}) catch return error.OutOfMemory;
    } else {
        path.writer.writeAll(", which no parameter permits") catch return error.OutOfMemory;
    }
    const message = allocator.dupe(u8, path.written()) catch return error.OutOfMemory;
    sink.items.append(allocator, .{
        .code = bound_code,
        .span = witness.span,
        .message = message,
        .related = .{ .span = function.declaration, .message = "this signature is the whole contract" },
    }) catch return error.OutOfMemory;
}

/// Report the two clause-only diagnostics of a signature-derived ceiling. A
/// clause that names an effect no parameter can supply is `E_DERIVED_EFFECTS`
/// because it can never be satisfied; a clause that permits exactly what the
/// parameters imply is `W_DERIVED_EFFECTS` because it says nothing.
fn appendClauseDiagnostics(allocator: std.mem.Allocator, src: source.Source, function: typed.Function, derived: sets.Mask, sink: *diagnostic.Sink) diagnostic.Error!bool {
    const bound = function.policy.effect_bound orelse return false;
    if (!writtenClause(src, bound.span)) return false;
    const clause = src.text(bound.span);
    if (!negativeClause(src, bound.span)) {
        const unsupplied = bound.allowed & ~derived;
        if (unsupplied != 0) {
            var message: std.Io.Writer.Allocating = .init(allocator);
            defer message.deinit();
            message.writer.print("`{s}` names ", .{clause}) catch return error.OutOfMemory;
            var separator = false;
            for (std.meta.tags(sets.Effect)) |effect| {
                if (unsupplied & sets.bit(effect) == 0) continue;
                if (separator) message.writer.writeAll(", ") catch return error.OutOfMemory;
                message.writer.print("`{s}`", .{@tagName(effect)}) catch return error.OutOfMemory;
                separator = true;
            }
            message.writer.writeAll(", which no parameter supplies; add ") catch return error.OutOfMemory;
            separator = false;
            for (std.meta.tags(sets.Effect)) |effect| {
                if (unsupplied & sets.bit(effect) == 0) continue;
                const paste = supplyingParameter(effect) orelse continue;
                if (separator) message.writer.writeAll(", ") catch return error.OutOfMemory;
                message.writer.print("`{s}`", .{paste}) catch return error.OutOfMemory;
                separator = true;
            }
            message.writer.writeAll(" to the parameters or drop the clause") catch return error.OutOfMemory;
            const text = allocator.dupe(u8, message.written()) catch return error.OutOfMemory;
            sink.items.append(allocator, .{
                .severity = .err,
                .code = unsupplied_clause_code,
                .span = bound.span,
                .message = text,
            }) catch return error.OutOfMemory;
            return true;
        }
    }
    if (derived & ~bound.allowed == 0) {
        const text = std.fmt.allocPrint(allocator, "`{s}` is exactly what the parameters imply; remove it", .{clause}) catch return error.OutOfMemory;
        sink.items.append(allocator, .{
            .severity = .warning,
            .code = restating_clause_code,
            .span = bound.span,
            .message = text,
        }) catch return error.OutOfMemory;
    }
    return false;
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
        .code = bound_code,
        .span = bound.span,
        .message = message,
        .related = .{ .span = graph.states[cursor].witnesses[@backingInt(effect)].?.span, .message = "effect originates at this operation or owned type" },
    }) catch return error.OutOfMemory;
}

/// Infer transitive effects and reject function bodies that exceed declared effect bounds.
/// Everything the effect and mutation passes need besides the checked program:
/// the exporting verdicts and the source the declaration-side messages quote.
pub const Request = struct {
    /// Whether each function is exported, in program order.
    exported: []const bool,
    /// Merged source of the checked program, for paste-ready diagnostics.
    src: source.Source,
    /// Parsed declarations, which carry each parameter's own type span.
    syntax: ast.Program,
    /// Diagnostic destination.
    sink: *diagnostic.Sink,
    /// Stand-in facts for bodies this check did not materialize, by function
    /// index. Such a function keeps its stored effect mask and mutation summary,
    /// is not walked, and reports no diagnostics of its own.
    stubs: []const ?origin_pass.Fact = &.{},
    /// When set, receives every function's final effect mask and mutation summary.
    facts: ?[]origin_pass.Fact = null,
};

/// Validate every checked function's effects, then enforce the mutation
/// guarantee over the same program. Request collects the program's exporting
/// verdicts, its merged source and the diagnostic sink.
pub fn check(allocator: std.mem.Allocator, program: typed.Program, request: Request) diagnostic.Error!void {
    const sink = request.sink;
    var graph = try Graph.init(allocator, program.functions.len);
    defer graph.deinit();
    const cleanup_masks = cleanupMasks(allocator, program.records) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => unreachable,
    };
    defer allocator.free(cleanup_masks);
    for (program.functions, graph.states) |function, *state| state.contained = containedEffects(program.records, function.signature, function.scope.locals, function.policy);
    for (program.functions, 0..) |function, index| {
        if (origin_pass.standIn(request.stubs, index)) |fact| {
            seedStandIn(&graph, index, fact.graph_mask, function.declaration);
        } else try seedFunction(allocator, program, &graph, index, cleanup_masks);
    }
    try graph.infer();
    // M2: enforce the checked call-duration mutation guarantee. This computes
    // transitive write footprints and return-alias bounds to a fixed point,
    // attributes writes to caller inputs through aliases and calls, and rejects
    // writes that exceed a declared ceiling or unknown-overlap call arguments.
    const mutation_violated = try mutationPass(allocator, program, request, &graph);
    // Exported declarations are no longer required to spell out a ceiling. The
    // inferred transitive mask is frozen onto the checked function below and is
    // what interfaces/fingerprints publish; an explicit `noalloc`, `noio` or
    // `effects(...)` remains an opt-in upper bound enforced by the loop below.
    // The signature is the whole contract: every checked function is held to the
    // ceiling its parameter list implies (a `mut` parameter permits `mutation`,
    // a capability parameter its effect, a callback parameter its declared
    // ceiling, and allocation is always permitted). An explicit `noalloc`,
    // `noio` or `effects(...)` clause may only narrow that set, and the inferred
    // transitive mask stays a checked body fact for diagnostics.
    for (@constCast(program.functions), 0..) |*function, index| {
        function.policy.effects = graph.states[index].mask;
        if (function.signature.inferred.external) function.policy.effects |= sets.bit(.mutation);
    }
    var violated = mutation_violated;
    if (try checkSlotCeilings(allocator, .{ .program = program, .graph = &graph }, sink)) violated = true;
    const context: CeilingContext = .{ .allocator = allocator, .program = program, .graph = &graph, .src = request.src, .sink = sink };
    for (program.functions, 0..) |_, index| {
        if (origin_pass.standIn(request.stubs, index) != null) continue;
        if (try checkSignatureCeiling(context, index)) violated = true;
        if (try checkContractPurity(context, index)) violated = true;
    }
    if (violated) return error.SourceError;
}

/// Seed one checked function's own effects, call edges, cleanup effects and
/// local mutation facts from a walk of its body.
fn seedFunction(allocator: std.mem.Allocator, program: typed.Program, graph: *Graph, index: usize, cleanup_masks: []const sets.Mask) diagnostic.Error!void {
    const function = program.functions[index];
    if (function.policy.host) |span| try seedHost(graph, index, function.policy.effect_bound, span);
    try seedOwnership(graph, index, function.signature.return_type, function.scope.locals, function.declaration, cleanup_masks);
    const facts = inferFacts(allocator, program, function) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InternalError => return error.InternalError,
    };
    const mutable = @constCast(&program.functions[index]);
    mutable.signature.mutates = facts.mutates;
    mutable.signature.return_origin = facts.return_origin;
    mutable.signature.inferred.writes = facts.inferred.writes;
    mutable.signature.inferred.external = facts.inferred.external;
    var walker = try typed_walk.Walker.init(allocator, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| if (item == .expression) {
        const node = program.nodes[@backingInt(item.expression)];
        switch (node.data) {
            .invoke => |call| {
                const contract = callables.signature(program.nodes[@backingInt(call.callee)].ty, program.records).?;
                inline for (std.meta.tags(sets.Effect)) |effect| if (effect != .mutation and callbackContribution(contract) & sets.bit(effect) != 0) graph.direct(index, effect, node.span);
            },
            .call => |call| graph.call(index, @backingInt(call.function), node.span) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InternalError => unreachable, // Resolved typed function identity.
            },
            else => if (directEffect(program, function, node)) |effect| graph.direct(index, effect, node.span),
        }
    };
    // Ownership-bearing signatures and locals conservatively include their
    // fallback cleanup effect, including on traps and propagated errors.
}

/// The effect one checked node has by itself, apart from the calls it makes:
/// a capability operation, an output, or a managed allocation. Null when the
/// node has none of its own.
fn directEffect(program: typed.Program, function: typed.Function, node: typed.Node) ?sets.Effect {
    return switch (node.data) {
        .acquire_resource => typed.resourceKind(typed.resultShape(node.ty, program.records).?.ok_type, program.records).?.effect(),
        .complete_resource => typed.resourceKind(typed.completionShape(node.ty, program.records).?.resource_type, program.records).?.effect(),
        .resource_io => |io| typed.resourceKind(function.scope.locals[@backingInt(io.owner)].ty, program.records).?.effect(),
        .environment_get, .environment_names => .environment,
        // A `debug` line is effect-free.
        .print => |output| if (output.debug) null else .output,
        .stream_write => .output,
        .file_access, .file_method => .filesystem,
        .external_read => |read| read.kind.effect(),
        .cast => if (allocatingSequence(program.records, node.ty)) .managed_allocation else null,
        .array => if (literalAllocates(program.records, node.ty)) .managed_allocation else null,
        .record => |fields| if (node.ty.isAggregate() and program.records[node.ty.recordIndex()].managed) .managed_allocation else boxing(program.records, node.ty, fields),
        // Building a boxed field or case allocates its box (RECURSIVE-VALUES-2).
        .update => |update| boxing(program.records, node.ty, update.fields),
        .variant => |variant| if (variant.value != null and program.records[node.ty.recordIndex()].shape.variants.?.cases[variant.tag].boxed) .managed_allocation else null,
        .binary => |binary| if (binary.op == .add and allocatingSequence(program.records, node.ty)) .managed_allocation else null,
        // Charged by the receiver, as `validate` charges `get_index`: only a
        // `str` read builds a fresh string. A static-array or dictionary
        // read of a `str` element hands back the stored reference.
        .index => |access| if (allocatingElement(program.records, program.nodes[@backingInt(access.base)].ty)) .managed_allocation else null,
        .acquire_buffer, .arena_escape => .managed_allocation,
        .buffer_operation => |op| operation: {
            const owner = program.records[function.scope.locals[@backingInt(op.owner)].ty.recordIndex()];
            const dictionary = owner.collection.kind == .dictionary;
            break :operation if (owner.managed and @import("buffer_operations.zig").managedAllocation(op.kind, dictionary)) .managed_allocation else null;
        },
        .invoke, .call => null,
        .restrict_resource,
        .dir_resource,
        .host_resource,
        .environment_only,
        // A stand-in grants no real authority, so building or moving one
        // is not an effect; using it is charged where the use happens.
        .stand_in,
        .function_value,
        .integer,
        .boolean,
        .unit,
        // Embedded file data is static, so it allocates nothing (`EMBED-1`).
        .blob,
        .local,
        .propagate,
        .wrap,
        .block_value,
        .unwrap,
        .replace,
        .length,
        .field,
        .unary,
        => null,
    };
}

/// The allocation of a record construction or update that stores a boxed
/// field: each boxed value it writes gets a fresh box (RECURSIVE-VALUES-2).
fn boxing(records: []const typed.Record, ty: typed.Type, fields: []const typed.FieldInit) ?sets.Effect {
    const schema = records[ty.recordIndex()];
    for (fields) |field| if (schema.fields[field.index].boxed) return .managed_allocation;
    return null;
}

/// Whether a local names storage a contract condition did not build itself.
fn existingStorage(function: typed.Function, slot: typed.LocalId) bool {
    if (@backingInt(slot) < function.signature.parameter_count) return true;
    const origin = function.scope.locals[@backingInt(slot)].origin;
    return origin == .contract_old or origin == .contract_value;
}

/// One effect a contract condition has, and the operation it comes from.
const ContractEffect = struct { effect: sets.Effect, span: Span };

/// The first effect other than `managed_allocation` that evaluating the
/// expression `root` of `function` has, including every effect its callees
/// were inferred to have, or null when it is effect-free.
fn contractEffect(allocator: std.mem.Allocator, program: typed.Program, graph: *const Graph, function: typed.Function, root: typed.NodeId) diagnostic.Error!?ContractEffect {
    var walker = try typed_walk.Walker.initExpression(allocator, program, root);
    defer walker.deinit();
    const allowed = sets.bit(.managed_allocation);
    while (try walker.next()) |item| if (item == .expression) {
        const node = program.nodes[@backingInt(item.expression)];
        const mask: sets.Mask = switch (node.data) {
            .call => |call| graph.states[@backingInt(call.function)].mask | (program.functions[@backingInt(call.function)].policy.effects & sets.bit(.mutation)),
            .invoke => |call| callbackContribution(callables.signature(program.nodes[@backingInt(call.callee)].ty, program.records).?),
            // Only storage that existed before the condition ran can be
            // changed by it: a parameter or a value the clause is checked
            // against. A list a comprehension or literal builds is its own.
            .buffer_operation => |op| if (op.kind.writesReceiver() and existingStorage(function, op.owner)) sets.bit(.mutation) else 0,
            else => if (directEffect(program, function, node)) |effect| sets.bit(effect) else 0,
        };
        inline for (std.meta.tags(sets.Effect)) |effect| if (mask & ~allowed & sets.bit(effect) != 0) return .{ .effect = effect, .span = node.span };
    };
    return null;
}

/// CONTRACT-PURE-1: every contract condition the checker placed in a body —
/// a `@requires`, `@ensures` or `@invariant` assertion, and each `old(...)`
/// capture — may allocate but has no other effect, judged by the same
/// inference that computes every function's effects. Reports each violation
/// and returns whether any.
fn checkContractPurity(ctx: CeilingContext, index: usize) diagnostic.Error!bool {
    const function = ctx.program.functions[index];
    var walker = try typed_walk.Walker.init(ctx.allocator, ctx.program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| if (item == .statement) {
        const statement = ctx.program.statements[@backingInt(item.statement)];
        const root: typed.NodeId, const clause: []const u8 = switch (statement.data) {
            .assertion => |claim| if (claim.kind != .statement) .{ claim.condition, @tagName(claim.kind) } else continue,
            .initialize => |store| if (function.scope.locals[@backingInt(store.slot)].origin == .contract_old) .{ store.value, "old" } else continue,
            else => continue,
        };
        const found = try contractEffect(ctx.allocator, ctx.program, ctx.graph, function, root) orelse continue;
        const message = try std.fmt.allocPrint(ctx.allocator, "a contract condition may allocate but have no other effect; this `{s}` clause has the `{s}` effect", .{ clause, @tagName(found.effect) });
        try ctx.sink.items.append(ctx.allocator, .{
            .code = contract_effect_code,
            .span = ctx.program.nodes[@backingInt(root)].span,
            .message = message,
            .related = .{ .span = found.span, .message = "the effect comes from this operation" },
        });
        return true;
    };
    return false;
}

/// Run the M2 mutation pass over `program` and, when the request asks for them,
/// hand back each function's final effect mask and mutation summary.
fn mutationPass(allocator: std.mem.Allocator, program: typed.Program, request: Request, graph: *const Graph) diagnostic.Error!bool {
    for (@constCast(program.functions), 0..) |*function, index| if (origin_pass.standIn(request.stubs, index)) |fact| {
        if (!mut_abi.valid(program.records, function.*, fact.caller_storage)) return error.InternalError;
        function.signature.inferred.caller_storage = fact.caller_storage;
    };
    const storage = try mut_abi.collect(allocator, program);
    defer allocator.free(storage);
    for (@constCast(program.functions), storage) |*function, mask| function.signature.inferred.caller_storage = mask;
    const summaries: ?[]origin_pass.Summary = if (request.facts) |facts| try allocator.alloc(origin_pass.Summary, facts.len) else null;
    defer if (summaries) |owned| allocator.free(owned);
    const violated = origin_pass.check(allocator, program, .{
        .exported = request.exported,
        .src = request.src,
        .syntax = request.syntax,
        .sink = request.sink,
        .stubs = request.stubs,
        .summaries = summaries,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
    };
    if (request.facts) |facts| for (facts, 0..) |*fact, index| {
        fact.* = .{ .graph_mask = if (index < graph.states.len) graph.states[index].mask else 0, .caller_storage = storage[index], .summary = summaries.?[index] };
    };
    return violated;
}

/// CALLBACK-SLOT-1: an unannotated function used as a value takes the ceiling
/// of the callback slot it fills (`Checker.functionValue`, and a generic call's
/// instantiated parameter), so a call through that slot is charged only that
/// ceiling. Its inferred body set is what keeps that honest: every function
/// value whose target declares no clause of its own must fit the ceiling its
/// value type carries, or an effect would reach a caller through a callback
/// its bound never sees. Reports each violation and returns whether any.
fn checkSlotCeilings(allocator: std.mem.Allocator, ctx: BoundContext, sink: *diagnostic.Sink) diagnostic.Error!bool {
    const program = ctx.program;
    var violated = false;
    for (program.nodes) |node| {
        const target = switch (node.data) {
            .function_value => |id| @backingInt(id),
            else => continue,
        };
        if (target >= program.functions.len) return error.InternalError;
        const function = program.functions[target];
        if (function.policy.effect_bound != null) continue;
        const contract = callables.signature(node.ty, program.records) orelse return error.InternalError;
        // `mutation` belongs to the mutation analysis. A sort key that builds a
        // `str` (LIST-SORT-KEY-3) fits because the key slot itself admits
        // `managed_allocation` (LAMBDA-KEY-INFER-1).
        const forbidden = ctx.graph.states[target].mask & ~contract.effects & ~sets.bit(.mutation);
        if (forbidden == 0) continue;
        const effect = for (std.meta.tags(sets.Effect)) |effect| {
            if (forbidden & sets.bit(effect) != 0) break effect;
        } else unreachable;
        var path: std.Io.Writer.Allocating = .init(allocator);
        defer path.deinit();
        const slot = try typed.surfaceTypeName(allocator, node.ty, program.records);
        path.writer.print("`{s}` fills a callback slot of type `{s}`, but its body has effect `{s}`: {s}", .{ function.name, slot, @tagName(effect), function.name }) catch return error.OutOfMemory;
        var cursor = target;
        var steps: usize = 0;
        while (ctx.graph.states[cursor].witnesses[@backingInt(effect)].?.via) |callee| {
            path.writer.print(" -> {s}", .{program.functions[callee].name}) catch return error.OutOfMemory;
            cursor = callee;
            steps += 1;
            std.debug.assert(steps < program.functions.len);
        }
        path.writer.writeAll("; keep the body within the slot's ceiling, or widen the callback type's `effects(...)`") catch return error.OutOfMemory;
        sink.items.append(allocator, .{
            .code = bound_code,
            .span = node.span,
            .message = allocator.dupe(u8, path.written()) catch return error.OutOfMemory,
            .related = .{ .span = ctx.graph.states[cursor].witnesses[@backingInt(effect)].?.span, .message = "effect originates at this operation or owned type" },
        }) catch return error.OutOfMemory;
        violated = true;
    }
    return violated;
}

/// Everything one per-function ceiling check reads: the allocator, the checked
/// program, the inferred graph, the merged source, and the diagnostic sink.
const CeilingContext = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    graph: *const Graph,
    src: source.Source,
    sink: *diagnostic.Sink,
};

/// Enforce one checked function's signature-derived ceiling and report the clause
/// diagnostics that belong to it. Returns whether this function alone exceeded
/// its ceiling, so the caller can keep collecting every violation.
fn checkSignatureCeiling(ctx: CeilingContext, index: usize) diagnostic.Error!bool {
    const function = ctx.program.functions[index];
    // The synthesized entry wrapper is the runtime's exit protocol, not guest
    // code: rendering an `Err` result on stderr is how `main -> Result` reports,
    // just as an `int` result becomes the status, so no signature bounds it.
    if (std.mem.eql(u8, function.name, entry_adapter.wrapper_name)) return false;
    // A `host def`/`extern def` has no body to derive from: its clause is its
    // authority and stays its ceiling.
    const derived_applies = function.policy.host == null and !function.policy.c_abi;
    const derived = derivedCeiling(ctx.program.records, function);
    var violated = false;
    if (derived_applies) violated = try appendClauseDiagnostics(ctx.allocator, ctx.src, function, derived, ctx.sink);
    const forbidden = function.policy.effects & ~effectiveCeiling(ctx.program.records, function);
    if (forbidden == 0) return violated;
    for (std.meta.tags(sets.Effect)) |effect| {
        // `mutation` permission and footprint violations are reported by
        // origins.check with argument witnesses; the effect graph does not carry
        // a mutation witness.
        if (effect == .mutation) continue;
        if (forbidden & sets.bit(effect) == 0) continue;
        const bound_context: BoundContext = .{ .program = ctx.program, .graph = ctx.graph };
        if (function.policy.effect_bound) |bound| {
            try appendBoundViolation(ctx.allocator, bound_context, index, effect, bound, ctx.sink);
        } else {
            try appendDerivedViolation(ctx.allocator, bound_context, index, effect, ctx.sink);
        }
        violated = true;
    }
    return violated;
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
    // An exported generic template without an explicit ceiling is accepted; the
    // concrete specializations freeze the inferred mask during `check`. Explicit
    // ceilings on templates remain upper bounds enforced below.
    var violated = false;
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
                .code = bound_code,
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
        const permitted = positionMask(function.signature.mut_positions);
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
    if (!function.signature.inferred.writes) return false;
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
        .environment_get, .environment_names => graph.direct(index, .environment, instruction.span),
        .print => |output| if (!output.debug) graph.direct(index, .output, instruction.span),
        .stream_write => graph.direct(index, .output, instruction.span),
        .file_access, .file_method => graph.direct(index, .filesystem, instruction.span),
        .external_read => |read| graph.direct(index, read.kind.effect(), instruction.span),
        .cast_integer => |ty| if (allocatingSequence(program.records, ty)) {
            graph.direct(index, .managed_allocation, instruction.span);
        },
        // An embedded file is static data, so it allocates nothing (`EMBED-1`).
        .make_record => |record| if (record.blob == null and try managedType(program.records, record.ty) and
            program.records[record.ty.recordIndex()].collection.kind != .string)
        {
            graph.direct(index, .managed_allocation, instruction.span);
        },
        .binary_integer => |binary| if (binary.op == .add and allocatingSequence(program.records, binary.ty)) {
            graph.direct(index, .managed_allocation, instruction.span);
        },
        .get_index => |access| if (allocatingElement(program.records, access.ty)) {
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
            const contract = callables.signature(ty, program.records) orelse return error.InternalError;
            inline for (std.meta.tags(sets.Effect)) |effect| if (effect != .mutation and callbackContribution(contract) & sets.bit(effect) != 0) graph.direct(index, effect, instruction.span);
        },
        .call => |callee| try graph.call(index, @backingInt(callee), instruction.span),
        .arena_escape => graph.direct(index, .managed_allocation, instruction.span),
        .begin_arena,
        .end_arena,
        .restrict_resource,
        .dir_resource,
        .host_resource,
        .environment_only,
        .stand_in,
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
        // A value-semantics copy is not an effect in this stage: the switch
        // must not change a function's published effects (`VALUE-SEMANTICS-2`).
        .value_copy,
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
        .ref_local,
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
    for (program.functions, graph.states) |function, *state| state.contained = containedEffects(program.records, function.signature, function.scope.locals, function.policy);
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
            if (function.signature.inferred.external and bound.allowed & sets.bit(.mutation) == 0) return error.InternalError;
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

/// Seed a stood-in body with the effect mask it propagated when it was last
/// checked. It registers no call edges, so propagation never widens it; a
/// checked caller still inherits the mask through its own call edge.
fn seedStandIn(graph: *Graph, index: usize, mask: sets.Mask, span: Span) void {
    const state = &graph.states[index];
    state.mask = mask;
    inline for (std.meta.tags(sets.Effect)) |effect| {
        if (mask & sets.bit(effect) != 0) state.witnesses[@backingInt(effect)] = .{ .span = span };
    }
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
