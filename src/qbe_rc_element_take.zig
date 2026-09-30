//! RC-ELEMENT-TAKE-1 lowering: bind a certified arm by moving the element's
//! payload when the scrutinee is that element's own storage in a physically
//! unique list, and by retaining a copy otherwise (`rc_element_take.zig`).
const typed = @import("typed.zig");
const format = @import("qbe_format.zig");
const slots = @import("qbe_rc_slots.zig");
const Take = @import("rc_element_take.zig").Take;
/// Native emission failures shared with typed slot operations.
pub const Error = slots.Error;
/// The arm's scrutinee pointer, the payload address inside it, the binding's
/// work storage, the payload type and the transfer's region depth.
pub const Binding = struct { scrutinee: usize, payload: usize, work: usize, ty: typed.Type, region: usize };

// Common-header mark bits (native_heap.h): immortal, copy-on-write shared and
// arena objects never count as physically unique here.
const shared_marks: u64 = (@as(u64, 1) << 62) | (@as(u64, 1) << 61) | 2;
// Prefix words below a counted payload (native_rc.h): owners and mark.
const prefix = @import("qbe_rc_prefix.zig");
const owners_offset = prefix.owners_offset;
const mark_offset = prefix.mark_offset;

/// Move or copy the payload into `binding.work`; either way the work storage
/// then holds one ordinary owner, exactly as the ordinary retain leaves it.
pub fn bind(comptime E: type, self: *E, take: Take, binding: Binding) Error!void {
    const moved = try movable(E, self, take, binding.scrutinee);
    const label = self.temp();
    try self.print(" # RC-ELEMENT-TAKE-1 dispatch {d} slot {d} list {d}\n", .{ take.dispatch, take.slot, take.list });
    try self.print(" jnz %v{d}, @rctakeelement{d}, @rctakecopy{d}\n@rctakeelement{d}\n", .{ moved, label, label, label });
    try slots.Lower(E).transfer(self, .{ .ty = binding.ty, .destination = binding.work, .source = binding.payload, .region = binding.region, .mode = .take_empty });
    try self.print(" jmp @rctaken{d}\n@rctakecopy{d}\n", .{ label, label });
    try slots.Lower(E).transfer(self, .{ .ty = binding.ty, .destination = binding.work, .source = binding.payload, .region = binding.region, .mode = .retain_empty });
    try self.print("@rctaken{d}\n", .{label});
}

// A word flag: the scrutinee is element `index` of the list in the list local,
// read in place rather than through a private loan copy, and the list has one
// owner and no shared, arena or immortal mark (only a counted object has an
// owner word to read).
fn movable(comptime E: type, self: *E, take: Take, scrutinee: usize) Error!usize {
    const list_ty = self.function.scope.locals[take.list].ty;
    const element_ty = self.program.records[list_ty.recordIndex()].shape.buffer orelse return error.InternalError;
    const size = (try self.layout(element_ty)).size;
    const list = self.temp();
    const at = self.temp();
    const storage = self.temp();
    const index = self.temp();
    const offset = self.temp();
    const element = self.temp();
    const result = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =w copy 0\n %v{d} =l loadl %l{d}\n", .{ result, list, take.list });
    try self.print(" jnz %v{d}, @rctakelist{d}, @rctakedone{d}\n@rctakelist{d}\n", .{ try nonzero(E, self, list), label, label, label });
    try self.markObject(list);
    try self.print(" %v{d} =l add %v{d}, {d}\n %v{d} =l loadl %v{d}\n", .{ at, list, format.list_storage_offset, storage, at });
    try self.print(" %v{d} =l loadl %l{d}\n %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ index, take.index, offset, index, size, element, storage, offset });
    try self.print(" jnz %v{d}, @rctakedone{d}, @rctakeheader{d}\n@rctakeheader{d}\n", .{ try different(E, self, element, scrutinee), label, label, label });
    const header = self.temp();
    const mark = self.temp();
    const special = self.temp();
    try self.print(" %v{d} =l sub %v{d}, {d}\n # myl-rc %v{d}\n %v{d} =l loadl %v{d}\n %v{d} =l and %v{d}, {d}\n", .{ header, list, mark_offset, header, mark, header, special, mark, shared_marks });
    try self.print(" jnz %v{d}, @rctakedone{d}, @rctakecount{d}\n@rctakecount{d}\n", .{ try nonzero(E, self, special), label, label, label });
    const counter = self.temp();
    const owners = self.temp();
    try self.print(prefix.load_count, .{ counter, list, owners_offset, counter, owners, counter });
    try self.print(" %v{d} =w cult" ++ prefix.count_type ++ " %v{d}, 2\n@rctakedone{d}\n", .{ result, owners, label });
    return result;
}

// Full-width comparisons: QBE's jnz reads only the low word of an l value.
fn nonzero(comptime E: type, self: *E, value: usize) Error!usize {
    const flag = self.temp();
    try self.print(" %v{d} =w cnel %v{d}, 0\n", .{ flag, value });
    return flag;
}

fn different(comptime E: type, self: *E, left: usize, right: usize) Error!usize {
    const flag = self.temp();
    try self.print(" %v{d} =w cnel %v{d}, %v{d}\n", .{ flag, left, right });
    return flag;
}
