//! Adapt checked domain signatures to synchronous compiled calls without linking a VM.
const std = @import("std");
const typed = @import("typed.zig");
const bc = @import("bytecode_model.zig");
const abi = @import("native_json_abi.zig");
const invocation = @import("invocation_contract.zig");
const values = @import("native_json_values.zig");
/// Reconstruct only compiler-owned checked method signatures for codec validation.
pub fn signatures(allocator: std.mem.Allocator, records: []typed.Record, execution: ?*const abi.Execution) std.mem.Allocator.Error![]const bc.Function {
    const context = execution orelse return &.{};
    var count: usize = 0;
    for (context.codecs[0..context.count]) |codec| count = @max(count, @max(codec.decode, codec.encode) + 1);
    const functions = try allocator.alloc(bc.Function, count);
    for (functions, 0..) |*function, i| function.* = .{ .id = @fromBackingInt(i), .name = "unused", .scope = .{ .instructions = &.{} } };
    for (context.codecs[0..context.count]) |codec| {
        const domain: typed.Type = @fromBackingInt(@intCast(codec.domain));
        const wire: typed.Type = @fromBackingInt(@intCast(codec.wire));
        records[domain.recordIndex()].contract.codec = .{ .wire = wire, .decode = @fromBackingInt(codec.decode), .encode = @fromBackingInt(codec.encode) };
        functions[codec.decode] = try method(allocator, codec.decode, domain, wire, @fromBackingInt(@intCast(codec.result)));
        functions[codec.encode] = try method(allocator, codec.encode, domain, domain, wire);
    }
    return functions;
}
fn method(allocator: std.mem.Allocator, id: usize, owner: typed.Type, input: typed.Type, output: typed.Type) !bc.Function {
    const locals = try allocator.alloc(typed.Local, 1);
    locals[0] = .{ .name = "input", .declaration = .{ .start = 0, .end = 0 }, .ty = input, .mutable = false };
    return .{ .id = @fromBackingInt(id), .name = "codec", .policy = .{ .owner = owner }, .signature = .{ .parameter_count = 1, .return_type = output }, .scope = .{ .locals = locals, .instructions = &.{} } };
}
/// Invoke native machine code using copied preorder values and operation-local limits.
pub fn dispatch(opaque_context: *anyopaque, allocator: std.mem.Allocator, program: bc.Program, id: typed.FunctionId, inputs: []const typed.Value, options: invocation.InvokeOptions) invocation.InvokeError!invocation.ValueResult {
    const context: *const abi.Execution = @ptrCast(@alignCast(opaque_context));
    if (options.max_frames == 0 or options.max_steps == 0) return error.InvalidBudget;
    if (inputs.len != 1) return error.InvocationArity;
    const function = program.functions[@backingInt(id)];
    var copier: @import("value_copy.zig").Copier = .{ .records = program.records, .limits = options.arguments };
    const input = try copier.copy(allocator, function.scope.locals[0].ty, inputs[0]);
    defer input.release(allocator);
    var nodes: std.ArrayList(abi.Node) = .empty;
    defer nodes.deinit(allocator);
    values.writeNodes(allocator, program.records, input.typeOf(), input, &nodes) catch return error.OutOfMemory;
    var output: abi.Output = .{};
    const call: abi.Call = .{
        .function = @backingInt(id),
        .input_type = @backingInt(input.typeOf()),
        .output_type = @backingInt(function.signature.return_type),
        .nodes = nodes.items.ptr,
        .count = nodes.items.len,
        .steps = options.max_steps,
        .frames = options.max_frames,
    };
    const status = context.invoke(&call, &output);
    if (options.steps_executed) |used| used.* = output.work;
    // C transfers malloc storage; decode it before releasing through the same C allocator.
    defer if (output.data) |data| context.release(data);
    if (status == -1) return error.OutOfMemory;
    if (status == -2) return error.InternalError;
    if (status == 4) return error.ValueCountLimit;
    if (status != 0) return .{ .trap = .{ .code = switch (status) {
        2 => "R_STEP_LIMIT",
        3 => "R_FRAME_LIMIT",
        else => "R_DOMAIN_CODEC",
    }, .span = .{ .start = 0, .end = 0 }, .message = "compiled domain codec trapped" } };
    var cursor: usize = 0;
    const copied: [*]const abi.Node = @ptrCast(@alignCast(output.data.?));
    return .{ .value = values.readNodes(allocator, program.records, function.signature.return_type, copied[0..output.count], &cursor) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError };
}
