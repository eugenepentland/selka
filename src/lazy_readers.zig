//! The audit of who reads the merged program's node and statement tables.
//!
//! A program served lazily (`SELKA_LAZY_SYNTAX`, the default; `lazy_loader.zig`) has full-length `ast.Program.nodes` and `statements`
//! whose function bodies are filled when something asks (`ast.ensureBody`, `ensureModule`, `ensureAll`, `scanAt`). A ReleaseFast compiler
//! fills nothing else: a reader that indexes a table without a hook, and without one of the other reasons below, reads whatever the
//! arena held, silently. The Debug compiler and any run with `SELKA_ENGINE_VERIFY` fill the unread bodies with a sentinel, which finds
//! a missed hook only on a path some test runs.
//!
//! This file is the rest of the answer. `lazy_readers_test.zig` fails for any file under `src/` that reads the tables and is not in
//! `audited` below, so a new reader cannot appear unaudited: whoever adds one reads `Safety`, picks the reason that is true, and names
//! it in `via`. It also fails for an entry whose file no longer reads the tables, for a `hooked` entry that calls no hook, and for an
//! entry that is out of order or has no reason. Adding an entry is a claim that the reads are safe: say how.
//!
//! A file *reads the tables* when it spells `.nodes.items` or `.statements.items` (the list form of `ast.Program`'s tables), or names the
//! `ast` module and spells a `.nodes` or `.statements` field. The rule is textual and errs towards listing: a file that reads another
//! structure with a field of that name is listed as `other_table`.

const std = @import("std");

/// Why a file's reads of the tables are safe while bodies are filled on demand.
pub const Safety = enum {
    /// It calls a hook itself (`ast.ensureBody`, `ensureModule`, `ensureAll` or `scanAt`) before it reads a body, or returns first on the
    /// module facts (`ast.Retired`). Checked: the file must contain a call to a hook.
    hooked,
    /// It is an internal of the checker: entered from `Checker.checkFunction` or `checkInstance` after `sema.zig` filled the body, or from
    /// `generic_bodies`' symbolic check (itself hooked), so the body it reads is filled.
    checker,
    /// It reads only trees outside every lazy body (parameter and field defaults, a constant's body, the root statement of each body, all
    /// written at merge), or only the lengths of the tables.
    declaration_level,
    /// It runs only in a session that reads every module whole: a command that completes the program (`Session.completeProgram`: every
    /// command of `main.zig` outside the check family), or a caller of `interfaces.build*` without a lazy mode (the default is eager).
    eager,
    /// It runs only for a program that holds a retired construct (or a lambda), which `project_syntax.build` loads completely.
    retired_complete,
    /// It parses the source itself and reads that parse, a complete program with no loader.
    fresh_parse,
    /// It builds, copies, serializes or fills the tables: the parser, the merge, the syntax store, the loader.
    builds_tables,
    /// What it indexes is not `ast.Program`'s tables (the checked program's slices, the type graph, a count of ranges).
    other_table,
};

/// One audited file: its path from the repository root, why its reads are safe, and the hook or path that makes them so.
pub const Entry = struct { path: []const u8, safety: Safety, via: []const u8 };

const checker_via = "a checker internal: entered from Checker.checkFunction or checkInstance after sema.zig's " ++
    "ensureBody(function.body), or from generic_bodies' symbolic check (hooked), so the body it reads is filled";

const retired_via = "reached only for a program that holds a retired construct (or a lambda), which project_syntax.build loads " ++
    "completely (ast.ensureAll) before anything reads it";

const parser_via = "the parser appends to the module's own tables while it parses (or repairs the syntax it just parsed); nothing " ++
    "is lazy yet";

const declaration_via = "reads declaration-level trees only (parameter and field defaults, a constant's body, a function's root " ++
    "statement), all written at merge";

const typed_via = "indexes the checked (typed) program's slices or another structure, not the ast.Program tables";

const graph_via = "indexes the type graph's own nodes (`graph.nodes`, `self.nodes`), not the syntax tables";

const fresh_via = "parses the source itself and reads that parse, a complete program with no loader";

const eager_via = "a command whose session completes the program (Session.completeProgram: every command of main.zig outside the " ++
    "check family), which reads every module whole";

/// The files under `src/` that read the tables, sorted by path.
pub const audited = [_]Entry{
    .{ .path = "src/arena_fix.zig", .safety = .hooked, .via = "reject returns at once when the module facts say the construct is absent; otherwise " ++
        "ast.ensureAll(syntax) before it scans" },
    .{ .path = "src/array_literals.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/ast.zig", .safety = .hooked, .via = "defines the hooks (ensureBody, ensureModule, ensureAll, scanAt); its accessors read the extent " ++
        "scanAt returned" },
    .{ .path = "src/ast_copy.zig", .safety = .builds_tables, .via = "copies or relocates the trees it is given (the merge, the loader, the semantic cache); callers " ++
        "pass filled trees" },
    .{ .path = "src/ast_literals.zig", .safety = .builds_tables, .via = "scans the tables of a parse at store time; a lazy module's literals come with its entry " ++
        "(Facts.literals)" },
    .{ .path = "src/ast_subtree.zig", .safety = .builds_tables, .via = parser_via },
    .{ .path = "src/codec_defaults.zig", .safety = .declaration_level, .via = "checks record field defaults and a record's `@invariant` clauses " ++
        "(declaration-level trees written at merge) after every body is checked" },
    .{ .path = "src/collection_lower.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/comprehension_migration.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/constant_values.zig", .safety = .hooked, .via = "calls ast.ensureBody(function.body) before it evaluates the body of a constant or helper (two " ++
        "sites)" },
    .{ .path = "src/context.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/control_expression_migration.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/core/module_parts.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/core/receiver_repair.zig", .safety = .fresh_parse, .via = fresh_via },
    .{ .path = "src/core/view_function_value.zig", .safety = .fresh_parse, .via = fresh_via },
    .{ .path = "src/declaration_borrow.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/dictionary_views.zig", .safety = .hooked, .via = "Consumers.index calls ast.ensureModule for the module (ast.ensureAll when the program has no " ++
        "extents)" },
    .{ .path = "src/docstring_example_source.zig", .safety = .fresh_parse, .via = fresh_via },
    .{ .path = "src/domain_migration.zig", .safety = .hooked, .via = "hasRetired returns at once on the module facts; otherwise ast.ensureAll(program) before it scans" },
    .{ .path = "src/domain_migration_names.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/domain_operation_migration.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/embed.zig", .safety = .checker, .via = "reads the argument node of the embed call being checked; its callers are sema_calls (checker) " ++
        "and generic_bodies (hooked)" },
    .{ .path = "src/entry_adapter.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/enum_cases.zig", .safety = .checker, .via = "reads the argument nodes of the `Kind.cases()` or `Kind.from_name(text)` call being checked; its callers are " ++
        "sema_expressions and sema_builtins (checker internals) and generic_bodies' symbolic check (hooked)" },
    .{ .path = "src/format_verify.zig", .safety = .fresh_parse, .via = "compares the input's parse and the parse of the formatted text, both made by Compilation.format: complete programs with no loader" },
    .{ .path = "src/frontend_binding_migration.zig", .safety = .builds_tables, .via = parser_via },
    .{ .path = "src/frontend_cache.zig", .safety = .builds_tables, .via = "reads the per-module tables of a parse to store them; a module served lazily is not stored again" },
    .{ .path = "src/frontend_failures.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/frontend_fixed_arrays.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/frontend_migration.zig", .safety = .builds_tables, .via = parser_via },
    .{ .path = "src/frontend_migration_variants.zig", .safety = .builds_tables, .via = parser_via },
    .{ .path = "src/frontend_patterns.zig", .safety = .hooked, .via = "isolateSourceTables calls ast.ensureAll(syntax) before it copies the tables" },
    .{ .path = "src/function_digest.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/generic_arrays.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/generic_bodies.zig", .safety = .hooked, .via = "the symbolic check calls ast.ensureBody(function.body) and copyTables calls ast.ensureAll before " ++
        "it copies the tables" },
    .{ .path = "src/generic_inference.zig", .safety = .other_table, .via = graph_via },
    .{ .path = "src/incremental.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/interface_files.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/interfaces.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/iteration_effects.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/iteration_place.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/lambda_migration.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/lazy_loader.zig", .safety = .builds_tables, .via = "the loader: fills the lazy bodies of the merged tables (ast.Loader) and reads only the root " ++
        "statements, which are always filled" },
    .{ .path = "src/lazy_module.zig", .safety = .builds_tables, .via = "a module's stored syntax read as far as its declaration part; it counts and builds the sparse " ++
        "program and reads no table" },
    .{ .path = "src/lazy_readers.zig", .safety = .other_table, .via = "this audit: it spells the patterns it searches for and reads no table" },
    .{ .path = "src/linear_rules.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/lint.zig", .safety = .eager, .via = eager_via },
    .{ .path = "src/literal_peer.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/local_qualifiers.zig", .safety = .builds_tables, .via = parser_via },
    .{ .path = "src/loop_detach.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/loop_rebinding.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/main.zig", .safety = .declaration_level, .via = "reads lengths only (nodes.items.len, statements.items.len) for the timing counts, which the " ++
        "full-length merged tables have" },
    .{ .path = "src/migration_moves.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/migration_support.zig", .safety = .retired_complete, .via = retired_via },
    .{ .path = "src/module_interface_build.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/module_interface_oracle.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/navigation.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/navigation_syntax.zig", .safety = .eager, .via = eager_via },
    .{ .path = "src/negative_index.zig", .safety = .hooked, .via = "report calls ast.ensureAll before it scans the program for the repair" },
    .{ .path = "src/nominal_catalog.zig", .safety = .other_table, .via = graph_via },
    .{ .path = "src/nominal_layouts.zig", .safety = .other_table, .via = graph_via },
    .{ .path = "src/nominal_sources.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/nominal_state.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/numeric_surface.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/option_flow.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/origins.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/overview_facts.zig", .safety = .eager, .via = eager_via },
    .{ .path = "src/parser.zig", .safety = .builds_tables, .via = parser_via },
    .{ .path = "src/pattern_discard_fix.zig", .safety = .hooked, .via = "finds the pattern of one checked binding with ast.scanAt, which fills the body that holds it, and reads that body only" },
    .{ .path = "src/prelude_builtins.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/project_syntax.zig", .safety = .builds_tables, .via = "the merge: writes the eager runs, attaches the loader, and completes a program with a retired " ++
        "construct (ast.ensureAll)" },
    .{ .path = "src/quality.zig", .safety = .eager, .via = eager_via },
    .{ .path = "src/record_defaults.zig", .safety = .declaration_level, .via = declaration_via },
    .{ .path = "src/rename_uses.zig", .safety = .hooked, .via = "Resolver.run calls ast.ensureAll before it walks any body" },
    .{ .path = "src/repetition.zig", .safety = .hooked, .via = "build and importRepair call ast.ensureAll; legacyRepeatCall asks ast.scanAt for the body around " ++
        "the call" },
    .{ .path = "src/review_inside.zig", .safety = .eager, .via = eager_via },
    .{ .path = "src/scalar_text_helpers.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sealed_rules.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema.zig", .safety = .hooked, .via = "Checker.checkFunction calls ast.ensureBody(function.body); Checker.propagated asks ast.scanAt " ++
        "for the body around the site" },
    .{ .path = "src/sema_builtins.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_calls.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_collections.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_contracts.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_exchange.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_expressions.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_gathers.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_idioms.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_loops.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_operators.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_places.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_receiver_marker.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_recovery.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_sets.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_simd.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_specialize.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/sema_statements.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/sema_summaries.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/sema_tasks.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/semantic_cache.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/semantic_copy.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/semantic_entry.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/semantic_key.zig", .safety = .hooked, .via = "Collector.collectValue calls ast.ensureBody for the function it collects (Builder.context, " ++
        "Surface.functionLookups, constants)" },
    .{ .path = "src/semantic_type_recipe.zig", .safety = .hooked, .via = "Sites.prepare asks ast.scanAt for the body that holds the site and reads only that interval" },
    .{ .path = "src/set_lower.zig", .safety = .checker, .via = checker_via },
    .{ .path = "src/symbolic_types.zig", .safety = .other_table, .via = graph_via },
    .{ .path = "src/syntax_dump.zig", .safety = .declaration_level, .via = "reads lengths only (store-check counts the nodes and statements of a stored entry)" },
    .{ .path = "src/syntax_hints.zig", .safety = .hooked, .via = "warn calls ast.ensureBody for every function whose summary did not stand in, restored bodies " ++
        "included" },
    .{ .path = "src/syntax_store.zig", .safety = .builds_tables, .via = "encodes a parse and decodes stored syntax into fresh tables; the bodies it reads are those of a " ++
        "complete parse" },
    .{ .path = "src/tests_index.zig", .safety = .other_table, .via = typed_via },
    .{ .path = "src/text_slice_octets.zig", .safety = .eager, .via = eager_via },
    .{ .path = "src/tuple_migration.zig", .safety = .hooked, .via = "reject returns at once on the module facts; otherwise ast.ensureAll(program) before it scans" },
    .{ .path = "src/variant_is.zig", .safety = .checker, .via = checker_via },
};

/// One source file for `check`: its path from the repository root and its bytes.
pub const File = struct { path: []const u8, bytes: []const u8 };

fn contains(bytes: []const u8, needle: []const u8) bool {
    return std.mem.indexOf(u8, bytes, needle) != null;
}

/// Whether `bytes` spell the field `name` (`.nodes`, not `.nodes_total`).
fn spellsField(bytes: []const u8, name: []const u8) bool {
    var from: usize = 0;
    while (std.mem.indexOfPos(u8, bytes, from, ".")) |dot| {
        from = dot + 1;
        if (!std.mem.startsWith(u8, bytes[from..], name)) continue;
        const end = from + name.len;
        if (end == bytes.len) return true;
        const next = bytes[end];
        if (!(std.ascii.isAlphanumeric(next) or next == '_')) return true;
    }
    return false;
}

/// Whether the file names the `ast` module (an import of `ast.zig`, `language.ast`, or `ast_copy`).
fn namesAst(bytes: []const u8) bool {
    return contains(bytes, "ast.zig\")") or contains(bytes, "language.ast") or contains(bytes, "ast_copy");
}

/// Whether the file reads the tables by the rule in this file's header.
pub fn readsTables(bytes: []const u8) bool {
    if (contains(bytes, ".nodes.items") or contains(bytes, ".statements.items")) return true;
    return namesAst(bytes) and (spellsField(bytes, "nodes") or spellsField(bytes, "statements"));
}

/// Whether the file calls a hook (or defines them, as `ast.zig` does).
pub fn callsHook(bytes: []const u8) bool {
    const needles = [_][]const u8{ ".ensureBody(", ".ensureModule(", ".ensureAll(", ".scanAt(", "fn ensureBody(" };
    for (needles) |needle| if (contains(bytes, needle)) return true;
    return false;
}

fn entryFor(entries: []const Entry, path: []const u8) ?Entry {
    for (entries) |entry| if (std.mem.eql(u8, entry.path, path)) return entry;
    return null;
}

/// The problems with `entries` against `files`, one line each; empty when the audit holds. `files` are the non-test sources under `src/`.
pub fn check(allocator: std.mem.Allocator, entries: []const Entry, files: []const File) std.mem.Allocator.Error![]u8 {
    var report: std.ArrayList(u8) = .empty;
    errdefer report.deinit(allocator);
    for (files) |file| {
        if (!readsTables(file.bytes)) continue;
        const entry = entryFor(entries, file.path) orelse {
            try report.print(allocator, "{s}: reads the syntax tables and is not audited; add it to `audited` in src/lazy_readers.zig with the reason its reads are safe under lazy loading\n", .{file.path});
            continue;
        };
        if (entry.safety == .hooked and !callsHook(file.bytes)) try report.print(allocator, "{s}: audited as hooked but calls no ast.ensure* or scanAt hook\n", .{file.path});
    }
    for (entries, 0..) |entry, at| {
        if (entry.via.len < 20) try report.print(allocator, "{s}: the audit names no hook or path (via is empty or too short)\n", .{entry.path});
        if (at > 0 and !std.mem.lessThan(u8, entries[at - 1].path, entry.path)) try report.print(allocator, "{s}: audited out of order or twice\n", .{entry.path});
        const file = fileFor(files, entry.path) orelse {
            try report.print(allocator, "{s}: audited but not found under src/ (renamed or deleted)\n", .{entry.path});
            continue;
        };
        if (!readsTables(file.bytes)) try report.print(allocator, "{s}: audited but no longer reads the syntax tables; remove the entry\n", .{entry.path});
    }
    return report.toOwnedSlice(allocator);
}

fn fileFor(files: []const File, path: []const u8) ?File {
    for (files) |file| if (std.mem.eql(u8, file.path, path)) return file;
    return null;
}
