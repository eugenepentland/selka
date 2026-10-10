//! Raw AST projection and ownership transfer for batched interface type analysis.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const value = @import("type_interface_value.zig");
const declaration = @import("declaration_value.zig");
const Error = std.mem.Allocator.Error || error{ComponentProtocol};

const Projection = struct {
    allocator: std.mem.Allocator,
    rows: usize = 0,

    fn alloc(self: *Projection, comptime T: type, count: usize) Error![]T {
        // Admission precedes allocation even for a host AST beyond the component profile.
        if (count > 262144 - self.rows) return error.ComponentProtocol;
        self.rows += count;
        return self.allocator.alloc(T, count);
    }
    fn fields(self: *Projection, parameters: []const ast.Parameter) Error![]const value.Field {
        const output = try self.alloc(value.Field, parameters.len);
        for (parameters, output) |item, *out| out.* = .{ .name = item.name, .ty = item.ty };
        return output;
    }
    fn fieldTypes(self: *Projection, parameters: []const ast.Parameter) Error![]const source.Span {
        const output = try self.alloc(source.Span, parameters.len);
        for (parameters, output) |item, *out| out.* = item.ty;
        return output;
    }
    fn generic(self: *Projection, parameter: ast.TypeParameter) Error!value.Generic {
        const operations = try self.alloc(value.Operation, parameter.operation_requirements.len);
        for (parameter.operation_requirements, operations) |item, *out| out.* = .{
            .name = item.name,
            .parameters = try self.fields(item.parameters),
            .return_type = item.return_type,
        };
        const named = try self.alloc(value.Reference, parameter.named_requirements.len);
        for (parameter.named_requirements, named) |item, *out| out.* = .{ .alias = item.alias, .name = item.name };
        return .{
            .name = parameter.name,
            .default_copy = parameter.default_copy,
            .constant_length = parameter.constant_length,
            .requirements = parameter.requirements,
            .fields = try self.fields(parameter.field_requirements),
            .operations = operations,
            .named = named,
        };
    }
    fn generics(self: *Projection, parameters: []const ast.TypeParameter) Error![]const value.Generic {
        const output = try self.alloc(value.Generic, parameters.len);
        for (parameters, output) |item, *out| out.* = try self.generic(item);
        return output;
    }
    fn catalog(self: *Projection, program: ast.Program) Error!value.Catalog {
        var result: value.Catalog = .{};
        const syntax = program.types;
        const records = try self.alloc(value.Record, syntax.records.len);
        for (syntax.records, records) |item, *out| out.* = .{
            .name = item.name,
            .parameters = try self.generics(item.type_parameters),
            .fields = try self.fieldTypes(item.fields),
        };
        result.declarations.records = records;
        const variants = try self.alloc(value.Variant, syntax.variants.len);
        for (syntax.variants, variants) |item, *out| {
            const cases = try self.alloc(value.Case, item.cases.len);
            for (item.cases, cases) |branch, *converted| converted.* = .{ .payload = branch.payload, .fields = try self.fieldTypes(branch.fields) };
            out.* = .{ .name = item.name, .parameters = try self.generics(item.type_parameters), .cases = cases };
        }
        result.declarations.variants = variants;
        const aliases = try self.alloc(value.Alias, syntax.expressions.aliases.len);
        for (syntax.expressions.aliases, aliases) |item, *out| out.* = .{ .name = item.name, .target = item.target };
        result.declarations.aliases = aliases;
        const domains = try self.alloc(value.Alias, syntax.domains.len);
        for (syntax.domains, domains) |item, *out| out.* = .{ .name = item.name, .target = item.backing };
        result.declarations.domains = domains;
        const constraints = try self.alloc(value.Constraint, syntax.constraints.len);
        for (syntax.constraints, constraints) |item, *out| out.* = .{ .name = item.name, .span = item.span, .subject = try self.generic(item.subject) };
        result.declarations.constraints = constraints;
        const functions = try self.alloc(value.Function, program.functions.len);
        for (program.functions, functions) |item, *out| out.* = .{
            .name = item.name,
            .owner = item.policy.owner,
            .parameters = try self.generics(item.signature.type_parameters),
            .inputs = try self.fieldTypes(item.signature.parameters),
            .return_type = item.signature.return_type,
            .failure_type = item.signature.failure_type,
        };
        result.declarations.functions = functions;
        try self.types(&result, syntax.expressions);
        return result;
    }
    fn types(self: *Projection, result: *value.Catalog, syntax: ast.TypeExpressions) Error!void {
        const suffixes = try self.alloc(value.Suffix, syntax.suffixes.len);
        for (syntax.suffixes, suffixes) |item, *out| out.* = .{ .span = item.span, .base = item.base };
        result.types.suffixes = suffixes;
        const callbacks = try self.alloc(value.Callback, syntax.callbacks.len);
        for (syntax.callbacks, callbacks) |item, *out| out.* = .{ .span = item.span, .parameters = item.parameters, .return_type = item.return_type, .failure_type = item.failure_type };
        result.types.callbacks = callbacks;
        const arrays = try self.alloc(value.Array, syntax.arrays.len);
        for (syntax.arrays, arrays) |item, *out| out.* = .{
            .span = item.span,
            .enum_index = if (item.index == .enum_type) item.index.enum_type else null,
            .element = item.element,
        };
        result.types.arrays = arrays;
        const applications = try self.alloc(value.Application, syntax.applications.len);
        for (syntax.applications, applications) |item, *out| out.* = .{ .span = item.span, .name = item.name, .arguments = item.arguments };
        result.types.applications = applications;
        const tuples = try self.alloc(value.Tuple, syntax.tuples.len);
        for (syntax.tuples, tuples) |item, *out| out.* = .{ .span = item.span, .elements = item.elements };
        result.types.tuples = tuples;
    }
};

/// Project syntax and existing symbol facts without making any resolution decisions.
pub fn input(a: std.mem.Allocator, index: anytype) Error!value.Input {
    const modules = index.project.modules.items;
    if (modules.len > 4096) return error.ComponentProtocol;
    var source_bytes: usize = 0;
    for (modules) |module| {
        if (module.src.bytes.len > 1048576) return error.ComponentProtocol;
        source_bytes += module.src.bytes.len;
        if (source_bytes > 8 * 1048576) return error.ComponentProtocol;
    }
    var projection: Projection = .{ .allocator = a };
    const output = try a.alloc(value.Module, modules.len);
    const imported = try a.alloc(bool, modules.len);
    @memset(imported, false);
    for (modules) |module| for (module.imports) |edge| {
        imported[edge.target] = true;
    };
    for (modules, output, 0..) |module, *out, id| {
        const imports = try projection.alloc(declaration.Import, module.imports.len);
        for (module.imports, imports) |item, *edge| edge.* = .{ .name = item.name, .alias = item.alias, .span = item.span, .target = item.target };
        out.* = .{
            .context = .{ .module = id, .name = module.name, .path = module.src.path, .trusted_intrinsics = module.src.trusted_intrinsics, .is_imported = imported[id], .source = module.src.bytes },
            .imports = imports,
            .symbols = index.units[id].symbols.items,
            .import_used = try a.dupe(bool, index.units[id].import_used),
            .syntax = try projection.catalog(index.units[id].syntax),
        };
    }
    return .{ .order = index.project.order.items, .modules = output };
}

/// Capture the oracle's resulting import usage in ascending module ID order.
pub fn importUsage(a: std.mem.Allocator, comptime Unit: type, units: []const Unit) Error![]const []const bool {
    const output = try a.alloc([]const bool, units.len);
    for (units, output) |unit, *out| out.* = unit.import_used;
    return output;
}

/// Apply validated usage to the host tables; signature decisions already belong to Selka.
pub fn adopt(index: anytype, output: value.Output) Error!void {
    if (!std.mem.eql(usize, index.project.order.items, output.order)) return error.ComponentProtocol;
    if (output.import_used.len != index.units.len) return error.ComponentProtocol;
    for (index.units, output.import_used) |*unit, used| {
        if (unit.import_used.len != used.len) return error.ComponentProtocol;
        @memcpy(unit.import_used, used);
    }
}
