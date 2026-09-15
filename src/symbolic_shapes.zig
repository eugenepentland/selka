//! Resolve nominal fields and contracts without assigning runtime IDs to type parameters.
const body_limit = "E_GENERIC_BODY_LIMIT";
const generic_requirements = @import("generic_requirements.zig");
const type_catalog = @import("type_catalog.zig");
const ast = @import("ast.zig");
const std = @import("std");
const symbolic = @import("symbolic_types.zig");
const templates = @import("nominal_templates.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const Value = symbolic.Value;
const Schema = symbolic.Schema;
const Properties = symbolic.Properties;
/// Function-local shape resolution; allocated shapes borrow compilation metadata and argument values.
pub const Context = struct {
    arena: *std.heap.ArenaAllocator,
    catalog: type_catalog.Catalog,
    src: source.Source,
    sink: *diagnostic.Sink,
    parameters: []const generic_requirements.Parameter,
    contracts: struct { cleanup: []const @import("effect_set.zig").Mask },
    work: *usize,

    fn charge(self: Context, span: source.Span) Error!void {
        if (self.work.* == 100000) return self.sink.fail(body_limit, span, "generic nominal shapes exceed checking work budget");
        self.work.* += 1;
    }
    /// Retain nominal identity and copied ordered arguments in the function's shape arena.
    pub fn nominal(self: Context, declaration: usize, arguments: []const Value) Error!Value {
        const node = try self.arena.allocator().create(symbolic.Nominal);
        node.* = .{ .declaration = declaration, .arguments = try self.arena.allocator().dupe(Value, arguments) };
        return .{ .nominal = node };
    }
    fn lengthArgument(self: Context, span: source.Span) Error!Value {
        for (self.parameters, 0..) |parameter, index| {
            if (!std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) continue;
            if (!parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "expected a const length parameter");
            return .{ .length_parameter = index };
        }
        return .{ .length = try @import("generic_lengths.zig").literal(self.src, span, self.sink) };
    }
    fn expression(self: Context, expression_value: templates.Expression, arguments: []const Value, depth: usize, span: source.Span) Error!Value {
        try self.charge(span);
        if (depth == 256) return self.sink.fail(body_limit, span, "generic nominal expression exceeds 256 levels");
        const store = self.catalog.templates.store.?;
        return switch (expression_value) {
            .length => |value| .{ .length = value },
            .callback => |callback| result: {
                const values = try self.arena.allocator().alloc(Value, callback.arguments.len);
                for (callback.arguments, values) |argument, *value| value.* = try self.expression(argument, arguments, depth + 1, span);
                const signature = try self.arena.allocator().create(symbolic.Callback);
                signature.* = .{
                    .parameters = values[0 .. values.len - 1],
                    .result = values[values.len - 1],
                    .effects = callback.syntax.effect_bound.allowed,
                    .mutates = callback.syntax.mutates,
                    .return_origin = .unknown,
                };
                break :result .{ .callback = signature };
            },
            .builtin => |ty| .{ .concrete = ty },
            .parameter => |id| arguments[id],
            .named => |declaration| .{ .concrete = store.runtime(store.graph.index.get(.{ .base = .{ .named = declaration }, .arguments = &.{} }).?) orelse return error.InternalError },
            .application => |application| result: {
                var values: [16]Value = undefined;
                for (application.arguments, 0..) |argument, i| values[i] = try self.expression(argument, arguments, depth + 1, span);
                break :result try self.nominal(application.declaration, values[0..application.arguments.len]);
            },
            .array => |array| result: {
                const shape = try self.arena.allocator().create(symbolic.Array);
                const key = if (array.length_parameter != null) null else switch (array.syntax.index) {
                    .enum_type => |key_span| try self.catalog.resolve(self.src, key_span, self.sink),
                    .length => null,
                };
                const length: Value = if (array.length_parameter) |i| arguments[i] else .{ .length = array.length orelse self.catalog.records[key.?.recordIndex()].shape.variants.?.cases.len };
                if (length != .length and length != .length_parameter) return self.sink.fail(diagnostic.generic_length, span, "array length requires a const argument");
                shape.* = .{
                    .length = if (length == .length) length.length else 0,
                    .length_parameter = if (length == .length_parameter) length.length_parameter else null,
                    .element = try self.expression(array.element, arguments, depth + 1, span),
                    .key = key,
                };
                break :result .{ .array = shape };
            },
        };
    }
    fn sourceType(self: Context, span: source.Span, depth: usize, aliases: []const generic_requirements.SubjectAlias) Error!Value {
        try self.charge(span);
        if (depth == 256) return self.sink.fail(body_limit, span, "structural field type exceeds 256 levels");
        const scope = generic_requirements.matchScope(aliases, self.src, span);
        switch (scope) {
            .subject => |index| return .{ .parameter = index },
            .foreign, .local => {},
        }
        if (self.catalog.templates.store) |store| if (store.index.syntax.callbacks.get(span.start)) |callback| {
            // Concrete signatures retain the same identity as their type aliases.
            if (self.catalog.arrays.resolved.get(span.start)) |ty| return .{ .concrete = ty };
            const parameters = try self.arena.allocator().alloc(Value, callback.parameters.len);
            for (callback.parameters, parameters) |input, *out| out.* = try self.sourceType(input, depth + 1, aliases);
            const signature = try self.arena.allocator().create(symbolic.Callback);
            signature.* = .{
                .parameters = parameters,
                .result = try self.sourceType(callback.return_type, depth + 1, aliases),
                .effects = callback.effect_bound.allowed,
                .mutates = callback.mutates,
                .return_origin = .unknown,
            };
            return .{ .callback = signature };
        };
        if (self.catalog.templates.applications.get(span.start)) |template| {
            var arguments: [16]Value = undefined;
            const required = self.catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
            for (template.syntax.arguments, required, 0..) |argument, parameter, i| arguments[i] = if (parameter.constant_length) try self.lengthArgument(argument) else try self.sourceType(argument, depth + 1, aliases);
            return self.nominal(template.declaration, arguments[0..template.arguments.len]);
        }
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            const array = try self.arena.allocator().create(symbolic.Array);
            const size: Value = if (template.length_parameter) |at| try self.lengthArgument(at) else .{ .length = template.length };
            array.* = .{ .length = if (size == .length) size.length else 0, .length_parameter = if (size == .length_parameter) size.length_parameter else null, .element = try self.sourceType(template.syntax.element, depth + 1, aliases) };
            return .{ .array = array };
        }
        if (scope == .local) {
            for (self.parameters, 0..) |parameter, i| {
                if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) {
                    if (parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "const length parameters are values, not types");
                    return .{ .parameter = i };
                }
            }
        }
        return .{ .concrete = try self.catalog.resolve(self.src, span, self.sink) };
    }
    /// Inspect declaration kind without demanding a record shape from an unconstrained parameter.
    pub fn kind(self: Context, value: Value) ?templates.Kind {
        if (value == .nominal) return self.catalog.templates.store.?.index.declarations.items[value.nominal.declaration].kind;
        if (value != .concrete or !value.concrete.isAggregate()) return null;
        const shape = self.catalog.records[value.concrete.recordIndex()];
        if (shape.shape.buffer != null) return .buffer;
        if (shape.shape.variants) |variants| return if (variants.fallible) .result else if (variants.is_union) .variants else .enumeration;
        return if (shape.isRecord()) .record else null;
    }
    /// Identify the builtin managed Cell nominal in concrete and generic source types.
    pub fn isCell(self: Context, value: Value) bool {
        if (value == .nominal) {
            const declaration = self.catalog.templates.store.?.index.declarations.items[value.nominal.declaration];
            const builtin = declaration.builtin_name orelse return false;
            return std.mem.eql(u8, builtin, "Cell");
        }
        return value == .concrete and value.concrete.isAggregate() and self.catalog.records[value.concrete.recordIndex()].isCell();
    }
    /// Identify copyable managed list identities in concrete and generic source types.
    pub fn managed(self: Context, value: Value) bool {
        if (value == .nominal) return self.catalog.templates.store.?.index.declarations.items[value.nominal.declaration].managed;
        return value == .concrete and value.concrete.isAggregate() and self.catalog.records[value.concrete.recordIndex()].managed;
    }
    /// Distinguish symbolic managed lists, strings, and dictionaries.
    pub fn collectionKind(self: Context, value: Value) ?@import("runtime_values.zig").ManagedKind {
        if (!self.managed(value) or self.kind(value) != .buffer) return null;
        if (value == .concrete) return self.catalog.records[value.concrete.recordIndex()].collection.kind;
        const declaration = self.catalog.templates.store.?.index.declarations.items[value.nominal.declaration];
        if (declaration.builtin_name) |name| {
            if (std.mem.eql(u8, name, "dict")) return .dictionary;
            if (std.mem.eql(u8, name, "str")) return .string;
            if (std.mem.eql(u8, name, "bytes")) return .bytes;
        }
        return .list;
    }
    /// Resolve symbolic dictionary keys without inventing concrete parameter types.
    pub fn collectionKey(self: Context, value: Value, span: source.Span) Error!Value {
        if (self.collectionKind(value) != .dictionary) return error.InternalError;
        if (value == .concrete) return .{ .concrete = self.catalog.records[value.concrete.recordIndex()].collection.key.? };
        return (try self.schema(value, span)).fields[0].ty.?;
    }
    /// Resolve a managed collection's element type without inventing a concrete type.
    pub fn container(self: Context, value: Value, span: source.Span) Error!?struct { element: Value } {
        if (self.kind(value) != templates.Kind.buffer) return null;
        if (value == .nominal) {
            const shape = try self.schema(value, span);
            const element_index: usize = if (self.collectionKind(value) == .dictionary) 1 else 0;
            return .{ .element = shape.fields[element_index].ty.? };
        }
        return .{ .element = .{ .concrete = self.catalog.records[value.concrete.recordIndex()].shape.buffer.? } };
    }
    /// Recognize named result payloads while keeping symbolic arguments intact.
    pub fn matchResult(self: Context, value: Value, span: source.Span) Error!?symbolic.ResultShape {
        if (self.kind(value) != .result) return null;
        const shape = try self.schema(value, span);
        if (shape.fields.len != 2) return null;
        var ok: ?Value = null;
        var failure: ?Value = null;
        for (shape.fields) |field| {
            if (std.mem.eql(u8, field.name, "ok")) ok = field.ty;
            if (std.mem.eql(u8, field.name, "err")) failure = field.ty;
        }
        return .{ .ok_type = ok orelse return null, .error_type = failure orelse return null };
    }
    /// Recognize a symbolic optional payload while keeping the parameter intact.
    pub fn matchOption(self: Context, value: Value, span: source.Span) Error!?symbolic.OptionShape {
        if (self.kind(value) != .variants) return null;
        const shape = try self.schema(value, span);
        if (shape.fields.len != 2) return null;
        var element: ?Value = null;
        var none = false;
        for (shape.fields) |field| {
            if (std.mem.eql(u8, field.name, "some")) {
                element = field.ty orelse return null;
            } else if (std.mem.eql(u8, field.name, "none")) {
                if (field.ty != null) return null;
                none = true;
            } else return null;
        }
        if (!none) return null;
        return .{ .element = element orelse return null };
    }
    /// Resolve a record/variant schema, caching substituted nominal members without expanding phantom arguments.
    pub fn schema(self: Context, value: Value, span: source.Span) Error!Schema {
        try self.charge(span);
        if (value == .nominal) {
            const nominal_value = value.nominal;
            if (nominal_value.schema) |cached| return cached.*;
            const declaration = self.catalog.templates.store.?.index.declarations.items[nominal_value.declaration];
            const fields = try self.arena.allocator().alloc(symbolic.Field, declaration.fields.len);
            for (declaration.fields, fields) |field, *out| out.* = .{
                .name = field.builtin_name orelse self.src.text(field.name),
                .span = field.name,
                .ty = if (field.ty) |ty| try self.expression(ty, nominal_value.arguments, 0, field.name) else null,
            };
            const resolved = try self.arena.allocator().create(Schema);
            resolved.* = .{ .kind = declaration.kind, .fields = fields };
            nominal_value.schema = resolved;
            return resolved.*;
        }
        if (value == .parameter and self.parameters[value.parameter].field_requirements.len != 0) {
            const declared = self.parameters[value.parameter].field_requirements;
            const fields = try self.arena.allocator().alloc(symbolic.Field, declared.len);
            for (declared, fields) |field, *out| {
                out.* = .{ .name = self.src.text(field.name), .span = field.name, .ty = try self.sourceType(field.ty, 0, generic_requirements.subjectAliases(self.parameters[value.parameter])) };
            }
            return .{ .kind = .record, .fields = fields };
        }
        if (value != .concrete) return self.sink.fail("E_GENERIC_BODY_UNSUPPORTED", span, "structural operations on a type parameter require declared constraints");
        if (!value.concrete.isAggregate()) return self.sink.fail("E_TYPE", span, "operation requires a declared record or variant type");
        const record = self.catalog.records[value.concrete.recordIndex()];
        if (record.shape.variants) |variants| {
            const fields = try self.arena.allocator().alloc(symbolic.Field, variants.cases.len);
            for (variants.cases, fields) |field, *out| out.* = .{ .name = field.name, .span = field.declaration, .ty = if (field.payload) |ty| .{ .concrete = ty } else null };
            return .{ .kind = if (variants.fallible) .result else if (variants.is_union) .variants else .enumeration, .fields = fields };
        }
        if (!record.isRecord() and record.tableKey() == null) return self.sink.fail("E_TYPE", span, "operation requires a record or variant value");
        const fields = try self.arena.allocator().alloc(symbolic.Field, record.fields.len);
        for (record.fields, fields) |field, *out| out.* = .{ .name = field.name, .span = field.declaration, .ty = .{ .concrete = field.ty } };
        return .{ .kind = .record, .fields = fields, .key = record.tableKey() };
    }
    /// Require a record, permitting enum-indexed tables only for complete construction.
    pub fn requireRecord(self: Context, value: Value, span: source.Span, complete: bool) Error!Schema {
        if (complete and value == .parameter) return self.sink.fail("E_GENERIC_BODY_UNSUPPORTED", span, "structural fields do not describe a complete record constructor");
        const shape = try self.schema(value, span);
        if (shape.kind != .record or (!complete and shape.key != null)) return self.sink.fail("E_TYPE", span, "operation requires a record value");
        return shape;
    }
    /// Require a closed variant family, retaining result and enum distinctions.
    pub fn requireVariants(self: Context, value: Value, span: source.Span) Error!Schema {
        const shape = try self.schema(value, span);
        if (shape.kind != .variants and shape.kind != .result and shape.kind != .enumeration) return self.sink.fail("E_TYPE", span, "operation requires an enum or tagged union");
        return shape;
    }
    /// Resolve member identity within this exact declared shape.
    pub fn memberIndex(self: Context, shape: Schema, span: source.Span) Error!usize {
        for (shape.fields, 0..) |member, i| if (std.mem.eql(u8, member.name, self.src.text(span))) return i;
        return self.sink.fail(if (shape.kind == .record) "E_UNKNOWN_FIELD" else "E_UNKNOWN_VARIANT", span, "member is not declared on this type");
    }
    fn leaf(self: Context, value: Value) ?Properties {
        return switch (value) {
            .callback => .{},
            .length, .length_parameter => .{},
            .parameter => |id| .{
                .move_only = self.parameters[id].requirements.contains(.storable) and !self.parameters[id].requirements.contains(.copy),
                .requires_handling = self.parameters[id].requirements.contains(.codec) and !self.parameters[id].requirements.contains(.storable),
            },
            .concrete => |ty| .{
                .move_only = typed.moveOnly(ty, self.catalog.records),
                .requires_handling = typed.requiresHandling(ty, self.catalog.records),
                .cleanup = if (ty.isAggregate()) self.contracts.cleanup[ty.recordIndex()] else 0,
            },
            .nominal => |nominal_value| switch (self.kind(value).?) {
                .buffer => .{},
                else => nominal_value.properties,
            },
            .array => null,
        };
    }
    fn child(self: Context, value: Value, cursor: *usize, result: *Properties, span: source.Span) Error!?Value {
        if (value == .array) {
            if (cursor.* != 0 or (value.array.length_parameter == null and value.array.length == 0)) return null;
            cursor.* += 1;
            return value.array.element;
        }
        const shape = try self.schema(value, span);
        result.requires_handling = result.requires_handling or shape.kind == .result;
        while (cursor.* < shape.fields.len) {
            const index = cursor.*;
            cursor.* += 1;
            if (shape.fields[index].ty) |ty| return ty;
        }
        return null;
    }
    /// Derive contracts over stored children with an explicit stack, never by expanding type arguments.
    pub fn properties(self: Context, value: Value, span: source.Span) Error!Properties {
        if (self.leaf(value)) |known| return known;
        const Visit = struct { value: Value, next: usize = 0, result: Properties = .{} };
        var stack: std.ArrayList(Visit) = .empty;
        defer stack.deinit(self.arena.allocator());
        try stack.append(self.arena.allocator(), .{ .value = value });
        while (stack.items.len != 0) {
            try self.charge(span);
            const last = stack.items.len - 1;
            const visit = stack.items[last];
            var result = self.leaf(visit.value);
            if (result == null) {
                if (try self.child(visit.value, &stack.items[last].next, &stack.items[last].result, span)) |child_type| {
                    try stack.append(self.arena.allocator(), .{ .value = child_type });
                    continue;
                }
                result = stack.items[last].result;
                if (visit.value == .nominal) visit.value.nominal.properties = result;
            }
            _ = stack.pop();
            if (stack.items.len == 0) return result.?;
            const parent = &stack.items[stack.items.len - 1].result;
            parent.move_only = parent.move_only or result.?.move_only;
            parent.requires_handling = parent.requires_handling or result.?.requires_handling;
            parent.cleanup |= result.?.cleanup;
        }
        return error.InternalError;
    }
};
/// Coalesce equivalent expanded requirement members by resolved identity and
/// reject same-name members whose resolved types differ. Spans stay in their
/// declaring coordinate space; only the comparison is normalized, so nominal
/// identities and alpha-renamed subjects compare structurally.
pub fn normalizeRequirements(
    allocator: std.mem.Allocator,
    catalog: type_catalog.Catalog,
    src: source.Source,
    parameters: []const generic_requirements.Parameter,
    sink: *diagnostic.Sink,
) Error![]const generic_requirements.Parameter {
    if (parameters.len == 0) return parameters;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var work: usize = 0;
    const context: Context = .{
        .arena = &arena,
        .catalog = catalog,
        .src = src,
        .sink = sink,
        .parameters = parameters,
        .contracts = .{ .cleanup = &.{} },
        .work = &work,
    };
    const output = try allocator.alloc(generic_requirements.Parameter, parameters.len);
    for (parameters, output) |parameter, *item| item.* = try normalizeOne(allocator, context, parameter);
    return output;
}
fn normalizeOne(allocator: std.mem.Allocator, context: Context, parameter: generic_requirements.Parameter) Error!generic_requirements.Parameter {
    const aliases = generic_requirements.subjectAliases(parameter);
    const Seen = struct { key: []const u8, span: source.Span };
    var fields: std.ArrayList(ast.Parameter) = .empty;
    defer fields.deinit(allocator);
    var seen_fields: std.StringHashMapUnmanaged(Seen) = .empty;
    defer seen_fields.deinit(allocator);
    for (parameter.field_requirements) |field| {
        const key = try canonical(allocator, context.catalog, try context.sourceType(field.ty, 0, aliases));
        const name = context.src.text(field.name);
        if (seen_fields.get(name)) |previous| {
            if (!std.mem.eql(u8, previous.key, key))
                return context.sink.failRelated(diagnostic.generic_requirement, field.name, "conflicting structural field requirement", .{ .span = previous.span, .message = "previous requirement is here" });
            continue;
        }
        try seen_fields.put(allocator, name, .{ .key = key, .span = field.name });
        try fields.append(allocator, field);
    }
    var operations: std.ArrayList(ast.Operation) = .empty;
    defer operations.deinit(allocator);
    var seen_operations: std.StringHashMapUnmanaged(Seen) = .empty;
    defer seen_operations.deinit(allocator);
    for (parameter.operation_requirements) |operation| {
        const key = try canonicalOperation(allocator, context, operation, aliases);
        const name = context.src.text(operation.name);
        if (seen_operations.get(name)) |previous| {
            if (!std.mem.eql(u8, previous.key, key))
                return context.sink.failRelated(diagnostic.generic_requirement, operation.name, "conflicting structural operation requirement", .{ .span = previous.span, .message = "previous requirement is here" });
            continue;
        }
        try seen_operations.put(allocator, name, .{ .key = key, .span = operation.name });
        try operations.append(allocator, operation);
    }
    const aliases_copy: ?*const generic_requirements.AliasSet = if (parameter.aliases) |set| copy: {
        const items = try allocator.dupe(generic_requirements.SubjectAlias, set.items);
        errdefer allocator.free(items);
        const created = try allocator.create(generic_requirements.AliasSet);
        errdefer allocator.destroy(created);
        created.* = .{ .items = items };
        break :copy created;
    } else null;
    return .{
        .constant_length = parameter.constant_length,
        .name = parameter.name,
        .requirements = parameter.requirements,
        .field_requirements = try allocator.dupe(ast.Parameter, fields.items),
        .operation_requirements = try allocator.dupe(ast.Operation, operations.items),
        .aliases = aliases_copy,
    };
}
fn canonicalOperation(allocator: std.mem.Allocator, context: Context, operation: ast.Operation, aliases: []const generic_requirements.SubjectAlias) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    output.writer.print("op({d})", .{operation.effect_bound.allowed}) catch return error.OutOfMemory;
    for (operation.parameters) |parameter| {
        output.writer.writeByte('|') catch return error.OutOfMemory;
        output.writer.writeAll(try canonical(allocator, context.catalog, try context.sourceType(parameter.ty, 0, aliases))) catch return error.OutOfMemory;
    }
    output.writer.writeAll("->") catch return error.OutOfMemory;
    output.writer.writeAll(try canonical(allocator, context.catalog, try context.sourceType(operation.return_type, 0, aliases))) catch return error.OutOfMemory;
    return output.toOwnedSlice();
}
fn canonical(allocator: std.mem.Allocator, catalog: type_catalog.Catalog, value: Value) Error![]const u8 {
    var output: std.Io.Writer.Allocating = .init(allocator);
    errdefer output.deinit();
    try writeCanonical(&output.writer, catalog, value);
    return output.toOwnedSlice();
}
fn writeCanonical(writer: *std.Io.Writer, catalog: type_catalog.Catalog, value: Value) Error!void {
    switch (value) {
        .parameter => |index| writer.print("p{d}", .{index}) catch return error.OutOfMemory,
        .length => |count| writer.print("l{d}", .{count}) catch return error.OutOfMemory,
        .length_parameter => |index| writer.print("lp{d}", .{index}) catch return error.OutOfMemory,
        .concrete => |ty| {
            if (ty.isAggregate()) {
                writer.print("r{d}", .{ty.recordIndex()}) catch return error.OutOfMemory;
            } else writer.print("b{s}", .{@tagName(ty)}) catch return error.OutOfMemory;
        },
        .nominal => |nominal| {
            writer.print("n{d}(", .{nominal.declaration}) catch return error.OutOfMemory;
            for (nominal.arguments) |argument| {
                writer.writeByte(',') catch return error.OutOfMemory;
                try writeCanonical(writer, catalog, argument);
            }
            writer.writeByte(')') catch return error.OutOfMemory;
        },
        .array => |array| {
            writer.print("a{d},{?d}[", .{ array.length, array.length_parameter }) catch return error.OutOfMemory;
            try writeCanonical(writer, catalog, array.element);
            writer.writeByte(']') catch return error.OutOfMemory;
            if (array.key) |key| {
                writer.writeByte('k') catch return error.OutOfMemory;
                if (key.isAggregate()) writer.print("{d}", .{key.recordIndex()}) catch return error.OutOfMemory else writer.print("{s}", .{@tagName(key)}) catch return error.OutOfMemory;
            }
        },
        .callback => |callback| {
            writer.print("c({d}", .{callback.effects}) catch return error.OutOfMemory;
            if (callback.mutates.len != 0) {
                writer.writeByte('m') catch return error.OutOfMemory;
                for (callback.mutates) |position| writer.print("{d},", .{position}) catch return error.OutOfMemory;
            }
            switch (callback.return_origin) {
                .unknown => {},
                .fresh => writer.writeByte('f') catch return error.OutOfMemory,
                .params => |positions| {
                    writer.writeByte('p') catch return error.OutOfMemory;
                    for (positions) |position| writer.print("{d},", .{position}) catch return error.OutOfMemory;
                },
            }
            for (callback.parameters) |parameter| {
                writer.writeByte(',') catch return error.OutOfMemory;
                try writeCanonical(writer, catalog, parameter);
            }
            writer.writeAll(")->") catch return error.OutOfMemory;
            try writeCanonical(writer, catalog, callback.result);
        },
    }
}
