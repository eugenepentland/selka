//! Versioned, dependency-free native memory ownership contract shared by the
//! frontend and native build driver. Runtime selection is an artifact property.
const std = @import("std");

/// Carrier inherited by compiler children after command-line normalization.
pub const variable = "MYLANG_RUNTIME";

/// Memory implementations with distinct ownership and instrumentation identities.
pub const Selection = enum {
    gc,
    rc,
    rc_counting,

    /// Stable native ownership ABI tag; change its version when the ABI changes.
    pub fn identity(self: Selection) []const u8 {
        return switch (self) {
            .gc => "gc-v1",
            .rc => "rc-v1",
            .rc_counting => "rc-v1-counting",
        };
    }

    /// Whether this artifact uses reference counting rather than tracing GC.
    pub fn enabled(self: Selection) bool {
        return self != .gc;
    }

    /// Whether this artifact records RC ownership operations.
    pub fn counting(self: Selection) bool {
        return self == .rc_counting;
    }
};

/// Decode only supported ABI tags; absent selection keeps experimental RC off.
pub fn parse(text: ?[]const u8) error{InvalidRuntimeContract}!Selection {
    const value = text orelse return .gc;
    inline for (std.meta.tags(Selection)) |selection| {
        if (std.mem.eql(u8, value, selection.identity())) return selection;
    }
    return error.InvalidRuntimeContract;
}

/// Preserve legacy GC for inherited RC while rejecting an explicit conflict.
pub fn resolve(selected: Selection, values: bool, explicit: bool) error{IncompatibleRuntime}!Selection {
    if (values or !selected.enabled()) return selected;
    if (explicit) return error.IncompatibleRuntime;
    return .gc;
}
