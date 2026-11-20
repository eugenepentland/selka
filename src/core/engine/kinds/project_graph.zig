//! The `project-graph` kind (spec §17.2): which modules a program is made of, and in what order.
//!
//! The argument is the entry module's name, a zero byte, and the settings that decide how a graph loads (the budgets and
//! the header flags). The result is the module list in module-id order (the order the merged source concatenates them in),
//! the list in dependency order, and the two program flags the checker reads (a module named `std_result` is present; the
//! program is more than one file or its one file imports). Its parts are a digest of each of those: `modules`, `order`,
//! `flags`, and `set` (the sorted set of paths, for a reader that does not care about order).
//!
//! The kind reads the `imports` part of each module in the graph (`module-syntax`), so an edit to a declaration or a body
//! leaves the graph valid and an edit to an import list recomputes it. A graph that failed to load (a cycle, a budget, a
//! missing module) is never recorded: the query fails and the front end reports the error as it always did.
//!
//! In shadow (G2a-G2f) the front end has loaded the project, and the body returns the graph it built; the reads are the ones
//! a graph computed from the import lists would make.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");

/// What the front end computed: the payload, the paths of the modules whose import lists it depends on, and the parts.
pub const Answer = struct { payload: []const u8, modules: []const []const u8, parts: []const record.Part };

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `module-syntax` kind, whose parts it reads.
pub const Data = struct { source: Source, syntax: *const context.Kind };

/// The graph for `argument`, after reading the import list of each module in it. A graph the front end did not build fails the
/// query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    for (answer.modules) |path| _ = try ctx.part(data.syntax, path, &.{"imports"});
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}
