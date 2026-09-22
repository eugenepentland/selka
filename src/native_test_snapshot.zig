//! Immutable bounded source inventories and isolated guest provider replacements.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
const project_config = @import("project_config.zig");
const project = @import("native_test_root").snapshot_project;
/// Source races and invalid provider contracts discard test results.
pub const Error = fs.Error || std.Io.Dir.OpenError || std.Io.Dir.SelectiveWalker.Error ||
    std.Io.File.StatError || std.Io.File.ReadPositionalError ||
    error{ InvalidTestSnapshot, SourceChanged, InvalidTestProviders, ProviderSignatureChanged };
const byte_limit = 16 * 1024 * 1024;
/// Entry-point body appended to a library entry so it can be checked as a project.
const main_stub = "def main() -> int:\n    return 0\n";
/// Captured bytes are independent of subsequent source edits.
pub const File = struct { path: []const u8, data: []const u8, hash: []const u8 };
/// Captured required-configuration files and their combined policy identity.
pub const Support = struct { files: []const File = &.{}, policy_identity: ?[]const u8 = null };
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
        try files.append(context.allocator, .{ .path = path, .data = bytes, .hash = try fs.hash(context.allocator, bytes) });
    }
    std.mem.sort(File, files.items, {}, less);
    if (find(files.items, name) == null) return error.InvalidTestSnapshot;
    const support = try captureSupport(context, absolute);
    return .{
        .root = root,
        .entry = name,
        .entry_path = absolute,
        .files = files.items,
        .support = support,
        .identity = try identity(context.allocator, name, files.items, support.files),
        .excluded = excluded,
    };
}

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
    return .{ .files = try support.toOwnedSlice(context.allocator), .policy_identity = policy_identity };
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
fn identity(allocator: std.mem.Allocator, entry: []const u8, files: []const File, support: []const File) Error![]const u8 {
    var loaded = project.Project.init(allocator);
    defer loaded.deinit();
    var provider: MemoryProvider = .{ .files = files };
    const module_name = try entryModule(allocator, entry);
    loaded.load(.{ .context = &provider, .read = MemoryProvider.read }, module_name, .{}) catch return broadIdentity(allocator, entry, files, support);
    const pairs = try allocator.alloc([2][]const u8, loaded.modules.items.len + support.len);
    var count: usize = 0;
    for (loaded.modules.items) |module| {
        const path = project.modulePath(allocator, module.name) catch |err| switch (err) {
            error.InvalidModuleName => return error.InvalidTestSnapshot,
            error.OutOfMemory => return error.OutOfMemory,
        };
        const index = find(files, path) orelse continue;
        pairs[count] = .{ files[index].path, files[index].hash };
        count += 1;
    }
    for (support) |file| {
        pairs[count] = .{ file.path, file.hash };
        count += 1;
    }
    std.mem.sort([2][]const u8, pairs[0..count], {}, pairLess);
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{ .version = "resolved-source-v2", .entry = entry, .files = pairs[0..count] }, .{});
    return fs.hash(allocator, encoded);
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

fn broadIdentity(allocator: std.mem.Allocator, entry: []const u8, files: []const File, support: []const File) Error![]const u8 {
    const pairs = try allocator.alloc([2][]const u8, files.len + support.len);
    for (files, pairs[0..files.len]) |file, *pair| pair.* = .{ file.path, file.hash };
    for (support, pairs[files.len..]) |file, *pair| pair.* = .{ file.path, file.hash };
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{ .version = "broad-source-v1", .entry = entry, .files = pairs }, .{});
    return fs.hash(allocator, encoded);
}

fn pairLess(_: void, left: [2][]const u8, right: [2][]const u8) bool {
    return std.mem.lessThan(u8, left[0], right[0]);
}
/// Reject edits, additions, deletions, or dependency changes since initial capture.
pub fn verify(context: fs.Context, snapshot: Snapshot) Error!void {
    const current = try captureExcluding(context, snapshot.entry_path, snapshot.excluded);
    if (!std.mem.eql(u8, current.identity, snapshot.identity)) return error.SourceChanged;
}

/// Provider substitutions may introduce imports to any captured neighbor, so
/// require their broad fixture inventory to remain byte-for-byte current.
fn verifyProviderInventory(context: fs.Context, snapshot: Snapshot) Error!void {
    const current = try captureExcluding(context, snapshot.entry_path, snapshot.excluded);
    const before = try broadIdentity(context.allocator, snapshot.entry, snapshot.files, snapshot.support.files);
    const after = try broadIdentity(context.allocator, current.entry, current.files, current.support.files);
    if (!std.mem.eql(u8, before, after)) return error.SourceChanged;
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
    return .{
        .root = root,
        .entry = snapshot.entry,
        .entry_path = try std.fs.path.join(context.allocator, &.{ root, snapshot.entry }),
        .files = snapshot.files,
        .support = snapshot.support,
        .identity = snapshot.identity,
    };
}

/// Return a snapshot whose entry file declares a stub `main` when it has none,
/// so a library module or `*_test.my` file can be checked and tested as a
/// project. A file with a `main` and every other file are returned unchanged.
/// A patched projection carries the identity of its patched bytes, because that
/// is what the checker and `verify` see; the caller keeps the user's snapshot.
pub fn withTestEntry(context: fs.Context, snapshot: Snapshot) Error!Snapshot {
    const index = find(snapshot.files, snapshot.entry) orelse return error.InvalidTestSnapshot;
    const original = snapshot.files[index].data;
    if (declaresMain(original)) return snapshot;
    var patched: std.ArrayList(u8) = .empty;
    if (!hasModuleHeader(original)) {
        const stem = snapshot.entry[0 .. snapshot.entry.len - ".my".len];
        try patched.appendSlice(context.allocator, "module ");
        for (stem) |byte| try patched.append(context.allocator, if (byte == std.fs.path.sep) '.' else byte);
        try patched.append(context.allocator, '\n');
    }
    try patched.appendSlice(context.allocator, original);
    if (original.len != 0 and original[original.len - 1] != '\n') try patched.append(context.allocator, '\n');
    try patched.appendSlice(context.allocator, main_stub);
    const files = try context.allocator.dupe(File, snapshot.files);
    files[index] = .{ .path = snapshot.files[index].path, .data = patched.items, .hash = try fs.hash(context.allocator, patched.items) };
    return .{
        .root = snapshot.root,
        .entry = snapshot.entry,
        .entry_path = snapshot.entry_path,
        .files = files,
        .support = snapshot.support,
        .identity = try identity(context.allocator, snapshot.entry, files, snapshot.support.files),
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
    var total: usize = 0;
    const temp_root = try context.absolute(directory);
    const root = try mirrorPath(context.allocator, temp_root, snapshot.root);
    for (snapshot.files) |file| {
        const replacement = replacements.object.get(file.path);
        const data = if (replacement) |value| value.string else file.data;
        total = std.math.add(usize, total, file.path.len) catch return error.InvalidTestProviders;
        total = std.math.add(usize, total, data.len) catch return error.InvalidTestProviders;
        if (total > byte_limit) return error.InvalidTestProviders;
        const target = try std.fs.path.join(context.allocator, &.{ root, file.path });
        try context.mkdir(std.fs.path.dirname(target).?);
        try context.write(target, data);
    }
    for (snapshot.support.files) |file| {
        const target = try std.fs.path.join(context.allocator, &.{ temp_root, file.path });
        try context.mkdir(std.fs.path.dirname(target).?);
        try context.write(target, file.data);
    }
    return capture(context, try std.fs.path.join(context.allocator, &.{ root, snapshot.entry }));
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
    try std.testing.expect(std.mem.startsWith(u8, patched_bare.files[bare_index].data, "module bare_test\n"));
    const program = try std.fs.path.join(context.allocator, &.{ root, "app.my" });
    try context.write(program, "module app\ndef main() -> int:\n    return 0\n");
    const app = try capture(context, program);
    const untouched = try withTestEntry(context, app);
    const app_index = find(untouched.files, "app.my").?;
    try std.testing.expectEqualStrings(app.files[app_index].data, untouched.files[app_index].data);
    try std.testing.expect(declaresMain("def main() -> int:\n    return 0\n"));
    try std.testing.expect(!declaresMain("def mainstreet() -> int:\n    return 0\n"));
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
    try std.testing.expect(std.mem.startsWith(u8, prepared.files[index].data, "module tests.parser_test\n"));
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
