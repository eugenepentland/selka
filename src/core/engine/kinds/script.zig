//! A kind that interprets a small graph of nodes, for the engine's tests, test vectors and measurements.
//!
//! A node is a list of reads (a file, an existence test, a listing, a variable, a tool, another node's query, or some of
//! another node's parts) and a fold of what they returned into the node's result. A node publishes parts: each is the
//! digest of one of its own pieces, under a name. The graph is the kind's data (part of its code, never of its
//! inputs); the argument of a query is the node number in decimal. Because a graph is plain data it can be written
//! in JSON, which is how the validation scenarios of the test vectors state their kinds, and because a node's result
//! is a function of its reads alone, a from-scratch evaluation is a few lines (`truth` in the tests).
const std = @import("std");
const engine = @import("../engine.zig");
const context = @import("../context.zig");
const digest_rules = @import("../digest.zig");
const Context = context.Context;
const Kind = context.Kind;
const Error = context.Error;

/// How a node folds the pieces its reads gave into its result.
pub const Fold = enum {
    /// The pieces joined with `|`.
    concat,
    /// The length of the concatenation, in decimal: different pieces of one length cut a dependent off.
    length,
    /// `even` or `odd` by the length of the concatenation.
    parity,
    /// The empty string: every change is cut off.
    empty,
};

/// A listing read: the directory and the filter number.
pub const Listing = struct { path: []const u8, filter: u8 = 0 };

/// A projection read: the parts of `node` called `names`. The piece it gives is the first eight hexadecimal digits of
/// each part's digest, joined with `,` in the order of `names`, `~` for a part the node does not publish.
pub const PartOp = struct { node: u32, names: []const []const u8 };

/// A part a node publishes: the digest of its own piece number `op`, under `name`.
pub const Expose = struct { name: []const u8, op: u32 };

/// One read of a node.
pub const Op = union(enum) {
    file: []const u8,
    exists: []const u8,
    listing: Listing,
    variable: []const u8,
    /// A placement variable: read through the context (so it is recorded), and the node's result does not depend on it.
    placement: []const u8,
    tool: []const u8,
    node: u32,
    part: PartOp,
};

/// A node: its reads, in order, how they fold, and the parts it publishes.
pub const Node = struct { ops: []const Op, fold: Fold = .concat, expose: []const Expose = &.{} };

/// The data of a script kind.
pub const Graph = struct { nodes: []const Node };

/// The name every script kind has.
pub const kind_name = "script";

/// A script kind over `graph` with code identity `identity`. The graph must outlive the kind.
pub fn kindFor(graph: *const Graph, identity: digest_rules.Digest) Kind {
    return .{ .name = kind_name, .identity = identity, .run = run, .data = graph };
}

/// The argument of the query for node `number`.
pub fn argumentFor(a: std.mem.Allocator, number: u32) std.mem.Allocator.Error![]u8 {
    return std.fmt.allocPrint(a, "{d}", .{number});
}

/// What a file read gives the node when the file is absent.
pub const absent_piece = "~";

/// What a placement variable gives a node, whatever its value.
pub const placement_piece = "p";

fn run(ctx: *Context, argument: []const u8) Error![]const u8 {
    const graph = ctx.kindData(Graph);
    const number = std.fmt.parseInt(u32, argument, 10) catch return error.Failed;
    if (number >= graph.nodes.len) return error.Failed;
    const node = graph.nodes[number];
    var text: std.ArrayList(u8) = .empty;
    const pieces = try ctx.arena.alloc([]const u8, node.ops.len);
    for (node.ops, pieces, 0..) |op, *given, at| {
        given.* = try piece(ctx, op);
        if (at != 0) try text.append(ctx.arena, '|');
        try text.appendSlice(ctx.arena, given.*);
    }
    for (node.expose) |part| {
        if (part.op >= pieces.len) return error.Failed;
        try ctx.exposePart(part.name, digest_rules.hash(pieces[part.op]));
    }
    return fold(ctx.arena, node.fold, text.items);
}

fn piece(ctx: *Context, op: Op) Error![]const u8 {
    switch (op) {
        .file => |path| return (try ctx.file(path)) orelse absent_piece,
        .exists => |path| return if (try ctx.exists(path)) "1" else "0",
        .listing => |listing| return std.mem.join(ctx.arena, ",", try ctx.listing(listing.path, listing.filter)),
        .variable => |name| return (try ctx.variable(name)) orelse absent_piece,
        .placement => |name| {
            _ = try ctx.variable(name);
            return placement_piece;
        },
        .tool => |path| return if (try ctx.tool(path)) |identity| try std.fmt.allocPrint(ctx.arena, "{s}", .{digest_rules.hex(identity)[0..8]}) else absent_piece,
        .node => |number| {
            const text = try argumentFor(ctx.arena, number);
            return (try ctx.query(ctx.frame.kind, text)).payload();
        },
        .part => |projection| {
            const text = try argumentFor(ctx.arena, projection.node);
            return partPiece(ctx.arena, try ctx.part(ctx.frame.kind, text, projection.names));
        },
    }
}

/// The piece a projection read gives for the digests it was answered with: the first eight hexadecimal digits of each,
/// `~` for a part that was not there, joined with `,`.
pub fn partPiece(a: std.mem.Allocator, answers: []const ?digest_rules.Digest) std.mem.Allocator.Error![]const u8 {
    var text: std.ArrayList(u8) = .empty;
    for (answers, 0..) |answer, at| {
        if (at != 0) try text.append(a, ',');
        if (answer) |digest| try text.appendSlice(a, digest_rules.hex(digest)[0..8]) else try text.appendSlice(a, absent_piece);
    }
    return text.items;
}

/// The result a node with this fold gives for the concatenated pieces `text`, allocated in `a`.
pub fn fold(a: std.mem.Allocator, how: Fold, text: []const u8) std.mem.Allocator.Error![]const u8 {
    return switch (how) {
        .concat => text,
        .length => std.fmt.allocPrint(a, "{d}", .{text.len}),
        .parity => if (text.len % 2 == 0) "even" else "odd",
        .empty => "",
    };
}

test "a script node reads through the context and folds what it saw" {
    const memory_world = @import("../memory_world.zig");
    var files: memory_world.MemoryWorld = .init(std.testing.allocator);
    defer files.deinit();
    try files.write("/src/a.txt", "alpha");
    try files.setVariable("MODE", "fast");
    const graph: Graph = .{ .nodes = &.{
        .{ .ops = &.{ .{ .file = "/src/a.txt" }, .{ .variable = "MODE" }, .{ .exists = "/src/none" } } },
        .{ .ops = &.{ .{ .node = 0 }, .{ .file = "/src/missing" } }, .fold = .length },
    } };
    var script = kindFor(&graph, @splat(1));
    var runner = try engine.Engine.init(std.testing.allocator, std.testing.io, files.world(), .{ .work = "/unused" });
    defer runner.deinit();
    try runner.register(&script);
    const first = try runner.query(&script, "0");
    try std.testing.expectEqualStrings("alpha|fast|0", try first.payload());
    const second = try runner.query(&script, "1");
    try std.testing.expectEqualStrings("14", try second.payload());
}
