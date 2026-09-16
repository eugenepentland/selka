//! Wave-3 invalidation observability: compare two `project-dependencies-v1`
//! receipts stage by stage and explain which input invalidated each query.
//!
//! The `incremental` object is deliberately treated as opaque JSON.  Receipts
//! produced by an older compiler (v1 identities) and a newer one (v2) both
//! compare through the same extraction rules: unknown additions are ignored,
//! absent fields are tolerated, and a missing or unreadable baseline degrades
//! to "everything missed" instead of failing the command that asked for the
//! explanation.
const std = @import("std");

/// Failure modes of the comparison layer.  A bad `current` receipt is the only
/// input that is allowed to fail the caller; a bad baseline never does.
pub const Error = error{ OutOfMemory, InvalidCurrent };

// Receipt field names shared by fingerprints, first-changed reports and
// toolchain extraction.  Keeping them here avoids ambiguous repeated literals.
const compiler_sha256_field = "compiler_sha256";
const architecture_field = "architecture";
const os_field = "os";
const abi_field = "abi";
const zig_version_field = "zig_version";
const optimize_field = "optimize";
const runtime_abi_field = "runtime_abi";
const target_field = "target";
const identity_field = "identity";
const function_declaration_kind = "function";
const specializations_field = "specializations";
const fragments_field = "fragments";
const fragment_label = "fragment";
const compiler_label = "compiler";
const module_label = "module:";
const module_prefix = "module:{s}";

/// The nine query stages named in the Wave-3 plan, in canonical report order.
pub const Stage = enum {
    load_source,
    lex_parse,
    collect_declarations,
    resolve_interface,
    check_body,
    instantiate_specialization,
    lower_function,
    emit_fragment,
    link,
};

/// Stable display name for one stage; the enum tag is the contract.
pub fn stageName(stage: Stage) []const u8 {
    return @tagName(stage);
}

/// Whether a query was satisfied by the baseline, had to miss, or did not run
/// for this command at all. Skipped stages are never reported as reuse.
pub const Status = enum { hit, miss, skipped };

/// One stage's outcome.  `key` is a canonical shortened digest of the query
/// input; `first_changed` is owned only on a miss.
pub const Query = struct {
    stage: Stage,
    status: Status,
    key: []const u8,
    first_changed: ?[]const u8 = null,
};

/// Complete result of comparing a baseline receipt with the current receipt.
pub const Explanation = struct {
    queries: []const Query,
    hits: usize,
    misses: usize,
    /// Stages that the current command did not execute; never counted as reuse.
    skipped: usize,

    /// Free every string and slice allocated by `explain`.
    pub fn deinit(self: Explanation, allocator: std.mem.Allocator) void {
        for (self.queries) |query| {
            allocator.free(query.key);
            if (query.first_changed) |name| allocator.free(name);
        }
        allocator.free(self.queries);
    }
};

/// Parse and compare two complete receipt documents.
///
/// `previous == null` makes every stage miss with `first_changed` equal to
/// `"no-baseline"`; an unparsable baseline makes every stage miss with
/// `"corrupt-baseline"`.  Only an unparsable `current` returns an error.
pub fn explain(allocator: std.mem.Allocator, previous: ?[]const u8, current: []const u8, executed: []const bool) Error!Explanation {
    var arena_state = std.heap.ArenaAllocator.init(allocator);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    const current_value = std.json.parseFromSliceLeaky(std.json.Value, arena, current, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidCurrent,
    };
    if (!validReceipt(current_value)) return error.InvalidCurrent;

    if (previous == null) return allMiss(allocator, "no-baseline", executed);

    const previous_value = std.json.parseFromSliceLeaky(std.json.Value, arena, previous.?, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return allMiss(allocator, "corrupt-baseline", executed),
    };
    if (!validReceipt(previous_value)) return allMiss(allocator, "corrupt-baseline", executed);

    const stages = std.meta.tags(Stage);
    const queries = try allocator.alloc(Query, stages.len);
    var filled: usize = 0;
    var hits: usize = 0;
    var misses: usize = 0;
    var skipped: usize = 0;
    errdefer {
        for (queries[0..filled]) |query| {
            allocator.free(query.key);
            if (query.first_changed) |name| allocator.free(name);
        }
        allocator.free(queries);
    }

    for (stages, 0..) |stage, index| {
        const ran = index < executed.len and executed[index];
        if (!ran) {
            const key = try allocator.dupe(u8, stageName(stage));
            queries[index] = .{ .stage = stage, .status = .skipped, .key = key, .first_changed = null };
            skipped += 1;
            filled = index + 1;
            continue;
        }
        const outcome = try compareStage(arena, stage, previous_value, current_value);
        const key = try allocator.dupe(u8, outcome.key);
        errdefer allocator.free(key);
        const first_changed = if (outcome.first_changed) |name| try allocator.dupe(u8, name) else null;
        switch (outcome.status) {
            .hit => hits += 1,
            .miss => misses += 1,
            .skipped => skipped += 1,
        }
        queries[index] = .{ .stage = stage, .status = outcome.status, .key = key, .first_changed = first_changed };
        filled = index + 1;
    }

    return .{ .queries = queries, .hits = hits, .misses = misses, .skipped = skipped };
}

/// Render one `invalidation-report-v1` JSON object (no trailing newline).
pub fn render(allocator: std.mem.Allocator, explanation: Explanation) Error![]u8 {
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "invalidation-report-v1",
        .hits = explanation.hits,
        .misses = explanation.misses,
        .skipped = explanation.skipped,
        .queries = explanation.queries,
    }, .{ .emit_null_optional_fields = false });
}

// ---------------------------------------------------------------------------
// work-report-v1: actual observed work, independent of fingerprint comparison.
//
// The nine `Stage` queries above compare a baseline receipt with the current
// receipt. Their `hit` status only means "the compared input digest is equal";
// it does not establish that the command reused anything. The seven work stages
// below are counted where the command actually executes or actually reuses
// something, so they can separate a forced fresh check with equal fingerprints
// (`fingerprint_unchanged == true`, `checked_bodies.performed > 0`) from a
// command answered by a real cache hit (`reused > 0`).
// ---------------------------------------------------------------------------

/// Actual-work stages. These are independent of the nine fingerprint comparison
/// stages: a command can skip one entirely, or perform one even when the
/// corresponding fingerprint is unchanged.
pub const WorkStage = enum {
    parsed_modules,
    checked_bodies,
    instantiated_specializations,
    lowered_functions,
    emitted_fragments,
    links,
    executed_tests,
};

pub const work_stage_count = std.meta.tags(WorkStage).len;

/// One work stage's observed executions and true reuse. `executed == false`
/// renders as `skipped` and is never counted as reuse.
pub const StageCount = struct {
    performed: usize = 0,
    reused: usize = 0,
    executed: bool = false,
};

/// A disabled or refused optimization and why. `reason` is a static tag; the
/// value is copied into the report, never derived from a digest comparison.
pub const Bypass = struct { reason: []const u8 = "", count: usize = 0 };

/// Observation of actual work for one invocation plus optional cumulative
/// process counters. `fingerprint_unchanged` is the comparison result and is
/// deliberately distinct from `reused`, which only becomes true when a lookup
/// actually returned a stored result.
pub const Work = struct {
    /// Actual reuse observations not tied to one stage (for example a replayed
    /// whole-project verdict). Never inferred from equal fingerprints.
    pub const Results = struct { request: usize = 0, session: usize = 0 };
    /// C3 symbolic-template direct results actually checked and replayed. Kept
    /// separate from `checked_bodies` so a template hit is never inferred from a
    /// fingerprint comparison.
    pub const Symbolic = struct { checked: usize = 0, reused: usize = 0 };
    /// C3 concrete-specialization bodies actually checked fresh and actually
    /// replayed. Kept separate from the checked-program instantiation count and
    /// from `checked_bodies` so a replay is never inferred from a fingerprint.
    pub const Specializations = struct { checked: usize = 0, reused: usize = 0 };
    /// C3 work grouped into one record so the observation stays within the
    /// struct field budget as more C3 counters are added.
    pub const Counters = struct { symbolic: Symbolic = .{}, specializations: Specializations = .{} };

    command: []const u8 = "",
    /// Null when this invocation ran no baseline comparison.
    fingerprint_unchanged: ?bool = null,
    results: Results = .{},
    counters: Counters = .{},
    stages: [work_stage_count]StageCount = @splat(.{}),
    /// Cumulative process counters. Null means this is a one-shot invocation and
    /// the request counters are already the whole-process totals.
    session: ?[work_stage_count]StageCount = null,
    bypassed: BypassSet = .{},

    /// Borrow the mutable counter for one stage.
    pub fn stage(self: *Work, which: WorkStage) *StageCount {
        return &self.stages[@backingInt(which)];
    }
    /// Count executions/reuse for one stage without replacing earlier counts.
    pub fn note(self: *Work, which: WorkStage, performed: usize, reuse_count: usize) void {
        const count = self.stage(which);
        count.executed = true;
        count.performed += performed;
        count.reused += reuse_count;
    }
    /// Record a whole-stage result (lowering, emission and linking run at most
    /// once per command, so their counts are replaced rather than accumulated).
    pub fn set(self: *Work, which: WorkStage, performed: usize, reuse_count: usize) void {
        const count = self.stage(which);
        count.executed = true;
        count.performed = performed;
        count.reused = reuse_count;
    }
    /// Mark a stage as not reached by this command.
    pub fn skip(self: *Work, which: WorkStage) void {
        self.stages[@backingInt(which)] = .{};
    }
    /// Record a bypass with its reason, ignoring zero counts and overflow.
    pub fn addBypass(self: *Work, reason: []const u8, count: usize) void {
        self.bypassed.add(reason, count);
    }
    /// Whether any actual reuse was observed. `fingerprint_unchanged` must not
    /// influence this result.
    pub fn reused(self: Work) bool {
        for (self.stages) |count| if (count.reused != 0) return true;
        return self.results.request != 0;
    }
    /// Work-stage status: skipped when the command never reached it, hit only
    /// when reuse happened and no fresh work did, miss otherwise.
    pub fn status(self: Work, which: WorkStage) Status {
        const count = self.stages[@backingInt(which)];
        if (!count.executed) return .skipped;
        if (count.performed == 0 and count.reused != 0) return .hit;
        return .miss;
    }
};

/// A bounded, reason-tagged bypass list carried inline by `Work`.
pub const BypassSet = struct {
    items: [8]Bypass = @splat(.{}),
    len: usize = 0,

    /// Append one bypass reason; zero counts and overflow are ignored.
    pub fn add(self: *BypassSet, reason: []const u8, count: usize) void {
        if (count == 0 or self.len == self.items.len) return;
        self.items[self.len] = .{ .reason = reason, .count = count };
        self.len += 1;
    }
    /// Borrow the populated prefix of the list.
    pub fn slice(self: *const BypassSet) []const Bypass {
        return self.items[0..self.len];
    }
};

const StageView = struct { status: []const u8, performed: usize, reused: usize };
/// Public performed/reused counters for one work stage.
pub const CountView = struct { performed: usize = 0, reused: usize = 0 };
/// Public per-stage counters for one request or one cumulative session.
pub const SessionView = struct {
    parsed_modules: CountView = .{},
    checked_bodies: CountView = .{},
    instantiated_specializations: CountView = .{},
    lowered_functions: CountView = .{},
    emitted_fragments: CountView = .{},
    links: CountView = .{},
    executed_tests: CountView = .{},
};

/// Compact request/session view of a work observation, used by the
/// `check-session` protocol. `request` is this invocation's deltas; `session` is
/// the cumulative process totals (from `Work.session` when present).
pub const Summary = struct {
    fingerprint_unchanged: ?bool = null,
    reused: bool = false,
    request: SessionView,
    session: SessionView,
    request_reused_results: usize = 0,
    session_reused_results: usize = 0,
    bypassed: []const Bypass = &.{},
};

/// Summarize a work observation into request deltas and session totals.
pub fn summarize(work: *const Work) Summary {
    const cumulative = work.session orelse work.stages;
    return .{
        .fingerprint_unchanged = work.fingerprint_unchanged,
        .reused = work.reused(),
        .request = sessionView(work.stages),
        .session = sessionView(cumulative),
        .request_reused_results = work.results.request,
        .session_reused_results = if (work.session == null) work.results.request else work.results.session,
        .bypassed = work.bypassed.slice(),
    };
}

fn stageView(work: Work, which: WorkStage) StageView {
    const count = work.stages[@backingInt(which)];
    return .{ .status = @tagName(work.status(which)), .performed = count.performed, .reused = count.reused };
}

fn countView(stages: [work_stage_count]StageCount, which: WorkStage) CountView {
    const count = stages[@backingInt(which)];
    return .{ .performed = count.performed, .reused = count.reused };
}

fn sessionView(stages: [work_stage_count]StageCount) SessionView {
    return .{
        .parsed_modules = countView(stages, .parsed_modules),
        .checked_bodies = countView(stages, .checked_bodies),
        .instantiated_specializations = countView(stages, .instantiated_specializations),
        .lowered_functions = countView(stages, .lowered_functions),
        .emitted_fragments = countView(stages, .emitted_fragments),
        .links = countView(stages, .links),
        .executed_tests = countView(stages, .executed_tests),
    };
}

/// Render one `work-report-v1` JSON object (no trailing newline). Top-level
/// stage objects describe this invocation; `session` carries the cumulative
/// process totals (identical to the request for a one-shot process).
pub fn renderWork(allocator: std.mem.Allocator, work: Work) Error![]u8 {
    const cumulative = work.session orelse work.stages;
    const session_reused = if (work.session == null) work.results.request else work.results.session;
    return std.json.Stringify.valueAlloc(allocator, .{
        .version = "work-report-v1",
        .command = work.command,
        .fingerprint_unchanged = work.fingerprint_unchanged,
        .reused = work.reused(),
        .parsed_modules = stageView(work, .parsed_modules),
        .checked_bodies = stageView(work, .checked_bodies),
        .instantiated_specializations = stageView(work, .instantiated_specializations),
        .lowered_functions = stageView(work, .lowered_functions),
        .emitted_fragments = stageView(work, .emitted_fragments),
        .links = stageView(work, .links),
        .executed_tests = stageView(work, .executed_tests),
        .reused_results = work.results.request,
        .session_reused_results = session_reused,
        .symbolic_templates = symbolicView(work),
        .specialization_bodies = specializationView(work),
        .bypassed = work.bypassed.slice(),
        .session = sessionView(cumulative),
    }, .{ .emit_null_optional_fields = false });
}

/// Per-request view of C3 symbolic-template work. `skipped` means the abstract
/// pass never ran; `hit` means every visited template was replayed.
fn symbolicView(work: Work) StageView {
    const performed = work.counters.symbolic.checked;
    const reused = work.counters.symbolic.reused;
    return .{
        .status = if (performed == 0 and reused == 0)
            "skipped"
        else if (performed == 0)
            "hit"
        else
            "miss",
        .performed = performed,
        .reused = reused,
    };
}

/// Per-request view of concrete-specialization body work. `skipped` means no
/// specialization was visited; `hit` means every visited specialization was
/// replayed; a replay is never inferred from an unchanged fingerprint.
fn specializationView(work: Work) StageView {
    const performed = work.counters.specializations.checked;
    const reused = work.counters.specializations.reused;
    return .{
        .status = if (performed == 0 and reused == 0)
            "skipped"
        else if (performed == 0)
            "hit"
        else
            "miss",
        .performed = performed,
        .reused = reused,
    };
}

fn allMiss(allocator: std.mem.Allocator, reason: []const u8, executed: []const bool) Error!Explanation {
    const stages = std.meta.tags(Stage);
    const queries = try allocator.alloc(Query, stages.len);
    var filled: usize = 0;
    var misses: usize = 0;
    var skipped: usize = 0;
    errdefer {
        for (queries[0..filled]) |query| {
            allocator.free(query.key);
            if (query.first_changed) |name| allocator.free(name);
        }
        allocator.free(queries);
    }
    for (stages, 0..) |stage, index| {
        const ran = index < executed.len and executed[index];
        const key = try allocator.dupe(u8, stageName(stage));
        errdefer allocator.free(key);
        if (!ran) {
            queries[index] = .{ .stage = stage, .status = .skipped, .key = key, .first_changed = null };
            skipped += 1;
        } else {
            const first_changed = try allocator.dupe(u8, reason);
            queries[index] = .{ .stage = stage, .status = .miss, .key = key, .first_changed = first_changed };
            misses += 1;
        }
        filled = index + 1;
    }
    return .{ .queries = queries, .hits = 0, .misses = misses, .skipped = skipped };
}

/// Validate the receipt shape before comparing. A syntactically valid `{}` is
/// not a baseline: it must name the version, carry an implementation identity,
/// an inputs array and an incremental module table.
fn validReceipt(root: std.json.Value) bool {
    if (root != .object) return false;
    const version = stringOf(member(root, "version")) orelse return false;
    if (!std.mem.eql(u8, version, "project-dependencies-v1")) return false;
    const implementation = implementationOf(root) orelse return false;
    if (stringOf(objectMember(implementation, compiler_sha256_field)) == null) return false;
    switch (member(root, "inputs") orelse return false) {
        .array => {},
        else => return false,
    }
    const incremental = incrementalOf(root) orelse return false;
    switch (objectMember(incremental, "modules") orelse return false) {
        .array => {},
        else => return false,
    }
    return true;
}

const Outcome = struct { status: Status, key: []const u8, first_changed: ?[]const u8 };
const Fingerprint = struct { key: []const u8, present: bool };
const Component = struct { name: []const u8, value: []const u8 };

fn compareStage(arena: std.mem.Allocator, stage: Stage, previous: std.json.Value, current: std.json.Value) !Outcome {
    return switch (stage) {
        .load_source => compareWith(arena, previous, current, loadSourceFingerprint, loadSourceFirstChanged),
        .lex_parse => compareWith(arena, previous, current, lexParseFingerprint, lexParseFirstChanged),
        .collect_declarations => compareWith(arena, previous, current, collectDeclarationsFingerprint, collectDeclarationsFirstChanged),
        .resolve_interface => compareWith(arena, previous, current, resolveInterfaceFingerprint, resolveInterfaceFirstChanged),
        .check_body => compareWith(arena, previous, current, checkBodyFingerprint, checkBodyFirstChanged),
        .instantiate_specialization => compareWith(arena, previous, current, specializationFingerprint, specializationFirstChanged),
        .lower_function => compareWith(arena, previous, current, lowerFunctionFingerprint, lowerFunctionFirstChanged),
        .emit_fragment => compareWith(arena, previous, current, fragmentFingerprint, fragmentFirstChanged),
        .link => compareWith(arena, previous, current, linkFingerprint, linkFirstChanged),
    };
}

fn compareWith(
    arena: std.mem.Allocator,
    previous: std.json.Value,
    current: std.json.Value,
    comptime fingerprint: anytype,
    comptime firstChanged: anytype,
) !Outcome {
    const prior = try fingerprint(arena, previous);
    const next = try fingerprint(arena, current);
    if (!prior.present and !next.present) return .{ .status = .hit, .key = "", .first_changed = null };
    if (prior.present and next.present and std.mem.eql(u8, prior.key, next.key)) return .{ .status = .hit, .key = next.key, .first_changed = null };
    if (!prior.present or !next.present) return .{ .status = .miss, .key = next.key, .first_changed = "absent" };
    const reason = try firstChanged(arena, previous, current);
    return .{ .status = .miss, .key = next.key, .first_changed = reason };
}

const FingerprintBuilder = struct {
    hash: std.crypto.hash.sha2.Sha256,
    present: bool = false,

    fn init() FingerprintBuilder {
        return .{ .hash = std.crypto.hash.sha2.Sha256.init(.{}) };
    }
    fn markPresent(self: *FingerprintBuilder) void {
        self.present = true;
    }
    fn field(self: *FingerprintBuilder, tag: []const u8, value: []const u8) void {
        updateField(&self.hash, tag, value);
    }
    fn finish(self: *FingerprintBuilder, arena: std.mem.Allocator) std.mem.Allocator.Error![]const u8 {
        if (!self.present) return "";
        var digest: [32]u8 = undefined;
        self.hash.final(&digest);
        return std.fmt.allocPrint(arena, "{s}", .{std.fmt.bytesToHex(digest, .lower)});
    }
};

fn updateField(hash: *std.crypto.hash.sha2.Sha256, tag: []const u8, value: []const u8) void {
    hash.update(tag);
    hash.update(&.{0});
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, @intCast(value.len), .little);
    hash.update(&length);
    hash.update(value);
}

fn componentLess(_: void, a: Component, b: Component) bool {
    if (!std.mem.eql(u8, a.name, b.name)) return std.mem.lessThan(u8, a.name, b.name);
    return std.mem.lessThan(u8, a.value, b.value);
}

fn sortComponents(components: []Component) void {
    std.mem.sort(Component, components, {}, componentLess);
}

fn firstChangedComponent(previous: []const Component, current: []const Component) ?[]const u8 {
    var left: usize = 0;
    var right: usize = 0;
    while (left < previous.len and right < current.len) {
        const a = previous[left];
        const b = current[right];
        if (!std.mem.eql(u8, a.name, b.name)) {
            return if (std.mem.lessThan(u8, a.name, b.name)) a.name else b.name;
        }
        if (!std.mem.eql(u8, a.value, b.value)) return a.name;
        left += 1;
        right += 1;
    }
    if (left < previous.len) return previous[left].name;
    if (right < current.len) return current[right].name;
    return null;
}

fn member(value: std.json.Value, name: []const u8) ?std.json.Value {
    return switch (value) {
        .object => |object| object.get(name),
        else => null,
    };
}

fn objectMember(object: std.json.ObjectMap, name: []const u8) ?std.json.Value {
    return object.get(name);
}

fn objectOf(value: ?std.json.Value) ?std.json.ObjectMap {
    const inner = value orelse return null;
    return switch (inner) {
        .object => |object| object,
        else => null,
    };
}

fn stringOf(value: ?std.json.Value) ?[]const u8 {
    const inner = value orelse return null;
    return switch (inner) {
        .string => |text| text,
        else => null,
    };
}

fn arrayOf(value: ?std.json.Value) []const std.json.Value {
    const inner = value orelse return &.{};
    return switch (inner) {
        .array => |array| array.items,
        else => &.{},
    };
}

fn implementationOf(root: std.json.Value) ?std.json.ObjectMap {
    return objectOf(member(root, "implementation"));
}

fn incrementalOf(root: std.json.Value) ?std.json.ObjectMap {
    return objectOf(member(root, "incremental"));
}

fn modulesOf(root: std.json.Value) []const std.json.Value {
    const incremental = incrementalOf(root) orelse return &.{};
    return arrayOf(objectMember(incremental, "modules"));
}

fn scalarText(arena: std.mem.Allocator, value: std.json.Value) std.mem.Allocator.Error![]const u8 {
    return switch (value) {
        .string => |text| text,
        .integer => |number| try std.fmt.allocPrint(arena, "{d}", .{number}),
        .float => |number| try std.fmt.allocPrint(arena, "{d}", .{number}),
        .bool => |flag| if (flag) "true" else "false",
        .null => "",
        .number_string => |text| text,
        .array, .object => try std.json.Stringify.valueAlloc(arena, value, .{}),
    };
}

fn scalarTextOrEmpty(arena: std.mem.Allocator, value: ?std.json.Value) std.mem.Allocator.Error![]const u8 {
    const inner = value orelse return "";
    return scalarText(arena, inner);
}

fn optionalText(value: std.json.Value, name: []const u8) []const u8 {
    const inner = member(value, name) orelse return "";
    return switch (inner) {
        .null => "",
        .string => |text| text,
        else => "",
    };
}

fn elementName(arena: std.mem.Allocator, value: std.json.Value) std.mem.Allocator.Error![]const u8 {
    switch (value) {
        .string => |text| return text,
        .object => |object| {
            if (object.get("name")) |name| switch (name) {
                .string => |text| return text,
                else => {},
            };
        },
        else => {},
    }
    const rendered = try std.json.Stringify.valueAlloc(arena, value, .{});
    return rendered;
}

fn inputShaComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    const inputs = arrayOf(member(root, "inputs"));
    const components = try arena.alloc(Component, inputs.len);
    for (inputs, 0..) |input, index| {
        components[index] = .{
            .name = stringOf(member(input, "module")) orelse "",
            .value = stringOf(member(input, "sha256")) orelse "",
        };
    }
    sortComponents(components);
    return components;
}

fn inputPathComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    const inputs = arrayOf(member(root, "inputs"));
    const components = try arena.alloc(Component, inputs.len);
    for (inputs, 0..) |input, index| {
        const path = stringOf(member(input, "path")) orelse "";
        const sha = stringOf(member(input, "sha256")) orelse "";
        components[index] = .{
            .name = stringOf(member(input, "module")) orelse "",
            .value = try std.fmt.allocPrint(arena, "{s}\x1f{s}", .{ path, sha }),
        };
    }
    sortComponents(components);
    return components;
}

fn moduleComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    const modules = modulesOf(root);
    const components = try arena.alloc(Component, modules.len);
    for (modules, 0..) |module, index| {
        components[index] = .{
            .name = stringOf(member(module, "name")) orelse "",
            .value = stringOf(member(module, identity_field)) orelse "",
        };
    }
    sortComponents(components);
    return components;
}

fn bodyComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    var components: std.ArrayList(Component) = .empty;
    for (modulesOf(root)) |module| {
        const module_name = stringOf(member(module, "name")) orelse "";
        for (arrayOf(member(module, "declarations"))) |declaration| {
            const body = member(declaration, "body_sha256") orelse continue;
            switch (body) {
                .null => continue,
                else => {},
            }
            const declaration_name = stringOf(member(declaration, "name")) orelse "";
            try components.append(arena, .{
                .name = try std.fmt.allocPrint(arena, "{s}::{s}", .{ module_name, declaration_name }),
                .value = try scalarText(arena, body),
            });
        }
    }
    const slice = try components.toOwnedSlice(arena);
    sortComponents(slice);
    return slice;
}

fn functionComponents(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error![]const Component {
    var components: std.ArrayList(Component) = .empty;
    for (modulesOf(root)) |module| {
        const module_name = stringOf(member(module, "name")) orelse "";
        for (arrayOf(member(module, "declarations"))) |declaration| {
            const kind = stringOf(member(declaration, "kind")) orelse "";
            if (!std.mem.eql(u8, kind, function_declaration_kind)) continue;
            try components.append(arena, .{
                .name = stringOf(member(declaration, "name")) orelse "",
                .value = try std.fmt.allocPrint(arena, "{s}\x1f{s}\x1f{s}\x1f{s}", .{
                    module_name,
                    stringOf(member(declaration, identity_field)) orelse "",
                    optionalText(declaration, "interface_sha256"),
                    optionalText(declaration, "body_sha256"),
                }),
            });
        }
    }
    const slice = try components.toOwnedSlice(arena);
    sortComponents(slice);
    return slice;
}

fn namedArrayComponents(arena: std.mem.Allocator, root: std.json.Value, comptime field_name: []const u8) std.mem.Allocator.Error![]const Component {
    const incremental = incrementalOf(root) orelse return &.{};
    const values = arrayOf(objectMember(incremental, field_name));
    var components: std.ArrayList(Component) = .empty;
    for (values) |value| {
        try components.append(arena, .{
            .name = try elementName(arena, value),
            .value = try std.json.Stringify.valueAlloc(arena, value, .{}),
        });
    }
    const slice = try components.toOwnedSlice(arena);
    sortComponents(slice);
    return slice;
}

fn loadSourceFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    if (implementationOf(root)) |implementation| {
        builder.markPresent();
        builder.field(compiler_sha256_field, try scalarTextOrEmpty(arena, objectMember(implementation, compiler_sha256_field)));
        builder.field(architecture_field, try scalarTextOrEmpty(arena, objectMember(implementation, architecture_field)));
        builder.field(os_field, try scalarTextOrEmpty(arena, objectMember(implementation, os_field)));
        builder.field(abi_field, try scalarTextOrEmpty(arena, objectMember(implementation, abi_field)));
    }
    const components = try inputShaComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("module", component.name);
        builder.field("sha256", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn loadSourceFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    if (!try sameCompilerIdentity(arena, previous, current)) return compiler_label;
    const changed = firstChangedComponent(try inputShaComponents(arena, previous), try inputShaComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return compiler_label;
}

fn lexParseFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try inputPathComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("module", component.name);
        builder.field("path_sha", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn lexParseFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try inputPathComponents(arena, previous), try inputPathComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return module_label;
}

fn collectDeclarationsFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try moduleComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("module", component.name);
        builder.field(identity_field, component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn collectDeclarationsFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try moduleComponents(arena, previous), try moduleComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return module_label;
}

fn resolveInterfaceFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    if (incrementalOf(root)) |incremental| {
        if (objectMember(incremental, "project_interface_sha256")) |value| {
            builder.markPresent();
            builder.field("interface", try scalarText(arena, value));
        }
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn resolveInterfaceFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    _ = arena;
    _ = previous;
    _ = current;
    return "interface";
}

fn checkBodyFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try bodyComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("declaration", component.name);
        builder.field("body", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn checkBodyFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try bodyComponents(arena, previous), try bodyComponents(arena, current));
    if (changed) |name| {
        const rendered = try std.fmt.allocPrint(arena, module_prefix, .{name});
        return rendered;
    }
    return module_label;
}

fn specializationFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try namedArrayComponents(arena, root, specializations_field);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field("specialization", component.name);
        builder.field("value", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn specializationFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try namedArrayComponents(arena, previous, specializations_field), try namedArrayComponents(arena, current, specializations_field));
    if (changed) |name| return name;
    return "specialization";
}

fn lowerFunctionFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try functionComponents(arena, root);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field(function_declaration_kind, component.name);
        builder.field(identity_field, component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn lowerFunctionFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try functionComponents(arena, previous), try functionComponents(arena, current));
    if (changed) |name| return name;
    return function_declaration_kind;
}

fn fragmentFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    const components = try namedArrayComponents(arena, root, fragments_field);
    if (components.len != 0) builder.markPresent();
    for (components) |component| {
        builder.field(fragment_label, component.name);
        builder.field("value", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn fragmentFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const changed = firstChangedComponent(try namedArrayComponents(arena, previous, fragments_field), try namedArrayComponents(arena, current, fragments_field));
    if (changed) |name| return name;
    return fragment_label;
}

const LinkField = struct { present: bool, text: []const u8 };

fn linkField(arena: std.mem.Allocator, root: std.json.Value, comptime name: []const u8) std.mem.Allocator.Error!LinkField {
    if (member(root, name)) |value| {
        switch (value) {
            .null => {},
            else => return .{ .present = true, .text = try scalarText(arena, value) },
        }
    }
    if (incrementalOf(root)) |incremental| {
        if (objectMember(incremental, name)) |value| {
            switch (value) {
                .null => {},
                else => return .{ .present = true, .text = try scalarText(arena, value) },
            }
        }
    }
    return .{ .present = false, .text = "" };
}

fn linkFingerprint(arena: std.mem.Allocator, root: std.json.Value) std.mem.Allocator.Error!Fingerprint {
    var builder = FingerprintBuilder.init();
    if (implementationOf(root)) |implementation| {
        builder.markPresent();
        builder.field(compiler_sha256_field, try scalarTextOrEmpty(arena, objectMember(implementation, compiler_sha256_field)));
        builder.field(zig_version_field, try scalarTextOrEmpty(arena, objectMember(implementation, zig_version_field)));
        builder.field(architecture_field, try scalarTextOrEmpty(arena, objectMember(implementation, architecture_field)));
        builder.field(os_field, try scalarTextOrEmpty(arena, objectMember(implementation, os_field)));
        builder.field(abi_field, try scalarTextOrEmpty(arena, objectMember(implementation, abi_field)));
        builder.field(optimize_field, try scalarTextOrEmpty(arena, objectMember(implementation, optimize_field)));
    }
    const runtime_abi = try linkField(arena, root, runtime_abi_field);
    const target = try linkField(arena, root, target_field);
    if (runtime_abi.present or target.present) builder.markPresent();
    builder.field(runtime_abi_field, runtime_abi.text);
    builder.field(target_field, target.text);
    // Linking consumes the emitted fragments, so a changed fragment invalidates it.
    const fragments = try namedArrayComponents(arena, root, fragments_field);
    if (fragments.len != 0) builder.markPresent();
    for (fragments) |component| {
        builder.field(fragment_label, component.name);
        builder.field("value", component.value);
    }
    return .{ .key = try builder.finish(arena), .present = builder.present };
}

fn linkFirstChanged(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error![]const u8 {
    const previous_implementation = implementationOf(previous);
    const current_implementation = implementationOf(current);
    const previous_compiler = try scalarTextOrEmpty(arena, if (previous_implementation) |implementation| objectMember(implementation, compiler_sha256_field) else null);
    const current_compiler = try scalarTextOrEmpty(arena, if (current_implementation) |implementation| objectMember(implementation, compiler_sha256_field) else null);
    if (!std.mem.eql(u8, previous_compiler, current_compiler)) return compiler_label;

    const previous_runtime = try linkField(arena, previous, runtime_abi_field);
    const current_runtime = try linkField(arena, current, runtime_abi_field);
    if (!std.mem.eql(u8, previous_runtime.text, current_runtime.text)) return "runtime-abi";

    const previous_target = try linkField(arena, previous, target_field);
    const current_target = try linkField(arena, current, target_field);
    if (!std.mem.eql(u8, previous_target.text, current_target.text)) return target_field;

    const changed_fragment = firstChangedComponent(
        try namedArrayComponents(arena, previous, fragments_field),
        try namedArrayComponents(arena, current, fragments_field),
    );
    if (changed_fragment) |name| return name;

    return "toolchain";
}

fn sameCompilerIdentity(arena: std.mem.Allocator, previous: std.json.Value, current: std.json.Value) std.mem.Allocator.Error!bool {
    const previous_implementation = implementationOf(previous);
    const current_implementation = implementationOf(current);
    inline for (.{ compiler_sha256_field, architecture_field, os_field, abi_field }) |name| {
        const prior = try scalarTextOrEmpty(arena, if (previous_implementation) |implementation| objectMember(implementation, name) else null);
        const next = try scalarTextOrEmpty(arena, if (current_implementation) |implementation| objectMember(implementation, name) else null);
        if (!std.mem.eql(u8, prior, next)) return false;
    }
    return true;
}
