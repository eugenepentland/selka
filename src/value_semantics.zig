//! Default value semantics (`VALUE-SEMANTICS-1`, stage 3 of D9,
//! `docs/value-semantics.md`). In this mode, `list`, `dict`, `set` and
//! `byte_buffer` values, and every inline aggregate holding one, are
//! independent values: assignment, a store into a field, element, dictionary
//! value, tuple or payload, a match or loop binding and a return never make two
//! names reach the same collection. A read-only argument is lent, not copied:
//! the callee cannot write it.
//!
//! This module holds the switch, the type predicates and the lowering facts.
//! Lowering (`lower.zig`) puts one `value_copy` instruction after every value
//! that moves to a second home and is not fresh; the ownership analysis
//! (`ownership_values.zig`) decides which of them are moves or borrows and so
//! emit nothing; the native emitter lowers the rest through the one rooted
//! copy-on-write transfer entry `myl_qbe_cow_transfer` (`qbe_value_copy.zig`,
//! `qbe_cow_runtime.c`). Builtin `class` and `Cell` are rejected in the default
//! mode; the one-release legacy-sharing mode retains their reference behavior.
//! `str` and `bytes` are immutable and shared.
const std = @import("std");
const typed = @import("typed.zig");
const typed_walk = @import("typed_walk.zig");
const buffer_operations = @import("buffer_operations.zig");
const flag = @import("wiring/value_semantics.zig");

/// Allocation failure while collecting a function's lowering facts.
pub const Error = std.mem.Allocator.Error;

/// The environment variable that carries the switch into every child compiler
/// a command spawns (the build driver's frontend, the test runner's builds).
pub const variable = "MYLANG_VALUE_SEMANTICS";

/// Internal instrumentation selector inherited by build and test children.
pub const counting_variable = "MYLANG_COW_COUNTING";

/// The command-line spelling of the switch.
pub const option = "--value-semantics";

/// Whether this process checks and lowers with value semantics.
pub fn enabled() bool {
    return flag.enabled;
}

/// Turn value semantics on or off for this process. `main` calls it once,
/// before any checking or lowering; a test restores the previous value.
pub fn setEnabled(value: bool) void {
    flag.enabled = value;
}

/// Whether the compiler emits counter calls beside COW marks and checks.
pub fn counting() bool {
    return flag.counting;
}

/// Set counting before frontend caching or native emission begins.
pub fn setCounting(value: bool) void {
    flag.counting = value;
}

/// Whether an environment value turns the switch on: exactly `1`.
pub fn environmentEnables(value: ?[]const u8) bool {
    const text = value orelse return false;
    return std.mem.eql(u8, text, "1");
}

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

/// Whether the elements (or dictionary values) of the collection type `ty`
/// need copies of their own: a shallow copy, a slice or a concatenation of such
/// a collection is a fresh outer collection whose elements are still shared.
pub fn childrenNeedCopy(records: []const typed.Record, ty: typed.Type) bool {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (!record.isCollection()) return false;
    return switch (record.collection.kind) {
        .list, .dictionary => needsCopy(records, record.shape.buffer.?),
        .string, .bytes => false,
    };
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

/// Whether a value can contain a live dictionary view, including through
/// recursive boxes, containers and inline aggregates. Exhausted proof bounds
/// conservatively answer yes. This does not make the view itself a snapshot.
pub fn containsLiveView(records: []const typed.Record, ty: typed.Type) bool {
    return @import("value_semantics_views.zig").contains(records, ty);
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
                .initialize, .assign => |store| {
                    const index = @backingInt(store.slot);
                    counts[index] +|= 1;
                    // Several stores of one path (a refreshed receiver) still
                    // name one root; different roots name none.
                    self.stores[index] = if (counts[index] == 1) store.value else if (self.stores[index]) |previous| sameRoot(self.program, previous, store.value) else null;
                },
                else => {},
            },
        };
    }

    /// Whether a store into `slot` moves a value to a home of its own.
    pub fn namedStore(self: *const Facts, slot: typed.LocalId) bool {
        return !self.synthetic[@backingInt(slot)];
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
            .unwrap, .wrap, .cast => |value| self.classify(value, null),
            .update => |update| if (self.rootedAt(update.base, target)) .fresh else self.classify(update.base, null),
            .replace => |replace| if (self.rootedAt(replace.base, target)) .fresh else self.classify(replace.base, null),
            .buffer_operation => |operation| bufferSource(operation.kind),
            else => .fresh,
        };
    }
};

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

/// Whether a collection operation builds a fresh outer collection that still
/// shares the receiver's elements, which a transfer must copy.
pub fn shallowResult(kind: buffer_operations.Kind) bool {
    return switch (kind) {
        .copy, .slice, .slice_step, .to_list => true,
        else => false,
    };
}

/// The argument of a collection operation that the operation stores or hands
/// back, and so transfers: an appended, written or inserted element, a
/// dictionary value, a default `get`, `setdefault` or `pop` may return, and the
/// source of an `extend`, `update` or gathering keyed sort whose elements hold
/// collections. Null when the operation stores nothing that needs a copy.
pub fn storedArgument(records: []const typed.Record, owner: typed.Type, kind: buffer_operations.Kind) ?usize {
    if (!owner.isAggregate() or owner.recordIndex() >= records.len) return null;
    const schema = records[owner.recordIndex()];
    if (!schema.isCollection()) return null;
    const element = schema.shape.buffer orelse return null;
    return switch (kind) {
        .append => 0,
        .write, .insert, .setdefault, .get, .pop_default => 1,
        .extend, .update, .sort_keyed => if (needsCopy(records, element)) 0 else null,
        else => null,
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

/// Whether a read-only argument could share storage with one of the same
/// call's `mut` arguments, which the callee may write while it reads the other.
/// Two distinct named locals or parameters are distinct values under value
/// semantics, so only a common root, an untraceable temporary, or a shared
/// `class` object reached from either side can link them. Such an argument is
/// passed as a real copy taken before the call (`VALUE-SEMANTICS-5`).
pub fn argumentConflicts(facts: *const Facts, argument: typed.NodeId, writable: []const typed.NodeId) bool {
    const records = facts.program.records;
    const ty = facts.program.nodes[@backingInt(argument)].ty;
    if (!needsCopy(records, ty) or facts.classify(argument, null) == .fresh) return false;
    const root = valueRoot(facts, argument);
    for (writable) |other| {
        const other_root = valueRoot(facts, other) orelse return true;
        if (root == null or root.? == other_root) return true;
        const other_ty = facts.program.nodes[@backingInt(other)].ty;
        const linked = !copiesAll(records, ty) or !copiesAll(records, other_ty);
        if (linked and sharesWritableType(records, ty, other_ty)) return true;
    }
    return false;
}

/// The named local or parameter a value is read from, following synthetic
/// temporaries to the one value they hold; null when untraceable.
fn valueRoot(facts: *const Facts, id: typed.NodeId) ?typed.LocalId {
    return namedRoot(facts, pathRoot(facts.program, id) orelse return null);
}

/// The named local or parameter local `slot` names: the slot itself, or the
/// local a synthetic temporary was read from; null when untraceable.
pub fn namedRoot(facts: *const Facts, slot: typed.LocalId) ?typed.LocalId {
    var current = slot;
    var hops: usize = 0;
    while (hops < 64) : (hops += 1) {
        const index = @backingInt(current);
        if (!facts.synthetic[index]) return current;
        const value = facts.stores[index] orelse return null;
        current = pathRoot(facts.program, value) orelse return null;
    }
    return null;
}

/// Whether two types can reach a common writable type (a list, dict, set,
/// byte_buffer, `class` or Cell), the only way a `class` link could make one
/// value's storage reachable from the other.
fn sharesWritableType(records: []const typed.Record, a: typed.Type, b: typed.Type) bool {
    var left: [64]typed.Type = undefined;
    var right: [64]typed.Type = undefined;
    const found_left = writableTypes(records, a, &left) orelse return true;
    const found_right = writableTypes(records, b, &right) orelse return true;
    for (found_left) |x| for (found_right) |y| if (x == y) return true;
    return false;
}

/// Every writable type reachable from `root`, or null past the buffer's size.
fn writableTypes(records: []const typed.Record, root: typed.Type, buffer: *[64]typed.Type) ?[]const typed.Type {
    var seen: [128]typed.Type = undefined;
    var seen_len: usize = 0;
    var stack: [128]typed.Type = undefined;
    var depth: usize = 1;
    stack[0] = root;
    var len: usize = 0;
    while (depth > 0) {
        depth -= 1;
        const ty = stack[depth];
        if (!ty.isAggregate() or ty.recordIndex() >= records.len) continue;
        if (std.mem.indexOfScalar(typed.Type, seen[0..seen_len], ty) != null) continue;
        if (seen_len == seen.len) return null;
        seen[seen_len] = ty;
        seen_len += 1;
        const record = records[ty.recordIndex()];
        if (typed.carriesWritableStorage(records, ty) and record.managed) {
            if (len == buffer.len) return null;
            buffer[len] = ty;
            len += 1;
        }
        var children: [64]typed.Type = undefined;
        const count = childTypes(record, &children) orelse return null;
        for (children[0..count]) |child| {
            if (depth == stack.len) return null;
            stack[depth] = child;
            depth += 1;
        }
    }
    return buffer[0..len];
}

/// The component types of one schema, written into `children`; null when there
/// are more than it holds.
fn childTypes(record: typed.Record, children: *[64]typed.Type) ?usize {
    var count: usize = 0;
    const singles = [_]?typed.Type{ record.shape.buffer, record.collection.key, record.shape.domain, if (record.shape.array) |array| array.element else null };
    for (singles) |single| if (single) |child| {
        children[count] = child;
        count += 1;
    };
    if (record.shape.variants) |variants| {
        for (variants.cases) |case| if (case.payload) |payload| {
            if (count == children.len) return null;
            children[count] = payload;
            count += 1;
        };
        return count;
    }
    for (record.fields) |field| {
        if (count == children.len) return null;
        children[count] = field.ty;
        count += 1;
    }
    return count;
}
