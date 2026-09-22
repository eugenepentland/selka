//! Bind source-ordered positional and keyword operands to declared parameters.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const eArgument = "E_CALL_ARGUMENT";
pub const Call = @FieldType(@FieldType(ast.Node, "data"), "call");

/// Normalize argument positions while retaining their source evaluation order.
/// Scalar literal defaults are appended after explicitly supplied expressions.
pub fn bind(allocator: std.mem.Allocator, src: source.Source, call: Call, parameters: []const ast.Parameter, sink: *diagnostic.Sink) diagnostic.Error!Call {
    if (call.argument_names.len == 0 and call.arguments.len == parameters.len) return call;
    if (call.arguments.len > parameters.len) {
        const message = try std.fmt.allocPrint(allocator, "too many arguments for this function: expected {d}, given {d}", .{ parameters.len, call.arguments.len });
        return sink.fail("E_ARITY", call.name, message);
    }
    const values = try allocator.alloc(ast.NodeId, parameters.len);
    errdefer allocator.free(values);
    const order = try allocator.alloc(usize, parameters.len);
    errdefer allocator.free(order);
    const filled = try allocator.alloc(bool, parameters.len);
    defer allocator.free(filled);
    @memset(filled, false);
    for (call.arguments, 0..) |value, source_index| {
        const name = if (call.argument_names.len == 0) null else call.argument_names[source_index];
        const target = if (name) |keyword| try parameterIndex(src, parameters, keyword, sink) else source_index;
        if (filled[target]) return sink.fail(eArgument, name orelse call.name, "parameter receives more than one argument");
        filled[target] = true;
        values[target] = value;
        order[source_index] = target;
    }
    var next = call.arguments.len;
    for (parameters, 0..) |parameter, index| if (!filled[index]) {
        const default = parameter.default_value orelse {
            const message = try std.fmt.allocPrint(allocator, "missing required argument: expected {d}, given {d}", .{ parameters.len, call.arguments.len });
            return sink.fail("E_ARITY", call.name, message);
        };
        values[index] = default;
        order[next] = index;
        next += 1;
    };
    var out = call;
    out.arguments = values;
    out.argument_names = &.{};
    out.evaluation_order = order;
    return out;
}
fn parameterIndex(src: source.Source, parameters: []const ast.Parameter, name: source.Span, sink: *diagnostic.Sink) diagnostic.Error!usize {
    for (parameters, 0..) |parameter, index| if (std.mem.eql(u8, src.text(parameter.name), src.text(name))) return index;
    return sink.fail(eArgument, name, "keyword names no parameter of this function");
}
/// Map source-order indices to parameter-order indices after binding.
pub fn parameterPosition(call: Call, source_index: usize) usize {
    return if (call.evaluation_order.len == 0) source_index else call.evaluation_order[source_index];
}
/// Intrinsics and callback values have no source-declared keyword contract.
pub fn positional(call: Call, sink: *diagnostic.Sink) diagnostic.Error!void {
    if (call.argument_names.len != 0) return sink.fail(eArgument, call.name, "keyword arguments require a declared function or record constructor");
}

/// Release normalized buffers when binding uses a non-arena allocator.
pub fn release(allocator: std.mem.Allocator, original: Call, bound: Call) void {
    if (bound.arguments.ptr == original.arguments.ptr) return;
    allocator.free(bound.arguments);
    allocator.free(bound.evaluation_order);
}
