//! Managed list generic contracts, recursive nominal layouts, and source formatting.
const std = @import("std");
const t = std.testing;
const debug = std.debug.print;
const language = @import("compiler.zig");
const native = @import("native_execute.zig");

fn evaluate(bytes: []const u8) !void {
    var compilation = try language.Compilation.init(t.allocator, "managed-generic.my", bytes);
    defer compilation.deinit();
    const result = native.run(&compilation) catch |err| {
        for (compilation.diagnostics.items) |diag| debug("{s}: {s} ({s})\n", .{ diag.code, diag.message, compilation.src.text(diag.span) });
        return err;
    };
    try t.expectEqual(@as(i64, 42), result.value);
}
// spec: GC-GENERIC-3
test "managed nominal indirection does not admit recursive by value records" {
    var compilation = try language.Compilation.init(t.allocator, "managed-invalid.my",
        \\class Bad[T]:
        \\    nested: Bad[T]
        \\
        \\
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    try t.expectEqualStrings("E_RECURSIVE_RECORD", compilation.diagnostics.items[0].code);
}

// spec: GC-GENERIC-4
test "managed list formatting preserves contextual list case identifiers" {
    var compilation = try language.Compilation.init(t.allocator, "managed-format.my",
        \\enum Kind:
        \\    list,
        \\    atom
        \\
        \\
        \\def main() -> i64:
        \\    values: List[i64] = []
        \\    values.push(42)
        \\    return values[0]
    );
    defer compilation.deinit();
    const formatted = try compilation.format(t.allocator);
    defer t.allocator.free(formatted);
    try t.expect(std.mem.indexOf(u8, formatted, "[]") != null);
    try evaluate(formatted);
}

// spec: GC-GENERIC-1
test "managed generic list creation mutation and copy identity preserve shared aliases" {
    try evaluate(
        \\def make[T]() -> List[T]:
        \\    items: List[T] = []
        \\    return items
        \\
        \\
        \\def add[T](items: List[T], value: T):
        \\    items.push(value)
        \\
        \\
        \\def identity[T](value: T) -> T:
        \\    return value
        \\
        \\
        \\def main() -> i64:
        \\    values = make[i64]()
        \\    alias = identity(values)
        \\    add[i64](alias, 42)
        \\    return values[0]
    );
}

// spec: GC-GENERIC-2
test "managed nominal recursive list record edges allow finite reference graphs" {
    try evaluate(
        \\class Node[T]:
        \\    value: T
        \\    children: List[Node[T]]
        \\
        \\
        \\def main() -> i64:
        \\    children: List[Node[i64]] = []
        \\    node = Node[i64](value=42, children=children)
        \\    children.push(node)
        \\    child = children[0]
        \\    return child.value
    );
}

// spec: GC-GENERIC-5
test "managed lists reject nested and generic capabilities before helper alias escape" {
    const cases = [_][]const u8{
        \\class Box:
        \\    value: [1]clock_cap
        \\
        \\
        \\def main() -> i64:
        \\    values: List[Box] = []
        \\    return i64(len(values))
        ,
        \\def hold[T](sample: T) -> i64:
        \\    values: List[T] = []
        \\    return i64(len(values))
        \\
        \\
        \\def main(clock: clock_cap) -> i64:
        \\    return hold[clock_cap](clock)
        ,
    };
    for (cases) |bytes| {
        var compilation = try language.Compilation.init(t.allocator, "managed-capability.my", bytes);
        defer compilation.deinit();
        try t.expectError(error.SourceError, compilation.check());
        try t.expectEqualStrings("E_LIST_CAPABILITY", compilation.diagnostics.items[0].code);
    }
}
