//! Persistent, content-addressed reuse of parsed module syntax and successful
//! whole-program check verdicts for ordinary one-shot commands.
//!
//! Every entry is named by the SHA-256 of the exact inputs that produced it, and
//! its own header repeats that key plus a checksum over the payload. A hit
//! therefore requires byte equality of the source, the compiler build identity,
//! the output format and the module set; a damaged, truncated or foreign entry is
//! discarded and the caller checks fresh. Nothing here can turn a changed source
//! into a stale success: a verdict hit only ever replays previously rendered
//! warning text for an identical, already-successful project.
//!
//! What is deliberately *not* stored: checked typed programs, symbol indexes,
//! interfaces and declaration resolution. Those always run fresh, so a changed
//! declaration, visibility or effect bound is never masked by a cache hit.
const std = @import("std");
const product = @import("product.zig");
const source_digest = @import("source_digest.zig");
const ast = @import("ast.zig");
const source = @import("source.zig");
const codec = @import("persist_codec.zig");
const diagnostic_output = @import("diagnostic_output.zig");
const project = @import("project.zig");
const cache_key = @import("cache_key.zig");
const shared_artifacts = @import("shared_artifact_store.zig");
const module_records = @import("module_records.zig");
const syntax_store = @import("syntax_store.zig");
const lazy_module = @import("lazy_module.zig");

/// Bump when the on-disk layout or a stored serializer changes; older files miss.
pub const format_version = "selka-frontend-cache-v16";
/// Default retention floor: entries above this are bypassed, and a run that
/// stored anything trims the directory back to the larger of this and twice
/// the bytes the run itself used (FRONTEND-CACHE-RETAIN-1).
pub const default_max_bytes: usize = 128 * 1024 * 1024;
/// Entry bytes a project may need per byte of its source (FRONTEND-CACHE-ENTRY-1).
pub const entry_bytes_per_source_byte: usize = 8;
/// Default per-project cache directory for one-shot commands.
pub const default_directory = product.work_dir ++ "/frontend";

/// Parsed-syntax observations from the lookup execution site: a `hit` actually
/// returned stored syntax, a `miss` fell through to a real lex/parse.
pub const SyntaxCounters = struct {
    hits: usize = 0,
    misses: usize = 0,
    stored: usize = 0,
};
/// Successful whole-program verdict observations from the lookup site: a `hit`
/// actually replayed stored warnings.
pub const VerdictCounters = struct {
    hits: usize = 0,
    misses: usize = 0,
    stored: usize = 0,
};
/// Cumulative reuse counters; all are actual observed work, not estimates.
pub const Statistics = struct {
    syntax: SyntaxCounters = .{},
    verdict: VerdictCounters = .{},
    /// Entries rejected because key, header or checksum did not match.
    damaged: usize = 0,
    bypassed: usize = 0,
    evicted: usize = 0,
    retained_bytes: usize = 0,
    /// Entry bytes this run read back or stored: its working set, which the
    /// retention budget keeps twice over (FRONTEND-CACHE-RETAIN-1).
    used_bytes: usize = 0,
};

/// Allocator and I/O handle shared by every cache operation.
const Runtime = struct {
    allocator: std.mem.Allocator,
    io: std.Io,
    /// Required import policy identity when the entry project configures one.
    /// Only the successful-verdict key consumes it: a changed or stricter
    /// policy must not replay an earlier pass, while syntax parsing stays
    /// independent of policy acceptance. Owned by `allocator`; assign it only
    /// through `Cache.setPolicyIdentity`.
    policy_identity: ?[]const u8 = null,
    /// Whether this run stored an entry, so `finish` has a directory to trim.
    stored: bool = false,
    /// Optional immutable transport; rendered warnings and summaries stay local.
    shared: ?*shared_artifacts.Store = null,
    /// The identity of the code that decides which summaries are stored (the ownership and lowering omission policy).
    /// Summary keys fold it in; syntax and body keys do not. Set through `setSummaryPolicy`; empty when unset.
    summary_policy: []const u8 = "",
};

/// Which check keeps an entry's summary table. An executable check and every lowering command
/// share the `entry` slot. A library check has its own, so the stand-ins an executable check
/// reads never come from a library check's table, and it is keyed by the entry's path as given:
/// two entries that share a name and a module path under different directories (a tree and its
/// copy) keep a slot each, and neither starts out primed by the other's first check.
pub const SummarySlot = union(enum) { entry, library: []const u8 };

/// One bounded, caller-serialized directory of immutable entries.
pub const Cache = struct {
    /// Allocator and I/O handle bundled so the Wave-3 contract stays a
    /// first-class field without exceeding the type-size ratchet.
    runtime: Runtime,
    /// Root directory; the compiler identity partitions identities that never mix.
    root: []const u8,
    max_bytes: usize = default_max_bytes,
    /// Embedded build-time compiler identity; a rebuild never reuses old entries.
    identity: []const u8,
    /// Full Wave-3 contract. Its fingerprint is mixed into every content key so a
    /// changed target, runtime ABI, bootstrap language, capabilities contract, flag set
    /// or compiler identity can never replay an entry from another contract.
    contract: cache_key.Contract = .default,
    /// Whether `root` was allocated by the caller and must be released by deinit.
    root_owned: bool = false,
    statistics: Statistics = .{},

    /// Open a persistent cache rooted at `root` for one compiler build identity.
    /// The cache owns no files until the first successful store and holds no
    /// retained in-memory state, so deinit only releases borrows it never took.
    pub fn init(allocator: std.mem.Allocator, io: std.Io, root: []const u8, identity: []const u8) Cache {
        return .{ .runtime = .{ .allocator = allocator, .io = io }, .root = root, .identity = identity };
    }
    /// Open a cache with an explicit Wave-3 contract. Callers that only have an
    /// identity keep using `init`; the contract may also be assigned afterwards.
    pub fn initWithContract(allocator: std.mem.Allocator, io: std.Io, root: []const u8, identity: []const u8, contract: cache_key.Contract) Cache {
        return .{ .runtime = .{ .allocator = allocator, .io = io }, .root = root, .identity = identity, .contract = contract };
    }
    /// Hex contract fingerprint for key and namespace construction.
    fn contractHex(self: *Cache) [64]u8 {
        var hex: [64]u8 = undefined;
        self.contract.fingerprintHex(&hex);
        return hex;
    }
    /// FRONTEND-CACHE-RETAIN-1: once a run is done, bound the directory by the
    /// budget `retention` gives, evicting the least recently used entries.
    /// Trimming only here, and not after every store, means the budget sees
    /// the whole working set and the directory is listed once per run rather
    /// than once per stored entry. A run that stored nothing leaves it alone.
    pub fn finish(self: *Cache) void {
        if (!self.runtime.stored) return;
        self.runtime.stored = false;
        self.trim() catch return;
    }
    /// Store a small record that is rewritten in place and kept out of the run's accounting: `finish` does not trim the directory because
    /// of it, and `runtime.stored` keeps saying whether an entry with a working set was stored (the digest memo, `file_digests.zig`).
    pub fn writeRecord(self: *Cache, key: [32]u8, payload: []const u8) error{ OutOfMemory, WriteFailed }!void {
        const stored = self.runtime.stored;
        const used = self.statistics.used_bytes;
        defer {
            self.runtime.stored = stored;
            self.statistics.used_bytes = used;
        }
        _ = try self.write(key, payload);
    }
    /// FRONTEND-CACHE-ENTRY-1: fit the per-entry ceiling to a loaded project of
    /// `source_bytes`: the larger of the configured ceiling and eight bytes per
    /// source byte. A project's largest entry, its check summaries, is about
    /// one byte per source byte (39 MB at a million lines), and a module's
    /// syntax about eight per byte of that module, so neither is refused at
    /// any project size, while a damaged length still cannot make a read
    /// allocate more than the project could have produced. The retention
    /// floor rises with it; the working set is already that large.
    pub fn fitProject(self: *Cache, source_bytes: usize) void {
        self.max_bytes = @max(self.max_bytes, entry_bytes_per_source_byte *| source_bytes);
    }
    /// The directory's retention budget: the configured floor, or twice the
    /// bytes this run used when that is larger, so a project whose working set
    /// outgrows the floor keeps all of it plus as much again of history
    /// instead of evicting every entry on every run.
    pub fn retention(self: *const Cache) usize {
        return @max(self.max_bytes, 2 *| self.statistics.used_bytes);
    }
    /// Release the caller-owned root path, if any, and the owned policy
    /// identity; entries stay on disk.
    pub fn deinit(self: *Cache) void {
        if (self.root_owned) self.runtime.allocator.free(self.root);
        if (self.runtime.policy_identity) |owned| self.runtime.allocator.free(owned);
        self.runtime.policy_identity = null;
    }
    /// Name the identity of the summary policy (the omission decisions of the ownership and lowering callbacks). The
    /// caller keeps the bytes alive for the cache's lifetime.
    pub fn setSummaryPolicy(self: *Cache, identity: []const u8) void {
        self.runtime.summary_policy = identity;
    }

    /// Replace the policy identity the verdict key folds in with an owned copy
    /// of `identity` (null clears it), so the caller's buffer may die
    /// afterwards. On OutOfMemory the previous identity stays in place.
    pub fn setPolicyIdentity(self: *Cache, identity: ?[]const u8) error{OutOfMemory}!void {
        const owned = if (identity) |bytes| try self.runtime.allocator.dupe(u8, bytes) else null;
        if (self.runtime.policy_identity) |previous| self.runtime.allocator.free(previous);
        self.runtime.policy_identity = owned;
    }

    /// The module header records this cache keeps for the project loader: one entry per record, named by its content key
    /// and stored under this cache's identity and contract, so retention bounds them with the rest.
    pub fn records(self: *Cache) module_records.Records {
        return .{ .context = self, .fetch = fetchRecord, .store = storeRecord };
    }

    fn fetchRecord(context: ?*anyopaque, allocator: std.mem.Allocator, key: [32]u8) ?[]u8 {
        const self: *Cache = @ptrCast(@alignCast(context.?));
        if (self.read(key)) |payload| {
            defer self.runtime.allocator.free(payload);
            return allocator.dupe(u8, payload) catch null;
        } else |_| {}
        // A fresh work directory has none: another worktree of the project may have published it.
        const store = self.runtime.shared orelse return null;
        if (store.load(allocator, .frontend, self.sharedRecordKey(key))) |found| {
            return found;
        } else |err| {
            store.reportFailure(err);
            return null;
        }
    }

    fn storeRecord(context: ?*anyopaque, key: [32]u8, payload: []const u8) void {
        const self: *Cache = @ptrCast(@alignCast(context.?));
        _ = self.write(key, payload) catch {
            self.statistics.bypassed += 1;
        };
        const store = self.runtime.shared orelse return;
        _ = store.save(.frontend, self.sharedRecordKey(key), payload) catch |err| store.reportFailure(err);
    }

    /// The shared tier's key of a header record: its own key under this cache's compiler identity and contract, and no path.
    fn sharedRecordKey(self: *Cache, key: [32]u8) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        frame(&hash, "shared-frontend-record-v1");
        frame(&hash, format_version);
        frame(&hash, self.identity);
        const contract = self.contractHex();
        hash.update(&contract);
        hash.update(&key);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// Borrow the process-owned immutable artifact store for parsed syntax only.
    pub fn setSharedStore(self: *Cache, store: ?*shared_artifacts.Store) void {
        self.runtime.shared = store;
    }

    /// The directory holding entries for this compiler identity.
    fn namespace(self: *Cache) ![]const u8 {
        const tag = std.fmt.bytesToHex(self.identityHash(), .lower);
        return std.fs.path.join(self.runtime.allocator, &.{ self.root, &tag });
    }
    fn identityHash(self: *Cache) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update("frontend-cache-identity-v3");
        frame(&hash, self.identity);
        const contract = self.contractHex();
        hash.update(&contract);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// Copy parsed module syntax for an exact path/bytes/body-start match, or null.
    /// The returned program owns all of its storage through `allocator`.
    pub fn lookupSyntax(self: *Cache, allocator: std.mem.Allocator, src: source.Source, body_start: usize) error{ OutOfMemory, InternalError }!?ast.Program {
        return self.lookupSyntaxOf(allocator, src, source_digest.of(src.bytes), body_start);
    }

    /// `lookupSyntax` for a source whose `digest` (`source_digest.of` its bytes) the caller holds: the key takes the digest in place of the
    /// bytes, so a module is hashed once per command.
    pub fn lookupSyntaxOf(self: *Cache, allocator: std.mem.Allocator, src: source.Source, digest: [32]u8, body_start: usize) error{ OutOfMemory, InternalError }!?ast.Program {
        const key = syntaxKeyOf(self, src, digest, body_start);
        // Decoding copies everything it keeps, so the payload is decoded in
        // place in the file buffer rather than copied out of it first.
        const entry = self.readEntry(key, .whole) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Damaged => {
                self.statistics.damaged += 1;
                return self.lookupSharedSyntax(allocator, src, digest, body_start);
            },
            else => {
                return self.lookupSharedSyntax(allocator, src, digest, body_start);
            },
        };
        defer self.runtime.allocator.free(entry.bytes);
        const program = syntax_store.reassemble(allocator, entry.payload) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.damaged += 1;
                return self.lookupSharedSyntax(allocator, src, digest, body_start);
            },
        };
        self.statistics.syntax.hits += 1;
        return program;
    }

    /// The bytes of the largest prefix a first read takes: most modules' declaration parts fit, so a hit is one read.
    const first_read = 32 * 1024;

    /// The stored syntax of a source as far as its declaration part, or null when there is none: the bodies stay on disk (or in the shared
    /// tier's payload) until the returned module is asked for them (`lazy_module.Module.entry`). A damaged declaration part is a miss, as
    /// a damaged entry is for `lookupSyntaxOf`; a damaged body is found when it is read, and its module is parsed again then.
    pub fn lookupSyntaxLazyOf(self: *Cache, allocator: std.mem.Allocator, src: source.Source, digest: [32]u8, body_start: usize) error{ OutOfMemory, InternalError }!?*lazy_module.Module {
        const key = syntaxKeyOf(self, src, digest, body_start);
        const stored = self.readPrefix(allocator, key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Damaged => {
                self.statistics.damaged += 1;
                return self.lookupSharedSyntaxLazy(allocator, src, digest, body_start);
            },
            else => return self.lookupSharedSyntaxLazy(allocator, src, digest, body_start),
        };
        self.statistics.syntax.hits += 1;
        return stored;
    }

    fn lookupSharedSyntaxLazy(self: *Cache, allocator: std.mem.Allocator, src: source.Source, digest: [32]u8, body_start: usize) error{ OutOfMemory, InternalError }!?*lazy_module.Module {
        const store = if (portableSyntax(src)) self.runtime.shared else null;
        const payload = if (store) |shared| shared.load(allocator, .syntax, self.sharedSyntaxKey(digest, body_start)) catch |err| return sharedError(shared, err) else null;
        if (payload) |bytes| {
            const module = try allocator.create(lazy_module.Module);
            const header = syntax_store.Header.parse(bytes) catch return self.missedSyntax();
            if (bytes.len < header.prefixLen()) return self.missedSyntax();
            module.* = .{ .declarations = syntax_store.decodeDeclarations(allocator, bytes[0..@intCast(header.prefixLen())]) catch return self.missedSyntax(), .whole = bytes, .fetch = null };
            self.statistics.syntax.hits += 1;
            return module;
        }
        self.statistics.syntax.misses += 1;
        return null;
    }

    fn missedSyntax(self: *Cache) ?*lazy_module.Module {
        self.statistics.damaged += 1;
        self.statistics.syntax.misses += 1;
        return null;
    }

    /// Where a module's entry is read from when its first body is asked for: this cache and the entry's key.
    const EntryReader = struct {
        cache: *Cache,
        key: [32]u8,

        fn read(context: ?*anyopaque, allocator: std.mem.Allocator) std.mem.Allocator.Error!?[]const u8 {
            const self: *EntryReader = @ptrCast(@alignCast(context.?));
            const entry = self.cache.readEntryPayload(allocator, self.key) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => return null,
            };
            return entry;
        }
    };

    /// The payload of the entry stored under `key`, whole, without the checksum of the whole (every section of a syntax entry carries its
    /// own, and `decodeBody` checks it). Owned by `allocator`.
    fn readEntryPayload(self: *Cache, allocator: std.mem.Allocator, key: [32]u8) error{ OutOfMemory, NotFound, Damaged, ReadFailed }![]const u8 {
        var file = try self.openEntry(key);
        defer file.close(self.runtime.io);
        const length = file.length(self.runtime.io) catch return error.ReadFailed;
        if (length < headerSize or length > self.max_bytes + headerSize) return error.Damaged;
        const bytes = try allocator.alloc(u8, @intCast(length));
        if ((file.readPositionalAll(self.runtime.io, bytes, 0) catch return error.ReadFailed) != bytes.len) return error.Damaged;
        const payload = try framedPayload(bytes, key);
        return payload;
    }

    fn openEntry(self: *Cache, key: [32]u8) error{ OutOfMemory, NotFound, ReadFailed }!std.Io.File {
        const directory = try self.namespace();
        defer self.runtime.allocator.free(directory);
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ directory, &std.fmt.bytesToHex(key, .lower) }) catch return error.ReadFailed;
        return std.Io.Dir.cwd().openFile(self.runtime.io, path, .{}) catch |err| switch (err) {
            error.FileNotFound => error.NotFound,
            else => error.ReadFailed,
        };
    }

    /// Read the front of the entry stored under `key`: its frame and the declaration part of the syntax it holds, the first
    /// `first_read` bytes in one read and the rest of the prefix in a second when the declarations are longer. The module keeps the
    /// bytes it read as the start of the entry; the bodies are read later.
    fn readPrefix(self: *Cache, allocator: std.mem.Allocator, key: [32]u8) error{ OutOfMemory, NotFound, Damaged, ReadFailed }!*lazy_module.Module {
        var file = try self.openEntry(key);
        defer file.close(self.runtime.io);
        const length = file.length(self.runtime.io) catch return error.ReadFailed;
        if (length < headerSize + syntax_store.Header.size or length > self.max_bytes + headerSize) return error.Damaged;
        const total: usize = @intCast(length);
        const first = @min(total, first_read);
        var front = try allocator.alloc(u8, first);
        if ((file.readPositionalAll(self.runtime.io, front, 0) catch return error.ReadFailed) != first) return error.Damaged;
        const payload_start = frameStart(front, key) orelse return error.Damaged;
        const header = syntax_store.Header.parse(front[payload_start..]) catch return error.Damaged;
        const prefix_end = std.math.add(u64, payload_start, header.prefixLen()) catch return error.Damaged;
        if (prefix_end > total) return error.Damaged;
        if (prefix_end > front.len) {
            const wider = try allocator.alloc(u8, @intCast(prefix_end));
            @memcpy(wider[0..front.len], front);
            if ((file.readPositionalAll(self.runtime.io, wider[front.len..], front.len) catch return error.ReadFailed) != wider.len - front.len) return error.Damaged;
            front = wider;
        }
        const declarations = syntax_store.decodeDeclarations(allocator, front[payload_start..@intCast(prefix_end)]) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.Damaged,
        };
        // A hit renews the entry, as `readEntry` does: eviction goes by last use.
        file.setTimestampsNow(self.runtime.io) catch |err| switch (err) {
            error.ReadOnlyFileSystem => {},
            else => {},
        };
        self.statistics.used_bytes +|= front.len;
        const module = try allocator.create(lazy_module.Module);
        module.* = .{ .declarations = declarations, .whole = null, .fetch = null };
        if (front.len == total) {
            module.whole = framedPayload(front, key) catch return error.Damaged;
        } else {
            const reader = try allocator.create(EntryReader);
            reader.* = .{ .cache = self, .key = key };
            module.fetch = .{ .context = reader, .read = EntryReader.read };
        }
        return module;
    }

    fn lookupSharedSyntax(self: *Cache, allocator: std.mem.Allocator, src: source.Source, digest: [32]u8, body_start: usize) error{ OutOfMemory, InternalError }!?ast.Program {
        const store = if (portableSyntax(src)) self.runtime.shared else null;
        const payload = if (store) |shared| shared.load(self.runtime.allocator, .syntax, self.sharedSyntaxKey(digest, body_start)) catch |err| return sharedError(shared, err) else null;
        if (payload) |bytes| {
            defer self.runtime.allocator.free(bytes);
            const program = syntax_store.reassemble(allocator, bytes) catch |err| switch (err) {
                error.OutOfMemory => return error.OutOfMemory,
                else => {
                    self.statistics.damaged += 1;
                    self.statistics.syntax.misses += 1;
                    return null;
                },
            };
            self.statistics.syntax.hits += 1;
            return program;
        }
        self.statistics.syntax.misses += 1;
        return null;
    }

    /// Retain parsed syntax under its exact path/bytes/body-start key.
    pub fn rememberSyntax(self: *Cache, src: source.Source, body_start: usize, syntax: ast.Program) error{ OutOfMemory, InternalError }!void {
        return self.rememberSyntaxOf(src, source_digest.of(src.bytes), body_start, syntax);
    }

    /// `rememberSyntax` for a source whose `digest` the caller holds.
    pub fn rememberSyntaxOf(self: *Cache, src: source.Source, digest: [32]u8, body_start: usize, syntax: ast.Program) error{ OutOfMemory, InternalError }!void {
        const key = syntaxKeyOf(self, src, digest, body_start);
        const bytes = syntax_store.encode(self.runtime.allocator, src, syntax) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return,
        };
        defer self.runtime.allocator.free(bytes);
        if (portableSyntax(src)) {
            if (self.runtime.shared) |shared| _ = shared.save(.syntax, self.sharedSyntaxKey(digest, body_start), bytes) catch |err| return sharedError(shared, err);
        }
        const stored = self.write(key, bytes) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.bypassed += 1;
                return;
            },
        };
        if (stored) self.statistics.syntax.stored += 1;
    }

    /// Copy the rendered warning text of an identical, successful project, or null.
    /// Warning storage belongs to `allocator`.
    pub fn lookupVerdict(self: *Cache, allocator: std.mem.Allocator, loaded: *const project.Project, format: diagnostic_output.Format) error{OutOfMemory}!?[]const u8 {
        if (!loaded.progress.complete or loaded.problem != null) {
            self.statistics.verdict.misses += 1;
            return null;
        }
        const key = verdictKeyFor(self, loaded, format);
        const payload = self.read(key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Damaged => {
                self.statistics.verdict.misses += 1;
                self.statistics.damaged += 1;
                return null;
            },
            else => {
                self.statistics.verdict.misses += 1;
                return null;
            },
        };
        defer self.runtime.allocator.free(payload);
        const warnings = decodeWarnings(allocator, payload) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.verdict.misses += 1;
                self.statistics.damaged += 1;
                return null;
            },
        };
        self.statistics.verdict.hits += 1;
        return warnings;
    }

    /// Retain one successful verdict's rendered warnings for an identical project.
    /// Only complete, error-free checks may be remembered.
    pub fn rememberVerdict(self: *Cache, loaded: *const project.Project, format: diagnostic_output.Format, warnings: []const u8) error{OutOfMemory}!void {
        if (!loaded.progress.complete or loaded.problem != null) return;
        const key = verdictKeyFor(self, loaded, format);
        var writer = codec.Writer.init(self.runtime.allocator);
        defer writer.deinit();
        writer.integer(@as(u64, warnings.len)) catch |err| return err;
        writer.raw(warnings) catch |err| return err;
        const stored = self.write(key, writer.bytes.items) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.bypassed += 1;
                return;
            },
        };
        if (stored) self.statistics.verdict.stored += 1;
    }

    /// The check summaries last remembered for this project's entry, or null.
    /// The payload belongs to the cache allocator; the caller frees it. A
    /// damaged or foreign file is a miss, and the check then checks every body.
    pub fn lookupSummaries(self: *Cache, loaded: *const project.Project) error{OutOfMemory}!?[]u8 {
        return self.lookupSummariesIn(loaded, .entry);
    }

    /// `lookupSummaries` for the slot of one kind of check.
    pub fn lookupSummariesIn(self: *Cache, loaded: *const project.Project, slot: SummarySlot) error{OutOfMemory}!?[]u8 {
        const found = (try self.lookupSlotIn(loaded, slot)) orelse return null;
        defer self.runtime.allocator.free(found.buffer);
        const copy = try self.runtime.allocator.dupe(u8, found.payload);
        return copy;
    }

    /// One summary slot's entry as read: the buffer the file was read into (the caller frees it with the cache's allocator) and the payload inside it.
    pub const SlotBytes = struct { buffer: []u8, payload: []const u8 };

    /// The summary table last remembered in `slot`, without copying it out of the buffer it was read into and without hashing it whole: a
    /// table of sections vouches for its own areas (`semantic_sections.zig`). Null when there is none, or the file is damaged.
    pub fn lookupSlotIn(self: *Cache, loaded: *const project.Project, slot: SummarySlot) error{OutOfMemory}!?SlotBytes {
        const key = self.summariesKeyIn(loaded, slot) orelse return null;
        if (self.readEntry(key, .slot)) |entry| {
            return .{ .buffer = entry.bytes, .payload = entry.payload };
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Damaged => self.statistics.damaged += 1,
            else => {},
        }
        const shared = (try self.lookupSharedSummaries(loaded, slot)) orelse return null;
        return .{ .buffer = shared, .payload = shared };
    }

    /// The table another worktree of this project published, when this work directory holds none. Every stand-in the table offers is
    /// validated against the fresh function (key, dependency context, region digest), so an old or foreign table costs reuse, never
    /// correctness.
    fn lookupSharedSummaries(self: *Cache, loaded: *const project.Project, slot: SummarySlot) error{OutOfMemory}!?[]u8 {
        const store = self.runtime.shared orelse return null;
        const key = self.sharedSummariesKey(loaded, slot) orelse return null;
        if (store.load(self.runtime.allocator, .frontend, key)) |found| {
            return found;
        } else |err| {
            if (err == error.OutOfMemory) return error.OutOfMemory;
            store.reportFailure(err);
            return null;
        }
    }

    /// Publish the table for the other worktrees of this project: it replaces the one before it, whoever wrote that.
    fn publishSummaries(self: *Cache, loaded: *const project.Project, slot: SummarySlot, payload: []const u8) void {
        const store = self.runtime.shared orelse return;
        const key = self.sharedSummariesKey(loaded, slot) orelse return;
        // This slot is replaced on purpose: `replace`, not `save`, which would keep the old table and log this one as a mismatch.
        _ = store.replace(.frontend, key, payload) catch |err| store.reportFailure(err);
    }

    /// The shared slot key of an entry check, for tests that compare projects.
    pub fn sharedSummariesKeyForTest(self: *Cache, loaded: *const project.Project) [32]u8 {
        return self.sharedSummariesKey(loaded, .entry).?;
    }

    /// Slot key of the shared summary table. The work directory's key names the entry (name and project-relative path) under this
    /// compiler identity and contract; the shared one adds the project's identity, the set of its module paths, so that two projects
    /// with the same entry name and path (the 99k and 400k ports are two) never share a slot, and two worktrees of one project do. It
    /// holds no root, no content and no order: an edit changes no module path, and a worktree that adds a module starts a slot of its own.
    /// Only an entry check shares; a library check's slot is named by the path as given.
    fn sharedSummariesKey(self: *Cache, loaded: *const project.Project, slot: SummarySlot) ?[32]u8 {
        if (slot != .entry) return null;
        const local = self.summariesKeyIn(loaded, slot) orelse return null;
        var members: [32]u8 = @splat(0);
        for (loaded.modules.items) |module| {
            var one: [32]u8 = undefined;
            std.crypto.hash.Blake3.hash(module.src.path, &one, .{});
            for (&members, one) |*total, byte| total.* ^= byte;
        }
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        frame(&hash, "shared-check-summaries-v1");
        hash.update(&local);
        hash.update(std.mem.asBytes(&loaded.modules.items.len));
        hash.update(&members);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// Key of the shared pack of this project's semantic entries (`semantic_pack.zig`): the summary table's slot, so the pack belongs to the
    /// same compiler identity, contract and set of module paths, and no other. Null for a project that has no shared slot.
    pub fn sharedPackKey(self: *Cache, loaded: *const project.Project) ?[32]u8 {
        const slot = self.sharedSummariesKey(loaded, .entry) orelse return null;
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        frame(&hash, "shared-semantic-pack-v1");
        hash.update(&slot);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// Remember one successful check's summaries for this project's entry,
    /// replacing the previous ones: there is one slot per entry, not one per edit.
    pub fn rememberSummaries(self: *Cache, loaded: *const project.Project, payload: []const u8) error{OutOfMemory}!void {
        return self.rememberSummariesIn(loaded, .entry, payload);
    }

    /// `rememberSummaries` for the slot of one kind of check.
    pub fn rememberSummariesIn(self: *Cache, loaded: *const project.Project, slot: SummarySlot, payload: []const u8) error{OutOfMemory}!void {
        const key = self.summariesKeyIn(loaded, slot) orelse return;
        _ = self.writeEntry(key, payload, .slot) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.bypassed += 1;
                return;
            },
        };
        self.publishSummaries(loaded, slot, payload);
    }

    /// Leave a small mark in a summary slot without asking the end of the run to scan and trim
    /// the directory. A table is budgeted, so storing one does; a mark adds nothing worth
    /// budgeting, and the scan costs a `stat` per entry of a directory that holds thousands.
    pub fn markSummariesIn(self: *Cache, loaded: *const project.Project, slot: SummarySlot, payload: []const u8) error{OutOfMemory}!void {
        const pending = self.runtime.stored;
        try self.rememberSummariesIn(loaded, slot, payload);
        self.runtime.stored = pending;
    }

    /// Slot key of an entry's check summaries: the entry module's name and path
    /// under this compiler identity and contract.
    pub fn summariesKey(self: *Cache, loaded: *const project.Project) ?[32]u8 {
        return self.summariesKeyIn(loaded, .entry);
    }

    /// `summariesKey` for the slot of one kind of check.
    pub fn summariesKeyIn(self: *Cache, loaded: *const project.Project, slot: SummarySlot) ?[32]u8 {
        if (loaded.modules.items.len == 0) return null;
        const entry = loaded.modules.items[0];
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(format_version);
        hash.update(switch (slot) {
            .entry => "check-summaries",
            .library => "check-summaries-library",
        });
        if (slot == .library) frame(&hash, slot.library);
        frame(&hash, self.identity);
        frame(&hash, self.runtime.summary_policy);
        const contract = self.contractHex();
        hash.update(&contract);
        frame(&hash, entry.name);
        frame(&hash, entry.src.path);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// Content key of one parsed-module entry; exposed so tests can damage it.
    pub fn syntaxKey(self: *Cache, src: source.Source, body_start: usize) [32]u8 {
        return syntaxKeyOf(self, src, source_digest.of(src.bytes), body_start);
    }

    /// The key of an entry for a source whose bytes have the digest `digest`.
    pub fn syntaxKeyOf(self: *Cache, src: source.Source, digest: [32]u8, body_start: usize) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(format_version);
        hash.update("syntax");
        frame(&hash, self.identity);
        const contract = self.contractHex();
        hash.update(&contract);
        frame(&hash, src.path);
        hash.update(&digest);
        hash.update(std.mem.asBytes(&body_start));
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    // StoredSyntax owns spans and literals only. Paths are deliberately absent;
    // parser authority is excluded before using this separate transport key.
    fn sharedSyntaxKey(self: *Cache, digest: [32]u8, body_start: usize) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        frame(&hash, "portable-parsed-syntax-v1");
        frame(&hash, format_version);
        frame(&hash, self.identity);
        const contract = self.contractHex();
        hash.update(&contract);
        hash.update(&digest);
        var start: [8]u8 = undefined;
        std.mem.writeInt(u64, &start, body_start, .little);
        hash.update(&start);
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    fn verdictKey(self: *Cache, digest: [32]u8, format: diagnostic_output.Format) [32]u8 {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(format_version);
        hash.update("verdict");
        frame(&hash, self.identity);
        const contract = self.contractHex();
        hash.update(&contract);
        if (self.runtime.policy_identity) |identity| {
            hash.update("policy");
            frame(&hash, identity);
        } else {
            hash.update("no-policy");
        }
        hash.update(&digest);
        hash.update(&.{@backingInt(format)});
        var out: [32]u8 = undefined;
        hash.final(&out);
        return out;
    }

    /// Content key of one successful-verdict entry; exposed so tests can damage it.
    pub fn verdictKeyFor(self: *Cache, loaded: *const project.Project, format: diagnostic_output.Format) [32]u8 {
        return verdictKey(self, digestModules(loaded.modules.items), format);
    }

    /// Absolute path of the entry stored under `key`; the caller frees it.
    pub fn entryPath(self: *Cache, key: [32]u8) error{OutOfMemory}![]const u8 {
        const directory = try self.namespace();
        defer self.runtime.allocator.free(directory);
        return std.fmt.allocPrint(self.runtime.allocator, "{s}/{s}", .{ directory, std.fmt.bytesToHex(key, .lower) }) catch error.OutOfMemory;
    }

    /// Read `key`, rejecting anything whose stored key or payload checksum
    /// disagrees. The payload belongs to the cache allocator; the caller frees it.
    pub fn read(self: *Cache, key: [32]u8) error{ OutOfMemory, NotFound, Damaged, ReadFailed }![]u8 {
        const entry = try self.readEntry(key, .whole);
        defer self.runtime.allocator.free(entry.bytes);
        return self.runtime.allocator.dupe(u8, entry.payload) catch return error.OutOfMemory;
    }

    /// One validated entry file: its whole buffer, which the caller frees with
    /// the cache allocator, and the payload inside it.
    const ReadEntry = struct { bytes: []u8, payload: []const u8 };

    /// What vouches for an entry's payload: its checksum over every byte, or (a summary slot, whose sections each carry their own) the cheap
    /// one `slotChecksum` takes, with the frame's key and lengths.
    const Vouch = enum { whole, slot };

    fn readEntry(self: *Cache, key: [32]u8, vouch: Vouch) error{ OutOfMemory, NotFound, Damaged, ReadFailed }!ReadEntry {
        const directory = self.namespace() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer self.runtime.allocator.free(directory);
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ directory, &std.fmt.bytesToHex(key, .lower) }) catch return error.ReadFailed;
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.runtime.io, path, self.runtime.allocator, .limited(self.max_bytes)) catch |err| switch (err) {
            error.FileNotFound => return error.NotFound,
            error.StreamTooLong => return error.Damaged,
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.ReadFailed,
        };
        var kept = false;
        defer if (!kept) self.runtime.allocator.free(bytes);
        if (bytes.len < headerSize) return error.Damaged;
        var reader = codec.Reader.init(self.runtime.allocator, bytes);
        const magic = reader.integer(u32) catch return error.Damaged;
        if (magic != entry_magic) return error.Damaged;
        const stored_key = reader.integer([32]u8) catch return error.Damaged;
        if (!std.mem.eql(u8, &stored_key, &key)) return error.Damaged;
        const payload_len = reader.integer(u64) catch return error.Damaged;
        const payload = reader.slice(std.math.cast(usize, payload_len) orelse return error.Damaged) catch return error.Damaged;
        const checksum = reader.integer(u64) catch return error.Damaged;
        if (!reader.done()) return error.Damaged;
        if ((if (vouch == .whole) codec.checksum(payload) else slotChecksum(payload)) != checksum) return error.Damaged;
        kept = true;
        self.statistics.used_bytes +|= bytes.len;
        // Eviction goes oldest first, so a use renews the entry: the order is
        // by last use, and the entries this run needs are the last to go.
        // A read-only cache still serves hits; it only ages in store order.
        std.Io.Dir.cwd().setTimestampsNow(self.runtime.io, path, .{}) catch |err| switch (err) {
            error.ReadOnlyFileSystem => {},
            else => {},
        };
        return .{ .bytes = bytes, .payload = payload };
    }

    /// Stage `payload` under `key`; returns false when the entry is too large to
    /// retain. A damaged or concurrent store is not fatal: the caller keeps the
    /// freshly computed value either way.
    pub fn write(self: *Cache, key: [32]u8, payload: []const u8) error{ OutOfMemory, WriteFailed }!bool {
        return self.writeEntry(key, payload, .whole);
    }

    fn writeEntry(self: *Cache, key: [32]u8, payload: []const u8, vouch: Vouch) error{ OutOfMemory, WriteFailed }!bool {
        if (payload.len > self.max_bytes) return false;
        const directory = self.namespace() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer self.runtime.allocator.free(directory);
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ directory, &std.fmt.bytesToHex(key, .lower) }) catch return error.WriteFailed;
        var staging_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var nonce: [8]u8 = undefined;
        std.Io.random(self.runtime.io, &nonce);
        const staging = std.fmt.bufPrint(&staging_buffer, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return error.WriteFailed;
        var writer = codec.Writer.init(self.runtime.allocator);
        defer writer.deinit();
        encodeHeader(&writer, key, payload, vouch) catch return error.WriteFailed;
        // The directory is made only when the file cannot be written without it (a failing `mkdirat` per entry otherwise).
        std.Io.Dir.cwd().writeFile(self.runtime.io, .{ .sub_path = staging, .data = writer.bytes.items }) catch |err| {
            if (err != error.FileNotFound) return error.WriteFailed;
            std.Io.Dir.cwd().createDirPath(self.runtime.io, directory) catch return error.WriteFailed;
            std.Io.Dir.cwd().writeFile(self.runtime.io, .{ .sub_path = staging, .data = writer.bytes.items }) catch return error.WriteFailed;
        };
        std.Io.Dir.rename(.cwd(), staging, .cwd(), path, self.runtime.io) catch {
            std.Io.Dir.cwd().deleteFile(self.runtime.io, staging) catch |err| switch (err) {
                error.FileNotFound => {},
                else => {},
            };
            return error.WriteFailed;
        };
        self.statistics.used_bytes +|= writer.bytes.items.len;
        self.runtime.stored = true;
        return true;
    }

    /// Bound the directory: drop the least recently used entries (oldest
    /// mtime; a read renews it) once it exceeds `retention`. Concurrent trims
    /// may both remove entries; a lost race only costs a future miss, never a
    /// false hit.
    fn trim(self: *Cache) error{ OutOfMemory, WriteFailed }!void {
        const directory = self.namespace() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer self.runtime.allocator.free(directory);
        var dir = std.Io.Dir.cwd().openDir(self.runtime.io, directory, .{ .iterate = true }) catch return;
        defer dir.close(self.runtime.io);
        var total: usize = 0;
        var entries: std.ArrayList(Entry) = .empty;
        defer {
            for (entries.items) |entry| self.runtime.allocator.free(entry.name);
            entries.deinit(self.runtime.allocator);
        }
        var iterator = dir.iterate();
        while (iterator.next(self.runtime.io) catch return error.WriteFailed) |item| {
            if (item.kind != .file or std.mem.endsWith(u8, item.name, ".tmp")) continue;
            const stat = dir.statFile(self.runtime.io, item.name, .{}) catch continue;
            const owned = self.runtime.allocator.dupe(u8, item.name) catch return error.OutOfMemory;
            entries.append(self.runtime.allocator, .{ .name = owned, .size = @intCast(stat.size), .mtime = stat.mtime.nanoseconds }) catch {
                self.runtime.allocator.free(owned);
                return error.OutOfMemory;
            };
            total += @intCast(stat.size);
        }
        self.statistics.retained_bytes = total;
        const budget = self.retention();
        if (total <= budget) return;
        std.mem.sort(Entry, entries.items, {}, oldestFirst);
        for (entries.items) |entry| {
            if (total <= budget) break;
            dir.deleteFile(self.runtime.io, entry.name) catch continue;
            total -= entry.size;
            self.statistics.evicted += 1;
        }
        self.statistics.retained_bytes = total;
    }

    const Entry = struct { name: []const u8, size: usize, mtime: i128 };
    fn oldestFirst(_: void, a: Entry, b: Entry) bool {
        return a.mtime < b.mtime;
    }
};

const entry_magic: u32 = 0x4d594643; // "FCYM" little-endian.
/// magic + key + payload length + payload + checksum.
const headerSize = @sizeOf(u32) + 32 + @sizeOf(u64) + @sizeOf(u64);

/// Where the payload starts in an entry file whose first bytes are `bytes`, when the frame names `key`; null for another magic or key.
fn frameStart(bytes: []const u8, key: [32]u8) ?usize {
    const prefix = @sizeOf(u32) + 32 + @sizeOf(u64);
    if (bytes.len < prefix) return null;
    if (std.mem.readInt(u32, bytes[0..4], .little) != entry_magic) return null;
    if (!std.mem.eql(u8, bytes[4..36], &key)) return null;
    return prefix;
}

/// The payload of a whole entry file `bytes` under `key`, by its frame alone: a syntax entry's sections carry the checksums that matter,
/// so the checksum of the whole is not computed here.
fn framedPayload(bytes: []const u8, key: [32]u8) error{Damaged}![]const u8 {
    const start = frameStart(bytes, key) orelse return error.Damaged;
    const payload_len = std.mem.readInt(u64, bytes[36..44], .little);
    const end = std.math.add(u64, start, payload_len) catch return error.Damaged;
    if (end + @sizeOf(u64) != bytes.len) return error.Damaged;
    return bytes[start..@intCast(end)];
}

fn encodeHeader(writer: *codec.Writer, key: [32]u8, payload: []const u8, vouch: Cache.Vouch) std.mem.Allocator.Error!void {
    try writer.bytes.ensureTotalCapacity(writer.allocator, headerSize + payload.len);
    try writer.integer(entry_magic);
    try writer.raw(&key);
    try writer.integer(@as(u64, payload.len));
    try writer.raw(payload);
    try writer.integer(if (vouch == .whole) codec.checksum(payload) else slotChecksum(payload));
}

/// The checksum a summary slot's frame carries: of the payload's length and its first bytes. The payload is a table of sections whose
/// directory and areas each carry a checksum that is verified before the bytes are used, so the frame has only to tell this entry from
/// another and a complete write from a short one; hashing megabytes of it again on every read and write is the cost the sections avoid.
fn slotChecksum(payload: []const u8) u64 {
    return codec.checksum(payload[0..@min(payload.len, 256)]) ^ payload.len;
}

/// Frame one borrowed byte string so adjacent fields cannot alias.
fn frame(hash: *std.crypto.hash.sha2.Sha256, bytes: []const u8) void {
    hash.update(std.mem.asBytes(&bytes.len));
    hash.update(bytes);
}

/// Content digest of every module, in project load order, mixed with its name
/// and source path. Any change to the graph or its bytes changes the verdict key.
fn digestModules(modules: []const project.Module) [32]u8 {
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    hash.update("frontend-cache-modules-v1");
    for (modules) |module| {
        frame(&hash, module.name);
        frame(&hash, module.src.path);
        const digest = if (module.state.digest_pending) source_digest.of(module.src.bytes) else module.digest;
        hash.update(&digest);
    }
    var out: [32]u8 = undefined;
    hash.final(&out);
    return out;
}

fn decodeWarnings(allocator: std.mem.Allocator, payload: []const u8) error{ OutOfMemory, InvalidEncoding }![]const u8 {
    var reader = codec.Reader.init(allocator, payload);
    const length = reader.integer(u64) catch return error.InvalidEncoding;
    const bytes = reader.slice(std.math.cast(usize, length) orelse return error.InvalidEncoding) catch return error.InvalidEncoding;
    if (!reader.done()) return error.InvalidEncoding;
    return allocator.dupe(u8, bytes) catch return error.OutOfMemory;
}

/// Canonical persisted `ast.Program`: the two growable lists become exact-length
/// owned slices. A restored `ArrayList` therefore has `capacity == items.len`
/// and can never append past its allocation or free a longer slice than it owns.
pub const StoredSyntax = struct {
    types: ast.TypeDeclarations,
    nodes: []ast.Node,
    statements: []ast.Statement,
    functions: []const ast.Function,
    lambdas: []const ast.Lambda,
    /// Declaration attributes, including contract clauses and their conditions;
    /// a warm restore that dropped them would build a program without contracts.
    attributes: []const ast.DeclarationAttributes = &.{},
    docstrings: []const ast.DeclarationDoc = &.{},
};

/// The exact bytes the syntax cache stores for `syntax`, owned by `allocator`.
/// The two growable `Program` lists are written as exact-length owned slices,
/// never as `ArrayList` values: a restored list must not claim spare capacity
/// it does not own. Every other field is already a slice. `selka dump-syntax`
/// prints these bytes, so a parser written in Selka is checked against them.
pub fn encodeSyntax(allocator: std.mem.Allocator, syntax: ast.Program) std.mem.Allocator.Error![]u8 {
    var writer = codec.Writer.init(allocator);
    errdefer writer.deinit();
    try writer.write(StoredSyntax, .{
        .types = syntax.types,
        .nodes = syntax.nodes.items,
        .statements = syntax.statements.items,
        .functions = syntax.functions,
        .lambdas = syntax.lambdas,
        .attributes = syntax.attributes,
        .docstrings = syntax.docstrings,
    });
    return writer.bytes.toOwnedSlice(allocator);
}

fn portableSyntax(src: source.Source) bool {
    return !src.trusted_intrinsics and !std.mem.startsWith(u8, src.path, "@stdlib/");
}

fn sharedError(store: *shared_artifacts.Store, err: anyerror) error{ OutOfMemory, InternalError } {
    if (err == error.OutOfMemory) return error.OutOfMemory;
    store.reportFailure(err);
    return error.InternalError;
}
