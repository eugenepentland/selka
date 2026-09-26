//! The physical layout of recursive value types (RECURSIVE-VALUES-2).
//!
//! The checker keeps every field and union case at the value type the program
//! wrote, and marks the ones that close a recursive value type `boxed`. The
//! backend needs a finite layout instead: each boxed field or case holds a
//! pointer to a box, a one-field managed record that is built once and never
//! written. This module derives that view of the record catalog. Types that
//! box nothing keep their schemas, so a program without a recursive value type
//! lowers against exactly the catalog it was checked with.
const std = @import("std");
const typed = @import("typed.zig");

/// Name of the one field a box record holds its value in.
pub const value_field = "value";

/// Whether any schema has a boxed field or union case.
pub fn any(records: []const typed.Record) bool {
    for (records) |schema| if (boxes(schema)) return true;
    return false;
}

fn boxes(schema: typed.Record) bool {
    for (schema.fields) |field| if (field.boxed) return true;
    if (schema.shape.variants) |variants| for (variants.cases) |case| if (case.boxed) return true;
    return false;
}

/// Whether `ty` is a box record of the physical catalog.
pub fn isBox(records: []const typed.Record, ty: typed.Type) bool {
    return ty.isAggregate() and ty.recordIndex() < records.len and records[ty.recordIndex()].collection.box;
}

/// The catalog as the backend lays it out: the checked schemas, in their own
/// positions, with each boxed field's type and each boxed case's payload
/// replaced by a box record of that value type, and one box record per boxed
/// value type appended after them. A boxed field or case keeps its `boxed`
/// mark, so lowering knows to build the box on the way in and read through it
/// on the way out. Without a boxed schema the input itself is returned.
pub fn physical(allocator: std.mem.Allocator, records: []const typed.Record) std.mem.Allocator.Error![]const typed.Record {
    if (!any(records)) return records;
    var out: std.ArrayList(typed.Record) = .empty;
    try out.appendSlice(allocator, records);
    var box_of: std.array_hash_map.Auto(typed.Type, typed.Type) = .empty;
    defer box_of.deinit(allocator);
    for (records, 0..) |schema, index| {
        if (!boxes(schema)) continue;
        var copy = schema;
        if (schema.fields.len != 0) {
            const fields = try allocator.dupe(typed.Field, schema.fields);
            for (fields) |*field| if (field.boxed) {
                field.ty = try boxType(allocator, &out, &box_of, field.ty);
            };
            copy.fields = fields;
        }
        if (schema.shape.variants) |variants| {
            const cases = try allocator.dupe(typed.Variant, variants.cases);
            for (cases) |*case| if (case.boxed) {
                case.payload = try boxType(allocator, &out, &box_of, case.payload.?);
            };
            copy.shape.variants = .{ .fallible = variants.fallible, .is_union = variants.is_union, .cases = cases };
        }
        out.items[index] = copy;
    }
    return out.toOwnedSlice(allocator);
}

/// The box record holding a `content` value, appended on first use. Its name
/// is the content's canonical name inside `box<...>`, which no declaration can
/// spell, so native identities stay unique and stable across compilations.
fn boxType(allocator: std.mem.Allocator, out: *std.ArrayList(typed.Record), box_of: *std.array_hash_map.Auto(typed.Type, typed.Type), content: typed.Type) std.mem.Allocator.Error!typed.Type {
    if (box_of.get(content)) |found| return found;
    const schema = out.items[content.recordIndex()];
    const ty: typed.Type = @fromBackingInt(typed.Type.record_base + out.items.len);
    const fields = try allocator.dupe(typed.Field, &.{.{ .name = value_field, .declaration = schema.declaration, .ty = content }});
    try out.append(allocator, .{
        .id = ty,
        .name = try std.fmt.allocPrint(allocator, "box<{s}>", .{schema.name}),
        .declaration = schema.declaration,
        .fields = fields,
        .managed = true,
        .collection = .{ .box = true },
        .contract = .{ .public_arguments = schema.contract.public_arguments },
    });
    try box_of.put(allocator, content, ty);
    return ty;
}

const span: @import("source.zig").Span = .{ .start = 0, .end = 0 };
fn recordType(index: usize) typed.Type {
    return @fromBackingInt(typed.Type.record_base + index);
}
// spec: RECURSIVE-VALUES-2
test "the physical catalog boxes each recursive payload once and leaves other schemas alone" {
    const allocator = std.testing.allocator;
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // union List: nil, cons: Cell  /  record Cell: head: int, tail: List
    const cases = [_]typed.Variant{
        .{ .name = "nil", .declaration = span, .payload = null },
        .{ .name = "cons", .declaration = span, .payload = recordType(1), .boxed = true },
    };
    const cell = [_]typed.Field{ .{ .name = "head", .declaration = span, .ty = .i64 }, .{ .name = "tail", .declaration = span, .ty = recordType(0) } };
    const records = [_]typed.Record{
        .{ .id = recordType(0), .name = "List", .declaration = span, .fields = &.{}, .shape = .{ .variants = .{ .is_union = true, .cases = &cases } } },
        .{ .id = recordType(1), .name = "Cell", .declaration = span, .fields = &cell },
    };
    const view = try physical(a, &records);
    try std.testing.expectEqual(@as(usize, 3), view.len);
    const box = view[0].shape.variants.?.cases[1].payload.?;
    try std.testing.expectEqual(recordType(2), box);
    try std.testing.expect(isBox(view, box));
    try std.testing.expect(view[2].managed);
    try std.testing.expectEqualStrings("box<Cell>", view[2].name);
    try std.testing.expectEqual(recordType(1), view[2].fields[0].ty);
    // The checked schemas are untouched, and a schema that boxes nothing is shared.
    try std.testing.expectEqual(recordType(1), records[0].shape.variants.?.cases[1].payload.?);
    try std.testing.expectEqual(records[1].fields.ptr, view[1].fields.ptr);
    const plain = [_]typed.Record{records[1]};
    try std.testing.expectEqual(@as([*]const typed.Record, &plain), (try physical(a, &plain)).ptr);
}
