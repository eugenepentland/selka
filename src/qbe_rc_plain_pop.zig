//! Tail removal for registered small values without ownership edges.
const typed = @import("typed.zig");
const format = @import("qbe_format.zig");
const zero = @import("qbe_zero.zig");
const Error = @import("qbe_rc_slots.zig").Error;

/// Keep the runtime path for cold metadata, pending finalizers and invalid
/// headers. The common caller still reports the original allocation/bounds error.
pub fn emit(comptime E: type, self: *E, element: typed.Type, list: usize, destination: usize, output: usize) Error!bool {
    const layout = try self.layout(element);
    if (layout.size == 0 or layout.size > 64) return false;
    const state = self.cow.?.rc orelse return error.InternalError;
    const shape = state.catalog.get(element) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    if (shape.counted or shape.unique_drop) return false;
    try self.print(" # RC-PLAIN-POP-1 small tail removal\n", .{});
    try self.markObject(list);
    const length = try self.readValue(list, .u64);
    const generation_address = try self.address(list, 16);
    const generation = try self.readValue(generation_address, .u64);
    const nonempty = self.temp();
    const young = self.temp();
    const valid = self.temp();
    const ready = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =w cnel %v{d}, 0\n %v{d} =w cnel %v{d}, -1\n", .{ nonempty, length, young, generation });
    try self.print(" %v{d} =w and %v{d}, %v{d}\n jnz %v{d}, @rcpopquery{d}, @rcpopslow{d}\n@rcpopquery{d}\n", .{ valid, nonempty, young, valid, label, label, label });
    try self.print(" %v{d} =w call $myl_rc_list_plain_pop_ready(l %heap, l %v{d})\n", .{ ready, list });
    try self.print(" jnz %v{d}, @rcpopready{d}, @rcpopslow{d}\n@rcpopslow{d}\n", .{ ready, label, label, label });
    try self.print(" %v{d} =w call $myl_rc_list_pop(l %heap, l %v{d}, l %v{d})\n", .{ output, list, destination });
    try self.print(" jmp @rcpopdone{d}\n@rcpopready{d}\n", .{ label, label });
    const storage = try self.readValue(try self.address(list, format.list_storage_offset), .u64);
    try self.markElements(storage, element);
    const next_length = self.temp();
    const offset = self.temp();
    const slot = self.temp();
    const next_generation = self.temp();
    try self.print(" %v{d} =l sub %v{d}, 1\n %v{d} =l mul %v{d}, {d}\n", .{ next_length, length, offset, next_length, layout.size });
    try self.print(" %v{d} =l add %v{d}, %v{d}\n blit %v{d}, %v{d}, {d}\n", .{ slot, storage, offset, slot, destination, layout.size });
    try zero.clear(*E, self, slot, layout.size, layout.alignment);
    try self.print(" storel %v{d}, %v{d}\n %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n", .{ next_length, list, next_generation, generation, next_generation, generation_address });
    try self.print(" %v{d} =w copy 1\n@rcpopdone{d}\n", .{ output, label });
    return true;
}
