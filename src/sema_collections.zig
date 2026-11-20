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
const eResultOperation = diagnostic.result_operation;
const collections = @import("collection_lower.zig");
const text_scalar = @import("scalar_text_helpers.zig");
/// The diagnostic for a stepped slice, which a contiguous view cannot be.
const stepped_slice_code = "E_STEPPED_SLICE_REMOVED";
const borrow_view_fix = @import("borrow_view_fix.zig");
const stepped_slice_message = "a stepped slice was removed; a slice is a contiguous view, so use strings.char_stride or lists.stride";
const iteration_place = @import("iteration_place.zig");
const option_flow = @import("option_flow.zig");
const option_spelling = @import("option_spelling.zig");
const copy_method = @import("copy_method.zig");
const retired_methods = @import("retired_methods.zig");
const retiring_forms = @import("retiring_forms.zig");
const contains_removed = @import("contains_removed.zig");
const import_fix = @import("import_fix.zig");
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const file_operations = @import("file_operations.zig");
const call_argument_code = sema_shared.call_argument_code;
const eShadowing = diagnostic.shadowing;
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const eResourceResult = diagnostic.resource_result;
const eResourceType = diagnostic.resource_type;
const eImmutable = diagnostic.immutable;
const std = @import("std");
const copy_arity = "copy takes no arguments";
const dictionary_views = @import("dictionary_views.zig");
const eCollectionMethod = sema_shared.eCollectionMethod;
const ast = @import("ast.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const mutation_marker_code = @import("origins.zig").mutation_marker_code;
const receiver_marker = @import("sema_receiver_marker.zig");
const own_marker_code = @import("own_parameters.zig").marker_code;
const diagnostic = @import("diagnostic.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const eFileArgument = sema_shared.eFileArgument;
const negative_index = @import("negative_index.zig");
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
/// String functions whose only operand is a scalar width rather than more text.
fn widthArgument(kind: BufferKind) bool {
    return kind == .zfill;
}
/// Whether one operand of an in-place byte-buffer method is a scalar count or
/// index rather than another managed value. `append_range` takes the source span
/// first and both endpoints after it, `append_utf8` takes text, and every other
/// method takes one count or byte value.
fn byteBufferInteger(kind: BufferKind, index: usize) bool {
    return switch (kind) {
        .buffer_append_range, .buffer_append_array => index > 0,
        .buffer_append, .buffer_append_utf8, .buffer_append_float => false,
        else => buffer_operations.byteBuffer(kind),
    };
}
/// The one diagnostic for an in-place buffer method on a receiver that is not
/// the mutable octet buffer.
const byte_buffer_receiver = "in-place buffer methods require a byte_buffer receiver";
/// The diagnostic for an `append_array` source that is not a fixed array of octets.
const append_array_source = "append_array requires a FixedArray[u8, N] source";
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
        /// Check accepting one connection from a live network resource.
        pub fn checkAcceptResource(self: *Checker, accept: @FieldType(@FieldType(ast.Node, "data"), "accept_resource"), out: *typed.Node) Error!void {
            return impl.checkAcceptResource(Checker, self, accept, out);
        }
        /// Check a method on a named collection local, including dictionary views and
        /// the in-place list methods that count as writes.
        pub fn checkBufferOperation(self: *Checker, unused1: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), out: *typed.Node) Error!void {
            try impl.checkBufferOperation(Checker, self, unused1, operation, out);
            try impl.checkNegativeBufferPositions(Checker, self, out);
        }
        /// Normalize a checked collection operation's negative position arguments
        /// the way a method call's are; a helper builds the same operation and needs
        /// the same refusal and repair.
        pub fn normalizeNegativePositions(self: *Checker, out: *typed.Node) Error!void {
            return impl.checkNegativeBufferPositions(Checker, self, out);
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
        /// Check an `f"..."` literal as one node of its literal pieces and its
        /// holes, each with its resolved format specification.
        pub fn checkFormat(self: *Checker, node: ast.Node, parts: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkFormat(Checker, self, node, parts, temporaries);
        }
        /// check the receiver, then the access against it.
        pub fn checkListAccess(self: *Checker, node: ast.Node, operation: ListAccess, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkListAccess(Checker, self, node, operation, temporaries);
        }
        /// Check a list literal, inferring the element type from context or the first
        /// element; a fixed-array context requires an explicit constructor.
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
        /// Recognize the prelude spellings that write through their first argument.
        pub fn writerFunction(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?WriterFunction {
            return impl.writerFunction(Checker, self, call);
        }
        /// Check `append(mut xs, x)` or `sort(mut xs)`, marker included.
        pub fn checkWriterFunction(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: WriterFunction) Error!typed.Node {
            return impl.checkWriterFunction(Checker, self, node, call, kind);
        }
        /// Refuse `values.sort(key=…)` onto the prelude `sort(mut values, key=…)`.
        /// The keyword form has its own queued lowering, so it asks here before
        /// it lowers instead of reaching the method table.
        pub fn refuseSortMethod(self: *Checker, node: ast.Node, spelling: SortSpelling) Error!void {
            return impl.refuseSortMethod(Checker, self, node, spelling);
        }
        /// Recognize `unwrap_or(value, default)`: the prelude call shape of the
        /// intrinsic Option method, with the receiver as the first argument.
        pub fn preludeOptionFunction(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.preludeOptionFunction(Checker, self, call);
        }
        /// Check `unwrap_or(value, default)` by the receiver method's own rule.
        pub fn checkPreludeOptionFunction(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
            return impl.checkPreludeOptionFunction(Checker, self, node, call, out);
        }
        /// Check a call to a recognized standard-module home as the operation its
        /// retired method spelling lowered to; null when the call is not a home.
        pub fn checkRecognizedHome(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!?typed.Node {
            return impl.checkRecognizedHome(Checker, self, node, temporaries);
        }
        /// Check a call of a supplied home (`builtin func`, W10) whose row is already known, with its arguments in
        /// parameter order, as the operation the row names; null when the receiver is not the row's.
        pub fn checkSuppliedHome(self: *Checker, node: ast.Node, retirement: retired_methods.Retirement, arguments: []const ast.NodeId, temporaries: []const typed.Type) Error!?typed.Node {
            return impl.checkSuppliedHome(Checker, self, node, retirement, arguments, temporaries);
        }
        /// Hint a recognized home's operands before the call's arguments are
        /// checked, so an empty list literal takes its element type.
        pub fn hintRecognizedHome(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
            return impl.hintRecognizedHome(Checker, self, call);
        }
        /// Whether this call is the prelude spelling `copy(value)`: unshadowed,
        /// no receiver and exactly one argument.
        pub fn preludeCopyFunction(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.preludeCopyFunction(Checker, self, call);
        }
        /// Check `copy(value)`: the same copy the removed method lowered to.
        pub fn checkPreludeCopy(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
            return impl.checkPreludeCopy(Checker, self, node, call, out);
        }
        /// Copy one already checked value, for a prelude dispatch that has no
        /// method call to read the receiver from.
        pub fn checkCopyValue(self: *Checker, span: source.Span, base: typed.NodeId) Error!typed.Node {
            return impl.checkCopyValue(Checker, self, span, base);
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
        if (try @import("record_calls.zig").lower(self.allocator, self.src, self.catalog, self.syntax.nodes.items, call, self.sink)) |record| {
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
            if (value_type.isFile()) return collectionSyntaxFileCall(Checker, self, node, call, owner);
            // `values.sort(key=..., reverse=...)` stays a call: its operands
            // are named, and it lowers to a keyed sort, not one operation.
            if (self.listSortOwner(call) != null) {
                try pendingListOperation(Checker, self, value_type, .sort, node.span);
                return node;
            }
            if (value_type.isAggregate() and self.catalog.records[value_type.recordIndex()].isCollection()) {
                try call_arguments.positional(call, self.sink);
                const name = self.src.text(call.name);
                const family = self.catalog.records[value_type.recordIndex()].collection.kind;
                const raw_kind = buffer_operations.methodFor(name, call.arguments.len) orelse {
                    try refuseRemovedContains(Checker, self, value_type, containsCall(Checker, self, node.span, call.name, owner, call.arguments, call.argument_names), name);
                    _ = try removed_names.reject(self.sink, call.name, name);
                    return self.sink.fail("E_LIST_METHOD", call.name, try self.unknownMethodMessage(family, value_type));
                };
                const kind = buffer_operations.forFamily(raw_kind, family);
                if (std.mem.eql(u8, name, "copy")) return refuseCopySyntax(Checker, self, node, call.owner.?);
                // Stage 2b: a spelling this stage retires names its function home
                // and carries the certain rewrite. A trusted standard-library
                // source keeps the method, whose lowering is its home's body.
                try refuseNamedRetirement(Checker, self, node, call, value_type);
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
            } else if (record_layouts.tupleRecord(self.catalog.records, value_type) != null) {
                if (!std.mem.eql(u8, self.src.text(call.name), "copy")) return self.sink.fail("E_TYPE", call.name, "a tuple has no methods, and tuples were removed; use a record with named fields");
                if (std.mem.eql(u8, self.src.text(call.name), "copy")) return refuseCopySyntax(Checker, self, node, call.owner.?);
                try call_arguments.positional(call, self.sink);
                if (call.type_arguments.len != 0 or call.arguments.len != 0) return self.sink.fail("E_ARITY", call.name, copy_arity);
                node.data = .{ .buffer_operation = .{ .kind = .copy, .owner = owner, .arguments = call.arguments } };
            }
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
/// Wrap a growable literal in the exact fixed-array constructor required by its context.
fn fixedLiteralFix(comptime Checker: type, self: *Checker, node: ast.Node, shape: typed.Array) Error {
    const element = try typed.surfaceTypeName(self.allocator, shape.element, self.catalog.records);
    const replacement = try std.fmt.allocPrint(self.allocator, "FixedArray[{s}, {d}]({s})", .{ element, shape.length, self.src.text(node.span) });
    return self.sink.failFix("E_FIXED_ARRAY_LITERAL", node.span, "an array literal creates a growable array; construct the fixed array explicitly", .{ .span = node.span, .text = replacement });
}

fn checkListLiteral(comptime Checker: type, self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    var expected = self.expected_types.get(node.span);
    if (expected) |ty_value| if (arrays.fixed(self.catalog, ty_value)) |shape|
        return fixedLiteralFix(Checker, self, node, shape);
    var element: ?typed.Type = if (expected) |ty_value| try listElement(Checker, self, ty_value, node.span) else null;
    if (inputs.len == 0 and expected == null) return self.sink.fail("E_LIST_INFERENCE", node.span, "empty list requires an expected List type");
    const values = try self.allocator.alloc(typed.NodeId, inputs.len);
    for (inputs, values) |input, *value| {
        if (element) |ty_value| try self.hint(input, ty_value);
        value.* = try self.expressionWithTemporaries(input, temporaries);
        // A list literal takes its elements: an element of a new list moves out of it (F-55).
        try self.moveTemporaryElement(input, value.*);
        const actual = self.nodes.items[@backingInt(value.*)].ty;
        if (element) |ty_value| try self.require(actual, ty_value, self.syntax.nodes.items[@backingInt(input)].span) else element = actual;
    }
    if (expected == null) expected = try collections.listType(&self.catalog, element.?, node.span);
    if (!typed.storable(element.?, self.catalog.records) or typed.moveOnly(element.?, self.catalog.records))
        return self.sink.failOwnership(.{ .code = eListType, .rule = .T4 }, node.span, "list elements require storable values without owned resources");
    return (collections.Builder(Checker){ .checker = self, .span = node.span }).literal(expected.?, values);
}
/// Retained compatibility arm; the parser normalizes comprehension syntax to gathers.
fn checkComprehension(comptime Checker: type, self: *Checker, node: ast.Node, each: ast.Comprehension, temporaries: []const typed.Type) Error!typed.Node {
    _ = each;
    _ = temporaries;
    return self.sink.fail("E_COMPREHENSION_REMOVED", node.span, "comprehensions were removed; use a typed accumulator and an explicit loop");
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
    const child = try b.read(value_slot);
    // Text iteration already creates each character; collection children borrow.
    const independent = if (element.isAggregate() and (fixed != null or schema.collection.kind != .string)) copied: {
        const copy = try b.access(child, .copy, &.{}, false);
        break :copied try b.node(copy.ty, copy.data);
    } else child;
    const body = try sets.add(output, independent);
    const slots: ComprehensionSlots = .{ .owner = owner, .index = index, .limit = limit, .slot = value_slot };
    return comprehensionLoop(Checker, self, b, slots, body, .{
        .iterable = iterable,
        .output = output,
        .kind = schema.collection.kind,
        .projection = if (projected) view else null,
        .fixed = fixed,
    });
}
/// Assemble D1 iteration, its mutation check, and the produced collection.
const ComprehensionSlots = struct { owner: typed.LocalId, index: typed.LocalId, limit: typed.LocalId, slot: typed.LocalId };
const ComprehensionSource = struct {
    iterable: typed.NodeId,
    output: typed.LocalId,
    kind: ManagedKind,
    projection: ?dictionary_views.Kind = null,
    /// Set when the source is a fixed array, which is read by index.
    fixed: ?typed.Array = null,
};
fn comprehensionLoop(
    comptime Checker: type,
    self: *Checker,
    b: collections.Builder(Checker),
    slots: ComprehensionSlots,
    body: typed.StatementId,
    source_values: ComprehensionSource,
) Error!typed.Node {
    const prepared = try iteration_place.prepare(Checker, b, source_values.iterable, slots.owner, null);
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
    const output_type = self.locals.items[@backingInt(source_values.output)].ty;
    const acquire_output = try b.node(output_type, .{ .array = &.{} });
    return iteration_place.foldBlock(Checker, b, prepared, &.{
        try b.stmt(.{ .initialize = .{ .slot = slots.index, .value = try b.integer(0) } }),
        try b.stmt(.{ .initialize = .{ .slot = slots.limit, .value = if (source_values.fixed) |shape| try b.integer(@intCast(shape.length)) else try b.length(slots.owner) } }),
        try b.stmt(.{ .initialize = .{ .slot = source_values.output, .value = acquire_output } }),
        try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(slots.limit), .bool), .body = iteration, .step = step } }),
    }, try b.read(source_values.output));
}
/// One interpolated value with no format specification: the hole itself. A hole
/// takes whatever `print` can render, through the same renderer, so one value has
/// one spelling.
fn formatHole(comptime Checker: type, self: *Checker, value: typed.NodeId, span: source.Span) Error!typed.FormatHole {
    const ty_value = self.nodes.items[@backingInt(value)].ty;
    if (@import("extern_types.zig").contains(ty_value, self.catalog.records)) return @import("extern_types.zig").refuse(self.sink, span, .text);
    if (@import("collection_text.zig").partWithoutText(ty_value, self.catalog.records)) |part| {
        if (part == ty_value) return self.sink.fail(
            "E_TEXT_CONVERSION",
            span,
            "format string interpolation requires a value with a rendering; capabilities, open files and callbacks have none",
        );
        return self.sink.fail("E_TEXT_CONVERSION", span, try @import("collection_text.zig").printRefusal(self.allocator, "a format string hole", ty_value, part, self.catalog.records));
    }
    return .{ .value = value };
}
/// Check an `f"..."` literal as one node of its pieces (`PY-FSTRING-1`): literal
/// bytes as they were written, and each hole's checked value with the format
/// specification it was given. Nothing is converted to `str`, copied, listed or
/// joined here; the pieces reach Core as they are.
fn checkFormat(comptime Checker: type, self: *Checker, node: ast.Node, parts: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const str_type = self.catalog.names.get("str") orelse return error.InternalError;
    const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
    // A string of one literal part is that part's text, which the checker already
    // builds as a fresh literal, and a string of one text hole is that text: the
    // same value with the same owner, so neither makes a copy.
    if (parts.len == 1 and self.syntax.nodes.items[@backingInt(parts[0])].data == .text)
        return builder.block(&.{}, try self.expressionWithTemporaries(parts[0], temporaries));
    var pieces: std.ArrayList(typed.FormatPiece) = .empty;
    var literal: std.ArrayList(u8) = .empty;
    defer literal.deinit(self.allocator);
    for (parts) |part| {
        const syntax = self.syntax.nodes.items[@backingInt(part)];
        if (syntax.data == .text) {
            try literal.appendSlice(self.allocator, syntax.data.text);
            continue;
        }
        try flushLiteral(&pieces, &literal, self.allocator);
        const hole = if (syntax.data == .format_field)
            try self.formatField(try self.expressionWithTemporaries(syntax.data.format_field.value, temporaries), syntax.data.format_field.spec, syntax.span.start - 1)
        else
            try formatHole(Checker, self, try self.expressionWithTemporaries(part, temporaries), syntax.span);
        try pieces.append(self.allocator, .{ .hole = hole });
    }
    try flushLiteral(&pieces, &literal, self.allocator);
    if (pieces.items.len == 1) single: {
        const hole = switch (pieces.items[0]) {
            .literal => break :single,
            .hole => |value| value,
        };
        if (hole.spec != null or self.nodes.items[@backingInt(hole.value)].ty != str_type) break :single;
        return builder.block(&.{}, hole.value);
    }
    return .{ .span = node.span, .ty = str_type, .data = .{ .format = .{ .pieces = try pieces.toOwnedSlice(self.allocator) } } };
}
/// Move one run of adjacent literal bytes into the piece list as one piece.
fn flushLiteral(pieces: *std.ArrayList(typed.FormatPiece), literal: *std.ArrayList(u8), allocator: std.mem.Allocator) Error!void {
    if (literal.items.len == 0) return;
    try pieces.append(allocator, .{ .literal = try allocator.dupe(u8, literal.items) });
    literal.clearRetainingCapacity();
}
fn narrowedCollection(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
    const owner = call.owner orelse return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    if (std.mem.eql(u8, self.src.text(call.name), "copy")) return slot;
    const shape = self.narrowedOption(slot) orelse return null;
    if (!shape.element.isAggregate() or !self.catalog.records[shape.element.recordIndex()].isCollection()) return null;
    return slot;
}
fn checkNarrowedMethod(comptime Checker: type, self: *Checker, node: ast.Node, slot: typed.LocalId, temporaries: []const typed.Type) Error!typed.Node {
    const call = node.data.call;
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "collection methods do not take explicit type arguments");
    const receiver_type = if (self.narrowedOption(slot)) |shape| shape.element else self.locals.items[@backingInt(slot)].ty;
    // `.copy()` has one home: the prelude function. A scalar or record receiver
    // reaches this in-place path rather than the collection dispatch, so the
    // removed method is refused here too, with the same certain edit.
    if (std.mem.eql(u8, self.src.text(call.name), "copy")) return refuseCopyMethod(Checker, self, node, call.owner orelse node.span, receiver_type);
    // Every other retired spelling is refused here as well: a narrowed optional
    // is a collection receiver the receiver dispatch never sees, and `.append` on
    // it used to check clean.
    try refuseNamedRetirement(Checker, self, node, call, receiver_type);
    const family = if (receiver_type.isAggregate()) self.catalog.records[receiver_type.recordIndex()].collection.kind else null;
    const kind = buffer_operations.methodFor(self.src.text(call.name), call.arguments.len) orelse
        return self.sink.fail(eCollectionMethod, call.name, try self.unknownMethodMessage(family, if (receiver_type.isAggregate()) receiver_type else null));
    var value: typed.Node = .{ .span = call.owner.?, .ty = .unit, .data = .unit };
    try self.checkName(.{ .span = call.owner.?, .data = .{ .name = call.owner.? } }, call.owner.?, &value);
    const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    return checkCollectionAccess(Checker, self, node, .{ .base = base, .kind = kind, .inputs = call.arguments, .temporaries = temporaries });
}
/// The prelude spellings of the receiver methods that write through their first
/// argument: `append(mut xs, x)` and `sort(mut xs)`.
const WriterFunction = enum { append, sort };

/// Whether this call is one of the writing prelude spellings: unshadowed, no
/// receiver, and a spelling whose method form takes the receiver first.
fn writerFunction(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?WriterFunction {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    const kind: WriterFunction = if (std.mem.eql(u8, name, "append"))
        .append
    else if (std.mem.eql(u8, name, "sort"))
        .sort
    else
        return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return kind;
}

/// Check `append(mut xs, x)` or `sort(mut xs)`: the receiver is the first argument
/// and the call site marks it, because the callee writes through it. The marker is
/// this call's own, so the call never reaches the declared-callee marker check;
/// a missing or misplaced marker still carries its exact edit.
fn checkWriterFunction(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: WriterFunction) Error!typed.Node {
    const spelling = self.src.text(call.name);
    if (call.arguments.len == 0) return self.sink.fail("E_ARITY", node.span, try std.fmt.allocPrint(self.allocator, "`{s}` takes its receiver first: `{s}(mut value, …)`", .{ spelling, spelling }));
    const first = try receiver_marker.require(Checker, self, spelling, call);
    const target = self.syntax.nodes.items[@backingInt(first.data.mut_argument)];
    const assignable = switch (target.data) {
        .name, .field, .index => true,
        else => false,
    };
    if (!assignable)
        return self.sink.failOwnership(.{ .code = mutation_marker_code, .rule = .M3 }, first.span, "`mut` requires an assignable argument (a variable, field or list slot); assign it to a local first");
    // Any assignable place is a receiver: the method form needs a name, the prelude
    // call takes the projection the marker names.
    const base = try @import("sema_expressions.zig").borrowList(Checker, self, call.arguments[0], &.{});
    // `sort(mut values, key=…, reverse=…)` is the method's own keyword form, so
    // the prelude spelling reaches the same keyed sort the method lowered to.
    if (kind == .sort and call.arguments.len > 1) return self.checkPreludeListSort(node, call, base);
    const operation = switch (kind) {
        .append => buffer_operations.methodFor(spelling, call.arguments.len - 1) orelse return self.sink.fail("E_ARITY", node.span, "`append` takes one value: `append(mut values, value)`"),
        .sort => .sort,
    };
    return checkCollectionAccess(Checker, self, node, .{ .base = base, .kind = operation, .inputs = call.arguments[1..], .temporaries = &.{} });
}

/// Whether this call is the prelude spelling `unwrap_or(value, default)` of the
/// intrinsic Option method: unshadowed, no receiver and exactly two arguments.
fn preludeOptionFunction(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (call.owner != null or call.type_arguments.len != 0) return false;
    const name = self.src.text(call.name);
    if (!std.mem.eql(u8, name, "unwrap_or")) return false;
    if (self.active.contains(name) or self.functions.contains(name)) return false;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
    if (call.arguments.len != 2) return self.sink.fail("E_ARITY", call.name, "unwrap_or takes two arguments: `unwrap_or(value, default)`");
    return true;
}

/// Check `unwrap_or(value, default)`: the first argument is the receiver, and the
/// default is checked against its payload exactly as the method form checks it.
fn checkPreludeOptionFunction(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    _ = try preludeOptionFunction(Checker, self, call);
    try call_arguments.positional(call, self.sink);
    const base = try self.expression(call.arguments[0]);
    out.* = try checkOptionMethod(Checker, self, node, base, call.name, call.arguments[1..], &.{});
    try warnBareUnwrapOr(Checker, self, call);
}

/// Refuse the bare `unwrap_or(x, d)` (`E_REMOVED_SPELLING`, W13-Q1): the method `x.unwrap_or(d)` is the one
/// spelling that stays, and the prelude call already hands its first operand to the method's own check, so the rewrite
/// is the same operation. A first operand that a postfix call cannot follow is put in parentheses; one passed `own` or
/// `mut` has no method form and no edit.
fn warnBareUnwrapOr(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    if (call.arguments.len != 2) return;
    try retiring_forms.reported(self.sink, call.name);
    const first = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    const default = self.syntax.nodes.items[@backingInt(call.arguments[1])];
    const text = self.src.text(first.span);
    const code = retiring_forms.duplicate_code;
    const plain = switch (first.data) {
        .own_argument, .mut_argument => {
            const message = try retiring_forms.duplicateMessage(self.allocator, "unwrap_or(value, default)", "value.unwrap_or(default)", "the option is passed `own` or `mut`, which the method form does not take");
            return retiring_forms.append(self.sink, code, call.name, message, null);
        },
        .name, .field, .call, .method_call, .index, .slice, .text, .bytes, .list_literal, .record, .variant => true,
        else => text.len != 0 and text[0] == '(' and text[text.len - 1] == ')',
    };
    const receiver = if (plain) text else try std.fmt.allocPrint(self.allocator, "({s})", .{text});
    const head = try std.fmt.allocPrint(self.allocator, "{s}.unwrap_or(", .{receiver});
    const whole = try std.fmt.allocPrint(self.allocator, "{s}{s})", .{ head, self.src.text(default.span) });
    const message = try retiring_forms.duplicateMessage(self.allocator, "unwrap_or(value, default)", whole, null);
    const edit: diagnostic.Edit = .{ .span = .{ .start = call.name.start, .end = default.span.start }, .text = head };
    return retiring_forms.append(self.sink, code, call.name, message, .{ .edit = edit });
}

/// Whether this call is the prelude spelling `copy(value)`: unshadowed, no
/// receiver, and exactly one argument.
fn preludeCopyFunction(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (call.owner != null or call.type_arguments.len != 0) return false;
    const name = self.src.text(call.name);
    if (!std.mem.eql(u8, name, "copy")) return false;
    // `copy` is also a generic requirement name, so the catalog's builtin table
    // holds it; only a declaration or an active binding can shadow the prelude.
    if (self.active.contains(name) or self.functions.contains(name)) return false;
    if (call.arguments.len != 1) return self.sink.fail("E_ARITY", call.name, "copy takes one value: `copy(value)`");
    return true;
}

/// Check `copy(value)`: the receiver is read exactly as the removed method read
/// it, then the copy produces independent storage.
fn checkPreludeCopy(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    _ = try preludeCopyFunction(Checker, self, call);
    try call_arguments.positional(call, self.sink);
    const argument = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    // A bare collection or tuple name keeps the buffer operation the syntax
    // rewrite built for `name.copy()`, so an owned view, a pending Result list and
    // a staged tuple keep the same operation, the same obligations and the same
    // code.
    if (argument.data == .name and std.mem.eql(u8, self.src.text(argument.span), self.src.text(argument.data.name)))
        if (self.active.get(self.src.text(argument.data.name))) |slot| {
            const ty = self.locals.items[@backingInt(slot)].ty;
            if (self.narrowedOption(slot) == null and desugarsCopy(Checker, self, ty)) {
                const operation: ast.Node = .{ .span = node.span, .data = .{ .buffer_operation = .{ .kind = .copy, .owner = argument.data.name, .arguments = &.{} } } };
                return self.checkBufferOperation(operation, operation.data.buffer_operation, out);
            }
        };
    // Everything else is an expression receiver: a narrowed payload, a value that
    // is not a collection, or a receiver the source wraps in its own parentheses.
    // The removed method read each one as a value, and so does this.
    const base = try self.expression(call.arguments[0]);
    out.* = try checkCollectionAccess(Checker, self, node, .{ .base = base, .kind = .copy, .inputs = &.{}, .temporaries = &.{} });
}

/// Whether `name.copy()` desugared to a buffer operation for this receiver: a
/// managed collection, or a tuple the retired form still stages.
fn desugarsCopy(comptime Checker: type, self: *Checker, ty: typed.Type) bool {
    if (record_layouts.tupleRecord(self.catalog.records, ty) != null) return true;
    return ty.isAggregate() and self.catalog.records[ty.recordIndex()].isCollection();
}

/// Rewrite a method call on a named local file handle into its file operation.
fn collectionSyntaxFileCall(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), owner: source.Span) Error!ast.Node {
    var rewritten = node;
    try call_arguments.positional(call, self.sink);
    const kind = file_operations.method(self.src.text(call.name)) orelse
        return self.sink.fail(eFileArgument, call.name, "unknown file method; open handles support read, readline, readlines, write, flush, sync and close");
    const most: usize = @intFromBool(kind.takesArgument());
    const least: usize = @intFromBool(kind.requiresArgument());
    if (call.type_arguments.len != 0 or call.arguments.len > most or call.arguments.len < least)
        return self.fileMethodArityFailure(call.name, kind, call.arguments.len);
    rewritten.data = .{ .file_operation = .{ .kind = kind, .owner = owner, .argument = if (call.arguments.len == 0) null else call.arguments[0] } };
    return rewritten;
}

/// Refuse one named-local `.copy()` in the syntax rewrite and name the prelude.
fn refuseCopySyntax(comptime Checker: type, self: *Checker, node: ast.Node, receiver: source.Span) Error {
    refuseCopySpelling(Checker, self, node, receiver) catch |err| return err;
    return error.InternalError;
}

/// Refuse one `.copy()` spelling with the certain prelude rewrite. A file that
/// declares or binds `copy` itself would capture the prelude name the repair
/// writes, so that site stays a hand migration with its own message
/// (FIX-MIGRATION-CAPTURE-1).
fn refuseCopySpelling(comptime Checker: type, self: *Checker, node: ast.Node, receiver: source.Span) Error!void {
    _ = @sizeOf(Checker);
    if (try @import("lexer.zig").claimsName(self.allocator, self.src.bytes, "copy"))
        return self.sink.fail(copy_method.code, node.span, copy_method.claimed_message);
    const text = try copy_method.callText(self.allocator, self.src.text(receiver));
    return self.sink.failFix(copy_method.code, node.span, copy_method.message, .{ .span = node.span, .text = text });
}

/// The retirement key of a checked receiver (F-b): its managed collection family
/// and its shape. A set keeps the dictionary family with the set shape, and the
/// mutable `byte_buffer` keeps the byte family with the buffer shape, so neither
/// matches a plain collection's rows.
const ReceiverKey = struct {
    /// The collection family the receiver is.
    family: ManagedKind,
    /// The receiver's shape within that family.
    shape: retired_methods.Shape,
};

/// The retirement key of a receiver type, or null when it is not a collection.
fn receiverKey(comptime Checker: type, self: *Checker, ty: typed.Type) ?ReceiverKey {
    _ = @sizeOf(Checker);
    if (!ty.isAggregate()) return null;
    const record = self.catalog.records[ty.recordIndex()];
    if (!record.isCollection()) return null;
    const shape: retired_methods.Shape = if (typed.isSet(record)) .set else if (isMutableBytes(record)) .buffer else .collection;
    return .{ .family = record.collection.kind, .shape = shape };
}

/// Whether a receiver type answers the retirement row `retirement` (F-b): the
/// same family and the same shape, or a `byte_buffer` given to a `bytes` read
/// (W13-Q5), which lends its octets to the operation its own method runs.
fn homeReceiver(comptime Checker: type, self: *Checker, ty: typed.Type, retirement: retired_methods.Retirement) bool {
    const key = receiverKey(Checker, self, ty) orelse return false;
    if (key.family != retirement.family) return false;
    return key.shape == retirement.shape or (key.shape == .buffer and retired_methods.lendsBuffer(retirement));
}

/// The embedded standard module an `alias.function` qualifier names, when the
/// qualifier is one of the writing module's imports, or null otherwise. A name
/// the writing module imports resolves through the project, so an alias works as
/// well as the module's own name, and the use is recorded for `W_UNUSED_IMPORT`.
fn recognizedHomeModule(comptime Checker: type, self: *Checker, at: source.Span, qualifier: []const u8) Error!?[]const u8 {
    _ = @sizeOf(Checker);
    const names = self.catalog.module_names orelse return null;
    const target = names.index.project.names.get(qualifier) orelse return null;
    const module = names.index.project.modules.items[target].name;
    // The embedded module's path is its name with the extension the loader uses.
    const path = try std.fmt.allocPrint(self.allocator, "{s}.selka", .{module});
    if (@import("standard_library.zig").source(path) == null) return null;
    if (!try names.importsModule(at, module)) return null;
    return module;
}

/// One call a recognized home answered, as the site's spelling resolves it: the
/// row, the operation kind and the operand positions the method's own call had.
const HomeCall = struct {
    /// The retirement row the qualified spelling names.
    retirement: retired_methods.Retirement,
    /// The operation the retired spelling lowered to.
    kind: BufferKind,
    /// Which argument is the receiver.
    receiver_at: usize,
    /// The method's own operands, receiver excluded.
    inputs: []const ast.NodeId,
    /// Every argument in parameter order, the receiver included.
    arguments: []const ast.NodeId,
};

/// The home a module-qualified call names, or null when the call is not one. The
/// qualifier resolves through the project, the module must be one of the embedded
/// standard sources, and the function must be a row whose argument count matches.
fn recognizedHomeCall(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?HomeCall {
    // A module-qualified call keeps its whole dotted name in `name` and has no
    // owner; a method call carries its receiver in `owner`.
    const name = self.src.text(call.name);
    var qualifier: []const u8 = name;
    var function: []const u8 = name;
    if (call.owner) |owner| {
        qualifier = self.src.text(owner);
    } else {
        const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
        if (dot == 0 or dot + 1 == name.len) return null;
        qualifier = name[0..dot];
        function = name[dot + 1 ..];
    }
    if (self.active.contains(qualifier)) return null;
    const module = try recognizedHomeModule(Checker, self, call.name, qualifier) orelse return null;
    const retirement = retired_methods.home(module, function, call.arguments.len) orelse return null;
    // A home that answers an option rather than the method's `-1` is a real
    // function, not a lowering of the operation: the option is the function's
    // own checked answer (F57), so its call resolves through the module.
    if (retirement.home.absence == .option) return null;
    if (call.type_arguments.len != 0 or call.argument_names.len != 0) return null;
    return homeCallFor(Checker, self, retirement, call.arguments);
}

/// The home call a known row makes of `arguments`, given in the function's parameter order.
fn homeCallFor(comptime Checker: type, self: *Checker, retirement: retired_methods.Retirement, arguments: []const ast.NodeId) Error!?HomeCall {
    if (arguments.len == 0) return null;
    const raw = buffer_operations.methodFor(retirement.method, retirement.arguments) orelse return null;
    // `bytes.join(parts, separator)` writes the method's receiver last; every
    // other home writes it first, so the other operands are the inputs.
    const receiver_at = if (retirement.home.arguments_first) arguments.len - 1 else 0;
    const inputs = try self.allocator.alloc(ast.NodeId, arguments.len - 1);
    var slot: usize = 0;
    for (arguments, 0..) |id, index| {
        if (index == receiver_at) continue;
        inputs[slot] = id;
        slot += 1;
    }
    return .{ .retirement = retirement, .kind = buffer_operations.forFamily(raw, retirement.family), .receiver_at = receiver_at, .inputs = inputs, .arguments = arguments };
}

/// Check a call to a recognized standard-module home as the operation its retired
/// method spelling lowered to: the first operand is the receiver, the rest are the
/// operation's own. A bare collection name takes the desugared buffer operation
/// (the shape `name.method(...)` built), and any other expression takes the
/// access path, so the split cursor, prefix and span lowerings and every release
/// pass see exactly the method's shape.
fn checkRecognizedHome(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!?typed.Node {
    const home = try recognizedHomeCall(Checker, self, node.data.call) orelse return null;
    return checkHome(Checker, self, node, home, temporaries);
}

/// Check a supplied home whose row the caller resolved (W10): an alias, a re-export, keyword arguments or the body of
/// the `builtin func` itself, with `arguments` in parameter order.
fn checkSuppliedHome(comptime Checker: type, self: *Checker, node: ast.Node, retirement: retired_methods.Retirement, arguments: []const ast.NodeId, temporaries: []const typed.Type) Error!?typed.Node {
    const home = try homeCallFor(Checker, self, retirement, arguments) orelse return null;
    return checkHome(Checker, self, node, home, temporaries);
}

/// Check one home call as the operation its row names.
fn checkHome(comptime Checker: type, self: *Checker, node: ast.Node, home: HomeCall, temporaries: []const typed.Type) Error!?typed.Node {
    const retirement = home.retirement;
    const kind = home.kind;
    const receiver_at = home.receiver_at;
    const inputs = home.inputs;
    const receiver = self.syntax.nodes.items[@backingInt(home.arguments[receiver_at])];
    // A writing home takes its receiver with the call-site `mut` marker, as the
    // prelude writers do: the marker is what says the callee writes that place.
    if (retirement.home.writer) try requireWriterMarker(Checker, self, receiver, retirement);
    // The marker is transparent here: the place it names is the one the retired
    // method's own receiver named, so both spellings lower from the same site.
    const place = if (receiver.data == .mut_argument) self.syntax.nodes.items[@backingInt(receiver.data.mut_argument)] else receiver;
    const named = place.data == .name and std.mem.eql(u8, self.src.text(place.span), self.src.text(place.data.name));
    if (named) if (self.active.get(self.src.text(place.data.name))) |active| {
        const ty = self.locals.items[@backingInt(active)].ty;
        if (homeReceiver(Checker, self, ty, retirement)) {
            // The operands are checked in source order, as the desugared method's
            // own call checked them, and the receiver's element type hints each
            // operand the writable method hints (`insert(mut rows, 0, [])`).
            try hintHomeOperands(Checker, self, kind, ty, inputs);
            for (inputs) |id| _ = try self.expression(id);
            try refuseSetUpdateSource(Checker, self, retirement, inputs);
            const operation: ast.Node = .{ .span = node.span, .data = .{ .buffer_operation = .{ .kind = kind, .owner = place.data.name, .arguments = inputs } } };
            var out: typed.Node = .{ .span = node.span, .ty = .unit, .data = .unit };
            try self.checkBufferOperation(operation, operation.data.buffer_operation, &out);
            // A home whose method always answered `true` answers nothing (wave 2, lane B).
            if (retirement.answer == .nothing) {
                const answered = try nothingAnswer(Checker, self, out);
                return answered;
            }
            return out;
        }
    };
    // Any other receiver is an expression: check it first so the family decides.
    const base = try self.expressionWithTemporaries(home.arguments[receiver_at], temporaries);
    const receiver_type = self.nodes.items[@backingInt(base)].ty;
    if (!homeReceiver(Checker, self, receiver_type, retirement)) return null;
    // The checked receiver's element type hints the operands exactly as the
    // writable method hinted them (`insert(mut rows[0], 0, [])`).
    try hintHomeOperands(Checker, self, kind, receiver_type, inputs);
    try refuseSetUpdateSource(Checker, self, retirement, inputs);
    const checked = try checkListAccess(Checker, self, node, .{ .base = home.arguments[receiver_at], .kind = kind, .inputs = inputs }, temporaries);
    if (retirement.answer == .nothing) {
        const answered = try nothingAnswer(Checker, self, checked);
        return answered;
    }
    return checked;
}

/// Refuse a `sets.update` whose source is neither a set nor a list (W13): the function adds the elements of another
/// set or of a list of the element type. The method `s.update(x)` also collects a text's characters or a dictionary's
/// keys, and keeps doing so; the function says what it takes, so `sets.update(mut s, "abc")` is not three letters.
fn refuseSetUpdateSource(comptime Checker: type, self: *Checker, retirement: retired_methods.Retirement, inputs: []const ast.NodeId) Error!void {
    if (retirement.shape != .set or !std.mem.eql(u8, retirement.method, "update") or inputs.len != 1) return;
    const checked = try self.expression(inputs[0]);
    const ty = self.nodes.items[@backingInt(checked)].ty;
    if (ty.isAggregate()) {
        const record = self.catalog.records[ty.recordIndex()];
        if (typed.isSet(record) or (record.isCollection() and record.collection.kind == .list)) return;
    }
    const span = self.syntax.nodes.items[@backingInt(inputs[0])].span;
    return self.sink.fail("E_TYPE", span, "`sets.update` adds the elements of another set or of a list of the element type; collect any other values into a list or a set first");
}

/// The checked answer of a home whose method always answered `true` (wave 2, lane B):
/// the operation runs as the one statement of a block whose value is `unit`. A value
/// use is therefore a `Unit` as a unit call's is, never the method's bool, and the
/// statement form needs no `_ =`. The lowering of the operation is the method's own.
fn nothingAnswer(comptime Checker: type, self: *Checker, operation: typed.Node) Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = self, .span = operation.span };
    const operated = try b.node(operation.ty, operation.data);
    const discard = try b.stmt(.{ .discard = operated });
    return b.block(&.{discard}, try b.node(.unit, .unit));
}

/// Hint a recognized home's operands before they are checked, the way the retired
/// method's own operands were hinted: a bare `[]` takes the receiver's element
/// type. The queue asks this for every call, so a non-home returns at once.
pub fn hintRecognizedHome(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    const home = try recognizedHomeCall(Checker, self, call) orelse return;
    // Only a list or dictionary home infers anything from its receiver: a text
    // home's operands are text, which a literal spells by itself, so its receiver
    // stays lazily checked and its diagnostics keep their order. A `bytes` read
    // given a named `byte_buffer` hints its operands as the buffer's method does (W13-Q5).
    const byte_home = home.retirement.family == .bytes and retired_methods.lendsBuffer(home.retirement);
    if (home.retirement.family != .list and home.retirement.family != .dictionary and !byte_home) return;
    const receiver_id = call.arguments[home.receiver_at];
    const receiver = self.syntax.nodes.items[@backingInt(receiver_id)];
    const place = if (receiver.data == .mut_argument) self.syntax.nodes.items[@backingInt(receiver.data.mut_argument)] else receiver;
    const named = place.data == .name and std.mem.eql(u8, self.src.text(place.span), self.src.text(place.data.name));
    // A `bytes` read checks a field, element, slice or call receiver here, to learn whether it is a buffer, as the
    // method's own hints learn it (a buffer's slice is a buffer, W13-S3 after FR25; `make().find(b",")` became
    // `bytes.find(make(), b",")` when W13-S5 refused the method); any other receiver expression stays lazily checked.
    const reachable = named or place.data == .field or place.data == .index or place.data == .slice or place.data == .call or place.data == .method_call;
    if (byte_home and !reachable) return;
    // A named receiver answers from its binding before anything is checked; any
    // other receiver (a field or element path) is checked here, which the queue's
    // own entry for it then reuses.
    const ty = if (named) named_ty: {
        const slot = self.active.get(self.src.text(place.data.name)) orelse return;
        break :named_ty self.locals.items[@backingInt(slot)].ty;
    } else checked_ty: {
        const base = try self.expression(receiver_id);
        break :checked_ty self.nodes.items[@backingInt(base)].ty;
    };
    if (!homeReceiver(Checker, self, ty, home.retirement)) return;
    try hintHomeOperands(Checker, self, home.kind, ty, home.inputs);
}

/// Hint a recognized home's operands from the receiver's own type, so a bare `[]`
/// or an untyped literal takes the element type the method spelling gave it.
fn hintHomeOperands(comptime Checker: type, self: *Checker, kind: BufferKind, receiver: typed.Type, inputs: []const ast.NodeId) Error!void {
    if (!receiver.isAggregate() or !self.catalog.records[receiver.recordIndex()].isCollection()) return;
    if (isMutableBytes(self.catalog.records[receiver.recordIndex()])) {
        if (!buffer_operations.byteBuffer(kind)) return hintLentBufferHome(Checker, self, kind, receiver, inputs);
        return hintByteBufferHome(Checker, self, kind, receiver, inputs);
    }
    // A set's operands are hinted as its method hints them (SET-1), not as a mapping's.
    if (typed.isSet(self.catalog.records[receiver.recordIndex()])) {
        for (inputs) |input| try self.hintSetOperand(input, receiver, kind);
        return;
    }
    if (self.catalog.records[receiver.recordIndex()].collection.kind == .dictionary) return hintDictionaryHome(Checker, self, kind, receiver, inputs);
    const element = self.catalog.records[receiver.recordIndex()].shape.buffer orelse return;
    for (inputs, 0..) |id, index| switch (kind) {
        .extend => try self.hint(id, receiver),
        .insert, .exchange => try self.hint(id, if (index == 0) .i64 else element),
        .remove, .index_of => try self.hint(id, element),
        else => {},
    };
}

/// Hint a byte-buffer home's operands with the expected type the method's own
/// operand takes (`checkManagedAccess`), so `buffers.append_utf8(mut b, b"x")`
/// checks like `b.append_utf8(b"x")`: a recognized call is not checked as a
/// declared function's call, and its operands must not be looser than the method's.
fn hintByteBufferHome(comptime Checker: type, self: *Checker, kind: BufferKind, receiver: typed.Type, inputs: []const ast.NodeId) Error!void {
    for (inputs, 0..) |input, index| {
        const integer = byteBufferInteger(kind, index);
        const span = self.syntax.nodes.items[@backingInt(input)].span;
        const expected: typed.Type = if (integer) .i64 else if ((kind == .buffer_append or kind == .buffer_append_range) and index == 0)
            try collections.preludeType(&self.catalog, "bytes", span)
        else if (kind == .buffer_append_utf8)
            self.catalog.names.get("str") orelse return error.InternalError
        else if (kind == .buffer_append_float)
            self.catalog.names.get("float") orelse return error.InternalError
        else
            receiver;
        if (kind != .buffer_append_array or integer) try hintTextMethodArgument(Checker, self, input, expected, kind);
    }
}

// twin-drift-ok: the method's own hints for a byte receiver (`hintBufferArguments` in `sema_expressions.zig`).
/// Hint a `bytes` read given a `byte_buffer` (W13-Q5) as the buffer's own method hints its operands, so
/// `bytes.find(buf, b",")` takes the literal as `buf.find(b",")` does: a lone sequence operand and `find_any`'s octets
/// take the receiver's type. Nothing else is hinted, as the method hints nothing else.
fn hintLentBufferHome(comptime Checker: type, self: *Checker, kind: BufferKind, receiver: typed.Type, inputs: []const ast.NodeId) Error!void {
    if ((kind == .find_any and inputs.len == 2) or (kind == .find_any_range and inputs.len == 3)) {
        try self.hint(inputs[0], receiver);
        for (inputs[1..]) |bound| try self.hint(bound, .i64);
        return;
    }
    // `rfind`, `index` (`text_index`) and `rindex` take their needle from the buffer as `find` does (W13-S3: `bytes.rfind(buf, b"d")`
    // was refused while `buf.rfind(b"d")` checked). The bounded forms and the character-set trims take theirs too:
    // the method on a buffer reached by an element, a slice or a call took a `bytes` literal there, and its rewrite
    // must check (W13-S5's grid); on a named buffer the method wanted a buffer operand, which the hint gives.
    const sequence = switch (kind) {
        .split, .starts_with, .ends_with, .find, .rfind, .text_index, .rindex, .count, .replace => true,
        .strip_chars, .lstrip_chars, .rstrip_chars => true,
        .find_start, .find_range, .rfind_start, .rfind_range, .text_index_start, .text_index_range => true,
        .rindex_start, .rindex_range, .count_start, .count_range => true,
        .starts_with_start, .starts_with_range, .ends_with_start, .ends_with_range => true,
        else => false,
    };
    if (sequence and inputs.len >= 1) try hintTextMethodArgument(Checker, self, inputs[0], receiver, kind);
}

/// Hint a dictionary home's operands exactly as the method's buffer operation is
/// hinted (`hintBufferArguments` in `sema_expressions.zig`): `update`'s other
/// mapping takes the receiver's type, and any other operand takes the key and then
/// the value. A recognized call and its method spelling then check the same way.
fn hintDictionaryHome(comptime Checker: type, self: *Checker, kind: BufferKind, receiver: typed.Type, inputs: []const ast.NodeId) Error!void {
    const schema = self.catalog.records[receiver.recordIndex()];
    if (kind == .update and inputs.len == 1) return self.hint(inputs[0], receiver);
    if (inputs.len > 0) try self.hint(inputs[0], schema.collection.key.?);
    if (inputs.len == 2) try self.hint(inputs[1], schema.shape.buffer.?);
}

/// Require the call-site `mut` marker on a writing home's receiver, with the same
/// certain edit the declared `mut` parameters carry: the callee writes the place.
fn requireWriterMarker(comptime Checker: type, self: *Checker, receiver: ast.Node, retirement: retired_methods.Retirement) Error!void {
    _ = @sizeOf(Checker);
    if (receiver.data == .mut_argument) return;
    const text = self.src.text(receiver.span);
    const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes `{s}`; write `mut {s}`", .{ retirement.home.function, text, text });
    const insert: source.Span = .{ .start = receiver.span.start, .end = receiver.span.start };
    return self.sink.failOwnershipFix(.{ .code = mutation_marker_code, .rule = .M3 }, receiver.span, message, .{ .span = insert, .text = "mut " });
}

/// Whether the checked site is written in one of the compiler's own
/// standard-library sources, which may acquire a network resource from its raw
/// request. A merged project source maps the site back to its module.
fn trustedStdlib(comptime Checker: type, self: *Checker, span: source.Span) bool {
    _ = @sizeOf(Checker);
    const library = @import("standard_library.zig");
    if (self.src.trusted_intrinsics) return true;
    if (library.trusted(self.src.path, self.src.bytes, false)) return true;
    const original = self.src.originalSpan(span) catch return false;
    const unit = self.src.origins[original.input].original;
    return library.trusted(unit.path, unit.bytes, unit.trusted_intrinsics);
}

/// The retirement a spelling names for a checked receiver, or null when the
/// receiver keeps its methods: a mutable octet buffer answers the buffer
/// vocabulary, never the immutable byte string module's functions (F54), and a
/// set keeps its own vocabulary (SET-1).
fn retiredFor(comptime Checker: type, self: *Checker, receiver: typed.Type, name: []const u8, arguments: usize) ?retired_methods.Retirement {
    const key = receiverKey(Checker, self, receiver) orelse return null;
    return retired_methods.findShaped(name, key.family, key.shape, arguments);
}

/// Refuse one retired spelling on a named collection receiver. A mutable octet
/// buffer answers the buffer vocabulary, never the immutable byte string
/// module's functions, so it keeps its methods (F54).
fn refuseNamedRetirement(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: typed.Type) Error!void {
    const key = receiverKey(Checker, self, receiver) orelse return;
    return refuseRetiredSyntax(Checker, self, node, call, call.owner.?, key);
}

/// Refuse one retired spelling reached through the named-receiver rewrite, where
/// the call site keeps the receiver's own span.
fn refuseRetiredSyntax(
    comptime Checker: type,
    self: *Checker,
    node: ast.Node,
    call: @FieldType(@FieldType(ast.Node, "data"), "call"),
    receiver: source.Span,
    key: ReceiverKey,
) Error!void {
    const written: RetiredOperands = .{ .name = call.name, .arguments = call.arguments, .names = call.argument_names };
    // A spelling W13 removed is refused with its rewrite, and the check goes on past it (W13, slices 2 and 5).
    const found = retired_methods.findShaped(self.src.text(call.name), key.family, key.shape, call.arguments.len) orelse
        return warnMethodForm(Checker, self, node, written, receiver, key);
    const retirement = retired_methods.forArgument(found, call.arguments.len != 1 or !lentArgument(Checker, self, call.arguments[0]));
    return refuseRetiredMethod(Checker, self, node, written, receiver, retirement);
}

/// Refuse one method spelling W13 removed (`E_METHOD_REMOVED`) with its rewrite: the home called with the receiver's
/// and every operand's own text, and the home module's import when the file lacks it. The checker goes on checking the
/// method as before, so one check reports every site of a function, which fails when its body is done. A rewrite that
/// is not certain keeps the refusal and names why it has no edit: a prelude home this unit claims (F48's rule), a join whose two operands are both evaluated work (they change
/// places), a search whose `int?` answer is not compared with a literal (F57's table), and a module home whose import
/// would hide a name the file already binds.
fn warnMethodForm(comptime Checker: type, self: *Checker, node: ast.Node, written: RetiredOperands, receiver: source.Span, key: ReceiverKey) Error!void {
    const row = retiring_forms.methodForm(self.src.text(written.name), key.family, key.shape, written.arguments.len) orelse return;
    try retiring_forms.reported(self.sink, node.span);
    const arguments = try self.allocator.alloc([]const u8, written.arguments.len);
    for (written.arguments, arguments) |id, *slot| slot.* = self.src.text(self.syntax.nodes.items[@backingInt(id)].span);
    const names = try self.allocator.alloc(?[]const u8, written.names.len);
    for (written.names, names) |name, *slot| slot.* = if (name) |span| self.src.text(span) else null;
    const text = try retired_methods.callText(self.allocator, row, self.src.text(receiver), arguments, names);
    const code = retiring_forms.method_code;
    if (row.home.module == null and try homeClaimed(Checker, self, written.name)) {
        const why = try std.fmt.allocPrint(self.allocator, "this unit declares or imports `{s}`, so the call is written by hand", .{row.home.function});
        return retiring_forms.append(self.sink, code, node.span, try retiring_forms.methodMessage(self.allocator, row, text, why), null);
    }
    const reordered = row.home.arguments_first and arguments.len == 1;
    const pure = retiring_forms.pureText(self.src.text(receiver)) or (arguments.len != 0 and retiring_forms.pureText(arguments[0]));
    if (reordered and !pure) {
        const why = "both operands are evaluated work and the function takes them in the other order, so the call is written by hand";
        return retiring_forms.append(self.sink, code, node.span, try retiring_forms.methodMessage(self.allocator, row, text, why), null);
    }
    var span = node.span;
    var replacement = text;
    if (row.home.absence == .option) {
        const why = "its result is not compared with a literal, so the use of the `int?` answer is written by hand";
        const comparison = retired_methods.comparisonAround(self.src.bytes, node.span) orelse
            return retiring_forms.append(self.sink, code, node.span, try retiring_forms.methodMessage(self.allocator, row, text, why), null);
        replacement = try retired_methods.absenceRepair(self.allocator, comparison, text) orelse
            return retiring_forms.append(self.sink, code, node.span, try retiring_forms.methodMessage(self.allocator, row, text, why), null);
        span = comparison.span;
    }
    var more: []const diagnostic.Edit = &.{};
    if (row.home.module) |module| if (try moduleImportEdit(Checker, self, node.span, module)) |imported| {
        if (retiring_forms.fileNames(self.src, node.span, module)) {
            const why = try std.fmt.allocPrint(self.allocator, "this file binds the name `{s}`, which the import the call needs would hide", .{module});
            return retiring_forms.append(self.sink, code, node.span, try retiring_forms.methodMessage(self.allocator, row, text, why), null);
        }
        more = try self.allocator.dupe(diagnostic.Edit, &.{imported});
    };
    const message = try retiring_forms.methodMessage(self.allocator, row, text, null);
    return retiring_forms.append(self.sink, code, span, message, .{ .edit = .{ .span = span, .text = replacement }, .more = more });
}

/// `warnMethodForm` for a receiver the checker typed as an expression (a call result, a field, a module constant).
fn warnMethodFormOn(comptime Checker: type, self: *Checker, node: ast.Node, written: RetiredOperands, receiver: source.Span, receiver_type: typed.Type) Error!void {
    const key = receiverKey(Checker, self, receiver_type) orelse return;
    return warnMethodForm(Checker, self, node, written, receiver, key);
}

/// Whether a retired method's argument is a value the caller only lends (F-2): a parameter, a loop or pattern binding,
/// or a field or element read. `sets.add` takes its value `own`, which such a value cannot give, so its set's `add`
/// becomes `sets.include`; a literal, a call's result or an owned local can be given and keeps `sets.add`.
fn lentArgument(comptime Checker: type, self: *Checker, argument: ast.NodeId) bool {
    return switch (self.syntax.nodes.items[@backingInt(argument)].data) {
        .field, .index => true,
        .name => |span| if (self.active.get(self.src.text(span))) |slot| switch (self.locals.items[@backingInt(slot)].origin) {
            .parameter, .iteration, .pattern, .view => true,
            else => false,
        } else false,
        else => false,
    };
}

/// The operands one retired call writes, keyword names included, as the refusal
/// rebuilds them in the replacement call.
const RetiredOperands = struct {
    /// The spelling's own span, for the capture test a prelude home needs.
    name: source.Span,
    arguments: []const ast.NodeId,
    names: []const ?source.Span,
};

/// Refuse one retired method spelling with the certain `home(receiver, operands)`
/// rewrite, keeping the receiver's and every operand's own source text. A search
/// whose home answers an option instead of `-1` is repaired by F57's table: the
/// comparison it is written in becomes `is None`, `is not None` or `Some(N)`.
/// A bare use, a chain or an unlisted comparison has no certain repair, so the
/// refusal names the convention and the site is migrated by hand.
fn refuseRetiredMethod(
    comptime Checker: type,
    self: *Checker,
    node: ast.Node,
    written: RetiredOperands,
    receiver: source.Span,
    retirement: retired_methods.Retirement,
) Error!void {
    _ = @sizeOf(Checker);
    const arguments = try self.allocator.alloc([]const u8, written.arguments.len);
    for (written.arguments, arguments) |id, *slot| slot.* = self.src.text(self.syntax.nodes.items[@backingInt(id)].span);
    // A keyword operand keeps its name: `values.sort(reverse=True)` becomes
    // `sort(mut values, reverse=True)`, the prelude's own keyword form.
    const names = try self.allocator.alloc(?[]const u8, written.names.len);
    for (written.names, names[0..]) |name, *slot| slot.* = if (name) |span| self.src.text(span) else null;
    // A prelude home whose name the unit already claims cannot be written here:
    // the repair would resolve to the unit's own declaration, so the refusal
    // reports the capture and the site is migrated by hand (F48's rule).
    if (retirement.home.module == null and try homeClaimed(Checker, self, written.name))
        return self.sink.fail(retired_methods.code, node.span, try capturedMessage(self.allocator, retirement));
    const text = try retired_methods.callText(self.allocator, retirement, self.src.text(receiver), arguments, names);
    const message = try retired_methods.message(self.allocator, retirement);
    var span = node.span;
    var replacement = text;
    if (retirement.home.absence == .option) {
        const comparison = retired_methods.comparisonAround(self.src.bytes, node.span) orelse
            return self.sink.fail(retired_methods.code, node.span, message);
        replacement = try retired_methods.absenceRepair(self.allocator, comparison, text) orelse
            return self.sink.fail(retired_methods.code, node.span, message);
        span = comparison.span;
    } else if (retirement.answer == .nothing) {
        // A statement form drops its `_ =` discard with the call, as the stream rule does; a value
        // use has no statement to rewrite, so it has no certain repair (wave 2, lane B).
        span = retired_methods.statementSpan(self.src.bytes, node.span) orelse
            return self.sink.fail(retired_methods.code, node.span, try retired_methods.nothingMessage(self.allocator, retirement));
    }
    const edit: diagnostic.Edit = .{ .span = span, .text = replacement };
    // A module home also needs its import in this unit; `import_fix` owns the
    // canonical placement, so the repair reaches a clean check in one round.
    var more: []const diagnostic.Edit = &.{};
    if (retirement.home.module) |module| {
        if (try moduleImportEdit(Checker, self, node.span, module)) |imported|
            more = try self.allocator.dupe(diagnostic.Edit, &.{imported});
    }
    try self.sink.appendFix(.{ .code = retired_methods.code, .span = span, .message = message }, edit);
    self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = more;
    return error.SourceError;
}

/// One list sort spelling's operands and receiver, as the refusal reads them.
pub const SortSpelling = struct {
    name: source.Span,
    arguments: []const ast.NodeId,
    names: []const ?source.Span,
    receiver: source.Span,
};

/// Refuse a keyworded list sort onto the prelude spelling. The named list sort
/// is checked through its own queued path rather than the collection-method
/// dispatch, so both paths ask this before they lower it.
pub fn refuseSortMethod(comptime Checker: type, self: *Checker, node: ast.Node, spelling: SortSpelling) Error!void {
    const found = retired_methods.find("sort", .list, spelling.arguments.len) orelse return;
    return refuseRetiredMethod(Checker, self, node, .{ .name = spelling.name, .arguments = spelling.arguments, .names = spelling.names }, spelling.receiver, found);
}

/// Whether the writing unit declares or imports `name`, so a repair that writes
/// the prelude call would resolve to the unit's own declaration instead.
fn homeClaimed(comptime Checker: type, self: *Checker, name: source.Span) Error!bool {
    const text = self.src.text(name);
    if (self.active.contains(text) or self.functions.contains(text)) return true;
    if (self.catalog.module_names) |names| if (try names.topLevel(name)) return true;
    return false;
}

/// The message for a prelude home this unit already claims: the refusal stands,
/// the edit does not, because it would name the unit's own declaration.
fn capturedMessage(allocator: std.mem.Allocator, retirement: retired_methods.Retirement) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        "`{s}()` is a function now, but this unit declares or imports `{s}`; rename that or write the call by hand",
        .{ retirement.method, retirement.home.function },
    );
}

/// The repair that adds `module`'s import to the file that writes `span`, or null
/// when that file already imports it. A merged project source maps the placement
/// back to the writing module; a single unit is its own file.
fn moduleImportEdit(comptime Checker: type, self: *Checker, span: source.Span, module: []const u8) Error!?diagnostic.Edit {
    _ = @sizeOf(Checker);
    return import_fix.moduleEdit(self.allocator, self.src, span, module);
}

/// Copy one already checked value: the same lowering the removed method used.
pub fn checkCopyValue(comptime Checker: type, self: *Checker, span: source.Span, base: typed.NodeId) Error!typed.Node {
    return checkCollectionAccess(Checker, self, .{ .span = span, .data = .unit }, .{ .base = base, .kind = .copy, .inputs = &.{}, .temporaries = &.{} });
}

/// Refuse `.copy()` and name the prelude call. A resource or move-only value
/// keeps its own refusal: `copy(value)` cannot copy one either.
fn refuseCopyMethod(comptime Checker: type, self: *Checker, node: ast.Node, receiver: source.Span, owner_type: typed.Type) Error!typed.Node {
    _ = @sizeOf(Checker);
    // A capability is a scalar handle (5C) and copies like one; a file or other resource does not.
    if (owner_type.isFile() or typed.moveOnly(owner_type, self.catalog.records))
        return self.sink.fail(eCollectionMethod, node.span, "resource and move-only values cannot be copied");
    refuseCopySpelling(Checker, self, node, receiver) catch |err| return err;
    return error.InternalError;
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
    if (intrinsic != .unwrap_or) {
        // Presence has one spelling, `value is None`, so the method form names
        // its certain repair. An owned payload needs `match` instead.
        if (shape != null and self.transfers(receiver_type))
            return self.sink.fail(eOptionTest, name, "use match for an Option carrying an owned value or checked Result");
        return refusePresenceMethod(Checker, self, node, self.nodes.items[@backingInt(base)].span, intrinsic == .is_some);
    }
    if (arguments.len != 1)
        return self.sink.fail("E_ARITY", node.span, "`unwrap_or` takes exactly one argument: `unwrap_or(default)`");
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

/// Refuse `.is_none()` or `.is_some()` and name the presence test it repairs
/// to. The receiver's own text stays, so the edit is certain from the end of
/// the receiver through the closing parenthesis; a test written where a
/// comparison already binds would re-parse as a chain, so it stays a hand
/// migration.
fn refusePresenceMethod(comptime Checker: type, self: *Checker, node: ast.Node, receiver: source.Span, present: bool) Error {
    const message = option_spelling.method_message;
    if (option_spelling.adjacentComparison(self.src, node.span))
        return self.sink.fail(option_spelling.method_code, node.span, message);
    return self.sink.failFix(option_spelling.method_code, node.span, message, .{ .span = .{ .start = receiver.end, .end = node.span.end }, .text = option_spelling.testSuffix(present) });
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
/// Refuse the buffer-operation form of the removed `.borrow(start, end)`, the
/// shape a `name.method(...)` call desugars to, with the slice repair.
fn refuseBorrowOperation(comptime Checker: type, self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation)) Error {
    _ = @sizeOf(Checker);
    const message = if (operation.kind == .view) borrow_view_fix.view_message else borrow_view_fix.message;
    if (operation.arguments.len != 2) return self.sink.fail(borrow_view_fix.code, node.span, message);
    const fix = try borrow_view_fix.edit(
        self.allocator,
        self.src,
        operation.owner,
        self.syntax.nodes.items[@backingInt(operation.arguments[0])].span,
        self.syntax.nodes.items[@backingInt(operation.arguments[1])].span,
        node.span,
    );
    return self.sink.failFix(borrow_view_fix.code, node.span, message, fix);
}

/// `.borrow(start, end)` was removed with `TextView`/`ByteView` (wave 3 §5.4):
/// a slice is a view of its source, so the certain repair is the slice spelling
/// of the same range.
fn refuseBorrowView(comptime Checker: type, self: *Checker, node: ast.Node, base: typed.NodeId, inputs: []const ast.NodeId, kind: buffer_operations.Kind) Error {
    _ = @sizeOf(Checker);
    const code: []const u8 = borrow_view_fix.code;
    const message = if (kind == .view) borrow_view_fix.view_message else borrow_view_fix.message;
    if (inputs.len != 2) return self.sink.fail(code, node.span, message);
    const fix = try borrow_view_fix.edit(
        self.allocator,
        self.src,
        self.nodes.items[@backingInt(base)].span,
        self.syntax.nodes.items[@backingInt(inputs[0])].span,
        self.syntax.nodes.items[@backingInt(inputs[1])].span,
        node.span,
    );
    return self.sink.failFix(code, node.span, message, fix);
}

/// Refuse the removed `contains` method called as `name` on a receiver of `receiver_type`, with the sentence for that type
/// (`contains_removed.zig`); any other method, and a receiver that is no collection, return to be checked as usual.
fn refuseRemovedContains(comptime Checker: type, self: *Checker, receiver_type: typed.Type, site: contains_removed.Call, name: []const u8) Error!void {
    if (!std.mem.eql(u8, name, contains_removed.method)) return;
    const receiver = contains_removed.receiverOf(self.catalog.records, receiver_type) orelse return;
    return contains_removed.refuse(self.allocator, self.src, self.sink, receiver, site);
}
/// The call `receiver.contains(...)` as the removed-method refusal reads it: its span, its receiver, and the one positional
/// argument when the call has exactly that.
fn containsCall(comptime Checker: type, self: *Checker, call: source.Span, name: source.Span, receiver: source.Span, arguments: []const ast.NodeId, names: []const ?source.Span) contains_removed.Call {
    const named = names.len != 0 and names[0] != null;
    const argument: ?source.Span = if (arguments.len == 1 and !named) self.syntax.nodes.items[@backingInt(arguments[0])].span else null;
    return .{ .name = name, .call = call, .receiver = receiver, .argument = argument };
}
fn checkCollectionMethod(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const call = node.data.method_call;
    const name = self.src.text(call.name);
    if (!std.mem.eql(u8, name, contains_removed.method)) _ = try removed_names.reject(self.sink, call.name, name);
    // The receiver is checked first so an unknown method can name its type;
    // `checkListAccess` reads the same cached checked node.
    const base = try self.expressionWithTemporaries(call.base, temporaries);
    const owner_type = self.nodes.items[@backingInt(base)].ty;
    // The removed `contains` is worded for the receiver's type (FR19); a receiver with no such sentence has no methods.
    try refuseRemovedContains(Checker, self, owner_type, containsCall(Checker, self, node.span, call.name, self.syntax.nodes.items[@backingInt(call.base)].span, call.arguments, call.argument_names), name);
    if (!std.mem.eql(u8, name, "copy") and prelude.optionShape(owner_type, self.catalog.records) != null)
        return checkOptionMethod(Checker, self, node, base, call.name, call.arguments, temporaries);
    // `.copy()` has one home: the prelude function, whose call keeps the
    // receiver's own text and needs no marker. A resource or stream keeps its
    // own refusal, because `copy(value)` cannot copy one either.
    if (std.mem.eql(u8, name, "copy")) return refuseCopyMethod(Checker, self, node, self.syntax.nodes.items[@backingInt(call.base)].span, owner_type);
    // A retired spelling on an expression receiver is refused with the same
    // rewrite the named-receiver path writes; the family is the checked
    // receiver's collection kind.
    const written: RetiredOperands = .{ .name = call.name, .arguments = call.arguments, .names = call.argument_names };
    const receiver_span = self.syntax.nodes.items[@backingInt(call.base)].span;
    if (retiredFor(Checker, self, owner_type, name, call.arguments.len)) |found| {
        try refuseRetiredMethod(Checker, self, node, written, receiver_span, found);
    } else try warnMethodFormOn(Checker, self, node, written, receiver_span, owner_type);
    if (owner_type == .stream_cap) return self.checkStreamReceiverMethod(node, base, temporaries);
    switch (owner_type) {
        .filesystem_cap, .network_cap, .environment_cap, .clock_cap, .random_cap, .host_cap, .process_cap, .input_cap, .stop_cap, .registers_cap => return self.checkCapabilityReceiverMethod(node, base, temporaries),
        else => {},
    }
    // Only a list's `sort` takes named operands, and passing any operand
    // to it is the Python keyword form.
    if (std.mem.eql(u8, name, "sort") and call.arguments.len != 0) {
        try pendingListOperation(Checker, self, owner_type, .sort, node.span);
        try self.requireWritableRoot(call.base);
        return self.checkMethodListSort(node, base, temporaries);
    }
    const site: call_arguments.MethodSite = .{ .receiver = self.syntax.nodes.items[@backingInt(call.base)].span, .name = call.name, .arguments = call.arguments, .names = call.argument_names };
    if (call.argument_names.len != 0) {
        const message = if (hasNoMethods(Checker, self, owner_type) and self.callableField(owner_type, name) == null)
            try self.noMethodsMessage(owner_type, site)
        else
            "collection methods take their arguments by position; only a list's sort takes key= and reverse=";
        return self.sink.fail(call_argument_code, call.name, message);
    }
    const kind = try methodKind(Checker, self, site, owner_type);
    if (try fusedByteRange(Checker, self, node, base, kind, call.arguments.len)) |fused| return fused;
    return checkListAccess(Checker, self, node, .{ .base = call.base, .kind = kind, .inputs = call.arguments }, temporaries);
}
/// Whether a receiver of `owner_type` has no methods at all: it is neither a managed collection nor a checked `Result`, so a
/// record, an enum or a scalar reached through a field or an element is told to use the function form.
fn hasNoMethods(comptime Checker: type, self: *Checker, owner_type: typed.Type) bool {
    const managed = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
    return !managed and typed.resultShape(owner_type, self.catalog.records) == null;
}
/// The buffer operation a method name and argument count select on a receiver of
/// `owner_type`, or the unknown-method diagnostic listing what that receiver accepts. A receiver that has no methods at all
/// (a record, an enum or a scalar reached through a field or an element) is told so, with the function form, as a local is.
fn methodKind(comptime Checker: type, self: *Checker, site: call_arguments.MethodSite, owner_type: typed.Type) Error!BufferKind {
    const call_name = site.name;
    const count = site.arguments.len;
    const name = self.src.text(call_name);
    // A function value stored in a record field is not a method; name the one
    // spelling (bind it first) instead of listing the collection methods (FR-422).
    if (self.callableField(owner_type, name) != null)
        return self.sink.fail(eCollectionMethod, call_name, try self.functionFieldMessage(owner_type, name));
    return buffer_operations.methodFor(name, count) orelse {
        const managed = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
        const family: ?ManagedKind = if (managed) self.catalog.records[owner_type.recordIndex()].collection.kind else null;
        const message = if (hasNoMethods(Checker, self, owner_type)) try self.noMethodsMessage(owner_type, site) else try self.unknownMethodMessage(family, owner_type);
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
    if (!std.mem.eql(u8, self.src.text(call.name), contains_removed.method)) _ = try removed_names.reject(self.sink, call.name, self.src.text(call.name));
    const owner = call.owner.?;
    var value: typed.Node = .{ .span = owner, .ty = .unit, .data = .unit };
    try self.checkName(.{ .span = owner, .data = .{ .name = owner } }, owner, &value);
    try refuseRemovedContains(Checker, self, value.ty, containsCall(Checker, self, node.span, call.name, owner, call.arguments, call.argument_names), self.src.text(call.name));
    const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, value);
    // A module constant is a named receiver too: the retired spelling is refused
    // with the same rewrite before its kind is resolved.
    const written: RetiredOperands = .{ .name = call.name, .arguments = call.arguments, .names = call.argument_names };
    if (retiredFor(Checker, self, value.ty, self.src.text(call.name), call.arguments.len)) |found| {
        try refuseRetiredMethod(Checker, self, node, written, owner, found);
    } else try warnMethodFormOn(Checker, self, node, written, owner, value.ty);
    const kind = try methodKind(Checker, self, .{ .receiver = owner, .name = call.name, .arguments = call.arguments, .names = call.argument_names }, value.ty);
    if (try fusedByteRange(Checker, self, node, base, kind, call.arguments.len)) |fused| return fused;
    return checkCollectionAccess(Checker, self, node, .{ .base = base, .kind = kind, .inputs = call.arguments, .temporaries = temporaries });
}
fn checkCollectionSlice(comptime Checker: type, self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
    const slice = node.data.slice;
    const base = try self.expressionWithTemporaries(slice.base, temporaries);
    const input = self.nodes.items[@backingInt(base)].ty;
    if (!input.isAggregate() or !self.catalog.records[input.recordIndex()].isCollection()) return self.sink.fail(eCollectionMethod, node.span, "slicing requires a list or str");
    const schema = self.catalog.records[input.recordIndex()];
    try pendingListOperation(Checker, self, input, .slice, node.span);
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

        // V3: a stepped slice is replaced by the stride helper, for text and lists
        // alike, because a slice is a contiguous view from this wave on. The
        // lowered node comes first so a negative bound's diagnostic keeps its
        // earlier position in the list.
        const lowered = try b.sliceStep(base, start, end, step);
        const base_span = self.syntax.nodes.items[@backingInt(slice.base)].span;
        const text_receiver = schema.collection.kind == .string and text_scalar.scalarText(self, input);
        const rewrite = try std.fmt.allocPrint(self.allocator, "{s}({s}, {s}, {s}, {s})", .{
            if (text_receiver) "strings.char_stride" else "lists.stride",
            self.src.text(base_span),
            try endpointText(Checker, self, base_span, slice.start),
            try endpointText(Checker, self, base_span, slice.end),
            self.src.text(self.syntax.nodes.items[@backingInt(stride)].span),
        });
        // The diagnostic points at the step, which is the part that was removed,
        // while the repair replaces the whole expression.
        try self.sink.appendFix(.{ .code = stepped_slice_code, .span = self.syntax.nodes.items[@backingInt(stride)].span, .message = stepped_slice_message }, .{ .span = node.span, .text = rewrite });
        return lowered;
    }
    // Wave 3 phase 2: `text[start:end]` slices by byte offset, a copy whose
    // endpoints the runtime checks (`R_TEXT_BOUNDARY`). The scalar helper
    // `strings.char_slice` keeps the scalar `textSlice` lowering.
    const out = if (schema.collection.kind == .string and text_scalar.scalarText(self, input))
        try collections.bytesSlice(Checker, b, base, start, end)
    else if (schema.collection.kind == .list)
        try b.slice(base, start, end)
    else
        try b.textSlice(base, start, end);
    // A slice expression is a view of its source (`E_SLICE_ESCAPES` keeps it out
    // of owning storage); the scalar helpers copy and never set this. The
    // lowered node is wrapped in a block for its endpoints' temporaries, so the
    // mark goes on the operation the block's value names.
    markSliceView(self.nodes.items, @fromBackingInt(self.nodes.items.len - 1));
    return out;
}
/// Mark the slice operation at the bottom of `out`'s block wrappers as a view of
/// its source. One node per expression carries the mark.
fn markSliceView(nodes: []typed.Node, out: typed.NodeId) void {
    var current = @backingInt(out);
    var remaining: usize = 16;
    while (remaining != 0) : (remaining -= 1) {
        switch (nodes[current].data) {
            .block_value => |block| current = @backingInt(block.value),
            .buffer_operation => |operation| {
                // A whole-value slice (`source[:]`) lowers to the value's own
                // copy, not to a view of a range inside it, so it may be stored
                // and returned as it is.
                switch (operation.kind) {
                    .slice, .slice_bytes, .text_tail => nodes[current].view = true,
                    else => {},
                }
                return;
            },
            else => return,
        }
    }
}

/// An omitted slice endpoint is `None` in the helper call: it stays omitted, so
/// the source expression is evaluated exactly once and in the same position.
fn endpointText(comptime Checker: type, self: *Checker, base_span: source.Span, id: ?ast.NodeId) Error![]const u8 {
    const value = id orelse return "None";
    return text_scalar.argumentText(Checker, self, base_span, self.syntax.nodes.items[@backingInt(value)].span, true);
}

/// Check a list method call or element access whose receiver is still unchecked:
/// check the receiver, then the access against it.
fn checkListAccess(comptime Checker: type, self: *Checker, node: ast.Node, operation: ListAccess, temporaries: []const typed.Type) Error!typed.Node {
    if (operation.kind.mutates()) try self.requireWritableRoot(operation.base);
    const base = try @import("sema_expressions.zig").borrowList(Checker, self, operation.base, temporaries);
    return checkCollectionAccess(Checker, self, node, .{
        .base = base,
        .kind = operation.kind,
        .inputs = operation.inputs,
        .temporaries = temporaries,
        .signed_length = operation.signed_length,
    });
}
fn checkCollectionAccess(comptime Checker: type, self: *Checker, node: ast.Node, call: ListMethodCall) Error!typed.Node {
    if (call.kind == .borrow_view or call.kind == .view) return refuseBorrowView(Checker, self, node, call.base, call.inputs, call.kind);
    const base = call.base;
    var kind = call.kind;
    const inputs = call.inputs;
    const temporaries = call.temporaries;
    const owner_type = self.nodes.items[@backingInt(base)].ty;
    try pendingListOperation(Checker, self, owner_type, kind, node.span);
    const managed_owner = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
    if (kind == .copy and !managed_owner) {
        if (inputs.len != 0) return self.sink.fail("E_ARITY", node.span, copy_arity);
        try refuseLinearCopy(self.catalog.records, owner_type, node.span, self.sink);
        if (owner_type.isFile() or typed.moveOnly(owner_type, self.catalog.records))
            return self.sink.fail(eCollectionMethod, node.span, "resource and move-only values cannot be copied");
        if (!owner_type.isAggregate()) return self.nodes.items[@backingInt(base)];
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, &.{}, false);
    }
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
        .extend, .insert, .exchange, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => true,
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
        // The list takes an appended or stored element: one of a new list moves out of it (F-55).
        if (writes_element and kind != .contains) try self.moveTemporaryElement(input, argument.*);
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
        .insert, .exchange => {
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
        error.InternalError => return self.sink.fail(eCollectionMethod, node.span, try self.unsupportedMethodMessage(operation.kind, owner_type)),
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
        const integer = !dictionary and (operation.kind == .read or operation.kind == .slice or operation.kind == .view or operation.kind == .borrow_view or
            operation.kind == .parse_int_range or operation.kind == .parse_float_range or operation.kind == .scalar_count_range or widthArgument(operation.kind) or
            (operation.kind == .find_any and index == 1) or (operation.kind == .find_any_range and index > 0) or
            (buffer_operations.search(operation.kind) != null and index > 0)) or
            byteBufferInteger(operation.kind, index);
        const expected = if (integer) typed.Type.i64 else if (dictionary) map_argument: {
            break :map_argument if (index == 0) schema.collection.key.? else schema.shape.buffer.?;
        } else if ((operation.kind == .buffer_append or operation.kind == .buffer_append_range) and index == 0)
            try collections.preludeType(&self.catalog, "bytes", node.span)
        else if (operation.kind == .buffer_append_utf8)
            self.catalog.names.get("str") orelse return error.InternalError
        else if (operation.kind == .buffer_append_float)
            self.catalog.names.get("float") orelse return error.InternalError
        else if (operation.kind == .join) try collectionListType(Checker, self, owner_type, node.span) else owner_type;
        // PY-GENERATOR-1: `"".join(x for x in xs)` joins the list the loop builds.
        if (operation.kind == .join) _ = try self.consumeGenerator(input, .list);
        if (operation.kind != .buffer_append_array or integer) try self.hintTextMethodArgument(input, expected, operation.kind);
        argument.* = try self.expressionWithTemporaries(input, temporaries);
        // A dictionary stores its value: an element of a new list moves out of it (F-55).
        if (dictionary and operation.kind == .write and index == 1) try self.moveTemporaryElement(input, argument.*);
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        if (integer) {
            try self.requireInteger(actual, node.span);
        } else if (operation.kind == .buffer_append_array) {
            // The array's own length is part of its type, so any `FixedArray[u8, N]` is accepted.
            if (!typed.byteRequest(actual, self.catalog.records)) return self.sink.fail(eCollectionMethod, node.span, append_array_source);
        } else try self.requireArgument(.{ .actual = actual, .expected = expected, .span = node.span, .kind = operation.kind, .names = names });
    }
    const accessed = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
    if (dictionary and operation.kind == .write) markBorrowedKey(Checker, self, accessed, operation.inputs[0], arguments[0]);
    return accessed;
}
/// Whether a dictionary operation takes the key written at `written` (checked as `key`) by borrow: a name, a field or an
/// element of a managed type. A key written `copy(...)`, `own ...`, as a literal or as a call is a value the operation consumes.
fn borrowsKey(comptime Checker: type, self: *Checker, written: ast.NodeId, key: typed.NodeId) bool {
    switch (self.syntax.nodes.items[@backingInt(written)].data) {
        .name, .field, .index => {},
        else => return false,
    }
    return self.nodes.items[@backingInt(key)].ty.isAggregate() and keyIsPlaceRead(Checker, self, key, 0);
}
/// Mark the dictionary operation `accessed` as taking its key by borrow when the source wrote the key as a place: the table
/// then copies the key only when it is new.
fn markBorrowedKey(comptime Checker: type, self: *Checker, accessed: typed.Node, written: ast.NodeId, key: typed.NodeId) void {
    if (!borrowsKey(Checker, self, written, key) or accessed.data != .block_value) return;
    const operation = &self.nodes.items[@backingInt(accessed.data.block_value.value)];
    if (operation.data == .buffer_operation) operation.data.buffer_operation.borrowed_key = true;
}
/// Whether the checked key reads an existing place without producing a fresh value: a local, a record field or an element
/// of a list or dictionary. A character read of a `str` is fresh, and so is every call.
fn keyIsPlaceRead(comptime Checker: type, self: *Checker, id: typed.NodeId, depth: usize) bool {
    if (depth > 8) return false;
    const node = self.nodes.items[@backingInt(id)];
    if (node.own or node.view) return false;
    return switch (node.data) {
        .local, .field, .index => true,
        .block_value => |block| keyIsPlaceRead(Checker, self, block.value, depth + 1),
        .buffer_operation => |read| blk: {
            if (read.kind != .read) break :blk false;
            const owner = self.locals.items[@backingInt(read.owner)].ty;
            break :blk owner.isAggregate() and self.catalog.records[owner.recordIndex()].collection.kind != .string;
        },
        else => false,
    };
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
    const accessed = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
    if (operation.kind == .setdefault) markBorrowedKey(Checker, self, accessed, operation.inputs[0], arguments[0]);
    return accessed;
}
fn collectionListType(comptime Checker: type, self: *Checker, element: typed.Type, span: source.Span) Error!typed.Type {
    const state = self.catalog.templates.store orelse return error.InternalError;
    return nominal_catalog.instantiateLengths(&self.catalog, state.index.names.get("List").?, &.{element}, &.{}, span);
}
/// The arguments of `bytes.find_any` and of its bounded form: the byte set takes the receiver's type, `start` and `end` are integers.
fn requireFindAnyArguments(comptime Checker: type, self: *Checker, receiver: typed.Type, arguments: []const typed.NodeId, span: source.Span) Error!void {
    try self.require(self.nodes.items[@backingInt(arguments[0])].ty, receiver, span);
    for (arguments[1..]) |bound| try self.requireInteger(self.nodes.items[@backingInt(bound)].ty, span);
}
fn checkTextDictionary(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
    const local = self.locals.items[@backingInt(owner)];
    const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;

    const schema = self.catalog.records[local.ty.recordIndex()];
    const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
    for (operation.arguments, arguments) |input, *argument| argument.* = self.resolved.at(@backingInt(input)).?;
    const dictionary = schema.collection.kind == .dictionary;
    const byte_string = schema.collection.kind == .bytes;
    const output_element = if (dictionary or byte_string) element else local.ty;
    if (try checkPythonText(Checker, self, operation, owner, out, arguments)) return;
    switch (operation.kind) {
        .length => out.ty = .i64,
        .find_any, .find_any_range => {
            if (!byte_string) return self.sink.fail(eCollectionMethod, operation.owner, "find_any requires a bytes receiver and a byte set");
            try requireFindAnyArguments(Checker, self, local.ty, arguments, operation.owner);
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
        .to_list, .hex, .blake3, .sha256, .decode, .encode, .from_hex, .parse_int, .parse_float, .parse_f32 => out.ty = collections.operationType(&self.catalog, local.ty, operation.kind, operation.owner) catch |err| switch (err) {
            error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
            else => return err,
        },
        // A view shares the receiver's octets, `copy` materializes them and
        // `scalar_count` measures them.
        .copy, .scalar_count, .scalar_count_range, .parse_int_range, .parse_float_range => if (!try checkByteViewMethod(Checker, self, operation, owner, schema, arguments, out))
            return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
        .buffer_reserve, .buffer_append, .buffer_append_byte, .buffer_append_range, .buffer_append_array => try checkByteBufferMethod(Checker, self, operation, owner, arguments, out),
        .buffer_append_utf8, .buffer_append_int, .buffer_append_float => try checkByteBufferMethod(Checker, self, operation, owner, arguments, out),
        .read, .write, .get, .contains => {
            if (!dictionary and operation.kind != .read and operation.kind != .contains) return self.sink.failOwnership(.{ .code = "E_TEXT_IMMUTABLE", .rule = .T4 }, operation.owner, "str values are immutable");
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
        // A byte buffer's `buffers.clear` empties it and keeps its storage; every other collection answers the dictionary's.
        .clear => if (byte_string and isMutableBytes(schema))
            try checkByteBufferMethod(Checker, self, operation, owner, arguments, out)
        else
            return checkDictionaryBufferMethod(Checker, self, operation, owner, out),
        .items, .pop, .pop_key, .pop_default, .update, .setdefault => return checkDictionaryBufferMethod(Checker, self, operation, owner, out),
        else => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
    }
    out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
}
/// Check one byte-string method that reads the receiver's own octets rather
/// than the collection surface around them: `copy` materializes them, and
/// `scalar_count` validates and measures them. Both exist only on the
/// immutable byte string, so neither a mutable buffer nor a `str` reaches
/// them, and none of them allocates except the copy it names.
fn checkByteViewMethod(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, schema: typed.Record, arguments: []const typed.NodeId, out: *typed.Node) Error!bool {
    const owner_type = self.locals.items[@backingInt(owner)].ty;
    switch (operation.kind) {
        .copy => {
            // A dictionary shares the spelling and keeps its own shallow copy.
            if (schema.collection.kind == .dictionary) {
                try checkDictionaryBufferMethod(Checker, self, operation, owner, out);
                return true;
            }
            if (schema.collection.kind != .string and schema.collection.kind != .bytes) return self.sink.fail(eCollectionMethod, operation.owner, "copy requires text or bytes");
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
        } else if (operation.kind == .buffer_append_array and index == 0) {
            if (!typed.byteRequest(actual, self.catalog.records)) return self.sink.fail(eCollectionMethod, operation.owner, append_array_source);
        } else if ((operation.kind == .buffer_append or operation.kind == .buffer_append_range) and index == 0) {
            // An append copies octets out of any byte-kind value, so an
            // immutable `bytes` argument is accepted beside another buffer.
            if (!actual.isAggregate() or self.catalog.records[actual.recordIndex()].collection.kind != .bytes)
                return self.sink.fail(eCollectionMethod, operation.owner, "append requires a bytes or byte_buffer source");
        } else try self.require(actual, local.ty, operation.owner);
    }
    // `clear` answers nothing: it always empties the buffer.
    out.ty = if (operation.kind == .clear) .unit else .bool;
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
        argument.* = self.resolved.at(@backingInt(input)).?;
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
    const borrowed = kind == .setdefault and borrowsKey(Checker, self, operation.arguments[0], arguments[0]);
    out.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = arguments, .borrowed_key = borrowed } };
}
fn rangePositions(kind: BufferKind) bool {
    return negative_index.rangeBound(kind, 0) or negative_index.rangeBound(kind, 1);
}
/// Apply position-removal recognition after a named receiver's method is typed.
fn checkNegativeBufferPositions(comptime Checker: type, self: *Checker, out: *typed.Node) Error!void {
    if (out.data != .buffer_operation) return;
    const operation = out.data.buffer_operation;
    const owner_type = self.locals.items[@backingInt(operation.owner)].ty;
    if (!owner_type.isAggregate() or self.catalog.records[owner_type.recordIndex()].collection.kind == .dictionary) return;
    const b: collections.Builder(Checker) = .{ .checker = self, .span = out.span };
    if (rangePositions(operation.kind)) {
        out.* = try b.access(try b.read(operation.owner), operation.kind, operation.arguments, false);
        return;
    }
    if (operation.kind == .insert) {
        const arguments = try self.allocator.dupe(typed.NodeId, operation.arguments);
        arguments[0] = try b.insertionIndex(operation.owner, arguments[0]);
        out.data.buffer_operation.arguments = arguments;
    } else if (operation.kind == .read or operation.kind == .write or operation.kind == .exchange or operation.kind == .pop_at) {
        try negative_index.check(Checker, self, operation.arguments[0], false);
    }
}
/// `copy` of a `@linear` value is refused: two owners would each have to consume it (D-FFI-11).
fn refuseLinearCopy(records: []const typed.Record, ty: typed.Type, span: source.Span, sink: *diagnostic.Sink) Error!void {
    if (typed.linear(ty, records)) return @import("linear_rules.zig").refuse(sink, span, .copy);
}
fn checkBufferOperation(comptime Checker: type, self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), out: *typed.Node) Error!void {
    if (operation.kind == .borrow_view or operation.kind == .view) return refuseBorrowOperation(Checker, self, node, operation);
    const owner = try self.resolve(operation.owner);
    const local = &self.locals.items[@backingInt(owner)];
    const collection = local.ty.isAggregate() and self.catalog.records[local.ty.recordIndex()].isCollection();
    if (record_layouts.pendingList(self.catalog.records, local.ty)) {
        if (!local.ownership.transfer_available) return self.sink.failOwnershipTransfer(.{ .code = "E_RESULT_CONSUMED", .rule = .L1 }, out.span, local.declaration, local.ownership.transfer_span);
        try pendingListOperation(Checker, self, local.ty, operation.kind, out.span);
    }
    if (operation.kind == .copy and !collection) {
        if (operation.arguments.len != 0) return self.sink.fail("E_ARITY", out.span, copy_arity);
        try refuseLinearCopy(self.catalog.records, local.ty, out.span, self.sink);
        if (local.ty.isFile() or typed.moveOnly(local.ty, self.catalog.records))
            return self.sink.fail(eCollectionMethod, out.span, "resource and move-only values cannot be copied");
        local.usage.reads += 1;
        out.ty = local.ty;
        out.data = if (!local.ty.isAggregate()) .{ .local = owner } else .{ .buffer_operation = .{ .kind = .copy, .owner = owner, .arguments = &.{} } };
        return;
    }
    if (!local.ty.isAggregate() or !self.catalog.records[local.ty.recordIndex()].isCollection()) return self.sink.fail(eListType, operation.owner, needs_list);
    local.usage.reads += 1;
    if (operation.kind.mutates()) {
        if (!local.mutable) return self.sink.failOwnership(.{ .code = eImmutable, .rule = .B1 }, operation.owner, "collection update requires a writable binding");
        self.option_facts.forget(@backingInt(owner));
    }
    if (typed.isSet(self.catalog.records[local.ty.recordIndex()])) {
        if (operation.kind.mutates()) local.usage.writes += 1;
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments) |input, *argument| argument.* = self.resolved.at(@backingInt(input)).?;
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
        .extend, .insert, .exchange, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => {
            try checkListBufferMethod(Checker, self, operation, owner, out);
            return;
        },
        else => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_list),
    }
    const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
    for (operation.arguments, arguments, 0..) |input, *argument, argument_index| {
        argument.* = self.resolved.at(@backingInt(input)).?;
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
        argument.* = self.resolved.at(@backingInt(input)).?;
        const actual = self.nodes.items[@backingInt(argument.*)].ty;
        const span = self.syntax.nodes.items[@backingInt(input)].span;
        switch (kind) {
            .extend => try self.requireArgument(.{ .actual = actual, .expected = owner_type, .span = span, .kind = kind, .names = names }),
            .insert, .exchange => if (index == 0) try self.requireInteger(actual, span) else try self.requireArgument(.{ .actual = actual, .expected = element, .span = span, .kind = kind, .names = names }),
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
fn checkAcquireResource(comptime Checker: type, self: *Checker, node: ast.Node, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource"), out: *typed.Node) Error!void {
    out.ty = try self.ty(acquire.ty);
    const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceResult, acquire.ty, "acquisition requires a resource success and int error result");
    const kind = typed.resourceKind(shape.ok_type, self.catalog.records) orelse return self.sink.fail(eResourceResult, acquire.ty, "acquisition success must be a resource");
    if (shape.error_type != .i64) return self.sink.fail(eResourceResult, acquire.ty, "acquisition error must be int");
    const capability = self.resolved.at(@backingInt(acquire.capability)).?;
    const request = self.resolved.at(@backingInt(acquire.request)).?;
    // FR5a: a network request is the `network` module's internal encoding, and one built at run time reaches any
    // address the launch grants past the rule that a narrowing names a literal; the module's operations take an
    // address value instead (`connect_to`, `open_poller_at`).
    const trusted = trustedStdlib(Checker, self, node.span);
    if (kind == .network and !trusted) return self.sink.failRepaired(eInternalName, node.span, raw_network_message, rawNetworkFix(Checker, self, acquire, out.ty, .{ .request = request, .span = node.span }));
    try self.require(self.nodes.items[@backingInt(capability)].ty, if (kind == .filesystem) .filesystem_cap else .network_cap, self.syntax.nodes.items[@backingInt(acquire.capability)].span);
    const request_type = self.nodes.items[@backingInt(request)].ty;
    // The standard library builds an addressed network request as `bytes`, whose length is the address's.
    const library_bytes = trusted and kind == .network and typed.byteString(request_type, self.catalog.records);
    if (!typed.acquisitionBytes(request_type, self.catalog.records) and !library_bytes) return self.sink.fail("E_RESOURCE_REQUEST", self.syntax.nodes.items[@backingInt(acquire.request)].span, "request must be a fixed u8 array");
    out.data = .{ .acquire_resource = .{ .capability = capability, .request = request } };
}

const eInternalName = "E_INTERNAL_NAME";
const raw_network_message = sema_shared.raw_network_message;

/// The certain repair of a refused network acquisition: the standard library's own `Connected`, `Listening` or
/// `Polling` acquired with the one-octet request of `connect` (0), `listen` (1) or `open_poller` (2) is exactly that
/// call, which sends the same request. A request with an address, a request held in a name and a result type of the
/// program's own are left alone: the operation that would replace them sends other octets or answers another type.
fn rawNetworkFix(comptime Checker: type, self: *Checker, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource"), result: typed.Type, site: struct { request: typed.NodeId, span: source.Span }) ?diagnostic.Fix {
    const forms = [_]struct { ty: []const u8, tag: i128, call: []const u8 }{
        .{ .ty = "network.Connected", .tag = 0, .call = "network.connect" },
        .{ .ty = "network.Listening", .tag = 1, .call = "network.listen" },
        .{ .ty = "network.Polling", .tag = 2, .call = "network.open_poller" },
    };
    if (!result.isAggregate() or result.recordIndex() >= self.catalog.records.len) return null;
    if (!trustedStdlib(Checker, self, self.catalog.records[result.recordIndex()].declaration)) return null;
    const values = switch (self.nodes.items[@backingInt(site.request)].data) {
        .array => |items| items,
        else => return null,
    };
    if (values.len != 1) return null;
    const tag = switch (self.nodes.items[@backingInt(values[0])].data) {
        .integer => |value| value,
        else => return null,
    };
    const spelled = self.src.text(acquire.ty);
    for (forms) |form| {
        if (form.tag != tag or !std.mem.eql(u8, spelled, form.ty)) continue;
        const capability = self.src.text(self.syntax.nodes.items[@backingInt(acquire.capability)].span);
        const text = std.fmt.allocPrint(self.allocator, "{s}({s})", .{ form.call, capability }) catch return null;
        return .{ .edit = .{ .span = site.span, .text = text } };
    }
    return null;
}
fn checkAcceptResource(comptime Checker: type, self: *Checker, accept: @FieldType(@FieldType(ast.Node, "data"), "accept_resource"), out: *typed.Node) Error!void {
    out.ty = try self.ty(accept.ty);
    const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceResult, accept.ty, "acceptance requires a resource success and int error result");
    if (typed.resourceKind(shape.ok_type, self.catalog.records) != .network) return self.sink.fail(eResourceResult, accept.ty, "acceptance success must be a network resource");
    if (shape.error_type != .i64) return self.sink.fail(eResourceResult, accept.ty, "acceptance error must be int");
    const node = self.syntax.nodes.items[@backingInt(accept.value)];
    if (node.data != .name) return self.sink.fail(eResourceType, node.span, "acceptance requires a named resource binding");
    const owner = try self.resolve(node.data.name);
    const local = &self.locals.items[@backingInt(owner)];
    if (typed.resourceKind(local.ty, self.catalog.records) != .network) return self.sink.fail(eResourceType, node.span, "acceptance requires a network resource binding");
    local.usage.reads += 1;
    out.data = .{ .accept_resource = owner };
}

fn checkResourceIo(comptime Checker: type, self: *Checker, node: ast.Node, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io"), out: *typed.Node) Error!void {
    const owner = try self.resolve(io.owner);
    const local = &self.locals.items[@backingInt(owner)];
    if (typed.resourceKind(local.ty, self.catalog.records) == null) return self.sink.fail(eResourceType, io.owner, "I/O requires an owned resource binding");
    if (!local.mutable) return self.sink.failOwnership(.{ .code = eImmutable, .rule = .B1 }, io.owner, "resource I/O requires a binding it may modify");
    out.ty = try self.ty(io.ty);
    if (io.kind == .read) {
        if (typed.resourceReadShape(out.ty, self.catalog.records) == null) return self.sink.fail(eResourceIoResult, io.ty, "read result requires int error and record success with bytes: FixedArray[u8, N], length: u64, eof: bool");
    } else {
        const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceIoResult, io.ty, "write result requires u64 success and int error");
        if (shape.ok_type != .u64 or shape.error_type != .i64) return self.sink.fail(eResourceIoResult, io.ty, "write result requires u64 success and int error");
    }
    const value = if (io.value) |input| self.resolved.at(@backingInt(input)).? else null;
    if (value) |input| {
        const input_type = self.nodes.items[@backingInt(input)].ty;
        if (!typed.byteString(input_type, self.catalog.records) and !typed.byteRequest(input_type, self.catalog.records)) return self.sink.fail("E_RESOURCE_BYTES", node.span, "write input must be bytes or a fixed u8 array");
    }
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

/// Pending list elements may only be added, transferred, inspected or explicitly copied.
fn pendingListOperation(comptime Checker: type, self: *Checker, owner: typed.Type, kind: BufferKind, span: source.Span) Error!void {
    if (!record_layouts.pendingList(self.catalog.records, owner)) return;
    switch (kind) {
        .append, .pop, .pop_at, .exchange, .copy, .read, .length, .capacity, .iteration_check => {},
        else => return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, span, "this operation would implicitly discard or copy pending Results; handle elements or explicitly discard the whole list"),
    }
}
