//! The `program-facts` kind (spec §17.2, §17.6, step G3h): what the optimizer joins across functions, one part per function and
//! fact.
//!
//! The optimizer reads a few things about the whole program: how far each function's arguments range over all its callers
//! (`params:<fn>`; a function whose address is taken, or that nobody calls, has no hull), the interval each function returns
//! (`returns:<fn>`), what each function does to its parameters and may answer (`effects:<fn>`), the interval of every record field
//! any write stores (`fields`), whether the program holds a function value at all (`closed`, which decides the consuming calling
//! convention), the runtime helpers the program declares (`helpers`) and the entry (`entry`). A reader of one function's facts
//! reads those parts, never the whole result: an edit that leaves a function's facts as they were leaves its dependents valid.
//!
//! The argument is the entry and the optimizer settings that decide the facts (mode and facts on or off). The record reads the
//! `unit-lower` result of every unit, as one query read each: the cost of a program-level kind is a record open and a comparison
//! per unit (§17.6). Until `unit-lower` publishes a smaller summary of its functions (a part per function that holds only what
//! the joins consume), any change to a unit's lowered functions recomputes the facts, and the early cutoff is the facts' own: a
//! recomputation whose parts all agree leaves `unit-optimize` served.
//!
//! In shadow (G3h) the optimizer's joins are the body, digested per function at the point the optimizer finishes them.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");

/// What the optimizer joined: the payload, the parts, and the `unit-lower` arguments of the program's units.
pub const Answer = struct { payload: []const u8, parts: []const record.Part, units: []const []const u8 };

/// Where the kind gets the optimizer's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `unit-lower` kind it reads.
pub const Data = struct { source: Source, lower: *const context.Kind };

/// The facts of the program named by `argument`, after reading the lowered result of every unit. A program the optimizer did not
/// describe fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    for (answer.units) |unit| _ = try ctx.query(data.lower, unit);
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}

/// The argument of a program: its entry, the settings the facts depend on and the digest of the units it reads (their
/// arguments, sorted), so a change of the program's units is another query and not a record that still holds (G-D13).
pub fn argumentOf(a: std.mem.Allocator, entry: []const u8, mode: []const u8, facts_on: bool, units: [32]u8) std.mem.Allocator.Error![]const u8 {
    return std.fmt.allocPrint(a, "{s}\x00mode={s}\x00facts={d}\x00units={s}", .{ entry, mode, @intFromBool(facts_on), std.fmt.bytesToHex(units[0..16], .lower) });
}

test "the argument of a program names its entry, the optimizer mode, whether facts are on and the units it reads" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try std.testing.expectEqualStrings("main\x00mode=trusted\x00facts=1\x00units=02020202020202020202020202020202", try argumentOf(arena.allocator(), "main", "trusted", true, @splat(2)));
}
