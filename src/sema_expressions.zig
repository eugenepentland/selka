//! The expression work queue. `expressionWithTemporaries` checks an expression
//! tree without recursion: `queueExpression` pushes a node's operands with the
//! type hints their context implies, and `checkedExpression` builds the typed
//! node once its operands are checked, dispatching each syntax form to the
//! builtin, collection, call and operator modules. Lambda values, `len` and the
//! cleanup of consumed temporaries live here too. Each step is a free function
//! over the concrete checker type; `Checks` exposes the ones the rest of the
//! checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const buffer_operations = @import("buffer_operations.zig");
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const call_arguments = @import("call_arguments.zig");
const io_builtins = @import("io_builtins.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const eResultOperation = diagnostic.result_operation;
const eResultPath = diagnostic.result_path;
const eEnvironmentName = sema_shared.eEnvironmentName;
const std = @import("std");
const dictionary_views = @import("dictionary_views.zig");
const bufferOperation = sema_shared.bufferOperation;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const StandIn = @import("external_capabilities.zig").StandIn;
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const Literal = @import("integer_literal.zig").Literal;
const instances = @import("generic_instances.zig");
const eArenaBinding = sema_shared.eArenaBinding;
const Work = sema_shared.Work;
const prelude = @import("prelude.zig");
const arrays = @import("array_literals.zig");
const variant_calls = @import("variant_calls.zig");
const lambda_context_code = sema_shared.lambda_context_code;
const variantDeclaredHere = sema_shared.variantDeclaredHere;
const LambdaCapture = sema_shared.LambdaCapture;
const eVariantPayload = "E_VARIANT_PAYLOAD";
fn sequenceArgument(kind: BufferKind) bool {
    return switch (kind) {
        .split, .contains, .starts_with, .ends_with, .find, .count, .replace => true,
        else => false,
    };
}
const impl = @This();
/// Bind the expression work queue to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Check one expression tree iteratively through the work queue, starting from the
        /// temporaries an enclosing expression already holds, and return its typed node.
        pub fn expressionWithTemporaries(self: *Checker, root: ast.NodeId, inherited: []const typed.Type) Error!typed.NodeId {
            return impl.expressionWithTemporaries(Checker, self, root, inherited);
        }
        /// Find the parsed lambda whose span matches `span`, if any.
        pub fn lambdaIndex(self: *Checker, span: source.Span) ?usize {
            return impl.lambdaIndex(Checker, self, span);
        }
    };
}
fn hintBufferArguments(comptime Checker: type, self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation)) Error!void {
    if (self.active.get(self.src.text(operation.owner))) |slot| {
        const owner_type = self.locals.items[@backingInt(slot)].ty;
        // A list method's operands take the list's element type before they are
        // checked, so `rows.append([])` and `rows.insert(0, [])` infer the empty
        // literal exactly as `row: list[int] = []` does.
        if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].collection.kind == .list) {
            const element = self.catalog.records[owner_type.recordIndex()].shape.buffer.?;
            switch (operation.kind) {
                .append, .remove, .index_of => if (operation.arguments.len == 1) try self.hint(operation.arguments[0], element),
                .insert => if (operation.arguments.len == 2) {
                    try self.hint(operation.arguments[0], .i64);
                    try self.hint(operation.arguments[1], element);
                },
                .extend => if (operation.arguments.len == 1) try self.hint(operation.arguments[0], owner_type),
                else => {},
            }
            return;
        }
        if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].collection.kind != .list) {
            const schema = self.catalog.records[owner_type.recordIndex()];
            if (schema.collection.kind == .dictionary) {
                if (operation.kind == .update and operation.arguments.len == 1) {
                    try self.hint(operation.arguments[0], owner_type);
                } else {
                    if (operation.arguments.len > 0) try self.hint(operation.arguments[0], schema.collection.key.?);
                    if (operation.arguments.len == 2) try self.hint(operation.arguments[1], schema.shape.buffer.?);
                }
            } else if (operation.kind == .replace and operation.arguments.len == 2) {
                for (operation.arguments) |argument| try self.hint(argument, owner_type);
            } else if (operation.kind == .find_any and operation.arguments.len == 2) {
                try self.hint(operation.arguments[0], owner_type);
                try self.hint(operation.arguments[1], .i64);
            } else if (sequenceArgument(operation.kind) and operation.arguments.len == 1) {
                const byte_needle = schema.collection.kind == .bytes and operation.kind == .contains;
                if (!byte_needle) try self.hint(operation.arguments[0], owner_type);
            }
            return;
        }
    }
}
fn hintRecordFields(comptime Checker: type, self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record")) Error!void {
    const record_type = try self.ty(record.name);
    const schema = try self.catalog.constructor(record_type, record.name, self.sink);
    for (record.fields) |field| {
        const index = if (schema.tableKey()) |key| try self.catalog.variant(key, self.src, field.name, self.sink) else try self.catalog.field(schema.id, self.src, field.name, self.sink);
        try self.hint(field.value, schema.fields[index].ty);
    }
}
fn hintCallArguments(
    comptime Checker: type,
    self: *Checker,
    call: @FieldType(@FieldType(ast.Node, "data"), "call"),
    declaration: instances.DeclarationId,
    target: @FieldType(@FieldType(ast.Node, "data"), "call"),
    span: source.Span,
) Error!void {
    const signature = self.syntax.functions[@backingInt(declaration)].signature;
    const function = if (signature.type_parameters.len == 0)
        self.ordinary_ids[@backingInt(declaration)]
    else if (target.type_arguments.len != 0 or try resultDeterminesArguments(Checker, self, signature, span))
        try self.specialize(declaration, target, span)
    else
        null;
    for (call.arguments, signature.parameters) |argument, parameter| {
        if (function) |function_id| {
            try self.hint(argument, try self.functionType(function_id, parameter.ty));
        } else if (self.catalog.arrays.resolved.get(parameter.ty.start)) |closed| {
            try self.hint(argument, closed);
        } else if (typed.Type.fromName(self.src.text(parameter.ty))) |closed| {
            try self.hint(argument, closed);
        }
    }
}
/// Use a complete contextual substitution to check nested constructor arguments once.
fn resultDeterminesArguments(comptime Checker: type, self: *Checker, signature: ast.FunctionSignature, span: source.Span) Error!bool {
    const expected = self.expected_types.get(span) orelse return false;
    var context: @import("generic_inference.zig").Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = span };
    try context.match(signature.return_type, .{ .concrete = expected });
    return context.complete();
}
/// Queue the positional values, then `sep=` and `end=`, of a print-shaped call.
fn queuePrintArguments(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call"), node: ast.Node) Error!void {
    _ = try io_builtins.printArguments(self.src, call, self.sink);
    // Only a keyword operand needs the text type, and only then is it materialized.
    const text_type = if (call.argument_names.len == 0) null else try collections.preludeType(&self.catalog, "str", node.span);
    var index = call.arguments.len;
    while (index > 0) {
        index -= 1;
        if (call.argument_names.len != 0 and call.argument_names[index] != null) try self.hint(call.arguments[index], text_type.?);
        try work.append(self.allocator, .{ .id = call.arguments[index] });
    }
}
fn queueBuiltinCall(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), call_id: ast.NodeId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), node: ast.Node) Error!bool {
    if (try self.queueListSort(work, call)) return true;
    if (try self.queuePreludeCall(work, call_id, call)) return true;
    if (try self.floatIntrinsic(call) != null) {
        try call_arguments.positional(call, self.sink);
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "float operations require one argument");
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }
    if (try self.numericConversion(call) != null) {
        try call_arguments.positional(call, self.sink);
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "numeric conversions require one argument");
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }
    if (try self.typeConversion(call) != null) {
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }
    if (try self.optionConstructor(call)) {
        try call_arguments.positional(call, self.sink);
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "Some requires one payload");
        try self.hint(call.arguments[0], (try self.expectedOption(node)).shape.element);
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }
    if (try self.textConstructor(call, node.span)) {
        try call_arguments.positional(call, self.sink);
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }
    if (self.byteConversion(call)) |conversion| {
        try call_arguments.positional(call, self.sink);
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "byte conversions require one argument");
        // `bytes([])` and `byte_buffer([])` build from a `list[int]`, so an empty
        // literal takes that type instead of needing an annotated local.
        if (conversion != .from_hex) try self.hintEmptyPreludeList(call.arguments[0], .i64);
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }

    if (try self.fileAccessBuiltin(call) != null) {
        try call_arguments.positional(call, self.sink);
        var index = call.arguments.len;
        while (index > 0) {
            index -= 1;
            try work.append(self.allocator, .{ .id = call.arguments[index] });
        }
        return true;
    }
    if (self.streamLocal(call)) |_| {
        if (std.mem.eql(u8, self.src.text(call.name), "write")) {
            try call_arguments.positional(call, self.sink);
            if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "stream.write takes one str or bytes argument");
            try work.append(self.allocator, .{ .id = call.arguments[0] });
            return true;
        }
        try queuePrintArguments(Checker, self, work, call, node);
        return true;
    }
    if (try self.debugBuiltin(call)) {
        try queuePrintArguments(Checker, self, work, call, node);
        return true;
    }
    if (try self.outputBuiltin(call)) |_| {
        try queuePrintArguments(Checker, self, work, call, node);
        return true;
    }
    if (try self.resultConstructor(call)) |ok| {
        try call_arguments.positional(call, self.sink);
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "Ok and Err require one payload");
        const shape = typed.resultShape(try self.expectedResult(node), self.catalog.records).?;
        try self.hint(call.arguments[0], if (ok) shape.ok_type else shape.error_type);
        try work.append(self.allocator, .{ .id = call.arguments[0] });
        return true;
    }
    return false;
}
/// An intrinsic demanding a fixed `[N]u8` lets a list literal adopt its own length,
/// so a byte sequence needs no type spelling the Python surface cannot write.
fn hintByteArray(comptime Checker: type, self: *Checker, id: ast.NodeId) Error!void {
    const node = self.syntax.nodes.items[@backingInt(id)];
    if (node.data != .list_literal) return;
    const bytes = try self.catalog.instantiateArray(self.allocator, .u8, node.data.list_literal.len, node.span, self.sink);
    try self.hint(id, bytes);
}
fn queueDictionary(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId) Error!bool {
    const node = self.syntax.nodes.items[@backingInt(id)];
    const entries = node.data.dictionary_literal;

    try work.append(self.allocator, .{ .id = id, .emit = true });
    const expected = self.expected_types.get(node.span);
    var index = entries.len;
    while (index > 0) {
        index -= 1;
        if (expected) |expected_type| if (expected_type.isAggregate() and self.catalog.records[expected_type.recordIndex()].collection.kind == .dictionary) {
            const schema = self.catalog.records[expected_type.recordIndex()];
            try self.hint(entries[index], if (index % 2 == 0) schema.collection.key.? else schema.shape.buffer.?);
        } else if (arrays.table(self.catalog, expected_type)) |_| {
            if (index % 2 == 1) try self.hint(entries[index], self.catalog.records[expected_type.recordIndex()].shape.array.?.element);
        };
        try work.append(self.allocator, .{ .id = entries[index] });
    }
    return true;
}
/// Resolve a variant construction's type, letting a generic template adopt its context.
fn variantType(comptime Checker: type, self: *Checker, variant: @FieldType(@FieldType(ast.Node, "data"), "variant"), at: source.Span) Error!typed.Type {
    if (try variant_calls.contextual(self.src, self.catalog, variant.ty, self.expected_types.get(at), self.sink)) |found| return found;
    return self.ty(variant.ty);
}
fn queueVariant(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId, variant: @FieldType(@FieldType(ast.Node, "data"), "variant")) Error!bool {
    const span = self.syntax.nodes.items[@backingInt(id)].span;
    if (variant.fielded) {
        const variant_type = try variantType(Checker, self, variant, span);
        const tag = try self.catalog.variant(variant_type, self.src, variant.name, self.sink);
        const case = self.catalog.records[variant_type.recordIndex()].shape.variants.?.cases[tag];
        const payload = case.payload orelse return self.sink.failRelated(
            eVariantPayload,
            span,
            "this case carries no payload, so it is constructed without parentheses",
            .{ .span = case.declaration, .message = variantDeclaredHere },
        );
        const record = try self.catalog.record(payload, span, self.sink);
        const initializers = try caseInitializers(Checker, self, record, variant.values, variant.value_names, span);
        for (initializers) |initializer| {
            const index = try self.catalog.field(record.id, self.src, initializer.name, self.sink);
            try self.hint(initializer.value, record.fields[index].ty);
        }
        try work.append(self.allocator, .{ .id = id, .emit = true });
        try self.queueFields(work, initializers);
        return true;
    }
    if (variant.value) |value| {
        const variant_type = try variantType(Checker, self, variant, self.syntax.nodes.items[@backingInt(id)].span);
        const tag = try self.catalog.variant(variant_type, self.src, variant.name, self.sink);
        if (self.catalog.records[variant_type.recordIndex()].shape.variants.?.cases[tag].payload) |payload| try self.hint(value, payload);
        try work.append(self.allocator, .{ .id = id, .emit = true });
        try work.append(self.allocator, .{ .id = value });
        return true;
    }
    return false;
}
/// Bind a parenthesized case's positional and named field arguments to the
/// payload record's declared fields, appending one initializer per omitted
/// defaulted field. Arity, unknown, duplicate and missing-field diagnostics
/// come from the shared record-construction path.
fn caseInitializers(comptime Checker: type, self: *Checker, record: typed.Record, values: []const ast.NodeId, names: []const ?source.Span, span: source.Span) Error![]const ast.FieldInit {
    if (values.len > record.fields.len) return self.sink.fail("E_ARITY", span, "too many field arguments for this variant case");
    var initializers: std.ArrayList(ast.FieldInit) = .empty;
    const supplied = try self.allocator.alloc(bool, record.fields.len);
    defer self.allocator.free(supplied);
    @memset(supplied, false);
    for (values, 0..) |value, source_index| {
        const keyword = if (names.len == 0) null else names[source_index];
        const index = if (keyword) |name| try self.catalog.field(record.id, self.src, name, self.sink) else source_index;
        if (supplied[index]) return self.sink.fail("E_DUPLICATE_FIELD", keyword orelse span, "field is initialized more than once");
        supplied[index] = true;
        try initializers.append(self.allocator, .{ .name = if (keyword) |name| name else record.fields[index].declaration, .value = value });
    }
    for (record.fields, 0..) |field, index| {
        if (supplied[index]) continue;
        const default = field.default_value orelse continue;
        try initializers.append(self.allocator, .{ .name = field.declaration, .value = @fromBackingInt(default), .default = true });
    }
    return initializers.toOwnedSlice(self.allocator);
}
/// Queue a qualified call on a local `Filesystem`. `read_only()` and `dir()`
/// queue no operands; a whole-path helper queues its value arguments, because
/// its receiver is a `Span` with no expression node and the checker
/// synthesizes that operand.
/// Qualified calls on a capability local whose receiver is a `Span`: the
/// checker synthesizes that receiver, so only the value arguments are queued
/// here. Returns true when the call is one of them.
fn queueCapabilityCall(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    const owner = call.owner orelse return false;
    const slot = self.active.get(self.src.text(owner)) orelse return false;
    const name = self.src.text(call.name);
    if (self.locals.items[@backingInt(slot)].ty == .network_cap) return std.mem.eql(u8, name, "host");
    if (self.locals.items[@backingInt(slot)].ty != .filesystem_cap) return false;
    if (std.mem.eql(u8, name, "read_only") or std.mem.eql(u8, name, "dir")) return true;
    if (file_operations.access(name) == null) return false;
    var index = call.arguments.len;
    while (index > 0) {
        index -= 1;
        try work.append(self.allocator, .{ .id = call.arguments[index] });
    }
    return true;
}
fn queueExpression(comptime Checker: type, self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId) Error!bool {
    const node = try self.collectionSyntax(id);
    switch (node.data) {
        .file_operation => |operation| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            if (operation.argument) |value| try work.append(self.allocator, .{ .id = value });
            return true;
        },
        .buffer_operation => |operation| {
            try hintBufferArguments(Checker, self, operation);
            try work.append(self.allocator, .{ .id = id, .emit = true });
            var i = operation.arguments.len;
            while (i > 0) {
                i -= 1;
                try work.append(self.allocator, .{ .id = operation.arguments[i] });
            }
            return true;
        },
        .variant => |variant| return queueVariant(Checker, self, work, id, variant),
        .index => |access| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = access.index });
            try work.append(self.allocator, .{ .id = access.base });
            return true;
        },
        .replace => |replace| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = replace.value });
            try work.append(self.allocator, .{ .id = replace.index });
            try work.append(self.allocator, .{ .id = replace.base });
            return true;
        },
        .length, .unwrap, .propagate => |base| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = base });
            return true;
        },
        .restrict_resource => |restrict| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = restrict.value });
            return true;
        },
        .resource_io => |io| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            if (io.value) |value| try work.append(self.allocator, .{ .id = value });
            return true;
        },
        .environment_get => |get| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try hintByteArray(Checker, self, get.name);
            try work.append(self.allocator, .{ .id = get.name });
            try work.append(self.allocator, .{ .id = get.capability });
            return true;
        },
        .complete_resource => |complete| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = complete.value });
            return true;
        },
        .acquire_resource => |acquire| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = acquire.request });
            try work.append(self.allocator, .{ .id = acquire.capability });
            return true;
        },
        .external_read => |read| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = read.capability });
            return true;
        },
        .stand_in => |stand| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            if (stand.second) |second| try work.append(self.allocator, .{ .id = second });
            try work.append(self.allocator, .{ .id = stand.first });
            return true;
        },
        .cast, .wrap => |cast| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = cast.value });
            return true;
        },
        .arena_escape => |copy| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = copy.value });
            return true;
        },
        .dictionary_literal => return queueDictionary(Checker, self, work, id),
        .record => |record| {
            try hintRecordFields(Checker, self, record);
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try self.queueFields(work, record.fields);
            return true;
        },
        .field => |field| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = field.base });
            return true;
        },
        .call => |call| {
            if (self.narrowedCollection(call) != null) return false;
            // An intrinsic `Option` method on a named local is checked in
            // place, like a narrowed collection method: its receiver and its
            // one argument are the call's own, not queued temporaries.
            if (self.optionReceiverMethod(call)) return false;
            try work.append(self.allocator, .{ .id = id, .emit = true });
            if (try queueCapabilityCall(Checker, self, work, call)) return true;
            if (self.environmentMethod(call) != null) return true;
            if (try self.cellConstructor(call) != null) {
                if (self.expected_types.get(node.span)) |expected| if (expected.isAggregate() and self.catalog.records[expected.recordIndex()].isCell()) {
                    try self.hint(call.arguments[0], self.catalog.records[expected.recordIndex()].fields[0].ty);
                };
                try work.append(self.allocator, .{ .id = call.arguments[0] });
                return true;
            }
            if (try queueBuiltinCall(Checker, self, work, id, call, node)) return true;
            if (try self.recordUpdateCall(call)) {
                var update_index = call.arguments.len;
                while (update_index > 0) {
                    update_index -= 1;
                    try work.append(self.allocator, .{ .id = call.arguments[update_index] });
                }
                return true;
            }
            if (call.owner == null and self.active.contains(self.src.text(call.name))) {
                var index = call.arguments.len;
                while (index > 0) {
                    index -= 1;
                    try work.append(self.allocator, .{ .id = call.arguments[index] });
                }
                return true;
            }
            const target = try self.callDeclaration(call, node.span);
            if (target.call.type_arguments.len != 0) _ = try self.specialize(target.declaration, target.call, node.span);
            const signature = self.syntax.functions[@backingInt(target.declaration)];
            try hintCallArguments(Checker, self, target.call, target.declaration, target.call, node.span);
            var i = target.call.arguments.len;
            while (i > 0) {
                i -= 1;
                const position = call_arguments.parameterPosition(target.call, i);
                const argument = target.call.arguments[position];
                const parameter = signature.signature.parameters[position];
                try work.append(self.allocator, .{ .id = argument, .default_value = parameter.default_value == argument });
            }
            return true;
        },
        .unary => |u| {
            if (u.op == .is_none) {
                try self.hintOptionOperand(u.operand);
            } else if (self.expected_types.get(node.span)) |expected| try self.hint(u.operand, expected);
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = u.operand });
            return true;
        },
        .binary => |b| {
            try self.hintBinary(node);
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = b.right, .checkpoint = if (b.op == .logical_and or b.op == .logical_or) .{ .condition = b.left, .truth = b.op == .logical_and } else null });
            try work.append(self.allocator, .{ .id = b.left });
            return true;
        },
        // A `mut` marker is transparent: the value it wraps is checked on its
        // own, and the node itself reuses the resolved target's type and data.
        .mut_argument => |inner| {
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = inner });
            return true;
        },
        else => {},
    }
    return false;
}
fn checkedExpression(comptime Checker: type, self: *Checker, node: ast.Node, minimum_literal: ?Literal, temporaries: []const typed.Type) Error!typed.Node {
    var out: typed.Node = .{ .span = node.span, .ty = .i64, .data = undefined };
    if (lambdaIndex(Checker, self, node.span)) |lambda_index| {
        try checkLambdaValue(Checker, self, lambda_index, node, &out);
    } else if (minimum_literal) |parsed| {
        out.ty = parsed.ty;
        out.data = .{ .integer = parsed.value };
    } else switch (node.data) {
        .field_assignment => return self.checkFieldAssignment(node, temporaries),
        .index_assignment => return self.checkIndexAugmented(node, temporaries),
        .list_literal => |inputs| return self.checkListLiteral(node, inputs, temporaries),
        .format => |parts| return self.checkFormat(node, parts, temporaries),
        .comprehension => |each| return self.checkComprehension(node, each, temporaries),
        .list_operation => |op| {
            if (op.kind == .write and op.arguments.len == 2) if (try self.arrayPlace(op.base, op.arguments[0])) |place|
                return self.checkArrayPlace(node, place, .{ .op = .set, .value = op.arguments[1] }, temporaries);
            return self.checkListAccess(node, .{ .base = op.base, .kind = op.kind, .inputs = op.arguments }, temporaries);
        },
        .method_call => return self.checkCollectionMethod(node, temporaries),
        .slice => return self.checkCollectionSlice(node, temporaries),
        .buffer_operation => |operation| try self.checkBufferOperation(node, operation, &out),
        .file_operation => |operation| try self.checkFileMethod(node, operation, &out),
        .acquire_resource => |acquire| try self.checkAcquireResource(node, acquire, &out),
        .restrict_resource => |restrict| {
            const value = self.resolved[@backingInt(restrict.value)].?;
            out.ty = self.nodes.items[@backingInt(value)].ty;
            if (out.ty != .filesystem_cap) return self.sink.fail("E_TYPE", node.span, "read_only requires a Filesystem capability");
            out.data = .{ .restrict_resource = .{ .permissions = restrict.permissions, .value = value } };
        },
        .resource_io => |io| try self.checkResourceIo(node, io, &out),
        .environment_get => |get| {
            out.ty = try self.ty(get.ty);
            if (typed.environmentShape(out.ty, self.catalog.records) == null) return self.sink.fail(
                "E_ENVIRONMENT_RESULT",
                get.ty,
                "environment result requires i64 error and a record success with bytes: [N]u8, length: u64, present: bool",
            );
            const capability = self.resolved[@backingInt(get.capability)].?;
            const name = self.resolved[@backingInt(get.name)].?;
            try self.require(self.nodes.items[@backingInt(capability)].ty, .environment_cap, self.syntax.nodes.items[@backingInt(get.capability)].span);
            if (!typed.byteRequest(self.nodes.items[@backingInt(name)].ty, self.catalog.records)) return self.sink.fail(
                eEnvironmentName,
                self.syntax.nodes.items[@backingInt(get.name)].span,
                "environment name must be a fixed u8 array",
            );
            out.data = .{ .environment_get = .{ .capability = capability, .name = name } };
        },
        .complete_resource => |complete| {
            out.ty = try self.ty(complete.ty);
            const shape = typed.completionShape(out.ty, self.catalog.records) orelse return self.sink.fail("E_COMPLETION_RESULT", complete.ty, "completion requires bool success and an error record with resource and code: i64 fields");
            const value = self.resolved[@backingInt(complete.value)].?;
            try self.require(self.nodes.items[@backingInt(value)].ty, shape.resource_type, self.syntax.nodes.items[@backingInt(complete.value)].span);
            out.data = .{ .complete_resource = value };
        },
        .external_read => |read| {
            out.ty = try self.ty(read.ty);
            const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail("E_EXTERNAL_RESULT", read.ty, "external reads require a declared result type");
            const expected: typed.Type = if (read.kind == .clock) .i64 else .u64;
            if (shape.ok_type != expected or shape.error_type != .i64) return self.sink.fail("E_EXTERNAL_RESULT", read.ty, "clock success must be i64, random success u64, and the error payload i64");
            const capability = self.resolved[@backingInt(read.capability)].?;
            try self.require(self.nodes.items[@backingInt(capability)].ty, if (read.kind == .clock) .clock_cap else .random_cap, self.syntax.nodes.items[@backingInt(read.capability)].span);
            out.data = .{ .external_read = .{ .kind = read.kind, .capability = capability } };
        },
        .stand_in => |stand| try checkStandIn(Checker, self, stand, &out),
        .propagate => |operand| {
            const value = self.resolved[@backingInt(operand)].?;
            const input_ty = self.nodes.items[@backingInt(value)].ty;
            var element: typed.Type = undefined;
            if (typed.resultShape(input_ty, self.catalog.records)) |input| {
                const output = typed.resultShape(self.return_type, self.catalog.records) orelse return self.sink.fail("E_TRY_RETURN", node.span, "try requires a function returning a declared result type");
                // The error converts implicitly when the enclosing union carries it as a case payload.
                if (input.error_type != output.error_type and typed.wrappingCase(self.catalog.records, output.error_type, input.error_type) == null)
                    try self.require(input.error_type, output.error_type, node.span);
                element = input.ok_type;
            } else if (prelude.optionShape(input_ty, self.catalog.records)) |input| {
                // OPTION-TRY-3: `None` carries no payload, so it propagates
                // into any enclosing `Option[U]`, whatever the operand's `T`.
                _ = prelude.optionShape(self.return_type, self.catalog.records) orelse return self.sink.fail("E_TRY_RETURN", node.span, "try requires a function returning an Option type");
                element = input.element;
            } else return self.sink.fail("E_TRY_TYPE", node.span, "try requires a declared result or option");
            try self.requireHandled(0, node.span);
            for (temporaries[0 .. temporaries.len - 1]) |temporary| if (self.requiresHandling(temporary)) return self.sink.fail(
                "E_RESULT_PROPAGATION",
                node.span,
                "propagation could drop a pending result temporary; handle or transfer it before this expression",
            );
            out.ty = element;
            out.data = .{ .propagate = .{ .value = value, .output = self.return_type } };
        },
        .variant => |variant| {
            out.ty = try variantType(Checker, self, variant, node.span);
            const tag = try self.catalog.variant(out.ty, self.src, variant.name, self.sink);
            const schema = (try self.catalog.variants(out.ty, node.span, self.sink)).cases[tag];
            if (variant.fielded) {
                const payload = schema.payload orelse return self.sink.failRelated(
                    eVariantPayload,
                    node.span,
                    "this case carries no payload, so it is constructed without parentheses",
                    .{ .span = schema.declaration, .message = variantDeclaredHere },
                );
                const record = try self.catalog.record(payload, node.span, self.sink);
                const initializers = try caseInitializers(Checker, self, record, variant.values, variant.value_names, node.span);
                const checked = try self.fields(payload, initializers, true, node.span);
                // The payload record is the variant's single value, so every
                // downstream lowering and equality path is unchanged.
                const record_node: typed.NodeId = @fromBackingInt(self.nodes.items.len);
                try self.nodes.append(self.allocator, .{ .span = node.span, .ty = payload, .data = .{ .record = checked } });
                out.data = .{ .variant = .{ .tag = tag, .value = record_node } };
            } else {
                const value = if (variant.value) |input| self.resolved[@backingInt(input)].? else null;
                if ((schema.payload != null) != (value != null)) return self.sink.failRelated(
                    eVariantPayload,
                    node.span,
                    "construction must supply exactly the payload declared for this variant",
                    .{
                        .span = schema.declaration,
                        .message = variantDeclaredHere,
                    },
                );
                if (value) |input| try self.require(self.nodes.items[@backingInt(input)].ty, schema.payload.?, self.syntax.nodes.items[@backingInt(variant.value.?)].span);
                out.data = .{ .variant = .{ .tag = tag, .value = value } };
            }
        },
        .index => |access| try self.checkValueIndex(node, access, &out),
        .replace => |replace| {
            const base = self.resolved[@backingInt(replace.base)].?;
            const index_value = self.resolved[@backingInt(replace.index)].?;
            const value = self.resolved[@backingInt(replace.value)].?;
            out.ty = self.nodes.items[@backingInt(base)].ty;
            const schema = try self.catalog.array(out.ty, node.span, self.sink);
            if (self.requiresHandling(schema.element)) return self.sink.fail(eResultOperation, node.span, "replacement would drop an unhandled result-bearing element");
            try self.requireIndex(schema, self.nodes.items[@backingInt(index_value)].ty, self.syntax.nodes.items[@backingInt(replace.index)].span);
            try self.require(self.nodes.items[@backingInt(value)].ty, schema.element, self.syntax.nodes.items[@backingInt(replace.value)].span);
            const key = try self.arrayKey(schema, index_value);
            out.data = .{ .replace = .{ .base = base, .index = key.key, .value = value, .from_end = key.from_end } };
        },
        .length => |input| return checkLength(Checker, self, node, input),
        .membership => |membership| return self.checkMembership(node, membership, temporaries),
        .dictionary_literal => |entries| try self.checkDictionaryLiteral(node, entries, &out),
        .record => |record| {
            out.ty = try self.ty(record.name);
            out.data = .{ .record = try self.fields(out.ty, record.fields, true, node.span) };
        },
        .field => |field| try self.checkField(node, field, &out),
        .bytes, .text => |bytes| try self.checkTextLiteral(node, bytes, &out),
        .integer => return self.checkInteger(node),
        .wrap => |wrap| {
            const value = self.resolved[@backingInt(wrap.value)].?;
            out.ty = try self.ty(wrap.ty);
            const backing = try self.catalog.domain(out.ty, wrap.ty, self.sink);
            try self.requireDomainAccess(out.ty, node.span);
            try self.require(self.nodes.items[@backingInt(value)].ty, backing, self.syntax.nodes.items[@backingInt(wrap.value)].span);
            out.data = .{ .wrap = value };
        },
        .unwrap => |input| {
            const value = self.resolved[@backingInt(input)].?;
            const domain_type = self.nodes.items[@backingInt(value)].ty;
            out.ty = try self.catalog.domain(domain_type, node.span, self.sink);
            try self.requireDomainAccess(domain_type, node.span);
            out.data = .{ .unwrap = value };
        },
        .arena_escape => |copy| {
            const value = self.resolved[@backingInt(copy.value)].?;
            out.ty = self.nodes.items[@backingInt(value)].ty;
            if (self.requiresHandling(out.ty)) return self.sink.fail(eResultOperation, node.span, "escape requires a value without a pending result obligation");
            if (typed.moveOnly(out.ty, self.catalog.records)) return self.sink.fail(eArenaBinding, node.span, "escape copies managed values; owned storage and capabilities cannot be copied out of an arena");
            out.data = .{ .arena_escape = value };
        },
        .cast => |cast| {
            const value = self.resolved[@backingInt(cast.value)].?;
            out.ty = try self.ty(cast.ty);
            try self.requireInteger(out.ty, cast.ty);
            try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
            out.data = .{ .cast = value };
        },
        .unit => return self.checkUnit(node),
        .boolean => |value| {
            out.ty = .bool;
            out.data = .{ .boolean = value };
        },
        .name => |name| try self.checkName(node, name, &out),
        .call => |call| {
            // An intrinsic `Option` method outranks the narrowed-collection
            // reading, so a proven-present `Option[list[T]]` receiver still
            // answers `unwrap_or` while keeping `append` and the rest.
            if (self.optionReceiverMethod(call)) return self.checkOptionReceiverMethod(node, call, temporaries);
            if (self.narrowedCollection(call)) |slot| return self.checkNarrowedMethod(node, slot, temporaries);
            try self.checkCall(node, call, &out);
        },
        .unary => |u| return self.checkUnary(node, u),
        .binary => |b| try self.checkValueBinary(b, &out),
        .tuple => |elements| try self.checkTuple(node, elements, temporaries, &out),
        .conditional => |conditional| return self.checkConditional(node, conditional),
        // A `mut` marker is transparent in expression position: the value it
        // wraps keeps its own type and node. The call that owns the marker
        // checks the position, and a marker anywhere else has no call to be
        // checked against.
        .mut_argument => |inner| {
            const value = self.resolved[@backingInt(inner)].?;
            out.ty = self.nodes.items[@backingInt(value)].ty;
            out.data = self.nodes.items[@backingInt(value)].data;
        },
    }
    return out;
}
/// Check `len(value)`, projecting a dictionary view back to its retained
/// mapping so the operation stays nonallocating and observes the live size.
/// Type one deterministic stand-in operation. `__stand_in[T](operand)` builds
/// the stand-in for capability type `T` from an `int` (a clock's start, an
/// entropy seed, ignored otherwise) or, for `Environment`, a `str` of
/// `NAME\0VALUE\0` pairs; `__clock_advance(clock, count)` returns an `int` status.
fn checkStandIn(comptime Checker: type, self: *Checker, stand: @FieldType(@FieldType(ast.Node, "data"), "stand_in"), out: *typed.Node) Error!void {
    const first = self.resolved[@backingInt(stand.first)].?;
    const first_span = self.syntax.nodes.items[@backingInt(stand.first)].span;
    const span = stand.ty orelse {
        const second = self.resolved[@backingInt(stand.second.?)].?;
        try self.require(self.nodes.items[@backingInt(first)].ty, .clock_cap, first_span);
        try self.require(self.nodes.items[@backingInt(second)].ty, .i64, self.syntax.nodes.items[@backingInt(stand.second.?)].span);
        out.ty = .i64;
        out.data = .{ .stand_in = .{ .kind = .advance, .first = first, .second = second } };
        return;
    };
    out.ty = try self.ty(span);
    const index = out.ty.capabilityIndex() orelse return self.sink.fail("E_STAND_IN", span, "a stand-in is a Clock, Entropy, Filesystem, Network or Environment");
    const kind = StandIn.building(index) orelse return self.sink.fail("E_STAND_IN", span, "a stand-in is a Clock, Entropy, Filesystem, Network or Environment");
    const operand: typed.Type = if (kind == .environment) try collections.preludeType(&self.catalog, "str", span) else .i64;
    try self.require(self.nodes.items[@backingInt(first)].ty, operand, first_span);
    out.data = .{ .stand_in = .{ .kind = kind, .first = first, .second = null } };
}

fn checkLength(comptime Checker: type, self: *Checker, node: ast.Node, input: ast.NodeId) Error!typed.Node {
    const base = self.resolved[@backingInt(input)].?;
    const receiver_type = self.nodes.items[@backingInt(base)].ty;
    if (dictionary_views.identify(self.catalog, receiver_type)) |view| if (view != .item) {
        const mapping = try dictionary_views.owner(Checker, self, node.span, base);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(mapping, .length, &.{}, false);
    };
    if (record_layouts.tupleRecord(self.catalog.records, receiver_type) != null)
        return self.sink.fail("E_TYPE", node.span, "a tuple has no length; take it apart with `head, rest = value`");
    if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].collection.kind != .list) {
        return .{ .span = node.span, .ty = .i64, .data = .{ .length = base } };
    }
    if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].isCollection()) {
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, .length, &.{}, true);
    }
    _ = try self.catalog.array(receiver_type, node.span, self.sink);
    if (self.requiresHandling(receiver_type)) return self.sink.fail(eResultOperation, node.span, "length evaluation would drop result-bearing elements");
    return .{ .span = node.span, .ty = .i64, .data = .{ .length = base } };
}
/// Find the parsed lambda whose span matches `span`, if any.
fn lambdaIndex(comptime Checker: type, self: *Checker, span: source.Span) ?usize {
    for (self.syntax.lambdas, 0..) |lambda, index| {
        if (lambda.span.start == span.start and lambda.span.end == span.end) return index;
    }
    return null;
}
fn checkLambdaValue(comptime Checker: type, self: *Checker, index: usize, node: ast.Node, out: *typed.Node) Error!void {
    const expected = self.expected_types.get(node.span) orelse return self.sink.fail(
        lambda_context_code,
        node.span,
        "lambda requires an expected callback type; annotate the destination or pass it to a callback parameter",
    );
    const contract = callables.signature(expected, self.catalog.records) orelse return self.sink.fail(
        lambda_context_code,
        node.span,
        "lambda requires an expected callback type",
    );
    const lambda = self.syntax.lambdas[index];
    if (lambda.parameters.len != contract.parameters.len) return self.sink.fail("E_ARITY", node.span, "lambda parameter count must match its expected callback type");
    for (contract.mutates) |position| if (position < contract.parameters.len and typed.referenceArray(self.catalog.records, contract.parameters[position]))
        return self.sink.fail(lambda_context_code, node.span, "a callback with a `mut` fixed-array parameter cannot be a lambda; write a function and call it directly");
    if (self.lambda_types[index]) |previous| {
        const old = callables.signature(previous, self.catalog.records) orelse return error.InternalError;
        if (!callables.equal(old, contract)) return self.sink.fail(lambda_context_code, node.span, "one lambda expression cannot have conflicting callback types");
    } else self.lambda_types[index] = expected;
    var captures: std.ArrayList(LambdaCapture) = .empty;
    var active = self.active.iterator();
    while (active.next()) |entry| try captures.append(self.allocator, .{ .name = entry.key_ptr.* });
    self.lambda_captures[index] = try captures.toOwnedSlice(self.allocator);
    out.ty = expected;
    out.data = .{ .function_value = @fromBackingInt(self.lambda_start + index) };
}
fn consumedTemporaries(comptime Checker: type, self: *Checker, node: ast.Node, out: typed.Node) Error!usize {
    if (node.data == .unary and node.data.unary.op == .is_none) return 1;
    // An intrinsic `Option` method is checked in place: its receiver and its
    // one argument are the call's own and never reached this stack, so
    // neither the tag test nor the two-arm match consumes a temporary.
    if (node.data == .method_call and option_flow.methodNamed(self.src.text(node.data.method_call.name)) != null) return 0;
    if (node.data == .call and self.optionReceiverMethod(node.data.call)) return 0;
    // `print`/`write` through a `Stream` field checks its receiver and
    // arguments in place, so none of them reached this stack either.
    if (node.data == .method_call and (out.data == .print or out.data == .stream_write)) return 0;
    if (node.data == .index and out.data == .block_value) return 2;
    if (node.data == .length and out.data == .block_value) return 1;
    if (node.data == .bytes or node.data == .text or node.data == .integer) return 0;
    // A list literal checks its own elements, so none of them reach the caller's stack;
    // a dict literal queues every key and value, whether it builds a dict or a table.
    if (node.data == .list_literal or node.data == .format or node.data == .comprehension) return 0;
    if (node.data == .dictionary_literal) return node.data.dictionary_literal.len;
    if (node.data == .binary) return 2;
    // `fs.read_only()` is a narrowing method whose receiver is a local, not a
    // queued sub-expression, so it leaves no temporary for the caller to pop.
    if (node.data == .call and out.data == .restrict_resource) return 0;
    if (node.data == .call and out.data == .dir_resource) return 0;
    // A qualified whole-path helper synthesizes its receiver instead of
    // queueing it, so only the value arguments leave temporaries to pop.
    if (node.data == .call and out.data == .file_access and node.data.call.owner != null)
        return out.data.file_access.arguments.len - 1;
    if (node.data == .call and out.data == .host_resource) return 0;
    // `env.get` and `env.only` read their literal names straight from the
    // syntax tree, so their receivers and arguments are not queued temporaries.
    if (node.data == .call and out.data == .environment_get) return 0;
    if (node.data == .call and out.data == .environment_only) return 0;
    if (node.data == .call and out.data == .environment_names) return 0;
    if (node.data == .call and try self.numericConversion(node.data.call) != null) return node.data.call.arguments.len;
    if (node.data == .call and try self.typeConversion(node.data.call) != null) return 1;
    return switch (out.data) {
        .function_value, .unit, .integer, .boolean, .local, .block_value, .dir_resource, .host_resource => 0,
        .arena_escape, .cast, .wrap, .unwrap, .length, .field, .unary, .propagate, .external_read, .complete_resource, .restrict_resource, .environment_names => 1,
        .stand_in => |stand| stand.kind.operands(),
        .acquire_buffer => 1,
        .acquire_resource, .environment_get, .environment_only => 2,
        .index, .binary => 2,
        .replace => 3,
        .variant => |variant| if (node.data == .variant and node.data.variant.fielded)
            (if (variant.value) |record_node| self.nodes.items[@backingInt(record_node)].data.record.len else 0)
        else if (variant.value != null) 1 else 0,
        .array => |values| values.len,
        // A tuple's elements are checked in place and consume no temporary;
        // only a named construction draws on sorted-argument temporaries.
        .record => |initializers| if (node.data == .tuple) 0 else initializers.len,
        .update => |update| update.fields.len + 1,
        .invoke => |call| call.arguments.len,
        .call => |call| call.arguments.len,
        .buffer_operation => |operation| operation.arguments.len,
        .resource_io => |io| if (io.value != null) 1 else 0,
        .print => |output| output.arguments.len + @intFromBool(output.separator != null) + @intFromBool(output.terminator != null),
        .stream_write => 1,
        .file_access => |call| call.arguments.len,
        .file_method => |call| @intFromBool(call.argument != null),
    };
}
/// Check one expression tree iteratively through the work queue, starting from the
/// temporaries an enclosing expression already holds, and return its typed node.
fn expressionWithTemporaries(comptime Checker: type, self: *Checker, root: ast.NodeId, inherited: []const typed.Type) Error!typed.NodeId {
    var work: std.ArrayList(Work) = .empty;
    defer work.deinit(self.allocator);
    var temporaries: std.ArrayList(typed.Type) = .empty;
    defer temporaries.deinit(self.allocator);
    try temporaries.appendSlice(self.allocator, inherited);
    try work.append(self.allocator, .{ .id = root });
    while (work.pop()) |task| {
        if (task.sorted_key) {
            const parent = self.syntax.nodes.items[@backingInt(task.id)];
            std.debug.assert(parent.data == .call);
            const call = parent.data.call;
            try self.hintSortedArguments(call, try self.sortedKeywords(call));
            // The named operands are checked in source order, after the list.
            var index = call.arguments.len;
            while (index > 1) {
                index -= 1;
                try work.append(self.allocator, .{ .id = call.arguments[index] });
            }
            continue;
        }
        if (task.verify) |state| {
            try self.samePending(state.pending, self.syntax.nodes.items[@backingInt(task.id)].span, eResultPath);
            self.option_facts.restore(state.facts);
            continue;
        }
        if (task.checkpoint) |guard| {
            const state = try self.pendingState(self.locals.items.len);
            const facts = try self.option_facts.snapshot(self.allocator);
            try self.assumeOption(guard.condition, guard.truth);
            try work.append(self.allocator, .{ .id = task.id, .verify = .{ .pending = state, .facts = facts } });
            try work.append(self.allocator, .{ .id = task.id });
            continue;
        }
        const index = @backingInt(task.id);
        if (self.resolved[index]) |value| {
            if (task.default_value) try temporaries.append(self.allocator, self.nodes.items[@backingInt(value)].ty);
            continue;
        }
        const node = try self.collectionSyntax(task.id);
        const minimum_literal = try self.minimum(node);
        if (!task.emit and minimum_literal == null) {
            if (try queueExpression(Checker, self, &work, task.id)) continue;
        }
        const out = try checkedExpression(Checker, self, node, minimum_literal, temporaries.items);
        const consumed = try consumedTemporaries(Checker, self, node, out);
        std.debug.assert(temporaries.items.len >= consumed);
        temporaries.shrinkRetainingCapacity(temporaries.items.len - consumed);
        try temporaries.append(self.allocator, out.ty);
        try self.resolved_nodes.append(self.allocator, index);
        self.resolved[index] = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, out);
    }
    return self.resolved[@backingInt(root)].?;
}

test "text methods whose one operand is more text get the receiver type as their hint" {
    try std.testing.expect(sequenceArgument(.split));
    try std.testing.expect(sequenceArgument(.starts_with));
    try std.testing.expect(sequenceArgument(.replace));
    try std.testing.expect(!sequenceArgument(.zfill));
}
