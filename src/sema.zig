//! Scope and type checking use resolved binding identities, including advisory use counts.
const buffer_operations = @import("buffer_operations.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const needs_list = "operation requires a managed list";
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const io_builtins = @import("io_builtins.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const callback_type_code = "E_CALLBACK_TYPE";
const lambda_context_code = "E_LAMBDA_CONTEXT";
const call_argument_code = "E_CALL_ARGUMENT";
const eResultOperation = diagnostic.result_operation;
const eOwnedConsumed = diagnostic.owned_consumed;
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
const eIterationShadow = "iteration binding shadows an active declaration";
const eWildcardArm = "E_WILDCARD_ARM";
const eConversionBody = "E_CONVERSION_BODY";
const eByteConversion = "E_BYTES_CONVERSION";
/// Managed collection methods whose only argument has the receiver's own sequence type.
/// Recognize `case _`, the contextual arm that stands for every remaining variant.
fn wildcard(src: source.Source, arm: anytype) bool {
    if (arm.ty.start != arm.ty.end or arm.binding != null or arm.discard_payload) return false;
    return std.mem.eql(u8, src.text(arm.name), "_");
}

fn sequenceArgument(kind: BufferKind) bool {
    return switch (kind) {
        .split, .contains, .starts_with, .ends_with, .find, .count, .replace => true,
        else => false,
    };
}

/// String methods whose only operand is a scalar width rather than more text.
fn widthArgument(kind: BufferKind) bool {
    return kind == .zfill;
}
const eResourceResult = diagnostic.resource_result;
const eResourceIoResult = "E_RESOURCE_IO_RESULT";
const eResultLoop = diagnostic.result_loop;
const bindingDeclaredHere = "binding declared here";
const eImmutable = diagnostic.immutable;
const eResultDiscard = diagnostic.result_discard;
const variantDeclaredHere = "variant declared here";
const std = @import("std");
const bufferOperation = "buffer_operation";
const eCollectionMethod = "E_COLLECTION_METHOD";
/// The ordinary binary operator one augmented assignment applies to its operand pair.
fn augmentedOperator(op: ast.AssignmentOp) ast.BinaryOp {
    return switch (op) {
        .add => .add,
        .sub => .sub,
        .mul => .mul,
        .div => .python_div,
        .floor_div => .floor_div,
        .rem => .floor_rem,
        .set => .add,
    };
}
const eTextOperator = "E_TEXT_OPERATOR";
const unsupported_collection = "operation is not supported by this collection";
const unsupported_list = "operation is not supported by lists";
const method_arity = "collection method argument count differs from its signature";

const ast = @import("ast.zig");
const entry_adapter = @import("entry_adapter.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const records = @import("records.zig");
const Error = diagnostic.Error;
const instances = @import("generic_instances.zig");
const Names = @import("module_names.zig").Names;
const LoopScope = struct { id: usize, before: []const Pending, arenas: usize = 0, exited: bool = false };
const ArenaScope = struct { name: []const u8, declaration: source.Span, watermark: typed.LocalId };
const eArenaEscape = "E_ARENA_ESCAPE";
const eUnbound = "E_UNBOUND";
const eArenaBinding = "E_ARENA_BINDING";
const eWithResource = "E_WITH_RESOURCE";
const eFileArgument = "E_FILE_ARGUMENT";
const Pending = struct { available: bool, transfer_span: ?source.Span };
const Work = struct { default_value: bool = false, id: ast.NodeId, emit: bool = false, checkpoint: bool = false, sorted_key: bool = false, verify: ?[]const Pending = null };
const FieldDestination = struct { owner: typed.LocalId, index: ?typed.NodeId, value: typed.NodeId, refresh: typed.StatementId };
/// An already-evaluated managed receiver and the source arguments of its method.
const ManagedAccess = struct { base: typed.NodeId, kind: BufferKind, inputs: []const ast.NodeId, receiver: ?typed.LocalId = null };
/// One list method call whose receiver and arguments are already evaluated.
const ListMethodCall = struct { base: typed.NodeId, base_input: ast.NodeId, kind: BufferKind, inputs: []const ast.NodeId, temporaries: []const typed.Type };
const CheckedStatement = struct { id: typed.StatementId, terminates: bool, looping: bool = false };

const StatementFlow = struct {
    terminates: bool = false,
    /// A loop the checker proved never exits ends control flow without making a
    /// following statement a mistake, because its exit is inferred, not written.
    looping: bool = false,
    owned_cleanup: []const typed.LocalId = &.{},
};

const integer_literal = @import("integer_literal.zig");
const float_syntax = @import("float_syntax.zig");
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const arrays = @import("array_literals.zig");
const variant_calls = @import("variant_calls.zig");
const truncating = @import("truncating_math.zig");

const LambdaCapture = struct { name: []const u8 };

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
    current_lambda: ?usize = null,
    lambda_start: usize = 0,
    lambda_types: []?typed.Type = &.{},
    lambda_captures: []?[]const LambdaCapture = &.{},
    loops: struct { active: std.ArrayList(LoopScope) = .empty, next: usize = 0 } = .{},
    return_type: typed.Type = .i64,
    arenas: std.ArrayList(ArenaScope) = .empty,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,
    managed_types: []bool = &.{},
    owner: ?typed.Type = null,
    /// The `with open(...)` head whose failure traps instead of yielding a result.
    trapping_open: ?source.Span = null,

    fn checkFunction(self: *Checker, i: usize) Error!typed.Function {
        if (i >= self.lambda_start and i < self.lambda_start + self.syntax.lambdas.len)
            return self.checkLambdaFunction(i - self.lambda_start);
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        self.current_function = @fromBackingInt(i);
        self.current_lambda = null;
        const function = self.syntaxFunction(@fromBackingInt(i));
        const constant_context: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        const constant = if (function.policy.constant) try constant_context.evaluate(@backingInt(self.instance_keys.items[i].declaration)) else null;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.locals = .empty;
        self.active.clearRetainingCapacity();
        self.owner = if (function.policy.owner) |owner| try self.ty(owner) else null;
        self.return_type = try self.ty(function.signature.return_type);
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
            if (function.signature.parameters.len != 1) return sink.fail(
                "E_CONVERSION_SIGNATURE",
                function.name,
                "a complete conversion requires one source record parameter",
            );
            const source_record = try self.catalog.record(self.locals.items[0].ty, function.signature.parameters[0].ty, sink);
            _ = try self.catalog.record(self.return_type, function.signature.return_type, sink);
            try conversionBody(self, function);
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
        const implicit_unit = self.return_type == .unit;
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
                .return_type = self.return_type,
                .parameter_count = function.signature.parameters.len,
            },
            .scope = .{
                .body = body.id,
                .locals = try self.locals.toOwnedSlice(allocator),
            },
            .id = @fromBackingInt(i),
            .name = try self.instanceName(@fromBackingInt(i)),
            .type_arguments = self.instance_keys.items[i].arguments,
            .declaration = function.name,
        };
    }
    fn checkLambdaFunction(self: *Checker, index: usize) Error!typed.Function {
        const lambda = self.syntax.lambdas[index];
        const lambda_type = self.lambda_types[index] orelse
            return self.sink.fail(lambda_context_code, lambda.span, "lambda requires an expected callback type");
        const contract = callables.signature(lambda_type, self.catalog.records) orelse return error.InternalError;
        self.current_function = null;
        self.current_lambda = index;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.locals = .empty;
        self.active.clearRetainingCapacity();
        self.owner = null;
        self.return_type = contract.return_type;
        for (lambda.parameters, contract.parameters) |parameter, parameter_type| {
            const name = self.src.text(parameter);
            if (self.active.contains(name)) return self.sink.fail("E_DUPLICATE_PARAMETER", parameter, "lambda parameter name is already declared");
            const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
            try self.locals.append(self.allocator, .{
                .name = name,
                .declaration = parameter,
                .ty = parameter_type,
                .mutable = false,
                .ownership = .{ .initialized = true, .transfer_available = self.transfers(parameter_type) },
            });
            try self.active.put(self.allocator, name, slot);
        }
        const value = try self.expressionExpected(lambda.body, contract.return_type);
        try self.require(self.nodes.items[@backingInt(value)].ty, contract.return_type, self.syntax.nodes.items[@backingInt(lambda.body)].span);
        try self.requireHandled(0, lambda.span);
        const body: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = lambda.span, .terminates = true, .data = .{ .ret = value } });
        const name = try std.fmt.allocPrint(self.allocator, "lambda@{d}", .{lambda.span.start});
        return .{
            .policy = .{ .effect_bound = .{ .span = lambda.span, .allowed = contract.effects } },
            .signature = .{ .return_type = contract.return_type, .parameter_count = contract.parameters.len },
            .scope = .{ .body = body, .locals = try self.locals.toOwnedSlice(self.allocator) },
            .id = @fromBackingInt(self.lambda_start + index),
            .name = name,
            .declaration = lambda.span,
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
        output.writer.print("{s}[", .{base}) catch return error.OutOfMemory;
        for (arguments, 0..) |argument, index| {
            if (index != 0) output.writer.writeByte(',') catch return error.OutOfMemory;
            if (self.instance_keys.items[@backingInt(id)].length(index)) |length| {
                output.writer.print("{d}", .{length}) catch return error.OutOfMemory;
            } else output.writer.writeAll(typed.typeName(argument, self.catalog.records)) catch return error.OutOfMemory;
        }
        output.writer.writeByte(']') catch return error.OutOfMemory;
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
            const actual = self.nodes.items[@backingInt(self.resolved[@backingInt(input)].?)].ty;
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
        for (self.locals.items[0..count], state) |local, *pending| pending.* = .{ .available = local.ownership.transfer_available, .transfer_span = local.ownership.transfer_span };
        return state;
    }
    fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*local, pending| {
            local.ownership.transfer_available = pending.available;
            local.ownership.transfer_span = pending.transfer_span;
        }
    }
    fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |local, pending| if (local.ownership.transfer_available != pending.available) return self.sink.failRelated(
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
        return local.ownership.transfer_available and self.requiresHandling(local.ty);
    }
    fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
        for (self.locals.items[first..], first..) |local, index| {
            if (self.pendingObligation(local) and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index))) return self.sink.failRelated(
                "E_RESULT_UNHANDLED",
                span,
                "result-bearing value leaves scope without being handled, returned, transferred, or explicitly discarded",
                .{
                    .span = local.declaration,
                    .message = "unhandled result-bearing binding",
                },
            );
        }
    }
    const ResolvedCall = struct { declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call") };
    fn callTarget(self: *Checker, input: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
        const target = try self.callDeclaration(input, span);
        return self.specialize(target.declaration, target.call, span);
    }
    fn callDeclaration(self: *Checker, raw: @FieldType(@FieldType(ast.Node, "data"), "call"), _: source.Span) Error!ResolvedCall {
        const applied = try @import("call_type_arguments.zig").split(self.src, self.syntax, self.catalog.module_names, raw, self.sink);
        const input = applied orelse raw;
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
    /// Reject reading a function-scoped binding that no path reaching here has
    /// assigned, or one that names a managed value confined to a released arena.
    fn requireReadable(self: *Checker, slot: typed.LocalId, name: source.Span) Error!void {
        const local = self.locals.items[@backingInt(slot)];
        if (local.ownership.arena_confined) return self.sink.failRelated(
            eArenaEscape,
            name,
            "names a managed value that lives in a released `with arena()` scope; an arena value cannot be read after the block, so copy it out with `arena.escape(...)` into a binding declared before the block",
            .{ .span = local.declaration, .message = "arena-managed binding first assigned here" },
        );
        if (!local.ownership.initialized) return self.sink.failRelated(
            eUnbound,
            name,
            "name may be read before it is assigned; some control-flow path reaching here leaves it unbound",
            .{ .span = local.declaration, .message = "binding first assigned here" },
        );
    }
    /// Snapshot every local's definite-assignment flag for later branch merging.
    fn initSnapshot(self: *Checker) Error![]bool {
        const state = try self.allocator.alloc(bool, self.locals.items.len);
        for (self.locals.items, state) |local, *flag| flag.* = local.ownership.initialized;
        return state;
    }
    /// Restore definite-assignment flags to a snapshot; locals created since it are
    /// treated as unassigned on the path being started.
    fn initRestore(self: *Checker, state: []const bool) void {
        for (self.locals.items, 0..) |*local, index| local.ownership.initialized = index < state.len and state[index];
    }
    /// Keep a local assigned after a branch only when both paths assigned it.
    fn initIntersect(self: *Checker, state: []const bool) void {
        for (self.locals.items, 0..) |*local, index| local.ownership.initialized = local.ownership.initialized and (index < state.len and state[index]);
    }
    /// Merge one continuing match arm's definite-assignment snapshot into the
    /// intersection over all continuing arms.
    fn mergeMatchInit(self: *Checker, merged: *?[]bool) Error!void {
        const current = try self.initSnapshot();
        if (merged.*) |prior| {
            self.initRestore(prior);
            self.initIntersect(current);
            merged.* = try self.initSnapshot();
        } else merged.* = current;
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
        return self.expressionWithTemporaries(root, &.{});
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
    /// Recognize `sqrt`, `floor`, `ceil`, `trunc` and `abs` as prelude float operations.
    /// A local binding, a declared function or a module top-level name of the same name wins.
    fn floatIntrinsic(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.UnaryOp {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.src.text(call.name);
        const op = @import("float_intrinsics.zig").operation(name) orelse return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        return op;
    }
    fn checkFloatIntrinsic(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), op: typed.UnaryOp, out: *typed.Node) Error!void {
        const value = self.resolved[@backingInt(call.arguments[0])].?;
        const ty_value = self.nodes.items[@backingInt(value)].ty;
        if (!numeric_surface.isFloat(ty_value, self.catalog.records)) return self.sink.fail("E_TYPE", node.span, "this prelude operation requires a float argument");
        out.* = try self.numericBuilder(node.span).unary(op, value);
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
        // `int(text)` and `float(text)` parse rather than convert, so they answer an Option.
        if (ty_value.isAggregate() and self.catalog.records[ty_value.recordIndex()].collection.kind == .string) {
            const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
            out.* = try builder.access(value, if (floating) .parse_float else .parse_int, &.{}, false);
            return;
        }
        if (!input_float and !ty_value.isInteger()) return self.sink.fail("E_TYPE", node.span, "numeric conversion requires an integer, float or str");
        if (floating) {
            out.* = if (input_float) self.nodes.items[@backingInt(value)] else try self.numericBuilder(node.span).fromInteger(value);
        } else if (input_float) {
            out.* = try self.numericBuilder(node.span).toInteger(value);
        } else out.* = .{ .span = node.span, .ty = .i64, .data = .{ .cast = value } };
    }
    /// The bare prelude builtins answer only when no binding, declaration or module name claims them.
    fn preludeName(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
        if (call.owner != null or call.type_arguments.len != 0) return false;
        const name = self.src.text(call.name);
        if (!prelude_builtins.reserved(name)) return false;
        if (self.active.contains(name) or self.functions.contains(name)) return false;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
        return true;
    }
    /// The `range(...)` source of `list(range(...))`, which is never an ordinary expression.
    fn rangeSource(self: *Checker, id: ast.NodeId) Error!?@FieldType(@FieldType(ast.Node, "data"), "call") {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data != .call) return null;
        const call = node.data.call;
        if (call.owner != null or call.type_arguments.len != 0) return null;
        if (!std.mem.eql(u8, self.src.text(call.name), "range")) return null;
        if (self.active.contains("range") or self.functions.contains("range")) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        if (call.arguments.len == 0 or call.arguments.len > 2) return null;
        return call;
    }
    /// An unannotated empty list literal adopts the element type the builtin fixes,
    /// so `any([])`, `sum([])`, `sorted([])` and `list([])` all infer their schema.
    fn hintEmptyPreludeList(self: *Checker, id: ast.NodeId, element: typed.Type) Error!void {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data != .list_literal or node.data.list_literal.len != 0) return;
        try self.hint(id, try collections.listType(&self.catalog, element, node.span));
    }
    /// Hint the fixed element types of one bare prelude builtin's sequence arguments.
    fn hintPreludeArguments(self: *Checker, name: []const u8, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
        if (std.mem.eql(u8, name, "zip")) {
            for (call.arguments) |id| try self.hintEmptyPreludeList(id, .i64);
            return;
        }
        if (call.arguments.len != 1) return;
        if (std.mem.eql(u8, name, "any") or std.mem.eql(u8, name, "all")) return self.hintEmptyPreludeList(call.arguments[0], .bool);
        inline for (.{ "sum", "min", "max", "sorted", "reversed", "list" }) |builtin| {
            if (std.mem.eql(u8, name, builtin)) return self.hintEmptyPreludeList(call.arguments[0], .i64);
        }
    }
    /// Queue the operands of one prelude builtin call in evaluation order.
    fn queuePreludeCall(self: *Checker, work: *std.ArrayList(Work), call_id: ast.NodeId, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
        if (!try self.preludeName(call)) return false;
        const name = self.src.text(call.name);
        if (std.mem.eql(u8, name, "sorted")) {
            try self.validateSortedArguments(call);
            if (call.arguments.len == 2) {
                try work.append(self.allocator, .{ .id = call_id, .sorted_key = true });
                try work.append(self.allocator, .{ .id = call.arguments[0] });
                return true;
            }
        } else try call_arguments.positional(call, self.sink);
        try self.hintPreludeArguments(name, call);
        const materialized = if (prelude_builtins.materializes(name) and call.arguments.len == 1) try self.rangeSource(call.arguments[0]) else null;
        const arguments = if (materialized) |range| range.arguments else call.arguments;
        var index = arguments.len;
        while (index > 0) {
            index -= 1;
            try work.append(self.allocator, .{ .id = arguments[index] });
        }
        return true;
    }
    /// Build one prelude builtin call, or report that a later recognizer owns it.
    fn checkPreludeCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
        if (!try self.preludeName(call)) return false;
        const name = self.src.text(call.name);
        if (std.mem.eql(u8, name, "sorted")) try self.validateSortedArguments(call) else try call_arguments.positional(call, self.sink);
        const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
        if (prelude_builtins.materializes(name) and call.arguments.len == 1) {
            if (try self.rangeSource(call.arguments[0])) |range| {
                const bounds = try self.allocator.alloc(typed.NodeId, range.arguments.len);
                for (range.arguments, bounds) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
                out.* = try builtins.rangeList(node.span, bounds);
                return true;
            }
            out.* = try builtins.copyList(node.span, self.resolved[@backingInt(call.arguments[0])].?);
            return true;
        }
        const values = try self.allocator.alloc(typed.NodeId, call.arguments.len);
        for (call.arguments, values) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
        out.* = (try builtins.build(node.span, name, values)) orelse return false;
        return true;
    }
    fn validateSortedArguments(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
        if (call.arguments.len == 0 or call.arguments.len > 2) return self.sink.fail("E_ARITY", call.name, "sorted requires a list and optional key callback");
        if (call.argument_names.len == 0) {
            if (call.arguments.len == 2) return self.sink.fail(call_argument_code, self.syntax.nodes.items[@backingInt(call.arguments[1])].span, "sorted key must be written as key=callback");
            return;
        }
        if (call.argument_names[0] != null) return self.sink.fail(call_argument_code, call.argument_names[0].?, "the sorted list is positional");
        if (call.arguments.len != 2 or call.argument_names[1] == null or !std.mem.eql(u8, self.src.text(call.argument_names[1].?), "key"))
            return self.sink.fail(call_argument_code, call.name, "sorted accepts only the named argument key=callback");
    }
    fn hintSortedArguments(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
        try self.validateSortedArguments(call);
        if (call.arguments.len != 2) return;
        const input = self.syntax.nodes.items[@backingInt(call.arguments[0])];
        const input_type = if (self.resolved[@backingInt(call.arguments[0])]) |value|
            self.nodes.items[@backingInt(value)].ty
        else if (input.data == .name) name: {
            const slot = self.active.get(self.src.text(input.data.name)) orelse return;
            break :name self.locals.items[@backingInt(slot)].ty;
        } else return;
        if (!input_type.isAggregate()) return self.sink.fail("E_PRELUDE_TYPE", input.span, "sorted key requires a list input");
        const input_schema = self.catalog.records[input_type.recordIndex()];
        if (!input_schema.managed or input_schema.collection.kind != .list)
            return self.sink.fail("E_PRELUDE_TYPE", input.span, "sorted key requires a list input");
        const element = input_schema.shape.buffer.?;
        const parameters = try self.allocator.dupe(typed.Type, &.{element});
        const callback = try callables.intern(self.allocator, &self.catalog, .{ .parameters = parameters, .return_type = .i64, .effects = 0 }, call.argument_names[1].?, self.sink);
        try self.hint(call.arguments[1], callback);
    }
    /// Whole-path file helpers are reserved under the same shadowing rule as `print`.
    fn fileAccessBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?file_operations.Access {
        if (call.owner != null) return null;
        const name = self.src.text(call.name);
        const kind = file_operations.access(name) orelse return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        return kind;
    }
    fn fileShapes(self: *Checker, span: source.Span) Error!typed.FileShapes {
        const text = try collections.preludeType(&self.catalog, "str", span);
        const bytes = try collections.preludeType(&self.catalog, "bytes", span);
        return .{ .text = text, .bytes = bytes, .list = try collections.listType(&self.catalog, text, span) };
    }
    /// The declared result of one whole-path helper, given the open mode it saw.
    fn fileAccessType(self: *Checker, kind: file_operations.Access, mode: file_operations.Mode, span: source.Span) Error!typed.Type {
        const shapes = try self.fileShapes(span);
        const payload: typed.Type = switch (kind) {
            .open => if (mode.text) .text_file else .file,
            .read_file => shapes.bytes,
            .read_text => shapes.text,
            .listdir => shapes.list,
            .exists => return .bool,
            else => .unit,
        };
        return collections.resultType(&self.catalog, payload, shapes.text, span);
    }
    fn checkFileAccess(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0 or call.arguments.len != kind.arity()) return self.sink.fail("E_ARITY", node.span, "this file operation's argument count does not match its signature");
        const shapes = try self.fileShapes(node.span);
        const arguments = try self.allocator.alloc(typed.NodeId, call.arguments.len);
        for (call.arguments, arguments) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
        try self.require(self.nodes.items[@backingInt(arguments[0])].ty, .filesystem_cap, node.span);
        try self.require(self.nodes.items[@backingInt(arguments[1])].ty, shapes.text, self.nodes.items[@backingInt(arguments[1])].span);
        const mode = try self.openMode(call, kind);
        if (kind == .write_file) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.bytes, node.span);
        if (kind == .write_text) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.text, node.span);
        const direct = kind == .open and self.trapping_open != null and std.meta.eql(self.trapping_open.?, node.span);
        out.ty = if (direct) (if (mode.text) .text_file else .file) else try self.fileAccessType(kind, mode, node.span);
        out.data = .{ .file_access = .{ .kind = kind, .mode = mode.letter, .text = mode.text, .arguments = arguments, .shapes = shapes } };
    }
    /// `open` needs a literal mode so the checker knows whether reads yield text.
    fn openMode(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access) Error!file_operations.Mode {
        if (kind != .open) return .{ .letter = 'r', .text = kind == .read_text or kind == .write_text };
        const spelling = self.syntax.nodes.items[@backingInt(call.arguments[2])];
        if (spelling.data != .text) return self.sink.fail(eFileArgument, spelling.span, "open requires a literal mode such as \"rb\", \"r\", \"wb\", \"w\", \"ab\" or \"a\"");
        return file_operations.parseMode(spelling.data.text) orelse self.sink.fail(eFileArgument, spelling.span, "unsupported open mode; use \"r\", \"w\", \"a\" with an optional \"b\" or \"t\"");
    }
    /// A file method's result type follows its receiver's text or binary mode.
    fn checkFileMethod(self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "file_operation"), out: *typed.Node) Error!void {
        const slot = self.active.get(self.src.text(operation.owner)).?;
        const text = self.locals.items[@backingInt(slot)].ty == .text_file;
        const shapes = try self.fileShapes(node.span);
        const element: typed.Type = if (text) shapes.text else shapes.bytes;
        const argument: ?typed.NodeId = if (operation.argument) |id| self.resolved[@backingInt(id)].? else null;
        if (operation.kind == .write) try self.require(self.nodes.items[@backingInt(argument.?)].ty, element, node.span);
        if (operation.kind == .read) if (argument) |id| try self.require(self.nodes.items[@backingInt(id)].ty, .i64, node.span);
        out.ty = switch (operation.kind) {
            .read, .readline => element,
            .readlines => try collections.listType(&self.catalog, element, node.span),
            .write => .i64,
            .flush, .close => .unit,
        };
        out.data = .{ .file_method = .{ .kind = operation.kind, .owner = slot, .text = text, .argument = argument, .shapes = shapes } };
    }
    /// `print`/`eprint` are reserved unless a local binding or declared function shadows the spelling.
    fn outputBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Sink {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.src.text(call.name);
        const sink: typed.Sink = if (std.mem.eql(u8, name, "print")) .stdout else if (std.mem.eql(u8, name, "eprint")) .stderr else return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        return sink;
    }
    fn checkPrintOperand(self: *Checker, id: ast.NodeId, expected_text: bool) Error!typed.NodeId {
        const value = self.resolved[@backingInt(id)].?;
        const ty_value = self.nodes.items[@backingInt(value)].ty;
        if (expected_text) {
            const text_type = try collections.preludeType(&self.catalog, "str", self.nodes.items[@backingInt(value)].span);
            try self.require(ty_value, text_type, self.nodes.items[@backingInt(value)].span);
            return value;
        }
        if (!io_render.printable(ty_value, self.catalog.records)) return self.sink.fail(
            io_builtins.argument_code,
            self.nodes.items[@backingInt(value)].span,
            "print cannot render this value; capabilities, files, owned resources and callbacks have no Python spelling",
        );
        return value;
    }
    fn checkPrint(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), sink: typed.Sink, out: *typed.Node) Error!void {
        const split = try io_builtins.printArguments(self.src, call, self.sink);
        const arguments = try self.allocator.alloc(typed.NodeId, split.values.len);
        for (split.values, arguments) |id, *slot| slot.* = try self.checkPrintOperand(id, false);
        out.ty = .unit;
        out.data = .{ .print = .{
            .sink = sink,
            .arguments = arguments,
            .separator = if (split.separator) |id| try self.checkPrintOperand(id, true) else null,
            .terminator = if (split.terminator) |id| try self.checkPrintOperand(id, true) else null,
        } };
        _ = node;
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
                    if (call.type_arguments.len != 0 or call.arguments.len > most or call.arguments.len < least) return self.sink.fail("E_ARITY", node.span, "file method argument count does not match its signature");
                    node.data = .{ .file_operation = .{ .kind = kind, .owner = owner, .argument = if (call.arguments.len == 0) null else call.arguments[0] } };
                    return node;
                }
                if (value_type.isAggregate() and self.catalog.records[value_type.recordIndex()].managed) {
                    try call_arguments.positional(call, self.sink);
                    const name = self.src.text(call.name);
                    const kind = buffer_operations.method(name) orelse {
                        _ = try @import("removed_names.zig").reject(self.sink, call.name, name);
                        return self.sink.fail("E_LIST_METHOD", call.name, "unknown managed collection method");
                    };
                    // The everyday vocabulary stays a buffer operation; the
                    // checker picks its arity from the receiver and `pop` name.
                    if (!buffer_operations.vocabulary(kind) and (call.type_arguments.len != 0 or call.arguments.len != kind.arity()))
                        return self.sink.fail("E_ARITY", node.span, "list method argument count does not match its signature");
                    node.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = call.arguments } };
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
        value = try self.expressionWithTemporaries(assignment.value, temporaries);
        try self.require(self.nodes.items[@backingInt(value)].ty, expected, node.span);
        if (destination.index == null) try self.requireArenaStore(destination.owner, value);
        const assigned = try b.local(expected);
        const evaluate_value = try b.stmt(.{ .initialize = .{ .slot = assigned, .value = value } });
        // The assigned value is computed before the destination is refreshed.
        try statements.insert(self.allocator, 0, evaluate_value);
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
    /// Check `values[index] op= value` by reading the slot once, combining the pair with
    /// the operator's ordinary rules and writing the result back through the same slot.
    fn checkIndexAugmented(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const assignment = node.data.index_assignment;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        var statements: std.ArrayList(typed.StatementId) = .empty;
        const destination = try self.fieldDestination(self.syntax.nodes.items[@backingInt(assignment.target)], &statements, temporaries);
        const index = destination.index orelse return self.sink.fail("E_ASSIGNMENT_TARGET", node.span, "augmented assignment requires a list slot or dictionary entry");
        const element = self.nodes.items[@backingInt(destination.value)].ty;
        try self.hint(assignment.value, element);
        const right = try self.expressionWithTemporaries(assignment.value, temporaries);
        try self.require(self.nodes.items[@backingInt(right)].ty, element, node.span);
        const combined = try self.augmented(assignment.op, destination.value, right, node.span);
        const stored = try b.local(element);
        const evaluate_value = try b.stmt(.{ .initialize = .{ .slot = stored, .value = combined } });
        // Python reads the slot first, then evaluates the assigned value and writes back.
        try statements.append(self.allocator, evaluate_value);
        try statements.append(self.allocator, try b.stmt(.{ .discard = try b.operation(destination.owner, .write, &.{ index, try b.read(stored) }) }));
        return b.block(statements.items, try b.node(.unit, .unit));
    }
    /// Combine one augmented-assignment operand pair with the operator's checked rules.
    fn augmented(self: *Checker, op: ast.AssignmentOp, left: typed.NodeId, right: typed.NodeId, span: source.Span) Error!typed.NodeId {
        const left_type = self.nodes.items[@backingInt(left)].ty;
        if (numeric_surface.isFloat(left_type, self.catalog.records)) {
            const builder = self.numericBuilder(span);
            return builder.append(try builder.binary(augmentedOperator(op), left, right, self.sink));
        }
        if (left_type.isAggregate() and self.catalog.records[left_type.recordIndex()].managed) {
            const sequence = self.catalog.records[left_type.recordIndex()].collection.kind;
            if (op != .add or sequence == .dictionary) return self.sink.fail(eTextOperator, span, "a managed collection augments with `+=` only, and str, bytes and list are the types that support it");
        } else {
            try self.requireInteger(left_type, span);
            if (op == .div) return self.sink.fail("E_TYPE", span, "augmented `/=` produces a float; declare the binding as float or use `//=`");
        }
        const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
        return b.node(left_type, .{ .binary = .{
            .op = std.meta.stringToEnum(typed.BinaryOp, @tagName(augmentedOperator(op))).?,
            .left = left,
            .right = right,
            .op_span = span,
        } });
    }
    fn fieldDestination(self: *Checker, root: ast.Node, statements: *std.ArrayList(typed.StatementId), temporaries: []const typed.Type) Error!FieldDestination {
        const b: collections.Builder(Checker) = .{ .checker = self, .span = root.span };
        if (root.data == .name) {
            const owner = try self.resolve(root.data.name);
            try self.requireReadable(owner, root.data.name);
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
        const base = try self.expressionWithTemporaries(access.base, temporaries);
        const ty_value = self.nodes.items[@backingInt(base)].ty;
        if (!ty_value.isAggregate() or !self.catalog.records[ty_value.recordIndex()].managed) return self.sink.fail(eCollectionMethod, root.span, "indexed field assignment requires a list or dictionary");
        const schema = self.catalog.records[ty_value.recordIndex()];
        if (schema.collection.kind == .string or schema.collection.kind == .bytes) return self.sink.fail(eCollectionMethod, root.span, "str and bytes are immutable");
        const element = schema.shape.buffer.?;
        const owner = try b.local(ty_value);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = owner, .value = base } }));
        const index_value = try self.expressionWithTemporaries(access.index, temporaries);
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
    /// Build a fixed array from a list literal whose context already demands `[N]T`.
    fn checkFixedArray(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type, expected: typed.Type) Error!typed.Node {
        const shape = arrays.fixed(self.catalog, expected).?;
        if (inputs.len != shape.length) return arrays.wrongLength(self.allocator, node.span, inputs.len, shape, self.sink);
        const values = try self.allocator.alloc(typed.NodeId, inputs.len);
        for (inputs, values) |input, *value| {
            try self.hint(input, shape.element);
            value.* = try self.expressionWithTemporaries(input, temporaries);
            try self.require(self.nodes.items[@backingInt(value.*)].ty, shape.element, self.syntax.nodes.items[@backingInt(input)].span);
        }
        return .{ .span = node.span, .ty = expected, .data = .{ .array = values } };
    }
    fn checkListLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
        var expected = self.expected_types.get(node.span);
        if (expected) |ty_value| if (arrays.fixed(self.catalog, ty_value) != null) return self.checkFixedArray(node, inputs, temporaries, ty_value);
        var element: ?typed.Type = if (expected) |ty_value| try self.listElement(ty_value, node.span) else null;
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
    fn bindElement(self: *Checker, name: source.Span, slot: typed.LocalId) Error!void {
        const text = self.src.text(name);
        if (try self.topLevel(name) or self.active.contains(text)) return self.sink.fail(eShadowing, name, "comprehension binding shadows an active declaration");
        self.locals.items[@backingInt(slot)].name = text;
        self.locals.items[@backingInt(slot)].declaration = name;
        self.locals.items[@backingInt(slot)].ownership.initialized = true;
        try self.active.put(self.allocator, text, slot);
    }

    /// Build `[value for name in source if condition]` as a checked loop over a fresh list,
    /// drawing elements from a collection or, like a `for` loop, from an integer `range(...)`.
    fn checkComprehension(self: *Checker, node: ast.Node, each: ast.Comprehension, temporaries: []const typed.Type) Error!typed.Node {
        const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        const iterable_node = switch (each.source) {
            .range => |bounds| return self.checkRangeComprehension(b, node, each, bounds),
            .iterable => |iterable| iterable,
        };
        const iterable = try self.expressionWithTemporaries(iterable_node, temporaries);
        const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
        if (!iterable_type.isAggregate() or !self.catalog.records[iterable_type.recordIndex()].managed) return self.sink.fail(eCollectionMethod, node.span, "iteration requires a list, str, or dictionary");
        const schema = self.catalog.records[iterable_type.recordIndex()];
        const element = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .string => iterable_type,
            .bytes => typed.Type.i64,
            .dictionary => schema.collection.key.?,
        };
        const owner = try b.local(iterable_type);
        const index = try b.local(.i64);
        const limit = try b.local(.i64);
        const value_slot = try b.local(element);
        const parts = try self.comprehensionBody(b, node, each, value_slot);
        return self.comprehensionLoop(b, .{ .owner = owner, .index = index, .limit = limit, .slot = value_slot }, parts.body, .{ .iterable = iterable, .output = parts.output, .kind = schema.collection.kind });
    }

    /// Check the produced value and optional filter with `slot` bound to the element name,
    /// returning the fresh output list and the retained-append body the loop repeats. Shared
    /// by the collection and range forms so both keep one element-storability contract.
    fn comprehensionBody(self: *Checker, b: collections.Builder(Checker), node: ast.Node, each: ast.Comprehension, slot: typed.LocalId) Error!struct { output: typed.LocalId, body: typed.StatementId } {
        try self.bindElement(each.name, slot);
        defer _ = self.active.remove(self.src.text(each.name));
        const produced = try self.expression(each.output);
        const produced_type = self.nodes.items[@backingInt(produced)].ty;
        if (!typed.storable(produced_type, self.catalog.records) or typed.moveOnly(produced_type, self.catalog.records) or self.requiresHandling(produced_type))
            return self.sink.fail(eListType, node.span, "list elements require copyable storable values without pending results");
        const output = try b.local(try collections.listType(&self.catalog, produced_type, node.span));
        const kept = try b.stmt(.{ .discard = try b.operation(output, .append, &.{produced}) });
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
    fn checkRangeComprehension(self: *Checker, b: collections.Builder(Checker), node: ast.Node, each: ast.Comprehension, bounds: @FieldType(ast.Comprehension.Source, "range")) Error!typed.Node {
        const zero_start = self.syntax.nodes.items[@backingInt(bounds.start)].data == .unit;
        const start = if (zero_start) try b.integer(0) else try self.expression(bounds.start);
        const end = try self.expression(bounds.end);
        const element = self.nodes.items[@backingInt(start)].ty;
        try self.requireInteger(element, each.name);
        try self.require(self.nodes.items[@backingInt(end)].ty, element, self.syntax.nodes.items[@backingInt(bounds.end)].span);
        const index = try b.local(element);
        const limit = try b.local(element);
        const parts = try self.comprehensionBody(b, node, each, index);
        const i = try b.read(index);
        const step = try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.node(element, .{ .integer = 1 }), element) } });
        const loop_id = self.loops.next;
        self.loops.next += 1;
        return b.block(&.{
            try b.stmt(.{ .initialize = .{ .slot = index, .value = start } }),
            try b.stmt(.{ .initialize = .{ .slot = limit, .value = end } }),
            try b.stmt(.{ .initialize = .{ .slot = parts.output, .value = try b.node(self.locals.items[@backingInt(parts.output)].ty, .{ .acquire_buffer = .{ .capacity = try b.integer(0) } }) } }),
            try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = parts.body, .step = step } }),
        }, try b.read(parts.output));
    }

    /// Assemble the fixed-bound iteration, its mutation check, and the produced list.
    fn comprehensionLoop(
        self: *Checker,
        b: collections.Builder(Checker),
        slots: struct { owner: typed.LocalId, index: typed.LocalId, limit: typed.LocalId, slot: typed.LocalId },
        body: typed.StatementId,
        source_values: struct { iterable: typed.NodeId, output: typed.LocalId, kind: ManagedKind },
    ) Error!typed.Node {
        const i = try b.read(slots.index);
        const guard = try b.stmt(.{ .discard = try b.operation(slots.owner, .iteration_check, &.{try b.read(slots.limit)}) });
        const iteration = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            guard,
            try b.stmt(.{ .initialize = .{ .slot = slots.slot, .value = try self.iterationValue(b, slots.owner, source_values.kind, i) } }),
            body,
        }) });
        const step = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            guard,
            try b.stmt(.{ .assign = .{ .slot = slots.index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
        }) });
        const loop_id = self.loops.next;
        self.loops.next += 1;
        return b.block(&.{
            try b.stmt(.{ .initialize = .{ .slot = slots.owner, .value = source_values.iterable } }),
            try b.stmt(.{ .initialize = .{ .slot = slots.index, .value = try b.integer(0) } }),
            try b.stmt(.{ .initialize = .{ .slot = slots.limit, .value = try b.length(slots.owner) } }),
            try b.stmt(.{ .initialize = .{ .slot = source_values.output, .value = try b.node(self.locals.items[@backingInt(source_values.output)].ty, .{ .acquire_buffer = .{ .capacity = try b.integer(0) } }) } }),
            try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(slots.limit), .bool), .body = iteration, .step = step } }),
        }, try b.read(source_values.output));
    }

    /// Convert one interpolated value to text. A hole takes whatever `print` can
    /// render, through the same renderer, so one value has one spelling.
    fn formatPart(self: *Checker, value: typed.NodeId, str_type: typed.Type, span: source.Span) Error!typed.NodeId {
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

    /// Concatenate an f-string's literal chunks and converted interpolations.
    fn checkFormat(self: *Checker, node: ast.Node, parts: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
        const str_type = self.catalog.names.get("str") orelse return error.InternalError;
        const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        var result: ?typed.NodeId = null;
        for (parts) |part| {
            const span = self.syntax.nodes.items[@backingInt(part)].span;
            const value = try self.formatPart(try self.expressionWithTemporaries(part, temporaries), str_type, span);
            result = if (result) |left| try builder.binary(.add, left, value, str_type) else value;
        }
        return self.nodes.items[@backingInt(result orelse return error.InternalError)];
    }

    fn checkCollectionMethod(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const call = node.data.method_call;
        const name = self.src.text(call.name);
        _ = try @import("removed_names.zig").reject(self.sink, call.name, name);
        const kind = buffer_operations.method(name) orelse return self.sink.fail("E_COLLECTION_METHOD", call.name, "unknown managed collection method");
        return self.checkListAccess(node, .{ .base = call.base, .kind = kind, .inputs = call.arguments }, temporaries);
    }
    fn checkCollectionSlice(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const slice = node.data.slice;
        const base = try self.expressionWithTemporaries(slice.base, temporaries);
        const input = self.nodes.items[@backingInt(base)].ty;
        if (!input.isAggregate() or !self.catalog.records[input.recordIndex()].managed) return self.sink.fail(eCollectionMethod, node.span, "slicing requires a list or str");
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
    fn checkListAccess(self: *Checker, node: ast.Node, operation: struct { base: ast.NodeId, kind: BufferKind, inputs: []const ast.NodeId, signed_length: bool = false }, temporaries: []const typed.Type) Error!typed.Node {
        const base_input = operation.base;
        var kind = operation.kind;
        const inputs = operation.inputs;
        const base = try self.expressionWithTemporaries(base_input, temporaries);
        const owner_type = self.nodes.items[@backingInt(base)].ty;
        const managed_owner = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].managed;
        const dictionary = managed_owner and self.catalog.records[owner_type.recordIndex()].collection.kind == .dictionary;
        // `pop` is one Python name with an optional argument; its arity selects the
        // list-tail, list-index, dictionary-key or dictionary-default form.
        if (kind == .pop) kind = if (dictionary) (if (inputs.len == 2) .pop_default else .pop_key) else (if (inputs.len == 1) .pop_at else .pop);
        if (managed_owner and self.catalog.records[owner_type.recordIndex()].collection.kind != .list) {
            const receiver = self.arenaReceiver(base_input);
            return self.checkManagedAccess(node, .{ .base = base, .kind = kind, .inputs = inputs, .receiver = receiver }, temporaries);
        }
        if (switch (kind) {
            .extend, .insert, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => true,
            else => false,
        }) return self.checkListMethod(node, .{ .base = base, .base_input = base_input, .kind = kind, .inputs = inputs, .temporaries = temporaries });
        const supported = switch (kind) {
            .append, .read, .write, .length, .contains => true,
            else => false,
        };
        if (!supported) return self.sink.fail(eCollectionMethod, node.span, unsupported_list);
        const element = try self.listElement(self.nodes.items[@backingInt(base)].ty, node.span);
        if (inputs.len != kind.arity()) return self.sink.fail("E_ARITY", node.span, method_arity);
        const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
        for (inputs, arguments, 0..) |input, *argument, i| {
            const writes_element = kind == .append or kind == .contains or (kind == .write and i == 1);
            if (writes_element) try self.hint(input, element);
            argument.* = try self.expressionWithTemporaries(input, temporaries);
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            if (writes_element) try self.require(actual, element, node.span) else try self.requireInteger(actual, node.span);
        }
        try self.requireArenaOperation(self.arenaReceiver(base_input), kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, arguments, operation.signed_length);
    }
    /// Check a list's Python-shaped method call, which either mutates or copies its receiver.
    fn checkListMethod(self: *Checker, node: ast.Node, call: ListMethodCall) Error!typed.Node {
        const base = call.base;
        const base_input = call.base_input;
        const kind = call.kind;
        const inputs = call.inputs;
        const temporaries = call.temporaries;
        const owner_type = self.nodes.items[@backingInt(base)].ty;
        const element = try self.listElement(owner_type, node.span);
        if (inputs.len != kind.arity()) return self.sink.fail("E_ARITY", node.span, method_arity);
        if (kind == .sort and !(element.isInteger() or numeric_surface.isFloat(element, self.catalog.records))) {
            return self.sink.fail(eCollectionMethod, node.span, "sort requires an integer or float element type");
        }
        const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
        switch (kind) {
            .extend => {
                try self.hint(inputs[0], owner_type);
                arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, owner_type, node.span);
            },
            .insert => {
                try self.hint(inputs[0], .i64);
                arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
                try self.requireInteger(self.nodes.items[@backingInt(arguments[0])].ty, node.span);
                try self.hint(inputs[1], element);
                arguments[1] = try self.expressionWithTemporaries(inputs[1], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[1])].ty, element, node.span);
            },
            .pop_at => {
                try self.hint(inputs[0], .i64);
                arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
                try self.requireInteger(self.nodes.items[@backingInt(arguments[0])].ty, node.span);
            },
            .remove, .index_of => {
                try self.hint(inputs[0], element);
                arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, element, node.span);
            },
            .pop, .reverse, .sort, .copy, .clear => {},
            else => return self.sink.fail(eCollectionMethod, node.span, unsupported_list),
        }
        try self.requireArenaOperation(self.arenaReceiver(base_input), kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, arguments, false);
    }

    fn checkManagedAccess(self: *Checker, node: ast.Node, operation: ManagedAccess, temporaries: []const typed.Type) Error!typed.Node {
        const owner_type = self.nodes.items[@backingInt(operation.base)].ty;
        const schema = self.catalog.records[owner_type.recordIndex()];
        const dictionary = schema.collection.kind == .dictionary;
        _ = collections.operationType(&self.catalog, owner_type, operation.kind, node.span) catch |err| switch (err) {
            error.InternalError => return self.sink.fail(eCollectionMethod, node.span, unsupported_collection),
            else => return err,
        };
        if (dictionary and switch (operation.kind) {
            .items, .update, .setdefault, .pop_key, .pop_default, .copy, .clear => true,
            else => false,
        }) return self.checkDictionaryMethod(node, owner_type, operation, temporaries);
        if (operation.inputs.len != operation.kind.arity()) return self.sink.fail("E_ARITY", node.span, method_arity);
        const arguments = try self.allocator.alloc(typed.NodeId, operation.inputs.len);
        for (operation.inputs, arguments, 0..) |input, *argument, index| {
            const integer = !dictionary and (operation.kind == .read or operation.kind == .slice or widthArgument(operation.kind));
            const expected = if (integer) typed.Type.i64 else if (dictionary) map_argument: {
                break :map_argument if (index == 0) schema.collection.key.? else schema.shape.buffer.?;
            } else if (operation.kind == .join) try self.collectionListType(owner_type, node.span) else owner_type;
            try self.hint(input, expected);
            argument.* = try self.expressionWithTemporaries(input, temporaries);
            if (integer) try self.requireInteger(self.nodes.items[@backingInt(argument.*)].ty, node.span) else try self.require(self.nodes.items[@backingInt(argument.*)].ty, expected, node.span);
        }
        try self.requireArenaOperation(operation.receiver, operation.kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
    }
    /// Check a dictionary's Python-shaped methods against its key and value types.
    fn checkDictionaryMethod(self: *Checker, node: ast.Node, owner_type: typed.Type, operation: ManagedAccess, temporaries: []const typed.Type) Error!typed.Node {
        const schema = self.catalog.records[owner_type.recordIndex()];
        const key_type = schema.collection.key.?;
        const value_type = schema.shape.buffer.?;
        if (operation.inputs.len != operation.kind.arity()) return self.sink.fail("E_ARITY", node.span, method_arity);
        const arguments = try self.allocator.alloc(typed.NodeId, operation.inputs.len);
        switch (operation.kind) {
            .items, .copy, .clear => {},
            .update => {
                try self.hint(operation.inputs[0], owner_type);
                arguments[0] = try self.expressionWithTemporaries(operation.inputs[0], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, owner_type, node.span);
            },
            .pop_key => {
                try self.hint(operation.inputs[0], key_type);
                arguments[0] = try self.expressionWithTemporaries(operation.inputs[0], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, key_type, node.span);
            },
            .pop_default, .setdefault => {
                try self.hint(operation.inputs[0], key_type);
                arguments[0] = try self.expressionWithTemporaries(operation.inputs[0], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, key_type, node.span);
                try self.hint(operation.inputs[1], value_type);
                arguments[1] = try self.expressionWithTemporaries(operation.inputs[1], temporaries);
                try self.require(self.nodes.items[@backingInt(arguments[1])].ty, value_type, node.span);
            },
            else => return self.sink.fail(eCollectionMethod, node.span, "operation is not supported by dictionaries"),
        }
        try self.requireArenaOperation(operation.receiver, operation.kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
    }

    fn hintBufferArguments(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation)) Error!void {
        if (self.active.get(self.src.text(operation.owner))) |slot| {
            const owner_type = self.locals.items[@backingInt(slot)].ty;
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
                } else if (sequenceArgument(operation.kind) and operation.arguments.len == 1) {
                    const byte_needle = schema.collection.kind == .bytes and operation.kind == .contains;
                    if (!byte_needle) try self.hint(operation.arguments[0], owner_type);
                }
                return;
            }
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
            if (function) |function_id| {
                try self.hint(argument, try self.functionType(function_id, parameter.ty));
            } else if (self.catalog.arrays.resolved.get(parameter.ty.start)) |closed| {
                try self.hint(argument, closed);
            } else if (typed.Type.fromName(self.src.text(parameter.ty))) |closed| {
                try self.hint(argument, closed);
            }
        }
    }
    fn queueBuiltinCall(self: *Checker, work: *std.ArrayList(Work), call_id: ast.NodeId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), node: ast.Node) Error!bool {
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
        if (self.byteConversion(call) != null) {
            try call_arguments.positional(call, self.sink);
            if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "byte conversions require one argument");
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
        if (try self.outputBuiltin(call)) |_| {
            _ = try io_builtins.printArguments(self.src, call, self.sink);
            // Only a keyword operand needs the text type, and only then is it materialized.
            const text_type = if (call.argument_names.len == 0) null else try collections.preludeType(&self.catalog, "str", node.span);
            var index = call.arguments.len;
            while (index > 0) {
                index -= 1;
                if (call.argument_names.len != 0 and call.argument_names[index] != null) try self.hint(call.arguments[index], text_type.?);
                try work.append(self.allocator, .{ .id = call.arguments[index] });
            }
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
    fn hintByteArray(self: *Checker, id: ast.NodeId) Error!void {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data != .list_literal) return;
        const bytes = try self.catalog.instantiateArray(self.allocator, .u8, node.data.list_literal.len, node.span, self.sink);
        try self.hint(id, bytes);
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
            } else if (arrays.table(self.catalog, expected_type)) |_| {
                if (index % 2 == 1) try self.hint(entries[index], self.catalog.records[expected_type.recordIndex()].shape.array.?.element);
            };
            try work.append(self.allocator, .{ .id = entries[index] });
        }
        return true;
    }
    /// Resolve a variant construction's type, letting a generic template adopt its context.
    fn variantType(self: *Checker, variant: @FieldType(@FieldType(ast.Node, "data"), "variant"), at: source.Span) Error!typed.Type {
        if (try variant_calls.contextual(self.src, self.catalog, variant.ty, self.expected_types.get(at), self.sink)) |found| return found;
        return self.ty(variant.ty);
    }
    fn queueVariant(self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId, variant: @FieldType(@FieldType(ast.Node, "data"), "variant")) Error!bool {
        if (variant.value) |value| {
            const variant_type = try self.variantType(variant, self.syntax.nodes.items[@backingInt(id)].span);
            const tag = try self.catalog.variant(variant_type, self.src, variant.name, self.sink);
            if (self.catalog.records[variant_type.recordIndex()].shape.variants.?.cases[tag].payload) |payload| try self.hint(value, payload);
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try work.append(self.allocator, .{ .id = value });
            return true;
        }
        return false;
    }
    fn queueExpression(self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId) Error!bool {
        const node = try self.collectionSyntax(id);
        switch (node.data) {
            .file_operation => |operation| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                if (operation.argument) |value| try work.append(self.allocator, .{ .id = value });
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
                try self.hintByteArray(get.name);
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
            .dictionary_literal => return self.queueDictionary(work, id),
            .record => |record| {
                try self.hintRecordFields(record);
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
                try work.append(self.allocator, .{ .id = id, .emit = true });
                if (try self.queueBuiltinCall(work, id, call, node)) return true;
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
                try self.hintCallArguments(target.call, target.declaration, target.call, node.span);
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
    fn collectionListType(self: *Checker, element: typed.Type, span: source.Span) Error!typed.Type {
        const state = self.catalog.templates.store orelse return error.InternalError;
        return @import("nominal_catalog.zig").instantiateLengths(&self.catalog, state.index.names.get("List").?, &.{element}, &.{}, span);
    }
    fn checkTextDictionary(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
        const local = self.locals.items[@backingInt(owner)];
        const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;

        const schema = self.catalog.records[local.ty.recordIndex()];
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments) |input, *argument| argument.* = self.resolved[@backingInt(input)].?;
        const dictionary = schema.collection.kind == .dictionary;
        const byte_string = schema.collection.kind == .bytes;
        const output_element = if (dictionary or byte_string) element else local.ty;
        switch (operation.kind) {
            .length => out.ty = .i64,
            .find, .starts_with, .ends_with => {
                if (dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "prefix, suffix and search operations require str or bytes");
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, local.ty, operation.owner);
                out.ty = if (operation.kind == .find) .i64 else .bool;
            },
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .count, .zfill, .is_digit, .is_alpha, .is_space, .parse_int, .parse_float => {
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
            .to_list, .hex, .decode, .encode, .from_hex => out.ty = collections.operationType(&self.catalog, local.ty, operation.kind, operation.owner) catch |err| switch (err) {
                error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, "conversion is not supported by this collection"),
                else => return err,
            },
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
                out.ty = try self.collectionListType(if (operation.kind == .keys) schema.collection.key.? else element, operation.owner);
            },
            .split, .join => {
                if (dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "split and join require str");
                const list_type = try self.collectionListType(local.ty, operation.owner);
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, if (operation.kind == .split) local.ty else list_type, operation.owner);
                out.ty = if (operation.kind == .split) list_type else local.ty;
            },
            .items, .pop, .pop_key, .pop_default, .update, .setdefault, .copy, .clear => return self.checkDictionaryBufferMethod(operation, owner, out),
            else => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
        }
        out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
    }
    /// Check a dictionary vocabulary operation reached through the buffer-operation
    /// form that a simple `mapping.method(...)` call desugars to.
    fn checkDictionaryBufferMethod(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
        const owner_type = self.locals.items[@backingInt(owner)].ty;
        const schema = self.catalog.records[owner_type.recordIndex()];
        if (schema.collection.kind != .dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "operation is not supported by this collection");
        const key_type = schema.collection.key.?;
        const value_type = schema.shape.buffer.?;
        var kind = operation.kind;
        if (kind == .pop) kind = if (operation.arguments.len == 2) .pop_default else .pop_key;
        if (operation.arguments.len != kind.arity()) return self.sink.fail("E_ARITY", operation.owner, method_arity);
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments, 0..) |input, *argument, index| {
            argument.* = self.resolved[@backingInt(input)].?;
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            const span = self.syntax.nodes.items[@backingInt(input)].span;
            switch (kind) {
                .items, .copy, .clear => {},
                .update => try self.require(actual, owner_type, span),
                .pop_key => try self.require(actual, key_type, span),
                .pop_default, .setdefault => if (index == 0) try self.require(actual, key_type, span) else try self.require(actual, value_type, span),
                else => {},
            }
        }
        try self.requireArenaOperation(owner, kind, arguments);
        out.ty = collections.operationType(&self.catalog, owner_type, kind, operation.owner) catch |err| switch (err) {
            error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
            else => return err,
        };
        out.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = arguments } };
    }

    fn checkBufferOperation(self: *Checker, _: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), out: *typed.Node) Error!void {
        const owner = try self.resolve(operation.owner);
        const local = &self.locals.items[@backingInt(owner)];
        if (!local.ty.isAggregate() or !self.catalog.records[local.ty.recordIndex()].managed) return self.sink.fail(eListType, operation.owner, needs_list);
        local.usage.reads += 1;
        if (operation.kind.mutates()) local.usage.writes += 1;
        const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;
        if (self.catalog.records[local.ty.recordIndex()].collection.kind != .list) {
            try self.checkTextDictionary(operation, owner, out);
            return;
        }
        switch (operation.kind) {
            .append, .read, .write, .length, .capacity, .contains, .iteration_check => {},
            .extend, .insert, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => {
                try self.checkListBufferMethod(operation, owner, out);
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
        try self.requireArenaOperation(owner, operation.kind, arguments);
        out.ty = if (operation.kind.mutates()) .unit else if (operation.kind == .read) element else if (operation.kind == .contains) .bool else .u64;
        out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
    }
    /// Check a list vocabulary operation reached through the buffer-operation form
    /// that a simple `values.method(...)` call desugars to.
    fn checkListBufferMethod(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
        const owner_type = self.locals.items[@backingInt(owner)].ty;
        const element = self.catalog.records[owner_type.recordIndex()].shape.buffer.?;
        var kind = operation.kind;
        if (kind == .pop) kind = if (operation.arguments.len == 1) .pop_at else .pop;
        if (operation.arguments.len != kind.arity()) return self.sink.fail("E_ARITY", operation.owner, method_arity);
        if (kind == .sort and !(element.isInteger() or numeric_surface.isFloat(element, self.catalog.records))) {
            return self.sink.fail(eCollectionMethod, operation.owner, "sort requires an integer or float element type");
        }
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments, 0..) |input, *argument, index| {
            argument.* = self.resolved[@backingInt(input)].?;
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            const span = self.syntax.nodes.items[@backingInt(input)].span;
            switch (kind) {
                .extend => try self.require(actual, owner_type, span),
                .insert => if (index == 0) try self.requireInteger(actual, span) else try self.require(actual, element, span),
                .pop_at => try self.requireInteger(actual, span),
                .remove, .index_of => try self.require(actual, element, span),
                else => {},
            }
        }
        try self.requireArenaOperation(owner, kind, arguments);
        out.ty = collections.operationType(&self.catalog, owner_type, kind, operation.owner) catch |err| switch (err) {
            error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
            else => return err,
        };
        out.data = .{ .buffer_operation = .{ .kind = kind, .owner = owner, .arguments = arguments } };
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
        if (!typed.acquisitionBytes(request_type, self.catalog.records)) return self.sink.fail("E_RESOURCE_REQUEST", self.syntax.nodes.items[@backingInt(acquire.request)].span, "request must be a fixed u8 array");
        out.data = .{ .acquire_resource = .{ .capability = capability, .request = request } };
    }
    fn checkResourceIo(self: *Checker, node: ast.Node, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io"), out: *typed.Node) Error!void {
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
        const bound = function.policy.effect_bound orelse return self.sink.fail("E_CALLBACK_EFFECTS", name, "function values require a declared effect ceiling");
        const parameters = try self.allocator.alloc(typed.Type, function.signature.parameters.len);
        if (parameters.len > 16) return self.sink.fail(callback_type_code, name, "callbacks support at most 16 parameters");
        for (function.signature.parameters, parameters) |input, *parameter| {
            parameter.* = try self.catalog.resolve(self.src, input.ty, self.sink);
        }
        const result = try self.catalog.resolve(self.src, function.signature.return_type, self.sink);
        out.ty = try callables.intern(self.allocator, &self.catalog, .{ .parameters = parameters, .return_type = result, .effects = bound.allowed }, name, self.sink);
        out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
        return true;
    }
    fn indirectCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        const slot = try self.resolve(call.name);
        const contract = callables.signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) orelse return self.sink.fail(callback_type_code, call.name, "called local is not a function value");
        if (call.type_arguments.len != 0 or call.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", call.name, "callback argument count must match its signature");
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const callee: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = call.name, .ty = self.locals.items[@backingInt(slot)].ty, .data = .{ .local = slot } });
        var arguments: std.ArrayList(typed.NodeId) = .empty;
        for (call.arguments, contract.parameters) |input, expected| {
            const value = self.resolved[@backingInt(input)].?;
            try self.require(self.nodes.items[@backingInt(value)].ty, expected, node.span);
            try arguments.append(self.allocator, value);
        }
        out.ty = contract.return_type;
        out.data = .{ .invoke = .{ .callee = callee, .arguments = try arguments.toOwnedSlice(self.allocator) } };
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
        for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, self.src.text(name))) return self.sink.fail(
            eArenaBinding,
            name,
            "an arena binding is opaque; it cannot be stored, passed, returned or compared, and its only operation is `escape(value)`",
        );
        if (self.active.get(self.src.text(name))) |bound| if (self.locals.items[@backingInt(bound)].ty.isFile()) return self.sink.fail(
            eWithResource,
            name,
            "an open file binding cannot be stored, passed or returned; call its methods instead, and iterate lines with `for line in name.readlines():`",
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
        if (!self.active.contains(self.src.text(name))) if (self.current_lambda) |lambda_index| {
            if (self.lambda_captures[lambda_index]) |captures| for (captures) |capture| {
                if (!std.mem.eql(u8, capture.name, self.src.text(name))) continue;
                const message = try std.fmt.allocPrint(self.allocator, "lambda cannot capture local `{s}`; use a top-level function or pass the value as an explicit state parameter", .{capture.name});
                return self.sink.fail("E_LAMBDA_CAPTURE", name, message);
            };
        };
        const slot = try self.resolve(name);
        try self.requireReadable(slot, name);
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
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        out.ty = self.locals.items[@backingInt(slot)].ty;
        out.data = .{ .local = slot };
    }
    /// Python-spelled byte-string constructors that are not ordinary function calls.
    const ByteConversion = enum { from_list, from_hex };
    fn byteConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?ByteConversion {
        if (self.active.contains("bytes") or self.functions.contains("bytes")) return null;
        const target = self.catalog.names.get("bytes") orelse return null;
        if (!target.isAggregate() or self.catalog.records[target.recordIndex()].collection.kind != .bytes) return null;
        if (call.owner) |owner| {
            if (!std.mem.eql(u8, self.src.text(owner), "bytes")) return null;
            return if (std.mem.eql(u8, self.src.text(call.name), "fromhex")) .from_hex else null;
        }
        return if (std.mem.eql(u8, self.src.text(call.name), "bytes")) .from_list else null;
    }
    fn checkByteConversion(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), conversion: ByteConversion, out: *typed.Node) Error!void {
        const value = self.resolved[@backingInt(call.arguments[0])].?;
        const input_type = self.nodes.items[@backingInt(value)].ty;
        const schema = if (input_type.isAggregate()) self.catalog.records[input_type.recordIndex()] else null;
        if (conversion == .from_hex) {
            if (schema == null or schema.?.collection.kind != .string) return self.sink.fail(eByteConversion, node.span, "bytes.fromhex requires a str argument");
            out.* = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(value, .from_hex, &.{}, false);
            return;
        }
        const integer_list = schema != null and schema.?.managed and schema.?.collection.kind == .list;
        if (!integer_list or schema.?.shape.buffer != .i64) return self.sink.fail(eByteConversion, node.span, "bytes() requires a list[int] argument");
        out.ty = self.catalog.names.get("bytes") orelse return error.InternalError;
        out.data = .{ .cast = value };
    }
    fn textConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!bool {
        if (call.owner != null or !std.mem.eql(u8, self.src.text(call.name), "str")) return false;
        if (self.active.contains("str") or self.functions.contains("str")) return false;
        const text_type = self.catalog.names.get("str") orelse return false;
        if (self.catalog.records[text_type.recordIndex()].collection.kind != .string) return false;
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", span, "str conversion requires one argument");
        return true;
    }
    /// `T(x)` converts between integer widths wherever `T` names an integer type rather
    /// than a function: a declared alias, or a type parameter of the enclosing signature.
    /// The fixed-width keywords reach the same node straight from the parser.
    fn typeConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Type {
        if (call.owner != null or call.arguments.len != 1 or call.argument_names.len != 0) return null;
        const name = self.src.text(call.name);
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.current_function) |id| {
            for (self.syntaxFunction(id).signature.type_parameters) |parameter| {
                if (!std.mem.eql(u8, self.src.text(parameter.name), name)) continue;
                const resolved = try self.ty(call.name);
                return if (resolved.isInteger()) resolved else null;
            }
        }
        const declared = self.catalog.names.get(name) orelse return null;
        return if (declared.isInteger()) declared else null;
    }
    fn checkTypeConversion(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), ty_value: typed.Type, out: *typed.Node) Error!void {
        const value = self.resolved[@backingInt(call.arguments[0])].?;
        try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
        out.ty = ty_value;
        out.data = .{ .cast = value };
    }
    fn checkCall(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        if (try self.checkPreludeCall(node, input, out)) return;
        if (try self.floatIntrinsic(input)) |op| return self.checkFloatIntrinsic(node, input, op, out);
        if (try self.numericConversion(input)) |floating| return self.checkNumericConversion(node, input, floating, out);
        if (try self.typeConversion(input)) |ty_value| return self.checkTypeConversion(node, input, ty_value, out);
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
        if (try self.fileAccessBuiltin(input)) |kind| return self.checkFileAccess(node, input, kind, out);
        if (try self.outputBuiltin(input)) |sink| return self.checkPrint(node, input, sink, out);
        if (self.byteConversion(input)) |conversion| return self.checkByteConversion(node, input, conversion, out);
        if (try self.resultConstructor(input)) |ok| {
            try call_arguments.positional(input, self.sink);
            return self.checkResultConstructor(node, input, ok, out);
        }
        if (input.owner == null and self.active.contains(self.src.text(input.name))) {
            try call_arguments.positional(input, self.sink);
            return self.indirectCall(node, input, out);
        }
        const target = try self.callDeclaration(input, node.span);
        const call = target.call;
        const function = try self.specialize(target.declaration, call, node.span);
        const signature = self.syntaxFunction(function);
        var arguments: std.ArrayList(typed.NodeId) = .empty;
        for (call.arguments, signature.signature.parameters) |arg, parameter| {
            const argument = self.syntax.nodes.items[@backingInt(arg)];
            const value = self.resolved[@backingInt(arg)].?;
            try self.require(self.nodes.items[@backingInt(value)].ty, try self.functionType(function, parameter.ty), argument.span);
            try arguments.append(self.allocator, value);
        }
        out.ty = try self.functionType(function, signature.signature.return_type);
        out.data = .{ .call = .{ .function = function, .arguments = try arguments.toOwnedSlice(self.allocator) } };
        try (@import("call_evaluation.zig").Context{
            .storage = .{ .nodes = &self.nodes, .locals = &self.locals, .statements = &self.statements },
            .span = node.span,
            .call = call,
            .parameters = signature.signature.parameters,
        }).apply(self.allocator, &out.data.call);
    }
    fn byteValues(self: *Checker, bytes: []const u8, span: source.Span) Error![]const typed.NodeId {
        const values = try self.allocator.alloc(typed.NodeId, bytes.len);
        for (bytes, values) |byte, *value| {
            value.* = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = span, .ty = .u8, .data = .{ .integer = byte } });
        }
        return values;
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
        const operand_ty = self.nodes.items[@backingInt(operand)].ty;
        out.ty = if (u.op == .not) .bool else operand_ty;
        if (u.op == .neg and numeric_surface.isFloat(out.ty, self.catalog.records)) return self.numericBuilder(node.span).negate(operand);
        // A `float` operand is the binary64 value itself, so the float-in/float-out
        // `f64_*` operations answer a float instead of demanding a bit pattern.
        if (@import("float_intrinsics.zig").floatwise(u.op) and numeric_surface.isFloat(operand_ty, self.catalog.records)) {
            return self.numericBuilder(u.op_span).unary(std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, operand);
        }
        if (u.op == .neg) try self.requireInteger(out.ty, u.op_span) else try self.require(operand_ty, if (u.op == .not) .bool else .u64, u.op_span);
        out.data = .{ .unary = .{ .op = std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, .operand = operand, .op_span = u.op_span } };
        return out;
    }
    /// Build an enum-indexed table from a dict literal whose context already demands `[Kind]T`.
    fn checkTableLiteral(self: *Checker, node: ast.Node, entries: []const ast.NodeId, expected: typed.Type, out: *typed.Node) Error!void {
        const key = arrays.table(self.catalog, expected).?;
        const context: arrays.Context = .{ .src = self.src, .syntax = self.syntax, .catalog = self.catalog, .key = key };
        const named = try arrays.initializers(self.allocator, context, entries, self.sink);
        out.ty = expected;
        out.data = .{ .record = try self.fields(expected, named, true, node.span) };
    }
    fn checkDictionaryLiteral(self: *Checker, node: ast.Node, entries: []const ast.NodeId, out: *typed.Node) Error!void {
        const expected = self.expected_types.get(node.span);
        if (expected) |ty_value| if (arrays.table(self.catalog, ty_value) != null) return self.checkTableLiteral(node, entries, ty_value, out);
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
    /// A `b"..."` literal is always the managed bytes type; plain text keeps its array form.
    fn byteLiteralType(self: *Checker, node: ast.Node) Error!typed.Type {
        const spelling = self.src.text(node.span);
        if (spelling.len == 0 or spelling[0] != 'b') return self.ty(node.span);
        return collections.preludeType(&self.catalog, "bytes", node.span);
    }
    fn checkTextLiteral(self: *Checker, node: ast.Node, bytes: []const u8, out: *typed.Node) Error!void {
        out.ty = if (node.data == .text) try self.ty(node.span) else self.expected_types.get(node.span) orelse try self.byteLiteralType(node);
        if (out.ty.isAggregate() and self.catalog.records[out.ty.recordIndex()].collection.kind == .bytes) {
            out.data = .{ .array = try self.byteValues(bytes, node.span) };
            return;
        }
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
            const sequence = self.catalog.records[lt.recordIndex()].collection.kind;
            const concatenation = b.op == .add and (sequence == .string or sequence == .bytes);
            if (!concatenation and b.op != .eq and b.op != .ne) return self.sink.fail("E_TEXT_OPERATOR", b.op_span, "managed collections support equality and str/bytes support concatenation");
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
        const needle = try self.expressionWithTemporaries(membership.needle, temporaries);
        const container = try self.expressionWithTemporaries(membership.container, temporaries);
        const container_type = self.nodes.items[@backingInt(container)].ty;
        if (!container_type.isAggregate() or !self.catalog.records[container_type.recordIndex()].managed) return self.sink.fail("E_MEMBERSHIP", node.span, "membership requires a list, dictionary, or str");
        const schema = self.catalog.records[container_type.recordIndex()];
        var member = needle;
        const expected = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .dictionary => schema.collection.key.?,
            .string => container_type,
            .bytes => try self.byteMembership(node.span, &member, container_type),
        };
        try self.require(self.nodes.items[@backingInt(member)].ty, expected, node.span);
        const inputs = [_]typed.NodeId{ member, container };
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
    /// Byte membership accepts either a byte scalar, widened to int, or a whole subsequence.
    fn byteMembership(self: *Checker, span: source.Span, needle: *typed.NodeId, container_type: typed.Type) Error!typed.Type {
        const actual = self.nodes.items[@backingInt(needle.*)].ty;
        if (!actual.isInteger()) return container_type;
        if (actual != .i64) needle.* = try (collections.Builder(Checker){ .checker = self, .span = span }).node(.i64, .{ .cast = needle.* });
        return .i64;
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
            if (receiver.collection.kind == .bytes) {
                const b: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
                out.ty = .i64;
                out.data = .{ .cast = try b.node(receiver.shape.buffer.?, .{ .index = .{ .base = base, .index = index_value } }) };
                return;
            }
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
        if (self.lambdaIndex(node.span)) |lambda_index| {
            try self.checkLambdaValue(lambda_index, node, &out);
        } else if (minimum_literal) |parsed| {
            out.ty = parsed.ty;
            out.data = .{ .integer = parsed.value };
        } else switch (node.data) {
            .field_assignment => return self.checkFieldAssignment(node, temporaries),
            .index_assignment => return self.checkIndexAugmented(node, temporaries),
            .list_literal => |inputs| return self.checkListLiteral(node, inputs, temporaries),
            .format => |parts| return self.checkFormat(node, parts, temporaries),
            .comprehension => |each| return self.checkComprehension(node, each, temporaries),
            .list_operation => |op| return self.checkListAccess(node, .{ .base = op.base, .kind = op.kind, .inputs = op.arguments }, temporaries),
            .method_call => return self.checkCollectionMethod(node, temporaries),
            .slice => return self.checkCollectionSlice(node, temporaries),
            .buffer_operation => |operation| try self.checkBufferOperation(node, operation, &out),
            .file_operation => |operation| try self.checkFileMethod(node, operation, &out),
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
            .propagate => |operand| {
                const value = self.resolved[@backingInt(operand)].?;
                const input_ty = self.nodes.items[@backingInt(value)].ty;
                var element: typed.Type = undefined;
                if (typed.resultShape(input_ty, self.catalog.records)) |input| {
                    const output = typed.resultShape(self.return_type, self.catalog.records) orelse return self.sink.fail("E_TRY_RETURN", node.span, "try requires a function returning a declared result type");
                    try self.require(input.error_type, output.error_type, node.span);
                    element = input.ok_type;
                } else if (prelude.optionShape(input_ty, self.catalog.records)) |input| {
                    const output = prelude.optionShape(self.return_type, self.catalog.records) orelse return self.sink.fail("E_TRY_RETURN", node.span, "try requires a function returning an Option type");
                    try self.require(input.element, output.element, node.span);
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
                out.ty = try self.variantType(variant, node.span);
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
                out.ty = .i64;
                out.data = .{ .length = base };
            },
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
            .call => |call| try self.checkCall(node, call, &out),
            .unary => |u| return self.checkUnary(node, u),
            .binary => |b| try self.checkValueBinary(b, &out),
        }
        return out;
    }
    fn lambdaIndex(self: *Checker, span: source.Span) ?usize {
        for (self.syntax.lambdas, 0..) |lambda, index| {
            if (lambda.span.start == span.start and lambda.span.end == span.end) return index;
        }
        return null;
    }
    fn checkLambdaValue(self: *Checker, index: usize, node: ast.Node, out: *typed.Node) Error!void {
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
    fn consumedTemporaries(self: *Checker, node: ast.Node, out: typed.Node) Error!usize {
        if (node.data == .index and out.data == .block_value) return 2;
        if (node.data == .length and out.data == .block_value) return 1;
        if (node.data == .bytes or node.data == .text or node.data == .integer) return 0;
        // A list literal checks its own elements, so none of them reach the caller's stack;
        // a dict literal queues every key and value, whether it builds a dict or a table.
        if (node.data == .list_literal or node.data == .format or node.data == .comprehension) return 0;
        if (node.data == .dictionary_literal) return node.data.dictionary_literal.len;
        if (node.data == .binary) return 2;
        if (node.data == .call and try self.numericConversion(node.data.call) != null) return node.data.call.arguments.len;
        if (node.data == .call and try self.typeConversion(node.data.call) != null) return 1;
        return switch (out.data) {
            .function_value, .unit, .integer, .boolean, .local, .block_value => 0,
            .arena_escape, .cast, .wrap, .unwrap, .length, .field, .unary, .propagate, .external_read, .complete_resource, .restrict_resource => 1,
            .acquire_buffer => 1,
            .acquire_resource, .environment_get => 2,
            .index, .binary => 2,
            .replace => 3,
            .variant => |variant| if (variant.value != null) 1 else 0,
            .array => |values| values.len,
            .record => |initializers| initializers.len,
            .update => |update| update.fields.len + 1,
            .invoke => |call| call.arguments.len,
            .call => |call| call.arguments.len,
            .buffer_operation => |operation| operation.arguments.len,
            .resource_io => |io| if (io.value != null) 1 else 0,
            .print => |output| output.arguments.len + @intFromBool(output.separator != null) + @intFromBool(output.terminator != null),
            .file_access => |call| call.arguments.len,
            .file_method => |call| @intFromBool(call.argument != null),
        };
    }
    fn expressionWithTemporaries(self: *Checker, root: ast.NodeId, inherited: []const typed.Type) Error!typed.NodeId {
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
                try self.hintSortedArguments(parent.data.call);
                try work.append(self.allocator, .{ .id = parent.data.call.arguments[1] });
                continue;
            }
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
                if (try self.queueExpression(&work, task.id)) continue;
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
    fn needsLocalCleanup(self: *Checker, local_type: typed.Type) Error!bool {
        if (local_type.isFile()) return true;
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
        if ((kind == .append or kind == .extend) and arguments.len == 1) return self.requireArenaStore(slot, arguments[0]);
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
    /// A file `with` scope binds one open handle and closes it at every exit.
    fn statementWithFile(self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "with_scope"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const head = self.syntax.nodes.items[@backingInt(scope.resource.?)];
        if (head.data == .call) if (try self.fileAccessBuiltin(head.data.call)) |kind| {
            if (kind == .open) self.trapping_open = head.span;
        };
        defer self.trapping_open = null;
        const value = try self.expression(scope.resource.?);
        const value_type = self.nodes.items[@backingInt(value)].ty;
        if (!value_type.isFile()) {
            const guidance = if (typed.resultShape(value_type, self.catalog.records) != null)
                "`with` opens an arena or a file; `open` returns a Result, so propagate it with `open(...)?` or match it first"
            else
                "`with` opens `arena()` or a file handle; no other value can be used as a resource";
            return self.sink.fail(eWithResource, self.nodes.items[@backingInt(value)].span, guidance);
        }
        const declared = scope.name orelse return self.sink.fail(eWithResource, stmt.span, "a file `with` scope requires a binding, as in `with open(fs, path, \"rb\")? as f:`");
        const name = self.src.text(declared);
        if (try self.topLevel(declared) or self.active.contains(name)) return self.sink.fail(eShadowing, declared, "file name shadows an active name");
        for (self.arenas.items) |active| if (std.mem.eql(u8, active.name, name)) return self.sink.fail(eShadowing, declared, "file name shadows an enclosing arena scope");
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .declaration = declared, .ty = value_type, .mutable = false, .ownership = .{ .initialized = true }, .usage = .{ .reads = 1 } });
        try self.active.put(self.allocator, name, slot);
        defer _ = self.active.remove(name);
        const body = try self.statement(scope.body);
        flow.terminates = body.terminates;
        return .{ .with_scope = .{ .slot = slot, .resource = value, .body = body.id } };
    }
    fn statementWithScope(self: *Checker, stmt: ast.Statement, scope: @FieldType(@FieldType(ast.Statement, "data"), "with_scope"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        if (scope.resource != null) return self.statementWithFile(stmt, scope, flow);
        var name: []const u8 = "";
        if (scope.name) |declared| {
            name = self.src.text(declared);
            if (try self.topLevel(declared) or self.active.contains(name)) return self.sink.fail(eShadowing, declared, "arena name shadows an active name");
            for (self.arenas.items) |active| if (std.mem.eql(u8, active.name, name)) return self.sink.fail(eShadowing, declared, "arena name shadows an enclosing arena scope");
        }
        const watermark: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.arenas.append(self.allocator, .{ .name = name, .declaration = scope.name orelse stmt.span, .watermark = watermark });
        defer _ = self.arenas.pop();
        const body = try self.statement(scope.body);
        // A managed binding first assigned inside the arena lives in the released
        // region. Function scoping keeps its name visible after the block, so confine
        // it: reading it once the region is gone is E_ARENA_ESCAPE, not a dangling read.
        for (self.locals.items[@backingInt(watermark)..]) |*local| {
            if (try self.managedBearing(local.ty)) local.ownership.arena_confined = true;
        }
        flow.terminates = body.terminates;
        return .{ .with_scope = .{ .slot = watermark, .resource = null, .body = body.id } };
    }
    fn statementBlock(self: *Checker, stmt: ast.Statement, children: @FieldType(@FieldType(ast.Statement, "data"), "block"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const first_local = self.locals.items.len;
        // Plain (copyable and garbage-collected) locals are function-scoped and stay
        // visible after the block. A move-only resource carries a cleanup obligation
        // discharged at block exit, so it remains confined to the block.
        defer for (self.locals.items[first_local..]) |local| {
            if (typed.moveOnly(local.ty, self.catalog.records)) _ = self.active.remove(local.name);
        };
        var checked: std.ArrayList(typed.StatementId) = .empty;
        var looping = false;
        for (children) |child| {
            if (flow.terminates and !looping) return self.sink.fail("E_UNREACHABLE", self.syntax.statements.items[@backingInt(child)].span, "statement follows a structurally terminating statement");
            const result = try self.statement(child);
            flow.terminates = result.terminates;
            looping = result.looping;
            try checked.append(self.allocator, result.id);
        }
        flow.looping = looping;
        if (!flow.terminates) {
            try self.requireHandled(first_local, stmt.span);
            var owned: std.ArrayList(typed.LocalId) = .empty;
            for (self.locals.items[first_local..], first_local..) |local, index| {
                if (typed.moveOnly(local.ty, self.catalog.records)) try owned.append(self.allocator, @fromBackingInt(index));
            }
            flow.owned_cleanup = try owned.toOwnedSlice(self.allocator);
        }
        return .{ .block = try checked.toOwnedSlice(self.allocator) };
    }
    fn patternTag(self: *Checker, value_type: typed.Type, type_span: source.Span, name: source.Span) Error!usize {
        if (type_span.start != type_span.end) {
            const contextual = try variant_calls.contextual(self.src, self.catalog, type_span, value_type, self.sink);
            try self.require(contextual orelse try self.ty(type_span), value_type, type_span);
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
    /// Give every variant no earlier arm named the wildcard's body, discarding its payload.
    fn wildcardArms(
        self: *Checker,
        arms: *std.ArrayList(typed.MatchArm),
        shape: struct { seen: []?source.Span, variants: typed.Variants, name: source.Span },
        body: typed.StatementId,
    ) Error!void {
        var covered: usize = 0;
        for (shape.seen, shape.variants.cases, 0..) |named, variant, tag| {
            if (named != null) continue;
            if (variant.payload) |payload| if (self.requiresHandling(payload)) return self.sink.fail(
                eResultDiscard,
                shape.name,
                "`case _` would drop a result-bearing payload; give that variant its own arm",
            );
            shape.seen[tag] = shape.name;
            covered += 1;
            try arms.append(self.allocator, .{ .tag = tag, .slot = null, .body = body });
        }
        if (covered == 0) return self.sink.fail(eWildcardArm, shape.name, "every variant already has an arm, so `case _` is unreachable");
    }
    fn statementMatch(self: *Checker, stmt: ast.Statement, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const value = try self.expression(match.value);
        const value_type = self.nodes.items[@backingInt(value)].ty;
        const variants = try self.catalog.variants(value_type, stmt.span, self.sink);
        const seen = try self.allocator.alloc(?source.Span, variants.cases.len);
        @memset(seen, null);
        var arms: std.ArrayList(typed.MatchArm) = .empty;
        const before = try self.pendingState(self.locals.items.len);
        const init_before = try self.initSnapshot();
        var continuation: ?[]Pending = null;
        var continuation_init: ?[]bool = null;
        flow.terminates = true;
        for (match.arms, 0..) |arm, position| {
            self.restorePending(before);
            // Every arm starts from the same pre-match definite-assignment state.
            self.initRestore(init_before);
            if (wildcard(self.src, arm)) {
                if (position + 1 != match.arms.len) return self.sink.fail(eWildcardArm, arm.name, "`case _` must be the last arm of a match");
                const body = try self.statement(arm.body);
                if (!body.terminates) {
                    try self.mergeMatchInit(&continuation_init);
                    if (continuation) |state| try self.samePending(state, stmt.span, eResultPath) else continuation = try self.pendingState(before.len);
                }
                flow.terminates = flow.terminates and body.terminates;
                try self.wildcardArms(&arms, .{ .seen = seen, .variants = variants, .name = arm.name }, body.id);
                continue;
            }
            const tag = try self.patternTag(value_type, arm.ty, arm.name);
            if (seen[tag]) |previous| return self.sink.failRelated("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm", .{ .span = previous, .message = "previous arm" });
            seen[tag] = arm.name;
            const payload = variants.cases[tag].payload;
            if (arm.discard_payload and payload != null and self.requiresHandling(payload.?)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling");
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
            var payload_name: ?[]const u8 = null;
            defer if (payload_name) |name| {
                _ = self.active.remove(name);
            };
            var slot: ?typed.LocalId = null;
            if (arm.binding) |binding| {
                const name = self.src.text(binding);
                if (try self.topLevel(binding) or self.active.contains(name)) return self.sink.fail(eShadowing, binding, "payload binding shadows an active binding or top-level name");
                slot = @fromBackingInt(self.locals.items.len);
                try self.locals.append(self.allocator, .{
                    .ownership = .{
                        .initialized = true,
                        .transfer_available = self.transfers(payload.?),
                    },
                    .name = name,
                    .declaration = binding,
                    .ty = payload.?,
                    .mutable = false,
                });
                try self.active.put(self.allocator, name, slot.?);
                payload_name = name;
            }
            var body = try self.statement(arm.body);
            if (!body.terminates) {
                try self.mergeMatchInit(&continuation_init);
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
            try arms.append(self.allocator, .{ .tag = tag, .slot = slot, .body = body.id });
        }
        for (seen, variants.cases) |covered, variant| if (covered == null) {
            const message = try std.fmt.allocPrint(self.allocator, "match does not handle variant `{s}`; every variant requires an explicit arm", .{variant.name});
            return self.sink.failRelated("E_INCOMPLETE_MATCH", stmt.span, message, .{ .span = variant.declaration, .message = "unhandled variant declared here" });
        };
        if (continuation) |state| self.restorePending(state);
        if (continuation_init) |state| self.initRestore(state) else self.initRestore(init_before);
        return .{ .match = .{ .value = value, .arms = try arms.toOwnedSlice(self.allocator) } };
    }
    fn statementDiscard(self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "discard"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const value = try self.expression(expr);
        if (stmt.implicit_discard and self.nodes.items[@backingInt(value)].ty != .unit) return self.sink.fail("E_EXPLICIT_DISCARD_REQUIRED", stmt.span, "a standalone non-unit value requires `_ =` or result handling");
        return .{ .discard = value };
    }
    fn statementBranch(self: *Checker, stmt: ast.Statement, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const condition = try self.expression(branch.condition);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(branch.condition)].span);
        const before = try self.pendingState(self.locals.items.len);
        const init_before = try self.initSnapshot();
        const then_body = try self.statement(branch.then_body);
        const then_state = try self.pendingState(before.len);
        const init_then = try self.initSnapshot();
        self.restorePending(before);
        self.initRestore(init_before);
        const else_body = if (branch.else_body) |other| try self.statement(other) else null;
        const then_terminates = then_body.terminates;
        const else_terminates = if (else_body) |other| other.terminates else false;
        // Merge definite assignment: a name is bound after the `if` only when every
        // path that continues bound it. A path that diverges contributes nothing.
        if (then_terminates and !else_terminates) {
            // Continuation is the else path, already reflected in the flags.
        } else if (else_terminates and !then_terminates) {
            self.initRestore(init_then);
        } else if (!then_terminates and !else_terminates) {
            self.initIntersect(init_then);
        }
        if (!then_body.terminates) {
            if (else_body == null or !else_body.?.terminates) try self.samePending(then_state, stmt.span, eResultPath);
            self.restorePending(then_state);
        }
        flow.terminates = then_terminates and else_terminates;
        return .{ .branch = .{ .condition = condition, .then_body = then_body.id, .else_body = if (else_body) |other| other.id else null } };
    }
    fn statementLoop(self: *Checker, stmt: ast.Statement, loop: @FieldType(@FieldType(ast.Statement, "data"), "loop"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const before = try self.pendingState(self.locals.items.len);
        const condition = try self.expression(loop.condition);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(loop.condition)].span);
        try self.samePending(before, stmt.span, eResultLoop);
        const loop_id = self.loops.next;
        self.loops.next += 1;
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const init_before = try self.initSnapshot();
        const body = try self.statement(loop.body);
        // A loop may execute zero times, so assignments made only in its body
        // cannot make a pre-existing local definitely assigned after the loop.
        // Locals first introduced in the body remain resolvable by name but
        // report E_UNBOUND until a later assignment on this path initializes them.
        self.initRestore(init_before);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        // `while True:` without a break has no exit, so control never reaches what follows.
        const always = self.nodes.items[@backingInt(condition)].data == .boolean and self.nodes.items[@backingInt(condition)].data.boolean;
        flow.terminates = always and !self.loops.active.items[self.loops.active.items.len - 1].exited;
        flow.looping = flow.terminates;
        return .{ .loop = .{ .id = loop_id, .condition = condition, .body = body.id } };
    }
    fn statementForEach(self: *Checker, stmt: ast.Statement, each: @FieldType(@FieldType(ast.Statement, "data"), "for_each")) Error!@FieldType(typed.Statement, "data") {
        if (try self.preludeIteration(stmt, each)) |statements| return .{ .block = statements };
        const b: collections.Builder(Checker) = .{ .checker = self, .span = stmt.span };
        const iterable = try self.expression(each.iterable);
        const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
        if (!iterable_type.isAggregate() or !self.catalog.records[iterable_type.recordIndex()].managed) return self.sink.fail(eCollectionMethod, stmt.span, "iteration requires a list, str, or dictionary");
        const schema = self.catalog.records[iterable_type.recordIndex()];
        const element = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .string => iterable_type,
            .bytes => typed.Type.i64,
            .dictionary => schema.collection.key.?,
        };
        const owner = try b.local(iterable_type);
        const index = try b.local(.i64);
        const limit = try b.local(.i64);
        const value_slot = try b.local(element);
        const names = [_]?source.Span{ each.name, each.index_name };
        const slots = [_]typed.LocalId{ value_slot, index };
        for (names) |maybe_name| if (maybe_name) |name| {
            if (try self.topLevel(name) or self.active.contains(self.src.text(name))) return self.sink.fail(eShadowing, name, eIterationShadow);
        };
        if (each.index_name) |name| if (std.mem.eql(u8, self.src.text(name), self.src.text(each.name))) return self.sink.fail(eShadowing, name, "iteration names must differ");
        for (names, slots) |maybe_name, slot| if (maybe_name) |name| {
            self.locals.items[@backingInt(slot)].name = self.src.text(name);
            self.locals.items[@backingInt(slot)].declaration = name;
            self.locals.items[@backingInt(slot)].ownership.initialized = true;
            try self.active.put(self.allocator, self.src.text(name), slot);
        };
        defer for (names) |maybe_name| if (maybe_name) |name| {
            _ = self.active.remove(self.src.text(name));
        };
        const before = try self.pendingState(self.locals.items.len);
        const loop_id = self.loops.next;
        self.loops.next += 1;
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const init_before = try self.initSnapshot();
        const body = try self.statement(each.body);
        self.initRestore(init_before);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        const i = try b.read(index);
        const iteration_check = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
        const iteration = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            iteration_check,
            try b.stmt(.{ .initialize = .{ .slot = value_slot, .value = try self.iterationValue(b, owner, schema.collection.kind, i) } }),
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
    /// `for x in reversed(xs):` and `for a, b in zip(xs, ys):` walk their sources
    /// directly, so no intermediate list is materialised.
    fn preludeIteration(self: *Checker, stmt: ast.Statement, each: @FieldType(@FieldType(ast.Statement, "data"), "for_each")) Error!?[]const typed.StatementId {
        const node = self.syntax.nodes.items[@backingInt(each.iterable)];
        if (node.data != .call) return null;
        const call = node.data.call;
        if (!std.mem.eql(u8, self.src.text(call.name), "reversed") and !std.mem.eql(u8, self.src.text(call.name), "zip")) return null;
        if (!try self.preludeName(call)) return null;
        try call_arguments.positional(call, self.sink);
        const paired = std.mem.eql(u8, self.src.text(call.name), "zip");
        if (call.arguments.len != (if (paired) @as(usize, 2) else 1)) return self.sink.fail("E_ARITY", node.span, "reversed takes one iterable and zip takes two");
        if (paired != (each.index_name != null)) return self.sink.fail(eCollectionMethod, stmt.span, "zip binds two iteration names and reversed binds one");
        for (call.arguments) |id| try self.hintEmptyPreludeList(id, .i64);
        const sources = try self.allocator.alloc(typed.NodeId, call.arguments.len);
        for (call.arguments, sources) |id, *slot| slot.* = try self.expression(id);
        const builtins: prelude_builtins.Prelude(Checker) = .{ .checker = self };
        const left_type = self.nodes.items[@backingInt(sources[0])].ty;
        const zip = if (paired) try builtins.reserveZip(stmt.span, left_type, self.nodes.items[@backingInt(sources[1])].ty) else null;
        const walk = if (zip) |pair| pair.left else try builtins.reserveWalk(stmt.span, left_type);
        const names = [_]?source.Span{ each.index_name, each.name };
        const slots = [_]typed.LocalId{ walk.slot, if (zip) |pair| pair.right.slot else walk.slot };
        for (names, slots) |maybe_name, slot| if (maybe_name) |name| {
            if (try self.topLevel(name) or self.active.contains(self.src.text(name))) return self.sink.fail(eShadowing, name, eIterationShadow);
            self.locals.items[@backingInt(slot)].name = self.src.text(name);
            self.locals.items[@backingInt(slot)].declaration = name;
            // `reversed`/`zip` bind their names before the body checks, exactly like
            // the ordinary for-each path; function-scoped locals need the binding
            // marked initialized or a body read is refused as use-before-assignment.
            self.locals.items[@backingInt(slot)].ownership.initialized = true;
            try self.active.put(self.allocator, self.src.text(name), slot);
        };
        defer for (names) |maybe_name| if (maybe_name) |name| {
            _ = self.active.remove(self.src.text(name));
        };
        const before = try self.pendingState(self.locals.items.len);
        try self.loops.active.append(self.allocator, .{ .id = walk.loop, .before = before, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const init_before = try self.initSnapshot();
        const body = try self.statement(each.body);
        self.initRestore(init_before);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        if (zip) |pair| {
            const statements = try builtins.zipStatements(.{ .span = stmt.span, .left = sources[0], .right = sources[1], .zip = pair, .body = body.id });
            return statements;
        }
        const statements = try builtins.walkStatements(.{ .span = stmt.span, .input = sources[0], .walk = walk, .descending = true, .body = body.id });
        return statements;
    }
    fn iterationValue(self: *Checker, b: collections.Builder(Checker), owner: typed.LocalId, kind: ManagedKind, index: typed.NodeId) Error!typed.NodeId {
        _ = self;
        const read = try b.operation(owner, if (kind == .dictionary) .key_at else .read, &.{index});
        return if (kind == .bytes) b.node(.i64, .{ .cast = read }) else read;
    }
    fn statementForRange(self: *Checker, stmt: ast.Statement, range: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!@FieldType(typed.Statement, "data") {
        const name = self.src.text(range.name);
        if (try self.topLevel(range.name) or self.active.contains(name)) return self.sink.fail(eShadowing, range.name, "iteration binding shadows an active declaration");
        const zero_start = self.syntax.nodes.items[@backingInt(range.start)].data == .unit;
        const start = if (zero_start) try (collections.Builder(Checker){ .checker = self, .span = range.name }).integer(0) else try self.expression(range.start);
        const end = try self.expression(range.end);
        const element = self.nodes.items[@backingInt(start)].ty;
        try self.requireInteger(element, range.name);
        try self.require(self.nodes.items[@backingInt(end)].ty, element, self.syntax.nodes.items[@backingInt(range.end)].span);
        const index: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .declaration = range.name, .ty = element, .mutable = false, .ownership = .{ .initialized = true }, .usage = .{ .reads = 1 } });
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
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const init_before = try self.initSnapshot();
        const body = try self.statement(range.body);
        self.initRestore(init_before);
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
        for (self.locals.items[loop.before.len..], loop.before.len..) |local, index| {
            if (typed.moveOnly(local.ty, self.catalog.records)) try owned.append(self.allocator, @fromBackingInt(index));
        }
        if (!continuing) self.loops.active.items[self.loops.active.items.len - 1].exited = true;
        flow.terminates = true;
        flow.owned_cleanup = try owned.toOwnedSlice(self.allocator);
        var arenas: std.ArrayList(typed.LocalId) = .empty;
        var open = self.arenas.items.len;
        while (open > loop.arenas) {
            open -= 1;
            try arenas.append(self.allocator, self.arenas.items[open].watermark);
        }
        return .{ .loop_exit = .{
            .target = loop.id,
            .continuing = continuing,
            .arenas = try arenas.toOwnedSlice(self.allocator),
        } };
    }
    fn unitFallthrough(self: *Checker, body: CheckedStatement, span: source.Span) Error!CheckedStatement {
        try self.requireHandled(0, span);
        const value: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = span, .ty = .unit, .data = .unit });
        const ret: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = .{ .ret = value } });
        const children = try self.allocator.dupe(typed.StatementId, &.{ body.id, ret });
        const block: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = span, .terminates = true, .data = .{ .block = children } });
        return .{ .id = block, .terminates = true };
    }
    fn statementRet(self: *Checker, stmt: ast.Statement, expr: @FieldType(@FieldType(ast.Statement, "data"), "ret"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const value = try self.expressionExpected(expr, self.return_type);
        try self.require(self.nodes.items[@backingInt(value)].ty, self.return_type, stmt.span);
        try self.requireArenaReturn(value, stmt.span);
        try self.requireHandled(0, stmt.span);
        flow.terminates = true;
        return .{ .ret = value };
    }
    /// `assert` traps instead of returning, so it needs no result type and no effect.
    fn statementAssert(self: *Checker, claim: ast.Assertion) Error!@FieldType(typed.Statement, "data") {
        const condition = try self.expressionExpected(claim.condition, .bool);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(claim.condition)].span);
        return .{ .assertion = .{ .condition = condition, .message = claim.message } };
    }
    fn statementBinding(self: *Checker, _: ast.Statement, b: @FieldType(@FieldType(ast.Statement, "data"), "binding"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const name = self.src.text(b.name);
        if (try self.topLevel(b.name) or self.active.contains(name))
            return self.sink.fail(eShadowing, b.name, "binding shadows an active local or top-level function");
        for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, name)) return self.sink.fail(eShadowing, b.name, "binding shadows an active arena name");
        const value = if (b.annotation) |annotation| try self.expressionExpected(b.value, try self.ty(annotation)) else try self.expression(b.value);
        const value_type = self.nodes.items[@backingInt(value)].ty;
        if (b.annotation) |annotation| try self.require(value_type, try self.ty(annotation), annotation);
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{
                .initialized = true,
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
        const unbound = !self.active.contains(self.src.text(a.name));
        if (a.op == .set and unbound)
            return self.statementBinding(stmt, .{ .name = a.name, .mutable = true, .annotation = null, .value = a.value }, flow);
        const slot = try self.resolve(a.name);
        if (!self.locals.items[@backingInt(slot)].mutable)
            return self.sink.fail(eImmutable, a.name, "this binding cannot be assigned");
        var value = try self.expressionExpected(a.value, self.locals.items[@backingInt(slot)].ty);
        if (a.op != .set) {
            try self.requireReadable(slot, a.name);
            const target_type = self.locals.items[@backingInt(slot)].ty;
            try self.require(self.nodes.items[@backingInt(value)].ty, target_type, a.op_span);
            // `values += other` is Python's in-place extend, not a fresh list.
            if (a.op == .add and target_type.isAggregate() and self.catalog.records[target_type.recordIndex()].managed and self.catalog.records[target_type.recordIndex()].collection.kind == .list) {
                const b: collections.Builder(Checker) = .{ .checker = self, .span = a.op_span };
                const arguments = try self.allocator.alloc(typed.NodeId, 1);
                arguments[0] = value;
                try self.requireArenaOperation(slot, .extend, arguments);
                self.locals.items[@backingInt(slot)].usage.reads += 1;
                self.locals.items[@backingInt(slot)].usage.writes += 1;
                return .{ .block = try self.allocator.dupe(typed.StatementId, &.{try b.stmt(.{ .discard = try b.operation(slot, .extend, arguments) })}) };
            }
            self.locals.items[@backingInt(slot)].usage.reads += 1;
            const read: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .ty = target_type, .span = a.name, .data = .{ .local = slot } });
            value = try self.augmented(a.op, read, value, a.op_span);
        }
        try self.require(self.nodes.items[@backingInt(value)].ty, self.locals.items[@backingInt(slot)].ty, stmt.span);
        try self.requireArenaAssignment(slot, value);
        if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
            if (self.pendingObligation(self.locals.items[@backingInt(slot)])) return self.sink.fail("E_RESULT_OVERWRITE", a.name, "assignment would overwrite an unhandled result-bearing value");
            self.locals.items[@backingInt(slot)].ownership.transfer_available = true;
            self.locals.items[@backingInt(slot)].ownership.transfer_span = null;
        }
        self.locals.items[@backingInt(slot)].usage.writes += 1;
        // A reassignment definitely binds the name on this path and re-homes it out
        // of any arena it was previously confined to.
        self.locals.items[@backingInt(slot)].ownership.initialized = true;
        self.locals.items[@backingInt(slot)].ownership.arena_confined = false;
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
            if (try self.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "parameter shadows a top-level function");
            const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
            const parameter_type = try self.ty(parameter.ty);
            if (parameter.default_value) |value| {
                const checked = try self.expressionExpected(value, parameter_type);
                try self.require(self.nodes.items[@backingInt(checked)].ty, parameter_type, parameter.ty);
            }
            try self.locals.append(
                allocator,
                .{
                    .name = name,
                    .declaration = parameter.name,
                    .ty = parameter_type,
                    .mutable = function.policy.host == null,
                    .ownership = .{
                        .initialized = true,
                        .transfer_available = self.transfers(parameter_type),
                    },
                },
            );
            try self.active.put(allocator, name, slot);
        }
    }
    fn statement(self: *Checker, statement_id: ast.StatementId) Error!CheckedStatement {
        const stmt = self.syntax.statements.items[@backingInt(statement_id)];
        var flow: StatementFlow = .{};
        const data: @FieldType(typed.Statement, "data") = switch (stmt.data) {
            .with_scope => |scope| try self.statementWithScope(stmt, scope, &flow),
            .block => |children| try self.statementBlock(stmt, children, &flow),
            .match => |match| try self.statementMatch(stmt, match, &flow),
            .discard => |expr| try self.statementDiscard(stmt, expr, &flow),
            .branch => |branch| try self.statementBranch(stmt, branch, &flow),
            .loop => |loop| try self.statementLoop(stmt, loop, &flow),
            .ret => |expr| try self.statementRet(stmt, expr, &flow),
            .loop_exit => |continuing| try self.statementLoopExit(stmt, continuing, &flow),
            .for_each => |each| try self.statementForEach(stmt, each),
            .for_range => |range| try self.statementForRange(stmt, range),
            .assertion => |claim| try self.statementAssert(claim),
            .binding => |b| try self.statementBinding(stmt, b, &flow),
            .assignment => |a| try self.statementAssignment(stmt, a, &flow),
        };
        const result: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = flow.terminates, .owned_cleanup = flow.owned_cleanup, .data = data });
        return .{ .id = result, .terminates = flow.terminates, .looping = flow.looping };
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
/// Return the index of the first capability parameter after an optional argv list.
fn entryParameterStart(parameters: []const ast.Parameter, checker: *Checker, sink: *diagnostic.Sink) Error!usize {
    if (parameters.len == 0) return 0;
    const first_ty = try checker.ty(parameters[0].ty);
    if (entry_adapter.argvElement(first_ty, checker.catalog.records) != null) return 1;
    if (first_ty.capabilityIndex() != null) return 0;
    return sink.fail("E_MAIN", parameters[0].ty, "entry parameters must be `args: list[str]` followed by capabilities");
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
    const lambda_types = try allocator.alloc(?typed.Type, program.lambdas.len);
    @memset(lambda_types, null);
    const lambda_captures = try allocator.alloc(?[]const LambdaCapture, program.lambdas.len);
    @memset(lambda_captures, null);
    var checker: Checker = .{
        .allocator = allocator,
        .src = src,
        .syntax = program,
        .sink = sink,
        .resolved = resolved,
        .catalog = catalog,
        .ordinary_ids = ordinary_ids,
        .lambda_types = lambda_types,
        .lambda_captures = lambda_captures,
    };
    defer allocator.free(checker.managed_types);
    for (program.functions, 0..) |function, i| {
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
    checker.lambda_start = checker.instance_keys.items.len;
    for (program.lambdas) |_| try checker.instance_keys.append(allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{} });
    const main_name = if (module_names) |names| try std.fmt.allocPrint(allocator, "{s}::main", .{names.index.project.modules.items[0].name}) else "main";
    checker.ordinary_count = checker.instance_keys.items.len;
    const main_declaration = checker.functions.get(main_name) orelse {
        if (failed) return error.SourceError;
        return sink.fail("E_MAIN", .{ .start = 0, .end = 0 }, "the program requires an entry point: def main() -> int");
    };
    const entry = program.functions[@backingInt(main_declaration)];
    const main = ordinary_ids[@backingInt(main_declaration)] orelse return sink.fail("E_MAIN", entry.name, "main cannot have type parameters");
    if (entry.policy.host != null or entry.policy.constant) return sink.fail("E_MAIN", entry.name, "main must have a guest function body");
    // An entry point may take `args: list[str]` first, followed by at most one
    // capability of each kind. The list is input data, never authority.
    var entry_capabilities: u8 = 0;
    const first_capability = try entryParameterStart(entry.signature.parameters, &checker, sink);
    for (entry.signature.parameters[first_capability..]) |parameter| {
        const index = (try checker.ty(parameter.ty)).capabilityIndex() orelse return sink.fail("E_MAIN", parameter.ty, "entry parameters must be `args: list[str]` followed by capabilities");
        const bit = @as(u8, 1) << index;
        if (entry_capabilities & bit != 0) return sink.fail("E_MAIN", parameter.name, "entry requests at most one value parameter of each capability kind");
        entry_capabilities |= bit;
    }
    if (!entry_adapter.supported(try checker.ty(entry.signature.return_type), checker.catalog.records)) return sink.fail("E_TYPE", entry.signature.return_type, "main must return int, None, Result<None/int,int>, or Result[int,str]");
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
    try entry_adapter.adapt(allocator, &checked);
    try @import("effects.zig").check(allocator, checked, sink);
    try @import("domain_codecs.zig").check(allocator, src, program.types.domains, checker.catalog, .{ .items = functions, .names = executable_names }, sink);
    try warnBindings(allocator, functions, sink);
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    if (session) |*queries| try queries.remember(checked);
    return checked;
}

// This initial conversion form is declarative. Restricting its body avoids
// pretending arbitrary control/data flow proves source-field accounting.
fn conversionBody(self: *Checker, function: ast.Function) Error!void {
    const src = self.src;
    const program = self.syntax;
    const sink = self.sink;
    const statements = program.statements.items[@backingInt(function.body)].data.block;
    for (statements) |id| {
        const stmt = program.statements.items[@backingInt(id)];
        switch (stmt.data) {
            .ret => |value| {
                if (!try constructsRecord(self, program.nodes.items[@backingInt(value)]))
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

/// Accept both record construction spellings: legacy `new T { a: 1 }` and Python `T(a=1)`.
/// Both check with complete field accounting, so the conversion contract is unchanged.
fn constructsRecord(self: *Checker, node: ast.Node) Error!bool {
    if (node.data == .record) return true;
    if (node.data != .call) return false;
    const lowered = try @import("record_calls.zig").lower(self.allocator, self.src, self.catalog, node.data.call, self.sink);
    return lowered != null;
}

const functionName = @import("function_identity.zig").localName;

fn checkHostType(allocator: std.mem.Allocator, catalog: []const typed.Record, ty: typed.Type, span: source.Span, sink: *diagnostic.Sink) Error!void {
    @import("data_type.zig").check(allocator, catalog, ty, true) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return sink.fail("E_HOST_SIGNATURE", span, "host signatures require ordinary data without capabilities or runtime-owned storage"),
    };
}

fn warnBindings(allocator: std.mem.Allocator, functions: []const typed.Function, sink: *diagnostic.Sink) Error!void {
    for (functions) |function| {
        if (function.policy.host != null) continue;
        for (function.scope.locals) |local| {
            if (local.usage.temporary or local.usage.reads != 0) continue;
            try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_BINDING",
                .span = local.declaration,
                .message = "binding is never read; use it or remove it, preserving initializer effects with `_ =` when needed",
            });
        }
    }
}
