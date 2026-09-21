//! Checked domain conversion contracts for the copied native codec-call ABI.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const bytecode = @import("bytecode_model.zig");
/// Checked decode/encode methods and their declared rejection representation.
pub const Codec = struct { domain: []const u8, wire: []const u8, decode: usize, encode: usize, result: []const u8, ok: usize, err: usize, error_type: []const u8 };
/// One compiled codec method the native runtime calls by its exported symbol.
pub const Callback = struct { index: usize, symbol: []const u8, input: []const u8, output: []const u8 };
/// Domain conversion shapes, the native descriptor symbol of each manifest
/// entry, and the compiled methods that implement them. `descriptors` is
/// positionally parallel to `types`: the generated adapter hands the runtime the
/// exact `myl_native_type` the program already publishes for that type, rather
/// than synthesizing a second descriptor that could drift from the collector's.
pub const Metadata = struct {
    types: []const @import("qbe_wire.zig").Type,
    descriptors: []const []const u8,
    codecs: []const Codec,
    callbacks: []const Callback,
};

/// Derive metadata for every declared domain codec in the program.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, catalog: *native.Catalog) native.Error!Metadata {
    var codecs: std.ArrayList(Codec) = .empty;
    var callbacks: std.ArrayList(Callback) = .empty;
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
        for ([_]typed.FunctionId{ codec.decode, codec.encode }) |id| {
            const function = program.functions[@backingInt(id)];
            var digest: [32]u8 = undefined;
            std.crypto.hash.sha2.Sha256.hash(function.name, &digest, .{});
            try callbacks.append(allocator, .{
                .index = @backingInt(id),
                .symbol = try std.fmt.allocPrint(allocator, "myl_f_{s}", .{std.fmt.bytesToHex(digest, .lower)}),
                .input = typed.typeName(function.scope.locals[0].ty, program.records),
                .output = typed.typeName(function.signature.return_type, program.records),
            });
        }
    };
    const table = try @import("qbe_wire.zig").describeWithDomains(allocator, catalog, true);
    const descriptors = try allocator.alloc([]const u8, table.types.len);
    for (table.ids, descriptors) |id, *slot| slot.* = try @import("native_descriptors.zig").symbol(allocator, catalog, id);
    return .{
        .types = table.types,
        .descriptors = descriptors,
        .codecs = try codecs.toOwnedSlice(allocator),
        .callbacks = try callbacks.toOwnedSlice(allocator),
    };
}
