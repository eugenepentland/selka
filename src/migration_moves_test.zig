//! Capture-renderer coverage stays outside the production compiler import graph.
const std = @import("std");
const ast = @import("ast.zig");
const source = @import("source.zig");
const moves = @import("migration_moves.zig");

fn capturedExpression(a: std.mem.Allocator, src: source.Source, syntax: ast.Program, expression: []const u8, managed: bool) ![]const u8 {
    for (syntax.nodes.items, 0..) |node, index| {
        if (std.mem.eql(u8, src.text(node.span), expression)) return moves.capture(a, src, syntax, @fromBackingInt(index), managed);
    }
    return error.TestUnexpectedResult;
}

test "O4 generated captures snapshot borrowed reads and preserve fresh and written values" {
    const text =
        // migrate-embedded: skip intentional parse-only capture-renderer original operands
        \\func effect() -> int[]:
        \\    return [1]
        \\func borrowed(values: int[]) -> int[] from values:
        \\    return values
        \\func shapes(own values: int[]):
        \\    _ = values
        \\    _ = values[:]
        \\    _ = values[0]
        \\    _ = borrowed(values)
        \\    _ = remote.effect()
        \\    _ = effect()
        \\    _ = copy(effect())
        \\    _ = own values
        \\    _ = [1]
    ;
    const language = @import("compiler.zig");
    var parsed = try language.Compilation.init(std.testing.allocator, "captures.selka", text);
    defer parsed.deinit();
    try parsed.parse();
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const cases = [_]struct { expression: []const u8, expected: []const u8, managed: bool = true }{
        .{ .expression = "values", .expected = "copy(values)" },
        .{ .expression = "values[:]", .expected = "copy(values[:])" },
        .{ .expression = "values[0]", .expected = "copy(values[0])" },
        .{ .expression = "borrowed(values)", .expected = "copy(borrowed(values))" },
        .{ .expression = "remote.effect()", .expected = "copy(remote.effect())" },
        .{ .expression = "effect()", .expected = "effect()" },
        .{ .expression = "copy(effect())", .expected = "copy(effect())" },
        .{ .expression = "own values", .expected = "own values" },
        .{ .expression = "[1]", .expected = "[1]" },
        .{ .expression = "values", .expected = "values", .managed = false },
    };
    for (cases) |case| try std.testing.expectEqualStrings(case.expected, try capturedExpression(arena.allocator(), parsed.src, parsed.syntax.?, case.expression, case.managed));
}
