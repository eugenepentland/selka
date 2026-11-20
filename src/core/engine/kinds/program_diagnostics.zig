//! The `program-diagnostics` kind (spec §17.2, G-D6): what `check` prints for a program.
//!
//! The argument is `project-graph`'s: the entry module's name, a zero byte, and the settings that decide how the graph loads. The
//! result is the diagnostics of the whole program as the command renders them: each module's, in the order of the program's
//! modules, each module's in the front end's order. It is assembled from parts, never recomputed: the record reads the graph's
//! `modules` part, which fixes the order, and each module's `warnings` part of `module-passes`, so an edit that leaves every
//! module's warnings as they were leaves the output served, whatever it did to bodies.
//!
//! The front end sorts all of a program's diagnostics once, by merged offset (module order, then the offset in the module), and
//! drops a later diagnostic with the same span and code as an earlier one. Both are properties of a module's own list, because a
//! span never crosses a module, so assembling is concatenation. The three gates of a failing program (a collection error hides
//! every body error, a body error hides the passes, the first ownership refusal in instance order stands alone) decide *which*
//! diagnostics exist; this kind records a program that passed them. A program that did not is not recorded.
//!
//! In shadow (G2h) the front end's rendered text is the body, with the reads of the assembly.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");
const noalloc_kind = @import("noalloc_closure.zig");

/// What the front end computed: the rendered diagnostics, their parts, the `module-passes` arguments in module order, and the
/// `noalloc-closure` queries of the generic functions that promise `@noalloc` and are instantiated in the program.
pub const Answer = struct { payload: []const u8, parts: []const record.Part, modules: []const []const u8, noalloc: []const []const u8 = &.{} };

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `project-graph`, `module-passes` and `noalloc-closure` kinds whose parts it reads.
pub const Data = struct { source: Source, graph: *const context.Kind, passes: *const context.Kind, noalloc: *const context.Kind };

/// The diagnostics of the program named by `argument`, after reading the module order and each module's warnings. A program the
/// front end did not describe fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    _ = try ctx.part(data.graph, argument, &.{"modules"});
    for (answer.modules) |module| _ = try ctx.part(data.passes, module, &.{"warnings"});
    for (answer.noalloc) |root| _ = try ctx.part(data.noalloc, root, &.{noalloc_kind.verdict_part});
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}
