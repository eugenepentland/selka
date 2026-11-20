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
pub const method_spellings = "an Option receiver supports `unwrap_or(default)`; test presence with `value is None` or `value is not None`";
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
/// The message of the unreachable `None` arm a narrowed read keeps.
const narrowing_trap = "invalidated Option narrowing";
/// The hidden owner of the payload `own NAME` takes out of a narrowed option; a name with a space is never written.
const moved_payload_name = "narrowed payload";
/// The hidden owner the moved payload leaves the narrowing's block in.
const moved_result_name = "moved payload";
/// Project a proven-present payload, retaining a defensive unreachable-case trap.
pub fn payloadValue(checker: anytype, value: typed.NodeId, shape: prelude.OptionShape, span: source.Span) diagnostic.Error!typed.Node {
    const b: collections.Builder(@TypeOf(checker.*)) = .{ .checker = checker, .span = span };
    const slot = try b.local(shape.element);
    const some = try b.stmt(.{ .block = &.{} });
    const none = try b.stmt(.{ .assertion = .{ .condition = try b.node(.bool, .{ .boolean = false }), .message = narrowing_trap } });
    const arms = try checker.allocator.dupe(typed.MatchArm, &.{ .{ .tag = shape.some, .slot = slot, .body = some }, .{ .tag = shape.none, .slot = null, .body = none } });
    return b.block(&.{try b.stmt(.{ .match = .{ .value = value, .arms = arms } })}, try b.read(slot));
}
/// The local a read in place that `payloadValue` built projects, or null for any other value.
pub fn narrowedRead(nodes: []const typed.Node, statements: []const typed.Statement, value: typed.NodeId) ?typed.LocalId {
    const node = nodes[@backingInt(value)];
    if (node.data != .block_value) return null;
    const body = statements[@backingInt(node.data.block_value.body)];
    if (body.data != .block or body.data.block.len != 1) return null;
    const select = statements[@backingInt(body.data.block[0])];
    if (select.data != .match or select.data.match.arms.len != 2) return null;
    const arms = select.data.match.arms;
    const none = statements[@backingInt(arms[1].body)];
    if (none.data != .assertion or !std.mem.eql(u8, none.data.assertion.message, narrowing_trap)) return null;
    const scrutinee = nodes[@backingInt(select.data.match.value)];
    const read = nodes[@backingInt(node.data.block_value.value)];
    if (scrutinee.own or scrutinee.data != .local or read.data != .local or arms[0].slot != read.data.local) return null;
    return scrutinee.data.local;
}
/// `own NAME` of an owner narrowed to `Some` (decision NARROW-OWN): the read in place `payloadValue` built becomes the
/// block `const c = own NAME else:` lowers to, `match own NAME: case Some(payload): (nothing) case None: (unreachable)`,
/// whose value moves the payload out, so the option is consumed and nothing is copied. Null for any other value and for an
/// owner the function does not own (a plain or `mut` parameter, a loop variable, a match binding): those keep the read in
/// place, and Core refuses the marker naming the lender.
pub fn ownedPayload(comptime Checker: type, checker: *Checker, value: typed.NodeId, span: source.Span) diagnostic.Error!?typed.Node {
    const owner = narrowedRead(checker.nodes.items, checker.statements.items, value) orelse return null;
    const local = checker.locals.items[@backingInt(owner)];
    const owned = switch (local.origin) {
        .local => true,
        .parameter => local.ownership.owned_parameter,
        else => false,
    };
    if (!owned) return null;
    const ty = checker.nodes.items[@backingInt(value)].ty;
    const shape = prelude.optionShape(local.ty, checker.catalog.records) orelse return error.InternalError;
    const b: collections.Builder(Checker) = .{ .checker = checker, .span = span };
    const payload: typed.LocalId = @fromBackingInt(checker.locals.items.len);
    try checker.locals.append(checker.allocator, .{
        .ownership = .{ .initialized = true, .transfer_available = checker.transfers(ty) },
        .name = moved_payload_name,
        .usage = .{ .reads = 1 },
        .declaration = span,
        .ty = ty,
        .mutable = false,
    });
    // The payload binding ends with its arm, so the arm moves it into a hidden owner the block's value moves out of.
    const result = try b.local(ty);
    checker.locals.items[@backingInt(result)].name = moved_result_name;
    checker.locals.items[@backingInt(result)].mutable = false;
    checker.locals.items[@backingInt(result)].usage = .{ .reads = 1, .writes = 1 };
    const take = try b.stmt(.{ .initialize = .{ .slot = result, .value = try movedOut(Checker, b, payload) } });
    const some = try b.stmt(.{ .block = try checker.allocator.dupe(typed.StatementId, &.{take}) });
    const none = try b.stmt(.{ .assertion = .{ .condition = try b.node(.bool, .{ .boolean = false }), .message = narrowing_trap } });
    const arms = try checker.allocator.dupe(typed.MatchArm, &.{ .{ .tag = shape.some, .slot = payload, .body = some }, .{ .tag = shape.none, .slot = null, .body = none } });
    const select = try b.stmt(.{ .match = .{ .value = try movedOut(Checker, b, owner), .arms = arms } });
    const moved = try b.block(&.{select}, try movedOut(Checker, b, result));
    return moved;
}
/// A bare `return NAME` or `fail NAME` of an owner narrowed to `Some` gives the payload as `own NAME` would (NARROW-OWN): a
/// return of an owned local moves it with no marker. Only a payload with managed storage moves (a number or a record of
/// numbers is copied, as before). The block spans the statement and its moved value the name, so Core does not take the
/// value for a bare return of the hidden owner, which `return own x` would be.
pub fn moveReturned(comptime Checker: type, checker: *Checker, expression: ast.NodeId, value: typed.NodeId, statement: source.Span) diagnostic.Error!void {
    const written = checker.syntax.nodes.items[@backingInt(expression)];
    if (written.data != .name) return;
    if (!@import("own_parameters.zig").managed(checker.catalog.records, checker.nodes.items[@backingInt(value)].ty)) return;
    const moved = try ownedPayload(Checker, checker, value, statement) orelse return;
    checker.nodes.items[@backingInt(moved.data.block_value.value)].span = written.span;
    checker.nodes.items[@backingInt(value)] = moved;
}
/// A read of `slot` that moves its value out.
fn movedOut(comptime Checker: type, b: collections.Builder(Checker), slot: typed.LocalId) diagnostic.Error!typed.NodeId {
    const id = try b.read(slot);
    b.checker.nodes.items[@backingInt(id)].own = true;
    return id;
}
/// Lower `Option.unwrap_or(default)` through the same exhaustive match as a
/// presence test: the receiver is rooted first, the default is evaluated
/// eagerly into a fresh temporary, and the two arms bind the payload or that
/// temporary into one result slot. Nothing here allocates, so a `noalloc`
/// ceiling accepts the method, and the default's own effects stay its own. The
/// checker type is an explicit compile-time parameter so this file keeps its
/// `anytype` budget.
pub fn defaultValue(comptime Checker: type, checker: *Checker, value: typed.NodeId, shape: prelude.OptionShape, fallback: typed.NodeId, span: source.Span) diagnostic.Error!typed.Node {
    // A `@linear` payload makes a linear option, and either the default or the payload would end unconsumed: refused here
    // with the way out, as the borrowed selection would be an internal error (`valid` refuses a pending option).
    if (typed.linear(shape.element, checker.catalog.records)) return @import("linear_rules.zig").refuse(checker.sink, span, .unwrap_or);
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
