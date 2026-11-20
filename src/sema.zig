//! Scope and type checking use resolved binding identities, including advisory use counts.
const sema_shared = @import("sema_shared.zig");
const check_directory = @import("check_directory.zig");
const lexer = @import("lexer.zig");
const removed_names = @import("removed_names.zig");
const sema_contracts = @import("sema_contracts.zig");
const buffer_operations = @import("buffer_operations.zig");
const ManagedKind = @import("runtime_values.zig").ManagedKind;
const BufferKind = buffer_operations.Kind;
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const loop_rebinding = @import("loop_rebinding.zig");
const eListType = @import("collection_lower.zig").list_type_error;
const call_arguments = @import("call_arguments.zig");
const unknown_qualifier = @import("unknown_qualifier.zig");
const library_function_form = @import("library_function_form.zig");
const external_resources = @import("external_resources.zig");
const io_builtins = @import("io_builtins.zig");
const io_render = @import("io_render.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const own_parameters = @import("own_parameters.zig");
const lambda_context_code = sema_shared.lambda_context_code;
const call_argument_code = sema_shared.call_argument_code;
/// Stable code for a call-site `&` mutation marker that does not match the
/// callee's declared `mutates(...)` footprint.
const eResultOperation = diagnostic.result_operation;
const eResultReturnRemoved = diagnostic.result_return_removed;
const eResultPath = diagnostic.result_path;
const eShadowing = diagnostic.shadowing;
/// `Unit()` outside a `return` (F-41): the builtin type has no constructor.
const unit_call_message = "`Unit` is a type with no constructor: its one value is written `()`, and a function that returns `Unit` ends with a bare `return`";
const eConversionBody = "E_CONVERSION_BODY";
const sem_copy = @import("semantic_copy.zig");
const generic_specializations = @import("generic_specializations.zig");
const generic_bodies = @import("generic_bodies.zig");
const semantic_key = @import("semantic_key.zig");
const sem_entry = @import("semantic_entry.zig");
const pattern_discard_fix = @import("pattern_discard_fix.zig");

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
const builtin = @import("builtin");
const compile_mode = @import("builtin").mode;
const value_semantics = @import("value_semantics.zig");
const dictionary_views = @import("dictionary_views.zig");
const bufferOperation = sema_shared.bufferOperation;
const eCollectionMethod = sema_shared.eCollectionMethod;
const eParallelMapFallible = "E_PARALLEL_MAP_FALLIBLE";
/// A `parallel.map` with trailing arguments refused by its checks (E1b): too many, an owned one, or a fallible function.
const eParallelMapArgs = "E_PARALLEL_MAP_ARGS";
/// The `mut` argument refusal a task and its map share (E1b).
const eTaskMut = "E_TASK_MUT";
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
/// The checked signature of one whole-path file helper in the spelling that works, a method of the `Filesystem` (`fs`) or of
/// the `Input` (`input`), with the types as the compiler reads them (`Result[Unit, str]`, not `None`). The free `read_text(fs, ...)`
/// is a removed spelling, so no row prints it; the three channels of the standard library (`run_process`, `process_control`,
/// `stop_control`) have no method and print their own form, which only the library writes.
fn fileAccessSignature(kind: file_operations.Access) []const u8 {
    return switch (kind) {
        .open => "fs.open(path: str, mode: str) -> Result[File, str]",
        .read_file => "fs.read_file(path: str) -> Result[bytes, str]",
        .read_text => "fs.read_text(path: str) -> Result[str, str]",
        .write_file => "fs.write_file(path: str, data: bytes) -> Result[Unit, str]",
        .write_text => "fs.write_text(path: str, text: str) -> Result[Unit, str]",
        .exists => "fs.exists(path: str) -> bool",
        .listdir => "fs.listdir(path: str) -> Result[str[], str]",
        .mkdir => "fs.mkdir(path: str) -> Result[Unit, str]",
        .remove => "fs.remove(path: str) -> Result[Unit, str]",
        .atomic_write_file => "fs.atomic_write_file(path: str, data: bytes) -> Result[Unit, str]",
        .lock_directory => "fs.lock_directory(path: str) -> Result[File, str]",
        .sync_directory => "fs.sync_directory(path: str) -> Result[Unit, str]",
        .read_regular_file => "fs.read_regular_file(path: str, max_bytes: int) -> Result[bytes, str]",
        .rename_path => "fs.rename_path(from: str, to: str) -> Result[Unit, str]",
        .stat_path => "fs.stat_path(path: str) -> Result[bytes, str]",
        .lock_file => "fs.lock_file(path: str) -> Result[File, str]",
        .try_lock_file => "fs.try_lock_file(path: str) -> Result[File, str]",
        .canonical_path => "fs.canonical_path(path: str) -> Result[str, str]",
        .chmod_path => "fs.chmod_path(path: str, mode: int) -> Result[Unit, str]",
        .touch_path => "fs.touch_path(path: str) -> Result[Unit, str]",
        .set_modified_path => "fs.set_modified_path(path: str, nanoseconds: int) -> Result[Unit, str]",
        .atomic_write_file_mode => "fs.atomic_write_file_mode(path: str, data: bytes, mode: int) -> Result[Unit, str]",
        .stat_follow_path => "fs.stat_follow_path(path: str) -> Result[bytes, str]",
        .list_entries_path => "fs.list_entries_path(path: str) -> Result[bytes, str]",
        .replace_file => "fs.replace_file(path: str, data: bytes) -> Result[Unit, str]",
        .replace_file_mode => "fs.replace_file_mode(path: str, data: bytes, mode: int) -> Result[Unit, str]",
        .replace_file_synced => "fs.replace_file_synced(path: str, data: bytes) -> Result[Unit, str]",
        .replace_file_synced_mode => "fs.replace_file_synced_mode(path: str, data: bytes, mode: int) -> Result[Unit, str]",
        .symlink_path => "fs.symlink_path(target: str, path: str) -> Result[Unit, str]",
        .statfs_path => "fs.statfs_path(path: str) -> Result[bytes, str]",
        .read_at_path => "fs.read_at_path(path: str, offset: bytes, max_bytes: int) -> Result[bytes, str]",
        .read_link_path => "fs.read_link_path(path: str) -> Result[str, str]",
        .link_path => "fs.link_path(target: str, path: str) -> Result[Unit, str]",
        .mkdir_mode => "fs.mkdir_mode(path: str, mode: int) -> Result[Unit, str]",
        .create_mode => "fs.create_mode(path: str, mode: int) -> Result[File, str]",
        .run_process => "run_process(proc: Process, request: bytes, limit: int) -> Result[bytes, str]",
        .process_control => "process_control(proc: Process, data: bytes, op: int) -> Result[bytes, str]",
        .read => "input.read(max: int) -> bytes",
        .read_exact => "input.read_exact(n: int) -> bytes?",
        .read_line => "input.read_line() -> bytes?",
        .stop_control => "stop_control(stop: Stop, op: int) -> bool",
        .list_directory => "fs.list_directory(path: str, max_entries: int) -> Result[str[], str]",
    };
}
/// The accepted argument shapes of one open-handle method.
fn fileMethodSignature(kind: file_operations.Method) []const u8 {
    return switch (kind) {
        .read => "read() -> str, or read(size: int) -> str",
        .readline => "readline() -> str",
        .readlines => "readlines() -> str[]",
        .write => "write(data) -> int",
        .flush => "flush() -> None",
        .close => "close() -> None",
        .sync => "sync() -> Result[Unit, str]",
    };
}

const ast = @import("ast.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const entry_adapter = @import("entry_adapter.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const records = @import("records.zig");
const template_stand_ins = @import("template_stand_ins.zig");
const stand_in_kinds = @import("stand_in_kinds.zig");
const record_layouts = @import("record_layouts.zig");
const Error = diagnostic.Error;
const instances = @import("generic_instances.zig");
const semantic_cache = @import("semantic_cache.zig");
const sema_summaries = @import("sema_summaries.zig");
const resolved_table = @import("sema_resolved.zig");
const origins = @import("origins.zig");
const timings = @import("timings.zig");
const generic_cache = @import("generic_cache.zig");
const names_module = @import("module_names.zig");
const Names = names_module.Names;
const sealed_rules = @import("sealed_rules.zig");
const LoopCheckpoint = struct { pending: []const Pending, init_before: []const u2, init_breaks: ?[]u2 = null };
/// `detach` is the frame of a `detach` loop (`loop_detach.zig`), whose put-back each `return` inside it runs first.
const LoopScope = struct { id: usize, before: *LoopCheckpoint, exited: bool = false, detach: ?*const @import("loop_detach.zig").Frame = null };
const ArenaScope = struct { name: []const u8 };
const eUnbound = "E_UNBOUND";
const eWithResource = sema_shared.eWithResource;
const eFileArgument = sema_shared.eFileArgument;
const Pending = sema_shared.Pending;
const Work = sema_shared.Work;

const StatementFlow = sema_shared.StatementFlow;

const integer_literal = @import("integer_literal.zig");
const float_syntax = @import("float_syntax.zig");
const literal_peer = @import("literal_peer.zig");
const number_literal = @import("number_literal.zig");
const numeric_surface = @import("numeric_surface.zig");
const prelude = @import("prelude.zig");
const prelude_builtins = @import("prelude_builtins.zig");
const prelude_names = @import("prelude_names.zig");
const arrays = @import("array_literals.zig");
const variant_calls = @import("variant_calls.zig");
const truncating = @import("truncating_math.zig");

const LambdaCapture = sema_shared.LambdaCapture;
const uninferred_lambda = sema_shared.uninferred_lambda;

const markerPositionDeclared = sema_shared.markerPositionDeclared;
/// The success and failure spellings inside a `Result[...]` return clause, or null.
const ResultClause = struct { success: []const u8, failure: []const u8 };
fn parseResultClause(text: []const u8) ?ResultClause {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const prefix: []const u8 = if (std.mem.startsWith(u8, trimmed, "Result["))
        "Result["
    else if (std.mem.startsWith(u8, trimmed, "std_result::Result["))
        "std_result::Result["
    else
        return null;
    if (trimmed.len <= prefix.len or trimmed[trimmed.len - 1] != ']') return null;
    const inner = trimmed[prefix.len .. trimmed.len - 1];
    var depth: i32 = 0;
    var comma: ?usize = null;
    for (inner, 0..) |ch, index| {
        switch (ch) {
            '[', '(', '{' => depth += 1,
            ']', ')', '}' => depth -= 1,
            ',' => if (depth == 0 and comma == null) {
                comma = index;
            },
            else => {},
        }
    }
    const at = comma orelse return null;
    return .{ .success = std.mem.trim(u8, inner[0..at], " \t\r\n"), .failure = std.mem.trim(u8, inner[at + 1 ..], " \t\r\n") };
}

const Checker = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    syntax: ast.Program,
    /// Whether `syntax`'s node and statement lists are this check's private copy, made by
    /// `frontend_patterns` before its first append. The caller's lists are never written.
    tables_private: bool = false,
    view_consumers: dictionary_views.Consumers,
    sink: *diagnostic.Sink,
    nodes: std.ArrayList(typed.Node) = .empty,
    statements: std.ArrayList(typed.Statement) = .empty,
    locals: std.ArrayList(typed.Local) = .empty,
    /// Statements in earlier functions use a different local ID namespace.
    function_statement_start: usize = 0,
    active: std.StringHashMapUnmanaged(typed.LocalId) = .empty,
    /// How many record field defaults are being checked at once (`enterDefault`): inside one, no local is in scope.
    constant_default: u32 = 0,
    resolved: resolved_table.Resolved,
    expected_types: std.AutoHashMapUnmanaged(source.Span, typed.Type) = .empty,
    /// Original expression types containing generic parameters, before substitution.
    generic_type_dependence: ?*const std.AutoHashMapUnmanaged(source.Span, void) = null,
    option_facts: option_flow.State = .{},
    functions: std.StringHashMapUnmanaged(instances.DeclarationId) = .empty,
    resolved_nodes: std.ArrayList(usize) = .empty,
    /// The declaration name of each syntactic function, as the registration loop of `checkProgram` made it: an ordinary instance's name is this one.
    declared_names: []const []const u8 = &.{},
    instance_keys: std.ArrayList(instances.Key) = .empty,
    generic_registry: instances.Registry = .{},
    /// C3 concrete-specialization reuse: stable declaration facts and the
    /// canonical fingerprint -> fresh instance-index map. Empty when no
    /// semantic cache is attached.
    prepared: ?*const semantic_key.Prepared = null,
    spec_build: []const u8 = "",
    spec_fingerprints_enabled: bool = false,
    spec_fingerprints: std.ArrayList(?[]const u8) = .empty,
    spec_ranges: std.ArrayList(sem_copy.Range) = .empty,
    spec_index: std.StringHashMapUnmanaged(typed.FunctionId) = .empty,
    spec_fresh: std.ArrayList(usize) = .empty,
    ordinary_instance_by_key: std.StringHashMapUnmanaged(usize) = .empty,
    /// Declaration index of each stable key (`maxInt` for a key two declarations share), built on the first lookup of a template by key.
    template_by_key: ?std.StringHashMapUnmanaged(usize) = null,
    /// The transitive record shapes this request asked for, kept across the specializations it restores (a record's shape does not change
    /// once the catalog holds it).
    spec_shapes: ?semantic_key.Shapes = null,
    record_by_name: std.StringHashMapUnmanaged(usize) = .empty,
    indexed_record_count: usize = 0,
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
    return_type: typed.Type = .i64,
    success_type: typed.Type = .unit,
    failure_type: ?typed.Type = null,
    arenas: std.ArrayList(ArenaScope) = .empty,
    catalog: records.Catalog,
    conversion_fields: ?[]bool = null,
    managed_types: []bool = &.{},
    owner: ?typed.Type = null,
    /// The `with open(...)` head whose failure traps instead of yielding a result.
    trapping_open: ?source.Span = null,
    /// Contract clauses of the function being checked and the invariant index.
    contract: sema_contracts.State = .{},
    /// The comprehensions and generator expressions being checked, innermost
    /// last, and the use each consuming call gave its generator argument.
    match_yield: ?struct { slot: typed.LocalId, ty: ?typed.Type } = null,
    gathers: @import("sema_gathers.zig").State = .{},
    /// Task groups, their handles and the values they lend (E1).
    tasks: @import("sema_tasks.zig").State = .{},
    /// Which statements of the function being checked failed, and the names they leave unknown (`sema_recovery.zig`).
    recovery: @import("sema_recovery.zig").State = .{},
    /// The payload bindings of the function being checked that own their payloads: those of `match own <name>:` and of
    /// a match on a value no local holds. A consuming loop takes one (`for x in own found:`), as it takes an owned local.
    consuming_bindings: std.AutoHashMapUnmanaged(typed.LocalId, void) = .empty,
    /// The `@linear` owners of the function being checked that a `match mut` lent, with that scrutinee's span: the match
    /// does not end them, and a refusal of one left unconsumed says so (FX8, decision LIN).
    match_lent_owners: std.AutoHashMapUnmanaged(typed.LocalId, source.Span) = .empty,

    /// Reset the per-function state and bind one ordinary instance's signature:
    /// its owner, return type and parameter locals.
    fn beginFunction(self: *Checker, i: usize, function: ast.Function) Error!void {
        self.checked_index = i;
        self.current_function = @fromBackingInt(i);
        self.current_lambda = null;
        for (self.resolved_nodes.items) |node| self.resolved.put(node, null);
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.option_facts.clear();
        self.locals = .empty;
        self.consuming_bindings.clearRetainingCapacity();
        self.match_lent_owners.clearRetainingCapacity();
        self.function_statement_start = self.statements.items.len;
        self.active.clearRetainingCapacity();
        self.owner = if (function.policy.owner) |owner| try self.ty(owner) else null;
        self.success_type = try self.ty(function.signature.return_type);
        self.failure_type = if (function.signature.failure_type) |failure| try self.ty(failure) else null;
        self.return_type = if (self.failure_type) |failure| try @import("frontend_failures.zig").resultType(&self.catalog, self.allocator, self.success_type, failure, function.name, self.sink) else self.success_type;
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
                .noalloc = noalloc: {
                    for (ast.attributesOf(self.syntax, function.name)) |attribute| if (attribute.kind == .noalloc) break :noalloc attribute.span;
                    break :noalloc null;
                },
                .freestanding = freestanding: {
                    for (ast.attributesOf(self.syntax, function.name)) |attribute| if (attribute.kind == .freestanding) break :freestanding attribute.span;
                    break :freestanding null;
                },
                // `@freestanding(ram)`: the parser keeps an argument only for the one placement, `ram`.
                .ram = for (ast.attributesOf(self.syntax, function.name)) |attribute| {
                    if (attribute.kind == .freestanding and attribute.argument != null) break true;
                } else false,
                .owner = self.owner,
                .restricted = function.policy.restricted,
                .conversion = function.policy.conversion,
                .builtin = function.policy.builtin,
                .address = function.policy.c_abi and ast.hasAttribute(self.syntax, function.name, .address),
            },
            .signature = .{
                .constant_arguments = self.instance_keys.items[i].lengths,
                .return_type = self.return_type,
                .parameter_count = function.signature.parameters.len,
                .mutates = function.signature.mut_positions,
                .return_origin = try generic_bodies.declaredBorrow(self.allocator, self.src, self.syntax, self.catalog, function, self.sink),
                // The declared footprint is the `mut` parameter set itself: a
                // written position and a `name: mut T` declaration are the same
                // fact, so there is no separate clause to reconcile.
                .declared_mutates = function.signature.mut_positions,
            },
            .scope = .{
                .body_complete = function.policy.host == null,
                .body = body,
                .locals = try self.locals.toOwnedSlice(self.allocator),
                .parameter_labels = try callables.functionLabels(self.allocator, self.src, function.signature.parameters),
                .own_parameters = try own_parameters.flags(self.allocator, function.signature.parameters),
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
        var result = try self.finishFunction(i, function, body);
        result.scope.body_complete = false;
        return result;
    }
    /// Refuse the retired `-> Result[T, E]` return clause: a fallible function
    /// declares `-> T fails E`, and a call still answers the same checked result.
    /// The fix rewrites the clause and every return in the function.
    fn refuseResultReturn(self: *Checker, function: ast.Function) Error!void {
        // The entry point keeps this spelling: `main() -> Result[T, E]` exits with
        // the error payload, while a fallible `main` exits 1, so the rewrite would
        // change the program's status (F41).
        if (std.mem.eql(u8, self.src.text(function.name), "main")) return;
        if (function.signature.failure_type != null) return;
        const shape = typed.resultShape(self.return_type, self.catalog.records) orelse return;
        const parsed = parseResultClause(self.src.text(function.signature.return_type)) orelse return;
        var edits: std.ArrayList(diagnostic.Edit) = .empty;
        try edits.append(self.allocator, .{ .span = function.signature.return_type, .text = try std.fmt.allocPrint(self.allocator, "{s} fails {s}", .{ parsed.success, parsed.failure }) });
        var uncertain = false;
        for (self.statements.items[self.function_statement_start..]) |checked| {
            const edit = (try self.resultReturnRewrite(checked, shape)) orelse {
                if (checked.data == .ret) uncertain = true;
                continue;
            };
            try edits.append(self.allocator, edit);
        }
        if (edits.items.len == 0) return;
        var item: diagnostic.Diagnostic = .{
            .code = eResultReturnRemoved,
            .span = function.signature.return_type,
            .message = "a function that returns the builtin `Result` declares its failure with `fails`; write `-> T fails E` (a call still answers the same checked result)",
        };
        if (!uncertain) item.provenance.fix = .{ .edit = edits.items[0], .more = edits.items[1..] };
        try self.sink.items.append(self.allocator, item);
        return error.SourceError;
    }
    /// The edit that rewrites one checked return of a `Result`-returning function,
    /// or null when the source shape cannot be rewritten certainly.
    fn resultReturnRewrite(self: *Checker, checked: typed.Statement, shape: typed.ResultShape) Error!?diagnostic.Edit {
        if (checked.data != .ret) return null;
        const statement_text = std.mem.trimStart(u8, self.src.text(checked.span), " \t\r\n");
        if (!std.mem.startsWith(u8, statement_text, "return")) return null;
        const node = self.nodes.items[@backingInt(checked.data.ret)];
        if (node.data != .variant) {
            const value_text = self.src.text(node.span);
            if (std.mem.startsWith(u8, std.mem.trimStart(u8, value_text, " \t\r\n"), "return")) return null;
            return .{ .span = checked.span, .text = try std.fmt.allocPrint(self.allocator, "return try {s}", .{value_text}) };
        }
        const variant = node.data.variant;
        const value = variant.value orelse return null;
        const text = self.src.text(self.nodes.items[@backingInt(value)].span);
        if (variant.tag == shape.ok_tag) return .{ .span = checked.span, .text = try std.fmt.allocPrint(self.allocator, "return {s}", .{text}) };
        if (variant.tag == shape.error_tag) return .{ .span = checked.span, .text = try std.fmt.allocPrint(self.allocator, "fail {s}", .{text}) };
        return null;
    }
    /// Mark the immutable bindings of checked text slices as views. A binding
    /// whose source is immutable cannot be invalidated, so making it a view
    /// changes no value: reads borrow the octets, and every owned use is a copy.
    fn markViewBindings(self: *Checker, first_node: usize, first_statement: usize) Error!void {
        var index = first_statement;
        while (index < self.statements.items.len) : (index += 1) {
            const data = self.statements.items[index].data;
            const store = switch (data) {
                .initialize => |initialize| initialize,
                else => continue,
            };
            if (self.locals.items[@backingInt(store.slot)].ownership.view) continue;
            try self.refuseBufferSliceBinding(store);
            const view = try self.viewBinding(store.slot, store.value) or try self.listViewBinding(store.slot, store.value, first_node);
            if (!view) continue;
            // A deferred `const` or `mut` is a view only when every path stores
            // one; a binding that is a slice on one path and owned on another is
            // owned, and its slice initializations copy at their stores
            // (DECISIONS F3, the review's X2). REFUSAL-R3.
            if (!try self.everyInitializationIsView(store.slot, first_node, first_statement)) continue;
            self.locals.items[@backingInt(store.slot)].ownership.view = true;
        }
    }

    /// Refuse a name bound to a bare slice of a `byte_buffer` (`const piece = buf[1:3]`, `mut part = buf[0:1]`). A buffer can
    /// grow under a borrowed slice and nothing tracks that, so the check reads a bare slice as a borrow of its buffer, which a
    /// name cannot hold; the slice is a new buffer of the range (FR27), so `copy(slice)` names one and `bytes(slice)` the octets.
    /// A compiler temporary is not a name.
    fn refuseBufferSliceBinding(self: *Checker, store: anytype) Error!void {
        const target = self.locals.items[@backingInt(store.slot)];
        if (target.usage.temporary) return;
        const base = self.sliceBase(store.value) orelse return;
        const base_type = self.nodes.items[@backingInt(base)].ty;
        if (!base_type.isAggregate() or !isMutableBytes(self.catalog.records[base_type.recordIndex()])) return;
        const span = self.nodes.items[@backingInt(store.value)].span;
        const message = try std.fmt.allocPrint(self.allocator, "a slice of a `byte_buffer` is a new buffer of that range, and a buffer can grow under a " ++
            "borrowed slice, so the name `{s}` cannot hold it bare; write `copy({s})` for a buffer of the range or `bytes({s})` for its octets", .{ target.name, self.src.text(span), self.src.text(span) });
        return self.sink.fail("E_BUFFER_SLICE_NAME", span, message);
    }

    /// Whether every store into `slot` in this body is a view initializer of
    /// one source: a binding borrows one local, so two paths that slice
    /// different sources are owned and copy (DECISIONS F7).
    fn everyInitializationIsView(self: *Checker, slot: typed.LocalId, first_node: usize, first_statement: usize) Error!bool {
        var root: ?usize = null;
        var index = first_statement;
        while (index < self.statements.items.len) : (index += 1) {
            const data = self.statements.items[index].data;
            const store = switch (data) {
                .initialize => |initialize| initialize,
                else => continue,
            };
            if (store.slot != slot) continue;
            const text_view = try self.viewBinding(store.slot, store.value);
            if (!text_view and !try self.listViewBinding(store.slot, store.value, first_node)) return false;
            // A text slice names its base through the slice operation; a list
            // slice names it through the copy loop's first store.
            const base = if (self.sliceBase(store.value)) |text_base|
                text_base
            else if (self.listSliceParts(store.value)) |parts|
                parts.base
            else
                return false;
            const base_root = self.rootLocal(base, !self.locals.items[@backingInt(slot)].usage.temporary) orelse return false;
            if (root) |seen| {
                if (seen != base_root) return false;
            } else root = base_root;
        }
        return true;
    }

    /// Whether `value` is a list slice bound to a local, which makes the local a
    /// view of the sliced list. A view is only read: a store, a return or an
    /// invalidation of it is the escape rule's (batch W3), and a `copy(value)` of it
    /// lowers to an owned copy (DECISIONS F11).
    fn listViewBinding(self: *Checker, slot: typed.LocalId, value: typed.NodeId, first_node: usize) Error!bool {
        if (!self.nodes.items[@backingInt(value)].view) return false;
        const target = self.locals.items[@backingInt(slot)];
        // A compiler receiver or iteration temporary is mutable but has no
        // source-level writes; a user's view binding is immutable.
        const user_mutable = target.mutable and !target.usage.temporary;
        if (user_mutable or !target.ty.isAggregate()) return false;
        if (self.catalog.records[target.ty.recordIndex()].collection.kind != .list) return false;
        const parts = self.listSliceParts(value) orelse return false;
        const base = parts.base;
        const base_type = self.nodes.items[@backingInt(base)].ty;
        if (!base_type.isAggregate()) return false;
        if (self.catalog.records[base_type.recordIndex()].collection.kind != .list) return false;
        const root = self.rootLocal(base, !target.usage.temporary) orelse return false;
        if (root >= self.locals.items.len) return false;
        // `copy(value)` needs an owned list to allocate, and a view has nothing to
        // copy from, so a binding a `copy(value)` call reads lowers to the copy loop
        // (DECISIONS F11). Everything else about the binding is a view: a store
        // or a return is refused by the escape rule, which is what makes one rule
        // bind whether the slice is bound (W3).
        if (self.listCopied(slot, first_node)) return false;
        // A slice of a list view binding is a view of the same elements (zero-copy part 1, F-RC-103), as for text.
        // A mutable source is allowed: the ownership checker refuses a write that
        // would invalidate the view, with the copy repair, exactly as for text
        // (wave 2's W3/W4, DECISIONS D31 by analogy).
        return true;
    }

    /// Whether the checked binding `slot` is the receiver of a `copy(value)` call,
    /// whose result must be an owned list rather than a view of one.
    fn listCopied(self: *Checker, slot: typed.LocalId, first_node: usize) bool {
        if (first_node >= self.nodes.items.len) return false;
        for (self.nodes.items[first_node..]) |node| switch (node.data) {
            .buffer_operation => |operation| if (@backingInt(operation.owner) == @backingInt(slot) and operation.kind == .copy) return true,
            else => {},
        };
        return false;
    }

    /// The source and clamped endpoints of the append loop a checked list slice
    /// lowers to (`collection_lower.Builder.slice`): the block initializes the
    /// source, the two endpoints, the fresh output, then runs the copy loop.
    fn listSliceParts(self: *Checker, value: typed.NodeId) ?struct { base: typed.NodeId, start: typed.NodeId, end: typed.NodeId } {
        const node = self.nodes.items[@backingInt(value)];
        if (!node.view or node.data != .block_value) return null;
        const body = self.statements.items[@backingInt(node.data.block_value.body)].data;
        const children = switch (body) {
            .block => |children| children,
            else => return null,
        };
        if (children.len < 5) return null;
        const first_child = self.statements.items[@backingInt(children[0])].data;
        const second_child = self.statements.items[@backingInt(children[1])].data;
        const third_child = self.statements.items[@backingInt(children[2])].data;
        const fourth_child = self.statements.items[@backingInt(children[3])].data;
        const fifth_child = self.statements.items[@backingInt(children[4])].data;
        if (fifth_child != .loop) return null;
        if (fourth_child != .initialize) return null;
        if (self.nodes.items[@backingInt(fourth_child.initialize.value)].data != .acquire_buffer) return null;
        const source_store = switch (first_child) {
            .initialize => |store| store,
            else => return null,
        };
        const first_store = switch (second_child) {
            .initialize => |store| store,
            else => return null,
        };
        const last_store = switch (third_child) {
            .initialize => |store| store,
            else => return null,
        };
        return .{ .base = source_store.value, .start = first_store.value, .end = last_store.value };
    }

    /// Whether `value` is a checked text slice of an immutable local, bound to an
    /// Whether `value` is a checked text or byte slice of a local, bound to an
    /// immutable local: the exact shape the builder can hold as a `str_view`.
    fn viewBinding(self: *Checker, slot: typed.LocalId, value: typed.NodeId) Error!bool {
        const target = self.locals.items[@backingInt(slot)];
        if (target.mutable or !target.ty.isAggregate()) return false;
        const target_kind = self.catalog.records[target.ty.recordIndex()].collection.kind;
        if (target_kind != .string and target_kind != .bytes) return false;
        const base = self.sliceBase(value) orelse return false;
        const base_type = self.nodes.items[@backingInt(base)].ty;
        if (!base_type.isAggregate()) return false;
        const base_kind = self.catalog.records[base_type.recordIndex()].collection.kind;
        if (base_kind != .string and base_kind != .bytes) return false;
        // A text slice and a byte slice are the same view representation, but a
        // binding cannot change family.
        if (base_kind != target_kind) return false;
        // A byte buffer has no borrowed slice: it can grow under one, and nothing tracks that. Its slice is the copy of that
        // range (`build_text.bufferSliceCopy`), so the binding owns bytes of its own (FR26).
        if (isMutableBytes(self.catalog.records[base_type.recordIndex()])) return false;
        const root = self.rootLocal(base, !target.usage.temporary) orelse return false;
        if (root >= self.locals.items.len) return false;
        // The record a fresh constructor's or call's field slice is rooted in (`collection_lower.freshFieldReceiver`) is a hidden
        // temporary that lives for the statement: a binding of the slice would outlive it, so it is owned and the store is refused.
        if (self.hiddenRecord(value, root)) return false;
        // A slice of a view binding is a view of the same octets (zero-copy part 1, F-RA-300): the new core slices a view in
        // place (`myl_core_view_slice`), so D30's copy is gone. A mutable source is allowed: the ownership checker refuses
        // a write that would invalidate the view, with the copy repair (DECISIONS D31).
        return true;
    }

    /// Whether local `slot` is the hidden owner of a fresh whole record (not a text, bytes or list) that the slice expression
    /// `value` makes for itself, so that the record's field is read within one statement: the slice's own block initializes
    /// it. A loop's element or a pattern's binding is a compiler local too, but it is initialized before the statement and
    /// stays a view root (FX14).
    fn hiddenRecord(self: *Checker, value: typed.NodeId, slot: usize) bool {
        const local = self.locals.items[slot];
        if (!local.usage.temporary or !local.ty.isAggregate()) return false;
        if (self.catalog.records[local.ty.recordIndex()].isCollection()) return false;
        const node = self.nodes.items[@backingInt(value)];
        if (node.data != .block_value) return false;
        const children = switch (self.statements.items[@backingInt(node.data.block_value.body)].data) {
            .block => |children| children,
            else => return false,
        };
        for (children) |child| switch (self.statements.items[@backingInt(child)].data) {
            .initialize => |initialize| if (@backingInt(initialize.slot) == slot) return true,
            else => {},
        };
        return false;
    }

    /// The local a checked slice expression borrows: the base the operation's
    /// block initializes its owner from.
    fn sliceBase(self: *Checker, value: typed.NodeId) ?typed.NodeId {
        const node = self.nodes.items[@backingInt(value)];
        if (node.data != .block_value) return null;
        const inner = self.nodes.items[@backingInt(node.data.block_value.value)];
        if (inner.data != .buffer_operation or !inner.view) return null;
        const owner = @backingInt(inner.data.buffer_operation.owner);
        const body = self.statements.items[@backingInt(node.data.block_value.body)];
        const children = switch (body.data) {
            .block => |children| children,
            else => return null,
        };
        for (children) |child| {
            const data = self.statements.items[@backingInt(child)].data;
            const initialize = switch (data) {
                .initialize => |initialize| initialize,
                else => continue,
            };
            if (@backingInt(initialize.slot) != owner) continue;
            return initialize.value;
        }
        return null;
    }

    /// The local a path of fields and indexes starts at, so a slice of
    /// `request.body` borrows from whatever holds `request`. With `elements`, a read of a list's element
    /// (`names[0]`, `rows[i].tags[1]`) is a step of the path as an indexed read of a dictionary is (FR69): the slice
    /// of an element is a view of the list's storage, as the slice of the borrowed name `const line = names[0]` is.
    fn rootLocal(self: *Checker, start: typed.NodeId, elements: bool) ?usize {
        var current = start;
        var reads: [16]typed.NodeId = undefined;
        var count: usize = 0;
        var depth: usize = 0;
        while (depth < 16) : (depth += 1) {
            const node = self.nodes.items[@backingInt(current)];
            switch (node.data) {
                .local => |slot| {
                    // A list read of a fresh record's field (`rows().lines[0]`) roots the record in a temporary of the read's block
                    // that lives for the statement: a binding of its slice would outlive it.
                    for (reads[0..count]) |read| if (self.hiddenRecord(read, @backingInt(slot))) return null;
                    return @backingInt(slot);
                },
                .field => |field| current = field.base,
                .index => |index| current = index.base,
                .block_value => |block| {
                    const list = if (elements) self.listElementSource(block.body, block.value) else null;
                    if (list != null) {
                        reads[count] = current;
                        count += 1;
                    }
                    current = list orelse block.value;
                },
                else => return null,
            }
        }
        return null;
    }

    /// The list a list element read (`xs[i]`) takes its element from: the block `collection_lower.Builder.access` makes
    /// roots the list in a temporary, and its value reads that temporary at the index. Null when the block is not one.
    fn listElementSource(self: *Checker, body: typed.StatementId, value: typed.NodeId) ?typed.NodeId {
        const read = self.nodes.items[@backingInt(value)].data;
        if (read != .buffer_operation or read.buffer_operation.kind != .read) return null;
        const owner = read.buffer_operation.owner;
        const owner_type = self.locals.items[@backingInt(owner)].ty;
        if (!owner_type.isAggregate() or self.catalog.records[owner_type.recordIndex()].collection.kind != .list) return null;
        const children = switch (self.statements.items[@backingInt(body)].data) {
            .block => |children| children,
            else => return null,
        };
        for (children) |child| switch (self.statements.items[@backingInt(child)].data) {
            .initialize => |initialize| if (initialize.slot == owner) return initialize.value,
            else => {},
        };
        return null;
    }

    /// `bytes.parse_float(data)` in a file that does not import `bytes`: the qualifier names a builtin type that is not a
    /// domain, and a standard module of the same name declares the function. The repair is the import (W13-S5), as for
    /// any other standard module (`type_catalog.resolve`, `interfaces.unimportedModule`).
    fn refuseUnimportedTypeModule(self: *Checker, owner_type: typed.Type, owner: source.Span) Error!void {
        const import_fix = @import("import_fix.zig");
        if (owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].shape.domain != null) return;
        const name = self.src.text(owner);
        if (!import_fix.standardModule(name)) return;
        const message = try import_fix.unimportedMessage(self.allocator, name);
        if (try import_fix.moduleEdit(self.allocator, self.src, owner, name)) |edit| return self.sink.failFix(import_fix.code, owner, message, edit);
        return self.sink.fail(import_fix.code, owner, message);
    }
    fn checkFunction(self: *Checker, i: usize) Error!typed.Function {
        // Loop targets belong to one body, including synthesized loops. Keeping
        // their numbering local makes fresh and retained bodies identical even
        // when preceding bodies were skipped or acquired another loop. CoreIR
        // inlining separately assigns IDs in the caller when it moves loops.
        std.debug.assert(self.loops.active.items.len == 0);
        self.loops.next = 0;
        self.checked_index = i;
        if (i >= self.lambda_start and i < self.lambda_start + self.syntax.lambdas.len)
            return self.checkLambdaFunction(i - self.lambda_start);
        const allocator = self.allocator;
        const src = self.src;
        const sink = self.sink;
        self.current_function = @fromBackingInt(i);
        self.current_lambda = null;
        const function = self.syntaxFunction(@fromBackingInt(i));
        // A body of a program read lazily is filled before it is walked.
        try ast.ensureBody(self.syntax, function.body);
        self.recovery.reset();
        const first_node = self.nodes.items.len;
        const first_statement = self.statements.items.len;
        const constant_context: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        const declaration = @backingInt(self.instance_keys.items[i].declaration);
        const constant = if (function.policy.constant and try constant_context.literalType(declaration) == null) try constant_context.evaluate(declaration) else null;
        // A text constant joined from literals and constants holds the one literal they fold to (F-54).
        const folded_text = if (function.policy.constant and constant == null) try constant_context.foldedText(declaration) else null;
        defer if (folded_text) |octets| sink.allocator.free(octets);
        try self.beginFunction(i, function);
        try @import("sema_supplied.zig").requireSupplier(src, function, sink);
        try self.sealedTestInputs(function);
        if (function.policy.c_abi) {
            const foreign = @import("c_abi.zig");
            if (self.locals.items.len == 0 or self.locals.items[0].ty != .host_cap) return sink.fail("E_HOST_CAPABILITY", function.name, "an extern or host declaration must take `host: Host` as its first parameter");
            try externSignature(self, function);
            if (ast.hasAttribute(self.syntax, function.name, .address)) try addressTarget(self, function);
            if (!foreign.validSymbol(src.text(function.name))) return sink.fail("E_EXTERN_SYMBOL", function.name, "extern names must be C identifiers outside the reserved myl_/mylang_ runtime namespaces"); // rename: keep
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
        // Only a home's body is checked: its call of itself is the operation, which a function value runs. Every
        // other `builtin func` keeps an empty body, which nothing runs (W10).
        var body = if (@import("sema_supplied.zig").bodiless(src, function)) bodiless: {
            const empty: typed.StatementId = @fromBackingInt(self.statements.items.len);
            try self.statements.append(allocator, .{ .span = function.name, .terminates = true, .data = .{ .block = &.{} } });
            break :bodiless @TypeOf(try self.statement(function.body)){ .id = empty, .terminates = true };
        } else if (folded_text) |octets| folded: {
            const initializer = constant_context.initializerNode(declaration);
            const span = self.syntax.nodes.items[@backingInt(initializer)].span;
            const node_id = try self.foldedTextNode(span, octets, try constant_context.declaredType(declaration));
            const statement_id: typed.StatementId = @fromBackingInt(self.statements.items.len);
            try self.statements.append(allocator, .{ .span = function.name, .terminates = true, .data = .{ .ret = node_id } });
            break :folded @TypeOf(try self.statement(function.body)){ .id = statement_id, .terminates = true };
        } else try self.statement(function.body);
        if (constant) |value| {
            const folded = try self.constantNode(value, function.name);
            const node_id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
            try self.nodes.append(allocator, folded);
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
        try self.markViewBindings(first_node, first_statement);
        // A generic `builtin func` has an empty body: every call is its operation and nothing runs the body (W10).
        if (function.policy.builtin and !body.terminates) {
            body.terminates = true;
            self.statements.items[@backingInt(body.id)].terminates = true;
        }
        const implicit_unit = self.success_type == .unit;
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
        try sealed_rules.checkBody(Checker, self, first_node);
        try self.enforceInvariants(first_node, first_statement);
        try self.refuseResultReturn(function);
        return self.finishFunction(i, function, body.id);
    }
    /// Rule 12 of `@sealed` (W11): a test the runner calls with inputs takes no sealed record of another module.
    fn sealedTestInputs(self: *Checker, function: ast.Function) Error!void {
        if (!sealed_rules.isTest(self.syntax, self.src, self.catalog.module_names, function)) return;
        const parameters = function.signature.parameters;
        if (self.locals.items.len < parameters.len) return;
        const types = try self.allocator.alloc(typed.Type, parameters.len);
        defer self.allocator.free(types);
        const spans = try self.allocator.alloc(source.Span, parameters.len);
        defer self.allocator.free(spans);
        for (parameters, self.locals.items[0..parameters.len], types, spans) |parameter, local, *slot_type, *span| {
            slot_type.* = local.ty;
            span.* = parameter.ty;
        }
        try sealed_rules.checkTestInputs(sealed_rules.contextOf(Checker, self), self.allocator, self.sink, types, spans);
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
            if (self.inGenericBody(lambda.span)) return self.sink.fail("E_LAMBDA_REMOVED", lambda.span, generic_bodies.lambda_in_generic_body);
            return self.sink.fail("E_LAMBDA_REMOVED", lambda.span, "lambdas were removed; declare a named top-level function with explicit parameter and result types");
        };
        if (lambda_type == uninferred_lambda) return error.SourceError;
        const contract = callables.signature(lambda_type, self.catalog.records) orelse return error.InternalError;
        self.current_function = null;
        self.current_lambda = index;
        self.contract.ensures = &.{};
        self.contract.olds = &.{};
        for (self.resolved_nodes.items) |node| self.resolved.put(node, null);
        self.resolved_nodes.clearRetainingCapacity();
        self.expected_types.clearRetainingCapacity();
        self.option_facts.clear();
        self.locals = .empty;
        self.consuming_bindings.clearRetainingCapacity();
        self.match_lent_owners.clearRetainingCapacity();
        self.function_statement_start = self.statements.items.len;
        self.active.clearRetainingCapacity();
        self.owner = null;
        self.return_type = contract.return_type;
        self.success_type = contract.return_type;
        self.failure_type = null;
        for (lambda.parameters, contract.parameters) |parameter, parameter_type| {
            const name = self.src.text(parameter);
            if (self.active.contains(name)) return self.sink.fail("E_DUPLICATE_PARAMETER", parameter, "lambda parameter name is already declared");
            const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
            try self.locals.append(self.allocator, .{
                .name = name,
                .declaration = parameter,
                .ty = parameter_type,
                .mutable = std.mem.indexOfScalar(u16, contract.mutates, @intCast(@backingInt(slot))) != null,
                .ownership = .{ .initialized = true, .transfer_available = self.transfers(parameter_type) },
            });
            try self.active.put(self.allocator, name, slot);
        }
        const value = try self.expressionExpected(lambda.body, contract.return_type);
        try self.require(self.nodes.items[@backingInt(value)].ty, contract.return_type, self.syntax.nodes.items[@backingInt(lambda.body)].span);
        try self.requireHandled(0, lambda.span);
        // Recognition and body checking exist only to establish a certain repair.
        // Removed lambdas never become executable typed functions.
        return @import("lambda_migration.zig").reject(self.allocator, .{ .src = self.src, .syntax = self.syntax, .names = self.catalog.module_names, .records = self.catalog.records, .sink = self.sink }, lambda, contract);
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
    /// Refuse a qualified name whose first segment is a local in force. The parser reads such a name as the field
    /// chain of the local (`local_qualifiers.zig`), so one that gets here uses a binding form that pass does not follow;
    /// reading it as the module path would silently use a declaration the local hides.
    pub fn refuseHiddenPath(self: *Checker, name: source.Span) Error!void {
        const text = self.src.text(name);
        const dot = std.mem.indexOfScalar(u8, text, '.') orelse return;
        if (!self.active.contains(text[0..dot])) return;
        const message = try std.fmt.allocPrint(self.allocator, "`{s}` is a local here, so `{s}` does not name a module path; rename the local, or reach the module through its import alias", .{ text[0..dot], text });
        return self.sink.fail(eShadowing, name, message);
    }
    /// Refuse binding `name` as `form` ("parameter", "binding", "payload binding", "iteration binding" and the
    /// others) where it would hide an active local or a module-level name, saying which kind of thing that is and
    /// pointing at its declaration (F-10). The caller has found that one of them is in force.
    pub fn refuseShadowing(self: *Checker, name: source.Span, form: []const u8) Error {
        const text = self.src.text(name);
        if (self.active.get(text)) |slot| {
            const local = self.locals.items[@backingInt(slot)];
            const kind = if (local.origin == .parameter) "the parameter" else "the local";
            return self.shadowingRefusal(name, form, kind, local.declaration);
        }
        if (self.current_function) |id| {
            for (self.syntaxFunction(id).signature.type_parameters) |parameter| {
                if (parameter.constant_length and std.mem.eql(u8, self.src.text(parameter.name), text))
                    return self.shadowingRefusal(name, form, "the length parameter", parameter.name);
            }
        }
        if (self.catalog.module_names) |names| if (try names.declarationOf(name)) |found| {
            const constant = if (found.at) |at| self.constantAt(at) else false;
            return self.shadowingRefusal(name, form, names_module.shadowedKind(found.kind, constant), found.at);
        };
        // A program without a module graph has no interface index: its own declarations say what the name is.
        for (self.syntax.functions) |function| {
            if (function.policy.owner != null or !std.mem.eql(u8, self.src.text(function.name), text)) continue;
            return self.shadowingRefusal(name, form, if (function.policy.constant) "the module constant" else "the function", function.name);
        }
        if (self.catalog.names.get(text)) |declared| {
            const at = if (declared.isAggregate()) self.catalog.records[declared.recordIndex()].declaration else null;
            return self.shadowingRefusal(name, form, "the type", at);
        }
        if (self.functions.contains(text)) return self.shadowingRefusal(name, form, "the function", null);
        if (self.catalog.templates.names.contains(text)) return self.shadowingRefusal(name, form, "the type", null);
        return self.shadowingRefusal(name, form, "a module-level name", null);
    }
    /// Whether the declaration whose name is at `at` is a module constant, which the interface index lists as a
    /// function: a constant of that name declared in the same module.
    fn constantAt(self: *Checker, at: source.Span) bool {
        const module = (self.src.originalSpan(at) catch return false).input;
        const text = self.src.text(at);
        for (self.syntax.functions) |function| {
            if (!function.policy.constant or !std.mem.eql(u8, self.src.text(function.name), text)) continue;
            const declared = self.src.originalSpan(function.name) catch continue;
            if (declared.input == module) return true;
        }
        return false;
    }
    /// Report `form` `name` hiding `kind` `name`, with a note at the hidden declaration when its span is known.
    fn shadowingRefusal(self: *Checker, name: source.Span, form: []const u8, kind: []const u8, at: ?source.Span) Error {
        const message = try names_module.shadowingMessage(self.allocator, form, self.src.text(name), kind);
        const declared = if (std.mem.eql(u8, kind, "the imported module")) "imported here" else "declared here";
        if (at) |span| return self.sink.failRelated(eShadowing, name, message, .{ .span = span, .message = declared });
        return self.sink.fail(eShadowing, name, message);
    }
    /// Whether binding `name` in a new scope would hide an active local or a
    /// top-level declaration. `_` is the discard name: it may be bound again in a
    /// nested loop, so it never shadows anything (`DISCARD-NAME-1`).
    pub fn shadows(self: *Checker, name: source.Span) error{InternalError}!bool {
        const text = self.src.text(name);
        if (std.mem.eql(u8, text, "_")) return false;
        const top_level = try self.topLevel(name);
        return top_level or self.active.contains(text);
    }
    /// Bind `slot` under `text` for the rest of a scope. Only `_` can hide an
    /// earlier binding (`DISCARD-NAME-1`); that binding is returned so
    /// `unbindScoped` can hand it back when the scope ends.
    pub fn bindScoped(self: *Checker, text: []const u8, slot: typed.LocalId) Error!?typed.LocalId {
        const hidden = self.active.get(text);
        try self.active.put(self.allocator, text, slot);
        return hidden;
    }
    /// End a `bindScoped` binding, restoring the one it hid, if any.
    pub fn unbindScoped(self: *Checker, text: []const u8, hidden: ?typed.LocalId) void {
        if (hidden) |slot| {
            self.active.getPtr(text).?.* = slot;
        } else _ = self.active.remove(text);
    }
    /// The typed literal a joined `str` or `bytes` constant of type `declared` folds to (F-54): the node its literal
    /// would check to, at `span`.
    pub fn foldedTextNode(self: *Checker, span: source.Span, octets: []const u8, declared: typed.Type) Error!typed.NodeId {
        const text = self.catalog.records[declared.recordIndex()].collection.kind == .string;
        const spelled: ast.Node = .{ .span = span, .data = if (text) .{ .text = octets } else .{ .bytes = octets } };
        var out: typed.Node = .{ .span = span, .ty = .unit, .data = .unit };
        try self.checkTextLiteral(spelled, octets, &out);
        const node_id: typed.NodeId = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, out);
        return node_id;
    }
    /// The typed literal a folded scalar constant becomes at `span`: an integer or Boolean
    /// node, or for a `float` the same wrapped bit pattern a float literal checks to.
    pub fn constantNode(self: *Checker, value: typed.Value, span: source.Span) Error!typed.Node {
        if (numeric_surface.isBinaryFloat(value.typeOf(), self.catalog.records)) return self.numericBuilderFor(span, value.typeOf()).constant(@intCast(value.integer.value));
        return .{ .span = span, .ty = value.typeOf(), .data = if (value == .bool) .{ .boolean = value.bool } else .{ .integer = if (value == .i64) value.i64 else value.integer.value } };
    }
    /// Resolve a spelled type in the current function's generic scope, or at top level.
    pub fn ty(self: *Checker, span: source.Span) Error!typed.Type {
        const resolved = if (self.current_function) |id| try self.functionType(id, span) else try self.catalog.resolve(self.src, span, self.sink);
        try self.refuseMoveOnlyFunctionPositions(resolved, span);
        return resolved;
    }
    /// T: a function type's plain position takes its argument, so a move-only
    /// type there must be spelled `own`. A function type that came from source
    /// is refused position by position, in the type's own spelling.
    fn refuseMoveOnlyFunctionPositions(self: *Checker, value_type: typed.Type, span: source.Span) Error!void {
        const syntax = own_parameters.syntaxAt(self.syntax.types.expressions.callbacks, span) orelse return;
        const type_parameters = if (self.current_function) |id| self.syntaxFunction(id).signature.type_parameters else &.{};
        try own_parameters.refuseFunctionType(self.allocator, self.sink, .{ .src = self.src, .records = self.catalog.records, .type_parameters = type_parameters }, value_type, syntax);
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
    /// The declaration name of a syntactic function, made from its module and its text.
    fn declarationName(self: *Checker, function: ast.Function) Error![]const u8 {
        if (self.catalog.module_names) |module| return module.functionDeclaration(function.policy.owner, function.name);
        return functionName(self.allocator, self.src, function.policy.owner, function.name);
    }
    fn instanceName(self: *Checker, id: typed.FunctionId) Error![]const u8 {
        const function = self.syntaxFunction(id);
        const declaration = @backingInt(self.instance_keys.items[@backingInt(id)].declaration);
        const base = if (declaration < self.declared_names.len) self.declared_names[declaration] else try self.declarationName(function);
        // A Debug compiler makes the name again and holds it to the one the registration made.
        if (builtin.mode == .debug and declaration < self.declared_names.len) std.debug.assert(std.mem.eql(u8, base, try self.declarationName(function)));
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
    pub const bindOrdinaryReferences = specialization_checks.bindOrdinaryReferences;
    pub const publishSpecializations = specialization_checks.publishSpecializations;
    pub const specialize = specialization_checks.specialize;
    pub const probeTemplates = specialization_checks.probeTemplates;
    /// Whether a value of this type carries a pending Result obligation.
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
    /// Require Result obligations to match a checkpoint on every continuing path.
    /// Core alone checks availability joins and loops for other managed values.
    pub fn samePending(self: *Checker, state: []const Pending, span: source.Span, code: []const u8) Error!void {
        for (self.locals.items[0..state.len], state) |local, pending| if (typed.linear(local.ty, self.catalog.records) and local.ownership.transfer_available != pending.available)
            return @import("linear_rules.zig").refuse(self.sink, span, if (std.mem.eql(u8, code, diagnostic.result_loop)) .loop else .paths);
        for (self.locals.items[0..state.len], state) |local, pending| if (self.requiresHandling(local.ty) and local.ownership.transfer_available != pending.available) return self.sink.failOwnershipRelated(
            .{ .code = code, .rule = .L1 },
            span,
            "result obligation must have the same state on every continuing path",
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
        return self.requireHandledAt(first, span, .scope);
    }
    /// `requireHandled` for a path that leaves at `exit`: a `try` that propagates names the `on fail:` clause that ends a live `@linear` owner.
    pub fn requireHandledAt(self: *Checker, first: usize, span: source.Span, exit: @import("linear_rules.zig").Exit) Error!void {
        for (self.locals.items[first..], first..) |local, index| {
            // Remaining mut-list elements return to the caller; overwrite checks
            // still use pendingObligation and require explicit acknowledgement.
            const caller_writeback = local.origin == .parameter and local.mutable and !local.ownership.owned_parameter and @import("record_layouts.zig").pendingList(self.catalog.records, local.ty);
            // A `mut` parameter of a `@linear` type is the caller's owner, lent; the callee owes nothing for it.
            const lent_linear = local.origin == .parameter and local.mutable and !local.ownership.owned_parameter and typed.linear(local.ty, self.catalog.records);
            if (lent_linear) continue;
            // A plain parameter of a `@linear` type is a read-only loan of the caller's owner (decision LINEAR-LEND).
            if (@import("linear_rules.zig").loan(local) and typed.linear(local.ty, self.catalog.records)) continue;
            if (self.pendingObligation(local) and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index)) and typed.linear(local.ty, self.catalog.records))
                return @import("linear_rules.zig").unconsumed(self.sink, self.allocator, .{ .name = local.name, .declaration = local.declaration, .end = span, .lent_at = self.match_lent_owners.get(@fromBackingInt(index)), .exit = exit });
            if (!caller_writeback and self.pendingObligation(local) and self.active.get(local.name) == @as(typed.LocalId, @fromBackingInt(index)))
                return self.sink.failResultUnhandled(local.name, local.declaration, span);
        }
    }
    /// The standard `parallel.map` of a fallible callback has the type `R[] fails E`, so when the call is the
    /// operand of `try` it routes to `map_fallible`. Any other such call keeps the old `Result[R, E][]` meaning
    /// only as `parallel.map_results`; the bare spelling is refused with a fix that renames it, which keeps that
    /// meaning exactly (E_PARALLEL_MAP_FALLIBLE).
    fn mapFallibleName(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span, name: []const u8) Error![]const u8 {
        if (std.mem.eql(u8, name, "parallel::map") and call.arguments.len > 2) return self.mapWithArgumentsName(call);
        if (!std.mem.eql(u8, name, "parallel::map") or call.arguments.len != 2) return name;
        if (!self.mapCallbackFallible(call)) return name;
        if (try self.propagated(span)) return "parallel::map_fallible";
        // The name's own text (`parallel.map`, qualifier included) gains `_results`, so the repair keeps the spelling.
        const renamed = try std.fmt.allocPrint(self.allocator, "{s}_results", .{self.src.text(call.name)});
        return self.sink.failFix(
            eParallelMapFallible,
            call.name,
            "parallel.map with a fallible function returns R[] fails E, so write `try parallel.map(...)`; for the list of results, write parallel.map_results(...)",
            .{ .span = call.name, .text = renamed },
        );
    }
    /// Whether the callback argument of a call has a fallible function type (its return is a result).
    /// `parallel.map(values, fn, ARGS)` (E1b): the trailing arguments name the variant `map_with<N>` of their count, which
    /// takes the same items and the arguments, each read-only and the same for every item. A `mut` argument is E_TASK_MUT;
    /// an `own` argument, more than five, and a fallible function are refused (E_PARALLEL_MAP_ARGS).
    fn mapWithArgumentsName(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error![]const u8 {
        for (call.arguments[2..]) |argument| {
            const node = self.syntax.nodes.items[@backingInt(argument)];
            if (node.data == .mut_argument) return self.sink.failOwnership(
                .{ .code = eTaskMut, .rule = .K3 },
                node.span,
                "a `mut` argument cannot go to parallel.map: its function borrows every argument read-only; pass the value plainly",
            );
            if (node.data == .own_argument) return self.sink.failOwnership(.{ .code = eParallelMapArgs, .rule = .K3 }, node.span, "an `own` argument cannot go to parallel.map: pass the value plainly, as its arguments are read-only");
        }
        if (call.arguments.len - 2 > 5) return self.sink.failOwnership(.{ .code = eParallelMapArgs, .rule = .K3 }, call.name, "parallel.map takes at most five trailing arguments");
        if (self.mapCallbackFallible(call) or self.mapCallbackFails(call)) return self.sink.failOwnership(
            .{ .code = eParallelMapArgs, .rule = .K3 },
            call.name,
            "parallel.map with trailing arguments needs a function that does not fail; write the fallible form without them",
        );
        return std.fmt.allocPrint(self.allocator, "parallel::map_with{d}", .{call.arguments.len - 2});
    }
    /// Whether the callback named as the call's second argument is declared `fails` (E1b). The name is read from the syntax,
    /// because the argument's type is not checked yet when the call's name is chosen.
    fn mapCallbackFails(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
        const node = self.syntax.nodes.items[@backingInt(call.arguments[1])];
        if (node.data != .name) return false;
        const wanted = self.src.text(node.span);
        for (self.syntax.functions) |function| {
            if (function.signature.failure_type == null) continue;
            if (std.mem.eql(u8, self.src.text(function.name), wanted)) return true;
        }
        return false;
    }
    fn mapCallbackFallible(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
        const value = self.resolved.at(@backingInt(call.arguments[1])) orelse return false;
        const value_ty = self.nodes.items[@backingInt(value)].ty;
        if (!value_ty.isAggregate()) return false;
        const callback = self.catalog.records[value_ty.recordIndex()].contract.callback orelse return false;
        return typed.resultShape(callback.return_type, self.catalog.records) != null;
    }
    /// Whether the call at `span` is the operand of a `try`, which the parser records as a propagation node.
    fn propagated(self: *Checker, span: source.Span) Error!bool {
        // The propagation and its operand lie in the function body the call does (in a program whose bodies are filled on demand: that body,
        // filled), so only that body's nodes are read; a program of one module or with no loader reads the module's.
        const around = try ast.scanAt(self.syntax, span.start);
        const found = Checker.propagates(self.syntax, self.syntax.nodes.items[around.node_start..around.node_end], span);
        if (compile_mode == .debug and self.syntax.facts.loader == null) std.debug.assert(found == Checker.propagates(self.syntax, self.syntax.nodes.items, span));
        return found;
    }
    /// Whether one of `nodes` is a `try` whose operand has exactly `span`.
    fn propagates(program: ast.Program, nodes: []const ast.Node, span: source.Span) bool {
        for (nodes) |node| switch (node.data) {
            .propagate => |operand| {
                const operand_span = program.nodes.items[@backingInt(operand)].span;
                if (operand_span.start == span.start and operand_span.end == span.end) return true;
            },
            else => {},
        };
        return false;
    }
    const ResolvedCall = struct { declaration: instances.DeclarationId, call: @FieldType(@FieldType(ast.Node, "data"), "call") };
    /// Whether one in-scope local may appear in a hole snapshot as a usable
    /// input: initialized, not consumed, not synthetic.
    fn holeUsable(self: *Checker, local: typed.Local) bool {
        if (!local.ownership.initialized) return false;
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
            .mutation = try diagnostic.mutationFact(self.allocator, self.src, function),
        };
    }
    /// The bounded facts this checker can see at a typed hole. The candidate and
    /// requirement lists live in the checker's own allocator, so they outlive
    /// this call and are released with the rest of the check.
    fn holeFindings(self: *Checker, call_span: source.Span, candidates: []const diagnostic.Candidate, requirements: []const diagnostic.Requirement) Error!diagnostic.Findings {
        return .{ .function = self.holeFunction(), .expected = try self.holeExpected(call_span), .candidates = candidates, .requirements = requirements, .contract = try self.holeContract() };
    }
    /// The declared type of a `todo[T]()` hole that trap mode checks as an expression, or null for any
    /// other call. Refused holes keep `callDeclaration`'s diagnostic, so only trap mode answers here.
    pub fn trapHoleType(self: *Checker, raw: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Type {
        if (self.sink.hole_mode == .refuse) return null;
        const applied = try @import("call_type_arguments.zig").split(self.src, self.syntax, self.catalog.module_names, raw, self.sink);
        const input = applied orelse raw;
        if (input.owner != null or input.type_arguments.len != 1) return null;
        if (!std.mem.eql(u8, self.src.text(input.name), "todo")) return null;
        self.sink.trapped_holes += 1;
        const declared = try self.ty(input.type_arguments[0]);
        return declared;
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
    /// Resolve a call's callee: a `todo(T)` hole or a declared
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
        const call = input;
        if (call.owner == null) try self.refuseHiddenPath(call.name);
        if (call.owner) |owner_span| if (self.active.get(self.src.text(owner_span))) |slot| {
            const owner_type = self.locals.items[@backingInt(slot)].ty;
            const field_name = self.src.text(call.name);
            if (self.callableField(owner_type, field_name) != null)
                return self.sink.fail(eCollectionMethod, call.name, try self.functionFieldMessage(owner_type, field_name));
            // A local is a value, never a type or a module, and a value has no methods: name the function form.
            const answer = try self.valueReceiverAnswer(owner_type, call, span);
            return self.sink.failRepaired("E_UNKNOWN_TYPE", owner_span, answer.message, answer.fix);
        };
        const owner = if (call.owner) |name| try self.qualifierType(name) else null;
        if (owner) |domain_type| {
            try self.refuseUnimportedTypeModule(domain_type, call.owner.?);
            _ = try self.catalog.domain(domain_type, call.owner.?, self.sink);
        }
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
        const function_name = try self.mapFallibleName(call, span, name);
        const function = self.functions.get(function_name) orelse {
            // An unreserved word keeps its migration: a call of a spelling the
            // language removed reports that, with its certain edit unless the
            // edit would capture a name this file declares (F7, F8).
            const spelling = self.src.text(call.name);
            const withheld = if (removed_names.replacement(spelling)) |fix| try lexer.claimsName(self.allocator, self.src.bytes, fix) else false;
            if (try removed_names.rejectUnless(self.sink, call.name, spelling, withheld)) return error.SourceError;
            // `Unit()` is a constructor call of the builtin type, which has none: name its one value rather than
            // a function whose spelling is near (F-41).
            if (call.owner == null and std.mem.eql(u8, spelling, "Unit")) return self.sink.fail("E_UNKNOWN_FUNCTION", call.name, unit_call_message);
            const clause = try typed.suggestionClause(self.allocator, &self.functions, spelling);
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
    /// The type a call's qualifier names. A qualifier that is no local, type or imported module is told it is not a name in scope,
    /// with the close names that are (FR34), where the type lookup alone says only that a type is not declared.
    fn qualifierType(self: *Checker, name: source.Span) Error!typed.Type {
        const first = self.sink.items.items.len;
        const resolved = self.ty(name);
        if (resolved) |_| {} else |_| if (self.sink.items.items.len == first + 1) try self.explainUnknownQualifier(&self.sink.items.items[first], name);
        return resolved;
    }
    /// Rewrite `refusal`, the "type is not declared" of the qualifier at `name`, as the message for a name that is nothing at all.
    fn explainUnknownQualifier(self: *Checker, refusal: *diagnostic.Diagnostic, name: source.Span) Error!void {
        const undeclared = std.mem.eql(u8, refusal.code, "E_UNKNOWN_TYPE") and std.mem.eql(u8, refusal.message, "type is not declared");
        if (!undeclared or refusal.span.start != name.start) return;
        var scope: std.StringHashMapUnmanaged(void) = .empty;
        defer scope.deinit(self.allocator);
        var locals = self.active.keyIterator();
        while (locals.next()) |key| try scope.put(self.allocator, key.*, {});
        var types = self.catalog.names.keyIterator();
        while (types.next()) |key| try scope.put(self.allocator, key.*, {});
        const text = self.src.text(name);
        refusal.message = try unknown_qualifier.message(self.allocator, text, try typed.suggestionClause(self.allocator, &scope, text));
    }
    /// The answer for `value.name(arguments)` where `value` is a local: a value has no methods, so the call is the function
    /// `name(value, arguments)`, as in `norm(p)` for `p.norm()`. `span` is the whole call, for the repair.
    fn valueReceiverAnswer(self: *Checker, owner_type: typed.Type, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!library_function_form.Answer {
        return self.noMethodsAnswer(owner_type, .{ .receiver = call.owner.?, .name = call.name, .arguments = call.arguments, .names = call.argument_names }, span);
    }
    /// The message for a method-style call on a receiver that has no methods, whether the receiver is a local (`p.norm()`) or an
    /// expression (`b.p.norm()`, `ps[0].norm()`): the call is the function `name(receiver, arguments)`. A record is said to have
    /// no methods, any other type is named. A `Stop` names the one function that reads it, whatever the method was.
    pub fn noMethodsMessage(self: *Checker, owner_type: typed.Type, site: call_arguments.MethodSite) Error![]const u8 {
        return (try self.noMethodsAnswer(owner_type, site, null)).message;
    }
    /// `noMethodsMessage` with the repair that goes with it when the call's whole `span` is known and every edit is certain: a
    /// function of that name that a standard module declares for the receiver's type is named with its module and its import (FR34).
    pub fn noMethodsAnswer(self: *Checker, owner_type: typed.Type, site: call_arguments.MethodSite, span: ?source.Span) Error!library_function_form.Answer {
        if (owner_type == .stop_cap) return .{ .message = try self.allocator.dupe(u8, "a Stop has no methods; read it with process.stop_requested(stop)") };
        const form = try call_arguments.functionForm(self.allocator, self.src, self.syntax.nodes.items, site);
        defer self.allocator.free(form);
        // A function form that names no function in scope is not advice to follow as it stands (B2: a lane wrote
        // `write_line(out, ...)`, which nothing declares), so the message says so, and a Stream names what writes to it.
        const missing = !try self.functionInScope(site.name);
        if (missing) if (try self.libraryAnswer(owner_type, .{ .name = site.name, .form = form, .span = span })) |found| return found;
        if (missing and owner_type == .stream_cap) return .{ .message = try std.fmt.allocPrint(
            self.allocator,
            "a value of type `Stream` has no methods and no function `{s}` is in scope; write to a Stream with `print({s}, ...)`",
            .{ self.src.text(site.name), self.src.text(site.receiver) },
        ) };
        const unknown: []const u8 = if (missing) try std.fmt.allocPrint(self.allocator, "; no function `{s}` is declared or in the prelude, so declare it first", .{self.src.text(site.name)}) else "";
        const plain_record = owner_type.isAggregate() and self.catalog.records[owner_type.recordIndex()].isRecord();
        if (plain_record) return .{ .message = try std.fmt.allocPrint(self.allocator, "a record has no methods; write the function form `{s}`{s}", .{ form, unknown }) };
        const type_name = try typed.surfaceTypeName(self.allocator, owner_type, self.catalog.records);
        return .{ .message = try std.fmt.allocPrint(self.allocator, "a value of type `{s}` has no methods; write the function form `{s}`{s}", .{ type_name, form, unknown }) };
    }
    /// FR37: the answer for a method written on a capability without methods that is reached through an expression
    /// (`ctx.clock.now()`), with the receiver's own text; `span` is the whole call. Null keeps the capability's plain text.
    pub fn capabilityReceiverAnswer(self: *Checker, reading: library_function_form.Reading, site: call_arguments.MethodSite, span: source.Span) Error!?library_function_form.Answer {
        const form = try call_arguments.functionForm(self.allocator, self.src, self.syntax.nodes.items, site);
        defer self.allocator.free(form);
        const own = try self.functionInScope(site.name);
        return library_function_form.capabilityAnswer(self.allocator, self.src, reading, site.receiver, .{ .name = site.name, .form = form, .span = span }, own);
    }
    /// The answer that names the standard module's function `call` meant, or null when no one module declares it for the receiver. A
    /// program's own type may share a library type's spelling, so only the types the language itself supplies are looked up.
    fn libraryAnswer(self: *Checker, owner_type: typed.Type, call: library_function_form.Call) Error!?library_function_form.Answer {
        if (owner_type.isAggregate()) return null;
        const spelled = if (owner_type == .random_cap) "Entropy" else try typed.surfaceTypeName(self.allocator, owner_type, self.catalog.records);
        const advice = (try library_function_form.advise(self.allocator, self.src, spelled, call)) orelse return null;
        const clause = try library_function_form.clause(self.allocator, advice);
        const message = try std.fmt.allocPrint(self.allocator, "a value of type `{s}` has no methods; write the function form {s}", .{ spelled, clause });
        return .{ .message = message, .fix = advice.fix };
    }
    /// Whether a bare call of the name written at `name` would find a function: a prelude function, or one the program declares
    /// (its own module's, in a project).
    fn functionInScope(self: *Checker, name: source.Span) Error!bool {
        if (prelude_names.isPrelude(self.src.text(name))) return true;
        if (self.catalog.module_names) |names| return (try names.symbolKind(name)) == .function;
        return self.functions.contains(try functionName(self.allocator, self.src, null, name));
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
            const value = if (field.default) try self.defaultExpected(field.value, record.fields[index].ty) else try self.expressionExpected(field.value, record.fields[index].ty);
            try self.require(self.nodes.items[@backingInt(value)].ty, record.fields[index].ty, self.syntax.nodes.items[@backingInt(field.value)].span);
            // A field takes its value: an element of a new list moves out of it (F-55).
            if (!field.default) try self.moveTemporaryElement(field.value, value);
            if (field.default) try self.requireConstantDefault(field.value, value);
            out.* = .{ .index = index, .value = value };
        }
        if (complete) for (seen, record.fields) |present, field| {
            if (!present) {
                const record_name = try typed.surfaceTypeName(self.allocator, record.id, self.catalog.records);
                const message = try std.fmt.allocPrint(self.allocator, "missing initializer for {s} `{s}` of `{s}`", .{ if (table_key != null) "key" else "field", field.name, record_name });
                return self.sink.failRelated(if (table_key != null) "E_INCOMPLETE_TABLE" else "E_INCOMPLETE_CONSTRUCTION", span, message, .{ .span = field.declaration, .message = "missing entry declared here" });
            }
        };
        return checked;
    }
    /// Check a field default as the constant of its declaring module that it is: with no local of the constructing function
    /// in scope, so a name in it is a module constant, a case or a type, never a variable that happens to share its spelling.
    pub fn defaultExpected(self: *Checker, id: ast.NodeId, expected: typed.Type) Error!typed.NodeId {
        const saved = self.enterDefault();
        defer self.leaveDefault(saved);
        return self.expressionExpected(id, expected);
    }
    /// Open the scope of a record field default: every local is hidden, and a text or bytes constant is read as the literal
    /// it holds, since the constructing function may sit in a module that cannot call the constant's private getter.
    pub fn enterDefault(self: *Checker) std.StringHashMapUnmanaged(typed.LocalId) {
        const saved = self.active;
        self.active = .empty;
        self.constant_default += 1;
        return saved;
    }
    /// Close the scope `enterDefault` opened and bring the locals back.
    pub fn leaveDefault(self: *Checker, saved: std.StringHashMapUnmanaged(typed.LocalId)) void {
        self.active.deinit(self.allocator);
        self.active = saved;
        self.constant_default -= 1;
    }
    /// Confirm that a record field default written as a name, a negated name, a member path or a call (`LIMIT`, `-INF`,
    /// `Kind.ground`, `Turn(angle=0)`) is a constant: a module constant, an enum case, or a record constructor whose
    /// arguments are plain values, constants or constructors in turn. The parser sees only the shape, so a call of a
    /// function (`pick(1)`), a function used as a value or a member that is no case is refused here, where the default is
    /// first built, with `E_DEFAULT_ARGUMENT`. Scalar and empty-collection defaults are not constants of this kind and pass.
    pub fn requireConstantDefault(self: *Checker, written: ast.NodeId, checked: typed.NodeId) Error!void {
        const syntax = self.syntax.nodes.items[@backingInt(written)];
        const constant = switch (syntax.data) {
            .name, .field => true,
            .unary => |unary| unary.op == .neg and switch (self.syntax.nodes.items[@backingInt(unary.operand)].data) {
                .name, .field => true,
                else => false,
            },
            .call => |call| !(call.owner == null and call.arguments.len == 0 and call.type_arguments.len == 0 and std.mem.eql(u8, self.src.text(call.name), "set")),
            else => false,
        };
        if (!constant) return;
        try self.constantDefaultNode(checked, syntax.span, true);
    }
    /// One node of a constant default: at the top an enum case, a record constructor or a read of a module constant, inside
    /// it a plain value or a constant again. A call of a function, or a function used as a value, is refused at any depth.
    fn constantDefaultNode(self: *Checker, id: typed.NodeId, span: source.Span, top: bool) Error!void {
        const refusal = "a default must be a literal, a module constant, an enum case or a record constructor whose arguments are such defaults; " ++
            "a call of a function (`math.nan()`, `pick(1)`), a function used as a value, or a name that is not a constant cannot be a default; " ++
            "bind the value to a module `const` and name that";
        switch (self.nodes.items[@backingInt(id)].data) {
            .variant => |variant| if (variant.value) |payload| try self.constantDefaultNode(payload, span, false),
            .record => |initializers| for (initializers) |initializer| try self.constantDefaultNode(initializer.value, span, false),
            .wrap, .cast, .unwrap => |inner| try self.constantDefaultNode(inner, span, top),
            .unary => |unary| try self.constantDefaultNode(unary.operand, span, top),
            .integer, .boolean, .unit, .array, .blob => {},
            .call => |call| if (!self.syntaxFunction(call.function).policy.constant) return self.sink.fail("E_DEFAULT_ARGUMENT", span, refusal),
            .invoke, .function_value, .local => return self.sink.fail("E_DEFAULT_ARGUMENT", span, refusal),
            else => if (top) return self.sink.fail("E_DEFAULT_ARGUMENT", span, refusal),
        }
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
        return self.requireValue(actual, expected, span, null);
    }
    /// `require` for the checked value `node`, which a `fails` call used as its plain value (`2 + parse("1")`) explains: the refusal
    /// then names the call and the two ways out, and carries `try ` as its repair when the enclosing function can pass the error on.
    /// `value` is `requireValue`'s: the argument's source text, when it is one.
    pub fn requireNode(self: *Checker, node: typed.NodeId, expected: typed.Type, span: source.Span, value: ?source.Span) Error!void {
        try self.refuseMissingTry(node, .{ .type = expected }, span);
        return self.requireValue(self.nodes.items[@backingInt(node)].ty, expected, span, value);
    }
    /// Refuse the checked value `node` when it is a direct call of a `fails` function whose success type is `expected`, with the advice
    /// of `frontend_failures.missingTry`; return when it is anything else, for the caller's own comparison to say what it says.
    pub fn refuseMissingTry(self: *Checker, node: typed.NodeId, wanted: @import("frontend_failures.zig").Wanted, span: source.Span) Error!void {
        const actual = self.nodes.items[@backingInt(node)].ty;
        if (wanted == .type and actual == wanted.type) return;
        const advice = (try @import("frontend_failures.zig").missingTry(Checker, self, node, wanted)) orelse return;
        const said = switch (wanted) {
            .type => |expected| try std.fmt.allocPrint(self.allocator, "expected {s}, found {s}", .{
                try typed.surfaceTypeName(self.allocator, expected, self.catalog.records),
                try typed.surfaceTypeName(self.allocator, actual, self.catalog.records),
            }),
            .integer => "operation requires an integer type",
        };
        const message = try std.fmt.allocPrint(self.allocator, "{s}; {s}", .{ said, advice.sentence });
        const edit = advice.insert orelse return self.sink.fail("E_TYPE", span, message);
        return self.sink.failFix("E_TYPE", span, message, edit);
    }
    /// `require` for a value whose source text is `value` (a call's argument), which a repair can name.
    pub fn requireValue(self: *Checker, actual: typed.Type, expected: typed.Type, span: source.Span, value: ?source.Span) Error!void {
        if (actual == expected) return;
        if (callables.signature(actual, self.catalog.records)) |implementation| {
            if (callables.signature(expected, self.catalog.records)) |destination| {
                if (callables.assignable(implementation, destination)) return;
            }
        }
        // `f32` and `float` are distinct domains: a plain mismatch names the width, and its repair is the conversion.
        if (numeric_surface.isBinaryFloat(actual, self.catalog.records) and numeric_surface.isBinaryFloat(expected, self.catalog.records))
            return self.sink.fail(numeric_surface.float_width_code, span, "f32 and float are different types; convert explicitly with f32(...) or float(...)");
        const expected_name = try typed.surfaceTypeName(self.allocator, expected, self.catalog.records);
        const actual_name = try typed.surfaceTypeName(self.allocator, actual, self.catalog.records);
        const message = try std.fmt.allocPrint(self.allocator, "expected {s}, found {s}{s}", .{ expected_name, actual_name, try self.octetsAdvice(actual, expected, value) });
        return self.sink.fail("E_TYPE", span, message);
    }
    /// The repair of a `byte_buffer` where `bytes` is expected (FX17: `takes_bytes(buf[1:3])`, a slice of a buffer being a
    /// buffer): `bytes(...)` of it gives its octets, spelled with the value's text when it is known and short. Empty for any
    /// other pair of types.
    fn octetsAdvice(self: *Checker, actual: typed.Type, expected: typed.Type, value: ?source.Span) Error![]const u8 {
        const schemas = self.catalog.records;
        if (!expected.isAggregate() or expected.recordIndex() >= schemas.len) return "";
        if (!typed.isByteString(schemas[expected.recordIndex()])) return "";
        if (!actual.isAggregate() or actual.recordIndex() >= schemas.len) return "";
        const found = schemas[actual.recordIndex()];
        if (!found.managed or found.collection.kind != .bytes or typed.isByteString(found)) return "";
        const text = if (value) |span| self.src.text(span) else "";
        const quotable = text.len != 0 and text.len <= 60 and std.mem.indexOfScalar(u8, text, '\n') == null;
        if (!quotable) return "; write `bytes(...)` of the value for its octets";
        return std.fmt.allocPrint(self.allocator, "; write `bytes({s})` for its octets", .{text});
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
        // A checked `Result` has no methods at all: name the two ways to handle one rather
        // than the union of every collection's methods (FR-109).
        if (family == null) if (receiver) |receiver_type| if (typed.resultShape(receiver_type, self.catalog.records) != null) {
            const name = try typed.surfaceTypeName(self.allocator, receiver_type, self.catalog.records);
            return std.fmt.allocPrint(
                self.allocator,
                "a {s} receiver has no methods; handle it with `match` (`case Ok(value)` and `case Err(message)`), or take the value with `try` in a function that declares `fails`",
                .{name},
            );
        };
        const set = if (receiver) |receiver_type| typed.setRecord(self.catalog.records, receiver_type) != null else false;
        const spellings = if (set)
            try buffer_operations.setMethodSpellings(self.allocator)
        else if (family) |kind|
            try buffer_operations.methodSpellings(self.allocator, kind)
        else
            try buffer_operations.advertisedUnionSpellings(self.allocator);
        const name = if (receiver) |receiver_type|
            try std.fmt.allocPrint(self.allocator, "a {s} receiver", .{try typed.surfaceTypeName(self.allocator, receiver_type, self.catalog.records)})
        else
            try self.allocator.dupe(u8, "this receiver");
        return std.fmt.allocPrint(self.allocator, "unknown method for {s}; {s}", .{ name, try self.acceptedMethods(spellings, family, set) });
    }
    /// The field `name` of `owner_type` when it is a record field that holds a function
    /// value, or null (FR-422).
    pub fn callableField(self: *Checker, owner_type: typed.Type, name: []const u8) ?typed.Type {
        if (!owner_type.isAggregate()) return null;
        const record = self.catalog.records[owner_type.recordIndex()];
        if (!record.isRecord()) return null;
        for (record.fields) |field| {
            if (!std.mem.eql(u8, field.name, name)) continue;
            return if (callables.signature(field.ty, self.catalog.records) != null) field.ty else null;
        }
        return null;
    }
    /// The message for a call through a function-valued field: the one spelling is to
    /// bind the field to a local and call that (FR-422).
    pub fn functionFieldMessage(self: *Checker, owner_type: typed.Type, name: []const u8) Error![]const u8 {
        return std.fmt.allocPrint(self.allocator, "a {s} has no methods; `{s}` is a function value stored in a field, so bind it first (`const f = value.{s}`) and call `f(...)`, or pass `f` as a value", .{
            try typed.surfaceTypeName(self.allocator, owner_type, self.catalog.records),
            name,
            name,
        });
    }
    /// The diagnostic for a method that exists for some collection family but not for
    /// `owner_type`'s: the receiver, the method and what the receiver does accept (FR-109).
    pub fn unsupportedMethodMessage(self: *Checker, kind: BufferKind, owner_type: typed.Type) Error![]const u8 {
        const family = self.catalog.records[owner_type.recordIndex()].collection.kind;
        const spellings = try buffer_operations.methodSpellings(self.allocator, family);
        const set = typed.setRecord(self.catalog.records, owner_type) != null;
        return std.fmt.allocPrint(self.allocator, "a {s} receiver has no `{s}` method; {s}", .{
            try typed.surfaceTypeName(self.allocator, owner_type, self.catalog.records),
            buffer_operations.spelling(kind) orelse "such",
            try self.acceptedMethods(spellings, family, set),
        });
    }
    /// The end of an unknown-method message: the methods the receiver still accepts, or, when it accepts none (a text,
    /// a list, a dictionary or a set, whose operations are all module functions since W13), the module to look in.
    fn acceptedMethods(self: *Checker, spellings: []const []const u8, family: ?ManagedKind, set: bool) Error![]const u8 {
        if (spellings.len == 0) {
            const module = if (set) "sets" else if (family) |kind| switch (kind) {
                .string => "strings",
                .bytes => "bytes",
                .list => "lists",
                .dictionary => "dicts",
            } else "standard";
            return std.fmt.allocPrint(self.allocator, "it has no methods: its operations are functions of the `{s}` module", .{module});
        }
        var joined: std.ArrayList(u8) = .empty;
        defer joined.deinit(self.allocator);
        for (spellings, 0..) |spelling, index| {
            if (index != 0) try joined.appendSlice(self.allocator, ", ");
            try joined.appendSlice(self.allocator, spelling);
        }
        return std.fmt.allocPrint(self.allocator, "accepted methods: {s}", .{joined.items});
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
    /// Reject a whole-path file helper whose argument count differs from its checked signature, rendering the spelling that
    /// works (`fs.write_text(path, text)`). The free spelling (`write_text(fs, path, text)`) is removed, so its message names
    /// the method and says that the Filesystem is the receiver; a channel of the standard library called outside the library
    /// is told the `process` module's functions instead.
    pub fn fileAccessArityFailure(self: *Checker, node: ast.Node, kind: file_operations.Access, actual: usize, method: bool) Error {
        const retiring_forms = @import("retiring_forms.zig");
        const name = @tagName(kind);
        const channel = kind == .run_process or kind == .process_control or kind == .stop_control;
        if (channel and !retiring_forms.librarySource(self.src, node.span))
            return self.sink.fail("E_ARITY", node.span, try retiring_forms.channelMessage(self.allocator, name));
        const expected = if (channel) kind.arity() else kind.methodArity();
        const plural: []const u8 = if (expected == 1) "" else "s";
        if (method or channel) return self.sink.fail("E_ARITY", node.span, try std.fmt.allocPrint(self.allocator, "`{s}` takes {d} argument{s}, but this call passes {d}", .{
            fileAccessSignature(kind), expected, plural, actual,
        }));
        const lead = "`{s}(fs, ...)` is a second spelling and was removed; write `{s}`, which takes {d} argument{s}";
        return self.sink.fail("E_ARITY", node.span, try std.fmt.allocPrint(self.allocator, lead ++ " (the Filesystem is its receiver); this call passes {d} in all", .{
            name, fileAccessSignature(kind), expected, plural, actual,
        }));
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
    /// assigned.
    pub fn requireReadable(self: *Checker, slot: typed.LocalId, name: source.Span) Error!void {
        const local = self.locals.items[@backingInt(slot)];
        if (!local.ownership.initialized) return self.sink.failRelated(
            eUnbound,
            name,
            "name may be read before it is assigned; some control-flow path reaching here leaves it unbound",
            .{ .span = local.declaration, .message = "binding first assigned here" },
        );
    }
    /// Snapshot every local's definite-assignment flag for later branch merging.
    pub fn initSnapshot(self: *Checker) Error![]u2 {
        const state = try self.allocator.alloc(u2, self.locals.items.len);
        for (self.locals.items, state) |local, *flag| flag.* = @as(u2, @intFromBool(local.ownership.initialized)) | (if (local.ownership.initialized or local.ownership.maybe_initialized) @as(u2, 2) else 0);
        return state;
    }
    /// Restore definite-assignment flags to a snapshot; locals created since it are
    /// treated as unassigned on the path being started.
    pub fn initRestore(self: *Checker, state: []const u2) void {
        for (self.locals.items, 0..) |*local, index| {
            local.ownership.initialized = index < state.len and state[index] & 1 != 0;
            local.ownership.maybe_initialized = index < state.len and state[index] & 2 != 0;
        }
    }
    /// Keep a local assigned after a branch only when both paths assigned it.
    pub fn initIntersect(self: *Checker, state: []const u2) void {
        for (self.locals.items, 0..) |*local, index| {
            local.ownership.maybe_initialized = local.ownership.initialized or local.ownership.maybe_initialized or (index < state.len and state[index] & 2 != 0);
            local.ownership.initialized = local.ownership.initialized and (index < state.len and state[index] & 1 != 0);
        }
    }
    /// Merge one continuing match arm's definite-assignment snapshot into the
    /// intersection over all continuing arms.
    pub fn mergeMatchInit(self: *Checker, merged: *?[]u2) Error!void {
        const current = try self.initSnapshot();
        if (merged.*) |prior| {
            self.initRestore(prior);
            self.initIntersect(current);
            merged.* = try self.initSnapshot();
        } else merged.* = current;
    }
    /// Group the ownership and initialization checkpoints of one active loop.
    pub fn loopCheckpoint(self: *Checker, pending: []const Pending) Error!*LoopCheckpoint {
        const checkpoint = try self.allocator.create(LoopCheckpoint);
        checkpoint.* = .{ .pending = pending, .init_before = try self.initSnapshot() };
        return checkpoint;
    }
    /// Reject a const initialization that can execute again on a loop backedge.
    pub fn requireConstLoopState(self: *Checker, span: source.Span) Error!void {
        const loop = self.loops.active.items[self.loops.active.items.len - 1];
        for (self.locals.items[0..loop.before.pending.len], 0..) |local, index| {
            if (local.mutable or loop.before.init_before[index] & 2 != 0) continue;
            if (local.ownership.initialized or local.ownership.maybe_initialized)
                return self.sink.failOwnershipRelated(
                    .{ .code = eImmutable, .rule = .B1 },
                    span,
                    "const assignment reaches a loop backedge and may execute more than once",
                    .{ .span = local.declaration, .message = "const binding declared outside this loop" },
                );
        }
    }
    /// Merge break exits with the optional zero-iteration path, excluding returns.
    pub fn finishLoopInit(self: *Checker, terminates: bool, zero_iterations: bool, span: source.Span) Error!void {
        if (!terminates) try self.requireConstLoopState(span);
        const loop = self.loops.active.items[self.loops.active.items.len - 1];
        self.initRestore(loop.before.init_before);
        if (loop.before.init_breaks) |exits| {
            if (zero_iterations) self.initIntersect(exits) else self.initRestore(exits);
        }
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
        if (expected) |ty_value| if (numeric_surface.isBinaryFloat(ty_value, self.catalog.records)) return null;
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
        if (@import("extern_types.zig").is(actual, self.catalog.records)) return @import("extern_types.zig").refuse(self.sink, span, .conversion);
        if (!actual.isInteger()) return self.sink.fail("E_TYPE", span, "operation requires an integer type");
    }
    /// Check one expression as a borrow of the place it names, which keeps its owner: `match mut` of a `@linear` owner reads
    /// its scrutinee this way (FX8), as a list inspection does.
    pub fn borrowedExpression(self: *Checker, root: ast.NodeId) Error!typed.NodeId {
        return @import("sema_expressions.zig").borrowList(Checker, self, root, &.{});
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
    /// An integer spelling with an `f32` suffix (`1f32`) has no decimal point or exponent, so it
    /// is refused rather than read as an integer: a binary32 literal is written `1.0f32`.
    fn refuseBareF32(self: *Checker, token: source.Span, text: []const u8) Error!void {
        if (float_syntax.isLiteral(text) or !std.mem.endsWith(u8, text, number_literal.f32_suffix)) return;
        return self.sink.fail(number_literal.suffix_code, token, "an f32 literal needs a decimal point or an exponent; write 1.0f32, not 1f32");
    }
    /// Type an integer literal against its expected type, or as a float literal when
    /// spelled or expected as one.
    pub fn checkInteger(self: *Checker, node: ast.Node) Error!typed.Node {
        const token = node.data.integer;
        const expected = self.expected_types.get(node.span);
        const text = self.src.text(token);
        try self.refuseBareF32(token, text);
        if (float_syntax.isLiteral(text) or (expected != null and numeric_surface.isBinaryFloat(expected.?, self.catalog.records))) {
            // An `f32` suffix or an expected `f32` makes the literal binary32; any other spelling is `float`.
            const target = if (float_syntax.isF32Literal(text) or (expected != null and numeric_surface.isF32(expected.?, self.catalog.records)))
                self.catalog.names.get("f32").?
            else
                self.catalog.names.get("float").?;
            return self.numericBuilderFor(node.span, target).literal(text, self.sink);
        }
        const parsed = try integer_literal.parseExpected(self.src, token, false, expected, self.sink);
        return .{ .span = node.span, .ty = parsed.ty, .data = .{ .integer = parsed.value } };
    }
    /// A numeric-surface builder that appends typed nodes for arithmetic at `span`.
    pub fn numericBuilder(self: *Checker, span: source.Span) numeric_surface.Builder {
        return self.numericBuilderFor(span, self.catalog.names.get("float").?);
    }
    /// A numeric-surface builder whose results wrap the floating domain `float_type` (`float` or `f32`).
    pub fn numericBuilderFor(self: *Checker, span: source.Span, float_type: typed.Type) numeric_surface.Builder {
        return .{ .arena = self.allocator, .nodes = &self.nodes, .span = span, .float_type = float_type, .records = self.catalog.records };
    }
    fn obviousType(self: *Checker, id: ast.NodeId) ?typed.Type {
        const node = self.syntax.nodes.items[@backingInt(id)];
        if (node.data == .name) {
            if (self.active.get(self.src.text(node.data.name))) |slot| {
                const declared = self.locals.items[@backingInt(slot)].ty;
                if (self.option_facts.has(@backingInt(slot))) if (prelude.optionShape(declared, self.catalog.records)) |shape| return shape.element;
                return declared;
            }
            return self.constantType(node.data.name);
        }
        if (self.expected_types.get(node.span)) |expected| return expected;
        // A field access over an obviously typed base is itself obvious, so
        // `node.literal == ...` and `node.kind == Kind.atom("x")` can hint the
        // constructor on the other operand the way a plain binding does.
        if (node.data == .field) if (self.obviousFieldType(node.data.field.base, node.data.field.name)) |field_ty| return field_ty;
        if (node.data == .index) return self.obviousIndexType(node.data.index.base);
        // An unsuffixed float literal has no type of its own: its context (an `f32` operand or annotation) decides.
        if (node.data == .integer and float_syntax.isLiteral(self.src.text(node.data.integer))) return if (float_syntax.isF32Literal(self.src.text(node.data.integer))) self.catalog.names.get("f32") else null;
        if (node.data == .unary and node.data.unary.op == .neg) return self.obviousType(node.data.unary.operand);
        return null;
    }
    /// Declared integer type of a visible scalar constant, so `MASK + 1` and `x == MASK`
    /// give the other operand's literal that type, as a typed local does. A miss stays
    /// silent here; the name is checked, and diagnosed, when the operand itself is.
    /// A name that is not a constant declaration, such as the module in
    /// `scanner.Kind.B`, is skipped before any resolution: a failed resolve records a
    /// problem on the project, which would outlive this hint. The lookup itself
    /// reports into a scratch sink.
    fn constantType(self: *Checker, name: source.Span) ?typed.Type {
        if (self.catalog.module_names) |names| {
            if (!(names.isConstant(name) catch return null)) return null;
        }
        var scratch: diagnostic.Sink = .{ .allocator = self.allocator };
        defer scratch.deinit();
        const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = &scratch, .catalog = self.catalog };
        const index = (constants.lookup(name) catch return null) orelse return null;
        const declared = constants.declaredType(index) catch return null;
        return if (declared.isInteger()) declared else null;
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
    // Index expressions need no evaluation to recover a collection's declared
    // element type. This also lets a following field continue the hint path.
    fn obviousIndexType(self: *Checker, base_id: ast.NodeId) ?typed.Type {
        const base = self.obviousType(base_id) orelse return null;
        if (!base.isAggregate()) return null;
        const index = base.recordIndex();
        if (index >= self.catalog.records.len) return null;
        const schema = self.catalog.records[index];
        if (schema.shape.array) |array| return array.element;
        if (schema.collection.kind == .list or schema.collection.kind == .dictionary) return schema.shape.buffer;
        return null;
    }
    /// Give a binary operator's untyped operand the type of its typed side or context.
    pub fn hintBinary(self: *Checker, node: ast.Node) Error!void {
        return self.hintOperands(node.data.binary, self.expected_types.get(node.span));
    }
    /// Give each operand of one binary operator the numeric type the other side
    /// or the context makes obvious, so a literal adopts its partner's width.
    pub fn hintOperands(self: *Checker, binary: @FieldType(@FieldType(ast.Node, "data"), "binary"), context: ?typed.Type) Error!void {
        // Sequence repetition has unlike operand types. A runtime count must
        // not lend its integer type to a contextual list constructor.
        if (binary.op == .mul) {
            for ([_]ast.NodeId{ binary.left, binary.right }) |operand| {
                switch (self.syntax.nodes.items[@backingInt(operand)].data) {
                    .list_literal, .comprehension, .gather => {
                        const shape = self.syntax.nodes.items[@backingInt(operand)].data;
                        if (shape == .gather and shape.gather.shape != .list) continue;
                        if (context) |expected| {
                            if (expected.isAggregate() and self.catalog.records[expected.recordIndex()].collection.kind == .list) try self.hint(operand, expected);
                        }
                        return;
                    },
                    else => {},
                }
            }
        }
        const expected = self.obviousType(binary.left) orelse self.obviousType(binary.right) orelse context orelse return;
        if (!expected.isInteger() and !numeric_surface.isBinaryFloat(expected, self.catalog.records)) {
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
        // A literal that cannot hold the type of the typed operand beside it is refused at the literal, naming that operand.
        if (self.obviousType(binary.left) != null)
            try literal_peer.refuseUnfit(Checker, self, binary.right, expected, binary.left)
        else if (self.obviousType(binary.right) != null)
            try literal_peer.refuseUnfit(Checker, self, binary.left, expected, binary.right);
        try self.hint(binary.left, expected);
        try self.hint(binary.right, expected);
    }
    /// Check an expression after recording the type its context expects.
    pub fn expressionExpected(self: *Checker, id: ast.NodeId, expected: typed.Type) Error!typed.NodeId {
        try self.hint(id, expected);
        const value = try self.expression(id);
        return @import("frontend_failures.zig").injectOptional(Checker, self, value, expected, self.syntax.nodes.items[@backingInt(id)].span);
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
    pub const checkFileAccessOn = builtin_checks.checkFileAccessOn;
    pub const checkFileMethod = builtin_checks.checkFileMethod;
    pub const checkFloatIntrinsic = builtin_checks.checkFloatIntrinsic;
    pub const checkListSort = builtin_checks.checkListSort;
    pub const checkMethodListSort = builtin_checks.checkMethodListSort;
    pub const checkPreludeListSort = builtin_checks.checkPreludeListSort;
    pub const hintPreludeListSort = builtin_checks.hintPreludeListSort;
    pub const checkNumericConversion = builtin_checks.checkNumericConversion;
    pub const checkOptionConstructor = builtin_checks.checkOptionConstructor;
    pub const checkPreludeCall = builtin_checks.checkPreludeCall;
    pub const checkPrint = builtin_checks.checkPrint;
    pub const checkResultConstructor = builtin_checks.checkResultConstructor;
    pub const checkStreamReceiverMethod = builtin_checks.checkStreamReceiverMethod;
    pub const checkStreamFunction = builtin_checks.checkStreamFunction;
    pub const checkStreamWrite = builtin_checks.checkStreamWrite;
    pub const streamFunction = builtin_checks.streamFunction;
    pub const checkUnit = builtin_checks.checkUnit;
    pub const debugBuiltin = builtin_checks.debugBuiltin;
    pub const expectedOption = builtin_checks.expectedOption;
    pub const expectedResult = builtin_checks.expectedResult;
    pub const fileAccessBuiltin = builtin_checks.fileAccessBuiltin;
    pub const fileAccessMethodKind = builtin_checks.fileAccessMethodKind;
    pub const floatIntrinsic = builtin_checks.floatIntrinsic;
    pub const floatFma = builtin_checks.floatFma;
    pub const checkFloatFma = builtin_checks.checkFloatFma;
    pub const byteRead = builtin_checks.byteRead;
    pub const checkByteRead = builtin_checks.checkByteRead;
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
    pub const refuseStreamSpelling = builtin_checks.refuseStreamSpelling;
    const collection_checks = @import("sema_collections.zig").Checks(Checker);
    pub const checkAcquireResource = collection_checks.checkAcquireResource;
    pub const checkAcceptResource = collection_checks.checkAcceptResource;
    pub const checkConstantMethod = collection_checks.checkConstantMethod;
    pub const checkRecognizedHome = collection_checks.checkRecognizedHome;
    pub const checkSuppliedHome = collection_checks.checkSuppliedHome;
    pub const hintRecognizedHome = collection_checks.hintRecognizedHome;
    pub const constantReceiver = collection_checks.constantReceiver;
    pub const checkBufferOperation = collection_checks.checkBufferOperation;
    pub const normalizeNegativePositions = collection_checks.normalizeNegativePositions;
    pub const hintTextMethodArgument = collection_checks.hintTextMethodArgument;
    pub const checkCollectionMethod = collection_checks.checkCollectionMethod;
    pub const checkCollectionSlice = collection_checks.checkCollectionSlice;
    pub const checkComprehension = collection_checks.checkComprehension;
    pub const checkSetFromIterable = collection_checks.checkSetFromIterable;
    pub const checkFormat = collection_checks.checkFormat;
    pub const checkListAccess = collection_checks.checkListAccess;
    pub const checkListLiteral = collection_checks.checkListLiteral;
    pub const checkNarrowedMethod = collection_checks.checkNarrowedMethod;
    pub const checkOptionReceiverMethod = collection_checks.checkOptionReceiverMethod;
    pub const checkPreludeOptionFunction = collection_checks.checkPreludeOptionFunction;
    pub const checkWriterFunction = collection_checks.checkWriterFunction;
    pub const refuseSortMethod = collection_checks.refuseSortMethod;
    pub const preludeOptionFunction = collection_checks.preludeOptionFunction;
    pub const preludeCopyFunction = collection_checks.preludeCopyFunction;
    pub const checkPreludeCopy = collection_checks.checkPreludeCopy;
    pub const checkCopyValue = collection_checks.checkCopyValue;
    pub const writerFunction = collection_checks.writerFunction;
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
    pub const hintSetOperand = set_checks.hintSetOperand;
    const place_checks = @import("sema_places.zig").Checks(Checker);
    pub const arrayKey = place_checks.arrayKey;
    pub const arrayPlace = place_checks.arrayPlace;
    pub const augmented = place_checks.augmented;
    pub const checkArrayPlace = place_checks.checkArrayPlace;
    pub const checkFieldAssignment = place_checks.checkFieldAssignment;
    /// Require a writable root for an ordinary nested data update.
    pub const requireWritableRoot = place_checks.requireWritableRoot;
    pub const checkFixedArray = place_checks.checkFixedArray;
    pub const checkIndexAugmented = place_checks.checkIndexAugmented;
    pub const checkTuple = place_checks.checkTuple;
    pub const referenceParameter = place_checks.referenceParameter;
    pub const requireRebindable = place_checks.requireRebindable;
    pub const twoNameLoopMessage = place_checks.twoNameLoopMessage;

    const expression_checks = @import("sema_expressions.zig").Checks(Checker);
    pub const expressionWithTemporaries = expression_checks.expressionWithTemporaries;
    /// Recognize a constructor whose equality peer supplies its expected type.
    pub const awaitsPeerType = expression_checks.awaitsPeerType;
    pub const lambdaIndex = expression_checks.lambdaIndex;
    const call_checks = @import("sema_calls.zig").Checks(Checker);
    pub const byteConversion = call_checks.byteConversion;
    pub const embedBuiltin = call_checks.embedBuiltin;
    pub const checkCall = call_checks.checkCall;
    pub const checkCapabilityReceiverMethod = call_checks.checkCapabilityReceiverMethod;
    pub const checkField = call_checks.checkField;
    pub const checkName = call_checks.checkName;
    pub const environmentMethod = call_checks.environmentMethod;
    pub const environmentComputedName = call_checks.environmentComputedName;
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
    pub const refusePresenceLink = operator_checks.refusePresenceLink;
    pub const checkValueBinary = operator_checks.checkValueBinary;
    pub const binaryValue = operator_checks.binaryValue;
    const gather_checks = @import("sema_gathers.zig").Checks(Checker);
    pub const checkGather = gather_checks.checkGather;
    pub const consumeGenerator = gather_checks.consumeGenerator;
    pub const foldedGenerator = gather_checks.foldedGenerator;
    pub const statementGatherStep = gather_checks.statementGatherStep;
    const idiom_checks = @import("sema_idioms.zig").Checks(Checker);
    pub const checkChain = idiom_checks.checkChain;
    pub const idiomBinary = idiom_checks.idiomBinary;
    pub const rangeStep = idiom_checks.rangeStep;
    pub const repeatAssignment = idiom_checks.repeatAssignment;
    pub const formatField = idiom_checks.formatField;
    pub const checkFormatHinted = idiom_checks.checkFormatHinted;
    pub const checkValueIndex = operator_checks.checkValueIndex;
    pub const moveTemporaryElement = operator_checks.moveTemporaryElement;
    /// Whether a name spells the binding of an enclosing `with arena() as name:`
    /// block, whose one use is `name.escape(value)` (NEW-CORE-S5-ARENA-2).
    pub fn arenaBinding(self: *Checker, name: source.Span) bool {
        const text = self.src.text(name);
        for (self.arenas.items) |scope| if (std.mem.eql(u8, scope.name, text)) return true;
        return false;
    }
    const contract_checks = sema_contracts.Checks(Checker);
    pub const indexInvariants = contract_checks.indexInvariants;
    /// Compile native decoded-value invariant callbacks after source bodies.
    pub const boundaryValidators = contract_checks.boundaryValidators;
    pub const contractSeeded = contract_checks.contractSeeded;
    pub const contractPrologue = contract_checks.contractPrologue;
    pub const contractReturn = contract_checks.contractReturn;
    pub const enforceInvariants = contract_checks.enforceInvariants;
    pub const writtenPlaces = contract_checks.writtenPlaces;
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
            if (try self.topLevel(parameter.name)) return self.refuseShadowing(parameter.name, "parameter");
            // `own` takes the value and `mut` writes the caller's, so a parameter
            // is one or the other; the parser reports the doubled spelling and
            // this keeps a cached or synthesized parameter from carrying both.
            if (parameter.own and parameter.mut) return sink.fail("E_PARAMETER_MODIFIER", parameter.name, "a parameter takes its value `own` or writes it `mut`, not both");
            const slot: typed.LocalId = @fromBackingInt(self.locals.items.len);
            const parameter_type = try self.ty(parameter.ty);
            // T: a plain parameter reads, so a move-only argument must not be
            // taken without the marker. `own` takes it and `mut` borrows it.
            const plain = !parameter.own and !parameter.mut;
            if (plain and typed.moveOnly(parameter_type, self.catalog.records)) try own_parameters.refusePlain(
                allocator,
                sink,
                src,
                parameter,
                try typed.surfaceTypeName(self.allocator, parameter_type, self.catalog.records),
                own_parameters.mentionsTypeParameter(src, parameter.ty, function.signature.type_parameters),
            );
            // `mut` promises a write the caller can observe, so it is accepted
            // only on a type that can carry one. Rejecting it here, before any
            // body or call is checked, keeps the declaration out of the published
            // footprint: the call site reports the missing marker instead.
            // VALUE-SEMANTICS-3: under value semantics a `mut` record crosses
            // as the caller's own variable, as a `mut` fixed array does.
            const plain_mode = !parameter.mut and !parameter.own;
            // A plain `@linear` parameter is a read-only loan (decision LINEAR-LEND); a call to a generic function checks its
            // arguments before the instance's types are known, so there it stays `own` or `mut`.
            const generic = function.signature.type_parameters.len != 0;
            if (plain_mode and generic and typed.linear(parameter_type, self.catalog.records)) return @import("linear_rules.zig").refuse(sink, parameter.ty, .parameter);
            const reference = parameter.mut and typed.referenceMut(self.catalog.records, parameter_type);
            if (reference) {
                const array = typed.referenceArray(self.catalog.records, parameter_type);
                if (function.policy.host != null or function.policy.c_abi) {
                    try markMutRejected(self);
                    const message = if (array)
                        "a host or C ABI function cannot take a `mut` fixed array; pass the array and return the changed copy"
                    else
                        "a host or C ABI function cannot take a `mut` record; pass the record and return the changed copy";
                    return sink.failOwnership(.{ .code = mutation_marker_code, .rule = .M2 }, parameter.ty, message);
                }
                // A `@linear` record crosses `mut` as an exclusive borrow its callee cannot end (D-FFI-11).
                if (self.transfers(parameter_type) and !typed.linear(parameter_type, self.catalog.records)) {
                    try markMutRejected(self);
                    return sink.failOwnership(
                        .{ .code = mutation_marker_code, .rule = .M2 },
                        parameter.ty,
                        if (array) "a `mut` fixed array needs copyable elements without pending results" else "a `mut` record needs copyable fields without pending results",
                    );
                }
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
                    // An `own` parameter is the callee's to write, so it is writable
                    // like a `mut` local; its writes never reach the caller.
                    .mutable = (parameter.mut or parameter.own) and function.policy.host == null,
                    .origin = .parameter,
                    .ownership = .{
                        .initialized = true,
                        .transfer_available = self.transfers(parameter_type),
                        .owned_parameter = parameter.own,
                    },
                },
            );
            try self.active.put(allocator, name, slot);
        }
    }
};
/// Whether any of these diagnostics is an error rather than a warning.
fn reportedError(items: []const diagnostic.Diagnostic) bool {
    for (items) |item| if (item.severity == .err) return true;
    return false;
}
/// Where a diagnostic is ordered. A pending result is reported on its binding but ordered where the path leaves with it, so
/// a result handled on some paths only is still reported after the `E_RESULT_PATH` that names the branch.
fn orderSpan(item: diagnostic.Diagnostic) source.Span {
    if (item.related) |related| if (std.mem.eql(u8, item.code, "E_RESULT_UNHANDLED")) return related.span;
    return item.span;
}
fn warningLess(_: void, a: diagnostic.Diagnostic, b: diagnostic.Diagnostic) bool {
    const left, const right = .{ orderSpan(a), orderSpan(b) };
    if (left.start != right.start) return left.start < right.start;
    if (left.end != right.end) return left.end < right.end;
    if (!std.mem.eql(u8, a.code, b.code)) return std.mem.lessThan(u8, a.code, b.code);
    return a.span.start < b.span.start;
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
fn checkGenericContracts(
    src: source.Source,
    program: ast.Program,
    sink: *diagnostic.Sink,
    catalog: records.Catalog,
    symbolic: *?generic_cache.Session,
    reuse: generic_bodies.Reuse,
) Error!void {
    const session: ?*generic_cache.Session = if (symbolic.*) |*retained| retained else null;
    var options = reuse;
    options.symbolic = session;
    try generic_bodies.checkWithCatalogCached(sink.allocator, src, program, sink, catalog, options);
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
    session: *?semantic_cache.Session,
    spec_session: *?generic_specializations.Session,
) Error!void {
    checker.prepared = if (session.*) |*queries| &queries.prepared else null;
    checker.spec_build = if (spec_session.*) |*reuse| reuse.backend.build else "";
    checker.spec_fingerprints_enabled = if (spec_session.*) |*reuse| reuse.backend.enabled else false;
    if (session.*) |*queries| if (spec_session.*) |*reuse| try checker.bindOrdinaryReferences(queries, reuse);
    if (checker.prepared) |prepared| for (prepared.ordinary_ast, 0..) |ast_index, instance| {
        const entry = try checker.ordinary_instance_by_key.getOrPut(allocator, prepared.keys[ast_index]);
        if (entry.found_existing) entry.value_ptr.* = std.math.maxInt(usize) else entry.value_ptr.* = instance;
    };
}
/// Active opt-in phase recorder, if any. Timing never changes semantic results.
fn activeTiming(cache: ?*semantic_cache.Cache) ?*timings.Profile {
    const c = cache orelse return null;
    const p = c.context.timing orelse return null;
    return if (p.enabled) p else null;
}
/// Start an exclusive window; phases recorded inside it are subtracted when it closes.
fn timingStart(timing: ?*timings.Profile) ?timings.Mark {
    if (timing) |p| return p.mark();
    return null;
}
fn timingAdd(timing: ?*timings.Profile, name: []const u8, start: ?timings.Mark) void {
    if (timing) |p| if (start) |at| p.addMark(name, at, false);
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
fn openPlan(cache: ?*semantic_cache.Cache, session: *?semantic_cache.Session, allocator: std.mem.Allocator, main: usize, syntax: ast.Program, names: ?*Names) Error!?sema_summaries.Plan {
    const c = cache orelse return null;
    const request = c.context.summaries orelse return null;
    const queries = if (session.*) |*opened| opened else return null;
    const timing = activeTiming(cache);
    const start = timingStart(timing);
    defer timingAdd(timing, "stand_in_planning", start);
    var plan = try sema_summaries.Plan.init(allocator, request, queries, main, .{ .timing = timing, .syntax = syntax, .names = names });
    const bodies_start = timingStart(timing);
    try plan.requireAllocationBodies(allocator, syntax, names);
    timingAdd(timing, "plan_allocation", bodies_start);
    const resolve_start = timingStart(timing);
    try plan.resolveStandIns(allocator);
    timingAdd(timing, "plan_resolve", resolve_start);
    return plan;
}
/// `W_UNUSED_IMPORT` reports against what the bodies resolved. A body a summary stood in for
/// resolved nothing here, so the references it recorded stand in for that.
fn noteStoodInImports(names: ?*Names, plan: *?sema_summaries.Plan, src: source.Source, program: ast.Program) void {
    const active = if (plan.*) |*value| value else return;
    const index = (names orelse return).index;
    active.noteImportUses(index, src, program);
}
/// Mark a failed stand-in attempt for a full retry and pass the error on. A
/// check with no stood-in body reports its diagnostics as they are. Only the whole-program
/// passes ask for a retry: they read the stood-in bodies' stored facts, which carry no witness
/// spans, so what they report may differ from a full check's. A body that fails to check is
/// reported as it is, because a body stands in only while the context that decides its own
/// result is unchanged, and every body that was checked reports exactly what a full check does.
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
    const start_reads = checker.sink.file_reads.items.len;
    if (step.plan.*) |*plan| if (plan.bodyStandsIn(i)) {
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
    const start_records = checker.catalog.records.len;
    const function = reused orelse checker.checkFunction(i) catch |err| switch (err) {
        error.SourceError => {
            @import("sema_recovery.zig").trimFailed(checker.sink, checker.recovery);
            return null;
        },
        else => return err,
    };
    // A finding the checker reports and keeps checking past (a call-site
    // `mut` marker) still fails its function once the body is done.
    if (reused == null and reportedError(checker.sink.items.items[start_diagnostics..])) return null;
    // A replayed body re-derives its binding warnings and nothing else, so a body whose check reported
    // anything (a call to a `@deprecated` function in another module) must be checked again, not
    // replayed, or the warning would vanish from the build that replays it. So must a body with a site
    // whose warning a file waiver silenced or another part of its file decided (`Sink.file_reads`, FX13):
    // the store keys a body by its own region, which a waiver elsewhere in the file leaves as it was.
    const replayable = reused == null and checker.sink.items.items.len == start_diagnostics and checker.sink.file_reads.items.len == start_reads;
    if (reused == null and !replayable) if (step.session.*) |*queries| queries.withhold(i);
    try recordBodyRange(.{
        .checker = checker,
        .session = step.session,
        .allocator = step.allocator,
        .index = i,
        .start = .{ .nodes = start_nodes, .statements = start_statements, .records = start_records },
        .publish = replayable,
    });
    if (step.plan.*) |*plan| try plan.recordChecked(step.allocator, .{
        .instance = i,
        .nodes = .{ .start = start_nodes, .end = checker.nodes.items.len },
        .statements = .{ .start = start_statements, .end = checker.statements.items.len },
        .diagnostics = checker.sink.items.items[start_diagnostics..],
    });
    return function;
}
/// In `HoleMode.recover`, the empty stand-in body of an ordinary function whose body failed to check; null in any other mode,
/// for a generic instance, or when the function's parameters do not check either.
fn standInFailedBody(step: InstanceStep) Error!?typed.Function {
    const checker = step.checker;
    if (checker.sink.hole_mode != .recover or step.index >= checker.lambda_start) return null;
    return checker.standInFunction(step.index) catch |err| switch (err) {
        error.SourceError => null,
        else => err,
    };
}
/// Under the stand-in count of W3 (`diagnostic.Probes.every`), an instance the count made whose own body check failed: its first
/// error goes to the count's log, its diagnostics leave the sink, and an empty body stands in, so the check goes on and the
/// ownership pass sees every other instance. Null for any other failure, which fails the check as before.
fn refusedStandIn(step: InstanceStep, start_diagnostics: usize) Error!?typed.Function {
    const checker = step.checker;
    const log = switch (checker.sink.template_probes) {
        .every => |log| log,
        else => return null,
    };
    if (step.index < log.first_stand_in or log.first_stand_in == 0) return null;
    const items = checker.sink.items.items;
    const first = for (items[@min(start_diagnostics, items.len)..]) |item| {
        if (item.severity == .err) break item;
    } else return null;
    try log.refused.put(log.allocator, step.index, .{ .code = first.code, .span = first.span });
    checker.sink.items.shrinkRetainingCapacity(@min(start_diagnostics, items.len));
    const stand_in = checker.standInFunction(step.index) catch |err| switch (err) {
        error.SourceError => {
            checker.sink.items.shrinkRetainingCapacity(@min(start_diagnostics, checker.sink.items.items.len));
            return null;
        },
        else => return err,
    };
    checker.sink.items.shrinkRetainingCapacity(@min(start_diagnostics, checker.sink.items.items.len));
    return stand_in;
}

/// A template whose body a stand-in instance's own check refused, under `diagnostic.Probes.declaration` (W3 step 2): the one
/// refusal it has in the sink and the conditions that refused it.
const DeclarationRefusal = struct { declaration: usize, item: usize, conditions: std.ArrayList(template_stand_ins.Condition) };

/// The instances `check` made to judge generic bodies at their declaration: from `first` up to `end`.
const StandInRange = struct { first: usize = 0, end: usize = 0 };

/// Under `diagnostic.Probes.declaration`, a stand-in instance (in `range`) whose own body check failed: its first error becomes
/// the template's one refusal at its declaration, naming the type parameter and the kinds, with the place in the body as a note
/// and no fix; a later stand-in of the same template only adds its kind. False for any other failure.
fn refuseAtDeclaration(step: InstanceStep, start_diagnostics: usize, range: StandInRange, refusals: *std.ArrayList(DeclarationRefusal)) Error!bool {
    const checker = step.checker;
    if (checker.sink.template_probes != .declaration or step.index < range.first or step.index >= range.end) return false;
    const items = checker.sink.items.items;
    const start = @min(start_diagnostics, items.len);
    const first = for (items[start..]) |item| {
        if (item.severity == .err) break item;
    } else return false;
    const key = checker.instance_keys.items[step.index];
    const declaration: usize = @backingInt(key.declaration);
    const function = checker.syntax.functions[declaration];
    const found = stand_in_kinds.condition(key.arguments, checker.catalog.records);
    const names = try template_stand_ins.parameterNames(checker.allocator, checker.src.bytes, function.name.end);
    checker.sink.items.shrinkRetainingCapacity(start);
    for (refusals.items) |*refusal| if (refusal.declaration == declaration) {
        try template_stand_ins.addCondition(checker.allocator, &refusal.conditions, found.parameters, found.kind);
        checker.sink.items.items[refusal.item].message = try template_stand_ins.describe(checker.allocator, checker.src.text(function.name), names, refusal.conditions.items);
        return true;
    };
    var conditions: std.ArrayList(template_stand_ins.Condition) = .empty;
    try template_stand_ins.addCondition(checker.allocator, &conditions, found.parameters, found.kind);
    var item = first;
    item.span = function.name;
    item.related = .{ .span = first.span, .message = first.message };
    item.provenance = .{ .rule = first.provenance.rule };
    item.message = try template_stand_ins.describe(checker.allocator, checker.src.text(function.name), names, conditions.items);
    try refusals.append(checker.allocator, .{ .declaration = declaration, .item = checker.sink.items.items.len, .conditions = conditions });
    try checker.sink.items.append(checker.sink.allocator, item);
    return true;
}

/// Under `diagnostic.Probes.declaration`, how the probe asks whether a template's judgment at its declaration is proven under
/// this run's inputs (W3 step 2): the host's `judged` callback and the check's prepared keys. Null when the check has no prepared
/// keys or its host keeps no judgments, so every template is judged.
fn judgmentHost(step: InstanceStep) ?@import("sema_specialize.zig").JudgmentHost {
    const checker = step.checker;
    if (checker.sink.template_probes != .declaration) return null;
    const plan = if (step.plan.*) |*active| active else return null;
    const demand = plan.request.policy.demand orelse return null;
    const judged = demand.judged orelse return null;
    const prepared = checker.prepared orelse return null;
    if (prepared.recalled.digests.len != checker.syntax.functions.len) return null;
    return .{ .context = demand.context, .judged = judged, .prepared = prepared };
}

/// Check ordinary bodies and any generic bodies required by invariant callbacks.
fn checkBodies(initial: InstanceStep, contracts_failed: bool, prior_failure: bool) Error![]typed.Function {
    var step = initial;
    var failed = prior_failure;
    var functions: std.ArrayList(typed.Function) = .empty;
    var validators: ?[]typed.Function = null;
    var probed = false;
    var range: StandInRange = .{};
    var refusals: std.ArrayList(DeclarationRefusal) = .empty;
    while (true) {
        while (step.index < step.checker.instance_keys.items.len and (!contracts_failed or step.index < step.checker.ordinary_count)) : (step.index += 1) {
            const start_diagnostics = step.checker.sink.items.items.len;
            const function = (try checkInstance(step)) orelse {
                if (try refuseAtDeclaration(step, start_diagnostics, range, &refusals)) {
                    failed = true;
                    continue;
                }
                if (try refusedStandIn(step, start_diagnostics)) |stand_in| {
                    try functions.append(step.allocator, stand_in);
                    continue;
                }
                if (try standInFailedBody(step)) |stand_in| {
                    try functions.append(step.allocator, stand_in);
                    continue;
                }
                failed = true;
                continue;
            };
            try functions.append(step.allocator, function);
        }
        if (failed) return error.SourceError;
        const probe = step.checker.sink.template_probes.any() and !contracts_failed;
        if (probe and !probed) {
            probed = true;
            range.first = step.checker.instance_keys.items.len;
            const registered = try step.checker.probeTemplates(judgmentHost(step));
            range.end = range.first + registered;
            if (registered != 0) continue;
        }
        if (validators != null) break;
        // The boundary validators, then the defaults a `json.decode` gives a missing member (`codec_defaults.zig`).
        const contract_validators = try step.checker.boundaryValidators();
        const defaults = try @import("codec_defaults.zig").functions(Checker, step.checker, functions.items);
        validators = try std.mem.concat(step.allocator, typed.Function, &.{ contract_validators, defaults });
    }
    for (validators.?) |*function| {
        function.id = @fromBackingInt(functions.items.len);
        try functions.append(step.allocator, function.*);
    }
    return functions.toOwnedSlice(step.allocator);
}

/// Where a body's check began in the node, statement and catalog record tables.
const StartMarks = struct { nodes: usize, statements: usize, records: usize };
/// One body's fresh interval recording inputs.
const RangeRecord = struct {
    checker: *Checker,
    session: *?semantic_cache.Session,
    allocator: std.mem.Allocator,
    index: usize,
    start: StartMarks,
    /// A body checked just now that a later request may replay: it reported no diagnostic.
    publish: bool,
};
/// Record the fresh node/statement interval for one body and remember a fresh
/// specialization for publication.
fn recordBodyRange(record: RangeRecord) Error!void {
    const checker = record.checker;
    const range: sem_copy.Range = .{
        .nodes = .{ .start = record.start.nodes, .end = checker.nodes.items.len },
        .statements = .{ .start = record.start.statements, .end = checker.statements.items.len },
    };
    if (record.session.*) |*queries| {
        if (record.index < queries.ranges.len) queries.ranges[record.index] = range;
        if (record.index < queries.record_ranges.len) queries.record_ranges[record.index] = .{ .start = record.start.records, .end = checker.catalog.records.len };
    }
    if (record.index < checker.spec_ranges.items.len) checker.spec_ranges.items[record.index] = range;
    if (record.publish and record.index >= checker.ordinary_count) try checker.spec_fresh.append(record.allocator, record.index);
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
    if (first_ty.capabilityIndex() != null or entryOptionalCapability(checker, first_ty) != null) return 0;
    return sink.fail("E_MAIN", parameters[0].ty, "entry parameters must be `args: str[]` followed by capabilities");
}

/// The capability index of an entry parameter written `T?` (CAP-OPT), or null when `ty` is no option of a capability.
fn entryOptionalCapability(checker: *Checker, ty: typed.Type) ?u4 {
    const shape = prelude.optionShape(ty, checker.catalog.records) orelse return null;
    return shape.element.capabilityIndex();
}

/// Whether a command line grants the capability of `index` (`Stream`, `Input` and `Stop` need no grant, so an entry
/// `T?` of one would never be `None`).
fn grantedCapability(index: u4) bool {
    return index != 5 and index != 8 and index != 9 and index != registers_family;
}

/// The capability index of `Registers` (`Type.capabilityIndex`): a device target hands `main` its registers, which need
/// no grant, so `Registers?` is refused as `Stop?` is. A build for a target without registers refuses `main(reg: Registers)`
/// (`pipeline.refuseUnprovided`, `E_TARGET_CAPABILITY`): the check does not know the target (MCU-B1D).
const registers_family: u4 = 10;

/// The capability index of one entry parameter after `args`: `T`, or `T?` for a capability a command line grants.
fn entryCapability(checker: *Checker, sink: *diagnostic.Sink, parameter: ast.Parameter, parameter_ty: typed.Type) Error!u4 {
    const index = parameter_ty.capabilityIndex() orelse entryOptionalCapability(checker, parameter_ty) orelse return sink.fail("E_MAIN", parameter.ty, "entry parameters must be `args: str[]` followed by capabilities");
    if (parameter_ty.capabilityIndex() != null) return index;
    if (!grantedCapability(index)) return sink.fail("E_MAIN", parameter.ty, "an entry `Stream`, `Input`, `Stop` or `Registers` needs no grant, so it is never `None`: write it without `?`");
    return index;
}

/// Validate the capability tail of the entry signature, splitting Streams by
/// name so `out: Stream` and `err: Stream` may both appear. A capability a command line grants may be written `T?`
/// (CAP-OPT): the entry passes `None` when the command line grants nothing of it.
fn validateEntryParameters(src: source.Source, checker: *Checker, sink: *diagnostic.Sink, entry: ast.Function) Error!void {
    const first_capability = try entryParameterStart(entry.signature.parameters, checker, sink);
    var entry_capabilities: u16 = 0;
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
        const index = try entryCapability(checker, sink, parameter, parameter_ty);
        const bit = @as(u16, 1) << index;
        if (entry_capabilities & bit != 0) return sink.fail("E_MAIN", parameter.name, "entry requests at most one value parameter of each capability kind");
        entry_capabilities |= bit;
    }
}

/// Whether this check is a project check (`selka check DIR`): its entry is the one a directory check generates, which
/// imports every module of the project, so the program holds every caller a private function can have.
fn projectCheck(module_names: ?*Names) bool {
    const names = module_names orelse return false;
    return check_directory.isEntry(names.index.project.modules.items[0].name);
}

/// `inputs` for the pass that also repairs `public` functions, when the command layer found the project no package.
fn publicRepaired(inputs: @import("copy_for_store.zig").Inputs, module_names: ?*Names) @import("copy_for_store.zig").Inputs {
    var repaired = inputs;
    repaired.public_repaired = if (module_names) |names| names.repairs_public else false;
    return repaired;
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
            !@import("invariant_callbacks.zig").isName(function.name) and
            !std.mem.eql(u8, function.name, entry_adapter.wrapper_name) and
            (if (module_names) |names| names.index.functionExported(names.src, function.declaration) else false);
    }
    return exported;
}

/// What `privateFunctions` reads of the program: the merged source, its syntax and the interface index (null for a single file).
const PrivacyInputs = struct { src: source.Source, syntax: ast.Program, names: ?*Names, main: typed.FunctionId };

/// Whether a compiler-made wrapper may call a function of this name: the program's `main`, and the tests (`test_`). The name of a
/// function of a project module carries its module (`app::main`).
fn isRootName(name: []const u8) bool {
    const bare = if (std.mem.lastIndexOf(u8, name, "::")) |at| name[at + 2 ..] else name;
    return std.mem.eql(u8, bare, "main") or std.mem.startsWith(u8, bare, "test_");
}

/// Whether `function` is an ordinary, named source function that no compiler-made wrapper calls: not a specialization, a member of a
/// domain, a conversion, restricted or foreign, not `main` or a test (`test_` or `@test`; wrappers in units of their own call those), not a lambda or a
/// generated callback.
fn mayBePrivate(function: typed.Function, inputs: PrivacyInputs) bool {
    const policy = function.policy;
    const ordinary = function.type_arguments.len == 0 and policy.owner == null and !policy.conversion and !policy.restricted;
    if (!ordinary or policy.c_abi or policy.host != null) return false;
    if (function.id == inputs.main or isRootName(function.name)) return false;
    for (ast.attributesOf(inputs.syntax, function.declaration)) |attribute| if (attribute.kind == .@"test") return false;
    const synthetic = std.mem.startsWith(u8, function.name, "lambda@") or @import("invariant_callbacks.zig").isName(function.name);
    return !synthetic and !std.mem.eql(u8, function.name, entry_adapter.wrapper_name);
}

/// Flag the functions no other unit of a build can name (`typed.Program.private`; spec section 17.5): ordinary source functions that
/// are neither exported by their module's interface nor members of a domain, conversions, restricted or foreign, and that sit in a
/// module declaring no generic function and with no test file in the build, and that no function value names (its adapter is a unit of its own,
/// and the optimizer may copy the value into a unit of another module). A body that stood in for a summary has no checked nodes, so `stood_values`
/// lists, by instance, the functions such bodies name as values: the answer is then the one a check of every body gives.
/// A generic template's body may call a private function of its module from the unit of an
/// instance elsewhere, and the template need not be instantiated in every program, so the whole module counts as visible. Without an
/// interface index (a single file) nothing is flagged.
fn privateFunctions(allocator: std.mem.Allocator, inputs: PrivacyInputs, functions: []const typed.Function, exported: []const bool, nodes: []const typed.Node, stood_values: []const u32) Error![]bool {
    const private = try allocator.alloc(bool, functions.len);
    @memset(private, false);
    if (inputs.names == null) return private;
    var visible_modules: std.AutoHashMapUnmanaged(usize, void) = .empty; // modules whose private functions another unit may call
    defer visible_modules.deinit(allocator);
    for (inputs.syntax.functions) |declared| {
        if (declared.signature.type_parameters.len == 0) continue;
        const at = inputs.src.originalSpan(declared.name) catch continue;
        try visible_modules.put(allocator, at.input, {});
    }
    // A module's test file (`<module>_test`, loaded by `selka test`) reaches its private declarations from a unit of its own.
    const index = inputs.names.?.index;
    for (0..index.project.modules.items.len) |from| {
        for (0..index.project.modules.items.len) |target| {
            if (index.testsModule(from, target)) try visible_modules.put(allocator, target, {});
        }
    }
    for (functions, private, exported) |function, *flag, is_exported| {
        if (is_exported or !mayBePrivate(function, inputs)) continue;
        const at = inputs.src.originalSpan(function.declaration) catch continue;
        flag.* = !visible_modules.contains(at.input);
    }
    // A function value of a function whose ABI differs from the plain one (a `mut` or named parameter) is reached through an adapter
    // that the build gives a unit of its own, and that unit calls the function: the function is visible to it.
    for (nodes) |node| switch (node.data) {
        .function_value => |callee| if (@backingInt(callee) < private.len) {
            private[@backingInt(callee)] = false;
        },
        else => {},
    };
    for (stood_values) |callee| if (callee < private.len) {
        private[callee] = false;
    };
    return private;
}

/// Whether the catalog's type `name` is a builtin (`bytes`, `str`, `float`) and not
/// one the program declares: the standard index marks a builtin by its name.
fn builtinTypeName(catalog: *const records.Catalog, name: []const u8) bool {
    const store = catalog.templates.store orelse return false;
    const declaration = store.index.names.get(name) orelse return false;
    return store.index.declarations.items[declaration].builtin_name != null;
}

/// Validate explicit return-source declarations using the shared Core authority.
/// Catalog collection resolves declaration types, without indexing body literals
/// or checking statements, generic bodies, entry points or semantic caches.
pub fn checkBorrowDeclarations(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names) Error!void {
    const declarations = try @import("declaration_borrow.zig").signatureProgram(allocator, program);
    const catalog = try nominal_catalog.collect(allocator, src, declarations, sink, module_names);
    try validateBorrowDeclarations(allocator, src, declarations, catalog, sink);
}

fn validateBorrowDeclarations(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, catalog: records.Catalog, sink: *diagnostic.Sink) Error!void {
    for (program.functions) |function| {
        const borrowing = try generic_bodies.declaredBorrow(allocator, src, program, catalog, function, sink);
        if (borrowing == .params) allocator.free(borrowing.params);
    }
}

/// Reuse supported checked bodies, then rerun all cross-function validation passes.
pub fn checkCached(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, module_names: ?*Names, cache: ?*semantic_cache.Cache) Error!typed.Program {
    return checkCore(allocator, src, program, sink, .{ .names = module_names, .cache = cache });
}

/// Check every library declaration and body without creating an executable entry.
/// Checked trees are discarded; library success cannot seed executable caches.
pub fn checkLibrary(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names) Error!void {
    _ = try checkLibraryProgram(allocator, src, program, sink, names);
}

/// Library tree for backend contract verification; never an executable entry.
pub fn checkLibraryProgram(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names) Error!typed.Program {
    return checkLibraryProgramCached(allocator, src, program, sink, names, null);
}

/// A library check that stands unchanged bodies in from `cache`'s check summaries, as an
/// executable check does: a body whose dependency context and declaration region are
/// unchanged is neither checked nor copied, the cross-function passes and warnings run on
/// its stored facts, and a pass that disagrees repeats the check in full. Without a summary
/// request on the cache this is `checkLibraryProgram`. The placeholder entry index is
/// always checked, and nothing executable is retained.
pub fn checkLibraryProgramCached(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, names: ?*Names, cache: ?*semantic_cache.Cache) Error!typed.Program {
    return checkCore(allocator, src, program, sink, .{ .names = names, .cache = cache, .entry_required = false });
}

/// Whether the entry unit declares a free function named `main`, the lookup
/// `checkEntry` makes. In a merged project the entry is input 0; a single
/// unmapped source is its own entry. `selka check` uses this to decide between
/// the executable check (a declared `main`, whatever its signature) and the
/// library check (none).
pub fn declaresMain(src: source.Source, program: ast.Program) bool {
    for (program.functions) |function| {
        if (function.policy.owner != null or !std.mem.eql(u8, src.text(function.name), "main")) continue;
        const input = if (src.originalSpan(function.name)) |original| original.input else |err| switch (err) {
            error.NotMappedSource => 0,
            else => continue,
        };
        if (input == 0) return true;
    }
    return false;
}

const CheckOptions = struct {
    names: ?*Names,
    cache: ?*semantic_cache.Cache = null,
    entry_required: bool = true,
};

fn checkCore(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, options: CheckOptions) Error!typed.Program {
    defer normalizeDiagnostics(sink);
    const checked = checkProgram(allocator, src, program, sink, options) catch |err| {
        // Removal repairs remain available even when an unrelated body fails.
        if (err == error.SourceError) try @import("arena_fix.zig").reject(allocator, src, program, sink);
        if (err == error.SourceError) try @import("domain_migration.zig").reject(allocator, src, program, options.names, sink, null);
        if (err == error.SourceError) try @import("tuple_migration.zig").reject(allocator, src, program, options.names, sink, null);
        return err;
    };
    // A recovering check's program stands beside diagnostics the refused check already reports.
    if (sink.hole_mode == .recover) return checked;
    try @import("arena_fix.zig").reject(allocator, src, program, sink);
    try @import("domain_migration.zig").reject(allocator, src, program, options.names, sink, &checked);
    try @import("tuple_migration.zig").reject(allocator, src, program, options.names, sink, &checked);
    if (reportedError(sink.items.items)) return error.SourceError;
    return checked;
}

/// T for declared types: a record field or union payload of function type takes
/// its positions the way a parameter does, so a move-only plain position is
/// refused there too. A generic declaration is skipped: each instance is
/// resolved where it is used, through `Checker.ty`.
fn checkDeclaredFunctionPositions(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, catalog: records.Catalog, sink: *diagnostic.Sink) Error!void {
    const callbacks = program.types.expressions.callbacks;
    for (program.types.records) |record| {
        if (record.type_parameters.len != 0) continue;
        for (record.fields) |field| try declaredFunctionType(allocator, src, callbacks, catalog, sink, field.ty);
    }
    for (program.types.variants) |variants| {
        if (variants.type_parameters.len != 0) continue;
        for (variants.cases) |case| {
            if (case.payload) |payload| try declaredFunctionType(allocator, src, callbacks, catalog, sink, payload);
            for (case.fields) |field| try declaredFunctionType(allocator, src, callbacks, catalog, sink, field.ty);
        }
    }
}
/// Resolve the declared type at `span` when it is spelled as a function type,
/// and refuse its move-only plain positions.
fn declaredFunctionType(allocator: std.mem.Allocator, src: source.Source, callbacks: []const ast.CallbackType, catalog: records.Catalog, sink: *diagnostic.Sink, span: source.Span) Error!void {
    const syntax = own_parameters.syntaxAt(callbacks, span) orelse return;
    const resolved = try catalog.resolve(src, span, sink);
    try own_parameters.refuseFunctionType(allocator, sink, .{ .src = src, .records = catalog.records, .type_parameters = &.{} }, resolved, syntax);
}
fn checkProgram(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink, options: CheckOptions) Error!typed.Program {
    const cache = options.cache;
    const module_names = options.names;
    const timing = activeTiming(cache);
    const collect_start = timingStart(timing);
    const catalog = try records.collectWithNames(allocator, src, program, sink, module_names);
    try checkDeclaredFunctionPositions(allocator, src, program, catalog, sink);
    try @import("record_defaults.zig").check(allocator, src, program, catalog, sink);
    // Source contracts are validated even when a cache can omit every body.
    try validateBorrowDeclarations(allocator, src, program, catalog, sink);
    timingAdd(timing, "sema_collect", collect_start);
    const session_start = timingStart(timing);
    var session = if (cache) |c| try c.begin(allocator, src, program, catalog.records) else null;
    var symbolic = try openSymbolicSession(cache, &session, src, module_names != null);
    defer deinitSymbolic(&symbolic);
    var spec_session = try openSpecializationSession(cache, &session);
    defer deinitSpecialization(&spec_session);
    const view_consumers = try dictionary_views.Consumers.init(allocator, src, program);
    defer view_consumers.deinit(allocator);
    timingAdd(timing, "sema_session_open", session_start);
    var failed = false;
    var generic_type_dependence: std.AutoHashMapUnmanaged(source.Span, void) = .empty;
    defer generic_type_dependence.deinit(allocator);
    const symbolic_start = timingStart(timing);
    checkGenericContracts(src, program, sink, catalog, &symbolic, .{ .view_consumers = view_consumers, .type_dependence = &generic_type_dependence }) catch |err| switch (err) {
        error.SourceError => failed = true,
        else => return err,
    };
    timingAdd(timing, "symbolic_templates", symbolic_start);
    const setup_start = timingStart(timing);
    const contracts_failed = failed;
    const ordinary_ids = try allocator.alloc(?typed.FunctionId, program.functions.len);
    @memset(ordinary_ids, null);
    const lambda_types = try allocator.alloc(?typed.Type, program.lambdas.len);
    @memset(lambda_types, null);
    const lambda_captures = try allocator.alloc(?[]const LambdaCapture, program.lambdas.len);
    @memset(lambda_captures, null);
    // The table comes from the system as zero pages: a warm check visits the few nodes of the bodies it checks, and the pages of the rest are never written.
    const resolved = try resolved_table.Resolved.init(program.nodes.items.len);
    var checker: Checker = .{
        .allocator = allocator,
        .src = src,
        .syntax = program,
        .view_consumers = view_consumers,
        .generic_type_dependence = &generic_type_dependence,
        .sink = sink,
        .resolved = resolved,
        .catalog = catalog,
        .ordinary_ids = ordinary_ids,
        .lambda_types = lambda_types,
        .lambda_captures = lambda_captures,
    };
    defer checker.resolved.deinit();
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
    try initSpecializationReuse(&checker, allocator, &session, &spec_session);
    const declared_names = try allocator.alloc([]const u8, program.functions.len);
    for (program.functions, 0..) |function, i| {
        const name = if (module_names) |names| try names.functionDeclaration(function.policy.owner, function.name) else try functionName(allocator, src, function.policy.owner, function.name);
        declared_names[i] = name;
        // The builtin `set` type is new beside programs that already declare a
        // function of that name, so such a function keeps its name and its
        // calls (SET-1); a declared type named `set` still conflicts.
        // A builtin type (`bytes`, `str`, `float`, `dict`) is no declaration of the
        // program's: its spelling is read as the type and a bare call of it as the
        // builtin (E_BUILTIN_FUNCTION_NAME refuses a function its module calls
        // bare), so a function of that name conflicts with nothing. Only a program
        // with no module names saw the clash, because its function names are bare;
        // the same file with an import, or checked as a module, was accepted (FX 5).
        // A function named `set` keeps its calls beside the builtin type (SET-1); a
        // declared type of the function's name still conflicts.
        const template = checker.catalog.templates.names.get(name);
        const builtin_template = template != null and template.?.end == 0;
        const declared_type = checker.catalog.names.contains(name) and !builtinTypeName(&checker.catalog, name);
        if (declared_type or (template != null and !builtin_template)) return sink.fail("E_DUPLICATE_NAME", function.name, "function name conflicts with a declared type");
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
    checker.declared_names = declared_names;
    checker.lambda_start = checker.instance_keys.items.len;
    for (program.lambdas) |_| {
        try checker.instance_keys.append(allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{} });
        try checker.spec_fingerprints.append(allocator, null);
        try checker.spec_ranges.append(allocator, .{ .nodes = .{ .start = 0, .end = 0 }, .statements = .{ .start = 0, .end = 0 } });
    }
    checker.ordinary_count = checker.instance_keys.items.len;
    // A library has no executable entry. This placeholder remains internal:
    // library checking neither adapts, returns nor caches the checked program.
    const main = if (options.entry_required) try checkEntry(&checker, module_names, failed) else @as(typed.FunctionId, @fromBackingInt(0));
    var plan = try openPlan(cache, &session, allocator, @backingInt(main), program, options.names);
    timingAdd(timing, "sema_checker_setup", setup_start);
    // The body loop's own time: every body phase inside it is subtracted, leaving the
    // loop's bookkeeping and the boundary validators.
    const bodies_start = timingStart(timing);
    const functions = checkBodies(.{
        .checker = &checker,
        .session = &session,
        .spec_session = &spec_session,
        .cache = cache,
        .plan = &plan,
        .allocator = allocator,
        .index = 0,
    }, contracts_failed, failed) catch |err| return err;
    noteStoodInImports(module_names, &plan, src, program);
    timingAdd(timing, "body_loop", bodies_start);
    const post_start = timingStart(timing);
    const pass_start = sink.items.items.len;
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
    timingAdd(timing, "sema_post_bodies", post_start);
    const entry_start = timingStart(timing);
    if (options.entry_required) try entry_adapter.adapt(allocator, &checked);
    const exported = try exportedFunctions(allocator, module_names, checked.functions);
    const stood_values = if (plan) |*active| try active.standInValues(allocator) else &[0]u32{};
    checked.private = try privateFunctions(allocator, .{ .src = src, .syntax = program, .names = module_names, .main = checked.main }, checked.functions, exported, checked.nodes, stood_values);
    timingAdd(timing, "entry_adaptation", entry_start);
    // A recovering check answers with the bodies it checked as soon as they are assembled: the whole-program passes would
    // judge the stand-ins, and their findings are the refused check's to report. Without a stand-in nothing is recovered.
    if (sink.hole_mode == .recover) return recoveredProgram(checked);
    const origins_start = timingStart(timing);
    const stubs: []const ?origins.Fact = if (plan) |*active| try active.passStubs(allocator, checked.functions.len) else &.{};
    const storage_start = timingStart(timing);
    try @import("linear_rules.zig").checkProgram(allocator, checked, sink, stubs);
    try @import("freestanding.zig").checkProgram(allocator, checked, src, sink, stubs);
    timingAdd(timing, "storage_rules", storage_start);
    // A borrowed value given to a task is refused on the same published sets (E1b).
    const tasks_start = timingStart(timing);
    if (try @import("sema_tasks.zig").refuseBorrowedArguments(allocator, checked.nodes, checked.functions, checked.records, sink)) return error.SourceError;
    timingAdd(timing, "task_borrows", tasks_start);
    const facts: ?[]origins.Fact = if (plan != null) try allocator.alloc(origins.Fact, checked.functions.len) else null;
    const enforce_start = timingStart(timing);
    origins.enforce(allocator, checked, .{ .exported = exported, .src = src, .syntax = program, .sink = sink, .stubs = stubs, .facts = facts }) catch |err| return retryOr(&plan, err);
    timingAdd(timing, "origins_enforce", enforce_start);
    timingAdd(timing, "origin_passes", origins_start);
    const codecs_start = timingStart(timing);
    @import("domain_codecs.zig").check(allocator, src, program.types.domains, checker.catalog, .{ .items = functions, .names = executable_names }, sink) catch |err| return retryOr(&plan, err);
    timingAdd(timing, "domain_codec_validation", codecs_start);
    const warnings_start = timingStart(timing);
    const bindings_start = timingStart(timing);
    try warnBindings(allocator, checked, .{ .stubs = stubs, .src = src, .entry = if (options.entry_required) main else null, .functions = program.functions, .syntax = program }, sink);
    try warnImports(module_names, sink);
    timingAdd(timing, "warn_bindings_imports", bindings_start);
    // P1: a copy the copy-free form provably replaces is a warning with its
    // `fix`, in the same pass as the other warnings so a stood-in body replays it.
    const copies_start = timingStart(timing);
    try @import("needless_copy.zig").warn(allocator, checked, src, stubs, exported, sink);
    const repair_inputs: @import("copy_for_store.zig").Inputs = .{ .program = checked, .src = src, .stubs = stubs, .exported = exported, .project = projectCheck(module_names) };
    // A function whose every return copies a place of one parameter, where `from` that parameter is certain, in a project
    // check (its callers judged later, with the `W_COPY_MOVE` hint it stands beside); a `public` function too when the command
    // layer found the project no package (`Names.repairs_public`), as for the two repairs below.
    try @import("copy_from_repair.zig").warn(allocator, publicRepaired(repair_inputs, module_names), sink);
    // A parameter copied into storage where `own` would make the copy a move, in a project check (its callers judged later); a `public`
    // function too when the command layer found the project no package (`Names.repairs_public`).
    try @import("copy_for_store.zig").warn(allocator, publicRepaired(repair_inputs, module_names), sink);
    // A plain list parameter whose elements a loop copies into storage, where `own` and `for x in own` make the copies moves:
    // the same warning, so the same rule for a `public` function.
    try @import("copy_loop_repair.zig").warn(allocator, publicRepaired(repair_inputs, module_names), sink);
    // O4: a copy of a function's context passed into its own recursive call copies it at every level.
    try @import("copy_recursion.zig").warn(allocator, checked, src, stubs, sink);
    timingAdd(timing, "needless_copy", copies_start);
    // 5C: an `own` marker on a capability, or on a value that only held one, transfers nothing now.
    const capability_markers_start = timingStart(timing);
    try @import("capability_markers.zig").warn(allocator, checked, src, stubs, sink);
    timingAdd(timing, "capability_markers", capability_markers_start);
    // 5C: a `mut` capability parameter that nothing writes hands nothing back.
    const capability_mut_start = timingStart(timing);
    try @import("capability_mut.zig").warn(allocator, checked, src, stubs, sink);
    timingAdd(timing, "capability_mut", capability_mut_start);
    const idioms_start = timingStart(timing);
    const silenced = try warnIdioms(allocator, src, program, checker.ordinary_ids, .{ .stubs = stubs, .checked = checked, .sink = sink });
    timingAdd(timing, "idiom_hints", idioms_start);
    const pass_items: []const diagnostic.Diagnostic = if (plan != null) try allocator.dupe(diagnostic.Diagnostic, sink.items.items[pass_start..]) else &.{};
    std.mem.sort(diagnostic.Diagnostic, sink.items.items, {}, warningLess);
    timingAdd(timing, "warning_derivation", warnings_start);
    // A rejected dead copy write is an implementation error, not advice: it must
    // stop checking before retention publishes an invalid program.
    for (sink.items.items) |item| if (item.severity == .err) return retryOr(&plan, error.SourceError);
    if (plan) |*active| {
        const summary_start = timingStart(timing);
        defer timingAdd(timing, "check_summaries", summary_start);
        try active.verifyWithheld(allocator, checked, facts.?, pass_items);
        const file_reads = try allocator.dupe(source.Span, sink.file_reads.items);
        std.mem.sort(source.Span, file_reads, {}, spanStartsFirst);
        if (!try active.finish(allocator, checked, facts.?, .{ .pass = pass_items, .syntax = program, .silenced = silenced, .file_reads = file_reads }, sink)) return retryOr(&plan, error.SourceError);
    }
    const retain_start = timingStart(timing);
    // A check that kept a hole as a trap publishes nothing (see `Sink.trapped_holes`).
    if (sink.trapped_holes == 0) {
        try publishSpecializationSession(&spec_session, &checker, allocator, checked);
        if (session) |*queries| try queries.remember(checked);
    }
    timingAdd(timing, "retention_store_io", retain_start);
    return checked;
}

/// A recovering check's answer: its program when it stood in at least one failed body, else the refusal.
fn recoveredProgram(checked: typed.Program) Error!typed.Program {
    for (checked.functions) |function| if (typed.recoveredStandIn(function)) return checked;
    return error.SourceError;
}

fn checkEntry(checker: *Checker, module_names: ?*Names, failed: bool) Error!typed.FunctionId {
    const allocator = checker.allocator;
    const src = checker.src;
    const program = checker.syntax;
    const sink = checker.sink;
    const main_name = if (module_names) |names| try std.fmt.allocPrint(allocator, "{s}::main", .{names.index.project.modules.items[0].name}) else "main";
    const main_declaration = checker.functions.get(main_name) orelse {
        if (failed) return error.SourceError;
        return sink.fail("E_MAIN", .{ .start = 0, .end = 0 }, "the program requires an entry point: func main() -> int; `selka check FILE` type-checks a library that has no main");
    };
    const entry = program.functions[@backingInt(main_declaration)];
    const main = checker.ordinary_ids[@backingInt(main_declaration)] orelse return sink.fail("E_MAIN", entry.name, "main cannot have type parameters");
    if (entry.policy.host != null or entry.policy.constant) return sink.fail("E_MAIN", entry.name, "main must have a guest function body");
    // An entry point may take `args: str[]` first, followed by at most one
    // capability of each kind. Streams split by name, so `out: Stream` and
    // `err: Stream` may both appear; any other Stream name is rejected.
    try validateEntryParameters(src, checker, sink, entry);
    const entry_message = "main must return int, None, or Result[int or None, E] whose error E print can render";
    if (!entry_adapter.supported(try checker.ty(entry.signature.return_type), checker.catalog.records)) return sink.fail("E_TYPE", entry.signature.return_type, entry_message);
    return main;
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
    const lowered = try @import("record_calls.zig").lower(self.allocator, self.src, self.catalog, self.syntax.nodes.items, node.data.call, self.sink);
    return lowered != null;
}

const functionName = @import("function_identity.zig").localName;

/// The C ABI of an `extern func` signature after its `host` parameter (`c_abi.zig`, D-FFI-2 to D-FFI-5).
fn externSignature(self: *Checker, function: ast.Function) Error!void {
    const foreign = @import("c_abi.zig");
    const catalog_records = self.catalog.records;
    const sink = self.sink;
    if (foreign.isText(self.return_type, catalog_records)) return sink.fail("E_EXTERN_SIGNATURE", function.signature.return_type, foreign.text_result_message);
    if (!foreign.supported(self.return_type, catalog_records, true)) return sink.fail("E_EXTERN_SIGNATURE", function.signature.return_type, foreign.signature_message);
    const parameters = function.signature.parameters;
    for (self.locals.items[1..parameters.len], parameters[1..]) |local, parameter| {
        if (foreign.isBuffer(local.ty, catalog_records)) return sink.fail("E_EXTERN_SIGNATURE", local.declaration, foreign.buffer_message);
        if (!foreign.supported(local.ty, catalog_records, false)) return sink.fail("E_EXTERN_SIGNATURE", local.declaration, foreign.signature_message);
        if (!parameter.mut) continue;
        if (!foreign.outParameter(local.ty, catalog_records)) return sink.fail("E_EXTERN_SIGNATURE", local.declaration, foreign.out_parameter_message);
        if (foreign.isBytes(self.return_type, catalog_records)) return sink.fail("E_EXTERN_SIGNATURE", local.declaration, foreign.bytes_out_message);
    }
}

/// The target an `@address` extern func calls through: its parameter after `host`, an `extern type` handle (a C function
/// pointer carried unchanged) or `u32`/`u64` (an address; the build refuses a `u64` where addresses are 32 bits). It is read, never written back, so it is not `mut`.
fn addressTarget(self: *Checker, function: ast.Function) Error!void {
    const parameters = function.signature.parameters;
    if (parameters.len < 2) return self.sink.fail("E_EXTERN_ADDRESS", function.name, address_target_message);
    const target = self.locals.items[1];
    const accepted = target.ty == .u32 or target.ty == .u64 or @import("c_abi.zig").foreignHandle(target.ty, self.catalog.records);
    if (!accepted or parameters[1].mut) return self.sink.fail("E_EXTERN_ADDRESS", target.declaration, address_target_message);
}

const address_target_message = "an `@address` extern func takes the function it calls as the parameter after `host`: an `extern type` handle, " ++
    "or `u32` or `u64` for an address, not `mut`";

fn checkHostType(allocator: std.mem.Allocator, catalog: []const typed.Record, ty: typed.Type, span: source.Span, sink: *diagnostic.Sink) Error!void {
    @import("data_type.zig").checkHost(allocator, catalog, ty) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return sink.fail("E_HOST_SIGNATURE", span, "host signatures require ordinary data, or `bytes`, without capabilities or other runtime-owned storage"),
    };
}

/// Whether local `slot` names caller storage through a declared mut parameter.
fn callerBinding(function: typed.Function, slot: usize) bool {
    if (slot >= function.signature.parameter_count) return false;
    for (function.signature.declared_mutates) |position| if (position == slot) return true;
    return false;
}

/// Whether a binding warning already stands at this declaration.
fn warnedAt(items: []const diagnostic.Diagnostic, declaration: source.Span) bool {
    for (items) |item| {
        if (item.span.start == declaration.start and item.span.end == declaration.end and std.mem.eql(u8, item.code, "W_UNUSED_BINDING")) return true;
    }
    return false;
}
/// The stand-ins and the sink the idiom pass reports against.
const IdiomContext = struct { stubs: []const ?origins.Fact, checked: typed.Program, sink: *diagnostic.Sink };

fn spanStartsFirst(_: void, left: source.Span, right: source.Span) bool {
    return left.start < right.start;
}

/// The idiom warnings (`syntax_hints.zig`) of every function body this check reads. A body a stand-in
/// replaces is not read again: its warnings were made with its summary and are replayed with it.
fn warnIdioms(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, ordinary_ids: []const ?typed.FunctionId, context: IdiomContext) Error![]const source.Span {
    const skip = try allocator.alloc(bool, program.functions.len);
    defer allocator.free(skip);
    for (skip, 0..) |*slot, index| {
        const id = if (index < ordinary_ids.len) ordinary_ids[index] else null;
        slot.* = if (id) |known| origins.standIn(context.stubs, @backingInt(known)) != null else false;
    }
    return @import("syntax_hints.zig").warn(allocator, src, program, skip, .{ .program = context.checked, .ordinary_ids = ordinary_ids }, context.sink);
}

/// Whether the checked body of `function` holds a typed hole kept as a trap (`diagnostic.HoleMode.trap`).
fn bodyHoldsHole(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function) Error!bool {
    var walker = try @import("typed_walk.zig").Walker.init(allocator, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        if (item != .expression) continue;
        if (std.meta.activeTag(program.nodes[@backingInt(item.expression)].data) == .hole) return true;
    }
    return false;
}

/// What `warnBindings` reads besides the program: the stood-in bodies' facts, the source, the program's entry `main` (null in a
/// library check, which has none) and the declared signatures, where the entry's parameter list is found.
const BindingContext = struct { stubs: []const ?origins.Fact, src: source.Source, entry: ?typed.FunctionId, functions: []const ast.Function, syntax: ast.Program };

/// The refusal of an unread Stream parameter of the entry `main`, with the deletion of the parameter when that is certain.
fn refuseEntryStream(allocator: std.mem.Allocator, context: BindingContext, local: typed.Local, sink: *diagnostic.Sink) Error!void {
    const refusal: diagnostic.Diagnostic = .{
        .severity = .err,
        .code = origins.unused_capability_code,
        .span = local.declaration,
        .message = try origins.unusedEntryStreamMessage(allocator, local.name),
    };
    if (@import("entry_stream_fix.zig").deletion(context.src, context.functions, local.declaration)) |edit| {
        try sink.appendFix(refusal, edit);
    } else try sink.items.append(allocator, refusal);
}

fn warnBindings(allocator: std.mem.Allocator, program: typed.Program, context: BindingContext, sink: *diagnostic.Sink) Error!void {
    const stubs = context.stubs;
    const src = context.src;
    for (program.functions, 0..) |function, index| {
        // A foreign or supplied (`builtin func`, W10) declaration has no body to read its parameters.
        if (function.policy.host != null or function.policy.builtin) continue;
        // A stood-in body has only its parameters here; its summary replays
        // the binding warnings its checked body reported.
        if (origins.standIn(stubs, index) != null) continue;
        const first_warning = sink.items.items.len;
        // A body that still holds a typed hole is unfinished: the code that fills the hole may read any
        // parameter, so an unread parameter is neither an over-claimed capability nor a dead binding yet.
        // Only a check that kept a hole as a trap gets here with one, and it publishes no cache entry.
        const unfinished = sink.trapped_holes != 0 and try bodyHoldsHole(allocator, program, function);
        for (function.scope.locals, 0..) |local, slot| {
            if (local.usage.temporary or local.usage.reads != 0) continue;
            if (unfinished and local.origin == .parameter) continue;
            // The arms of a `case a(x) | b(x):` list each check a copy of one body, so a local of it is declared at one span twice.
            if (warnedAt(sink.items.items[first_warning..], local.declaration)) continue;
            // Rebinding a `mut` caller variable uses the parameter even when
            // the body never reads its previous value.
            if (callerBinding(function, slot)) continue;
            // A capability parameter is the signature's whole claim to an
            // effect: a body that never reads it promises authority it does not
            // use, so the over-claim is rejected rather than warned about.
            if (local.origin == .parameter and local.ty.capabilityIndex() != null) {
                if (std.mem.startsWith(u8, local.name, "_")) continue;
                // The entry names its Streams `out` and `err` (E_MAIN), so renaming one `_out` is refused: the advice there is to
                // delete the parameter, and the diagnostic carries that deletion when it is certain (FR35).
                if (context.entry != null and @backingInt(context.entry.?) == index and local.ty.isStream()) {
                    try refuseEntryStream(allocator, context, local, sink);
                    continue;
                }
                const repair = try origins.unusedCapabilityRepair(allocator, src.bytes, local.name);
                try sink.appendFix(.{
                    .severity = .err,
                    .code = origins.unused_capability_code,
                    .span = local.declaration,
                    .message = repair.message,
                }, .{ .span = local.declaration, .text = repair.replacement });
                continue;
            }
            // A binding that a `match` pattern introduces is ignored by writing `_` there, and the diagnostic carries that edit (FR45).
            if (local.origin == .pattern or local.origin == .local) {
                if (try pattern_discard_fix.repair(allocator, src, context.syntax, program.records, local)) |repair| {
                    try sink.appendFix(.{ .severity = .warning, .code = "W_UNUSED_BINDING", .span = local.declaration, .message = repair.message }, repair.edit);
                    continue;
                }
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
        // A directory check's generated entry imports every module of the project and uses none of them.
        if (check_directory.isEntry(index.project.modules.items[module].name)) continue;
        const imports = index.project.modules.items[module].imports;
        for (imports, 0..) |imported, import_index| {
            if (index.importUsed(module, import_index)) continue;
            const span = names.src.mappedSpan(module, imported.span) catch continue;
            const message = try std.fmt.allocPrint(sink.allocator, "import `{s}` is never referenced in this module; remove it or use it", .{imported.name});
            const line = @import("import_fix.zig").importLine(index.project.modules.items[module].src.bytes, imported.span);
            const removal = if (line) |local| names.src.mappedSpan(module, local) catch null else null;
            try sink.items.append(sink.allocator, .{
                .severity = .warning,
                .code = "W_UNUSED_IMPORT",
                .span = span,
                .message = message,
                .provenance = .{ .fix = if (removal) |whole| .{ .edit = .{ .span = whole, .text = "" } } else null },
            });
        }
    }
}
