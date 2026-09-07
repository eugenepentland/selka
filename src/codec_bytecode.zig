//! Revalidate codec callable identities at the executable boundary, including forged catalogs.
const std = @import("std");
const model = @import("bytecode_model.zig");
const typed = @import("typed.zig");
/// A codec must call public, effect-free value methods owned by its domain.
pub fn validate(allocator: std.mem.Allocator, program: model.Program) (std.mem.Allocator.Error || error{InternalError})!void {
    for (program.records) |record| if (record.contract.codec) |codec| {
        if (record.shape.domain == null) return error.InternalError;
        try ordinary(allocator, program.records, codec.wire);
        const decode = try method(program, record.id, codec.decode);
        const encode = try method(program, record.id, codec.encode);
        const shape = typed.resultShape(decode.signature.return_type, program.records) orelse return error.InternalError;
        if (decode.scope.locals[0].ty != codec.wire or shape.ok_type != record.id) return error.InternalError;
        if (encode.scope.locals[0].ty != record.id or encode.signature.return_type != codec.wire) return error.InternalError;
        try ordinary(allocator, program.records, shape.error_type);
    };
}
fn method(program: model.Program, owner: typed.Type, id: typed.FunctionId) error{InternalError}!model.Function {
    if (@backingInt(id) >= program.functions.len) return error.InternalError;
    const function = program.functions[@backingInt(id)];
    if (function.policy.owner != owner or function.policy.restricted or function.policy.host != null or function.policy.effects != 0) return error.InternalError;
    if (function.signature.parameter_count != 1 or function.scope.locals.len == 0 or function.signature.return_reference != null or function.scope.locals[0].parameter.reference_parameter != null) return error.InternalError;
    return function;
}
fn ordinary(allocator: std.mem.Allocator, records: []const typed.Record, ty: typed.Type) (std.mem.Allocator.Error || error{InternalError})!void {
    @import("data_type.zig").check(allocator, records, ty, false) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InternalError,
    };
}

/// Verify JSON opcode result and wire types before any runtime value access.
pub fn operation(
    allocator: std.mem.Allocator,
    program: model.Program,
    codec: @FieldType(@FieldType(model.Instruction, "op"), "json_codec"),
) (std.mem.Allocator.Error || error{InternalError})!void {
    const shape = typed.resultShape(codec.output, program.records) orelse return error.InternalError;
    if (shape.error_type != .i64) return error.InternalError;
    if (!@import("source_json.zig").byteBuffer(if (codec.decode) codec.input else shape.ok_type, program.records)) return error.InternalError;
    if (codec.document) {
        if (!codec.decode or !@import("source_json.zig").wordBuffer(shape.ok_type, program.records)) return error.InternalError;
        return;
    }
    @import("data_type.zig").checkCodecs(allocator, program.records, if (codec.decode) shape.ok_type else codec.input) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
