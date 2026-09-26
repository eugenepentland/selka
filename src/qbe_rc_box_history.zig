//! Immutable box materialization retains the tracing lane's semantic event.
const frame = @import("qbe_rc_frame.zig");
const slots = @import("qbe_rc_slots.zig");
/// Native emitter failures shared with ownership lowering.
pub const Error = slots.Error;
/// The GC lane materializes a mutable-bearing immutable body at this field read.
pub fn boxMaterialization(comptime E: type, self: *E) bool {
    const stack = self.states[self.pc] orelse return false;
    if (stack.len == 0) return false;
    const ty = stack[stack.len - 1];
    if (!ty.isAggregate() or !self.program.records[ty.recordIndex()].collection.box) return false;
    if (!@import("value_semantics.zig").needsCopy(self.program.records, ty)) return false;
    return !@import("qbe_cow.zig").Lower(E).scopedProjection(self, self.pc);
}

/// Materialize and publish the inline box body before any later field projection.
pub fn unbox(comptime E: type, self: *E, source: usize) Error!void {
    const stack = self.states[self.pc].?;
    const body = (try self.field(stack[stack.len - 1], 0)).ty;
    const destination = try self.aggregatePointer();
    const done = self.temp();
    try self.print(" %v{d} =w call $myl_rc_native_publish(l %heap, l extern ${s}, l %v{d}, l %v{d}, w %v{d}, w 0)\n", .{
        done, try self.descriptor(body), destination, source, try frame.region(E, self),
    });
    try slots.requireSuccess(E, self, done);
    try self.store(stack.len - 1, destination);
}
