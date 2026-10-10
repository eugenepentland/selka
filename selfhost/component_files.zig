//! Bounded file hashes, canonical identities and atomic component publication.
const std = @import("std");
const Value = std.json.Value;
const Sha = std.crypto.hash.sha2.Sha256;
const cwd = std.Io.Dir.cwd;

/// Hash file bytes with a fixed buffer, independent of the file's size.
pub fn digest(io: std.Io, path: []const u8) ![64]u8 {
    const file = try cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [65536]u8 = undefined;
    var sha = Sha.init(.{});
    while (true) {
        const n = file.readStreaming(io, &.{&buffer}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) break;
        sha.update(buffer[0..n]);
    }
    var result: [32]u8 = undefined;
    sha.final(&result);
    return std.fmt.bytesToHex(result, .lower);
}

/// Stream the first record from procfs, whose files often report a zero stat size.
/// Retain only one bounded metadata block rather than the whole pseudo-file.
pub fn firstBlock(a: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    const file = try cwd().openFile(io, path, .{});
    defer file.close(io);
    var buffer: [65536]u8 = undefined;
    var length: usize = 0;
    while (length < buffer.len) {
        const n = file.readStreaming(io, &.{buffer[length..]}) catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (n == 0) break;
        length += n;
        if (std.mem.indexOf(u8, buffer[0..length], "\n\n")) |end| return a.dupe(u8, buffer[0..end]);
    }
    if (length == buffer.len) return error.CpuMetadataTooLarge;
    return a.dupe(u8, buffer[0..length]);
}

/// Hash an already bounded identity record.
pub fn textDigest(text: []const u8) [64]u8 {
    var result: [32]u8 = undefined;
    Sha.hash(text, &result, .{});
    return std.fmt.bytesToHex(result, .lower);
}

/// Join path fragments owned by the caller's allocator.
pub fn join(a: std.mem.Allocator, parts: []const []const u8) ![]const u8 {
    return std.fs.path.join(a, parts);
}

/// Whether a path exists; unexpected filesystem errors remain failures.
pub fn exists(io: std.Io, path: []const u8) !bool {
    cwd().access(io, path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    return true;
}

/// Own a JSON object with named fields.
pub fn object(a: std.mem.Allocator, fields: []const Field) !Value {
    var map: std.json.ObjectMap = .empty;
    for (fields) |field| try map.put(a, field.name, field.value);
    return .{ .object = map };
}
pub const Field = struct { name: []const u8, value: Value };
pub fn string(bytes: []const u8) Value {
    return .{ .string = bytes };
}
pub fn integer(n: i64) Value {
    return .{ .integer = n };
}

/// Copy path/digest metadata only. File content buffers never enter an arena.
pub fn tree(a: std.mem.Allocator, io: std.Io, path: []const u8) !Value {
    const dir = try cwd().openDir(io, path, .{ .iterate = true });
    defer dir.close(io);
    var walker = try dir.walk(a);
    defer walker.deinit();
    var map: std.json.ObjectMap = .empty;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file and entry.kind != .sym_link) continue;
        if (std.mem.endsWith(u8, entry.path, ".pyc") or excludedPath(entry.path)) continue;
        var path_buffer: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const full = try std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ path, entry.path });
        if (entry.kind == .sym_link) {
            const stat = cwd().statFile(io, full, .{}) catch |err| switch (err) {
                error.FileNotFound => continue,
                else => return err,
            };
            if (stat.kind != .file) continue;
        }
        const hash = try digest(io, full);
        try map.put(a, try a.dupe(u8, entry.path), string(try a.dupe(u8, &hash)));
    }
    return .{ .object = map };
}

fn excludedPath(path: []const u8) bool {
    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| if (std.mem.eql(u8, part, "__pycache__")) return true;
    return false;
}

fn less(_: void, lhs: []const u8, rhs: []const u8) bool {
    return std.mem.lessThan(u8, lhs, rhs);
}
fn canonicalWrite(a: std.mem.Allocator, writer: *std.Io.Writer, value: Value) anyerror!void {
    switch (value) {
        .object => |map| {
            const keys = try a.dupe([]const u8, map.keys());
            defer a.free(keys);
            std.mem.sort([]const u8, keys, {}, less);
            try writer.writeByte('{');
            for (keys, 0..) |key, index| {
                if (index != 0) try writer.writeByte(',');
                try std.json.Stringify.value(key, .{ .escape_unicode = true }, writer);
                try writer.writeByte(':');
                try canonicalWrite(a, writer, map.get(key).?);
            }
            try writer.writeByte('}');
        },
        .array => |array| {
            try writer.writeByte('[');
            for (array.items, 0..) |item, index| {
                if (index != 0) try writer.writeByte(',');
                try canonicalWrite(a, writer, item);
            }
            try writer.writeByte(']');
        },
        else => try std.json.Stringify.value(value, .{ .escape_unicode = true }, writer),
    }
}

/// Python-compatible sorted, compact, ASCII-escaped JSON for seed receipts.
pub fn canonical(a: std.mem.Allocator, value: Value) ![]const u8 {
    var writer = std.Io.Writer.Allocating.init(a);
    errdefer writer.deinit();
    try canonicalWrite(a, &writer.writer, value);
    return writer.toOwnedSlice();
}

/// Bound metadata reads. Artifact and toolchain reads must use digest instead.
pub fn readJson(a: std.mem.Allocator, io: std.Io, path: []const u8) !Value {
    const text = try cwd().readFileAlloc(io, path, a, .limited(16 << 20));
    defer a.free(text);
    return try std.json.parseFromSliceLeaky(Value, a, text, .{ .allocate = .alloc_always });
}

/// Atomically publish bytes with explicit permissions, including before rename.
pub fn atomicJson(a: std.mem.Allocator, io: std.Io, path: []const u8, value: Value, mode: u32) !void {
    const text = try canonical(a, value);
    defer a.free(text);
    var file = try cwd().createFileAtomic(io, path, .{ .permissions = .fromMode(mode), .replace = true });
    defer file.deinit(io);
    try file.file.writeStreamingAll(io, text);
    try file.file.writeStreamingAll(io, "\n");
    try file.file.setPermissions(io, .fromMode(mode));
    try file.replace(io);
}

/// Atomic fd-to-fd copy without loading executable bytes into memory.
pub fn copy(io: std.Io, source: []const u8, destination: []const u8, mode: u32) !void {
    const input = try cwd().openFile(io, source, .{});
    defer input.close(io);
    if (std.fs.path.dirname(destination)) |parent| try cwd().createDirPath(io, parent);
    var output = try cwd().createFileAtomic(io, destination, .{ .permissions = .fromMode(mode), .replace = true });
    defer output.deinit(io);
    var read_buffer: [65536]u8 = undefined;
    var write_buffer: [65536]u8 = undefined;
    var reader = input.reader(io, &read_buffer);
    var writer = output.file.writer(io, &write_buffer);
    _ = try writer.interface.sendFileAll(&reader, .unlimited);
    try writer.interface.flush();
    try output.file.setPermissions(io, .fromMode(mode));
    try output.replace(io);
}

/// Reset a selected cache directory; cleanup errors must stop stale reuse.
pub fn remove(io: std.Io, path: []const u8) !void {
    try cwd().deleteTree(io, path);
}

/// Deferred cleanup reports a bounded diagnostic; primary failures retain priority.
pub fn discard(io: std.Io, path: []const u8) void {
    remove(io, path) catch |err| {
        var buffer: [512]u8 = undefined;
        const message = std.fmt.bufPrint(&buffer, "components: cleanup failed ({s})\n", .{@errorName(err)}) catch return;
        std.Io.File.stderr().writeStreamingAll(io, message) catch return;
    };
}
