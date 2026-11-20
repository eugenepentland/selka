//! Symbolic template checking preserves types, writability and Result obligations without representative substitution.
const repetition = @import("repetition.zig");
const call_arguments = @import("call_arguments.zig");
const scalar_text_helpers = @import("scalar_text_helpers.zig");
const embed = @import("embed.zig");
const eResultDiscard = diagnostic.result_discard;
const fixed_array_name = "FixedArray";
const ePatternPayload = diagnostic.pattern_payload;
const eMatchYield = "E_MATCH_YIELD";
const eResourceType = diagnostic.resource_type;
const std = @import("std");
const frontend_patterns = @import("frontend_patterns.zig");
const pattern_alternatives = @import("pattern_alternatives.zig");
const sema_statements = @import("sema_statements.zig");
const variant_is = @import("variant_is.zig");
const bind_or_else = @import("bind_or_else.zig");
const case_payload = @import("case_payload.zig");
const option_flow = @import("option_flow.zig");
const dictionary_views = @import("dictionary_views.zig");
const negative_index = @import("negative_index.zig");
const numeric_surface = @import("numeric_surface.zig");
const set_lower = @import("set_lower.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const float_syntax = @import("float_syntax.zig");
const float_intrinsics = @import("float_intrinsics.zig");
const integer_literal = @import("integer_literal.zig");
const buffer_operations = @import("buffer_operations.zig");
const retired_methods = @import("retired_methods.zig");
const contains_removed = @import("contains_removed.zig");
const import_fix = @import("import_fix.zig");
const borrow_view_fix = @import("borrow_view_fix.zig");
const BufferKind = buffer_operations.Kind;
const ast = @import("ast.zig");
const unreachable_repair = @import("unreachable_repair.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const format_strings = @import("format_strings.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const Error = diagnostic.Error;
const names_module = @import("module_names.zig");
const Names = names_module.Names;
const constraint_lookup = @import("constraint_lookup.zig");
const variant_calls = @import("variant_calls.zig");
const arrays = @import("array_literals.zig");
const truncating = @import("truncating_math.zig");
const eShadowing = diagnostic.shadowing;
const eResultOperation = diagnostic.result_operation;
const eResultPath = diagnostic.result_path;
const eTryReturn = "E_TRY_RETURN";
const eListMethod = "E_LIST_METHOD";
const eCollectionMethod = @import("sema_shared.zig").eCollectionMethod;
/// The rejection of a method a set does not answer inside a template body.
const unknown_set_method = "unknown set method; sets answer add, remove, discard, pop, clear, copy, update, union, intersection, difference, " ++
    "symmetric_difference, issubset, issuperset and isdisjoint";
const eArgument = diagnostic.generic_argument;
const eListType = @import("collection_lower.zig").list_type_error;
const eUnsupported = "E_GENERIC_BODY_UNSUPPORTED";
/// The marker a call that writes its receiver needs at the call site.
const mutation_marker_code = @import("origins.zig").mutation_marker_code;
/// The one message a lambda written inside a generic function body reports,
/// from the template checker and from the unchecked lambda alike, so the two
/// merge into a single diagnostic.
pub const lambda_in_generic_body = "a lambda is not supported inside a generic function body; declare a top-level function and pass it by name";
/// A misplaced or unknown call operand, the concrete checker's code for it.
const eCallArgument = "E_CALL_ARGUMENT";
const eTupleArity = diagnostic.tuple_arity;
/// The accepted arity beside a rejected tuple in a template body.
const tuple_arity_message = symbolic_shapes.tuple_arity_message;
const Catalog = @import("records.zig").Catalog;
const symbolic = @import("symbolic_types.zig");
const symbolic_shapes = @import("symbolic_shapes.zig");
const provider_shapes = @import("symbolic_providers.zig");
const generic_cache = @import("generic_cache.zig");
const option_spelling = @import("option_spelling.zig");
const copy_method = @import("copy_method.zig");
const bit_operators = @import("bit_operators.zig");
const Symbolic = symbolic.Value;
const Call = @FieldType(@FieldType(ast.Node, "data"), "call");
const function_same = @import("function_same.zig");
const function_digest = @import("function_digest.zig");
const enum_cases = @import("enum_cases.zig");
const collection_text = @import("collection_text.zig");
const unknown_method = "unknown collection method";
/// Whether a call on a named receiver is a list's `sort` with operands, the
/// Python keyword form whose operands are named rather than positional.
fn keywordSort(self: anytype, input_call: Call) bool {
    if (input_call.arguments.len == 0 or !std.mem.eql(u8, self.src.text(input_call.name), "sort")) return false;
    // The prelude spelling `sort(mut values, key=…)` names its keywords too, so
    // a call with more than its receiver is the keyword form in either spelling.
    if (input_call.owner == null) return input_call.arguments.len > 1;
    return true;
}
const scopedDirectoryPath = @import("scoped_directory.zig").valid;
const FunctionMap = std.StringHashMapUnmanaged(usize);

const Pending = struct { available: bool = true, transfer_span: ?source.Span = null, initialized: bool = true, maybe_initialized: bool = false };
const LoopInitialization = struct { before: []const Pending, exits: ?[]Pending = null };
const Local = struct {
    internal_name: ?[]const u8 = null,
    name: source.Span,
    ty: Symbolic,
    mutable: bool,
    caller_writeback: bool = false,
    ownership: Pending = .{},
};
/// One comprehension a template body is checking: what it builds, the context's
/// expected result, and the element (and key) its step produced.
const GatherFrame = struct { shape: ast.GatherShape, expected: ?Symbolic = null, value: ?Symbolic = null, key: ?Symbolic = null };
/// A `try` or `fail value` converting an error into the enclosing union: what a refusal names.
const Conversion = struct { form: @FieldType(@import("frontend_failures.zig").Ambiguous, "form"), span: source.Span, value: ?source.Span = null };
const Checker = struct {
    allocator: std.mem.Allocator,
    field_arena: std.heap.ArenaAllocator,
    src: source.Source,
    program: ast.Program,
    view_consumers: dictionary_views.Consumers,
    catalog: Catalog,
    calls: *std.ArrayList(generic_cache.Call),
    function_index: usize,
    sink: *diagnostic.Sink,
    parameters: []const requirements.Parameter,
    requirement_aliases: []const requirements.SubjectAlias = &.{},
    result: Symbolic,
    match_yield: ?struct { value: ?Symbolic } = null,
    exclusive_match: bool = false,
    expected_types: std.AutoHashMapUnmanaged(source.Span, Symbolic) = .empty,
    option_facts: option_flow.State = .{},
    functions: *const FunctionMap,
    owner: ?source.Span = null,
    module_names: ?*Names = null,
    locals: std.ArrayList(Local) = .empty,
    active: std.StringHashMapUnmanaged(usize) = .empty,
    depth: usize = 0,
    work: usize = 0,
    expression_depth: usize = 0,
    temporary_results: usize = 0,
    loop_pending: ?*LoopInitialization = null,
    /// Factual source-expression types, captured before concrete substitution.
    type_dependence: ?*std.ArrayList(source.Span) = null,
    original_nodes: usize = 0,
    /// Nested syntax payloads outlive the shared private tables' body checks.
    pattern_memory: ?std.mem.Allocator = null,
    /// The comprehensions being checked, innermost last (`PY-GATHER-1`).
    gather_frames: std.ArrayList(GatherFrame) = .empty,
    fn topLevel(self: *Checker, span: source.Span) Error!bool {
        if (self.module_names) |names| return names.topLevel(span);
        const text = self.src.text(span);
        return self.functions.contains(text) or self.catalog.names.contains(text) or self.catalog.templates.names.contains(text);
    }
    /// Whether binding `name` in a new scope would hide an active binding or a
    /// top-level declaration; `_` is the discard name and never does (`DISCARD-NAME-1`).
    fn shadows(self: *Checker, name: source.Span) Error!bool {
        const text = self.src.text(name);
        if (std.mem.eql(u8, text, "_")) return false;
        const top_level = try self.topLevel(name);
        return top_level or self.active.contains(text);
    }
    /// End a scoped binding of `text`, restoring the `_` binding it hid, if any.
    fn unbindScoped(self: *Checker, text: []const u8, hidden: ?usize) void {
        if (hidden) |slot| {
            self.active.getPtr(text).?.* = slot;
        } else _ = self.active.remove(text);
    }
    fn checkFunction(self: *Checker, function: ast.Function) Error!void {
        const sink = self.sink;
        try ast.ensureBody(self.program, function.body);
        if (function.policy.conversion) return sink.fail(eUnsupported, function.name, "generic conversions still need abstract checking");
        for (self.parameters) |parameter| if (try self.topLevel(parameter.name)) return sink.fail(eShadowing, parameter.name, "type parameter shadows a top-level declaration or import");
        try self.validateStructural();
        const success = try self.ty(function.signature.return_type);
        self.result = if (function.signature.failure_type) |failure| try self.resultType(success, try self.ty(failure), function.name) else success;
        for (function.signature.parameters) |parameter| {
            const parameter_type = try self.ty(parameter.ty);
            if (parameter.default_value) |value| try self.compatible(try self.expressionExpected(value, parameter_type), parameter_type, parameter.ty);
            try self.bindMode(parameter.name, parameter_type, (parameter.mut or parameter.own) and function.policy.host == null);
            self.locals.items[self.locals.items.len - 1].caller_writeback = parameter.mut and function.policy.host == null and self.shapes().collectionKind(parameter_type) == .list;
        }
        const implicit_unit = symbolic.same(success, .{ .concrete = .unit }, self.catalog);
        // A generic `builtin func` has no body to judge: every call of it is the compiler's operation (W10).
        if (function.policy.builtin) return;
        const terminates = try self.statement(function.body);
        if (!terminates and !implicit_unit) return sink.fail("E_MISSING_RETURN", function.name, "template may fall through without returning its declared type");
        if (!terminates) try self.requireHandled(0, function.name);
    }
    fn shapes(self: *Checker) symbolic_shapes.Context {
        return .{
            .arena = &self.field_arena,
            .catalog = self.catalog,
            .src = self.src,
            .sink = self.sink,
            .parameters = self.parameters,
            .work = &self.work,
        };
    }
    fn properties(self: *Checker, value: Symbolic) Error!symbolic.Properties {
        const span = if (self.function_index < self.program.functions.len)
            self.program.functions[self.function_index].name
        else switch (value) {
            .nominal => |nominal| self.catalog.templates.store.?.index.declarations.items[nominal.declaration].name,
            .parameter => |index| self.parameters[index].name,
            else => source.Span{ .start = 0, .end = 0 },
        };
        return self.shapes().properties(value, span);
    }
    fn enter(self: *Checker, span: source.Span) Error!void {
        if (self.depth == 256 or self.work == 100000) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic body exceeds checking depth/work budget");
        self.depth += 1;
        self.work += 1;
    }
    fn resultType(self: *Checker, success: Symbolic, failure: Symbolic, span: source.Span) Error!Symbolic {
        _ = span;
        return self.shapes().nominal(self.catalog.templates.store.?.index.names.get("Result").?, &.{ success, failure });
    }
    fn ty(self: *Checker, span: source.Span) Error!Symbolic {
        if (self.catalog.templates.store) |store| if (store.index.syntax.suffixes.get(span)) |suffix| {
            try self.enter(span);
            defer self.depth -= 1;
            return self.shapes().nominal(self.catalog.templates.store.?.index.names.get(if (suffix.kind == .growable) "list" else "Option").?, &.{try self.ty(suffix.base)});
        };
        for (self.program.types.expressions.callbacks) |callback| if (callback.span.start == span.start) {
            try self.enter(span);
            defer self.depth -= 1;
            const parameters = try self.field_arena.allocator().alloc(Symbolic, callback.parameters.len);
            for (callback.parameters, parameters) |input, *out| out.* = try self.ty(input);
            return self.callbackType(callback, parameters, if (callback.failure_type) |failure| try self.resultType(try self.ty(callback.return_type), try self.ty(failure), span) else try self.ty(callback.return_type));
        };
        if (self.catalog.templates.store) |store| if (store.index.syntax.applications.get(span.start)) |syntax| {
            if (syntax.span.end == span.end) return self.sourceApplication(syntax);
        };
        if (self.catalog.templates.applications.get(span.start)) |template| if (template.syntax.span.end == span.end) {
            try self.enter(span);
            defer self.depth -= 1;
            var arguments: [16]Symbolic = undefined;
            const required = self.catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
            for (template.syntax.arguments, required, 0..) |argument, parameter, i| arguments[i] = if (parameter.constant_length) try self.lengthType(argument) else try self.ty(argument);
            return self.shapes().nominal(template.declaration, arguments[0..template.arguments.len]);
        };
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            try self.enter(span);
            defer self.depth -= 1;
            const length: Symbolic = if (template.length_parameter) |at| try self.lengthType(at) else .{ .length = template.length };
            return self.arrayWithLength(length, try self.ty(template.syntax.element), span);
        }
        if (self.catalog.templates.store) |store| if (store.index.syntax.tuples.get(span.start)) |syntax| {
            try self.enter(span);
            defer self.depth -= 1;
            const elements = try self.field_arena.allocator().alloc(Symbolic, syntax.elements.len);
            for (syntax.elements, elements) |element, *out| out.* = try self.ty(element);
            return self.symbolicTuple(elements, span);
        };
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
    fn sourceApplication(self: *Checker, syntax: ast.TypeApplication) Error!Symbolic {
        const store = self.catalog.templates.store.?;
        if (std.mem.eql(u8, self.src.text(syntax.name), fixed_array_name)) {
            if (syntax.arguments.len != 2) return self.sink.fail(diagnostic.generic_arity, syntax.span, "FixedArray needs an element type and a constant length");
            return self.arrayWithLength(try self.lengthType(syntax.arguments[1]), try self.ty(syntax.arguments[0]), syntax.span);
        }
        const type_expression = try store.index.expression(syntax.span, self.parameters);
        if (type_expression != .application) return error.InternalError;
        const template = type_expression.application;
        const required = store.index.declarations.items[template.declaration].parameters;
        const arguments = try self.field_arena.allocator().alloc(Symbolic, required.len);
        for (syntax.arguments, required, arguments) |argument, parameter, *out| {
            out.* = if (parameter.constant_length) try self.lengthType(argument) else try self.ty(argument);
        }
        return self.shapes().nominal(template.declaration, arguments);
    }
    fn substitutedApplication(self: *Checker, syntax: ast.TypeApplication, parameters: []const ast.TypeParameter, arguments: []const Symbolic) Error!Symbolic {
        const store = self.catalog.templates.store.?;
        if (std.mem.eql(u8, self.src.text(syntax.name), fixed_array_name)) {
            if (syntax.arguments.len != 2) return self.sink.fail(diagnostic.generic_arity, syntax.span, "FixedArray needs an element type and a constant length");
            const length = try self.substitutedLength(syntax.arguments[1], parameters, arguments);
            return self.arrayWithLength(length, try self.substituted(syntax.arguments[0], parameters, arguments), syntax.span);
        }
        const resolved = try requirements.resolve(self.field_arena.allocator(), self.src, parameters, self.sink);
        const type_expression = try store.index.expression(syntax.span, resolved);
        if (type_expression != .application) return error.InternalError;
        const template = type_expression.application;
        const required = store.index.declarations.items[template.declaration].parameters;
        const values = try self.field_arena.allocator().alloc(Symbolic, required.len);
        for (syntax.arguments, required, values) |argument, parameter, *out| {
            out.* = if (parameter.constant_length) try self.substitutedLength(argument, parameters, arguments) else try self.substituted(argument, parameters, arguments);
        }
        return self.shapes().nominal(template.declaration, values);
    }
    fn callbackType(self: *Checker, syntax: ast.CallbackType, parameters: []const Symbolic, result: Symbolic) Error!Symbolic {
        const signature = try self.field_arena.allocator().create(symbolic.Callback);
        signature.* = .{
            .parameters = parameters,
            .result = result,
            .labels = try @import("callables.zig").syntaxLabels(self.field_arena.allocator(), self.src, syntax),
            .mutates = try ast.mutPositions(self.field_arena.allocator(), syntax.parameter_modes.mut),
            .return_origin = .fresh,
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
    fn transfers(self: *Checker, value: Symbolic) Error!bool {
        const flags = try self.properties(value);
        return flags.move_only or flags.requires_handling;
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
    fn pendingObligation(self: *Checker, binding: Local) Error!bool {
        return binding.ownership.initialized and binding.ownership.available and try self.requiresHandling(binding.ty);
    }
    /// Whether a binding holds a concrete `@linear` type (D-FFI-11).
    fn linearBinding(self: *Checker, binding: Local) bool {
        return binding.ty == .concrete and typed.linear(binding.ty.concrete, self.catalog.records);
    }
    fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
        return self.requireHandledAt(first, span, .scope);
    }
    /// `requireHandled` for a path that leaves at `exit`: a `try` that propagates names the `on fail:` clause that ends a live `@linear` owner.
    fn requireHandledAt(self: *Checker, first: usize, span: source.Span, exit: @import("linear_rules.zig").Exit) Error!void {
        for (self.locals.items[first..]) |binding| {
            if (!binding.caller_writeback and self.linearBinding(binding) and (try self.pendingObligation(binding)))
                return @import("linear_rules.zig").unconsumed(self.sink, self.allocator, .{ .name = self.src.text(binding.name), .declaration = binding.name, .end = span, .exit = exit });
            if (!binding.caller_writeback and (try self.pendingObligation(binding)))
                return self.sink.failResultUnhandled(self.src.text(binding.name), binding.name, span);
        }
    }
    fn pendingState(self: *Checker, count: usize) Error![]Pending {
        const state = try self.allocator.alloc(Pending, count);
        for (self.locals.items[0..count], state) |binding, *pending| pending.* = binding.ownership;
        return state;
    }
    fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*binding, pending| {
            binding.ownership = pending;
        }
    }
    fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |binding, pending| {
            if (!try self.requiresHandling(binding.ty)) continue;
            const available = binding.ownership.initialized and binding.ownership.available;
            const before = pending.initialized and pending.available;
            if (available != before and self.linearBinding(binding))
                return @import("linear_rules.zig").refuse(self.sink, span, if (std.mem.eql(u8, code, diagnostic.result_loop)) .loop else .paths);
            if (available != before) return self.sink.failOwnershipRelated(
                .{ .code = code, .rule = .L1 },
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
        if (try self.shapes().matchOption(expected, span)) |option| return self.compatible(actual, option.element, span);
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
        // GENERIC-LAMBDA-1: a lambda is one synthesized function with one
        // callback type, so it cannot follow a template body's type parameters
        // into each specialization. Say so instead of failing its name lookup.
        // The parser names a lambda by its `lambda` keyword; the diagnostic
        // covers the whole lambda, as the unchecked lambda's own report does.
        for (self.program.lambdas) |lambda| if (lambda.span.start == span.start)
            return self.sink.fail("E_LAMBDA_REMOVED", lambda.span, lambda_in_generic_body);
        const index = self.active.get(self.src.text(span)) orelse return self.sink.fail("E_UNKNOWN_NAME", span, "name is not defined in this template scope");
        try self.requireInitialized(self.locals.items[index], span);
        return &self.locals.items[index];
    }
    fn requireInitialized(self: *Checker, binding: Local, span: source.Span) Error!void {
        if (!binding.ownership.initialized) return self.sink.failRelated(
            "E_UNBOUND",
            span,
            "name may be read before it is assigned; some control-flow path reaching here leaves it unbound",
            .{ .span = binding.name, .message = "binding declared here" },
        );
    }
    fn intersectInitialization(self: *Checker, state: []Pending) void {
        for (self.locals.items[0..state.len], state) |binding, *pending| {
            pending.maybe_initialized = pending.initialized or pending.maybe_initialized or binding.ownership.initialized or binding.ownership.maybe_initialized;
            pending.initialized = pending.initialized and binding.ownership.initialized;
        }
    }
    /// A deferred const declared outside the loop cannot initialize twice.
    fn requireConstLoopState(self: *Checker, span: source.Span) Error!void {
        const before = self.loop_pending.?.before;
        for (self.locals.items[0..before.len], before) |binding, old| {
            if (binding.mutable or old.initialized or old.maybe_initialized) continue;
            if (!binding.ownership.initialized and !binding.ownership.maybe_initialized) continue;
            return self.sink.failOwnershipRelated(
                .{ .code = diagnostic.immutable, .rule = .B1 },
                span,
                "const assignment reaches a loop backedge and may execute more than once",
                .{ .span = binding.name, .message = "const binding declared outside this loop" },
            );
        }
    }
    fn finishLoopInitialization(self: *Checker, zero_iterations: bool) void {
        const loop = self.loop_pending.?;
        self.restorePending(loop.before);
        if (loop.exits) |exits| {
            if (zero_iterations) self.intersectInitialization(exits);
            self.restorePending(exits);
        }
    }
    fn syntheticValue(self: *Checker, name: []const u8, span: source.Span) Error!Symbolic {
        const binding = &self.locals.items[self.active.get(name) orelse return error.InternalError];
        try self.requireInitialized(binding.*, span);
        if (try self.requiresHandling(binding.ty)) {
            if (!binding.ownership.available) return self.sink.failOwnership(.{ .code = "E_RESULT_CONSUMED", .rule = .L1 }, span, "pattern value was already transferred");
            binding.ownership.available = false;
            binding.ownership.transfer_span = span;
        }
        return binding.ty;
    }
    fn namedValue(self: *Checker, span: source.Span) Error!Symbolic {
        for (self.parameters) |parameter| {
            if (parameter.constant_length and std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) return .{ .concrete = .u64 };
        }
        if (!self.active.contains(self.src.text(span))) {
            const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.program, .names = self.module_names, .sink = self.sink, .catalog = self.catalog };
            if (try constants.lookup(span)) |index| {
                if (try constants.literalType(index)) |ty_value| {
                    return .{ .concrete = ty_value };
                }
                return .{ .concrete = (try constants.evaluate(index)).typeOf() };
            }
        }
        const binding = try self.local(span);
        try self.requireInitialized(binding.*, span);
        if (try self.requiresHandling(binding.ty)) {
            if (!binding.ownership.available) return self.sink.failOwnershipTransfer(
                .{ .code = "E_RESULT_CONSUMED", .rule = .L1 },
                span,
                binding.name,
                binding.ownership.transfer_span,
            );
            binding.ownership.available = false;
            binding.ownership.transfer_span = span;
        }
        if (self.option_facts.has(self.active.get(self.src.text(span)).?)) {
            if (self.expected_types.get(span)) |expected| if (symbolic.same(expected, binding.ty, self.catalog)) return binding.ty;
            return self.optionElement(binding.ty, span);
        }
        return binding.ty;
    }
    fn endScope(self: *Checker, before: usize) void {
        self.option_facts.endScope(before);
        for (self.locals.items[before..]) |item| _ = self.active.remove(item.internal_name orelse self.src.text(item.name));
        self.locals.shrinkRetainingCapacity(before);
        // A nested `_` hid an outer one for its scope; the outer binding is visible again.
        var outer = self.locals.items.len;
        while (outer > 0) {
            outer -= 1;
            if (!std.mem.eql(u8, self.src.text(self.locals.items[outer].name), "_")) continue;
            self.active.putAssumeCapacity("_", outer);
            break;
        }
    }
    fn yieldValue(self: *Checker, value: ast.NodeId, span: source.Span) Error!bool {
        const context = self.match_yield orelse return self.sink.fail("E_MATCH_EXPRESSION_REMOVED", span, "yield arms were removed; assign a named result or return from a match statement arm");
        const actual = if (context.value) |expected| try self.expressionExpected(value, expected) else try self.expression(value);
        if (context.value) |expected| try self.compatible(actual, expected, span);
        self.match_yield.?.value = context.value orelse actual;
        return false;
    }
    fn failValue(self: *Checker, value: ast.NodeId, span: source.Span) Error!bool {
        const failure = self.program.functions[self.function_index].signature.failure_type orelse
            return self.sink.fail("E_FAIL_CONTEXT", span, "fail requires a fails clause");
        const expected = try self.ty(failure);
        const actual = try self.expressionExpected(value, expected);
        const at = @import("frontend_failures.zig").failSite(span, self.program.nodes.items[@backingInt(value)].span);
        const conversion: Conversion = .{ .form = at.form, .span = span, .value = at.value };
        if (!try self.wrappingErrorCase(expected, actual, conversion)) try self.compatible(actual, expected, span);
        try self.requireHandled(0, span);
        return true;
    }
    fn returnValue(self: *Checker, value: ast.NodeId, span: source.Span) Error!void {
        const signature = self.program.functions[self.function_index].signature;
        const expected = if (signature.failure_type != null) (try self.resultShape(self.result, span, "E_FAIL_CONTEXT")).ok_type else self.result;
        try self.compatible(try self.expressionExpected(value, expected), expected, span);
        try self.requireHandled(0, span);
    }
    fn bindingDeclaration(self: *Checker, name: source.Span) Error {
        const insertion: source.Span = .{ .start = name.start, .end = name.start };
        return self.sink.failFix(diagnostic.binding_declaration, name, "assignment requires a declared binding; introduce a writable local with `mut`", .{ .span = insertion, .text = "mut " });
    }
    /// Writability is a source binding fact, independent of concrete ownership.
    fn requireWritableBinding(self: *Checker, name: source.Span, initialize: bool) Error!void {
        const slot = self.active.get(self.src.text(name)) orelse return self.sink.fail("E_UNKNOWN_NAME", name, "name is not defined in this template scope");
        const binding = self.locals.items[slot];
        const assigned = binding.ownership.initialized or binding.ownership.maybe_initialized;
        if (binding.mutable or (initialize and !assigned)) return;
        return self.sink.failOwnershipRelated(
            .{ .code = diagnostic.immutable, .rule = .B1 },
            name,
            "this binding and its nested data are read-only; declare it with `mut` to update it",
            .{ .span = binding.name, .message = "read-only binding declared here" },
        );
    }
    fn requireWritablePlace(self: *Checker, target: ast.NodeId) Error!void {
        try self.requireWritableBinding(try self.placeRoot(target), false);
    }
    /// Locate a named place root without inspecting or settling its Result state.
    fn placeRoot(self: *Checker, target: ast.NodeId) Error!source.Span {
        var current = target;
        while (true) {
            const node = self.program.nodes.items[@backingInt(current)];
            switch (node.data) {
                .name => |name| return name,
                .field => |field| current = field.base,
                .index => |index| current = index.base,
                .mut_argument, .own_argument => |value| current = value,
                else => return self.sink.fail("E_ASSIGNMENT_TARGET", node.span, "a write requires a writable variable, field or element"),
            }
        }
    }
    fn bind(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool) Error!void {
        return self.bindMode(name, ty_value, mutable);
    }
    fn bindPattern(self: *Checker, arm: ast.MatchArm, position: usize, name: source.Span, value: Symbolic, mutable: bool) Error!void {
        if (arm.internal.names.len == 0 or arm.internal.names[position].len == 0) return self.bind(name, value, mutable);
        const internal = arm.internal.names[position];
        try self.active.put(self.allocator, internal, self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .internal_name = internal, .ty = value, .mutable = mutable });
    }
    /// Refuse a binding of a generic body named like a module-level name, saying which kind (F-10).
    fn refuseTopLevelShadow(self: *Checker, name: source.Span) Error {
        const text = self.src.text(name);
        const found = if (self.module_names) |names| try names.declarationOf(name) else null;
        const kind = if (found) |top| names_module.shadowedKind(top.kind, false) else "a module-level name";
        const message = try names_module.shadowingMessage(self.allocator, "binding", text, kind);
        if (found) |top| if (top.at) |at| return self.sink.failRelated(eShadowing, name, message, .{ .span = at, .message = if (top.kind == .module) "imported here" else "declared here" });
        return self.sink.fail(eShadowing, name, message);
    }
    fn bindMode(self: *Checker, name: source.Span, ty_value: Symbolic, mutable: bool) Error!void {
        const text = self.src.text(name);
        if (!std.mem.eql(u8, text, "_")) {
            if (try self.topLevel(name)) return self.refuseTopLevelShadow(name);
            if (self.active.get(text)) |slot| {
                const message = try names_module.shadowingMessage(self.allocator, "binding", text, "the local");
                return self.sink.failRelated(eShadowing, name, message, .{ .span = self.locals.items[slot].name, .message = "declared here" });
            }
            for (self.parameters) |parameter| if (std.mem.eql(u8, text, self.src.text(parameter.name))) return self.sink.fail(eShadowing, name, "binding shadows a template type parameter");
        }
        try self.active.put(self.allocator, text, self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = name, .ty = ty_value, .mutable = mutable });
    }
    fn callTarget(self: *Checker, invocation: Call, call_span: source.Span) Error!ast.Function {
        if (invocation.owner == null) {
            const spelling = self.src.text(invocation.name);
            const reserved = std.mem.eql(u8, spelling, "print") or @import("file_operations.zig").access(spelling) != null;
            if (reserved and !self.functions.contains(spelling)) return self.sink.fail(eUnsupported, invocation.name, "`print` and the file builtins are not supported inside generic function bodies");
            // A prelude builtin that `specialCall` does not answer is no function of the program: say so, not that no function has its name.
            const shadowed = self.active.contains(spelling) or try self.topLevel(invocation.name);
            if (prelude_builtins.reserved(spelling) and !shadowed) {
                const message = try std.fmt.allocPrint(self.allocator, "the prelude builtin `{s}` is not supported inside generic function bodies; write an ordinary function that uses it and call that function", .{spelling});
                return self.sink.fail(eUnsupported, invocation.name, message);
            }
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
        try self.calls.append(self.allocator, .{ .caller = self.function_index, .callee = index, .span = call_span });
        if (self.module_names == null and function.policy.restricted) {
            const allowed = if (self.owner) |owner| std.mem.eql(u8, self.src.text(owner), self.src.text(function.policy.owner.?)) else false;
            if (!allowed) return self.sink.failRelated("E_PRIVATE_FUNCTION", invocation.name, "private generic method requires the same declaring domain", .{ .span = function.name, .message = "private function declared here" });
        }
        // The callee's body is not walked here. Every template is checked from the worklist, and an ordinary helper is
        // checked by the concrete checker, which knows every form and builtin a body may use; this symbolic one does
        // not (`set()`, `dict()`, `sum(...)`, `print` and more are refused), so walking a helper reached from a template
        // refused bodies that check alone (F-S1a-3).
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
        if (self.catalog.templates.store) |store| if (store.index.syntax.suffixes.get(span)) |suffix| {
            try self.enter(span);
            defer self.depth -= 1;
            return self.shapes().nominal(self.catalog.templates.store.?.index.names.get(if (suffix.kind == .growable) "list" else "Option").?, &.{try self.substituted(suffix.base, parameters, arguments)});
        };
        for (self.program.types.expressions.callbacks) |callback| if (callback.span.start == span.start) {
            try self.enter(span);
            defer self.depth -= 1;
            const inputs = try self.field_arena.allocator().alloc(Symbolic, callback.parameters.len);
            for (callback.parameters, inputs) |input, *out| out.* = try self.substituted(input, parameters, arguments);
            const success = try self.substituted(callback.return_type, parameters, arguments);
            const result = if (callback.failure_type) |failure|
                try self.resultType(success, try self.substituted(failure, parameters, arguments), span)
            else
                success;
            return self.callbackType(callback, inputs, result);
        };
        if (self.catalog.templates.store) |store| if (store.index.syntax.applications.get(span.start)) |syntax| {
            if (syntax.span.end == span.end) return self.substitutedApplication(syntax, parameters, arguments);
        };
        if (self.catalog.templates.applications.get(span.start)) |template| if (template.syntax.span.end == span.end) {
            try self.enter(span);
            defer self.depth -= 1;
            var values: [16]Symbolic = undefined;
            const required = self.catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
            for (template.syntax.arguments, required, 0..) |argument, parameter, i| {
                values[i] = if (parameter.constant_length) try self.substitutedLength(argument, parameters, arguments) else try self.substituted(argument, parameters, arguments);
            }
            return self.shapes().nominal(template.declaration, values[0..template.arguments.len]);
        };
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
        return applied orelse raw;
    }
    fn indirectCall(self: *Checker, invocation: Call) Error!Symbolic {
        const value = try self.namedValue(invocation.name);
        var concrete_parameters: [16]Symbolic = undefined;
        const contract: symbolic.Callback = if (value == .callback) value.callback.* else concrete: {
            const ty_value = try self.concreteValue(value, invocation.name);
            const signature = @import("callables.zig").signature(ty_value, self.catalog.records) orelse return self.sink.fail("E_CALLBACK_TYPE", invocation.name, "called local is not a function value");
            for (signature.parameters, 0..) |parameter, i| concrete_parameters[i] = .{ .concrete = parameter };
            break :concrete .{
                .parameters = concrete_parameters[0..signature.parameters.len],
                .result = .{ .concrete = signature.return_type },
                .labels = signature.labels,
                .mutates = signature.mutates,
                .return_origin = signature.return_origin,
            };
        };
        if (invocation.type_arguments.len != 0 or invocation.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", invocation.name, "callback arguments must match its signature");
        const bound = try self.callbackArguments(invocation, contract);
        for (bound, contract.parameters) |input, parameter| {
            try self.compatible(try self.expressionExpected(input, parameter), parameter, invocation.name);
        }
        return contract.result;
    }
    fn callbackArguments(self: *Checker, invocation: Call, contract: symbolic.Callback) Error![]const ast.NodeId {
        const values = try self.field_arena.allocator().alloc(ast.NodeId, invocation.arguments.len);
        const filled = try self.field_arena.allocator().alloc(bool, values.len);
        @memset(filled, false);
        for (invocation.arguments, 0..) |input, index| {
            const label = if (invocation.argument_names.len == 0) null else invocation.argument_names[index];
            const target = if (label) |name| target: {
                for (contract.labels, 0..) |candidate, position| {
                    if (candidate.len != 0 and std.mem.eql(u8, candidate, self.src.text(name))) break :target position;
                }
                return self.sink.fail(eCallArgument, name, "keyword names no named callback parameter");
            } else index;
            if (target >= values.len or filled[target]) return self.sink.fail(eCallArgument, invocation.name, "callback parameter receives more than one argument");
            if (label == null and target < contract.labels.len and contract.labels[target].len != 0)
                return self.sink.fail("E_KEYWORD_ONLY", invocation.name, "callback parameter must be supplied by name");
            filled[target] = true;
            values[target] = input;
        }
        return values;
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
        if (self.program.nodes.items[@backingInt(assignment.target)].data == .tuple)
            return self.tupleAssignment(assignment, node.span);
        try self.requireWritablePlace(assignment.target);
        try self.requireResultAvailable(try self.placeRoot(assignment.target));
        const expected = try self.expression(assignment.target);
        if (assignment.op != .set) try self.augmentedTarget(assignment.op, expected, node.span);
        try self.compatible(try self.expressionExpected(assignment.value, expected), expected, node.span);
        return .{ .concrete = .unit };
    }
    /// Build a symbolic tuple value from its element values. Concrete elements
    /// are interned in the catalog, so a value and a `tuple[...]` spelling of
    /// the same elements are one identity; anything else keeps the elements as
    /// ordered arguments, which is what makes `tuple[T, int]` spellable.
    // twin-drift-ok: the shape-only copy in `symbolic_shapes.Context.tuple`
    // carries a catalog by value, so it may look an interned tuple up but never
    // create one; this one holds the checker's catalog and interns on demand.
    fn symbolicTuple(self: *Checker, elements: []const Symbolic, span: source.Span) Error!Symbolic {
        if (elements.len < 2 or elements.len > 8) return self.sink.fail(eTupleArity, span, tuple_arity_message);
        var concrete: [8]typed.Type = undefined;
        var all_concrete = true;
        for (elements, 0..) |element, index| {
            if (element != .concrete) {
                all_concrete = false;
                break;
            }
            concrete[index] = element.concrete;
        }
        if (all_concrete) return .{ .concrete = try self.catalog.tupleType(concrete[0..elements.len]) };
        const declaration = self.catalog.templates.store.?.index.tupleDeclaration(elements.len) orelse return error.InternalError;
        return self.shapes().nominal(declaration, elements);
    }
    /// Check one `(a, b)` value in a template body. A destination that already
    /// demands a tuple type checks each element against its positional type;
    /// otherwise the element types are inferred and interned.
    fn tupleValue(self: *Checker, span: source.Span, elements: []const ast.NodeId) Error!Symbolic {
        const demanded = self.expected_types.get(span);
        const expected = if (demanded) |value| symbolic_shapes.tupleArity(self.catalog, value) else null;
        if (expected) |arity| if (arity != elements.len) return self.sink.fail(
            eTupleArity,
            span,
            try std.fmt.allocPrint(self.allocator, "this tuple has {d} elements but the destination has {d}; write {d} elements", .{ elements.len, arity, arity }),
        );
        const values = try self.field_arena.allocator().alloc(Symbolic, elements.len);
        for (elements, 0..) |element, index| {
            if (demanded) |value| {
                const wanted = symbolic_shapes.tupleElement(self.catalog, value, index).?;
                values[index] = try self.expressionExpected(element, wanted);
                try self.compatible(values[index], wanted, span);
            } else values[index] = try self.expression(element);
        }
        return self.symbolicTuple(values, span);
    }
    /// The accepted arity a two-name `for` needs, naming the one-name loop.
    fn twoNameLoopMessage(self: *Checker, elements: usize) Error![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "a two-name `for` takes `enumerate(values)`, `zip(left, right)` or `dicts.items(mapping)`, and this source gives values of {d} parts — bind each with one name (tuples were removed; use a record with named fields)",
            .{elements},
        );
    }
    /// `x, y = value` inside a template body: the value must be a tuple whose
    /// arity matches the names, and each name binds one positional element.
    fn validateTupleTargets(self: *Checker, target: ast.Node, declaration: ?bool) Error!void {
        var unknown: ?source.Span = null;
        var all_unknown = true;
        for (target.data.tuple) |id| {
            const node = self.program.nodes.items[@backingInt(id)];
            if (node.data != .name) {
                if (declaration != null) return self.sink.fail("E_ASSIGNMENT_TARGET", node.span, "a destructuring declaration requires binding names");
                all_unknown = false;
                continue;
            }
            const name = node.data.name;
            if (std.mem.eql(u8, self.src.text(name), "_")) continue;
            if (self.active.contains(self.src.text(name))) all_unknown = false else unknown = unknown orelse name;
        }
        if (declaration != null or unknown == null) return;
        if (!all_unknown) return self.sink.fail(diagnostic.binding_declaration, unknown.?, "destructuring assignment requires declared bindings");
        const at = target.span.start;
        return self.sink.failFix(diagnostic.binding_declaration, unknown.?, "introduce writable tuple bindings with mut", .{ .span = .{ .start = at, .end = at }, .text = "mut " });
    }
    fn tupleAssignment(self: *Checker, assignment: @FieldType(@FieldType(ast.Node, "data"), "field_assignment"), span: source.Span) Error!Symbolic {
        const target = self.program.nodes.items[@backingInt(assignment.target)];
        const names = target.data.tuple;
        try self.validateTupleTargets(target, assignment.declaration);
        const value = try self.expression(assignment.value);
        const arity = symbolic_shapes.tupleArity(self.catalog, value) orelse {
            const found = try self.symbolicText(value);
            const message = try std.fmt.allocPrint(self.allocator, "a destructuring assignment binds the values of a tuple; `{s}` is not one — bind it with one name instead", .{found});
            return self.sink.fail("E_TYPE", span, message);
        };
        if (arity != names.len) return self.sink.fail(eTupleArity, span, "a destructuring assignment binds one name per tuple element");
        for (names, 0..) |name_id, index| {
            const element = symbolic_shapes.tupleElement(self.catalog, value, index).?;
            if (self.program.nodes.items[@backingInt(name_id)].data != .name) {
                try self.placeTarget(name_id, element, span);
                continue;
            }
            const name = self.program.nodes.items[@backingInt(name_id)].data.name;
            if (std.mem.eql(u8, self.src.text(name), "_")) continue;
            if (assignment.declaration) |mutable| {
                try self.bind(name, element, mutable);
            } else if (self.active.contains(self.src.text(name))) {
                try self.requireWritableBinding(name, false);
                const target_binding = try self.local(name);
                try self.compatible(element, target_binding.ty, name);
                self.option_facts.forget(self.active.get(self.src.text(name)).?);
            } else return self.bindingDeclaration(name);
        }
        return .{ .concrete = .unit };
    }
    /// PY-DESTRUCTURE-PLACE-1: an element or field destructuring target takes
    /// the tuple element the way `target = value` does in a template body.
    fn placeTarget(self: *Checker, target: ast.NodeId, element: Symbolic, span: source.Span) Error!void {
        try self.requireWritablePlace(target);
        try self.requireResultAvailable(try self.placeRoot(target));
        try self.compatible(element, try self.expression(target), span);
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
        if (self.shapes().isSet(expected.?)) return self.sink.fail("E_DICT_TYPE", node.span, "`{}` is an empty dict; write `set()` for an empty set");
        const key = try self.shapes().collectionKey(expected.?, node.span);
        const element = try self.collectionElement(expected.?, node.span);
        try self.hashableKey(key, node.span, false);
        try self.supports(element, .copy, node.span);
        try self.supports(element, .storable, node.span);
        if (try self.requiresHandling(element)) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, node.span, "dictionary values cannot contain pending results");
        for (entries, 0..) |input, index| {
            const target = if (index % 2 == 0) key else element;
            try self.compatible(try self.expressionExpected(input, target), target, node.span);
        }
        return expected.?;
    }
    /// Require a dictionary key or set element a template can hash
    /// (HASH-KEYS-1): a concrete type by the ordinary hashability rule, a `str`,
    /// or a type parameter that promises integer support.
    fn hashableKey(self: *Checker, key: Symbolic, span: source.Span, set: bool) Error!void {
        if (key == .concrete) return @import("hashable_keys.zig").require(self.allocator, self.catalog.records, self.sink, key.concrete, span, set);
        if (self.shapes().collectionKind(key) == .string) return;
        try self.supports(key, .integer, span);
    }
    /// `{a, b, ...}` in a template body: one element type from the context or
    /// the first element, which the set must be able to hash (SET-1).
    fn setLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId) Error!Symbolic {
        var expected = self.expected_types.get(node.span);
        if (expected) |value| if (!self.shapes().isSet(value)) {
            expected = null;
        };
        var element: ?Symbolic = if (expected) |value| try self.shapes().collectionKey(value, node.span) else null;
        for (inputs) |input| {
            const value = if (element) |ty_value| try self.expressionExpected(input, ty_value) else try self.expression(input);
            if (element) |ty_value| try self.compatible(value, ty_value, node.span) else element = value;
        }
        try self.setElement(element.?, node.span);
        return expected orelse try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("set").?, &.{element.?});
    }
    /// The rules one set element type follows in a template body.
    fn setElement(self: *Checker, element: Symbolic, span: source.Span) Error!void {
        try self.hashableKey(element, span, true);
        try self.supports(element, .copy, span);
        try self.supports(element, .storable, span);
        if (try self.requiresHandling(element)) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, span, "set elements cannot contain pending results");
    }
    /// Build a fixed array from a list literal whose context already demands `[N]T`.
    fn fixedArrayLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, expected: Symbolic) Error!Symbolic {
        const shape = try self.arrayShape(expected, node.span);
        if (shape.length_parameter != null) return self.sink.fail(diagnostic.generic_length, node.span, "array literal construction requires a fixed length in an uncalled template");
        if (inputs.len != shape.length) return self.sink.fail("E_ARRAY_LENGTH", node.span, "list literal length differs from the expected fixed array");
        for (inputs) |input| try self.compatible(try self.expressionExpected(input, shape.element), shape.element, node.span);
        return expected;
    }
    /// Retained compatibility arm; parsed comprehensions use abstract gather recognition.
    fn comprehensionValue(self: *Checker, each: ast.Comprehension, span: source.Span) Error!Symbolic {
        _ = each;
        return self.sink.fail("E_COMPREHENSION_REMOVED", span, "comprehensions were removed; use a typed accumulator and an explicit loop");
    }
    /// PY-GATHER-1: a comprehension checked through its own loop: the collection
    /// its step fills. A generator expression needs the concrete checker's
    /// consuming call, which template bodies do not have.
    fn gatherValue(self: *Checker, gather: ast.Gather, span: source.Span) Error!Symbolic {
        if (gather.shape == .generator) return self.sink.fail(@import("sema_gathers.zig").generator_code, span, "generator arguments were removed; use a typed accumulator and an explicit loop");
        try self.gather_frames.append(self.allocator, .{ .shape = gather.shape, .expected = self.expected_types.get(span) });
        defer _ = self.gather_frames.pop();
        _ = try self.statement(gather.loop);
        const frame = self.gather_frames.items[self.gather_frames.items.len - 1];
        const value = frame.value orelse return error.InternalError;
        const names = self.catalog.templates.store.?.index.names;
        const result = frame.expected orelse try switch (gather.shape) {
            .list => self.shapes().nominal(names.get("List").?, &.{value}),
            .set => self.shapes().nominal(names.get("set").?, &.{value}),
            .dict => self.shapes().nominal(names.get("dict").?, &.{ frame.key.?, value }),
            .generator => error.InternalError,
        };
        const type_name = try self.gatherTypeName(result);
        if (type_name) |spelling| {
            const element = if (gather.shape == .set) try self.shapes().collectionKey(result, span) else try self.collectionElement(result, span);
            var seen: std.ArrayList(Symbolic) = .empty;
            const migration = @import("comprehension_migration.zig");
            const use: @import("sema_gathers.zig").Use = switch (gather.shape) {
                .list => .list,
                .set => .set,
                .dict => .dict,
                .generator => unreachable,
            };
            try migration.publishNamed(self.allocator, .{ .src = self.src, .syntax = self.program, .prefix = try migration.modulePrefix(self.allocator, self.src, span, self.module_names) }, self.sink, .{
                .node = .{ .span = span, .data = .{ .gather = gather } },
                .gather = gather,
                .use = use,
                .types = .{
                    .result = spelling,
                    .value = try self.gatherTypeName(element) orelse return error.InternalError,
                    .key = if (gather.shape == .dict) try self.gatherTypeName(try self.shapes().collectionKey(result, span)) else null,
                    .managed_value = try possiblyManaged(self.shapes(), element, &seen),
                    .managed_key = gather.shape == .dict and try possiblyManaged(self.shapes(), try self.shapes().collectionKey(result, span), &seen),
                },
            });
        } else {
            try self.sink.items.append(self.allocator, .{ .code = "E_COMPREHENSION_REMOVED", .span = span, .message = "comprehensions were removed; use a typed accumulator and an explicit loop" });
        }
        return result;
    }
    /// Spell accumulator types from abstract parameters, independent of actual types.
    fn gatherTypeName(self: *Checker, value: Symbolic) Error!?[]const u8 {
        switch (value) {
            .concrete => |concrete_type| {
                const spelling = try typed.surfaceTypeName(self.allocator, concrete_type, self.catalog.records);
                return spelling;
            },
            .parameter => |index| return self.src.text(self.parameters[index].name),
            .nominal => |nominal| {
                const store = self.catalog.templates.store orelse return null;
                const declaration = store.index.declarations.items[nominal.declaration];
                const name = declaration.builtin_name orelse self.src.text(declaration.name);
                var arguments: std.ArrayList([]const u8) = .empty;
                for (nominal.arguments) |argument| try arguments.append(self.allocator, try self.gatherTypeName(argument) orelse return null);
                if (std.mem.eql(u8, name, "List") and arguments.items.len == 1) {
                    const spelling = try std.fmt.allocPrint(self.allocator, "{s}[]", .{arguments.items[0]});
                    return spelling;
                }
                if (arguments.items.len == 0) return name;
                const spelling = try std.fmt.allocPrint(self.allocator, "{s}[{s}]", .{ name, try std.mem.join(self.allocator, ", ", arguments.items) });
                return spelling;
            },
            else => return null,
        }
    }
    /// The innermost step of the comprehension being checked.
    fn gatherStep(self: *Checker, step: ast.GatherStep, span: source.Span) Error!void {
        if (self.gather_frames.items.len == 0) return error.InternalError;
        const key = if (step.key) |syntax| try self.expression(syntax) else null;
        const value = try self.expression(step.value);
        const frame = &self.gather_frames.items[self.gather_frames.items.len - 1];
        if (frame.shape != .list) try self.supports(value, .copy, span);
        try self.supports(value, .storable, span);
        frame.key = key;
        frame.value = value;
    }
    /// The shape of a fixed array a loop may walk by position; an enum table
    /// is indexed by its key, not by position, so it is not one.
    fn walkableArray(self: *Checker, value: Symbolic) ?symbolic.Array {
        const shape = symbolic.array(value, self.catalog.records) orelse return null;
        return if (shape.key == null) shape else null;
    }
    /// Every f-string piece converts to text, so the whole literal is `str`.
    fn formatValue(self: *Checker, parts: []const ast.NodeId, span: source.Span) Error!Symbolic {
        const str_type: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
        for (parts) |part| {
            // A literal piece of the f-string is text, not an expression: the
            // concrete checker skips it the same way (sema_collections.checkFormat).
            // Checking it as an expression reads the text as a type name.
            if (self.program.nodes.items[@backingInt(part)].data == .text) continue;
            const before = self.sink.items.items.len;
            const value = self.expression(part) catch |err| {
                // The one unknown name a hole reports says a literal brace is written `{{`, as the concrete checker's does.
                if (err == error.SourceError and self.sink.items.items.len == before + 1)
                    try format_strings.adviseUnknownName(self.allocator, self.src.bytes, self.program.nodes.items, parts, &self.sink.items.items[before]);
                return err;
            };
            // PY-FSTRING-SPEC-1: a formatted field always builds fresh text.
            if (symbolic.same(value, str_type, self.catalog)) continue;
            if (self.isFloat(value)) continue;
            try self.supports(value, .integer, span);
        }
        return str_type;
    }
    /// PY-FSTRING-SPEC-1: a specification formats a `str`, a float or an
    /// integer; the concrete instance checks the specification itself.
    fn formattedField(self: *Checker, value_id: ast.NodeId, span: source.Span) Error!Symbolic {
        const str_type: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
        const value = try self.expression(value_id);
        if (!symbolic.same(value, str_type, self.catalog) and !self.isFloat(value)) try self.supports(value, .integer, span);
        return str_type;
    }
    fn listLiteral(self: *Checker, node: ast.Node, inputs: []const ast.NodeId) Error!Symbolic {
        var expected = self.expected_types.get(node.span);
        if (expected) |ty_value| if (symbolic.array(ty_value, self.catalog.records)) |shape| {
            if (shape.key == null) return self.sink.fail("E_FIXED_ARRAY_LITERAL", node.span, "array literals are growable; construct FixedArray explicitly");
        };
        var element: ?Symbolic = if (expected) |ty_value| try self.collectionElement(ty_value, node.span) else null;
        if (inputs.len == 0 and expected == null) return self.sink.fail("E_LIST_INFERENCE", node.span, "empty list requires an expected List type");
        for (inputs) |input| {
            const value = if (element) |ty_value| try self.expressionExpected(input, ty_value) else try self.expression(input);
            if (element) |ty_value| try self.compatible(value, ty_value, node.span) else element = value;
        }
        try self.supports(element.?, .storable, node.span);
        if (expected == null) expected = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{element.?});
        return expected.?;
    }
    /// Python trim/search in generic bodies uses the receiver family and scalar bounds.
    fn textOperation(self: *Checker, owner: Symbolic, operation: struct { kind: BufferKind, inputs: []const ast.NodeId, span: source.Span }) Error!Symbolic {
        const family = self.shapes().collectionKind(owner);
        if (family != .string and family != .bytes)
            return self.sink.fail(eListType, operation.span, "search and trim require str or bytes");
        for (operation.inputs, 0..) |input, index| {
            if (buffer_operations.search(operation.kind) != null and index > 0)
                try self.supports(try self.expression(input), .integer, operation.span)
            else
                try self.compatible(try self.expressionExpected(input, owner), owner, operation.span);
        }
        if (buffer_operations.trim(operation.kind) != null) {
            return owner;
        }
        const mode = buffer_operations.search(operation.kind).?;
        return .{ .concrete = if (mode == .prefix or mode == .suffix) .bool else .i64 };
    }
    fn valueOperation(self: *Checker, owner: Symbolic, kind: BufferKind, arguments: usize, span: source.Span) Error!Symbolic {
        if (kind != .copy) return self.sink.fail(eListType, span, "operation requires a managed collection");
        return self.copyValue(owner, arguments, span);
    }
    fn copyValue(self: *Checker, owner: Symbolic, arguments: usize, span: source.Span) Error!Symbolic {
        if (arguments != 0) return self.sink.fail("E_ARITY", span, "copy takes no arguments");
        try self.supports(owner, .copy, span);
        return owner;
    }
    /// The operations in a template body that only a list receiver answers: a
    /// dictionary or byte receiver that reached one is the wrong family.
    fn requireListReceiver(self: *Checker, kind: BufferKind, family: @import("runtime_values.zig").ManagedKind, span: source.Span) Error!void {
        const list_only = switch (kind) {
            .exchange, .extend, .insert, .remove, .index_of, .reverse => true,
            else => false,
        };
        if (list_only and family != .list) return self.sink.fail(eListMethod, span, "this operation requires a list receiver");
    }
    fn checkNegativePositions(self: *Checker, dictionary: bool, kind: BufferKind, inputs: []const ast.NodeId) Error!void {
        if (!dictionary) {
            const position = kind == .read or kind == .write or kind == .exchange or kind == .insert or kind == .pop_at;
            for (inputs, 0..) |input, index| {
                const bound = negative_index.rangeBound(kind, index);
                if ((position and index == 0) or bound)
                    try negative_index.checkSyntax(Checker, self, input, bound or kind == .insert);
            }
        }
    }
    /// The type a dictionary operand takes in a template body: `update`'s other mapping
    /// takes the receiver's own type, a key takes the key type, and a value the element type.
    fn mappingOperand(kind: BufferKind, index: usize, owner: Symbolic, key: Symbolic, element: Symbolic) Symbolic {
        if (kind == .update) return owner;
        return if (index == 0) key else element;
    }
    /// The operation a template-body collection call names on a receiver of `family`.
    /// A dictionary's `pop` is one spelling whose argument count selects `pop_key` or
    /// `pop_default`, as the concrete checker selects it; the dictionary-only kinds
    /// are refused on any other receiver.
    fn selectedKind(self: *Checker, kind: BufferKind, family: @import("runtime_values.zig").ManagedKind, inputs: usize, span: source.Span) Error!BufferKind {
        switch (kind) {
            .pop_key, .pop_default, .setdefault, .update => if (family != .dictionary)
                return self.sink.fail(eUnsupported, span, "unsupported collection operation in generic body"),
            else => {},
        }
        if (family == .dictionary and kind == .pop) return if (inputs == 2) .pop_default else .pop_key;
        return kind;
    }
    fn collectionOperation(self: *Checker, owner: Symbolic, operation: struct { kind: BufferKind, inputs: []const ast.NodeId, span: source.Span, owner_node: ?ast.NodeId = null }) Error!Symbolic {
        if (operation.kind.mutates()) if (operation.owner_node) |target| try self.requireWritablePlace(target);
        if (self.shapes().isSet(owner)) {
            return self.setOperation(owner, .{ .kind = operation.kind, .inputs = operation.inputs, .span = operation.span });
        }
        const family = self.shapes().collectionKind(owner) orelse return self.valueOperation(owner, operation.kind, operation.inputs.len, operation.span);
        const element = try self.collectionElement(owner, operation.span);
        const key = if (family == .dictionary) try self.shapes().collectionKey(owner, operation.span) else element;
        const kind = buffer_operations.forFamily(try selectedKind(self, operation.kind, family, operation.inputs.len, operation.span), family);
        try self.requireListReceiver(kind, family, operation.span);
        try self.checkPendingOperation(owner, kind, operation.span);
        if (operation.inputs.len != kind.arity()) return self.sink.fail("E_ARITY", operation.span, "collection argument count differs from its signature");
        try self.checkNegativePositions(family == .dictionary, kind, operation.inputs);
        if (buffer_operations.search(kind) != null or buffer_operations.trim(kind) != null)
            return self.textOperation(owner, .{ .kind = kind, .inputs = operation.inputs, .span = operation.span });
        if (family == .dictionary) if (dictionary_views.operation(kind)) |view|
            return self.shapes().nominal(self.catalog.templates.store.?.index.names.get(view.name()).?, &.{ key, element });
        const output: Symbolic = switch (kind) {
            .strip, .lstrip, .rstrip, .upper, .lower, .replace, .zfill => owner,
            .view, .slice => owner,
            .is_digit, .is_alpha, .is_space => .{ .concrete = .bool },
            .count => .{ .concrete = .i64 },
            .length, .capacity => .{ .concrete = .i64 },
            .parse_int, .parse_int_range => try self.optionType(.{ .concrete = .i64 }),
            .parse_float, .parse_float_range => try self.optionType(self.floatType()),
            .read, .get, .pop, .pop_at, .exchange, .pop_key, .pop_default, .setdefault => element,
            .contains => .{ .concrete = .bool },
            .index_of => .{ .concrete = .i64 },
            .append, .write, .extend, .insert, .remove, .reverse, .clear, .update => .{ .concrete = .unit },
            .buffer_append_array => .{ .concrete = .bool },
            .keys, .values, .split => try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{if (kind == .keys) key else if (kind == .split) owner else element}),
            .join => owner,
            .copy => owner,
            .sort => sorted: {
                if (family != .list or !self.sortable(element)) return self.sink.fail(eCollectionMethod, operation.span, "sort requires an integer, float, str or bytes element type");
                break :sorted .{ .concrete = .unit };
            },
            else => return self.sink.fail(eUnsupported, operation.span, "unsupported collection operation in generic body"),
        };
        const numeric_parse = kind == .parse_int or kind == .parse_float or kind == .parse_int_range or kind == .parse_float_range;
        if (numeric_parse and family != .bytes)
            return self.sink.fail(eListType, operation.span, "numeric byte parsing requires a bytes receiver");
        if (family == .string and (kind == .write or kind == .append or kind == .get)) return self.sink.failOwnership(.{ .code = "E_TEXT_IMMUTABLE", .rule = .T4 }, operation.span, "strings are immutable");
        if (family != .string and (kind == .split or kind == .join)) return self.sink.fail(eListType, operation.span, "split and join require str");
        if (family != .dictionary and (kind == .keys or kind == .values or kind == .get)) return self.sink.fail(eListType, operation.span, "mapping operation requires a dictionary");
        const range_bound = kind == .view or kind == .borrow_view or kind == .slice or kind == .parse_int_range or kind == .parse_float_range;
        if (kind == .buffer_append_array) try self.checkAppendArray(.{ .owner = owner, .bytes = family == .bytes }, operation.inputs, operation.span);
        for (operation.inputs, 0..) |input, index| {
            if (kind == .buffer_append_array) continue;
            // The insertion position is the integer; its value is the element.
            const indexed = index == 0 and (kind == .read or kind == .write or kind == .pop_at or kind == .exchange or kind == .insert);
            const integer = family != .dictionary and (range_bound or indexed);
            const expected = if (family == .dictionary)
                mappingOperand(kind, index, owner, key, element)
            else if (kind == .join)
                try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{owner})
            else if (kind == .extend)
                // `extend` appends another list of the same element type.
                owner
            else
                element;
            if (integer) try self.supports(try self.expression(input), .integer, operation.span) else try self.compatible(try self.expressionExpected(input, expected), expected, operation.span);
        }
        return output;
    }
    /// `byte_buffer.append_array(array, start, end)` in a template body: a mutable byte buffer
    /// receiver, a fixed `u8` array of any (possibly symbolic) length, and two integer endpoints.
    fn checkAppendArray(self: *Checker, receiver: struct { owner: Symbolic, bytes: bool }, inputs: []const ast.NodeId, span: source.Span) Error!void {
        if (!receiver.bytes or self.immutableBytes(receiver.owner)) return self.sink.fail(eCollectionMethod, span, "in-place buffer methods require a byte_buffer receiver");
        const shape = try self.arrayShape(try self.expression(inputs[0]), span);
        if (shape.key != null or shape.element != .concrete or shape.element.concrete != .u8)
            return self.sink.fail(eCollectionMethod, span, "append_array requires a FixedArray[u8, N] source");
        for (inputs[1..]) |endpoint| try self.supports(try self.expression(endpoint), .integer, span);
    }
    /// One set method in a template body (SET-1): its operands take the
    /// element (`add`, `remove`, `discard`) or the set type, and its writes and
    /// allocations are the ones the concrete desugaring performs.
    fn setOperation(self: *Checker, owner: Symbolic, operation: struct { kind: BufferKind, inputs: []const ast.NodeId, span: source.Span }) Error!Symbolic {
        const kind = operation.kind;
        if (!buffer_operations.setMethod(kind)) return self.sink.fail(eListMethod, operation.span, unknown_set_method);
        if (operation.inputs.len != kind.arity()) return self.sink.fail("E_ARITY", operation.span, "collection argument count differs from its signature");
        const element = try self.shapes().collectionKey(owner, operation.span);
        const takes_element = kind == .set_add or kind == .set_discard or kind == .remove;
        for (operation.inputs) |input| {
            const expected = if (takes_element) element else owner;
            try self.compatible(try self.expressionExpected(input, expected), expected, operation.span);
        }
        return switch (kind) {
            .pop => element,
            .copy, .set_union, .set_intersection, .set_difference, .set_symmetric_difference => owner,
            .set_subset, .set_superset, .set_disjoint => .{ .concrete = .bool },
            else => .{ .concrete = .unit },
        };
    }
    /// `.borrow(start, end)` was removed with `TextView`/`ByteView` (wave 3
    /// §5.4): the repair is the slice spelling of the same range.
    fn refuseBorrowView(self: *Checker, at: source.Span, receiver: source.Span, arguments: []const ast.NodeId, kind: BufferKind) Error {
        const message = if (kind == .view) borrow_view_fix.view_message else borrow_view_fix.message;
        if (arguments.len != 2) return self.sink.fail(borrow_view_fix.code, at, message);
        const edit = try borrow_view_fix.edit(
            self.allocator,
            self.src,
            receiver,
            self.program.nodes.items[@backingInt(arguments[0])].span,
            self.program.nodes.items[@backingInt(arguments[1])].span,
            at,
        );
        return self.sink.failFix(borrow_view_fix.code, at, message, edit);
    }

    fn listOperation(self: *Checker, node: ast.Node, operation: @FieldType(@FieldType(ast.Node, "data"), "list_operation")) Error!Symbolic {
        if (operation.kind == .view or operation.kind == .borrow_view) return self.refuseBorrowView(node.span, self.program.nodes.items[@backingInt(operation.base)].span, operation.arguments, operation.kind);
        const owner = try self.borrowList(operation.base);
        if (operation.kind == .write and operation.arguments.len == 2 and symbolic.array(owner, self.catalog.records) != null)
            return self.arrayWrite(owner, operation, node.span);
        return self.collectionOperation(owner, .{ .kind = operation.kind, .inputs = operation.arguments, .span = node.span, .owner_node = operation.base });
    }
    /// `values[index] = value` on a fixed array in a template body: the index
    /// and element follow the array's own rules, and the binding the path is
    /// rooted at must be one the body may modify, as for a record field write.
    fn arrayWrite(self: *Checker, owner: Symbolic, operation: @FieldType(@FieldType(ast.Node, "data"), "list_operation"), span: source.Span) Error!Symbolic {
        const shape = try self.arrayIndex(owner, operation.arguments[0], span);
        try self.compatible(try self.expressionExpected(operation.arguments[1], shape.element), shape.element, span);
        try self.requireWritablePlace(operation.base);
        try self.requireResultAvailable(try self.placeRoot(operation.base));
        return .{ .concrete = .unit };
    }
    /// What the removed `contains` was called with: its whole span, its receiver's span and its arguments.
    const ContainsSite = struct { name: source.Span, call: source.Span, receiver: source.Span, arguments: []const ast.NodeId, names: []const ?source.Span };
    /// FR19: refuse the removed `.contains(value)` on a collection `receiver`, worded for its type as the concrete check words it
    /// (`contains_removed.zig`). A receiver that is no collection returns, to be refused as an unknown method.
    fn refuseContains(self: *Checker, receiver: Symbolic, site: ContainsSite) Error!void {
        const family = self.shapes().collectionKind(receiver) orelse return;
        const named = site.names.len != 0 and site.names[0] != null;
        const argument: ?source.Span = if (site.arguments.len == 1 and !named) self.program.nodes.items[@backingInt(site.arguments[0])].span else null;
        return contains_removed.refuse(self.allocator, self.src, self.sink, contains_removed.fromKind(family, self.shapes().isSet(receiver)), .{
            .name = site.name,
            .call = site.call,
            .receiver = site.receiver,
            .argument = argument,
        });
    }
    /// MSG-B 1: `lists.contains(first, value)` with a text, bytes, set or dictionary `first` is told to write the operator `in`,
    /// as the concrete check says (`contains_removed.refuseListsContains`). Any other first argument returns, to be inferred.
    fn refuseListsContains(self: *Checker, function: ast.Function, invocation: Call, first: Symbolic, span: source.Span) Error!void {
        if (!contains_removed.isListsContains(self.src, function)) return;
        const family = self.shapes().collectionKind(first) orelse return;
        const kind = contains_removed.fromKind(family, self.shapes().isSet(first));
        if (kind == .list) return;
        return contains_removed.refuseListsContains(self.allocator, self.src, self.sink, kind, .{
            .span = span,
            .start = if (invocation.owner) |owner| owner.start else invocation.name.start,
            .name_end = invocation.name.end,
        });
    }
    fn listMethod(self: *Checker, node: ast.Node) Error!Symbolic {
        const method = node.data.method_call;
        const name = self.src.text(method.name);
        if (std.mem.eql(u8, name, "copy")) {
            const receiver = self.program.nodes.items[@backingInt(method.base)].span;
            const text = try copy_method.callText(self.allocator, self.src.text(receiver));
            return self.sink.failFix(copy_method.code, node.span, copy_method.message, .{ .span = node.span, .text = text });
        }
        if (option_flow.methodNamed(name) != null) {
            const receiver = try self.expression(method.base);
            if (try self.optionMethod(receiver, self.program.nodes.items[@backingInt(method.base)].span, name, method.arguments, node.span)) |value| return value;
        }
        if (std.mem.eql(u8, name, "read_only")) {
            if (method.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "read_only takes no arguments");
            const value = try self.expression(method.base);
            if (try self.concreteValue(value, node.span) != .filesystem_cap) return self.sink.fail("E_TYPE", node.span, "read_only requires a Filesystem capability");
            return value;
        }
        if (std.mem.eql(u8, name, "push")) _ = try @import("removed_names.zig").reject(self.sink, method.name, name);
        if (std.mem.eql(u8, name, contains_removed.method)) try self.refuseContains(try self.expression(method.base), .{
            .name = method.name,
            .call = node.span,
            .receiver = self.program.nodes.items[@backingInt(method.base)].span,
            .arguments = method.arguments,
            .names = method.argument_names,
        });
        if (std.mem.eql(u8, name, "sort") and method.arguments.len != 0)
            return self.keyedSort(try self.expression(method.base), .{ .arguments = method.arguments, .names = method.argument_names, .span = node.span, .owner_node = method.base });
        if (method.argument_names.len != 0) return self.sink.fail(eCallArgument, method.name, "collection methods take their arguments by position; only a list's sort takes key= and reverse=");
        const kind = buffer_operations.methodFor(name, method.arguments.len) orelse return self.sink.fail(eListMethod, method.name, unknown_method);
        if (kind == .borrow_view or kind == .view) return self.refuseBorrowView(node.span, self.program.nodes.items[@backingInt(method.base)].span, method.arguments, kind);
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
    const NumericRange = struct { owner: Symbolic, start: ?ast.NodeId, end: ?ast.NodeId, kind: BufferKind, span: source.Span };
    /// Check one immediate range's receiver and optional bounds in source order.
    fn numericRangeResult(self: *Checker, range: NumericRange) Error!Symbolic {
        if (self.shapes().collectionKind(range.owner) != .bytes) return self.sink.fail(eListType, range.span, "numeric byte parsing requires a bytes receiver");
        if (range.start) |bound| {
            try self.supports(try self.expression(bound), .integer, range.span);
            try negative_index.checkSyntax(Checker, self, bound, true);
        }
        if (range.end) |bound| {
            try self.supports(try self.expression(bound), .integer, range.span);
            try negative_index.checkSyntax(Checker, self, bound, true);
        }
        return if (range.kind == .parse_int) try self.optionType(.{ .concrete = .i64 }) else try self.optionType(self.floatType());
    }
    /// Wave 3's scalar text helpers over a symbolic receiver: the count is an
    /// integer and every other helper answers its receiver's own type, so the
    /// abstract pass agrees with the concrete check without naming a shape a
    /// generic body cannot know.
    fn scalarTextHelper(self: *Checker, invocation: Call) Error!?Symbolic {
        const candidate = scalar_text_helpers.helper(Checker, self, invocation) orelse return null;
        try scalar_text_helpers.requireImport(Checker, self, invocation.name, candidate);
        if (scalar_text_helpers.loopSource(candidate))
            return self.sink.fail(scalar_text_helpers.iteration_code, invocation.name, "a text loop source is only usable as a for statement's source");
        try call_arguments.positional(invocation, self.sink);
        // A search helper's positions after the needle are range bounds: report a
        // constant negative here, exactly as an uninstantiated method body did.
        switch (candidate) {
            .char_find, .char_rfind, .char_index, .char_rindex, .char_count_of, .char_startswith, .char_endswith => {
                if (invocation.arguments.len > 2) for (invocation.arguments[2..]) |position| try negative_index.checkSyntax(Checker, self, position, true);
            },
            else => {},
        }
        const receiver = try self.expression(invocation.arguments[0]);
        return switch (candidate) {
            .char_count, .char_find, .char_rfind, .char_index, .char_rindex, .char_count_of => .{ .concrete = .i64 },
            .char_startswith, .char_endswith => .{ .concrete = .bool },
            .char_at, .char_slice, .char_stride, .list_stride => receiver,
            .chars, .bytes => null,
        };
    }

    /// Recognize a numeric parser consuming a slice directly. Concrete
    /// specialization performs the matching range lowering; this abstract pass
    /// mirrors its allocation effect so a generic `noalloc` contract agrees.
    fn immediateNumericRange(self: *Checker, id: ast.NodeId, kind: BufferKind, span: source.Span) Error!?Symbolic {
        const input = self.program.nodes.items[@backingInt(id)];
        return switch (input.data) {
            .slice => |slice| if (slice.step != null)
                null
            else
                try self.numericRangeResult(.{ .owner = try self.expression(slice.base), .start = slice.start, .end = slice.end, .kind = kind, .span = span }),
            else => null,
        };
    }
    /// Check `values[index] op= value` in a generic body against the element's own rules.
    fn indexAssignment(self: *Checker, node: ast.Node) Error!Symbolic {
        const assignment = node.data.index_assignment;
        try self.requireWritablePlace(assignment.target);
        const target = self.program.nodes.items[@backingInt(assignment.target)];
        const expected = try self.expression(assignment.target);
        try self.augmentedTarget(assignment.op, expected, node.span);
        try self.compatible(try self.expressionExpected(assignment.value, expected), expected, node.span);
        if (target.data == .index) if (self.program.nodes.items[@backingInt(target.data.index.base)].data == .name)
            try self.requireResultAvailable(self.program.nodes.items[@backingInt(target.data.index.base)].data.name);
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
        const owner = try self.borrowList(slice.base);
        try self.checkPendingOperation(owner, .slice, node.span);
        _ = try self.collectionElement(owner, node.span);
        if (slice.start) |input| {
            try self.supports(try self.expression(input), .integer, node.span);
            if (self.shapes().collectionKind(owner) != .dictionary) try negative_index.checkSyntax(Checker, self, input, true);
        }
        if (slice.end) |input| {
            try self.supports(try self.expression(input), .integer, node.span);
            if (self.shapes().collectionKind(owner) != .dictionary) try negative_index.checkSyntax(Checker, self, input, true);
        }
        if (slice.step) |input| try self.supports(try self.expression(input), .integer, node.span);
        return owner;
    }
    /// One intrinsic `Option[T]` method checked over a symbolic receiver, or
    /// null when the receiver is not an `Option` or the name is no such method.
    /// The three are pure, allocate nothing and contribute no effect, so a
    /// generic body may call them under a `noalloc` ceiling.
    fn optionMethod(self: *Checker, receiver: Symbolic, receiver_span: source.Span, name: []const u8, arguments: []const ast.NodeId, span: source.Span) Error!?Symbolic {
        const shape = (try self.shapes().matchOption(receiver, span)) orelse return null;
        const method = option_flow.methodNamed(name) orelse return null;
        if (method != .unwrap_or) {
            // Presence has one spelling, `value is None`, so the method form
            // names its certain repair. An owned payload needs `match`.
            if (try self.transfers(receiver)) return self.sink.fail("E_OPTION_TEST", span, "use match for an Option carrying an owned value or checked Result");
            const message = option_spelling.method_message;
            if (option_spelling.adjacentComparison(self.src, span)) return self.sink.fail(option_spelling.method_code, span, message);
            return self.sink.failFix(option_spelling.method_code, span, message, .{ .span = .{ .start = receiver_span.end, .end = span.end }, .text = option_spelling.testSuffix(method == .is_some) });
        }
        if (arguments.len != 1)
            return self.sink.fail("E_ARITY", span, "`unwrap_or` takes exactly one argument: `unwrap_or(default)`");
        try self.compatible(try self.expressionExpected(arguments[0], shape.element), shape.element, span);
        return shape.element;
    }
    /// The intrinsic `Option` method a call on a named local spells, or null
    /// when the receiver is not an `Option` binding or another receiver's
    /// methods win. A narrowed collection payload keeps its own methods, exactly
    /// as the concrete checker decides.
    fn optionReceiverCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        const owner = input_call.owner orelse return null;
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        const name = self.src.text(input_call.name);
        if (option_flow.methodNamed(name) == null and self.shapes().managed(self.locals.items[slot].ty)) return null;
        try self.requireInitialized(self.locals.items[slot], owner);
        return self.optionMethod(self.locals.items[slot].ty, owner, name, input_call.arguments, span);
    }
    fn managedMethod(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (input_call.owner) |owner| if (self.active.get(self.src.text(owner))) |slot| {
            const receiver = if (self.option_facts.has(slot)) try self.optionElement(self.locals.items[slot].ty, owner) else self.locals.items[slot].ty;
            if (self.shapes().managed(receiver) or std.mem.eql(u8, self.src.text(input_call.name), "copy")) {
                try self.requireResultAvailable(owner);
                try self.refuseRetiredSpelling(input_call, owner, receiver, span);
                if (keywordSort(self, input_call)) {
                    try self.requireWritableBinding(owner, false);
                    const sorted = try self.keyedSort(receiver, .{ .arguments = input_call.arguments, .names = input_call.argument_names, .span = span });
                    return sorted;
                }
                const kind = buffer_operations.methodFor(self.src.text(input_call.name), input_call.arguments.len) orelse {
                    if (std.mem.eql(u8, self.src.text(input_call.name), contains_removed.method))
                        try self.refuseContains(receiver, .{ .name = input_call.name, .call = span, .receiver = owner, .arguments = input_call.arguments, .names = input_call.argument_names });
                    return self.sink.fail(eListMethod, input_call.name, unknown_method);
                };
                if (kind == .borrow_view or kind == .view) return self.refuseBorrowView(span, owner, input_call.arguments, kind);
                if (input_call.type_arguments.len != 0) return self.sink.fail("E_ARITY", span, "collection methods do not take explicit type arguments");
                if (kind.mutates()) try self.requireWritableBinding(owner, false);
                if (self.shapes().isSet(receiver)) {
                    const answer = try self.setOperation(receiver, .{ .kind = kind, .inputs = input_call.arguments, .span = span });
                    return answer;
                }
                const result = try self.collectionOperation(receiver, .{ .kind = kind, .inputs = input_call.arguments, .span = span });
                return result;
            }
        };
        return null;
    }
    /// A retired method spelling in a template body is refused as the concrete
    /// check refuses it, with the certain call as its repair. A template body is
    /// checked before any instance exists, so an unused one refuses too: one home
    /// per operation. The import the call needs comes as the next round's own repair,
    /// so this edit is the call alone. The standard library's own sources are refused
    /// as any program is: they are written in the function forms (W13, slice 3).
    fn refuseRetiredSpelling(self: *Checker, input_call: Call, owner: source.Span, receiver: Symbolic, span: source.Span) Error!void {
        const family = self.shapes().collectionKind(receiver) orelse return;
        const found = retired_methods.findShaped(self.src.text(input_call.name), family, self.receiverShape(receiver), input_call.arguments.len) orelse
            return self.refuseMethodForm(input_call, owner, family, receiver, span);
        // A field or element read is lent (F-2); a generic body's names keep `sets.add` and its next round.
        const lent = input_call.arguments.len == 1 and switch (self.program.nodes.items[@backingInt(input_call.arguments[0])].data) {
            .field, .index => true,
            else => false,
        };
        const retirement = retired_methods.forArgument(found, !lent);
        const arguments = try self.allocator.alloc([]const u8, input_call.arguments.len);
        for (input_call.arguments, arguments) |id, *slot| slot.* = self.src.text(self.program.nodes.items[@backingInt(id)].span);
        const names = try self.allocator.alloc(?[]const u8, input_call.argument_names.len);
        for (input_call.argument_names, names) |name, *slot| slot.* = if (name) |written| self.src.text(written) else null;
        const text = try retired_methods.callText(self.allocator, retirement, self.src.text(owner), arguments, names);
        // A home that answers nothing takes its statement's `_ =` with it; a value use has no certain repair.
        var fix_span = span;
        if (retirement.answer == .nothing) {
            fix_span = retired_methods.statementSpan(self.src.bytes, span) orelse
                return self.sink.fail(retired_methods.code, span, try retired_methods.nothingMessage(self.allocator, retirement));
        }
        const message = try retired_methods.message(self.allocator, retirement);
        // A module home needs its import in this unit, so the repair carries it too:
        // without it the rewritten call is an unknown function, and no fix follows.
        var more: []const diagnostic.Edit = &.{};
        if (retirement.home.module) |module| if (try self.importEdit(span, module)) |imported| {
            more = try self.allocator.dupe(diagnostic.Edit, &.{imported});
        };
        try self.sink.appendFix(.{ .code = retired_methods.code, .span = fix_span, .message = message }, .{ .span = fix_span, .text = text });
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = more;
        return error.SourceError;
    }
    /// A method W13 removed (W13-S5) in a template body is refused as its instances are (`E_METHOD_REMOVED`), so an
    /// unused template refuses it too. The edit is the plain home call, and only where it is certain without what an
    /// instance knows: not a search whose `int?` answer needs its comparison rewritten, a join whose operands change
    /// places, or a prelude home (the concrete check decides those, with their reasons).
    fn refuseMethodForm(self: *Checker, input_call: Call, owner: source.Span, family: @import("runtime_values.zig").ManagedKind, receiver: Symbolic, span: source.Span) Error!void {
        const retiring_forms = @import("retiring_forms.zig");
        const row = retiring_forms.methodForm(self.src.text(input_call.name), family, self.receiverShape(receiver), input_call.arguments.len) orelse return;
        try retiring_forms.reported(self.sink, span);
        const arguments = try self.allocator.alloc([]const u8, input_call.arguments.len);
        for (input_call.arguments, arguments) |id, *slot| slot.* = self.src.text(self.program.nodes.items[@backingInt(id)].span);
        const names = try self.allocator.alloc(?[]const u8, input_call.argument_names.len);
        for (input_call.argument_names, names) |name, *slot| slot.* = if (name) |written| self.src.text(written) else null;
        const text = try retired_methods.callText(self.allocator, row, self.src.text(owner), arguments, names);
        // The same decisions as the concrete check's (`sema_collections.warnMethodForm`): a prelude home the unit claims,
        // a join whose two operands are both evaluated work, a search whose `int?` answer is not compared with a literal.
        const claimed = row.home.module == null and (self.active.contains(row.home.function) or self.functions.contains(row.home.function) or try self.topLevel(input_call.name));
        const pure = retiring_forms.pureText(self.src.text(owner)) or (arguments.len != 0 and retiring_forms.pureText(arguments[0]));
        const reordered = row.home.arguments_first and arguments.len == 1 and !pure;
        var fix_span = span;
        var replacement = text;
        var compared = true;
        if (row.home.absence == .option) {
            compared = false;
            if (retired_methods.comparisonAround(self.src.bytes, span)) |comparison| if (try retired_methods.absenceRepair(self.allocator, comparison, text)) |repaired| {
                replacement = repaired;
                fix_span = comparison.span;
                compared = true;
            };
        }
        const uncertain = claimed or reordered or !compared;
        const message = try retiring_forms.methodMessage(self.allocator, row, text, if (uncertain) "a generic body's call is written by hand" else null);
        if (uncertain) return self.sink.fail(retiring_forms.method_code, span, message);
        var more: []const diagnostic.Edit = &.{};
        if (row.home.module) |module| if (try self.importEdit(span, module)) |imported| {
            more = try self.allocator.dupe(diagnostic.Edit, &.{imported});
        };
        try self.sink.appendFix(.{ .code = retiring_forms.method_code, .span = fix_span, .message = message }, .{ .span = fix_span, .text = replacement });
        self.sink.items.items[self.sink.items.items.len - 1].provenance.fix.?.more = more;
        return error.SourceError;
    }
    /// The retirement shape of a symbolic managed receiver (F-b): a set, the mutable
    /// buffer, or any other collection.
    fn receiverShape(self: *Checker, receiver: Symbolic) retired_methods.Shape {
        if (self.shapes().isSet(receiver)) return .set;
        if (self.shapes().isMutableBuffer(receiver)) return .buffer;
        return .collection;
    }
    /// The `import` line a standard module needs in the unit `span` belongs to, or
    /// null when that unit already imports it. The same placement as the concrete
    /// check's repair (`sema_collections.moduleImportEdit`).
    fn importEdit(self: *Checker, span: source.Span, module: []const u8) Error!?diagnostic.Edit {
        return import_fix.moduleEdit(self.allocator, self.src, span, module);
    }
    /// Whether the source a checked span belongs to is one of the compiler's own
    /// standard-library sources, which may acquire a network resource from its raw request.
    fn trustedSource(self: *Checker, span: source.Span) bool {
        const library = @import("standard_library.zig");
        if (self.src.trusted_intrinsics) return true;
        if (library.trusted(self.src.path, self.src.bytes, false)) return true;
        const original = self.src.originalSpan(span) catch return false;
        const unit = self.src.origins[original.input].original;
        return library.trusted(unit.path, unit.bytes, unit.trusted_intrinsics);
    }
    /// The calls in a template body that write through their first operand: the
    /// prelude writers (`append`, `sort`, `take`, `exchange`) and the list module's homes, which answer the operation
    /// the retired method spelling lowered to.
    fn writingCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (try self.homeCall(input_call, span)) |value| return value;
        if (try self.writerCall(input_call, span)) |value| return value;
        return self.exchangeCall(input_call, span);
    }
    /// `lists.pop(mut values, index)` and the rest of the list module's homes in a
    /// template body: the call lowers to the operation its retired method spelling
    /// did, which is what the concrete checker recognizes too, so a migrated helper
    /// body checks without the module function's declared requirements. A `mut`
    /// marker on the receiver is required here as the concrete call requires it.
    fn homeCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        // A module-qualified call keeps its whole dotted name in `name` and has no
        // receiver, because the qualifier is a module rather than a value.
        if (input_call.owner != null) return null;
        if (input_call.type_arguments.len != 0 or input_call.argument_names.len != 0) return null;
        const name = self.src.text(input_call.name);
        const dot = std.mem.lastIndexOfScalar(u8, name, '.') orelse return null;
        if (dot == 0 or dot + 1 == name.len) return null;
        const qualifier = name[0..dot];
        if (self.active.contains(qualifier)) return null;
        const module = try self.homeModule(qualifier, input_call.name) orelse return null;
        const retirement = retired_methods.home(module, name[dot + 1 ..], input_call.arguments.len) orelse return null;
        if (input_call.arguments.len == 0) return null;
        const written = buffer_operations.methodFor(retirement.method, retirement.arguments) orelse return null;
        const receiver_at = if (retirement.home.arguments_first) input_call.arguments.len - 1 else 0;
        const receiver = input_call.arguments[receiver_at];
        // The marker names the receiver; symbolic and concrete checking both
        // enforce the source binding's writability.
        const marker = self.program.nodes.items[@backingInt(receiver)];
        if (retirement.home.writer and marker.data != .mut_argument) {
            const text = self.src.text(marker.span);
            const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes `{s}`; write `mut {s}`", .{ retirement.home.function, text, text });
            const insert: source.Span = .{ .start = marker.span.start, .end = marker.span.start };
            return self.sink.failOwnershipFix(.{ .code = mutation_marker_code, .rule = .M3 }, marker.span, message, .{ .span = insert, .text = "mut " });
        }
        const place = if (marker.data == .mut_argument) marker.data.mut_argument else receiver;
        const inputs = try self.allocator.alloc(ast.NodeId, input_call.arguments.len - 1);
        var slot: usize = 0;
        for (input_call.arguments, 0..) |id, index| {
            if (index == receiver_at) continue;
            inputs[slot] = id;
            slot += 1;
        }
        const value = try self.borrowList(place);
        // A home answers only the receiver its row names: a dictionary's home is not a
        // list's, and a set or a buffer answers its own rows (SET-1, F-b). Any other
        // receiver takes the module function's own checks, as the concrete call does.
        if (self.shapes().collectionKind(value) != retirement.family) return null;
        const shape = self.receiverShape(value);
        if (shape != retirement.shape and !(shape == .buffer and retired_methods.lendsBuffer(retirement))) return null;
        const operation = try self.collectionOperation(value, .{ .kind = written, .inputs = inputs, .span = span, .owner_node = place });
        // A home whose method always answered `true` answers nothing (wave 2, lane B).
        if (retirement.answer == .nothing) return Symbolic{ .concrete = .unit };
        return operation;
    }
    // twin-drift-ok: this copy reads the template checker's own module table and
    // spells the path on the stack, because a template check may run on a caller's
    // allocator; the concrete checker's copy reads the catalog and may allocate.
    /// The embedded standard module a qualifier names, when the writing module
    /// imports it: the same rule the concrete checker's recognized home applies.
    fn homeModule(self: *Checker, qualifier: []const u8, at: source.Span) Error!?[]const u8 {
        const names = self.module_names orelse return null;
        const target = names.index.project.names.get(qualifier) orelse return null;
        const module = names.index.project.modules.items[target].name;
        // The path is a stack spelling: a template check may run on a caller's own
        // allocator, so a blocked allocation path must not own one.
        var buffer: [96]u8 = undefined;
        const path = std.fmt.bufPrint(&buffer, "{s}.selka", .{module}) catch return null;
        if (@import("standard_library.zig").source(path) == null) return null;
        if (!try names.importsModule(at, module)) return null;
        return module;
    }
    /// `NAME.method(...)` on a `str` or `bytes` module constant in a generic body: the
    /// constant is read once, and its type answers the method (`CONST-METHOD-1`).
    fn constantMethod(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        const owner = input_call.owner orelse return null;
        if (input_call.type_arguments.len != 0 or self.active.contains(self.src.text(owner))) return null;
        if (self.module_names) |names| {
            const kind = try names.symbolKind(owner);
            if (kind == null or kind.? != .function) return null;
        }
        const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.program, .names = self.module_names, .sink = self.sink, .catalog = self.catalog };
        const index = (try constants.lookup(owner)) orelse return null;
        if ((try constants.literalType(index)) == null) return null;
        const receiver = try self.namedValue(owner);
        const kind = buffer_operations.methodFor(self.src.text(input_call.name), input_call.arguments.len) orelse {
            if (std.mem.eql(u8, self.src.text(input_call.name), contains_removed.method))
                try self.refuseContains(receiver, .{ .name = input_call.name, .call = span, .receiver = owner, .arguments = input_call.arguments, .names = input_call.argument_names });
            return self.sink.fail(eListMethod, input_call.name, unknown_method);
        };
        if (kind == .borrow_view or kind == .view) return self.refuseBorrowView(span, owner, input_call.arguments, kind);
        const answer = try self.collectionOperation(receiver, .{ .kind = kind, .inputs = input_call.arguments, .span = span });
        return answer;
    }
    /// `append(mut values, item)` and `sort(mut values, key=…)` in a template
    /// body: the prelude spellings of the two writing methods, whose receiver is
    /// the marked first operand. The marker rides the call, so the inner node is
    /// the collection the operation writes.
    fn writerCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (input_call.owner != null or input_call.type_arguments.len != 0) return null;
        const spelling = self.src.text(input_call.name);
        const appending = std.mem.eql(u8, spelling, "append");
        if (!appending and !std.mem.eql(u8, spelling, "sort")) return null;
        if (self.active.contains(spelling) or try self.topLevel(input_call.name)) return null;
        if (input_call.arguments.len == 0) return null;
        const first = self.program.nodes.items[@backingInt(input_call.arguments[0])];
        if (first.data != .mut_argument) return null;
        try self.requireWritablePlace(first.data.mut_argument);
        const receiver = try self.borrowList(first.data.mut_argument);
        if (!appending) {
            if (input_call.arguments.len > 1) {
                const sorted = try self.keyedSort(receiver, .{
                    .arguments = input_call.arguments[1..],
                    .names = input_call.argument_names[1..],
                    .span = span,
                });
                return sorted;
            }
            const sorted = try self.collectionOperation(receiver, .{ .kind = .sort, .inputs = &.{}, .span = span });
            return sorted;
        }
        if (input_call.arguments.len != 2) return self.sink.fail("E_ARITY", span, "`append` takes one value: `append(mut values, value)`");
        const appended = try self.collectionOperation(receiver, .{ .kind = .append, .inputs = input_call.arguments[1..], .span = span });
        return appended;
    }
    /// `take(mut place)` and `exchange(mut place, value)` in a template body (LANG1 item 3): the answer is the place's own
    /// type, and the replacement must have it. Whether the place has an empty value to leave behind is decided where the
    /// type is concrete, at each specialization, as for any other operation that needs a native capability of `T`.
    fn exchangeCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (input_call.owner != null or input_call.type_arguments.len != 0) return null;
        const spelling = self.src.text(input_call.name);
        const exchanging = std.mem.eql(u8, spelling, "exchange");
        if (!exchanging and !std.mem.eql(u8, spelling, "take")) return null;
        if (self.active.contains(spelling) or try self.topLevel(input_call.name)) return null;
        const wanted: usize = if (exchanging) 2 else 1;
        if (input_call.arguments.len != wanted)
            return self.sink.fail("E_ARITY", span, if (exchanging) "exchange takes a place and a value: `exchange(mut place, value)`" else "take takes one place: `take(mut place)`");
        const first = self.program.nodes.items[@backingInt(input_call.arguments[0])];
        if (first.data != .mut_argument) {
            const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes `{s}`; write `mut {s}`", .{ spelling, self.src.text(first.span), self.src.text(first.span) });
            const insert: source.Span = .{ .start = first.span.start, .end = first.span.start };
            return self.sink.failOwnershipFix(.{ .code = mutation_marker_code, .rule = .M3 }, first.span, message, .{ .span = insert, .text = "mut " });
        }
        try self.requireWritablePlace(first.data.mut_argument);
        const place = try self.borrowList(first.data.mut_argument);
        if (exchanging) try self.compatible(try self.expressionExpected(input_call.arguments[1], place), place, span);
        return place;
    }
    /// `copy(value)` in a generic body: the prelude copy of the argument, whose
    /// own type is the result unless the argument is a borrowed view.
    fn preludeCopyCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (input_call.owner != null or input_call.type_arguments.len != 0) return null;
        if (!std.mem.eql(u8, self.src.text(input_call.name), "copy")) return null;
        if (self.active.contains("copy") or try self.topLevel(input_call.name)) return null;
        if (input_call.arguments.len != 1) return self.sink.fail("E_ARITY", span, "copy takes one value: `copy(value)`");
        // The argument is read as `name.copy()` read its receiver: a borrowed
        // view copies to its owned collection, a collection keeps its own family,
        // and any other value is copied as a value.
        const value = try self.borrowList(input_call.arguments[0]);
        const copied = try self.collectionOperation(value, .{ .kind = .copy, .inputs = &.{}, .span = span, .owner_node = input_call.arguments[0] });
        return copied;
    }
    /// `sorted(values, key=..., reverse=...)` in a generic body, when no
    /// binding or declaration claims the name: a new list of the argument's
    /// type, its named operands checked as `values.sort(...)` checks them.
    fn sortedCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (input_call.owner != null or input_call.type_arguments.len != 0) return null;
        if (!std.mem.eql(u8, self.src.text(input_call.name), "sorted")) return null;
        if (self.active.contains("sorted") or try self.topLevel(input_call.name)) return null;
        if (input_call.arguments.len == 0) return self.sink.fail("E_ARITY", span, "sorted requires a list");
        const names = input_call.argument_names;
        if (names.len != 0 and names[0] != null) return self.sink.fail(eCallArgument, names[0].?, "the sorted list is positional");
        const receiver = try self.expression(input_call.arguments[0]);
        _ = try self.keyedSort(receiver, .{ .arguments = input_call.arguments[1..], .names = if (names.len == 0) names else names[1..], .span = span });
        return receiver;
    }
    /// The operands of one `values.sort(key=..., reverse=...)` in a generic body.
    const SortOperands = struct { arguments: []const ast.NodeId, names: []const ?source.Span, span: source.Span, owner_node: ?ast.NodeId = null };
    /// `values.sort(key=..., reverse=...)` in a generic body: the operands are
    /// checked in source order, `reverse` as a `bool`, and the receiver is
    /// written. Each specialization checks the key against its concrete
    /// element type; without a key the element needs a native order.
    fn keyedSort(self: *Checker, receiver: Symbolic, sort: SortOperands) Error!Symbolic {
        if (sort.owner_node) |target| try self.requireWritablePlace(target);
        try self.checkPendingOperation(receiver, .sort, sort.span);
        if (self.shapes().collectionKind(receiver) != .list) return self.sink.fail(eListType, sort.span, "sort requires a list receiver");
        var keyed = false;
        for (sort.arguments, 0..) |argument, index| {
            const keyword = if (sort.names.len == 0) null else sort.names[index];
            const text = if (keyword) |name| self.src.text(name) else "";
            if (std.mem.eql(u8, text, "reverse")) {
                const flag: Symbolic = .{ .concrete = .bool };
                try self.compatible(try self.expressionExpected(argument, flag), flag, sort.span);
            } else if (std.mem.eql(u8, text, "key")) {
                _ = try self.expression(argument);
                keyed = true;
            } else return self.sink.fail(eCallArgument, keyword orelse sort.span, "sort takes only key= and reverse=, by keyword");
        }
        if (!keyed and !self.sortable(try self.collectionElement(receiver, sort.span)))
            return self.sink.fail(eCollectionMethod, sort.span, "sort requires an integer, float, str or bytes element type");
        return .{ .concrete = .unit };
    }
    fn floatType(self: *Checker) Symbolic {
        return .{ .concrete = self.catalog.names.get("float").? };
    }
    fn isFloat(self: *Checker, value: Symbolic) bool {
        return value == .concrete and numeric_surface.isFloat(value.concrete, self.catalog.records);
    }
    /// Whether a list of `element` has a native order for `sort`: a concrete
    /// integer, float, str or bytes element, matching the concrete checker.
    fn sortable(self: *Checker, element: Symbolic) bool {
        if (self.shapes().collectionKind(element) == .string or self.immutableBytes(element)) return true;
        if (element != .concrete) return false;
        if (element.concrete.isInteger() or self.isFloat(element)) return true;
        return false;
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
        const floating = std.mem.eql(u8, name, "float") or std.mem.eql(u8, name, "parse_float");
        if (!floating) {
            if (!std.mem.eql(u8, name, "int") and !std.mem.eql(u8, name, "parse_int")) return null;
        }
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", span, "numeric conversions require one argument");
        const input = try self.expression(invocation.arguments[0]);
        if (try self.numericParse(invocation, input, floating, span)) |parsed| return parsed;
        if (!self.isFloat(input)) try self.supports(input, .integer, span);
        return if (floating) self.floatType() else .{ .concrete = .i64 };
    }
    fn surfaceUnit(self: *Checker, node: ast.Node) Error!Symbolic {
        if (!@import("frontend_units.zig").isNone(self.src, node.span)) return .{ .concrete = .unit };
        if (self.expected_types.get(node.span)) |expected| {
            if (expected == .concrete and expected.concrete == .unit) return self.sink.failFix(
                "E_NONE_UNIT",
                node.span,
                "None means optional absence; write () for the Unit value",
                .{ .span = node.span, .text = "()" },
            );
            _ = try self.optionElement(expected, node.span);
            return expected;
        }
        return self.sink.fail("E_NONE_CONTEXT", node.span, "None requires an expected optional type");
    }
    fn numericParse(self: *Checker, invocation: Call, input: Symbolic, floating: bool, span: source.Span) Error!?Symbolic {
        const parses = std.mem.startsWith(u8, self.src.text(invocation.name), "parse_");
        if (self.shapes().collectionKind(input) == .string) {
            if (!parses) {
                const target = if (floating) "parse_float" else "parse_int";
                const claimed = self.active.contains(target) or self.functions.contains(target) or self.catalog.names.contains(target) or self.catalog.templates.names.contains(target) or
                    if (self.module_names) |names| try names.topLevelSpelling(invocation.name, target) else false;
                const operand = self.program.nodes.items[@backingInt(invocation.arguments[0])];
                const conversion: numeric_surface.TextConversion = .{ .name = invocation.name, .call = span, .operand = self.src.text(operand.span), .primary = numeric_surface.primaryOperand(operand), .method = false };
                return numeric_surface.rejectTextConversion(self.sink, conversion, target, claimed);
            }
            const parsed = try self.optionType(if (floating) self.floatType() else .{ .concrete = .i64 });
            return parsed;
        }
        if (parses) return self.sink.fail("E_TYPE", span, "parse_int and parse_float require a str argument");
        return null;
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
    fn cellConstructor(self: *Checker, invocation: Call) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        const name = self.src.text(invocation.name);
        if (!std.mem.eql(u8, name, "Cell")) return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        const store = self.catalog.templates.store orelse return null;
        const declaration = store.index.names.get("Cell") orelse return null;
        const builtin = store.index.declarations.items[declaration].builtin_name orelse return null;
        if (!std.mem.eql(u8, builtin, "Cell")) return null;
        return self.sink.failOwnership(
            .{ .code = "E_VALUE_CELL", .rule = .T3 },
            invocation.name,
            "builtin Cell is shared mutable state under value semantics; use a value record with `mut` and store-back, or a pool handle for identity",
        );
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
    /// The scalar repr builtin in generic bodies respects ordinary shadowing.
    fn reprCall(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or !std.mem.eql(u8, self.src.text(invocation.name), "repr")) return null;
        if (self.active.contains("repr") or self.functions.contains("repr")) return null;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 1 or invocation.type_arguments.len != 0 or invocation.argument_names.len != 0)
            return self.sink.fail("E_ARITY", span, "repr requires one argument");
        const input = try self.expression(invocation.arguments[0]);
        try self.requireReprScalar(input, span);
        return .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
    }
    fn requireReprScalar(self: *Checker, input: Symbolic, span: source.Span) Error!void {
        if (self.shapes().collectionKind(input) == .string or self.immutableBytes(input) or self.isFloat(input)) return;
        if (input == .concrete) {
            if (input.concrete == .bool or input.concrete.isInteger()) return;
            // A list, set, dictionary, option, record, result or fixed array of values that have a text is accepted; the concrete check of each instance
            // lowers it as `print` does (F-38, `collection_text.zig`).
            if (collection_text.classify(input.concrete, self.catalog.records) == .accepted) return;
            return self.sink.fail("E_REPR_TYPE", span, try collection_text.refusal(self.allocator, .repr, input.concrete, self.catalog.records));
        }
        if (try self.collectionTextDeferred(input, span)) return;
        if (input == .parameter) return self.supports(input, .integer, span);
        return self.sink.fail("E_REPR_TYPE", span, "repr takes a str, bytes, int, float or bool, or a list, set, dictionary, option, record, result or fixed array of values `print` can show");
    }
    /// Whether `input` is a list, set, dictionary, option, record, result or fixed array that still names a type parameter or
    /// a literal's open width: its text is the instance's to check, as the text of a `debug` argument is (F-38, F-38b). Each
    /// instance takes the concrete check of `str` and `repr`, which refuses a part that has no text and names it.
    fn collectionTextDeferred(self: *Checker, input: Symbolic, span: source.Span) Error!bool {
        if (input == .array) return true;
        if (input != .nominal) return false;
        if (self.shapes().collectionKind(input)) |collection| return collection == .list or collection == .dictionary;
        if (self.shapes().kind(input)) |declared| if (declared == .record or declared == .result) return true;
        return (try self.shapes().matchOption(input, span)) != null;
    }
    /// `debug(values..., sep=, end=)` in a template body, which a plain function accepts (`sema_builtins.debugBuiltin`):
    /// it needs no capability, so nothing of the template's signature changes. Each value is checked here; whether it can
    /// be rendered is the concrete check's, which every instance takes with its own types (the `print` operand check).
    fn debugCall(self: *Checker, invocation: Call) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        if (!std.mem.eql(u8, self.src.text(invocation.name), "debug")) return null;
        if (self.active.contains("debug") or try self.topLevel(invocation.name)) return null;
        const split = try @import("io_builtins.zig").printArguments(self.src, invocation, self.sink);
        for (split.values) |id| _ = try self.expression(id);
        const text: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
        if (split.separator) |id| try self.compatible(try self.expression(id), text, self.program.nodes.items[@backingInt(id)].span);
        if (split.terminator) |id| try self.compatible(try self.expression(id), text, self.program.nodes.items[@backingInt(id)].span);
        return Symbolic{ .concrete = .unit };
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
            // A list, set, dictionary, option, record, result or fixed array of values that have a text is accepted, as the concrete check accepts it (F-38).
            const collection = collection_text.classify(value.concrete, self.catalog.records) == .accepted;
            const takes_text = scalar or aggregate or collection;
            if (!takes_text)
                return self.sink.fail("E_TEXT_CONVERSION", span, try collection_text.refusal(self.allocator, .str, value.concrete, self.catalog.records));
        } else if (!try self.collectionTextDeferred(value, span)) try self.supports(value, .integer, span);
        return Symbolic{ .concrete = target };
    }
    /// `embed_bytes("path")` and `embed_str("path")`: static data of one concrete
    /// type, checked against the file the loader read (`EMBED-1`).
    fn embedCall(self: *Checker, call_value: Call, span: source.Span) Error!?Symbolic {
        if (call_value.owner != null or call_value.type_arguments.len != 0) return null;
        const name = self.src.text(call_value.name);
        const kind = embed.kindOf(name) orelse return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.module_names) |names| if (try names.topLevel(call_value.name)) return null;
        _ = try embed.check(.{ .scratch = self.allocator, .src = self.src, .nodes = self.program.nodes.items, .sink = self.sink }, call_value, kind, span);
        const target = self.catalog.names.get(if (kind == .bytes) "bytes" else "str") orelse return null;
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
                else => return self.sink.fail("E_FILESYSTEM_DIR", argument.span, @import("sema_shared.zig").filesystem_dir_literal_message),
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
                else => return self.sink.fail("E_NETWORK_HOST", argument.span, @import("sema_shared.zig").network_host_literal_message),
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
            if (receiver == .concrete and receiver.concrete == .input_cap)
                return self.sink.fail(eUnsupported, span, "input operations are not supported inside generic function bodies");
            return null;
        }
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        const receiver = self.locals.items[slot].ty;
        if (receiver != .concrete or receiver.concrete != .environment_cap) return null;
        try self.requireInitialized(self.locals.items[slot], owner);
        if (std.mem.eql(u8, name, "get")) {
            if (input_call.type_arguments.len != 0 or input_call.arguments.len != 1 or input_call.argument_names.len != 0) return self.sink.fail("E_ARITY", span, "env.get takes one name");
            const text: Symbolic = .{ .concrete = self.catalog.names.get("str") orelse return self.sink.fail("E_TYPE", span, "env.get requires str") };
            try self.compatible(try self.expression(input_call.arguments[0]), text, self.program.nodes.items[@backingInt(input_call.arguments[0])].span);
            const answer = try self.optionType(text);
            return answer;
        }
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
        const result = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get("List").?, &.{element});
        return result;
    }
    /// Scalar extrema used by explicit positional-bound migrations retain abstract checking.
    /// `min` and `max` of two ordered values, and the float builtins (`floatBuiltin`).
    fn scalarExtreme(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (try self.floatBuiltin(invocation)) |value| return value;
        if (invocation.owner != null or invocation.type_arguments.len != 0) return null;
        const name = self.src.text(invocation.name);
        if (!std.mem.eql(u8, name, "min") and !std.mem.eql(u8, name, "max")) return null;
        if (self.active.contains(name) or try self.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 2) return null;
        try call_arguments.positional(invocation, self.sink);
        const left = try self.expression(invocation.arguments[0]);
        const right = try self.expression(invocation.arguments[1]);
        try self.compatible(right, left, span);
        if (self.shapes().collectionKind(left) != .string and !self.isFloat(left))
            try self.supports(left, .integer, span);
        return left;
    }
    /// `sqrt`, `floor`, `ceil`, `trunc` and `round` of a float answer a float of the same type, as outside a generic
    /// body: the prelude's forms, which W13-S5 made the one spelling of the `math` twins a generic body could call.
    fn floatBuiltin(self: *Checker, invocation: Call) Error!?Symbolic {
        if (invocation.owner != null or invocation.type_arguments.len != 0 or invocation.arguments.len != 1) return null;
        const name = self.src.text(invocation.name);
        const known = for ([_][]const u8{ "sqrt", "floor", "ceil", "trunc", "round" }) |builtin| {
            if (std.mem.eql(u8, name, builtin)) break true;
        } else false;
        if (!known or self.active.contains(name) or try self.topLevel(invocation.name)) return null;
        try call_arguments.positional(invocation, self.sink);
        const value = try self.expression(invocation.arguments[0]);
        if (!self.isFloat(value)) return null;
        return value;
    }
    fn specialCall(self: *Checker, input_call: Call, span: source.Span) Error!?Symbolic {
        if (try self.scalarTextHelper(input_call)) |value| return value;
        if (try self.scalarExtreme(input_call, span)) |value| return value;
        if (try self.identityCall(input_call, span)) |value| return value;
        if (try self.viewSnapshot(input_call, span)) |value| return value;
        if (try self.capabilityMethodCall(input_call, span)) |value| return value;
        if (try self.reprCall(input_call, span)) |value| return value;
        if (try self.textConstructor(input_call, span)) |value| return value;
        if (try self.debugCall(input_call)) |value| return value;
        if (try self.embedCall(input_call, span)) |value| return value;
        if (std.mem.eql(u8, self.src.text(input_call.name), "todo") and input_call.owner == null) {
            const hole = try self.recordHole(input_call.name, input_call.type_arguments[0], span);
            return hole;
        }
        if (try self.truncatingHelper(input_call, span)) |value| return value;
        if (try self.variantConstruction(input_call, span)) |value| return value;
        if (try self.optionReceiverCall(input_call, span)) |value| return value;
        if (try self.managedMethod(input_call, span)) |value| return value;
        if (try self.constantMethod(input_call, span)) |value| return value;
        if (try self.preludeCopyCall(input_call, span)) |value| return value;
        if (try self.writingCall(input_call, span)) |value| return value;
        if (try self.sortedCall(input_call, span)) |value| return value;
        if (try self.cellConstructor(input_call)) |value| return value;
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

    /// The calls that answer a fixed type from one or two operands: `function_digest`, `same_function`, `case_name`,
    /// `Kind.cases()` and `Kind.from_name(text)`.
    fn identityCall(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (try self.functionDigestCall(invocation, span)) |value| return value;
        if (try self.sameFunctionCall(invocation, span)) |value| return value;
        return self.enumCaseCall(invocation, span);
    }
    fn functionDigestCall(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or !std.mem.eql(u8, self.src.text(invocation.name), function_digest.name)) return null;
        if (self.active.contains(function_digest.name) or try self.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 1 or invocation.type_arguments.len != 0)
            return self.sink.fail("E_ARITY", span, "function_digest requires one argument and no type arguments");
        const value = try self.expression(invocation.arguments[0]);
        if (!function_same.symbolicCompatible(value, value, self.catalog))
            return self.sink.fail(function_digest.code, span, function_digest.message);
        return .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
    }
    /// `case_name(value)`, `Kind.cases()` and `Kind.from_name(text)` (`enum_cases.zig`): a concrete enum answers a concrete type, and
    /// a value a type parameter stands for is no enum the check can name a case of.
    fn enumCaseCall(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner == null and std.mem.eql(u8, self.src.text(invocation.name), enum_cases.name_builtin)) {
            if (self.active.contains(enum_cases.name_builtin) or try self.topLevel(invocation.name)) return null;
            if (invocation.arguments.len != 1 or invocation.type_arguments.len != 0) return self.sink.fail("E_ARITY", span, enum_cases.name_message);
            const value = try self.expression(invocation.arguments[0]);
            if (value != .concrete or !enum_cases.isCaseType(self.catalog.records, value.concrete)) return self.sink.fail(enum_cases.code, span, enum_cases.name_message);
            return .{ .concrete = self.catalog.names.get("str") orelse return error.InternalError };
        }
        const found = (try enum_cases.symbolic(Checker, self, invocation, span)) orelse return null;
        for (invocation.arguments) |argument| {
            const value = try self.expression(argument);
            if (value != .concrete or !enum_cases.isText(self.catalog.records, value.concrete)) return self.sink.fail(enum_cases.code, span, "from_name takes one str or bytes name: `Kind.from_name(text)`");
        }
        const store = self.catalog.templates.store orelse return error.InternalError;
        const declaration = store.index.names.get(if (found.which == .cases) "List" else "Option") orelse return error.InternalError;
        const result = try self.shapes().nominal(declaration, &.{.{ .concrete = found.enum_type }});
        return result;
    }
    fn sameFunctionCall(self: *Checker, invocation: Call, span: source.Span) Error!?Symbolic {
        if (invocation.owner != null or !std.mem.eql(u8, self.src.text(invocation.name), function_same.name)) return null;
        if (self.active.contains(function_same.name) or try self.topLevel(invocation.name)) return null;
        if (invocation.arguments.len != 2 or invocation.type_arguments.len != 0)
            return self.sink.fail("E_ARITY", span, "same_function requires two arguments and no type arguments");
        const left = try self.expression(invocation.arguments[0]);
        const right = try self.expression(invocation.arguments[1]);
        if (!function_same.symbolicCompatible(left, right, self.catalog))
            return self.sink.fail(function_same.code, span, function_same.message);
        return .{ .concrete = .bool };
    }
    /// One binding's snapshot entry, spelled from its abstract type.
    fn holeCandidate(self: *Checker, binding: Local) Error!diagnostic.Candidate {
        return .{
            .name = self.src.text(binding.name),
            .ty = try self.symbolicText(binding.ty),
            .declaration = binding.name,
            .mutable = binding.mutable,
            .usable = binding.ownership.initialized and binding.ownership.available,
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
            .mutation = try diagnostic.mutationFact(self.allocator, self.src, function),
        };
    }
    /// The bounded facts this checker can see at a typed hole. The candidate and
    /// requirement lists live in the checker's own allocator, so they outlive
    /// this call and are released with the rest of the check.
    fn holeFindings(self: *Checker, call_span: source.Span, candidates: []const diagnostic.Candidate, required: []const diagnostic.Requirement) Error!diagnostic.Findings {
        return .{ .function = self.holeFunction(), .expected = try self.holeExpected(call_span), .candidates = candidates, .requirements = required, .contract = try self.holeContract() };
    }
    /// Record one typed hole from the facts this checker sees right now. Trap mode takes the hole as an
    /// opaque value of its declared type, which the ordinary checker lowers to a trap, and reports nothing.
    fn recordHole(self: *Checker, at: source.Span, target: source.Span, call_span: source.Span) Error!Symbolic {
        const declared = try self.ty(target);
        if (self.sink.hole_mode != .refuse) {
            self.sink.trapped_holes += 1;
            return declared;
        }
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
            .concrete => |ty_value| writer.writeAll(try typed.surfaceTypeName(self.allocator, ty_value, self.catalog.records)) catch return error.OutOfMemory,
            .parameter => |index| writer.writeAll(self.src.text(self.parameters[index].name)) catch return error.OutOfMemory,
            .length_parameter => |index| writer.writeAll(self.src.text(self.parameters[index].name)) catch return error.OutOfMemory,
            .length => |count| writer.print("{d}", .{count}) catch return error.OutOfMemory,
            .array => |array| {
                writer.writeAll("[") catch return error.OutOfMemory;
                try self.writeSymbolic(writer, array.element, depth - 1);
                if (array.key) |key| {
                    writer.print(": {s}]", .{try typed.surfaceTypeName(self.allocator, key, self.catalog.records)}) catch return error.OutOfMemory;
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
    fn namedVariantCall(self: *Checker, invocation: Call) Error!bool {
        const owner = invocation.owner orelse return false;
        if (self.active.contains(self.src.text(owner))) return false;
        return variant_calls.caseFielded(self.src, self.catalog, owner, invocation.name, self.sink);
    }
    fn call(self: *Checker, input_call: Call, span: source.Span) Error!Symbolic {
        if (try self.specialCall(input_call, span)) |value| {
            // `debug` takes `sep=` and `end=` (its own check, `debugCall`).
            const debug = input_call.owner == null and std.mem.eql(u8, self.src.text(input_call.name), "debug");
            const named = debug or std.mem.eql(u8, self.src.text(input_call.name), "Cell") or keywordSort(self, input_call) or std.mem.eql(u8, self.src.text(input_call.name), "sorted");
            if (!named and !try self.namedVariantCall(input_call)) try call_arguments.positional(input_call, self.sink);
            return value;
        }
        const resolved = try self.resolveCall(input_call);
        const function = try self.callTarget(resolved, input_call.name);
        const signature = function.signature;
        const invocation = try call_arguments.bind(self.field_arena.allocator(), self.src, self.program.nodes.items, resolved, signature, self.sink);
        if (function.policy.conversion) return self.sink.fail(eUnsupported, span, "generic conversions still need abstract checking");
        if (invocation.type_arguments.len != 0 and invocation.type_arguments.len != signature.type_parameters.len) return self.sink.fail(diagnostic.generic_arity, span, "explicit type argument count does not match generic parameters");
        if (invocation.arguments.len != signature.parameters.len) return self.sink.fail("E_ARITY", span, "argument count does not match function parameters");
        var provider: constraint_lookup.Provider = .{ .program = self.program, .src = self.src, .names = self.module_names };
        const required = try requirements.resolveBounds(self.allocator, self.src, signature.type_parameters, self.sink, provider.lookup());
        defer requirements.deinitResolved(self.allocator, required);
        const arguments = try self.allocator.alloc(Symbolic, required.len);
        defer self.allocator.free(arguments);
        const inferred = invocation.type_arguments.len == 0 and required.len != 0;
        const actuals = if (inferred) try self.inferCall(invocation, function, arguments, span) else null;
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
        const success = try self.substituted(signature.return_type, signature.type_parameters, arguments);
        return if (signature.failure_type) |failure| try self.resultType(success, try self.substituted(failure, signature.type_parameters, arguments), span) else success;
    }
    fn inferredRequirement(self: *Checker, argument: Symbolic, parameter: requirements.Parameter, argument_span: source.Span) Error!void {
        const satisfies = switch (argument) {
            .length, .length_parameter => parameter.constant_length,
            .parameter => |index| self.parameters[index].requirements.implies(parameter.requirements),
            .concrete => |builtin| parameter.requirements.accepts(builtin, self.catalog.records),
            .callback, .array, .nominal => supportsSet(argument, parameter.requirements, self.parameters, self.catalog),
        };
        if (!satisfies and argument == .concrete and parameter.requirements.contains(.codec)) {
            if (try @import("codec_form.zig").refusal(self.allocator, argument.concrete, self.catalog.records)) |text|
                return self.sink.failRelated(@import("codec_form.zig").code, argument_span, text, .{ .span = parameter.name, .message = "the `codec` bound is declared here" });
        }
        if (!satisfies) return self.sink.failRelated(
            eArgument,
            argument_span,
            "type argument does not satisfy the callee's declared requirements",
            .{ .span = parameter.name, .message = "required type parameter declared here" },
        );
    }
    fn inferCall(self: *Checker, invocation: Call, function: ast.Function, arguments: []Symbolic, span: source.Span) Error![]Symbolic {
        const signature = function.signature;
        var inference: @import("generic_inference.zig").Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = invocation.name };
        if (self.expected_types.get(span)) |expected| try inference.matchResult(signature.return_type, signature.failure_type, expected);
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
            if (position == 0) try self.refuseListsContains(function, invocation, actual.*, span);
            try inference.matchArgument(parameter.ty, actual.*, self.program.nodes.items[@backingInt(input)].span);
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
                    actual = .{ .name = function.name, .parameters = function.signature.parameters, .return_type = function.signature.return_type };
                    concrete = true;
                },
                else => {},
            }
            const provided = actual orelse return self.sink.fail(eArgument, operation.name, "forwarded type does not promise the required operation");
            if (provided.parameters.len != operation.parameters.len)
                return self.sink.fail(eArgument, operation.name, "forwarded operation arity does not match the contract");
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
    /// Explicit byte literals have the managed bytes type; array contexts keep
    /// their fixed-octet representation, as in concrete expression checking.
    fn byteLiteral(self: *Checker, node: ast.Node) Error!Symbolic {
        if (self.expected_types.get(node.span)) |expected| {
            if (symbolic.array(expected, self.catalog.records) != null) return self.arrayType(node.data.bytes.len, .{ .concrete = .u8 });
        }
        // The AST already distinguishes byte and text literals; grouping can
        // extend the source span without changing the literal's byte identity.
        return .{ .concrete = self.catalog.names.get("bytes").? };
    }
    fn expression(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const before = self.temporary_results;
        self.expression_depth += 1;
        defer self.expression_depth -= 1;
        errdefer self.temporary_results = before;
        const result = try self.expressionValue(id);
        // Private lowering nodes may share a source anchor with another value.
        // Only an original syntax expression supplies this source type fact.
        if (@backingInt(id) < self.original_nodes and typeDependent(result)) {
            if (self.type_dependence) |spans| try spans.append(self.allocator, self.program.nodes.items[@backingInt(id)].span);
        }
        if (dictionary_views.symbolicKind(self.catalog, result)) |kind| try dictionary_views.validateKind(Checker, self, id, kind);
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
    fn dynamicFixedArray(self: *Checker, input: ast.NodeId, target: Symbolic, span: source.Span) Error!Symbolic {
        const value = try self.expression(input);
        if (self.shapes().collectionKind(value) != .list)
            return self.sink.fail("E_TYPE", span, "runtime FixedArray conversion requires a growable array");
        const shape = try self.arrayShape(target, span);
        try self.compatible(try self.collectionElement(value, span), shape.element, span);
        const failure = try self.shapes().nominal(self.catalog.templates.store.?.index.names.get(@import("frontend_type_names.zig").fixed_length_error).?, &.{});
        return self.resultType(target, failure, span);
    }
    fn fixedConstructor(self: *Checker, node: ast.Node) Error!?Symbolic {
        const invocation = node.data.call;
        for (self.program.types.expressions.applications) |application| {
            if (application.span.start != invocation.name.start or application.span.end != invocation.name.end) continue;
            if (!std.mem.eql(u8, self.src.text(application.name), fixed_array_name)) return null;
            if (invocation.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "FixedArray construction requires one explicit array literal");
            const input = self.program.nodes.items[@backingInt(invocation.arguments[0])];
            if (input.data != .list_literal) {
                const converted = try self.dynamicFixedArray(invocation.arguments[0], try self.ty(application.span), node.span);
                return converted;
            }
            const checked = try self.fixedArrayLiteral(node, input.data.list_literal, try self.ty(application.span));
            return checked;
        }
        return null;
    }
    fn expressionValue(self: *Checker, id: ast.NodeId) Error!Symbolic {
        var node = self.program.nodes.items[@backingInt(id)];
        if (node.data == .call) if (try @import("record_calls.zig").lower(self.field_arena.allocator(), self.src, self.catalog, self.program.nodes.items, node.data.call, self.sink)) |record| {
            node.data = record.data;
        };
        try self.enter(node.span);
        defer self.depth -= 1;
        return switch (node.data) {
            .format_field => |field| try self.formattedField(field.value, node.span),
            .synthetic_name => |name| try self.syntheticValue(name, node.span),
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
            .buffer_operation => |operation| try self.bufferValue(operation, node.span),
            .external_read => |read| try self.externalValue(read),
            .stand_in => return self.sink.fail(eUnsupported, node.span, "deterministic stand-in capabilities are not supported inside generic function bodies"),
            .environment_get => |get| try self.environmentValue(get),
            .acquire_resource => |acquire| try self.acquireResource(acquire),
            .accept_resource => |accept| try self.acceptResource(accept),
            .complete_resource => |complete| try self.completeResource(complete),
            .resource_io => |io| try self.resourceIo(io),
            .restrict_resource => |restrict| result: {
                const value = try self.expression(restrict.value);
                const value_type = try self.concreteValue(value, node.span);
                if (value_type.resourceKind() == null) return self.sink.fail("E_TYPE", node.span, "restriction requires filesystem or network capability authority");
                break :result value;
            },
            .call => |invocation| (try self.fixedConstructor(node)) orelse try self.call(invocation, node.span),
            .propagate => |operand| try self.propagateValue(operand, node.span),
            .bytes => try self.byteLiteral(node),
            .text => try self.concreteType(node.span),
            .membership => |membership| member: {
                const needle = try self.expression(membership.needle);
                const container = try self.expression(membership.container);
                const expected = if (self.shapes().collectionKind(container) == .dictionary) try self.shapes().collectionKey(container, node.span) else try self.collectionElement(container, node.span);
                try self.compatible(needle, expected, node.span);
                const values_view = dictionary_views.symbolicKind(self.catalog, container) == .values;
                if (self.shapes().collectionKind(container) == .list or values_view) try repetition.symbolicMembership(Checker, self, node, symbolic.supports(expected, .equality, self.parameters, self.catalog), values_view);
                break :member .{ .concrete = .bool };
            },
            .dictionary_literal => |entries| try self.dictionaryLiteral(node, entries),
            .unit => try self.surfaceUnit(node),
            .boolean => .{ .concrete = .bool },
            .integer => |span| try self.numericLiteral(span, false),
            .unary => |unary| try self.unaryValue(unary),
            .binary => |operation| try self.binary(operation),
            .record => |record| try self.recordValue(record, node.span),
            .variant => |variant| try self.variantValue(variant, node.span),
            .field_assignment => try self.fieldAssignment(node),
            .index_assignment => try self.indexAssignment(node),
            .list_literal => |inputs| try self.listLiteral(node, inputs),
            .set_literal => |inputs| try self.setLiteral(node, inputs),
            .format => |parts| try self.formatValue(parts, node.span),
            .comprehension => |each| try self.comprehensionValue(each, node.span),
            .gather => |gather| try self.gatherValue(gather, node.span),
            .list_operation => |operation| try self.listOperation(node, operation),
            .method_call => try self.listMethod(node),
            .slice => try self.listSlice(node),
            .replace => |replacement| result: {
                const base = try self.expression(replacement.base);
                const shape = try self.arrayIndex(base, replacement.index, node.span);
                if ((try self.requiresHandling(shape.element))) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, node.span, "replacement would drop a result-bearing element");
                try self.compatible(try self.expression(replacement.value), shape.element, node.span);
                break :result base;
            },
            .field => |field| result: {
                if (try self.enumMember(field, node.span)) |value| break :result value;
                const base = try self.expression(field.base);
                const shape = try self.shapes().requireRecord(base, node.span, false);
                const index = try self.shapes().memberIndex(shape, field.name);
                for (shape.fields, 0..) |other, i| {
                    if (i != index and (try self.requiresHandling(other.ty.?))) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, node.span, "projection would drop another result-bearing field");
                }
                break :result shape.fields[index].ty.?;
            },
            .length => |input| result: {
                const base = try self.borrowList(input);
                if (dictionary_views.symbolicKind(self.catalog, base)) |kind| if (kind != .item) break :result .{ .concrete = .i64 };
                if (self.shapes().managed(base)) break :result .{ .concrete = .i64 };
                _ = try self.arrayShape(base, node.span);
                if ((try self.requiresHandling(base))) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, node.span, "length would drop result-bearing elements");
                break :result .{ .concrete = .i64 };
            },
            .index => |access| result: {
                const base = try self.borrowList(access.base);
                if (self.shapes().managed(base)) {
                    if (self.shapes().collectionKind(base) == .dictionary) {
                        try self.compatible(try self.expression(access.index), try self.shapes().collectionKey(base, node.span), node.span);
                    } else {
                        try self.supports(try self.expression(access.index), .integer, node.span);
                        try negative_index.checkSyntax(Checker, self, access.index, false);
                    }
                    // The concrete checker types `text[i]` and `data[i]` as an
                    // octet, an `int` (sema_operators.checkValueIndex); a borrowed
                    // str view keeps the element type of its collection.
                    if (self.shapes().collectionKind(base)) |kind| {
                        if (kind == .bytes or kind == .string) break :result .{ .concrete = .i64 };
                    }
                    break :result try self.collectionElement(base, node.span);
                }
                const shape = try self.arrayIndex(base, access.index, node.span);
                if (shape.length != 1 and (try self.requiresHandling(shape.element))) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, node.span, "indexing would drop other result-bearing elements");
                break :result shape.element;
            },
            .cast => |cast| try self.integerCast(cast, node.span),
            // A tuple value is checked element-wise against its schema, and a
            // conditional with the same condition and arm agreement rules as an
            // ordinary function body.
            .tuple => |elements| try self.tupleValue(node.span, elements),
            .conditional => |conditional| try self.conditionalValue(node, conditional),
            // The marker preserves the symbolic type; its writable-owner
            // permission and overlap remain per concrete instance (M4).
            .mut_argument => |inner| try self.borrowList(inner),
            // `own` transfers its operand, including genuine Result-list
            // obligations. Pass the expected type through the marker so
            // contextual constructors keep the same typing in every position.
            // Core judges eligibility in each concrete specialization.
            .own_argument => |inner| if (self.expected_types.get(node.span)) |expected|
                try self.expressionExpected(inner, expected)
            else
                try self.expression(inner),
            .variant_test => |test_node| blk: {
                if (test_node.binds) return self.sink.fail(variant_is.binding_code, node.span, variant_is.binding_message);
                _ = try self.statement(test_node.check);
                break :blk .{ .concrete = .bool };
            },
            .match_expression => |match| blk: {
                const previous = self.match_yield;
                defer self.match_yield = previous;
                self.match_yield = .{ .value = self.expected_types.get(node.span) };
                _ = try self.matchValue(.{ .value = match.value, .arms = match.arms }, node.span);
                const result = self.match_yield.?.value orelse return self.sink.fail(eMatchYield, node.span, "match expressions were removed; use a match statement whose arms assign a named result or return");
                const migration = @import("control_expression_migration.zig");
                if (migration.nestedSelection(self.program, node)) break :blk result;
                const spelling = try @import("control_expression_symbolic.zig").symbolicSpelling(self.allocator, self.src, node.span, result, self.parameters, self.catalog);
                break :blk migration.reject(self.src, self.program, self.sink, node, spelling);
            },
        };
    }
    /// A fixed-width cast accepts a concrete float or an integer-constrained operand.
    fn integerCast(self: *Checker, cast: @FieldType(@FieldType(ast.Node, "data"), "cast"), span: source.Span) Error!Symbolic {
        const operand = try self.expression(cast.value);
        const target = try self.ty(cast.ty);
        if (!self.isFloat(operand)) try self.supports(operand, .integer, span);
        try self.supports(target, .integer, cast.ty);
        return target;
    }
    /// `value_if_true if condition else value_if_false` inside a template body:
    /// the condition is bool, both arms agree on one symbolic type, and only the
    /// chosen arm runs, so the value carries the then arm's type.
    fn conditionalValue(self: *Checker, node: ast.Node, conditional: @FieldType(@FieldType(ast.Node, "data"), "conditional")) Error!Symbolic {
        const condition = try self.expressionExpected(conditional.condition, .{ .concrete = .bool });
        try self.compatible(condition, .{ .concrete = .bool }, self.program.nodes.items[@backingInt(conditional.condition)].span);
        const facts = try self.option_facts.snapshot(self.field_arena.allocator());
        defer self.option_facts.restore(facts);
        const expected = self.expected_types.get(node.span);
        try self.assumeOption(conditional.condition, true);
        const then_value = if (expected) |ty_value| try self.expressionExpected(conditional.then_value, ty_value) else try self.expression(conditional.then_value);
        self.option_facts.restore(facts);
        try self.assumeOption(conditional.condition, false);
        const else_value = try self.expressionExpected(conditional.else_value, expected orelse then_value);
        if (expected) |ty_value| {
            try self.compatible(then_value, ty_value, self.program.nodes.items[@backingInt(conditional.then_value)].span);
            try self.compatible(else_value, ty_value, self.program.nodes.items[@backingInt(conditional.else_value)].span);
        } else try self.same(else_value, then_value, self.program.nodes.items[@backingInt(conditional.else_value)].span);
        const migration = @import("control_expression_migration.zig");
        if (migration.nestedSelection(self.program, node)) return then_value;
        const spelling = try @import("control_expression_symbolic.zig").symbolicSpelling(self.allocator, self.src, node.span, then_value, self.parameters, self.catalog);
        return migration.reject(self.src, self.program, self.sink, node, spelling);
    }
    fn externalValue(self: *Checker, read: @FieldType(@FieldType(ast.Node, "data"), "external_read")) Error!Symbolic {
        const success: typed.Type = if (read.kind == .clock) .i64 else .u64;
        const result = try self.operationResult(read.ty, success, "E_EXTERNAL_RESULT");
        const authority: typed.Type = if (read.kind == .clock) .clock_cap else .random_cap;
        try self.compatible(try self.expression(read.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(read.capability)].span);
        return result;
    }
    fn byteInput(self: *Checker, input: ast.NodeId, code: []const u8) Error!void {
        const span = self.program.nodes.items[@backingInt(input)].span;
        const value_type = try self.expression(input);
        if (!provider_shapes.bytes(value_type, self.catalog.records)) return self.sink.fail(code, span, "input requires a fixed u8 array");
    }
    fn environmentValue(self: *Checker, get: @FieldType(@FieldType(ast.Node, "data"), "environment_get")) Error!Symbolic {
        const result = try self.ty(get.ty);
        if (try provider_shapes.payload(self.shapes(), result, .environment, get.ty) == null) return self.sink.fail("E_ENVIRONMENT_RESULT", get.ty, "environment result requires bytes, length and present success fields with int error");
        try self.compatible(try self.expression(get.capability), .{ .concrete = .environment_cap }, self.program.nodes.items[@backingInt(get.capability)].span);
        try self.byteInput(get.name, "E_ENVIRONMENT_NAME");
        return result;
    }
    fn acquireResource(self: *Checker, acquire: @FieldType(@FieldType(ast.Node, "data"), "acquire_resource")) Error!Symbolic {
        const result = try self.ty(acquire.ty);
        const shape = try self.resultShape(result, acquire.ty, diagnostic.resource_result);
        const kind = provider_shapes.resource(shape.ok_type, self.catalog.records) orelse return self.sink.fail(diagnostic.resource_result, acquire.ty, "acquisition success must be a resource");
        if (!symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(diagnostic.resource_result, acquire.ty, "acquisition error must be int");
        // FR5a: a raw network request is the standard library's own encoding, as in a concrete body.
        if (kind == .network and !self.trustedSource(acquire.ty)) return self.sink.fail("E_INTERNAL_NAME", acquire.ty, @import("sema_shared.zig").raw_network_message);
        const authority: typed.Type = if (kind == .filesystem) .filesystem_cap else .network_cap;
        try self.compatible(try self.expression(acquire.capability), .{ .concrete = authority }, self.program.nodes.items[@backingInt(acquire.capability)].span);
        const request_type = try self.expression(acquire.request);
        const owned_bytes = if (request_type == .concrete) typed.acquisitionBytes(request_type.concrete, self.catalog.records) else false;
        if (!provider_shapes.bytes(request_type, self.catalog.records) and !owned_bytes)
            return self.sink.fail("E_RESOURCE_REQUEST", self.program.nodes.items[@backingInt(acquire.request)].span, "request requires a fixed byte array or owned byte buffer");
        return result;
    }
    fn acceptResource(self: *Checker, accept: @FieldType(@FieldType(ast.Node, "data"), "accept_resource")) Error!Symbolic {
        const result = try self.ty(accept.ty);
        const shape = try self.resultShape(result, accept.ty, diagnostic.resource_result);
        if (provider_shapes.resource(shape.ok_type, self.catalog.records) != .network) return self.sink.fail(diagnostic.resource_result, accept.ty, "acceptance success must be a network resource");
        if (!symbolic.same(shape.error_type, .{ .concrete = .i64 }, self.catalog)) return self.sink.fail(diagnostic.resource_result, accept.ty, "acceptance error must be int");
        const node = self.program.nodes.items[@backingInt(accept.value)];
        if (node.data != .name) return self.sink.fail(eResourceType, node.span, "acceptance requires a named resource binding");
        const owner = try self.local(node.data.name);
        const owner_type = try self.concreteValue(owner.ty, node.span);
        if (typed.resourceKind(owner_type, self.catalog.records) != .network) return self.sink.fail(eResourceType, node.span, "acceptance requires a network resource binding");
        try self.requireResultAvailable(node.data.name);
        return result;
    }
    fn completeResource(self: *Checker, complete: @FieldType(@FieldType(ast.Node, "data"), "complete_resource")) Error!Symbolic {
        const result = try self.ty(complete.ty);
        const fields = (try provider_shapes.payload(self.shapes(), result, .completion, complete.ty)) orelse return self.sink.fail(
            "E_COMPLETION_RESULT",
            complete.ty,
            "completion requires bool success and an error record containing the resource and int code",
        );
        try self.compatible(try self.expression(complete.value), fields[0].?, self.program.nodes.items[@backingInt(complete.value)].span);
        return result;
    }
    fn resourceIo(self: *Checker, io: @FieldType(@FieldType(ast.Node, "data"), "resource_io")) Error!Symbolic {
        if (io.value) |input| {
            const span = self.program.nodes.items[@backingInt(input)].span;
            const value_type = try self.expression(input);
            const dynamic = value_type == .concrete and typed.byteString(value_type.concrete, self.catalog.records);
            if (!dynamic and !provider_shapes.bytes(value_type, self.catalog.records))
                return self.sink.fail("E_RESOURCE_BYTES", span, "write input must be bytes or a fixed u8 array");
        }
        const owner = try self.local(io.owner);
        const owner_type = try self.concreteValue(owner.ty, io.owner);
        _ = typed.resourceKind(owner_type, self.catalog.records) orelse return self.sink.fail(eResourceType, io.owner, "I/O requires an owned resource value binding");
        try self.requireWritableBinding(io.owner, false);
        try self.requireResultAvailable(io.owner);
        const result = try self.ty(io.ty);
        if (io.kind == .write) {
            _ = try self.operationResult(io.ty, .u64, "E_RESOURCE_IO_RESULT");
        } else {
            const valid = try provider_shapes.payload(self.shapes(), result, .read, io.ty) != null;
            if (!valid) return self.sink.fail("E_RESOURCE_IO_RESULT", io.ty, "read result must contain the required bytes/length/eof fields and int error");
        }
        return result;
    }
    /// Inspection never settles a named pending list's aggregate obligation.
    fn borrowList(self: *Checker, id: ast.NodeId) Error!Symbolic {
        const node = self.program.nodes.items[@backingInt(id)];
        if (node.data == .name) if (self.active.get(self.src.text(node.data.name))) |slot| {
            const binding = self.locals.items[slot];
            if (self.shapes().collectionKind(binding.ty) == .list and try self.requiresHandling(binding.ty)) {
                try self.requireResultAvailable(node.data.name);
                return binding.ty;
            }
        };
        const value = try self.expression(id);
        if (self.shapes().collectionKind(value) == .list and try self.requiresHandling(value))
            return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, node.span, "bind the pending Result list before inspecting it; acknowledge the remaining elements explicitly");
        return value;
    }
    fn checkPendingOperation(self: *Checker, owner: Symbolic, kind: BufferKind, span: source.Span) Error!void {
        if (self.shapes().collectionKind(owner) == .list and try self.requiresHandling(owner)) try self.pendingListOperation(kind, span);
    }
    fn pendingListOperation(self: *Checker, kind: BufferKind, span: source.Span) Error!void {
        switch (kind) {
            .append, .pop, .pop_at, .exchange, .copy, .read, .length, .capacity, .iteration_check => {},
            else => return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, span, "this operation would implicitly discard or copy pending Results; handle elements or explicitly discard the whole list"),
        }
    }
    /// Inspect a named Result-bearing value without settling its obligation.
    fn requireResultAvailable(self: *Checker, span: source.Span) Error!void {
        const binding = try self.local(span);
        if (try self.requiresHandling(binding.ty) and !binding.ownership.available) return self.sink.failOwnershipTransfer(
            .{ .code = "E_RESULT_CONSUMED", .rule = .L1 },
            span,
            binding.name,
            binding.ownership.transfer_span,
        );
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
    fn bufferValue(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "buffer_operation"), span: source.Span) Error!Symbolic {
        if (operation.kind == .view or operation.kind == .borrow_view) return self.refuseBorrowView(span, operation.owner, operation.arguments, operation.kind);
        const owner = try self.local(operation.owner);
        if (operation.kind.mutates()) try self.requireWritableBinding(operation.owner, false);
        try self.requireResultAvailable(operation.owner);
        if (self.shapes().collectionKind(owner.ty) == .list and try self.requiresHandling(owner.ty))
            try self.pendingListOperation(operation.kind, operation.owner);
        if (operation.kind == .copy) return self.collectionOperation(owner.ty, .{ .kind = .copy, .inputs = operation.arguments, .span = operation.owner });
        if (!self.shapes().managed(owner.ty)) return self.sink.fail(eListType, operation.owner, "operation requires a managed collection value binding");
        const shape = (try self.shapes().container(owner.ty, operation.owner)) orelse return self.sink.fail(eListType, operation.owner, "operation requires a managed collection value binding");
        const element = shape.element;
        if (operation.kind == .read) try self.supports(element, .storable, operation.owner);
        for (operation.arguments, 0..) |input, index| {
            const writes_element = index == 1 and (operation.kind == .write or operation.kind == .exchange);
            const value = if (operation.kind == .append or writes_element) try self.expressionExpected(input, element) else try self.expression(input);
            const at = self.program.nodes.items[@backingInt(input)].span;
            if (operation.kind == .append or writes_element) try self.compatible(value, element, at) else try self.supports(value, .integer, at);
        }
        try self.requireResultAvailable(operation.owner);
        if (operation.kind == .pop or operation.kind == .pop_at or operation.kind == .exchange) return element;
        if (operation.kind.mutates()) return .{ .concrete = .unit };
        const success: Symbolic = if (operation.kind == .read) element else .{ .concrete = .u64 };
        return self.symbolicOperationResult(null, success, eListType);
    }
    fn resultShape(self: *Checker, value: Symbolic, span: source.Span, code: []const u8) Error!symbolic.ResultShape {
        return (try self.shapes().matchResult(value, span)) orelse self.sink.fail(code, span, "operation requires a declared result type");
    }
    /// F-57: `try` on an Option in a function that does not return an Option, with what is true for its result.
    fn refuseOptionTry(self: *Checker, span: source.Span) Error {
        const output = try self.shapes().matchResult(self.result, span);
        const optional = if (output) |shape| (try self.shapes().matchOption(shape.ok_type, span)) != null else false;
        return self.sink.fail(eTryReturn, span, bind_or_else.optionTryMessage(output != null, optional));
    }
    fn propagateValue(self: *Checker, operand: ast.NodeId, span: source.Span) Error!Symbolic {
        const temporaries = self.temporary_results;
        const value = try self.expression(operand);
        if (try self.shapes().matchResult(value, span)) |input| {
            const output = try self.resultShape(self.result, span, eTryReturn);
            // The error converts implicitly when exactly one case of the enclosing
            // union carries it, the concrete path's `typed.errorCaseFit` rule.
            // Distinct type parameters still stay distinct.
            if (!symbolic.same(input.error_type, output.error_type, self.catalog) and
                !try self.wrappingErrorCase(output.error_type, input.error_type, .{ .form = .try_, .span = span }))
                try self.same(input.error_type, output.error_type, span);
            try self.requireHandledAt(0, span, .try_failure);
            if (temporaries != 0) return self.sink.failOwnership(.{ .code = "E_RESULT_PROPAGATION", .rule = .L1 }, span, "propagation could drop an already evaluated result temporary");
            return input.ok_type;
        }
        if (try self.shapes().matchOption(value, span)) |input| {
            // OPTION-TRY-3: a propagated `None` carries no payload, so the
            // enclosing Option's element need not match the operand's.
            _ = (try self.shapes().matchOption(self.result, span)) orelse return self.refuseOptionTry(span);
            try self.requireHandled(0, span);
            if (temporaries != 0) return self.sink.failOwnership(.{ .code = "E_RESULT_PROPAGATION", .rule = .L1 }, span, "propagation could drop an already evaluated result temporary");
            return input.element;
        }
        return self.sink.fail("E_TRY_TYPE", span, "try requires a declared result or option");
    }
    /// Whether exactly one case of the symbolic union `container` carries `payload`: the symbolic
    /// form of the concrete path's `typed.errorCaseFit`, so `try` and `fail` can convert a narrower
    /// error into the enclosing union inside an uninstantiated template body. Several fitting
    /// cases are refused (`E_ERROR_CASE_AMBIGUOUS`) here when the types are known at the
    /// declaration; a case that fits only for some instances is refused at that instance.
    fn wrappingErrorCase(self: *Checker, container: Symbolic, payload: Symbolic, conversion: Conversion) Error!bool {
        const failures = @import("frontend_failures.zig");
        if (container == .concrete and payload == .concrete) {
            const fit = typed.errorCaseFit(self.catalog.records, container.concrete, payload.concrete);
            if (fit.count > 1) return failures.refuseAmbiguous(self.allocator, self.sink, self.src, self.catalog.records, .{
                .form = conversion.form,
                .container = container.concrete,
                .payload = payload.concrete,
                .fit = fit,
                .span = conversion.span,
                .spelling = failures.unionSpelling(self.program.functions[self.function_index].signature),
                .value = conversion.value,
            });
            return fit.count == 1;
        }
        const kind = self.shapes().kind(container) orelse return false;
        if (kind != .variants) return false;
        const shape = try self.shapes().schema(container, conversion.span);
        var fitting: std.ArrayList(symbolic.Field) = .empty;
        defer fitting.deinit(self.allocator);
        for (shape.fields) |field| {
            if (try self.caseCarries(field, payload, conversion.span)) try fitting.append(self.allocator, field);
        }
        if (fitting.items.len > 1) return self.refuseSymbolicAmbiguity(shape.fields, fitting.items, payload, conversion);
        return fitting.items.len == 1;
    }
    /// Whether the first fitting case is the one the compiler would have chosen for every instance: no case declared before it
    /// can carry the error for some instance (a payload of the union's own type parameter against a concrete error, or the
    /// reverse). Only then does naming it repair every instance and not just those where the cases coincide.
    fn firstIsCertain(all: []const symbolic.Field, first: symbolic.Field, payload: Symbolic) bool {
        for (all) |field| {
            if (std.mem.eql(u8, field.name, first.name)) return true;
            const declared = field.ty orelse continue;
            if (declared == .concrete and payload == .concrete) continue;
            return false;
        }
        return true;
    }
    /// Refuse a conversion that several cases of a generic union carry for every instance, with the message and the repair the
    /// concrete refusal has (`failures.refuse`): the fitting cases in declaration order, and for `fail value` the first of them
    /// built through the union's bare name, which takes its type arguments from the expected type, when it is certain.
    fn refuseSymbolicAmbiguity(self: *Checker, all: []const symbolic.Field, fitting: []const symbolic.Field, payload: Symbolic, conversion: Conversion) Error {
        const failures = @import("frontend_failures.zig");
        const signature = self.program.functions[self.function_index].signature;
        var names: std.Io.Writer.Allocating = .init(self.allocator);
        defer names.deinit();
        const shown = @min(fitting.len, 4);
        for (fitting[0..shown], 0..) |field, i| {
            const separator: []const u8 = if (i == 0) "" else if (i + 1 == fitting.len) " and " else ", ";
            names.writer.print("{s}{s}", .{ separator, field.name }) catch return error.OutOfMemory;
        }
        if (fitting.len > shown) names.writer.print(" and {d} more", .{fitting.len - shown}) catch return error.OutOfMemory;
        const first = fitting[0];
        const wrapped = if (first.fielded) (try self.shapes().schema(first.ty orelse return error.InternalError, conversion.span)).fields else &.{};
        const payload_name: ?[]const u8 = switch (payload) {
            .parameter => |index| self.src.text(signature.type_parameters[index].name),
            .concrete => |concrete| try typed.surfaceTypeName(self.allocator, concrete, self.catalog.records),
            else => null,
        };
        return failures.refuse(self.allocator, self.sink, self.src, .{
            .form = conversion.form,
            .span = conversion.span,
            .spelling = if (firstIsCertain(all, first, payload)) failures.unionSpelling(signature) else null,
            .value = conversion.value,
            .every_instance = true,
        }, .{
            .union_name = if (signature.failure_type) |clause| self.src.text(clause) else "the error union",
            .payload_name = payload_name,
            .list = try self.allocator.dupe(u8, names.written()),
            .count = fitting.len,
            .first = first.name,
            .field = if (wrapped.len != 0) wrapped[0].name else null,
        });
    }
    /// Whether one symbolic case carries `payload`: as its payload, or as the one field of its record.
    fn caseCarries(self: *Checker, field: symbolic.Field, payload: Symbolic, span: source.Span) Error!bool {
        const declared = field.ty orelse return false;
        if (symbolic.same(declared, payload, self.catalog)) return true;
        if (!field.fielded) return false;
        const record = try self.shapes().schema(declared, span);
        if (record.fields.len != 1) return false;
        const element = record.fields[0].ty orelse return false;
        return symbolic.same(element, payload, self.catalog);
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
        const labels = try self.field_arena.allocator().alloc([]const u8, record.fields.len);
        for (record.fields, labels) |field, *label| label.* = field.name;
        const sites = try self.field_arena.allocator().alloc(source.Span, values.len);
        for (values, sites) |value, *site| site.* = self.program.nodes.items[@backingInt(value)].span;
        try @import("frontend_named_fields.zig").require(self.sink, span, "E_NAMED_FIELDS", .{ .labels = labels, .sites = sites, .names = names });
        var initializers: std.ArrayList(ast.FieldInit) = .empty;
        const supplied = try self.allocator.alloc(bool, record.fields.len);
        defer self.allocator.free(supplied);
        @memset(supplied, false);
        for (values, 0..) |value, source_index| {
            const keyword = if (names.len == 0) null else names[source_index];
            const index = if (keyword) |name| try self.shapes().memberIndex(record, name) else return self.sink.fail("E_NAMED_FIELDS", span, "variant payload fields must be supplied by name");
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
    /// The tag an arm takes: the success or failure case of a bind-or-else, otherwise the case its pattern names.
    fn armTag(self: *Checker, value: Symbolic, variants: symbolic.Schema, arm: ast.MatchArm) Error!usize {
        if (arm.alternatives.role == .named) return self.patternTag(value, variants, arm.ty, arm.name, arm.internal.labelled);
        return bind_or_else.roleTag(variants.fields, arm.alternatives.role) orelse error.InternalError;
    }
    fn patternTag(self: *Checker, value: Symbolic, variants: symbolic.Schema, type_span: source.Span, name: source.Span, labelled: bool) Error!usize {
        if (type_span.start != type_span.end) {
            // A labelled field's qualified case keeps its qualifier (see `sema_statements.patternTag`).
            if (labelled) try self.same(try self.variantTypeFrom(type_span, value), value, type_span) else try self.qualifiedCase(value, type_span, name);
            return self.shapes().memberIndex(variants, name);
        }
        const canonical = @import("prelude.zig").caseName(self.src.text(name));
        for (variants.fields, 0..) |candidate, index| if (std.mem.eql(u8, candidate.name, canonical)) return index;
        return self.sink.fail("E_UNKNOWN_VARIANT", name, "case is not a variant of the matched type");
    }
    /// Refuse a case pattern spelled with its type, as the concrete check does
    /// (`sema_statements.qualifiedCase`). The repair drops the qualifier only when the
    /// qualifier names the matched value's own type; otherwise the refusal has no repair.
    fn qualifiedCase(self: *Checker, value: Symbolic, type_span: source.Span, name: source.Span) Error!void {
        const span: source.Span = .{ .start = type_span.start, .end = name.end };
        for (self.sink.items.items) |item| {
            if (item.span.start == span.start and std.mem.eql(u8, item.code, "E_PATTERN_QUALIFIED")) return;
        }
        const message = "a case pattern names its case alone; the matched value's type already says which type it is";
        if (try self.qualifierNamesValue(value, type_span)) return self.sink.appendFix(
            .{ .code = "E_PATTERN_QUALIFIED", .span = span, .message = message },
            .{ .span = .{ .start = type_span.start, .end = name.start }, .text = "" },
        );
        try self.sink.items.append(self.sink.allocator, .{
            .code = "E_PATTERN_QUALIFIED",
            .span = span,
            .message = "a case pattern names its case alone; this qualifier does not name the matched type",
        });
    }
    /// Whether a pattern qualifier names the matched value's own type, exactly.
    fn qualifierNamesValue(self: *Checker, value: Symbolic, type_span: source.Span) Error!bool {
        const declaration = try variant_calls.templateDeclaration(self.src, self.catalog, type_span, self.sink);
        if (declaration) |id| return value == .nominal and value.nominal.declaration == id;
        return symbolic.same(try self.ty(type_span), value, self.catalog);
    }
    /// Whether `arm` is the wildcard: a synthetic arm (`internal.wildcard`) or, by its text as in the concrete check
    /// (`sema_statements.wildcard`), a `case _` written in the source (FR82), which `sourceWildcard` checks first.
    fn wildcardArm(self: *Checker, arm: ast.MatchArm, variants: symbolic.Schema, last: bool, seen: []const bool) Error!bool {
        if (arm.internal.wildcard) return true;
        if (!sema_statements.wildcard(self.src, arm)) return false;
        try self.sourceWildcard(arm, variants, last, seen);
        return true;
    }
    /// A `case _` written in the source, refused as `sema_statements.statementMatch` and `wildcardArms` refuse it: it is
    /// the last arm, some variant has no earlier arm, and none of those carries a payload that needs handling.
    fn sourceWildcard(self: *Checker, arm: ast.MatchArm, variants: symbolic.Schema, last: bool, seen: []const bool) Error!void {
        if (!last) return self.sink.fail("E_WILDCARD_ARM", arm.name, "`case _` must be the last arm of a match");
        var covered: usize = 0;
        for (variants.fields, seen) |variant, named| {
            if (named) continue;
            if (variant.ty) |payload| if (try self.requiresHandling(payload)) return self.sink.failOwnership(
                .{ .code = eResultDiscard, .rule = .L1 },
                arm.name,
                "`case _` would drop a result-bearing payload; give that variant its own arm",
            );
            covered += 1;
        }
        if (covered == 0) return self.sink.fail("E_WILDCARD_ARM", arm.name, "every variant already has an arm, so `case _` is unreachable");
    }
    fn wildcardBody(self: *Checker, arm: ast.MatchArm, span: source.Span, state: struct { incoming_len: usize, seen: []const bool, continuation: *?[]Pending }) Error!bool {
        if (std.mem.allEqual(bool, state.seen, true)) return true;
        const continuation = state.continuation;
        const returns = try self.statement(arm.body);
        if (!returns) {
            if (continuation.*) |pending| {
                try self.samePending(pending, span, eResultPath);
                self.intersectInitialization(pending);
            } else continuation.* = try self.pendingState(state.incoming_len);
        }
        return returns;
    }
    fn requirePatternLabels(self: *Checker, arm: ast.MatchArm, shape: symbolic.Schema) Error!void {
        const labels = try self.field_arena.allocator().alloc([]const u8, shape.fields.len);
        for (shape.fields, labels) |field, *label| label.* = field.name;
        const sites = try self.field_arena.allocator().alloc(source.Span, arm.bindings.len);
        for (arm.bindings, sites, 0..) |binding, *site, position| {
            site.* = if (position < arm.payload_patterns.len) arm.payload_patterns[position].pattern.span else binding orelse arm.name;
        }
        try @import("frontend_named_fields.zig").requirePattern(self.sink, self.src, arm.name, "E_NAMED_PATTERN", .{ .labels = labels, .sites = sites, .names = arm.binding_names });
    }
    // twin-drift-ok: the concrete check reads typed records and this one reads symbolic schemas; the two must stay separate
    /// A bare name in a fielded case's payload that names one of the case's fields binds that
    /// field, as `sema_statements.nameFieldPayloads` does for a concrete match. The label is
    /// written into the arm, so the labelled pattern path checks it.
    fn nameFieldPayloads(self: *Checker, variants: symbolic.Schema, input: []const ast.MatchArm) Error![]const ast.MatchArm {
        var output: ?[]ast.MatchArm = null;
        for (input, 0..) |arm, arm_index| {
            if (arm.payload_patterns.len == 0 or arm.binding_names.len != arm.payload_patterns.len) continue;
            const tag = canonicalCaseTag(self.src, variants, arm.name) orelse continue;
            if (!variants.fields[tag].fielded) continue;
            const payload = variants.fields[tag].ty orelse continue;
            const shape = try self.shapes().schema(payload, arm.name);
            var fields: ?[]ast.PatternField = null;
            var labels: ?[]?source.Span = null;
            for (arm.payload_patterns, 0..) |field, position| {
                if (field.name != null or field.pattern.data != .binding) continue;
                const binding = field.pattern.data.binding orelse continue;
                if (!symbolicDeclares(shape, self.src.text(binding))) continue;
                if (fields == null) {
                    fields = try self.field_arena.allocator().dupe(ast.PatternField, arm.payload_patterns);
                    labels = try self.field_arena.allocator().dupe(?source.Span, arm.binding_names);
                }
                fields.?[position].name = binding;
                labels.?[position] = binding;
            }
            const named = fields orelse continue;
            if (output == null) output = try self.field_arena.allocator().dupe(ast.MatchArm, input);
            output.?[arm_index].payload_patterns = named;
            output.?[arm_index].binding_names = labels.?;
        }
        return output orelse input;
    }
    // twin-drift-ok: the concrete check reads typed records and this one reads symbolic schemas; the two must stay separate
    /// A rest marker, `case atom(text, ..)`, stands for a discard of every field the pattern does not name, written into
    /// the arm as `sema_statements.restFields` does for a concrete match.
    fn restFields(self: *Checker, variants: symbolic.Schema, input: []const ast.MatchArm) Error![]const ast.MatchArm {
        var output: ?[]ast.MatchArm = null;
        for (input, 0..) |arm, arm_index| {
            if (!pattern_alternatives.spellsRest(arm)) continue;
            const tag = canonicalCaseTag(self.src, variants, arm.name) orelse continue;
            const filled = try self.fillRest(variants.fields[tag], arm);
            if (output == null) output = try self.field_arena.allocator().dupe(ast.MatchArm, input);
            output.?[arm_index] = filled;
        }
        return output orelse input;
    }
    fn fillRest(self: *Checker, case_field: symbolic.Field, arm: ast.MatchArm) Error!ast.MatchArm {
        const memory = self.field_arena.allocator();
        var filled = arm;
        var fields = try memory.dupe(ast.PatternField, arm.payload_patterns);
        var labels = try memory.dupe(?source.Span, arm.binding_names);
        var bindings = try memory.dupe(?source.Span, arm.bindings);
        if (arm.alternatives.rest and !(arm.alternatives.bare and case_field.ty == null)) {
            const payload = case_field.ty orelse return self.sink.fail(ePatternPayload, arm.name, "this case has no payload, so there are no fields for `..` to ignore");
            if (case_field.fielded) {
                const shape = try self.shapes().schema(payload, arm.name);
                for (shape.fields) |declared| {
                    var named = false;
                    for (arm.payload_patterns) |field| {
                        if (field.name) |label| named = named or std.mem.eql(u8, self.src.text(label), declared.name);
                    }
                    if (named) continue;
                    fields = try pattern_alternatives.appendField(memory, fields, pattern_alternatives.discardOf(declared.span));
                    labels = try pattern_alternatives.appendSpan(memory, labels, declared.span);
                    bindings = try pattern_alternatives.appendSpan(memory, bindings, null);
                }
            } else if (arm.payload_patterns.len == 0) {
                fields = try pattern_alternatives.appendField(memory, fields, .{ .pattern = .{ .span = arm.name, .data = .{ .binding = null } } });
                labels = try pattern_alternatives.appendSpan(memory, labels, null);
                bindings = try pattern_alternatives.appendSpan(memory, bindings, null);
            }
        }
        for (fields) |*field| {
            if (field.pattern.data != .variant) continue;
            const slot = (try self.slotValue(case_field, field.*)) orelse continue;
            field.pattern = try self.fillNested(field.pattern, slot, 0);
        }
        filled.payload_patterns = fields;
        filled.binding_names = labels;
        filled.bindings = bindings;
        return filled;
    }
    /// The type a payload field of a case holds: the declared field a label names, or the single payload.
    fn slotValue(self: *Checker, case_field: symbolic.Field, field: ast.PatternField) Error!?Symbolic {
        const payload = case_field.ty orelse return null;
        if (!case_field.fielded) return payload;
        const label = field.name orelse return null;
        const shape = try self.shapes().schema(payload, label);
        for (shape.fields) |declared| {
            if (std.mem.eql(u8, declared.name, self.src.text(label))) return declared.ty;
        }
        return null;
    }
    fn fillNested(self: *Checker, pattern: ast.Pattern, slot: Symbolic, depth: usize) Error!ast.Pattern {
        if (pattern.data != .variant or depth > 32) return pattern;
        const nested = pattern.data.variant;
        if (!nested.rest and !pattern_alternatives.nestedSpellsRest(nested.fields, 0)) return pattern;
        const kind = self.shapes().kind(slot) orelse return pattern;
        if (kind != .variants and kind != .result and kind != .enumeration) return pattern;
        const variants = try self.shapes().schema(slot, nested.name);
        const tag = canonicalCaseTag(self.src, variants, nested.name) orelse return pattern;
        const memory = self.field_arena.allocator();
        var fields = try memory.dupe(ast.PatternField, nested.fields);
        if (nested.rest) {
            const payload = variants.fields[tag].ty orelse return self.sink.fail(ePatternPayload, nested.name, "this case has no payload, so there are no fields for `..` to ignore");
            if (variants.fields[tag].fielded) {
                const shape = try self.shapes().schema(payload, nested.name);
                for (shape.fields) |declared| {
                    var named = false;
                    for (nested.fields) |field| {
                        if (field.name) |label| named = named or std.mem.eql(u8, self.src.text(label), declared.name);
                    }
                    if (!named) fields = try pattern_alternatives.appendField(memory, fields, pattern_alternatives.discardOf(declared.span));
                }
            } else if (nested.fields.len == 0) {
                fields = try pattern_alternatives.appendField(memory, fields, .{ .pattern = .{ .span = nested.name, .data = .{ .binding = null } } });
            }
        }
        for (fields) |*field| {
            if (field.pattern.data != .variant) continue;
            const inner = (try self.slotValue(variants.fields[tag], field.*)) orelse continue;
            field.pattern = try self.fillNested(field.pattern, inner, depth + 1);
        }
        return .{ .span = pattern.span, .data = .{ .variant = .{ .ty = nested.ty, .name = nested.name, .fields = fields } } };
    }
    /// Check every arm's qualifier before arms are grouped (see `sema_statements.statementMatch`).
    fn checkQualifiers(self: *Checker, value: Symbolic, arms: []const ast.MatchArm) Error!void {
        for (arms) |arm| {
            if (arm.ty.start == arm.ty.end) continue;
            if (arm.internal.labelled) try self.same(try self.variantTypeFrom(arm.ty, value), value, arm.ty) else try self.qualifiedCase(value, arm.ty, arm.name);
        }
    }
    /// A literal arm is checked on concrete functions only; a generic body refuses it for now.
    fn refuseLiteralArms(self: *Checker, arms: []const ast.MatchArm) Error!void {
        for (arms) |arm| if (arm.literals.len != 0) return self.sink.fail("E_LITERAL_ARM", arm.name, "a literal arm is not checked in a generic function yet; move the match into a function with concrete types");
    }
    /// `case leaf | blank:` is a list of constants to the parser and a list of cases over an enum or a union.
    fn listedArms(self: *Checker, value: Symbolic, arms: []const ast.MatchArm) Error![]const ast.MatchArm {
        const kind = self.shapes().kind(value) orelse return arms;
        if (kind != .variants and kind != .result and kind != .enumeration) return arms;
        return pattern_alternatives.splitNames(self.field_arena.allocator(), self.program.nodes.items, arms);
    }
    /// The labels of a pattern over a case with named fields (`shape`), after `case NAME:` with no pattern is refused.
    fn requireFieldPattern(self: *Checker, arm: ast.MatchArm, payload: Symbolic, shape: symbolic.Schema) Error!void {
        if (case_payload.bare(self.src, arm)) return self.refuseBareCase(arm, payload, shape);
        try self.requirePatternLabels(arm, shape);
    }
    /// A single-payload arm that binds nothing where it must: a bare `else:` over a Result (F-60), or `case NAME:` over a case
    /// that carries a payload (FR14, `case_payload.zig`). Any other arm passes.
    fn refuseUnbound(self: *Checker, arm: ast.MatchArm, payload: ?Symbolic, operand: ast.NodeId) Error!void {
        try self.refuseBareElse(arm, payload, operand);
        const carried = payload orelse return;
        if (!case_payload.bare(self.src, arm)) return;
        return case_payload.refuse(self.src, self.sink, ePatternPayload, arm, .{
            .payload = try self.symbolicText(carried),
            .droppable = !(try self.requiresHandling(carried)),
        });
    }
    /// FR14: refuse `case NAME:` over a case with named fields (`shape`), naming the fields and the two patterns, as the
    /// concrete check does (`case_payload.zig`), under the code this check has always given that arm.
    fn refuseBareCase(self: *Checker, arm: ast.MatchArm, payload: Symbolic, shape: symbolic.Schema) Error {
        const names = try self.allocator.alloc([]const u8, shape.fields.len);
        const types = try self.allocator.alloc([]const u8, shape.fields.len);
        for (shape.fields, names, types) |field, *name, *spelled| {
            name.* = field.name;
            spelled.* = if (field.ty) |field_type| try self.symbolicText(field_type) else "?";
        }
        return case_payload.refuse(self.src, self.sink, ePatternPayload, arm, .{
            .fields = try case_payload.Fields.of(self.allocator, names, types),
            .droppable = !(try self.requiresHandling(payload)),
        });
    }
    /// F-60: refuse a bare `else:` over a Result, whose failure case carries `payload`; any other arm passes.
    fn refuseBareElse(self: *Checker, arm: ast.MatchArm, payload: ?Symbolic, operand: ast.NodeId) Error!void {
        const failure = payload orelse return;
        if (!bind_or_else.bareElse(self.src, arm)) return;
        return bind_or_else.refuseBareElse(self.src, self.sink, arm, .{
            .operand = self.src.text(self.program.nodes.items[@backingInt(operand)].span),
            .failure = if (failure == .concrete) try typed.surfaceTypeName(self.allocator, failure.concrete, self.catalog.records) else "its error type",
            .called = null,
            .droppable = !(try self.requiresHandling(failure)),
            .call = self.program.nodes.items[@backingInt(operand)].data == .call,
        });
    }
    fn matchValue(self: *Checker, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), span: source.Span) Error!bool {
        const previous_exclusive = self.exclusive_match;
        const synthetic = self.program.nodes.items[@backingInt(match.value)].data == .synthetic_name;
        const exclusive = match.exclusive or (synthetic and previous_exclusive);
        self.exclusive_match = exclusive;
        defer self.exclusive_match = previous_exclusive;
        for (match.arms) |arm| try self.invalidateOptions(arm.body);
        const match_facts = try self.option_facts.snapshot(self.field_arena.allocator());
        defer self.option_facts.restore(match_facts);
        const value = try self.rawOptionExpression(match.value);
        const listed_arms = try self.listedArms(value, match.arms);
        try refuseLiteralArms(self, listed_arms);
        const variants = try self.shapes().requireVariants(value, span);
        try bind_or_else.requireOperand(self.sink, listed_arms, bind_or_else.roleTag(variants.fields, .success) != null, self.program.nodes.items[@backingInt(match.value)].span);
        try self.checkQualifiers(value, listed_arms);
        const named_arms = try self.nameFieldPayloads(variants, listed_arms);
        const rest_arms = try self.restFields(variants, named_arms);
        try pattern_alternatives.requireSameBindings(self.field_arena.allocator(), self.sink, self.src, rest_arms, exclusive);
        const normalized_arms = try frontend_patterns.normalizeInArena(Checker, self, rest_arms, self.pattern_memory orelse self.field_arena.allocator());
        const seen = try self.allocator.alloc(bool, variants.fields.len);
        defer self.allocator.free(seen);
        @memset(seen, false);
        const incoming = try self.pendingState(self.locals.items.len);
        defer self.allocator.free(incoming);
        var continuation: ?[]Pending = null;
        defer if (continuation) |state| self.allocator.free(state);
        var terminated = true;
        for (normalized_arms, 0..) |arm, arm_index| {
            self.option_facts.restore(match_facts);
            self.restorePending(incoming);
            if (try self.wildcardArm(arm, variants, arm_index + 1 == normalized_arms.len, seen)) {
                terminated = try self.wildcardBody(arm, span, .{ .incoming_len = incoming.len, .seen = seen, .continuation = &continuation }) and terminated;
                @memset(seen, true);
                continue;
            }
            const tag = try self.armTag(value, variants, arm);
            if (seen[tag]) return self.sink.fail("E_DUPLICATE_ARM", arm.name, "variant has more than one match arm");
            seen[tag] = true;
            const payload = variants.fields[tag].ty;
            const before = self.locals.items.len;
            defer self.endScope(before);
            if (payload != null and variants.fields[tag].fielded) {
                const shape = try self.shapes().schema(payload.?, arm.name);
                try self.requireFieldPattern(arm, payload.?, shape);
                if (arm.bindings.len != shape.fields.len) return self.sink.fail(ePatternPayload, arm.name, "a named-field case pattern binds exactly one name per field, using `_` to discard one");
                var all_discard = true;
                for (arm.bindings) |binding| if (binding != null) {
                    all_discard = false;
                    break;
                };
                if (all_discard) {
                    if (try self.requiresHandling(payload.?)) return self.sink.failOwnership(.{ .code = eResultDiscard, .rule = .L1 }, arm.name, "nested result payload requires explicit handling");
                } else for (arm.bindings, 0..) |binding, position| {
                    const label = if (arm.binding_names.len != 0) arm.binding_names[position] else null;
                    const field_index = if (label) |name| try self.shapes().memberIndex(shape, name) else position;
                    const field_type = shape.fields[field_index].ty orelse return error.InternalError;
                    if (binding) |at| {
                        try self.bindPattern(arm, position, at, field_type, exclusive);
                    } else if (try self.requiresHandling(field_type)) return self.sink.failOwnership(.{ .code = eResultDiscard, .rule = .L1 }, arm.name, "discarding a result-bearing field requires a binding and explicit handling");
                }
            } else {
                const discards_payload = arm.bindings.len == 1 and arm.bindings[0] == null;
                if (discards_payload and payload != null and (try self.requiresHandling(payload.?))) return self.sink.failOwnership(.{ .code = eResultDiscard, .rule = .L1 }, arm.name, "nested result payload requires explicit handling");
                try self.refuseUnbound(arm, payload, match.value);
                if (arm.bindings.len > 1 or (payload != null) != (arm.bindings.len == 1)) return self.sink.fail(ePatternPayload, arm.name, "payload cases require a binding or discard; empty cases take neither");
                if (arm.bindings.len == 1) if (arm.bindings[0]) |binding| try self.bindPattern(arm, 0, binding, payload.?, exclusive);
            }
            const returns = try self.statement(arm.body);
            try bind_or_else.requireLeaves(self.sink, arm, returns, bind_or_else.leaveSpan(self.program.statements.items, arm.body));
            if (!returns) {
                try self.requireHandled(before, arm.name);
                if (continuation) |state| {
                    try self.samePending(state, span, eResultPath);
                    self.intersectInitialization(state);
                } else continuation = try self.pendingState(incoming.len);
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
        if (shape.key) |key| try self.compatible(index, .{ .concrete = key }, span) else {
            try self.supports(index, .integer, span);
            try negative_index.checkSyntax(Checker, self, input, false);
        }
        return shape;
    }
    fn recordValue(self: *Checker, record: @FieldType(@FieldType(ast.Node, "data"), "record"), span: source.Span) Error!Symbolic {
        const result = try self.ty(record.name);
        // `T()` of an `extern type` is its null handle and has no fields (`record_calls.zig`).
        if (result == .concrete and @import("c_abi.zig").foreignHandle(result.concrete, self.catalog.records)) return result;
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
            if (!complete and (try self.requiresHandling(shape.fields[index].ty.?))) return self.sink.failOwnership(.{ .code = eResultOperation, .rule = .L1 }, field.name, "update would drop a result-bearing field");
            try self.compatible(try self.expressionExpected(field.value, shape.fields[index].ty.?), shape.fields[index].ty.?, field.name);
        }
        if (complete) for (seen) |present| {
            if (!present) return self.sink.fail(if (table_key != null) "E_INCOMPLETE_TABLE" else "E_MISSING_FIELD", span, "named construction must initialize every entry");
        };
    }
    /// Diagnose sequence repetition assignment before ordinary numeric compatibility.
    fn removedRepetitionAssignment(self: *Checker, assignment: @FieldType(@FieldType(ast.Statement, "data"), "assignment"), target: Symbolic) Error!bool {
        if (assignment.op != .mul or !self.repeatable(target)) return false;
        const count = try self.expression(assignment.value);
        try self.supports(count, .integer, assignment.op_span);
        const kind = self.shapes().collectionKind(target).?;
        const module: []const u8 = if (kind == .string) "strings" else if (kind == .bytes) "byte_builder" else "lists";
        const span: source.Span = .{ .start = assignment.name.start, .end = self.program.nodes.items[@backingInt(assignment.value)].span.end };
        const known_integer = count == .concrete and count.concrete.isInteger();
        if (kind == .list and known_integer and count.concrete != .u64) {
            try repetition.listAssignmentFix(Checker, self, span, assignment.name, self.program.nodes.items[@backingInt(assignment.value)].span);
        } else if (count == .concrete and count.concrete == .u64) {
            try repetition.unsignedAssignmentFix(Checker, self, span, .{ .name = assignment.name, .count = self.program.nodes.items[@backingInt(assignment.value)].span, .module = module });
        } else {
            const replacement = if (kind != .list and count == .concrete and count.concrete == .i64) try std.fmt.allocPrint(self.allocator, "{s} = {s}.repeat({s}, {s})", .{
                self.src.text(assignment.name), module, self.src.text(assignment.name), self.src.text(self.program.nodes.items[@backingInt(assignment.value)].span),
            }) else null;
            try repetition.removed(Checker, self, span, .{ .code = "E_REPETITION_REMOVED", .message = "sequence repetition assignment was removed; use explicit library words or loops", .module = module }, replacement);
        }
        self.option_facts.forget(self.active.get(self.src.text(assignment.name)).?);
        return true;
    }

    /// PY-REPEAT-1: the sequence a `*` repeats when one side is a `str`,
    /// `bytes` or list and the other an integer, or null for any other `*`.
    fn repeated(self: *Checker, left: Symbolic, right: Symbolic) ?Symbolic {
        const integer_left = symbolic.supports(left, .integer, self.parameters, self.catalog);
        const integer_right = symbolic.supports(right, .integer, self.parameters, self.catalog);
        if (integer_right and self.repeatable(left)) return left;
        if (integer_left and self.repeatable(right)) return right;
        return null;
    }
    fn repeatable(self: *Checker, value: Symbolic) bool {
        const kind = self.shapes().collectionKind(value) orelse return false;
        return kind == .string or kind == .bytes or kind == .list;
    }
    /// PY-CHAIN-1: a comparison chain checks every operand once, in source
    /// order, and each adjacent pair under its own operator.
    fn chain(self: *Checker, last: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!Symbolic {
        var links: std.ArrayList(@FieldType(@FieldType(ast.Node, "data"), "binary")) = .empty;
        defer links.deinit(self.allocator);
        var head = last;
        while (head.chained) {
            try links.append(self.allocator, head);
            head = self.program.nodes.items[@backingInt(head.left)].data.binary;
        }
        try links.append(self.allocator, head);
        std.mem.reverse(@FieldType(@FieldType(ast.Node, "data"), "binary"), links.items);
        const first = try self.comparisonPeers(links.items[0], null);
        _ = try self.operands(links.items[0], first.left, first.right);
        var left = first.right;
        for (links.items[1..]) |link| {
            const peers = try self.comparisonPeers(link, left);
            try self.refusePresenceLink(.{ .op = link.op, .left = symbolicChainPreviousOperand(self, link.left), .right = link.right, .left_value = peers.left, .right_value = peers.right, .certain = false });
            _ = try self.operands(link, peers.left, peers.right);
            left = peers.right;
        }
        return .{ .concrete = .bool };
    }
    /// One comparison link the symbolic checker has already typed, ready for
    /// its presence refusal.
    const PresenceLink = struct {
        op: ast.BinaryOp,
        left: ast.NodeId,
        right: ast.NodeId,
        left_value: Symbolic,
        right_value: Symbolic,
        certain: bool,
    };
    /// Refuse a removed integer bit operator in a template body, naming the
    /// prelude operation with both operand texts.
    fn refuseBitOperator(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary"), builtin: []const u8) Error!Symbolic {
        const left_span = self.program.nodes.items[@backingInt(operation.left)].span;
        const right_span = self.program.nodes.items[@backingInt(operation.right)].span;
        const span = source.Span.join(left_span, right_span);
        const text = try bit_operators.callText(self.allocator, builtin, self.src.text(left_span), self.src.text(right_span));
        return self.sink.failFix(bit_operators.code, operation.op_span, bit_operators.message, .{ .span = span, .text = text });
    }
    /// Refuse `value == None` and `value != None` wherever a symbolic comparison
    /// chain puts them. A chain link has no certain edit, because `is None`
    /// between two comparisons would re-parse as a chain.
    fn refusePresenceLink(self: *Checker, link: PresenceLink) Error!void {
        if (link.op != .eq and link.op != .ne) return;
        const left_none = self.noneKeyword(link.left);
        if (left_none == self.noneKeyword(link.right)) return;
        const other = if (left_none) link.right else link.left;
        const other_value = if (left_none) link.right_value else link.left_value;
        const other_span = self.program.nodes.items[@backingInt(other)].span;
        if (try self.shapes().matchOption(other_value, other_span) == null) return;
        const span = source.Span.join(self.program.nodes.items[@backingInt(link.left)].span, self.program.nodes.items[@backingInt(link.right)].span);
        const message = option_spelling.comparison_message;
        const certain_edit = link.certain and !try self.transfers(other_value) and !option_spelling.adjacentComparison(self.src, span);
        if (!certain_edit) return self.sink.fail(option_spelling.comparison_code, span, message);
        const text = try option_spelling.testText(self.allocator, self.src.text(other_span), link.op == .ne);
        return self.sink.failFix(option_spelling.comparison_code, span, message, .{ .span = span, .text = text });
    }
    /// Whether `id` is the `None` keyword, not the `()` unit literal that
    /// shares the same untyped shape.
    fn noneKeyword(self: *Checker, id: ast.NodeId) bool {
        const node = self.program.nodes.items[@backingInt(id)];
        return node.data == .unit and std.mem.eql(u8, self.src.text(node.span), "None");
    }
    /// The operand a chained link compares against its own right operand: the
    /// last operand of the chain to its left.
    fn symbolicChainPreviousOperand(self: *Checker, left: ast.NodeId) ast.NodeId {
        var current = left;
        while (true) {
            const node = self.program.nodes.items[@backingInt(current)];
            if (node.data != .binary) return current;
            if (node.data.binary.chained) {
                current = node.data.binary.left;
                continue;
            }
            return node.data.binary.right;
        }
    }
    /// Whether `id` is `None`, `Some(...)`, `Ok(...)` or `Err(...)` written with no
    /// expected type: an operand whose own type comes from the value it meets.
    fn awaitsPeerType(self: *Checker, id: ast.NodeId) Error!bool {
        const node = self.program.nodes.items[@backingInt(id)];
        if (self.expected_types.get(node.span) != null) return false;
        return switch (node.data) {
            .unit => true,
            .call => |invocation| try self.awaitsConstructorType(invocation),
            else => false,
        };
    }
    fn awaitsConstructorType(self: *Checker, invocation: Call) Error!bool {
        if (invocation.owner != null or invocation.type_arguments.len != 0) return false;
        const name = self.src.text(invocation.name);
        const constructor = std.mem.eql(u8, name, "Some") or std.mem.eql(u8, name, "Ok") or std.mem.eql(u8, name, "Err");
        if (!constructor) return false;
        if (self.active.contains(name) or self.functions.contains(name)) return false;
        if (self.module_names) |names| if (try names.topLevel(invocation.name)) return false;
        return true;
    }
    /// Type an equality's contextual constructor from its peer. A chain passes
    /// its already checked shared operand, so no operand is checked twice.
    fn comparisonPeers(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary"), previous: ?Symbolic) Error!struct { left: Symbolic, right: Symbolic } {
        const equality = operation.op == .eq or operation.op == .ne;
        const left_awaits = previous == null and equality and try self.awaitsPeerType(operation.left);
        const right_awaits = equality and try self.awaitsPeerType(operation.right);
        const early_right = if (left_awaits and !right_awaits) try self.expression(operation.right) else null;
        const left = previous orelse if (early_right) |peer| try self.expressionExpected(operation.left, peer) else try self.expression(operation.left);
        const right = early_right orelse if (right_awaits and !left_awaits) try self.expressionExpected(operation.right, left) else try self.expression(operation.right);
        return .{ .left = left, .right = right };
    }
    /// Type a unary operation, keeping binary64 operands in their float domain.
    fn unaryValue(self: *Checker, unary: @FieldType(@FieldType(ast.Node, "data"), "unary")) Error!Symbolic {
        if (unary.op == .is_none) {
            const operand = try self.rawOptionExpression(unary.operand);
            _ = try self.optionElement(operand, unary.op_span);
            if (try self.transfers(operand)) return self.sink.fail("E_OPTION_TEST", unary.op_span, "use match for an Option carrying an owned value or checked Result");
            return .{ .concrete = .bool };
        }
        const child = self.program.nodes.items[@backingInt(unary.operand)];
        const operand: Symbolic = if (unary.op == .neg and child.data == .integer)
            try self.numericLiteral(child.data.integer, true)
        else
            try self.expression(unary.operand);
        if (unary.op == .neg) {
            if (!self.isFloat(operand)) try self.supports(operand, .integer, unary.op_span);
        } else if (float_intrinsics.floatwise(unary.op)) {
            try self.compatible(operand, self.floatType(), unary.op_span);
        } else try self.compatible(operand, .{ .concrete = if (unary.op == .not) .bool else .u64 }, unary.op_span);
        return operand;
    }
    fn binary(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary")) Error!Symbolic {
        if (operation.chained) return self.chain(operation);
        if (operation.op == .eq or operation.op == .ne) {
            const peers = try self.comparisonPeers(operation, null);
            try self.refusePresenceLink(.{ .op = operation.op, .left = operation.left, .right = operation.right, .left_value = peers.left, .right_value = peers.right, .certain = true });
            return self.operands(operation, peers.left, peers.right);
        }
        const left = try self.expression(operation.left);
        const short_circuit = operation.op == .logical_and or operation.op == .logical_or;
        const state = if (short_circuit) try self.pendingState(self.locals.items.len) else null;
        defer if (state) |snapshot| self.allocator.free(snapshot);
        const facts = if (short_circuit) try self.option_facts.snapshot(self.field_arena.allocator()) else null;
        defer if (facts) |saved| self.option_facts.restore(saved);
        if (short_circuit) try self.assumeOption(operation.left, operation.op == .logical_and);
        const right = try self.expression(operation.right);
        if (state) |snapshot| try self.samePending(snapshot, operation.op_span, eResultPath);
        return self.operands(operation, left, right);
    }
    /// The type one binary operator answers for two already checked operand types.
    fn operands(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), "binary"), left: Symbolic, right: Symbolic) Error!Symbolic {
        if (operation.op == .mul) if (self.repeated(left, right)) |repeats| {
            const sequence_left = self.repeatable(left);
            const count = if (sequence_left) right else left;
            const kind = self.shapes().collectionKind(repeats).?;
            try repetition.symbolicRepeat(Checker, self, operation, .{
                .sequence = if (sequence_left) operation.left else operation.right,
                .count = if (sequence_left) operation.right else operation.left,
                .module = if (kind == .string) "strings" else if (kind == .bytes) "byte_builder" else "lists",
                .exact_count = count == .concrete and count.concrete.isInteger(),
                .count_type = if (count == .concrete) count.concrete else .u64,
            });
            return repeats;
        };
        if (self.isFloat(left) or self.isFloat(right) or operation.op == .python_div) {
            if (!self.isFloat(left)) try self.supports(left, .integer, operation.op_span);
            if (!self.isFloat(right)) try self.supports(right, .integer, operation.op_span);
            return switch (operation.op) {
                .add, .sub, .mul, .div, .python_div, .floor_div, .floor_rem => self.floatType(),
                .eq, .ne, .lt, .le, .gt, .ge => .{ .concrete = .bool },
                else => self.sink.fail("E_FLOAT_OPERATION", operation.op_span, "float supports arithmetic and numeric comparison"),
            };
        }
        // `|`, `&` and `^` combine two sets (SET-OPERATORS-1) or were the
        // integer bit operators (PY-SET-OPS-1); any other operand is refused.
        const set_left = self.shapes().isSet(left);
        const integer_left = symbolic.supports(left, .integer, self.parameters, self.catalog);
        if (!set_left) if (set_lower.bitwiseSpelling(self.src.text(operation.op_span))) |builtin| {
            if (integer_left and symbolic.supports(right, .integer, self.parameters, self.catalog))
                return self.refuseBitOperator(operation, builtin);
            if (!integer_left) {
                const message = try std.fmt.allocPrint(self.sink.allocator, "`{s}` combines two sets or two integers (`{s}(a, b)`)", .{ self.src.text(operation.op_span), builtin });
                return self.sink.fail(set_lower.bitwise_code, operation.op_span, message);
            }
        };
        try self.compatible(right, left, operation.op_span);
        // The set operators build a fresh set or compare two (SET-OPERATORS-1).
        if (set_left) switch (operation.op) {
            .bit_or, .bit_and, .sub, .bit_xor => {
                return left;
            },
            .lt, .le, .gt, .ge => return .{ .concrete = .bool },
            else => {},
        };
        if (self.shapes().managed(left)) {
            if (operation.op == .eq or operation.op == .ne) return .{ .concrete = .bool };
            if (operation.op == .add and self.shapes().collectionKind(left) == .string) {
                return left;
            }
            const sequence = self.shapes().collectionKind(left) == .string or self.shapes().collectionKind(left) == .bytes;
            const ordering = operation.op == .lt or operation.op == .le or operation.op == .gt or operation.op == .ge;
            if (sequence and ordering) return .{ .concrete = .bool };
            if (operation.op == .add and self.shapes().collectionKind(left) == .list)
                return self.sink.fail("E_TEXT_OPERATOR", operation.op_span, "a generic body cannot add two lists yet; build `mut joined = copy(first)` and `lists.extend(mut joined, second)` instead");
            return self.sink.fail("E_TEXT_OPERATOR", operation.op_span, "collection supports equality; str and bytes also support `+` and `<`, `<=`, `>`, `>=`");
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
        for (statements, 0..) |id, position| {
            if (terminated) {
                const refused = try unreachable_repair.refusal(self.allocator, self.src, self.program.statements.items, statements, position, "statement follows an unconditional return");
                return self.sink.failRepaired("E_UNREACHABLE", self.program.statements.items[@backingInt(id)].span, refused.message, refused.fix);
            }
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
            if (!right) {
                try self.samePending(after, span, eResultPath);
                self.intersectInitialization(after);
            }
            self.restorePending(after);
        }
        return left and right;
    }
    fn statementBinding(self: *Checker, binding: @FieldType(@FieldType(ast.Statement, "data"), "binding")) Error!void {
        if (!binding.initialized) {
            const value = try self.ty(binding.annotation orelse return error.InternalError);
            try self.bind(binding.name, value, binding.mutable);
            self.locals.items[self.locals.items.len - 1].ownership = .{ .initialized = false };
        } else {
            const value = if (binding.annotation) |annotation| try self.expressionExpected(binding.value, try self.ty(annotation)) else try self.expression(binding.value);
            if (binding.annotation) |annotation| try self.compatible(value, try self.ty(annotation), annotation);
            const source_node = self.program.nodes.items[@backingInt(binding.value)];
            const pattern_mutable = if (source_node.data == .synthetic_name)
                self.locals.items[self.active.get(source_node.data.synthetic_name) orelse return error.InternalError].mutable
            else
                false;
            // A bind-or-else `adopt` binding replaces the arm's own binding of the same name.
            if (binding.adopt) _ = self.active.remove(self.src.text(binding.name));
            try self.bind(binding.name, value, binding.mutable or pattern_mutable);
        }
    }
    fn statementAssignment(self: *Checker, assignment: @FieldType(@FieldType(ast.Statement, "data"), "assignment")) Error!void {
        if (!self.active.contains(self.src.text(assignment.name))) return self.bindingDeclaration(assignment.name);
        try self.requireWritableBinding(assignment.name, assignment.op == .set);
        const target = &self.locals.items[self.active.get(self.src.text(assignment.name)).?];
        if (assignment.op != .set) try self.requireInitialized(target.*, assignment.name);
        if (try self.removedRepetitionAssignment(assignment, target.ty)) return;
        const value = try self.expressionExpected(assignment.value, target.ty);
        try self.compatible(value, target.ty, assignment.op_span);
        if (assignment.op != .set) try self.augmentedTarget(assignment.op, target.ty, assignment.op_span);
        if (try self.requiresHandling(target.ty)) {
            if ((try self.pendingObligation(target.*))) return self.sink.failOwnership(.{ .code = "E_RESULT_OVERWRITE", .rule = .L1 }, assignment.name, "assignment would overwrite an unhandled result");
            target.ownership.available = true;
            target.ownership.transfer_span = null;
        }
        target.ownership.initialized = true;
        self.option_facts.forget(self.active.get(self.src.text(assignment.name)).?);
    }
    fn statement(self: *Checker, id: ast.StatementId) Error!bool {
        const statement_value = self.program.statements.items[@backingInt(id)];
        try self.enter(statement_value.span);
        defer self.depth -= 1;
        switch (statement_value.data) {
            .gather_step => |step| {
                try self.gatherStep(step, statement_value.span);
                return false;
            },
            .block => |statements| return self.block(statements),
            .with_scope => return self.sink.fail(eUnsupported, statement_value.span, "`with` resource scopes are not supported inside generic function bodies"),
            .match => |match| return self.matchValue(match, statement_value.span),
            .fail => |value| return self.failValue(value, statement_value.span),
            .yield_value => |value| return self.yieldValue(value, statement_value.span),
            .ret => |value| {
                try self.returnValue(value, statement_value.span);
                return true;
            },
            .assertion => |claim| {
                const condition = try self.expression(claim.condition);
                try self.compatible(condition, .{ .concrete = .bool }, statement_value.span);
            },
            .binding => |binding| try self.statementBinding(binding),
            .assignment => |assignment| try self.statementAssignment(assignment),
            // `_ = expr` evaluates the value and releases it, settling a result obligation.
            .discard => |value| {
                const ty_value = try self.expression(value);
                if (statement_value.implicit_discard and !symbolic.same(ty_value, .{ .concrete = .unit }, self.catalog)) {
                    const code = "E_EXPLICIT_DISCARD_REQUIRED";
                    const message = "a standalone non-unit value requires `_ =` or result handling";
                    // Only a value known not to be a result gets the `_ = ` fix;
                    // a type parameter may be one at some specialization.
                    if (ty_value == .parameter) return self.sink.fail(code, statement_value.span, message);
                    if (try self.requiresHandling(ty_value)) return self.sink.failOwnership(.{ .code = code, .rule = .L1 }, statement_value.span, message);
                    const at = statement_value.span.start;
                    return self.sink.failFix(code, statement_value.span, message, .{ .span = .{ .start = at, .end = at }, .text = "_ = " });
                }
                if (ty_value == .parameter) try self.supports(ty_value, .storable, statement_value.span);
            },
            .branch => |branch| return self.branchValue(branch, statement_value.span),
            .for_each => |each| {
                try self.invalidateOptions(each.body);
                const loop_facts = try self.option_facts.snapshot(self.field_arena.allocator());
                defer self.option_facts.restore(loop_facts);
                const source_type = try self.borrowList(each.iterable);
                const view = dictionary_views.symbolicKind(self.catalog, source_type);
                const projected = view != null and view.? != .item;
                const owner = if (projected) try dictionary_views.symbolicOwner(self.shapes(), source_type, statement_value.span) else source_type;
                const fixed = self.walkableArray(owner);
                if (fixed == null and !self.shapes().managed(owner)) return self.sink.fail(eListType, statement_value.span, "iteration requires a collection, fixed array or dictionary view");
                const element = if (fixed) |shape| shape.element else try self.iterationElement(source_type, owner, statement_value.span);
                const first = self.locals.items.len;
                if (each.index_name != null and !each.enumerated) {
                    if (symbolic_shapes.tupleArity(self.catalog, element)) |arity| {
                        if (arity != 2) return self.sink.fail(eTupleArity, statement_value.span, try self.twoNameLoopMessage(arity));
                        try self.bind(each.index_name.?, symbolic_shapes.tupleElement(self.catalog, element, 0).?, false);
                        try self.bind(each.name, symbolic_shapes.tupleElement(self.catalog, element, 1).?, false);
                    } else {
                        if (dictionary_views.symbolicKind(self.catalog, element) != .item) return self.sink.fail("E_ITERATION", statement_value.span, "two iteration names require dictionary items, enumerate or zip");
                        const shape = try self.shapes().schema(element, statement_value.span);
                        try self.bind(each.index_name.?, shape.fields[0].ty.?, false);
                        try self.bind(each.name, shape.fields[1].ty.?, false);
                    }
                } else {
                    try self.bind(each.name, element, false);
                    if (each.index_name) |name| try self.bind(name, .{ .concrete = .i64 }, false);
                }
                defer self.endScope(first);
                const before = try self.pendingState(first);
                defer self.allocator.free(before);
                const previous = self.loop_pending;
                var loop_initialization: LoopInitialization = .{ .before = before };
                defer if (loop_initialization.exits) |exits| self.allocator.free(exits);
                self.loop_pending = &loop_initialization;
                defer self.loop_pending = previous;
                if (!try self.statement(each.body)) {
                    try self.requireHandled(first, statement_value.span);
                    try self.requireConstLoopState(statement_value.span);
                    try self.samePending(before, statement_value.span, diagnostic.result_loop);
                }
                self.finishLoopInitialization(true);
            },
            .for_range => |range| {
                try self.invalidateOptions(range.body);
                const loop_facts = try self.option_facts.snapshot(self.field_arena.allocator());
                defer self.option_facts.restore(loop_facts);
                const element: Symbolic = if (self.program.nodes.items[@backingInt(range.start)].data == .unit) .{ .concrete = .i64 } else try self.expression(range.start);
                try self.supports(element, .integer, range.name);
                try self.compatible(try self.expression(range.end), element, range.name);
                if (range.step) |step| try self.compatible(try self.expression(step), element, range.name);
                const first = self.locals.items.len;
                try self.bind(range.name, element, false);
                defer self.endScope(first);
                const before = try self.pendingState(self.locals.items.len);
                defer self.allocator.free(before);
                const previous = self.loop_pending;
                var loop_initialization: LoopInitialization = .{ .before = before };
                defer if (loop_initialization.exits) |exits| self.allocator.free(exits);
                self.loop_pending = &loop_initialization;
                defer self.loop_pending = previous;
                if (!try self.statement(range.body)) {
                    try self.requireConstLoopState(statement_value.span);
                    try self.samePending(before, statement_value.span, diagnostic.result_loop);
                }
                self.finishLoopInitialization(true);
            },
            .loop_exit => |continuing| {
                const loop = self.loop_pending orelse return self.sink.fail("E_LOOP_EXIT", statement_value.span, "break and continue require an enclosing loop");
                try self.requireHandled(loop.before.len, statement_value.span);
                try self.samePending(loop.before, statement_value.span, diagnostic.result_loop);
                if (continuing) try self.requireConstLoopState(statement_value.span);
                if (!continuing) {
                    if (loop.exits) |exits| {
                        self.intersectInitialization(exits);
                    } else loop.exits = try self.pendingState(loop.before.len);
                }
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
                var loop_initialization: LoopInitialization = .{ .before = before };
                defer if (loop_initialization.exits) |exits| self.allocator.free(exits);
                self.loop_pending = &loop_initialization;
                defer self.loop_pending = previous;
                try self.assumeOption(loop.condition, true);
                if (!try self.statement(loop.body)) {
                    try self.requireConstLoopState(statement_value.span);
                    try self.samePending(before, statement_value.span, diagnostic.result_loop);
                }
                const condition = self.program.nodes.items[@backingInt(loop.condition)];
                const always = condition.data == .boolean and condition.data.boolean;
                self.finishLoopInitialization(!always);
                return always and loop_initialization.exits == null;
            },
        }
        return false;
    }
};
/// Whether an abstract expression's type retains a source type or length
/// parameter. This is a typing fact; Core decides what a concrete marker means.
fn typeDependent(value: Symbolic) bool {
    return switch (value) {
        .parameter, .length_parameter => true,
        .length, .concrete => false,
        .array => |array| array.length_parameter != null or typeDependent(array.element),
        .nominal => |nominal| result: {
            for (nominal.arguments) |argument| if (typeDependent(argument)) break :result true;
            break :result false;
        },
        .callback => |callback| result: {
            if (typeDependent(callback.result)) break :result true;
            for (callback.parameters) |parameter| if (typeDependent(parameter)) break :result true;
            break :result false;
        },
    };
}

pub const TypeDependence = std.AutoHashMapUnmanaged(source.Span, void);

fn publishTypeDependence(allocator: std.mem.Allocator, output: ?*TypeDependence, spans: []const source.Span) error{OutOfMemory}!void {
    const facts = output orelse return;
    for (spans) |span| try facts.put(allocator, span, {});
}

fn supportsSet(value: Symbolic, required: requirements.Set, parameters: []const requirements.Parameter, catalog: Catalog) bool {
    inline for (std.meta.tags(requirements.Requirement)) |requirement| {
        if (required.contains(requirement) and !symbolic.supports(value, requirement, parameters, catalog)) return false;
    }
    return true;
}
const ReplayState = struct {
    allocator: std.mem.Allocator,
    sink: *diagnostic.Sink,
    calls: *std.ArrayList(generic_cache.Call),
    type_dependence: ?*TypeDependence = null,
};
/// Apply one retained direct result: its diagnostics, its type-dependent spans and
/// its recorded call edges. A callee is never scheduled from here, as a cold pass
/// schedules none, so a warm pass checks the same templates.
fn applyReplay(state: ReplayState, replay: generic_cache.Replay) error{OutOfMemory}!void {
    defer state.allocator.free(replay.notes);
    defer state.allocator.free(replay.edges);
    defer state.allocator.free(replay.type_dependence);
    try publishTypeDependence(state.allocator, state.type_dependence, replay.type_dependence);
    for (replay.notes) |note| try appendReplayedDiagnostic(state.sink, note);
    for (replay.edges) |edge| try state.calls.append(state.allocator, edge);
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
    const parameters = symbolic_shapes.normalizeRequirements(allocator, context.catalog, context.src, raw, context.sink) catch |err| switch (err) {
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

/// Resolve a declared borrow through Core's declaration authority using type
/// facts from the original template, preserving its contract in scalar instances.
pub fn declaredBorrow(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, catalog: Catalog, function: ast.Function, sink: *diagnostic.Sink) Error!typed.ReturnOrigin {
    if (function.signature.borrowing.len == 0) return .fresh;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const resolved = try resolveTemplate(.{ .allocator = a, .src = src, .program = program, .sink = sink, .module_names = catalog.module_names, .catalog = catalog }, function) orelse return error.SourceError;
    defer resolved.deinit(a);
    var work: usize = 0;
    const shapes: symbolic_shapes.Context = .{ .arena = &arena, .catalog = catalog, .src = src, .sink = sink, .parameters = resolved.parameters, .work = &work };
    const managed = try a.alloc(bool, function.signature.parameters.len);
    const concrete = try a.alloc(?typed.Type, function.signature.parameters.len);
    var seen: std.ArrayList(Symbolic) = .empty;
    for (function.signature.parameters, managed, concrete) |parameter, *fact, *known| {
        const declared = try shapes.declarationType(parameter.ty);
        known.* = switch (declared) {
            .concrete => |ty| ty,
            else => null,
        };
        // A nongeneric declaration's parameter types are all concrete: a collection or other nominal type resolves through
        // the catalog, so the authority judges a list or record source too (lane HC).
        if (known.* == null and function.signature.type_parameters.len == 0) known.* = try resolvedQuietly(a, src, catalog, parameter.ty);
        fact.* = try possiblyManaged(shapes, declared, &seen);
    }
    const result = if (function.signature.type_parameters.len == 0) try catalog.resolve(src, function.signature.return_type, sink) else null;
    const failure_managed = if (function.signature.failure_type) |failure|
        try possiblyManaged(shapes, try shapes.declarationType(failure), &seen)
    else
        false;
    return @import("core/borrow_contract.zig").declaration(allocator, src, function, .{
        .parameters = managed,
        .result = result,
        .records = catalog.records,
        .failure_managed = failure_managed,
        .parameter_types = concrete,
    }, sink);
}

/// The catalog's type for the spelling at `span`, or null when it does not resolve; its diagnostics are dropped, since the
/// declaration's own check reports them.
fn resolvedQuietly(a: std.mem.Allocator, src: source.Source, catalog: Catalog, span: source.Span) Error!?typed.Type {
    var quiet: diagnostic.Sink = .{ .allocator = a };
    return catalog.resolve(src, span, &quiet) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => null,
    };
}

fn possiblyManaged(shapes: symbolic_shapes.Context, value: Symbolic, seen: *std.ArrayList(Symbolic)) Error!bool {
    return switch (value) {
        .callback, .length, .length_parameter => false,
        .parameter => |index| !shapes.parameters[index].requirements.contains(.integer),
        .concrete => |ty| @import("return_borrow.zig").managed(shapes.catalog.records, ty),
        .array => |array| (array.length_parameter != null or array.length != 0) and try possiblyManaged(shapes, array.element, seen),
        .nominal => nominal: {
            if (shapes.managed(value) or shapes.kind(value) == .resource) break :nominal true;
            if (shapes.kind(value) == .domain or shapes.kind(value) == .enumeration) break :nominal false;
            // A recursive value closes through boxed storage. Phantom type
            // arguments alone do not create ownership: inspect actual fields.
            for (seen.items) |previous| if (symbolic.same(value, previous, shapes.catalog)) break :nominal true;
            try seen.append(shapes.arena.allocator(), value);
            defer _ = seen.pop();
            const shape = try shapes.schema(value, .{ .start = 0, .end = 0 });
            for (shape.fields) |field| if (field.ty) |child| if (try possiblyManaged(shapes, child, seen)) break :nominal true;
            break :nominal false;
        },
    };
}
/// Count a rejected abstract check without branching in the hot loop.
/// A private copy of the program's node and statement tables, which the bodies checked afresh append their lowerings to.
fn copyTables(allocator: std.mem.Allocator, program: ast.Program) error{OutOfMemory}!ast.Program {
    // The copy is a snapshot: a program whose bodies are filled on demand is complete before it is taken.
    try ast.ensureAll(program);
    var tables = program;
    tables.nodes = .fromOwnedSlice(try allocator.dupe(ast.Node, program.nodes.items));
    errdefer tables.nodes.deinit(allocator);
    tables.statements = .fromOwnedSlice(try allocator.dupe(ast.Statement, program.statements.items));
    return tables;
}

/// Count the copy of the tables in the symbolic session, when there is one.
fn noteTableCopy(symbolic_session: ?*generic_cache.Session) void {
    if (symbolic_session) |reuse| reuse.noteTableCopy();
}

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
    return checkWithCatalogCached(allocator, src, program, sink, catalog, .{});
}

/// What one abstract template check may take instead of checking a body: retained
/// direct results.
pub const Reuse = struct {
    symbolic: ?*generic_cache.Session = null,
    view_consumers: ?dictionary_views.Consumers = null,
    type_dependence: ?*TypeDependence = null,
};

fn deinitOwnedConsumers(allocator: std.mem.Allocator, reuse: Reuse, consumers: dictionary_views.Consumers) void {
    if (reuse.view_consumers == null) consumers.deinit(allocator);
}
/// Check symbolic bodies, reusing unchanged direct results from `symbolic`.
pub fn checkWithCatalogCached(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, catalog: Catalog, reuse_with: Reuse) Error!void {
    const symbolic_session = reuse_with.symbolic;
    const module_names = catalog.module_names;
    var has_work = program.types.constraints.len != 0;
    for (program.functions) |function| if (function.signature.type_parameters.len != 0) {
        has_work = true;
        break;
    };
    if (!has_work) return;
    const view_consumers = reuse_with.view_consumers orelse try dictionary_views.Consumers.init(allocator, src, program);
    defer deinitOwnedConsumers(allocator, reuse_with, view_consumers);
    var calls: std.ArrayList(generic_cache.Call) = .empty;
    defer calls.deinit(allocator);
    var type_dependence: std.ArrayList(source.Span) = .empty;
    defer type_dependence.deinit(allocator);
    var functions: FunctionMap = .empty;
    defer functions.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        const key = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try @import("function_identity.zig").localName(sink.allocator, src, function.policy.owner, function.name);
        const entry = try functions.getOrPut(allocator, key);
        if (entry.found_existing) return sink.fail("E_DUPLICATE_FUNCTION", function.name, "duplicate function declaration");
        entry.value_ptr.* = index;
    }
    // The templates, in declaration order: the only bodies this pass walks. A function without type parameters that a
    // template calls is not walked (see `callTarget`).
    var templates = try std.ArrayList(usize).initCapacity(allocator, program.functions.len);
    defer templates.deinit(allocator);
    for (program.functions, 0..) |function, index| {
        if (function.signature.type_parameters.len != 0) templates.appendAssumeCapacity(index);
    }
    var pattern_arena = std.heap.ArenaAllocator.init(allocator);
    defer pattern_arena.deinit();
    // Every body that is checked afresh appends its lowerings to one private copy of the module's tables, which
    // grows across bodies. A copy per body would make checking quadratic, and the caller's
    // lists must never be written (see `frontend_patterns.normalize`).
    // The copy is made when the first body is checked afresh: a template the symbolic cache serves reads and appends
    // nothing, and copying every node of the program before looking at one made an edit to a large program pay for all of it.
    var tables = program;
    var tables_private = false;
    defer if (tables_private) {
        tables.nodes.deinit(allocator);
        tables.statements.deinit(allocator);
    };
    var failed = false;
    for (templates.items) |index| {
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
            .program = tables,
            .view_consumers = view_consumers,
            .catalog = catalog,
            .calls = &calls,
            .function_index = index,
            .type_dependence = &type_dependence,
            .original_nodes = program.nodes.items.len,
            .pattern_memory = pattern_arena.allocator(),
            .sink = sink,
            .parameters = resolved.parameters,
            .result = undefined,
            .module_names = module_names,
            .functions = &functions,
            .owner = function.policy.owner,
        };
        // Keep what this body appended for the bodies after it, on every exit path.
        defer if (tables_private) {
            tables.nodes = checker.program.nodes;
            tables.statements = checker.program.statements;
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
        _ = declaredBorrow(checker.field_arena.allocator(), src, program, catalog, function, sink) catch |err| switch (err) {
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
                .calls = &calls,
                .type_dependence = reuse_with.type_dependence,
            }, replay);
            continue;
        };
        if (!tables_private) {
            tables = try copyTables(allocator, program);
            tables_private = true;
            checker.program = tables;
            noteTableCopy(symbolic_session);
        }
        const diag_start = sink.items.items.len;
        const edge_start = calls.items.len;
        const dependence_start = type_dependence.items.len;
        if (!try runFresh(&checker, function)) {
            failed = true;
            noteSymbolicFailure(symbolic_session, index);
            continue;
        }
        const dependent = type_dependence.items[dependence_start..];
        try publishTypeDependence(allocator, reuse_with.type_dependence, dependent);
        if (symbolic_session) |reuse| {
            _ = try reuse.record(index, .{
                .notes = sink.items.items[diag_start..],
                .edges = calls.items[edge_start..],
                .type_dependence = dependent,
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
            .view_consumers = view_consumers,
            .catalog = catalog,
            .calls = &calls,
            .function_index = 0,
            .sink = sink,
            .parameters = parameters,
            .result = undefined,
            .module_names = module_names,
            .functions = &functions,
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
    // Capability operations are checked at their typed use sites; no effect inference.
    // Publish only after the whole abstract graph passed. A rejected request
    // keeps its fresh direct results private to this session and frees them at
    // `deinit`; the durable store never inherits a pass that failed.
    // A check that kept a hole as a trap publishes nothing (see `Sink.trapped_holes`).
    if (symbolic_session) |reuse| if (sink.trapped_holes == 0) try reuse.publish();
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

/// The index of a case in a symbolic case set, by its canonical spelling.
fn canonicalCaseTag(src: source.Source, variants: symbolic.Schema, name: source.Span) ?usize {
    const canonical = @import("prelude.zig").caseName(src.text(name));
    for (variants.fields, 0..) |candidate, index| if (std.mem.eql(u8, candidate.name, canonical)) return index;
    return null;
}

/// Whether a symbolic record shape declares a field with this name.
fn symbolicDeclares(shape: symbolic.Schema, name: []const u8) bool {
    for (shape.fields) |field| if (std.mem.eql(u8, field.name, name)) return true;
    return false;
}

test "G2p the private tables are a copy that can be appended to, and a failure while copying leaks nothing" {
    const nodes = [_]ast.Node{.{ .span = .{ .start = 0, .end = 1 }, .data = .{ .integer = .{ .start = 0, .end = 1 } } }};
    const statements = [_]ast.Statement{.{ .span = .{ .start = 0, .end = 1 }, .data = .{ .discard = @fromBackingInt(0) } }};
    const program: ast.Program = .{ .nodes = .fromOwnedSlice(@constCast(&nodes)), .statements = .fromOwnedSlice(@constCast(&statements)), .functions = &.{} };
    var copied = try copyTables(std.testing.allocator, program);
    defer copied.nodes.deinit(std.testing.allocator);
    defer copied.statements.deinit(std.testing.allocator);
    try std.testing.expect(copied.nodes.items.ptr != program.nodes.items.ptr);
    try copied.nodes.append(std.testing.allocator, nodes[0]);
    try std.testing.expectEqual(@as(usize, 1), program.nodes.items.len);
    // The second table's copy fails: the first is released.
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 1 });
    try std.testing.expectError(error.OutOfMemory, copyTables(failing.allocator(), program));
}

// Construct the unavailable synthetic binding produced by nested-pattern lowering.
// This probes the real checker boundary without claiming source can reuse a key.
fn syntheticTransferRule(handling: bool) !void {
    const t = std.testing;
    const span: source.Span = .{ .start = 0, .end = 1 };
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base);
    var records = [_]typed.Record{.{
        .id = ty,
        .name = "PatternValue",
        .declaration = span,
        .fields = &.{},
        .contract = .{ .move_only = true, .requires_handling = handling },
    }};
    var sink: diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    var calls: std.ArrayList(generic_cache.Call) = .empty;
    var functions: FunctionMap = .empty;
    var checker: Checker = .{
        .allocator = t.allocator,
        .field_arena = std.heap.ArenaAllocator.init(t.allocator),
        .src = .{ .path = "synthetic-pattern.selka", .bytes = "x", .line_starts = &.{0} },
        .program = .{ .nodes = .empty, .statements = .empty, .functions = &.{} },
        .view_consumers = .empty,
        .catalog = .{ .records = &records, .names = .empty },
        .calls = &calls,
        .function_index = 0,
        .sink = &sink,
        .parameters = &.{},
        .result = .{ .concrete = .unit },
        .functions = &functions,
    };
    defer checker.field_arena.deinit();
    defer checker.locals.deinit(t.allocator);
    defer checker.active.deinit(t.allocator);
    try checker.active.put(t.allocator, "pattern", 0);
    try checker.locals.append(t.allocator, .{
        .name = span,
        .internal_name = "pattern",
        .ty = .{ .concrete = ty },
        .mutable = false,
        .ownership = .{ .available = false },
    });
    if (handling) {
        try t.expectError(error.SourceError, checker.syntheticValue("pattern", span));
        try t.expectEqualStrings("E_RESULT_CONSUMED", sink.items.items[0].code);
        try t.expectEqual(diagnostic.Rule.L1, sink.items.items[0].provenance.rule.?);
    } else {
        const value = try checker.syntheticValue("pattern", span);
        try t.expectEqual(ty, value.concrete);
        try t.expectEqual(@as(usize, 0), sink.items.items.len);
    }
}

test "ownership coverage generic synthetic transfer checks only Result obligations" {
    try syntheticTransferRule(false);
    try syntheticTransferRule(true);
}
