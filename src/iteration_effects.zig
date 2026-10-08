//! Find writes in real and generated iteration bodies by following syntax IDs.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const typed = @import("typed.zig");
const operations = @import("buffer_operations.zig");
const loop_rebinding = @import("loop_rebinding.zig");
const Error = @import("diagnostic.zig").Error;

/// A statement loop body or a comprehension's produced expression.
pub const Body = union(enum) { statement: ast.StatementId, expression: ast.NodeId };

/// Whether a body replaces the root syntactically. Expressions cannot assign it.
pub fn rebinds(comptime Checker: type, checker: *Checker, body: Body, name: []const u8, immutable: bool) Error!bool {
    return switch (body) {
        .statement => |id| loop_rebinding.rebinds(checker.allocator, .{ .program = checker.syntax, .src = checker.src }, id, name, immutable),
        .expression => false,
    };
}

/// Whether any reachable expression or statement may write the rooted place.
pub fn changes(comptime Checker: type, checker: *Checker, body: Body, name: []const u8) Error!bool {
    if (body == .statement and try loop_rebinding.assigns(checker.allocator, .{ .program = checker.syntax, .src = checker.src }, body.statement, name)) return true;
    var walk: Walk = .{ .allocator = checker.allocator };
    defer walk.work.deinit(checker.allocator);
    try walk.append(body);
    while (walk.work.pop()) |item| switch (item) {
        .statement => |id| try walk.append(checker.syntax.statements.items[@backingInt(id)].data),
        .expression => |id| {
            const node = checker.syntax.nodes.items[@backingInt(id)];
            if (nodeChanges(Checker, checker, node, name)) return true;
            try walk.append(node.data);
        },
    };
    return false;
}

fn nodeChanges(comptime Checker: type, checker: *Checker, node: ast.Node, name: []const u8) bool {
    const target: ?ast.NodeId = switch (node.data) {
        .mut_argument => |value| value,
        .list_operation => |op| if (writes(op.kind)) op.base else null,
        .method_call => |call| if (methodChanges(Checker, checker, call.base, call.name)) call.base else null,
        .call => |call| if (call.owner) |owner| blk: {
            if (!std.mem.eql(u8, checker.src.text(owner), name)) break :blk null;
            const slot = checker.active.get(name) orelse break :blk null;
            return receiverChanges(Checker, checker, checker.locals.items[@backingInt(slot)].ty, call.name);
        } else null,
        .buffer_operation => |op| return writes(op.kind) and std.mem.eql(u8, checker.src.text(op.owner), name),
        else => null,
    };
    return if (target) |value| loop_rebinding.rootedAt(.{ .program = checker.syntax, .src = checker.src }, value, name) else false;
}

fn methodChanges(comptime Checker: type, checker: *Checker, base: ast.NodeId, name: source.Span) bool {
    const resolved = checker.resolved[@backingInt(base)] orelse return true;
    return receiverChanges(Checker, checker, checker.nodes.items[@backingInt(resolved)].ty, name);
}

fn receiverChanges(comptime Checker: type, checker: *Checker, ty: typed.Type, name: source.Span) bool {
    if (!ty.isAggregate() or !checker.catalog.records[ty.recordIndex()].isCollection()) return true;
    const kind = operations.method(checker.src.text(name)) orelse return true;
    return writes(kind);
}

fn writes(kind: operations.Kind) bool {
    return kind.writesReceiver() or kind == .set_add or kind == .set_discard;
}

// Generated gather statements have spans for just their filter or clause.
// Follow all syntax IDs, including produced values before the `for` spelling.
const Walk = struct {
    allocator: std.mem.Allocator,
    work: std.ArrayList(Body) = .empty,

    fn append(self: *Walk, input: anytype) std.mem.Allocator.Error!void {
        const T = @TypeOf(input);
        if (T == ast.NodeId) return self.work.append(self.allocator, .{ .expression = input });
        if (T == ast.StatementId) return self.work.append(self.allocator, .{ .statement = input });
        if (T == source.Span) return;
        switch (@typeInfo(T)) {
            .@"struct" => inline for (@typeInfo(T).@"struct".field_names) |name| try self.append(@field(input, name)),
            .@"union" => switch (input) {
                inline else => |value| try self.append(value),
            },
            .optional => if (input) |value| try self.append(value),
            .pointer => |pointer| if (pointer.size == .slice and pointer.child != u8) {
                for (input) |value| try self.append(value);
            },
            else => {},
        }
    }
};
