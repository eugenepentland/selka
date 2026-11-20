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
const negative_index = @import("negative_index.zig");
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
        .parse_f32 => optionType(catalog, try preludeType(catalog, "f32", span), span),
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
        .length, .find, .find_any, .find_any_range => .i64,
        .contains, .starts_with, .ends_with => .bool,
        .buffer_reserve, .buffer_append, .buffer_append_byte, .buffer_append_range, .buffer_append_array => .bool,
        .buffer_append_utf8, .buffer_append_int, .buffer_append_float => .bool,
        .iteration_check, .clear => .unit,
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
        .blake3, .sha256 => preludeType(catalog, "bytes", span),
        .decode => resultType(catalog, try preludeType(catalog, "str", span), try preludeType(catalog, "str", span), span),
        .scalar_count, .scalar_count_range => resultType(catalog, .i64, try preludeType(catalog, "str", span), span),
        .parse_int, .parse_int_range => optionType(catalog, .i64, span),
        .parse_float, .parse_float_range => optionType(catalog, try preludeType(catalog, "float", span), span),
        else => error.InternalError,
    };
}

/// Resolve a managed operation output without conflating list, text, and map schemas.
pub fn operationType(catalog: *Catalog, owner: typed.Type, kind: Kind, span: Span) Error!typed.Type {
    if (kind == .position_fail) return .unit;
    const collection = owner.isAggregate() and catalog.records[owner.recordIndex()].isCollection();
    if (kind == .copy and !collection) return owner;
    const schema = catalog.records[owner.recordIndex()];
    const element = schema.shape.buffer.?;
    if (schema.collection.kind == .list) return switch (kind) {
        .read, .pop, .pop_at, .exchange => element,
        .index_of => .i64,
        .copy => owner,
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
        .encode, .blake3, .sha256 => if (!dictionary) preludeType(catalog, "bytes", span) else error.InternalError,
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
        .slice, .slice_bytes, .join => if (!dictionary) owner else error.InternalError,
        .text_tail => if (schema.collection.kind == .string) owner else error.InternalError,
        .slice_step => if (dictionary or schema.collection.kind == .bytes) error.InternalError else owner,
        .keys => if (dictionary) listType(catalog, schema.collection.key.?, span) else error.InternalError,
        .values => if (dictionary) listType(catalog, element, span) else error.InternalError,
        .split => if (!dictionary) listType(catalog, owner, span) else error.InternalError,
        else => if (dictionary) error.InternalError else textMethodType(catalog, owner, kind, span),
    };
}

/// Append checked statements and expressions without manufacturing source names.
/// Whether `ty` is a text record (a `str` collection) of `checker`'s catalog.
fn textRecordType(comptime Checker: type, checker: *const Checker, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < checker.catalog.records.len and checker.catalog.records[ty.recordIndex()].collection.kind == .string;
}

/// The temporary that holds a read-only text or bytes source: a view-keeping owner for either family (C9 bytes),
/// a plain temporary otherwise. A bytes receiver read through a plain temporary is copied at its store.
fn readOwnerFor(comptime Checker: type, b: Builder(Checker), ty: typed.Type) Error!typed.LocalId {
    return if (textRecordType(Checker, b.checker, ty) or bytesRecordType(Checker, b.checker, ty)) b.sliceOwner(ty) else b.local(ty);
}

/// Whether checked type `ty` is a bytes collection (the bytes family of a read-only owner, C9 bytes).
fn bytesRecordType(comptime Checker: type, checker: *const Checker, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < checker.catalog.records.len and checker.catalog.records[ty.recordIndex()].collection.kind == .bytes;
}

/// The builder of collection lowering over `Checker`: the statements, reads and writes that lower a collection.
pub fn Builder(comptime Checker: type) type {
    return struct {
        checker: *Checker,
        span: Span,
        /// Read text positions as Unicode scalars: the scalar helpers and a
        /// `strings.chars` walk measure a `str` in scalars, while the surface
        /// `len(text)`, `text[i]` and `text[a:b]` measure it in octets.
        scalar_text: bool = false,
        const Self = @This();
        /// The same builder with scalar text positions.
        pub fn scalarText(self: Self) Self {
            var copy = self;
            copy.scalar_text = true;
            return copy;
        }
        /// The number of Unicode scalars of a text binding.
        pub fn scalarTextLength(self: Self, slot: typed.LocalId) Error!typed.NodeId {
            return self.node(.i64, .{ .length = try self.read(slot) });
        }
        /// A walk's bound: a scalar text walk counts scalars, every other collection
        /// counts elements or octets.
        pub fn iterationLimit(self: Self, slot: typed.LocalId, kind: @import("runtime_values.zig").ManagedKind) Error!typed.NodeId {
            return limitOfWalk(Checker, self, slot, kind);
        }
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
        /// The temporary that holds the base of a text or bytes slice. It is initialized once and never
        /// assigned; the builder keeps a view it holds borrowed (`<slice>` names it, C9).
        pub fn sliceOwner(self: Self, ty: typed.Type) Error!typed.LocalId {
            const slot: typed.LocalId = @fromBackingInt(self.checker.locals.items.len);
            try self.checker.locals.append(self.checker.allocator, .{ .name = "<slice>", .declaration = self.span, .ty = ty, .mutable = true, .usage = .{ .reads = 1, .temporary = true } });
            return slot;
        }
        /// The temporary that holds a read-only text source: a view-keeping owner (`sliceOwner`) for text,
        /// a plain temporary otherwise. It is initialized once and only read, so a borrowed view stays borrowed.
        pub fn readOwner(self: Self, ty: typed.Type) Error!typed.LocalId {
            return readOwnerFor(Checker, self, ty);
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
            if (range_op.kind != .slice or range_op.arguments.len != 2) return null;
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
            return lengthOfSlot(Checker, self, slot);
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
        /// Preserve a written index; negative slice endpoints trap before the upper clamp.
        pub fn index(self: Self, owner: typed.LocalId, input: typed.NodeId, clamp: bool) Error!typed.NodeId {
            return checkedIndex(Checker, self, owner, input, clamp);
        }
        /// Reject a negative positional bound without moving its later upper clamp.
        pub fn insertionIndex(self: Self, owner: typed.LocalId, input: typed.NodeId) Error!typed.NodeId {
            try negative_index.check(Checker, self.checker, input, true);
            if (self.checker.nodes.items[@backingInt(input)].ty == .u64) return input;
            const slot = try self.local(.i64);
            const current = try self.read(slot);
            const invalid = try self.stmt(.{ .discard = try self.operation(owner, .position_fail, &.{ current, try self.length(owner) }) });
            const result = try self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = slot, .value = try self.widened(input) } }),
                try self.stmt(.{ .branch = .{ .condition = try self.binary(.lt, current, try self.integer(0), .bool), .then_body = invalid, .else_body = null } }),
            }, current);
            return self.node(result.ty, result.data);
        }
        /// Clamp an unsigned bound before converting it to the signed slice representation.
        fn unsignedBound(self: Self, owner: typed.LocalId, input: typed.NodeId) Error!typed.NodeId {
            const slot = try self.local(.u64);
            const current = try self.read(slot);
            const count = try self.node(.u64, .{ .cast = try self.length(owner) });
            const high = try self.stmt(.{ .assign = .{ .slot = slot, .value = count } });
            const value = try self.node(.i64, .{ .cast = current });
            const result = try self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = slot, .value = input } }),
                try self.stmt(.{ .branch = .{ .condition = try self.binary(.gt, current, count, .bool), .then_body = high, .else_body = null } }),
            }, value);
            return self.node(result.ty, result.data);
        }
        fn positionalAccess(kind: Kind) bool {
            return switch (kind) {
                .read, .write, .pop_at, .exchange => true,
                else => false,
            };
        }
        /// Root the receiver before evaluating indices and element-producing arguments.
        pub fn access(self: Self, base: typed.NodeId, kind: Kind, inputs: []const typed.NodeId, signed_length: bool) Error!typed.Node {
            const ty = self.checker.nodes.items[@backingInt(base)].ty;
            // Text is immutable: every access to it reads its owner, which holds once and is never written, so the
            // owner may keep a borrowed view of a plain parameter (C9 str): `strings.char_at(text, i)` and
            // `strings.char_find(text, sep)` read the view's octets in place.
            const owner = try self.readOwner(ty);
            var statements: std.ArrayList(typed.StatementId) = .empty;
            const rooted = try freshFieldReceiver(Checker, self, base, kind, &statements);
            const init = try self.stmt(.{ .initialize = .{ .slot = owner, .value = rooted } });
            const arguments = try self.checker.allocator.dupe(typed.NodeId, inputs);
            if (kind == .write) {
                const value_slot = try self.local(self.checker.nodes.items[@backingInt(arguments[1])].ty);
                try statements.append(self.checker.allocator, try self.stmt(.{ .initialize = .{ .slot = value_slot, .value = arguments[1], .transfer = true } }));
                arguments[1] = try self.read(value_slot);
            }
            try statements.append(self.checker.allocator, init);
            const list_receiver = ty.isAggregate() and self.checker.catalog.records[ty.recordIndex()].collection.kind == .list;
            if (list_receiver and positionalAccess(kind))
                arguments[0] = try self.index(owner, arguments[0], false);
            if (list_receiver and kind == .insert) arguments[0] = try self.insertionIndex(owner, arguments[0]);
            try guardRangeArguments(Checker, self, owner, kind, arguments);
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
            const scalar = self.scalarText();
            const ty = scalar.checker.nodes.items[@backingInt(base)].ty;
            const owner = try scalar.sliceOwner(ty);
            const family = scalar.checker.catalog.records[ty.recordIndex()].collection.kind;
            const kind: Kind = if (end == null and family == .string) .text_tail else .slice;
            var statements: std.ArrayList(typed.StatementId) = .empty;
            const rooted = try freshFieldReceiver(Checker, scalar, base, kind, &statements);
            try statements.append(scalar.checker.allocator, try scalar.stmt(.{ .initialize = .{ .slot = owner, .value = rooted } }));
            const first = if (start) |value| try scalar.index(owner, value, true) else try scalar.integer(0);
            const last = if (end) |value| try scalar.index(owner, value, true) else try scalar.length(owner);
            // A scalar slice of text is a view of its base, as `text[start:end]` is (sema marks that
            // node): the escape rule reads this mark, so a stored or returned piece is refused until
            // `copy(...)` writes it, and `strings.char_slice` obeys the same rule.
            const slice_node = try scalar.operation(owner, kind, &.{ first, last });
            scalar.checker.nodes.items[@backingInt(slice_node)].view = true;
            return scalar.block(statements.items, slice_node);
        }
        /// Copy a stepped slice into fresh storage. An omitted endpoint stays a sentinel
        /// so the runtime can default it for the step's sign, and explicit endpoints are
        /// nonnegative and upper-clamped before the runtime selects the step direction.
        /// The receiver, both endpoints and the step are each evaluated exactly once.
        pub fn sliceStep(self: Self, base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId, step: typed.NodeId) Error!typed.Node {
            const scalar = self.scalarText();
            const ty = scalar.checker.nodes.items[@backingInt(base)].ty;
            const owner = try scalar.readOwner(ty);
            const first_slot = try scalar.local(.i64);
            const last_slot = try scalar.local(.i64);
            const step_slot = try scalar.local(.i64);
            const first = if (start) |value| try scalar.index(owner, value, true) else try scalar.integer(omitted_first);
            const last = if (end) |value| try scalar.index(owner, value, true) else try scalar.integer(omitted_last);
            return scalar.block(&.{
                try scalar.stmt(.{ .initialize = .{ .slot = owner, .value = base } }),
                try scalar.stmt(.{ .initialize = .{ .slot = first_slot, .value = first } }),
                try scalar.stmt(.{ .initialize = .{ .slot = last_slot, .value = last } }),
                try scalar.stmt(.{ .initialize = .{ .slot = step_slot, .value = step } }),
            }, try scalar.operation(owner, .slice_step, &.{ try scalar.read(first_slot), try scalar.read(last_slot), try scalar.read(step_slot) }));
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
                return self.checker.sink.failOwnership(.{ .code = "E_RESULT_OPERATION", .rule = .L1 }, self.span, "a list slice cannot duplicate pending result obligations");
            if (typed.moveOnly(element, self.checker.catalog.records))
                return self.checker.sink.failOwnership(.{ .code = list_type_error, .rule = .T2 }, self.span, "a list slice cannot duplicate resource owners");
            const owner = try self.local(ty);
            if (start == null and end == null) return self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } }),
            }, try self.operation(owner, .copy, &.{}));
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
            var slice_node = try self.block(&.{
                try self.stmt(.{ .initialize = .{ .slot = owner, .value = base } }),
                try self.stmt(.{ .initialize = .{ .slot = index_slot, .value = if (start) |v| try self.index(owner, v, true) else zero } }),
                try self.stmt(.{ .initialize = .{ .slot = limit_slot, .value = if (end) |v| try self.index(owner, v, true) else try self.length(owner) } }),
                try self.stmt(.{ .initialize = .{ .slot = output, .value = acquire } }),
                try self.stmt(.{ .loop = .{ .id = loop_id, .condition = try self.binary(.lt, i, try self.read(limit_slot), .bool), .body = body, .step = step } }),
            }, try self.read(output));
            // A ranged list slice is a view of its source too: the mark is what
            // the ownership checker's escape rule reads, and it is what tells a
            // slice apart from a builtin that lowers to a similar block
            // (`list(d.items())`). DECISIONS F11.
            slice_node.view = true;
            return slice_node;
        }
    };
}

/// The length of one binding: the scalar count for a scalar text walk, and the
/// element or octet count otherwise.
fn lengthOfSlot(comptime Checker: type, b: Builder(Checker), slot: typed.LocalId) Error!typed.NodeId {
    const ty = b.checker.locals.items[@backingInt(slot)].ty;
    const text = b.scalar_text and ty.isAggregate() and b.checker.catalog.records[ty.recordIndex()].collection.kind == .string;
    if (text) return b.scalarTextLength(slot);
    return b.node(.i64, .{ .cast = try b.operation(slot, .length, &.{}) });
}

/// A walk's bound, which is the scalar count of a text walk and the length otherwise.
fn limitOfWalk(comptime Checker: type, b: Builder(Checker), slot: typed.LocalId, kind: @import("runtime_values.zig").ManagedKind) Error!typed.NodeId {
    if (kind == .string) return b.scalarTextLength(slot);
    return b.length(slot);
}

/// Copy a byte-offset slice of text, which is wave 3 phase 2's `text[start:end]`:
/// the bounds are byte offsets, and the runtime traps `R_TEXT_BOUNDARY` when an
/// endpoint falls inside a multi-byte scalar.
pub fn bytesSlice(comptime Checker: type, b: Builder(Checker), base: typed.NodeId, start: ?typed.NodeId, end: ?typed.NodeId) Error!typed.Node {
    // Only text keeps a view-owner temporary here (C9 str); a bytes base keeps its plain temporary, as at HEAD.
    const owner = try b.readOwner(b.checker.nodes.items[@backingInt(base)].ty);
    var statements: std.ArrayList(typed.StatementId) = .empty;
    const rooted = try freshFieldReceiver(Checker, b, base, .slice_bytes, &statements);
    try statements.append(b.checker.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = rooted } }));
    const first = if (start) |value| try b.index(owner, value, true) else try b.integer(0);
    const last = if (end) |value| try b.index(owner, value, true) else try b.length(owner);
    return b.block(statements.items, try b.operation(owner, .slice_bytes, &.{ first, last }));
}

/// Keep a fresh whole result (a call's, a function value's, a moved-out place's, or a record constructor) as the owner while
/// a read-only receiver borrows its fields. Named assignments still cannot partially move it.
fn freshFieldReceiver(comptime Checker: type, b: Builder(Checker), base: typed.NodeId, kind: Kind, statements: *std.ArrayList(typed.StatementId)) Error!typed.NodeId {
    if (kind.writesReceiver() or kind == .borrow_view or kind == .view) return base;
    var path: [64]typed.NodeId = undefined;
    var count: usize = 0;
    var root = base;
    while (b.checker.nodes.items[@backingInt(root)].data == .field) {
        // A written marker must reach Core on its original source projection.
        // Rebuilding this path would discard it before eligibility is checked.
        if (b.checker.nodes.items[@backingInt(root)].own) return base;
        if (count == path.len) return base;
        path[count] = root;
        count += 1;
        root = b.checker.nodes.items[@backingInt(root)].data.field.base;
    }
    const node = b.checker.nodes.items[@backingInt(root)];
    const fresh = node.data == .call or node.data == .invoke or node.data == .record or movedOut(b.checker.nodes.items, root);
    if (count == 0 or !fresh) return base;
    const records = b.checker.catalog.records;
    if (!typed.storable(node.ty, records) or typed.moveOnly(node.ty, records)) return base;
    if (typed.requiresHandling(node.ty, records)) return base;
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

/// Whether a value is the result of `take` or `exchange`: a fresh owned value, as a call's is, so a field read of it
/// (`take(mut b.block).items`) roots the whole value first. An element place's exchange is wrapped in its receiver block.
fn movedOut(nodes: []const typed.Node, id: typed.NodeId) bool {
    return switch (nodes[@backingInt(id)].data) {
        .place_exchange => true,
        .block_value => |block| nodes[@backingInt(block.value)].data == .place_exchange,
        else => false,
    };
}

fn checkedIndex(comptime Checker: type, self: Builder(Checker), owner: typed.LocalId, input: typed.NodeId, clamp: bool) Error!typed.NodeId {
    const input_type = self.checker.nodes.items[@backingInt(input)].ty;
    if (!input_type.isInteger()) return self.checker.sink.fail("E_TYPE", self.span, "collection index requires an integer");
    try negative_index.check(Checker, self.checker, input, clamp);
    if (!clamp and input_type == .u64) return input;
    const value = if (input_type == .u64 and clamp) try self.unsignedBound(owner, input) else try self.widened(input);
    if (!clamp) return value;
    const slot = try self.local(.i64);
    const current = try self.read(slot);
    const count = try self.length(owner);
    const negative = try self.binary(.lt, current, try self.integer(0), .bool);
    const invalid = try self.stmt(.{ .discard = try self.operation(owner, .position_fail, &.{ current, try self.length(owner) }) });
    const high = try self.stmt(.{ .assign = .{ .slot = slot, .value = count } });
    const block_value = try self.block(&.{
        try self.stmt(.{ .initialize = .{ .slot = slot, .value = value } }),
        try self.stmt(.{ .branch = .{ .condition = negative, .then_body = invalid, .else_body = null } }),
        try self.stmt(.{ .branch = .{ .condition = try self.binary(.gt, current, count, .bool), .then_body = high, .else_body = null } }),
    }, current);
    return self.node(block_value.ty, block_value.data);
}

fn guardRangeArguments(comptime Checker: type, self: Builder(Checker), owner: typed.LocalId, kind: Kind, arguments: []typed.NodeId) Error!void {
    // Every method position of a `str` is a scalar position (wave 1's text
    // search), so its guard measures the text in scalars; the surface index and
    // slice are the only byte positions, and they lower through `.slice_bytes`.
    const positions = if (self.checker.locals.items[@backingInt(owner)].ty.isAggregate() and
        self.checker.catalog.records[self.checker.locals.items[@backingInt(owner)].ty.recordIndex()].collection.kind == .string)
        self.scalarText()
    else
        self;
    for (arguments, 0..) |*argument, index| {
        if (!negative_index.rangeBound(kind, index)) continue;
        // A search start beyond the end remains beyond it, preserving empty-needle rules.
        argument.* = if (operations.search(kind) != null)
            try positions.insertionIndex(owner, argument.*)
        else
            try positions.index(owner, argument.*, true);
    }
}
