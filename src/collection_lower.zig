//! Lower managed collection expressions to existing rooted locals and control flow.
const std = @import("std");
const typed = @import("typed.zig");
const Span = @import("source.zig").Span;
const Error = @import("diagnostic.zig").Error;
/// Shared diagnostic for invalid managed collection types.
pub const list_type_error = "E_LIST_TYPE";
/// Omitted slice endpoints, mirrored by `MYL_NATIVE_SLICE_FIRST`/`_LAST` in the runtime.
const omitted_first: i128 = std.math.minInt(i64);
const omitted_last: i128 = std.math.maxInt(i64);
const operations = @import("buffer_operations.zig");
const Kind = operations.Kind;
const nominal = @import("nominal_catalog.zig");
const Catalog = @import("type_catalog.zig").Catalog;

/// Materialize the canonical built-in list application for inferred elements.
pub fn listType(catalog: *Catalog, element: typed.Type, span: Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    const declaration = state.index.names.get("List") orelse return error.InternalError;
    return nominal.instantiateLengths(catalog, declaration, &.{element}, &.{}, span);
}

/// Materialize a parameterless prelude collection such as `str` or `bytes`.
pub fn preludeType(catalog: *Catalog, name: []const u8, span: Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    // A collection operation can produce `bytes` without the source naming the
    // type, so materialize its schema on demand; a declared type still wins.
    if (std.mem.eql(u8, name, "bytes") and !state.index.names.contains("bytes")) try state.index.addByteString();
    // The mutable octet buffer is materialized the same way, so a program that
    // never names one carries no extra prelude type.
    if (std.mem.eql(u8, name, "byte_buffer") and !state.index.names.contains("byte_buffer")) try state.index.addByteBuffer();
    const declaration = state.index.names.get(name) orelse return error.InternalError;
    const builtin = state.index.declarations.items[declaration].builtin_name orelse return error.InternalError;
    if (!std.mem.eql(u8, builtin, name)) return error.InternalError;
    return nominal.instantiateLengths(catalog, declaration, &.{}, &.{}, span);
}

/// Materialize the builtin checked result used by fallible byte conversions.
pub fn resultType(catalog: *Catalog, ok: typed.Type, failure: typed.Type, span: Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    const declaration = state.index.names.get("Result") orelse return error.InternalError;
    return nominal.instantiateLengths(catalog, declaration, &.{ ok, failure }, &.{}, span);
}

/// Instantiate `Option[T]` for an operation that may have no answer.
pub fn optionType(catalog: *Catalog, element: typed.Type, span: Span) Error!typed.Type {
    const state = catalog.templates.store orelse return error.InternalError;
    const declaration = state.index.names.get("Option") orelse return error.InternalError;
    return nominal.instantiateLengths(catalog, declaration, &.{element}, &.{}, span);
}

/// Resolve the output of a Python string method that no other collection shares.
fn textMethodType(catalog: *Catalog, owner: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    if (operations.search(kind)) |mode| return if (mode == .prefix or mode == .suffix) .bool else .i64;
    if (operations.trim(kind) != null) return owner;
    if (kind == .text_repr) return preludeType(catalog, "str", span);
    return switch (kind) {
        .strip, .lstrip, .rstrip, .upper, .lower, .replace, .zfill, .copy => owner,
        .splitlines, .split_whitespace => listType(catalog, owner, span),
        .text_ord => .i64,
        .text_chr, .text_format, .number_format => preludeType(catalog, "str", span),
        .float_round => preludeType(catalog, "float", span),
        .is_digit, .is_alpha, .is_space, .starts_with, .ends_with => .bool,
        .count, .find => .i64,
        .parse_int => optionType(catalog, .i64, span),
        .parse_float => optionType(catalog, try preludeType(catalog, "float", span), span),
        else => error.InternalError,
    };
}

/// Resolve the output of a managed byte-string operation.
fn bytesOperationType(catalog: *Catalog, owner: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    if (operations.search(kind)) |mode| return if (mode == .prefix or mode == .suffix) .bool else .i64;
    if (operations.trim(kind) != null) return owner;
    if (kind == .text_repr) return preludeType(catalog, "str", span);
    const element = catalog.records[owner.recordIndex()].shape.buffer.?;
    return switch (kind) {
        .length, .find, .find_any => .i64,
        .contains, .starts_with, .ends_with => .bool,
        .buffer_reserve, .buffer_append_byte, .buffer_append_range => .bool,
        .buffer_append_utf8, .buffer_append_int, .buffer_append_float => .bool,
        .iteration_check => .unit,
        .read => element,
        .slice, .join => owner,
        // A view reads the same octets and answers the same byte-string type, so
        // every read operation is already defined for it; `copy` materializes
        // those octets instead.
        .view, .copy => owner,
        .split => listType(catalog, owner, span),
        .split_whitespace => listType(catalog, owner, span),
        .to_list => listType(catalog, .i64, span),
        .hex => preludeType(catalog, "str", span),
        .decode => resultType(catalog, try preludeType(catalog, "str", span), try preludeType(catalog, "str", span), span),
        .scalar_count, .scalar_count_range => resultType(catalog, .i64, try preludeType(catalog, "str", span), span),
        .parse_int, .parse_int_range => optionType(catalog, .i64, span),
        .parse_float, .parse_float_range => optionType(catalog, try preludeType(catalog, "float", span), span),
        else => error.InternalError,
    };
}

/// View materialization and text indexing produce ordinary owned values.
fn viewOwnedResult(catalog: *Catalog, owner: typed.Type, kind: Kind, span: Span) Error!?typed.Type {
    const schema = catalog.records[owner.recordIndex()];
    if (schema.shape.builtin != .borrowed_view) return null;
    if (kind != .copy and !(kind == .read and schema.collection.kind == .string)) return null;
    const result = try preludeType(catalog, if (schema.collection.kind == .string) "str" else "bytes", span);
    return result;
}

/// Resolve a managed operation output without conflating list, text, and map schemas.
pub fn operationType(catalog: *Catalog, owner: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    const collection = owner.isAggregate() and catalog.records[owner.recordIndex()].isCollection();
    if (kind == .copy and !collection) return owner;
    const schema = catalog.records[owner.recordIndex()];
    const element = schema.shape.buffer.?;
    if (kind == .borrow_view) return preludeType(catalog, if (schema.collection.kind == .string) "TextView" else "ByteView", span);
    if (try viewOwnedResult(catalog, owner, kind, span)) |result| return result;
    if (schema.collection.kind == .list) return switch (kind) {
        .read, .pop, .pop_at => element,
        .index_of => .i64,
        .copy, .snapshot => owner,
        .contains => .bool,
        .length, .capacity => .u64,
        .append, .write, .iteration_check => .unit,
        .extend, .insert, .remove, .reverse, .sort, .sort_keyed, .clear => .unit,
        .slice_step => owner,
        else => error.InternalError,
    };
    if (schema.collection.kind == .bytes) return bytesOperationType(catalog, owner, kind, span);
    const dictionary = schema.collection.kind == .dictionary;
    return switch (kind) {
        .encode => if (!dictionary) preludeType(catalog, "bytes", span) else error.InternalError,
        .from_hex => if (!dictionary) resultType(catalog, try preludeType(catalog, "bytes", span), owner, span) else error.InternalError,
        .length => .i64,
        .contains => .bool,
        .iteration_check => .unit,
        .read => if (dictionary) element else owner,
        .get, .pop_key, .pop_default, .setdefault => if (dictionary) element else error.InternalError,
        // A set's `pop` removes and answers its most recently added element.
        .pop => if (schema.collection.set) schema.collection.key.? else error.InternalError,
        .write, .update, .clear => if (dictionary) .unit else error.InternalError,
        .copy => owner,
        .items => if (dictionary) listType(catalog, element, span) else error.InternalError,
        .key_at => if (dictionary) schema.collection.key.? else error.InternalError,
        .value_at => if (dictionary) element else error.InternalError,
        .slice, .join => if (!dictionary) owner else error.InternalError,
        .text_tail => if (schema.collection.kind == .string) owner else error.InternalError,
        .slice_step => if (dictionary or schema.collection.kind == .bytes) error.InternalError else owner,
        .keys => if (dictionary) listType(catalog, schema.collection.key.?, span) else error.InternalError,
        .values => if (dictionary) listType(catalog, element, span) else error.InternalError,
        .split => if (!dictionary) listType(catalog, owner, span) else error.InternalError,
        else => if (dictionary) error.InternalError else textMethodType(catalog, owner, kind, span),
    };
}

/// Append checked statements and expressions without manufacturing source names.
pub fn Builder(comptime Checker: type) type {
    return struct {
        checker: *Checker,
        span: Span,
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
        /// Replace an immediately consumed byte slice or view with the matching
        /// range operation. The checked intermediate can be either a direct
        /// operation on a local or a block that first roots an expression; in
        /// the latter case the same block keeps receiver-before-bounds order.
        pub fn fuseImmediateByteRange(self: Self, base: typed.NodeId, kind: Kind) Error!?typed.Node {
            const checked = self.checker.nodes.items[@backingInt(base)];
            var body: ?typed.StatementId = null;
            var value = base;
            if (checked.data == .block_value) {
                body = checked.data.block_value.body;
                value = checked.data.block_value.value;
            }
            const range_op = switch (self.checker.nodes.items[@backingInt(value)].data) {
                .buffer_operation => |op| op,
                else => return null,
            };
            if ((range_op.kind != .slice and range_op.kind != .view) or range_op.arguments.len != 2) return null;
            const result = try self.operation(range_op.owner, kind, range_op.arguments);
            if (body) |statements| return .{
                .span = self.span,
                .ty = self.checker.nodes.items[@backingInt(result)].ty,
                .data = .{ .block_value = .{ .body = statements, .value = result } },
            };
            const fused = try self.block(&.{}, result);
            return fused;
        }
        /// Read collection length with the ordinary signed index type.
        pub fn length(self: Self, slot: typed.LocalId) Error!typed.NodeId {
            return self.node(.i64, .{ .cast = try self.operation(slot, .length, &.{}) });
        }
        /// Create a binary operation with explicit result type.
        pub fn binary(self: Self, op: typed.BinaryOp, left: typed.NodeId, right: typed.NodeId, ty: typed.Type) Error!typed.NodeId {
            return self.node(ty, .{ .binary = .{ .op = op, .left = left, .right = right, .op_span = self.span } });
        }
        /// Compute `max(end - start, 0)` as an unsigned list capacity. Signed
        /// bounds that cross zero are split around `-1/0`, so even the full
        /// `minInt..maxInt` distance is represented without signed overflow.
        pub fn rangeCapacity(self: Self, start: typed.NodeId, end: typed.NodeId, ty: typed.Type) Error!typed.NodeId {
            const info = ty.integer() orelse return error.InternalError;
            const capacity = try self.local(.u64);
            const zero = try self.node(ty, .{ .integer = 0 });
            const zero_capacity = try self.node(.u64, .{ .integer = 0 });
            const direct = try self.node(.u64, .{ .cast = try self.binary(.sub, end, start, ty) });
            const direct_assignment = try self.stmt(.{ .assign = .{ .slot = capacity, .value = direct } });
            const ascending = try self.binary(.lt, start, end, .bool);
            const reserve = if (!info.signed)
                direct_assignment
            else reserve: {
                const start_negative = try self.binary(.lt, start, zero, .bool);
                const end_negative = try self.binary(.lt, end, zero, .bool);
                const one = try self.node(ty, .{ .integer = 1 });
                const adjusted = try self.binary(.add, start, one, ty);
                const magnitude = try self.node(ty, .{ .unary = .{ .op = .neg, .operand = adjusted, .op_span = self.span } });
                const low = try self.node(.u64, .{ .cast = magnitude });
                const high = try self.node(.u64, .{ .cast = end });
                const crossed = try self.binary(.add, try self.binary(.add, high, low, .u64), try self.node(.u64, .{ .integer = 1 }), .u64);
                const crossed_assignment = try self.stmt(.{ .assign = .{ .slot = capacity, .value = crossed } });
                const negative_start = try self.stmt(.{ .branch = .{
                    .condition = end_negative,
                    .then_body = direct_assignment,
                    .else_body = crossed_assignment,
                } });
                break :reserve try self.stmt(.{ .branch = .{
                    .condition = start_negative,
                    .then_body = negative_start,
                    .else_body = direct_assignment,
                } });
            };
            const block_value = try self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = capacity, .value = zero_capacity } }),
                try self.stmt(.{ .branch = .{ .condition = ascending, .then_body = reserve, .else_body = null } }),
            }, try self.read(capacity));
            return self.node(block_value.ty, block_value.data);
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
            var statements: std.ArrayList(typed.StatementId) = .empty;
            const rooted = try freshFieldReceiver(Checker, self, base, kind, &statements);
            const init = try self.stmt(.{ .initialize = .{ .slot = owner, .value = rooted } });
            const arguments = try self.checker.allocator.dupe(typed.NodeId, inputs);
            if (kind == .write) {
                const value_slot = try self.local(self.checker.nodes.items[@backingInt(arguments[1])].ty);
                try statements.append(self.checker.allocator, try self.stmt(.{ .initialize = .{ .slot = value_slot, .value = arguments[1] } }));
                arguments[1] = try self.read(value_slot);
            }
            try statements.append(self.checker.allocator, init);
            const list_receiver = ty.isAggregate() and self.checker.catalog.records[ty.recordIndex()].collection.kind == .list;
            if (list_receiver and (kind == .read or kind == .write or kind == .pop_at)) arguments[0] = try self.index(owner, arguments[0], false);
            const result = if (signed_length) try self.length(owner) else try self.operation(owner, kind, arguments);
            return self.block(statements.items, result);
        }
        /// Construct a fresh list and append elements in source order.
        pub fn literal(self: Self, ty: typed.Type, values: []const typed.NodeId) Error!typed.Node {
            const records = self.checker.catalog.records;
            const element = records[ty.recordIndex()].shape.buffer.?;
            if (@import("constant_list.zig").canPack(records, self.checker.nodes.items, values, element))
                return .{ .span = self.span, .ty = ty, .data = .{ .array = values } };
            const capacity = try self.integer(@intCast(values.len));
            const acquire = try self.node(ty, .{ .acquire_buffer = .{ .capacity = capacity } });
            const owner = try self.local(ty);
            var statements: std.ArrayList(typed.StatementId) = .empty;
            try statements.append(self.checker.allocator, try self.stmt(.{ .initialize = .{ .slot = owner, .value = acquire } }));
            for (values) |value| try statements.append(self.checker.allocator, try self.stmt(.{ .discard = try self.operation(owner, .append, &.{value}) }));
            return self.block(statements.items, try self.read(owner));
        }
        /// Root text once, then evaluate each optional slice endpoint in order.
        pub fn textSlice(self: Self, base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId) Error!typed.Node {
            const owner = try self.local(self.checker.nodes.items[@backingInt(base)].ty);
            const ty = self.checker.nodes.items[@backingInt(base)].ty;
            const family = self.checker.catalog.records[ty.recordIndex()].collection.kind;
            const kind: Kind = if (end == null and family == .string) .text_tail else .slice;
            return self.block(&.{try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } })}, try self.operation(owner, kind, &.{ start orelse try self.integer(0), end orelse try self.length(owner) }));
        }
        /// Copy a stepped slice into fresh storage. An omitted endpoint stays a sentinel
        /// so the runtime can default it for the step's sign, and explicit endpoints are
        /// passed unclamped because the runtime applies Python's adjustment exactly once.
        /// The receiver, both endpoints and the step are each evaluated exactly once.
        pub fn sliceStep(self: Self, base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId, step: typed.NodeId) Error!typed.Node {
            const ty = self.checker.nodes.items[@backingInt(base)].ty;
            const owner = try self.local(ty);
            const first_slot = try self.local(.i64);
            const last_slot = try self.local(.i64);
            const step_slot = try self.local(.i64);
            const first = if (start) |value| try self.widened(value) else try self.integer(omitted_first);
            const last = if (end) |value| try self.widened(value) else try self.integer(omitted_last);
            return self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } }),
                try self.stmt(.{ .initialize = .{ .slot = first_slot, .value = first } }),
                try self.stmt(.{ .initialize = .{ .slot = last_slot, .value = last } }),
                try self.stmt(.{ .initialize = .{ .slot = step_slot, .value = step } }),
            }, try self.operation(owner, .slice_step, &.{ try self.read(first_slot), try self.read(last_slot), try self.read(step_slot) }));
        }
        /// Widen a checked integer expression to the signed index type.
        fn widened(self: Self, input: typed.NodeId) Error!typed.NodeId {
            return if (self.checker.nodes.items[@backingInt(input)].ty == .i64) input else self.node(.i64, .{ .cast = input });
        }
        /// Copy a bounded slice into a fresh list using existing checked loop instructions.
        pub fn slice(self: Self, base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId) Error!typed.Node {
            const ty = self.checker.nodes.items[@backingInt(base)].ty;
            const element = self.checker.catalog.records[ty.recordIndex()].shape.buffer.?;
            if (typed.requiresHandling(element, self.checker.catalog.records))
                return self.checker.sink.fail("E_RESULT_OPERATION", self.span, "a list slice cannot duplicate pending result obligations");
            if (typed.moveOnly(element, self.checker.catalog.records))
                return self.checker.sink.fail(list_type_error, self.span, "a list slice cannot duplicate resource owners");
            const owner = try self.local(ty);
            const output = try self.local(ty);
            const index_slot = try self.local(.i64);
            const limit_slot = try self.local(.i64);
            const zero = try self.integer(0);
            const acquire = try self.node(ty, .{ .acquire_buffer = .{ .capacity = zero } });
            const i = try self.read(index_slot);
            const loop_id = self.checker.loops.next;
            self.checker.loops.next += 1;
            const child = try self.operation(owner, .read, &.{i});
            const selected = if (element.isAggregate()) copied: {
                const copy = try self.access(child, .copy, &.{}, false);
                break :copied try self.node(copy.ty, copy.data);
            } else child;
            const body = try self.stmt(.{ .discard = try self.operation(output, .append, &.{selected}) });
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

/// Keep a fresh whole result as the owner while a read-only receiver
/// borrows its fields. Named assignments still cannot partially move it.
fn freshFieldReceiver(comptime Checker: type, b: Builder(Checker), base: typed.NodeId, kind: Kind, statements: *std.ArrayList(typed.StatementId)) Error!typed.NodeId {
    if (kind.writesReceiver() or kind == .borrow_view or kind == .view or kind == .snapshot) return base;
    var path: [64]typed.NodeId = undefined;
    var count: usize = 0;
    var root = base;
    while (b.checker.nodes.items[@backingInt(root)].data == .field) {
        if (count == path.len) return base;
        path[count] = root;
        count += 1;
        root = b.checker.nodes.items[@backingInt(root)].data.field.base;
    }
    const node = b.checker.nodes.items[@backingInt(root)];
    if (count == 0 or (node.data != .call and node.data != .invoke)) return base;
    const records = b.checker.catalog.records;
    if (!typed.storable(node.ty, records) or typed.moveOnly(node.ty, records)) return base;
    if (typed.requiresHandling(node.ty, records) or typed.isBorrowedView(records, node.ty)) return base;
    const whole = try b.local(node.ty);
    try statements.append(b.checker.allocator, try b.stmt(.{ .initialize = .{ .slot = whole, .value = root } }));
    var value = try b.read(whole);
    while (count != 0) {
        count -= 1;
        const field = b.checker.nodes.items[@backingInt(path[count])];
        value = try b.node(field.ty, .{ .field = .{ .base = value, .index = field.data.field.index } });
    }
    return value;
}
