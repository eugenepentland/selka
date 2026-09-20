//! `mylang context`: one bounded, source-pinned answer about one declaration.
//!
//! The command composes facts other surfaces already publish — checked
//! navigation, static test reachability and the classified `api-diff`
//! comparison — into a single `agent-context-v1` envelope, so an agent asking
//! about one declaration pays for one frontend pass instead of four.
//!
//! Two rules shape every answer. A fact that was not checked is published with
//! the status that says so rather than an empty set, and the response never
//! exceeds the requested byte budget: records are dropped whole from the
//! lowest-priority section first, and the envelope names what it left out and
//! how to ask for the rest.
const std = @import("std");
const typed = @import("typed.zig");
const project = @import("project.zig");
const pc = @import("project_compile.zig");
const receipt = @import("source_receipt.zig");
const navigation = @import("navigation.zig");
const navigation_partial = @import("navigation_partial.zig");
const fact_status = @import("fact_status.zig");
const tests_index = @import("tests_index.zig");
const api_diff = @import("api_diff.zig");
const effect_set = @import("effect_set.zig");
const diagnostic = @import("diagnostic.zig");

const Value = std.json.Value;
const Object = std.json.ObjectMap;
const Array = std.json.Array;

/// An insertion-ordered JSON object under one arena. `std.json.ObjectMap` is an
/// unmanaged map in this toolchain, so the wrapper keeps the arena in one place
/// instead of threading it through every field a section publishes.
const Doc = struct {
    arena: std.mem.Allocator,
    map: Object = .empty,

    fn init(arena: std.mem.Allocator) Doc {
        return .{ .arena = arena };
    }

    fn put(self: *Doc, key: []const u8, value: Value) Error!void {
        self.map.put(self.arena, key, value) catch return error.OutOfMemory;
    }

    fn json(self: *const Doc) Value {
        return .{ .object = self.map };
    }
};
const unlimited = std.math.maxInt(usize);

/// JSON keys reused across sections, so a rename touches one place.
const key_status = "status";
const key_kind = "kind";
const key_symbol = "symbol";
const key_at = "at";
const key_location = "location";
const key_analysis = "analysis";
const key_declaration = "declaration";
const key_id = "id";
const key_name = "name";
const key_contract = "contract";

/// Which declaration, or source position, the caller asked about.
pub const Selector = union(enum) {
    /// An exact module-qualified declaration name, e.g. `model::validate`.
    symbol: []const u8,
    /// A one-based `path:line:column` position in the loaded source.
    at: []const u8,
};

/// A caller-supplied `api-diff` baseline to classify the selection against.
pub const Baseline = struct { path: []const u8, bytes: []const u8 };

/// Everything one `mylang context` run was asked for.
pub const Options = struct {
    /// The project entry the answer describes, repeated in the continuation query.
    entry: []const u8 = "",
    selector: Selector,
    /// Total serialized response budget in bytes, metadata included.
    context_bytes: usize = default_context_bytes,
    baseline: ?Baseline = null,
    /// Why resolved relationships are unavailable, when the project is incomplete.
    unavailable_reason: ?[]const u8 = null,
    /// The provider the project was loaded from. When present, the answer is
    /// confirmed against the files as they are now before it is published, so a
    /// source that changed while the answer was assembled is rejected instead of
    /// contributing facts from two versions.
    sources: ?project.Provider = null,
};

/// The command's verdict, which decides the process status: `ok` and `partial`
/// answer successfully, the rest are usage-level failures.
pub const Status = enum { ok, partial, ambiguous, missing, stale };

/// A rendered answer and the verdict that goes with it.
pub const Answer = struct { bytes: []u8, status: Status };

/// Failures a context run reports. `RecheckUnavailable` is separate from a
/// changed source: the answer could not be confirmed, rather than being known
/// to describe another version.
pub const Error = error{ OutOfMemory, InternalError, IncompleteProject, NavigationLimit, BudgetTooSmall, InvalidBaseline, RecheckUnavailable };

/// Smallest budget the envelope and its identity metadata fit in.
pub const minimum_context_bytes = 1024;
/// Budget used when `--context-bytes` is absent.
pub const default_context_bytes = 8192;
/// Largest source the confirmation pass re-reads through the provider.
const recheck_source_limit = 64 * 1024 * 1024;
/// The path prefix of a module that ships inside the compiler, which no file
/// change can reach.
const embedded_source_prefix = "@stdlib/";

/// How much of the answer one assembly attempt may include. A `null` section cap
/// omits the section; a number keeps at most that many of its records.
const Caps = struct {
    /// The per-input source receipt, the largest purely descriptive metadata.
    inputs: bool = true,
    types: ?usize = unlimited,
    dependencies: ?usize = unlimited,
    tests: ?usize = unlimited,
    changes: ?usize = unlimited,
    /// False drops the selected declaration's source body.
    snippet: bool = true,
    /// How much of the body this attempt publishes.
    detail: Detail = .full,
};

/// The three depths of an answer once records stop fitting: the sections, the
/// identity and verdict with the omissions that name what the sections would
/// have carried, and finally the identity alone for a rejected answer.
const Detail = enum { full, identity, bare };

/// The list-valued sections in the fixed priority order the answer publishes
/// them. `declaration` and `contract` are always present and never dropped.
const ListSection = enum(usize) {
    types = 0,
    dependencies = 1,
    tests = 2,
    changes = 3,

    /// The wire name of this section.
    fn wireName(self: ListSection) []const u8 {
        return switch (self) {
            .types => "types",
            .dependencies => "dependencies",
            .tests => "tests",
            .changes => "changes",
        };
    }
};

/// Sections in priority order; the answer gives them up from the end.
const priority_order = [_]ListSection{ .types, .dependencies, .tests, .changes };

/// The records each list section would publish if the budget allowed all of them.
const Records = struct {
    types: std.ArrayList(Value) = .empty,
    dependencies: std.ArrayList(Value) = .empty,
    tests: std.ArrayList(Value) = .empty,
    changes: std.ArrayList(Value) = .empty,

    fn count(self: *const Records, section: ListSection) usize {
        return switch (section) {
            .types => self.types.items.len,
            .dependencies => self.dependencies.items.len,
            .tests => self.tests.items.len,
            .changes => self.changes.items.len,
        };
    }

    fn slice(self: *const Records, section: ListSection) []const Value {
        return switch (section) {
            .types => self.types.items,
            .dependencies => self.dependencies.items,
            .tests => self.tests.items,
            .changes => self.changes.items,
        };
    }
};

/// What the selector resolved to, and why nothing resolved when it did not.
const Subject = struct {
    compilation: ?*pc.Compilation = null,
    facts: ?*navigation.Facts = null,
    snapshot: ?navigation.Snapshot = null,
    snapshot_sha256: []const u8 = "",
    symbol: ?*const navigation.Symbol = null,
    diagnostic: ?usize = null,
    candidates: []const []const u8 = &.{},
};

/// What a lexical-candidate answer has instead of a merged compilation: the
/// loaded project a position selector resolves against, and the names a lexer
/// pass recovered.
const Lexical = struct {
    loaded: *const project.Project,
    candidates: navigation_partial.Candidates,
};

/// The verdict and the records one run assembled, before any budget was applied.
const Diagnosis = struct {
    status: Status = .ok,
    reason: ?[]const u8 = null,
    records: Records = .{},
};

/// One `mylang context` run: what it was asked, what it found, and how it ended.
const Session = struct {
    gpa: std.mem.Allocator,
    arena: std.mem.Allocator,
    options: Options,
    source: Subject = .{},
    diagnosis: Diagnosis = .{},
    /// Present only when body syntax failed before any declaration merged.
    lexical: ?Lexical = null,
};

/// Render one answer from a loaded compilation, checked or not. A compilation
/// with no typed program still answers with the declarations it has and the
/// diagnostics that cover the selection, which is what makes the command useful
/// on a project that does not currently build.
pub fn render(allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, options: Options) Error!Answer {
    return run(allocator, compilation, identity, options);
}

/// Render the answer for a project whose body syntax failed before any
/// declaration could merge: the envelope names the selector, states that only
/// lexical candidates were recovered, and publishes no resolved relationship.
pub fn renderPartial(allocator: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity, options: Options) Error!Answer {
    return runPartial(allocator, loaded, identity, options);
}

fn run(allocator: std.mem.Allocator, compilation: *pc.Compilation, identity: receipt.Identity, options: Options) Error!Answer {
    if (options.context_bytes < minimum_context_bytes) return error.BudgetTooSmall;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var session: Session = .{ .gpa = allocator, .arena = arena.allocator(), .options = options };
    var facts = try navigation.collect(session.arena, compilation, identity, .{});
    session.source = .{
        .compilation = compilation,
        .facts = &facts,
        .snapshot = facts.snapshot,
        .snapshot_sha256 = facts.snapshot_sha256,
    };
    try resolve(&session);
    if (session.diagnosis.status == .ok and !facts.checked) {
        session.diagnosis.status = .partial;
        session.diagnosis.reason = options.unavailable_reason orelse "bodies were not checked; declarations and diagnostics only";
    }
    if (session.diagnosis.status == .ok or session.diagnosis.status == .partial) try collectRecords(&session);
    if (try sourcesChanged(&session, session.arena, &compilation.index.project.*, facts.snapshot)) {
        return .{ .bytes = try rejectedAnswer(&session), .status = .stale };
    }
    return assembleAnswer(&session);
}

fn runPartial(allocator: std.mem.Allocator, loaded: *const project.Project, identity: receipt.Identity, options: Options) Error!Answer {
    if (options.context_bytes < minimum_context_bytes) return error.BudgetTooSmall;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    var session: Session = .{ .gpa = allocator, .arena = arena.allocator(), .options = options };
    const recovered = navigation_partial.candidates(session.arena, loaded) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.NavigationLimit => return error.NavigationLimit,
        error.InternalError, error.IncompleteProject => return error.IncompleteProject,
    };
    session.lexical = .{ .loaded = loaded, .candidates = recovered };
    var snapshot_project = loaded.*;
    snapshot_project.problem = null;
    const snapshot: navigation.Snapshot = .{
        .implementation = try receipt.implementation(session.arena, identity),
        .inputs = receipt.inputs(session.arena, &snapshot_project) catch return error.IncompleteProject,
    };
    session.source = .{
        .snapshot = snapshot,
        .snapshot_sha256 = try receipt.digest(session.arena, snapshot),
    };
    session.diagnosis = .{
        .status = .partial,
        .reason = options.unavailable_reason orelse "body syntax failed; only lexical top-level candidates were recovered",
    };
    try resolve(&session);
    if (try sourcesChanged(&session, session.arena, loaded, snapshot)) {
        return .{ .bytes = try rejectedAnswer(&session), .status = .stale };
    }
    return assembleAnswer(&session);
}

/// Resolve the selector against the declarations this pass produced.
fn resolve(session: *Session) Error!void {
    switch (session.options.selector) {
        .symbol => |name| try resolveSymbol(session, name),
        .at => |spec| try resolveAt(session, spec),
    }
}

/// Every declaration this run can name: the checked tables when the bodies
/// merged, and the recovered lexical candidates when they did not.
fn allSymbols(session: *const Session) []const navigation.Symbol {
    if (session.source.facts) |facts| return facts.symbols;
    if (session.lexical) |*recovered| return recovered.candidates.symbols;
    return &.{};
}

/// The one declaration this run can name with an exact qualified name.
fn symbolWithId(session: *const Session, id: []const u8) ?*const navigation.Symbol {
    for (allSymbols(session)) |*item| {
        if (std.mem.eql(u8, item.id, id)) return item;
    }
    return null;
}

fn resolveSymbol(session: *Session, name: []const u8) Error!void {
    const symbols = allSymbols(session);
    if (symbols.len == 0) {
        session.diagnosis.status = .partial;
        session.diagnosis.reason = "no declarations were recovered; the source could not be parsed or lexed";
        return;
    }
    if (symbolWithId(session, name)) |found| {
        session.source.symbol = found;
        return;
    }
    // A bare name is accepted only when exactly one declaration carries it: a
    // near match is reported, never silently chosen.
    var matches: std.ArrayList([]const u8) = .empty;
    for (symbols) |*item| {
        if (std.mem.eql(u8, item.name, name)) matches.append(session.arena, item.id) catch return error.OutOfMemory;
    }
    if (matches.items.len == 1) {
        session.source.symbol = symbolWithId(session, matches.items[0]);
        return;
    }
    std.mem.sort([]const u8, matches.items, {}, stringLessThan);
    session.source.candidates = session.arena.dupe([]const u8, matches.items) catch return error.OutOfMemory;
    session.diagnosis.status = if (matches.items.len == 0) .missing else .ambiguous;
    session.diagnosis.reason = if (matches.items.len == 0)
        "no declaration in this project has that qualified name"
    else
        "several declarations carry that unqualified name; use a module-qualified name";
}

fn stringLessThan(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// A one-based `path:line:column` source position.
const At = struct { path: []const u8, line: usize, column: usize };

fn parseAt(spec: []const u8) ?At {
    const last = std.mem.lastIndexOfScalar(u8, spec, ':') orelse return null;
    const before = std.mem.lastIndexOfScalar(u8, spec[0..last], ':') orelse return null;
    const column = std.fmt.parseInt(usize, spec[last + 1 ..], 10) catch return null;
    const line = std.fmt.parseInt(usize, spec[before + 1 .. last], 10) catch return null;
    if (before == 0 or line == 0 or column == 0) return null;
    return .{ .path = spec[0..before], .line = line, .column = column };
}

fn resolveAt(session: *Session, spec: []const u8) Error!void {
    const at = parseAt(spec) orelse {
        session.diagnosis.status = .missing;
        session.diagnosis.reason = "expected a one-based PATH:LINE:COLUMN position";
        return;
    };
    const loaded = if (session.source.compilation) |compilation|
        &compilation.index.project.*
    else if (session.lexical) |*recovered|
        recovered.loaded
    else {
        session.diagnosis.status = .partial;
        session.diagnosis.reason = "no source was parsed; only lexical candidates were recovered";
        return;
    };
    const offset = offsetOf(loaded, at) orelse {
        session.diagnosis.status = .missing;
        session.diagnosis.reason = "that position is outside every loaded module";
        return;
    };
    const symbol = try innermostSymbol(session, at.path, offset);
    const found = if (session.source.compilation) |compilation|
        try innermostDiagnostic(compilation, at.path, offset)
    else
        null;
    if (symbol) |best| {
        session.source.symbol = best;
        session.source.diagnostic = found;
        return;
    }
    if (found) |index| {
        session.source.diagnostic = index;
        return;
    }
    session.diagnosis.status = .missing;
    session.diagnosis.reason = "no declaration or diagnostic covers that position";
}

/// The byte offset of a one-based line and column inside the loaded module whose
/// original path matches, or null when no module carries that path.
fn offsetOf(loaded: *const project.Project, at: At) ?usize {
    for (loaded.modules.items) |module| {
        if (!pathMatches(module.src.path, at.path)) continue;
        const line = at.line - 1;
        if (line >= module.src.line_starts.len) return null;
        const start = module.src.line_starts[line];
        const end = if (line + 1 < module.src.line_starts.len) module.src.line_starts[line + 1] else module.src.bytes.len;
        return @min(start + at.column - 1, end);
    }
    return null;
}

/// Compare a selector path with a loaded path, accepting the suffix spelling a
/// caller who ran the command from the project root would type.
fn pathMatches(loaded: []const u8, requested: []const u8) bool {
    if (std.mem.eql(u8, loaded, requested)) return true;
    if (loaded.len <= requested.len) return false;
    return std.mem.endsWith(u8, loaded, requested) and loaded[loaded.len - requested.len - 1] == '/';
}

/// The smallest declaration whose span covers the position. The declarations
/// are the ones this run can name, so a position selector resolves a lexically
/// recovered candidate exactly as a symbol selector does.
fn innermostSymbol(session: *Session, path: []const u8, offset: usize) Error!?*const navigation.Symbol {
    var best: ?*const navigation.Symbol = null;
    var best_width: usize = unlimited;
    for (allSymbols(session)) |*item| {
        if (!pathMatches(item.location.path, path)) continue;
        if (!covers(session, item, offset)) continue;
        const width = spanWidth(item, session);
        if (width >= best_width) continue;
        best = item;
        best_width = width;
    }
    return best;
}

/// Whether a declaration's source span contains one position. `navigation`
/// locates a declaration by its name, but the span a caller means by "inside this
/// declaration" runs to the end of its body: the snippet `navigation` publishes
/// starts at the name and stops at the body end, so the coverage is the name plus
/// the snippet rather than the name token alone. A type, field or local declares
/// no body and keeps the span `navigation` gave it.
fn covers(session: *const Session, symbol: *const navigation.Symbol, offset: usize) bool {
    return symbol.location.start <= offset and offset <= coverageEnd(session, symbol);
}

/// The last byte a declaration covers.
fn coverageEnd(session: *const Session, symbol: *const navigation.Symbol) usize {
    if (symbol.context.snippet.len == 0) return symbol.location.end;
    const shown = symbol.location.start +| symbol.context.snippet.len;
    if (!symbol.context.snippet_truncated) return @max(shown, symbol.location.end);
    // A snippet longer than the excerpt limit stops short of the body end, so the
    // merged syntax supplies the end the excerpt was cut off from.
    return bodyEnd(session, symbol) orelse @max(shown, symbol.location.end);
}

/// The original end of the function declaration whose name starts where `symbol`
/// starts, for a declaration whose published snippet was cut short of its body.
fn bodyEnd(session: *const Session, symbol: *const navigation.Symbol) ?usize {
    const compilation = session.source.compilation orelse return null;
    for (compilation.syntax.functions) |function| {
        const name = compilation.src.originalSpan(function.name) catch continue;
        if (name.span.start != symbol.location.start) continue;
        if (name.input >= compilation.index.project.modules.items.len) continue;
        if (!pathMatches(compilation.index.project.modules.items[name.input].src.path, symbol.location.path)) continue;
        const body = compilation.src.originalSpan(compilation.syntax.statements.items[@backingInt(function.body)].span) catch continue;
        if (body.input != name.input) continue;
        return body.span.end;
    }
    return null;
}

fn spanWidth(symbol: *const navigation.Symbol, session: *const Session) usize {
    return coverageEnd(session, symbol) -| symbol.location.start;
}

/// The smallest diagnostic whose original span covers the position.
fn innermostDiagnostic(compilation: *pc.Compilation, path: []const u8, offset: usize) Error!?usize {
    var best: ?usize = null;
    var best_width: usize = unlimited;
    for (compilation.diagnostics.items.items, 0..) |item, index| {
        const at = compilation.src.locate(item.span.start);
        if (!pathMatches(at.path, path)) continue;
        const original = compilation.src.originalSpan(item.span) catch continue;
        if (!(original.span.start <= offset and offset <= original.span.end)) continue;
        const width = original.span.end -| original.span.start;
        if (width >= best_width) continue;
        best = index;
        best_width = width;
    }
    return best;
}

/// Detect a source change between the receipt the answer was built from and the
/// files as they are now. A read failure counts as a change: the answer cannot
/// be pinned to the source it claims. Combining facts from two versions is never
/// allowed.
///
/// The receipt hashes the module digest recorded when the source was loaded, so
/// comparing two receipts alone cannot see an edit to the bytes the answer was
/// assembled from. Each digest is therefore re-derived from the bytes the module
/// holds now, and, when the caller supplied the provider the project was loaded
/// from, every input is re-read and compared with the identity the snapshot
/// published. A file that cannot be re-read is its own outcome: the answer is
/// unconfirmed rather than known to describe another version.
fn sourcesChanged(session: *const Session, arena: std.mem.Allocator, loaded: *const project.Project, before: navigation.Snapshot) Error!bool {
    var current = loaded.*;
    current.problem = null;
    _ = receipt.inputs(arena, &current) catch return true;
    if (current.order.items.len != before.inputs.len) return true;
    for (current.order.items, before.inputs) |id, then| {
        const module = current.modules.items[id];
        if (!std.mem.eql(u8, module.name, then.module)) return true;
        if (!hashesTo(module.src.bytes, then.sha256)) return true;
    }
    const sources = session.options.sources orelse return false;
    for (before.inputs) |input| {
        if (std.mem.startsWith(u8, input.path, embedded_source_prefix)) continue;
        const bytes = sources.read(sources.context, arena, input.path, recheck_source_limit) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.RecheckUnavailable,
        };
        if (!hashesTo(bytes, input.sha256)) return true;
    }
    return false;
}

/// Whether one source still hashes to the identity a snapshot published.
fn hashesTo(bytes: []const u8, recorded: []const u8) bool {
    var digest: [32]u8 = undefined;
    std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
    return std.mem.eql(u8, &std.fmt.bytesToHex(digest, .lower), recorded);
}

/// The answer a rejected run publishes: identities and the reason, no facts.
fn rejectedAnswer(session: *Session) Error![]u8 {
    session.diagnosis.status = .stale;
    session.diagnosis.reason = "the source changed while this answer was being assembled; no facts are published";
    session.diagnosis.records = .{};
    return assemble(session, .{ .inputs = false, .types = null, .dependencies = null, .tests = null, .changes = null, .snippet = false, .detail = .bare });
}

fn assembleAnswer(session: *Session) Error!Answer {
    const budget = session.options.context_bytes;
    var level: usize = 0;
    while (level <= drop_levels) : (level += 1) {
        var caps = capsFor(session, level);
        const full = try assemble(session, caps);
        if (full.len <= budget) return .{ .bytes = full, .status = session.diagnosis.status };
        session.gpa.free(full);
        // Drop whole records from the lowest-priority section that is still
        // present before giving the section up entirely, so a section that fits
        // in part is kept rather than discarded whole.
        const section = lowestPresent(session, caps) orelse continue;
        setCap(&caps, section, largestFittingCap(session, caps, section, budget) catch |err| return err);
        const trimmed = try assemble(session, caps);
        if (trimmed.len <= budget) return .{ .bytes = trimmed, .status = session.diagnosis.status };
        session.gpa.free(trimmed);
    }
    return error.BudgetTooSmall;
}

/// The number of rungs in the reduction ladder: one per droppable item, then the
/// rung that drops the sections and the rung that drops the omissions too.
const drop_levels = 8;

/// The rung that gives the sections up: it keeps the identity, the verdict and
/// the omissions that name every section the answer would have carried.
const identity_level = 7;

/// The largest record cap for one section whose complete response still fits.
fn largestFittingCap(session: *Session, caps: Caps, section: ListSection, budget: usize) Error!usize {
    var low: usize = 0;
    var high = session.diagnosis.records.count(section);
    var attempt = caps;
    while (low < high) {
        const middle = low + (high - low + 1) / 2;
        setCap(&attempt, section, middle);
        const bytes = try assemble(session, attempt);
        defer session.gpa.free(bytes);
        if (bytes.len <= budget) low = middle else high = middle - 1;
    }
    return low;
}

fn capsFor(session: *const Session, level: usize) Caps {
    const has_changes = session.options.baseline != null and session.diagnosis.status != .stale;
    return .{
        .inputs = level < 1,
        .changes = if (!has_changes or level >= 2) null else unlimited,
        .tests = if (level >= 3) null else unlimited,
        .dependencies = if (level >= 4) null else unlimited,
        .types = if (level >= 5) null else unlimited,
        .snippet = level < 6,
        .detail = if (level < identity_level) .full else if (level < drop_levels) .identity else .bare,
    };
}

fn capOf(caps: Caps, section: ListSection) ?usize {
    return switch (section) {
        .types => caps.types,
        .dependencies => caps.dependencies,
        .tests => caps.tests,
        .changes => caps.changes,
    };
}

fn setCap(caps: *Caps, section: ListSection, value: ?usize) void {
    switch (section) {
        .types => caps.types = value,
        .dependencies => caps.dependencies = value,
        .tests => caps.tests = value,
        .changes => caps.changes = value,
    }
}

/// The lowest-priority section a record cap can still be applied to.
fn lowestPresent(session: *const Session, caps: Caps) ?ListSection {
    var index = priority_order.len;
    while (index > 0) {
        index -= 1;
        const section = priority_order[index];
        if (capOf(caps, section) == null) continue;
        if (section == .changes and session.options.baseline == null) continue;
        return section;
    }
    return null;
}

fn assemble(session: *Session, caps: Caps) Error![]u8 {
    var root = try document(session, caps);
    const json_bytes = try serialize(session.gpa, &root);
    defer session.gpa.free(json_bytes);
    const out = session.gpa.alloc(u8, json_bytes.len + 1) catch return error.OutOfMemory;
    @memcpy(out[0..json_bytes.len], json_bytes);
    out[json_bytes.len] = '\n';
    return out;
}

/// Serialize with an exact `emitted_bytes`, which counts itself: the written
/// number is repeated until it has as many digits as the document carrying it.
fn serialize(gpa: std.mem.Allocator, root: *Doc) Error![]u8 {
    var attempt: usize = 0;
    for (0..8) |_| {
        try root.put("emitted_bytes", .{ .integer = @intCast(attempt) });
        const bytes = std.json.Stringify.valueAlloc(gpa, root.json(), .{}) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        if (bytes.len + 1 == attempt) return bytes;
        gpa.free(bytes);
        attempt = bytes.len + 1;
    }
    return error.InternalError;
}

fn document(session: *Session, caps: Caps) Error!Doc {
    const arena = session.arena;
    var root = Doc.init(arena);
    try root.put("version", .{ .string = "agent-context-v1" });
    try root.put(key_status, .{ .string = @tagName(session.diagnosis.status) });
    try root.put("entry", .{ .string = session.options.entry });
    try root.put("selector", try selectorValue(session));
    try root.put("context_bytes", .{ .integer = @intCast(session.options.context_bytes) });
    try root.put(key_analysis, try analysisValue(session));
    if (session.source.snapshot) |snapshot| try root.put("snapshot", try snapshotValue(session, snapshot, caps.inputs));
    try root.put("snapshot_sha256", .{ .string = session.source.snapshot_sha256 });
    if (session.diagnosis.reason) |reason| try root.put("reason", .{ .string = reason });
    if (session.source.candidates.len != 0) try root.put("candidates", try candidatesValue(session));
    try root.put("sections", try sectionsValue(session, caps));
    const omissions = try omissionsValue(session, caps);
    try root.put("omissions", .{ .array = omissions });
    if (omissions.items.len != 0) try root.put("continuation", .{ .string = try continuationQuery(session) });
    return root;
}

fn selectorValue(session: *const Session) Error!Value {
    var object = Doc.init(session.arena);
    switch (session.options.selector) {
        .symbol => |name| {
            try object.put(key_kind, .{ .string = "symbol" });
            try object.put(key_symbol, .{ .string = name });
        },
        .at => |spec| {
            try object.put(key_kind, .{ .string = "at" });
            try object.put(key_at, .{ .string = spec });
        },
    }
    if (session.source.symbol) |symbol| try object.put("resolved", .{ .string = symbol.id });
    return object.json();
}

fn candidatesValue(session: *Session) Error!Value {
    var items = Array.init(session.arena);
    for (session.source.candidates) |id| items.append(.{ .string = id }) catch return error.OutOfMemory;
    return .{ .array = items };
}

/// How much of the contract the run actually analyzed, in the shared fact-status
/// vocabulary, plus the reason when it is less than everything.
fn analysisValue(session: *const Session) Error!Value {
    var object = Doc.init(session.arena);
    const facts = session.source.facts;
    const status: fact_status.Status = if (facts) |found|
        (if (found.checked) .checked else .declaration_only)
    else
        .lexical_only;
    try object.put(key_status, .{ .string = fact_status.name(status) });
    if (facts == null or !facts.?.checked) {
        try object.put("reason", .{ .string = session.diagnosis.reason orelse "bodies were not checked" });
    }
    return object.json();
}

/// The compiler and source identities the answer is pinned to. The per-input
/// rows are descriptive detail, so they are the first thing a small budget gives
/// up; the digest above them never is.
fn snapshotValue(session: *Session, snapshot: navigation.Snapshot, with_inputs: bool) Error!Value {
    var object = Doc.init(session.arena);
    var compiler = Doc.init(session.arena);
    try compiler.put("compiler_sha256", .{ .string = snapshot.implementation.compiler_sha256 });
    try compiler.put("zig_version", .{ .string = snapshot.implementation.zig_version });
    try compiler.put("architecture", .{ .string = snapshot.implementation.architecture });
    try compiler.put("os", .{ .string = snapshot.implementation.os });
    try compiler.put("abi", .{ .string = snapshot.implementation.abi });
    try compiler.put("optimize", .{ .string = snapshot.implementation.optimize });
    try object.put("compiler", compiler.json());
    try object.put("modules", .{ .integer = @intCast(snapshot.inputs.len) });
    if (!with_inputs) return object.json();
    var inputs = Array.init(session.arena);
    for (snapshot.inputs) |input| {
        var row = Doc.init(session.arena);
        try row.put("module", .{ .string = input.module });
        try row.put("path", .{ .string = input.path });
        try row.put("sha256", .{ .string = input.sha256 });
        inputs.append(row.json()) catch return error.OutOfMemory;
    }
    try object.put("inputs", .{ .array = inputs });
    return object.json();
}

fn sectionsValue(session: *Session, caps: Caps) Error!Value {
    var sections = Array.init(session.arena);
    if (caps.detail != .full) return .{ .array = sections };
    try sections.append(try sectionOf(session, key_declaration, try declarationRecords(session, caps)));
    try sections.append(try sectionOf(session, key_contract, try contractRecords(session)));
    for (priority_order) |section| {
        if (section == .changes and session.options.baseline == null) continue;
        const cap = capOf(caps, section) orelse continue;
        const total = session.diagnosis.records.count(section);
        try sections.append(try sectionOf(session, section.wireName(), session.diagnosis.records.slice(section)[0..@min(cap, total)]));
    }
    return .{ .array = sections };
}

fn sectionOf(session: *Session, name: []const u8, records: []const Value) Error!Value {
    var object = Doc.init(session.arena);
    try object.put(key_name, .{ .string = name });
    var items = Array.init(session.arena);
    for (records) |record| items.append(record) catch return error.OutOfMemory;
    try object.put("records", .{ .array = items });
    return object.json();
}

fn omissionsValue(session: *Session, caps: Caps) Error!Array {
    var omissions = Array.init(session.arena);
    if (caps.detail == .bare) return omissions;
    if (caps.detail == .identity) {
        try appendIdentityOmissions(session, &omissions);
        return omissions;
    }
    if (!caps.inputs) try appendOmission(session, &omissions, "source", "inputs", null);
    if (!caps.snippet) try appendOmission(session, &omissions, key_declaration, "snippet", null);
    for (priority_order) |section| {
        if (section == .changes and session.options.baseline == null) continue;
        const total = session.diagnosis.records.count(section);
        const cap = capOf(caps, section) orelse {
            if (total != 0) try appendOmission(session, &omissions, section.wireName(), null, total);
            continue;
        };
        if (cap < total) try appendOmission(session, &omissions, section.wireName(), null, total - cap);
    }
    return omissions;
}

/// The omissions of the identity-only rung: the sections are gone, so every
/// section the answer would have carried is named with the whole record count
/// the caller gave up, and the envelope's continuation query asks for the room
/// to include them. A budget too small for the sections is still an answer that
/// says what it left out rather than a silent truncation.
fn appendIdentityOmissions(session: *Session, omissions: *Array) Error!void {
    if (session.source.symbol != null or session.source.diagnostic != null) {
        try appendOmission(session, omissions, key_declaration, null, null);
        try appendOmission(session, omissions, key_contract, null, null);
    }
    for (priority_order) |section| {
        if (section == .changes and session.options.baseline == null) continue;
        const total = session.diagnosis.records.count(section);
        if (total != 0) try appendOmission(session, omissions, section.wireName(), null, total);
    }
}

fn appendOmission(session: *Session, omissions: *Array, section: []const u8, field: ?[]const u8, dropped: ?usize) Error!void {
    var object = Doc.init(session.arena);
    try object.put("section", .{ .string = section });
    if (field) |name| try object.put("field", .{ .string = name });
    try object.put("reason", .{ .string = "budget" });
    if (dropped) |count| try object.put("records_omitted", .{ .integer = @intCast(count) });
    omissions.append(object.json()) catch return error.OutOfMemory;
}

/// The query that asks for the same answer with room to include what was dropped.
fn continuationQuery(session: *Session) Error![]const u8 {
    const asked = @max(session.options.context_bytes * 2, minimum_context_bytes * 4);
    const flag = switch (session.options.selector) {
        .symbol => "symbol",
        .at => "at",
    };
    const text = switch (session.options.selector) {
        .symbol => |name| name,
        .at => |spec| spec,
    };
    return std.fmt.allocPrint(session.arena, "mylang context {s} --{s}='{s}' --context-bytes={d}", .{ session.options.entry, flag, text, asked }) catch return error.OutOfMemory;
}

/// Section 1: the selected declaration's identity, span and body, plus every
/// diagnostic whose span covers it.
fn declarationRecords(session: *Session, caps: Caps) Error![]const Value {
    var records = Array.init(session.arena);
    if (session.source.symbol) |symbol| {
        var object = Doc.init(session.arena);
        try object.put("kind", .{ .string = "declaration" });
        try object.put(key_id, .{ .string = symbol.id });
        try object.put(key_name, .{ .string = symbol.name });
        try object.put("declaration_kind", .{ .string = symbol.kind });
        try object.put("exported", .{ .bool = symbol.exported });
        try object.put(key_location, try locationValue(session.arena, symbol.location));
        if (caps.snippet) {
            try object.put("snippet", .{ .string = symbol.context.snippet });
            try object.put("snippet_truncated", .{ .bool = symbol.context.snippet_truncated });
        }
        records.append(object.json()) catch return error.OutOfMemory;
    }
    if (session.source.compilation) |compilation| {
        for (try diagnosticsFor(session, compilation)) |item| records.append(item) catch return error.OutOfMemory;
    }
    return records.items;
}

/// Every diagnostic that covers the selection: the one a position selector
/// landed on, or every diagnostic inside a selected declaration's span.
fn diagnosticsFor(session: *Session, compilation: *pc.Compilation) Error![]const Value {
    var found = Array.init(session.arena);
    const bounds = selectionSpan(session) orelse {
        if (session.source.diagnostic) |index| {
            if (index < compilation.diagnostics.items.items.len) found.append(try diagnosticValue(session.arena, compilation, compilation.diagnostics.items.items[index])) catch return error.OutOfMemory;
        }
        return found.items;
    };
    for (compilation.diagnostics.items.items) |item| {
        if (item.span.start > bounds.end or bounds.start > item.span.end) continue;
        found.append(try diagnosticValue(session.arena, compilation, item)) catch return error.OutOfMemory;
    }
    return found.items;
}

/// The selected declaration's span in the merged source, which is the
/// coordinate space diagnostics use. The span is the whole declaration, body
/// included, so a diagnostic inside the selected body is published with it.
fn selectionSpan(session: *const Session) ?struct { start: usize, end: usize } {
    const symbol = session.source.symbol orelse return null;
    const compilation = session.source.compilation orelse return null;
    for (compilation.index.project.modules.items, 0..) |module, index| {
        if (!pathMatches(module.src.path, symbol.location.path)) continue;
        if (index >= compilation.src.origins.len) return null;
        const origin = compilation.src.origins[index];
        return .{ .start = origin.start + symbol.location.start, .end = origin.start + coverageEnd(session, symbol) };
    }
    return null;
}

fn diagnosticValue(arena: std.mem.Allocator, compilation: *pc.Compilation, item: diagnostic.Diagnostic) Error!Value {
    var object = Doc.init(arena);
    try object.put("kind", .{ .string = "diagnostic" });
    try object.put("code", .{ .string = item.code });
    try object.put("severity", .{ .string = @tagName(item.severity) });
    try object.put("message", .{ .string = item.message });
    try object.put(key_location, try sourceLocationValue(arena, compilation, item.span.start));
    if (item.related) |related| try object.put("related", try relatedValue(arena, compilation, related));
    return object.json();
}

fn relatedValue(arena: std.mem.Allocator, compilation: *pc.Compilation, related: diagnostic.Related) Error!Value {
    var object = Doc.init(arena);
    try object.put("role", .{ .string = @tagName(related.role) });
    try object.put("message", .{ .string = related.message });
    try object.put(key_location, try sourceLocationValue(arena, compilation, related.span.start));
    return object.json();
}

fn sourceLocationValue(arena: std.mem.Allocator, compilation: *pc.Compilation, offset: usize) Error!Value {
    const at = compilation.src.locate(offset);
    var object = Doc.init(arena);
    try object.put("path", .{ .string = at.path });
    try object.put("line", .{ .integer = @intCast(at.line) });
    try object.put("column", .{ .integer = @intCast(at.column) });
    return object.json();
}

fn locationValue(arena: std.mem.Allocator, location: navigation.Location) Error!Value {
    var object = Doc.init(arena);
    try object.put("path", .{ .string = location.path });
    try object.put("start", .{ .integer = @intCast(location.start) });
    try object.put("end", .{ .integer = @intCast(location.end) });
    try object.put("line", .{ .integer = @intCast(location.line) });
    try object.put("column", .{ .integer = @intCast(location.column) });
    return object.json();
}

/// Section 2: the contract, with every inferred fact labeled by its status, so
/// an unchecked declaration publishes an explicit absence rather than an empty
/// set that would read as a promise.
fn contractRecords(session: *Session) Error![]const Value {
    var records = Array.init(session.arena);
    const symbol = session.source.symbol orelse return records.items;
    var object = Doc.init(session.arena);
    try object.put("kind", .{ .string = key_contract });
    try object.put(key_id, .{ .string = symbol.id });
    try object.put("signature", .{ .string = symbol.details.signature });
    try object.put("return_type", .{ .string = symbol.details.type_name });
    try object.put(key_analysis, .{ .string = fact_status.name(symbol.details.analysis) });
    try object.put("declared_effects", try declaredEffects(session, symbol));
    const checked = symbol.details.analysis == .checked;
    try object.put("effects", if (checked) try namesValue(session.arena, symbol.details.effects) else .null);
    try object.put("mutates", if (checked) try positionsValue(session.arena, symbol.details.mutates) else .null);
    try object.put("return_origin", if (checked) .{ .string = symbol.details.return_origin } else .null);
    try object.put("mutation_writes", if (checked) .{ .bool = symbol.details.mutation_writes } else .null);
    records.append(object.json()) catch return error.OutOfMemory;
    return records.items;
}

/// The declared `effects(...)` ceiling written in the source, or null when the
/// declaration spells no clause. It is read from the checked policy, so it is
/// absent rather than guessed when no typed entry exists.
fn declaredEffects(session: *Session, symbol: *const navigation.Symbol) Error!Value {
    const compilation = session.source.compilation orelse return .null;
    const program = compilation.program orelse return .null;
    for (program.functions) |function| {
        if (!std.mem.eql(u8, function.name, symbol.id)) continue;
        const bound = function.policy.effect_bound orelse return .null;
        var names = Array.init(session.arena);
        inline for (std.meta.tags(effect_set.Effect)) |effect| {
            if (bound.allowed & effect_set.bit(effect) != 0) names.append(.{ .string = @tagName(effect) }) catch return error.OutOfMemory;
        }
        return .{ .array = names };
    }
    return .null;
}

fn namesValue(arena: std.mem.Allocator, names: []const []const u8) Error!Value {
    var items = Array.init(arena);
    for (names) |name| items.append(.{ .string = name }) catch return error.OutOfMemory;
    return .{ .array = items };
}

fn positionsValue(arena: std.mem.Allocator, positions: []const u16) Error!Value {
    var items = Array.init(arena);
    for (positions) |position| items.append(.{ .integer = @intCast(position) }) catch return error.OutOfMemory;
    return .{ .array = items };
}

fn collectRecords(session: *Session) Error!void {
    try collectTypes(session);
    try collectDependencies(session);
    try collectTests(session);
    try collectChanges(session);
}

fn isTypeEdge(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "returns") or std.mem.eql(u8, kind, "accepts") or
        std.mem.eql(u8, kind, "uses_type") or std.mem.eql(u8, kind, "contains_type");
}

fn isCallEdge(kind: []const u8) bool {
    return std.mem.eql(u8, kind, "call") or std.mem.eql(u8, kind, "function_value");
}

/// Section 3: the nominal types the selection mentions, each with its declared
/// fields or cases, so a caller never has to open a second file to read a shape.
fn collectTypes(session: *Session) Error!void {
    const symbol = session.source.symbol orelse return;
    const facts = session.source.facts orelse return;
    var seen = std.StringHashMapUnmanaged(void){};
    for (facts.references) |reference| {
        if (!std.mem.eql(u8, reference.from, symbol.id)) continue;
        if (!isTypeEdge(reference.kind)) continue;
        const target = facts.symbol(reference.to) orelse continue;
        if (!std.mem.eql(u8, target.kind, "type")) continue;
        if (seen.contains(target.id)) continue;
        seen.put(session.arena, target.id, {}) catch return error.OutOfMemory;
        try session.diagnosis.records.types.append(session.arena, try typeValue(session, facts, target));
    }
}

fn typeValue(session: *Session, facts: *navigation.Facts, target: *const navigation.Symbol) Error!Value {
    var object = Doc.init(session.arena);
    try object.put(key_id, .{ .string = target.id });
    try object.put(key_name, .{ .string = target.name });
    try object.put(key_analysis, .{ .string = fact_status.name(target.details.analysis) });
    try object.put(key_location, try locationValue(session.arena, target.location));
    var members = Array.init(session.arena);
    for (facts.symbols) |*member| {
        if (member.id.len <= target.id.len + 1) continue;
        if (!std.mem.startsWith(u8, member.id, target.id)) continue;
        if (member.id[target.id.len] != '.') continue;
        var row = Doc.init(session.arena);
        try row.put(key_id, .{ .string = member.id });
        try row.put(key_name, .{ .string = member.name });
        try row.put("member_kind", .{ .string = member.kind });
        try row.put("type_name", .{ .string = member.details.type_name });
        try row.put(key_location, try locationValue(session.arena, member.location));
        members.append(row.json()) catch return error.OutOfMemory;
    }
    try object.put("members", .{ .array = members });
    return object.json();
}

/// Section 4: the resolved calls out of the selection and the callers into it,
/// each naming the other declaration's checked signature.
fn collectDependencies(session: *Session) Error!void {
    const symbol = session.source.symbol orelse return;
    const facts = session.source.facts orelse return;
    var seen = std.StringHashMapUnmanaged(void){};
    for (facts.references) |reference| {
        if (!std.mem.eql(u8, reference.from, symbol.id)) continue;
        if (!isCallEdge(reference.kind)) continue;
        const target = facts.symbol(reference.to) orelse continue;
        const key = std.fmt.allocPrint(session.arena, "out:{s}", .{target.id}) catch return error.OutOfMemory;
        if (seen.contains(key)) continue;
        seen.put(session.arena, key, {}) catch return error.OutOfMemory;
        try session.diagnosis.records.dependencies.append(session.arena, try referenceValue(session, "outgoing", reference.kind, target));
    }
    for (facts.references) |reference| {
        if (!std.mem.eql(u8, reference.to, symbol.id)) continue;
        if (!isCallEdge(reference.kind)) continue;
        const caller = facts.symbol(reference.from) orelse continue;
        const key = std.fmt.allocPrint(session.arena, "in:{s}", .{caller.id}) catch return error.OutOfMemory;
        if (seen.contains(key)) continue;
        seen.put(session.arena, key, {}) catch return error.OutOfMemory;
        try session.diagnosis.records.dependencies.append(session.arena, try referenceValue(session, "incoming", reference.kind, caller));
    }
}

fn referenceValue(session: *Session, direction: []const u8, edge: []const u8, target: *const navigation.Symbol) Error!Value {
    var object = Doc.init(session.arena);
    try object.put("direction", .{ .string = direction });
    try object.put("edge", .{ .string = edge });
    try object.put(key_id, .{ .string = target.id });
    try object.put("kind", .{ .string = target.kind });
    try object.put("signature", .{ .string = target.details.signature });
    try object.put(key_analysis, .{ .string = fact_status.name(target.details.analysis) });
    try object.put(key_location, try locationValue(session.arena, target.location));
    return object.json();
}

/// Section 5: the discovered tests that reach the selection, labeled as static
/// reachability. A test that calls a declaration is not a promise that it runs.
fn collectTests(session: *Session) Error!void {
    const symbol = session.source.symbol orelse return;
    const compilation = session.source.compilation orelse return;
    const program = compilation.program orelse return;
    const target = functionNamed(program, symbol.id) orelse return;
    const modules = compilation.index.moduleSyntax(session.arena) catch return error.OutOfMemory;
    const graph = tests_index.callGraph(session.arena, program) catch return error.OutOfMemory;
    const discovered = tests_index.discoveredTests(session.arena, program, modules) catch return error.OutOfMemory;
    var index = tests_index.build(session.arena, program, graph, discovered) catch return error.OutOfMemory;
    const answer = index.answer(target);
    for (answer.direct) |name| try session.diagnosis.records.tests.append(session.arena, try testValue(session, "direct", name));
    for (answer.reached) |name| try session.diagnosis.records.tests.append(session.arena, try testValue(session, "reached", name));
}

fn testValue(session: *Session, relation: []const u8, name: []const u8) Error!Value {
    var object = Doc.init(session.arena);
    try object.put("relation", .{ .string = relation });
    try object.put("test", .{ .string = name });
    try object.put("basis", .{ .string = "static-reachability" });
    return object.json();
}

/// The checked function with one exact qualified name.
fn functionNamed(program: typed.Program, name: []const u8) ?typed.FunctionId {
    for (program.functions, 0..) |function, index| {
        if (std.mem.eql(u8, function.name, name)) return @fromBackingInt(@intCast(index));
    }
    return null;
}

/// Section 6: how the selection changed against a caller-supplied baseline.
fn collectChanges(session: *Session) Error!void {
    const baseline = session.options.baseline orelse return;
    const symbol = session.source.symbol orelse return;
    const compilation = session.source.compilation orelse return;
    const entries = api_diff.parseBaseline(session.arena, baseline.bytes) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBaseline,
    };
    const report = api_diff.compare(session.arena, entries, compilation) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidBaseline,
    };
    for ([_][]const api_diff.Change{ report.additive, report.compatible, report.breaking }) |changes| {
        for (changes) |change| {
            if (!std.mem.eql(u8, change.display, symbol.id)) continue;
            var object = Doc.init(session.arena);
            try object.put("class", .{ .string = @tagName(change.class) });
            try object.put(key_declaration, .{ .string = change.display });
            try object.put("detail", .{ .string = change.detail });
            try object.put("basis", .{ .string = "api-diff" });
            session.diagnosis.records.changes.append(session.arena, object.json()) catch return error.OutOfMemory;
        }
    }
}
