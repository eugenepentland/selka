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
    try t.expectEqual(language.ownership_rules.Rule.T4, compilation.diagnostics.items[0].provenance.rule.?);
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
test "Core file storage refuses acyclic fields and preserves fallible file returns" {
    const source =
        \\record Owner:
        \\    file: TextFile
        \\
        \\func opened(fs: Filesystem) -> Owner fails str:
        \\    const file = try fs.open("data", "w")
        \\    return Owner(file=file)
        \\
        \\func main() -> int:
        \\    return 0
    ;
    // The record that stores the file is refused where it is declared (P4), not only when a local has its type.
    var compilation = try language.Compilation.init(t.allocator, "legal-file.selka", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_WITH_RESOURCE", compilation.diagnostics.items[0].code);
    var fallible = try language.Compilation.init(t.allocator, "fallible-file.selka",
        \\func opened(fs: Filesystem) -> TextFile fails str:
        \\    return try fs.open("data", "w")
        \\func main() -> int:
        \\    return 0
    );
    defer fallible.deinit();
    try fallible.check();
    try t.expect(fallible.program != null);
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
    const source =
        \\record Owner:
        \\    file: TextFile
        \\func opened(fs: Filesystem) -> Owner fails str:
        \\    with fs.open("data", "w") as file:
        \\        return Owner(file=file)
        \\func main() -> int:
        \\    return 0
    ;
    var compilation = try language.Compilation.init(t.allocator, "scoped-file.selka", source);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_WITH_RESOURCE", compilation.diagnostics.items[0].code);
}
