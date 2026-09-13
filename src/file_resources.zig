//! VM adapter for the Python file surface. Every operation goes through the
//! injected filesystem resource store, so no ambient authority exists here.
const std = @import("std");
const typed = @import("typed.zig");
const resources = @import("external_resources.zig");
const operations = @import("file_operations.zig");
const managed_text = @import("managed_text.zig");
const gc = @import("gc_heap.zig");

/// Failures returned by file operations; callers must handle these boundary errors.
pub const Error = resources.Error || managed_text.Error || @import("managed_bytes.zig").Error || error{ InternalError, InvalidAggregateType };

/// Largest whole-file transfer, so one path cannot exhaust host memory.
pub const max_bytes: usize = 64 * 1024 * 1024;
/// Longest guest path, matching the scoped provider's own request bound.
pub const max_path: usize = 4094;

/// Nominal types the checker resolved for one operation's result payloads.
pub const Shapes = struct { output: typed.Type, text: typed.Type, bytes: typed.Type, list: typed.Type };

/// Borrowed store, heap and schemas for one file operation.
pub const Context = struct {
    heap: *gc.Heap,
    records: []const typed.Record,
    store: *resources.Store,
    shapes: Shapes,
    /// Borrow the managed heap's allocator for temporary host-side storage.
    pub fn allocator(self: Context) std.mem.Allocator {
        return self.heap.allocator;
    }
};

/// Borrowed operands of one whole-path helper.
pub const Request = struct { kind: operations.Access, mode: u8, text: bool, capability: typed.Value, path: []const u8, input: ?[]const u8 };

/// Borrowed operands of one method call on an open handle.
pub const MethodRequest = struct { kind: operations.Method, owner: typed.Value, text: bool, count: ?i64, input: ?[]const u8 };

/// Readable explanation of a provider failure, used in `Result` error text and traps.
pub fn reason(err: anyerror) []const u8 {
    return switch (err) {
        error.Unavailable => "no filesystem authority is available",
        error.Denied => "denied: outside the granted directories, or the mode needs a write grant",
        error.ResourceLimit => "too many files are open",
        error.InvalidOwner, error.Closed => "the file is already closed",
        error.InvalidUtf8 => "the bytes read are not valid UTF-8 text",
        else => "failed: the path does not exist or could not be used",
    };
}

/// Guest paths stay relative; the scoped provider validates every component.
fn requestBytes(buffer: []u8, letter: u8, path: []const u8) error{Denied}![]const u8 {
    if (path.len > max_path) return error.Denied;
    buffer[0] = letter;
    buffer[1] = ':';
    @memcpy(buffer[2..][0..path.len], path);
    return buffer[0 .. path.len + 2];
}

/// Open for writing: create the file exclusively, or truncate an existing one.
fn acquire(store: *resources.Store, capability: resources.Capability, letter: u8, path: []const u8) resources.Error!resources.Owner {
    var buffer: [max_path + 2]u8 = undefined;
    if (letter != 'w') return store.acquire(capability, try requestBytes(&buffer, letter, path));
    const created = store.acquire(capability, try requestBytes(&buffer, 'c', path));
    if (created) |owner| return owner else |_| {}
    return store.acquire(capability, try requestBytes(&buffer, 't', path));
}

/// Read a whole resource into caller-owned bytes, honouring the size ceiling.
fn readAll(allocator: std.mem.Allocator, store: *resources.Store, owner: resources.Owner, limit: usize) Error![]u8 {
    var collected: std.ArrayList(u8) = .empty;
    // UNTESTED-ERROR: host allocation failure only; the allocation-failure sweeps cover it and it names no guest-visible error
    errdefer collected.deinit(allocator);
    var chunk: [16 * 1024]u8 = undefined;
    while (collected.items.len < limit) {
        const wanted = @min(chunk.len, limit - collected.items.len);
        const outcome = try store.read(owner, chunk[0..wanted]);
        if (collected.items.len + outcome.length > max_bytes) return error.Denied;
        try collected.appendSlice(allocator, chunk[0..outcome.length]);
        if (outcome.eof or outcome.length == 0) break;
    }
    return collected.toOwnedSlice(allocator);
}

/// Write every byte, looping over the provider's reported partial progress.
fn writeAll(store: *resources.Store, owner: resources.Owner, input: []const u8) resources.Error!usize {
    var written: usize = 0;
    while (written < input.len) {
        const count = try store.write(owner, input[written..]);
        if (count == 0) return error.Failed;
        written += count;
    }
    return written;
}

fn sequence(context: Context, text: bool, bytes: []const u8) Error!typed.Value {
    if (text) return managed_text.create(context.heap, context.shapes.text, bytes);
    return @import("managed_bytes.zig").create(context.heap, context.shapes.bytes, bytes);
}

fn failed(context: Context, verb: []const u8, path: []const u8, err: anyerror) Error!typed.Value {
    const message = try std.fmt.allocPrint(context.allocator(), "{s} '{s}': {s}", .{ verb, path, reason(err) });
    defer context.allocator().free(message);
    const text = try managed_text.create(context.heap, context.shapes.text, message);
    defer text.release(context.allocator());
    const shape = typed.resultShape(context.shapes.output, context.records) orelse return error.InternalError;
    return typed.Value.createVariant(context.allocator(), context.shapes.output, shape.error_tag, text);
}

fn ok(context: Context, payload: typed.Value) Error!typed.Value {
    const shape = typed.resultShape(context.shapes.output, context.records) orelse return error.InternalError;
    return typed.Value.createVariant(context.allocator(), context.shapes.output, shape.ok_tag, payload);
}

/// Decode one `l:` directory snapshot into a managed list of entry names.
fn listing(context: Context, bytes: []const u8) Error!typed.Value {
    const list = try context.heap.create(context.shapes.list, context.shapes.text, 0);
    errdefer list.release(context.allocator());
    if (bytes.len == 0 or bytes[0] != 1) return error.InvalidProvider;
    var cursor: usize = 1;
    while (cursor + 3 <= bytes.len) {
        const size = std.mem.readInt(u16, bytes[cursor + 1 ..][0..2], .little);
        cursor += 3;
        if (cursor + size > bytes.len) return error.InvalidProvider;
        const name = try managed_text.create(context.heap, context.shapes.text, bytes[cursor..][0..size]);
        defer name.release(context.allocator());
        try context.heap.append(list, name);
        cursor += size;
    }
    return list;
}

/// The provider request letter each whole-path helper needs.
fn letterFor(kind: operations.Access, mode: u8) u8 {
    return switch (kind) {
        .open => mode,
        .read_file, .read_text => 'r',
        .write_file, .write_text => 'w',
        .exists => 'm',
        .listdir => 'l',
        .mkdir => 'k',
        .remove => 'x',
    };
}

/// The verb used in this helper's error message.
fn verbFor(kind: operations.Access) []const u8 {
    return switch (kind) {
        .open => "open",
        .read_file, .read_text => "read",
        .write_file, .write_text => "write",
        .exists => "stat",
        .listdir => "listdir",
        .mkdir => "mkdir",
        .remove => "remove",
    };
}

/// Run one whole-path helper, reporting provider failures as `Result` errors.
pub fn access(context: Context, request: Request) Error!typed.Value {
    if (!request.capability.isCapability(.resource_capability)) return error.InternalError;
    const capability = request.capability.capability.resource_capability;
    const owner = acquire(context.store, capability, letterFor(request.kind, request.mode), request.path) catch |err| {
        if (request.kind == .exists) return .{ .bool = false };
        // A `with open(...)` head declares the handle type directly and traps instead.
        if (typed.resultShape(context.shapes.output, context.records) == null) return err;
        return failed(context, verbFor(request.kind), request.path, err);
    };
    if (request.kind == .open) return openHandle(context, owner, request.text);
    var settled = false;
    defer if (!settled) {
        _ = context.store.releaseIfLive(owner);
    };
    const payload = finish(context, request, owner) catch |err| {
        settled = true;
        _ = context.store.releaseIfLive(owner);
        if (request.kind == .exists) return .{ .bool = false };
        if (err == error.OutOfMemory) return err;
        return failed(context, verbFor(request.kind), request.path, err);
    };
    settled = true;
    defer payload.release(context.allocator());
    context.store.complete(owner) catch {
        _ = context.store.releaseIfLive(owner);
    };
    if (request.kind == .exists) return .{ .bool = true };
    return ok(context, payload);
}

fn finish(context: Context, request: Request, owner: resources.Owner) Error!typed.Value {
    return switch (request.kind) {
        .open => error.InternalError,
        .read_file, .read_text => payload: {
            const bytes = try readAll(context.allocator(), context.store, owner, max_bytes);
            defer context.allocator().free(bytes);
            break :payload try sequence(context, request.text, bytes);
        },
        .write_file, .write_text => payload: {
            _ = try writeAll(context.store, owner, request.input orelse return error.InternalError);
            break :payload .unit;
        },
        .listdir => payload: {
            const bytes = try readAll(context.allocator(), context.store, owner, max_bytes);
            defer context.allocator().free(bytes);
            break :payload try listing(context, bytes);
        },
        .exists, .mkdir, .remove => .unit,
    };
}

fn openHandle(context: Context, owner: resources.Owner, text: bool) Error!typed.Value {
    const ty: typed.Type = if (text) .text_file else .file;
    // UNTESTED-ERROR: host allocation failure only; the allocation-failure sweeps cover it and it names no guest-visible error
    const value = typed.Value.ownExternal(context.allocator(), ty, context.store, owner) catch |err| {
        _ = context.store.releaseIfLive(owner);
        return err;
    };
    if (typed.resultShape(context.shapes.output, context.records) == null) return value;
    defer value.release(context.allocator());
    return ok(context, value);
}

/// Read up to one line, keeping its terminator, without provider pushback.
fn readLine(allocator: std.mem.Allocator, store: *resources.Store, owner: resources.Owner) Error![]u8 {
    var collected: std.ArrayList(u8) = .empty;
    // UNTESTED-ERROR: host allocation failure only; the allocation-failure sweeps cover it and it names no guest-visible error
    errdefer collected.deinit(allocator);
    var byte: [1]u8 = undefined;
    while (collected.items.len < max_bytes) {
        const outcome = try store.read(owner, &byte);
        if (outcome.length == 0) break;
        try collected.append(allocator, byte[0]);
        if (byte[0] == '\n' or outcome.eof) break;
    }
    return collected.toOwnedSlice(allocator);
}

fn lines(context: Context, request: MethodRequest, owner: resources.Owner) Error!typed.Value {
    const bytes = try readAll(context.allocator(), context.store, owner, max_bytes);
    defer context.allocator().free(bytes);
    const list = try context.heap.create(context.shapes.list, if (request.text) context.shapes.text else context.shapes.bytes, 0);
    errdefer list.release(context.allocator());
    var start: usize = 0;
    while (start < bytes.len) {
        const end = if (std.mem.indexOfScalarPos(u8, bytes, start, '\n')) |at| at + 1 else bytes.len;
        const line = try sequence(context, request.text, bytes[start..end]);
        defer line.release(context.allocator());
        try context.heap.append(list, line);
        start = end;
    }
    return list;
}

/// Run one method on an open handle; failures trap rather than yielding a result.
pub fn method(context: Context, request: MethodRequest) Error!typed.Value {
    if (!request.owner.isOwned(.external_resource)) return error.InternalError;
    const resource = request.owner.owned.external_resource;
    if (resource.store != context.store) return error.InvalidOwner;
    const owner = resource.owner orelse return error.InvalidOwner;
    switch (request.kind) {
        .flush => return .unit,
        .close => {
            try context.store.complete(owner);
            resource.owner = null;
            return .unit;
        },
        .write => {
            const input = request.input orelse return error.InternalError;
            return .{ .i64 = @intCast(try writeAll(context.store, owner, input)) };
        },
        .readlines => return lines(context, request, owner),
        .readline => {
            const bytes = try readLine(context.allocator(), context.store, owner);
            defer context.allocator().free(bytes);
            return sequence(context, request.text, bytes);
        },
        .read => {
            // Python spells "read everything" as a negative count.
            const limit: usize = if (request.count) |count| (if (count < 0) max_bytes else @intCast(count)) else max_bytes;
            const bytes = try readAll(context.allocator(), context.store, owner, limit);
            defer context.allocator().free(bytes);
            return sequence(context, request.text, bytes);
        },
    }
}
