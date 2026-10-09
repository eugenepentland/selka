//! Conservative fixed-target Clang discovery inputs, additional to the complete
//! Zig/library/runtime inventory. Exact reviewed state permits reuse; another
//! layout remains executable through the unproved-tool path. No native flags
//! change. Official 22.1.8 sources explain these branches; a reproducible build
//! relation to the pinned binary is unestablished, so approval is platform-bound.
const std = @import("std");
const platform = @import("core_tool_platform");

/// Existing inputs keep complete content/stat guards. Only proved directory
/// existence/alias queries may ignore membership timestamps. Enumerated version
/// directories retain complete generations and reviewed sorted membership.
pub const Role = enum { content, predicate, membership, discovery_file };
/// Logical selection path and the kind of generation guard it requires.
pub const Path = struct { name: []const u8, role: Role };
/// Discovery errors cannot silently grant persistent reuse.
pub const Error = error{ OutOfMemory, ReadFailed };
const Digest = [32]u8;
const directory_suffixes = [_][]const u8{ "lib64", "lib", "lib32", "libx32" };
const gcc_families = [_][]const u8{ "gcc", "gcc-cross" };
const native_aliases = [_][]const u8{
    "x86_64-unknown-linux5.10.0-gnu2.31.0", "x86_64-linux5.10.0-gnu2.31.0",
    "x86_64-linux-gnu",                     "x86_64-unknown-linux-gnu",
    "x86_64-pc-linux-gnu",                  "x86_64-redhat-linux6E",
    "x86_64-redhat-linux",                  "x86_64-suse-linux",
    "x86_64-manbo-linux-gnu",               "x86_64-slackware-linux",
    "x86_64-unknown-linux",                 "x86_64-amazon-linux",
};
const biarch_aliases = [_][]const u8{
    "i386-unknown-linux5.10.0-gnu2.31.0", "i386-linux5.10.0-gnu2.31.0",
    "i586-linux-gnu",                     "i686-linux-gnu",
    "i686-pc-linux-gnu",                  "i386-redhat-linux6E",
    "i686-redhat-linux",                  "i386-redhat-linux",
    "i586-suse-linux",                    "i686-montavista-linux",
    "x86_64-linux-gnux32",                "x86_64-pc-linux-gnux32",
};
const host_predicates = platform.discovery_predicates;
const reviewed_installation = platform.discovery_installation;
const installation_predicates = [_][]const u8{
    "", "include/c++", "include/g++-v15", "include/g++-v15.-1",
};
const multilib_suffixes = [_][]const u8{ "", "64", "32", "x32", "sparcv8plus" };

const Builder = struct {
    arena: std.mem.Allocator,
    entries: std.ArrayList(Path) = .empty,

    fn add(self: *Builder, name: []const u8, role: Role) Error!void {
        for (self.entries.items) |entry| if (std.mem.eql(u8, entry.name, name)) return;
        try self.entries.append(self.arena, .{ .name = name, .role = role });
    }

    fn triples(self: *Builder, root: []const u8, aliases: []const []const u8) Error!void {
        for (gcc_families) |family| {
            const base = try std.fs.path.join(self.arena, &.{ root, family });
            try self.add(base, .predicate);
            for (aliases) |alias| try self.add(try std.fs.path.join(self.arena, &.{ base, alias }), .membership);
        }
    }

    fn prefix(self: *Builder, root: []const u8) Error!void {
        try self.add(root, .predicate);
        for (directory_suffixes, 0..) |suffix, index| {
            const path = try std.fs.path.join(self.arena, &.{ root, suffix });
            try self.add(path, .predicate);
            if (index < 2) try self.triples(path, &native_aliases);
            if (index != 0) try self.triples(path, &biarch_aliases);
        }
    }
};

/// Generate every permitted discovery branch without inspecting command outputs
/// or traversing their parents. Missing enclosing roots guard deeper candidates.
pub fn paths(arena: std.mem.Allocator, executable: []const u8) Error![]const Path {
    var builder: Builder = .{ .arena = arena };
    const tool_directory = std.fs.path.dirname(executable) orelse return error.ReadFailed;
    const parent = std.fs.path.dirname(tool_directory) orelse return error.ReadFailed;
    try builder.add(tool_directory, .predicate);
    try builder.prefix(parent);
    try builder.prefix(platform.discovery_system_prefix);
    for (platform.discovery_files) |file| try builder.add(file.path, .discovery_file);
    for (host_predicates) |path| try builder.add(path, .predicate);
    for (installation_predicates) |suffix|
        try builder.add(try std.fs.path.join(arena, &.{ reviewed_installation, suffix }), .predicate);
    for (multilib_suffixes) |suffix|
        try builder.add(try std.fs.path.join(arena, &.{ reviewed_installation, suffix, "crtbegin.o" }), .discovery_file);
    std.mem.sort(Path, builder.entries.items, {}, before);
    return builder.entries.items;
}

fn before(_: void, a: Path, b: Path) bool {
    return std.mem.lessThan(u8, a.name, b.name);
}

fn frame(hash: anytype, bytes: []const u8) void {
    var length: [8]u8 = undefined;
    std.mem.writeInt(u64, &length, bytes.len, .little);
    hash.update(&length);
    hash.update(bytes);
}

/// Bind collector branch descriptors and exact approved discovery state to both
/// hint and approval keys, including the distinction between directory roles.
pub fn policy(hash: anytype) void {
    frame(hash, "core-native-discovery-v1");
    frame(hash, platform.discovery_state);
    frame(hash, platform.discovery_system_prefix);
    for (std.meta.tags(Role)) |role| frame(hash, @tagName(role));
    for (directory_suffixes) |part| frame(hash, part);
    for (gcc_families) |family| frame(hash, family);
    for (native_aliases) |alias| frame(hash, alias);
    for (biarch_aliases) |alias| frame(hash, alias);
    for (host_predicates) |path| frame(hash, path);
    frame(hash, reviewed_installation);
    for (installation_predicates) |suffix| frame(hash, suffix);
    for (multilib_suffixes) |suffix| frame(hash, suffix);
    for (platform.discovery_files) |file| frame(hash, file.path);
}

fn relative(arena: std.mem.Allocator, path: []const u8, executable: []const u8) Error![]const u8 {
    const directory = std.fs.path.dirname(executable) orelse return error.ReadFailed;
    const parent = std.fs.path.dirname(directory) orelse return error.ReadFailed;
    if (std.mem.eql(u8, path, directory)) return "@tool-directory";
    if (std.mem.eql(u8, path, parent)) return "@tool-parent";
    if (std.mem.startsWith(u8, path, parent) and path.len > parent.len and path[parent.len] == '/')
        return std.fmt.allocPrint(arena, "@tool-parent{s}", .{path[parent.len..]});
    return path;
}

fn stat(io: std.Io, path: []const u8) Error!?std.Io.File.Stat {
    return std.Io.Dir.cwd().statFile(io, path, .{}) catch |err| switch (err) {
        // A guarded non-directory ancestor makes this candidate unreachable.
        // Its own type/content remains present in the discovery inventory.
        error.FileNotFound, error.NotDir => null,
        else => return error.ReadFailed,
    };
}

fn directoryMembers(arena: std.mem.Allocator, io: std.Io, path: []const u8, hash: *std.crypto.hash.sha2.Sha256) Error!void {
    var dir = std.Io.Dir.cwd().openDir(io, path, .{ .iterate = true }) catch return error.ReadFailed;
    defer dir.close(io);
    var entries: std.ArrayList([]const u8) = .empty;
    var iterator = dir.iterate();
    while (iterator.next(io) catch return error.ReadFailed) |entry|
        try entries.append(arena, try arena.dupe(u8, entry.name));
    std.mem.sort([]const u8, entries.items, {}, stringBefore);
    frame(hash, "members");
    for (entries.items) |entry| frame(hash, entry);
    frame(hash, "end-members");
}

fn stringBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

fn selection(arena: std.mem.Allocator, io: std.Io, entry: Path, executable: []const u8, hash: *std.crypto.hash.sha2.Sha256) Error!void {
    frame(hash, try relative(arena, entry.name, executable));
    frame(hash, @tagName(entry.role));
    const info = (try stat(io, entry.name)) orelse {
        frame(hash, "absent");
        return;
    };
    frame(hash, @tagName(info.kind));
    const resolved = std.Io.Dir.cwd().realPathFileAlloc(io, entry.name, arena) catch |err| return readError(err);
    frame(hash, try relative(arena, resolved, executable));
    if (info.kind == .directory and entry.role == .membership)
        try directoryMembers(arena, io, entry.name, hash);
    if (info.kind == .file) {
        const bytes = std.Io.Dir.cwd().readFileAlloc(io, entry.name, arena, .limited(1 << 20)) catch |err| return readError(err);
        var digest: Digest = undefined;
        std.crypto.hash.sha2.Sha256.hash(bytes, &digest, .{});
        frame(hash, &digest);
    }
}

fn readError(err: anyerror) Error {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.ReadFailed;
}

/// Reviewed content/type/alias/membership state independent of directory mtimes
/// and physical tool-copy location. Full input generations separately guard
/// reads before/after review and compilation, including restored-mtime edits.
pub fn state(arena: std.mem.Allocator, io: std.Io, executable: []const u8) Error!Digest {
    const entries = try paths(arena, executable);
    const normalized = try arena.alloc(Normalized, entries.len);
    for (entries, normalized) |entry, *row| row.* = .{ .name = try relative(arena, entry.name, executable), .entry = entry };
    std.mem.sort(Normalized, normalized, {}, normalizedBefore);
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    frame(&hash, "core-native-discovery-state-v1");
    for (normalized) |row| try selection(arena, io, row.entry, executable, &hash);
    var digest: Digest = undefined;
    hash.final(&digest);
    return digest;
}

const Normalized = struct { name: []const u8, entry: Path };

fn normalizedBefore(_: void, left: Normalized, right: Normalized) bool {
    return std.mem.lessThan(u8, left.name, right.name);
}

/// Unknown discovery layouts/contents refuse persistent reuse. This approval
/// is additional to exact executable/library/runtime content approval.
pub fn approved(arena: std.mem.Allocator, io: std.Io, executable: []const u8) Error!bool {
    const current = std.fmt.bytesToHex(try state(arena, io, executable), .lower);
    return std.mem.eql(u8, &current, platform.discovery_state);
}

const Fixture = struct {
    temporary: std.testing.TmpDir,
    arena: std.heap.ArenaAllocator,

    fn init(allocator: std.mem.Allocator) Fixture {
        return .{ .temporary = std.testing.tmpDir(.{ .iterate = true }), .arena = .init(allocator) };
    }

    fn deinit(self: *Fixture) void {
        self.arena.deinit();
        self.temporary.cleanup();
    }

    fn path(self: *Fixture, suffix: []const u8) ![]const u8 {
        const root = try self.temporary.dir.realPathFileAlloc(std.testing.io, ".", self.arena.allocator());
        return std.fs.path.join(self.arena.allocator(), &.{ root, suffix });
    }

    fn signature(self: *Fixture, suffix: []const u8, role: Role) !Digest {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        const entry: Path = .{ .name = try self.path(suffix), .role = role };
        try selection(self.arena.allocator(), std.testing.io, entry, try self.path("zig"), &hash);
        var result: Digest = undefined;
        hash.final(&result);
        return result;
    }
};

// spec-case: NEW-CORE-S4-TEST-3
test "paths cover distro fallback GCC candidates and refuse invalid paths allocation" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const entries = try paths(fixture.arena.allocator(), try fixture.path("zig"));
    var distro = false;
    var gcc = false;
    for (entries) |entry| {
        if (std.mem.eql(u8, entry.name, "/etc/SuSE-release")) distro = entry.role == .discovery_file;
        if (std.mem.eql(u8, entry.name, "/usr/lib/gcc/i686-montavista-linux")) gcc = entry.role == .membership;
    }
    try std.testing.expect(distro);
    try std.testing.expect(gcc);
    try std.testing.expectError(error.ReadFailed, paths(fixture.arena.allocator(), "zig"));
    try std.testing.expectError(error.OutOfMemory, paths(std.testing.failing_allocator, "/owned/tool/zig"));
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery version membership changes but predicate directory writes do not" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.temporary.dir.createDirPath(std.testing.io, "versions/15");
    const original = try fixture.signature("versions", .membership);
    const predicate = try fixture.signature("versions", .predicate);
    try fixture.temporary.dir.createDirPath(std.testing.io, "versions/16");
    try std.testing.expect(!std.mem.eql(u8, &original, &try fixture.signature("versions", .membership)));
    try std.testing.expectEqual(predicate, try fixture.signature("versions", .predicate));
    try fixture.temporary.dir.deleteTree(std.testing.io, "versions/16");
    try std.testing.expectEqual(original, try fixture.signature("versions", .membership));
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery absent roots additions removals and symlink retarget change state" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    const absent = try fixture.signature("resource", .predicate);
    try fixture.temporary.dir.createDirPath(std.testing.io, "resource");
    try std.testing.expect(!std.mem.eql(u8, &absent, &try fixture.signature("resource", .predicate)));
    try fixture.temporary.dir.deleteTree(std.testing.io, "resource");
    try std.testing.expectEqual(absent, try fixture.signature("resource", .predicate));
    try fixture.temporary.dir.createDirPath(std.testing.io, "first");
    try fixture.temporary.dir.createDirPath(std.testing.io, "other");
    try fixture.temporary.dir.symLink(std.testing.io, "first", "resource", .{ .is_directory = true });
    const linked = try fixture.signature("resource", .predicate);
    try fixture.temporary.dir.deleteFile(std.testing.io, "resource");
    try fixture.temporary.dir.symLink(std.testing.io, "other", "resource", .{ .is_directory = true });
    try std.testing.expect(!std.mem.eql(u8, &linked, &try fixture.signature("resource", .predicate)));
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery consumed file restored mtime edits and unreadable member refuse" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "distro", .data = "first" });
    const original = try fixture.signature("distro", .discovery_file);
    const info = try fixture.temporary.dir.statFile(std.testing.io, "distro", .{});
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "distro", .data = "other" });
    try fixture.temporary.dir.setTimestamps(std.testing.io, "distro", .{ .modify_timestamp = .init(info.mtime) });
    try std.testing.expect(!std.mem.eql(u8, &original, &try fixture.signature("distro", .discovery_file)));
    var hash = std.crypto.hash.sha2.Sha256.init(.{});
    try std.testing.expectError(error.ReadFailed, directoryMembers(fixture.arena.allocator(), std.testing.io, try fixture.path("distro"), &hash));
    try std.testing.expectError(error.OutOfMemory, state(std.testing.failing_allocator, std.testing.io, try fixture.path("zig")));
}

// spec-case: NEW-CORE-S4-TEST-3
test "discovery unreachable descendants retain non-directory parent selection" {
    var fixture = Fixture.init(std.testing.allocator);
    defer fixture.deinit();
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib", .data = "first" });
    const parent = try fixture.signature("lib", .predicate);
    const child = try fixture.signature("lib/gcc", .membership);
    try fixture.temporary.dir.writeFile(std.testing.io, .{ .sub_path = "lib", .data = "other" });
    try std.testing.expect(!std.mem.eql(u8, &parent, &try fixture.signature("lib", .predicate)));
    try std.testing.expectEqual(child, try fixture.signature("lib/gcc", .membership));
    try fixture.temporary.dir.symLink(std.testing.io, "loop", "loop", .{});
    try std.testing.expectError(error.ReadFailed, fixture.signature("loop/gcc", .membership));
}
