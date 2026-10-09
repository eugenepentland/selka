//! PY-REPEAT-1: `sequence * count` and `count * sequence` for `str`, `bytes`
//! and `list[T]`, as Python repeats them.
//!
//! A repeated `str` or `bytes` gathers `count` references to the one operand and
//! joins them with the empty separator, so the result is built with one
//! exactly-sized allocation instead of a chain of growing prefixes. A repeated
//! list extends a fresh list by the operand `count` times, so its elements are
//! shared shallowly, as Python's are. A count of zero or less answers an empty
//! value. Both operands are evaluated once, left to right.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const collections = @import("collection_lower.zig");

/// The sequence kinds `*` repeats: text, immutable octets and lists.
pub fn repeatable(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate()) return false;
    const record = records[ty.recordIndex()];
    // A value record such as `float` has a collection kind field too; only a
    // managed collection is a sequence.
    if (!record.isCollection()) return false;
    return switch (record.collection.kind) {
        .string, .list => true,
        .bytes => !std.mem.eql(u8, record.name, "byte_buffer"),
        else => false,
    };
}

/// One checked repetition: the sequence operand, the count operand and which
/// of the two the source wrote first.
pub const Operands = struct { sequence: typed.NodeId, count: typed.NodeId, count_first: bool };

/// Build the checked value of one repetition through the checker's builder.
pub fn build(comptime Checker: type, checker: *Checker, span: source.Span, operands: Operands) diagnostic.Error!typed.Node {
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    const allocator = checker.allocator;
    const sequence_type = checker.nodes.items[@backingInt(operands.sequence)].ty;
    const kind = checker.catalog.records[sequence_type.recordIndex()].collection.kind;
    const sequence = try b.local(sequence_type);
    const count = try b.local(.i64);
    const count_value = if (checker.nodes.items[@backingInt(operands.count)].ty == .i64) operands.count else try b.node(.i64, .{ .cast = operands.count });
    const bind_sequence = try b.stmt(.{ .initialize = .{ .slot = sequence, .value = operands.sequence } });
    const bind_count = try b.stmt(.{ .initialize = .{ .slot = count, .value = count_value } });
    // A list gathers the operand's elements; text and octets gather the operand.
    const gathered_type = if (kind == .list) sequence_type else try collections.listType(&checker.catalog, sequence_type, span);
    const gathered = try b.local(gathered_type);
    const index = try b.local(.i64);
    const gather: @import("buffer_operations.zig").Kind = if (kind == .list) .extend else .append;
    const body = try b.stmt(.{ .block = try allocator.dupe(typed.StatementId, &.{
        try b.stmt(.{ .discard = try b.operation(gathered, gather, &.{try b.read(sequence)}) }),
        try b.stmt(.{ .assign = .{ .slot = index, .value = try b.binary(.add, try b.read(index), try b.integer(1), .i64) } }),
    }) });
    const loop_id = checker.loops.next;
    checker.loops.next += 1;
    const statements = try allocator.dupe(typed.StatementId, &.{
        if (operands.count_first) bind_count else bind_sequence,
        if (operands.count_first) bind_sequence else bind_count,
        try b.stmt(.{ .initialize = .{ .slot = gathered, .value = try b.node(gathered_type, .{ .acquire_buffer = .{ .capacity = try b.integer(0) } }) } }),
        try b.stmt(.{ .initialize = .{ .slot = index, .value = try b.integer(0) } }),
        try b.stmt(.{ .loop = .{ .id = loop_id, .condition = try b.binary(.lt, try b.read(index), try b.read(count), .bool), .body = body } }),
    });
    if (kind == .list) return b.block(statements, try b.read(gathered));
    const empty = try b.node(sequence_type, .{ .array = &.{} });
    const joined = try b.access(empty, .join, &.{try b.read(gathered)}, false);
    return b.block(statements, try b.node(joined.ty, joined.data));
}
