//! One bounded successful project-check verdict, keyed by freshly loaded sources.
const std = @import("std");
const project = @import("project.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
/// Cumulative outcomes; retained bytes count the owned entry arena capacity.
pub const Statistics = struct { hits: usize = 0, misses: usize = 0, stored: usize = 0, bypassed: usize = 0, retained_bytes: usize = 0 };
const Input = struct { name: []const u8, path: []const u8, bytes: []const u8 };
const Entry = struct { arena: std.heap.ArenaAllocator, inputs: []const Input, warnings: []const u8 };
/// Caller-serialized in-memory reuse under one running compiler implementation.
/// Only successful complete checks may be remembered; failed requests stay fresh.
pub const Cache = struct {
    allocator: std.mem.Allocator,
    max_bytes: usize,
    entry: ?Entry = null,
    statistics: Statistics = .{},
    /// Create an empty cache; zero capacity disables retention.
    pub fn init(allocator: std.mem.Allocator, max_bytes: usize) Cache {
        return .{ .allocator = allocator, .max_bytes = max_bytes };
    }
    /// Release retained source and diagnostic text.
    pub fn deinit(self: *Cache) void {
        self.clear();
    }
    /// Drop the last successful verdict without resetting cumulative observations.
    pub fn clear(self: *Cache) void {
        if (self.entry) |*entry| entry.arena.deinit();
        self.entry = null;
        self.statistics.retained_bytes = 0;
    }
    /// Borrow saved warning text until clear/remember/deinit, or require fresh checking.
    pub fn lookup(self: *Cache, loaded: *const project.Project) ?[]const u8 {
        if (loaded.progress.complete and loaded.problem == null) {
            if (self.entry) |entry| {
                if (matches(entry.inputs, loaded.modules.items)) {
                    self.statistics.hits += 1;
                    return entry.warnings;
                }
            }
        }
        self.statistics.misses += 1;
        return null;
    }
    /// Snapshot a successful check and its rendered warnings. Old storage survives OOM.
    pub fn remember(self: *Cache, loaded: *const project.Project, src: source.Source, diagnostics: []const diagnostic.Diagnostic) error{ OutOfMemory, InvalidVerdict }!void {
        if (!loaded.progress.complete or loaded.problem != null) return error.InvalidVerdict;
        for (diagnostics) |item| if (item.severity == .err) return error.InvalidVerdict;
        if (self.max_bytes == 0 or loaded.counts.bytes > self.max_bytes) {
            self.statistics.bypassed += 1;
            return;
        }
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        errdefer arena.deinit();
        const allocator = arena.allocator();
        const inputs = try allocator.alloc(Input, loaded.modules.items.len);
        for (inputs, loaded.modules.items) |*input, module| input.* = .{
            .name = try allocator.dupe(u8, module.name),
            .path = try allocator.dupe(u8, module.src.path),
            .bytes = try allocator.dupe(u8, module.src.bytes),
        };
        var warnings: std.Io.Writer.Allocating = .init(allocator);
        for (diagnostics) |item| {
            const text = try item.render(allocator, src);
            warnings.writer.writeAll(text) catch return error.OutOfMemory;
        }
        const text = try warnings.toOwnedSlice();
        const bytes = arena.queryCapacity();
        if (bytes > self.max_bytes) {
            arena.deinit();
            self.statistics.bypassed += 1;
            return;
        }
        self.clear();
        self.entry = .{ .arena = arena, .inputs = inputs, .warnings = text };
        self.statistics.retained_bytes = bytes;
        self.statistics.stored += 1;
    }
};
fn matches(inputs: []const Input, modules: []const project.Module) bool {
    if (inputs.len != modules.len) return false;
    for (inputs, modules) |input, module| {
        if (!std.mem.eql(u8, input.name, module.name)) return false;
        if (!std.mem.eql(u8, input.path, module.src.path)) return false;
        if (!std.mem.eql(u8, input.bytes, module.src.bytes)) return false;
    }
    return true;
}
