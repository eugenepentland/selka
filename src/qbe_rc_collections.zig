//! RC collection calls preserve ownership at each runtime publication boundary.
const mode = @import("runtime_mode.zig");
const allocation_failure = @import("qbe_format.zig").allocation_failure;
const Error = @import("qbe_rc_slots.zig").Error;
const typed = @import("typed.zig");
const values = @import("qbe_rc_values.zig");
const BufferOperation = @FieldType(@FieldType(@import("bytecode.zig").Instruction, "op"), "buffer_operation");

/// Destructive reads distinguish missing elements from refused publication.
pub fn removalStatus(comptime E: type, self: *E, status: usize) Error!void {
    if (!mode.enabled()) return;
    const valid = self.temp();
    try self.print(" %v{d} =w csgew %v{d}, 0\n", .{ valid, status });
    try self.require(valid, allocation_failure);
}

/// Owned element append; the receiver and source slot remain borrowed.
/// A counted element type appends through its glue (RC-GLUE-1).
pub fn append(comptime E: type, self: *E, element: typed.Type, result: usize, list: usize, value: usize) Error!void {
    if (mode.enabled()) {
        const glue = @import("qbe_rc_glue.zig");
        if (try glue.routed(E, self, element)) return glue.listWrite(E, self, .{ .element = element, .result = result, .list = list, .value = value });
    }
    const symbol = if (mode.enabled()) "myl_rc_list_append" else "myl_native_list_append";
    try self.print(" %v{d} =w call ${s}(l %heap, l %v{d}, l %v{d})\n", .{ result, symbol, list, value });
}

/// Six request words use one frame slot rather than exceeding the C ABI limit.
pub const KeyedSort = struct { values: usize, source: usize, keys: usize, shape: u64, offsets: u64, reverse: usize };
/// Fill the reserved sort request and call the heap-aware ownership helper.
pub fn keyedSort(comptime E: type, self: *E, output: usize, request: KeyedSort) Error!void {
    const pointer = self.temp();
    try self.print(" %v{d} =l copy %rcsort\n storel %v{d}, %v{d}\n", .{ pointer, request.values, pointer });
    const source = try self.address(pointer, 8);
    const keys = try self.address(pointer, 16);
    const shape = try self.address(pointer, 24);
    const offsets = try self.address(pointer, 32);
    const reverse = try self.address(pointer, 40);
    try self.print(" storel %v{d}, %v{d}\n storel %v{d}, %v{d}\n storel {d}, %v{d}\n storel {d}, %v{d}\n storel %v{d}, %v{d}\n", .{
        request.source, source, request.keys, keys, request.shape, shape, request.offsets, offsets, request.reverse, reverse,
    });
    try self.print(" %v{d} =w call $myl_rc_list_sort_keyed(l %heap, l %v{d})\n", .{ output, pointer });
}

/// Runtime constructors and destructive reads publish owned results; ordinary
/// element reads and dictionary defaults borrow until the operand plan copies.
pub fn resultOrigin(kind: @import("runtime_values.zig").ManagedKind, operation: @FieldType(BufferOperation, "kind")) values.Origin {
    return switch (operation) {
        .read => if (kind == .string) .owned else .borrowed,
        .key_at, .value_at, .get => .borrowed,
        else => .owned,
    };
}

/// A successful pop already owns its output. Copy the fallback on the absent
/// branch so both incoming paths give the operand journal one owned result.
pub const DefaultResult = struct { found: usize, pointer: usize, base: usize, ty: typed.Type };
/// Normalize both branches of dictionary pop-with-default to owned results.
pub fn ownedDefault(comptime E: type, self: *E, result: DefaultResult) Error!void {
    const label = self.temp();
    try self.print(" jnz %v{d}, @rcfound{d}, @rcmissing{d}\n@rcmissing{d}\n", .{ result.found, label, label, label });
    const input = self.temp();
    if (self.isScalar(result.ty)) try self.print(" %v{d} =l copy %s{d}\n", .{ input, result.base + 1 }) else try self.print(" %v{d} =l loadl %s{d}\n", .{ input, result.base + 1 });
    try values.copyRuntime(E, self, result.ty, result.pointer, input);
    try self.print(" jmp @rcfound{d}\n@rcfound{d}\n", .{ label, label });
    try self.store(result.base, try self.readValue(result.pointer, result.ty));
}

// spec-case: RC-COLLECTION-1
// spec-case: RC-DICTIONARY-1
// spec-case: RC-VIEWS-1
test "RC collection results distinguish borrowed reads from owned publication" {
    const std = @import("std");
    try std.testing.expectEqual(values.Origin.borrowed, resultOrigin(.list, .read));
    try std.testing.expectEqual(values.Origin.owned, resultOrigin(.string, .read));
    try std.testing.expectEqual(values.Origin.borrowed, resultOrigin(.dictionary, .get));
    try std.testing.expectEqual(values.Origin.borrowed, resultOrigin(.dictionary, .value_at));
    try std.testing.expectEqual(values.Origin.owned, resultOrigin(.dictionary, .setdefault));
    try std.testing.expectEqual(values.Origin.owned, resultOrigin(.dictionary, .pop_default));
    try std.testing.expectEqual(values.Origin.owned, resultOrigin(.list, .pop));
    try std.testing.expectEqual(values.Origin.owned, resultOrigin(.bytes, .slice));
}
