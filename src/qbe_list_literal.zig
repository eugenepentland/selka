//! Constant mutable lists share an immortal image until a proved write detaches.
const std = @import("std");
const typed = @import("typed.zig");
const bytecode = @import("bytecode.zig");
const values = @import("value_semantics.zig");
/// Failures validating, naming and emitting a constant list image.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
const MakeRecord = @FieldType(@FieldType(bytecode.Instruction, "op"), "make_record");

/// Emit one packed image evaluation. Legacy sharing and arena evaluations
/// create one regional clone rather than per-element append glue.
pub fn emit(comptime E: type, self: *E, record: MakeRecord, element: typed.Type, base: usize) Error!bool {
    if (record.payload.len == 0) return false;
    if (@import("constant_list_text.zig").family(self.program.records, element)) |text| {
        try managed(E, self, record.payload, element, text, base);
        return true;
    }
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
    try self.print("# myl-lit {s} {s} {d} {d} {x} list\n", .{ symbol, descriptor, width, record.payload.len / width, record.payload });
    try publish(E, self, base, symbol);
    return true;
}

fn publish(comptime E: type, self: *E, base: usize, symbol: []const u8) Error!void {
    const result = self.temp();
    try self.print(" %v{d} =l loadl ${s}\n", .{ result, symbol });
    const fresh = self.temp();
    const helper = if (values.enabled()) "myl_native_list_literal_value" else "myl_native_list_literal_copy";
    try self.print(" %v{d} =l call ${s}(l %heap, l %v{d})\n", .{ fresh, helper, result });
    try self.require(fresh, @import("qbe_format.zig").allocation_failure);
    try self.store(base, fresh);
}

fn managed(comptime E: type, self: *E, payload: []const u8, element: typed.Type, text: bool, base: usize) Error!void {
    const rows_api = @import("constant_list_text.zig");
    if (!rows_api.valid(payload, text)) return error.InternalError;
    const descriptor = try self.descriptor(element);
    const leaf = if (text) @import("qbe_embeds.zig").text_leaf else try self.descriptor(.u8);
    var rows = rows_api.Rows.init(payload) orelse return error.InternalError;
    const count = rows.remaining;
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("mutable-list\x00");
    hash.update(descriptor);
    hash.update(&.{0});
    hash.update(payload);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    var name: [73]u8 = undefined;
    const symbol = std.fmt.bufPrint(&name, "myl_list_{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch return error.InternalError;
    while (rows.next() catch return error.InternalError) |bytes| {
        var child: [72]u8 = undefined;
        try childSymbol(&child, leaf, bytes);
        if (text) {
            const scalars = std.unicode.utf8CountCodepoints(bytes) catch return error.InternalError;
            try self.print("# myl-lit {s} {s} 0 {d} {d} {d} {x}\n", .{ child, leaf, bytes.len, scalars, @intFromBool(scalars == bytes.len), bytes });
        } else try self.print("# myl-lit {s} {s} 1 {d} {x}\n", .{ child, leaf, bytes.len, bytes });
    }
    try self.print("# myl-list {s} {s} {d}", .{ symbol, descriptor, count });
    rows = rows_api.Rows.init(payload).?;
    while (rows.next() catch return error.InternalError) |bytes| {
        var child: [72]u8 = undefined;
        try childSymbol(&child, leaf, bytes);
        try self.print(" {s}", .{child});
    }
    try self.print("\n", .{});
    try publish(E, self, base, symbol);
}

fn childSymbol(out: *[72]u8, leaf: []const u8, payload: []const u8) Error!void {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update(leaf);
    hash.update(&.{0});
    hash.update(payload);
    var digest: [32]u8 = undefined;
    hash.final(&digest);
    _ = std.fmt.bufPrint(out, "myl_lit_{s}", .{std.fmt.bytesToHex(digest, .lower)}) catch return error.InternalError;
}
