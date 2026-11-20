//! How a checked name reads when a person sees it.
//!
//! A checked function or record name carries its module (`app::put`) and, for a
//! generic instance, its type arguments in brackets (`app::put[app::Value]`,
//! `app::Box<app::Value>`). The type arguments hold module qualifiers of their own,
//! so a split at the last `::` of the whole name cuts inside them and leaves
//! `Value]`. These helpers search the head only (the text before the first `[` or
//! `<`), and `readable` also drops the qualifiers inside the arguments, so a
//! diagnostic or a printed value names an instance the way the source names its
//! parts: `put[Value]`.
const std = @import("std");
const typed = @import("typed.zig");

/// Where the type arguments of an instance name begin: the first `[` or `<`, or
/// the length of the name when it has none.
fn argumentsStart(name: []const u8) usize {
    return std.mem.indexOfAny(u8, name, "[<") orelse name.len;
}

/// The name without the module qualifier of its head. Only the head is searched,
/// so a `::` inside the type arguments never ends the qualifier early; the type
/// arguments come back as they were spelled, qualifiers included.
pub fn local(name: []const u8) []const u8 {
    const head = name[0..argumentsStart(name)];
    return if (std.mem.lastIndexOf(u8, head, "::")) |at| name[at + 2 ..] else name;
}

/// The module qualifier of the head of a name, or empty when it has none.
pub fn module(name: []const u8) []const u8 {
    const head = name[0..argumentsStart(name)];
    return if (std.mem.indexOf(u8, head, "::")) |at| name[0..at] else "";
}

/// The name as a reader writes it: no module qualifier on its head and none on any
/// type argument, so `app::put[app::Value]` reads `put[Value]`. A name without
/// type arguments is returned as a slice of `name`; one with them is copied into
/// `allocator`, which owns the result.
pub fn readable(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    const bare = local(name);
    if (std.mem.indexOf(u8, bare, "::") == null) return bare;
    var out = try std.ArrayList(u8).initCapacity(allocator, bare.len);
    errdefer out.deinit(allocator);
    // Where the qualified name being copied began in `out`; a `::` removes what was copied since.
    var segment: usize = 0;
    var at: usize = 0;
    while (at < bare.len) {
        if (bare[at] == ':' and at + 1 < bare.len and bare[at + 1] == ':') {
            out.shrinkRetainingCapacity(segment);
            at += 2;
            continue;
        }
        try out.append(allocator, bare[at]);
        at += 1;
        switch (bare[at - 1]) {
            '[', ']', '<', '>', ',', '(', ')', ' ', '?' => segment = out.items.len,
            else => {},
        }
    }
    return out.toOwnedSlice(allocator);
}

/// `readable`, spelled as the source spells it, for a message (`typed.messageTypeText`): the instance of `put[T]` for `int`
/// is `put[int]`, not the checked name `put[i64]`, the record `Box<f64>` is `Box[float]` and `Box<List<i64>>` is `Box[int[]]`. A name with nothing to respell
/// (no type arguments and no `i64` or `f64`) comes back as `readable` returns it, with no allocation of its own. The
/// guest's printed values use `printed`.
pub fn spelled(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    const plain = try readable(allocator, name);
    const respelled = std.mem.indexOfAny(u8, plain, "<>,") != null or std.mem.indexOf(u8, plain, "i64") != null or std.mem.indexOf(u8, plain, "f64") != null;
    if (!respelled) return plain;
    const surface = try typed.surfaceTypeText(allocator, plain);
    defer allocator.free(surface);
    // The copy `readable` made of an instance name is not wanted any more; a slice of `name` is not ours to free.
    release(allocator, plain, name);
    return typed.messageTypeText(allocator, surface);
}

/// The name a printed value shows: `readable`'s name with the type arguments of a generic instance spelled as the source writes
/// them, so `app::Pair<i64,str>` prints `Pair[int, str]` and `Holder<List<i64>>` prints `Holder[int[]]` (`typed.sourceTypeSpelling`).
/// A name that is no generic instance is returned as `readable` returns it, a slice of `name` that allocates nothing.
pub fn printed(allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error![]const u8 {
    const plain = try readable(allocator, name);
    if (std.mem.indexOfScalar(u8, plain, '<') == null) return plain;
    const surface = try typed.sourceTypeSpelling(allocator, plain);
    release(allocator, plain, name);
    return surface;
}

/// Give back what `spelled` (or `readable`) returned for `name` when the caller used it only to format a message and its
/// allocator is not an arena: a result that is a slice of `name` was never allocated and is left alone.
pub fn release(allocator: std.mem.Allocator, result: []const u8, name: []const u8) void {
    const borrowed = @intFromPtr(result.ptr) >= @intFromPtr(name.ptr) and @intFromPtr(result.ptr) < @intFromPtr(name.ptr) + name.len;
    if (!borrowed) allocator.free(result);
}
