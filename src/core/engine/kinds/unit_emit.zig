//! The `unit-emit` kind (spec §17.2, step G4a): the LLVM text of one unit.
//!
//! The argument names the unit (a module by its path, any other unit by the key of its first function), the emission mode and the
//! digest of what the program supplies to the unit's emission (G-D13): the unit's linkage, the reference digest, symbol and effects of
//! every function it calls, its source positions and inline ancestry, and the options the build emits under. The same input
//! digest comes from the compact key of the emitter (`emission_key.Compact`), which binds nothing but what the unit reads. The
//! result is the digest of the unit's text.
//!
//! The record reads the `opt:<function>` parts of the `unit-optimize` result of each function the unit holds, and nothing whose
//! argument names a program. The positions the text carries are in the argument, not in those parts: until the optimizer's records
//! are position-free end to end, emission's keys keep covering positions (G-D14), so a line shift moves the argument of every unit
//! of the module it happens in and leaves every other unit's argument as it was.
//!
//! In shadow (G4a step 3) the emitter's units are the result, with the reads of an emission from the optimizer's results.
const std = @import("std");
const context = @import("../context.zig");

/// The parts of one `unit-optimize` result that a unit's emission reads: the optimization's argument and the names of the parts
/// (`opt:<function>`) of the unit's functions in it.
pub const Read = struct { argument: []const u8, parts: []const []const u8 };

/// What the emitter made of one unit: the payload and the optimizer parts its emission reads.
pub const Answer = struct { payload: []const u8, optimized: []const Read };

/// Where the kind gets the emitter's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `unit-optimize` kind it reads.
pub const Data = struct { source: Source, optimize: *const context.Kind };

/// The first line of every unit's payload.
pub const payload_magic = "selka-unit-emit-v1";

/// The text of the unit named by `argument`, after reading what an emission of it reads. A unit the emitter did not describe fails
/// the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    for (answer.optimized) |read| _ = try ctx.part(data.optimize, read.argument, read.parts);
    return answer.payload;
}

/// The argument of a unit's emission: the unit's name, the mode and the digest of what the program supplies.
pub fn argumentOf(a: std.mem.Allocator, unit: []const u8, mode: []const u8, input: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00emit={s}\x00in={s}", .{ unit, mode, std.fmt.bytesToHex(input[0..16], .lower) });
}

/// The payload that says a unit's text has the digest `text`.
pub fn payloadOf(a: std.mem.Allocator, text: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\n{s}\n", .{ payload_magic, std.fmt.bytesToHex(text, .lower) });
}

test "the argument of a unit's emission is its name, the mode and the digest of what the program supplies" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("module:a.selka\x00emit=debug\x00in=05050505050505050505050505050505", try argumentOf(arena.allocator(), "module:a.selka", "debug", @splat(5)));
}

test "the payload of a unit's emission carries the digest of its text" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const payload = try payloadOf(arena.allocator(), @splat(0xab));
    try std.testing.expect(std.mem.startsWith(u8, payload, payload_magic ++ "\n" ++ "abab"));
}
