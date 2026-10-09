//! Python string methods: trimming, case, search, classification and parsing.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");
const values = @import("runtime_values.zig");

const text_type: values.Type = @fromBackingInt(@intCast(32));
const list_type: values.Type = @fromBackingInt(@intCast(33));

fn reject(source: []const u8, code: []const u8) !void {
    var c = try language.Compilation.init(t.allocator, "strings.selka", source);
    defer c.deinit();
    try t.expectError(error.SourceError, c.check());
    try t.expectEqualStrings(code, c.diagnostics.items[0].code);
}

// spec-case: PY-STR-2
test "string methods are rejected on lists and empty split separators trap" {
    try reject(
        \\func main() -> int:
        \\    mut values = [1, 2]
        \\    _ = values.strip()
        \\    return 0
    , "E_COLLECTION_METHOD");
    try reject(
        \\func main() -> int:
        \\    mut counts: dict[str, int] = {}
        \\    _ = counts.upper()
        \\    return 0
    , "E_COLLECTION_METHOD");
    var c = try language.Compilation.init(t.allocator, "strings.selka", "func main() -> int:\n    return len(\"ab\".split(\"\"))\n");
    defer c.deinit();
    const result = try native.run(&c);
    try t.expect(result.trapped());
    try t.expectEqualStrings("R_EMPTY_SEPARATOR", result.trap.code);
}
