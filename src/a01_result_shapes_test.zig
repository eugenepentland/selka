//! Recursive generic list shapes never cache incomplete Result obligations.
const std = @import("std");
const language = @import("compiler.zig");
const shapes = @import("symbolic_shapes.zig");
const source =
    \\record First[T: storable]:
    \\    children: Second[T][]
    \\    pending: Result[int, int]
    \\record Second[T: storable]:
    \\    children: First[T][]
;

// spec-case: NEW-CORE-ZERO-RC-RESULT-LISTS-1
test "A01 recursive generic Result list obligations do not memoize incomplete cycle prefixes" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var unit = try language.Compilation.init(a, "recursive-results.my", source);
    defer unit.deinit();
    try unit.parse();
    var sink: language.diagnostic.Sink = .{ .allocator = a };
    const catalog = try @import("records.zig").collectWithNames(a, unit.src, unit.syntax.?, &sink, null);
    const cleanup = try a.alloc(@import("effect_set.zig").Mask, catalog.records.len);
    @memset(cleanup, 0);
    var work: usize = 0;
    const context: shapes.Context = .{
        .arena = &arena,
        .catalog = catalog,
        .src = unit.src,
        .sink = &sink,
        .parameters = &.{.{ .name = .{ .start = 0, .end = 0 }, .requirements = .{ .bits = 16 } }},
        .contracts = .{ .cleanup = cleanup },
        .work = &work,
    };
    const at: language.source.Span = .{ .start = 0, .end = 0 };
    const first = try context.nominal(catalog.templates.store.?.index.names.get("First").?, &.{.{ .parameter = 0 }});
    try std.testing.expect((try context.properties(first, at)).requires_handling);
    const members = try context.schema(first, at);
    const children = members.fields[0].ty.?;
    const second = children.nominal.arguments[0];
    for (0..64) |_| {
        try std.testing.expect((try context.properties(second, at)).requires_handling);
        try std.testing.expect((try context.properties(children, at)).requires_handling);
        try std.testing.expect((try context.properties(first, at)).requires_handling);
    }
    try std.testing.expect(work < 100000);
}
