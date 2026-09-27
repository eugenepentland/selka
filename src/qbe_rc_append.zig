//! Scalar appends use spare capacity only after nonmutating runtime admission.
const typed = @import("typed.zig");
const format = @import("qbe_format.zig");
const collections = @import("qbe_rc_collections.zig");
const Error = @import("qbe_rc_slots.zig").Error;
const loops = @import("qbe_rc_append_loop.zig");

/// An already-evaluated receiver and source; the surrounding COW and journals
/// remain responsible for uniqueness, lifetime and every fallback failure.
pub const Append = struct { list: usize, element: typed.Type, value: usize, output: usize };

/// Emit a scalar-only room path. Cold descriptors, queued finalizers, growth and
/// generation overflow retain precisely the original runtime append operation.
pub fn emit(comptime E: type, self: *E, append: Append) Error!bool {
    const width = (try self.layout(append.element)).size;
    if (!self.isScalar(append.element)) return false;
    if (width != 1 and width != 2 and width != 4 and width != 8) return false;
    const state = self.cow.?.rc orelse return error.InternalError;
    const shape = state.catalog.get(append.element) catch |err| return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
    if (shape.counted or shape.unique_drop) return false;
    // The source may point into the receiver's old backing. Capture its scalar
    // bits before either mutation path, without publishing or dropping a token.
    const held = try self.readValue(append.value, append.element);
    const label = self.temp();
    try self.markObject(append.list);
    const length = try word(E, self, append.list, 0);
    const capacity = try word(E, self, append.list, 8);
    const generation = try word(E, self, append.list, 16);
    const room = self.temp();
    const incrementable = self.temp();
    const ready = self.temp();
    try self.print(" %v{d} =w cultl %v{d}, %v{d}\n %v{d} =w cnel %v{d}, -1\n %v{d} =w and %v{d}, %v{d}\n", .{ room, length, capacity, incrementable, generation, ready, room, incrementable });
    try self.print(" jnz %v{d}, @rcappend_check{d}, @rcappend_slow{d}\n@rcappend_check{d}\n", .{ ready, label, label, label });
    const cached = loops.at(E, self);
    if (cached) |slot| {
        const known = self.temp();
        try self.print(" %v{d} =w loaduw %rcappend{d}\n jnz %v{d}, @rcappend_fast{d}, @rcappend_query{d}\n@rcappend_query{d}\n", .{ known, slot, known, label, label, label });
    }
    const admitted = self.temp();
    try self.print(" %v{d} =w call $myl_rc_list_plain_ready(l %heap, l %v{d})\n", .{ admitted, append.list });
    if (cached) |slot| try self.print(" storew %v{d}, %rcappend{d}\n", .{ admitted, slot });
    try self.print(" jnz %v{d}, @rcappend_fast{d}, @rcappend_slow{d}\n@rcappend_slow{d}\n", .{ admitted, label, label, label });
    // Never carry admission across allocation, cleanup or a reentrant callback.
    if (cached) |slot| try self.print(" storew 0, %rcappend{d}\n", .{slot});
    try collections.append(E, self, append.output, append.list, append.value);
    try self.require(append.output, format.allocation_failure);
    try self.print(" jmp @rcappend_done{d}\n@rcappend_fast{d}\n", .{ label, label });
    const storage = try word(E, self, append.list, format.list_storage_offset);
    try self.markElements(storage, append.element);
    const offset = self.temp();
    const destination = self.temp();
    try self.print(" %v{d} =l mul %v{d}, {d}\n %v{d} =l add %v{d}, %v{d}\n", .{ offset, length, width, destination, storage, offset });
    try self.writeValue(destination, held, append.element);
    try bump(E, self, append.list, length, 0);
    try bump(E, self, append.list, generation, 16);
    try self.print("@rcappend_done{d}\n", .{label});
    return true;
}

/// Read one fixed header word; no cached pointer survives the slow path.
fn word(comptime E: type, self: *E, list: usize, offset: usize) Error!usize {
    const address = try self.address(list, offset);
    const result = self.temp();
    try self.print(" %v{d} =l loadl %v{d}\n", .{ result, address });
    return result;
}

/// Both increments were checked before the no-callback publication span.
fn bump(comptime E: type, self: *E, list: usize, current: usize, offset: usize) Error!void {
    const address = try self.address(list, offset);
    const next = self.temp();
    try self.print(" %v{d} =l add %v{d}, 1\n storel %v{d}, %v{d}\n", .{ next, current, next, address });
}
