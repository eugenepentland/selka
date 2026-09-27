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
        if ((try catalog.get(local.ty)).unique_drop) {
            mode.* = .consume_on_entry;
            continue;
        }
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

/// An additional internal entry exists only after an every-return physical proof.
/// The canonical guest contract above remains owned, including indirect calls.
pub fn borrowed(allocator: std.mem.Allocator, catalog: *shapes.Catalog, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    return @import("rc_borrow_certificate.zig").certify(allocator, catalog, function, abi);
}

/// Program-aware proof also folds dependencies of immortal-only helper bodies.
pub fn borrowedIn(allocator: std.mem.Allocator, catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?model.BorrowCertificate {
    return @import("rc_borrow_certificate.zig").certifyIn(allocator, catalog, functions, function, abi);
}

/// Standalone constant-result authority, including its actual physical preflight.
pub fn immortalIn(catalog: *shapes.Catalog, functions: []const bytecode.Function, function: bytecode.Function, abi: []const u8) native.Error!?model.ImmortalCertificate {
    return @import("rc_immortal_certificate.zig").certify(catalog, functions, function, abi);
}
