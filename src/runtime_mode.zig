//! Compiler view of the resolved runtime contract. Lowering never reads the
//! environment or independently chooses a memory implementation.
const std = @import("std");
const contract = @import("runtime_contract");
const wiring = @import("wiring/runtime_mode.zig");
const values = @import("wiring/value_semantics.zig");

/// Versioned memory implementation selected before compilation starts.
pub const Selection = contract.Selection;

/// Normalized carrier used by command startup and native children.
pub const variable = contract.variable;

/// The current process selection, also used for test save/restore.
pub fn get() Selection {
    return wiring.selection;
}

/// The contract lowering and in-process native builds use. Legacy sharing
/// lowers for the collector whatever was selected, the way a command resolves
/// `--legacy-sharing` with a default or inherited RC (`RC-DEFAULT-1`): RC
/// lowering needs the value model's copy-on-write plan.
pub fn lowered() Selection {
    if (!values.enabled) return .gc;
    return wiring.selection;
}

/// Set the already normalized selection at startup, or inside a restored test.
pub fn set(selection: Selection) void {
    wiring.selection = selection;
}

/// Select the tracing collector and return the selection to restore, for a
/// test that reads the collector's own lowering (roots, safepoints, barriers,
/// stand-in reuse, copy on write over the collector) rather than a program's
/// meaning, which the default reference counting must also give (`RC-DEFAULT-1`).
pub fn pinCollector() Selection {
    const saved = get();
    set(.gc);
    return saved;
}

/// Whether the selected artifact uses reference counting.
pub fn enabled() bool {
    return lowered().enabled();
}

/// Whether the selected artifact instruments reference-count operations.
pub fn counting() bool {
    return lowered().counting();
}

/// Whether the selected artifact attributes ownership events to their
/// emission sites (`RC-SITES-1`).
pub fn sites() bool {
    return lowered().sites();
}

/// Ownership ABI and instrumentation identity for persisted native artifacts.
pub fn identity() []const u8 {
    return lowered().identity();
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
    try std.testing.expectEqualStrings("rc-v5", identity());
    set(.rc_counting);
    try std.testing.expect(enabled() and counting() and !sites());
    try std.testing.expectEqualStrings("rc-v5-counting", identity());
    set(.rc_sites);
    try std.testing.expect(enabled() and counting() and sites());
    try std.testing.expectEqualStrings("rc-v5-sites", identity());
}

// spec: RC-RUNTIME-CONTRACT-1
test "runtime contract versions reject unknown ABIs and preserve legacy GC" {
    try std.testing.expectEqual(Selection.gc, try contract.parse("gc-v1"));
    try std.testing.expectEqual(Selection.rc, try contract.parse("rc-v5"));
    try std.testing.expectEqual(Selection.rc_counting, try contract.parse("rc-v5-counting"));
    try std.testing.expectEqual(Selection.rc_sites, try contract.parse("rc-v5-sites"));
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

// spec: RC-DEFAULT-1
test "reference counting is the process default and GC stays a selectable opt-out" {
    try std.testing.expectEqual(Selection.rc, contract.default);
    try std.testing.expectEqual(Selection.rc, try contract.parse(null));
    try std.testing.expectEqual(Selection.gc, try contract.parse("gc-v1"));
    // The default is not explicit: legacy sharing still normalizes it to GC.
    try std.testing.expectEqual(Selection.gc, try contract.resolve(contract.default, false, false));
    try std.testing.expectEqual(Selection.rc, try contract.resolve(contract.default, true, false));
    try std.testing.expectEqual(Selection.gc, try contract.resolve(.gc, true, true));
    try std.testing.expectEqualStrings("rc-v5", contract.default.identity());
    // A build driver names the contract to its frontend child by these flags.
    try std.testing.expectEqualStrings("--gc-runtime", Selection.gc.flag());
    try std.testing.expectEqualStrings("--rc-runtime", Selection.rc.flag());
    try std.testing.expectEqualStrings("--rc-runtime=stats", Selection.rc_counting.flag());
    try std.testing.expectEqualStrings("--rc-runtime=sites", Selection.rc_sites.flag());
}

// spec-case: RC-DEFAULT-1
test "legacy sharing lowers for the collector whatever runtime is selected" {
    const saved = get();
    defer set(saved);
    const mode = values.enabled;
    defer values.enabled = mode;
    set(.rc);
    values.enabled = false;
    try std.testing.expectEqual(Selection.gc, lowered());
    try std.testing.expectEqual(Selection.rc, get());
    try std.testing.expect(!enabled());
    try std.testing.expectEqualStrings("gc-v1", identity());
    values.enabled = true;
    try std.testing.expectEqual(Selection.rc, lowered());
    const pinned = pinCollector();
    try std.testing.expectEqual(Selection.rc, pinned);
    try std.testing.expectEqual(Selection.gc, lowered());
}

// spec-case: RC-RUNTIME-CONTRACT-1
test "ABI5 rejects obsolete counted artifact identities" {
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v3"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v3-counting"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v3-sites"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v4"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v4-counting"));
    try std.testing.expectError(error.InvalidRuntimeContract, contract.parse("rc-v4-sites"));
}
