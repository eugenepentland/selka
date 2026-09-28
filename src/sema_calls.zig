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
const call_arguments = @import("call_arguments.zig");
const external_resources = @import("external_resources.zig");
const callables = @import("callables.zig");
const eResultOperation = diagnostic.result_operation;
const eOwnedConsumed = diagnostic.owned_consumed;
const byte_buffer_name = @import("nominal_templates.zig").byte_buffer_name;
const isMutableBytes = sema_shared.isMutableBytes;
const eImmutable = diagnostic.immutable;
const std = @import("std");
const mutation_marker_code = @import("origins.zig").mutation_marker_code;
const ast = @import("ast.zig");
const effect_set = @import("effect_set.zig");
const nominal_catalog = @import("nominal_catalog.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const eArenaBinding = sema_shared.eArenaBinding;
const prelude = @import("prelude.zig");
const markerPositionDeclared = sema_shared.markerPositionDeclared;
const eEnvironmentName = sema_shared.eEnvironmentName;
const eWithResource = sema_shared.eWithResource;
const callback_type_code = "E_CALLBACK_TYPE";
const embed = @import("embed.zig");
const eByteConversion = "E_BYTES_CONVERSION";
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
            return impl.checkCall(Checker, self, node, input, out);
        }
        /// Check a record field read, rejecting a projection that would drop another
        /// result-bearing field.
        pub fn checkField(self: *Checker, node: ast.Node, field: @FieldType(@FieldType(ast.Node, "data"), "field"), out: *typed.Node) Error!void {
            return impl.checkField(Checker, self, node, field, out);
        }
        /// Check a bare name: a constant-length type parameter, a local read (rejecting an
        /// arena binding or a consumed owned value), or a function used as a value.
        pub fn checkName(self: *Checker, node: ast.Node, name: @FieldType(@FieldType(ast.Node, "data"), "name"), out: *typed.Node) Error!void {
            return impl.checkName(Checker, self, node, name, out);
        }
        /// Recognize `env.get(...)`, `env.only(...)` and `env.names()` on a local
        /// `Environment` binding.
        pub fn environmentMethod(self: *Checker, call: @FieldType(@FieldType(ast.Node, "data"), "call")) ?EnvironmentMethod {
            return impl.environmentMethod(Checker, self, call);
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
fn checkField(comptime Checker: type, self: *Checker, node: ast.Node, field: @FieldType(@FieldType(ast.Node, "data"), "field"), out: *typed.Node) Error!void {
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
/// CALLBACK-SLOT-1: a generic callee's callback parameter is only concrete
/// once its type arguments are inferred from the checked arguments, so an
/// unannotated function value passed there was typed before its slot was
/// known and carries the unbounded ceiling. Give it the slot's type, exactly
/// as `functionValue` does for a slot known up front; the effect pass then
/// holds the function's inferred body to that ceiling.
fn adoptSlotCeiling(comptime Checker: type, self: *Checker, value: typed.NodeId, expected: typed.Type) void {
    const node = &self.nodes.items[@backingInt(value)];
    if (node.ty == expected) return;
    const target = switch (node.data) {
        .function_value => |id| id,
        else => return,
    };
    if (self.syntaxFunction(target).policy.effect_bound != null) return;
    const actual = callables.signature(node.ty, self.catalog.records) orelse return;
    const slot = callables.signature(expected, self.catalog.records) orelse return;
    if (actual.return_type != slot.return_type or !std.mem.eql(typed.Type, actual.parameters, slot.parameters)) return;
    if (!callables.positionSubset(actual.mutates, slot.mutates)) return;
    node.ty = expected;
}
fn functionValue(comptime Checker: type, self: *Checker, name: source.Span, out: *typed.Node) Error!bool {
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
    for (function.signature.mut_positions) |position| if (position < parameters.len and typed.referenceMut(self.catalog.records, parameters[position]))
        return self.sink.fail(callback_type_code, name, "a function with a `mut` fixed-array or record parameter writes the caller's own variable and cannot be used as a value; call it directly");
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
        .mutates = function.signature.mut_positions,
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
fn indirectCall(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    const slot = try self.resolve(call.name);
    const contract = callables.signature(self.locals.items[@backingInt(slot)].ty, self.catalog.records) orelse return self.sink.fail(callback_type_code, call.name, "called local is not a function value");
    if (call.type_arguments.len != 0 or call.arguments.len != contract.parameters.len) return self.sink.fail("E_ARITY", call.name, "callback argument count must match its signature");
    try checkMutationMarkers(Checker, self, call.name, call.arguments, contract.mutates);
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
/// Check a bare name: a constant-length type parameter, a local read (rejecting an
/// arena binding or a consumed owned value), or a function used as a value.
fn checkName(comptime Checker: type, self: *Checker, node: ast.Node, name: @FieldType(@FieldType(ast.Node, "data"), "name"), out: *typed.Node) Error!void {
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
    if (!self.active.contains(self.src.text(name)) and try functionValue(Checker, self, name, out)) return;
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
/// builds the mutable buffer that the in-place append methods accept.
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
    const value = self.resolved[@backingInt(call.arguments[0])].?;
    try self.requireInteger(self.nodes.items[@backingInt(value)].ty, node.span);
    out.ty = ty_value;
    out.data = .{ .cast = value };
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
/// `env.get("NAME") -> Option[str]`: materialize the literal bytes as a fixed
/// `[N]u8` request and build the checked `environment_get` node with an Option
/// result, so the native boundary answers `Some(text)` or `None`.
fn checkEnvironmentGet(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, owner: source.Span, out: *typed.Node) Error!void {
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
fn checkEnvironmentOnly(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, owner: source.Span, out: *typed.Node) Error!void {
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
fn checkEnvironmentNames(comptime Checker: type, self: *Checker, node: ast.Node, call: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, owner: source.Span, out: *typed.Node) Error!void {
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
fn checkCapabilityNarrowing(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
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
        try checkDirCall(Checker, self, node, input, slot, out);
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
    if (!std.mem.eql(u8, self.src.text(input.name), "host")) return false;
    try checkHostCall(Checker, self, node, input, slot, out);
    return true;
}
/// Check `net.host(name)`: a `Network` receiver and one literal endpoint that
/// becomes the sole endpoint every acquisition through the derived value may
/// request. A dynamic name is `E_NETWORK_HOST`.
fn checkHostCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, out: *typed.Node) Error!void {
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
fn checkEnvironmentDispatch(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!bool {
    const method = environmentMethod(Checker, self, input) orelse return false;
    const owner = input.owner.?;
    const slot = self.active.get(self.src.text(owner)).?;
    switch (method) {
        .get => try checkEnvironmentGet(Checker, self, node, input, slot, owner, out),
        .only => try checkEnvironmentOnly(Checker, self, node, input, slot, owner, out),
        .names => try checkEnvironmentNames(Checker, self, node, input, slot, owner, out),
    }
    return true;
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
    const base = self.resolved[@backingInt(input.arguments[0])].?;
    const record_type = self.nodes.items[@backingInt(base)].ty;
    if (!record_type.isAggregate() or !self.catalog.records[record_type.recordIndex()].isRecord())
        return self.sink.fail("E_TYPE", input.name, "replace(...) needs a record value; the positional form replaces a list index");
    const initializers = try self.allocator.alloc(ast.FieldInit, input.arguments.len - 1);
    for (input.arguments[1..], 0..) |value, index| initializers[index] = .{ .name = input.argument_names[index + 1].?, .value = value };
    out.ty = record_type;
    out.data = .{ .update = .{ .base = base, .fields = try self.fields(record_type, initializers, false, node.span) } };
}
fn checkCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), out: *typed.Node) Error!void {
    // A call carrying a `mut` marker must resolve to a declared function or a
    // callable value: only those expose a `mut` parameter set. Skipping the
    // builtin and constructor dispatch for such a call routes it through the
    // ordinary resolution below, where the marker is checked positionally
    // instead of silently accepted and dropped.
    if (self.listSortOwner(input)) |slot| return self.checkListSort(node, input, slot, out);
    const markers_present = callCarriesMutMarker(Checker, self, input);
    if (!markers_present) {
        if (try checkCapabilityNarrowing(Checker, self, node, input, out)) return;
        if (try checkNetworkHost(Checker, self, node, input, out)) return;
        if (try checkEnvironmentDispatch(Checker, self, node, input, out)) return;
        if (try embedBuiltin(Checker, self, input)) |kind| return checkEmbed(Checker, self, node, input, kind, out);
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
        if (try typeConversion(Checker, self, input)) |ty_value| return checkTypeConversion(Checker, self, node, input, ty_value, out);
        if (try self.optionConstructor(input)) return self.checkOptionConstructor(node, input, out);
        if (try textConstructor(Checker, self, input, node.span)) {
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
        if (byteConversion(Checker, self, input)) |conversion| return checkByteConversion(Checker, self, node, input, conversion, out);
        if (try self.resultConstructor(input)) |ok| {
            try call_arguments.positional(input, self.sink);
            return self.checkResultConstructor(node, input, ok, out);
        }
    }
    if (try recordUpdateCall(Checker, self, input)) return checkRecordUpdate(Checker, self, node, input, out);
    if (input.owner == null and self.active.contains(self.src.text(input.name))) {
        try call_arguments.positional(input, self.sink);
        return indirectCall(Checker, self, node, input, out);
    }
    const target = try self.callDeclaration(input, node.span);
    const call = target.call;
    const function = try self.specialize(target.declaration, call, node.span);
    const signature = self.syntaxFunction(function);
    try warnDeprecated(Checker, self, function, input);
    if (!mutFootprintRejected(Checker, self, function)) try checkMutationMarkers(Checker, self, call.name, call.arguments, signature.signature.mut_positions);
    var arguments: std.ArrayList(typed.NodeId) = .empty;
    for (call.arguments, signature.signature.parameters) |arg, parameter| {
        const argument = self.syntax.nodes.items[@backingInt(arg)];
        const value = self.resolved[@backingInt(arg)].?;
        const expected = try self.functionType(function, parameter.ty);
        adoptSlotCeiling(Checker, self, value, expected);
        try self.require(self.nodes.items[@backingInt(value)].ty, expected, argument.span);
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
/// through. Each rejection spells the replacement in its own message. Once
/// every marker is right, two marked places that may overlap are rejected.
fn checkMutationMarkers(comptime Checker: type, self: *Checker, call_name: source.Span, arguments: []const ast.NodeId, mut_positions: []const u16) Error!void {
    for (arguments, 0..) |argument, position| {
        const declared = markerPositionDeclared(mut_positions, @intCast(position));
        const arg_node = self.syntax.nodes.items[@backingInt(argument)];
        if (arg_node.data != .mut_argument) {
            if (!declared) continue;
            const marked = try markedCallText(Checker, self, arguments, position);
            const message = try std.fmt.allocPrint(
                self.allocator,
                "`{s}` writes `{s}`; write `{s}`",
                .{ self.src.text(call_name), self.src.text(arg_node.span), marked },
            );
            return self.sink.fail(mutation_marker_code, arg_node.span, message);
        }
        const target = self.syntax.nodes.items[@backingInt(arg_node.data.mut_argument)];
        if (!declared) {
            const plain = try unmarkedCallText(Checker, self, arguments, position);
            const message = try std.fmt.allocPrint(
                self.allocator,
                "`{s}` does not write `{s}`; remove `mut`: `{s}`",
                .{ self.src.text(call_name), self.src.text(target.span), plain },
            );
            return self.sink.fail(mutation_marker_code, arg_node.span, message);
        }
        if (!markerTarget(Checker, self, target)) return self.sink.fail(
            mutation_marker_code,
            arg_node.span,
            "`mut` requires an assignable argument (a variable, field or list slot); assign it to a local first",
        );
        try requireArrayMarkerTarget(Checker, self, argument, target);
    }
    // MUT-EXCLUSIVE-1: with every marker in place, the marked places must be disjoint.
    try @import("mut_exclusive.zig").check(Checker, self, call_name, arguments);
}
/// A `mut` fixed array crosses the call as the caller's own storage, so its
/// argument must be a variable the caller can write: a local array or a
/// `mut` array parameter being passed on. A field or element is a part of
/// some other value, and the call would have nowhere of its own to write.
fn requireArrayMarkerTarget(comptime Checker: type, self: *Checker, argument: ast.NodeId, target: ast.Node) Error!void {
    const checked = self.resolved[@backingInt(argument)] orelse return;
    const node = self.nodes.items[@backingInt(checked)];
    if (!typed.referenceMut(self.catalog.records, node.ty)) return;
    // VALUE-SEMANTICS-3: a `mut` record crosses as the caller's variable too.
    const what = if (typed.referenceArray(self.catalog.records, node.ty)) "a fixed array" else "a record";
    if (target.data != .name or node.data != .local) return self.sink.fail(
        mutation_marker_code,
        target.span,
        try std.fmt.allocPrint(self.allocator, "`mut` on {s} passes a variable itself; copy the field or element into a local, pass `mut` that local, and store it back", .{what}),
    );
    if (!self.locals.items[@backingInt(node.data.local)].mutable) return self.sink.fail(eImmutable, target.span, try std.fmt.allocPrint(self.allocator, "`mut` on {s} requires a mutable binding", .{what}));
    // The callee writes the variable itself (`PY-ARRAY-ITER-2` reads this).
    self.locals.items[@backingInt(node.data.local)].usage.writes += 1;
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
/// single string literal that stays within the current root.
fn checkDirCall(comptime Checker: type, self: *Checker, node: ast.Node, input: @FieldType(@FieldType(ast.Node, "data"), "call"), slot: typed.LocalId, out: *typed.Node) Error!void {
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

test "a literal dir() path stays under its scoped root" {
    try std.testing.expect(scopedDirectoryPath(""));
    try std.testing.expect(scopedDirectoryPath("data/raw"));
    try std.testing.expect(!scopedDirectoryPath("../outside"));
    try std.testing.expect(!scopedDirectoryPath("data/./raw"));
    try std.testing.expect(!scopedDirectoryPath("/absolute"));
    try std.testing.expect(!scopedDirectoryPath("data\\raw"));
}
