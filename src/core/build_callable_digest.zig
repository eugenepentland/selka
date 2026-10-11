//! Source-schema-bound lowering declarations for persistent callable identity.
const std = @import("std");
const ir = @import("ir.zig");
const language = @import("mylang");
const prefix = @import("callable_digest_contract.zig").prefix;
/// Lower checked callback conversion into a signature-specific compiler declaration.
pub fn lower(b: anytype, operand_node: language.typed.NodeId, operand: ir.Ref, span: u32) error{ OutOfMemory, Unsupported }!ir.Ref {
    const program = b.mb.input.program;
    const schema = language.callable_identity.schema(b.allocator(), program, b.nodeOf(operand_node).ty) catch |err| {
        if (err == error.OutOfMemory) return error.OutOfMemory;
        return error.Unsupported;
    };
    var hash: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(schema, &hash, .{});
    const symbol = try std.fmt.allocPrint(b.allocator(), "{s}{s}", .{ prefix, std.fmt.bytesToHex(hash, .lower) });
    return b.effectCall(symbol, &.{b.typeOfRef(operand)}, .str, &.{operand}, span);
}
