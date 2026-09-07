//! Source-declared field and public domain-operation obligations; no representative types.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const typed = @import("typed.zig");
const requirements = @import("generic_requirements.zig");
const Error = diagnostic.Error;
const eArgument = diagnostic.generic_argument;
/// Shared concrete satisfaction checking used before specialization publication.
pub const Context = struct {
    src: source.Source,
    catalog: *@import("type_catalog.zig").Catalog,
    program: ast.Program,
    sink: *diagnostic.Sink,
    lengths: []const ?usize = &.{},
    fn ty(self: Context, allocator: std.mem.Allocator, span: source.Span, parameters: []const ast.TypeParameter, arguments: []const typed.Type) Error!typed.Type {
        return @import("generic_substitution.zig").resolve(allocator, self.catalog, self.src, self.sink, .{ .span = span, .parameters = parameters, .arguments = arguments, .lengths = self.lengths });
    }
    /// Resolve an explicitly public, nongeneric domain method with a declared effect ceiling.
    pub fn method(self: Context, target: typed.Type, name: source.Span) Error!ast.Function {
        if (!target.isAggregate() or self.catalog.records[target.recordIndex()].shape.domain == null) return self.sink.fail(eArgument, name, "structural operation requires a domain with a public method");
        for (self.program.functions) |function| {
            if (!std.mem.eql(u8, self.src.text(function.name), self.src.text(name))) continue;
            const owner = function.policy.owner orelse continue;
            if (try self.catalog.resolve(self.src, owner, self.sink) != target) continue;
            const unsupported_signature = function.signature.type_parameters.len != 0 or function.signature.return_reference != null;
            if (function.policy.restricted or function.policy.conversion or unsupported_signature or function.policy.effect_bound == null)
                return self.sink.fail(eArgument, name, "required operation must be public, nongeneric, return a value, and declare effects");
            return function;
        }
        return self.sink.fail(eArgument, name, "type does not provide the required public operation");
    }
    /// Require every declared field and operation without equating nominal identities.
    pub fn accepts(self: Context, allocator: std.mem.Allocator, target: typed.Type, parameter: requirements.Parameter, parameters: []const ast.TypeParameter, arguments: []const typed.Type) Error!void {
        if (parameter.field_requirements.len != 0) {
            if (!target.isAggregate() or !self.catalog.records[target.recordIndex()].isRecord()) return self.sink.fail(eArgument, parameter.name, "structural field requirement needs a record, not an opaque domain or scalar");
            const record = self.catalog.records[target.recordIndex()];
            for (parameter.field_requirements) |field| {
                var found = false;
                for (record.fields) |actual| if (std.mem.eql(u8, actual.name, self.src.text(field.name))) {
                    found = actual.ty == try self.ty(allocator, field.ty, parameters, arguments);
                    break;
                };
                if (!found) return self.sink.fail(eArgument, field.name, "type lacks a required field with the declared type");
            }
        }
        for (parameter.operation_requirements) |operation| {
            const function = try self.method(target, operation.name);
            if (function.policy.effect_bound.?.allowed & ~operation.effect_bound.allowed != 0) return self.sink.fail(eArgument, operation.name, "operation effect ceiling exceeds the required contract");
            if (function.signature.parameters.len != operation.parameters.len) return self.sink.fail(eArgument, operation.name, "operation parameter count differs from contract");
            for (function.signature.parameters, operation.parameters) |actual, expected| {
                if (actual.reference != expected.reference or actual.slice != expected.slice or try self.catalog.resolve(self.src, actual.ty, self.sink) != try self.ty(allocator, expected.ty, parameters, arguments))
                    return self.sink.fail(eArgument, expected.name, "operation parameter type or reference permission differs from contract");
            }
            if (try self.catalog.resolve(self.src, function.signature.return_type, self.sink) != try self.ty(allocator, operation.return_type, parameters, arguments))
                return self.sink.fail(eArgument, operation.name, "operation result type differs from contract");
        }
    }
};
