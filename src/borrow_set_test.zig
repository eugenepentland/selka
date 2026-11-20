//! Return origins come from declarations, independently of checked bodies.
const std = @import("std");
const language = @import("compiler.zig");
const return_borrow = @import("return_borrow.zig");
const t = std.testing;

fn frontEnd(a: std.mem.Allocator, source: []const u8) !language.typed.Program {
    const text = try std.mem.concat(a, u8, &.{ source, "\n\nfunc main() -> int:\n    return 0\n" });
    var unit = try language.Compilation.init(a, "declared-borrow.selka", text);
    try unit.checkWithFrontend(null);
    return unit.program.?;
}

fn sourcesOf(program: language.typed.Program, name: []const u8) ![]const u16 {
    for (program.functions) |function| {
        if (std.mem.eql(u8, function.name, name)) return return_borrow.sources(function.signature);
        if (std.mem.endsWith(u8, function.name, name) and function.name.len > name.len and function.name[function.name.len - name.len - 1] == ':') return return_borrow.sources(function.signature);
    }
    return error.TestUnexpectedResult;
}

test "declared borrows normalize all source positions independently of body use" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const program = try frontEnd(arena.allocator(),
        \\func pick(a: str, b: str, c: str) -> str from c, a, b:
        \\    return a
    );
    try t.expectEqualSlices(u16, &.{ 0, 1, 2 }, try sourcesOf(program, "pick"));
}

test "declared borrows are never inferred from an unannotated return" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const program = try frontEnd(arena.allocator(),
        // migrate-embedded: skip frontend-only absent-from contract observation must retain an empty declared source set
        \\func part(s: str) -> str:
        \\    return s[1:3]
    );
    try t.expectEqualSlices(u16, &.{}, try sourcesOf(program, "part"));
}

test "declared borrows survive ensures and standard optional results" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const program = try frontEnd(arena.allocator(),
        \\@ensures(len(result) >= 0)
        \\func head(s: str) -> str from s:
        \\    return s[0:2]
        \\
        \\func maybe(s: str, flag: bool) -> str? from s:
        \\    if flag:
        \\        return Some(s)
        \\    return None
    );
    try t.expectEqualSlices(u16, &.{0}, try sourcesOf(program, "head"));
    try t.expectEqualSlices(u16, &.{0}, try sourcesOf(program, "maybe"));
}

test "declared borrows do not require a recursive summary fixed point" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const program = try frontEnd(arena.allocator(),
        \\func loop_a(value: str, n: int) -> str from value:
        \\    if n == 0:
        \\        return value
        \\    return loop_b(value, n - 1)
        \\
        \\func loop_b(value: str, n: int) -> str from value:
        \\    return loop_a(value, n)
    );
    try t.expectEqualSlices(u16, &.{0}, try sourcesOf(program, "loop_a"));
    try t.expectEqualSlices(u16, &.{0}, try sourcesOf(program, "loop_b"));
}

test "declared borrows keep source positions above 63" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var text: std.Io.Writer.Allocating = .init(a);
    try text.writer.writeAll("func last(");
    for (0..130) |position| {
        if (position != 0) try text.writer.writeAll(", ");
        try text.writer.print("p{d}: str", .{position});
    }
    try text.writer.writeAll(") -> str from p129, p64, p0:\n    return p129\n");
    const program = try frontEnd(a, text.written());
    try t.expectEqualSlices(u16, &.{ 0, 64, 129 }, try sourcesOf(program, "last"));
}

test "declared contracts keep unused mut positions and govern forwarded calls" {
    var arena = std.heap.ArenaAllocator.init(t.allocator);
    defer arena.deinit();
    const program = try frontEnd(arena.allocator(),
        \\func unused(mut values: int[]) -> int:
        \\    return len(values)
        \\
        \\func written(mut values: int[]) -> int:
        \\    append(mut values, 1)
        \\    return len(values)
        \\
        \\func forward(mut values: int[]) -> int:
        \\    return unused(mut values)
    );
    for (program.functions[0..3]) |function| try t.expectEqualSlices(u16, &.{0}, function.signature.mutates);
    try t.expect(!program.functions[0].signature.inferred.writes);
    try t.expect(program.functions[1].signature.inferred.writes);
    // Forwarding honors the callee's promise even though its current body does no write.
    try t.expect(program.functions[2].signature.inferred.writes);
}
