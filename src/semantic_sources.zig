//! Exact original-file proofs for nonlocal spans in independently retained bodies.
const std = @import("std");
const source = @import("source.zig");
const copy = @import("semantic_copy.zig");

/// An immutable original file and its old interval in the merged source.
pub const Reference = struct { path: []const u8, before: source.Span, digest: [32]u8 };

/// One request owns the index and memo; all source text remains borrowed.
pub const Catalog = struct {
    allocator: std.mem.Allocator,
    src: source.Source,
    names: std.StringHashMapUnmanaged(usize) = .empty,
    digests: []?[32]u8,

    /// Index original paths, rejecting ambiguity rather than choosing an origin.
    pub fn init(allocator: std.mem.Allocator, src: source.Source) error{OutOfMemory}!Catalog {
        const count = @max(1, src.origins.len);
        var catalog: Catalog = .{ .allocator = allocator, .src = src, .digests = try allocator.alloc(?[32]u8, count) };
        errdefer catalog.deinit();
        @memset(catalog.digests, null);
        for (0..count) |index| {
            const entry = try catalog.names.getOrPut(allocator, catalog.path(index));
            entry.value_ptr.* = if (entry.found_existing) std.math.maxInt(usize) else index;
        }
        return catalog;
    }

    /// Release request indices when used outside an arena-owned session.
    pub fn deinit(self: *Catalog) void {
        self.names.deinit(self.allocator);
        self.allocator.free(self.digests);
    }

    fn path(self: *const Catalog, index: usize) []const u8 {
        return if (self.src.origins.len == 0) self.src.path else self.src.origins[index].original.path;
    }

    fn interval(self: *const Catalog, index: usize) source.Span {
        if (self.src.origins.len == 0) return .{ .start = 0, .end = self.src.bytes.len };
        const input = self.src.origins[index];
        // initMapped appends one newline per input. The proof includes it so
        // parser spans ending at the following input boundary stay bounded.
        return .{ .start = input.start, .end = input.start + input.original.bytes.len + 1 };
    }

    fn digest(self: *Catalog, index: usize) [32]u8 {
        if (self.digests[index]) |known| return known;
        const region = self.interval(index);
        var hash: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(self.src.bytes[region.start..region.end], &hash, .{});
        self.digests[index] = hash;
        return hash;
    }

    fn origin(self: *const Catalog, span: source.Span) ?usize {
        if (span.start > span.end or span.end > self.src.bytes.len) return null;
        if (self.src.origins.len == 0) return 0;
        var low: usize = 0;
        var high = self.src.origins.len;
        while (low < high) {
            const middle = low + (high - low) / 2;
            if (self.src.origins[middle].start <= span.start) low = middle + 1 else high = middle;
        }
        if (low == 0) return null;
        const index = low - 1;
        if (span.end > self.interval(index).end) return null;
        return index;
    }

    /// Keep proofs only for source spans outside the body's checked region.
    pub fn capture(self: *Catalog, allocator: std.mem.Allocator, region: source.Span, spans: *std.AutoHashMapUnmanaged(source.Span, void)) error{OutOfMemory}![]Reference {
        var seen: std.AutoHashMapUnmanaged(usize, void) = .empty;
        defer seen.deinit(allocator);
        var references: std.ArrayList(Reference) = .empty;
        errdefer references.deinit(allocator);
        var iterator = spans.keyIterator();
        while (iterator.next()) |span| {
            if (span.start >= region.start and span.end <= region.end) continue;
            const index = self.origin(span.*) orelse continue;
            if ((try seen.getOrPut(allocator, index)).found_existing) continue;
            try references.append(allocator, .{ .path = self.path(index), .before = self.interval(index), .digest = self.digest(index) });
        }
        std.mem.sort(Reference, references.items, {}, referenceBefore);
        return references.toOwnedSlice(allocator);
    }

    /// Supply only independently proven file segments; other spans still miss.
    pub fn segments(self: *Catalog, allocator: std.mem.Allocator, references: []const Reference, local: copy.Segment) error{OutOfMemory}![]copy.Segment {
        var mapped: std.ArrayList(copy.Segment) = .empty;
        errdefer mapped.deinit(allocator);
        var includes_local = false;
        for (references) |reference| {
            const index = self.names.get(reference.path) orelse continue;
            if (index == std.math.maxInt(usize)) continue;
            const current = self.interval(index);
            if (current.end - current.start != reference.before.end - reference.before.start) continue;
            const fresh = self.digest(index);
            if (!std.mem.eql(u8, &fresh, &reference.digest)) continue;
            try mapped.append(allocator, .{ .before = reference.before, .after = current.start });
            if (reference.before.start <= local.before.start and reference.before.end >= local.before.end) includes_local = true;
        }
        if (!includes_local) try mapped.append(allocator, local);
        std.mem.sort(copy.Segment, mapped.items, {}, segmentBefore);
        return mapped.toOwnedSlice(allocator);
    }
};

fn referenceBefore(_: void, a: Reference, b: Reference) bool {
    return a.before.start < b.before.start;
}
fn segmentBefore(_: void, a: copy.Segment, b: copy.Segment) bool {
    return a.before.start < b.before.start;
}

/// Reject malformed or overlapping retained intervals before any relocation.
pub fn valid(references: []const Reference, old_len: usize) bool {
    var end: usize = 0;
    for (references) |reference| {
        if (reference.before.start < end or reference.before.start > reference.before.end) return false;
        if (reference.before.end > old_len) return false;
        end = reference.before.end;
    }
    return true;
}
