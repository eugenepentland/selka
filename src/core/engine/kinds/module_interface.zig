//! The `module-interface` kind (spec §17.2): what a module declares that another module can see, one part per name.
//!
//! The argument is the module's project-relative path. Its parts are `name:<key>` for every name the module binds (a free
//! declaration, a `Domain.member`, a facade's re-export), and each part's digest covers the declarations the name stands for
//! and everything they reach: a declaration's text, its visibility, and, through the names it looks up in the modules it
//! imports, those names' own digests. A reader that uses a name depends on that name's part, and an edit to a function's body,
//! or to a declaration the reader never names, leaves it valid.
//!
//! The kind reads the module's own declarations through `module-syntax`'s `heads` part (the text of every declaration head, not
//! a body), its import list and its export directives, and for each other module whose names it looks up, those names as
//! projection reads of that module's `module-interface`. A name looked up and not found is read as absent, so a later
//! declaration of it is a change. A constant whose value a function body computes holds that value in its digest, so the kind
//! also reads the whole text (`module`) of every module that declares a body the module's constants evaluate: an edit of such
//! a body recomputes the interface, and the readers of the constant are rebuilt only when its value changed (CONSTSTALE).
//!
//! In shadow (G2b-G2f) the front end computes the digests from its own declaration graph and the body returns them, with
//! the reads a computation from those parts would make.
const std = @import("std");
const context = @import("../context.zig");
const record = @import("../record.zig");

/// The names one module's interface looks up in another module, as the parts they are published as there.
pub const Lookup = struct { path: []const u8, names: []const []const u8 };

/// What the front end computed for one module: the payload, the parts, the other modules' names it looked up, and the modules
/// whose whole text its constants' values were computed from (the bodies a constant evaluates, CONSTSTALE).
pub const Answer = struct { payload: []const u8, parts: []const record.Part, lookups: []const Lookup, evaluated: []const []const u8 = &.{} };

/// Where the kind gets the front end's answer.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// What the kind needs besides the answer: the `module-syntax` kind whose parts it reads.
pub const Data = struct { source: Source, syntax: *const context.Kind };

/// The names of the module-syntax parts every interface depends on: the text of the declarations, the import list, the exports.
pub const syntax_parts = [_][]const u8{ "exports", "heads", "imports" };

/// The module-syntax part read of a module whose bodies a constant evaluates: its whole text, since a body edit there may
/// change the constant's value, which the constant's name part holds.
pub const evaluated_parts = [_][]const u8{"module"};

/// The interface of the module named by `argument`, after reading what a computation of it reads. A module the front end did
/// not describe fails the query and stores nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const data = ctx.kindData(Data);
    const answer = data.source.answer(data.source.context, argument) orelse return error.Failed;
    _ = try ctx.part(data.syntax, argument, &syntax_parts);
    for (answer.lookups) |lookup| _ = try ctx.part(ctx.frame.kind, lookup.path, lookup.names);
    for (answer.evaluated) |path| _ = try ctx.part(data.syntax, path, &evaluated_parts);
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}
