//! Signature-only classification of declared borrowed logical results.
//! Only standard option and fallible-success wrappers change their payload
//! representation; a borrow of an ordinary record keeps that record's layout.
const std = @import("std");
const typed = @import("typed.zig");

/// The storage representation of a declared borrow's logical success value.
pub const Kind = enum { none, value, text, bytes, list };
/// The leaf reached through standard borrowed-result wrappers.
pub const Shape = struct { leaf: typed.Type, kind: Kind };
/// One standard wrapper's success payload and variant tag.
pub const Step = struct { payload: typed.Type, tag: usize };

/// Source-declared positions, independent of a concrete instance's result type.
pub fn sources(signature: typed.FunctionSignature) []const u16 {
    return if (signature.return_origin == .params) signature.return_origin.params else &.{};
}

/// Peel one standard Option's Some or a fallible function's success payload.
pub fn step(records: []const typed.Record, ty: typed.Type) ?Step {
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return null;
    const record = records[ty.recordIndex()];
    const standard_result = std.mem.startsWith(u8, record.name, "Result<") or std.mem.startsWith(u8, record.name, "std_result::Result<");
    if (standard_result) if (typed.resultShape(ty, records)) |result| return .{ .payload = result.ok_type, .tag = result.ok_tag };
    if (!std.mem.startsWith(u8, record.name, "Option<") and
        !std.mem.startsWith(u8, record.name, "std_result::Option<")) return null;
    const variants = record.shape.variants orelse return null;
    if (!variants.is_union or variants.fallible or variants.cases.len != 2) return null;
    var payload: ?Step = null;
    var empty = false;
    for (variants.cases, 0..) |case, tag| {
        if (std.mem.eql(u8, case.name, "some")) if (case.payload) |ty_payload| {
            payload = .{ .payload = ty_payload, .tag = tag };
        };
        if (std.mem.eql(u8, case.name, "none") and case.payload == null) empty = true;
    }
    return if (empty) payload else null;
}

/// Classify a function from its declaration alone. A scalar concrete generic
/// result ignores its retained clause, including when its failure type owns data.
pub fn shape(records: []const typed.Record, signature: typed.FunctionSignature) Shape {
    var leaf = signature.return_type;
    var remaining = records.len + 1;
    while (remaining != 0) : (remaining -= 1) {
        const next = step(records, leaf) orelse break;
        leaf = next.payload;
    }
    if (sources(signature).len == 0 or !managed(records, leaf)) return .{ .leaf = leaf, .kind = .none };
    if (leaf.isAggregate() and leaf.recordIndex() < records.len) {
        const record = records[leaf.recordIndex()];
        if (record.isCollection()) return .{ .leaf = leaf, .kind = switch (record.collection.kind) {
            .string => .text,
            .bytes => .bytes,
            .list => .list,
            .dictionary => .value,
        } };
    }
    return .{ .leaf = leaf, .kind = .value };
}

/// Whether a `from` source of type `parameter` (null for an unresolved type parameter) can lend a result whose borrowed leaf
/// is `leaf`. Core declares a source only when it holds storage of the leaf (`ir.Module.borrowCompatible`): a text or bytes
/// value for a text or bytes leaf, a list of the leaf's element type for a list leaf, and for a record leaf the record or the
/// storage of one of its managed fields; it drops every other source (`build.zig`, `lendingSources`). A contract with no
/// lending source is one Core cannot declare: the declaration authority refuses it (`core/borrow_contract.zig`), and Core's
/// ownership check refuses a generic instance with it (`core/instance_borrow.zig`). A plain (not `mut`) `str` or `bytes`
/// parameter is a view of the caller's octets and lends only a text or bytes leaf of its own kind.
///
/// The answer is false only where the checked types make it certain. Where the IR types could still agree (two records or
/// dictionaries, scalar elements, a resource, a callback) it is true, so a source Core would keep is never refused here.
pub fn sourceLends(records: []const typed.Record, mutable: bool, parameter: ?typed.Type, leaf: Shape) bool {
    const ty = parameter orelse return true;
    if (leaf.kind == .none) return true;
    if (!mutable and ty.isAggregate() and ty.recordIndex() < records.len) {
        const record = records[ty.recordIndex()];
        if (record.isCollection() and record.collection.kind == .string) return leaf.kind == .text;
        if (typed.isByteString(record)) return leaf.kind == .bytes;
    }
    return holds(records, ty, leaf, 0);
}

/// The depth past which a walk of nested types answers "may lend".
const lend_depth = 24;

/// Whether `ty`, or a type it holds (a field, a variant's payload, a collection's element or key, an array's element), may be
/// storage the leaf borrows.
fn holds(records: []const typed.Record, ty: typed.Type, leaf: Shape, depth: usize) bool {
    if (depth > lend_depth) return true;
    if (lendsLeaf(records, ty, leaf)) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    const record = records[ty.recordIndex()];
    if (record.shape.resource != null or record.contract.callback != null or record.isCell()) return true;
    if (record.shape.buffer) |element| if (holds(records, element, leaf, depth + 1)) return true;
    if (record.collection.key) |key| if (holds(records, key, leaf, depth + 1)) return true;
    if (record.shape.array) |array| if (holds(records, array.element, leaf, depth + 1)) return true;
    if (record.shape.domain) |domain| if (holds(records, domain, leaf, depth + 1)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.payload) |payload| if (holds(records, payload, leaf, depth + 1)) return true;
    };
    for (record.fields) |field| if (holds(records, field.ty, leaf, depth + 1)) return true;
    return false;
}

/// Whether a value of type `ty` itself may be storage the leaf borrows: text for a text leaf, bytes or a byte buffer for a
/// bytes leaf, a list of the leaf's element type for a list leaf, and for a record leaf the record or a managed field of it
/// (or a managed payload of an option or union field).
fn lendsLeaf(records: []const typed.Record, ty: typed.Type, leaf: Shape) bool {
    const class = classOf(records, ty, 0);
    return switch (leaf.kind) {
        .none => true,
        .text => class == .text or class == .other,
        .bytes => class == .bytes or class == .buffer or class == .other,
        .list => class == .other or class == .set or (class == .list and sameElement(records, ty, leaf.leaf, 0)),
        .value => sameStorage(records, ty, leaf.leaf, 0) or fieldStorage(records, ty, leaf.leaf, 0),
    };
}

/// Whether `ty` may be the storage of a managed field of record `leaf`, or of a managed payload of a union field, as Core's
/// `lendableField` asks.
fn fieldStorage(records: []const typed.Record, ty: typed.Type, leaf: typed.Type, depth: usize) bool {
    if (depth > lend_depth) return true;
    if (!leaf.isAggregate() or leaf.recordIndex() >= records.len) return false;
    const record = records[leaf.recordIndex()];
    if (depth == 0) {
        if (!record.isRecord()) return false;
        for (record.fields) |field| {
            if (!managed(records, field.ty)) continue;
            if (sameStorage(records, ty, field.ty, 0) or fieldStorage(records, ty, field.ty, 1)) return true;
        }
        return false;
    }
    const variants = record.shape.variants orelse return false;
    for (variants.cases) |case| {
        const payload = case.payload orelse continue;
        if (!managed(records, payload)) continue;
        if (sameStorage(records, ty, payload, 0) or fieldStorage(records, ty, payload, depth + 1)) return true;
    }
    return false;
}

/// The storage kinds a checked type may have in Core, as far as the checked type tells them apart. `other` is a kind the
/// checked type does not settle (a resource handle, a box), which may be any of them.
const StorageClass = enum { scalar, text, bytes, buffer, list, set, dictionary, record, other };

fn classOf(records: []const typed.Record, ty: typed.Type, depth: usize) StorageClass {
    if (!managed(records, ty)) return .scalar;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len or depth > lend_depth) return .other;
    const record = records[ty.recordIndex()];
    if (record.shape.domain) |domain| return classOf(records, domain, depth + 1);
    if (record.shape.resource != null or record.contract.callback != null or record.isCell()) return .other;
    if (!record.isCollection()) return .record;
    if (record.collection.box) return .other;
    return switch (record.collection.kind) {
        .string => .text,
        .bytes => if (typed.isByteString(record)) .bytes else .buffer,
        .list => if (record.collection.set) .set else .list,
        .dictionary => .dictionary,
    };
}

/// Whether `left` and `right` may be one storage type in Core: false only where their storage kinds differ, or where two
/// lists' elements cannot be one type.
fn sameStorage(records: []const typed.Record, left: typed.Type, right: typed.Type, depth: usize) bool {
    if (left == right or depth > lend_depth) return true;
    const a = classOf(records, left, 0);
    const b = classOf(records, right, 0);
    if (a == .other or b == .other) return true;
    if (a != b) return false;
    return a != .list or sameElement(records, left, right, depth + 1);
}

/// Whether the elements of lists `left` and `right` may be one type.
fn sameElement(records: []const typed.Record, left: typed.Type, right: typed.Type, depth: usize) bool {
    const a = records[left.recordIndex()].shape.buffer orelse return true;
    const b = records[right.recordIndex()].shape.buffer orelse return true;
    return sameStorage(records, a, b, depth);
}

/// The owners an actual borrowed result holds; scalar instances hold none.
pub fn effectiveSources(records: []const typed.Record, signature: typed.FunctionSignature) []const u16 {
    return if (shape(records, signature).kind == .none) &.{} else sources(signature);
}

const Seen = struct { ty: typed.Type, parent: ?*const Seen };

/// Whether this type contains managed storage, with cycle detection rather
/// than a fixed nesting limit. Plain scalar records remain ordinary values.
pub fn managed(records: []const typed.Record, ty: typed.Type) bool {
    return managedAt(records, ty, null);
}

fn managedAt(records: []const typed.Record, ty: typed.Type, previous: ?*const Seen) bool {
    if (ty.isFile()) return true;
    if (!ty.isAggregate() or ty.recordIndex() >= records.len) return false;
    var at = previous;
    while (at) |seen| : (at = seen.parent) if (seen.ty == ty) return false;
    const seen: Seen = .{ .ty = ty, .parent = previous };
    const record = records[ty.recordIndex()];
    if (record.managed or record.collection.box or record.shape.resource != null) return true;
    if (record.shape.array) |array| if (managedAt(records, array.element, &seen)) return true;
    if (record.shape.variants) |variants| for (variants.cases) |case| {
        if (case.boxed) return true;
        if (case.payload) |payload| if (managedAt(records, payload, &seen)) return true;
    };
    for (record.fields) |field| {
        if (field.boxed or managedAt(records, field.ty, &seen)) return true;
    }
    return false;
}
