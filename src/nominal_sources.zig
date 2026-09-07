//! Source type applications retain the type-parameter scope of their declaration or function.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const templates = @import("nominal_templates.zig");
const layouts = @import("nominal_layouts.zig");
const Scope = struct { span: source.Span, parameters: []const requirements.Parameter, nominal: bool };
/// Compilation-arena mapping from complete source expression spans to concrete semantic identities.
pub const Sources = struct {
    resolved: std.AutoHashMapUnmanaged(usize, layouts.Id) = .empty,
    nominal_templates: std.AutoHashMapUnmanaged(usize, *const templates.Application) = .empty,
    scopes: std.ArrayList(Scope) = .empty,
    array_templates: std.AutoHashMapUnmanaged(usize, @import("generic_arrays.zig").Template) = .empty,
    fn scope(self: Sources, span: source.Span) ?Scope {
        var low: usize = 0;
        var high = self.scopes.items.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.scopes.items[middle].span.start <= span.start) low = middle + 1 else high = middle;
        }
        if (low == 0) return null;
        const found = self.scopes.items[low - 1];
        return if (span.end <= found.span.end) found else null;
    }
    fn addScopes(self: *Sources, allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) diagnostic.Error!void {
        for (program.functions) |function| {
            if (function.signature.type_parameters.len == 0) continue;
            const parameters = try requirements.resolve(allocator, src, function.signature.type_parameters, sink);
            try self.scopes.append(allocator, .{ .span = .{ .start = function.name.start, .end = program.statements.items[@backingInt(function.body)].span.end }, .parameters = parameters, .nominal = false });
        }
        inline for (.{ "records", "variants" }) |category| for (@field(program.types, category)) |declaration| {
            if (declaration.type_parameters.len == 0) continue;
            const parameters = try requirements.resolve(allocator, src, declaration.type_parameters, sink);
            const fields = if (@hasField(@TypeOf(declaration), "fields")) declaration.fields else declaration.cases;
            for (fields) |field| {
                const span: ?source.Span = if (@hasField(@TypeOf(field), "ty")) field.ty else field.payload;
                if (span) |at| try self.scopes.append(allocator, .{ .span = at, .parameters = parameters, .nominal = true });
            }
        };
        inline for (.{ "buffers", "pools" }) |category| for (@field(program.types, category)) |declaration| {
            if (declaration.type_parameters.len == 0) continue;
            const parameters = try requirements.resolve(allocator, src, declaration.type_parameters, sink);
            const span = if (@hasField(@TypeOf(declaration), "backing")) declaration.backing else declaration.element;
            try self.scopes.append(allocator, .{ .span = span, .parameters = parameters, .nominal = true });
        };
        std.mem.sort(Scope, self.scopes.items, {}, less);
    }
};
fn less(_: void, a: Scope, b: Scope) bool {
    return a.span.start < b.span.start;
}
/// Resolve every concrete application/array before body checking, deferring only declared variables.
pub fn collect(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, index: *templates.Index, graph: *layouts.Graph, sink: *diagnostic.Sink) diagnostic.Error!Sources {
    var result: Sources = .{};
    try result.addScopes(allocator, src, program, sink);
    inline for (.{ "applications", "arrays", "callbacks" }) |category| for (@field(program.types.expressions, category)) |syntax| {
        const scope = result.scope(syntax.span);
        const parameters: []const requirements.Parameter = if (scope) |found| found.parameters else &.{};
        const expression = try index.expression(syntax.span, parameters);
        try index.checkArguments(expression, parameters);
        if (templates.depends(expression)) {
            if (scope.?.nominal) continue;
            if (expression == .application) {
                try result.nominal_templates.put(allocator, syntax.span.start, expression.application);
                continue;
            }
            if (expression != .array) return error.InternalError;
            try result.array_templates.put(allocator, syntax.span.start, .{
                .syntax = expression.array.syntax,
                .length = expression.array.length orelse 0,
                .length_parameter = if (expression.array.length_parameter != null) expression.array.syntax.index.enum_type else null,
            });
            continue;
        }
        try result.resolved.put(allocator, syntax.span.start, try graph.materialize(expression, syntax.span));
    };
    return result;
}
