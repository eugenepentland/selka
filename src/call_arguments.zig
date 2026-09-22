//! Bind source-ordered positional and keyword operands to declared parameters.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const eArgument = "E_CALL_ARGUMENT";
/// A keyword-only parameter reached by a positional operand; the message prints
/// the whole call with every keyword-only operand passed by name.
const eKeywordOnly = "E_KEYWORD_ONLY";
pub const Call = @FieldType(@FieldType(ast.Node, "data"), "call");

/// One call, the declared signature its operands bind to, and the parsed operand
/// nodes the repaired-call renderer reads source text from.
const Binding = struct {
    call: Call,
    signature: ast.FunctionSignature,
    syntax: []const ast.Node,
};

/// Normalize argument positions while retaining their source evaluation order.
/// Scalar literal defaults are appended after explicitly supplied expressions.
/// A positional operand that would land on the signature's first keyword-only
/// parameter, or a later one, is `E_KEYWORD_ONLY` instead of a binding.
pub fn bind(allocator: std.mem.Allocator, src: source.Source, syntax: []const ast.Node, call: Call, signature: ast.FunctionSignature, sink: *diagnostic.Sink) diagnostic.Error!Call {
    const parameters = signature.parameters;
    const binding: Binding = .{ .call = call, .signature = signature, .syntax = syntax };
    if (call.argument_names.len == 0 and call.arguments.len == parameters.len and (signature.keyword_only_from == null or call.arguments.len <= signature.keyword_only_from.?)) return call;
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
        const target = if (name) |keyword| try parameterIndex(src, parameters, keyword, sink) else try positionalTarget(allocator, src, binding, source_index, sink);
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
/// The parameter one positional operand binds to, or `E_KEYWORD_ONLY` when the
/// declaration makes that parameter keyword-only. The rejection names the
/// parameter and prints the whole call as it must be written.
fn positionalTarget(allocator: std.mem.Allocator, src: source.Source, binding: Binding, source_index: usize, sink: *diagnostic.Sink) diagnostic.Error!usize {
    const boundary = binding.signature.keyword_only_from orelse return source_index;
    if (source_index < boundary) return source_index;
    const names = try parameterNames(allocator, src, binding.signature.parameters);
    const message = try std.fmt.allocPrint(allocator, "`{s}` is keyword-only; write `{s}`", .{ names[source_index], try render(allocator, src, binding.syntax, binding.call, names, boundary) });
    return sink.fail(eKeywordOnly, binding.call.name, message);
}
/// The declared parameter names in source order, for the shared call renderer.
pub fn parameterNames(allocator: std.mem.Allocator, src: source.Source, parameters: []const ast.Parameter) std.mem.Allocator.Error![]const []const u8 {
    const names = try allocator.alloc([]const u8, parameters.len);
    for (parameters, names) |parameter, *name| name.* = src.text(parameter.name);
    return names;
}
/// Render one call exactly as it must be written: the callee as the call site
/// spells it, then every operand in source order, with each operand from
/// `named_from` on written `name=value` beside the parameter its own position
/// binds to. An operand the call site already named keeps the name it spells.
/// Every call-site rejection and lint that prints a repaired call goes through
/// this one renderer, so the paste and the message can never disagree.
pub fn render(allocator: std.mem.Allocator, src: source.Source, syntax: []const ast.Node, call: Call, names: []const []const u8, named_from: usize) std.mem.Allocator.Error![]const u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(allocator);
    try out.appendSlice(allocator, calleeText(src, call));
    try out.append(allocator, '(');
    for (call.arguments, 0..) |value, source_index| {
        if (source_index != 0) try out.appendSlice(allocator, ", ");
        const written = if (call.argument_names.len == 0) null else call.argument_names[source_index];
        const parameter = if (source_index < names.len) names[source_index] else null;
        if (written) |keyword| {
            try out.appendSlice(allocator, src.text(keyword));
            try out.append(allocator, '=');
        } else if (source_index >= named_from) if (parameter) |name| {
            try out.appendSlice(allocator, name);
            try out.append(allocator, '=');
        };
        try out.appendSlice(allocator, src.text(syntax[@backingInt(value)].span));
    }
    try out.append(allocator, ')');
    return out.toOwnedSlice(allocator);
}
/// The callee as the call site spells it: `io.issue`, `open`, or a member name
/// joined to its receiver.
pub fn calleeText(src: source.Source, call: Call) []const u8 {
    const owner = call.owner orelse return src.text(call.name);
    return src.text(source.Span.join(owner, call.name));
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
