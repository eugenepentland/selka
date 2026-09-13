//! Immutable bounded source inventories and isolated guest provider replacements.
const std = @import("std");
const fs = @import("qbe_build_io.zig");
const v = @import("qbe_build_value.zig");
/// Source races and invalid provider contracts discard test results.
pub const Error = fs.Error || std.Io.Dir.OpenError || std.Io.Dir.SelectiveWalker.Error ||
    std.Io.File.StatError || std.Io.File.ReadPositionalError ||
    error{ InvalidTestSnapshot, SourceChanged, InvalidTestProviders, ProviderSignatureChanged };
const byte_limit = 16 * 1024 * 1024;
/// Captured bytes are independent of subsequent source edits.
pub const File = struct { path: []const u8, data: []const u8, hash: []const u8 };
/// Paths and bytes belong to the enclosing native build context.
pub const Snapshot = struct {
    root: []const u8,
    entry: []const u8,
    entry_path: []const u8,
    files: []const File,
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
    const root = std.fs.path.dirname(absolute) orelse return error.InvalidTestSnapshot;
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
    const name = std.fs.path.basename(absolute);
    if (find(files.items, name) == null) return error.InvalidTestSnapshot;
    return .{ .root = root, .entry = name, .entry_path = absolute, .files = files.items, .identity = try identity(context.allocator, name, files.items), .excluded = excluded };
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
fn identity(allocator: std.mem.Allocator, entry: []const u8, files: []const File) Error![]const u8 {
    const pairs = try allocator.alloc([2][]const u8, files.len);
    for (files, pairs) |file, *pair| pair.* = .{ file.path, file.hash };
    const encoded = try std.json.Stringify.valueAlloc(allocator, .{ .version = "worker-source-v1", .entry = entry, .files = pairs }, .{});
    return fs.hash(allocator, encoded);
}
/// Reject edits, additions, deletions, or dependency changes since initial capture.
pub fn verify(context: fs.Context, snapshot: Snapshot) Error!void {
    const current = try captureExcluding(context, snapshot.entry_path, snapshot.excluded);
    if (!std.mem.eql(u8, current.identity, snapshot.identity)) return error.SourceChanged;
}
/// Materialize captured bytes for checking and code generation without rereading live sources.
pub fn materialize(context: fs.Context, snapshot: Snapshot, directory: []const u8) Error!Snapshot {
    const root = try context.absolute(directory);
    for (snapshot.files) |file| {
        const path = try std.fs.path.join(context.allocator, &.{ root, file.path });
        try context.mkdir(std.fs.path.dirname(path).?);
        try context.write(path, file.data);
    }
    return .{ .root = root, .entry = snapshot.entry, .entry_path = try std.fs.path.join(context.allocator, &.{ root, snapshot.entry }), .files = snapshot.files, .identity = snapshot.identity };
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
    try verify(context, snapshot);
    var total: usize = 0;
    for (snapshot.files) |file| {
        const replacement = replacements.object.get(file.path);
        const data = if (replacement) |value| value.string else file.data;
        total = std.math.add(usize, total, file.path.len) catch return error.InvalidTestProviders;
        total = std.math.add(usize, total, data.len) catch return error.InvalidTestProviders;
        if (total > byte_limit) return error.InvalidTestProviders;
        const target = try std.fs.path.join(context.allocator, &.{ directory, file.path });
        try context.mkdir(std.fs.path.dirname(target).?);
        try context.write(target, data);
    }
    return capture(context, try std.fs.path.join(context.allocator, &.{ directory, snapshot.entry }));
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
    try context.write(entry, "module main;");
    try context.write(dependency, "module dependency;");
    const snapshot = try capture(context, entry);
    const invalid = try std.json.parseFromSlice(std.json.Value, context.allocator, "{\"main.my\":\"replacement\"}", .{});
    const injected = try std.json.parseFromSlice(std.json.Value, context.allocator, "{\"dependency.my\":\"module dependency; // fixture\"}", .{});
    const destination = try std.fs.path.join(context.allocator, &.{ root, "snapshot" });
    try std.testing.expectError(error.InvalidTestProviders, replace(context, snapshot, invalid.value, destination));
    const replaced = try replace(context, snapshot, injected.value, destination);
    try std.testing.expect(!std.mem.eql(u8, snapshot.identity, replaced.identity));
    try std.testing.expectEqualStrings("module dependency;", try context.read(dependency));
    try verify(context, snapshot);
    try context.write(dependency, "changed");
    const immutable = try materialize(context, snapshot, try std.fs.path.join(context.allocator, &.{ root, "immutable" }));
    const copied_dependency = try std.fs.path.join(context.allocator, &.{ immutable.root, "dependency.my" });
    try std.testing.expectEqualStrings("module dependency;", try context.read(copied_dependency));
    try verify(context, immutable);
    try std.testing.expectError(error.SourceChanged, verify(context, snapshot));
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
