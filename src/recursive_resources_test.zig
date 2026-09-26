//! Immutable recursive boxes obey the same resource contract for builtin files.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn rejected(allocator: std.mem.Allocator, fields: []const u8) !void {
    const source = try std.fmt.allocPrint(allocator, "record Owner:\n{s}\n    next: Option[Owner]\n\ndef main() -> int:\n    return 0\n", .{fields});
    defer allocator.free(source);
    try rejectedSource(allocator, source);
}

fn rejectedSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "recursive-resource.my", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_RECURSIVE_RECORD", compilation.diagnostics.items[0].code);
    try t.expect(std.mem.indexOf(u8, compilation.diagnostics.items[0].message, "owned resource") != null);
}

// spec-case: RECURSIVE-FILE-CONTRACT-1
test "recursive file contracts follow later declared generic wrappers" {
    try rejectedSource(t.allocator,
        \\record Owner:
        \\    file: Envelope[TextFile]
        \\    next: Option[Owner]
        \\
        \\record Envelope[T]:
        \\    value: T
        \\
        \\def main() -> int:
        \\    return 0
    );
}

// spec-case: RECURSIVE-FILE-CONTRACT-1
test "recursive file contracts preserve acyclic records and fallible file returns" {
    var compilation = try language.Compilation.init(t.allocator, "legal-file.my",
        \\record Owner:
        \\    file: TextFile
        \\
        \\def opened(fs: Filesystem) -> Result[Owner, str]:
        \\    return Ok(Owner(fs.open("data", "w")?))
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

// spec: RECURSIVE-FILE-CONTRACT-1
test "recursive file contracts reject primitive resources through stored fields" {
    try rejected(t.allocator, "    file: File");
    try rejected(t.allocator, "    file: TextFile");
    try rejected(t.allocator, "    files: [1]TextFile");
    try rejected(t.allocator, "    file: tuple[int, TextFile]");
}

// spec-case: RECURSIVE-FILE-CONTRACT-1
test "recursive file contracts preserve zero length resource arrays" {
    var compilation = try language.Compilation.init(t.allocator, "empty-resource.my",
        \\record Node:
        \\    files: [0]TextFile
        \\    next: Option[Node]
        \\
        \\def main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}
