//! AST-only detection of nominal syntax that requires conservative semantic checking.
const ast = @import("ast.zig");

fn managedLiteral(node: ast.Node) bool {
    return switch (node.data) {
        .list_literal, .text, .dictionary_literal, .format, .comprehension => true,
        else => false,
    };
}

/// Whether the parsed program declares or applies a parameterized nominal type.
pub fn present(program: ast.Program) bool {
    for (program.nodes.items) |node| if (managedLiteral(node)) return true;
    inline for (.{ "records", "variants" }) |category| {
        for (@field(program.types, category)) |declaration| if (declaration.type_parameters.len != 0) return true;
    }
    for (program.functions) |function| for (function.signature.type_parameters) |parameter| {
        if (parameter.constant_length) return true;
    };
    if (program.types.expressions.callbacks.len != 0) return true;
    return program.types.expressions.applications.len != 0 or program.types.expressions.aliases.len != 0;
}
