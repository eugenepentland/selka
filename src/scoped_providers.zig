//! Synchronous trusted adapters with directory-relative files and literal TCP allowlists.
const std = @import("std");
const external = @import("external_capabilities.zig");
const resources = @import("external_resources.zig");
const CallError = external.CallError;
const directory_data = @import("scoped_directory.zig");
/// A configured numeric address. No DNS resolution or redirect following occurs.
pub const Endpoint = struct { name: []const u8, address: std.Io.net.IpAddress };
/// One granted directory. Writing modes consider only writable roots; a relative
/// request is tried against each root in order and the first success wins.
pub const Root = struct { dir: std.Io.Dir, writable: bool = false };
const Handle = union(enum) { file: std.Io.File, stream: std.Io.net.Stream, snapshot: *directory_data.Snapshot };
/// Callbacks borrow this stable context and its directory/endpoint grants until stores close.
pub const Context = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    roots: []const Root = &.{},
    endpoints: []const Endpoint = &.{},
    handles: std.ArrayList(?Handle) = .empty,
    max_handles: usize = 256,
    snapshot_limits: directory_data.Limits = .{},
    /// Release all remaining handles; root directory and endpoint storage remain caller-owned.
    pub fn deinit(self: *Context) void {
        for (self.handles.items) |handle| if (handle) |h| self.close(h);
        self.handles.deinit(self.allocator);
        self.handles = .empty;
    }
    /// File requests use r:path, w:path, c:path (exclusive create), t:path (truncate
    /// existing), m:path, l:path, k:path (create directory) or x:path (remove entry).
    pub fn filesystem(self: *Context) resources.Provider {
        return .{ .context = self, .acquire = acquireFile, .read = read, .write = write, .complete = complete, .release = release };
    }
    /// Network requests must exactly equal one configured literal endpoint string.
    pub fn network(self: *Context) resources.Provider {
        return .{ .context = self, .acquire = acquireNetwork, .read = read, .write = write, .complete = complete, .release = release };
    }
    fn reserve(self: *Context) CallError!usize {
        for (self.handles.items, 0..) |handle, i| if (handle == null) return i;
        if (self.handles.items.len >= self.max_handles) return error.Denied;
        try self.handles.append(self.allocator, null);
        return self.handles.items.len - 1;
    }
    fn close(self: *Context, handle: Handle) void {
        switch (handle) {
            .file => |file| file.close(self.io),
            .stream => |stream| stream.close(self.io),
            .snapshot => |snapshot| snapshot.deinit(),
        }
    }
    fn get(self: *Context, id: u64) CallError!Handle {
        if (id >= self.handles.items.len) return error.Failed;
        return self.handles.items[@intCast(id)] orelse error.Failed;
    }
    fn acquireFile(raw: *anyopaque, request: []const u8, permissions: resources.Permissions) CallError!u64 {
        const self: *Context = @ptrCast(@alignCast(raw));
        if (self.roots.len == 0) return error.Unavailable;
        const spec = try fileRequest(request, permissions);
        var failure: CallError = error.Denied;
        for (self.roots) |root| {
            if (writingMode(spec.mode) and !root.writable) continue;
            if (self.acquireIn(root.dir, spec.mode, spec.path)) |handle| return handle else |err| {
                if (err == error.OutOfMemory) return err;
                failure = err;
            }
        }
        return failure;
    }
    fn acquireIn(self: *Context, root: std.Io.Dir, mode: u8, path: []const u8) CallError!u64 {
        const index = try self.reserve();
        var parent = root;
        var owned = false;
        defer if (owned) parent.close(self.io);
        var parts = std.mem.splitScalar(u8, path, '/');
        var name = parts.next().?;
        while (parts.next()) |next| {
            const child = parent.openDir(self.io, name, .{ .follow_symlinks = false }) catch |err| return mapError(err);
            if (owned) parent.close(self.io);
            parent = child;
            owned = true;
            name = next;
        }
        if (mode == 'm' or mode == 'l' or mode == 'k' or mode == 'x') {
            const snapshot = try directory_data.create(self.allocator, self.io, parent, name, mode, self.snapshot_limits);
            self.handles.items[index] = .{ .snapshot = snapshot };
            return @intCast(index);
        }
        const file = try self.open(parent, name, mode);
        self.handles.items[index] = .{ .file = file };
        return @intCast(index);
    }
    fn open(self: *Context, parent: std.Io.Dir, name: []const u8, mode: u8) CallError!std.Io.File {
        const file = if (mode == 'c')
            parent.createFile(self.io, name, .{ .exclusive = true }) catch |err| return mapError(err)
        else
            parent.openFile(self.io, name, .{ .mode = if (mode == 'r') .read_only else .write_only, .follow_symlinks = false, .allow_directory = false }) catch |err| return mapError(err);
        errdefer file.close(self.io);
        const stat = file.stat(self.io) catch |err| return mapError(err);
        if (stat.kind != .file) return error.Denied;
        if (mode == 't') file.setLength(self.io, 0) catch |err| return mapError(err);
        return file;
    }
    fn acquireNetwork(raw: *anyopaque, request: []const u8, permissions: resources.Permissions) CallError!u64 {
        const self: *Context = @ptrCast(@alignCast(raw));
        if (permissions & (resources.permissionBit(.read) | resources.permissionBit(.write)) == 0) return error.Denied;
        const address = try endpoint(self.endpoints, request);
        const index = try self.reserve();
        const stream = address.connect(self.io, .{ .mode = .stream }) catch |err| return mapError(err);
        self.handles.items[index] = .{ .stream = stream };
        return @intCast(index);
    }
    fn read(raw: *anyopaque, id: u64, output: []u8) CallError!resources.Read {
        const self: *Context = @ptrCast(@alignCast(raw));
        const handle = try self.get(id);
        // A zero-size callback does not probe EOF, including immutable snapshots.
        if (output.len == 0) return .{ .length = 0, .eof = false };
        if (handle == .snapshot) return handle.snapshot.read(output[0..@min(output.len, 64 * 1024)]);
        var buffers = [_][]u8{output[0..@min(output.len, 64 * 1024)]};
        const length = switch (handle) {
            .snapshot => return error.Failed,
            .file => |file| file.readStreaming(self.io, &buffers) catch |err| if (err == error.EndOfStream) 0 else return mapError(err),
            .stream => |stream| stream.read(self.io, &buffers) catch |err| if (err == error.EndOfStream) 0 else return mapError(err),
        };
        return .{ .length = length, .eof = length == 0 };
    }
    fn write(raw: *anyopaque, id: u64, input: []const u8) CallError!usize {
        const self: *Context = @ptrCast(@alignCast(raw));
        const bytes = input[0..@min(input.len, 64 * 1024)];
        return switch (try self.get(id)) {
            .snapshot => error.Denied,
            .file => |file| file.writeStreaming(self.io, &.{}, &.{bytes}, 1) catch |err| return mapError(err),
            .stream => |stream| blk: {
                var writer = stream.writer(self.io, &.{});
                break :blk writer.interface.write(bytes) catch |err| return mapError(err);
            },
        };
    }
    fn complete(raw: *anyopaque, id: u64) CallError!void {
        const self: *Context = @ptrCast(@alignCast(raw));
        self.close(try self.get(id));
        self.handles.items[@intCast(id)] = null;
    }
    fn release(raw: *anyopaque, id: u64) void {
        const self: *Context = @ptrCast(@alignCast(raw));
        const handle = self.get(id) catch return;
        self.close(handle);
        self.handles.items[@intCast(id)] = null;
    }
};
/// Reject traversal and write-mode requests before opening, creating or truncating anything.
pub fn fileRequest(request: []const u8, permissions: resources.Permissions) CallError!struct { mode: u8, path: []const u8 } {
    if (request.len < 2 or request.len > 4096 or request[1] != ':') return error.Denied;
    const mode = request[0];
    const reading = mode == 'r' or mode == 'm' or mode == 'l';
    const writing = writingMode(mode);
    if (!reading and !writing) return error.Denied;
    const required = resources.permissionBit(if (reading) .read else .write);
    if (permissions & required == 0) return error.Denied;
    const path = request[2..];
    if (path.len == 0 and (mode == 'm' or mode == 'l')) return .{ .mode = mode, .path = path };
    if (std.mem.indexOfAny(u8, path, "\\\x00") != null) return error.Denied;
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) return error.Denied;
    }
    return .{ .mode = mode, .path = path };
}
/// Request modes that change the granted tree and therefore need write authority.
pub fn writingMode(mode: u8) bool {
    return mode == 'w' or mode == 'c' or mode == 't' or mode == 'k' or mode == 'x';
}
/// Exact configured endpoints prevent DNS rebinding and implicit network scope expansion.
pub fn endpoint(allowed: []const Endpoint, request: []const u8) CallError!std.Io.net.IpAddress {
    for (allowed) |item| if (std.mem.eql(u8, item.name, request)) return item.address;
    return error.Denied;
}
fn mapError(err: anyerror) CallError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.AccessDenied, error.PermissionDenied, error.SymLinkLoop, error.NotDir => error.Denied,
        else => error.Failed,
    };
}
