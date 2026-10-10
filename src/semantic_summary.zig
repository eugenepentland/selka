//! Per-function check summaries: what `check` needs to stand in for an unchanged
//! ordinary body without checking it or materializing its checked tree.
//!
//! A summary is recorded for every ordinary function of a successful check. It
//! names the function by its stable declaration key and proves the body
//! unchanged by the function's dependency context (the digest `semantic_key`
//! computes over every declaration the signature and body reference) and a
//! BLAKE3 digest of its declaration region. It carries the facts the
//! cross-function passes read about the function — its propagated effect mask
//! and mutation summary — the diagnostics the function produced, with spans
//! relative to its region, and the functions its body names. A later check may
//! stand the summary in for the body only while those cross-function facts stay
//! exactly as stored for every function it re-checks; the check itself enforces
//! that and otherwise repeats in full.
const std = @import("std");
const diagnostic = @import("diagnostic.zig");
const origins = @import("origins.zig");
const effect_set = @import("effect_set.zig");
const source = @import("source.zig");
const codec = @import("persist_codec.zig");
const semantic_key = @import("semantic_key.zig");

/// Payload version; bump for any layout or meaning change so old payloads miss.
pub const format_version = "check-summaries-v8";

/// One stored diagnostic without related notes, its span relative to the start
/// of its function's declaration region.
pub const Note = struct {
    code: []const u8,
    severity: diagnostic.Severity,
    start: u32,
    end: u32,
    message: []const u8,
};

/// Diagnostics one function contributed: those appended while its body was
/// checked, and the warnings the whole-program passes reported inside it.
pub const Notes = struct { body: []const Note = &.{}, pass: []const Note = &.{} };

/// Length and BLAKE3 digest of one declaration region's bytes, and the names
/// its syntax references (which those bytes determine).
pub const Region = struct { len: u32, digest: [32]u8, names: []const semantic_key.Name = &.{} };

/// The persisted shape of `origins.Fact`: the propagated effect mask and the
/// mutation summary without its witness spans, which only locate diagnostics.
pub const Fact = struct {
    graph_mask: effect_set.Mask = 0,
    mutates: origins.Mask = 0,
    mutates_unknown: bool = false,
    return_origin: origins.Origin = .{},
    inferred: struct { writes: bool = false, external: bool = false } = .{},
};

/// What one checked body reached besides its own declaration: the functions
/// it calls and the catalog records its checked tree touched.
pub const Uses = struct {
    /// Positions in the same summary table of the functions the body names.
    callees: []const u32 = &.{},
    /// Positions in the table's record list of the records the tree touched.
    records: []const u32 = &.{},
    /// `combineShapes` over those records' transitive shape digests. A record
    /// reached only through a field, element or return type is still touched,
    /// so a body is never stood in over a record whose shape changed.
    shape: [32]u8 = @splat(0),
};

/// One ordinary function's summary. `stubbable` is false for a function that
/// every check re-checks (the entry point, constants, conversions, host
/// declarations, and bodies whose checked tree names a specialization, a lambda
/// or a type interned while checking); its facts still bound the functions that
/// call it.
pub const Summary = struct {
    key: []const u8,
    context: [32]u8,
    region: Region,
    fact: Fact,
    notes: Notes = .{},
    uses: Uses = .{},
    stubbable: bool,
};

/// One entry's summaries and the names of the records they touched.
pub const Table = struct {
    records: []const []const u8 = &.{},
    summaries: []const Summary = &.{},
};

/// One touched record: its catalog name and transitive shape digest.
pub const Shape = struct { name: []const u8, digest: [32]u8 };

/// The digest over a body's touched records, independent of their order.
pub fn combineShapes(shapes: []Shape) [32]u8 {
    std.mem.sort(Shape, shapes, {}, shapeBefore);
    var hash = std.crypto.hash.Blake3.init(.{});
    hash.update("touched-shapes-v1");
    for (shapes) |shape| {
        var length: [8]u8 = undefined;
        std.mem.writeInt(u64, &length, shape.name.len, .little);
        hash.update(&length);
        hash.update(shape.name);
        hash.update(&shape.digest);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

fn shapeBefore(_: void, a: Shape, b: Shape) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

/// A decoded summary table with its key index.
pub const Index = struct {
    summaries: []const Summary = &.{},
    records: []const []const u8 = &.{},
    by_key: std.StringHashMapUnmanaged(u32) = .empty,

    /// Position of the summary with this stable key, or null.
    pub fn find(self: *const Index, key: []const u8) ?u32 {
        return self.by_key.get(key);
    }
};

/// Prepared declaration identities shared with demand-driven lowering hosts.
pub const Prepared = semantic_key.Prepared;

/// A lowering host's proof that a stored artifact can replace one checked body.
/// The omission mask records actual skipped bodies by ordinary instance index.
pub const Demand = struct {
    context: *const anyopaque,
    allow: *const fn (context: *const anyopaque, key: []const u8, context_digest: [32]u8, region_digest: [32]u8) bool,
    /// Bind the fresh source catalog once before consulting body receipts.
    /// Hosts use it to prove debug locations outside an unchanged body.
    prepare_sources: ?*const fn (*const anyopaque, source.Source) error{OutOfMemory}!void = null,
    omitted: []bool = &.{},
};

/// Optional declared-interface and demand-lowering policies for one request.
pub const Policy = struct { declared: bool = false, demand: ?Demand = null };

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
        .graph_mask = fact.graph_mask,
        .mutates = fact.summary.mutates,
        .mutates_unknown = fact.summary.mutates_unknown,
        .return_origin = fact.summary.return_origin,
        .inferred = .{ .writes = fact.summary.writes, .external = fact.summary.external },
    };
}

/// Convert persisted facts back to the passes' shape; witness spans stay empty.
pub fn toFact(fact: Fact) origins.Fact {
    return .{ .graph_mask = fact.graph_mask, .summary = .{
        .return_origin = fact.return_origin,
        .mutates = fact.mutates,
        .mutates_unknown = fact.mutates_unknown,
        .writes = fact.inferred.writes,
        .external = fact.inferred.external,
    } };
}

/// Whether two persisted facts are identical.
pub fn sameFact(a: Fact, b: Fact) bool {
    return std.meta.eql(a, b);
}

/// The names a table recorded for one function, offered to dependency-key
/// preparation while the function's region digest is unchanged.
pub fn recall(index: *const Index) semantic_key.Recall {
    return .{ .context = index, .names = recalledNames };
}

fn recalledNames(context: *const anyopaque, key: []const u8, digest: [32]u8) ?[]const semantic_key.Name {
    const index: *const Index = @ptrCast(@alignCast(context));
    const position = index.find(key) orelse return null;
    const stored = index.summaries[position].region;
    if (!std.mem.eql(u8, &stored.digest, &digest)) return null;
    return stored.names;
}

/// Whether a diagnostic can be stored against the region `[start, end)`: its
/// span lies inside, and it carries no related, provenance or trace notes that
/// could point outside the function.
pub fn storable(item: diagnostic.Diagnostic, region: source.Span) bool {
    if (item.related != null or item.provenance.origin != null or item.provenance.requirement != null or item.provenance.obligation != null) return false;
    if (item.stack.len != 0) return false;
    return item.span.start >= region.start and item.span.end <= region.end and item.span.start <= item.span.end;
}

/// Store one storable diagnostic relative to `region_start`.
pub fn noteOf(item: diagnostic.Diagnostic, region_start: usize) Note {
    return .{
        .code = item.code,
        .severity = item.severity,
        .start = @intCast(item.span.start - region_start),
        .end = @intCast(item.span.end - region_start),
        .message = item.message,
    };
}

/// Rebuild the diagnostic a note stands for at the region's current offset.
pub fn diagnosticOf(note: Note, region_start: usize) diagnostic.Diagnostic {
    return .{
        .code = note.code,
        .severity = note.severity,
        .span = .{ .start = region_start + note.start, .end = region_start + note.end },
        .message = note.message,
    };
}

/// Serialize a summary table with its format version.
pub fn encode(allocator: std.mem.Allocator, table: Table) std.mem.Allocator.Error![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write([]const u8, format_version);
    try writer.write(Table, table);
    return writer.bytes.toOwnedSlice(allocator);
}

/// Decode a payload into an index owned by `allocator` (an arena: a failed
/// decode leaves its partial storage to the arena). Any malformed, foreign or
/// inconsistent payload is null, and the caller checks every body.
pub fn decode(allocator: std.mem.Allocator, payload: []const u8) ?Index {
    var reader = codec.Reader.init(allocator, payload);
    const version = reader.read([]const u8) catch return null;
    if (!std.mem.eql(u8, version, format_version)) return null;
    const table = reader.read(Table) catch return null;
    if (!reader.done()) return null;
    const summaries = table.summaries;
    var index: Index = .{ .summaries = summaries, .records = table.records };
    index.by_key.ensureTotalCapacity(allocator, @intCast(summaries.len)) catch return null;
    for (summaries, 0..) |summary, position| {
        for (summary.uses.callees) |callee| if (callee >= summaries.len) return null;
        for (summary.uses.records) |record| if (record >= table.records.len) return null;
        const entry = index.by_key.getOrPutAssumeCapacity(summary.key);
        // Keys are unique in a table this compiler wrote; a duplicate is foreign.
        if (entry.found_existing) return null;
        entry.value_ptr.* = @intCast(position);
    }
    return index;
}
