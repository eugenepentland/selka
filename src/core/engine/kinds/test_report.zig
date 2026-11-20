//! The `test-report` kind (spec section 13): the report of an entry's complete, successful `selka test` run, replayed while
//! everything it was made from is as it was.
//!
//! The argument is the run's settings digest (`test_runner_receipt.settings`: it binds the compiler, the toolchain, the
//! cases, the configuration and the keyed environment), the entry's root and the name filter. The kind reads every file the
//! front end read to check the entry (the module sources, the assets they embed, the interface files, the cases file, the
//! configuration), so a changed file is a changed read. Its result is the report of the run that proved every test, with the
//! warnings its check printed; a later run with the same argument and the same files prints that report with every test
//! `cached`, without checking anything.
//!
//! The body does not check anything: it reads the files the front end already read and returns the report the runner
//! computed, which the runner hands the kind through its data (`Source`) when it records one. Since stage 6 of the test-loop
//! plan a module source is read through the `module-tokens` kind instead of by its bytes, unless a warning of the check points
//! into it: a comment edit or a line shift then leaves the report valid (D-TL6-1).
const std = @import("std");
const context = @import("../context.zig");

/// What the runner computed for one report argument: the files its check read by their bytes, the module sources it read
/// through `module-tokens` (test-loop stage 6), and the report document.
pub const Answer = struct { files: []const []const u8, sources: []const []const u8 = &.{}, payload: []const u8 };

/// Where the kind gets the runner's answer, as `test_exec.Source` does, and the `module-tokens` kind its sources are read
/// through (null reads them by their bytes).
pub const Source = struct {
    context: *anyopaque,
    answer: *const fn (context: *anyopaque, argument: []const u8) ?Answer,
    tokens: ?*const context.Kind = null,
};

/// Read the files of the report for `argument`, and its sources through `module-tokens`, and return the report document. A
/// report the runner did not compute fails the query.
pub fn run(ctx: *context.Context, argument: []const u8) context.Error![]const u8 {
    const source = ctx.kindData(Source);
    const found = source.answer(source.context, argument) orelse return error.Failed;
    for (found.files) |path| _ = try ctx.file(path);
    for (found.sources) |path| {
        if (source.tokens) |tokens| _ = try ctx.query(tokens, path) else _ = try ctx.file(path);
    }
    return found.payload;
}
