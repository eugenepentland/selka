//! The operating system's world for the engine (spec §4): the files, directories, variables and tools of the machine
//! the process runs on. It is the only place the engine's context reaches the filesystem and the environment; a kind
//! never imports it. It answers a listing filter by the number `inputs.Filter` gives the filter.
const std = @import("std");
const language = @import("selka");
const inputs = @import("../inputs.zig");
const tool_identity = @import("../tool_identity.zig");
const digest_rules = @import("digest.zig");
const world_rules = @import("world.zig");
const Digest = digest_rules.Digest;
const Stat = world_rules.Stat;
const World = world_rules.World;

/// Files a session reads from memory in place of the disk (the test runner's providers and the stub `main` it appends to an entry):
/// the project-relative paths it answers for, and their bytes. The engine reads such a file through the world as the session read it,
/// so a record made over an overlaid module is valid exactly while the overlaid bytes are.
pub const Overlay = struct {
    context: *anyopaque,
    /// Whether the session reads `path` from memory.
    has: *const fn (context: *anyopaque, path: []const u8) bool,
    /// The bytes of an overlaid `path` in `arena`, or null when the session cannot give them.
    text: *const fn (context: *anyopaque, arena: std.mem.Allocator, path: []const u8) ?[]const u8,
};

/// The machine's world.
pub const OsWorld = struct {
    io: std.Io,
    /// The environment the process was given; the context reads variables from it, not from the process.
    environment: *const std.process.Environ.Map,
    /// The work directory, where the toolchain identity keeps its memo.
    work: []const u8,
    /// The directory a path that is not absolute is read from, or empty for the process's working directory. A project is
    /// read through this root with project-relative paths, so no record names the tree it was made in (spec §17.1, G-D11).
    root: []const u8 = "",
    /// What the session reads from memory instead of the disk, when it overlays anything.
    overlay: ?Overlay = null,

    /// The `World` the engine reads through. The `OsWorld` must outlive it.
    pub fn world(self: *OsWorld) World {
        return .{ .context = self, .vtable = &vtable };
    }
};

fn fromContext(context: *anyopaque) *OsWorld {
    return @ptrCast(@alignCast(context));
}

fn clamp(value: i96) i64 {
    return std.math.cast(i64, value) orelse if (value < 0) std.math.minInt(i64) else std.math.maxInt(i64);
}

/// The path to hand the operating system for `path`: itself, or beneath the root when it is relative and there is one. A path
/// that does not fit the buffer is returned as it is and is not found.
fn underRoot(self: *const OsWorld, buffer: []u8, path: []const u8) []const u8 {
    if (self.root.len == 0 or std.fs.path.isAbsolute(path) or std.mem.eql(u8, path, world_rules.environment_path)) return path;
    return std.fmt.bufPrint(buffer, "{s}/{s}", .{ self.root, path }) catch path;
}

fn statOf(context: *anyopaque, given: []const u8) ?Stat {
    const self = fromContext(context);
    // An overlaid file has no tuple that tells one version from another, so it is hashed whenever it is validated.
    if (self.overlay) |overlay| if (overlay.has(overlay.context, given)) return Stat.none;
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = underRoot(self, &buffer, given);
    const found = std.Io.Dir.cwd().statFile(self.io, path, .{}) catch return null;
    return .{ .inode = @intCast(found.inode), .size = found.size, .mtime = clamp(found.mtime.nanoseconds), .ctime = clamp(found.ctime.nanoseconds) };
}

fn readOf(context: *anyopaque, arena: std.mem.Allocator, given: []const u8, limit: usize) world_rules.ReadError!?[]const u8 {
    const self = fromContext(context);
    if (self.overlay) |overlay| if (overlay.has(overlay.context, given)) {
        const bytes = overlay.text(overlay.context, arena, given) orelse return error.ReadFailed;
        return if (bytes.len > limit) error.ReadFailed else bytes;
    };
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = underRoot(self, &buffer, given);
    return std.Io.Dir.cwd().readFileAlloc(self.io, path, arena, .limited(limit)) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotFound, error.NotDir => return null,
        else => return error.ReadFailed,
    };
}

fn listOf(context: *anyopaque, arena: std.mem.Allocator, given: []const u8, filter: u8) world_rules.ReadError!?[]const []const u8 {
    const self = fromContext(context);
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const path = underRoot(self, &buffer, given);
    if (std.mem.eql(u8, path, world_rules.environment_path)) {
        const keyed = try keyedEntries(self, arena);
        return keyed;
    }
    const rule = std.enums.fromInt(inputs.Filter, filter) orelse return error.ReadFailed;
    var directory = std.Io.Dir.cwd().openDir(self.io, path, .{ .iterate = true }) catch return null;
    defer directory.close(self.io);
    var kept: std.ArrayList([]const u8) = .empty;
    var entries = directory.iterate();
    while (entries.next(self.io) catch return null) |entry| {
        if (rule.keeps(entry.name)) try kept.append(arena, try arena.dupe(u8, entry.name));
    }
    return kept.items;
}

/// One `NAME=VALUE` per variable of the keyed class of the environment identity contract.
fn keyedEntries(self: *OsWorld, arena: std.mem.Allocator) world_rules.ReadError![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var entries = self.environment.iterator();
    while (entries.next()) |entry| {
        if (!language.environment_identity.keyed(entry.key_ptr.*)) continue;
        try names.append(arena, try std.fmt.allocPrint(arena, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }));
    }
    return names.items;
}

fn variableOf(context: *anyopaque, name: []const u8) ?[]const u8 {
    return fromContext(context).environment.get(name);
}

fn placementOf(_: *anyopaque, name: []const u8) bool {
    return language.environment_identity.classify(name) == .placement;
}

fn toolOf(context: *anyopaque, arena: std.mem.Allocator, path: []const u8) world_rules.ReadError!?Digest {
    const self = fromContext(context);
    const identity = tool_identity.capture(.{ .arena = arena, .io = self.io, .environment = self.environment, .executable = path, .cache = self.work }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.ToolNotFound => return null,
        else => return error.ReadFailed,
    };
    return identity.digest;
}

fn nowOf(context: *anyopaque) i64 {
    return clamp(language.native_cache_retention.retentionNanoseconds(fromContext(context).io));
}

const vtable: World.VTable = .{ .stat = statOf, .read = readOf, .list = listOf, .variable = variableOf, .placement = placementOf, .tool = toolOf, .now = nowOf };

test "the machine's world reports files, directories, variables and the filters of the older listing handle" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "strings.selka", .data = "x = 1\n" });
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "local.selka", .data = "" });
    var environment: std.process.Environ.Map = .init(a);
    try environment.put("SELKA_JOBS", "4");
    try environment.put("SOURCE_DATE_EPOCH", "7");
    var machine: OsWorld = .{ .io = std.testing.io, .environment = &environment, .work = root };
    const world = machine.world();
    const file = try std.fs.path.join(a, &.{ root, "strings.selka" });
    try std.testing.expectEqual(@as(u64, 6), world.stat(file).?.size);
    try std.testing.expectEqual(@as(?Stat, null), world.stat(try std.fs.path.join(a, &.{ root, "none" })));
    try std.testing.expectEqualStrings("x = 1\n", (try world.read(a, file, 1 << 20)).?);
    try std.testing.expectEqual(@as(?[]const u8, null), try world.read(a, try std.fs.path.join(a, &.{ root, "none" }), 1 << 20));
    try std.testing.expectError(error.ReadFailed, world.read(a, root, 1 << 20));
    try std.testing.expectEqual(@as(usize, 2), (try world.list(a, root, 0)).?.len);
    const standard = (try world.list(a, root, @backingInt(inputs.Filter.standard_modules))).?;
    try std.testing.expectEqual(@as(usize, 1), standard.len);
    try std.testing.expectEqualStrings("strings.selka", standard[0]);
    try std.testing.expectEqualStrings("7", world.variable("SOURCE_DATE_EPOCH").?);
    try std.testing.expect(world.placement("SELKA_JOBS"));
    try std.testing.expect(!world.placement("SOURCE_DATE_EPOCH"));
    try std.testing.expect(world.now() > 1_700_000_000 * std.time.ns_per_s);
}

test "a relative path is read beneath the root, and an absolute path is read where it is" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var temporary = std.testing.tmpDir(.{});
    defer temporary.cleanup();
    const root = try temporary.dir.realPathFileAlloc(std.testing.io, ".", a);
    try temporary.dir.createDirPath(std.testing.io, "src");
    try temporary.dir.writeFile(std.testing.io, .{ .sub_path = "src/lexer.selka", .data = "lexer" });
    var environment: std.process.Environ.Map = .init(a);
    var machine: OsWorld = .{ .io = std.testing.io, .environment = &environment, .work = root, .root = root };
    const world = machine.world();
    try std.testing.expectEqual(@as(u64, 5), world.stat("src/lexer.selka").?.size);
    try std.testing.expectEqualStrings("lexer", (try world.read(a, "src/lexer.selka", 1 << 20)).?);
    try std.testing.expectEqualStrings("lexer", (try world.read(a, try std.fs.path.join(a, &.{ root, "src/lexer.selka" }), 1 << 20)).?);
    try std.testing.expectEqual(@as(?Stat, null), world.stat("src/none.selka"));
    try std.testing.expectEqual(@as(usize, 1), (try world.list(a, "src", 0)).?.len);
    var unrooted: OsWorld = .{ .io = std.testing.io, .environment = &environment, .work = root };
    try std.testing.expectEqual(@as(?Stat, null), unrooted.world().stat("src/lexer.selka"));
}
