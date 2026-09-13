//! Public native-call metadata, derived only from checked project export roots.
const std = @import("std");
const bytecode = @import("bytecode_model.zig");
const typed = @import("typed.zig");

/// Failures allocating export metadata or validating checked identities.
pub const Error = error{ OutOfMemory, InternalError };

/// Exact scalar ABI signature; unsupported public signatures remain discoverable.
pub const Export = struct { name: []const u8, parameters: []const []const u8, result: []const u8, scalar: bool, references: bool };

/// Return null for implementation-private functions and concrete generic instances.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, index: usize, roots: []const typed.FunctionId) Error!?Export {
    var exported = false;
    for (roots) |root| {
        if (@backingInt(root) >= program.functions.len) return error.InternalError;
        if (@backingInt(root) == index) exported = true;
    }
    if (!exported) return null;
    const function = program.functions[index];
    const parameters = try allocator.alloc([]const u8, function.signature.parameter_count);
    var references = function.signature.return_reference != null;
    var scalar = !references and scalarType(function.signature.return_type);
    for (function.scope.locals[0..function.signature.parameter_count], parameters) |local, *parameter| {
        parameter.* = typed.typeName(local.ty, program.records);
        if (local.parameter.reference_parameter != null) references = true;
        if (local.parameter.reference_parameter != null or !scalarType(local.ty)) scalar = false;
    }
    return .{ .name = function.name, .parameters = parameters, .result = typed.typeName(function.signature.return_type, program.records), .scalar = scalar, .references = references };
}
fn scalarType(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool;
}

test "export metadata rejects an invalid authoritative root" {
    try std.testing.expectError(error.InternalError, describe(std.testing.allocator, .{ .functions = &.{} }, 0, &.{@fromBackingInt(0)}));
    try std.testing.expectEqual(@as(?Export, null), try describe(std.testing.allocator, .{ .functions = &.{} }, 0, &.{}));
}
