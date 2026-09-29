//! Decimal floating syntax and demand detection without changing scalar wire identities.
const std = @import("std");
const ast = @import("ast.zig");
const Source = @import("source.zig").Source;
const number_literal = @import("number_literal.zig");

/// Decimal points or exponent markers distinguish floating tokens from integer suffixes;
/// a `0x`, `0o` or `0b` spelling is always an integer, whatever letters it holds.
pub fn isLiteral(text: []const u8) bool {
    return number_literal.isFloat(text);
}

/// Whether the AST contains an operation that needs a concrete float schema.
pub fn used(src: Source, program: ast.Program) bool {
    for (program.nodes.items) |node| switch (node.data) {
        .integer => |span| if (isLiteral(src.text(span))) return true,
        .binary => |binary| if (binary.op == .python_div) return true,
        .call => |call| if (std.mem.eql(u8, src.text(call.name), "float")) return true,
        else => {},
    };
    for (program.functions) |function| {
        if (std.mem.eql(u8, src.text(function.signature.return_type), "float")) return true;
        for (function.signature.parameters) |parameter| if (std.mem.eql(u8, src.text(parameter.ty), "float")) return true;
    }
    for (program.types.records) |record| for (record.fields) |field| if (std.mem.eql(u8, src.text(field.ty), "float")) return true;
    for (program.types.expressions.applications) |application| for (application.arguments) |argument| if (std.mem.eql(u8, src.text(argument), "float")) return true;
    for (program.types.expressions.aliases) |alias| if (std.mem.eql(u8, src.text(alias.target), "float")) return true;
    for (program.statements.items) |statement| if (statement.data == .binding) {
        if (statement.data.binding.annotation) |annotation| if (std.mem.eql(u8, src.text(annotation), "float")) return true;
    };
    return false;
}
