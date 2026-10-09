//! Value semantics (`VALUE-SEMANTICS-1`, `docs/value-semantics.md`), the only
//! model: `list`, `dict`, `set` and `byte_buffer` values, and every inline
//! aggregate holding one, are independent values. Assignment, a store into a
//! field, element, dictionary value, tuple or payload, a match or loop binding
//! and a return never make two names reach the same collection. A read-only
//! argument is lent, not copied: the callee cannot write it. Builtin `class` and
//! `Cell` are rejected. `str` and `bytes` are immutable and shared.
//!
//! This module holds the type predicates and the per-function facts the
//! checker's value rules (`value_semantics_check.zig`) and the origin analysis read.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const buffer_operations = @import("buffer_operations.zig");

/// Allocation failure while collecting a function's lowering facts.
pub const Error = std.mem.Allocator.Error;

/// Whether a value of `ty` reaches a list, dict, set or byte_buffer that a
/// transfer would have to duplicate: the type is one, or an inline aggregate
/// holding one. A `class` or Cell is a shared reference, `str` and `bytes` are
/// immutable, and a live dictionary view lends its mapping.
pub fn needsCopy(records: []const typed.Record, ty: typed.Type) bool {
    var path: [1024]usize = undefined;
    return needsCopyDepth(records, ty, &path, 0);
}

fn needsCopyDepth(records: []const typed.Record, ty: typed.Type, path: *[1024]usize, depth: usize) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const index = ty.recordIndex();
    for (path[0..depth]) |prior| if (prior == index) return false;
    if (depth == path.len) return true; // Conservative at the explicit type-depth limit.
    path[depth] = index;
    const record = records[index];
    if (record.managed) {
        // A physical recursive box is immutable, but its one body field can
        // still reach a mutable collection that a transfer must share.
        if (record.collection.box) return record.fields.len == 1 and needsCopyDepth(records, record.fields[0].ty, path, depth + 1);
        if (!record.isCollection()) return false;
        return switch (record.collection.kind) {
            .list, .dictionary => true,
            .string => false,
            .bytes => !typed.isByteString(record),
        };
    }
    if (record.contract.callback != null or record.shape.resource != null) return false;
    if (liveView(record)) return false;
    if (record.shape.domain) |backing| return needsCopyDepth(records, backing, path, depth + 1);
    if (record.shape.array) |array| return needsCopyDepth(records, array.element, path, depth + 1);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (needsCopyDepth(records, payload, path, depth + 1)) return true;
        return false;
    }
    for (record.fields) |field| if (needsCopyDepth(records, field.ty, path, depth + 1)) return true;
    return false;
}

/// Whether a deep value copy of `ty` shares nothing writable with its source:
/// every writable storage it reaches is a collection the copy duplicates, and
/// no `class` object or Cell, which stay shared references.
pub fn copiesAll(records: []const typed.Record, ty: typed.Type) bool {
    var path: [1024]usize = undefined;
    return copiesAllDepth(records, ty, &path, 0);
}

fn copiesAllDepth(records: []const typed.Record, ty: typed.Type, path: *[1024]usize, depth: usize) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return true;
    const index = ty.recordIndex();
    for (path[0..depth]) |prior| if (prior == index) return true;
    if (depth == path.len) return false; // Conservative at the explicit type-depth limit.
    path[depth] = index;
    const record = records[index];
    if (record.managed) {
        if (record.collection.box) return record.fields.len == 1 and copiesAllDepth(records, record.fields[0].ty, path, depth + 1);
        if (!record.isCollection()) return false;
        if (record.collection.kind == .string or record.collection.kind == .bytes) return true;
        if (record.collection.key) |key| if (!copiesAllDepth(records, key, path, depth + 1)) return false;
        return copiesAllDepth(records, record.shape.buffer orelse return true, path, depth + 1);
    }
    if (record.contract.callback != null) return true;
    if (record.shape.resource != null or liveView(record)) return false;
    if (record.shape.domain) |backing| return copiesAllDepth(records, backing, path, depth + 1);
    if (record.shape.array) |array| return copiesAllDepth(records, array.element, path, depth + 1);
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| if (!copiesAllDepth(records, payload, path, depth + 1)) return false;
        return true;
    }
    for (record.fields) |field| if (!copiesAllDepth(records, field.ty, path, depth + 1)) return false;
    return true;
}

/// Whether `ty` is a live dictionary view, whose construction lends its
/// mapping rather than storing a copy of it.
pub fn isLiveView(records: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and liveView(records[ty.recordIndex()]);
}

/// Whether `ty` is a `class` or Cell: a shared reference, never copied.
pub fn sharedRecord(records: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].isManagedRecord();
}

/// Whether reading a field crosses externally held identity, even on the
/// last read of the aggregate that exposes it.
pub fn sharedFields(records: []const typed.Record, ty: typed.Type) bool {
    return sharedRecord(records, ty) or isLiveView(records, ty);
}

/// A `DictKeys`, `DictValues` or `DictItems` projection record.
fn liveView(record: typed.Record) bool {
    return record.shape.builtin == .live_view;
}

/// Whether local `index` of `function` is a home a transferred value is
/// copied into: a name the source spells (a `for` variable included) or the
/// hidden local an `old(...)` captures, rather than a compiler temporary (a
/// materialized receiver, argument, conditional or payload), which is a path to
/// the value it was filled from.
pub fn namedHome(function: typed.Function, index: usize) bool {
    const local = function.scope.locals[index];
    if (local.origin == .iteration or local.origin == .contract_old) return true;
    return !(local.usage.temporary or local.name.len == 0 or local.name[0] == '<');
}

/// How a transferred expression relates to storage that already has a home.
pub const Source = enum {
    /// A value nothing else names: a construction, a call result, a pop, an
    /// `escape` or the result of an operation that already copied.
    fresh,
    /// A read of existing storage, which may need a copy.
    place,
};

/// Per-function lowering facts: which locals are compiler temporaries, and the
/// one value each temporary holds, so a path through one can be followed.
pub const Facts = struct {
    program: typed.Program,
    function: typed.Function,
    /// Per local: a compiler temporary rather than a home (`namedHome`).
    synthetic: []bool,
    /// Per synthetic local: the one value stored into it, or null when it has
    /// none or values rooted at different locals.
    stores: []?typed.NodeId,

    /// Collect `function`'s facts; every allocation comes from `allocator`,
    /// which must be an arena: nothing is freed on its own.
    pub fn collect(allocator: std.mem.Allocator, program: typed.Program, function: typed.Function) Error!Facts {
        const locals = function.scope.locals;
        const synthetic = try allocator.alloc(bool, locals.len);
        const stores = try allocator.alloc(?typed.NodeId, locals.len);
        @memset(stores, null);
        for (synthetic, 0..) |*invented, index| invented.* = index >= function.signature.parameter_count and !namedHome(function, index);
        var self: Facts = .{ .program = program, .function = function, .synthetic = synthetic, .stores = stores };
        if (function.policy.host == null) try self.recordStores(allocator);
        return self;
    }

    fn recordStores(self: *Facts, allocator: std.mem.Allocator) Error!void {
        const counts = try allocator.alloc(u8, self.stores.len);
        @memset(counts, 0);
        var walker = try typed_walk.Walker.init(allocator, self.program, self.function.scope.body);
        defer walker.deinit();
        while (try walker.next()) |item| switch (item) {
            .expression => {},
            .statement => |id| switch (self.program.statements[@backingInt(id)].data) {
                .initialize, .assign => |store| self.recordStore(counts, store),
                .range_loop => |range| {
                    self.recordStore(counts, range.plan().start);
                    self.recordStore(counts, range.plan().end);
                },
                else => {},
            },
        };
    }

    fn recordStore(self: *Facts, counts: []u8, store: typed.Store) void {
        const index = @backingInt(store.slot);
        counts[index] +|= 1;
        // Several stores of one path still name one root; different roots name none.
        self.stores[index] = if (counts[index] == 1) store.value else if (self.stores[index]) |previous| sameRoot(self.program, previous, store.value) else null;
    }

    /// Whether `id` is a path (fields, indexes, updates) rooted at local
    /// `target`, following a synthetic temporary to the one value it holds.
    pub fn rootedAt(self: *const Facts, id: typed.NodeId, target: ?typed.LocalId) bool {
        const wanted = target orelse return false;
        var current = id;
        var hops: usize = 0;
        while (hops < 64) : (hops += 1) switch (self.program.nodes[@backingInt(current)].data) {
            .local => |slot| {
                if (slot == wanted) return true;
                if (!self.synthetic[@backingInt(slot)]) return false;
                current = self.stores[@backingInt(slot)] orelse return false;
            },
            .field => |field| current = field.base,
            .index => |access| current = access.base,
            .update => |update| current = update.base,
            .replace => |replace| current = replace.base,
            else => return false,
        };
        return false;
    }

    /// Whether the value of `id`, stored into `target` (null for a transfer
    /// that is not a local store), is fresh or reads existing storage. An
    /// update rooted at the target itself rebuilds that local from its own old
    /// value, which nothing else names, so it is fresh.
    pub fn classify(self: *const Facts, id: typed.NodeId, target: ?typed.LocalId) Source {
        const node = self.program.nodes[@backingInt(id)];
        return switch (node.data) {
            .local => .place,
            // A field of a `class`, Cell or live view is shared storage, whoever
            // produced the object.
            .field => |field| if (sharedFields(self.program.records, self.program.nodes[@backingInt(field.base)].ty)) .place else self.classify(field.base, null),
            .index => |access| self.classify(access.base, null),
            .block_value => |block| self.classify(block.value, target),
            .propagate => |propagate| self.classify(propagate.value, null),
            .unwrap, .wrap => |value| self.classify(value, null),
            // `byte_buffer(values)` widens a `list[int]` into octet storage of its
            // own, so it reads nothing the list keeps. Any other conversion is
            // read through to its source.
            .cast => |value| if (isByteBuffer(self.program.records, node.ty)) .fresh else self.classify(value, null),
            .update => |update| if (self.rootedAt(update.base, target)) .fresh else self.classify(update.base, null),
            .replace => |replace| if (self.rootedAt(replace.base, target)) .fresh else self.classify(replace.base, null),
            .buffer_operation => |operation| bufferSource(operation.kind),
            else => .fresh,
        };
    }
};

/// Whether `ty` is the mutable `byte_buffer`, the one byte kind a conversion
/// builds from a list rather than snapshotting an existing byte string.
fn isByteBuffer(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    return record.managed and record.collection.kind == .bytes and !typed.isByteString(record);
}

/// Whether a collection operation's result reads storage the receiver keeps:
/// an element or value read, or `setdefault`'s stored value. A `pop` takes its
/// element out; a copy, slice or concatenation already copied its elements
/// (`childrenCopy`); every other result is new.
fn bufferSource(kind: buffer_operations.Kind) Source {
    return switch (kind) {
        .read, .key_at, .value_at, .get, .setdefault => .place,
        else => .fresh,
    };
}

/// The local a read path (fields, indexes, element reads, unwraps) starts from.
pub fn pathRoot(program: typed.Program, id: typed.NodeId) ?typed.LocalId {
    var current = id;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) switch (program.nodes[@backingInt(current)].data) {
        .local => |slot| return slot,
        .field => |field| current = field.base,
        .index => |access| current = access.base,
        .unwrap, .cast, .wrap => |value| current = value,
        .propagate => |propagate| current = propagate.value,
        .block_value => |block| current = block.value,
        .buffer_operation => |operation| switch (operation.kind) {
            .read, .get, .value_at, .key_at => return operation.owner,
            else => return null,
        },
        else => return null,
    };
    return null;
}

/// `previous` when `value` reads a path from the same local, else null.
fn sameRoot(program: typed.Program, previous: typed.NodeId, value: typed.NodeId) ?typed.NodeId {
    const a = pathRoot(program, previous) orelse return null;
    const b = pathRoot(program, value) orelse return null;
    return if (a == b) previous else null;
}
