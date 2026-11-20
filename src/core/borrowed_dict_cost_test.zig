//! F18: a read-only borrowed dictionary (`const table = record.table`) is a `borrowed` overlay of its dictionary
//! type. The allocation classifier, the noalloc contract, the ownership pass and the view materialization read
//! the table through `Module.dictShape`, never `compound(ty).dict`, whose member is not active on an overlay.
const std = @import("std");
const ir = @import("ir.zig");
const cost = @import("cost.zig");
const build = @import("build.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const contracts = @import("allocation_contract.zig");
const language = @import("selka");

/// A function whose instructions are one parameter of each type in `types`, so instruction `i` has type `types[i]`.
fn parameters(a: std.mem.Allocator, types: []const ir.Type) !ir.Function {
    var function: ir.Function = .{ .name = "probe", .signature = .{ .params = &.{}, .ret = .void } };
    for (types, 0..) |ty, index| try function.insts.append(a, .{ .op = .param, .ty = ty, .data = index });
    return function;
}

/// A `dict_find` of the dictionary held by instruction `index`.
fn probe(index: u32) ir.Inst {
    return .{ .op = .dict_find, .ty = .i64, .a = @fromBackingInt(index) };
}

test "dictShape reads a borrowed overlay through its storage type and answers null for any other type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const table = try module.intern(a, .{ .dict = .{ .key = .str, .value = .i64 } });
    const overlay = try module.borrowedType(a, table);
    const list = try module.intern(a, .{ .list = .i64 });
    const list_overlay = try module.borrowedType(a, list);
    try std.testing.expectEqual(ir.Type.str, module.dictShape(table).?.key);
    try std.testing.expectEqual(ir.Type.str, module.dictShape(overlay).?.key);
    try std.testing.expectEqual(ir.Type.i64, module.dictShape(overlay).?.value);
    try std.testing.expect(module.dictShape(list) == null);
    try std.testing.expect(module.dictShape(list_overlay) == null);
    try std.testing.expect(module.dictShape(.i64) == null);
}

test "allocation classifies a dict_find on a borrowed dictionary by the key of the dictionary it borrows" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var module: ir.Module = .{};
    const scalar = try module.intern(a, .{ .dict = .{ .key = .i64, .value = .i64 } });
    const text = try module.intern(a, .{ .dict = .{ .key = .str, .value = .i64 } });
    const point = try module.intern(a, .{ .record = &.{ .i64, .i64 } });
    const compound = try module.intern(a, .{ .dict = .{ .key = point, .value = .i64 } });
    const types = [_]ir.Type{
        try module.borrowedType(a, scalar), try module.borrowedType(a, text), try module.borrowedType(a, compound),
        scalar,                             text,                             compound,
        .i64,
    };
    const function = try parameters(a, &types);
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, probe(0)));
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, probe(1)));
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, probe(2)));
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, probe(3)));
    try std.testing.expectEqual(cost.Allocation.never, cost.allocation(&module, &function, probe(4)));
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, probe(5)));
    // An operand that is no dictionary is refused by the verifier; the classifier stays conservative.
    try std.testing.expectEqual(cost.Allocation.may, cost.allocation(&module, &function, probe(6)));
}

const integer_key =
    \\record Holder:
    \\    table: dict[int, int]
    \\func read(h: Holder, key: int) -> int:
    \\    const table = h.table
    \\    return table[key]
    \\func main(out: Stream) -> int:
    \\    mut table: dict[int, int] = {1: 3}
    \\    const h = Holder(table=own table)
    \\    print(out, read(h, 1))
    \\    return 0
;

const text_key =
    \\record Holder:
    \\    table: dict[str, int]
    \\func read(h: Holder, key: str) -> int:
    \\    const table = h.table
    \\    return table[key]
    \\func main(out: Stream) -> int:
    \\    mut table: dict[str, int] = {"a": 3}
    \\    const h = Holder(table=own table)
    \\    print(out, read(h, "a"))
    \\    return 0
;

const record_key =
    \\record Point:
    \\    x: int
    \\    y: int
    \\record Holder:
    \\    table: dict[Point, int]
    \\func read(h: Holder, key: Point) -> int:
    \\    const table = h.table
    \\    return table[key]
    \\func main(out: Stream) -> int:
    \\    mut table: dict[Point, int] = {Point(x=1, y=2): 3}
    \\    const h = Holder(table=own table)
    \\    print(out, read(h, Point(x=1, y=2)))
    \\    return 0
;

const local_alias =
    \\func main(out: Stream) -> int:
    \\    mut table: dict[str, int] = {"a": 3}
    \\    const alias = table
    \\    print(out, alias["a"])
    \\    return 0
;

/// The allocation sites `selka cost` counts in `function` after the optimizing passes, or after the debug ones.
fn sites(a: std.mem.Allocator, source: []const u8, function: []const u8, optimized: bool) !u32 {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a, source, &refusal);
    const result = if (optimized) try support.runPasses(a, &module, .trusted) else try passes.debug(a, &module);
    const report = try cost.measure(a, &module, &result, function);
    return report.totals.allocation.sites;
}

test "cost measures a probe of a borrowed dictionary without reading the wrong member" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(u32, 0), try sites(a, integer_key, "read", true));
    try std.testing.expectEqual(@as(u32, 0), try sites(a, integer_key, "read", false));
    try std.testing.expectEqual(@as(u32, 0), try sites(a, text_key, "read", true));
    try std.testing.expectEqual(@as(u32, 0), try sites(a, text_key, "read", false));
    try std.testing.expectEqual(@as(u32, 1), try sites(a, record_key, "read", true));
    try std.testing.expectEqual(@as(u32, 1), try sites(a, record_key, "read", false));
}

test "cost measures a probe of a borrowed alias of a local dictionary" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    // The dictionary literal is two sites (a construction and an insert); the probe through the alias adds none.
    try std.testing.expectEqual(@as(u32, 2), try sites(a, local_alias, "main", true));
    try std.testing.expectEqual(@as(u32, 2), try sites(a, local_alias, "main", false));
}

const noalloc_integer_key =
    \\record Holder:
    \\    table: dict[int, int]
    \\@noalloc
    \\func read(h: Holder, key: int) -> int:
    \\    const table = h.table
    \\    return table[key]
;

const noalloc_text_key =
    \\record Holder:
    \\    table: dict[str, int]
    \\@noalloc
    \\func read(h: Holder, key: str) -> int:
    \\    const table = h.table
    \\    return table[key]
;

const noalloc_record_key =
    \\record Point:
    \\    x: int
    \\    y: int
    \\record Holder:
    \\    table: dict[Point, int]
    \\@noalloc
    \\func read(h: Holder, key: Point) -> int:
    \\    const table = h.table
    \\    return table[key]
;

/// How many noalloc promises of the library `source` the contract check refuses.
fn refused(a: std.mem.Allocator, source: []const u8) !usize {
    var compilation = try language.Compilation.init(a, "contract.selka", source);
    const program = try compilation.checkLibraryProgram();
    const failures = try contracts.collectProgram(a, program, compilation.src);
    return failures.len;
}

test "a noalloc promise over a borrowed dictionary probe is judged by the key type" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    try std.testing.expectEqual(@as(usize, 0), try refused(a, noalloc_integer_key));
    try std.testing.expectEqual(@as(usize, 0), try refused(a, noalloc_text_key));
    try std.testing.expectEqual(@as(usize, 1), try refused(a, noalloc_record_key));
}

test "the ownership pass accepts the items of a borrowed dictionary with unit keys" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(a,
        \\import dicts
        \\record Holder:
        \\    table: dict[Unit, int]
        \\func total(h: Holder) -> int:
        \\    const table = h.table
        \\    mut sum = 0
        \\    for item in dicts.items(table):
        \\        sum += item.value
        \\    return sum
        \\func main(out: Stream) -> int:
        \\    mut table: dict[Unit, int] = {}
        \\    const h = Holder(table=own table)
        \\    print(out, total(h))
        \\    return 0
    , &refusal);
    _ = try passes.debug(a, &module);
    try std.testing.expect(module.functions.items.len != 0);
}
