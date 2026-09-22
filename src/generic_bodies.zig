//! Symbolic template checking preserves types, ownership and effects without representative substitution.
const call_arguments = @import("call_arguments.zig");
const eResultDiscard = diagnostic.result_discard;
const std = @import("std");
const option_flow = @import("option_flow.zig");
const dictionary_views = @import("dictionary_views.zig");
const numeric_surface = @import("numeric_surface.zig");
const float_syntax = @import("float_syntax.zig");
const integer_literal = @import("integer_literal.zig");
const buffer_operations = @import("buffer_operations.zig");
const BufferKind = buffer_operations.Kind;
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const Error = diagnostic.Error;
const effects = @import("effects.zig");
const effect_set = @import("effect_set.zig");
const mutation = @import("mutation.zig");
const Names = @import("module_names.zig").Names;
const constraint_lookup = @import("constraint_lookup.zig");
const variant_calls = @import("variant_calls.zig");
const arrays = @import("array_literals.zig");
const truncating = @import("truncating_math.zig");
const eShadowing = diagnostic.shadowing;
const eResultOperation = diagnostic.result_operation;
const eResultPath = diagnostic.result_path;
const eTryReturn = "E_TRY_RETURN";
const eArgument = diagnostic.generic_argument;
const eListType = @import("collection_lower.zig").list_type_error;
const eUnsupported = "E_GENERIC_BODY_UNSUPPORTED";
const Catalog = @import("records.zig").Catalog;
const symbolic = @import("symbolic_types.zig");
const provider_shapes = @import("symbolic_providers.zig");
const generic_cache = @import("generic_cache.zig");
const Symbolic = symbolic.Value;
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
/// Reject a literal `dir()` path that could leave a scoped root, mirroring `scopedPath`.
fn scopedDirectoryPath(bytes: []const u8) bool {
    if (bytes.len == 0) return true;
    if (std.mem.indexOfAny(u8, bytes, "\\\x00") != null) return false;
    var parts = std.mem.splitScalar(u8, bytes, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}
const FunctionMap = std.StringHashMapUnmanaged(usize);

const Pending = struct { available: bool, transfer_span: ?source.Span };
const Local = struct {
    name: source.Span,
    ty: Symbolic,
    mutable: bool,
    transfer_span: ?source.Span = null,
    available: bool = true,
};
const Checker = struct {
    allocator: std.mem.Allocator,
    field_arena: std.heap.ArenaAllocator,
    src: source.Source,
    program: ast.Program,
    catalog: Catalog,
    cleanup_masks: []const effect_set.Mask,
    effect_masks: []effect_set.Mask,
    /// Per-function bitmask of parameter positions written by this body (M1 direct only).
    mutation_masks: []u16,
    /// Per-function write fact before parameter-origin resolution.
    mutation_write_masks: []bool,
    effect_calls: *std.ArrayList(effects.AbstractCall),
    function_index: usize,
    sink: *diagnostic.Sink,
    parameters: []const requirements.Parameter,
    requirement_aliases: []const requirements.SubjectAlias = &.{},
    result: Symbolic,
    expected_types: std.AutoHashMapUnmanaged(source.Span, Symbolic) = .empty,
    option_facts: option_flow.State = .{},
    functions: *const FunctionMap,
    pending: *std.ArrayList(usize),
    scheduled: []bool,
    owner: ?source.Span = null,
    module_names: ?*Names = null,
    locals: std.ArrayList(Local) = .empty,
    active: std.StringHashMapUnmanaged(usize) = .empty,
    depth: usize = 0,
    work: usize = 0,
    expression_depth: usize = 0,
    temporary_results: usize = 0,
    loop_pending: ?[]const Pending = null,
    fn topLevel(self: *Checker, span: source.Span) Error!bool {
        if (self.module_names) |names| return names.topLevel(span);
        const text = self.src.text(span);
        return self.functions.contains(text) or self.catalog.names.contains(text) or self.catalog.templates.names.contains(text);
    }
    fn checkFunction(self: *Checker, function: ast.Function) Error!void {
        const sink = self.sink;
        if (function.policy.conversion) return sink.fail(eUnsupported, function.name, "generic conversions still need abstract checking");
        for (self.parameters) |parameter| if (try self.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "type parameter shadows a top-level declaration or import");
        try self.validateStructural();
        self.result = try self.ty(function.signature.return_type);
        try self.seedCleanup(self.result);
        for (function.signature.parameters) |parameter| {
            const parameter_type = try self.ty(parameter.ty);
            if (parameter.default_value) |value| try self.compatible(try self.expressionExpected(value, parameter_type), parameter_type, parameter.ty);
            try self.bindMode(parameter.name, parameter_type, function.policy.host == null);
        }
        const implicit_unit = symbolic.same(self.result, .{ .concrete = .unit }, self.catalog);
        const terminates = try self.statement(function.body);
        if (!terminates and !implicit_unit) return sink.fail("E_MISSING_RETURN", function.name, "template may fall through without returning its declared type");
        if (!terminates) try self.requireHandled(0, function.name);
    }
    fn shapes(self: *Checker) @import("symbolic_shapes.zig").Context {
        return .{
            .arena = &self.field_arena,
            .catalog = self.catalog,
            .src = self.src,
            .sink = self.sink,
            .parameters = self.parameters,
            .contracts = .{ .cleanup = self.cleanup_masks },
            .work = &self.work,
        };
    }
    fn properties(self: *Checker, value: Symbolic) Error!symbolic.Properties {
        return self.shapes().properties(value, self.program.functions[self.function_index].name);
    }
    fn carriesRegion(self: *Checker, value: Symbolic) Error!bool {
        return (try self.properties(value)).region;
    }
    fn enter(self: *Checker, span: source.Span) Error!void {
        if (self.depth == 256 or self.work == 100000) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic body exceeds checking depth/work budget");
        self.depth += 1;
        self.work += 1;
    }
    fn ty(self: *Checker, span: source.Span) Error!Symbolic {
        for (self.program.types.expressions.callbacks) |callback| if (callback.span.start == span.start) {
            try self.enter(span);
            defer self.depth -= 1;
            const parameters = try self.field_arena.allocator().alloc(Symbolic, callback.parameters.len);
            for (callback.parameters, parameters) |input, *out| out.* = try self.ty(input);
            return self.callbackType(callback, parameters, try self.ty(callback.return_type));
        };
        if (self.catalog.templates.applications.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            var arguments: [16]Symbolic = undefined;
            const required = self.catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
            for (template.syntax.arguments, required, 0..) |argument, parameter, i| arguments[i] = if (parameter.constant_length) try self.lengthType(argument) else try self.ty(argument);
            return self.shapes().nominal(template.declaration, arguments[0..template.arguments.len]);
        }
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            const length: Symbolic = if (template.length_parameter) |at| try self.lengthType(at) else .{ .length = template.length };
            return self.arrayWithLength(length, try self.ty(template.syntax.element), span);
        }
        const text = self.src.text(span);
        switch (requirements.matchScope(self.requirement_aliases, self.src, span)) {
            .subject => |index| {
                if (index >= self.parameters.len) return error.InternalError;
                return .{ .parameter = index };
            },
            .foreign => {},
            .local => {
                for (self.parameters, 0..) |parameter, index| if (std.mem.eql(u8, text, self.src.text(parameter.name))) {
                    if (parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "const length parameters are values, not types");
                    return .{ .parameter = index };
                };
            },
        }
        return self.concreteType(span);
    }
    fn callbackType(self: *Checker, syntax: ast.CallbackType, parameters: []const Symbolic, result: Symbolic) Error!Symbolic {
        const signature = try self.field_arena.allocator().create(symbolic.Callback);
        signature.* = .{
            .parameters = parameters,
            .result = result,
            .effects = syntax.effect_bound.allowed,
            .mutates = syntax.mutates,
            .return_origin = .unknown,
        };
        return .{ .callback = signature };
    }
    fn lengthType(self: *Checker, span: source.Span) Error!Symbolic {
        for (self.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) continue;
            if (!parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "expected a const length argument, not a type parameter");
            return .{ .length_parameter = index };
        }
        return .{ .length = try @import("generic_lengths.zig").literal(self.src, span, self.sink) };
    }
    fn arrayWithLength(self: *Checker, length: Symbolic, element: Symbolic, span: source.Span) Error!Symbolic {
        if (length == .length) return self.arrayType(length.length, element);
        if (length != .length_parameter) return self.sink.fail(diagnostic.generic_length, span, "array requires a const length value");
        const shape = try self.field_arena.allocator().create(symbolic.Array);
        shape.* = .{ .length = 0, .length_parameter = length.length_parameter, .element = element };
        return .{ .array = shape };
    }
    fn arrayType(self: *Checker, length: usize, element: Symbolic) Error!Symbolic {
        const shape = try self.field_arena.allocator().create(symbolic.Array);
        shape.* = .{ .length = length, .element = element };
        return .{ .array = shape };
    }
    fn arrayShape(self: *Checker, value: Symbolic, span: source.Span) Error!symbolic.Array {
        return symbolic.array(value, self.catalog.records) orelse self.sink.fail("E_TYPE", span, "operation requires a fixed array value");
    }
    fn concreteType(self: *Checker, span: source.Span) Error!Symbolic {
        return .{ .concrete = try self.catalog.resolve(self.src, span, self.sink) };
    }
    fn moveOnly(self: *Checker, value: Symbolic) Error!bool {
        return (try self.properties(value)).move_only;
    }
    fn transfers(self: *Checker, value: Symbolic) Error!bool {
        const flags = try self.properties(value);
        return flags.move_only or flags.requires_handling;
    }
    fn seedCleanup(self: *Checker, value: Symbolic) Error!void {
        self.effect_masks[self.function_index] |= (try self.properties(value)).cleanup;
    }
    fn definiteHandling(self: *Checker, value: Symbolic, span: source.Span) Error!bool {
        try self.enter(span);
        defer self.depth -= 1;
        return switch (value) {
            .callback, .length, .length_parameter, .parameter => false,
            .concrete => |ty_value| typed.requiresHandling(ty_value, self.catalog.records),
            .array => |array| (array.length_parameter != null or array.length != 0) and try self.definiteHandling(array.element, span),
            .nominal => result: {
                const shape = try self.shapes().schema(value, span);
                if (shape.kind == .result) break :result true;
                for (shape.fields) |field| if (field.ty) |field_type| if (try self.definiteHandling(field_type, span)) break :result true;
                break :result false;
            },
        };
    }
    fn requiresHandling(self: *Checker, value: Symbolic) Error!bool {
        return (try self.properties(value)).requires_handling;
    }
    fn seedEffect(self: *Checker, effect: effect_set.Effect) void {
        self.effect_masks[self.function_index] |= effect_set.bit(effect);
    }
    /// Resolve the direct value-parameter index addressed by a source expression.
    fn parameterIndex(self: *Checker, id: ast.NodeId, depth: usize) ?u16 {
        if (depth == 256) return null;
        const node = self.program.nodes.items[@backingInt(id)];
        const parameter_count = self.program.functions[self.function_index].signature.parameters.len;
        return switch (node.data) {
            .name => |name| if (self.active.get(self.src.text(name))) |slot| if (slot < parameter_count) @intCast(slot) else null else null,
            .field => |field| self.parameterIndex(field.base, depth + 1),
            .index => |index| self.parameterIndex(index.base, depth + 1),
            else => null,
        };
    }
    /// Resolve the direct value-parameter index named by a binder span.
    fn parameterIndexAt(self: *Checker, span: source.Span) ?u16 {
        const slot = self.active.get(self.src.text(span)) orelse return null;
        const parameter_count = self.program.functions[self.function_index].signature.parameters.len;
        if (slot >= parameter_count) return null;
        return @intCast(slot);
    }
    /// Record one managed write and its direct enclosing input, if known.
    fn seedManagedWrite(self: *Checker, input: ?u16) void {
        self.mutation_write_masks[self.function_index] = true;
        if (input) |position| self.mutation_masks[self.function_index] |= @as(u16, 1) << @intCast(position);
    }
    /// Record a collection operation using the shared buffer classification.
    fn seedCollectionWrite(self: *Checker, kind: BufferKind, dictionary: bool, input: ?u16) void {
        const classification = mutation.buffer(kind, dictionary);
        if (classification.writes_receiver) self.seedManagedWrite(input);
    }
    fn pendingObligation(self: *Checker, binding: Local) Error!bool {
        return binding.available and try self.requiresHandling(binding.ty);
    }
    fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
        for (self.locals.items[first..]) |binding| {
            if ((try self.pendingObligation(binding)))
                return self.sink.failRelated("E_RESULT_UNHANDLED", span, "result-bearing binding leaves scope without handling or transfer", .{ .span = binding.name, .message = "unhandled result-bearing binding" });
        }
    }
    fn pendingState(self: *Checker, count: usize) Error![]Pending {
        const state = try self.allocator.alloc(Pending, count);
        for (self.locals.items[0..count], state) |binding, *pending| pending.* = .{ .available = binding.available, .transfer_span = binding.transfer_span };
        return state;
    }
    fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*binding, pending| {
            binding.available = pending.available;
            binding.transfer_span = pending.transfer_span;
        }
    }
    fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |binding, pending| {
            const owned = (try self.moveOnly(binding.ty)) and !(try self.requiresHandling(binding.ty));
            const mismatch_code = if (owned) (if (std.mem.eql(u8, code, diagnostic.result_loop)) "E_OWNED_LOOP" else "E_OWNED_PATH") else code;
            if (binding.available != pending.available) return self.sink.failRelated(
                mismatch_code,
                span,
                "result obligation must agree on every continuing path",
                .{ .span = binding.name, .message = "binding declared here" },
            );
        }
    }
    fn concreteValue(self: *Checker, value: Symbolic, span: source.Span) Error!typed.Type {
        return switch (value) {
            .concrete => |ty_value| ty_value,
            .callback, .length, .length_parameter, .parameter, .array, .nominal => self.sink.fail(eUnsupported, span, "structural operations require a concrete type; parameter shapes need declared constraints"),
        };
    }
    fn same(self: *Checker, actual: Symbolic, expected: Symbolic, span: source.Span) Error!void {
        if (!symbolic.same(actual, expected, self.catalog)) return self.sink.fail("E_GENERIC_TYPE", span, "types differ; distinct type parameters remain distinct even with identical requirements");
    }
    /// Value compatibility allows a callback implementation to promise fewer
    /// effects than its destination; structural parameter/result comparisons stay `same`.
    fn compatible(self: *Checker, actual: Symbolic, expected: Symbolic, span: source.Span) Error!void {
        if (symbolic.same(actual, expected, self.catalog)) return;
        if (symbolic.callbackAssignable(actual, expected, self.catalog)) return;
        return self.sink.fail("E_GENERIC_TYPE", span, "types differ; distinct type parameters remain distinct even with identical requirements");
    }
    fn supports(self: *Checker, ty_value: Symbolic, requirement: requirements.Requirement, span: source.Span) Error!void {
        const supported = symbolic.supports(ty_value, requirement, self.parameters, self.catalog);
        if (!supported) {
            const message = try std.fmt.allocPrint(self.sink.allocator, "operation requires declared {s} support", .{@tagName(requirement)});
            return self.sink.fail("E_GENERIC_OPERATION", span, message);
        }
    }
    fn local(self: *Checker, span: source.Span) Error!*Local {
        const index = self.active.get(self.src.text(span)) orelse return self.sink.fail("E_UNKNOWN_NAME", span, "name is not defined in this template scope");
        return &self.locals.items[index];
    }
    fn namedValue(self: *Checker, span: source.Span) Error!Symbolic {
        for (self.parameters) |parameter| {
            if (parameter.constant_length and std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) return .{ .concrete = .u64 };
        }
        if (!self.active.contains(self.src.text(span))) {
            const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.program, .names = self.module_names, .sink = self.sink, .catalog = self.catalog };
            if (try constants.lookup(span)) |index| {
                if (try constants.literalType(index)) |ty_value| {
                    self.seedEffect(.managed_allocation);
                    return .{ .concrete = ty_value };
                }
                return .{ .concrete = (try constants.evaluate(index)).typeOf() };
            }
        }
        const binding = try self.local(span);
        if ((try self.transfers(binding.ty))) {
            if (!binding.available) return self.sink.failTransfer(if ((try self.moveOnly(binding.ty))) diagnostic.owned_consumed else "E_RESULT_CONSUMED", span, binding.name, binding.transfer_span);
            binding.available = false;
            binding.transfer_span = span;
        }
        if (self.option_facts.has(self.active.get(self.src.text(span)).?)) {
            if (self.expected_types.get(span)) |expected| if (symbolic.same(expected, binding.ty, self.catalog)) return binding.ty;
            return self.optionElement(binding.ty, span);
        }
        return binding.ty;
    }
    fn endScope(self: *Checker, before: usize) void {
        self.option_facts.endScope(before);
        for (self.locals.items[before..]) |item| _ = self.active.remove(self.src.text(item.name));
        self.locals.shrinkRetainingCapacity(before);
    }
    fn returnValue(self: *Checker, value: ast.NodeId, span: source.Span) Error!void {
        try self.compatible(try self.expressionExpected(value, self.result), self.result, span);
        try self.requireHandled(0, span);
    }
    fn bind(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool) Error!void {
        return self.bindMode(name, ty_value, mutable);
    }
    fn bindMode(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool) Error!void {
        const text = self.src.text(name);
        if (try self.topLevel(name)) return self.sink.fail(eShadowing, name, "binding shadows a top-level declaration or import");
        if (self.active.contains(text)) return self.sink.fail(eShadowing, name, "binding shadows an active template binding");
        for (self.parameters) |parameter| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return self.sink.fail(eShadowing, name, "binding shadows a template type parameter");
        try self.active.put(self.allocator, text, self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .ty = ty_value, .mutable = mutable });
        try self.seedCleanup(ty_value);
    }
    fn callTarget(self: *Checker, invocation: Call, call_span: source.Span) Error!ast.Function {
        if (invocation.owner == null) {
            const spelling = self.src.text(invocation.name);
            const reserved = std.mem.eql(u8, spelling, "print") or @import("file_operations.zig").access(spelling) != null;
            if (reserved and !self.functions.contains(spelling)) return self.sink.fail(eUnsupported, invocation.name, "`print` and the file builtins are not supported inside generic function bodies");
        }
        const key = if (self.module_names) |names|
            try names.reference(invocation.owner orelse invocation.name, .function, if (invocation.owner != null) invocation.name else null, if (self.owner) |owner| self.src.text(owner) else null, self.sink)
        else
            try @import("function_identity.zig").localName(self.sink.allocator, self.src, invocation.owner, invocation.name);
        const index = self.functions.get(key) orelse {
            const clause = try typed.suggestionClause(self.allocator, self.functions, self.src.text(invocation.name));
            const message = if (clause.len == 0) "no function has this qualified name" else try std.fmt.allocPrint(self.allocator, "no function has this qualified name{s}", .{clause});
            return self.sink.fail("E_UNKNOWN_FUNCTION", invocation.name, message);
        };
        const function = self.program.functions[index];
        try self.effect_calls.append(self.allocator, .{ .caller = self.function_index, .callee = index, .span = call_span });
        if (self.module_names == null and function.policy.restricted) {
            const allowed = if (self.owner) |owner| std.mem.eql(u8, self.src.text(owner), self.src.text(function.policy.owner.?)) else false;
            if (!allowed) return self.sink.failRelated("E_PRIVATE_FUNCTION", invocation.name, "private generic method requires the same declaring domain", .{ .span = function.name, .message = "private function declared here" });
        }
        if (!self.scheduled[index]) {
            self.pending.appendAssumeCapacity(index);
            self.scheduled[index] = true;
        }
        return function;
    }
    fn substitutedLength(self: *Checker, span: source.Span, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!Symbolic {
        switch (requirements.matchScope(self.requirement_aliases, self.src, span)) {
            .subject => |index| {
                if (index >= arguments.len) return error.InternalError;
                return arguments[index];
            },
            .foreign => return self.lengthType(span),
            .local => {
                for (parameters, arguments) |parameter, argument| {
                    if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) {
                        if (!parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "expected a constant parameter");
                        return argument;
                    }
                }
            },
        }
        return self.lengthType(span);
    }
    fn substituted(self: *Checker, span: source.Span, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!Symbolic {
        for (self.program.types.expressions.callbacks) |callback| if (callback.span.start == span.start) {
            try self.enter(span);
            defer self.depth -= 1;
            const inputs = try self.field_arena.allocator().alloc(Symbolic, callback.parameters.len);
            for (callback.parameters, inputs) |input, *out| out.* = try self.substituted(input, parameters, arguments);
            return self.callbackType(callback, inputs, try self.substituted(callback.return_type, parameters, arguments));
        };
        if (self.catalog.templates.applications.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            var values: [16]Symbolic = undefined;
            const required = self.catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
            for (template.syntax.arguments, required, 0..) |argument, parameter, i| {
                values[i] = if (parameter.constant_length) try self.substitutedLength(argument, parameters, arguments) else try self.substituted(argument, parameters, arguments);
            }
            return self.shapes().nominal(template.declaration, values[0..template.arguments.len]);
        }
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            var length: Symbolic = .{ .length = template.length };
            if (template.length_parameter) |at| {
                var found = false;
                for (parameters, arguments) |parameter, argument| {
                    if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(at))) {
                        length = argument;
                        found = true;
                        break;
                    }
                }
                if (!found) length = try self.lengthType(at);
            }
            return self.arrayWithLength(length, try self.substituted(template.syntax.element, parameters, arguments), span);
        }
        const text = self.src.text(span);
        switch (requirements.matchScope(self.requirement_aliases, self.src, span)) {
            .subject => |index| {
                if (index >= arguments.len) return error.InternalError;
                return arguments[index];
            },
            .foreign => {},
            .local => {
                for (parameters, arguments) |parameter, argument| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return argument;
            },
        }
        return self.concreteType(span);
    }
    fn tyWithAliases(self: *Checker, span: source.Span, aliases: []const requirements.SubjectAlias) Error!Symbolic {
        const previous = self.requirement_aliases;
        self.requirement_aliases = aliases;
        defer self.requirement_aliases = previous;
        return self.ty(span);
    }
    fn substitutedWithAliases(self: *Checker, span: source.Span, parameters: []const ast.TypeParameter, arguments: []const Symbolic, aliases: []const requirements.SubjectAlias) Error!Symbolic {
        const previous = self.requirement_aliases;
        self.requirement_aliases = aliases;
        defer self.requirement_aliases = previous;
        return self.substituted(span, parameters, arguments);
    }
    fn resolveCall(self: *Checker, raw: Call) Error!Call {
        const applied = try @import("call_type_arguments.zig").split(self.src, self.program, self.module_names, raw, self.sink);
        const invocation = applied orelse raw;
        const codec = @import("source_codec.zig");
        if (!codec.operation(self.src.text(invocation.name)) or invocation.owner != null) return invocation;
        if (invocation.type_arguments.len != 1 or invocation.arguments.len != 1) return self.sink.fail("E_CODEC_ARITY", invocation.name, "codec operation requires one explicit domain type and one value argument");
        const target = try self.ty(invocation.type_arguments[0]);
        if (target != .concrete) return self.sink.fail(eUnsupported, invocation.type_arguments[0], "codec operations on type parameters require declared codec constraints");
        return codec.resolve(self.src, self.program, self.catalog, invocation, self.sink);
    }
    fn indirectCall(self: *Checker, invocation: Call) Error!Symbolic {
        const value = try self.namedValue(invocation.name);
        var concrete_parameters: [16]Symbolic = undefined;
        const contract: symbolic.Callback = if (value == .callback) value.callback.* else concrete: {
            const ty_value = try self.concreteValue(value, invocation.name);
            const signature = @import("callables.zig").signature(ty_value, self.catalog.records) orelse return self.sink.fail("E_CALLBACK_TYPE", invocation.name, "called local is not a function value");
            for (signature.parameters, 0..) |parameter, i| concrete_parameters[i] = .{ .concrete = parameter };
            break :concrete .{ .parameters = concrete_parameters[0..signature.parameters.len], .result = .{ .concrete = signature.return_type }, .effects = signature.effects };
        };
        if (invocation.type_arguments.len != 0 or invocation.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", invocation.name, "callback arguments must match its signature");
        for (invocation.arguments, contract.parameters) |input, parameter| {
            try self.compatible(try self.expression(input), parameter, invocation.name);
        }
        self.effect_masks[self.function_index] |= contract.effects;
        return contract.result;
    }
    fn collectionElement(self: *Checker, owner: Symbolic, span: source.Span) Error!Symbolic {
        if (dictionary_views.symbolicKind(self.catalog, owner)) |kind| if (kind != .item)
            return dictionary_views.symbolicElement(self.shapes(), try dictionary_views.symbolicOwner(self.shapes(), owner, span), kind, span);
        const kind = self.shapes().collectionKind(owner) orelse return self.sink.fail(eListType, span, "operation requires a managed list, string, or dictionary");
        if (kind == .string) return owner;
        return (try self.shapes().container(owner, span)).?.element;
    }
    /// Element bound by ordinary iteration: dictionary keys, view projections,
    /// or the element shape used by every other managed collection.
    fn iterationElement(self: *Checker, source_type: Symbolic, owner: Symbolic, span: source.Span) Error!Symbolic {
        if (dictionary_views.symbolicKind(self.catalog, source_type)) |view| if (view != .item)
            return dictionary_views.symbolicElement(self.shapes(), owner, view, span);
        if (self.shapes().collectionKind(owner) == .dictionary) return self.shapes().collectionKey(owner, span);
        return self.collectionElement(owner, span);
    }
    /// The dictionary receiver of one `items()` iteration source in a template body.
    fn fieldAssignment(self: *Checker, node: ast.Node) Error!Symbolic {
        const assignment = node.data.field_assignment;
        var root = assignment.target;
        while (self.program.nodes.items[@backingInt(root)].data == .field) root = self.program.nodes.items[@backingInt(root)].data.field.base;
        const root_node = self.program.nodes.items[@backingInt(root)];
        if (root_node.data == .name) {
            const binding = try self.local(root_node.data.name);
            if (!binding.mutable) return self.sink.fail(diagnostic.immutable, root_node.span, "record field assignment requires a mutable binding");
            try self.runtimeOwner(root_node.data.name, true);
        } else if (root_node.data != .index) return self.sink.fail("E_ASSIGNMENT_TARGET", root_node.span, "field assignment requires a mutable local record or list slot");
        self.seedManagedWrite(self.parameterIndex(root, 0));
        const expected = try self.expression(assignment.target);
        try self.compatible(try self.expressionExpected(assignment.value, expected), expected, node.span);
        return .{ .concrete = .unit };
    }
    /// Build an enum-indexed table from a dict literal whose context already demands `[Kind]T`.
    fn tableLiteral(self: *Checker, node: ast.Node, entries: []const ast.NodeId, expected: Symbolic, key: typed.Type) Error!Symbolic {
        const context: arrays.Context = .{ .src = self.src, .syntax = self.program, .catalog = self.catalog, .key = key };
        const named = try arrays.initializers(self.allocator, context, entries, self.sink);
        try self.recordFields(expected, named, true, node.span);
        return expected;
    }
    fn dictionaryLiteral(self: *Checker, node: ast.Node, entries: []const ast.NodeId) Error!Symbolic {
        var expected = self.expected_types.get(node.span);
        if (expected) |value| if (symbolic.array(value, self.catalog.records)) |shape| {
            if (shape.key) |key| return self.tableLiteral(node, entries, value, key);
        };
        if (expected == null and entries.len == 0) return self.sink.fail("E_DICT_INFERENCE", node.span, "empty dictionary requires an expected dictionary type");
        if (expected == null) expected = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("dict").?, &.{ try self.expression(entries[0]), try self.expression(entries[1]) });
        if (self.shapes().collectionKind(expected.?) != .dictionary) return self.sink.fail("E_DICT_TYPE", node.span, "dictionary literal requires a dictionary type");
        const key = try self.shapes().collectionKey(expected.?, node.span);
        const element = try self.collectionElement(expected.?, node.span);
        if (self.shapes().collectionKind(key) != .string) try self.supports(key, .integer, node.span);
        try self.supports(element, .copy, node.span);
        try self.supports(element, .storable, node.span);
        if (try self.requiresHandling(element)) return self.sink.fail(eResultOperation, node.span, "dictionary values cannot contain pending results");
        for (entries, 0..) |input, index| {
            const target = if (index % 2 == 0) key else element;
            try self.compatible(try self.expressionExpected(input, target), target, node.span);
        }
        self.seedEffect(.managed_allocation);
        return expected.?;
    }
    /// Build a fixed array from a list literal whose context already demands `[N]T`.
    fn fixedArrayLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, expected: Symbolic) Error!Symbolic {
        const shape = try self.arrayShape(expected, node.span);
        if (shape.length_parameter != null) return self.sink.fail(diagnostic.generic_length, node.span, "array literal construction requires a fixed length in an uncalled template");
        if (inputs.len != shape.length) return self.sink.fail("E_ARRAY_LENGTH", node.span, "list literal length differs from the expected fixed array");
        for (inputs) |input| try self.compatible(try self.expressionExpected(input, shape.element), shape.element, node.span);
        return expected;
    }
    /// A comprehension iterates one collection or integer range and yields a list of its
    /// produced values.
    fn comprehensionValue(self: *Checker, each: ast.Comprehension, span: source.Span) Error!Symbolic {
        const element = switch (each.source) {
            .iterable => |iterable| try self.collectionElement(try self.expression(iterable), span),
            .range => |bounds| try self.rangeElement(bounds, each.name, span),
        };
        const text = self.src.text(each.name);
        if (try self.topLevel(each.name) or self.active.contains(text)) return self.sink.fail(eShadowing, each.name, "comprehension binding shadows an active declaration");
        try self.bind(each.name, element, false);
        defer _ = self.active.remove(text);
        const produced = try self.expression(each.output);
        if (each.filter) |condition| try self.compatible(try self.expression(condition), .{ .concrete = .bool }, span);
        try self.supports(produced, .copy, span);
        try self.supports(produced, .storable, span);
        self.seedEffect(.managed_allocation);
        return self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{produced});
    }
    /// Resolve a `range(...)` comprehension source to its integer element type, mirroring the
    /// generic `for` range bounds check: a unit start is zero, and both bounds share one type.
    fn rangeElement(self: *Checker, bounds: @FieldType(ast.Comprehension.Source, "range"), name: source.Span, span: source.Span) Error!Symbolic {
        const element: Symbolic = if (self.program.nodes.items[@backingInt(bounds.start)].data == .unit) .{ .concrete = .i64 } else try self.expression(bounds.start);
        try self.supports(element, .integer, name);
        try self.compatible(try self.expression(bounds.end), element, span);
        return element;
    }

    /// Every f-string piece converts to text, so the whole literal is `str`.
    fn formatValue(self: *Checker, parts: []const ast.NodeId, span: source.Span) Error!Symbolic {
        const str_type: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
        var allocation = parts.len != 1;
        for (parts) |part| {
            const value = try self.expression(part);
            if (symbolic.same(value, str_type, self.catalog)) continue;
            allocation = true;
            if (self.isFloat(value)) continue;
            try self.supports(value, .integer, span);
        }
        if (allocation) self.seedEffect(.managed_allocation);
        return str_type;
    }
    fn listLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId) Error!Symbolic {
        var expected = self.expected_types.get(node.span);
        if (expected) |ty_value| if (symbolic.array(ty_value, self.catalog.records)) |shape| {
            if (shape.key == null) return self.fixedArrayLiteral(node, inputs, ty_value);
        };
        var element: ?Symbolic = if (expected) |ty_value| try self.collectionElement(ty_value, node.span) else null;
        if (inputs.len == 0 and expected == null) return self.sink.fail("E_LIST_INFERENCE", node.span, "empty list requires an expected List type");
        for (inputs) |input| {
            const value = if (element) |ty_value| try self.expressionExpected(input, ty_value) else try self.expression(input);
            if (element) |ty_value| try self.compatible(value, ty_value, node.span) else element = value;
        }
        try self.supports(element.?, .copy, node.span);
        try self.supports(element.?, .storable, node.span);
        if (try self.requiresHandling(element.?)) return self.sink.fail(eResultOperation, node.span, "list elements cannot contain pending results");
        if (expected == null) expected = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{element.?});
        self.seedEffect(.managed_allocation);
        return expected.?;
    }
    fn collectionOperation(self: *Checker, owner: Symbolic, operation: struct { kind: BufferKind, inputs: []const ast.NodeId, span: source.Span, owner_node: ?ast.NodeId = null }) Error!Symbolic {
        const family = self.shapes().collectionKind(owner) orelse return self.sink.fail(eListType, operation.span, "operation requires a managed collection");
        const element = try self.collectionElement(owner, operation.span);
        const key = if (family == .dictionary) try self.shapes().collectionKey(owner, operation.span) else element;
        const kind = operation.kind;
        if (operation.inputs.len != kind.arity()) return self.sink.fail("E_ARITY", operation.span, "collection argument count differs from its signature");
        if (family == .dictionary) if (dictionary_views.operation(kind)) |view|
            return self.shapes().nominal(self.catalog.templates.store.?.index.names.get(view.name()).?, &.{ key, element });
        const output: Symbolic = switch (kind) {
            .strip, .lstrip, .rstrip, .upper, .lower, .replace, .zfill => owner,
            .view, .slice => owner,
            .is_digit, .is_alpha, .is_space => .{ .concrete = .bool },
            .count => .{ .concrete = .i64 },
            .length => .{ .concrete = .i64 },
            .parse_int, .parse_int_range => try self.optionType(.{ .concrete = .i64 }),
            .parse_float, .parse_float_range => try self.optionType(self.floatType()),
            .read, .get => element,
            .contains => .{ .concrete = .bool },
            .append, .write => .{ .concrete = .unit },
            .keys, .values, .split => try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{if (kind == .keys) key else if (kind == .split) owner else element}),
            .join => owner,
            else => return self.sink.fail(eUnsupported, operation.span, "unsupported collection operation in generic body"),
        };
        const numeric_parse = kind == .parse_int or kind == .parse_float or kind == .parse_int_range or kind == .parse_float_range;
        if (numeric_parse and family != .bytes)
            return self.sink.fail(eListType, operation.span, "numeric byte parsing requires a bytes receiver");
        if (kind == .view and !self.immutableBytes(owner)) return self.sink.fail(eListType, operation.span, "view requires an immutable bytes receiver");
        if (family == .string and (kind == .write or kind == .append or kind == .get)) return self.sink.fail("E_TEXT_IMMUTABLE", operation.span, "strings are immutable");
        if (family != .string and (kind == .split or kind == .join)) return self.sink.fail(eListType, operation.span, "split and join require str");
        if (family != .dictionary and (kind == .keys or kind == .values or kind == .get)) return self.sink.fail(eListType, operation.span, "mapping operation requires a dictionary");
        const range_bound = kind == .view or kind == .slice or kind == .parse_int_range or kind == .parse_float_range;
        for (operation.inputs, 0..) |input, index| {
            const indexed = index == 0 and (kind == .read or kind == .write);
            const integer = family != .dictionary and (range_bound or indexed);
            const expected = if (family == .dictionary) (if (index == 0) key else element) else if (kind == .join) try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{owner}) else element;
            if (integer) try self.supports(try self.expression(input), .integer, operation.span) else try self.compatible(try self.expressionExpected(input, expected), expected, operation.span);
        }
        if (buffer_operations.managedAllocation(kind, family == .dictionary) or (family == .string and kind == .read)) self.seedEffect(.managed_allocation);
        self.seedCollectionWrite(kind, family == .dictionary, if (operation.owner_node) |node_id| self.parameterIndex(node_id, 0) else null);
        return output;
    }
    fn listOperation(self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "list_operation")) Error!Symbolic {
        return self.collectionOperation(try self.expression(operation.base), .{ .kind = operation.kind, .inputs = operation.arguments, .span = node.span, .owner_node = operation.base });
    }
    fn listMethod(self: *Checker, node: ast.Node) Error!Symbolic {
        const method = node.data.method_call;
        const name = self.src.text(method.name);
        if (std.mem.eql(u8, name, "read_only")) {
            if (method.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "read_only takes no arguments");
            const value = try self.expression(method.base);
            if (try self.concreteValue(value, node.span) != .filesystem_cap) return self.sink.fail("E_TYPE", node.span, "read_only requires a Filesystem capability");
            return value;
        }
        if (std.mem.eql(u8, name, "push")) return self.sink.fail("E_REMOVED_SPELLING", method.name, "`push` was removed; use `append(value)`");
        const kind = buffer_operations.method(name) orelse return self.sink.fail("E_LIST_METHOD", method.name, "unknown collection method");
        if (method.arguments.len == 0 and (kind == .parse_int or kind == .parse_float))
            if (try self.immediateNumericRange(method.base, kind, node.span)) |output| return output;
        return self.listOperation(node, .{ .base = method.base, .kind = kind, .arguments = method.arguments });
    }
    /// Whether a symbolic byte collection is the immutable `bytes` builtin and
    /// can therefore be read through a range without observing later mutation.
    fn immutableBytes(self: *Checker, value: Symbolic) bool {
        if (value == .concrete) {
            if (!value.concrete.isAggregate()) return false;
            const schema = self.catalog.records[value.concrete.recordIndex()];
            return schema.collection.kind == .bytes and !std.mem.eql(u8, schema.name, @import("nominal_templates.zig").byte_buffer_name);
        }
        if (value != .nominal) return false;
        const declaration = self.catalog.templates.store.?.index.declarations.items[value.nominal.declaration];
        return if (declaration.builtin_name) |name| std.mem.eql(u8, name, "bytes") else false;
    }
    /// Instantiate the builtin option around a symbolic numeric result.
    fn optionType(self: *Checker, element: Symbolic) Error!Symbolic {
        return self.shapes().nominal(self.catalog.templates.store.?.index.names.get("Option").?, &.{element});
    }
    const NumericRange = struct { owner: Symbolic, start: ?ast.NodeId, end: ?ast.NodeId, view: bool, kind: BufferKind, span: source.Span };
    /// Check one immediate range's receiver and optional bounds in source order.
    fn numericRangeResult(self: *Checker, range: NumericRange) Error!Symbolic {
        if (self.shapes().collectionKind(range.owner) != .bytes) return self.sink.fail(eListType, range.span, "numeric byte parsing requires a bytes receiver");
        if (range.start) |bound| try self.supports(try self.expression(bound), .integer, range.span);
        if (range.end) |bound| try self.supports(try self.expression(bound), .integer, range.span);
        if (!self.immutableBytes(range.owner)) {
            if (range.view) return self.sink.fail(eListType, range.span, "view requires an immutable bytes receiver");
            self.seedEffect(.managed_allocation);
        }
        return if (range.kind == .parse_int) try self.optionType(.{ .concrete = .i64 }) else try self.optionType(self.floatType());
    }
    /// Recognize a numeric parser consuming a slice or view directly. Concrete
    /// specialization performs the matching range lowering; this abstract pass
    /// mirrors its allocation effect so a generic `noalloc` contract agrees.
    fn immediateNumericRange(self: *Checker, id: ast.NodeId, kind: BufferKind, span: source.Span) Error!?Symbolic {
        const input = self.program.nodes.items[@backingInt(id)];
        return switch (input.data) {
            .slice => |slice| if (slice.step != null)
                null
            else
                try self.numericRangeResult(.{ .owner = try self.expression(slice.base), .start = slice.start, .end = slice.end, .view = false, .kind = kind, .span = span }),
            .method_call => |method| if (!std.mem.eql(u8, self.src.text(method.name), "view"))
                null
            else if (method.arguments.len != 2)
                self.sink.fail("E_ARITY", input.span, "view requires two bounds")
            else
                try self.numericRangeResult(.{ .owner = try self.expression(method.base), .start = method.arguments[0], .end = method.arguments[1], .view = true, .kind = kind, .span = span }),
            .call => |invocation| call_range: {
                const owner = invocation.owner orelse break :call_range null;
                if (!std.mem.eql(u8, self.src.text(invocation.name), "view")) break :call_range null;
                try call_arguments.positional(invocation, self.sink);
                if (invocation.type_arguments.len != 0 or invocation.arguments.len != 2) return self.sink.fail("E_ARITY", input.span, "view requires two bounds");
                break :call_range try self.numericRangeResult(.{ .owner = try self.namedValue(owner), .start = invocation.arguments[0], .end = invocation.arguments[1], .view = true, .kind = kind, .span = span });
            },
            else => null,
        };
    }
    /// Check `values[index] op= value` in a generic body against the element's own rules.
    fn indexAssignment(self: *Checker, node: ast.Node) Error!Symbolic {
        const assignment = node.data.index_assignment;
        const target = self.program.nodes.items[@backingInt(assignment.target)];
        const expected = try self.expression(assignment.target);
        self.seedManagedWrite(self.parameterIndex(assignment.target, 0));
        try self.augmentedTarget(assignment.op, expected, node.span);
        try self.compatible(try self.expressionExpected(assignment.value, expected), expected, node.span);
        if (target.data == .index) if (self.program.nodes.items[@backingInt(target.data.index.base)].data == .name)
            try self.runtimeOwner(self.program.nodes.items[@backingInt(target.data.index.base)].data.name, true);
        return .{ .concrete = .unit };
    }
    /// Augmented assignment accepts what the target type's ordinary binary rules accept.
    fn augmentedTarget(self: *Checker, op: ast.AssignmentOp, target: Symbolic, span: source.Span) Error!void {
        if (self.isFloat(target)) return;
        if (self.shapes().managed(target)) {
            if (op == .add and self.shapes().collectionKind(target) == .string) return;
            return self.sink.fail("E_TEXT_OPERATOR", span, "a managed collection augments with `+=` only, and str is the managed type whose `+=` a generic body can prove");
        }
        if (op == .div) return self.sink.fail("E_TYPE", span, "augmented `/=` produces a float; declare the binding as float or use `//=`");
        return self.supports(target, .integer, span);
    }
    fn listSlice(self: *Checker, node: ast.Node) Error!Symbolic {
        const slice = node.data.slice;
        const owner = try self.expression(slice.base);
        _ = try self.collectionElement(owner, node.span);
        if (slice.start) |input| try self.supports(try self.expression(input), .integer, node.span);
        if (slice.end) |input| try self.supports(try self.expression(input), .integer, node.span);
        if (slice.step) |input| try self.supports(try self.expression(input), .integer, node.span);
        self.seedEffect(.managed_allocation);
        return owner;
    }
    fn managedMethod(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (input_call.owner) |owner| if (self.active.get(self.src.text(owner))) |slot| {
            const receiver = if (self.option_facts.has(slot)) try self.optionElement(self.locals.items[slot].ty, owner) else self.locals.items[slot].ty;
            if (self.shapes().managed(receiver)) {
                const kind = buffer_operations.method(self.src.text(input_call.name)) orelse return self.sink.fail("E_LIST_METHOD", input_call.name, "unknown collection method");
                if (input_call.type_arguments.len != 0) return self.sink.fail("E_ARITY", span, "collection methods do not take explicit type arguments");
                const result = try self.collectionOperation(receiver, .{ .kind = kind, .inputs = input_call.arguments, .span = span });
                return result;
            }
        };
        return null;
    }
    fn floatType(self: *Checker) Symbolic {
        return .{ .concrete = self.catalog.names.get("float").? };
    }
    fn isFloat(self: *Checker, value: Symbolic) bool {
        return value == .concrete and numeric_surface.isFloat(value.concrete, self.catalog.records);
    }
    /// `T(x)` converts between integer widths wherever `T` names a type parameter of this
    /// template or a declared integer type, rather than a function.
    fn typeConversion(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        if (invocation.arguments.len != 1 or invocation.argument_names.len != 0) return null;
        const name = self.src.text(invocation.name);
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        var declared = false;
        for (self.parameters) |parameter| {
            if (std.mem.eql(u8, self.src.text(parameter.name), name)) declared = true;
        }
        if (!declared) {
            const concrete = self.catalog.names.get(name) orelse return null;
            if (!concrete.isInteger()) return null;
        }
        const target = try self.ty(invocation.name);
        const input = try self.expression(invocation.arguments[0]);
        try self.supports(input, .integer, span);
        try self.supports(target, .integer, span);
        return target;
    }
    fn scalarConstructor(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        const name = self.src.text(invocation.name);
        const floating = std.mem.eql(u8, name, "float");
        if (!floating and !std.mem.eql(u8, name, "int")) return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", span, "numeric conversions require one argument");
        const input = try self.expression(invocation.arguments[0]);
        if (!self.isFloat(input)) try self.supports(input, .integer, span);
        return if (floating) self.floatType() else .{ .concrete = .i64 };
    }
    fn optionElement(self: *Checker, value: Symbolic, span: source.Span) Error!Symbolic {
        const shape = try self.shapes().schema(value, span);
        if (shape.kind == .variants and shape.fields.len == 2) {
            var element: ?Symbolic = null;
            var none = false;
            for (shape.fields) |field| {
                if (std.mem.eql(u8, field.name, "some")) element = field.ty;
                if (std.mem.eql(u8, field.name, "none") and field.ty == null) none = true;
            }
            if (none) if (element) |item| return item;
        }
        return self.sink.fail("E_TYPE", span, "Some and contextual None require Option");
    }
    fn contextualOption(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0 or !std.mem.eql(u8, self.src.text(invocation.name), "Some")) return null;
        if (self.active.contains("Some") or self.functions.contains("Some")) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", span, "Some requires one payload");
        const expected = self.expected_types.get(span) orelse return self.sink.fail("E_OPTION_INFERENCE", span, "Some requires an expected Option type");
        const element = try self.optionElement(expected, span);
        try self.compatible(try self.expressionExpected(invocation.arguments[0], element), element, span);
        return expected;
    }
    fn cellConstructor(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        const name = self.src.text(invocation.name);
        if (!std.mem.eql(u8, name, "Cell")) return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        const store = self.catalog.templates.store orelse return null;
        const declaration = store.index.names.get("Cell") orelse return null;
        const builtin = store.index.declarations.items[declaration].builtin_name orelse return null;
        if (!std.mem.eql(u8, builtin, "Cell")) return null;
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", span, "Cell requires one value argument");
        const keyword = if (invocation.argument_names.len == 0) null else invocation.argument_names[0];
        if (keyword == null or !std.mem.eql(u8, self.src.text(keyword.?), "value"))
            return self.sink.fail("E_UNKNOWN_FIELD", invocation.name, "construct Cell with value=initial");
        var expected_element: ?Symbolic = null;
        var result: ?Symbolic = null;
        if (self.expected_types.get(span)) |expected| {
            if (self.shapes().isCell(expected)) {
                const schema = try self.shapes().schema(expected, span);
                if (schema.kind != .record) return error.InternalError;
                for (schema.fields) |field| {
                    if (!std.mem.eql(u8, field.name, "value")) continue;
                    expected_element = field.ty orelse return error.InternalError;
                    result = expected;
                    break;
                }
                if (result == null) return error.InternalError;
            }
        }
        const value = if (expected_element) |element| try self.expressionExpected(invocation.arguments[0], element) else try self.expression(invocation.arguments[0]);
        if (expected_element) |element| try self.compatible(value, element, span);
        if (try self.requiresHandling(value)) return self.sink.fail("E_CELL_ELEMENT", span, "Cell contents must be copyable, storable values without Result, Option, resources, capabilities, or result obligations");
        try self.supports(value, .storable, span);
        self.seedEffect(.managed_allocation);
        return result orelse try self.shapes().nominal(declaration, &.{value});
    }
    fn numericLiteral(self: *Checker, span: source.Span, minimum: bool) Error!Symbolic {
        const expected = self.expected_types.get(span);
        if (float_syntax.isLiteral(self.src.text(span)) or (expected != null and self.isFloat(expected.?))) return self.floatType();
        return .{ .concrete = (try integer_literal.parseExpected(self.src, span, minimum, if (expected != null and expected.? == .concrete) expected.?.concrete else null, self.sink)).ty };
    }
    fn contextualResult(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        const name = self.src.text(invocation.name);
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        const ok = std.mem.eql(u8, name, "Ok");
        if (!ok and !std.mem.eql(u8, name, "Err")) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", span, "Ok and Err require one payload");
        const expected = self.expected_types.get(span) orelse return self.sink.fail("E_RESULT_INFERENCE", span, "Ok and Err require an expected Result type");
        const shape = try self.resultShape(expected, span, "E_TYPE");
        const payload = if (ok) shape.ok_type else shape.error_type;
        try self.compatible(try self.expressionExpected(invocation.arguments[0], payload), payload, span);
        return expected;
    }
    fn textConstructor(self: *Checker, call_value: Call, span: source.Span) Error!?Symbolic {
        if (call_value.owner != null or !std.mem.eql(u8, self.src.text(call_value.name), "str")) return null;
        if (self.active.contains("str") or self.functions.contains("str")) return null;
        const target = self.catalog.names.get("str") orelse return null;
        if (self.catalog.records[target.recordIndex()].collection.kind != .string) return null;
        if (call_value.arguments.len != 1 or call_value.type_arguments.len != 0) return self.sink.fail("E_ARITY", span, "str requires one value argument");
        const value = try self.expression(call_value.arguments[0]);
        if (value == .concrete) {
            const scalar = value.concrete.isInteger() or value.concrete == .bool or value.concrete == .unit;
            const aggregate = value.concrete.isAggregate() and (self.shapes().collectionKind(value) == .string or std.mem.eql(u8, self.catalog.records[value.concrete.recordIndex()].name, "float"));
            if (!scalar and !aggregate) return self.sink.fail("E_TEXT_CONVERSION", span, "str requires a scalar or str value");
        } else try self.supports(value, .integer, span);
        self.seedEffect(.managed_allocation);
        return Symbolic{ .concrete = target };
    }
    /// `.read_only()`, `.only(...)` and `.names()` on a capability value.
    fn capabilityMethodCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        const owner = input_call.owner orelse return null;
        const name = self.src.text(input_call.name);
        if (std.mem.eql(u8, name, "read_only")) {
            if (input_call.arguments.len != 0 or input_call.type_arguments.len != 0) return self.sink.fail("E_ARITY", span, "read_only takes no arguments");
            const value = try self.namedValue(owner);
            try self.compatible(value, .{ .concrete = .filesystem_cap }, owner);
            return .{ .concrete = .filesystem_cap };
        }
        if (std.mem.eql(u8, name, "dir")) {
            if (input_call.arguments.len != 1 or input_call.type_arguments.len != 0 or input_call.argument_names.len != 0) return self.sink.fail("E_ARITY", span, "dir takes one path argument");
            const argument = self.program.nodes.items[@backingInt(input_call.arguments[0])];
            const bytes = switch (argument.data) {
                .text, .bytes => |spelling| spelling,
                else => return self.sink.fail("E_FILESYSTEM_DIR", argument.span, "dir requires a string literal path"),
            };
            if (!scopedDirectoryPath(bytes)) return self.sink.fail("E_FILESYSTEM_DIR", argument.span, "dir path must stay within the current root");
            const value = try self.namedValue(owner);
            try self.compatible(value, .{ .concrete = .filesystem_cap }, owner);
            return .{ .concrete = .filesystem_cap };
        }
        if (std.mem.eql(u8, name, "host")) {
            if (input_call.arguments.len != 1 or input_call.type_arguments.len != 0 or input_call.argument_names.len != 0) return self.sink.fail("E_ARITY", span, "host takes one endpoint argument");
            const argument = self.program.nodes.items[@backingInt(input_call.arguments[0])];
            const bytes = switch (argument.data) {
                .text, .bytes => |spelling| spelling,
                else => return self.sink.fail("E_NETWORK_HOST", argument.span, "host requires a string literal endpoint"),
            };
            if (bytes.len == 0 or std.mem.indexOfScalar(u8, bytes, 0) != null) return self.sink.fail("E_NETWORK_HOST", argument.span, "host endpoint must be a nonempty str without NUL");
            const value = try self.namedValue(owner);
            try self.compatible(value, .{ .concrete = .network_cap }, owner);
            return .{ .concrete = .network_cap };
        }
        // The free `read_text(fs, path)` spelling is rejected by `callTarget`;
        // reject the qualified `fs.read_text(path)` spelling the same way so the
        // receiver names the reserved builtin rather than a missing function.
        if (@import("file_operations.zig").access(name)) |_| {
            const receiver_slot = self.active.get(self.src.text(owner)) orelse return null;
            const receiver = self.locals.items[receiver_slot].ty;
            if (receiver == .concrete and receiver.concrete == .filesystem_cap)
                return self.sink.fail(eUnsupported, span, "file operations are not supported inside generic function bodies");
            return null;
        }
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        const receiver = self.locals.items[slot].ty;
        if (receiver != .concrete or receiver.concrete != .environment_cap) return null;
        if (std.mem.eql(u8, name, "only")) {
            if (input_call.type_arguments.len != 0 or input_call.arguments.len == 0) return self.sink.fail("E_ARITY", span, "env.only takes at least one literal name");
            for (input_call.arguments) |argument| {
                const spelling = self.program.nodes.items[@backingInt(argument)];
                if (spelling.data != .text) return self.sink.fail("E_ENVIRONMENT_NAME", spelling.span, "environment names must be literal str values");
            }
            return .{ .concrete = .environment_cap };
        }
        if (std.mem.eql(u8, name, "names")) {
            if (input_call.type_arguments.len != 0 or input_call.arguments.len != 0) return self.sink.fail("E_ARITY", span, "env.names takes no arguments");
            const store = self.catalog.templates.store orelse return error.InternalError;
            const declaration = store.index.names.get("List") orelse return error.InternalError;
            const text: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return self.sink.fail("E_TYPE", span, "env.names requires str") };
            const result = try self.shapes().nominal(declaration, &.{text});
            return result;
        }
        return null;
    }
    fn viewSnapshot(self: *Checker, call_value: Call, span: source.Span) Error!?Symbolic {
        if (call_value.owner != null or !std.mem.eql(u8, self.src.text(call_value.name), "list")) return null;
        if (self.active.contains("list") or self.functions.contains("list")) return null;
        if (call_value.arguments.len != 1 or call_value.type_arguments.len != 0) return null;
        const view = try self.expression(call_value.arguments[0]);
        const kind = dictionary_views.symbolicKind(self.catalog, view) orelse return null;
        if (kind == .item) return null;
        const mapping = try dictionary_views.symbolicOwner(self.shapes(), view, span);
        const element = try dictionary_views.symbolicElement(self.shapes(), mapping, kind, span);
        self.seedEffect(.managed_allocation);
        const result = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{element});
        return result;
    }
    fn specialCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (try self.viewSnapshot(input_call, span)) |value| return value;
        if (try self.capabilityMethodCall(input_call, span)) |value| return value;
        if (try self.textConstructor(input_call, span)) |value| return value;
        if (std.mem.eql(u8, self.src.text(input_call.name), "todo") and input_call.owner == null) {
            _ = try self.ty(input_call.type_arguments[0]);
            return self.recordHole(input_call.name, input_call.type_arguments[0], span);
        }
        if (try self.truncatingHelper(input_call, span)) |value| return value;
        if (try self.variantConstruction(input_call, span)) |value| return value;
        if (try self.managedMethod(input_call, span)) |value| return value;
        if (try self.cellConstructor(input_call, span)) |value| return value;
        if (try self.contextualResult(input_call, span)) |value| return value;
        if (try self.contextualOption(input_call, span)) |value| return value;
        if (try self.scalarConstructor(input_call, span)) |value| return value;
        if (try self.typeConversion(input_call, span)) |value| return value;
        if (input_call.owner == null and self.active.contains(self.src.text(input_call.name))) {
            const value = try self.indirectCall(input_call);
            return value;
        }
        if (try self.operationCall(input_call)) |result| return result;
        return null;
    }
    /// One binding's snapshot entry, spelled from its abstract type.
    fn holeCandidate(self: *Checker, binding: Local) Error!diagnostic.Candidate {
        return .{
            .name = self.src.text(binding.name),
            .ty = try self.symbolicText(binding.ty),
            .declaration = binding.name,
            .mutable = binding.mutable,
            .usable = binding.available,
        };
    }
    /// Offer every active, unconsumed binding a filling could read at a typed hole.
    fn holeCandidates(self: *Checker, out: *std.ArrayList(diagnostic.Candidate)) Error!void {
        for (self.locals.items, 0..) |binding, index| {
            if (self.active.get(self.src.text(binding.name)) != index) continue;
            try out.append(self.allocator, try self.holeCandidate(binding));
        }
    }
    /// The generic requirements in force at a typed hole.
    fn holeRequirements(self: *Checker, out: *std.ArrayList(diagnostic.Requirement)) Error!void {
        try diagnostic.appendRequirements(self.allocator, self.src, self.program.functions[self.function_index].signature.type_parameters, out);
    }
    /// The template whose body the hole sits in.
    fn holeFunction(self: *Checker) diagnostic.Fact {
        const name = self.program.functions[self.function_index].name;
        return .{ .text = self.src.text(name), .span = name };
    }
    /// The contextual expected type, published only when the checker knows one.
    fn holeExpected(self: *Checker, call_span: source.Span) Error!?diagnostic.Fact {
        const expected = self.expected_types.get(call_span) orelse return null;
        return .{ .text = try self.symbolicText(expected), .span = call_span };
    }
    /// The declared effect ceiling and permitted mutation footprint.
    fn holeContract(self: *Checker) Error!diagnostic.ObligationContract {
        const function = self.program.functions[self.function_index];
        return .{
            .effects = if (function.policy.effect_bound) |bound| .{ .text = self.src.text(bound.span), .span = bound.span } else null,
            .mutation = try diagnostic.mutationFact(self.allocator, self.src, function),
        };
    }
    /// The bounded facts this checker can see at a typed hole. The candidate and
    /// requirement lists live in the checker's own allocator, so they outlive
    /// this call and are released with the rest of the check.
    fn holeFindings(self: *Checker, call_span: source.Span, candidates: []const diagnostic.Candidate, required: []const diagnostic.Requirement) Error!diagnostic.Findings {
        return .{ .function = self.holeFunction(), .expected = try self.holeExpected(call_span), .candidates = candidates, .requirements = required, .contract = try self.holeContract() };
    }
    /// Record one typed hole from the facts this checker sees right now.
    fn recordHole(self: *Checker, at: source.Span, target: source.Span, call_span: source.Span) Error {
        var candidates: std.ArrayList(diagnostic.Candidate) = .empty;
        try self.holeCandidates(&candidates);
        var required: std.ArrayList(diagnostic.Requirement) = .empty;
        try self.holeRequirements(&required);
        return self.sink.recordHole(self.src, at, target, try self.holeFindings(call_span, candidates.items, required.items));
    }
    /// Render one abstract type as bounded source spelling for a hole snapshot.
    fn symbolicText(self: *Checker, value: Symbolic) error{OutOfMemory}![]const u8 {
        var out: std.Io.Writer.Allocating = .init(self.allocator);
        // The successful slice is transferred out and empties the writer, so
        // this releases only a partial buffer on an error return.
        defer out.deinit();
        self.writeSymbolic(&out.writer, value, 4) catch return error.OutOfMemory;
        return out.toOwnedSlice();
    }
    /// Write one abstract type, replacing anything past `depth` with a marker
    /// instead of recursing without bound.
    fn writeSymbolic(self: *Checker, writer: *std.Io.Writer, value: Symbolic, depth: usize) error{OutOfMemory}!void {
        if (depth == 0) {
            writer.writeAll("<abstract>") catch return error.OutOfMemory;
            return;
        }
        switch (value) {
            .concrete => |ty_value| writer.writeAll(typed.typeName(ty_value, self.catalog.records)) catch return error.OutOfMemory,
            .parameter => |index| writer.writeAll(self.src.text(self.parameters[index].name)) catch return error.OutOfMemory,
            .length_parameter => |index| writer.writeAll(self.src.text(self.parameters[index].name)) catch return error.OutOfMemory,
            .length => |count| writer.print("{d}", .{count}) catch return error.OutOfMemory,
            .array => |array| {
                writer.writeAll("[") catch return error.OutOfMemory;
                try self.writeSymbolic(writer, array.element, depth - 1);
                if (array.key) |key| {
                    writer.print(": {s}]", .{typed.typeName(key, self.catalog.records)}) catch return error.OutOfMemory;
                } else {
                    writer.print("; {d}]", .{array.length}) catch return error.OutOfMemory;
                }
            },
            .callback => |callback| {
                writer.writeAll("fn(") catch return error.OutOfMemory;
                for (callback.parameters, 0..) |parameter, index| {
                    if (index != 0) writer.writeAll(", ") catch return error.OutOfMemory;
                    try self.writeSymbolic(writer, parameter, depth - 1);
                }
                writer.writeAll(") -> ") catch return error.OutOfMemory;
                try self.writeSymbolic(writer, callback.result, depth - 1);
            },
            .nominal => |nominal| {
                const store = self.catalog.templates.store orelse {
                    writer.writeAll("<nominal>") catch return error.OutOfMemory;
                    return;
                };
                const declaration = store.index.declarations.items[nominal.declaration];
                writer.writeAll(declaration.builtin_name orelse self.src.text(declaration.name)) catch return error.OutOfMemory;
                if (nominal.arguments.len == 0) return;
                writer.writeAll("[") catch return error.OutOfMemory;
                for (nominal.arguments, 0..) |argument, index| {
                    if (index != 0) writer.writeAll(", ") catch return error.OutOfMemory;
                    try self.writeSymbolic(writer, argument, depth - 1);
                }
                writer.writeAll("]") catch return error.OutOfMemory;
            },
        }
    }
    fn call(self: *Checker, input_call: Call, span: source.Span) Error!Symbolic {
        if (try self.specialCall(input_call, span)) |value| {
            if (!std.mem.eql(u8, self.src.text(input_call.name), "Cell")) try call_arguments.positional(input_call, self.sink);
            return value;
        }
        const resolved = try self.resolveCall(input_call);
        const function = try self.callTarget(resolved, input_call.name);
        const signature = function.signature;
        const invocation = try call_arguments.bind(self.field_arena.allocator(), self.src, self.program.nodes.items, resolved, signature, self.sink);
        if (function.policy.conversion) return self.sink.fail(eUnsupported, span, "generic conversions still need abstract checking");
        if (invocation.type_arguments.len != 0 and invocation.type_arguments.len != signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (invocation.arguments.len != signature.parameters.len) return self.sink.fail("E_ARITY", span, "argument count does not match function parameters");
        var provider: constraint_lookup.Provider = .{ .program = self.program, .src = self.src, .names = self.module_names };
        const required = try requirements.resolveBounds(self.allocator, self.src, signature.type_parameters, self.sink, provider.lookup());
        defer requirements.deinitResolved(self.allocator, required);
        const arguments = try self.allocator.alloc(Symbolic, required.len);
        defer self.allocator.free(arguments);
        const inferred = invocation.type_arguments.len == 0 and required.len != 0;
        const actuals = if (inferred) try self.inferCall(invocation, signature, arguments, span) else null;
        defer if (actuals) |values| self.allocator.free(values);
        for (required, arguments, 0..) |parameter, *argument, index| {
            const argument_span = if (inferred) span else invocation.type_arguments[index];
            if (!inferred) argument.* = if (parameter.constant_length) try self.lengthType(argument_span) else try self.ty(argument_span);
            try self.inferredRequirement(argument.*, parameter, argument_span);
        }
        for (required, arguments) |parameter, argument| try self.structural(argument, parameter, signature.type_parameters, arguments);
        for (0..invocation.arguments.len) |source_index| {
            const input_index = call_arguments.parameterPosition(invocation, source_index);
            const input = invocation.arguments[input_index];
            const parameter = signature.parameters[input_index];
            const expected = try self.substituted(parameter.ty, signature.type_parameters, arguments);
            const node = self.program.nodes.items[@backingInt(input)];
            try self.compatible(if (actuals) |values| values[input_index] else try self.expressionExpected(input, expected), expected, node.span);
        }
        return self.substituted(signature.return_type, signature.type_parameters, arguments);
    }
    fn inferredRequirement(self: *Checker, argument: Symbolic, parameter: requirements.Parameter, argument_span: source.Span) Error!void {
        const satisfies = switch (argument) {
            .length, .length_parameter => parameter.constant_length,
            .parameter => |index| self.parameters[index].requirements.implies(parameter.requirements),
            .concrete => |builtin| parameter.requirements.accepts(builtin, self.catalog.records),
            .callback, .array, .nominal => supportsSet(argument, parameter.requirements, self.parameters, self.catalog),
        };
        if (!satisfies) return self.sink.failRelated(
            eArgument,
            argument_span,
            "type argument does not satisfy the callee's declared requirements",
            .{ .span = parameter.name, .message = "required type parameter declared here" },
        );
    }
    fn inferCall(self: *Checker, invocation: Call, signature: @FieldType(ast.Function, "signature"), arguments: []Symbolic, span: source.Span) Error![]Symbolic {
        var inference: @import("generic_inference.zig").Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = invocation.name };
        if (self.expected_types.get(span)) |expected| try inference.match(signature.return_type, expected);
        const contextual = inference.complete();
        if (contextual) try inference.finish(arguments);
        const actuals = try self.allocator.alloc(Symbolic, invocation.arguments.len);
        errdefer self.allocator.free(actuals);
        for (0..invocation.arguments.len) |source_index| {
            const position = call_arguments.parameterPosition(invocation, source_index);
            const input = invocation.arguments[position];
            const parameter = signature.parameters[position];
            const actual = &actuals[position];
            actual.* = if (contextual) try self.expressionExpected(input, try self.substituted(parameter.ty, signature.type_parameters, arguments)) else try self.expression(input);
            try inference.match(parameter.ty, actual.*);
        }
        try inference.finish(arguments);
        return actuals;
    }
    fn operationCall(self: *Checker, invocation: Call) Error!?Symbolic {
        const owner = invocation.owner orelse return null;
        var contract: ?ast.Operation = null;
        var owner_index: ?usize = null;
        for (self.parameters, 0..) |parameter, index| if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(owner))) {
            owner_index = index;
            for (parameter.operation_requirements) |operation| if (std.mem.eql(u8, self.src.text(operation.name), self.src.text(invocation.name))) {
                contract = operation;
                break;
            };
        };
        const resolved_owner = owner_index orelse return null;
        const aliases = requirements.subjectAliases(self.parameters[resolved_owner]);
        const operation = contract orelse return self.sink.fail("E_GENERIC_REQUIREMENT", invocation.name, "type parameter does not declare this operation");
        if (invocation.type_arguments.len != 0 or invocation.arguments.len != operation.parameters.len)
            return self.sink.fail("E_ARITY", invocation.name, "structural operation requires its declared value/reference arguments and no type arguments");
        for (invocation.arguments, operation.parameters) |input, parameter| {
            const expected = try self.tyWithAliases(parameter.ty, aliases);
            const node = self.program.nodes.items[@backingInt(input)];
            try self.compatible(try self.expression(input), expected, node.span);
        }
        self.effect_masks[self.function_index] |= operation.effect_bound.allowed;
        const result = try self.tyWithAliases(operation.return_type, aliases);
        return result;
    }
    /// Find the operation a parameter's own requirements promise under a given name.
    fn findProvidedOperation(self: *Checker, parameter_index: usize, operation_name: source.Span) ?ast.Operation {
        for (self.parameters[parameter_index].operation_requirements) |provided| {
            if (std.mem.eql(u8, self.src.text(provided.name), self.src.text(operation_name))) return provided;
        }
        return null;
    }
    fn structural(self: *Checker, argument: Symbolic, required: requirements.Parameter, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!void {
        if (required.field_requirements.len != 0) {
            const shape = try self.shapes().requireRecord(argument, required.name, false);
            for (required.field_requirements) |field| {
                const index = try self.shapes().memberIndex(shape, field.name);
                try self.same(shape.fields[index].ty.?, try self.substitutedWithAliases(field.ty, parameters, arguments, requirements.subjectAliases(required)), field.name);
            }
        }
        for (required.operation_requirements) |operation| {
            var actual: ?ast.Operation = null;
            var concrete = false;
            var provider_aliases: []const requirements.SubjectAlias = &.{};
            switch (argument) {
                .parameter => |index| {
                    provider_aliases = requirements.subjectAliases(self.parameters[index]);
                    actual = self.findProvidedOperation(index, operation.name);
                },
                .concrete => |target| {
                    const function = try (@import("structural_constraints.zig").Context{ .src = self.src, .catalog = &self.catalog, .program = self.program, .sink = self.sink }).method(target, operation.name);
                    actual = .{ .name = function.name, .parameters = function.signature.parameters, .return_type = function.signature.return_type, .effect_bound = function.policy.effect_bound.? };
                    concrete = true;
                },
                else => {},
            }
            const provided = actual orelse return self.sink.fail(eArgument, operation.name, "forwarded type does not promise the required operation");
            if (provided.effect_bound.allowed & ~operation.effect_bound.allowed != 0 or provided.parameters.len != operation.parameters.len)
                return self.sink.fail(eArgument, operation.name, "forwarded operation arity or effects do not imply the contract");
            for (provided.parameters, operation.parameters) |input, expected| {
                const actual_type = if (concrete) try self.concreteType(input.ty) else try self.tyWithAliases(input.ty, provider_aliases);
                try self.same(actual_type, try self.substitutedWithAliases(expected.ty, parameters, arguments, requirements.subjectAliases(required)), expected.name);
            }
            const result = if (concrete) try self.concreteType(provided.return_type) else try self.tyWithAliases(provided.return_type, provider_aliases);
            try self.same(result, try self.substitutedWithAliases(operation.return_type, parameters, arguments, requirements.subjectAliases(required)), operation.name);
        }
    }
    fn validateStructural(self: *Checker) Error!void {
        for (self.parameters) |parameter| {
            for (parameter.field_requirements) |field| {
                const transferable = try self.transfers(try self.tyWithAliases(field.ty, requirements.subjectAliases(parameter)));
                if (transferable) return self.sink.fail("E_GENERIC_REQUIREMENT", field.ty, "structural fields require a copyable field type without result obligations");
            }
            for (parameter.operation_requirements) |operation| {
                _ = try self.tyWithAliases(operation.return_type, requirements.subjectAliases(parameter));
                for (operation.parameters) |input| _ = try self.tyWithAliases(input.ty, requirements.subjectAliases(parameter));
            }
        }
    }
    fn expressionExpected(self: *Checker, id: ast.NodeId, expected: Symbolic) Error!Symbolic {
        try self.expected_types.put(self.allocator, self.program.nodes.items[@backingInt(id)].span, expected);
        return self.expression(id);
    }
    fn expression(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const before = self.temporary_results;
        self.expression_depth += 1;
        defer self.expression_depth -= 1;
        errdefer self.temporary_results = before;
        const result = try self.expressionValue(id);
        self.temporary_results = before;
        if (self.expression_depth > 1 and (try self.requiresHandling(result))) self.temporary_results += 1;
        return result;
    }
    fn domainBacking(self: *Checker, value: Symbolic, span: source.Span) Error!Symbolic {
        const domain_type = try self.concreteValue(value, span);
        const backing = try self.catalog.domain(domain_type, span, self.sink);
        const owner = if (self.owner) |name| try self.concreteType(name) else null;
        if (owner == null or !symbolic.same(owner.?, value, self.catalog)) return self.sink.failRelated(
            "E_PRIVATE_DOMAIN",
            span,
            "only functions declared inside this domain can access its representation; use its factories and accessors",
            .{ .span = self.catalog.records[domain_type.recordIndex()].declaration, .message = "domain representation is private here" },
        );
        return .{ .concrete = backing };
    }
    fn expressionValue(self: *Checker, id: ast.NodeId) Error!Symbolic {
        var node = self.program.nodes.items[@backingInt(id)];
        if (node.data == .call) if (try @import("record_calls.zig").lower(self.field_arena.allocator(), self.src, self.catalog, node.data.call, self.sink)) |record| {
            node.data = record.data;
        };
        try self.enter(node.span);
        defer self.depth -= 1;
        return switch (node.data) {
            .name => |name| try self.namedValue(name),
            .wrap => |wrap| result: {
                const operand = try self.expression(wrap.value);
                const target = try self.ty(wrap.ty);
                try self.compatible(operand, try self.domainBacking(target, node.span), node.span);
                break :result target;
            },
            .unwrap => |input| try self.domainBacking(try self.expression(input), node.span),
            .arena_escape => return self.sink.fail(eUnsupported, node.span, "managed arena scopes and escape copies are not supported inside generic function bodies"),
            .file_operation => return self.sink.fail(eUnsupported, node.span, "file operations are not supported inside generic function bodies"),
            .buffer_operation => |operation| try self.bufferValue(operation),
            .external_read => |read| try self.externalValue(read),
            .environment_get => |get| try self.environmentValue(get),
            .acquire_resource => |acquire| try self.acquireResource(acquire),
            .complete_resource => |complete| try self.completeResource(complete),
            .resource_io => |io| try self.resourceIo(io),
            .restrict_resource => |restrict| result: {
                const value = try self.expression(restrict.value);
                const value_type = try self.concreteValue(value, node.span);
                if (value_type.resourceKind() == null) return self.sink.fail("E_TYPE", node.span, "restriction requires filesystem or network capability authority");
                break :result value;
            },
            .call => |invocation| try self.call(invocation, node.span),
            .propagate => |operand| try self.propagateValue(operand, node.span),
            .bytes, .text => try self.concreteType(node.span),
            .membership => |membership| member: {
                const needle = try self.expression(membership.needle);
                const container = try self.expression(membership.container);
                const expected = if (self.shapes().collectionKind(container) == .dictionary) try self.shapes().collectionKey(container, node.span) else try self.collectionElement(container, node.span);
                try self.compatible(needle, expected, node.span);
                break :member .{ .concrete = .bool };
            },
            .dictionary_literal => |entries| try self.dictionaryLiteral(node, entries),
            .unit => unit: {
                if (self.expected_types.get(node.span)) |expected| if (self.shapes().kind(expected) == .variants) {
                    _ = try self.optionElement(expected, node.span);
                    break :unit expected;
                };
                break :unit .{ .concrete = .unit };
            },
            .boolean => .{ .concrete = .bool },
            .integer => |span| try self.numericLiteral(span, false),
            .unary => |unary| result: {
                if (unary.op == .is_none) {
                    const operand = try self.rawOptionExpression(unary.operand);
                    _ = try self.optionElement(operand, unary.op_span);
                    if (try self.transfers(operand)) return self.sink.fail("E_OPTION_TEST", unary.op_span, "use match for an Option carrying an owned value or checked Result");
                    break :result .{ .concrete = .bool };
                }
                const child = self.program.nodes.items[@backingInt(unary.operand)];
                const operand: Symbolic = if (unary.op == .neg and child.data == .integer)
                    try self.numericLiteral(child.data.integer, true)
                else
                    try self.expression(unary.operand);
                if (unary.op == .neg) {
                    if (!self.isFloat(operand)) try self.supports(operand, .integer, unary.op_span);
                } else try self.compatible(operand, .{ .concrete = if (unary.op == .not) .bool else .u64 }, unary.op_span);
                break :result operand;
            },
            .binary => |operation| try self.binary(operation),
            .record => |record| try self.recordValue(record, node.span),
            .variant => |variant| try self.variantValue(variant, node.span),
            .field_assignment => try self.fieldAssignment(node),
            .index_assignment => try self.indexAssignment(node),
            .list_literal => |inputs| try self.listLiteral(node, inputs),
            .format => |parts| try self.formatValue(parts, node.span),
            .comprehension => |each| try self.comprehensionValue(each, node.span),
            .list_operation => |operation| try self.listOperation(node, operation),
            .method_call => try self.listMethod(node),
            .slice => try self.listSlice(node),
            .replace => |replacement| result: {
                const base = try self.expression(replacement.base);
                const shape = try self.arrayIndex(base, replacement.index, node.span);
                if ((try self.requiresHandling(shape.element))) return self.sink.fail(eResultOperation, node.span, "replacement would drop a result-bearing element");
                try self.compatible(try self.expression(replacement.value), shape.element, node.span);
                break :result base;
            },
            .field => |field| result: {
                if (try self.enumMember(field, node.span)) |value| break :result value;
                const base = try self.expression(field.base);
                const shape = try self.shapes().requireRecord(base, node.span, false);
                const index = try self.shapes().memberIndex(shape, field.name);
                for (shape.fields, 0..) |other, i| {
                    if (i != index and (try self.requiresHandling(other.ty.?))) return self.sink.fail(eResultOperation, node.span, "projection would drop another result-bearing field");
                }
                break :result shape.fields[index].ty.?;
            },
            .length => |input| result: {
                const base = try self.expression(input);
                if (dictionary_views.symbolicKind(self.catalog, base)) |kind| if (kind != .item) break :result .{ .concrete = .i64 };
                if (self.shapes().managed(base)) break :result .{ .concrete = .i64 };
                _ = try self.arrayShape(base, node.span);
                if ((try self.requiresHandling(base))) return self.sink.fail(eResultOperation, node.span, "length would drop result-bearing elements");
                break :result .{ .concrete = .i64 };
            },
            .index => |access| result: {
                const base = try self.expression(access.base);
                if (self.shapes().managed(base)) {
                    if (self.shapes().collectionKind(base) == .dictionary) {
                        try self.compatible(try self.expression(access.index), try self.shapes().collectionKey(base, node.span), node.span);
                    } else try self.supports(try self.expression(access.index), .integer, node.span);
                    if (self.shapes().collectionKind(base) == .string) self.seedEffect(.managed_allocation);
                    break :result try self.collectionElement(base, node.span);
                }
                const shape = try self.arrayIndex(base, access.index, node.span);
                if (shape.length != 1 and (try self.requiresHandling(shape.element))) return self.sink.fail(eResultOperation, node.span, "indexing would drop other result-bearing elements");
                break :result shape.element;
            },
            .cast => |cast| result: {
                const operand = try self.expression(cast.value);
                const target = try self.ty(cast.ty);
                try self.supports(operand, .integer, node.span);
                try self.supports(target, .integer, cast.ty);
                break :result target;
            },
            // lane: tuples (item 4), conditional expression (item 6) and the
            // `mut` marker (item 1): the lanes add real support for the ones
            // that can appear in a generic body.
            .tuple => return self.sink.fail(eUnsupported, node.span, "tuple values are not supported inside generic function bodies yet"),
            .conditional => return self.sink.fail(eUnsupported, node.span, "conditional expressions are not supported inside generic function bodies yet"),
            .mut_argument => return self.sink.fail(eUnsupported, node.span, "the `mut` argument marker is not supported inside generic function bodies yet"),
        };
    }
    fn externalValue(self: *Checker, read: @FieldType(@FieldType(ast.Node, "data"), "external_read")) Error!Symbolic {
        const success: typed.Type = if (read.kind == .clock) .i64 else .u64;
        const result = try self.operationResult(read.ty, success, "E_EXTERNAL_RESULT");
        const authority: typed.Type = if (read.kind == .clock) .clock_cap else .random_cap;
        try self.compatible(try self.expression(read.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(read.capability)].span);
        self.seedEffect(read.kind.effect());
        return result;
    }
    fn byteInput(self: *Checker, input: ast.NodeId, code: []const u8) Error!void {
        const span = self.program.nodes.items[@backingInt(input)].span;
        const value_type = try self.expression(input);
        if (!provider_shapes.bytes(value_type, self.catalog.records)) return self.sink.fail(code, span, "input requires a fixed u8 array");
    }
    fn environmentValue(self: *Checker, get: @FieldType(@FieldType(ast.Node, "data"), "environment_get")) Error!Symbolic {
        const result = try self.ty(get.ty);
        if (try provider_shapes.payload(self.shapes(), result, .environment, get.ty) == null) return self.sink.fail("E_ENVIRONMENT_RESULT", get.ty, "environment result requires bytes, length and present success fields with i64 error");
        try self.compatible(try self.expression(get.capability), .{ .concrete = .environment_cap }, self.program.nodes.items[@backingInt(get.capability)].span);
        try self.byteInput(get.name, "E_ENVIRONMENT_NAME");
        self.seedEffect(.environment);
        return result;
    }
    fn acquireResource(self: *Checker, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource")) Error!Symbolic {
        const result = try self.ty(acquire.ty);
        const shape = try self.resultShape(result, acquire.ty, diagnostic.resource_result);
        const kind = provider_shapes.resource(shape.ok_type, self.catalog.records) orelse return self.sink.fail(diagnostic.resource_result, acquire.ty, "acquisition success must be a resource");
        if (!symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(diagnostic.resource_result, acquire.ty, "acquisition error must be i64");
        const authority: typed.Type = if (kind == .filesystem) .filesystem_cap else .network_cap;
        try self.compatible(try self.expression(acquire.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(acquire.capability)].span);
        const request_type = try self.expression(acquire.request);
        const owned_bytes = if (request_type == .concrete) typed.acquisitionBytes(request_type.concrete, self.catalog.records) else false;
        if (!provider_shapes.bytes(request_type, self.catalog.records) and !owned_bytes)
            return self.sink.fail("E_RESOURCE_REQUEST", self.program.nodes.items[@backingInt(acquire.request)].span, "request requires a fixed byte array or owned byte buffer");
        self.seedEffect(kind.effect());
        return result;
    }
    fn completeResource(self: *Checker, complete: @FieldType(@FieldType(ast.Node, "data"), "complete_resource")) Error!Symbolic {
        const result = try self.ty(complete.ty);
        const fields = (try provider_shapes.payload(self.shapes(), result, .completion, complete.ty)) orelse return self.sink.fail(
            "E_COMPLETION_RESULT",
            complete.ty,
            "completion requires bool success and an error record containing the resource and i64 code",
        );
        try self.compatible(try self.expression(complete.value), fields[0].?, self.program.nodes.items[@backingInt(complete.value)].span);
        self.seedEffect(provider_shapes.resource(fields[0].?, self.catalog.records).?.effect());
        return result;
    }
    fn resourceIo(self: *Checker, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io")) Error!Symbolic {
        if (io.value) |input| try self.byteInput(input, "E_RESOURCE_BYTES");
        const owner = try self.local(io.owner);
        const owner_type = try self.concreteValue(owner.ty, io.owner);
        const kind = typed.resourceKind(owner_type, self.catalog.records) orelse return self.sink.fail("E_RESOURCE_TYPE", io.owner, "I/O requires an owned resource value binding");
        try self.runtimeOwner(io.owner, true);
        const result = try self.ty(io.ty);
        if (io.kind == .write) {
            _ = try self.operationResult(io.ty, .u64, "E_RESOURCE_IO_RESULT");
        } else {
            const valid = try provider_shapes.payload(self.shapes(), result, .read, io.ty) != null;
            if (!valid) return self.sink.fail("E_RESOURCE_IO_RESULT", io.ty, "read result must contain the required bytes/length/eof fields and i64 error");
        }
        self.seedEffect(kind.effect());
        return result;
    }
    fn runtimeOwner(self: *Checker, span: source.Span, mutates: bool) Error!void {
        const binding = try self.local(span);
        if (!self.shapes().managed(binding.ty) and !binding.available) return self.sink.failTransfer(diagnostic.owned_consumed, span, binding.name, binding.transfer_span);
        if (mutates and !binding.mutable) return self.sink.fail(diagnostic.immutable, span, "mutation requires a binding it may modify");
    }
    fn operationResult(self: *Checker, span: ?source.Span, success: typed.Type, code: []const u8) Error!Symbolic {
        return self.symbolicOperationResult(span, .{ .concrete = success }, code);
    }
    fn symbolicOperationResult(self: *Checker, span: ?source.Span, success: Symbolic, code: []const u8) Error!Symbolic {
        const result_span = span orelse return success;
        const result = try self.ty(result_span);
        const shape = try self.resultShape(result, result_span, code);
        const success_matches = symbolic.same(shape.ok_type, success, self.catalog);
        if (!success_matches or !symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(code, result_span, "operation result payloads do not match its contract");
        return result;
    }
    fn bufferValue(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "buffer_operation")) Error!Symbolic {
        const owner = try self.local(operation.owner);
        if (!self.shapes().managed(owner.ty)) return self.sink.fail(eListType, operation.owner, "operation requires a managed collection value binding");
        const shape = (try self.shapes().container(owner.ty, operation.owner)) orelse return self.sink.fail(eListType, operation.owner, "operation requires a managed collection value binding");
        const element = shape.element;
        if (operation.kind == .read) try self.supports(element, .copy, operation.owner);
        for (operation.arguments, 0..) |input, index| {
            const writes_element = index == 1 and operation.kind == .write;
            const value = if (operation.kind == .append or writes_element) try self.expressionExpected(input, element) else try self.expression(input);
            const at = self.program.nodes.items[@backingInt(input)].span;
            if (operation.kind == .append or writes_element) try self.compatible(value, element, at) else try self.supports(value, .integer, at);
        }
        try self.runtimeOwner(operation.owner, false);
        if (operation.kind == .append) self.seedEffect(.managed_allocation);
        const dictionary = (self.shapes().collectionKind(owner.ty) orelse .list) == .dictionary;
        self.seedCollectionWrite(operation.kind, dictionary, self.parameterIndexAt(operation.owner));
        if (operation.kind.mutates()) return .{ .concrete = .unit };
        const success: Symbolic = if (operation.kind == .read) element else .{ .concrete = .u64 };
        return self.symbolicOperationResult(null, success, eListType);
    }
    fn resultShape(self: *Checker, value: Symbolic, span: source.Span, code: []const u8) Error!symbolic.ResultShape {
        return (try self.shapes().matchResult(value, span)) orelse self.sink.fail(code, span, "operation requires a declared result type");
    }
    fn propagateValue(self: *Checker, operand: ast.NodeId, span: source.Span) Error!Symbolic {
        const temporaries = self.temporary_results;
        const value = try self.expression(operand);
        if (try self.shapes().matchResult(value, span)) |input| {
            const output = try self.resultShape(self.result, span, eTryReturn);
            // The error converts implicitly when the enclosing union carries it
            // as a case payload, exactly as the concrete path's `typed.wrappingCase`
            // rule allows. Distinct type parameters still stay distinct.
            if (!symbolic.same(input.error_type, output.error_type, self.catalog) and
                !try self.wrappingErrorCase(output.error_type, input.error_type, span))
                try self.same(input.error_type, output.error_type, span);
            try self.requireHandled(0, span);
            if (temporaries != 0) return self.sink.fail("E_RESULT_PROPAGATION", span, "propagation could drop an already evaluated result temporary");
            return input.ok_type;
        }
        if (try self.shapes().matchOption(value, span)) |input| {
            const output = (try self.shapes().matchOption(self.result, span)) orelse return self.sink.fail(eTryReturn, span, "try requires a function returning an Option type");
            try self.same(input.element, output.element, span);
            try self.requireHandled(0, span);
            if (temporaries != 0) return self.sink.fail("E_RESULT_PROPAGATION", span, "propagation could drop an already evaluated result temporary");
            return input.element;
        }
        return self.sink.fail("E_TRY_TYPE", span, "try requires a declared result or option");
    }
    /// Whether `container` is a symbolic union that carries `payload` as one
    /// case payload: the symbolic form of the concrete path's
    /// `typed.wrappingCase`, so `?` can convert a narrower error into the
    /// enclosing union inside an uninstantiated template body.
    fn wrappingErrorCase(self: *Checker, container: Symbolic, payload: Symbolic, span: source.Span) Error!bool {
        if (container == .concrete and payload == .concrete) {
            return typed.wrappingCase(self.catalog.records, container.concrete, payload.concrete) != null;
        }
        const kind = self.shapes().kind(container) orelse return false;
        if (kind != .variants) return false;
        const shape = try self.shapes().schema(container, span);
        for (shape.fields) |field| {
            const declared = field.ty orelse continue;
            if (symbolic.same(declared, payload, self.catalog)) return true;
        }
        return false;
    }
    fn enumMember(self: *Checker, field: @FieldType(@FieldType(ast.Node, "data"), "field"), span: source.Span) Error!?Symbolic {
        const base = self.program.nodes.items[@backingInt(field.base)];
        if (base.data != .name or self.active.contains(self.src.text(base.data.name))) return null;
        if (!try variant_calls.declaresVariant(self.src, self.catalog, base.data.name, self.sink)) return null;
        const value = try self.variantValue(.{ .ty = base.data.name, .name = field.name, .value = null }, span);
        return value;
    }
    /// Resolve a variant construction's type spelling; a bare generic template name carries no
    /// arguments and adopts the expected symbolic type of its use site instead.
    fn variantType(self: *Checker, ty_span: source.Span, span: source.Span) Error!Symbolic {
        return self.variantTypeFrom(ty_span, self.expected_types.get(span));
    }
    fn variantTypeFrom(self: *Checker, ty_span: source.Span, expected: ?Symbolic) Error!Symbolic {
        const id = try variant_calls.templateDeclaration(self.src, self.catalog, ty_span, self.sink) orelse return self.ty(ty_span);
        if (expected) |value| if (value == .nominal and value.nominal.declaration == id) return value;
        return self.sink.fail("E_GENERIC_INFERENCE", ty_span, variant_calls.inference_message);
    }
    /// Lower `divtrunc(a, b)` and `remtrunc(a, b)` to their truncating integer operators.
    fn truncatingHelper(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        const name = self.src.text(invocation.name);
        const shadowed = self.active.contains(name) or self.functions.contains(name);
        const node = try truncating.lower(self.src, invocation, span, shadowed, self.sink) orelse return null;
        const value = try self.binary(node.data.binary);
        return value;
    }
    /// Lower `Type.case(value)` construction before resolving the member as a function.
    fn variantConstruction(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        const owner = invocation.owner orelse return null;
        if (invocation.type_arguments.len != 0 or self.active.contains(self.src.text(owner))) return null;
        if (!try variant_calls.namesCase(self.src, self.catalog, owner, invocation.name, self.sink)) return null;
        if (try variant_calls.caseFielded(self.src, self.catalog, owner, invocation.name, self.sink)) {
            const built = try self.variantValue(.{
                .ty = owner,
                .name = invocation.name,
                .values = invocation.arguments,
                .value_names = invocation.argument_names,
                .fielded = true,
            }, span);
            return built;
        }
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", invocation.name, "variant construction takes exactly one payload");
        const built = try self.variantValue(.{ .ty = owner, .name = invocation.name, .value = invocation.arguments[0] }, span);
        return built;
    }
    fn variantValue(self: *Checker, variant: @FieldType(@FieldType(ast.Node, "data"), "variant"), span: source.Span) Error!Symbolic {
        const result = try self.variantType(variant.ty, span);
        const shape = try self.shapes().requireVariants(result, span);
        const tag = try self.shapes().memberIndex(shape, variant.name);
        const payload = shape.fields[tag].ty;
        if (variant.fielded) {
            const field = payload orelse return self.sink.fail("E_VARIANT_PAYLOAD", span, "this case carries no payload");
            const record = try self.shapes().schema(field, span);
            if (record.kind != .record) return error.InternalError;
            try self.recordFields(field, try self.caseInitializers(record, variant.values, variant.value_names, span), true, span);
            return result;
        }
        if ((payload != null) != (variant.value != null)) return self.sink.fail("E_VARIANT_PAYLOAD", span, "construction must supply exactly the declared payload");
        if (variant.value) |value| try self.compatible(try self.expressionExpected(value, payload.?), payload.?, span);
        return result;
    }
    /// Bind a parenthesized case's positional and named field arguments to the
    /// payload record's declared fields, filling every omitted default.
    // twin-drift-ok: the concrete checker resolves field identity through the type
    // catalog while this symbolic checker resolves it through the function-local
    // shape arena; the binding rules themselves are identical.
    fn caseInitializers(self: *Checker, record: symbolic.Schema, values: []const ast.NodeId, names: []const ?source.Span, span: source.Span) Error![]const ast.FieldInit {
        if (values.len > record.fields.len) return self.sink.fail("E_ARITY", span, "too many field arguments for this variant case");
        var initializers: std.ArrayList(ast.FieldInit) = .empty;
        const supplied = try self.allocator.alloc(bool, record.fields.len);
        defer self.allocator.free(supplied);
        @memset(supplied, false);
        for (values, 0..) |value, source_index| {
            const keyword = if (names.len == 0) null else names[source_index];
            const index = if (keyword) |name| try self.shapes().memberIndex(record, name) else source_index;
            if (supplied[index]) return self.sink.fail("E_DUPLICATE_FIELD", keyword orelse span, "field is initialized more than once");
            supplied[index] = true;
            try initializers.append(self.allocator, .{ .name = if (keyword) |name| name else record.fields[index].span, .value = value });
        }
        for (record.fields, 0..) |field, index| {
            if (supplied[index]) continue;
            const default = field.default_value orelse continue;
            try initializers.append(self.allocator, .{ .name = field.span, .value = @fromBackingInt(default), .default = true });
        }
        return initializers.toOwnedSlice(self.allocator);
    }
    fn patternTag(self: *Checker, value: Symbolic, variants: symbolic.Schema, type_span: source.Span, name: source.Span) Error!usize {
        if (type_span.start != type_span.end) {
            try self.same(try self.variantTypeFrom(type_span, value), value, type_span);
            return self.shapes().memberIndex(variants, name);
        }
        const canonical = @import("prelude.zig").caseName(self.src.text(name));
        for (variants.fields, 0..) |candidate, index| if (std.mem.eql(u8, candidate.name, canonical)) return index;
        return self.sink.fail("E_UNKNOWN_VARIANT", name, "case is not a variant of the matched type");
    }
    fn matchValue(self: *Checker, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), span: source.Span) Error!bool {
        for (match.arms) |arm| try self.invalidateOptions(arm.body);
        const match_facts = try self.option_facts.snapshot(self.field_arena.allocator());
        defer self.option_facts.restore(match_facts);
        const value = try self.rawOptionExpression(match.value);
        const variants = try self.shapes().requireVariants(value, span);
        const seen = try self.allocator.alloc(bool, variants.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const incoming = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(incoming);
        var continuation: ?[]Pending = null;
        defer if (continuation) |state| self.allocator.free(state);
        var terminated = true;
        for (match.arms) |arm| {
            self.option_facts.restore(match_facts);
            self.restorePending(incoming);
            const tag = try self.patternTag(value, variants, arm.ty, arm.name);
            if (seen[tag]) return self.sink.fail("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm");
            seen[tag] = true;
            const payload = variants.fields[tag].ty;
            const before = self.locals.items.len;
            defer self.endScope(before);
            if (payload != null and variants.fields[tag].fielded) {
                const shape = try self.shapes().schema(payload.?, arm.name);
                if (arm.bindings.len != shape.fields.len) return self.sink.fail("E_PATTERN_PAYLOAD", arm.name, "a named-field case pattern binds exactly one name per field, using `_` to discard one");
                var all_discard = true;
                for (arm.bindings) |binding| if (binding != null) {
                    all_discard = false;
                    break;
                };
                if (all_discard) {
                    if (try self.requiresHandling(payload.?)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires explicit handling");
                } else for (arm.bindings, shape.fields) |binding, field| {
                    const field_type = field.ty orelse return error.InternalError;
                    if (binding) |at| {
                        try self.bind(at, field_type, false);
                    } else if (try self.requiresHandling(field_type)) return self.sink.fail(eResultDiscard, arm.name, "discarding a result-bearing field requires a binding and explicit handling");
                }
            } else {
                const discards_payload = arm.bindings.len == 1 and arm.bindings[0] == null;
                if (discards_payload and payload != null and (try self.requiresHandling(payload.?))) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires explicit handling");
                if (arm.bindings.len > 1 or (payload != null) != (arm.bindings.len == 1)) return self.sink.fail("E_PATTERN_PAYLOAD", arm.name, "payload cases require a binding or discard; empty cases take neither");
                if (arm.bindings.len == 1) if (arm.bindings[0]) |binding| try self.bind(binding, payload.?, false);
            }
            const returns = try self.statement(arm.body);
            if (!returns) {
                try self.requireHandled(before, arm.name);
                if (continuation) |state| try self.samePending(state, span, eResultPath) else continuation = try self.pendingState(incoming.len);
            }
            terminated = terminated and returns;
        }
        for (seen) |present| if (!present) return self.sink.fail("E_INCOMPLETE_MATCH", span, "match must cover every declared case");
        if (continuation) |state| self.restorePending(state);
        return terminated;
    }
    fn arrayIndex(self: *Checker, base: Symbolic, input: ast.NodeId, span: source.Span) Error!symbolic.Array {
        const shape = try self.arrayShape(base, span);
        const index = try self.expression(input);
        if (shape.key) |key| try self.compatible(index, .{ .concrete = key }, span) else try self.supports(index, .integer, span);
        return shape;
    }
    fn recordValue(self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record"), span: source.Span) Error!Symbolic {
        const result = try self.ty(record.name);
        try self.recordFields(result, record.fields, true, span);
        if (self.shapes().managed(result)) self.seedEffect(.managed_allocation);
        return result;
    }
    fn recordFields(self: *Checker, ty_value: Symbolic, fields: []const ast.FieldInit, complete: bool, span: source.Span) Error!void {
        const shape = try self.shapes().requireRecord(ty_value, span, complete);
        const table_key = shape.key;
        const seen = try self.allocator.alloc(bool, shape.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        for (fields) |field| {
            const index = try self.shapes().memberIndex(shape, field.name);
            if (seen[index]) return self.sink.fail(if (table_key != null) "E_DUPLICATE_KEY" else "E_DUPLICATE_FIELD", field.name, "named entry is initialized more than once");
            seen[index] = true;
            if (!complete and (try self.requiresHandling(shape.fields[index].ty.?))) return self.sink.fail(eResultOperation, field.name, "update would drop a result-bearing field");
            try self.compatible(try self.expressionExpected(field.value, shape.fields[index].ty.?), shape.fields[index].ty.?, field.name);
        }
        if (complete) for (seen) |present| {
            if (!present) return self.sink.fail(if (table_key != null) "E_INCOMPLETE_TABLE" else "E_MISSING_FIELD", span, "named construction must initialize every entry");
        };
    }
    fn binary(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!Symbolic {
        const left = try self.expression(operation.left);
        const short_circuit = operation.op == .logical_and or operation.op == .logical_or;
        const state = if (short_circuit) try self.pendingState(self.locals.items.len) else null;
        defer if (state) |snapshot| self.allocator.free(snapshot);
        const facts = if (short_circuit) try self.option_facts.snapshot(self.field_arena.allocator()) else null;
        defer if (facts) |saved| self.option_facts.restore(saved);
        if (short_circuit) try self.assumeOption(operation.left, operation.op == .logical_and);
        const right = try self.expression(operation.right);
        if (state) |snapshot| try self.samePending(snapshot, operation.op_span, eResultPath);
        if (self.isFloat(left) or self.isFloat(right) or operation.op == .python_div) {
            if (!self.isFloat(left)) try self.supports(left, .integer, operation.op_span);
            if (!self.isFloat(right)) try self.supports(right, .integer, operation.op_span);
            return switch (operation.op) {
                .add, .sub, .mul, .div, .python_div, .floor_div, .floor_rem => self.floatType(),
                .eq, .ne, .lt, .le, .gt, .ge => .{ .concrete = .bool },
                else => self.sink.fail("E_FLOAT_OPERATION", operation.op_span, "float supports arithmetic and numeric comparison"),
            };
        }
        try self.compatible(right, left, operation.op_span);
        if (self.shapes().managed(left)) {
            if (operation.op == .eq or operation.op == .ne) return .{ .concrete = .bool };
            if (operation.op == .add and self.shapes().collectionKind(left) == .string) {
                self.seedEffect(.managed_allocation);
                return left;
            }
            return self.sink.fail("E_TEXT_OPERATOR", operation.op_span, "collection supports equality and str supports concatenation");
        }
        switch (operation.op) {
            .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_eq, .f64_lt, .f64_le => try self.compatible(left, .{ .concrete = .u64 }, operation.op_span),
            .logical_and, .logical_or => try self.compatible(left, .{ .concrete = .bool }, operation.op_span),
            .eq, .ne => try self.supports(left, .equality, operation.op_span),
            else => try self.supports(left, .integer, operation.op_span),
        }
        return switch (operation.op) {
            .f64_add,
            .f64_sub,
            .f64_mul,
            .f64_div,
            .add,
            .sub,
            .mul,
            .div,
            .rem,
            .floor_div,
            .floor_rem,
            .bit_and,
            .bit_or,
            .bit_xor,
            .shift_left,
            .shift_right,
            .wrapping_add,
            .wrapping_sub,
            .wrapping_mul,
            .saturating_add,
            .saturating_sub,
            .saturating_mul,
            => left,
            else => .{ .concrete = .bool },
        };
    }
    fn block(self: *Checker, statements: []const ast.StatementId) Error!bool {
        const before = self.locals.items.len;
        defer self.endScope(before);
        var terminated = false;
        for (statements) |id| {
            if (terminated) return self.sink.fail("E_UNREACHABLE", self.program.statements.items[@backingInt(id)].span, "statement follows an unconditional return");
            terminated = try self.statement(id);
        }
        if (!terminated and statements.len != 0) try self.requireHandled(before, self.program.statements.items[@backingInt(statements[statements.len - 1])].span);
        return terminated;
    }
    /// Read the original optional binding for a tag test or explicit match.
    fn rawOptionExpression(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const node = self.program.nodes.items[@backingInt(id)];
        if (node.data == .name) if (self.active.get(self.src.text(node.data.name))) |slot| {
            return self.expressionExpected(id, self.locals.items[slot].ty);
        };
        return self.expression(id);
    }
    /// Derive facts along one edge using the same rules as the concrete checker.
    fn assumeOption(self: *Checker, condition: ast.NodeId, truth: bool) Error!void {
        try self.option_facts.assume(self.field_arena.allocator(), .{ .program = self.program, .src = self.src }, .{ .symbolic = &self.active }, .{ .condition = condition, .truth = truth });
    }
    /// Invalidate loop-carried assignments before checking a symbolic iteration.
    fn invalidateOptions(self: *Checker, body: ast.StatementId) Error!void {
        try self.option_facts.invalidateWrites(self.field_arena.allocator(), .{ .program = self.program, .src = self.src }, .{ .symbolic = &self.active }, body);
    }
    fn branchValue(self: *Checker, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), span: source.Span) Error!bool {
        try self.compatible(try self.expression(branch.condition), .{ .concrete = .bool }, span);
        const before = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(before);
        const facts_before = try self.option_facts.snapshot(self.field_arena.allocator());
        try self.assumeOption(branch.condition, true);
        const left = try self.statement(branch.then_body);
        const facts_after = try self.option_facts.snapshot(self.field_arena.allocator());
        const after = try self.pendingState(before.len);
        defer self.allocator.free(after);
        self.restorePending(before);
        self.option_facts.restore(facts_before);
        try self.assumeOption(branch.condition, false);
        const right = if (branch.else_body) |other| try self.statement(other) else false;
        if (!left) {
            if (right) self.option_facts.restore(facts_after) else self.option_facts.intersect(facts_after);
        }
        if (!left) {
            if (!right) try self.samePending(after, span, eResultPath);
            self.restorePending(after);
        }
        return left and right;
    }
    fn statement(self: *Checker, id: ast.StatementId) Error!bool {
        const statement_value = self.program.statements.items[@backingInt(id)];
        try self.enter(statement_value.span);
        defer self.depth -= 1;
        switch (statement_value.data) {
            .block => |statements| return self.block(statements),
            .with_scope => return self.sink.fail(eUnsupported, statement_value.span, "`with` resource scopes are not supported inside generic function bodies"),
            .match => |match| return self.matchValue(match, statement_value.span),
            .ret => |value| {
                try self.returnValue(value, statement_value.span);
                return true;
            },
            .assertion => |claim| {
                const condition = try self.expression(claim.condition);
                try self.compatible(condition, .{ .concrete = .bool }, statement_value.span);
            },
            .binding => |binding| {
                const value = if (binding.annotation) |annotation| try self.expressionExpected(binding.value, try self.ty(annotation)) else try self.expression(binding.value);
                if (binding.annotation) |annotation| try self.compatible(value, try self.ty(annotation), annotation);
                try self.bind(binding.name, value, binding.mutable);
            },
            .assignment => |assignment| {
                if (assignment.op == .set and !self.active.contains(self.src.text(assignment.name))) {
                    const value = try self.expression(assignment.value);
                    try self.bind(assignment.name, value, true);
                    return false;
                }
                const target = try self.local(assignment.name);
                if (!target.mutable) return self.sink.fail(diagnostic.immutable, assignment.name, "assignment requires a mutable binding");
                const value = try self.expressionExpected(assignment.value, target.ty);
                try self.compatible(value, target.ty, assignment.op_span);
                if (assignment.op != .set) try self.augmentedTarget(assignment.op, target.ty, assignment.op_span);
                if ((try self.transfers(target.ty))) {
                    if ((try self.pendingObligation(target.*))) return self.sink.fail("E_RESULT_OVERWRITE", assignment.name, "assignment would overwrite an unhandled result");
                    target.available = true;
                    target.transfer_span = null;
                }
                self.option_facts.forget(self.active.get(self.src.text(assignment.name)).?);
            },
            // `_ = expr` evaluates the value and releases it, settling a result obligation.
            .discard => |value| {
                const ty_value = try self.expression(value);
                if (statement_value.implicit_discard and !symbolic.same(ty_value, .{ .concrete = .unit }, self.catalog)) return self.sink.fail(
                    "E_EXPLICIT_DISCARD_REQUIRED",
                    statement_value.span,
                    "a standalone non-unit value requires `_ =` or result handling",
                );
                if (ty_value == .parameter) try self.supports(ty_value, .storable, statement_value.span);
            },
            .branch => |branch| return self.branchValue(branch, statement_value.span),
            .for_each => |each| {
                try self.invalidateOptions(each.body);
                const loop_facts = try self.option_facts.snapshot(self.field_arena.allocator());
                defer self.option_facts.restore(loop_facts);
                const source_type = try self.expression(each.iterable);
                const view = dictionary_views.symbolicKind(self.catalog, source_type);
                const projected = view != null and view.? != .item;
                const owner = if (projected) try dictionary_views.symbolicOwner(self.shapes(), source_type, statement_value.span) else source_type;
                if (!self.shapes().managed(owner)) return self.sink.fail(eListType, statement_value.span, "iteration requires a collection or dictionary view");
                const element = try self.iterationElement(source_type, owner, statement_value.span);
                const first = self.locals.items.len;
                if (each.index_name != null and !each.enumerated) {
                    if (dictionary_views.symbolicKind(self.catalog, element) != .item) return self.sink.fail("E_ITERATION", statement_value.span, "two iteration names require dictionary items, enumerate or zip");
                    const shape = try self.shapes().schema(element, statement_value.span);
                    try self.bind(each.index_name.?, shape.fields[0].ty.?, false);
                    try self.bind(each.name, shape.fields[1].ty.?, false);
                } else {
                    try self.bind(each.name, element, false);
                    if (each.index_name) |name| try self.bind(name, .{ .concrete = .i64 }, false);
                }
                defer self.endScope(first);
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                const previous = self.loop_pending;
                self.loop_pending = before;
                defer self.loop_pending = previous;
                if (!try self.statement(each.body)) try self.samePending(before, statement_value.span, diagnostic.result_loop);
                self.restorePending(before);
            },
            .for_range => |range| {
                try self.invalidateOptions(range.body);
                const loop_facts = try self.option_facts.snapshot(self.field_arena.allocator());
                defer self.option_facts.restore(loop_facts);
                const element: Symbolic = if (self.program.nodes.items[@backingInt(range.start)].data == .unit) .{ .concrete = .i64 } else try self.expression(range.start);
                try self.supports(element, .integer, range.name);
                try self.compatible(try self.expression(range.end), element, range.name);
                const first = self.locals.items.len;
                try self.bind(range.name, element, false);
                defer self.endScope(first);
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                const previous = self.loop_pending;
                self.loop_pending = before;
                defer self.loop_pending = previous;
                if (!try self.statement(range.body)) try self.samePending(before, statement_value.span, diagnostic.result_loop);
                self.restorePending(before);
            },
            .loop_exit => {
                const before = self.loop_pending orelse return self.sink.fail("E_LOOP_EXIT", statement_value.span, "break and continue require an enclosing loop");
                try self.requireHandled(before.len, statement_value.span);
                try self.samePending(before, statement_value.span, diagnostic.result_loop);
                return true;
            },
            .loop => |loop| {
                try self.invalidateOptions(loop.body);
                const loop_facts = try self.option_facts.snapshot(self.field_arena.allocator());
                defer self.option_facts.restore(loop_facts);
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                try self.compatible(try self.expression(loop.condition), .{ .concrete = .bool }, statement_value.span);
                try self.samePending(before, statement_value.span, diagnostic.result_loop);
                const previous = self.loop_pending;
                self.loop_pending = before;
                defer self.loop_pending = previous;
                try self.assumeOption(loop.condition, true);
                if (!try self.statement(loop.body)) try self.samePending(before, statement_value.span, diagnostic.result_loop);
                self.restorePending(before);
            },
        }
        return false;
    }
};
fn supportsSet(value: Symbolic, required: requirements.Set, parameters: []const requirements.Parameter, catalog: Catalog) bool {
    inline for (std.meta.tags(requirements.Requirement)) |requirement| {
        if (required.contains(requirement) and !symbolic.supports(value, requirement, parameters, catalog)) return false;
    }
    return true;
}
/// Direct abstract facts and worklists one replayed function writes into.
const DirectMasks = struct { effects: []effect_set.Mask, mutations: []u16, writes: []bool };
const ReplayState = struct {
    allocator: std.mem.Allocator,
    sink: *diagnostic.Sink,
    masks: DirectMasks,
    effect_calls: *std.ArrayList(effects.AbstractCall),
    pending: *std.ArrayList(usize),
    scheduled: []bool,
};
/// Apply one retained direct result and schedule its recorded callees. The
/// replayed caller/scheduke order is the stored discovery order, so a warm pass
/// visits dependencies in the same order as a cold pass.
fn applyReplay(state: ReplayState, index: usize, replay: generic_cache.Replay) error{OutOfMemory}!void {
    defer state.allocator.free(replay.notes);
    defer state.allocator.free(replay.edges);
    state.masks.effects[index] = replay.effect_mask;
    state.masks.mutations[index] = replay.mutation_mask;
    state.masks.writes[index] = replay.mutation_writes;
    for (replay.notes) |note| try appendReplayedDiagnostic(state.sink, note);
    for (replay.edges) |edge| {
        try state.effect_calls.append(state.allocator, edge);
        if (!state.scheduled[edge.callee]) {
            state.scheduled[edge.callee] = true;
            state.pending.appendAssumeCapacity(edge.callee);
        }
    }
}

/// Immutable inputs one template check resolves against.
const TemplateCheck = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    program: ast.Program,
    sink: *diagnostic.Sink,
    module_names: ?*Names,
    catalog: Catalog,
};
/// One template's resolved declaration bounds and normalized requirements.
const ResolvedTemplate = struct {
    raw: []const requirements.Parameter,
    parameters: []const requirements.Parameter,
    fn deinit(self: ResolvedTemplate, allocator: std.mem.Allocator) void {
        requirements.deinitResolved(allocator, self.raw);
        requirements.deinitResolved(allocator, self.parameters);
    }
};
/// Resolve one template's scoped constraints. A bound failure reports through
/// the shared sink and returns null so the caller marks the whole pass failed.
fn resolveTemplate(context: TemplateCheck, function: ast.Function) Error!?ResolvedTemplate {
    const allocator = context.allocator;
    var provider: constraint_lookup.Provider = .{ .program = context.program, .src = context.src, .names = context.module_names };
    const raw = requirements.resolveBounds(allocator, context.src, function.signature.type_parameters, context.sink, provider.lookup()) catch |err| switch (err) {
        error.SourceError => return null,
        else => return err,
    };
    const parameters = @import("symbolic_shapes.zig").normalizeRequirements(allocator, context.catalog, context.src, raw, context.sink) catch |err| switch (err) {
        error.SourceError => {
            requirements.deinitResolved(allocator, raw);
            return null;
        },
        else => {
            requirements.deinitResolved(allocator, raw);
            return err;
        },
    };
    return .{ .raw = raw, .parameters = parameters };
}
/// Count a rejected abstract check without branching in the hot loop.
fn noteSymbolicFailure(symbolic_session: ?*generic_cache.Session, index: usize) void {
    if (symbolic_session) |reuse| reuse.noteFailed(index);
}

/// Run one fresh abstract body check; a source rejection is a `false` result.
fn runFresh(checker: *Checker, function: ast.Function) Error!bool {
    checker.checkFunction(function) catch |err| switch (err) {
        error.SourceError => return false,
        else => return err,
    };
    return true;
}

/// Validate supported template bodies symbolically; unsupported forms remain explicit errors.
pub fn check(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) Error!void {
    return checkWithNames(allocator, src, program, sink, null);
}
/// Validate bodies while preserving the declaring module's names and import aliases.
pub fn checkWithNames(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!void {
    const catalog = try @import("records.zig").collectWithNames(sink.allocator, src, program, sink, module_names);
    return checkWithCatalog(allocator, src, program, sink, catalog);
}
/// Check symbolic bodies against the same concrete type catalog used by specialization.
pub fn checkWithCatalog(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, catalog: Catalog) Error!void {
    return checkWithCatalogCached(allocator, src, program, sink, catalog, null);
}
/// Check symbolic bodies, reusing unchanged direct results from `symbolic`.
/// The whole-graph `effects.checkAbstract` pass always runs from the combined
/// fresh and replayed masks, so a changed callee body is re-derived even when a
/// caller's own direct result is reusable.
pub fn checkWithCatalogCached(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, catalog: Catalog, symbolic_session: ?*generic_cache.Session) Error!void {
    const module_names = catalog.module_names;
    var has_work = program.types.constraints.len != 0;
    for (program.functions) |function| if (function.signature.type_parameters.len != 0) {
        has_work = true;
        break;
    };
    if (!has_work) return;
    const cleanup_masks = try effects.cleanupMasks(allocator, catalog.records);
    defer allocator.free(cleanup_masks);
    const effect_masks = try allocator.alloc(effect_set.Mask, program.functions.len);
    defer allocator.free(effect_masks);
    @memset(effect_masks, 0);
    const mutation_masks = try allocator.alloc(u16, program.functions.len);
    defer allocator.free(mutation_masks);
    @memset(mutation_masks, 0);
    const mutation_write_masks = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(mutation_write_masks);
    @memset(mutation_write_masks, false);
    var effect_calls: std.ArrayList(effects.AbstractCall) = .empty;
    defer effect_calls.deinit(allocator);
    var functions: FunctionMap = .empty;
    defer functions.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        const key = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try @import("function_identity.zig").localName(sink.allocator, src, function.policy.owner, function.name);
        const entry = try functions.getOrPut(allocator, key);
        if (entry.found_existing) return sink.fail("E_DUPLICATE_FUNCTION", function.name, "duplicate function declaration");
        entry.value_ptr.* = index;
    }
    const scheduled = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(scheduled);
    @memset(scheduled, false);
    var pending = try std.ArrayList(usize).initCapacity(allocator, program.functions.len);
    defer pending.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        if (function.signature.type_parameters.len == 0) continue;
        scheduled[index] = true;
        pending.appendAssumeCapacity(index);
    }
    var failed = false;
    var cursor: usize = 0;
    while (cursor < pending.items.len) : (cursor += 1) {
        const index = pending.items[cursor];
        const function = program.functions[index];
        if (function.policy.host != null) continue;
        const resolved = try resolveTemplate(.{
            .allocator = allocator,
            .src = src,
            .program = program,
            .sink = sink,
            .module_names = module_names,
            .catalog = catalog,
        }, function) orelse {
            failed = true;
            noteSymbolicFailure(symbolic_session, index);
            continue;
        };
        defer resolved.deinit(allocator);
        var checker: Checker = .{
            .allocator = allocator,
            .field_arena = std.heap.ArenaAllocator.init(allocator),
            .src = src,
            .program = program,
            .catalog = catalog,
            .cleanup_masks = cleanup_masks,
            .effect_masks = effect_masks,
            .mutation_masks = mutation_masks,
            .mutation_write_masks = mutation_write_masks,
            .effect_calls = &effect_calls,
            .function_index = index,
            .sink = sink,
            .parameters = resolved.parameters,
            .result = undefined,
            .module_names = module_names,
            .functions = &functions,
            .pending = &pending,
            .scheduled = scheduled,
            .owner = function.policy.owner,
        };
        defer checker.field_arena.deinit();
        defer checker.locals.deinit(allocator);
        defer checker.active.deinit(allocator);
        defer checker.expected_types.deinit(allocator);
        // Boundary validation is fresh work even on a retained hit: a malformed
        // bound or structural requirement must reject exactly as a cold check.
        checker.validateStructural() catch |err| switch (err) {
            error.SourceError => {
                failed = true;
                noteSymbolicFailure(symbolic_session, index);
                continue;
            },
            else => return err,
        };
        if (symbolic_session) |reuse| if (try reuse.lookup(allocator, index)) |replay| {
            try applyReplay(.{
                .allocator = allocator,
                .sink = sink,
                .masks = .{ .effects = effect_masks, .mutations = mutation_masks, .writes = mutation_write_masks },
                .effect_calls = &effect_calls,
                .pending = &pending,
                .scheduled = scheduled,
            }, index, replay);
            continue;
        };
        const diag_start = sink.items.items.len;
        const edge_start = effect_calls.items.len;
        if (!try runFresh(&checker, function)) {
            failed = true;
            noteSymbolicFailure(symbolic_session, index);
            continue;
        }
        if (symbolic_session) |reuse| {
            _ = try reuse.record(index, .{
                .effect_mask = effect_masks[index],
                .mutation_mask = mutation_masks[index],
                .mutation_writes = mutation_write_masks[index],
                .notes = sink.items.items[diag_start..],
                .edges = effect_calls.items[edge_start..],
            });
        }
    }
    for (program.types.constraints) |*constraint| {
        var provider: constraint_lookup.Provider = .{ .program = program, .src = src, .names = module_names };
        const parameters = requirements.resolveBounds(allocator, src, &.{constraint.subject}, sink, provider.lookup()) catch |err| switch (err) {
            error.SourceError => {
                failed = true;
                continue;
            },
            else => return err,
        };
        defer requirements.deinitResolved(allocator, parameters);
        var checker: Checker = .{
            .allocator = allocator,
            .field_arena = std.heap.ArenaAllocator.init(allocator),
            .src = src,
            .program = program,
            .catalog = catalog,
            .cleanup_masks = cleanup_masks,
            .effect_masks = effect_masks,
            .mutation_masks = mutation_masks,
            .mutation_write_masks = mutation_write_masks,
            .effect_calls = &effect_calls,
            .function_index = 0,
            .sink = sink,
            .parameters = parameters,
            .result = undefined,
            .module_names = module_names,
            .functions = &functions,
            .pending = &pending,
            .scheduled = scheduled,
            .owner = null,
        };
        defer checker.field_arena.deinit();
        defer checker.locals.deinit(allocator);
        defer checker.active.deinit(allocator);
        defer checker.expected_types.deinit(allocator);
        checker.validateStructural() catch |err| switch (err) {
            error.SourceError => failed = true,
            else => return err,
        };
    }
    if (failed) return error.SourceError;
    // E2: generic templates are checked abstractly, so their missing exported
    // ceilings are reported here from the abstract inferred mask.
    const exported = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(exported);
    for (program.functions, 0..) |function, index| {
        exported[index] = if (module_names) |names| names.index.functionExported(names.src, function.name) else false;
    }
    for (program.functions, 0..) |function, index| {
        const mask = mutation_masks[index];
        var inferred_mutates: std.ArrayList(u16) = .empty;
        var bit: u5 = 0;
        while (bit < 16) : (bit += 1) {
            if (mask & (@as(u16, 1) << @intCast(bit)) != 0) try inferred_mutates.append(allocator, bit);
        }
        const mutable = @constCast(&program.functions[index]);
        mutable.signature.inferred_mutates = try inferred_mutates.toOwnedSlice(allocator);
        mutable.signature.inferred_mutation_writes = function.signature.inferred_mutation_writes or mask != 0 or mutation_write_masks[index];
    }
    try effects.checkAbstract(allocator, program.functions, effect_masks, effect_calls.items, exported, sink);
    // Publish only after the whole abstract graph passed. A rejected request
    // keeps its fresh direct results private to this session and frees them at
    // `deinit`; the durable store never inherits a pass that failed.
    if (symbolic_session) |reuse| try reuse.publish();
}

/// Append one replayed diagnostic, copying its text into the sink's allocator
/// so the collected diagnostic never borrows a retained cache arena.
fn appendReplayedDiagnostic(sink: *diagnostic.Sink, note: diagnostic.Diagnostic) error{OutOfMemory}!void {
    var copy = note;
    copy.code = try sink.allocator.dupe(u8, note.code);
    copy.message = try sink.allocator.dupe(u8, note.message);
    if (note.related) |related| copy.related = .{ .span = related.span, .message = try sink.allocator.dupe(u8, related.message) };
    if (note.provenance.origin) |related| copy.provenance.origin = .{ .span = related.span, .message = try sink.allocator.dupe(u8, related.message) };
    if (note.provenance.requirement) |related| copy.provenance.requirement = .{ .span = related.span, .message = try sink.allocator.dupe(u8, related.message) };
    try sink.items.append(sink.allocator, copy);
}
