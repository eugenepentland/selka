//! Independently owned function snapshots share immutable source generations.
const std = @import("std");
const typed = @import("typed.zig");
const source = @import("source.zig");
const copy = @import("semantic_copy.zig");
/// Reference counts are coordinator-owned; no cache mutation is concurrent.
pub const Generation = struct {
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    bytes: []const u8,
    bodies: []const source.Span,
    references: usize = 1,
    /// The returned generation starts with one temporary construction reference.
    pub fn create(allocator: std.mem.Allocator, bytes: []const u8, bodies: []const source.Span) std.mem.Allocator.Error!*Generation {
        const generation = try allocator.create(Generation);
        errdefer allocator.destroy(generation);
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        generation.* = .{ .allocator = allocator, .arena = undefined, .bytes = try arena.allocator().dupe(u8, bytes), .bodies = try arena.allocator().dupe(source.Span, bodies) };
        generation.arena = arena;
        return generation;
    }
    /// Drop one entry or construction reference and release the last source snapshot.
    pub fn deinit(self: *Generation) void {
        self.references -= 1;
        if (self.references == 0) {
            const allocator = self.allocator;
            self.arena.deinit();
            allocator.destroy(self);
        }
    }
};
/// One local checked tree owns its metadata and one source-generation reference.
pub const Entry = struct {
    arena: std.heap.ArenaAllocator,
    function: typed.Function,
    nodes: []const typed.Node,
    statements: []const typed.Statement,
    range: copy.Range,
    generation: *Generation,
    /// Clone only one changed function; unchanged cache entries transfer ownership directly.
    pub fn create(allocator: std.mem.Allocator, generation: *Generation, program: typed.Program, index: usize, range: copy.Range) error{ OutOfMemory, InternalError }!Entry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const mapper: @import("ast_copy.zig").Mapper = .{};
        const saved_function = mapper.value(arena.allocator(), typed.Function, program.functions[index]) catch |err| return classify(err);
        const nodes = mapper.value(arena.allocator(), []const typed.Node, program.nodes[range.nodes.start..range.nodes.end]) catch |err| return classify(err);
        const statements = mapper.value(arena.allocator(), []const typed.Statement, program.statements[range.statements.start..range.statements.end]) catch |err| return classify(err);
        generation.references += 1;
        return .{ .arena = arena, .function = saved_function, .nodes = nodes, .statements = statements, .range = range, .generation = generation };
    }
    /// Release this function tree without invalidating other generation users.
    pub fn deinit(self: *Entry) void {
        self.arena.deinit();
        self.generation.deinit();
    }
};
fn classify(err: anyerror) error{ OutOfMemory, InternalError } {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
/// Count each source generation once, plus every independently owned tree arena.
pub fn retained(entries: []const Entry) usize {
    var bytes: usize = entries.len * @sizeOf(Entry);
    for (entries, 0..) |entry, i| {
        bytes += entry.arena.queryCapacity();
        var first = true;
        for (entries[0..i]) |previous| if (previous.generation == entry.generation) {
            first = false;
            break;
        };
        if (first) bytes += entry.generation.arena.queryCapacity() + @sizeOf(Generation);
    }
    return bytes;
}
