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

    pub fn text(self: Source, span: Span) []const u8 {
        return self.bytes[span.start..span.end];
    }

    pub const Location = struct { line: usize, column: usize, text: []const u8 };

    pub fn locate(self: Source, offset: usize) Location {
        const at = @min(offset, self.bytes.len);
        var low: usize = 0;
        var high = self.line_starts.len;
        while (low + 1 < high) {
            const mid = low + (high - low) / 2;
            if (self.line_starts[mid] <= at) low = mid else high = mid;
        }
        const start = self.line_starts[low];
        const end = if (low + 1 < self.line_starts.len) self.line_starts[low + 1] - 1 else self.bytes.len;
        return .{ .line = low + 1, .column = at - start + 1, .text = std.mem.trimEnd(u8, self.bytes[start..end], "\r") };
    }
};
