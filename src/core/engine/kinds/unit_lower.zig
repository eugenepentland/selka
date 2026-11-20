//! The `unit-lower` kind (spec §17.2): the lowered form of the functions of one unit.
//!
//! A unit is a module or a generic instance. The argument names it and the one setting lowering reads besides the program: the
//! kind of unit, its name (the module's project-relative path, or the instance function's checked name) and whether debug
//! information is dropped (a release build). The result is, for each function the unit lowers, the digest of its artifact in
//! canonical form (`lowering_cache.canonicalDigest`): Core IR with unit-local type and function ids and local string indexes, the
//! requests it made of the program's tables, and nothing about where the program that lowered it put it. The parts are `fn:<name>`,
//! one per function, so a reader of one function depends on that function alone; the payload lists them.
//!
//! The record reads what lowering reads, as far as lowering reads the program through the front end's results:
//! - the unit's checked bodies, as the `body:<name>` parts of `module-check` for each function of the unit (a generic instance
//!   reads its template's). A part is the digest of the function's stable key, the region of source it was checked from and the
//!   dependency context it was checked in, and that context folds the declarations the body names: a callee's signature, a
//!   record's layout or a default expression the body reaches. So an edit to a function the unit does not lower, in the same
//!   module or another, leaves the record valid. Until the front end computes its results on the engine (G2g) the checked
//!   bodies are read through today's front end, and these parts are the record that they are as they were. A function whose
//!   name has no part (a name the module-check kind does not publish) reads the whole `module-check` result instead;
//! - for a generic instance, the interface of each record its type arguments reach, which no body of the instantiating module
//!   necessarily names;
//! - the parts of the text of every other module a position in the unit's functions points into, up to the last line any
//!   position touches (a position is a file, a line and a column: the lines above it must read the same);
//! - the files the module's embeds name, through `module-check`.
//!
//! In shadow (G3c) today's lowering computes the artifacts and the body returns their digests, with the reads a lowering from
//! those results would make. Nothing the kind reads is a position in the program: every read names a module or a declaration.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");
const interface_kind = @import("module_interface.zig");

/// The parts of one module's text that a unit's positions point into.
pub const Text = struct { path: []const u8, parts: []const []const u8 };

/// The checked bodies a unit lowers, in one module: the module's `module-check` argument and the names of the bodies' parts, or
/// null when the unit reads the whole check.
pub const Check = struct { argument: []const u8, bodies: ?[]const []const u8 };

/// What lowering computed for one unit: the payload, the parts, and everything the record reads.
pub const Answer = struct {
    payload: []const u8,
    parts: []const record.Part,
    /// The checked bodies the unit lowers.
    checks: []const Check,
    /// Names in other modules' interfaces the unit reaches through its type arguments.
    lookups: []const interface_kind.Lookup,
    /// The parts of other modules' text that positions in the unit point into.
    texts: []const Text,
};

/// Where the kind gets lowering's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the kinds whose results and parts it reads.
pub const Data = struct { source: Source, check: *const context.Kind, interface: *const context.Kind, syntax: *const context.Kind };

/// The lowering of the unit named by `argument`, after reading what a lowering of it reads. A unit lowering did not describe
/// fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    for (answer.checks) |check| {
        if (check.bodies) |bodies| _ = try ctx.part(data.check, check.argument, bodies) else _ = try ctx.query(data.check, check.argument);
    }
    for (answer.lookups) |lookup| _ = try ctx.part(data.interface, lookup.path, lookup.names);
    for (answer.texts) |text| _ = try ctx.part(data.syntax, text.path, text.parts);
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}

/// The argument of a module unit.
pub fn moduleArgument(a: std.mem.Allocator, path: []const u8, drop_debug: bool) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "module\x00{s}\x00debug={d}", .{ path, @intFromBool(!drop_debug) });
}

/// The argument of a generic instance unit.
pub fn instanceArgument(a: std.mem.Allocator, name: []const u8, drop_debug: bool) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "instance\x00{s}\x00debug={d}", .{ name, @intFromBool(!drop_debug) });
}

/// `base` (a unit's argument) with the digest of what the program demands of the unit: the functions it lowers, which differ from
/// program to program for a module they share. The digest is computed in the run that asks (D-48), so a record made for one program
/// is the record of every program that demands the same of the unit (G-D13).
pub fn withDemand(a: std.mem.Allocator, base: []const u8, demand: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00demand={s}", .{ base, std.fmt.bytesToHex(demand[0..16], .lower) });
}

test "the argument of a unit names its sort, its name and whether debug information is kept" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqualStrings("module\x00src/a.selka\x00debug=1", try moduleArgument(a, "src/a.selka", false));
    try std.testing.expectEqualStrings("module\x00src/a.selka\x00debug=0", try moduleArgument(a, "src/a.selka", true));
    try std.testing.expectEqualStrings("instance\x00pair<i64>\x00debug=1", try instanceArgument(a, "pair<i64>", false));
}

test "a unit's argument carries the digest of the demand on it, so two programs that demand alike share it and two that do not do not" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const base = try moduleArgument(a, "src/a.selka", false);
    const one = try withDemand(a, base, @splat(1));
    try std.testing.expectEqualStrings("module\x00src/a.selka\x00debug=1\x00demand=01010101010101010101010101010101", one);
    try std.testing.expectEqualStrings(one, try withDemand(a, base, @splat(1)));
    try std.testing.expect(!std.mem.eql(u8, one, try withDemand(a, base, @splat(2))));
}
