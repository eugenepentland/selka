//! Shared canonical constructor spellings for ordinary and symbolic checking.
const std = @import("std");
const typed = @import("typed.zig");

/// Map familiar contextual constructors onto the stable variant schema names.
pub fn caseName(name: []const u8) []const u8 {
    inline for (.{ "Ok", "Err", "Some", "None" }, .{ "ok", "err", "some", "none" }) |surface, canonical| {
        if (std.mem.eql(u8, name, surface)) return canonical;
    }
    return name;
}

/// Payload and tags for a closed optional value with some and none cases.
pub const OptionShape = struct { element: typed.Type, some: usize, none: usize };

/// Recognize optional values without conflating them with checked errors.
pub fn optionShape(ty: typed.Type, records: []const typed.Record) ?OptionShape {
    if (!ty.isAggregate()) return null;
    const variants = records[ty.recordIndex()].shape.variants orelse return null;
    if (!variants.is_union or variants.fallible or variants.cases.len != 2) return null;
    var result: OptionShape = undefined;
    var found: u2 = 0;
    for (variants.cases, 0..) |variant, i| {
        if (std.mem.eql(u8, variant.name, "some") and variant.payload != null) {
            result.element = variant.payload.?;
            result.some = i;
            found |= 1;
        } else if (std.mem.eql(u8, variant.name, "none") and variant.payload == null) {
            result.none = i;
            found |= 2;
        }
    }
    return if (found == 3) result else null;
}

/// Number of type arguments for ordinary prelude collection and result types.
pub fn arity(name: []const u8) ?usize {
    inline for (.{ "list", "List", "Option" }) |one| if (std.mem.eql(u8, name, one)) return 1;
    inline for (.{ "dict", "Result" }) |two| if (std.mem.eql(u8, name, two)) return 2;
    return null;
}
/// Nonprimitive builtin names accepted by exported module signatures.
pub fn scalar(name: []const u8) bool {
    return std.mem.eql(u8, name, "str") or std.mem.eql(u8, name, "float");
}
