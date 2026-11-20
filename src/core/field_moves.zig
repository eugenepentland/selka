//! FR91: several fields moved out of one owned record in one statement (`total(own p.lo, own p.hi)`, rule B8).
//!
//! One `own p.field` consumes the whole record `p` and destroys its other fields there. A statement may move several fields of
//! one record: the record is consumed once, at the first move the statement evaluates, and the fields no move names are
//! destroyed there. The ownership checker (`single_owner.zig`) and the lowering (`build.zig`) find the same groups here, so the
//! lowering opens the record (`record_open`, then one owned read of each field) exactly where the checker consumed it.
//!
//! A group is the moves a statement evaluates unconditionally: the walk goes into call arguments, constructor fields, `try`,
//! list literals, conversions, arithmetic, `print` arguments and f-string holes, and stops at a short-circuit operand, a
//! conditional, a match, a block and a closure. So every move of a group runs after the first one on every path that reaches it, and a move under a condition is
//! a move of its own, refused when the record was already consumed (as before FR91). Each move of a group leaves the record
//! by a different field: the same field twice (`own p.a.b` beside `own p.a.c` included) makes no group.
const std = @import("std");
const typed = @import("selka").typed;
const Span = @import("selka").source.Span;

/// One move of a group: the `own` field node, the root local's node and slot, and the field of the root the move leaves by.
pub const Move = struct { node: typed.NodeId, local: typed.NodeId, root: usize, field: usize };

/// The groups of one statement: the moves, two or more for each root, of different fields.
pub const Groups = struct {
    moves: []const Move = &.{},
    /// FR91B: every `own` field move of the statement out of a local that two or more of them leave, whether or not the record
    /// is one a field may leave (a borrowed parameter's moves are here and not in `moves`): what the writer meant as a group.
    attempts: []const Move = &.{},

    /// The move of `attempts` that `node` is, if it is one.
    pub fn attempt(self: Groups, node: typed.NodeId) ?Move {
        for (self.attempts) |move| if (move.node == node) return move;
        return null;
    }

    /// The group move `node` is, if it is one.
    pub fn find(self: Groups, node: typed.NodeId) ?Move {
        for (self.moves) |move| if (move.node == node) return move;
        return null;
    }

    /// Whether `local` is the root node of a move of the group of `root`: the place the first move consumed it.
    pub fn consumedAt(self: Groups, program: typed.Program, root: usize, span: Span) bool {
        for (self.moves) |move| {
            if (move.root != root) continue;
            const at = program.nodes[@backingInt(move.local)].span;
            if (at.start == span.start and at.end == span.end) return true;
        }
        return false;
    }

    /// The root node's span of a move of the group of `root` other than the one at `span`, when the group consumed the record
    /// at `span`: where a second move would have been refused before FR91.
    pub fn otherMove(self: Groups, program: typed.Program, root: usize, span: Span) ?Span {
        if (!self.consumedAt(program, root, span)) return null;
        for (self.moves) |move| {
            if (move.root != root) continue;
            const at = program.nodes[@backingInt(move.local)].span;
            if (at.start != span.start or at.end != span.end) return at;
        }
        return null;
    }
};

/// The groups of the value statement `id` evaluates, of the moves `carries(context, node)` accepts (the checker's and the
/// lowering's own test that a field node moves out of its record). A statement of no value, or with no group, has none.
pub fn of(arena: std.mem.Allocator, program: typed.Program, id: typed.StatementId, context: anytype, comptime carries: anytype) !Groups {
    const value = switch (program.statements[@backingInt(id)].data) {
        .initialize, .assign => |store| store.value,
        .discard, .ret => |node| node,
        else => return .{},
    };
    var found: std.ArrayList(Move) = .empty;
    try walk(arena, program, value, &found);
    var attempts: std.ArrayList(Move) = .empty;
    for (found.items) |move| {
        var count: usize = 0;
        for (found.items) |other| count += @intFromBool(other.root == move.root);
        if (count >= 2) try attempts.append(arena, move);
    }
    var kept: std.ArrayList(Move) = .empty;
    for (found.items) |move| if (try carries(context, move.node)) try kept.append(arena, move);
    var groups: std.ArrayList(Move) = .empty;
    for (kept.items) |move| {
        var count: usize = 0;
        for (kept.items) |other| count += @intFromBool(other.root == move.root);
        if (count < 2) continue;
        // One field twice: no group for the record, so the second move is refused as before.
        if (!repeatsField(kept.items, move.root)) try groups.append(arena, move);
    }
    return .{ .moves = groups.items, .attempts = attempts.items };
}

/// Whether two of `moves` out of `root` leave it by the same field.
fn repeatsField(moves: []const Move, root: usize) bool {
    for (moves, 0..) |move, at| {
        if (move.root != root) continue;
        for (moves[at + 1 ..]) |later| {
            if (later.root == root and later.field == move.field) return true;
        }
    }
    return false;
}

/// Collect the `own` field moves out of a named local that `id` evaluates unconditionally.
fn walk(arena: std.mem.Allocator, program: typed.Program, id: typed.NodeId, found: *std.ArrayList(Move)) error{OutOfMemory}!void {
    const node = program.nodes[@backingInt(id)];
    if (node.own and node.data == .field) if (rooted(program, id)) |move| {
        try found.append(arena, move);
        return;
    };
    switch (node.data) {
        .call => |call| for (call.arguments) |argument| try walk(arena, program, argument, found),
        .invoke => |invoke| {
            try walk(arena, program, invoke.callee, found);
            for (invoke.arguments) |argument| try walk(arena, program, argument, found);
        },
        .record => |fields| for (fields) |field| try walk(arena, program, field.value, found),
        .array => |items| for (items) |item| try walk(arena, program, item, found),
        .propagate => |propagate| try walk(arena, program, propagate.value, found),
        .variant => |variant| if (variant.value) |value| try walk(arena, program, value, found),
        .wrap, .cast => |value| try walk(arena, program, value, found),
        .field => |field| try walk(arena, program, field.base, found),
        .unary => |unary| try walk(arena, program, unary.operand, found),
        .print => |print| for (print.arguments) |argument| try walk(arena, program, argument, found),
        .format => |format| for (format.pieces) |piece| switch (piece) {
            .hole => |hole| try walk(arena, program, hole.value, found),
            .literal => {},
        },
        .binary => |binary| if (binary.op != .logical_and and binary.op != .logical_or) {
            try walk(arena, program, binary.left, found);
            try walk(arena, program, binary.right, found);
        },
        else => {},
    }
}

/// The move `id` makes when its field path starts at a local: the local and the field of it the path leaves by.
fn rooted(program: typed.Program, id: typed.NodeId) ?Move {
    var at = id;
    while (true) {
        const field = program.nodes[@backingInt(at)].data.field;
        const base = program.nodes[@backingInt(field.base)];
        switch (base.data) {
            .local => |slot| return .{ .node = id, .local = field.base, .root = @backingInt(slot), .field = field.index },
            .field => at = field.base,
            else => return null,
        }
    }
}
