//! Checked source JSON operations share the public typed-json-v1 wire contract.
const std = @import("std");
const typed = @import("typed.zig");
/// Identify a reserved unqualified source operation; true selects decoding.
pub fn operation(name: []const u8) ?bool {
    if (std.mem.eql(u8, name, "json_encode")) return false;
    if (std.mem.eql(u8, name, "json_decode") or isDocument(name)) return true;
    return null;
}
/// The `codec` promise: the type has a plain JSON form (`codec_form.zig`), which `json.encode` and `json.decode` derive.
pub fn supportsCodec(ty: typed.Type, records: []const typed.Record) bool {
    return @import("codec_form.zig").supports(ty, records);
}
/// Owned byte buffers are the explicit input/output boundary, never raw pointers.
pub fn byteBuffer(ty: typed.Type, records: []const typed.Record) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    if (records[ty.recordIndex()].managed) return false;
    return records[ty.recordIndex()].shape.buffer == .u8;
}

/// Plain parsing deliberately does not use the typed-json-v1 envelope.
pub fn isDocument(name: []const u8) bool {
    return std.mem.eql(u8, name, "json_parse");
}
