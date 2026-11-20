//! The stable names of a checked program's records (docs/design/incremental-engine.md §17.1, part 2 step G3a2).
//!
//! A nominal record or union is a position in `Program.records` for the checker and for lowering, and a position moves
//! when an earlier record is added. `RecordIndex` names each record by the key path of its module, its checked name
//! and an ordinal among the records that share both, and finds a record by that name again. The op log (`op_log.zig`)
//! and the lowering artifacts built from it hold the names, never the positions.
const std = @import("std");
const language = @import("selka");
const typed = language.typed;
const names = @import("stable_names.zig");
const fast_blake3 = @import("fast_blake3.zig");

/// The key path of the module whose source holds merged offset `start`; empty without a source or outside every module.
pub fn moduleOf(source: ?language.source.Source, start: usize) []const u8 {
    const merged = source orelse return "";
    if (merged.origins.len == 0) return merged.keyPath();
    const at = merged.originalSpan(.{ .start = start, .end = start }) catch return "";
    return merged.origins[at.input].original.keyPath();
}

/// The module a record is named under. An ordinary record belongs to the module that declares it. A generic instance
/// (`Result<str,strings::Error>`, `Box<i64>`) is spelled where the program first needs it, and which module that is depends on
/// the program: named under it, the same instance would have one name in one program and another in the next, and no stored
/// result that holds it could be shared. An instance has no home module: its checked name carries its type arguments and the
/// qualification of the generic.
pub fn homeOf(source: ?language.source.Source, record: typed.Record) []const u8 {
    if (std.mem.indexOfScalar(u8, record.name, '<') != null) return "";
    return moduleOf(source, record.declaration.start);
}

/// Every record of one checked program, by name and by position.
pub const RecordIndex = struct {
    /// The name of each record, by record index.
    by_position: []names.RecordName,
    by_name: std.HashMapUnmanaged(names.RecordName, u32, names.RecordNameContext, std.hash_map.default_max_load_percentage),
    /// How many records share their module and name with an earlier record.
    ambiguous: u32,

    /// Name every record of `program`. The names borrow from `source` and `program`; the table is allocated in `a`.
    pub fn init(a: std.mem.Allocator, program: typed.Program, source: ?language.source.Source) std.mem.Allocator.Error!RecordIndex {
        var self: RecordIndex = .{ .by_position = try a.alloc(names.RecordName, program.records.len), .by_name = .empty, .ambiguous = 0 };
        errdefer a.free(self.by_position);
        try self.by_name.ensureTotalCapacity(a, @intCast(program.records.len));
        for (program.records, self.by_position, 0..) |record, *slot, position| {
            var name: names.RecordName = .{ .module = homeOf(source, record), .name = record.name };
            while (self.by_name.contains(name)) {
                name.ordinal += 1;
                self.ambiguous += @intFromBool(name.ordinal == 1);
            }
            slot.* = name;
            self.by_name.putAssumeCapacity(name, @intCast(position));
        }
        return self;
    }

    /// The name of the record `ty` stands for, or null when `ty` is no record of the program.
    pub fn nameOf(self: *const RecordIndex, ty: typed.Type) ?names.RecordName {
        if (!ty.isAggregate() or ty.recordIndex() >= self.by_position.len) return null;
        return self.by_position[ty.recordIndex()];
    }

    /// The index's own copy of `name`, whose strings live as long as the program does, or null for an unknown record.
    pub fn canonical(self: *const RecordIndex, name: names.RecordName) ?names.RecordName {
        const position = self.by_name.get(name) orelse return null;
        return self.by_position[position];
    }

    /// The checked type of the record called `name`, or null when the program has no such record.
    pub fn find(self: *const RecordIndex, program: typed.Program, name: names.RecordName) ?typed.Type {
        const position = self.by_name.get(name) orelse return null;
        return program.records[position].id;
    }
};

/// The digest of each record's stable name, by record index, and the record each digest names. A lowering key hashes a
/// record type by its digest, never by its position in the checked program's record table, so a record added before it
/// moves no key (part 2 step G3b3). The digest covers the name only; what the record holds is the record's own digest in
/// the key's reach.
pub const RecordKeys = struct {
    /// The digest of each record's name, by record index.
    digests: []const Digest,
    /// The index of the record each digest names.
    by_digest: std.AutoHashMapUnmanaged(Digest, u32),

    /// A name digest: 32 bytes of Blake3 over the module, the checked name and the ordinal.
    pub const Digest = [32]u8;

    /// Name every record of `program` and digest the names. The tables are allocated in `a`.
    pub fn init(a: std.mem.Allocator, program: typed.Program, source: ?language.source.Source) std.mem.Allocator.Error!RecordKeys {
        var index = try RecordIndex.init(a, program, source);
        defer index.by_name.deinit(a);
        defer a.free(index.by_position);
        const digests = try a.alloc(Digest, program.records.len);
        errdefer a.free(digests);
        var self: RecordKeys = .{ .digests = digests, .by_digest = .empty };
        try self.by_digest.ensureTotalCapacity(a, @intCast(digests.len));
        for (index.by_position, digests, 0..) |name, *slot, position| {
            slot.* = digestOf(name);
            self.by_digest.putAssumeCapacity(slot.*, @intCast(position));
        }
        return self;
    }

    /// The digest of a record name.
    pub fn digestOf(name: names.RecordName) Digest {
        var hash = fast_blake3.Blake3.init(.{});
        hash.update("record-name-v1\x00");
        hash.update(name.module);
        hash.update("\x00");
        hash.update(name.name);
        hash.update("\x00");
        const ordinal = std.mem.nativeToLittle(u32, name.ordinal);
        hash.update(std.mem.asBytes(&ordinal));
        var out: Digest = undefined;
        hash.final(&out);
        return out;
    }

    /// The digest of the record `ty` stands for, or null when `ty` is no record of the program.
    pub fn digestOfType(self: *const RecordKeys, ty: typed.Type) ?Digest {
        if (!ty.isAggregate() or ty.recordIndex() >= self.digests.len) return null;
        return self.digests[ty.recordIndex()];
    }

    /// The index of the record a digest names, or null when the program has no such record.
    pub fn find(self: *const RecordKeys, digest: Digest) ?u32 {
        return self.by_digest.get(digest);
    }
};

test "record keys digest each record by its name and not by its position" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const span: language.source.Span = .{ .start = 0, .end = 0 };
    const first: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Pair", .declaration = span, .fields = &.{} };
    const second: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base + 1), .name = "Other", .declaration = span, .fields = &.{} };
    const moved: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base + 1), .name = "Pair", .declaration = span, .fields = &.{} };
    const before: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0), .records = &.{ first, second } };
    const after: typed.Program = .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0), .records = &.{ second, moved } };
    const left = try RecordKeys.init(a, before, null);
    const right = try RecordKeys.init(a, after, null);
    try std.testing.expectEqualSlices(u8, &left.digests[0], &right.digests[1]);
    try std.testing.expect(!std.mem.eql(u8, &left.digests[0], &left.digests[1]));
    try std.testing.expectEqual(@as(?u32, 1), right.find(left.digests[0]));
    try std.testing.expectEqual(@as(?u32, 1), left.find(right.digests[0]));
    try std.testing.expectEqual(@as(?[32]u8, null), left.digestOfType(@fromBackingInt(typed.Type.record_base + 5)));
}

test "a generic instance is named under no module, so two programs that spell it in different modules name it alike" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const one: language.source.Source = .{ .path = "one.selka", .bytes = "0123456789", .line_starts = &.{} };
    const two: language.source.Source = .{ .path = "two.selka", .bytes = "0123456789", .line_starts = &.{} };
    const merged_one: language.source.Source = .{ .path = "<project>", .bytes = "", .line_starts = &.{}, .origins = &.{ .{ .start = 0, .original = one }, .{ .start = 20, .original = two } } };
    const here: language.source.Span = .{ .start = 2, .end = 3 };
    const there: language.source.Span = .{ .start = 22, .end = 23 };
    const instance_in_one: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Result<str,strings::Error>", .declaration = here, .fields = &.{} };
    const instance_in_two: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Result<str,strings::Error>", .declaration = there, .fields = &.{} };
    const plain_in_one: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Pair", .declaration = here, .fields = &.{} };
    const plain_in_two: typed.Record = .{ .id = @fromBackingInt(typed.Type.record_base), .name = "Pair", .declaration = there, .fields = &.{} };
    const first = try RecordKeys.init(a, .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0), .records = &.{instance_in_one} }, merged_one);
    const second = try RecordKeys.init(a, .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0), .records = &.{instance_in_two} }, merged_one);
    try std.testing.expectEqualSlices(u8, &first.digests[0], &second.digests[0]);
    const plain_first = try RecordKeys.init(a, .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0), .records = &.{plain_in_one} }, merged_one);
    const plain_second = try RecordKeys.init(a, .{ .nodes = &.{}, .statements = &.{}, .functions = &.{}, .main = @fromBackingInt(0), .records = &.{plain_in_two} }, merged_one);
    try std.testing.expect(!std.mem.eql(u8, &plain_first.digests[0], &plain_second.digests[0]));
}
