//! Constant mutable lists share an immortal image until a proved write detaches.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const values = @import("value_semantics.zig");
/// Failures validating, naming and emitting a primitive list image.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const MakeRecord = @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record");

/// Emit one packed image load, preserving eager fresh allocations in legacy
/// sharing through a single native clone rather than element append glue.
pub fn emit(comptime E: type, self: *E, record: MakeRecord, element: typed.Type, base: usize) Error!bool {
    if (record.payload.len == 0) return false;
    const width = @import("constant_list.zig").width(self.program.records, element) orelse return false;
    if ((try self.layout(element)).size != width or record.payload.len % width != 0) return error.InternalError;
    const descriptor = try self.descriptor(element);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mutable-list\x00");
    hash.update(descriptor);
    hash.update(&.{0});
    hash.update(record.payload);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    var name: [73]u8 = undefined;
    const symbol = std.fmt.bufPrint(&name, "myl_list_{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch return error.InternalError;
    const result = self.temp();
    try self.print(" %v{d} =l loadl ${s}\n# myl-lit {s} {s} {d} {d} {x} list\n", .{ result, symbol, symbol, descriptor, width, record.payload.len / width, record.payload });
    if (!values.enabled()) {
        const fresh = self.temp();
        try self.print(" %v{d} =l call $myl_native_list_literal_copy(l %heap, l %v{d})\n", .{ fresh, result });
        try self.require(fresh, @import("qbe_format.zig").allocation_failure);
        try self.store(base, fresh);
    } else try self.store(base, result);
    return true;
}
