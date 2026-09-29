//! Immutable bounded source inventories and isolated guest provider replacements.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const project_config = @import("project_config.zig");
const project = @import("native_test_root").snapshot_project;
const embed = @import("native_test_root").snapshot_embed;
/// Source races and invalid provider contracts discard test results.
pub const Error = fs.Error || std.Io.Dir.OpenError || std.Io.Dir.SelectiveWalker.Error ||
    std.Io.File.StatError || std.Io.File.ReadPositionalError ||
    error{ InvalidTestSnapshot, SourceChanged, InvalidTestProviders, ProviderSignatureChanged };
/// Entry-point body appended to a library entry so it can be checked as a project.
const main_stub = "def main() -> int:\n    return 0\n";
/// Captured bytes are independent of subsequent source edits.
pub const File = struct {
    path: []const u8,
    data: []const u8,
    hash: []const u8,
    /// Length-only refused asset; never replayed as successful embedded contents.
    refused_size: ?u64 = null,
};
/// Captured required-configuration files, their combined policy identity, and
/// the project budgets the same configuration sets (PROJ-SCALE-1): the snapshot
/// is bounded by its `max_total_bytes`, and the resolved identity loads under it.
/// `assets` are the files the captured sources embed (`EMBED-1`), each named by
/// the path it has relative to the snapshot root, which may climb above it.
pub const Support = struct { files: []const File = &.{}, policy_identity: ?[]const u8 = null, budgets: project.Options = .{}, assets: []const File = &.{}, origin: ?AssetRoots = null };
/// Paths and bytes belong to the enclosing native build context.
pub const Snapshot = struct {
    root: []const u8,
    entry: []const u8,
    entry_path: []const u8,
    files: []const File,
    /// Required `mylang.json` and its relative policy file, mirrored so the
    /// materialized entry discovers the same configuration as the live project.
    support: Support = .{},
    identity: []const u8,
    excluded: ?[]const u8 = null,
};
/// Capture the complete bounded .my inventory beneath the test entry directory.
pub fn capture(context: fs.Context, entry: []const u8) Error!Snapshot {
    return captureExcluding(context, entry, null);
}
/// Ignore a configured build-cache subtree in addition to conventional generated directories.
pub fn captureExcluding(context: fs.Context, entry: []const u8, excluded: ?[]const u8) Error!Snapshot {
    var captured = try inventory(context, entry, excluded, true);
    captured.identity = try identity(context.allocator, captured.entry, captured.files, captured.support, null);
    return captured;
}
/// `captureExcluding` with the resolved identity computed through the import
/// memo at `memo_path` (`Imports`), which the capture then brings up to date.
/// The identity is the one a full load computes; only its cost differs.
pub fn captureMemoized(context: fs.Context, entry: []const u8, excluded: ?[]const u8, memo_path: []const u8) Error!Snapshot {
    var captured = try inventory(context, entry, excluded, true);
    var memo = Imports.open(context, memo_path);
    defer memo.deinit();
    defer memo.save(context);
    // A project that embeds files resolves them through a real load, which the memo cannot replay.
    if (captured.support.assets.len == 0) if (try memoIdentity(context.allocator, &memo, captured.entry, captured.files, captured.support.files)) |memoized| {
        captured.identity = memoized;
        return captured;
    };
    captured.identity = try identity(context.allocator, captured.entry, captured.files, captured.support, &memo);
    return captured;
}
/// The bounded `.my` inventory beneath the entry's project root and its
/// configuration, without a resolved identity. `hashed` also fingerprints
/// every file, which identity needs and a byte-for-byte comparison does not.
fn inventory(context: fs.Context, entry: []const u8, excluded: ?[]const u8, hashed: bool) Error!Snapshot {
    const absolute = try context.absolute(entry);
    var root: []const u8 = std.fs.path.dirname(absolute) orelse return error.InvalidTestSnapshot;
    var name: []const u8 = std.fs.path.basename(absolute);
    // A standalone test under a subdirectory resolves imports and its module
    // name from the enclosing project root, so its snapshot captures the whole
    // project and names it `tests.<stem>` rather than dropping the directory.
    if (project_config.testEntryLocation(context.allocator, context.io, absolute) catch return error.InvalidTestSnapshot) |location| {
        root = location.root;
        name = location.relative;
    }
    var support = try captureSupport(context, absolute);
    const byte_limit = support.budgets.max_total_bytes;
    var directory = try std.Io.Dir.cwd().openDir(context.io, root, .{ .iterate = true, .follow_symlinks = false });
    defer directory.close(context.io);
    var walker = try directory.walk(context.allocator);
    defer walker.deinit();
    var files: std.ArrayList(File) = .empty;
    var visited: usize = 0;
    var total: usize = 0;
    while (try walker.next(context.io)) |item| {
        visited += 1;
        if (visited > 50000) return error.InvalidTestSnapshot;
        if (try ignored(context, root, item, excluded)) {
            if (item.kind == .directory) walker.leave(context.io);
            continue;
        }
        if (item.kind == .sym_link) return error.InvalidTestSnapshot;
        if (item.kind == .directory) continue;
        if (!std.mem.endsWith(u8, item.path, ".my")) continue;
        if (item.kind != .file) return error.InvalidTestSnapshot;
        const path = try context.allocator.dupe(u8, item.path);
        const bytes = try read(context, item.dir, item.basename, byte_limit - total);
        total += bytes.len;
        try files.append(context.allocator, .{ .path = path, .data = bytes, .hash = if (hashed) try fileHash(context.allocator, bytes) else "" });
    }
    std.mem.sort(File, files.items, {}, less);
    if (find(files.items, name) == null) return error.InvalidTestSnapshot;
    support.origin = .{ .root = root, .entry = absolute, .name = name };
    support.assets = try captureAssets(context, support.origin.?, files.items, support);
    return .{
        .root = root,
        .entry = name,
        .entry_path = absolute,
        .files = files.items,
        .support = support,
        .identity = "",
        .excluded = excluded,
    };
}

/// Where a snapshot's embedded files are read from: the project root its sources
/// are captured under, and the entry that locates the nearest `mylang.json`.
const AssetRoots = struct { root: []const u8, entry: []const u8, name: []const u8 };

/// EMBED-1: read every file the captured sources' `embed_bytes`/`embed_str` calls
/// name, by the same rules the compiler applies, so a test child compiled from
/// the materialized copy finds them. A call whose file cannot be read is left
/// for the child's own compile to report.
fn captureAssets(context: fs.Context, roots: AssetRoots, files: []const File, support: Support) Error![]const File {
    const config = project_config.discover(context.allocator, context.io, roots.entry) catch null;
    const prepared = try withTestEntry(context, .{ .root = roots.root, .entry = roots.name, .entry_path = roots.entry, .files = files, .support = support, .identity = "" });
    var provider: AssetProvider = .{
        .context = context,
        .roots = .{ .io = context.io, .import_root = roots.root, .root = if (config) |path| std.fs.path.dirname(path) orelse roots.root else roots.root },
        .files = prepared.files,
    };
    var loaded = project.Project.init(context.allocator);
    defer loaded.deinit();
    loaded.load(.{ .context = &provider, .read = AssetProvider.read, .embed = AssetProvider.readEmbed }, try entryModule(context.allocator, roots.name), support.budgets) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {}, // The immutable child reports the located source refusal.
    };
    std.mem.sort(File, provider.assets.items, {}, less);
    return provider.assets.items;
}

/// Capture the loaded closure through the same before-read caps as the compiler.
const AssetProvider = struct {
    context: fs.Context,
    roots: embed.Roots,
    files: []const File,
    assets: std.ArrayList(File) = .empty,

    fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *AssetProvider = @ptrCast(@alignCast(raw.?));
        var memory: MemoryProvider = .{ .files = self.files };
        return MemoryProvider.read(&memory, allocator, path, limit);
    }
    fn readEmbed(raw: ?*anyopaque, _: std.mem.Allocator, module_path: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!embed.Read {
        const self: *AssetProvider = @ptrCast(@alignCast(raw.?));
        const a = self.context.allocator;
        if (embed.spelledStatus(path)) |status| return .{ .status = status };
        const relative = try embed.relativeTarget(a, std.fs.path.dirname(module_path) orelse "", path);
        if (find(self.assets.items, relative)) |index| {
            const file = self.assets.items[index];
            if (file.refused_size != null or file.data.len > limit) return .{ .status = .too_large };
            return .{ .status = .ok, .contents = file.data };
        }
        const outcome = try embed.readLimited(a, self.roots, module_path, path, limit);
        if (outcome.status == .ok) {
            try self.assets.append(a, .{ .path = relative, .data = outcome.contents, .hash = try fileHash(a, outcome.contents) });
        } else if (outcome.status == .too_large) {
            try self.assets.append(a, .{ .path = relative, .data = "", .hash = try std.fmt.allocPrint(a, "refused:{d}", .{limit}), .refused_size = @as(u64, limit) + 1 });
        }
        return outcome;
    }
};

/// Capture the winning `mylang.json` and, when it names a relative policy, the
/// resolved policy bytes. A malformed configuration is still copied verbatim so
/// the shared frontend gate reports the precise error; the policy identity is
/// only published for a configuration that loads.
fn captureSupport(context: fs.Context, entry_absolute: []const u8) Error!Support {
    const config_path = project_config.discover(context.allocator, context.io, entry_absolute) catch return error.InvalidTestSnapshot;
    const absolute_config = config_path orelse return .{ .files = &.{} };
    const config_bytes = readAbsolute(context, absolute_config, project_config.max_config_bytes) catch return error.InvalidTestSnapshot;
    var support: std.ArrayList(File) = .empty;
    try support.append(context.allocator, .{
        .path = try strippedPath(context.allocator, absolute_config),
        .data = config_bytes,
        .hash = try fs.hash(context.allocator, config_bytes),
    });
    var failure: project_config.Failure = .{};
    var config = project_config.load(context.allocator, context.io, absolute_config, &failure) catch
        return .{ .files = try support.toOwnedSlice(context.allocator) };
    defer config.deinit();
    var budgets: project.Options = .{};
    const configured = config.document.budgets;
    if (configured.max_modules) |value| budgets.max_modules = value;
    if (configured.max_imports) |value| budgets.max_imports = value;
    if (configured.max_file_bytes) |value| budgets.max_file_bytes = value;
    if (configured.max_total_bytes) |value| budgets.max_total_bytes = value;
    var policy_identity: ?[]const u8 = null;
    if (config.policy) |policy| {
        if (!policy.absolute) {
            // Re-read the exact bytes into this context rather than borrowing the
            // parsed configuration's storage, whose arena lifetime ends here.
            const policy_bytes = try readAbsolute(context, policy.path, project_config.max_config_bytes);
            try support.append(context.allocator, .{
                .path = try strippedPath(context.allocator, policy.path),
                .data = policy_bytes,
                .hash = try fs.hash(context.allocator, policy_bytes),
            });
        }
        var identity_buffer: [64]u8 = undefined;
        if (config.cacheIdentity(&identity_buffer)) policy_identity = try context.allocator.dupe(u8, &identity_buffer);
    }
    return .{ .files = try support.toOwnedSlice(context.allocator), .policy_identity = policy_identity, .budgets = budgets };
}

fn readAbsolute(context: fs.Context, path: []const u8, limit: usize) Error![]const u8 {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(context.io, path, context.allocator, .limited(limit + 1));
    if (bytes.len > limit) return error.InvalidTestSnapshot;
    return bytes;
}

/// Strip a leading filesystem root so the path can be mirrored beneath a temp root.
fn strippedPath(allocator: std.mem.Allocator, path: []const u8) Error![]const u8 {
    return allocator.dupe(u8, std.mem.trimStart(u8, path, "/"));
}

fn ignored(context: fs.Context, root: []const u8, item: std.Io.Dir.Walker.Entry, excluded: ?[]const u8) Error!bool {
    const names = [_][]const u8{ ".mylang-cache", ".zig-cache", "zig-out", ".git" };
    if (item.kind == .directory or item.kind == .sym_link) {
        for (names) |name| if (std.mem.eql(u8, name, item.basename)) return true;
    }
    if (excluded) |path| {
        const candidate = try std.fs.path.join(context.allocator, &.{ root, item.path });
        if (std.mem.eql(u8, candidate, path)) return true;
    }
    return false;
}
fn less(_: void, left: File, right: File) bool {
    return std.mem.lessThan(u8, left.path, right.path);
}
fn find(files: []const File, name: []const u8) ?usize {
    for (files, 0..) |file, i| if (std.mem.eql(u8, file.path, name)) return i;
    return null;
}
fn read(context: fs.Context, directory: std.Io.Dir, path: []const u8, limit: usize) Error![]const u8 {
    const file = try directory.openFile(context.io, path, .{ .follow_symlinks = false, .allow_directory = false });
    defer file.close(context.io);
    const stat = try file.stat(context.io);
    if (stat.kind != .file or stat.size > limit) return error.InvalidTestSnapshot;
    const buffer = try context.allocator.alloc(u8, @intCast(stat.size + 1));
    const count = try file.readPositionalAll(context.io, buffer, 0);
    if (count != stat.size) return error.SourceChanged;
    return buffer[0..count];
}
/// Hash the compiler-resolved import closure while retaining the broad source
/// inventory separately for immutable materialization and provider fixtures.
/// A `memo` learns the standard modules the load passed through.
fn identity(allocator: std.mem.Allocator, entry: []const u8, files: []const File, configuration: Support, memo: ?*Imports) Error![]const u8 {
    const support = configuration.files;
    var loaded = project.Project.init(allocator);
    defer loaded.deinit();
    var provider: MemoryProvider = .{ .files = files, .assets = configuration.assets };
    const module_name = try entryModule(allocator, entry);
    loaded.load(provider.provider(), module_name, configuration.budgets) catch return broadIdentity(allocator, entry, files, configuration);
    if (memo) |learning| try rememberStandard(learning, &loaded);
    var pairs: std.ArrayList([2][]const u8) = .empty;
    for (loaded.modules.items) |module| {
        const path = project.modulePath(allocator, module.name) catch |err| switch (err) {
            error.InvalidModuleName => return error.InvalidTestSnapshot,
            error.OutOfMemory => return error.OutOfMemory,
        };
        const index = find(files, path) orelse continue;
        try pairs.append(allocator, .{ files[index].path, files[index].hash });
        // EMBED-1: each file the module embeds, or why it could not be read.
        for (module.src.embeds) |embedded| {
            const name = try std.fmt.allocPrint(allocator, "embed:{s}:{s}", .{ module.src.path, embedded.path });
            const value = if (embedded.status == .ok) try allocator.dupe(u8, &std.fmt.bytesToHex(embedded.digest, .lower)) else @tagName(embedded.status);
            try pairs.append(allocator, .{ name, value });
        }
    }
    return resolvedIdentity(allocator, entry, pairs.items, support);
}
/// The `resolved-source-v2` digest over the resolved files' (path, hash)
/// pairs and the configuration files.
fn resolvedIdentity(allocator: std.mem.Allocator, entry: []const u8, resolved: []const [2][]const u8, support: []const File) Error![]const u8 {
    const pairs = try allocator.alloc([2][]const u8, resolved.len + support.len);
    @memcpy(pairs[0..resolved.len], resolved);
    for (support, pairs[resolved.len..]) |file, *pair| pair.* = .{ file.path, file.hash };
    std.mem.sort([2][]const u8, pairs, {}, pairLess);
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{ .version = "resolved-source-v2", .entry = entry, .files = pairs }, .{});
    return fs.hash(allocator, encoded);
}
/// Import lists of module sources, memoized by content across runs, so the
/// resolved identity of an unchanged project — or of one with a single edited
/// module — never lexes every module again. The project loader lexes a whole
/// file to read its header; at 200,000 lines that was a third of a second on
/// every run and again at its end. An entry is keyed by the BLAKE3 of the
/// module's bytes and whether it is the entry (a standard module by its name),
/// and holds exactly the import names the loader recorded for those bytes, so
/// the walk visits the modules a real load visits. The file is sealed by its
/// digest; a damaged one is simply empty.
pub const Imports = struct {
    allocator: std.mem.Allocator,
    /// An allocator that really frees, for the throwaway one-module load that
    /// reads a header the memo has not seen (NATIVE-TEST-MEMO-MEMORY-1): each
    /// such load holds a 1 MiB header scratch and a project arena, which in the
    /// build context's arena would stay allocated once per module (3.8 GB for
    /// a cold million-line run, which then failed with OutOfMemory).
    scratch: std.mem.Allocator,
    /// The memo file; empty when the run keeps no memo.
    path: []const u8 = "",
    entries: std.StringHashMapUnmanaged([]const []const u8) = .empty,
    /// Keys this run consulted, the entries a rewrite keeps.
    used: std.StringHashMapUnmanaged(void) = .empty,
    /// Whether this run added an entry, so the file needs rewriting.
    added: bool = false,

    /// Read the memo at `path`; a missing, damaged or foreign file yields an empty memo.
    pub fn open(context: fs.Context, path: []const u8) Imports {
        var memo: Imports = .{ .allocator = context.allocator, .scratch = context.parent, .path = path };
        const bytes = context.read(path) catch return memo;
        if (bytes.len < 65 or bytes[64] != '\n' or !std.mem.eql(u8, &sealOf(bytes[65..]), bytes[0..64])) return memo;
        var lines = std.mem.splitScalar(u8, bytes[65..], '\n');
        while (lines.next()) |line| {
            const tab = std.mem.indexOfScalar(u8, line, '\t') orelse continue;
            var names: std.ArrayList([]const u8) = .empty;
            var words = std.mem.tokenizeScalar(u8, line[tab + 1 ..], ' ');
            while (words.next()) |word| names.append(context.allocator, word) catch return memo;
            memo.entries.put(context.allocator, line[0..tab], names.items) catch return memo;
        }
        return memo;
    }
    /// Release the memo's tables; names and keys belong to the caller's allocator.
    pub fn deinit(self: *Imports) void {
        self.entries.deinit(self.allocator);
        self.used.deinit(self.allocator);
    }
    /// Rewrite the memo when this run learned something: the entries it used,
    /// plus the older ones while the file stays within a few projects' worth.
    pub fn save(self: *Imports, context: fs.Context) void {
        if (!self.added or self.path.len == 0) return;
        const keep_all = self.entries.count() <= 4 * self.used.count() + 256;
        var body: std.ArrayList(u8) = .empty;
        var iterator = self.entries.iterator();
        while (iterator.next()) |entry| {
            if (!keep_all and !self.used.contains(entry.key_ptr.*)) continue;
            body.appendSlice(self.allocator, entry.key_ptr.*) catch return;
            body.append(self.allocator, '\t') catch return;
            for (entry.value_ptr.*, 0..) |name, index| {
                if (index != 0) body.append(self.allocator, ' ') catch return;
                body.appendSlice(self.allocator, name) catch return;
            }
            body.append(self.allocator, '\n') catch return;
        }
        const seal = sealOf(body.items);
        const sealed = std.mem.concat(self.allocator, u8, &.{ &seal, "\n", body.items }) catch return;
        context.mkdir(std.fs.path.dirname(self.path) orelse return) catch return;
        // The memo is an acceleration: a refused write only costs the next run a lex.
        context.atomic(self.path, sealed) catch return;
    }
    /// The imports of one module: memoized, or read from its header alone.
    fn importsOf(self: *Imports, key: []const u8, name: []const u8, bytes: []const u8) Error!?[]const []const u8 {
        try self.used.put(self.allocator, key, {});
        if (self.entries.get(key)) |names| return names;
        const names = (try headerImports(self.allocator, self.scratch, name, bytes)) orelse return null;
        try self.entries.put(self.allocator, key, names);
        self.added = true;
        return names;
    }
};
fn sealOf(bytes: []const u8) [64]u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return std.fmt.bytesToHex(digest, .lower);
}
/// The import names the project loader records for one module's bytes, read by
/// loading that module alone: its header is scanned exactly as in a full load,
/// and the load then stops at the first project import it cannot read. Null
/// when the header itself is refused; a full load then decides the identity.
fn headerImports(allocator: std.mem.Allocator, scratch: std.mem.Allocator, name: []const u8, bytes: []const u8) Error!?[]const []const u8 {
    var loaded = project.Project.init(scratch);
    defer loaded.deinit();
    const path = project.modulePath(allocator, name) catch |err| switch (err) {
        error.InvalidModuleName => return null,
        error.OutOfMemory => return error.OutOfMemory,
    };
    var provider: MemoryProvider = .{ .files = &.{.{ .path = path, .data = bytes, .hash = "" }} };
    loaded.load(.{ .context = &provider, .read = MemoryProvider.read }, name, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    };
    if (loaded.modules.items.len == 0) return null;
    if (loaded.problem) |problem| if (!std.mem.eql(u8, problem.code, "E_MODULE_READ")) return null;
    const imports = loaded.modules.items[0].imports;
    const names = try allocator.alloc([]const u8, imports.len);
    for (imports, names) |imported, *copy| copy.* = try allocator.dupe(u8, imported.name);
    return names;
}
/// The resolved identity computed from memoized import lists: the walk a
/// real load makes, reading a header only for a module the memo has not seen.
/// Null when a module cannot be resolved that way; the caller then loads.
fn memoIdentity(allocator: std.mem.Allocator, memo: *Imports, entry: []const u8, files: []const File, support: []const File) Error!?[]const u8 {
    const entry_module = try entryModule(allocator, entry);
    var queue: std.ArrayList([]const u8) = .empty;
    var seen: std.StringHashMapUnmanaged(void) = .empty;
    var pairs: std.ArrayList([2][]const u8) = .empty;
    try queue.append(allocator, entry_module);
    try seen.put(allocator, entry_module, {});
    var cursor: usize = 0;
    while (cursor < queue.items.len) : (cursor += 1) {
        const name = queue.items[cursor];
        const path = project.modulePath(allocator, name) catch |err| switch (err) {
            error.InvalidModuleName => return null,
            error.OutOfMemory => return error.OutOfMemory,
        };
        const found = find(files, path);
        if (found) |index| try pairs.append(allocator, .{ files[index].path, files[index].hash });
        const standard = project.isStandardModule(allocator, name) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return null,
        };
        const imports = if (standard)
            memo.entries.get(try std.fmt.allocPrint(allocator, "std:{s}", .{name})) orelse return null
        else imports: {
            const index = found orelse return null;
            const role = if (cursor == 0) "entry" else "module";
            const key = try std.fmt.allocPrint(allocator, "{s}:{s}", .{ files[index].hash, role });
            break :imports (try memo.importsOf(key, name, files[index].data)) orelse return null;
        };
        if (standard) try memo.used.put(allocator, try std.fmt.allocPrint(allocator, "std:{s}", .{name}), {});
        for (imports) |imported| {
            const visited = try seen.getOrPut(allocator, imported);
            if (!visited.found_existing) try queue.append(allocator, imported);
        }
    }
    const resolved = try resolvedIdentity(allocator, entry, pairs.items, support);
    return resolved;
}
/// Record the standard modules a real load visited, whose import lists the
/// memo walk cannot read from project files.
fn rememberStandard(memo: *Imports, loaded: *const project.Project) Error!void {
    for (loaded.modules.items) |module| {
        if (!std.mem.startsWith(u8, module.src.path, "@stdlib/")) continue;
        const key = try std.fmt.allocPrint(memo.allocator, "std:{s}", .{module.name});
        if (memo.entries.contains(key)) continue;
        const names = try memo.allocator.alloc([]const u8, module.imports.len);
        for (module.imports, names) |imported, *copy| copy.* = try memo.allocator.dupe(u8, imported.name);
        try memo.entries.put(memo.allocator, key, names);
        try memo.used.put(memo.allocator, key, {});
        memo.added = true;
    }
}

/// The absolute paths of the project sources one test entry's import closure
/// reaches, the entry first, resolved from the same project root a child run
/// of that entry uses. Only the module headers are read. A graph that fails to
/// load still reports every source it read before the failure, so a broken
/// import never hides the modules its entry did reach.
pub fn reach(context: fs.Context, entry: []const u8) Error![]const []const u8 {
    const absolute = try context.absolute(entry);
    var root: []const u8 = std.fs.path.dirname(absolute) orelse return error.InvalidTestSnapshot;
    var name: []const u8 = std.fs.path.basename(absolute);
    if (project_config.testEntryLocation(context.allocator, context.io, absolute) catch return error.InvalidTestSnapshot) |location| {
        root = location.root;
        name = location.relative;
    }
    var provider: DiskProvider = .{ .context = context, .root = root };
    var loaded = project.Project.init(context.allocator);
    defer loaded.deinit();
    const module_name = try entryModule(context.allocator, name);
    loaded.load(.{ .context = &provider, .read = DiskProvider.read }, module_name, .{}) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => {},
    };
    if (provider.paths.items.len == 0) try provider.paths.append(context.allocator, absolute);
    return provider.paths.items;
}

/// The live paths of the captured sources a project check loaded, given the
/// check's `{"modules": [{"name": ...}]}` listing. An embedded standard module
/// has no captured source and is left out.
pub fn sourcesOf(context: fs.Context, snapshot: Snapshot, listing: std.json.Value) Error![]const []const u8 {
    var paths: std.ArrayList([]const u8) = .empty;
    for (v.array(v.get(listing, "modules"))) |module| {
        const relative = project.modulePath(context.allocator, v.text(v.get(module, "name"))) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidModuleName => continue,
        };
        if (find(snapshot.files, relative) == null) continue;
        try paths.append(context.allocator, try std.fs.path.join(context.allocator, &.{ snapshot.root, relative }));
    }
    return paths.items;
}

/// Reads project sources beneath one root and records each path it served.
const DiskProvider = struct {
    context: fs.Context,
    root: []const u8,
    paths: std.ArrayList([]const u8) = .empty,
    fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *DiskProvider = @ptrCast(@alignCast(raw.?));
        const absolute = std.fs.path.join(self.context.allocator, &.{ self.root, path }) catch return error.OutOfMemory;
        const bytes = std.Io.Dir.cwd().readFileAlloc(self.context.io, absolute, allocator, .limited(limit + 1)) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.FileNotFound => return error.NotFound,
            error.StreamTooLong => return error.TooLarge,
            else => return error.ReadFailed,
        };
        self.paths.append(self.context.allocator, absolute) catch return error.OutOfMemory;
        return bytes;
    }
};

const MemoryProvider = struct {
    files: []const File,
    assets: []const File = &.{},
    fn provider(self: *MemoryProvider) project.Provider {
        return .{ .context = self, .read = MemoryProvider.read, .embed = readEmbed };
    }
    /// The captured file an embed literal names, found by the path it has relative to the root.
    fn readEmbed(raw: ?*anyopaque, allocator: std.mem.Allocator, module_path: []const u8, path: []const u8, limit: usize) std.mem.Allocator.Error!embed.Read {
        const self: *MemoryProvider = @ptrCast(@alignCast(raw.?));
        if (embed.spelledStatus(path)) |status| return .{ .status = status };
        const relative = try embed.relativeTarget(allocator, std.fs.path.dirname(module_path) orelse "", path);
        defer allocator.free(relative);
        const index = find(self.assets, relative) orelse return .{ .status = .missing };
        if (self.assets[index].refused_size != null) return .{ .status = .too_large };
        if (self.assets[index].data.len > limit) return .{ .status = .too_large };
        return .{ .status = .ok, .contents = try allocator.dupe(u8, self.assets[index].data) };
    }
    fn read(raw: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, limit: usize) project.ReadError![]u8 {
        const self: *MemoryProvider = @ptrCast(@alignCast(raw.?));
        const index = find(self.files, path) orelse return error.NotFound;
        if (self.files[index].data.len > limit) return error.TooLarge;
        return allocator.dupe(u8, self.files[index].data);
    }
};

fn entryModule(allocator: std.mem.Allocator, entry: []const u8) Error![]const u8 {
    if (!std.mem.endsWith(u8, entry, ".my")) return error.InvalidTestSnapshot;
    const name = try allocator.dupe(u8, entry[0 .. entry.len - 3]);
    for (name) |*byte| {
        if (byte.* == std.fs.path.sep) byte.* = '.';
    }
    return name;
}

fn broadIdentity(allocator: std.mem.Allocator, entry: []const u8, files: []const File, support: Support) Error![]const u8 {
    const pairs = try allocator.alloc([2][]const u8, files.len + support.files.len + support.assets.len);
    for (files, pairs[0..files.len]) |file, *pair| pair.* = .{ file.path, file.hash };
    for (support.files, pairs[files.len..][0..support.files.len]) |file, *pair| pair.* = .{ file.path, file.hash };
    for (support.assets, pairs[files.len + support.files.len ..]) |file, *pair| pair.* = .{ file.path, file.hash };
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{ .version = "broad-source-v1", .entry = entry, .files = pairs }, .{});
    return fs.hash(allocator, encoded);
}

fn pairLess(_: void, left: [2][]const u8, right: [2][]const u8) bool {
    return std.mem.lessThan(u8, left[0], right[0]);
}
/// Reject edits, additions, deletions, or dependency changes since initial capture.
/// A tree whose every captured file and configuration byte is unchanged has
/// the captured identity by construction, so that case costs one re-read and
/// no re-resolution; only a changed tree resolves its import closure again,
/// which keeps an unrelated neighbouring edit from failing the run.
pub fn verify(context: fs.Context, snapshot: Snapshot) Error!void {
    if (sameBytes(snapshot, try inventory(context, snapshot.entry_path, snapshot.excluded, false))) return;
    const current = try captureExcluding(context, snapshot.entry_path, snapshot.excluded);
    if (!std.mem.eql(u8, current.identity, snapshot.identity)) return error.SourceChanged;
}
/// Whether two inventories hold the same entry, paths and bytes.
fn sameBytes(before: Snapshot, after: Snapshot) bool {
    if (!std.mem.eql(u8, before.entry, after.entry)) return false;
    if (before.files.len != after.files.len or before.support.files.len != after.support.files.len) return false;
    for (before.files, after.files) |old, new| {
        if (!std.mem.eql(u8, old.path, new.path) or !std.mem.eql(u8, old.data, new.data)) return false;
    }
    for (before.support.files, after.support.files) |old, new| {
        if (!std.mem.eql(u8, old.path, new.path) or !std.mem.eql(u8, old.data, new.data)) return false;
    }
    if (before.support.assets.len != after.support.assets.len) return false;
    for (before.support.assets, after.support.assets) |old, new| {
        if (old.refused_size != new.refused_size) return false;
        if (!std.mem.eql(u8, old.path, new.path) or !std.mem.eql(u8, old.data, new.data)) return false;
    }
    return true;
}
/// Fingerprint of one captured file's bytes, for the resolved identity.
/// BLAKE3: a large project hashes megabytes of source on every run.
fn fileHash(allocator: std.mem.Allocator, bytes: []const u8) std.mem.Allocator.Error![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(bytes, &digest, .{});
    return allocator.dupe(u8, &std.fmt.bytesToHex(digest, .lower));
}

/// Provider substitutions may introduce imports to any captured neighbor, so
/// require their broad fixture inventory to remain byte-for-byte current.
fn verifyProviderInventory(context: fs.Context, snapshot: Snapshot) Error!void {
    const current = try captureExcluding(context, snapshot.entry_path, snapshot.excluded);
    const before = try broadIdentity(context.allocator, snapshot.entry, snapshot.files, snapshot.support);
    const after = try broadIdentity(context.allocator, current.entry, current.files, current.support);
    if (!std.mem.eql(u8, before, after)) return error.SourceChanged;
}
/// A snapshot root at the same path on every run of one project from one
/// cache: `<scratch>/.pending/snapshot-<key>`, claimed through the scratch
/// owner protocol (an exclusive lock on its `.owner` marker) for the run's
/// lifetime. The compiler's caches are keyed by source path as well as bytes —
/// the check verdict, the emitted-fragment packs — so a snapshot at a fresh
/// random path missed all of them on every run; at a stable path an unchanged
/// project replays its verdict and an edited one re-emits only what changed.
pub const Stable = struct {
    directory: []const u8,
    marker: std.Io.File,
    /// Remove the snapshot tree, then release the claim, so a concurrent sweep
    /// never deletes a tree this run is still reading.
    pub fn release(self: Stable, context: fs.Context) void {
        context.remove(self.directory);
        self.marker.close(context.io);
    }
};
/// Claim the stable snapshot root for `seed` (the cache directory, project
/// root and entry). Null when another live run holds it or the scratch root
/// cannot hold it; the caller then stages at a fresh private path exactly as
/// before. An attempt a concurrent sweep wins is made again. Whatever a killed
/// run left inside is cleared first, keeping only the marker.
pub fn claimStable(context: fs.Context, scratch: []const u8, seed: []const u8) ?Stable {
    return claim(context, scratch, seed, false);
}
/// MODULE-TEST-5: `claimStable`, waiting while another run holds the path:
/// a detached seeder takes the path once the run that started it released it,
/// and a run takes it once a seeder holding it is done.
pub fn claimStableWaiting(context: fs.Context, scratch: []const u8, seed: []const u8) ?Stable {
    return claim(context, scratch, seed, true);
}
/// The file a detached seeder leaves in the stable snapshot it holds, so a
/// run that finds the path held waits for it rather than staging elsewhere
/// (MODULE-TEST-5).
const seeding_name = "seeding";
/// MODULE-TEST-5: mark a claimed stable snapshot as a detached seeder's.
pub fn markSeeding(context: fs.Context, stable: Stable) void {
    const path = std.fs.path.join(context.allocator, &.{ stable.directory, seeding_name }) catch return;
    context.write(path, "") catch return;
}
/// MODULE-TEST-5: whether the stable snapshot of `seed` is marked as a
/// detached seeder's: a run then waits for it (`claimStableWaiting`),
/// since its module records answer only at that path.
pub fn heldBySeeder(context: fs.Context, scratch: []const u8, seed: []const u8) bool {
    const directory = stableDirectory(context.allocator, scratch, seed) catch return false;
    const path = std.fs.path.join(context.allocator, &.{ directory, seeding_name }) catch return false;
    return context.exists(path);
}
/// The stable snapshot directory of `seed` under `scratch`.
fn stableDirectory(allocator: std.mem.Allocator, scratch: []const u8, seed: []const u8) error{OutOfMemory}![]const u8 {
    var digest: [16]u8 = undefined;
    std.crypto.hash.Blake3.hash(seed, &digest, .{});
    const name = try std.fmt.allocPrint(allocator, "snapshot-{s}", .{std.fmt.bytesToHex(digest, .lower)});
    return std.fs.path.join(allocator, &.{ scratch, ".pending", name });
}
/// How one attempt at the stable path ended: claimed, held by a live run
/// (or not claimable at all), or lost to a sweep that removed the tree
/// under it, or to the release of the run that held it.
const Attempt = union(enum) { claimed: Stable, held, lost };
fn claim(context: fs.Context, scratch: []const u8, seed: []const u8, wait: bool) ?Stable {
    // NATIVE-TEST-STABLE-1: a sweep (`fs.Context.reclaim`, run by any
    // process staging owned scratch) can take a fresh marker between its
    // creation and this run's lock and delete the tree; a run that released
    // the path unlinks the marker a waiting claim then holds. Either is a lost
    // race, not a live holder, so the claim is made again.
    for (0..3) |_| switch (attempt(context, scratch, seed, wait)) {
        .claimed => |stable| return stable,
        .held => return null,
        .lost => {},
    };
    return null;
}
fn attempt(context: fs.Context, scratch: []const u8, seed: []const u8, wait: bool) Attempt {
    const directory = stableDirectory(context.allocator, scratch, seed) catch return .held;
    const marker_path = std.fs.path.join(context.allocator, &.{ directory, fs.owner_name }) catch return .held;
    std.Io.Dir.cwd().createDirPath(context.io, directory) catch return .lost;
    const marker = std.Io.Dir.cwd().createFile(context.io, marker_path, .{ .truncate = false, .permissions = .fromMode(0o600) }) catch return .lost;
    const locked = if (wait) lockWaiting(context, marker) else marker.tryLock(context.io, .exclusive) catch false;
    if (locked and stillLinked(context, marker, marker_path)) {
        if (clearExcept(context, directory, fs.owner_name)) return .{ .claimed = .{ .directory = directory, .marker = marker } };
        marker.close(context.io);
        return .held;
    }
    marker.close(context.io);
    return if (locked) .lost else .held;
}
fn lockWaiting(context: fs.Context, marker: std.Io.File) bool {
    marker.lock(context.io, .exclusive) catch return false;
    return true;
}
/// Whether the locked marker is still the file at its path: a sweep that won
/// the marker and deleted the tree before this lock leaves it unlinked.
fn stillLinked(context: fs.Context, marker: std.Io.File, path: []const u8) bool {
    const opened = marker.stat(context.io) catch return false;
    const current = std.Io.Dir.cwd().statFile(context.io, path, .{}) catch return false;
    return opened.inode == current.inode;
}
/// Delete every entry of `directory` except `keep`; false when one could not be.
fn clearExcept(context: fs.Context, directory: []const u8, keep: []const u8) bool {
    var opened = std.Io.Dir.cwd().openDir(context.io, directory, .{ .iterate = true, .follow_symlinks = false }) catch return false;
    defer opened.close(context.io);
    var names: std.ArrayList([]const u8) = .empty;
    var iterator = opened.iterate();
    while (iterator.next(context.io) catch return false) |entry| {
        if (std.mem.eql(u8, entry.name, keep)) continue;
        names.append(context.allocator, context.allocator.dupe(u8, entry.name) catch return false) catch return false;
    }
    for (names.items) |entry| opened.deleteTree(context.io, entry) catch return false;
    return true;
}
/// Materialize captured bytes for checking and code generation without rereading
/// live sources. Absolute paths are mirrored beneath the temp root so a
/// configuration discovered above the entry directory is still found by the
/// materialized entry's walk-up discovery.
pub fn materialize(context: fs.Context, snapshot: Snapshot, directory: []const u8) Error!Snapshot {
    const temp_root = try context.absolute(directory);
    const root = try mirrorPath(context.allocator, temp_root, snapshot.root);
    for (snapshot.files) |file| {
        const path = try std.fs.path.join(context.allocator, &.{ root, file.path });
        try context.mkdir(std.fs.path.dirname(path).?);
        try context.write(path, file.data);
    }
    for (snapshot.support.files) |file| {
        const path = try std.fs.path.join(context.allocator, &.{ temp_root, file.path });
        try context.mkdir(std.fs.path.dirname(path).?);
        try context.write(path, file.data);
    }
    try writeAssets(context, snapshot.support.assets, root);
    return .{
        .root = root,
        .entry = snapshot.entry,
        .entry_path = try std.fs.path.join(context.allocator, &.{ root, snapshot.entry }),
        .files = snapshot.files,
        .support = snapshot.support,
        .identity = snapshot.identity,
    };
}

/// Write each embedded file where the materialized sources' relative references
/// find it: its captured path, resolved lexically against the copy's `root`.
fn writeAssets(context: fs.Context, assets: []const File, root: []const u8) Error!void {
    for (assets) |asset| {
        const path = try std.fs.path.resolve(context.allocator, &.{ root, asset.path });
        try context.mkdir(std.fs.path.dirname(path) orelse return error.InvalidTestSnapshot);
        if (asset.refused_size) |size| {
            const file = try std.Io.Dir.cwd().createFile(context.io, path, .{});
            defer file.close(context.io);
            file.setLength(context.io, size) catch return error.InvalidTestSnapshot;
        } else try context.write(path, asset.data);
    }
}

/// Return a snapshot whose entry file is a project module with a `main`, so a
/// library module, a `*_test.my` file or a headerless script can be checked and
/// tested as a project: a stub `main` is appended when there is none, and a
/// `module` header is written in front of the first line when there is none —
/// on that same line, so every diagnostic and trap keeps the line number of the
/// user's file. A headered file with a `main` and every other file are returned
/// unchanged. A patched projection carries the identity of its patched bytes,
/// because that is what the checker and `verify` see; the caller keeps the
/// user's snapshot.
pub fn withTestEntry(context: fs.Context, snapshot: Snapshot) Error!Snapshot {
    const index = find(snapshot.files, snapshot.entry) orelse return error.InvalidTestSnapshot;
    const original = snapshot.files[index].data;
    const has_main = declaresMain(original);
    const has_header = hasModuleHeader(original);
    if (has_main and has_header) return snapshot;
    var patched: std.ArrayList(u8) = .empty;
    if (!has_header) {
        const stem = snapshot.entry[0 .. snapshot.entry.len - ".my".len];
        try patched.appendSlice(context.allocator, "module ");
        for (stem) |byte| try patched.append(context.allocator, if (byte == std.fs.path.sep) '.' else byte);
        try patched.appendSlice(context.allocator, "; ");
    }
    try patched.appendSlice(context.allocator, original);
    if (!has_main) {
        if (original.len != 0 and original[original.len - 1] != '\n') try patched.append(context.allocator, '\n');
        try patched.appendSlice(context.allocator, main_stub);
    }
    const files = try context.allocator.dupe(File, snapshot.files);
    files[index] = .{ .path = snapshot.files[index].path, .data = patched.items, .hash = try fileHash(context.allocator, patched.items) };
    return .{
        .root = snapshot.root,
        .entry = snapshot.entry,
        .entry_path = snapshot.entry_path,
        .files = files,
        .support = snapshot.support,
        .identity = try identity(context.allocator, snapshot.entry, files, snapshot.support, null),
        .excluded = snapshot.excluded,
    };
}

/// Whether a source declares a top-level `def main`, the entry point a project
/// check requires. Library modules and `*_test.my` files generally do not.
pub fn declaresMain(source: []const u8) bool {
    return project_config.declaresMain(source);
}

/// Whether a source opens with a `module` declaration rather than a bare body.
fn hasModuleHeader(source: []const u8) bool {
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0 or line[0] == '#') continue;
        if (!std.mem.startsWith(u8, line, "module")) return false;
        const after = line["module".len..];
        return after.len != 0 and (after[0] == ' ' or after[0] == '\t');
    }
    return false;
}

/// Place an absolute path under `temp_root` with its root stripped, preserving
/// every ancestor directory so walk-up discovery observes the same hierarchy.
fn mirrorPath(allocator: std.mem.Allocator, temp_root: []const u8, absolute: []const u8) Error![]const u8 {
    const relative = std.mem.trimStart(u8, absolute, "/");
    if (relative.len == 0) return allocator.dupe(u8, temp_root);
    return std.fs.path.join(allocator, &.{ temp_root, relative });
}
/// Replace only existing dependency sources in a private snapshot directory.
pub fn replace(context: fs.Context, snapshot: Snapshot, replacements: std.json.Value, directory: []const u8) Error!Snapshot {
    if (replacements != .object) return error.InvalidTestProviders;
    if (replacements.object.count() == 0 or snapshot.files.len > 128) return error.InvalidTestProviders;
    var entries = replacements.object.iterator();
    while (entries.next()) |entry| {
        if (std.mem.eql(u8, entry.key_ptr.*, snapshot.entry) or find(snapshot.files, entry.key_ptr.*) == null) return error.InvalidTestProviders;
        if (entry.value_ptr.* != .string) return error.InvalidTestProviders;
    }
    try verifyProviderInventory(context, snapshot);
    const files = try context.allocator.dupe(File, snapshot.files);
    var total: usize = 0;
    for (files) |*file| {
        if (replacements.object.get(file.path)) |value| {
            file.data = value.string;
            file.hash = try fileHash(context.allocator, file.data);
        }
        total = std.math.add(usize, total, file.path.len) catch return error.InvalidTestProviders;
        total = std.math.add(usize, total, file.data.len) catch return error.InvalidTestProviders;
        if (total > snapshot.support.budgets.max_total_bytes) return error.InvalidTestProviders;
    }
    var replaced = snapshot;
    replaced.files = files;
    if (snapshot.support.origin) |origin| {
        replaced.support.assets = try captureAssets(context, origin, files, snapshot.support);
    }
    replaced.identity = try identity(context.allocator, replaced.entry, files, replaced.support, null);
    return materialize(context, replaced, directory);
}

/// Confirm the actual files a selected replacement closure embedded, including
/// assets its production closure never needed, before publishing test receipts.
pub fn verifyAssets(context: fs.Context, snapshot: Snapshot) Error!void {
    const origin = snapshot.support.origin orelse return;
    const current = try captureAssets(context, origin, snapshot.files, snapshot.support);
    if (!sameAssets(snapshot.support.assets, current)) return error.SourceChanged;
}

fn sameAssets(before: []const File, after: []const File) bool {
    if (before.len != after.len) return false;
    for (before, after) |old, new| {
        if (old.refused_size != new.refused_size) return false;
        if (!std.mem.eql(u8, old.path, new.path) or !std.mem.eql(u8, old.data, new.data)) return false;
    }
    return true;
}

/// Require provider snapshots to preserve exported types and the selected test ABI.
pub fn compatible(original: std.json.Value, replacement: std.json.Value, name: []const u8) Error!void {
    if (!equivalent(v.get(original, "types"), v.get(replacement, "types"))) return error.ProviderSignatureChanged;
    const before = function(original, name) orelse return error.ProviderSignatureChanged;
    const after = function(replacement, name) orelse return error.ProviderSignatureChanged;
    if (!equivalent(v.get(before, "parameters"), v.get(after, "parameters"))) return error.ProviderSignatureChanged;
    if (!equivalent(v.get(before, "result"), v.get(after, "result"))) return error.ProviderSignatureChanged;
    if (!equivalent(v.get(before, "return_reference"), v.get(after, "return_reference"))) return error.ProviderSignatureChanged;
}
fn function(schema: std.json.Value, name: []const u8) ?std.json.Value {
    for (v.array(v.get(schema, "functions"))) |item| if (std.mem.eql(u8, v.text(v.get(item, "name")), name)) return item;
    return null;
}
/// Structural typed JSON comparison preserves scalar kinds and ignores object order.
pub fn equivalent(left: std.json.Value, right: std.json.Value) bool {
    if (std.meta.activeTag(left) != std.meta.activeTag(right)) return false;
    return switch (left) {
        .null => true,
        .bool => left.bool == right.bool,
        .integer => left.integer == right.integer,
        .float => left.float == right.float,
        .number_string => std.mem.eql(u8, left.number_string, right.number_string),
        .string => std.mem.eql(u8, left.string, right.string),
        .array => arrays(left.array.items, right.array.items),
        .object => objects(left.object, right.object),
    };
}
fn arrays(left: []const std.json.Value, right: []const std.json.Value) bool {
    if (left.len != right.len) return false;
    for (left, right) |a, b| if (!equivalent(a, b)) return false;
    return true;
}
fn objects(left: std.json.ObjectMap, right: std.json.ObjectMap) bool {
    if (left.count() != right.count()) return false;
    var entries = left.iterator();
    while (entries.next()) |entry| if (!equivalent(entry.value_ptr.*, right.get(entry.key_ptr.*) orelse return false)) return false;
    return true;
}

// spec: NATIVE-TEST-3
test "provider snapshots preserve originals and detect changed dependencies" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "project/main.my" });
    const dependency = try std.fs.path.join(context.allocator, &.{ root, "project/dependency.my" });
    try context.mkdir(std.fs.path.dirname(entry).?);
    try std.testing.expectError(error.InvalidTestSnapshot, capture(context, entry));
    try context.write(entry, "module main\nimport dependency\n");
    try context.write(dependency, "module dependency\n");
    const snapshot = try capture(context, entry);
    const invalid = try std.json.parseFromSlice(std.json.Value, context.allocator, "{\"main.my\":\"replacement\"}", .{});
    const injected = try std.json.parseFromSlice(std.json.Value, context.allocator, "{\"dependency.my\":\"module dependency; // fixture\"}", .{});
    const destination = try std.fs.path.join(context.allocator, &.{ root, "snapshot" });
    try std.testing.expectError(error.InvalidTestProviders, replace(context, snapshot, invalid.value, destination));
    const replaced = try replace(context, snapshot, injected.value, destination);
    try std.testing.expect(!std.mem.eql(u8, snapshot.identity, replaced.identity));
    try std.testing.expectEqualStrings("module dependency\n", try context.read(dependency));
    try verify(context, snapshot);
    try context.write(dependency, "changed");
    const immutable = try materialize(context, snapshot, try std.fs.path.join(context.allocator, &.{ root, "immutable" }));
    const copied_dependency = try std.fs.path.join(context.allocator, &.{ immutable.root, "dependency.my" });
    try std.testing.expectEqualStrings("module dependency\n", try context.read(copied_dependency));
    try verify(context, immutable);
    try std.testing.expectError(error.SourceChanged, verify(context, snapshot));
}

// spec-case: NATIVE-TEST-12
test "resolved snapshot identity ignores unreachable edits and retains transitive configuration and resolution inputs" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    const middle = try std.fs.path.join(context.allocator, &.{ root, "middle.my" });
    const leaf = try std.fs.path.join(context.allocator, &.{ root, "leaf.my" });
    const unrelated = try std.fs.path.join(context.allocator, &.{ root, "unrelated.my" });
    const config = try std.fs.path.join(context.allocator, &.{ root, "mylang.json" });
    try context.write(entry, "module main\nimport middle\nimport math\n");
    try context.write(middle, "module middle\nimport leaf\n");
    try context.write(leaf, "module leaf\n");
    try context.write(unrelated, "module unrelated\n");
    try context.write(config, "{\"version\":1,\"budgets\":{\"max_modules\":20}}");
    const initial = try capture(context, entry);
    try context.write(unrelated, "module unrelated\n# harmless edit\n");
    try verify(context, initial);
    try std.testing.expectEqualStrings(initial.identity, (try capture(context, entry)).identity);
    const providers = try std.json.parseFromSlice(std.json.Value, context.allocator, "{\"middle.my\":\"module middle\\nimport unrelated\\n\"}", .{});
    const provider_root = try std.fs.path.join(context.allocator, &.{ root, "provider" });
    try std.testing.expectError(error.SourceChanged, replace(context, initial, providers.value, provider_root));
    try context.write(leaf, "module leaf\n# transitive edit\n");
    try std.testing.expectError(error.SourceChanged, verify(context, initial));
    try context.write(leaf, "module leaf\n");
    const shadow = try std.fs.path.join(context.allocator, &.{ root, "math.my" });
    try context.write(shadow, "module math\n");
    try std.testing.expectError(error.SourceChanged, verify(context, initial));
    try std.Io.Dir.cwd().deleteFile(context.io, shadow);
    try verify(context, initial);
    try context.write(config, "{\"version\":1,\"budgets\":{\"max_modules\":21}}");
    try std.testing.expectError(error.SourceChanged, verify(context, initial));
}
// spec-case: PROJ-SCALE-1
test "a test snapshot is bounded by the project's configured source budget rather than a fixed size" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    const config = try std.fs.path.join(context.allocator, &.{ root, "mylang.json" });
    try context.write(entry, "module main\nimport big\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "big.my" }), "module big\n# " ++ ("0123456789abcdef" ++ "0123456789abcdef") ++ ("0123456789abcdef" ++ "0123456789abcdef") ++ "\n");
    // With no configuration the snapshot has the default project budget.
    const unconfigured = try capture(context, entry);
    try std.testing.expectEqual((project.Options{}).max_total_bytes, unconfigured.support.budgets.max_total_bytes);
    // A configured budget smaller than the sources refuses the snapshot, and
    // one that holds them admits it and is what the resolved identity loads under.
    try context.write(config, "{\"version\":1,\"budgets\":{\"max_total_bytes\":64}}");
    try std.testing.expectError(error.InvalidTestSnapshot, capture(context, entry));
    try context.write(config, "{\"version\":1,\"budgets\":{\"max_total_bytes\":4096}}");
    const configured = try capture(context, entry);
    try std.testing.expectEqual(@as(usize, 4096), configured.support.budgets.max_total_bytes);
    try std.testing.expectEqual(@as(usize, 2), configured.files.len);
}
test "provider signatures and typed values compare structurally" {
    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator,
        \\{"before":{"types":[],"functions":[{"name":"test_ok","parameters":[],"result":"bool"}]},"after":{"functions":[{"result":"bool","parameters":[],"name":"test_ok"}],"types":[]},"changed":{"types":[],"functions":[{"name":"test_ok","parameters":[],"result":"i64"}]}}
    , .{});
    defer parsed.deinit();
    try compatible(v.get(parsed.value, "before"), v.get(parsed.value, "after"), "test_ok");
    try std.testing.expectError(error.ProviderSignatureChanged, compatible(v.get(parsed.value, "before"), v.get(parsed.value, "changed"), "test_ok"));
    try std.testing.expect(!equivalent(.{ .bool = true }, .{ .integer = 1 }));
}

// spec: NATIVE-TEST-9
test "a library test entry gains a stub main and a program entry is untouched" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const library = try std.fs.path.join(context.allocator, &.{ root, "inventory.my" });
    try context.write(library, "module inventory\npublic def test_value() -> bool effects():\n    return True\n");
    const captured = try capture(context, library);
    const prepared = try withTestEntry(context, captured);
    const index = find(prepared.files, "inventory.my").?;
    try std.testing.expect(std.mem.endsWith(u8, prepared.files[index].data, main_stub));
    try std.testing.expect(!std.mem.eql(u8, captured.identity, prepared.identity));
    var mirror = std.testing.tmpDir(.{});
    defer mirror.cleanup();
    const mirror_root = try mirror.dir.realPathFileAlloc(context.io, ".", context.allocator);
    try verify(context, try materialize(context, prepared, mirror_root));
    const bare = try std.fs.path.join(context.allocator, &.{ root, "bare_test.my" });
    try context.write(bare, "public def test_x() -> bool effects():\n    return True\n");
    const patched_bare = try withTestEntry(context, try capture(context, bare));
    const bare_index = find(patched_bare.files, "bare_test.my").?;
    try std.testing.expect(std.mem.startsWith(u8, patched_bare.files[bare_index].data, "module bare_test; public def test_x"));
    const program = try std.fs.path.join(context.allocator, &.{ root, "app.my" });
    try context.write(program, "module app\ndef main() -> int:\n    return 0\n");
    const app = try capture(context, program);
    const untouched = try withTestEntry(context, app);
    const app_index = find(untouched.files, "app.my").?;
    try std.testing.expectEqualStrings(app.files[app_index].data, untouched.files[app_index].data);
    try std.testing.expect(declaresMain("def main() -> int:\n    return 0\n"));
    try std.testing.expect(!declaresMain("def mainstreet() -> int:\n    return 0\n"));
}

// spec: NATIVE-TEST-HEADERLESS-1
test "a headerless test entry gains its header on the first line, keeping every line number" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const script = try std.fs.path.join(context.allocator, &.{ root, "calc.my" });
    const text = "record Token:\n    kind: int\n\ndef main() -> int:\n    return 0\n\npublic def test_kind() -> bool:\n    return True\n";
    try context.write(script, text);
    const prepared = try withTestEntry(context, try capture(context, script));
    const data = prepared.files[find(prepared.files, "calc.my").?].data;
    try std.testing.expectEqualStrings("module calc; " ++ text, data);
    try std.testing.expectEqual(std.mem.count(u8, text, "\n"), std.mem.count(u8, data, "\n"));
    var mirror = std.testing.tmpDir(.{});
    defer mirror.cleanup();
    const mirror_root = try mirror.dir.realPathFileAlloc(context.io, ".", context.allocator);
    try verify(context, try materialize(context, prepared, mirror_root));
}

test "source snapshots exclude generated sources and configured cache subtrees" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    try context.write(entry, "module main;");
    const before = try capture(context, entry);
    const standard = try std.fs.path.join(context.allocator, &.{ root, ".mylang-cache" });
    try context.mkdir(standard);
    try context.write(try std.fs.path.join(context.allocator, &.{ standard, "generated.my" }), "generated");
    try verify(context, before);
    const custom = try std.fs.path.join(context.allocator, &.{ root, "custom-cache" });
    try context.mkdir(custom);
    try context.write(try std.fs.path.join(context.allocator, &.{ custom, "generated.my" }), "generated");
    const excluded = try captureExcluding(context, entry, custom);
    try std.testing.expectEqualStrings(before.identity, excluded.identity);
    try verify(context, excluded);
}

// spec-case: NATIVE-TEST-9
test "a subdirectory test entry captures its whole project and gains a dotted module header" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const program = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    const dependency = try std.fs.path.join(context.allocator, &.{ root, "sexpr/parser.my" });
    const test_entry = try std.fs.path.join(context.allocator, &.{ root, "tests/parser_test.my" });
    try context.mkdir(std.fs.path.dirname(dependency).?);
    try context.mkdir(std.fs.path.dirname(test_entry).?);
    try context.write(program, "module main\nimport sexpr.parser as sp\ndef main() -> int:\n    return 0\n");
    try context.write(dependency, "module sexpr.parser\npublic def value() -> int:\n    return 42\n");
    try context.write(test_entry, "import sexpr.parser as sp\npublic def test_value() -> bool:\n    return True\n");
    const captured = try capture(context, test_entry);
    try std.testing.expectEqualStrings(root, captured.root);
    try std.testing.expectEqualStrings("tests/parser_test.my", captured.entry);
    try std.testing.expect(find(captured.files, "sexpr/parser.my") != null);
    const prepared = try withTestEntry(context, captured);
    const index = find(prepared.files, "tests/parser_test.my").?;
    try std.testing.expect(std.mem.startsWith(u8, prepared.files[index].data, "module tests.parser_test; import sexpr.parser"));
}

// spec-case: NATIVE-TEST-9
test "testEntryLocation resolves a subdirectory test against its project root" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try temporary.dir.writeFile(io, .{ .sub_path = "main.my", .data = "module main\ndef main() -> int:\n    return 0\n" });
    try temporary.dir.createDir(io, "tests", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "tests/parser_test.my", .data = "public def test_value() -> bool:\n    return True\n" });
    const entry = try std.fs.path.join(std.testing.allocator, &.{ root, "tests/parser_test.my" });
    defer std.testing.allocator.free(entry);
    const location = (try project_config.testEntryLocation(std.testing.allocator, io, entry)).?;
    defer std.testing.allocator.free(location.root);
    defer std.testing.allocator.free(location.relative);
    defer std.testing.allocator.free(location.name);
    try std.testing.expectEqualStrings(root, location.root);
    try std.testing.expectEqualStrings("tests/parser_test.my", location.relative);
    try std.testing.expectEqualStrings("tests.parser_test", location.name);
}

// spec-case: NATIVE-TEST-9
test "testEntryLocation propagates allocation failure" {
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const io = std.testing.io;
    const root = try temporary.dir.realPathFileAlloc(io, ".", std.testing.allocator);
    defer std.testing.allocator.free(root);
    try temporary.dir.writeFile(io, .{ .sub_path = "main.my", .data = "module main\ndef main() -> int:\n    return 0\n" });
    try temporary.dir.createDir(io, "tests", .default_dir);
    try temporary.dir.writeFile(io, .{ .sub_path = "tests/parser_test.my", .data = "public def test_value() -> bool:\n    return True\n" });
    const entry = try std.fs.path.join(std.testing.allocator, &.{ root, "tests/parser_test.my" });
    defer std.testing.allocator.free(entry);
    var failing = std.testing.FailingAllocator.init(std.testing.allocator, .{ .fail_index = 0 });
    try std.testing.expectError(error.OutOfMemory, project_config.testEntryLocation(failing.allocator(), io, entry));
}

/// The full-load identity of `entry`, with the cache subtree excluded.
fn loadedIdentity(context: fs.Context, entry: []const u8, cache: []const u8) ![]const u8 {
    return (try captureExcluding(context, entry, cache)).identity;
}
/// The memoized identity of `entry`, reading and updating `memo`.
fn memoizedIdentity(context: fs.Context, entry: []const u8, cache: []const u8, memo: []const u8) ![]const u8 {
    return (try captureMemoized(context, entry, cache, memo)).identity;
}
// spec: NATIVE-TEST-IDENTITY-1
test "a memoized capture resolves the identity a full load resolves, through edits, new imports and a damaged memo" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    const leaf = try std.fs.path.join(context.allocator, &.{ root, "leaf.my" });
    const extra = try std.fs.path.join(context.allocator, &.{ root, "extra.my" });
    const cache = try std.fs.path.join(context.allocator, &.{ root, "cache" });
    const memo = try std.fs.path.join(context.allocator, &.{ cache, "imports", "memo" });
    try context.write(entry, "module main\nimport middle\nimport math\n");
    try context.write(try std.fs.path.join(context.allocator, &.{ root, "middle.my" }), "module middle\nimport leaf\n");
    try context.write(leaf, "module leaf\n");
    try context.write(extra, "module extra\n");
    const cold = try memoizedIdentity(context, entry, cache, memo);
    try std.testing.expectEqualStrings(try loadedIdentity(context, entry, cache), cold);
    // A warm capture reads every import list from the memo and learns nothing.
    const warm = try captureMemoized(context, entry, cache, memo);
    try std.testing.expectEqualStrings(cold, warm.identity);
    var reopened = Imports.open(context, memo);
    defer reopened.deinit();
    try std.testing.expectEqualStrings(cold, (try memoIdentity(context.allocator, &reopened, warm.entry, warm.files, warm.support.files)) orelse "");
    try std.testing.expect(!reopened.added);
    // An unreachable module is outside the identity until an edit imports it.
    try context.write(extra, "module extra\n# unreachable edit\n");
    try std.testing.expectEqualStrings(cold, try memoizedIdentity(context, entry, cache, memo));
    try context.write(leaf, "module leaf\nimport extra\n");
    const imported = try memoizedIdentity(context, entry, cache, memo);
    try std.testing.expectEqualStrings(try loadedIdentity(context, entry, cache), imported);
    try context.write(extra, "module extra\n# now reachable\n");
    try std.testing.expect(!std.mem.eql(u8, imported, try memoizedIdentity(context, entry, cache, memo)));
    // A damaged memo is ignored rather than trusted.
    try context.write(memo, "not a sealed memo\n");
    try std.testing.expectEqualStrings(try loadedIdentity(context, entry, cache), try memoizedIdentity(context, entry, cache, memo));
}

// spec: NATIVE-TEST-MEMO-MEMORY-1
test "a cold memoized capture gives back each module's header load instead of keeping it per module" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const root = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const entry = try std.fs.path.join(context.allocator, &.{ root, "main.my" });
    const memo = try std.fs.path.join(context.allocator, &.{ root, "cache", "imports", "memo" });
    // A chain of 64 modules, every header unknown to the memo.
    try context.write(entry, "module main\nimport m0\n");
    for (0..64) |index| {
        const path = try std.fmt.allocPrint(context.allocator, "{s}/m{d}.my", .{ root, index });
        const text = if (index == 63) "module m63\n" else try std.fmt.allocPrint(context.allocator, "module m{d}\nimport m{d}\n", .{ index, index + 1 });
        try context.write(path, text);
    }
    const before = context.arena.queryCapacity();
    const captured = try captureMemoized(context, entry, null, memo);
    try std.testing.expectEqual(@as(usize, 65), captured.files.len);
    // Each header load held a 1 MiB scratch and its own project arena; they go
    // back to the parent allocator, so the build context grows by kilobytes
    // per module rather than by a mebibyte.
    try std.testing.expect(context.arena.queryCapacity() - before < 16 * 1024 * 1024);
}

// spec: NATIVE-TEST-STABLE-1
test "the stable snapshot root is one path per seed, held by one run at a time and cleared of a killed run's files" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const scratch = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const first = claimStable(context, scratch, "seed-a") orelse return error.TestUnexpectedResult;
    // A live claim keeps a second run of the same project on a private path.
    try std.testing.expect(claimStable(context, scratch, "seed-a") == null);
    const other = claimStable(context, scratch, "seed-b") orelse return error.TestUnexpectedResult;
    try std.testing.expect(!std.mem.eql(u8, first.directory, other.directory));
    other.release(context);
    const directory = first.directory;
    first.release(context);
    try std.testing.expect(!context.exists(directory));
    // What a killed run leaves (an unlocked marker and its files) is cleared
    // by the next claim, which gets the very same path.
    const stale = try std.fs.path.join(context.allocator, &.{ directory, "stale.my" });
    try context.write(try std.fs.path.join(context.allocator, &.{ try makeDirectory(context, directory), fs.owner_name }), "");
    try context.write(stale, "module stale\n");
    const again = claimStable(context, scratch, "seed-a") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(directory, again.directory);
    try std.testing.expect(!context.exists(stale));
    again.release(context);
    // The last release leaves the scratch root as it found it.
    try std.testing.expect(!context.exists(try std.fs.path.join(context.allocator, &.{ scratch, ".pending" })));
}
// spec-case: MODULE-TEST-5
test "a stable snapshot a seeder holds is marked as its, and a waiting claim takes the path once it is released" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary_dir = std.testing.tmpDir(.{});
    defer temporary_dir.cleanup();
    const scratch = try temporary_dir.dir.realPathFileAlloc(context.io, ".", context.allocator);
    const seeder = claimStable(context, scratch, "seed-a") orelse return error.TestUnexpectedResult;
    try std.testing.expect(!heldBySeeder(context, scratch, "seed-a"));
    markSeeding(context, seeder);
    try std.testing.expect(heldBySeeder(context, scratch, "seed-a"));
    try std.testing.expect(!heldBySeeder(context, scratch, "seed-b"));
    const directory = seeder.directory;
    seeder.release(context);
    try std.testing.expect(!heldBySeeder(context, scratch, "seed-a"));
    // The next claim, waiting or not, gets the very same path, unmarked.
    const next = claimStableWaiting(context, scratch, "seed-a") orelse return error.TestUnexpectedResult;
    try std.testing.expectEqualStrings(directory, next.directory);
    try std.testing.expect(!heldBySeeder(context, scratch, "seed-a"));
    next.release(context);
}
/// Create `path` and return it.
fn makeDirectory(context: fs.Context, path: []const u8) ![]const u8 {
    try context.mkdir(path);
    return path;
}

// spec-case: EMBED-PROJECT-BUDGET-1
test "snapshot embeds dedup before reading and refused assets remain length-only" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = context.allocator;
    const root = try temporary.dir.realPathFileAlloc(context.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const config = try std.fs.path.join(a, &.{ root, "mylang.json" });
    const text = "module main\n\nconst A: bytes = embed_bytes(\"data.bin\")\nconst B: bytes = embed_bytes(\"data.bin\")\n\ndef main() -> int:\n    return 0\n";
    try context.write(entry, text);
    try context.write(try std.fs.path.join(a, &.{ root, "data.bin" }), "abcd");
    try context.write(config, try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{text.len + 4}));
    const exact = try capture(context, entry);
    try std.testing.expectEqual(@as(usize, 1), exact.support.assets.len);
    try std.testing.expectEqualStrings("abcd", exact.support.assets[0].data);
    try std.testing.expect(exact.support.assets[0].refused_size == null);
    try context.write(config, try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{text.len + 3}));
    const refused = try capture(context, entry);
    try std.testing.expectEqual(@as(usize, 1), refused.support.assets.len);
    try std.testing.expectEqual(@as(?u64, 4), refused.support.assets[0].refused_size);
    try std.testing.expectEqual(@as(usize, 0), refused.support.assets[0].data.len);
    const mirror = try materialize(context, refused, try std.fs.path.join(a, &.{ root, "mirror" }));
    try std.testing.expectEqual(@as(u64, 4), (try std.Io.Dir.cwd().statFile(context.io, try std.fs.path.join(a, &.{ mirror.root, "data.bin" }), .{})).size);
    try context.write(config, try std.fmt.allocPrint(a, "{{\"version\":1,\"budgets\":{{\"max_total_bytes\":{d}}}}}", .{text.len + 4}));
    try std.testing.expectError(error.SourceChanged, verify(context, refused));
    const widened = try capture(context, entry);
    try std.testing.expectEqualStrings("abcd", widened.support.assets[0].data);
    try std.testing.expect(widened.support.assets[0].refused_size == null);
}

// spec-case: EMBED-PROJECT-BUDGET-1
// spec-case: NATIVE-TEST-12
test "provider snapshots capture newly reachable embedded assets and reject their mid-run edits" {
    var environment: std.process.Environ.Map = .init(std.testing.allocator);
    defer environment.deinit();
    var context = try fs.Context.init(std.testing.allocator, std.testing.io, &environment);
    defer context.deinit();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const a = context.allocator;
    const root = try temporary.dir.realPathFileAlloc(context.io, ".", a);
    const entry = try std.fs.path.join(a, &.{ root, "main.my" });
    const asset = try std.fs.path.join(a, &.{ root, "fixture.bin" });
    try context.write(entry, "module main\nimport dependency\n");
    try context.write(try std.fs.path.join(a, &.{ root, "dependency.my" }), "module dependency\n");
    try context.write(try std.fs.path.join(a, &.{ root, "fixture.my" }), "module fixture\nconst DATA: bytes = embed_bytes(\"fixture.bin\")\n");
    try context.write(asset, "abcd");
    const production = try capture(context, entry);
    try std.testing.expectEqual(@as(usize, 0), production.support.assets.len);
    const staged = try materialize(context, production, try std.fs.path.join(a, &.{ root, "staged" }));
    const providers = try std.json.parseFromSlice(std.json.Value, a, "{\"dependency.my\":\"module dependency\\nimport fixture\\n\"}", .{});
    const replaced = try replace(context, staged, providers.value, try std.fs.path.join(a, &.{ root, "provider" }));
    try std.testing.expectEqual(@as(usize, 1), replaced.support.assets.len);
    try std.testing.expectEqualStrings("abcd", try context.read(try std.fs.path.join(a, &.{ replaced.root, "fixture.bin" })));
    try verifyAssets(context, replaced);
    try context.write(asset, "dcba");
    try std.testing.expectError(error.SourceChanged, verifyAssets(context, replaced));
    const recaptured = try replace(context, staged, providers.value, try std.fs.path.join(a, &.{ root, "recaptured" }));
    try std.testing.expect(!std.mem.eql(u8, replaced.identity, recaptured.identity));
    try std.testing.expectEqualStrings("dcba", recaptured.support.assets[0].data);
}
