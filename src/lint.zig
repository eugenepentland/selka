//! `selka lint`: one verdict over a checked project, with a code family
//! (`L_*`), profiles, waiver comments and a report/block split.
//!
//! The driver never changes acceptance on its own. Every rule resolves to a
//! mode for the selected profile (`agent` by default), a report is printed and
//! ignored, and only a `block` rule under `--gate` (or a project that sets
//! `on_build: "block"`) makes the command exit 3. Waivers are directive
//! comments on the line above a declaration; a waiver without a reason is
//! itself a blocking finding.
const std = @import("std");
const product = @import("product.zig");
const ast = @import("ast.zig");
const call_arguments = @import("call_arguments.zig");
const copy_for_store = @import("copy_for_store.zig");
const copy_forms = @import("copy_forms.zig");
const dead_writes = @import("dead_writes.zig");
const text_slice_octets = @import("text_slice_octets.zig");
const declaration_diff = @import("declaration_diff.zig");
const diagnostic = @import("diagnostic.zig");
const diagnostic_output = @import("diagnostic_output.zig");
const display_name = @import("display_name.zig");
const duplicates = @import("duplicates.zig");
const friction_session = @import("wiring/friction_session.zig");
const generated_marker = @import("generated_marker.zig");
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const lint_config = @import("lint_config.zig");
const lint_store = @import("lint_store.zig");
const project_compile = @import("project_compile.zig");
const quality = @import("quality.zig");
const walk = @import("typed_walk.zig");
/// The named builtin operation one checked `buffer_operation` node carries.
const BufferOperation = @import("buffer_operations.zig").Kind;
const ref_diff = @import("ref_diff.zig");
const source = @import("source.zig");
const tests_index = @import("tests_index.zig");
const lint_examples = @import("lint_examples.zig");
const component_adapter = @import("component_adapter.zig");
const typed = @import("typed.zig");

/// Exit status for a language-valid project with at least one blocking finding.
pub const blocked_status: u8 = 3;
/// Exit status for a valid project with no blocking finding.
pub const clean_status: u8 = 0;

/// One static allocation or copy site from the `cost --sites` analysis, as the
/// `L_ALLOC_IN_LOOP` and `L_COPY_IN_LOOP` rules read it: the source position,
/// what the site is for, the loop depth the Core passes recorded and that
/// kind's one-line hint.
pub const AllocationSite = struct {
    function: []const u8,
    path: []const u8,
    line: u32,
    column: u32,
    kind: Kind,
    loop_depth: u32,
    hint: []const u8,

    /// The kinds `cost --sites` names; `alloc-in-loop` reports the two that build
    /// a value at a loop depth, and `copy-in-loop` reports the copies.
    pub const Kind = enum { copy, construction, conversion, growth, unresolved_call };
};

/// One lint invocation's inputs. Grouped because every entry point stays at
/// or below the six-parameter ceiling.
pub const Request = struct {
    /// Allocator for findings, messages and rendering; borrowed, never owned.
    memory: std.mem.Allocator,
    io: std.Io,
    compilation: *project_compile.Compilation,
    /// Configured `lint` object, or null for an unconfigured project.
    config: ?*const lint_config.Config,
    /// Entry source path; names the file malformed lint options are reported against.
    entry_path: []const u8,
    options: Options,
    /// Per-run inputs the caller supplies beside the checked project.
    data: Data = .{},
};

/// The data one run hands a rule beside the checked project: how to render a
/// finding, and the `cost --sites` rows `L_ALLOC_IN_LOOP` reads (empty when the
/// caller ran no analysis, which every run without `--against REF` skips).
pub const Data = struct {
    diagnostics: diagnostic_output.Format = .text,
    sites: []const AllocationSite = &.{},
    /// The first error code of the analysis behind `sites` when it failed, so the rows are missing, not empty; null when it
    /// ran (a program with nothing to analyse is not a failure). `unjudged` says what that left unjudged.
    analysis_failed: ?[]const u8 = null,
};

/// Command-line switches for one run.
pub const Options = struct {
    /// `--gate` makes every `block` rule refusing and reads the whole project.
    gate: bool = false,
    /// `--json` renders findings as `diagnostic-v1` lines.
    json: bool = false,
    /// `--accept` records current findings in the baseline store.
    accept: bool = false,
    /// `--against REF` scopes per-declaration rules to changed declarations.
    against: ?[]const u8 = null,
    /// `--profile NAME` overrides the configured profile for this run.
    profile: ?lint_config.Profile = null,
    /// `--all` prints every finding in full instead of one count line per
    /// report-only rule.
    all: bool = false,
    /// `--rule=NAME` turns on, at `report`, one rule that the profile and the
    /// project leave off (`dead-write`); a rule already on keeps its mode.
    rule: ?[]const u8 = null,
};

/// Declaration identity a baseline or ratchet row is keyed on.
pub const Subject = struct {
    module: []const u8 = "",
    qualified: []const u8 = "",
};

/// How a finding prints and counts: its resolved severity, whether its rule
/// resolves to `block` mode, and whether its declaration changed against the
/// run's `--against REF`. Grouped so `Finding` stays inside the field ceiling.
pub const State = struct {
    severity: diagnostic.Severity = .warning,
    /// The rule resolves to `block` mode, so this finding refuses under
    /// `--gate` and is never summarized.
    blocks_under_gate: bool = false,
    /// The declaration this finding names changed against the run's
    /// `--against REF`, so it prints in full in every run (P2).
    changed: bool = false,
    /// The rule reports this finding everywhere and never refuses it.
    report_only: bool = false,
    /// The rule only refuses in a declaration changed against `--against REF`.
    change_scoped: bool = false,
};

/// One lint finding, with the state its rule and diff resolved.
pub const Finding = struct {
    code: []const u8,
    rule: []const u8,
    span: source.Span,
    message: []const u8,
    related: ?diagnostic.Related = null,
    subject: Subject = .{},
    state: State = .{},
};

/// The exported declarations and discovered tests one run judges, each beside
/// the per-function flag array built from it.
pub const Roots = struct {
    exports: []const typed.FunctionId,
    tests: []const typed.FunctionId,
    export_flags: []const bool,
    test_flags: []const bool,
    /// Functions named as a value anywhere in the program (`sort(key=by_key)`),
    /// which is a use even though no call node names them (FR-420).
    value_flags: []const bool = &.{},
    /// Functions a docstring example names or reaches through the call graph,
    /// which is a use and a test (FR-415).
    example_flags: []const bool = &.{},
    /// Everything the example-named declarations reach through the call graph,
    /// which the `agent` profile counts as tested (FR-415).
    example_reach_flags: []const bool = &.{},

    /// Whether `id` names a discovered test.
    pub fn isTest(self: Roots, id: typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.test_flags.len and self.test_flags[index];
    }

    /// Whether `id` names an exported declaration.
    pub fn isExport(self: Roots, id: typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.export_flags.len and self.export_flags[index];
    }

    /// Whether `id` is passed or stored as a function value somewhere.
    pub fn isValueReferenced(self: Roots, id: typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.value_flags.len and self.value_flags[index];
    }

    /// Whether a docstring example uses `id` or reaches it through its calls.
    pub fn isExampleTested(self: Roots, id: typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.example_flags.len and self.example_flags[index];
    }

    /// Whether a declaration an example names reaches `id` through its calls.
    pub fn isExampleReached(self: Roots, id: typed.FunctionId) bool {
        const index = @backingInt(id);
        return index < self.example_reach_flags.len and self.example_reach_flags[index];
    }
};

/// Resolved per-function facts every rule reads: the call graph, the checked
/// syntax the call sites were written in, and the roots one run judges.
pub const Facts = struct {
    program: typed.Program,
    /// The checked merged source and its syntax, so a rule can read the operands
    /// a checked node was built from.
    src: source.Source,
    syntax: ast.Program,
    functions: []const quality.Function,
    roots: Roots,
    /// Backend warnings supplied by the lint command after concrete Core checking.
    diagnostics: []const diagnostic.Diagnostic = &.{},
    /// Static allocation and copy sites for `L_ALLOC_IN_LOOP` and `L_COPY_IN_LOOP`,
    /// from the same analysis `selka cost --sites` renders; empty when the run computed none.
    sites: []const AllocationSite = &.{},

    /// Whether `id` names a discovered test.
    pub fn isTest(self: *const Facts, id: typed.FunctionId) bool {
        return self.roots.isTest(id);
    }

    /// Whether `id` names an exported declaration.
    pub fn isExport(self: *const Facts, id: typed.FunctionId) bool {
        return self.roots.isExport(id);
    }
};

/// State one rule reads and appends findings to.
pub const RuleContext = struct {
    facts: *const Facts,
    config: ?*const lint_config.Config,
    /// Interface index of the checked project, for rules that walk exports.
    index: *interfaces.Index,
    /// Arena for this run's messages; borrowed, never owned.
    memory: std.mem.Allocator,
    findings: *std.ArrayList(Finding),
    /// Diff scope for `--gate --against REF`, or null when this run judges the
    /// tree rather than a diff. Only `change-without-test` reads it.
    change: ?ChangeScope = null,
    /// Test-reachability facts of this run: the selected profile and the one
    /// index every reachability reading comes from.
    reach: Reachability = .{},
};

/// The reachability evidence one run shares: which profile decides how much
/// test contact counts as tested, and the single index built for that walk.
pub const Reachability = struct {
    /// Selected profile. `agent` accepts an export any discovered test reaches,
    /// directly or transitively; `strict` and `safety` keep the direct-call fact.
    profile: lint_config.Profile = .agent,
    /// Index over the same discovery, call graph and inversion `selka
    /// tests-for` answers from, or null when the caller built none.
    index: ?*const tests_index.Index = null,
};

/// The repository, reference revision and I/O a diff-judging rule reads.
pub const ChangeScope = struct {
    /// I/O used to spawn `git` for the working-tree diff.
    io: std.Io,
    /// Directory the entry file lives in; `git -C` runs here so module paths
    /// resolve exactly as the project loader spelled them.
    repo_root: []const u8,
    /// Reference revision the working tree is compared against.
    reference: []const u8,
};

/// Everything one `change-without-test` evaluation reads. Grouped so the public
/// helper stays inside the parameter ceiling.
pub const ChangeQuery = struct {
    /// Arena for messages, the per-module diff cache and the findings.
    memory: std.mem.Allocator,
    /// Per-run call graph, discovered tests and merged source.
    facts: *const Facts,
    /// Interface index that maps a declaration back to its own module.
    index: *interfaces.Index,
    /// Configured `test-coverage` exemptions, or null for a default run.
    config: ?*const lint_config.Config,
    /// Diff scope; a change-time rule only runs when the caller supplies one.
    scope: ChangeScope,
};

/// Mode defaults for one rule under each named profile.
pub const Modes = struct { agent: lint_config.Mode, strict: lint_config.Mode, safety: lint_config.Mode };

/// One lint rule: a stable name, a one-line description, profile defaults and
/// the function that produces its findings.
pub const Rule = struct {
    name: []const u8,
    description: []const u8,
    modes: Modes,
    run: *const fn (*RuleContext) std.mem.Allocator.Error!void,
    /// The rule judges a declaration's shape at the line, so it only refuses
    /// in a declaration changed against `--against REF`; everywhere else it
    /// reports (P1's heuristic finding).
    change_scoped: bool = false,
    /// The rule reports only in a declaration changed against `--against REF`
    /// (the plan's `L_ALLOC_IN_LOOP`); outside the diff it contributes nothing.
    reports_only_in_change: bool = false,
};

/// The qualified-name separator every rule splits on.
const separator = "::";

/// Local (unqualified) part of a `module::name` function identity. Only the head
/// before an instance's type arguments is searched (`display_name.local`).
pub fn localName(qualified: []const u8) []const u8 {
    return display_name.local(qualified);
}

/// Module part of a `module::name` function identity, or empty when unqualified.
pub fn moduleName(qualified: []const u8) []const u8 {
    return display_name.module(qualified);
}

/// A checked function's source name without the specialization suffix a generic
/// instantiation carries (`contains[i64]` is the source `contains`).
fn unspecializedName(name: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, name, '[')) |at| return name[0..at];
    return name;
}

const rule_untested_export = "untested-export";
const rule_dead_private = "dead-private";
const rule_test_coverage = "test-coverage";
const rule_waiver_reason = "waiver-reason";
const rule_test_no_assertion = "test-no-assertion";
const rule_test_conditional = "test-conditional";
const rule_test_empty = "test-empty";
const rule_function_length = "function-length";
const rule_parameters = "parameters";
const rule_nesting_depth = "nesting-depth";
const rule_call_nesting = "call-nesting";
const rule_counting_while = "counting-while";
const rule_double_lookup = "double-lookup";
const rule_data_clump = "data-clump";
const rule_decision_points = "decision-points";
const rule_dead_export = "dead-export";
const rule_undocumented_export = "undocumented-export";
const rule_undocumented_module = "undocumented-module";
const rule_missing_example = "missing-example";
const rule_long_example = "long-example";
const rule_change_without_test = "change-without-test";
const rule_integration_tests = "integration-tests";
const rule_record_size = "record-size";
const rule_file_length = "file-length";
const rule_bool_ops = "bool-ops-per-condition";
const rule_naming = "naming";
const rule_repeated_literal = "repeated-literal";
const rule_same_type_adjacent_params = "same-type-adjacent-params";
const rule_duplicate_body = "duplicate-body";
const rule_output_in_library = "output-in-library";
const rule_positional_literal = "positional-literal";
const rule_sentinel_int = "sentinel-int";
const rule_discarded_failure = "discarded-failure";
const rule_public_dict = "public-dict";
const rule_noalloc_allocates = "noalloc-allocates";
const rule_needless_copy = "needless-copy";
const rule_byte_set = "byte-set";
const rule_range_chain = "range-chain";
const rule_literal_match = "literal-match";
const rule_pattern_shorthand = "pattern-shorthand";
const rule_option_try = "option-try";
const rule_else_is_try = "else-is-try";
const rule_match_else = "match-else";
const rule_match_is = "match-is";
const rule_copy_for_store = "copy-for-store";
const rule_copy_move = "copy-move";
const rule_linear_search_in_loop = "linear-search-in-loop";
const rule_shift_in_loop = "shift-in-loop";
const rule_sort_in_loop = "sort-in-loop";
const rule_alloc_in_loop = "alloc-in-loop";
const rule_copy_in_loop = "copy-in-loop";
const rule_dead_write = "dead-write";
const rule_text_slice_octets = "text-slice-octets";

/// Advisory size-budget defaults for the report-only rules (plan section 9).
const default_max_function_lines: usize = 60;
const default_max_parameters: usize = 5;
/// Control-nesting levels before `nesting-depth` reports. Calibrated on the selka
/// projects (wave 2 round 34): half their findings at 4 sat exactly at 5.
const default_max_nesting: usize = 5;
/// Calls nested inside one expression before `call-nesting` reports (proposal 2).
/// Calibrated on the selka projects (wave 2 round 34): 15 of 18 findings at 2 sat at 3.
const default_max_call_nesting: usize = 3;
const default_max_decisions: usize = 10;
const default_max_record_fields: usize = 7;
const default_max_file_lines: usize = 1000;
const default_max_bool_ops: usize = 3;
/// How many times one notable integer literal may repeat in a module before
/// `repeated-literal` reports it. `0` and `1` never count; they are structural
/// rather than a duplicated piece of knowledge.
const default_literal_repeats: usize = 3;
/// Module globs a capability-requesting test may live in (plan section 5.2).
const default_integration_modules: []const []const u8 = &.{ "*_integration", "integration.*" };
/// Module globs allowed to contain print operations (plan section 9). The
/// conventional entry module and the CLI/integration families print by design.
const default_output_modules: []const []const u8 = &.{ "main", "*_cli", "cli", "cli.*", "*_integration", "integration.*" };
/// Shortest accepted `undocumented-export` docstring, over non-whitespace bytes.
const default_min_chars: usize = 12;

/// Every rule the driver knows. Wave 1 ships the configuration, the finding
/// family, waivers and exit codes; the semantic rules follow.
pub const rules = [_]Rule{
    .{
        .name = rule_alloc_in_loop,
        .description = "a construction or conversion site at loop depth 1 or more; build it once outside the loop",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runAllocInLoop,
        .change_scoped = true,
        .reports_only_in_change = true,
    },
    .{
        .name = rule_copy_in_loop,
        .description = "a copy site at loop depth 1 or more, every copy a choice: a field store, exchange, a borrowing const or an own hand-off",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runCopyInLoop,
        .change_scoped = true,
    },
    .{
        .name = rule_noalloc_allocates,
        .description = "written noalloc has a static Core allocation witness or unsupported body",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runNoallocAllocates,
    },
    .{
        .name = rule_needless_copy,
        .description = "a `.copy()` whose copy-free form checks reads the checker's W_NEEDLESS_COPY",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runNeedlessCopy,
    },
    .{
        .name = rule_byte_set,
        .description = "an or-chain of byte equalities on one value reads the checker's W_BYTE_SET; `value in b\"...\"` tests the same set",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runByteSet,
    },
    .{
        .name = rule_range_chain,
        .description = "two comparisons bound one value from both sides reads the checker's W_RANGE_CHAIN; `low <= value <= high` is one chain",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runRangeChain,
    },
    .{
        .name = rule_literal_match,
        .description = "an if/elif chain of `x == literal` tests reads the checker's W_LITERAL_MATCH; a literal `match` compares the value once",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runLiteralMatch,
    },
    .{
        .name = rule_pattern_shorthand,
        .description = "a pattern field `name=name` reads the checker's W_PATTERN_SHORTHAND; the bare name binds the same field",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runPatternShorthand,
    },
    .{
        .name = rule_option_try,
        .description = "an Option match whose `None` arm only returns `None` reads the checker's W_OPTION_TRY; `try` unwraps it",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runOptionTry,
    },
    .{
        .name = rule_else_is_try,
        .description = "a bind-or-else whose `else` block only passes the failure on reads the checker's W_ELSE_IS_TRY; `try` does the same",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runElseIsTry,
    },
    .{
        .name = rule_match_else,
        .description = "a two-arm match over an Option or a Result whose failure arm leaves reads the checker's W_MATCH_ELSE; `const x = value else:` unwraps it",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runMatchElse,
    },
    .{
        .name = rule_match_is,
        .description = "a two-arm match over an Option or a Result one of whose arms does nothing reads the checker's W_MATCH_IS; `if value is Some(x):` tests it",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runMatchIs,
    },
    .{
        .name = rule_linear_search_in_loop,
        .description = "a list a loop appends to is linearly searched in the same loop; keep a set or dict beside it",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runLinearSearchInLoop,
        .change_scoped = true,
    },
    .{
        .name = rule_shift_in_loop,
        .description = "a list declared outside a loop shifts at index 0 inside it; keep an index cursor",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runShiftInLoop,
        .change_scoped = true,
    },
    .{
        .name = rule_sort_in_loop,
        .description = "a list a loop appends to is sorted in the same loop; sort once after the loop",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runSortInLoop,
        .change_scoped = true,
    },
    .{
        .name = rule_untested_export,
        .description = "an exported declaration no discovered test reaches under `agent`, or does not call directly under `strict`",
        .modes = .{ .agent = .report, .strict = .block, .safety = .block },
        .run = runUntestedExport,
    },
    .{
        .name = rule_dead_private,
        .description = "a private declaration has no call site",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runDeadPrivate,
    },
    .{
        .name = rule_test_no_assertion,
        .description = "a test body has no assert statement",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runTestNoAssertion,
    },
    .{
        .name = rule_test_conditional,
        .description = "a test body has a top-level conditional or loop",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runTestConditional,
    },
    .{
        .name = rule_test_empty,
        .description = "a test body is empty",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runTestEmpty,
    },
    .{
        .name = rule_integration_tests,
        .description = "a test requesting Filesystem, Network, Clock or Entropy lives outside an integration module",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runIntegrationTests,
    },
    .{
        .name = rule_function_length,
        .description = "a function body exceeds its line budget",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runFunctionLength,
    },
    .{
        .name = rule_parameters,
        .description = "a function takes more data parameters than its budget (capabilities do not count)",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runParameters,
    },
    .{
        .name = rule_nesting_depth,
        .description = "a function nests control flow deeper than its budget",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runNestingDepth,
    },
    .{
        .name = rule_call_nesting,
        .description = "calls are nested inside one expression; bind an inner result to a named temporary",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runCallNesting,
    },
    .{
        .name = rule_counting_while,
        .description = "a loop counts with `while`; write `for i in range(start, bound):`",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runCountingWhile,
    },
    .{
        .name = rule_data_clump,
        .description = "three or more caller arguments are written together at several call sites; group them into a record",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runDataClump,
    },
    .{
        .name = rule_double_lookup,
        .description = "one statement probes a dictionary key twice; `dicts.add` or `dicts.append_to` probes once",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runDoubleLookup,
    },
    .{
        .name = rule_copy_for_store,
        .description = "a parameter is `copy`-ed into storage; an `own` parameter takes the value without a copy",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runCopyForStore,
    },
    .{
        .name = rule_copy_move,
        .description = "a copy a move would replace reads the checker's W_COPY_MOVE and names the form: take, take_or, a consuming loop",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runCopyMove,
    },
    .{
        .name = rule_public_dict,
        .description = "a public signature spells a bare `dict[...]`; name it with a `type` alias",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runPublicDict,
    },
    .{
        .name = rule_discarded_failure,
        .description = "a failing call's result is discarded with `_ =`",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runDiscardedFailure,
    },
    .{
        .name = rule_decision_points,
        .description = "a function carries more decision points than its budget",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runDecisionPoints,
    },
    .{
        .name = rule_dead_export,
        .description = "an exported declaration has no caller anywhere in the project",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runDeadExport,
    },
    .{
        .name = rule_undocumented_export,
        .description = "an exported declaration has no docstring, a docstring under min_chars, or one that restates its name",
        .modes = .{ .agent = .report, .strict = .block, .safety = .block },
        .run = runUndocumentedExport,
    },
    .{
        .name = rule_undocumented_module,
        .description = "a project module has no module docstring",
        .modes = .{ .agent = .off, .strict = .report, .safety = .report },
        .run = runUndocumentedModule,
    },
    .{
        .name = rule_missing_example,
        .description = "a public function has no runnable docstring example",
        .modes = .{ .agent = .off, .strict = .report, .safety = .report },
        .run = runMissingExample,
    },
    .{
        .name = rule_long_example,
        .description = "a docstring example prints more than 120 characters on one expected line, or runs more than 6 `>>>` lines; show the call, not a dump",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runLongExample,
    },
    .{
        .name = rule_change_without_test,
        .description = "a changed non-test declaration has no test whose body changed in the same diff",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runChangeWithoutTest,
    },
    .{
        .name = rule_record_size,
        .description = "a record or class declares more fields than its budget",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runRecordSize,
    },
    .{
        .name = rule_file_length,
        .description = "a module carries more code lines than its budget",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runFileLength,
    },
    .{
        .name = rule_bool_ops,
        .description = "a single condition combines more boolean operators than its budget",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runBoolOpsPerCondition,
    },
    .{
        .name = rule_naming,
        .description = "a declaration or binding does not follow the casing or vague-name convention",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runNaming,
    },
    .{
        .name = rule_repeated_literal,
        .description = "the same integer literal repeats in one module",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runRepeatedLiteral,
    },
    .{
        .name = rule_same_type_adjacent_params,
        .description = "adjacent parameters share one type, where a keyword argument reads better",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runSameTypeAdjacentParams,
    },
    .{
        .name = rule_duplicate_body,
        .description = "two or more checked functions share an identical body",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runDuplicateBody,
    },
    .{
        .name = rule_output_in_library,
        .description = "a module outside the output allow-list prints",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runOutputInLibrary,
    },
    .{
        .name = rule_positional_literal,
        .description = "a call passes a bool, integer or None literal positionally, where naming the parameter reads better",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runPositionalLiteral,
    },
    .{
        .name = rule_dead_write,
        .description = "a write to a local, or to a field or element of one, that no later read sees (off unless asked for: W7's count)",
        .modes = .{ .agent = .off, .strict = .off, .safety = .off },
        .run = runDeadWrite,
    },
    .{
        .name = rule_text_slice_octets,
        .description = "a slice of a `str` whose bound is a literal, a constant or the other bound plus a literal counts octets it did not find",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runTextSliceOctets,
    },
    .{
        .name = rule_sentinel_int,
        .description = "an `int` sentinel a negative literal marks, where `int?` with `is None` or `unwrap_or` would say it",
        .modes = .{ .agent = .report, .strict = .block, .safety = .block },
        .run = runSentinelInt,
    },
};

// ---------------------------------------------------------------------------
// `positional-literal`: a bool, integer or `None` literal passed positionally
// in a call of three or more arguments says nothing about what it means, so the
// rule names the parameter it binds to and prints the call as it should be
// written. Only a resolved declared function or record constructor counts: an
// intrinsic and a call through a callback value have no parameter names to
// write, so they are exempt. The rule never blocks; it is a report-only
// readability finding.

/// Which declaration kind one linted call constructs.
const Origin = enum { function, record };

/// One linted call: the checked syntax it was written in, the declared names its
/// operands bind to in source order, and the kind of its callee.
const PositionalCall = struct {
    syntax: ast.Program,
    src: source.Source,
    call: call_arguments.Call,
    names: []const []const u8,
    origin: Origin,
};

/// The call sites and declarations of one run, keyed by the span their checked
/// node carries, so a rule can read the operands a checked call was written
/// with: `call` maps a checked node's span to the parsed call node, and
/// `parameters` maps a checked function's declaration span to its declared
/// parameter names.
const CallSites = struct {
    /// Every parsed call node, keyed by its own span.
    calls: std.AutoHashMapUnmanaged(source.Span, ast.NodeId) = .empty,
    /// Every declared function, keyed by its name span.
    functions: std.AutoHashMapUnmanaged(source.Span, usize) = .empty,

    /// Index the checked syntax of one compilation.
    fn init(memory: std.mem.Allocator, syntax: ast.Program) std.mem.Allocator.Error!CallSites {
        var sites: CallSites = .{};
        errdefer sites.calls.deinit(memory);
        errdefer sites.functions.deinit(memory);
        for (syntax.nodes.items, 0..) |node, index| {
            if (node.data != .call) continue;
            try sites.calls.put(memory, node.span, @fromBackingInt(index));
        }
        for (syntax.functions, 0..) |function, index| try sites.functions.put(memory, function.name, index);
        return sites;
    }

    /// The parsed call node a checked node at `span` was built from, or null
    /// when that position is not a call.
    fn call(self: CallSites, syntax: ast.Program, span: source.Span) ?call_arguments.Call {
        const index = self.calls.get(span) orelse return null;
        return syntax.nodes.items[@backingInt(index)].data.call;
    }

    /// The declared parameter names of one function, in source order, or null
    /// when no declaration has that span.
    fn parameters(self: CallSites, memory: std.mem.Allocator, src: source.Source, syntax: ast.Program, declaration: source.Span) std.mem.Allocator.Error!?[]const []const u8 {
        const index = self.functions.get(declaration) orelse return null;
        const names = try call_arguments.parameterNames(memory, src, syntax.functions[index].signature.parameters);
        return names;
    }
};

/// Section 9 `positional-literal`: report a declared call or record constructor
/// of three or more arguments whose operands include a positional bool, integer
/// or `None` literal, naming the parameter the last one binds to.
fn runPositionalLiteral(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    var sites = try CallSites.init(context.memory, facts.syntax);
    var names: std.ArrayList([]const u8) = .empty;
    defer names.deinit(context.memory);
    for (facts.program.nodes) |node| {
        const call = sites.call(facts.syntax, node.span) orelse continue;
        if (call.arguments.len < 3) continue;
        names.clearRetainingCapacity();
        const origin: Origin = switch (node.data) {
            .call => |invocation| found: {
                const function = facts.program.functions[@backingInt(invocation.function)];
                const parameters = try sites.parameters(context.memory, facts.src, facts.syntax, function.declaration) orelse continue;
                try names.appendSlice(context.memory, parameters);
                break :found .function;
            },
            .record => |fields| found: {
                try appendRecordFields(context, node, fields, &names) orelse continue;
                break :found .record;
            },
            else => continue,
        };
        const literals = positionalLiterals(facts.syntax, call) orelse continue;
        if (literals.last >= names.items.len or literals.first >= names.items.len) continue;
        const site: PositionalCall = .{ .syntax = facts.syntax, .src = facts.src, .call = call, .names = names.items, .origin = origin };
        try context.findings.append(context.memory, .{
            .code = "L_POSITIONAL_LITERAL",
            .rule = rule_positional_literal,
            .span = call.name,
            .message = try positionalLiteralMessage(context.memory, site, literals),
            .subject = positionalSubject(facts, node),
        });
    }
}

/// Append the declared field names of one record construction, in the source
/// order its checked initializers were written.
fn appendRecordFields(context: *RuleContext, node: typed.Node, fields: []const typed.FieldInit, names: *std.ArrayList([]const u8)) std.mem.Allocator.Error!?void {
    if (!node.ty.isAggregate()) return null;
    const index = node.ty.recordIndex();
    if (index >= context.facts.program.records.len) return null;
    const record = context.facts.program.records[index];
    for (fields) |field| {
        if (field.index >= record.fields.len) return null;
        try names.append(context.memory, record.fields[field.index].name);
    }
    return {};
}

/// The first and last operand one call passes positionally as a bool, integer
/// or `None` literal. The finding names the last one, where the reader has the
/// least left to go on, while the repair names the call from the first one on.
const LiteralRange = struct { first: usize, last: usize };

/// The positional-literal range of one call, or null when it passes none.
fn positionalLiterals(syntax: ast.Program, call: call_arguments.Call) ?LiteralRange {
    var range: ?LiteralRange = null;
    for (call.arguments, 0..) |argument, index| {
        const named = call.argument_names.len != 0 and call.argument_names[index] != null;
        if (named) continue;
        if (!isLiteral(syntax.nodes.items[@backingInt(argument)])) continue;
        if (range) |*found| found.last = index else range = .{ .first = index, .last = index };
    }
    return range;
}

/// Whether one parsed operand is a `bool`, integer or `None` literal.
fn isLiteral(node: ast.Node) bool {
    return switch (node.data) {
        .integer, .boolean, .unit => true,
        else => false,
    };
}

/// The finding's subject: the callee's own declaration identity, or the record
/// type's name for a construction.
fn positionalSubject(facts: *const Facts, node: typed.Node) Subject {
    if (node.data == .call) {
        const name = facts.program.functions[@backingInt(node.data.call.function)].name;
        return .{ .module = moduleName(name), .qualified = name };
    }
    if (!node.ty.isAggregate()) return .{};
    const index = node.ty.recordIndex();
    if (index >= facts.program.records.len) return .{};
    const name = facts.program.records[index].name;
    return .{ .module = moduleName(name), .qualified = name };
}

/// Render the `positional-literal` finding: the last positional literal, the
/// ordinal and name of the parameter it binds to, and the call with every
/// operand from the first positional literal on written by name, through the one
/// shared call renderer.
fn positionalLiteralMessage(memory: std.mem.Allocator, site: PositionalCall, literals: LiteralRange) std.mem.Allocator.Error![]const u8 {
    const at = literals.last;
    const literal = site.src.text(site.syntax.nodes.items[@backingInt(site.call.arguments[at])].span);
    const callee = call_arguments.calleeText(site.src, site.call);
    const repaired = try call_arguments.render(memory, site.src, site.syntax.nodes.items, site.call, site.names, literals.first);
    return std.fmt.allocPrint(memory, "`{s}` is passed positionally to `{s}`'s {d}{s} {s} `{s}`; name it: `{s}`", .{
        literal,
        callee,
        at + 1,
        ordinalSuffix(at + 1),
        if (site.origin == .function) "parameter" else "field",
        site.names[at],
        repaired,
    });
}

/// The English ordinal suffix of `value`.
fn ordinalSuffix(value: usize) []const u8 {
    const last_two = value % 100;
    if (last_two >= 11 and last_two <= 13) return "th";
    return switch (value % 10) {
        1 => "st",
        2 => "nd",
        3 => "rd",
        else => "th",
    };
}

/// Resolve one rule's mode for the run's profile, applying configured overrides.
fn resolveMode(rule: Rule, profile: lint_config.Profile, config: ?*const lint_config.Config) lint_config.Mode {
    const fallback = switch (profile) {
        .agent => rule.modes.agent,
        .strict => rule.modes.strict,
        .safety => rule.modes.safety,
    };
    const settings = config orelse return fallback;
    return settings.modeFor(rule.name, fallback);
}

/// The mode a rule runs at once `--rule=NAME` is applied: the named rule, when
/// it resolves `off`, reports; every other rule keeps the mode it resolved.
pub fn requestedMode(rule: Rule, resolved: lint_config.Mode, requested: ?[]const u8) lint_config.Mode {
    const name = requested orelse return resolved;
    if (resolved != .off or !std.mem.eql(u8, name, rule.name)) return resolved;
    return .report;
}

/// Whether `name` is a rule this driver knows, for validating `--rule=NAME`.
pub fn knownRule(name: []const u8) bool {
    for (rules) |rule| if (std.mem.eql(u8, rule.name, name)) return true;
    return false;
}

/// Errors a lint run reports to the CLI: allocator failure, a wild call-graph
/// root, a check failure while deriving facts, or a refused diagnostic write.
pub const RunError = std.mem.Allocator.Error || quality.AnalyzeError || project_compile.CheckError || lint_store.Error || std.Io.File.Writer.Error || component_adapter.Error;

/// Findings and counts one lint evaluation produced, before any rendering.
pub const Outcome = struct {
    findings: []const Finding,
    blocking: usize,
    reporting: usize,
    waived: usize,
    accepted: usize,
};

/// The per-function evidence besides tests and exports: value uses (FR-420) and
/// docstring examples (FR-415), both read once from the checked program.
const ReachEvidence = struct { values: []const bool, examples: lint_examples.Evidence };

fn reachEvidence(memory: std.mem.Allocator, index: *interfaces.Index, program: typed.Program, functions: []const quality.Function) std.mem.Allocator.Error!ReachEvidence {
    // A function named as a value (`values.sort(key=by_key)`) has no call node,
    // so the call graph cannot see the use; record it here once (FR-420).
    const values = try memory.alloc(bool, program.functions.len);
    @memset(values, false);
    for (program.nodes) |node| switch (node.data) {
        .function_value => |id| values[@backingInt(id)] = true,
        else => {},
    };
    // A docstring example runs code: it uses what it names and tests what it
    // reaches, from the same checked program and call graph (FR-415).
    return .{ .values = values, .examples = try lint_examples.used(memory, index, program, functions) };
}

/// Evaluate every enabled rule and return the final findings and counts without
/// writing anything. The CLI wrapper `run` renders and prints the summary, so a
/// test can drive the identical pipeline without touching the process stdout
/// (which is the test runner's own protocol pipe).
pub fn evaluate(request: Request, scratch: std.mem.Allocator) RunError!Outcome {
    return evaluateUsing(request, scratch, .reference);
}

/// The discovered tests of a checked project: the `test_`-prefixed declarations and the `@test` ones.
/// `testRoots` is the native-test entry set, exported declarations *and* discovered tests; only these are
/// tests for coverage purposes, or every exported function would vouch for itself.
pub fn discoveredTests(compilation: *project_compile.Compilation, scratch: std.mem.Allocator) RunError![]const typed.FunctionId {
    const program = compilation.program.?;
    var found: std.ArrayList(typed.FunctionId) = .empty;
    for (try compilation.testRoots(scratch)) |id| {
        const function = program.functions[@backingInt(id)];
        if (!isTestName(function.name) and !ast.hasAttribute(compilation.syntax, function.declaration, .@"test")) continue;
        try found.append(scratch, id);
    }
    return found.items;
}

/// Evaluate with the test-index implementation chosen at the command boundary.
pub fn evaluateUsing(request: Request, scratch: std.mem.Allocator, adapter: component_adapter.Adapter) RunError!Outcome {
    const program = request.compilation.program.?;
    const exports = try request.compilation.exportRoots(scratch);
    const test_ids = try discoveredTests(request.compilation, scratch);
    var analysis = try quality.analyzeWithExports(scratch, program, request.compilation.src, request.compilation.syntax, .{}, exports);
    defer analysis.deinit();

    const test_flags = try scratch.alloc(bool, program.functions.len);
    const export_flags = try scratch.alloc(bool, program.functions.len);
    @memset(test_flags, false);
    @memset(export_flags, false);
    for (test_ids) |id| test_flags[@backingInt(id)] = true;
    for (exports) |id| export_flags[@backingInt(id)] = true;

    const evidence = try reachEvidence(scratch, request.compilation.index, program, analysis.functions);

    var facts: Facts = .{
        .program = program,
        .src = request.compilation.src,
        .syntax = request.compilation.syntax,
        .functions = analysis.functions,
        .diagnostics = request.compilation.diagnostics.items.items,
        .sites = request.data.sites,
        .roots = .{
            .exports = exports,
            .tests = test_ids,
            .test_flags = test_flags,
            .export_flags = export_flags,
            .value_flags = evidence.values,
            .example_flags = evidence.examples.direct,
            .example_reach_flags = evidence.examples.reached,
        },
    };

    // One reachability walk for the whole run, built before any rule reads it:
    // the same discovered tests, call graph and inversion `selka tests-for`
    // answers from. The `untested-export` verdict and every related note on a
    // finding read this index, so none of them can disagree with the command.
    var reach = try buildReachabilityIndex(scratch, request.compilation, adapter);
    defer reach.deinit();

    var findings: std.ArrayList(Finding) = .empty;
    var waived: usize = 0;

    var waivers: std.ArrayList(Waiver) = .empty;
    try scanWaivers(scratch, request.compilation.src, &waivers);
    try scanAttributeWaivers(scratch, request.compilation.src, request.compilation.syntax, &waivers);

    const profile = profileOf(request);
    const force_block = forcesBlock(request);
    const root = std.fs.path.dirname(request.entry_path) orelse ".";

    // `--against REF` reads a diff in every run, with or without `--gate`: the
    // change-time rule judges it, and findings in a changed declaration print in
    // full while the rest are summarized (P2).
    const change: ?ChangeScope = if (request.options.against) |reference| .{
        .io = request.io,
        .repo_root = root,
        .reference = reference,
    } else null;

    var context: RuleContext = .{
        .facts = &facts,
        .config = request.config,
        .index = request.compilation.index,
        .memory = scratch,
        .findings = &findings,
        .change = change,
        .reach = .{ .profile = profile, .index = &reach },
    };
    for (rules) |rule| {
        const mode = requestedMode(rule, resolveMode(rule, profile, request.config), request.options.rule);
        if (mode == .off) continue;
        const start = findings.items.len;
        try rule.run(&context);
        // A standard-library module is never the project's review surface (P2),
        // so its findings leave before waivers and modes count anything.
        dropStandardLibraryFindings(request.compilation.src, request.entry_path, &findings);
        const kept = filterWaived(waivers.items, request.compilation.src, findings.items, .{
            .start = start,
            .waived = &waived,
            .severity = if (mode == .block) .err else .warning,
            .block = mode == .block,
            .change_scoped = rule.change_scoped,
        });
        findings.shrinkRetainingCapacity(kept);
    }

    // The waiver-reason rule is exact and always blocks: a silent waiver is
    // exactly the review bypass the store exists to prevent.
    const reason_start = findings.items.len;
    try appendWaiverReasonFindings(scratch, waivers.items, &findings);
    dropStandardLibraryFindings(request.compilation.src, request.entry_path, &findings);
    const reason_kept = filterWaived(waivers.items, request.compilation.src, findings.items, .{
        .start = reason_start,
        .waived = &waived,
        .severity = .err,
        .block = true,
    });
    findings.shrinkRetainingCapacity(reason_kept);

    // A file that declares itself generated is not a review surface: its text is
    // a build product, so no rule's finding survives, whichever mode resolves.
    dropGeneratedFindings(request.compilation.src, &findings);

    // The standard library is the compiler's own code, not the project's: a
    // project's lint never reports it (P2), exactly as a generated file is
    // dropped before any mode resolves. Linting the standard library itself
    // keeps every finding.
    dropStandardLibraryFindings(request.compilation.src, request.entry_path, &findings);

    // Every finding that names a declaration carries the discovered tests that
    // reach it, from the same index `tests-for` answers from and the same one
    // the rule above judged. Waived findings are already gone, and a rule that
    // set its own related note keeps it.
    try attachReachabilityNotes(scratch, &facts, &reach, findings.items);

    // Baselines turn existing blockers into accepted debt. `--accept` rewrites
    // the store so the next `--gate` is green; a plain `--gate` only reads it.
    // A block-mode finding is `.err` at this point even without `--gate`, so
    // `--accept` records debt a plain run would only report.
    var accepted: usize = 0;
    if (request.options.accept) {
        try acceptFindings(scratch, request.io, root, findings.items);
        for (findings.items) |*finding| {
            if (finding.state.severity != .err) continue;
            finding.state.severity = .warning;
            accepted += 1;
        }
    } else if (request.options.gate) {
        for (findings.items) |*finding| {
            if (finding.state.severity != .err) continue;
            if (!try baselineContains(scratch, request.io, root, finding.*)) continue;
            finding.state.severity = .warning;
            accepted += 1;
        }
    }
    // Mark every finding the diff covers so the renderer prints it in full:
    // a changed declaration is the part of a project a run must show exactly.
    if (change) |scope| {
        var marks = try ChangeMarks.init(scratch, scope, request.compilation);
        for (findings.items) |*finding| finding.state.changed = marks.changed(finding.*);
    }
    // A rule that reports only in a changed declaration contributes nothing
    // outside one, so its finding leaves before any count or print.
    var kept: usize = 0;
    for (findings.items) |finding| {
        if (reportsOnlyInChange(finding.rule) and !finding.state.changed) continue;
        findings.items[kept] = finding;
        kept += 1;
    }
    findings.shrinkRetainingCapacity(kept);

    var blocking: usize = 0;
    var reporting: usize = 0;
    for (findings.items) |*finding| {
        // A finding the rule only ever reports, and a change-scoped rule's
        // finding outside the diff, never refuses. Without `--gate` (or
        // `on_build: "block"`) a block rule still only reports; the severity is
        // demoted here, after the store has seen it.
        if (finding.state.report_only or (finding.state.change_scoped and !finding.state.changed)) finding.state.severity = .warning;
        if (finding.state.severity == .err and !force_block) finding.state.severity = .warning;
        if (finding.state.severity == .err) blocking += 1 else reporting += 1;
    }

    return .{
        .findings = findings.items,
        .blocking = blocking,
        .reporting = reporting,
        .waived = waived,
        .accepted = accepted,
    };
}

/// Drop findings whose own file opens with a `# generated by …` line: the file
/// says a build wrote it, so its shape is not a review surface.
fn dropGeneratedFindings(src: source.Source, findings: *std.ArrayList(Finding)) void {
    var kept: usize = 0;
    for (findings.items) |finding| {
        if (isGeneratedLocation(src, src.locate(finding.span.start).path)) continue;
        findings.items[kept] = finding;
        kept += 1;
    }
    findings.shrinkRetainingCapacity(kept);
}

/// Drop findings located in an embedded standard-library module. A project
/// imports the standard library the way it imports its own modules, but its
/// declarations are not the project's to review; a run whose own entry is in the
/// standard library keeps them.
fn dropStandardLibraryFindings(src: source.Source, entry_path: []const u8, findings: *std.ArrayList(Finding)) void {
    if (std.mem.startsWith(u8, entry_path, "@stdlib/")) return;
    if (std.mem.startsWith(u8, src.path, "@stdlib/")) return;
    var kept: usize = 0;
    for (findings.items) |finding| {
        if (std.mem.startsWith(u8, src.locate(finding.span.start).path, "@stdlib/")) continue;
        findings.items[kept] = finding;
        kept += 1;
    }
    findings.shrinkRetainingCapacity(kept);
}

/// Whether the file at `path` is one of `src`'s own files and opens with the
/// generated marker. A merged project source answers per module, so one
/// generated module does not exempt its neighbours.
fn isGeneratedLocation(src: source.Source, path: []const u8) bool {
    if (std.mem.eql(u8, src.path, path)) return opensGenerated(src.bytes);
    for (src.origins) |origin| {
        if (!std.mem.eql(u8, origin.original.path, path)) continue;
        return opensGenerated(origin.original.bytes);
    }
    return false;
}

/// Whether `bytes` opens with the generated marker (`# generated by …`, in any letter
/// case), the shared rule the change review also uses; see `generated_marker.zig`.
fn opensGenerated(bytes: []const u8) bool {
    return generated_marker.isGenerated(bytes);
}

/// The profile one run judges under: `--profile`, else the configured one, else `agent`.
fn profileOf(request: Request) lint_config.Profile {
    return request.options.profile orelse if (request.config) |config| config.profile else .agent;
}

/// Whether the run makes every `block` rule refusing: `--gate`, or a configured `on_build: "block"`.
fn forcesBlock(request: Request) bool {
    return request.options.gate or (if (request.config) |config| config.on_build == .block else false);
}

/// What a failed analysis (`Data.analysis_failed`) left unjudged in one run: which of the rules that read `Data.sites` are on,
/// and whether the run refuses for it. A gate that passes says every blocking rule was judged, so it refuses (status 3) when
/// `copy-in-loop`, which blocks in a changed declaration, could not be judged. `alloc-in-loop` only reports.
pub const Unjudged = struct {
    alloc_in_loop: bool = false,
    copy_in_loop: bool = false,
    refuses: bool = false,
};

/// The rules the failed analysis of `request` left unjudged; all false when the analysis did not fail.
pub fn unjudged(request: Request) Unjudged {
    if (request.data.analysis_failed == null) return .{};
    var result: Unjudged = .{};
    for (rules) |rule| {
        const mode = requestedMode(rule, resolveMode(rule, profileOf(request), request.config), request.options.rule);
        if (mode == .off) continue;
        if (std.mem.eql(u8, rule.name, rule_alloc_in_loop)) result.alloc_in_loop = true;
        if (!std.mem.eql(u8, rule.name, rule_copy_in_loop)) continue;
        result.copy_in_loop = true;
        result.refuses = forcesBlock(request) and mode == .block;
    }
    return result;
}

/// Lint one already-checked project. Returns the process status.
pub fn run(request: Request) RunError!u8 {
    return runUsing(request, .reference);
}

/// Run with an explicit component adapter; production commands supply this.
pub fn runUsing(request: Request, adapter: component_adapter.Adapter) RunError!u8 {
    var arena = std.heap.ArenaAllocator.init(request.memory);
    defer arena.deinit();
    const outcome = try evaluateUsing(request, arena.allocator(), adapter);
    try renderFindings(request, outcome.findings);
    const summary = try std.fmt.allocPrint(request.memory, "lint: {d} finding(s): {d} blocking, {d} report, {d} waived, {d} accepted\n", .{
        outcome.findings.len, outcome.blocking, outcome.reporting, outcome.waived, outcome.accepted,
    });
    defer request.memory.free(summary);
    try std.Io.File.stdout().writeStreamingAll(request.io, summary);
    return if (outcome.blocking > 0 or unjudged(request).refuses) blocked_status else clean_status;
}

/// How one rule's findings take their severity: the block mode also decides
/// that the finding prints in full in every run.
const WaiverFilter = struct {
    start: usize,
    waived: *usize,
    severity: diagnostic.Severity,
    block: bool,
    change_scoped: bool = false,
};

/// Drop waived findings from `items[filter.start..]` in place and set each
/// survivor's severity and block mode, counting one waiver per drop.
fn filterWaived(waivers: []const Waiver, src: source.Source, items: []Finding, filter: WaiverFilter) usize {
    var kept = filter.start;
    for (items[filter.start..]) |finding| {
        if (isWaived(waivers, finding, src)) {
            filter.waived.* += 1;
            continue;
        }
        var kept_finding = finding;
        kept_finding.state.severity = filter.severity;
        kept_finding.state.blocks_under_gate = filter.block;
        kept_finding.state.change_scoped = filter.change_scoped;
        items[kept] = kept_finding;
        kept += 1;
    }
    return kept;
}

/// The `--against REF` diff one run consults. One module's changed-line ranges
/// are read from `git` on first use and cached, so a run spawns one diff per
/// module however many findings it judges.
const ChangeMarks = struct {
    diff: declaration_diff.Diff,
    program: typed.Program,

    fn init(scratch: std.mem.Allocator, scope: ChangeScope, compilation: *project_compile.Compilation) std.mem.Allocator.Error!ChangeMarks {
        const modules = compilation.index.project.modules.items;
        const cache = try scratch.alloc(declaration_diff.ModuleDiff, modules.len);
        @memset(cache, .{});
        return .{
            .diff = .{
                .memory = scratch,
                .io = scope.io,
                .repo_root = scope.repo_root,
                .reference = scope.reference,
                .index = compilation.index,
                .src = compilation.src,
                .cache = cache,
            },
            .program = compilation.program.?,
        };
    }

    /// Whether the declaration `finding` names intersects the diff. A finding
    /// with a checked subject judges that function's declaration and body, which
    /// is the same union `change-without-test` reads; a finding without one
    /// judges its own span.
    fn changed(self: ChangeMarks, finding: Finding) bool {
        if (finding.subject.qualified.len != 0) {
            for (self.program.functions) |function| {
                if (!std.mem.eql(u8, function.name, finding.subject.qualified)) continue;
                const body = self.program.statements[@backingInt(function.scope.body)].span;
                return self.diff.changed(.{
                    .start = @min(function.declaration.start, body.start),
                    .end = @max(function.declaration.end, body.end),
                }) catch false;
            }
        }
        return self.diff.changed(finding.span) catch false;
    }
};

/// Row identity recorded in a baseline file: `<module>|<qualified>`.
fn baselineRow(scratch: std.mem.Allocator, finding: Finding) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(scratch, "{s}|{s}", .{ finding.subject.module, finding.subject.qualified });
}

/// Whether a rule may record accepted debt in a baseline store. Change-time
/// rules judge a diff, not the tree's standing state, so a stored row would
/// silence a later refusal that no reviewer ever saw; they are never adopted
/// and an existing row never suppresses them.
fn baselineEligible(rule: []const u8) bool {
    if (changeScoped(rule)) return false;
    return !std.mem.eql(u8, rule, rule_change_without_test) and
        !std.mem.eql(u8, rule, rule_noalloc_allocates) and
        !std.mem.eql(u8, rule, rule_needless_copy);
}

/// Whether one rule only refuses in a declaration changed against `--against REF`.
fn changeScoped(rule: []const u8) bool {
    for (rules) |entry| if (std.mem.eql(u8, entry.name, rule)) return entry.change_scoped;
    return false;
}

/// Whether one rule reports only in a declaration changed against `--against REF`.
fn reportsOnlyInChange(rule: []const u8) bool {
    for (rules) |entry| if (std.mem.eql(u8, entry.name, rule)) return entry.reports_only_in_change;
    return false;
}

/// Whether a blocking finding's row is already accepted debt. A missing or
/// unreadable store leaves the finding blocking.
fn baselineContains(scratch: std.mem.Allocator, io: std.Io, root: []const u8, finding: Finding) RunError!bool {
    if (!baselineEligible(finding.rule)) return false;
    var baseline = lint_store.loadBaseline(scratch, io, root, finding.rule) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return false,
    };
    defer baseline.deinit();
    const row = try baselineRow(scratch, finding);
    return baseline.contains(row);
}

/// `--accept`: rewrite every rule's baseline to exactly the current blocking
/// findings, so resolved debt disappears and new debt is recorded. A
/// change-time rule has no baseline to rewrite.
fn acceptFindings(scratch: std.mem.Allocator, io: std.Io, root: []const u8, findings: []const Finding) RunError!void {
    for (rules) |rule| {
        if (!baselineEligible(rule.name)) continue;
        var baseline: lint_store.Baseline = .{ .allocator = scratch };
        defer baseline.deinit();
        for (findings) |finding| {
            if (finding.state.severity != .err) continue;
            if (!std.mem.eql(u8, finding.rule, rule.name)) continue;
            try baseline.record(try baselineRow(scratch, finding));
        }
        try lint_store.saveBaseline(&baseline, scratch, io, root, rule.name);
    }
}

/// One directive comment found in the checked source.
pub const Waiver = struct {
    rule: []const u8,
    line: usize,
    has_reason: bool,
    span: source.Span,
    reason: ?[]const u8 = null,
    /// `# lint: allow-file` covers every finding of `rule` in this file, not
    /// only the declaration directly below it.
    file_wide: bool = false,
};

/// True when a waiver on the line above `finding`'s declaration covers it.
pub fn isWaived(waivers: []const Waiver, finding: Finding, src: source.Source) bool {
    const span = if (std.mem.eql(u8, finding.rule, rule_noalloc_allocates) and finding.related != null) finding.related.?.span else finding.span;
    const line = src.physicalLocation(span.start).line;
    for (waivers) |waiver| {
        if (!std.mem.eql(u8, waiver.rule, finding.rule)) continue;
        if (waiver.file_wide or waiver.line + 1 == line) return true;
    }
    return false;
}

/// Walk every source line for `# lint: allow <rule> reason="..."` comments.
fn scanWaivers(scratch: std.mem.Allocator, src: source.Source, waivers: *std.ArrayList(Waiver)) !void {
    const marker = "# lint:";
    var cursor: usize = 0;
    while (std.mem.indexOfPos(u8, src.bytes, cursor, marker)) |at| {
        const end_of_line = std.mem.indexOfScalarPos(u8, src.bytes, at, '\n') orelse src.bytes.len;
        const comment = src.bytes[at..end_of_line];
        cursor = end_of_line;
        const parsed = try parseWaiver(scratch, comment, at, src.physicalLocation(at).line);
        if (parsed) |waiver| try waivers.append(scratch, waiver);
    }
}

fn parseWaiver(scratch: std.mem.Allocator, comment: []const u8, offset: usize, line: usize) std.mem.Allocator.Error!?Waiver {
    const after = std.mem.trim(u8, comment["# lint:".len..], " \t");
    if (!std.mem.startsWith(u8, after, "allow")) return null;
    const file_wide = std.mem.startsWith(u8, after, "allow-file");
    const rest = std.mem.trim(u8, after[if (file_wide) "allow-file".len else "allow".len..], " \t");
    const space = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    const rule = rest[0..space];
    if (rule.len == 0) return null;
    const reason = commentReason(rest);
    const has_reason = if (reason) |text| std.mem.trim(u8, text, " \t\r\n").len != 0 else false;
    return .{
        .rule = try scratch.dupe(u8, rule),
        .line = line,
        .has_reason = has_reason,
        .reason = reason,
        .span = .{ .start = offset, .end = offset + comment.len },
        .file_wide = file_wide,
    };
}

fn commentReason(text: []const u8) ?[]const u8 {
    const start = (std.mem.indexOf(u8, text, "reason=") orelse return null) + "reason=".len;
    if (start >= text.len or (text[start] != '"' and text[start] != '\'')) return null;
    var end = start + 1;
    while (end < text.len) : (end += 1) {
        if (text[end] == text[start]) return text[start + 1 .. end];
        if (text[end] == '\\') end += 1;
    }
    return null;
}

/// Return a nonempty waiver reason for this declaration and rule, using exactly
/// lint's adjacent comment and @allow matching. The returned reason borrows src.
pub fn waiverReason(memory: std.mem.Allocator, src: source.Source, syntax: ast.Program, declaration: source.Span, rule: []const u8) std.mem.Allocator.Error!?[]const u8 {
    var waivers: std.ArrayList(Waiver) = .empty;
    try scanWaivers(memory, src, &waivers);
    try scanAttributeWaivers(memory, src, syntax, &waivers);
    const line = src.physicalLocation(declaration.start).line;
    for (waivers.items) |waiver| {
        if (!waiver.has_reason or !std.mem.eql(u8, waiver.rule, rule)) continue;
        if (waiver.file_wide or waiver.line + 1 == line) return waiver.reason;
    }
    return null;
}

/// Add one waiver per `@allow("rule", reason="...")` attribute. The waiver is
/// keyed to the line above its declaration, matching the comment spelling it
/// replaces; a missing `reason=` still becomes a blocking `L_WAIVER_REASON`.
pub fn scanAttributeWaivers(scratch: std.mem.Allocator, src: source.Source, syntax: ast.Program, waivers: *std.ArrayList(Waiver)) std.mem.Allocator.Error!void {
    for (syntax.attributes) |entry| {
        const declaration_line = src.physicalLocation(entry.declaration.start).line;
        const line = if (declaration_line > 0) declaration_line - 1 else 0;
        for (entry.attributes) |attribute| {
            if (attribute.kind != .allow) continue;
            const argument = attribute.argument orelse continue;
            try waivers.append(scratch, .{
                .rule = try scratch.dupe(u8, stripLiteral(src.bytes[argument.start..argument.end])),
                .line = line,
                .has_reason = if (attribute.reason) |span| std.mem.trim(u8, stripLiteral(src.text(span)), " \t\r\n").len != 0 else false,
                .reason = if (attribute.reason) |span| stripLiteral(src.text(span)) else null,
                .span = attribute.span,
            });
        }
    }
}

/// Remove the matching quotes around one string-literal spelling.
fn stripLiteral(text: []const u8) []const u8 {
    if (text.len >= 2 and (text[0] == '"' or text[0] == '\'')) return text[1 .. text.len - 1];
    return text;
}

/// Every waiver missing a `reason=` becomes a `L_WAIVER_REASON` finding.
fn appendWaiverReasonFindings(scratch: std.mem.Allocator, waivers: []const Waiver, findings: *std.ArrayList(Finding)) !void {
    for (waivers) |waiver| {
        if (waiver.has_reason) continue;
        const message = try std.fmt.allocPrint(scratch, "{s}: waiver for {s} is missing a reason=\"...\" clause", .{ rule_waiver_reason, waiver.rule });
        try findings.append(scratch, .{
            .code = "L_WAIVER_REASON",
            .rule = rule_waiver_reason,
            .span = waiver.span,
            .message = message,
            .subject = .{ .qualified = waiver.rule },
        });
    }
}

/// Render findings through the shared diagnostic renderer, honoring `--json`
/// and the global `--diagnostics` format.
///
/// A run prints in full only the findings an agent must act on: the findings
/// that block in this run (a `block` rule's under `--gate`, or a project that
/// sets `on_build: "block"`) and every finding in a declaration changed against
/// `--against REF`. Every other finding prints as one count line per code, so a
/// project’s default output stays readable; `--all` lists everything, and
/// `--json` is unchanged and always complete (P2). The count lines never hide a
/// finding that would refuse: those print in full above them.
fn renderFindings(request: Request, findings: []const Finding) !void {
    const format: diagnostic_output.Format = if (request.options.json) .json else request.data.diagnostics;
    if (request.options.json or request.options.all) return renderEach(request, findings, format);
    var hidden: std.array_hash_map.String(usize) = .empty;
    defer hidden.deinit(request.memory);
    for (findings) |finding| {
        if (finding.state.severity == .err or finding.state.changed) {
            try renderOne(request, finding, format);
            continue;
        }
        const entry = try hidden.getOrPut(request.memory, finding.code);
        if (!entry.found_existing) entry.value_ptr.* = 0;
        entry.value_ptr.* += 1;
    }
    for (hidden.keys(), hidden.values()) |code, count| {
        const line = try std.fmt.allocPrint(request.memory, "{s}: {d} {s} (selka lint --all lists them)\n", .{
            code, count, if (count == 1) "finding" else "findings",
        });
        defer request.memory.free(line);
        try std.Io.File.stderr().writeStreamingAll(request.io, line);
    }
}

/// Render every finding in full, in the order the rules produced them.
fn renderEach(request: Request, findings: []const Finding, format: diagnostic_output.Format) !void {
    for (findings) |finding| try renderOne(request, finding, format);
}

/// Render one finding through the shared diagnostic renderer.
fn renderOne(request: Request, finding: Finding, format: diagnostic_output.Format) !void {
    const item: diagnostic.Diagnostic = .{
        .code = finding.code,
        .severity = finding.state.severity,
        .span = finding.span,
        .message = finding.message,
        .related = finding.related,
    };
    friction_session.note(item);
    const rendered = try diagnostic_output.render(request.memory, item, request.compilation.src, format);
    defer request.memory.free(rendered);
    try std.Io.File.stderr().writeStreamingAll(request.io, rendered);
}

/// Whether a qualified declaration name is a discovered test for coverage.
fn isTestName(qualified: []const u8) bool {
    return std.mem.startsWith(u8, localName(qualified), "test_");
}

/// Names a declaration is exempt from because the compiler or a test runner
/// owns it rather than the project.
fn isSyntheticOrEntry(name: []const u8) bool {
    const local = localName(name);
    return std.mem.eql(u8, local, "main") or
        std.mem.startsWith(u8, local, "test_") or
        std.mem.startsWith(u8, local, "bench_") or
        std.mem.startsWith(u8, name, "lambda@") or
        @import("invariant_callbacks.zig").isName(name) or
        std.mem.eql(u8, name, "__selka_entry");
}

fn configuredExempt(context: *RuleContext, rule: []const u8, qualified: []const u8) bool {
    return configuredExemptFrom(context.config, rule, qualified);
}

/// Whether `qualified` carries a reasoned `exempt` entry for `rule`.
fn configuredExemptFrom(config: ?*const lint_config.Config, rule: []const u8, qualified: []const u8) bool {
    const settings = config orelse return false;
    const setting = settings.setting(rule) orelse return false;
    for (setting.exempt) |item| {
        if (std.mem.eql(u8, item.name, qualified)) return true;
    }
    return false;
}

/// W2 `untested-export`: every exported declaration, and every public method
/// of an exported domain, must be reached by a discovered test. The `agent`
/// profile accepts an export any test reaches, directly or transitively, so a
/// reached accessor is never reported as untested; `strict` and `safety` keep
/// the direct-call fact and say "reached only transitively" when the only
/// evidence is indirect. Both readings come from the run's one shared index.
fn runUntestedExport(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const transitive_is_tested = context.reach.profile == .agent;
    for (facts.roots.exports) |id| {
        const index = @backingInt(id);
        const function = facts.program.functions[index];
        if (isSyntheticOrEntry(function.name)) continue;
        if (facts.isTest(id)) continue;
        if (id == facts.program.main) continue;
        if (configuredExempt(context, rule_test_coverage, function.name)) continue;
        // A docstring example is a test too (FR-415): naming the export is a
        // direct call, and in `agent` what the example reaches counts as well.
        if (facts.roots.isExampleTested(id)) continue;
        if (transitive_is_tested and facts.roots.isExampleReached(id)) continue;
        const answer = if (context.reach.index) |shared| shared.answer(id) else tests_index.Answer{};
        if (answer.direct.len != 0) continue;
        if (transitive_is_tested and answer.reached.len != 0) continue;
        const message = if (answer.reached.len != 0)
            try std.fmt.allocPrint(context.memory, "{s}: exported {s} is reached only transitively; no test calls it directly", .{ rule_untested_export, function.name })
        else if (transitive_is_tested)
            try std.fmt.allocPrint(context.memory, "{s}: exported {s} is not reached by any discovered test", .{ rule_untested_export, function.name })
        else
            try std.fmt.allocPrint(context.memory, "{s}: exported {s} is not called directly by any test_ function", .{ rule_untested_export, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_UNTESTED_EXPORT",
            .rule = rule_untested_export,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// What the syntax says about module constants. A `const NAME: T = ...` declaration is checked
/// as a zero-parameter getter function, and a scalar constant's reads fold to their literal
/// before checking ends, so the call graph shows neither a call site nor a function-shaped
/// name: the rules that judge functions need the syntax to tell a constant from a function.
const ConstantFacts = struct {
    /// Start offsets (checked-source coordinates) of every constant declaration's name.
    declared: std.AutoHashMapUnmanaged(usize, void) = .empty,
    /// `input:name` for every plain name read in module `input`, and `*:name` for every field
    /// read (`module.NAME`), whatever module it names.
    reads: std.StringHashMapUnmanaged(void) = .empty,
    /// `input:name` for every unqualified call written inside a constant's initializer: the function it evaluates, which the checked
    /// program shows no call of because the constant folds to its value.
    calls: std.StringHashMapUnmanaged(void) = .empty,

    /// Whether the checked function declared at `span` is a module constant.
    fn declares(self: ConstantFacts, span: source.Span) bool {
        return self.declared.contains(span.start);
    }

    /// Whether the function declared at `span` is called from a constant's initializer.
    fn calledByConstant(self: ConstantFacts, context: *RuleContext, span: source.Span) std.mem.Allocator.Error!bool {
        const src = context.facts.src;
        const original = src.originalSpan(span) catch return false;
        return self.calls.contains(try std.fmt.allocPrint(context.memory, "{d}:{s}", .{ original.input, src.text(span) }));
    }

    /// Whether the constant declared at `span` is read: by a plain name in its own module and,
    /// when `anywhere`, by a field read (`module.NAME`) in any module.
    fn read(self: ConstantFacts, context: *RuleContext, span: source.Span, anywhere: bool) std.mem.Allocator.Error!bool {
        const src = context.facts.src;
        const original = src.originalSpan(span) catch return false;
        const name = src.text(span);
        if (self.reads.contains(try std.fmt.allocPrint(context.memory, "{d}:{s}", .{ original.input, name }))) return true;
        return anywhere and self.reads.contains(try std.fmt.allocPrint(context.memory, "*:{s}", .{name}));
    }
};

/// Collect the module constants of the checked program and how their names are read.
fn constantFacts(context: *RuleContext) std.mem.Allocator.Error!ConstantFacts {
    var facts: ConstantFacts = .{};
    const syntax = context.facts.syntax;
    const src = context.facts.src;
    for (syntax.functions) |function| {
        if (function.policy.constant) try facts.declared.put(context.memory, function.name.start, {});
    }
    if (facts.declared.count() == 0) return facts;
    var initializers: std.ArrayList(source.Span) = .empty;
    for (syntax.functions) |function| {
        if (function.policy.constant) try initializers.append(context.memory, syntax.statements.items[@backingInt(function.body)].span);
    }
    for (syntax.nodes.items) |node| switch (node.data) {
        .call => |call| {
            if (std.mem.indexOfScalar(u8, src.text(call.name), '.') != null) continue;
            for (initializers.items) |initializer| {
                if (node.span.start < initializer.start or node.span.end > initializer.end) continue;
                const original = src.originalSpan(call.name) catch continue;
                try facts.calls.put(context.memory, try std.fmt.allocPrint(context.memory, "{d}:{s}", .{ original.input, src.text(call.name) }), {});
                break;
            }
        },
        .name => |name| {
            const original = src.originalSpan(name) catch continue;
            try facts.reads.put(context.memory, try std.fmt.allocPrint(context.memory, "{d}:{s}", .{ original.input, src.text(name) }), {});
        },
        .field => |field| try facts.reads.put(context.memory, try std.fmt.allocPrint(context.memory, "*:{s}", .{src.text(field.name)}), {}),
        else => {},
    };
    return facts;
}

/// W2 `dead-private`: a private declaration with no call site anywhere in the
/// checked program is a leftover from a repair loop. A private constant is dead
/// only when no name in its module reads it.
fn runDeadPrivate(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const constants = try constantFacts(context);
    for (facts.program.functions, 0..) |function, index| {
        const id: typed.FunctionId = @fromBackingInt(@intCast(index));
        if (id == facts.program.main) continue;
        if (facts.isExport(id)) continue;
        if (isSyntheticOrEntry(function.name)) continue;
        if (facts.functions[index].incoming_sites != 0) continue;
        if (facts.roots.isValueReferenced(id)) continue;
        if (facts.roots.isExampleTested(id)) continue;
        if (constants.declares(function.declaration) and try constants.read(context, function.declaration, false)) continue;
        if (try constants.calledByConstant(context, function.declaration)) continue;
        if (configuredExempt(context, rule_dead_private, function.name)) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: private {s} has no call site", .{ rule_dead_private, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_DEAD_PRIVATE",
            .rule = rule_dead_private,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// W2 `test-no-assertion`: a discovered test whose body never asserts cannot
/// fail, which makes it worse than no test at all.
fn runTestNoAssertion(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.roots.tests) |id| {
        const function = facts.program.functions[@backingInt(id)];
        if (configuredExempt(context, rule_test_no_assertion, function.name)) continue;
        const body = try scanTestBody(context.memory, facts.program, function.scope.body);
        if (body.has_assert) continue;
        if (!body.has_return) continue;
        if (!body.all_returns_true) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: test {s} has no assert statement", .{ rule_test_no_assertion, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_TEST_NO_ASSERTION",
            .rule = rule_test_no_assertion,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// W2 `test-conditional`: table-driven data belongs in `--cases`, so a branch,
/// loop or match at the top level of a test body is a finding.
fn runTestConditional(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.roots.tests) |id| {
        const function = facts.program.functions[@backingInt(id)];
        if (configuredExempt(context, rule_test_conditional, function.name)) continue;
        const top = topLevelStatements(facts.program, function.scope.body);
        if (!hasTopLevelControl(facts.program, top)) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: test {s} has a top-level conditional or loop", .{ rule_test_conditional, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_TEST_CONDITIONAL",
            .rule = rule_test_conditional,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// W2 `test-empty`: a discovered test with an empty body asserts nothing.
fn runTestEmpty(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.roots.tests) |id| {
        const function = facts.program.functions[@backingInt(id)];
        if (configuredExempt(context, rule_test_empty, function.name)) continue;
        if (topLevelStatements(facts.program, function.scope.body).len != 0) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: test {s} has an empty body", .{ rule_test_empty, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_TEST_EMPTY",
            .rule = rule_test_empty,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// The top-level statements of one block body.
fn topLevelStatements(program: typed.Program, id: typed.StatementId) []const typed.StatementId {
    return switch (program.statements[@backingInt(id)].data) {
        .block => |list| list,
        else => &.{},
    };
}

/// Whether a test body's top level carries a conditional: any branch or match
/// always violates, and more than one loop (table-driven cases) does too. A
/// single loop is allowed because a `for` over a fixed table is idiomatic and
/// the typed form does not distinguish it from `while`; a false negative is
/// safe for a blocking rule, a false positive is not.
fn hasTopLevelControl(program: typed.Program, top: []const typed.StatementId) bool {
    var loops: usize = 0;
    for (top) |id| {
        switch (program.statements[@backingInt(id)].data) {
            .branch, .match => return true,
            .loop, .range_loop => loops += 1,
            else => {},
        }
    }
    return loops > 1;
}

/// What one test body contains, for the W2 hygiene rules.
const TestBody = struct {
    has_assert: bool = false,
    has_return: bool = false,
    all_returns_true: bool = true,
};

/// Record one `return` value: the body has a return, and it is the literal
/// `true` only when the node is `.boolean true`.
fn recordReturn(program: typed.Program, value: typed.NodeId, body: *TestBody) void {
    body.has_return = true;
    switch (program.nodes[@backingInt(value)].data) {
        .boolean => |literal| body.all_returns_true = body.all_returns_true and literal,
        else => body.all_returns_true = false,
    }
}

/// Scan every statement reachable from `root` for an `assert` and for whether
/// each `return` yields the boolean literal `true`.
fn scanTestBody(scratch: std.mem.Allocator, program: typed.Program, root: typed.StatementId) std.mem.Allocator.Error!TestBody {
    var body: TestBody = .{};
    var pending: std.ArrayList(typed.StatementId) = .empty;
    defer pending.deinit(scratch);
    try pending.append(scratch, root);
    while (pending.pop()) |id| {
        const statement = program.statements[@backingInt(id)];
        switch (statement.data) {
            .assertion => body.has_assert = true,
            .ret => |value| recordReturn(program, value, &body),
            .block => |list| for (list) |child| try pending.append(scratch, child),
            .with_scope => |scope| try pending.append(scratch, scope.body),
            .branch => |branch| {
                try pending.append(scratch, branch.then_body);
                if (branch.else_body) |otherwise| try pending.append(scratch, otherwise);
            },
            .match => |matching| for (matching.arms) |arm| try pending.append(scratch, arm.body),
            .range_loop => |range| {
                try pending.appendSlice(scratch, range.plan().setup);
                try pending.append(scratch, range.plan().loop.body);
                if (range.plan().loop.step) |step| try pending.append(scratch, step);
            },
            .loop => |loop| {
                try pending.append(scratch, loop.body);
                if (loop.step) |step| try pending.append(scratch, step);
            },
            else => {},
        }
    }
    return body;
}

/// The effective `max` for one rule: its configured value, else the default.
fn configuredMax(context: *RuleContext, rule: []const u8, fallback: usize) usize {
    const config = context.config orelse return fallback;
    const setting = config.setting(rule) orelse return fallback;
    return setting.max orelse fallback;
}

/// Append one report-only budget finding with the measured value and limit.
fn appendBudgetFinding(context: *RuleContext, rule: []const u8, code: []const u8, function: typed.Function, measured: usize, limit: usize) std.mem.Allocator.Error!void {
    const message = try std.fmt.allocPrint(context.memory, "{s}: {s} measures {d} (max {d})", .{ rule, function.name, measured, limit });
    try context.findings.append(context.memory, .{
        .code = code,
        .rule = rule,
        .span = function.declaration,
        .message = message,
        .subject = .{ .module = moduleName(function.name), .qualified = function.name },
    });
}

/// Section 9 `function-length`: report a function over its line budget.
fn runFunctionLength(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_function_length, default_max_function_lines);
    for (context.facts.program.functions, 0..) |function, index| {
        if (isSyntheticOrEntry(function.name)) continue;
        const measured = context.facts.functions[index].structure.lines;
        if (measured <= limit) continue;
        try appendBudgetFinding(context, rule_function_length, "L_FUNCTION_LENGTH", function, measured, limit);
    }
}

/// Section 9 `parameters`: report a function over its parameter budget.
fn runParameters(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_parameters, default_max_parameters);
    for (context.facts.program.functions, 0..) |function, index| {
        if (isSyntheticOrEntry(function.name)) continue;
        const measured = context.facts.functions[index].structure.parameters;
        if (measured <= limit) continue;
        try appendBudgetFinding(context, rule_parameters, "L_PARAMETER_COUNT", function, measured, limit);
    }
}

/// Section 9 `nesting-depth`: report a function over its control-nesting budget.
fn runNestingDepth(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_nesting_depth, default_max_nesting);
    for (context.facts.program.functions, 0..) |function, index| {
        if (isSyntheticOrEntry(function.name)) continue;
        const measured = context.facts.functions[index].structure.nesting;
        if (measured <= limit) continue;
        try appendBudgetFinding(context, rule_nesting_depth, "L_NESTING_DEPTH", function, measured, limit);
    }
}

/// §3.5 `data-clump` (proposal 9): a function writes three or more of its
/// caller's arguments at two or more call sites, so the group is a record in
/// waiting and the rewrite is to introduce it and pass one argument.
fn runDataClump(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const calls = try context.memory.alloc(usize, facts.program.functions.len);
    @memset(calls, 0);
    for (facts.program.nodes) |node| switch (node.data) {
        .call => |call| {
            const index = @backingInt(call.function);
            if (index < calls.len) calls[index] += 1;
        },
        else => {},
    };
    for (facts.program.functions, 0..) |function, index| {
        if (isSyntheticOrEntry(function.name)) continue;
        const written = function.signature.mutates.len;
        if (written < 3 or calls[index] < 2) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: {s} writes {d} caller arguments at {d} call sites; group them into a record and pass one argument", .{ rule_data_clump, function.name, written, calls[index] });
        try context.findings.append(context.memory, .{
            .code = "L_DATA_CLUMP",
            .rule = rule_data_clump,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// §3.4 `copy-for-store`: a parameter is `copy`-ed into storage, where an
/// `own` parameter takes the value without a copy. Report only: the copy is
/// correct, and changing the parameter moves the caller's binding, so the
/// reader decides whether every call site can give the value up. The
/// detection, and the parameters `own` cannot be advised for, live in `copy_for_store.zig`.
fn runCopyForStore(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        const copies = try copy_for_store.storedCopies(context.memory, context.facts.program, function);
        for (copies) |copied| {
            if (warnedByCheck(context, function, copies, copied.parameter)) continue;
            try reportCopyForStore(context, function, copied.span, copied.parameter);
        }
    }
}

/// Whether the check's `W_COPY_FOR_STORE` already names this parameter, at one of its stored copies, with the repair that
/// declares it `own`: the advice would say it again.
fn warnedByCheck(context: *RuleContext, function: typed.Function, copies: []const copy_for_store.Copy, parameter: usize) bool {
    const name = function.scope.locals[parameter].name;
    for (context.facts.diagnostics) |item| {
        const judged = copy_for_store.judged(item.code, item.message) orelse continue;
        if (!std.mem.eql(u8, judged.parameter, name)) continue;
        for (copies) |copied| {
            if (copied.parameter == parameter and copied.span.start == item.span.start and copied.span.end == item.span.end) return true;
        }
    }
    return false;
}

/// Append one finding for a parameter copied into storage.
fn reportCopyForStore(context: *RuleContext, function: typed.Function, span: source.Span, parameter: usize) std.mem.Allocator.Error!void {
    const name = function.scope.locals[parameter].name;
    const message = try std.fmt.allocPrint(context.memory, "{s}: {s} copies parameter `{s}` into storage; declare it `own` and pass `own {s}` " ++
        "where every caller can give the value up", .{ rule_copy_for_store, function.name, name, name });
    try context.findings.append(context.memory, .{
        .code = "L_COPY_FOR_STORE",
        .rule = rule_copy_for_store,
        .span = span,
        .message = message,
        .subject = .{ .module = moduleName(function.name), .qualified = function.name },
    });
}

/// §3.5 `double-lookup` (proposal 18): one statement probes a dictionary key
/// and then writes it, two probes where `dicts.add` or `dicts.append_to` need one.
fn runDoubleLookup(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        try checkFunctionDoubleLookup(context, function);
    }
}

/// Judge every store statement of one function body for a doubled probe.
fn checkFunctionDoubleLookup(context: *RuleContext, function: typed.Function) std.mem.Allocator.Error!void {
    var walker = try walk.Walker.init(context.memory, context.facts.program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        const id = switch (item) {
            .statement => |value| value,
            else => continue,
        };
        try checkDoubleLookup(context, function, id);
    }
}

/// Report one store statement that reads the key it writes.
fn checkDoubleLookup(context: *RuleContext, function: typed.Function, id: typed.StatementId) std.mem.Allocator.Error!void {
    const facts = context.facts;
    switch (facts.program.statements[@backingInt(id)].data) {
        .discard => {},
        else => return,
    }
    var reads: std.ArrayList([]const u8) = .empty;
    defer reads.deinit(context.memory);
    var writes: std.ArrayList([]const u8) = .empty;
    defer writes.deinit(context.memory);
    var walker = try walk.Walker.init(context.memory, facts.program, id);
    defer walker.deinit();
    while (try walker.next()) |item| {
        const node = switch (item) {
            .expression => |value| facts.program.nodes[@backingInt(value)],
            else => continue,
        };
        switch (node.data) {
            .buffer_operation => |op| try collectProbe(context, op.kind, op.arguments, &reads, &writes),
            .index => |index| {
                if (!isDictionary(facts, facts.program.nodes[@backingInt(index.base)].ty)) continue;
                try reads.append(context.memory, facts.src.text(facts.program.nodes[@backingInt(index.index)].span));
            },
            else => {},
        }
    }
    for (writes.items) |written| {
        for (reads.items) |read| {
            if (!std.mem.eql(u8, written, read)) continue;
            const message = try std.fmt.allocPrint(context.memory, "{s}: {s} probes {s} twice in one statement; " ++
                "`dicts.add(mut d, k, delta)` or `dicts.append_to(mut d, k, item)` probes once", .{ rule_double_lookup, function.name, written });
            try context.findings.append(context.memory, .{
                .code = "L_DOUBLE_LOOKUP",
                .rule = rule_double_lookup,
                .span = facts.program.statements[@backingInt(id)].span,
                .message = message,
                .subject = .{ .module = moduleName(function.name), .qualified = function.name },
            });
            return;
        }
    }
}

/// Sort one buffer operation into the read or write probe lists by its key.
/// The key's own source spelling is the identity a doubled probe compares:
/// the checked key node keeps the literal's span even when the operation is
/// rewritten, so two probes of one key spell it the same way.
fn collectProbe(context: *RuleContext, kind: BufferOperation, arguments: []const typed.NodeId, reads: *std.ArrayList([]const u8), writes: *std.ArrayList([]const u8)) std.mem.Allocator.Error!void {
    if (arguments.len == 0) return;
    const key = context.facts.src.text(context.facts.program.nodes[@backingInt(arguments[0])].span);
    switch (kind) {
        .write => try writes.append(context.memory, key),
        .get, .find, .contains => try reads.append(context.memory, key),
        else => {},
    }
}

/// Whether one checked type is a dictionary: a managed mapping collection, as
/// `set[T]` is its mapping-to-unit sibling.
fn isDictionary(facts: *const Facts, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= facts.program.records.len) return false;
    const record = facts.program.records[ty.recordIndex()];
    return record.managed and record.collection.kind == .dictionary and !record.collection.set;
}

/// §3.5 `counting-while` (proposal 19): `mut i = start` / `while i < bound:` /
/// `i += 1`, the shape `for i in range(start, bound):` says in one line.
fn runCountingWhile(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        try checkFunctionCountingWhile(context, function);
    }
}

/// Offer the rewrite at every counted `while` in one function body.
fn checkFunctionCountingWhile(context: *RuleContext, function: typed.Function) std.mem.Allocator.Error!void {
    var walker = try walk.Walker.init(context.memory, context.facts.program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        const id = switch (item) {
            .statement => |value| value,
            else => continue,
        };
        try checkCountingWhile(context, function, id);
    }
}

/// Report one counted loop, but only when the rewrite is exact: one
/// initialization in the whole function, one increment, and no `continue`
/// skipping it.
fn checkCountingWhile(context: *RuleContext, function: typed.Function, id: typed.StatementId) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const loop = switch (facts.program.statements[@backingInt(id)].data) {
        .loop => |value| value,
        else => return,
    };
    // A `for ... in range(...)` and several builtin calls lower to the same
    // checked loop; only a loop a source `while` wrote gets the rewrite.
    if (!isSourceWhile(facts, facts.program.statements[@backingInt(id)].span)) return;
    const comparison = switch (facts.program.nodes[@backingInt(loop.condition)].data) {
        .binary => |value| value,
        else => return,
    };
    if (comparison.op != .lt) return;
    const counter = switch (facts.program.nodes[@backingInt(comparison.left)].data) {
        .local => |slot| slot,
        else => return,
    };
    const step = stepsCounter(facts, loop.body, counter) orelse return;
    if (try hasContinue(context, loop.body)) return;
    const start = (try counterStart(context, function, counter, id, step)) orelse return;
    const message = try std.fmt.allocPrint(context.memory, "{s}: {s} counts with `while`; write `for {s} in range({s}, {s}):`", .{
        rule_counting_while,
        function.name,
        facts.src.text(facts.program.nodes[@backingInt(comparison.left)].span),
        start,
        facts.src.text(facts.program.nodes[@backingInt(comparison.right)].span),
    });
    try context.findings.append(context.memory, .{
        .code = "L_COUNTING_WHILE",
        .rule = rule_counting_while,
        .span = facts.program.statements[@backingInt(id)].span,
        .message = message,
        .subject = .{ .module = moduleName(function.name), .qualified = function.name },
    });
}

/// Whether one checked loop statement is the `while` a source line wrote, rather
/// than a loop the checker lowered a `for ... in range(...)` or a builtin into.
fn isSourceWhile(facts: *const Facts, span: source.Span) bool {
    for (facts.syntax.statements.items) |statement| {
        switch (statement.data) {
            .loop => {},
            else => continue,
        }
        if (statement.span.start == span.start and statement.span.end == span.end) return true;
    }
    return false;
}

/// The loop body's last statement when it is exactly `counter = counter + 1`.
fn stepsCounter(facts: *const Facts, body: typed.StatementId, counter: typed.LocalId) ?typed.StatementId {
    const statements = switch (facts.program.statements[@backingInt(body)].data) {
        .block => |block| block,
        else => return null,
    };
    if (statements.len == 0) return null;
    const step = statements[statements.len - 1];
    const store = switch (facts.program.statements[@backingInt(step)].data) {
        .assign => |value| value,
        else => return null,
    };
    if (store.slot != counter) return null;
    const added = switch (facts.program.nodes[@backingInt(store.value)].data) {
        .binary => |value| value,
        else => return null,
    };
    const counted = switch (facts.program.nodes[@backingInt(added.left)].data) {
        .local => |slot| slot == counter,
        else => false,
    };
    const one = switch (facts.program.nodes[@backingInt(added.right)].data) {
        .integer => |value| value == 1,
        else => false,
    };
    return if (added.op == .add and counted and one) step else null;
}

/// Whether one loop body continues early, which would skip the step when the
/// loop became a `for ... in range(...)`.
fn hasContinue(context: *RuleContext, body: typed.StatementId) std.mem.Allocator.Error!bool {
    var walker = try walk.Walker.init(context.memory, context.facts.program, body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        const id = switch (item) {
            .statement => |value| value,
            else => continue,
        };
        switch (context.facts.program.statements[@backingInt(id)].data) {
            .loop_exit => |exit| if (exit.continuing) return true,
            else => {},
        }
    }
    return false;
}

/// The source spelling of the counter's one initializer, or null when the
/// function writes the counter anywhere else, before or after the loop.
fn counterStart(context: *RuleContext, function: typed.Function, counter: typed.LocalId, loop: typed.StatementId, step: typed.StatementId) std.mem.Allocator.Error!?[]const u8 {
    const facts = context.facts;
    var walker = try walk.Walker.init(context.memory, facts.program, function.scope.body);
    defer walker.deinit();
    var initialize: ?typed.NodeId = null;
    var writes: usize = 0;
    while (try walker.next()) |item| {
        const id = switch (item) {
            .statement => |value| value,
            else => continue,
        };
        const statement = facts.program.statements[@backingInt(id)];
        switch (statement.data) {
            .initialize => |store| {
                if (store.slot != counter) continue;
                writes += 1;
                initialize = store.value;
            },
            .assign => |store| {
                if (store.slot == counter and @backingInt(id) != @backingInt(step)) writes += 1;
            },
            else => {},
        }
    }
    const value = initialize orelse return null;
    // The one write is the initialization itself; the step is the loop's own.
    if (writes != 1) return null;
    // The rewrite moves the initialization into the loop header, so the loop
    // must not read the counter before it is written.
    if (facts.program.nodes[@backingInt(value)].span.start > facts.program.statements[@backingInt(loop)].span.start) return null;
    return facts.src.text(facts.program.nodes[@backingInt(value)].span);
}

/// §3.5 `call-nesting` (proposal 2): one expression nests more calls than the
/// budget, so one of its operands is cheaper to read as a named temporary.
fn runCallNesting(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_call_nesting, default_max_call_nesting);
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        try checkCallNesting(context, function, limit);
    }
}

/// Report the first call of each chain that nests past `limit` calls.
fn checkCallNesting(context: *RuleContext, function: typed.Function, limit: usize) std.mem.Allocator.Error!void {
    var walker = try walk.Walker.init(context.memory, context.facts.program, function.scope.body);
    defer walker.deinit();
    // Calls still open on the walk, innermost last: the walk is pre-order, so a
    // node at depth `d` closes every open call at depth `d` or deeper.
    var open: std.ArrayList(u16) = .empty;
    defer open.deinit(context.memory);
    while (try walker.advance()) |step| {
        while (open.items.len != 0 and open.items[open.items.len - 1] >= step.depth) _ = open.pop();
        const id = switch (step.item) {
            .expression => |value| value,
            else => continue,
        };
        const node = context.facts.program.nodes[@backingInt(id)];
        switch (node.data) {
            .call, .invoke => {},
            else => continue,
        }
        try open.append(context.memory, step.depth);
        // One finding per chain: a fourth call in the same chain is the same
        // temporary's fault, not a second one.
        if (open.items.len != limit + 1) continue;
        try appendCallNestingFinding(context, function, node, open.items.len, limit);
    }
}

/// Append one `call-nesting` finding naming the call to bind to a temporary.
fn appendCallNestingFinding(context: *RuleContext, function: typed.Function, node: typed.Node, nested: usize, limit: usize) std.mem.Allocator.Error!void {
    const message = try std.fmt.allocPrint(context.memory, "{s}: {s} nests {d} calls in one expression (max {d}); " ++
        "bind the `{s}` result to a named `const` first", .{ rule_call_nesting, function.name, nested, limit, nestedCallee(context, node) });
    try context.findings.append(context.memory, .{
        .code = "L_CALL_NESTING",
        .rule = rule_call_nesting,
        .span = node.span,
        .message = message,
        .subject = .{ .module = moduleName(function.name), .qualified = function.name },
    });
}

/// The spelling of the call a finding asks the reader to name: the declared
/// function's local name, or an invoked value's own source text.
fn nestedCallee(context: *RuleContext, node: typed.Node) []const u8 {
    return switch (node.data) {
        .call => |call| blk: {
            const functions = context.facts.program.functions;
            const index = @backingInt(call.function);
            break :blk if (index < functions.len) localName(functions[index].name) else "call";
        },
        .invoke => |call| context.facts.src.text(context.facts.program.nodes[@backingInt(call.callee)].span),
        else => "call",
    };
}

/// §3.5 `public-dict` (proposal 7): a public function's parameter or result spells
/// a bare `dict[...]` instead of a `type` alias or a named record field.
fn runPublicDict(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.syntax.functions) |function| {
        if (isSyntheticOrEntry(facts.src.text(function.name))) continue;
        if (std.mem.startsWith(u8, facts.src.text(function.name), "test_")) continue;
        if (!ast.isPublicDeclaration(facts.syntax, function.name)) continue;
        for (function.signature.parameters) |parameter| try checkPublicDictType(context, function, parameter.ty);
        try checkPublicDictType(context, function, function.signature.return_type);
        if (function.signature.failure_type) |failure| try checkPublicDictType(context, function, failure);
    }
}

/// Report one bare `dict[...]` spelling in a public signature.
fn checkPublicDictType(context: *RuleContext, function: ast.Function, ty: source.Span) std.mem.Allocator.Error!void {
    const texts = context.facts.src.text(ty);
    const written = std.mem.trim(u8, texts, " \t\r\n");
    if (!std.mem.startsWith(u8, written, "dict[")) return;
    const message = try std.fmt.allocPrint(context.memory, "{s}: {s} spells a bare `dict[...]` in its signature; name it with a `type` alias or a record field", .{ rule_public_dict, context.facts.src.text(function.name) });
    try context.findings.append(context.memory, .{
        .code = "L_PUBLIC_DICT",
        .rule = rule_public_dict,
        .span = ty,
        .message = message,
        .subject = .{ .module = moduleName(context.facts.src.text(function.name)), .qualified = context.facts.src.text(function.name) },
    });
}

/// §3.5 `discarded-failure`: a `_ = call()` whose value carries a failure drops
/// the error without a decision. A plain `selka lint` reports it; `--gate` refuses.
/// `dead-write` (W7 step 1, off unless asked for): a write to a local, to a field or element of a
/// local, or a writer call on one, that no later read can see (`dead_writes.zig`). Report only: the
/// count it gives decides what the rule becomes.
fn runDeadWrite(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const hits = try dead_writes.find(context.memory, facts.program, facts.src.bytes);
    for (hits) |hit| {
        const function = facts.program.functions[@backingInt(hit.function)];
        const tail: []const u8 = if (hit.never_read) "; nothing in the function reads it at all" else "";
        const message = try std.fmt.allocPrint(context.memory, "{s}: nothing reads `{s}` after this {s}, so the write changes nothing{s}", .{ rule_dead_write, hit.local, hit.kind.label(), tail });
        try context.findings.append(context.memory, .{
            .code = "L_DEAD_WRITE",
            .rule = rule_dead_write,
            .span = hit.span,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// `text-slice-octets` (F-74): a slice of a `str` whose bound counts octets it did not find. Report only: the slice
/// is correct for a text known to be ASCII, and the message names the three ways that cannot trap.
fn runTextSliceOctets(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const sites = try text_slice_octets.find(context.memory, .{ .program = facts.program, .syntax = facts.syntax, .src = facts.src });
    for (sites) |site| {
        const function = facts.program.functions[@backingInt(site.function)];
        // A `starts_with` or `ends_with` of the same text covers the cut but names another prefix or suffix than the width the cut
        // counts (F-77, FR27): one clause that names the guard as written and that width.
        const near = if (site.nearly) |guard| try std.fmt.allocPrint(
            context.memory,
            "; the guard `{s}` tests another text than `{s}`, the width this cut measures",
            .{ facts.src.text(guard), facts.src.text(site.bound) },
        ) else "";
        const message = try std.fmt.allocPrint(context.memory, "{s}: `{s}` counts octets: its {s} is {s}, not an offset the program found, " ++
            "so the slice traps `R_TEXT_BOUNDARY` on a text whose character spans that cut; cut a width with `strings.cut_octets`, " ++
            "cut by characters with `strings.char_slice`, or ask at an offset with `strings.starts_with_at`{s}", .{
            rule_text_slice_octets,
            facts.src.text(site.span),
            site.side.label(),
            site.reason.label(),
            near,
        });
        try context.findings.append(context.memory, .{
            .code = "L_TEXT_SLICE_OCTETS",
            .rule = rule_text_slice_octets,
            .span = site.span,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

fn runDiscardedFailure(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.program.functions) |function| {
        var walker = try walk.Walker.init(context.memory, facts.program, function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| {
            const statement_id = switch (item) {
                .statement => |id| id,
                else => continue,
            };
            const statement = facts.program.statements[@backingInt(statement_id)];
            const discarded = switch (statement.data) {
                .discard => |value| value,
                else => continue,
            };
            const value = facts.program.nodes[@backingInt(discarded)];
            if (typed.resultShape(value.ty, facts.program.records) == null) continue;
            const message = try std.fmt.allocPrint(context.memory, "{s}: {s} drops the failure of a result", .{ rule_discarded_failure, function.name });
            try context.findings.append(context.memory, .{
                .code = "L_DISCARDED_FAILURE",
                .rule = rule_discarded_failure,
                .span = value.span,
                .message = message,
                .subject = .{ .module = moduleName(function.name), .qualified = function.name },
            });
        }
    }
}

/// Section 9 `decision-points`: report a function over its decision budget.
fn runDecisionPoints(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_decision_points, default_max_decisions);
    for (context.facts.program.functions, 0..) |function, index| {
        if (isSyntheticOrEntry(function.name)) continue;
        const measured = context.facts.functions[index].structure.decisions;
        if (measured <= limit) continue;
        try appendBudgetFinding(context, rule_decision_points, "L_DECISION_POINTS", function, measured, limit);
    }
}

/// Section 9 `dead-export`: report an exported declaration with no caller
/// anywhere in the checked project. Ambiguous for a library, so never blocks.
fn runDeadExport(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const constants = try constantFacts(context);
    for (facts.program.functions, 0..) |function, index| {
        const id: typed.FunctionId = @fromBackingInt(@intCast(index));
        if (!facts.isExport(id)) continue;
        if (facts.isTest(id)) continue;
        if (isSyntheticOrEntry(function.name)) continue;
        if (facts.functions[index].incoming_sites != 0) continue;
        if (constants.declares(function.declaration) and try constants.read(context, function.declaration, true)) continue;
        if (configuredExempt(context, rule_dead_export, function.name)) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: exported {s} has no caller in this project", .{ rule_dead_export, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_DEAD_EXPORT",
            .rule = rule_dead_export,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// `undocumented-export`: every exported function, record, union or domain must
/// carry a docstring long enough to say something. `min_chars` is the configured
/// top-level `lint` floor, or 12.
fn runUndocumentedExport(context: *RuleContext) std.mem.Allocator.Error!void {
    const min_chars = if (context.config) |config| config.min_chars orelse default_min_chars else default_min_chars;
    const start = context.findings.items.len;
    try appendUndocumentedExports(context.memory, context.index, min_chars, context.findings);
    mapDocumentationFindings(context, start);
}

/// Append one `L_UNDOCUMENTED_EXPORT` finding per exported declaration in `index`
/// whose docstring is missing, shorter than `min_chars` non-whitespace
/// characters, or merely restates the declaration's own name.
pub fn appendUndocumentedExports(
    memory: std.mem.Allocator,
    index: *interfaces.Index,
    min_chars: usize,
    findings: *std.ArrayList(Finding),
) std.mem.Allocator.Error!void {
    for (index.project.order.items) |module| {
        const unit = index.units[module];
        const module_name = index.project.modules.items[module].name;
        const src = index.project.modules.items[module].src;
        if (documentationExempt(src.path)) continue;
        for (unit.symbols.items) |symbol| {
            // A facade re-export declares nothing; its defining module is checked.
            if (!symbol.exported or symbol.re_export != null) continue;
            if (!documentable(unit, symbol)) continue;
            if (symbol.kind == .function and documentationFunctionExempt(symbol.name)) continue;
            if (ast.hasAttribute(unit.syntax, symbol.span, .@"test")) continue;
            const name = src.text(symbol.span);
            const message = (try undocumentedMessage(memory, name, ast.docstringOf(unit.syntax, symbol.span), min_chars)) orelse continue;
            try findings.append(memory, .{
                .code = "L_UNDOCUMENTED_EXPORT",
                .rule = rule_undocumented_export,
                .span = symbol.span,
                .message = message,
                .subject = .{ .module = module_name, .qualified = try std.fmt.allocPrint(memory, "{s}::{s}", .{ module_name, symbol.name }) },
            });
        }
    }
}

fn documentationFunctionExempt(name: []const u8) bool {
    return std.mem.eql(u8, name, "main") or std.mem.startsWith(u8, name, "test_");
}

fn documentationExempt(path: []const u8) bool {
    return std.mem.startsWith(u8, path, "@stdlib/") or product.isTestSource(path);
}

fn runUndocumentedModule(context: *RuleContext) std.mem.Allocator.Error!void {
    const start = context.findings.items.len;
    for (context.index.project.order.items) |module| try appendModuleDoc(context.memory, context.index, module, context.findings);
    mapDocumentationFindings(context, start);
}

fn runMissingExample(context: *RuleContext) std.mem.Allocator.Error!void {
    const start = context.findings.items.len;
    for (context.index.project.order.items) |module| try appendExamples(context.memory, context.index, module, context.findings);
    mapDocumentationFindings(context, start);
}

/// Longest expected-output line an example may print, and the longest `>>>`
/// block, before `long-example` suggests showing a property instead of a dump.
const max_example_output: usize = 120;
const max_example_block: usize = 6;

fn runLongExample(context: *RuleContext) std.mem.Allocator.Error!void {
    const start = context.findings.items.len;
    for (context.index.project.order.items) |module| try appendLongExamples(context.memory, context.index, module, context.findings);
    mapDocumentationFindings(context, start);
}

fn appendLongExamples(memory: std.mem.Allocator, index: *interfaces.Index, module: usize, findings: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    const loaded = index.project.modules.items[module];
    if (documentationExempt(loaded.src.path)) return;
    const unit = index.units[module];
    if (ast.docstringOf(unit.syntax, ast.module_docstring_span)) |doc| {
        try appendLongExampleDoc(memory, loaded, "", doc, moduleDocumentationSpan(loaded.src), findings);
    }
    for (unit.syntax.functions) |function| {
        const doc = ast.docstringOf(unit.syntax, function.name) orelse continue;
        try appendLongExampleDoc(memory, loaded, loaded.src.text(function.name), doc, function.name, findings);
    }
}

fn appendLongExampleDoc(memory: std.mem.Allocator, loaded: @import("project.zig").Module, name: []const u8, doc: ast.DeclarationDoc, declaration: source.Span, findings: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    const grammar = @import("docstring_examples.zig");
    const first_line = loaded.src.physicalLocation(doc.span.start).line;
    const parsed = try grammar.parse(memory, doc.text, first_line);
    defer grammar.release(memory, parsed);
    for (parsed) |example| {
        const qualified = if (name.len == 0) loaded.name else try std.fmt.allocPrint(memory, "{s}::{s}", .{ loaded.name, name });
        if (example.lines.len > max_example_block) {
            try findings.append(memory, .{
                .code = "L_LONG_EXAMPLE",
                .rule = rule_long_example,
                .span = declaration,
                .message = try std.fmt.allocPrint(memory, "{s}: example at line {d} runs {d} `>>>` lines (max {d}); show the call, not a dump", .{ qualified, example.line, example.lines.len, max_example_block }),
                .subject = .{ .module = loaded.name, .qualified = qualified },
            });
            continue;
        }
        var lines = std.mem.splitScalar(u8, std.mem.trimEnd(u8, example.expected, "\n"), '\n');
        while (lines.next()) |line| {
            if (line.len <= max_example_output) continue;
            try findings.append(memory, .{
                .code = "L_LONG_EXAMPLE",
                .rule = rule_long_example,
                .span = declaration,
                .message = try std.fmt.allocPrint(memory, "{s}: example at line {d} prints {d} characters on one expected line (max {d}); " ++
                    "assert a property such as `len(...)` or a prefix instead", .{ qualified, example.line, line.len, max_example_output }),
                .subject = .{ .module = loaded.name, .qualified = qualified },
            });
            break;
        }
    }
}

fn mapDocumentationFindings(context: *RuleContext, start: usize) void {
    for (context.findings.items[start..]) |*finding| {
        const module = context.index.project.names.get(finding.subject.module) orelse continue;
        finding.span = context.facts.src.mappedSpan(module, finding.span) catch finding.span;
    }
}

fn moduleDocumentationSpan(src: source.Source) source.Span {
    var offset: usize = 0;
    var lines = std.mem.splitScalar(u8, src.bytes, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        const start = offset;
        offset += raw.len + 1;
        if (line.len == 0 or line[0] == '#' or std.mem.startsWith(u8, line, "import ")) continue;
        return .{ .start = start, .end = start + raw.len };
    }
    return .{ .start = src.bytes.len, .end = src.bytes.len };
}

fn appendModuleDoc(memory: std.mem.Allocator, index: *interfaces.Index, module: usize, findings: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    const loaded = index.project.modules.items[module];
    if (documentationExempt(loaded.src.path)) return;
    const syntax = index.units[module].syntax;
    if (ast.docstringOf(syntax, ast.module_docstring_span)) |doc| {
        if (std.mem.trim(u8, doc.text, " \t\r\n").len != 0) return;
    }
    try findings.append(memory, .{
        .code = "L_UNDOCUMENTED_MODULE",
        .rule = rule_undocumented_module,
        .span = moduleDocumentationSpan(loaded.src),
        .message = try std.fmt.allocPrint(memory, "module {s} has no module docstring", .{loaded.name}),
        .subject = .{ .module = loaded.name },
    });
}

fn appendExamples(memory: std.mem.Allocator, index: *interfaces.Index, module: usize, findings: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    const loaded = index.project.modules.items[module];
    if (documentationExempt(loaded.src.path)) return;
    const unit = index.units[module];
    for (unit.symbols.items) |symbol| {
        if (!symbol.exported or symbol.re_export != null or symbol.kind != .function) continue;
        if (!documentable(unit, symbol) or documentationFunctionExempt(symbol.name)) continue;
        if (ast.hasAttribute(unit.syntax, symbol.span, .@"test")) continue;
        if (ast.docstringOf(unit.syntax, symbol.span)) |doc| {
            if (@import("docstring_examples.zig").count(doc.text) != 0) continue;
        }
        const qualified = try std.fmt.allocPrint(memory, "{s}::{s}", .{ loaded.name, symbol.name });
        try findings.append(memory, .{
            .code = "L_MISSING_EXAMPLE",
            .rule = rule_missing_example,
            .span = symbol.span,
            .message = try std.fmt.allocPrint(memory, "public function {s} has no `>>>` example; add one, or waive it with a reason", .{qualified}),
            .subject = .{ .module = loaded.name, .qualified = qualified },
        });
    }
}

/// Append blocking documentation findings for the shared release model's selected
/// modules, honoring lint's reasoned waivers. Other modules are never inspected.
pub fn appendProjectDocumentation(memory: std.mem.Allocator, index: *interfaces.Index, modules: []const usize, min_chars: usize, findings: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    var exports: std.ArrayList(Finding) = .empty;
    try appendUndocumentedExports(memory, index, min_chars, &exports);
    for (modules) |module| {
        const loaded = index.project.modules.items[module];
        const start = findings.items.len;
        try appendModuleDoc(memory, index, module, findings);
        try appendExamples(memory, index, module, findings);
        for (exports.items) |finding| if (std.mem.eql(u8, finding.subject.module, loaded.name)) try findings.append(memory, finding);
        var kept = start;
        for (findings.items[start..]) |finding| {
            if (try waiverReason(memory, loaded.src, index.units[module].syntax, finding.span, finding.rule) != null) continue;
            findings.items[kept] = finding;
            findings.items[kept].state.severity = .err;
            kept += 1;
        }
        findings.shrinkRetainingCapacity(kept);
    }
}

/// Whether an exported symbol is a declaration this rule documents: a function,
/// or a record, union/result or domain type.
fn documentable(unit: interfaces.Unit, symbol: interfaces.Symbol) bool {
    if (symbol.kind == .function) {
        for (unit.syntax.functions) |function| if (sameSpan(function.name, symbol.span)) return !function.policy.constant;
        return false;
    }
    if (symbol.kind != .type) return false;
    for (unit.syntax.types.records) |record| if (sameSpan(record.name, symbol.span)) return true;
    for (unit.syntax.types.variants) |variant| if (sameSpan(variant.name, symbol.span)) return true;
    for (unit.syntax.types.domains) |domain| if (sameSpan(domain.name, symbol.span)) return true;
    return false;
}

fn sameSpan(a: source.Span, b: source.Span) bool {
    return a.start == b.start and a.end == b.end;
}

/// The finding message for one exported declaration, or null when its docstring
/// satisfies the rule. `min_chars` counts non-whitespace characters.
fn undocumentedMessage(memory: std.mem.Allocator, name: []const u8, doc: ?ast.DeclarationDoc, min_chars: usize) std.mem.Allocator.Error!?[]const u8 {
    const entry = doc orelse {
        const missing = try std.fmt.allocPrint(memory, "{s}: exported {s} has no docstring", .{ rule_undocumented_export, name });
        return missing;
    };
    const measured = nonWhitespaceCount(entry.text);
    if (measured < min_chars) {
        const short = try std.fmt.allocPrint(memory, "{s}: exported {s} docstring has {d} non-whitespace characters (min {d})", .{ rule_undocumented_export, name, measured, min_chars });
        return short;
    }
    if (restatesName(entry.text, name)) {
        const restated = try std.fmt.allocPrint(memory, "{s}: exported {s} docstring merely restates the declaration name", .{ rule_undocumented_export, name });
        return restated;
    }
    return null;
}

fn nonWhitespaceCount(text: []const u8) usize {
    var count: usize = 0;
    for (text) |byte| count += @intFromBool(!std.ascii.isWhitespace(byte));
    return count;
}

/// Whether a docstring is just the declaration name spelled again: the name's
/// words (case-insensitive, `_` splitting) followed by fewer than two more
/// words. That covers an exact repeat and spellings like `<name> doc`.
fn restatesName(text: []const u8, name: []const u8) bool {
    var text_cursor: usize = 0;
    var name_cursor: usize = 0;
    var matched: usize = 0;
    while (nextWord(name, &name_cursor)) |name_word| {
        const text_word = nextWord(text, &text_cursor) orelse return false;
        if (!std.ascii.eqlIgnoreCase(text_word, name_word)) return false;
        matched += 1;
    }
    if (matched == 0) return false;
    var extra: usize = 0;
    while (nextWord(text, &text_cursor) != null) extra += 1;
    return extra < 2;
}

/// The next word of `text` at or after `cursor`, advancing it past the word.
/// Whitespace, `_` and sentence punctuation separate words.
fn nextWord(text: []const u8, cursor: *usize) ?[]const u8 {
    while (cursor.* < text.len) : (cursor.* += 1) {
        if (!wordSeparator(text[cursor.*])) break;
    }
    const start = cursor.*;
    while (cursor.* < text.len) : (cursor.* += 1) {
        if (wordSeparator(text[cursor.*])) break;
    }
    return if (cursor.* == start) null else text[start..cursor.*];
}

fn wordSeparator(byte: u8) bool {
    return std.ascii.isWhitespace(byte) or byte == '_' or byte == '.' or byte == ',' or byte == ':' or byte == ';';
}

/// `change-without-test`'s rule entry. It stays silent unless the caller
/// supplied a diff scope, which only `--gate --against REF` does.
fn runChangeWithoutTest(context: *RuleContext) std.mem.Allocator.Error!void {
    const scope = context.change orelse return;
    try appendChangeWithoutTestFindings(.{
        .memory = context.memory,
        .facts = context.facts,
        .index = context.index,
        .config = context.config,
        .scope = scope,
    }, context.findings);
}

/// `change-without-test`: under `--gate --against REF`, every non-test function
/// whose declaration changed in the working tree must be the direct callee of a
/// test whose own body changed in the same diff, be exempt under
/// `test-coverage.exempt`, or carry a waiver (which the caller applies). A
/// finding's related note lists the tests that call the function directly, so a
/// reader knows exactly which test to extend.
pub fn appendChangeWithoutTestFindings(query: ChangeQuery, findings: *std.ArrayList(Finding)) std.mem.Allocator.Error!void {
    const facts = query.facts;
    const modules = query.index.project.modules.items;
    // One diff per module, loaded on first use. A module git cannot diff is an
    // empty range set: the rule stays quiet rather than flagging everything.
    const diff_cache = try query.memory.alloc(declaration_diff.ModuleDiff, modules.len);
    @memset(diff_cache, .{});
    const diff: declaration_diff.Diff = .{
        .memory = query.memory,
        .io = query.scope.io,
        .repo_root = query.scope.repo_root,
        .reference = query.scope.reference,
        .index = query.index,
        .src = facts.src,
        .cache = diff_cache,
    };
    const changed = try query.memory.alloc(bool, facts.program.functions.len);
    @memset(changed, false);
    for (facts.program.functions, 0..) |function, index| {
        // A body edit lives outside the signature span, so intersect the union
        // of the declaration and its body: a signature-only or body-only change
        // both count.
        const body = facts.program.statements[@backingInt(function.scope.body)].span;
        changed[index] = try diff.changed(.{
            .start = @min(function.declaration.start, body.start),
            .end = @max(function.declaration.end, body.end),
        });
    }
    for (facts.program.functions, 0..) |function, index| {
        if (!changed[index]) continue;
        const id: typed.FunctionId = @fromBackingInt(@intCast(index));
        if (facts.isTest(id)) continue;
        if (isSyntheticOrEntry(function.name)) continue;
        if (configuredExemptFrom(query.config, rule_test_coverage, function.name)) continue;
        if (hasChangedTestCaller(facts, changed, id)) continue;
        const message = try std.fmt.allocPrint(query.memory, "{s}: {s} changed without a test that changed too", .{ rule_change_without_test, function.name });
        try findings.append(query.memory, .{
            .code = "L_CHANGE_WITHOUT_TEST",
            .rule = rule_change_without_test,
            .span = function.declaration,
            .message = message,
            .related = try callerNote(query.memory, function, facts, id),
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// Whether a test whose own body changed calls `target` directly. That is the
/// one thing that lets a changed declaration through.
fn hasChangedTestCaller(facts: *const Facts, changed: []const bool, target: typed.FunctionId) bool {
    for (facts.roots.tests) |test_id| {
        const index = @backingInt(test_id);
        if (index >= changed.len or !changed[index]) continue;
        if (callsDirectly(facts.functions[index], target)) return true;
    }
    return false;
}

/// Whether one function's static call evidence includes `target`.
fn callsDirectly(function: quality.Function, target: typed.FunctionId) bool {
    for (function.calls) |call| {
        if (call.callee == target) return true;
    }
    return false;
}

/// The related note for one changed function: the tests that call it directly,
/// so the reader knows which test to extend, or an explicit statement that none
/// do. The note points at the first caller when there is one.
fn callerNote(memory: std.mem.Allocator, function: typed.Function, facts: *const Facts, target: typed.FunctionId) std.mem.Allocator.Error!diagnostic.Related {
    var callers: std.ArrayList(typed.Function) = .empty;
    for (facts.roots.tests) |test_id| {
        const index = @backingInt(test_id);
        if (!callsDirectly(facts.functions[index], target)) continue;
        try callers.append(memory, facts.program.functions[index]);
    }
    if (callers.items.len == 0) {
        return .{ .span = function.declaration, .message = try std.fmt.allocPrint(memory, "no test calls {s} directly", .{function.name}) };
    }
    var list: std.ArrayList(u8) = .empty;
    for (callers.items, 0..) |caller, index| {
        if (index != 0) try list.appendSlice(memory, ", ");
        try list.appendSlice(memory, caller.name);
    }
    return .{ .span = callers.items[0].declaration, .message = try std.fmt.allocPrint(memory, "tests that call {s} directly: {s}", .{ function.name, list.items }) };
}

/// Build the run's one test-reachability index: the same discovery, per-function
/// call graph and inversion `selka tests-for` performs, so this run and that
/// command answer from one walk rather than two that could drift apart. The
/// index owns its own arena; the caller frees it with `deinit`.
fn buildReachabilityIndex(scratch: std.mem.Allocator, compilation: *project_compile.Compilation, adapter: component_adapter.Adapter) component_adapter.Error!tests_index.Index {
    const program = compilation.program.?;
    const modules = try compilation.index.moduleSyntax(scratch);
    const call_graph = try tests_index.callGraph(scratch, program);
    const discovered = try tests_index.discoveredTests(scratch, program, modules);
    return adapter.build(scratch, program, call_graph, discovered);
}

/// Attach the discovered tests that reach a finding's declaration as a related
/// note. The walk is the shared `tests_index.zig` one built once for this run,
/// so the note agrees with `tests-for`, the `list-interfaces` tests column and
/// the `untested-export` verdict. A rule that already set its own related note
/// keeps it, and a declaration no test reaches gets none.
fn attachReachabilityNotes(scratch: std.mem.Allocator, facts: *const Facts, reach: *const tests_index.Index, findings: []Finding) std.mem.Allocator.Error!void {
    for (findings) |*finding| {
        if (finding.related != null) continue;
        const target = findFunctionByName(facts.program, finding.subject.qualified) orelse continue;
        const answer = reach.answer(target);
        if (answer.reached.len == 0) continue;
        const first = findFunctionByName(facts.program, answer.reached[0]) orelse continue;
        finding.related = .{
            .span = facts.program.functions[@backingInt(first)].declaration,
            .message = try reachedTestsMessage(scratch, answer),
        };
    }
}

/// The checked function with one exact qualified name, or null.
fn findFunctionByName(program: typed.Program, name: []const u8) ?typed.FunctionId {
    if (name.len == 0) return null;
    for (program.functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return @fromBackingInt(@intCast(index));
    }
    return null;
}

/// One related-note sentence naming every test that reaches a declaration.
fn reachedTestsMessage(scratch: std.mem.Allocator, answer: tests_index.Answer) std.mem.Allocator.Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    for (answer.reached, 0..) |name, index| {
        if (index != 0) try list.appendSlice(scratch, ", ");
        try list.appendSlice(scratch, name);
    }
    return std.fmt.allocPrint(scratch, "reached by tests: {s}", .{list.items});
}

/// W2 `integration-tests`: a test whose signature requests `Filesystem`,
/// `Network`, `Clock` or `Entropy` is an integration test and must live in a
/// module matching the rule's `modules` globs (default `*_integration`,
/// `integration.*`). A declared `exempt` entry or a matching module exempts it.
fn runIntegrationTests(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.roots.tests) |id| {
        const function = facts.program.functions[@backingInt(id)];
        if (!requestsCapability(function)) continue;
        if (configuredExempt(context, rule_integration_tests, function.name)) continue;
        if (moduleAllowed(context, rule_integration_tests, moduleName(function.name), default_integration_modules)) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: test {s} requests a capability and is not in an integration module", .{ rule_integration_tests, function.name });
        try context.findings.append(context.memory, .{
            .code = "L_TEST_CAPABILITY",
            .rule = rule_integration_tests,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// Whether a function's declared parameters request `Filesystem`, `Network`,
/// `Clock` or `Entropy`. `Environment` and the output stream are not
/// integration capabilities for this rule.
fn requestsCapability(function: typed.Function) bool {
    const count = @min(function.signature.parameter_count, function.scope.locals.len);
    for (function.scope.locals[0..count]) |local| switch (local.ty) {
        .filesystem_cap, .network_cap, .clock_cap, .random_cap => return true,
        else => {},
    };
    return false;
}

/// Whether one module name matches any glob in a rule's configured `modules`
/// allow-list, falling back to that rule's default list when none is set.
fn moduleAllowed(context: *RuleContext, rule: []const u8, module: []const u8, defaults: []const []const u8) bool {
    var configured = defaults;
    if (context.config) |config| {
        if (config.setting(rule)) |setting| {
            if (setting.modules.len != 0) configured = setting.modules;
        }
    }
    for (configured) |pattern| if (moduleGlobMatches(pattern, module)) return true;
    return false;
}

/// Anchored `*`/`?` glob over one module name. `*` spans module segments, so a
/// wildcard suffix matches a dotted module name and a `integration.*` prefix
/// matches every dotted module below `integration`.
fn moduleGlobMatches(pattern: []const u8, name: []const u8) bool {
    var p: usize = 0;
    var n: usize = 0;
    var star: ?usize = null;
    var star_name: usize = 0;
    while (n < name.len) {
        if (p < pattern.len and (pattern[p] == '?' or pattern[p] == name[n])) {
            p += 1;
            n += 1;
            continue;
        }
        if (p < pattern.len and pattern[p] == '*') {
            star = p;
            p += 1;
            star_name = n;
            continue;
        }
        if (star) |at| {
            p = at + 1;
            star_name += 1;
            n = star_name;
            continue;
        }
        return false;
    }
    while (p < pattern.len and pattern[p] == '*') p += 1;
    return p == pattern.len;
}

/// Section 9 `record-size`: report a user record or class over its field
/// budget. Builtin aggregates are not declarations and are never counted.
fn runRecordSize(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_record_size, default_max_record_fields);
    const project = context.index.project;
    for (project.order.items) |module| {
        const unit = context.index.units[module];
        const definition = project.modules.items[module];
        for (unit.syntax.types.records) |record| {
            if (record.fields.len <= limit) continue;
            const span = context.facts.src.mappedSpan(module, record.name) catch continue;
            const name = definition.src.text(record.name);
            const kind = if (record.managed) "class" else "record";
            const message = try std.fmt.allocPrint(context.memory, "{s}: {s} {s} has {d} fields (max {d})", .{ rule_record_size, kind, name, record.fields.len, limit });
            try context.findings.append(context.memory, .{
                .code = "L_RECORD_SIZE",
                .rule = rule_record_size,
                .span = span,
                .message = message,
                .subject = .{ .module = definition.name, .qualified = try std.mem.concat(context.memory, u8, &.{ definition.name, separator, name }) },
            });
        }
    }
}

/// Section 9 `file-length`: report a module over its code-line budget. Blank
/// and whole-line comment lines do not count; the budget is a design signal,
/// unlike the parser's byte limit.
fn runFileLength(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_file_length, default_max_file_lines);
    const project = context.index.project;
    for (project.order.items) |module| {
        const definition = project.modules.items[module];
        const measured = codeLineCount(definition.src.bytes);
        if (measured <= limit) continue;
        const span = context.facts.src.mappedSpan(module, .{ .start = 0, .end = 0 }) catch continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: module {s} has {d} code lines (max {d})", .{ rule_file_length, definition.name, measured, limit });
        try context.findings.append(context.memory, .{
            .code = "L_FILE_LENGTH",
            .rule = rule_file_length,
            .span = span,
            .message = message,
            .subject = .{ .module = definition.name, .qualified = definition.name },
        });
    }
}

/// Count non-blank lines that are not whole-line `#` comments.
fn codeLineCount(bytes: []const u8) usize {
    var count: usize = 0;
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        count += 1;
    }
    return count;
}

/// Section 9 `bool-ops-per-condition`: report the function whose single
/// condition combines the most `and`/`or` operators.
fn runBoolOpsPerCondition(context: *RuleContext) std.mem.Allocator.Error!void {
    const limit = configuredMax(context, rule_bool_ops, default_max_bool_ops);
    const program = context.facts.program;
    for (program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        const measured = try worstConditionLogicalCount(context.memory, program, function, context.facts.src);
        if (measured <= limit) continue;
        try appendBudgetFinding(context, rule_bool_ops, "L_BOOL_OPS", function, measured, limit);
    }
}

/// The largest `and`/`or` count of any one branch or loop condition in a body.
fn worstConditionLogicalCount(scratch: std.mem.Allocator, program: typed.Program, function: typed.Function, src: source.Source) std.mem.Allocator.Error!usize {
    var worst: usize = 0;
    var walker = try walk.Walker.init(scratch, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .statement => |id| {
            const condition = switch (program.statements[@backingInt(id)].data) {
                .branch => |branch| branch.condition,
                .loop => |loop| loop.condition,
                .range_loop => |range| range.plan().loop.condition,
                else => continue,
            };
            worst = @max(worst, logicalOperatorCount(src.text(program.nodes[@backingInt(condition)].span)));
        },
        else => {},
    };
    return worst;
}

/// Count `and`/`or` keywords in one condition's source text, skipping string
/// literals and inner word characters so `candy` and `"or"` never count.
fn logicalOperatorCount(text: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    var quote: u8 = 0;
    while (i < text.len) {
        const byte = text[i];
        if (quote != 0) {
            if (byte == '\\') {
                i += 2;
                continue;
            }
            if (byte == quote) quote = 0;
            i += 1;
            continue;
        }
        if (byte == '"' or byte == '\'') {
            quote = byte;
            i += 1;
            continue;
        }
        if (keywordAt(text, i, "and") or keywordAt(text, i, "or")) {
            count += 1;
            i += 2;
            continue;
        }
        i += 1;
    }
    return count;
}

/// Whether `word` starts at `at` as a whole identifier.
fn keywordAt(text: []const u8, at: usize, word: []const u8) bool {
    if (at + word.len > text.len) return false;
    if (!std.mem.eql(u8, text[at .. at + word.len], word)) return false;
    if (at > 0 and identifierByte(text[at - 1])) return false;
    if (at + word.len < text.len and identifierByte(text[at + word.len])) return false;
    return true;
}

fn identifierByte(byte: u8) bool {
    return std.ascii.isAlphanumeric(byte) or byte == '_';
}

/// Section 9 `naming`: PEP 8 casing for functions, parameters and types, plus a
/// small vague-name list. Report-only, and synthetic entry points are exempt.
fn runNaming(context: *RuleContext) std.mem.Allocator.Error!void {
    const program = context.facts.program;
    const constants = try constantFacts(context);
    for (program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        // A specialization's checked name carries its type arguments
        // (`contains[i64]`); the source name is the one a convention judges.
        const local = unspecializedName(localName(function.name));
        // A domain method's checked name is `Domain.method`; only the method
        // part is subject to the function casing rule.
        const checked = if (std.mem.lastIndexOfScalar(u8, local, '.')) |at| local[at + 1 ..] else local;
        // A module constant is a value, not a function: the guides spell it in upper case.
        if (constants.declares(function.declaration)) {
            if (!(snakeCase(checked) or upperSnakeCase(checked)) or vagueName(checked)) try appendNamingFinding(context, "constant", checked, function.declaration, function.name);
            continue;
        }
        if (!snakeCase(checked) or vagueName(checked)) try appendNamingFinding(context, "function", checked, function.declaration, function.name);
        const count = @min(function.signature.parameter_count, function.scope.locals.len);
        for (function.scope.locals[0..count]) |parameter| {
            if (snakeCase(parameter.name) and !vagueName(parameter.name)) continue;
            try appendNamingFinding(context, "parameter", parameter.name, parameter.declaration, function.name);
        }
        for (function.scope.locals[count..]) |binding| {
            // A name the compiler made up for a hidden owner (`consumed list`) is no variable of the program's.
            if (!binding.written()) continue;
            if (snakeCase(binding.name) and !vagueName(binding.name)) continue;
            try appendNamingFinding(context, "local", binding.name, binding.declaration, function.name);
        }
    }
    const project = context.index.project;
    for (project.order.items) |module| {
        const unit = context.index.units[module];
        const definition = project.modules.items[module];
        for (unit.syntax.types.records) |record| try checkTypeName(context, module, definition, record.name, "record");
        for (unit.syntax.types.variants) |variant| try checkTypeName(context, module, definition, variant.name, "union");
        for (unit.syntax.types.domains) |domain| try checkTypeName(context, module, definition, domain.name, "domain");
    }
}

/// Names a project should not spell, per Guardian's vague-name list.
const vague_names = [_][]const u8{ "tmp", "data", "info", "obj", "mgr", "Helper", "Util", "Manager" };

fn appendNamingFinding(context: *RuleContext, kind: []const u8, name: []const u8, span: source.Span, qualified: []const u8) std.mem.Allocator.Error!void {
    const message = try std.fmt.allocPrint(context.memory, "{s}: {s} {s} does not follow the naming convention", .{ rule_naming, kind, name });
    try context.findings.append(context.memory, .{
        .code = "L_NAMING",
        .rule = rule_naming,
        .span = span,
        .message = message,
        .subject = .{ .module = moduleName(qualified), .qualified = qualified },
    });
}

fn checkTypeName(context: *RuleContext, module: usize, definition: graph.Module, name_span: source.Span, kind: []const u8) std.mem.Allocator.Error!void {
    const name = definition.src.text(name_span);
    if (pascalCase(name) and !vagueName(name)) return;
    const span = context.facts.src.mappedSpan(module, name_span) catch return;
    try appendNamingFinding(context, kind, name, span, try std.mem.concat(context.memory, u8, &.{ definition.name, separator, name }));
}

fn snakeCase(name: []const u8) bool {
    if (name.len == 0) return false;
    for (name) |byte| {
        if (std.ascii.isLower(byte) or std.ascii.isDigit(byte) or byte == '_') continue;
        return false;
    }
    return true;
}

/// `UPPER_SNAKE_CASE`, the spelling the guides use for module constants.
fn upperSnakeCase(name: []const u8) bool {
    if (name.len == 0 or std.ascii.isDigit(name[0])) return false;
    for (name) |byte| {
        if (std.ascii.isUpper(byte) or std.ascii.isDigit(byte) or byte == '_') continue;
        return false;
    }
    return true;
}

fn pascalCase(name: []const u8) bool {
    return name.len != 0 and std.ascii.isUpper(name[0]);
}

fn vagueName(name: []const u8) bool {
    for (vague_names) |vague| if (std.mem.eql(u8, name, vague)) return true;
    return false;
}

/// One integer literal occurrence, before grouping into a repeated run.
const LiteralOccurrence = struct { module: usize, value: i128, span: source.Span };

/// Section 9 `repeated-literal`: report an integer literal that appears at
/// least three times in one module. `0` and `1` are structural and never count.
fn runRepeatedLiteral(context: *RuleContext) std.mem.Allocator.Error!void {
    const program = context.facts.program;
    const src = context.facts.src;
    var occurrences: std.ArrayList(LiteralOccurrence) = .empty;
    for (program.nodes) |node| {
        const value = switch (node.data) {
            .integer => |literal| literal,
            else => continue,
        };
        if (value == 0 or value == 1) continue;
        // A folded constant read is checked as the literal its constant holds, but what the source
        // wrote there is the constant's name: naming a value is what this rule asks for.
        const written = src.text(node.span);
        if (written.len == 0 or !(std.ascii.isDigit(written[0]) or written[0] == '-')) continue;
        const original = src.originalSpan(node.span) catch continue;
        try occurrences.append(context.memory, .{ .module = original.input, .value = value, .span = node.span });
    }
    std.mem.sort(LiteralOccurrence, occurrences.items, {}, literalLessThan);
    var start: usize = 0;
    while (start < occurrences.items.len) {
        var end = start + 1;
        while (end < occurrences.items.len and sameLiteral(occurrences.items[start], occurrences.items[end])) end += 1;
        if (end - start >= default_literal_repeats) try appendRepeatedLiteral(context, occurrences.items[start..end]);
        start = end;
    }
}

fn literalLessThan(_: void, a: LiteralOccurrence, b: LiteralOccurrence) bool {
    if (a.module != b.module) return a.module < b.module;
    if (a.value != b.value) return a.value < b.value;
    return a.span.start < b.span.start;
}

fn sameLiteral(a: LiteralOccurrence, b: LiteralOccurrence) bool {
    return a.module == b.module and a.value == b.value;
}

fn appendRepeatedLiteral(context: *RuleContext, occurrences: []const LiteralOccurrence) std.mem.Allocator.Error!void {
    const module = context.index.project.modules.items[occurrences[0].module].name;
    const message = try std.fmt.allocPrint(context.memory, "{s}: literal {d} appears {d} times in module {s}", .{ rule_repeated_literal, occurrences[0].value, occurrences.len, module });
    try context.findings.append(context.memory, .{
        .code = "L_REPEATED_LITERAL",
        .rule = rule_repeated_literal,
        .span = occurrences[default_literal_repeats - 1].span,
        .message = message,
        .subject = .{ .module = module, .qualified = module },
    });
}

/// Section 9 `same-type-adjacent-params`: report adjacent parameters that share
/// one type, where a keyword argument is the fix. Capability and `unit`
/// parameters are structural and never count.
fn runSameTypeAdjacentParams(context: *RuleContext) std.mem.Allocator.Error!void {
    const program = context.facts.program;
    for (program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        const count = @min(function.signature.parameter_count, function.scope.locals.len);
        if (count < 2) continue;
        var shared: ?typed.Type = null;
        for (function.scope.locals[0 .. count - 1], function.scope.locals[1..count]) |left, right| {
            if (left.ty != right.ty) continue;
            if (left.ty == .unit or left.ty.capabilityIndex() != null) continue;
            shared = left.ty;
            break;
        }
        const ty = shared orelse continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: {s} takes adjacent parameters of type {s}", .{ rule_same_type_adjacent_params, function.name, try typed.surfaceTypeName(context.memory, ty, program.records) });
        try context.findings.append(context.memory, .{
            .code = "L_SAME_TYPE_ADJACENT_PARAMS",
            .rule = rule_same_type_adjacent_params,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// Section 9 `duplicate-body`: report each exact group of functions whose
/// normalized bodies match. Advisory and never blocking; independent
/// implementations are allowed to stay separate.
fn runDuplicateBody(context: *RuleContext) std.mem.Allocator.Error!void {
    var analysis = duplicates.discover(context.memory, context.facts.program, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidThreshold, error.InternalError => return,
    };
    defer analysis.deinit();
    for (analysis.groups) |group| {
        if (group.members.len < 2) continue;
        const representative = context.facts.program.functions[@backingInt(group.members[0])];
        const duplicate = context.facts.program.functions[@backingInt(group.members[1])];
        const message = try std.fmt.allocPrint(context.memory, "{s}: {d} functions share a {d}-node body, starting with {s}", .{ rule_duplicate_body, group.members.len, group.nodes, representative.name });
        try context.findings.append(context.memory, .{
            .code = "L_DUPLICATE_BODY",
            .rule = rule_duplicate_body,
            .span = representative.declaration,
            .message = message,
            .related = .{ .span = duplicate.declaration, .message = try duplicateMembersMessage(context.memory, context.facts.program, group.members) },
            .subject = .{ .module = moduleName(representative.name), .qualified = representative.name },
        });
    }
}

fn duplicateMembersMessage(memory: std.mem.Allocator, program: typed.Program, members: []const typed.FunctionId) std.mem.Allocator.Error![]const u8 {
    var list: std.ArrayList(u8) = .empty;
    for (members, 0..) |id, index| {
        if (index != 0) try list.appendSlice(memory, ", ");
        try list.appendSlice(memory, program.functions[@backingInt(id)].name);
    }
    return std.fmt.allocPrint(memory, "duplicate members: {s}", .{list.items});
}

/// Section 9 `output-in-library`: report a function whose checked body contains
/// a print operation in a module outside the rule's `modules` allow-list.
fn runOutputInLibrary(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        var walker = try walk.Walker.init(context.memory, context.facts.program, function.scope.body);
        defer walker.deinit();
        var prints = false;
        while (try walker.next()) |item| {
            if (item == .expression and context.facts.program.nodes[@backingInt(item.expression)].data == .print) {
                prints = true;
                break;
            }
        }
        if (!prints) continue;
        if (isSyntheticOrEntry(function.name)) continue;
        const module = moduleName(function.name);
        if (moduleAllowed(context, rule_output_in_library, module, default_output_modules)) continue;
        if (configuredExempt(context, rule_output_in_library, function.name)) continue;
        const message = try std.fmt.allocPrint(context.memory, "{s}: {s} prints in library module {s}", .{ rule_output_in_library, function.name, module });
        try context.findings.append(context.memory, .{
            .code = "L_OUTPUT_IN_LIBRARY",
            .rule = rule_output_in_library,
            .span = function.declaration,
            .message = message,
            .subject = .{ .module = module, .qualified = function.name },
        });
    }
}

// --- sentinel-int -----------------------------------------------------------

/// Function local names whose `-1` is the method's own contract rather than a
/// sentinel to rewrite: `str.find` and `bytes.find`/`find_any` answer the
/// searched index or `-1`, so a project function mirroring that spelling is
/// exempt by name.
const sentinel_exempt_names = [_][]const u8{ "find", "find_any" };

/// One comparison of a constant against a value with the constant on the right.
const Comparison = struct { op: typed.BinaryOp, value: typed.NodeId, literal: i128 };

/// One `-1` compared against a parameter or a field.
const MinusOneSite = struct {
    /// Identity of the parameter or field, so repeats of one subject group together.
    key: []const u8,
    /// Subject as the finding reads it, e.g. "field `pin` of `Pin`".
    description: []const u8,
    qualified: []const u8,
    module: []const u8,
    span: source.Span,
};

/// Whether a function is exempt from the sentinel rule by its local name.
fn sentinelExempt(qualified: []const u8) bool {
    for (sentinel_exempt_names) |name| if (std.mem.eql(u8, localName(qualified), name)) return true;
    return false;
}

/// The constant value of one integer expression, or null when it is not one.
fn literalValue(program: typed.Program, id: typed.NodeId) ?i128 {
    const node = program.nodes[@backingInt(id)];
    switch (node.data) {
        .integer => |value| return value,
        .unary => |unary| {
            if (unary.op != .neg) return null;
            const operand = literalValue(program, unary.operand) orelse return null;
            return -operand;
        },
        else => return null,
    }
}

/// The comparison one operator spells when its operands swap sides.
fn flippedComparison(op: typed.BinaryOp) typed.BinaryOp {
    return switch (op) {
        .lt => .gt,
        .gt => .lt,
        .le => .ge,
        .ge => .le,
        else => op,
    };
}

/// The value and constant one comparison tests, with the constant on the right,
/// or null when neither operand is an integer constant.
fn comparisonOperands(program: typed.Program, node: typed.Node) ?Comparison {
    if (node.data != .binary) return null;
    const binary = node.data.binary;
    if (literalValue(program, binary.right)) |literal| return .{ .op = binary.op, .value = binary.left, .literal = literal };
    if (literalValue(program, binary.left)) |literal| return .{ .op = flippedComparison(binary.op), .value = binary.right, .literal = literal };
    return null;
}

/// Whether one binary operator is a comparison.
fn comparisonOp(op: typed.BinaryOp) bool {
    return switch (op) {
        .lt, .le, .eq, .ne, .gt, .ge => true,
        else => false,
    };
}

/// Whether one comparison against a constant tests for a sentinel: any
/// comparison against a negative literal, or the `< 0` and `>= 0` guards that
/// name presence.
fn sentinelTest(op: typed.BinaryOp, literal: i128) bool {
    if (!comparisonOp(op)) return false;
    if (literal == 0) return op == .lt or op == .ge;
    return literal < 0;
}

/// Whether one function's declared result is an integer and some `return` in
/// its body is a negative integer literal, which is what makes that result a
/// sentinel. A function exempt by name never is.
fn returnsSentinel(memory: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error!bool {
    if (!function.signature.return_type.isInteger()) return false;
    if (sentinelExempt(function.name)) return false;
    var walker = try walk.Walker.init(memory, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        const statement = switch (item) {
            .statement => |id| id,
            .expression => continue,
        };
        const returned = switch (program.statements[@backingInt(statement)].data) {
            .ret => |value| value,
            else => continue,
        };
        if (literalValue(program, returned)) |value| if (value < 0) return true;
    }
    return false;
}

/// The sentinel function one expression is a direct call to, or null.
fn sentinelCallee(program: typed.Program, sources: []const bool, id: typed.NodeId) ?typed.FunctionId {
    const node = program.nodes[@backingInt(id)];
    const call = switch (node.data) {
        .call => |call| call,
        else => return null,
    };
    const index = @backingInt(call.function);
    if (index >= sources.len or !sources[index]) return null;
    return call.function;
}

/// `sentinel-int`: report an `int` used as a sentinel. A function whose result
/// is a negative literal on some path and is compared against a negative
/// literal where its value is tested is reported at that comparison, and so is
/// a parameter or field compared against `-1` in two or more places. Every
/// finding names the `int?` rewrite.
fn runSentinelInt(context: *RuleContext) std.mem.Allocator.Error!void {
    const program = context.facts.program;
    const sources = try context.memory.alloc(bool, program.functions.len);
    defer context.memory.free(sources);
    for (program.functions, 0..) |function, index| sources[index] = try returnsSentinel(context.memory, program, function);
    var caller: std.ArrayList(?typed.FunctionId) = .empty;
    defer caller.deinit(context.memory);
    var sites: std.ArrayList(MinusOneSite) = .empty;
    defer sites.deinit(context.memory);
    for (program.functions) |function| try scanSentinelFunction(context, program, sources, function, &caller, &sites);
    try reportMinusOneSites(context, sites.items);
}

/// Scan one function for comparisons that test a sentinel result and for `-1`
/// comparisons against its own parameters or record fields. `caller` is reused
/// as the per-function map from a local slot to the sentinel function whose
/// result it holds, and `sites` collects the repeated `-1` subjects. Only
/// source bindings count: a lowering temporary (a collection read's rooted
/// receiver, a normalized index, a match payload) is the compiler's own
/// bookkeeping and never a reader-facing sentinel.
fn scanSentinelFunction(context: *RuleContext, program: typed.Program, sources: []const bool, function: typed.Function, caller: *std.ArrayList(?typed.FunctionId), sites: *std.ArrayList(MinusOneSite)) std.mem.Allocator.Error!void {
    const memory = context.memory;
    try caller.resize(memory, function.scope.locals.len);
    @memset(caller.items, null);
    var stores: std.ArrayList(typed.Store) = .empty;
    defer stores.deinit(memory);
    var walker = try walk.Walker.init(memory, program, function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| {
        const statement = switch (item) {
            .statement => |id| id,
            .expression => continue,
        };
        switch (program.statements[@backingInt(statement)].data) {
            .range_loop => |range| for ([_]typed.Store{ range.plan().start, range.plan().end }) |store| {
                const slot = @backingInt(store.slot);
                if (slot >= function.scope.locals.len or function.scope.locals[slot].usage.temporary) continue;
                try stores.append(memory, store);
            },
            .initialize, .assign => |store| {
                const slot = @backingInt(store.slot);
                if (slot >= function.scope.locals.len) continue;
                if (function.scope.locals[slot].usage.temporary) continue;
                try stores.append(memory, store);
            },
            else => {},
        }
    }
    // A local may be assigned from another local, so propagate the sentinel
    // fact to a fixpoint instead of trusting statement order.
    var changed = true;
    while (changed) {
        changed = false;
        for (stores.items) |store| {
            const slot = @backingInt(store.slot);
            if (slot >= caller.items.len or caller.items[slot] != null) continue;
            if (sentinelCallee(program, sources, store.value)) |callee| {
                caller.items[slot] = callee;
                changed = true;
                continue;
            }
            const value = program.nodes[@backingInt(store.value)];
            const from = switch (value.data) {
                .local => |source_slot| @backingInt(source_slot),
                else => continue,
            };
            if (from < caller.items.len) if (caller.items[from]) |callee| {
                caller.items[slot] = callee;
                changed = true;
            };
        }
    }
    var comparisons = try walk.Walker.init(memory, program, function.scope.body);
    defer comparisons.deinit();
    while (try comparisons.next()) |item| {
        const id = switch (item) {
            .expression => |node| node,
            .statement => continue,
        };
        const node = program.nodes[@backingInt(id)];
        const comparison = comparisonOperands(program, node) orelse continue;
        if (!comparisonOp(comparison.op)) continue;
        // A `-1` comparison is the second trigger on its own, whether or not it
        // also tests a sentinel function's result below.
        if (comparison.literal == -1) try recordMinusOne(context, program, function, comparison.value, sites);
        if (!sentinelTest(comparison.op, comparison.literal)) continue;
        if (sentinelCallee(program, sources, comparison.value)) |callee| {
            try reportSentinelComparison(context, program, callee, node.span);
            continue;
        }
        const value = program.nodes[@backingInt(comparison.value)];
        const slot = switch (value.data) {
            .local => |local| @backingInt(local),
            else => continue,
        };
        if (slot >= caller.items.len) continue;
        if (caller.items[slot]) |callee| try reportSentinelComparison(context, program, callee, node.span);
    }
}

/// Report one comparison that tests a sentinel function's result against a
/// negative literal, naming the callee and the `int?` rewrite.
fn reportSentinelComparison(context: *RuleContext, program: typed.Program, callee: typed.FunctionId, span: source.Span) std.mem.Allocator.Error!void {
    const sentinel = program.functions[@backingInt(callee)];
    const callee_name = try display_name.spelled(context.memory, sentinel.name);
    const message = try std.fmt.allocPrint(context.memory, "`{s}` returns -1 on one path and its result is tested against a negative literal here; return `int?` and test `is None` or use `unwrap_or`", .{callee_name});
    try context.findings.append(context.memory, .{
        .code = "L_SENTINEL_INT",
        .rule = rule_sentinel_int,
        .span = span,
        .message = message,
        .subject = .{ .module = moduleName(sentinel.name), .qualified = sentinel.name },
    });
}

/// Record one `-1` comparison against a parameter or a record field.
fn recordMinusOne(context: *RuleContext, program: typed.Program, function: typed.Function, value: typed.NodeId, sites: *std.ArrayList(MinusOneSite)) std.mem.Allocator.Error!void {
    const node = program.nodes[@backingInt(value)];
    switch (node.data) {
        .field => |field| {
            const base = program.nodes[@backingInt(field.base)].ty;
            if (!base.isAggregate()) return;
            const record = program.records[base.recordIndex()];
            if (field.index >= record.fields.len) return;
            // A field read the lowering introduced names no declared field of a
            // source value, so it is not a reader-facing sentinel either.
            if (program.nodes[@backingInt(field.base)].data == .local) {
                const slot = @backingInt(program.nodes[@backingInt(field.base)].data.local);
                if (slot < function.scope.locals.len and function.scope.locals[slot].usage.temporary) return;
            }
            try sites.append(context.memory, .{
                .key = try std.fmt.allocPrint(context.memory, "field:{d}:{d}", .{ base.recordIndex(), field.index }),
                .description = try std.fmt.allocPrint(context.memory, "field `{s}` of `{s}`", .{ record.fields[field.index].name, try display_name.spelled(context.memory, record.name) }),
                .qualified = function.name,
                .module = moduleName(function.name),
                .span = node.span,
            });
        },
        .local => |local| {
            const slot = @backingInt(local);
            if (slot >= function.signature.parameter_count or slot >= function.scope.locals.len) return;
            if (function.scope.locals[slot].usage.temporary) return;
            try sites.append(context.memory, .{
                .key = try std.fmt.allocPrint(context.memory, "parameter:{d}:{d}", .{ @backingInt(function.id), slot }),
                .description = try std.fmt.allocPrint(context.memory, "parameter `{s}` of `{s}`", .{ function.scope.locals[slot].name, try display_name.spelled(context.memory, function.name) }),
                .qualified = function.name,
                .module = moduleName(function.name),
                .span = node.span,
            });
        },
        else => {},
    }
}

/// Report one finding per parameter or field compared against `-1` in two or
/// more places, naming the subject and the `int?` rewrite.
fn reportMinusOneSites(context: *RuleContext, sites: []MinusOneSite) std.mem.Allocator.Error!void {
    std.mem.sort(MinusOneSite, sites, {}, minusOneLessThan);
    var start: usize = 0;
    while (start < sites.len) {
        var end = start + 1;
        while (end < sites.len and std.mem.eql(u8, sites[start].key, sites[end].key)) end += 1;
        if (end - start >= 2) {
            const site = sites[end - 1];
            const message = try std.fmt.allocPrint(context.memory, "{s} is compared against -1 in {d} places; declare it `int?` and test `is None` or use `unwrap_or`", .{ site.description, end - start });
            try context.findings.append(context.memory, .{
                .code = "L_SENTINEL_INT",
                .rule = rule_sentinel_int,
                .span = site.span,
                .message = message,
                .subject = .{ .module = site.module, .qualified = site.qualified },
            });
        }
        start = end;
    }
}

fn minusOneLessThan(_: void, left: MinusOneSite, right: MinusOneSite) bool {
    return std.mem.lessThan(u8, left.key, right.key);
}

/// Convert Core warnings into findings so profile modes, waivers and gate status agree.
fn runNeedlessCopy(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, "W_NEEDLESS_COPY")) continue;
        try context.findings.append(context.memory, .{
            .code = "L_NEEDLESS_COPY",
            .rule = rule_needless_copy,
            .span = item.span,
            .message = item.message,
            .related = item.related,
            .subject = subjectAt(context.facts, item.span),
        });
    }
}

/// Convert one idiom warning (`syntax_hints.zig`) into a finding, so profile modes, waivers and the gate agree.
fn idiomFindings(context: *RuleContext, warning: []const u8, code: []const u8, rule: []const u8) std.mem.Allocator.Error!void {
    for (context.facts.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, warning)) continue;
        try context.findings.append(context.memory, .{
            .code = code,
            .rule = rule,
            .span = item.span,
            .message = item.message,
            .related = item.related,
            .subject = subjectAt(context.facts, item.span),
        });
    }
}

fn runCopyMove(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_COPY_MOVE", "L_COPY_MOVE", rule_copy_move);
}

fn runByteSet(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_BYTE_SET", "L_BYTE_SET", rule_byte_set);
}

fn runRangeChain(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_RANGE_CHAIN", "L_RANGE_CHAIN", rule_range_chain);
}

fn runLiteralMatch(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_LITERAL_MATCH", "L_LITERAL_MATCH", rule_literal_match);
}

fn runPatternShorthand(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_PATTERN_SHORTHAND", "L_PATTERN_SHORTHAND", rule_pattern_shorthand);
}

fn runOptionTry(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_OPTION_TRY", "L_OPTION_TRY", rule_option_try);
}

fn runElseIsTry(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_ELSE_IS_TRY", "L_ELSE_IS_TRY", rule_else_is_try);
}

fn runMatchElse(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_MATCH_ELSE", "L_MATCH_ELSE", rule_match_else);
}

fn runMatchIs(context: *RuleContext) std.mem.Allocator.Error!void {
    try idiomFindings(context, "W_MATCH_IS", "L_MATCH_IS", rule_match_is);
}

/// The declaration whose checked span contains `span`, so a finding on a body
/// carries its function's subject and the same tests-for index every other rule
/// reads.
fn subjectAt(facts: *const Facts, span: source.Span) Subject {
    for (facts.program.functions) |function| {
        const body = facts.program.statements[@backingInt(function.scope.body)].span;
        const first = @min(function.declaration.start, body.start);
        const last = @max(function.declaration.end, body.end);
        if (span.start < first or span.start >= last) continue;
        return .{ .module = moduleName(function.name), .qualified = function.name };
    }
    return .{};
}

fn runNoallocAllocates(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, "E_NOALLOC_ALLOCATES")) continue;
        var subject: Subject = .{};
        if (item.related) |related| for (context.facts.program.functions) |function| {
            const bound = function.policy.noalloc orelse continue;
            if (bound.start != related.span.start) continue;
            subject = .{ .module = moduleName(function.name), .qualified = function.name };
            break;
        };
        try context.findings.append(context.memory, .{
            .code = "L_NOALLOC_ALLOCATES",
            .rule = rule_noalloc_allocates,
            .span = item.span,
            .message = item.message,
            .related = item.related,
            .subject = subject,
        });
    }
}

// ---------------------------------------------------------------------------
// The loop rules: work inside a loop that grows with the list it works on.
// Each rule reads an exact shape on the checked tree and names its rewrite; a
// site is attributed to its innermost loop, so a nested loop's shape is not
// charged to the outer one. `linear-search-in-loop` reports a search on a list
// the loop does not change, and all three refuse only in a declaration changed
// against `--against REF` (P1's heuristic finding).

/// One site a loop rule reads: the list it works on, where it is, and the
/// innermost loop around it.
const LoopSite = struct { root: usize, span: source.Span, loop: usize };

/// Everything the loop rules read about one checked function.
const LoopScan = struct {
    loops: std.ArrayList(source.Span) = .empty,
    appends: std.ArrayList(LoopSite) = .empty,
    searches: std.ArrayList(LoopSite) = .empty,
    shifts: std.ArrayList(LoopSite) = .empty,
    sorts: std.ArrayList(LoopSite) = .empty,

    /// Release the scan's lists.
    fn deinit(self: *LoopScan, memory: std.mem.Allocator) void {
        self.loops.deinit(memory);
        self.appends.deinit(memory);
        self.searches.deinit(memory);
        self.shifts.deinit(memory);
        self.sorts.deinit(memory);
    }

    /// Whether one loop appends to `root`.
    fn appended(self: LoopScan, root: usize, loop: usize) bool {
        for (self.appends.items) |site| if (site.root == root and site.loop == loop) return true;
        return false;
    }
};

/// Whether `inner` lies inside `outer`.
fn spanInside(outer: source.Span, inner: source.Span) bool {
    return inner.start >= outer.start and inner.end <= outer.end;
}

/// The innermost loop whose span contains `span`, or null outside every loop.
fn innermostLoop(loops: []const source.Span, span: source.Span) ?usize {
    var found: ?usize = null;
    for (loops, 0..) |loop, index| {
        if (!spanInside(loop, span)) continue;
        if (found) |best| if (loops[best].start >= loop.start) continue;
        found = index;
    }
    return found;
}

/// Scan one function for the shapes the three loop rules read.
fn scanLoopSites(memory: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error!LoopScan {
    var scan: LoopScan = .{};
    var loops = try walk.Walker.init(memory, program, function.scope.body);
    defer loops.deinit();
    while (try loops.next()) |item| {
        const statement = switch (item) {
            .statement => |value| value,
            .expression => continue,
        };
        const data = program.statements[@backingInt(statement)].data;
        if (data == .loop or data == .range_loop) try scan.loops.append(memory, program.statements[@backingInt(statement)].span);
    }
    if (scan.loops.items.len == 0) return scan;
    var body = try walk.Walker.init(memory, program, function.scope.body);
    defer body.deinit();
    while (try body.next()) |item| {
        const id = switch (item) {
            .expression => |value| value,
            .statement => continue,
        };
        const node = program.nodes[@backingInt(id)];
        const loop = innermostLoop(scan.loops.items, node.span) orelse continue;
        try classifyLoopSite(memory, program, function, node, loop, &scan);
    }
    return scan;
}

/// Record one expression's loop-rule shape, when it has one.
fn classifyLoopSite(memory: std.mem.Allocator, program: typed.Program, function: typed.Function, node: typed.Node, loop: usize, scan: *LoopScan) std.mem.Allocator.Error!void {
    switch (node.data) {
        .call => |call| {
            if (@backingInt(call.function) >= program.functions.len) return;
            const callee = unspecializedName(program.functions[@backingInt(call.function)].name);
            const site: LoopSite = .{ .root = 0, .span = node.span, .loop = loop };
            if (std.mem.eql(u8, callee, "lists::contains") or std.mem.eql(u8, callee, "lists::index_of") or std.mem.eql(u8, callee, "lists::remove")) {
                if (call.arguments.len == 0) return;
                const root = (try loopRoot(memory, program, function, nodeRoot(program, call.arguments[0]) orelse return)) orelse return;
                if (!listSlot(program, function, root)) return;
                return scan.searches.append(memory, .{ .root = root, .span = site.span, .loop = loop });
            }
            if (!std.mem.eql(u8, callee, "lists::pop_at") and !std.mem.eql(u8, callee, "lists::insert")) return;
            if (call.arguments.len < 2 or !zeroIndex(program, call.arguments[1])) return;
            const root = (try loopRoot(memory, program, function, nodeRoot(program, call.arguments[0]) orelse return)) orelse return;
            if (!listSlot(program, function, root)) return;
            return scan.shifts.append(memory, .{ .root = root, .span = site.span, .loop = loop });
        },
        .buffer_operation => |operation| {
            const site: LoopSite = .{ .root = 0, .span = node.span, .loop = loop };
            switch (operation.kind) {
                .append, .extend, .index_of, .pop_at, .insert => {
                    const root = (try loopRoot(memory, program, function, @backingInt(operation.owner))) orelse return;
                    if (!listSlot(program, function, root)) return;
                    switch (operation.kind) {
                        .append, .extend => try scan.appends.append(memory, .{ .root = root, .span = site.span, .loop = loop }),
                        .index_of => try scan.searches.append(memory, .{ .root = root, .span = site.span, .loop = loop }),
                        else => {
                            if (operation.arguments.len == 0 or !zeroIndex(program, operation.arguments[0])) return;
                            try scan.shifts.append(memory, .{ .root = root, .span = site.span, .loop = loop });
                        },
                    }
                },
                .sort => {
                    // The sort orders a fresh copy of its input; `L = sorted(L)`
                    // is the shape where the list is re-sorted as it grows.
                    const input = (try dataRoot(memory, program, function, @backingInt(operation.owner), 0)) orelse return;
                    if (!listSlot(program, function, input)) return;
                    try scan.sorts.append(memory, .{ .root = input, .span = site.span, .loop = loop });
                },
                else => {},
            }
        },
        else => {},
    }
}

/// Whether one checked index expression is the literal `0`.
fn zeroIndex(program: typed.Program, id: typed.NodeId) bool {
    return switch (program.nodes[@backingInt(id)].data) {
        .integer => |value| value == 0,
        else => false,
    };
}

/// The root local one value's place starts at, for any expression node.
fn nodeRoot(program: typed.Program, id: typed.NodeId) ?usize {
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .local => |slot| @backingInt(slot),
        .field => |field| nodeRoot(program, field.base),
        .index => |index| nodeRoot(program, index.base),
        .cast, .wrap, .unwrap => |value| nodeRoot(program, value),
        .block_value => |block| nodeRoot(program, block.value),
        .buffer_operation => |operation| @backingInt(operation.owner),
        else => null,
    };
}

/// Resolve a place local through the compiler temporaries a field, element or
/// slice access lowers through.
fn loopRoot(memory: std.mem.Allocator, program: typed.Program, function: typed.Function, slot: usize) std.mem.Allocator.Error!?usize {
    var current = slot;
    var depth: usize = 0;
    while (depth < 32) : (depth += 1) {
        if (current >= function.scope.locals.len) return null;
        const local = function.scope.locals[current];
        if (!local.usage.temporary) return current;
        var body = try walk.Walker.init(memory, program, function.scope.body);
        defer body.deinit();
        var initializer: ?typed.NodeId = null;
        while (try body.next()) |item| {
            const statement = switch (item) {
                .statement => |value| value,
                .expression => continue,
            };
            const store = switch (program.statements[@backingInt(statement)].data) {
                .initialize => |value| value,
                else => continue,
            };
            if (@backingInt(store.slot) != current) continue;
            if (initializer != null) return null;
            initializer = store.value;
        }
        current = nodeRoot(program, initializer orelse return null) orelse return null;
    }
    return null;
}

/// The named list local a value's data comes from, following the copy a fresh
/// result is built through; null for a value the loop built itself.
fn dataRoot(memory: std.mem.Allocator, program: typed.Program, function: typed.Function, slot: usize, depth: usize) std.mem.Allocator.Error!?usize {
    if (depth > 32 or slot >= function.scope.locals.len) return null;
    if (!function.scope.locals[slot].usage.temporary) return slot;
    const initializer = try @import("needless_copy.zig").soleInitializer(memory, program, function, slot) orelse return null;
    return valueRoot(memory, program, function, initializer, depth + 1);
}

/// The named list local one value's data comes from.
fn valueRoot(memory: std.mem.Allocator, program: typed.Program, function: typed.Function, id: typed.NodeId, depth: usize) std.mem.Allocator.Error!?usize {
    if (depth > 32) return null;
    const node = program.nodes[@backingInt(id)];
    return switch (node.data) {
        .local => |slot| dataRoot(memory, program, function, @backingInt(slot), depth + 1),
        .field => |field| valueRoot(memory, program, function, field.base, depth + 1),
        .index => |index| valueRoot(memory, program, function, index.base, depth + 1),
        .cast, .wrap, .unwrap => |value| valueRoot(memory, program, function, value, depth + 1),
        .block_value => |block| valueRoot(memory, program, function, block.value, depth + 1),
        .buffer_operation => |operation| dataRoot(memory, program, function, @backingInt(operation.owner), depth + 1),
        else => null,
    };
}

/// Whether `slot` holds a list.
fn listSlot(program: typed.Program, function: typed.Function, slot: usize) bool {
    if (slot >= function.scope.locals.len) return false;
    const ty = function.scope.locals[slot].ty;
    if (!ty.isAggregate() or ty.recordIndex() >= program.records.len) return false;
    return program.records[ty.recordIndex()].collection.kind == .list;
}

/// Whether `slot` is declared before `loop` starts, so the list outlives it.
fn declaredOutside(function: typed.Function, slot: usize, loop: source.Span) bool {
    if (slot >= function.scope.locals.len) return false;
    return function.scope.locals[slot].declaration.start < loop.start;
}

/// The subject a loop-rule finding names: the function that holds the loop.
fn functionSubject(function: typed.Function) Subject {
    return .{ .module = moduleName(function.name), .qualified = function.name };
}

/// `linear-search-in-loop`: a list the loop appends to is linearly searched in
/// the same loop. A search on a list the loop leaves alone only reports.
fn runLinearSearchInLoop(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        var scan = try scanLoopSites(context.memory, context.facts.program, function);
        defer scan.deinit(context.memory);
        for (scan.searches.items) |site| {
            const loop = scan.loops.items[site.loop];
            if (!declaredOutside(function, site.root, loop)) continue;
            const appended = scan.appended(site.root, site.loop);
            const name = function.scope.locals[site.root].name;
            const reason = if (appended)
                "is searched and appended in the same loop, so every probe walks what the loop has built; keep a `set` or `dict` beside it and probe that instead"
            else
                "is searched in a loop but the loop does not change it; a `set` or `dict` answers the same probe in constant time";
            const message = try std.fmt.allocPrint(context.memory, "{s}: `{s}` {s}", .{
                rule_linear_search_in_loop, name, reason,
            });
            try context.findings.append(context.memory, .{
                .code = "L_LINEAR_SEARCH_IN_LOOP",
                .rule = rule_linear_search_in_loop,
                .span = site.span,
                .message = message,
                .subject = functionSubject(function),
                .state = .{ .report_only = !appended },
            });
        }
    }
}

/// `shift-in-loop`: a list declared outside the loop loses its front element.
fn runShiftInLoop(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        var scan = try scanLoopSites(context.memory, context.facts.program, function);
        defer scan.deinit(context.memory);
        for (scan.shifts.items) |site| {
            const loop = scan.loops.items[site.loop];
            if (!declaredOutside(function, site.root, loop)) continue;
            const message = try std.fmt.allocPrint(context.memory, "{s}: `{s}` removes or inserts at index 0 inside a loop, so every later element shifts; keep an index cursor over the list, or use B6's `deque`", .{
                rule_shift_in_loop, function.scope.locals[site.root].name,
            });
            try context.findings.append(context.memory, .{
                .code = "L_SHIFT_IN_LOOP",
                .rule = rule_shift_in_loop,
                .span = site.span,
                .message = message,
                .subject = functionSubject(function),
            });
        }
    }
}

/// `sort-in-loop`: sorting a list the same loop appends to, so it is re-sorted
/// as it grows.
fn runSortInLoop(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        var scan = try scanLoopSites(context.memory, context.facts.program, function);
        defer scan.deinit(context.memory);
        for (scan.sorts.items) |site| {
            const loop = scan.loops.items[site.loop];
            if (!declaredOutside(function, site.root, loop)) continue;
            if (!scan.appended(site.root, site.loop)) continue;
            const message = try std.fmt.allocPrint(context.memory, "{s}: `{s}` is appended to and sorted in the same loop, so it is re-sorted as it grows; sort it once after the loop, or use B6's `heap`", .{
                rule_sort_in_loop, function.scope.locals[site.root].name,
            });
            try context.findings.append(context.memory, .{
                .code = "L_SORT_IN_LOOP",
                .rule = rule_sort_in_loop,
                .span = site.span,
                .message = message,
                .subject = functionSubject(function),
            });
        }
    }
}

/// `alloc-in-loop`: a construction or conversion site the Core passes placed at
/// loop depth 1 or more. The rows are `selka cost --sites` rows, so the rule
/// reads the same classification the build reports and never re-derives one;
/// it reports only in a declaration changed against `--against REF` (the plan's
/// P1 heuristic finding), never refuses, and names the kind's hint.
fn runAllocInLoop(context: *RuleContext) std.mem.Allocator.Error!void {
    // Several Core instructions can share one witness span; the reader sees one
    // site there, so the rule names it once.
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer seen.deinit(context.memory);
    for (context.facts.sites) |site| {
        if (site.loop_depth < 1) continue;
        if (site.kind != .construction and site.kind != .conversion) continue;
        const span = siteSpan(context.facts.src, site.path, site.line, site.column) orelse continue;
        const key: u64 = @as(u64, span.start) << 8 | @backingInt(site.kind);
        const entry = try seen.getOrPut(context.memory, key);
        if (entry.found_existing) continue;
        // The Core name is unqualified for a one-module project; the enclosing
        // checked declaration is what the diff and `tests-for` key on.
        var subject = subjectAt(context.facts, span);
        if (subject.qualified.len == 0) subject = .{ .module = moduleName(site.function), .qualified = site.function };
        const message = try std.fmt.allocPrint(context.memory, "{s}: a {s} site at loop depth {d} in `{s}`; {s}", .{
            rule_alloc_in_loop, @tagName(site.kind), site.loop_depth, try display_name.spelled(context.memory, subject.qualified), site.hint,
        });
        try context.findings.append(context.memory, .{
            .code = "L_ALLOC_IN_LOOP",
            .rule = rule_alloc_in_loop,
            .span = span,
            .message = message,
            .subject = subject,
            .state = .{ .report_only = true },
        });
    }
}

/// `copy-in-loop`: a copy site the Core passes placed at loop depth 1 or more,
/// read from the same `cost --sites` rows as `alloc-in-loop`. Under rule C every
/// copy is written, so each one is a choice, and the rule reports it in every
/// declaration. It refuses only in a declaration changed against `--against REF`
/// under `--gate`, the way the other loop rules do. The message names the
/// rewrites in the order a reviewer should try them.
fn runCopyInLoop(context: *RuleContext) std.mem.Allocator.Error!void {
    // The copy rows of one span arrive once per Core instruction; the reader sees one site.
    var seen: std.AutoHashMapUnmanaged(u64, void) = .empty;
    defer seen.deinit(context.memory);
    for (context.facts.sites) |site| {
        if (site.loop_depth < 1) continue;
        if (site.kind != .copy) continue;
        const span = siteSpan(context.facts.src, site.path, site.line, site.column) orelse continue;
        const key: u64 = @as(u64, span.start) << 8 | @backingInt(site.kind);
        const entry = try seen.getOrPut(context.memory, key);
        if (entry.found_existing) continue;
        var subject = subjectAt(context.facts, span);
        if (subject.qualified.len == 0) subject = .{ .module = moduleName(site.function), .qualified = site.function };
        const form = try copy_forms.judge(.{
            .memory = context.memory,
            .program = context.facts.program,
            .src = context.facts.src,
            .diagnostics = context.facts.diagnostics,
        }, span.start);
        const message = try std.fmt.allocPrint(context.memory, "{s}: a copy at loop depth {d} in `{s}`; {s}", .{
            rule_copy_in_loop, site.loop_depth, try display_name.spelled(context.memory, subject.qualified), copyAdvice(form),
        });
        try context.findings.append(context.memory, .{
            .code = "L_COPY_IN_LOOP",
            .rule = rule_copy_in_loop,
            .span = span,
            .message = message,
            .subject = subject,
        });
    }
}

/// The one line that names the zero-copy form which fits a copy in a loop, with the documentation section that teaches it.
fn copyAdvice(form: copy_forms.Form) []const u8 {
    return switch (form) {
        .borrow => "the copy-free form checks here, so `selka fix` deletes the copy (docs/tooling/lint.md#needless-copies)",
        .own => "its source is not read again, so a move replaces it: `own x`, `take(mut x.f)` or `for x in own xs` (docs/value-semantics.md#taking-and-exchanging-a-value)",
        .span => "store a `spans.Span` into the source instead of a copy of its text (docs/value-semantics.md#long-lived-data-hold-the-key-not-the-borrow)",
        .symbol => "the same name is copied every iteration; intern it once with `symbols` and store the key (docs/standard-library.md#symbols)",
        .loop_take => "if neither the list nor the element is read again, `for x in own xs` takes the elements and `own x` or `own x.field` " ++
            "moves each one without a copy (docs/value-semantics.md#taking-and-exchanging-a-value)",
        .loop_param => "the value is stored, so the copy is a real transfer; an `own` list parameter would let the loop take the elements: " ++
            "`for x in own xs`, then `own x` or `own x.field` (docs/value-semantics.md#taking-and-exchanging-a-value)",
        .transfer => "the value is stored, so the copy is a real transfer",
    };
}

/// The checked source position of one `cost --sites` row: its module path and
/// one-based line and column mapped into the merged source's bytes.
fn siteSpan(src: source.Source, path: []const u8, line: u32, column: u32) ?source.Span {
    if (line == 0 or column == 0) return null;
    if (src.origins.len == 0) {
        if (!std.mem.eql(u8, src.path, path)) return null;
        return positionSpan(src, line, column);
    }
    for (src.origins) |origin| {
        if (!std.mem.eql(u8, origin.original.path, path)) continue;
        const local = positionSpan(origin.original, line, column) orelse return null;
        return .{ .start = origin.start + local.start, .end = origin.start + local.end };
    }
    return null;
}

/// One zero-width span at a source's one-based line and column.
fn positionSpan(src: source.Source, line: u32, column: u32) ?source.Span {
    if (line > src.line_starts.len) return null;
    const start = src.line_starts[line - 1];
    const end = if (line < src.line_starts.len) src.line_starts[line] - 1 else src.bytes.len;
    const offset = start + @min(@as(usize, column - 1), end -| start);
    const clamped = @min(offset, src.bytes.len);
    return .{ .start = clamped, .end = clamped };
}
