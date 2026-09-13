//! Detect nominal template syntax before selecting semantic catalog construction.
const Source = @import("source.zig").Source;
const ast = @import("ast.zig");
/// Whether the program declares or applies a parameterized nominal type.
pub fn present(program: ast.Program) bool {
    for (program.nodes.items) |node| if (node.data == .list_literal or node.data == .text or node.data == .dictionary_literal) return true;
    inline for (.{ "records", "variants", "buffers", "pools" }) |category| {
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
    return present(program) or textUsed(src);
}

/// Detect text/dictionary syntax without scanning quoted or commented words.
pub fn textUsed(src: Source) bool {
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
            if (std.mem.eql(u8, word, "str") or std.mem.eql(u8, word, "dict")) return true;
        } else i += 1;
    }
    return false;
}

/// Materialize text only when a literal or explicit text type needs its schema.
pub fn textRequired(program: ast.Program, src: Source) bool {
    for (program.nodes.items) |node| if (node.data == .text) return true;
    return textUsed(src);
}
