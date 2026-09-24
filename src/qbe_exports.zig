//! Public native-call metadata, derived only from checked project export roots.
const std = @import("std");
const bytecode = @import("bytecode_model.zig");
const typed = @import("typed.zig");

/// Failures allocating export metadata or validating checked identities.
pub const Error = error{ OutOfMemory, InternalError };

/// Exact scalar ABI signature; unsupported public signatures remain discoverable.
/// `parameter_names` lets the adapter inject a `Stream` sentinel by parameter
/// name even though the type itself travels as an opaque word.
pub const Export = struct { name: []const u8, parameters: []const []const u8, parameter_names: []const []const u8, result: []const u8, scalar: bool, references: bool };

/// Return null for implementation-private functions and concrete generic instances.
pub fn describe(allocator: std.mem.Allocator, program: bytecode.Program, index: usize, roots: []const typed.FunctionId) Error!?Export {
    const mask = try rootMask(allocator, program, roots);
    defer allocator.free(mask);
    return describeMarked(allocator, program, index, mask);
}

/// One flag per function of `program`, set for every export root; a root
/// outside the program is refused. An emission marks the roots once and
/// reads one flag per unit, where looking each unit up in the
/// root list cost a program whose every function is public time quadratic in
/// its size (about a fifth of a second at 18,000 functions).
pub fn rootMask(allocator: std.mem.Allocator, program: bytecode.Program, roots: []const typed.FunctionId) Error![]bool {
    const mask = try allocator.alloc(bool, program.functions.len);
    @memset(mask, false);
    for (roots) |root| {
        if (@backingInt(root) >= program.functions.len) {
            allocator.free(mask);
            return error.InternalError;
        }
        mask[@backingInt(root)] = true;
    }
    return mask;
}

/// The export description of function `index` when `mask` (from `rootMask`) marks it.
pub fn describeMarked(allocator: std.mem.Allocator, program: bytecode.Program, index: usize, mask: []const bool) Error!?Export {
    if (index >= mask.len or !mask[index]) return null;
    const function = program.functions[index];
    const parameters = try allocator.alloc([]const u8, function.signature.parameter_count);
    const parameter_names = try allocator.alloc([]const u8, function.signature.parameter_count);
    var scalar = scalarType(function.signature.return_type);
    for (function.scope.locals[0..function.signature.parameter_count], parameters, parameter_names) |local, *parameter, *name| {
        parameter.* = typed.typeName(local.ty, program.records);
        name.* = local.name;
        if (!scalarType(local.ty)) scalar = false;
    }
    return .{ .name = function.name, .parameters = parameters, .parameter_names = parameter_names, .result = typed.typeName(function.signature.return_type, program.records), .scalar = scalar, .references = false };
}
fn scalarType(ty: typed.Type) bool {
    return ty.isInteger() or ty == .bool;
}

test "export metadata rejects an invalid authoritative root" {
    try std.testing.expectError(error.InternalError, describe(std.testing.allocator, .{ .functions = &.{} }, 0, &.{@fromBackingInt(0)}));
    try std.testing.expectEqual(@as(?Export, null), try describe(std.testing.allocator, .{ .functions = &.{} }, 0, &.{}));
}
