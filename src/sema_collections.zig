//! Checking of collection syntax and methods: list, tuple-free dictionary and
//! text literals, comprehensions and f-strings, element access and slices, and
//! the method families of lists, dictionaries, text, bytes, byte buffers and
//! Option receivers, plus resource acquisition and I/O on managed values. Each
//! check is a free function over the concrete checker type; `Checks` exposes
//! the ones the rest of the checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const buffer_operations = @import("buffer_operations.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const iteration_place = @import("iteration_place.zig");
const option_flow = @import("option_flow.zig");
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const call_argument_code = sema_shared.call_argument_code;
const eOwnedConsumed = diagnostic.owned_consumed;
const eShadowing = diagnostic.shadowing;
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const eResourceResult = diagnostic.resource_result;
const eImmutable = diagnostic.immutable;
const std = @import("std");
const dictionary_views = @import("dictionary_views.zig");
const eCollectionMethod = sema_shared.eCollectionMethod;
const ast = @import("ast.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const eFileArgument = sema_shared.eFileArgument;
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const arrays = @import("array_literals.zig");
const variant_calls = @import("variant_calls.zig");
const set_lower = @import("set_lower.zig");
const truncating = @import("truncating_math.zig");
const isMutableBytes = sema_shared.isMutableBytes;
const eCellEquality = sema_shared.eCellEquality;
const eOptionTest = sema_shared.eOptionTest;
const bufferOperation = sema_shared.bufferOperation;
const needs_list = "operation requires a managed list";
const removed_names = @import("removed_names.zig");
/// String methods whose only operand is a scalar width rather than more text.
fn widthArgument(kind: BufferKind) bool {
    return kind == .zfill;
}
/// Whether one operand of an in-place byte-buffer method is a scalar count or
/// index rather than another managed value. `append_range` takes the source span
/// first and both endpoints after it, `append_utf8` takes text, and every other
/// method takes one count or byte value.
fn byteBufferInteger(kind: BufferKind, index: usize) bool {
    return switch (kind) {
        .buffer_append_range => index > 0,
        .buffer_append_utf8, .buffer_append_float => false,
        else => buffer_operations.byteBuffer(kind),
    };
}
/// The one diagnostic for an in-place buffer method on a receiver that is not
/// the mutable octet buffer.
const byte_buffer_receiver = "in-place buffer methods require a byte_buffer receiver";
/// Whether a managed byte-kind schema is an immutable byte string: a `bytes`
/// literal, conversion result, slice or view, but never the octet buffer.
fn isImmutableBytes(schema: typed.Record) bool {
    return schema.collection.kind == .bytes and !isMutableBytes(schema);
}
const eResourceIoResult = "E_RESOURCE_IO_RESULT";
const unsupported_collection = "operation is not supported by this collection";
const unsupported_list = "operation is not supported by lists";
/// The accepted spelling of a Python method form this language rejects, or null
/// when it has none. Only deliberate, known gaps appear here; a rejected call
/// with no entry prints its signature or its accepted methods and stops.
fn methodAlternative(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "format")) return "use an f-string: f\"{value}\" interpolates where str.format does";
    return null;
}
/// An already-evaluated managed receiver and the source arguments of its method.
const ManagedAccess = struct { base: typed.NodeId, kind: BufferKind, inputs: []const ast.NodeId };
/// One list method call whose receiver and arguments are already evaluated.
const ListMethodCall = struct { base: typed.NodeId, kind: BufferKind, inputs: []const ast.NodeId, temporaries: []const typed.Type, signed_length: bool = false };
/// A list method call or element access whose receiver is still unchecked.
const ListAccess = struct { base: ast.NodeId, kind: BufferKind, inputs: []const ast.NodeId, signed_length: bool = false };
const impl = @This();
/// Bind collection checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Preserve literal families at Python search/trim call sites while
        /// retaining the existing contextual octet syntax in declarations.
        pub fn hintTextMethodArgument(self: *Checker, input: ast.NodeId, expected: typed.Type, kind: BufferKind) Error!void {
            return impl.hintTextMethodArgument(Checker, self, input, expected, kind);
        }
        /// Check a resource acquisition: its Result type, capability and fixed-byte request.
        pub fn checkAcquireResource(self: *Checker, unused1: ast.Node, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource"), out: *typed.Node) Error!void {
            return impl.checkAcquireResource(Checker, self, unused1, acquire, out);
        }
        /// Check a method on a named collection local, including dictionary views and
        /// the in-place list methods that count as writes.
        pub fn checkBufferOperation(self: *Checker, unused1: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), out: *typed.Node) Error!void {
            return impl.checkBufferOperation(Checker, self, unused1, operation, out);
        }
        /// Check a method call on an arbitrary receiver expression: Option, Stream, list
        /// `sort`, or the managed collection method families.
        pub fn checkCollectionMethod(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkCollectionMethod(Checker, self, node, temporaries);
        }
        /// Check `value[start:end]` and a stepped slice on a list or text.
        pub fn checkCollectionSlice(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkCollectionSlice(Checker, self, node, temporaries);
        }
        /// Build `[value for name in source if condition]` as a checked loop over a fresh list,
        /// drawing elements from a collection or, like a `for` loop, from an integer `range(...)`.
        pub fn checkComprehension(self: *Checker, node: ast.Node, each: ast.Comprehension, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkComprehension(Checker, self, node, each, temporaries);
        }
        /// `set(iterable)`: a fresh set of every element one walk over a list,
        /// str, bytes, fixed array, dictionary (its keys), dictionary view or
        /// set visits, in that order (SET-1).
        pub fn checkSetFromIterable(self: *Checker, span: source.Span, source_value: typed.NodeId) Error!typed.Node {
            return impl.checkSetFromIterable(Checker, self, span, source_value);
        }
        /// Render an f-string's pieces once in source order, then join them into one
        /// exactly-sized text allocation instead of repeatedly copying prefixes.
        pub fn checkFormat(self: *Checker, node: ast.Node, parts: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkFormat(Checker, self, node, parts, temporaries);
        }
        /// Check a list method call or element access whose receiver is still unchecked:
        /// check the receiver, then the access against it.
        pub fn checkListAccess(self: *Checker, node: ast.Node, operation: ListAccess, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkListAccess(Checker, self, node, operation, temporaries);
        }
        /// Check a list literal, inferring the element type from context or the first
        /// element; a context that demands `[N]T` builds a fixed array instead.
        pub fn checkListLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkListLiteral(Checker, self, node, inputs, temporaries);
        }
        /// The `str` or `bytes` module constant behind `NAME.method(...)`, when no local
        /// claims `NAME`.
        pub fn constantReceiver(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?usize {
            return impl.constantReceiver(Checker, self, call);
        }
        /// Check a method call on a `str` or `bytes` module constant.
        pub fn checkConstantMethod(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkConstantMethod(Checker, self, node, temporaries);
        }
        /// Check a collection method on a local whose Option type a preceding test narrowed.
        pub fn checkNarrowedMethod(self: *Checker, node: ast.Node, slot: typed.LocalId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkNarrowedMethod(Checker, self, node, slot, temporaries);
        }
        /// Check the intrinsic `Option` method one named local receiver calls. The
        /// caller has already established that this call is one of them.
        pub fn checkOptionReceiverMethod(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkOptionReceiverMethod(Checker, self, node, call, temporaries);
        }
        /// Check a read or write on an owned resource binding and its Result type.
        pub fn checkResourceIo(self: *Checker, node: ast.Node, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io"), out: *typed.Node) Error!void {
            return impl.checkResourceIo(Checker, self, node, io, out);
        }
        /// Rewrite call syntax that names a collection form (arena `escape`, record
        /// constructors, conversions and prelude calls) into its dedicated node.
        pub fn collectionSyntax(self: *Checker, id: ast.NodeId) Error!ast.Node {
            return impl.collectionSyntax(Checker, self, id);
        }
        /// The element type of a managed list, or `E_LIST_TYPE` when the value is not a list.
        pub fn listElement(self: *Checker, ty_value: typed.Type, span: source.Span) Error!typed.Type {
            return impl.listElement(Checker, self, ty_value, span);
        }
        /// The local behind `name.method(...)` when `name` is a narrowed Option of a collection.
        pub fn narrowedCollection(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
            return impl.narrowedCollection(Checker, self, call);
        }
        /// Whether a call whose receiver is a plain name belongs to the intrinsic
        /// `Option` methods: the name is an active binding declared as an `Option`,
        /// and either the name is one of the three methods or the payload is not a
        /// narrowed collection, whose own methods this receiver keeps.
        pub fn optionReceiverMethod(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
            return impl.optionReceiverMethod(Checker, self, call);
        }
        /// Require a sort element type with a total order: an integer, float or `str`.
        pub fn requireSortable(self: *Checker, element: typed.Type, span: source.Span) Error!void {
            return impl.requireSortable(Checker, self, element, span);
        }
        /// Whether equality-based collection operations would compare a Cell-bearing type.
        pub fn requiresCellEquality(self: *Checker, ty_value: typed.Type) bool {
            return impl.requiresCellEquality(Checker, self, ty_value);
        }
    };
}
fn collectionSyntax(comptime Checker: type, self: *Checker, id: ast.NodeId) Error!ast.Node {
    var node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data == .call) {
        const call = node.data.call;
        // NEW-CORE-S5-ARENA-2: `name.escape(value)` on an arena binding is `value`;
        // any other use of the name is an unknown name.
        if (call.owner) |owner| if (self.arenaBinding(owner) and std.mem.eql(u8, self.src.text(call.name), "escape")) {
            try call_arguments.positional(call, self.sink);
            if (call.type_arguments.len != 0 or call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "escape requires exactly one value argument");
            node.data = .{ .arena_escape = .{ .arena = owner, .value = call.arguments[0] } };
            return node;
        };
        if (try @import("record_calls.zig").lower(self.allocator, self.src, self.catalog, call, self.sink)) |record| {
            node.data = record.data;
            return node;
        }
        if (call.owner == null) {
            const name = self.src.text(call.name);
            const shadowed = self.active.contains(name) or self.functions.contains(name) or
                (if (self.catalog.module_names) |names| try names.topLevel(call.name) else false);
            if (try truncating.lower(self.src, call, node.span, shadowed, self.sink)) |helper| {
                node.data = helper.data;
                return node;
            }
        }
        if (call.owner == null or !self.active.contains(self.src.text(call.owner.?))) {
            if (try variant_calls.lower(self.src, self.catalog, call, node.span, self.sink)) |variant| {
                node.data = variant.data;
                return node;
            }
        }
        if (call.owner) |owner| if (self.active.get(self.src.text(owner))) |slot| {
            try self.requireReadable(slot, owner);
            const value_type = self.locals.items[@backingInt(slot)].ty;
            if (value_type.isFile()) {
                try call_arguments.positional(call, self.sink);
                const kind = file_operations.method(self.src.text(call.name)) orelse
                    return self.sink.fail(eFileArgument, call.name, "unknown file method; open handles support read, readline, readlines, write, flush and close");
                const most: usize = @intFromBool(kind.takesArgument());
                const least: usize = @intFromBool(kind.requiresArgument());
                if (call.type_arguments.len != 0 or call.arguments.len > most or call.arguments.len < least)
                    return self.fileMethodArityFailure(call.name, kind, call.arguments.len);
                node.data = .{ .file_operation = .{ .kind = kind, .owner = owner, .argument = if (call.arguments.len == 0) null else call.arguments[0] } };
                return node;
            }
            // `values.sort(key=..., reverse=...)` stays a call: its operands
            // are named, and it lowers to a keyed sort, not one operation.
            if (self.listSortOwner(call) != null) return node;
            if (value_type.isAggregate() and self.catalog.records[value_type.recordIndex()].isCollection()) {
                try call_arguments.positional(call, self.sink);
                const name = self.src.text(call.name);
                const family = self.catalog.records[value_type.recordIndex()].collection.kind;
                const raw_kind = buffer_operations.methodFor(name, call.arguments.len) orelse {
                    _ = try removed_names.reject(self.sink, call.name, name);
                    return self.sink.fail("E_LIST_METHOD", call.name, try self.unknownMethodMessage(family, value_type));
                };
                const kind = buffer_operations.forFamily(raw_kind, family);
                // A set answers only the set vocabulary, never the mapping one
                // its dictionary representation would otherwise admit (SET-1).
                if (typed.isSet(self.catalog.records[value_type.recordIndex()]) and !buffer_operations.setMethod(kind))
                    return self.sink.fail("E_LIST_METHOD", call.name, try self.unknownMethodMessage(family, value_type));
                // The everyday vocabulary stays a buffer operation; the
                // checker picks its arity from the receiver and `pop` name.
                if (!buffer_operations.vocabulary(kind) and (call.type_arguments.len != 0 or call.arguments.len != kind.arity()))
                    return self.methodArityFailure(.{
                        .span = node.span,
                        .name = call.name,
                        .kind = kind,
                        .names = try self.signatureNames(value_type),
                        .arguments = call.arguments.len,
                    });
                node.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = call.arguments } };
            } else if (record_layouts.tupleRecord(self.catalog.records, value_type) != null)
                return self.sink.fail("E_TYPE", call.name, "a tuple has no methods; take it apart with `head, rest = value`");
        };
    }
    if (node.data == .field) {
        const field = node.data.field;
        const base = self.syntax.nodes.items[@backingInt(field.base)];
        if (base.data == .name and !self.active.contains(self.src.text(base.data.name))) {
            if (try variant_calls.declaresVariant(self.src, self.catalog, base.data.name, self.sink))
                node.data = .{ .variant = .{ .ty = base.data.name, .name = field.name, .value = null } };
        }
    }
    return node;
}
/// The element type of a managed list, or `E_LIST_TYPE` when the value is not a list.
fn listElement(comptime Checker: type, self: *Checker, ty_value: typed.Type, span: source.Span) Error!typed.Type {
    if (!ty_value.isAggregate() or !self.catalog.records[ty_value.recordIndex()].isCollection()) return self.sink.fail(eListType, span, needs_list);
    if (self.catalog.records[ty_value.recordIndex()].collection.kind != .list) return self.sink.fail(eListType, span, needs_list);
    return self.catalog.records[ty_value.recordIndex()].shape.buffer orelse return self.sink.fail(eListType, span, needs_list);
}
/// Whether equality-based collection operations would compare a Cell-bearing type.
fn requiresCellEquality(comptime Checker: type, self: *Checker, ty_value: typed.Type) bool {
    return ty_value.isAggregate() and self.catalog.records[ty_value.recordIndex()].collection.contains_cell;
}
fn checkListLiteral(comptime Checker: type, self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    var expected = self.expected_types.get(node.span);
    if (expected) |ty_value| if (arrays.fixed(self.catalog, ty_value) != null) return self.checkFixedArray(node, inputs, temporaries, ty_value);
    var element: ?typed.Type = if (expected) |ty_value| try listElement(Checker, self, ty_value, node.span) else null;
    if (inputs.len == 0 and expected == null) return self.sink.fail("E_LIST_INFERENCE", node.span, "empty list requires an expected List type");
    const values = try self.allocator.alloc(typed.NodeId, inputs.len);
    for (inputs, values) |input, *value| {
        if (element) |ty_value| try self.hint(input, ty_value);
        value.* = try self.expressionWithTemporaries(input, temporaries);
        const actual = self.nodes.items[@backingInt(value.*)].ty;
        if (element) |ty_value| try self.require(actual, ty_value, self.syntax.nodes.items[@backingInt(input)].span) else element = actual;
    }
    if (expected == null) expected = try collections.listType(&self.catalog, element.?, node.span);
    if (!typed.storable(element.?, self.catalog.records) or typed.moveOnly(element.?, self.catalog.records) or self.requiresHandling(element.?))
        return self.sink.fail(eListType, node.span, "list elements require copyable storable values without pending results");
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).literal(expected.?, values);
}
/// Bind a comprehension's element name to a fresh slot for the duration of its body.
fn bindElement(comptime Checker: type, self: *Checker, name: source.Span, slot: typed.LocalId) Error!?typed.LocalId {
    const text = self.src.text(name);
    if (try self.shadows(name)) return self.sink.fail(eShadowing, name, "comprehension binding shadows an active declaration");
    self.locals.items[@backingInt(slot)].name = text;
    self.locals.items[@backingInt(slot)].declaration = name;
    self.locals.items[@backingInt(slot)].ownership.initialized = true;
    return self.bindScoped(text, slot);
}
/// Build `[value for name in source if condition]` as a checked loop over a fresh list,
/// drawing elements from a collection or, like a `for` loop, from an integer `range(...)`.
fn checkComprehension(comptime Checker: type, self: *Checker, node: ast.Node, each: ast.Comprehension, temporaries: []const typed.Type) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const iterable_node = switch (each.source) {
        .range => |bounds| return checkRangeComprehension(Checker, self, b, node, each, bounds),
        .iterable => |iterable| iterable,
    };
    const source_value = try self.expressionWithTemporaries(iterable_node, temporaries);
    const view = dictionary_views.identify(self.catalog, self.nodes.items[@backingInt(source_value)].ty);
    const projected = view != null and view.? != .item;
    const iterable = if (projected) try dictionary_views.owner(Checker, self, node.span, source_value) else source_value;
    const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
    const fixed = arrays.fixed(self.catalog, iterable_type);
    if (fixed == null and !self.collectionType(iterable_type)) return self.sink.fail(eCollectionMethod, node.span, "iteration requires a list, str, fixed array or dictionary");
    const schema = self.catalog.records[iterable_type.recordIndex()];
    const element = if (fixed) |shape| shape.element else if (projected) try dictionary_views.element(&self.catalog, iterable_type, view.?, node.span) else switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .string => iterable_type,
        .bytes => typed.Type.i64,
        .dictionary => schema.collection.key.?,
    };
    const owner = try b.local(iterable_type);
    const index = try b.local(.i64);
    const limit = try b.local(.i64);
    const value_slot = try b.local(element);
    const parts = try comprehensionBody(Checker, self, b, node, each, value_slot);
    const slots: ComprehensionSlots = .{ .owner = owner, .index = index, .limit = limit, .slot = value_slot };
    const source_values: ComprehensionSource = .{
        .iterable = .{ .value = iterable, .body = .{ .expression = each.output } },
        .output = parts.output,
        .kind = schema.collection.kind,
        .reserve = each.filter == null and !each.set,
        .projection = if (projected) view else null,
        .fixed = fixed,
        .set = each.set,
    };
    return comprehensionLoop(Checker, self, b, slots, parts.body, source_values);
}
fn checkSetFromIterable(comptime Checker: type, self: *Checker, span: source.Span, source_value: typed.NodeId) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const view = dictionary_views.identify(self.catalog, self.nodes.items[@backingInt(source_value)].ty);
    const projected = view != null and view.? != .item;
    const iterable = if (projected) try dictionary_views.owner(Checker, self, span, source_value) else source_value;
    const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
    const fixed = arrays.fixed(self.catalog, iterable_type);
    if (fixed == null and !self.collectionType(iterable_type)) return self.sink.fail(eCollectionMethod, span, "set() takes a list, str, bytes, fixed array, dictionary, dictionary view or set");
    const schema = self.catalog.records[iterable_type.recordIndex()];
    const element = if (fixed) |shape| shape.element else if (projected) try dictionary_views.element(&self.catalog, iterable_type, view.?, span) else switch (schema.collection.kind) {
        .list => schema.shape.buffer.?,
        .string => iterable_type,
        .bytes => typed.Type.i64,
        .dictionary => schema.collection.key.?,
    };
    try self.requireSetElement(element, span);
    const owner = try b.local(iterable_type);
    const index = try b.local(.i64);
    const limit = try b.local(.i64);
    const value_slot = try b.local(element);
    const output = try b.local(try set_lower.setType(&self.catalog, element, span));
    const sets: set_lower.Builder(Checker) = .{ .b = b };
    const body = try sets.add(output, try b.read(value_slot));
    const slots: ComprehensionSlots = .{ .owner = owner, .index = index, .limit = limit, .slot = value_slot };
    return comprehensionLoop(Checker, self, b, slots, body, .{
        .iterable = .{ .value = iterable },
        .output = output,
        .kind = schema.collection.kind,
        .reserve = false,
        .projection = if (projected) view else null,
        .fixed = fixed,
        .set = true,
    });
}
/// Check the produced value and optional filter with `slot` bound to the element name,
/// returning the fresh output list and the retained-append body the loop repeats. Shared
/// by the collection and range forms so both keep one element-storability contract.
fn comprehensionBody(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), node: ast.Node, each: ast.Comprehension, slot: typed.LocalId) Error!struct { output: typed.LocalId, body: typed.StatementId } {
    const hidden = try bindElement(Checker, self, each.name, slot);
    defer self.unbindScoped(self.src.text(each.name), hidden);
    const produced = try self.expression(each.output);
    const produced_type = self.nodes.items[@backingInt(produced)].ty;
    // `{value for ...}` adds each value to a fresh set instead (SET-1).
    if (each.set) try self.requireSetElement(produced_type, node.span);
    if (!typed.storable(produced_type, self.catalog.records) or typed.moveOnly(produced_type, self.catalog.records) or self.requiresHandling(produced_type))
        return self.sink.fail(eListType, node.span, "list elements require copyable storable values without pending results");
    const output = try b.local(if (each.set) try set_lower.setType(&self.catalog, produced_type, node.span) else try collections.listType(&self.catalog, produced_type, node.span));
    const sets: set_lower.Builder(Checker) = .{ .b = b };
    const kept = if (each.set) try sets.add(output, produced) else try b.stmt(.{ .discard = try b.operation(output, .append, &.{produced}) });
    const body = if (each.filter) |condition| guarded: {
        const test_value = try self.expression(condition);
        try self.require(self.nodes.items[@backingInt(test_value)].ty, .bool, self.syntax.nodes.items[@backingInt(condition)].span);
        break :guarded try b.stmt(.{ .branch = .{ .condition = test_value, .then_body = kept, .else_body = null } });
    } else kept;
    return .{ .output = output, .body = body };
}
/// Build `[value for name in range(...)]` as an ascending integer loop, resolving the
/// half-open bounds exactly as a `for` range statement does and binding the name to the
/// running index, so a comprehension over `range` yields integer elements.
fn checkRangeComprehension(comptime Checker: type, self: *Checker, b: collections.Builder(Checker), node: ast.Node, each: ast.Comprehension, bounds: @FieldType(ast.Comprehension.Source, "range")) Error!typed.Node {
    const zero_start = self.syntax.nodes.items[@backingInt(bounds.start)].data == .unit;
    const start = if (zero_start) try b.integer(0) else try self.expression(bounds.start);
    const end = try self.expression(bounds.end);
    const element = self.nodes.items[@backingInt(start)].ty;
    try self.requireInteger(element, each.name);
    try self.require(self.nodes.items[@backingInt(end)].ty, element, self.syntax.nodes.items[@backingInt(bounds.end)].span);
    const stepped = try self.rangeStep(each.name, bounds.step, element);
    const index = try b.local(element);
    const limit = try b.local(element);
    // PY-ARRAY-NEGATIVE-1: the running index never drops below its start,
    // and an expression cannot assign it.
    self.locals.items[@backingInt(index)].mutable = false;
    if (stepped.ascending() and self.nonNegative(start, 0)) try self.counters.put(self.allocator, index, {});
    const parts = try comprehensionBody(Checker, self, b, node, each, index);
    // A trial check of a sort key's lambda discards its locals, so a
    // counter's slot must not outlive its loop.
    _ = self.counters.remove(index);
    const i = try b.read(index);
    const step = if (stepped.lower) |lower| try lower.advance(index, limit) else try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.node(element, .{ .integer = 1 }), element) } });
    const condition = if (stepped.lower) |lower| try lower.condition(index, limit) else try b.binary(.lt, i, try b.read(limit), .bool);
    const loop_id = self.loops.next;
    self.loops.next += 1;
    const counted = each.filter == null and !each.set and stepped.lower == null;
    const capacity = if (counted) try b.rangeCapacity(try b.read(index), try b.read(limit), element) else try b.integer(0);
    const output_type = self.locals.items[@backingInt(parts.output)].ty;
    const fresh = if (each.set) try b.node(output_type, .{ .array = &.{} }) else try b.node(output_type, .{ .acquire_buffer = .{ .capacity = capacity } });
    var statements: std.ArrayList(typed.StatementId) = .empty;
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = index, .value = start } }));
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = limit, .value = end } }));
    try statements.appendSlice(self.allocator, try stepped.setup());
    try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = parts.output, .value = fresh } }));
    try statements.append(self.allocator, try b.stmt(.{ .loop = .{ .id = loop_id, .condition = condition, .body = parts.body, .step = step } }));
    return b.block(statements.items, try b.read(parts.output));
}
/// Assemble D1 iteration, its mutation check, and the produced collection.
const ComprehensionSlots = struct { owner: typed.LocalId, index: typed.LocalId, limit: typed.LocalId, slot: typed.LocalId };
const ComprehensionInput = struct { value: typed.NodeId, body: ?iteration_place.Body = null };
const ComprehensionSource = struct {
    iterable: ComprehensionInput,
    output: typed.LocalId,
    kind: ManagedKind,
    reserve: bool,
    projection: ?dictionary_views.Kind = null,
    /// Set when the source is a fixed array, which is read by index.
    fixed: ?typed.Array = null,
    /// The output is a fresh set rather than a list (SET-1).
    set: bool = false,
};
fn comprehensionLoop(
    comptime Checker: type,
    self: *Checker,
    b: collections.Builder(Checker),
    slots: ComprehensionSlots,
    body: typed.StatementId,
    source_values: ComprehensionSource,
) Error!typed.Node {
    const prepared = try iteration_place.prepare(Checker, b, source_values.iterable.value, slots.owner, source_values.iterable.body);
    const i = try b.read(slots.index);
    const initialize = try b.stmt(.{ .initialize = .{ .slot = slots.slot, .value = try self.iterationRead(b, slots.owner, i, .{
        .kind = source_values.kind,
        .fixed = source_values.fixed,
        .projection = source_values.projection,
    }) } });
    const advance = try b.stmt(.{ .assign = .{ .slot = slots.index, .value = try b.binary(.add, i, try b.integer(1), .i64) } });
    const guard = try iteration_place.guard(Checker, b, prepared, slots.owner, slots.limit);
    const iteration = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ guard, initialize, body }) });
    const step = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ guard, advance }) });
    const loop_id = self.loops.next;
    self.loops.next += 1;
    const output_capacity = if (source_values.reserve) try b.read(slots.limit) else try b.integer(0);
    const output_type = self.locals.items[@backingInt(source_values.output)].ty;
    const acquire_output = if (source_values.set) try b.node(output_type, .{ .array = &.{} }) else try b.node(output_type, .{ .acquire_buffer = .{ .capacity = output_capacity } });
    return iteration_place.foldBlock(Checker, b, prepared, &.{
        try b.stmt(.{ .initialize = .{ .slot = slots.index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = slots.limit, .value = if (source_values.fixed) |shape| try b.integer(@intCast(shape.length)) else try b.length(slots.owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = source_values.output, .value = acquire_output } }),
        try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(slots.limit), .bool), .body = iteration, .step = step } }),
    }, try b.read(source_values.output));
}
/// Convert one interpolated value to text. A hole takes whatever `print` can
/// render, through the same renderer, so one value has one spelling.
fn formatPart(comptime Checker: type, self: *Checker, value: typed.NodeId, str_type: typed.Type, span: source.Span) Error!typed.NodeId {
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    if (ty_value == str_type) return value;
    if (!io_render.printable(ty_value, self.catalog.records)) return self.sink.fail(
        "E_TEXT_CONVERSION",
        span,
        "format string interpolation requires a value with a rendering; capabilities, open files and callbacks have none",
    );
    const id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = span, .ty = str_type, .data = .{ .cast = value } });
    return id;
}
/// Render an f-string's pieces once in source order, then join them into one
/// exactly-sized text allocation instead of repeatedly copying prefixes.
fn checkFormat(comptime Checker: type, self: *Checker, node: ast.Node, parts: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const str_type = self.catalog.names.get("str") orelse return error.InternalError;
    const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    const values = try self.allocator.alloc(typed.NodeId, parts.len);
    for (parts, values) |part, *value| {
        const syntax = self.syntax.nodes.items[@backingInt(part)];
        value.* = if (syntax.data == .format_field)
            try self.formatField(try self.expressionWithTemporaries(syntax.data.format_field.value, temporaries), syntax.data.format_field.spec, syntax.span)
        else
            try formatPart(Checker, self, try self.expressionWithTemporaries(part, temporaries), str_type, syntax.span);
    }
    if (values.len == 1) return builder.block(&.{}, values[0]);
    const empty = try builder.node(str_type, .{ .array = &.{} });
    if (values.len == 0) return builder.block(&.{}, empty);
    const list_type = try collections.listType(&self.catalog, str_type, node.span);
    const list = try builder.literal(list_type, values);
    const list_id = try builder.node(list.ty, list.data);
    return builder.access(empty, .join, &.{list_id}, false);
}
fn narrowedCollection(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
    const owner = call.owner orelse return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    const shape = self.narrowedOption(slot) orelse return null;
    if (!shape.element.isAggregate() or !self.catalog.records[shape.element.recordIndex()].isCollection()) return null;
    return slot;
}
fn checkNarrowedMethod(comptime Checker: type, self: *Checker, node: ast.Node, slot: typed.LocalId, temporaries: []const typed.Type) Error!typed.Node {
    const call = node.data.call;
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "collection methods do not take explicit type arguments");
    const shape = self.narrowedOption(slot).?;
    const kind = buffer_operations.methodFor(self.src.text(call.name), call.arguments.len) orelse
        return self.sink.fail(eCollectionMethod, call.name, try self.unknownMethodMessage(self.catalog.records[shape.element.recordIndex()].collection.kind, shape.element));
    var value: typed.Node = .{ .span = call.owner.?, .ty = .unit, .data = .unit };
    try self.checkName(.{ .span = call.owner.?, .data = .{ .name = call.owner.? } }, call.owner.?, &value);
    const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    return checkCollectionAccess(Checker, self, node, .{ .base = base, .kind = kind, .inputs = call.arguments, .temporaries = temporaries });
}
/// Check one intrinsic `Option[T]` method against an already checked
/// receiver. `unwrap_or`'s default is checked against the payload with the
/// ordinary literal inference, so an integer-literal default adopts the
/// payload type exactly as it does in a binding. Presence tests lower to the
/// tag test and `unwrap_or` to a two-arm match, both through `option_flow`.
fn checkOptionMethod(comptime Checker: type, self: *Checker, node: ast.Node, base: typed.NodeId, name: source.Span, arguments: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const text = self.src.text(name);
    const receiver_type = self.nodes.items[@backingInt(base)].ty;
    // A narrowed local has already projected its payload, so the receiver
    // type decides: an Option here still needs its tag, a payload does not.
    const shape = prelude.optionShape(receiver_type, self.catalog.records);
    const payload = if (shape) |present| present.element else receiver_type;
    const intrinsic = option_flow.methodNamed(text) orelse return self.sink.fail(eCollectionMethod, name, option_flow.method_spellings);
    if (intrinsic == .unwrap_or and arguments.len != 1)
        return self.sink.fail("E_ARITY", node.span, "`unwrap_or` takes exactly one argument: `unwrap_or(default)`");
    if (intrinsic != .unwrap_or and arguments.len != 0) {
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` takes no arguments", .{text});
        return self.sink.fail("E_ARITY", node.span, message);
    }
    if (shape != null and self.transfers(receiver_type))
        return self.sink.fail(eOptionTest, name, "use match for an Option carrying an owned value or checked Result");
    if (intrinsic == .unwrap_or) {
        const argument = arguments[0];
        try self.hint(argument, payload);
        const fallback = try self.expressionWithTemporaries(argument, temporaries);
        const actual = self.nodes.items[@backingInt(fallback)].ty;
        if (actual != payload) {
            const expected_name = try typed.surfaceTypeName(self.allocator, payload, self.catalog.records);
            const actual_name = try typed.surfaceTypeName(self.allocator, actual, self.catalog.records);
            const message = try std.fmt.allocPrint(self.allocator, "`unwrap_or` default must be `{s}` (the Option's payload), found {s}", .{ expected_name, actual_name });
            return self.sink.fail("E_TYPE", self.syntax.nodes.items[@backingInt(argument)].span, message);
        }
        // A proven-present receiver is its own payload; the default is
        // checked for its type but is dead on every path that reaches here.
        if (shape == null) return self.nodes.items[@backingInt(base)];
        return option_flow.defaultValue(Checker, self, base, shape.?, fallback, node.span);
    }
    if (shape == null) return .{ .span = node.span, .ty = .bool, .data = .{ .boolean = intrinsic == .is_some } };
    const presence = try option_flow.testValue(self, base, shape.?, node.span);
    if (intrinsic == .is_none) return presence;
    const test_id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, presence);
    return .{ .span = node.span, .ty = .bool, .data = .{ .unary = .{ .op = .not, .operand = test_id, .op_span = node.span } } };
}
/// Whether a call whose receiver is a plain name belongs to the intrinsic
/// `Option` methods: the name is an active binding declared as an `Option`,
/// and either the name is one of the three methods or the payload is not a
/// narrowed collection, whose own methods this receiver keeps.
fn optionReceiverMethod(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
    const owner = call.owner orelse return false;
    const slot = self.active.get(self.src.text(owner)) orelse return false;
    if (prelude.optionShape(self.locals.items[@backingInt(slot)].ty, self.catalog.records) == null) return false;
    return option_flow.methodNamed(self.src.text(call.name)) != null or narrowedCollection(Checker, self, call) == null;
}
/// Check the intrinsic `Option` method one named local receiver calls. The
/// caller has already established that this call is one of them.
fn checkOptionReceiverMethod(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), temporaries: []const typed.Type) Error!typed.Node {
    try call_arguments.positional(call, self.sink);
    const owner = call.owner.?;
    var value: typed.Node = .{ .span = owner, .ty = .unit, .data = .unit };
    try self.checkName(.{ .span = owner, .data = .{ .name = owner } }, owner, &value);
    const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    return checkOptionMethod(Checker, self, node, base, call.name, call.arguments, temporaries);
}
fn checkCollectionMethod(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const call = node.data.method_call;
    const name = self.src.text(call.name);
    _ = try removed_names.reject(self.sink, call.name, name);
    // The receiver is checked first so an unknown method can name its type;
    // `checkListAccess` reads the same cached checked node.
    const base = try self.expressionWithTemporaries(call.base, temporaries);
    const owner_type = self.nodes.items[@backingInt(base)].ty;
    if (prelude.optionShape(owner_type, self.catalog.records) != null)
        return checkOptionMethod(Checker, self, node, base, call.name, call.arguments, temporaries);
    if (owner_type == .stream_cap) return self.checkStreamReceiverMethod(node, base, temporaries);
    switch (owner_type) {
        .filesystem_cap, .network_cap, .environment_cap, .clock_cap, .random_cap, .host_cap => return self.checkCapabilityReceiverMethod(node, base, temporaries),
        else => {},
    }
    // Only a list's `sort` takes named operands, and passing any operand
    // to it is the Python keyword form.
    if (std.mem.eql(u8, name, "sort") and call.arguments.len != 0) return self.checkMethodListSort(node, base, temporaries);
    if (call.argument_names.len != 0) return self.sink.fail(call_argument_code, call.name, "collection methods take their arguments by position; only a list's sort takes key= and reverse=");
    const kind = try methodKind(Checker, self, call.name, call.arguments.len, owner_type);
    if (try fusedByteRange(Checker, self, node, base, kind, call.arguments.len)) |fused| return fused;
    return checkListAccess(Checker, self, node, .{ .base = call.base, .kind = kind, .inputs = call.arguments }, temporaries);
}
/// The buffer operation a method name and argument count select on a receiver of
/// `owner_type`, or the unknown-method diagnostic listing what that receiver accepts.
fn methodKind(comptime Checker: type, self: *Checker, call_name: source.Span, count: usize, owner_type: typed.Type) Error!BufferKind {
    const name = self.src.text(call_name);
    return buffer_operations.methodFor(name, count) orelse {
        const managed = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
        const family: ?ManagedKind = if (managed) self.catalog.records[owner_type.recordIndex()].collection.kind else null;
        const message = try self.unknownMethodMessage(family, if (managed) owner_type else null);
        if (methodAlternative(name)) |alternative|
            return self.sink.failRelated(eCollectionMethod, call_name, message, .{ .span = call_name, .message = alternative, .role = .alternative });
        return self.sink.fail(eCollectionMethod, call_name, message);
    };
}
/// A numeric parse of an immutable byte string with no arguments reads the whole
/// receiver through the fused range form; null when `kind` is not such a parse.
fn fusedByteRange(comptime Checker: type, self: *Checker, node: ast.Node, base: typed.NodeId, kind: BufferKind, arguments: usize) Error!?typed.Node {
    const owner_type = self.nodes.items[@backingInt(base)].ty;
    if (arguments != 0 or !owner_type.isAggregate()) return null;
    if (!isImmutableBytes(self.catalog.records[owner_type.recordIndex()])) return null;
    const range_kind: BufferKind = switch (kind) {
        .parse_int => .parse_int_range,
        .parse_float => .parse_float_range,
        else => return null,
    };
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).fuseImmediateByteRange(base, range_kind);
}
/// The `str` or `bytes` module constant a call's receiver names: `NAME.method(...)`
/// where no local claims `NAME` and it declares a text or byte string. Returns the
/// constant's declaration index (`CONST-METHOD-1`).
fn constantReceiver(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?usize {
    const owner = call.owner orelse return null;
    if (call.type_arguments.len != 0 or self.active.contains(self.src.text(owner))) return null;
    if (self.catalog.module_names) |names| {
        const kind = try names.symbolKind(owner);
        if (kind == null or kind.? != .function) return null;
    }
    const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
    const index = try constants.lookup(owner) orelse return null;
    return if (try constants.literalType(index) != null) index else null;
}
/// Check `NAME.method(...)` on a `str` or `bytes` module constant exactly as the
/// same method on a local bound to the constant: the constant is read once and the
/// method applies to that value (`CONST-METHOD-1`).
fn checkConstantMethod(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const call = node.data.call;
    try call_arguments.positional(call, self.sink);
    _ = try removed_names.reject(self.sink, call.name, self.src.text(call.name));
    const owner = call.owner.?;
    var value: typed.Node = .{ .span = owner, .ty = .unit, .data = .unit };
    try self.checkName(.{ .span = owner, .data = .{ .name = owner } }, owner, &value);
    const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    const kind = try methodKind(Checker, self, call.name, call.arguments.len, value.ty);
    if (try fusedByteRange(Checker, self, node, base, kind, call.arguments.len)) |fused| return fused;
    return checkCollectionAccess(Checker, self, node, .{ .base = base, .kind = kind, .inputs = call.arguments, .temporaries = temporaries });
}
fn checkCollectionSlice(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const slice = node.data.slice;
    const base = try self.expressionWithTemporaries(slice.base, temporaries);
    const input = self.nodes.items[@backingInt(base)].ty;
    if (!input.isAggregate() or !self.catalog.records[input.recordIndex()].isCollection()) return self.sink.fail(eCollectionMethod, node.span, "slicing requires a list or str");
    const schema = self.catalog.records[input.recordIndex()];
    if (schema.collection.kind == .dictionary) return self.sink.fail(eCollectionMethod, node.span, "dictionary keys do not support slices");
    const start = if (slice.start) |value| try self.expressionWithTemporaries(value, temporaries) else null;
    const end = if (slice.end) |value| try self.expressionWithTemporaries(value, temporaries) else null;
    if (start) |value| try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
    if (end) |value| try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
    const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    if (slice.step) |stride| {
        if (schema.collection.kind == .bytes) return self.sink.fail(eCollectionMethod, node.span, "byte strings do not support a slice step");
        const step = try self.expressionWithTemporaries(stride, temporaries);
        try self.requireInteger(self.nodes.items[@backingInt(step)].ty, node.span);
        return b.sliceStep(base, start, end, step);
    }
    return if (schema.collection.kind == .list) b.slice(base, start, end) else b.textSlice(base, start, end);
}
/// Check a list method call or element access whose receiver is still unchecked:
/// check the receiver, then the access against it.
fn checkListAccess(comptime Checker: type, self: *Checker, node: ast.Node, operation: ListAccess, temporaries: []const typed.Type) Error!typed.Node {
    const base = try self.expressionWithTemporaries(operation.base, temporaries);
    return checkCollectionAccess(Checker, self, node, .{
        .base = base,
        .kind = operation.kind,
        .inputs = operation.inputs,
        .temporaries = temporaries,
        .signed_length = operation.signed_length,
    });
}
fn checkCollectionAccess(comptime Checker: type, self: *Checker, node: ast.Node, call: ListMethodCall) Error!typed.Node {
    const base = call.base;
    var kind = call.kind;
    const inputs = call.inputs;
    const temporaries = call.temporaries;
    const owner_type = self.nodes.items[@backingInt(base)].ty;
    const managed_owner = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
    const dictionary = managed_owner and self.catalog.records[owner_type.recordIndex()].collection.kind == .dictionary;
    if (managed_owner) kind = buffer_operations.forFamily(kind, self.catalog.records[owner_type.recordIndex()].collection.kind);
    if (typed.setRecord(self.catalog.records, owner_type) != null)
        return self.checkSetMethodSyntax(node, .{ .span = node.span, .base = base, .kind = kind, .arguments = &.{} }, inputs, temporaries);
    // `pop` is one Python name with an optional argument; its arity selects the
    // list-tail, list-index, dictionary-key or dictionary-default form.
    if (kind == .pop) kind = if (dictionary) (if (inputs.len == 2) .pop_default else .pop_key) else (if (inputs.len == 1) .pop_at else .pop);
    if (managed_owner and self.catalog.records[owner_type.recordIndex()].collection.kind != .list) {
        return checkManagedAccess(Checker, self, node, .{ .base = base, .kind = kind, .inputs = inputs }, temporaries);
    }
    if (switch (kind) {
        .extend, .insert, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => true,
        else => false,
    }) return checkListMethod(Checker, self, node, .{ .base = base, .kind = kind, .inputs = inputs, .temporaries = temporaries });
    const supported = switch (kind) {
        .append, .read, .write, .length, .contains => true,
        else => false,
    };
    if (!supported) return self.sink.fail(eCollectionMethod, node.span, unsupported_list);
    const element = try listElement(Checker, self, self.nodes.items[@backingInt(base)].ty, node.span);
    if (kind == .contains and requiresCellEquality(Checker, self, element))
        return self.sink.fail(eCellEquality, node.span, "list membership over Cell-bearing values requires equality, which Cell does not define");
    if (inputs.len != kind.arity()) return self.methodArityFailure(.{
        .span = node.span,
        .name = node.span,
        .kind = kind,
        .names = try self.signatureNames(self.nodes.items[@backingInt(base)].ty),
        .arguments = inputs.len,
    });
    const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
    for (inputs, arguments, 0..) |input, *argument, i| {
        const writes_element = kind == .append or kind == .contains or (kind == .write and i == 1);
        if (writes_element) try self.hint(input, element);
        argument.* = try self.expressionWithTemporaries(input, temporaries);
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        if (writes_element) try self.require(actual, element, node.span) else try self.requireInteger(actual, node.span);
    }
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, arguments, call.signed_length);
}
/// Require a sort element type with a total order: an integer, float, str or bytes.
fn requireSortable(comptime Checker: type, self: *Checker, element: typed.Type, span: source.Span) Error!void {
    if (element.isInteger() or numeric_surface.isFloat(element, self.catalog.records)) return;
    if (element.isAggregate()) {
        const schema = self.catalog.records[element.recordIndex()];
        if (schema.collection.kind == .string or typed.isByteString(schema)) return;
    }
    return self.sink.fail(eCollectionMethod, span, "sort requires an integer, float, str or bytes element type");
}
/// Check a list's Python-shaped method call, which either mutates or copies its receiver.
fn checkListMethod(comptime Checker: type, self: *Checker, node: ast.Node, call: ListMethodCall) Error!typed.Node {
    const base = call.base;
    const kind = call.kind;
    const inputs = call.inputs;
    const temporaries = call.temporaries;
    const owner_type = self.nodes.items[@backingInt(base)].ty;
    const element = try listElement(Checker, self, owner_type, node.span);
    if ((kind == .remove or kind == .index_of) and requiresCellEquality(Checker, self, element))
        return self.sink.fail(eCellEquality, node.span, "list search over Cell-bearing values requires equality, which Cell does not define");
    if (inputs.len != kind.arity()) return self.methodArityFailure(.{
        .span = node.span,
        .name = node.span,
        .kind = kind,
        .names = try self.signatureNames(owner_type),
        .arguments = inputs.len,
    });
    if (kind == .sort) try requireSortable(Checker, self, element, node.span);
    const names = try self.signatureNames(owner_type);
    const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
    switch (kind) {
        .extend => {
            try self.hint(inputs[0], owner_type);
            arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[0])].ty, .expected = owner_type, .span = node.span, .kind = kind, .names = names });
        },
        .insert => {
            try self.hint(inputs[0], .i64);
            arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
            try self.requireInteger(self.nodes.items[@backingInt(arguments[0])].ty, node.span);
            try self.hint(inputs[1], element);
            arguments[1] = try self.expressionWithTemporaries(inputs[1], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[1])].ty, .expected = element, .span = node.span, .kind = kind, .names = names });
        },
        .pop_at => {
            try self.hint(inputs[0], .i64);
            arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
            try self.requireInteger(self.nodes.items[@backingInt(arguments[0])].ty, node.span);
        },
        .remove, .index_of => {
            try self.hint(inputs[0], element);
            arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[0])].ty, .expected = element, .span = node.span, .kind = kind, .names = names });
        },
        .pop, .reverse, .sort, .copy, .clear => {},
        else => return self.sink.fail(eCollectionMethod, node.span, unsupported_list),
    }
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, arguments, false);
}
fn checkManagedAccess(comptime Checker: type, self: *Checker, node: ast.Node, operation: ManagedAccess, temporaries: []const typed.Type) Error!typed.Node {
    const owner_type = self.nodes.items[@backingInt(operation.base)].ty;
    const schema = self.catalog.records[owner_type.recordIndex()];
    const dictionary = schema.collection.kind == .dictionary;
    if (dictionary) if (dictionary_views.operation(operation.kind)) |kind| {
        if (operation.inputs.len != 0) return self.sink.fail("E_ARITY", node.span, "dictionary views take no arguments");
        return dictionary_views.construct(Checker, self, node.span, operation.base, kind);
    };
    if (buffer_operations.byteBuffer(operation.kind) and !isMutableBytes(schema))
        return self.sink.fail(eCollectionMethod, node.span, byte_buffer_receiver);
    _ = collections.operationType(&self.catalog, owner_type, operation.kind, node.span) catch |err| switch (err) {
        error.InternalError => return self.sink.fail(eCollectionMethod, node.span, unsupported_collection),
        else => return err,
    };
    if (dictionary and switch (operation.kind) {
        .items, .update, .setdefault, .pop_key, .pop_default, .copy, .clear => true,
        else => false,
    }) return checkDictionaryMethod(Checker, self, node, owner_type, operation, temporaries);
    if (operation.inputs.len != operation.kind.arity()) return self.methodArityFailure(.{
        .span = node.span,
        .name = node.span,
        .kind = operation.kind,
        .names = try self.signatureNames(owner_type),
        .arguments = operation.inputs.len,
    });
    const names = try self.signatureNames(owner_type);
    const arguments = try self.allocator.alloc(typed.NodeId, operation.inputs.len);
    for (operation.inputs, arguments, 0..) |input, *argument, index| {
        const integer = !dictionary and (operation.kind == .read or operation.kind == .slice or operation.kind == .view or
            operation.kind == .parse_int_range or operation.kind == .parse_float_range or operation.kind == .scalar_count_range or widthArgument(operation.kind) or
            (operation.kind == .find_any and index == 1) or
            (buffer_operations.search(operation.kind) != null and index > 0)) or
            byteBufferInteger(operation.kind, index);
        const expected = if (integer) typed.Type.i64 else if (dictionary) map_argument: {
            break :map_argument if (index == 0) schema.collection.key.? else schema.shape.buffer.?;
        } else if (operation.kind == .buffer_append_range and index == 0)
            try collections.preludeType(&self.catalog, "bytes", node.span)
        else if (operation.kind == .buffer_append_utf8)
            self.catalog.names.get("str") orelse return error.InternalError
        else if (operation.kind == .buffer_append_float)
            self.catalog.names.get("float") orelse return error.InternalError
        else if (operation.kind == .join) try collectionListType(Checker, self, owner_type, node.span) else owner_type;
        // PY-GENERATOR-1: `"".join(x for x in xs)` joins the list the loop builds.
        if (operation.kind == .join) _ = try self.consumeGenerator(input, .list);
        try self.hintTextMethodArgument(input, expected, operation.kind);
        argument.* = try self.expressionWithTemporaries(input, temporaries);
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        if (integer) try self.requireInteger(actual, node.span) else try self.requireArgument(.{ .actual = actual, .expected = expected, .span = node.span, .kind = operation.kind, .names = names });
    }
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
}
/// Check a dictionary's Python-shaped methods against its key and value types.
fn checkDictionaryMethod(comptime Checker: type, self: *Checker, node: ast.Node, owner_type: typed.Type, operation: ManagedAccess, temporaries: []const typed.Type) Error!typed.Node {
    const schema = self.catalog.records[owner_type.recordIndex()];
    const key_type = schema.collection.key.?;
    const value_type = schema.shape.buffer.?;
    if (operation.inputs.len != operation.kind.arity()) return self.methodArityFailure(.{
        .span = node.span,
        .name = node.span,
        .kind = operation.kind,
        .names = try self.signatureNames(owner_type),
        .arguments = operation.inputs.len,
    });
    const names = try self.signatureNames(owner_type);
    const arguments = try self.allocator.alloc(typed.NodeId, operation.inputs.len);
    switch (operation.kind) {
        .items, .copy, .clear => {},
        .update => {
            try self.hint(operation.inputs[0], owner_type);
            arguments[0] = try self.expressionWithTemporaries(operation.inputs[0], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[0])].ty, .expected = owner_type, .span = node.span, .kind = operation.kind, .names = names });
        },
        .pop_key => {
            try self.hint(operation.inputs[0], key_type);
            arguments[0] = try self.expressionWithTemporaries(operation.inputs[0], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[0])].ty, .expected = key_type, .span = node.span, .kind = operation.kind, .names = names });
        },
        .pop_default, .setdefault => {
            try self.hint(operation.inputs[0], key_type);
            arguments[0] = try self.expressionWithTemporaries(operation.inputs[0], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[0])].ty, .expected = key_type, .span = node.span, .kind = operation.kind, .names = names });
            try self.hint(operation.inputs[1], value_type);
            arguments[1] = try self.expressionWithTemporaries(operation.inputs[1], temporaries);
            try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[1])].ty, .expected = value_type, .span = node.span, .kind = operation.kind, .names = names });
        },
        else => return self.sink.fail(eCollectionMethod, node.span, "operation is not supported by dictionaries"),
    }
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
}
fn collectionListType(comptime Checker: type, self: *Checker, element: typed.Type, span: source.Span) Error!typed.Type {
    const state = self.catalog.templates.store orelse return error.InternalError;
    return nominal_catalog.instantiateLengths(&self.catalog, state.index.names.get("List").?, &.{element}, &.{}, span);
}
fn checkTextDictionary(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
    const local = self.locals.items[@backingInt(owner)];
    const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;

    const schema = self.catalog.records[local.ty.recordIndex()];
    const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
    for (operation.arguments, arguments) |input, *argument| argument.* = self.resolved[@backingInt(input)].?;
    const dictionary = schema.collection.kind == .dictionary;
    const byte_string = schema.collection.kind == .bytes;
    const output_element = if (dictionary or byte_string) element else local.ty;
    if (try checkPythonText(Checker, self, operation, owner, out, arguments)) return;
    switch (operation.kind) {
        .length => out.ty = .i64,
        .find_any => {
            if (!byte_string) return self.sink.fail(eCollectionMethod, operation.owner, "find_any requires a bytes receiver and a byte set");
            try self.require(self.nodes.items[@backingInt(arguments[0])].ty, local.ty, operation.owner);
            try self.requireInteger(self.nodes.items[@backingInt(arguments[1])].ty, operation.owner);
            out.ty = .i64;
        },
        .upper, .lower, .splitlines, .replace, .zfill, .is_digit, .is_alpha, .is_space => {
            if (dictionary or byte_string) return self.sink.fail(eCollectionMethod, operation.owner, "this method requires str");
            for (arguments) |argument| {
                const actual = self.nodes.items[@backingInt(argument)].ty;
                if (widthArgument(operation.kind)) try self.requireInteger(actual, operation.owner) else try self.require(actual, local.ty, operation.owner);
            }
            out.ty = collections.operationType(&self.catalog, local.ty, operation.kind, operation.owner) catch |err| switch (err) {
                error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
                else => return err,
            };
        },
        // Both numeric parses answer through the conversion table: a `str`
        // reads its scalars and a byte string reads its octets, so neither
        // decodes a temporary value and neither allocates.
        .to_list, .hex, .decode, .encode, .from_hex, .parse_int, .parse_float => out.ty = collections.operationType(&self.catalog, local.ty, operation.kind, operation.owner) catch |err| switch (err) {
            error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
            else => return err,
        },
        // A view shares the receiver's octets, `copy` materializes them and
        // `scalar_count` measures them.
        .view, .copy, .scalar_count, .scalar_count_range, .parse_int_range, .parse_float_range => if (!try checkByteViewMethod(Checker, self, operation, owner, schema, arguments, out))
            return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
        .buffer_reserve, .buffer_append_byte, .buffer_append_range, .buffer_append_utf8, .buffer_append_int, .buffer_append_float => try checkByteBufferMethod(Checker, self, operation, owner, arguments, out),
        .read, .write, .get, .contains => {
            if (!dictionary and operation.kind != .read and operation.kind != .contains) return self.sink.fail("E_TEXT_IMMUTABLE", operation.owner, "str values are immutable");
            if (dictionary) {
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, schema.collection.key.?, operation.owner);
            } else if (operation.kind == .contains) {
                var needle = arguments[0];
                const wanted = if (byte_string) try self.byteMembership(operation.owner, &needle, local.ty) else local.ty;
                arguments[0] = needle;
                try self.require(self.nodes.items[@backingInt(needle)].ty, wanted, operation.owner);
            } else try self.requireInteger(self.nodes.items[@backingInt(arguments[0])].ty, operation.owner);
            if (arguments.len == 2) try self.require(self.nodes.items[@backingInt(arguments[1])].ty, element, operation.owner);
            out.ty = if (operation.kind == .write) .unit else if (operation.kind == .contains) .bool else output_element;
        },
        .keys, .values => {
            if (!dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "keys and values require a dictionary");
            out.ty = try collectionListType(Checker, self, if (operation.kind == .keys) schema.collection.key.? else element, operation.owner);
        },
        .split, .split_whitespace, .join => {
            if (dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "split and join require str");
            const list_type = try collectionListType(Checker, self, local.ty, operation.owner);
            // The no-argument form has no separator to type-check; `join`
            // takes the list of pieces and both splits answer one.
            if (operation.kind != .split_whitespace) try self.require(self.nodes.items[@backingInt(arguments[0])].ty, if (operation.kind == .split) local.ty else list_type, operation.owner);
            out.ty = if (operation.kind == .join) local.ty else list_type;
        },
        .items, .pop, .pop_key, .pop_default, .update, .setdefault, .clear => return checkDictionaryBufferMethod(Checker, self, operation, owner, out),
        else => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
    }
    out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
}
/// Check one byte-string method that reads the receiver's own octets rather
/// than the collection surface around them: `view` shares the octets as a
/// range that retains the source's backing, `copy` materializes them, and
/// `scalar_count` validates and measures them. All three exist only on the
/// immutable byte string, so neither a mutable buffer nor a `str` reaches
/// them, and none of them allocates except the copy it names.
fn checkByteViewMethod(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, schema: typed.Record, arguments: []const typed.NodeId, out: *typed.Node) Error!bool {
    const owner_type = self.locals.items[@backingInt(owner)].ty;
    switch (operation.kind) {
        .view => {
            if (!isImmutableBytes(schema)) return self.sink.fail(eCollectionMethod, operation.owner, "view requires an immutable bytes receiver");
            for (arguments) |argument| try self.requireInteger(self.nodes.items[@backingInt(argument)].ty, operation.owner);
            out.ty = owner_type;
        },
        .copy => {
            // A dictionary shares the spelling and keeps its own shallow copy.
            if (schema.collection.kind == .dictionary) {
                try checkDictionaryBufferMethod(Checker, self, operation, owner, out);
                return true;
            }
            if (!isImmutableBytes(schema)) return self.sink.fail(eCollectionMethod, operation.owner, "copy requires an immutable bytes receiver");
            out.ty = owner_type;
        },
        .scalar_count, .scalar_count_range, .parse_int_range, .parse_float_range => {
            if (schema.collection.kind != .bytes) return false;
            for (arguments) |argument| try self.requireInteger(self.nodes.items[@backingInt(argument)].ty, operation.owner);
            out.ty = collections.operationType(&self.catalog, owner_type, operation.kind, operation.owner) catch |err| switch (err) {
                error.InternalError => return false,
                else => return err,
            };
        },
        else => return false,
    }
    return true;
}
/// Check one in-place octet-buffer method against a `byte_buffer` receiver:
/// the appended span is another byte string, the appended text is a `str`,
/// and every other operand is a scalar count, index or byte value. Each
/// answers whether it wrote. An immutable byte string has no such method, so
/// a view or a literal can never be written through.
fn checkByteBufferMethod(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, arguments: []const typed.NodeId, out: *typed.Node) Error!void {
    const local = self.locals.items[@backingInt(owner)];
    if (!isMutableBytes(self.catalog.records[local.ty.recordIndex()]))
        return self.sink.fail(eCollectionMethod, operation.owner, byte_buffer_receiver);
    const text_type = self.catalog.names.get("str") orelse return error.InternalError;
    for (arguments, 0..) |argument, index| {
        const actual = self.nodes.items[@backingInt(argument)].ty;
        if (byteBufferInteger(operation.kind, index)) {
            try self.requireInteger(actual, operation.owner);
        } else if (operation.kind == .buffer_append_utf8) {
            try self.require(actual, text_type, operation.owner);
        } else if (operation.kind == .buffer_append_float) {
            try self.require(actual, self.catalog.names.get("float") orelse return error.InternalError, operation.owner);
        } else if (operation.kind == .buffer_append_range and index == 0) {
            // An append copies octets out of any byte-kind value, so an
            // immutable `bytes` argument is accepted beside another buffer.
            if (!actual.isAggregate() or self.catalog.records[actual.recordIndex()].collection.kind != .bytes)
                return self.sink.fail(eCollectionMethod, operation.owner, "append_range requires a bytes or byte_buffer source");
        } else try self.require(actual, local.ty, operation.owner);
    }
    out.ty = .bool;
}
/// Check a dictionary vocabulary operation reached through the buffer-operation
/// form that a simple `mapping.method(...)` call desugars to.
fn checkDictionaryBufferMethod(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
    const owner_type = self.locals.items[@backingInt(owner)].ty;
    const schema = self.catalog.records[owner_type.recordIndex()];
    if (schema.collection.kind != .dictionary) return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection);
    const key_type = schema.collection.key.?;
    const value_type = schema.shape.buffer.?;
    var kind = operation.kind;
    if (kind == .pop) kind = if (operation.arguments.len == 2) .pop_default else .pop_key;
    if (operation.arguments.len != kind.arity()) return self.methodArityFailure(.{
        .span = operation.owner,
        .name = operation.owner,
        .kind = kind,
        .names = try self.signatureNames(owner_type),
        .arguments = operation.arguments.len,
    });
    const names = try self.signatureNames(owner_type);
    const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
    for (operation.arguments, arguments, 0..) |input, *argument, index| {
        argument.* = self.resolved[@backingInt(input)].?;
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        const span = self.syntax.nodes.items[@backingInt(input)].span;
        switch (kind) {
            .items, .copy, .clear => {},
            .update => try self.requireArgument(.{ .actual = actual, .expected = owner_type, .span = span, .kind = kind, .names = names }),
            .pop_key => try self.requireArgument(.{ .actual = actual, .expected = key_type, .span = span, .kind = kind, .names = names }),
            .pop_default, .setdefault => if (index == 0)
                try self.requireArgument(.{ .actual = actual, .expected = key_type, .span = span, .kind = kind, .names = names })
            else
                try self.requireArgument(.{ .actual = actual, .expected = value_type, .span = span, .kind = kind, .names = names }),
            else => {},
        }
    }
    out.ty = collections.operationType(&self.catalog, owner_type, kind, operation.owner) catch |err| switch (err) {
        error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
        else => return err,
    };
    out.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = arguments } };
}
fn checkBufferOperation(comptime Checker: type, self: *Checker, _: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), out: *typed.Node) Error!void {
    const owner = try self.resolve(operation.owner);
    const local = &self.locals.items[@backingInt(owner)];
    if (!local.ty.isAggregate() or !self.catalog.records[local.ty.recordIndex()].isCollection()) return self.sink.fail(eListType, operation.owner, needs_list);
    local.usage.reads += 1;
    if (typed.isSet(self.catalog.records[local.ty.recordIndex()])) {
        if (operation.kind.mutates()) local.usage.writes += 1;
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments) |input, *argument| argument.* = self.resolved[@backingInt(input)].?;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = out.span };
        out.* = try self.checkSetMethod(.{ .span = out.span, .base = try b.read(owner), .kind = operation.kind, .arguments = arguments });
        return;
    }
    if (self.catalog.records[local.ty.recordIndex()].collection.kind == .dictionary) if (dictionary_views.operation(operation.kind)) |kind| {
        if (operation.arguments.len != 0) return self.sink.fail("E_ARITY", operation.owner, "dictionary views take no arguments");
        const b: collections.Builder(Checker) = .{ .checker = self, .span = out.span };
        out.* = try dictionary_views.construct(Checker, self, out.span, try b.read(owner), kind);
        return;
    };
    if (operation.kind.mutates()) local.usage.writes += 1;
    const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;
    if (self.catalog.records[local.ty.recordIndex()].collection.kind != .list) {
        try checkTextDictionary(Checker, self, operation, owner, out);
        return;
    }
    if (operation.kind == .contains and requiresCellEquality(Checker, self, element))
        return self.sink.fail(eCellEquality, operation.owner, "list membership over Cell-bearing values requires equality, which Cell does not define");
    switch (operation.kind) {
        .append, .read, .write, .length, .capacity, .contains, .iteration_check => {},
        .extend, .insert, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => {
            try checkListBufferMethod(Checker, self, operation, owner, out);
            return;
        },
        else => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_list),
    }
    const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
    for (operation.arguments, arguments, 0..) |input, *argument, argument_index| {
        argument.* = self.resolved[@backingInt(input)].?;
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        const span = self.syntax.nodes.items[@backingInt(input)].span;
        const writes_element = argument_index == 1 and operation.kind == .write;
        if (operation.kind == .append or operation.kind == .contains or writes_element) {
            try self.require(actual, element, span);
        } else {
            try self.requireInteger(actual, span);
        }
    }
    out.ty = if (operation.kind.mutates()) .unit else if (operation.kind == .read) element else if (operation.kind == .contains) .bool else .u64;
    out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
}
/// Check a list vocabulary operation reached through the buffer-operation form
/// that a simple `values.method(...)` call desugars to.
fn checkListBufferMethod(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
    const owner_type = self.locals.items[@backingInt(owner)].ty;
    const element = self.catalog.records[owner_type.recordIndex()].shape.buffer.?;
    var kind = operation.kind;
    if (kind == .pop) kind = if (operation.arguments.len == 1) .pop_at else .pop;
    if ((kind == .remove or kind == .index_of) and requiresCellEquality(Checker, self, element))
        return self.sink.fail(eCellEquality, operation.owner, "list search over Cell-bearing values requires equality, which Cell does not define");
    if (operation.arguments.len != kind.arity()) return self.methodArityFailure(.{
        .span = operation.owner,
        .name = operation.owner,
        .kind = kind,
        .names = try self.signatureNames(owner_type),
        .arguments = operation.arguments.len,
    });
    if (kind == .sort) try requireSortable(Checker, self, element, operation.owner);
    const names = try self.signatureNames(owner_type);
    const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
    for (operation.arguments, arguments, 0..) |input, *argument, index| {
        argument.* = self.resolved[@backingInt(input)].?;
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        const span = self.syntax.nodes.items[@backingInt(input)].span;
        switch (kind) {
            .extend => try self.requireArgument(.{ .actual = actual, .expected = owner_type, .span = span, .kind = kind, .names = names }),
            .insert => if (index == 0) try self.requireInteger(actual, span) else try self.requireArgument(.{ .actual = actual, .expected = element, .span = span, .kind = kind, .names = names }),
            .pop_at => try self.requireInteger(actual, span),
            .remove, .index_of => try self.requireArgument(.{ .actual = actual, .expected = element, .span = span, .kind = kind, .names = names }),
            else => {},
        }
    }
    out.ty = collections.operationType(&self.catalog, owner_type, kind, operation.owner) catch |err| switch (err) {
        error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
        else => return err,
    };
    out.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = arguments } };
}
fn checkAcquireResource(comptime Checker: type, self: *Checker, _: ast.Node, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource"), out: *typed.Node) Error!void {
    out.ty = try self.ty(acquire.ty);
    const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceResult, acquire.ty, "acquisition requires a resource success and i64 error result");
    const kind = typed.resourceKind(shape.ok_type, self.catalog.records) orelse return self.sink.fail(eResourceResult, acquire.ty, "acquisition success must be a resource");
    if (shape.error_type != .i64) return self.sink.fail(eResourceResult, acquire.ty, "acquisition error must be i64");
    const capability = self.resolved[@backingInt(acquire.capability)].?;
    const request = self.resolved[@backingInt(acquire.request)].?;
    try self.require(self.nodes.items[@backingInt(capability)].ty, if (kind == .filesystem) .filesystem_cap else .network_cap, self.syntax.nodes.items[@backingInt(acquire.capability)].span);
    const request_type = self.nodes.items[@backingInt(request)].ty;
    if (!typed.acquisitionBytes(request_type, self.catalog.records)) return self.sink.fail("E_RESOURCE_REQUEST", self.syntax.nodes.items[@backingInt(acquire.request)].span, "request must be a fixed u8 array");
    out.data = .{ .acquire_resource = .{ .capability = capability, .request = request } };
}
fn checkResourceIo(comptime Checker: type, self: *Checker, node: ast.Node, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io"), out: *typed.Node) Error!void {
    const owner = try self.resolve(io.owner);
    const local = &self.locals.items[@backingInt(owner)];
    if (typed.resourceKind(local.ty, self.catalog.records) == null) return self.sink.fail("E_RESOURCE_TYPE", io.owner, "I/O requires an owned resource binding");
    if (!local.ownership.transfer_available) return self.sink.failTransfer(eOwnedConsumed, io.owner, local.declaration, local.ownership.transfer_span);
    if (!local.mutable) return self.sink.fail(eImmutable, io.owner, "resource I/O requires a binding it may modify");
    out.ty = try self.ty(io.ty);
    if (io.kind == .read) {
        if (typed.resourceReadShape(out.ty, self.catalog.records) == null) return self.sink.fail(eResourceIoResult, io.ty, "read result requires i64 error and record success with bytes: [N]u8, length: u64, eof: bool");
    } else {
        const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceIoResult, io.ty, "write result requires u64 success and i64 error");
        if (shape.ok_type != .u64 or shape.error_type != .i64) return self.sink.fail(eResourceIoResult, io.ty, "write result requires u64 success and i64 error");
    }
    const value = if (io.value) |input| self.resolved[@backingInt(input)].? else null;
    if (value) |input| if (!typed.byteRequest(self.nodes.items[@backingInt(input)].ty, self.catalog.records)) return self.sink.fail("E_RESOURCE_BYTES", node.span, "write input must be a fixed u8 array");
    local.usage.reads += 1;
    local.usage.writes += 1;
    out.data = .{ .resource_io = .{ .kind = io.kind, .owner = owner, .value = value } };
}

test "a byte-buffer append takes its source span first and scalar operands after it" {
    try std.testing.expect(!byteBufferInteger(.buffer_append_range, 0));
    try std.testing.expect(byteBufferInteger(.buffer_append_range, 1));
    try std.testing.expect(byteBufferInteger(.buffer_append_byte, 0));
    try std.testing.expect(!byteBufferInteger(.buffer_append_utf8, 0));
    try std.testing.expect(!byteBufferInteger(.buffer_append_float, 0));
    try std.testing.expect(widthArgument(.zfill));
}

/// Check text/byte needles and charsets separately from integer search bounds.
fn hintTextMethodArgument(comptime Checker: type, self: *Checker, input: ast.NodeId, expected: typed.Type, kind: BufferKind) Error!void {
    const node = self.syntax.nodes.items[@backingInt(input)];
    if (buffer_operations.search(kind) != null or buffer_operations.trim(kind) != null) {
        if (node.data == .bytes and expected.isAggregate()) {
            const spelling = self.src.text(node.span);
            if (spelling.len != 0 and spelling[0] == 'b') {
                if (self.catalog.records[expected.recordIndex()].collection.kind == .string)
                    return self.sink.fail("E_TYPE", node.span, "bytes needle or charset cannot be used as str");
            }
        }
    }
    try self.hint(input, expected);
}

/// Check text/byte needles and charsets separately from integer search bounds.
fn checkTextOperands(comptime Checker: type, self: *Checker, kind: BufferKind, arguments: []const typed.NodeId, owner: typed.Type, span: source.Span) Error!void {
    for (arguments, 0..) |argument, index| {
        const actual = self.nodes.items[@backingInt(argument)].ty;
        if (buffer_operations.search(kind) != null and index > 0)
            try self.requireInteger(actual, span)
        else
            try self.require(actual, owner, span);
    }
}

/// Validate and publish search/trim independently of dictionary method checking.
fn checkPythonText(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node, arguments: []const typed.NodeId) Error!bool {
    if (buffer_operations.search(operation.kind) == null and buffer_operations.trim(operation.kind) == null) return false;
    const local = self.locals.items[@backingInt(owner)];
    if (self.catalog.records[local.ty.recordIndex()].collection.kind == .dictionary)
        return self.sink.fail(eCollectionMethod, operation.owner, "search and trim require str or bytes");
    try checkTextOperands(Checker, self, operation.kind, arguments, local.ty, operation.owner);
    out.ty = try collections.operationType(&self.catalog, local.ty, operation.kind, operation.owner);
    out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
    return true;
}
