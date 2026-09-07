//! Bounded source-level typed JSON, using checked codecs and explicit allocation authority.
const std = @import("std");
const typed = @import("typed.zig");
const json = @import("typed_json.zig");
const memory = @import("memory.zig");
const bc = @import("bytecode.zig");
const codec_execution = @import("codec_execution.zig");
const invocation = @import("invocation_contract.zig");
const Op = @FieldType(@FieldType(bc.Instruction, "op"), "json_codec");
/// Result codes: invalid wire/value, quota, domain rejection/trap, invalid byte budget.
pub const Code = enum(i64) { invalid = 1, limit = 2, domain = 3, budget = 4 };
/// Charged instruction work is returned separately from the owned checked result.
pub const Outcome = struct { value: typed.Value, steps: u64 };
/// VM resources and remaining budgets shared by one source operation.
pub const Context = struct {
    program: bc.Program,
    storage: *memory.Store,
    steps: u64,
    frames: u64,
    dispatch: invocation.Dispatch,
};
/// Evaluated source operands, retained by the calling VM instruction.
pub const Request = struct { op: Op, authority: typed.Value, input: typed.Value, limit: i128 };
/// Execute one operation; all input values remain owned by the VM instruction.
pub fn run(allocator: std.mem.Allocator, context: Context, request: Request) (invocation.RunError || error{ CodecStepLimit, CodecFrameLimit })!Outcome {
    const program = context.program;
    const storage = context.storage;
    const steps = context.steps;
    const frames = context.frames;
    const op = request.op;
    const authority = request.authority;
    const input = request.input;
    const limit = request.limit;
    if (!authority.isCapability(.allocator) or input.typeOf() != op.input) return error.InternalError;
    try storage.checkAllocator(authority.capability.allocator);
    const shape = typed.resultShape(op.output, program.records) orelse return error.InternalError;
    if (limit <= 0 or limit > 1024 * 1024) return failure(allocator, op.output, shape.error_tag, .budget, 0);
    var bounded: @import("codec_memory.zig").Memory = .{ .parent = allocator, .limit = if (op.document) 128 * 1024 * 1024 else 32 * 1024 * 1024 };
    const scratch = bounded.allocator();
    var codec_failure: codec_execution.Failure = .{};
    defer codec_failure.deinit(scratch);
    var execution: codec_execution.Execution = .{ .backend = .{ .dispatch = context.dispatch, .program = program }, .max_steps = steps, .max_frames = frames, .max_calls = 256, .arguments = .{}, .failure = &codec_failure };
    var traversal: Traversal = .{ .budget = .{ .limits = .{ .max_bytes = @intCast(limit) } } };
    const budget = &traversal.budget;
    const byte_work = &traversal.bytes;
    const result = convert(scratch, context, request, shape.ok_type, &execution, &traversal) catch |err| {
        if (codec_failure.trap) |trap| {
            if (std.mem.eql(u8, trap.code, "R_FRAME_LIMIT")) return error.CodecFrameLimit;
            if (std.mem.eql(u8, trap.code, "R_STEP_LIMIT")) return error.CodecStepLimit;
        }
        if (err == error.InvalidBudget and execution.max_frames == 0) return error.CodecFrameLimit;
        const used = execution.used.steps + budget.values + byte_work.*;
        if (used > steps or err == error.CodecStepLimit) return error.CodecStepLimit;
        if (err == error.OutOfMemory and !bounded.limit_failure) return error.OutOfMemory;
        if (err == error.InternalError) return error.InternalError;
        const code: Code = switch (err) {
            error.CodecByteLimit, error.CodecDepthLimit, error.CodecTokenLimit, error.CodecValueLimit, error.CodecWorkLimit, error.CodecCallLimit, error.CapacityLimit, error.OutOfMemory => .limit,
            error.DomainCodecRejected, error.DomainCodecTrap => .domain,
            else => .invalid,
        };
        return failure(allocator, op.output, shape.error_tag, code, used);
    };
    defer result.release(allocator);
    const used = execution.used.steps + budget.values + byte_work.*;
    if (used > steps) return error.CodecStepLimit;
    return .{ .value = try typed.Value.createVariant(allocator, op.output, shape.ok_tag, result), .steps = used };
}
fn failure(allocator: std.mem.Allocator, ty: typed.Type, tag: usize, code: Code, steps: u64) !Outcome {
    return .{ .value = try typed.Value.createVariant(allocator, ty, tag, .{ .i64 = @backingInt(code) }), .steps = steps };
}
const Traversal = struct { budget: json.Budget, bytes: usize = 0 };
fn convert(
    allocator: std.mem.Allocator,
    context: Context,
    request: Request,
    output: typed.Type,
    execution: *codec_execution.Execution,
    traversal: *Traversal,
) !typed.Value {
    const budget = &traversal.budget;
    const byte_work = &traversal.bytes;
    const storage = context.storage;
    const op = request.op;
    const authority = request.authority;
    const input = request.input;
    var location: json.Location = .{};
    if (op.decode) {
        if (input != .owned or input.owned != .resource) return error.InternalError;
        const resource = input.owned.resource;
        if (resource.store != storage) return error.ForeignMemory;
        const info = try storage.bufferInfo(resource.owner);
        if (info.element_type != .u8) return error.InternalError;
        if (info.length > budget.limits.max_bytes) return error.CodecByteLimit;
        if (info.length > execution.max_steps) return error.CodecStepLimit;
        byte_work.* = info.length;
        const bytes = try allocator.alloc(u8, info.length);
        defer allocator.free(bytes);
        for (bytes, 0..) |*byte, index| {
            const value = try storage.readOwner(resource.owner, index);
            defer value.release(allocator);
            byte.* = std.math.cast(u8, try value.asInteger()) orelse return error.InternalError;
        }
        if (op.document) return parseDocument(allocator, storage, authority, output, bytes, traversal);
        var document = try json.Document.parse(allocator, bytes, budget.limits);
        defer document.deinit();
        return document.decodeWithCodecs(allocator, execution, output, budget, &location);
    }
    const bytes = try json.encodeWithCodecs(allocator, execution, op.input, input, budget, &location);
    defer allocator.free(bytes);
    byte_work.* = bytes.len;
    const values = try allocator.alloc(typed.Value, bytes.len);
    defer allocator.free(values);
    for (bytes, values) |byte, *value| value.* = typed.Value.number(.u8, byte);
    const owner = try storage.createAuthorized(authority.capability.allocator, .u8, values, values.len);
    errdefer storage.destroy(owner) catch |err| std.debug.panic("JSON buffer cleanup: {s}", .{@errorName(err)});
    return typed.Value.ownBuffer(allocator, output, storage, owner);
}

/// Materialize the generic tape under the caller's allocator, without a second Value array.
fn parseDocument(allocator: std.mem.Allocator, storage: *memory.Store, authority: typed.Value, output: typed.Type, bytes: []const u8, traversal: *Traversal) !typed.Value {
    const words = try @import("json_document.zig").parse(allocator, bytes);
    defer allocator.free(words);
    traversal.bytes += words.len;
    const owner = try storage.createAuthorized(authority.capability.allocator, .i64, &.{}, words.len);
    errdefer storage.destroy(owner) catch |err| std.debug.panic("JSON document cleanup: {s}", .{@errorName(err)});
    try storage.resizeWithinCapacity(owner, words.len, .{ .i64 = 0 });
    for (words, 0..) |word, index| try storage.writeOwner(owner, index, .{ .i64 = word });
    return typed.Value.ownBuffer(allocator, output, storage, owner);
}
