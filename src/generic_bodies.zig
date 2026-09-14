//! Symbolic template checking preserves types, ownership and effects without representative substitution.
const call_arguments = @import("call_arguments.zig");
const eResultDiscard = diagnostic.result_discard;
const std = @import("std");
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
const Names = @import("module_names.zig").Names;
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
const Symbolic = symbolic.Value;
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
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
    effect_calls: *std.ArrayList(effects.AbstractCall),
    function_index: usize,
    sink: *diagnostic.Sink,
    parameters: []const requirements.Parameter,
    result: Symbolic,
    expected_types: std.AutoHashMapUnmanaged(source.Span, Symbolic) = .empty,
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
            if (parameter.default_value) |value| try self.same(try self.expressionExpected(value, parameter_type), parameter_type, parameter.ty);
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
        for (self.parameters, 0..) |parameter, index| if (std.mem.eql(u8, text, self.src.text(parameter.name))) {
            if (parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "const length parameters are values, not types");
            return .{ .parameter = index };
        };
        return self.concreteType(span);
    }
    fn callbackType(self: *Checker, syntax: ast.CallbackType, parameters: []const Symbolic, result: Symbolic) Error!Symbolic {
        const signature = try self.field_arena.allocator().create(symbolic.Callback);
        signature.* = .{ .parameters = parameters, .result = result, .effects = syntax.effect_bound.allowed };
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
            if (try constants.lookup(span)) |index| return .{ .concrete = (try constants.evaluate(index)).typeOf() };
        }
        const binding = try self.local(span);
        if ((try self.transfers(binding.ty))) {
            if (!binding.available) return self.sink.failTransfer(if ((try self.moveOnly(binding.ty))) diagnostic.owned_consumed else "E_RESULT_CONSUMED", span, binding.name, binding.transfer_span);
            binding.available = false;
            binding.transfer_span = span;
        }
        return binding.ty;
    }
    fn endScope(self: *Checker, before: usize) void {
        for (self.locals.items[before..]) |item| _ = self.active.remove(self.src.text(item.name));
        self.locals.shrinkRetainingCapacity(before);
    }
    fn returnValue(self: *Checker, value: ast.NodeId, span: source.Span) Error!void {
        try self.same(try self.expressionExpected(value, self.result), self.result, span);
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
        const index = self.functions.get(key) orelse return self.sink.fail("E_UNKNOWN_FUNCTION", invocation.name, "no function has this qualified name");
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
        for (parameters, arguments) |parameter, argument| {
            if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) {
                if (!parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "expected a constant parameter");
                return argument;
            }
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
        for (parameters, arguments) |parameter, argument| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return argument;
        return self.concreteType(span);
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
            try self.same(try self.expression(input), parameter, invocation.name);
        }
        self.effect_masks[self.function_index] |= contract.effects;
        return contract.result;
    }
    fn collectionElement(self: *Checker, owner: Symbolic, span: source.Span) Error!Symbolic {
        if (!self.shapes().managed(owner)) return self.sink.fail(eListType, span, "operation requires a managed list");
        if (self.shapes().collectionKind(owner) == .string) return owner;
        return (try self.shapes().container(owner, span)).?.element;
    }
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
        const expected = try self.expression(assignment.target);
        try self.same(try self.expressionExpected(assignment.value, expected), expected, node.span);
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
            try self.same(try self.expressionExpected(input, target), target, node.span);
        }
        self.seedEffect(.managed_allocation);
        return expected.?;
    }
    /// Build a fixed array from a list literal whose context already demands `[N]T`.
    fn fixedArrayLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, expected: Symbolic) Error!Symbolic {
        const shape = try self.arrayShape(expected, node.span);
        if (shape.length_parameter != null) return self.sink.fail(diagnostic.generic_length, node.span, "array literal construction requires a fixed length in an uncalled template");
        if (inputs.len != shape.length) return self.sink.fail("E_ARRAY_LENGTH", node.span, "list literal length differs from the expected fixed array");
        for (inputs) |input| try self.same(try self.expressionExpected(input, shape.element), shape.element, node.span);
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
        if (each.filter) |condition| try self.same(try self.expression(condition), .{ .concrete = .bool }, span);
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
        try self.same(try self.expression(bounds.end), element, span);
        return element;
    }

    /// Every f-string piece converts to text, so the whole literal is `str`.
    fn formatValue(self: *Checker, parts: []const ast.NodeId, span: source.Span) Error!Symbolic {
        const str_type: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
        for (parts) |part| {
            const value = try self.expression(part);
            if (symbolic.same(value, str_type, self.catalog)) continue;
            if (self.isFloat(value)) continue;
            try self.supports(value, .integer, span);
        }
        self.seedEffect(.managed_allocation);
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
            if (element) |ty_value| try self.same(value, ty_value, node.span) else element = value;
        }
        try self.supports(element.?, .copy, node.span);
        try self.supports(element.?, .storable, node.span);
        if (try self.requiresHandling(element.?)) return self.sink.fail(eResultOperation, node.span, "list elements cannot contain pending results");
        if (expected == null) expected = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{element.?});
        self.seedEffect(.managed_allocation);
        return expected.?;
    }
    fn collectionOperation(self: *Checker, owner: Symbolic, operation: struct { kind: BufferKind, inputs: []const ast.NodeId, span: source.Span }) Error!Symbolic {
        const family = self.shapes().collectionKind(owner) orelse return self.sink.fail(eListType, operation.span, "operation requires a managed collection");
        const element = try self.collectionElement(owner, operation.span);
        const key = if (family == .dictionary) try self.shapes().collectionKey(owner, operation.span) else element;
        const kind = operation.kind;
        if (operation.inputs.len != kind.arity()) return self.sink.fail("E_ARITY", operation.span, "collection argument count differs from its signature");
        const output: Symbolic = switch (kind) {
            .strip, .lstrip, .rstrip, .upper, .lower, .replace, .zfill => owner,
            .is_digit, .is_alpha, .is_space => .{ .concrete = .bool },
            .count => .{ .concrete = .i64 },
            .length => .{ .concrete = if (family == .list) typed.Type.u64 else .i64 },
            .read, .get => element,
            .contains => .{ .concrete = .bool },
            .append, .write => .{ .concrete = .unit },
            .keys, .values, .split => try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{if (kind == .keys) key else if (kind == .split) owner else element}),
            .join => owner,
            else => return self.sink.fail(eUnsupported, operation.span, "unsupported collection operation in generic body"),
        };
        if (family == .string and (kind == .write or kind == .append or kind == .get)) return self.sink.fail("E_TEXT_IMMUTABLE", operation.span, "strings are immutable");
        if (family != .string and (kind == .split or kind == .join)) return self.sink.fail(eListType, operation.span, "split and join require str");
        if (family != .dictionary and (kind == .keys or kind == .values or kind == .get)) return self.sink.fail(eListType, operation.span, "mapping operation requires a dictionary");
        for (operation.inputs, 0..) |input, index| {
            const integer = family != .dictionary and index == 0 and (kind == .read or kind == .write);
            const expected = if (family == .dictionary) (if (index == 0) key else element) else if (kind == .join) try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{owner}) else element;
            if (integer) try self.supports(try self.expression(input), .integer, operation.span) else try self.same(try self.expressionExpected(input, expected), expected, operation.span);
        }
        if (buffer_operations.managedAllocation(kind, family == .dictionary) or (family == .string and kind == .read)) self.seedEffect(.managed_allocation);
        return output;
    }
    fn listOperation(self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "list_operation")) Error!Symbolic {
        return self.collectionOperation(try self.expression(operation.base), .{ .kind = operation.kind, .inputs = operation.arguments, .span = node.span });
    }
    fn listMethod(self: *Checker, node: ast.Node) Error!Symbolic {
        const method = node.data.method_call;
        const name = self.src.text(method.name);
        if (std.mem.eql(u8, name, "push")) return self.sink.fail("E_REMOVED_SPELLING", method.name, "`push` was removed; use `append(value)`");
        const kind = buffer_operations.method(name) orelse return self.sink.fail("E_LIST_METHOD", method.name, "unknown collection method");
        return self.listOperation(node, .{ .base = method.base, .kind = kind, .arguments = method.arguments });
    }
    /// Check `values[index] op= value` in a generic body against the element's own rules.
    fn indexAssignment(self: *Checker, node: ast.Node) Error!Symbolic {
        const assignment = node.data.index_assignment;
        const target = self.program.nodes.items[@backingInt(assignment.target)];
        const expected = try self.expression(assignment.target);
        try self.augmentedTarget(assignment.op, expected, node.span);
        try self.same(try self.expressionExpected(assignment.value, expected), expected, node.span);
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
            if (self.shapes().managed(self.locals.items[slot].ty)) {
                const kind = buffer_operations.method(self.src.text(input_call.name)) orelse return self.sink.fail("E_LIST_METHOD", input_call.name, "unknown collection method");
                if (input_call.type_arguments.len != 0) return self.sink.fail("E_ARITY", span, "collection methods do not take explicit type arguments");
                const result = try self.collectionOperation(self.locals.items[slot].ty, .{ .kind = kind, .inputs = input_call.arguments, .span = span });
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
        try self.same(try self.expressionExpected(invocation.arguments[0], element), element, span);
        return expected;
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
        try self.same(try self.expressionExpected(invocation.arguments[0], payload), payload, span);
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
    fn specialCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (try self.textConstructor(input_call, span)) |value| return value;
        if (std.mem.eql(u8, self.src.text(input_call.name), "todo") and input_call.owner == null) {
            _ = try self.ty(input_call.type_arguments[0]);
            return self.sink.typedHole(input_call.name, input_call.type_arguments[0]);
        }
        if (try self.truncatingHelper(input_call, span)) |value| return value;
        if (try self.variantConstruction(input_call, span)) |value| return value;
        if (try self.managedMethod(input_call, span)) |value| return value;
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
    fn call(self: *Checker, input_call: Call, span: source.Span) Error!Symbolic {
        if (try self.specialCall(input_call, span)) |value| {
            try call_arguments.positional(input_call, self.sink);
            return value;
        }
        const resolved = try self.resolveCall(input_call);
        const function = try self.callTarget(resolved, input_call.name);
        const signature = function.signature;
        const invocation = try call_arguments.bind(self.field_arena.allocator(), self.src, resolved, signature.parameters, self.sink);
        if (function.policy.conversion) return self.sink.fail(eUnsupported, span, "generic conversions still need abstract checking");
        if (invocation.type_arguments.len != 0 and invocation.type_arguments.len != signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (invocation.arguments.len != signature.parameters.len) return self.sink.fail("E_ARITY", span, "argument count does not match function parameters");
        const required = try requirements.resolve(self.allocator, self.src, signature.type_parameters, self.sink);
        defer self.allocator.free(required);
        const arguments = try self.allocator.alloc(Symbolic, required.len);
        defer self.allocator.free(arguments);
        const inferred = invocation.type_arguments.len == 0 and required.len != 0;
        const actuals = if (inferred) try self.inferCall(invocation, signature, arguments) else null;
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
            try self.same(if (actuals) |values| values[input_index] else try self.expressionExpected(input, expected), expected, node.span);
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
    fn inferCall(self: *Checker, invocation: Call, signature: @FieldType(ast.Function, "signature"), arguments: []Symbolic) Error![]Symbolic {
        var inference: @import("generic_inference.zig").Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = invocation.name };
        const actuals = try self.allocator.alloc(Symbolic, invocation.arguments.len);
        errdefer self.allocator.free(actuals);
        for (0..invocation.arguments.len) |source_index| {
            const position = call_arguments.parameterPosition(invocation, source_index);
            const input = invocation.arguments[position];
            const parameter = signature.parameters[position];
            const actual = &actuals[position];
            actual.* = try self.expression(input);
            try inference.match(parameter.ty, actual.*);
        }
        try inference.finish(arguments);
        return actuals;
    }
    fn operationCall(self: *Checker, invocation: Call) Error!?Symbolic {
        const owner = invocation.owner orelse return null;
        var contract: ?ast.Operation = null;
        var symbolic_owner = false;
        for (self.parameters) |parameter| if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(owner))) {
            symbolic_owner = true;
            for (parameter.operation_requirements) |operation| if (std.mem.eql(u8, self.src.text(operation.name), self.src.text(invocation.name))) {
                contract = operation;
                break;
            };
        };
        if (!symbolic_owner) return null;
        const operation = contract orelse return self.sink.fail("E_GENERIC_REQUIREMENT", invocation.name, "type parameter does not declare this operation");
        if (invocation.type_arguments.len != 0 or invocation.arguments.len != operation.parameters.len)
            return self.sink.fail("E_ARITY", invocation.name, "structural operation requires its declared value/reference arguments and no type arguments");
        for (invocation.arguments, operation.parameters) |input, parameter| {
            const expected = try self.ty(parameter.ty);
            const node = self.program.nodes.items[@backingInt(input)];
            try self.same(try self.expression(input), expected, node.span);
        }
        self.effect_masks[self.function_index] |= operation.effect_bound.allowed;
        const result = try self.ty(operation.return_type);
        return result;
    }
    fn structural(self: *Checker, argument: Symbolic, required: requirements.Parameter, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!void {
        if (required.field_requirements.len != 0) {
            const shape = try self.shapes().requireRecord(argument, required.name, false);
            for (required.field_requirements) |field| {
                const index = try self.shapes().memberIndex(shape, field.name);
                try self.same(shape.fields[index].ty.?, try self.substituted(field.ty, parameters, arguments), field.name);
            }
        }
        for (required.operation_requirements) |operation| {
            var actual: ?ast.Operation = null;
            var concrete = false;
            switch (argument) {
                .parameter => |index| for (self.parameters[index].operation_requirements) |provided| {
                    if (std.mem.eql(u8, self.src.text(provided.name), self.src.text(operation.name))) {
                        actual = provided;
                        break;
                    }
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
                const actual_type = if (concrete) try self.concreteType(input.ty) else try self.ty(input.ty);
                try self.same(actual_type, try self.substituted(expected.ty, parameters, arguments), expected.name);
            }
            const result = if (concrete) try self.concreteType(provided.return_type) else try self.ty(provided.return_type);
            try self.same(result, try self.substituted(operation.return_type, parameters, arguments), operation.name);
        }
    }
    fn validateStructural(self: *Checker) Error!void {
        for (self.parameters) |parameter| {
            for (parameter.field_requirements) |field| {
                if (try self.transfers(try self.ty(field.ty))) return self.sink.fail("E_GENERIC_REQUIREMENT", field.ty, "structural fields require a copyable field type without result obligations");
            }
            for (parameter.operation_requirements) |operation| {
                _ = try self.ty(operation.return_type);
                for (operation.parameters) |input| _ = try self.ty(input.ty);
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
                try self.same(operand, try self.domainBacking(target, node.span), node.span);
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
                try self.same(needle, expected, node.span);
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
                const child = self.program.nodes.items[@backingInt(unary.operand)];
                const operand: Symbolic = if (unary.op == .neg and child.data == .integer)
                    try self.numericLiteral(child.data.integer, true)
                else
                    try self.expression(unary.operand);
                if (unary.op == .neg) {
                    if (!self.isFloat(operand)) try self.supports(operand, .integer, unary.op_span);
                } else try self.same(operand, .{ .concrete = if (unary.op == .not) .bool else .u64 }, unary.op_span);
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
                try self.same(try self.expression(replacement.value), shape.element, node.span);
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
                if (self.shapes().managed(base)) break :result .{ .concrete = .i64 };
                _ = try self.arrayShape(base, node.span);
                if ((try self.requiresHandling(base))) return self.sink.fail(eResultOperation, node.span, "length would drop result-bearing elements");
                break :result .{ .concrete = .u64 };
            },
            .index => |access| result: {
                const base = try self.expression(access.base);
                if (self.shapes().managed(base)) {
                    if (self.shapes().collectionKind(base) == .dictionary) {
                        try self.same(try self.expression(access.index), try self.shapes().collectionKey(base, node.span), node.span);
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
        };
    }
    fn externalValue(self: *Checker, read: @FieldType(@FieldType(ast.Node, "data"), "external_read")) Error!Symbolic {
        const success: typed.Type = if (read.kind == .clock) .i64 else .u64;
        const result = try self.operationResult(read.ty, success, "E_EXTERNAL_RESULT");
        const authority: typed.Type = if (read.kind == .clock) .clock_cap else .random_cap;
        try self.same(try self.expression(read.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(read.capability)].span);
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
        try self.same(try self.expression(get.capability), .{ .concrete = .environment_cap }, self.program.nodes.items[@backingInt(get.capability)].span);
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
        try self.same(try self.expression(acquire.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(acquire.capability)].span);
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
        try self.same(try self.expression(complete.value), fields[0].?, self.program.nodes.items[@backingInt(complete.value)].span);
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
            if (operation.kind == .append or writes_element) try self.same(value, element, at) else try self.supports(value, .integer, at);
        }
        try self.runtimeOwner(operation.owner, false);
        if (operation.kind == .append) self.seedEffect(.managed_allocation);
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
        const input = try self.resultShape(value, span, "E_TRY_TYPE");
        const output = try self.resultShape(self.result, span, eTryReturn);
        try self.same(input.error_type, output.error_type, span);
        try self.requireHandled(0, span);
        if (temporaries != 0) return self.sink.fail("E_RESULT_PROPAGATION", span, "propagation could drop an already evaluated result temporary");
        return input.ok_type;
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
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", invocation.name, "variant construction takes exactly one payload");
        const built = try self.variantValue(.{ .ty = owner, .name = invocation.name, .value = invocation.arguments[0] }, span);
        return built;
    }
    fn variantValue(self: *Checker, variant: @FieldType(@FieldType(ast.Node, "data"), "variant"), span: source.Span) Error!Symbolic {
        const result = try self.variantType(variant.ty, span);
        const shape = try self.shapes().requireVariants(result, span);
        const tag = try self.shapes().memberIndex(shape, variant.name);
        const payload = shape.fields[tag].ty;
        if ((payload != null) != (variant.value != null)) return self.sink.fail("E_VARIANT_PAYLOAD", span, "construction must supply exactly the declared payload");
        if (variant.value) |value| try self.same(try self.expressionExpected(value, payload.?), payload.?, span);
        return result;
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
        const value = try self.expression(match.value);
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
            self.restorePending(incoming);
            const tag = try self.patternTag(value, variants, arm.ty, arm.name);
            if (seen[tag]) return self.sink.fail("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm");
            seen[tag] = true;
            const payload = variants.fields[tag].ty;
            if (arm.discard_payload and payload != null and (try self.requiresHandling(payload.?))) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires explicit handling");
            if ((payload != null) != (arm.binding != null or arm.discard_payload)) return self.sink.fail("E_PATTERN_PAYLOAD", arm.name, "payload cases require a binding or discard; empty cases take neither");
            const before = self.locals.items.len;
            defer self.endScope(before);
            if (arm.binding) |binding| try self.bind(binding, payload.?, false);
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
        if (shape.key) |key| try self.same(index, .{ .concrete = key }, span) else try self.supports(index, .integer, span);
        return shape;
    }
    fn recordValue(self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record"), span: source.Span) Error!Symbolic {
        const result = try self.ty(record.name);
        try self.recordFields(result, record.fields, true, span);
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
            try self.same(try self.expressionExpected(field.value, shape.fields[index].ty.?), shape.fields[index].ty.?, field.name);
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
        try self.same(right, left, operation.op_span);
        if (self.shapes().managed(left)) {
            if (operation.op == .eq or operation.op == .ne) return .{ .concrete = .bool };
            if (operation.op == .add and self.shapes().collectionKind(left) == .string) {
                self.seedEffect(.managed_allocation);
                return left;
            }
            return self.sink.fail("E_TEXT_OPERATOR", operation.op_span, "collection supports equality and str supports concatenation");
        }
        switch (operation.op) {
            .f64_add, .f64_sub, .f64_mul, .f64_div, .f64_eq, .f64_lt, .f64_le => try self.same(left, .{ .concrete = .u64 }, operation.op_span),
            .logical_and, .logical_or => try self.same(left, .{ .concrete = .bool }, operation.op_span),
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
    fn branchValue(self: *Checker, branch: @FieldType(@FieldType(ast.Statement, "data"), "branch"), span: source.Span) Error!bool {
        try self.same(try self.expression(branch.condition), .{ .concrete = .bool }, span);
        const before = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(before);
        const left = try self.statement(branch.then_body);
        const after = try self.pendingState(before.len);
        defer self.allocator.free(after);
        self.restorePending(before);
        const right = if (branch.else_body) |other| try self.statement(other) else false;
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
                try self.same(condition, .{ .concrete = .bool }, statement_value.span);
            },
            .binding => |binding| {
                const value = if (binding.annotation) |annotation| try self.expressionExpected(binding.value, try self.ty(annotation)) else try self.expression(binding.value);
                if (binding.annotation) |annotation| try self.same(value, try self.ty(annotation), annotation);
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
                try self.same(value, target.ty, assignment.op_span);
                if (assignment.op != .set) try self.augmentedTarget(assignment.op, target.ty, assignment.op_span);
                if ((try self.transfers(target.ty))) {
                    if ((try self.pendingObligation(target.*))) return self.sink.fail("E_RESULT_OVERWRITE", assignment.name, "assignment would overwrite an unhandled result");
                    target.available = true;
                    target.transfer_span = null;
                }
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
                const owner = try self.expression(each.iterable);
                if (!self.shapes().managed(owner)) return self.sink.fail(eListType, statement_value.span, "iteration requires a list");
                const shape = if (self.shapes().collectionKind(owner) == .dictionary) try self.shapes().collectionKey(owner, statement_value.span) else try self.collectionElement(owner, statement_value.span);
                const first = self.locals.items.len;
                try self.bind(each.name, shape, false);
                if (each.index_name) |name| try self.bind(name, .{ .concrete = .i64 }, false);
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
                const element: Symbolic = if (self.program.nodes.items[@backingInt(range.start)].data == .unit) .{ .concrete = .i64 } else try self.expression(range.start);
                try self.supports(element, .integer, range.name);
                try self.same(try self.expression(range.end), element, range.name);
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
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                try self.same(try self.expression(loop.condition), .{ .concrete = .bool }, statement_value.span);
                try self.samePending(before, statement_value.span, diagnostic.result_loop);
                const previous = self.loop_pending;
                self.loop_pending = before;
                defer self.loop_pending = previous;
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
    const module_names = catalog.module_names;
    var has_generic = false;
    for (program.functions) |function| if (function.signature.type_parameters.len != 0) {
        has_generic = true;
        break;
    };
    if (!has_generic) return;
    const cleanup_masks = try effects.cleanupMasks(allocator, catalog.records);
    defer allocator.free(cleanup_masks);
    const effect_masks = try allocator.alloc(effect_set.Mask, program.functions.len);
    defer allocator.free(effect_masks);
    @memset(effect_masks, 0);
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
        const function = program.functions[pending.items[cursor]];
        if (function.policy.host != null) continue;
        const parameters = requirements.resolve(allocator, src, function.signature.type_parameters, sink) catch |err| switch (err) {
            error.SourceError => {
                failed = true;
                continue;
            },
            else => return err,
        };
        defer allocator.free(parameters);
        var checker: Checker = .{
            .allocator = allocator,
            .field_arena = std.heap.ArenaAllocator.init(allocator),
            .src = src,
            .program = program,
            .catalog = catalog,
            .cleanup_masks = cleanup_masks,
            .effect_masks = effect_masks,
            .effect_calls = &effect_calls,
            .function_index = pending.items[cursor],
            .sink = sink,
            .parameters = parameters,
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
        checker.checkFunction(function) catch |err| switch (err) {
            error.SourceError => failed = true,
            else => return err,
        };
    }
    if (failed) return error.SourceError;
    try effects.checkAbstract(allocator, program.functions, effect_masks, effect_calls.items, sink);
}
