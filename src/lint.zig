//! `mylang lint`: one verdict over a checked project, with a code family
//! (`L_*`), profiles, waiver comments and a report/block split.
//!
//! The driver never changes acceptance on its own. Every rule resolves to a
//! mode for the selected profile (`agent` by default), a report is printed and
//! ignored, and only a `block` rule under `--gate` (or a project that sets
//! `on_build: "block"`) makes the command exit 3. Waivers are directive
//! comments on the line above a declaration; a waiver without a reason is
//! itself a blocking finding.
const std = @import("std");
const ast = @import("ast.zig");
const call_arguments = @import("call_arguments.zig");
const declaration_diff = @import("declaration_diff.zig");
const diagnostic = @import("diagnostic.zig");
const diagnostic_output = @import("diagnostic_output.zig");
const duplicates = @import("duplicates.zig");
const effect_set = @import("effect_set.zig");
const graph = @import("project.zig");
const interfaces = @import("interfaces.zig");
const lint_config = @import("lint_config.zig");
const lint_store = @import("lint_store.zig");
const project_compile = @import("project_compile.zig");
const quality = @import("quality.zig");
const ref_diff = @import("ref_diff.zig");
const source = @import("source.zig");
const tests_index = @import("tests_index.zig");
const component_adapter = @import("component_adapter.zig");
const typed = @import("typed.zig");
const walk = @import("typed_walk.zig");

/// Exit status for a language-valid project with at least one blocking finding.
pub const blocked_status: u8 = 3;
/// Exit status for a valid project with no blocking finding.
pub const clean_status: u8 = 0;

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
    diagnostics: diagnostic_output.Format,
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
};

/// Declaration identity a baseline or ratchet row is keyed on.
pub const Subject = struct {
    module: []const u8 = "",
    qualified: []const u8 = "",
};

/// One lint finding, before mode resolution decides its severity.
pub const Finding = struct {
    code: []const u8,
    rule: []const u8,
    severity: diagnostic.Severity = .warning,
    span: source.Span,
    message: []const u8,
    related: ?diagnostic.Related = null,
    subject: Subject = .{},
};

/// The exported declarations and discovered tests one run judges, each beside
/// the per-function flag array built from it.
pub const Roots = struct {
    exports: []const typed.FunctionId,
    tests: []const typed.FunctionId,
    export_flags: []const bool,
    test_flags: []const bool,

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
    /// Index over the same discovery, call graph and inversion `mylang
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
};

/// The qualified-name separator every rule splits on.
const separator = "::";

/// Local (unqualified) part of a `module::name` function identity.
pub fn localName(qualified: []const u8) []const u8 {
    if (std.mem.indexOf(u8, qualified, separator)) |at| return qualified[at + separator.len ..];
    return qualified;
}

/// Module part of a `module::name` function identity, or empty when unqualified.
pub fn moduleName(qualified: []const u8) []const u8 {
    if (std.mem.indexOf(u8, qualified, separator)) |at| return qualified[0..at];
    return "";
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
const rule_decision_points = "decision-points";
const rule_dead_export = "dead-export";
const rule_undocumented_export = "undocumented-export";
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
const rule_derived_effects = "derived-effects";
const rule_noalloc_allocates = "noalloc-allocates";

/// Advisory size-budget defaults for the report-only rules (plan section 9).
const default_max_function_lines: usize = 80;
const default_max_parameters: usize = 6;
const default_max_nesting: usize = 4;
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
/// Module globs allowed to carry the `output` effect (plan section 9). The
/// conventional entry module and the CLI/integration families print by design.
const default_output_modules: []const []const u8 = &.{ "main", "*_cli", "cli", "cli.*", "*_integration", "integration.*" };
/// Shortest accepted `undocumented-export` docstring, over non-whitespace bytes.
const default_min_chars: usize = 12;

/// Every rule the driver knows. Wave 1 ships the configuration, the finding
/// family, waivers and exit codes; the semantic rules follow.
pub const rules = [_]Rule{
    .{
        .name = rule_noalloc_allocates,
        .description = "written noalloc has a static Core allocation witness or unsupported body",
        .modes = .{ .agent = .block, .strict = .block, .safety = .block },
        .run = runNoallocAllocates,
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
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runFunctionLength,
    },
    .{
        .name = rule_parameters,
        .description = "a function takes more parameters than its budget",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runParameters,
    },
    .{
        .name = rule_nesting_depth,
        .description = "a function nests control flow deeper than its budget",
        .modes = .{ .agent = .report, .strict = .report, .safety = .report },
        .run = runNestingDepth,
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
        .name = rule_sentinel_int,
        .description = "an `int` sentinel a negative literal marks, where `Option[int]` with `is None` or `unwrap_or` would say it",
        .modes = .{ .agent = .report, .strict = .block, .safety = .block },
        .run = runSentinelInt,
    },
    .{
        .name = rule_derived_effects,
        .description = "an effect clause that restates the ceiling its own parameter list implies",
        .modes = .{ .agent = .report, .strict = .block, .safety = .block },
        .run = runDerivedEffects,
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

/// Evaluate every enabled rule and return the final findings and counts without
/// writing anything. The CLI wrapper `run` renders and prints the summary, so a
/// test can drive the identical pipeline without touching the process stdout
/// (which is the test runner's own protocol pipe).
pub fn evaluate(request: Request, scratch: std.mem.Allocator) RunError!Outcome {
    return evaluateUsing(request, scratch, .reference);
}

/// Evaluate with the test-index implementation chosen at the command boundary.
pub fn evaluateUsing(request: Request, scratch: std.mem.Allocator, adapter: component_adapter.Adapter) RunError!Outcome {
    const program = request.compilation.program.?;
    const exports = try request.compilation.exportRoots(scratch);
    const tests = try request.compilation.testRoots(scratch);
    var analysis = try quality.analyzeWithExports(scratch, program, request.compilation.src, .{}, exports);
    defer analysis.deinit();

    const test_flags = try scratch.alloc(bool, program.functions.len);
    const export_flags = try scratch.alloc(bool, program.functions.len);
    @memset(test_flags, false);
    @memset(export_flags, false);
    // `testRoots` is the native-test entry set: exported declarations *and*
    // discovered tests. Only the `test_`-prefixed ones and `@test` declarations
    // are tests for coverage purposes, or every exported function would vouch
    // for itself.
    var test_ids: std.ArrayList(typed.FunctionId) = .empty;
    for (tests) |id| {
        const function = program.functions[@backingInt(id)];
        if (!isTestName(function.name) and !ast.hasAttribute(request.compilation.syntax, function.declaration, .@"test")) continue;
        test_flags[@backingInt(id)] = true;
        try test_ids.append(scratch, id);
    }
    for (exports) |id| export_flags[@backingInt(id)] = true;

    var facts: Facts = .{
        .program = program,
        .src = request.compilation.src,
        .syntax = request.compilation.syntax,
        .functions = analysis.functions,
        .diagnostics = request.compilation.diagnostics.items.items,
        .roots = .{ .exports = exports, .tests = test_ids.items, .test_flags = test_flags, .export_flags = export_flags },
    };

    // One reachability walk for the whole run, built before any rule reads it:
    // the same discovered tests, call graph and inversion `mylang tests-for`
    // answers from. The `untested-export` verdict and every related note on a
    // finding read this index, so none of them can disagree with the command.
    var reach = try buildReachabilityIndex(scratch, request.compilation, adapter);
    defer reach.deinit();

    var findings: std.ArrayList(Finding) = .empty;
    var waived: usize = 0;

    var waivers: std.ArrayList(Waiver) = .empty;
    try scanWaivers(scratch, request.compilation.src, &waivers);
    try scanAttributeWaivers(scratch, request.compilation.src, request.compilation.syntax, &waivers);

    const profile = request.options.profile orelse if (request.config) |config| config.profile else .agent;
    const force_block = request.options.gate or (if (request.config) |config| config.on_build == .block else false);
    const root = std.fs.path.dirname(request.entry_path) orelse ".";

    // `change-without-test` judges a diff rather than the tree, so it only runs
    // when the caller asked for both `--gate` and `--against REF`; every other
    // invocation leaves its context null and the rule silent.
    const change: ?ChangeScope = if (request.options.gate and request.options.against != null) .{
        .io = request.io,
        .repo_root = root,
        .reference = request.options.against.?,
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
        const mode = resolveMode(rule, profile, request.config);
        if (mode == .off) continue;
        const start = findings.items.len;
        try rule.run(&context);
        const kept = filterWaived(waivers.items, request.compilation.src, findings.items, start, &waived, if (mode == .block) .err else .warning);
        findings.shrinkRetainingCapacity(kept);
    }

    // The waiver-reason rule is exact and always blocks: a silent waiver is
    // exactly the review bypass the store exists to prevent.
    const reason_start = findings.items.len;
    try appendWaiverReasonFindings(scratch, waivers.items, &findings);
    const reason_kept = filterWaived(waivers.items, request.compilation.src, findings.items, reason_start, &waived, .err);
    findings.shrinkRetainingCapacity(reason_kept);

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
            if (finding.severity != .err) continue;
            finding.severity = .warning;
            accepted += 1;
        }
    } else if (request.options.gate) {
        for (findings.items) |*finding| {
            if (finding.severity != .err) continue;
            if (!try baselineContains(scratch, request.io, root, finding.*)) continue;
            finding.severity = .warning;
            accepted += 1;
        }
    }
    var blocking: usize = 0;
    var reporting: usize = 0;
    for (findings.items) |*finding| {
        // Without `--gate` (or `on_build: "block"`) a block rule still only
        // reports; the severity is demoted here, after the store has seen it.
        if (finding.severity == .err and !force_block) finding.severity = .warning;
        if (finding.severity == .err) blocking += 1 else reporting += 1;
    }

    return .{
        .findings = findings.items,
        .blocking = blocking,
        .reporting = reporting,
        .waived = waived,
        .accepted = accepted,
    };
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
    return if (outcome.blocking > 0) blocked_status else clean_status;
}

/// Drop waived findings from `items[start..]` in place and set each survivor's
/// severity, counting one waiver per drop.
fn filterWaived(waivers: []const Waiver, src: source.Source, items: []Finding, start: usize, waived: *usize, severity: diagnostic.Severity) usize {
    var kept = start;
    for (items[start..]) |finding| {
        if (isWaived(waivers, finding, src)) {
            waived.* += 1;
            continue;
        }
        var kept_finding = finding;
        kept_finding.severity = severity;
        items[kept] = kept_finding;
        kept += 1;
    }
    return kept;
}

/// Row identity recorded in a baseline file: `<module>|<qualified>`.
fn baselineRow(scratch: std.mem.Allocator, finding: Finding) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(scratch, "{s}|{s}", .{ finding.subject.module, finding.subject.qualified });
}

/// Whether a rule may record accepted debt in a baseline store. Change-time
/// rules judge a diff, not the tree's standing state, so a stored row would
/// silence a later refusal that no reviewer ever saw; they are never adopted
/// and an existing row never suppresses them.
fn baselineEligible(rule: []const u8) bool {
    return !std.mem.eql(u8, rule, rule_change_without_test) and !std.mem.eql(u8, rule, rule_noalloc_allocates);
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
            if (finding.severity != .err) continue;
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
};

/// True when a waiver on the line above `finding`'s declaration covers it.
pub fn isWaived(waivers: []const Waiver, finding: Finding, src: source.Source) bool {
    const span = if (std.mem.eql(u8, finding.rule, rule_noalloc_allocates) and finding.related != null) finding.related.?.span else finding.span;
    const line = src.physicalLocation(span.start).line;
    for (waivers) |waiver| {
        if (waiver.line + 1 == line and std.mem.eql(u8, waiver.rule, finding.rule)) return true;
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
        const parsed = try parseWaiver(scratch, comment, at, src.locate(at).line);
        if (parsed) |waiver| try waivers.append(scratch, waiver);
    }
}

fn parseWaiver(scratch: std.mem.Allocator, comment: []const u8, offset: usize, line: usize) std.mem.Allocator.Error!?Waiver {
    const after = std.mem.trim(u8, comment["# lint:".len..], " \t");
    if (!std.mem.startsWith(u8, after, "allow")) return null;
    const rest = std.mem.trim(u8, after["allow".len..], " \t");
    const space = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    const rule = rest[0..space];
    if (rule.len == 0) return null;
    const has_reason = std.mem.indexOf(u8, rest, "reason=\"") != null or std.mem.indexOf(u8, rest, "reason='") != null;
    return .{
        .rule = try scratch.dupe(u8, rule),
        .line = line,
        .has_reason = has_reason,
        .span = .{ .start = offset, .end = offset + comment.len },
    };
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
                .has_reason = attribute.reason != null,
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
fn renderFindings(request: Request, findings: []const Finding) !void {
    const format: diagnostic_output.Format = if (request.options.json) .json else request.diagnostics;
    for (findings) |finding| {
        const rendered = try diagnostic_output.render(request.memory, .{
            .code = finding.code,
            .severity = finding.severity,
            .span = finding.span,
            .message = finding.message,
            .related = finding.related,
        }, request.compilation.src, format);
        defer request.memory.free(rendered);
        try std.Io.File.stderr().writeStreamingAll(request.io, rendered);
    }
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
        std.mem.eql(u8, name, "__mylang_entry");
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

/// W2 `dead-private`: a private declaration with no call site anywhere in the
/// checked program is a leftover from a repair loop.
fn runDeadPrivate(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    for (facts.program.functions, 0..) |function, index| {
        const id: typed.FunctionId = @fromBackingInt(@intCast(index));
        if (id == facts.program.main) continue;
        if (facts.isExport(id)) continue;
        if (isSyntheticOrEntry(function.name)) continue;
        if (facts.functions[index].incoming_sites != 0) continue;
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
        try appendBudgetFinding(context, rule_parameters, "L_PARAMETERS", function, measured, limit);
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
    for (facts.program.functions, 0..) |function, index| {
        const id: typed.FunctionId = @fromBackingInt(@intCast(index));
        if (!facts.isExport(id)) continue;
        if (facts.isTest(id)) continue;
        if (isSyntheticOrEntry(function.name)) continue;
        if (facts.functions[index].incoming_sites != 0) continue;
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
    try appendUndocumentedExports(context.memory, context.index, min_chars, context.findings);
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
        for (unit.symbols.items) |symbol| {
            // A facade re-export declares nothing; its defining module is checked.
            if (!symbol.exported or symbol.re_export != null) continue;
            if (!documentable(unit, symbol)) continue;
            if (isSyntheticOrEntry(symbol.name)) continue;
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

/// Whether an exported symbol is a declaration this rule documents: a function,
/// or a record, union/result or domain type.
fn documentable(unit: interfaces.Unit, symbol: interfaces.Symbol) bool {
    if (symbol.kind == .function) return true;
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
/// call graph and inversion `mylang tests-for` performs, so this run and that
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
    for (program.functions) |function| {
        if (isSyntheticOrEntry(function.name)) continue;
        const local = localName(function.name);
        // A domain method's checked name is `Domain.method`; only the method
        // part is subject to the function casing rule.
        const checked = if (std.mem.lastIndexOfScalar(u8, local, '.')) |at| local[at + 1 ..] else local;
        if (!snakeCase(checked) or vagueName(checked)) try appendNamingFinding(context, "function", checked, function.declaration, function.name);
        const count = @min(function.signature.parameter_count, function.scope.locals.len);
        for (function.scope.locals[0..count]) |parameter| {
            if (snakeCase(parameter.name) and !vagueName(parameter.name)) continue;
            try appendNamingFinding(context, "parameter", parameter.name, parameter.declaration, function.name);
        }
        for (function.scope.locals[count..]) |binding| {
            if (binding.usage.temporary) continue;
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
        const message = try std.fmt.allocPrint(context.memory, "{s}: {s} takes adjacent parameters of type {s}", .{ rule_same_type_adjacent_params, function.name, typed.typeName(ty, program.records) });
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

/// Section 9 `output-in-library`: report a function whose inferred effects
/// include `output` in a module outside the rule's `modules` allow-list.
fn runOutputInLibrary(context: *RuleContext) std.mem.Allocator.Error!void {
    const output_bit = effect_set.bit(.output);
    for (context.facts.program.functions) |function| {
        if (function.policy.effects & output_bit == 0) continue;
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
/// finding names the `Option[int]` rewrite.
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
/// negative literal, naming the callee and the `Option[int]` rewrite.
fn reportSentinelComparison(context: *RuleContext, program: typed.Program, callee: typed.FunctionId, span: source.Span) std.mem.Allocator.Error!void {
    const sentinel = program.functions[@backingInt(callee)];
    const message = try std.fmt.allocPrint(context.memory, "`{s}` returns -1 on one path and its result is tested against a negative literal here; return `Option[int]` and test `is None` or use `unwrap_or`", .{localName(sentinel.name)});
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
                .description = try std.fmt.allocPrint(context.memory, "field `{s}` of `{s}`", .{ record.fields[field.index].name, localName(record.name) }),
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
                .description = try std.fmt.allocPrint(context.memory, "parameter `{s}` of `{s}`", .{ function.scope.locals[slot].name, localName(function.name) }),
                .qualified = function.name,
                .module = moduleName(function.name),
                .span = node.span,
            });
        },
        else => {},
    }
}

/// Report one finding per parameter or field compared against `-1` in two or
/// more places, naming the subject and the `Option[int]` rewrite.
fn reportMinusOneSites(context: *RuleContext, sites: []MinusOneSite) std.mem.Allocator.Error!void {
    std.mem.sort(MinusOneSite, sites, {}, minusOneLessThan);
    var start: usize = 0;
    while (start < sites.len) {
        var end = start + 1;
        while (end < sites.len and std.mem.eql(u8, sites[start].key, sites[end].key)) end += 1;
        if (end - start >= 2) {
            const site = sites[end - 1];
            const message = try std.fmt.allocPrint(context.memory, "{s} is compared against -1 in {d} places; declare it `Option[int]` and test `is None` or use `unwrap_or`", .{ site.description, end - start });
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

/// Report every declared effect clause that permits exactly what the function's
/// own parameter list already implies. Such a clause says nothing, so under
/// `--profile=strict` it is the same finding the checker warns about, and
/// removing it is the whole fix.
fn runDerivedEffects(context: *RuleContext) std.mem.Allocator.Error!void {
    const facts = context.facts;
    const derived_effects = @import("effects.zig");
    for (facts.program.functions) |function| {
        if (function.policy.host != null or function.policy.c_abi) continue;
        const bound = function.policy.effect_bound orelse continue;
        if (!derived_effects.writtenClause(facts.src, bound.span) or effect_set.coreAllocationBound(facts.src, bound)) continue;
        const derived = derived_effects.derivedCeiling(facts.program.records, function);
        if (derived & ~bound.allowed != 0) continue;
        if (!derived_effects.negativeClause(facts.src, bound.span) and bound.allowed & ~derived != 0) continue;
        const clause = facts.src.text(bound.span);
        const message = try std.fmt.allocPrint(context.memory, "`{s}` is exactly what the parameters imply; remove it", .{clause});
        try context.findings.append(context.memory, .{
            .code = "W_DERIVED_EFFECTS",
            .rule = rule_derived_effects,
            .span = bound.span,
            .message = message,
            .subject = .{ .module = moduleName(function.name), .qualified = function.name },
        });
    }
}

/// Convert Core warnings into findings so profile modes, waivers and gate status agree.
fn runNoallocAllocates(context: *RuleContext) std.mem.Allocator.Error!void {
    for (context.facts.diagnostics) |item| {
        if (!std.mem.eql(u8, item.code, "W_NOALLOC_ALLOCATES")) continue;
        var subject: Subject = .{};
        if (item.related) |related| for (context.facts.program.functions) |function| {
            const bound = function.policy.effect_bound orelse continue;
            if (bound.span.start != related.span.start) continue;
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
