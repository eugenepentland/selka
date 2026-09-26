//! Canonical physical guest-call contracts (RC-OWNERSHIP-PLAN-1).
//! Provenance summaries bound possible aliases; they never grant a borrowed ABI.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const native = @import("native_types.zig");
const shapes = @import("rc_shape.zig");
const model = @import("rc_model.zig");

/// Allocate a guest contract in the function's planning arena.
pub fn guest(allocator: std.mem.Allocator, catalog: *shapes.Catalog, function: bytecode.Function, abi: []const u8) native.Error!model.CallContract {
    const count = function.signature.parameter_count;
    if (count > function.scope.locals.len) return error.InvalidType;
    const parameters = try allocator.alloc(model.Parameter, count);
    errdefer allocator.free(parameters);
    for (function.scope.locals[0..count], parameters, 0..) |local, *mode, position| {
        const writes = @import("ownership_model.zig").writesParameter(function, position);
        mode.* = if (!writes) .read else if (typed.referenceMut(catalog.native.records, local.ty)) .caller_storage else .mutable_payload;
    }
    const result = try catalog.get(function.signature.return_type);
    return .{
        .parameters = parameters,
        .result = if (result.counted or result.unique_drop) .owned else .plain,
        .mutates = function.signature.mutates,
        .abi = abi,
    };
}
