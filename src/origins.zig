//! Local alias and mutation validation for M2.
//! Calls read only declared `mut` and `from` contracts; each body resolves its
//! finite local aliases independently, without a whole-program fixed point.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const mutation = @import("mutation.zig");
const diagnostic = @import("diagnostic.zig");
const source = @import("source.zig");
const callables = @import("callables.zig");
const return_borrow = @import("return_borrow.zig");
const Walker = @import("typed_walk.zig").Walker;
const value_semantics = @import("value_semantics.zig");
const value_checks = @import("value_semantics_check.zig");

/// Diagnostic code for an unused capability parameter without an underscore prefix.
pub const unused_capability_code = "E_UNUSED_CAPABILITY";

/// Diagnostic code for a managed write that exceeds its declared contract.
pub const permission_code = "E_MUTATION_PERMISSION";
/// Error code for a `mut` marker that is missing, unneeded or unauthorizable.
pub const mutation_marker_code = "E_MUTATION_MARKER";

/// A canonical, sorted set of parameter positions, without a machine-word limit.
const Positions = []const u16;

fn hasPosition(positions: Positions, position: u16) bool {
    return std.mem.indexOfScalar(u16, positions, position) != null;
}

fn containsPositions(all: Positions, subset: Positions) bool {
    for (subset) |position| if (!hasPosition(all, position)) return false;
    return true;
}

fn joinPositions(allocator: std.mem.Allocator, a: Positions, b: Positions) std.mem.Allocator.Error!Positions {
    if (containsPositions(a, b)) return a;
    if (containsPositions(b, a)) return b;
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    var left: usize = 0;
    var right: usize = 0;
    while (left < a.len or right < b.len) {
        if (right == b.len or (left < a.len and a[left] < b[right])) {
            try out.append(allocator, a[left]);
            left += 1;
        } else if (left == a.len or b[right] < a[left]) {
            try out.append(allocator, b[right]);
            right += 1;
        } else {
            try out.append(allocator, a[left]);
            left += 1;
            right += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn subtractPositions(allocator: std.mem.Allocator, all: Positions, excluded: Positions) std.mem.Allocator.Error!Positions {
    var out: std.ArrayList(u16) = .empty;
    errdefer out.deinit(allocator);
    for (all) |position| if (!hasPosition(excluded, position)) try out.append(allocator, position);
    return out.toOwnedSlice(allocator);
}

/// The caller parameters whose writable storage a local value may reach.
pub const Origin = struct {
    positions: Positions = &.{},
    unknown: bool = false,

    /// The origin of a reference to one parameter, including positions above 63.
    pub fn fromPosition(allocator: std.mem.Allocator, position: u16) std.mem.Allocator.Error!Origin {
        return .{ .positions = try allocator.dupe(u16, &.{position}) };
    }

    /// An origin disjoint from every caller input.
    pub fn fresh() Origin {
        return .{};
    }

    /// Join two origins without discarding any possible source.
    pub fn merge(allocator: std.mem.Allocator, a: Origin, b: Origin) std.mem.Allocator.Error!Origin {
        return .{ .positions = try joinPositions(allocator, a.positions, b.positions), .unknown = a.unknown or b.unknown };
    }

    /// Whether this value is proven disjoint from every caller input.
    pub fn isFresh(self: Origin) bool {
        return self.positions.len == 0 and !self.unknown;
    }

    /// Whether the origin names one parameter position.
    pub fn has(self: Origin, position: u16) bool {
        return hasPosition(self.positions, position);
    }
};

/// One body's local validation facts and its declared return contract.
pub const Summary = struct {
    return_origin: Origin = .{},
    mutates: Positions = &.{},
    mutates_unknown: bool = false,
    writes: bool = false,
    external: bool = false,
    witnesses: struct { external: ?source.Span = null, undeclared: ?source.Span = null } = .{},
};

/// Retained local validation facts for a body omitted by incremental checking.
pub const Fact = struct { summary: Summary = .{} };

/// The retained local facts for a body omitted from this check.
pub fn standIn(stubs: []const ?Fact, index: usize) ?Fact {
    return if (index < stubs.len) stubs[index] else null;
}

/// Compare local facts by contents; diagnostic witness spans do not participate.
pub fn sameSummary(a: Summary, b: Summary) bool {
    return std.mem.eql(u16, a.mutates, b.mutates) and a.mutates_unknown == b.mutates_unknown and
        a.writes == b.writes and a.external == b.external and
        std.mem.eql(u16, a.return_origin.positions, b.return_origin.positions) and a.return_origin.unknown == b.return_origin.unknown;
}

/// Whether a value of `ty` may reach managed storage another value could share.
pub fn mayContainManaged(program: typed.Program, ty: typed.Type) bool {
    var path: [64]typed.Type = undefined;
    return mayContainManagedDepth(program, ty, &path, 0);
}

/// `path` holds the types on the current walk: a recursive value type reaches
/// itself again through a boxed field (RECURSIVE-VALUES-2), and the visit
/// already on the path answers for everything below the repeat.
fn mayContainManagedDepth(program: typed.Program, ty: typed.Type, path: *[64]typed.Type, depth: usize) bool {
    if (!ty.isAggregate()) return false;
    const index = ty.recordIndex();
    if (index >= program.records.len) return true;
    if (depth == path.len) return true;
    for (path[0..depth]) |seen| if (seen == ty) return false;
    path[depth] = ty;
    const record = program.records[index];
    if (record.managed) {
        // Strings and bytes are immutable managed buffers; they carry no
        // writable storage and therefore no mutation origin.
        const kind = record.collection.kind;
        if (kind == .string or kind == .bytes) return false;
        return true;
    }
    if (record.shape.array) |array| if (mayContainManagedDepth(program, array.element, path, depth + 1)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (mayContainManagedDepth(program, payload, path, depth + 1)) return true;
    };
    for (record.fields) |field| if (mayContainManagedDepth(program, field.ty, path, depth + 1)) return true;
    return false;
}

fn managedElement(program: typed.Program, owner: typed.Type) bool {
    if (!owner.isAggregate()) return false;
    const index = owner.recordIndex();
    if (index >= program.records.len) return true;
    const element = program.records[index].shape.buffer orelse return true;
    return mayContainManaged(program, element);
}

fn originFromBound(bound: typed.ReturnOrigin) Origin {
    return switch (bound) {
        .fresh => .{},
        .unknown => .{ .unknown = true },
        .params => |positions| .{ .positions = positions },
    };
}

fn effectiveFootprint(program: typed.Program, index: usize) Positions {
    return program.functions[index].signature.declared_mutates;
}

/// Apply the block's own initialize/assign statements to the origin table. The
/// ordinary walker will visit them again; merging is idempotent and conservative.
fn applyBlockStatements(context: *const Context, function: typed.Function, origins: []Origin, body: typed.StatementId, depth: usize) std.mem.Allocator.Error!void {
    if (depth == 256) return;
    const statement = context.program.statements[@backingInt(body)];
    switch (statement.data) {
        .initialize, .assign => _ = try bindStatement(context, function, origins, statement, depth + 1),
        .match => |matched| {
            _ = try bindStatement(context, function, origins, statement, depth + 1);
            for (matched.arms) |arm| try applyBlockStatements(context, function, origins, arm.body, depth + 1);
        },
        .block => |children| for (children) |child| try applyBlockStatements(context, function, origins, child, depth + 1),
        .branch => |branch| {
            try applyBlockStatements(context, function, origins, branch.then_body, depth + 1);
            if (branch.else_body) |otherwise| try applyBlockStatements(context, function, origins, otherwise, depth + 1);
        },
        .range_loop => |range| {
            _ = try bindStatement(context, function, origins, statement, depth + 1);
            for (range.plan().setup) |setup| try applyBlockStatements(context, function, origins, setup, depth + 1);
            try applyBlockStatements(context, function, origins, range.plan().loop.body, depth + 1);
            if (range.plan().loop.step) |step| try applyBlockStatements(context, function, origins, step, depth + 1);
        },
        .loop => |loop| {
            try applyBlockStatements(context, function, origins, loop.body, depth + 1);
            if (loop.step) |step| try applyBlockStatements(context, function, origins, step, depth + 1);
        },
        .with_scope => |scope| try applyBlockStatements(context, function, origins, scope.body, depth + 1),
        else => {},
    }
}

/// Merge one binding statement's value origin into the local origin table and
/// report whether any local's origin grew. A store binds its slot to the value;
/// a `match` binds each arm's payload slot to the matched value, because a
/// payload of a class type is the very object the matched container holds, so
/// a write through it is a write to the container's owner.
fn bindStatement(context: *const Context, function: typed.Function, origins: []Origin, statement: typed.Statement, depth: usize) std.mem.Allocator.Error!bool {
    switch (statement.data) {
        .initialize, .assign => |store| {
            const grew = try bindStore(context, function, origins, store, depth);
            return grew;
        },
        .range_loop => |range| {
            var grew = false;
            for ([_]typed.Store{ range.plan().start, range.plan().end }) |store| {
                if (copiedHome(context.program, function, store.slot)) continue;
                const value = try context.nodeOrigin(function, origins, store.value, depth);
                grew = try widen(context.allocator, origins, @backingInt(store.slot), value) or grew;
            }
            return grew;
        },
        .match => |matched| {
            var grew = false;
            for (matched.arms) |arm| {
                const slot = arm.slot orelse continue;
                const index = @backingInt(slot);
                if (index >= function.scope.locals.len) continue;
                if (copiedHome(context.program, function, slot)) continue;
                const payload = function.scope.locals[index].ty;
                if (try widen(context.allocator, origins, index, try context.childIfManaged(payload, function, origins, matched.value, depth))) grew = true;
            }
            return grew;
        },
        else => return false,
    }
}

/// Complete tuple staging carries the same conservative child origins as the
/// field projections it replaces; ownership transfer does not erase effects.
fn bindStore(context: *const Context, function: typed.Function, origins: []Origin, store: typed.Store, depth: usize) std.mem.Allocator.Error!bool {
    // VALUE-SEMANTICS-4: a named local receives its own copy.
    if (copiedHome(context.program, function, store.slot)) return false;
    const value = try context.nodeOrigin(function, origins, store.value, depth);
    var grew = try widen(context.allocator, origins, @backingInt(store.slot), value);
    if (store.unpack) |fields| for (fields) |field| {
        const slot = field orelse continue;
        const ty = function.scope.locals[@backingInt(slot)].ty;
        if (!typed.carriesWritableStorage(context.program.records, ty)) continue;
        if (copiedHome(context.program, function, slot)) continue;
        grew = try widen(context.allocator, origins, @backingInt(slot), value) or grew;
    };
    return grew;
}

/// Under value semantics, whether a store into `slot` gives it a copy that
/// shares nothing writable with its source, so the local starts fresh: a named
/// local (not a parameter) whose type reaches no `class` or Cell.
fn copiedHome(program: typed.Program, function: typed.Function, slot: typed.LocalId) bool {
    const index = @backingInt(slot);
    if (index < function.signature.parameter_count or index >= function.scope.locals.len) return false;
    if (!value_semantics.namedHome(function, index)) return false;
    return value_semantics.copiesAll(program.records, function.scope.locals[index].ty);
}

/// Merge `value` into one slot's origin, reporting whether it grew.
fn widen(allocator: std.mem.Allocator, origins: []Origin, slot: usize, value: Origin) std.mem.Allocator.Error!bool {
    if (slot >= origins.len) return false;
    const merged = try Origin.merge(allocator, origins[slot], value);
    const grew = !std.mem.eql(u16, merged.positions, origins[slot].positions) or merged.unknown != origins[slot].unknown;
    origins[slot] = merged;
    return grew;
}

const Context = struct {
    allocator: std.mem.Allocator,
    program: typed.Program,

    fn tracks(self: *const Context, ty: typed.Type) bool {
        return mayContainManaged(self.program, ty);
    }

    /// Resolve the origin of one checked expression under the current local origins.
    fn nodeOrigin(self: *const Context, function: typed.Function, origins: []const Origin, node_id: typed.NodeId, depth: usize) std.mem.Allocator.Error!Origin {
        if (depth == 256) return .{ .unknown = true };
        const node = self.program.nodes[@backingInt(node_id)];
        return switch (node.data) {
            .local => |slot| try self.localOrigin(function, origins, slot),
            .field => |field| try self.childIfManaged(node.ty, function, origins, field.base, depth),
            .index => |index| try self.childIfManaged(node.ty, function, origins, index.base, depth),
            .cast => |value| try self.childIfManaged(node.ty, function, origins, value, depth),
            .wrap, .arena_escape => |value| try self.childIfManaged(node.ty, function, origins, value, depth),
            .restrict_resource => |restrict| try self.childIfManaged(node.ty, function, origins, restrict.value, depth),
            .unwrap => |value| try self.childIfManaged(node.ty, function, origins, value, depth),
            .stream_flush, .float_fma, .byte_load, .vector_binary, .vector_neg, .vector_sqrt, .vector_convert, .vector_select, .task_group_open, .task_result, .hole, .place_exchange => .{},
            .task_submit => .{},
            // A format string is its own fresh text: its holes are rendered into
            // storage this value owns, so nothing it carries aliases a caller input.
            .format => .{},
            .propagate => |propagate| try self.nodeOrigin(function, origins, propagate.value, depth + 1),
            .block_value => |block| if (self.tracks(node.ty)) try self.blockValueOrigin(function, origins, block, depth + 1) else Origin{},
            .borrow_selection => |selection| try Origin.merge(
                self.allocator,
                try self.childIfManaged(node.ty, function, origins, selection.first, depth),
                try self.childIfManaged(node.ty, function, origins, selection.second, depth),
            ),
            .variant => |variant| try self.variantOrigin(node.ty, function, origins, variant.value, depth),
            .array => |values| try self.mergeValues(function, origins, values, depth),
            .record => |fields| try self.mergeFields(function, origins, fields, depth),
            .update => |update| try self.updateOrigin(node.ty, function, origins, update, depth),
            .replace => |replace| try self.replaceOrigin(node.ty, function, origins, replace, depth),
            .buffer_operation => |operation| try self.bufferOrigin(node.ty, function, origins, operation),
            .call => |call| try self.callResultOrigin(function, origins, call.function, call.arguments, depth + 1),
            .invoke => |invoke| try self.invokeOrigin(function, origins, invoke, depth),
            .acquire_buffer,
            .acquire_resource,
            .accept_resource,
            .complete_resource,
            .dir_resource,
            .host_resource,
            .environment_get,
            .environment_only,
            .environment_names,
            .external_read,
            .stand_in,
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
            .blob,
            .function_value,
            => Origin{},
        };
    }

    fn childIfManaged(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, base: typed.NodeId, depth: usize) std.mem.Allocator.Error!Origin {
        // The test is writability, not managedness: a `byte_buffer` is managed
        // like `bytes` but keeps writable storage, so a write through it belongs
        // to whoever owns the buffer. A read-only `str`, `bytes` or scalar-only
        // record carries no origin because nothing can be written through it.
        if (!typed.carriesWritableStorage(self.program.records, ty)) return Origin{};
        const origin = try self.nodeOrigin(function, origins, base, depth + 1);
        return origin;
    }

    fn variantOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, value: ?typed.NodeId, depth: usize) std.mem.Allocator.Error!Origin {
        const payload = value orelse return Origin{};
        const origin = try self.childIfManaged(ty, function, origins, payload, depth);
        return origin;
    }

    fn updateOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, update: @FieldType(@FieldType(typed.Node, "data"), "update"), depth: usize) std.mem.Allocator.Error!Origin {
        var origin = try self.childIfManaged(ty, function, origins, update.base, depth);
        for (update.fields) |field| {
            if (!self.tracks(self.program.nodes[@backingInt(field.value)].ty)) continue;
            origin = try Origin.merge(self.allocator, origin, try self.nodeOrigin(function, origins, field.value, depth + 1));
        }
        return origin;
    }

    fn replaceOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, replace: @FieldType(@FieldType(typed.Node, "data"), "replace"), depth: usize) std.mem.Allocator.Error!Origin {
        const origin = try self.childIfManaged(ty, function, origins, replace.base, depth);
        const replacement = try self.nodeOrigin(function, origins, replace.value, depth + 1);
        const merged = try Origin.merge(self.allocator, origin, replacement);
        return merged;
    }

    fn bufferOrigin(self: *const Context, ty: typed.Type, function: typed.Function, origins: []const Origin, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) std.mem.Allocator.Error!Origin {
        if (!self.tracks(ty)) return Origin{};
        const owner = try self.localOrigin(function, origins, operation.owner);
        if (operation.kind == .copy and !self.ownerElementManaged(function, operation.owner)) return Origin{};
        return owner;
    }

    fn invokeOrigin(self: *const Context, function: typed.Function, origins: []const Origin, invoke: @FieldType(@FieldType(typed.Node, "data"), "invoke"), depth: usize) std.mem.Allocator.Error!Origin {
        const signature = callables.signature(self.program.nodes[@backingInt(invoke.callee)].ty, self.program.records) orelse return .{ .unknown = true };
        if (!self.tracks(signature.return_type)) return .{};
        const origin = try self.substituteOrigin(function, origins, originFromBound(signature.return_origin), invoke.arguments, depth + 1);
        return origin;
    }

    fn localOrigin(self: *const Context, function: typed.Function, origins: []const Origin, slot: typed.LocalId) std.mem.Allocator.Error!Origin {
        const index = @backingInt(slot);
        if (index < function.signature.parameter_count) {
            const origin = try Origin.fromPosition(self.allocator, @intCast(index));
            return origin;
        }
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
    fn blockValueOrigin(self: *const Context, function: typed.Function, origins: []const Origin, block: @FieldType(@FieldType(typed.Node, "data"), "block_value"), depth: usize) std.mem.Allocator.Error!Origin {
        if (depth == 256) return .{ .unknown = true };
        const mutable = @constCast(origins);
        try applyBlockStatements(self, function, mutable, block.body, depth + 1);
        const origin = try self.nodeOrigin(function, mutable, block.value, depth + 1);
        return origin;
    }

    fn mergeValues(self: *const Context, function: typed.Function, origins: []const Origin, values: []const typed.NodeId, depth: usize) std.mem.Allocator.Error!Origin {
        var origin = Origin{};
        for (values) |value| {
            if (!self.tracks(self.program.nodes[@backingInt(value)].ty)) continue;
            origin = try Origin.merge(self.allocator, origin, try self.nodeOrigin(function, origins, value, depth + 1));
        }
        return origin;
    }

    fn mergeFields(self: *const Context, function: typed.Function, origins: []const Origin, fields: []const typed.FieldInit, depth: usize) std.mem.Allocator.Error!Origin {
        var origin = Origin{};
        for (fields) |field| {
            if (!self.tracks(self.program.nodes[@backingInt(field.value)].ty)) continue;
            origin = try Origin.merge(self.allocator, origin, try self.nodeOrigin(function, origins, field.value, depth + 1));
        }
        return origin;
    }

    fn substituteOrigin(self: *const Context, function: typed.Function, origins: []const Origin, bound: Origin, arguments: []const typed.NodeId, depth: usize) std.mem.Allocator.Error!Origin {
        if (bound.unknown) return .{ .unknown = true };
        var origin = Origin{};
        for (bound.positions) |position| {
            if (position >= arguments.len) {
                origin.unknown = true;
                continue;
            }
            origin = try Origin.merge(self.allocator, origin, try self.nodeOrigin(function, origins, arguments[position], depth + 1));
        }
        return origin;
    }

    /// The caller inputs a callee's write through one argument can reach. A
    /// fixed array crosses a `mut` position as the caller's own variable, so a
    /// write to its elements reaches only that variable: a parameter's
    /// position when the argument passes a parameter on, fresh storage for a
    /// local. Managed elements it holds are shared like any value's, so their
    /// origins still count.
    fn writtenArgumentOrigin(self: *const Context, function: typed.Function, origins: []const Origin, argument: typed.NodeId) std.mem.Allocator.Error!Origin {
        var current = argument;
        var depth: usize = 0;
        while (depth < 256) : (depth += 1) {
            const node = self.program.nodes[@backingInt(current)];
            switch (node.data) {
                .local => |slot| {
                    const index = @backingInt(slot);
                    if (index < function.signature.parameter_count) {
                        const origin = try Origin.fromPosition(self.allocator, @intCast(index));
                        return origin;
                    }
                    if (index < function.scope.locals.len and function.scope.locals[index].usage.temporary) {
                        const origin = try self.localOrigin(function, origins, slot);
                        return origin;
                    }
                    return .{};
                },
                .block_value => |block| {
                    try applyBlockStatements(self, function, @constCast(origins), block.body, depth + 1);
                    current = block.value;
                },
                .field => |field| current = field.base,
                .index => |index| current = index.base,
                else => return .{},
            }
        }
        return .{ .unknown = true };
    }

    fn callResultOrigin(self: *const Context, function: typed.Function, origins: []const Origin, callee: typed.FunctionId, arguments: []const typed.NodeId, depth: usize) std.mem.Allocator.Error!Origin {
        const index = @backingInt(callee);
        if (index >= self.program.functions.len) return .{ .unknown = true };
        const signature = self.program.functions[index].signature;
        if (!self.tracks(signature.return_type)) return .{};
        const sources: Origin = .{ .positions = return_borrow.effectiveSources(self.program.records, signature) };
        const origin = try self.substituteOrigin(function, origins, sources, arguments, depth + 1);
        return origin;
    }
};

/// Accumulates one call's writes into the caller's inferred summary.
const WriteSite = struct {
    context: *const Context,
    function: typed.Function,
    origins: []const Origin,
    arguments: []const typed.NodeId,
    summary: *Summary,

    fn absorbWrite(self: WriteSite, origin_value: Origin, span: source.Span) std.mem.Allocator.Error!void {
        self.summary.writes = true;
        if (origin_value.unknown) {
            self.summary.mutates_unknown = true;
            self.summary.external = true;
            self.witness(try callerPositions(self.context.allocator, self.function), span);
            return;
        }
        var positions: std.ArrayList(u16) = .empty;
        for (origin_value.positions) |position| {
            if (!ownParameter(self.function, position)) try positions.append(self.context.allocator, position);
        }
        if (positions.items.len == 0) return;
        const retained = try positions.toOwnedSlice(self.context.allocator);
        self.summary.mutates = try joinPositions(self.context.allocator, self.summary.mutates, retained);
        self.summary.external = true;
        self.witness(retained, span);
    }

    fn witness(self: WriteSite, positions: Positions, span: source.Span) void {
        if (self.summary.witnesses.external == null) self.summary.witnesses.external = span;
        if (!containsPositions(self.function.signature.declared_mutates, positions) and self.summary.witnesses.undeclared == null) self.summary.witnesses.undeclared = span;
    }

    fn absorb(self: WriteSite, positions: Positions, unknown: bool, span: source.Span) std.mem.Allocator.Error!void {
        if (unknown) {
            self.summary.writes = true;
            for (self.arguments) |argument| {
                if ((try self.context.nodeOrigin(self.function, self.origins, argument, 0)).isFresh()) continue;
                self.summary.mutates_unknown = true;
                self.summary.external = true;
                self.witness(try callerPositions(self.context.allocator, self.function), span);
                break;
            }
            return;
        }
        for (positions) |position| {
            if (position >= self.arguments.len) {
                self.summary.writes = true;
                self.summary.mutates_unknown = true;
                self.summary.external = true;
                self.witness(try callerPositions(self.context.allocator, self.function), span);
                continue;
            }
            try self.absorbWrite(try self.context.writtenArgumentOrigin(self.function, self.origins, self.arguments[position]), span);
        }
    }
};

/// Record assignments that write a parameter's caller storage: fixed-array
/// elements and whole `mut` record or collection variables.
fn absorbElementWrite(context: *const Context, function: typed.Function, origins: []const Origin, store: typed.Store, span: source.Span, summary: *Summary) std.mem.Allocator.Error!void {
    const slot = @backingInt(store.slot);
    if (slot >= function.signature.parameter_count or ownParameter(function, slot)) return;
    const ty = function.scope.locals[slot].ty;
    const array_write = store.element and typed.referenceArray(context.program.records, ty);
    // VALUE-SEMANTICS-3: any assignment to a `mut` record parameter (a field
    // write rebuilds it) lands in the caller's record.
    const declared_mut = declaredMut(function, slot);
    const caller_write = array_write or declared_mut;
    if (!caller_write) return;
    const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = &.{}, .summary = summary };
    try site.absorbWrite(try Origin.fromPosition(context.allocator, @intCast(slot)), span);
}

/// Whether parameter `slot` of `function` is spelled `own`.
fn ownParameter(function: typed.Function, slot: usize) bool {
    return slot < function.scope.own_parameters.len and function.scope.own_parameters[slot];
}

fn declaredMut(function: typed.Function, slot: usize) bool {
    for (function.signature.declared_mutates) |position| if (position == slot) return true;
    return false;
}

fn absorbDirectWrite(context: *const Context, function: typed.Function, origins: []const Origin, node: typed.Node, summary: *Summary) std.mem.Allocator.Error!void {
    const witness = mutation.typedNode(context.program, function, node) orelse return;
    if (witness.operation != .receiver_write) return;
    const origin_value = if (witness.owner) |owner|
        try context.localOrigin(function, origins, owner)
    else if (witness.input) |position|
        try Origin.fromPosition(context.allocator, position)
    else
        Origin{ .unknown = true };
    const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = &.{}, .summary = summary };
    try site.absorbWrite(origin_value, witness.span);
}

fn absorbExpressionCall(context: *const Context, function: typed.Function, origins: []const Origin, node: typed.Node, summary: *Summary) std.mem.Allocator.Error!void {
    switch (node.data) {
        .call => |call| {
            const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = call.arguments, .summary = summary };
            const footprint = effectiveFootprint(context.program, @backingInt(call.function));
            try site.absorb(footprint, false, node.span);
        },
        .invoke => |invoke| {
            const signature = callables.signature(context.program.nodes[@backingInt(invoke.callee)].ty, context.program.records);
            const site = WriteSite{ .context = context, .function = function, .origins = origins, .arguments = invoke.arguments, .summary = summary };
            if (signature) |contract| {
                try site.absorb(contract.mutates, false, node.span);
            } else {
                try site.absorb(&.{}, true, node.span);
            }
        },
        else => {},
    }
}

/// Bind one statement's aliases and record writes to caller storage.
fn applyStatement(context: *const Context, function: typed.Function, origins: []Origin, statement_id: typed.StatementId, summary: *Summary) std.mem.Allocator.Error!bool {
    const statement = context.program.statements[@backingInt(statement_id)];
    switch (statement.data) {
        .initialize, .assign => |store| {
            const grew = try bindStatement(context, function, origins, statement, 0);
            try absorbElementWrite(context, function, origins, store, statement.span, summary);
            return grew;
        },
        else => {
            const grew = try bindStatement(context, function, origins, statement, 0);
            return grew;
        },
    }
}

fn applyExpression(context: *const Context, function: typed.Function, origins: []const Origin, expression_id: typed.NodeId, summary: *Summary) std.mem.Allocator.Error!void {
    const node = context.program.nodes[@backingInt(expression_id)];
    try absorbDirectWrite(context, function, origins, node, summary);
    try absorbExpressionCall(context, function, origins, node, summary);
}

fn analyzeFunction(context: *const Context, index: usize) std.mem.Allocator.Error!Summary {
    const function = context.program.functions[index];
    const locals = function.scope.locals.len;
    const origins = try context.allocator.alloc(Origin, if (locals == 0) 1 else locals);
    defer context.allocator.free(origins);
    @memset(origins, .{});
    var summary = Summary{ .return_origin = originFromBound(function.signature.return_origin) };
    // Bindings are resolved first, in source order. A hidden temporary such as
    // the receiver of `builder.buffer.append_byte(v)` is initialized by an
    // earlier statement than the expression that reads it, so a single walk that
    // also recorded writes could meet the read before the store and attribute the
    // write to fresh storage.
    // A loop can read a binding before a later statement widens it, so the
    // walk repeats until no local's origin grows. Each local only gains origins
    // from this function's finite set of parameters.
    var grew = true;
    while (grew) {
        grew = false;
        var bindings = try Walker.init(context.allocator, context.program, function.scope.body);
        defer bindings.deinit();
        while (try bindings.next()) |item| switch (item) {
            .statement => |statement_id| if (try applyStatement(context, function, origins, statement_id, &summary)) {
                grew = true;
            },
            else => {},
        };
    }
    var walker = try Walker.init(context.allocator, context.program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .expression => |expression_id| try applyExpression(context, function, origins, expression_id, &summary),
        else => {},
    };
    return summary;
}

/// Analyze each body once against declarations. Local alias closure remains finite.
fn buildSummaries(allocator: std.mem.Allocator, program: typed.Program, stubs: []const ?Fact) std.mem.Allocator.Error![]Summary {
    const summaries = try allocator.alloc(Summary, program.functions.len);
    errdefer allocator.free(summaries);
    var scratch = std.heap.ArenaAllocator.init(allocator);
    defer scratch.deinit();
    for (program.functions, summaries, 0..) |function, *summary, index| {
        if (standIn(stubs, index)) |fact| {
            summary.* = fact.summary;
        } else {
            _ = scratch.reset(.retain_capacity);
            const context: Context = .{ .allocator = scratch.allocator(), .program = program };
            summary.* = try analyzeFunction(&context, index);
            summary.mutates = try allocator.dupe(u16, summary.mutates);
        }
        summary.return_origin = originFromBound(function.signature.return_origin);
    }
    return summaries;
}

fn publish(program: typed.Program, summaries: []const Summary) void {
    for (program.functions, summaries, 0..) |function, summary, index| {
        const mutable = @constCast(&program.functions[index]);
        mutable.signature.inferred.writes = summary.writes;
        mutable.signature.inferred.external = summary.external;
        mutable.signature.mutates = function.signature.declared_mutates;
    }
}

/// Every parameter position of `function` the caller still holds, in order:
/// all of them except the `own` ones, which the caller gave away.
fn callerPositions(allocator: std.mem.Allocator, function: typed.Function) std.mem.Allocator.Error![]const u16 {
    var count: usize = 0;
    for (0..function.signature.parameter_count) |position| {
        if (!ownParameter(function, position)) count += 1;
    }
    const out = try allocator.alloc(u16, count);
    var written: usize = 0;
    for (0..function.signature.parameter_count) |position| {
        if (ownParameter(function, position)) continue;
        out[written] = @intCast(position);
        written += 1;
    }
    return out;
}

fn permissionMessage(allocator: std.mem.Allocator, function: typed.Function) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "managed write in `{s}` exceeds its contract; the write target's origin could not be proven fresh or tied to a published input", .{function.name});
}

/// Write one parameter's source name, falling back to `p<N>` when the checked
/// local carries no name. Positions are zero-based, matching `mutates(...)`.
fn writeParameterName(writer: *std.Io.Writer, function: typed.Function, position: u16) std.Io.Writer.Error!void {
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
fn unmarkedWriteMessage(allocator: std.mem.Allocator, src: source.Source, declared: ast.Function, function: typed.Function, positions: Positions) std.mem.Allocator.Error![]const u8 {
    var text: std.Io.Writer.Allocating = .init(allocator);
    defer text.deinit();
    text.writer.writeAll("this function writes ") catch return error.OutOfMemory;
    var listed = false;
    for (positions) |position| {
        if (listed) text.writer.writeAll(", ") catch return error.OutOfMemory;
        text.writer.writeAll("`") catch return error.OutOfMemory;
        writeParameterName(&text.writer, function, position) catch return error.OutOfMemory;
        text.writer.print("` (parameter {d})", .{@as(u32, position) + 1}) catch return error.OutOfMemory;
        listed = true;
    }
    // VALUE-SEMANTICS-4: a parameter is read-only unless declared `mut`.
    text.writer.writeAll(", which is read-only here; declare ") catch return error.OutOfMemory;
    writeMutatedParameters(&text.writer, src, declared, function, positions) catch return error.OutOfMemory;
    text.writer.writeAll(" so the change reaches the caller, or assign it to a local (`copy = ") catch return error.OutOfMemory;
    writeParameterName(&text.writer, function, positions[0]) catch return error.OutOfMemory;
    text.writer.writeAll("`) and change the copy") catch return error.OutOfMemory;
    return allocator.dupe(u8, text.written()) catch return error.OutOfMemory;
}

/// Write one `mut name: T` declaration per member of `positions`, comma
/// separated. Each is a paste-ready parameter annotation.
fn writeMutatedParameters(writer: *std.Io.Writer, src: source.Source, declared: ast.Function, function: typed.Function, positions: Positions) std.mem.Allocator.Error!void {
    var listed = false;
    for (positions) |position| {
        if (listed) writer.writeAll(", ") catch return error.OutOfMemory;
        writer.writeAll("`") catch return error.OutOfMemory;
        try writeMutatedParameter(writer, src, declared, function, position);
        writer.writeAll("`") catch return error.OutOfMemory;
        listed = true;
    }
}

/// One parameter's declaration as `mut name: T`. The type is the source text the
/// reader actually wrote, so the paste is exactly the edit they need to make and
/// appears verbatim in the message.
fn writeMutatedParameter(writer: *std.Io.Writer, src: source.Source, declared: ast.Function, function: typed.Function, position: u16) std.mem.Allocator.Error!void {
    writer.writeAll("mut ") catch return error.OutOfMemory;
    writeParameterName(writer, function, position) catch return error.OutOfMemory;
    writer.writeAll(": ") catch return error.OutOfMemory;
    const index: usize = position;
    if (index >= declared.signature.parameters.len) {
        writer.writeAll("T") catch return error.OutOfMemory;
        return;
    }
    writer.writeAll(src.text(declared.signature.parameters[index].ty)) catch return error.OutOfMemory;
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
    /// Stand-in facts for bodies this check did not materialize, by function
    /// index; such a function is neither analyzed nor diagnosed.
    stubs: []const ?Fact = &.{},
    /// When set, receives every function's final mutation summary.
    summaries: ?[]Summary = null,
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
/// `mut`. Unused declared caller-update capabilities remain valid. Every message carries the exact
/// replacement text. A position already rejected by `checkMutTypes` is not
/// reported again here.
fn checkMutDeclarations(allocator: std.mem.Allocator, program: typed.Program, request: Request, index: usize, summary: Summary) std.mem.Allocator.Error!bool {
    const src = request.src;
    const sink = request.sink;

    const function = program.functions[index];
    // The declaring syntax is found by a scan of every declaration, so it is
    // looked up only for a function that actually reports a diagnostic.
    const positions = if (summary.mutates_unknown) try callerPositions(allocator, function) else summary.mutates;
    const missing = try subtractPositions(allocator, positions, function.signature.declared_mutates);
    defer allocator.free(missing);
    var violated = false;
    if (summary.external and missing.len != 0) {
        const message = try unmarkedWriteMessage(allocator, src, declaringFunction(request.syntax, function), function, missing);
        // Only an attributed write names the parameters for certain; a widened
        // unknown write lists every position, scalars included, as advice.
        const fix = if (summary.mutates_unknown) null else try markParameters(allocator, request.syntax, function, missing);
        var item = diagnostic.ownership(.{ .code = mutation_marker_code, .rule = .M2 }, summary.witnesses.undeclared orelse summary.witnesses.external orelse function.declaration, message);
        item.provenance.fix = fix;
        try sink.items.append(allocator, item);
        violated = true;
    }
    return violated;
}

/// The syntax declaration of one checked function, or null when none has its
/// exact name span (a lambda body), so a fix never edits another signature.
fn exactDeclaration(syntax: ast.Program, function: typed.Function) ?ast.Function {
    for (syntax.functions) |declared| {
        if (declared.name.start == function.declaration.start and declared.name.end == function.declaration.end) return declared;
    }
    return null;
}

/// The fix for an unmarked written parameter: `mut ` in front of each written
/// parameter's declared name, in parameter order.
fn markParameters(allocator: std.mem.Allocator, syntax: ast.Program, function: typed.Function, positions: Positions) std.mem.Allocator.Error!?diagnostic.Fix {
    const declared = exactDeclaration(syntax, function) orelse return null;
    var edits: std.ArrayList(diagnostic.Edit) = .empty;
    for (positions) |position| {
        if (position >= declared.signature.parameters.len) return null;
        const at = declared.signature.parameters[position].name.start;
        try edits.append(allocator, .{ .span = .{ .start = at, .end = at }, .text = "mut " });
    }
    if (edits.items.len == 0) return null;
    return .{ .edit = edits.items[0], .more = edits.items[1..] };
}

fn checkDeclaredBound(allocator: std.mem.Allocator, program: typed.Program, index: usize, summary: Summary, sink: *diagnostic.Sink) std.mem.Allocator.Error!bool {
    const function = program.functions[index];
    if (!summary.external) return false;
    const permitted = function.signature.declared_mutates;
    if (summary.mutates_unknown and !mutCoversUnknown(permitted, function)) {
        const message = try permissionMessage(allocator, function);
        var item = diagnostic.ownership(.{ .code = permission_code, .rule = .M2 }, summary.witnesses.external orelse function.declaration, message);
        item.related = .{ .span = function.declaration, .message = "declared mutation parameters are here" };
        try sink.items.append(allocator, item);
        return true;
    }
    return false;
}

/// Whether the declared `mut` positions already permit every position an
/// unattributed write could reach, which is what makes such a write the marker
/// error's business rather than a permission failure's.
fn mutCoversUnknown(permitted: Positions, function: typed.Function) bool {
    for (0..function.signature.parameter_count) |position| {
        if (!ownParameter(function, position) and !hasPosition(permitted, @intCast(position))) return false;
    }
    return true;
}

/// Enforce M2's mutation permissions over a checked program. Returns whether
/// any diagnostic was emitted; callers turn that into `error.SourceError`.
pub fn check(allocator: std.mem.Allocator, program: typed.Program, request: Request) std.mem.Allocator.Error!bool {
    const sink = request.sink;
    _ = request.exported;
    var violated = false;
    const summaries = try buildSummaries(allocator, program, request.stubs);
    defer allocator.free(summaries);
    publish(program, summaries);
    if (request.summaries) |out| {
        for (out, 0..) |*summary, index| summary.* = if (index < summaries.len) summaries[index] else .{};
    }
    // A stood-in body passed the mutation checks when it was last checked, and its
    // own facts and every callee fact it reads are unchanged, so it is skipped.
    for (program.functions, 0..) |_, index| {
        if (standIn(request.stubs, index) != null) continue;
        if (try checkDeclaredBound(allocator, program, index, summaries[index], sink)) violated = true;
    }
    // Every caller-visible write must be declared `mut`; an unused capability
    // remains valid.
    for (program.functions, 0..) |_, index| {
        if (standIn(request.stubs, index) != null) continue;
        if (try checkMutDeclarations(allocator, program, request, index, summaries[index])) violated = true;
    }

    // Binding writability and writes into returned temporaries stay in the
    // front end. Core alone checks whether active call arguments overlap.
    for (program.functions, 0..) |_, index| {
        if (standIn(request.stubs, index) != null) continue;
        if (try value_checks.checkWrites(allocator, program, index, sink)) violated = true;
    }
    return violated;
}

test "origin sets retain every parameter position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const merged = try Origin.merge(a, try Origin.fromPosition(a, 1), try Origin.fromPosition(a, 129));
    try std.testing.expectEqualSlices(u16, &.{ 1, 129 }, merged.positions);
    try std.testing.expect(merged.has(129));
    try std.testing.expect(!merged.isFresh());
    try std.testing.expect(Origin.fresh().isFresh());
}

test "parameter sets join duplicate and arbitrary positions" {
    const a = std.testing.allocator;
    const positions = try joinPositions(a, &.{ 0, 64, 129 }, &.{ 3, 64 });
    defer a.free(positions);
    try std.testing.expectEqualSlices(u16, &.{ 0, 3, 64, 129 }, positions);
}

fn subtractPositionsAllocations(allocator: std.mem.Allocator) !void {
    var all: [256]u16 = undefined;
    for (&all, 0..) |*position, index| position.* = @intCast(index);
    const remaining = try subtractPositions(allocator, &all, &.{ 0, 64, 129, 255 });
    defer allocator.free(remaining);
    try std.testing.expectEqual(@as(usize, 252), remaining.len);
    try std.testing.expectEqual(@as(u16, 1), remaining[0]);
    try std.testing.expectEqual(@as(u16, 65), remaining[63]);
    try std.testing.expectEqual(@as(u16, 130), remaining[127]);
    try std.testing.expectEqual(@as(u16, 254), remaining[251]);
}

test "subtractPositions frees partial source sets on allocation failure" {
    const allocator = std.testing.allocator;
    var failing = std.testing.FailingAllocator.init(allocator, .{ .fail_index = 1, .resize_fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, subtractPositionsAllocations(failing.allocator()));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
    var stable = std.testing.FailingAllocator.init(allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(stable.allocator(), subtractPositionsAllocations, .{});
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

/// Source inputs and optional incremental facts for mutation enforcement.
pub const Enforcement = struct {
    exported: []const bool,
    src: source.Source,
    syntax: ast.Program,
    sink: *diagnostic.Sink,
    stubs: []const ?Fact = &.{},
    facts: ?[]Fact = null,
};

/// Enforce mutation guarantees and publish retained incremental facts.
pub fn enforce(allocator: std.mem.Allocator, program: typed.Program, request: Enforcement) diagnostic.Error!void {
    const summaries: ?[]Summary = if (request.facts) |facts| try allocator.alloc(Summary, facts.len) else null;
    defer if (summaries) |owned| allocator.free(owned);
    const violated = try check(allocator, program, .{
        .exported = request.exported,
        .src = request.src,
        .syntax = request.syntax,
        .sink = request.sink,
        .stubs = request.stubs,
        .summaries = summaries,
    });
    if (request.facts) |facts| for (facts, 0..) |*fact, index| {
        fact.* = .{ .summary = summaries.?[index] };
    };
    if (violated) return error.SourceError;
}

/// Choose a collision-free underscore name and explain its certain rename repair.
pub fn unusedCapabilityRepair(allocator: std.mem.Allocator, bytes: []const u8, name: []const u8) std.mem.Allocator.Error!struct { replacement: []const u8, message: []const u8 } {
    const stem = try std.fmt.allocPrint(allocator, "_{s}", .{name});
    defer allocator.free(stem);
    const replacement = try @import("migration_support.zig").freshName(allocator, .{ .path = "", .bytes = bytes, .line_starts = &.{} }, stem);
    errdefer allocator.free(replacement);
    return .{ .replacement = replacement, .message = try std.fmt.allocPrint(allocator, "capability parameter `{s}` is never used; rename it to `{s}` to retain the callback signature, or remove it", .{ name, replacement }) };
}

/// The refusal of an unused Stream parameter of the entry `main`: the entry's Streams must be named `out` or `err`, so the
/// rename `unusedCapabilityRepair` offers is refused (E_MAIN) and the parameter is deleted instead.
pub fn unusedEntryStreamMessage(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(allocator, "capability parameter `{s}` is never used; delete the parameter (an entry Stream parameter must be named `out` or `err`, so it cannot be renamed `_{s}`)", .{ name, name });
}

// spec-case: CAPABILITY-UNUSED-1
test "unusedCapabilityRepair frees fresh name when message allocation fails" {
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 2 });
    try std.testing.expectError(error.OutOfMemory, unusedCapabilityRepair(failing.allocator(), "out", "out"));
    try std.testing.expectEqual(failing.allocated_bytes, failing.freed_bytes);
}

// Declared recursion remains independent of any whole-program iteration budget.
fn coverageBudgetProgram(a: std.mem.Allocator) !typed.Program {
    const count = 130;
    const span: source.Span = .{ .start = 0, .end = 0 };
    const list_type: typed.Type = @fromBackingInt(typed.Type.record_base);
    const locals = try a.alloc(typed.Local, count);
    const nodes = try a.alloc(typed.Node, count + 3);
    const arguments = try a.alloc(typed.NodeId, count);
    const mutates = try a.alloc(u16, count);
    for (locals, 0..) |*local, index| {
        local.* = .{ .name = "parameter", .declaration = span, .ty = list_type, .mutable = true, .origin = .parameter };
        nodes[index] = .{ .span = span, .ty = list_type, .data = .{ .local = @fromBackingInt(index) } };
        arguments[index] = @fromBackingInt((index + 1) % count);
        mutates[index] = @intCast(index);
    }
    nodes[count] = .{ .span = span, .ty = .i64, .data = .{ .integer = 1 } };
    nodes[count + 1] = .{ .span = span, .ty = .unit, .data = .{ .buffer_operation = .{ .kind = .append, .owner = @fromBackingInt(0), .arguments = try a.dupe(typed.NodeId, &.{@fromBackingInt(count)}) } } };
    nodes[count + 2] = .{ .span = span, .ty = .unit, .data = .{ .call = .{ .function = @fromBackingInt(0), .arguments = arguments } } };
    const statements = try a.dupe(typed.Statement, &.{
        .{ .span = span, .terminates = false, .data = .{ .discard = @fromBackingInt(count + 1) } },
        .{ .span = span, .terminates = false, .data = .{ .discard = @fromBackingInt(count + 2) } },
        .{ .span = span, .terminates = false, .data = .{ .block = try a.dupe(typed.StatementId, &.{ @fromBackingInt(0), @fromBackingInt(1) }) } },
    });
    const functions = try a.dupe(typed.Function, &.{.{
        .id = @fromBackingInt(0),
        .name = "rotate",
        .declaration = span,
        .signature = .{ .parameter_count = count, .return_type = .unit, .declared_mutates = mutates },
        .scope = .{ .body = @fromBackingInt(2), .locals = locals, .body_complete = true },
    }});
    const records = try a.dupe(typed.Record, &.{.{ .id = @fromBackingInt(0), .name = "List", .declaration = span, .managed = true, .fields = &.{}, .shape = .{ .buffer = .i64 } }});
    return .{ .nodes = nodes, .statements = statements, .functions = functions, .records = records, .main = @fromBackingInt(0) };
}

test "ownership declared recursion supports more than 64 mutation parameters" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const program = try coverageBudgetProgram(arena.allocator());
    const summaries = try buildSummaries(arena.allocator(), program, &.{});
    try std.testing.expect(!summaries[0].mutates_unknown);
    try std.testing.expectEqual(@as(usize, 130), summaries[0].mutates.len);
    try std.testing.expectEqual(@as(u16, 129), summaries[0].mutates[129]);
    var sink: diagnostic.Sink = .{ .allocator = arena.allocator() };
    const request: Request = .{ .exported = &.{false}, .src = try source.Source.init(arena.allocator(), "rotation.selka", ""), .syntax = .{ .nodes = .empty, .statements = .empty, .functions = &.{} }, .sink = &sink };
    try std.testing.expect(!try check(arena.allocator(), program, request));
    try std.testing.expectEqual(@as(usize, 0), sink.items.items.len);
}
