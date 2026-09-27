//! Lower certified borrowed entries independently of canonical owned calls.
const std = @import("std");
const bytecode = @import("bytecode.zig");
const typed = @import("typed.zig");
const frame = @import("qbe_rc_frame.zig");
const model = @import("rc_model.zig");
const runtime = @import("runtime_mode.zig");
/// Errors shared with the concrete native emitter.
pub const Error = frame.Error;

/// Whether this body has a complete caller-anchored loan certificate.
pub fn active(comptime E: type, self: *E) bool {
    if (!runtime.enabled()) return false;
    const state = if (self.cow) |cow| cow.rc orelse return false else return false;
    return state.readonly or state.contract.result == .borrowed;
}

/// Resolve a direct callee's every-return proof in the current physical catalog.
pub fn certificate(comptime E: type, self: *E, function: bytecode.Function) Error!?model.BorrowCertificate {
    if (runtime.enabled()) if (self.cow) |cow| if (cow.rc) |state| {
        if (state.readonly) {
            const route = (try @import("qbe_rc_readonly_calls.zig").route(E, self, function)) orelse return null;
            return switch (route) {
                .borrowed => |proof| proof,
                .immortal => error.InternalError,
            };
        }
    };
    const state = frame.get(E, self) orelse return null;
    return @import("rc_calls.zig").borrowedIn(self.allocator, &state.catalog, self.program.functions, function, runtime.identity()) catch |err| {
        return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    };
}

/// Canonical symbols remain the ABI for function values, exports and providers.
pub fn symbol(allocator: std.mem.Allocator, canonical: []const u8) error{OutOfMemory}![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}_rc_borrow", .{canonical});
}

/// Select a saved raw route before frame.get can hide the inactive journal.
pub fn calleeSymbol(comptime E: type, self: *E, function: bytecode.Function, canonical: []const u8) Error![]const u8 {
    if (runtime.enabled()) if (self.cow) |cow| if (cow.rc) |state| {
        if (state.readonly) {
            const route = (try @import("qbe_rc_readonly_calls.zig").route(E, self, function)) orelse return canonical;
            return entrySymbol(self.allocator, canonical, route);
        }
    };
    return if (try certificate(E, self, function) != null) symbol(self.allocator, canonical) else canonical;
}

/// Distinct alternate symbols preserve canonical owned and function-value ABIs.
pub fn entrySymbol(allocator: std.mem.Allocator, canonical: []const u8, entry: model.EntryCertificate) error{OutOfMemory}![]const u8 {
    return switch (entry) {
        .borrowed => symbol(allocator, canonical),
        .immortal => std.fmt.allocPrint(allocator, "{s}_rc_immortal", .{canonical}),
    };
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
            const value = try self.load("s", stack.len - 1);
            // Local scalar slots are canonical machine words even when their
            // packed field layout is a byte (for example a branch's bool).
            if (self.isScalar(ty)) try self.print(" storel %v{d}, %v{d}\n", .{ value, destination }) else try self.writeValue(destination, value, ty);
            return true;
        },
        else => return false,
    }
}
