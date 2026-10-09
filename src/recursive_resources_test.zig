//! Immutable recursive boxes obey the same resource contract for builtin files.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

fn rejected(allocator: std.mem.Allocator, fields: []const u8) !void {
    const source = try std.fmt.allocPrint(allocator, "record Owner:\n{s}\n    next: Owner?\n\nfunc main() -> int:\n    return 0\n", .{fields});
    defer allocator.free(source);
    try rejectedSource(allocator, source);
}

fn rejectedSource(allocator: std.mem.Allocator, source: []const u8) !void {
    var compilation = try language.Compilation.init(allocator, "recursive-resource.selka", source);
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
        \\    next: Owner?
        \\
        \\record Envelope[T]:
        \\    value: T
        \\
        \\func main() -> int:
        \\    return 0
    );
}

// spec-case: RECURSIVE-FILE-CONTRACT-1
test "recursive file contracts preserve acyclic records and fallible file returns" {
    var compilation = try language.Compilation.init(t.allocator, "legal-file.selka",
        \\record Owner:
        \\    file: TextFile
        \\
        \\func opened(fs: Filesystem) -> Result[Owner, str]:
        \\    const file = try fs.open("data", "w")
        \\    return Ok(Owner(file=file))
        \\
        \\func main() -> int:
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
    try rejected(t.allocator, "    files: FixedArray[TextFile, 1]");
    try rejected(t.allocator, "    file: tuple[int, TextFile]");
}

// spec-case: RECURSIVE-FILE-CONTRACT-1
test "recursive file contracts preserve zero length resource arrays" {
    var compilation = try language.Compilation.init(t.allocator, "empty-resource.selka",
        \\record Node:
        \\    files: FixedArray[TextFile, 0]
        \\    next: Node?
        \\
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.check();
    try t.expectEqual(@as(usize, 0), compilation.diagnostics.items.len);
}

// spec-case: RECURSIVE-FILE-CONTRACT-1
test "with owned file handles remain scoped when ordinary acquired handles can transfer" {
    var compilation = try language.Compilation.init(t.allocator, "scoped-file.selka",
        \\record Owner:
        \\    file: TextFile
        \\func opened(fs: Filesystem) -> Result[Owner, str]:
        \\    with fs.open("data", "w") as file:
        \\        return Ok(Owner(file=file))
        \\func main() -> int:
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_WITH_RESOURCE", compilation.diagnostics.items[0].code);
}
