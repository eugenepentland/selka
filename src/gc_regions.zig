//! Region allocation of ordinary managed objects. Every managed header carries the
//! arena depth that owns it; depth 0 is the ordinary tracing heap and depth k is the
//! k-th nested active `with arena()` scope. The invariant an object never references
//! an object of a younger arena is kept by a store barrier, so bulk release at scope
//! exit can free a whole depth without tracing the surviving graph.
const std = @import("std");
const gc = @import("gc_heap.zig");
const values = @import("runtime_values.zig");
const Value = values.Value;
const Object = values.ManagedObject;

/// Failures shared with ordinary managed storage, including the escape barrier.
pub const Error = gc.Error;

/// Enter a new innermost arena; later managed allocation lands in it.
pub fn begin(heap: *gc.Heap) void {
    heap.regions.depth += 1;
    heap.statistics.arena.scopes +|= 1;
}

/// Report whether a value still reaches the innermost arena about to be released.
pub fn retains(heap: *gc.Heap, value: Value) Error!bool {
    if (heap.regions.depth == 0) return false;
    const deepest = try heap.regionDepth(value);
    return deepest >= heap.regions.depth;
}

/// Release every object allocated in the innermost arena and leave that scope.
/// Outgoing edges are dropped before any header is freed, so surviving older
/// objects keep exact reference counts for the next tracing collection.
pub fn end(heap: *gc.Heap) void {
    if (heap.regions.depth == 0) return;
    const dying = heap.regions.depth;
    var cursor = heap.first;
    while (cursor) |object| : (cursor = object.next) {
        if (object.trace.region >= dying) heap.clear(object);
    }
    var link = &heap.first;
    while (link.*) |object| {
        if (object.trace.region < dying) {
            link = &object.next;
            continue;
        }
        link.* = object.next;
        heap.statistics.live_capacity -= object.items.capacity;
        object.items.deinit(heap.allocator);
        heap.allocator.destroy(object);
        heap.statistics.live_objects -= 1;
        heap.statistics.arena.released +|= 1;
    }
    heap.regions.depth = dying - 1;
}

/// Deep-copy state for one escape. Objects already older than the innermost arena
/// are shared rather than copied; sharing and cycles inside the copy are preserved.
const Copier = struct {
    heap: *gc.Heap,
    dying: u32,
    map: std.AutoHashMapUnmanaged(*Object, *Object) = .empty,
    records: std.AutoHashMapUnmanaged(*values.Aggregate, Value) = .empty,

    fn deinit(self: *Copier) void {
        var clones = self.map.valueIterator();
        while (clones.next()) |clone| clone.*.release();
        var copies = self.records.valueIterator();
        while (copies.next()) |copy| copy.release(self.heap.allocator);
        self.records.deinit(self.heap.allocator);
        self.map.deinit(self.heap.allocator);
    }

    fn discover(self: *Copier, root: Value) Error!void {
        var pending: std.ArrayList(Value) = .empty;
        defer pending.deinit(self.heap.allocator);
        var seen: std.AutoHashMapUnmanaged(*values.Aggregate, void) = .empty;
        defer seen.deinit(self.heap.allocator);
        try pending.append(self.heap.allocator, root);
        while (pending.pop()) |item| switch (item) {
            .managed => |object| {
                if (object.trace.region < self.dying or self.map.contains(object)) continue;
                // Reserve first: a clone is only recorded once it exists, so a failed
                // allocation never leaves an unowned entry behind for cleanup.
                try self.map.ensureUnusedCapacity(self.heap.allocator, 1);
                const clone = try self.heap.create(object.ty, object.element_type, object.items.items.len);
                clone.managed.collection = object.collection;
                self.map.putAssumeCapacity(object, clone.managed);
                for (object.items.items) |field| try pending.append(self.heap.allocator, field);
            },
            .aggregate => |record| {
                const entry = try seen.getOrPut(self.heap.allocator, record);
                if (entry.found_existing) continue;
                if (record.moved_fields != null) return error.InvalidDataValue;
                for (record.fields) |field| try pending.append(self.heap.allocator, field);
            },
            .owned, .capability => return error.InvalidDataValue,
            else => {},
        };
    }

    fn translate(self: *Copier, value: Value) Error!Value {
        switch (value) {
            .managed => |object| {
                const clone = self.map.get(object) orelse return value.retain();
                clone.retain();
                return .{ .managed = clone };
            },
            .aggregate => |record| {
                if (self.records.get(record)) |copy| return copy.retain();
                try self.records.ensureUnusedCapacity(self.heap.allocator, 1);
                var fields: std.ArrayList(Value) = .empty;
                defer {
                    for (fields.items) |field| field.release(self.heap.allocator);
                    fields.deinit(self.heap.allocator);
                }
                for (record.fields) |field| try fields.append(self.heap.allocator, try self.translate(field));
                const copy = Value.create(self.heap.allocator, record.ty, fields.items) catch |err| switch (err) {
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InvalidAggregateType => return error.InvalidDataValue,
                };
                copy.aggregate.active_tag = record.active_tag;
                self.records.putAssumeCapacity(record, copy);
                return copy.retain();
            },
            else => return value.retain(),
        }
    }

    fn fill(self: *Copier) Error!void {
        var entries = self.map.iterator();
        while (entries.next()) |entry| {
            const source = entry.key_ptr.*;
            const clone = entry.value_ptr.*;
            for (source.items.items) |item| clone.items.appendAssumeCapacity(try self.translate(item));
        }
    }
};

/// Copy the innermost arena's part of the graph reachable from `value` into the
/// enclosing region, sharing objects that already live there. Collection is
/// suspended for the duration because partly built clones are not yet rooted.
pub fn escape(heap: *gc.Heap, value: Value) Error!Value {
    if (heap.regions.depth == 0) return value.retain();
    var copier: Copier = .{ .heap = heap, .dying = heap.regions.depth };
    defer copier.deinit();
    const suspended = heap.regions.suspended;
    heap.regions.suspended = true;
    heap.regions.depth -= 1;
    defer {
        heap.regions.depth = copier.dying;
        heap.regions.suspended = suspended;
    }
    try copier.discover(value);
    try copier.fill();
    const result = try copier.translate(value);
    heap.statistics.arena.escaped +|= copier.map.count();
    return result;
}
