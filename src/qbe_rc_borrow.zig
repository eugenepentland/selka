//! Lower certified borrowed entries independently of canonical owned calls.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const model = @import("rc_model.zig");
const runtime = @import("runtime_mode.zig");
/// Errors shared with the concrete native emitter.
pub const Error = frame.Error;

/// Whether this body is the separately certified internal borrowed entry.
pub fn active(comptime E: type, self: *E) bool {
    const state = frame.get(E, self) orelse return false;
    return state.contract.result == .borrowed;
}

/// Resolve a direct callee's every-return proof in the current physical catalog.
pub fn certificate(comptime E: type, self: *E, function: bytecode.Function) Error!?model.BorrowCertificate {
    const state = frame.get(E, self) orelse return null;
    return @import("rc_calls.zig").borrowedIn(self.allocator, &state.catalog, self.program.functions, function, runtime.identity()) catch |err| {
        return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    };
}

/// Canonical symbols remain the ABI for function values, exports and providers.
pub fn symbol(allocator: std.mem.Allocator, canonical: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}_rc_borrow", .{canonical});
}

/// Locals in a certified body are physical borrowed bits; none acquires an owner.
/// The proof forbids parameter writes, unique resources and fresh allocations.
pub fn local(comptime E: type, self: *E, op: @FieldType(bytecode.Instruction, "op"), stack: []const typed.Type) Error!?bool {
    if (!active(E, self)) return null;
    switch (op) {
        .value_copy, .drop_local, .pop, .acknowledge => return true,
        .store_local => |local_id| {
            const index = @backingInt(local_id);
            const ty = self.function.scope.locals[index].ty;
            const destination = self.temp();
            try self.print(" %v{d} =l copy %l{d}\n", .{ destination, index });
            try self.writeValue(destination, try self.load("s", stack.len - 1), ty);
            return true;
        },
        else => return false,
    }
}
