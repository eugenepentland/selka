//! Typed local/operand storage and explicitly checked guest arithmetic in every host mode.
const frame_limit_code = "R_FRAME_LIMIT";
const index_bounds_code = "R_INDEX_BOUNDS";
const arena_escape_code = "R_ARENA_ESCAPE";
const list_bounds_code = "R_LIST_BOUNDS";
const list_bounds_message = "list index is outside initialized bounds";
const iteration_mutation_code = "R_LIST_ITERATION_MUTATION";
const invalid_utf8_message = "invalid UTF-8 in byte string";
const invalid_hex_message = "hexadecimal text requires an even number of hex digits";

fn byteCount(result: managed_bytes.Error!usize) managed_bytes.Error!Value {
    return Value{ .i64 = @intCast(try result) };
}
fn byteTruth(result: managed_bytes.Error!bool) managed_bytes.Error!Value {
    return Value{ .bool = try result };
}
const division_zero_message = "division or remainder by zero";
const division_zero_code = "R_DIVISION_BY_ZERO";
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
const managed_equal = @import("managed_equal.zig");
const managed_text = @import("managed_text.zig");
const managed_bytes = @import("managed_bytes.zig");
const managed_dict = @import("managed_dict.zig");
const invocation_contract = @import("invocation_contract.zig");
const bc = @import("bytecode.zig");
const fusion = @import("vm_fusion.zig");
const integers = @import("integers.zig");
const typed = @import("typed.zig");
const gc_heap = @import("gc_heap.zig");
const gc_regions = @import("gc_regions.zig");
const external = @import("external_capabilities.zig");
const Diagnostic = @import("diagnostic.zig").Diagnostic;
const environment = @import("environment.zig");
const resource_runtime = @import("resource_runtime.zig");
/// Host failures and invalid checked execution state returned by the VM.
pub const RunError = invocation_contract.RunError;
/// Invocation additionally checks exported function identity and argument contracts.
pub const InvokeError = invocation_contract.InvokeError;
/// Execution quotas, optional statistics, and explicitly supplied host authority.
pub const Options = struct {
    memory: MemoryOptions = .{},
    environment: ?environment.Provider = null,
    resources: resource_runtime.Options = .{},
    external: external.Providers = .{},
    max_steps: u64 = 10_000_000,
    max_frames: u64 = 1024,
};
/// Collection stress mode and observations for each fresh managed execution heap.
pub const GcStatistics = gc_heap.Statistics;
/// Optional collection stress and counters, independent of explicit allocator authority.
pub const GcOptions = struct {
    stress: bool = false,
    statistics: ?*gc_heap.Statistics = null,
};
/// Collection stress options and optional execution-memory observations.
pub const MemoryOptions = struct {
    gc: GcOptions = .{},
    /// Select original dispatch for differential execution and memory measurements.
    optimize_dispatch: bool = true,
    trace: ?*@import("vm_trace.zig").Trace = null,
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
inline fn pushOwned(stack: *std.ArrayList(typed.Value), allocator: std.mem.Allocator, value: typed.Value) !void {
    errdefer value.release(allocator);
    try appendValue(stack, allocator, value);
}
inline fn appendValue(stack: *std.ArrayList(typed.Value), allocator: std.mem.Allocator, value: typed.Value) !void {
    if (stack.items.len == stack.capacity) try growOperandStack(stack, allocator);
    stack.appendAssumeCapacity(value);
}
noinline fn growOperandStack(stack: *std.ArrayList(typed.Value), allocator: std.mem.Allocator) !void {
    try stack.ensureUnusedCapacity(allocator, 1);
}
const Span = @import("source.zig").Span;
const ActiveArena = struct { watermark: usize, frame: usize };
const Frame = struct {
    arena_base: usize = 0,
    function: typed.FunctionId,
    pc: usize = 0,
    local_base: usize,
    operand_base: usize,
    call_span: Span,
};
inline fn appendFrame(frames: *std.ArrayList(Frame), allocator: std.mem.Allocator, frame: Frame) !void {
    if (frames.items.len == frames.capacity) try growFrames(frames, allocator);
    frames.appendAssumeCapacity(frame);
}
noinline fn growFrames(frames: *std.ArrayList(Frame), allocator: std.mem.Allocator) !void {
    try frames.ensureUnusedCapacity(allocator, 1);
}
noinline fn growLocals(locals: *std.ArrayList(?Value), allocator: std.mem.Allocator, capacity: usize) !void {
    try locals.ensureTotalCapacity(allocator, capacity);
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
inline fn pop(stack: *std.ArrayList(typed.Value), base: usize) error{InternalError}!typed.Value {
    if (stack.items.len <= base) return error.InternalError;
    const value = stack.items[stack.items.len - 1];
    stack.items.len -= 1;
    return value;
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
    if (arguments.len != function.signature.parameter_count) return error.InvocationArity;
    try @import("data_type.zig").check(allocator, program.records, function.signature.return_type, true);
    for (function.scope.locals[0..function.signature.parameter_count]) |parameter| {
        try @import("data_type.zig").check(allocator, program.records, parameter.ty, true);
    }
    return .{ .id = function_id, .arguments = arguments, .limits = options.arguments, .steps_executed = options.steps_executed };
}
fn runInvocation(allocator: std.mem.Allocator, program: bc.Program, options: InvokeOptions, entry: Entry) RunError!ValueResult {
    return runValues(allocator, program, .{ .max_steps = options.max_steps, .max_frames = options.max_frames }, entry);
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
    var quickened: fusion.Plan = .{ .enabled = options.memory.optimize_dispatch and options.memory.trace == null };
    var managed_heap = gc_heap.Heap.init(allocator);
    managed_heap.stress = options.memory.gc.stress;
    defer {
        managed_heap.deinit();
        if (options.memory.gc.statistics) |statistics| statistics.* = managed_heap.statistics;
    }
    const execution_identity = try @import("wiring/identity.zig").acquire();
    var environment_execution = environment.Runtime.init(execution_identity, options.environment);
    defer environment_execution.close();
    var resource_execution = try resource_runtime.Runtime.init(allocator, options.resources);
    defer resource_execution.deinit();
    var external_runtime = external.Runtime.init(execution_identity, options.external);
    defer external_runtime.close();
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
    var active_arenas: std.ArrayList(ActiveArena) = .empty;
    defer active_arenas.deinit(allocator);
    var frames: std.ArrayList(Frame) = .empty;
    defer frames.deinit(allocator);
    try locals.resize(allocator, program.functions[@backingInt(entry_request.id)].scope.locals.len);
    @memset(locals.items, null);
    const entry = program.functions[@backingInt(entry_request.id)];
    var copier: value_copy.Copier = .{ .records = program.records, .limits = entry_request.limits };
    for (entry.scope.locals[0..entry.signature.parameter_count], 0..) |parameter, index| {
        if (entry_request.arguments) |values| {
            locals.items[index] = try copier.copy(allocator, parameter.ty, values[index]);
        } else if (parameter.ty == .environment_cap) {
            locals.items[index] = .{ .capability = .{ .environment_capability = try environment_execution.grant() } };
        } else if (parameter.ty.resourceKind()) |kind| {
            locals.items[index] = try resource_execution.grant(kind);
        } else {
            locals.items[index] = .{ .capability = .{ .external = try external_runtime.grant(parameter.ty.externalKind().?) } };
        }
    }
    try appendFrame(&frames, allocator, .{ .function = entry_request.id, .local_base = 0, .operand_base = 0, .call_span = .{ .start = 0, .end = 0 } });
    var execution: Execution = .{
        .allocator = allocator,
        .program = program,
        .options = options,
        .steps = &steps,
        .managed_heap = &managed_heap,
        .providers = .{ .host = entry_request.host, .environment = &environment_execution, .resources = &resource_execution, .external = &external_runtime },
        .state = .{ .arenas = &active_arenas, .stack = &stack, .locals = &locals, .frames = &frames },
    };
    while (frames.items.len != 0) {
        if (quickened.enabled and try runOptimized(&execution, &quickened)) return execution.outcome;
        // Only call handlers grow frames; they capture metadata before growth.
        // This frame pointer is used only during the current dispatch.
        const frame_index = frames.items.len - 1;
        const frame = &frames.items[frame_index];
        const function = program.functions[@backingInt(frame.function)];
        if (frame.pc >= function.scope.instructions.len) return error.InternalError;
        const instruction = &function.scope.instructions[frame.pc];
        var step: Step = .{ .execution = &execution, .frame = frame, .steps = &steps, .local_values = locals.items[frame.local_base..][0..function.scope.locals.len], .frame_index = frame_index, .instruction = instruction };
        if (steps == options.max_steps) return trap("R_STEP_LIMIT", "instruction budget exhausted", instruction.span, frames.items, program);
        steps += 1;
        if (options.memory.trace) |trace| trace.record(frame.function, frame.pc, steps, instruction.*, stack.items[frame.operand_base..]);
        frames.items[frame_index].pc += 1;
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
            .begin_arena => step.executeBeginArena(),
            .end_arena => step.executeEndArena(),
            .arena_escape => step.executeArenaEscape(),
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
            .push_unit => step.executePushUnit(),
            .buffer_operation => step.executeBufferOperation(),
            .acquire_resource => step.executeAcquireResource(),
            .resource_io => step.executeResourceIo(),
            .restrict_resource => step.executeRestrictResource(),
            .environment_get => step.executeEnvironmentGet(),
            .complete_resource => step.executeCompleteResource(),
            .external_read => step.executeExternalRead(),
            .acquire_buffer => step.executeAcquireBuffer(),
            .move_local => step.executeMoveLocal(),
            .drop_local => step.executeDropLocal(),
            .load_local => step.executeLoadLocal(),
            .store_local => step.executeStoreLocal(),
            .call => step.executeCall(),
            .ret => step.executeRet(),
            .not_bool => step.executeNotBool(),
            .neg_i64_checked => step.executeNegI64Checked(),
            .add_i64_checked, .sub_i64_checked, .mul_i64_checked => step.executeAddI64Checked(),
            .cmp_i64 => step.executeCmpI64(),
            .cmp_bool => step.executeCmpBool(),
        };
        if (outcome) return execution.outcome;
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

// An execution borrows the stores and collections owned by runValues. Individual
// instruction handlers cannot outlive that invocation or retain frame pointers.
const Execution = struct {
    outcome: ValueResult = undefined,
    allocator: std.mem.Allocator,
    program: bc.Program,
    options: Options,
    steps: *u64,
    managed_heap: *gc_heap.Heap,
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
    arenas: *std.ArrayList(ActiveArena),
    stack: *std.ArrayList(typed.Value),
    locals: *std.ArrayList(?typed.Value),
    frames: *std.ArrayList(Frame),
};
// Keep scalar dispatch separate from the large generic handler loop so the host
// compiler can retain hot state in registers across fused operations.
noinline fn runOptimized(execution: *Execution, plan: *fusion.Plan) !bool {
    var fast_steps = execution.steps.*;
    defer execution.steps.* = fast_steps;
    const frames = execution.state.frames;
    var frame_index = frames.items.len - 1;
    var frame = &frames.items[frame_index];
    var function = &execution.program.functions[@backingInt(frame.function)];
    var cache_offset = @backingInt(frame.function) *% 17;
    var frame_locals = execution.state.locals.items[frame.local_base..][0..function.scope.locals.len];
    while (true) {
        if (frame.pc >= function.scope.instructions.len) return error.InternalError;
        const fused = plan.get(execution.program, function, cache_offset, frame.pc);
        if (fused.cost == 0 or execution.options.max_steps - fast_steps < fused.cost) return false;
        var step: Step = .{ .execution = execution, .frame = frame, .steps = &fast_steps, .local_values = frame_locals, .frame_index = frame_index, .instruction = &function.scope.instructions[frame.pc] };
        switch (try step.executeFused(fused)) {
            .fallback => return false,
            .continued => {
                if (frames.items.len - 1 != frame_index) {
                    frame_index = frames.items.len - 1;
                    frame = &frames.items[frame_index];
                    function = &execution.program.functions[@backingInt(frame.function)];
                    cache_offset = @backingInt(frame.function) *% 17;
                    // Calls may grow either backing array; refresh both views.
                    frame_locals = execution.state.locals.items[frame.local_base..][0..function.scope.locals.len];
                }
            },
            .finished => return true,
        }
    }
}
const Step = struct {
    execution: *Execution,
    frame: *Frame,
    steps: *u64,
    local_values: []?Value,
    frame_index: usize,
    instruction: *const bc.Instruction,
    fn finish(self: *Step, outcome: ValueResult) bool {
        self.execution.outcome = outcome;
        if (self.execution.state.arenas.items.len != 0) self.unwindArenas();
        return true;
    }
    /// Traps, budget exhaustion and host allocation failure end the execution while
    /// arena scopes are open. Release every operand and local root first, then bulk
    /// release each arena so surviving objects keep exact reference counts.
    fn unwindArenas(self: *Step) void {
        const allocator = self.execution.allocator;
        const state = self.execution.state;
        releaseValues(state.stack.items, allocator);
        state.stack.clearRetainingCapacity();
        for (state.locals.items) |*slot| {
            if (slot.*) |owned| owned.release(allocator);
            slot.* = null;
        }
        while (state.arenas.items.len != 0) {
            _ = state.arenas.pop();
            gc_regions.end(self.execution.managed_heap);
        }
    }
    const FusedResult = enum { fallback, continued, finished };
    inline fn fastLocal(self: *Step, slot: usize) ?*Value {
        if (self.local_values[slot]) |*value| return value;
        return null;
    }
    inline fn fastScalar(self: *Step, operand: fusion.Operand, ty: typed.Type) ?i64 {
        return switch (operand) {
            .constant => |value| value,
            .local => |slot| blk: {
                const value = self.fastLocal(@backingInt(slot)) orelse break :blk null;
                // Checked stores, argument copies and pattern bindings establish
                // the declared local representation before any optimized access.
                if (ty == .i64) {
                    std.debug.assert(value.* == .i64);
                    break :blk value.i64;
                }
                std.debug.assert(ty == .bool);
                std.debug.assert(value.* == .bool);
                break :blk @intFromBool(value.bool);
            },
        };
    }
    inline fn fastDestination(self: *Step, slot: usize, ty: typed.Type) ?*?Value {
        const destination = &self.local_values[slot];
        if (destination.*) |value| std.debug.assert((ty == .i64 and value == .i64) or (ty == .bool and value == .bool));
        return destination;
    }
    inline fn advanceFused(self: *Step, count: u8) void {
        self.steps.* += count;
        self.frame.pc += count;
    }
    inline fn advanceEntry(self: *Step, fused: *const fusion.Entry) void {
        self.advanceFused(fused.cost);
        if (fused.operation.tail_jump) self.frame.pc = fused.successor;
    }
    fn fusedArithmeticFailure(self: *Step, err: error{ Overflow, DivisionByZero }, offset: u8) FusedResult {
        const pc = self.frame.pc;
        const instruction = self.execution.program.functions[@backingInt(self.frame.function)].scope.instructions[pc + offset];
        self.advanceFused(offset + 1);
        self.execution.outcome = if (err == error.Overflow)
            overflow(instruction, self.execution.state.frames.items, self.execution.program)
        else
            trap(division_zero_code, division_zero_message, instruction.span, self.execution.state.frames.items, self.execution.program);
        return .finished;
    }
    inline fn executeFused(self: *Step, fused: *const fusion.Entry) !FusedResult {
        return switch (fused.kind) {
            .none => .fallback,
            .scalar_store, .stack_binary, .stack_binary_store, .stack_binary_return, .stack_compare, .jump, .branch => self.executeScalarStack(fused),
            .scalar_call => self.executeScalarCall(@fromBackingInt(@intCast(fused.destination)), null),
            .scalar_return => blk: {
                self.advanceFused(1);
                break :blk self.executeScalarRet(fused.ty);
            },
            .index => self.executeFusedIndex(fused),
            .scalar_load, .copy, .copy_pair, .return_value => self.executeFusedValue(fused),
            .binary_store => self.executeFusedStore(fused),
            .binary_chain => self.executeFusedChain(fused),
            .compare, .compare_jump, .compare_return => self.executeFusedCompare(fused),
            .binary, .binary_compare, .binary_compare_jump, .arguments_call, .binary_call => self.executeFusedOperands(fused),
        };
    }
    fn executeFusedValue(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const left = self.fastScalar(fused.inputs.left, fused.ty) orelse return .fallback;
        if (fused.kind == .scalar_load) {
            try appendValue(self.execution.state.stack, self.execution.allocator, if (fused.ty == .i64) .{ .i64 = left } else .{ .bool = left != 0 });
            self.advanceFused(1);
            return .continued;
        }
        if (fused.kind == .copy_pair) {
            const right = switch (fused.inputs.right) {
                .local => |slot| if (@backingInt(slot) == fused.destination) left else self.fastScalar(fused.inputs.right, fused.ty) orelse return .fallback,
                .constant => |value| value,
            };
            const first = self.fastDestination(fused.destination, fused.ty) orelse return .fallback;
            const second = self.fastDestination(fused.operation.second_destination, fused.ty) orelse return .fallback;
            first.* = if (fused.ty == .i64) .{ .i64 = left } else .{ .bool = left != 0 };
            second.* = if (fused.ty == .i64) .{ .i64 = right } else .{ .bool = right != 0 };
            self.advanceEntry(fused);
            return .continued;
        }
        if (fused.kind == .copy) {
            const destination = self.fastDestination(fused.destination, fused.ty) orelse return .fallback;
            destination.* = if (fused.ty == .i64) .{ .i64 = left } else .{ .bool = left != 0 };
            self.advanceEntry(fused);
            return .continued;
        }
        if (fused.kind == .return_value) {
            self.advanceFused(fused.cost);
            self.instruction = &self.execution.program.functions[@backingInt(self.frame.function)].scope.instructions[self.frame.pc - 1];
            try appendValue(self.execution.state.stack, self.execution.allocator, if (fused.ty == .i64) .{ .i64 = left } else .{ .bool = left != 0 });
            if (fused.operation.scalar_function) return self.executeScalarRet(fused.ty);
            return if (try self.executeRet()) .finished else .continued;
        }
        unreachable;
    }
    fn executeFusedChain(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const left = self.fastScalar(fused.inputs.left, .i64) orelse return .fallback;
        const right = self.fastScalar(fused.inputs.right, .i64) orelse return .fallback;
        const third = self.fastScalar(fused.inputs.third, .i64) orelse return .fallback;
        const first = fusion.evaluate(fused.operation.arithmetic, left, right) catch |err| return self.fusedArithmeticFailure(err, 2);
        const result = fusion.evaluate(fused.operation.next_arithmetic, first, third) catch |err| return self.fusedArithmeticFailure(err, 4);
        self.advanceFused(fused.cost);
        try appendValue(self.execution.state.stack, self.execution.allocator, .{ .i64 = result });
        return .continued;
    }
    fn executeFusedStore(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const left = self.fastScalar(fused.inputs.left, .i64) orelse return .fallback;
        const right = self.fastScalar(fused.inputs.right, .i64) orelse return .fallback;
        const destination = self.fastDestination(fused.destination, .i64) orelse return .fallback;
        const result = fusion.evaluate(fused.operation.arithmetic, left, right) catch |err| return self.fusedArithmeticFailure(err, fused.operation.offset);
        self.advanceEntry(fused);
        destination.* = .{ .i64 = result };
        return .continued;
    }
    fn executeFusedCompare(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const left = self.fastScalar(fused.inputs.left, .i64) orelse return .fallback;
        const right = self.fastScalar(fused.inputs.right, .i64) orelse return .fallback;
        if (fused.kind == .compare_return) {
            if (!fusion.compare(fused.operation.predicate, left, right)) {
                self.advanceFused(4);
                self.frame.pc = fused.destination;
                return .continued;
            }
            const returned = self.fastScalar(fused.inputs.third, fused.ty) orelse return .fallback;
            self.advanceFused(6);
            try appendValue(self.execution.state.stack, self.execution.allocator, if (fused.ty == .i64) .{ .i64 = returned } else .{ .bool = returned != 0 });
            return self.executeScalarRet(fused.ty);
        }
        if (fused.kind == .compare or fused.kind == .compare_jump) {
            const result = fusion.compare(fused.operation.predicate, left, right);
            self.advanceFused(fused.cost);
            if (fused.kind == .compare_jump) {
                if (!result) self.frame.pc = fused.destination;
            } else try appendValue(self.execution.state.stack, self.execution.allocator, .{ .bool = result });
            return .continued;
        }
        unreachable;
    }
    fn executeFusedOperands(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const left = self.fastScalar(fused.inputs.left, .i64) orelse return .fallback;
        const right = self.fastScalar(fused.inputs.right, .i64) orelse return .fallback;
        if (fused.kind == .arguments_call) {
            const arguments = [_]i64{ left, right };
            self.advanceFused(fused.cost - 1);
            self.instruction = &self.execution.program.functions[@backingInt(self.frame.function)].scope.instructions[self.frame.pc];
            return self.executeScalarCall(@fromBackingInt(@intCast(fused.destination)), arguments[0 .. fused.cost - 1]);
        }
        const third = if (fused.kind == .binary_compare or fused.kind == .binary_compare_jump) self.fastScalar(fused.inputs.third, .i64) orelse return .fallback else 0;
        const result = fusion.evaluate(fused.operation.arithmetic, left, right) catch |err| return self.fusedArithmeticFailure(err, fused.operation.offset);
        if (fused.kind == .binary_call) {
            self.advanceFused(fused.cost - 1);
            self.instruction = &self.execution.program.functions[@backingInt(self.frame.function)].scope.instructions[self.frame.pc];
            return self.executeScalarCall(@fromBackingInt(@intCast(fused.destination)), &.{result});
        }
        self.advanceFused(fused.cost);
        if (fused.kind == .binary_compare or fused.kind == .binary_compare_jump) {
            const comparison = fusion.compare(fused.operation.predicate, result, third);
            if (fused.kind == .binary_compare_jump) {
                if (!comparison) self.frame.pc = fused.destination;
            } else try appendValue(self.execution.state.stack, self.execution.allocator, .{ .bool = comparison });
            return .continued;
        }
        try appendValue(self.execution.state.stack, self.execution.allocator, .{ .i64 = result });
        return .continued;
    }
    fn executeScalarStack(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const stack = self.execution.state.stack;
        if (stack.items.len < self.frame.operand_base) return error.InternalError;
        const count = stack.items.len - self.frame.operand_base;
        if (fused.kind == .jump) {
            self.advanceFused(1);
            self.frame.pc = fused.destination;
            return .continued;
        }
        if (count == 0) return .fallback;
        const top = &stack.items[stack.items.len - 1];
        if (fused.kind == .branch) {
            if (top.* != .bool) return .fallback;
            const value = top.bool;
            stack.items.len -= 1;
            self.advanceFused(1);
            if (!value) self.frame.pc = fused.destination;
            return .continued;
        }
        if (fused.kind == .scalar_store) {
            if (top.typeOf() != fused.ty) return .fallback;
            const destination = self.fastDestination(fused.destination, fused.ty) orelse return .fallback;
            destination.* = top.*;
            stack.items.len -= 1;
            self.advanceFused(1);
            return .continued;
        }
        if (count < 2 or top.* != .i64) return .fallback;
        const destination = if (fused.kind == .stack_binary_store) self.fastDestination(fused.destination, .i64) orelse return .fallback else null;
        const left = &stack.items[stack.items.len - 2];
        if (left.* != .i64) return .fallback;
        if (fused.kind == .stack_compare) {
            const result = fusion.compare(fused.operation.predicate, left.i64, top.i64);
            left.* = .{ .bool = result };
        } else {
            const result = fusion.evaluate(fused.operation.arithmetic, left.i64, top.i64) catch |err| return self.fusedArithmeticFailure(err, 0);
            left.i64 = result;
        }
        stack.items.len -= 1;
        self.advanceFused(fused.cost);
        if (destination) |out| {
            out.* = .{ .i64 = left.i64 };
            stack.items.len -= 1;
        }
        if (fused.kind == .stack_binary_return) return self.executeScalarRet(.i64);
        return .continued;
    }
    inline fn executeScalarCall(self: *Step, id: typed.FunctionId, integer_arguments: ?[]const i64) !FusedResult {
        const execution = self.execution;
        const state = execution.state;
        const callee = execution.program.functions[@backingInt(id)];
        const count = callee.signature.parameter_count;
        const stack_count = if (integer_arguments != null) 0 else count;
        if (state.stack.items.len < self.frame.operand_base or state.stack.items.len - self.frame.operand_base < stack_count) return error.InternalError;
        self.advanceFused(1);
        if (state.frames.items.len >= execution.options.max_frames) {
            execution.outcome = trap(frame_limit_code, "active frame budget exhausted", self.instruction.span, state.frames.items, execution.program);
            return .finished;
        }
        const argument_base = state.stack.items.len - stack_count;
        if (integer_arguments) |arguments| {
            if (arguments.len != count) return error.InternalError;
            for (callee.scope.locals[0..count]) |parameter| if (parameter.ty != .i64) return error.InternalError;
        } else for (callee.scope.locals[0..count], state.stack.items[argument_base..]) |parameter, value| {
            if (value.typeOf() != parameter.ty) return error.InternalError;
        }
        const local_base = state.locals.items.len;
        const local_end = std.math.add(usize, local_base, callee.scope.locals.len) catch return error.OutOfMemory;
        if (local_end > state.locals.capacity) try growLocals(state.locals, execution.allocator, local_end);
        state.locals.items.len = local_end;
        @memset(state.locals.items[local_base + count ..], null);
        if (integer_arguments) |arguments| {
            for (arguments, state.locals.items[local_base..][0..count]) |value, *destination| destination.* = .{ .i64 = value };
        } else for (state.stack.items[argument_base..], state.locals.items[local_base..][0..count]) |value, *destination| {
            destination.* = value;
        }
        state.stack.items.len = argument_base;
        const frame: Frame = .{
            .function = id,
            .local_base = local_base,
            .operand_base = argument_base,
            .call_span = self.instruction.span,
            .arena_base = state.arenas.items.len,
        };
        try appendFrame(state.frames, execution.allocator, frame);
        return .continued;
    }
    inline fn executeScalarRet(self: *Step, expected: typed.Type) !FusedResult {
        const execution = self.execution;
        const state = execution.state;
        const frame = self.frame;
        if (state.stack.items.len != frame.operand_base + 1) return error.InternalError;
        const value = &state.stack.items[frame.operand_base];
        if (expected == .i64) {
            if (value.* != .i64) return error.InternalError;
        } else if (expected == .bool) {
            if (value.* != .bool) return error.InternalError;
        } else return error.InternalError;
        state.locals.items.len = frame.local_base;
        state.frames.items.len -= 1;
        if (state.frames.items.len == 0) {
            state.stack.items.len -= 1;
            execution.outcome = .{ .value = value.* };
            return .finished;
        }
        return .continued;
    }
    fn executeFusedIndex(self: *Step, fused: *const fusion.Entry) !FusedResult {
        const base = self.fastLocal(fused.destination) orelse return .fallback;
        if (base.* != .aggregate or base.aggregate.ty != fused.ty or base.aggregate.moved_fields != null) return .fallback;
        const left = self.fastScalar(fused.inputs.left, .i64) orelse return .fallback;
        const right = self.fastScalar(fused.inputs.right, .i64) orelse return .fallback;
        const index = fusion.evaluate(fused.operation.arithmetic, left, right) catch |err| return self.fusedArithmeticFailure(err, fused.operation.offset);
        const schema = self.execution.program.records[fused.ty.recordIndex()].shape.array.?;
        const instruction = self.execution.program.functions[@backingInt(self.frame.function)].scope.instructions[self.frame.pc + fused.cost - 1];
        if (index < 0 or index >= schema.length) {
            self.advanceFused(fused.cost);
            self.execution.outcome = trap(index_bounds_code, "array index is outside its declared bounds", instruction.span, self.execution.state.frames.items, self.execution.program);
            return .finished;
        }
        const at: usize = @intCast(index);
        if (at >= base.aggregate.fields.len or base.aggregate.fields[at] != .i64) return .fallback;
        const value = base.aggregate.fields[at].i64;
        self.advanceFused(fused.cost);
        try appendValue(self.execution.state.stack, self.execution.allocator, .{ .i64 = value });
        return .continued;
    }
    fn executeTryResult(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
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
        return false;
    }

    fn executeAcknowledge(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const ty = self.instruction.op.acknowledge;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        if (value.typeOf() != ty) return error.InternalError;
        return false;
    }

    fn executePop(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        (try pop(stack, frame.operand_base)).release(allocator);
        return false;
    }

    fn executeJump(self: *Step) !bool {
        const frames = self.execution.state.frames;
        const frame_index = self.frame_index;
        const target = self.instruction.op.jump;
        frames.items[frame_index].pc = target;
        return false;
    }

    fn executeJumpIfFalse(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const frame_index = self.frame_index;
        const target = self.instruction.op.jump_if_false;
        if (!(try boolean(try pop(stack, frame.operand_base), allocator))) {
            frames.items[frame_index].pc = target;
        }
        return false;
    }

    fn executeDivI64Checked(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const right = try integer(try pop(stack, frame.operand_base), allocator);
        const left = try integer(try pop(stack, frame.operand_base), allocator);
        if (right == 0) return self.finish(trap(division_zero_code, division_zero_message, instruction.span, frames.items, program));
        const minimum_case = left == std.math.minInt(i64) and right == -1;
        if (instruction.op == .div_i64_checked and minimum_case) return self.finish(overflow(instruction, frames.items, program));
        const value = if (instruction.op == .div_i64_checked) @divTrunc(left, right) else if (minimum_case) @as(i64, 0) else @rem(left, right);
        try appendValue(stack, allocator, .{ .i64 = value });
        return false;
    }

    fn executeMakeRecord(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const record = self.instruction.op.make_record;
        if (stack.items.len - frame.operand_base < record.fields) return error.InternalError;
        const start = stack.items.len - record.fields;
        const schema = program.records[record.ty.recordIndex()];
        if (schema.managed and schema.collection.kind != .list) {
            const heap = self.execution.managed_heap;
            const result = if (schema.collection.kind == .dictionary)
                managed_dict.create(heap, record.ty, schema.collection.key.?, schema.shape.buffer.?) catch |err| return self.collectionFailure(err)
            else
                heap.create(record.ty, if (schema.collection.kind == .bytes) .u8 else .u32, record.fields) catch |err| return self.managedFailure(err);
            defer result.release(allocator);
            if (schema.collection.kind == .dictionary) {
                var index: usize = start;
                while (index < stack.items.len) : (index += 2) managed_dict.write(heap, result, stack.items[index], stack.items[index + 1]) catch |err| return self.collectionFailure(err);
            } else {
                for (stack.items[start..]) |point| heap.append(result, point) catch |err| return self.managedFailure(err);
                result.managed.collection.kind = schema.collection.kind;
            }
            releaseValues(stack.items[start..], allocator);
            stack.shrinkRetainingCapacity(start);
            try pushOwned(stack, allocator, result.retain());
            return false;
        }
        for (stack.items[start..], 0..) |field, i| {
            const field_index = if (record.order.len == 0) i else record.order[i];
            if (field.typeOf() != schema.elementType(field_index)) return error.InternalError;
        }
        const value = try typed.Value.createOrdered(allocator, record.ty, stack.items[start..], record.order);
        releaseValues(stack.items[start..], allocator);
        stack.shrinkRetainingCapacity(start);
        try pushOwned(stack, allocator, value);
        return false;
    }

    fn executeUpdateRecord(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
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
        return false;
    }

    fn executeGetIndex(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const ty = self.instruction.op.get_index;
        const key = try pop(stack, frame.operand_base);
        defer key.release(allocator);
        const base = try pop(stack, frame.operand_base);
        defer base.release(allocator);
        if (base.typeOf() != ty) return error.InternalError;
        if (base == .managed and base.managed.collection.kind != .list) {
            if (base.managed.collection.kind == .bytes) {
                const byte = managed_bytes.at(self.execution.managed_heap, base, try key.asInteger()) catch |err| return self.bytesFailure(err);
                try pushOwned(stack, allocator, byte);
                return false;
            }
            const result = if (base.managed.collection.kind == .string)
                managed_text.at(self.execution.managed_heap, base, try key.asInteger())
            else
                managed_dict.read(self.execution.managed_heap, base, key);
            const value = result catch |err| return self.collectionFailure(err);
            try pushOwned(stack, allocator, value);
            return false;
        }
        const schema = program.records[ty.recordIndex()].shape.array orelse return error.InternalError;
        const index = try arrayIndex(key, schema);
        if (index < 0 or index >= schema.length) return self.finish(trap(index_bounds_code, "array index is outside its declared bounds", instruction.span, frames.items, program));
        try pushOwned(stack, allocator, try base.getField(@intCast(index)));
        return false;
    }

    fn executeReplaceIndex(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
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
        if (index < 0 or index >= schema.length) return self.finish(trap(index_bounds_code, "array replacement index is outside its declared bounds", instruction.span, frames.items, program));
        const result = try base.updated(allocator, &.{@intCast(index)}, &.{replacement});
        releaseValues(stack.items[start..], allocator);
        stack.shrinkRetainingCapacity(start);
        try pushOwned(stack, allocator, result);
        return false;
    }

    fn executeArrayLength(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const ty = self.instruction.op.array_length;
        const base = try pop(stack, frame.operand_base);
        defer base.release(allocator);
        if (base.typeOf() != ty) return error.InternalError;
        if (base == .managed and base.managed.collection.kind != .list) {
            const size = switch (base.managed.collection.kind) {
                .string => managed_text.len(self.execution.managed_heap, base),
                .bytes => managed_bytes.len(self.execution.managed_heap, base) catch |err| return self.bytesFailure(err),
                else => managed_dict.len(self.execution.managed_heap, base),
            };
            const length = size catch |err| return self.collectionFailure(err);
            try appendValue(stack, allocator, .{ .i64 = @intCast(length) });
            return false;
        }
        const schema = program.records[ty.recordIndex()].shape.array orelse return error.InternalError;
        try appendValue(stack, allocator, typed.Value.number(.u64, schema.length));
        return false;
    }

    fn executeMakeVariant(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const variant = self.instruction.op.make_variant;
        const schema = program.records[variant.ty.recordIndex()].shape.variants.?.cases[variant.tag];
        const payload: ?typed.Value = if (schema.payload != null) try pop(stack, frame.operand_base) else null;
        defer if (payload) |value| value.release(allocator);
        if (payload) |value| if (value.typeOf() != schema.payload.?) return error.InternalError;
        try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, variant.ty, variant.tag, payload));
        return false;
    }

    fn executeSwitchVariant(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const frame_index = self.frame_index;
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
            if (locals.items[index]) |old| old.release(allocator);
            locals.items[index] = payload;
        }
        frames.items[frame_index].pc = arm.target;
        return false;
    }

    fn executeBeginArena(self: *Step) !bool {
        const arenas = self.execution.state.arenas;
        try arenas.append(self.execution.allocator, .{ .watermark = @backingInt(self.instruction.op.begin_arena), .frame = self.frame_index });
        gc_regions.begin(self.execution.managed_heap);
        return false;
    }

    fn executeEndArena(self: *Step) !bool {
        const execution = self.execution;
        const arenas = execution.state.arenas;
        if (arenas.items.len <= self.frame.arena_base) return error.InternalError;
        const active = arenas.items[arenas.items.len - 1];
        if (active.frame != self.frame_index) return error.InternalError;
        if (active.watermark != @backingInt(self.instruction.op.end_arena)) return error.InternalError;
        const heap = execution.managed_heap;
        const scanned = @min(active.watermark, self.local_values.len);
        for (self.local_values[0..scanned]) |slot| {
            const value = slot orelse continue;
            const escaped = gc_regions.retains(heap, value) catch |err| return self.managedFailure(err);
            if (escaped) return self.finish(trap(
                arena_escape_code,
                "a binding declared before this arena still references storage allocated inside it",
                self.instruction.span,
                execution.state.frames.items,
                execution.program,
            ));
        }
        // Bindings introduced inside the block die with it. Release them before the
        // bulk free so no execution root can observe a released arena object.
        var index = self.local_values.len;
        while (index > scanned) {
            index -= 1;
            if (self.local_values[index]) |owned| owned.release(execution.allocator);
            self.local_values[index] = null;
        }
        _ = arenas.pop();
        gc_regions.end(heap);
        return false;
    }

    fn executeArenaEscape(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        if (value.typeOf() != self.instruction.op.arena_escape) return error.InternalError;
        const copied = gc_regions.escape(self.execution.managed_heap, value) catch |err| return self.managedFailure(err);
        try pushOwned(stack, allocator, copied);
        return false;
    }

    fn executeCmpEnum(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const comparison = self.instruction.op.cmp_enum;
        const right = try pop(stack, frame.operand_base);
        defer right.release(allocator);
        const left = try pop(stack, frame.operand_base);
        defer left.release(allocator);
        if (left.typeOf() != comparison.ty or right.typeOf() != comparison.ty) return error.InternalError;
        const equal = try left.variantTag() == try right.variantTag();
        try appendValue(stack, allocator, .{ .bool = if (comparison.predicate == .eq) equal else !equal });
        return false;
    }

    fn executeCmpDomain(self: *Step) !bool {
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
        try appendValue(stack, allocator, .{ .bool = if (comparison.predicate == .eq) equal else !equal });
        return false;
    }

    fn executeWrapDomain(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const ty = self.instruction.op.wrap_domain;
        const input = try pop(stack, frame.operand_base);
        defer input.release(allocator);
        const backing = program.records[ty.recordIndex()].shape.domain orelse return error.InternalError;
        if (input.typeOf() != backing) return error.InternalError;
        try pushOwned(stack, allocator, try typed.Value.create(allocator, ty, &.{input}));
        return false;
    }

    fn executeUnwrapDomain(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const ty = self.instruction.op.unwrap_domain;
        const input = try pop(stack, frame.operand_base);
        defer input.release(allocator);
        if (input.typeOf() != ty) return error.InternalError;
        try pushOwned(stack, allocator, try input.getField(0));
        return false;
    }

    fn executeGetField(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const index = self.instruction.op.get_field;
        const record = try pop(stack, frame.operand_base);
        defer record.release(allocator);
        if (record.typeOf().isAggregate() and (program.records[record.typeOf().recordIndex()].shape.domain != null or program.records[record.typeOf().recordIndex()].shape.variants != null)) return error.InternalError;
        try pushOwned(stack, allocator, try record.getField(index));
        return false;
    }

    fn executeUnaryFloat(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const op = self.instruction.op.unary_float;
        const operand = try numeric(stack, self.frame.operand_base, if (op == .f64_from_i64) .i64 else .u64, allocator);
        const input: u64 = if (op == .f64_from_i64) @bitCast(@as(i64, @intCast(operand))) else @intCast(operand);
        const value = @import("floats.zig").unary(op, input) catch |err| switch (err) {
            error.FloatConversion => return self.finish(trap("R_FLOAT_CONVERSION", "floating value is outside the target integer range", self.instruction.span, self.execution.state.frames.items, self.execution.program)),
            else => return error.InternalError,
        };
        try appendValue(stack, allocator, if (op == .f64_to_i64) .{ .i64 = @bitCast(value) } else Value.number(.u64, value));
        return false;
    }
    fn executePushInteger(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const number = self.instruction.op.push_integer;
        try appendValue(stack, allocator, typed.Value.number(number.ty, number.value));
        return false;
    }

    fn executeCastInteger(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const ty = switch (self.instruction.op) {
            .cast_integer, .neg_integer => |value| value,
            else => unreachable,
        };
        if (ty.isAggregate() and program.records[ty.recordIndex()].collection.kind == .bytes) {
            const input = try pop(stack, frame.operand_base);
            defer input.release(allocator);
            const built = managed_bytes.fromList(self.execution.managed_heap, ty, input) catch |err| return self.bytesFailure(err);
            try pushOwned(stack, allocator, built);
            return false;
        }
        if (ty.isAggregate() and program.records[ty.recordIndex()].collection.kind == .string) {
            const input = try pop(stack, frame.operand_base);
            defer input.release(allocator);
            const input_type = input.typeOf();
            const floating = input_type.isAggregate() and std.mem.eql(u8, program.records[input_type.recordIndex()].name, "float");
            const converted = managed_text.convert(self.execution.managed_heap, ty, input, floating) catch |err| return self.collectionFailure(err);
            try pushOwned(stack, allocator, converted);
            return false;
        }
        const operand = try numeric(stack, frame.operand_base, if (instruction.op == .neg_integer) ty else null, allocator);
        const value = integers.cast(ty, if (instruction.op == .neg_integer) -operand else operand) catch |err| switch (err) {
            error.Overflow => return self.finish(trap(overflow_code, "integer conversion or negation exceeds the destination width", instruction.span, frames.items, program)),
            else => return error.InternalError,
        };
        try appendValue(stack, allocator, value);
        return false;
    }

    fn executeBinaryInteger(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const binary = self.instruction.op.binary_integer;
        if (binary.ty.isAggregate() and program.records[binary.ty.recordIndex()].managed) {
            const text = managed_text;
            const right_value = try pop(stack, frame.operand_base);
            defer right_value.release(allocator);
            const left_value = try pop(stack, frame.operand_base);
            defer left_value.release(allocator);
            if (binary.op == .add and program.records[binary.ty.recordIndex()].collection.kind == .bytes) {
                const joined = managed_bytes.concat(self.execution.managed_heap, left_value, right_value) catch |err| return self.bytesFailure(err);
                try pushOwned(stack, allocator, joined);
                return false;
            }
            const result: managed_dict.Error!Value = if (binary.op == .add) text.concat(self.execution.managed_heap, left_value, right_value) else comparison: {
                const equal = managed_equal.equalWithRecords(self.execution.managed_heap, left_value, right_value, program.records) catch |err| break :comparison err;
                break :comparison Value{ .bool = equal == (binary.op == .eq) };
            };
            const value = result catch |err| return self.collectionFailure(err);
            try pushOwned(stack, allocator, value);
            return false;
        }
        const right = try numeric(stack, frame.operand_base, binary.ty, allocator);
        const left = try numeric(stack, frame.operand_base, binary.ty, allocator);
        const value = integers.binary(binary.ty, binary.op, left, right) catch |err| switch (err) {
            error.Overflow => return self.finish(trap(overflow_code, "integer arithmetic exceeds its declared width", instruction.span, frames.items, program)),
            error.InvalidShift => return self.finish(trap("R_INVALID_SHIFT", "shift count must be nonnegative and smaller than the integer width", instruction.span, frames.items, program)),
            error.DivisionByZero => return self.finish(trap(division_zero_code, division_zero_message, instruction.span, frames.items, program)),
            else => return error.InternalError,
        };
        try appendValue(stack, allocator, value);
        return false;
    }

    fn executePushI64(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const value = self.instruction.op.push_i64;
        try appendValue(stack, allocator, .{ .i64 = value });
        return false;
    }

    fn executePushUnit(self: *Step) !bool {
        try appendValue(self.execution.state.stack, self.execution.allocator, .unit);
        return false;
    }

    fn executePushBool(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const value = self.instruction.op.push_bool;
        try appendValue(stack, allocator, .{ .bool = value });
        return false;
    }

    fn executeBufferOperation(self: *Step) !bool {
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const operation = self.instruction.op.buffer_operation;
        const count = operation.kind.arity();
        if (stack.items.len - frame.operand_base < count) return error.InternalError;
        const start = stack.items.len - count;
        const arguments = stack.items[start..];
        const owner = self.local_values[@backingInt(operation.owner)] orelse return error.InternalError;
        const local = owner.retain();
        defer local.release(self.execution.allocator);
        if (local != .managed) return error.InternalError;
        return self.executeManagedOperation(local, arguments, start);
    }

    fn executeManagedOperation(self: *Step, list: Value, arguments: []const Value, start: usize) !bool {
        const execution = self.execution;
        const heap = execution.managed_heap;
        const operation = self.instruction.op.buffer_operation;
        if (list.managed.collection.kind == .bytes) return self.executeByteString(list, arguments, start);
        if (list.managed.collection.kind != .list) return self.executeTextDictionary(list, arguments, start);
        const number = if (operation.kind == .read or operation.kind == .write) try arguments[0].asInteger() else 0;
        if (number < 0 or number > std.math.maxInt(usize)) return self.finish(trap(list_bounds_code, list_bounds_message, self.instruction.span, execution.state.frames.items, execution.program));
        const index: usize = @intCast(number);
        const output: Value = switch (operation.kind) {
            .iteration_check => checked: {
                if (try arguments[0].asInteger() != heap.len(list) catch |err| return self.managedFailure(err)) return self.finish(trap(
                    iteration_mutation_code,
                    "list length changed during iteration",
                    self.instruction.span,
                    execution.state.frames.items,
                    execution.program,
                ));
                break :checked .unit;
            },
            .contains => .{ .bool = managed_equal.containsWithRecords(heap, list, arguments[0], self.execution.program.records) catch |err| return self.collectionFailure(err) },
            .length => Value.number(.u64, heap.len(list) catch |err| return self.managedFailure(err)),
            .capacity => Value.number(.u64, list.managed.items.capacity),
            .read => heap.read(list, index) catch |err| return self.managedFailure(err),
            .append => mutation: {
                heap.append(list, arguments[0]) catch |err| return self.managedFailure(err);
                break :mutation .unit;
            },
            .write => mutation: {
                heap.write(list, index, arguments[1]) catch |err| return self.managedFailure(err);
                break :mutation .unit;
            },
            else => return error.InternalError,
        };
        releaseValues(arguments, execution.allocator);
        execution.state.stack.shrinkRetainingCapacity(start);
        try pushOwned(execution.state.stack, execution.allocator, output);
        return false;
    }

    fn executeTextDictionary(self: *Step, value: Value, arguments: []const Value, start: usize) !bool {
        const heap = self.execution.managed_heap;
        const operation = self.instruction.op.buffer_operation;
        const dictionary = managed_dict;
        const text = managed_text;
        if (operation.kind == .iteration_check) {
            const length = if (value.managed.collection.kind == .dictionary) (dictionary.len(heap, value) catch |err| return self.collectionFailure(err)) else (text.len(heap, value) catch |err| return self.collectionFailure(err));
            if (length != try arguments[0].asInteger()) return self.finish(trap(iteration_mutation_code, "collection size changed during iteration", self.instruction.span, self.execution.state.frames.items, self.execution.program));
            releaseValues(arguments, self.execution.allocator);
            self.execution.state.stack.shrinkRetainingCapacity(start);
            try pushOwned(self.execution.state.stack, self.execution.allocator, .unit);
            return false;
        }
        const result: dictionary.Error!Value = if (value.managed.collection.kind == .string) switch (operation.kind) {
            .length => length: {
                const n = text.len(heap, value) catch |err| break :length err;
                break :length Value{ .i64 = @intCast(n) };
            },
            .read => text.at(heap, value, try arguments[0].asInteger()),
            .contains => contains: {
                const found = managed_equal.containsWithRecords(heap, value, arguments[0], self.execution.program.records) catch |err| break :contains err;
                break :contains Value{ .bool = found };
            },
            .slice => text.slice(heap, value, try arguments[0].asInteger(), try arguments[1].asInteger()),
            .split => text.split(heap, operation.output, value, arguments[0]),
            .join => text.join(heap, value, arguments[0]),
            .encode, .from_hex => return self.executeByteString(value, arguments, start),
            else => return error.InternalError,
        } else switch (operation.kind) {
            .length => length: {
                const n = dictionary.len(heap, value) catch |err| break :length err;
                break :length Value{ .i64 = @intCast(n) };
            },
            .read => dictionary.read(heap, value, arguments[0]),
            .key_at => dictionary.keyAt(heap, value, try arguments[0].asInteger()),
            .write => writing: {
                dictionary.write(heap, value, arguments[0], arguments[1]) catch |err| break :writing err;
                break :writing Value.unit;
            },
            .get => dictionary.get(heap, value, arguments[0], arguments[1]),
            .contains => contains: {
                const found = dictionary.contains(heap, value, arguments[0]) catch |err| break :contains err;
                break :contains Value{ .bool = found };
            },
            .keys, .values => dictionary.snapshot(heap, value, operation.output, operation.kind == .keys),
            else => return error.InternalError,
        };
        const output = result catch |err| return self.collectionFailure(err);
        releaseValues(arguments, self.execution.allocator);
        self.execution.state.stack.shrinkRetainingCapacity(start);
        try pushOwned(self.execution.state.stack, self.execution.allocator, output);
        return false;
    }

    fn executeByteString(self: *Step, value: Value, arguments: []const Value, start: usize) !bool {
        const heap = self.execution.managed_heap;
        const operation = self.instruction.op.buffer_operation;
        if (operation.kind == .decode or operation.kind == .from_hex) return self.executeByteResult(value, arguments, start, operation.kind == .from_hex);
        const result: managed_bytes.Error!Value = switch (operation.kind) {
            .length => byteCount(managed_bytes.len(heap, value)),
            .iteration_check => check: {
                const size = managed_bytes.len(heap, value) catch |err| break :check err;
                if (size != try arguments[0].asInteger()) return self.finish(trap(iteration_mutation_code, "collection size changed during iteration", self.instruction.span, self.execution.state.frames.items, self.execution.program));
                break :check Value.unit;
            },
            .read => managed_bytes.at(heap, value, try arguments[0].asInteger()),
            .slice => managed_bytes.slice(heap, value, try arguments[0].asInteger(), try arguments[1].asInteger()),
            .split => managed_bytes.split(heap, operation.output, value, arguments[0]),
            .join => managed_bytes.join(heap, value, arguments[0]),
            .contains => byteTruth(managed_bytes.contains(heap, value, arguments[0])),
            .starts_with => byteTruth(managed_bytes.startsWith(heap, value, arguments[0])),
            .ends_with => byteTruth(managed_bytes.endsWith(heap, value, arguments[0])),
            .find => found: {
                const at = managed_bytes.find(heap, value, arguments[0]) catch |err| break :found err;
                break :found Value{ .i64 = at };
            },
            .to_list => managed_bytes.toList(heap, operation.output, value),
            .hex => managed_bytes.hex(heap, operation.output, value),
            .encode => managed_bytes.encode(heap, operation.output, value),
            else => return error.InternalError,
        };
        const output = result catch |err| return self.bytesFailure(err);
        releaseValues(arguments, self.execution.allocator);
        self.execution.state.stack.shrinkRetainingCapacity(start);
        try pushOwned(self.execution.state.stack, self.execution.allocator, output);
        return false;
    }

    fn executeByteResult(self: *Step, value: Value, arguments: []const Value, start: usize, hexadecimal: bool) !bool {
        const allocator = self.execution.allocator;
        const heap = self.execution.managed_heap;
        const operation = self.instruction.op.buffer_operation;
        const shape = typed.resultShape(operation.output, self.execution.program.records) orelse return error.InternalError;
        var tag = shape.ok_tag;
        const produced = if (hexadecimal) managed_bytes.fromHex(heap, shape.ok_type, value) else managed_bytes.decode(heap, shape.ok_type, value);
        const payload = produced catch |err| switch (err) {
            error.InvalidUtf8, error.InvalidHex => message: {
                tag = shape.error_tag;
                break :message managed_text.create(heap, shape.error_type, if (hexadecimal) invalid_hex_message else invalid_utf8_message) catch |other| return self.bytesFailure(other);
            },
            else => return self.bytesFailure(err),
        };
        defer payload.release(allocator);
        const output = try typed.Value.createVariant(allocator, operation.output, tag, payload);
        releaseValues(arguments, allocator);
        self.execution.state.stack.shrinkRetainingCapacity(start);
        try pushOwned(self.execution.state.stack, allocator, output);
        return false;
    }

    fn bytesFailure(self: *Step, err: managed_bytes.Error) RunError!bool {
        const code: []const u8 = switch (err) {
            error.Bounds => list_bounds_code,
            error.ArenaEscape => return self.managedFailure(error.ArenaEscape),
            error.ByteRange => "R_BYTE_RANGE",
            error.EmptySeparator => "R_EMPTY_SEPARATOR",
            error.InvalidHex, error.InvalidUtf8 => return error.InternalError,
            error.OutOfMemory => return error.OutOfMemory,
            error.CapacityLimit => return error.CapacityLimit,
            error.ForeignMemory => return error.ForeignMemory,
            error.InvalidDataValue => return error.InvalidDataValue,
            error.TypeMismatch => return error.TypeMismatch,
        };
        return self.finish(trap(code, "byte string operation failed", self.instruction.span, self.execution.state.frames.items, self.execution.program));
    }

    fn collectionFailure(self: *Step, err: managed_dict.Error) RunError!bool {
        const code: []const u8 = switch (err) {
            error.Bounds => "R_TEXT_BOUNDS",
            error.MissingKey => "R_MISSING_KEY",
            error.EmptySeparator => "R_EMPTY_SEPARATOR",
            error.ArenaEscape => return self.managedFailure(error.ArenaEscape),
            error.InvalidKey, error.InvalidUtf8 => return error.InternalError,
            error.OutOfMemory => return error.OutOfMemory,
            error.CapacityLimit => return error.CapacityLimit,
            error.ForeignMemory => return error.ForeignMemory,
            error.InvalidDataValue => return error.InvalidDataValue,
            error.TypeMismatch => return error.TypeMismatch,
        };
        return self.finish(trap(code, "collection operation failed", self.instruction.span, self.execution.state.frames.items, self.execution.program));
    }

    fn managedFailure(self: *Step, err: gc_heap.Error) !bool {
        switch (err) {
            error.Bounds => return self.finish(trap(list_bounds_code, list_bounds_message, self.instruction.span, self.execution.state.frames.items, self.execution.program)),
            error.ArenaEscape => return self.finish(trap(
                arena_escape_code,
                "storing a value allocated in this arena into an object that outlives it would leave a dangling reference",
                self.instruction.span,
                self.execution.state.frames.items,
                self.execution.program,
            )),
            error.OutOfMemory => return error.OutOfMemory,
            error.CapacityLimit => return error.CapacityLimit,
            error.ForeignMemory => return error.ForeignMemory,
            error.InvalidDataValue => return error.InvalidDataValue,
            error.TypeMismatch => return error.TypeMismatch,
        }
    }

    fn executeAcquireResource(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const acquire = self.instruction.op.acquire_resource;
        const request = try pop(stack, frame.operand_base);
        defer request.release(allocator);
        const capability = try pop(stack, frame.operand_base);
        defer capability.release(allocator);
        const output = resource_execution.acquire(acquire.output, program.records, capability, request, acquire.request) catch |err| switch (err) {
            error.InvalidCapability, error.InvalidOwner, error.Closed => return self.finish(trap(capability_code, "external resource authority is stale or invalid", instruction.span, frames.items, program)),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return false;
    }

    fn executeResourceIo(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const io = self.instruction.op.resource_io;
        const input = if (io.kind == .write) try pop(stack, frame.operand_base) else null;
        defer if (input) |value| value.release(allocator);
        const owner = locals.items[frame.local_base + @backingInt(io.owner)] orelse return error.InternalError;
        const output = resource_execution.io(program.records, .{ .kind = io.kind, .output = io.output, .value = owner, .input = input, .input_type = io.input }) catch |err| switch (err) {
            error.InvalidCapability, error.InvalidOwner, error.Closed => return self.finish(trap(capability_code, "resource I/O owner is stale or invalid", instruction.span, frames.items, program)),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return false;
    }

    fn executeRestrictResource(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const restrict = self.instruction.op.restrict_resource;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        if (value.typeOf() != restrict.ty) return error.InternalError;
        const restricted = resource_execution.restrict(value, restrict.permissions) catch |err| switch (err) {
            error.InvalidCapability, error.Closed => return self.finish(trap(capability_code, "resource capability is stale or invalid", instruction.span, frames.items, program)),
            else => return err,
        };
        try pushOwned(stack, allocator, restricted);
        return false;
    }

    fn executeEnvironmentGet(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const environment_execution = self.execution.providers.environment;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const get = self.instruction.op.environment_get;
        const name = try pop(stack, frame.operand_base);
        defer name.release(allocator);
        const capability = try pop(stack, frame.operand_base);
        defer capability.release(allocator);
        const output = environment.readValue(allocator, environment_execution, .{ .output = get.output, .capability = capability, .name = name, .name_type = get.name }, program.records) catch |err| switch (err) {
            error.InvalidCapability => return self.finish(trap(capability_code, "environment capability is stale or invalid", instruction.span, frames.items, program)),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return false;
    }

    fn executeCompleteResource(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const resource_execution = self.execution.providers.resources;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const output_type = self.instruction.op.complete_resource;
        const value = try pop(stack, frame.operand_base);
        defer value.release(allocator);
        const output = resource_execution.complete(output_type, program.records, value) catch |err| switch (err) {
            error.InvalidCapability, error.InvalidOwner, error.Closed => return self.finish(trap(capability_code, "external resource owner is stale or invalid", instruction.span, frames.items, program)),
            else => return err,
        };
        try pushOwned(stack, allocator, output);
        return false;
    }

    fn executeExternalRead(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const external_runtime = self.execution.providers.external;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
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
                error.InvalidCapability => return self.finish(trap(capability_code, "external capability has the wrong kind or execution identity", instruction.span, frames.items, program)),
            };
            break :sample 0;
        };
        const shape = typed.resultShape(read.output, program.records).?;
        try pushOwned(stack, allocator, try typed.Value.createVariant(allocator, read.output, if (status == 0) shape.ok_tag else shape.error_tag, if (status == 0) typed.Value.number(shape.ok_type, sample) else .{ .i64 = status }));
        return false;
    }

    fn executeAcquireBuffer(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const ty = self.instruction.op.acquire_buffer;
        const capacity = try numeric(stack, frame.operand_base, null, allocator);
        if (!program.records[ty.recordIndex()].managed) return error.InternalError;
        if (capacity < 0 or capacity > std.math.maxInt(usize)) return self.finish(trap("R_LIST_CAPACITY", "list capacity is outside supported bounds", instruction.span, frames.items, program));
        const value = self.execution.managed_heap.create(ty, program.records[ty.recordIndex()].shape.buffer.?, @intCast(capacity)) catch |err| return self.managedFailure(err);
        try pushOwned(stack, allocator, value);
        return false;
    }

    fn executeMoveLocal(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frame = self.frame.*;
        const slot = self.instruction.op.move_local;
        const index = frame.local_base + @backingInt(slot);
        const value = locals.items[index] orelse return error.InternalError;
        locals.items[index] = null;
        try pushOwned(stack, allocator, value);
        return false;
    }

    fn executeDropLocal(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const locals = self.execution.state.locals;
        const frame = self.frame.*;
        const slot = self.instruction.op.drop_local;
        const index = frame.local_base + @backingInt(slot);
        if (locals.items[index]) |value| value.release(allocator);
        locals.items[index] = null;
        return false;
    }

    fn executeLoadLocal(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frame = self.frame.*;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const slot = self.instruction.op.load_local;
        if (typed.moveOnly(function.scope.locals[@backingInt(slot)].ty, program.records)) return error.InternalError;
        const index = frame.local_base + @backingInt(slot);
        const value = (locals.items[index] orelse return error.InternalError).retain();
        try pushOwned(stack, allocator, value);
        return false;
    }

    fn executeStoreLocal(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frame = self.frame.*;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const slot = self.instruction.op.store_local;
        const value = try pop(stack, frame.operand_base);
        errdefer value.release(allocator);
        if (value.typeOf() != function.scope.locals[@backingInt(slot)].ty) return error.InternalError;
        const index = frame.local_base + @backingInt(slot);
        if (locals.items[index]) |old| old.release(allocator);
        locals.items[index] = value;
        return false;
    }

    fn hostFailure(self: *Step, err: host.Error) RunError!bool {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        const code: []const u8 = switch (err) {
            error.HostCallLimit, error.HostWorkLimit, error.ValueCountLimit, error.ValueDepthLimit => "R_HOST_LIMIT",
            error.HostFailure => "R_HOST_FAILURE",
            else => "R_HOST_CONTRACT",
        };
        return self.finish(trap(code, @errorName(err), self.instruction.span, self.execution.state.frames.items, self.execution.program));
    }
    fn executeFunctionValue(self: *Step) !bool {
        const value = self.instruction.op.function_value;
        try appendValue(self.execution.state.stack, self.execution.allocator, .{ .integer = .{ .ty = value.ty, .value = @backingInt(value.function) } });
        return false;
    }
    fn indirectTarget(self: *Step, ty: typed.Type) !typed.FunctionId {
        const contract = callables.signature(ty, self.execution.program.records) orelse return error.InternalError;
        const stack = self.execution.state.stack;
        if (stack.items.len <= contract.valueCount() + self.frame.operand_base) return error.InternalError;
        const value = stack.orderedRemove(stack.items.len - contract.valueCount() - 1);
        defer value.release(self.execution.allocator);
        if (value.typeOf() != ty) return error.InternalError;
        const target = try value.asInteger();
        if (target < 0 or target >= self.execution.program.functions.len) return error.InternalError;
        const id: typed.FunctionId = @fromBackingInt(@as(usize, @intCast(target)));
        if (!callables.accepts(contract, self.execution.program.functions[@backingInt(id)])) return error.InternalError;
        return id;
    }
    fn executeCall(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const options = self.execution.options;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const id = switch (instruction.op) {
            .invoke => |callback_type| try self.indirectTarget(callback_type),
            .call => |id| id,
            else => unreachable,
        };
        const callee = program.functions[@backingInt(id)];
        const value_count = bc.valueParameterCount(callee);
        if (stack.items.len < frame.operand_base or stack.items.len - frame.operand_base < value_count) return error.InternalError;
        if (frames.items.len >= options.max_frames) return self.finish(trap(frame_limit_code, "active frame budget exhausted", instruction.span, frames.items, program));
        const argument_base = stack.items.len - value_count;
        var argument_index = argument_base;
        for (callee.scope.locals[0..callee.signature.parameter_count]) |parameter| {
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
            return false;
        }
        const local_base = locals.items.len;
        const local_end = std.math.add(usize, local_base, callee.scope.locals.len) catch return error.OutOfMemory;
        try locals.resize(allocator, local_end);
        @memset(locals.items[local_base..], null);
        argument_index = argument_base;
        for (0..callee.signature.parameter_count) |index| {
            locals.items[local_base + index] = stack.items[argument_index];
            argument_index += 1;
        }
        stack.shrinkRetainingCapacity(argument_base);
        try appendFrame(frames, allocator, .{
            .arena_base = self.execution.state.arenas.items.len,
            .function = id,
            .local_base = local_base,
            .operand_base = argument_base,
            .call_span = instruction.span,
        });
        return false;
    }

    fn executeRet(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const locals = self.execution.state.locals;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const function = self.execution.program.functions[@backingInt(self.frame.function)];
        const value = try pop(stack, frame.operand_base);
        var transferred = false;
        defer if (!transferred) value.release(allocator);
        if (stack.items.len != frame.operand_base) return error.InternalError;
        if (value.typeOf() != function.signature.return_type) return error.InternalError;
        var cleanup_index = locals.items.len;
        while (cleanup_index > frame.local_base) {
            cleanup_index -= 1;
            const local = &locals.items[cleanup_index];
            if (local.*) |owned| owned.release(allocator);
            local.* = null;
        }
        locals.shrinkRetainingCapacity(frame.local_base);
        const arenas = self.execution.state.arenas;
        while (arenas.items.len > frame.arena_base) {
            _ = arenas.pop();
            gc_regions.end(self.execution.managed_heap);
        }
        _ = frames.pop();
        transferred = true;
        if (frames.items.len == 0) return self.finish(.{ .value = value });
        try pushOwned(stack, allocator, value);
        return false;
    }

    fn executeNotBool(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        try appendValue(stack, allocator, .{ .bool = !(try boolean(try pop(stack, frame.operand_base), allocator)) });
        return false;
    }

    fn executeNegI64Checked(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const value = try integer(try pop(stack, frame.operand_base), allocator);
        const result = @subWithOverflow(@as(i64, 0), value);
        if (result[1] != 0) return self.finish(overflow(instruction, frames.items, program));
        try appendValue(stack, allocator, .{ .i64 = result[0] });
        return false;
    }

    fn executeAddI64Checked(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const program = self.execution.program;
        const stack = self.execution.state.stack;
        const frames = self.execution.state.frames;
        const frame = self.frame.*;
        const instruction = self.instruction.*;
        const right = try integer(try pop(stack, frame.operand_base), allocator);
        const left = try integer(try pop(stack, frame.operand_base), allocator);
        const result = switch (instruction.op) {
            .add_i64_checked => @addWithOverflow(left, right),
            .sub_i64_checked => @subWithOverflow(left, right),
            .mul_i64_checked => @mulWithOverflow(left, right),
            else => return error.InternalError,
        };
        if (result[1] != 0) return self.finish(overflow(instruction, frames.items, program));
        try appendValue(stack, allocator, .{ .i64 = result[0] });
        return false;
    }

    fn executeCmpI64(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
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
        try appendValue(stack, allocator, .{ .bool = value });
        return false;
    }

    fn executeCmpBool(self: *Step) !bool {
        const allocator = self.execution.allocator;
        const stack = self.execution.state.stack;
        const frame = self.frame.*;
        const predicate = self.instruction.op.cmp_bool;
        const right = try boolean(try pop(stack, frame.operand_base), allocator);
        const left = try boolean(try pop(stack, frame.operand_base), allocator);
        try appendValue(stack, allocator, .{ .bool = if (predicate == .eq) left == right else left != right });
        return false;
    }
};
