//! Descriptor names follow a type's identity, never its position in the module's type table (G4a step 2a).
const std = @import("std");
const ir = @import("ir.zig");
const constants = @import("emit_constants.zig");
const type_ids = @import("type_ids.zig");
const identity = @import("canonical_ir.zig");
const equality = @import("build_equality.zig");
const source_location = @import("source_location.zig");

const World = struct { module: ir.Module, record: ir.Type, list: ir.Type, dict: ir.Type };

fn compound(ordinal: usize) ir.Type {
    return @fromBackingInt(@as(u32, @intCast(ir.Type.first_compound + ordinal)));
}

/// A module with one record, a list of it and a dictionary keyed by a float (so a descriptor catalog exists). `before` unrelated
/// types come first in the table, so every type after them has another ordinal.
fn world(a: std.mem.Allocator, before: usize) !World {
    var module: ir.Module = .{};
    for (0..before) |index| try module.compounds.append(a, if (index % 2 == 0) .{ .list = .str } else .{ .box = .i64 });
    const record = compound(module.compounds.items.len);
    try module.compounds.appendSlice(a, &.{ .{ .record = &.{ .i64, .str } }, .{ .list = record }, .{ .dict = .{ .key = .f64, .value = record } } });
    return .{ .module = module, .record = record, .list = compound(@backingInt(record) - ir.Type.first_compound + 1), .dict = compound(@backingInt(record) - ir.Type.first_compound + 2) };
}

fn definition(a: std.mem.Allocator, catalog: constants.Catalog, ty: ir.Type) ![]const u8 {
    const name = try std.fmt.allocPrint(a, "myl.value.{s}", .{catalog.ids.text(ty)});
    return catalog.globals.get(name).?;
}

fn nowhere(_: *const anyopaque, _: u32) source_location.Location {
    return .{ .line = 0, .column = 0 };
}

test "a type added before another leaves the other's id, descriptor and reached closure as they were" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const plain = try world(a, 0);
    const shifted = try world(a, 3);
    const first = try constants.Catalog.init(a, &plain.module);
    const second = try constants.Catalog.init(a, &shifted.module);
    try std.testing.expect(plain.record != shifted.record);
    try std.testing.expectEqualSlices(u8, &first.ids.text(plain.record), &second.ids.text(shifted.record));
    try std.testing.expectEqualSlices(u8, &first.ids.text(plain.dict), &second.ids.text(shifted.dict));
    try std.testing.expectEqualStrings(try definition(a, first, plain.list), try definition(a, second, shifted.list));
    try std.testing.expectEqualStrings(try definition(a, first, plain.dict), try definition(a, second, shifted.dict));
    const reach = try std.fmt.allocPrint(a, "@selected = private constant ptr @myl.value.{s}\n", .{first.ids.text(plain.dict)});
    const moved = try std.fmt.allocPrint(a, "@selected = private constant ptr @myl.value.{s}\n", .{second.ids.text(shifted.dict)});
    try std.testing.expectEqualStrings(try first.finish(a, reach), try second.finish(a, moved));
    try std.testing.expect(!std.mem.eql(u8, &first.ids.text(plain.record), &first.ids.text(plain.list)));
}

test "no descriptor name carries an ordinal of the module's tables" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const sample = try world(a, 5);
    const catalog = try constants.Catalog.init(a, &sample.module);
    var names = catalog.globals.keyIterator();
    const dotted = names.next().?.*;
    const ordinal = try std.fmt.allocPrint(a, "myl.value.{d}", .{@backingInt(sample.record)});
    try std.testing.expect(catalog.globals.get(ordinal) == null);
    try std.testing.expect(std.mem.startsWith(u8, dotted, "myl."));
    try std.testing.expectEqual(@as(usize, 32), catalog.ids.text(sample.record).len);
}

test "a body that calls an equality marker still has a known reference digest, the same wherever the marker's type sits" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var plain = try world(a, 0);
    var shifted = try world(a, 4);
    const marker = equality.prefix ++ "0123456789abcdef0123456789abcdef";
    try plain.module.functions.append(a, .{ .name = marker, .signature = .{ .params = &.{ plain.record, plain.record }, .ret = .bool, .linkage = .runtime_c } });
    try shifted.module.functions.append(a, .{ .name = marker, .signature = .{ .params = &.{ shifted.record, shifted.record }, .ret = .bool, .linkage = .runtime_c } });
    const locator: source_location.Locator = .{ .context = &plain, .locate = nowhere };
    var first = try identity.Canon.prepare(a, &plain.module, locator);
    var second = try identity.Canon.prepare(a, &shifted.module, locator);
    try std.testing.expectEqualSlices(u8, &try first.callee(0), &try second.callee(0));
}

test "an equality adapter named by a type's ordinal is no adapter: its name is a plain name" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sample = try world(a, 0);
    try sample.module.functions.append(a, .{ .name = "myl_core_equal_16", .signature = .{ .params = &.{ sample.record, sample.record }, .ret = .bool, .linkage = .runtime_c } });
    const generated = @import("emit_values.zig").generated(&sample.module.functions.items[0]);
    try std.testing.expect(!generated);
}
