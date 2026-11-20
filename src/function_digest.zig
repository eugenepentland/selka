//! Checked admission for compiler-issued persistent callable implementation keys.
const typed = @import("typed.zig");
const source = @import("source.zig");
const callables = @import("callables.zig");

/// The builtin remains shadowable by ordinary declarations.
pub const name = "function_digest";
/// Noncallable arguments never acquire implementation identity.
pub const code = "E_FUNCTION_DIGEST";
/// Explain the callable-only boundary.
pub const message = "function_digest requires one function value";

/// Reuse checked scalar conversion storage without admitting ordinary str(function).
pub fn check(comptime Checker: type, checker: *Checker, span: source.Span, arguments: []const typed.NodeId) @import("diagnostic.zig").Error!typed.Node {
    if (arguments.len != 1) return checker.sink.fail("E_ARITY", span, message);
    const operand = arguments[0];
    if (callables.signature(checker.nodes.items[@backingInt(operand)].ty, checker.catalog.records) == null)
        return checker.sink.fail(code, span, message);
    return .{ .span = span, .ty = checker.catalog.names.get("str") orelse return error.InternalError, .data = .{ .cast = operand } };
}

/// Canonical checked schema and callback ceiling, independent of catalog ordinals.
pub fn schema(a: @import("std").mem.Allocator, program: typed.Program, ty: typed.Type) @import("schema_graph.zig").RenderError![]u8 {
    const graph = try @import("schema_graph.zig").renderType(a, program, ty);
    const callback = callables.signature(ty, program.records) orelse return error.InvalidCheckedType;
    return @import("std").json.Stringify.valueAlloc(a, .{ .graph = graph, .labels = callback.labels, .origin = callback.return_origin }, .{});
}
