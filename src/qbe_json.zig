//! Stable typed-JSON entry helpers around the normative native codec bridge.
const std = @import("std");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const bytecode = @import("bytecode_model.zig");
const descriptors = @import("native_descriptors.zig");
/// Failures allocating or rendering checked native JSON metadata.
pub const Error = native.Error || error{WriteFailed};
/// One typed JSON helper with a stable semantic type symbol.
pub const Operation = struct { symbol: []const u8, type: []const u8, index: usize, decode: bool };
/// Direct compiled domain-method signature for boundary conversion.
pub const Callback = struct { index: usize, symbol: []const u8, input: []const u8, output: []const u8 };
/// Compiler-owned codec shapes and the helpers required by this program.
pub const Metadata = struct { schema: []const u8, operations: []const Operation, byte_descriptor: []const u8, word_descriptor: []const u8, document: bool, types: []const @import("qbe_wire.zig").Type, callbacks: []const Callback };

/// Emit only the helpers used by checked JSON expressions, with stable symbols.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, catalog: *native.Catalog) Error!?Metadata {
    var operations: std.ArrayList(Operation) = .empty;
    var document = false;
    for (program.functions) |function| for (function.scope.instructions) |instruction| {
        if (instruction.op != .json_codec) continue;
        const operation = instruction.op.json_codec;
        if (operation.document) {
            document = true;
            continue;
        }
        const shape = typed.resultShape(operation.output, program.records) orelse return error.InvalidType;
        const ty = if (operation.decode) shape.ok_type else operation.input;
        const symbol = try std.fmt.allocPrint(allocator, "{s}_json_{s}", .{ try descriptors.symbol(allocator, catalog, ty), if (operation.decode) "decode" else "encode" });
        var duplicate = false;
        for (operations.items) |existing| if (std.mem.eql(u8, existing.symbol, symbol)) {
            duplicate = true;
            break;
        };
        if (!duplicate) try operations.append(allocator, .{ .symbol = symbol, .type = typed.typeName(ty, program.records), .index = @backingInt(ty), .decode = operation.decode });
    };
    if (operations.items.len == 0 and !document) return null;
    var callbacks: std.ArrayList(Callback) = .empty;
    for (program.records) |record| if (record.contract.codec) |codec| {
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
    var schema: std.Io.Writer.Allocating = .init(allocator);
    try @import("native_json_schema.zig").emit(&schema.writer, program);
    return .{
        .document = document,
        .word_descriptor = try descriptors.symbol(allocator, catalog, .i64),
        .types = try @import("qbe_wire.zig").describeWithDomains(allocator, catalog, true),
        .callbacks = try callbacks.toOwnedSlice(allocator),
        .schema = try schema.toOwnedSlice(),
        .operations = try operations.toOwnedSlice(allocator),
        .byte_descriptor = try descriptors.symbol(allocator, catalog, .u8),
    };
}

test "JSON metadata rejects InvalidType in a forged codec result" {
    const allocator = std.testing.allocator;
    var catalog = try native.Catalog.initRecords(allocator, &.{});
    defer catalog.deinit();
    const instructions = [_]bytecode.Instruction{.{ .span = .{ .start = 0, .end = 0 }, .op = .{ .json_codec = .{ .decode = false, .input = .i64, .output = .i64 } } }};
    const functions = [_]bytecode.Function{.{ .id = @fromBackingInt(0), .name = "bad", .scope = .{ .instructions = &instructions } }};
    try std.testing.expectError(error.InvalidType, describe(allocator, .{ .functions = &functions }, &catalog));
}
