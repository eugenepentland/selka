//! Analyze concrete frontend output independently of backend emission.
const std = @import("std");
const compiler = @import("compiler.zig");
const native_ir = @import("native_ir.zig");

fn analyzeSource(allocator: std.mem.Allocator, input: []const u8) !void {
    var compilation = try compiler.Compilation.init(allocator, "native-ir.my", input);
    defer compilation.deinit();
    try compilation.emit();
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    for (compilation.code.?.functions) |function| {
        const result = try native_ir.analyze(arena.allocator(), compilation.code.?, function);
        try std.testing.expect(result.states.len != 0);
        try std.testing.expect(result.stack_capacity != 0);
    }
}

test "native analysis covers concrete record and generic calls" {
    try analyzeSource(std.testing.allocator,
        \\record Box[T]:
        \\    value: T
        \\
        \\
        \\def get[T](x: Box[T]) -> T:
        \\    return x.value
        \\
        \\
        \\def main() -> i64:
        \\    b = Box[i64](value=7)
        \\    return get[i64](b)
    );
}

test "native analysis covers arrays and indexed updates" {
    try analyzeSource(std.testing.allocator,
        \\def main() -> i64:
        \\    a: [3]i64 = [1, 2, 3]
        \\    return a[1]
    );
}

test "native analysis covers text concatenation indexing and ordered dictionaries" {
    try analyzeSource(std.testing.allocator,
        \\def main() -> int:
        \\    text = "é" + "🙂"
        \\    values: dict[str,int] = {"first": 40, "second": 2}
        \\    if text[-1] == "🙂":
        \\        return values["first"] + values["second"]
        \\    return 0
    );
}

test "native analysis rejects a function without an instruction entry" {
    var compilation = try compiler.Compilation.init(std.testing.allocator, "empty.my",
        \\def main() -> i64:
        \\    return 0
    );
    defer compilation.deinit();
    try compilation.emit();
    var function = compilation.code.?.functions[0];
    function.scope.instructions = &.{};
    try std.testing.expectError(error.UnsupportedOperation, native_ir.analyze(std.testing.allocator, compilation.code.?, function));
}
