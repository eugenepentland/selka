//! The `module-syntax` kind (spec §17.2): the parts of one module's syntax.
//!
//! The argument is the module's path relative to the project root (`src/lexer.selka`), or `@stdlib/<path>` for a module the
//! compiler embeds (G-D11: no absolute root is ever part of a key or a read). The kind reads the module's file through the
//! context, so the record is valid while the file's bytes are. It publishes the parts of `core/module_parts.zig` (a digest
//! for the header, each declaration's head, each function's body, the import list, the export directives and the whole
//! text) and its payload is the digest of the bytes read and the import list. A reader that depends on one declaration
//! reads that part (`ctx.part`) and is not invalidated by an edit to another.
//!
//! In shadow (G2a-G2f) the front end has already parsed the module, and the body returns the parts that parse gave; the
//! kind checks that the file it reads is the file that was parsed, by the digest of the bytes, and fails the query when it
//! is not (a file changed between the load and this read), so a record never pairs one version's reads with another's
//! result. Nothing is read for an embedded module: its text is part of the compiler, and the kind's code identity covers it.
const std = @import("std");
const context = @import("../context.zig");
const digest_rules = @import("../digest.zig");
const record = @import("../record.zig");

/// The prefix of the argument of a module the compiler embeds.
pub const embedded_prefix = "@stdlib/";

/// What the front end computed for one module: the digest of its bytes, its payload and its parts.
pub const Answer = struct { source_digest: digest_rules.Digest, payload: []const u8, parts: []const record.Part };

/// Where the kind gets the front end's answer, as `test_exec.Source` does, so this file imports none of the front end's code.
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
};

/// The parts of the module named by `argument`. A module the front end did not parse, and a file that is not the one it
/// parsed, fail the query (`error.Failed`) and store nothing.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const source = ctx.kindData(Source);
    const answer = source.answer(source.context, argument) orelse return error.Failed;
    if (!std.mem.startsWith(u8, argument, embedded_prefix)) {
        const bytes = (try ctx.file(argument)) orelse return error.Failed;
        if (!std.mem.eql(u8, &digest_rules.hash(bytes), &answer.source_digest)) return error.Failed;
    }
    for (answer.parts) |part| try ctx.exposePart(part.name, part.digest);
    return answer.payload;
}
