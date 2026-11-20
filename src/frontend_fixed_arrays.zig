//! Explicit conversion of a runtime growable array into a length checked fixed array.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const collections = @import("collection_lower.zig");
const Error = diagnostic.Error;
/// Prelude error identity for a runtime fixed array length mismatch.
pub const error_name = @import("frontend_type_names.zig").fixed_length_error;
/// Evaluate the source once and read elements only after its exact length is proved.
pub fn convert(comptime Checker: type, self: *Checker, input: typed.NodeId, target: typed.Type, span: source.Span) Error!typed.Node {
    const array = self.catalog.records[target.recordIndex()].shape.array orelse return error.InternalError;
    const input_type = self.nodes.items[@backingInt(input)].ty;
    // A fixed array or a Simd is a list-kind record too, but it has no growable
    // buffer: only a `T[]` converts at run time.
    const buffer = if (input_type.isAggregate() and self.catalog.records[input_type.recordIndex()].collection.kind == .list)
        self.catalog.records[input_type.recordIndex()].shape.buffer
    else
        null;
    if (buffer == null) return self.sink.fail("E_TYPE", span, try notGrowable(Checker, self, input_type, target));
    try self.require(buffer.?, array.element, span);
    const failure = try collections.preludeType(&self.catalog, error_name, span);
    const result = try collections.resultType(&self.catalog, target, failure, span);
    const shape = typed.resultShape(result, self.catalog.records).?;
    const builder: collections.Builder(Checker) = .{ .checker = self, .span = span };
    const owner = try builder.local(input_type);
    const output = try builder.local(result);
    const initialize = try builder.stmt(.{ .initialize = .{ .slot = owner, .value = input } });
    const length = try builder.length(owner);
    const condition = try builder.node(.bool, .{ .binary = .{ .op = .eq, .op_span = span, .left = length, .right = try builder.integer(@intCast(array.length)) } });
    const elements = try self.allocator.alloc(typed.NodeId, array.length);
    for (elements, 0..) |*element, index| element.* = try builder.operation(owner, .read, &.{try builder.node(.u64, .{ .integer = @intCast(index) })});
    const fixed = try builder.node(target, .{ .array = elements });
    const ok = try builder.node(result, .{ .variant = .{ .tag = shape.ok_tag, .value = fixed } });
    const err = try builder.node(result, .{ .variant = .{ .tag = shape.error_tag, .value = try builder.node(failure, .{ .variant = .{ .tag = 0, .value = null } }) } });
    const branch = try builder.stmt(.{ .branch = .{
        .condition = condition,
        .then_body = try builder.stmt(.{ .initialize = .{ .slot = output, .value = ok } }),
        .else_body = try builder.stmt(.{ .initialize = .{ .slot = output, .value = err } }),
    } });
    return builder.block(&.{ initialize, branch }, try builder.read(output));
}
/// The refusal of a constructor input that is not a growable array: it names
/// both forms the constructor takes and the type it was given.
fn notGrowable(comptime Checker: type, self: *Checker, input: typed.Type, target: typed.Type) Error![]const u8 {
    const records = self.catalog.records;
    const wanted = try typed.surfaceTypeName(self.allocator, target, records);
    const given = try typed.surfaceTypeName(self.allocator, input, records);
    const same = input.isAggregate() and target.isAggregate() and input.recordIndex() == target.recordIndex();
    const hint = if (same) "; the value already has this type, so use it as it is" else "";
    return std.fmt.allocPrint(
        self.allocator,
        "{s}(...) takes a list literal of its elements or a growable array (T[]), not {s}{s}",
        .{ wanted, given, hint },
    );
}
