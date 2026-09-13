//! Scope and type checking use resolved binding identities, including advisory use counts.
const buffer_operations = @import("buffer_operations.zig");
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const needs_list = "operation requires a managed list";
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const callables = @import("callables.zig");
const eBorrowConflict = diagnostic.borrow_conflict;
const callback_type_code = "E_CALLBACK_TYPE";
const eResultOperation = diagnostic.result_operation;
const eOwnedConsumed = diagnostic.owned_consumed;
const eReferenceResult = diagnostic.reference_result;
const eResultPath = diagnostic.result_path;
const eReturnLifetime = diagnostic.return_lifetime;
const eShadowing = diagnostic.shadowing;
const eConversionBody = "E_CONVERSION_BODY";
const eResourceResult = diagnostic.resource_result;
const eReferenceReadOnly = diagnostic.reference_read_only;
const eBufferResult = "E_BUFFER_RESULT";
const eResultBorrow = diagnostic.result_borrow;
const eResourceIoResult = "E_RESOURCE_IO_RESULT";
const eResultLoop = diagnostic.result_loop;
const bindingDeclaredHere = "binding declared here";
const ePoolResult = "E_POOL_RESULT";
const eImmutable = diagnostic.immutable;
const eResultDiscard = diagnostic.result_discard;
const variantDeclaredHere = "variant declared here";
const std = @import("std");
const bufferOperation = "buffer_operation";
const eCollectionMethod = "E_COLLECTION_METHOD";
const eReferenceArgument = diagnostic.reference_argument;
const source_json = @import("source_json.zig");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const field_moves = @import("field_moves.zig");
const records = @import("records.zig");
const Error = diagnostic.Error;
const instances = @import("generic_instances.zig");
const Names = @import("module_names.zig").Names;
const LoopScope = struct { id: usize, before: []const Pending, references: usize, arena_depth: usize, arenas: usize = 0 };
const ArenaScope = struct { name: []const u8, declaration: source.Span, watermark: typed.LocalId };
const eArenaEscape = "E_ARENA_ESCAPE";
const eArenaBinding = "E_ARENA_BINDING";
const Pending = struct { available: bool, fields: field_moves.State, transfer_span: ?source.Span };
const Work = struct { default_value: bool = false, id: ast.NodeId, emit: bool = false, checkpoint: bool = false, verify: ?[]const Pending = null };
const FieldDestination = struct { owner: typed.LocalId, index: ?typed.NodeId, value: typed.NodeId, refresh: typed.StatementId };
const CheckedStatement = struct { id: typed.StatementId, terminates: bool };

const StatementFlow = struct {
    terminates: bool = false,
    cleanup: []const typed.ReferenceId = &.{},
    owned_cleanup: []const typed.LocalId = &.{},
};

const integer_literal = @import("integer_literal.zig");
const float_syntax = @import("float_syntax.zig");
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");

const Checker = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    syntax: ast.Program,
    sink: *diagnostic.Sink,
    nodes: std.ArrayList(typed.Node) = .empty,
    statements: std.ArrayList(typed.Statement) = .empty,
    locals: std.ArrayList(typed.Local) = .empty,
    active: std.StringHashMapUnmanaged(typed.LocalId) = .empty,
    resolved: []?typed.NodeId,
    expected_types: std.AutoHashMapUnmanaged(source.Span, typed.Type) = .empty,
    functions: std.StringHashMapUnmanaged(instances.DeclarationId) = .empty,
    resolved_nodes: std.ArrayList(usize) = .empty,
    instance_keys: std.ArrayList(instances.Key) = .empty,
    generic_registry: instances.Registry = .{},
    ordinary_ids: []?typed.FunctionId,
    ordinary_count: usize = 0,
    current_function: ?typed.FunctionId = null,
    python_assignment_order: bool = false,
    loops: struct { active: std.ArrayList(LoopScope) = .empty, next: usize = 0 } = .{},
    return_type: typed.Type = .i64,
    arena_depth: usize = 0,
    arenas: std.ArrayList(ArenaScope) = .empty,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,
    managed_types: []bool = &.{},
    owner: ?typed.Type = null,
    return_reference: ?typed.ReturnReference = null,
    references: std.ArrayList(typed.Reference) = .empty,
    active_refs: std.StringHashMapUnmanaged(typed.ReferenceId) = .empty,

    fn checkFunction(self: *Checker, i: usize) Error!typed.Function {
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        self.current_function = @fromBackingInt(i);
        const function = self.syntaxFunction(@fromBackingInt(i));
        self.python_assignment_order = function.policy.python;
        const constant_context: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        const constant = if (function.policy.constant) try constant_context.evaluate(@backingInt(self.instance_keys.items[i].declaration)) else null;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.locals = .empty;
        self.references = .empty;
        self.active_refs.clearRetainingCapacity();
        self.active.clearRetainingCapacity();
        self.owner = if (function.policy.owner) |owner| try self.ty(owner) else null;
        self.return_type = try self.ty(function.signature.return_type);
        self.return_reference = try self.returnContract(@fromBackingInt(i));
        try self.bindParameters(function);
        if (function.policy.c_abi) {
            const foreign = @import("c_abi.zig");
            if (!foreign.supported(self.return_type, self.catalog.records, true)) return sink.fail("E_EXTERN_SIGNATURE", function.signature.return_type, foreign.signature_message);
            for (self.locals.items) |local| if (!foreign.supported(local.ty, self.catalog.records, false)) return sink.fail("E_EXTERN_SIGNATURE", local.declaration, foreign.signature_message);
            if (!foreign.validSymbol(src.text(function.name))) return sink.fail("E_EXTERN_SYMBOL", function.name, "extern names must be C identifiers outside the reserved myl_/mylang_ runtime namespaces");
        } else if (function.policy.host != null) {
            try checkHostType(allocator, self.catalog.records, self.return_type, function.signature.return_type, sink);
            for (self.locals.items) |local| try checkHostType(allocator, self.catalog.records, local.ty, local.declaration, sink);
        }
        self.conversion_fields = null;
        if (function.policy.conversion) {
            if (function.signature.return_reference != null or function.signature.parameters.len != 1 or function.signature.parameters[0].reference != null) return sink.fail(
                "E_CONVERSION_SIGNATURE",
                function.name,
                "a complete conversion requires one source record parameter",
            );
            const source_record = try self.catalog.record(self.locals.items[0].ty, function.signature.parameters[0].ty, sink);
            _ = try self.catalog.record(self.return_type, function.signature.return_type, sink);
            try conversionBody(src, self.syntax, function, sink);
            self.conversion_fields = try allocator.alloc(bool, source_record.fields.len);
            @memset(self.conversion_fields.?, false);
        }
        // Type-check even unevaluated short-circuit operands before replacing the
        // immutable initializer with its checked literal value.
        var body = try self.statement(function.body);
        if (constant) |value| {
            const node_id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(allocator, .{ .span = function.name, .ty = value.typeOf(), .data = if (value == .bool) .{ .boolean = value.bool } else .{ .integer = if (value == .i64) value.i64 else value.integer.value } });
            const statement_id: typed.StatementId = @fromBackingInt(self.statements.items.len);
            try self.statements.append(allocator, .{ .span = function.name, .terminates = true, .data = .{ .ret = node_id } });
            body = .{ .id = statement_id, .terminates = true };
        }
        if (self.conversion_fields) |seen| {
            const source_record = self.catalog.records[self.locals.items[0].ty.recordIndex()];
            for (seen, source_record.fields) |accounted, field| {
                if (!accounted) {
                    const message = try std.fmt.allocPrint(allocator, "source field `{s}` is not accounted for; use it in the destination or explicitly discard that named field", .{field.name});
                    return sink.failRelated("E_INCOMPLETE_CONVERSION", function.name, message, .{ .span = field.declaration, .message = "unaccounted source field declared here" });
                }
            }
        }
        const implicit_unit = self.return_type == .unit and self.return_reference == null;
        if (function.policy.host == null and !body.terminates and implicit_unit) body = try self.unitFallthrough(body, function.name);
        if (function.policy.host == null and !body.terminates) return sink.fail(
            "E_MISSING_RETURN",
            function.name,
            "function may fall through without returning its declared type; loops are conservatively treated as falling through, even while true",
        );
        return .{
            .policy = .{
                .host = function.policy.host,
                .c_abi = function.policy.c_abi,
                .effect_bound = function.policy.effect_bound,
                .owner = self.owner,
                .restricted = function.policy.restricted,
                .conversion = function.policy.conversion,
            },
            .signature = .{
                .constant_arguments = self.instance_keys.items[i].lengths,
                .return_reference = self.return_reference,
                .return_type = self.return_type,
                .parameter_count = function.signature.parameters.len,
            },
            .scope = .{
                .references = try self.references.toOwnedSlice(allocator),
                .body = body.id,
                .locals = try self.locals.toOwnedSlice(allocator),
            },
            .id = @fromBackingInt(i),
            .name = try self.instanceName(@fromBackingInt(i)),
            .type_arguments = self.instance_keys.items[i].arguments,
            .declaration = function.name,
        };
    }
    fn topLevel(self: *Checker, span: source.Span) error{InternalError}!bool {
        if (self.current_function) |id| {
            for (self.syntaxFunction(id).signature.type_parameters) |parameter| {
                if (parameter.constant_length and std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) return true;
            }
        }
        if (self.catalog.module_names) |names| return names.topLevel(span);
        const name = self.src.text(span);
        return self.functions.contains(name) or self.catalog.names.contains(name) or self.catalog.templates.names.contains(name);
    }
    fn ty(self: *Checker, span: source.Span) Error!typed.Type {
        if (self.current_function) |id| return self.functionType(id, span);
        return self.catalog.resolve(self.src, span, self.sink);
    }
    fn syntaxFunction(self: *Checker, id: typed.FunctionId) ast.Function {
        return self.syntax.functions[@backingInt(self.instance_keys.items[@backingInt(id)].declaration)];
    }
    fn instanceName(self: *Checker, id: typed.FunctionId) Error![]const u8 {
        const function = self.syntaxFunction(id);
        const base = if (self.catalog.module_names) |module|
            try module.functionDeclaration(function.policy.owner, function.name)
        else
            try functionName(self.allocator, self.src, function.policy.owner, function.name);
        const arguments = self.instance_keys.items[@backingInt(id)].arguments;
        if (arguments.len == 0) return base;
        var output: std.Io.Writer.Allocating = .init(self.allocator);
        defer output.deinit();
        output.writer.print("{s}::<", .{base}) catch return error.OutOfMemory;
        for (arguments, 0..) |argument, index| {
            if (index != 0) output.writer.writeByte(',') catch return error.OutOfMemory;
            if (self.instance_keys.items[@backingInt(id)].length(index)) |length| {
                output.writer.print("{d}", .{length}) catch return error.OutOfMemory;
            } else output.writer.writeAll(typed.typeName(argument, self.catalog.records)) catch return error.OutOfMemory;
        }
        output.writer.writeByte('>') catch return error.OutOfMemory;
        return output.toOwnedSlice();
    }
    fn functionType(self: *Checker, id: typed.FunctionId, span: source.Span) Error!typed.Type {
        return self.functionTypeDepth(id, span, 0);
    }
    fn functionTypeDepth(self: *Checker, id: typed.FunctionId, span: source.Span, depth: usize) Error!typed.Type {
        const key = self.instance_keys.items[@backingInt(id)];
        const function = self.syntax.functions[@backingInt(key.declaration)];
        return @import("generic_substitution.zig").resolve(self.allocator, &self.catalog, self.src, self.sink, .{
            .span = span,
            .parameters = function.signature.type_parameters,
            .arguments = key.arguments,
            .lengths = key.lengths,
            .depth = depth,
        });
    }
    fn lengthArgument(self: *Checker, span: source.Span) Error!usize {
        const id = self.current_function orelse return @import("generic_lengths.zig").literal(self.src, span, self.sink);
        const key = self.instance_keys.items[@backingInt(id)];
        return @import("generic_lengths.zig").resolve(self.src, span, self.syntaxFunction(id).signature.type_parameters, key.lengths, self.sink);
    }
    fn specialize(self: *Checker, declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
        const function = self.syntax.functions[@backingInt(declaration)];
        if (call.type_arguments.len != 0 and call.type_arguments.len != function.signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (self.ordinary_ids[@backingInt(declaration)]) |id| return id;
        const required = try @import("generic_requirements.zig").resolve(self.allocator, self.src, function.signature.type_parameters, self.sink);
        const arguments = try self.allocator.alloc(typed.Type, required.len);
        const lengths = try self.allocator.alloc(?usize, required.len);
        @memset(lengths, null);
        if (call.type_arguments.len == 0) {
            try self.inferArguments(function.signature, call, span, arguments, lengths);
        }
        for (required, arguments, 0..) |parameter, *argument, argument_index| {
            const at = if (call.type_arguments.len == 0) span else call.type_arguments[argument_index];
            if (parameter.constant_length) {
                if (call.type_arguments.len != 0) lengths[argument_index] = try self.lengthArgument(at);
                argument.* = .u64;
                continue;
            }
            if (call.type_arguments.len != 0) argument.* = try self.ty(at);
            if (!parameter.requirements.accepts(argument.*, self.catalog.records)) return self.sink.failRelated(
                "E_GENERIC_ARGUMENT",
                at,
                "type argument does not satisfy the callee's declared requirements",
                .{ .span = parameter.name, .message = "required type parameter declared here" },
            );
        }
        for (required, arguments) |parameter, argument| try (@import("structural_constraints.zig").Context{
            .src = self.src,
            .catalog = &self.catalog,
            .program = self.syntax,
            .sink = self.sink,
            .lengths = lengths,
        }).accepts(self.allocator, argument, parameter, function.signature.type_parameters, arguments);
        const instance = self.generic_registry.intern(self.allocator, .{ .declaration = declaration, .arguments = arguments, .lengths = lengths }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return self.sink.fail("E_GENERIC_LIMIT", span, "generic specialization exceeds instance or type argument budget"),
        };
        const index = self.ordinary_count + @backingInt(instance);
        if (index == self.instance_keys.items.len) try self.instance_keys.append(self.allocator, (self.generic_registry.get(instance) catch return error.InternalError));
        return @fromBackingInt(index);
    }
    fn inferArguments(self: *Checker, signature: @FieldType(ast.Function, "signature"), call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span, arguments: []typed.Type, lengths: []?usize) Error!void {
        const inference = @import("generic_inference.zig");
        var context: inference.Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = span };
        for (signature.parameters, call.arguments) |parameter, input| {
            const node = self.syntax.nodes.items[@backingInt(input)];
            const actual = if (parameter.reference != null and node.data != .bytes) reference_type: {
                if (node.data != .name) return self.sink.fail(eReferenceArgument, node.span, "reference parameter requires an active reference name");
                const id = self.active_refs.get(self.src.text(node.data.name)) orelse return self.sink.fail("E_REFERENCE_SCOPE", node.span, "reference is not active in this scope");
                break :reference_type self.references.items[@backingInt(id)].ty;
            } else if (parameter.reference != null) typed.Type.u8 else self.nodes.items[@backingInt(self.resolved[@backingInt(input)].?)].ty;
            try context.match(parameter.ty, .{ .concrete = actual });
        }
        var inferred: [16]@import("symbolic_types.zig").Value = undefined;
        try context.finish(inferred[0..arguments.len]);
        for (inferred[0..arguments.len], arguments, lengths) |value, *argument, *length| {
            switch (value) {
                .concrete => |ty_value| argument.* = ty_value,
                .length => |count| {
                    argument.* = .u64;
                    length.* = count;
                },
                else => return error.InternalError,
            }
        }
    }
    fn requiresHandling(self: *Checker, value_type: typed.Type) bool {
        return typed.requiresHandling(value_type, self.catalog.records);
    }
    fn transfers(self: *Checker, value_type: typed.Type) bool {
        return self.requiresHandling(value_type) or typed.moveOnly(value_type, self.catalog.records);
    }
    fn pendingState(self: *Checker, count: usize) Error![]Pending {
        const state = try self.allocator.alloc(Pending, count);
        for (self.locals.items[0..count], state) |local, *pending| pending.* = .{ .available = local.ownership.transfer_available, .fields = local.ownership.partial_fields, .transfer_span = local.ownership.transfer_span };
        return state;
    }
    fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*local, pending| {
            local.ownership.transfer_available = pending.available;
            local.ownership.partial_fields = pending.fields;
            local.ownership.transfer_span = pending.transfer_span;
        }
    }
    fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |local, pending| if (local.ownership.transfer_available != pending.available or !field_moves.same(local.ownership.partial_fields, pending.fields)) return self.sink.failRelated(
            if (!self.requiresHandling(local.ty) and typed.moveOnly(local.ty, self.catalog.records)) (if (std.mem.eql(u8, code, eResultLoop)) "E_OWNED_LOOP" else "E_OWNED_PATH") else code,
            span,
            "ownership or result obligation must have the same state on every continuing path",
            .{
                .span = local.declaration,
                .message = bindingDeclaredHere,
            },
        );
    }
    fn pendingObligation(self: *Checker, local: typed.Local) bool {
        if (!local.ownership.transfer_available or !self.requiresHandling(local.ty)) return false;
        if (local.ownership.partial_fields.len == 0) return true;
        for (self.catalog.records[local.ty.recordIndex()].fields, local.ownership.partial_fields) |field, moved| {
            if (moved == null and self.requiresHandling(field.ty)) return true;
        }
        return false;
    }
    fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
        for (self.locals.items[first..], first..) |local, index| {
            if (self.pendingObligation(local) and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index))) return self.sink.failRelated(
                "E_RESULT_UNHANDLED",
                span,
                "result-bearing value leaves scope without being handled, returned, transferred, or explicitly acknowledged",
                .{
                    .span = local.declaration,
                    .message = "unhandled result-bearing binding",
                },
            );
        }
    }
    fn activeCleanup(self: *Checker) Error![]const typed.ReferenceId {
        var refs: std.ArrayList(typed.ReferenceId) = .empty;
        for (self.references.items, 0..) |ref, i| {
            const id: typed.ReferenceId = @fromBackingInt(i);
            if (self.active_refs.get(ref.name) == id) try refs.append(self.allocator, id);
        }
        return refs.toOwnedSlice(self.allocator);
    }
    fn returnContract(self: *Checker, id: typed.FunctionId) Error!?typed.ReturnReference {
        const function = self.syntaxFunction(id);
        const contract = function.signature.return_reference orelse return null;
        for (function.signature.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.src.text(parameter.name), self.src.text(contract.source))) continue;
            const mutable = parameter.reference orelse return self.sink.fail(eReturnLifetime, contract.source, "reference result must borrow from a reference parameter");
            if (contract.mutable and !mutable) return self.sink.fail(eReferenceReadOnly, contract.source, "shared parameter cannot supply an exclusive result");
            const input_type = try self.functionType(id, parameter.ty);
            const expected = if (contract.slice and !parameter.slice) try self.sliceElement(input_type, contract.source) else input_type;
            if (parameter.slice and !contract.slice) return self.sink.fail("E_REFERENCE_KIND", function.signature.return_type, "a slice parameter cannot supply a whole-value reference result");
            try self.require(try self.functionType(id, function.signature.return_type), expected, function.signature.return_type);
            return .{ .parameter = @fromBackingInt(index), .mutable = contract.mutable, .slice = contract.slice };
        }
        return self.sink.fail(eReturnLifetime, contract.source, "result lifetime names no parameter");
    }
    const ResolvedCall = struct { declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call") };
    fn callTarget(self: *Checker, input: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
        const target = try self.callDeclaration(input, span);
        return self.specialize(target.declaration, target.call, span);
    }
    fn callDeclaration(self: *Checker, input: @FieldType(@FieldType(ast.Node, "data"), "call"), _: source.Span) Error!ResolvedCall {
        if (std.mem.eql(u8, self.src.text(input.name), "todo") and input.owner == null) {
            _ = try self.ty(input.type_arguments[0]);
            return self.sink.typedHole(input.name, input.type_arguments[0]);
        }
        const call = try @import("source_codec.zig").resolve(self.src, self.syntax, self.catalog, input, self.sink);
        const owner = if (call.owner) |name| try self.ty(name) else null;
        if (owner) |domain_type| _ = try self.catalog.domain(domain_type, call.owner.?, self.sink);
        const current_owner = if (self.owner) |domain| self.catalog.records[domain.recordIndex()].name else null;
        const bare_owner = if (current_owner) |name| (if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name) else null;
        const member = if (call.owner != null) call.name else null;
        var symbolic_owner = false;
        if (call.owner) |owner_span| if (self.current_function) |id| {
            for (self.syntaxFunction(id).signature.type_parameters) |parameter| {
                if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(owner_span))) symbolic_owner = true;
            }
        };
        const name = if (symbolic_owner)
            try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.catalog.records[owner.?.recordIndex()].name, self.src.text(call.name) })
        else if (self.catalog.module_names) |names|
            try names.reference(call.owner orelse call.name, .function, member, bare_owner, self.sink)
        else
            try functionName(self.allocator, self.src, call.owner, call.name);
        const function = self.functions.get(name) orelse return self.sink.fail("E_UNKNOWN_FUNCTION", call.name, "no function has this qualified name");
        const signature = self.syntax.functions[@backingInt(function)];
        if (signature.policy.restricted and self.owner != owner) return self.sink.failRelated(
            "E_PRIVATE_FUNCTION",
            call.name,
            "private domain function is only callable from the same domain",
            .{
                .span = signature.name,
                .message = "private function declared here",
            },
        );
        const bound = try call_arguments.bind(self.allocator, self.src, call, signature.signature.parameters, self.sink);
        return .{ .declaration = function, .call = bound };
    }
    fn reference(self: *Checker, span: source.Span) Error!typed.ReferenceId {
        const id = self.active_refs.get(self.src.text(span)) orelse return self.sink.fail("E_REFERENCE_SCOPE", span, "reference is not active in this scope");
        const ref = self.references.items[@backingInt(id)];
        if (self.locals.items[@backingInt(ref.owner)].parameter.reference_parameter != null) self.locals.items[@backingInt(ref.owner)].usage.reads += 1;
        if (ref.mutable) {
            var cause: ?source.Span = null;
            var entries = self.active_refs.valueIterator();
            while (entries.next()) |child| {
                const loan = self.references.items[@backingInt(child.*)];
                if (loan.parent == id and (cause == null or loan.declaration.start < cause.?.start)) cause = loan.declaration;
            }
            if (cause) |at| return self.sink.failProvenance(
                "E_BORROW_SUSPENDED",
                span,
                "exclusive reference is suspended by an active child borrow",
                .{ .span = at, .message = "child borrow starts here" },
                self.locals.items[@backingInt(ref.owner)].declaration,
            );
        }

        return id;
    }
    fn requireReferenceKind(self: *Checker, id: typed.ReferenceId, slice: bool, span: source.Span) Error!void {
        if (self.references.items[@backingInt(id)].mode.slice != slice) return self.sink.fail("E_REFERENCE_KIND", span, if (slice) "operation requires a slice" else "operation requires a whole-value reference");
    }
    fn sliceElement(self: *Checker, ty_id: typed.Type, span: source.Span) Error!typed.Type {
        return typed.sliceElement(ty_id, self.catalog.records) orelse self.sink.fail("E_SLICE_TYPE", span, "slicing requires a fixed numeric array, buffer, or existing slice");
    }

    fn ownerAccess(self: *Checker, slot: typed.LocalId, write: bool, span: source.Span) Error!void {
        var cause: ?source.Span = null;
        var entries = self.active_refs.valueIterator();
        while (entries.next()) |id| {
            const ref = self.references.items[@backingInt(id.*)];
            if (ref.owner == slot and ref.parent == null and (write or ref.mutable)) {
                if (cause == null or ref.declaration.start < cause.?.start) cause = ref.declaration;
            }
        }
        if (cause) |at| return self.sink.failProvenance(
            eBorrowConflict,
            span,
            "owner access conflicts with an active borrow",
            .{ .span = at, .message = "conflicting borrow starts here" },
            self.locals.items[@backingInt(slot)].declaration,
        );
    }
    fn requireDomainAccess(self: *Checker, domain_type: typed.Type, span: source.Span) Error!void {
        if (self.owner != domain_type) return self.sink.failRelated(
            "E_PRIVATE_DOMAIN",
            span,
            "only functions declared inside this domain can access its representation; use its factories and accessors",
            .{
                .span = self.catalog.records[domain_type.recordIndex()].declaration,
                .message = "domain representation is private here",
            },
        );
    }
    fn fields(self: *Checker, record_type: typed.Type, initializers: []const ast.FieldInit, complete: bool, span: source.Span) Error![]const typed.FieldInit {
        const record = if (complete) try self.catalog.constructor(record_type, span, self.sink) else try self.catalog.record(record_type, span, self.sink);
        const table_key = record.tableKey();
        const seen = try self.allocator.alloc(bool, record.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const checked = try self.allocator.alloc(typed.FieldInit, initializers.len);
        for (initializers, checked) |field, *out| {
            const index = if (table_key) |key| try self.catalog.variant(key, self.src, field.name, self.sink) else try self.catalog.field(record_type, self.src, field.name, self.sink);
            if (seen[index]) return self.sink.fail(if (table_key != null) "E_DUPLICATE_KEY" else "E_DUPLICATE_FIELD", field.name, "named entry is initialized more than once");
            seen[index] = true;
            const value = self.resolved[@backingInt(field.value)].?;
            try self.require(self.nodes.items[@backingInt(value)].ty, record.fields[index].ty, self.syntax.nodes.items[@backingInt(field.value)].span);
            out.* = .{ .index = index, .value = value };
        }
        if (complete) for (seen, record.fields) |present, field| {
            if (!present) {
                const message = try std.fmt.allocPrint(self.allocator, "missing initializer for {s} `{s}` of `{s}`", .{ if (table_key != null) "key" else "field", field.name, record.name });
                return self.sink.failRelated(if (table_key != null) "E_INCOMPLETE_TABLE" else "E_INCOMPLETE_CONSTRUCTION", span, message, .{ .span = field.declaration, .message = "missing entry declared here" });
            }
        };
        return checked;
    }
    fn queueFields(self: *Checker, work: *std.ArrayList(Work), initializers: []const ast.FieldInit) Error!void {
        var i = initializers.len;
        while (i > 0) {
            i -= 1;
            try work.append(self.allocator, .{ .id = initializers[i].value });
        }
    }
    fn require(self: *Checker, actual: typed.Type, expected: typed.Type, span: source.Span) Error!void {
        if (actual != expected) {
            const message = try std.fmt.allocPrint(self.allocator, "expected {s}, found {s}", .{ typed.typeName(expected, self.catalog.records), typed.typeName(actual, self.catalog.records) });
            return self.sink.fail("E_TYPE", span, message);
        }
    }
    fn resolve(self: *Checker, name: source.Span) Error!typed.LocalId {
        return self.active.get(self.src.text(name)) orelse self.sink.fail("E_UNKNOWN_NAME", name, "name is not defined in this scope");
    }
    const Literal = integer_literal.Literal;
    fn literal(self: *Checker, span: source.Span, allow_minimum: bool) Error!Literal {
        return integer_literal.parse(self.src, span, allow_minimum, self.sink);
    }
    fn minimum(self: *Checker, node: ast.Node) Error!?Literal {
        if (node.data != .unary or node.data.unary.op != .neg) return null;
        const child = self.syntax.nodes.items[@backingInt(node.data.unary.operand)];
        if (child.data != .integer or float_syntax.isLiteral(self.src.text(child.data.integer))) return null;
        const expected = self.expected_types.get(node.span);
        if (expected) |ty_value| if (numeric_surface.isFloat(ty_value, self.catalog.records)) return null;
        const parsed = try integer_literal.parseExpected(self.src, child.data.integer, true, expected, self.sink);
        if (expected != null and parsed.ty.isInteger()) {
            if (!parsed.ty.fits(-parsed.value)) return self.sink.fail("E_INTEGER_RANGE", node.span, "negative integer literal does not fit its expected type");
            return .{ .ty = parsed.ty, .value = -parsed.value };
        }
        if (parsed.ty.integer().?.signed and parsed.value == -parsed.ty.min()) return .{ .ty = parsed.ty, .value = -parsed.value };
        return null;
    }
    fn requireIndex(self: *Checker, array: typed.Array, actual: typed.Type, span: source.Span) Error!void {
        if (array.key) |key| try self.require(actual, key, span) else try self.requireInteger(actual, span);
    }
    fn requireInteger(self: *Checker, actual: typed.Type, span: source.Span) Error!void {
        if (!actual.isInteger()) return self.sink.fail("E_TYPE", span, "operation requires an integer type");
    }
    fn expression(self: *Checker, root: ast.NodeId) Error!typed.NodeId {
        return self.expressionMode(root, false);
    }
    fn hint(self: *Checker, id: ast.NodeId, expected: typed.Type) Error!void {
        try self.expected_types.put(self.allocator, self.syntax.nodes.items[@backingInt(id)].span, expected);
    }
    fn checkInteger(self: *Checker, node: ast.Node) Error!typed.Node {
        const token = node.data.integer;
        const expected = self.expected_types.get(node.span);
        const text = self.src.text(token);
        if (float_syntax.isLiteral(text) or (expected != null and numeric_surface.isFloat(expected.?, self.catalog.records))) return self.numericBuilder(node.span).literal(text, self.sink);
        const parsed = try integer_literal.parseExpected(self.src, token, false, expected, self.sink);
        return .{ .span = node.span, .ty = parsed.ty, .data = .{ .integer = parsed.value } };
    }
    fn numericBuilder(self: *Checker, span: source.Span) numeric_surface.Builder {
        return .{ .arena = self.allocator, .nodes = &self.nodes, .span = span, .float_type = self.catalog.names.get("float").? };
    }
    fn obviousNumericType(self: *Checker, id: ast.NodeId) ?typed.Type {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (self.expected_types.get(node.span)) |expected| return expected;
        if (node.data == .name) if (self.active.get(self.src.text(node.data.name))) |slot| return self.locals.items[@backingInt(slot)].ty;
        if (node.data == .integer and float_syntax.isLiteral(self.src.text(node.data.integer))) return self.catalog.names.get("float");
        return null;
    }
    fn hintBinary(self: *Checker, node: ast.Node) Error!void {
        const binary = node.data.binary;
        const expected = self.obviousNumericType(binary.left) orelse self.obviousNumericType(binary.right) orelse self.expected_types.get(node.span) orelse return;
        if (!expected.isInteger() and !numeric_surface.isFloat(expected, self.catalog.records)) return;
        try self.hint(binary.left, expected);
        try self.hint(binary.right, expected);
    }
    fn expressionExpected(self: *Checker, id: ast.NodeId, expected: typed.Type) Error!typed.NodeId {
        try self.hint(id, expected);
        return self.expression(id);
    }
    fn resultConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.src.text(call.name);
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        if (std.mem.eql(u8, name, "Ok")) return true;
        if (std.mem.eql(u8, name, "Err")) return false;
        return null;
    }
    fn numericConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.src.text(call.name);
        const floating = std.mem.eql(u8, name, "float");
        if (!floating and !std.mem.eql(u8, name, "int")) return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        return floating;
    }
    fn checkNumericConversion(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), floating: bool, out: *typed.Node) Error!void {
        const value = self.resolved[@backingInt(call.arguments[0])].?;
        const ty_value = self.nodes.items[@backingInt(value)].ty;
        const input_float = numeric_surface.isFloat(ty_value, self.catalog.records);
        if (!input_float and !ty_value.isInteger()) return self.sink.fail("E_TYPE", node.span, "numeric conversion requires an integer or float");
        if (floating) {
            out.* = if (input_float) self.nodes.items[@backingInt(value)] else try self.numericBuilder(node.span).fromInteger(value);
        } else if (input_float) {
            out.* = try self.numericBuilder(node.span).toInteger(value);
        } else out.* = .{ .span = node.span, .ty = .i64, .data = .{ .cast = value } };
    }
    fn optionConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
        if (call.owner != null or call.type_arguments.len != 0 or !std.mem.eql(u8, self.src.text(call.name), "Some")) return false;
        if (self.active.contains("Some") or self.functions.contains("Some")) return false;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
        return true;
    }
    fn expectedOption(self: *Checker, node: ast.Node) Error!struct { ty: typed.Type, shape: prelude.OptionShape } {
        const expected = self.expected_types.get(node.span) orelse return self.sink.fail("E_OPTION_INFERENCE", node.span, "Some requires an expected Option type");
        const shape = prelude.optionShape(expected, self.catalog.records) orelse return self.sink.fail("E_TYPE", node.span, "Some requires an expected Option type");
        return .{ .ty = expected, .shape = shape };
    }
    fn checkOptionConstructor(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        const expected = try self.expectedOption(node);
        const value = self.resolved[@backingInt(call.arguments[0])].?;
        try self.require(self.nodes.items[@backingInt(value)].ty, expected.shape.element, node.span);
        out.* = .{ .span = node.span, .ty = expected.ty, .data = .{ .variant = .{ .tag = expected.shape.some, .value = value } } };
    }
    fn checkUnit(self: *Checker, node: ast.Node) typed.Node {
        if (self.expected_types.get(node.span)) |expected| if (prelude.optionShape(expected, self.catalog.records)) |shape| {
            return .{ .span = node.span, .ty = expected, .data = .{ .variant = .{ .tag = shape.none, .value = null } } };
        };
        return .{ .span = node.span, .ty = .unit, .data = .unit };
    }
    fn expectedResult(self: *Checker, node: ast.Node) Error!typed.Type {
        const expected = self.expected_types.get(node.span) orelse return self.sink.fail("E_RESULT_INFERENCE", node.span, "Ok and Err require a Result type from a binding, return, argument, or field");
        if (typed.resultShape(expected, self.catalog.records) == null) return self.sink.fail("E_TYPE", node.span, "Ok and Err require an expected Result type");
        return expected;
    }
    fn checkResultConstructor(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), ok: bool, out: *typed.Node) Error!void {
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "Ok and Err require one payload");
        out.ty = try self.expectedResult(node);
        const shape = typed.resultShape(out.ty, self.catalog.records).?;
        const value = self.resolved[@backingInt(call.arguments[0])].?;
        try self.require(self.nodes.items[@backingInt(value)].ty, if (ok) shape.ok_type else shape.error_type, node.span);
        out.data = .{ .variant = .{ .tag = if (ok) shape.ok_tag else shape.error_tag, .value = value } };
    }
    fn collectionSyntax(self: *Checker, id: ast.NodeId) Error!ast.Node {
        var node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data == .call) {
            const call = node.data.call;
            if (call.owner) |owner| if (try self.arenaBinding(owner)) {
                try call_arguments.positional(call, self.sink);
                if (!std.mem.eql(u8, self.src.text(call.name), "escape")) return self.sink.fail(eArenaBinding, call.name, "an arena binding supports only `escape(value)`");
                if (call.type_arguments.len != 0 or call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "escape requires exactly one value argument");
                node.data = .{ .arena_escape = .{ .arena = owner, .value = call.arguments[0] } };
                return node;
            };
            if (try @import("record_calls.zig").lower(self.allocator, self.src, self.catalog, call, self.sink)) |record| {
                node.data = record.data;
                return node;
            }
            if (call.owner) |owner| if (self.active.get(self.src.text(owner))) |slot| {
                const value_type = self.locals.items[@backingInt(slot)].ty;
                if (value_type.isAggregate() and self.catalog.records[value_type.recordIndex()].managed) {
                    try call_arguments.positional(call, self.sink);
                    const name = self.src.text(call.name);
                    const kind = buffer_operations.method(name) orelse
                        return self.sink.fail("E_LIST_METHOD", call.name, "unknown managed collection method");
                    if (call.type_arguments.len != 0 or call.arguments.len != kind.arity()) return self.sink.fail("E_ARITY", node.span, "list method argument count does not match its signature");
                    node.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .result = null, .arguments = call.arguments } };
                }
            };
        }
        if (node.data == .field) {
            const field = node.data.field;
            const base = self.syntax.nodes.items[@backingInt(field.base)];
            if (base.data == .name and !self.active.contains(self.src.text(base.data.name))) {
                if (try self.catalog.variantType(self.src, base.data.name, self.sink) != null)
                    node.data = .{ .variant = .{ .ty = base.data.name, .name = field.name, .value = null } };
            }
        }
        return node;
    }
    fn listElement(self: *Checker, ty_value: typed.Type, span: source.Span) Error!typed.Type {
        if (!ty_value.isAggregate() or !self.catalog.records[ty_value.recordIndex()].managed) return self.sink.fail(eListType, span, needs_list);
        if (self.catalog.records[ty_value.recordIndex()].collection.kind != .list) return self.sink.fail(eListType, span, needs_list);
        return self.catalog.records[ty_value.recordIndex()].shape.buffer orelse return self.sink.fail(eListType, span, needs_list);
    }
    fn checkFieldAssignment(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const assignment = node.data.field_assignment;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        var path_fields: std.ArrayList(source.Span) = .empty;
        var root = assignment.target;
        while (self.syntax.nodes.items[@backingInt(root)].data == .field) {
            const field = self.syntax.nodes.items[@backingInt(root)].data.field;
            try path_fields.append(self.allocator, field.name);
            root = field.base;
        }
        const root_node = self.syntax.nodes.items[@backingInt(root)];
        var statements: std.ArrayList(typed.StatementId) = .empty;
        const destination = try self.fieldDestination(root_node, &statements, temporaries);
        var value = destination.value;
        const bases = try self.allocator.alloc(typed.NodeId, path_fields.items.len);
        const indices = try self.allocator.alloc(usize, path_fields.items.len);
        for (0..path_fields.items.len) |i| {
            const name = path_fields.items[path_fields.items.len - i - 1];
            const ty_value = self.nodes.items[@backingInt(value)].ty;
            const schema = try self.catalog.record(ty_value, name, self.sink);
            if (self.transfers(ty_value)) return self.sink.fail(eResultOperation, name, "field assignment requires a copyable record without pending results");
            const field = try self.catalog.field(ty_value, self.src, name, self.sink);
            bases[i] = value;
            indices[i] = field;
            value = try b.node(schema.fields[field].ty, .{ .field = .{ .base = value, .index = field } });
        }
        const expected = self.nodes.items[@backingInt(value)].ty;
        try self.hint(assignment.value, expected);
        value = try self.expressionWithTemporaries(assignment.value, false, temporaries);
        try self.require(self.nodes.items[@backingInt(value)].ty, expected, node.span);
        if (destination.index == null) try self.requireArenaStore(destination.owner, value);
        const assigned = try b.local(expected);
        const evaluate_value = try b.stmt(.{ .initialize = .{ .slot = assigned, .value = value } });
        if (self.python_assignment_order) try statements.insert(self.allocator, 0, evaluate_value) else try statements.append(self.allocator, evaluate_value);
        // Preserve unrelated fields changed through aliases while computing the RHS.
        try statements.append(self.allocator, destination.refresh);
        value = try b.read(assigned);
        var i = bases.len;
        while (i > 0) {
            i -= 1;
            value = try b.node(self.nodes.items[@backingInt(bases[i])].ty, .{ .update = .{
                .base = bases[i],
                .fields = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = indices[i], .value = value }}),
            } });
        }
        const write = if (destination.index) |index|
            try b.stmt(.{ .discard = try b.operation(destination.owner, .write, &.{ index, value }) })
        else
            try b.stmt(.{ .assign = .{ .slot = destination.owner, .value = value } });
        try statements.append(self.allocator, write);
        return b.block(statements.items, try b.node(.unit, .unit));
    }
    fn fieldDestination(self: *Checker, root: ast.Node, statements: *std.ArrayList(typed.StatementId), temporaries: []const typed.Type) Error!FieldDestination {
        const b: collections.Builder(Checker) = .{ .checker = self, .span = root.span };
        if (root.data == .name) {
            const owner = try self.resolve(root.data.name);
            try self.ownerAccess(owner, true, root.span);
            if (!self.locals.items[@backingInt(owner)].mutable) return self.sink.fail(eImmutable, root.span, "record field assignment requires a mutable binding");
            self.locals.items[@backingInt(owner)].usage.writes += 1;
            self.locals.items[@backingInt(owner)].usage.reads += 1;
            const saved = try b.local(self.locals.items[@backingInt(owner)].ty);
            const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = try b.read(owner) } });
            try statements.append(self.allocator, refresh);
            return .{ .owner = owner, .index = null, .value = try b.read(saved), .refresh = refresh };
        }
        if (root.data != .index) return self.sink.fail("E_ASSIGNMENT_TARGET", root.span, "field assignment requires a mutable local record or list slot");
        const access = root.data.index;
        const base = try self.expressionWithTemporaries(access.base, false, temporaries);
        const ty_value = self.nodes.items[@backingInt(base)].ty;
        if (!ty_value.isAggregate() or !self.catalog.records[ty_value.recordIndex()].managed) return self.sink.fail(eCollectionMethod, root.span, "indexed field assignment requires a list or dictionary");
        const schema = self.catalog.records[ty_value.recordIndex()];
        if (schema.collection.kind == .string) return self.sink.fail(eCollectionMethod, root.span, "strings are immutable");
        const element = schema.shape.buffer.?;
        const owner = try b.local(ty_value);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = base } }));
        const index_value = try self.expressionWithTemporaries(access.index, false, temporaries);
        const dictionary = self.catalog.records[ty_value.recordIndex()].collection.kind == .dictionary;
        const key_type = if (dictionary) self.catalog.records[ty_value.recordIndex()].collection.key.? else typed.Type.i64;
        const index_slot = try b.local(key_type);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = index_slot, .value = if (dictionary) index_value else try b.index(owner, index_value, false) } }));
        const index = try b.read(index_slot);
        const saved = try b.local(element);
        const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = try b.operation(owner, .read, &.{index}) } });
        try statements.append(self.allocator, refresh);
        return .{ .owner = owner, .index = index, .value = try b.read(saved), .refresh = refresh };
    }
    fn checkListLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
        var expected = self.expected_types.get(node.span);
        var element: ?typed.Type = if (expected) |ty_value| try self.listElement(ty_value, node.span) else null;
        if (inputs.len == 0 and expected == null) return self.sink.fail("E_LIST_INFERENCE", node.span, "empty list requires an expected List type");
        const values = try self.allocator.alloc(typed.NodeId, inputs.len);
        for (inputs, values) |input, *value| {
            if (element) |ty_value| try self.hint(input, ty_value);
            value.* = try self.expressionWithTemporaries(input, false, temporaries);
            const actual = self.nodes.items[@backingInt(value.*)].ty;
            if (element) |ty_value| try self.require(actual, ty_value, self.syntax.nodes.items[@backingInt(input)].span) else element = actual;
        }
        if (expected == null) expected = try collections.listType(&self.catalog, element.?, node.span);
        if (!typed.storable(element.?, self.catalog.records) or typed.moveOnly(element.?, self.catalog.records) or self.requiresHandling(element.?))
            return self.sink.fail(eListType, node.span, "list elements require copyable storable values without pending results");
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).literal(expected.?, values);
    }
    fn checkCollectionMethod(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const call = node.data.method_call;
        const name = self.src.text(call.name);
        const kind = buffer_operations.method(name) orelse return self.sink.fail("E_COLLECTION_METHOD", call.name, "unknown managed collection method");
        return self.checkListAccess(node, .{ .base = call.base, .kind = kind, .inputs = call.arguments }, temporaries);
    }
    fn checkCollectionSlice(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const slice = node.data.slice;
        const base = try self.expressionWithTemporaries(slice.base, false, temporaries);
        const input = self.nodes.items[@backingInt(base)].ty;
        if (!input.isAggregate() or !self.catalog.records[input.recordIndex()].managed) return self.sink.fail(eCollectionMethod, node.span, "slicing requires a list or str");
        const schema = self.catalog.records[input.recordIndex()];
        if (schema.collection.kind == .dictionary) return self.sink.fail(eCollectionMethod, node.span, "dictionary keys do not support slices");
        const start = if (slice.start) |value| try self.expressionWithTemporaries(value, false, temporaries) else null;
        const end = if (slice.end) |value| try self.expressionWithTemporaries(value, false, temporaries) else null;
        if (start) |value| try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
        if (end) |value| try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        return if (schema.collection.kind == .string) b.textSlice(base, start, end) else b.slice(base, start, end);
    }
    fn checkListAccess(self: *Checker, node: ast.Node, operation: struct { base: ast.NodeId, kind: BufferKind, inputs: []const ast.NodeId, signed_length: bool = false }, temporaries: []const typed.Type) Error!typed.Node {
        const base_input = operation.base;
        const kind = operation.kind;
        const inputs = operation.inputs;
        const base = try self.expressionWithTemporaries(base_input, false, temporaries);
        const owner_type = self.nodes.items[@backingInt(base)].ty;
        if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].collection.kind != .list) {
            const receiver = self.arenaReceiver(base_input);
            return self.checkManagedAccess(node, .{ .base = base, .kind = kind, .inputs = inputs, .receiver = receiver }, temporaries);
        }
        const supported = switch (kind) {
            .append, .read, .write, .length, .contains => true,
            else => false,
        };
        if (!supported) return self.sink.fail(eCollectionMethod, node.span, "operation is not supported by lists");
        const element = try self.listElement(self.nodes.items[@backingInt(base)].ty, node.span);
        if (inputs.len != kind.arity()) return self.sink.fail("E_ARITY", node.span, "collection method argument count differs from its signature");
        const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
        for (inputs, arguments, 0..) |input, *argument, i| {
            const writes_element = kind == .append or kind == .contains or (kind == .write and i == 1);
            if (writes_element) try self.hint(input, element);
            argument.* = try self.expressionWithTemporaries(input, false, temporaries);
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            if (writes_element) try self.require(actual, element, node.span) else try self.requireInteger(actual, node.span);
        }
        try self.requireArenaOperation(self.arenaReceiver(base_input), kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span, .python_assignment_order = self.python_assignment_order }).access(base, kind, arguments, operation.signed_length);
    }
    fn checkManagedAccess(self: *Checker, node: ast.Node, operation: struct { base: typed.NodeId, kind: BufferKind, inputs: []const ast.NodeId, receiver: ?typed.LocalId = null }, temporaries: []const typed.Type) Error!typed.Node {
        const owner_type = self.nodes.items[@backingInt(operation.base)].ty;
        const schema = self.catalog.records[owner_type.recordIndex()];
        const dictionary = schema.collection.kind == .dictionary;
        _ = collections.operationType(&self.catalog, owner_type, operation.kind, node.span) catch |err| switch (err) {
            error.InternalError => return self.sink.fail(eCollectionMethod, node.span, "operation is not supported by this collection"),
            else => return err,
        };
        if (operation.inputs.len != operation.kind.arity()) return self.sink.fail("E_ARITY", node.span, "collection method argument count differs from its signature");
        const arguments = try self.allocator.alloc(typed.NodeId, operation.inputs.len);
        for (operation.inputs, arguments, 0..) |input, *argument, index| {
            const integer = !dictionary and (operation.kind == .read or operation.kind == .slice);
            const expected = if (integer) typed.Type.i64 else if (dictionary) map_argument: {
                break :map_argument if (index == 0) schema.collection.key.? else schema.shape.buffer.?;
            } else if (operation.kind == .join) try self.collectionListType(owner_type, node.span) else owner_type;
            try self.hint(input, expected);
            argument.* = try self.expressionWithTemporaries(input, false, temporaries);
            if (integer) try self.requireInteger(self.nodes.items[@backingInt(argument.*)].ty, node.span) else try self.require(self.nodes.items[@backingInt(argument.*)].ty, expected, node.span);
        }
        try self.requireArenaOperation(operation.receiver, operation.kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span, .python_assignment_order = self.python_assignment_order }).access(operation.base, operation.kind, arguments, false);
    }
    fn hintBufferArguments(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation)) Error!void {
        if (self.active.get(self.src.text(operation.owner))) |slot| {
            const owner_type = self.locals.items[@backingInt(slot)].ty;
            if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].collection.kind != .list) {
                const schema = self.catalog.records[owner_type.recordIndex()];
                if (schema.collection.kind == .dictionary) {
                    if (operation.arguments.len > 0) try self.hint(operation.arguments[0], schema.collection.key.?);
                    if (operation.arguments.len == 2) try self.hint(operation.arguments[1], schema.shape.buffer.?);
                } else if ((operation.kind == .split or operation.kind == .contains) and operation.arguments.len == 1) try self.hint(operation.arguments[0], owner_type);
                return;
            }
            if (owner_type.isAggregate()) if (self.catalog.records[owner_type.recordIndex()].shape.buffer) |element| {
                if (operation.kind == .append and operation.arguments.len == 1) try self.hint(operation.arguments[0], element);
                if (operation.kind == .write and operation.arguments.len == 2) try self.hint(operation.arguments[1], element);
            };
        }
    }
    fn hintRecordFields(self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record")) Error!void {
        const record_type = try self.ty(record.name);
        const schema = try self.catalog.constructor(record_type, record.name, self.sink);
        for (record.fields) |field| {
            const index = if (schema.tableKey()) |key| try self.catalog.variant(key, self.src, field.name, self.sink) else try self.catalog.field(schema.id, self.src, field.name, self.sink);
            try self.hint(field.value, schema.fields[index].ty);
        }
    }
    fn hintCallArguments(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), declaration: instances.DeclarationId, target: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!void {
        const signature = self.syntax.functions[@backingInt(declaration)].signature;
        const function = if (signature.type_parameters.len == 0) self.ordinary_ids[@backingInt(declaration)] else if (target.type_arguments.len != 0) try self.specialize(declaration, target, span) else null;
        for (call.arguments, signature.parameters) |argument, parameter| {
            if (parameter.reference != null) continue;
            if (function) |function_id| {
                try self.hint(argument, try self.functionType(function_id, parameter.ty));
            } else if (self.catalog.arrays.resolved.get(parameter.ty.start)) |closed| {
                try self.hint(argument, closed);
            } else if (typed.Type.fromName(self.src.text(parameter.ty))) |closed| {
                try self.hint(argument, closed);
            }
        }
    }
    fn queueBuiltinCall(self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call"), node: ast.Node) Error!bool {
        if (try self.numericConversion(call) != null) {
            try call_arguments.positional(call, self.sink);
            if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "numeric conversions require one argument");
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
    fn queueDictionary(self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId) Error!bool {
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
            };
            try work.append(self.allocator, .{ .id = entries[index] });
        }
        return true;
    }
    fn queueVariant(self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId, variant: @FieldType(@FieldType(ast.Node, "data"), "variant")) Error!bool {
        if (variant.value) |value| {
            const variant_type = try self.ty(variant.ty);
            const tag = try self.catalog.variant(variant_type, self.src, variant.name, self.sink);
            if (self.catalog.records[variant_type.recordIndex()].shape.variants.?.cases[tag].payload) |payload| try self.hint(value, payload);
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = value });
            return true;
        }
        return false;
    }
    fn queueExpression(self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId, allow_reference: bool) Error!bool {
        const node = try self.collectionSyntax(id);
        switch (node.data) {
            .pool_operation => |operation| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(self.allocator, .{ .id = operation.arguments[i] });
                }
                return true;
            },
            .buffer_operation => |operation| {
                try self.hintBufferArguments(operation);
                try work.append(self.allocator, .{ .id = id, .emit = true });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(self.allocator, .{ .id = operation.arguments[i] });
                }
                return true;
            },
            .variant => |variant| return self.queueVariant(work, id, variant),
            .array => |array| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                var i = array.values.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(self.allocator, .{ .id = array.values[i] });
                }
                return true;
            },
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
            .acquire_buffer, .acquire_pool => |acquire| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = acquire.value });
                if (!acquire.managed) try work.append(self.allocator, .{ .id = acquire.allocator });
                return true;
            },
            .reset_arena, .cast, .wrap => |cast| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = cast.value });
                return true;
            },
            .arena_escape => |copy| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = copy.value });
                return true;
            },
            .dictionary_literal => return self.queueDictionary(work, id),
            .record => |record| {
                try self.hintRecordFields(record);
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try self.queueFields(work, record.fields);
                return true;
            },
            .update => |update| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try self.queueFields(work, update.fields);
                try work.append(self.allocator, .{ .id = update.base });
                return true;
            },
            .field => |field| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = field.base });
                return true;
            },
            .read_slice => |read| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = read.index });
                return true;
            },
            .call => |call| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                if (try self.queueBuiltinCall(work, call, node)) return true;
                if (call.owner == null and (self.active.contains(self.src.text(call.name)) or source_json.operation(self.src.text(call.name)) != null)) {
                    var index = call.arguments.len;
                    const contract = if (self.active.get(self.src.text(call.name))) |slot| callables.signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) else null;
                    while (index > 0) {
                        index -= 1;
                        if (contract) |signature| if (index < signature.parameters.len and signature.borrows(index)) continue;
                        try work.append(self.allocator, .{ .id = call.arguments[index] });
                    }
                    return true;
                }
                const target = try self.callDeclaration(call, node.span);
                if (target.call.type_arguments.len != 0) _ = try self.specialize(target.declaration, target.call, node.span);
                const signature = self.syntax.functions[@backingInt(target.declaration)];
                try self.hintCallArguments(target.call, target.declaration, target.call, node.span);
                if (signature.signature.return_reference != null and !(allow_reference)) return self.sink.fail(eReferenceResult, node.span, "reference-returning calls require a borrow scope");
                var i = target.call.arguments.len;
                while (i > 0) {
                    i -= 1;
                    const position = call_arguments.parameterPosition(target.call, i);
                    const argument = target.call.arguments[position];
                    const parameter = signature.signature.parameters[position];
                    if (parameter.reference == null or self.syntax.nodes.items[@backingInt(argument)].data == .bytes)
                        try work.append(self.allocator, .{ .id = argument, .default_value = parameter.default_value == argument });
                }
                return true;
            },
            .unary => |u| {
                if (self.expected_types.get(node.span)) |expected| try self.hint(u.operand, expected);
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = u.operand });
                return true;
            },
            .binary => |b| {
                try self.hintBinary(node);
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = b.right, .checkpoint = b.op == .logical_and or b.op == .logical_or });
                try work.append(self.allocator, .{ .id = b.left });
                return true;
            },
            else => {},
        }
        return false;
    }
    fn operationOwner(self: *Checker, span: source.Span, mutable: bool) Error!struct { owner: typed.LocalId, reference: ?typed.ReferenceId } {
        if (self.active_refs.contains(self.src.text(span))) {
            const id = try self.reference(span);
            try self.requireReferenceKind(id, false, span);
            const ref = self.references.items[@backingInt(id)];
            if (mutable and !ref.mutable) return self.sink.fail(eReferenceReadOnly, span, "mutation requires an exclusive owner reference");
            return .{ .owner = ref.owner, .reference = id };
        }
        const owner = try self.resolve(span);
        try self.ownerAccess(owner, mutable, span);
        return .{ .owner = owner, .reference = null };
    }
    fn checkReadField(self: *Checker, node: ast.Node, read: @FieldType(@FieldType(ast.Node, "data"), "read_field"), out: *typed.Node) Error!void {
        const taking = node.data == .take_field;
        const access = try self.operationOwner(read.owner, taking);
        if (taking and access.reference != null) return self.sink.fail("E_FIELD_TAKE", read.owner, "cannot move a field out of a borrowed owner");
        const owner = access.owner;
        const local = &self.locals.items[@backingInt(owner)];
        const field = try self.catalog.field(local.ty, self.src, read.field, self.sink);
        out.ty = self.catalog.records[local.ty.recordIndex()].fields[field].ty;
        if (!taking and self.transfers(out.ty)) return self.sink.fail("E_FIELD_COPY", read.field, "read_field cannot copy owned values or result obligations");
        if (self.transfers(local.ty) and !local.ownership.transfer_available) return self.sink.failTransfer(eOwnedConsumed, read.owner, local.declaration, local.ownership.transfer_span);
        if (taking and !self.transfers(local.ty)) return self.sink.fail("E_FIELD_TAKE", read.owner, "take_field requires an owned or result-bearing record; use read_field for copyable records");
        if (local.ownership.partial_fields.len != 0) {
            if (local.ownership.partial_fields[field]) |at| return self.sink.failMovedField(read.field, local.declaration, at);
        }
        if (taking) local.ownership.partial_fields = try field_moves.take(
            self.allocator,
            local.ownership.partial_fields,
            self.catalog.records[local.ty.recordIndex()].fields.len,
            field,
            read.field,
        );
        local.usage.reads += 1;
        if (self.conversion_fields) |seen| {
            if (@backingInt(owner) == 0) seen[field] = true;
        }
        out.data = if (taking) .{ .take_field = .{ .owner = owner, .field = field } } else .{ .read_field = .{ .reference = access.reference, .owner = owner, .field = field } };
    }
    fn checkPoolOperation(self: *Checker, _: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "pool_operation"), out: *typed.Node) Error!void {
        const access = try self.operationOwner(operation.owner, operation.kind.mutates());
        const owner = access.owner;
        const local = &self.locals.items[@backingInt(owner)];
        if (!local.ty.isAggregate()) return self.sink.fail("E_POOL_TYPE", operation.owner, "operation requires an owned pool binding");
        const pool = self.catalog.records[local.ty.recordIndex()].shape.pool orelse return self.sink.fail("E_POOL_TYPE", operation.owner, "operation requires an owned pool binding");
        if (!local.ownership.transfer_available) return self.sink.failTransfer(eOwnedConsumed, operation.owner, local.declaration, local.ownership.transfer_span);
        if (operation.kind.mutates() and access.reference == null and !local.mutable) return self.sink.fail(eImmutable, operation.owner, "pool mutation requires a let mut binding");
        local.usage.reads += 1;
        if (operation.kind.mutates()) local.usage.writes += 1;
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments, 0..) |input, *argument, argument_index| {
            argument.* = self.resolved[@backingInt(input)].?;
            try self.require(self.nodes.items[@backingInt(argument.*)].ty, if (operation.kind == .insert or argument_index == 1) pool.element else pool.handle, self.syntax.nodes.items[@backingInt(input)].span);
        }
        out.ty = operation.kind.output(pool);
        if (operation.result) |result_type| {
            const result = try self.ty(result_type);
            const shape = typed.resultShape(result, self.catalog.records) orelse return self.sink.fail(ePoolResult, result_type, "pool operation requires a result with the operation's success type and i64 error");
            if (shape.ok_type != out.ty or shape.error_type != .i64) return self.sink.fail(ePoolResult, result_type, "pool operation requires a result with the operation's success type and i64 error");
            out.ty = result;
        }
        out.data = .{ .pool_operation = .{ .reference = access.reference, .kind = operation.kind, .owner = owner, .arguments = arguments } };
    }
    fn collectionListType(self: *Checker, element: typed.Type, span: source.Span) Error!typed.Type {
        const state = self.catalog.templates.store orelse return error.InternalError;
        return @import("nominal_catalog.zig").instantiateLengths(&self.catalog, state.index.names.get("List").?, &.{element}, &.{}, span);
    }
    fn checkTextDictionary(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), access: struct { owner: typed.LocalId, reference: ?typed.ReferenceId }, out: *typed.Node) Error!void {
        const owner = access.owner;
        const local = self.locals.items[@backingInt(owner)];
        const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;

        const schema = self.catalog.records[local.ty.recordIndex()];
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments) |input, *argument| argument.* = self.resolved[@backingInt(input)].?;
        const dictionary = schema.collection.kind == .dictionary;
        const output_element = if (dictionary) element else local.ty;
        switch (operation.kind) {
            .length => out.ty = .i64,
            .read, .write, .get, .contains => {
                if (!dictionary and operation.kind != .read and operation.kind != .contains) return self.sink.fail("E_TEXT_IMMUTABLE", operation.owner, "str values are immutable");
                if (dictionary) {
                    try self.require(self.nodes.items[@backingInt(arguments[0])].ty, schema.collection.key.?, operation.owner);
                } else if (operation.kind == .contains) {
                    try self.require(self.nodes.items[@backingInt(arguments[0])].ty, local.ty, operation.owner);
                } else try self.requireInteger(self.nodes.items[@backingInt(arguments[0])].ty, operation.owner);
                if (arguments.len == 2) try self.require(self.nodes.items[@backingInt(arguments[1])].ty, element, operation.owner);
                out.ty = if (operation.kind == .write) .unit else if (operation.kind == .contains) .bool else output_element;
            },
            .keys, .values => {
                if (!dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "keys and values require a dictionary");
                out.ty = try self.collectionListType(if (operation.kind == .keys) schema.collection.key.? else element, operation.owner);
            },
            .split, .join => {
                if (dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "split and join require str");
                const list_type = try self.collectionListType(local.ty, operation.owner);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, if (operation.kind == .split) local.ty else list_type, operation.owner);
                out.ty = if (operation.kind == .split) list_type else local.ty;
            },
            else => return self.sink.fail(eCollectionMethod, operation.owner, "operation is not supported by this collection"),
        }
        out.data = .{ .buffer_operation = .{ .reference = access.reference, .kind = operation.kind, .owner = owner, .arguments = arguments } };
    }
    fn checkBufferOperation(self: *Checker, _: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), out: *typed.Node) Error!void {
        const initial = try self.operationOwner(operation.owner, false);
        const local = &self.locals.items[@backingInt(initial.owner)];
        const managed = local.ty.isAggregate() and self.catalog.records[local.ty.recordIndex()].managed;
        const access = if (managed) initial else try self.operationOwner(operation.owner, operation.kind.mutates());
        const owner = access.owner;
        if (!local.ty.isAggregate() or self.catalog.records[local.ty.recordIndex()].shape.buffer == null) return self.sink.fail("E_BUFFER_TYPE", operation.owner, "operation requires an owned buffer binding");
        if (!managed and !local.ownership.transfer_available) return self.sink.failTransfer(eOwnedConsumed, operation.owner, local.declaration, local.ownership.transfer_span);
        const needs_mutable_binding = !managed and operation.kind.mutates() and access.reference == null;
        if (needs_mutable_binding and !local.mutable) return self.sink.fail(eImmutable, operation.owner, "buffer mutation requires a let mut binding");
        local.usage.reads += 1;
        if (operation.kind.mutates()) local.usage.writes += 1;
        const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;
        if ((operation.kind == .read or operation.kind == .resize) and typed.moveOnly(element, self.catalog.records)) return self.sink.fail(
            "E_BUFFER_COPY",
            operation.owner,
            "owned buffer elements require take_buffer or truncate_buffer; reads and resize fill would copy ownership",
        );
        if (managed and self.catalog.records[local.ty.recordIndex()].collection.kind != .list) {
            try self.checkTextDictionary(operation, .{ .owner = access.owner, .reference = access.reference }, out);
            return;
        }
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments, 0..) |input, *argument, argument_index| {
            argument.* = self.resolved[@backingInt(input)].?;
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            const span = self.syntax.nodes.items[@backingInt(input)].span;
            const writes_element = argument_index == 1 and (operation.kind == .write or operation.kind == .resize);
            if (operation.kind == .reserve and argument_index == 0) {
                try self.require(actual, .allocator, span);
            } else if (operation.kind == .append or operation.kind == .contains or writes_element) {
                try self.require(actual, element, span);
            } else {
                try self.requireInteger(actual, span);
            }
        }
        try self.requireArenaOperation(if (managed) initial.owner else null, operation.kind, arguments);
        if (managed and operation.result != null) return self.sink.fail(eListType, operation.owner, "managed list mutations return unit without a result type");
        if (operation.result) |result_type| {
            out.ty = try self.ty(result_type);
            const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(
                eBufferResult,
                result_type,
                "buffer mutation result requires matching success and i64 error payloads",
            );
            if (shape.ok_type != (if (operation.kind == .take) element else typed.Type.bool) or shape.error_type != .i64) return self.sink.fail(
                eBufferResult,
                result_type,
                "buffer mutation result requires matching success and i64 error payloads",
            );
        } else {
            if (operation.kind.mutates() and !managed) return self.sink.fail(eListType, operation.owner, "list mutation requires a managed list");
            out.ty = if (operation.kind.mutates()) .unit else if (operation.kind == .read) element else if (operation.kind == .contains) .bool else .u64;
        }
        out.data = .{ .buffer_operation = .{ .reference = access.reference, .kind = operation.kind, .owner = owner, .arguments = arguments } };
    }
    fn checkAcquireResource(self: *Checker, _: ast.Node, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource"), out: *typed.Node) Error!void {
        out.ty = try self.ty(acquire.ty);
        const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceResult, acquire.ty, "acquisition requires a resource success and i64 error result");
        const kind = typed.resourceKind(shape.ok_type, self.catalog.records) orelse return self.sink.fail(eResourceResult, acquire.ty, "acquisition success must be a resource");
        if (shape.error_type != .i64) return self.sink.fail(eResourceResult, acquire.ty, "acquisition error must be i64");
        const capability = self.resolved[@backingInt(acquire.capability)].?;
        const request = self.resolved[@backingInt(acquire.request)].?;
        try self.require(self.nodes.items[@backingInt(capability)].ty, if (kind == .filesystem) .filesystem_cap else .network_cap, self.syntax.nodes.items[@backingInt(acquire.capability)].span);
        const request_type = self.nodes.items[@backingInt(request)].ty;
        if (!typed.acquisitionBytes(request_type, self.catalog.records)) return self.sink.fail("E_RESOURCE_REQUEST", self.syntax.nodes.items[@backingInt(acquire.request)].span, "request must be a fixed u8 array or owned u8 buffer");
        out.data = .{ .acquire_resource = .{ .capability = capability, .request = request } };
    }
    fn checkResourceIo(self: *Checker, node: ast.Node, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io"), out: *typed.Node) Error!void {
        const owner = try self.resolve(io.owner);
        const local = &self.locals.items[@backingInt(owner)];
        if (typed.resourceKind(local.ty, self.catalog.records) == null) return self.sink.fail("E_RESOURCE_TYPE", io.owner, "I/O requires an owned resource binding");
        if (!local.ownership.transfer_available) return self.sink.failTransfer(eOwnedConsumed, io.owner, local.declaration, local.ownership.transfer_span);
        if (!local.mutable) return self.sink.fail(eImmutable, io.owner, "resource I/O requires a let mut binding");
        try self.ownerAccess(owner, true, io.owner);
        const slice_reference = if (io.reference) |name| try self.reference(name) else null;
        if (slice_reference) |id| {
            try self.requireReferenceKind(id, true, io.reference.?);
            const ref = self.references.items[@backingInt(id)];
            try self.require(ref.ty, .u8, io.reference.?);
            if (io.kind == .read and !ref.mutable) return self.sink.fail(eReferenceReadOnly, io.reference.?, "resource reads require an exclusive destination slice");
            if (io.kind == .read) self.locals.items[@backingInt(ref.owner)].usage.writes += 1;
        }
        out.ty = try self.ty(io.ty);
        if (io.kind == .read and slice_reference != null) {
            if (typed.resourceSliceReadShape(out.ty, self.catalog.records) == null) return self.sink.fail(eResourceIoResult, io.ty, "slice read result requires i64 error and record success with length: u64, eof: bool");
        } else if (io.kind == .read) {
            if (typed.resourceReadShape(out.ty, self.catalog.records) == null) return self.sink.fail(eResourceIoResult, io.ty, "read result requires i64 error and record success with bytes: [N]u8, length: u64, eof: bool");
        } else {
            const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eResourceIoResult, io.ty, "write result requires u64 success and i64 error");
            if (shape.ok_type != .u64 or shape.error_type != .i64) return self.sink.fail(eResourceIoResult, io.ty, "write result requires u64 success and i64 error");
        }
        const value = if (io.value) |input| self.resolved[@backingInt(input)].? else null;
        if (value) |input| if (!typed.byteRequest(self.nodes.items[@backingInt(input)].ty, self.catalog.records)) return self.sink.fail("E_RESOURCE_BYTES", node.span, "write input must be a fixed u8 array");
        local.usage.reads += 1;
        local.usage.writes += 1;
        out.data = .{ .resource_io = .{ .kind = io.kind, .owner = owner, .value = value, .reference = slice_reference } };
    }
    fn checkAcquireBuffer(self: *Checker, node: ast.Node, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_buffer"), out: *typed.Node) Error!void {
        const inferred = acquire.managed and acquire.ty.start == acquire.ty.end;
        out.ty = if (inferred) self.expected_types.get(node.span) orelse return self.sink.fail("E_LIST_INFERENCE", node.span, "empty list requires an expected List type") else try self.ty(acquire.ty);
        const is_pool = node.data == .acquire_pool;
        const code: []const u8 = if (is_pool) ePoolResult else eBufferResult;
        const message: []const u8 = if (is_pool) "pool acquisition requires a pool success and i64 error result" else "buffer acquisition requires a buffer success and i64 error result";
        if (acquire.managed) {
            if (!out.ty.isAggregate() or !self.catalog.records[out.ty.recordIndex()].managed) return self.sink.fail(eListType, acquire.ty, "new_list requires a managed list type");
        } else {
            const acquired = typed.acquisitionShape(out.ty, self.catalog.records, is_pool) orelse return self.sink.fail(code, acquire.ty, message);
            if (self.catalog.records[acquired.ok_type.recordIndex()].managed) return self.sink.fail(eListType, acquire.ty, "managed lists require new_list");
        }
        var capacity = self.resolved[@backingInt(acquire.value)].?;
        if (inferred) {
            capacity = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .u64, .data = .{ .integer = 0 } });
        }
        try self.requireInteger(self.nodes.items[@backingInt(capacity)].ty, node.span);
        const authority = self.resolved[@backingInt(acquire.allocator)].?;
        if (!acquire.managed) try self.require(self.nodes.items[@backingInt(authority)].ty, .allocator, self.syntax.nodes.items[@backingInt(acquire.allocator)].span);
        out.data = if (is_pool) .{ .acquire_pool = .{ .allocator = authority, .capacity = capacity } } else .{ .acquire_buffer = .{ .allocator = authority, .capacity = capacity, .managed = acquire.managed } };
    }
    fn checkArray(self: *Checker, node: ast.Node, array: @FieldType(@FieldType(ast.Node, "data"), "array"), out: *typed.Node) Error!void {
        out.ty = try self.ty(array.ty);
        const schema = try self.catalog.array(out.ty, array.ty, self.sink);
        if (schema.key != null) return self.sink.fail("E_TABLE_CONSTRUCTION", node.span, "enum-indexed tables require named initializers for every enum case");
        if (array.values.len != schema.length) return self.sink.fail("E_ARRAY_ARITY", node.span, "array construction must initialize exactly its declared number of elements");
        const values = try self.allocator.alloc(typed.NodeId, array.values.len);
        for (array.values, values) |input, *value| {
            value.* = self.resolved[@backingInt(input)].?;
            try self.require(self.nodes.items[@backingInt(value.*)].ty, schema.element, self.syntax.nodes.items[@backingInt(input)].span);
        }
        out.data = .{ .array = values };
    }
    fn checkField(self: *Checker, node: ast.Node, field: @FieldType(@FieldType(ast.Node, "data"), "field"), out: *typed.Node) Error!void {
        const base = self.resolved[@backingInt(field.base)].?;
        const record_type = self.nodes.items[@backingInt(base)].ty;
        const field_index = try self.catalog.field(record_type, self.src, field.name, self.sink);
        for (self.catalog.records[record_type.recordIndex()].fields, 0..) |other, i| if (i != field_index and self.requiresHandling(other.ty)) return self.sink.fail(
            eResultOperation,
            node.span,
            "projection would drop another result-bearing field; transfer or acknowledge the whole record",
        );
        if (self.conversion_fields) |seen| {
            const base_node = self.nodes.items[@backingInt(base)];
            if (base_node.data == .local and @backingInt(base_node.data.local) == 0) seen[field_index] = true;
        }
        out.ty = self.catalog.records[record_type.recordIndex()].fields[field_index].ty;
        out.data = .{ .field = .{ .base = base, .index = field_index } };
    }
    fn functionValue(self: *Checker, name: source.Span, out: *typed.Node) Error!bool {
        const key = if (self.catalog.module_names) |names| module: {
            if (!try names.topLevel(name) and std.mem.indexOf(u8, self.src.text(name), "::") == null) return false;
            break :module try names.reference(name, .function, null, null, self.sink);
        } else self.src.text(name);
        const declaration = self.functions.get(key) orelse return false;
        const function = self.syntax.functions[@backingInt(declaration)];
        if (function.policy.owner != null or function.signature.type_parameters.len != 0) return self.sink.fail(callback_type_code, name, "function values require a nongeneric free function");
        if (function.signature.return_reference != null) return self.sink.fail(callback_type_code, name, "callback values cannot return borrowed references");
        const bound = function.policy.effect_bound orelse return self.sink.fail("E_CALLBACK_EFFECTS", name, "function values require a declared effect ceiling");
        const parameters = try self.allocator.alloc(typed.Type, function.signature.parameters.len);
        var borrowed: u16 = 0;
        var slices: u16 = 0;
        if (parameters.len > 16) return self.sink.fail(callback_type_code, name, "callbacks support at most 16 parameters");
        for (function.signature.parameters, parameters, 0..) |input, *parameter, i| {
            if (input.reference == true) return self.sink.fail(callback_type_code, name, "callback context parameters are readonly borrows");
            const bit = @as(u16, 1) << @as(u4, @intCast(i));
            if (input.reference != null) borrowed |= bit;
            if (input.slice) slices |= bit;
            parameter.* = try self.catalog.resolve(self.src, input.ty, self.sink);
        }
        const result = try self.catalog.resolve(self.src, function.signature.return_type, self.sink);
        out.ty = try callables.intern(self.allocator, &self.catalog, .{ .parameters = parameters, .return_type = result, .effects = bound.allowed, .borrowed = borrowed, .slices = slices }, name, self.sink);
        out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
        return true;
    }
    fn indirectCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        const slot = try self.resolve(call.name);
        const contract = callables.signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) orelse return self.sink.fail(callback_type_code, call.name, "called local is not a function value");
        if (call.type_arguments.len != 0 or call.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", call.name, "callback argument count must match its signature");
        try self.ownerAccess(slot, false, call.name);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const callee: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = call.name, .ty = self.locals.items[@backingInt(slot)].ty, .data = .{ .local = slot } });
        var arguments: std.ArrayList(typed.NodeId) = .empty;
        var loans: std.ArrayList(typed.ReferenceId) = .empty;
        for (call.arguments, contract.parameters, 0..) |input, expected, i| {
            const argument = self.syntax.nodes.items[@backingInt(input)];
            if (contract.borrows(i)) {
                if (argument.data != .name) return self.sink.fail(eReferenceArgument, argument.span, "callback context requires an active reference name");
                const id = try self.reference(argument.data.name);
                try self.requireReferenceKind(id, contract.slice(i), argument.span);
                try self.require(self.references.items[@backingInt(id)].ty, expected, argument.span);
                const ref = self.references.items[@backingInt(id)];
                for (loans.items) |previous_id| {
                    const previous = self.references.items[@backingInt(previous_id)];
                    const overlap = previous.owner == ref.owner and !typed.disjointReferences(self.references.items, previous_id, id);
                    if (overlap and (previous.mutable or ref.mutable))
                        return self.sink.fail(eBorrowConflict, argument.span, "callback contexts cannot alias exclusive access");
                }
                try loans.append(self.allocator, id);
            } else {
                const value = self.resolved[@backingInt(input)].?;
                try self.require(self.nodes.items[@backingInt(value)].ty, expected, node.span);
                try arguments.append(self.allocator, value);
            }
        }
        out.ty = contract.return_type;
        out.data = .{ .invoke = .{ .callee = callee, .arguments = try arguments.toOwnedSlice(self.allocator), .references = try loans.toOwnedSlice(self.allocator) } };
    }
    fn checkName(self: *Checker, _: ast.Node, name: @FieldType(@FieldType(ast.Node, "data"), "name"), out: *typed.Node) Error!void {
        if (self.current_function) |id| {
            const key = self.instance_keys.items[@backingInt(id)];
            for (self.syntaxFunction(id).signature.type_parameters, 0..) |parameter, index| {
                if (!parameter.constant_length or !std.mem.eql(u8, self.src.text(parameter.name), self.src.text(name))) continue;
                out.ty = .u64;
                out.data = .{ .integer = key.length(index) orelse return error.InternalError };
                return;
            }
        }
        if (self.active_refs.contains(self.src.text(name))) return self.sink.fail("E_REFERENCE_VALUE", name, "references cannot be copied, stored, returned, or passed to value parameters; use read_ref to copy the referenced value");
        for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, self.src.text(name))) return self.sink.fail(
            eArenaBinding,
            name,
            "an arena binding is opaque; it cannot be stored, passed, returned or compared, and its only operation is `escape(value)`",
        );
        if (!self.active.contains(self.src.text(name))) {
            const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
            if (try constants.lookup(name)) |index| {
                const value = try constants.evaluate(index);
                out.ty = value.typeOf();
                out.data = .{ .call = .{ .function = self.ordinary_ids[index] orelse return error.InternalError, .arguments = &.{} } };
                return;
            }
        }
        if (!self.active.contains(self.src.text(name)) and try self.functionValue(name, out)) return;
        const slot = try self.resolve(name);
        if (field_moves.first(self.locals.items[@backingInt(slot)].ownership.partial_fields)) |at| return self.sink.failPartialMove(
            name,
            self.locals.items[@backingInt(slot)].declaration,
            at,
        );
        if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
            const local = &self.locals.items[@backingInt(slot)];
            if (!local.ownership.transfer_available) return self.sink.failTransfer(
                if (typed.moveOnly(local.ty, self.catalog.records)) eOwnedConsumed else "E_RESULT_CONSUMED",
                name,
                local.declaration,
                local.ownership.transfer_span,
            );
            local.ownership.transfer_available = false;
            local.ownership.transfer_span = name;
        }
        try self.ownerAccess(slot, self.transfers(self.locals.items[@backingInt(slot)].ty), name);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        out.ty = self.locals.items[@backingInt(slot)].ty;
        out.data = .{ .local = slot };
    }
    fn textConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!bool {
        if (call.owner != null or !std.mem.eql(u8, self.src.text(call.name), "str")) return false;
        if (self.active.contains("str") or self.functions.contains("str")) return false;
        const text_type = self.catalog.names.get("str") orelse return false;
        if (self.catalog.records[text_type.recordIndex()].collection.kind != .string) return false;
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", span, "str conversion requires one argument");
        return true;
    }
    fn checkCall(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        if (try self.numericConversion(input)) |floating| return self.checkNumericConversion(node, input, floating, out);
        if (try self.optionConstructor(input)) return self.checkOptionConstructor(node, input, out);
        if (try self.textConstructor(input, node.span)) {
            const value = self.resolved[@backingInt(input.arguments[0])].?;
            const input_type = self.nodes.items[@backingInt(value)].ty;
            const aggregate_scalar = input_type.isAggregate() and (self.catalog.records[input_type.recordIndex()].collection.kind == .string or std.mem.eql(u8, self.catalog.records[input_type.recordIndex()].name, "float"));
            const scalar = input_type.isInteger() or input_type == .bool or input_type == .unit;
            if (!scalar and !aggregate_scalar) return self.sink.fail("E_TEXT_CONVERSION", node.span, "str conversion requires a scalar or str value");
            out.ty = self.catalog.names.get("str") orelse return error.InternalError;
            out.data = .{ .cast = value };
            return;
        }
        if (try self.resultConstructor(input)) |ok| {
            try call_arguments.positional(input, self.sink);
            return self.checkResultConstructor(node, input, ok, out);
        }
        if (input.owner == null and self.active.contains(self.src.text(input.name))) {
            try call_arguments.positional(input, self.sink);
            return self.indirectCall(node, input, out);
        }
        if (input.owner == null) if (source_json.operation(self.src.text(input.name))) |decode| {
            try call_arguments.positional(input, self.sink);
            return self.checkJson(input, decode, out);
        };
        const target = try self.callDeclaration(input, node.span);
        const call = target.call;
        const function = try self.specialize(target.declaration, call, node.span);
        const signature = self.syntaxFunction(function);
        var arguments: std.ArrayList(typed.NodeId) = .empty;
        var loans: std.ArrayList(typed.ReferenceId) = .empty;
        var literals: std.ArrayList(typed.LiteralArgument) = .empty;
        for (call.arguments, signature.signature.parameters) |arg, parameter| {
            const argument = self.syntax.nodes.items[@backingInt(arg)];
            if (parameter.reference) |mutable| {
                if (argument.data == .bytes) {
                    if (mutable or !parameter.slice or try self.functionType(function, parameter.ty) != .u8)
                        return self.sink.fail(eReferenceArgument, argument.span, "byte literals require a readonly u8 slice parameter");
                    if (signature.signature.return_reference != null)
                        return self.sink.fail(eReferenceArgument, argument.span, "a call borrowing a byte literal cannot return a reference");
                    const temporary = try self.literalArgument(arg, argument.span);
                    try loans.append(self.allocator, temporary.reference);
                    try literals.append(self.allocator, temporary);
                    continue;
                }
                if (argument.data != .name) return self.sink.fail(eReferenceArgument, argument.span, "reference parameter requires an active reference name");
                const id = try self.reference(argument.data.name);
                const ref = self.references.items[@backingInt(id)];
                try self.requireReferenceKind(id, parameter.slice, argument.span);
                if (mutable and !ref.mutable) return self.sink.fail(eReferenceReadOnly, argument.span, "exclusive parameter requires an exclusive reference");
                try self.require(ref.ty, try self.functionType(function, parameter.ty), argument.span);
                for (loans.items) |previous_id| {
                    const previous = self.references.items[@backingInt(previous_id)];
                    const exclusive = previous.mutable or ref.mutable;
                    if (previous.owner == ref.owner and exclusive and !typed.disjointReferences(self.references.items, previous_id, id)) return self.sink.failRelated(
                        eBorrowConflict,
                        argument.span,
                        "call arguments cannot reborrow overlapping exclusive access",
                        .{
                            .span = previous.declaration,
                            .message = "conflicting reference declared here",
                        },
                    );
                }
                try loans.append(self.allocator, id);
            } else {
                const value = self.resolved[@backingInt(arg)].?;
                try self.require(self.nodes.items[@backingInt(value)].ty, try self.functionType(function, parameter.ty), argument.span);
                try arguments.append(self.allocator, value);
            }
        }
        out.ty = try self.functionType(function, signature.signature.return_type);
        out.data = .{ .call = .{ .function = function, .arguments = try arguments.toOwnedSlice(self.allocator), .references = try loans.toOwnedSlice(self.allocator), .literals = try literals.toOwnedSlice(self.allocator) } };
        try (@import("call_evaluation.zig").Context{
            .storage = .{ .nodes = &self.nodes, .locals = &self.locals, .statements = &self.statements },
            .span = node.span,
            .call = call,
            .parameters = signature.signature.parameters,
            .arena_depth = self.arena_depth,
        }).apply(self.allocator, &out.data.call);
    }
    fn literalArgument(self: *Checker, arg: ast.NodeId, span: source.Span) Error!typed.LiteralArgument {
        const value = self.resolved[@backingInt(arg)].?;
        const value_type = self.nodes.items[@backingInt(value)].ty;
        const owner: typed.LocalId = @fromBackingInt(self.locals.items.len);
        const reference_id: typed.ReferenceId = @fromBackingInt(self.references.items.len);
        try self.locals.append(self.allocator, .{ .name = "<literal>", .declaration = span, .ty = value_type, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
        try self.references.append(self.allocator, .{ .name = "<literal>", .declaration = span, .owner = owner, .parent = null, .ty = .u8, .mutable = false, .mode = .{ .slice = true, .temporary = true } });
        return .{ .value = value, .owner = owner, .reference = reference_id, .length = self.catalog.records[value_type.recordIndex()].shape.array.?.length };
    }
    fn checkJson(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), decode: bool, out: *typed.Node) Error!void {
        if (call.type_arguments.len != 1 or call.arguments.len != 3) return self.sink.fail("E_JSON_ARITY", call.name, "JSON operation requires one result type and allocator, value, byte-limit arguments");
        out.ty = try self.ty(call.type_arguments[0]);
        const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail("E_JSON_RESULT", call.name, "JSON operation requires a checked result with i64 error");
        if (shape.error_type != .i64) return self.sink.fail("E_JSON_RESULT", call.name, "JSON operation requires a checked result with i64 error");
        var arguments: [3]typed.NodeId = undefined;
        for (call.arguments, &arguments) |input, *output| output.* = self.resolved[@backingInt(input)].?;
        try self.require(self.nodes.items[@backingInt(arguments[0])].ty, .allocator, call.name);
        try self.requireInteger(self.nodes.items[@backingInt(arguments[2])].ty, call.name);
        const input = self.nodes.items[@backingInt(arguments[1])].ty;
        const codec = source_json;
        if (!codec.byteBuffer(if (decode) input else shape.ok_type, self.catalog.records)) return self.sink.fail("E_JSON_BYTES", call.name, "JSON wire bytes require an owned u8 buffer");
        const document = codec.isDocument(self.src.text(call.name));
        if (document and !codec.wordBuffer(shape.ok_type, self.catalog.records)) return self.sink.fail("E_JSON_DOCUMENT", call.name, "plain JSON parsing requires an owned i64 document buffer success");
        if (!document and !codec.supportsCodec(if (decode) shape.ok_type else input, self.catalog.records)) return self.sink.fail("E_JSON_CODEC", call.name, "JSON values require ordinary data and explicit codecs for every domain");
        out.data = .{ .json_codec = .{ .document = document, .decode = decode, .arguments = arguments } };
    }
    fn byteValues(self: *Checker, bytes: []const u8, span: source.Span) Error![]const typed.NodeId {
        const values = try self.allocator.alloc(typed.NodeId, bytes.len);
        for (bytes, values) |byte, *value| {
            value.* = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = span, .ty = .u8, .data = .{ .integer = byte } });
        }
        return values;
    }
    fn checkReadReference(self: *Checker, name: source.Span, out: *typed.Node) Error!void {
        const id = try self.reference(name);
        try self.requireReferenceKind(id, false, name);
        out.ty = self.references.items[@backingInt(id)].ty;
        if (self.transfers(out.ty)) return self.sink.fail("E_REFERENCE_VALUE", name, "read_ref cannot copy an owned value; use owner inspection or mutation operations");
        out.data = .{ .read_ref = id };
    }
    fn numericOperands(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!struct { left: typed.NodeId, right: typed.NodeId } {
        var left = self.resolved[@backingInt(operation.left)].?;
        var right = self.resolved[@backingInt(operation.right)].?;
        const lt = self.nodes.items[@backingInt(left)].ty;
        const rt = self.nodes.items[@backingInt(right)].ty;
        const promote = operation.op == .python_div or numeric_surface.isFloat(lt, self.catalog.records) or numeric_surface.isFloat(rt, self.catalog.records);
        if (promote) {
            const builder = self.numericBuilder(operation.op_span);
            if (lt.isInteger()) left = try builder.append(try builder.fromInteger(left));
            if (rt.isInteger()) right = try builder.append(try builder.fromInteger(right));
        }
        return .{ .left = left, .right = right };
    }
    fn checkUnary(self: *Checker, node: ast.Node, u: @FieldType(@FieldType(ast.Node, "data"), "unary")) Error!typed.Node {
        var out: typed.Node = undefined;
        out.span = node.span;
        const operand = self.resolved[@backingInt(u.operand)].?;
        out.ty = if (u.op == .not) .bool else self.nodes.items[@backingInt(operand)].ty;
        if (u.op == .neg and numeric_surface.isFloat(out.ty, self.catalog.records)) return self.numericBuilder(node.span).negate(operand);
        if (u.op == .neg) try self.requireInteger(out.ty, u.op_span) else try self.require(self.nodes.items[@backingInt(operand)].ty, if (u.op == .not) .bool else .u64, u.op_span);
        out.data = .{ .unary = .{ .op = std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, .operand = operand, .op_span = u.op_span } };
        return out;
    }
    fn checkDictionaryLiteral(self: *Checker, node: ast.Node, entries: []const ast.NodeId, out: *typed.Node) Error!void {
        const expected = self.expected_types.get(node.span);
        if (expected) |expected_type| {
            out.ty = expected_type;
        } else {
            if (entries.len == 0) return self.sink.fail("E_DICT_INFERENCE", node.span, "empty dictionary requires a dict key/value annotation");
            const state = self.catalog.templates.store orelse return error.InternalError;
            const key = self.nodes.items[@backingInt(self.resolved[@backingInt(entries[0])].?)].ty;
            const value = self.nodes.items[@backingInt(self.resolved[@backingInt(entries[1])].?)].ty;
            out.ty = try @import("nominal_catalog.zig").instantiateLengths(&self.catalog, state.index.names.get("dict").?, &.{ key, value }, &.{}, node.span);
        }
        if (!out.ty.isAggregate() or self.catalog.records[out.ty.recordIndex()].collection.kind != .dictionary) return self.sink.fail("E_DICT_TYPE", node.span, "dictionary literal requires dict key/value types");
        const schema = self.catalog.records[out.ty.recordIndex()];
        const key = schema.collection.key.?;
        const text_key = key.isAggregate() and self.catalog.records[key.recordIndex()].collection.kind == .string;
        if (!key.isInteger() and !text_key) return self.sink.fail("E_DICT_KEY", node.span, "dictionary keys must be integers or str");
        const items = try self.allocator.alloc(typed.NodeId, entries.len);
        for (entries, items, 0..) |entry, *item, index| {
            item.* = self.resolved[@backingInt(entry)].?;
            try self.require(self.nodes.items[@backingInt(item.*)].ty, if (index % 2 == 0) key else schema.shape.buffer.?, self.syntax.nodes.items[@backingInt(entry)].span);
        }
        out.data = .{ .array = items };
    }
    fn checkTextLiteral(self: *Checker, node: ast.Node, bytes: []const u8, out: *typed.Node) Error!void {
        out.ty = if (node.data == .text) try self.ty(node.span) else self.expected_types.get(node.span) orelse try self.ty(node.span);
        if (out.ty.isAggregate() and self.catalog.records[out.ty.recordIndex()].collection.kind == .string) {
            const view = std.unicode.Utf8View.init(bytes) catch return self.sink.fail("E_TEXT_UTF8", node.span, "str literals require valid UTF-8");
            var iterator = view.iterator();
            var points: std.ArrayList(typed.NodeId) = .empty;
            while (iterator.nextCodepoint()) |point| {
                const id: typed.NodeId = @fromBackingInt(@intCast(self.nodes.items.len));
                try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .u32, .data = .{ .integer = point } });
                try points.append(self.allocator, id);
            }
            out.data = .{ .array = try points.toOwnedSlice(self.allocator) };
        } else {
            out.ty = try self.ty(node.span);
            out.data = .{ .array = try self.byteValues(bytes, node.span) };
        }
    }
    fn checkFloatBinary(self: *Checker, span: source.Span, op: ast.BinaryOp, left: typed.NodeId, right: typed.NodeId) Error!typed.Node {
        const builder: collections.Builder(Checker) = .{ .checker = self, .span = span };
        var statements: std.ArrayList(typed.StatementId) = .empty;
        var values: [2]typed.NodeId = undefined;
        for ([_]typed.NodeId{ left, right }, &values) |input, *value| {
            const slot = try builder.local(self.nodes.items[@backingInt(input)].ty);
            try statements.append(self.allocator, try builder.stmt(.{ .initialize = .{ .slot = slot, .value = input } }));
            value.* = try builder.read(slot);
        }
        const result = try self.numericBuilder(span).binary(op, values[0], values[1], self.sink);
        return builder.block(statements.items, try builder.node(result.ty, result.data));
    }
    fn checkValueBinary(self: *Checker, b: @FieldType(@FieldType(ast.Node, "data"), "binary"), out: *typed.Node) Error!void {
        const operands = try self.numericOperands(b);
        const left = operands.left;
        const right = operands.right;
        const lt = self.nodes.items[@backingInt(left)].ty;
        const rt = self.nodes.items[@backingInt(right)].ty;
        try self.require(rt, lt, b.op_span);
        if (numeric_surface.isFloat(lt, self.catalog.records)) {
            out.* = try self.checkFloatBinary(out.span, b.op, left, right);
            return;
        }
        const text_operands = lt.isAggregate() and self.catalog.records[lt.recordIndex()].managed;
        if (text_operands) {
            const concatenation = b.op == .add and self.catalog.records[lt.recordIndex()].collection.kind == .string;
            if (!concatenation and b.op != .eq and b.op != .ne) return self.sink.fail("E_TEXT_OPERATOR", b.op_span, "managed collections support equality and str supports concatenation");
            out.ty = if (b.op == .add) lt else .bool;
        } else switch (b.op) {
            .f64_eq, .f64_lt, .f64_le => {
                try self.require(lt, .u64, b.op_span);
                out.ty = .bool;
            },
            .f64_add, .f64_sub, .f64_mul, .f64_div => {
                try self.require(lt, .u64, b.op_span);
                out.ty = .u64;
            },
            .logical_and, .logical_or => {
                try self.require(lt, .bool, b.op_span);
                out.ty = .bool;
            },
            .eq, .ne => {
                if (!typed.supportsEquality(lt, self.catalog.records)) return self.sink.fail("E_TYPE", b.op_span, "aggregate equality is not defined; compare the relevant elements explicitly");
                out.ty = .bool;
            },
            .lt, .le, .gt, .ge => {
                try self.requireInteger(lt, b.op_span);
                out.ty = .bool;
            },
            else => {
                try self.requireInteger(lt, b.op_span);
                out.ty = lt;
            },
        }
        out.data = .{ .binary = .{
            .op = std.meta.stringToEnum(typed.BinaryOp, @tagName(b.op)).?,
            .left = left,
            .right = right,
            .op_span = b.op_span,
        } };
    }
    fn checkMembership(self: *Checker, node: ast.Node, membership: @FieldType(@FieldType(ast.Node, "data"), "membership"), temporaries: []const typed.Type) Error!typed.Node {
        const needle = try self.expressionWithTemporaries(membership.needle, false, temporaries);
        const container = try self.expressionWithTemporaries(membership.container, false, temporaries);
        const container_type = self.nodes.items[@backingInt(container)].ty;
        if (!container_type.isAggregate() or !self.catalog.records[container_type.recordIndex()].managed) return self.sink.fail("E_MEMBERSHIP", node.span, "membership requires a list, dictionary, or str");
        const schema = self.catalog.records[container_type.recordIndex()];
        const expected = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .dictionary => schema.collection.key.?,
            .string => container_type,
        };
        try self.require(self.nodes.items[@backingInt(needle)].ty, expected, node.span);
        const inputs = [_]typed.NodeId{ needle, container };
        var locals: [2]typed.LocalId = undefined;
        var statements: [2]typed.StatementId = undefined;
        for (inputs, 0..) |input, i| {
            locals[i] = @fromBackingInt(self.locals.items.len);
            try self.locals.append(self.allocator, .{ .name = "<membership>", .declaration = node.span, .ty = self.nodes.items[@backingInt(input)].ty, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
            statements[i] = @fromBackingInt(self.statements.items.len);
            try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .initialize = .{ .slot = locals[i], .value = input } } });
        }
        const needle_read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = expected, .data = .{ .local = locals[0] } });
        var result: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .bool, .data = .{ .buffer_operation = .{ .owner = locals[1], .kind = .contains, .arguments = try self.allocator.dupe(typed.NodeId, &.{needle_read}) } } });
        if (membership.negate) {
            const inverse: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = node.span, .ty = .bool, .data = .{ .unary = .{ .op = .not, .operand = result, .op_span = node.span } } });
            result = inverse;
        }
        const body: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .block = try self.allocator.dupe(typed.StatementId, &statements) } });
        return .{ .span = node.span, .ty = .bool, .data = .{ .block_value = .{ .body = body, .value = result } } };
    }
    fn checkValueIndex(self: *Checker, node: ast.Node, access: @FieldType(@FieldType(ast.Node, "data"), "index"), out: *typed.Node) Error!void {
        const base = self.resolved[@backingInt(access.base)].?;
        const index_value = self.resolved[@backingInt(access.index)].?;
        const receiver_type = self.nodes.items[@backingInt(base)].ty;
        if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].collection.kind != .list) {
            const receiver = self.catalog.records[receiver_type.recordIndex()];
            if (receiver.collection.kind == .dictionary) {
                try self.require(self.nodes.items[@backingInt(index_value)].ty, receiver.collection.key.?, node.span);
            } else try self.requireInteger(self.nodes.items[@backingInt(index_value)].ty, node.span);
            out.ty = if (receiver.collection.kind == .string) receiver_type else receiver.shape.buffer.?;
            out.data = .{ .index = .{ .base = base, .index = index_value } };
            return;
        }
        if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].managed) {
            out.* = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, .read, &.{index_value}, false);
            return;
        }
        const schema = try self.catalog.array(receiver_type, node.span, self.sink);
        try self.requireIndex(schema, self.nodes.items[@backingInt(index_value)].ty, self.syntax.nodes.items[@backingInt(access.index)].span);
        if (self.requiresHandling(schema.element) and schema.length != 1) return self.sink.fail(eResultOperation, node.span, "indexing would drop other result-bearing elements; handle or transfer the entire array");
        out.ty = schema.element;
        out.data = .{ .index = .{ .base = base, .index = index_value } };
    }
    fn checkedExpression(self: *Checker, node: ast.Node, minimum_literal: ?Literal, temporaries: []const typed.Type) Error!typed.Node {
        var out: typed.Node = .{ .span = node.span, .ty = .i64, .data = undefined };
        if (minimum_literal) |parsed| {
            out.ty = parsed.ty;
            out.data = .{ .integer = parsed.value };
        } else switch (node.data) {
            .field_assignment => return self.checkFieldAssignment(node, temporaries),
            .list_literal => |inputs| return self.checkListLiteral(node, inputs, temporaries),
            .list_operation => |op| return self.checkListAccess(node, .{ .base = op.base, .kind = op.kind, .inputs = op.arguments }, temporaries),
            .method_call => return self.checkCollectionMethod(node, temporaries),
            .slice => return self.checkCollectionSlice(node, temporaries),
            .read_field, .take_field => |read| try self.checkReadField(node, read, &out),
            .pool_operation => |operation| try self.checkPoolOperation(node, operation, &out),
            .buffer_operation => |operation| try self.checkBufferOperation(node, operation, &out),
            .acquire_resource => |acquire| try self.checkAcquireResource(node, acquire, &out),
            .restrict_resource => |restrict| {
                const value = self.resolved[@backingInt(restrict.value)].?;
                out.ty = self.nodes.items[@backingInt(value)].ty;
                if (out.ty.resourceKind() == null) return self.sink.fail("E_TYPE", node.span, "restrict_resource requires a filesystem or network capability");
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
                    "E_ENVIRONMENT_NAME",
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
            .acquire_buffer, .acquire_pool => |acquire| try self.checkAcquireBuffer(node, acquire, &out),
            .propagate => |operand| {
                const value = self.resolved[@backingInt(operand)].?;
                const input = typed.resultShape(self.nodes.items[@backingInt(value)].ty, self.catalog.records) orelse return self.sink.fail("E_TRY_TYPE", node.span, "try requires a declared fallible result");
                const output = typed.resultShape(self.return_type, self.catalog.records) orelse return self.sink.fail("E_TRY_RETURN", node.span, "try requires a function returning a declared result type");
                if (self.return_reference != null) return self.sink.fail("E_TRY_RETURN", node.span, "try cannot propagate through a reference return");
                try self.require(input.error_type, output.error_type, node.span);
                try self.requireHandled(0, node.span);
                for (temporaries[0 .. temporaries.len - 1]) |temporary| if (self.requiresHandling(temporary)) return self.sink.fail(
                    "E_RESULT_PROPAGATION",
                    node.span,
                    "propagation could drop a pending result temporary; handle or transfer it before this expression",
                );
                out.ty = input.ok_type;
                out.data = .{ .propagate = .{ .value = value, .output = self.return_type, .cleanup = try self.activeCleanup() } };
            },
            .variant => |variant| {
                out.ty = try self.ty(variant.ty);
                const tag = try self.catalog.variant(out.ty, self.src, variant.name, self.sink);
                const schema = (try self.catalog.variants(out.ty, node.span, self.sink)).cases[tag];
                const value = if (variant.value) |input| self.resolved[@backingInt(input)].? else null;
                if ((schema.payload != null) != (value != null)) return self.sink.failRelated(
                    "E_VARIANT_PAYLOAD",
                    node.span,
                    "construction must supply exactly the payload declared for this variant",
                    .{
                        .span = schema.declaration,
                        .message = variantDeclaredHere,
                    },
                );
                if (value) |input| try self.require(self.nodes.items[@backingInt(input)].ty, schema.payload.?, self.syntax.nodes.items[@backingInt(variant.value.?)].span);
                out.data = .{ .variant = .{ .tag = tag, .value = value } };
            },
            .array => |array| try self.checkArray(node, array, &out),
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
                out.data = .{ .replace = .{ .base = base, .index = index_value, .value = value } };
            },
            .length => |input| {
                const base = self.resolved[@backingInt(input)].?;
                const receiver_type = self.nodes.items[@backingInt(base)].ty;
                if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].collection.kind != .list) {
                    out.ty = .i64;
                    out.data = .{ .length = base };
                    return out;
                }
                if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].managed) return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, .length, &.{}, true);
                _ = try self.catalog.array(receiver_type, node.span, self.sink);
                if (self.requiresHandling(self.nodes.items[@backingInt(base)].ty)) return self.sink.fail(eResultOperation, node.span, "length evaluation would drop result-bearing elements");
                out.ty = .u64;
                out.data = .{ .length = base };
            },
            .membership => |membership| return self.checkMembership(node, membership, temporaries),
            .dictionary_literal => |entries| try self.checkDictionaryLiteral(node, entries, &out),
            .record => |record| {
                out.ty = try self.ty(record.name);
                out.data = .{ .record = try self.fields(out.ty, record.fields, true, node.span) };
            },
            .update => |update| {
                const base = self.resolved[@backingInt(update.base)].?;
                out.ty = self.nodes.items[@backingInt(base)].ty;
                const replacements = try self.fields(out.ty, update.fields, false, node.span);
                for (replacements) |field| if (self.requiresHandling(self.catalog.records[out.ty.recordIndex()].fields[field.index].ty)) return self.sink.fail(eResultOperation, node.span, "update would drop a result-bearing field");
                out.data = .{ .update = .{ .base = base, .fields = replacements } };
            },
            .field => |field| try self.checkField(node, field, &out),
            .bytes, .text => |bytes| try self.checkTextLiteral(node, bytes, &out),
            .match_expression => |match| return self.matchExpression(node, match, temporaries),
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
            .reset_arena => |reset| {
                out.ty = try self.ty(reset.ty);
                const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail("E_ARENA_RESULT", reset.ty, "arena reset requires bool success and i64 error payloads");
                if (shape.ok_type != .bool or shape.error_type != .i64) return self.sink.fail("E_ARENA_RESULT", reset.ty, "arena reset requires bool success and i64 error payloads");
                const value = self.resolved[@backingInt(reset.value)].?;
                try self.require(self.nodes.items[@backingInt(value)].ty, .allocator, node.span);
                out.data = .{ .reset_arena = value };
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
            .read_slice => |read| {
                const id = try self.reference(read.name);
                try self.requireReferenceKind(id, true, read.name);
                const element_index = self.resolved[@backingInt(read.index)].?;
                try self.requireInteger(self.nodes.items[@backingInt(element_index)].ty, self.nodes.items[@backingInt(element_index)].span);
                out.ty = self.references.items[@backingInt(id)].ty;
                out.data = .{ .read_slice = .{ .reference = id, .index = element_index } };
            },
            .len_slice => |name| {
                const id = try self.reference(name);
                try self.requireReferenceKind(id, true, name);
                out.ty = .u64;
                out.data = .{ .len_slice = id };
            },
            .read_ref => |name| try self.checkReadReference(name, &out),
            .name => |name| try self.checkName(node, name, &out),
            .call => |call| try self.checkCall(node, call, &out),
            .unary => |u| return self.checkUnary(node, u),
            .binary => |b| try self.checkValueBinary(b, &out),
        }
        return out;
    }
    fn expressionMode(self: *Checker, root: ast.NodeId, reference_result: bool) Error!typed.NodeId {
        return self.expressionWithTemporaries(root, reference_result, &.{});
    }
    fn consumedTemporaries(self: *Checker, node: ast.Node, out: typed.Node) Error!usize {
        if (node.data == .index and out.data == .block_value) return 2;
        if (node.data == .length and out.data == .block_value) return 1;
        if (node.data == .bytes or node.data == .text or node.data == .integer) return 0;
        if (node.data == .binary) return 2;
        if (node.data == .call and try self.numericConversion(node.data.call) != null) return node.data.call.arguments.len;
        return switch (out.data) {
            .json_codec => 3,
            .function_value, .unit, .integer, .boolean, .local, .read_ref, .read_field, .take_field, .len_slice, .block_value => 0,
            .arena_escape, .reset_arena, .cast, .wrap, .unwrap, .length, .field, .unary, .read_slice, .propagate, .external_read, .complete_resource, .restrict_resource => 1,
            .acquire_buffer, .acquire_pool => |acquire| if (acquire.managed) 1 else 2,
            .acquire_resource, .environment_get => 2,
            .index, .binary => 2,
            .replace => 3,
            .variant => |variant| if (variant.value != null) 1 else 0,
            .array => |values| values.len,
            .record => |initializers| initializers.len,
            .update => |update| update.fields.len + 1,
            .invoke => |call| call.arguments.len,
            .call => |call| call.arguments.len + call.literals.len,
            .pool_operation => |operation| operation.arguments.len,
            .buffer_operation => |operation| operation.arguments.len,
            .resource_io => |io| if (io.value != null) 1 else 0,
        };
    }
    fn expressionWithTemporaries(self: *Checker, root: ast.NodeId, reference_result: bool, inherited: []const typed.Type) Error!typed.NodeId {
        var work: std.ArrayList(Work) = .empty;
        defer work.deinit(self.allocator);
        var temporaries: std.ArrayList(typed.Type) = .empty;
        defer temporaries.deinit(self.allocator);
        try temporaries.appendSlice(self.allocator, inherited);
        try work.append(self.allocator, .{ .id = root });
        while (work.pop()) |task| {
            if (task.verify) |state| {
                try self.samePending(state, self.syntax.nodes.items[@backingInt(task.id)].span, eResultPath);
                continue;
            }
            if (task.checkpoint) {
                const state = try self.pendingState(self.locals.items.len);
                try work.append(self.allocator, .{ .id = task.id, .verify = state });
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
                if (try self.queueExpression(&work, task.id, reference_result and task.id == root)) continue;
            }
            const out = try self.checkedExpression(node, minimum_literal, temporaries.items);
            const consumed = try self.consumedTemporaries(node, out);
            std.debug.assert(temporaries.items.len >= consumed);
            temporaries.shrinkRetainingCapacity(temporaries.items.len - consumed);
            try temporaries.append(self.allocator, out.ty);
            try self.resolved_nodes.append(self.allocator, index);
            self.resolved[index] = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, out);
        }
        return self.resolved[@backingInt(root)].?;
    }
    fn statementArenaScope(self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "arena_scope"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const parent = try self.expression(scope.parent);
        try self.require(self.nodes.items[@backingInt(parent)].ty, .allocator, stmt.span);
        const name = self.src.text(scope.name);
        if (try self.topLevel(scope.name) or self.active.contains(name) or self.active_refs.contains(name)) return self.sink.fail(eShadowing, scope.name, "arena allocator shadows an active name");
        self.arena_depth += 1;
        defer self.arena_depth -= 1;
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{
                .arena_depth = self.arena_depth,
            },
            .name = name,
            .declaration = scope.name,
            .ty = .allocator,
            .mutable = false,
        });
        try self.active.put(self.allocator, name, slot);
        defer _ = self.active.remove(name);
        const body = try self.statement(scope.body);
        flow.terminates = body.terminates;
        return .{ .arena_scope = .{ .parent = parent, .slot = slot, .body = body.id } };
    }
    fn needsLocalCleanup(self: *Checker, local_type: typed.Type) Error!bool {
        if (typed.moveOnly(local_type, self.catalog.records)) return true;
        return self.managedBearing(local_type);
    }
    /// Whether values of this type may hold a garbage-collected reference, including
    /// references nested inside records, variants, options, results and arrays.
    fn managedBearing(self: *Checker, local_type: typed.Type) Error!bool {
        if (!local_type.isAggregate()) return false;
        if (self.managed_types.len != self.catalog.records.len) {
            const flags = try @import("record_layouts.zig").managedTypes(self.allocator, self.catalog.records);
            self.allocator.free(self.managed_types);
            self.managed_types = flags;
        }
        return self.managed_types[local_type.recordIndex()];
    }
    /// Source spelling of the innermost arena binding, or `arena` when anonymous.
    fn arenaName(self: *Checker) []const u8 {
        const scope = self.arenas.items[self.arenas.items.len - 1];
        return if (scope.name.len == 0) "arena" else scope.name;
    }
    /// Resolve an arena binding spelling, rejecting an enclosing rather than innermost scope.
    fn arenaBinding(self: *Checker, name: source.Span) Error!bool {
        const text = self.src.text(name);
        var index = self.arenas.items.len;
        while (index > 0) {
            index -= 1;
            if (!std.mem.eql(u8, self.arenas.items[index].name, text)) continue;
            if (index + 1 != self.arenas.items.len) return self.sink.fail(eArenaEscape, name, "escape must name the innermost active arena scope");
            return true;
        }
        return false;
    }
    /// Whether this slot names a binding that outlives the innermost arena scope.
    fn outlivesArena(self: *Checker, slot: typed.LocalId) bool {
        if (self.arenas.items.len == 0) return false;
        return @backingInt(slot) < @backingInt(self.arenas.items[self.arenas.items.len - 1].watermark);
    }
    /// Whether a checked expression is the arena copy-out that re-homes its result.
    fn isArenaEscape(self: *Checker, value: typed.NodeId) bool {
        return self.nodes.items[@backingInt(value)].data == .arena_escape;
    }
    /// Reject a managed value leaving the innermost arena, naming scope and destination.
    fn failArenaEscape(self: *Checker, span: source.Span, message: []const u8, destination: ?source.Span) Error {
        const scope = self.arenas.items[self.arenas.items.len - 1];
        const cause: diagnostic.Related = .{ .span = scope.declaration, .message = "arena scope opened here" };
        if (destination) |at| return self.sink.failProvenance(eArenaEscape, span, message, cause, at);
        return self.sink.failRelated(eArenaEscape, span, message, cause);
    }
    /// Resolve a plain-name collection receiver to its local slot for arena store checks.
    fn arenaReceiver(self: *Checker, id: ast.NodeId) ?typed.LocalId {
        if (self.arenas.items.len == 0) return null;
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data != .name) return null;
        return self.active.get(self.src.text(node.data.name));
    }
    /// Reject an arena-allocated element stored through a collection mutation.
    fn requireArenaOperation(self: *Checker, owner: ?typed.LocalId, kind: BufferKind, arguments: []const typed.NodeId) Error!void {
        const slot = owner orelse return;
        if (self.arenas.items.len == 0) return;
        if (kind == .append and arguments.len == 1) return self.requireArenaStore(slot, arguments[0]);
        if (kind != .write or arguments.len != 2) return;
        try self.requireArenaStore(slot, arguments[0]);
        try self.requireArenaStore(slot, arguments[1]);
    }
    /// Reject storing a managed value into a container binding that outlives the arena.
    fn requireArenaStore(self: *Checker, owner: typed.LocalId, value: typed.NodeId) Error!void {
        if (!self.outlivesArena(owner)) return;
        if (!try self.managedBearing(self.nodes.items[@backingInt(value)].ty)) return;
        if (self.isArenaEscape(value)) return;
        const local = self.locals.items[@backingInt(owner)];
        const span = self.nodes.items[@backingInt(value)].span;
        const message = try std.fmt.allocPrint(
            self.allocator,
            "`{s}` stores a managed value into `{s}`, which outlives arena `{s}`; store `{s}.escape(...)` instead",
            .{ self.src.text(span), local.name, self.arenaName(), self.arenaName() },
        );
        return self.failArenaEscape(span, message, local.declaration);
    }
    /// Reject assigning a managed value to a binding declared outside the arena.
    fn requireArenaAssignment(self: *Checker, slot: typed.LocalId, value: typed.NodeId) Error!void {
        if (!self.outlivesArena(slot)) return;
        if (!try self.managedBearing(self.locals.items[@backingInt(slot)].ty)) return;
        if (self.isArenaEscape(value)) return;
        const local = self.locals.items[@backingInt(slot)];
        const span = self.nodes.items[@backingInt(value)].span;
        const message = try std.fmt.allocPrint(
            self.allocator,
            "`{s}` is assigned to `{s}`, which outlives arena `{s}`; assign `{s}.escape(...)` instead",
            .{ self.src.text(span), local.name, self.arenaName(), self.arenaName() },
        );
        return self.failArenaEscape(span, message, local.declaration);
    }
    /// Reject returning a managed value out of an arena scope. A copy-out of the
    /// outermost arena in this function targets the caller's region and is allowed.
    fn requireArenaReturn(self: *Checker, value: typed.NodeId, span: source.Span) Error!void {
        if (self.arenas.items.len == 0) return;
        if (!try self.managedBearing(self.nodes.items[@backingInt(value)].ty)) return;
        if (self.arenas.items.len == 1 and self.isArenaEscape(value)) return;
        const message = try std.fmt.allocPrint(
            self.allocator,
            "`{s}` returns a managed value from inside arena `{s}`; assign `{s}.escape(...)` to a binding declared before the block and return it afterwards",
            .{ self.src.text(self.nodes.items[@backingInt(value)].span), self.arenaName(), self.arenaName() },
        );
        return self.failArenaEscape(span, message, null);
    }
    fn statementManagedArena(self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "managed_arena"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        var name: []const u8 = "";
        if (scope.name) |declared| {
            name = self.src.text(declared);
            if (try self.topLevel(declared) or self.active.contains(name) or self.active_refs.contains(name)) return self.sink.fail(eShadowing, declared, "arena name shadows an active name");
            for (self.arenas.items) |active| if (std.mem.eql(u8, active.name, name)) return self.sink.fail(eShadowing, declared, "arena name shadows an enclosing arena scope");
        }
        const watermark: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.arenas.append(self.allocator, .{ .name = name, .declaration = scope.name orelse stmt.span, .watermark = watermark });
        defer _ = self.arenas.pop();
        const body = try self.statement(scope.body);
        flow.terminates = body.terminates;
        return .{ .managed_arena = .{ .watermark = watermark, .body = body.id } };
    }
    fn statementBlock(self: *Checker, stmt: ast.Statement, children: @FieldType(@FieldType(ast.Statement, "data"), "block"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const first_local = self.locals.items.len;
        defer for (self.locals.items[first_local..]) |local| {
            _ = self.active.remove(local.name);
        };
        var checked: std.ArrayList(typed.StatementId) = .empty;
        for (children) |child| {
            if (flow.terminates) return self.sink.fail("E_UNREACHABLE", self.syntax.statements.items[@backingInt(child)].span, "statement follows a structurally terminating statement");
            const result = try self.statement(child);
            flow.terminates = result.terminates;
            try checked.append(self.allocator, result.id);
        }
        if (!flow.terminates) {
            try self.requireHandled(first_local, stmt.span);
            var owned: std.ArrayList(typed.LocalId) = .empty;
            for (self.locals.items[first_local..], first_local..) |local, index| {
                if (try self.needsLocalCleanup(local.ty)) try owned.append(self.allocator, @fromBackingInt(index));
            }
            flow.owned_cleanup = try owned.toOwnedSlice(self.allocator);
        }
        return .{ .block = try checked.toOwnedSlice(self.allocator) };
    }
    fn patternTag(self: *Checker, value_type: typed.Type, type_span: source.Span, name: source.Span) Error!usize {
        if (type_span.start != type_span.end) {
            try self.require(try self.ty(type_span), value_type, type_span);
            return self.catalog.variant(value_type, self.src, name, self.sink);
        }
        const spelling = self.src.text(name);
        const canonical = prelude.caseName(spelling);
        const variants = try self.catalog.variants(value_type, name, self.sink);
        for (variants.cases, 0..) |candidate, index| {
            if (std.mem.eql(u8, candidate.name, canonical)) return index;
        }
        return self.sink.fail("E_UNKNOWN_VARIANT", name, "case is not a variant of the matched type");
    }
    fn statementMatch(self: *Checker, stmt: ast.Statement, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const value = try self.expression(match.value);
        const value_type = self.nodes.items[@backingInt(value)].ty;
        const variants = try self.catalog.variants(value_type, stmt.span, self.sink);
        const seen = try self.allocator.alloc(?source.Span, variants.cases.len);
        @memset(seen, null);
        const arms = try self.allocator.alloc(typed.MatchArm, match.arms.len);
        const before = try self.pendingState(self.locals.items.len);
        var continuation: ?[]Pending = null;
        flow.terminates = true;
        for (match.arms, arms) |arm, *out_arm| {
            self.restorePending(before);
            const tag = try self.patternTag(value_type, arm.ty, arm.name);
            if (seen[tag]) |previous| return self.sink.failRelated("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm", .{ .span = previous, .message = "previous arm" });
            seen[tag] = arm.name;
            const payload = variants.cases[tag].payload;
            if (arm.discard_payload and payload != null and self.requiresHandling(payload.?)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling or acknowledgement");
            if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.failRelated(
                "E_PATTERN_PAYLOAD",
                arm.name,
                "payload variants require a binding or (discard); empty variants take neither",
                .{
                    .span = variants.cases[tag].declaration,
                    .message = variantDeclaredHere,
                },
            );
            const first_local = self.locals.items.len;
            defer for (self.locals.items[first_local..]) |local| {
                _ = self.active.remove(local.name);
            };
            var slot: ?typed.LocalId = null;
            if (arm.binding) |binding| {
                const name = self.src.text(binding);
                if (try self.topLevel(binding) or self.active.contains(name) or self.active_refs.contains(name)) return self.sink.fail(eShadowing, binding, "payload binding shadows an active binding or top-level name");
                slot = @fromBackingInt(self.locals.items.len);
                try self.locals.append(self.allocator, .{
                    .ownership = .{
                        .arena_depth = self.arena_depth,
                        .transfer_available = self.transfers(payload.?),
                    },
                    .name = name,
                    .declaration = binding,
                    .ty = payload.?,
                    .mutable = false,
                });
                try self.active.put(self.allocator, name, slot.?);
            }
            var body = try self.statement(arm.body);
            if (!body.terminates) {
                try self.requireHandled(first_local, stmt.span);
                if (slot) |payload_slot| if (try self.needsLocalCleanup(payload.?)) {
                    const children = try self.allocator.dupe(typed.StatementId, &.{body.id});
                    const cleanup_slots = try self.allocator.dupe(typed.LocalId, &.{payload_slot});
                    body.id = @fromBackingInt(self.statements.items.len);
                    try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = false, .owned_cleanup = cleanup_slots, .data = .{ .block = children } });
                };
                if (continuation) |state| try self.samePending(state, stmt.span, eResultPath) else continuation = try self.pendingState(before.len);
            }
            flow.terminates = flow.terminates and body.terminates;
            out_arm.* = .{ .tag = tag, .slot = slot, .body = body.id };
        }
        for (seen, variants.cases) |covered, variant| if (covered == null) {
            const message = try std.fmt.allocPrint(self.allocator, "match does not handle variant `{s}`; every variant requires an explicit arm", .{variant.name});
            return self.sink.failRelated("E_INCOMPLETE_MATCH", stmt.span, message, .{ .span = variant.declaration, .message = "unhandled variant declared here" });
        };
        if (continuation) |state| self.restorePending(state);
        return .{ .match = .{ .value = value, .arms = arms } };
    }
    fn matchExpression(self: *Checker, node: ast.Node, match: @FieldType(@FieldType(ast.Node, "data"), "match_expression"), temporaries: []const typed.Type) Error!typed.Node {
        const value = try self.expressionWithTemporaries(match.value, false, temporaries);
        const value_type = self.nodes.items[@backingInt(value)].ty;
        const variants = try self.catalog.variants(value_type, node.span, self.sink);
        const seen = try self.allocator.alloc(?source.Span, variants.cases.len);
        @memset(seen, null);
        const arms = try self.allocator.alloc(typed.MatchArm, match.arms.len);
        const before = try self.pendingState(self.locals.items.len);
        var continuation: ?[]Pending = null;
        const result_slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = "<match-result>", .declaration = node.span, .ty = .i64, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
        var result_type: ?typed.Type = null;
        for (match.arms, arms) |arm, *out_arm| {
            self.restorePending(before);
            const tag = try self.patternTag(value_type, arm.ty, arm.name);
            if (seen[tag]) |previous| return self.sink.failRelated("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm", .{ .span = previous, .message = "previous arm" });
            seen[tag] = arm.name;
            const payload = variants.cases[tag].payload;
            if (arm.discard_payload and payload != null and self.requiresHandling(payload.?)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling or acknowledgement");
            if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.failRelated(
                "E_PATTERN_PAYLOAD",
                arm.name,
                "payload variants require a binding or (discard); empty variants take neither",
                .{
                    .span = variants.cases[tag].declaration,
                    .message = variantDeclaredHere,
                },
            );
            const first_local = self.locals.items.len;
            defer for (self.locals.items[first_local..]) |local| {
                _ = self.active.remove(local.name);
            };
            var slot: ?typed.LocalId = null;
            if (arm.binding) |binding| {
                const name = self.src.text(binding);
                if (try self.topLevel(binding) or self.active.contains(name) or self.active_refs.contains(name)) return self.sink.fail(eShadowing, binding, "payload binding shadows an active binding or top-level name");
                slot = @fromBackingInt(self.locals.items.len);
                try self.locals.append(self.allocator, .{
                    .ownership = .{
                        .arena_depth = self.arena_depth,
                        .transfer_available = self.transfers(payload.?),
                    },
                    .name = name,
                    .declaration = binding,
                    .ty = payload.?,
                    .mutable = false,
                });
                try self.active.put(self.allocator, name, slot.?);
            }
            const arm_value = try self.expressionWithTemporaries(arm.value, false, temporaries);
            const arm_type = self.nodes.items[@backingInt(arm_value)].ty;
            if (result_type) |expected| try self.require(arm_type, expected, self.syntax.nodes.items[@backingInt(arm.value)].span) else result_type = arm_type;
            try self.requireHandled(first_local, node.span);
            const body_id: typed.StatementId = @fromBackingInt(self.statements.items.len);
            try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .initialize = .{ .slot = result_slot, .value = arm_value } } });
            var body: CheckedStatement = .{ .id = body_id, .terminates = false };
            if (slot) |payload_slot| if (try self.needsLocalCleanup(payload.?)) {
                const children = try self.allocator.dupe(typed.StatementId, &.{body.id});
                const cleanup_slots = try self.allocator.dupe(typed.LocalId, &.{payload_slot});
                body.id = @fromBackingInt(self.statements.items.len);
                try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .owned_cleanup = cleanup_slots, .data = .{ .block = children } });
            };
            if (continuation) |state| try self.samePending(state, node.span, eResultPath) else continuation = try self.pendingState(before.len);
            out_arm.* = .{ .tag = tag, .slot = slot, .body = body.id };
        }
        for (seen, variants.cases) |covered, variant| if (covered == null) {
            const message = try std.fmt.allocPrint(self.allocator, "match does not handle variant `{s}`; every variant requires an explicit arm", .{variant.name});
            return self.sink.failRelated("E_INCOMPLETE_MATCH", node.span, message, .{ .span = variant.declaration, .message = "unhandled variant declared here" });
        };
        if (continuation) |state| self.restorePending(state);
        const output_type = result_type orelse return self.sink.fail("E_EMPTY_MATCH", node.span, "a value-producing match requires at least one case");
        self.locals.items[@backingInt(result_slot)].ty = output_type;
        self.locals.items[@backingInt(result_slot)].ownership.arena_depth = self.arena_depth;
        const body: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = node.span, .terminates = false, .data = .{ .match = .{ .value = value, .arms = arms } } });
        const result: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = output_type, .data = .{ .local = result_slot } });
        return .{ .span = node.span, .ty = output_type, .data = .{ .block_value = .{ .body = body, .value = result } } };
    }
    fn statementBorrowCall(self: *Checker, _: ast.Statement, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow_call"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const call_node = self.syntax.nodes.items[@backingInt(borrow.call)];
        if (call_node.data != .call) return self.sink.fail(eReferenceResult, call_node.span, "borrow result requires a direct function call");
        const name = self.src.text(borrow.name);
        if (self.active.contains(name) or self.active_refs.contains(name) or try self.topLevel(borrow.name)) return self.sink.fail(eShadowing, borrow.name, "reference shadows an active binding or top-level name");
        const call = try self.expressionMode(borrow.call, true);
        const checked_call = self.nodes.items[@backingInt(call)].data.call;
        const contract = (try self.returnContract(checked_call.function)) orelse return self.sink.fail(eReferenceResult, call_node.span, "borrow result requires a reference-returning function");
        if (borrow.mutable and !contract.mutable) return self.sink.fail(eReferenceReadOnly, borrow.name, "shared function result cannot be borrowed exclusively");
        const argument = self.syntax.nodes.items[@backingInt(call_node.data.call.arguments[@backingInt(contract.parameter)])];
        const parent = try self.reference(argument.data.name);
        const owner = self.references.items[@backingInt(parent)].owner;
        const id: typed.ReferenceId = @fromBackingInt(self.references.items.len);
        try self.references.append(self.allocator, .{ .mode = .{
            .slice = contract.slice,
        }, .name = name, .declaration = borrow.name, .owner = owner, .parent = parent, .ty = self.nodes.items[@backingInt(call)].ty, .mutable = borrow.mutable });
        try self.active_refs.put(self.allocator, name, id);
        defer _ = self.active_refs.remove(name);
        const body = try self.statement(borrow.body);
        flow.terminates = body.terminates;
        return .{ .borrow_call = .{ .call = call, .reference = id, .body = body.id } };
    }
    fn statementSplitBorrow(self: *Checker, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const split = borrow.split.?;
        const middle = try self.expression(split.middle);
        try self.requireInteger(self.nodes.items[@backingInt(middle)].ty, borrow.owner);
        const parent = try self.reference(borrow.owner);
        try self.requireReferenceKind(parent, true, borrow.owner);
        const source_ref = self.references.items[@backingInt(parent)];
        if (!source_ref.mutable) return self.sink.fail(eReferenceReadOnly, borrow.owner, "split requires an exclusive slice");
        const left: typed.ReferenceId = @fromBackingInt(self.references.items.len);
        const right: typed.ReferenceId = @fromBackingInt(self.references.items.len + 1);
        for ([_]source.Span{ borrow.name, split.right }, [_]typed.ReferenceId{ right, left }) |span, sibling| {
            const name = self.src.text(span);
            if (self.active.contains(name) or self.active_refs.contains(name) or try self.topLevel(span)) return self.sink.fail(eShadowing, span, "split name shadows an active binding or top-level name");
            const id: typed.ReferenceId = @fromBackingInt(self.references.items.len);
            try self.references.append(self.allocator, .{ .mode = .{ .slice = true, .split_sibling = sibling }, .name = name, .declaration = span, .owner = source_ref.owner, .parent = parent, .ty = source_ref.ty, .mutable = true });
            try self.active_refs.put(self.allocator, name, id);
        }
        defer _ = self.active_refs.remove(self.src.text(borrow.name));
        defer _ = self.active_refs.remove(self.src.text(split.right));
        const body = try self.statement(borrow.body);
        flow.terminates = body.terminates;
        return .{ .borrow = .{ .reference = left, .body = body.id, .split = .{ .right = right, .middle = middle } } };
    }
    fn wholeBorrowRange(self: *Checker, owner: typed.LocalId, parent: ?typed.ReferenceId, source_type: typed.Type, parent_slice: bool, span: source.Span) Error!typed.Range {
        const start: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = span, .ty = .u64, .data = .{ .integer = 0 } });
        const end: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        const data: @FieldType(typed.Node, "data") = if (parent_slice)
            .{ .len_slice = parent.? }
        else if (self.catalog.records[source_type.recordIndex()].shape.array) |array|
            .{ .integer = array.length }
        else
            .{ .buffer_operation = .{ .kind = .length, .owner = owner, .arguments = &.{} } };
        try self.nodes.append(self.allocator, .{ .span = span, .ty = .u64, .data = data });
        return .{ .start = start, .end = end };
    }
    fn statementBorrow(self: *Checker, _: ast.Statement, borrow: @FieldType(@FieldType(ast.Statement, "data"), "borrow"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        if (borrow.split != null) return self.statementSplitBorrow(borrow, flow);
        const name = self.src.text(borrow.name);
        if (self.active.contains(name) or self.active_refs.contains(name) or try self.topLevel(borrow.name)) return self.sink.fail(eShadowing, borrow.name, "reference shadows an active binding or top-level name");
        var range: ?typed.Range = null;
        if (borrow.range) |bounds| {
            const start = try self.expression(bounds.start);
            const end = try self.expression(bounds.end);
            try self.requireInteger(self.nodes.items[@backingInt(start)].ty, self.nodes.items[@backingInt(start)].span);
            try self.requireInteger(self.nodes.items[@backingInt(end)].ty, self.nodes.items[@backingInt(end)].span);
            range = .{ .start = start, .end = end };
        }
        var parent: ?typed.ReferenceId = null;
        var owner: typed.LocalId = undefined;
        if (self.active_refs.contains(self.src.text(borrow.owner))) {
            parent = try self.reference(borrow.owner);
            const ref = self.references.items[@backingInt(parent.?)];
            if (borrow.mutable and !ref.mutable) return self.sink.fail(eReferenceReadOnly, borrow.owner, "shared references cannot be reborrowed exclusively");
            owner = ref.owner;
        } else {
            owner = try self.resolve(borrow.owner);
            if (borrow.mutable and !self.locals.items[@backingInt(owner)].mutable) return self.sink.fail(eImmutable, borrow.owner, "exclusive borrowing requires a mutable owner");
            try self.ownerAccess(owner, borrow.mutable, borrow.owner);
            self.locals.items[@backingInt(owner)].usage.reads += 1;
            if (borrow.mutable) self.locals.items[@backingInt(owner)].usage.mutable_borrow = true;
        }
        const owner_type = self.locals.items[@backingInt(owner)].ty;
        if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].managed) return self.sink.fail("E_LIST_BORROW", borrow.owner, "managed lists are passed by value; borrowing their storage is not supported");
        if (self.transfers(owner_type) and !self.locals.items[@backingInt(owner)].ownership.transfer_available) return self.sink.failTransfer(
            eOwnedConsumed,
            borrow.owner,
            self.locals.items[@backingInt(owner)].declaration,
            self.locals.items[@backingInt(owner)].ownership.transfer_span,
        );
        if (self.requiresHandling(owner_type)) return self.sink.fail(eResultBorrow, borrow.owner, "result-bearing values must transfer their handling obligation by value");
        for (self.locals.items[@backingInt(owner)].ownership.partial_fields) |moved| if (moved != null) return self.sink.fail(eResultBorrow, borrow.owner, "a partially moved owner cannot be borrowed whole");
        const source_type = if (parent) |id| self.references.items[@backingInt(id)].ty else self.locals.items[@backingInt(owner)].ty;
        const parent_slice = if (parent) |id| self.references.items[@backingInt(id)].mode.slice else false;
        const slicing = range != null or borrow.whole_slice;
        const owner_subslice = slicing and parent != null and !parent_slice;
        if (owner_subslice and source_type.isAggregate()) {
            if (self.catalog.records[source_type.recordIndex()].shape.buffer != null)
                return self.sink.fail("E_SLICE_TYPE", borrow.owner, "borrow buffer elements directly from the owner in a separate lexical scope");
        }
        const element = if (slicing and !parent_slice) try self.sliceElement(source_type, borrow.owner) else source_type;
        if (self.requiresHandling(element) or ((slicing or parent_slice) and self.transfers(element)))
            return self.sink.fail(eResultBorrow, borrow.owner, "result obligations and owned slice elements cannot be exposed through references");
        if (borrow.whole_slice) range = try self.wholeBorrowRange(owner, parent, source_type, parent_slice, borrow.owner);
        const id: typed.ReferenceId = @fromBackingInt(self.references.items.len);
        try self.references.append(self.allocator, .{ .mode = .{ .slice = slicing or parent_slice }, .name = name, .declaration = borrow.name, .owner = owner, .parent = parent, .ty = element, .mutable = borrow.mutable });
        try self.active_refs.put(self.allocator, name, id);
        defer _ = self.active_refs.remove(name);
        const body = try self.statement(borrow.body);
        flow.terminates = body.terminates;
        return .{ .borrow = .{ .reference = id, .body = body.id, .range = range } };
    }
    fn statementWriteSlice(self: *Checker, stmt: ast.Statement, write: @FieldType(@FieldType(ast.Statement, "data"), "write_slice"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const id = try self.reference(write.name);
        try self.requireReferenceKind(id, true, write.name);
        const ref = self.references.items[@backingInt(id)];
        if (!ref.mutable) return self.sink.fail(eReferenceReadOnly, write.name, "writing requires an exclusive slice");
        const index = try self.expression(write.index);
        try self.requireInteger(self.nodes.items[@backingInt(index)].ty, self.nodes.items[@backingInt(index)].span);
        const value = try self.expression(write.value);
        try self.require(self.nodes.items[@backingInt(value)].ty, ref.ty, stmt.span);
        self.locals.items[@backingInt(ref.owner)].usage.writes += 1;
        return .{ .write_slice = .{ .reference = id, .index = index, .value = value } };
    }
    fn statementWriteRef(self: *Checker, stmt: ast.Statement, write: @FieldType(@FieldType(ast.Statement, "data"), "write_ref"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const id = try self.reference(write.name);
        try self.requireReferenceKind(id, false, write.name);
        const ref = self.references.items[@backingInt(id)];
        if (!ref.mutable) return self.sink.fail(eReferenceReadOnly, write.name, "writing requires an exclusive reference");
        const value = try self.expression(write.value);
        try self.require(self.nodes.items[@backingInt(value)].ty, ref.ty, stmt.span);
        self.locals.items[@backingInt(ref.owner)].usage.writes += 1;
        return .{ .write_ref = .{ .reference = id, .value = value } };
    }
    fn statementAcknowledge(self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "acknowledge"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const value = try self.expression(expr);
        if (!self.requiresHandling(self.nodes.items[@backingInt(value)].ty)) return self.sink.fail("E_ACKNOWLEDGE_TYPE", stmt.span, "acknowledge requires a result-bearing value");
        return .{ .acknowledge = value };
    }
    fn statementDiscard(self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "discard"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const value = try self.expression(expr);
        if (stmt.implicit_discard and self.nodes.items[@backingInt(value)].ty != .unit) return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", stmt.span, "a standalone non-unit value requires explicit discard or result handling");
        if (self.requiresHandling(self.nodes.items[@backingInt(value)].ty)) return self.sink.fail(eResultDiscard, stmt.span, "discard cannot erase a fallible result; match, return, transfer, or explicitly acknowledge it");
        return .{ .discard = value };
    }
    fn statementBranch(self: *Checker, stmt: ast.Statement, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const condition = try self.expression(branch.condition);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(branch.condition)].span);
        const before = try self.pendingState(self.locals.items.len);
        const then_body = try self.statement(branch.then_body);
        const then_state = try self.pendingState(before.len);
        self.restorePending(before);
        const else_body = if (branch.else_body) |other| try self.statement(other) else null;
        if (!then_body.terminates) {
            if (else_body == null or !else_body.?.terminates) try self.samePending(then_state, stmt.span, eResultPath);
            self.restorePending(then_state);
        }
        flow.terminates = then_body.terminates and if (else_body) |other| other.terminates else false;
        return .{ .branch = .{ .condition = condition, .then_body = then_body.id, .else_body = if (else_body) |other| other.id else null } };
    }
    fn statementLoop(self: *Checker, stmt: ast.Statement, loop: @FieldType(@FieldType(ast.Statement, "data"), "loop"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const before = try self.pendingState(self.locals.items.len);
        const condition = try self.expression(loop.condition);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(loop.condition)].span);
        try self.samePending(before, stmt.span, eResultLoop);
        const loop_id = self.loops.next;
        self.loops.next += 1;
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .references = self.references.items.len, .arena_depth = self.arena_depth, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const body = try self.statement(loop.body);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        return .{ .loop = .{ .id = loop_id, .condition = condition, .body = body.id } };
    }
    fn statementForEach(self: *Checker, stmt: ast.Statement, each: @FieldType(@FieldType(ast.Statement, "data"), "for_each")) Error!@FieldType(typed.Statement, "data") {
        const b: collections.Builder(Checker) = .{ .checker = self, .span = stmt.span };
        const iterable = try self.expression(each.iterable);
        const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
        if (!iterable_type.isAggregate() or !self.catalog.records[iterable_type.recordIndex()].managed) return self.sink.fail(eCollectionMethod, stmt.span, "iteration requires a list, str, or dictionary");
        const schema = self.catalog.records[iterable_type.recordIndex()];
        const element = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .string => iterable_type,
            .dictionary => schema.collection.key.?,
        };
        const owner = try b.local(iterable_type);
        const index = try b.local(.i64);
        const limit = try b.local(.i64);
        const value_slot = try b.local(element);
        const names = [_]?source.Span{ each.name, each.index_name };
        const slots = [_]typed.LocalId{ value_slot, index };
        for (names) |maybe_name| if (maybe_name) |name| {
            if (try self.topLevel(name) or self.active.contains(self.src.text(name)) or self.active_refs.contains(self.src.text(name))) return self.sink.fail(eShadowing, name, "iteration binding shadows an active declaration");
        };
        if (each.index_name) |name| if (std.mem.eql(u8, self.src.text(name), self.src.text(each.name))) return self.sink.fail(eShadowing, name, "iteration names must differ");
        for (names, slots) |maybe_name, slot| if (maybe_name) |name| {
            self.locals.items[@backingInt(slot)].name = self.src.text(name);
            self.locals.items[@backingInt(slot)].declaration = name;
            try self.active.put(self.allocator, self.src.text(name), slot);
        };
        defer for (names) |maybe_name| if (maybe_name) |name| {
            _ = self.active.remove(self.src.text(name));
        };
        const before = try self.pendingState(self.locals.items.len);
        const loop_id = self.loops.next;
        self.loops.next += 1;
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .references = self.references.items.len, .arena_depth = self.arena_depth, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const body = try self.statement(each.body);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        const i = try b.read(index);
        const iteration_check = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
        const iteration = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            iteration_check,
            try b.stmt(.{ .initialize = .{ .slot = value_slot, .value = try b.operation(owner, if (schema.collection.kind == .dictionary) .key_at else .read, &.{i}) } }),
            body.id,
        }) });
        const step = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            iteration_check,
            try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
        }) });
        return .{ .block = try self.allocator.dupe(typed.StatementId, &.{
            try b.stmt(.{ .initialize = .{ .slot = owner, .value = iterable } }),
            try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
            try b.stmt(.{ .initialize = .{ .slot = limit, .value = try b.length(owner) } }),
            try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = iteration, .step = step } }),
        }) };
    }
    fn statementForRange(self: *Checker, stmt: ast.Statement, range: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!@FieldType(typed.Statement, "data") {
        const name = self.src.text(range.name);
        if (try self.topLevel(range.name) or self.active.contains(name) or self.active_refs.contains(name)) return self.sink.fail(eShadowing, range.name, "iteration binding shadows an active declaration");
        const zero_start = self.syntax.nodes.items[@backingInt(range.start)].data == .unit;
        const start = if (zero_start) try (collections.Builder(Checker){ .checker = self, .span = range.name }).integer(0) else try self.expression(range.start);
        const end = try self.expression(range.end);
        const element = self.nodes.items[@backingInt(start)].ty;
        try self.requireInteger(element, range.name);
        try self.require(self.nodes.items[@backingInt(end)].ty, element, self.syntax.nodes.items[@backingInt(range.end)].span);
        const index: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .declaration = range.name, .ty = element, .mutable = false, .usage = .{ .reads = 1 } });
        const limit: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = "<range-limit>", .declaration = range.name, .ty = element, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
        try self.active.put(self.allocator, name, index);
        defer _ = self.active.remove(name);
        const index_node: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .local = index } });
        const limit_node: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .local = limit } });
        const condition: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = stmt.span, .ty = .bool, .data = .{ .binary = .{ .op = .lt, .left = index_node, .right = limit_node, .op_span = stmt.span } } });
        const one: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .integer = 1 } });
        const next: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = range.name, .ty = element, .data = .{ .binary = .{ .op = .add, .left = index_node, .right = one, .op_span = range.name } } });
        const before = try self.pendingState(self.locals.items.len);
        const loop_id = self.loops.next;
        self.loops.next += 1;
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .references = self.references.items.len, .arena_depth = self.arena_depth, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const body = try self.statement(range.body);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        const step: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = range.name, .terminates = false, .data = .{ .assign = .{ .slot = index, .value = next } } });
        const children = try self.allocator.alloc(typed.StatementId, 3);
        children[0] = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = range.name, .terminates = false, .data = .{ .initialize = .{ .slot = index, .value = start } } });
        children[1] = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = range.name, .terminates = false, .data = .{ .initialize = .{ .slot = limit, .value = end } } });
        children[2] = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = false, .data = .{ .loop = .{ .id = loop_id, .condition = condition, .body = body.id, .step = step } } });
        return .{ .block = children };
    }
    fn statementLoopExit(self: *Checker, stmt: ast.Statement, continuing: bool, flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        if (self.loops.active.items.len == 0) return self.sink.fail("E_LOOP_EXIT", stmt.span, "break and continue require an enclosing loop");
        const loop = self.loops.active.items[self.loops.active.items.len - 1];
        try self.requireHandled(loop.before.len, stmt.span);
        try self.samePending(loop.before, stmt.span, eResultLoop);
        var owned: std.ArrayList(typed.LocalId) = .empty;
        var regions: std.ArrayList(typed.LocalId) = .empty;
        var refs: std.ArrayList(typed.ReferenceId) = .empty;
        for (self.locals.items[loop.before.len..], loop.before.len..) |local, index| {
            if (try self.needsLocalCleanup(local.ty)) try owned.append(self.allocator, @fromBackingInt(index));
            if (local.ty == .allocator and local.ownership.arena_depth > loop.arena_depth and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index)))
                try regions.append(self.allocator, @fromBackingInt(index));
        }
        for (self.references.items[loop.references..], loop.references..) |ref, index| {
            if (self.active_refs.get(ref.name) == @as(typed.ReferenceId, @fromBackingInt(index))) try refs.append(self.allocator, @fromBackingInt(index));
        }
        flow.terminates = true;
        flow.owned_cleanup = try owned.toOwnedSlice(self.allocator);
        flow.cleanup = try refs.toOwnedSlice(self.allocator);
        var arenas: std.ArrayList(typed.LocalId) = .empty;
        var open = self.arenas.items.len;
        while (open > loop.arenas) {
            open -= 1;
            try arenas.append(self.allocator, self.arenas.items[open].watermark);
        }
        return .{ .loop_exit = .{
            .target = loop.id,
            .continuing = continuing,
            .regions = try regions.toOwnedSlice(self.allocator),
            .arenas = try arenas.toOwnedSlice(self.allocator),
        } };
    }
    fn unitFallthrough(self: *Checker, body: CheckedStatement, span: source.Span) Error!CheckedStatement {
        try self.requireHandled(0, span);
        const value: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = span, .ty = .unit, .data = .unit });
        const ret: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .cleanup = try self.activeCleanup(), .data = .{ .ret = value } });
        const children = try self.allocator.dupe(typed.StatementId, &.{ body.id, ret });
        const block: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = .{ .block = children } });
        return .{ .id = block, .terminates = true };
    }
    fn statementRet(self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "ret"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        var value: ?typed.NodeId = null;
        var returned: ?typed.ReferenceId = null;
        if (self.return_reference) |contract| {
            const expression_node = self.syntax.nodes.items[@backingInt(expr)];
            if (expression_node.data != .name) return self.sink.fail(eReferenceResult, expression_node.span, "reference return requires an active reference name");
            returned = try self.reference(expression_node.data.name);
            const ref = self.references.items[@backingInt(returned.?)];
            if (ref.owner != contract.parameter) return self.sink.failReturnLifetime(
                expression_node.span,
                ref.declaration,
                self.locals.items[@backingInt(ref.owner)].declaration,
                self.locals.items[@backingInt(contract.parameter)].declaration,
            );
            try self.requireReferenceKind(returned.?, contract.slice, expression_node.span);
            if (contract.mutable and !ref.mutable) return self.sink.fail(eReferenceReadOnly, expression_node.span, "shared reference cannot supply an exclusive result");
            try self.require(ref.ty, self.return_type, stmt.span);
        } else {
            value = try self.expressionExpected(expr, self.return_type);
            try self.require(self.nodes.items[@backingInt(value.?)].ty, self.return_type, stmt.span);
            try self.requireArenaReturn(value.?, stmt.span);
        }
        try self.requireHandled(0, stmt.span);
        flow.terminates = true;
        flow.cleanup = try self.activeCleanup();
        return if (returned) |id| .{ .ret_ref = id } else .{ .ret = value.? };
    }
    fn statementBinding(self: *Checker, _: ast.Statement, b: @FieldType(@FieldType(ast.Statement, "data"), "binding"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const name = self.src.text(b.name);
        if (try self.topLevel(b.name) or self.active.contains(name) or self.active_refs.contains(name))
            return self.sink.fail(eShadowing, b.name, "binding shadows an active local or top-level function");
        for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, name)) return self.sink.fail(eShadowing, b.name, "binding shadows an active arena name");
        const value = if (b.annotation) |annotation| try self.expressionExpected(b.value, try self.ty(annotation)) else try self.expression(b.value);
        const value_type = self.nodes.items[@backingInt(value)].ty;
        if (b.annotation) |annotation| try self.require(value_type, try self.ty(annotation), annotation);
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{
                .arena_depth = self.arena_depth,
                .transfer_available = self.transfers(value_type),
            },
            .name = name,
            .declaration = b.name,
            .ty = value_type,
            .mutable = b.mutable,
        });
        try self.active.put(self.allocator, name, slot);
        return .{ .initialize = .{ .slot = slot, .value = value } };
    }
    fn statementAssignment(self: *Checker, stmt: ast.Statement, a: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const new_python_local = a.python and a.op == .set;
        const unbound = !self.active.contains(self.src.text(a.name)) and !self.active_refs.contains(self.src.text(a.name));
        if (new_python_local and unbound)
            return self.statementBinding(stmt, .{ .name = a.name, .mutable = true, .annotation = null, .value = a.value }, flow);
        const slot = try self.resolve(a.name);
        try self.ownerAccess(slot, true, a.name);
        if (!self.locals.items[@backingInt(slot)].mutable)
            return self.sink.fail(eImmutable, a.name, "assignment requires a let mut binding");
        var value = try self.expressionExpected(a.value, self.locals.items[@backingInt(slot)].ty);
        if (a.op != .set) {
            try self.requireInteger(self.locals.items[@backingInt(slot)].ty, a.op_span);
            try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, a.op_span);
            self.locals.items[@backingInt(slot)].usage.reads += 1;
            const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .ty = self.locals.items[@backingInt(slot)].ty, .span = a.name, .data = .{ .local = slot } });
            const combined: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .ty = self.locals.items[@backingInt(slot)].ty, .span = stmt.span, .data = .{ .binary = .{
                .op = if (a.op == .add) .add else .sub,
                .left = read,
                .right = value,
                .op_span = a.op_span,
            } } });
            value = combined;
        }
        try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, stmt.span);
        try self.requireArenaAssignment(slot, value);
        if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
            if (self.pendingObligation(self.locals.items[@backingInt(slot)])) return self.sink.fail("E_RESULT_OVERWRITE", a.name, "assignment would overwrite an unhandled result-bearing value");
            self.locals.items[@backingInt(slot)].ownership.transfer_available = true;
            self.locals.items[@backingInt(slot)].ownership.transfer_span = null;
            self.locals.items[@backingInt(slot)].ownership.partial_fields = &.{};
        }
        self.locals.items[@backingInt(slot)].usage.writes += 1;
        return .{ .assign = .{ .slot = slot, .value = value } };
    }
    fn bindParameters(self: *Checker, function: ast.Function) Error!void {
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        for (function.signature.parameters) |parameter| {
            const name = src.text(parameter.name);
            if (self.active.get(name)) |previous| return sink.failRelated(
                "E_DUPLICATE_PARAMETER",
                parameter.name,
                "parameter name is already declared",
                .{
                    .span = self.locals.items[@backingInt(previous)].declaration,
                    .message = "previous parameter declaration",
                },
            );
            if (self.active_refs.get(name)) |previous| return sink.failRelated(
                "E_DUPLICATE_PARAMETER",
                parameter.name,
                "parameter name is already declared",
                .{
                    .span = self.references.items[@backingInt(previous)].declaration,
                    .message = "previous parameter declaration",
                },
            );
            if (try self.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "parameter shadows a top-level function");
            const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
            const parameter_type = try self.ty(parameter.ty);
            if (parameter.default_value) |value| {
                const checked = try self.expressionExpected(value, parameter_type);
                try self.require(self.nodes.items[@backingInt(checked)].ty, parameter_type, parameter.ty);
            }
            if (parameter.reference != null and self.requiresHandling(parameter_type)) return sink.fail(eResultBorrow, parameter.ty, "result-bearing parameters must transfer their handling obligation by value");
            try self.locals.append(
                allocator,
                .{
                    .name = name,
                    .declaration = parameter.name,
                    .ty = parameter_type,
                    .mutable = function.policy.python and function.policy.host == null,
                    .parameter = .{
                        .reference_parameter = parameter.reference,
                        .slice_parameter = parameter.slice,
                    },
                    .ownership = .{
                        .transfer_available = self.transfers(parameter_type),
                    },
                },
            );
            if (parameter.reference) |mutable| {
                const reference_id: typed.ReferenceId = @fromBackingInt(self.references.items.len);
                try self.references.append(allocator, .{ .mode = .{ .parameter = true, .slice = parameter.slice }, .name = name, .declaration = parameter.name, .owner = slot, .parent = null, .ty = parameter_type, .mutable = mutable });
                try self.active_refs.put(allocator, name, reference_id);
            } else try self.active.put(allocator, name, slot);
        }
    }
    fn statement(self: *Checker, statement_id: ast.StatementId) Error!CheckedStatement {
        const stmt = self.syntax.statements.items[@backingInt(statement_id)];
        var flow: StatementFlow = .{};
        const data: @FieldType(typed.Statement, "data") = switch (stmt.data) {
            .arena_scope => |scope| try self.statementArenaScope(stmt, scope, &flow),
            .managed_arena => |scope| try self.statementManagedArena(stmt, scope, &flow),
            .block => |children| try self.statementBlock(stmt, children, &flow),
            .match => |match| try self.statementMatch(stmt, match, &flow),
            .borrow_call => |borrow| try self.statementBorrowCall(stmt, borrow, &flow),
            .borrow => |borrow| try self.statementBorrow(stmt, borrow, &flow),
            .write_slice => |write| try self.statementWriteSlice(stmt, write, &flow),
            .write_ref => |write| try self.statementWriteRef(stmt, write, &flow),
            .acknowledge => |expr| try self.statementAcknowledge(stmt, expr, &flow),
            .discard => |expr| try self.statementDiscard(stmt, expr, &flow),
            .branch => |branch| try self.statementBranch(stmt, branch, &flow),
            .loop => |loop| try self.statementLoop(stmt, loop, &flow),
            .ret => |expr| try self.statementRet(stmt, expr, &flow),
            .loop_exit => |continuing| try self.statementLoopExit(stmt, continuing, &flow),
            .for_each => |each| try self.statementForEach(stmt, each),
            .for_range => |range| try self.statementForRange(stmt, range),
            .binding => |b| try self.statementBinding(stmt, b, &flow),
            .assignment => |a| try self.statementAssignment(stmt, a, &flow),
        };
        const result: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = flow.terminates, .owned_cleanup = flow.owned_cleanup, .cleanup = flow.cleanup, .data = data });
        return .{ .id = result, .terminates = flow.terminates };
    }
};
fn warningLess(_: void, a: diagnostic.Diagnostic, b: diagnostic.Diagnostic) bool {
    if (a.span.start != b.span.start) return a.span.start < b.span.start;
    if (a.span.end != b.span.end) return a.span.end < b.span.end;
    return std.mem.lessThan(u8, a.code, b.code);
}
// The same invalid signature can be reached from several callers. Keep its
// source diagnostic once, ordered independently of specialization discovery.
fn normalizeDiagnostics(sink: *diagnostic.Sink) void {
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    var count: usize = 0;
    for (sink.items.items) |item| {
        if (count != 0) {
            const previous = sink.items.items[count - 1];
            if (previous.span.start == item.span.start and previous.span.end == item.span.end and
                std.mem.eql(u8, previous.code, item.code)) continue;
        }
        sink.items.items[count] = item;
        count += 1;
    }
    sink.items.shrinkRetainingCapacity(count);
}
/// Type-check a single source unit, returning arena-owned resolved instructions.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) Error!typed.Program {
    return checkWithNames(allocator, src, program, sink, null);
}
fn checkGenericContracts(src: source.Source, program: ast.Program, sink: *diagnostic.Sink, catalog: records.Catalog) Error!void {
    try @import("generic_bodies.zig").checkWithCatalog(sink.allocator, src, program, sink, catalog);
}
/// Type-check linked module names and validate ownership, effects, and domain codecs.
pub fn checkWithNames(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!typed.Program {
    return checkCached(allocator, src, program, sink, module_names, null);
}
/// Reuse supported checked bodies, then rerun all cross-function validation passes.
pub fn checkCached(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names, cache: ?*@import("semantic_cache.zig").Cache) Error!typed.Program {
    defer normalizeDiagnostics(sink);
    const catalog = try records.collectWithNames(allocator, src, program, sink, module_names);
    var session = if (cache) |c| try c.begin(allocator, src, program, catalog.records) else null;
    var failed = false;
    checkGenericContracts(src, program, sink, catalog) catch |err| switch (err) {
        error.SourceError => failed = true,
        else => return err,
    };
    const contracts_failed = failed;
    const resolved = try allocator.alloc(?typed.NodeId, program.nodes.items.len);
    @memset(resolved, null);
    const ordinary_ids = try allocator.alloc(?typed.FunctionId, program.functions.len);
    @memset(ordinary_ids, null);
    var checker: Checker = .{ .allocator = allocator, .src = src, .syntax = program, .sink = sink, .resolved = resolved, .catalog = catalog, .ordinary_ids = ordinary_ids };
    defer allocator.free(checker.managed_types);
    for (program.functions, 0..) |function, i| {
        if (function.policy.owner == null and source_json.operation(src.text(function.name)) != null) return sink.fail("E_RESERVED_FUNCTION", function.name, "JSON operation names are reserved compiler intrinsics");
        const name = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try functionName(allocator, src, function.policy.owner, function.name);
        if (checker.catalog.names.contains(name) or checker.catalog.templates.names.contains(name)) return sink.fail("E_DUPLICATE_NAME", function.name, "function name conflicts with a declared type");
        if (checker.functions.get(name)) |previous| return sink.failRelated(
            "E_DUPLICATE_FUNCTION",
            function.name,
            "function name is already declared",
            .{
                .span = program.functions[@backingInt(previous)].name,
                .message = "previous function declaration",
            },
        );
        try checker.functions.put(allocator, name, @fromBackingInt(i));
        if (function.signature.type_parameters.len == 0) {
            ordinary_ids[i] = @fromBackingInt(checker.instance_keys.items.len);
            try checker.instance_keys.append(allocator, .{ .declaration = @fromBackingInt(i), .arguments = &.{} });
        }
    }
    const main_name = if (module_names) |names| try std.fmt.allocPrint(allocator, "{s}::main", .{names.index.project.modules.items[0].name}) else "main";
    checker.ordinary_count = checker.instance_keys.items.len;
    const main_declaration = checker.functions.get(main_name) orelse {
        if (failed) return error.SourceError;
        return sink.fail("E_MAIN", .{ .start = 0, .end = 0 }, "the program requires fn main() -> i64");
    };
    const entry = program.functions[@backingInt(main_declaration)];
    const main = ordinary_ids[@backingInt(main_declaration)] orelse return sink.fail("E_MAIN", entry.name, "main cannot have type parameters");
    if (entry.policy.host != null or entry.policy.constant) return sink.fail("E_MAIN", entry.name, "main must have a guest function body");
    if (entry.signature.return_reference != null) return sink.fail("E_MAIN", entry.name, "main must return an i64 value");
    var entry_capabilities: u8 = 0;
    for (entry.signature.parameters) |parameter| {
        const index = (try checker.ty(parameter.ty)).capabilityIndex() orelse return sink.fail("E_MAIN", parameter.ty, "entry parameters must be capabilities");
        const bit = @as(u8, 1) << index;
        if (parameter.reference != null or entry_capabilities & bit != 0) return sink.fail("E_MAIN", parameter.name, "entry requests at most one value parameter of each capability kind");
        entry_capabilities |= bit;
    }
    if (!@import("entry_adapter.zig").supported(try checker.ty(entry.signature.return_type), checker.catalog.records)) return sink.fail("E_TYPE", entry.signature.return_type, "main must return int, None, or Result<None/int,int>");
    var checked_functions: std.ArrayList(typed.Function) = .empty;
    var i: usize = 0;
    while (i < checker.instance_keys.items.len and (!contracts_failed or i < checker.ordinary_count)) : (i += 1) {
        const start_nodes = checker.nodes.items.len;
        const start_statements = checker.statements.items.len;
        const reused = if (session) |*queries| try queries.lookup(allocator, i, &checker.nodes, &checker.statements) else null;
        if (reused == null) if (cache) |c| {
            c.statistics.checked += 1;
        };
        const function = reused orelse checker.checkFunction(i) catch |err| switch (err) {
            error.SourceError => {
                failed = true;
                continue;
            },
            else => return err,
        };
        if (session) |*queries| if (i < queries.ranges.len) {
            queries.ranges[i] = .{
                .nodes = .{ .start = start_nodes, .end = checker.nodes.items.len },
                .statements = .{ .start = start_statements, .end = checker.statements.items.len },
            };
        };
        try checked_functions.append(allocator, function);
    }
    // Failed functions leave no executable placeholders. Cross-function passes
    // require a complete graph and must never see the partial function list.
    if (failed) return error.SourceError;
    const functions = try checked_functions.toOwnedSlice(allocator);
    try @import("c_abi.zig").validateImports(allocator, functions, sink);
    var executable_names: std.StringHashMapUnmanaged(typed.FunctionId) = .empty;
    for (functions) |function| try executable_names.put(allocator, function.name, function.id);
    var checked: typed.Program = .{
        .aliases = try checker.catalog.aliases(allocator, src, program, sink),
        .nodes = try checker.nodes.toOwnedSlice(allocator),
        .statements = try checker.statements.toOwnedSlice(allocator),
        .functions = functions,
        .main = main,
        .records = checker.catalog.records,
    };
    try @import("entry_adapter.zig").adapt(allocator, &checked);
    try @import("region_check.zig").check(allocator, checked, sink);
    try @import("effects.zig").check(allocator, checked, sink);
    try @import("domain_codecs.zig").check(allocator, src, program.types.domains, checker.catalog, .{ .items = functions, .names = executable_names }, sink);
    try warnBindings(allocator, program, functions, sink);
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    if (session) |*queries| try queries.remember(checked);
    return checked;
}

// This initial conversion form is declarative. Restricting its body avoids
// pretending arbitrary control/data flow proves source-field accounting.
fn conversionBody(src: source.Source, program: ast.Program, function: ast.Function, sink: *diagnostic.Sink) Error!void {
    const statements = program.statements.items[@backingInt(function.body)].data.block;
    for (statements) |id| {
        const stmt = program.statements.items[@backingInt(id)];
        switch (stmt.data) {
            .ret => |value| {
                if (program.nodes.items[@backingInt(value)].data != .record)
                    return sink.fail(eConversionBody, stmt.span, "conversion must return an explicit complete record construction");
            },
            .discard => |value| {
                const expression = program.nodes.items[@backingInt(value)];
                if (expression.data != .field) return sink.fail(eConversionBody, stmt.span, "conversion discard must name a direct source field");
                const base = program.nodes.items[@backingInt(expression.data.field.base)];
                if (base.data != .name or !std.mem.eql(u8, src.text(base.data.name), src.text(function.signature.parameters[0].name)))
                    return sink.fail(eConversionBody, stmt.span, "conversion discard must name a direct source field");
            },
            else => return sink.fail(eConversionBody, stmt.span, "conversion bodies contain named source-field discards followed by a complete record construction; use helpers for transformations"),
        }
    }
}

const functionName = @import("function_identity.zig").localName;

fn checkHostType(allocator: std.mem.Allocator, catalog: []const typed.Record, ty: typed.Type, span: source.Span, sink: *diagnostic.Sink) Error!void {
    @import("data_type.zig").check(allocator, catalog, ty, true) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return sink.fail("E_HOST_SIGNATURE", span, "host signatures require ordinary data without capabilities or runtime-owned storage"),
    };
}

fn warnBindings(allocator: std.mem.Allocator, syntax: ast.Program, functions: []const typed.Function, sink: *diagnostic.Sink) Error!void {
    for (functions) |function| {
        if (function.policy.host != null) continue;
        const python = pythonFunction(syntax, function.declaration);
        for (function.scope.locals) |local| {
            if (local.usage.temporary) continue;
            if (local.usage.reads == 0) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_BINDING",
                .span = local.declaration,
                .message = "binding is never read; use it or remove it, preserving initializer effects with discard when needed",
            });
            const redundant_mut = local.mutable and local.usage.writes == 0 and !local.usage.mutable_borrow;
            if (!python and redundant_mut) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNNECESSARY_MUT",
                .span = local.declaration,
                .message = "binding is never assigned after initialization; remove mut",
            });
        }
    }
}

fn pythonFunction(syntax: ast.Program, declaration: source.Span) bool {
    for (syntax.functions) |function| if (function.name.start == declaration.start) return function.policy.python;
    return false;
}
