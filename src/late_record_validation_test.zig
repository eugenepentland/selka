//! Records interned after collection, through a generic instance a body uses, keep
//! the layout and ownership diagnostics that a whole-catalog check gives them.
const std = @import("std");
const t = std.testing;
const language = @import("compiler.zig");

/// Check `text`, which must be refused with `code` at a diagnostic spanning `start..end`.
fn expectRefused(name: []const u8, text: []const u8, code: []const u8, start: usize, end: usize) !void {
    var compilation = try language.Compilation.init(t.allocator, name, text);
    defer compilation.deinit();
    try t.expectError(error.SourceError, compilation.check());
    const first = compilation.diagnostics.items[0];
    try t.expectEqualStrings(code, first.code);
    try t.expectEqual(start, first.span.start);
    try t.expectEqual(end, first.span.end);
}

test "a late generic record cycle is refused by layout where the instance is built" {
    try expectRefused("late-layout.selka",
        \\record A[T]:
        \\    b: B[T]
        \\
        \\record B[T]:
        \\    a: A[T]
        \\
        \\func main() -> int:
        \\    mut values: A[int][] = []
        \\    return len(values)
        \\
    , "E_RECURSIVE_RECORD", 43, 44);
}

test "a late list of a boxed holder of a capability (5C) is accepted as an ordinary list" {
    var compilation = try language.Compilation.init(t.allocator, "late-capability-list.selka",
        \\record Chain[T]:
        \\    head: T
        \\    tail: Chain[T]?
        \\
        \\func main() -> int:
        \\    mut values: Chain[Clock][] = []
        \\    return len(values)
        \\
    );
    defer compilation.deinit();
    try compilation.check();
}

test "a late boxed holder of a file is refused by its file carrier" {
    try expectRefused("late-file-box.selka",
        \\record Chain[T]:
        \\    head: T
        \\    tail: Chain[T]?
        \\
        \\func main() -> int:
        \\    mut values: Chain[File][] = []
        \\    return len(values)
        \\
    , "E_RECURSIVE_RECORD", 0, 0);
}

test "a late boxed holder of a capability reached through a generic specialization (5C) checks" {
    var compilation = try language.Compilation.init(t.allocator, "late-capability-box.selka",
        \\record Chain[T]:
        \\    head: T
        \\    tail: Chain[T]?
        \\
        \\func hold[T](sample: T) -> int:
        \\    mut values: Chain[T][] = []
        \\    append(mut values, Chain[T](head=sample, tail=None))
        \\    return len(values)
        \\
        \\func main(clock: Clock) -> int:
        \\    return hold[Clock](clock)
        \\
    );
    defer compilation.deinit();
    try compilation.check();
}

test "a late boxed holder of plain values still checks" {
    var compilation = try language.Compilation.init(t.allocator, "late-plain-box.selka",
        \\record Chain[T]:
        \\    head: T
        \\    tail: Chain[T]?
        \\
        \\func main() -> int:
        \\    mut values: Chain[int][] = []
        \\    return len(values)
        \\
    );
    defer compilation.deinit();
    try compilation.check();
}
