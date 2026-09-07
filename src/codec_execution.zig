//! Per-operation codec calls: no authority injection or implicit domain wrapping.
/// Failures returned by invoke; callers must handle these boundary errors.
pub const InvokeError = error{
    BorrowConflict,
    BorrowSuspended,
    Bounds,
    CapabilityUnavailable,
    CapacityLimit,
    ChildrenActive,
    Closed,
    CodecCallLimit,
    CodecStepLimit,
    Denied,
    DomainCodecTrap,
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
    InvocationArity,
    InvocationEffects,
    InvocationReference,
    InvocationTrap,
    MemoryClosed,
    NoCapacity,
    NotDataType,
    OutOfMemory,
    PrivateInvocationFunction,
    ReadOnly,
    RegionInUse,
    ResourceLimit,
    TypeMismatch,
    Unavailable,
    UnknownInvocationFunction,
    ValueCountLimit,
    ValueDepthLimit,
    ValueTypeMismatch,
};
/// Failures returned by decode; callers must handle these boundary errors.
pub const DecodeError = InvokeError || error{
    DomainCodecRejected,
    InvalidCodecContract,
    NoImplicitCodec,
};
/// Failures returned by encode; callers must handle these boundary errors.
pub const EncodeError = InvokeError || error{
    InvalidCodecContract,
    NoImplicitCodec,
};

const std = @import("std");
const typed = @import("typed.zig");
const invocation = @import("invocation_contract.zig");
/// Domain identity, owned decoder rejection, or guest trap retained by a failed codec call.
pub const Failure = struct {
    domain: ?typed.Type = null,
    rejection: ?typed.Value = null,
    trap: ?@import("diagnostic.zig").Diagnostic = null,
    pub fn deinit(self: *Failure, allocator: std.mem.Allocator) void {
        if (self.rejection) |value| value.release(allocator);
        self.* = .{};
    }
};
/// Checked program paired with its authority-free invocation implementation.
pub const Backend = struct { program: @import("bytecode.zig").Program, dispatch: invocation.Dispatch };
/// Shares guest instruction and invocation quotas across a complete codec operation.
pub const Execution = struct {
    backend: Backend,
    max_steps: u64,
    max_frames: u64,
    max_calls: usize,
    arguments: @import("value_copy.zig").Limits,
    failure: *Failure,
    used: struct { steps: u64 = 0, calls: usize = 0 } = .{},
    fn call(self: *Execution, allocator: std.mem.Allocator, domain: ?typed.Type, id: typed.FunctionId, inputs: []const typed.Value) !typed.Value {
        if (self.used.calls == self.max_calls) return error.CodecCallLimit;
        if (self.used.steps == self.max_steps) return error.CodecStepLimit;
        self.used.calls += 1;
        var executed: u64 = 0;
        defer self.used.steps += executed;
        const result = try self.backend.dispatch(allocator, self.backend.program, id, inputs, .{ .max_steps = self.max_steps - self.used.steps, .max_frames = self.max_frames, .arguments = self.arguments, .steps_executed = &executed });
        return switch (result) {
            .value => |value| value,
            .trap => |trap| {
                self.failure.domain = domain;
                self.failure.trap = trap;
                return if (domain != null) error.DomainCodecTrap else error.InvocationTrap;
            },
        };
    }
    /// Call a checked function without injected authority and return its owned typed result.
    pub fn invoke(self: *Execution, allocator: std.mem.Allocator, id: typed.FunctionId, inputs: []const typed.Value) InvokeError!typed.Value {
        return self.call(allocator, null, id, inputs);
    }
    fn validateContract(self: *Execution, allocator: std.mem.Allocator) (std.mem.Allocator.Error || error{InvalidCodecContract})!void {
        @import("codec_bytecode.zig").validate(allocator, self.backend.program) catch |err| return switch (err) {
            error.OutOfMemory => error.OutOfMemory,
            error.InternalError => error.InvalidCodecContract,
        };
    }
    /// Run the declared domain decoder, retaining its typed rejection when it returns err.
    pub fn decode(self: *Execution, allocator: std.mem.Allocator, domain: typed.Type, input: typed.Value) DecodeError!typed.Value {
        const codec = self.backend.program.records[domain.recordIndex()].contract.codec orelse return error.NoImplicitCodec;
        try self.validateContract(allocator);
        const result = try self.call(allocator, domain, codec.decode, &.{input});
        defer result.release(allocator);
        const shape = typed.resultShape(result.typeOf(), self.backend.program.records) orelse return error.InvalidCodecContract;
        if (shape.ok_type != domain or result != .aggregate or result.aggregate.fields.len != 1) return error.InvalidCodecContract;
        const tag = try result.variantTag();
        if (tag == shape.ok_tag) return result.aggregate.fields[0].retain();
        if (tag != shape.error_tag) return error.InvalidCodecContract;
        self.failure.domain = domain;
        self.failure.rejection = result.aggregate.fields[0].retain();
        return error.DomainCodecRejected;
    }
    /// Run the declared domain encoder under the operation's remaining quotas.
    pub fn encode(self: *Execution, allocator: std.mem.Allocator, domain: typed.Type, input: typed.Value) EncodeError!typed.Value {
        const codec = self.backend.program.records[domain.recordIndex()].contract.codec orelse return error.NoImplicitCodec;
        try self.validateContract(allocator);
        const result = try self.call(allocator, domain, codec.encode, &.{input});
        errdefer result.release(allocator);
        if (result.typeOf() != codec.wire) return error.InvalidCodecContract;
        return result;
    }
};
