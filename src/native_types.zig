//! Target layouts for independently compiled native declarations. Identity input
//! must be canonical frontend identity, never a compilation-local type ordinal.
const std = @import("std");
const typed = @import("typed.zig");
/// SHA-256 digest of canonical native layout inputs.
pub const Digest = [32]u8;
/// Invalid schemas, ambiguous identities, excessive layouts or allocation failure.
pub const Error = error{ OutOfMemory, InvalidType, MissingIdentity, DuplicateIdentity, RecursiveLayout, LayoutOverflow };
/// Concrete native value representations used by backend and runtime. A
/// `niche` value is an `Option` of a managed reference stored as the reference
/// word alone: null is `None`, any other word is `Some` of that reference.
pub const Kind = enum { scalar, record, array, domain, variant, managed, handle, owned_buffer, owned_pool, pool_handle, resource, callable, niche };
/// Copy is a byte copy for plain values, a pointer copy for GC references, and
/// prohibited for move-only values. Trace/drop recurse using the field metadata.
pub const Copy = enum { bytes, reference, prohibited };
/// Native byte offset, symbolic child type and optional active variant tag.
pub const Field = struct { offset: u64, ty: typed.Type, tag: ?usize = null };
/// Target size, alignment, ownership and precise tracing metadata.
pub const Layout = struct {
    kind: Kind,
    size: u64,
    alignment: u8,
    fields: []const Field = &.{},
    count: u64 = 1,
    stride: u64 = 0,
    payload_offset: u64 = 0,
    copy: Copy = .bytes,
    trace: bool = false,
    drop: bool = false,
    hash: Digest = undefined,
};
const State = enum { unseen, active, done };
/// Versioned Linux AMD64 ABI catalog. The caller retains records and identities
/// until deinit. Fields and cached layouts are owned by this catalog.
pub const Catalog = struct {
    pub const abi_version = "mylang-native-amd64-layout-v3";
    allocator: std.mem.Allocator,
    records: []const typed.Record,
    identities: []const []const u8,
    layouts: []Layout,
    states: []State,
    owns_identities: bool = false,
    /// Fingerprints computed for the builtin types, indexed by their tag. A
    /// builtin's layout and digest are a pure function of that tag: the switch in
    /// `layout` reads no catalog state and `fingerprint` recurses only through an
    /// aggregate's fields, of which a builtin has none. A digest computed once
    /// therefore cannot go stale while this catalog lives, and `null` means "not
    /// computed yet". Every builtin is laid out on nearly every emitted
    /// instruction, and recomputing its SHA-256 dominated emission.
    builtin_hashes: [typed.Type.record_base]?Digest = @splat(null),

    /// Nominal catalog names already encode qualified declarations and canonical
    /// type/constant arguments (nominal_catalog.Builder.appendName).
    pub fn initRecords(allocator: std.mem.Allocator, records: []const typed.Record) Error!Catalog {
        const identities = try allocator.alloc([]const u8, records.len);
        errdefer allocator.free(identities);
        for (records, identities) |record, *name| name.* = record.name;
        var result = try init(allocator, records, identities);
        result.owns_identities = true;
        return result;
    }

    /// Validate unique canonical identities and initialize an empty layout cache.
    pub fn init(allocator: std.mem.Allocator, records: []const typed.Record, identities: []const []const u8) Error!Catalog {
        if (identities.len != records.len) return error.MissingIdentity;
        var unique: std.StringHashMapUnmanaged(void) = .empty;
        defer unique.deinit(allocator);
        for (identities) |name| {
            if (name.len == 0) return error.MissingIdentity;
            if ((try unique.getOrPut(allocator, name)).found_existing) return error.DuplicateIdentity;
        }
        const layouts = try allocator.alloc(Layout, records.len);
        errdefer allocator.free(layouts);
        const states = try allocator.alloc(State, records.len);
        @memset(states, .unseen);
        return .{ .allocator = allocator, .records = records, .identities = identities, .layouts = layouts, .states = states };
    }
    pub fn deinit(self: *Catalog) void {
        for (self.layouts, self.states) |item, state| if (state == .done) self.allocator.free(item.fields);
        self.allocator.free(self.layouts);
        self.allocator.free(self.states);
        if (self.owns_identities) self.allocator.free(self.identities);
        self.* = undefined;
    }
    /// Resolve a builtin or canonical nominal identity, rejecting unknown indices.
    pub fn identity(self: *const Catalog, ty: typed.Type) Error![]const u8 {
        if (!ty.isAggregate()) return @tagName(ty);
        if (ty.recordIndex() >= self.identities.len) return error.InvalidType;
        return self.identities[ty.recordIndex()];
    }
    /// Lazily compute a native layout and its stable content fingerprint.
    pub fn layout(self: *Catalog, ty: typed.Type) Error!Layout {
        if (!ty.isAggregate()) {
            var result: Layout = if (ty.integer()) |integer| .{ .kind = .scalar, .size = integer.bits / 8, .alignment = @intCast(integer.bits / 8) } else switch (ty) {
                .bool => .{ .kind = .scalar, .size = 1, .alignment = 1 },
                .unit => .{ .kind = .scalar, .size = 0, .alignment = 1 },
                // An open file is one owned resource word, so the ordinary local
                // drop closes it at every scope exit.
                .file, .text_file => .{ .kind = .resource, .size = 8, .alignment = 8, .copy = .prohibited, .trace = true, .drop = true },
                else => .{ .kind = .handle, .size = 8, .alignment = 8 },
            };
            result.hash = try self.builtinHash(ty, result);
            return result;
        }
        const index = ty.recordIndex();
        if (index >= self.records.len) return error.InvalidType;
        switch (self.states[index]) {
            .done => return self.layouts[index],
            .active => return error.RecursiveLayout,
            .unseen => {},
        }
        self.states[index] = .active;
        errdefer self.states[index] = .unseen;
        var result = try self.build(self.records[index]);
        errdefer self.allocator.free(result.fields);
        result.hash = try self.fingerprint(ty, result);
        self.layouts[index] = result;
        self.states[index] = .done;
        return result;
    }
    /// Owned inline body descriptor for a managed nominal record. Managed
    /// references within its fields remain pointers, so cyclic graphs terminate.
    /// Collection backing uses layout(element) plus runtime element count.
    /// Release fields with releaseLayout after serializing this descriptor.
    pub fn heapLayout(self: *Catalog, ty: typed.Type) Error!Layout {
        if (!ty.isAggregate() or ty.recordIndex() >= self.records.len) return error.InvalidType;
        var record = self.records[ty.recordIndex()];
        if (!record.managed) return error.InvalidType;
        record.managed = false;
        var result = try self.build(record);
        errdefer self.allocator.free(result.fields);
        result.hash = try self.fingerprint(ty, result);
        return result;
    }
    /// Release an independently owned managed body descriptor.
    pub fn releaseLayout(self: *Catalog, item: Layout) void {
        self.allocator.free(item.fields);
    }
    fn build(self: *Catalog, record: typed.Record) Error!Layout {
        if (record.managed) return .{ .kind = .managed, .size = 8, .alignment = 8, .copy = .reference, .trace = true };
        if (record.contract.callback != null) return .{ .kind = .callable, .size = 8, .alignment = 8 };
        if (record.shape.resource != null) return .{ .kind = .resource, .size = 8, .alignment = 8, .copy = .prohibited, .trace = true, .drop = true };
        if (record.shape.hasRuntimeIdentity()) return .{ .kind = .handle, .size = 8, .alignment = 8, .copy = if (record.contract.move_only) .prohibited else .bytes, .drop = record.contract.move_only };
        if (record.shape.array) |array| {
            const child = try self.layout(array.element);
            const stride = try alignSize(child.size, child.alignment);
            const fields = try self.allocator.alloc(Field, 1);
            errdefer self.allocator.free(fields);
            fields[0] = .{ .offset = 0, .ty = array.element };
            return .{
                .kind = .array,
                .size = std.math.mul(u64, stride, array.length) catch return error.LayoutOverflow,
                .alignment = child.alignment,
                .fields = fields,
                .count = array.length,
                .stride = stride,
                .trace = child.trace,
                .drop = child.drop,
                .copy = if (record.contract.move_only) .prohibited else .bytes,
            };
        }
        if (record.shape.domain) |backing| {
            const child = try self.layout(backing);
            const fields = try self.allocator.alloc(Field, 1);
            fields[0] = .{ .offset = 0, .ty = backing };
            var result = child;
            result.kind = .domain;
            result.fields = fields;
            result.count = 1;
            result.stride = 0;
            if (record.contract.move_only) result.copy = .prohibited;
            return result;
        }
        var fields: std.ArrayList(Field) = .empty;
        errdefer fields.deinit(self.allocator);
        var result: Layout = .{ .kind = .record, .size = 0, .alignment = 1, .copy = if (record.contract.move_only) .prohibited else .bytes };
        if (record.shape.variants) |variants| {
            if (try self.niche(variants)) |item| return item;
            result.kind = .variant;
            result.alignment = 4;
            var payload_size: u64 = 0;
            var payload_alignment: u8 = 1;
            for (variants.cases, 0..) |case, tag| if (case.payload) |payload| {
                const child = try self.layout(payload);
                payload_alignment = @max(payload_alignment, child.alignment);
                payload_size = @max(payload_size, child.size);
                result.trace = result.trace or child.trace;
                result.drop = result.drop or child.drop;
                try fields.append(self.allocator, .{ .offset = 0, .ty = payload, .tag = tag });
            };
            result.alignment = @max(result.alignment, payload_alignment);
            result.payload_offset = try alignSize(4, payload_alignment);
            for (fields.items) |*field| field.offset = result.payload_offset;
            result.size = try alignSize(try add(result.payload_offset, payload_size), result.alignment);
        } else {
            for (record.fields) |field| {
                const child = try self.layout(field.ty);
                const offset = try alignSize(result.size, child.alignment);
                try fields.append(self.allocator, .{ .offset = offset, .ty = field.ty });
                result.size = try add(offset, child.size);
                result.alignment = @max(result.alignment, child.alignment);
                result.trace = result.trace or child.trace;
                result.drop = result.drop or child.drop;
            }
            result.size = try alignSize(result.size, result.alignment);
        }
        result.fields = try fields.toOwnedSlice(self.allocator);
        return result;
    }
    /// QBE-NICHE-1: an `Option` whose `Some` payload is a managed reference is
    /// that reference word alone. A managed reference is never null, so the
    /// null word is free to mean `None`; every other optional keeps its
    /// `{tag, payload}` layout, including an optional optional, whose inner
    /// `None` already owns the null word. The single field is the payload at
    /// offset zero, tagged with the `Some` case, exactly where a tagged
    /// variant's field table would put it.
    fn niche(self: *Catalog, variants: typed.Variants) Error!?Layout {
        const shape = @import("prelude.zig").optionCases(variants) orelse return null;
        if ((try self.layout(shape.element)).kind != .managed) return null;
        const fields = try self.allocator.alloc(Field, 1);
        fields[0] = .{ .offset = 0, .ty = shape.element, .tag = shape.some };
        return .{ .kind = .niche, .size = 8, .alignment = 8, .fields = fields, .trace = true };
    }
    /// The fingerprint of one builtin type, computed at most once per catalog.
    /// The memo is keyed by the tag and holds only the digest; the layout the
    /// digest covers is rebuilt from the same switch every time, because it is a
    /// handful of instructions while the digest is a SHA-256. A tag outside the
    /// builtin range cannot arise from `isAggregate`, but one that did would fall
    /// back to computing the digest rather than reading outside the memo.
    fn builtinHash(self: *Catalog, ty: typed.Type, item: Layout) Error!Digest {
        const tag = @backingInt(ty);
        if (tag >= self.builtin_hashes.len) return self.fingerprint(ty, item);
        if (self.builtin_hashes[tag]) |hash| return hash;
        const hash = try self.fingerprint(ty, item);
        self.builtin_hashes[tag] = hash;
        return hash;
    }
    fn fingerprint(self: *Catalog, ty: typed.Type, item: Layout) Error!Digest {
        var hash = std.crypto.hash.sha2.Sha256.init(.{});
        string(&hash, abi_version);
        string(&hash, try self.identity(ty));
        string(&hash, @tagName(item.kind));
        number(&hash, item.size);
        number(&hash, item.alignment);
        number(&hash, item.count);
        number(&hash, item.stride);
        number(&hash, item.payload_offset);
        string(&hash, @tagName(item.copy));
        number(&hash, @intFromBool(item.trace));
        number(&hash, @intFromBool(item.drop));
        number(&hash, item.fields.len);
        for (item.fields) |field| {
            number(&hash, field.offset);
            number(&hash, if (field.tag) |tag| tag + 1 else 0);
            string(&hash, try self.identity(field.ty));
            const child = try self.layout(field.ty);
            hash.update(&child.hash);
        }
        return hash.finalResult();
    }
};
fn add(a: u64, b: u64) Error!u64 {
    return std.math.add(u64, a, b) catch error.LayoutOverflow;
}
fn alignSize(size: u64, alignment: u8) Error!u64 {
    return (try add(size, alignment - 1)) & ~(@as(u64, alignment) - 1);
}
fn number(hash: *std.crypto.hash.sha2.Sha256, value: u64) void {
    var bytes: [8]u8 = undefined;
    std.mem.writeInt(u64, &bytes, value, .little);
    hash.update(&bytes);
}
fn string(hash: *std.crypto.hash.sha2.Sha256, value: []const u8) void {
    number(hash, value.len);
    hash.update(value);
}

const span = @import("source.zig").Span{ .start = 0, .end = 0 };
fn recordType(index: usize) typed.Type {
    return @fromBackingInt(typed.Type.record_base + index);
}
// spec: NATIVE-LAYOUT-MEMO-1
test "a memoized builtin fingerprint equals the freshly computed one for every tag" {
    const fields = [_]typed.Field{ .{ .name = "small", .declaration = span, .ty = .u8 }, .{ .name = "large", .declaration = span, .ty = .i64 } };
    const records = [_]typed.Record{.{ .id = recordType(0), .name = "Point", .declaration = span, .fields = &fields }};
    var memoized = try Catalog.init(std.testing.allocator, &records, &.{"geometry::Point"});
    defer memoized.deinit();
    var fresh = try Catalog.init(std.testing.allocator, &records, &.{"geometry::Point"});
    defer fresh.deinit();
    // Lay the aggregate out first, so its fields fill the memo before the sweep,
    // and again afterwards, so a digest computed with a warm memo cannot differ
    // from one computed with a cold one.
    const aggregate = try memoized.layout(recordType(0));
    for (0..typed.Type.record_base) |tag| {
        const ty: typed.Type = @fromBackingInt(tag);
        const cached = try memoized.layout(ty);
        const computed = try fresh.layout(ty);
        try std.testing.expectEqualSlices(u8, &computed.hash, &cached.hash);
        try std.testing.expectEqual(computed.size, cached.size);
        try std.testing.expectEqual(computed.alignment, cached.alignment);
        try std.testing.expectEqual(computed.kind, cached.kind);
        try std.testing.expectEqual(computed.copy, cached.copy);
    }
    try std.testing.expectEqualSlices(u8, &aggregate.hash, &(try memoized.layout(recordType(0))).hash);
    try std.testing.expectEqualSlices(u8, &(try fresh.layout(recordType(0))).hash, &(try memoized.layout(recordType(0))).hash);
}
test "native concrete widths, padding and nominal identity" {
    const fields = [_]typed.Field{ .{ .name = "small", .declaration = span, .ty = .u8 }, .{ .name = "large", .declaration = span, .ty = .i64 } };
    const records = [_]typed.Record{.{ .id = recordType(0), .name = "Point", .declaration = span, .fields = &fields }};
    var catalog = try Catalog.init(std.testing.allocator, &records, &.{"geometry::Point"});
    defer catalog.deinit();
    const result = try catalog.layout(recordType(0));
    try std.testing.expectEqual(@as(u64, 16), result.size);
    try std.testing.expectEqual(@as(u64, 8), result.fields[1].offset);
    try std.testing.expectEqual(@as(u64, 1), (try catalog.layout(.i8)).size);
    var renamed = try Catalog.init(std.testing.allocator, &records, &.{"other::Point"});
    defer renamed.deinit();
    try std.testing.expect(!std.mem.eql(u8, &result.hash, &(try renamed.layout(recordType(0))).hash));
}
test "managed recursion is a pointer and inline recursion is rejected" {
    const fields = [_]typed.Field{.{ .name = "next", .declaration = span, .ty = recordType(0) }};
    var records = [_]typed.Record{.{ .id = recordType(0), .name = "Node", .declaration = span, .fields = &fields, .managed = true }};
    var catalog = try Catalog.init(std.testing.allocator, &records, &.{"Node"});
    defer catalog.deinit();
    const result = try catalog.layout(recordType(0));
    try std.testing.expect(result.trace);
    try std.testing.expectEqual(@as(u64, 8), result.size);
    records[0].managed = false;
    var inline_catalog = try Catalog.init(std.testing.allocator, &records, &.{"Node"});
    defer inline_catalog.deinit();
    try std.testing.expectError(error.RecursiveLayout, inline_catalog.layout(recordType(0)));
}

test "array stride and union payload metadata" {
    const cases = [_]typed.Variant{ .{ .name = "none", .declaration = span, .payload = null }, .{ .name = "some", .declaration = span, .payload = .i64 } };
    const records = [_]typed.Record{
        .{ .id = recordType(0), .name = "Maybe<i64>", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &cases } } },
        .{ .id = recordType(1), .name = "[3]Maybe<i64>", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = recordType(0), .length = 3 } } },
    };
    var catalog = try Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const variant = try catalog.layout(recordType(0));
    try std.testing.expectEqual(@as(u64, 8), variant.payload_offset);
    try std.testing.expectEqual(@as(u64, 16), variant.size);
    try std.testing.expectEqual(@as(?usize, 1), variant.fields[0].tag);
    const array = try catalog.layout(recordType(1));
    try std.testing.expectEqual(@as(u64, 48), array.size);
    try std.testing.expectEqual(@as(u64, 16), array.stride);
}

// spec: QBE-NICHE-1
test "an option of a managed reference is one nullable word and every other option keeps its tag" {
    const node = recordType(0);
    const maybe_node = recordType(1);
    const maybe_maybe = recordType(2);
    const pair = recordType(3);
    const maybe_pair = recordType(4);
    const either = recordType(5);
    const node_fields = [_]typed.Field{ .{ .name = "left", .declaration = span, .ty = maybe_node }, .{ .name = "right", .declaration = span, .ty = maybe_node } };
    const pair_fields = [_]typed.Field{.{ .name = "x", .declaration = span, .ty = .i64 }};
    const option_node = [_]typed.Variant{ .{ .name = "none", .declaration = span, .payload = null }, .{ .name = "some", .declaration = span, .payload = node } };
    const option_option = [_]typed.Variant{ .{ .name = "some", .declaration = span, .payload = maybe_node }, .{ .name = "none", .declaration = span, .payload = null } };
    const option_pair = [_]typed.Variant{ .{ .name = "none", .declaration = span, .payload = null }, .{ .name = "some", .declaration = span, .payload = pair } };
    const other_names = [_]typed.Variant{ .{ .name = "empty", .declaration = span, .payload = null }, .{ .name = "full", .declaration = span, .payload = node } };
    const records = [_]typed.Record{
        .{ .id = node, .name = "Node", .declaration = span, .fields = &node_fields, .managed = true },
        .{ .id = maybe_node, .name = "Option<Node>", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &option_node } } },
        .{ .id = maybe_maybe, .name = "Option<Option<Node>>", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &option_option } } },
        .{ .id = pair, .name = "Pair", .declaration = span, .fields = &pair_fields },
        .{ .id = maybe_pair, .name = "Option<Pair>", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &option_pair } } },
        .{ .id = either, .name = "Either", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &other_names } } },
    };
    var catalog = try Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const niche = try catalog.layout(maybe_node);
    try std.testing.expectEqual(Kind.niche, niche.kind);
    try std.testing.expectEqual(@as(u64, 8), niche.size);
    try std.testing.expectEqual(@as(u8, 8), niche.alignment);
    try std.testing.expect(niche.trace);
    try std.testing.expectEqual(@as(usize, 1), niche.fields.len);
    try std.testing.expectEqual(@as(u64, 0), niche.fields[0].offset);
    try std.testing.expectEqual(@as(?usize, 1), niche.fields[0].tag);
    // A binary_trees node: two optional children are two words, not two tagged pairs.
    const body = try catalog.heapLayout(node);
    defer catalog.releaseLayout(body);
    try std.testing.expectEqual(@as(u64, 16), body.size);
    try std.testing.expectEqual(@as(u64, 8), body.fields[1].offset);
    // An optional optional keeps its tag: its inner `None` owns the null word.
    const nested = try catalog.layout(maybe_maybe);
    try std.testing.expectEqual(Kind.variant, nested.kind);
    try std.testing.expectEqual(@as(u64, 16), nested.size);
    try std.testing.expectEqual(@as(u64, 8), nested.payload_offset);
    const plain = try catalog.layout(maybe_pair);
    try std.testing.expectEqual(Kind.variant, plain.kind);
    try std.testing.expectEqual(@as(u64, 16), plain.size);
    const named = try catalog.layout(either);
    try std.testing.expectEqual(Kind.variant, named.kind);
    try std.testing.expectEqual(@as(u64, 16), named.size);
}

test "catalog reorder preserves generic layout hashes" {
    const a_fields = [_]typed.Field{.{ .name = "value", .declaration = span, .ty = recordType(1) }};
    const b_fields = [_]typed.Field{.{ .name = "value", .declaration = span, .ty = recordType(0) }};
    const records_a = [_]typed.Record{
        .{ .id = recordType(0), .name = "pkg::Box<pkg::Number>", .declaration = span, .fields = &a_fields },
        .{ .id = recordType(1), .name = "pkg::Number", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } },
    };
    const records_b = [_]typed.Record{
        .{ .id = recordType(0), .name = "pkg::Number", .declaration = span, .fields = &.{}, .shape = .{ .domain = .i64 } },
        .{ .id = recordType(1), .name = "pkg::Box<pkg::Number>", .declaration = span, .fields = &b_fields },
    };
    var a = try Catalog.initRecords(std.testing.allocator, &records_a);
    defer a.deinit();
    var b = try Catalog.initRecords(std.testing.allocator, &records_b);
    defer b.deinit();
    try std.testing.expectEqualSlices(u8, &(try a.layout(recordType(0))).hash, &(try b.layout(recordType(1))).hash);
}

test "array layout overflow and invalid identities fail closed" {
    const records = [_]typed.Record{.{ .id = recordType(0), .name = "Huge", .declaration = span, .fields = &.{}, .shape = .{ .array = .{ .element = .u64, .length = std.math.maxInt(usize) } } }};
    var catalog = try Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    try std.testing.expectError(error.LayoutOverflow, catalog.layout(recordType(0)));
    try std.testing.expectError(error.MissingIdentity, Catalog.init(std.testing.allocator, &records, &.{}));
}

test "native type identity rejects unknown and duplicate declarations" {
    var empty = try Catalog.initRecords(std.testing.allocator, &.{});
    defer empty.deinit();
    try std.testing.expectError(error.InvalidType, empty.layout(recordType(0)));
    try std.testing.expectError(error.InvalidType, empty.identity(recordType(0)));
    const records = [_]typed.Record{
        .{ .id = recordType(0), .name = "duplicate", .declaration = span, .fields = &.{} },
        .{ .id = recordType(1), .name = "duplicate", .declaration = span, .fields = &.{} },
    };
    try std.testing.expectError(error.DuplicateIdentity, Catalog.initRecords(std.testing.allocator, &records));
}

test "heapLayout owns recursive managed record body descriptors" {
    const fields = [_]typed.Field{.{ .name = "next", .declaration = span, .ty = recordType(0) }};
    const records = [_]typed.Record{.{ .id = recordType(0), .name = "Node", .declaration = span, .fields = &fields, .managed = true }};
    var catalog = try Catalog.initRecords(std.testing.allocator, &records);
    defer catalog.deinit();
    const body = try catalog.heapLayout(recordType(0));
    defer catalog.releaseLayout(body);
    try std.testing.expect(body.trace and body.fields.len == 1);
    try std.testing.expectEqual(@as(u64, 8), body.size);
    try std.testing.expectError(error.InvalidType, catalog.heapLayout(.i64));
}
