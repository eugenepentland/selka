//! Checked source JSON operations share the public typed-json-v1 wire contract.
const std = @import("std");
const typed = @import("typed.zig");
/// Identify a reserved unqualified source operation; true selects decoding.
pub fn operation(name: []const u8) ?bool {
    if (std.mem.eql(u8, name, "json_encode")) return false;
    if (std.mem.eql(u8, name, "json_decode") or isDocument(name)) return true;
    return null;
}
/// Closed codec promise used by concrete calls and symbolic generic requirements.
/// Domain declarations are validated fully after their method bodies are checked.
pub fn supportsCodec(ty: typed.Type, records: []const typed.Record) bool {
    var work: usize = 65536;
    return supports(ty, records, 0, &work);
}
fn supports(ty: typed.Type, records: []const typed.Record, depth: usize, work: *usize) bool {
    if (work.* == 0) return false;
    work.* -= 1;
    if (ty.isInteger() or ty == .bool) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len or depth > 128) return false;
    const record = records[ty.recordIndex()];
    if (record.shape.hasRuntimeIdentity() or record.contract.move_only) return false;
    if (record.shape.domain != null) return record.contract.codec_declared or record.contract.codec != null;
    if (record.shape.array) |array| return supports(array.element, records, depth + 1, work);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (!supports(payload, records, depth + 1, work)) return false;
    } else for (record.fields) |field| if (!supports(field.ty, records, depth + 1, work)) return false;
    return true;
}
/// Owned byte buffers are the explicit input/output boundary, never raw pointers.
pub fn byteBuffer(ty: typed.Type, records: []const typed.Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].shape.buffer == .u8;
}

/// Plain JSON documents use a generic tape of i64 words.
pub fn wordBuffer(ty: typed.Type, records: []const typed.Record) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].shape.buffer == .i64;
}
/// Plain parsing deliberately does not use the typed-json-v1 envelope.
pub fn isDocument(name: []const u8) bool {
    return std.mem.eql(u8, name, "json_parse");
}
