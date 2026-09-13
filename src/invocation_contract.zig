//! Authority-free invocation types, independent of the VM implementation.
const std = @import("std");
const typed = @import("typed.zig");
/// Host failures and invalid checked execution state returned by the VM.
pub const RunError = error{
    BorrowConflict,
    BorrowSuspended,
    Bounds,
    CapabilityUnavailable,
    CapacityLimit,
    ChildrenActive,
    Closed,
    Denied,
    ExpiredBorrow,
    Failed,
    ForeignMemory,
    IdentityExhausted,
    InternalError,
    InvalidAggregateType,
    InvalidAllocation,
    InvalidBudget,
    InvalidCapability,
    InvalidDataType,
    InvalidDataValue,
    InvalidOwner,
    InvalidProvider,
    InvalidValueLimits,
    MemoryClosed,
    NoCapacity,
    NotDataType,
    OutOfMemory,
    ReadOnly,
    RegionInUse,
    ResourceLimit,
    TypeMismatch,
    Unavailable,
    ValueCountLimit,
    ValueDepthLimit,
    ValueTypeMismatch,
};
/// Invocation additionally checks exported function identity and argument contracts.
pub const InvokeError = RunError || error{ InvocationArity, InvocationEffects, PrivateInvocationFunction, UnknownInvocationFunction };
/// Owned typed invocation result or a source-located runtime trap.
pub const ValueResult = union(enum) { value: typed.Value, trap: @import("diagnostic.zig").Diagnostic };
/// Authority-free invocation limits and checked argument-copy limits.
pub const InvokeOptions = struct {
    max_steps: u64 = 1_000_000,
    max_frames: u64 = 256,
    arguments: @import("value_copy.zig").Limits = .{},
    steps_executed: ?*u64 = null,
};
/// Injectable checked invocation used by codecs without a dependency on the VM.
pub const Dispatch = *const fn (
    std.mem.Allocator,
    @import("bytecode_model.zig").Program,
    typed.FunctionId,
    []const typed.Value,
    InvokeOptions,
) InvokeError!ValueResult;

/// Context-bearing synchronous dispatch for compiled providers with no global binding.
pub const Contextual = struct {
    context: *anyopaque,
    dispatch: *const fn (*anyopaque, std.mem.Allocator, @import("bytecode_model.zig").Program, typed.FunctionId, []const typed.Value, InvokeOptions) InvokeError!ValueResult,
};
