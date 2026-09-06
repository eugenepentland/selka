//! Resolve explicit domain codec contracts after complete body/effect checking.
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
fn method(allocator: std.mem.Allocator, src: source.Source, record: typed.Record, name: source.Span, functions: []const typed.Function, names: std.StringHashMapUnmanaged(typed.FunctionId), sink: *diagnostic.Sink) diagnostic.Error!typed.Function {
    const qualified = try std.fmt.allocPrint(allocator, "{s}.{s}", .{ record.name, src.text(name) });
    defer allocator.free(qualified);
    const id = names.get(qualified) orelse return sink.fail("E_CODEC_FUNCTION", name, "codec must name a method declared in this domain");
    const function = functions[@backingInt(id)];
    if (function.owner != record.id or function.restricted) return sink.failRelated("E_CODEC_PRIVATE", name, "codec methods must be public methods of their domain", .{ .span = function.declaration, .message = "method declared here" });
    if (function.effects != 0) return sink.failRelated("E_CODEC_EFFECT", name, "codec methods must be effect-free, including all transitive calls", .{ .span = function.declaration, .message = "effectful method declared here" });
    if (function.parameter_count != 1 or function.return_reference != null or function.locals[0].reference_parameter != null) return sink.failRelated("E_CODEC_SIGNATURE", name, "codec methods require exactly one value parameter and a value result", .{ .span = function.declaration, .message = "method declared here" });
    return function;
}
pub fn check(allocator: std.mem.Allocator, src: source.Source, domains: []const ast.Domain, catalog: @import("records.zig").Catalog, functions: []const typed.Function, names: std.StringHashMapUnmanaged(typed.FunctionId), sink: *diagnostic.Sink) diagnostic.Error!void {
    for (domains) |domain| {
        const declaration = domain.codec orelse continue;
        const ty = try catalog.resolve(src, domain.name, sink);
        const record = &catalog.records[ty.recordIndex()];
        const wire = try catalog.resolve(src, declaration.wire, sink);
        try ordinary(allocator, catalog.records, wire, declaration.wire, sink);
        const decode = try method(allocator, src, record.*, declaration.decode, functions, names, sink);
        const encode = try method(allocator, src, record.*, declaration.encode, functions, names, sink);
        const shape = typed.resultShape(decode.return_type, catalog.records) orelse return sink.fail("E_CODEC_SIGNATURE", declaration.decode, "decoder must return a typed result with this domain as its ok payload");
        if (decode.locals[0].ty != wire or shape.ok_type != ty) return sink.fail("E_CODEC_SIGNATURE", declaration.decode, "decoder must accept the declared wire type and return this domain in its ok payload");
        if (encode.locals[0].ty != ty or encode.return_type != wire) return sink.fail("E_CODEC_SIGNATURE", declaration.encode, "encoder must accept this domain and return the declared wire type");
        try ordinary(allocator, catalog.records, shape.error_type, declaration.decode, sink);
        record.codec = .{ .wire = wire, .decode = decode.id, .encode = encode.id };
    }
}
