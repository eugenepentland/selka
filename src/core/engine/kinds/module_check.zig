//! The `module-check` kind (spec §17.2): which bodies of a module are checked, and under what each was checked.
//!
//! The argument is the module's project-relative path, a zero byte, and the two program-wide flags the checker reads
//! (`std_result=0;module_graph=1`; a flag that changes is another query, not a change to read). Its parts are `body:<name>` for
//! every function the module declares: the digest of the function's validity key, the region of source it was checked from and
//! the dependency context it was checked in (the digest the front end's checked-body store keys a stored body by), so a reader
//! that depends on one body depends on that body alone.
//!
//! The record reads the module's whole text (`module-syntax`'s `module` part) and its heads, import list and exports, and
//! every name its bodies look up in other modules as projection reads of those modules' `module-interface` (a name not found
//! is read as absent), and every file an `embed_bytes` or `embed_str` call in the module names. So an edit to another module
//! that leaves the names this module's bodies use as they were leaves the record valid: a callee's body edit does not
//! recheck its callers.
//!
//! In shadow (G2c) the front end computes the keys and the body returns them, with the reads a computation would make.
//! Generic instances are not covered: they are bodies of the templates' modules instantiated here, and belong to a kind of
//! their own.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");
const interface_kind = @import("module_interface.zig");

/// What the front end computed for one module: the payload, the parts, the names its bodies look up elsewhere, and the files
/// its embed calls name (project-relative).
pub const Answer = struct {
    payload: []const u8,
    parts: []const record.Part,
    lookups: []const interface_kind.Lookup,
    files: []const []const u8,
};

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `module-syntax` kind and the `module-interface` kind whose parts it reads.
pub const Data = struct { source: Source, syntax: *const context.Kind, interface: *const context.Kind };

/// The names of the module-syntax parts every check depends on: the whole text, the heads, the import list, the exports.
pub const syntax_parts = [_][]const u8{ "exports", "heads", "imports", "module" };

/// The module path in a query's argument: what comes before the zero byte.
pub fn pathOf(argument: []const u8) []const u8 {
    return argument[0 .. std.mem.indexOfScalar(u8, argument, 0) orelse argument.len];
}

/// The check of the module named by `argument`, after reading what a computation of it reads. A module the front end did not
/// check fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    _ = try ctx.part(data.syntax, pathOf(argument), &syntax_parts);
    for (answer.lookups) |lookup| _ = try ctx.part(data.interface, lookup.path, lookup.names);
    for (answer.files) |path| _ = try ctx.file(path);
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}

test "the module path of an argument is what precedes the zero byte" {
    try std.testing.expectEqualStrings("src/a.selka", pathOf("src/a.selka\x00std_result=0"));
    try std.testing.expectEqualStrings("src/a.selka", pathOf("src/a.selka"));
}
