//! Versioned, dependency-free native memory ownership contract shared by the
//! frontend and native build driver. Runtime selection is an artifact property.
const std = @import("std");

/// Backend emission policy shared across compiler and native-driver modules.
pub const native_variants = @import("native_variant_policy.zig");

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
            .rc => "rc-v5",
            .rc_counting => "rc-v5-counting",
            .rc_sites => "rc-v5-sites",
        };
    }

    /// The command-line flag that selects this contract explicitly, which a
    /// build driver hands its frontend child (`RC-DEFAULT-1`).
    pub fn flag(self: Selection) []const u8 {
        return switch (self) {
            .gc => "--gc-runtime",
            .rc => "--rc-runtime",
            .rc_counting => "--rc-runtime=stats",
            .rc_sites => "--rc-runtime=sites",
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

/// The contract a process runs when neither a runtime flag, `--gc-stress` nor
/// `MYLANG_RUNTIME` names one: reference counting (`RC-DEFAULT-1`). Only the
/// resolved selection reaches caches, so changing it never reuses artifacts
/// built under another contract.
pub const default: Selection = .rc;

/// Decode only supported ABI tags; an absent selection is the process default.
pub fn parse(text: ?[]const u8) error{InvalidRuntimeContract}!Selection {
    const value = text orelse return default;
    inline for (std.meta.tags(Selection)) |selection| {
        if (std.mem.eql(u8, value, selection.identity())) return selection;
    }
    return error.InvalidRuntimeContract;
}

/// Preserve legacy GC for inherited or default RC while rejecting an explicit conflict.
pub fn resolve(selected: Selection, values: bool, explicit: bool) error{IncompatibleRuntime}!Selection {
    if (values or !selected.enabled()) return selected;
    if (explicit) return error.IncompatibleRuntime;
    return .gc;
}

/// Backend-specific checked scalar instruction selection.
pub const scalars = @import("scalar_lowering_policy.zig");
