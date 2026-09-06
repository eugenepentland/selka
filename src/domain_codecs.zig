//! Resolve explicit domain codec contracts after complete body/effect checking.
const signature_error = "E_CODEC_SIGNATURE";
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
fn ordinary(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type, span: source.Span, sink: *diagnostic.Sink) diagnostic.Error!void {
    @import("data_type.zig").check(allocator, records, ty, false) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return sink.fail("E_CODEC_DATA", span, "codec wire and error types must have a complete ordinary representation without domains, capabilities, or runtime owners");
    };
}
fn method(
    allocator: std.mem.Allocator,
    src: source.Source,
    record: typed.Record,
    name: source.Span,
    functions: Functions,
    sink: *diagnostic.Sink,
) diagnostic.Error!typed.Function {
    const qualified = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ record.name, src.text(name) });
    defer allocator.free(qualified);
    const id = functions.names.get(qualified) orelse return sink.fail("E_CODEC_FUNCTION", name, "codec must name a method declared in this domain");
    const function = functions.items[@backingInt(id)];
    if (function.policy.owner != record.id or function.policy.restricted) return sink.failRelated("E_CODEC_PRIVATE", name, "codec methods must be public methods of their domain", .{
        .span = function.declaration,
        .message = "method declared here",
    });
    if (function.policy.effects != 0) return sink.failRelated("E_CODEC_EFFECT", name, "codec methods must be effect-free, including all transitive calls", .{ .span = function.declaration, .message = "effectful method declared here" });
    if (function.signature.parameter_count != 1 or function.signature.return_reference != null or function.scope.locals[0].parameter.reference_parameter != null) {
        return sink.failRelated(signature_error, name, "codec methods require exactly one value parameter and a value result", .{
            .span = function.declaration,
            .message = "method declared here",
        });
    }
    return function;
}
/// Validate explicit domain codec signatures, wire/error data graphs, and effect-free implementations.
pub fn check(
    allocator: std.mem.Allocator,
    src: source.Source,
    domains: []const ast.Domain,
    catalog: @import("records.zig").Catalog,
    functions: Functions,
    sink: *diagnostic.Sink,
) diagnostic.Error!void {
    for (domains) |domain| {
        const declaration = domain.codec orelse continue;
        const ty = try catalog.resolve(src, domain.name, sink);
        const record = &catalog.records[ty.recordIndex()];
        const wire = try catalog.resolve(src, declaration.wire, sink);
        try ordinary(allocator, catalog.records, wire, declaration.wire, sink);
        const decode = try method(allocator, src, record.*, declaration.decode, functions, sink);
        const encode = try method(allocator, src, record.*, declaration.encode, functions, sink);
        const shape = typed.resultShape(decode.signature.return_type, catalog.records) orelse return sink.fail(signature_error, declaration.decode, "decoder must return a typed result with this domain as its ok payload");
        if (decode.scope.locals[0].ty != wire or shape.ok_type != ty) return sink.fail(signature_error, declaration.decode, "decoder must accept the declared wire type and return this domain in its ok payload");
        if (encode.scope.locals[0].ty != ty or encode.signature.return_type != wire) return sink.fail(signature_error, declaration.encode, "encoder must accept this domain and return the declared wire type");
        try ordinary(allocator, catalog.records, shape.error_type, declaration.decode, sink);
        record.contract.codec = .{ .wire = wire, .decode = decode.id, .encode = encode.id };
    }
}

/// Checked callable declarations and the resolved method-name index.
pub const Functions = struct { items: []const typed.Function, names: std.StringHashMapUnmanaged(typed.FunctionId) };
