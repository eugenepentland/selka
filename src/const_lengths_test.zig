//! Constant generic lengths preserve shape identity and runtime integer values.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
fn nominalScenario(allocator: std.mem.Allocator) !void {
    const text =
        \\record Chunk[T, const N: u64]:
        \\    items: [N]T
        \\
        \\
        \\func make[T, const N: u64](items: [N]T) -> Chunk[T, N]:
        \\    return Chunk[T, N](items=items)
        \\
        \\
        \\func first[T, const N: u64](chunk: Chunk[T, N]) -> T:
        \\    return chunk.items[0]
        \\
        \\
        \\func main() -> i64:
        \\    mut a = make[i64, 2](FixedArray[int, 2]([40, 0]))
        \\    mut b = make[i64, 3](FixedArray[int, 3]([2, 0, 0]))
        \\    return first[i64, 2](a) + first[i64, 3](b)
    ;
    var c = try language.Compilation.init(allocator, "lengths.my", text);
    defer c.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&c)).value);
    const formatted = try c.format(allocator);
    defer allocator.free(formatted);
    var again = try language.Compilation.init(allocator, "formatted.my", formatted);
    defer again.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&again)).value);
}
// spec: CONST-LENGTH-1
test "const length nominal parameters compose arrays across a reformat" {
    try nominalScenario(t.allocator);
}
test "uncalled const length templates reject kind confusion unprovable construction and missing requirements" {
    const cases = [_]struct { source: []const u8, code: []const u8 }{
        .{ .source =
        \\func bad[const N: u64](x: N) -> i64:
        \\    return 0
        , .code = "E_GENERIC_LENGTH" },
        .{ .source =
        \\record Bad[const N: u64]:
        \\    x: N
        , .code = "E_GENERIC_LENGTH" },
        .{ .source =
        \\func bad[const N: u64]() -> FixedArray[i64, N]:
        \\    return FixedArray[i64, N]([])
        , .code = "E_GENERIC_LENGTH" },
        .{ .source =
        \\func bad[T, const N: u64](items: [N]T) -> i64:
        \\    return items[0] + 1
        , .code = "E_GENERIC_TYPE" },
        .{ .source =
        \\func bad[const N: u64]() -> u64:
        \\    mut N = 1u64
        \\    return N
        , .code = "E_SHADOWING" },
        .{ .source =
        \\record Bad[T]:
        \\    x: [T]i64
        , .code = "E_GENERIC_ARRAY_KEY" },
        .{ .source =
        \\record Chunk[const N: u64]:
        \\    x: [N]i64
        \\
        \\
        \\record Bad:
        \\    x: Chunk[1048577]
        , .code = "E_GENERIC_LENGTH" },
    };
    for (cases) |case| {
        const text = try std.fmt.allocPrint(t.allocator, "{s}\n\n\nfunc main() -> i64:\n    return 0\n", .{case.source});
        defer t.allocator.free(text);
        var c = try language.Compilation.init(t.allocator, "invalid.my", text);
        defer c.deinit();
        try t.expectError(error.SourceError, c.check());
        try t.expectEqualStrings(case.code, c.diagnostics.items[0].code);
    }
}

test "constant specialization identity owns lengths and distinguishes equal scalar representations" {
    const instances = @import("generic_instances.zig");
    var registry: instances.Registry = .{};
    defer registry.deinit(t.allocator);
    var lengths = [_]?usize{2};
    const first = try registry.intern(t.allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{.u64}, .lengths = &lengths });
    lengths[0] = 3;
    const second = try registry.intern(t.allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{.u64}, .lengths = &lengths });
    const repeated = try registry.intern(t.allocator, .{ .declaration = @fromBackingInt(0), .arguments = &.{.u64}, .lengths = &.{2} });
    try t.expect(first != second);
    try t.expectEqual(first, repeated);
    try t.expectEqual(@as(?usize, 2), (try registry.get(first)).length(0));
}
fn provider(_: ?*anyopaque, allocator: std.mem.Allocator, path: []const u8, _: usize) language.project.ReadError![]u8 {
    if (std.mem.eql(u8, path, "main.my")) return allocator.dupe(u8,
        \\import shapes as s
        \\
        \\
        \\func main() -> i64:
        \\    mut chunk = s.make[i64, 2](FixedArray[int, 2]([42, 0]))
        \\    return chunk.items[0]
    );
    if (std.mem.eql(u8, path, "shapes.my")) return allocator.dupe(u8,
        \\
        \\
        \\public record Chunk[T, const N: u64]:
        \\    items: [N]T
        \\
        \\
        \\public func make[T, const N: u64](items: [N]T) -> Chunk[T, N] effects():
        \\    return Chunk[T, N](items=items)
    );
    return error.NotFound;
}
test "exported constant length constructors retain kind through source relocation" {
    var program: language.embedded_project.Program = undefined;
    try program.init(t.allocator, .{ .context = null, .read = provider });
    defer program.deinit();
    try t.expectEqual(@as(i64, 42), (try native.run(&program.compilation)).value);
}
