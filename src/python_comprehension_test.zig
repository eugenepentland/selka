//! List comprehensions build a fresh list through one checked loop.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "comprehension.my", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec: PY-COMPREHENSION-2
test "comprehensions reject shadowing, non-Boolean filters and uniterable sources" {
    try reject(
        \\def main() -> int:
        \\    value = 1
        \\    _ = [value for value in [1, 2]]
        \\    return 0
    , "E_SHADOWING");
    try reject(
        \\def main() -> int:
        \\    _ = [x for x in [1, 2] if x]
        \\    return 0
    , "E_TYPE");
    try reject(
        \\def main() -> int:
        \\    _ = [x for x in 3]
        \\    return 0
    , "E_COLLECTION_METHOD");
}
