//! Independently owned function snapshots share immutable source generations.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const copy = @import("semantic_copy.zig");
const diagnostic = @import("diagnostic.zig");
const effect_set = @import("effect_set.zig");

/// One stable function identity exchanged for a fresh catalog ordinal at lookup time.
pub const FunctionRef = struct { id: typed.FunctionId, key: []const u8 };
/// One stable nominal-type identity exchanged for a fresh catalog ordinal.
pub const RecordRef = struct { index: usize, key: []const u8 };
/// Relocatable declaration facts retained for one checked function.
pub const Identity = struct { key: []const u8, context: [32]u8, body: source.Span, region: source.Span, checked_contract: [32]u8 = @splat(0) };
/// One persisted body-local diagnostic/warning. Warnings are derived from the
/// checked locals at snapshot time; the fresh binding pass still relocates and
/// re-emits them, while the stored copy keeps the durable entry self-describing.
pub const Note = struct {
    code: []const u8,
    severity: diagnostic.Severity,
    span: source.Span,
    message: []const u8,
    related: ?diagnostic.Related = null,
    provenance: ?diagnostic.Related = null,
};
/// Declaration dependencies and catalog cardinalities of one retained snapshot.
pub const Metadata = struct {
    identity: Identity,
    old_function_count: usize,
    old_record_count: usize,
    function_refs: []const FunctionRef,
    record_refs: []const RecordRef,
    notes: []const Note = &.{},
};
/// Inputs for `Entry.create`; bundles the changing snapshot facts.
pub const Spec = struct { identity: Identity, function_refs: []const FunctionRef, record_refs: []const RecordRef };

/// Source bytes and the optional shared immutable generation backing them.
pub const SourceRef = struct {
    generation: ?*Generation = null,
    old_len: usize = 0,
    body_bytes: []const u8 = &.{},
    region_bytes: []const u8 = &.{},
};
/// Reference counts are coordinator-owned; no cache mutation is concurrent.
pub const Generation = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    bytes: []const u8,
    bodies: []const source.Span,
    references: usize = 1,
    /// The returned generation starts with one temporary construction reference.
    pub fn create(allocator: std.mem.Allocator, bytes: []const u8, bodies: []const source.Span) std.mem.Allocator.Error!*Generation {
        const generation = try allocator.create(Generation);
        errdefer allocator.destroy(generation);
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        generation.* = .{ .allocator = allocator, .arena = undefined, .bytes = try arena.allocator().dupe(u8, bytes), .bodies = try arena.allocator().dupe(source.Span, bodies) };
        generation.arena = arena;
        return generation;
    }
    /// Drop one entry or construction reference and release the last source snapshot.
    pub fn deinit(self: *Generation) void {
        self.references -= 1;
        if (self.references == 0) {
            const allocator = self.allocator;
            self.arena.deinit();
            allocator.destroy(self);
        }
    }
};
/// One local checked tree owns its metadata, stable dependency identities and
/// one source-generation reference.
pub const Entry = struct {
    arena: std.heap.ArenaAllocator,
    function: typed.Function,
    nodes: []const typed.Node,
    statements: []const typed.Statement,
    range: copy.Range,
    /// In-process entries borrow the immutable generation bytes; decoded entries
    /// own these slices through `arena`. Validation compares these bytes directly,
    /// so a persisted body never depends on a reconstructed whole-source buffer.
    source: SourceRef = .{},
    meta: Metadata,
    /// Clone only one changed function; unchanged cache entries transfer ownership directly.
    pub fn create(allocator: std.mem.Allocator, generation: *Generation, program: typed.Program, index: usize, range: copy.Range, spec: Spec) error{ OutOfMemory, InternalError }!Entry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const arena_allocator = arena.allocator();
        const mapper: @import("ast_copy.zig").Mapper = .{};
        const saved_function = mapper.value(arena_allocator, typed.Function, program.functions[index]) catch |err| return classify(err);
        const nodes = mapper.value(arena_allocator, []const typed.Node, program.nodes[range.nodes.start..range.nodes.end]) catch |err| return classify(err);
        const statements = mapper.value(arena_allocator, []const typed.Statement, program.statements[range.statements.start..range.statements.end]) catch |err| return classify(err);
        const notes = noteWarnings(arena_allocator, saved_function) catch |err| return classify(err);
        const function_refs = try arena_allocator.alloc(FunctionRef, spec.function_refs.len);
        for (spec.function_refs, function_refs) |ref, *out| out.* = .{ .id = ref.id, .key = try arena_allocator.dupe(u8, ref.key) };
        const record_refs = try arena_allocator.alloc(RecordRef, spec.record_refs.len);
        for (spec.record_refs, record_refs) |ref, *out| out.* = .{ .index = ref.index, .key = try arena_allocator.dupe(u8, ref.key) };
        const identity = Identity{
            .key = try arena_allocator.dupe(u8, spec.identity.key),
            .context = spec.identity.context,
            .body = spec.identity.body,
            .region = spec.identity.region,
            .checked_contract = spec.identity.checked_contract,
        };
        if (identity.body.start > identity.body.end or identity.body.end > generation.bytes.len) return error.InternalError;
        if (identity.region.start > identity.region.end or identity.region.end > generation.bytes.len) return error.InternalError;
        generation.references += 1;
        return .{
            .arena = arena,
            .function = saved_function,
            .nodes = nodes,
            .statements = statements,
            .range = range,
            .source = .{
                .generation = generation,
                .old_len = generation.bytes.len,
                .body_bytes = generation.bytes[identity.body.start..identity.body.end],
                .region_bytes = generation.bytes[identity.region.start..identity.region.end],
            },
            .meta = .{
                .identity = identity,
                .old_function_count = program.functions.len,
                .old_record_count = program.records.len,
                .function_refs = function_refs,
                .record_refs = record_refs,
                .notes = notes,
            },
        };
    }
    /// Release this function tree without invalidating other generation users.
    pub fn deinit(self: *Entry) void {
        self.arena.deinit();
        if (self.source.generation) |generation| generation.deinit();
    }
};
fn classify(err: anyerror) error{ OutOfMemory, InternalError } {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}

/// Derive the same binding warnings the fresh `warnBindings` pass emits, so the
/// durable body carries the body-local diagnostics that belong to it. Relocation
/// still re-renders them from the copied locals; this copy is validation data for
/// the persisted entry.
fn noteWarnings(allocator: std.mem.Allocator, function: typed.Function) error{OutOfMemory}![]const Note {
    if (function.policy.host != null) return &.{};
    var count: usize = 0;
    for (function.scope.locals) |local| {
        if (local.usage.temporary or local.usage.reads != 0) continue;
        count += 1;
    }
    if (count == 0) return &.{};
    const notes = try allocator.alloc(Note, count);
    var index: usize = 0;
    for (function.scope.locals) |local| {
        if (local.usage.temporary or local.usage.reads != 0) continue;
        notes[index] = .{
            .code = "W_UNUSED_BINDING",
            .severity = .warning,
            .span = local.declaration,
            .message = "binding is never read; use it or remove it, preserving initializer effects with `_ =` when needed",
        };
        index += 1;
    }
    return notes;
}
/// Count each source generation once, plus every independently owned tree arena.
pub fn retained(entries: []const Entry) usize {
    var bytes: usize = entries.len * @sizeOf(Entry);
    for (entries, 0..) |entry, i| {
        bytes += entry.arena.queryCapacity();
        const generation = entry.source.generation orelse continue;
        var first = true;
        for (entries[0..i]) |previous| if (previous.source.generation == generation) {
            first = false;
            break;
        };
        if (first) bytes += generation.arena.queryCapacity() + @sizeOf(Generation);
    }
    return bytes;
}

/// C3 symbolic-template entry kind. A symbolic entry shares the C2 durable
/// store but lives under its own stable-key namespace and payload version so it
/// can never be confused with (or overwrite) an ordinary checked body.
pub const symbolic_kind = "symbolic-template-v1";
/// Prefix applied to a declaration's stable key for symbolic entries. Ordinary
/// C2 entries use the bare key, so the two kinds occupy disjoint file keys. The
/// embedded version invalidates every retained abstract result when the
/// abstract-checker rules change.
pub const symbolic_key_prefix = "sym\x1fabstract-v1\x1f";

/// A source span stored relative to one declaration region. The relative form
/// survives unrelated text insertion/deletion above the declaration; the
/// region bytes themselves must still be byte-identical before a hit.
pub const RelativeSpan = struct {
    start: i64,
    end: i64,

    /// Convert an absolute span constrained to `region`, or null when outside.
    pub fn fromAbsolute(region: source.Span, span: source.Span) ?RelativeSpan {
        if (span.start < region.start or span.end > region.end or span.end < span.start) return null;
        return .{ .start = @intCast(span.start - region.start), .end = @intCast(span.end - region.start) };
    }
    /// Relocate back into a fresh region, or null when the offset no longer fits.
    pub fn toAbsolute(self: RelativeSpan, region: source.Span) ?source.Span {
        if (self.start < 0 or self.end < self.start) return null;
        const start = region.start + @as(usize, std.math.cast(usize, self.start) orelse return null);
        const end = region.start + @as(usize, std.math.cast(usize, self.end) orelse return null);
        if (start > region.end or end > region.end) return null;
        return .{ .start = start, .end = end };
    }
};
/// One related/provenance note with a region-relative span.
pub const RelativeNote = struct { span: RelativeSpan, message: []const u8 };
/// The optional attached notes of one diagnostic, grouped to keep the note
/// struct small while preserving the full diagnostic on relocation.
pub const SymbolicNotes = struct {
    related: ?RelativeNote = null,
    origin: ?RelativeNote = null,
    requirement: ?RelativeNote = null,
};
/// One abstract-check diagnostic or warning captured for a symbolic entry.
pub const SymbolicNote = struct {
    code: []const u8,
    severity: diagnostic.Severity,
    span: RelativeSpan,
    message: []const u8,
    notes: SymbolicNotes = .{},
};
/// One abstract call edge: the callee's stable declaration key plus the call site.
pub const SymbolicEdge = struct { callee: []const u8, span: RelativeSpan };

/// Stable identity fields of one symbolic entry.
pub const SymbolicIdentity = struct { kind: []const u8 = symbolic_kind, key: []const u8, context: [32]u8 };
/// Captured source intervals and bytes proving the declaration is unchanged.
pub const SymbolicSource = struct {
    old_len: usize,
    region: source.Span,
    body: source.Span,
    region_bytes: []const u8,
    body_bytes: []const u8,
};
/// Direct abstract facts produced by the body check for one function.
pub const SymbolicContract = struct {
    effect_mask: effect_set.Mask,
    mutation_mask: u16,
    mutation_writes: bool,
};
/// Persisted payload for one abstract-checked function. All slices are owned by
/// the entry arena; spans in `source.region`/`source.body` are absolute
/// positions in the captured source, while note/edge spans are relative to
/// `source.region.start`.
pub const StoredSymbolic = struct {
    identity: SymbolicIdentity,
    source: SymbolicSource,
    contract: SymbolicContract,
    notes: []const SymbolicNote,
    edges: []const SymbolicEdge,
};
/// One decoded or freshly captured abstract result. The arena owns every slice
/// borrowed by `payload`.
pub const SymbolicEntry = struct {
    arena: std.heap.ArenaAllocator,
    payload: StoredSymbolic,

    pub fn deinit(self: *SymbolicEntry) void {
        self.arena.deinit();
    }
};

/// Whether one symbolic payload is internally consistent. Called by the store
/// before a decoded entry can reach the checker; a false result is a miss.
pub fn validSymbolic(payload: StoredSymbolic, max_declarations: usize, max_entry_bytes: usize) bool {
    if (!std.mem.eql(u8, payload.identity.kind, symbolic_kind)) return false;
    if (payload.identity.key.len == 0 or payload.identity.key.len > max_entry_bytes) return false;
    if (payload.source.old_len == 0) return false;
    const region: source.Span = payload.source.region;
    const body: source.Span = payload.source.body;
    if (region.start > region.end or region.end > payload.source.old_len) return false;
    if (body.start > body.end or body.end > payload.source.old_len) return false;
    if (body.start < region.start or body.end > region.end) return false;
    if (payload.source.region_bytes.len != region.end - region.start) return false;
    if (payload.source.body_bytes.len != body.end - body.start) return false;
    if (payload.contract.effect_mask & ~effect_set.all != 0) return false;
    if (payload.notes.len > max_declarations or payload.edges.len > max_declarations) return false;
    const region_len = region.end - region.start;
    for (payload.notes) |note| {
        if (note.code.len == 0 or note.code.len > max_entry_bytes) return false;
        if (note.message.len == 0 or note.message.len > max_entry_bytes) return false;
        if (!symbolicSpanValid(note.span, region_len)) return false;
        for ([_]?RelativeNote{ note.notes.related, note.notes.origin, note.notes.requirement }) |maybe| if (maybe) |relative| {
            if (relative.message.len > max_entry_bytes) return false;
            if (!symbolicSpanValid(relative.span, region_len)) return false;
        };
    }
    for (payload.edges) |edge| {
        if (edge.callee.len == 0 or edge.callee.len > max_entry_bytes) return false;
        if (!symbolicSpanValid(edge.span, region_len)) return false;
    }
    return true;
}
fn symbolicSpanValid(span: RelativeSpan, region_len: usize) bool {
    if (span.start < 0 or span.end < span.start) return false;
    const start = std.math.cast(usize, span.start) orelse return false;
    const end = std.math.cast(usize, span.end) orelse return false;
    return end <= region_len and start <= end;
}
