//! Source type applications retain the type-parameter scope of their declaration or function.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const requirements = @import("generic_requirements.zig");
const templates = @import("nominal_templates.zig");
const Names = @import("module_names.zig").Names;
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
    fn addScopes(self: *Sources, allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: ?*Names, sink: *diagnostic.Sink) diagnostic.Error!void {
        for (program.functions) |function| {
            if (function.signature.type_parameters.len == 0) continue;
            var provider: @import("constraint_lookup.zig").Provider = .{ .program = program, .src = src, .names = names };
            const parameters = try requirements.resolveBounds(allocator, src, function.signature.type_parameters, sink, provider.lookup());
            try self.scopes.append(allocator, .{ .span = .{ .start = function.name.start, .end = program.statements.items[@backingInt(function.body)].span.end }, .parameters = parameters, .nominal = false });
        }
        for (program.types.constraints) |constraint| {
            var provider: @import("constraint_lookup.zig").Provider = .{ .program = program, .src = src, .names = names };
            const parameters = try requirements.resolveBounds(allocator, src, &.{constraint.subject}, sink, provider.lookup());
            try self.scopes.append(allocator, .{ .span = constraint.span, .parameters = parameters, .nominal = false });
        }
        inline for (.{ "records", "variants" }) |category| for (@field(program.types, category)) |declaration| {
            if (declaration.type_parameters.len == 0) continue;
            const parameters = try requirements.resolve(allocator, src, declaration.type_parameters, sink);
            if (comptime std.mem.eql(u8, category, "records")) {
                for (declaration.fields) |field| try self.scopes.append(allocator, .{ .span = field.ty, .parameters = parameters, .nominal = true });
            } else for (declaration.cases) |case| {
                if (case.payload) |at| try self.scopes.append(allocator, .{ .span = at, .parameters = parameters, .nominal = true });
                for (case.fields) |field| try self.scopes.append(allocator, .{ .span = field.ty, .parameters = parameters, .nominal = true });
            }
        };
        std.mem.sort(Scope, self.scopes.items, {}, less);
    }
};
fn less(_: void, a: Scope, b: Scope) bool {
    return a.span.start < b.span.start;
}
/// One standalone declaration name and whether a constraint owns it.
const StandaloneName = struct { span: source.Span, constraint: bool };
/// Bind one declaration name; only conflicts involving a constraint report here so other
/// declaration kinds keep their existing duplicate diagnostics from later checking phases.
fn addStandaloneName(allocator: std.mem.Allocator, src: source.Source, names: *std.StringHashMapUnmanaged(StandaloneName), name: source.Span, constraint: bool, sink: *diagnostic.Sink) diagnostic.Error!void {
    const key = src.text(name);
    if (names.get(key)) |previous| {
        if (previous.constraint or constraint) return sink.failRelated("E_DUPLICATE_SYMBOL", name, "module declaration name is already bound", .{ .span = previous.span, .message = "declaration is here" });
        return;
    }
    try names.put(allocator, key, .{ .span = name, .constraint = constraint });
}
/// Add nominal type declarations in the module index's declaration order.
fn addStandaloneTypes(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: *std.StringHashMapUnmanaged(StandaloneName), sink: *diagnostic.Sink) diagnostic.Error!void {
    inline for (.{ "records", "domains", "variants", "resources" }) |category| for (@field(program.types, category)) |declaration| try addStandaloneName(allocator, src, names, declaration.name, false, sink);
}
/// Add transparent type aliases, which share the type declaration namespace.
fn addStandaloneAliases(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: *std.StringHashMapUnmanaged(StandaloneName), sink: *diagnostic.Sink) diagnostic.Error!void {
    for (program.types.expressions.aliases) |alias| try addStandaloneName(allocator, src, names, alias.name, false, sink);
}
/// Add top-level function names; domain methods are owner-qualified and stay separate.
fn addStandaloneFunctions(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: *std.StringHashMapUnmanaged(StandaloneName), sink: *diagnostic.Sink) diagnostic.Error!void {
    for (program.functions) |function| {
        if (function.policy.owner != null) continue;
        try addStandaloneName(allocator, src, names, function.name, false, sink);
    }
}
/// Add named constraints, the only declarations whose conflicts report here.
fn addStandaloneConstraints(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, names: *std.StringHashMapUnmanaged(StandaloneName), sink: *diagnostic.Sink) diagnostic.Error!void {
    for (program.types.constraints) |constraint| try addStandaloneName(allocator, src, names, constraint.name, true, sink);
}
/// Enforce the constraint declaration namespace for a standalone program before any use resolves.
/// The interfaces index performs the equivalent pass for module projects; standalone files
/// have no index, so duplicate and colliding constraint declarations are rejected here.
fn checkStandaloneConstraintNamespace(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, sink: *diagnostic.Sink) diagnostic.Error!void {
    var names: std.StringHashMapUnmanaged(StandaloneName) = .empty;
    defer names.deinit(allocator);
    try addStandaloneTypes(allocator, src, program, &names, sink);
    try addStandaloneAliases(allocator, src, program, &names, sink);
    try addStandaloneConstraints(allocator, src, program, &names, sink);
    try addStandaloneFunctions(allocator, src, program, &names, sink);
    for (program.types.constraints) |constraint| {
        const subject = constraint.subject.name;
        if (names.get(src.text(subject))) |declaration| return sink.failRelated(diagnostic.shadowing, subject, "type parameter shadows a top-level declaration", .{ .span = declaration.span, .message = "declaration is here" });
    }
}
/// Resolve every concrete application/array before body checking, deferring only declared variables.
pub fn collect(allocator: std.mem.Allocator, src: source.Source, program: ast.Program, index: *templates.Index, graph: *layouts.Graph, sink: *diagnostic.Sink) diagnostic.Error!Sources {
    if (index.context.names == null) try checkStandaloneConstraintNamespace(allocator, src, program, sink);
    var result: Sources = .{};
    try result.addScopes(allocator, src, program, index.context.names, sink);
    for (program.types.constraints) |constraint| {
        const scope = result.scope(constraint.span) orelse continue;
        for (constraint.subject.field_requirements) |field| {
            const expression = try index.expression(field.ty, scope.parameters);
            try index.checkArguments(expression, scope.parameters);
        }
        for (constraint.subject.operation_requirements) |operation| {
            for (operation.parameters) |input| {
                const expression = try index.expression(input.ty, scope.parameters);
                try index.checkArguments(expression, scope.parameters);
            }
            const expression = try index.expression(operation.return_type, scope.parameters);
            try index.checkArguments(expression, scope.parameters);
        }
    }
    inline for (.{ "applications", "arrays", "tuples", "callbacks", "suffixes" }) |category| for (@field(program.types.expressions, category)) |syntax| {
        // `f[T](x)` parses as an application in call position; its base names a function, not a type.
        if (comptime std.mem.eql(u8, category, "applications")) {
            if (try @import("call_type_arguments.zig").functionApplication(src, program, index.context.names, syntax, sink)) continue;
        }
        const scope = result.scope(syntax.span);
        const parameters: []const requirements.Parameter = if (scope) |found| found.parameters else &.{};
        const expression = try index.expression(syntax.span, parameters);
        try index.checkArguments(expression, parameters);
        if (templates.depends(expression)) {
            if (scope.?.nominal) continue;
            // A dependent tuple is resolved from its spelling's element spans by
            // the generic substitution and symbolic body checkers, which read
            // `Index.syntax.tuples`, so it needs no template entry here.
            if (comptime std.mem.eql(u8, category, "tuples")) continue;
            if (expression == .application) {
                try result.nominal_templates.put(allocator, syntax.span.start, expression.application);
                continue;
            }
            if (expression == .callback) continue;
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
