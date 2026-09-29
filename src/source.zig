//! Owned source and byte locations; diagnostic text borrows this storage.
/// Failures returned by initMapped; callers must handle these boundary errors.
pub const InitMappedError = error{
    EmptySourceMap,
    NestedSourceMap,
    OutOfMemory,
    Overflow,
};
/// Failures returned by mappedSpan; callers must handle these boundary errors.
pub const MappedSpanError = error{
    InvalidSourceIndex,
    InvalidSourceSpan,
};
/// Failures returned by originalSpan; callers must handle these boundary errors.
pub const OriginalSpanError = error{
    InvalidSourceSpan,
    NotMappedSource,
};

const std = @import("std");

/// Half-open byte range within source text.
pub const Span = struct {
    start: usize,
    end: usize,

    /// Join ordered source ranges from the start of a through the end of b.
    pub fn join(a: Span, b: Span) Span {
        return .{ .start = a.start, .end = b.end };
    }
};

/// Why an `embed_bytes`/`embed_str` path could or could not be read. Everything but
/// `ok` names the located diagnostic the checker reports at the literal.
pub const EmbedStatus = enum { unresolved, ok, invalid_path, absolute, escapes, missing, directory, too_large, unreadable };

/// One compile-time file read on behalf of an `embed_bytes("path")` or
/// `embed_str("path")` call in this source (`EMBED-1`). `literal` is the string
/// literal's span in this source's own coordinates, `path` its decoded text, and
/// `contents`/`digest` the file's bytes and BLAKE3 digest when `status` is `ok`; every
/// other status leaves both empty. Entries are sorted by `literal.start`.
pub const Embed = struct {
    literal: Span,
    path: []const u8,
    status: EmbedStatus = .unresolved,
    digest: [32]u8 = @splat(0),
    contents: []const u8 = &.{},
    /// Whether the call was `embed_str` rather than `embed_bytes`.
    text: bool = false,
};

/// Source path, owned bytes, line index, and optional origins for merged modules.
pub const Source = struct {
    path: []const u8,
    bytes: []const u8,
    line_starts: []const usize,
    origins: []const Origin = &.{},
    /// The files this source's embed calls read, resolved when it was loaded.
    embeds: []const Embed = &.{},
    /// Mark a compiler-owned test source that may spell reserved internal
    /// intrinsics. Guest and embedder sources never set this; only the parser's
    /// own unit tests reach it, so the public surface stays gated.
    trusted_intrinsics: bool = false,

    /// Offset and original source contributing a segment to merged source text.
    pub const Origin = struct { start: usize, original: Source };

    /// Copy source bytes/path and allocate a line index with the supplied allocator.
    pub fn init(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!Source {
        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);
        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);
        var starts: std.ArrayList(usize) = .empty;
        errdefer starts.deinit(allocator);
        try starts.append(allocator, 0);
        for (bytes, 0..) |byte, i| {
            if (byte == '\n') try starts.append(allocator, i + 1);
        }
        return .{ .path = owned_path, .bytes = owned_bytes, .line_starts = try starts.toOwnedSlice(allocator) };
    }

    /// Copy source bytes into one offset space without changing source spelling.
    /// Origin metadata borrows the inputs, which must outlive the returned Source.
    /// Caller owns returned bytes/path/line_starts/origins (normally in an arena).
    pub fn initMapped(allocator: std.mem.Allocator, inputs: []const Source) InitMappedError!Source {
        if (inputs.len == 0) return error.EmptySourceMap;
        var size: usize = 0;
        for (inputs) |input| {
            if (input.origins.len != 0) return error.NestedSourceMap;
            size = try std.math.add(usize, size, input.bytes.len);
            size = try std.math.add(usize, size, 1);
        }
        const bytes = try allocator.alloc(u8, size);
        defer allocator.free(bytes);
        const origins = try allocator.alloc(Origin, inputs.len);
        errdefer allocator.free(origins);
        var offset: usize = 0;
        for (inputs, origins) |input, *origin| {
            origin.* = .{ .start = offset, .original = input };
            @memcpy(bytes[offset..][0..input.bytes.len], input.bytes);
            offset += input.bytes.len;
            // Each EOF gets its own offset, including adjacent empty files.
            bytes[offset] = '\n';
            offset += 1;
        }
        var mapped = try init(allocator, "<project>", bytes);
        mapped.origins = origins;
        return mapped;
    }

    /// Convert a checked module-local span into the merged source coordinate space.
    pub fn mappedSpan(self: Source, input: usize, local: Span) MappedSpanError!Span {
        if (input >= self.origins.len) return error.InvalidSourceIndex;
        const origin = self.origins[input];
        if (local.start > local.end or local.end > origin.original.bytes.len) return error.InvalidSourceSpan;
        return .{ .start = origin.start + local.start, .end = origin.start + local.end };
    }

    fn originIndex(self: Source, offset: usize) ?usize {
        if (self.origins.len == 0) return null;
        var low: usize = 0;
        var high = self.origins.len;
        while (low + 1 < high) {
            const mid = low + (high - low) / 2;
            if (self.origins[mid].start <= offset) low = mid else high = mid;
        }
        return low;
    }

    /// Locate the original module and local span underlying a merged span.
    pub fn originalSpan(self: Source, global: Span) OriginalSpanError!struct { input: usize, span: Span } {
        const index = self.originIndex(global.start) orelse return error.NotMappedSource;
        const origin = self.origins[index];
        if (global.start > global.end or global.end > origin.start + origin.original.bytes.len) return error.InvalidSourceSpan;
        return .{ .input = index, .span = .{ .start = global.start - origin.start, .end = global.end - origin.start } };
    }

    /// The embed whose string literal starts at `span`, in this source's own
    /// coordinates or, for a merged source, in the merged offset space.
    pub fn embedAt(self: Source, span: Span) ?*const Embed {
        var embeds = self.embeds;
        var start = span.start;
        if (self.origins.len != 0) {
            const original = self.originalSpan(span) catch return null;
            embeds = self.origins[original.input].original.embeds;
            start = original.span.start;
        }
        var low: usize = 0;
        var high = embeds.len;
        while (low < high) {
            const mid = low + (high - low) / 2;
            if (embeds[mid].literal.start < start) low = mid + 1 else high = mid;
        }
        if (low < embeds.len and embeds[low].literal.start == start) return &embeds[low];
        return null;
    }

    /// The embeds whose string literals lie inside `span`, in source order: a
    /// declaration region's own files, which its cache keys must cover.
    pub fn embedsWithin(self: Source, span: Span) []const Embed {
        var embeds = self.embeds;
        var start = span.start;
        var end = span.end;
        if (self.origins.len != 0) {
            const original = self.originalSpan(span) catch return &.{};
            embeds = self.origins[original.input].original.embeds;
            start = original.span.start;
            end = original.span.end;
        }
        var first: usize = 0;
        var high = embeds.len;
        while (first < high) {
            const mid = first + (high - first) / 2;
            if (embeds[mid].literal.start < start) first = mid + 1 else high = mid;
        }
        var last = first;
        while (last < embeds.len and embeds[last].literal.end <= end) last += 1;
        return embeds[first..last];
    }

    /// Borrow the bytes covered by a valid source span.
    pub fn text(self: Source, span: Span) []const u8 {
        return self.bytes[span.start..span.end];
    }

    /// Original path, line/column, and source line text for a diagnostic location.
    pub const Location = struct { path: []const u8, line: usize, column: usize, text: []const u8 };

    /// Map a byte offset to its original source path and human-readable line/column.
    pub fn locate(self: Source, offset: usize) Location {
        if (self.originIndex(offset)) |index| {
            const origin = self.origins[index];
            return origin.original.locate(@min(offset - origin.start, origin.original.bytes.len));
        }
        return self.physicalLocation(offset);
    }

    /// Location in the combined byte buffer, for aggregate line metrics only.
    pub fn physicalLocation(self: Source, offset: usize) Location {
        const at = @min(offset, self.bytes.len);
        var low: usize = 0;
        var high = self.line_starts.len;
        while (low + 1 < high) {
            const mid = low + (high - low) / 2;
            if (self.line_starts[mid] <= at) low = mid else high = mid;
        }
        const start = self.line_starts[low];
        const end = if (low + 1 < self.line_starts.len) self.line_starts[low + 1] - 1 else self.bytes.len;
        return .{ .path = self.path, .line = low + 1, .column = at - start + 1, .text = std.mem.trimEnd(u8, self.bytes[start..end], "\r") };
    }
};
