//! Copy the backend's small borrowed frontend views before releasing checked trees.
const std = @import("std");
const source = @import("mylang").source;
const ir = @import("ir.zig");

/// Physical instruction/type tables already belong to the result arena. Names
/// and literal slices can still borrow checked source or diagnostic storage.
pub fn retainModule(arena: std.mem.Allocator, module: *ir.Module) std.mem.Allocator.Error!void {
    for (module.functions.items) |*function| function.name = try arena.dupe(u8, function.name);
    for (module.strings.items) |*bytes| bytes.* = try arena.dupe(u8, bytes.*);
}

/// Preserve exact source offsets, line indexes, origin order and embedded bytes.
/// Copies belong to the caller's result arena, including on allocation failure.
pub fn retainSource(arena: std.mem.Allocator, given: source.Source) std.mem.Allocator.Error!source.Source {
    var retained = given;
    retained.path = try arena.dupe(u8, given.path);
    retained.bytes = try arena.dupe(u8, given.bytes);
    retained.line_starts = try arena.dupe(usize, given.line_starts);
    const origins = try arena.alloc(source.Source.Origin, given.origins.len);
    for (origins, given.origins) |*origin, original| origin.* = .{
        .start = original.start,
        .original = try retainSource(arena, original.original),
    };
    retained.origins = origins;
    const embeds = try arena.dupe(source.Embed, given.embeds);
    for (embeds) |*embed| {
        embed.path = try arena.dupe(u8, embed.path);
        embed.contents = try arena.dupe(u8, embed.contents);
    }
    retained.embeds = embeds;
    return retained;
}

/// Entry parameter labels select stream sentinels during native entry emission.
pub fn retainNames(arena: std.mem.Allocator, names: []const []const u8) std.mem.Allocator.Error![]const []const u8 {
    const retained = try arena.alloc([]const u8, names.len);
    for (retained, names) |*name, original| name.* = try arena.dupe(u8, original);
    return retained;
}
