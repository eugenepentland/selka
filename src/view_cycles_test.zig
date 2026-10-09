//! Recursive live-view storage admission preserves D9's acyclic value heap.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const typed = @import("typed.zig");
const diagnostic = @import("diagnostic.zig");
const cycles = @import("view_cycles.zig");
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
    var c = try language.Compilation.init(t.allocator, "view-cycle.my", text);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings("E_VIEW_STORED", c.diagnostics.items[0].code);
    try t.expect(c.diagnostics.items[0].span.end > c.diagnostics.items[0].span.start);
}
fn accepted(text: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "view-safe.my", text);
    defer c.deinit();
    try c.check();
    try t.expect(c.program != null);
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
        \\record Node:
        \\    children: Node[]
        \\    next: Node?
        \\record Saved:
        \\    view: int[]
        \\func retain(mapping: dict[int, int]) -> Saved:
        \\    return Saved(view=list(mapping.values()))
        \\func main() -> int:
        \\    mut mapping = {1: 4}
        \\    mut snapshot = mapping
        \\    mut retained = retain(snapshot)
        \\    mapping[1] = 7
        \\    mut node = Node(children=[], next=None)
        \\    return len(retained.view) + len(node.children)
    );
    try accepted(
        \\record Entry:
        \\    values: Entry[]
        \\func main() -> int:
        \\    mut mapping: dict[int, Entry] = {}
        \\    mapping[0] = Entry(values=list(mapping.values()))
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
    cycles.validate(allocator, .{ .records = records, .names = .empty }, &sink) catch |err| {
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
    try cycles.validate(t.allocator, .{ .records = records, .names = .empty }, &sink);
    try t.expectEqual(@as(usize, 0), sink.items.items.len);
}
