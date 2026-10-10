//! Bounded little-endian fields shared by type/interface requests and replies.
const std = @import("std");
const value = @import("declaration_value.zig");
const Span = @import("source.zig").Span;
/// Maximum complete framed declaration exchange, in either direction.
pub const wire_limit = 64 * 1024 * 1024;
/// Wire allocation and format failures remain host failures.
pub const Error = error{ OutOfMemory, ComponentProtocol };
/// Checked writer whose allocation never grows beyond the declared wire budget.
pub const Writer = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8) = .empty,
    /// Release accumulated bytes on every success or failure path.
    pub fn deinit(self: *Writer) void {
        self.output.deinit(self.allocator);
    }
    /// Append bytes after checking the complete exchange size.
    pub fn raw(self: *Writer, bytes: []const u8) Error!void {
        if (bytes.len > wire_limit - self.output.items.len) return error.ComponentProtocol;
        try self.output.appendSlice(self.allocator, bytes);
    }
    /// Encode an unsigned value only when it fits the wire's u32 domain.
    pub fn integer(self: *Writer, number: usize) Error!void {
        const narrowed = std.math.cast(u32, number) orelse return error.ComponentProtocol;
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, narrowed, .little);
        try self.raw(&bytes);
    }
    /// Encode one canonical Boolean field.
    pub fn boolean(self: *Writer, yes: bool) Error!void {
        try self.integer(@intFromBool(yes));
    }
    /// Encode a length-delimited byte string without text transcoding.
    pub fn blob(self: *Writer, bytes: []const u8) Error!void {
        try self.integer(bytes.len);
        try self.raw(bytes);
    }
    /// Encode a source byte range.
    pub fn span(self: *Writer, location: Span) Error!void {
        try self.integer(location.start);
        try self.integer(location.end);
    }
    /// Encode all logical symbol fields, including canonical origin identity.
    pub fn symbol(self: *Writer, item: value.Symbol) Error!void {
        try self.blob(item.name);
        try self.integer(@backingInt(item.kind));
        try self.span(item.span);
        try self.boolean(item.exported);
        try self.boolean(item.owner != null);
        if (item.owner) |owner| try self.blob(owner);
        try self.boolean(item.restricted);
        try self.boolean(item.re_export != null);
        if (item.re_export) |origin| {
            try self.integer(origin.module);
            try self.integer(origin.symbol);
        }
    }
};
/// A cursor over a bounded reply; returned strings live in the caller's arena.
pub const Reader = struct {
    arena: *std.heap.ArenaAllocator,
    bytes: []const u8,
    at: usize = 0,
    string_bytes: usize = 0,
    /// Read an exact extent without overflow or truncation.
    pub fn take(self: *Reader, size: usize) Error![]const u8 {
        if (size > self.bytes.len - self.at) return error.ComponentProtocol;
        const result = self.bytes[self.at..][0..size];
        self.at += size;
        return result;
    }
    /// Read one little-endian u32 into the host index domain.
    pub fn integer(self: *Reader) Error!usize {
        const bytes = try self.take(4);
        return std.mem.readInt(u32, bytes[0..4], .little);
    }
    /// Reject all Boolean spellings except zero and one.
    pub fn boolean(self: *Reader) Error!bool {
        return switch (try self.integer()) {
            0 => false,
            1 => true,
            else => error.ComponentProtocol,
        };
    }
    /// Copy a bounded string, limiting aggregate owned name/diagnostic bytes.
    pub fn blob(self: *Reader) Error![]const u8 {
        const size = try self.integer();
        // Aggregate reply string ownership is admitted independently of source bytes.
        if (size > 8388608 - self.string_bytes) return error.ComponentProtocol;
        const bytes = try self.take(size);
        self.string_bytes += size;
        return self.arena.allocator().dupe(u8, bytes);
    }
    /// Decode a byte span whose range is validated in its source context later.
    pub fn span(self: *Reader) Error!Span {
        return .{ .start = try self.integer(), .end = try self.integer() };
    }
    /// Decode one symbol, requiring canonical enum, optional and Boolean fields.
    pub fn symbol(self: *Reader) Error!value.Symbol {
        const name = try self.blob();
        const kind = std.enums.fromInt(value.Kind, try self.integer()) orelse return error.ComponentProtocol;
        const location = try self.span();
        const exported = try self.boolean();
        const owner: ?[]const u8 = if (try self.boolean()) try self.blob() else null;
        const restricted = try self.boolean();
        const origin: ?value.Identity = if (try self.boolean()) .{ .module = try self.integer(), .symbol = try self.integer() } else null;
        return .{ .name = name, .kind = kind, .span = location, .exported = exported, .owner = owner, .restricted = restricted, .re_export = origin };
    }
    /// Read one diagnostic site with an explicit module identity.
    pub fn site(self: *Reader) Error!value.Site {
        return .{ .module = try self.integer(), .span = try self.span() };
    }
};
