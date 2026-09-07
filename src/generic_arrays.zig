//! Source-scoped array templates defer only declared type variables, never unknown names.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const eArrayLength = "E_ARRAY_LENGTH";
/// Numeric array syntax whose element depends on an enclosing type parameter.
pub const Template = struct { syntax: ast.ArrayType, length: usize, length_parameter: ?source.Span = null };
/// Match a leaf only against type parameters of its enclosing function.
pub fn parameter(src: source.Source, program: ast.Program, span: source.Span) bool {
    for (program.functions) |function| {
        if (function.signature.type_parameters.len == 0) continue;
        const end = program.statements.items[@backingInt(function.body)].span.end;
        if (span.start < function.name.start or span.end > end) continue;
        for (function.signature.type_parameters) |item| if (std.mem.eql(u8, src.text(item.name), src.text(span))) return true;
    }
    return false;
}
/// Parse the same bounded numeric length for concrete arrays and templates.
pub fn length(src: source.Source, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!usize {
    const digits = src.text(span);
    for (digits) |c| if (!std.ascii.isDigit(c)) return sink.fail(eArrayLength, span, "array length must be an unsuffixed decimal integer");
    const count = std.fmt.parseInt(usize, digits, 10) catch return sink.fail(eArrayLength, span, "array length exceeds the host index range");
    if (count > std.math.maxInt(usize) / @sizeOf(typed.Value)) return sink.fail(eArrayLength, span, "array value storage exceeds the host address range");
    return count;
}
