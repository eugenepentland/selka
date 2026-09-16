//! Independently owned function snapshots share immutable source generations.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const copy = @import("semantic_copy.zig");
const diagnostic = @import("diagnostic.zig");

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
