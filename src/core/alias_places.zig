//! The `const` bindings of a record place that a later write to the record makes stale (R2, disjoint fields).
//!
//! `const item = self.items[i]` borrows the element in place, and `append(mut self.links, copy(item))` writes another field of
//! `self`. The lowering threads the record through its updates as SSA values, so a borrow read from the record before an update
//! is rooted at a value the update consumes, and the ownership pass (and the certificate validator after it) refuse a use of
//! that borrow after the update. The lowering therefore reads such a binding's place again from the record's current value at
//! each use that follows a write (`build.zig`, `reprojected`), and the borrow check lets a write to a field that is disjoint from
//! the place stand only for these bindings (`single_owner.zig`, `exemptible`). Both ask this module, so they agree.
//!
//! The answer is a property of the checked body alone. A binding is listed when it names a place with at least one record
//! field below a named local and that local is written later in the body; it is also marked `carried` when a loop that reads
//! the binding and does not contain it contains such a write, because the next iteration reads the binding after the write. A
//! write is anything that can change the local: an
//! assignment, a mutating operation on a receiver rooted at it, a `mut` argument of a call or callback rooted at it, a
//! `take` or `exchange` of one of its fields, or a `match mut` over one of its places. Over-listing is harmless (a binding
//! that is never read after a write behaves as before); a write this module misses leaves its bindings unlisted, so the
//! borrow check keeps refusing the write.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const typed_walk = language.typed_walk;

/// A named place: the local it is rooted at and whether a record field lies between the root and the place.
const Named = struct { root: u32, fields: bool };

/// One use of a local that can change it, in the order the body is walked.
const Write = struct { order: usize, root: u32 };

/// One `const` binding of a place, in the order the body is walked.
const Binding = struct { order: usize, slot: u32, root: u32 };

/// One read of a local.
const Read = struct { order: usize, slot: u32 };

/// The items a loop statement covers in the order the body is walked, itself included.
const Extent = struct { start: usize, end: usize };

fn inside(extent: Extent, order: usize) bool {
    return order >= extent.start and order <= extent.end;
}

const Collector = struct {
    a: std.mem.Allocator,
    program: typed.Program,
    function: typed.Function,
    /// The initializer of each compiler temporary, so a receiver is traced to the local it was read from.
    temporaries: std.AutoHashMapUnmanaged(u32, typed.NodeId) = .empty,
    writes: std.ArrayList(Write) = .empty,
    bindings: std.ArrayList(Binding) = .empty,
    reads: std.ArrayList(Read) = .empty,
    loops: std.ArrayList(Extent) = .empty,
    /// The temporaries a `for` loop iterates: the owners of its iteration checks.
    iterated: std.AutoHashMapUnmanaged(u32, void) = .empty,

    fn local(c: *const Collector, slot: u32) typed.Local {
        return c.function.scope.locals[slot];
    }

    fn temporary(c: *const Collector, slot: u32) bool {
        const info = c.local(slot);
        return info.usage.temporary or std.mem.startsWith(u8, info.name, "<");
    }

    /// The local an expression is a place of, through fields, elements, receiver temporaries and the staging blocks of an
    /// element read. Null for a value that names no place.
    fn named(c: *const Collector, id: typed.NodeId, depth: usize) ?Named {
        if (depth > c.program.nodes.len) return null;
        const node = c.program.nodes[@backingInt(id)];
        switch (node.data) {
            .local => |slot| {
                const index: u32 = @intCast(@backingInt(slot));
                if (!c.temporary(index)) return .{ .root = index, .fields = false };
                const initializer = c.temporaries.get(index) orelse return null;
                return c.named(initializer, depth + 1);
            },
            .field => |field| {
                const base = c.named(field.base, depth + 1) orelse return null;
                return .{ .root = base.root, .fields = true };
            },
            .index => |index| return c.named(index.base, depth + 1),
            .block_value => |block| return c.named(block.value, depth + 1),
            .buffer_operation => |operation| {
                if (operation.kind != .read) return null;
                const owner: u32 = @intCast(@backingInt(operation.owner));
                if (!c.temporary(owner)) return .{ .root = owner, .fields = false };
                const initializer = c.temporaries.get(owner) orelse return null;
                return c.named(initializer, depth + 1);
            },
            else => return null,
        }
    }

    fn write(c: *Collector, order: usize, id: typed.NodeId) std.mem.Allocator.Error!void {
        if (c.named(id, 0)) |place| try c.writes.append(c.a, .{ .order = order, .root = place.root });
    }

    fn writeLocal(c: *Collector, order: usize, slot: u32) std.mem.Allocator.Error!void {
        if (!c.temporary(slot)) return c.writes.append(c.a, .{ .order = order, .root = slot });
        const initializer = c.temporaries.get(slot) orelse return;
        try c.write(order, initializer);
    }

    /// Note what the expression at `order` can change, and which local it reads.
    fn expression(c: *Collector, order: usize, id: typed.NodeId) std.mem.Allocator.Error!void {
        switch (c.program.nodes[@backingInt(id)].data) {
            .local => |slot| try c.reads.append(c.a, .{ .order = order, .slot = @intCast(@backingInt(slot)) }),
            .buffer_operation => |operation| {
                try c.reads.append(c.a, .{ .order = order, .slot = @intCast(@backingInt(operation.owner)) });
                if (operation.kind.writesReceiver()) try c.writeLocal(order, @intCast(@backingInt(operation.owner)));
            },
            .call => |call| {
                const callee = c.program.functions[@backingInt(call.function)];
                for (callee.signature.declared_mutates) |position| {
                    if (position < call.arguments.len) try c.write(order, call.arguments[position]);
                }
            },
            .invoke => |call| {
                const callee_type = c.program.nodes[@backingInt(call.callee)].ty;
                if (!callee_type.isAggregate()) return;
                const callback = c.program.records[callee_type.recordIndex()].contract.callback orelse return;
                for (callback.mutates) |position| {
                    if (position < call.arguments.len) try c.write(order, call.arguments[position]);
                }
            },
            .place_exchange => |exchange| try c.write(order, exchange.place),
            else => {},
        }
    }

    /// Note the statement at `order`: a store, a `match mut`, and a binding of a place.
    fn statement(c: *Collector, order: usize, id: typed.StatementId) std.mem.Allocator.Error!void {
        switch (c.program.statements[@backingInt(id)].data) {
            .assign => |store| try c.writeLocal(order, @intCast(@backingInt(store.slot))),
            .match => |match| if (match.exclusive) try c.write(order, match.value),
            .initialize => |store| try c.binding(order, store),
            .loop, .range_loop => {
                var inner = try typed_walk.Walker.init(c.a, c.program, id);
                var count: usize = 0;
                while (try inner.next()) |_| count += 1;
                try c.loops.append(c.a, .{ .start = order, .end = order + count - 1 });
            },
            else => {},
        }
    }

    /// Whether a loop that reads binding `bound` and does not contain it contains the write: the loop's next iteration reads the
    /// binding after the write.
    fn carried(c: *const Collector, bound: Binding, written: Write) bool {
        for (c.loops.items) |extent| {
            if (!inside(extent, written.order) or inside(extent, bound.order)) continue;
            for (c.reads.items) |read| {
                if (read.slot == bound.slot and inside(extent, read.order)) return true;
            }
        }
        return false;
    }

    fn binding(c: *Collector, order: usize, store: typed.Store) std.mem.Allocator.Error!void {
        const slot: u32 = @intCast(@backingInt(store.slot));
        // A loop variable, and the collection temporary a `for` loop iterates (the owner of its iteration check), are bound
        // for one iteration and read again after a write; any other temporary keeps the value it captured.
        const looped = c.local(slot).origin == .iteration or (iteratedCollection(c.local(slot)) and c.iterated.contains(slot));
        if (store.unpack != null or store.transfer) return;
        if (c.temporary(slot) and !looped) return;
        if (!projectedBinding(c.local(slot)) or c.program.nodes[@backingInt(store.value)].own) return;
        if (!c.local(slot).ty.isAggregate()) return;
        const place = c.named(store.value, 0) orelse return;
        if (!place.fields or place.root == slot) return;
        try c.bindings.append(c.a, .{ .order = order, .slot = slot, .root = place.root });
    }
};

/// What the body does to a binding's record after the binding: `bound` when the record is written later, `carried` when a
/// loop that reads the binding and does not contain it writes the record.
pub const Flags = packed struct { bound: bool = false, carried: bool = false };

/// Whether a binding of a place is read again after a later write to its record: a source `const` declaration, or a loop
/// variable (`for pn in ledger.pins`), which names an element of the iterated place for one iteration (zero-copy part 1).
pub fn projectedBinding(info: typed.Local) bool {
    if (namedConst(info)) return true;
    // The collection a `for` loop iterates (`<collection>`) is read at every iteration, after the body's writes.
    if (iteratedCollection(info)) return true;
    return info.origin == .iteration and !info.mutable and !info.ownership.view and !std.mem.startsWith(u8, info.name, "<");
}

/// Whether a local may be the compiler temporary a `for` loop iterates (`compute` also requires it to own the loop's iteration
/// check): it holds the iterated place, read again each iteration.
pub fn iteratedCollection(info: typed.Local) bool {
    return std.mem.eql(u8, info.name, "<collection>") and info.origin == .local and !info.ownership.view;
}

/// Whether a local is a source `const` declaration: not a compiler temporary, an iteration or pattern binding, a text view or a
/// contract value. Only these bind a place of another local.
pub fn namedConst(info: typed.Local) bool {
    return !info.mutable and !info.usage.temporary and !info.ownership.view and
        info.origin != .contract_value and info.origin != .iteration and info.origin != .pattern and
        !std.mem.startsWith(u8, info.name, "<");
}

/// For each local of `function`, what the body does to the record of a `const` binding of a record place after the binding is made.
/// Allocated from `a`, one entry per local.
pub fn compute(a: std.mem.Allocator, program: typed.Program, function: typed.Function) std.mem.Allocator.Error![]const Flags {
    const listed = try a.alloc(Flags, function.scope.locals.len);
    errdefer a.free(listed);
    @memset(listed, .{});
    var scratch = std.heap.ArenaAllocator.init(a);
    defer scratch.deinit();
    const work = scratch.allocator();
    var collector: Collector = .{ .a = work, .program = program, .function = function };
    // The receiver temporaries are initialized inside the expressions that read them, which the walk reaches after the
    // statement that holds the expression: a first walk finds every temporary, the second orders the writes.
    var walker = try typed_walk.Walker.init(work, program, function.scope.body);
    while (try walker.next()) |item| switch (item) {
        .statement => |id| switch (program.statements[@backingInt(id)].data) {
            .initialize => |store| {
                const slot: u32 = @intCast(@backingInt(store.slot));
                if (collector.temporary(slot) and store.unpack == null) {
                    const first = try collector.temporaries.getOrPut(work, slot);
                    if (!first.found_existing) first.value_ptr.* = store.value;
                }
            },
            else => {},
        },
        .expression => |id| switch (program.nodes[@backingInt(id)].data) {
            .buffer_operation => |operation| if (operation.kind == .iteration_check) try collector.iterated.put(work, @intCast(@backingInt(operation.owner)), {}),
            else => {},
        },
    };
    var order: usize = 0;
    var second = try typed_walk.Walker.init(work, program, function.scope.body);
    while (try second.next()) |item| : (order += 1) switch (item) {
        .statement => |id| try collector.statement(order, id),
        .expression => |id| try collector.expression(order, id),
    };
    for (collector.bindings.items) |bound| {
        for (collector.writes.items) |written| {
            if (written.order <= bound.order or written.root != bound.root) continue;
            listed[bound.slot].bound = true;
            if (collector.carried(bound, written)) listed[bound.slot].carried = true;
        }
    }
    return listed;
}
