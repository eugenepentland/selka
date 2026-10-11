//! Opt-in immutable compiler artifacts. Indexes and materialized executables stay local.
const std = @import("std");
const storage = @import("shared_artifact_io.zig");
const retention = @import("native_cache_retention.zig");

/// Explicit opt-in, independent of private caches and shared test-success receipts.
pub const environment_variable = "MYLANG_COMPILER_SHARED_CACHE";
/// Per-artifact bound; oversized entries use the ordinary private compilation path.
pub const maximum_payload = 128 * 1024 * 1024;
/// Storage failures; corruption is a miss, conflicting valid outputs are errors.
pub const Error = storage.Error;
/// Independent serializer domains under one versioned storage namespace.
pub const Kind = enum(u8) { syntax = 1, typed = 2, program = 3 };
/// Complete producer key supplied by the syntax, semantic or native layer.
pub const Key = [32]u8;
const format = "selka-compiler-artifact-store-v2\n";
const magic = "selka-compiler-blob-v1\x00";
const header_size = magic.len + 1 + 32 + 8 + 32;

/// Nonempty configured roots opt in; an empty value explicitly disables sharing.
pub fn selected(environment: *const std.process.Environ.Map) ?[]const u8 {
    const root = environment.get(environment_variable) orelse return null;
    return if (root.len == 0) null else root;
}

/// A bounded immutable store. No lock spans checking, code generation or linking.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    serial: std.atomic.Value(u64) = .init(0),

    /// Create or validate a dedicated namespace. Release the owned path with deinit.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error!Store {
        if (directory.len == 0) return error.WriteFailed;
        const self: Store = .{ .allocator = a, .io = io, .root = try std.fs.path.join(a, &.{ directory, "compiler-artifacts-v2" }) };
        errdefer a.free(self.root);
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(io, self.root) catch return error.WriteFailed;
        try self.initialize();
        self.retentionContext().automatic();
        return self;
    }

    fn retentionContext(self: *const Store) retention.Context {
        return retention.Context.init(self.allocator, self.io, self.root, .compiler);
    }

    fn initialize(self: *const Store) Error!void {
        const a = self.allocator;
        const io = self.io;
        const cwd = std.Io.Dir.cwd();
        const lease = try self.retentionContext().lease();
        defer lease.close(io);
        const lock_path = try self.path(".lock");
        defer a.free(lock_path);
        const guard = try storage.lock(a, io, lock_path);
        defer guard.close(io);
        const marker = try self.path("format");
        defer a.free(marker);
        if (try storage.bounded(a, io, marker, 128)) |bytes| {
            defer a.free(bytes);
            if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
        } else {
            var directory_handle = cwd.openDir(io, self.root, .{ .iterate = true }) catch return error.ReadFailed;
            defer directory_handle.close(io);
            var entries = directory_handle.iterate();
            while (entries.next(io) catch return error.ReadFailed) |entry| {
                if (std.mem.eql(u8, entry.name, ".retention.lock") or std.mem.eql(u8, entry.name, ".lock") or std.mem.eql(u8, entry.name, "format.partial")) continue;
                return error.ReadFailed;
            }
            const temporary = try self.path("format.partial");
            defer a.free(temporary);
            storage.remove(io, temporary);
            defer storage.remove(io, temporary);
            const file = cwd.createFile(io, temporary, .{ .exclusive = true }) catch return error.WriteFailed;
            defer file.close(io);
            file.writeStreamingAll(io, format) catch return error.WriteFailed;
            cwd.rename(temporary, cwd, marker, io) catch return error.WriteFailed;
        }
        _ = try self.retentionContext().policy();
    }

    /// Release the path; committed artifacts and permanent lock files remain.
    pub fn deinit(self: *Store) void {
        self.allocator.free(self.root);
    }

    /// Emit a useful storage diagnosis before a frontend maps the failure to its error set.
    pub fn reportFailure(self: *const Store, err: anyerror) void {
        var buffer: [256]u8 = undefined;
        const text = std.fmt.bufPrint(&buffer, "error: shared compiler cache: {s}\n", .{@errorName(err)}) catch return;
        std.Io.File.stderr().writeStreamingAll(self.io, text) catch return;
    }

    /// Load verified bytes into the caller's allocator; damaged records miss.
    pub fn load(self: *const Store, a: std.mem.Allocator, kind: Kind, key: Key) Error!?[]u8 {
        const lease = try self.retentionContext().lease();
        defer lease.close(self.io);
        const entry = try self.record(kind, key) orelse return null;
        defer entry.file.close(self.io);
        const bytes = try a.alloc(u8, entry.content.size);
        errdefer a.free(bytes);
        const count = entry.file.readPositionalAll(self.io, bytes, header_size) catch return error.ReadFailed;
        if (count != bytes.len) {
            a.free(bytes);
            return null;
        }
        var digest: Key = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        if (!std.mem.eql(u8, &digest, &entry.content.digest)) {
            a.free(bytes);
            return null;
        }
        self.retentionContext().touch(entry.file);
        return bytes;
    }

    /// Retain exact serialized bytes; valid same-key disagreement is never overwritten.
    pub fn save(self: *Store, kind: Kind, key: Key, bytes: []const u8) Error!bool {
        if (bytes.len > maximum_payload) return false;
        return self.publish(kind, key, .{ .bytes = bytes }, bytes.len);
    }

    /// Stream a private artifact into shared storage without allocating its contents.
    pub fn publishFile(self: *Store, kind: Kind, key: Key, source: []const u8) Error!bool {
        const file = try storage.regular(self.allocator, self.io, source) orelse return error.ReadFailed;
        defer file.close(self.io);
        const size = (file.stat(self.io) catch return error.ReadFailed).size;
        if (size > maximum_payload) return false;
        return self.publish(kind, key, .{ .file = file }, @intCast(size));
    }

    /// Stream verified bytes to a new private staging file; a corrupt copy is removed.
    pub fn restore(self: *const Store, kind: Kind, key: Key, destination: []const u8) Error!bool {
        const lease = try self.retentionContext().lease();
        defer lease.close(self.io);
        const entry = try self.record(kind, key) orelse return false;
        defer entry.file.close(self.io);
        const output = std.Io.Dir.cwd().createFile(self.io, destination, .{ .exclusive = true }) catch return error.WriteFailed;
        defer output.close(self.io);
        var keep = false;
        defer if (!keep) storage.remove(self.io, destination);
        const actual = storage.transfer(self.io, entry.file, output, header_size, entry.content.size) catch |err| {
            if (err == error.InputChanged) return false;
            return err;
        };
        if (!std.mem.eql(u8, &actual.digest, &entry.content.digest)) return false;
        output.setPermissions(self.io, .fromMode(if (kind == .program) 0o700 else 0o600)) catch return error.WriteFailed;
        keep = true;
        self.retentionContext().touch(entry.file);
        return true;
    }

    /// The immutable record path, useful for storage inspection and corruption tests.
    pub fn artifactPath(self: *const Store, kind: Kind, key: Key) Error![]u8 {
        return std.fmt.allocPrint(self.allocator, "{s}/{s}/{s}.blob", .{ self.root, @tagName(kind), std.fmt.bytesToHex(key, .lower) });
    }

    fn path(self: *const Store, leaf: []const u8) Error![]u8 {
        return std.fs.path.join(self.allocator, &.{ self.root, leaf });
    }

    fn validate(self: *const Store) Error!void {
        const path_name = try self.path("format");
        defer self.allocator.free(path_name);
        const bytes = try storage.bounded(self.allocator, self.io, path_name, 128) orelse return error.ReadFailed;
        defer self.allocator.free(bytes);
        if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
    }

    fn record(self: *const Store, kind: Kind, key: Key) Error!?Record {
        try self.validate();
        const path_name = try self.artifactPath(kind, key);
        defer self.allocator.free(path_name);
        const file = try storage.regular(self.allocator, self.io, path_name) orelse return null;
        var keep = false;
        defer if (!keep) file.close(self.io);
        const size = (file.stat(self.io) catch return error.ReadFailed).size;
        if (size < header_size or size > header_size + maximum_payload) return null;
        var header: [header_size]u8 = undefined;
        if ((file.readPositionalAll(self.io, &header, 0) catch return error.ReadFailed) != header.len) return null;
        const content = decode(&header, kind, key) orelse return null;
        if (content.size != size - header_size) return null;
        keep = true;
        return .{ .file = file, .content = content };
    }

    fn publish(self: *Store, kind: Kind, key: Key, input: Input, size: usize) Error!bool {
        const lease = try self.retentionContext().lease();
        defer lease.close(self.io);
        try self.validate();
        const a = self.allocator;
        const directory = try self.path(@tagName(kind));
        defer a.free(directory);
        const cwd = std.Io.Dir.cwd();
        cwd.createDirPath(self.io, directory) catch return error.WriteFailed;
        const staged = try stage(self, directory);
        defer a.free(staged.path);
        defer storage.remove(self.io, staged.path);
        const content = try stageContents(self.io, staged.file, input, .{ .kind = kind, .key = key, .size = size });
        const target = try self.artifactPath(kind, key);
        defer a.free(target);
        const lock_name = try std.fmt.allocPrint(a, "{s}.lock", .{target});
        defer a.free(lock_name);
        const guard = try storage.lock(a, self.io, lock_name);
        defer guard.close(self.io);
        // Only this key is serialized. All staging and its hashing precede admission.
        if (try self.record(kind, key)) |previous| {
            defer previous.file.close(self.io);
            const actual: ?storage.Content = storage.transfer(self.io, previous.file, null, header_size, previous.content.size) catch |err| previous_missing: {
                if (err == error.InputChanged) break :previous_missing null;
                return err;
            };
            if (actual) |verified| if (std.mem.eql(u8, &verified.digest, &previous.content.digest)) {
                if (content.size != verified.size or !std.mem.eql(u8, &content.digest, &verified.digest)) return error.DeterminismMismatch;
                self.retentionContext().touch(previous.file);
                return true;
            };
        }
        try self.validate();
        cwd.rename(staged.path, cwd, target, self.io) catch return error.WriteFailed;
        return true;
    }
};

const Record = struct { file: std.Io.File, content: storage.Content };
const Input = union(enum) { bytes: []const u8, file: std.Io.File };
const Address = struct { kind: Kind, key: Key, size: usize };
const Staged = struct { file: std.Io.File, path: []u8 };

fn stage(store: *Store, directory: []const u8) Error!Staged {
    const a = store.allocator;
    const io = store.io;
    for (0..1024) |_| {
        const path = try std.fmt.allocPrint(a, "{s}/.{d}-{x}-{d}.partial", .{ directory, std.os.linux.getpid(), @intFromPtr(store), store.serial.fetchAdd(1, .monotonic) });
        const file = std.Io.Dir.cwd().createFile(io, path, .{ .exclusive = true }) catch |err| {
            a.free(path);
            if (err == error.PathAlreadyExists) continue;
            return error.WriteFailed;
        };
        return .{ .file = file, .path = path };
    }
    return error.WriteFailed;
}

fn stageContents(io: std.Io, file: std.Io.File, input: Input, address: Address) Error!storage.Content {
    defer file.close(io);
    file.writeStreamingAll(io, &@as([header_size]u8, @splat(0))) catch return error.WriteFailed;
    const content: storage.Content = switch (input) {
        .bytes => |bytes| content: {
            file.writeStreamingAll(io, bytes) catch return error.WriteFailed;
            var digest: Key = undefined;
            std.crypto.hash.Blake3.hash(bytes, &digest, .{});
            break :content .{ .size = bytes.len, .digest = digest };
        },
        .file => |source| content: {
            const result = try storage.transfer(io, source, file, 0, address.size);
            if ((source.stat(io) catch return error.ReadFailed).size != address.size) return error.InputChanged;
            break :content result;
        },
    };
    const header = encode(address.kind, address.key, content);
    file.writePositionalAll(io, &header, 0) catch return error.WriteFailed;
    return content;
}

fn encode(kind: Kind, key: Key, content: storage.Content) [header_size]u8 {
    var bytes: [header_size]u8 = undefined;
    @memcpy(bytes[0..magic.len], magic);
    bytes[magic.len] = @backingInt(kind);
    @memcpy(bytes[magic.len + 1 ..][0..32], &key);
    std.mem.writeInt(u64, bytes[magic.len + 33 ..][0..8], content.size, .little);
    @memcpy(bytes[magic.len + 41 ..][0..32], &content.digest);
    return bytes;
}

fn decode(bytes: *const [header_size]u8, kind: Kind, key: Key) ?storage.Content {
    if (!std.mem.eql(u8, bytes[0..magic.len], magic) or bytes[magic.len] != @backingInt(kind)) return null;
    if (!std.mem.eql(u8, bytes[magic.len + 1 ..][0..32], &key)) return null;
    const size = std.mem.readInt(u64, bytes[magic.len + 33 ..][0..8], .little);
    if (size > maximum_payload) return null;
    return .{ .size = @intCast(size), .digest = bytes[magic.len + 41 ..][0..32].* };
}
