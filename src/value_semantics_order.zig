//! VALUE-SEMANTICS-14: operands evaluate left to right, and each operand's
//! value is fixed when it is evaluated.
//!
//! A read-only operand is lent, not copied (`VALUE-SEMANTICS-2`): the consumer
//! reads the storage the operand was read from. That is sound only while
//! nothing writes that storage before the consumer is done with it. A later
//! operand of the same expression can: a nested `mut` call, a mutating method
//! such as `pop` or `append`, or a store in a lowered block. This module finds,
//! per function and before lowering, every lent operand whose root local a
//! later operand of the same expression may write, so lowering follows that
//! operand with a real copy (`value_copy` at an `argument` site). A copy only
//! marks the payload shared (the collector) or takes an owner (reference
//! counting); the later write then clones it and the operand keeps the value it
//! had. Where no later operand can write the root, nothing is emitted.
//!
//! The same holds for the receiver of a collection read with arguments
//! (`d.get(k, f(mut d))`, `xs.index(g(mut xs))`, `COW-READ-RECEIVER-1`): the
//! receiver is captured into a private copy before its arguments evaluate.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const values = @import("value_semantics.zig");

/// Allocation failure while finding a function's snapshots.
pub const Error = std.mem.Allocator.Error;

/// The nodes of one function whose value lowering must fix when it is read.
pub const Snapshots = struct {
    /// Operands that lowering follows with a real copy.
    operands: std.AutoHashMapUnmanaged(typed.NodeId, void) = .empty,
    /// Read-only collection operations whose receiver lowering captures into
    /// a private copy before their arguments evaluate.
    receivers: std.AutoHashMapUnmanaged(typed.NodeId, void) = .empty,

    /// Whether lowering must copy operand `id` right after evaluating it.
    pub fn operand(self: *const Snapshots, id: typed.NodeId) bool {
        return self.operands.contains(id);
    }
    /// Whether the collection operation `id` reads a captured receiver.
    pub fn receiver(self: *const Snapshots, id: typed.NodeId) bool {
        return self.receivers.contains(id);
    }
};

/// Where an operand's storage comes from: nothing another name holds, a named
/// local (or parameter), or a place this analysis cannot follow.
const Root = union(enum) { fresh, local: typed.LocalId, unknown };

/// One operand in evaluation order, and whether its consumer only lends it.
const Operand = struct { node: typed.NodeId, lent: bool };

/// Find `facts.function`'s snapshots. Every allocation comes from `allocator`,
/// which must be an arena: nothing is freed on its own.
pub fn find(allocator: std.mem.Allocator, facts: *const values.Facts) Error!Snapshots {
    var finder: Finder = .{ .allocator = allocator, .facts = facts, .written = try writtenTemporaries(allocator, facts) };
    var walker = try typed_walk.Walker.init(allocator, facts.program, facts.function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .expression => |id| try finder.expression(id),
        .statement => |id| try finder.statement(id),
    };
    return finder.found;
}

/// Per local: a compiler temporary that some write goes through (a writing
/// collection operation names it, or it is passed `mut`), so it is a path into
/// the value it was filled from rather than a read-only capture of it.
fn writtenTemporaries(allocator: std.mem.Allocator, facts: *const values.Facts) Error![]bool {
    const written = try allocator.alloc(bool, facts.synthetic.len);
    @memset(written, false);
    var walker = try typed_walk.Walker.init(allocator, facts.program, facts.function.scope.body);
    defer walker.deinit();
    while (try walker.next()) |item| switch (item) {
        .statement => {},
        .expression => |id| switch (facts.program.nodes[@backingInt(id)].data) {
            .buffer_operation => |operation| if (writesReceiver(operation.kind)) {
                written[@backingInt(operation.owner)] = true;
            },
            .call, .invoke => {
                var positions: Positions = .{};
                const arguments = mutablePositions(facts.program, id, &positions);
                for (positions.slice()) |position| if (position < arguments.len) switch (facts.program.nodes[@backingInt(arguments[position])].data) {
                    .local => |slot| written[@backingInt(slot)] = true,
                    else => {},
                };
            },
            else => {},
        },
    };
    return written;
}

const Finder = struct {
    allocator: std.mem.Allocator,
    facts: *const values.Facts,
    written: []const bool,
    found: Snapshots = .{},

    fn program(self: *const Finder) typed.Program {
        return self.facts.program;
    }

    /// The operands of one expression, in evaluation order.
    fn expression(self: *Finder, id: typed.NodeId) Error!void {
        const node = self.program().nodes[@backingInt(id)];
        var list: std.ArrayList(Operand) = .empty;
        switch (node.data) {
            .call => |call| {
                var positions: Positions = .{};
                _ = mutablePositions(self.program(), id, &positions);
                for (call.arguments, 0..) |argument, index| try list.append(self.allocator, .{ .node = argument, .lent = !positions.has(index) });
            },
            .invoke => |call| {
                var positions: Positions = .{};
                _ = mutablePositions(self.program(), id, &positions);
                try list.append(self.allocator, .{ .node = call.callee, .lent = false });
                for (call.arguments, 0..) |argument, index| try list.append(self.allocator, .{ .node = argument, .lent = !positions.has(index) });
            },
            .print => |output| {
                if (output.stream) |stream| try list.append(self.allocator, .{ .node = stream, .lent = false });
                for (output.arguments) |argument| try list.append(self.allocator, .{ .node = argument, .lent = true });
                if (output.separator) |value| try list.append(self.allocator, .{ .node = value, .lent = true });
                if (output.terminator) |value| try list.append(self.allocator, .{ .node = value, .lent = true });
            },
            .binary => |b| {
                if (b.op == .logical_and or b.op == .logical_or) return;
                try list.append(self.allocator, .{ .node = b.left, .lent = true });
                try list.append(self.allocator, .{ .node = b.right, .lent = true });
            },
            .update => |update| {
                try list.append(self.allocator, .{ .node = update.base, .lent = true });
                for (update.fields) |field| try list.append(self.allocator, .{ .node = field.value, .lent = false });
            },
            .replace => |replace| {
                try list.append(self.allocator, .{ .node = replace.base, .lent = true });
                try list.append(self.allocator, .{ .node = replace.index, .lent = true });
                try list.append(self.allocator, .{ .node = replace.value, .lent = false });
            },
            .file_access => |call| for (call.arguments) |argument| try list.append(self.allocator, .{ .node = argument, .lent = true }),
            .buffer_operation => |operation| return self.bufferOperation(id, operation),
            else => return,
        }
        try self.sequence(list.items);
    }

    /// A read-only collection operation reads its receiver after its
    /// arguments; capture the receiver first when an argument may write it.
    /// Its lent arguments are operands like any other.
    fn bufferOperation(self: *Finder, id: typed.NodeId, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) Error!void {
        const stored = storedArgument(self.facts, operation);
        var list: std.ArrayList(Operand) = .empty;
        for (operation.arguments, 0..) |argument, index| try list.append(self.allocator, .{ .node = argument, .lent = stored != index });
        try self.sequence(list.items);
        if (writesReceiver(operation.kind) or operation.arguments.len == 0) return;
        const ty = self.facts.function.scope.locals[@backingInt(operation.owner)].ty;
        if (!values.needsCopy(self.program().records, ty)) return;
        const root = resolve(self.facts, operation.owner);
        if (root == .fresh) return;
        var writes: Writes = .{};
        for (operation.arguments) |argument| try self.collectWrites(argument, &writes);
        if (writes.hits(root)) try self.found.receivers.put(self.allocator, id, {});
    }

    /// A run of initializations of read-only compiler temporaries in one block
    /// (source-order keyword arguments, `zip` sources, membership operands)
    /// evaluates its values in order too, and each temporary is read after the
    /// run.
    fn statement(self: *Finder, id: typed.StatementId) Error!void {
        const children = switch (self.program().statements[@backingInt(id)].data) {
            .block => |children| children,
            else => return,
        };
        var list: std.ArrayList(Operand) = .empty;
        for (children) |child| {
            const store = switch (self.program().statements[@backingInt(child)].data) {
                .initialize => |store| store,
                else => null,
            };
            if (store != null and self.facts.synthetic[@backingInt(store.?.slot)]) {
                try list.append(self.allocator, .{ .node = store.?.value, .lent = !self.written[@backingInt(store.?.slot)] });
                continue;
            }
            try self.sequence(list.items);
            list.clearRetainingCapacity();
        }
        try self.sequence(list.items);
    }

    /// Mark every lent operand whose root a later operand may write.
    fn sequence(self: *Finder, operands: []const Operand) Error!void {
        if (operands.len < 2) return;
        const roots = try self.allocator.alloc(Root, operands.len);
        var any = false;
        for (operands, roots) |item, *root| {
            root.* = if (item.lent) self.operandRoot(item.node) else .fresh;
            any = any or root.* != .fresh;
        }
        if (!any) return;
        var writes: Writes = .{};
        var index = operands.len;
        while (index > 1) {
            index -= 1;
            try self.collectWrites(operands[index].node, &writes);
            const earlier = index - 1;
            if (writes.hits(roots[earlier])) try self.found.operands.put(self.allocator, operands[earlier].node, {});
        }
    }

    /// Where a lent operand's storage comes from; fresh when it needs no copy.
    fn operandRoot(self: *const Finder, id: typed.NodeId) Root {
        const node = self.program().nodes[@backingInt(id)];
        if (!values.needsCopy(self.program().records, node.ty)) return .fresh;
        return valueRoot(self.facts, id);
    }

    /// Every local the evaluation of `id` may write in place.
    fn collectWrites(self: *const Finder, id: typed.NodeId, writes: *Writes) Error!void {
        if (writes.unknown) return;
        var walker = try typed_walk.Walker.initExpression(self.allocator, self.program(), id);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => |node| switch (self.program().nodes[@backingInt(node)].data) {
                .buffer_operation => |operation| if (writesReceiver(operation.kind)) try writes.add(self.allocator, resolve(self.facts, operation.owner)),
                .call, .invoke => {
                    var positions: Positions = .{};
                    const arguments = mutablePositions(self.program(), node, &positions);
                    for (positions.slice()) |position| {
                        if (position >= arguments.len) continue;
                        const root = valueRoot(self.facts, arguments[position]);
                        try writes.add(self.allocator, if (root == .fresh) .unknown else root);
                    }
                },
                else => {},
            },
            .statement => |at| switch (self.program().statements[@backingInt(at)].data) {
                .initialize, .assign => |store| if (!self.facts.synthetic[@backingInt(store.slot)]) try writes.add(self.allocator, .{ .local = store.slot }),
                else => {},
            },
        };
    }
};

/// The locals a stretch of evaluation may write in place.
const Writes = struct {
    locals: std.ArrayList(typed.LocalId) = .empty,
    /// A write this analysis cannot attribute to one local.
    unknown: bool = false,

    fn add(self: *Writes, allocator: std.mem.Allocator, root: Root) Error!void {
        switch (root) {
            .fresh => {},
            .unknown => self.unknown = true,
            .local => |slot| if (std.mem.indexOfScalar(typed.LocalId, self.locals.items, slot) == null) try self.locals.append(allocator, slot),
        }
    }
    /// Whether one of these writes may reach storage rooted at `root`.
    fn hits(self: *const Writes, root: Root) bool {
        return switch (root) {
            .fresh => false,
            .unknown => self.unknown or self.locals.items.len != 0,
            .local => |slot| self.unknown or std.mem.indexOfScalar(typed.LocalId, self.locals.items, slot) != null,
        };
    }
};

/// The `mut` positions of a call or invoke, at most 32.
const Positions = struct {
    items: [32]u16 = undefined,
    len: usize = 0,

    fn add(self: *Positions, position: u16) void {
        if (self.has(position) or self.len == self.items.len) return;
        self.items[self.len] = position;
        self.len += 1;
    }
    fn has(self: *const Positions, position: usize) bool {
        for (self.slice()) |item| if (item == position) return true;
        return false;
    }
    fn slice(self: *const Positions) []const u16 {
        return self.items[0..self.len];
    }
};

/// Fill `positions` with the `mut` positions of call or invoke `id`, whose
/// arguments it returns: the callee's declared and inferred writes, or the
/// callback signature's.
fn mutablePositions(program: typed.Program, id: typed.NodeId, positions: *Positions) []const typed.NodeId {
    switch (program.nodes[@backingInt(id)].data) {
        .call => |call| {
            const signature = program.functions[@backingInt(call.function)].signature;
            for (signature.declared_mutates) |position| positions.add(position);
            for (signature.mutates) |position| positions.add(position);
            return call.arguments;
        },
        .invoke => |call| {
            const callee = program.nodes[@backingInt(call.callee)].ty;
            if (callee.isAggregate() and callee.recordIndex() < program.records.len) {
                if (program.records[callee.recordIndex()].contract.callback) |signature| for (signature.mutates) |position| positions.add(position);
            }
            return call.arguments;
        },
        else => return &.{},
    }
}

/// Where the storage of value `id` comes from.
fn valueRoot(facts: *const values.Facts, id: typed.NodeId) Root {
    if (facts.classify(id, null) == .fresh) return .fresh;
    const slot = values.pathRoot(facts.program, id) orelse return .unknown;
    return resolve(facts, slot);
}

/// The named local or parameter `slot` names: the slot itself, or what the one
/// value a compiler temporary was filled with comes from.
fn resolve(facts: *const values.Facts, slot: typed.LocalId) Root {
    var current = slot;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) {
        const index = @backingInt(current);
        if (!facts.synthetic[index]) return .{ .local = current };
        const value = facts.stores[index] orelse return .unknown;
        if (facts.classify(value, null) == .fresh) return .fresh;
        current = values.pathRoot(facts.program, value) orelse return .unknown;
    }
    return .unknown;
}

/// The argument a collection operation stores or hands back, which lowering
/// already transfers with a copy site of its own.
fn storedArgument(facts: *const values.Facts, operation: @FieldType(@FieldType(typed.Node, "data"), "buffer_operation")) ?usize {
    const owner = facts.function.scope.locals[@backingInt(operation.owner)].ty;
    return values.storedArgument(facts.program.records, owner, operation.kind);
}

/// Whether a collection operation changes the collection it is called on.
fn writesReceiver(kind: @import("buffer_operations.zig").Kind) bool {
    return kind.writesReceiver() or kind == .set_add or kind == .set_discard;
}
