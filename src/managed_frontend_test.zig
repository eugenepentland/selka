//! Managed list generic contracts, recursive nominal layouts, and source formatting.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn evaluate(bytes: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "managed-generic.selka", bytes);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}
// spec: GC-GENERIC-3
test "managed nominal indirection does not admit recursive by value records" {
    var compilation = try language.Compilation.init(t.allocator, "managed-invalid.selka",
        \\record Bad[T]:
        \\    nested: Bad[T]
        \\
        \\
        \\func main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_RECURSIVE_RECORD", compilation.diagnostics.items[0].code);
}

// spec: GC-GENERIC-4
test "managed list formatting preserves contextual list case identifiers" {
    var compilation = try language.Compilation.init(t.allocator, "managed-format.selka",
        \\enum Kind:
        \\    list
        \\    atom
        \\
        \\
        \\func main() -> i64:
        \\    mut values: i64[] = []
        \\    values.append(42)
        \\    return values[0]
    );
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "[]") != null);
    try evaluate(formatted);
}

// spec: GC-GENERIC-5
test "managed lists reject nested and generic capabilities before helper alias escape" {
    const cases = [_][]const u8{
        \\record Box:
        \\    value: FixedArray[Clock, 1]
        \\
        \\
        \\func main() -> i64:
        \\    mut values: Box[] = []
        \\    return i64(len(values))
        ,
        \\func hold[T](sample: T) -> i64:
        \\    mut values: T[] = []
        \\    return i64(len(values))
        \\
        \\
        \\func main(clock: Clock) -> i64:
        \\    return hold[Clock](clock)
        ,
    };
    for (cases) |bytes| {
        var compilation = try language.Compilation.init(t.allocator, "managed-capability.selka", bytes);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_LIST_CAPABILITY", compilation.diagnostics.items[0].code);
    }
}
