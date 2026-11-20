//! Structural equality descriptors exclude unrelated transient borrowed layouts.
const std = @import("std");
const ir = @import("ir.zig");
const equality = @import("build_equality.zig");
const values = @import("emit_values.zig");
const support = @import("test_support.zig");

const Fixture = struct { module: ir.Module, ordinary: ir.Type, overlay: ir.Type, recursive: ir.Type, transients: []const ir.Type };

fn adapter(a: std.mem.Allocator, ty: ir.Type) !ir.Function {
    return .{
        .name = try support.fixtureName(a, equality.prefix, ty),
        .signature = .{ .params = try a.dupe(ir.Type, &.{ ty, ty }), .ret = .bool, .linkage = .runtime_c },
    };
}

fn fixture(a: std.mem.Allocator) !Fixture {
    var module: ir.Module = .{};
    const list = try module.intern(a, .{ .list = .i64 });
    const ordinary = try module.intern(a, .{ .record = &.{ list, .str } });
    const overlay = try module.borrowedType(a, ordinary);
    const optional = try module.option(a, .str_view);
    const bytes_result = try module.intern(a, .{ .@"union" = &.{ .bytes_view, .str } });
    const list_view = try module.intern(a, .{ .list_view = .i64 });
    const list_result = try module.intern(a, .{ .@"union" = &.{ list_view, .str } });
    const nested = try module.intern(a, .{ .record = &.{ optional, list_result } });
    const array = try module.intern(a, .{ .array = .{ .elem = optional, .n = 2 } });
    // The catalog closes boxed cycles without following an arbitrary depth bound.
    const recursive: ir.Type = @fromBackingInt(ir.Type.first_compound + @as(u32, @intCast(module.compounds.items.len)));
    const box: ir.Type = @fromBackingInt(@backingInt(recursive) + 1);
    try module.compounds.appendSlice(a, &.{ .{ .@"union" = try a.dupe(ir.Type, &.{ .str, box }) }, .{ .box = recursive } });
    const transient_cycle: ir.Type = @fromBackingInt(@backingInt(box) + 1);
    const transient_box: ir.Type = @fromBackingInt(@backingInt(transient_cycle) + 1);
    try module.compounds.appendSlice(a, &.{ .{ .@"union" = try a.dupe(ir.Type, &.{ .str_view, transient_box }) }, .{ .box = transient_cycle } });
    try module.functions.append(a, try adapter(a, ordinary));
    return .{
        .module = module,
        .ordinary = ordinary,
        .overlay = overlay,
        .recursive = recursive,
        .transients = try a.dupe(ir.Type, &.{ optional, bytes_result, list_view, list_result, nested, array, transient_cycle, transient_box }),
    };
}

fn descriptorName(a: std.mem.Allocator, ids: @import("type_ids.zig").Table, ty: ir.Type) ![]const u8 {
    return std.fmt.allocPrint(a, "@myl.value.{s} =", .{ids.text(ty)});
}

test "O3 equality descriptors ignore unrelated borrowed result wrappers and preserve owned overlays" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sample = try fixture(a);
    try equality.validateModule(a, &sample.module);
    var text: std.ArrayList(u8) = .empty;
    const ids = try @import("type_ids.zig").Table.build(a, &sample.module);
    try values.descriptorsWith(a, &sample.module, ids, &text);
    try std.testing.expect(std.mem.indexOf(u8, text.items, try descriptorName(a, ids, sample.ordinary)) != null);
    try std.testing.expect(std.mem.indexOf(u8, text.items, try descriptorName(a, ids, sample.overlay)) != null);
    try std.testing.expect(std.mem.indexOf(u8, text.items, try descriptorName(a, ids, sample.recursive)) != null);
    try std.testing.expect(std.mem.indexOf(u8, text.items, try descriptorName(a, ids, .str_view)) == null);
    try std.testing.expect(std.mem.indexOf(u8, text.items, try descriptorName(a, ids, .bytes_view)) == null);
    for (sample.transients) |ty| try std.testing.expect(std.mem.indexOf(u8, text.items, try descriptorName(a, ids, ty)) == null);
    sample.module.functions.items[0] = try adapter(a, sample.overlay);
    try equality.validateModule(a, &sample.module);
    const catalog = try @import("emit_constants.zig").Catalog.init(a, &sample.module);
    const selected = try std.fmt.allocPrint(a, "@selected = private constant ptr @myl.value.{s}\n", .{catalog.ids.text(sample.overlay)});
    const closed = try catalog.finish(a, selected);
    try std.testing.expect(std.mem.indexOf(u8, closed, "@selected") != null);
}

test "O3 equality descriptors refuse actual transient equality roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sample = try fixture(a);
    for (sample.transients) |ty| {
        sample.module.functions.items[0] = try adapter(a, ty);
        try std.testing.expectError(error.UnsupportedInstruction, equality.validateModule(a, &sample.module));
        var text: std.ArrayList(u8) = .empty;
        try std.testing.expectError(error.UnsupportedInstruction, values.descriptors(a, &sample.module, &text));
    }
}

test "O3 equality descriptors refuse unsupported dynamic dictionary key roots" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var sample = try fixture(a);
    const list_view = sample.transients[2];
    _ = try sample.module.intern(a, .{ .dict = .{ .key = list_view, .value = .i64 } });
    var text: std.ArrayList(u8) = .empty;
    try std.testing.expectError(error.UnsupportedInstruction, values.descriptors(a, &sample.module, &text));
}

fn descriptorTypesAllocations(a: std.mem.Allocator, module: *const ir.Module) !void {
    const ordinary = try equality.descriptorTypes(a, module);
    defer a.free(ordinary);
    try std.testing.expect(ordinary[1]);
    try std.testing.expect(!ordinary[3]);
}

test "O3 descriptorTypes releases partial graph allocations on every failure" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var sample = try fixture(arena.allocator());
    var stable = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(stable.allocator(), descriptorTypesAllocations, .{&sample.module});
    sample.module.compounds.items[1] = .{ .record = &.{@fromBackingInt(99999)} };
    try std.testing.expectError(error.UnsupportedInstruction, equality.descriptorTypes(arena.allocator(), &sample.module));
}

test "O3 equality emits ordinary comparisons beside optional borrowed calls and rendering" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const text = try support.llvmText(arena.allocator(),
        \\record Row:
        \\    items: int[]
        \\func same(left: Row, right: Row) -> bool:
        \\    return left == right
        \\func maybe(value: str) -> str? from value:
        \\    return Some(value[0:1])
        \\func main(out: Stream) -> int:
        \\    const left = Row(items=[1, 2])
        \\    const right = Row(items=[1, 2])
        \\    assert same(left, right)
        \\    const text = "hello"
        \\    match maybe(text):
        \\        case Some(part):
        \\            assert len(part) == 1
        \\        case None:
        \\            assert False
        \\    print(out, f"{left}")
        \\    return 0
    );
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl_core_values_equal") != null);
    try std.testing.expect(std.mem.indexOf(u8, text, "@myl.render.") != null);
}
