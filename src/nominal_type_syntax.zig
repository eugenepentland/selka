//! Detect nominal template syntax before selecting semantic catalog construction.
const Source = @import("source.zig").Source;
const ast = @import("ast.zig");
/// Whether the program declares or applies a parameterized nominal type.
pub fn present(program: ast.Program) bool {
    for (program.nodes.items) |node| if (node.data == .list_literal or node.data == .text or node.data == .dictionary_literal or node.data == .format) return true;
    inline for (.{ "records", "variants" }) |category| {
        for (@field(program.types, category)) |declaration| if (declaration.type_parameters.len != 0) return true;
    }
    for (program.functions) |function| for (function.signature.type_parameters) |parameter| {
        if (parameter.constant_length) return true;
    };
    if (program.types.expressions.callbacks.len != 0) return true;
    return program.types.expressions.applications.len != 0 or program.types.expressions.aliases.len != 0;
}

/// Select builtin nominal text/numeric schemas without requiring a generic use.
pub fn presentInSource(program: ast.Program, src: Source) bool {
    return present(program) or textUsed(src) or byteLiteral(program, src);
}

/// Recognize the `b` prefix that distinguishes managed byte strings from fixed arrays.
pub fn byteLiteral(program: ast.Program, src: Source) bool {
    for (program.nodes.items) |node| {
        if (node.data != .bytes) continue;
        const spelling = src.text(node.span);
        if (spelling.len != 0 and spelling[0] == 'b') return true;
    }
    return false;
}

/// Recognize the literal and constructor spellings that need the managed bytes prelude type.
pub fn bytesSyntax(program: ast.Program, src: Source) bool {
    const std = @import("std");
    if (byteLiteral(program, src)) return true;
    for (program.functions) |function| if (std.mem.eql(u8, src.text(function.name), "bytes")) return false;
    for (program.nodes.items) |node| {
        if (node.data != .call) continue;
        const call = node.data.call;
        if (call.owner) |owner| {
            if (std.mem.eql(u8, src.text(owner), "bytes") and std.mem.eql(u8, src.text(call.name), "fromhex")) return true;
        } else if (std.mem.eql(u8, src.text(call.name), "bytes")) return true;
    }
    return false;
}

/// Detect text/dictionary syntax without scanning quoted or commented words.
pub fn textUsed(src: Source) bool {
    return wordUsed(src, &.{ "str", "dict" });
}

/// Scan identifier words outside quoted literals and comments for any listed spelling.
pub fn wordUsed(src: Source, names: []const []const u8) bool {
    const std = @import("std");
    const bytes = src.bytes;
    var i: usize = 0;
    while (i < bytes.len) {
        if (bytes[i] == '"' or bytes[i] == '\'') {
            const quote = bytes[i];
            i += 1;
            while (i < bytes.len and bytes[i] != quote) {
                if (bytes[i] == '\\' and i + 1 < bytes.len) i += 1;
                i += 1;
            }
            if (i < bytes.len) i += 1;
        } else if (bytes[i] == '#' or (bytes[i] == '/' and i + 1 < bytes.len and bytes[i + 1] == '/')) {
            while (i < bytes.len and bytes[i] != '\n') i += 1;
        } else if (std.ascii.isAlphabetic(bytes[i]) or bytes[i] == '_') {
            const start = i;
            i += 1;
            while (i < bytes.len and (std.ascii.isAlphanumeric(bytes[i]) or bytes[i] == '_')) i += 1;
            const word = bytes[start..i];
            for (names) |name| if (std.mem.eql(u8, word, name)) return true;
        } else i += 1;
    }
    return false;
}

/// Materialize text only when a literal or explicit text type needs its schema.
pub fn textRequired(program: ast.Program, src: Source) bool {
    for (program.nodes.items) |node| if (node.data == .text or node.data == .format) return true;
    return textUsed(src);
}
