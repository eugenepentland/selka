//! Scope and type checking use resolved binding identities, including advisory use counts.
const sema_shared = @import("sema_shared.zig");
const buffer_operations = @import("buffer_operations.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const loop_rebinding = @import("loop_rebinding.zig");
/// A parsed `for` loop over a collection, `enumerate`, `reversed` or `zip`.
const ForEach = @FieldType(@FieldType(ast.Statement, "data"), "for_each");
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const external_resources = @import("external_resources.zig");
const io_builtins = @import("io_builtins.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const lambda_context_code = "E_LAMBDA_CONTEXT";
const call_argument_code = sema_shared.call_argument_code;
/// Stable code for a call-site `&` mutation marker that does not match the
/// callee's declared `mutates(...)` footprint.
const eResultOperation = diagnostic.result_operation;
const eOwnedConsumed = diagnostic.owned_consumed;
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
const eIterationShadow = "iteration binding shadows an active declaration";
const eWildcardArm = "E_WILDCARD_ARM";
const eVariantPayload = "E_VARIANT_PAYLOAD";
const ePatternPayload = "E_PATTERN_PAYLOAD";
const eConversionBody = "E_CONVERSION_BODY";
const sem_copy = @import("semantic_copy.zig");
const generic_specializations = @import("generic_specializations.zig");
const semantic_key = @import("semantic_key.zig");
const sem_entry = @import("semantic_entry.zig");
/// Managed collection methods whose only argument has the receiver's own sequence type.
/// Recognize `case _`, the contextual arm that stands for every remaining variant.
fn wildcard(src: source.Source, arm: anytype) bool {
    if (arm.ty.start != arm.ty.end or arm.bindings.len != 0) return false;
    return std.mem.eql(u8, src.text(arm.name), "_");
}

fn sequenceArgument(kind: BufferKind) bool {
    return switch (kind) {
        .split, .contains, .starts_with, .ends_with, .find, .count, .replace => true,
        else => false,
    };
}

/// The builtin mutable octet buffer's name, shared with the template index that
/// declares the type. It shares the byte collection kind with `bytes`, so the
/// name, not the representation, is what tells the checker which receiver accepts
/// an in-place append and which stays immutable.
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const isMutableBytes = sema_shared.isMutableBytes;
const eResourceResult = diagnostic.resource_result;
const eResultLoop = diagnostic.result_loop;
const bindingDeclaredHere = "binding declared here";
const eImmutable = diagnostic.immutable;
const eResultDiscard = diagnostic.result_discard;
const eCellEquality = sema_shared.eCellEquality;
const eOptionTest = sema_shared.eOptionTest;
const eEnvironmentName = sema_shared.eEnvironmentName;
const variantDeclaredHere = "variant declared here";
const std = @import("std");
const dictionary_views = @import("dictionary_views.zig");
const bufferOperation = sema_shared.bufferOperation;
const eCollectionMethod = sema_shared.eCollectionMethod;
/// A missing, unneeded or unauthorizable `mut` marker is one diagnostic code.
const mutation_marker_code = @import("origins.zig").mutation_marker_code;
const eTupleArity = diagnostic.tuple_arity;
const method_arity = "collection method argument count differs from its signature";
/// The whitespace alternative for the two `split` forms, attached to a rejected
/// `split` arity so the reader learns the spelling that does accept it.
const split_alternative = "`split()` with no argument splits on runs of ASCII whitespace and drops empty parts; `split(separator)` splits on one exact separator";
/// The accepted spelling beside a rejected `dict.get` arity: the fallback is a
/// required operand, so the repair is to pass it rather than to drop it.
const dictionary_get_alternative = "a dictionary `get` always takes its fallback: `d.get(key, default)`";
/// The accepted callee for a bare `print` or `eprint`: `Stream`'s printing
/// method, with the optional `sep` and `end` keywords the I/O builtins accept.
const print_signature = buffer_operations.stream_print_signature;
/// The accepted callee of the `sorted` prelude builtin, with Python's `key=`
/// and `reverse=` keywords.
const sorted_signature = buffer_operations.sorted_signature;
/// The accepted signature of a list's `sort` method with its keywords.
const list_sort_signature = buffer_operations.list_sort_signature;
/// The accepted spelling beside a rejected collection operation, or null when
/// the language has no alternative for it.
fn alternativeFor(kind: BufferKind) ?[]const u8 {
    return switch (kind) {
        .split, .split_whitespace => split_alternative,
        .get => dictionary_get_alternative,
        else => null,
    };
}
/// The capability-first repair for a free file helper called the Python way.
const capability_first = "a free file helper takes the Filesystem capability first: `open(fs, path, mode)` or `read_text(fs, path)`; `fs.open(path, mode)` is the method spelling";
/// The checked signature of one whole-path file helper as the free spelling
/// prints it, which is also how `docs/io.md` tabulates the helpers.
fn fileAccessSignature(kind: file_operations.Access) []const u8 {
    return switch (kind) {
        .open => "open(fs: Filesystem, path: str, mode: str) -> Result[File, str]",
        .read_file => "read_file(fs: Filesystem, path: str) -> Result[bytes, str]",
        .read_text => "read_text(fs: Filesystem, path: str) -> Result[str, str]",
        .write_file => "write_file(fs: Filesystem, path: str, data: bytes) -> Result[None, str]",
        .write_text => "write_text(fs: Filesystem, path: str, text: str) -> Result[None, str]",
        .exists => "exists(fs: Filesystem, path: str) -> bool",
        .listdir => "listdir(fs: Filesystem, path: str) -> Result[list[str], str]",
        .mkdir => "mkdir(fs: Filesystem, path: str) -> Result[None, str]",
        .remove => "remove(fs: Filesystem, path: str) -> Result[None, str]",
    };
}
/// The accepted argument shapes of one open-handle method.
fn fileMethodSignature(kind: file_operations.Method) []const u8 {
    return switch (kind) {
        .read => "read() -> str, or read(size: int) -> str",
        .readline => "readline() -> str",
        .readlines => "readlines() -> list[str]",
        .write => "write(data) -> int",
        .flush => "flush() -> None",
        .close => "close() -> None",
    };
}

const ast = @import("ast.zig");
const effect_set = @import("effect_set.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const entry_adapter = @import("entry_adapter.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const records = @import("records.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const instances = @import("generic_instances.zig");
const semantic_cache = @import("semantic_cache.zig");
const timings = @import("timings.zig");
const generic_cache = @import("generic_cache.zig");
const Names = @import("module_names.zig").Names;
const LoopScope = struct { id: usize, before: []const Pending, arenas: usize = 0, exited: bool = false };
const ArenaScope = struct { name: []const u8, declaration: source.Span, watermark: typed.LocalId };
const eArenaEscape = "E_ARENA_ESCAPE";
const eUnbound = "E_UNBOUND";
const eArenaBinding = sema_shared.eArenaBinding;
const eWithResource = sema_shared.eWithResource;
const eFileArgument = sema_shared.eFileArgument;
const Pending = sema_shared.Pending;
const Work = sema_shared.Work;
/// How a loop reads its source: a collection kind, a fixed array read by
/// index, or a dictionary view's projection.
const IterationShape = struct { kind: ManagedKind, fixed: ?typed.Array = null, projection: ?@import("dictionary_views.zig").Kind = null };
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
const uninferred_lambda = sema_shared.uninferred_lambda;

const markerPositionDeclared = sema_shared.markerPositionDeclared;
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
    option_facts: option_flow.State = .{},
    functions: std.StringHashMapUnmanaged(instances.DeclarationId) = .empty,
    resolved_nodes: std.ArrayList(usize) = .empty,
    instance_keys: std.ArrayList(instances.Key) = .empty,
    generic_registry: instances.Registry = .{},
    /// C3 concrete-specialization reuse: stable declaration facts and the
    /// canonical fingerprint -> fresh instance-index map. Empty when no
    /// semantic cache is attached.
    prepared: ?*const semantic_key.Prepared = null,
    spec_build: []const u8 = "",
    spec_fingerprints: std.ArrayList(?[]const u8) = .empty,
    spec_ranges: std.ArrayList(sem_copy.Range) = .empty,
    spec_index: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
    spec_fresh: std.ArrayList(usize) = .empty,
    ordinary_instance_by_key: std.StringHashMapUnmanaged(usize) = .empty,
    record_by_name: std.StringHashMapUnmanaged(usize) = .empty,
    initial_record_count: usize = 0,
    ordinary_ids: []?typed.FunctionId,
    ordinary_count: usize = 0,
    current_function: ?typed.FunctionId = null,
    current_lambda: ?usize = null,
    lambda_start: usize = 0,
    /// One flag per instance key: the declaration carried a `mut` parameter whose
    /// type cannot carry a write. Its call-site markers are not checked against
    /// the footprint it never declared.
    mut_parameter_rejected: std.ArrayList(bool) = .empty,
    /// Instance key currently being checked, for per-instance bookkeeping.
    checked_index: usize = 0,
    lambda_types: []?typed.Type = &.{},
    lambda_captures: []?[]const LambdaCapture = &.{},
    loops: struct { active: std.ArrayList(LoopScope) = .empty, next: usize = 0 } = .{},
    /// Loop counters that are never negative while their loop runs: `range`
    /// induction variables from a non-negative start and `enumerate`
    /// positions. Each is immutable — a loop whose body assigns its variable
    /// counts on a hidden local instead (`PY-FOR-REBIND-1`).
    counters: std.AutoHashMapUnmanaged(typed.LocalId, void) = .empty,
    return_type: typed.Type = .i64,
    arenas: std.ArrayList(ArenaScope) = .empty,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,
    managed_types: []bool = &.{},
    owner: ?typed.Type = null,
    /// The `with open(...)` head whose failure traps instead of yielding a result.
    trapping_open: ?source.Span = null,

    fn checkFunction(self: *Checker, i: usize) Error!typed.Function {
        self.checked_index = i;
        if (i >= self.lambda_start and i < self.lambda_start + self.syntax.lambdas.len)
            return self.checkLambdaFunction(i - self.lambda_start);
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        self.current_function = @fromBackingInt(i);
        self.current_lambda = null;
        const function = self.syntaxFunction(@fromBackingInt(i));
        const constant_context: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        const declaration = @backingInt(self.instance_keys.items[i].declaration);
        const constant = if (function.policy.constant and try constant_context.literalType(declaration) == null) try constant_context.evaluate(declaration) else null;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.option_facts.clear();
        self.locals = .empty;
        self.counters.clearRetainingCapacity();
        self.active.clearRetainingCapacity();
        self.owner = if (function.policy.owner) |owner| try self.ty(owner) else null;
        self.return_type = try self.ty(function.signature.return_type);
        try self.bindParameters(function);
        if (function.policy.c_abi) {
            const foreign = @import("c_abi.zig");
            if (self.locals.items.len == 0 or self.locals.items[0].ty != .host_cap) return sink.fail("E_HOST_CAPABILITY", function.name, "an extern or host declaration must take `host: Host` as its first parameter");
            if (!foreign.supported(self.return_type, self.catalog.records, true)) return sink.fail("E_EXTERN_SIGNATURE", function.signature.return_type, foreign.signature_message);
            for (self.locals.items[1..]) |local| if (!foreign.supported(local.ty, self.catalog.records, false)) return sink.fail("E_EXTERN_SIGNATURE", local.declaration, foreign.signature_message);
            if (!foreign.validSymbol(src.text(function.name))) return sink.fail("E_EXTERN_SYMBOL", function.name, "extern names must be C identifiers outside the reserved myl_/mylang_ runtime namespaces");
        } else if (function.policy.host != null) {
            if (self.locals.items.len == 0 or self.locals.items[0].ty != .host_cap) return sink.fail("E_HOST_CAPABILITY", function.name, "an extern or host declaration must take `host: Host` as its first parameter");
            try checkHostType(allocator, self.catalog.records, self.return_type, function.signature.return_type, sink);
            for (self.locals.items[1..]) |local| try checkHostType(allocator, self.catalog.records, local.ty, local.declaration, sink);
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
        // scalar initializer with its checked literal value. Managed constants keep
        // their ordinary checked literal node and its allocation effect.
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
                .mutates = &.{},
                .return_origin = .unknown,
                // The declared footprint is the `mut` parameter set itself: a
                // written position and a `name: mut T` declaration are the same
                // fact, so there is no separate clause to reconcile.
                .declared_mutates = function.signature.mut_positions,
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
    /// Whether `span` lies inside the body of a generic function declaration,
    /// where a lambda never receives a callback type (GENERIC-LAMBDA-1).
    fn inGenericBody(self: *Checker, span: source.Span) bool {
        for (self.syntax.functions) |function| {
            if (function.signature.type_parameters.len == 0) continue;
            const body = self.syntax.statements.items[@backingInt(function.body)].span;
            if (body.start <= span.start and span.end <= body.end) return true;
        }
        return false;
    }
    fn checkLambdaFunction(self: *Checker, index: usize) Error!typed.Function {
        const lambda = self.syntax.lambdas[index];
        const lambda_type = self.lambda_types[index] orelse {
            if (self.inGenericBody(lambda.span)) return self.sink.fail("E_GENERIC_BODY_UNSUPPORTED", lambda.span, @import("generic_bodies.zig").lambda_in_generic_body);
            return self.sink.fail(lambda_context_code, lambda.span, "lambda requires an expected callback type");
        };
        if (lambda_type == uninferred_lambda) return error.SourceError;
        const contract = callables.signature(lambda_type, self.catalog.records) orelse return error.InternalError;
        self.current_function = null;
        self.current_lambda = index;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.option_facts.clear();
        self.locals = .empty;
        self.counters.clearRetainingCapacity();
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
            .signature = .{
                .return_type = contract.return_type,
                .parameter_count = contract.parameters.len,
                .mutates = contract.mutates,
                .return_origin = contract.return_origin,
                .declared_mutates = contract.mutates,
            },
            .scope = .{ .body = body, .locals = try self.locals.toOwnedSlice(self.allocator) },
            .id = @fromBackingInt(self.lambda_start + index),
            .name = name,
            .declaration = lambda.span,
        };
    }
    /// Whether a name refers to a top-level declaration: a constant-length type parameter
    /// of the current function, a function, a record or a template.
    pub fn topLevel(self: *Checker, span: source.Span) error{InternalError}!bool {
        if (self.current_function) |id| {
            for (self.syntaxFunction(id).signature.type_parameters) |parameter| {
                if (parameter.constant_length and std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) return true;
            }
        }
        if (self.catalog.module_names) |names| return names.topLevel(span);
        const name = self.src.text(span);
        return self.functions.contains(name) or self.catalog.names.contains(name) or self.catalog.templates.names.contains(name);
    }
    /// Resolve a spelled type in the current function's generic scope, or at top level.
    pub fn ty(self: *Checker, span: source.Span) Error!typed.Type {
        if (self.current_function) |id| return self.functionType(id, span);
        return self.catalog.resolve(self.src, span, self.sink);
    }
    /// Record that the function currently being checked declared a `mut`
    /// parameter of a type that cannot carry a write. The array is filled lazily
    /// because only a rejected declaration pays for it.
    fn markMutRejected(self: *Checker) Error!void {
        if (self.mut_parameter_rejected.items.len != self.instance_keys.items.len) {
            try self.mut_parameter_rejected.resize(self.allocator, self.instance_keys.items.len);
            @memset(self.mut_parameter_rejected.items, false);
        }
        self.mut_parameter_rejected.items[self.checked_index] = true;
    }
    /// The parsed declaration an instance was specialized from.
    pub fn syntaxFunction(self: *Checker, id: typed.FunctionId) ast.Function {
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
    /// Resolve a spelled type inside a specialized function, substituting its type arguments.
    pub fn functionType(self: *Checker, id: typed.FunctionId, span: source.Span) Error!typed.Type {
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
    /// The function instance a call to a declaration names: its ordinary instance, or a
    /// generic specialization for the inferred or explicit type arguments.
    pub fn specialize(self: *Checker, declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
        const function = self.syntax.functions[@backingInt(declaration)];
        if (call.type_arguments.len != 0 and call.type_arguments.len != function.signature.type_parameters.len) return self.sink.fail("E_GENERIC_ARITY", span, "explicit type argument count does not match generic parameters");
        if (self.ordinary_ids[@backingInt(declaration)]) |id| return id;
        var provider: @import("constraint_lookup.zig").Provider = .{ .program = self.syntax, .src = self.src, .names = self.catalog.module_names };
        const required = try @import("generic_requirements.zig").resolveBounds(self.allocator, self.src, function.signature.type_parameters, self.sink, provider.lookup());
        defer @import("generic_requirements.zig").deinitResolved(self.allocator, required);
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
        if (index == self.instance_keys.items.len) {
            const owned_key = self.generic_registry.get(instance) catch return error.InternalError;
            try self.instance_keys.append(self.allocator, owned_key);
            try self.spec_ranges.append(self.allocator, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
            const fingerprint = try self.specializationFingerprint(@backingInt(declaration), arguments, lengths);
            try self.spec_fingerprints.append(self.allocator, fingerprint);
            if (fingerprint) |canonical| {
                const entry = try self.spec_index.getOrPut(self.allocator, canonical);
                entry.value_ptr.* = @fromBackingInt(index);
            }
        }
        return @fromBackingInt(index);
    }
    /// Canonical `specialization-v1` fingerprint of one fresh instance. Null
    /// when no semantic cache (and therefore no prepared declaration facts) is
    /// attached. The template identity, ordered positional descriptors, resolved
    /// provider contracts, template constraint dependency, declared
    /// effect/mutation/return-origin contract and build context all participate;
    /// every boundary is length-prefixed by the key engine.
    fn specializationFingerprint(self: *Checker, declaration: usize, arguments: []const typed.Type, lengths: []const ?usize) Error!?[]const u8 {
        const prepared = self.prepared orelse return null;
        const function = self.syntax.functions[declaration];
        const descriptors = try self.allocator.alloc([]const u8, arguments.len);
        for (arguments, 0..) |argument, i| descriptors[i] = try semantic_key.argumentDescriptor(self.allocator, argument, if (i < lengths.len) lengths[i] else null, self.catalog.records);
        const provider = try semantic_key.providerIdentity(self.allocator, arguments, self.catalog.records);
        const contract = semantic_key.declaredContractDigest(function.policy.effect_bound, function.signature.mut_positions);
        const canonical = try semantic_key.specializationFingerprint(self.allocator, .{
            .template_identity = prepared.keys[declaration],
            .arguments = descriptors,
            .provider = provider,
            .constraints = prepared.contexts[declaration][0..],
            .contracts = contract[0..],
            .build = self.spec_build,
        });
        return canonical;
    }
    /// Replay one checked concrete specialization when every retained reference
    /// remaps to a fresh identity. A missing or ambiguous reference, an
    /// unvalidated fingerprint, a changed defining region or a reference to a
    /// specialization that the fresh run has not instantiated is a conservative
    /// miss; an unvalidated specialization is never reused.
    fn lookupSpecialization(self: *Checker, reuse: *generic_specializations.Session, allocator: std.mem.Allocator, index: usize, nodes: *std.ArrayList(typed.Node), statements: *std.ArrayList(typed.Statement)) Error!?typed.Function {
        if (index >= self.spec_fingerprints.items.len) return null;
        const fingerprint = self.spec_fingerprints.items[index] orelse return null;
        const prepared = self.prepared orelse {
            reuse.noteMiss(.context_changed);
            return null;
        };
        const instance = self.instance_keys.items[index];
        const declaration = @backingInt(instance.declaration);
        const context = prepared.contexts[declaration];
        const entry = (try reuse.open(fingerprint, context)) orelse return null;
        if (!std.mem.eql(u8, entry.payload.identity.fingerprint, fingerprint)) {
            reuse.noteMiss(.stale_identity);
            return null;
        }
        if (!std.mem.eql(u8, entry.payload.identity.template, prepared.keys[declaration])) {
            reuse.noteMiss(.stale_identity);
            return null;
        }
        if (!std.mem.eql(u8, entry.payload.identity.context[0..], context[0..])) {
            reuse.noteMiss(.context_changed);
            return null;
        }
        const fresh_region = prepared.regions[declaration];
        const region_len = entry.payload.source.region.end - entry.payload.source.region.start;
        if (region_len != fresh_region.end - fresh_region.start) {
            reuse.noteMiss(.region_length_changed);
            return null;
        }
        if (!std.mem.eql(u8, entry.payload.source.region_bytes, self.src.bytes[fresh_region.start..fresh_region.end])) {
            reuse.noteMiss(.region_bytes_changed);
            return null;
        }
        const fresh_body = prepared.bodies[declaration];
        const body_len = entry.payload.source.body.end - entry.payload.source.body.start;
        if (body_len != fresh_body.end - fresh_body.start) {
            reuse.noteMiss(.region_length_changed);
            return null;
        }
        if (!std.mem.eql(u8, entry.payload.source.body_bytes, self.src.bytes[fresh_body.start..fresh_body.end])) {
            reuse.noteMiss(.region_bytes_changed);
            return null;
        }
        const functions = try allocator.alloc(?typed.FunctionId, entry.payload.counts.old_function_count);
        @memset(functions, null);
        for (entry.payload.refs.function_refs) |reference| {
            const id = @backingInt(reference.id);
            if (id >= functions.len) {
                reuse.noteMiss(.relocation_failed);
                return null;
            }
            switch (reference.kind) {
                .ordinary => {
                    const fresh = self.ordinary_instance_by_key.get(reference.key) orelse {
                        reuse.noteMiss(.missing_ordinary);
                        return null;
                    };
                    if (fresh == std.math.maxInt(usize)) {
                        reuse.noteMiss(.ambiguous_ordinary);
                        return null;
                    }
                    functions[id] = @fromBackingInt(fresh);
                },
                .specialization => {
                    const fresh = self.spec_index.get(reference.key) orelse {
                        reuse.noteMiss(.missing_specialization);
                        return null;
                    };
                    functions[id] = fresh;
                },
            }
        }
        const record_remaps = try allocator.alloc(?typed.Type, entry.payload.counts.old_record_count);
        @memset(record_remaps, null);
        for (entry.payload.refs.record_refs) |reference| {
            if (reference.index >= self.initial_record_count) {
                reuse.noteMiss(.interned_record);
                return null;
            }
            const fresh = self.record_by_name.get(reference.key) orelse {
                reuse.noteMiss(.missing_record);
                return null;
            };
            if (fresh == std.math.maxInt(usize)) {
                reuse.noteMiss(.ambiguous_record);
                return null;
            }
            record_remaps[reference.index] = @fromBackingInt(fresh + typed.Type.record_base);
        }
        var segment = [_]sem_copy.Segment{.{ .before = entry.payload.source.region, .after = fresh_region.start }};
        const mapper: sem_copy.Mapper = .{
            .segments = &segment,
            .before = entry.payload.body.range,
            .after = .{
                .nodes = .{ .start = nodes.items.len, .end = nodes.items.len + entry.payload.body.nodes.len },
                .statements = .{ .start = statements.items.len, .end = statements.items.len + entry.payload.body.statements.len },
            },
            .functions = functions,
            .records = record_remaps,
        };
        const function = mapper.copy(allocator, typed.Function, entry.payload.body.function) catch |err| return specializationRelocationMiss(reuse, err);
        const copied_nodes = mapper.copy(allocator, []const typed.Node, entry.payload.body.nodes) catch |err| return specializationRelocationMiss(reuse, err);
        const copied_statements = mapper.copy(allocator, []const typed.Statement, entry.payload.body.statements) catch |err| return specializationRelocationMiss(reuse, err);
        try nodes.appendSlice(allocator, copied_nodes);
        try statements.appendSlice(allocator, copied_statements);
        reuse.noteReused();
        return function;
    }
    fn specializationRelocationMiss(reuse: *generic_specializations.Session, err: sem_copy.Error) error{ OutOfMemory, InternalError }!?typed.Function {
        return switch (err) {
            error.InvalidRelocation => blk: {
                reuse.noteMiss(.relocation_failed);
                break :blk null;
            },
            error.OutOfMemory => error.OutOfMemory,
            error.InternalError => error.InternalError,
        };
    }
    /// Capture every specialization freshly checked by this request and publish
    /// them after the whole graph passed. A tree that references a synthesized
    /// lambda, an interned catalog record or an unresolvable identity is a
    /// conservative miss, never a partial entry.
    fn publishSpecializations(self: *Checker, reuse: *generic_specializations.Session, allocator: std.mem.Allocator, program: typed.Program) Error!void {
        // Zero retention must perform the checks but publish nothing, so
        // `--no-cache` never reads or writes a specialization entry.
        if (!reuse.backend.enabled) return;
        const prepared = self.prepared orelse return;
        for (self.spec_fresh.items) |index| {
            if (index >= self.spec_fingerprints.items.len) continue;
            const fingerprint = self.spec_fingerprints.items[index] orelse continue;
            const instance = self.instance_keys.items[index];
            const declaration = @backingInt(instance.declaration);
            if (declaration >= prepared.keys.len) continue;
            const range = self.spec_ranges.items[index];
            if (range.nodes.end > program.nodes.len or range.statements.end > program.statements.len) continue;
            var refs = sem_copy.RefSet.init(allocator);
            defer refs.deinit();
            sem_copy.collectRefs(allocator, program.functions[index], program.nodes[range.nodes.start..range.nodes.end], program.statements[range.statements.start..range.statements.end], &refs) catch continue;
            const function_refs = allocator.alloc(sem_entry.SpecializationFunctionRef, refs.functions.count()) catch return error.OutOfMemory;
            defer allocator.free(function_refs);
            var iterator = refs.functions.keyIterator();
            var function_count: usize = 0;
            var representable = true;
            while (iterator.next()) |id| {
                const old = id.*;
                if (old < prepared.ordinary_ast.len) {
                    function_refs[function_count] = .{ .kind = .ordinary, .id = @fromBackingInt(old), .key = prepared.keys[prepared.ordinary_ast[old]] };
                } else if (old < self.ordinary_count) {
                    representable = false;
                    break;
                } else {
                    if (old >= self.spec_fingerprints.items.len) {
                        representable = false;
                        break;
                    }
                    const canonical = self.spec_fingerprints.items[old] orelse {
                        representable = false;
                        break;
                    };
                    function_refs[function_count] = .{ .kind = .specialization, .id = @fromBackingInt(old), .key = canonical };
                }
                function_count += 1;
            }
            if (!representable) {
                reuse.noteMiss(.lambda_reference);
                continue;
            }
            const record_refs = allocator.alloc(sem_entry.RecordRef, refs.records.count()) catch return error.OutOfMemory;
            defer allocator.free(record_refs);
            var record_iterator = refs.records.keyIterator();
            var record_count: usize = 0;
            var stable_records = true;
            while (record_iterator.next()) |record_index| {
                if (record_index.* >= self.initial_record_count or record_index.* >= program.records.len) {
                    stable_records = false;
                    break;
                }
                record_refs[record_count] = .{ .index = record_index.*, .key = program.records[record_index.*].name };
                record_count += 1;
            }
            if (!stable_records) {
                reuse.noteMiss(.interned_record);
                continue;
            }
            const descriptors = allocator.alloc([]const u8, instance.arguments.len) catch return error.OutOfMemory;
            defer allocator.free(descriptors);
            for (instance.arguments, 0..) |argument, argument_index| {
                descriptors[argument_index] = semantic_key.argumentDescriptor(allocator, argument, instance.length(argument_index), program.records) catch return error.OutOfMemory;
            }
            const region = prepared.regions[declaration];
            const body = prepared.bodies[declaration];
            // The retained entry owns an arena backed by the cache's allocator,
            // never this per-request compilation arena: the cache outlives the
            // request that produced the body.
            const entry = sem_entry.createSpecialization(reuse.allocator, program, index, range, .{
                .identity = .{
                    .key = generic_specializations.Session.stableKey(allocator, fingerprint) catch return error.OutOfMemory,
                    .fingerprint = fingerprint,
                    .template = prepared.keys[declaration],
                    .context = prepared.contexts[declaration],
                    .arguments = descriptors,
                    .lengths = instance.lengths,
                },
                .source = .{
                    .old_len = self.src.bytes.len,
                    .region = region,
                    .body = body,
                    .region_bytes = self.src.bytes[region.start..region.end],
                    .body_bytes = self.src.bytes[body.start..body.end],
                },
                .function_refs = function_refs[0..function_count],
                .record_refs = record_refs[0..record_count],
                .old_function_count = self.instance_keys.items.len,
                .old_record_count = program.records.len,
            }) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                error.InternalError => continue,
            };
            // UNTESTED-ERROR: this branch only releases the just-built entry
            // when the cache-owned append allocation fails; the cache-wide
            // FailingAllocator scenario covers allocation failure at the
            // checkWithCache boundary, not this release path.
            reuse.record(entry) catch |err| {
                var released = entry;
                released.deinit();
                return err;
            };
        }
        try reuse.publish();
    }
    fn inferArguments(self: *Checker, signature: @FieldType(ast.Function, "signature"), call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span, arguments: []typed.Type, lengths: []?usize) Error!void {
        const inference = @import("generic_inference.zig");
        var context: inference.Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = span };
        if (self.expected_types.get(span)) |expected| try context.match(signature.return_type, .{ .concrete = expected });
        for (signature.parameters, call.arguments) |parameter, input| {
            const resolved = self.resolved[@backingInt(input)] orelse continue;
            const actual = self.nodes.items[@backingInt(resolved)].ty;
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
    /// Whether a value of this type must be consumed or handled (a Result or resource).
    pub fn requiresHandling(self: *Checker, value_type: typed.Type) bool {
        return typed.requiresHandling(value_type, self.catalog.records);
    }
    /// Whether a value of this type moves on assignment: it must be handled or is move-only.
    pub fn transfers(self: *Checker, value_type: typed.Type) bool {
        return self.requiresHandling(value_type) or typed.moveOnly(value_type, self.catalog.records);
    }
    /// Snapshot the ownership-transfer state of the first `count` locals.
    pub fn pendingState(self: *Checker, count: usize) Error![]Pending {
        const state = try self.allocator.alloc(Pending, count);
        for (self.locals.items[0..count], state) |local, *pending| pending.* = .{ .available = local.ownership.transfer_available, .transfer_span = local.ownership.transfer_span };
        return state;
    }
    /// Restore the ownership-transfer state `pendingState` captured.
    pub fn restorePending(self: *Checker, state: []const Pending) void {
        for (self.locals.items[0..state.len], state) |*local, pending| {
            local.ownership.transfer_available = pending.available;
            local.ownership.transfer_span = pending.transfer_span;
        }
    }
    /// Require every local's ownership-transfer state to match a checkpoint, reporting
    /// `code` (or the owned-value variant) where two paths disagree.
    pub fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
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
    /// Whether a local still holds a value that must be handled before it goes out of scope.
    pub fn pendingObligation(self: *Checker, local: typed.Local) bool {
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
    /// Whether one in-scope local may appear in a hole snapshot as a usable
    /// input: initialized, not consumed, not arena-confined, not synthetic.
    fn holeUsable(self: *Checker, local: typed.Local) bool {
        if (!local.ownership.initialized) return false;
        if (local.ownership.arena_confined) return false;
        if (local.usage.temporary) return false;
        return !self.transfers(local.ty) or local.ownership.transfer_available;
    }
    /// One binding's snapshot entry, spelled the way source declares its type.
    fn holeCandidate(self: *Checker, local: typed.Local) Error!diagnostic.Candidate {
        return .{
            .name = local.name,
            .ty = try typed.surfaceTypeName(self.allocator, local.ty, self.catalog.records),
            .declaration = local.declaration,
            .mutable = local.mutable,
            .usable = self.holeUsable(local),
        };
    }
    /// Offer every in-scope binding a filling could read at a typed hole.
    fn holeCandidates(self: *Checker, out: *std.ArrayList(diagnostic.Candidate)) Error!void {
        for (self.locals.items, 0..) |local, index| {
            if (self.active.get(local.name) != @as(typed.LocalId, @fromBackingInt(index))) continue;
            try out.append(self.allocator, try self.holeCandidate(local));
        }
    }
    /// The generic requirements in force at a typed hole.
    fn holeRequirements(self: *Checker, out: *std.ArrayList(diagnostic.Requirement)) Error!void {
        if (self.current_function) |id| try diagnostic.appendRequirements(self.allocator, self.src, self.syntaxFunction(id).signature.type_parameters, out);
    }
    /// The callable enclosing a hole: its checked function, its lambda, or none.
    fn holeFunction(self: *Checker) ?diagnostic.Fact {
        if (self.current_function) |id| {
            const declaration = self.syntaxFunction(id).name;
            return .{ .text = self.src.text(declaration), .span = declaration };
        }
        if (self.current_lambda) |index| return .{ .text = "lambda", .span = self.syntax.lambdas[index].span };
        return null;
    }
    /// The contextual expected type, published only when the checker knows one.
    fn holeExpected(self: *Checker, call_span: source.Span) Error!?diagnostic.Fact {
        const expected = self.expected_types.get(call_span) orelse return null;
        return .{ .text = try typed.surfaceTypeName(self.allocator, expected, self.catalog.records), .span = call_span };
    }
    /// The declared effect ceiling and permitted mutation footprint. A lambda
    /// states no ceiling of its own, so both stay explicitly unknown there.
    fn holeContract(self: *Checker) Error!diagnostic.ObligationContract {
        const id = self.current_function orelse return .{};
        const function = self.syntaxFunction(id);
        return .{
            .effects = if (function.policy.effect_bound) |bound| .{ .text = self.src.text(bound.span), .span = bound.span } else null,
            .mutation = try diagnostic.mutationFact(self.allocator, self.src, function),
        };
    }
    /// The bounded facts this checker can see at a typed hole. The candidate and
    /// requirement lists live in the checker's own allocator, so they outlive
    /// this call and are released with the rest of the check.
    fn holeFindings(self: *Checker, call_span: source.Span, candidates: []const diagnostic.Candidate, requirements: []const diagnostic.Requirement) Error!diagnostic.Findings {
        return .{ .function = self.holeFunction(), .expected = try self.holeExpected(call_span), .candidates = candidates, .requirements = requirements, .contract = try self.holeContract() };
    }
    /// Record one typed hole from the facts this checker sees right now.
    fn recordHole(self: *Checker, at: source.Span, target: source.Span, call_span: source.Span) Error {
        var candidates: std.ArrayList(diagnostic.Candidate) = .empty;
        try self.holeCandidates(&candidates);
        var requirements: std.ArrayList(diagnostic.Requirement) = .empty;
        try self.holeRequirements(&requirements);
        return self.sink.recordHole(self.src, at, target, try self.holeFindings(call_span, candidates.items, requirements.items));
    }
    fn callTarget(self: *Checker, input: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!typed.FunctionId {
        const target = try self.callDeclaration(input, span);
        return self.specialize(target.declaration, target.call, span);
    }
    /// Resolve a call's callee: a `todo(T)` hole, a codec entry point, or a declared
    /// function with its explicit type arguments split off.
    pub fn callDeclaration(self: *Checker, raw: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!ResolvedCall {
        const applied = try @import("call_type_arguments.zig").split(self.src, self.syntax, self.catalog.module_names, raw, self.sink);
        const input = applied orelse raw;
        if (std.mem.eql(u8, self.src.text(input.name), "todo") and input.owner == null) {
            _ = try self.ty(input.type_arguments[0]);
            return self.recordHole(input.name, input.type_arguments[0], span);
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
        const function = self.functions.get(name) orelse {
            const clause = try typed.suggestionClause(self.allocator, &self.functions, self.src.text(call.name));
            const message = if (clause.len == 0) "no function has this qualified name" else try std.fmt.allocPrint(self.allocator, "no function has this qualified name{s}", .{clause});
            return self.sink.fail("E_UNKNOWN_FUNCTION", call.name, message);
        };
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
        const bound = try call_arguments.bind(self.allocator, self.src, self.syntax.nodes.items, call, signature.signature, self.sink);
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
    /// Check a record constructor's or update's field initializers against the record,
    /// rejecting unknown and repeated fields and, when `complete`, missing ones.
    pub fn fields(self: *Checker, record_type: typed.Type, initializers: []const ast.FieldInit, complete: bool, span: source.Span) Error![]const typed.FieldInit {
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
            try work.append(self.allocator, .{ .id = initializers[i].value, .default_value = initializers[i].default });
        }
    }
    /// Require `actual` to be assignable to `expected`; callables compare by signature.
    /// Otherwise report `E_TYPE` naming both types.
    pub fn require(self: *Checker, actual: typed.Type, expected: typed.Type, span: source.Span) Error!void {
        if (actual == expected) return;
        if (callables.signature(actual, self.catalog.records)) |implementation| {
            if (callables.signature(expected, self.catalog.records)) |destination| {
                if (callables.assignable(implementation, destination)) return;
            }
        }
        const expected_name = try typed.surfaceTypeName(self.allocator, expected, self.catalog.records);
        const actual_name = try typed.surfaceTypeName(self.allocator, actual, self.catalog.records);
        const message = try std.fmt.allocPrint(self.allocator, "expected {s}, found {s}", .{ expected_name, actual_name });
        return self.sink.fail("E_TYPE", span, message);
    }
    /// Resolve a name to its active local, or report `E_UNKNOWN_NAME` with a suggestion.
    pub fn resolve(self: *Checker, name: source.Span) Error!typed.LocalId {
        const text = self.src.text(name);
        return self.active.get(text) orelse {
            const clause = try typed.suggestionClause(self.allocator, &self.active, text);
            const message = if (clause.len == 0)
                "name is not defined in this scope"
            else
                try std.fmt.allocPrint(self.allocator, "name is not defined in this scope{s}", .{clause});
            return self.sink.fail("E_UNKNOWN_NAME", name, message);
        };
    }
    /// Render the `unknown managed collection method` diagnostic with the
    /// receiver's type when its family is known and the method spellings that
    /// receiver accepts, or their union when its family is not known.
    pub fn unknownMethodMessage(self: *Checker, family: ?ManagedKind, receiver: ?typed.Type) Error![]const u8 {
        const spellings = if (family) |kind|
            try buffer_operations.methodSpellings(self.allocator, kind)
        else
            try buffer_operations.unionMethodSpellings(self.allocator);
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(self.allocator);
        for (spellings, 0..) |spelling, index| {
            if (index != 0) try joined.appendSlice(self.allocator, ", ");
            try joined.appendSlice(self.allocator, spelling);
        }
        const name = if (receiver) |receiver_type|
            try std.fmt.allocPrint(self.allocator, "a {s} receiver", .{try typed.surfaceTypeName(self.allocator, receiver_type, self.catalog.records)})
        else
            try self.allocator.dupe(u8, "this receiver");
        return std.fmt.allocPrint(self.allocator, "unknown method for {s}; accepted methods: {s}", .{ name, joined.items });
    }
    /// The receiver, family, element and key type spellings one method signature
    /// is rendered with.
    pub fn signatureNames(self: *Checker, owner_type: typed.Type) Error!buffer_operations.SignatureNames {
        const schema = self.catalog.records[owner_type.recordIndex()];
        return .{
            .receiver = try typed.surfaceTypeName(self.allocator, owner_type, self.catalog.records),
            .family = schema.collection.kind,
            .element = try typed.surfaceTypeName(self.allocator, schema.shape.buffer orelse .i64, self.catalog.records),
            .key = if (schema.collection.key) |key| try typed.surfaceTypeName(self.allocator, key, self.catalog.records) else "int",
        };
    }
    /// One rejected method call: the syntax it occupies, the callee, and the
    /// argument count or argument type that did not match the callee.
    const MethodRejection = struct {
        span: source.Span,
        name: source.Span,
        kind: BufferKind,
        names: buffer_operations.SignatureNames,
        arguments: usize,
    };
    /// One argument whose checked type did not match the method's declared
    /// parameter type, kept together so the signature is rendered only on failure.
    const ArgumentRejection = struct {
        actual: typed.Type,
        expected: typed.Type,
        span: source.Span,
        kind: BufferKind,
        names: buffer_operations.SignatureNames,
    };
    /// Reject a method call whose argument count differs from the callee's
    /// checked signature. The message names the receiver type and renders the
    /// signature through the one shared renderer, and a Python form with a known
    /// accepted spelling carries that spelling as an `alternative` note.
    pub fn methodArityFailure(self: *Checker, rejection: MethodRejection) Error {
        const signature = try buffer_operations.signatureText(self.allocator, rejection.kind, rejection.names) orelse method_arity;
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` takes {d} argument{s}, but this call passes {d}", .{
            signature, rejection.kind.arity(), if (rejection.kind.arity() == 1) "" else "s", rejection.arguments,
        });
        if (alternativeFor(rejection.kind)) |alternative|
            return self.sink.failRelated("E_ARITY", rejection.span, message, .{ .span = rejection.name, .message = alternative, .role = .alternative });
        return self.sink.fail("E_ARITY", rejection.span, message);
    }
    /// Require one method argument's type, attaching the callee's rendered
    /// signature beside the offending argument when the type is rejected.
    pub fn requireArgument(self: *Checker, rejection: ArgumentRejection) Error!void {
        self.require(rejection.actual, rejection.expected, rejection.span) catch |err| {
            if (err == error.SourceError) if (try buffer_operations.signatureText(self.allocator, rejection.kind, rejection.names)) |signature|
                self.attachAlternative(rejection.span, signature);
            return err;
        };
    }
    /// Attach an `alternative` note to the diagnostic just appended, unless that
    /// diagnostic already carries related evidence.
    fn attachAlternative(self: *Checker, span: source.Span, message: []const u8) void {
        const items = self.sink.items.items;
        if (items.len == 0) return;
        const last = &items[items.len - 1];
        if (last.related != null) return;
        last.related = .{ .span = span, .message = message, .role = .alternative };
    }
    /// Reject a whole-path file helper whose argument count differs from its
    /// checked signature, rendering that signature and, for the free spelling, the
    /// capability-first repair a Python `open(path)` call needs.
    pub fn fileAccessArityFailure(self: *Checker, node: ast.Node, kind: file_operations.Access, actual: usize, method: bool) Error {
        const expected = if (method) kind.methodArity() else kind.arity();
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` takes {d} argument{s}, but this call passes {d}", .{
            fileAccessSignature(kind), expected, if (expected == 1) "" else "s", actual,
        });
        if (method) return self.sink.fail("E_ARITY", node.span, message);
        return self.sink.failRelated("E_ARITY", node.span, message, .{ .span = node.span, .message = capability_first, .role = .alternative });
    }
    /// Reject an open-handle method whose argument count differs from its checked
    /// signature.
    pub fn fileMethodArityFailure(self: *Checker, name: source.Span, kind: file_operations.Method, actual: usize) Error {
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` does not take {d} argument{s}", .{
            fileMethodSignature(kind), actual, if (actual == 1) "" else "s",
        });
        return self.sink.fail("E_ARITY", name, message);
    }
    /// Reject reading a function-scoped binding that no path reaching here has
    /// assigned, or one that names a managed value confined to a released arena.
    pub fn requireReadable(self: *Checker, slot: typed.LocalId, name: source.Span) Error!void {
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
    pub fn initSnapshot(self: *Checker) Error![]bool {
        const state = try self.allocator.alloc(bool, self.locals.items.len);
        for (self.locals.items, state) |local, *flag| flag.* = local.ownership.initialized;
        return state;
    }
    /// Restore definite-assignment flags to a snapshot; locals created since it are
    /// treated as unassigned on the path being started.
    pub fn initRestore(self: *Checker, state: []const bool) void {
        for (self.locals.items, 0..) |*local, index| local.ownership.initialized = index < state.len and state[index];
    }
    /// Keep a local assigned after a branch only when both paths assigned it.
    pub fn initIntersect(self: *Checker, state: []const bool) void {
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
    /// Require an index operand: the array's declared key type, or any integer.
    pub fn requireIndex(self: *Checker, array: typed.Array, actual: typed.Type, span: source.Span) Error!void {
        if (array.key) |key| try self.require(actual, key, span) else try self.requireInteger(actual, span);
    }
    /// Require an integer type, or report `E_TYPE`.
    pub fn requireInteger(self: *Checker, actual: typed.Type, span: source.Span) Error!void {
        if (!actual.isInteger()) return self.sink.fail("E_TYPE", span, "operation requires an integer type");
    }
    /// Check one expression tree with no inherited temporaries and return its typed node.
    pub fn expression(self: *Checker, root: ast.NodeId) Error!typed.NodeId {
        return self.expressionWithTemporaries(root, &.{});
    }
    /// Record the type an expression is expected to have, so literals, `None`, `Ok`/`Err`
    /// and lambdas below it can infer from context.
    pub fn hint(self: *Checker, id: ast.NodeId, expected: typed.Type) Error!void {
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
    /// A numeric-surface builder that appends typed nodes for arithmetic at `span`.
    pub fn numericBuilder(self: *Checker, span: source.Span) numeric_surface.Builder {
        return .{ .arena = self.allocator, .nodes = &self.nodes, .span = span, .float_type = self.catalog.names.get("float").? };
    }
    fn obviousType(self: *Checker, id: ast.NodeId) ?typed.Type {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (self.expected_types.get(node.span)) |expected| return expected;
        if (node.data == .name) if (self.active.get(self.src.text(node.data.name))) |slot| {
            const declared = self.locals.items[@backingInt(slot)].ty;
            if (self.option_facts.has(@backingInt(slot))) if (prelude.optionShape(declared, self.catalog.records)) |shape| return shape.element;
            return declared;
        };
        // A field access over an obviously typed base is itself obvious, so
        // `node.literal == ...` and `node.kind == Kind.atom("x")` can hint the
        // constructor on the other operand the way a plain binding does.
        if (node.data == .field) if (self.obviousFieldType(node.data.field.base, node.data.field.name)) |field_ty| return field_ty;
        if (node.data == .integer and float_syntax.isLiteral(self.src.text(node.data.integer))) return self.catalog.names.get("float");
        return null;
    }
    /// Field type of `base.name` when both the base type and the field are
    /// already known, without diagnosing a miss: this runs in the hint pass,
    /// before the operands themselves are checked.
    fn obviousFieldType(self: *Checker, base_id: ast.NodeId, name: source.Span) ?typed.Type {
        const base = self.obviousType(base_id) orelse return null;
        if (!base.isAggregate()) return null;
        const index = base.recordIndex();
        if (index >= self.catalog.records.len) return null;
        const slot = self.catalog.field_names.items[index].get(self.src.text(name)) orelse return null;
        const declared = self.catalog.records[index].fields;
        if (slot >= declared.len) return null;
        return declared[slot].ty;
    }
    fn hintBinary(self: *Checker, node: ast.Node) Error!void {
        const binary = node.data.binary;
        const expected = self.obviousType(binary.left) orelse self.obviousType(binary.right) orelse self.expected_types.get(node.span) orelse return;
        if (!expected.isInteger() and !numeric_surface.isFloat(expected, self.catalog.records)) {
            // `==`/`!=` operands share one aggregate type, so a typed side gives a
            // contextual constructor on the other side its type (`v == None`,
            // `r == Ok(3)`); any other aggregate operator is unaffected.
            if (binary.op != .eq and binary.op != .ne) return;
            if (self.obviousType(binary.left)) |left| try self.hint(binary.right, left);
            if (self.obviousType(binary.right)) |right| try self.hint(binary.left, right);
            return;
        }
        try self.hint(binary.left, expected);
        try self.hint(binary.right, expected);
    }
    /// Check an expression after recording the type its context expects.
    pub fn expressionExpected(self: *Checker, id: ast.NodeId, expected: typed.Type) Error!typed.NodeId {
        try self.hint(id, expected);
        return self.expression(id);
    }
    /// Recognize an unshadowed `Ok(...)` (true) or `Err(...)` (false) call.
    pub fn resultConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?bool {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.src.text(call.name);
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        if (std.mem.eql(u8, name, "Ok")) return true;
        if (std.mem.eql(u8, name, "Err")) return false;
        return null;
    }
    const builtin_checks = @import("sema_builtins.zig").Checks(Checker);
    pub const cellConstructor = builtin_checks.cellConstructor;
    pub const checkFileAccessCall = builtin_checks.checkFileAccessCall;
    pub const checkFileAccessMethod = builtin_checks.checkFileAccessMethod;
    pub const checkFileMethod = builtin_checks.checkFileMethod;
    pub const checkFloatIntrinsic = builtin_checks.checkFloatIntrinsic;
    pub const checkListSort = builtin_checks.checkListSort;
    pub const checkMethodListSort = builtin_checks.checkMethodListSort;
    pub const checkNumericConversion = builtin_checks.checkNumericConversion;
    pub const checkOptionConstructor = builtin_checks.checkOptionConstructor;
    pub const checkPreludeCall = builtin_checks.checkPreludeCall;
    pub const checkPrint = builtin_checks.checkPrint;
    pub const checkResultConstructor = builtin_checks.checkResultConstructor;
    pub const checkStreamReceiverMethod = builtin_checks.checkStreamReceiverMethod;
    pub const checkStreamWrite = builtin_checks.checkStreamWrite;
    pub const checkUnit = builtin_checks.checkUnit;
    pub const debugBuiltin = builtin_checks.debugBuiltin;
    pub const expectedOption = builtin_checks.expectedOption;
    pub const expectedResult = builtin_checks.expectedResult;
    pub const fileAccessBuiltin = builtin_checks.fileAccessBuiltin;
    pub const fileAccessMethodKind = builtin_checks.fileAccessMethodKind;
    pub const floatIntrinsic = builtin_checks.floatIntrinsic;
    pub const hintEmptyPreludeList = builtin_checks.hintEmptyPreludeList;
    pub const hintSortedArguments = builtin_checks.hintSortedArguments;
    pub const listSortOwner = builtin_checks.listSortOwner;
    pub const numericConversion = builtin_checks.numericConversion;
    pub const optionConstructor = builtin_checks.optionConstructor;
    pub const outputBuiltin = builtin_checks.outputBuiltin;
    pub const preludeName = builtin_checks.preludeName;
    pub const queueListSort = builtin_checks.queueListSort;
    pub const queuePreludeCall = builtin_checks.queuePreludeCall;
    pub const sortedKeywords = builtin_checks.sortedKeywords;
    pub const streamLocal = builtin_checks.streamLocal;
    pub const streamMethod = builtin_checks.streamMethod;
    const collection_checks = @import("sema_collections.zig").Checks(Checker);
    pub const checkAcquireResource = collection_checks.checkAcquireResource;
    pub const checkBufferOperation = collection_checks.checkBufferOperation;
    pub const checkCollectionMethod = collection_checks.checkCollectionMethod;
    pub const checkCollectionSlice = collection_checks.checkCollectionSlice;
    pub const checkComprehension = collection_checks.checkComprehension;
    pub const checkFormat = collection_checks.checkFormat;
    pub const checkListAccess = collection_checks.checkListAccess;
    pub const checkListLiteral = collection_checks.checkListLiteral;
    pub const checkNarrowedMethod = collection_checks.checkNarrowedMethod;
    pub const checkOptionReceiverMethod = collection_checks.checkOptionReceiverMethod;
    pub const checkResourceIo = collection_checks.checkResourceIo;
    pub const collectionSyntax = collection_checks.collectionSyntax;
    pub const listElement = collection_checks.listElement;
    pub const narrowedCollection = collection_checks.narrowedCollection;
    pub const optionReceiverMethod = collection_checks.optionReceiverMethod;
    pub const requireSortable = collection_checks.requireSortable;
    pub const requiresCellEquality = collection_checks.requiresCellEquality;
    const place_checks = @import("sema_places.zig").Checks(Checker);
    pub const arrayKey = place_checks.arrayKey;
    pub const arrayPlace = place_checks.arrayPlace;
    pub const augmented = place_checks.augmented;
    pub const checkArrayPlace = place_checks.checkArrayPlace;
    pub const checkFieldAssignment = place_checks.checkFieldAssignment;
    pub const checkFixedArray = place_checks.checkFixedArray;
    pub const checkIndexAugmented = place_checks.checkIndexAugmented;
    pub const checkTuple = place_checks.checkTuple;
    pub const nonNegative = place_checks.nonNegative;
    pub const referenceParameter = place_checks.referenceParameter;
    pub const requireRebindable = place_checks.requireRebindable;
    pub const twoNameLoopMessage = place_checks.twoNameLoopMessage;

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
        const function = if (signature.type_parameters.len == 0)
            self.ordinary_ids[@backingInt(declaration)]
        else if (target.type_arguments.len != 0 or try self.resultDeterminesArguments(signature, span))
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
    fn resultDeterminesArguments(self: *Checker, signature: ast.FunctionSignature, span: source.Span) Error!bool {
        const expected = self.expected_types.get(span) orelse return false;
        var context: @import("generic_inference.zig").Context = .{ .src = self.src, .catalog = self.catalog, .parameters = signature.type_parameters, .sink = self.sink, .site = span };
        try context.match(signature.return_type, .{ .concrete = expected });
        return context.complete();
    }
    /// Queue the positional values, then `sep=` and `end=`, of a print-shaped call.
    fn queuePrintArguments(self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call"), node: ast.Node) Error!void {
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
    fn queueBuiltinCall(self: *Checker, work: *std.ArrayList(Work), call_id: ast.NodeId, call: @FieldType(@FieldType(ast.Node, "data"), "call"), node: ast.Node) Error!bool {
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
        if (self.streamLocal(call)) |_| {
            if (std.mem.eql(u8, self.src.text(call.name), "write")) {
                try call_arguments.positional(call, self.sink);
                if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "stream.write takes one str or bytes argument");
                try work.append(self.allocator, .{ .id = call.arguments[0] });
                return true;
            }
            try self.queuePrintArguments(work, call, node);
            return true;
        }
        if (try self.debugBuiltin(call)) {
            try self.queuePrintArguments(work, call, node);
            return true;
        }
        if (try self.outputBuiltin(call)) |_| {
            try self.queuePrintArguments(work, call, node);
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
        const span = self.syntax.nodes.items[@backingInt(id)].span;
        if (variant.fielded) {
            const variant_type = try self.variantType(variant, span);
            const tag = try self.catalog.variant(variant_type, self.src, variant.name, self.sink);
            const case = self.catalog.records[variant_type.recordIndex()].shape.variants.?.cases[tag];
            const payload = case.payload orelse return self.sink.failRelated(
                eVariantPayload,
                span,
                "this case carries no payload, so it is constructed without parentheses",
                .{ .span = case.declaration, .message = variantDeclaredHere },
            );
            const record = try self.catalog.record(payload, span, self.sink);
            const initializers = try self.caseInitializers(record, variant.values, variant.value_names, span);
            for (initializers) |initializer| {
                const index = try self.catalog.field(record.id, self.src, initializer.name, self.sink);
                try self.hint(initializer.value, record.fields[index].ty);
            }
            try work.append(self.allocator, .{ .id = id, .emit = true });
            try self.queueFields(work, initializers);
            return true;
        }
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
    /// Bind a parenthesized case's positional and named field arguments to the
    /// payload record's declared fields, appending one initializer per omitted
    /// defaulted field. Arity, unknown, duplicate and missing-field diagnostics
    /// come from the shared record-construction path.
    fn caseInitializers(self: *Checker, record: typed.Record, values: []const ast.NodeId, names: []const ?source.Span, span: source.Span) Error![]const ast.FieldInit {
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
    fn queueCapabilityCall(self: *Checker, work: *std.ArrayList(Work), call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
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
                if (self.narrowedCollection(call) != null) return false;
                // An intrinsic `Option` method on a named local is checked in
                // place, like a narrowed collection method: its receiver and its
                // one argument are the call's own, not queued temporaries.
                if (self.optionReceiverMethod(call)) return false;
                try work.append(self.allocator, .{ .id = id, .emit = true });
                if (try self.queueCapabilityCall(work, call)) return true;
                if (self.environmentMethod(call) != null) return true;
                if (try self.cellConstructor(call) != null) {
                    if (self.expected_types.get(node.span)) |expected| if (expected.isAggregate() and self.catalog.records[expected.recordIndex()].isCell()) {
                        try self.hint(call.arguments[0], self.catalog.records[expected.recordIndex()].fields[0].ty);
                    };
                    try work.append(self.allocator, .{ .id = call.arguments[0] });
                    return true;
                }
                if (try self.queueBuiltinCall(work, id, call, node)) return true;
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
    const call_checks = @import("sema_calls.zig").Checks(Checker);
    pub const byteConversion = call_checks.byteConversion;
    pub const checkCall = call_checks.checkCall;
    pub const checkField = call_checks.checkField;
    pub const checkName = call_checks.checkName;
    pub const environmentMethod = call_checks.environmentMethod;
    pub const recordUpdateCall = call_checks.recordUpdateCall;
    pub const textConstructor = call_checks.textConstructor;
    pub const typeConversion = call_checks.typeConversion;
    const operator_checks = @import("sema_operators.zig").Checks(Checker);
    pub const byteMembership = operator_checks.byteMembership;
    pub const byteValues = operator_checks.byteValues;
    pub const checkConditional = operator_checks.checkConditional;
    pub const checkDictionaryLiteral = operator_checks.checkDictionaryLiteral;
    pub const checkMembership = operator_checks.checkMembership;
    pub const checkTextLiteral = operator_checks.checkTextLiteral;
    pub const checkUnary = operator_checks.checkUnary;
    pub const checkValueBinary = operator_checks.checkValueBinary;
    pub const checkValueIndex = operator_checks.checkValueIndex;
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
                out.ty = try self.variantType(variant, node.span);
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
                    const initializers = try self.caseInitializers(record, variant.values, variant.value_names, node.span);
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
            .length => |input| return self.checkLength(node, input),
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
    fn checkLength(self: *Checker, node: ast.Node, input: ast.NodeId) Error!typed.Node {
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
    pub fn lambdaIndex(self: *Checker, span: source.Span) ?usize {
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
    fn consumedTemporaries(self: *Checker, node: ast.Node, out: typed.Node) Error!usize {
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
    pub fn expressionWithTemporaries(self: *Checker, root: ast.NodeId, inherited: []const typed.Type) Error!typed.NodeId {
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
    pub fn arenaBinding(self: *Checker, name: source.Span) Error!bool {
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
    pub fn arenaReceiver(self: *Checker, id: ast.NodeId) ?typed.LocalId {
        if (self.arenas.items.len == 0) return null;
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data != .name) return null;
        return self.active.get(self.src.text(node.data.name));
    }
    /// Reject an arena-allocated element stored through a collection mutation.
    pub fn requireArenaOperation(self: *Checker, owner: ?typed.LocalId, kind: BufferKind, arguments: []const typed.NodeId) Error!void {
        const slot = owner orelse return;
        if (self.arenas.items.len == 0) return;
        if ((kind == .append or kind == .extend) and arguments.len == 1) return self.requireArenaStore(slot, arguments[0]);
        if (kind != .write or arguments.len != 2) return;
        try self.requireArenaStore(slot, arguments[0]);
        try self.requireArenaStore(slot, arguments[1]);
    }
    /// Reject storing a managed value into a container binding that outlives the arena.
    pub fn requireArenaStore(self: *Checker, owner: typed.LocalId, value: typed.NodeId) Error!void {
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
    pub fn requireArenaAssignment(self: *Checker, slot: typed.LocalId, value: typed.NodeId) Error!void {
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
        if (head.data == .call) {
            const kind = try self.fileAccessBuiltin(head.data.call) orelse self.fileAccessMethodKind(head.data.call);
            if (kind) |access| {
                if (access == .open) self.trapping_open = head.span;
            }
        }
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
    /// Per-arm payload locals: the slot the lowering binds the payload into, the
    /// field-projection prologue that initializes visible bindings, and the names
    /// to remove from scope after the arm.
    const ArmBindings = struct {
        slot: ?typed.LocalId = null,
        prologue: []const typed.StatementId = &.{},
        names: []const []const u8 = &.{},
        fielded: bool = false,
    };
    fn bindArmPayload(self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm) Error!ArmBindings {
        if (case_schema.fielded) return self.bindFieldedPayload(case_schema, arm);
        const payload = case_schema.payload;
        if (arm.bindings.len > 1) return self.sink.failRelated(
            ePatternPayload,
            arm.name,
            "a single-payload case binds one name",
            .{ .span = case_schema.declaration, .message = variantDeclaredHere },
        );
        const discards_payload = arm.bindings.len == 1 and arm.bindings[0] == null;
        if (discards_payload and payload != null and self.requiresHandling(payload.?)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling");
        if ((payload != null) != (arm.bindings.len == 1)) return self.sink.failRelated(
            ePatternPayload,
            arm.name,
            "payload variants require a binding or (discard); empty variants take neither",
            .{ .span = case_schema.declaration, .message = variantDeclaredHere },
        );
        if (arm.bindings.len == 0) return .{};
        const binding = arm.bindings[0] orelse return .{};
        const name = self.src.text(binding);
        if (try self.topLevel(binding) or self.active.contains(name)) return self.sink.fail(eShadowing, binding, "payload binding shadows an active binding or top-level name");
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{ .initialized = true, .transfer_available = self.transfers(payload.?) },
            .name = name,
            .declaration = binding,
            .ty = payload.?,
            .mutable = false,
        });
        try self.active.put(self.allocator, name, slot);
        return .{ .slot = slot, .names = try self.allocator.dupe([]const u8, &.{name}) };
    }
    /// Bind one name per named field. The lowering still stores the payload
    /// record in a hidden slot; every visible binding is a `.field` projection
    /// of it, so typed IR, bytecode and native lowering stay single-slot.
    fn bindFieldedPayload(self: *Checker, case_schema: typed.Variant, arm: ast.MatchArm) Error!ArmBindings {
        const payload = case_schema.payload orelse return error.InternalError;
        const record = try self.catalog.record(payload, arm.name, self.sink);
        if (arm.bindings.len != record.fields.len) return self.sink.failRelated(
            ePatternPayload,
            arm.name,
            "a named-field case pattern binds exactly one name per field, using `_` to discard one",
            .{ .span = case_schema.declaration, .message = variantDeclaredHere },
        );
        var all_discard = true;
        for (arm.bindings) |binding| if (binding != null) {
            all_discard = false;
            break;
        };
        // A pattern that discards every field behaves exactly like `case _` over
        // the whole payload, including its cleanup.
        if (all_discard) {
            if (self.requiresHandling(payload)) return self.sink.fail(eResultDiscard, arm.name, "nested result payload requires a binding and explicit handling");
            return .{};
        }
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{ .initialized = true },
            .usage = .{ .reads = 1, .temporary = true },
            .name = "",
            .declaration = arm.name,
            .ty = payload,
            .mutable = false,
        });
        var prologue: std.ArrayList(typed.StatementId) = .empty;
        var names: std.ArrayList([]const u8) = .empty;
        for (arm.bindings, record.fields, 0..) |binding, field_info, index| {
            const binding_span = binding orelse {
                if (self.requiresHandling(field_info.ty)) return self.sink.failRelated(
                    eResultDiscard,
                    arm.name,
                    "discarding this field would drop a result-bearing payload; bind it and handle the result",
                    .{ .span = field_info.declaration, .message = "result-bearing field declared here" },
                );
                continue;
            };
            const name = self.src.text(binding_span);
            if (try self.topLevel(binding_span) or self.active.contains(name)) return self.sink.fail(eShadowing, binding_span, "payload binding shadows an active binding or top-level name");
            const binding_slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
            try self.locals.append(self.allocator, .{
                .ownership = .{ .initialized = true, .transfer_available = self.transfers(field_info.ty) },
                .name = name,
                .declaration = binding_span,
                .ty = field_info.ty,
                .mutable = false,
            });
            try self.active.put(self.allocator, name, binding_slot);
            try names.append(self.allocator, name);
            const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = arm.name, .ty = payload, .data = .{ .local = slot } });
            const projected: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = binding_span, .ty = field_info.ty, .data = .{ .field = .{ .base = base, .index = index } } });
            try prologue.append(self.allocator, @fromBackingInt(self.statements.items.len));
            try self.statements.append(self.allocator, .{ .span = binding_span, .terminates = false, .data = .{ .initialize = .{ .slot = binding_slot, .value = projected } } });
        }
        return .{ .slot = slot, .prologue = try prologue.toOwnedSlice(self.allocator), .names = try names.toOwnedSlice(self.allocator), .fielded = true };
    }
    fn armCleanup(self: *Checker, bindings: ArmBindings, payload: ?typed.Type, first_local: usize) Error![]const typed.LocalId {
        var cleanup: std.ArrayList(typed.LocalId) = .empty;
        if (bindings.fielded) {
            // A managed payload keeps its trace slot cleared; a move-only payload
            // is owned by the per-field bindings instead, so it is never dropped
            // twice.
            if (bindings.slot) |hidden| if (!typed.moveOnly(payload.?, self.catalog.records) and try self.managedBearing(payload.?)) try cleanup.append(self.allocator, hidden);
            for (self.locals.items[first_local..], first_local..) |local, index| {
                if (bindings.slot != null and @as(usize, @backingInt(bindings.slot.?)) == index) continue;
                if (try self.needsLocalCleanup(local.ty)) try cleanup.append(self.allocator, @fromBackingInt(index));
            }
        } else if (bindings.slot) |payload_slot| if (try self.needsLocalCleanup(payload.?)) try cleanup.append(self.allocator, payload_slot);
        return cleanup.toOwnedSlice(self.allocator);
    }
    fn statementMatch(self: *Checker, stmt: ast.Statement, match: @FieldType(@FieldType(ast.Statement, "data"), "match"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        for (match.arms) |arm| try self.invalidateOptions(arm.body);
        const match_facts = try self.option_facts.snapshot(self.allocator);
        defer self.option_facts.restore(match_facts);
        try self.hintOptionOperand(match.value);
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
            self.option_facts.restore(match_facts);
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
            const case_schema = variants.cases[tag];
            const first_local = self.locals.items.len;
            const arm_bindings = try self.bindArmPayload(case_schema, arm);
            defer for (arm_bindings.names) |name| {
                _ = self.active.remove(name);
            };
            var body = try self.statement(arm.body);
            // The field-projection prologue must run on every path into the arm,
            // including one whose body returns immediately; cleanup is only needed
            // when the body can fall through.
            const cleanup: []const typed.LocalId = if (body.terminates) &.{} else try self.armCleanup(arm_bindings, case_schema.payload, first_local);
            if (arm_bindings.prologue.len != 0 or cleanup.len != 0) {
                const children = try self.allocator.alloc(typed.StatementId, arm_bindings.prologue.len + 1);
                @memcpy(children[0..arm_bindings.prologue.len], arm_bindings.prologue);
                children[arm_bindings.prologue.len] = body.id;
                body.id = @fromBackingInt(self.statements.items.len);
                try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = body.terminates, .owned_cleanup = cleanup, .data = .{ .block = children } });
            }
            if (!body.terminates) {
                try self.mergeMatchInit(&continuation_init);
                try self.requireHandled(first_local, stmt.span);
                if (continuation) |state| try self.samePending(state, stmt.span, eResultPath) else continuation = try self.pendingState(before.len);
            }
            flow.terminates = flow.terminates and body.terminates;
            try arms.append(self.allocator, .{ .tag = tag, .slot = arm_bindings.slot, .body = body.id });
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
        const facts_before = try self.option_facts.snapshot(self.allocator);
        try self.assumeOption(branch.condition, true);
        const then_body = try self.statement(branch.then_body);
        const facts_then = try self.option_facts.snapshot(self.allocator);
        const then_state = try self.pendingState(before.len);
        const init_then = try self.initSnapshot();
        self.restorePending(before);
        self.initRestore(init_before);
        self.option_facts.restore(facts_before);
        try self.assumeOption(branch.condition, false);
        const else_body = if (branch.else_body) |other| try self.statement(other) else null;
        const then_terminates = then_body.terminates;
        const else_terminates = if (else_body) |other| other.terminates else false;
        if (!then_terminates) {
            if (else_terminates) self.option_facts.restore(facts_then) else self.option_facts.intersect(facts_then);
        }
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
    /// Preserve the declared Option when testing its tag, including a repeated guard.
    fn hintOptionOperand(self: *Checker, id: ast.NodeId) Error!void {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data == .name) if (self.active.get(self.src.text(node.data.name))) |slot| {
            try self.hint(id, self.locals.items[@backingInt(slot)].ty);
        };
    }
    /// Payload schema of a local whose original optional value is known present.
    pub fn narrowedOption(self: *Checker, slot: typed.LocalId) ?prelude.OptionShape {
        if (!self.option_facts.has(@backingInt(slot))) return null;
        return prelude.optionShape(self.locals.items[@backingInt(slot)].ty, self.catalog.records);
    }
    /// Apply facts carried by one branch of an already-checked condition.
    pub fn assumeOption(self: *Checker, condition: ast.NodeId, truth: bool) Error!void {
        try self.option_facts.assume(self.allocator, .{ .program = self.syntax, .src = self.src }, .{ .concrete = &self.active }, .{ .condition = condition, .truth = truth });
    }
    /// Remove facts a loop body can invalidate on its next iteration.
    fn invalidateOptions(self: *Checker, body: ast.StatementId) Error!void {
        try self.option_facts.invalidateWrites(self.allocator, .{ .program = self.syntax, .src = self.src }, .{ .concrete = &self.active }, body);
    }
    fn statementLoop(self: *Checker, stmt: ast.Statement, loop: @FieldType(@FieldType(ast.Statement, "data"), "loop"), flow: *StatementFlow) Error!@FieldType(typed.Statement, "data") {
        try self.invalidateOptions(loop.body);
        const loop_facts = try self.option_facts.snapshot(self.allocator);
        defer self.option_facts.restore(loop_facts);
        const before = try self.pendingState(self.locals.items.len);
        const condition = try self.expression(loop.condition);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(loop.condition)].span);
        try self.samePending(before, stmt.span, eResultLoop);
        const loop_id = self.loops.next;
        self.loops.next += 1;
        try self.loops.active.append(self.allocator, .{ .id = loop_id, .before = before, .arenas = self.arenas.items.len });
        defer _ = self.loops.active.pop();
        const init_before = try self.initSnapshot();
        try self.assumeOption(loop.condition, true);
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
    fn statementForEach(self: *Checker, stmt: ast.Statement, each: ForEach) Error!@FieldType(typed.Statement, "data") {
        try self.invalidateOptions(each.body);
        const loop_facts = try self.option_facts.snapshot(self.allocator);
        defer self.option_facts.restore(loop_facts);
        if (try self.preludeIteration(stmt, each)) |statements| return .{ .block = statements };
        const b: collections.Builder(Checker) = .{ .checker = self, .span = stmt.span };
        const source_value = try self.expression(each.iterable);
        const view = dictionary_views.identify(self.catalog, self.nodes.items[@backingInt(source_value)].ty);
        const projected = view != null and view.? != .item;
        const iterable = if (projected) try dictionary_views.owner(Checker, self, stmt.span, source_value) else source_value;
        const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
        // A fixed array iterates like a list over the value it had when the
        // loop began: the loop reads a copy, so element writes in the body
        // change the array but not the elements this loop visits.
        const fixed = arrays.fixed(self.catalog, iterable_type);
        if (fixed == null and !self.collectionType(iterable_type)) return self.sink.fail(eCollectionMethod, stmt.span, "iteration requires a collection, fixed array or dictionary view");
        const kind = self.catalog.records[iterable_type.recordIndex()].collection.kind;
        const element = try self.iterationElement(iterable_type, fixed, if (projected) view else null, stmt.span);
        const unpack = each.index_name != null and !each.enumerated;
        if (unpack and dictionary_views.identify(self.catalog, element) != .item) {
            const pair = record_layouts.tupleRecord(self.catalog.records, element) orelse
                return self.sink.fail("E_ITERATION", stmt.span, "two iteration names require dictionary items, enumerate, zip or a list of two-value tuples");
            if (pair.fields.len != 2) return self.sink.fail(eTupleArity, stmt.span, try self.twoNameLoopMessage(pair.fields.len));
        }
        const first_type = if (unpack) self.catalog.records[element.recordIndex()].fields[0].ty else element;
        // PY-ARRAY-ITER-2: a fixed array's copy is made only if the body writes it.
        var source_walk = try self.beginWalk(b, iterable, fixed);
        const index = try b.local(.i64);
        const limit = try b.local(.i64);
        const first_slot = try b.local(first_type);
        const position = try self.loopPosition(b, each, index);
        const second_slot = if (unpack) try b.local(self.catalog.records[element.recordIndex()].fields[1].ty) else position.slot;
        const names = if (unpack) [_]?source.Span{ each.index_name, each.name } else [_]?source.Span{ each.name, each.index_name };
        const slots = [_]typed.LocalId{ first_slot, second_slot };
        for (names) |maybe_name| if (maybe_name) |name| {
            if (try self.topLevel(name) or self.active.contains(self.src.text(name))) return self.sink.fail(eShadowing, name, eIterationShadow);
        };
        if (each.index_name) |name| if (std.mem.eql(u8, self.src.text(name), self.src.text(each.name))) return self.sink.fail(eShadowing, name, "iteration names must differ");
        for (names, slots) |maybe_name, slot| if (maybe_name) |name| {
            self.locals.items[@backingInt(slot)].name = self.src.text(name);
            self.locals.items[@backingInt(slot)].declaration = name;
            self.locals.items[@backingInt(slot)].ownership.initialized = true;
            self.locals.items[@backingInt(slot)].origin = .iteration;
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
        _ = self.counters.remove(index);
        const owner = try self.endWalk(b, &source_walk);
        self.initRestore(init_before);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        const i = try b.read(index);
        // A fixed array's length is its type's, and nothing can resize it.
        const iteration_check = if (fixed == null) try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) }) else null;
        var iteration_statements: std.ArrayList(typed.StatementId) = .empty;
        if (iteration_check) |guarded| try iteration_statements.append(self.allocator, guarded);
        const value = try self.iterationRead(b, owner, i, .{ .kind = kind, .fixed = fixed, .projection = if (projected) view else null });
        if (unpack) {
            const pair = try b.local(element);
            try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = pair, .value = value } }));
            const first_value = try b.node(first_type, .{ .field = .{ .base = try b.read(pair), .index = 0 } });
            const second_type = self.locals.items[@backingInt(second_slot)].ty;
            const second_value = try b.node(second_type, .{ .field = .{ .base = try b.read(pair), .index = 1 } });
            try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first_slot, .value = first_value } }));
            try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = second_slot, .value = second_value } }));
        } else try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first_slot, .value = value } }));
        try self.appendRebinding(b, &iteration_statements, position, i);
        try iteration_statements.append(self.allocator, body.id);
        const iteration = try b.stmt(.{ .block = try iteration_statements.toOwnedSlice(self.allocator) });
        const advance = try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, i, try b.integer(1), .i64) } });
        const step = try b.stmt(.{ .block = if (iteration_check) |guarded|
            try self.allocator.dupe(typed.StatementId, &.{ guarded, advance })
        else
            try self.allocator.dupe(typed.StatementId, &.{advance}) });
        const setup = [_]typed.StatementId{
            try b.stmt(.{ .initialize = .{ .slot = owner, .value = iterable } }),
            try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
            try b.stmt(.{ .initialize = .{ .slot = limit, .value = if (fixed) |shape| try b.integer(@intCast(shape.length)) else try b.length(owner) } }),
            try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = iteration, .step = step } }),
        };
        // Walking the array in place, the loop reads the variable itself.
        return .{ .block = try self.allocator.dupe(typed.StatementId, setup[@intFromBool(source_walk.in_place)..]) };
    }
    /// PY-FOR-REBIND-1: whether a loop body can assign `name`.
    fn bodyAssigns(self: *Checker, body: ast.StatementId, name: []const u8) Error!bool {
        return loop_rebinding.assigns(self.allocator, .{ .program = self.syntax, .src = self.src }, body, name);
    }
    /// The slot a `for` loop's position binds — only `enumerate` binds one —
    /// and whether it is a variable of its own rather than the loop's counter.
    const Position = struct { slot: typed.LocalId, rebound: bool };
    /// PY-FOR-REBIND-1: an `enumerate` position the body never assigns is the
    /// loop's counter itself, immutable and never negative
    /// (`PY-ARRAY-NEGATIVE-1`); one the body assigns is a variable of its own,
    /// copied from the counter at the top of every iteration.
    fn loopPosition(self: *Checker, b: collections.Builder(Checker), each: ForEach, counter: typed.LocalId) Error!Position {
        if (!each.enumerated) return .{ .slot = counter, .rebound = false };
        if (try self.bodyAssigns(each.body, self.src.text(each.index_name.?))) return .{ .slot = try b.local(.i64), .rebound = true };
        self.locals.items[@backingInt(counter)].mutable = false;
        try self.counters.put(self.allocator, counter, {});
        return .{ .slot = counter, .rebound = false };
    }
    /// Copy the loop's counter into a position variable of its own at the top
    /// of an iteration; a position that is the counter needs nothing.
    fn appendRebinding(self: *Checker, b: collections.Builder(Checker), statements: *std.ArrayList(typed.StatementId), position: Position, counter: typed.NodeId) Error!void {
        if (position.rebound) try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = position.slot, .value = counter } }));
    }
    /// The source a `for` loop reads its elements from, decided around its body.
    const Walk = struct { owner: ?typed.LocalId, variable: ?typed.LocalId, writes: usize, ty: typed.Type, in_place: bool = false };
    /// Start deciding a loop's source. A managed collection is a reference, so
    /// the loop's copy of it is only a pointer and is taken as before. A fixed
    /// array held in a local variable waits for the body.
    fn beginWalk(self: *Checker, b: collections.Builder(Checker), iterable: typed.NodeId, fixed: ?typed.Array) Error!Walk {
        const source_type = self.nodes.items[@backingInt(iterable)].ty;
        if (fixed == null) return .{ .owner = try b.local(source_type), .variable = null, .writes = 0, .ty = source_type };
        const variable = switch (self.nodes.items[@backingInt(iterable)].data) {
            // A `mut` array parameter may be one of two writable names for the
            // same array, so a write through the other would show.
            .local => |slot| if (self.referenceParameter(slot)) null else slot,
            else => null,
        };
        const writes = if (variable) |slot| self.locals.items[@backingInt(slot)].usage.writes else 0;
        return .{ .owner = null, .variable = variable, .writes = writes, .ty = source_type };
    }
    /// PY-ARRAY-ITER-2: once the body is checked, a fixed array the body never
    /// writes is walked where it lives, so the loop copies nothing; otherwise
    /// the loop reads a copy taken when it began, as `PY-ARRAY-ITER-1` says.
    fn endWalk(self: *Checker, b: collections.Builder(Checker), walk: *Walk) Error!typed.LocalId {
        if (walk.owner) |owner| return owner;
        if (walk.variable) |slot| if (self.locals.items[@backingInt(slot)].usage.writes == walk.writes) {
            walk.in_place = true;
            return slot;
        };
        return b.local(walk.ty);
    }
    /// Read the element at `index` of the loop's source copy in `owner`.
    pub fn iterationRead(self: *Checker, b: collections.Builder(Checker), owner: typed.LocalId, index: typed.NodeId, source_shape: IterationShape) Error!typed.NodeId {
        if (source_shape.fixed) |shape| return b.node(shape.element, .{ .index = .{ .base = try b.read(owner), .index = index } });
        return self.projectedIterationValue(b, owner, index, source_shape.kind, source_shape.projection);
    }
    /// Whether a type is a managed collection a loop can walk by position.
    pub fn collectionType(self: *Checker, candidate: typed.Type) bool {
        return candidate.isAggregate() and self.catalog.records[candidate.recordIndex()].isCollection();
    }
    /// The value one `for` iteration binds: a fixed array's element, a
    /// dictionary view's projection, or the collection's own element kind.
    fn iterationElement(self: *Checker, iterable_type: typed.Type, fixed: ?typed.Array, projection: ?dictionary_views.Kind, span: source.Span) Error!typed.Type {
        if (fixed) |shape| return shape.element;
        if (projection) |view| return dictionary_views.element(&self.catalog, iterable_type, view, span);
        const schema = self.catalog.records[iterable_type.recordIndex()];
        return switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .string => iterable_type,
            .bytes => typed.Type.i64,
            .dictionary => schema.collection.key.?,
        };
    }
    /// `for x in reversed(xs):` and `for a, b in zip(xs, ys):` walk their sources
    /// directly, so no intermediate list is materialised.
    fn preludeIteration(self: *Checker, stmt: ast.Statement, each: ForEach) Error!?[]const typed.StatementId {
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
            self.locals.items[@backingInt(slot)].origin = .iteration;
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

    /// Read one iteration element, applying a dictionary view's projection when
    /// the source is keys, values or items and using ordinary collection access otherwise.
    fn projectedIterationValue(
        self: *Checker,
        b: collections.Builder(Checker),
        owner: typed.LocalId,
        index: typed.NodeId,
        kind: ManagedKind,
        projection: ?dictionary_views.Kind,
    ) Error!typed.NodeId {
        if (projection) |view| return dictionary_views.at(Checker, self, b.span, owner, index, view);
        return self.iterationValue(b, owner, kind, index);
    }
    fn statementForRange(self: *Checker, stmt: ast.Statement, range: @FieldType(@FieldType(ast.Statement, "data"), "for_range")) Error!@FieldType(typed.Statement, "data") {
        try self.invalidateOptions(range.body);
        const loop_facts = try self.option_facts.snapshot(self.allocator);
        defer self.option_facts.restore(loop_facts);
        const name = self.src.text(range.name);
        if (try self.topLevel(range.name) or self.active.contains(name)) return self.sink.fail(eShadowing, range.name, "iteration binding shadows an active declaration");
        const zero_start = self.syntax.nodes.items[@backingInt(range.start)].data == .unit;
        const start = if (zero_start) try (collections.Builder(Checker){ .checker = self, .span = range.name }).integer(0) else try self.expression(range.start);
        const end = try self.expression(range.end);
        const element = self.nodes.items[@backingInt(start)].ty;
        try self.requireInteger(element, range.name);
        try self.require(self.nodes.items[@backingInt(end)].ty, element, self.syntax.nodes.items[@backingInt(range.end)].span);
        // PY-FOR-REBIND-1: a body that assigns the name gets its own variable,
        // copied from a hidden counter at the top of every iteration, so the
        // assignment never changes which iteration comes next.
        const rebound = try self.bodyAssigns(range.body, name);
        const index: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .name = if (rebound) "<range-index>" else name,
            .declaration = range.name,
            .ty = element,
            .mutable = false,
            .ownership = .{ .initialized = true },
            .usage = .{ .reads = 1, .temporary = rebound },
        });
        // PY-ARRAY-NEGATIVE-1: an immutable induction variable counting up
        // from a non-negative start never holds a negative value.
        if (!rebound and self.nonNegative(start, 0)) try self.counters.put(self.allocator, index, {});
        const limit: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = "<range-limit>", .declaration = range.name, .ty = element, .mutable = false, .usage = .{ .reads = 1, .temporary = true } });
        const variable: typed.LocalId = if (rebound) try self.reboundVariable(range.name, element) else index;
        try self.active.put(self.allocator, name, variable);
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
        const iteration = if (rebound) try self.rebindFirst(range.name, variable, index_node, body.id) else body.id;
        children[2] = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = stmt.span, .terminates = false, .data = .{ .loop = .{ .id = loop_id, .condition = condition, .body = iteration, .step = step } } });
        return .{ .block = children };
    }
    /// PY-FOR-REBIND-1: the visible loop variable of a counting loop whose body
    /// assigns it: an ordinary mutable local, bound for the whole body.
    fn reboundVariable(self: *Checker, name: source.Span, element: typed.Type) Error!typed.LocalId {
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{ .name = self.src.text(name), .declaration = name, .ty = element, .mutable = true, .ownership = .{ .initialized = true }, .usage = .{ .reads = 1 }, .origin = .iteration });
        return slot;
    }
    /// One iteration of a counting loop whose body assigns its variable: the
    /// variable takes the hidden counter's value, then the body runs.
    fn rebindFirst(self: *Checker, span: source.Span, variable: typed.LocalId, counter: typed.NodeId, body: typed.StatementId) Error!typed.StatementId {
        const b: collections.Builder(Checker) = .{ .checker = self, .span = span };
        const copy = try b.stmt(.{ .initialize = .{ .slot = variable, .value = counter } });
        return b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{ copy, body }) });
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
    /// A rendered message is checked as `str` here but evaluated only on failure,
    /// which is why the effect pass exempts its expression from the ceiling.
    fn statementAssert(self: *Checker, claim: ast.Assertion) Error!@FieldType(typed.Statement, "data") {
        const condition = try self.expressionExpected(claim.condition, .bool);
        try self.require(self.nodes.items[@backingInt(condition)].ty, .bool, self.syntax.nodes.items[@backingInt(claim.condition)].span);
        const message_value = if (claim.value) |value| message: {
            const str_type = self.catalog.names.get("str") orelse return error.InternalError;
            const checked = try self.expressionExpected(value, str_type);
            try self.require(self.nodes.items[@backingInt(checked)].ty, str_type, self.syntax.nodes.items[@backingInt(value)].span);
            break :message checked;
        } else null;
        return .{ .assertion = .{ .condition = condition, .message = claim.message, .message_value = message_value } };
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
            // A binding initialized from an index read holds an element copy,
            // which is what makes a later field write dead when never read.
            .origin = if (self.syntax.nodes.items[@backingInt(b.value)].data == .index) .collection_copy else .local,
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
        try self.requireRebindable(slot, a.name);
        var value = try self.expressionExpected(a.value, self.locals.items[@backingInt(slot)].ty);
        if (a.op != .set) {
            try self.requireReadable(slot, a.name);
            const target_type = self.locals.items[@backingInt(slot)].ty;
            try self.require(self.nodes.items[@backingInt(value)].ty, target_type, a.op_span);
            // `values += other` is Python's in-place extend, not a fresh list.
            if (a.op == .add and target_type.isAggregate() and self.catalog.records[target_type.recordIndex()].isCollection() and self.catalog.records[target_type.recordIndex()].collection.kind == .list) {
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
        // A plain reassignment re-homes the value, so its copy provenance follows
        // the new initializer; an indexed read still yields an element copy.
        if (a.op == .set) self.locals.items[@backingInt(slot)].origin = if (self.syntax.nodes.items[@backingInt(a.value)].data == .index) .collection_copy else .local;
        // A reassignment definitely binds the name on this path and re-homes it out
        // of any arena it was previously confined to.
        self.locals.items[@backingInt(slot)].ownership.initialized = true;
        self.locals.items[@backingInt(slot)].ownership.arena_confined = false;
        self.option_facts.forget(@backingInt(slot));
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
            // `mut` promises a write the caller can observe, so it is accepted
            // only on a type that can carry one. Rejecting it here, before any
            // body or call is checked, keeps the declaration out of the published
            // footprint: the call site reports the missing marker instead.
            const reference = parameter.mut and typed.referenceArray(self.catalog.records, parameter_type);
            if (reference) {
                if (function.policy.host != null or function.policy.c_abi) {
                    try markMutRejected(self);
                    return sink.fail(mutation_marker_code, parameter.ty, "a host or C ABI function cannot take a `mut` fixed array; pass the array and return the changed copy");
                }
                if (self.transfers(parameter_type)) {
                    try markMutRejected(self);
                    return sink.fail(mutation_marker_code, parameter.ty, "a `mut` fixed array needs copyable elements without pending results");
                }
            }
            const writable = reference or typed.carriesWritableStorage(self.catalog.records, parameter_type);
            if (parameter.mut and !writable) {
                try markMutRejected(self);
                return sink.fail(
                    mutation_marker_code,
                    parameter.ty,
                    try std.fmt.allocPrint(
                        allocator,
                        "`mut` on `{s}` has nothing to write; only a list, dict, class, Cell, array, byte buffer or a record holding one can be `mut`",
                        .{typed.typeName(parameter_type, self.catalog.records)},
                    ),
                );
            }
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
                    .origin = .parameter,
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
fn checkGenericContracts(src: source.Source, program: ast.Program, sink: *diagnostic.Sink, catalog: records.Catalog, symbolic: *?generic_cache.Session) Error!void {
    const session: ?*generic_cache.Session = if (symbolic.*) |*reuse| reuse else null;
    try @import("generic_bodies.zig").checkWithCatalogCached(sink.allocator, src, program, sink, catalog, session);
}
/// Open the C3 symbolic session when this request has both a semantic cache and
/// a prepared ordinary session. Kept separate so `checkCached` stays readable.
fn openSymbolicSession(cache: ?*semantic_cache.Cache, session: *?semantic_cache.Session, src: source.Source, project_mode: bool) Error!?generic_cache.Session {
    const c = cache orelse return null;
    if (session.*) |*queries| {
        const opened = try c.symbolicSession(src, &queries.prepared, if (project_mode) "project" else "unit");
        return opened;
    }
    return null;
}
/// Release an optional symbolic session without branching in `checkCached`.
fn deinitSymbolic(session: *?generic_cache.Session) void {
    if (session.*) |*reuse| reuse.deinit();
}
/// Open the C3 concrete-specialization session beside the ordinary one. The
/// prepared declaration facts outlive the request through the caller's
/// `semantic_cache.Session`.
fn openSpecializationSession(cache: ?*semantic_cache.Cache, session: *?semantic_cache.Session) Error!?generic_specializations.Session {
    const c = cache orelse return null;
    _ = c;
    if (session.*) |*queries| {
        const opened = try queries.cache.specializationSession(&queries.prepared);
        return opened;
    }
    return null;
}
/// Release an optional specialization session without branching in `checkCached`.
fn deinitSpecialization(session: *?generic_specializations.Session) void {
    if (session.*) |*reuse| reuse.deinit();
}
/// Populate the per-request specialization identity maps and prepared facts.
fn initSpecializationReuse(
    checker: *Checker,
    allocator: std.mem.Allocator,
    catalog_records: []const typed.Record,
    session: *?semantic_cache.Session,
    spec_session: *?generic_specializations.Session,
) Error!void {
    checker.prepared = if (session.*) |*queries| &queries.prepared else null;
    checker.spec_build = if (spec_session.*) |*reuse| reuse.backend.build else "";
    checker.initial_record_count = catalog_records.len;
    if (checker.prepared) |prepared| for (prepared.ordinary_ast, 0..) |ast_index, instance| {
        const entry = try checker.ordinary_instance_by_key.getOrPut(allocator, prepared.keys[ast_index]);
        if (entry.found_existing) entry.value_ptr.* = std.math.maxInt(usize) else entry.value_ptr.* = instance;
    };
    for (catalog_records, 0..) |record, index| {
        const entry = try checker.record_by_name.getOrPut(allocator, record.name);
        if (entry.found_existing) entry.value_ptr.* = std.math.maxInt(usize) else entry.value_ptr.* = index;
    }
}
/// Active opt-in phase recorder, if any. Timing never changes semantic results.
fn activeTiming(cache: ?*semantic_cache.Cache) ?*timings.Profile {
    const c = cache orelse return null;
    const p = c.context.timing orelse return null;
    return if (p.enabled) p else null;
}
fn timingStart(timing: ?*timings.Profile) ?std.Io.Timestamp {
    if (timing) |p| return p.now();
    return null;
}
fn timingAdd(timing: ?*timings.Profile, name: []const u8, start: ?std.Io.Timestamp) void {
    if (timing) |p| if (start) |at| p.addSince(name, at, false);
}

/// Look up one checked body, preferring the ordinary store and falling back to
/// the concrete-specialization store. Counts performed/reused work at the same
/// site so `work-report-v1` never infers reuse from a fingerprint.
fn reuseBody(
    checker: *Checker,
    session: *?semantic_cache.Session,
    spec_session: *?generic_specializations.Session,
    cache: ?*semantic_cache.Cache,
    allocator: std.mem.Allocator,
    i: usize,
) Error!?typed.Function {
    const timing = activeTiming(cache);
    var function: ?typed.Function = null;
    if (session.*) |*queries| {
        const start = timingStart(timing);
        function = try queries.lookup(allocator, i, &checker.nodes, &checker.statements);
        timingAdd(timing, "ordinary_body_replay", start);
    }
    if (function == null and i >= checker.ordinary_count) {
        if (spec_session.*) |*reuse| {
            const start = timingStart(timing);
            function = try checker.lookupSpecialization(reuse, allocator, i, &checker.nodes, &checker.statements);
            timingAdd(timing, "specialization_body_replay", start);
        }
    }
    if (function == null) {
        if (cache) |c| c.statistics.checked += 1;
        if (i >= checker.ordinary_count) if (spec_session.*) |*reuse| reuse.noteChecked();
    } else if (i >= checker.ordinary_count) {
        if (cache) |c| c.statistics.reused += 1;
    }
    return function;
}
/// One body's fresh interval recording inputs.
const RangeRecord = struct {
    checker: *Checker,
    session: *?semantic_cache.Session,
    allocator: std.mem.Allocator,
    index: usize,
    start_nodes: usize,
    start_statements: usize,
    reused: bool,
};
/// Record the fresh node/statement interval for one body and remember a fresh
/// specialization for publication.
fn recordBodyRange(record: RangeRecord) Error!void {
    const checker = record.checker;
    const range: sem_copy.Range = .{
        .nodes = .{ .start = record.start_nodes, .end = checker.nodes.items.len },
        .statements = .{ .start = record.start_statements, .end = checker.statements.items.len },
    };
    if (record.session.*) |*queries| {
        if (record.index < queries.ranges.len) queries.ranges[record.index] = range;
    }
    if (record.index < checker.spec_ranges.items.len) checker.spec_ranges.items[record.index] = range;
    if (!record.reused and record.index >= checker.ordinary_count) try checker.spec_fresh.append(record.allocator, record.index);
}
/// Publish freshly checked specializations only after every cross-function pass
/// succeeded.
fn publishSpecializationSession(
    spec_session: *?generic_specializations.Session,
    checker: *Checker,
    allocator: std.mem.Allocator,
    program: typed.Program,
) Error!void {
    if (spec_session.*) |*reuse| try checker.publishSpecializations(reuse, allocator, program);
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

/// Validate the capability tail of the entry signature, splitting Streams by
/// name so `out: Stream` and `err: Stream` may both appear.
fn validateEntryParameters(src: source.Source, checker: *Checker, sink: *diagnostic.Sink, entry: ast.Function) Error!void {
    const first_capability = try entryParameterStart(entry.signature.parameters, checker, sink);
    var entry_capabilities: u8 = 0;
    var entry_streams: [2]bool = .{ false, false };
    for (entry.signature.parameters[first_capability..]) |parameter| {
        const parameter_ty = try checker.ty(parameter.ty);
        if (parameter_ty.isStream()) {
            const name = src.text(parameter.name);
            const slot: usize = if (std.mem.eql(u8, name, "out")) 0 else if (std.mem.eql(u8, name, "err")) 1 else return sink.fail("E_MAIN", parameter.name, "entry Stream parameters must be named `out` or `err`");
            if (entry_streams[slot]) return sink.fail("E_MAIN", parameter.name, "entry requests at most one `out` and one `err` Stream");
            entry_streams[slot] = true;
            continue;
        }
        const index = parameter_ty.capabilityIndex() orelse return sink.fail("E_MAIN", parameter.ty, "entry parameters must be `args: list[str]` followed by capabilities");
        const bit = @as(u8, 1) << index;
        if (entry_capabilities & bit != 0) return sink.fail("E_MAIN", parameter.name, "entry requests at most one value parameter of each capability kind");
        entry_capabilities |= bit;
    }
}

/// E2: flag ordinary source functions whose name span is an exported interface
/// symbol. Concrete generic specializations are implementation details (their
/// template is checked abstractly) and synthesized entry/lambda bodies have no
/// module declaration.
fn exportedFunctions(allocator: std.mem.Allocator, module_names: ?*Names, functions: []const typed.Function) Error![]bool {
    const exported = try allocator.alloc(bool, functions.len);
    for (functions, 0..) |function, index| {
        exported[index] = function.type_arguments.len == 0 and
            !std.mem.startsWith(u8, function.name, "lambda@") and
            !std.mem.eql(u8, function.name, entry_adapter.wrapper_name) and
            (if (module_names) |names| names.index.functionExported(names.src, function.declaration) else false);
    }
    return exported;
}

/// Reuse supported checked bodies, then rerun all cross-function validation passes.
pub fn checkCached(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names, cache: ?*semantic_cache.Cache) Error!typed.Program {
    defer normalizeDiagnostics(sink);
    const timing = activeTiming(cache);
    const catalog = try records.collectWithNames(allocator, src, program, sink, module_names);
    var session = if (cache) |c| try c.begin(allocator, src, program, catalog.records) else null;
    var symbolic = try openSymbolicSession(cache, &session, src, module_names != null);
    defer deinitSymbolic(&symbolic);
    var spec_session = try openSpecializationSession(cache, &session);
    defer deinitSpecialization(&spec_session);
    var failed = false;
    const symbolic_start = timingStart(timing);
    checkGenericContracts(src, program, sink, catalog, &symbolic) catch |err| switch (err) {
        error.SourceError => failed = true,
        else => return err,
    };
    timingAdd(timing, "symbolic_templates", symbolic_start);
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
    // C3 reuse: prepared declaration facts and fresh identity maps are
    // per-request; only populated when a semantic cache is attached.
    try initSpecializationReuse(&checker, allocator, catalog.records, &session, &spec_session);
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
            try checker.spec_fingerprints.append(allocator, null);
            try checker.spec_ranges.append(allocator, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
        }
    }
    checker.lambda_start = checker.instance_keys.items.len;
    for (program.lambdas) |_| {
        try checker.instance_keys.append(allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{} });
        try checker.spec_fingerprints.append(allocator, null);
        try checker.spec_ranges.append(allocator, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
    }
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
    // capability of each kind. Streams split by name, so `out: Stream` and
    // `err: Stream` may both appear; any other Stream name is rejected.
    try validateEntryParameters(src, &checker, sink, entry);
    if (!entry_adapter.supported(try checker.ty(entry.signature.return_type), checker.catalog.records)) return sink.fail("E_TYPE", entry.signature.return_type, "main must return int, None, Result<None/int,int>, or Result[int,str]");
    var checked_functions: std.ArrayList(typed.Function) = .empty;
    var i: usize = 0;
    while (i < checker.instance_keys.items.len and (!contracts_failed or i < checker.ordinary_count)) : (i += 1) {
        const start_nodes = checker.nodes.items.len;
        const start_statements = checker.statements.items.len;
        const reused = try reuseBody(&checker, &session, &spec_session, cache, allocator, i);
        const fresh = reused == null;
        const fresh_start = if (fresh) timingStart(timing) else null;
        defer if (fresh) timingAdd(timing, "fresh_body_check", fresh_start);
        const function = reused orelse checker.checkFunction(i) catch |err| switch (err) {
            error.SourceError => {
                failed = true;
                continue;
            },
            else => return err,
        };
        try recordBodyRange(.{
            .checker = &checker,
            .session = &session,
            .allocator = allocator,
            .index = i,
            .start_nodes = start_nodes,
            .start_statements = start_statements,
            .reused = reused != null,
        });
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
    const entry_start = timingStart(timing);
    try entry_adapter.adapt(allocator, &checked);
    const exported = try exportedFunctions(allocator, module_names, checked.functions);
    timingAdd(timing, "entry_adaptation", entry_start);
    const effects_start = timingStart(timing);
    try @import("effects.zig").check(allocator, checked, .{ .exported = exported, .src = src, .syntax = program, .sink = sink });
    timingAdd(timing, "effect_origin_passes", effects_start);
    const codecs_start = timingStart(timing);
    try @import("domain_codecs.zig").check(allocator, src, program.types.domains, checker.catalog, .{ .items = functions, .names = executable_names }, sink);
    timingAdd(timing, "domain_codec_validation", codecs_start);
    const warnings_start = timingStart(timing);
    try warnBindings(allocator, functions, sink);
    try warnImports(module_names, sink);
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    timingAdd(timing, "warning_derivation", warnings_start);
    // A rejected dead copy write is an implementation error, not advice: it must
    // stop checking before retention publishes an invalid program.
    for (sink.items.items) |item| if (item.severity == .err) return error.SourceError;
    const retain_start = timingStart(timing);
    try publishSpecializationSession(&spec_session, &checker, allocator, checked);
    if (session) |*queries| try queries.remember(checked);
    timingAdd(timing, "retention_store_io", retain_start);
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
    @import("data_type.zig").checkHost(allocator, catalog, ty) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return sink.fail("E_HOST_SIGNATURE", span, "host signatures require ordinary data, or `bytes`, without capabilities or other runtime-owned storage"),
    };
}

fn warnBindings(allocator: std.mem.Allocator, functions: []const typed.Function, sink: *diagnostic.Sink) Error!void {
    for (functions) |function| {
        if (function.policy.host != null) continue;
        for (function.scope.locals) |local| {
            if (local.usage.dead_write_span) |span| {
                // Each field write reads its destination once; a read beyond that
                // means the copied binding is observed after the write. A copy
                // whose only reads are the write itself can never reach the
                // original storage, so the mistake is rejected rather than
                // shipped with a warning.
                if (local.origin != .local and local.usage.reads == local.usage.dead_write_reads) try sink.items.append(allocator, .{
                    .severity = .err,
                    .code = "E_DEAD_RECORD_WRITE",
                    .span = span,
                    .message = "field write to a `record` copy is never observed; `record` values are copies, so the write cannot reach the original; use `class` for reference semantics, or return the updated record",
                });
            }
            if (local.usage.temporary or local.usage.reads != 0) continue;
            // A capability parameter is the signature's whole claim to an
            // effect: a body that never reads it promises authority it does not
            // use, so the over-claim is rejected rather than warned about.
            if (local.origin == .parameter and local.ty.capabilityIndex() != null) {
                const message = try std.fmt.allocPrint(
                    allocator,
                    "`{s}` is never used, so this signature claims an effect the body cannot have; remove the parameter or use it",
                    .{local.name},
                );
                try sink.items.append(allocator, .{
                    .severity = .err,
                    .code = @import("effects.zig").unused_capability_code,
                    .span = local.declaration,
                    .message = message,
                });
                continue;
            }
            try sink.items.append(allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_BINDING",
                .span = local.declaration,
                .message = "binding is never read; use it or remove it, preserving initializer effects with `_ =` when needed",
            });
        }
    }
}

/// One module-level warning for every direct import no reference resolved
/// through. The evidence is the interface index's resolved-import flags, so a
/// local binding that merely spells the alias cannot make an unused import look
/// used; a cached body that was replayed rather than re-resolved is recovered
/// from its own qualified names first.
fn warnImports(module_names: ?*Names, sink: *diagnostic.Sink) Error!void {
    const names = module_names orelse return;
    const index = names.index;
    index.recoverImportUsage(sink.allocator);
    for (index.project.order.items) |module| {
        const imports = index.project.modules.items[module].imports;
        for (imports, 0..) |imported, import_index| {
            if (index.importUsed(module, import_index)) continue;
            const span = names.src.mappedSpan(module, imported.span) catch continue;
            const message = try std.fmt.allocPrint(sink.allocator, "import `{s}` is never referenced in this module; remove it or use it", .{imported.name});
            try sink.items.append(sink.allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_IMPORT",
                .span = span,
                .message = message,
            });
        }
    }
}
