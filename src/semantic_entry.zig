//! Independently owned function snapshots, each owning its own source slices.
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

/// Source bytes owned by one entry: its original length plus the body and
/// declaration-region slices used to prove the entry still matches fresh source.
/// Each entry copies only the two slices it needs, so retention accounting is a
/// plain per-entry sum and releasing one entry never invalidates another.
pub const SourceRef = struct {
    old_len: usize = 0,
    body_bytes: []const u8 = &.{},
    region_bytes: []const u8 = &.{},
};
/// One local checked tree owns its metadata, stable dependency identities and
/// the two source slices that validate it.
pub const Entry = struct {
    arena: std.heap.ArenaAllocator,
    function: typed.Function,
    nodes: []const typed.Node,
    statements: []const typed.Statement,
    range: copy.Range,
    /// In-process and decoded entries both own these slices through `arena`, so
    /// validation never depends on a reconstructed whole-source buffer and no
    /// entry keeps a sibling alive.
    source: SourceRef = .{},
    meta: Metadata,
    /// Clone only one changed function; unchanged cache entries transfer ownership directly.
    pub fn create(allocator: std.mem.Allocator, bytes: []const u8, program: typed.Program, index: usize, range: copy.Range, spec: Spec) error{ OutOfMemory, InternalError }!Entry {
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
        if (identity.body.start > identity.body.end or identity.body.end > bytes.len) return error.InternalError;
        if (identity.region.start > identity.region.end or identity.region.end > bytes.len) return error.InternalError;
        const body_bytes = try arena_allocator.dupe(u8, bytes[identity.body.start..identity.body.end]);
        const region_bytes = try arena_allocator.dupe(u8, bytes[identity.region.start..identity.region.end]);
        return .{
            .arena = arena,
            .function = saved_function,
            .nodes = nodes,
            .statements = statements,
            .range = range,
            .source = .{
                .old_len = bytes.len,
                .body_bytes = body_bytes,
                .region_bytes = region_bytes,
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
    /// Release this function tree and its copied source slices.
    pub fn deinit(self: *Entry) void {
        self.arena.deinit();
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
/// Count the entry rows plus every independently owned tree arena, including
/// the per-chunk bookkeeping nodes the arena allocator keeps in front of each
/// backing allocation. Source slices live in the same arena as their tree, so
/// this is a plain sum and the retained total is independent of sibling
/// entries.
pub fn retained(entries: []const Entry) usize {
    var bytes: usize = entries.len * @sizeOf(Entry);
    for (entries) |entry| bytes += arenaOwnedBytes(entry.arena);
    return bytes;
}

/// Owned bytes of one ordinary entry: its row plus the arena that owns the
/// copied tree, metadata, dependency keys and the two source slices, including
/// arena chunk bookkeeping.
pub fn entryCost(entry: Entry) usize {
    return @sizeOf(Entry) + arenaOwnedBytes(entry.arena);
}
/// Owned bytes of one symbolic entry arena (the row is counted by the table),
/// including arena chunk bookkeeping.
pub fn symbolicArenaBytes(entry: SymbolicEntry) usize {
    return arenaOwnedBytes(entry.arena);
}
/// Owned bytes of one specialization entry arena (the row is counted by the
/// table), including arena chunk bookkeeping.
pub fn specializationArenaBytes(entry: SpecializationEntry) usize {
    return arenaOwnedBytes(entry.arena);
}
/// Actual owned bytes of an arena: `queryCapacity()` plus the per-chunk
/// `ArenaAllocator` node bookkeeping that `queryCapacity()` deliberately
/// excludes. This mirrors the pinned allocator layout (`used_list` plus any
/// retained `free_list` chunks) so the shared budget counts real backing
/// allocations, and it returns 0 for an empty arena.
pub fn arenaOwnedBytes(arena: std.heap.ArenaAllocator) usize {
    var bytes = arena.queryCapacity();
    const node_ptr = @TypeOf(arena.state.used_list);
    for ([_]node_ptr{ arena.state.used_list, arena.state.free_list }) |first_node| {
        var it = first_node;
        while (it) |node| : (it = node.next) {
            bytes += @sizeOf(@TypeOf(node.*));
        }
    }
    return bytes;
}
/// Exact backing allocation one `std.StringHashMapUnmanaged(usize)` owns at
/// `capacity` slots. The standard library keeps the map `Header`, the one-byte
/// metadata array and the aligned key/value arrays in a single allocation, so
/// this mirrors `HashMapUnmanaged.allocate` including alignment padding rather
/// than estimating a bare slot sum. Capacity 0 owns no allocation.
pub fn hashIndexBytes(capacity: usize) usize {
    if (capacity == 0) return 0;
    const Header = struct {
        values: [*]usize,
        keys: [*][]const u8,
        capacity: u32,
    };
    const header_align = @alignOf(Header);
    const key_align = if (@sizeOf([]const u8) == 0) 1 else @alignOf([]const u8);
    const val_align = if (@sizeOf(usize) == 0) 1 else @alignOf(usize);
    const max_align = @max(header_align, key_align, val_align);
    const meta_size = @sizeOf(Header) + capacity * @sizeOf(u8);
    const keys_start = std.mem.alignForward(usize, meta_size, key_align);
    const keys_end = keys_start + capacity * @sizeOf([]const u8);
    const vals_start = std.mem.alignForward(usize, keys_end, val_align);
    const vals_end = vals_start + capacity * @sizeOf(usize);
    return std.mem.alignForward(usize, vals_end, max_align);
}
/// Slot capacity `std.StringHashMapUnmanaged` allocates for `count` entries:
/// the standard library's 80% load factor and power-of-two growth, floored at
/// its minimum capacity of 8. An empty map owns no slots.
pub fn indexCapacityFor(count: usize) usize {
    if (count == 0) return 0;
    var capacity: u32 = @intCast((@as(u64, count) * 100) / 80 + 1);
    capacity = std.math.ceilPowerOfTwo(u32, capacity) catch std.math.maxInt(u32);
    return @max(@as(usize, capacity), 8);
}
/// Index bytes the standard hash map would own for `count` entries.
pub fn indexBytesFor(count: usize) usize {
    return hashIndexBytes(indexCapacityFor(count));
}

/// Callback binding a generic entry table to its owning cache's combined
/// retention policy. The entry modules do not import the cache module; the
/// cache installs this hook when it opens a session.
pub const RetentionHook = struct {
    owner: ?*anyopaque = null,
    reconcile: *const fn (?*anyopaque) void,
};

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
    /// Insertion order for the shared retention budget. Runtime-only; never
    /// part of the durable payload.
    sequence: u64 = 0,

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

/// C3 concrete-specialization entry kind. A specialization entry shares the C2
/// durable store but lives under its own stable-key namespace and payload
/// version so it can never be confused with an ordinary checked body or an
/// abstract symbolic template.
pub const specialization_kind = "specialization-v1";
/// Prefix applied to a canonical specialization fingerprint for durable keys.
/// Embedded version invalidates every retained concrete result when the
/// specialization encoding or remap rules change.
pub const specialization_key_prefix = "spec\x1fv1\x1f";

/// Whether one stored function reference names an ordinary declaration or a
/// concrete specialization. The stable key is a semantic declaration key for
/// ordinary functions and a canonical specialization fingerprint for
/// specializations; the old numeric ordinal is retained only to index the
/// relocation table, never as identity.
/// Whether one reference names an ordinary function or a specialization.
pub const FunctionRefKind = enum(u8) { ordinary = 0, specialization = 1 };
/// One stored function reference: `key` is a stable semantic declaration key
/// for ordinary functions and a canonical specialization fingerprint for
/// specializations; `id` only indexes the relocation table.
pub const SpecializationFunctionRef = struct { kind: FunctionRefKind, id: typed.FunctionId, key: []const u8 };

/// Stable identity of one concrete specialization. `fingerprint` is the
/// canonical key over template identity, ordered positional descriptors,
/// provider contracts, constraint dependencies, declared contracts and build
/// context. `template` is the defining template's stable declaration key.
pub const SpecializationIdentity = struct {
    kind: []const u8 = specialization_kind,
    /// Durable store key: `specialization_key_prefix` followed by `fingerprint`.
    key: []const u8,
    fingerprint: []const u8,
    template: []const u8,
    /// Template dependency digest; the durable entry is namespaced by it.
    context: [32]u8,
    /// Ordered positional descriptors (`T:<type>` or `L:<length>`).
    arguments: []const []const u8,
    lengths: []const ?usize,
};

/// The owned checked tree of one specialization, grouped to keep the payload
/// shape within the struct-field budget.
pub const SpecializationBody = struct {
    function: typed.Function,
    nodes: []const typed.Node,
    statements: []const typed.Statement,
    range: copy.Range,
};
/// Stable remap tables of one specialization tree.
pub const SpecializationRefs = struct {
    function_refs: []const SpecializationFunctionRef,
    record_refs: []const RecordRef,
};
/// Catalog cardinalities the stored reference ordinals were captured against.
pub const SpecializationCounts = struct { old_function_count: usize, old_record_count: usize };

/// Persisted payload for one checked concrete specialization. All slices are
/// owned by the entry arena. `source.region`/`source.body` are the defining
/// template's absolute intervals in the captured source; the checked tree's
/// node ids are absolute in that same source and are relocated on replay.
pub const StoredSpecialization = struct {
    identity: SpecializationIdentity,
    source: SymbolicSource,
    body: SpecializationBody,
    refs: SpecializationRefs,
    counts: SpecializationCounts,
};

/// One decoded or freshly captured concrete specialization. The arena owns
/// every slice borrowed by `payload`.
pub const SpecializationEntry = struct {
    arena: std.heap.ArenaAllocator,
    payload: StoredSpecialization,
    /// Insertion order for the shared retention budget. Runtime-only; never
    /// part of the durable payload.
    sequence: u64 = 0,

    pub fn deinit(self: *SpecializationEntry) void {
        self.arena.deinit();
    }
};

/// Whether one specialization payload is internally consistent. Called by the
/// store before a decoded entry can reach the checker; a false result is a
/// miss, never a trusted unchecked identity.
pub fn validSpecialization(payload: StoredSpecialization, max_declarations: usize, max_entry_bytes: usize) bool {
    if (!std.mem.eql(u8, payload.identity.kind, specialization_kind)) return false;
    if (payload.identity.key.len == 0 or payload.identity.key.len > max_entry_bytes) return false;
    if (payload.identity.fingerprint.len == 0 or payload.identity.fingerprint.len > max_entry_bytes) return false;
    if (payload.identity.template.len == 0 or payload.identity.template.len > max_entry_bytes) return false;
    if (payload.identity.arguments.len > max_declarations) return false;
    if (payload.identity.lengths.len != 0 and payload.identity.lengths.len != payload.identity.arguments.len) return false;
    for (payload.identity.arguments) |argument| {
        if (argument.len == 0 or argument.len > max_entry_bytes) return false;
    }
    const region: source.Span = payload.source.region;
    const body: source.Span = payload.source.body;
    if (payload.source.old_len == 0) return false;
    if (region.start > region.end or region.end > payload.source.old_len) return false;
    if (body.start > body.end or body.end > payload.source.old_len) return false;
    if (body.start < region.start or body.end > region.end) return false;
    if (payload.source.region_bytes.len != region.end - region.start) return false;
    if (payload.source.body_bytes.len != body.end - body.start) return false;
    if (payload.body.range.nodes.start > payload.body.range.nodes.end) return false;
    if (payload.body.range.nodes.end - payload.body.range.nodes.start != payload.body.nodes.len) return false;
    if (payload.body.range.statements.start > payload.body.range.statements.end) return false;
    if (payload.body.range.statements.end - payload.body.range.statements.start != payload.body.statements.len) return false;
    if (!validSpecializationRefs(payload.refs, payload.counts, max_declarations, max_entry_bytes)) return false;
    return true;
}
/// Validate the stored remap tables independently of the tree body.
fn validSpecializationRefs(refs: SpecializationRefs, counts: SpecializationCounts, max_declarations: usize, max_entry_bytes: usize) bool {
    if (counts.old_function_count > max_declarations or counts.old_record_count > max_declarations) return false;
    if (refs.function_refs.len > max_declarations or refs.record_refs.len > max_declarations) return false;
    for (refs.function_refs) |reference| {
        if (@backingInt(reference.id) >= counts.old_function_count) return false;
        if (reference.key.len == 0 or reference.key.len > max_entry_bytes) return false;
    }
    for (refs.record_refs) |reference| {
        if (reference.index >= counts.old_record_count) return false;
        if (reference.key.len == 0 or reference.key.len > max_entry_bytes) return false;
    }
    return true;
}

/// Inputs for one freshly checked concrete specialization. All slices are
/// borrowed for the duration of `SpecializationEntry.create`.
pub const SpecializationSpec = struct {
    identity: SpecializationIdentity,
    source: SymbolicSource,
    function_refs: []const SpecializationFunctionRef,
    record_refs: []const RecordRef,
    old_function_count: usize,
    old_record_count: usize,
};

/// Snapshot one freshly checked specialization tree into independently owned
/// arena storage. `index` selects the checked function in `program`; `range`
/// is its node/statement interval. Spans stay absolute in `program`'s source,
/// exactly like `Entry.create`, and are relocated on replay.
pub fn createSpecialization(
    allocator: std.mem.Allocator,
    program: typed.Program,
    index: usize,
    range: copy.Range,
    spec: SpecializationSpec,
) error{ OutOfMemory, InternalError }!SpecializationEntry {
    if (index >= program.functions.len) return error.InternalError;
    if (range.nodes.start > range.nodes.end or range.nodes.end > program.nodes.len) return error.InternalError;
    if (range.statements.start > range.statements.end or range.statements.end > program.statements.len) return error.InternalError;
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const a = arena.allocator();
    const mapper: @import("ast_copy.zig").Mapper = .{};
    const function = mapper.value(a, typed.Function, program.functions[index]) catch |err| return classify(err);
    const nodes = mapper.value(a, []const typed.Node, program.nodes[range.nodes.start..range.nodes.end]) catch |err| return classify(err);
    const statements = mapper.value(a, []const typed.Statement, program.statements[range.statements.start..range.statements.end]) catch |err| return classify(err);
    const function_refs = try a.alloc(SpecializationFunctionRef, spec.function_refs.len);
    for (spec.function_refs, function_refs) |reference, *out| out.* = .{ .kind = reference.kind, .id = reference.id, .key = try a.dupe(u8, reference.key) };
    const record_refs = try a.alloc(RecordRef, spec.record_refs.len);
    for (spec.record_refs, record_refs) |reference, *out| out.* = .{ .index = reference.index, .key = try a.dupe(u8, reference.key) };
    const arguments = try a.alloc([]const u8, spec.identity.arguments.len);
    for (spec.identity.arguments, arguments) |argument, *out| out.* = try a.dupe(u8, argument);
    const lengths = try a.dupe(?usize, spec.identity.lengths);
    const identity: SpecializationIdentity = .{
        .kind = specialization_kind,
        .key = try a.dupe(u8, spec.identity.key),
        .fingerprint = try a.dupe(u8, spec.identity.fingerprint),
        .template = try a.dupe(u8, spec.identity.template),
        .context = spec.identity.context,
        .arguments = arguments,
        .lengths = lengths,
    };
    const source_ref: SymbolicSource = .{
        .old_len = spec.source.old_len,
        .region = spec.source.region,
        .body = spec.source.body,
        .region_bytes = try a.dupe(u8, spec.source.region_bytes),
        .body_bytes = try a.dupe(u8, spec.source.body_bytes),
    };
    return .{
        .arena = arena,
        .payload = .{
            .identity = identity,
            .source = source_ref,
            .body = .{ .function = function, .nodes = nodes, .statements = statements, .range = range },
            .refs = .{ .function_refs = function_refs, .record_refs = record_refs },
            .counts = .{ .old_function_count = spec.old_function_count, .old_record_count = spec.old_record_count },
        },
    };
}
