//! Bounded monotone state joins for the physical borrowed-entry certificate.
//! Unavailable locals are distinct from available immortal/plain values.
const std = @import("std");
const typed = @import("typed.zig");

/// One physical value, anchored to a parameter or containing only immortals.
pub const Value = struct { ty: typed.Type, anchor: ?u32 = null };
/// Stack and local facts at one reachable instruction.
pub const State = struct { stack: []Value, locals: []?Value };
const Queue = struct {
    items: []usize,
    queued: []bool,
    head: usize = 0,
    count: usize = 0,

    fn add(self: *Queue, pc: usize) void {
        if (self.queued[pc]) return;
        std.debug.assert(self.count < self.items.len);
        self.items[(self.head + self.count) % self.items.len] = pc;
        self.queued[pc] = true;
        self.count += 1;
    }
    fn take(self: *Queue) ?usize {
        if (self.count == 0) return null;
        const pc = self.items[self.head];
        self.head = (self.head + 1) % self.items.len;
        self.count -= 1;
        self.queued[pc] = false;
        return pc;
    }
};

/// Worklist storage with bounded state joins and a shared root-query budget.
pub const Graph = struct {
    allocator: std.mem.Allocator,
    incoming: []?State,
    queue: Queue,
    width: usize,
    remaining: *usize,

    /// Allocate empty incoming facts and one queue position per instruction.
    pub fn init(allocator: std.mem.Allocator, count: usize, local_count: usize, remaining: *usize) std.mem.Allocator.Error!Graph {
        const incoming = try allocator.alloc(?State, count);
        errdefer allocator.free(incoming);
        @memset(incoming, null);
        const queued = try allocator.alloc(bool, count);
        errdefer allocator.free(queued);
        @memset(queued, false);
        return .{ .allocator = allocator, .incoming = incoming, .queue = .{ .items = try allocator.alloc(usize, count), .queued = queued }, .width = count + local_count, .remaining = remaining };
    }
    /// Release all per-instruction facts and queue storage.
    pub fn deinit(self: *Graph) void {
        for (self.incoming) |state| if (state) |present| {
            self.allocator.free(present.stack);
            self.allocator.free(present.locals);
        };
        self.allocator.free(self.incoming);
        self.allocator.free(self.queue.items);
        self.allocator.free(self.queue.queued);
    }
    /// Charge one conservative full-state operation to the root-query budget.
    pub fn charge(self: *Graph) bool {
        if (self.width > self.remaining.*) return false;
        self.remaining.* -= self.width;
        return true;
    }
    /// Remove the next changed instruction, allowing it to be enqueued again.
    pub fn take(self: *Graph) ?usize {
        return self.queue.take();
    }
    /// Join an edge and enqueue only changed facts; false declines the proof.
    pub fn publish(self: *Graph, target: usize, source: State) std.mem.Allocator.Error!bool {
        if (target >= self.incoming.len or source.stack.len > self.incoming.len or !self.charge()) return false;
        var changed = false;
        if (self.incoming[target]) |state| {
            if (state.stack.len != source.stack.len or state.locals.len != source.locals.len) return false;
            for (state.stack, source.stack) |*destination, value| {
                const old = destination.anchor;
                if (!merge(destination, value)) return false;
                changed = changed or old != destination.anchor;
            }
            for (state.locals, source.locals) |*destination, value| {
                if (destination.*) |*present| {
                    if (value) |incoming| {
                        const old = present.anchor;
                        if (!merge(present, incoming)) return false;
                        changed = changed or old != present.anchor;
                    } else {
                        destination.* = null;
                        changed = true;
                    }
                }
                // Once unavailable, a join never restores a local from only
                // one predecessor. An explicit store is a separate transfer.
            }
        } else {
            const stack = try self.allocator.dupe(Value, source.stack);
            errdefer self.allocator.free(stack);
            self.incoming[target] = .{ .stack = stack, .locals = try self.allocator.dupe(?Value, source.locals) };
            changed = true;
        }
        if (changed) self.queue.add(target);
        return true;
    }
};

/// Join compatible physical values, refusing conflicting parameter anchors.
pub fn merge(destination: *Value, source: Value) bool {
    if (destination.ty != source.ty) return false;
    if (destination.anchor) |anchor| {
        if (source.anchor) |other| if (anchor != other) return false;
    } else destination.anchor = source.anchor;
    return true;
}
