//! Detect nominal template syntax before selecting semantic catalog construction.
const ast = @import("ast.zig");
/// Whether the program declares or applies a parameterized nominal type.
pub fn present(program: ast.Program) bool {
    inline for (.{ "records", "variants" }) |category| {
        for (@field(program.types, category)) |declaration| if (declaration.type_parameters.len != 0) return true;
    }
    return program.types.expressions.applications.len != 0;
}
