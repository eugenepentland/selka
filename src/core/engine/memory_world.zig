//! A world held in memory (spec §4's test world): files with stat tuples and a clock the test sets, variables, tools
//! and directories derived from the file names. The property test, the test vectors and the budget measurements run
//! the engine over it so that an edit, a touch or a write inside one clock tick is exactly what the test says.
//!
//! It counts what the engine asks of it (stat calls, reads, listings, tool identities), which is how a test shows
//! that a served query hashed nothing, or hashed once.
const std = @import("std");
const product = @import("selka").product;
const digest_rules = @import("digest.zig");
const world_rules = @import("world.zig");
const Digest = digest_rules.Digest;
const Stat = world_rules.Stat;
const World = world_rules.World;

/// What the world was asked, since it was made or last reset.
pub const Counters = struct {
    stats: std.atomic.Value(u64) = .init(0),
    reads: std.atomic.Value(u64) = .init(0),
    lists: std.atomic.Value(u64) = .init(0),
    tools: std.atomic.Value(u64) = .init(0),
};

const File = struct { bytes: []const u8, inode: u64, mtime: i64, ctime: i64 };

const Tables = struct {
    files: std.StringHashMapUnmanaged(File) = .empty,
    directories: std.StringHashMapUnmanaged(void) = .empty,
    variables: std.StringHashMapUnmanaged([]const u8) = .empty,
    tools: std.StringHashMapUnmanaged(Digest) = .empty,
};

/// A variable whose name starts with this is a placement variable in the memory world.
pub const placement_prefix = "PLACE_";

/// The filter number that keeps only names ending in `.selka` in the memory world (filter 0 keeps every name).
pub const my_files_filter: u8 = 1;

/// The in-memory world. Not thread-safe: a test that uses threads uses the operating system's world.
pub const MemoryWorld = struct {
    /// Owns every path, byte block and name the tables hold.
    gpa: std.mem.Allocator,
    tables: Tables = .{},
    /// The clock, in nanoseconds. A test advances it; a write stamps the file with it.
    clock: i64 = 1_000_000_000_000,
    next_inode: u64 = 1,
    counters: Counters = .{},

    /// An empty world whose allocations come from `gpa`.
    pub fn init(gpa: std.mem.Allocator) MemoryWorld {
        return .{ .gpa = gpa };
    }

    /// Free everything the world holds.
    pub fn deinit(self: *MemoryWorld) void {
        var files = self.tables.files.iterator();
        while (files.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.bytes);
        }
        self.tables.files.deinit(self.gpa);
        var directories = self.tables.directories.keyIterator();
        while (directories.next()) |name| self.gpa.free(name.*);
        self.tables.directories.deinit(self.gpa);
        var variables = self.tables.variables.iterator();
        while (variables.next()) |entry| {
            self.gpa.free(entry.key_ptr.*);
            self.gpa.free(entry.value_ptr.*);
        }
        self.tables.variables.deinit(self.gpa);
        var tools = self.tables.tools.keyIterator();
        while (tools.next()) |name| self.gpa.free(name.*);
        self.tables.tools.deinit(self.gpa);
    }

    /// The `World` the engine reads through.
    pub fn world(self: *MemoryWorld) World {
        return .{ .context = self, .vtable = &vtable };
    }

    /// Move the clock forward.
    pub fn advance(self: *MemoryWorld, nanoseconds: i64) void {
        self.clock += nanoseconds;
    }

    /// Write `bytes` to `path` in place: a new file gets a new inode; an existing one keeps its inode and takes the
    /// clock as its modification and change time. Two writes with no `advance` between them leave the same stamps.
    pub fn write(self: *MemoryWorld, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!void {
        const copy = try self.gpa.dupe(u8, bytes);
        errdefer self.gpa.free(copy);
        if (self.tables.files.getPtr(path)) |file| {
            self.gpa.free(file.bytes);
            file.bytes = copy;
            file.mtime = self.clock;
            file.ctime = self.clock;
            return;
        }
        const name = try self.gpa.dupe(u8, path);
        errdefer self.gpa.free(name);
        try self.tables.files.put(self.gpa, name, .{ .bytes = copy, .inode = self.next_inode, .mtime = self.clock, .ctime = self.clock });
        self.next_inode += 1;
    }

    /// Replace the file at `path` the way a rename over it would: same name, new inode.
    pub fn replace(self: *MemoryWorld, path: []const u8, bytes: []const u8) std.mem.Allocator.Error!void {
        try self.write(path, bytes);
        self.tables.files.getPtr(path).?.inode = self.next_inode;
        self.next_inode += 1;
    }

    /// Set the modification and change time of `path` to the clock without touching its bytes.
    pub fn touch(self: *MemoryWorld, path: []const u8) void {
        const file = self.tables.files.getPtr(path) orelse return;
        file.mtime = self.clock;
        file.ctime = self.clock;
    }

    /// Remove the file at `path`.
    pub fn remove(self: *MemoryWorld, path: []const u8) void {
        const removed = self.tables.files.fetchRemove(path) orelse return;
        self.gpa.free(removed.key);
        self.gpa.free(removed.value.bytes);
    }

    /// Make the (empty) directory `path` exist.
    pub fn makeDirectory(self: *MemoryWorld, path: []const u8) std.mem.Allocator.Error!void {
        if (self.tables.directories.contains(path)) return;
        try self.tables.directories.put(self.gpa, try self.gpa.dupe(u8, path), {});
    }

    /// Set the environment variable `name` to `value`.
    pub fn setVariable(self: *MemoryWorld, name: []const u8, value: []const u8) std.mem.Allocator.Error!void {
        const copy = try self.gpa.dupe(u8, value);
        errdefer self.gpa.free(copy);
        if (self.tables.variables.getPtr(name)) |slot| {
            self.gpa.free(slot.*);
            slot.* = copy;
            return;
        }
        try self.tables.variables.put(self.gpa, try self.gpa.dupe(u8, name), copy);
    }

    /// Unset the environment variable `name`.
    pub fn unsetVariable(self: *MemoryWorld, name: []const u8) void {
        const removed = self.tables.variables.fetchRemove(name) orelse return;
        self.gpa.free(removed.key);
        self.gpa.free(removed.value);
    }

    /// Give the tool at `path` the identity `identity`.
    pub fn setTool(self: *MemoryWorld, path: []const u8, identity: Digest) std.mem.Allocator.Error!void {
        if (self.tables.tools.getPtr(path)) |slot| {
            slot.* = identity;
            return;
        }
        try self.tables.tools.put(self.gpa, try self.gpa.dupe(u8, path), identity);
    }

    /// Zero the counters.
    pub fn resetCounters(self: *MemoryWorld) void {
        self.counters = .{};
    }

    /// How many times the world has been asked for `field` ("stats", "reads", "lists" or "tools").
    pub fn count(self: *const MemoryWorld, comptime field: []const u8) u64 {
        return @field(self.counters, field).load(.monotonic);
    }

    fn childOf(directory: []const u8, path: []const u8) ?[]const u8 {
        if (path.len <= directory.len + 1 or !std.mem.startsWith(u8, path, directory) or path[directory.len] != '/') return null;
        const rest = path[directory.len + 1 ..];
        return rest[0 .. std.mem.indexOfScalar(u8, rest, '/') orelse rest.len];
    }

    fn isDirectory(self: *const MemoryWorld, path: []const u8) bool {
        if (self.tables.directories.contains(path)) return true;
        var files = self.tables.files.keyIterator();
        while (files.next()) |name| if (childOf(path, name.*) != null) return true;
        return false;
    }
};

fn fromContext(context: *anyopaque) *MemoryWorld {
    return @ptrCast(@alignCast(context));
}

fn statOf(context: *anyopaque, path: []const u8) ?Stat {
    const world = fromContext(context);
    _ = world.counters.stats.fetchAdd(1, .monotonic);
    if (world.tables.files.get(path)) |file| return .{ .inode = file.inode, .size = file.bytes.len, .mtime = file.mtime, .ctime = file.ctime };
    if (!world.isDirectory(path)) return null;
    return .{ .inode = std.hash.Wyhash.hash(7, path) | 1, .size = 0, .mtime = 0, .ctime = 0 };
}

fn readOf(context: *anyopaque, arena: std.mem.Allocator, path: []const u8, limit: usize) world_rules.ReadError!?[]const u8 {
    const world = fromContext(context);
    _ = world.counters.reads.fetchAdd(1, .monotonic);
    const file = world.tables.files.get(path) orelse {
        if (world.isDirectory(path)) return error.ReadFailed;
        return null;
    };
    if (file.bytes.len > limit) return error.ReadFailed;
    const copy = try arena.dupe(u8, file.bytes);
    return copy;
}

fn listOf(context: *anyopaque, arena: std.mem.Allocator, path: []const u8, filter: u8) world_rules.ReadError!?[]const []const u8 {
    const world = fromContext(context);
    _ = world.counters.lists.fetchAdd(1, .monotonic);
    if (std.mem.eql(u8, path, world_rules.environment_path)) {
        const keyed = try keyedEntries(world, arena);
        return keyed;
    }
    if (!world.isDirectory(path)) return null;
    var names: std.ArrayList([]const u8) = .empty;
    var files = world.tables.files.keyIterator();
    while (files.next()) |name| try addChild(arena, &names, path, name.*, filter);
    var directories = world.tables.directories.keyIterator();
    while (directories.next()) |name| try addChild(arena, &names, path, name.*, filter);
    return names.items;
}

/// One `NAME=VALUE` per variable that is not a placement variable.
fn keyedEntries(world: *MemoryWorld, arena: std.mem.Allocator) world_rules.ReadError![]const []const u8 {
    var names: std.ArrayList([]const u8) = .empty;
    var entries = world.tables.variables.iterator();
    while (entries.next()) |entry| {
        if (std.mem.startsWith(u8, entry.key_ptr.*, placement_prefix)) continue;
        try names.append(arena, try std.fmt.allocPrint(arena, "{s}={s}", .{ entry.key_ptr.*, entry.value_ptr.* }));
    }
    return names.items;
}

fn addChild(arena: std.mem.Allocator, names: *std.ArrayList([]const u8), directory: []const u8, path: []const u8, filter: u8) std.mem.Allocator.Error!void {
    const child = MemoryWorld.childOf(directory, path) orelse return;
    if (filter == my_files_filter and !product.isSource(child)) return;
    for (names.items) |known| if (std.mem.eql(u8, known, child)) return;
    try names.append(arena, try arena.dupe(u8, child));
}

fn variableOf(context: *anyopaque, name: []const u8) ?[]const u8 {
    return fromContext(context).tables.variables.get(name);
}

fn placementOf(_: *anyopaque, name: []const u8) bool {
    return std.mem.startsWith(u8, name, placement_prefix);
}

fn toolOf(context: *anyopaque, _: std.mem.Allocator, path: []const u8) world_rules.ReadError!?Digest {
    const world = fromContext(context);
    _ = world.counters.tools.fetchAdd(1, .monotonic);
    return world.tables.tools.get(path);
}

fn nowOf(context: *anyopaque) i64 {
    return fromContext(context).clock;
}

const vtable: World.VTable = .{ .stat = statOf, .read = readOf, .list = listOf, .variable = variableOf, .placement = placementOf, .tool = toolOf, .now = nowOf };

test "a write keeps the inode, a replace changes it, and two writes in one tick leave the same stamps" {
    var memory: MemoryWorld = .init(std.testing.allocator);
    defer memory.deinit();
    const world = memory.world();
    try memory.write("/a.txt", "one");
    const first = world.stat("/a.txt").?;
    try memory.write("/a.txt", "two");
    try std.testing.expect(first.eql(world.stat("/a.txt").?));
    memory.advance(1_000);
    try memory.write("/a.txt", "three");
    const later = world.stat("/a.txt").?;
    try std.testing.expectEqual(first.inode, later.inode);
    try std.testing.expect(!first.eql(later));
    try memory.replace("/a.txt", "four");
    try std.testing.expect(world.stat("/a.txt").?.inode != first.inode);
    try std.testing.expectEqual(@as(?Stat, null), world.stat("/missing"));
}

test "directories are the parents of files, listings name each child once, and a filter keeps what it names" {
    var memory: MemoryWorld = .init(std.testing.allocator);
    defer memory.deinit();
    const world = memory.world();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try memory.write("/src/a.selka", "");
    try memory.write("/src/b.txt", "");
    try memory.write("/src/deep/c.selka", "");
    try memory.makeDirectory("/empty");
    const all = (try world.list(arena.allocator(), "/src", 0)).?;
    try std.testing.expectEqual(@as(usize, 3), all.len);
    const mine = (try world.list(arena.allocator(), "/src", my_files_filter)).?;
    try std.testing.expectEqual(@as(usize, 1), mine.len);
    try std.testing.expectEqualStrings("a.selka", mine[0]);
    try std.testing.expectEqual(@as(usize, 0), (try world.list(arena.allocator(), "/empty", 0)).?.len);
    try std.testing.expectEqual(@as(?[]const []const u8, null), try world.list(arena.allocator(), "/nowhere", 0));
    try std.testing.expect(world.stat("/src") != null);
}

test "variables, placement names and tools answer as set, and every question is counted" {
    var memory: MemoryWorld = .init(std.testing.allocator);
    defer memory.deinit();
    const world = memory.world();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try memory.setVariable("MODE", "debug");
    try memory.setVariable("MODE", "release");
    try std.testing.expectEqualStrings("release", world.variable("MODE").?);
    memory.unsetVariable("MODE");
    try std.testing.expectEqual(@as(?[]const u8, null), world.variable("MODE"));
    try std.testing.expect(world.placement("PLACE_TMP") and !world.placement("MODE"));
    try memory.setTool("zig", @splat(3));
    try std.testing.expectEqual(@as(?Digest, @splat(3)), try world.tool(arena.allocator(), "zig"));
    try std.testing.expectEqual(@as(u64, 1), memory.count("tools"));
    _ = world.stat("/x");
    try std.testing.expectEqual(@as(u64, 1), memory.count("stats"));
    memory.resetCounters();
    try std.testing.expectEqual(@as(u64, 0), memory.count("tools"));
}
