//! Resolve nominal fields and contracts without assigning runtime IDs to type parameters.
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
        if (self.work.* == 100000) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic nominal shapes exceed checking work budget");
        self.work.* += 1;
    }
    /// Retain nominal identity and copied ordered arguments in the function's shape arena.
    pub fn nominal(self: Context, declaration: usize, arguments: []const Value) Error!Value {
        const node = try self.arena.allocator().create(symbolic.Nominal);
        node.* = .{ .declaration = declaration, .arguments = try self.arena.allocator().dupe(Value, arguments) };
        return .{ .nominal = node };
    }
    fn expression(self: Context, expression_value: templates.Expression, arguments: []const Value, depth: usize, span: source.Span) Error!Value {
        try self.charge(span);
        if (depth == 256) return self.sink.fail("E_GENERIC_BODY_LIMIT", span, "generic nominal expression exceeds 256 levels");
        const store = self.catalog.templates.store.?;
        return switch (expression_value) {
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
                const key = switch (array.syntax.index) {
                    .enum_type => |key_span| try self.catalog.resolve(self.src, key_span, self.sink),
                    .length => null,
                };
                shape.* = .{
                    .length = array.length orelse self.catalog.records[key.?.recordIndex()].shape.variants.?.cases.len,
                    .element = try self.expression(array.element, arguments, depth + 1, span),
                    .key = key,
                };
                break :result .{ .array = shape };
            },
        };
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
            .parameter => |id| .{ .region = !self.parameters[id].requirements.contains(.equality) },
            .concrete => |ty| .{
                .move_only = typed.moveOnly(ty, self.catalog.records),
                .requires_handling = typed.requiresHandling(ty, self.catalog.records),
                .region = @import("region_check.zig").carries(ty, self.contracts.regions),
                .cleanup = if (ty.isAggregate()) self.contracts.cleanup[ty.recordIndex()] else 0,
            },
            .nominal => |nominal_value| nominal_value.properties,
            .array => null,
        };
    }
    fn child(self: Context, value: Value, cursor: *usize, result: *Properties, span: source.Span) Error!?Value {
        if (value == .array) {
            if (cursor.* != 0 or value.array.length == 0) return null;
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
