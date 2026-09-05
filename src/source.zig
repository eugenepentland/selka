//! Owned source and byte locations; diagnostic text borrows this storage.
const std = @import("std");

pub const Span = struct {
    start: usize,
    end: usize,

    pub fn join(a: Span, b: Span) Span {
        return .{ .start = a.start, .end = b.end };
    }
};

pub const Source = struct {
    path: []const u8,
    bytes: []const u8,
    line_starts: []const usize,
    origins: []const Origin = &.{},

    pub const Origin = struct { start: usize, original: Source };

    pub fn init(allocator: std.mem.Allocator, path: []const u8, bytes: []const u8) !Source {
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
    pub fn initMapped(allocator: std.mem.Allocator, inputs: []const Source) !Source {
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

    pub fn mappedSpan(self: Source, input: usize, local: Span) !Span {
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

    pub fn originalSpan(self: Source, global: Span) !struct { input: usize, span: Span } {
        const index = self.originIndex(global.start) orelse return error.NotMappedSource;
        const origin = self.origins[index];
        if (global.start > global.end or global.end > origin.start + origin.original.bytes.len) return error.InvalidSourceSpan;
        return .{ .input = index, .span = .{ .start = global.start - origin.start, .end = global.end - origin.start } };
    }

    pub fn text(self: Source, span: Span) []const u8 {
        return self.bytes[span.start..span.end];
    }

    pub const Location = struct { path: []const u8, line: usize, column: usize, text: []const u8 };

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
