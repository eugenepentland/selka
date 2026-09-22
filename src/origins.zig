//! Deep origin, alias and call-permission analysis for M2.
//!
//! The pass computes a sound, monotone upper bound on which caller inputs a
//! checked value may alias (including managed descendants reached through
//! records, arrays, variants and fresh wrappers) and which inputs a function's
//! body may write. Call footprints are substituted into actual argument origins
//! and propagated through direct calls, indirect callbacks, recursion and
//! specializations to a fixed point. Budget exhaustion widens every summary
//! conservatively instead of accepting a write.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const mutation = @import("mutation.zig");
const effect_set = @import("effect_set.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const callables = @import("callables.zig");
const Walker = @import("typed_walk.zig").Walker;

/// Diagnostic code for a managed write that exceeds its declared contract.
pub const permission_code = "E_MUTATION_PERMISSION";
/// Diagnostic code for writable and read-only arguments that may overlap.
pub const overlap_code = "E_MUTATION_OVERLAP";
/// Diagnostic code for a bounded analysis that had to widen conservatively.
pub const limit_code = "E_MUTATION_LIMIT";
/// Error code for a `mut` marker that is missing, unneeded or unauthorizable.
pub const mutation_marker_code = "E_MUTATION_MARKER";
/// Error code for a parameter declared `mut` that the body never writes.
pub const unused_mut_code = mutation_marker_code;

/// Abstract upper bound on the caller inputs a value may alias.
///
/// `positions` names the enclosing function's parameter positions whose managed
/// storage may be reachable; `unknown` means the bound could not be proven. A
/// value with no positions and no unknown bit is definitely fresh local storage
/// and therefore disjoint from every caller input.
pub const Origin = struct {
    positions: u16 = 0,
    unknown: bool = false,

    /// Build the origin of a direct reference to one parameter position.
    pub fn fromPosition(position: u16) Origin {
        return .{ .positions = @as(u16, 1) << @intCast(position) };
    }

    /// Build the origin of definitely fresh local storage.
    pub fn fresh() Origin {
        return .{};
    }

    /// Join two origins, preserving every possible alias and unknown marker.
    pub fn merge(a: Origin, b: Origin) Origin {
        return .{ .positions = a.positions | b.positions, .unknown = a.unknown or b.unknown };
    }

    /// Whether this value is proven disjoint from every caller input.
    pub fn isFresh(self: Origin) bool {
        return self.positions == 0 and !self.unknown;
    }

    /// Whether one parameter position is in the alias set.
    pub fn has(self: Origin, position: u16) bool {
        return self.positions & (@as(u16, 1) << @intCast(position)) != 0;
    }
};

/// Inferred transitive facts for one checked function.
pub const Summary = struct {
    return_origin: Origin = .{},
    /// Positions of this function's parameters it may write (transitively).
    mutates: u16 = 0,
    /// A write target's origin could not be attributed to a parameter position.
    mutates_unknown: bool = false,
    /// Any managed receiver write, fresh local or not.
    writes: bool = false,
    /// A managed write that is not proven to target definitely fresh storage.
    external: bool = false,
    /// First located external write, used for diagnostics.
    witness: ?source.Span = null,
};

fn mergeSummaries(a: Summary, b: Summary) Summary {
    return .{
        .return_origin = Origin.merge(a.return_origin, b.return_origin),
        .mutates = a.mutates | b.mutates,
        .mutates_unknown = a.mutates_unknown or b.mutates_unknown,
        .writes = a.writes or b.writes,
        .external = a.external or b.external,
        .witness = a.witness orelse b.witness,
    };
}

fn sameSummary(a: Summary, b: Summary) bool {
    return a.mutates == b.mutates and a.mutates_unknown == b.mutates_unknown and
        a.writes == b.writes and a.external == b.external and
        a.return_origin.positions == b.return_origin.positions and a.return_origin.unknown == b.return_origin.unknown;
}

/// Whether a value of `ty` may reach managed storage another value could share.
pub fn mayContainManaged(program: typed.Program, ty: typed.Type) bool {
    return mayContainManagedDepth(program, ty, 0);
}

fn mayContainManagedDepth(program: typed.Program, ty: typed.Type, depth: usize) bool {
    if (!ty.isAggregate()) return false;
    const index = ty.recordIndex();
    if (index >= program.records.len) return true;
    if (depth == 64) return true;
    const record = program.records[index];
    if (record.managed) {
        // Strings and bytes are immutable managed buffers; they carry no
        // writable storage and therefore no mutation origin.
        const kind = record.collection.kind;
        if (kind == .string or kind == .bytes) return false;
        return true;
    }
    if (record.shape.array) |array| if (mayContainManagedDepth(program, array.element, depth + 1)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (mayContainManagedDepth(program, payload, depth + 1)) return true;
    };
    for (record.fields) |field| if (mayContainManagedDepth(program, field.ty, depth + 1)) return true;
    return false;
}

fn managedElement(program: typed.Program, owner: typed.Type) bool {
    if (!owner.isAggregate()) return false;
    const index = owner.recordIndex();
    if (index >= program.records.len) return true;
    const element = program.records[index].shape.buffer orelse return true;
    return mayContainManaged(program, element);
}

/// Normalize a sorted-free list of parameter positions to a bitset.
pub fn positionsBitset(positions: []const u16) u16 {
    var mask: u16 = 0;
    for (positions) |position| mask |= @as(u16, 1) << @intCast(position);
    return mask;
}

fn bitCount(mask: u16) usize {
    var count: usize = 0;
    var position: u5 = 0;
    while (position < 16) : (position += 1) {
        if (mask & (@as(u16, 1) << @intCast(position)) != 0) count += 1;
    }
    return count;
}

fn bitsetPositions(allocator: std.mem.Allocator, mask: u16) std.mem.Allocator.Error![]const u16 {
    const out = try allocator.alloc(u16, bitCount(mask));
    var written: usize = 0;
    var position: u5 = 0;
    while (position < 16) : (position += 1) {
        if (mask & (@as(u16, 1) << @intCast(position)) == 0) continue;
        out[written] = position;
        written += 1;
    }
    return out;
}

fn originFromBound(bound: typed.ReturnOrigin) Origin {
    return switch (bound) {
        .fresh => .{},
        .unknown => .{ .unknown = true },
        .params => |positions| blk: {
            var origin = Origin{};
            for (positions) |position| origin.positions |= @as(u16, 1) << @intCast(position);
            break :blk origin;
        },
    };
}

fn boundFromOrigin(allocator: std.mem.Allocator, origin: Origin) std.mem.Allocator.Error!typed.ReturnOrigin {
    if (origin.unknown) return .unknown;
    if (origin.positions == 0) return .fresh;
    return .{ .params = try bitsetPositions(allocator, origin.positions) };
}

const Footprint = struct { positions: u16 = 0, unknown: bool = false };

fn effectiveFootprint(program: typed.Program, summaries: []const Summary, index: usize) Footprint {
    const function = program.functions[index];
    if (function.policy.effect_bound != null) {
        return .{ .positions = positionsBitset(function.signature.declared_mutates) };
    }
    const summary = summaries[index];
    return .{ .positions = summary.mutates, .unknown = summary.mutates_unknown };
}

/// Apply the block's own initialize/assign statements to the origin table. The
/// ordinary walker will visit them again; merging is idempotent and conservative.
fn applyBlockStatements(context: *const Context, function: typed.Function, origins: []Origin, body: typed.StatementId, depth: usize) void {
    if (depth == 256) return;
    const statement = context.program.statements[@backingInt(body)];
    switch (statement.data) {
        .initialize, .assign => |store| {
            const value = context.nodeOrigin(function, origins, store.value, depth + 1);
            const slot = @backingInt(store.slot);
            if (slot < origins.len) origins[slot] = Origin.merge(origins[slot], value);
        },
        .block => |children| for (children) |child| applyBlockStatements(context, function, origins, child, depth + 1),
        .branch => |branch| {
            applyBlockStatements(context, function, origins, branch.then_body, depth + 1);
            if (branch.else_body) |otherwise| applyBlockStatements(context, function, origins, otherwise, depth + 1);
        },
        .loop => |loop| {
            applyBlockStatements(context, function, origins, loop.body, depth + 1);
            if (loop.step) |step| applyBlockStatements(context, function, origins, step, depth + 1);
        },
        .match => |matched| {
            bindArmPayloads(context, function, origins, matched, depth + 1);
            for (matched.arms) |arm| applyBlockStatements(context, function, origins, arm.body, depth + 1);
        },
        .with_scope => |scope| applyBlockStatements(context, function, origins, scope.body, depth + 1),
        else => {},
    }
}

/// A `match` arm's payload binding aliases the matched value's payload, so it
/// takes the matched value's origin. A write through the binding — including the
/// hidden one an `Option` narrowing lowers `candidate.field = v` to — then reaches
/// the caller instead of looking like fresh local storage.
fn bindArmPayloads(context: *const Context, function: typed.Function, origins: []Origin, matched: @FieldType(@FieldType(typed.Statement, "data"), "match"), depth: usize) void {
    for (matched.arms) |arm| {
        const slot = arm.slot orelse continue;
        const index = @backingInt(slot);
        if (index >= origins.len or index >= function.scope.locals.len) continue;
        const payload = context.childIfManaged(function.scope.locals[index].ty, function, origins, matched.value, depth);
        origins[index] = Origin.merge(origins[index], payload);
    }
}

const Context = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    summaries: []const Summary,

    /// Resolve the origin of one checked expression under the current local origins.
    fn nodeOrigin(self: *const Context, function: typed.Function, origins: []const Origin, node_id: typed.NodeId, depth: usize) Origin {
        if (depth == 256) return .{ .unknown = true };
        const node = self.program.nodes[@backingInt(node_id)];
        return switch (node.data) {
            .local => |slot| self.localOrigin(function, origins, slot),
            .field => |field| self.childIfManaged(node.ty, function, origins, field.base, depth),
            .index => |index| self.childIfManaged(node.ty, function, origins, index.base, depth),
            .cast => |value| self.childIfManaged(node.ty, function, origins, value, depth),
            .wrap, .arena_escape => |value| self.childIfManaged(node.ty, function, origins, value, depth),
            .restrict_resource => |restrict| self.childIfManaged(node.ty, function, origins, restrict.value, depth),
            .unwrap => |value| self.childIfManaged(node.ty, function, origins, value, depth),
            .propagate => |propagate| self.nodeOrigin(function, origins, propagate.value, depth + 1),
            .block_value => |block| if (mayContainManaged(self.program, node.ty)) self.blockValueOrigin(function, origins, block, depth + 1) else Origin{},
            .variant => |variant| self.variantOrigin(node.ty, function, origins, variant.value, depth),
            .array => |values| self.mergeValues(function, origins, values, depth),
            .record => |fields| self.mergeFields(function, origins, fields, depth),
            .update => |update| self.updateOrigin(node.ty, function, origins, update, depth),
            .replace => |replace| self.replaceOrigin(node.ty, function, origins, replace, depth),
            .buffer_operation => |operation| self.bufferOrigin(node.ty, function, origins, operation),
            .call => |call| self.callResultOrigin(function, origins, call.function, call.arguments, depth + 1),
            .invoke => |invoke| self.invokeOrigin(function, origins, invoke, depth),
            .acquire_buffer,
            .acquire_resource,
            .complete_resource,
            .dir_resource,
            .host_resource,
            .environment_get,
            .environment_only,
            .environment_names,
            .external_read,
            .resource_io,
            .print,
            .stream_write,
            .file_access,
            .file_method,
            .length,
            .binary,
            .unary,
            .integer,
            .boolean,
            .unit,
            .function_value,
            => Origin{},
        };
    }

    fn childIfManaged(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, base: typed.NodeId, depth: usize) Origin {
        // The test is writability, not managedness: a `byte_buffer` is managed
        // like `bytes` but keeps writable storage, so a write through it belongs
        // to whoever owns the buffer. A read-only `str`, `bytes` or scalar-only
        // record carries no origin because nothing can be written through it.
        if (!typed.carriesWritableStorage(self.program.records, ty)) return Origin{};
        return self.nodeOrigin(function, origins, base, depth + 1);
    }

    fn variantOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, value: ?typed.NodeId, depth: usize) Origin {
        const payload = value orelse return Origin{};
        return self.childIfManaged(ty, function, origins, payload, depth);
    }

    fn updateOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, update: @FieldType(@FieldType(typed.Node, "data"), "update"), depth: usize) Origin {
        var origin = self.childIfManaged(ty, function, origins, update.base, depth);
        for (update.fields) |field| {
            if (!mayContainManaged(self.program, self.program.nodes[@backingInt(field.value)].ty)) continue;
            origin = Origin.merge(origin, self.nodeOrigin(function, origins, field.value, depth + 1));
        }
        return origin;
    }

    fn replaceOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, replace: @FieldType(@FieldType(typed.Node, "data"), "replace"), depth: usize) Origin {
        const origin = self.childIfManaged(ty, function, origins, replace.base, depth);
        return Origin.merge(origin, self.nodeOrigin(function, origins, replace.value, depth + 1));
    }

    fn bufferOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) Origin {
        if (!mayContainManaged(self.program, ty)) return Origin{};
        const owner = self.localOrigin(function, origins, operation.owner);
        if (operation.kind == .copy and !self.ownerElementManaged(function, operation.owner)) return Origin{};
        return owner;
    }

    fn invokeOrigin(self: *const Context, function: typed.Function, origins: []const Origin, invoke: @FieldType(@FieldType(typed.Node, "data"), "invoke"), depth: usize) Origin {
        const signature = callables.signature(self.program.nodes[@backingInt(invoke.callee)].ty, self.program.records) orelse return .{ .unknown = true };
        return self.substituteOrigin(function, origins, originFromBound(signature.return_origin), invoke.arguments, depth + 1);
    }

    fn localOrigin(_: *const Context, function: typed.Function, origins: []const Origin, slot: typed.LocalId) Origin {
        const index = @backingInt(slot);
        if (index < function.signature.parameter_count) return Origin.fromPosition(@intCast(index));
        if (index < origins.len) return origins[index];
        return .{ .unknown = true };
    }

    fn ownerElementManaged(self: *const Context, function: typed.Function, slot: typed.LocalId) bool {
        const index = @backingInt(slot);
        if (index >= function.scope.locals.len) return true;
        return managedElement(self.program, function.scope.locals[index].ty);
    }

    /// Resolve the origin of an expression block. The block's own initialization
    /// statements are applied to the local-origin table first, so a lowered literal
    /// or method receiver keeps the origin of the value it was built from.
    fn blockValueOrigin(self: *const Context, function: typed.Function, origins: []const Origin, block: @FieldType(@FieldType(typed.Node, "data"), "block_value"), depth: usize) Origin {
        if (depth == 256) return .{ .unknown = true };
        const mutable = @constCast(origins);
        applyBlockStatements(self, function, mutable, block.body, depth + 1);
        return self.nodeOrigin(function, mutable, block.value, depth + 1);
    }

    fn mergeValues(self: *const Context, function: typed.Function, origins: []const Origin, values: []const typed.NodeId, depth: usize) Origin {
        var origin = Origin{};
        for (values) |value| {
            if (!mayContainManaged(self.program, self.program.nodes[@backingInt(value)].ty)) continue;
            origin = Origin.merge(origin, self.nodeOrigin(function, origins, value, depth + 1));
        }
        return origin;
    }

    fn mergeFields(self: *const Context, function: typed.Function, origins: []const Origin, fields: []const typed.FieldInit, depth: usize) Origin {
        var origin = Origin{};
        for (fields) |field| {
            if (!mayContainManaged(self.program, self.program.nodes[@backingInt(field.value)].ty)) continue;
            origin = Origin.merge(origin, self.nodeOrigin(function, origins, field.value, depth + 1));
        }
        return origin;
    }

    fn substituteOrigin(self: *const Context, function: typed.Function, origins: []const Origin, bound: Origin, arguments: []const typed.NodeId, depth: usize) Origin {
        if (bound.unknown) return .{ .unknown = true };
        var origin = Origin{};
        var position: u5 = 0;
        while (position < 16) : (position += 1) {
            if (!bound.has(position)) continue;
            if (position >= arguments.len) {
                origin.unknown = true;
                continue;
            }
            origin = Origin.merge(origin, self.nodeOrigin(function, origins, arguments[position], depth + 1));
        }
        return origin;
    }

    /// The caller inputs a callee's write through one argument can reach. A
    /// fixed array crosses a `mut` position as the caller's own variable, so a
    /// write to its elements reaches only that variable: a parameter's
    /// position when the argument passes a parameter on, fresh storage for a
    /// local. Managed elements it holds are shared like any value's, so their
    /// origins still count.
    fn writtenArgumentOrigin(self: *const Context, function: typed.Function, origins: []const Origin, argument: typed.NodeId) Origin {
        const node = self.program.nodes[@backingInt(argument)];
        if (!typed.referenceArray(self.program.records, node.ty)) return self.nodeOrigin(function, origins, argument, 0);
        const own: Origin = if (node.data == .local and @backingInt(node.data.local) < function.signature.parameter_count)
            Origin.fromPosition(@intCast(@backingInt(node.data.local)))
        else
            .{};
        if (!mayContainManaged(self.program, node.ty)) return own;
        return Origin.merge(own, self.nodeOrigin(function, origins, argument, 0));
    }

    fn callResultOrigin(self: *const Context, function: typed.Function, origins: []const Origin, callee: typed.FunctionId, arguments: []const typed.NodeId, depth: usize) Origin {
        const index = @backingInt(callee);
        if (index >= self.summaries.len) return .{ .unknown = true };
        return self.substituteOrigin(function, origins, self.summaries[index].return_origin, arguments, depth + 1);
    }
};

/// Accumulates one call's writes into the caller's inferred summary.
const WriteSite = struct {
    context: *const Context,
    function: typed.Function,
    origins: []const Origin,
    arguments: []const typed.NodeId,
    summary: *Summary,

    fn absorbWrite(self: WriteSite, origin_value: Origin, span: source.Span) void {
        self.summary.writes = true;
        if (origin_value.unknown) {
            self.summary.mutates_unknown = true;
            self.summary.external = true;
            if (self.summary.witness == null) self.summary.witness = span;
            return;
        }
        if (origin_value.positions == 0) return;
        self.summary.mutates |= origin_value.positions;
        self.summary.external = true;
        if (self.summary.witness == null) self.summary.witness = span;
    }

    fn absorb(self: WriteSite, mask: u16, unknown: bool, span: source.Span) void {
        if (unknown) {
            self.summary.writes = true;
            // An unknown footprint can only reach caller state through an actual
            // argument. If every argument is definitely fresh, the writes stay local.
            var reaches_caller = false;
            for (self.arguments) |argument| {
                if (!self.context.nodeOrigin(self.function, self.origins, argument, 0).isFresh()) {
                    reaches_caller = true;
                    break;
                }
            }
            if (reaches_caller) {
                self.summary.mutates_unknown = true;
                self.summary.external = true;
                if (self.summary.witness == null) self.summary.witness = span;
            }
            return;
        }
        var position: u5 = 0;
        while (position < 16) : (position += 1) {
            if (mask & (@as(u16, 1) << @intCast(position)) == 0) continue;
            if (position >= self.arguments.len) {
                self.summary.writes = true;
                self.summary.mutates_unknown = true;
                self.summary.external = true;
                if (self.summary.witness == null) self.summary.witness = span;
                continue;
            }
            const origin_value = self.context.writtenArgumentOrigin(self.function, self.origins, self.arguments[position]);
            self.absorbWrite(origin_value, span);
        }
    }
};

/// Record an element write `a[i] = v` into a local. Only a fixed-array
/// parameter's own storage belongs to the caller — a `mut` one is the caller's
/// array, and any other is refused as an undeclared write exactly as a list
/// parameter is — so a write into any other local stays inside this frame.
fn absorbElementWrite(context: *const Context, function: typed.Function, origins: []const Origin, store: typed.Store, span: source.Span, summary: *Summary) void {
    const slot = @backingInt(store.slot);
    if (!store.element or slot >= function.signature.parameter_count) return;
    if (!typed.referenceArray(context.program.records, function.scope.locals[slot].ty)) return;
    const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = &.{}, .summary = summary };
    site.absorbWrite(Origin.fromPosition(@intCast(slot)), span);
}

fn absorbDirectWrite(context: *const Context, function: typed.Function, origins: []const Origin, node: typed.Node, summary: *Summary) void {
    const witness = mutation.typedNode(context.program, function, node) orelse return;
    if (witness.operation != .receiver_write) return;
    const origin_value = if (witness.owner) |owner|
        context.localOrigin(function, origins, owner)
    else if (witness.input) |position|
        Origin.fromPosition(position)
    else
        Origin{ .unknown = true };
    const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = &.{}, .summary = summary };
    site.absorbWrite(origin_value, witness.span);
}

fn absorbExpressionCall(context: *const Context, function: typed.Function, origins: []const Origin, node: typed.Node, summary: *Summary) void {
    switch (node.data) {
        .call => |call| {
            const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = call.arguments, .summary = summary };
            const footprint = effectiveFootprint(context.program, context.summaries, @backingInt(call.function));
            site.absorb(footprint.positions, footprint.unknown, node.span);
        },
        .invoke => |invoke| {
            const signature = callables.signature(context.program.nodes[@backingInt(invoke.callee)].ty, context.program.records);
            const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = invoke.arguments, .summary = summary };
            if (signature) |contract| {
                site.absorb(positionsBitset(contract.mutates), false, node.span);
            } else {
                site.absorb(0, true, node.span);
            }
        },
        else => {},
    }
}

/// Bind one statement's effect on the local origin table. A `return` merges its
/// value's origin into the summary; that reads only bindings already resolved,
/// because the first pass visits statements in source order.
fn applyStatement(context: *const Context, function: typed.Function, origins: []Origin, statement_id: typed.StatementId, summary: *Summary) void {
    const statement = context.program.statements[@backingInt(statement_id)];
    switch (statement.data) {
        .initialize, .assign => |store| {
            const value = context.nodeOrigin(function, origins, store.value, 0);
            const slot = @backingInt(store.slot);
            if (slot < origins.len) origins[slot] = Origin.merge(origins[slot], value);
            absorbElementWrite(context, function, origins, store, statement.span, summary);
        },
        .ret => |value| summary.return_origin = Origin.merge(summary.return_origin, context.nodeOrigin(function, origins, value, 0)),
        .match => |matched| bindArmPayloads(context, function, origins, matched, 0),
        else => {},
    }
}

fn applyExpression(context: *const Context, function: typed.Function, origins: []const Origin, expression_id: typed.NodeId, summary: *Summary) void {
    const node = context.program.nodes[@backingInt(expression_id)];
    absorbDirectWrite(context, function, origins, node, summary);
    absorbExpressionCall(context, function, origins, node, summary);
}

fn analyzeFunction(context: *const Context, index: usize) std.mem.Allocator.Error!Summary {
    const function = context.program.functions[index];
    const locals = function.scope.locals.len;
    const origins = try context.allocator.alloc(Origin, if (locals == 0) 1 else locals);
    defer context.allocator.free(origins);
    @memset(origins, .{});
    var summary = Summary{};
    // Bindings are resolved first, in source order. A hidden temporary such as
    // the receiver of `builder.buffer.append_byte(v)` is initialized by an
    // earlier statement than the expression that reads it, so a single walk that
    // also recorded writes could meet the read before the store and attribute the
    // write to fresh storage. Return origins are merged in the same first pass
    // because they only read the bindings that are already known.
    var bindings = try Walker.init(context.allocator, context.program, function.scope.body);
    defer bindings.deinit();
    while (try bindings.next()) |item| switch (item) {
        .statement => |statement_id| applyStatement(context, function, origins, statement_id, &summary),
        else => {},
    };
    var walker = try Walker.init(context.allocator, context.program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .expression => |expression_id| applyExpression(context, function, origins, expression_id, &summary),
        else => {},
    };
    return summary;
}

const FixedPoint = struct { summaries: []Summary, widened: bool };

/// Compute transitive mutation and return-origin summaries to a fixed point.
/// Budget exhaustion widens conservatively; it never reports a write as absent.
fn buildSummaries(allocator: std.mem.Allocator, program: typed.Program) std.mem.Allocator.Error!FixedPoint {
    const summaries = try allocator.alloc(Summary, program.functions.len);
    @memset(summaries, .{});
    var keep = true;
    defer if (keep) allocator.free(summaries);
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const context = Context{ .allocator = scratch.allocator(), .program = program, .summaries = summaries };
    const budget = program.functions.len * 4 + 32;
    var iteration: usize = 0;
    while (true) {
        var changed = false;
        for (program.functions, 0..) |_, index| {
            _ = scratch.reset(.retain_capacity);
            const computed = try analyzeFunction(&context, index);
            const merged = mergeSummaries(summaries[index], computed);
            if (!sameSummary(merged, summaries[index])) {
                summaries[index] = merged;
                changed = true;
            }
        }
        if (!changed) break;
        iteration += 1;
        if (iteration >= budget) break;
    }
    const widened = iteration >= budget and iteration != 0;
    if (widened) for (summaries) |*summary| {
        summary.mutates_unknown = true;
        summary.return_origin.unknown = true;
        summary.writes = true;
        summary.external = true;
    };
    keep = false;
    return .{ .summaries = summaries, .widened = widened };
}

fn publish(allocator: std.mem.Allocator, program: typed.Program, summaries: []const Summary) std.mem.Allocator.Error!void {
    for (program.functions, summaries, 0..) |function, summary, index| {
        const mutable = @constCast(&program.functions[index]);
        mutable.signature.mutation_facts = .{ .writes = summary.writes, .external = summary.external };
        var positions = summary.mutates;
        if (summary.mutates_unknown) {
            var bit: u5 = 0;
            while (bit < 16) : (bit += 1) {
                if (bit < function.signature.parameter_count) positions |= @as(u16, 1) << @intCast(bit);
            }
        }
        mutable.signature.mutates = try bitsetPositions(allocator, positions);
        mutable.signature.return_origin = try boundFromOrigin(allocator, summary.return_origin);
    }
}

fn permissionMessage(allocator: std.mem.Allocator, function: typed.Function, summary: Summary, permitted: u16, has_permission: bool) std.mem.Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    text.writer.print("managed write in `{s}` exceeds its contract", .{function.name}) catch return error.OutOfMemory;
    if (summary.mutates_unknown) {
        text.writer.writeAll("; the write target's origin could not be proven fresh or tied to a published input") catch return error.OutOfMemory;
    } else if (!has_permission) {
        text.writer.writeAll("; the declared effect ceiling does not include `mutation`") catch return error.OutOfMemory;
    } else {
        text.writer.writeAll("; the declared mutates footprint does not cover ") catch return error.OutOfMemory;
        var listed = false;
        var position: u5 = 0;
        while (position < 16) : (position += 1) {
            const bit = @as(u16, 1) << @intCast(position);
            if (summary.mutates & bit == 0 or permitted & bit != 0) continue;
            text.writer.print("{s}p{d}", .{ if (listed) ", " else "", position }) catch return error.OutOfMemory;
            listed = true;
        }
        text.writer.writeAll("; declare both effects(mutation) and mutates(...), or pass a fresh local snapshot") catch return error.OutOfMemory;
    }
    return allocator.dupe(u8, text.written()) catch return error.OutOfMemory;
}

/// Write one parameter's source name, falling back to `p<N>` when the checked
/// local carries no name. Positions are zero-based, matching `mutates(...)`.
fn writeParameterName(writer: *std.Io.Writer, function: typed.Function, position: u5) std.Io.Writer.Error!void {
    const index: usize = position;
    if (index < function.scope.locals.len) {
        const name = function.scope.locals[index].name;
        if (name.len != 0) return writer.writeAll(name);
    }
    try writer.print("p{d}", .{position});
}

/// Build the rejection for a written parameter that no `mut` marks, naming the
/// exact declaration the reader should paste. `positions` is the inferred write
/// set widened by every position an untraceable target could reach, so the paste
/// covers the whole contract the body needs.
fn unmarkedWriteMessage(allocator: std.mem.Allocator, src: source.Source, declared: ast.Function, function: typed.Function, positions: u16) std.mem.Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    text.writer.writeAll("this function writes ") catch return error.OutOfMemory;
    var listed = false;
    var position: u5 = 0;
    while (position < 16) : (position += 1) {
        if (positions & (@as(u16, 1) << @intCast(position)) == 0) continue;
        if (listed) text.writer.writeAll(", ") catch return error.OutOfMemory;
        text.writer.writeAll("`") catch return error.OutOfMemory;
        writeParameterName(&text.writer, function, position) catch return error.OutOfMemory;
        text.writer.print("` (parameter {d})", .{@as(u32, position) + 1}) catch return error.OutOfMemory;
        listed = true;
    }
    text.writer.writeAll(" reachable from the caller; declare ") catch return error.OutOfMemory;
    writeMutatedParameters(&text.writer, src, declared, function, positions) catch return error.OutOfMemory;
    return allocator.dupe(u8, text.written()) catch return error.OutOfMemory;
}

/// Build the rejection for a `mut` parameter the body never writes, with the
/// parameter's own declaration as the paste that removes the marker.
fn unusedMutMessage(allocator: std.mem.Allocator, src: source.Source, declared: ast.Function, function: typed.Function, position: u5) std.mem.Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    text.writer.writeAll("`") catch return error.OutOfMemory;
    writeParameterName(&text.writer, function, position) catch return error.OutOfMemory;
    text.writer.writeAll("` is declared `mut` but never written; remove `mut`: `") catch return error.OutOfMemory;
    writeMutatedParameter(&text.writer, src, declared, function, position) catch return error.OutOfMemory;
    text.writer.writeAll("`") catch return error.OutOfMemory;
    return allocator.dupe(u8, text.written()) catch return error.OutOfMemory;
}

/// Write one `name: mut T` declaration per set bit of `positions`, comma
/// separated. Each is a paste-ready parameter annotation.
fn writeMutatedParameters(writer: *std.Io.Writer, src: source.Source, declared: ast.Function, function: typed.Function, positions: u16) std.mem.Allocator.Error!void {
    var listed = false;
    var position: u5 = 0;
    while (position < 16) : (position += 1) {
        if (positions & (@as(u16, 1) << @intCast(position)) == 0) continue;
        if (listed) writer.writeAll(", ") catch return error.OutOfMemory;
        writer.writeAll("`") catch return error.OutOfMemory;
        try writeMutatedParameter(writer, src, declared, function, position);
        writer.writeAll("`") catch return error.OutOfMemory;
        listed = true;
    }
}

/// One parameter's declaration as `name: mut T`. The type is the source text the
/// reader actually wrote, so the paste is exactly the edit they need to make and
/// appears verbatim in the message.
fn writeMutatedParameter(writer: *std.Io.Writer, src: source.Source, declared: ast.Function, function: typed.Function, position: u5) std.mem.Allocator.Error!void {
    writeParameterName(writer, function, position) catch return error.OutOfMemory;
    writer.writeAll(": mut ") catch return error.OutOfMemory;
    const index: usize = position;
    if (index >= declared.signature.parameters.len) {
        writer.writeAll("T") catch return error.OutOfMemory;
        return;
    }
    writer.writeAll(src.text(declared.signature.parameters[index].ty)) catch return error.OutOfMemory;
}

/// Every parameter position an unattributed write could reach. An untraceable
/// target can only be caller state through an argument, and every argument of
/// this function is one of its own parameters.
fn unknownWritePositions(function: typed.Function) u16 {
    var positions: u16 = 0;
    var bit: u5 = 0;
    while (bit < 16) : (bit += 1) {
        if (bit < function.signature.parameter_count) positions |= @as(u16, 1) << @intCast(bit);
    }
    return positions;
}

/// What the mutation pass needs besides the checked program: the exporting
/// verdicts and the source its declaration-side messages quote.
pub const Request = struct {
    /// Whether each function is exported, in program order.
    exported: []const bool,
    /// Merged source of the checked program, for paste-ready diagnostics.
    src: source.Source,
    /// Parsed declarations, which carry each parameter's own type span.
    syntax: ast.Program,
    /// Diagnostic destination.
    sink: *diagnostic.Sink,
};

/// The syntax function one checked function was built from. A specialized
/// generic instance shares its template's declaration, so the template's spans
/// are the ones the reader sees.
fn declaringFunction(syntax: ast.Program, function: typed.Function) ast.Function {
    for (syntax.functions) |declared| {
        if (declared.name.start == function.declaration.start and declared.name.end == function.declaration.end) return declared;
    }
    return syntax.functions[0];
}

/// The declaration-side half of item 1: a written parameter must be declared
/// `mut`, and a declared `mut` must be written. Every message carries the exact
/// replacement text. A position already rejected by `checkMutTypes` is not
/// reported again here.
fn checkMutDeclarations(allocator: std.mem.Allocator, program: typed.Program, request: Request, index: usize, summary: Summary) std.mem.Allocator.Error!bool {
    const src = request.src;
    const sink = request.sink;

    const function = program.functions[index];
    const declared_function = declaringFunction(request.syntax, function);
    const positions: u16 = if (summary.mutates_unknown) unknownWritePositions(function) else summary.mutates;
    const declared = positionsBitset(function.signature.declared_mutates);
    var violated = false;
    if (summary.external and positions & ~declared != 0) {
        const message = try unmarkedWriteMessage(allocator, src, declared_function, function, positions & ~declared);
        try sink.items.append(allocator, .{
            .code = mutation_marker_code,
            .span = summary.witness orelse function.declaration,
            .message = message,
        });
        violated = true;
    }
    // A host declaration has no body to write, and a lambda implements a
    // destination contract that may permit more positions than it writes.
    if (function.policy.host != null or isLambdaName(function.name)) return violated;
    var position: u5 = 0;
    while (position < 16) : (position += 1) {
        if (declared & (@as(u16, 1) << @intCast(position)) == 0) continue;
        if (summary.mutates & (@as(u16, 1) << @intCast(position)) != 0) continue;
        const message = try unusedMutMessage(allocator, src, declared_function, function, position);
        try sink.items.append(allocator, .{
            .code = unused_mut_code,
            .span = function.scope.locals[position].declaration,
            .message = message,
        });
        violated = true;
    }
    return violated;
}

/// Whether one checked function is a lambda body rather than a declared
/// function. Lambdas take their parameter contract from the destination
/// callback type, which may permit writes the body does not perform.
fn isLambdaName(name: []const u8) bool {
    return std.mem.startsWith(u8, name, "lambda@");
}

fn checkDeclaredBound(allocator: std.mem.Allocator, program: typed.Program, index: usize, summary: Summary, sink: *diagnostic.Sink) std.mem.Allocator.Error!bool {
    const function = program.functions[index];
    if (!summary.external) return false;
    const permitted = positionsBitset(function.signature.declared_mutates);
    if (function.policy.effect_bound) |bound| {
        const has_permission = bound.allowed & effect_set.bit(.mutation) != 0;
        if (!has_permission) {
            const message = try permissionMessage(allocator, function, summary, permitted, has_permission);
            try sink.items.append(allocator, .{
                .code = permission_code,
                .span = summary.witness orelse function.declaration,
                .message = message,
                .related = .{ .span = bound.span, .message = "declared effect ceiling and mutates footprint are here" },
            });
            return true;
        }
        // A declared `mut` position already reports its own missing marker, so a
        // write that lands outside the declared set is reported there rather than
        // twice. Only an untraceable target, which no single position can cover,
        // stays a permission failure.
        if (summary.mutates_unknown and !mutCoversUnknown(permitted, function)) {
            const message = try permissionMessage(allocator, function, summary, permitted, has_permission);
            try sink.items.append(allocator, .{
                .code = permission_code,
                .span = summary.witness orelse function.declaration,
                .message = message,
                .related = .{ .span = bound.span, .message = "declared effect ceiling and mutates footprint are here" },
            });
            return true;
        }
    }
    return false;
}

/// Whether the declared `mut` positions already permit every position an
/// unattributed write could reach, which is what makes such a write the marker
/// error's business rather than a permission failure's.
fn mutCoversUnknown(permitted: u16, function: typed.Function) bool {
    return unknownWritePositions(function) & ~permitted == 0;
}

/// One pair of nominal record identities already assumed disjoint on a path.
pub const TypePair = struct { a: usize, b: usize };

fn registeredPair(stack: []const TypePair, a: usize, b: usize) bool {
    for (stack) |pair| if (pair.a == a and pair.b == b) return true;
    return false;
}

/// Whether a value of `target` may be one of `container`'s managed components.
fn aliasComponents(program: typed.Program, target: typed.Type, container: typed.Type, stack: []TypePair, depth: usize) bool {
    if (!container.isAggregate()) return false;
    const index = container.recordIndex();
    if (index >= program.records.len) return true;
    const record = program.records[index];
    if (record.shape.buffer) |element| if (typesMayAlias(program, target, element, stack, depth)) return true;
    if (record.shape.array) |array| if (typesMayAlias(program, target, array.element, stack, depth)) return true;
    if (record.shape.domain) |domain| if (typesMayAlias(program, target, domain, stack, depth)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        const payload = case.payload orelse continue;
        if (typesMayAlias(program, target, payload, stack, depth)) return true;
    };
    for (record.fields) |field| if (typesMayAlias(program, target, field.ty, stack, depth)) return true;
    return false;
}

/// Sound proof that two argument types cannot share mutable managed storage.
/// Distinct nominal identities only alias through a shared component; re-entering
/// the same pair on one path is treated as no new alias (coinductive).
pub fn typesMayAlias(program: typed.Program, a: typed.Type, b: typed.Type, stack: []TypePair, depth: usize) bool {
    if (a == b) return true;
    if (!mayContainManaged(program, a) or !mayContainManaged(program, b)) return false;
    if (!a.isAggregate() or !b.isAggregate()) return false;
    const ai = a.recordIndex();
    const bi = b.recordIndex();
    if (ai >= program.records.len or bi >= program.records.len) return true;
    if (ai == bi) return true;
    if (depth >= stack.len) return true;
    if (registeredPair(stack[0..depth], ai, bi)) return false;
    stack[depth] = .{ .a = ai, .b = bi };
    if (aliasComponents(program, a, b, stack, depth + 1)) return true;
    if (aliasComponents(program, b, a, stack, depth + 1)) return true;
    return false;
}

/// One checked call site's argument list and the parameter types it binds.
const CallSite = struct {
    function: typed.Function,
    origins: []const Origin,
    arguments: []const typed.NodeId,
    parameter_types: []const typed.Type = &.{},
    parameter_locals: []const typed.Local = &.{},
    sink: *diagnostic.Sink,

    fn typeAt(self: CallSite, index: usize) typed.Type {
        if (index < self.parameter_types.len) return self.parameter_types[index];
        return self.parameter_locals[index].ty;
    }
};

const OverlapChecker = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,
    summaries: []const Summary,

    /// Report the first writable/read-only argument pair not proven disjoint.
    fn checkArguments(self: *const OverlapChecker, site: CallSite, written_mask: u16) std.mem.Allocator.Error!bool {
        const context = Context{ .allocator = self.allocator, .program = self.program, .summaries = self.summaries };
        var written: u5 = 0;
        while (written < 16) : (written += 1) {
            const written_bit = @as(u16, 1) << @intCast(written);
            if (written_mask & written_bit == 0 or written >= site.arguments.len) continue;
            if (written >= site.arguments.len or !mayContainManaged(self.program, site.typeAt(written))) continue;
            if (context.nodeOrigin(site.function, site.origins, site.arguments[written], 0).isFresh()) continue;
            if (try self.checkReadOnly(&context, site, written, written_mask)) return true;
        }
        return false;
    }

    fn checkReadOnly(self: *const OverlapChecker, context: *const Context, site: CallSite, written: u5, written_mask: u16) std.mem.Allocator.Error!bool {
        var read_only: u5 = 0;
        while (read_only < 16) : (read_only += 1) {
            const read_bit = @as(u16, 1) << @intCast(read_only);
            if (read_only == written or read_only >= site.arguments.len) continue;
            if (written_mask & read_bit != 0) continue;
            const written_type = site.typeAt(written);
            const read_type = site.typeAt(read_only);
            if (!mayContainManaged(self.program, read_type)) continue;
            if (context.nodeOrigin(site.function, site.origins, site.arguments[read_only], 0).isFresh()) continue;
            var stack: [64]TypePair = undefined;
            if (!typesMayAlias(self.program, written_type, read_type, &stack, 0)) continue;
            try site.sink.items.append(self.allocator, .{
                .code = overlap_code,
                .span = self.program.nodes[@backingInt(site.arguments[read_only])].span,
                .message = "writable argument may alias an argument promised read-only; pass a fresh snapshot, make both inputs writable, or split the call",
                .related = .{
                    .span = self.program.nodes[@backingInt(site.arguments[written])].span,
                    .message = "writable argument originates here; the two input graphs are not proven disjoint",
                },
            });
            return true;
        }
        return false;
    }
};

fn overlapForCall(checker: *const OverlapChecker, function: typed.Function, origins: []const Origin, node: typed.Node, sink: *diagnostic.Sink) std.mem.Allocator.Error!bool {
    switch (node.data) {
        .call => |call| {
            const callee_index = @backingInt(call.function);
            const callee = checker.program.functions[callee_index];
            // Overlap is a proof obligation created by a declared `mutates(...)`
            // contract. An unannotated helper's inferred writes are not such a
            // promise, so forwarding shared inputs through it is ordinary
            // sequential aliasing; only a declared footprint is checked.
            if (callee.signature.declared_mutates.len == 0) return false;
            const mask = positionsBitset(callee.signature.declared_mutates);
            if (mask == 0) return false;
            const site = CallSite{
                .function = function,
                .origins = origins,
                .arguments = call.arguments,
                .parameter_locals = callee.scope.locals[0..callee.signature.parameter_count],
                .sink = sink,
            };
            return checker.checkArguments(site, mask);
        },
        .invoke => |invoke| {
            const signature = callables.signature(checker.program.nodes[@backingInt(invoke.callee)].ty, checker.program.records) orelse return false;
            const mask = positionsBitset(signature.mutates);
            if (mask == 0) return false;
            const site = CallSite{
                .function = function,
                .origins = origins,
                .arguments = invoke.arguments,
                .parameter_types = signature.parameters,
                .sink = sink,
            };
            return checker.checkArguments(site, mask);
        },
        else => return false,
    }
}

fn collectOverlaps(allocator: std.mem.Allocator, program: typed.Program, summaries: []const Summary, index: usize, sink: *diagnostic.Sink) std.mem.Allocator.Error!bool {
    const function = program.functions[index];
    const locals = function.scope.locals.len;
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    const origins = try scratch.allocator().alloc(Origin, if (locals == 0) 1 else locals);
    @memset(origins, .{});
    const checker = OverlapChecker{ .allocator = allocator, .program = program, .summaries = summaries };
    var violated = false;
    var walker = try Walker.init(scratch.allocator(), program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .statement => |statement_id| {
            const statement = program.statements[@backingInt(statement_id)];
            switch (statement.data) {
                .initialize, .assign => |store| {
                    const context = Context{ .allocator = allocator, .program = program, .summaries = summaries };
                    const value = context.nodeOrigin(function, origins, store.value, 0);
                    const slot = @backingInt(store.slot);
                    if (slot < origins.len) origins[slot] = Origin.merge(origins[slot], value);
                },
                else => {},
            }
        },
        .expression => |expression_id| {
            const node = program.nodes[@backingInt(expression_id)];
            if (try overlapForCall(&checker, function, origins, node, sink)) violated = true;
        },
    };
    return violated;
}

/// Enforce M2's mutation permissions over a checked program. Returns whether
/// any diagnostic was emitted; callers turn that into `error.SourceError`.
pub fn check(allocator: std.mem.Allocator, program: typed.Program, request: Request) std.mem.Allocator.Error!bool {
    const sink = request.sink;
    _ = request.exported;
    var violated = false;
    const built = try buildSummaries(allocator, program);
    try publish(allocator, program, built.summaries);
    if (built.widened and program.functions.len != 0) {
        try sink.items.append(allocator, .{
            .code = limit_code,
            .span = program.functions[0].declaration,
            .message = "mutation origin analysis exhausted its fixed-point budget; mutation and return-origin summaries widened conservatively",
        });
        violated = true;
    }
    for (program.functions, 0..) |_, index| {
        if (try checkDeclaredBound(allocator, program, index, built.summaries[index], sink)) violated = true;
    }
    // Item 1's declaration side: every write is declared `mut`, every `mut` is
    // written, and every `mut` names a type with storage to write.
    for (program.functions, 0..) |_, index| {
        if (try checkMutDeclarations(allocator, program, request, index, built.summaries[index])) violated = true;
    }

    for (program.functions, 0..) |_, index| {
        if (try collectOverlaps(allocator, program, built.summaries, index, sink)) violated = true;
    }
    return violated;
}

test "origin lattice merges positions and identifies fresh storage" {
    const t = std.testing;
    const param_one = Origin.fromPosition(1);
    const param_three = Origin.fromPosition(3);
    const merged = Origin.merge(param_one, param_three);
    try t.expect(merged.has(1));
    try t.expect(merged.has(3));
    try t.expect(!merged.isFresh());
    try t.expect(Origin.fresh().isFresh());
    try t.expect(!(Origin{ .unknown = true }).isFresh());
}

test "bitset helpers normalize and order parameter positions" {
    const t = std.testing;
    const positions = [_]u16{ 3, 0, 7 };
    try t.expectEqual(@as(u16, 0b1000_1001), positionsBitset(&positions));
    const slice = try bitsetPositions(t.allocator, 0b1000_1001);
    defer t.allocator.free(slice);
    try t.expectEqualSlices(u16, &.{ 0, 3, 7 }, slice);
}

test "managed reachability sees records and recursive collections" {
    const t = std.testing;
    const record = typed.Record{ .id = @fromBackingInt(0), .name = "Box", .declaration = .{ .start = 0, .end = 0 }, .managed = false, .fields = &.{.{ .name = "items", .declaration = .{ .start = 0, .end = 0 }, .ty = .i64 }} };
    const list = typed.Record{ .id = @fromBackingInt(1), .name = "list", .declaration = .{ .start = 0, .end = 0 }, .managed = true, .fields = &.{}, .shape = .{ .buffer = .i64 } };
    const records = [_]typed.Record{ record, list };
    const empty_nodes: []const typed.Node = &.{};
    const empty_statements: []const typed.Statement = &.{};
    const empty_functions: []const typed.Function = &.{};
    const program = typed.Program{
        .nodes = empty_nodes,
        .statements = empty_statements,
        .functions = empty_functions,
        .main = @fromBackingInt(0),
        .records = &records,
    };
    try t.expect(!mayContainManaged(program, .i64));
    try t.expect(mayContainManaged(program, @fromBackingInt(typed.Type.record_base + 1)));
    try t.expect(!mayContainManaged(program, @fromBackingInt(typed.Type.record_base)));
}
