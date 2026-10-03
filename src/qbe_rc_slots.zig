//! Typed RC slot operations and success/failure commit points.
//! Addresses name physical values, never aggregate operand pointer cells.
const typed = @import("typed.zig");
const glue = @import("qbe_rc_glue.zig");

/// Native emission failures shared with the main QBE emitter.
pub const Error = error{ InternalError, OutOfMemory, SourceError, WriteFailed };
/// Which atomic runtime operation establishes the destination ownership.
pub const Mode = enum { copy_empty, retain_empty, take_empty, replace_copy };
/// One ownership operation; region is an SSA value containing the target depth.
pub const Transfer = struct {
    ty: typed.Type,
    destination: usize,
    source: usize,
    region: usize,
    mode: Mode,
    /// The complete value ranges occupy distinct compiler-reserved buffers.
    disjoint: bool = false,
};
/// One initialized frame value; guard names its 32-bit initialization slot.
pub const OwnedSlot = struct {
    ty: typed.Type,
    address: usize,
    guard: usize,
    unique_drop: bool,
    counted: bool,
};

/// Bind the slot primitives to a concrete emitter without an import cycle.
pub fn Lower(comptime E: type) type {
    return struct {
        /// Prepare ownership atomically; no compiler guard changes on failure.
        pub fn transfer(self: *E, operation: Transfer) Error!void {
            const moved = if (operation.mode == .take_empty) try @import("qbe_rc_inline_take.zig").begin(E, self, operation) else null;
            try runtimeTransfer(self, operation);
            if (moved) |label| try self.print("@rcmoved{d}\n", .{label});
        }

        /// Emit the fallible runtime operation and branch before publishing guards.
        pub fn runtimeTransfer(self: *E, operation: Transfer) Error!void {
            const routed = try glue.routed(E, self, operation.ty);
            const move: glue.Transfer = .{ .ty = operation.ty, .destination = operation.destination, .source = operation.source, .region = operation.region, .disjoint = operation.disjoint };
            if (routed and operation.mode == .retain_empty) return glue.retain(E, self, move);
            if (routed and operation.mode == .take_empty) return glue.take(E, self, move);
            const helper = switch (operation.mode) {
                .copy_empty => "myl_rc_native_copy",
                .retain_empty => "myl_rc_native_retain",
                .take_empty => "myl_rc_native_take",
                .replace_copy => "myl_rc_native_replace",
            };
            const result = self.temp();
            try self.print(" %v{d} =w call ${s}(l %heap, l extern ${s}, l %v{d}, l %v{d}, w %v{d})\n", .{
                result, helper, try self.descriptor(operation.ty), operation.destination, operation.source, operation.region,
            });
            try requireSuccess(E, self, result);
        }

        /// Publish an ownership guard only after all preceding helpers commit.
        pub fn initialized(self: *E, guard: usize, value: bool) Error!void {
            try self.print(" storew {d}, %v{d}\n", .{ @intFromBool(value), guard });
        }

        /// Clear the obligation before cleanup can reenter a host callback.
        /// Unique provider resources close through their existing scheduler;
        /// only physically counted subfields enter the RC descriptor walk.
        pub fn release(self: *E, slot: OwnedSlot) Error!void {
            const live = self.temp();
            const finish = self.temp();
            try self.print(" %v{d} =w loaduw %v{d}\n jnz %v{d}, @rcrelease{d}, @rcreleased{d}\n@rcrelease{d}\n", .{
                live, slot.guard, live, finish, finish, finish,
            });
            try initialized(self, slot.guard, false);
            if (slot.unique_drop) try self.print(" call $myl_native_owned_drop(l %heap, l extern ${s}, l %v{d})\n", .{ try self.descriptor(slot.ty), slot.address });
            if (slot.counted) try glue.drop(E, self, .{ .ty = slot.ty, .address = slot.address });
            try self.print("@rcreleased{d}\n", .{finish});
        }
    };
}

/// Map a sticky RC refusal before any compiler ownership guard changes.
pub fn requireSuccess(comptime E: type, self: *E, result: usize) Error!void {
    return glue.requireSuccess(E, self, result);
}
