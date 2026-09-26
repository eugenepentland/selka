//! Physical ownership identities and call conventions (RC-OWNERSHIP-PLAN-1).
//! Logical COW roles are inputs to planning, never an RC token ledger.
const typed = @import("typed.zig");
const shape = @import("rc_shape.zig");

/// An identity in one function's canonical physical storage table.
pub const StorageId = enum(u32) { _ };
/// One initialized ownership bundle, independent of its current storage.
pub const TokenId = enum(u32) { _ };
/// A compiler value version, including operand and join values.
pub const ValueId = enum(u32) { _ };
/// One conditional initialization result or branch discriminator.
pub const GuardId = enum(u32) { _ };
/// A pending receiver's separately balanced lifetime scope.
pub const ScopeId = enum(u32) { _ };

/// Why a borrowed value remains valid; scopes are lifetime holds, not owners.
pub const Anchor = union(enum) {
    storage: StorageId,
    parameter: u32,
    scope: ScopeId,
    immortal,
};

/// A bundle exists unconditionally, or only on a successful detached branch.
pub const Owned = struct { token: TokenId, initialized: ?GuardId = null };
/// Ownership of a value version; a hold never becomes an ordinary owner.
pub const Ownership = union(enum) {
    empty,
    plain,
    owned: Owned,
    borrowed: Anchor,
    inout: Anchor,
    held: ScopeId,
};
/// One typed value's physical storage and lifetime obligations.
pub const ValueState = struct {
    value: ValueId,
    ty: typed.Type,
    storage: StorageId,
    shape: shape.Shape,
    ownership: Ownership,
};

/// How a parameter's storage and token are lent or transferred to a callee.
pub const Parameter = enum {
    read,
    caller_storage,
    mutable_payload,
    /// Move-only guest arguments become the callee's cleanup obligation.
    consume_on_entry,
    consume_on_success,
};
/// A separate certificate is required before a result may be called borrowed.
pub const BorrowCertificate = struct {
    parameter: u32,
    shape_identity: [32]u8,
    dependency_identity: [32]u8,
};
/// Success result ownership; unknown or mixed provenance uses owned.
pub const Result = union(enum) { plain, owned, borrowed: BorrowCertificate };
/// Argument/result obligations when a call reports a runtime failure.
pub const Failure = enum {
    /// No output token. Read/inout inputs stay with the caller; entry-consumed
    /// arguments stay consumed even if admission fails before the body runs.
    /// Mutable contents may have changed before a guest trap.
    parameter_contracts,
    /// The helper's separately modeled checkpoints describe partial progress.
    checkpoints,
};
/// Caller-visible physical convention, separate from return-origin summaries.
pub const CallContract = struct {
    parameters: []const Parameter,
    result: Result,
    failure: Failure = .parameter_contracts,
    /// Parameters whose reachable storage the call may invalidate.
    mutates: []const u16 = &.{},
    /// The ownership/runtime ABI identity supplied by the resolved selector.
    abi: []const u8,
};

/// A source instruction's precise lowering state, including fallible substeps.
pub const Checkpoint = struct { pc: u32, step: u32 = 0 };
