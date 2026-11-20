//! The `module-passes` kind (spec §17.2): what the whole-program passes concluded about each function of a module.
//!
//! The argument is `module-check`'s: the module's project-relative path, a zero byte, and the program flags; for the program's
//! entry module alone it ends with a zero byte and `entry`, because the entry module's `main` is the program's entry point and no
//! other module's is, and the passes state the difference (the stand-in flag of that function, F40). Its
//! parts are `fact:<name>` for every function the module declares: the digest of the function's summary, the cross-function
//! facts the passes read about it (the parameter positions it mutates, where its result may point into its arguments, whether
//! it writes managed storage and whether that storage is fresh). The origin passes judge a body against its own checked tree and
//! its callees' *declared* signatures, never their bodies, so the facts are a function of what `module-check` already holds: the
//! record reads the module's body parts there, and a callee's body edit changes no fact of its callers. Whether the front end's
//! stand-in store may use a function's summary is no fact of it (it depends on the types the whole program names), so it is not
//! published: see `module_passes_facts.zig`.
//!
//! A function of the module that promises `@noalloc` is judged over the bodies of its callees, which this record does not read: it
//! reads the `verdict` of the `noalloc-closure` query of each such function instead (G2i), so an edit to a callee leaves the record
//! valid when the promise still holds. A generic function that promises it is judged where it is instantiated, which is the
//! program's business (`program-diagnostics`). A module with a promise the engine could not record is not recorded. The allocation
//! check of ownership is the `ownership-proof` kind's.
//!
//! It also publishes `warnings`: the digest of the module's diagnostics, each in the module's own coordinates with whatever it
//! points at (G-D6), the lines `program-diagnostics` assembles `check`'s output from. They derive from the module's checked bodies,
//! the callees' declarations and the module's own syntax, so the record also reads the module's text, and the text of any other
//! module a diagnostic of this one points into (a related note, a fix edit).
//!
//! In shadow (G2e, G2f) the front end's summaries and diagnostics are the body, with the reads a computation would make.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");
const noalloc_kind = @import("noalloc_closure.zig");

/// What the front end computed for one module: the payload, the parts, the names of the bodies whose checks it depends on, the
/// modules whose text it depends on (its own, and those its diagnostics point into) and the `noalloc-closure` queries of the
/// promises it declares. `check` is the argument of the module's own `module-check` query, which differs from the passes' argument by
/// the entry marker; empty means the passes' argument.
pub const Answer = struct { payload: []const u8, parts: []const record.Part, bodies: []const []const u8, texts: []const []const u8, noalloc: []const []const u8 = &.{}, check: []const u8 = "" };

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `module-check` kind, whose body parts it reads, `module-syntax`, whose text parts it
/// reads, and `noalloc-closure`, whose verdicts it reads.
pub const Data = struct { source: Source, check: *const context.Kind, syntax: *const context.Kind, noalloc: *const context.Kind };

/// The passes' conclusions for the module named by `argument`, after reading the module's checked bodies. A module the front end
/// did not describe fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    _ = try ctx.part(data.check, if (answer.check.len != 0) answer.check else argument, answer.bodies);
    for (answer.texts) |path| _ = try ctx.part(data.syntax, path, &.{"module"});
    for (answer.noalloc) |root| _ = try ctx.part(data.noalloc, root, &.{noalloc_kind.verdict_part});
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}
