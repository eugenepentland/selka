//! Checked domain conversion contracts for the copied native codec-call ABI.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const bytecode = @import("bytecode_model.zig");
/// Checked decode/encode methods and their declared rejection representation.
pub const Codec = struct { domain: []const u8, wire: []const u8, decode: usize, encode: usize, result: []const u8, ok: usize, err: usize, error_type: []const u8 };
/// Domain conversion shapes independent of source JSON expressions.
pub const Metadata = struct { types: []const @import("qbe_wire.zig").Type, codecs: []const Codec };

/// Derive metadata even when a project uses no source JSON expressions.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, catalog: *native.Catalog) native.Error!Metadata {
    var codecs: std.ArrayList(Codec) = .empty;
    for (program.records) |record| if (record.contract.codec) |codec| {
        const result = program.functions[@backingInt(codec.decode)].signature.return_type;
        const shape = typed.resultShape(result, program.records) orelse return error.InvalidType;
        try codecs.append(allocator, .{
            .domain = record.name,
            .wire = typed.typeName(codec.wire, program.records),
            .decode = @backingInt(codec.decode),
            .encode = @backingInt(codec.encode),
            .result = typed.typeName(result, program.records),
            .ok = shape.ok_tag,
            .err = shape.error_tag,
            .error_type = typed.typeName(shape.error_type, program.records),
        });
    };
    return .{ .types = try @import("qbe_wire.zig").describeWithDomains(allocator, catalog, true), .codecs = try codecs.toOwnedSlice(allocator) };
}
