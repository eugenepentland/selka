//! Checking of names, fields and calls: record field reads, functions used as
//! values and indirect calls, bare names, byte/text/type conversions, the
//! `Environment`, `Network` and filesystem capability methods, host calls,
//! record updates, ordinary calls with deprecation warnings, and the call-site
//! `&`/`mut` markers checked against a callee's declared footprint. Each check is
//! a free function over the concrete checker type; `Checks` exposes the ones
//! the rest of the checker calls as `self.name(...)`.
const sema_shared = @import("sema_shared.zig");
const collections = @import("collection_lower.zig");
const option_flow = @import("option_flow.zig");
const frontend_failures = @import("frontend_failures.zig");
const call_arguments = @import("call_arguments.zig");
const library_function_form = @import("library_function_form.zig");
const contains_removed = @import("contains_removed.zig");
const external_resources = @import("external_resources.zig");
const file_operations = @import("file_operations.zig");
const callables = @import("callables.zig");
const eResultOperation = diagnostic.result_operation;
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const isMutableBytes = sema_shared.isMutableBytes;
const eImmutable = diagnostic.immutable;
const std = @import("std");
const supplied_calls = @import("sema_supplied.zig");
const sema_exchange = @import("sema_exchange.zig");
const mutation_marker_code = @import("origins.zig").mutation_marker_code;
const own_parameters = @import("own_parameters.zig");
const own_marker_code = own_parameters.marker_code;
const ast = @import("ast.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const prelude = @import("prelude.zig");
const markerPositionDeclared = sema_shared.markerPositionDeclared;
const eEnvironmentName = sema_shared.eEnvironmentName;
const callback_type_code = "E_CALLBACK_TYPE";
const embed = @import("embed.zig");
const eByteConversion = "E_BYTES_CONVERSION";
const eFilesystemDir = "E_FILESYSTEM_DIR";
const eNetworkHost = "E_NETWORK_HOST";
const eCollectionMethod = sema_shared.eCollectionMethod;
const text_scalar = @import("scalar_text_helpers.zig");
/// The narrowing methods of `Filesystem` and `Network`, spelled once so the
/// named-local and expression-receiver dispatch cannot drift apart.
const read_only_method = "read_only";
const dir_method = "dir";
const host_method = "host";
const network_host_literal_message = @import("sema_shared.zig").network_host_literal_message;
const scopedDirectoryPath = @import("scoped_directory.zig").valid;
/// Remove the matching quotes around one string-literal spelling.
fn literalText(bytes: []const u8, span: source.Span) []const u8 {
    const text = bytes[span.start..span.end];
    if (text.len >= 2 and (text[0] == '"' or text[0] == '\'')) return text[1 .. text.len - 1];
    return text;
}
const impl = @This();
/// Bind name, field and call checking to the concrete checker without an import cycle.
pub fn Checks(comptime Checker: type) type {
    return struct {
        /// Recognize an unshadowed `embed_bytes(...)` or `embed_str(...)` call (`EMBED-1`).
        pub fn embedBuiltin(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?embed.Kind {
            return impl.embedBuiltin(Checker, self, call);
        }
        /// Recognize an unshadowed `bytes(...)` conversion or `bytes.fromhex(...)` call.
        pub fn byteConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?ByteConversion {
            return impl.byteConversion(Checker, self, call);
        }
        /// Check a call expression: builtins and constructors first, then a declared or
        /// callable callee with its arguments, `mut` markers and effects.
        pub fn checkCall(self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
            try impl.checkCall(Checker, self, node, input, out);
            try @import("repetition.zig").legacyRepeatCall(Checker, self, node, input, out);
        }
        /// Check a record field read, rejecting a projection that would drop another
        /// result-bearing field.
        pub fn checkField(self: *Checker, node: ast.Node, field: @FieldType(@FieldType(ast.Node, "data"), "field"), out: *typed.Node) Error!void {
            return impl.checkField(Checker, self, node, field, out);
        }
        /// Check a bare name: a constant-length type parameter, a local read (rejecting an
        /// arena binding or a consumed owned value), or a function used as a value.
        pub fn checkName(self: *Checker, node: ast.Node, name: @FieldType(@FieldType(ast.Node, "data"), "name"), out: *typed.Node) Error!void {
            return impl.checkName(Checker, self, node, name, out, false);
        }
        /// Check a method called on a capability reached through an expression, such
        /// as a record field (`ctx.fs.read_file(path)`), with the receiver already
        /// checked. It builds the nodes the named-local spelling builds.
        pub fn checkCapabilityReceiverMethod(self: *Checker, node: ast.Node, receiver: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
            return impl.checkCapabilityReceiverMethod(Checker, self, node, receiver, temporaries);
        }
        /// Recognize `env.get(...)`, `env.only(...)` and `env.names()` on a local
        /// `Environment` binding.
        pub fn environmentMethod(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?EnvironmentMethod {
            return impl.environmentMethod(Checker, self, call);
        }
        /// The name operand of a computed `env.get(name)`, which must be checked before the call; null for a literal
        /// name and for every other call.
        pub fn environmentComputedName(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?ast.NodeId {
            return impl.environmentComputedName(Checker, self, call);
        }
        /// Whether an unqualified `replace(value, field=…)` call is the functional
        /// record update rather than the positional three-argument list intrinsic.
        /// A declared, imported or local name called `replace` keeps its own meaning.
        pub fn recordUpdateCall(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
            return impl.recordUpdateCall(Checker, self, call);
        }
        /// Recognize an unshadowed one-argument `str(...)` conversion.
        pub fn textConstructor(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!bool {
            return impl.textConstructor(Checker, self, call, span);
        }
        /// `T(x)` converts between integer widths wherever `T` names an integer type rather
        /// than a function: a declared alias, or a type parameter of the enclosing signature.
        /// The fixed-width keywords reach the same node straight from the parser.
        pub fn typeConversion(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Type {
            return impl.typeConversion(Checker, self, call);
        }
    };
}
/// Check one call against the builtin families that answer before a declared
/// callee is resolved: capability narrowing, capability methods, embedding,
/// the prelude, numeric and text conversions, file and stream helpers and the
/// checked-result constructors. Answers whether this call was one of them.
fn builtinCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    if (try checkCapabilityNarrowing(Checker, self, node, input, out)) return true;
    if (try checkNetworkHost(Checker, self, node, input, out)) return true;
    if (try checkEnvironmentDispatch(Checker, self, node, input, out)) return true;
    if (try embedBuiltin(Checker, self, input)) |kind| {
        try checkEmbed(Checker, self, node, input, kind, out);
        return true;
    }
    if (try self.cellConstructor(input)) |declaration| {
        const value = self.resolved.at(@backingInt(input.arguments[0])).?;
        const element = self.nodes.items[@backingInt(value)].ty;
        out.ty = try nominal_catalog.instantiateLengths(&self.catalog, declaration, &.{element}, &.{}, node.span);
        out.data = .{ .record = try self.allocator.dupe(typed.FieldInit, &.{.{ .index = 0, .value = value }}) };
        return true;
    }
    if (try self.checkPreludeCall(node, input, out)) return true;
    if (try self.floatIntrinsic(input)) |op| {
        try self.checkFloatIntrinsic(node, input, op, out);
        return true;
    }
    if (try self.numericConversion(input)) |target| {
        try self.checkNumericConversion(node, input, target, out);
        return true;
    }
    if (try typeConversion(Checker, self, input)) |ty_value| {
        try checkTypeConversion(Checker, self, node, input, ty_value, out);
        return true;
    }
    if (try self.optionConstructor(input)) {
        try self.checkOptionConstructor(node, input, out);
        return true;
    }
    if (try textConstructor(Checker, self, input, node.span)) {
        const value = self.resolved.at(@backingInt(input.arguments[0])).?;
        const input_type = self.nodes.items[@backingInt(value)].ty;
        const input_record = if (input_type.isAggregate()) self.catalog.records[input_type.recordIndex()] else null;
        const aggregate_scalar = if (input_record) |record| record.collection.kind == .string or std.mem.eql(u8, record.name, "float") or std.mem.eql(u8, record.name, "f32") else false;
        const scalar = input_type.isInteger() or input_type == .bool or input_type == .unit;
        try refuseHandleText(self.catalog.records, input_type, node.span, self.sink);
        if (!scalar and !aggregate_scalar) try checkTextConversion(Checker, self, input_type, node.span);
        out.ty = self.catalog.names.get("str") orelse return error.InternalError;
        out.data = .{ .cast = value };
        return true;
    }
    if (try self.fileAccessBuiltin(input)) |kind| {
        try self.checkFileAccessCall(node, input, kind, out);
        return true;
    }
    if (try self.writerFunction(input)) |kind| {
        out.* = try self.checkWriterFunction(node, input, kind);
        return true;
    }
    if (try self.preludeOptionFunction(input)) {
        try self.checkPreludeOptionFunction(node, input, out);
        return true;
    }
    if (try self.preludeCopyFunction(input)) {
        try self.checkPreludeCopy(node, input, out);
        return true;
    }
    if (try self.streamFunction(input)) |found| {
        try self.checkStreamFunction(node, input, found, out);
        return true;
    }
    if (try self.streamMethod(input)) |method| {
        try self.refuseStreamSpelling(node, input);
        if (method.write) {
            try self.checkStreamWrite(node, input, method.stream, out);
            return true;
        }
        try self.checkPrint(node, input, .{ .stream = method.stream }, out);
        return true;
    }
    if (try self.debugBuiltin(input)) {
        try self.checkPrint(node, input, .{ .sink = .stderr, .debug = true }, out);
        return true;
    }
    if (try self.outputBuiltin(input)) |sink| {
        try self.checkPrint(node, input, .{ .sink = sink }, out);
        return true;
    }
    if (byteConversion(Checker, self, input)) |conversion| {
        try checkByteConversion(Checker, self, node, input, conversion, out);
        return true;
    }
    if (try self.resultConstructor(input)) |ok| {
        try call_arguments.positional(input, self.sink);
        try self.checkResultConstructor(node, input, ok, out);
        return true;
    }
    return false;
}

fn checkField(comptime Checker: type, self: *Checker, node: ast.Node, field: @FieldType(@FieldType(ast.Node, "data"), "field"), out: *typed.Node) Error!void {
    const base = self.resolved.at(@backingInt(field.base)).?;
    const record_type = self.nodes.items[@backingInt(base)].ty;
    const field_index = try self.catalog.field(record_type, self.src, field.name, self.sink);
    // A field of a `@linear` record is read by borrowing the record, which stays obliged (D-FFI-11).
    const linear_record = typed.linear(record_type, self.catalog.records);
    for (self.catalog.records[record_type.recordIndex()].fields, 0..) |other, i| if (!linear_record and i != field_index and self.requiresHandling(other.ty)) return self.sink.failOwnership(
        .{ .code = eResultOperation, .rule = .L1 },
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
/// Resolve a nongeneric free-function value using fresh declaration and slot facts.
pub fn functionValue(comptime Checker: type, self: *Checker, name: source.Span, out: *typed.Node) Error!bool {
    const key = if (self.catalog.module_names) |names| module: {
        if (!try names.topLevel(name) and std.mem.indexOf(u8, self.src.text(name), "::") == null) return false;
        break :module try names.reference(name, .function, null, null, self.sink);
    } else self.src.text(name);
    const declaration = self.functions.get(key) orelse return false;
    const function = self.syntax.functions[@backingInt(declaration)];
    if (function.policy.owner != null or function.signature.type_parameters.len != 0) return self.sink.fail(callback_type_code, name, "function values require a nongeneric free function");
    // A supplied operation checked against each call's arguments has no one body a value could run (W10).
    if (@import("sema_supplied.zig").supplierOf(self.src, function)) |supplier| if (!supplier.valueRuns()) {
        const supplied = @import("sema_supplied.zig");
        return self.sink.fail(@import("builtin_functions.zig").function_value_code, name, try supplied.valueMessage(self.allocator, supplied.moduleOf(self.src, function), self.src.text(function.name)));
    };
    const parameters = try self.allocator.alloc(typed.Type, function.signature.parameters.len);
    if (parameters.len > 16) return self.sink.fail(callback_type_code, name, "callbacks support at most 16 parameters");
    for (function.signature.parameters, parameters) |input, *parameter| {
        parameter.* = try self.catalog.resolve(self.src, input.ty, self.sink);
    }
    const success = try self.catalog.resolve(self.src, function.signature.return_type, self.sink);
    const result = if (function.signature.failure_type) |failure| try frontend_failures.resultType(&self.catalog, self.allocator, success, try self.catalog.resolve(self.src, failure, self.sink), name, self.sink) else success;
    const expected_type = self.expected_types.get(name);
    const destination = if (expected_type) |expected| callables.signature(expected, self.catalog.records) else null;
    const implementation: typed.Callable = .{
        .labels = try callables.functionLabels(self.allocator, self.src, function.signature.parameters),
        .parameters = parameters,
        .return_type = result,
        .mutates = function.signature.mut_positions,
        .return_origin = .fresh,
        .own = try own_parameters.flags(self.allocator, function.signature.parameters),
    };
    // Ordinary function values return owned storage. Reuse an exactly matching
    // destination without adopting a different borrowing contract.
    if (destination) |slot| {
        if (callables.equal(implementation, slot)) {
            out.ty = expected_type.?;
            out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
            return true;
        }
    }
    out.ty = try callables.intern(self.allocator, &self.catalog, implementation, name, self.sink);
    out.data = .{ .function_value = self.ordinary_ids[@backingInt(declaration)] orelse return error.InternalError };
    return true;
}
const CallbackBinding = struct { call: @FieldType(@FieldType(ast.Node, "data"), "call"), parameters: []const ast.Parameter };
fn bindCallback(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), contract: typed.Callable) Error!CallbackBinding {
    if (call.type_arguments.len != 0 or call.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", call.name, "callback argument count must match its signature");
    const values = try self.allocator.alloc(ast.NodeId, call.arguments.len);
    const order = try self.allocator.alloc(usize, call.arguments.len);
    const parameters = try self.allocator.alloc(ast.Parameter, call.arguments.len);
    const filled = try self.allocator.alloc(bool, call.arguments.len);
    @memset(filled, false);
    for (parameters, 0..) |*parameter, index| parameter.* = .{
        .name = call.name,
        .ty = call.name,
        .mut = markerPositionDeclared(contract.mutates, @intCast(index)),
        .named = index < contract.labels.len and contract.labels[index].len != 0,
    };
    for (call.arguments, 0..) |argument, index| {
        const label = if (call.argument_names.len != 0) call.argument_names[index] else null;
        const target = if (label) |name| blk: {
            for (contract.labels, 0..) |candidate, position| if (candidate.len != 0 and std.mem.eql(u8, candidate, self.src.text(name))) break :blk position;
            return self.sink.fail("E_CALL_ARGUMENT", name, "keyword names no named callback parameter");
        } else index;
        if (target >= parameters.len or filled[target]) return self.sink.fail("E_CALL_ARGUMENT", call.name, "callback parameter receives more than one argument");
        if (label == null and parameters[target].named) return self.sink.fail("E_KEYWORD_ONLY", self.syntax.nodes.items[@backingInt(argument)].span, "callback parameter must be supplied by name");
        filled[target] = true;
        values[target] = argument;
        order[index] = target;
    }
    var bound = call;
    bound.arguments = values;
    bound.argument_names = &.{};
    bound.evaluation_order = order;
    return .{ .call = bound, .parameters = parameters };
}
fn indirectCall(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    const slot = try self.resolve(call.name);
    const contract = callables.signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) orelse return self.sink.fail(callback_type_code, call.name, "called local is not a function value");
    const binding = try bindCallback(Checker, self, call, contract);
    try checkMutationMarkers(Checker, self, call.name, binding.call.arguments, contract.mutates, contract.own);
    try checkTakingModeMarkers(Checker, self, call.name, binding.call.arguments, contract.own);
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    const callee: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = call.name, .ty = self.locals.items[@backingInt(slot)].ty, .data = .{ .local = slot } });
    const arguments = try self.allocator.alloc(typed.NodeId, contract.parameters.len);
    for (binding.call.arguments, contract.parameters, arguments, 0..) |input, expected, *argument, position| {
        const value = try self.expressionExpected(input, expected);
        try self.require(self.nodes.items[@backingInt(value)].ty, expected, self.syntax.nodes.items[@backingInt(input)].span);
        // A plain `@linear` parameter lends its argument only in a call by name, which checks it as a borrow.
        const plain = !own_parameters.isOwn(contract.own, position) and !markerPositionDeclared(contract.mutates, @intCast(position));
        if (plain and typed.linear(expected, self.catalog.records)) return @import("linear_rules.zig").refuse(self.sink, self.syntax.nodes.items[@backingInt(input)].span, .loan_callback);
        argument.* = value;
    }
    out.ty = contract.return_type;
    out.data = .{ .invoke = .{ .callee = callee, .arguments = arguments } };
    try (@import("call_evaluation.zig").Context{
        .storage = .{ .nodes = &self.nodes, .locals = &self.locals, .statements = &self.statements },
        .span = node.span,
        .call = binding.call,
        .parameters = binding.parameters,
    }).apply(self.allocator, &out.data.invoke);
}

/// Check a bare name: a constant-length type parameter, a local read (rejecting an
/// arena binding or a consumed owned value), or a function used as a value.
/// A list inspection reads its storage without acknowledging pending Results.
pub fn checkBorrowedName(comptime Checker: type, self: *Checker, node: ast.Node, name: source.Span, out: *typed.Node) Error!void {
    return checkName(Checker, self, node, name, out, true);
}
/// One read of a local whose type may be `@linear`.
const LinearRead = struct { local: typed.Local, name: source.Span, borrowing: bool, text: []const u8 };

/// A `@linear` owner read after it was consumed, or a lent (`mut` parameter) or loaned (plain parameter) owner read as a
/// move, is refused (D-FFI-11, decision LINEAR-LEND).
fn refuseLinearRead(sink: *diagnostic.Sink, allocator: std.mem.Allocator, records: []const typed.Record, read: LinearRead) Error!void {
    const rules = @import("linear_rules.zig");
    if (!typed.linear(read.local.ty, records)) return;
    if (!read.local.ownership.transfer_available) {
        // A `match mut` binding names the matched place, which keeps the owner: a borrowing read (a field read, a
        // `mut` argument) leaves it there, as `.match_lent` says; only a move out of it is refused (FX8).
        if (rules.matchLent(read.local)) return if (read.borrowing) {} else rules.refuse(sink, read.name, .match_lent);
        return rules.consumed(sink, allocator, read.name, read.text, read.local.ownership.transfer_span);
    }
    if (!read.borrowing and rules.lent(read.local)) return rules.refuse(sink, read.name, .lent);
    if (!read.borrowing and rules.loan(read.local)) return rules.refuse(sink, read.name, .loan);
}
/// A field default is built wherever its record is: read a text constant's literal in place rather than call a getter
/// the constructing function's module may not link to. A joined constant is read as the one literal it folds to (F-54).
fn constantDefaultRead(comptime Checker: type, self: *Checker, constants: @import("constant_values.zig").Context, index: usize, literal_ty: typed.Type, out: *typed.Node) Error!void {
    const span = out.span;
    if (try constants.foldedText(index)) |octets| {
        defer self.sink.allocator.free(octets);
        out.* = self.nodes.items[@backingInt(try self.foldedTextNode(span, octets, literal_ty))];
        return;
    }
    out.* = self.nodes.items[@backingInt(try self.expressionExpected(constants.initializerNode(index), literal_ty))];
    out.span = span;
}
/// A bare name that is no local and no constant of this module, which a module the file imports declares as a constant or a function
/// (`LIMIT` after `import util`): `E_UNKNOWN_NAME` that names the module and the spelling, and writes the qualifier when one module
/// declares it. Returns for any other name, which `resolve` then refuses as it always did.
fn refuseImportedName(comptime Checker: type, self: *Checker, name: source.Span) Error!void {
    const names = self.catalog.module_names orelse return;
    const answer = (try names.importedAnswer(name)) orelse return;
    const message = try std.fmt.allocPrint(self.allocator, "name is not defined in this scope; {s}", .{answer.sentence});
    const qualifier = answer.qualifier orelse return self.sink.fail("E_UNKNOWN_NAME", name, message);
    if (!@import("interfaces.zig").Index.bareAt(self.src.bytes, name.start, self.src.text(name))) return self.sink.fail("E_UNKNOWN_NAME", name, message);
    return self.sink.failFix("E_UNKNOWN_NAME", name, message, .{ .span = .{ .start = name.start, .end = name.start }, .text = qualifier });
}
fn checkName(comptime Checker: type, self: *Checker, node: ast.Node, name: @FieldType(@FieldType(ast.Node, "data"), "name"), out: *typed.Node, borrowing: bool) Error!void {
    if (self.constant_default == 0) if (self.current_function) |id| {
        const key = self.instance_keys.items[@backingInt(id)];
        for (self.syntaxFunction(id).signature.type_parameters, 0..) |parameter, index| {
            if (!parameter.constant_length or !std.mem.eql(u8, self.src.text(parameter.name), self.src.text(name))) continue;
            out.ty = .u64;
            out.data = .{ .integer = key.length(index) orelse return error.InternalError };
            return;
        }
    };
    if (!self.active.contains(self.src.text(name))) {
        try self.refuseHiddenPath(name);
        const constants: @import("constant_values.zig").Context = .{ .src = self.src, .program = self.syntax, .names = self.catalog.module_names, .sink = self.sink, .catalog = self.catalog };
        if (try constants.lookup(name)) |index| {
            // A str/bytes literal constant still needs its getter call, but a
            // scalar constant is a compile-time value: fold it to a literal at
            // each use so no guest call remains.
            if (try constants.literalType(index)) |literal_ty| {
                if (self.constant_default != 0) return constantDefaultRead(Checker, self, constants, index, literal_ty, out);
                out.ty = literal_ty;
                out.data = .{ .call = .{ .function = self.ordinary_ids[index] orelse return error.InternalError, .arguments = &.{} } };
                return;
            }
            out.* = try self.constantNode(try constants.evaluate(index), node.span);
            return;
        }
    }
    if (!self.active.contains(self.src.text(name)) and try functionValue(Checker, self, name, out)) return;
    if (!self.active.contains(self.src.text(name))) if (self.current_lambda) |lambda_index| {
        if (self.lambda_captures[lambda_index]) |captures| for (captures) |capture| {
            if (!std.mem.eql(u8, capture.name, self.src.text(name))) continue;
            const message = try std.fmt.allocPrint(self.allocator, "lambda cannot capture local `{s}`; use a top-level function or pass the value as an explicit state parameter", .{capture.name});
            return self.sink.fail("E_LAMBDA_CAPTURE", name, message);
        };
    };
    if (!self.active.contains(self.src.text(name))) try refuseImportedName(Checker, self, name);
    const slot = try self.resolve(name);
    try @import("sema_tasks.zig").refuseEscape(Checker, self, slot, name);
    try self.requireReadable(slot, name);
    if (self.transfers(self.locals.items[@backingInt(slot)].ty)) {
        const local = &self.locals.items[@backingInt(slot)];
        try refuseLinearRead(self.sink, self.allocator, self.catalog.records, .{ .local = local.*, .name = name, .borrowing = borrowing, .text = self.src.text(name) });
        const lent_place = borrowing and typed.linear(local.ty, self.catalog.records) and @import("linear_rules.zig").matchLent(local.*);
        const obliged = self.requiresHandling(local.ty) and !local.ownership.transfer_available;
        if (obliged and !lent_place) return self.sink.failOwnershipTransfer(
            .{ .code = "E_RESULT_CONSUMED", .rule = .L1 },
            name,
            local.declaration,
            local.ownership.transfer_span,
        );
        // L16: a `mut` argument is an exclusive borrow, resources included, so
        // the caller's binding stays usable after the line (FR-203). A borrow
        // of any other type never transfers, and a pending Result list keeps its
        // obligation for the same reason.
        const borrowed_resource = borrowing and (typed.moveOnly(local.ty, self.catalog.records) or typed.linear(local.ty, self.catalog.records));
        const pending_list = @import("record_layouts.zig").pendingList(self.catalog.records, local.ty);
        const keeps_obligation = borrowing and pending_list;
        if (!borrowed_resource and !keeps_obligation) {
            local.ownership.transfer_available = false;
            local.ownership.transfer_span = name;
        }
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
/// An unshadowed `embed_bytes(...)` or `embed_str(...)` call: the bare builtin
/// answers only when no binding, declaration or module name claims it.
fn embedBuiltin(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?embed.Kind {
    if (call.owner != null or call.type_arguments.len != 0) return null;
    const name = self.src.text(call.name);
    const kind = embed.kindOf(name) orelse return null;
    if (self.active.contains(name) or self.functions.contains(name)) return null;
    if (self.catalog.module_names) |names| if (try names.topLevel(call.name)) return null;
    return kind;
}
/// `embed_bytes("path")` and `embed_str("path")`: static `bytes` or `str` data
/// the loader read at compile time, so the call has no operands and no effect.
fn checkEmbed(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), kind: embed.Kind, out: *typed.Node) Error!void {
    const file = try embed.check(.{ .scratch = self.allocator, .src = self.src, .nodes = self.syntax.nodes.items, .sink = self.sink }, call, kind, node.span);
    out.ty = try collections.preludeType(&self.catalog, if (kind == .bytes) "bytes" else "str", node.span);
    out.data = .{ .blob = .{ .digest = file.digest, .length = file.contents.len } };
}
/// Python-spelled byte-string and octet-buffer constructors that are not
/// ordinary function calls. `bytes(values)` builds from a `list[int]`,
/// `bytes(buffer)` copies an octet buffer into an immutable byte string,
/// `bytes.fromhex(s)` decodes hexadecimal text and `byte_buffer(values)`
/// builds the mutable buffer that the in-place append functions accept.
const ByteConversion = enum { from_list, from_hex, buffer_from_list };
fn byteConversion(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?ByteConversion {
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
fn checkByteConversion(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), conversion: ByteConversion, out: *typed.Node) Error!void {
    const value = self.resolved.at(@backingInt(call.arguments[0])).?;
    const input_type = self.nodes.items[@backingInt(value)].ty;
    const schema = if (input_type.isAggregate()) self.catalog.records[input_type.recordIndex()] else null;
    if (conversion == .from_hex) {
        if (schema == null or schema.?.collection.kind != .string) return self.sink.fail(eByteConversion, node.span, "bytes.fromhex requires a str argument");
        out.* = try (collections.Builder(Checker){ .checker = self, .span = node.span }).access(value, .from_hex, &.{}, false);
        return;
    }
    const integer_list = schema != null and schema.?.managed and schema.?.collection.kind == .list and schema.?.shape.buffer == .i64;
    if (conversion == .buffer_from_list) {
        if (!integer_list) return self.sink.fail(eByteConversion, node.span, "byte_buffer() requires an int[] argument");
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
    if (!integer_list) return self.sink.fail(eByteConversion, node.span, "bytes() requires an int[] or byte_buffer argument");
    out.ty = self.catalog.names.get("bytes") orelse return error.InternalError;
    out.data = .{ .cast = value };
}
fn textConstructor(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call"), span: source.Span) Error!bool {
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
fn typeConversion(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!?typed.Type {
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
fn checkTypeConversion(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), ty_value: typed.Type, out: *typed.Node) Error!void {
    const value = self.resolved.at(@backingInt(call.arguments[0])).?;
    try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
    out.ty = ty_value;
    out.data = .{ .cast = value };
}
/// The receiver of one capability method: a capability local named at the call
/// (`fs.read_file(p)`), or an expression already checked as the receiver, such as
/// a record field (`ctx.fs.read_file(p)`). Both build the same checked nodes.
const Receiver = union(enum) {
    local: struct { slot: typed.LocalId, owner: source.Span },
    checked: typed.NodeId,
};
/// The checked node of one capability receiver. A named local is confirmed
/// readable, counted as read and read back as a `local` node; an expression was
/// checked, and counted, when the call's receiver was.
fn receiverNode(comptime Checker: type, self: *Checker, receiver: Receiver, ty: typed.Type) Error!typed.NodeId {
    const named = switch (receiver) {
        .checked => |node| return node,
        .local => |local| local,
    };
    try self.requireReadable(named.slot, named.owner);
    self.locals.items[@backingInt(named.slot)].usage.reads += 1;
    const node: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = named.owner, .ty = ty, .data = .{ .local = named.slot } });
    return node;
}
/// The Python `Environment` surface reached through a capability value.
const EnvironmentMethod = enum { get, only, names };
/// Recognize `env.get(...)`, `env.only(...)` and `env.names()` on a local
/// `Environment` binding.
fn environmentMethod(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?EnvironmentMethod {
    const owner = call.owner orelse return null;
    const slot = self.active.get(self.src.text(owner)) orelse return null;
    if (self.locals.items[@backingInt(slot)].ty != .environment_cap) return null;
    const name = self.src.text(call.name);
    if (std.mem.eql(u8, name, "get")) return .get;
    if (std.mem.eql(u8, name, "only")) return .only;
    if (std.mem.eql(u8, name, "names")) return .names;
    return null;
}
/// The name operand of an `env.get(name)` whose name is a computed `str` rather than a literal, which the expression
/// queue must check before the call itself; null for a literal name, for `only` and `names`, and for a malformed call.
fn environmentComputedName(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?ast.NodeId {
    if (call.arguments.len != 1 or call.type_arguments.len != 0 or call.argument_names.len != 0) return null;
    if (!std.mem.eql(u8, self.src.text(call.name), "get")) return null;
    return if (self.syntax.nodes.items[@backingInt(call.arguments[0])].data == .text) null else call.arguments[0];
}
/// `env.get(name) -> Option[str]`. A literal name is materialized as a fixed `[N]u8` request, so its bytes are known
/// to the checker; any other `str` is passed as the value it is, and the runtime polices its octets: a name outside
/// the allow-list or the `env.only` scope traps `R_CAPABILITY`, and an empty name, one holding NUL or `=`, or one over
/// 255 octets answers `None`. Either way the checked `environment_get` node has an Option result, so the native
/// boundary answers `Some(text)` or `None`.
fn checkEnvironmentGet(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0 or call.arguments.len != 1) return self.sink.fail("E_ARITY", node.span, "env.get takes one name");
    const spelling = self.syntax.nodes.items[@backingInt(call.arguments[0])];
    var name: typed.NodeId = undefined;
    if (spelling.data == .text) {
        const bytes = spelling.data.text;
        const name_type = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, spelling.span, self.sink);
        const values = try self.byteValues(bytes, spelling.span);
        name = @fromBackingInt(self.nodes.items.len);
        try self.nodes.append(self.allocator, .{ .span = spelling.span, .ty = name_type, .data = .{ .array = values } });
    } else {
        name = self.resolved.at(@backingInt(call.arguments[0])) orelse return error.InternalError;
        const text = try collections.preludeType(&self.catalog, "str", node.span);
        try self.require(self.nodes.items[@backingInt(name)].ty, text, spelling.span);
    }
    const capability = try receiverNode(Checker, self, receiver, .environment_cap);
    const element = try collections.preludeType(&self.catalog, "str", node.span);
    out.ty = try collections.optionType(&self.catalog, element, node.span);
    out.data = .{ .environment_get = .{ .capability = capability, .name = name } };
}
/// `env.only("HOME", "PATH") -> Environment`: register the literal names as a
/// NUL-separated scope blob and return a narrowed capability value. It performs
/// no I/O and contributes no effect.
fn checkEnvironmentOnly(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
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
    const capability = try receiverNode(Checker, self, receiver, .environment_cap);
    out.ty = .environment_cap;
    out.data = .{ .environment_only = .{ .capability = capability, .names = names } };
}
/// `env.names() -> list[str]`: enumerate the visible environment names as a
/// fresh managed list. It reads host environment state and contributes the
/// `environment` effect.
fn checkEnvironmentNames(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
    try call_arguments.positional(call, self.sink);
    if (call.type_arguments.len != 0 or call.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "env.names takes no arguments");
    const capability = try receiverNode(Checker, self, receiver, .environment_cap);
    const text = try collections.preludeType(&self.catalog, "str", node.span);
    out.ty = try collections.listType(&self.catalog, text, node.span);
    out.data = .{ .environment_names = capability };
}
/// Check `fs.read_only()`: the same `Filesystem` with only the read permission.
fn checkReadOnly(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
    if (input.type_arguments.len != 0 or input.arguments.len != 0) return self.sink.fail("E_ARITY", node.span, "read_only takes no arguments");
    const value = try receiverNode(Checker, self, receiver, .filesystem_cap);
    out.ty = .filesystem_cap;
    out.data = .{ .restrict_resource = .{ .permissions = external_resources.permissionBit(.read), .value = value } };
}
/// `fs.read_only()` and `fs.dir(path)` on a local `Filesystem`. Returns false
/// when the call is not one of them and the ordinary call path should run.
fn checkCapabilityNarrowing(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    const owner = input.owner orelse return false;
    const slot = self.active.get(self.src.text(owner)) orelse return false;
    if (self.locals.items[@backingInt(slot)].ty == .input_cap) {
        const kind = self.fileAccessMethodKind(input) orelse return false;
        try self.checkFileAccessMethod(node, input, kind, out);
        return true;
    }
    if (self.locals.items[@backingInt(slot)].ty != .filesystem_cap) return false;
    const name = self.src.text(input.name);
    const receiver: Receiver = .{ .local = .{ .slot = slot, .owner = owner } };
    if (std.mem.eql(u8, name, read_only_method)) {
        try checkReadOnly(Checker, self, node, input, receiver, out);
        return true;
    }
    if (std.mem.eql(u8, name, dir_method)) {
        try checkDirCall(Checker, self, node, input, receiver, out);
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
fn checkNetworkHost(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    const owner = input.owner orelse return false;
    const slot = self.active.get(self.src.text(owner)) orelse return false;
    if (self.locals.items[@backingInt(slot)].ty != .network_cap) return false;
    if (!std.mem.eql(u8, self.src.text(input.name), host_method)) return false;
    try checkHostCall(Checker, self, node, input, .{ .local = .{ .slot = slot, .owner = owner } }, out);
    return true;
}
/// Check `net.host(name)`: a `Network` receiver and one literal endpoint that
/// becomes the sole endpoint every acquisition through the derived value may
/// request. A dynamic name is `E_NETWORK_HOST`.
fn checkHostCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
    if (input.type_arguments.len != 0 or input.arguments.len != 1 or input.argument_names.len != 0) return self.sink.fail("E_ARITY", node.span, "host takes one endpoint argument");
    const argument = self.syntax.nodes.items[@backingInt(input.arguments[0])];
    const bytes = switch (argument.data) {
        .text, .bytes => |spelling| spelling,
        else => return self.sink.fail(eNetworkHost, argument.span, network_host_literal_message),
    };
    if (bytes.len == 0 or std.mem.indexOfScalar(u8, bytes, 0) != null) return self.sink.fail(eNetworkHost, argument.span, "host endpoint must be a nonempty str without NUL");
    const capability = try receiverNode(Checker, self, receiver, .network_cap);
    const name_type = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, argument.span, self.sink);
    const values = try self.byteValues(bytes, argument.span);
    const name: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = argument.span, .ty = name_type, .data = .{ .array = values } });
    out.ty = .network_cap;
    out.data = .{ .host_resource = .{ .capability = capability, .name = name } };
}
/// Check one `Environment` method against its receiver.
fn checkEnvironmentMethod(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), method: EnvironmentMethod, receiver: Receiver, out: *typed.Node) Error!void {
    switch (method) {
        .get => try checkEnvironmentGet(Checker, self, node, input, receiver, out),
        .only => try checkEnvironmentOnly(Checker, self, node, input, receiver, out),
        .names => try checkEnvironmentNames(Checker, self, node, input, receiver, out),
    }
}
/// Dispatch `env.get`, `env.only` and `env.names` on a local `Environment`.
fn checkEnvironmentDispatch(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    const method = environmentMethod(Checker, self, input) orelse return false;
    const owner = input.owner.?;
    const receiver: Receiver = .{ .local = .{ .slot = self.active.get(self.src.text(owner)).?, .owner = owner } };
    try checkEnvironmentMethod(Checker, self, node, input, method, receiver, out);
    return true;
}
/// How `Clock`, `Entropy`, `Process` and `Stop` are read: each has no methods, and a standard module's function answers.
const clock_reading: library_function_form.Reading = .{ .type_name = "Clock", .verb = "read it with", .module = "time", .function = "now", .parameter = "clock" };
const entropy_reading: library_function_form.Reading = .{ .type_name = "Entropy", .verb = "read it with", .module = "random", .function = "from_entropy", .parameter = "entropy" };
const process_reading: library_function_form.Reading = .{ .type_name = "Process", .verb = "start a program with", .module = "process", .function = "run", .parameter = "proc", .more = ", request" };
const stop_reading: library_function_form.Reading = .{ .type_name = "Stop", .verb = "read it with", .module = "process", .function = "stop_requested", .parameter = "stop" };
const registers_reading: library_function_form.Reading = .{ .type_name = "Registers", .verb = "read one with", .module = "registers", .function = "read32", .parameter = "reg", .more = ", address" };
/// The reading of a capability type that has no methods and a module function in their place, or null for the others.
fn capabilityReading(ty: typed.Type) ?library_function_form.Reading {
    return switch (ty) {
        .clock_cap => clock_reading,
        .random_cap => entropy_reading,
        .process_cap => process_reading,
        .stop_cap => stop_reading,
        .registers_cap => registers_reading,
        else => null,
    };
}
/// Methods a capability type answers when reached through an expression,
/// for the message an unknown one gets.
fn capabilityMethods(ty: typed.Type) []const u8 {
    return switch (ty) {
        .filesystem_cap => "a Filesystem has the methods open, read_file, read_text, write_file, write_text, exists, listdir, mkdir, remove, read_only and dir",
        .network_cap => "a Network has the method host",
        .environment_cap => "an Environment has the methods get, only and names",
        .clock_cap => library_function_form.describe(clock_reading),
        .random_cap => library_function_form.describe(entropy_reading),
        .process_cap => library_function_form.describe(process_reading),
        .input_cap => "an Input has the methods read, read_exact, read_line and read_into",
        .stop_cap => library_function_form.describe(stop_reading),
        .registers_cap => library_function_form.describe(registers_reading),
        else => "this capability has no methods",
    };
}
/// The capability methods of `Filesystem`, `Network` and `Environment` on a
/// receiver reached through an expression (`ctx.fs.read_file(path)`,
/// `pair.env.get("HOME")`, `make_fs().dir("data")`), which the parser hands over
/// as a method call. The receiver is already checked, so only the arguments
/// still need it; each method checks and lowers exactly like its named-local
/// spelling, so the same effects, grants and capability rules apply. `Clock`,
/// `Entropy` and `Host` have no methods and an unknown name is
/// `E_COLLECTION_METHOD` listing the receiver's own.
fn checkCapabilityReceiverMethod(comptime Checker: type, self: *Checker, node: ast.Node, receiver: typed.NodeId, temporaries: []const typed.Type) Error!typed.Node {
    const method = node.data.method_call;
    const name = self.src.text(method.name);
    const receiver_type = self.nodes.items[@backingInt(receiver)].ty;
    const call: @FieldType(@FieldType(ast.Node, "data"), "call") = .{ .name = method.name, .arguments = method.arguments, .argument_names = method.argument_names };
    const known = switch (receiver_type) {
        .filesystem_cap => std.mem.eql(u8, name, read_only_method) or std.mem.eql(u8, name, dir_method) or if (file_operations.access(name)) |kind| !kind.isInput() else false,
        .input_cap => if (file_operations.access(name)) |kind| kind.isInput() else false,
        .network_cap => std.mem.eql(u8, name, host_method),
        .environment_cap => std.meta.stringToEnum(EnvironmentMethod, name) != null,
        else => false,
    };
    if (!known and receiver_type == .input_cap and std.mem.eql(u8, name, "read_into"))
        return self.sink.fail(eCollectionMethod, method.name, "read_into needs the Input bound to a name: `const stdin = holder.input`, then `stdin.read_into(mut buffer, max)`");
    if (!known) {
        // FR37: a Clock, Entropy, Process or Stop is told the module function with the receiver's own text, and a repair when the
        // method written is that function's name and the receiver is a plain field path.
        const site: call_arguments.MethodSite = .{ .receiver = self.syntax.nodes.items[@backingInt(method.base)].span, .name = method.name, .arguments = method.arguments, .names = method.argument_names };
        const answer: ?library_function_form.Answer = if (capabilityReading(receiver_type)) |reading| try self.capabilityReceiverAnswer(reading, site, node.span) else null;
        const told = if (answer) |found| found.message else capabilityMethods(receiver_type);
        const message = try std.fmt.allocPrint(self.allocator, "unknown method for a {s} receiver; {s}", .{ prelude.reservedTypeName(receiver_type) orelse "capability", told });
        return self.sink.failRepaired(eCollectionMethod, method.name, message, if (answer) |found| found.fix else null);
    }
    var out: typed.Node = .{ .span = node.span, .ty = .unit, .data = .unit };
    const checked: Receiver = .{ .checked = receiver };
    switch (receiver_type) {
        .filesystem_cap => if (std.mem.eql(u8, name, read_only_method)) {
            try checkReadOnly(Checker, self, node, call, checked, &out);
        } else if (std.mem.eql(u8, name, dir_method)) {
            try checkDirCall(Checker, self, node, call, checked, &out);
        } else {
            for (method.arguments) |argument| _ = try self.expressionWithTemporaries(argument, temporaries);
            try self.checkFileAccessOn(node, call, file_operations.access(name).?, receiver, &out);
        },
        .network_cap => try checkHostCall(Checker, self, node, call, checked, &out),
        .input_cap => {
            for (method.arguments) |argument| _ = try self.expressionWithTemporaries(argument, temporaries);
            try self.checkFileAccessOn(node, call, file_operations.access(name).?, receiver, &out);
        },
        else => {
            if (environmentComputedName(Checker, self, call)) |argument| _ = try self.expressionWithTemporaries(argument, temporaries);
            try checkEnvironmentMethod(Checker, self, node, call, std.meta.stringToEnum(EnvironmentMethod, name).?, checked, &out);
        },
    }
    return out;
}
/// Whether an unqualified `replace(value, field=…)` call is the functional
/// record update rather than the positional three-argument list intrinsic.
/// A declared, imported or local name called `replace` keeps its own meaning.
fn recordUpdateCall(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!bool {
    if (call.owner != null or call.argument_names.len == 0 or callCarriesMutMarker(Checker, self, call)) return false;
    if (!std.mem.eql(u8, self.src.text(call.name), "replace")) return false;
    if (self.active.contains(self.src.text(call.name))) return false;
    return !try self.topLevel(call.name);
}
/// Check `replace(record, field=value, …)` into the existing checked update
/// node: the base is an aggregate record and only the named fields change.
fn checkRecordUpdate(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    const base = self.resolved.at(@backingInt(input.arguments[0])).?;
    const record_type = self.nodes.items[@backingInt(base)].ty;
    if (!record_type.isAggregate() or !self.catalog.records[record_type.recordIndex()].isRecord())
        return self.sink.fail("E_TYPE", input.name, "replace(...) needs a record value; the positional form replaces a list index");
    const initializers = try self.allocator.alloc(ast.FieldInit, input.arguments.len - 1);
    for (input.arguments[1..], 0..) |value, index| initializers[index] = .{ .name = input.argument_names[index + 1].?, .value = value };
    out.ty = record_type;
    try @import("sealed_rules.zig").checkHere(Checker, self, .replace, record_type, node.span);
    out.data = .{ .update = .{ .base = base, .fields = try self.fields(record_type, initializers, false, node.span) } };
}
fn callReturnType(comptime Checker: type, self: *Checker, function: typed.FunctionId, signature: ast.Function, success: typed.Type) Error!typed.Type {
    const failure = signature.signature.failure_type orelse return success;
    return frontend_failures.resultType(&self.catalog, self.allocator, success, try self.functionType(function, failure), signature.name, self.sink);
}
const SortInput = struct { node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId };
fn checkWritableSort(comptime Checker: type, self: *Checker, input: SortInput, out: *typed.Node) Error!void {
    if (!self.locals.items[@backingInt(input.slot)].mutable) return self.sink.failOwnership(.{ .code = eImmutable, .rule = .B1 }, input.call.owner.?, "sorting requires a writable collection binding");
    self.option_facts.forget(@backingInt(input.slot));
    return self.checkListSort(input.node, input.call, input.slot, out);
}

/// `math.sqrt` takes a float. A Simd argument is refused with the certain repair `simd.sqrt`, which takes the
/// square root of each lane (SIMD-SQRT-1); the repair spells the same argument.
fn refuseMathSqrtOfVector(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
    // The qualified spelling is an owner and a name, or the whole `math.sqrt` text with no owner.
    const is_math_sqrt = if (input.owner) |owner|
        std.mem.eql(u8, self.src.text(owner), "math") and std.mem.eql(u8, self.src.text(input.name), "sqrt")
    else
        std.mem.eql(u8, self.src.text(input.name), "math.sqrt");
    if (!is_math_sqrt or input.arguments.len != 1 or self.active.contains("math")) return;
    const checked = self.resolved.at(@backingInt(input.arguments[0])) orelse return;
    if (@import("numeric_surface.zig").vectorShape(self.nodes.items[@backingInt(checked)].ty, self.catalog.records) == null) return;
    const argument_text = self.src.text(self.syntax.nodes.items[@backingInt(input.arguments[0])].span);
    const text = try std.fmt.allocPrint(self.allocator, "simd.sqrt({s})", .{argument_text});
    return self.sink.failFix("E_TYPE", node.span, "math.sqrt takes a float; simd.sqrt takes the square root of each lane of a Simd value", .{ .span = node.span, .text = text });
}
/// `lists.contains(values, value)` takes a list. Text, bytes, a set or a dictionary as its first argument cannot be
/// inferred as one (`E_GENERIC_INFERENCE`, as before), and the refusal says what to write: the operator `in`
/// (`contains_removed.refuseListsContains`). A call that names its type arguments, or whose first argument is a list or
/// anything else, is not read here.
fn refuseListsContainsOfCollection(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), target: anytype) Error!void {
    const call = target.call;
    if (call.type_arguments.len != 0 or call.arguments.len != 2) return;
    if (!contains_removed.isListsContains(self.src, self.syntax.functions[@backingInt(target.declaration)])) return;
    const first = self.resolved.at(@backingInt(call.arguments[0])) orelse return;
    const kind = contains_removed.receiverOf(self.catalog.records, self.nodes.items[@backingInt(first)].ty) orelse return;
    if (kind == .list) return;
    return contains_removed.refuseListsContains(self.allocator, self.src, self.sink, kind, .{
        .span = node.span,
        .start = if (input.owner) |owner| owner.start else input.name.start,
        .name_end = input.name.end,
    });
}
/// A resolved call of a supplied home: its declaration and specialization, how many arguments the source wrote, and
/// whether a `byte_buffer` was lent where the declaration reads `bytes`.
const ResolvedHome = struct {
    declaration: @import("generic_instances.zig").DeclarationId,
    function: typed.FunctionId,
    written: usize,
    lent_buffer: bool,
};

/// Answer a resolved call of a supplied home with its operation, or null when the operation does not take it. A call
/// that left trailing bounds to their defaults is the row of the count it wrote (W13-Q3), and the declared result is
/// checked against what the operation answers at every resolved call, so a declaration that disagrees with its
/// operation fails where it is used, not silently (W10); a lent buffer answers its own method's result (W13-Q5).
fn answerResolvedHome(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), supplier: @import("builtin_functions.zig").Supplier, home: ResolvedHome) Error!?typed.Node {
    var answered = call;
    var row = supplier;
    if (supplied_calls.writtenHome(self.src, self.syntax.functions[@backingInt(home.declaration)], call, home.written)) |written| {
        answered.arguments = written.arguments;
        row = .{ .home = written.row };
    }
    const checked = try supplied_calls.answer(Checker, self, node, answered, row, &.{}) orelse return null;
    const signature = self.syntaxFunction(home.function);
    const declared = try callReturnType(Checker, self, home.function, signature, try self.functionType(home.function, signature.signature.return_type));
    if (!home.lent_buffer) try supplied_calls.requireDeclaredResult(self.src, signature, checked.ty, declared, node.span, self.sink);
    return checked;
}

/// A standard module's own call of one of its homes, written bare and positionally (`add(mut values, copy(value))`
/// inside `sets.include`), is the operation, checked as the module-qualified spelling a program writes is
/// (`recognizedHomeCall`): no instance of the generic declaration is made. A module cannot import itself, so this is
/// the library's one spelling of such a call, and an instance per call would be checked again on every check of every
/// program that reaches it (W13, slice 3). An alias, a re-export or keyword arguments keep the declared signature's check.
fn answerOwnModuleHome(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), target: anytype, supplier: @import("builtin_functions.zig").Supplier) Error!?typed.Node {
    if (input.type_arguments.len != 0 or input.argument_names.len != 0 or input.owner != null) return null;
    if (std.mem.indexOfScalar(u8, self.src.text(input.name), '.') != null) return null;
    const call = target.call;
    const function = self.syntax.functions[@backingInt(target.declaration)];
    const declared = self.src.originalSpan(function.name) catch return null;
    const written_at = self.src.originalSpan(input.name) catch return null;
    if (declared.input != written_at.input) return null;
    var answered = call;
    var row = supplier;
    if (supplied_calls.writtenHome(self.src, function, call, input.arguments.len)) |written| {
        answered.arguments = written.arguments;
        row = .{ .home = written.row };
    }
    return supplied_calls.answer(Checker, self, node, answered, row, &.{});
}

fn checkCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    // `mut` belongs to a call's parameter modes. `own` is an expression marker,
    // so constructors and builtins retain it on their ordinary typed operands.
    if (@import("sema_simd.zig").isLaneCall(Checker, self, input)) return @import("sema_simd.zig").check(Checker, self, node, input, out);
    try refuseMathSqrtOfVector(Checker, self, node, input);
    if (try self.floatFma(input)) |narrow| return self.checkFloatFma(node, input, narrow, out);
    if (try self.byteRead(input)) |read| return self.checkByteRead(node, input, read, out);
    if (self.listSortOwner(input)) |slot| return checkWritableSort(Checker, self, .{ .node = node, .call = input, .slot = slot }, out);
    const mut_marker = callCarriesMutMarker(Checker, self, input);
    const own_marker = callCarriesOwnMarker(Checker, self, input);
    const markers_present = mut_marker or own_marker;
    // Wave 3's scalar text helpers are recognised by their qualified spelling
    // before ordinary resolution, and lower to the operation the old form used.
    if (try text_scalar.attempt(Checker, self, node, input, out)) return;
    // The writing prelude functions own their marker, so they are recognized before
    // the marker gate below routes every other marked call to a declared callee.
    if (markers_present) if (try self.writerFunction(input)) |kind| {
        out.* = try self.checkWriterFunction(node, input, kind);
        return;
    };
    // `take(mut place)` and `exchange(mut place, value)` write their place the same way, so a `mut`-marked call is theirs.
    if (mut_marker) if (try sema_exchange.spelling(Checker, self, input)) |name| {
        out.* = try sema_exchange.check(Checker, self, node, input, name);
        return;
    };
    if (try checkInputReadInto(Checker, self, node, input, out)) return;
    if (!mut_marker and try builtinCall(Checker, self, node, input, out)) return;
    if (try recordUpdateCall(Checker, self, input)) return checkRecordUpdate(Checker, self, node, input, out);
    if (input.owner == null and self.active.contains(self.src.text(input.name)))
        return indirectCall(Checker, self, node, input, out);
    const target = try self.callDeclaration(input, node.span);
    const call = target.call;
    // A `builtin func` reached by an alias, a re-export or keyword arguments is its operation (W10). A lane operation
    // and a scalar helper check their own arguments; a home is checked against the declared signature first, below.
    const supplied = @import("sema_supplied.zig").supplierOf(self.src, self.syntax.functions[@backingInt(target.declaration)]);
    if (supplied) |supplier| switch (supplier) {
        .lane => if (try @import("sema_supplied.zig").answer(Checker, self, node, call, supplier, &.{})) |checked| {
            out.* = checked;
            return;
        },
        .scalar => if (try @import("sema_supplied.zig").answer(Checker, self, node, input, supplier, &.{})) |checked| {
            out.* = checked;
            return;
        },
        .home => if (try answerOwnModuleHome(Checker, self, node, input, target, supplier)) |checked| {
            out.* = checked;
            return;
        },
        .parallel, .testing, .json, .registers => {},
    };
    try refuseListsContainsOfCollection(Checker, self, node, input, target);
    const function = try self.specialize(target.declaration, call, node.span);
    const signature = self.syntaxFunction(function);
    try warnDeprecated(Checker, self, function, input);
    const own_modes = try own_parameters.flags(self.allocator, signature.signature.parameters);
    if (!mutFootprintRejected(Checker, self, function)) try checkMutationMarkers(Checker, self, call.name, call.arguments, signature.signature.mut_positions, own_modes);
    try checkTakingModeMarkers(Checker, self, call.name, call.arguments, own_modes);
    var arguments: std.ArrayList(typed.NodeId) = .empty;
    // A `bytes` read lends a `byte_buffer` argument to its operation (W13-Q5), which then answers what the buffer's own
    // method answers; its declared result names the `bytes` answer, so that comparison is not made for a lent buffer.
    var lent_buffer = false;
    for (call.arguments, signature.signature.parameters) |arg, parameter| {
        const argument = self.syntax.nodes.items[@backingInt(arg)];
        const value = self.resolved.at(@backingInt(arg)).?;
        const expected = try self.functionType(function, parameter.ty);
        const actual = self.nodes.items[@backingInt(value)].ty;
        try requireLoanArgument(Checker, self, .{ .argument = arg, .value = value, .expected = expected, .plain = !parameter.own and !parameter.mut, .siblings = call.arguments });
        const lent = if (supplied) |supplier| supplied_calls.lendsBuffer(supplier, actual, expected, self.catalog.records) else false;
        if (!lent) try self.requireNode(value, expected, argument.span, argument.span);
        lent_buffer = lent_buffer or lent;
        try arguments.append(self.allocator, value);
    }
    try warnDuplicateSpelling(Checker, self, input, self.syntax.functions[@backingInt(target.declaration)], arguments.items);
    try @import("sema_tasks.zig").checkMapArguments(Checker, self, call);
    if (supplied) |supplier| if (supplier == .home) {
        const home: ResolvedHome = .{ .declaration = target.declaration, .function = function, .written = input.arguments.len, .lent_buffer = lent_buffer };
        if (try answerResolvedHome(Checker, self, node, call, supplier, home)) |checked| {
            out.* = checked;
            return;
        }
    };
    const success = try self.functionType(function, signature.signature.return_type);
    out.ty = try callReturnType(Checker, self, function, signature, success);
    out.data = .{ .call = .{ .function = function, .arguments = try arguments.toOwnedSlice(self.allocator) } };
    try (@import("call_evaluation.zig").Context{
        .storage = .{ .nodes = &self.nodes, .locals = &self.locals, .statements = &self.statements },
        .span = node.span,
        .call = call,
        .parameters = signature.signature.parameters,
    }).apply(self.allocator, &out.data.call);
}
/// `input.read_into(mut buffer, max)` on a local `Input`: read at most `max` octets and append them to the
/// `byte_buffer` named by a local, answering how many. It writes the buffer, so the call-site `mut` marker is
/// required and the typed node is a buffer operation owned by the buffer's local; the input and `max` are its
/// operands. Returns false when the call is not this one.
fn checkInputReadInto(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    const owner = input.owner orelse return false;
    const slot = self.active.get(self.src.text(owner)) orelse return false;
    if (self.locals.items[@backingInt(slot)].ty != .input_cap or !std.mem.eql(u8, self.src.text(input.name), "read_into")) return false;
    try call_arguments.positional(input, self.sink);
    if (input.type_arguments.len != 0 or input.arguments.len != 2) return self.sink.fail("E_ARITY", node.span, "read_into takes a `mut` byte_buffer and a maximum count");
    const buffer_syntax = self.syntax.nodes.items[@backingInt(input.arguments[0])];
    if (buffer_syntax.data != .mut_argument) return self.sink.failOwnership(.{ .code = mutation_marker_code, .rule = .M3 }, buffer_syntax.span, "read_into writes its buffer; write `mut buffer` at the call");
    const buffer = self.nodes.items[@backingInt(self.resolved.at(@backingInt(input.arguments[0])).?)];
    const most = self.resolved.at(@backingInt(input.arguments[1])).?;
    const target = switch (buffer.data) {
        .local => |local| local,
        else => return self.sink.fail("E_TYPE", buffer_syntax.span, "read_into appends to a byte_buffer named by a local; bind the buffer to a name first"),
    };
    const local = &self.locals.items[@backingInt(target)];
    const bytes_buffer = local.ty.isAggregate() and self.catalog.records[local.ty.recordIndex()].collection.kind == .bytes and
        !typed.isByteString(self.catalog.records[local.ty.recordIndex()]);
    if (!bytes_buffer) return self.sink.fail("E_TYPE", buffer_syntax.span, "read_into appends to a byte_buffer");
    if (!local.mutable) return self.sink.failOwnership(.{ .code = eImmutable, .rule = .B1 }, buffer_syntax.span, "collection update requires a writable binding");
    try self.require(self.nodes.items[@backingInt(most)].ty, .i64, self.syntax.nodes.items[@backingInt(input.arguments[1])].span);
    local.usage.writes += 1;
    self.option_facts.forget(@backingInt(target));
    try self.requireReadable(slot, owner);
    self.locals.items[@backingInt(slot)].usage.reads += 1;
    const receiver: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = owner, .ty = .input_cap, .data = .{ .local = slot } });
    const operands = try self.allocator.dupe(typed.NodeId, &.{ receiver, most });
    out.ty = .i64;
    out.data = .{ .buffer_operation = .{ .kind = .buffer_read_from, .owner = target, .arguments = operands } };
    return true;
}
/// Refuse a call of a standard-library function W13 removed as a second spelling (`E_REMOVED_SPELLING`):
/// `math.min`, `max`, `sqrt`, `abs`, `round`, `floor`, `ceil` and `trunc` (the prelude's forms stay, W13-Q2 and Q2b; the
/// float twins' message says that a zero result keeps its sign) and `strings.to_int` and `to_float`
/// (`strings.starts_with_at` stays: it answers where the bounded `starts_with` traps, W13-Q3b). The call resolves to the declaration, so an alias or a re-export warns too. The rewrite replaces the
/// callee's name, and its type argument, with the prelude function's; `math.min[T](a, b)` drops `T` only when no
/// operand is an integer literal, which takes `T` from the call where the prelude's `min` would read an `int`, unless
/// `T` is `int` itself (W13-Q2). A prelude name this unit claims (F48's rule) and the rows that differ from their home
/// (`math.abs`) are refused with no edit. A call written in the declaring module itself (`math.floor`'s own
/// `trunc(value)`) names the module's function, not a second spelling of the prelude's, as `warnDeprecated` judges it.
fn warnDuplicateSpelling(comptime Checker: type, self: *Checker, input: @FieldType(@FieldType(ast.Node, "data"), "call"), declaration: ast.Function, checked: []const typed.NodeId) Error!void {
    const retiring_forms = @import("retiring_forms.zig");
    const module = @import("builtin_functions.zig").embeddedModule(self.src.locate(declaration.name.start).path) orelse return;
    const row = retiring_forms.duplicate(module, self.src.text(declaration.name)) orelse return;
    const declared = self.src.originalSpan(declaration.name) catch return;
    const written_at = self.src.originalSpan(input.name) catch return;
    if (declared.input == written_at.input) return;
    try retiring_forms.reported(self.sink, input.name);
    const written = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ module, row.function });
    const code = retiring_forms.duplicate_code;
    var head_end = input.name.end;
    for (input.type_arguments) |argument| head_end = @max(head_end, argument.end);
    const paren = std.mem.indexOfScalarPos(u8, self.src.bytes, head_end, '(') orelse return;
    const replacement = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ row.home, self.src.bytes[paren..@max(paren, self.syntax.nodes.items[@backingInt(input.arguments[input.arguments.len - 1])].span.end)] });
    const whole = if (input.arguments.len == 0) row.home else try std.fmt.allocPrint(self.allocator, "{s})", .{replacement});
    if (row.repair == .none) return retiring_forms.append(self.sink, code, input.name, try retiring_forms.duplicateMessage(self.allocator, written, whole, row.reason), null);
    if (self.active.contains(row.home) or self.functions.contains(row.home) or (if (self.catalog.module_names) |names| try names.topLevelSpelling(input.name, row.home) else false)) {
        const why = try std.fmt.allocPrint(self.allocator, "this unit declares or imports `{s}`, so the call is written by hand", .{row.home});
        return retiring_forms.append(self.sink, code, input.name, try retiring_forms.duplicateMessage(self.allocator, written, whole, why), null);
    }
    // An operand that is a plain integer literal takes the call's type argument as its suffix (`math.min[u8](x, 3)` is
    // `min(x, 3u8)`, W13-S5); any other operand holding an untyped literal keeps the refusal without an edit.
    var suffixes: std.ArrayList(diagnostic.Edit) = .empty;
    if (row.repair == .typed_prelude and checked.len != 0 and self.nodes.items[@backingInt(checked[0])].ty != .i64) {
        // The written type argument, `[u8]` before the call's parenthesis (the callee's span may hold it).
        const head = self.src.bytes[input.name.start..paren];
        const between = std.mem.trim(u8, head[std.mem.indexOfScalar(u8, head, '[') orelse head.len ..], " \t");
        const written_type = if (between.len > 2 and between[0] == '[' and between[between.len - 1] == ']') std.mem.trim(u8, between[1 .. between.len - 1], " \t") else "";
        const suffix: ?[]const u8 = if (retiring_forms.suffixType(written_type)) written_type else null;
        for (input.arguments) |argument| {
            const operand = self.syntax.nodes.items[@backingInt(argument)].span;
            if (!retiring_forms.holdsIntegerLiteral(self.src.text(operand))) continue;
            if (suffix != null and retiring_forms.plainIntegerLiteral(self.src.text(operand))) {
                try suffixes.append(self.allocator, .{ .span = .{ .start = operand.end, .end = operand.end }, .text = suffix.? });
                continue;
            }
            const why = "an integer literal operand takes its type from the call, and the prelude's form would read it as an `int`, so the call is written by hand";
            return retiring_forms.append(self.sink, code, input.name, try retiring_forms.duplicateMessage(self.allocator, written, whole, why), null);
        }
    }
    const edit: diagnostic.Edit = .{ .span = .{ .start = input.name.start, .end = paren }, .text = row.home };
    var shown: []const u8 = whole;
    if (suffixes.items.len != 0) {
        // The message quotes the call with its suffixes, as the edits write it.
        var text: std.ArrayList(u8) = .empty;
        try text.appendSlice(self.allocator, row.home);
        var cursor = paren;
        for (suffixes.items) |suffix| {
            try text.appendSlice(self.allocator, self.src.bytes[cursor..suffix.span.start]);
            try text.appendSlice(self.allocator, suffix.text);
            cursor = suffix.span.start;
        }
        const last = self.syntax.nodes.items[@backingInt(input.arguments[input.arguments.len - 1])].span.end;
        try text.appendSlice(self.allocator, self.src.bytes[cursor..last]);
        try text.append(self.allocator, ')');
        shown = text.items;
    }
    return retiring_forms.append(self.sink, code, input.name, try retiring_forms.noteMessage(self.allocator, written, shown, null, row.note), .{ .edit = edit, .more = suffixes.items });
}
/// Append a `W_DEPRECATED` warning when a call resolves to a `@deprecated`
/// declaration in another module. The attribute lives on the AST, not on
/// `typed.Function`, so the callee's declaration header is consulted here.
fn warnDeprecated(comptime Checker: type, self: *Checker, function: typed.FunctionId, input: @FieldType(@FieldType(ast.Node, "data"), "call")) Error!void {
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
/// Enforce the `mut` call-site marker for one resolved call. `arguments` is in
/// parameter order and `mut_positions` is the callee's declared `mut` set, so
/// the marker is required exactly where the callee declares a write, rejected
/// where it declares none, and rejected on a target that cannot be assigned
/// through. Each rejection spells the replacement in its own message.
/// A missing or superfluous marker carries its exact edit as a fix and does
/// not stop the function's check: the call is checked as if the marker were
/// right, and the check loop fails the function once its body is done, so one
/// check reports every marker a function needs (MUT-PARAM-8).
fn checkMutationMarkers(comptime Checker: type, self: *Checker, call_name: source.Span, arguments: []const ast.NodeId, mut_positions: []const u16, own_modes: []const bool) Error!void {
    for (arguments, 0..) |argument, position| {
        const declared = markerPositionDeclared(mut_positions, @intCast(position));
        const arg_node = self.syntax.nodes.items[@backingInt(argument)];
        if (arg_node.data != .mut_argument) {
            if (!declared) continue;
            if (arg_node.data == .own_argument) {
                const target = self.syntax.nodes.items[@backingInt(arg_node.data.own_argument)];
                const message = try std.fmt.allocPrint(self.allocator, "`{s}` writes `{s}`; write `mut` instead of `own`", .{ self.src.text(call_name), self.src.text(target.span) });
                try self.sink.appendFix(diagnostic.ownership(.{ .code = own_marker_code, .rule = .W2 }, arg_node.span, message), .{
                    .span = .{ .start = arg_node.span.start, .end = target.span.start },
                    .text = "mut ",
                });
                continue;
            }
            const marked = try markedCallText(Checker, self, arguments, position);
            const message = try std.fmt.allocPrint(
                self.allocator,
                "`{s}` writes `{s}`; write `{s}`",
                .{ self.src.text(call_name), self.src.text(arg_node.span), marked },
            );
            const insert: source.Span = .{ .start = arg_node.span.start, .end = arg_node.span.start };
            try self.sink.appendFix(diagnostic.ownership(.{ .code = mutation_marker_code, .rule = .M3 }, arg_node.span, message), .{ .span = insert, .text = "mut " });
            continue;
        }
        const target = self.syntax.nodes.items[@backingInt(arg_node.data.mut_argument)];
        if (!declared) {
            // A parameter that takes its value is not written: the `own` check
            // owns this argument and replaces the marker with `own` in one edit.
            if (own_parameters.isOwn(own_modes, position)) continue;
            const plain = try unmarkedCallText(Checker, self, arguments, position);
            const message = try std.fmt.allocPrint(
                self.allocator,
                "`{s}` does not write `{s}`; remove `mut`: `{s}`",
                .{ self.src.text(call_name), self.src.text(target.span), plain },
            );
            const marker: source.Span = .{ .start = arg_node.span.start, .end = target.span.start };
            try self.sink.appendFix(diagnostic.ownership(.{ .code = mutation_marker_code, .rule = .M3 }, arg_node.span, message), .{ .span = marker, .text = "" });
            continue;
        }
        if (!markerTarget(Checker, self, target)) return self.sink.failOwnership(
            .{ .code = mutation_marker_code, .rule = .M3 },
            arg_node.span,
            "`mut` requires an assignable argument (a variable, field or list slot); assign it to a local first",
        );
        try requireArrayMarkerTarget(Checker, self, argument, target);
    }
}
/// Match a written `mut` to a taking parameter without judging ownership.
/// Core decides whether the resulting `own` transfer is legal.
/// A named `@linear` owner given to an `own` parameter is written `own`, so the consumption shows at the call (D-FFI-11);
/// the certain repair inserts the marker.
fn requireLinearOwn(comptime Checker: type, self: *Checker, argument: ast.NodeId, node: ast.Node) Error!void {
    if (node.data != .name) return;
    const value = self.resolved.at(@backingInt(argument)) orelse return;
    if (!typed.linear(self.nodes.items[@backingInt(value)].ty, self.catalog.records)) return;
    const rules = @import("linear_rules.zig");
    return self.sink.failFix(rules.use_code, node.span, rules.Use.move.message(), .{ .span = .{ .start = node.span.start, .end = node.span.start }, .text = "own " });
}
/// A plain parameter of a `@linear` type borrows its argument for the call (decision LINEAR-LEND), so the argument is a
/// place the caller keeps owning: a named owner or a field chain rooted at one, of the parameter's type (no `Some` made
/// around it), not written `own`. Any other argument would be made for the call and dropped unconsumed.
fn requireLoanArgument(comptime Checker: type, self: *Checker, loan: LoanArgument) Error!void {
    if (!loan.plain or !typed.linear(loan.expected, self.catalog.records)) return;
    const node = self.nodes.items[@backingInt(loan.value)];
    const place = node.data == .local or node.data == .field;
    const borrowed = place and !node.own and node.ty == loan.expected;
    if (!borrowed or !lentPlace(Checker, self, loan.argument))
        return @import("linear_rules.zig").refuse(self.sink, self.syntax.nodes.items[@backingInt(loan.argument)].span, .loan_argument);
    return refuseLoanOverlap(Checker, self, loan.argument, loan.siblings);
}
/// One argument of a call by name and its parameter: whether the parameter is plain, the type it declares, and every
/// argument of the call.
const LoanArgument = struct { argument: ast.NodeId, value: typed.NodeId, expected: typed.Type, plain: bool, siblings: []const ast.NodeId };
/// The loan of a plain `@linear` parameter lasts for the whole call, so no other argument of the same call may give the
/// owner away with `own` (the owner, a field of it, or a record that holds it: `own` of any of them ends the root) or lend
/// a place that overlaps the loaned one `mut` (the owner, a field of it, or a record that holds it): the callee could close
/// or replace the value it still reads through the loan.
fn refuseLoanOverlap(comptime Checker: type, self: *Checker, lent: ast.NodeId, siblings: []const ast.NodeId) Error!void {
    const loan = argumentPlace(Checker, self, lent) orelse return;
    for (siblings) |sibling| {
        const node = self.syntax.nodes.items[@backingInt(sibling)];
        const given = switch (node.data) {
            .own_argument, .mut_argument => |inner| inner,
            else => continue,
        };
        const other = argumentPlace(Checker, self, given) orelse continue;
        if (!sharesPlace(loan, other, node.data == .own_argument)) continue;
        const rules = @import("linear_rules.zig");
        return self.sink.failRelated(rules.use_code, node.span, rules.Use.loan_overlap.message(), .{
            .span = self.syntax.nodes.items[@backingInt(lent)].span,
            .message = "a plain parameter borrows the owner here, for the whole call",
        });
    }
}
/// How many field names of an argument place `argumentPlace` keeps; a deeper place is taken to overlap every place on its root.
const place_depth = 16;
/// The place an argument names: its root binding and the field names from the root down.
const ArgumentPlace = struct { root: []const u8, fields: [place_depth][]const u8 = undefined, len: usize = 0, deep: bool = false };
/// The place a bare name or a field chain rooted at one names, or null for any other argument.
fn argumentPlace(comptime Checker: type, self: *Checker, argument: ast.NodeId) ?ArgumentPlace {
    var reversed: [place_depth][]const u8 = undefined;
    var count: usize = 0;
    var deep = false;
    var current = self.syntax.nodes.items[@backingInt(argument)];
    while (current.data == .field) : (current = self.syntax.nodes.items[@backingInt(current.data.field.base)]) {
        deep = deep or count == place_depth;
        if (count == place_depth) continue;
        reversed[count] = self.src.text(current.data.field.name);
        count += 1;
    }
    if (current.data != .name) return null;
    var place: ArgumentPlace = .{ .root = self.src.text(current.data.name), .len = count, .deep = deep };
    for (0..count) |index| place.fields[index] = reversed[count - 1 - index];
    return place;
}
/// Whether a loaned place and a place given in the same call share storage: the same root, and for a `mut` lend one
/// place a prefix of the other (an `own` of any place on the root ends the root's owner).
fn sharesPlace(loan: ArgumentPlace, other: ArgumentPlace, whole: bool) bool {
    if (!std.mem.eql(u8, loan.root, other.root)) return false;
    if (whole or loan.deep or other.deep) return true;
    for (0..@min(loan.len, other.len)) |index| if (!std.mem.eql(u8, loan.fields[index], other.fields[index])) return false;
    return true;
}
/// Whether an argument's syntax is a bare name or a field chain rooted at one, the places a plain `@linear` parameter
/// borrows (`sema_expressions.loanedArgument` checks them as borrows).
pub fn lentPlace(comptime Checker: type, self: *Checker, argument: ast.NodeId) bool {
    var current = self.syntax.nodes.items[@backingInt(argument)];
    while (current.data == .field) current = self.syntax.nodes.items[@backingInt(current.data.field.base)];
    return current.data == .name;
}
fn checkTakingModeMarkers(comptime Checker: type, self: *Checker, call_name: source.Span, arguments: []const ast.NodeId, callee_modes: []const bool) Error!void {
    for (arguments, 0..) |argument, position| {
        if (!own_parameters.isOwn(callee_modes, position)) continue;
        const node = self.syntax.nodes.items[@backingInt(argument)];
        try requireLinearOwn(Checker, self, argument, node);
        // An element of a new list given to an `own` parameter moves out of that list (F-55).
        if (self.resolved.at(@backingInt(argument))) |value| try self.moveTemporaryElement(argument, value);
        if (node.data != .mut_argument) continue;
        const target = self.syntax.nodes.items[@backingInt(node.data.mut_argument)];
        const value = self.resolved.at(@backingInt(node.data.mut_argument)) orelse continue;
        const managed = own_parameters.managed(self.catalog.records, self.nodes.items[@backingInt(value)].ty);
        const message = if (managed)
            try std.fmt.allocPrint(self.allocator, "`{s}` takes `{s}`; write `own {s}` instead of `mut`", .{ self.src.text(call_name), self.src.text(target.span), self.src.text(target.span) })
        else
            try std.fmt.allocPrint(self.allocator, "`{s}` is read by value; remove `mut`", .{self.src.text(target.span)});
        try self.sink.appendFix(diagnostic.ownership(.{ .code = own_marker_code, .rule = .W2 }, node.span, message), .{
            .span = .{ .start = node.span.start, .end = target.span.start },
            .text = if (managed) "own " else "",
        });
    }
}
/// A `mut` fixed array crosses the call as the caller's own storage, so its
/// argument must be a variable the caller can write: a local array or a
/// `mut` array parameter being passed on. A field or element is a part of
/// some other value, and the call would have nowhere of its own to write.
fn requireArrayMarkerTarget(comptime Checker: type, self: *Checker, argument: ast.NodeId, target: ast.Node) Error!void {
    // A `with`-bound file lends its whole handle to a `mut` argument, an exclusive borrow; its binding stays read-only.
    if (target.data == .name and self.locals.items[@backingInt(try self.resolve(target.data.name))].ownership.scoped_file) return;
    try self.requireWritableRoot(argument);
    if (target.data == .name) self.option_facts.forget(@backingInt(try self.resolve(target.data.name)));
}
/// The call's own source text with `mut ` inserted before argument `target`,
/// so a missing-marker diagnostic carries the whole corrected call rather
/// than the one argument that needed it.
fn markedCallText(comptime Checker: type, self: *Checker, arguments: []const ast.NodeId, target: usize) Error![]const u8 {
    return callTextWithMarker(Checker, self, arguments, target, true);
}
/// The same text with the `mut ` before argument `target` removed, for the
/// diagnostic that reports a marker the callee does not write.
fn unmarkedCallText(comptime Checker: type, self: *Checker, arguments: []const ast.NodeId, target: usize) Error![]const u8 {
    return callTextWithMarker(Checker, self, arguments, target, false);
}
/// Rebuild one call's argument list from source, adding or dropping a single
/// `mut ` marker at `target`. Each argument keeps its own spelling, so a named
/// operand stays `name=value`; a call with no arguments returns empty.
fn callTextWithMarker(comptime Checker: type, self: *Checker, arguments: []const ast.NodeId, target: usize, add: bool) Error![]const u8 {
    if (arguments.len == 0 or target >= arguments.len) return "";
    var out: std.ArrayList(u8) = .empty;
    try out.append(self.allocator, '(');
    for (arguments, 0..) |argument, position| {
        if (position != 0) try out.appendSlice(self.allocator, ", ");
        const node = self.syntax.nodes.items[@backingInt(argument)];
        if (position == target) {
            if (add) {
                // The argument is unmarked (that is why this diagnostic
                // exists), so its span is the operand as written and
                // inserting `mut ` keeps a `name=value` spelling intact.
                try out.appendSlice(self.allocator, "mut ");
                try out.appendSlice(self.allocator, self.src.text(node.span));
            } else {
                // Dropping a marker: the node wraps the operand, so only the
                // wrapped expression belongs in the repaired call.
                const target_node = self.syntax.nodes.items[@backingInt(node.data.mut_argument)];
                try out.appendSlice(self.allocator, self.src.text(target_node.span));
            }
            continue;
        }
        // A non-target argument may itself carry a marker the caller wrote;
        // its span then includes the keyword, which is the text to keep.
        try out.appendSlice(self.allocator, self.src.text(node.span));
    }
    try out.append(self.allocator, ')');
    return out.items;
}
/// Whether any argument of one call is wrapped in a `mut` marker. A marker
/// belongs to a call that declares a `mut` position to check it against, so a
/// call carrying one skips the builtin and constructor dispatch.
fn callCarriesMutMarker(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
    for (call.arguments) |argument| if (self.syntax.nodes.items[@backingInt(argument)].data == .mut_argument) return true;
    return false;
}
/// Whether a writing prelude call carries `own`, so its receiver-mode check
/// runs even when the required `mut` is absent.
fn callCarriesOwnMarker(comptime Checker: type, self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) bool {
    for (call.arguments) |argument| if (self.syntax.nodes.items[@backingInt(argument)].data == .own_argument) return true;
    return false;
}
/// Whether an argument expression names a place a callee could write to:
/// a variable, or a field/index chain rooted at one.
fn markerTarget(comptime Checker: type, self: *Checker, node: ast.Node) bool {
    return switch (node.data) {
        .name => true,
        .field => |field| markerTarget(Checker, self, self.syntax.nodes.items[@backingInt(field.base)]),
        .index => |index| markerTarget(Checker, self, self.syntax.nodes.items[@backingInt(index.base)]),
        else => false,
    };
}
/// Whether one zero-based position appears in a normalized `mut` set.
/// Whether the declaration behind one instance key was rejected for a `mut`
/// type that cannot carry a write. A call to it is not judged against a
/// footprint the declaration never had.
fn mutFootprintRejected(comptime Checker: type, self: *Checker, id: typed.FunctionId) bool {
    const index = @backingInt(id);
    return index < self.mut_parameter_rejected.items.len and self.mut_parameter_rejected.items[index];
}
/// Check `fs.dir(path)`: the receiver must be a `Filesystem` and the path a
/// single string literal that stays within the current root, or, in the
/// standard library's own source, a computed `str` (`filesystem.dir_at`).
fn checkDirCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
    if (input.type_arguments.len != 0 or input.arguments.len != 1 or input.argument_names.len != 0) return self.sink.fail("E_ARITY", node.span, "dir takes one path argument");
    const argument = self.syntax.nodes.items[@backingInt(input.arguments[0])];
    const bytes = switch (argument.data) {
        .text, .bytes => |spelling| spelling,
        else => return checkComputedDir(Checker, self, node, input, receiver, out),
    };
    if (!scopedDirectoryPath(bytes)) return self.sink.fail(eFilesystemDir, argument.span, "dir path must stay within the current root");
    const capability = try receiverNode(Checker, self, receiver, .filesystem_cap);
    const path_type = try self.catalog.instantiateArray(self.allocator, .u8, bytes.len, argument.span, self.sink);
    const values = try self.byteValues(bytes, argument.span);
    const path: typed.NodeId = @fromBackingInt(self.nodes.items.len);
    try self.nodes.append(self.allocator, .{ .span = argument.span, .ty = path_type, .data = .{ .array = values } });
    out.ty = .filesystem_cap;
    out.data = .{ .dir_resource = .{ .capability = capability, .path = path } };
}

/// `fs.dir(path)` with a computed path, which only the standard library writes: `filesystem.dir_at` checks the folder
/// and the runtime reads the path as the receiver reads one (docs/io.md, "A folder named at run time"). Anywhere else, or
/// when the argument was not queued for checking, it is the literal rule's refusal.
fn checkComputedDir(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), receiver: Receiver, out: *typed.Node) Error!void {
    const argument = self.syntax.nodes.items[@backingInt(input.arguments[0])];
    if (!sema_shared.computedDirSite(self.src, self.syntax.nodes.items, input)) return self.sink.fail(eFilesystemDir, argument.span, sema_shared.filesystem_dir_literal_message);
    const path = self.resolved.at(@backingInt(input.arguments[0])) orelse return self.sink.fail(eFilesystemDir, argument.span, sema_shared.filesystem_dir_literal_message);
    const text = try collections.preludeType(&self.catalog, "str", node.span);
    try self.require(self.nodes.items[@backingInt(path)].ty, text, argument.span);
    const capability = try receiverNode(Checker, self, receiver, .filesystem_cap);
    out.ty = .filesystem_cap;
    out.data = .{ .dir_resource = .{ .capability = capability, .path = path } };
}

test "a literal dir() path stays under its scoped root" {
    try std.testing.expect(scopedDirectoryPath(""));
    try std.testing.expect(scopedDirectoryPath("data/raw"));
    try std.testing.expect(!scopedDirectoryPath("../outside"));
    try std.testing.expect(!scopedDirectoryPath("data/./raw"));
    try std.testing.expect(!scopedDirectoryPath("/absolute"));
    try std.testing.expect(scopedDirectoryPath("data\\raw"));
    try std.testing.expect(scopedDirectoryPath("..\\outside"));
    try std.testing.expect(!scopedDirectoryPath("data\x00raw"));
}

/// `str(handle)` of an `extern type`, or of a value that holds one, is refused (`extern_types.zig`).
fn refuseHandleText(records: []const typed.Record, ty: typed.Type, span: source.Span, sink: *diagnostic.Sink) Error!void {
    if (@import("extern_types.zig").contains(ty, records)) return @import("extern_types.zig").refuse(sink, span, .text);
}

/// Check `str(value)` of a type that is no scalar and no text: refused unless the type is a list, set, dictionary, option, record, result or fixed array whose parts all have a text (F-38,
/// `collection_text.zig`); those need no lowering of their own, since the `cast` of such a value to `str` is the renderer
/// `print` calls. A `@linear` value is refused as `print` refuses it.
fn checkTextConversion(comptime Checker: type, self: *Checker, input_type: typed.Type, span: source.Span) Error!void {
    const collection_text = @import("collection_text.zig");
    if (collection_text.classify(input_type, self.catalog.records) == .accepted) {
        if (typed.linear(input_type, self.catalog.records)) return @import("linear_rules.zig").refuse(self.sink, span, .read);
        return;
    }
    return self.sink.fail("E_TEXT_CONVERSION", span, try collection_text.refusal(self.allocator, .str, input_type, self.catalog.records));
}
