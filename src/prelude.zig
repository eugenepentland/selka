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
    inline for (.{ "list", "Option", "Cell" }) |one| if (std.mem.eql(u8, name, one)) return 1;
    inline for (.{ "dict", "Result", "DictItem", "DictKeys", "DictValues", "DictItems" }) |two| if (std.mem.eql(u8, name, two)) return 2;
    return null;
}
/// Python spellings of the injected host capabilities and open file handles,
/// used only when no declared type claims the name, so an ordinary `Clock`
/// record still wins inside its own module.
pub fn reservedType(name: []const u8) ?typed.Type {
    inline for (.{ "Filesystem", "Network", "Clock", "Entropy", "Environment", "Host", "Stream", "File", "TextFile" }, .{
        typed.Type.filesystem_cap,
        typed.Type.network_cap,
        typed.Type.clock_cap,
        typed.Type.random_cap,
        typed.Type.environment_cap,
        typed.Type.host_cap,
        typed.Type.stream_cap,
        typed.Type.file,
        typed.Type.text_file,
    }) |surface, ty| {
        if (std.mem.eql(u8, name, surface)) return ty;
    }
    return null;
}
/// Python spelling of a reserved capability or open-handle type, or null for
/// an ordinary scalar whose internal tag is already its source spelling.
pub fn reservedTypeName(ty: typed.Type) ?[]const u8 {
    return switch (ty) {
        .filesystem_cap => "Filesystem",
        .network_cap => "Network",
        .clock_cap => "Clock",
        .random_cap => "Entropy",
        .environment_cap => "Environment",
        .file => "File",
        .text_file => "TextFile",
        else => null,
    };
}
/// Nonprimitive builtin names accepted by exported module signatures. The
/// mutable octet buffer belongs here beside `bytes`: a module's public surface
/// may name it without importing a declaration, exactly as it names `str`.
pub fn scalar(name: []const u8) bool {
    if (std.mem.eql(u8, name, "str") or std.mem.eql(u8, name, "bytes") or std.mem.eql(u8, name, "float")) return true;
    if (std.mem.eql(u8, name, "byte_buffer")) return true;
    return reservedType(name) != null;
}
