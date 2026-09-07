//! Detect nominal template syntax before selecting semantic catalog construction.
const ast = @import("ast.zig");
/// Whether the program declares or applies a parameterized nominal type.
pub fn present(program: ast.Program) bool {
    inline for (.{ "records", "variants", "buffers", "pools" }) |category| {
        for (@field(program.types, category)) |declaration| if (declaration.type_parameters.len != 0) return true;
    }
    for (program.functions) |function| for (function.signature.type_parameters) |parameter| {
        if (parameter.constant_length) return true;
    };
    return program.types.expressions.applications.len != 0 or program.types.expressions.aliases.len != 0;
}
