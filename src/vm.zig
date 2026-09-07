//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const callables = @import("callables.zig");
const capability_code = "R_CAPABILITY";
const slice_bounds_code = "R_SLICE_BOUNDS";
const overflow_code = "R_OVERFLOW";
const reference_lifetime_code = "R_REFERENCE_LIFETIME";
const inactive_reference_message = "reference is not active";
const inactive_slice_message = "slice is not active";
const host = @import("host_functions.zig");
const vm_host = @import("vm_host.zig");
const value_copy = @import("value_copy.zig");
const std = @import("std");
const invocation_contract = @import("invocation_contract.zig");
const bc = @import("bytecode.zig");
const integers = @import("integers.zig");
const typed = @import("typed.zig");
const memory = @import("memory.zig");
const external = @import("external_capabilities.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const environment = @import("environment.zig");
const pool_runtime = @import("pool_runtime.zig");
const resource_runtime = @import("resource_runtime.zig");
/// Select independent general allocations or arena-backed VM storage.
/// Host failures and invalid checked execution state returned by the VM.
pub const RunError = invocation_contract.RunError;
/// Invocation additionally checks exported function identity and argument contracts.
pub const InvokeError = invocation_contract.InvokeError;
/// Select general allocation or arena backing for a VM execution.
pub const MemoryBacking = enum { general, arena };
/// Execution quotas, optional statistics, and explicitly supplied host authority.
pub const Options = struct {
    pools: PoolOptions = .{},
    memory: MemoryOptions = .{},
    environment: ?environment.Provider = null,
    resources: resource_runtime.Options = .{},
    external: external.Providers = .{},
    max_steps: u64 = 10_000_000,
    max_frames: u64 = 1024,
};
/// Backing policy, owner quotas, and optional execution-memory observations.
pub const MemoryOptions = struct {
    backing: MemoryBacking = .general,
    /// Optional guest buffer/pool backing allocator; excludes snapshots and VM metadata.
    backing_allocator: ?std.mem.Allocator = null,
    limits: memory.Limits = .{},
    statistics: ?*memory.Statistics = null,
    provide_allocator: bool = true,
    trace: ?*@import("vm_trace.zig").Trace = null,
};
/// Pool quotas and optional observations copied after execution cleanup.
pub const PoolOptions = struct {
    limits: pool_runtime.Limits = .{},
    statistics: ?*pool_runtime.Statistics = null,
};
/// Scalar entry-point outcome or a source-located runtime trap.
pub const Result = union(enum) { value: i64, trap: Diagnostic };
pub const Value = typed.Value;
/// Owned typed invocation result or a source-located runtime trap.
pub const ValueResult = invocation_contract.ValueResult;
/// Authority-free invocation limits and checked argument-copy limits.
pub const InvokeOptions = invocation_contract.InvokeOptions;
fn integer(value: typed.Value, allocator: std.mem.Allocator) error{InternalError}!i64 {
    defer value.release(allocator);
    if (value != .i64) return error.InternalError;
    return value.i64;
}
fn numeric(stack: *std.ArrayList(typed.Value), base: usize, expected: ?typed.Type, allocator: std.mem.Allocator) !i128 {
    const value = try pop(stack, base);
    defer value.release(allocator);
    if (!value.typeOf().isInteger()) return error.InternalError;
    if (expected) |ty| if (value.typeOf() != ty) {
        return error.InternalError;
    };
    return value.asInteger();
}
fn boolean(value: typed.Value, allocator: std.mem.Allocator) error{InternalError}!bool {
    defer value.release(allocator);
    if (value != .bool) return error.InternalError;
    return value.bool;
}
fn releaseValues(values: []const typed.Value, allocator: std.mem.Allocator) void {
    var i = values.len;
    while (i != 0) {
        i -= 1;
        values[i].release(allocator);
    }
}
fn pushOwned(stack: *std.ArrayList(typed.Value), allocator: std.mem.Allocator, value: typed.Value) !void {
    errdefer value.release(allocator);
    try stack.append(allocator, value);
}
const Span = @import("source.zig").Span;
const Slice = struct { start: usize, length: usize };
const Reference = struct { direct: bool = false, lease: memory.Borrow, slice: ?Slice = null };
const ReturnTarget = struct { destination: usize, parent: memory.Borrow, allocation: memory.Allocation, mutable: bool };
const CapturedReference = struct { direct: bool = false, slice: ?Slice };
const ActiveRegion = struct { capability: memory.AllocatorCapability, slot: typed.LocalId };
const Frame = struct {
    region_base: usize = 0,
    return_target: ?ReturnTarget = null,
    captured: ?CapturedReference = null,
    reference_base: usize = 0,
    function: typed.FunctionId,
    pc: usize = 0,
    local_base: usize,
    operand_base: usize,
    call_span: Span,
};
fn reborrowFull(store: *memory.Store, parent: memory.Borrow, kind: memory.Kind) memory.Error!memory.Borrow {
    const view = try store.describe(parent);
    return store.reborrow(parent, 0, view.length, kind);
}
fn trap(code: []const u8, message: []const u8, span: Span, frames: []const Frame, program: bc.Program) ValueResult {
    var diagnostic: Diagnostic = .{ .code = code, .message = message, .span = span };
    var i = frames.len;
    var at = span;
    while (i > 0 and diagnostic.stack.len < diagnostic.stack.frames.len) {
        i -= 1;
        const frame = frames[i];
        diagnostic.stack.frames[diagnostic.stack.len] = .{ .function = program.functions[@backingInt(frame.function)].name, .span = at };
        diagnostic.stack.len += 1;
        at = frame.call_span;
    }
    diagnostic.stack.omitted = i;
    return .{ .trap = diagnostic };
}
fn overflow(instruction: bc.Instruction, frames: []const Frame, program: bc.Program) ValueResult {
    return trap(overflow_code, "integer arithmetic overflowed i64", instruction.span, frames, program);
}
fn pop(stack: *std.ArrayList(typed.Value), base: usize) error{InternalError}!typed.Value {
    if (stack.items.len <= base) return error.InternalError;
    return stack.pop().?;
}
/// Execute the program entry point with default limits and return its scalar outcome.
pub fn run(allocator: std.mem.Allocator, program: bc.Program) RunError!Result {
    return runWithOptions(allocator, program, .{});
}
/// Execute the entry point with explicit quotas and host providers.
pub fn runWithOptions(allocator: std.mem.Allocator, program: bc.Program, options: Options) RunError!Result {
    return switch (try runValues(allocator, program, options, .{ .id = program.main })) {
        .value => |value| .{ .value = try integer(value, allocator) },
        .trap => |diagnostic| .{ .trap = diagnostic },
    };
}
/// Execute interpreted main with exact registered host functions and fresh callback budgets.
pub fn runWithHost(allocator: std.mem.Allocator, program: bc.Program, options: Options, registry: *vm_host.Registry, limits: host.Limits) (RunError || vm_host.Error)!Result {
    try bc.validate(allocator, program);
    const session = try registry.begin(allocator, program, limits);
    defer session.close() catch |err| std.debug.panic("VM host session cleanup failed: {s}", .{@errorName(err)});
    return switch (try runValues(allocator, program, options, .{ .id = program.main, .host = .{ .registry = registry, .session = session } })) {
        .value => |value| .{ .value = try integer(value, allocator) },
        .trap => |diagnostic| .{ .trap = diagnostic },
    };
}
/// Invoke a checked effect-free function with borrowed ordinary arguments. Input
/// storage is copied; the caller owns a returned value in the supplied allocator.
/// Module export selection belongs to the project API, not this bytecode layer.
pub fn invoke(allocator: std.mem.Allocator, program: bc.Program, function_id: typed.FunctionId, arguments: []const typed.Value, options: InvokeOptions) InvokeError!ValueResult {
    return runInvocation(allocator, program, options, try invocationEntry(allocator, program, function_id, arguments, options, 0));
}
/// Ordinary typed guest invocation with registered host effects and copied inputs.
pub const HostInvokeOptions = struct { execution: InvokeOptions = .{}, callbacks: host.Limits = .{} };
/// Host-enabled invocation preserves ordinary argument/export errors and rejects host-only entries.
pub const HostInvokeError = InvokeError || vm_host.Error || error{InvocationHostDeclaration};
/// Invoke a guest function with typed values and registered callbacks; caller owns the result.
pub fn invokeWithHost(allocator: std.mem.Allocator, program: bc.Program, function_id: typed.FunctionId, arguments: []const typed.Value, registry: *vm_host.Registry, options: HostInvokeOptions) HostInvokeError!ValueResult {
    var entry = try invocationEntry(allocator, program, function_id, arguments, options.execution, @import("effect_set.zig").all);
    if (program.functions[@backingInt(function_id)].policy.host != null) return error.InvocationHostDeclaration;
    const session = try registry.begin(allocator, program, options.callbacks);
    defer session.close() catch |err| std.debug.panic("VM host session cleanup failed: {s}", .{@errorName(err)});
    entry.host = .{ .registry = registry, .session = session };
    return runInvocation(allocator, program, options.execution, entry);
}
fn invocationEntry(allocator: std.mem.Allocator, program: bc.Program, function_id: typed.FunctionId, arguments: []const typed.Value, options: InvokeOptions, allowed_effects: @import("effect_set.zig").Mask) InvokeError!Entry {
    if (options.steps_executed) |steps| steps.* = 0;
    if (options.max_steps == 0 or options.max_frames == 0) return error.InvalidBudget;
    if (options.arguments.max_values == 0 or options.arguments.max_depth == 0 or options.arguments.max_depth > 128) return error.InvalidValueLimits;
    try bc.validate(allocator, program);
    if (@backingInt(function_id) >= program.functions.len) return error.UnknownInvocationFunction;
    const function = program.functions[@backingInt(function_id)];
    if (function.policy.restricted) return error.PrivateInvocationFunction;
    if (function.policy.effects & ~allowed_effects != 0) return error.InvocationEffects;
    if (function.signature.return_reference != null) return error.InvocationReference;
    if (arguments.len != function.signature.parameter_count) return error.InvocationArity;
    try @import("data_type.zig").check(allocator, program.records, function.signature.return_type, true);
    for (function.scope.locals[0..function.signature.parameter_count]) |parameter| {
        if (parameter.parameter.reference_parameter != null) return error.InvocationReference;
        try @import("data_type.zig").check(allocator, program.records, parameter.ty, true);
    }
    return .{ .id = function_id, .arguments = arguments, .limits = options.arguments, .steps_executed = options.steps_executed };
}
fn runInvocation(allocator: std.mem.Allocator, program: bc.Program, options: InvokeOptions, entry: Entry) RunError!ValueResult {
    return runValues(allocator, program, .{ .max_steps = options.max_steps, .max_frames = options.max_frames, .memory = .{
        .provide_allocator = false,
    } }, entry);
}

const HostExecution = struct { registry: *const vm_host.Registry, session: host.Session };
const Entry = struct {
    host: ?HostExecution = null,
    id: typed.FunctionId,
    arguments: ?[]const typed.Value = null,
    limits: value_copy.Limits = .{},
    steps_executed: ?*u64 = null,
};
fn runValues(allocator: std.mem.Allocator, program: bc.Program, options: Options, entry_request: Entry) !ValueResult {
    var steps: u64 = 0;
    defer if (entry_request.steps_executed) |out| {
        out.* = steps;
    };
    if (options.max_steps == 0 or options.max_frames == 0) return error.InvalidBudget;
    try bc.validate(allocator, program);
    if (entry_request.host == null) for (program.functions) |function| {
        if (function.policy.host) |span| return trap("R_HOST_REGISTRATION", "program requires explicitly registered host functions", span, &.{}, program);
    };
    var region: @import("arena.zig").Arena = undefined;
    try region.initWithBacking(allocator, options.memory.backing_allocator orelse allocator, options.memory.limits);
    const storage = &region.store;
    if (options.memory.backing == .general) storage.backing.allocator = options.memory.backing_allocator;
    defer {
        region.deinit();
        if (options.memory.statistics) |statistics| statistics.* = storage.statistics;
    }
    var pools: pool_runtime.Runtime = .{ .allocator = allocator, .limits = options.pools.limits };
    defer {
        std.debug.assert(pools.statistics.live_pools == 0);
        if (options.pools.statistics) |statistics| statistics.* = pools.statistics;
    }
    var environment_execution = environment.Runtime.init(storage.identity, options.environment);
    defer environment_execution.close();
    var resource_execution = try resource_runtime.Runtime.init(allocator, options.resources);
    defer resource_execution.deinit();
    var external_runtime = external.Runtime.init(storage.identity, options.external);
    defer external_runtime.close();
    var owners: std.AutoHashMapUnmanaged(usize, memory.Allocation) = .empty;
    defer owners.deinit(allocator);
    var references: std.ArrayList(?Reference) = .empty;
    defer references.deinit(allocator);
    var stack: std.ArrayList(typed.Value) = .empty;
    var locals: std.ArrayList(?typed.Value) = .empty;
    defer {
        var i = locals.items.len;
        while (i != 0) {
            i -= 1;
            if (locals.items[i]) |owned| owned.release(allocator);
        }
        locals.deinit(allocator);
    }
    defer {
        releaseValues(stack.items, allocator);
        stack.deinit(allocator);
    }
    var active_regions: std.ArrayList(ActiveRegion) = .empty;
    defer active_regions.deinit(allocator);
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(allocator);
    try locals.resize(allocator, program.functions[@backingInt(entry_request.id)].scope.locals.len);
    @memset(locals.items, null);
    const entry = program.functions[@backingInt(entry_request.id)];
    var copier: value_copy.Copier = .{ .records = program.records, .limits = entry_request.limits };
    for (entry.scope.locals[0..entry.signature.parameter_count], 0..) |parameter, index| {
        if (entry_request.arguments) |values| {
            locals.items[index] = try copier.copy(allocator, parameter.ty, values[index]);
        } else if (parameter.ty == .allocator) {
            if (!options.memory.provide_allocator) return error.CapabilityUnavailable;
            locals.items[index] = .{ .capability = .{ .allocator = try storage.allocatorCapability() } };
        } else if (parameter.ty == .environment_cap) {
            locals.items[index] = .{ .capability = .{ .environment_capability = try environment_execution.grant() } };
        } else if (parameter.ty.resourceKind()) |kind| {
            locals.items[index] = try resource_execution.grant(kind);
        } else {
            locals.items[index] = .{ .capability = .{ .external = try external_runtime.grant(parameter.ty.externalKind().?) } };
        }
    }
    try references.resize(allocator, program.functions[@backingInt(entry_request.id)].scope.references.len);
    @memset(references.items, null);
    try frames.append(allocator, .{ .function = entry_request.id, .local_base = 0, .operand_base = 0, .call_span = .{ .start = 0, .end = 0 } });
    var execution: Execution = .{
        .allocator = allocator,
        .program = program,
        .options = options,
        .steps = &steps,
        .storage = storage,
        .pools = &pools,
        .providers = .{ .host = entry_request.host, .environment = &environment_execution, .resources = &resource_execution, .external = &external_runtime },
        .state = .{ .stack = &stack, .locals = &locals, .owners = &owners, .references = &references, .active_regions = &active_regions, .frames = &frames },
    };
    while (frames.items.len != 0) {
        // Copy frame metadata before any grow; no references survive reallocations.
        const frame_index = frames.items.len - 1;
        const frame = frames.items[frame_index];
        const function = program.functions[@backingInt(frame.function)];
        if (frame.pc >= function.scope.instructions.len) return error.InternalError;
        const instruction = function.scope.instructions[frame.pc];
        if (steps == options.max_steps) return trap("R_STEP_LIMIT", "instruction budget exhausted", instruction.span, frames.items, program);
        steps += 1;
        if (options.memory.trace) |trace| trace.record(frame.function, frame.pc, steps, instruction, stack.items[frame.operand_base..]);
        frames.items[frame_index].pc += 1;
        var step: Step = .{ .execution = &execution, .frame = frame, .frame_index = frame_index, .instruction = instruction };
        const outcome = try switch (instruction.op) {
            .try_result => step.executeTryResult(),
            .acknowledge => step.executeAcknowledge(),
            .pop => step.executePop(),
            .jump => step.executeJump(),
            .jump_if_false => step.executeJumpIfFalse(),
            .div_i64_checked, .rem_i64_checked => step.executeDivI64Checked(),
            .make_record => step.executeMakeRecord(),
            .update_record => step.executeUpdateRecord(),
            .get_index => step.executeGetIndex(),
            .replace_index => step.executeReplaceIndex(),
            .array_length => step.executeArrayLength(),
            .make_variant => step.executeMakeVariant(),
            .switch_variant => step.executeSwitchVariant(),
            .reset_arena => step.executeResetArena(),
            .begin_region => step.executeBeginRegion(),
            .end_region => step.executeEndRegion(),
            .cmp_handle => step.executeCmpHandle(),
            .cmp_domain => step.executeCmpDomain(),
            .cmp_enum => step.executeCmpEnum(),
            .wrap_domain => step.executeWrapDomain(),
            .unwrap_domain => step.executeUnwrapDomain(),
            .get_field => step.executeGetField(),
            .push_integer => step.executePushInteger(),
            .function_value => step.executeFunctionValue(),
            .invoke => step.executeCall(),
            .unary_float => step.executeUnaryFloat(),
            .cast_integer, .neg_integer => step.executeCastInteger(),
            .binary_integer => step.executeBinaryInteger(),
            .push_i64 => step.executePushI64(),
            .push_bool => step.executePushBool(),
            .begin_borrow, .begin_slice => step.executeBeginBorrow(),
            .split_borrow => step.executeSplitBorrow(),
            .end_borrow => step.executeEndBorrow(),
            .len_slice => step.executeLenSlice(),
            .read_slice => step.executeReadSlice(),
            .write_slice => step.executeWriteSlice(),
            .read_ref => step.executeReadRef(),
            .write_ref => step.executeWriteRef(),
            .pool_operation => step.executePoolOperation(),
            .buffer_operation => step.executeBufferOperation(),
            .acquire_resource => step.executeAcquireResource(),
            .resource_io => step.executeResourceIo(),
            .restrict_resource => step.executeRestrictResource(),
            .environment_get => step.executeEnvironmentGet(),
            .complete_resource => step.executeCompleteResource(),
            .external_read => step.executeExternalRead(),
            .acquire_pool => step.executeAcquirePool(),
            .acquire_buffer => step.executeAcquireBuffer(),
            .json_codec => step.executeJson(),
            .move_local => step.executeMoveLocal(),
            .drop_local => step.executeDropLocal(),
            .take_field => step.executeTakeField(),
            .read_field => step.executeReadField(),
            .load_local => step.executeLoadLocal(),
            .store_local => step.executeStoreLocal(),
            .capture_ref => step.executeCaptureRef(),
            .call, .call_refs, .call_borrow => step.executeCall(),
            .ret, .ret_ref => step.executeRet(),
            .not_bool => step.executeNotBool(),
            .neg_i64_checked => step.executeNegI64Checked(),
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked => step.executeAddI64Checked(),
            .cmp_i64 => step.executeCmpI64(),
            .cmp_bool => step.executeCmpBool(),
        };
        if (outcome) |result| return result;
    }
    return error.InternalError;
}

fn arrayIndex(value: typed.Value, schema: typed.Array) error{InternalError}!i128 {
    if (schema.key) |key| {
        if (value.typeOf() != key) return error.InternalError;
        const tag = try value.variantTag();
        return tag;
    }
    return value.asInteger();
}

fn memoryFailure(err: memory.Error, instruction: bc.Instruction, frames: []const Frame, program: bc.Program) error{ OutOfMemory, IdentityExhausted }!?ValueResult {
    return switch (err) {
        error.RegionInUse => trap("R_REGION_IN_USE", "arena backing still has live owners", instruction.span, frames, program),
        error.InvalidCapability => trap(capability_code, "allocator capability is not valid for this execution", instruction.span, frames, program),
        error.OutOfMemory => error.OutOfMemory,
        error.IdentityExhausted => error.IdentityExhausted,
        error.BorrowConflict => trap("R_BORROW_CONFLICT", "access conflicts with an active borrow", instruction.span, frames, program),
        error.BorrowSuspended => trap("R_BORROW_SUSPENDED", "reference is suspended by an active child borrow", instruction.span, frames, program),
        error.ReadOnly => trap("R_REFERENCE_READ_ONLY", "reference does not permit writing", instruction.span, frames, program),
        error.Bounds => trap("R_REFERENCE_BOUNDS", "reference access is outside its bounds", instruction.span, frames, program),
        error.TypeMismatch => trap("R_REFERENCE_TYPE", "reference write has the wrong element type", instruction.span, frames, program),
        else => trap(reference_lifetime_code, "reference or owner lifetime is invalid", instruction.span, frames, program),
    };
}

// An execution borrows the stores and collections owned by runValues. Individual
// instruction handlers cannot outlive that invocation or retain frame pointers.
const Execution = struct {
    allocator: std.mem.Allocator,
    program: bc.Program,
    options: Options,
    steps: *u64,
    storage: *memory.Store,
    pools: *pool_runtime.Runtime,
    providers: Providers,
    state: State,
};
const Providers = struct {
    host: ?HostExecution = null,
    environment: *environment.Runtime,
    resources: *resource_runtime.Runtime,
    external: *external.Runtime,
};
const State = struct {
    stack: *std.ArrayList(typed.Value),
    locals: *std.ArrayList(?typed.Value),
    owners: *std.AutoHashMapUnmanaged(usize, memory.Allocation),
    references: *std.ArrayList(?Reference),
    active_regions: *std.ArrayList(ActiveRegion),
    frames: *std.ArrayList(Frame),
};
const Step = struct {
    execution: *Execution,
    frame: Frame,
    frame_index: usize,
    instruction: bc.Instruction,
    fn executeTryResult(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const frame_index = self.frame_index;
        const propagate = self.instruction.op.try_result;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        if (value.typeOf() != propagate.input) return error.InternalError;
        const input = typed.resultShape(propagate.input, program.records).?;
        const tag = try value.variantTag();
        const payload = try value.getField(0);
        if (tag == input.ok_tag) {
            try pushOwned(stack, allocator, payload);
        } else {
            defer payload.release(allocator);
            if (tag != input.error_tag) return error.InternalError;
            const output = typed.resultShape(propagate.output, program.records).?;
            const error_result = try typed.Value.createVariant(allocator, propagate.output, output.error_tag, payload);
            releaseValues(stack.items[frame.operand_base..], allocator);
            stack.shrinkRetainingCapacity(frame.operand_base);
            try pushOwned(stack, allocator, error_result);
            frames.items[frame_index].pc = propagate.error_target;
        }
        return null;
    }

    fn executeAcknowledge(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const ty = self.instruction.op.acknowledge;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        if (value.typeOf() != ty) return error.InternalError;
        return null;
    }

    fn executePop(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        (try pop(stack, frame.operand_base)).release(allocator);
        return null;
    }

    fn executeJump(self: *Step) !?ValueResult {
        const frames = self.execution.state.frames;
        const frame_index = self.frame_index;
        const target = self.instruction.op.jump;
        frames.items[frame_index].pc = target;
        return null;
    }

    fn executeJumpIfFalse(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const frame_index = self.frame_index;
        const target = self.instruction.op.jump_if_false;
        if (!(try boolean(try pop(stack, frame.operand_base), allocator))) {
            frames.items[frame_index].pc = target;
        }
        return null;
    }

    fn executeDivI64Checked(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const right = try integer(try pop(stack, frame.operand_base), allocator);
        const left = try integer(try pop(stack, frame.operand_base), allocator);
        if (right == 0) return trap("R_DIVISION_BY_ZERO", "division or remainder by zero", instruction.span, frames.items, program);
        const minimum_case = left == std.math.minInt(i64) and right == -1;
        if (instruction.op == .div_i64_checked and minimum_case) return overflow(instruction, frames.items, program);
        const value = if (instruction.op == .div_i64_checked) @divTrunc(left, right) else if (minimum_case) @as(i64, 0) else @rem(left, right);
        try stack.append(allocator, .{ .i64 = value });
        return null;
    }

    fn executeMakeRecord(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const record = self.instruction.op.make_record;
        if (stack.items.len - frame.operand_base < record.fields) return error.InternalError;
        const start = stack.items.len - record.fields;
        const schema = program.records[record.ty.recordIndex()];
        for (stack.items[start..], 0..) |field, i| {
            const field_index = if (record.order.len == 0) i else record.order[i];
            if (field.typeOf() != schema.elementType(field_index)) return error.InternalError;
        }
        const value = try typed.Value.createOrdered(allocator, record.ty, stack.items[start..], record.order);
        releaseValues(stack.items[start..], allocator);
        stack.shrinkRetainingCapacity(start);
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeUpdateRecord(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const update = self.instruction.op.update_record;
        if (stack.items.len - frame.operand_base <= update.indices.len) return error.InternalError;
        const start = stack.items.len - update.indices.len - 1;
        const base = stack.items[start];
        if (base.typeOf() != update.ty) return error.InternalError;
        const schema = program.records[update.ty.recordIndex()];
        for (stack.items[start + 1 ..], update.indices) |field, index| {
            if (field.typeOf() != schema.fields[index].ty) return error.InternalError;
        }
        const value = try base.updated(allocator, update.indices, stack.items[start + 1 ..]);
        releaseValues(stack.items[start..], allocator);
        stack.shrinkRetainingCapacity(start);
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeGetIndex(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const ty = self.instruction.op.get_index;
        const key = try pop(stack, frame.operand_base);
        defer key.release(allocator);
        const base = try pop(stack, frame.operand_base);
        defer base.release(allocator);
        if (base.typeOf() != ty) return error.InternalError;
        const schema = program.records[ty.recordIndex()].shape.array orelse return error.InternalError;
        const index = try arrayIndex(key, schema);
        if (index < 0 or index >= schema.length) return trap("R_INDEX_BOUNDS", "array index is outside its declared bounds", instruction.span, frames.items, program);
        try pushOwned(stack, allocator, try base.getField(@intCast(index)));
        return null;
    }

    fn executeReplaceIndex(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const ty = self.instruction.op.replace_index;
        if (stack.items.len - frame.operand_base < 3) return error.InternalError;
        const start = stack.items.len - 3;
        const base = stack.items[start];
        const key = stack.items[start + 1];
        const replacement = stack.items[start + 2];
        if (base.typeOf() != ty) return error.InternalError;
        const schema = program.records[ty.recordIndex()].shape.array orelse return error.InternalError;
        if (replacement.typeOf() != schema.element) return error.InternalError;
        const index = try arrayIndex(key, schema);
        if (index < 0 or index >= schema.length) return trap("R_INDEX_BOUNDS", "array replacement index is outside its declared bounds", instruction.span, frames.items, program);
        const result = try base.updated(allocator, &.{@intCast(index)}, &.{replacement});
        releaseValues(stack.items[start..], allocator);
        stack.shrinkRetainingCapacity(start);
        try pushOwned(stack, allocator, result);
        return null;
    }

    fn executeArrayLength(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const ty = self.instruction.op.array_length;
        const base = try pop(stack, frame.operand_base);
        defer base.release(allocator);
        if (base.typeOf() != ty) return error.InternalError;
        const schema = program.records[ty.recordIndex()].shape.array orelse return error.InternalError;
        try stack.append(allocator, typed.Value.number(.u64, schema.length));
        return null;
    }

    fn executeMakeVariant(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const variant = self.instruction.op.make_variant;
        const schema = program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag];
        const payload: ?typed.Value = if (schema.payload != null) try pop(stack, frame.operand_base) else null;
        defer if (payload) |value| value.release(allocator);
        if (payload) |value| if (value.typeOf() != schema.payload.?) return error.InternalError;
        try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, variant.ty, variant.tag, payload));
        return null;
    }

    fn executeSwitchVariant(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const owners = self.execution.state.owners;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const frame_index = self.frame_index;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const dispatch = self.instruction.op.switch_variant;
        const input = try pop(stack, frame.operand_base);
        defer input.release(allocator);
        if (input.typeOf() != dispatch.ty) return error.InternalError;
        const tag = try input.variantTag();
        if (tag >= dispatch.arms.len) return error.InternalError;
        const arm = dispatch.arms[tag];
        if (arm.slot) |slot| {
            const payload = try input.getField(0);
            if (payload.typeOf() != function.scope.locals[@backingInt(slot)].ty) {
                payload.release(allocator);
                return error.InternalError;
            }
            const index = frame.local_base + @backingInt(slot);
            if (owners.get(index)) |owner| {
                defer payload.release(allocator);
                storage.writeOwner(owner, 0, payload) catch |err| return memoryFailure(err, instruction, frames.items, program);
            } else {
                if (locals.items[index]) |old| old.release(allocator);
                locals.items[index] = payload;
            }
        }
        frames.items[frame_index].pc = arm.target;
        return null;
    }

    fn executeResetArena(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const output = self.instruction.op.reset_arena;
        const capability = try pop(stack, frame.operand_base);
        defer capability.release(allocator);
        if (!capability.isCapability(.allocator)) return error.InternalError;
        var status: i64 = 0;
        storage.resetRegion(capability.capability.allocator) catch |err| {
            status = switch (err) {
                error.RegionInUse => 1,
                error.ChildrenActive => 2,
                error.InvalidCapability => 3,
                else => return error.InternalError,
            };
        };
        const shape = typed.resultShape(output, program.records).?;
        try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, output, if (status == 0) shape.ok_tag else shape.error_tag, if (status == 0) .{ .bool = true } else .{ .i64 = status }));
        return null;
    }

    fn executeBeginRegion(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const active_regions = self.execution.state.active_regions;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const slot = self.instruction.op.begin_region;
        const parent = try pop(stack, frame.operand_base);
        defer parent.release(allocator);
        if (!parent.isCapability(.allocator)) return error.InternalError;
        const capability = storage.beginRegion(parent.capability.allocator) catch |err| switch (err) {
            error.CapacityLimit => return trap("R_REGION_LIMIT", "execution region limit exceeded", instruction.span, frames.items, program),
            else => return memoryFailure(err, instruction, frames.items, program),
        };
        active_regions.append(allocator, .{ .capability = capability, .slot = slot }) catch |err| {
            try storage.endRegion(capability);
            return err;
        };
        const index = frame.local_base + @backingInt(slot);
        if (locals.items[index]) |old| old.release(allocator);
        locals.items[index] = .{ .capability = .{ .allocator = capability } };
        return null;
    }

    fn executeEndRegion(self: *Step) !?ValueResult {
        const program = self.execution.program;
        const storage = self.execution.storage;
        const locals = self.execution.state.locals;
        const active_regions = self.execution.state.active_regions;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const slot = self.instruction.op.end_region;
        if (active_regions.items.len <= frame.region_base) return error.InternalError;
        const active_region = active_regions.items[active_regions.items.len - 1];
        if (active_region.slot != slot) return error.InternalError;
        storage.endRegion(active_region.capability) catch |err| return memoryFailure(err, instruction, frames.items, program);
        _ = active_regions.pop();
        locals.items[frame.local_base + @backingInt(slot)] = null;
        return null;
    }

    fn executeCmpHandle(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const comparison = self.instruction.op.cmp_handle;
        const right = try pop(stack, frame.operand_base);
        defer right.release(allocator);
        const left = try pop(stack, frame.operand_base);
        defer left.release(allocator);
        if (left != .handle or right != .handle or left.typeOf() != comparison.ty or right.typeOf() != comparison.ty) return error.InternalError;
        const equal = std.meta.eql(left.handle.id, right.handle.id);
        try stack.append(allocator, .{ .bool = if (comparison.predicate == .eq) equal else !equal });
        return null;
    }

    fn executeCmpEnum(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const comparison = self.instruction.op.cmp_enum;
        const right = try pop(stack, frame.operand_base);
        defer right.release(allocator);
        const left = try pop(stack, frame.operand_base);
        defer left.release(allocator);
        if (left.typeOf() != comparison.ty or right.typeOf() != comparison.ty) return error.InternalError;
        const equal = try left.variantTag() == try right.variantTag();
        try stack.append(allocator, .{ .bool = if (comparison.predicate == .eq) equal else !equal });
        return null;
    }

    fn executeCmpDomain(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const comparison = self.instruction.op.cmp_domain;
        const right = try pop(stack, self.frame.operand_base);
        defer right.release(allocator);
        const left = try pop(stack, self.frame.operand_base);
        defer left.release(allocator);
        if (left != .aggregate or right != .aggregate or left.typeOf() != comparison.ty or right.typeOf() != comparison.ty) return error.InternalError;
        if (left.aggregate.fields.len != 1 or right.aggregate.fields.len != 1) return error.InternalError;
        const backing = self.execution.program.records[comparison.ty.recordIndex()].shape.domain orelse return error.InternalError;
        const a = left.aggregate.fields[0];
        const b = right.aggregate.fields[0];
        if (a.typeOf() != backing or b.typeOf() != backing) return error.InternalError;
        const equal = if (backing == .bool) a.bool == b.bool else try a.asInteger() == try b.asInteger();
        try stack.append(allocator, .{ .bool = if (comparison.predicate == .eq) equal else !equal });
        return null;
    }

    fn executeWrapDomain(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const ty = self.instruction.op.wrap_domain;
        const input = try pop(stack, frame.operand_base);
        defer input.release(allocator);
        const backing = program.records[ty.recordIndex()].shape.domain orelse return error.InternalError;
        if (input.typeOf() != backing) return error.InternalError;
        try pushOwned(stack, allocator, try typed.Value.create(allocator, ty, &.{input}));
        return null;
    }

    fn executeUnwrapDomain(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const ty = self.instruction.op.unwrap_domain;
        const input = try pop(stack, frame.operand_base);
        defer input.release(allocator);
        if (input.typeOf() != ty) return error.InternalError;
        try pushOwned(stack, allocator, try input.getField(0));
        return null;
    }

    fn executeGetField(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const index = self.instruction.op.get_field;
        const record = try pop(stack, frame.operand_base);
        defer record.release(allocator);
        if (record.typeOf().isAggregate() and (program.records[record.typeOf().recordIndex()].shape.domain != null or program.records[record.typeOf().recordIndex()].shape.variants != null)) return error.InternalError;
        try pushOwned(stack, allocator, try record.getField(index));
        return null;
    }

    fn executeUnaryFloat(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const operand = try numeric(stack, self.frame.operand_base, .u64, allocator);
        const value = @import("floats.zig").unary(self.instruction.op.unary_float, @intCast(operand)) catch |err| switch (err) {
            error.FloatConversion => return trap("R_FLOAT_CONVERSION", "floating value is outside the unsigned integer range", self.instruction.span, self.execution.state.frames.items, self.execution.program),
            else => return error.InternalError,
        };
        try stack.append(allocator, Value.number(.u64, value));
        return null;
    }
    fn executePushInteger(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const number = self.instruction.op.push_integer;
        try stack.append(allocator, typed.Value.number(number.ty, number.value));
        return null;
    }

    fn executeCastInteger(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const ty = switch (self.instruction.op) {
            .cast_integer, .neg_integer => |value| value,
            else => unreachable,
        };
        const operand = try numeric(stack, frame.operand_base, if (instruction.op == .neg_integer) ty else null, allocator);
        const value = integers.cast(ty, if (instruction.op == .neg_integer) -operand else operand) catch |err| switch (err) {
            error.Overflow => return trap(overflow_code, "integer conversion or negation exceeds the destination width", instruction.span, frames.items, program),
            else => return error.InternalError,
        };
        try stack.append(allocator, value);
        return null;
    }

    fn executeBinaryInteger(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const binary = self.instruction.op.binary_integer;
        const right = try numeric(stack, frame.operand_base, binary.ty, allocator);
        const left = try numeric(stack, frame.operand_base, binary.ty, allocator);
        const value = integers.binary(binary.ty, binary.op, left, right) catch |err| switch (err) {
            error.Overflow => return trap(overflow_code, "integer arithmetic exceeds its declared width", instruction.span, frames.items, program),
            error.InvalidShift => return trap("R_INVALID_SHIFT", "shift count must be nonnegative and smaller than the integer width", instruction.span, frames.items, program),
            error.DivisionByZero => return trap("R_DIVISION_BY_ZERO", "division or remainder by zero", instruction.span, frames.items, program),
            else => return error.InternalError,
        };
        try stack.append(allocator, value);
        return null;
    }

    fn executePushI64(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const value = self.instruction.op.push_i64;
        try stack.append(allocator, .{ .i64 = value });
        return null;
    }

    fn executePushBool(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const value = self.instruction.op.push_bool;
        try stack.append(allocator, .{ .bool = value });
        return null;
    }

    fn executeBeginBorrow(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const owners = self.execution.state.owners;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const id = switch (self.instruction.op) {
            .begin_borrow, .begin_slice => |value| value,
            else => unreachable,
        };
        const index = frame.reference_base + @backingInt(id);
        if (references.items[index] != null) return trap(reference_lifetime_code, "reference is already active", instruction.span, frames.items, program);
        const metadata = function.scope.references[@backingInt(id)];
        var slice: ?Slice = null;
        var direct = false;
        if (metadata.mode.slice) {
            if (metadata.parent) |parent| {
                const previous = references.items[frame.reference_base + @backingInt(parent)] orelse return trap(reference_lifetime_code, "parent reference is not active", instruction.span, frames.items, program);
                direct = previous.direct;
                if (previous.slice) |view| slice = view else {
                    const array_type = function.scope.references[@backingInt(parent)].ty;
                    slice = .{ .start = 0, .length = program.records[array_type.recordIndex()].shape.array.?.length };
                }
            } else {
                const owner_type = function.scope.locals[@backingInt(metadata.owner)].ty;
                const schema = program.records[owner_type.recordIndex()];
                if (schema.shape.buffer != null) {
                    const local = try self.operationOwner(metadata.owner, null, false);
                    defer local.release(allocator);
                    if (!local.isOwned(.resource)) return error.InternalError;
                    const info = storage.bufferInfo(local.owned.resource.owner) catch |err| return memoryFailure(err, instruction, frames.items, program);
                    slice = .{ .start = 0, .length = info.length };
                    direct = true;
                } else slice = .{ .start = 0, .length = schema.shape.array.?.length };
            }
            if (instruction.op == .begin_slice) {
                const end = try numeric(stack, frame.operand_base, null, allocator);
                const start = try numeric(stack, frame.operand_base, null, allocator);
                if (start < 0 or end < start or end > slice.?.length) return trap(slice_bounds_code, "slice range is outside its source bounds", instruction.span, frames.items, program);
                slice = .{ .start = slice.?.start + @as(usize, @intCast(start)), .length = @intCast(end - start) };
            }
        }
        const kind: memory.Kind = if (metadata.mutable) .exclusive else .shared;
        const reference = if (metadata.parent) |parent| child: {
            const parent_reference = references.items[frame.reference_base + @backingInt(parent)] orelse return trap(reference_lifetime_code, "parent reference is not active", instruction.span, frames.items, program);
            break :child reborrowFull(storage, parent_reference.lease, kind) catch |err| return memoryFailure(err, instruction, frames.items, program);
        } else root: {
            const local_index = frame.local_base + @backingInt(metadata.owner);
            if (direct) {
                const value = try self.operationOwner(metadata.owner, null, false);
                defer value.release(allocator);
                const resource = value.owned.resource;
                const info = storage.bufferInfo(resource.owner) catch |err| return memoryFailure(err, instruction, frames.items, program);
                break :root storage.borrow(resource.owner, 0, info.length, kind) catch |err| return memoryFailure(err, instruction, frames.items, program);
            }
            var allocation = owners.get(local_index);
            if (allocation == null) {
                const old = locals.items[local_index] orelse return error.InternalError;
                const created = try storage.create(function.scope.locals[@backingInt(metadata.owner)].ty, &.{old});
                // The store owns created memory if inserting the owner map fails.
                try owners.put(allocator, local_index, created);
                locals.items[local_index] = null;
                old.release(allocator);
                allocation = created;
            }
            break :root storage.borrow(allocation.?, 0, 1, kind) catch |err| return memoryFailure(err, instruction, frames.items, program);
        };
        references.items[index] = .{ .direct = direct, .lease = reference, .slice = slice };
        return null;
    }

    fn executeSplitBorrow(self: *Step) !?ValueResult {
        const execution = self.execution;
        const frame = self.frame;
        const instruction = self.instruction;
        const pair = instruction.op.split_borrow;
        const references = execution.state.references;
        const function = execution.program.functions[@backingInt(frame.function)];
        const parent_id = function.scope.references[@backingInt(pair.left)].parent.?;
        const parent = references.items[frame.reference_base + @backingInt(parent_id)] orelse return trap(reference_lifetime_code, inactive_slice_message, instruction.span, execution.state.frames.items, execution.program);
        const view = parent.slice orelse return error.InternalError;
        const middle = try numeric(execution.state.stack, frame.operand_base, null, execution.allocator);
        if (middle < 0 or middle > view.length) return trap(slice_bounds_code, "split point is outside its source bounds", instruction.span, execution.state.frames.items, execution.program);
        const left = frame.reference_base + @backingInt(pair.left);
        const right = frame.reference_base + @backingInt(pair.right);
        if (references.items[left] != null or references.items[right] != null) return trap(reference_lifetime_code, "split reference is already active", instruction.span, execution.state.frames.items, execution.program);
        const at: usize = @intCast(middle);
        const divided = (if (parent.direct)
            execution.storage.split(parent.lease, view.start, view.length, at)
        else
            execution.storage.splitFields(parent.lease, view.start, view.length, at)) catch |err| return memoryFailure(err, instruction, execution.state.frames.items, execution.program);
        references.items[left] = .{ .direct = parent.direct, .lease = divided.left, .slice = .{ .start = if (parent.direct) 0 else view.start, .length = at } };
        references.items[right] = .{ .direct = parent.direct, .lease = divided.right, .slice = .{ .start = if (parent.direct) 0 else view.start + at, .length = view.length - at } };
        return null;
    }

    fn executeEndBorrow(self: *Step) !?ValueResult {
        const program = self.execution.program;
        const storage = self.execution.storage;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const id = self.instruction.op.end_borrow;
        const index = frame.reference_base + @backingInt(id);
        const reference = references.items[index] orelse return trap(reference_lifetime_code, inactive_reference_message, instruction.span, frames.items, program);
        storage.end(reference.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
        references.items[index] = null;
        return null;
    }

    fn executeLenSlice(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const id = self.instruction.op.len_slice;
        const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, inactive_slice_message, instruction.span, frames.items, program);
        _ = storage.describe(reference.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
        const view = reference.slice orelse return error.InternalError;
        try stack.append(allocator, typed.Value.number(.u64, view.length));
        return null;
    }

    fn executeReadSlice(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const id = self.instruction.op.read_slice;
        const index = try numeric(stack, frame.operand_base, null, allocator);
        const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, inactive_slice_message, instruction.span, frames.items, program);
        const view = reference.slice orelse return error.InternalError;
        if (index < 0 or index >= view.length) return trap(slice_bounds_code, "slice index is outside its bounds", instruction.span, frames.items, program);
        if (reference.direct) {
            const value = storage.read(reference.lease, view.start + @as(usize, @intCast(index))) catch |err| return memoryFailure(err, instruction, frames.items, program);
            try pushOwned(stack, allocator, value);
            return null;
        }
        const value = storage.readField(reference.lease, view.start + @as(usize, @intCast(index))) catch |err| return memoryFailure(err, instruction, frames.items, program);
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeWriteSlice(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const id = self.instruction.op.write_slice;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        const index = try numeric(stack, frame.operand_base, null, allocator);
        const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, inactive_slice_message, instruction.span, frames.items, program);
        const view = reference.slice orelse return error.InternalError;
        if (index < 0 or index >= view.length) return trap(slice_bounds_code, "slice index is outside its bounds", instruction.span, frames.items, program);
        if (value.typeOf() != function.scope.references[@backingInt(id)].ty) return trap("R_REFERENCE_TYPE", "slice write has the wrong element type", instruction.span, frames.items, program);
        if (reference.direct) {
            storage.write(reference.lease, view.start + @as(usize, @intCast(index)), value) catch |err| return memoryFailure(err, instruction, frames.items, program);
            return null;
        }
        storage.writeField(reference.lease, view.start + @as(usize, @intCast(index)), value) catch |err| return memoryFailure(err, instruction, frames.items, program);
        return null;
    }

    fn executeReadRef(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const id = self.instruction.op.read_ref;
        const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, inactive_reference_message, instruction.span, frames.items, program);
        const value = storage.read(reference.lease, 0) catch |err| return memoryFailure(err, instruction, frames.items, program);
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeWriteRef(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const id = self.instruction.op.write_ref;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, inactive_reference_message, instruction.span, frames.items, program);
        storage.write(reference.lease, 0, value) catch |err| return memoryFailure(err, instruction, frames.items, program);
        return null;
    }

    fn operationOwner(self: *Step, owner: typed.LocalId, reference_id: ?typed.ReferenceId, mutable: bool) !typed.Value {
        const storage = self.execution.storage;
        const state = self.execution.state;
        if (reference_id) |id| {
            const reference = state.references.items[self.frame.reference_base + @backingInt(id)] orelse return error.InternalError;
            const view = try storage.describe(reference.lease);
            if (mutable and view.kind != .exclusive) return error.InternalError;
            return storage.read(reference.lease, 0);
        }
        const index = self.frame.local_base + @backingInt(owner);
        if (state.owners.get(index)) |allocation| {
            try storage.checkOwnerAccess(allocation, mutable);
            return storage.readOwner(allocation, 0);
        }
        return (state.locals.items[index] orelse return error.InternalError).retain();
    }

    fn executePoolOperation(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const pools = self.execution.pools;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const operation = self.instruction.op.pool_operation;
        const count = operation.kind.arity();
        if (stack.items.len - frame.operand_base < count) return error.InternalError;
        const start = stack.items.len - count;
        const local = try self.operationOwner(operation.owner, operation.reference, operation.kind.mutates());
        defer local.release(allocator);
        if (!local.isOwned(.pool) or local.owned.pool.runtime != pools) return error.InternalError;
        const schema = program.records[local.owned.pool.ty.recordIndex()].shape.pool orelse return error.InternalError;
        var status: i64 = 0;
        const output = local.owned.pool.perform(operation.kind, schema, stack.items[start..]) catch |err| failed: {
            status = switch (err) {
                error.InvalidHandle => 1,
                error.ForeignPool => 2,
                error.CapacityLimit => 3,
                error.OutOfMemory => return error.OutOfMemory,
                else => return error.InternalError,
            };
            if (!operation.kind.fallible()) return error.InternalError;
            break :failed typed.Value{ .i64 = status };
        };
        defer output.release(allocator);
        for (stack.items[start..]) |argument| argument.release(allocator);
        stack.shrinkRetainingCapacity(start);
        if (operation.kind.fallible()) {
            const shape = typed.resultShape(operation.output, program.records).?;
            try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, operation.output, if (status == 0) shape.ok_tag else shape.error_tag, output));
        } else try pushOwned(stack, allocator, output.retain());
        return null;
    }

    fn executeBufferOperation(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const operation = self.instruction.op.buffer_operation;
        const count = operation.kind.arity();
        if (stack.items.len - frame.operand_base < count) return error.InternalError;
        const start = stack.items.len - count;
        const arguments = stack.items[start..];
        const local = try self.operationOwner(operation.owner, operation.reference, operation.kind.mutates());
        defer local.release(allocator);
        if (!local.isOwned(.resource) or local.owned.resource.store != storage) return error.InternalError;
        const owner = local.owned.resource.owner;
        const info = storage.bufferInfo(owner) catch |err| return memoryFailure(err, instruction, frames.items, program);
        const number: i128 = if (count != 0 and operation.kind != .append) try arguments[if (operation.kind == .reserve) 1 else 0].asInteger() else 0;
        if (operation.kind == .reserve) {
            if (!arguments[0].isCapability(.allocator)) return error.InternalError;
            storage.checkAllocationAllocator(owner, arguments[0].capability.allocator) catch |err| return memoryFailure(err, instruction, frames.items, program);
        }
        var status: i64 = 0;
        const output: typed.Value = switch (operation.kind) {
            .length => typed.Value.number(.u64, info.length),
            .capacity => typed.Value.number(.u64, info.capacity),
            .read => read: {
                if (number < 0 or number >= info.length) return trap("R_BUFFER_BOUNDS", "buffer index is outside initialized bounds", instruction.span, frames.items, program);
                break :read storage.readOwner(owner, @intCast(number)) catch |err| return memoryFailure(err, instruction, frames.items, program);
            },
            .take => taking: {
                const shape = typed.resultShape(operation.output, program.records).?;
                if (number < 0 or number >= info.length) break :taking try typed.Value.createVariant(allocator, operation.output, shape.error_tag, .{ .i64 = 3 });
                const value = storage.takeOwner(owner, @intCast(number)) catch |err| return memoryFailure(err, instruction, frames.items, program);
                defer value.release(allocator);
                break :taking try typed.Value.createVariant(allocator, operation.output, shape.ok_tag, value);
            },
            else => mutation: {
                if (operation.kind != .append and (number < 0 or number > std.math.maxInt(usize))) {
                    status = if (operation.kind == .reserve) 1 else 3;
                } else {
                    const index: usize = @intCast(number);
                    const result: memory.Error!void = switch (operation.kind) {
                        .write => storage.writeOwner(owner, index, arguments[1]),
                        .append => storage.appendWithinCapacity(owner, arguments[0]),
                        .resize => storage.resizeWithinCapacity(owner, index, arguments[1]),
                        .reserve => reserveBuffer(storage, owner, index),
                        .truncate => storage.truncateOwner(owner, index),
                        else => unreachable,
                    };
                    result catch |err| switch (err) {
                        error.CapacityLimit => status = 1,
                        error.NoCapacity => status = 2,
                        error.Bounds => status = 3,
                        else => return memoryFailure(err, instruction, frames.items, program),
                    };
                }
                const shape = typed.resultShape(operation.output, program.records).?;
                break :mutation try typed.Value.createVariant(allocator, operation.output, if (status == 0) shape.ok_tag else shape.error_tag, if (status == 0) .{ .bool = true } else .{ .i64 = status });
            },
        };
        releaseValues(arguments, allocator);
        stack.shrinkRetainingCapacity(start);
        try pushOwned(stack, allocator, output);
        return null;
    }

    fn executeAcquireResource(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const acquire = self.instruction.op.acquire_resource;
        const request = try pop(stack, frame.operand_base);
        defer request.release(allocator);
        const capability = try pop(stack, frame.operand_base);
        defer capability.release(allocator);
        const output = resource_execution.acquire(acquire.output, program.records, capability, request, acquire.request) catch |err| switch (err) {
            error.InvalidCapability, error.InvalidOwner, error.Closed => return trap(capability_code, "external resource authority is stale or invalid", instruction.span, frames.items, program),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return null;
    }

    fn executeResourceIo(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const io = self.instruction.op.resource_io;
        if (io.reference) |id| {
            const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, "resource I/O slice is not active", instruction.span, frames.items, program);
            const slice = reference.slice orelse return error.InternalError;
            const owner = locals.items[frame.local_base + @backingInt(io.owner)] orelse return error.InternalError;
            const output = resource_execution.ioSlice(program.records, storage, .{ .kind = io.kind, .output = io.output, .value = owner, .view = .{
                .lease = reference.lease,
                .direct = reference.direct,
                .start = slice.start,
                .length = slice.length,
            } }) catch |err| switch (err) {
                error.InvalidCapability, error.InvalidOwner, error.Closed => return trap(capability_code, "resource I/O owner is stale or invalid", instruction.span, frames.items, program),
                error.IdentityExhausted,
                error.MemoryClosed,
                error.ForeignMemory,
                error.InvalidAllocation,
                error.ExpiredBorrow,
                error.BorrowConflict,
                error.BorrowSuspended,
                error.ChildrenActive,
                error.ReadOnly,
                error.Bounds,
                error.TypeMismatch,
                error.CapacityLimit,
                error.NoCapacity,
                => return memoryFailure(@errorCast(err), instruction, frames.items, program),
                else => return err,
            };
            try pushOwned(stack, allocator, output);
            return null;
        }
        const input = if (io.kind == .write) try pop(stack, frame.operand_base) else null;
        defer if (input) |value| value.release(allocator);
        const owner = locals.items[frame.local_base + @backingInt(io.owner)] orelse return error.InternalError;
        const output = resource_execution.io(program.records, .{ .kind = io.kind, .output = io.output, .value = owner, .input = input, .input_type = io.input }) catch |err| switch (err) {
            error.InvalidCapability, error.InvalidOwner, error.Closed => return trap(capability_code, "resource I/O owner is stale or invalid", instruction.span, frames.items, program),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return null;
    }

    fn executeRestrictResource(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const restrict = self.instruction.op.restrict_resource;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        if (value.typeOf() != restrict.ty) return error.InternalError;
        const restricted = resource_execution.restrict(value, restrict.permissions) catch |err| switch (err) {
            error.InvalidCapability, error.Closed => return trap(capability_code, "resource capability is stale or invalid", instruction.span, frames.items, program),
            else => return err,
        };
        try pushOwned(stack, allocator, restricted);
        return null;
    }

    fn executeEnvironmentGet(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const environment_execution = self.execution.providers.environment;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const get = self.instruction.op.environment_get;
        const name = try pop(stack, frame.operand_base);
        defer name.release(allocator);
        const capability = try pop(stack, frame.operand_base);
        defer capability.release(allocator);
        const output = environment.readValue(allocator, environment_execution, .{ .output = get.output, .capability = capability, .name = name, .name_type = get.name }, program.records) catch |err| switch (err) {
            error.InvalidCapability => return trap(capability_code, "environment capability is stale or invalid", instruction.span, frames.items, program),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return null;
    }

    fn executeCompleteResource(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const output_type = self.instruction.op.complete_resource;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        const output = resource_execution.complete(output_type, program.records, value) catch |err| switch (err) {
            error.InvalidCapability, error.InvalidOwner, error.Closed => return trap(capability_code, "external resource owner is stale or invalid", instruction.span, frames.items, program),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return null;
    }

    fn executeExternalRead(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const external_runtime = self.execution.providers.external;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const read = self.instruction.op.external_read;
        const capability = try pop(stack, frame.operand_base);
        defer capability.release(allocator);
        if (!capability.isCapability(.external)) return error.InternalError;
        var status: i64 = 0;
        const sample = external_runtime.read(read.kind, capability.capability.external) catch |err| sample: {
            status = switch (err) {
                error.Unavailable => 1,
                error.Denied => 2,
                error.Failed => 3,
                error.OutOfMemory => return error.OutOfMemory,
                error.InvalidCapability => return trap(capability_code, "external capability has the wrong kind or execution identity", instruction.span, frames.items, program),
            };
            break :sample 0;
        };
        const shape = typed.resultShape(read.output, program.records).?;
        try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, read.output, if (status == 0) shape.ok_tag else shape.error_tag, if (status == 0) typed.Value.number(shape.ok_type, sample) else .{ .i64 = status }));
        return null;
    }

    fn executeAcquirePool(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const pools = self.execution.pools;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const ty = self.instruction.op.acquire_pool;
        const capacity = try numeric(stack, frame.operand_base, null, allocator);
        const authority = try pop(stack, frame.operand_base);
        defer authority.release(allocator);
        if (!authority.isCapability(.allocator)) return error.InternalError;
        storage.checkAllocator(authority.capability.allocator) catch |err| return memoryFailure(err, instruction, frames.items, program);
        const shape = typed.resultShape(ty, program.records).?;
        var status: i64 = 1;
        const owner: ?typed.Value = if (capacity < 0 or capacity > std.math.maxInt(usize)) null else pools.acquireAuthorized(shape.ok_type, @intCast(capacity), storage, authority.capability.allocator) catch |err| switch (err) {
            error.CapacityLimit => null,
            error.IdentityExhausted => exhausted: {
                status = 2;
                break :exhausted null;
            },
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InternalError,
        };
        if (owner) |value| {
            defer value.release(allocator);
            try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, ty, shape.ok_tag, value));
        } else {
            try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, ty, shape.error_tag, .{ .i64 = status }));
        }
        return null;
    }

    fn executeJson(self: *Step) !?ValueResult {
        const execution = self.execution;
        const allocator = execution.allocator;
        const stack = execution.state.stack;
        const limit = try numeric(stack, self.frame.operand_base, null, allocator);
        const input = try pop(stack, self.frame.operand_base);
        defer input.release(allocator);
        const authority = try pop(stack, self.frame.operand_base);
        defer authority.release(allocator);
        const outcome = @import("runtime_json.zig").run(allocator, .{
            .program = execution.program,
            .storage = execution.storage,
            .steps = execution.options.max_steps - execution.steps.*,
            .frames = execution.options.max_frames - execution.state.frames.items.len,
            .dispatch = invoke,
        }, .{ .op = self.instruction.op.json_codec, .authority = authority, .input = input, .limit = limit }) catch |err| switch (err) {
            error.CodecFrameLimit => return trap("R_FRAME_LIMIT", "JSON codec active frame budget exhausted", self.instruction.span, execution.state.frames.items, execution.program),
            error.CodecStepLimit => return trap("R_STEP_LIMIT", "JSON codec instruction budget exhausted", self.instruction.span, execution.state.frames.items, execution.program),
            else => |failure| return failure,
        };
        execution.steps.* += outcome.steps;
        try pushOwned(stack, allocator, outcome.value);
        return null;
    }
    fn executeAcquireBuffer(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const ty = self.instruction.op.acquire_buffer;
        const capacity = try numeric(stack, frame.operand_base, null, allocator);
        const authority = try pop(stack, frame.operand_base);
        defer authority.release(allocator);
        if (!authority.isCapability(.allocator)) return error.InternalError;
        storage.checkAllocator(authority.capability.allocator) catch |err| return memoryFailure(err, instruction, frames.items, program);
        const shape = typed.resultShape(ty, program.records).?;
        const element = program.records[shape.ok_type.recordIndex()].shape.buffer.?;
        const owner: ?memory.Allocation = if (capacity < 0 or capacity > std.math.maxInt(usize)) null else storage.createAuthorized(authority.capability.allocator, element, &.{}, @intCast(capacity)) catch |err| switch (err) {
            error.CapacityLimit => null,
            else => return memoryFailure(err, instruction, frames.items, program),
        };
        if (owner) |allocation| {
            const resource = typed.Value.ownBuffer(allocator, shape.ok_type, storage, allocation) catch |err| {
                try storage.destroy(allocation);
                return err;
            };
            defer resource.release(allocator);
            try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, ty, shape.ok_tag, resource));
        } else {
            try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, ty, shape.error_tag, .{ .i64 = 1 }));
        }
        return null;
    }

    fn restoreLocalOwner(self: *Step, index: usize) !void {
        const state = self.execution.state;
        if (state.owners.get(index)) |allocation| {
            const value = try self.execution.storage.readOwner(allocation, 0);
            errdefer value.release(self.execution.allocator);
            try self.execution.storage.destroy(allocation);
            _ = state.owners.remove(index);
            state.locals.items[index] = value;
        }
    }

    fn executeMoveLocal(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frame = self.frame;
        const slot = self.instruction.op.move_local;
        const index = frame.local_base + @backingInt(slot);
        try self.restoreLocalOwner(index);
        const value = locals.items[index] orelse return error.InternalError;
        locals.items[index] = null;
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeDropLocal(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const locals = self.execution.state.locals;
        const owners = self.execution.state.owners;
        const frame = self.frame;
        const slot = self.instruction.op.drop_local;
        const index = frame.local_base + @backingInt(slot);
        if (owners.get(index)) |owner| {
            self.execution.storage.destroy(owner) catch |err| return memoryFailure(err, self.instruction, self.execution.state.frames.items, self.execution.program);
            _ = owners.remove(index);
        }
        if (locals.items[index]) |value| value.release(allocator);
        locals.items[index] = null;
        return null;
    }

    fn executeTakeField(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frame = self.frame;
        const take = self.instruction.op.take_field;
        const index = frame.local_base + @backingInt(take.owner);
        try self.restoreLocalOwner(index);
        const owner = locals.items[index] orelse return error.InternalError;
        const value = try owner.takeField(allocator, take.field);
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeReadField(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const read = self.instruction.op.read_field;
        const owner = try self.operationOwner(read.owner, read.reference, false);
        defer owner.release(allocator);
        if (owner.typeOf() != function.scope.locals[@backingInt(read.owner)].ty) return error.InternalError;
        const value = try owner.getField(read.field);
        if (value.typeOf() != read.output) {
            value.release(allocator);
            return error.InternalError;
        }
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeLoadLocal(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const owners = self.execution.state.owners;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const slot = self.instruction.op.load_local;
        if (typed.moveOnly(function.scope.locals[@backingInt(slot)].ty, program.records)) return error.InternalError;
        const index = frame.local_base + @backingInt(slot);
        const value = if (owners.get(index)) |owner| storage.readOwner(owner, 0) catch |err| return memoryFailure(err, instruction, frames.items, program) else (locals.items[index] orelse return error.InternalError).retain();
        try pushOwned(stack, allocator, value);
        return null;
    }

    fn executeStoreLocal(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const owners = self.execution.state.owners;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const slot = self.instruction.op.store_local;
        const value = try pop(stack, frame.operand_base);
        var transferred = false;
        defer if (!transferred) value.release(allocator);
        if (value.typeOf() != function.scope.locals[@backingInt(slot)].ty) return error.InternalError;
        const index = frame.local_base + @backingInt(slot);
        if (owners.get(index)) |owner| {
            storage.writeOwner(owner, 0, value) catch |err| return memoryFailure(err, instruction, frames.items, program);
        } else {
            if (locals.items[index]) |old| old.release(allocator);
            locals.items[index] = value;
            transferred = true;
        }
        return null;
    }

    fn executeCaptureRef(self: *Step) !?ValueResult {
        const program = self.execution.program;
        const storage = self.execution.storage;
        const references = self.execution.state.references;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const frame_index = self.frame_index;
        const instruction = self.instruction;
        const id = self.instruction.op.capture_ref;
        const reference = references.items[frame.reference_base + @backingInt(id)] orelse return trap(reference_lifetime_code, "returned reference is not active", instruction.span, frames.items, program);
        const target = frame.return_target orelse return error.InternalError;
        const view = storage.describe(reference.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
        if (!std.meta.eql(view.allocation, target.allocation) or frame.captured != null) return trap(reference_lifetime_code, "returned reference does not belong to the declared input", instruction.span, frames.items, program);
        frames.items[frame_index].captured = .{ .direct = reference.direct, .slice = reference.slice };
        return null;
    }

    fn hostFailure(self: *Step, err: host.Error) RunError!?ValueResult {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const code: []const u8 = switch (err) {
            error.HostCallLimit, error.HostWorkLimit, error.ValueCountLimit, error.ValueDepthLimit => "R_HOST_LIMIT",
            error.HostFailure => "R_HOST_FAILURE",
            else => "R_HOST_CONTRACT",
        };
        return trap(code, @errorName(err), self.instruction.span, self.execution.state.frames.items, self.execution.program);
    }
    fn executeFunctionValue(self: *Step) !?ValueResult {
        const value = self.instruction.op.function_value;
        try self.execution.state.stack.append(self.execution.allocator, .{ .integer = .{ .ty = value.ty, .value = @backingInt(value.function) } });
        return null;
    }
    fn indirectTarget(self: *Step, ty: typed.Type) !typed.FunctionId {
        const contract = callables.signature(ty, self.execution.program.records) orelse return error.InternalError;
        const stack = self.execution.state.stack;
        if (stack.items.len <= contract.parameters.len + self.frame.operand_base) return error.InternalError;
        const value = stack.orderedRemove(stack.items.len - contract.parameters.len - 1);
        defer value.release(self.execution.allocator);
        if (value.typeOf() != ty) return error.InternalError;
        const target = try value.asInteger();
        if (target < 0 or target >= self.execution.program.functions.len) return error.InternalError;
        const id: typed.FunctionId = @fromBackingInt(@as(usize, @intCast(target)));
        if (!callables.accepts(contract, self.execution.program.functions[@backingInt(id)])) return error.InternalError;
        return id;
    }
    fn executeCall(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const options = self.execution.options;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const references = self.execution.state.references;
        const active_regions = self.execution.state.active_regions;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const id = switch (instruction.op) {
            .invoke => |ty| try self.indirectTarget(ty),
            .call => |id| id,
            .call_refs => |call| call.function,
            .call_borrow => |call| call.function,
            else => unreachable,
        };
        const loan_arguments: []const typed.ReferenceId = switch (instruction.op) {
            .invoke => &.{},
            .call => &.{},
            .call_refs => |call| call.references,
            .call_borrow => |call| call.references,
            else => unreachable,
        };
        const callee = program.functions[@backingInt(id)];
        const value_count = bc.valueParameterCount(callee);
        if (stack.items.len < frame.operand_base or stack.items.len - frame.operand_base < value_count) return error.InternalError;
        if (frames.items.len >= options.max_frames) return trap("R_FRAME_LIMIT", "active frame budget exhausted", instruction.span, frames.items, program);
        const argument_base = stack.items.len - value_count;
        var argument_index = argument_base;
        for (callee.scope.locals[0..callee.signature.parameter_count]) |parameter| {
            if (parameter.parameter.reference_parameter != null) continue;
            if (stack.items[argument_index].typeOf() != parameter.ty) return error.InternalError;
            argument_index += 1;
        }
        if (callee.policy.host != null) {
            const bound = self.execution.providers.host orelse return error.InternalError;
            const registration = bound.registry.resolve(id) catch return error.InternalError;
            const result = bound.session.call(registration, stack.items[argument_base..]) catch |err| return self.hostFailure(err);
            releaseValues(stack.items[argument_base..], allocator);
            stack.shrinkRetainingCapacity(argument_base);
            try pushOwned(stack, allocator, result);
            return null;
        }
        var return_target: ?ReturnTarget = null;
        if (instruction.op == .call_borrow) {
            const destination = instruction.op.call_borrow.destination;
            const target_index = frame.reference_base + @backingInt(destination);
            if (references.items[target_index] != null) return trap(reference_lifetime_code, "result reference is already active", instruction.span, frames.items, program);
            const metadata = function.scope.references[@backingInt(destination)];
            const parent = references.items[frame.reference_base + @backingInt(metadata.parent.?)] orelse return trap(reference_lifetime_code, "result input reference is not active", instruction.span, frames.items, program);
            const view = storage.describe(parent.lease) catch |err| return memoryFailure(err, instruction, frames.items, program);
            return_target = .{ .destination = target_index, .parent = parent.lease, .allocation = view.allocation, .mutable = metadata.mutable };
        }
        const reference_base = references.items.len;
        const reference_end = std.math.add(usize, reference_base, callee.scope.references.len) catch return error.OutOfMemory;
        try references.resize(allocator, reference_end);
        @memset(references.items[reference_base..], null);
        var loan_index: usize = 0;
        for (callee.scope.references, 0..) |parameter, index| {
            if (!parameter.mode.parameter) continue;
            const parent = references.items[frame.reference_base + @backingInt(loan_arguments[loan_index])] orelse return trap(reference_lifetime_code, "reference argument is not active", instruction.span, frames.items, program);
            loan_index += 1;
            const child = reborrowFull(storage, parent.lease, if (parameter.mutable) .exclusive else .shared) catch |err| return memoryFailure(err, instruction, frames.items, program);
            references.items[reference_base + index] = .{ .direct = parent.direct, .lease = child, .slice = parent.slice };
        }
        const local_base = locals.items.len;
        const local_end = std.math.add(usize, local_base, callee.scope.locals.len) catch return error.OutOfMemory;
        try locals.resize(allocator, local_end);
        @memset(locals.items[local_base..], null);
        argument_index = argument_base;
        for (callee.scope.locals[0..callee.signature.parameter_count], 0..) |parameter, index| {
            if (parameter.parameter.reference_parameter != null) continue;
            locals.items[local_base + index] = stack.items[argument_index];
            argument_index += 1;
        }
        stack.shrinkRetainingCapacity(argument_base);
        try frames.append(allocator, .{
            .region_base = active_regions.items.len,
            .return_target = return_target,
            .reference_base = reference_base,
            .function = id,
            .local_base = local_base,
            .operand_base = argument_base,
            .call_span = instruction.span,
        });
        return null;
    }

    fn executeRet(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const storage = self.execution.storage;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const owners = self.execution.state.owners;
        const references = self.execution.state.references;
        const active_regions = self.execution.state.active_regions;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const value: ?typed.Value = if (instruction.op == .ret) try pop(stack, frame.operand_base) else null;
        var transferred = false;
        defer if (!transferred) {
            if (value) |owned| owned.release(allocator);
        };
        if (stack.items.len != frame.operand_base) return error.InternalError;
        if (value) |owned| {
            if (owned.typeOf() != function.signature.return_type) return error.InternalError;
        } else if (frame.captured == null or frame.return_target == null) return trap(reference_lifetime_code, "reference return has no captured result", instruction.span, frames.items, program);
        for (references.items[frame.reference_base..]) |reference| if (reference != null) return trap(reference_lifetime_code, "function returned with an active reference", instruction.span, frames.items, program);
        references.shrinkRetainingCapacity(frame.reference_base);
        var cleanup_index = locals.items.len;
        while (cleanup_index > frame.local_base) {
            cleanup_index -= 1;
            const index = cleanup_index;
            const local = &locals.items[index];
            if (owners.get(index)) |owner| {
                storage.destroy(owner) catch |err| return memoryFailure(err, instruction, frames.items, program);
                _ = owners.remove(index);
            }
            if (local.*) |owned| owned.release(allocator);
            local.* = null;
        }
        locals.shrinkRetainingCapacity(frame.local_base);
        while (active_regions.items.len > frame.region_base) {
            const active_region = active_regions.items[active_regions.items.len - 1];
            storage.endRegion(active_region.capability) catch |err| return memoryFailure(err, instruction, frames.items, program);
            _ = active_regions.pop();
        }
        _ = frames.pop();
        if (value) |owned| {
            transferred = true;
            if (frames.items.len == 0) return .{ .value = owned };
            try pushOwned(stack, allocator, owned);
        } else {
            const target = frame.return_target.?;
            const lease = reborrowFull(storage, target.parent, if (target.mutable) .exclusive else .shared) catch |err| return memoryFailure(err, instruction, frames.items, program);
            references.items[target.destination] = .{ .direct = frame.captured.?.direct, .lease = lease, .slice = frame.captured.?.slice };
        }
        return null;
    }

    fn executeNotBool(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        try stack.append(allocator, .{ .bool = !(try boolean(try pop(stack, frame.operand_base), allocator)) });
        return null;
    }

    fn executeNegI64Checked(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const value = try integer(try pop(stack, frame.operand_base), allocator);
        const result = @subWithOverflow(@as(i64, 0), value);
        if (result[1] != 0) return overflow(instruction, frames.items, program);
        try stack.append(allocator, .{ .i64 = result[0] });
        return null;
    }

    fn executeAddI64Checked(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame;
        const instruction = self.instruction;
        const right = try integer(try pop(stack, frame.operand_base), allocator);
        const left = try integer(try pop(stack, frame.operand_base), allocator);
        const result = switch (instruction.op) {
            .add_i64_checked => @addWithOverflow(left, right),
            .sub_i64_checked => @subWithOverflow(left, right),
            .mul_i64_checked => @mulWithOverflow(left, right),
            else => return error.InternalError,
        };
        if (result[1] != 0) return overflow(instruction, frames.items, program);
        try stack.append(allocator, .{ .i64 = result[0] });
        return null;
    }

    fn executeCmpI64(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const predicate = self.instruction.op.cmp_i64;
        const right = try integer(try pop(stack, frame.operand_base), allocator);
        const left = try integer(try pop(stack, frame.operand_base), allocator);
        const value = switch (predicate) {
            .eq => left == right,
            .ne => left != right,
            .lt => left < right,
            .le => left <= right,
            .gt => left > right,
            .ge => left >= right,
        };
        try stack.append(allocator, .{ .bool = value });
        return null;
    }

    fn executeCmpBool(self: *Step) !?ValueResult {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame;
        const predicate = self.instruction.op.cmp_bool;
        const right = try boolean(try pop(stack, frame.operand_base), allocator);
        const left = try boolean(try pop(stack, frame.operand_base), allocator);
        try stack.append(allocator, .{ .bool = if (predicate == .eq) left == right else left != right });
        return null;
    }
};

fn reserveBuffer(storage: *memory.Store, owner: memory.Allocation, count: usize) memory.Error!void {
    _ = try storage.reserve(owner, count);
}
