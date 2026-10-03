//! Inline the existing generated-glue room path for small plain aggregates.
const format = @import("qbe_format.zig");
const collections = @import("qbe_rc_collections.zig");
const glue = @import("qbe_rc_glue.zig");
const Error = @import("qbe_rc_slots.zig").Error;

/// Match the plain generated append's exact capacity, generation and alias
/// guards. This removes a guest-to-glue call without removing an allocation,
/// registration, ownership transfer or callback from either existing path.
pub fn emit(comptime E: type, self: *E, append: anytype) Error!bool {
    const width = (try self.layout(append.element)).size;
    if (width == 0 or width > 64 or self.isScalar(append.element)) return false;
    const state = self.cow.?.rc orelse return error.InternalError;
    const shape = state.catalog.get(append.element) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    if (shape.counted or shape.unique_drop) return false;
    if (!try glue.listRouted(E, self, append.element, .list_append)) return false;
    try self.print(" # RC-PLAIN-APPEND-2 small aggregate room path\n", .{});
    try self.markObject(append.list);
    const length = try self.readValue(append.list, .u64);
    const capacity = try self.readValue(try self.address(append.list, 8), .u64);
    const generation_address = try self.address(append.list, 16);
    const generation = try self.readValue(generation_address, .u64);
    const storage = try self.readValue(try self.address(append.list, format.list_storage_offset), .u64);
    const extent = self.temp();
    const distance = self.temp();
    const outside = self.temp();
    const room = self.temp();
    const young = self.temp();
    const ready = self.temp();
    const admitted = self.temp();
    const label = self.temp();
    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l sub %v{d}, %v{d}\n", .{ extent, length, width, distance, append.value, storage });
    try self.print(" %v{d} =w cugel %v{d}, %v{d}\n %v{d} =w cultl %v{d}, %v{d}\n", .{ outside, distance, extent, room, length, capacity });
    try self.print(" %v{d} =w cnel %v{d}, -1\n %v{d} =w and %v{d}, %v{d}\n %v{d} =w and %v{d}, %v{d}\n", .{ young, generation, ready, room, young, admitted, ready, outside });
    try self.print(" jnz %v{d}, @rcplainroom{d}, @rcplainslow{d}\n@rcplainslow{d}\n", .{ admitted, label, label, label });
    try collections.append(E, self, append.element, append.output, append.list, append.value);
    try self.require(append.output, format.allocation_failure);
    try self.print(" jmp @rcplaindone{d}\n@rcplainroom{d}\n", .{ label, label });
    try self.markElements(storage, append.element);
    const destination = self.temp();
    const next_length = self.temp();
    const next_generation = self.temp();
    try self.print(" %v{d} =l add %v{d}, %v{d}\n blit %v{d}, %v{d}, {d}\n", .{ destination, storage, extent, append.value, destination, width });
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n", .{ next_length, length, next_length, append.list });
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n@rcplaindone{d}\n", .{ next_generation, generation, next_generation, generation_address, label });
    return true;
}
