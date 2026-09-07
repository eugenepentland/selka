//! Scope and type checking use resolved binding identities, including advisory use counts.
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
const LoopScope = struct { id: usize, before: []const Pending, references: usize, arena_depth: usize };
const Pending = struct { available: bool, fields: field_moves.State, transfer_span: ?source.Span };
const Work = struct { id: ast.NodeId, emit: bool = false, checkpoint: bool = false, verify: ?[]const Pending = null };
const CheckedStatement = struct { id: typed.StatementId, terminates: bool };

const StatementFlow = struct {
    terminates: bool = false,
    cleanup: []const typed.ReferenceId = &.{},
    owned_cleanup: []const typed.LocalId = &.{},
};

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
    functions: std.StringHashMapUnmanaged(instances.DeclarationId) = .empty,
    resolved_nodes: std.ArrayList(usize) = .empty,
    instance_keys: std.ArrayList(instances.Key) = .empty,
    generic_registry: instances.Registry = .{},
    ordinary_ids: []?typed.FunctionId,
    ordinary_count: usize = 0,
    current_function: ?typed.FunctionId = null,
    loops: struct { active: std.ArrayList(LoopScope) = .empty, next: usize = 0 } = .{},
    return_type: typed.Type = .i64,
    arena_depth: usize = 0,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,
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
        const constant_context: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        const constant = if (function.policy.constant) try constant_context.evaluate(@backingInt(self.instance_keys.items[i].declaration)) else null;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.locals = .empty;
        self.references = .empty;
        self.active_refs.clearRetainingCapacity();
        self.active.clearRetainingCapacity();
        self.owner = if (function.policy.owner) |owner| try self.ty(owner) else null;
        self.return_type = try self.ty(function.signature.return_type);
        self.return_reference = try self.returnContract(@fromBackingInt(i));
        try self.bindParameters(function);
        if (function.policy.host != null) {
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
        if (function.policy.host == null and !body.terminates) return sink.fail(
            "E_MISSING_RETURN",
            function.name,
            "function may fall through without returning its declared type; loops are conservatively treated as falling through, even while true",
        );
        return .{
            .policy = .{
                .host = function.policy.host,
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
        if (call.type_arguments.len != function.signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (self.ordinary_ids[@backingInt(declaration)]) |id| return id;
        const required = try @import("generic_requirements.zig").resolve(self.allocator, self.src, function.signature.type_parameters, self.sink);
        const arguments = try self.allocator.alloc(typed.Type, required.len);
        const lengths = try self.allocator.alloc(?usize, required.len);
        @memset(lengths, null);
        for (call.type_arguments, required, arguments, 0..) |at, parameter, *argument, argument_index| {
            if (parameter.constant_length) {
                lengths[argument_index] = try self.lengthArgument(at);
                argument.* = .u64;
                continue;
            }
            argument.* = try self.ty(at);
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
    fn callTarget(self: *Checker, input: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
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
        if (signature.signature.parameters.len != call.arguments.len) return self.sink.fail("E_ARITY", span, "argument count does not match function parameters");
        return self.specialize(function, call, span);
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
            "E_BORROW_CONFLICT",
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
    const Literal = @import("integer_literal.zig").Literal;
    fn literal(self: *Checker, span: source.Span, allow_minimum: bool) Error!Literal {
        return @import("integer_literal.zig").parse(self.src, span, allow_minimum, self.sink);
    }
    fn minimum(self: *Checker, node: ast.Node) Error!?Literal {
        if (node.data != .unary or node.data.unary.op != .neg) return null;
        const child = self.syntax.nodes.items[@backingInt(node.data.unary.operand)];
        if (child.data != .integer) return null;
        const parsed = try self.literal(child.data.integer, true);
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
    fn queueExpression(self: *Checker, work: *std.ArrayList(Work), id: ast.NodeId, allow_reference: bool) Error!bool {
        const node = self.syntax.nodes.items[@backingInt(id)];
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
                try work.append(self.allocator, .{ .id = id, .emit = true });
                var i = operation.arguments.len;
                while (i > 0) {
                    i -= 1;
                    try work.append(self.allocator, .{ .id = operation.arguments[i] });
                }
                return true;
            },
            .variant => |variant| {
                if (variant.value) |value| {
                    try work.append(self.allocator, .{ .id = id, .emit = true });
                    try work.append(self.allocator, .{ .id = value });
                    return true;
                }
            },
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
                try work.append(self.allocator, .{ .id = acquire.allocator });
                return true;
            },
            .reset_arena, .cast, .wrap => |cast| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = cast.value });
                return true;
            },
            .record => |record| {
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
                if (call.owner == null and (self.active.contains(self.src.text(call.name)) or source_json.operation(self.src.text(call.name)) != null)) {
                    var index = call.arguments.len;
                    while (index > 0) {
                        index -= 1;
                        try work.append(self.allocator, .{ .id = call.arguments[index] });
                    }
                    return true;
                }
                const target = try self.callTarget(call, node.span);
                const signature = self.syntaxFunction(target);
                if (signature.signature.return_reference != null and !(allow_reference)) return self.sink.fail(eReferenceResult, node.span, "reference-returning calls require a borrow scope");
                var i = call.arguments.len;
                while (i > 0) {
                    i -= 1;
                    if (signature.signature.parameters[i].reference == null or self.syntax.nodes.items[@backingInt(call.arguments[i])].data == .bytes) try work.append(self.allocator, .{ .id = call.arguments[i] });
                }
                return true;
            },
            .unary => |u| {
                try work.append(self.allocator, .{ .id = id, .emit = true });
                try work.append(self.allocator, .{ .id = u.operand });
                return true;
            },
            .binary => |b| {
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
    fn checkBufferOperation(self: *Checker, _: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "buffer_operation"), out: *typed.Node) Error!void {
        const access = try self.operationOwner(operation.owner, operation.kind.mutates());
        const owner = access.owner;
        const local = &self.locals.items[@backingInt(owner)];
        if (!local.ty.isAggregate() or self.catalog.records[local.ty.recordIndex()].shape.buffer == null) return self.sink.fail("E_BUFFER_TYPE", operation.owner, "operation requires an owned buffer binding");
        if (!local.ownership.transfer_available) return self.sink.failTransfer(eOwnedConsumed, operation.owner, local.declaration, local.ownership.transfer_span);
        if (operation.kind.mutates() and access.reference == null and !local.mutable) return self.sink.fail(eImmutable, operation.owner, "buffer mutation requires a let mut binding");
        local.usage.reads += 1;
        if (operation.kind.mutates()) local.usage.writes += 1;
        const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments, 0..) |input, *argument, argument_index| {
            argument.* = self.resolved[@backingInt(input)].?;
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            const span = self.syntax.nodes.items[@backingInt(input)].span;
            const writes_element = argument_index == 1 and (operation.kind == .write or operation.kind == .resize);
            if (operation.kind == .reserve and argument_index == 0) {
                try self.require(actual, .allocator, span);
            } else if (operation.kind == .append or writes_element) {
                try self.require(actual, element, span);
            } else {
                try self.requireInteger(actual, span);
            }
        }
        if (operation.result) |result_type| {
            out.ty = try self.ty(result_type);
            const shape = typed.resultShape(out.ty, self.catalog.records) orelse return self.sink.fail(eBufferResult, result_type, "buffer mutation requires a result with bool success and i64 error payloads");
            if (shape.ok_type != .bool or shape.error_type != .i64) return self.sink.fail(eBufferResult, result_type, "buffer mutation requires a result with bool success and i64 error payloads");
        } else out.ty = if (operation.kind == .read) element else .u64;
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
        out.ty = try self.ty(acquire.ty);
        const is_pool = node.data == .acquire_pool;
        const code: []const u8 = if (is_pool) ePoolResult else eBufferResult;
        const message: []const u8 = if (is_pool) "pool acquisition requires a pool success and i64 error result" else "buffer acquisition requires a buffer success and i64 error result";
        _ = typed.acquisitionShape(out.ty, self.catalog.records, is_pool) orelse return self.sink.fail(code, acquire.ty, message);
        const capacity = self.resolved[@backingInt(acquire.value)].?;
        try self.requireInteger(self.nodes.items[@backingInt(capacity)].ty, node.span);
        const authority = self.resolved[@backingInt(acquire.allocator)].?;
        try self.require(self.nodes.items[@backingInt(authority)].ty, .allocator, self.syntax.nodes.items[@backingInt(acquire.allocator)].span);
        out.data = if (is_pool) .{ .acquire_pool = .{ .allocator = authority, .capacity = capacity } } else .{ .acquire_buffer = .{ .allocator = authority, .capacity = capacity } };
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
        for (function.signature.parameters, parameters) |input, *parameter| {
            if (input.reference != null) return self.sink.fail(callback_type_code, name, "callback values currently accept value parameters only");
            parameter.* = try self.catalog.resolve(self.src, input.ty, self.sink);
        }
        const result = try self.catalog.resolve(self.src, function.signature.return_type, self.sink);
        out.ty = try @import("callables.zig").intern(self.allocator, &self.catalog, .{ .parameters = parameters, .return_type = result, .effects = bound.allowed }, name, self.sink);
        out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
        return true;
    }
    fn indirectCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        const slot = try self.resolve(call.name);
        const contract = @import("callables.zig").signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) orelse return self.sink.fail(callback_type_code, call.name, "called local is not a function value");
        if (call.type_arguments.len != 0 or call.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", call.name, "callback argument count must match its signature");
        try self.ownerAccess(slot, false, call.name);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const callee: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = call.name, .ty = self.locals.items[@backingInt(slot)].ty, .data = .{ .local = slot } });
        const arguments = try self.allocator.alloc(typed.NodeId, call.arguments.len);
        for (call.arguments, contract.parameters, arguments) |input, expected, *argument| {
            argument.* = self.resolved[@backingInt(input)].?;
            try self.require(self.nodes.items[@backingInt(argument.*)].ty, expected, node.span);
        }
        out.ty = contract.return_type;
        out.data = .{ .invoke = .{ .callee = callee, .arguments = arguments } };
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
    fn checkCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        if (call.owner == null and self.active.contains(self.src.text(call.name))) return self.indirectCall(node, call, out);
        if (call.owner == null) if (source_json.operation(self.src.text(call.name))) |decode| return self.checkJson(call, decode, out);
        const function = try self.callTarget(call, node.span);
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
                        "E_BORROW_CONFLICT",
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
    fn checkedExpression(self: *Checker, node: ast.Node, minimum_literal: ?Literal, temporaries: []const typed.Type) Error!typed.Node {
        var out: typed.Node = .{ .span = node.span, .ty = .i64, .data = undefined };
        if (minimum_literal) |parsed| {
            out.ty = parsed.ty;
            out.data = .{ .integer = parsed.value };
        } else switch (node.data) {
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
            .index => |access| {
                const base = self.resolved[@backingInt(access.base)].?;
                const index_value = self.resolved[@backingInt(access.index)].?;
                const schema = try self.catalog.array(self.nodes.items[@backingInt(base)].ty, node.span, self.sink);
                try self.requireIndex(schema, self.nodes.items[@backingInt(index_value)].ty, self.syntax.nodes.items[@backingInt(access.index)].span);
                if (self.requiresHandling(schema.element) and schema.length != 1) return self.sink.fail(eResultOperation, node.span, "indexing would drop other result-bearing elements; handle or transfer the entire array");
                out.ty = schema.element;
                out.data = .{ .index = .{ .base = base, .index = index_value } };
            },
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
                _ = try self.catalog.array(self.nodes.items[@backingInt(base)].ty, node.span, self.sink);
                if (self.requiresHandling(self.nodes.items[@backingInt(base)].ty)) return self.sink.fail(eResultOperation, node.span, "length evaluation would drop result-bearing elements");
                out.ty = .u64;
                out.data = .{ .length = base };
            },
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
            .bytes => |bytes| {
                out.ty = try self.ty(node.span);
                out.data = .{ .array = try self.byteValues(bytes, node.span) };
            },
            .match_expression => |match| return self.matchExpression(node, match, temporaries),
            .integer => |token| {
                const parsed = try self.literal(token, false);
                out.ty = parsed.ty;
                out.data = .{ .integer = parsed.value };
            },
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
            .unary => |u| {
                const operand = self.resolved[@backingInt(u.operand)].?;
                out.ty = if (u.op == .not) .bool else self.nodes.items[@backingInt(operand)].ty;
                if (u.op == .neg) try self.requireInteger(out.ty, u.op_span) else try self.require(self.nodes.items[@backingInt(operand)].ty, if (u.op == .not) .bool else .u64, u.op_span);
                out.data = .{ .unary = .{ .op = std.meta.stringToEnum(typed.UnaryOp, @tagName(u.op)).?, .operand = operand, .op_span = u.op_span } };
            },
            .binary => |b| {
                const left = self.resolved[@backingInt(b.left)].?;
                const right = self.resolved[@backingInt(b.right)].?;
                const lt = self.nodes.items[@backingInt(left)].ty;
                const rt = self.nodes.items[@backingInt(right)].ty;
                try self.require(rt, lt, b.op_span);
                switch (b.op) {
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
            },
        }
        return out;
    }
    fn expressionMode(self: *Checker, root: ast.NodeId, reference_result: bool) Error!typed.NodeId {
        return self.expressionWithTemporaries(root, reference_result, &.{});
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
            if (self.resolved[index] != null) continue;
            const node = self.syntax.nodes.items[index];
            const minimum_literal = try self.minimum(node);
            if (!task.emit and minimum_literal == null) {
                if (try self.queueExpression(&work, task.id, reference_result and task.id == root)) continue;
            }
            const out = try self.checkedExpression(node, minimum_literal, temporaries.items);
            const consumed: usize = if (node.data == .bytes) 0 else switch (out.data) {
                .json_codec => 3,
                .function_value, .integer, .boolean, .local, .read_ref, .read_field, .take_field, .len_slice, .block_value => 0,
                .reset_arena, .cast, .wrap, .unwrap, .length, .field, .unary, .read_slice, .propagate, .external_read, .complete_resource, .restrict_resource => 1,
                .acquire_buffer, .acquire_pool, .acquire_resource, .environment_get => 2,
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
                if (typed.moveOnly(local.ty, self.catalog.records)) try owned.append(self.allocator, @fromBackingInt(index));
            }
            flow.owned_cleanup = try owned.toOwnedSlice(self.allocator);
        }
        return .{ .block = try checked.toOwnedSlice(self.allocator) };
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
            try self.require(try self.ty(arm.ty), value_type, arm.ty);
            const tag = try self.catalog.variant(value_type, self.src, arm.name, self.sink);
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
                if (slot) |payload_slot| if (typed.moveOnly(payload.?, self.catalog.records)) {
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
            try self.require(try self.ty(arm.ty), value_type, arm.ty);
            const tag = try self.catalog.variant(value_type, self.src, arm.name, self.sink);
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
            if (slot) |payload_slot| if (typed.moveOnly(payload.?, self.catalog.records)) {
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
        const owner_subslice = range != null and parent != null and !parent_slice;
        if (owner_subslice and source_type.isAggregate()) {
            if (self.catalog.records[source_type.recordIndex()].shape.buffer != null)
                return self.sink.fail("E_SLICE_TYPE", borrow.owner, "borrow buffer elements directly from the owner in a separate lexical scope");
        }
        const element = if (range != null and !parent_slice) try self.sliceElement(source_type, borrow.owner) else source_type;
        if (self.requiresHandling(element) or ((range != null or parent_slice) and self.transfers(element)))
            return self.sink.fail(eResultBorrow, borrow.owner, "result obligations and owned slice elements cannot be exposed through references");
        const id: typed.ReferenceId = @fromBackingInt(self.references.items.len);
        try self.references.append(self.allocator, .{ .mode = .{ .slice = range != null or parent_slice }, .name = name, .declaration = borrow.name, .owner = owner, .parent = parent, .ty = element, .mutable = borrow.mutable });
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
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .references = self.references.items.len, .arena_depth = self.arena_depth });
        defer _ = self.loops.active.pop();
        const body = try self.statement(loop.body);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        return .{ .loop = .{ .id = loop_id, .condition = condition, .body = body.id } };
    }
    fn statementForRange(self: *Checker, stmt: ast.Statement, range: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!@FieldType(typed.Statement, "data") {
        const name = self.src.text(range.name);
        if (try self.topLevel(range.name) or self.active.contains(name) or self.active_refs.contains(name)) return self.sink.fail(eShadowing, range.name, "iteration binding shadows an active declaration");
        const start = try self.expression(range.start);
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
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .references = self.references.items.len, .arena_depth = self.arena_depth });
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
            if (typed.moveOnly(local.ty, self.catalog.records)) try owned.append(self.allocator, @fromBackingInt(index));
            if (local.ty == .allocator and local.ownership.arena_depth > loop.arena_depth and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index)))
                try regions.append(self.allocator, @fromBackingInt(index));
        }
        for (self.references.items[loop.references..], loop.references..) |ref, index| {
            if (self.active_refs.get(ref.name) == @as(typed.ReferenceId, @fromBackingInt(index))) try refs.append(self.allocator, @fromBackingInt(index));
        }
        flow.terminates = true;
        flow.owned_cleanup = try owned.toOwnedSlice(self.allocator);
        flow.cleanup = try refs.toOwnedSlice(self.allocator);
        return .{ .loop_exit = .{ .target = loop.id, .continuing = continuing, .regions = try regions.toOwnedSlice(self.allocator) } };
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
            value = try self.expression(expr);
            try self.require(self.nodes.items[@backingInt(value.?)].ty, self.return_type, stmt.span);
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
        const value = try self.expression(b.value);
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
    fn statementAssignment(self: *Checker, stmt: ast.Statement, a: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), _: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        const slot = try self.resolve(a.name);
        try self.ownerAccess(slot, true, a.name);
        if (!self.locals.items[@backingInt(slot)].mutable)
            return self.sink.fail(eImmutable, a.name, "assignment requires a let mut binding");
        var value = try self.expression(a.value);
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
            if (parameter.reference != null and self.requiresHandling(parameter_type)) return sink.fail(eResultBorrow, parameter.ty, "result-bearing parameters must transfer their handling obligation by value");
            try self.locals.append(
                allocator,
                .{
                    .name = name,
                    .declaration = parameter.name,
                    .ty = parameter_type,
                    .mutable = false,
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
    if (try checker.ty(entry.signature.return_type) != .i64) return sink.fail("E_TYPE", entry.signature.return_type, "main must return i64");
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
    var executable_names: std.StringHashMapUnmanaged(typed.FunctionId) = .empty;
    for (functions) |function| try executable_names.put(allocator, function.name, function.id);
    const checked: typed.Program = .{
        .aliases = try checker.catalog.aliases(allocator, src, program, sink),
        .nodes = try checker.nodes.toOwnedSlice(allocator),
        .statements = try checker.statements.toOwnedSlice(allocator),
        .functions = functions,
        .main = main,
        .records = checker.catalog.records,
    };
    try @import("region_check.zig").check(allocator, checked, sink);
    try @import("effects.zig").check(allocator, checked, sink);
    try @import("domain_codecs.zig").check(allocator, src, program.types.domains, checker.catalog, .{ .items = functions, .names = executable_names }, sink);
    try warnBindings(allocator, functions, sink);
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

fn warnBindings(allocator: std.mem.Allocator, functions: []const typed.Function, sink: *diagnostic.Sink) Error!void {
    for (functions) |function| {
        if (function.policy.host != null) continue;
        for (function.scope.locals) |local| {
            if (local.usage.reads == 0) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_BINDING",
                .span = local.declaration,
                .message = "binding is never read; use it or remove it, preserving initializer effects with discard when needed",
            });
            if (local.mutable and local.usage.writes == 0 and !local.usage.mutable_borrow) try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNNECESSARY_MUT",
                .span = local.declaration,
                .message = "binding is never assigned after initialization; remove mut",
            });
        }
    }
}
