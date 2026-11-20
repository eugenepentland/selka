//! The `noalloc-closure` kind (spec §17.2, G2i): whether one `@noalloc` function keeps its promise, judged over the bodies of every
//! function Core reaches from it.
//!
//! The argument names the root: the project-relative path of the module that declares it, a unit separator, its name in the program
//! (an instance of a generic function carries its type arguments), a zero byte and the program flags, as `module-check`'s do. The
//! promise is the only whole-program question that reads callee *bodies* (G0b FE2-15, FE2-31): Core lowers the root and everything it
//! calls and looks for a site that may allocate. So the record reads, as parts of `module-check`, the body of every function in that
//! closure (and nothing else of theirs): an edit to a body outside it leaves the record valid, and an edit inside it, even to a
//! callee in another module, recomputes the query and nothing above it unless the verdict moved.
//!
//! The one part, `verdict`, is the digest of the answer. A root that breaks its promise is not recorded: the check fails with
//! `E_NOALLOC_ALLOCATES` and, as for every other kind, a failing program stores nothing. A root whose closure cannot be tied to
//! declarations of the program (a function Core made that no source region owns) is not recorded either, rather than recorded with
//! reads that are too few.
//!
//! In shadow (G2i) the front end's check of the promise is the body, with the reads a computation would make.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");

/// The bodies of one module that a root's closure contains: the `module-check` query that states them, and their part names.
pub const Reads = struct { argument: []const u8, names: []const []const u8 };

/// What the front end computed for one root: the payload, the verdict part, and the bodies its closure holds.
pub const Answer = struct { payload: []const u8, parts: []const record.Part, bodies: []const Reads };

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `module-check` kind whose body parts it reads.
pub const Data = struct { source: Source, check: *const context.Kind };

/// The name of the part a root's verdict is published as.
pub const verdict_part = "verdict";

/// The verdict on the root named by `argument`, after reading the body of every function of its closure. A root the front end did
/// not describe fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    for (answer.bodies) |reads| _ = try ctx.part(data.check, reads.argument, reads.names);
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}

test "the verdict part is named once" {
    try std.testing.expectEqualStrings("verdict", verdict_part);
}
