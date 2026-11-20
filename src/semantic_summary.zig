//! Per-function check summaries: what `check` needs to stand in for an unchanged
//! ordinary body without checking it or materializing its checked tree.
//!
//! A summary is recorded for every ordinary function of a successful check. It
//! names the function by its stable declaration key and proves the body
//! unchanged by the function's dependency context (the digest `semantic_key`
//! computes over every declaration the signature and body reference) and a
//! BLAKE3 digest of its declaration region. It carries the facts the
//! cross-function passes read about the function — its mutation summary — the diagnostics the function produced, with spans
//! relative to its region, and the functions its body names. A later check may
//! stand the summary in for the body only while those cross-function facts stay
//! exactly as stored for every function it re-checks; the check itself enforces
//! that and otherwise repeats in full.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const source = @import("source.zig");
const semantic_key = @import("semantic_key.zig");
const types = @import("semantic_summary_types.zig");
const sections_mod = @import("semantic_sections.zig");

/// Payload version; bump for any layout or meaning change so old payloads miss.
pub const format_version = sections_mod.format_version;

/// Re-export of `semantic_summary_types.FixEdit`.
pub const FixEdit = types.FixEdit;

/// Re-export of `semantic_summary_types.Note`.
pub const Note = types.Note;

/// Re-export of `semantic_summary_types.Notes`.
pub const Notes = types.Notes;
/// Re-export of `semantic_summary_types.Keep`.
pub const Keep = types.Keep;

/// Re-export of `semantic_summary_types.Region`.
pub const Region = types.Region;

/// Re-export of `semantic_summary_types.Fact`.
pub const Fact = types.Fact;

/// Re-export of `semantic_summary_types.Template`.
pub const Template = types.Template;

/// Re-export of `semantic_summary_types.Refs`.
pub const Refs = types.Refs;

/// Re-export of `semantic_summary_types.Uses`.
pub const Uses = types.Uses;

/// Re-export of `semantic_summary_types.Summary`.
pub const Summary = types.Summary;

/// Re-export of `semantic_summary_types.Table`.
pub const Table = types.Table;

/// Re-export of `semantic_summary_types.OutSection`.
pub const OutSection = types.OutSection;

/// Re-export of `semantic_summary_types.Shape`.
pub const Shape = types.Shape;

/// Re-export of `semantic_summary_types.SizeHint`.
pub const SizeHint = types.SizeHint;

/// A decoded summary table. One decoded from a payload is a view of its sections, opened and decoded as functions are asked for
/// (`sections`); one built in memory (a library's declared functions, a test's table) holds its `summaries` outright. Either way a
/// function is its position, and `at`, `flagsAt`, `factAt` and `find` answer for both.
pub const Index = struct {
    summaries: []const Summary = &.{},
    records: []const []const u8 = &.{},
    record_shapes: []const [32]u8 = &.{},
    by_key: std.StringHashMapUnmanaged(u32) = .empty,
    size: SizeHint = .{},
    sections: ?*sections_mod.Sections = null,

    /// How many functions the table holds.
    pub fn count(self: *const Index) usize {
        if (self.sections) |view| return view.functionCount();
        return self.summaries.len;
    }

    /// The summary at `position`, decoded on first use. Its `uses.records` index the record list of its section (`recordName`), and its
    /// `uses.callees` and `uses.values` are empty when it was decoded from a payload (`calleesAt`, `valuesAt`).
    pub fn at(self: *const Index, position: u32) *const Summary {
        if (self.sections) |view| return view.at(position);
        return &self.summaries[position];
    }

    /// What the planner asks of the function at `position` before anything else, without decoding the rest.
    pub fn flagsAt(self: *const Index, position: u32) sections_mod.Flags {
        if (self.sections) |view| return view.flagsAt(position);
        return sections_mod.Flags.of(self.summaries[position]);
    }

    /// The facts of the function at `position`, without decoding the rest.
    pub fn factAt(self: *const Index, position: u32) Fact {
        if (self.sections) |view| return view.factAt(position);
        return self.summaries[position].fact;
    }

    /// The references of the function at `position`'s tree (null for one that names no specialization or interned type), without decoding the rest.
    pub fn refsAt(self: *const Index, position: u32) ?Refs {
        if (self.sections) |view| return (view.hotAt(position) orelse return null).refs;
        return self.summaries[position].uses.refs;
    }

    /// The waiver guard the function at `position` was stored under, if any, without decoding the rest.
    pub fn guardAt(self: *const Index, position: u32) ?[32]u8 {
        if (self.sections) |view| return (view.hotAt(position) orelse return null).guard;
        return self.summaries[position].notes.guard;
    }

    /// The diagnostics the body of the function at `position` produced when it was checked, without decoding the rest.
    pub fn bodyNotesAt(self: *const Index, position: u32) []const Note {
        if (self.sections) |view| return (view.hotAt(position) orelse return &.{}).body;
        return self.summaries[position].notes.body;
    }

    /// The `W_COPY_MOVE` filter's stored answers for the function at `position` as a caller (`Keep`), without decoding the rest.
    pub fn keepsAt(self: *const Index, position: u32) []const Keep {
        if (self.sections) |view| return (view.hotAt(position) orelse return &.{}).keeps;
        return self.summaries[position].notes.keeps;
    }

    /// The warnings the whole-program passes reported inside the function at `position`, without decoding the rest.
    pub fn passNotesAt(self: *const Index, position: u32) []const Note {
        if (self.sections) |view| return (view.hotAt(position) orelse return &.{}).pass;
        return self.summaries[position].notes.pass;
    }

    /// The positions of the functions the function at `position` names. A summary decoded from a payload leaves `uses.callees` empty and
    /// this finds them by key, so a reader that wants them asks here.
    pub fn calleesAt(self: *const Index, position: u32) []const u32 {
        if (self.sections) |view| return view.calleesAt(position);
        return self.summaries[position].uses.callees;
    }

    /// The positions of the functions the function at `position` names as values (each also among its callees). A summary decoded from a
    /// payload leaves `uses.values` empty, like `uses.callees`, and a reader asks here; a function that names none costs one flag read.
    pub fn valuesAt(self: *const Index, position: u32) []const u32 {
        if (self.sections) |view| return view.valuesAt(position);
        return self.summaries[position].uses.values;
    }

    /// The region of the function at `position` (its length, digest and the names its syntax references), without decoding the rest.
    pub fn regionAt(self: *const Index, position: u32) Region {
        if (self.sections) |view| return view.regionAt(position);
        return self.summaries[position].region;
    }

    /// The stable key of the function at `position`.
    pub fn keyAt(self: *const Index, position: u32) []const u8 {
        if (self.sections) |view| return view.keyAt(position);
        return self.summaries[position].key;
    }

    /// Position of the summary with this stable key, or null.
    pub fn find(self: *const Index, key: []const u8) ?u32 {
        if (self.sections) |view| return view.find(key);
        return self.by_key.get(key);
    }

    /// `find`, trying position `hint` first: the table lists the functions in the order the last program had, so the function after the
    /// last one found is usually the next one asked for, and a compare of two keys in sequential memory replaces a hash probe. Keys are
    /// unique in a decoded table, so the answer is the one `find` gives.
    pub fn findNear(self: *const Index, key: []const u8, hint: u32) ?u32 {
        if (hint < self.count() and std.mem.eql(u8, self.keyAt(hint), key)) return hint;
        return self.find(key);
    }

    /// Whether `sections`, the cut of a produced table, is this table exactly (every section is the one stored in its place): nothing then
    /// needs to be encoded or written.
    pub fn isTable(self: *const Index, sections: []const types.OutSection) bool {
        const view = self.sections orelse return false;
        return view.sameAs(sections);
    }

    /// The name of the record that id `local` of `summary_position`'s `uses.records` names.
    pub fn recordName(self: *const Index, summary_position: u32, local: u32) []const u8 {
        if (self.sections) |view| return view.recordOf(summary_position, local).name;
        return self.records[local];
    }

    /// The shape digest the table held for that record.
    pub fn recordShape(self: *const Index, summary_position: u32, local: u32) [32]u8 {
        if (self.sections) |view| return view.recordOf(summary_position, local).shape;
        return self.record_shapes[local];
    }

    /// How many records the table lists: the ids of `uses.records` are below it.
    pub fn recordCount(self: *const Index) usize {
        if (self.sections) |view| return view.recordCount();
        return self.records.len;
    }

    /// The whole table decoded: every summary, one list of records, `uses.records`, `uses.callees` and `uses.values` as positions in the table. For
    /// tests and tools that read a table whole.
    pub fn table(self: *const Index, allocator: std.mem.Allocator) std.mem.Allocator.Error!Table {
        const view = self.sections orelse return .{ .records = self.records, .record_shapes = self.record_shapes, .summaries = self.summaries };
        const names = try allocator.alloc([]const u8, view.recordCount());
        const shapes = try allocator.alloc([32]u8, names.len);
        for (names, shapes, 0..) |*name, *shape, id| {
            const record = view.recordById(@intCast(id));
            name.* = record.name;
            shape.* = record.shape;
        }
        const out = try allocator.alloc(Summary, view.functionCount());
        for (out, 0..) |*entry, position| {
            entry.* = view.at(@intCast(position)).*;
            entry.uses.callees = view.calleesAt(@intCast(position));
            entry.uses.values = view.valuesAt(@intCast(position));
        }
        return .{ .records = names, .record_shapes = shapes, .summaries = out };
    }
};

/// Prepared declaration identities shared with demand-driven lowering hosts.
pub const Prepared = semantic_key.Prepared;

/// A lowering host's proof that a stored artifact can replace one checked body.
/// The omission mask records actual skipped bodies by ordinary instance index.
pub const Demand = struct {
    context: *const anyopaque,
    allow: *const fn (context: *const anyopaque, key: []const u8, context_digest: [32]u8, region_digest: [32]u8) bool,
    /// The host's answer for a whole module, when it has one (G2p): `out[i]` is set for each member `i` of `group` whose `allow` would answer
    /// true. The return is false when the host holds no record for this module's signature and file, and `out` is then untouched. The
    /// planner asks `allow` for every candidate a set bit did not cover, so a host that answers less than it could costs time, never a result.
    allow_module: ?*const fn (context: *const anyopaque, group: semantic_key.ModuleGroup, out: []bool) bool = null,
    /// Whether a generic template's judgment at its declaration is proven under the stable key `key`, the judgment's dependency
    /// digest and the template's region digest (W3 step 2, `template_stand_ins.judgmentContext`): `check` then makes none of its
    /// stand-in instances. Null when the host keeps no such proofs; every template is then judged.
    judged: ?*const fn (context: *const anyopaque, key: []const u8, context_digest: [32]u8, region_digest: [32]u8) bool = null,
    /// Bind the fresh source catalog once before consulting body receipts.
    /// Hosts use it to prove debug locations outside an unchanged body.
    prepare_sources: ?*const fn (*const anyopaque, source.Source) error{OutOfMemory}!void = null,
    omitted: []bool = &.{},
    /// Whether the host's artifacts read callees' bodies, so that a body edit invalidates the transitive consumers (their trees are
    /// checked or replayed, and the facts of the edited function are not compared with the stored ones). The passes read the callees'
    /// declarations alone, whatever the host says (G2n); the lowering host sets this false: a lowered function reads its callees'
    /// signatures, and the allocation contracts keep what they read concrete (`allocation_contracts`).
    body_dependencies: bool = true,
    /// Whether the host's artifacts read no fact of an edited body: the check then does not hold the facts of a body whose text changed
    /// against the old ones (a change would repeat the whole check), because nothing that stands in reads them.
    facts_unread: bool = false,
    /// Builds retain bounded bodies and callees for Core allocation checks.
    /// Ownership-only validation has no allocation contract to evaluate.
    allocation_contracts: bool = true,
};

/// One `W_COPY_MOVE` hint `check` judges against the callers (FR14b): the function that holds it (an instance), whether its
/// advice is a `from` result (`result`) or an `own` parameter, and the parameter's position. `store` marks the target of a
/// `W_COPY_FOR_STORE` warning, whose callers must also pass a new value or a markable name (`copy_for_store.callerMarks`).
/// `strict` marks the target of a `W_COPY_RETURNED` warning, which a caller refused for any reason keeps, its own undeclared
/// borrowed return included: the repair edits no caller.
pub const HintTarget = struct { callee: usize, result: bool, position: usize, store: bool = false, strict: bool = false };

/// One caller's answer for one hint: whether it keeps what the hint would take.
pub const CallerFact = struct { caller: usize, keeps: bool };

/// The ownership check's answers the `W_COPY_MOVE` filter needs, which the front end cannot compute itself: for each target,
/// every caller with a checked body and its answer (`single_owner.callerFacts`). A session that runs `check` sets it, and the
/// check then judges its hints itself, storing each checked caller's answers in its summary (`Keep`).
pub const CopyMoveJudge = struct {
    context: *const anyopaque,
    facts: *const fn (context: *const anyopaque, allocator: std.mem.Allocator, program: @import("typed.zig").Program, src: source.Source, targets: []const HintTarget) error{OutOfMemory}![]const []const CallerFact,
};

/// Optional declared-interface and demand-lowering policies for one request.
pub const Policy = struct {
    declared: bool = false,
    demand: ?Demand = null,
    /// Whether a summary that cannot stand in whole (a constant, a function naming a type interned while it was checked) may stand in
    /// for its passes alone: the cross-function facts and the pass warnings are taken from it and its body is checked as usual (G2k).
    passes: bool = true,
    /// Whether the host asks the check for the trees of bodies that it restores from the checked-body store when their keys stand
    /// (`Session.checkBodiesOf`): the stored tree of a body a summary stands in for is then read back, so the check keeps writing it.
    restores_trees: bool = false,
    /// The `W_COPY_MOVE` filter's judge, for a command that prints those hints (`check`); null for a build or a test.
    copy_moves: ?CopyMoveJudge = null,
    /// Verify sampling of the pass stand-in: one summary in `every` that would stand in for its passes alone is checked instead
    /// and compared with what it holds (its facts and its warnings). `compared` and `mismatched` are the planner's answer.
    verify: struct { every: u32 = 0, compared: u32 = 0, mismatched: u32 = 0, first: []const u8 = "" } = .{},
};

/// One check request's summary state, carried by the semantic cache context.
pub const Request = struct {
    /// Summaries of this entry's last successful check; null checks every body.
    previous: ?*const Index = null,
    /// This check's summaries, set when it succeeds; the host persists them.
    produced: ?Table = null,
    /// Set when a stand-in attempt met a changed cross-function fact (or a
    /// diagnostic it cannot reproduce exactly) and must be repeated in full.
    retry: bool = false,
    /// Bodies a summary stood in for in the check that produced the result.
    stood_in: usize = 0,
    /// A command that lowers the checked program needs every body's checked
    /// tree: its bodies are all checked, and summaries stand in only for the
    /// cross-function facts (and the pass diagnostics) of unchanged ones.
    body_policy: enum { summaries, concrete, allocation_contracts } = .summaries,
    /// The request's prepared declaration identities (stable keys,
    /// dependency contexts, region digests), kept for the build's
    /// lowering-free unit reuse (`EMIT-STANDIN-1`); allocated in the check's arena.
    prepared: ?semantic_key.Prepared = null,
    /// MODULE-INTERFACE-1: `previous` holds the declared functions of imported
    /// module interfaces, whose bodies the compilation does not have. Each one
    /// stands in by its stable key alone, with the facts its interface carries.
    policy: Policy = .{},
};

/// Convert the passes' in-memory facts to the persisted shape.
pub fn fromFact(fact: origins.Fact) Fact {
    return .{
        .mutates = fact.summary.mutates,
        .mutates_unknown = fact.summary.mutates_unknown,
        .return_origin = fact.summary.return_origin,
        .inferred = .{ .writes = fact.summary.writes, .external = fact.summary.external },
    };
}

/// Convert persisted facts back to the passes' shape; witness spans stay empty.
pub fn toFact(fact: Fact) origins.Fact {
    return .{ .summary = .{
        .return_origin = fact.return_origin,
        .mutates = fact.mutates,
        .mutates_unknown = fact.mutates_unknown,
        .writes = fact.inferred.writes,
        .external = fact.inferred.external,
    } };
}

/// Whether two persisted facts are identical.
pub fn sameFact(a: Fact, b: Fact) bool {
    return origins.sameSummary(toFact(a).summary, toFact(b).summary);
}

/// The names a table recorded for one function, offered to dependency-key
/// preparation while the function's region digest is unchanged.
pub fn recall(index: *const Index) semantic_key.Recall {
    return .{ .context = index, .names = recalledNames };
}

fn recalledNames(context: *const anyopaque, key: []const u8, digest: [32]u8) ?[]const semantic_key.Name {
    const index: *const Index = @ptrCast(@alignCast(context));
    const position = index.find(key) orelse return null;
    const stored = index.regionAt(position);
    if (!std.mem.eql(u8, &stored.digest, &digest)) return null;
    return stored.names;
}

/// Whether a diagnostic can be stored against the region `[start, end)`: its
/// span lies inside, it carries no related, provenance or trace notes that
/// could point outside the function, and every edit of its repair lies inside too.
pub fn storable(item: diagnostic.Diagnostic, region: source.Span) bool {
    if (item.related != null or item.provenance.origin != null or item.provenance.requirement != null or item.provenance.obligation != null) return false;
    if (item.provenance.fix) |fix| {
        for (0..fix.count()) |position| {
            const edit = fix.at(position).span;
            if (edit.start < region.start or edit.end > region.end or edit.start > edit.end) return false;
        }
    }
    if (item.stack.len != 0) return false;
    return item.span.start >= region.start and item.span.end <= region.end and item.span.start <= item.span.end;
}

/// Store one storable diagnostic relative to `region_start`.
pub fn noteOf(allocator: std.mem.Allocator, item: diagnostic.Diagnostic, region_start: usize) std.mem.Allocator.Error!Note {
    var edits: []FixEdit = &.{};
    if (item.provenance.fix) |fix| {
        edits = try allocator.alloc(FixEdit, fix.count());
        for (edits, 0..) |*edit, position| {
            const found = fix.at(position);
            edit.* = .{ .start = @intCast(found.span.start - region_start), .end = @intCast(found.span.end - region_start), .text = found.text };
        }
    }
    return .{
        .code = item.code,
        .severity = item.severity,
        .start = @intCast(item.span.start - region_start),
        .end = @intCast(item.span.end - region_start),
        .message = item.message,
        .rule = item.provenance.rule,
        .fix = edits,
    };
}

/// Rebuild the diagnostic a note stands for at the region's current offset. The diagnostic owns its text: a note of a table decoded from a
/// payload borrows the payload's bytes, and a diagnostic is rendered when the check is over.
pub fn diagnosticOf(allocator: std.mem.Allocator, note: Note, region_start: usize) std.mem.Allocator.Error!diagnostic.Diagnostic {
    var fix: ?diagnostic.Fix = null;
    if (note.fix.len != 0) {
        const edits = try allocator.alloc(diagnostic.Edit, note.fix.len);
        for (edits, note.fix) |*edit, stored| edit.* = .{ .span = .{ .start = region_start + stored.start, .end = region_start + stored.end }, .text = try allocator.dupe(u8, stored.text) };
        fix = .{ .edit = edits[0], .more = edits[1..] };
    }
    return .{
        .code = try allocator.dupe(u8, note.code),
        .severity = note.severity,
        .span = .{ .start = region_start + note.start, .end = region_start + note.end },
        .message = try allocator.dupe(u8, note.message),
        .provenance = .{ .rule = note.rule, .fix = fix },
    };
}

/// Serialize a summary table with its format version, cut into one section per module.
pub fn encode(allocator: std.mem.Allocator, table: Table) std.mem.Allocator.Error![]u8 {
    return sections_mod.encodeTable(allocator, table, null, .{});
}

/// `encode`, with the buffer sized for a table about as large as `hint` says (the bytes are the same).
pub fn encodeSized(allocator: std.mem.Allocator, table: Table, hint: SizeHint) std.mem.Allocator.Error![]u8 {
    return sections_mod.encodeTable(allocator, table, null, hint);
}

/// `encodeSized`, where a section of `table` marked `reuse` is copied from `previous`, the table the check started from.
pub fn encodeFrom(allocator: std.mem.Allocator, table: Table, previous: ?*const Index, hint: SizeHint) std.mem.Allocator.Error![]u8 {
    return sections_mod.encodeTable(allocator, table, if (previous) |index| index.sections else null, hint);
}

/// Decode a payload into an index owned by `allocator` (an arena: a failed decode leaves its partial storage to the arena). A malformed,
/// foreign or inconsistent payload is null, and the caller checks every body. The index borrows `payload`, which the caller keeps alive
/// for as long as the index is used; only the directory is read now, and a section is checked and decoded when something asks for it.
pub fn decode(allocator: std.mem.Allocator, payload: []const u8) ?Index {
    const view = sections_mod.Sections.open(allocator, payload) orelse return null;
    return .{ .sections = view, .size = .{ .bytes = payload.len } };
}
