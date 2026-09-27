//! Versioned, dependency-free native memory ownership contract shared by the
//! frontend and native build driver. Runtime selection is an artifact property.
const std = @import("std");

/// Carrier inherited by compiler children after command-line normalization.
pub const variable = "MYLANG_RUNTIME";

/// The C define every RC artifact compiles with, and the one counting adds.
const rc_flag = "-DMYL_NATIVE_RC=1";
const counting_flag = "-DMYL_NATIVE_RC_COUNTING=1";

/// Memory implementations with distinct ownership and instrumentation identities.
pub const Selection = enum {
    gc,
    rc,
    rc_counting,
    /// Counting RC that also attributes every ownership event to the
    /// emitted call site that caused it (`RC-SITES-1`).
    rc_sites,

    /// Stable native ownership ABI tag; change its version when the ABI changes.
    pub fn identity(self: Selection) []const u8 {
        return switch (self) {
            .gc => "gc-v1",
            .rc => "rc-v3",
            .rc_counting => "rc-v3-counting",
            .rc_sites => "rc-v3-sites",
        };
    }

    /// Native flags shared by loose objects, generated adapters and LTO archives.
    pub fn cFlags(self: Selection) []const []const u8 {
        return switch (self) {
            .gc => &.{},
            .rc => &.{rc_flag},
            .rc_counting => &.{ rc_flag, counting_flag },
            .rc_sites => &.{ rc_flag, counting_flag, "-DMYL_NATIVE_RC_SITES=1" },
        };
    }

    /// Whether this artifact uses reference counting rather than tracing GC.
    pub fn enabled(self: Selection) bool {
        return self != .gc;
    }

    /// Whether this artifact records RC ownership operations.
    pub fn counting(self: Selection) bool {
        return self == .rc_counting or self == .rc_sites;
    }

    /// Whether this artifact also attributes each ownership event to its
    /// emission site (`RC-SITES-1`).
    pub fn sites(self: Selection) bool {
        return self == .rc_sites;
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
