//! The user guides `selka docs` prints, named once for `build.zig` and the command.
//!
//! `build.zig` imports this file to give each page an anonymous import named
//! `import_prefix ++ topic.name`, and `docs_command.zig` embeds the page under
//! that name, so the table below is the only list of topics and a page that
//! moves fails the build instead of the command. The file imports nothing,
//! because `build.zig` compiles it for the build runner.

/// One printable guide: the name `selka docs NAME` takes, the page under the
/// repository root that is embedded for it, the line the topic list shows, and
/// whether the list shows it under the pages the guides and `selka reference`
/// point at (`more`) rather than among the guides to read first.
pub const Topic = struct { name: []const u8, path: []const u8, summary: []const u8, more: bool = false };

/// The anonymous-import namespace `build.zig` gives the embedded pages.
pub const import_prefix = "user-doc/";

/// Every topic, in the order `selka docs` lists them: the primer first, then
/// the language, then the tools, then the `more` pages. The pages stay in `docs/`,
/// where doctest runs their examples; internal records (audits, experiments,
/// design notes) are never topics, so no guide may link to one.
pub const topics = [_]Topic{
    .{ .name = "primer", .path = "docs/primer.md", .summary = "selka in one page for a Python programmer: start here" },
    .{ .name = "card", .path = "docs/card.md", .summary = "read before writing Selka: the rules writers trip on, one line each, at most 6,000 characters" },
    .{ .name = "syntax", .path = "docs/python-syntax.md", .summary = "the language guide: declarations, statements, types and collections" },
    .{ .name = "statements", .path = "docs/statements.md", .summary = "bindings and scope, assignments, assert and conditions" },
    .{ .name = "records", .path = "docs/records-and-unions.md", .summary = "record, union and enum declarations and constructors (no class)" },
    .{ .name = "functions", .path = "docs/functions.md", .summary = "func, keyword arguments and defaults, entry points, function values" },
    .{ .name = "errors", .path = "docs/results-and-options.md", .summary = "Result, Option, `try` and `is None` narrowing (no exceptions)" },
    .{ .name = "text", .path = "docs/text.md", .summary = "str functions (`strings.split`), slices, format strings and number parsing" },
    .{ .name = "bytes", .path = "docs/bytes.md", .summary = "bytes: indexing, slices, conversions and in-place writes" },
    .{ .name = "integer-operations", .path = "docs/integer-operations.md", .summary = "bit_and and the shifts, wrapping_* and saturating_* arithmetic, divtrunc, fixed-width literals" },
    .{ .name = "io", .path = "docs/io.md", .summary = "print through Stream, debug, arguments, files and run authority" },
    .{ .name = "effects", .path = "docs/effects.md", .summary = "capabilities as parameters and `@noalloc` allocation contracts" },
    .{ .name = "contracts", .path = "docs/contracts.md", .summary = "@requires, @ensures and @invariant: checked preconditions, postconditions and invariants" },
    .{ .name = "modules", .path = "docs/modules.md", .summary = "imports, public declarations and projects (a module is its file path)" },
    .{ .name = "packages", .path = "docs/tooling/packages.md", .summary = "local packages: the folder layout, `import NAME`, the lock, `selka packages build` and test" },
    .{ .name = "memory", .path = "docs/managed-memory.md", .summary = "managed lists, dicts and strings: one owner, moves and `copy(value)`" },
    .{ .name = "ownership", .path = "docs/ownership-rules.md", .summary = "the ownership rules: moves, borrows, checking layers and diagnostic codes" },
    .{ .name = "concurrency", .path = "docs/concurrency.md", .summary = "tasks: parallel.group and parallel.map, what a task may take, the thread count" },
    .{ .name = "logging", .path = "docs/logging.md", .summary = "the logging module: leveled, typed events, one line each, on a stream the program holds" },
    .{ .name = "sets", .path = "docs/sets.md", .summary = "set[T]: literals, the `sets` functions, operators and hashable keys" },
    .{ .name = "stdlib", .path = "docs/standard-library.md", .summary = "the standard modules: strings, math, json, sort, time, ..." },
    .{ .name = "tests", .path = "docs/tooling/guest-tests.md", .summary = "selka test: test_ functions, cases files, filters, cached results" },
    .{ .name = "build", .path = "docs/tooling/native-build.md", .summary = "selka build and run: LLVM through zig cc, debug or --release, caches, reports" },
    .{ .name = "navigation", .path = "docs/tooling/navigation.md", .summary = "index-project and tests-for: definitions, uses and reaching tests" },
    .{ .name = "context", .path = "docs/tooling/agent-context.md", .summary = "selka context: a bounded answer about one declaration" },
    .{ .name = "api", .path = "docs/tooling/interface-files.md", .summary = "selka api: the generated .api interface file beside every module" },
    .{ .name = "release-docs", .path = "docs/tooling/release-docs.md", .summary = "checked project docs: generated overview, runnable docstrings and release decisions" },
    .{ .name = "change-review", .path = "docs/tooling/change-review.md", .summary = "plain-English change review before a merge: change notes, the review and its gate" },
    .{ .name = "fix", .path = "docs/tooling/fix.md", .summary = "selka fix: apply the diagnostics' structured fixes; migrations" },
    .{ .name = "floating-point", .path = "docs/floating-point.md", .summary = "float and f32: arithmetic, conversions, fma and hypot", .more = true },
    .{ .name = "match-expressions", .path = "docs/match-expressions.md", .summary = "match on a variant: arms, alternatives, the rest marker, exhaustiveness", .more = true },
    .{ .name = "value-semantics", .path = "docs/value-semantics.md", .summary = "the value rules in full: taking and exchanging, long-lived data, consuming a list", .more = true },
    .{ .name = "generics", .path = "docs/generics.md", .summary = "generic functions and types, and the constraints a type parameter may carry", .more = true },
    .{ .name = "generic-inference", .path = "docs/generic-inference.md", .summary = "which type arguments a generic call may leave out", .more = true },
    .{ .name = "const-length-generics", .path = "docs/const-length-generics.md", .summary = "constant length parameters: FixedArray[T, N] and bounded lengths", .more = true },
    .{ .name = "c-ffi", .path = "docs/c-ffi.md", .summary = "extern func: calling C from a native build; project links and the C of packages", .more = true },
    .{ .name = "module-constants", .path = "docs/module-constants.md", .summary = "immutable scalar module constants and what may initialize one", .more = true },
    .{ .name = "source-evaluation", .path = "docs/source-evaluation.md", .summary = "constants that are tables, and the bounded evaluation that builds them", .more = true },
    .{ .name = "range-iteration", .path = "docs/range-iteration.md", .summary = "for over range(...): bounds, steps and what the loop variable is", .more = true },
    .{ .name = "tuples", .path = "docs/tuples.md", .summary = "tuples are removed (E_TUPLE_REMOVED): what to write instead", .more = true },
    .{ .name = "typed-holes", .path = "docs/typed-holes.md", .summary = "typed holes: marked missing code, a located diagnostic while the rest still checks", .more = true },
    .{ .name = "type-aliases", .path = "docs/type-aliases.md", .summary = "transparent type aliases: another spelling for a type", .more = true },
    .{ .name = "typed-json", .path = "docs/typed-json.md", .summary = "the JSON the compiler derives for a project's exported types", .more = true },
    .{ .name = "simd", .path = "docs/simd.md", .summary = "Simd[T, N]: float, integer and mask lanes, and the simd module", .more = true },
    .{ .name = "python-text-surface", .path = "docs/python-text-surface.md", .summary = "sorting and comparing bytes and str the way Python does", .more = true },
    .{ .name = "structured-loop-exits", .path = "docs/structured-loop-exits.md", .summary = "break and continue: the loop they leave and where they may stand", .more = true },
    .{ .name = "diagnostic-recovery", .path = "docs/diagnostic-recovery.md", .summary = "one check reports the first fault of each function independently", .more = true },
    .{ .name = "lint", .path = "docs/tooling/lint.md", .summary = "selka lint: the rules, their codes, and the repairs fix applies", .more = true },
    .{ .name = "rename", .path = "docs/tooling/rename.md", .summary = "selka rename: one declaration and every use the compiler resolves to it", .more = true },
    .{ .name = "formatter", .path = "docs/tooling/formatter.md", .summary = "selka fmt: the one canonical layout; --check, --write, --diff", .more = true },
    .{ .name = "runtime-budgets", .path = "docs/tooling/runtime-budgets.md", .summary = "instruction, frame and byte budgets that bound a run", .more = true },
    .{ .name = "cost", .path = "docs/tooling/cost.md", .summary = "selka cost: the static per-function cost report", .more = true },
    .{ .name = "import-policy", .path = "docs/tooling/import-policy.md", .summary = "the import-direction policy a project's selka.json makes mandatory", .more = true },
    .{ .name = "api-diff", .path = "docs/tooling/api-diff.md", .summary = "selka api-diff: classify a change to the published interface", .more = true },
};

/// The topic that prints the page at `path` (repository relative, as `docs/tooling/packages.md`), or null when no
/// topic shows that page. Compared byte by byte so this file keeps importing nothing.
pub fn topicForPath(path: []const u8) ?Topic {
    for (topics) |topic| {
        if (sameBytes(topic.path, path)) return topic;
    }
    return null;
}

fn sameBytes(left: []const u8, right: []const u8) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| {
        if (a != b) return false;
    }
    return true;
}
