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

/// Payload version; bump for any layout or meaning change so old payloads miss.
pub const format_version = "check-summaries-v1";

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

/// Length and BLAKE3 digest of one declaration region's bytes.
pub const Region = struct { len: u32, digest: [32]u8 };

/// The persisted shape of `origins.Fact`: the propagated effect mask and the
/// mutation summary without its witness spans, which only locate diagnostics.
pub const Fact = struct {
    graph_mask: effect_set.Mask = 0,
    mutates: u16 = 0,
    mutates_unknown: bool = false,
    return_positions: u16 = 0,
    return_unknown: bool = false,
    writes: bool = false,
    external: bool = false,
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
    /// Positions in the same summary table of the functions the body names.
    callees: []const u32 = &.{},
    stubbable: bool,
};

/// A decoded summary table with its key index.
pub const Index = struct {
    summaries: []const Summary = &.{},
    by_key: std.StringHashMapUnmanaged(u32) = .empty,

    /// Position of the summary with this stable key, or null.
    pub fn find(self: *const Index, key: []const u8) ?u32 {
        return self.by_key.get(key);
    }
};

/// One check request's summary state, carried by the semantic cache context.
pub const Request = struct {
    /// Summaries of this entry's last successful check; null checks every body.
    previous: ?*const Index = null,
    /// This check's summaries, set when it succeeds; the host persists them.
    produced: ?[]const Summary = null,
    /// Set when a stand-in attempt met a changed cross-function fact (or a
    /// diagnostic it cannot reproduce exactly) and must be repeated in full.
    retry: bool = false,
    /// Bodies a summary stood in for in the check that produced the result.
    stood_in: usize = 0,
};

/// Convert the passes' in-memory facts to the persisted shape.
pub fn fromFact(fact: origins.Fact) Fact {
    return .{
        .graph_mask = fact.graph_mask,
        .mutates = fact.summary.mutates,
        .mutates_unknown = fact.summary.mutates_unknown,
        .return_positions = fact.summary.return_origin.positions,
        .return_unknown = fact.summary.return_origin.unknown,
        .writes = fact.summary.writes,
        .external = fact.summary.external,
    };
}

/// Convert persisted facts back to the passes' shape; witness spans stay empty.
pub fn toFact(fact: Fact) origins.Fact {
    return .{ .graph_mask = fact.graph_mask, .summary = .{
        .return_origin = .{ .positions = fact.return_positions, .unknown = fact.return_unknown },
        .mutates = fact.mutates,
        .mutates_unknown = fact.mutates_unknown,
        .writes = fact.writes,
        .external = fact.external,
    } };
}

/// Whether two persisted facts are identical.
pub fn sameFact(a: Fact, b: Fact) bool {
    return std.meta.eql(a, b);
}

/// Length and digest of one region's bytes.
pub fn regionOf(bytes: []const u8) Region {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return .{ .len = @intCast(@min(bytes.len, std.math.maxInt(u32))), .digest = digest };
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
pub fn encode(allocator: std.mem.Allocator, summaries: []const Summary) std.mem.Allocator.Error![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write([]const u8, format_version);
    try writer.write([]const Summary, summaries);
    return writer.bytes.toOwnedSlice(allocator);
}

/// Decode a payload into an index owned by `allocator` (an arena: a failed
/// decode leaves its partial storage to the arena). Any malformed, foreign or
/// inconsistent payload is null, and the caller checks every body.
pub fn decode(allocator: std.mem.Allocator, payload: []const u8) ?Index {
    var reader = codec.Reader.init(allocator, payload);
    const version = reader.read([]const u8) catch return null;
    if (!std.mem.eql(u8, version, format_version)) return null;
    const summaries = reader.read([]const Summary) catch return null;
    if (!reader.done()) return null;
    var index: Index = .{ .summaries = summaries };
    index.by_key.ensureTotalCapacity(allocator, @intCast(summaries.len)) catch return null;
    for (summaries, 0..) |summary, position| {
        for (summary.callees) |callee| if (callee >= summaries.len) return null;
        const entry = index.by_key.getOrPutAssumeCapacity(summary.key);
        // Keys are unique in a table this compiler wrote; a duplicate is foreign.
        if (entry.found_existing) return null;
        entry.value_ptr.* = @intCast(position);
    }
    return index;
}
