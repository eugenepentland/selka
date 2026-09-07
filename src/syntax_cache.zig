//! Bounded in-memory reuse of exact module syntax; semantic decisions are never cached.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const copy = @import("ast_copy.zig");
/// Maximum retained parse arenas and entry count; zero disables retention.
pub const Limits = struct { max_entries: usize = 256, max_bytes: usize = 16 * 1024 * 1024 };
/// Completed lookup/copy outcomes and retained arena capacity, excluding index storage.
pub const Statistics = struct {
    hits: usize = 0,
    misses: usize = 0,
    stored: usize = 0,
    evicted: usize = 0,
    bypassed: usize = 0,
    retained_bytes: usize = 0,
};
const Entry = struct {
    arena: std.heap.ArenaAllocator,
    src: source.Source,
    body_start: usize,
    syntax: ast.Program,
    fn init(allocator: std.mem.Allocator, src: source.Source, start: usize, syntax: ast.Program) error{ OutOfMemory, InternalError }!Entry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const owned_source = try source.Source.init(arena.allocator(), src.path, src.bytes);
        const owned_syntax = try copy.clone(arena.allocator(), syntax);
        return .{ .arena = arena, .src = owned_source, .body_start = start, .syntax = owned_syntax };
    }
    fn deinit(self: *Entry) void {
        self.arena.deinit();
    }
};
/// Owns reusable syntax independently of projects. Returned copies belong to caller arenas.
/// Callers serialize access; clearing or evicting entries cannot invalidate returned syntax.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    entries: std.ArrayList(Entry) = .empty,
    limits: Limits,
    statistics: Statistics = .{},
    /// Create an empty cache with explicit retention limits; release it with deinit.
    pub fn init(allocator: std.mem.Allocator, limits: Limits) Cache {
        return .{ .allocator = allocator, .limits = limits };
    }
    /// Release every retained arena and the entry index.
    pub fn deinit(self: *Cache) void {
        self.clear();
        self.entries.deinit(self.allocator);
    }
    /// Drop retained syntax without resetting cumulative observations.
    pub fn clear(self: *Cache) void {
        for (self.entries.items) |*entry| entry.deinit();
        self.entries.clearRetainingCapacity();
        self.statistics.retained_bytes = 0;
    }
    /// Deep-copy exact source/path/header matches; misses require fresh lexing and parsing.
    pub fn lookup(self: *Cache, allocator: std.mem.Allocator, src: source.Source, start: usize) error{ OutOfMemory, InternalError }!?ast.Program {
        for (self.entries.items) |entry| {
            if (entry.body_start != start) continue;
            if (!std.mem.eql(u8, entry.src.path, src.path)) continue;
            if (!std.mem.eql(u8, entry.src.bytes, src.bytes)) continue;
            const syntax = try copy.clone(allocator, entry.syntax);
            self.statistics.hits += 1;
            return syntax;
        }
        self.statistics.misses += 1;
        return null;
    }
    /// Retain a successful parse using deterministic oldest-insertion eviction.
    /// Oversized entries are bypassed; allocation failures remain explicit host failures.
    pub fn remember(self: *Cache, src: source.Source, start: usize, syntax: ast.Program) error{ OutOfMemory, InternalError }!void {
        if (self.limits.max_entries == 0 or src.bytes.len > self.limits.max_bytes) {
            self.statistics.bypassed += 1;
            return;
        }
        var entry = try Entry.init(self.allocator, src, start, syntax);
        errdefer entry.deinit();
        const bytes = entry.arena.queryCapacity();
        if (bytes > self.limits.max_bytes) {
            entry.deinit();
            self.statistics.bypassed += 1;
            return;
        }
        while (self.entries.items.len >= self.limits.max_entries or bytes > self.limits.max_bytes - self.statistics.retained_bytes) {
            var oldest = self.entries.orderedRemove(0);
            self.statistics.retained_bytes -= oldest.arena.queryCapacity();
            oldest.deinit();
            self.statistics.evicted += 1;
        }
        try self.entries.append(self.allocator, entry);
        self.statistics.retained_bytes += bytes;
        self.statistics.stored += 1;
    }
};
