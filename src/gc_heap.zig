//! Nonmoving tracing collection for aliased guest lists. Retained VM values are
//! roots; references held inside the heap are subtracted before root discovery.
//! This includes ordinary aggregate wrappers, so mixed aggregate/list cycles die.
const std = @import("std");
const values = @import("runtime_values.zig");
const Value = values.Value;
const Type = values.Type;

pub const Error = std.mem.Allocator.Error || error{ Bounds, TypeMismatch, CapacityLimit, ForeignMemory, InvalidDataValue, ArenaEscape };
/// Bulk arena release counters, reported separately from tracing reclamation.
pub const ArenaStatistics = struct { scopes: u64 = 0, released: u64 = 0, escaped: u64 = 0 };
/// Allocation and collection counters for one execution.
pub const Statistics = struct {
    live_objects: usize = 0,
    live_capacity: usize = 0,
    created: u64 = 0,
    reclaimed: u64 = 0,
    collections: u64 = 0,
    peak_objects: usize = 0,
    arena: ArenaStatistics = .{},
};
/// Innermost arena nesting depth and the escape-copy collection guard.
pub const RegionState = struct { depth: u32 = 0, suspended: bool = false };
pub const Object = values.ManagedObject;

/// Execution-local heap. Release exported values before deinitializing it.
pub const Heap = struct {
    allocator: std.mem.Allocator,
    first: ?*Object = null,
    statistics: Statistics = .{},
    stress: bool = false,
    next_collection: usize = 64,
    regions: RegionState = .{},
    max_capacity: usize = std.math.maxInt(usize) / @sizeOf(Value),

    /// Initialize an empty execution heap using the VM backing allocator.
    pub fn init(allocator: std.mem.Allocator) Heap {
        return .{ .allocator = allocator };
    }
    /// Final execution teardown breaks all edges before freeing any headers.
    pub fn deinit(self: *Heap) void {
        var cursor = self.first;
        while (cursor) |object| : (cursor = object.next) {
            self.clear(object);
        }
        cursor = self.first;
        while (cursor) |object| {
            const next = object.next;
            object.items.deinit(self.allocator);
            self.allocator.destroy(object);
            cursor = next;
        }
        self.first = null;
        self.statistics.live_objects = 0;
        self.statistics.live_capacity = 0;
    }
    /// Collect before allocation; retained expression temporaries remain roots.
    pub fn createList(self: *Heap, ty: Type, element_type: Type) Error!*Object {
        try self.safepoint();
        const object = try self.allocator.create(Object);
        object.* = .{ .heap = self, .ty = ty, .element_type = element_type, .next = self.first, .trace = .{ .region = self.regions.depth } };
        self.first = object;
        self.statistics.live_objects += 1;
        self.statistics.created +|= 1;
        self.statistics.peak_objects = @max(self.statistics.peak_objects, self.statistics.live_objects);
        return object;
    }
    /// Append through any alias. Collection sees both the receiver and argument.
    pub fn push(self: *Heap, object: *Object, value: Value) Error!void {
        if (object.collection.kind != .list) return error.TypeMismatch;
        if (object.heap != @as(*anyopaque, @ptrCast(self))) return error.ForeignMemory;
        if (value.typeOf() != object.element_type) return error.TypeMismatch;
        try self.validateElement(value);
        try self.barrier(object, value);
        if (object.items.items.len >= self.max_capacity) return error.CapacityLimit;
        object.retain();
        defer object.release();
        const rooted = value.retain();
        defer rooted.release(self.allocator);
        try self.safepoint();
        const previous = object.items.capacity;
        try object.items.ensureUnusedCapacity(self.allocator, 1);
        object.items.appendAssumeCapacity(value.retain());
        self.statistics.live_capacity += object.items.capacity - previous;
    }
    /// Replace a slot without collecting or changing the list's identity.
    pub fn set(self: *Heap, object: *Object, index: usize, value: Value) Error!void {
        if (object.collection.kind != .list) return error.TypeMismatch;
        if (index >= object.items.items.len) return error.Bounds;
        if (object.heap != @as(*anyopaque, @ptrCast(self))) return error.ForeignMemory;
        if (value.typeOf() != object.element_type) return error.TypeMismatch;
        try self.validateElement(value);
        try self.barrier(object, value);
        const retained = value.retain();
        object.items.items[index].release(self.allocator);
        object.items.items[index] = retained;
    }
    /// Empty the list while preserving all aliases and reusable capacity.
    pub fn clear(self: *Heap, object: *Object) void {
        for (object.items.items) |value| value.release(self.allocator);
        object.items.clearRetainingCapacity();
    }
    /// Allocate the default managed list without guest allocator authority.
    pub fn create(self: *Heap, ty: Type, element: Type, capacity: usize) Error!Value {
        if (capacity > self.max_capacity) return error.CapacityLimit;
        const object = try self.createList(ty, element);
        errdefer object.release();
        try object.items.ensureTotalCapacityPrecise(self.allocator, capacity);
        self.statistics.live_capacity += object.items.capacity;
        return .{ .managed = object };
    }
    fn objectFor(self: *Heap, value: Value) Error!*Object {
        if (value != .managed) return error.TypeMismatch;
        if (value.managed.heap != @as(*anyopaque, @ptrCast(self))) return error.ForeignMemory;
        return value.managed;
    }
    /// Read an element and retain its VM root.
    pub fn read(self: *Heap, value: Value, index: usize) Error!Value {
        return (try self.objectFor(value)).get(index);
    }
    /// Append a value through any alias of this list.
    pub fn append(self: *Heap, value: Value, item: Value) Error!void {
        return self.push(try self.objectFor(value), item);
    }
    /// Replace a value through any alias of this list.
    pub fn write(self: *Heap, value: Value, index: usize, item: Value) Error!void {
        return self.set(try self.objectFor(value), index, item);
    }
    /// Return the current length shared by all aliases.
    pub fn len(self: *Heap, value: Value) Error!usize {
        return (try self.objectFor(value)).items.items.len;
    }
    /// Reject foreign-heap edges and deterministic resources in GC storage.
    pub fn validateElement(self: *Heap, input: Value) Error!void {
        if (input == .owned or input == .capability) return error.InvalidDataValue;
        if (input == .managed) {
            _ = try self.objectFor(input);
            return;
        }
        if (input != .aggregate) return;
        var pending: std.ArrayList(Value) = .empty;
        defer pending.deinit(self.allocator);
        var visited: std.AutoHashMapUnmanaged(*values.Aggregate, void) = .empty;
        defer visited.deinit(self.allocator);
        try pending.append(self.allocator, input);
        while (pending.pop()) |value| switch (value) {
            .owned, .capability => return error.InvalidDataValue,
            .managed => |object| if (object.heap != @as(*anyopaque, @ptrCast(self))) {
                return error.ForeignMemory;
            },
            .aggregate => |aggregate| {
                if (aggregate.moved_fields != null) return error.InvalidDataValue;
                const entry = try visited.getOrPut(self.allocator, aggregate);
                if (entry.found_existing) continue;
                try pending.appendSlice(self.allocator, aggregate.fields);
            },
            else => {},
        };
    }
    /// Highest arena depth reachable from one stored value, visiting shared records once.
    pub fn regionDepth(self: *Heap, value: Value) Error!u32 {
        switch (value) {
            .managed => |object| return object.trace.region,
            .aggregate => {},
            else => return 0,
        }
        var deepest: u32 = 0;
        var pending: std.ArrayList(Value) = .empty;
        defer pending.deinit(self.allocator);
        var visited: std.AutoHashMapUnmanaged(*values.Aggregate, void) = .empty;
        defer visited.deinit(self.allocator);
        try pending.append(self.allocator, value);
        while (pending.pop()) |item| switch (item) {
            .managed => |object| deepest = @max(deepest, object.trace.region),
            .aggregate => |record| {
                const entry = try visited.getOrPut(self.allocator, record);
                if (entry.found_existing) continue;
                for (record.fields, 0..) |field, index| {
                    if (record.moved_fields) |moved| if (moved[index]) continue;
                    try pending.append(self.allocator, field);
                }
            },
            else => {},
        };
        return deepest;
    }

    /// Reject storing a younger arena's object into an older container. Depth ordering
    /// is sufficient because every live object belongs to an arena still on the stack.
    pub fn barrier(self: *Heap, object: *Object, value: Value) Error!void {
        if (self.regions.depth == 0) return;
        if (try self.regionDepth(value) > object.trace.region) return error.ArenaEscape;
    }
    fn safepoint(self: *Heap) Error!void {
        if (self.regions.suspended) return;
        if (self.stress or self.statistics.live_objects >= self.next_collection) try self.collect();
    }

    const Node = union(enum) {
        managed: *Object,
        aggregate: *values.Aggregate,

        fn references(self: Node) usize {
            return switch (self) {
                .managed => |object| object.references,
                .aggregate => |aggregate| aggregate.references,
            };
        }
        fn identity(self: Node) usize {
            return switch (self) {
                .managed => |object| @intFromPtr(object),
                .aggregate => |aggregate| @intFromPtr(aggregate),
            };
        }
        fn fromValue(value: Value) ?Node {
            return switch (value) {
                .managed => |object| .{ .managed = object },
                .aggregate => |aggregate| .{ .aggregate = aggregate },
                else => null,
            };
        }
    };
    const Entry = struct { node: Node, incoming: usize = 0, marked: bool = false };
    const Graph = struct {
        entries: std.ArrayList(Entry) = .empty,
        indices: std.AutoHashMapUnmanaged(usize, usize) = .empty,
        allocator: std.mem.Allocator,

        fn deinit(self: *Graph) void {
            self.entries.deinit(self.allocator);
            self.indices.deinit(self.allocator);
        }
        fn add(self: *Graph, node: Node) std.mem.Allocator.Error!usize {
            const result = try self.indices.getOrPut(self.allocator, node.identity());
            if (result.found_existing) return result.value_ptr.*;
            const index = self.entries.items.len;
            result.value_ptr.* = index;
            try self.entries.append(self.allocator, .{ .node = node });
            return index;
        }
        fn edge(self: *Graph, value: Value) std.mem.Allocator.Error!void {
            if (Node.fromValue(value)) |node| {
                const index = try self.add(node);
                self.entries.items[index].incoming += 1;
            }
        }
        fn discover(self: *Graph, node: Node) std.mem.Allocator.Error!void {
            switch (node) {
                .managed => |object| for (object.items.items) |value| try self.edge(value),
                .aggregate => |aggregate| for (aggregate.fields, 0..) |value, index| {
                    if (aggregate.moved_fields) |moved| if (moved[index]) continue;
                    try self.edge(value);
                },
            }
        }
        fn markValue(self: *Graph, value: Value, pending: *std.ArrayList(usize)) void {
            if (Node.fromValue(value)) |node| self.mark(self.indices.get(node.identity()).?, pending);
        }
        fn mark(self: *Graph, index: usize, pending: *std.ArrayList(usize)) void {
            const entry = &self.entries.items[index];
            if (entry.marked) return;
            entry.marked = true;
            pending.appendAssumeCapacity(index);
        }
        fn trace(self: *Graph, node: Node, pending: *std.ArrayList(usize)) void {
            switch (node) {
                .managed => |object| for (object.items.items) |value| self.markValue(value, pending),
                .aggregate => |aggregate| for (aggregate.fields, 0..) |value, index| {
                    if (aggregate.moved_fields) |moved| if (moved[index]) continue;
                    self.markValue(value, pending);
                },
            }
        }
    };
    /// Discover external roots, trace their graph, then sweep unreachable cycles.
    /// All scratch allocation precedes mutation, so OOM leaves the heap intact.
    pub fn collect(self: *Heap) std.mem.Allocator.Error!void {
        var graph: Graph = .{ .allocator = self.allocator };
        defer graph.deinit();
        var cursor = self.first;
        while (cursor) |object| : (cursor = object.next) {
            _ = try graph.add(.{ .managed = object });
        }
        var index: usize = 0;
        while (index < graph.entries.items.len) : (index += 1) try graph.discover(graph.entries.items[index].node);
        var pending: std.ArrayList(usize) = .empty;
        defer pending.deinit(self.allocator);
        try pending.ensureTotalCapacity(self.allocator, graph.entries.items.len);
        for (graph.entries.items, 0..) |entry, i| {
            std.debug.assert(entry.node.references() >= entry.incoming);
            if (entry.node.references() > entry.incoming) graph.mark(i, &pending);
        }
        while (pending.pop()) |i| graph.trace(graph.entries.items[i].node, &pending);
        for (graph.entries.items) |entry| switch (entry.node) {
            .managed => |object| object.trace.marked = entry.marked,
            .aggregate => {},
        };
        cursor = self.first;
        while (cursor) |object| : (cursor = object.next) {
            if (!object.trace.marked) self.clear(object);
        }
        var link = &self.first;
        while (link.*) |object| {
            if (object.trace.marked) {
                link = &object.next;
            } else {
                link.* = object.next;
                self.statistics.live_capacity -= object.items.capacity;
                object.items.deinit(self.allocator);
                self.allocator.destroy(object);
                self.statistics.live_objects -= 1;
                self.statistics.reclaimed +|= 1;
            }
        }
        self.statistics.collections +|= 1;
        self.next_collection = @max(64, self.statistics.live_objects *| 2);
    }
};
