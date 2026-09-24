//! Scope and type checking use resolved binding identities, including advisory use counts.
const sema_shared = @import("sema_shared.zig");
const sema_contracts = @import("sema_contracts.zig");
const buffer_operations = @import("buffer_operations.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const loop_rebinding = @import("loop_rebinding.zig");
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const external_resources = @import("external_resources.zig");
const io_builtins = @import("io_builtins.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const lambda_context_code = sema_shared.lambda_context_code;
const call_argument_code = sema_shared.call_argument_code;
/// Stable code for a call-site `&` mutation marker that does not match the
/// callee's declared `mutates(...)` footprint.
const eResultOperation = diagnostic.result_operation;
const eOwnedConsumed = diagnostic.owned_consumed;
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
const eConversionBody = "E_CONVERSION_BODY";
const sem_copy = @import("semantic_copy.zig");
const generic_specializations = @import("generic_specializations.zig");
const semantic_key = @import("semantic_key.zig");
const sem_entry = @import("semantic_entry.zig");

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
const variantDeclaredHere = sema_shared.variantDeclaredHere;
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
const sema_summaries = @import("sema_summaries.zig");
const origins = @import("origins.zig");
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

const StatementFlow = sema_shared.StatementFlow;

const integer_literal = @import("integer_literal.zig");
const float_syntax = @import("float_syntax.zig");
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const arrays = @import("array_literals.zig");
const variant_calls = @import("variant_calls.zig");
const truncating = @import("truncating_math.zig");

const LambdaCapture = sema_shared.LambdaCapture;
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
    /// Contract clauses of the function being checked and the invariant index.
    contract: sema_contracts.State = .{},

    /// Reset the per-function state and bind one ordinary instance's signature:
    /// its owner, return type and parameter locals.
    fn beginFunction(self: *Checker, i: usize, function: ast.Function) Error!void {
        self.checked_index = i;
        self.current_function = @fromBackingInt(i);
        self.current_lambda = null;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.option_facts.clear();
        self.locals = .empty;
        self.counters.clearRetainingCapacity();
        self.active.clearRetainingCapacity();
        self.owner = if (function.policy.owner) |owner| try self.ty(owner) else null;
        self.return_type = try self.ty(function.signature.return_type);
        self.contract.ensures = &.{};
        self.contract.olds = &.{};
        try self.bindParameters(function);
    }
    /// The checked function record of ordinary instance `i` with body `body`.
    fn finishFunction(self: *Checker, i: usize, function: ast.Function, body: typed.StatementId) Error!typed.Function {
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
                .body = body,
                .locals = try self.locals.toOwnedSlice(self.allocator),
            },
            .id = @fromBackingInt(i),
            .name = try self.instanceName(@fromBackingInt(i)),
            .type_arguments = self.instance_keys.items[i].arguments,
            .declaration = function.name,
        };
    }
    /// A stand-in for an unchanged ordinary body: the checked signature and
    /// parameter locals over an empty body, which no later pass walks. Its
    /// summary supplies the facts and diagnostics its body would.
    fn standInFunction(self: *Checker, i: usize) Error!typed.Function {
        const function = self.syntaxFunction(@fromBackingInt(i));
        try self.beginFunction(i, function);
        const body: typed.StatementId = @fromBackingInt(self.statements.items.len);
        try self.statements.append(self.allocator, .{ .span = self.syntax.statements.items[@backingInt(function.body)].span, .terminates = true, .data = .{ .block = &.{} } });
        return self.finishFunction(i, function, body);
    }
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
        const first_node = self.nodes.items.len;
        const constant_context: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        const declaration = @backingInt(self.instance_keys.items[i].declaration);
        const constant = if (function.policy.constant and try constant_context.literalType(declaration) == null) try constant_context.evaluate(declaration) else null;
        try self.beginFunction(i, function);
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
        // Preconditions and `old(...)` captures run after the parameters are
        // bound and before the body; postconditions wrap every return.
        const prologue = try self.contractPrologue(function);
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
        if (prologue.len != 0) {
            const children = try std.mem.concat(allocator, typed.StatementId, &.{ prologue, &.{body.id} });
            body.id = @fromBackingInt(self.statements.items.len);
            try self.statements.append(allocator, .{ .span = self.syntax.statements.items[@backingInt(function.body)].span, .terminates = true, .data = .{ .block = children } });
        }
        try self.enforceInvariants(first_node);
        return self.finishFunction(i, function, body.id);
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
        self.contract.ensures = &.{};
        self.contract.olds = &.{};
        const first_node = self.nodes.items.len;
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
        try self.enforceInvariants(first_node);
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
    /// Resolve a constant-length type argument: a literal at top level, or a length
    /// parameter of the current specialization.
    pub fn lengthArgument(self: *Checker, span: source.Span) Error!usize {
        const id = self.current_function orelse return @import("generic_lengths.zig").literal(self.src, span, self.sink);
        const key = self.instance_keys.items[@backingInt(id)];
        return @import("generic_lengths.zig").resolve(self.src, span, self.syntaxFunction(id).signature.type_parameters, key.lengths, self.sink);
    }
    const specialization_checks = @import("sema_specialize.zig").Checks(Checker);
    pub const lookupSpecialization = specialization_checks.lookupSpecialization;
    pub const publishSpecializations = specialization_checks.publishSpecializations;
    pub const specialize = specialization_checks.specialize;
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
    /// Require every result-bearing local declared since `first` to be handled before
    /// it leaves scope.
    pub fn requireHandled(self: *Checker, first: usize, span: source.Span) Error!void {
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
        // `old(...)` is contract syntax, bound before the call is ever resolved
        // inside `@ensures`; reaching it here means it is misplaced or nested.
        if (input.owner == null and std.mem.eql(u8, self.src.text(input.name), "old") and !try self.topLevel(input.name))
            return self.sink.fail(sema_contracts.old_code, span, if (self.contract.checking == .ensures) "`old(...)` cannot nest inside another `old(...)`" else "`old(...)` is only legal inside `@ensures`");
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
    /// Reject access to a domain's representation outside the functions it declares.
    pub fn requireDomainAccess(self: *Checker, domain_type: typed.Type, span: source.Span) Error!void {
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
    /// Push a record literal's field initializers onto the work queue in source order.
    pub fn queueFields(self: *Checker, work: *std.ArrayList(Work), initializers: []const ast.FieldInit) Error!void {
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
        const set = if (receiver) |receiver_type| typed.setRecord(self.catalog.records, receiver_type) != null else false;
        const spellings = if (set)
            try buffer_operations.setMethodSpellings(self.allocator)
        else if (family) |kind|
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
            .set = typed.isSet(schema),
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
    pub fn mergeMatchInit(self: *Checker, merged: *?[]bool) Error!void {
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
    /// Fold `-N` into one literal when it fits the expected type, so the most negative
    /// value of a width is accepted.
    pub fn minimum(self: *Checker, node: ast.Node) Error!?Literal {
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
    /// Type an integer literal against its expected type, or as a float literal when
    /// spelled or expected as one.
    pub fn checkInteger(self: *Checker, node: ast.Node) Error!typed.Node {
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
    /// Give a binary operator's untyped operand the type of its typed side or context.
    pub fn hintBinary(self: *Checker, node: ast.Node) Error!void {
        const binary = node.data.binary;
        const expected = self.obviousType(binary.left) orelse self.obviousType(binary.right) orelse self.expected_types.get(node.span) orelse return;
        if (!expected.isInteger() and !numeric_surface.isFloat(expected, self.catalog.records)) {
            // `==`/`!=` operands share one aggregate type, so a typed side gives a
            // contextual constructor on the other side its type (`v == None`,
            // `r == Ok(3)`); so do the set operators (`s | {3}`), whose two
            // operands are sets of one type. Any other aggregate operator is
            // unaffected.
            const set_operands = typed.setRecord(self.catalog.records, expected) != null;
            if (binary.op != .eq and binary.op != .ne and !set_operands) return;
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
    pub const checkSetFromIterable = collection_checks.checkSetFromIterable;
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
    const set_checks = @import("sema_sets.zig").Checks(Checker);
    pub const checkEmptySet = set_checks.checkEmptySet;
    pub const checkSetBinary = set_checks.checkSetBinary;
    pub const checkSetLiteral = set_checks.checkSetLiteral;
    pub const checkSetMethod = set_checks.checkSetMethod;
    pub const checkSetMethodSyntax = set_checks.checkSetMethodSyntax;
    pub const requireSetElement = set_checks.requireSetElement;
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

    const expression_checks = @import("sema_expressions.zig").Checks(Checker);
    pub const expressionWithTemporaries = expression_checks.expressionWithTemporaries;
    pub const lambdaIndex = expression_checks.lambdaIndex;
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
    /// Whether a local of this type needs cleanup when it leaves scope: a file,
    /// a move-only value, or a value holding managed storage.
    pub fn needsLocalCleanup(self: *Checker, local_type: typed.Type) Error!bool {
        if (local_type.isFile()) return true;
        if (typed.moveOnly(local_type, self.catalog.records)) return true;
        return self.managedBearing(local_type);
    }
    /// Whether values of this type may hold a garbage-collected reference, including
    /// references nested inside records, variants, options, results and arrays.
    pub fn managedBearing(self: *Checker, local_type: typed.Type) Error!bool {
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
        // `update` copies every entry of its operand in, exactly as `extend`
        // copies every element, so an arena-held operand is refused the same way.
        if ((kind == .append or kind == .extend or kind == .update) and arguments.len == 1) return self.requireArenaStore(slot, arguments[0]);
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
    pub fn requireArenaReturn(self: *Checker, value: typed.NodeId, span: source.Span) Error!void {
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
    const contract_checks = sema_contracts.Checks(Checker);
    pub const indexInvariants = contract_checks.indexInvariants;
    pub const contractSeeded = contract_checks.contractSeeded;
    pub const contractPrologue = contract_checks.contractPrologue;
    pub const contractReturn = contract_checks.contractReturn;
    pub const enforceInvariants = contract_checks.enforceInvariants;
    const statement_checks = @import("sema_statements.zig").Checks(Checker);
    pub const statement = statement_checks.statement;
    pub const unitFallthrough = statement_checks.unitFallthrough;
    /// Preserve the declared Option when testing its tag, including a repeated guard.
    pub fn hintOptionOperand(self: *Checker, id: ast.NodeId) Error!void {
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
    pub fn invalidateOptions(self: *Checker, body: ast.StatementId) Error!void {
        try self.option_facts.invalidateWrites(self.allocator, .{ .program = self.syntax, .src = self.src }, .{ .concrete = &self.active }, body);
    }
    const loop_checks = @import("sema_loops.zig").Checks(Checker);
    pub const collectionType = loop_checks.collectionType;
    pub const iterationRead = loop_checks.iterationRead;
    pub const statementForEach = loop_checks.statementForEach;
    pub const statementForRange = loop_checks.statementForRange;
    pub const statementLoop = loop_checks.statementLoop;
    pub const statementLoopExit = loop_checks.statementLoopExit;
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
/// Syntax size above which checking reserves its checked tables up front.
const presize_threshold = 1 << 14;
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
/// Open the stand-in plan for a request whose cache carries a summary request.
fn openPlan(cache: ?*semantic_cache.Cache, session: *?semantic_cache.Session, allocator: std.mem.Allocator, main: usize) Error!?sema_summaries.Plan {
    const c = cache orelse return null;
    const request = c.context.summaries orelse return null;
    const queries = if (session.*) |*opened| opened else return null;
    const timing = activeTiming(cache);
    const start = timingStart(timing);
    defer timingAdd(timing, "stand_in_planning", start);
    const plan = try sema_summaries.Plan.init(allocator, request, queries, main);
    return plan;
}
/// Mark a failed stand-in attempt for a full retry and pass the error on. A
/// check with no stood-in body reports its diagnostics as they are.
fn retryOr(plan: *?sema_summaries.Plan, err: Error) Error {
    if (err == error.SourceError) if (plan.*) |*active| if (active.active()) {
        active.request.retry = true;
    };
    return err;
}
/// Everything one body step reads: the checker, the reuse sessions, the
/// stand-in plan and the instance to check.
const InstanceStep = struct {
    checker: *Checker,
    session: *?semantic_cache.Session,
    spec_session: *?generic_specializations.Session,
    cache: ?*semantic_cache.Cache,
    plan: *?sema_summaries.Plan,
    allocator: std.mem.Allocator,
    index: usize,
};
/// Check, reuse or stand in for one instance's body. Null means the body
/// failed and its diagnostics are in the sink.
fn checkInstance(step: InstanceStep) Error!?typed.Function {
    const checker = step.checker;
    const i = step.index;
    const start_nodes = checker.nodes.items.len;
    const start_statements = checker.statements.items.len;
    const start_diagnostics = checker.sink.items.items.len;
    if (step.plan.*) |*plan| if (plan.bodyStandIn(i) != null) {
        const function = try checker.standInFunction(i);
        // Binding the parameters may repeat a diagnostic the stored body
        // notes already carry; the notes are the complete record.
        checker.sink.items.shrinkRetainingCapacity(start_diagnostics);
        try plan.replayBody(i, checker.sink);
        if (step.session.*) |*queries| queries.standIn(i);
        return function;
    };
    const reused = try reuseBody(checker, step.session, step.spec_session, step.cache, step.allocator, i);
    const timing = activeTiming(step.cache);
    const fresh = reused == null;
    const fresh_start = if (fresh) timingStart(timing) else null;
    defer if (fresh) timingAdd(timing, "fresh_body_check", fresh_start);
    const function = reused orelse checker.checkFunction(i) catch |err| switch (err) {
        error.SourceError => return null,
        else => return err,
    };
    try recordBodyRange(.{
        .checker = checker,
        .session = step.session,
        .allocator = step.allocator,
        .index = i,
        .start_nodes = start_nodes,
        .start_statements = start_statements,
        .reused = reused != null,
    });
    if (step.plan.*) |*plan| try plan.recordChecked(step.allocator, .{
        .instance = i,
        .nodes = .{ .start = start_nodes, .end = checker.nodes.items.len },
        .statements = .{ .start = start_statements, .end = checker.statements.items.len },
        .diagnostics = checker.sink.items.items[start_diagnostics..],
    });
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
    try checker.indexInvariants();
    // Checked trees run about one and a half times the syntax they come from.
    // Reserving that up front keeps the append path from regrowing (and, in the
    // project arena, recopying) a large program's checked tables; a small one
    // grows as it always did.
    if (program.nodes.items.len >= presize_threshold) {
        try checker.nodes.ensureTotalCapacity(allocator, program.nodes.items.len + program.nodes.items.len / 2);
        try checker.statements.ensureTotalCapacity(allocator, program.statements.items.len + program.statements.items.len / 2);
    }
    // C3 reuse: prepared declaration facts and fresh identity maps are
    // per-request; only populated when a semantic cache is attached.
    try initSpecializationReuse(&checker, allocator, catalog.records, &session, &spec_session);
    for (program.functions, 0..) |function, i| {
        const name = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try functionName(allocator, src, function.policy.owner, function.name);
        // The builtin `set` type is new beside programs that already declare a
        // function of that name, so such a function keeps its name and its
        // calls (SET-1); a declared type named `set` still conflicts.
        const template = checker.catalog.templates.names.get(name);
        const builtin_set = template != null and template.?.end == 0 and std.mem.eql(u8, name, "set");
        if (checker.catalog.names.contains(name) or (template != null and !builtin_set)) return sink.fail("E_DUPLICATE_NAME", function.name, "function name conflicts with a declared type");
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
    const entry_message = "main must return int, None, or Result[int or None, E] whose error E print can render";
    if (!entry_adapter.supported(try checker.ty(entry.signature.return_type), checker.catalog.records)) return sink.fail("E_TYPE", entry.signature.return_type, entry_message);
    var plan = try openPlan(cache, &session, allocator, @backingInt(main));
    var checked_functions: std.ArrayList(typed.Function) = .empty;
    var i: usize = 0;
    while (i < checker.instance_keys.items.len and (!contracts_failed or i < checker.ordinary_count)) : (i += 1) {
        const function = (try checkInstance(.{
            .checker = &checker,
            .session = &session,
            .spec_session = &spec_session,
            .cache = cache,
            .plan = &plan,
            .allocator = allocator,
            .index = i,
        })) orelse {
            failed = true;
            continue;
        };
        try checked_functions.append(allocator, function);
    }
    // Failed functions leave no executable placeholders. Cross-function passes
    // require a complete graph and must never see the partial function list.
    // A body that failed is checked in full whether or not others stood in:
    // a stood-in body had no errors and its inputs are unchanged.
    if (failed) return error.SourceError;
    const pass_start = sink.items.items.len;
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
    const stubs: []const ?origins.Fact = if (plan) |*active| try active.passStubs(allocator, checked.functions.len) else &.{};
    const facts: ?[]origins.Fact = if (plan != null) try allocator.alloc(origins.Fact, checked.functions.len) else null;
    @import("effects.zig").check(allocator, checked, .{ .exported = exported, .src = src, .syntax = program, .sink = sink, .stubs = stubs, .facts = facts }) catch |err| return retryOr(&plan, err);
    timingAdd(timing, "effect_origin_passes", effects_start);
    const codecs_start = timingStart(timing);
    @import("domain_codecs.zig").check(allocator, src, program.types.domains, checker.catalog, .{ .items = functions, .names = executable_names }, sink) catch |err| return retryOr(&plan, err);
    timingAdd(timing, "domain_codec_validation", codecs_start);
    const warnings_start = timingStart(timing);
    try warnBindings(allocator, functions, stubs, sink);
    try warnImports(module_names, sink);
    const pass_items: []const diagnostic.Diagnostic = if (plan != null) try allocator.dupe(diagnostic.Diagnostic, sink.items.items[pass_start..]) else &.{};
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    timingAdd(timing, "warning_derivation", warnings_start);
    // A rejected dead copy write is an implementation error, not advice: it must
    // stop checking before retention publishes an invalid program.
    for (sink.items.items) |item| if (item.severity == .err) return retryOr(&plan, error.SourceError);
    if (plan) |*active| {
        const summary_start = timingStart(timing);
        defer timingAdd(timing, "check_summaries", summary_start);
        if (!try active.consistent(allocator, checked, facts.?)) return retryOr(&plan, error.SourceError);
        if (active.publishes()) active.request.produced = try active.produce(allocator, checked, facts.?, .{ .pass = pass_items, .syntax = program });
        try active.replayPasses(sink);
    }
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

fn warnBindings(allocator: std.mem.Allocator, functions: []const typed.Function, stubs: []const ?origins.Fact, sink: *diagnostic.Sink) Error!void {
    for (functions, 0..) |function, index| {
        if (function.policy.host != null) continue;
        // A stood-in body has only its parameters here; its summary replays
        // the binding warnings its checked body reported.
        if (origins.standIn(stubs, index) != null) continue;
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
