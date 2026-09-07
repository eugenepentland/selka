//! Validate structural declarations without importing resolved generic contracts.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const Error = diagnostic.Error;
const eRequirement = diagnostic.generic_requirement;
/// Validate local contract syntax independently of use or specialization.
pub fn validate(src: source.Source, parameter: ast.TypeParameter, copyable: bool, sink: *diagnostic.Sink) Error!void {
    if (parameter.field_requirements.len != 0 and !copyable) return sink.fail(eRequirement, parameter.name, "structural field contracts require copy to exclude hidden ownership and result obligations");
    for (parameter.field_requirements, 0..) |field, i| {
        for (parameter.field_requirements[0..i]) |previous| if (std.mem.eql(u8, src.text(field.name), src.text(previous.name))) return sink.fail(eRequirement, field.name, "duplicate structural field requirement");
        try namedType(src, field.ty, sink);
    }
    for (parameter.operation_requirements, 0..) |operation, i| {
        for (parameter.operation_requirements[0..i]) |previous| if (std.mem.eql(u8, src.text(operation.name), src.text(previous.name))) return sink.fail(eRequirement, operation.name, "duplicate structural operation requirement");
        try namedType(src, operation.return_type, sink);
        for (operation.parameters, 0..) |input, j| {
            try namedType(src, input.ty, sink);
            for (operation.parameters[0..j]) |previous| if (std.mem.eql(u8, src.text(input.name), src.text(previous.name))) return sink.fail(eRequirement, input.name, "duplicate structural operation parameter");
        }
    }
}
fn namedType(src: source.Source, span: source.Span, sink: *diagnostic.Sink) Error!void {
    if (std.mem.indexOfAny(u8, src.text(span), "[<") != null) return sink.fail(eRequirement, span, "structural signatures currently accept named types and type parameters only");
}
