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
    declarations: []const source.Span,
    references: usize = 1,
    /// The returned generation starts with one temporary construction reference.
    pub fn create(allocator: std.mem.Allocator, bytes: []const u8, bodies: []const source.Span, declarations: []const source.Span) std.mem.Allocator.Error!*Generation {
        const generation = try allocator.create(Generation);
        errdefer allocator.destroy(generation);
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        generation.* = .{
            .allocator = allocator,
            .arena = undefined,
            .bytes = try arena.allocator().dupe(u8, bytes),
            .bodies = try arena.allocator().dupe(source.Span, bodies),
            .declarations = try arena.allocator().dupe(source.Span, declarations),
        };
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
/// Per-entry arena, relocation range and shared source generation.
const Storage = struct {
    arena: std.heap.ArenaAllocator,
    range: copy.Range,
    generation: *Generation,
};
/// Declaration identity/interface and the exact full source span. Bundled as
/// `Entry.create` input only; the entry itself exposes each field directly.
pub const Metadata = struct { identity: []const u8, interface_sha256: ?[]const u8, declaration: source.Span };
/// One local checked tree owns its metadata and one source-generation reference.
pub const Entry = struct {
    function: typed.Function,
    nodes: []const typed.Node,
    statements: []const typed.Statement,
    storage: Storage,
    /// Stable identity and semantic interface the lookup gate matched.
    identity: []const u8,
    interface_sha256: ?[]const u8,
    /// Full declaration span (header through body end) inside `generation.bytes`.
    declaration: source.Span,
    /// Clone only one changed function; unchanged cache entries transfer ownership directly.
    pub fn create(
        allocator: std.mem.Allocator,
        generation: *Generation,
        program: typed.Program,
        index: usize,
        range: copy.Range,
        metadata: Metadata,
    ) error{ OutOfMemory, InternalError }!Entry {
        var arena = std.heap.ArenaAllocator.init(allocator);
        errdefer arena.deinit();
        const saved_identity = arena.allocator().dupe(u8, metadata.identity) catch |err| return classify(err);
        const saved_interface = if (metadata.interface_sha256) |interface| arena.allocator().dupe(u8, interface) catch |err| return classify(err) else null;
        const mapper: @import("ast_copy.zig").Mapper = .{};
        const saved_function = mapper.value(arena.allocator(), typed.Function, program.functions[index]) catch |err| return classify(err);
        const nodes = mapper.value(arena.allocator(), []const typed.Node, program.nodes[range.nodes.start..range.nodes.end]) catch |err| return classify(err);
        const statements = mapper.value(arena.allocator(), []const typed.Statement, program.statements[range.statements.start..range.statements.end]) catch |err| return classify(err);
        generation.references += 1;
        return .{
            .function = saved_function,
            .nodes = nodes,
            .statements = statements,
            .storage = .{ .arena = arena, .range = range, .generation = generation },
            .identity = saved_identity,
            .interface_sha256 = saved_interface,
            .declaration = metadata.declaration,
        };
    }
    /// Release this function tree without invalidating other generation users.
    pub fn deinit(self: *Entry) void {
        self.storage.arena.deinit();
        self.storage.generation.deinit();
    }
};
fn classify(err: anyerror) error{ OutOfMemory, InternalError } {
    return if (err == error.OutOfMemory) error.OutOfMemory else error.InternalError;
}
/// Count each source generation once, plus every independently owned tree arena.
pub fn retained(entries: []const Entry) usize {
    var bytes: usize = entries.len * @sizeOf(Entry);
    for (entries, 0..) |entry, i| {
        bytes += entry.storage.arena.queryCapacity();
        var first = true;
        for (entries[0..i]) |previous| if (previous.storage.generation == entry.storage.generation) {
            first = false;
            break;
        };
        if (first) bytes += entry.storage.generation.arena.queryCapacity() + @sizeOf(Generation);
    }
    return bytes;
}
