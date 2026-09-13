//! Decimal floating syntax and demand detection without changing scalar wire identities.
const std = @import("std");
const ast = @import("ast.zig");
const Source = @import("source.zig").Source;

/// Decimal points or exponent markers distinguish floating tokens from integer suffixes.
pub fn isLiteral(text: []const u8) bool {
    return std.mem.indexOfAny(u8, text, ".eE") != null;
}

/// Scan one numeric token, retaining malformed suffixes for a precise checker diagnostic.
pub fn end(bytes: []const u8, start: usize) usize {
    var at = start;
    while (at < bytes.len and std.ascii.isDigit(bytes[at])) at += 1;
    if (at + 1 < bytes.len and bytes[at] == '.' and std.ascii.isDigit(bytes[at + 1])) {
        at += 1;
        while (at < bytes.len and std.ascii.isDigit(bytes[at])) at += 1;
    }
    if (at < bytes.len and (bytes[at] == 'e' or bytes[at] == 'E')) {
        at += 1;
        if (at < bytes.len and (bytes[at] == '+' or bytes[at] == '-')) at += 1;
    }
    while (at < bytes.len and std.ascii.isAlphanumeric(bytes[at])) at += 1;
    return at;
}

/// Only programs spelling float types, conversions, or literals materialize its schema.
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
