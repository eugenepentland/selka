//! Scope and type checking use resolved binding identities, including advisory use counts.
const buffer_operations = @import("buffer_operations.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const needs_list = "operation requires a managed list";
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const external_resources = @import("external_resources.zig");
const io_builtins = @import("io_builtins.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const callback_type_code = "E_CALLBACK_TYPE";
const lambda_context_code = "E_LAMBDA_CONTEXT";
const call_argument_code = "E_CALL_ARGUMENT";
/// Stable code for a call-site `&` mutation marker that does not match the
/// callee's declared `mutates(...)` footprint.
const mutation_marker_code = "E_MUTATION_MARKER";
const eResultOperation = diagnostic.result_operation;
const eOwnedConsumed = diagnostic.owned_consumed;
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
const eIterationShadow = "iteration binding shadows an active declaration";
const eWildcardArm = "E_WILDCARD_ARM";
const eVariantPayload = "E_VARIANT_PAYLOAD";
const ePatternPayload = "E_PATTERN_PAYLOAD";
const eConversionBody = "E_CONVERSION_BODY";
const eByteConversion = "E_BYTES_CONVERSION";
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

/// String methods whose only operand is a scalar width rather than more text.
fn widthArgument(kind: BufferKind) bool {
    return kind == .zfill;
}
/// Whether one operand of an in-place byte-buffer method is a scalar count or
/// index rather than another managed value. `append_range` takes the source span
/// first and both endpoints after it, `append_utf8` takes text, and every other
/// method takes one count or byte value.
fn byteBufferInteger(kind: BufferKind, index: usize) bool {
    return switch (kind) {
        .buffer_append_range => index > 0,
        .buffer_append_utf8, .buffer_append_float => false,
        else => buffer_operations.byteBuffer(kind),
    };
}
/// The builtin mutable octet buffer's name, shared with the template index that
/// declares the type. It shares the byte collection kind with `bytes`, so the
/// name, not the representation, is what tells the checker which receiver accepts
/// an in-place append and which stays immutable.
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
/// The one diagnostic for an in-place buffer method on a receiver that is not
/// the mutable octet buffer.
const byte_buffer_receiver = "in-place buffer methods require a byte_buffer receiver";
/// Whether a managed byte-kind schema is the mutable octet buffer rather than an
/// immutable byte string.
fn isMutableBytes(schema: typed.Record) bool {
    return schema.collection.kind == .bytes and std.mem.eql(u8, schema.name, byte_buffer_name);
}
/// Whether a managed byte-kind schema is an immutable byte string: a `bytes`
/// literal, conversion result, slice or view, but never the octet buffer.
fn isImmutableBytes(schema: typed.Record) bool {
    return schema.collection.kind == .bytes and !isMutableBytes(schema);
}
/// Whether a type is either managed byte kind — the immutable byte string or the
/// mutable octet buffer. The two hold the same one-octet elements and compare
/// content the same way, so one comparison may name both.
fn isByteKind(schemas: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and schemas[ty.recordIndex()].collection.kind == .bytes;
}
const eResourceResult = diagnostic.resource_result;
const eResourceIoResult = "E_RESOURCE_IO_RESULT";
const eResultLoop = diagnostic.result_loop;
const bindingDeclaredHere = "binding declared here";
const eImmutable = diagnostic.immutable;
const eResultDiscard = diagnostic.result_discard;
const eCellEquality = "E_CELL_EQUALITY";
const eEnvironmentName = "E_ENVIRONMENT_NAME";
const variantDeclaredHere = "variant declared here";
const std = @import("std");
const dictionary_views = @import("dictionary_views.zig");
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
/// Temporary rejection for the syntax the foundation parser accepts before its
/// lane implements the check: tuple values and destructuring, the conditional
/// expression, and the `mut` argument marker. Every use carries a `// lane:`
/// comment and is deleted by that lane.
const eNotImplemented = "E_NOT_IMPLEMENTED";
const eTupleArity = "E_TUPLE_ARITY";
/// The accepted spelling beside a rejected tuple arity.
const tuple_arity_alternative = "a tuple has between 2 and 8 elements; declare a record for a larger group";
/// The accepted spelling beside a rejected tuple index, which is the only way
/// to reach a tuple's values.
const tuple_index_alternative = "a tuple has no elements to index; bind its values with `head, rest = ...`";
const unsupported_collection = "operation is not supported by this collection";
const unsupported_list = "operation is not supported by lists";
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
/// The accepted callee of the `sorted` prelude builtin; Python's `reverse=` is
/// rejected with `reversed(sorted(...))` instead.
const sorted_signature = buffer_operations.sorted_signature;
/// The accepted spelling for Python's `sorted(..., reverse=True)`.
const sorted_reverse_alternative = "sorted orders ascending only; write `reversed(sorted(values))` for a descending order";
/// The accepted spelling of a Python method form this language rejects, or null
/// when it has none. Only deliberate, known gaps appear here; a rejected call
/// with no entry prints its signature or its accepted methods and stops.
fn methodAlternative(name: []const u8) ?[]const u8 {
    if (std.mem.eql(u8, name, "format")) return "use an f-string: f\"{value}\" interpolates where str.format does";
    return null;
}
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
const eArenaBinding = "E_ARENA_BINDING";
const eWithResource = "E_WITH_RESOURCE";
const eFileArgument = "E_FILE_ARGUMENT";
const eFilesystemDir = "E_FILESYSTEM_DIR";
const eNetworkHost = "E_NETWORK_HOST";
/// Reject a literal `dir()` path that could leave a scoped root, mirroring the
/// `scopedPath` rule. An empty path names the root itself.
fn scopedDirectoryPath(bytes: []const u8) bool {
    if (bytes.len == 0) return true;
    if (std.mem.indexOfAny(u8, bytes, "\\\x00") != null) return false;
    var parts = std.mem.splitScalar(u8, bytes, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return false;
    }
    return true;
}
const Pending = struct { available: bool, transfer_span: ?source.Span };
const Work = struct { default_value: bool = false, id: ast.NodeId, emit: bool = false, checkpoint: ?option_flow.Guard = null, sorted_key: bool = false, verify: ?struct { pending: []const Pending, facts: []const usize } = null };
const FieldDestination = struct { owner: typed.LocalId, index: ?typed.NodeId, value: typed.NodeId, refresh: ?typed.StatementId };
/// An already-evaluated managed receiver and the source arguments of its method.
const ManagedAccess = struct { base: typed.NodeId, kind: BufferKind, inputs: []const ast.NodeId, receiver: ?typed.LocalId = null };
/// One list method call whose receiver and arguments are already evaluated.
const ListMethodCall = struct { base: typed.NodeId, receiver: ?typed.LocalId, kind: BufferKind, inputs: []const ast.NodeId, temporaries: []const typed.Type, signed_length: bool = false };
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
    /// Opt-in D3 experiment: enforce call-site `&` markers against `mutates(...)`.
    mutation_markers: bool = false,

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
        const declaration = @backingInt(self.instance_keys.items[i].declaration);
        const constant = if (function.policy.constant and try constant_context.literalType(declaration) == null) try constant_context.evaluate(declaration) else null;
        for (self.resolved_nodes.items) |node| self.resolved[node] = null;
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.option_facts.clear();
        self.locals = .empty;
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
                .mutates = function.signature.mutates,
                .return_origin = .unknown,
                .declared_mutates = function.signature.mutates,
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
        self.option_facts.clear();
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
        const contract = semantic_key.declaredContractDigest(function.policy.effect_bound, function.signature.mutates);
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
    fn callDeclaration(self: *Checker, raw: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!ResolvedCall {
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
            try work.append(self.allocator, .{ .id = initializers[i].value, .default_value = initializers[i].default });
        }
    }
    fn require(self: *Checker, actual: typed.Type, expected: typed.Type, span: source.Span) Error!void {
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
    fn resolve(self: *Checker, name: source.Span) Error!typed.LocalId {
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
    fn unknownMethodMessage(self: *Checker, family: ?ManagedKind, receiver: ?typed.Type) Error![]const u8 {
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
    fn signatureNames(self: *Checker, owner_type: typed.Type) Error!buffer_operations.SignatureNames {
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
    fn methodArityFailure(self: *Checker, rejection: MethodRejection) Error {
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
    fn requireArgument(self: *Checker, rejection: ArgumentRejection) Error!void {
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
    fn fileAccessArityFailure(self: *Checker, node: ast.Node, kind: file_operations.Access, actual: usize, method: bool) Error {
        const expected = if (method) kind.methodArity() else kind.arity();
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` takes {d} argument{s}, but this call passes {d}", .{
            fileAccessSignature(kind), expected, if (expected == 1) "" else "s", actual,
        });
        if (method) return self.sink.fail("E_ARITY", node.span, message);
        return self.sink.failRelated("E_ARITY", node.span, message, .{ .span = node.span, .message = capability_first, .role = .alternative });
    }
    /// Reject an open-handle method whose argument count differs from its checked
    /// signature.
    fn fileMethodArityFailure(self: *Checker, name: source.Span, kind: file_operations.Method, actual: usize) Error {
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` does not take {d} argument{s}", .{
            fileMethodSignature(kind), actual, if (actual == 1) "" else "s",
        });
        return self.sink.fail("E_ARITY", name, message);
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
        if (call.arguments.len == 0 or call.arguments.len > 2) return self.sink.failCallSite("E_ARITY", call.name, "sorted requires a list and optional key callback", null, sorted_signature);
        if (call.argument_names.len == 0) {
            if (call.arguments.len == 2) return self.sink.failCallSite(call_argument_code, self.syntax.nodes.items[@backingInt(call.arguments[1])].span, "sorted key must be written as key=callback", null, sorted_signature);
            return;
        }
        if (call.argument_names[0] != null) return self.sink.failCallSite(call_argument_code, call.argument_names[0].?, "the sorted list is positional", null, sorted_signature);
        if (call.arguments.len != 2 or call.argument_names[1] == null or !std.mem.eql(u8, self.src.text(call.argument_names[1].?), "key")) {
            // `reverse=` is a Python keyword this surface does not accept, and the
            // repair is mechanical: `reversed` is already a prelude builtin.
            if (call.argument_names.len > 1) if (call.argument_names[1]) |keyword| if (std.mem.eql(u8, self.src.text(keyword), "reverse"))
                return self.sink.failCallSite(call_argument_code, call.name, "sorted accepts only the named argument key=callback", .{ .span = keyword, .message = sorted_reverse_alternative, .role = .alternative }, sorted_signature);
            return self.sink.failCallSite(call_argument_code, call.name, "sorted accepts only the named argument key=callback", null, sorted_signature);
        }
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
        if (!input_schema.isCollection() or input_schema.collection.kind != .list)
            return self.sink.fail("E_PRELUDE_TYPE", input.span, "sorted key requires a list input");
        const element = input_schema.shape.buffer.?;
        const parameters = try self.allocator.dupe(typed.Type, &.{element});
        const callback = try callables.intern(self.allocator, &self.catalog, .{ .parameters = parameters, .return_type = .i64, .effects = 0, .mutates = &.{}, .return_origin = .fresh }, call.argument_names[1].?, self.sink);
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
    /// The whole-path helper a qualified call names on a local `Filesystem`, or
    /// null for an ordinary receiver. The method form is never shadowed by a
    /// same-named function or local: it belongs to the receiver alone.
    fn fileAccessMethodKind(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?file_operations.Access {
        const owner = call.owner orelse return null;
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        if (self.locals.items[@backingInt(slot)].ty != .filesystem_cap) return null;
        return file_operations.access(self.src.text(call.name));
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
    /// Check one whole-path helper after its receiver, shared by the free
    /// `read_text(fs, path)` and qualified `fs.read_text(path)` spellings.
    /// `value_arguments` excludes the capability, so `arguments[0]` is the
    /// receiver and the typed operand order matches the free form exactly.
    fn checkFileAccess(self: *Checker, node: ast.Node, kind: file_operations.Access, receiver: typed.NodeId, value_arguments: []const ast.NodeId, out: *typed.Node) Error!void {
        const shapes = try self.fileShapes(node.span);
        const arguments = try self.allocator.alloc(typed.NodeId, value_arguments.len + 1);
        arguments[0] = receiver;
        for (value_arguments, arguments[1..]) |id, *slot| slot.* = self.resolved[@backingInt(id)].?;
        try self.require(self.nodes.items[@backingInt(receiver)].ty, .filesystem_cap, node.span);
        try self.require(self.nodes.items[@backingInt(arguments[1])].ty, shapes.text, self.nodes.items[@backingInt(arguments[1])].span);
        const mode = try self.openMode(kind, value_arguments);
        if (kind == .write_file) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.bytes, node.span);
        if (kind == .write_text) try self.require(self.nodes.items[@backingInt(arguments[2])].ty, shapes.text, node.span);
        const direct = kind == .open and self.trapping_open != null and std.meta.eql(self.trapping_open.?, node.span);
        out.ty = if (direct) (if (mode.text) .text_file else .file) else try self.fileAccessType(kind, mode, node.span);
        out.data = .{ .file_access = .{ .kind = kind, .mode = mode.letter, .text = mode.text, .arguments = arguments, .shapes = shapes } };
    }
    /// Check the free `read_text(fs, path)` spelling, whose leading argument is
    /// the capability the method form carries as its receiver.
    fn checkFileAccessCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0 or call.arguments.len != kind.arity()) return self.fileAccessArityFailure(node, kind, call.arguments.len, false);
        return self.checkFileAccess(node, kind, self.resolved[@backingInt(call.arguments[0])].?, call.arguments[1..], out);
    }
    /// Check the qualified `fs.read_text(path)` spelling on a local `Filesystem`.
    fn checkFileAccessMethod(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: file_operations.Access, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0 or call.arguments.len != kind.methodArity()) return self.fileAccessArityFailure(node, kind, call.arguments.len, true);
        const owner = call.owner.?;
        const slot = self.active.get(self.src.text(owner)).?;
        try self.requireReadable(slot, owner);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const receiver: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = owner, .ty = .filesystem_cap, .data = .{ .local = slot } });
        return self.checkFileAccess(node, kind, receiver, call.arguments, out);
    }
    /// `open` needs a literal mode so the checker knows whether reads yield text.
    fn openMode(self: *Checker, kind: file_operations.Access, value_arguments: []const ast.NodeId) Error!file_operations.Mode {
        if (kind != .open) return .{ .letter = 'r', .text = kind == .read_text or kind == .write_text };
        const spelling = self.syntax.nodes.items[@backingInt(value_arguments[1])];
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
    /// `debug(...)` writes to standard error with no capability and no effect.
    fn debugBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
        if (call.owner != null or call.type_arguments.len != 0) return false;
        if (!std.mem.eql(u8, self.src.text(call.name), "debug")) return false;
        if (self.active.contains("debug") or self.functions.contains("debug")) return false;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
        return true;
    }
    /// Resolve the receiver of `stream.print`/`stream.write` to its local slot, or null.
    fn streamLocal(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
        const owner = call.owner orelse return null;
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        if (self.locals.items[@backingInt(slot)].ty != .stream_cap) return null;
        const name = self.src.text(call.name);
        if (!std.mem.eql(u8, name, "write") and !std.mem.eql(u8, name, "print")) return null;
        return slot;
    }
    /// Recognize `stream.print(...)`/`stream.write(...)` on a `Stream` local.
    fn streamMethod(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?struct { stream: typed.NodeId, write: bool } {
        const slot = self.streamLocal(call) orelse return null;
        const write = std.mem.eql(u8, self.src.text(call.name), "write");
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const stream: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = call.owner.?, .ty = .stream_cap, .data = .{ .local = slot } });
        return .{ .stream = stream, .write = write };
    }
    /// The destination of one `print`-shaped call: an ambient sink, a runtime
    /// `Stream` receiver, or the `debug` stderr spelling.
    const PrintTarget = struct { sink: typed.Sink = .stdout, stream: ?typed.NodeId = null, debug: bool = false };
    /// `print`/`eprint` without a receiver are gone: once no local binding,
    /// declared function or imported name shadows the spelling, they name
    /// `E_OUTPUT_CAPABILITY` rather than an ambient sink. The same sentence the
    /// message carries is attached as an `alternative` note, so a tool reads the
    /// accepted spelling as data instead of parsing prose, and the primary
    /// message is unchanged.
    fn outputBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Sink {
        if (call.owner != null or call.type_arguments.len != 0) return null;
        const name = self.src.text(call.name);
        if (!std.mem.eql(u8, name, "print") and !std.mem.eql(u8, name, "eprint")) return null;
        if (self.active.contains(name) or self.functions.contains(name)) return null;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
        return self.sink.failCallSite(io_builtins.output_capability_code, call.name, io_builtins.output_capability_message, .{
            .span = call.name,
            .message = io_builtins.output_capability_message,
            .role = .alternative,
        }, print_signature);
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
    fn checkPrint(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), target: PrintTarget, out: *typed.Node) Error!void {
        const split = try io_builtins.printArguments(self.src, call, self.sink);
        const arguments = try self.allocator.alloc(typed.NodeId, split.values.len);
        for (split.values, arguments) |id, *slot| slot.* = try self.checkPrintOperand(id, false);
        out.ty = .unit;
        out.data = .{ .print = .{
            .sink = target.sink,
            .arguments = arguments,
            .separator = if (split.separator) |id| try self.checkPrintOperand(id, true) else null,
            .terminator = if (split.terminator) |id| try self.checkPrintOperand(id, true) else null,
            .stream = target.stream,
            .debug = target.debug,
        } };
        _ = node;
    }
    fn checkStreamWrite(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), stream: typed.NodeId, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "stream.write takes one str or bytes argument");
        const text = self.resolved[@backingInt(call.arguments[0])].?;
        const value = self.nodes.items[@backingInt(text)];
        const kind = if (value.ty.isAggregate()) self.catalog.records[value.ty.recordIndex()].collection.kind else null;
        if (kind != .string and kind != .bytes) return self.sink.fail("E_TYPE", value.span, "stream.write requires str or bytes");
        out.ty = .i64;
        out.data = .{ .stream_write = .{ .stream = stream, .text = text } };
    }
    fn optionConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
        if (call.owner != null or call.type_arguments.len != 0 or !std.mem.eql(u8, self.src.text(call.name), "Some")) return false;
        if (self.active.contains("Some") or self.functions.contains("Some")) return false;
        if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return false;
        return true;
    }
    fn cellConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?usize {
        if (self.active.contains("Cell") or self.functions.contains("Cell")) return null;
        return @import("cell_types.zig").constructor(self.src, self.catalog, call, self.sink);
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
                    if (call.type_arguments.len != 0 or call.arguments.len > most or call.arguments.len < least)
                        return self.fileMethodArityFailure(call.name, kind, call.arguments.len);
                    node.data = .{ .file_operation = .{ .kind = kind, .owner = owner, .argument = if (call.arguments.len == 0) null else call.arguments[0] } };
                    return node;
                }
                if (value_type.isAggregate() and self.catalog.records[value_type.recordIndex()].isCollection()) {
                    try call_arguments.positional(call, self.sink);
                    const name = self.src.text(call.name);
                    const family = self.catalog.records[value_type.recordIndex()].collection.kind;
                    const kind = buffer_operations.methodFor(name, call.arguments.len) orelse {
                        _ = try @import("removed_names.zig").reject(self.sink, call.name, name);
                        return self.sink.fail("E_LIST_METHOD", call.name, try self.unknownMethodMessage(family, value_type));
                    };
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
                } else if (record_layouts.tupleRecord(self.catalog.records, value_type) != null)
                    return self.sink.fail("E_TYPE", call.name, "a tuple has no methods; take it apart with `head, rest = value`");
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
        if (!ty_value.isAggregate() or !self.catalog.records[ty_value.recordIndex()].isCollection()) return self.sink.fail(eListType, span, needs_list);
        if (self.catalog.records[ty_value.recordIndex()].collection.kind != .list) return self.sink.fail(eListType, span, needs_list);
        return self.catalog.records[ty_value.recordIndex()].shape.buffer orelse return self.sink.fail(eListType, span, needs_list);
    }
    /// Whether equality-based collection operations would compare a Cell-bearing type.
    fn requiresCellEquality(self: *Checker, ty_value: typed.Type) bool {
        return ty_value.isAggregate() and self.catalog.records[ty_value.recordIndex()].collection.contains_cell;
    }
    /// Check one `(a, b)` tuple value. The expected-type rule reaches literals:
    /// a destination that already demands a tuple type checks each element
    /// against its positional type, and any other context infers the element
    /// types and interns their tuple.
    fn checkTuple(self: *Checker, node: ast.Node, inputs: []const ast.NodeId, temporaries: []const typed.Type, out: *typed.Node) Error!void {
        if (inputs.len < 2 or inputs.len > 8) return self.sink.fail(eTupleArity, node.span, tuple_arity_alternative);
        const expected = if (self.expected_types.get(node.span)) |demanded| record_layouts.tupleRecord(self.catalog.records, demanded) else null;
        if (expected) |schema| if (schema.fields.len != inputs.len) return self.sink.fail(
            eTupleArity,
            node.span,
            try std.fmt.allocPrint(self.allocator, "this tuple has {d} elements but {s} has {d}; write {d} elements", .{
                inputs.len,
                try typed.surfaceTypeName(self.allocator, schema.id, self.catalog.records),
                schema.fields.len,
                schema.fields.len,
            }),
        );
        const values = try self.allocator.alloc(typed.NodeId, inputs.len);
        const types = try self.allocator.alloc(typed.Type, inputs.len);
        for (inputs, 0..) |input, index| {
            if (expected) |schema| try self.hint(input, schema.fields[index].ty);
            const value = try self.expressionWithTemporaries(input, temporaries);
            const actual = self.nodes.items[@backingInt(value)].ty;
            if (expected) |schema| try self.require(actual, schema.fields[index].ty, self.syntax.nodes.items[@backingInt(input)].span);
            values[index] = value;
            types[index] = if (expected) |schema| schema.fields[index].ty else actual;
        }
        out.ty = if (expected) |schema| schema.id else try self.catalog.tupleType(types);
        const initializers = try self.allocator.alloc(typed.FieldInit, values.len);
        for (initializers, values, 0..) |*initializer, value, index| initializer.* = .{ .index = index, .value = value };
        out.data = .{ .record = initializers };
    }
    /// Bind the names of a `x, y = value` target list to the positional fields of
    /// one tuple value. The value is evaluated once into its own slot before any
    /// name is written, which is what makes `a, b = b, a` swap.
    fn checkTupleAssignment(self: *Checker, assignment: @FieldType(@FieldType(ast.Node, "data"), "field_assignment"), temporaries: []const typed.Type) Error!typed.Node {
        const target = self.syntax.nodes.items[@backingInt(assignment.target)];
        const names = target.data.tuple;
        const checked = try self.expressionWithTemporaries(assignment.value, temporaries);
        const value_type = self.nodes.items[@backingInt(checked)].ty;
        const schema = record_layouts.tupleRecord(self.catalog.records, value_type) orelse {
            const found = try typed.surfaceTypeName(self.allocator, value_type, self.catalog.records);
            const message = try std.fmt.allocPrint(self.allocator, "a destructuring assignment binds the values of a tuple; `{s}` is not one — bind it with one name instead", .{found});
            return self.sink.fail("E_TYPE", self.nodes.items[@backingInt(checked)].span, message);
        };
        if (schema.fields.len != names.len) return self.sink.fail(eTupleArity, target.span, try self.destructuringMessage(assignment.value, schema.fields.len));
        const b: collections.Builder(Checker) = .{ .checker = self, .span = target.span };
        var statements: std.ArrayList(typed.StatementId) = .empty;
        const value_slot = try b.local(value_type);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = value_slot, .value = checked } }));
        for (names, 0..) |name_id, index| {
            const name = self.syntax.nodes.items[@backingInt(name_id)].data.name;
            const element = try b.node(schema.fields[index].ty, .{ .field = .{ .base = try b.read(value_slot), .index = index } });
            try self.bindDestructured(name, element, &statements);
        }
        return b.block(statements.items, try b.node(.unit, .unit));
    }
    /// The accepted arity a destructuring names, naming the value's source when
    /// it is a call so the message tells the reader what returned that many.
    fn destructuringMessage(self: *Checker, value: ast.NodeId, elements: usize) Error![]const u8 {
        const node = self.syntax.nodes.items[@backingInt(value)];
        const origin = if (node.data == .call and node.data.call.owner == null)
            try std.fmt.allocPrint(self.allocator, "`{s}` returns {d} values", .{ self.src.text(node.data.call.name), elements })
        else
            try std.fmt.allocPrint(self.allocator, "the value has {d} values", .{elements});
        return std.fmt.allocPrint(self.allocator, "{s}; bind {d} names, or `_` for one you do not need", .{ origin, elements });
    }
    /// The accepted arity a two-name `for` needs, naming the one-name loop.
    fn twoNameLoopMessage(self: *Checker, elements: usize) Error![]const u8 {
        return std.fmt.allocPrint(
            self.allocator,
            "a two-name `for` destructures a two-value tuple; this one has {d} values — bind it with one name and destructure it in the body",
            .{elements},
        );
    }
    /// Bind one destructuring target: a fresh function-scoped local for a name
    /// that is not bound yet, an assignment into the existing binding otherwise,
    /// and nothing at all for `_`, which needs no slot and reads no element.
    fn bindDestructured(self: *Checker, name: source.Span, value: typed.NodeId, statements: *std.ArrayList(typed.StatementId)) Error!void {
        const text = self.src.text(name);
        if (std.mem.eql(u8, text, "_")) return;
        const b: collections.Builder(Checker) = .{ .checker = self, .span = name };
        const value_type = self.nodes.items[@backingInt(value)].ty;
        if (self.active.get(text)) |slot| {
            if (!self.locals.items[@backingInt(slot)].mutable) return self.sink.fail(eImmutable, name, "this binding cannot be assigned");
            try self.requireArenaAssignment(slot, value);
            if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
                if (self.pendingObligation(self.locals.items[@backingInt(slot)])) return self.sink.fail("E_RESULT_OVERWRITE", name, "assignment would overwrite an unhandled result-bearing value");
                self.locals.items[@backingInt(slot)].ownership.transfer_available = true;
                self.locals.items[@backingInt(slot)].ownership.transfer_span = null;
            }
            self.locals.items[@backingInt(slot)].usage.writes += 1;
            self.locals.items[@backingInt(slot)].ownership.initialized = true;
            self.locals.items[@backingInt(slot)].ownership.arena_confined = false;
            self.option_facts.forget(@backingInt(slot));
            try statements.append(self.allocator, try b.stmt(.{ .assign = .{ .slot = slot, .value = value } }));
            return;
        }
        if (try self.topLevel(name)) return self.sink.fail(eShadowing, name, "binding shadows an active local or top-level function");
        for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, text)) return self.sink.fail(eShadowing, name, "binding shadows an active arena name");
        const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
        try self.locals.append(self.allocator, .{
            .ownership = .{ .initialized = true, .transfer_available = self.transfers(value_type) },
            .name = text,
            .declaration = name,
            .ty = value_type,
            .mutable = true,
        });
        try self.active.put(self.allocator, text, slot);
        try self.requireArenaStore(slot, value);
        try statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = slot, .value = value } }));
    }
    fn checkFieldAssignment(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const assignment = node.data.field_assignment;
        if (self.syntax.nodes.items[@backingInt(assignment.target)].data == .tuple)
            return self.checkTupleAssignment(assignment, temporaries);
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
        // A field write through a by-name copy is only dead when the binding's
        // value came from a copy and nothing reads the binding afterwards. The
        // right-hand side is checked first: a read of the same binding there is
        // part of the write and does not observe the value just stored.
        const dead_owner: ?typed.LocalId = if (destination.index == null) destination.owner else null;
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
        if (dead_owner) |owner| {
            const payload = self.narrowedOption(owner);
            const shared = if (payload) |shape| shape.element.isAggregate() and self.catalog.records[shape.element.recordIndex()].isManagedRecord() else false;
            if (!shared) self.noteDeadRecordWrite(owner, node.span);
        }
        try self.require(self.nodes.items[@backingInt(value)].ty, expected, node.span);
        if (destination.index == null) try self.requireArenaStore(destination.owner, value);
        // The value needs its own slot only to survive the destination refresh: it
        // must be computed before the refresh, which re-reads the binding. A managed
        // record needs no refresh, and its update reads the binding where it stands,
        // so the value can go straight into the update's operand.
        if (destination.refresh) |refresh| {
            const assigned = try b.local(expected);
            const evaluate_value = try b.stmt(.{ .initialize = .{ .slot = assigned, .value = value } });
            try statements.insert(self.allocator, 0, evaluate_value);
            // Preserve unrelated fields changed through aliases while computing the RHS.
            try statements.append(self.allocator, refresh);
            value = try b.read(assigned);
        }
        var i = bases.len;
        while (i > 0) {
            i -= 1;
            value = try b.node(self.nodes.items[@backingInt(bases[i])].ty, .{ .update = .{
                .base = bases[i],
                .fields = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = indices[i], .value = value }}),
            } });
        }
        if (destination.index == null) if (self.narrowedOption(destination.owner)) |shape| {
            value = try b.node(self.locals.items[@backingInt(destination.owner)].ty, .{ .variant = .{ .tag = shape.some, .value = value } });
        };
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
        if (left_type.isAggregate() and self.catalog.records[left_type.recordIndex()].isCollection()) {
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
    /// Record a candidate dead field write on a named binding whose value came
    /// from a copy (a parameter, iteration variable, or indexed element). The
    /// warning is emitted later when no read follows the most recent write.
    fn noteDeadRecordWrite(self: *Checker, slot: typed.LocalId, span: source.Span) void {
        const local = &self.locals.items[@backingInt(slot)];
        if (local.origin == .local) return;
        if (!local.ty.isAggregate()) return;
        // A managed record (`class` or Cell) is shared, so a field write reaches
        // the original; only copied value `record`s can have dead writes.
        if (self.catalog.records[local.ty.recordIndex()].managed) return;
        if (self.catalog.records[local.ty.recordIndex()].isCollection()) return;
        local.usage.dead_write_reads = local.usage.reads;
        local.usage.dead_write_span = span;
    }
    fn fieldDestination(self: *Checker, root: ast.Node, statements: *std.ArrayList(typed.StatementId), temporaries: []const typed.Type) Error!FieldDestination {
        const b: collections.Builder(Checker) = .{ .checker = self, .span = root.span };
        if (root.data == .name) {
            const owner = try self.resolve(root.data.name);
            try self.requireReadable(owner, root.data.name);
            if (!self.locals.items[@backingInt(owner)].mutable) return self.sink.fail(eImmutable, root.span, "record field assignment requires a mutable binding");
            self.locals.items[@backingInt(owner)].usage.writes += 1;
            self.locals.items[@backingInt(owner)].usage.reads += 1;
            const owner_type = self.locals.items[@backingInt(owner)].ty;
            if (self.narrowedOption(owner)) |shape| {
                const projected = try option_flow.payloadValue(self, try b.read(owner), shape, root.span);
                const projected_id = try b.node(projected.ty, projected.data);
                const saved = try b.local(shape.element);
                const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = projected_id } });
                try statements.append(self.allocator, refresh);
                return .{ .owner = owner, .index = null, .value = try b.read(saved), .refresh = refresh };
            }
            // A managed record is a reference-identity cell, and `update_record`
            // lowers to an in-place mutation that stores the same pointer back, so
            // the binding never needs copying: the update reads the binding where it
            // stands, after the right-hand side, which is exactly the value the
            // refreshed copy would have held.
            if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isManagedRecord())
                return .{ .owner = owner, .index = null, .value = try b.read(owner), .refresh = null };
            const saved = try b.local(owner_type);
            const refresh = try b.stmt(.{ .initialize = .{ .slot = saved, .value = try b.read(owner) } });
            try statements.append(self.allocator, refresh);
            return .{ .owner = owner, .index = null, .value = try b.read(saved), .refresh = refresh };
        }
        if (root.data != .index) return self.sink.fail("E_ASSIGNMENT_TARGET", root.span, "field assignment requires a mutable local record or list slot");
        const access = root.data.index;
        const base = try self.expressionWithTemporaries(access.base, temporaries);
        const ty_value = self.nodes.items[@backingInt(base)].ty;
        if (!ty_value.isAggregate() or !self.catalog.records[ty_value.recordIndex()].isCollection()) return self.sink.fail(eCollectionMethod, root.span, "indexed field assignment requires a list or dictionary");
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
        const source_value = try self.expressionWithTemporaries(iterable_node, temporaries);
        const view = dictionary_views.identify(self.catalog, self.nodes.items[@backingInt(source_value)].ty);
        const projected = view != null and view.? != .item;
        const iterable = if (projected) try dictionary_views.owner(Checker, self, node.span, source_value) else source_value;
        const iterable_type = self.nodes.items[@backingInt(iterable)].ty;
        if (!iterable_type.isAggregate() or !self.catalog.records[iterable_type.recordIndex()].isCollection()) return self.sink.fail(eCollectionMethod, node.span, "iteration requires a list, str, or dictionary");
        const schema = self.catalog.records[iterable_type.recordIndex()];
        const element = if (projected) try dictionary_views.element(&self.catalog, iterable_type, view.?, node.span) else switch (schema.collection.kind) {
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
        const slots: ComprehensionSlots = .{ .owner = owner, .index = index, .limit = limit, .slot = value_slot };
        const source_values: ComprehensionSource = .{
            .iterable = iterable,
            .output = parts.output,
            .kind = schema.collection.kind,
            .reserve = each.filter == null,
            .projection = if (projected) view else null,
        };
        return self.comprehensionLoop(b, slots, parts.body, source_values);
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
        const capacity = if (each.filter == null) try b.rangeCapacity(try b.read(index), try b.read(limit), element) else try b.integer(0);
        return b.block(&.{
            try b.stmt(.{ .initialize = .{ .slot = index, .value = start } }),
            try b.stmt(.{ .initialize = .{ .slot = limit, .value = end } }),
            try b.stmt(.{ .initialize = .{ .slot = parts.output, .value = try b.node(self.locals.items[@backingInt(parts.output)].ty, .{ .acquire_buffer = .{ .capacity = capacity } }) } }),
            try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, i, try b.read(limit), .bool), .body = parts.body, .step = step } }),
        }, try b.read(parts.output));
    }

    /// Assemble the fixed-bound iteration, its mutation check, and the produced list.
    const ComprehensionSlots = struct { owner: typed.LocalId, index: typed.LocalId, limit: typed.LocalId, slot: typed.LocalId };
    const ComprehensionSource = struct {
        iterable: typed.NodeId,
        output: typed.LocalId,
        kind: ManagedKind,
        reserve: bool,
        projection: ?dictionary_views.Kind = null,
    };
    fn comprehensionLoop(
        self: *Checker,
        b: collections.Builder(Checker),
        slots: ComprehensionSlots,
        body: typed.StatementId,
        source_values: ComprehensionSource,
    ) Error!typed.Node {
        const i = try b.read(slots.index);
        const guard = try b.stmt(.{ .discard = try b.operation(slots.owner, .iteration_check, &.{try b.read(slots.limit)}) });
        const value = try self.projectedIterationValue(b, slots.owner, i, source_values.kind, source_values.projection);
        const iteration = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            guard,
            try b.stmt(.{ .initialize = .{ .slot = slots.slot, .value = value } }),
            body,
        }) });
        const step = try b.stmt(.{ .block = try self.allocator.dupe(typed.StatementId, &.{
            guard,
            try b.stmt(.{ .assign = .{ .slot = slots.index, .value = try b.binary(.add, i, try b.integer(1), .i64) } }),
        }) });
        const loop_id = self.loops.next;
        self.loops.next += 1;
        const output_capacity = if (source_values.reserve) try b.read(slots.limit) else try b.integer(0);
        const output_type = self.locals.items[@backingInt(source_values.output)].ty;
        const acquire_output = try b.node(output_type, .{ .acquire_buffer = .{ .capacity = output_capacity } });
        return b.block(&.{
            try b.stmt(.{ .initialize = .{ .slot = slots.owner, .value = source_values.iterable } }),
            try b.stmt(.{ .initialize = .{ .slot = slots.index, .value = try b.integer(0) } }),
            try b.stmt(.{ .initialize = .{ .slot = slots.limit, .value = try b.length(slots.owner) } }),
            try b.stmt(.{ .initialize = .{ .slot = source_values.output, .value = acquire_output } }),
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

    /// Render an f-string's pieces once in source order, then join them into one
    /// exactly-sized text allocation instead of repeatedly copying prefixes.
    fn checkFormat(self: *Checker, node: ast.Node, parts: []const ast.NodeId, temporaries: []const typed.Type) Error!typed.Node {
        const str_type = self.catalog.names.get("str") orelse return error.InternalError;
        const builder: collections.Builder(Checker) = .{ .checker = self, .span = node.span };
        const values = try self.allocator.alloc(typed.NodeId, parts.len);
        for (parts, values) |part, *value| {
            const span = self.syntax.nodes.items[@backingInt(part)].span;
            value.* = try self.formatPart(try self.expressionWithTemporaries(part, temporaries), str_type, span);
        }
        if (values.len == 1) return builder.block(&.{}, values[0]);
        const empty = try builder.node(str_type, .{ .array = &.{} });
        if (values.len == 0) return builder.block(&.{}, empty);
        const list_type = try collections.listType(&self.catalog, str_type, node.span);
        const list = try builder.literal(list_type, values);
        const list_id = try builder.node(list.ty, list.data);
        return builder.access(empty, .join, &.{list_id}, false);
    }

    fn narrowedCollection(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?typed.LocalId {
        const owner = call.owner orelse return null;
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        const shape = self.narrowedOption(slot) orelse return null;
        if (!shape.element.isAggregate() or !self.catalog.records[shape.element.recordIndex()].isCollection()) return null;
        return slot;
    }
    fn checkNarrowedMethod(self: *Checker, node: ast.Node, slot: typed.LocalId, temporaries: []const typed.Type) Error!typed.Node {
        const call = node.data.call;
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "collection methods do not take explicit type arguments");
        const shape = self.narrowedOption(slot).?;
        const kind = buffer_operations.methodFor(self.src.text(call.name), call.arguments.len) orelse
            return self.sink.fail(eCollectionMethod, call.name, try self.unknownMethodMessage(self.catalog.records[shape.element.recordIndex()].collection.kind, shape.element));
        var value: typed.Node = .{ .span = call.owner.?, .ty = .unit, .data = .unit };
        try self.checkName(.{ .span = call.owner.?, .data = .{ .name = call.owner.? } }, call.owner.?, &value);
        const base: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, value);
        return self.checkCollectionAccess(node, .{ .base = base, .receiver = slot, .kind = kind, .inputs = call.arguments, .temporaries = temporaries });
    }
    fn checkCollectionMethod(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const call = node.data.method_call;
        const name = self.src.text(call.name);
        _ = try @import("removed_names.zig").reject(self.sink, call.name, name);
        // The receiver is checked first so an unknown method can name its type;
        // `checkListAccess` reads the same cached checked node.
        const base = try self.expressionWithTemporaries(call.base, temporaries);
        const owner_type = self.nodes.items[@backingInt(base)].ty;
        const kind = buffer_operations.methodFor(name, call.arguments.len) orelse {
            const managed = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
            const family: ?ManagedKind = if (managed) self.catalog.records[owner_type.recordIndex()].collection.kind else null;
            const message = try self.unknownMethodMessage(family, if (managed) owner_type else null);
            if (methodAlternative(name)) |alternative|
                return self.sink.failRelated(eCollectionMethod, call.name, message, .{ .span = call.name, .message = alternative, .role = .alternative });
            return self.sink.fail(eCollectionMethod, call.name, message);
        };
        if (call.arguments.len == 0 and owner_type.isAggregate() and isImmutableBytes(self.catalog.records[owner_type.recordIndex()])) {
            const range_kind: ?BufferKind = switch (kind) {
                .parse_int => .parse_int_range,
                .parse_float => .parse_float_range,
                else => null,
            };
            if (range_kind) |ranged| if (try (collections.Builder(Checker){ .checker = self, .span = node.span }).fuseImmediateByteRange(base, ranged)) |fused|
                return fused;
        }
        return self.checkListAccess(node, .{ .base = call.base, .kind = kind, .inputs = call.arguments }, temporaries);
    }
    fn checkCollectionSlice(self: *Checker, node: ast.Node, temporaries: []const typed.Type) Error!typed.Node {
        const slice = node.data.slice;
        const base = try self.expressionWithTemporaries(slice.base, temporaries);
        const input = self.nodes.items[@backingInt(base)].ty;
        if (!input.isAggregate() or !self.catalog.records[input.recordIndex()].isCollection()) return self.sink.fail(eCollectionMethod, node.span, "slicing requires a list or str");
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
        const base = try self.expressionWithTemporaries(operation.base, temporaries);
        return self.checkCollectionAccess(node, .{ .base = base, .receiver = self.arenaReceiver(operation.base), .kind = operation.kind, .inputs = operation.inputs, .temporaries = temporaries, .signed_length = operation.signed_length });
    }
    fn checkCollectionAccess(self: *Checker, node: ast.Node, call: ListMethodCall) Error!typed.Node {
        const base = call.base;
        var kind = call.kind;
        const inputs = call.inputs;
        const temporaries = call.temporaries;
        const owner_type = self.nodes.items[@backingInt(base)].ty;
        const managed_owner = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isCollection();
        const dictionary = managed_owner and self.catalog.records[owner_type.recordIndex()].collection.kind == .dictionary;
        // `pop` is one Python name with an optional argument; its arity selects the
        // list-tail, list-index, dictionary-key or dictionary-default form.
        if (kind == .pop) kind = if (dictionary) (if (inputs.len == 2) .pop_default else .pop_key) else (if (inputs.len == 1) .pop_at else .pop);
        if (managed_owner and self.catalog.records[owner_type.recordIndex()].collection.kind != .list) {
            const receiver = call.receiver;
            return self.checkManagedAccess(node, .{ .base = base, .kind = kind, .inputs = inputs, .receiver = receiver }, temporaries);
        }
        if (switch (kind) {
            .extend, .insert, .pop, .pop_at, .remove, .index_of, .reverse, .sort, .copy, .clear => true,
            else => false,
        }) return self.checkListMethod(node, .{ .base = base, .receiver = call.receiver, .kind = kind, .inputs = inputs, .temporaries = temporaries });
        const supported = switch (kind) {
            .append, .read, .write, .length, .contains => true,
            else => false,
        };
        if (!supported) return self.sink.fail(eCollectionMethod, node.span, unsupported_list);
        const element = try self.listElement(self.nodes.items[@backingInt(base)].ty, node.span);
        if (kind == .contains and self.requiresCellEquality(element))
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
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            if (writes_element) try self.require(actual, element, node.span) else try self.requireInteger(actual, node.span);
        }
        try self.requireArenaOperation(call.receiver, kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, arguments, call.signed_length);
    }
    fn requireSortable(self: *Checker, element: typed.Type, span: source.Span) Error!void {
        if (element.isInteger() or numeric_surface.isFloat(element, self.catalog.records)) return;
        if (element.isAggregate() and self.catalog.records[element.recordIndex()].collection.kind == .string) return;
        return self.sink.fail(eCollectionMethod, span, "sort requires an integer, float or str element type");
    }

    /// Check a list's Python-shaped method call, which either mutates or copies its receiver.
    fn checkListMethod(self: *Checker, node: ast.Node, call: ListMethodCall) Error!typed.Node {
        const base = call.base;
        const kind = call.kind;
        const inputs = call.inputs;
        const temporaries = call.temporaries;
        const owner_type = self.nodes.items[@backingInt(base)].ty;
        const element = try self.listElement(owner_type, node.span);
        if ((kind == .remove or kind == .index_of) and self.requiresCellEquality(element))
            return self.sink.fail(eCellEquality, node.span, "list search over Cell-bearing values requires equality, which Cell does not define");
        if (inputs.len != kind.arity()) return self.methodArityFailure(.{
            .span = node.span,
            .name = node.span,
            .kind = kind,
            .names = try self.signatureNames(owner_type),
            .arguments = inputs.len,
        });
        if (kind == .sort and !(element.isInteger() or numeric_surface.isFloat(element, self.catalog.records))) {
            return self.sink.fail(eCollectionMethod, node.span, "sort requires an integer or float element type");
        }
        const names = try self.signatureNames(owner_type);
        const arguments = try self.allocator.alloc(typed.NodeId, inputs.len);
        switch (kind) {
            .extend => {
                try self.hint(inputs[0], owner_type);
                arguments[0] = try self.expressionWithTemporaries(inputs[0], temporaries);
                try self.requireArgument(.{ .actual = self.nodes.items[@backingInt(arguments[0])].ty, .expected = owner_type, .span = node.span, .kind = kind, .names = names });
            },
            .insert => {
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
        try self.requireArenaOperation(call.receiver, kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, kind, arguments, false);
    }

    fn checkManagedAccess(self: *Checker, node: ast.Node, operation: ManagedAccess, temporaries: []const typed.Type) Error!typed.Node {
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
            error.InternalError => return self.sink.fail(eCollectionMethod, node.span, unsupported_collection),
            else => return err,
        };
        if (dictionary and switch (operation.kind) {
            .items, .update, .setdefault, .pop_key, .pop_default, .copy, .clear => true,
            else => false,
        }) return self.checkDictionaryMethod(node, owner_type, operation, temporaries);
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
            const integer = !dictionary and (operation.kind == .read or operation.kind == .slice or operation.kind == .view or
                operation.kind == .parse_int_range or operation.kind == .parse_float_range or operation.kind == .scalar_count_range or widthArgument(operation.kind) or
                (operation.kind == .find_any and index == 1)) or
                byteBufferInteger(operation.kind, index);
            const expected = if (integer) typed.Type.i64 else if (dictionary) map_argument: {
                break :map_argument if (index == 0) schema.collection.key.? else schema.shape.buffer.?;
            } else if (operation.kind == .buffer_append_range and index == 0)
                try collections.preludeType(&self.catalog, "bytes", node.span)
            else if (operation.kind == .buffer_append_utf8)
                self.catalog.names.get("str") orelse return error.InternalError
            else if (operation.kind == .buffer_append_float)
                self.catalog.names.get("float") orelse return error.InternalError
            else if (operation.kind == .join) try self.collectionListType(owner_type, node.span) else owner_type;
            try self.hint(input, expected);
            argument.* = try self.expressionWithTemporaries(input, temporaries);
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            if (integer) try self.requireInteger(actual, node.span) else try self.requireArgument(.{ .actual = actual, .expected = expected, .span = node.span, .kind = operation.kind, .names = names });
        }
        try self.requireArenaOperation(operation.receiver, operation.kind, arguments);
        return (collections.Builder(Checker){ .checker = self, .span = node.span }).access(operation.base, operation.kind, arguments, false);
    }
    /// Check a dictionary's Python-shaped methods against its key and value types.
    fn checkDictionaryMethod(self: *Checker, node: ast.Node, owner_type: typed.Type, operation: ManagedAccess, temporaries: []const typed.Type) Error!typed.Node {
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
            else => {},
        }
        return false;
    }
    fn collectionListType(self: *Checker, element: typed.Type, span: source.Span) Error!typed.Type {
        const state = self.catalog.templates.store orelse return error.InternalError;
        return nominal_catalog.instantiateLengths(&self.catalog, state.index.names.get("List").?, &.{element}, &.{}, span);
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
            .find_any => {
                if (!byte_string) return self.sink.fail(eCollectionMethod, operation.owner, "find_any requires a bytes receiver and a byte set");
                try self.require(self.nodes.items[@backingInt(arguments[0])].ty, local.ty, operation.owner);
                try self.requireInteger(self.nodes.items[@backingInt(arguments[1])].ty, operation.owner);
                out.ty = .i64;
            },
            .strip, .lstrip, .rstrip, .upper, .lower, .splitlines, .replace, .count, .zfill, .is_digit, .is_alpha, .is_space => {
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
            .to_list, .hex, .decode, .encode, .from_hex, .parse_int, .parse_float => out.ty = collections.operationType(&self.catalog, local.ty, operation.kind, operation.owner) catch |err| switch (err) {
                error.InternalError => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
                else => return err,
            },
            // A view shares the receiver's octets, `copy` materializes them and
            // `scalar_count` measures them.
            .view, .copy, .scalar_count, .scalar_count_range, .parse_int_range, .parse_float_range => if (!try self.checkByteViewMethod(operation, owner, schema, arguments, out))
                return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
            .buffer_reserve, .buffer_append_byte, .buffer_append_range, .buffer_append_utf8, .buffer_append_int, .buffer_append_float => try self.checkByteBufferMethod(operation, owner, arguments, out),
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
            .split, .split_whitespace, .join => {
                if (dictionary) return self.sink.fail(eCollectionMethod, operation.owner, "split and join require str");
                const list_type = try self.collectionListType(local.ty, operation.owner);
                // The no-argument form has no separator to type-check; `join`
                // takes the list of pieces and both splits answer one.
                if (operation.kind != .split_whitespace) try self.require(self.nodes.items[@backingInt(arguments[0])].ty, if (operation.kind == .split) local.ty else list_type, operation.owner);
                out.ty = if (operation.kind == .join) local.ty else list_type;
            },
            .items, .pop, .pop_key, .pop_default, .update, .setdefault, .clear => return self.checkDictionaryBufferMethod(operation, owner, out),
            else => return self.sink.fail(eCollectionMethod, operation.owner, unsupported_collection),
        }
        out.data = .{ .buffer_operation = .{ .kind = operation.kind, .owner = owner, .arguments = arguments } };
    }
    /// Check one byte-string method that reads the receiver's own octets rather
    /// than the collection surface around them: `view` shares the octets as a
    /// range that retains the source's backing, `copy` materializes them, and
    /// `scalar_count` validates and measures them. All three exist only on the
    /// immutable byte string, so neither a mutable buffer nor a `str` reaches
    /// them, and none of them allocates except the copy it names.
    fn checkByteViewMethod(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, schema: typed.Record, arguments: []const typed.NodeId, out: *typed.Node) Error!bool {
        const owner_type = self.locals.items[@backingInt(owner)].ty;
        switch (operation.kind) {
            .view => {
                if (!isImmutableBytes(schema)) return self.sink.fail(eCollectionMethod, operation.owner, "view requires an immutable bytes receiver");
                for (arguments) |argument| try self.requireInteger(self.nodes.items[@backingInt(argument)].ty, operation.owner);
                out.ty = owner_type;
            },
            .copy => {
                // A dictionary shares the spelling and keeps its own shallow copy.
                if (schema.collection.kind == .dictionary) {
                    try self.checkDictionaryBufferMethod(operation, owner, out);
                    return true;
                }
                if (!isImmutableBytes(schema)) return self.sink.fail(eCollectionMethod, operation.owner, "copy requires an immutable bytes receiver");
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
    fn checkByteBufferMethod(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, arguments: []const typed.NodeId, out: *typed.Node) Error!void {
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
            } else if (operation.kind == .buffer_append_range and index == 0) {
                // An append copies octets out of any byte-kind value, so an
                // immutable `bytes` argument is accepted beside another buffer.
                if (!actual.isAggregate() or self.catalog.records[actual.recordIndex()].collection.kind != .bytes)
                    return self.sink.fail(eCollectionMethod, operation.owner, "append_range requires a bytes or byte_buffer source");
            } else try self.require(actual, local.ty, operation.owner);
        }
        out.ty = .bool;
    }
    /// Check a dictionary vocabulary operation reached through the buffer-operation
    /// form that a simple `mapping.method(...)` call desugars to.
    fn checkDictionaryBufferMethod(self: *Checker, operation: @FieldType(@FieldType(ast.Node, "data"), bufferOperation), owner: typed.LocalId, out: *typed.Node) Error!void {
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
            argument.* = self.resolved[@backingInt(input)].?;
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
        if (!local.ty.isAggregate() or !self.catalog.records[local.ty.recordIndex()].isCollection()) return self.sink.fail(eListType, operation.owner, needs_list);
        local.usage.reads += 1;
        if (self.catalog.records[local.ty.recordIndex()].collection.kind == .dictionary) if (dictionary_views.operation(operation.kind)) |kind| {
            if (operation.arguments.len != 0) return self.sink.fail("E_ARITY", operation.owner, "dictionary views take no arguments");
            const b: collections.Builder(Checker) = .{ .checker = self, .span = out.span };
            out.* = try dictionary_views.construct(Checker, self, out.span, try b.read(owner), kind);
            return;
        };
        if (operation.kind.mutates()) local.usage.writes += 1;
        const element = self.catalog.records[local.ty.recordIndex()].shape.buffer.?;
        if (self.catalog.records[local.ty.recordIndex()].collection.kind != .list) {
            try self.checkTextDictionary(operation, owner, out);
            return;
        }
        if (operation.kind == .contains and self.requiresCellEquality(element))
            return self.sink.fail(eCellEquality, operation.owner, "list membership over Cell-bearing values requires equality, which Cell does not define");
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
        if ((kind == .remove or kind == .index_of) and self.requiresCellEquality(element))
            return self.sink.fail(eCellEquality, operation.owner, "list search over Cell-bearing values requires equality, which Cell does not define");
        if (operation.arguments.len != kind.arity()) return self.methodArityFailure(.{
            .span = operation.owner,
            .name = operation.owner,
            .kind = kind,
            .names = try self.signatureNames(owner_type),
            .arguments = operation.arguments.len,
        });
        if (kind == .sort and !(element.isInteger() or numeric_surface.isFloat(element, self.catalog.records))) {
            return self.sink.fail(eCollectionMethod, operation.owner, "sort requires an integer or float element type");
        }
        const names = try self.signatureNames(owner_type);
        const arguments = try self.allocator.alloc(typed.NodeId, operation.arguments.len);
        for (operation.arguments, arguments, 0..) |input, *argument, index| {
            argument.* = self.resolved[@backingInt(input)].?;
            const actual = self.nodes.items[@backingInt(argument.*)].ty;
            const span = self.syntax.nodes.items[@backingInt(input)].span;
            switch (kind) {
                .extend => try self.requireArgument(.{ .actual = actual, .expected = owner_type, .span = span, .kind = kind, .names = names }),
                .insert => if (index == 0) try self.requireInteger(actual, span) else try self.requireArgument(.{ .actual = actual, .expected = element, .span = span, .kind = kind, .names = names }),
                .pop_at => try self.requireInteger(actual, span),
                .remove, .index_of => try self.requireArgument(.{ .actual = actual, .expected = element, .span = span, .kind = kind, .names = names }),
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
        const parameters = try self.allocator.alloc(typed.Type, function.signature.parameters.len);
        if (parameters.len > 16) return self.sink.fail(callback_type_code, name, "callbacks support at most 16 parameters");
        for (function.signature.parameters, parameters) |input, *parameter| {
            parameter.* = try self.catalog.resolve(self.src, input.ty, self.sink);
        }
        const result = try self.catalog.resolve(self.src, function.signature.return_type, self.sink);
        const expected_type = self.expected_types.get(name);
        const destination = if (expected_type) |expected| callables.signature(expected, self.catalog.records) else null;
        // An unannotated function value fills any callback slot: use the declared
        // ceiling when there is one, otherwise the destination slot's ceiling when
        // the call site fixes one, and finally unbounded `all`.
        var allowed = if (function.policy.effect_bound) |bound| bound.allowed else effect_set.all;
        if (function.policy.effect_bound == null) if (destination) |slot| {
            if (slot.return_type == result and std.mem.eql(typed.Type, slot.parameters, parameters)) allowed = slot.effects;
        };
        const implementation: typed.Callable = .{
            .parameters = parameters,
            .return_type = result,
            .effects = allowed,
            .mutates = function.signature.mutates,
            .return_origin = .unknown,
        };
        // Reuse the destination's interned schema when only its return-origin bound
        // differs; interning again would mint a second record with the same name.
        if (destination) |slot| {
            var probe = implementation;
            probe.return_origin = slot.return_origin;
            if (callables.equal(probe, slot)) {
                out.ty = expected_type.?;
                out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
                return true;
            }
        }
        out.ty = try callables.intern(self.allocator, &self.catalog, implementation, name, self.sink);
        out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
        return true;
    }
    fn indirectCall(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        const slot = try self.resolve(call.name);
        const contract = callables.signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) orelse return self.sink.fail(callback_type_code, call.name, "called local is not a function value");
        if (call.type_arguments.len != 0 or call.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", call.name, "callback argument count must match its signature");
        try self.checkMutationMarkers(call.arguments, call.argument_markers, contract.mutates);
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
    fn checkName(self: *Checker, node: ast.Node, name: @FieldType(@FieldType(ast.Node, "data"), "name"), out: *typed.Node) Error!void {
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
                // A str/bytes literal constant still needs its getter call, but a
                // scalar constant is a compile-time value: fold it to a literal at
                // each use so no guest call remains.
                if (try constants.literalType(index)) |literal_ty| {
                    out.ty = literal_ty;
                    out.data = .{ .call = .{ .function = self.ordinary_ids[index] orelse return error.InternalError, .arguments = &.{} } };
                    return;
                }
                const value = try constants.evaluate(index);
                out.ty = value.typeOf();
                out.data = if (value == .bool) .{ .boolean = value.bool } else .{ .integer = if (value == .i64) value.i64 else value.integer.value };
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
        if (self.option_facts.has(@backingInt(slot)) and self.expected_types.get(node.span) != out.ty) {
            const shape = prelude.optionShape(out.ty, self.catalog.records) orelse return error.InternalError;
            const value: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, out.*);
            out.* = try option_flow.payloadValue(self, value, shape, node.span);
        }
    }
    /// Python-spelled byte-string and octet-buffer constructors that are not
    /// ordinary function calls. `bytes(values)` builds from a `list[int]`,
    /// `bytes(buffer)` copies an octet buffer into an immutable byte string,
    /// `bytes.fromhex(s)` decodes hexadecimal text and `byte_buffer(values)`
    /// builds the mutable buffer that the in-place append methods accept.
    const ByteConversion = enum { from_list, from_hex, buffer_from_list };
    fn byteConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?ByteConversion {
        const name = self.src.text(call.name);
        if (call.owner) |owner| {
            if (self.active.contains("bytes") or self.functions.contains("bytes")) return null;
            const target = self.catalog.names.get("bytes") orelse return null;
            if (!target.isAggregate() or self.catalog.records[target.recordIndex()].collection.kind != .bytes) return null;
            if (!std.mem.eql(u8, self.src.text(owner), "bytes")) return null;
            return if (std.mem.eql(u8, name, "fromhex")) .from_hex else null;
        }
        if (std.mem.eql(u8, name, byte_buffer_name)) {
            if (self.active.contains(byte_buffer_name) or self.functions.contains(byte_buffer_name)) return null;
            return .buffer_from_list;
        }
        if (self.active.contains("bytes") or self.functions.contains("bytes")) return null;
        const target = self.catalog.names.get("bytes") orelse return null;
        if (!target.isAggregate() or self.catalog.records[target.recordIndex()].collection.kind != .bytes) return null;
        return if (std.mem.eql(u8, name, "bytes")) .from_list else null;
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
        const integer_list = schema != null and schema.?.managed and schema.?.collection.kind == .list and schema.?.shape.buffer == .i64;
        if (conversion == .buffer_from_list) {
            if (!integer_list) return self.sink.fail(eByteConversion, node.span, "byte_buffer() requires a list[int] argument");
            out.ty = try collections.preludeType(&self.catalog, byte_buffer_name, node.span);
            out.data = .{ .cast = value };
            return;
        }
        // `bytes(buffer)` copies the buffer's current octets, so the result shares
        // no storage with it: a later append through the buffer, or through any
        // alias of it, cannot change the byte string.
        if (schema != null and isMutableBytes(schema.?)) {
            out.ty = self.catalog.names.get("bytes") orelse return error.InternalError;
            out.data = .{ .cast = value };
            return;
        }
        if (!integer_list) return self.sink.fail(eByteConversion, node.span, "bytes() requires a list[int] or byte_buffer argument");
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
    /// The Python `Environment` surface reached through a capability value.
    const EnvironmentMethod = enum { get, only, names };
    /// Recognize `env.get(...)`, `env.only(...)` and `env.names()` on a local
    /// `Environment` binding.
    fn environmentMethod(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?EnvironmentMethod {
        const owner = call.owner orelse return null;
        const slot = self.active.get(self.src.text(owner)) orelse return null;
        if (self.locals.items[@backingInt(slot)].ty != .environment_cap) return null;
        const name = self.src.text(call.name);
        if (std.mem.eql(u8, name, "get")) return .get;
        if (std.mem.eql(u8, name, "only")) return .only;
        if (std.mem.eql(u8, name, "names")) return .names;
        return null;
    }
    /// `env.get("NAME") -> Option[str]`: materialize the literal bytes as a fixed
    /// `[N]u8` request and build the checked `environment_get` node with an Option
    /// result, so the native boundary answers `Some(text)` or `None`.
    fn checkEnvironmentGet(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, owner: source.Span, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0 or call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "env.get takes one literal name");
        const spelling = self.syntax.nodes.items[@backingInt(call.arguments[0])];
        if (spelling.data != .text) return self.sink.fail(eEnvironmentName, spelling.span, "environment name must be a literal str");
        const bytes = spelling.data.text;
        const name_type = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, spelling.span, self.sink);
        const values = try self.byteValues(bytes, spelling.span);
        const name: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = spelling.span, .ty = name_type, .data = .{ .array = values } });
        try self.requireReadable(slot, owner);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const capability: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = owner, .ty = .environment_cap, .data = .{ .local = slot } });
        const element = try collections.preludeType(&self.catalog, "str", node.span);
        out.ty = try collections.optionType(&self.catalog, element, node.span);
        out.data = .{ .environment_get = .{ .capability = capability, .name = name } };
    }
    /// `env.only("HOME", "PATH") -> Environment`: register the literal names as a
    /// NUL-separated scope blob and return a narrowed capability value. It performs
    /// no I/O and contributes no effect.
    fn checkEnvironmentOnly(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, owner: source.Span, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0 or call.arguments.len == 0) return self.sink.fail("E_ARITY", node.span, "env.only takes at least one literal name");
        var blob: std.ArrayList(u8) = .empty;
        defer blob.deinit(self.allocator);
        for (call.arguments) |argument| {
            const spelling = self.syntax.nodes.items[@backingInt(argument)];
            if (spelling.data != .text) return self.sink.fail(eEnvironmentName, spelling.span, "environment names must be literal str values");
            const name = spelling.data.text;
            if (name.len == 0 or std.mem.indexOfScalar(u8, name, 0) != null) return self.sink.fail(eEnvironmentName, spelling.span, "environment name must be a nonempty str without NUL");
            try blob.appendSlice(self.allocator, name);
            try blob.append(self.allocator, 0);
        }
        const names_type = try self.catalog.instantiateArray(self.allocator, .u8, blob.items.len, node.span, self.sink);
        const values = try self.byteValues(blob.items, node.span);
        const names: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = names_type, .data = .{ .array = values } });
        try self.requireReadable(slot, owner);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const capability: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = owner, .ty = .environment_cap, .data = .{ .local = slot } });
        out.ty = .environment_cap;
        out.data = .{ .environment_only = .{ .capability = capability, .names = names } };
    }
    /// `env.names() -> list[str]`: enumerate the visible environment names as a
    /// fresh managed list. It reads host environment state and contributes the
    /// `environment` effect.
    fn checkEnvironmentNames(self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, owner: source.Span, out: *typed.Node) Error!void {
        try call_arguments.positional(call, self.sink);
        if (call.type_arguments.len != 0 or call.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "env.names takes no arguments");
        try self.requireReadable(slot, owner);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const capability: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = owner, .ty = .environment_cap, .data = .{ .local = slot } });
        const text = try collections.preludeType(&self.catalog, "str", node.span);
        out.ty = try collections.listType(&self.catalog, text, node.span);
        out.data = .{ .environment_names = capability };
    }
    /// `fs.read_only()` and `fs.dir(path)` on a local `Filesystem`. Returns false
    /// when the call is not one of them and the ordinary call path should run.
    fn checkCapabilityNarrowing(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
        const owner = input.owner orelse return false;
        const slot = self.active.get(self.src.text(owner)) orelse return false;
        if (self.locals.items[@backingInt(slot)].ty != .filesystem_cap) return false;
        const name = self.src.text(input.name);
        if (std.mem.eql(u8, name, "read_only")) {
            if (input.type_arguments.len != 0 or input.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "read_only takes no arguments");
            try self.requireReadable(slot, owner);
            self.locals.items[@backingInt(slot)].usage.reads += 1;
            const value: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(self.allocator, .{ .span = owner, .ty = .filesystem_cap, .data = .{ .local = slot } });
            out.ty = .filesystem_cap;
            out.data = .{ .restrict_resource = .{ .permissions = external_resources.permissionBit(.read), .value = value } };
            return true;
        }
        if (std.mem.eql(u8, name, "dir")) {
            try self.checkDirCall(node, input, slot, out);
            return true;
        }
        if (self.fileAccessMethodKind(input)) |kind| {
            try self.checkFileAccessMethod(node, input, kind, out);
            return true;
        }
        return false;
    }
    /// `net.host(name) -> Network`: narrow a local `Network` to the single
    /// string-literal endpoint. Performs no I/O and contributes no effect.
    fn checkNetworkHost(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
        const owner = input.owner orelse return false;
        const slot = self.active.get(self.src.text(owner)) orelse return false;
        if (self.locals.items[@backingInt(slot)].ty != .network_cap) return false;
        if (!std.mem.eql(u8, self.src.text(input.name), "host")) return false;
        try self.checkHostCall(node, input, slot, out);
        return true;
    }
    /// Check `net.host(name)`: a `Network` receiver and one literal endpoint that
    /// becomes the sole endpoint every acquisition through the derived value may
    /// request. A dynamic name is `E_NETWORK_HOST`.
    fn checkHostCall(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, out: *typed.Node) Error!void {
        const owner = input.owner.?;
        if (input.type_arguments.len != 0 or input.arguments.len != 1 or input.argument_names.len != 0) return self.sink.fail("E_ARITY", node.span, "host takes one endpoint argument");
        const argument = self.syntax.nodes.items[@backingInt(input.arguments[0])];
        const bytes = switch (argument.data) {
            .text, .bytes => |spelling| spelling,
            else => return self.sink.fail(eNetworkHost, argument.span, "host requires a string literal endpoint"),
        };
        if (bytes.len == 0 or std.mem.indexOfScalar(u8, bytes, 0) != null) return self.sink.fail(eNetworkHost, argument.span, "host endpoint must be a nonempty str without NUL");
        try self.requireReadable(slot, owner);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const capability: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = owner, .ty = .network_cap, .data = .{ .local = slot } });
        const name_type = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, argument.span, self.sink);
        const values = try self.byteValues(bytes, argument.span);
        const name: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = argument.span, .ty = name_type, .data = .{ .array = values } });
        out.ty = .network_cap;
        out.data = .{ .host_resource = .{ .capability = capability, .name = name } };
    }
    /// Dispatch `env.get`, `env.only` and `env.names` on a local `Environment`.
    fn checkEnvironmentDispatch(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
        const method = self.environmentMethod(input) orelse return false;
        const owner = input.owner.?;
        const slot = self.active.get(self.src.text(owner)).?;
        switch (method) {
            .get => try self.checkEnvironmentGet(node, input, slot, owner, out),
            .only => try self.checkEnvironmentOnly(node, input, slot, owner, out),
            .names => try self.checkEnvironmentNames(node, input, slot, owner, out),
        }
        return true;
    }
    /// Whether an unqualified `replace(value, field=…)` call is the functional
    /// record update rather than the positional three-argument list intrinsic.
    /// A declared, imported or local name called `replace` keeps its own meaning.
    fn recordUpdateCall(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
        if (call.owner != null or call.argument_names.len == 0 or call.argument_markers.len != 0) return false;
        if (!std.mem.eql(u8, self.src.text(call.name), "replace")) return false;
        if (self.active.contains(self.src.text(call.name))) return false;
        return !try self.topLevel(call.name);
    }
    /// Check `replace(record, field=value, …)` into the existing checked update
    /// node: the base is an aggregate record and only the named fields change.
    fn checkRecordUpdate(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        const base = self.resolved[@backingInt(input.arguments[0])].?;
        const record_type = self.nodes.items[@backingInt(base)].ty;
        if (!record_type.isAggregate() or !self.catalog.records[record_type.recordIndex()].isRecord())
            return self.sink.fail("E_TYPE", input.name, "replace(...) needs a record value; the positional form replaces a list index");
        const initializers = try self.allocator.alloc(ast.FieldInit, input.arguments.len - 1);
        for (input.arguments[1..], 0..) |value, index| initializers[index] = .{ .name = input.argument_names[index + 1].?, .value = value };
        out.ty = record_type;
        out.data = .{ .update = .{ .base = base, .fields = try self.fields(record_type, initializers, false, node.span) } };
    }
    fn checkCall(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
        // A call carrying `&` markers must resolve to a declared function or a
        // callable value: only those expose a `mutates(...)` footprint. Skipping
        // the builtin/constructor dispatch for such a call routes it through the
        // ordinary resolution below, where a marker on a non-declaring callee is
        // reported instead of silently accepted.
        const markers_present = input.argument_markers.len != 0;
        if (!markers_present) {
            if (try self.checkCapabilityNarrowing(node, input, out)) return;
            if (try self.checkNetworkHost(node, input, out)) return;
            if (try self.checkEnvironmentDispatch(node, input, out)) return;
            if (try self.cellConstructor(input)) |declaration| {
                const value = self.resolved[@backingInt(input.arguments[0])].?;
                const element = self.nodes.items[@backingInt(value)].ty;
                out.ty = try nominal_catalog.instantiateLengths(&self.catalog, declaration, &.{element}, &.{}, node.span);
                out.data = .{ .record = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = 0, .value = value }}) };
                return;
            }
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
            if (try self.fileAccessBuiltin(input)) |kind| return self.checkFileAccessCall(node, input, kind, out);
            if (try self.streamMethod(input)) |method| {
                if (method.write) return self.checkStreamWrite(node, input, method.stream, out);
                return self.checkPrint(node, input, .{ .stream = method.stream }, out);
            }
            if (try self.debugBuiltin(input)) return self.checkPrint(node, input, .{ .sink = .stderr, .debug = true }, out);
            if (try self.outputBuiltin(input)) |sink| return self.checkPrint(node, input, .{ .sink = sink }, out);
            if (self.byteConversion(input)) |conversion| return self.checkByteConversion(node, input, conversion, out);
            if (try self.resultConstructor(input)) |ok| {
                try call_arguments.positional(input, self.sink);
                return self.checkResultConstructor(node, input, ok, out);
            }
        }
        if (try self.recordUpdateCall(input)) return self.checkRecordUpdate(node, input, out);
        if (input.owner == null and self.active.contains(self.src.text(input.name))) {
            try call_arguments.positional(input, self.sink);
            return self.indirectCall(node, input, out);
        }
        const target = try self.callDeclaration(input, node.span);
        const call = target.call;
        const function = try self.specialize(target.declaration, call, node.span);
        const signature = self.syntaxFunction(function);
        try self.warnDeprecated(function, input);
        try self.checkMutationMarkers(call.arguments, call.argument_markers, signature.signature.mutates);
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
    /// Append a `W_DEPRECATED` warning when a call resolves to a `@deprecated`
    /// declaration in another module. The attribute lives on the AST, not on
    /// `typed.Function`, so the callee's declaration header is consulted here.
    fn warnDeprecated(self: *Checker, function: typed.FunctionId, input: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
        if (self.catalog.module_names == null) return;
        const callee = self.syntaxFunction(function);
        const attributes = ast.attributesOf(self.syntax, callee.name);
        var deprecated = false;
        var reason: ?source.Span = null;
        for (attributes) |attribute| {
            if (attribute.kind != .deprecated) continue;
            deprecated = true;
            reason = attribute.argument;
        }
        if (!deprecated) return;
        const callee_original = self.src.originalSpan(callee.name) catch return;
        const call_original = self.src.originalSpan(input.name) catch return;
        if (callee_original.input == call_original.input) return;
        const message = try std.fmt.allocPrint(self.allocator, "{s} is deprecated: {s}", .{
            self.src.text(callee.name),
            if (reason) |span| literalText(self.src.bytes, span) else "no reason given",
        });
        try self.sink.items.append(self.allocator, .{ .severity = .warning, .code = "W_DEPRECATED", .span = input.name, .message = message });
    }
    /// Enforce the opt-in D3 call-site `&` marker against a resolved callee's
    /// declared `mutates(...)` parameter positions. `arguments` is already in
    /// parameter order and `markers` is aligned with it. A marker is required on
    /// every declared position, rejected on an undeclared one, and rejected on a
    /// target that cannot be assigned through.
    fn checkMutationMarkers(self: *Checker, arguments: []const ast.NodeId, markers: []const bool, mutates: []const u16) Error!void {
        if (!self.mutation_markers) return;
        for (arguments, 0..) |argument, position| {
            const declared = markerPositionDeclared(mutates, @intCast(position));
            const marked = markers.len != 0 and markers[position];
            const arg_node = self.syntax.nodes.items[@backingInt(argument)];
            const text = self.src.text(arg_node.span);
            if (declared and !marked) {
                const message = try std.fmt.allocPrint(self.allocator, "argument {d} is declared writable by `mutates(...)`; add the `&` marker so the call shows the write: `&{s}`", .{ position + 1, text });
                return self.sink.fail(mutation_marker_code, arg_node.span, message);
            }
            if (marked and !declared) {
                const message = try std.fmt.allocPrint(self.allocator, "`&` marks a write, but the callee does not declare this position in `mutates(...)`; remove the marker: `{s}`", .{text});
                return self.sink.fail(mutation_marker_code, arg_node.span, message);
            }
            if (marked and !self.markerTarget(arg_node)) return self.sink.fail(mutation_marker_code, arg_node.span, "`&` requires an assignable argument (a variable, field, or list slot); assign it to a local first");
        }
    }
    /// Whether an argument expression names a place a callee could write to:
    /// a variable, or a field/index chain rooted at one.
    fn markerTarget(self: *Checker, node: ast.Node) bool {
        return switch (node.data) {
            .name => true,
            .field => |field| self.markerTarget(self.syntax.nodes.items[@backingInt(field.base)]),
            .index => |index| self.markerTarget(self.syntax.nodes.items[@backingInt(index.base)]),
            else => false,
        };
    }
    /// Whether one zero-based position appears in a normalized `mutates(...)` set.
    fn markerPositionDeclared(positions: []const u16, position: u16) bool {
        for (positions) |candidate| if (candidate == position) return true;
        return false;
    }
    /// Check `fs.dir(path)`: the receiver must be a `Filesystem` and the path a
    /// single string literal that stays within the current root.
    fn checkDirCall(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, out: *typed.Node) Error!void {
        const owner = input.owner.?;
        if (input.type_arguments.len != 0 or input.arguments.len != 1 or input.argument_names.len != 0) return self.sink.fail("E_ARITY", node.span, "dir takes one path argument");
        const argument = self.syntax.nodes.items[@backingInt(input.arguments[0])];
        const bytes = switch (argument.data) {
            .text, .bytes => |spelling| spelling,
            else => return self.sink.fail(eFilesystemDir, argument.span, "dir requires a string literal path"),
        };
        if (!scopedDirectoryPath(bytes)) return self.sink.fail(eFilesystemDir, argument.span, "dir path must stay within the current root");
        try self.requireReadable(slot, owner);
        self.locals.items[@backingInt(slot)].usage.reads += 1;
        const capability: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = owner, .ty = .filesystem_cap, .data = .{ .local = slot } });
        const path_type = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, argument.span, self.sink);
        const values = try self.byteValues(bytes, argument.span);
        const path: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = argument.span, .ty = path_type, .data = .{ .array = values } });
        out.ty = .filesystem_cap;
        out.data = .{ .dir_resource = .{ .capability = capability, .path = path } };
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
        if (u.op == .is_none) {
            const shape = prelude.optionShape(operand_ty, self.catalog.records) orelse return self.sink.fail("E_OPTION_TEST", u.op_span, "is None requires an Option value");
            if (self.transfers(operand_ty)) return self.sink.fail("E_OPTION_TEST", u.op_span, "use match for an Option carrying an owned value or checked Result");
            return option_flow.testValue(self, operand, shape, node.span);
        }
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
            out.ty = try nominal_catalog.instantiateLengths(&self.catalog, state.index.names.get("dict").?, &.{ key, value }, &.{}, node.span);
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
        // Equality of the two byte kinds is content equality of the same octets,
        // so a byte string and an octet buffer compare without a conversion;
        // every other operator still requires one type on both sides.
        const mixed_bytes = (b.op == .eq or b.op == .ne) and isByteKind(self.catalog.records, lt) and isByteKind(self.catalog.records, rt);
        if (!mixed_bytes) try self.require(rt, lt, b.op_span);
        if ((b.op == .eq or b.op == .ne) and self.requiresCellEquality(lt))
            return self.sink.fail(eCellEquality, b.op_span, "Cell equality is not defined, including inside collections");
        if (numeric_surface.isFloat(lt, self.catalog.records)) {
            out.* = try self.checkFloatBinary(out.span, b.op, left, right);
            return;
        }
        const text_operands = lt.isAggregate() and self.catalog.records[lt.recordIndex()].isCollection();
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
        if (!container_type.isAggregate() or !self.catalog.records[container_type.recordIndex()].isCollection()) return self.sink.fail("E_MEMBERSHIP", node.span, "membership requires a list, dictionary, or str");
        const schema = self.catalog.records[container_type.recordIndex()];
        const compared = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .dictionary => schema.collection.key.?,
            .string => container_type,
            .bytes => null,
        };
        if (compared) |key_or_element| if (self.requiresCellEquality(key_or_element))
            return self.sink.fail(eCellEquality, node.span, "membership over Cell-bearing values requires equality, which Cell does not define");
        var member = needle;
        const expected = switch (schema.collection.kind) {
            .list => schema.shape.buffer.?,
            .dictionary => schema.collection.key.?,
            .string => container_type,
            .bytes => try self.byteMembership(node.span, &member, container_type),
        };
        // Both byte kinds name a contiguous octet needle, so a byte string finds
        // its octets inside an octet buffer and the reverse without conversion.
        const member_type = self.nodes.items[@backingInt(member)].ty;
        const mixed_needle = schema.collection.kind == .bytes and isByteKind(self.catalog.records, member_type);
        if (!mixed_needle) try self.require(member_type, expected, node.span);
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
        try self.nodes.append(self.allocator, .{ .span = node.span, .ty = if (mixed_needle) member_type else expected, .data = .{ .local = locals[0] } });
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
        if (receiver_type.isAggregate() and self.catalog.records[receiver_type.recordIndex()].isCollection()) {
            out.* = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(base, .read, &.{index_value}, false);
            return;
        }
        if (record_layouts.tupleRecord(self.catalog.records, receiver_type) != null)
            return self.sink.fail("E_TUPLE_INDEX", node.span, tuple_index_alternative);
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
                out.data = .{ .replace = .{ .base = base, .index = index_value, .value = value } };
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
                if (self.narrowedCollection(call)) |slot| return self.checkNarrowedMethod(node, slot, temporaries);
                try self.checkCall(node, call, &out);
            },
            .unary => |u| return self.checkUnary(node, u),
            .binary => |b| try self.checkValueBinary(b, &out),
            .tuple => |elements| try self.checkTuple(node, elements, temporaries, &out),
            // lane: conditional expression (item 6): this arm is replaced by the
            // two-branch check the simple lane adds.
            .conditional => return self.sink.fail(eNotImplemented, node.span, "conditional expressions parse but are not checked yet"),
            // lane: mut marker (item 1): this arm is replaced by the
            // mutation-marker check the `mut` lane adds.
            .mut_argument => return self.sink.fail(eNotImplemented, node.span, "the `mut` argument marker parses but is not checked yet"),
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
        if (node.data == .unary and node.data.unary.op == .is_none) return 1;
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
    fn narrowedOption(self: *Checker, slot: typed.LocalId) ?prelude.OptionShape {
        if (!self.option_facts.has(@backingInt(slot))) return null;
        return prelude.optionShape(self.locals.items[@backingInt(slot)].ty, self.catalog.records);
    }
    /// Apply facts carried by one branch of an already-checked condition.
    fn assumeOption(self: *Checker, condition: ast.NodeId, truth: bool) Error!void {
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
    fn statementForEach(self: *Checker, stmt: ast.Statement, each: @FieldType(@FieldType(ast.Statement, "data"), "for_each")) Error!@FieldType(typed.Statement, "data") {
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
        if (!iterable_type.isAggregate() or !self.catalog.records[iterable_type.recordIndex()].isCollection()) return self.sink.fail(eCollectionMethod, stmt.span, "iteration requires a collection or dictionary view");
        const schema = self.catalog.records[iterable_type.recordIndex()];
        const kind = schema.collection.kind;
        const element = if (projected) try dictionary_views.element(&self.catalog, iterable_type, view.?, stmt.span) else switch (kind) {
            .list => schema.shape.buffer.?,
            .string => iterable_type,
            .bytes => typed.Type.i64,
            .dictionary => schema.collection.key.?,
        };
        const unpack = each.index_name != null and !each.enumerated;
        if (unpack and dictionary_views.identify(self.catalog, element) != .item) {
            const pair = record_layouts.tupleRecord(self.catalog.records, element) orelse
                return self.sink.fail("E_ITERATION", stmt.span, "two iteration names require dictionary items, enumerate, zip or a list of two-value tuples");
            if (pair.fields.len != 2) return self.sink.fail(eTupleArity, stmt.span, try self.twoNameLoopMessage(pair.fields.len));
        }
        const first_type = if (unpack) self.catalog.records[element.recordIndex()].fields[0].ty else element;
        const owner = try b.local(iterable_type);
        const index = try b.local(.i64);
        const limit = try b.local(.i64);
        const first_slot = try b.local(first_type);
        const second_slot = if (unpack) try b.local(self.catalog.records[element.recordIndex()].fields[1].ty) else index;
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
        self.initRestore(init_before);
        if (!body.terminates) try self.samePending(before, stmt.span, eResultLoop);
        self.restorePending(before);
        const i = try b.read(index);
        const iteration_check = try b.stmt(.{ .discard = try b.operation(owner, .iteration_check, &.{try b.read(limit)}) });
        var iteration_statements: std.ArrayList(typed.StatementId) = .empty;
        try iteration_statements.append(self.allocator, iteration_check);
        const value = try self.projectedIterationValue(b, owner, i, kind, if (projected) view else null);
        if (unpack) {
            const pair = try b.local(element);
            try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = pair, .value = value } }));
            const first_value = try b.node(first_type, .{ .field = .{ .base = try b.read(pair), .index = 0 } });
            const second_type = self.locals.items[@backingInt(second_slot)].ty;
            const second_value = try b.node(second_type, .{ .field = .{ .base = try b.read(pair), .index = 1 } });
            try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first_slot, .value = first_value } }));
            try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = second_slot, .value = second_value } }));
        } else try iteration_statements.append(self.allocator, try b.stmt(.{ .initialize = .{ .slot = first_slot, .value = value } }));
        try iteration_statements.append(self.allocator, body.id);
        const iteration = try b.stmt(.{ .block = try iteration_statements.toOwnedSlice(self.allocator) });
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
        .mutation_markers = src.mutation_markers,
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
    try @import("effects.zig").check(allocator, checked, exported, sink);
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

/// Remove the matching quotes around one string-literal spelling.
fn literalText(bytes: []const u8, span: source.Span) []const u8 {
    const text = bytes[span.start..span.end];
    if (text.len >= 2 and (text[0] == '"' or text[0] == '\'')) return text[1 .. text.len - 1];
    return text;
}

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
