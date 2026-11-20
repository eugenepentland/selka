//! Named provider payload requirements shared by concrete and symbolic checking.
/// Provider operations with a structured success or failure payload.
pub const Operation = enum { completion, environment, read, slice_read };
/// Exact scalar or storage category required for a named field.
pub const Requirement = enum { i64, u64, boolean, bytes, resource };
/// Field identity and required value category, independent of declaration order.
pub const Field = struct { name: []const u8, requirement: Requirement };
const bytes: Field = .{ .name = "bytes", .requirement = .bytes };
const length: Field = .{ .name = "length", .requirement = .u64 };
const eof: Field = .{ .name = "eof", .requirement = .boolean };
/// Return the complete payload contract in stable semantic slot order.
pub fn fields(operation: Operation) []const Field {
    return switch (operation) {
        .completion => &.{ .{ .name = "resource", .requirement = .resource }, .{ .name = "code", .requirement = .i64 } },
        .environment => &.{ bytes, length, .{ .name = "present", .requirement = .boolean } },
        .read => &.{ bytes, length, eof },
        .slice_read => &.{ length, eof },
    };
}
