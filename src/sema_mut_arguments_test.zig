//! Transparent mutation markers consume their resolved target once.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

const nested_dictionary =
    \\def clone_during(target: mut dict[int,int], source: dict[int,dict[int,int]]) -> dict[int,dict[int,int]]:
    \\    target[1] = target[1]
    \\    return source.copy()
    \\
    \\def main(out: Stream) -> int:
    \\    original = {0:{1:7}}
    \\    copied = clone_during(mut original[0], original)
    \\    live = copied[0].values()
    \\    copied[0][1] = 13
    \\    out.print(list(live))
    \\    out.print(copied[0][1])
    \\    out.print(original[0][1])
    \\    return 0
;

// spec: MUT-EXPRESSION-STACK-1
test "mut expression stack accepts a dictionary element before its containing value" {
    var compilation = try language.Compilation.init(t.allocator, "mut-dictionary.my", nested_dictionary);
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

fn rejected(allocator: std.mem.Allocator, argument: []const u8, expected: []const u8) !void {
    const bytes = try std.fmt.allocPrint(allocator, "def touch(value: mut dict[int,int]) -> None:\n    value[1] = 2\n\ndef main() -> int:\n    values = {{0:{{1:7}}}}\n    touch({s})\n    return 0\n", .{argument});
    defer allocator.free(bytes);
    var compilation = try language.Compilation.init(allocator, "mut-diagnostic.my", bytes);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_MUTATION_MARKER", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, expected) != null);
}

// spec-case: MUT-EXPRESSION-STACK-1
test "mut expression stack preserves missing marker and nonassignable target diagnostics" {
    try rejected(t.allocator, "values[0]", "write `(mut values[0])`");
    try rejected(t.allocator, "mut {1:7}", "requires an assignable argument");
}
