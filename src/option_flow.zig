//! Local Option facts and lowering through existing exhaustive variant dispatch.
const std = @import("std");
const ast = @import("ast.zig");
const typed = @import("typed.zig");
const source = @import("source.zig");
const diagnostic = @import("diagnostic.zig");
const prelude = @import("prelude.zig");
const collections = @import("collection_lower.zig");
/// Source tables used to derive facts about local value bindings.
pub const Context = struct { program: ast.Program, src: source.Source };
/// Truth value known on one outgoing edge of a condition.
pub const Guard = struct { condition: ast.NodeId, truth: bool };
/// Active local names in either the concrete or symbolic checker.
pub const Active = union(enum) {
    concrete: *const std.StringHashMapUnmanaged(typed.LocalId),
    symbolic: *const std.StringHashMapUnmanaged(usize),
    fn get(self: Active, name: []const u8) ?usize {
        return switch (self) {
            .concrete => |names| @backingInt(names.get(name) orelse return null),
            .symbolic => |names| names.get(name),
        };
    }
};
const Walk = struct { context: Context, active: Active, remaining: usize = 1024 };
/// Known-present local slots, with path snapshots and conservative loop invalidation.
pub const State = struct {
    present: std.ArrayList(usize) = .empty,
    /// Whether every continuing path established presence.
    pub fn has(self: State, slot: usize) bool {
        return std.mem.indexOfScalar(usize, self.present.items, slot) != null;
    }
    /// Remove the fact about a replaced or out-of-scope value.
    pub fn forget(self: *State, slot: usize) void {
        if (std.mem.indexOfScalar(usize, self.present.items, slot)) |at| _ = self.present.swapRemove(at);
    }
    /// Reset facts at a function boundary.
    pub fn clear(self: *State) void {
        self.present.clearRetainingCapacity();
    }
    /// Copy facts before checking another control-flow path.
    pub fn snapshot(self: State, allocator: std.mem.Allocator) std.mem.Allocator.Error![]const usize {
        return allocator.dupe(usize, self.present.items);
    }
    /// Restore this state's own snapshot without reducing retained capacity.
    pub fn restore(self: *State, saved: []const usize) void {
        self.present.clearRetainingCapacity();
        self.present.appendSliceAssumeCapacity(saved);
    }
    /// Keep facts shared by both continuing paths.
    pub fn intersect(self: *State, saved: []const usize) void {
        var at = self.present.items.len;
        while (at > 0) {
            at -= 1;
            if (std.mem.indexOfScalar(usize, saved, self.present.items[at]) == null) _ = self.present.swapRemove(at);
        }
    }
    /// Remove scoped bindings before their indices can be reused.
    pub fn endScope(self: *State, first: usize) void {
        var at = self.present.items.len;
        while (at > 0) {
            at -= 1;
            if (self.present.items[at] >= first) _ = self.present.swapRemove(at);
        }
    }
    /// Derive facts from None guards and short-circuit conditions, never heap fields.
    pub fn assume(self: *State, allocator: std.mem.Allocator, context: Context, active: Active, guard: Guard) diagnostic.Error!void {
        var walk: Walk = .{ .context = context, .active = active };
        return self.assumeDepth(allocator, &walk, guard, 0);
    }
    fn assumeDepth(self: *State, allocator: std.mem.Allocator, walk: *Walk, guard: Guard, depth: usize) diagnostic.Error!void {
        // Alternative Boolean paths revisit subtrees; bound total work as well as depth.
        if (depth == 128 or walk.remaining == 0) return;
        walk.remaining -= 1;
        const context = walk.context;
        const active = walk.active;
        const node = context.program.nodes.items[@backingInt(guard.condition)];
        switch (node.data) {
            .unary => |unary| {
                if (unary.op == .not) return self.assumeDepth(allocator, walk, .{ .condition = unary.operand, .truth = !guard.truth }, depth + 1);
                if (unary.op != .is_none) return;
                const operand = context.program.nodes.items[@backingInt(unary.operand)];
                if (operand.data != .name) return;
                const slot = active.get(context.src.text(operand.data.name)) orelse return;
                if (guard.truth) self.forget(slot) else if (!self.has(slot)) try self.present.append(allocator, slot);
            },
            .binary => |binary| {
                if (binary.op != .logical_and and binary.op != .logical_or) return;
                if ((binary.op == .logical_and) == guard.truth) {
                    try self.assumeDepth(allocator, walk, .{ .condition = binary.left, .truth = guard.truth }, depth + 1);
                    try self.assumeDepth(allocator, walk, .{ .condition = binary.right, .truth = guard.truth }, depth + 1);
                } else {
                    const before = try self.snapshot(allocator);
                    try self.assumeDepth(allocator, walk, .{ .condition = binary.left, .truth = guard.truth }, depth + 1);
                    const left = try self.snapshot(allocator);
                    self.restore(before);
                    try self.assumeDepth(allocator, walk, .{ .condition = binary.left, .truth = !guard.truth }, depth + 1);
                    try self.assumeDepth(allocator, walk, .{ .condition = binary.right, .truth = guard.truth }, depth + 1);
                    self.intersect(left);
                }
            },
            else => {},
        }
    }
    /// Forget loop-carried assignments before checking any iteration, including its guard.
    pub fn invalidateWrites(self: *State, allocator: std.mem.Allocator, context: Context, active: Active, body: ast.StatementId) std.mem.Allocator.Error!void {
        var work: std.ArrayList(ast.StatementId) = .empty;
        defer work.deinit(allocator);
        try work.append(allocator, body);
        while (work.pop()) |id| switch (context.program.statements.items[@backingInt(id)].data) {
            .assignment => |assignment| if (active.get(context.src.text(assignment.name))) |slot| self.forget(slot),
            .binding => |binding| if (active.get(context.src.text(binding.name))) |slot| self.forget(slot),
            .block => |children| try work.appendSlice(allocator, children),
            .branch => |branch| {
                try work.append(allocator, branch.then_body);
                if (branch.else_body) |other| try work.append(allocator, other);
            },
            .match => |match| for (match.arms) |arm| {
                try work.append(allocator, arm.body);
            },
            .loop => |loop| try work.append(allocator, loop.body),
            .for_each => |each| try work.append(allocator, each.body),
            .for_range => |range| try work.append(allocator, range.body),
            .with_scope => |scope| try work.append(allocator, scope.body),
            else => {},
        };
    }
};
/// Evaluate a presence test once through the normal exhaustive match representation.
pub fn testValue(checker: anytype, value: typed.NodeId, shape: prelude.OptionShape, span: source.Span) diagnostic.Error!typed.Node {
    const b: collections.Builder(@TypeOf(checker.*)) = .{ .checker = checker, .span = span };
    const slot = try b.local(.bool);
    const some = try b.stmt(.{ .initialize = .{ .slot = slot, .value = try b.node(.bool, .{ .boolean = false }) } });
    const none = try b.stmt(.{ .initialize = .{ .slot = slot, .value = try b.node(.bool, .{ .boolean = true }) } });
    const arms = try checker.allocator.dupe(typed.MatchArm, &.{ .{ .tag = shape.some, .slot = null, .body = some }, .{ .tag = shape.none, .slot = null, .body = none } });
    return b.block(&.{try b.stmt(.{ .match = .{ .value = value, .arms = arms } })}, try b.read(slot));
}
/// Project a proven-present payload, retaining a defensive unreachable-case trap.
pub fn payloadValue(checker: anytype, value: typed.NodeId, shape: prelude.OptionShape, span: source.Span) diagnostic.Error!typed.Node {
    const b: collections.Builder(@TypeOf(checker.*)) = .{ .checker = checker, .span = span };
    const slot = try b.local(shape.element);
    const some = try b.stmt(.{ .block = &.{} });
    const none = try b.stmt(.{ .assertion = .{ .condition = try b.node(.bool, .{ .boolean = false }), .message = "invalidated Option narrowing" } });
    const arms = try checker.allocator.dupe(typed.MatchArm, &.{ .{ .tag = shape.some, .slot = slot, .body = some }, .{ .tag = shape.none, .slot = null, .body = none } });
    return b.block(&.{try b.stmt(.{ .match = .{ .value = value, .arms = arms } })}, try b.read(slot));
}
