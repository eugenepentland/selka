//! The user guides `mylang docs` prints, named once for `build.zig` and the command.
//!
//! `build.zig` imports this file to give each page an anonymous import named
//! `import_prefix ++ topic.name`, and `docs_command.zig` embeds the page under
//! that name, so the table below is the only list of topics and a page that
//! moves fails the build instead of the command. The file imports nothing,
//! because `build.zig` compiles it for the build runner.

/// One printable guide: the name `mylang docs NAME` takes, the page under the
/// repository root that is embedded for it, and the line the topic list shows.
pub const Topic = struct { name: []const u8, path: []const u8, summary: []const u8 };

/// The anonymous-import namespace `build.zig` gives the embedded pages.
pub const import_prefix = "user-doc/";

/// Every topic, in the order `mylang docs` lists them: the primer first, then
/// the language, then the tools. The pages stay in `docs/`, where doctest runs
/// their examples; internal records (audits, experiments) are never listed.
pub const topics = [_]Topic{
    .{ .name = "primer", .path = "docs/primer.md", .summary = "mylang in one page for a Python programmer: start here" },
    .{ .name = "syntax", .path = "docs/python-syntax.md", .summary = "the language guide: declarations, statements, types and collections" },
    .{ .name = "statements", .path = "docs/statements.md", .summary = "bindings and scope, assignments, assert and conditions" },
    .{ .name = "records", .path = "docs/records-and-unions.md", .summary = "record, class, union and enum declarations and constructors" },
    .{ .name = "functions", .path = "docs/functions.md", .summary = "def, keyword arguments and defaults, entry points, function values" },
    .{ .name = "errors", .path = "docs/results-and-options.md", .summary = "Result, Option, `?` and `is None` narrowing (no exceptions)" },
    .{ .name = "text", .path = "docs/text.md", .summary = "str methods, slices, format strings and number parsing" },
    .{ .name = "bytes", .path = "docs/bytes.md", .summary = "bytes: indexing, slices, conversions and in-place writes" },
    .{ .name = "io", .path = "docs/io.md", .summary = "print through Stream, debug, arguments, files and run authority" },
    .{ .name = "effects", .path = "docs/effects.md", .summary = "capabilities, effect ceilings and mutation contracts" },
    .{ .name = "contracts", .path = "docs/contracts.md", .summary = "@requires, @ensures and @invariant: checked preconditions, postconditions and invariants" },
    .{ .name = "modules", .path = "docs/modules.md", .summary = "module headers, imports, public declarations and projects" },
    .{ .name = "memory", .path = "docs/managed-memory.md", .summary = "managed lists, dicts and strings; the tracing collector" },
    .{ .name = "sets", .path = "docs/sets.md", .summary = "set[T]: literals, comprehensions, methods, operators and hashable keys" },
    .{ .name = "arenas", .path = "docs/arenas.md", .summary = "`with arena()` regions for bulk allocation" },
    .{ .name = "stdlib", .path = "docs/standard-library.md", .summary = "the standard modules: strings, math, json, sort, time, ..." },
    .{ .name = "tests", .path = "docs/tooling/guest-tests.md", .summary = "mylang test: test_ functions, cases files, benchmarks, caching" },
    .{ .name = "build", .path = "docs/tooling/native-build.md", .summary = "mylang build and run: QBE by default, --release, caches, reports" },
    .{ .name = "navigation", .path = "docs/tooling/navigation.md", .summary = "index-project and tests-for: definitions, uses and reaching tests" },
    .{ .name = "context", .path = "docs/tooling/agent-context.md", .summary = "mylang context: a bounded answer about one declaration" },
    .{ .name = "api", .path = "docs/tooling/interface-files.md", .summary = "mylang api: the generated .api interface file beside every module" },
    .{ .name = "fix", .path = "docs/tooling/fix.md", .summary = "mylang fix: apply the diagnostics' structured fixes; migrations" },
};
