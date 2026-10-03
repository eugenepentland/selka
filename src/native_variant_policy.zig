//! Backend selection for the checked native variant implementation.
const std = @import("std");

/// A lowering choice; original is every standalone emission API's default.
pub const Policy = enum {
    original,
    qbe_v2,

    /// Only a resolved QBE backend with the current producer enables V2.
    pub fn forBackend(llvm: bool, foreign: bool) Policy {
        return if (llvm or foreign) .original else .qbe_v2;
    }

    /// Versioned emission/cache identity; original keeps the old encoding.
    pub fn identity(self: Policy) []const u8 {
        return if (self == .original) "" else "native-variant-qbe-v2";
    }

    /// The module-interface configuration suffix of an enabled policy.
    pub fn suffix(self: Policy) []const u8 {
        return if (self == .original) "" else " native-variant=qbe-v2";
    }

    /// A checked-emission flag, never handed to a foreign producer by default.
    pub fn flag(self: Policy) ?[]const u8 {
        return if (self == .original) null else "--native-variants=qbe-v2";
    }

    /// Internal emission spelling; unknown values are a usage error.
    pub fn parse(text: []const u8) ?Policy {
        if (std.mem.eql(u8, text, "original")) return .original;
        if (std.mem.eql(u8, text, "qbe-v2")) return .qbe_v2;
        return null;
    }
};
