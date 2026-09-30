//! Physical proof dependencies use semantic references, independent of a module's local IDs.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");

/// Bind exactly the proved operation with symbolic type and callee references.
/// All ordinary operands and literal contents remain part of the identity.
pub fn operation(hash: *std.crypto.hash.Blake3, catalog: *shapes.Catalog, functions: []const bytecode.Function, op: @FieldType(bytecode.Instruction, "op")) native.Error!void {
    const digest = try @import("module_physical.zig").digest(catalog.allocator, .{ .records = catalog.native.records, .functions = functions }, op);
    hash.update(&digest);
}
