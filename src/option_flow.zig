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
/// The three intrinsic methods `Option[T]` answers: one absent-means-default
/// projection and the two presence tests. The concrete checker, the
/// generic-body pass and the message that names the accepted spellings all read
/// this list, so they cannot disagree about the set.
pub const Method = enum { unwrap_or, is_none, is_some };
/// The accepted spellings of `Option[T]`, printed when a receiver has no such
/// method.
pub const method_spellings = "an Option receiver supports `unwrap_or(default)`, `is_none()` and `is_some()`";
/// The intrinsic `Option` method a name spells, or null for every other name.
pub fn methodNamed(name: []const u8) ?Method {
    if (std.mem.eql(u8, name, "unwrap_or")) return .unwrap_or;
    if (std.mem.eql(u8, name, "is_none")) return .is_none;
    if (std.mem.eql(u8, name, "is_some")) return .is_some;
    return null;
}
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
        while (work.pop()) |id| {
            const statement = context.program.statements.items[@backingInt(id)];
            switch (statement.data) {
                .assignment => |assignment| if (active.get(context.src.text(assignment.name))) |slot| self.forget(slot),
                .binding => |binding| if (active.get(context.src.text(binding.name))) |slot| self.forget(slot),
                else => {},
            }
            try ast.appendNested(allocator, &work, statement);
        }
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
/// Lower `Option.unwrap_or(default)` through the same exhaustive match as a
/// presence test: the receiver is rooted first, the default is evaluated
/// eagerly into a fresh temporary, and the two arms bind the payload or that
/// temporary into one result slot. Nothing here allocates, so a `noalloc`
/// ceiling accepts the method, and the default's own effects stay its own. The
/// checker type is an explicit compile-time parameter so this file keeps its
/// `anytype` budget.
pub fn defaultValue(comptime Checker: type, checker: *Checker, value: typed.NodeId, shape: prelude.OptionShape, fallback: typed.NodeId, span: source.Span) diagnostic.Error!typed.Node {
    // Aggregate selections retain both evaluated sources. Primitive scalar
    // payloads keep the existing ordinary match path.
    if (shape.element.isAggregate()) return .{ .span = span, .ty = shape.element, .data = .{ .borrow_selection = .{
        .kind = .optional_default,
        .first = value,
        .second = fallback,
    } } };
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    const owner = try b.local(checker.nodes.items[@backingInt(value)].ty);
    const rooted = try b.stmt(.{ .initialize = .{ .slot = owner, .value = value } });
    const absent = try b.local(shape.element);
    const eager = try b.stmt(.{ .initialize = .{ .slot = absent, .value = fallback } });
    const slot = try b.local(shape.element);
    const some = try b.stmt(.{ .block = &.{} });
    const none = try b.stmt(.{ .initialize = .{ .slot = slot, .value = try b.read(absent) } });
    const arms = try checker.allocator.dupe(typed.MatchArm, &.{ .{ .tag = shape.some, .slot = slot, .body = some }, .{ .tag = shape.none, .slot = null, .body = none } });
    const select = try b.stmt(.{ .match = .{ .value = try b.read(owner), .arms = arms } });
    return b.block(&.{ rooted, eager, select }, try b.read(slot));
}
