//! Bounded dependent-resource contracts use one input origin, never body inference.
const typed = @import("mylang").typed;

/// Ordinary resources already have affine source semantics, including their carriers.
pub fn affine(program: typed.Program, ty: typed.Type) bool {
    return typed.moveOnly(ty, program.records);
}

/// Builtin file results borrow the same single named provider as generic owners.
/// Admit only a direct Result payload; stored file aggregates remain unsupported.
pub fn dependent(program: typed.Program, ty: typed.Type) bool {
    if (ty.isFile() or affine(program, ty)) return true;
    const shape = typed.resultShape(ty, program.records) orelse return false;
    return shape.ok_type.isFile() or shape.error_type.isFile();
}

/// A provider is borrowed by resources created through it; streams are scalar handles.
pub fn provider(ty: typed.Type) bool {
    return ty.capabilityIndex() != null and !ty.isStream() and ty != .host_cap;
}

/// A returned resource has exactly one possible provider/resource input by signature.
pub fn parameter(program: typed.Program, function: typed.Function) ?usize {
    var found: ?usize = null;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
        if (!provider(local.ty) and !dependent(program, local.ty)) continue;
        if (found != null) return null;
        found = index;
    }
    return found;
}
