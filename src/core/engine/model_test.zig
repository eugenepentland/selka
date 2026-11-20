//! What a script graph's results are, computed without the engine, and what the engine's counts must then be.
//!
//! `truth` evaluates a node from scratch against a world: no records, no reads, just the meaning of the ops. `Model`
//! is the engine's validation rule written the plain way over the same graph: it remembers what each node saw the last
//! time it ran, walks a node's ops in order and stops at the first that differs, and counts the nodes it had to run,
//! the nodes it could serve and the dependencies it cut off. The property test checks the engine against both.
const std = @import("std");
const script = @import("kinds/script.zig");
const world_rules = @import("world.zig");
const digest_rules = @import("digest.zig");

/// The piece an op gives, read straight from the world. A node op is given by `deps`, which answers dependencies.
fn pieceOf(a: std.mem.Allocator, world: world_rules.World, op: script.Op) world_rules.ReadError![]const u8 {
    switch (op) {
        .file => |path| return (try world.read(a, path, 1 << 20)) orelse script.absent_piece,
        .exists => |path| return if (world.stat(path) != null) "1" else "0",
        .listing => |listing| {
            const names = (try world.list(a, listing.path, listing.filter)) orelse &.{};
            const sorted = try a.dupe([]const u8, names);
            std.mem.sort([]const u8, sorted, {}, nameBefore);
            return std.mem.join(a, ",", sorted);
        },
        .variable => |name| return if (world.variable(name)) |value| try a.dupe(u8, value) else script.absent_piece,
        .placement => return script.placement_piece,
        .tool => |path| return if (try world.tool(a, path)) |identity| try std.fmt.allocPrint(a, "{s}", .{digest_rules.hex(identity)[0..8]}) else script.absent_piece,
        .node, .part => return error.ReadFailed,
    }
}

fn nameBefore(_: void, left: []const u8, right: []const u8) bool {
    return std.mem.lessThan(u8, left, right);
}

/// The text a projection read of `projection` gives when `node`'s pieces are `pieces`: the digest of each named part that
/// `graph.nodes[projection.node]` publishes, whatever else it holds.
fn partText(a: std.mem.Allocator, graph: script.Graph, projection: script.PartOp, pieces: []const []const u8) std.mem.Allocator.Error![]const u8 {
    const answers = try a.alloc(?digest_rules.Digest, projection.names.len);
    for (projection.names, answers) |name, *answer| {
        answer.* = null;
        for (graph.nodes[projection.node].expose) |part| {
            if (std.mem.eql(u8, part.name, name)) answer.* = digest_rules.hash(pieces[part.op]);
        }
    }
    return script.partPiece(a, answers);
}

/// The pieces of `node` evaluated from scratch, one per op. `known` holds the pieces of the nodes evaluated so far in
/// this evaluation, so a node several others read is evaluated once.
fn truthPieces(a: std.mem.Allocator, graph: script.Graph, world: world_rules.World, node: u32, known: []?[]const []const u8) world_rules.ReadError![]const []const u8 {
    if (known[node]) |done| return done;
    const ops = graph.nodes[node].ops;
    const pieces = try a.alloc([]const u8, ops.len);
    for (ops, pieces) |op, *piece| {
        piece.* = switch (op) {
            .node => |dependency| try script.fold(a, graph.nodes[dependency].fold, try std.mem.join(a, "|", try truthPieces(a, graph, world, dependency, known))),
            .part => |projection| try partText(a, graph, projection, try truthPieces(a, graph, world, projection.node, known)),
            else => try pieceOf(a, world, op),
        };
    }
    known[node] = pieces;
    return pieces;
}

/// The result of `node` evaluated from scratch.
pub fn truth(a: std.mem.Allocator, graph: script.Graph, world: world_rules.World, node: u32) world_rules.ReadError![]const u8 {
    const known = try a.alloc(?[]const []const u8, graph.nodes.len);
    @memset(known, null);
    const pieces = try truthPieces(a, graph, world, node, known);
    return script.fold(a, graph.nodes[node].fold, try std.mem.join(a, "|", pieces));
}

/// What one batch of queries did, by the rules: nodes run, nodes served from a record, dependencies cut off.
pub const Tally = struct { recomputed: u64 = 0, served: u64 = 0, cutoffs: u64 = 0 };

/// One answer: the result, the pieces it was made of, and whether answering ran the node in this process.
const Answer = struct { text: []const u8, pieces: []const []const u8, fresh: bool };

/// What a node saw the last time it ran: the piece each op gave, and the result.
const Seen = struct { pieces: []const []const u8, result: []const u8 };

/// The rules of validation over a graph.
pub const Model = struct {
    graph: script.Graph,
    world: world_rules.World,
    arena: std.mem.Allocator,
    recorded: []?Seen,
    /// Answered in this process (the memo), by node.
    memo: []?Seen,
    tally: Tally = .{},

    /// A model whose nodes have never run.
    pub fn init(arena: std.mem.Allocator, graph: script.Graph, world: world_rules.World) std.mem.Allocator.Error!Model {
        const recorded = try arena.alloc(?Seen, graph.nodes.len);
        errdefer arena.free(recorded);
        @memset(recorded, null);
        const memo = try arena.alloc(?Seen, graph.nodes.len);
        @memset(memo, null);
        return .{ .graph = graph, .world = world, .arena = arena, .recorded = recorded, .memo = memo };
    }

    /// A new process: the memo is gone, the records stay.
    pub fn restart(self: *Model) void {
        @memset(self.memo, null);
        self.tally = .{};
    }

    /// The record of `node` is gone (a retention sweep, a torn file).
    pub fn forget(self: *Model, node: u32) void {
        self.recorded[node] = null;
    }

    /// Answer `node`, counting what it takes.
    pub fn answer(self: *Model, node: u32) world_rules.ReadError![]const u8 {
        return (try self.resolve(node)).text;
    }

    fn resolve(self: *Model, node: u32) world_rules.ReadError!Answer {
        if (self.memo[node]) |known| return .{ .text = known.result, .pieces = known.pieces, .fresh = false };
        if (self.recorded[node]) |seen| {
            if (try self.stillHolds(node, seen)) {
                self.tally.served += 1;
                self.memo[node] = seen;
                return .{ .text = seen.result, .pieces = seen.pieces, .fresh = false };
            }
        }
        const ran = try self.run(node);
        self.tally.recomputed += 1;
        self.memo[node] = ran;
        self.recorded[node] = ran;
        return .{ .text = ran.result, .pieces = ran.pieces, .fresh = true };
    }

    /// Whether every op of `node` gives what it gave, in order, stopping at the first that does not.
    fn stillHolds(self: *Model, node: u32, seen: Seen) world_rules.ReadError!bool {
        for (self.graph.nodes[node].ops, seen.pieces) |op, was| {
            switch (op) {
                .node => |dependency| {
                    // A dependency is asked for by its key alone, so one without a record cannot be recomputed here.
                    if (self.memo[dependency] == null and self.recorded[dependency] == null) return false;
                    const now = try self.resolve(dependency);
                    if (!std.mem.eql(u8, now.text, was)) return false;
                    if (now.fresh) self.tally.cutoffs += 1;
                },
                .part => |projection| {
                    if (self.memo[projection.node] == null and self.recorded[projection.node] == null) return false;
                    const now = try self.resolve(projection.node);
                    if (!std.mem.eql(u8, try partText(self.arena, self.graph, projection, now.pieces), was)) return false;
                    if (now.fresh) self.tally.cutoffs += 1;
                },
                else => if (!std.mem.eql(u8, try pieceOf(self.arena, self.world, op), was)) return false,
            }
        }
        return true;
    }

    fn run(self: *Model, node: u32) world_rules.ReadError!Seen {
        const ops = self.graph.nodes[node].ops;
        const pieces = try self.arena.alloc([]const u8, ops.len);
        var text: std.ArrayList(u8) = .empty;
        for (ops, pieces, 0..) |op, *piece, at| {
            piece.* = switch (op) {
                .node => |dependency| (try self.resolve(dependency)).text,
                .part => |projection| try partText(self.arena, self.graph, projection, (try self.resolve(projection.node)).pieces),
                else => try pieceOf(self.arena, self.world, op),
            };
            if (at != 0) try text.append(self.arena, '|');
            try text.appendSlice(self.arena, piece.*);
        }
        return .{ .pieces = pieces, .result = try script.fold(self.arena, self.graph.nodes[node].fold, text.items) };
    }
};

test "a model serves what it saw, reruns what changed, and cuts a dependent off when a result did not change" {
    const memory_world = @import("memory_world.zig");
    var files: memory_world.MemoryWorld = .init(std.testing.allocator);
    defer files.deinit();
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    try files.write("/a", "xx");
    const graph: script.Graph = .{ .nodes = &.{
        .{ .ops = &.{.{ .file = "/a" }}, .fold = .length },
        .{ .ops = &.{ .{ .node = 0 }, .{ .exists = "/b" } } },
    } };
    var model = try Model.init(arena.allocator(), graph, files.world());
    try std.testing.expectEqualStrings("2|0", try model.answer(1));
    try std.testing.expectEqual(@as(u64, 2), model.tally.recomputed);
    model.restart();
    try std.testing.expectEqualStrings("2|0", try model.answer(1));
    try std.testing.expectEqual(@as(u64, 2), model.tally.served);
    model.restart();
    try files.write("/a", "yy");
    try std.testing.expectEqualStrings("2|0", try model.answer(1));
    try std.testing.expectEqual(@as(u64, 1), model.tally.recomputed);
    try std.testing.expectEqual(@as(u64, 1), model.tally.cutoffs);
    try std.testing.expectEqual(@as(u64, 1), model.tally.served);
    try std.testing.expectEqualStrings("2|0", try truth(arena.allocator(), graph, files.world(), 1));
}
