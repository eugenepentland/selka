//! Deterministic partial provider transfers and lifetime counters for standard I/O acceptance.
const std = @import("std");
const language = @import("compiler.zig");
const resources = @import("external_resources.zig");
const CallError = @import("external_capabilities.zig").CallError;
/// One in-memory file, with a one-shot failed/stalled callback for retry checks.
pub const Provider = struct {
    input: []const u8 = "abc",
    progress: struct { position: usize = 0, output: [256]u8 = undefined, length: usize = 0 } = .{},
    calls: struct { read: usize = 0, write: usize = 0, acquire: usize = 0, release: usize = 0 } = .{},
    failure: struct { read: ?usize = null, write: ?usize = null, stalled: bool = false } = .{},
    live: bool = false,
    /// Return callbacks borrowing stable fixture storage.
    pub fn provider(self: *Provider) resources.Provider {
        return .{ .context = self, .acquire = acquire, .read = read, .write = write, .complete = complete, .release = release };
    }
    fn acquire(raw: *anyopaque, request: []const u8, _: resources.Permissions) CallError!u64 {
        const self: *Provider = @ptrCast(@alignCast(raw));
        if (!std.mem.eql(u8, request, "r:data") and !std.mem.eql(u8, request, "w:data")) return error.Denied;
        if (self.live) return error.Denied;
        self.calls.acquire += 1;
        self.live = true;
        return 0;
    }
    fn read(raw: *anyopaque, _: u64, bytes: []u8) CallError!resources.Read {
        const self: *Provider = @ptrCast(@alignCast(raw));
        const call = self.calls.read;
        self.calls.read += 1;
        if (self.failure.read == call) {
            if (self.failure.stalled) return .{ .length = 0, .eof = false };
            return error.Failed;
        }
        const length = @min(bytes.len, 2, self.input.len - self.progress.position);
        @memcpy(bytes[0..length], self.input[self.progress.position..][0..length]);
        self.progress.position += length;
        return .{ .length = length, .eof = self.progress.position == self.input.len };
    }
    fn write(raw: *anyopaque, _: u64, bytes: []const u8) CallError!usize {
        const self: *Provider = @ptrCast(@alignCast(raw));
        const call = self.calls.write;
        self.calls.write += 1;
        if (self.failure.write == call) {
            if (self.failure.stalled) return 0;
            return error.Failed;
        }
        const length = @min(bytes.len, 2, self.progress.output.len - self.progress.length);
        @memcpy(self.progress.output[self.progress.length..][0..length], bytes[0..length]);
        self.progress.length += length;
        return length;
    }
    fn complete(raw: *anyopaque, id: u64) CallError!void {
        release(raw, id);
    }
    fn release(raw: *anyopaque, _: u64) void {
        const self: *Provider = @ptrCast(@alignCast(raw));
        std.debug.assert(self.live);
        self.live = false;
        self.calls.release += 1;
    }
};
/// Load one caller while standard dependencies use their reserved embedded source.
pub const Source = struct {
    text: []const u8,
    /// Return a copied bounded main module or fail resolution.
    pub fn load(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) language.project.ReadError![]u8 {
        const self: *Source = @ptrCast(@alignCast(raw.?));
        if (!std.mem.eql(u8, path, "main.my")) return error.NotFound;
        if (self.text.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.text);
    }
};
