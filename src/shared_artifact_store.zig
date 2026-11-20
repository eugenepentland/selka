//! Opt-in immutable compiler artifacts. Indexes and materialized executables stay local.
const std = @import("std");
const storage = @import("shared_artifact_io.zig");
const retention = @import("native_cache_retention.zig");
const work = @import("native_cache_work.zig");
const policy = @import("shared_cache_policy.zig");

/// Explicit opt-in, independent of private caches and shared test-success receipts.
pub const environment_variable = "SELKA_COMPILER_SHARED_CACHE";
/// Per-artifact bound; oversized entries use the ordinary private compilation path.
pub const maximum_payload = 128 * 1024 * 1024;
/// Storage failures; corruption is a miss and conflicting valid outputs are a
/// logged `Publication.mismatch`, never an error.
pub const Error = storage.Error;
/// What one publication did. Only `stored` wrote a record.
pub const Publication = enum {
    /// The bytes were staged and renamed into place.
    stored,
    /// A verified record already held exactly these bytes; nothing was written.
    present,
    /// Nothing was published: the payload is oversized or a collection holds the store.
    skipped,
    /// A verified record holds different bytes for this key. It is kept, nothing
    /// is published, and the pair of digests is appended to `mismatches.log`.
    mismatch,
};
/// Independent serializer domains under one versioned storage namespace. `frontend` holds the front end's own small records: a project's
/// check-summary table (replaced on each successful check, so its writer removes the old record first) and a module's header facts,
/// under keys that carry the compiler identity and no path. `engine_record` and `engine_object` are the
/// incremental engine's shared tier (`core/engine/compiler_records.zig`): a record under its query key, an object under the
/// digest of its bytes.
pub const Kind = enum(u8) { syntax = 1, typed = 2, program = 3, engine_record = 4, engine_object = 5, frontend = 6 };
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

/// Open the store a command uses. An explicit setting opens it or fails; an unset
/// variable opens the per-user default only while `default_sharing` is on, and a
/// default store that cannot be opened yields null and the command builds without sharing; one that exists but is unusable
/// first prints a warning that names the repair (`native_cache_retention.unusableWarning`).
pub fn openSelected(a: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map) Error!?Store {
    return openSelectedWith(a, io, environment, policy.default_sharing);
}

fn openSelectedWith(a: std.mem.Allocator, io: std.Io, environment: *const std.process.Environ.Map, sharing: bool) Error!?Store {
    const selection = try policy.resolveWith(a, environment, .compiler, null, sharing) orelse return null;
    defer if (selection.origin == .default) a.free(selection.path);
    const store = Store.open(a, io, selection.path) catch |err| {
        if (err == error.OutOfMemory or selection.origin == .explicit) return err;
        // A default location that could not be created (a read-only or absent home) is an ordinary miss: the command builds
        // without sharing, quietly. A store that is there and cannot be opened warns once, with the command that repairs it.
        retention.warnUnusable(a, io, selection.path, .compiler, err);
        return null;
    };
    return store;
}

/// A bounded immutable store with independent exact-key work claims.
pub const Store = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    root: []const u8,
    serial: std.atomic.Value(u64) = .init(0),
    /// Bit `n` is set once the directory of the kind numbered `n` is known to exist, so a publication does not ask for it again (a failing
    /// `mkdirat` and a `statx` per publication otherwise). A directory a sweep removed under the process is made again by the one retry
    /// `publish` takes when a write fails.
    directories: std.atomic.Value(u8) = .init(0),

    /// Create or validate a dedicated namespace. Release the owned path with deinit.
    /// An existing namespace is validated without any lock, and the throttled
    /// sweep that follows only tries its exclusive admission, so no open waits on
    /// another process's sweep.
    pub fn open(a: std.mem.Allocator, io: std.Io, directory: []const u8) Error!Store {
        if (directory.len == 0) return error.WriteFailed;
        const self: Store = .{ .allocator = a, .io = io, .root = try std.fs.path.join(a, &.{ directory, "compiler-artifacts-v2" }) };
        errdefer a.free(self.root);
        try self.initialize();
        self.retentionContext().automatic();
        return self;
    }

    fn retentionContext(self: *const Store) retention.Context {
        return retention.Context.init(self.allocator, self.io, self.root, .compiler);
    }

    // Concurrent first openers race to create one namespace (SHARED-STORE-6).
    // Each attempt tolerates directories and a marker a peer already created; a
    // failed attempt is retried a bounded number of times, re-reading whatever
    // a peer published meanwhile, so only a store that stays unusable fails.
    fn initialize(self: *const Store) Error!void {
        try retention.retried(self, createNamespace);
        _ = try self.retentionContext().policy();
    }

    // A present marker is checked without any lock. Only first creation takes the
    // exclusive `.lock`, and it re-reads the marker under it. No sweep can run
    // before the marker exists, so creation needs no retention lease.
    fn createNamespace(self: *const Store) Error!void {
        std.Io.Dir.cwd().createDirPath(self.io, self.root) catch return error.WriteFailed;
        if (try self.marked()) return;
        const lock_path = try self.path(".lock");
        defer self.allocator.free(lock_path);
        const guard = try storage.lock(self.allocator, self.io, lock_path);
        defer guard.close(self.io);
        if (!try self.marked()) try self.writeMarker();
    }

    fn marked(self: *const Store) Error!bool {
        const marker = try self.path("format");
        defer self.allocator.free(marker);
        const bytes = try storage.bounded(self.allocator, self.io, marker, 128) orelse return false;
        defer self.allocator.free(bytes);
        if (!std.mem.eql(u8, bytes, format)) return error.ReadFailed;
        return true;
    }

    // Write the marker of a namespace that has none: a fresh one, or one that lost its marker (it holds this cache's own
    // directories and nothing else, `Condition.unmarked`). The directory name pins the format, and every record is verified
    // against its own key and digest, so adopting such a namespace serves nothing a reader would not check. A directory
    // that holds anything else is refused: it is not this cache's to claim.
    fn writeMarker(self: *const Store) Error!void {
        const a = self.allocator;
        const io = self.io;
        const cwd = std.Io.Dir.cwd();
        switch (try self.retentionContext().condition()) {
            .fresh, .unmarked => {},
            .initialized => return,
            .bad_marker, .foreign => return error.ReadFailed,
        }
        const marker = try self.path("format");
        defer a.free(marker);
        const temporary = try self.path("format.partial");
        defer a.free(temporary);
        storage.remove(io, temporary);
        defer storage.remove(io, temporary);
        const file = cwd.createFile(io, temporary, .{ .exclusive = true }) catch return error.WriteFailed;
        defer file.close(io);
        file.writeStreamingAll(io, format) catch return error.WriteFailed;
        cwd.rename(temporary, cwd, marker, io) catch return error.WriteFailed;
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
    /// Reads hold no lease: records are immutable inodes replaced only by rename,
    /// so an entry a sweep evicts is either read whole through its open handle or
    /// missed.
    pub fn load(self: *const Store, a: std.mem.Allocator, kind: Kind, key: Key) Error!?[]u8 {
        if (kind == .program) return loadProgram(self, a, key);
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

    /// Whether the entry of `kind` under `key` holds exactly `bytes`, told by its header alone (its size and the BLAKE3 digest of its content):
    /// the content is neither read nor hashed, so the answer is a stat and one small read, where `load` reads and hashes it all and
    /// refreshes its recency. A reader still checks the content against the digest, so an entry whose content was damaged after its header
    /// was written is a miss for whoever loads it, as it always was. An entry the probe finds is refreshed when its recency is more than an
    /// hour old, so the entries that local trees keep using stay recent without a refresh in every build. Holds no lease.
    pub fn holds(self: *const Store, kind: Kind, key: Key, bytes: []const u8) bool {
        if (kind == .program or bytes.len > maximum_payload) return false;
        const entry = (self.entryHeader(kind, key) catch return false) orelse return false;
        defer entry.file.close(self.io);
        if (entry.content.size != bytes.len) return false;
        var digest: Key = undefined;
        std.crypto.hash.Blake3.hash(bytes, &digest, .{});
        if (!std.mem.eql(u8, &digest, &entry.content.digest)) return false;
        if (@import("infra/clock.zig").retentionNow(self.io) - entry.modified > recency_grain_ns) self.retentionContext().touch(entry.file);
        return true;
    }

    /// Retain exact serialized bytes; valid same-key disagreement is never overwritten.
    pub fn save(self: *Store, kind: Kind, key: Key, bytes: []const u8) Error!Publication {
        if (bytes.len > maximum_payload) return .skipped;
        return self.publish(kind, key, .{ .bytes = bytes }, bytes.len);
    }

    /// Put `bytes` under `key` whatever the entry held, under the key's publication lock: for a record its writer replaces on
    /// purpose (a project's check-summary table, its semantic pack), where `save` would keep the old one and log the new as a
    /// mismatch. A reader sees the old entry or the new one, never neither, so two writers that race leave one of their records
    /// and no log line. Never for a program record.
    pub fn replace(self: *Store, kind: Kind, key: Key, bytes: []const u8) Error!Publication {
        if (kind == .program or bytes.len > maximum_payload) return .skipped;
        const lease = try self.retentionContext().tryLease() orelse return .skipped;
        defer lease.close(self.io);
        try self.validate();
        const a = self.allocator;
        const directory = try self.path(@tagName(kind));
        defer a.free(directory);
        try self.makeDirectory(directory, @as(u8, 1) << @intCast(@backingInt(kind)));
        const target = try self.artifactPath(kind, key);
        defer a.free(target);
        const lock_name = try std.fmt.allocPrint(a, "{s}.lock", .{target});
        defer a.free(lock_name);
        const guard = try storage.lock(a, self.io, lock_name);
        defer guard.close(self.io);
        if (try self.verified(kind, key)) |previous| {
            defer previous.file.close(self.io);
            var digest: Key = undefined;
            std.crypto.hash.Blake3.hash(bytes, &digest, .{});
            if (previous.content.size == bytes.len and std.mem.eql(u8, &digest, &previous.content.digest)) return .present;
        }
        const staged = try stage(self, directory);
        defer a.free(staged.path);
        defer storage.remove(self.io, staged.path);
        _ = try stageContents(self.io, staged.file, .{ .bytes = bytes }, .{ .kind = kind, .key = key, .size = bytes.len });
        try self.validate();
        std.Io.Dir.cwd().rename(staged.path, std.Io.Dir.cwd(), target, self.io) catch return error.WriteFailed;
        return .stored;
    }

    /// As `save`, for a caller that judges a disagreement itself (the engine's tier compares results and reads, not bytes): a held
    /// record of other bytes is a `mismatch` that is kept, and nothing is logged; the caller logs the ones it finds real (`mismatch`).
    pub fn offer(self: *Store, kind: Kind, key: Key, bytes: []const u8) Error!Publication {
        if (bytes.len > maximum_payload) return .skipped;
        return self.publish(kind, key, .{ .offered = bytes }, bytes.len);
    }

    /// Stream a private artifact into shared storage without allocating its contents.
    pub fn publishFile(self: *Store, kind: Kind, key: Key, source: []const u8) Error!Publication {
        const file = try storage.regular(self.allocator, self.io, source) orelse return error.ReadFailed;
        defer file.close(self.io);
        const size = (file.stat(self.io) catch return error.ReadFailed).size;
        if (size > maximum_payload) return .skipped;
        return self.publish(kind, key, .{ .file = file }, @intCast(size));
    }

    /// As `publishFile`, for a caller that has already hashed the file and hands over the digest (BLAKE3 of its bytes): the file
    /// is neither read to be hashed nor hashed while it is copied. The digest goes into the record, and every reader checks the
    /// record's bytes against it (`restore`, a later publication), so a wrong digest makes a record that misses, never a wrong program.
    pub fn publishHashedFile(self: *Store, kind: Kind, key: Key, source: []const u8, digest: Key) Error!Publication {
        const file = try storage.regular(self.allocator, self.io, source) orelse return error.ReadFailed;
        defer file.close(self.io);
        const size = (file.stat(self.io) catch return error.ReadFailed).size;
        if (size > maximum_payload) return .skipped;
        return self.publish(kind, key, .{ .hashed = .{ .file = file, .path = source, .digest = digest } }, @intCast(size));
    }

    /// Stream verified bytes to a new private staging file; a corrupt, truncated or
    /// vanished record is a miss and its partial copy is removed. Holds no lease.
    pub fn restore(self: *const Store, kind: Kind, key: Key, destination: []const u8) Error!bool {
        if (kind == .program) return restoreProgram(self, key, destination);
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
        output.setPermissions(self.io, .fromMode(0o600)) catch return error.WriteFailed;
        keep = true;
        self.retentionContext().touch(entry.file);
        return true;
    }

    /// Coordinate expensive native work while retaining the namespace lease; null
    /// while a collection holds the store, so the caller works unclaimed.
    pub fn claim(self: *const Store, kind: Kind, key: Key) work.Error!?work.Claim {
        var hash = std.crypto.hash.Blake3.init(.{});
        hash.update(@tagName(kind));
        hash.update(&key);
        var work_key: Key = undefined;
        hash.final(&work_key);
        return work.Claim.attempt(self.allocator, self.io, self.root, work_key);
    }

    /// Whether the program record for `key` holds exactly the program with BLAKE3 digest `digest`, by its sidecar and the executable's
    /// size, without reading the executable (see `programHeld`).
    pub fn holdsProgram(self: *const Store, key: Key, digest: Key) bool {
        return programHeld(self, key, digest);
    }

    /// Whether an entry of `kind` under `key` is there, by a stat that follows no link and changes no recency. A damaged entry
    /// is present here and a miss when loaded.
    pub fn present(self: *const Store, kind: Kind, key: Key) bool {
        const target = self.artifactPath(kind, key) catch return false;
        defer self.allocator.free(target);
        const found = std.Io.Dir.cwd().statFile(self.io, target, .{ .follow_symlinks = false }) catch return false;
        return found.kind == .file;
    }

    /// Delete the entry of `kind` under `key`: a caller found it wrong. Best effort and absence is success: it is skipped
    /// while a collection holds the store, and taken under the key's publication lock, so it never races a publication's
    /// rename. A reader that has the entry open reads it whole.
    pub fn remove(self: *Store, kind: Kind, key: Key) void {
        const lease = (self.retentionContext().tryLease() catch return) orelse return;
        defer lease.close(self.io);
        const target = self.artifactPath(kind, key) catch return;
        defer self.allocator.free(target);
        const lock_name = std.fmt.allocPrint(self.allocator, "{s}.lock", .{target}) catch return;
        defer self.allocator.free(lock_name);
        const guard = storage.lock(self.allocator, self.io, lock_name) catch return;
        defer guard.close(self.io);
        storage.remove(self.io, target);
    }

    /// Log that the entry of `kind` under `key` holds another result than the one being published: both digests, no
    /// payload, in the store's `mismatches.log`.
    pub fn mismatch(self: *const Store, kind: Kind, key: Key, existing: Key, attempted: Key) void {
        self.retentionContext().mismatch(.{ .kind = @tagName(kind), .key = key, .existing = existing, .attempted = attempted });
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
        return self.entryHeader(kind, key);
    }

    // The entry's open file and what its header says it holds, from a stat and one read of the header; the content is not read.
    fn entryHeader(self: *const Store, kind: Kind, key: Key) Error!?Record {
        const path_name = try self.artifactPath(kind, key);
        defer self.allocator.free(path_name);
        const opened = try storage.regularStat(self.allocator, self.io, path_name) orelse return null;
        const file = opened.file;
        var keep = false;
        defer if (!keep) file.close(self.io);
        const stat = opened.stat;
        const size = stat.size;
        if (size < header_size or size > header_size + maximum_payload) return null;
        var bytes: [header_size]u8 = undefined;
        if ((file.readPositionalAll(self.io, &bytes, 0) catch return error.ReadFailed) != bytes.len) return null;
        const content = decode(&bytes, kind, key) orelse return null;
        if (content.size != size - header_size) return null;
        keep = true;
        return .{ .file = file, .content = content, .modified = stat.mtime.nanoseconds };
    }

    // A record for the key whose payload matches its header; null when absent or damaged.
    fn verified(self: *const Store, kind: Kind, key: Key) Error!?Record {
        const entry = try self.record(kind, key) orelse return null;
        var keep = false;
        defer if (!keep) entry.file.close(self.io);
        const actual = storage.transfer(self.io, entry.file, null, header_size, entry.content.size) catch |err| {
            if (err == error.InputChanged) return null;
            return err;
        };
        if (!std.mem.eql(u8, &actual.digest, &entry.content.digest)) return null;
        keep = true;
        return entry;
    }

    // One per-key lock covers comparison, staging and replacement. An existing
    // verified record is compared by hashing the input in place, so a repeated
    // publication stages nothing and renames nothing; only an absent or damaged
    // record is staged. The lease is only tried: a running sweep skips publication.
    fn publish(self: *Store, kind: Kind, key: Key, input: Input, size: usize) Error!Publication {
        const lease = try self.retentionContext().tryLease() orelse return .skipped;
        defer lease.close(self.io);
        try self.validate();
        const a = self.allocator;
        const directory = try self.path(@tagName(kind));
        defer a.free(directory);
        const bit = @as(u8, 1) << @intCast(@backingInt(kind));
        const known = self.directories.load(.monotonic) & bit != 0;
        if (!known) try self.makeDirectory(directory, bit);
        return self.publishInto(directory, kind, key, input, size) catch |err| {
            // A kind directory that a sweep removed since it was last made: make it again and publish once more.
            if (err != error.WriteFailed or !known) return err;
            _ = self.directories.fetchAnd(~bit, .monotonic);
            try self.makeDirectory(directory, bit);
            return self.publishInto(directory, kind, key, input, size);
        };
    }

    fn makeDirectory(self: *Store, directory: []const u8, bit: u8) Error!void {
        std.Io.Dir.cwd().createDirPath(self.io, directory) catch return error.WriteFailed;
        _ = self.directories.fetchOr(bit, .monotonic);
    }

    // The publication proper, in a kind directory that exists, under the lease `publish` holds.
    fn publishInto(self: *Store, directory: []const u8, kind: Kind, key: Key, given: Input, size: usize) Error!Publication {
        const a = self.allocator;
        // Offered bytes are published as bytes; only a disagreement goes unlogged, for the caller to judge.
        const quiet = given == .offered;
        const input: Input = if (quiet) .{ .bytes = given.offered } else given;
        const cwd = std.Io.Dir.cwd();
        const target = try self.artifactPath(kind, key);
        defer a.free(target);
        const lock_name = try std.fmt.allocPrint(a, "{s}.lock", .{target});
        defer a.free(lock_name);
        const guard = try storage.lock(a, self.io, lock_name);
        defer guard.close(self.io);
        if (kind == .program) return publishProgram(self, key, input, size, target);
        if (try self.verified(kind, key)) |previous| {
            defer previous.file.close(self.io);
            const attempted = try measure(self.io, input, size);
            if (attempted.size == previous.content.size and std.mem.eql(u8, &attempted.digest, &previous.content.digest)) {
                self.retentionContext().touch(previous.file);
                return .present;
            }
            if (quiet) return .mismatch;
            self.retentionContext().mismatch(.{ .kind = @tagName(kind), .key = key, .existing = previous.content.digest, .attempted = attempted.digest });
            return .mismatch;
        }
        const staged = try stage(self, directory);
        defer a.free(staged.path);
        defer storage.remove(self.io, staged.path);
        _ = try stageContents(self.io, staged.file, input, .{ .kind = kind, .key = key, .size = size });
        try self.validate();
        cwd.rename(staged.path, cwd, target, self.io) catch return error.WriteFailed;
        return .stored;
    }
};

// A program record is the linked executable itself, so a worktree's private copy can be a hardlink to it.
// Its size and digest sit in a `.sum` sidecar, published after the executable is renamed into place: a
// reader that finds the executable without a matching sidecar misses. Retention evicts the sidecar with
// its executable and reclaims an orphan one.
const program_sum_magic = "selka-compiler-program-sum-v1\n";

/// The sidecar path of the program record for `key`.
fn programSumPath(self: *const Store, key: Key) Error![]u8 {
    const target = try self.artifactPath(.program, key);
    defer self.allocator.free(target);
    return std.fmt.allocPrint(self.allocator, "{s}.sum", .{target});
}

/// The size and digest the sidecar of the program record for `key` records; null when absent or damaged.
fn programSum(self: *const Store, key: Key) Error!?storage.Content {
    const path_name = try programSumPath(self, key);
    defer self.allocator.free(path_name);
    const bytes = try storage.bounded(self.allocator, self.io, path_name, 256) orelse return null;
    defer self.allocator.free(bytes);
    if (!std.mem.startsWith(u8, bytes, program_sum_magic)) return null;
    var lines = std.mem.splitScalar(u8, bytes[program_sum_magic.len..], '\n');
    const size = std.fmt.parseInt(usize, lines.next() orelse return null, 10) catch return null;
    const hex = lines.next() orelse return null;
    if (hex.len != 64 or !std.mem.eql(u8, lines.rest(), "")) return null;
    var digest: Key = undefined;
    _ = std.fmt.hexToBytes(&digest, hex) catch return null;
    return .{ .size = size, .digest = digest };
}

/// Whether the regular file at `path` has exactly the size and digest `content` records.
fn fileMatches(self: *const Store, path: []const u8, content: storage.Content) Error!bool {
    const file = try storage.regular(self.allocator, self.io, path) orelse return false;
    defer file.close(self.io);
    if ((file.stat(self.io) catch return error.ReadFailed).size != content.size) return false;
    // A file that cannot be read whole is not a verified copy: the caller misses.
    const actual = storage.transfer(self.io, file, null, 0, content.size) catch return false;
    return std.mem.eql(u8, &actual.digest, &content.digest);
}

/// The bytes of the program record for `key`, checked against its sidecar; null when absent or damaged.
fn loadProgram(self: *const Store, a: std.mem.Allocator, key: Key) Error!?[]u8 {
    const content = try programSum(self, key) orelse return null;
    if (content.size > maximum_payload) return null;
    const source = try self.artifactPath(.program, key);
    defer self.allocator.free(source);
    const file = try storage.regular(self.allocator, self.io, source) orelse return null;
    defer file.close(self.io);
    const bytes = try a.alloc(u8, content.size);
    const count = file.readPositionalAll(self.io, bytes, 0) catch 0;
    var digest: Key = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    if (count != bytes.len or !std.mem.eql(u8, &digest, &content.digest)) {
        a.free(bytes);
        return null;
    }
    self.retentionContext().touch(file);
    return bytes;
}

/// Restore the program record for `key` to `destination`: a hardlink (no bytes copied) when the file
/// system allows one, else a verified copy. Either way the bytes handed out are checked against the
/// sidecar, and a damaged record is a miss that leaves nothing at `destination`.
fn restoreProgram(self: *const Store, key: Key, destination: []const u8) Error!bool {
    const content = try programSum(self, key) orelse return false;
    const source = try self.artifactPath(.program, key);
    defer self.allocator.free(source);
    if (linkProgram(self.io, source, destination)) |_| {
        if (try fileMatches(self, destination, content)) return true;
        storage.remove(self.io, destination);
        return false;
    } else |_| {}
    const file = try storage.regular(self.allocator, self.io, source) orelse return false;
    defer file.close(self.io);
    const output = std.Io.Dir.cwd().createFile(self.io, destination, .{ .exclusive = true }) catch return error.WriteFailed;
    defer output.close(self.io);
    var keep = false;
    defer if (!keep) storage.remove(self.io, destination);
    // A copy that fails or does not verify is a miss, and the partial file is removed (`keep`).
    const actual = storage.transfer(self.io, file, output, 0, content.size) catch return false;
    if (!std.mem.eql(u8, &actual.digest, &content.digest)) return false;
    output.setPermissions(self.io, .fromMode(0o500)) catch return error.WriteFailed;
    keep = true;
    return true;
}

/// Make `destination` a second name for the file at `source`; the caller falls back to a copy on error.
fn linkProgram(io: std.Io, source: []const u8, destination: []const u8) std.Io.Dir.HardLinkError!void {
    const cwd = std.Io.Dir.cwd();
    try cwd.hardLink(source, cwd, destination, io, .{});
}

/// Publish a program record: the executable is renamed into place, then its sidecar. A valid record
/// with the same bytes is `present`; one with other bytes is a logged `mismatch` that keeps the first.
fn publishProgram(self: *Store, key: Key, input: Input, size: usize, target: []const u8) Error!Publication {
    if (try programSum(self, key)) |previous| {
        if (try fileMatches(self, target, previous)) {
            const attempted = try measure(self.io, input, size);
            if (attempted.size == previous.size and std.mem.eql(u8, &attempted.digest, &previous.digest)) {
                self.retentionContext().touchPath(target);
                return .present;
            }
            self.retentionContext().mismatch(.{ .kind = "program", .key = key, .existing = previous.digest, .attempted = attempted.digest });
            return .mismatch;
        }
    }
    const directory = std.fs.path.dirname(target) orelse return error.WriteFailed;
    if (try linkedRecord(self, input, size, directory)) |linked| {
        defer self.allocator.free(linked.path);
        defer storage.remove(self.io, linked.path);
        try self.validate();
        std.Io.Dir.cwd().rename(linked.path, std.Io.Dir.cwd(), target, self.io) catch return error.WriteFailed;
        try publishProgramSum(self, key, linked.content, directory);
        return .stored;
    }
    const staged = try stage(self, directory);
    defer self.allocator.free(staged.path);
    defer storage.remove(self.io, staged.path);
    const content = try stageExecutable(self.io, staged.file, input, size);
    try self.validate();
    std.Io.Dir.cwd().rename(staged.path, std.Io.Dir.cwd(), target, self.io) catch return error.WriteFailed;
    try publishProgramSum(self, key, content, directory);
    return .stored;
}

/// A new name in `directory` for the file behind `input`, made as a hardlink: the record then is that file and no bytes are copied
/// (a build writes the program once and the store, the work directory and the output are names of it). Only a caller-hashed file
/// that nobody can write through is linked, because the record must not change under its sidecar: a writable source, another file
/// system, a refused link, and a source whose size is not the size announced all give null, and the caller copies. The caller removes the
/// name it was given, which does nothing once the name was renamed into place.
fn linkedRecord(self: *Store, input: Input, size: usize, directory: []const u8) Error!?Linked {
    const known = switch (input) {
        .hashed => |hashed| hashed,
        else => return null,
    };
    const status = known.file.stat(self.io) catch return error.ReadFailed;
    if (status.size != size or !status.permissions.readOnly()) return null;
    const a = self.allocator;
    for (0..1024) |_| {
        const name = try std.fmt.allocPrint(a, "{s}/.{d}-{x}-{d}.partial", .{ directory, std.os.linux.getpid(), @intFromPtr(self), self.serial.fetchAdd(1, .monotonic) });
        if (linkProgram(self.io, known.path, name)) |_| {
            return .{ .path = name, .content = .{ .size = size, .digest = known.digest } };
        } else |err| {
            a.free(name);
            if (err != error.PathAlreadyExists) return null;
        }
    }
    return null;
}

/// Whether the program record for `key` holds exactly the program with BLAKE3 digest `digest`, by its sidecar and the executable's
/// size, without reading the executable. A build that already has this program in its own store asks it to learn that publishing would
/// find nothing to do; the record is verified by whoever restores it, and by a publication that replaces it. Refreshes the record's
/// recency (retention's record of use) when that is over an hour old.
fn programHeld(self: *const Store, key: Key, digest: Key) bool {
    const recorded = (programSum(self, key) catch return false) orelse return false;
    if (!std.mem.eql(u8, &recorded.digest, &digest)) return false;
    const target = self.artifactPath(.program, key) catch return false;
    defer self.allocator.free(target);
    const status = std.Io.Dir.cwd().statFile(self.io, target, .{ .follow_symlinks = false }) catch return false;
    if (status.kind != .file or status.size != recorded.size) return false;
    const idle = std.Io.Timestamp.now(self.io, .real).nanoseconds - status.mtime.nanoseconds;
    if (idle > recency_interval_ns) self.retentionContext().touchPath(target);
    return true;
}

/// How stale a program record's modification time may get before `holdsProgram` refreshes it: retention's idle limits are days.
const recency_interval_ns: i96 = 3600 * std.time.ns_per_s;

/// Write the executable's bytes into `file` (closing it), readable and executable by its owner only, with no write permission: build outputs are second names for this file (`program_store.place`).
fn stageExecutable(io: std.Io, file: std.Io.File, input: Input, size: usize) Error!storage.Content {
    defer file.close(io);
    const content: storage.Content = switch (input) {
        .bytes, .offered => |bytes| content: {
            file.writeStreamingAll(io, bytes) catch return error.WriteFailed;
            var digest: Key = undefined;
            std.crypto.hash.Blake3.hash(bytes, &digest, .{});
            break :content .{ .size = bytes.len, .digest = digest };
        },
        .file => |source| content: {
            const result = try storage.transfer(io, source, file, 0, size);
            if ((source.stat(io) catch return error.ReadFailed).size != size) return error.InputChanged;
            break :content result;
        },
        .hashed => |known| content: {
            try storage.copy(io, known.file, file, 0, size);
            if ((known.file.stat(io) catch return error.ReadFailed).size != size) return error.InputChanged;
            break :content .{ .size = size, .digest = known.digest };
        },
    };
    file.setPermissions(io, .fromMode(0o500)) catch return error.WriteFailed;
    return content;
}

/// Publish the sidecar of a program record: staged beside it, then renamed into place.
fn publishProgramSum(self: *Store, key: Key, content: storage.Content, directory: []const u8) Error!void {
    const target = try programSumPath(self, key);
    defer self.allocator.free(target);
    const staged = try stage(self, directory);
    defer self.allocator.free(staged.path);
    defer storage.remove(self.io, staged.path);
    const text = try std.fmt.allocPrint(self.allocator, "{s}{d}\n{s}\n", .{ program_sum_magic, content.size, std.fmt.bytesToHex(content.digest, .lower) });
    defer self.allocator.free(text);
    staged.file.writeStreamingAll(self.io, text) catch {
        staged.file.close(self.io);
        return error.WriteFailed;
    };
    staged.file.close(self.io);
    std.Io.Dir.cwd().rename(staged.path, std.Io.Dir.cwd(), target, self.io) catch return error.WriteFailed;
}

const Record = struct { file: std.Io.File, content: storage.Content, modified: i96 };

/// How old an entry's recency may be before a probe that finds it still wanted refreshes it: retention works in days, so a probe that
/// finds the entry touched within the hour has nothing to add.
const recency_grain_ns: i96 = 60 * 60 * std.time.ns_per_s;
/// A program record's new name, made as a hardlink of the caller's file, and the size and digest it holds.
const Linked = struct { path: []u8, content: storage.Content };
/// What a publication stores: bytes, a file, a file whose digest is known, or bytes whose disagreement the caller judges (`offer`).
const Input = union(enum) { bytes: []const u8, file: std.Io.File, hashed: Hashed, offered: []const u8 };
/// A file whose digest the caller computed, open and by the path it was opened from (a program record may become a second name for it).
const Hashed = struct { file: std.Io.File, path: []const u8, digest: Key };
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

// The input's length and digest, read in place without writing a copy.
fn measure(io: std.Io, input: Input, size: usize) Error!storage.Content {
    switch (input) {
        .bytes, .offered => |bytes| {
            var digest: Key = undefined;
            std.crypto.hash.Blake3.hash(bytes, &digest, .{});
            return .{ .size = bytes.len, .digest = digest };
        },
        .file => |source| {
            const result = try storage.transfer(io, source, null, 0, size);
            if ((source.stat(io) catch return error.ReadFailed).size != size) return error.InputChanged;
            return result;
        },
        .hashed => |known| {
            if ((known.file.stat(io) catch return error.ReadFailed).size != size) return error.InputChanged;
            return .{ .size = size, .digest = known.digest };
        },
    }
}

fn stageContents(io: std.Io, file: std.Io.File, input: Input, address: Address) Error!storage.Content {
    defer file.close(io);
    file.writeStreamingAll(io, &@as([header_size]u8, @splat(0))) catch return error.WriteFailed;
    const content: storage.Content = switch (input) {
        .bytes, .offered => |bytes| content: {
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
        .hashed => |known| content: {
            try storage.copy(io, known.file, file, 0, address.size);
            if ((known.file.stat(io) catch return error.ReadFailed).size != address.size) return error.InputChanged;
            break :content .{ .size = address.size, .digest = known.digest };
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

// spec-case: SHARED-STORE-4
test "openSelected fails an explicit unusable store and skips an unusable default one" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    try temporary.dir.writeFile(io, .{ .sub_path = ".cache", .data = "a file where the cache directory belongs" });
    var environment: std.process.Environ.Map = .init(a);
    defer environment.deinit();
    try environment.put("HOME", root);
    try std.testing.expect((try openSelectedWith(a, io, &environment, false)) == null);
    try std.testing.expect((try openSelectedWith(a, io, &environment, true)) == null);
    try temporary.dir.deleteFile(io, ".cache");
    var default = (try openSelectedWith(a, io, &environment, true)).?;
    defer default.deinit();
    try std.testing.expect(std.mem.endsWith(u8, default.root, ".cache/selka/compiler-artifacts/compiler-artifacts-v2"));
    try temporary.dir.writeFile(io, .{ .sub_path = "blocked", .data = "not a directory" });
    try environment.put(environment_variable, try std.fs.path.join(a, &.{ root, "blocked" }));
    try std.testing.expectError(error.WriteFailed, openSelectedWith(a, io, &environment, true));
    try std.testing.expectError(error.WriteFailed, openSelected(a, io, &environment));
    try environment.put(environment_variable, "");
    try std.testing.expect((try openSelected(a, io, &environment)) == null);
}

const concurrent_publishers = 8;
const concurrent_keys = 16;

// One thread's open of a fresh store and its publication of every shared key.
const ConcurrentPublisher = struct {
    root: []const u8,
    backing: std.mem.Allocator,
    start: *const std.atomic.Value(bool),
    failure: ?anyerror = null,
    stored: usize = 0,
    mismatches: usize = 0,

    fn run(self: *ConcurrentPublisher) void {
        self.publishAll() catch |err| {
            self.failure = err;
        };
    }

    fn publishAll(self: *ConcurrentPublisher) !void {
        while (!self.start.load(.acquire)) std.atomic.spinLoopHint();
        var arena = std.heap.ArenaAllocator.init(self.backing);
        defer arena.deinit();
        var store = try Store.open(arena.allocator(), std.testing.io, self.root);
        defer store.deinit();
        for (0..concurrent_keys) |index| {
            const key = concurrentKey(index);
            switch (try store.save(.syntax, key, &key)) {
                .stored => self.stored += 1,
                .mismatch => self.mismatches += 1,
                .present, .skipped => {},
            }
        }
    }
};

fn concurrentKey(index: usize) Key {
    return @splat(@intCast(index + 1));
}

// Start every publisher at once against one store root and wait for all.
fn publishConcurrently(root: []const u8, backing: std.mem.Allocator, publishers: *[concurrent_publishers]ConcurrentPublisher) !void {
    var start: std.atomic.Value(bool) = .init(false);
    var threads: [concurrent_publishers]std.Thread = undefined;
    var started: usize = 0;
    defer for (threads[0..started]) |thread| thread.join();
    // Release the started publishers before joining, even when a spawn fails.
    defer start.store(true, .release);
    for (publishers, &threads) |*publisher, *thread| {
        publisher.* = .{ .root = root, .backing = backing, .start = &start };
        thread.* = try std.Thread.spawn(.{}, ConcurrentPublisher.run, .{publisher});
        started += 1;
    }
}

const ConcurrentTotals = struct { failures: usize = 0, stored: usize = 0, mismatches: usize = 0 };

fn concurrentTotals(publishers: []const ConcurrentPublisher) ConcurrentTotals {
    var totals: ConcurrentTotals = .{};
    for (publishers) |publisher| {
        if (publisher.failure != null) totals.failures += 1;
        totals.stored += publisher.stored;
        totals.mismatches += publisher.mismatches;
    }
    return totals;
}

// Every key holds exactly its bytes; a sequential republication finds them
// present (or stores one a sweep made every publisher skip), never a mismatch.
fn expectConcurrentRecords(store: *Store, a: std.mem.Allocator) !void {
    for (0..concurrent_keys) |index| {
        const key = concurrentKey(index);
        const again = try store.save(.syntax, key, &key);
        try std.testing.expect(again == .present or again == .stored);
        try std.testing.expectEqualSlices(u8, &key, (try store.load(a, .syntax, key)).?);
    }
}

// Staged partial files left in a tier directory; a finished publication leaves none.
fn leftoverPartials(io: std.Io, directory: []const u8) !usize {
    var tier = try std.Io.Dir.cwd().openDir(io, directory, .{ .iterate = true });
    defer tier.close(io);
    var entries = tier.iterate();
    var partials: usize = 0;
    while (try entries.next(io)) |entry| {
        if (std.mem.endsWith(u8, entry.name, ".partial")) partials += 1;
    }
    return partials;
}

// spec: SHARED-STORE-6
test "concurrent first openers initialize one fresh compiler store and publish every key once without failure or mismatch" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try std.fs.path.join(a, &.{ try temporary.dir.realPathFileAlloc(io, ".", a), "fresh", "store" });
    var publishers: [concurrent_publishers]ConcurrentPublisher = undefined;
    try publishConcurrently(root, std.testing.allocator, &publishers);
    const totals = concurrentTotals(&publishers);
    try std.testing.expectEqual(@as(usize, 0), totals.failures);
    try std.testing.expectEqual(@as(usize, 0), totals.mismatches);
    try std.testing.expect(totals.stored <= concurrent_keys);
    var store = try Store.open(a, io, root);
    defer store.deinit();
    try expectConcurrentRecords(&store, a);
    try std.testing.expectEqualStrings(format, (try storage.bounded(a, io, try store.path("format"), 128)).?);
    try std.testing.expectEqual(@as(?[]u8, null), try storage.bounded(a, io, try store.path("mismatches.log"), 4096));
    try std.testing.expectEqual(@as(usize, 0), try leftoverPartials(io, try store.path("syntax")));
}

// spec-case: SHARED-STORE-4
test "a compiler store that lost its marker is adopted with its records, and a wrong marker or a foreign file is refused" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(io, ".", a);
    const key: Key = @splat(5);
    var store = try Store.open(a, io, root);
    try std.testing.expectEqual(Publication.stored, try store.save(.syntax, key, "an artifact that outlives its marker"));
    store.deinit();
    try temporary.dir.deleteFile(io, "compiler-artifacts-v2/format");
    var lost = try Store.open(a, io, root);
    defer lost.deinit();
    try std.testing.expectEqualStrings(format, (try storage.bounded(a, io, try lost.path("format"), 128)).?);
    try std.testing.expectEqualStrings("an artifact that outlives its marker", (try lost.load(a, .syntax, key)).?);
    try temporary.dir.writeFile(io, .{ .sub_path = "compiler-artifacts-v2/format", .data = "selka-compiler-artifact-store-v1\n" });
    try std.testing.expectError(error.ReadFailed, Store.open(a, io, root));
    try std.testing.expectEqualStrings("selka-compiler-artifact-store-v1\n", (try storage.bounded(a, io, try lost.path("format"), 128)).?);
    try temporary.dir.deleteFile(io, "compiler-artifacts-v2/format");
    try temporary.dir.writeFile(io, .{ .sub_path = "compiler-artifacts-v2/notes.txt", .data = "not this cache's" });
    try std.testing.expectError(error.ReadFailed, Store.open(a, io, root));
    try std.testing.expectEqual(@as(?[]u8, null), try storage.bounded(a, io, try lost.path("format"), 128));
}

test "engine entries are found by a stat, removed under the key's lock, and kept apart by kind" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try Store.open(a, io, try temporary.dir.realPathFileAlloc(io, ".", a));
    defer store.deinit();
    const key: Key = @splat(7);
    try std.testing.expect(!store.present(.engine_record, key));
    try std.testing.expectEqual(Publication.stored, try store.save(.engine_record, key, "record"));
    try std.testing.expectEqual(Publication.stored, try store.save(.engine_object, key, "object"));
    try std.testing.expect(store.present(.engine_record, key) and store.present(.engine_object, key));
    try std.testing.expectEqualStrings("record", (try store.load(a, .engine_record, key)).?);
    store.remove(.engine_record, key);
    try std.testing.expect(!store.present(.engine_record, key));
    try std.testing.expect(store.present(.engine_object, key));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .engine_record, key));
    // Absence is success, and a removed key can be published again.
    store.remove(.engine_record, key);
    try std.testing.expectEqual(Publication.stored, try store.save(.engine_record, key, "another record"));
    // Another result under a held key is logged, and the entry stays.
    try std.testing.expectEqual(Publication.mismatch, try store.save(.engine_record, key, "a third record"));
    try std.testing.expectEqualStrings("another record", (try store.load(a, .engine_record, key)).?);
}

test "an entry is told to hold exactly its bytes by its header, without a read of its content, and a stale entry is refreshed by the probe" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const io = std.testing.io;
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    var store = try Store.open(a, io, try temporary.dir.realPathFileAlloc(io, ".", a));
    defer store.deinit();
    const key: Key = @splat(9);
    try std.testing.expect(!store.holds(.engine_record, key, "record"));
    try std.testing.expectEqual(Publication.stored, try store.save(.engine_record, key, "record"));
    try std.testing.expect(store.holds(.engine_record, key, "record"));
    // The same length with other bytes, another length and another key are not it, and a program entry is never probed.
    try std.testing.expect(!store.holds(.engine_record, key, "rec0rd"));
    try std.testing.expect(!store.holds(.engine_record, key, "records"));
    try std.testing.expect(!store.holds(.engine_record, @splat(8), "record"));
    try std.testing.expect(!store.holds(.program, key, "record"));
    // The probe reads the header: a content damaged after the header was written still passes it, and the reader that loads the content
    // finds it does not hash to its digest and misses.
    const path = try store.artifactPath(.engine_record, key);
    defer store.allocator.free(path);
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write });
    defer file.close(io);
    try file.writePositionalAll(io, "R", header_size);
    try std.testing.expect(store.holds(.engine_record, key, "record"));
    try std.testing.expectEqual(@as(?[]u8, null), try store.load(a, .engine_record, key));
    // An entry whose recency is older than the grain is refreshed by a probe that finds it; a recent one is left as it is.
    try std.testing.expectEqual(Publication.stored, try store.save(.engine_record, @splat(10), "fresh"));
    const old: i96 = 1_000_000_000;
    const stale = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_write });
    defer stale.close(io);
    try stale.setTimestamps(io, .{ .modify_timestamp = .{ .new = .{ .nanoseconds = old } } });
    try std.testing.expect(store.holds(.engine_record, key, "record"));
    try std.testing.expect((try stale.stat(io)).mtime.nanoseconds > old);
}
