//! Bounded dependent-resource contracts use one input origin, never body inference.
const typed = @import("selka").typed;

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
    return ty.capabilityIndex() != null and !ty.isHandle() and ty != .host_cap;
}

/// The provider kinds a resource value can be acquired through: a `File` through a `Filesystem`, a declared
/// `resource X: kind` through its kind's provider (`acquire_resource` requires that provider type), a carrier through
/// those of what it holds. A `Clock`, `Entropy`, `Environment` or `Process` acquires no resource (RES-ORIGIN-2, FR90).
pub const Kinds = struct {
    filesystem: bool = false,
    network: bool = false,

    /// Whether a provider of type `ty` is one of these kinds.
    pub fn admits(self: Kinds, ty: typed.Type) bool {
        const kind = ty.resourceKind() orelse return false;
        return switch (kind) {
            .filesystem => self.filesystem,
            .network => self.network,
        };
    }
};

/// The kinds of `ty`, both when the walk is cut off at `depth` or finds none for a resource, so a provider stays counted
/// whenever its kind is not shown to be the other one.
pub fn kinds(program: typed.Program, ty: typed.Type) Kinds {
    const found = kindsWithin(program, ty, 8);
    return if (found.filesystem or found.network) found else .{ .filesystem = true, .network = true };
}

fn kindsWithin(program: typed.Program, ty: typed.Type, depth: u8) Kinds {
    if (ty.isFile()) return .{ .filesystem = true };
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return .{};
    if (depth == 0) return .{ .filesystem = true, .network = true };
    const record = program.records[ty.recordIndex()];
    if (record.shape.resource) |kind| return switch (kind) {
        .filesystem => .{ .filesystem = true },
        .network => .{ .network = true },
    };
    var out: Kinds = .{};
    const join = struct {
        fn into(sum: *Kinds, next: Kinds) void {
            sum.filesystem = sum.filesystem or next.filesystem;
            sum.network = sum.network or next.network;
        }
    };
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| join.into(&out, kindsWithin(program, payload, depth - 1));
    } else if (record.shape.array) |array| {
        join.into(&out, kindsWithin(program, array.element, depth - 1));
    } else for (record.fields) |field| join.into(&out, kindsWithin(program, field.ty, depth - 1));
    return out;
}

/// Whether a parameter of type `ty` holds a resource of the returned type `result`: that type, or a Result's payload.
pub fn ofResult(program: typed.Program, ty: typed.Type, result: typed.Type) bool {
    if (ty == result) return true;
    const shape = typed.resultShape(result, program.records) orelse return false;
    return ty == shape.ok_type or ty == shape.error_type;
}

/// The one `own` resource parameter of the returned resource's type, when there is exactly one (RES-ORIGIN-2, option C).
pub fn ownOrigin(program: typed.Program, function: typed.Function) ?usize {
    const result = function.signature.return_type;
    var found: ?usize = null;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
        const own = index < function.scope.own_parameters.len and function.scope.own_parameters[index];
        const resource = !provider(local.ty) and dependent(program, local.ty);
        if (!own or !resource) continue;
        if (!ofResult(program, local.ty, result)) continue;
        if (found != null) return null;
        found = index;
    }
    return found;
}

/// Whether parameter `index` can be the origin of `function`'s returned resource, by type (RES-ORIGIN-2): a resource
/// input, a provider of the result's kind, and, beside one `own` input of the result's type, no provider. A function that
/// does not return a resource counts every provider and resource, as before.
pub fn counted(program: typed.Program, function: typed.Function, index: usize) bool {
    const ty = function.scope.locals[index].ty;
    if (!provider(ty) and !dependent(program, ty)) return false;
    const result = function.signature.return_type;
    if (!dependent(program, result)) return true;
    if (!provider(ty)) return true;
    if (ownOrigin(program, function) != null) return false;
    return kinds(program, result).admits(ty);
}

/// A returned resource has exactly one possible origin input by signature (P3): the one `counted` input. When none is,
/// the one provider or resource input of the count before RES-ORIGIN-2, so no function it accepted loses its origin.
pub fn parameter(program: typed.Program, function: typed.Function) ?usize {
    var found: ?usize = null;
    for (0..function.signature.parameter_count) |index| {
        if (!counted(program, function, index)) continue;
        if (found != null) return null;
        found = index;
    }
    return found orelse every(program, function);
}

fn every(program: typed.Program, function: typed.Function) ?usize {
    var found: ?usize = null;
    for (function.scope.locals[0..function.signature.parameter_count], 0..) |local, index| {
        if (!provider(local.ty) and !dependent(program, local.ty)) continue;
        if (found != null) return null;
        found = index;
    }
    return found;
}
