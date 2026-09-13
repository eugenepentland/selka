//! Lower managed collection expressions to existing rooted locals and control flow.
const std = @import("std");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;
const Error = @import("diagnostic.zig").Error;
/// Shared diagnostic for invalid managed collection types.
pub const list_type_error = "E_LIST_TYPE";
const Kind = @import("buffer_operations.zig").Kind;

/// Materialize the canonical built-in list application for inferred elements.
pub fn listType(catalog: *@import("type_catalog.zig").Catalog, element: typed.Type, span: Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    const declaration = state.index.names.get("List") orelse return error.InternalError;
    return @import("nominal_catalog.zig").instantiateLengths(catalog, declaration, &.{element}, &.{}, span);
}

/// Resolve a managed operation output without conflating list, text, and map schemas.
pub fn operationType(catalog: *@import("type_catalog.zig").Catalog, owner: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    const schema = catalog.records[owner.recordIndex()];
    const element = schema.shape.buffer.?;
    if (schema.collection.kind == .list) return switch (kind) {
        .read => element,
        .contains => .bool,
        .length, .capacity => .u64,
        .append, .write, .iteration_check => .unit,
        else => error.InternalError,
    };
    const dictionary = schema.collection.kind == .dictionary;
    return switch (kind) {
        .length => .i64,
        .contains => .bool,
        .iteration_check => .unit,
        .read => if (dictionary) element else owner,
        .write => if (dictionary) .unit else error.InternalError,
        .get => if (dictionary) element else error.InternalError,
        .key_at => if (dictionary) schema.collection.key.? else error.InternalError,
        .slice, .join => if (!dictionary) owner else error.InternalError,
        .keys => if (dictionary) listType(catalog, schema.collection.key.?, span) else error.InternalError,
        .values => if (dictionary) listType(catalog, element, span) else error.InternalError,
        .split => if (!dictionary) listType(catalog, owner, span) else error.InternalError,
        else => error.InternalError,
    };
}

/// Append checked statements and expressions without manufacturing source names.
pub fn Builder(comptime Checker: type) type {
    return struct {
        checker: *Checker,
        span: Span,
        python_assignment_order: bool = false,
        const Self = @This();
        /// Add a checked expression to the shared table.
        pub fn node(self: Self, ty: typed.Type, data: @FieldType(typed.Node, "data")) Error!typed.NodeId {
            const id: typed.NodeId = @fromBackingInt(self.checker.nodes.items.len);
            try self.checker.nodes.append(self.checker.allocator, .{ .span = self.span, .ty = ty, .data = data });
            return id;
        }
        /// Add a nonterminating checked statement.
        pub fn stmt(self: Self, data: @FieldType(typed.Statement, "data")) Error!typed.StatementId {
            const id: typed.StatementId = @fromBackingInt(self.checker.statements.items.len);
            try self.checker.statements.append(self.checker.allocator, .{ .span = self.span, .terminates = false, .data = data });
            return id;
        }
        /// Reserve an internal local; VM frame roots retain its managed value.
        pub fn local(self: Self, ty: typed.Type) Error!typed.LocalId {
            const slot: typed.LocalId = @fromBackingInt(self.checker.locals.items.len);
            try self.checker.locals.append(self.checker.allocator, .{ .name = "<collection>", .declaration = self.span, .ty = ty, .mutable = true, .usage = .{ .reads = 1, .temporary = true } });
            return slot;
        }
        /// Read an internal local.
        pub fn read(self: Self, slot: typed.LocalId) Error!typed.NodeId {
            return self.node(self.checker.locals.items[@backingInt(slot)].ty, .{ .local = slot });
        }
        /// Create a signed integer literal.
        pub fn integer(self: Self, value: i128) Error!typed.NodeId {
            return self.node(.i64, .{ .integer = value });
        }
        /// Retain statement storage before returning a block expression.
        pub fn block(self: Self, statements: []const typed.StatementId, value: typed.NodeId) Error!typed.Node {
            const owned = try self.checker.allocator.dupe(typed.StatementId, statements);
            const body = try self.stmt(.{ .block = owned });
            return .{ .span = self.span, .ty = self.checker.nodes.items[@backingInt(value)].ty, .data = .{ .block_value = .{ .body = body, .value = value } } };
        }
        /// Construct an operation on a receiver that has already been rooted.
        pub fn operation(self: Self, slot: typed.LocalId, kind: Kind, arguments: []const typed.NodeId) Error!typed.NodeId {
            const owner_type = self.checker.locals.items[@backingInt(slot)].ty;
            const ty = try operationType(&self.checker.catalog, owner_type, kind, self.span);
            return self.node(ty, .{ .buffer_operation = .{ .owner = slot, .kind = kind, .arguments = try self.checker.allocator.dupe(typed.NodeId, arguments) } });
        }
        /// Read collection length with the ordinary signed index type.
        pub fn length(self: Self, slot: typed.LocalId) Error!typed.NodeId {
            return self.node(.i64, .{ .cast = try self.operation(slot, .length, &.{}) });
        }
        /// Create a binary operation with explicit result type.
        pub fn binary(self: Self, op: typed.BinaryOp, left: typed.NodeId, right: typed.NodeId, ty: typed.Type) Error!typed.NodeId {
            return self.node(ty, .{ .binary = .{ .op = op, .left = left, .right = right, .op_span = self.span } });
        }
        /// Normalize negative signed indices once; slices additionally clamp endpoints.
        pub fn index(self: Self, owner: typed.LocalId, input: typed.NodeId, clamp: bool) Error!typed.NodeId {
            const input_type = self.checker.nodes.items[@backingInt(input)].ty;
            if (!input_type.isInteger()) return self.checker.sink.fail("E_TYPE", self.span, "collection index requires an integer");
            const slot = try self.local(.i64);
            const value = if (input_type == .i64) input else try self.node(.i64, .{ .cast = input });
            var statements: std.ArrayList(typed.StatementId) = .empty;
            try statements.append(self.checker.allocator, try self.stmt(.{ .initialize = .{ .slot = slot, .value = value } }));
            const current = try self.read(slot);
            const zero = try self.integer(0);
            const count = try self.length(owner);
            const negative = try self.binary(.lt, current, zero, .bool);
            const normalized = try self.binary(.add, count, current, .i64);
            const fix = try self.stmt(.{ .assign = .{ .slot = slot, .value = normalized } });
            try statements.append(self.checker.allocator, try self.stmt(.{ .branch = .{ .condition = negative, .then_body = fix, .else_body = null } }));
            if (clamp) {
                const low = try self.stmt(.{ .assign = .{ .slot = slot, .value = zero } });
                const high = try self.stmt(.{ .assign = .{ .slot = slot, .value = count } });
                try statements.append(self.checker.allocator, try self.stmt(.{ .branch = .{ .condition = negative, .then_body = low, .else_body = null } }));
                try statements.append(self.checker.allocator, try self.stmt(.{ .branch = .{ .condition = try self.binary(.gt, current, count, .bool), .then_body = high, .else_body = null } }));
            }
            const block_value = try self.block(statements.items, current);
            return self.node(block_value.ty, block_value.data);
        }
        /// Root the receiver before evaluating indices and element-producing arguments.
        pub fn access(self: Self, base: typed.NodeId, kind: Kind, inputs: []const typed.NodeId, signed_length: bool) Error!typed.Node {
            const ty = self.checker.nodes.items[@backingInt(base)].ty;
            const owner = try self.local(ty);
            const init = try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } });
            const arguments = try self.checker.allocator.dupe(typed.NodeId, inputs);
            var statements: std.ArrayList(typed.StatementId) = .empty;
            if (kind == .write and self.python_assignment_order) {
                const value_slot = try self.local(self.checker.nodes.items[@backingInt(arguments[1])].ty);
                try statements.append(self.checker.allocator, try self.stmt(.{ .initialize = .{ .slot = value_slot, .value = arguments[1] } }));
                arguments[1] = try self.read(value_slot);
            }
            try statements.append(self.checker.allocator, init);
            const list_receiver = self.checker.catalog.records[ty.recordIndex()].collection.kind == .list;
            if (list_receiver and (kind == .read or kind == .write)) arguments[0] = try self.index(owner, arguments[0], false);
            const result = if (signed_length) try self.length(owner) else try self.operation(owner, kind, arguments);
            return self.block(statements.items, result);
        }
        /// Construct a fresh list and append elements in source order.
        pub fn literal(self: Self, ty: typed.Type, values: []const typed.NodeId) Error!typed.Node {
            const capacity = try self.integer(@intCast(values.len));
            const acquire = try self.node(ty, .{ .acquire_buffer = .{ .allocator = capacity, .capacity = capacity, .managed = true } });
            const owner = try self.local(ty);
            var statements: std.ArrayList(typed.StatementId) = .empty;
            try statements.append(self.checker.allocator, try self.stmt(.{ .initialize = .{ .slot = owner, .value = acquire } }));
            for (values) |value| try statements.append(self.checker.allocator, try self.stmt(.{ .discard = try self.operation(owner, .append, &.{value}) }));
            return self.block(statements.items, try self.read(owner));
        }
        /// Root text once, then evaluate each optional slice endpoint in order.
        pub fn textSlice(self: Self, base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId) Error!typed.Node {
            const owner = try self.local(self.checker.nodes.items[@backingInt(base)].ty);
            return self.block(&.{try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } })}, try self.operation(owner, .slice, &.{ start orelse try self.integer(0), end orelse try self.length(owner) }));
        }
        /// Copy a bounded slice into a fresh list using existing checked loop instructions.
        pub fn slice(self: Self, base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId) Error!typed.Node {
            const ty = self.checker.nodes.items[@backingInt(base)].ty;
            const owner = try self.local(ty);
            const output = try self.local(ty);
            const index_slot = try self.local(.i64);
            const limit_slot = try self.local(.i64);
            const zero = try self.integer(0);
            const acquire = try self.node(ty, .{ .acquire_buffer = .{ .allocator = zero, .capacity = zero, .managed = true } });
            const i = try self.read(index_slot);
            const loop_id = self.checker.loops.next;
            self.checker.loops.next += 1;
            const body = try self.stmt(.{ .discard = try self.operation(output, .append, &.{try self.operation(owner, .read, &.{i})}) });
            const step = try self.stmt(.{ .assign = .{ .slot = index_slot, .value = try self.binary(.add, i, try self.integer(1), .i64) } });
            return self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } }),
                try self.stmt(.{ .initialize = .{ .slot = index_slot, .value = if (start) |v| try self.index(owner, v, true) else zero } }),
                try self.stmt(.{ .initialize = .{ .slot = limit_slot, .value = if (end) |v| try self.index(owner, v, true) else try self.length(owner) } }),
                try self.stmt(.{ .initialize = .{ .slot = output, .value = acquire } }),
                try self.stmt(.{ .loop = .{ .id = loop_id, .condition = try self.binary(.lt, i, try self.read(limit_slot), .bool), .body = body, .step = step } }),
            }, try self.read(output));
        }
    };
}
