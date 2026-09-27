//! Compiler view of the resolved runtime contract. Lowering never reads the
//! environment or independently chooses a memory implementation.
const std = @import("std");
const contract = @import("runtime_contract");
const wiring = @import("wiring/runtime_mode.zig");

/// Versioned memory implementation selected before compilation starts.
pub const Selection = contract.Selection;

/// Normalized carrier used by command startup and native children.
pub const variable = contract.variable;

/// The current process selection, also used for test save/restore.
pub fn get() Selection {
    return wiring.selection;
}

/// Set the already normalized selection at startup, or inside a restored test.
pub fn set(selection: Selection) void {
    wiring.selection = selection;
}

/// Whether the selected artifact uses reference counting.
pub fn enabled() bool {
    return get().enabled();
}

/// Whether the selected artifact instruments reference-count operations.
pub fn counting() bool {
    return get().counting();
}

/// Whether the selected artifact attributes ownership events to their
/// emission sites (`RC-SITES-1`).
pub fn sites() bool {
    return get().sites();
}

/// Ownership ABI and instrumentation identity for persisted native artifacts.
pub fn identity() []const u8 {
    return get().identity();
}

// spec-case: RC-RUNTIME-CONTRACT-1
test "runtime mode keeps compiler selection separate from its ABI decoding" {
    const saved = get();
    defer set(saved);
    set(.gc);
    try std.testing.expect(!enabled() and !counting());
    try std.testing.expectEqualStrings("gc-v1", identity());
    set(.rc);
    try std.testing.expect(enabled() and !counting());
    try std.testing.expectEqualStrings("rc-v3", identity());
    set(.rc_counting);
    try std.testing.expect(enabled() and counting() and !sites());
    try std.testing.expectEqualStrings("rc-v3-counting", identity());
    set(.rc_sites);
    try std.testing.expect(enabled() and counting() and sites());
    try std.testing.expectEqualStrings("rc-v3-sites", identity());
}

// spec: RC-RUNTIME-CONTRACT-1
test "runtime contract versions reject unknown ABIs and preserve legacy GC" {
    try std.testing.expectEqual(Selection.gc, try contract.parse(null));
    try std.testing.expectEqual(Selection.gc, try contract.parse("gc-v1"));
    try std.testing.expectEqual(Selection.rc, try contract.parse("rc-v3"));
    try std.testing.expectEqual(Selection.rc_counting, try contract.parse("rc-v3-counting"));
    try std.testing.expectEqual(Selection.rc_sites, try contract.parse("rc-v3-sites"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v1"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v1-counting"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v2"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v2-counting"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v4"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse(""));
    try std.testing.expectEqual(Selection.gc, try contract.resolve(.rc, false, false));
    try std.testing.expectError(error.IncompatibleRuntime, contract.resolve(.rc_counting, false, true));
    try std.testing.expectEqual(Selection.rc, try contract.resolve(.rc, true, true));
    try std.testing.expect(!Selection.gc.enabled() and !Selection.gc.counting());
    try std.testing.expect(Selection.rc.enabled() and !Selection.rc.counting());
    try std.testing.expect(Selection.rc_counting.enabled() and Selection.rc_counting.counting());
    try std.testing.expect(Selection.rc_sites.enabled() and Selection.rc_sites.counting() and Selection.rc_sites.sites());
    try std.testing.expect(!Selection.rc_counting.sites() and !Selection.rc.sites() and !Selection.gc.sites());
    try std.testing.expectError(error.IncompatibleRuntime, contract.resolve(.rc_sites, false, true));
}
