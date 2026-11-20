//! Recursive live-view storage admission preserves D9's acyclic value heap.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const cycles = @import("view_cycles.zig");
const fixture = @import("stdlib_fixture.zig");
const direct =
    \\record Entry:
    \\    view: DictValues[int, Entry]
    \\
    \\func main() -> int:
    \\    mut mapping: dict[int, Entry] = {}
    \\    mut live = mapping.values()
    \\    mapping[0] = Entry(view=live)
    \\    return 0
;
fn rejected(text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "view-cycle.selka", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_VIEW_STORED", c.diagnostics.items[0].code);
    try t.expect(c.diagnostics.items[0].span.end > c.diagnostics.items[0].span.start);
}
fn accepted(text: []const u8) !void {
    // Checked as a project, so a program may `import` a standard module (`dicts`).
    var program: language.embedded_project.Program = undefined;
    try fixture.load(&program, t.allocator, text);
    defer program.deinit();
    try t.expect(program.compilation.program != null);
}
// spec-case: D2-VIEW-STORAGE-1
test "D2 declarations reject direct mutual and generic view cycles" {
    try rejected(direct);
    try rejected(
        \\record First:
        \\    entries: Second[]
        \\record Second:
        \\    view: DictKeys[int, First]
        \\func main() -> int:
        \\    return 0
    );
    try rejected(
        \\record Wrapper[T]:
        \\    value: T
        \\record Entry:
        \\    value: Wrapper[DictItems[int, Entry]]
        \\func main() -> int:
        \\    return 0
    );
    try rejected(
        \\enum Link:
        \\    end
        \\    more(value: Entry)
        \\record Entry:
        \\    views: FixedArray[DictValues[int, Link], 2]
        \\func main() -> int:
        \\    return 0
    );
}
// spec-case: LIVE-VIEW-ACYCLIC-1
test "live view cycle admission keeps ordinary views snapshots and recursion" {
    try accepted(
        \\import dicts
        \\
        \\record Node:
        \\    children: Node[]
        \\    next: Node?
        \\record Saved:
        \\    view: int[]
        \\func retain(mapping: dict[int, int]) -> Saved:
        \\    return Saved(view=list(dicts.values(mapping)))
        \\func main() -> int:
        \\    mut mapping = {1: 4}
        \\    mut snapshot = copy(mapping)
        \\    mut retained = retain(snapshot)
        \\    mapping[1] = 7
        \\    mut node = Node(children=[], next=None)
        \\    return len(retained.view) + len(node.children)
    );
    try accepted(
        \\import dicts
        \\
        \\record Entry:
        \\    values: Entry[]
        \\func main() -> int:
        \\    mut mapping: dict[int, Entry] = {}
        \\    mapping[0] = Entry(values=list(dicts.values(mapping)))
        \\    return len(mapping)
    );
}
// spec-case: D2-VIEW-STORAGE-1
test "D2 rejects phantom and empty array view annotations but permits user names" {
    try rejected(
        \\record Phantom[T]:
        \\    pass
        \\record Entry:
        \\    marker: Phantom[DictValues[int, Entry]]
        \\    empty: FixedArray[DictValues[int, Entry], 0]
        \\func main() -> int:
        \\    return 0
    );
    try accepted(
        \\record DictValues[K, V]:
        \\    values: V[]
        \\record Entry:
        \\    nested: DictValues[int, Entry]
        \\func main() -> int:
        \\    return 0
    );
}

fn graphRejection(allocator: std.mem.Allocator, records: []typed.Record) !void {
    var sink: diagnostic.Sink = .{ .allocator = allocator };
    defer sink.deinit();
    _ = cycles.validateFrom(allocator, records, 0, &sink) catch |err| {
        if (err != error.SourceError) return err;
        try t.expectEqualStrings("E_LIVE_VIEW_CYCLE", sink.items.items[0].code);
        return;
    };
    return error.TestExpectedError;
}
// spec: LIVE-VIEW-ACYCLIC-1
test "live view cycle admission visits deep stored graphs and rolls back allocation refusal" {
    const count = 32768;
    const records = try t.allocator.alloc(typed.Record, count);
    defer t.allocator.free(records);
    const mapping: typed.Field = .{ .name = "mapping", .ty = @fromBackingInt(@intCast(typed.Type.record_base + 1)), .declaration = .{ .start = 1, .end = 2 } };
    for (records, 0..) |*record, i| record.* = .{
        .id = @fromBackingInt(@intCast(typed.Type.record_base + i)),
        .name = "stored",
        .declaration = .{ .start = 1, .end = 2 },
        .fields = if (i == 0) &.{mapping} else &.{},
        .managed = i != 0,
        .shape = if (i == 0) .{ .builtin = .live_view } else .{ .buffer = @fromBackingInt(@intCast(typed.Type.record_base + (i + 1) % count)) },
    };
    try graphRejection(t.allocator, records);
    try t.checkAllAllocationFailures(t.allocator, graphRejection, .{records});
    records[count - 1].shape.buffer = .i64;
    var sink: diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    _ = try cycles.validateFrom(t.allocator, records, 0, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}

/// A plain record `index` with no fields, for the late-batch checks below.
fn plainRecord(index: usize) typed.Record {
    return .{ .id = @fromBackingInt(@intCast(typed.Type.record_base + index)), .name = "plain", .declaration = .{ .start = 1, .end = 2 }, .fields = &.{} };
}

/// Set `records[from..to]` to plain records numbered from `from`.
fn fillPlain(records: []typed.Record, from: usize, to: usize) void {
    for (records[from..to], from..) |*record, index| record.* = plainRecord(index);
}

// spec: LIVE-VIEW-ACYCLIC-1
test "a live view cycle through a late record is found as a whole-catalog check finds it" {
    const settled = 3;
    var buffer: [settled + 2]typed.Record = undefined;
    fillPlain(&buffer, 0, settled);
    const view_field = [_]typed.Field{.{ .name = "mapping", .ty = @fromBackingInt(@intCast(typed.Type.record_base + settled + 1)), .declaration = .{ .start = 5, .end = 6 } }};
    buffer[settled] = .{ .id = @fromBackingInt(@intCast(typed.Type.record_base + settled)), .name = "view", .declaration = .{ .start = 7, .end = 8 }, .fields = &view_field, .shape = .{ .builtin = .live_view } };
    buffer[settled + 1] = .{
        .id = @fromBackingInt(@intCast(typed.Type.record_base + settled + 1)),
        .name = "stored",
        .declaration = .{ .start = 9, .end = 10 },
        .managed = true,
        .fields = &.{},
        .shape = .{ .buffer = @fromBackingInt(@intCast(typed.Type.record_base + settled)) },
    };
    var late: diagnostic.Sink = .{ .allocator = t.allocator };
    defer late.deinit();
    _ = try cycles.validateFrom(t.allocator, buffer[0..settled], 0, &late);
    try t.expectError(error.SourceError, cycles.validateFrom(t.allocator, &buffer, settled, &late));
    var whole: diagnostic.Sink = .{ .allocator = t.allocator };
    defer whole.deinit();
    try t.expectError(error.SourceError, cycles.validateFrom(t.allocator, &buffer, 0, &whole));
    try t.expectEqualStrings("E_LIVE_VIEW_CYCLE", late.items.items[0].code);
    try t.expectEqualStrings(whole.items.items[0].code, late.items.items[0].code);
    try t.expectEqual(whole.items.items[0].span.start, late.items.items[0].span.start);
    try t.expectEqual(whole.items.items[0].span.end, late.items.items[0].span.end);
}

test "a late batch searches only its own records and finds no cycle without a live view" {
    const settled = 2000;
    const added = 6;
    const buffer = try t.allocator.alloc(typed.Record, settled + added);
    defer t.allocator.free(buffer);
    fillPlain(buffer, 0, settled);
    var sink: diagnostic.Sink = .{ .allocator = t.allocator };
    defer sink.deinit();
    // No live view anywhere: nothing is searched, however many records there are.
    try t.expectEqual(@as(usize, 0), try cycles.validateFrom(t.allocator, buffer[0..settled], 0, &sink));
    fillPlain(buffer, settled, settled + added);
    try t.expectEqual(@as(usize, 0), try cycles.validateFrom(t.allocator, buffer, settled, &sink));
    // A late live view whose target is settled cannot close a cycle: it is searched, and only its batch counts.
    const settled_target = [_]typed.Field{.{ .name = "mapping", .ty = @fromBackingInt(@intCast(typed.Type.record_base)), .declaration = .{ .start = 5, .end = 6 } }};
    buffer[settled + 1] = .{ .id = @fromBackingInt(@intCast(typed.Type.record_base + settled + 1)), .name = "view", .declaration = .{ .start = 7, .end = 8 }, .fields = &settled_target, .shape = .{ .builtin = .live_view } };
    try t.expectEqual(@as(usize, added), try cycles.validateFrom(t.allocator, buffer, settled, &sink));
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
