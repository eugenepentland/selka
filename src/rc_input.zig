//! The finalized analysis boundary consumed by RC planning.
const ownership = @import("ownership_model.zig");
const model = @import("rc_model.zig");

/// One actual storage identity; a logical ownership role cannot substitute.
pub const Binding = struct {
    storage: model.StorageId,
    /// Present only when this slot physically borrows another value's storage.
    anchor: ?model.Anchor = null,
};
/// Facts after retained COW parents/keys have reached the liveness fixpoint.
pub const Flow = struct {
    live: @import("qbe_liveness.zig").Solution,
    ownership: ownership.Analysis,
};
/// Native count shapes and the emitter's actual local-storage aliases.
pub const Physical = struct {
    catalog: *@import("rc_shape.zig").Catalog,
    locals: []const Binding,
};
/// Final mutation placement; planning must not rerun weaker lifetime analysis.
pub const Mutation = struct { places: @import("cow_plan.zig").Plan = .{} };
/// Physical call conventions, with no provenance-to-ownership substitution.
pub const Contracts = struct {
    current: model.CallContract,
    functions: []const model.CallContract = &.{},
};
/// The resolved artifact convention that must match every planned call.
pub const Policy = struct { abi: []const u8 };
/// Inputs borrowed for the lifetime of one function compilation arena.
pub const Input = struct {
    code: ownership.Code,
    flow: Flow,
    physical: Physical,
    mutation: Mutation = .{},
    contracts: Contracts,
    policy: Policy,
};
