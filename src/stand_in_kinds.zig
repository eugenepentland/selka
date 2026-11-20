//! The kind of stand-in a concrete type argument corresponds to (W3), for the judgment of generic bodies at their declaration
//! (`diagnostic.Probes.declaration`) and for the developer count: sema names the kind of an instance whose own check failed,
//! and Core names the kinds of the instances the ownership pass refused.
const std = @import("std");
const typed = @import("typed.zig");
const stand_ins = @import("template_stand_ins.zig");

/// The kind of `ty`: a scalar or a record of scalars is `int`, `str` is `text`, a list is `list`, a resource or a record holding
/// one is `move_only`, and any other managed type (a record, a dictionary, a set, an option, bytes) is `record`.
pub fn of(ty: typed.Type, records: []const typed.Record) stand_ins.Kind {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return .int;
    const record = records[ty.recordIndex()];
    if (record.contract.move_only) return .move_only;
    if (record.isCollection() and record.collection.kind == .string) return .text;
    if (record.isCollection() and record.collection.kind == .list and !record.collection.set) return .list;
    if (record.managed or holdsManaged(record, records, 4)) return .record;
    return .int;
}

/// Whether a record (a tuple included, which carries no `managed` mark of its own) has a field of a managed type.
fn holdsManaged(record: typed.Record, records: []const typed.Record, depth: usize) bool {
    if (depth == 0) return true;
    for (record.fields) |field| {
        if (!field.ty.isAggregate() or field.ty.recordIndex() >= records.len) continue;
        const inner = records[field.ty.recordIndex()];
        if (inner.managed or inner.isCollection() or holdsManaged(inner, records, depth - 1)) return true;
    }
    return false;
}

/// The digest of a template declaration's text as its judgment reads it: its tokens with the spacing inside each line, without
/// comments, blank lines and the line numbers between tokens (`token_digest.digest`). Null when the lexer refuses the text alone.
pub fn tokenDigest(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error!?[32]u8 {
    return @import("token_digest.zig").digest(allocator, bytes, "selka-template-judgment-tokens-v1");
}

/// One stand-in instance's refusing condition (`template_stand_ins.Condition`): the type parameters given a managed kind and
/// that kind, or every parameter and `int` for the instance whose arguments are all scalars.
pub fn condition(arguments: []const typed.Type, records: []const typed.Record) struct { parameters: u16, kind: stand_ins.Kind } {
    var parameters: u16 = 0;
    var kind: stand_ins.Kind = .int;
    for (arguments, 0..) |argument, position| {
        const found = of(argument, records);
        if (found == .int or position >= 16) continue;
        parameters |= @as(u16, 1) << @intCast(position);
        kind = found;
    }
    if (parameters == 0) {
        for (0..@min(arguments.len, 16)) |position| parameters |= @as(u16, 1) << @intCast(position);
    }
    return .{ .parameters = parameters, .kind = kind };
}

test "W3 a stand-in instance's condition names the managed parameters, or all of them for int" {
    const all_int = condition(&.{ .i64, .i64 }, &.{});
    try std.testing.expectEqual(@as(u16, 0b11), all_int.parameters);
    try std.testing.expectEqual(stand_ins.Kind.int, all_int.kind);
    try std.testing.expectEqual(stand_ins.Kind.int, of(.bool, &.{}));
}
