//! Restricted evaluation foundation: checked call graph, no injected authority,
//! and a fixed VM allocation budget independent of frontend/source storage.
/// Failures returned by evaluate; callers must handle these boundary errors.
pub const EvaluateError = error{
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
    SourceError,
    TypeMismatch,
    Unavailable,
    ValueCountLimit,
    ValueDepthLimit,
    ValueTypeMismatch,
};

const std = @import("std");
const bc = @import("bytecode.zig");
const diagnostic = @import("diagnostic.zig");
const vm = @import("vm.zig");
/// Instruction, frame, and live-byte limits for authority-free scalar evaluation.
pub const Options = struct { max_steps: u64 = 1_000_000, max_frames: u64 = 256, max_bytes: usize = 16 * 1024 * 1024 };
/// Reject authority-bearing programs and evaluate a scalar result with bounded resources.
pub fn evaluate(allocator: std.mem.Allocator, program: bc.Program, sink: *diagnostic.Sink, options: Options) EvaluateError!vm.Result {
    return (try process(allocator, program, sink, options, true)).?;
}
/// Null means eligible for evaluation; it does not establish execution or a value.
pub fn preflight(allocator: std.mem.Allocator, program: bc.Program, sink: *diagnostic.Sink, options: Options) EvaluateError!?diagnostic.Diagnostic {
    return if (try process(allocator, program, sink, options, false)) |result| result.trap else null;
}
fn process(allocator: std.mem.Allocator, program: bc.Program, sink: *diagnostic.Sink, options: Options, execute: bool) !?vm.Result {
    if (options.max_steps == 0 or options.max_frames == 0 or options.max_bytes == 0) return error.InvalidBudget;
    const storage = try allocator.alloc(u8, options.max_bytes);
    defer allocator.free(storage);
    var fixed = std.heap.FixedBufferAllocator.init(storage);
    const bounded = fixed.allocator();
    bc.validate(bounded, program) catch |err| switch (err) {
        error.OutOfMemory => return memoryTrap(),
        else => return err,
    };
    const entry = program.functions[@backingInt(program.main)];
    const span = entry.scope.instructions[0].span;
    if (entry.policy.effects != 0) return sink.fail("E_EVAL_EFFECT", span, "compile-time evaluation requires an effect-free entry call graph, including untaken branches");
    if (entry.signature.parameter_count != 0) return sink.fail("E_EVAL_INPUT", span, "compile-time entry must have no parameters or injected capabilities");
    if (!execute) return null;
    return vm.runWithOptions(bounded, program, .{
        .max_steps = options.max_steps,
        .max_frames = options.max_frames,
    }) catch |err| switch (err) {
        error.OutOfMemory => memoryTrap(),
        else => return err,
    };
}

fn memoryTrap() vm.Result {
    return .{ .trap = .{ .code = "R_EVAL_MEMORY", .span = .{ .start = 0, .end = 0 }, .message = "compile-time VM allocation budget exhausted (includes bytecode validation and bookkeeping)" } };
}
