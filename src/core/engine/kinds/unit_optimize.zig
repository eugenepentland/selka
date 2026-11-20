//! The `unit-optimize` kind (spec §17.2, step G3e, G-D13): the optimized form of the functions of one unit.
//!
//! The argument is the unit's `unit-lower` argument, the optimizer mode and the digest of what a program supplies to the
//! unit's optimization: the arguments of the lowered units it reads (its own and those of every function inlined into it) and the
//! values of the facts it reads (the parameter hull, return interval and effects of its functions, the return interval and effects
//! of the functions its final bodies call, and the program-wide intervals of fields, whether the program is closed and the runtime
//! helpers). The result is, for each function the unit owns, the digest of its final body in canonical form without source positions
//! (`opt:<name>`); consumers relocate positions from the run's module lines.
//!
//! The record reads the lowered result of each unit its argument names, and nothing whose argument names a program: a record made
//! for one program is the record of every program whose argument it is. The facts are values in the argument, not a read of
//! `program-facts`.
//!
//! In shadow (G3e) the optimizer's final bodies are the result, with the reads of a computation from those results.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");

/// What the optimizer made of one unit: the payload, the parts, and the `unit-lower` arguments the record reads.
pub const Answer = struct {
    payload: []const u8,
    parts: []const record.Part,
    /// The `unit-lower` arguments read whole.
    lowered: []const []const u8,
};

/// Where the kind gets the optimizer's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `unit-lower` kind it reads.
pub const Data = struct { source: Source, lower: *const context.Kind };

/// The optimized form of the unit named by `argument`, after reading what an optimization of it reads. A unit the optimizer did not
/// describe fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    for (answer.lowered) |unit| _ = try ctx.query(data.lower, unit);
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}

/// The argument of a unit's optimization: the unit's lowering argument, the optimizer mode and the digest of what the program
/// supplies (the lowered units read and the facts values read).
pub fn argumentOf(a: std.mem.Allocator, unit: []const u8, mode: []const u8, supplied: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00opt={s}\x00in={s}", .{ unit, mode, std.fmt.bytesToHex(supplied[0..16], .lower) });
}

test "the argument of a unit's optimization is its lowering argument, the mode and the digest of what the program supplies" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("module\x00a.selka\x00debug=1\x00opt=trusted\x00in=03030303030303030303030303030303", try argumentOf(arena.allocator(), "module\x00a.selka\x00debug=1", "trusted", @splat(3)));
}
