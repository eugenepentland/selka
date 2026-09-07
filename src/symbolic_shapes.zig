//! Resolve nominal fields and contracts without assigning runtime IDs to type parameters.
const body_limit = "E_GENERIC_BODY_LIMIT";
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
    catalog: @import("type_catalog.zig").Catalog,
    src: source.Source,
    sink: *diagnostic.Sink,
    parameters: []const @import("generic_requirements.zig").Parameter,
    contracts: struct { regions: []const bool, cleanup: []const @import("effect_set.zig").Mask },
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
    fn sourceType(self: Context, span: source.Span, depth: usize) Error!Value {
        try self.charge(span);
        if (depth == 256) return self.sink.fail(body_limit, span, "structural field type exceeds 256 levels");
        for (self.parameters, 0..) |parameter, i| {
            if (std.mem.eql(u8, self.src.text(parameter.name), self.src.text(span))) {
                if (parameter.constant_length) return self.sink.fail(diagnostic.generic_length, span, "const length parameters are values, not types");
                return .{ .parameter = i };
            }
        }
        if (self.catalog.templates.applications.get(span.start)) |template| {
            var arguments: [16]Value = undefined;
            const required = self.catalog.templates.store.?.index.declarations.items[template.declaration].parameters;
            for (template.syntax.arguments, required, 0..) |argument, parameter, i| arguments[i] = if (parameter.constant_length) try self.lengthArgument(argument) else try self.sourceType(argument, depth + 1);
            return self.nominal(template.declaration, arguments[0..template.arguments.len]);
        }
        if (self.catalog.arrays.templates.get(span.start)) |template| {
            const array = try self.arena.allocator().create(symbolic.Array);
            const size: Value = if (template.length_parameter) |at| try self.lengthArgument(at) else .{ .length = template.length };
            array.* = .{ .length = if (size == .length) size.length else 0, .length_parameter = if (size == .length_parameter) size.length_parameter else null, .element = try self.sourceType(template.syntax.element, depth + 1) };
            return .{ .array = array };
        }
        return .{ .concrete = try self.catalog.resolve(self.src, span, self.sink) };
    }
    /// Inspect declaration kind without demanding a record shape from an unconstrained parameter.
    pub fn kind(self: Context, value: Value) ?templates.Kind {
        if (value == .nominal) return self.catalog.templates.store.?.index.declarations.items[value.nominal.declaration].kind;
        if (value != .concrete or !value.concrete.isAggregate()) return null;
        const shape = self.catalog.records[value.concrete.recordIndex()];
        if (shape.shape.buffer != null) return .buffer;
        if (shape.shape.pool != null) return .pool;
        if (shape.shape.handle_pool != null) return .handle;
        if (shape.shape.variants) |variants| return if (variants.fallible) .result else if (variants.is_union) .variants else .enumeration;
        return if (shape.isRecord()) .record else null;
    }
    /// Resolve an owner's element and nominal handle without inventing a concrete type.
    pub fn container(self: Context, value: Value, span: source.Span, pool: bool) Error!?struct { element: Value, handle: Value } {
        if (self.kind(value) != (if (pool) templates.Kind.pool else .buffer)) return null;
        if (value == .nominal) {
            const shape = try self.schema(value, span);
            return .{ .element = shape.fields[0].ty.?, .handle = if (pool) try self.nominal(value.nominal.declaration + 1, value.nominal.arguments) else .{ .concrete = .bool } };
        }
        const shape = self.catalog.records[value.concrete.recordIndex()].shape;
        return .{ .element = .{ .concrete = if (pool) shape.pool.?.element else shape.buffer.? }, .handle = .{ .concrete = if (pool) shape.pool.?.handle else .bool } };
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
    /// Resolve a record/variant schema, caching substituted nominal members without expanding phantom arguments.
    pub fn schema(self: Context, value: Value, span: source.Span) Error!Schema {
        try self.charge(span);
        if (value == .nominal) {
            const nominal_value = value.nominal;
            if (nominal_value.schema) |cached| return cached.*;
            const declaration = self.catalog.templates.store.?.index.declarations.items[nominal_value.declaration];
            const fields = try self.arena.allocator().alloc(symbolic.Field, declaration.fields.len);
            for (declaration.fields, fields) |field, *out| out.* = .{
                .name = self.src.text(field.name),
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
                out.* = .{ .name = self.src.text(field.name), .span = field.name, .ty = try self.sourceType(field.ty, 0) };
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
            .length, .length_parameter => .{},
            .parameter => |id| .{
                .region = !self.parameters[id].requirements.contains(.equality) and !self.parameters[id].requirements.contains(.codec),
                .requires_handling = self.parameters[id].requirements.contains(.codec) and !self.parameters[id].requirements.contains(.copy),
            },
            .concrete => |ty| .{
                .move_only = typed.moveOnly(ty, self.catalog.records),
                .requires_handling = typed.requiresHandling(ty, self.catalog.records),
                .region = @import("region_check.zig").carries(ty, self.contracts.regions),
                .cleanup = if (ty.isAggregate()) self.contracts.cleanup[ty.recordIndex()] else 0,
            },
            .nominal => |nominal_value| switch (self.kind(value).?) {
                .buffer, .pool => .{ .move_only = true, .region = true },
                .handle => .{},
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
            parent.region = parent.region or result.?.region;
            parent.cleanup |= result.?.cleanup;
        }
        return error.InternalError;
    }
};
