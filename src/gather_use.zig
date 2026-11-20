//! Recognition of the retired generator consumers during typed migration.
const std = @import("std");

/// Stable retirement diagnostic shared by parsing and typed recognition.
pub const generator_code = "E_GENERATOR_REMOVED";

/// What one gather builds from the values its loop produces.
pub const Use = enum {
    list,
    set,
    dict,
    sum,
    any,
    all,
    min,
    max,

    /// The use a consuming prelude call gives its generator argument, or null
    /// for a call that takes none.
    pub fn consuming(name: []const u8) ?Use {
        inline for (.{ "sum", "any", "all", "min", "max", "set", "dict" }, .{ Use.sum, .any, .all, .min, .max, .set, .dict }) |spelling, use| {
            if (std.mem.eql(u8, name, spelling)) return use;
        }
        if (std.mem.eql(u8, name, "sorted") or std.mem.eql(u8, name, "list")) return .list;
        return null;
    }
    /// Whether the use folds into one scalar instead of building a collection.
    pub fn folds(self: Use) bool {
        return switch (self) {
            .sum, .any, .all, .min, .max => true,
            else => false,
        };
    }
};
