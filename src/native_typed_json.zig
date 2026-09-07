//! Typed native JSON uses the same checked codecs and bounded traversal as the VM.
const std = @import("std");
const typed = @import("typed.zig");
const json = @import("typed_json.zig");
const abi = @import("native_json_abi.zig");
const invocation = @import("invocation_contract.zig");
const Execution = @import("codec_execution.zig").Execution;
const Failure = @import("codec_execution.zig").Failure;
/// C ABI: copied input tree to canonical bytes. Caller owns successful output.
pub fn encode(memory: *const abi.NativeAllocator, request: *const abi.Request, input: *const abi.Input, output: *abi.Output) callconv(.c) c_int {
    return convert(memory.allocator(), request, input, output, false);
}
/// C ABI: typed bytes to copied output tree. Caller owns successful output.
pub fn decode(memory: *const abi.NativeAllocator, request: *const abi.Request, input: *const abi.Input, output: *abi.Output) callconv(.c) c_int {
    return convert(memory.allocator(), request, input, output, true);
}
fn convert(allocator: std.mem.Allocator, request: *const abi.Request, input: *const abi.Input, output: *abi.Output, decoding: bool) c_int {
    output.* = .{};
    if (request.limit == 0 or request.limit > 1048576) return 4;
    var metadata = std.heap.ArenaAllocator.init(allocator);
    defer metadata.deinit();
    const records = catalog(metadata.allocator(), request) catch return -1;
    const ty: typed.Type = @fromBackingInt(@intCast(request.ty));
    var bounded: @import("codec_memory.zig").Memory = .{ .parent = allocator, .limit = 32 * 1024 * 1024 };
    var budget: json.Budget = .{ .limits = .{ .max_bytes = request.limit } };
    var failure: Failure = .{};
    defer failure.deinit(bounded.allocator());
    var execution: Execution = .{
        .backend = .{ .program = .{ .records = records, .functions = &.{}, .main = @fromBackingInt(0) }, .dispatch = unavailable },
        .max_steps = std.math.maxInt(u64),
        .max_frames = 1024,
        .max_calls = 256,
        .arguments = .{},
        .failure = &failure,
    };
    const result = operation(.{ .allocator = allocator, .scratch = bounded.allocator(), .records = records, .ty = ty, .execution = &execution, .budget = &budget }, input, decoding, output) catch |err| {
        output.work += budget.values;
        return switch (err) {
            error.OutOfMemory => if (bounded.limit_failure) 2 else -1,
            error.CodecByteLimit, error.CodecDepthLimit, error.CodecTokenLimit, error.CodecValueLimit, error.CodecWorkLimit, error.CodecCallLimit => 2,
            else => 1,
        };
    };
    output.data = result.data;
    output.count = result.count;
    output.work += budget.values;
    return 0;
}
const Operation = struct { allocator: std.mem.Allocator, scratch: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, execution: *Execution, budget: *json.Budget };
fn operation(context: Operation, input: *const abi.Input, decoding: bool, output: *abi.Output) !struct { data: *anyopaque, count: usize } {
    var location: json.Location = .{};
    if (decoding) {
        if (input.length > context.budget.limits.max_bytes) return error.CodecByteLimit;
        output.work = input.length;
        var document = try json.Document.parse(context.scratch, input.bytes.?[0..input.length], context.budget.limits);
        defer document.deinit();
        const value = try document.decodeWithCodecs(context.scratch, context.execution, context.ty, context.budget, &location);
        defer value.release(context.scratch);
        var nodes: std.ArrayList(abi.Node) = .empty;
        defer nodes.deinit(context.allocator);
        try writeNodes(context.allocator, context.records, context.ty, value, &nodes);
        const owned = try nodes.toOwnedSlice(context.allocator);
        return .{ .data = owned.ptr, .count = owned.len };
    }
    var cursor: usize = 0;
    const value = try readNodes(context.allocator, context.records, context.ty, input.nodes.?[0..input.count], &cursor);
    defer value.release(context.allocator);
    if (cursor != input.count) return error.InvalidDataValue;
    const bytes = try json.encodeWithCodecs(context.scratch, context.execution, context.ty, value, context.budget, &location);
    output.work = bytes.len;
    // The accounting wrapper forwards storage: caller can free it directly.
    return .{ .data = bytes.ptr, .count = bytes.len };
}
fn unavailable(_: std.mem.Allocator, _: @import("bytecode_model.zig").Program, _: typed.FunctionId, _: []const typed.Value, _: invocation.InvokeOptions) invocation.InvokeError!invocation.ValueResult {
    return error.InternalError;
}
fn catalog(allocator: std.mem.Allocator, request: *const abi.Request) ![]typed.Record {
    if (request.count < typed.Type.record_base or request.ty >= request.count) return error.InvalidDataValue;
    const records = try allocator.alloc(typed.Record, request.count - typed.Type.record_base);
    for (records, typed.Type.record_base..) |*record, index| {
        const schema = request.shapes[index];
        record.* = .{ .id = @fromBackingInt(@intCast(index)), .name = std.mem.span(schema.name), .declaration = .{ .start = 0, .end = 0 }, .fields = &.{} };
        if (schema.kind == 3) {
            record.shape.array = .{ .element = @fromBackingInt(@intCast(schema.children.?[0])), .length = schema.count, .key = if (schema.key == std.math.maxInt(usize)) null else @fromBackingInt(@intCast(schema.key)) };
        } else if (schema.kind == 4) {
            const cases = try allocator.alloc(typed.Variant, schema.count);
            for (cases, 0..) |*case, i| case.* = .{
                .name = std.mem.span(schema.names.?[i]),
                .declaration = .{ .start = 0, .end = 0 },
                .payload = if (schema.children.?[i] == std.math.maxInt(usize)) null else @fromBackingInt(@intCast(schema.children.?[i])),
            };
            record.shape.variants = .{ .cases = cases, .is_union = schema.flags & 1 != 0, .fallible = schema.flags & 2 != 0 };
        } else if (schema.kind == 2) {
            const fields = try allocator.alloc(typed.Field, schema.count);
            for (fields, 0..) |*field, i| field.* = .{ .name = std.mem.span(schema.names.?[i]), .declaration = .{ .start = 0, .end = 0 }, .ty = @fromBackingInt(@intCast(schema.children.?[i])) };
            record.fields = fields;
        } else {
            // Unreachable non-data types cannot be mistaken for empty records.
            record.contract.move_only = true;
        }
    }
    return records;
}
fn readNodes(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, nodes: []const abi.Node, cursor: *usize) anyerror!typed.Value {
    if (cursor.* == nodes.len) return error.InvalidDataValue;
    const node = nodes[cursor.*];
    cursor.* += 1;
    if (!std.mem.eql(u8, std.mem.span(node.name), typed.typeName(ty, records))) return error.ValueTypeMismatch;
    if (ty.isInteger()) {
        var number: i128 = node.bits;
        if (ty.integer().?.signed and node.bits >> 63 != 0) number -= @as(i128, 1) << 64;
        if (!ty.fits(number) or node.children != 0) return error.InvalidDataValue;
        return typed.Value.number(ty, number);
    }
    if (ty == .bool) {
        if (node.bits > 1 or node.children != 0) return error.InvalidDataValue;
        return .{ .bool = node.bits != 0 };
    }
    const record = records[ty.recordIndex()];
    if (record.shape.variants) |variants| {
        if (node.bits >= variants.cases.len) return error.InvalidDataValue;
        const tag: usize = @intCast(node.bits);
        if (variants.cases[tag].payload) |child| {
            if (node.children != 1) return error.InvalidDataValue;
            const value = try readNodes(allocator, records, child, nodes, cursor);
            defer value.release(allocator);
            return typed.Value.createVariant(allocator, ty, tag, value);
        }
        if (node.children != 0) return error.InvalidDataValue;
        return typed.Value.createVariant(allocator, ty, tag, null);
    }
    if (node.children != record.count() or node.bits != 0) return error.InvalidDataValue;
    const fields = try allocator.alloc(typed.Value, node.children);
    var initialized: usize = 0;
    defer {
        for (fields[0..initialized]) |value| value.release(allocator);
        allocator.free(fields);
    }
    for (fields, 0..) |*field, i| {
        field.* = try readNodes(allocator, records, record.elementType(i), nodes, cursor);
        initialized += 1;
    }
    return typed.Value.create(allocator, ty, fields);
}
fn writeNodes(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, value: typed.Value, nodes: *std.ArrayList(abi.Node)) anyerror!void {
    var node: abi.Node = .{ .name = @ptrCast(typed.typeName(ty, records).ptr), .bits = 0, .children = 0 };
    if (ty.isInteger()) {
        node.bits = @truncate(@as(u128, @bitCast(try value.asInteger())));
    } else if (ty == .bool) {
        node.bits = @intFromBool(value.bool);
    } else {
        node.children = value.aggregate.fields.len;
        if (value.aggregate.active_tag) |tag| node.bits = tag;
    }
    try nodes.append(allocator, node);
    if (!ty.isAggregate()) return;
    const record = records[ty.recordIndex()];
    for (value.aggregate.fields, 0..) |field, i| {
        const child = if (record.shape.variants) |variants| variants.cases[@intCast(node.bits)].payload.? else record.elementType(i);
        try writeNodes(allocator, records, child, field, nodes);
    }
}
// spec: NATIVE-JSON-2
test "typed native convert preserves canonical integers byte budgets and malformed errors" {
    const t = std.testing;
    var shapes: [typed.Type.record_base]abi.Shape = undefined;
    @memset(&shapes, .{ .name = "unused", .kind = 0, .count = 0, .children = null, .names = null, .key = std.math.maxInt(usize), .flags = 0 });
    var request: abi.Request = .{ .shapes = &shapes, .count = shapes.len, .ty = @backingInt(typed.Type.i64), .limit = 1024 };
    const nodes = [_]abi.Node{.{ .name = "i64", .bits = 42, .children = 0 }};
    var output: abi.Output = .{};
    try t.expectEqual(@as(c_int, 0), convert(t.allocator, &request, &.{ .nodes = &nodes, .count = nodes.len, .bytes = null, .length = 0 }, &output, false));
    const bytes = @as([*]u8, @ptrCast(output.data.?))[0..output.count];
    defer t.allocator.free(bytes);
    try t.expectEqualStrings("{\"version\":\"typed-json-v1\",\"type\":\"i64\",\"value\":\"42\"}", bytes);
    request.limit = 1;
    try t.expectEqual(@as(c_int, 2), convert(t.allocator, &request, &.{ .nodes = &nodes, .count = 1, .bytes = null, .length = 0 }, &output, false));
    request.limit = 1024;
    try t.expectEqual(@as(c_int, 1), convert(t.allocator, &request, &.{ .bytes = "{}", .length = 2, .nodes = null, .count = 0 }, &output, true));
}
// spec: NATIVE-JSON-4
test "typed native convert releases every allocation failure" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationScenario, .{});
}
fn allocationScenario(allocator: std.mem.Allocator) !void {
    var shapes: [typed.Type.record_base]abi.Shape = undefined;
    @memset(&shapes, .{ .name = "unused", .kind = 0, .count = 0, .children = null, .names = null, .key = std.math.maxInt(usize), .flags = 0 });
    const request: abi.Request = .{ .shapes = &shapes, .count = shapes.len, .ty = @backingInt(typed.Type.i64), .limit = 1024 };
    const nodes = [_]abi.Node{.{ .name = "i64", .bits = 42, .children = 0 }};
    var output: abi.Output = .{};
    const encoded = convert(allocator, &request, &.{ .nodes = &nodes, .count = 1, .bytes = null, .length = 0 }, &output, false);
    if (encoded == -1) return error.OutOfMemory;
    try std.testing.expectEqual(@as(c_int, 0), encoded);
    const bytes = @as([*]u8, @ptrCast(output.data.?))[0..output.count];
    defer allocator.free(bytes);
    const decoded = convert(allocator, &request, &.{ .bytes = bytes.ptr, .length = bytes.len, .nodes = null, .count = 0 }, &output, true);
    if (decoded == -1) return error.OutOfMemory;
    try std.testing.expectEqual(@as(c_int, 0), decoded);
    const values = @as([*]abi.Node, @ptrCast(@alignCast(output.data.?)))[0..output.count];
    defer allocator.free(values);
    try std.testing.expectEqual(@as(u64, 42), values[0].bits);
}
