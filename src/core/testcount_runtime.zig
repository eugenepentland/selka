//! The `testing` module's managed-allocation counter, inserted into the runtime
//! only for a program that imports it (`B5`).
//!
//! `testing.allocations(work, n)` counts one event per managed block the runtime
//! allocates while the measurement is active. The event reads a flag, so a
//! program that never measures would still pay it on every allocation; the
//! ordinary runtime therefore keeps none of it, and only an executable that
//! contains a `testing` import compiles the inserted text. The declarations and
//! the reader stay in the base runtime so the ABI is the same in every variant.
const std = @import("std");
const ir = @import("ir.zig");

/// The program declares the reserved runtime reader built by `build_testing`.
/// Split units inspect the complete module so a measured callee uses the same
/// allocation path as the unit containing the reader.
pub fn needed(module: *const ir.Module) bool {
    for (module.functions.items) |function| {
        if (function.signature.linkage != .runtime_c) continue;
        if (std.mem.eql(u8, function.name, "myl_core_test_allocations")) return true;
    }
    return false;
}

/// The text inserted before `block_alloc`'s header store.
pub const inserted =
    \\    /* One managed block while a `testing` measurement is active (B5). */
    \\    if (atomic_load_explicit(&test_count_allocations, memory_order_relaxed))
    \\        (void)atomic_fetch_add_explicit(&test_allocations, 1, memory_order_relaxed);
    \\
;

/// The line the event is inserted before; the same anchor the counting runtime uses.
pub const anchor = "    block->kind = kind | (class << MYL_CLASS_SHIFT);\n";

/// The ordinary runtime text with the allocation event inserted, or
/// `AnchorMissing` when the runtime no longer has the shape this insertion needs.
pub fn source(allocator: std.mem.Allocator, text: []const u8) error{ OutOfMemory, AnchorMissing }![]const u8 {
    const at = std.mem.indexOf(u8, text, anchor) orelse return error.AnchorMissing;
    return std.mem.concat(allocator, u8, &.{ text[0..at], inserted, text[at..] });
}

test "the allocation event is inserted once, before block_alloc's header store" {
    const a = std.testing.allocator;
    const base = "#include <stdlib.h>\nstatic void f(void) {\n" ++ anchor ++ "}\n";
    const counted = try source(a, base);
    defer a.free(counted);
    try std.testing.expectEqual(@as(usize, 1), std.mem.count(u8, counted, "test_count_allocations, memory_order_relaxed"));
    try std.testing.expect(std.mem.indexOf(u8, counted, anchor) != null);
    try std.testing.expectEqual(base.len + inserted.len, counted.len);
    try std.testing.expectError(error.AnchorMissing, source(a, "void f(void) {}\n"));
}
