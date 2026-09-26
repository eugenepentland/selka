//! Transactional physical transfers for the RC emitter (RC-OWNERSHIP-PLAN-1).
//! A semantic last use still crosses the pin-aware runtime publication path.
const model = @import("rc_model.zig");

/// A malformed physical plan, rather than an unsupported guest program.
pub const Error = error{ InvalidState, TypeMismatch, CopyProhibited };
/// The emitter's reason for making an independent destination value.
pub const Intent = enum { copy, last_use };
/// Both slots immediately before a fallible ownership transaction.
pub const Slots = struct { source: model.ValueState, destination: model.ValueState };
/// One semantic publication and the identity of its successful result bundle.
pub const Input = struct {
    slots: Slots,
    intent: Intent,
    token: model.TokenId,
    checkpoint: model.Checkpoint,
};
/// Runtime operation; take is pin-aware and can allocate, unlike relocation.
pub const Operation = enum {
    plain,
    self,
    copy,
    take,
    /// Prepare incoming ownership before the separate unique-drop scheduler
    /// closes the old destination; generic RC replacement cannot do that close.
    take_unique,
};
/// One atomic replacement. Failure preserves the input slots exactly.
pub const Plan = struct {
    operation: Operation,
    before: Slots,
    success: Slots,
    checkpoint: model.Checkpoint,

    /// The cleanup state at this helper's failure edge, before any commit.
    pub fn failure(self: Plan) Slots {
        return self.before;
    }
};

/// Choose copy or take from physical ownership, never from a logical COW role.
pub fn plan(input: Input) Error!Plan {
    const source = input.slots.source;
    const destination = input.slots.destination;
    if (source.ty != destination.ty) return error.TypeMismatch;
    if (source.ownership == .empty) return error.InvalidState;
    if (destination.ownership == .borrowed or destination.ownership == .held) return error.InvalidState;
    if (source.ownership == .owned and source.ownership.owned.initialized != null) return error.InvalidState;
    if (destination.ownership == .owned and destination.ownership.owned.initialized != null) return error.InvalidState;
    var result: Plan = .{
        .operation = .plain,
        .before = input.slots,
        .success = input.slots,
        .checkpoint = input.checkpoint,
    };
    if (source.storage == destination.storage) {
        if (source.value != destination.value) return error.InvalidState;
        result.operation = .self;
        return result;
    }
    if (!source.shape.counted and !source.shape.unique_drop) {
        result.success.destination.ownership = .plain;
        return result;
    }
    if (source.ownership == .plain) return error.InvalidState;
    const taking = input.intent == .last_use and source.ownership == .owned;
    if (!taking and !source.shape.copyable) return error.CopyProhibited;
    result.operation = if (taking and source.shape.unique_drop) .take_unique else if (taking) .take else .copy;
    // Caller storage remains an external ownership obligation after a write.
    if (destination.ownership != .inout) result.success.destination.ownership = .{ .owned = .{ .token = input.token } };
    if (taking) result.success.source.ownership = .empty;
    return result;
}
