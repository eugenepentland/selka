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
const ast = @import("ast.zig");
const source = @import("source.zig");
const codec = @import("persist_codec.zig");
const diagnostic_output = @import("diagnostic_output.zig");
const project = @import("project.zig");
const cache_key = @import("cache_key.zig");

/// Bump when the on-disk layout or a stored serializer changes; older files miss.
pub const format_version = "selka-frontend-cache-v7";
/// Default retention floor: entries above this are bypassed, and a run that
/// stored anything trims the directory back to the larger of this and twice
/// the bytes the run itself used (FRONTEND-CACHE-RETAIN-1).
pub const default_max_bytes: usize = 128 * 1024 * 1024;
/// Entry bytes a project may need per byte of its source (FRONTEND-CACHE-ENTRY-1).
pub const entry_bytes_per_source_byte: usize = 8;
/// Default per-project cache directory for one-shot commands.
pub const default_directory = ".selka-cache/frontend";

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
};

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
    /// changed target, runtime ABI, bootstrap language, effects contract, flag set
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
    /// Replace the policy identity the verdict key folds in with an owned copy
    /// of `identity` (null clears it), so the caller's buffer may die
    /// afterwards. On OutOfMemory the previous identity stays in place.
    pub fn setPolicyIdentity(self: *Cache, identity: ?[]const u8) error{OutOfMemory}!void {
        const owned = if (identity) |bytes| try self.runtime.allocator.dupe(u8, bytes) else null;
        if (self.runtime.policy_identity) |previous| self.runtime.allocator.free(previous);
        self.runtime.policy_identity = owned;
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
    pub fn lookupSyntax(self: *Cache, allocator: std.mem.Allocator, src: source.Source, body_start: usize) error{OutOfMemory}!?ast.Program {
        const key = syntaxKey(self, src, body_start);
        // Decoding copies everything it keeps, so the payload is decoded in
        // place in the file buffer rather than copied out of it first.
        const entry = self.readEntry(key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Damaged => {
                self.statistics.syntax.misses += 1;
                self.statistics.damaged += 1;
                return null;
            },
            else => {
                self.statistics.syntax.misses += 1;
                return null;
            },
        };
        defer self.runtime.allocator.free(entry.bytes);
        const program = decodeSyntax(allocator, entry.payload) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.syntax.misses += 1;
                self.statistics.damaged += 1;
                return null;
            },
        };
        self.statistics.syntax.hits += 1;
        return program;
    }

    /// Retain parsed syntax under its exact path/bytes/body-start key.
    pub fn rememberSyntax(self: *Cache, src: source.Source, body_start: usize, syntax: ast.Program) error{OutOfMemory}!void {
        const key = syntaxKey(self, src, body_start);
        var writer = codec.Writer.init(self.runtime.allocator);
        defer writer.deinit();
        // The two growable `Program` lists are stored as exact-length owned
        // slices, never as `ArrayList` values: a restored list must not claim
        // spare capacity it does not own. Every other field is already a slice.
        writer.write(StoredSyntax, .{
            .types = syntax.types,
            .nodes = syntax.nodes.items,
            .statements = syntax.statements.items,
            .functions = syntax.functions,
            .lambdas = syntax.lambdas,
            .attributes = syntax.attributes,
            .docstrings = syntax.docstrings,
        }) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return,
        };
        const stored = self.write(key, writer.bytes.items) catch |err| switch (err) {
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
        const key = self.summariesKey(loaded) orelse return null;
        return self.read(key) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.Damaged => {
                self.statistics.damaged += 1;
                return null;
            },
            else => return null,
        };
    }

    /// Remember one successful check's summaries for this project's entry,
    /// replacing the previous ones: there is one slot per entry, not one per edit.
    pub fn rememberSummaries(self: *Cache, loaded: *const project.Project, payload: []const u8) error{OutOfMemory}!void {
        const key = self.summariesKey(loaded) orelse return;
        _ = self.write(key, payload) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => {
                self.statistics.bypassed += 1;
                return;
            },
        };
    }

    /// Slot key of an entry's check summaries: the entry module's name and path
    /// under this compiler identity and contract.
    pub fn summariesKey(self: *Cache, loaded: *const project.Project) ?[32]u8 {
        if (loaded.modules.items.len == 0) return null;
        const entry = loaded.modules.items[0];
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(format_version);
        hash.update("check-summaries");
        frame(&hash, self.identity);
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
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        hash.update(format_version);
        hash.update("syntax");
        frame(&hash, self.identity);
        const contract = self.contractHex();
        hash.update(&contract);
        frame(&hash, src.path);
        frame(&hash, src.bytes);
        hash.update(std.mem.asBytes(&body_start));
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
        const entry = try self.readEntry(key);
        defer self.runtime.allocator.free(entry.bytes);
        return self.runtime.allocator.dupe(u8, entry.payload) catch return error.OutOfMemory;
    }

    /// One validated entry file: its whole buffer, which the caller frees with
    /// the cache allocator, and the payload inside it.
    const ReadEntry = struct { bytes: []u8, payload: []const u8 };

    fn readEntry(self: *Cache, key: [32]u8) error{ OutOfMemory, NotFound, Damaged, ReadFailed }!ReadEntry {
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
        if (codec.checksum(payload) != checksum) return error.Damaged;
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
        if (payload.len > self.max_bytes) return false;
        const directory = self.namespace() catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
        };
        defer self.runtime.allocator.free(directory);
        std.Io.Dir.cwd().createDirPath(self.runtime.io, directory) catch return error.WriteFailed;
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const path = std.fmt.bufPrint(&path_buffer, "{s}/{s}", .{ directory, &std.fmt.bytesToHex(key, .lower) }) catch return error.WriteFailed;
        var staging_buffer: [std.fs.max_path_bytes]u8 = undefined;
        var nonce: [8]u8 = undefined;
        std.Io.random(self.runtime.io, &nonce);
        const staging = std.fmt.bufPrint(&staging_buffer, "{s}.{s}.tmp", .{ path, std.fmt.bytesToHex(nonce, .lower) }) catch return error.WriteFailed;
        var writer = codec.Writer.init(self.runtime.allocator);
        defer writer.deinit();
        encodeHeader(&writer, key, payload) catch return error.WriteFailed;
        std.Io.Dir.cwd().writeFile(self.runtime.io, .{ .sub_path = staging, .data = writer.bytes.items }) catch return error.WriteFailed;
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

fn encodeHeader(writer: *codec.Writer, key: [32]u8, payload: []const u8) std.mem.Allocator.Error!void {
    try writer.integer(entry_magic);
    try writer.raw(&key);
    try writer.integer(@as(u64, payload.len));
    try writer.raw(payload);
    try writer.integer(codec.checksum(payload));
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
        frame(&hash, module.src.bytes);
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
const StoredSyntax = struct {
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

fn decodeSyntax(allocator: std.mem.Allocator, payload: []const u8) !ast.Program {
    var reader = codec.Reader.init(allocator, payload);
    const stored = try reader.read(StoredSyntax);
    if (!reader.done()) return error.InvalidEncoding;
    return .{
        .types = stored.types,
        .nodes = std.ArrayList(ast.Node).fromOwnedSlice(stored.nodes),
        .statements = std.ArrayList(ast.Statement).fromOwnedSlice(stored.statements),
        .functions = stored.functions,
        .lambdas = stored.lambdas,
        .attributes = stored.attributes,
        .docstrings = stored.docstrings,
    };
}
