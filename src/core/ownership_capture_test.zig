//! The table of owners the ownership pass keeps (docs/design/ownership-certificates.md, package C1.2): its states
//! match the schedule it made, and it covers exactly the instructions the pass analysed.
const std = @import("std");
const ir = @import("ir.zig");
const own = @import("own.zig");
const passes = @import("passes.zig");
const support = @import("test_support.zig");
const certificate = @import("ownership_certificate.zig");
const build = @import("build.zig");

const source =
    \\record Row:
    \\    items: int[]
    \\    name: str
    \\
    \\func grow(own r: Row) -> Row:
    \\    mut rows = own r
    \\    append(mut rows.items, 3)
    \\    return rows
    \\
    \\func width(text: str) -> int:
    \\    return len(text)
    \\
    \\func main(out: Stream) -> int:
    \\    const r = Row(items=[1, 2], name="x")
    \\    const g = grow(own r)
    \\    print(out, len(g.items), g.name, width("abc"))
    \\    return 0
;

/// The module of `source` after the release passes, with the tables the ownership pass kept.
fn kept(arena: std.mem.Allocator, sink: *certificate.Sink) !ir.Module {
    var refusal: build.Refusal = .{};
    var module = try support.buildSource(arena, source, &refusal);
    var stopped: own.Refusal = .{ .certificates = sink };
    _ = try (passes.Reporting{ .arena = arena, .backing = arena, .module = &module, .refusal = &stopped }).runWithScratch(.trusted);
    return module;
}

fn functionIndex(module: *const ir.Module, name: []const u8) u32 {
    for (module.functions.items, 0..) |function, i| if (std.mem.eql(u8, function.name, name)) return @intCast(i);
    unreachable;
}

/// How many instructions of `function` with operation `op` have state `state` in `table`.
fn countWith(function: *const ir.Function, table: certificate.Capture, op: ir.Op, state: certificate.State) usize {
    var found: usize = 0;
    for (function.insts.items, 0..) |inst, i| {
        if (inst.op == op and table.state(i) == state) found += 1;
    }
    return found;
}

test "the pass keeps a table for every internal function and none for a runtime helper" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var sink: certificate.Sink = .{};
    const module = try kept(arena.allocator(), &sink);
    try std.testing.expect(sink.get(functionIndex(&module, "grow")) != null);
    try std.testing.expect(sink.get(functionIndex(&module, "main")) != null);
    try std.testing.expectEqual(@as(?certificate.Capture, null), sink.get(@intCast(module.functions.items.len)));
}

test "an owned record parameter is owned and the field read that takes the list is owned too" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var sink: certificate.Sink = .{};
    const module = try kept(arena.allocator(), &sink);
    const index = functionIndex(&module, "grow");
    const table = sink.get(index).?;
    const function = &module.functions.items[index];
    try std.testing.expectEqual(@as(usize, 1), countWith(function, table, .param, .owned));
    try std.testing.expectEqual(@as(usize, 1), countWith(function, table, .record_get, .owned));
    try std.testing.expectEqual(@as(usize, 1), countWith(function, table, .record_set, .owned));
}

test "a record whose managed fields were all read out is emptied and a borrowed parameter has no table parents" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var sink: certificate.Sink = .{};
    const module = try kept(arena.allocator(), &sink);
    const main_index = functionIndex(&module, "main");
    const main_table = sink.get(main_index).?;
    try std.testing.expectEqual(@as(usize, 1), countWith(&module.functions.items[main_index], main_table, .record_set, .emptied));
    const width_index = functionIndex(&module, "width");
    const width_table = sink.get(width_index).?;
    // A plain `str` parameter travels as its span and its owner block: two borrowed parameters.
    try std.testing.expectEqual(@as(usize, 2), countWith(&module.functions.items[width_index], width_table, .param, .borrowed));
    try std.testing.expectEqual(@as(usize, 0), width_table.parents(0).len);
}

test "the table covers the instructions the pass analysed and the drops it adds come after it" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var sink: certificate.Sink = .{};
    const module = try kept(arena.allocator(), &sink);
    const index = functionIndex(&module, "main");
    const table = sink.get(index).?;
    const function = &module.functions.items[index];
    try std.testing.expect(table.len < function.insts.items.len);
    try std.testing.expectEqual(ir.Op.drop, function.insts.items[table.len].op);
}
